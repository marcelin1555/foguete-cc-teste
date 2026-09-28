-- lib/foguete/rcs.lua : RCS (so age com rcs_enabled = true no config.lua)
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot, Sens)
  local V = vector.new
  local UP = mat.UP
  local clamp, toLocal, periNames = mat.clamp, mat.toLocal, mat.periNames
  local call, typeOf, short = Mot.call, Mot.typeOf, Mot.short
  local readShip = Sens.readShip
  local RCS_FILE = "rcs.cal"

  -- O CC so liga/desliga o RCS (setThrust nao faz nada nele e o acelerador interno
  -- comeca em 0). O script da Sputnik poe o acelerador em 1; aqui so ligamos/desligamos.
  -- O CC tambem nao diz para onde cada RCS aponta: a calibracao liga um de cada vez
  -- e mede o giro que ele causa (em rad/s2, no referencial da nave). Fica em rcs.cal.
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
          if rv:length() > 1e-9 and rv:dot(ax[1]) / rv:length() > (CFG.rcs_cos) then covered = true end
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
    local want = ax * ((CFG.rcs_kp) * ang) - w * (CFG.rcs_kd)
    local fire, m = {}, want:length()
    if m > (CFG.rcs_deadband) then
      for _, n in ipairs(rcs.names) do
        local r = rcs.cal[n]
        if r then
          local rv = V(r[1], r[2], r[3])
          local rl = rv:length()
          if rl > 1e-9 and rv:dot(want) / (rl * m) > (CFG.rcs_cos) then fire[n] = true end
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
    local T = CFG.rcs_cal_time
    local cal, ok = {}, 0
    for _, n in ipairs(rcs.names) do
      local s0, t0 = readShip(), os.clock()
      rcsSet({ [n] = true })
      sleep(T)
      rcsSet({})
      local s1 = readShip()
      local dt = math.max(os.clock() - t0, 0.05)
      local r = (toLocal(s1.q, s1.angv) - toLocal(s0.q, s0.angv)) * (1 / dt)
      if r:length() > (CFG.rcs_min_resp) then
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

  return {
    estado = rcs, discover = rcsDiscover, missing = rcsMissing, ready = rcsReady, set = rcsSet, off = rcsOff,
    control = rcsControl, calibrate = rcsCalibrate, teste = rcsTeste,
  }
end

return M
