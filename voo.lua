-- voo.lua : piloto automatico ate a orbita (Create Cosmonautics + CC: Sable)
-- Uso: voo          -> checagem, espera o botao (ou retoma um voo em andamento)
--      voo teste    -> checagem completa + teste de gimbal, sem acender nada
--      voo reset    -> apaga o estado salvo (novo voo)
--      voo descer [Y]  -> deorbit (se no espaco) e pouso; Y = altura do chao, se souber
-- Registros: log.txt (eventos, use o programa 'logs') e voo.log (telemetria CSV)

local args = { ... }
local DIR = fs.getDir(shell.getRunningProgram())
local function path(p) return fs.combine(DIR, p) end
local L = dofile(path("log.lua"))
local STATE_FILE, CSV_FILE = path("estado.txt"), path("voo.log")

if not fs.exists(path("config.lua")) then
  printError("Rode 'setup' primeiro.") return
end
local CFG = dofile(path("config.lua"))

if args[1] == "reset" then
  fs.delete(STATE_FILE) L.info("Estado apagado (voo reset)") print("Estado apagado.") return
end

---------------------------------------------------------------- matematica
local V = vector.new
local UP = V(0, 1, 0)
local EAST = V(CFG.east[1], CFG.east[2], CFG.east[3]):normalize()

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

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
  for _, n in ipairs(peripheral.getNames()) do
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
local function steer(ship, target, force)
  local d = toLocal(ship.q, target:normalize())
  local ex, ez = d.x, d.z
  if d.y < 0 then
    local m = math.sqrt(ex * ex + ez * ez)
    if m < 1e-6 then ex, m = 1, 1 end
    ex, ez = ex / m, ez / m
  end
  local w = toLocal(ship.q, ship.angv)
  local s, lim = CFG.gimbal_sign, CFG.max_gimbal
  local gx = clamp(s * (CFG.kp * ex + CFG.kd * w.z), -lim, lim)
  local gz = clamp(s * (CFG.kp * ez - CFG.kd * w.x), -lim, lim)
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
  if not csv then csv = fs.open(CSV_FILE, "a") end
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
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "thruster") and not configured[n] then
      W("%s esta conectado mas NAO esta na config (rode setup)", short(n))
    end
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
  local twr = maxT / (ship.mass * g)
  L.info("CHECAGEM empuxo_max=%.0f TWR=%.2f", maxT, twr)
  if twr < CFG.min_twr then W("TWR %.2f abaixo de %.2f", twr, CFG.min_twr) end
  if not CFG.sputnik or not peripheral.isPresent(CFG.sputnik) then W("Sputnik nao encontrado: sem dados de orbita") end
  if not redstone then W("sem API redstone") end
  return errs, warns, twr
end

---------------------------------------------------------------- modo teste
local function teste()
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
  local gdir = nil
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
      if dsd and dsd.distanceToPlanet and lastDist then
        vr = (dsd.distanceToPlanet - lastDist) / math.max(now - lastDistT, 0.05)
      end
      if dsd and dsd.distanceToPlanet then lastDist, lastDistT = dsd.distanceToPlanet, now end
      thrust, spent = stageStatus(S.stage, now - burnStart)
      -- dados orbitais completos a cada 2s no espaco
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
        err, gx, gz = steer(ship, UP * math.cos(r) + EAST * math.sin(r))
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
      if thr < minThr and land.lastErr > 8 then thr = minThr end
      if aMax <= 0.5 then
        thr = 1
        if slow then L.err("Empuxo insuficiente para pousar (a_max=%.2f)", aMax) end
      end
      setThrottle(S.stage, thr)

      err, gx, gz = steer(ship, tgt, CFG.land_cc_gimbal ~= false)

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
      if lastVel and S.phase == "COAST" then
        local a = (ship.vel - lastVel) / dt
        if a:length() > 0.01 then
          gdir = gdir and (gdir * 0.9 + a:normalize() * 0.1):normalize() or a:normalize()
        end
      end
      local target
      if gdir then
        local vh = ship.vel - gdir * ship.vel:dot(gdir)
        local h = vh:length() > 1e-3 and vh:normalize() or EAST
        target = h + gdir * (vr * 0.05)
      else
        target = speed > 1e-3 and ship.vel:normalize() or EAST
      end
      err, gx, gz = steer(ship, target)

      if S.phase == "COAST" then
        local tApo = (dsd and dsd.gravity and dsd.gravity > 0) and vr / dsd.gravity or math.huge
        setThrottle(S.stage, tApo < 20 and CFG.steer_throttle or 0)
        if slow and dsd and vr <= 1 then
          bestEcc = math.huge
          setPhase("CIRC", ("apoastro, vr=%.2f ecc=%s"):format(vr, tostring(ecc)))
        end
      else
        setThrottle(S.stage, err < 10 and 1 or CFG.steer_throttle)
        if ecc == ecc then
          if ecc < bestEcc then bestEcc = ecc end
          if ecc <= CFG.ecc_target or (ecc > bestEcc + 0.005 and bestEcc < 0.3) then
            shutdown(S.stage)
            setPhase("ORBIT", ("ecc=%.4f"):format(ecc))
          end
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
    if now - engT >= engEvery then logEngines(S.phase) engT = now end

    if S.phase == "ORBIT" or S.phase == "FALHA" or S.phase == "FIM" or S.phase == "POUSADO" then
      shutdown(S.stage)
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
  S.failed = S.failed or {}
  S.fuelOut = nil
  S.t0 = S.t0 or os.epoch("utc")  -- sem isso o tempo no voo.log sai gigante (apos 'voo reset')
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

local main = (args[1] == "teste") and teste or (args[1] == "descer") and descer or voo
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
end
