-- voo.lua : piloto automatico ate a orbita (Create Cosmonautics + CC: Sable)
-- Uso: voo          -> checagem, espera o botao (ou retoma um voo em andamento)
--      voo teste    -> checagem completa + teste de gimbal, sem acender nada
--      voo reset    -> apaga o estado salvo (novo voo)
--      voo descer [Y]  -> deorbit (se no espaco) e pouso; Y = altura do chao, se souber
--      voo rcs      -> calibra os RCS (nave solta no ar/espaco) e testa por 15 s
-- Registros: um arquivo por voo em /logs, com data e hora no nome (use o programa 'logs')

local args = { ... }
local DIR = fs.getDir(shell.getRunningProgram())
local function path(p) return fs.combine(DIR, p) end
local L = dofile(path("log.lua"))
local STATE_FILE = path("estado.txt")

if not fs.exists(path("config.lua")) then
  printError("Rode 'setup' primeiro.") return
end
local CFG = dofile(path("config.lua"))
for _, st in ipairs(CFG.stages or {}) do
  local seen, list = {}, {}
  for _, n in ipairs(st.engines or {}) do
    if not seen[n] then seen[n] = true list[#list + 1] = n end
  end
  st.engines = list
end

if args[1] == "reset" then
  -- registra no log do voo que esta sendo apagado
  if fs.exists(STATE_FILE) then
    local h = fs.open(STATE_FILE, "r") local t = textutils.unserialize(h.readAll()) h.close()
    if type(t) == "table" and t.logFile and fs.exists(t.logFile) then
      L.useFile(t.logFile)
      L.info("Estado apagado (voo reset)")
    end
  end
  fs.delete(STATE_FILE) print("Estado apagado. O proximo voo vai gravar num log novo.") return
end

---------------------------------------------------------------- matematica
local V = vector.new
local UP = V(0, 1, 0)
local EAST = V(CFG.east[1], CFG.east[2], CFG.east[3]):normalize()

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- nomes dos perifericos sem repeticao (com 2 modems na mesma rede o CC lista cada um 2 vezes)
local function periNames()
  local seen, out = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if not seen[n] then seen[n] = true out[#out + 1] = n end
  end
  return out
end

local function qrot(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return V(v.x + qw * tx + (qy * tz - qz * ty),
           v.y + qw * ty + (qz * tx - qx * tz),
           v.z + qw * tz + (qx * ty - qy * tx))
end
local function toLocal(q, v) return qrot({ -q[1], -q[2], -q[3], q[4] }, v) end

local function quatParts(o)
  if o.v then return { o.v.x, o.v.y, o.v.z, o.a } end
  return { o.x, o.y, o.z, o.w }
end

---------------------------------------------------------------- nave
-- as 4 leituras em paralelo: cada uma pode custar 1 tick se feita em sequencia
local function readShip()
  local pose, vel, angv, mass
  parallel.waitForAll(
    function() pose = sublevel.getLogicalPose() end,
    function() vel = sublevel.getVelocity() end,
    function() angv = sublevel.getAngularVelocity() end,
    function() mass = sublevel.getMass() end)
  return {
    pos = pose.position,
    q = quatParts(pose.orientation),
    vel = vel,
    angv = angv,
    mass = mass,
  }
end

local function gravity()
  local ok, g = pcall(aero.getGravity)
  if ok and g and g:length() > 0.01 then return g:length() end
  return 9.81
end

---------------------------------------------------------------- estado
local S = { phase = "PAD", stage = 1 }
local function save()
  local f = fs.open(STATE_FILE, "w") f.write(textutils.serialize(S)) f.close()
end
local function load()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r") local t = textutils.unserialize(f.readAll()) f.close()
  if t then S = t end
end
local function setPhase(p, why)
  L.info("FASE %s -> %s (%s)", S.phase, p, why)
  S.phase = p
  save()
end

---------------------------------------------------------------- perifericos
local function call(name, fn, ...)
  if not peripheral.isPresent(name) then
    L.err("periferico %s ausente (ao chamar %s)", name, fn)
    return nil
  end
  local ok, r = pcall(peripheral.call, name, fn, ...)
  if not ok then
    L.err("%s.%s falhou: %s", name, fn, tostring(r))
    return nil
  end
  return r
end

local engineType = {}
local function typeOf(name)
  if not engineType[name] then
    local d = call(name, "getData")
    engineType[name] = d and d.engine_type or "?"
  end
  return engineType[name]
end

local function short(name) return (name:gsub("rocketnautics:", "")) end

local function stageEngines(i)
  local st = CFG.stages[i]
  return st and st.engines or {}
end

local function allEngines()
  local t = {}
  for _, st in ipairs(CFG.stages) do
    for _, n in ipairs(st.engines) do table.insert(t, n) end
  end
  return t
end

-- uma linha com o estado completo do motor
local function engineLine(name)
  local d = call(name, "getData")
  if not d then return short(name) .. " AUSENTE" end
  local s
  if d.engine_type == "booster_thruster" then
    s = ("aceso=%s gasto=%s carvao_ticks=%s potencia=%s"):format(
      tostring(d.ignited), tostring(d.is_spent), tostring(d.fuel_ticks), tostring(d.thrust_power))
  else
    s = ("ativo=%s lava=%s/%s fluxo=%s acel=%s aquec=%s/%s"):format(
      tostring(d.active), tostring(d.fuel_amount), tostring(d.fuel_capacity), tostring(d.fuel_usage),
      tostring(d.throttle), tostring(d.ignition_ticks), tostring(d.warmup_time))
  end
  return ("%s [%s] %s empuxo=%s"):format(short(name), tostring(d.engine_type), s,
    tostring(call(name, "getThrust")))
end

local function logEngines(tag)
  local names, lines, fns = allEngines(), {}, {}
  for k, n in ipairs(names) do
    fns[k] = function() lines[k] = engineLine(n) end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  for k = 1, #names do L.info("MOTOR %s %s", tag, lines[k] or "?") end
end

-- cada chamada de periferico custa 1 tick: evite chamadas repetidas
local lastThrottleN = {}
local function setThrottle(i, frac)
  local n = math.floor(clamp(frac, 0, 1) * CFG.max_thrust_n)
  n = math.floor(n / 50) * 50
  if lastThrottleN[i] == n then return end -- so chama o periferico quando muda
  lastThrottleN[i] = n
  local fns = {}
  for _, name in ipairs(stageEngines(i)) do
    if typeOf(name) ~= "booster_thruster" then
      -- acelerador 0 = motor desativado (ativo com empuxo 0 ainda gasta lava)
      fns[#fns + 1] = function()
        call(name, "setThrust", n)
        call(name, "setActive", n > 0)
      end
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
end

local function ignite(i)
  L.info("Acendendo estagio %d (%d motores)", i, #stageEngines(i))
  for _, name in ipairs(stageEngines(i)) do call(name, "setActive", true) end
end

local function shutdown(i)
  lastThrottleN[i] = nil
  for _, name in ipairs(stageEngines(i)) do
    if typeOf(name) ~= "booster_thruster" then
      call(name, "setThrust", 0)
      call(name, "setActive", false)
    end
  end
end

-- Rocket/Vector Thrusters nascem LIGADOS no mod: queimam assim que chega lava.
-- Desliga todos os motores liquidos conectados (config + qualquer outro achado).
local function safeAll(why)
  local seen, fns = {}, {}
  local names = allEngines()
  for _, n in ipairs(periNames()) do
    if peripheral.hasType(n, "thruster") then names[#names + 1] = n end
  end
  for _, n in ipairs(names) do
    if not seen[n] and peripheral.isPresent(n) and typeOf(n) ~= "booster_thruster" then
      seen[n] = true
      fns[#fns + 1] = function()
        call(n, "setThrust", 0)
        call(n, "setActive", false)
      end
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  lastThrottleN = {}
  L.info("Motores liquidos desligados (%d) - %s", #fns, why)
  return #fns
end

-- empuxo real somado e se o estagio inteiro acabou
S.failed = S.failed or {}
-- consulta todos os motores ao mesmo tempo (em paralelo = ~2 ticks no total)
local function stageStatus(i, burnTime)
  local total, spent, count = 0, 0, 0
  local fns = {}
  for _, name in ipairs(stageEngines(i)) do
    count = count + 1
    fns[#fns + 1] = function()
      local d = peripheral.isPresent(name) and call(name, "getData") or nil
      if not d then
        spent = spent + 1
      elseif d.engine_type == "booster_thruster" then
        if d.ignited and not d.is_spent then total = total + (d.thrust_power or 0) end
        if d.is_spent or S.failed[name] then spent = spent + 1 end
      else
        local th = call(name, "getThrust") or 0
        total = total + th
        -- so conta como esgotado se o acelerador estava ligado (com acelerador 0 o empuxo e 0 de proposito)
        local commanded = (lastThrottleN[i] or 0) > 0
        if commanded and burnTime > 3 and (d.fuel_amount or 0) <= 0 and th < 1 then spent = spent + 1 end
      end
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  return total, (count > 0 and spent == count)
end

local lastW = V(0, 0, 0) -- velocidade angular local (para o log)
local steerCount = 0      -- quantas vezes o gimbal foi comandado
-- force = true: o CC controla o gimbal mesmo com sputnik_guidance (manobras no espaco)
local integ = { x = 0, z = 0, t = nil }
-- integ = true: acumula o erro (tira o erro parado); so na subida, com motor ligado
local function steer(ship, target, force, useInteg)
  local d = toLocal(ship.q, target:normalize())
  local ex, ez = d.x, d.z
  if d.y < 0 then
    local m = math.sqrt(ex * ex + ez * ez)
    if m < 1e-6 then ex, m = 1, 1 end
    ex, ez = ex / m, ez / m
  end
  local w = toLocal(ship.q, ship.angv)
  local s, lim = CFG.gimbal_sign, CFG.max_gimbal
  local now = os.clock()
  local ki, imax = CFG.ki or 0.6, CFG.imax or 0.5
  if useInteg and integ.t then
    local dt = math.min(now - integ.t, 0.5)
    integ.x = clamp(integ.x + ex * dt, -imax, imax)
    integ.z = clamp(integ.z + ez * dt, -imax, imax)
  elseif not useInteg then
    integ.x, integ.z = 0, 0
  end
  integ.t = now
  local gx = clamp(s * (CFG.kp * ex + CFG.kd * w.z + ki * integ.x), -lim, lim)
  local gz = clamp(s * (CFG.kp * ez - CFG.kd * w.x + ki * integ.z), -lim, lim)
  -- todos os vector thrusters no mesmo tick
  -- (com sputnik_guidance o Sputnik controla o gimbal; o CC so mede o erro)
  local fns = {}
  if force or not CFG.sputnik_guidance then
    for _, name in ipairs(stageEngines(S.stage)) do
      if typeOf(name) == "vector_thruster" then
        fns[#fns + 1] = function() call(name, "setGimbal", gx, 0, gz) end
      end
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) else sleep(0.05) end
  lastW = w
  steerCount = steerCount + 1
  return math.deg(math.acos(clamp(d.y, -1, 1))), gx, gz
end

local function separate(i)
  local sep = CFG.stages[i].separator
  if not sep then return end
  L.info("Separando estagio %d (%s)", i, textutils.serialize(sep, { compact = true }))
  local function set(v)
    if sep.relay then call(sep.relay, "setOutput", sep.side, v)
    else redstone.setOutput(sep.side, v) end
  end
  set(true) sleep(0.3) set(false)
end

local function sputnik()
  if not CFG.sputnik then return nil end
  return call(CFG.sputnik, "getDeepSpaceData")
end

-- direcao da velocidade orbital (prograde) no mundo da nave, se a Sputnik der o vetor
local function orbitDir(d)
  local v = d and d.velocity
  if type(v) == "table" and v.x and v.x == v.x then
    local w = V(v.x, v.y or 0, v.z or 0)
    if w:length() > 1e-6 then return w:normalize() end
  end
  return nil
end

-- altura do periastro acima da superficie
local function periAlt(d)
  if not d or not d.semiMajorAxis or not d.eccentricity then return 0 / 0 end
  return d.semiMajorAxis * (1 - d.eccentricity) - (d.parentRadius or 0)
end

-- lava somada em tudo que for tanque de fluido ligado ao computador (inclui os motores)
local function lavaTotal()
  local names, amounts, fns = {}, {}, {}
  for _, n in ipairs(periNames()) do
    if peripheral.hasType(n, "fluid_storage") then names[#names + 1] = n end
  end
  for k, n in ipairs(names) do
    fns[k] = function()
      local ok, t = pcall(peripheral.call, n, "tanks")
      local sum = 0
      if ok and type(t) == "table" then
        for _, tk in pairs(t) do
          if type(tk) == "table" and tostring(tk.name):find("lava") then sum = sum + (tk.amount or 0) end
        end
      end
      amounts[k] = sum
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  local total = 0
  for k = 1, #names do total = total + (amounts[k] or 0) end
  return total, #names
end

---------------------------------------------------------------- RCS
-- O CC so liga/desliga o RCS (setThrust nao faz nada nele e o acelerador interno
-- comeca em 0). O script da Sputnik poe o acelerador em 1; aqui so ligamos/desligamos.
-- O CC tambem nao diz para onde cada RCS aponta: a calibracao liga um de cada vez
-- e mede o giro que ele causa (em rad/s2, no referencial da nave). Fica em rcs.cal.
local RCS_FILE = path("rcs.cal")
local rcs = { names = {}, cal = {}, on = {} }

local function rcsDiscover()
  rcs.names = {}
  -- RCS desligado por padrao: so e usado com rcs_enabled = true no config.lua
  if not CFG.rcs_enabled then return end
  for _, n in ipairs(periNames()) do
    if peripheral.hasType(n, "thruster") and typeOf(n) == "rcs_thruster" then rcs.names[#rcs.names + 1] = n end
  end
  table.sort(rcs.names)
  rcs.cal = {}
  if fs.exists(RCS_FILE) then
    local f = fs.open(RCS_FILE, "r")
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" then rcs.cal = t end
  end
end

-- eixos (X e Z da nave, nos dois sentidos) que nenhum RCS consegue girar
local function rcsMissing()
  local missing = {}
  for _, ax in ipairs({ { V(1, 0, 0), "+X" }, { V(-1, 0, 0), "-X" }, { V(0, 0, 1), "+Z" }, { V(0, 0, -1), "-Z" } }) do
    local covered = false
    for _, n in ipairs(rcs.names) do
      local rr = rcs.cal[n]
      if rr then
        local rv = V(rr[1], rr[2], rr[3])
        if rv:length() > 1e-9 and rv:dot(ax[1]) / rv:length() > (CFG.rcs_cos or 0.5) then covered = true end
      end
    end
    if not covered then missing[#missing + 1] = ax[2] end
  end
  return missing
end

-- RCS pronto para apontar a nave sozinho (calibrado e cobrindo os 4 lados)
local function rcsReady()
  if #rcs.names == 0 or rcs.failed then return false end
  return #rcsMissing() == 0
end

-- liga exatamente os RCS da lista (so chama o periferico quando muda)
local function rcsSet(list)
  local fns = {}
  for _, n in ipairs(rcs.names) do
    local want = list[n] == true
    if rcs.on[n] ~= want then
      rcs.on[n] = want
      fns[#fns + 1] = function() call(n, "setActive", want) end
    end
  end
  if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
end

local function rcsOff()
  rcs.on = {}  -- forca o desligamento de todos
  rcsSet({})
end

-- aponta o nariz (+Y da nave) para 'target' (mundo) so com RCS. Retorna o erro em graus.
local function rcsControl(ship, target)
  local d = toLocal(ship.q, target:normalize())
  local w = toLocal(ship.q, ship.angv)
  local ang = math.acos(clamp(d.y, -1, 1))
  local ax = V(d.z, 0, -d.x)  -- eixo que leva +Y ate o alvo (regra da mao direita)
  if ax:length() < 1e-6 then
    ax = (d.y < 0) and V(1, 0, 0) or V(0, 0, 0)
  else
    ax = ax:normalize()
  end
  -- aceleracao angular desejada: corrige o erro e amortece o giro (inclusive o de rolagem)
  local want = ax * ((CFG.rcs_kp or 0.4) * ang) - w * (CFG.rcs_kd or 1.2)
  local fire, m = {}, want:length()
  if m > (CFG.rcs_deadband or 0.01) then
    for _, n in ipairs(rcs.names) do
      local r = rcs.cal[n]
      if r then
        local rv = V(r[1], r[2], r[3])
        local rl = rv:length()
        if rl > 1e-9 and rv:dot(want) / (rl * m) > (CFG.rcs_cos or 0.5) then fire[n] = true end
      end
    end
  end
  rcsSet(fire)
  return math.deg(ang)
end

-- calibracao: precisa da nave solta (espaco ou no ar), nunca apoiada no chao
local function rcsCalibrate(why)
  rcsDiscover()
  if #rcs.names == 0 then return false end
  L.info("RCS calibrando %d propulsores (%s)", #rcs.names, why)
  rcsOff()
  local T = CFG.rcs_cal_time or 1.0
  local cal, ok = {}, 0
  for _, n in ipairs(rcs.names) do
    local s0, t0 = readShip(), os.clock()
    rcsSet({ [n] = true })
    sleep(T)
    rcsSet({})
    local s1 = readShip()
    local dt = math.max(os.clock() - t0, 0.05)
    local r = (toLocal(s1.q, s1.angv) - toLocal(s0.q, s0.angv)) * (1 / dt)
    if r:length() > (CFG.rcs_min_resp or 0.002) then
      cal[n] = { r.x, r.y, r.z }
      ok = ok + 1
      L.info("RCS %s giro=(%.4f, %.4f, %.4f) rad/s2", short(n), r.x, r.y, r.z)
    else
      L.warn("RCS %s nao girou a nave (%.4f rad/s2)", short(n), r:length())
    end
  end
  if ok == 0 then
    L.err("Nenhum RCS fez efeito. Confira: script NOVO da Sputnik (ele liga o acelerador do RCS) e nave solta, fora do chao.")
    return false
  end
  rcs.cal = cal
  local f = fs.open(RCS_FILE, "w") f.write(textutils.serialize(cal)) f.close()
  -- freia o giro que sobrou da calibracao
  local tEnd = os.clock() + 8
  while os.clock() < tEnd do
    local s = readShip()
    local w = toLocal(s.q, s.angv)
    if w:length() < 0.003 then break end
    local fire = {}
    for name, rr in pairs(cal) do
      if V(rr[1], rr[2], rr[3]):dot(w) < 0 then fire[name] = true end
    end
    rcsSet(fire)
    sleep(0.05)
  end
  rcsOff()
  L.info("RCS calibrado: %d de %d propulsores com efeito", ok, #rcs.names)
  local missing = rcsMissing()
  if #missing > 0 then
    L.warn("RCS nao consegue girar em torno de %s: vou girar com o motor principal. Com 4 RCS: ponha longe do centro de massa (nariz ou cauda), apontando para os 4 lados.",
      table.concat(missing, ", "))
  end
  return true
end

---------------------------------------------------------------- tela
local mon = CFG.monitor and peripheral.wrap(CFG.monitor)
local function show(t)
  local all = {}
  for _, l in ipairs(t) do table.insert(all, l) end
  for _, r in ipairs(L.recent) do table.insert(all, r) end
  for _, out in ipairs({ term, mon }) do
    if out then
      out.clear() out.setCursorPos(1, 1)
      for _, l in ipairs(all) do
        local _, y = out.getCursorPos()
        out.write(l) out.setCursorPos(1, y + 1)
      end
    end
  end
end

local csv
local function csvLine(fields)
  if not csv then csv = fs.open(L.csvPath(), "a") end
  csv.writeLine(table.concat(fields, ",")) csv.flush()
end

---------------------------------------------------------------- checagem
-- retorna lista de erros (impedem o lancamento) e avisos
local function preflight()
  local errs, warns = {}, {}
  local function E(...) local m = string.format(...) table.insert(errs, m) L.err("CHECAGEM %s", m) end
  local function W(...) local m = string.format(...) table.insert(warns, m) L.warn("CHECAGEM %s", m) end

  if not sublevel or not sublevel.isInPlotGrid() then E("computador fora da nave") return errs, warns end

  local ship = readShip()
  local g = gravity()
  L.info("CHECAGEM massa=%.1f g=%.2f pos=(%.1f, %.1f, %.1f)", ship.mass, g, ship.pos.x, ship.pos.y, ship.pos.z)

  -- motores configurados
  local configured = {}
  for i, st in ipairs(CFG.stages) do
    for _, n in ipairs(st.engines) do
      configured[n] = true
      if not peripheral.isPresent(n) then
        E("%s (estagio %d) nao encontrado: modem desligado ou cabo solto", short(n), i)
      else
        local d = call(n, "getData") or {}
        L.info("MOTOR pre %s", engineLine(n))
        if d.engine_type == "vector_thruster" or d.engine_type == "rocket_thruster" then
          if (d.fuel_amount or 0) <= 0 then
            E("%s sem lava no motor (bomba parada, sem forca ou cano errado)", short(n))
          end
        elseif d.engine_type == "booster_thruster" then
          if d.is_spent then E("%s ja esta gasto", short(n)) end
          if d.ignited then W("%s ja esta aceso!", short(n)) end
        end
      end
    end
  end
  -- motores ligados mas fora da config
  for _, n in ipairs(periNames()) do
    if peripheral.hasType(n, "thruster") and not configured[n] and typeOf(n) ~= "rcs_thruster" then
      W("%s esta conectado mas NAO esta na config (rode setup)", short(n))
    end
  end
  -- controle de direcao: sem Vector Thruster nao ha gimbal (a menos que o RCS esteja ligado e calibrado)
  local nVec = 0
  for _, n in ipairs(stageEngines(1)) do
    if typeOf(n) == "vector_thruster" then nVec = nVec + 1 end
  end
  if nVec == 0 then
    E("nenhum Vector Thruster no estagio 1: o foguete nao tem como corrigir a direcao e vai tombar (ligue um modem no Vector Thruster e rode setup)")
  end
  -- boosters: simetria de potencia
  local pots = {}
  for _, n in ipairs(stageEngines(1)) do
    local d = call(n, "getData")
    if d and d.engine_type == "booster_thruster" then pots[#pots + 1] = d.thrust_power or 0 end
  end
  for k = 2, #pots do
    if pots[k] ~= pots[1] then W("boosters com potencias diferentes (%s): foguete vai tombar", table.concat(pots, "/")) break end
  end
  -- empuxo
  local maxT = 0
  for _, n in ipairs(stageEngines(1)) do
    local d = call(n, "getData") or {}
    maxT = maxT + (d.engine_type == "booster_thruster" and (d.thrust_power or 0) or CFG.max_thrust_n)
  end
  local lava, nt = lavaTotal()
  L.info("CHECAGEM lava=%d mB em %d tanques/motores", lava, nt)
  rcsDiscover()
  if #rcs.names > 0 then
    L.info("CHECAGEM RCS: %d propulsores, %s", #rcs.names, rcsReady() and "calibrados" or "sem calibracao (calibra sozinho ao chegar no espaco)")
  end
  if nt == 0 then W("nenhum tanque ligado ao computador: nao da para medir o combustivel") end
  local twr = maxT / (ship.mass * g)
  L.info("CHECAGEM empuxo_max=%.0f TWR=%.2f", maxT, twr)
  if twr < CFG.min_twr then
    E("TWR %.2f abaixo de %.2f: o foguete so flutua e escorrega de lado (mais motores ou menos peso)", twr, CFG.min_twr)
  end
  if not CFG.sputnik or not peripheral.isPresent(CFG.sputnik) then W("Sputnik nao encontrado: sem dados de orbita") end
  if not redstone then W("sem API redstone") end
  return errs, warns, twr
end

---------------------------------------------------------------- modo teste
local function teste()
  L.newFile("teste")
  L.section("TESTE EM SOLO")
  safeAll("teste em solo")
  local errs, warns, twr = preflight()
  print(("TWR estagio 1: %.2f"):format(twr or 0))
  for _, e in ipairs(errs) do printError("ERRO: " .. e) end
  for _, w in ipairs(warns) do print("AVISO: " .. w) end
  print("Teste de gimbal: olhe os bocais dos Vector Thrusters.")
  for _, ax in ipairs({ { 0.35, 0, 0, "+X" }, { 0, 0, 0.35, "+Z" } }) do
    print("  inclinando o escape para " .. ax[4] .. " por 3s")
    for _ = 1, 60 do
      for _, n in ipairs(allEngines()) do
        if typeOf(n) == "vector_thruster" then call(n, "setGimbal", ax[1], ax[2], ax[3]) end
      end
      sleep(0.05)
    end
  end
  L.info("Teste concluido: %d erros, %d avisos", #errs, #warns)
  print(("Pronto. %d erros, %d avisos. Veja: logs"):format(#errs, #warns))
end

---------------------------------------------------------------- voo
local function voo()
  load()
  -- um arquivo de log por voo: continua no mesmo se o voo esta sendo retomado
  if S.logFile and fs.exists(S.logFile) then
    L.useFile(S.logFile)
  else
    S.logFile = L.newFile(S.phase == "PAD" and "voo" or "retomada")
    save()
  end
  S.failed = S.failed or {}
  if not sublevel.isInPlotGrid() then printError("Computador fora da nave!") return end

  if S.phase == "PAD" then
    L.section("PREPARACAO")
    safeAll("foguete na plataforma")
    local errs, warns, twr = preflight()
    local lines = { "== FOGUETE NA PLATAFORMA ==", ("TWR E1: %.2f  estagios: %d"):format(twr or 0, #CFG.stages) }
    for _, e in ipairs(errs) do table.insert(lines, "ERRO: " .. e) end
    for _, w in ipairs(warns) do table.insert(lines, "AVISO: " .. w) end
    if #errs > 0 then
      table.insert(lines, "Corrija os erros. F = forcar mesmo assim")
    else
      table.insert(lines, "Aperte o botao (" .. CFG.launch_side .. ") ou digite L")
    end
    show(lines)
    parallel.waitForAny(
      function()
        if #errs > 0 then while true do os.pullEvent("redstone") end end
        repeat os.pullEvent("redstone") until redstone.getInput(CFG.launch_side)
      end,
      function()
        while true do
          local _, c = os.pullEvent("char")
          c = c:lower()
          if (c == "l" and #errs == 0) or c == "f" then
            if c == "f" then L.warn("Lancamento FORCADO com %d erros", #errs) end
            return
          end
        end
      end)
    for t = CFG.countdown, 1, -1 do
      show({ "== CONTAGEM ==", ("T-%d"):format(t), "Digite A para abortar" })
      local timer = os.startTimer(1)
      while true do
        local ev, p = os.pullEvent()
        if ev == "timer" and p == timer then break end
        if ev == "char" and (p == "a" or p == "A") then
          L.info("Contagem abortada pelo piloto") show({ "ABORTADO" }) return
        end
      end
    end
    L.section("VOO")
    S.padY = readShip().pos.y
    S.stage, S.t0, S.failed = 1, os.epoch("utc"), {}
    setPhase("ASCENT", "lancamento")
    csvLine({ "t", "fase", "est", "y", "vel", "vy", "massa", "empuxo", "incl", "erro", "gx", "gz", "ecc", "dist" })
  else
    L.section("RETOMANDO VOO na fase " .. S.phase)
  end

  if S.phase == "ORBIT" or S.phase == "FALHA" or S.phase == "FIM" or S.phase == "POUSADO" then
    local d = sputnik() or {}
    show({ "== VOO ENCERRADO: " .. S.phase .. " ==", ("ECC %s"):format(tostring(d.eccentricity)),
      "Veja: logs erros", "Novo voo: voo reset" })
    return
  end

  if S.phase == "REENTRADA" then
    shutdown(S.stage)
  else
    ignite(S.stage)
  end
  if S.phase == "ASCENT" then setThrottle(S.stage, 1) end
  if S.phase == "DEORBIT" then setThrottle(S.stage, CFG.steer_throttle) end
  -- POUSO comeca com motor em 0: so acelera depois de apontar para cima
  -- (antes acendia com o foguete de lado e empurrava a nave para o lado)
  if S.phase == "POUSO" then setThrottle(S.stage, 0) end
  local land = { lastErr = 180, lastThr = 0, I = 0 }
  rcsDiscover()
  rcsOff()
  local deorbit = { sign = S.deorbitSign or 1, lastPeri = nil, lastT = os.clock(), flips = 0 }

  local burnStart = os.clock()
  local igniteT = os.clock()
  local boosterRetry = {}
  local lastDist, lastDistT, lastVel, lastT = nil, nil, nil, os.clock()
  local calT, calVy, calTicks = os.clock(), nil, 0
  local engT = os.clock()
  local slowT = -1
  local orbT = -math.huge
  local tiltT = nil
  local orb = { flips = 0 }
  local bestEcc = math.huge
  local tick = 0
  -- valores lidos na parte lenta do loop (a cada 0.5s)
  local g, dsd, inSpace, thrust, ecc, dist, vr = gravity(), nil, false, 0, 0 / 0, 0 / 0, 0

  while true do
    local steerBefore = steerCount
    local ship = readShip()
    local now = os.clock()
    local dt = math.max(now - lastT, 0.05)
    local speed = ship.vel:length()
    local tilt, err, gx, gz = 0, 0, 0, 0
    local spent = false
    local slow = now - slowT >= 0.5

    if slow then
      slowT = now
      g = gravity()
      dsd = sputnik()
      inSpace = dsd and dsd.inDeepSpace or false
      ecc = dsd and dsd.eccentricity or 0 / 0
      dist = dsd and dsd.distanceToPlanet or 0 / 0
      -- a Sputnik so atualiza a distancia de vez em quando: mede vr so quando ela muda
      if dsd and dsd.distanceToPlanet and lastDist and dsd.distanceToPlanet ~= lastDist then
        vr = (dsd.distanceToPlanet - lastDist) / math.max(now - lastDistT, 0.05)
        orb.vrOk = true
      end
      if dsd and dsd.distanceToPlanet and dsd.distanceToPlanet ~= lastDist then
        lastDist, lastDistT = dsd.distanceToPlanet, now
      elseif orb.vrOk and lastDistT and now - lastDistT > 3 then
        vr = 0  -- distancia parada ha 3 s: estamos no apoastro
      end
      thrust, spent = stageStatus(S.stage, now - burnStart)
      -- dados orbitais completos a cada 2s no espaco
      if inSpace and not orb.dumped then
        -- uma vez: tudo que a Sputnik entrega (para descobrir campos e unidades)
        orb.dumped = true
        L.info("SPUTNIK dados=%s", textutils.serialize(dsd, { compact = true }))
      end
      if inSpace and now - orbT >= 2 then
        orbT = now
        L.info("ORBITA ecc=%s sma=%s periodo=%s vel_orb=%s g=%s raio_planeta=%s dist=%s atm=%s corpo=%s",
          tostring(dsd.eccentricity), tostring(dsd.semiMajorAxis), tostring(dsd.period), tostring(dsd.speed),
          tostring(dsd.gravity), tostring(dsd.parentRadius), tostring(dsd.distanceToPlanet),
          tostring(dsd.inAtmosphere), tostring(dsd.parentBody))
      end
    end

    -- confirma que cada booster acendeu (parte lenta, ate 4s apos ignicao)
    local since = now - igniteT
    if slow and since > 0.5 and since < 4 then
      local fns = {}
      for _, n in ipairs(stageEngines(S.stage)) do
        if typeOf(n) == "booster_thruster" and not S.failed[n] then fns[#fns + 1] = function()
          local d = call(n, "getData")
          if d and not d.ignited and not d.is_spent then
            boosterRetry[n] = (boosterRetry[n] or 0) + 1
            if since < 3 then
              if boosterRetry[n] == 1 then L.warn("%s nao acendeu, tentando de novo", short(n)) end
              call(n, "setActive", true)
            else
              S.failed[n] = true save()
              L.err("%s NAO ACENDEU: sem bloco de carvao logo acima dele, ou potencia 0. %s", short(n), engineLine(n))
            end
          elseif d and d.ignited and boosterRetry[n] and boosterRetry[n] > 0 and not S.failed[n] then
            L.info("%s acendeu apos %d tentativas", short(n), boosterRetry[n])
            boosterRetry[n] = -1
          end
        end end
      end
      if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
    end

    -- empuxo desigual entre motores liquidos gira o foguete (bomba fraca num dos lados)
    if slow and S.phase == "ASCENT" and now - burnStart > 3 and now - (orb.unevenT or -99) > 5 then
      local lo, hi, loN, hiN = math.huge, 0, "?", "?"
      local vals, fns = {}, {}
      local names = stageEngines(S.stage)
      for k, n in ipairs(names) do
        if typeOf(n) ~= "booster_thruster" then
          fns[#fns + 1] = function() vals[k] = call(n, "getThrust") end
        end
      end
      if #fns > 1 then
        parallel.waitForAll(table.unpack(fns))
        for k, n in ipairs(names) do
          local v = vals[k]
          if v then
            if v < lo then lo, loN = v, short(n) end
            if v > hi then hi, hiN = v, short(n) end
          end
        end
        if hi > 0 and (hi - lo) / hi > 0.2 then
          orb.unevenT = now
          L.warn("EMPUXO DESIGUAL: %s=%d N e %s=%d N. O lado fraco nao recebe lava suficiente (bomba/cano).", loN, lo, hiN, hi)
        end
      end
    end

    -- troca de estagio
    if spent and now - burnStart > 3 then
      L.info("Estagio %d esgotado", S.stage)
      logEngines("fim_estagio")
      shutdown(S.stage)
      if S.stage < #CFG.stages then
        separate(S.stage)
        S.stage = S.stage + 1
        save()
        sleep(1)
        ignite(S.stage)
        setThrottle(S.stage, (S.phase == "ASCENT") and 1 or CFG.steer_throttle)
        burnStart, igniteT, boosterRetry = os.clock(), os.clock(), {}
      elseif not S.fuelOut then
        S.fuelOut = true
        if S.phase == "DEORBIT" then
          L.err("Combustivel acabou durante o DEORBIT. Periastro pode nao ter baixado o suficiente.")
          setPhase("REENTRADA", "sem combustivel no deorbit")
        elseif S.phase == "POUSO" or S.phase == "REENTRADA" then
          L.err("SEM COMBUSTIVEL PARA O POUSO! Y=%.0f vy=%.1f", ship.pos.y, ship.vel.y)
        elseif inSpace or S.phase == "COAST" or S.phase == "CIRC" then
          setPhase("FIM", "combustivel acabou no espaco")
        else
          setPhase("BALISTICO", ("combustivel acabou em Y=%.0f, subindo por inercia"):format(ship.pos.y))
        end
      end
    end

    if S.phase == "ASCENT" or S.phase == "BALISTICO" then
      if inSpace then
        setThrottle(S.stage, 0)
        setPhase("COAST", "entrou no espaco profundo")
      else
        local alt = ship.pos.y - (S.padY or ship.pos.y)
        if alt > CFG.turn_start_alt then
          local f = clamp((alt - CFG.turn_start_alt) / (CFG.turn_end_y - S.padY - CFG.turn_start_alt), 0, 1)
          tilt = CFG.turn_end_angle * f ^ 0.6
        end
        local r = math.rad(tilt)
        err, gx, gz = steer(ship, UP * math.cos(r) + EAST * math.sin(r), nil, S.phase == "ASCENT")
        if S.phase == "ASCENT" then
          local maxT = #stageEngines(S.stage) * CFG.max_thrust_n
          setThrottle(S.stage, math.min(1, CFG.max_twr * ship.mass * g / maxT))
        end
        -- tombando?
        if err - tilt > 45 then
          tiltT = tiltT or now
          if now - tiltT > 1 then
            L.err("FOGUETE TOMBANDO: erro de atitude %.0f graus em Y=%.1f. Motores liquidos cortados.", err, ship.pos.y)
            logEngines("tombou")
            shutdown(S.stage)
            setPhase("FALHA", "tombou")
          end
        else
          tiltT = nil
        end
        if S.phase == "BALISTICO" and ship.vel.y < -2 then
          L.err("Sem combustivel antes do espaco: pico Y=%.0f, faltaram %.0f blocos", ship.pos.y, CFG.transfer_y - ship.pos.y)
          setPhase("FALHA", "caindo sem combustivel")
        end
      end

    elseif S.phase == "DEORBIT" then
      -- queima contra o movimento orbital ate o periastro ficar baixo
      local alvo = CFG.deorbit_peri or 8000
      if slow and dsd and not inSpace then
        setPhase("POUSO", "saiu do espaco durante o deorbit")
      elseif dsd and dsd.velocity and dsd.velocity.x == dsd.velocity.x then
        local dv = V(dsd.velocity.x, dsd.velocity.y, dsd.velocity.z)
        local target = dv:length() > 1e-6 and dv:normalize() * (-deorbit.sign) or UP
        err, gx, gz = steer(ship, target, true)
        local burning = err < 15
        setThrottle(S.stage, burning and 1 or CFG.steer_throttle)
        if burning then deorbit.burnedFull = true end
        local peri = (dsd.semiMajorAxis or 0 / 0) * (1 - (dsd.eccentricity or 0 / 0)) - (dsd.parentRadius or 0)
        if slow and peri == peri then
          if now - deorbit.lastT >= 2 then
            -- se o periastro subiu com a queima ligada, a direcao esta invertida
            if deorbit.lastPeri and deorbit.burnedFull and peri > deorbit.lastPeri and deorbit.flips < 3 then
              deorbit.sign = -deorbit.sign
              deorbit.flips = deorbit.flips + 1
              S.deorbitSign = deorbit.sign save()
              L.warn("Periastro SUBINDO (%.0f -> %.0f m): invertendo a direcao da queima", deorbit.lastPeri, peri)
            end
            L.info("DEORBIT periastro=%.0f m (alvo < %.0f) erro=%.1f sinal=%d", peri, alvo, err, deorbit.sign)
            deorbit.lastPeri, deorbit.lastT, deorbit.burnedFull = peri, now, false
          end
          if peri < alvo then
            shutdown(S.stage)
            setPhase("REENTRADA", ("periastro %.0f m"):format(peri))
          end
        end
      end

    elseif S.phase == "REENTRADA" then
      -- motores desligados, esperando voltar ao overworld
      if slow and dsd and not inSpace then
        ignite(S.stage)
        setThrottle(S.stage, 0)
        setPhase("POUSO", "voltou ao overworld")
      end

    elseif S.phase == "POUSO" then
      local vy = ship.vel.y
      local vh = V(ship.vel.x, 0, ship.vel.z)
      local hs = vh:length()

      -- gravidade MEDIDA em queda livre (o valor do aero pode nao bater com o planeta)
      if land.lastVy and land.lastThr == 0 and dt < 1 then
        local gm = -(vy - land.lastVy) / dt
        land.gMed = land.gMed and (land.gMed * 0.9 + gm * 0.1) or gm
      end
      local gUse = (land.gMed and land.gMed > 0) and land.gMed or g

      -- chao: 'voo descer <Y>' ou ground_y na config. Sem chao conhecido, usa um teto
      -- seguro (land_ceiling_y) e desce devagar dali ate encostar no chao.
      local groundY = S.groundY or CFG.ground_y
      local off = CFG.land_offset or 3          -- altura do centro de massa com a nave no chao
      local h = groundY and (ship.pos.y - groundY - off) or nil
      local slowTop = groundY and (groundY + off + (CFG.land_slow_h or 40)) or (CFG.land_ceiling_y or 400)
      local hTop = ship.pos.y - slowTop          -- altura acima da zona de descida lenta

      local nEng = 0
      for _, n in ipairs(stageEngines(S.stage)) do
        if typeOf(n) ~= "booster_thruster" then nEng = nEng + 1 end
      end
      local Fmax = nEng * CFG.max_thrust_n
      local aMax = Fmax / math.max(ship.mass, 1) - gUse
      local vFinal = CFG.land_speed or 3

      -- velocidade vertical alvo
      local vT
      if hTop > 0 then
        local aB = math.max(aMax * 0.5, 0.5)
        vT = -math.max(vFinal, math.sqrt(2 * aB * hTop))
        vT = math.max(vT, -(CFG.land_max_speed or 120))
      else
        vT = -vFinal
        if h then vT = -clamp(h * 0.3, 1.5, vFinal) end
      end

      -- aceleracao desejada (vetor): vertical pelo perfil de velocidade,
      -- horizontal para zerar a deriva lateral
      local aV = gUse + 0.8 * (vT - vy)
      if hTop <= 0 and land.lastErr < 30 then
        land.I = clamp(land.I + 0.15 * (vT - vy) * dt, -3, 3)
        aV = aV + land.I
      end
      aV = math.max(aV, 0)
      local aH = V(0, 0, 0)
      if hs > 0.3 then
        aH = vh * (-0.4)
        local aHmax = CFG.land_h_accel or 8
        if aH:length() > aHmax then aH = aH * (aHmax / aH:length()) end
      end
      -- inclinacao maxima: 60 graus longe do chao, 25 graus perto
      local tanMax = math.tan(math.rad(hTop > 0 and (CFG.land_max_tilt_high or 60) or (CFG.land_max_tilt or 25)))
      local aHl = aH:length()
      if aHl > aV * tanMax then
        if hTop > 0 then aV = aHl / tanMax             -- longe do chao: sobe um pouco para frear de lado
        else aH = aH * (aV * tanMax / aHl) end         -- perto do chao: vertical tem prioridade
      end
      local aVec = UP * aV + aH
      local aMag = aVec:length()
      local tgt = aMag > 1e-3 and aVec * (1 / aMag) or UP

      -- empuxo, corrigido pelo quanto o foguete ainda esta desalinhado
      local cosE = math.cos(math.rad(math.min(land.lastErr, 60)))
      local thr = clamp(aMag * ship.mass / math.max(Fmax * cosE, 1), 0, 1)
      if land.lastErr > 60 then thr = 0 end      -- nunca acelera de lado ou de cabeca para baixo
      -- empuxo minimo so para o gimbal conseguir girar a nave (sem empuxo o gimbal nao faz nada)
      local minThr = (CFG.land_orient_n or 100) / CFG.max_thrust_n
      if thr < minThr and land.lastErr > 8 and not rcsReady() then thr = minThr end
      if aMax <= 0.5 then
        thr = 1
        if slow then L.err("Empuxo insuficiente para pousar (a_max=%.2f)", aMax) end
      end
      setThrottle(S.stage, thr)

      err, gx, gz = steer(ship, tgt, CFG.land_cc_gimbal ~= false)
      if rcsReady() then rcsControl(ship, tgt) end

      -- toque no chao: pela altura (se o chao e conhecido) ou por contato
      -- (vinha descendo, parou de repente mesmo com empuxo abaixo do necessario para pairar)
      if vy < -1.5 then land.fastT = now end
      local hover = gUse * ship.mass / math.max(Fmax, 1)
      local touched = h and h < 1.5 and math.abs(vy) < 2
      if not touched and hTop <= 0 and gUse > 0.4 and land.fastT and now - land.fastT < 4
         and math.abs(vy) < 0.3 and thr < hover * 0.5 then
        land.contactT = land.contactT or now
        if now - land.contactT > 1.5 then touched = true end
      else
        land.contactT = nil
      end

      if slow then
        L.info("POUSO y=%.1f h=%s h_zona=%.0f vy=%.2f v_alvo=%.1f vh=%.1f acel=%.2f pairar=%.2f g_aero=%.3f g_medido=%s a_max=%.1f erro=%.1f",
          ship.pos.y, h and ("%.1f"):format(h) or "?", hTop, vy, vT, hs, thr, hover, g,
          land.gMed and ("%.3f"):format(land.gMed) or "?", aMax, err)
      end
      land.lastVy, land.lastThr, land.lastErr = vy, (lastThrottleN[S.stage] or 0), err
      if touched then
        shutdown(S.stage)
        setPhase("POUSADO", ("y=%.1f vy=%.1f"):format(ship.pos.y, vy))
      end

    elseif S.phase == "COAST" or S.phase == "CIRC" then
      -- No espaco profundo a nave fica parada no seu proprio mundo: a orbita e
      -- simulada pela Sputnik. ship.vel nao serve para nada aqui; a direcao da
      -- queima vem da velocidade orbital da Sputnik, e o sinal certo e descoberto
      -- olhando se o semi-eixo maior (sma) sobe durante a queima.
      local pro = (not orb.noPro) and orbitDir(dsd) or nil
      if pro then
        orb.dir = pro * (S.progSign or 1)
      elseif not orb.dir then
        orb.dir = qrot(ship.q, UP)  -- sem vetor da Sputnik: mantem o nariz e testa o sinal queimando
        L.warn("Sputnik sem velocity: vou queimar para onde o nariz aponta e corrigir pelo sma")
      end
      -- calibra o RCS na primeira vez no espaco (nave solta e sem gravidade)
      if S.phase == "COAST" and #rcs.names > 0 and not rcsReady() and not orb.rcsTried then
        orb.rcsTried = true
        setThrottle(S.stage, 0)
        rcsCalibrate("primeira vez no espaco")
        ship = readShip()
      end
      local useRcs = rcsReady()
      err, gx, gz = steer(ship, orb.dir, true)
      if useRcs then
        rcsControl(ship, orb.dir)
        -- se em 30 s o erro nao cair pelo menos 5 graus, o RCS nao da conta: volta para o motor
        if err < 10 or not orb.rcsBest or err < orb.rcsBest - 5 then orb.rcsBest, orb.rcsT = err, now end
        if err >= 10 and now - orb.rcsT > (CFG.rcs_timeout or 30) then
          rcs.failed = true
          rcsOff()
          L.warn("RCS nao conseguiu apontar a nave em %ds (erro %.0f): girando com o motor principal", CFG.rcs_timeout or 30, err)
          useRcs = false
        end
      end
      local peri = periAlt(dsd)
      local sma = dsd and dsd.semiMajorAxis
      local alvo = math.min(CFG.orbit_peri_alt or 23000, (dist == dist and dist or 1e9) - 300)

      if S.phase == "COAST" then
        -- com RCS nao gasta lava para girar; sem RCS, empuxo minimo so enquanto gira
        setThrottle(S.stage, (not useRcs and err > 5) and CFG.steer_throttle or 0)
        if slow and dsd and ((orb.vrOk and vr <= 1) or (peri == peri and peri >= alvo)) then
          bestEcc = math.huge
          setPhase("CIRC", ("apoastro, vr=%.2f ecc=%s periastro=%.0f alvo=%.0f"):format(vr, tostring(ecc), peri, alvo))
        end
      else
        local aligned = err < 10
        -- perto do alvo reduz o empuxo para nao passar do ponto
        local falta = (peri == peri) and (alvo - peri) or math.huge
        local full = clamp(falta / (CFG.circ_slow_m or 50000), 0.2, 1)
        setThrottle(S.stage, aligned and full or (useRcs and 0 or CFG.steer_throttle))
        if aligned then orb.burned = true end
        if slow and sma then
          if not orb.lastSma then
            orb.lastSma, orb.lastT = sma, now
          elseif now - orb.lastT >= 1.5 then
            if orb.burned and sma < orb.lastSma - 1 and orb.flips < 3 then
              orb.flips, orb.stale = orb.flips + 1, 0
              if pro then S.progSign = -(S.progSign or 1) save() else orb.dir = orb.dir * -1 end
              L.warn("sma CAINDO com a queima (%.0f -> %.0f): invertendo a direcao", orb.lastSma, sma)
            elseif orb.burned and math.abs(sma - orb.lastSma) < 1 then
              -- queimando alinhado e a orbita nao muda: essa direcao e perpendicular ao movimento
              orb.stale = (orb.stale or 0) + 1
              if orb.stale >= 2 then
                orb.stale, orb.turns = 0, (orb.turns or 0) + 1
                local h = V(orb.dir.x, 0, orb.dir.z)
                if h:length() < 0.1 then h = EAST end
                orb.noPro = true
                orb.dir = V(-h.z, 0, h.x):normalize()  -- gira 90 graus no plano horizontal
                L.warn("Queima nao muda a orbita (sma=%.0f): tentando outra direcao (%d/4)", sma, orb.turns)
                if orb.turns > 4 then
                  shutdown(S.stage)
                  setPhase("FALHA", "nenhuma direcao de queima muda a orbita; mande o log")
                end
              end
            elseif orb.burned then
              orb.stale = 0
            end
            L.info("CIRC periastro=%.0f alvo=%.0f sma=%.0f ecc=%s erro=%.1f sinal=%d",
              peri, alvo, sma, tostring(ecc), err, S.progSign or 1)
            orb.lastSma, orb.lastT, orb.burned = sma, now, false
          end
        end
        if ecc == ecc and ecc < bestEcc then bestEcc = ecc end
        if slow and peri == peri and peri >= alvo then
          shutdown(S.stage)
          setPhase("ORBIT", ("periastro=%.0f ecc=%s"):format(peri, tostring(ecc)))
        elseif slow and ecc == ecc and bestEcc < 0.3 and ecc > bestEcc + 0.005 and peri == peri and peri > 0 then
          -- passou do ponto: a queima comecou a esticar a orbita do outro lado
          shutdown(S.stage)
          setPhase("ORBIT", ("ecc voltou a subir, periastro=%.0f ecc=%.4f"):format(peri, ecc))
        end
      end
    end

    -- fisica: aceleracao medida x esperada (calibra unidades de massa/empuxo)
    calTicks = calTicks + 1
    if now - calT >= 1 then
      if calVy then
        local aMed = (ship.vel.y - calVy) / (now - calT)
        L.info("FISICA y=%.1f vy=%.2f a_medida=%.2f F/m=%.2f g=%.2f massa=%.1f F=%.0f erro=%.1f gimbal=(%.2f,%.2f) w=(%.2f,%.2f,%.2f) loop=%.1fHz",
          ship.pos.y, ship.vel.y, aMed, thrust / math.max(ship.mass, 1e-6), g, ship.mass, thrust, err,
          gx, gz, lastW.x, lastW.y, lastW.z, calTicks / (now - calT))
      end
      calT, calVy, calTicks = now, ship.vel.y, 0
    end
    -- motores: a cada 5s no inicio, depois a cada 20s (em paralelo)
    local engEvery = (now - burnStart < 30) and 5 or 20
    if now - engT >= engEvery then
      logEngines(S.phase)
      local lava, nt = lavaTotal()
      L.info("COMBUSTIVEL lava=%d mB em %d tanques/motores (fase %s, Y=%.0f)", lava, nt, S.phase, ship.pos.y)
      engT = now
    end

    if S.phase == "ORBIT" or S.phase == "FALHA" or S.phase == "FIM" or S.phase == "POUSADO" then
      shutdown(S.stage)
      rcsOff()
      show({ "== VOO ENCERRADO: " .. S.phase .. " ==", ("Y %.0f  ECC %s"):format(ship.pos.y, tostring(ecc)),
        "Veja: logs erros" })
      break
    end

    lastVel, lastT = ship.vel, now
    tick = tick + 1

    if tick % 2 == 0 then
      csvLine({ os.epoch("utc") - (S.t0 or 0), S.phase, S.stage, ("%.1f"):format(ship.pos.y),
        ("%.2f"):format(speed), ("%.2f"):format(ship.vel.y), ("%.0f"):format(ship.mass),
        ("%.0f"):format(thrust), ("%.1f"):format(tilt), ("%.1f"):format(err),
        ("%.2f"):format(gx), ("%.2f"):format(gz), tostring(ecc), tostring(dist) })
    end
    if tick % 5 == 0 then
      show({ "== " .. S.phase .. " == estagio " .. S.stage .. "/" .. #CFG.stages,
        ("Y %.0f   vel %.1f   vy %.1f"):format(ship.pos.y, speed, ship.vel.y),
        ("Empuxo %.0f N   massa %.0f"):format(thrust, ship.mass),
        ("Inclin %.1f   erro %.1f"):format(tilt, err),
        inSpace and "ESPACO PROFUNDO" or "" })
    end
    -- o setGimbal dentro de steer() ja espera 1 tick; se nao houve steer, espera aqui
    if steerCount == steerBefore then sleep(0.05) end
  end
end

---------------------------------------------------------------- execucao protegida
-- voo descer: deorbit (se no espaco) e pouso controlado
local function descer()
  load()
  if S.logFile and fs.exists(S.logFile) then
    L.useFile(S.logFile)
  else
    S.logFile = L.newFile("descida")
  end
  S.failed = S.failed or {}
  S.fuelOut = nil
  S.t0 = S.t0 or os.epoch("utc")  -- sem isso o tempo na telemetria sai gigante (apos 'voo reset')
  L.section("MANOBRA DE DESCIDA")
  local gy = tonumber(args[2])
  if gy then S.groundY = gy L.info("Chao definido em Y=%.1f", gy) end
  if not S.groundY and not CFG.ground_y then
    L.warn("Chao desconhecido: freia ate Y=%s e desce a %s m/s ate encostar. Use 'voo descer <Y do chao>' se souber.",
      tostring(CFG.land_ceiling_y or 400), tostring(CFG.land_speed or 3))
  end
  csvLine({ "t", "fase", "est", "y", "vel", "vy", "massa", "empuxo", "incl", "erro", "gx", "gz", "ecc", "dist" })
  local d = sputnik() or {}
  if d.inDeepSpace then
    setPhase("DEORBIT", "comando 'voo descer' no espaco")
  else
    setPhase("POUSO", "comando 'voo descer' fora do espaco")
  end
  save()
  return voo()
end

-- voo rcs: calibra o RCS agora e testa segurando o nariz para cima por 15 s
local function rcsTeste()
  L.newFile("rcs")
  L.section("TESTE DO RCS")
  rcsDiscover()
  if not CFG.rcs_enabled then printError("RCS desligado. Para usar, ponha rcs_enabled = true no config.lua.") return end
  if #rcs.names == 0 then printError("Nenhum RCS ligado ao computador (modem + cabo em cada um).") return end
  print(("%d RCS encontrados. A nave precisa estar SOLTA (no ar ou no espaco)."):format(#rcs.names))
  if not rcsCalibrate("comando voo rcs") then printError("Calibracao falhou. Veja: logs erros") return end
  print("Calibrado. Segurando o nariz para cima por 15 s...")
  local tEnd = os.clock() + 15
  local nextLog = 0
  while os.clock() < tEnd do
    local ship = readShip()
    local e = rcsControl(ship, UP)
    if os.clock() >= nextLog then
      nextLog = os.clock() + 1
      local w = toLocal(ship.q, ship.angv)
      L.info("RCS teste erro=%.1f w=(%.3f,%.3f,%.3f)", e, w.x, w.y, w.z)
      print(("erro %.1f graus"):format(e))
    end
    sleep(0.05)
  end
  rcsOff()
  print("Pronto. Veja: logs")
end

local main = (args[1] == "teste") and teste or (args[1] == "descer") and descer
  or (args[1] == "rcs") and rcsTeste or voo
local ok, e = xpcall(main, debug.traceback)
if not ok then
  if tostring(e):find("Terminated") then
    L.warn("Programa interrompido (Ctrl+T) na fase %s", tostring(S.phase))
  else
    L.err("CRASH do script: %s", tostring(e))
    printError("O script travou! Detalhes em: logs erros")
    printError(tostring(e))
  end
  pcall(shutdown, S.stage)
  pcall(rcsOff)
end
