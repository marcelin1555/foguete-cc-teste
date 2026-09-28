-- lib/foguete/motores.lua : motores (perifericos), acelerador, ignicao e equilibrio de empuxo
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L)
  local S = E.proxy
  local function save() E.salvar() end
  local clamp, periNames = mat.clamp, mat.periNames

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
    if not st then return {} end
    -- boosters ja separados saem da lista (nao estao mais na nave)
    if S.boostersDropped and S.boostersDropped[i] then
      local list = {}
      for _, n in ipairs(st.engines) do
        if typeOf(n) ~= "booster_thruster" then list[#list + 1] = n end
      end
      return list
    end
    return st.engines
  end

  local function allEngines()
    local t = {}
    for i = 1, #CFG.stages do
      for _, n in ipairs(stageEngines(i)) do table.insert(t, n) end
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
  local lastThrottleN = {}  -- maior acelerador comandado no estagio (usado para saber se esgotou)
  local lastEngineN = {}    -- ultimo empuxo mandado para cada motor
  local function quantN(frac)
    local n = math.floor(clamp(frac, 0, 1) * CFG.max_thrust_n)
    return math.floor(n / 50) * 50
  end
  -- vecFrac (opcional): acelerador so dos Vector Thrusters; os fixos usam frac
  local function setThrottle(i, frac, vecFrac)
    local nMain = quantN(frac)
    local nVec = vecFrac and quantN(vecFrac) or nMain
    -- limite de equilibrio: com as bombas sem dar conta, todos os motores empurram igual
    if S.thrCap then nMain, nVec = math.min(nMain, S.thrCap), math.min(nVec, S.thrCap) end
    lastThrottleN[i] = math.max(nMain, nVec)
    local fns = {}
    for _, name in ipairs(stageEngines(i)) do
      local t = typeOf(name)
      if t ~= "booster_thruster" then
        local n = (t == "vector_thruster") and nVec or nMain
        if lastEngineN[name] ~= n then -- so chama o periferico quando muda
          lastEngineN[name] = n
          -- acelerador 0 = motor desativado (ativo com empuxo 0 ainda gasta lava)
          fns[#fns + 1] = function()
            call(name, "setThrust", n)
            call(name, "setActive", n > 0)
          end
        end
      end
    end
    if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  end

  -- girando: motores fixos desligados, so o Vector Thruster empurra (e o unico que vira a nave)
  local function orientThrottle(i)
    setThrottle(i, 0, CFG.orient_throttle)
  end

  local function ignite(i)
    L.info("Acendendo estagio %d (%d motores)", i, #stageEngines(i))
    for _, name in ipairs(stageEngines(i)) do call(name, "setActive", true) end
  end

  local function shutdown(i)
    lastThrottleN[i] = nil
    for _, name in ipairs(stageEngines(i)) do lastEngineN[name] = nil end
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
    lastEngineN = {}
    L.info("Motores liquidos desligados (%d) - %s", #fns, why)
    return #fns
  end

  -- empuxo real somado e se o estagio inteiro acabou
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

  -- empuxo desigual entre motores liquidos gira o foguete (bombas nao dao conta da vazao).
  -- Equilibra: limita todos os motores a media que as bombas sustentam; depois tenta subir aos poucos.
  local bal = {}
  local function equilibrar(now)
    if now - (bal.balT or -99) <= CFG.balance_every then return end
    bal.balT = now
      local vals, fns = {}, {}
      local names = stageEngines(S.stage)
      for k, n in ipairs(names) do
        if typeOf(n) ~= "booster_thruster" then
          fns[#fns + 1] = function() vals[k] = call(n, "getThrust") end
        end
      end
      if #fns > 1 then
        parallel.waitForAll(table.unpack(fns))
        local lo, hi, sum, cnt, loN, hiN = math.huge, 0, 0, 0, "?", "?"
        for k, n in ipairs(names) do
          local v = vals[k]
          if v then
            sum, cnt = sum + v, cnt + 1
            if v < lo then lo, loN = v, short(n) end
            if v > hi then hi, hiN = v, short(n) end
          end
        end
        local cap = S.thrCap or CFG.max_thrust_n
        if hi > 0 and (hi - lo) / hi > (CFG.balance_spread) then
          local newCap = math.max(CFG.balance_min, math.floor(sum / cnt / 50) * 50)
          if newCap < cap then
            S.thrCap = newCap
            save()
            L.warn("EMPUXO DESIGUAL: %s=%d N e %s=%d N (bombas sem vazao). Limitando todos a %d N para equilibrar.",
              loN, lo, hiN, hi, newCap)
          end
        elseif S.thrCap and lo >= S.thrCap - 50 and now - (bal.capUpT or -99) > 3 then
          -- todos chegando no limite: sobra lava, tenta subir 50 N
          bal.capUpT = now
          S.thrCap = math.min(CFG.max_thrust_n, S.thrCap + 50)
          if S.thrCap >= CFG.max_thrust_n then S.thrCap = nil end
          save()
          L.info("Empuxo equilibrado; limite por motor agora %s", S.thrCap and (S.thrCap .. " N") or "livre")
        end
      end
  end

  local function ultimoAcelerador(i) return lastThrottleN[i] end

  return {
    call = call, typeOf = typeOf, short = short, stageEngines = stageEngines, allEngines = allEngines,
    engineLine = engineLine, logEngines = logEngines, setThrottle = setThrottle, orientThrottle = orientThrottle,
    ignite = ignite, shutdown = shutdown, safeAll = safeAll, stageStatus = stageStatus, lavaTotal = lavaTotal,
    equilibrar = equilibrar, ultimoAcelerador = ultimoAcelerador,
  }
end

return M
