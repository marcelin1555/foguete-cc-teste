-- lib/foguete/checagem.lua : checagem antes do voo (preflight) e 'voo teste'
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS)
  local periNames = mat.periNames
  local call, typeOf, short, stageEngines, allEngines = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.allEngines
  local engineLine, lavaTotal, safeAll = Mot.engineLine, Mot.lavaTotal, Mot.safeAll
  local readShip, gravity = Sens.readShip, Sens.gravity
  local stabilizer = Ctl.stabilizer
  local rcs, rcsDiscover, rcsReady = Rcs.estado, Rcs.discover, Rcs.ready

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
    if CFG.stabilizer then
      L.info("CHECAGEM Magnetic Stabilizer no lado %s%s", tostring(CFG.stabilizer.side),
        CFG.stabilizer.relay and (" do relay " .. CFG.stabilizer.relay) or "")
    end
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
    for _, k in ipairs(DESCONHECIDAS) do
      W("chave desconhecida no config.lua: %s (erro de digitacao?)", k)
    end
    if not CFG.sputnik or not peripheral.isPresent(CFG.sputnik) then W("Sputnik nao encontrado: sem dados de orbita") end
    if not redstone then W("sem API redstone") end
    return errs, warns, twr
  end

  -- modo teste
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
    if CFG.stabilizer then
      print("Teste do Magnetic Stabilizer: ligando por 2 s (confira o bloco acender)")
      stabilizer(true) sleep(2) stabilizer(false)
    end
    L.info("Teste concluido: %d erros, %d avisos", #errs, #warns)
    print(("Pronto. %d erros, %d avisos. Veja: logs"):format(#errs, #warns))
  end

  return { preflight = preflight, teste = teste }
end

return M
