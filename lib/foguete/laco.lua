-- lib/foguete/laco.lua : monta os modulos, laco principal do voo, 'voo descer' e limpeza apos crash
local M = {}

function M.novo(args, L, CFG, DESCONHECIDAS, STATE_FILE)
  ---------------------------------------------------------------- matematica
  local mat = require("foguete.mat")
  local V = vector.new
  local UP = mat.UP
  local EAST = V(CFG.east[1], CFG.east[2], CFG.east[3]):normalize()
  local clamp, periNames, qrot, toLocal, quatParts = mat.clamp, mat.periNames, mat.qrot, mat.toLocal, mat.quatParts

  ---------------------------------------------------------------- nave
  local Sens = require("foguete.sensores")
  local readShip, gravity = Sens.readShip, Sens.gravity

  ---------------------------------------------------------------- estado
  local E = require("foguete.estado").novo(STATE_FILE, L)
  local S = E.proxy
  local save, load, setPhase = E.salvar, E.carregar, E.trocar

  ---------------------------------------------------------------- motores
  local Mot = require("foguete.motores").novo(CFG, E, L)
  local call, typeOf, short, stageEngines, allEngines = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.allEngines
  local engineLine, logEngines, setThrottle, orientThrottle = Mot.engineLine, Mot.logEngines, Mot.setThrottle, Mot.orientThrottle
  local ignite, shutdown, safeAll, stageStatus, lavaTotal = Mot.ignite, Mot.shutdown, Mot.safeAll, Mot.stageStatus, Mot.lavaTotal

  local Ctl = require("foguete.controle").novo(CFG, E, L, Mot)
  local steer, alignedFor, stabilizer = Ctl.steer, Ctl.alignedFor, Ctl.stabilizer
  local Sep = require("foguete.separacao").novo(CFG, E, L, Mot)
  local pulse, separate, checkBoosterDrop = Sep.pulse, Sep.separate, Sep.checkBoosterDrop

  local Sp = require("foguete.sputnik").novo(CFG, Mot)
  local sputnik, orbitDir, periAlt = Sp.dados, Sp.orbitDir, Sp.periAlt

  ---------------------------------------------------------------- RCS e checagem
  local Rcs = require("foguete.rcs").novo(CFG, E, L, Mot, Sens)
  local rcs, rcsDiscover, rcsReady, rcsOff = Rcs.estado, Rcs.discover, Rcs.ready, Rcs.off
  local rcsControl, rcsCalibrate, rcsTeste = Rcs.control, Rcs.calibrate, Rcs.teste

  ---------------------------------------------------------------- tela
  local Tela = require("foguete.tela").novo(CFG, L)
  local show = Tela.show
  local TelCsv = require("foguete.telemetria").novo(L)
  local csvLine = TelCsv.csvLine

  local Chk = require("foguete.checagem").novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS)
  local preflight, teste = Chk.preflight, Chk.teste

  ---------------------------------------------------------------- fases
  local Plataforma = require("foguete.fases.plataforma")
  local MODULOS_FASE = { "subida", "orbita", "deorbit", "reentrada", "pouso" }
  local porFase, porNome = {}, {}
  for _, nome in ipairs(MODULOS_FASE) do
    local F = require("foguete.fases." .. nome)
    F.nome = nome
    porNome[nome] = F
    for _, f in ipairs(F.fases) do porFase[f] = F end
  end

  ---------------------------------------------------------------- voo
  local function voo()
    load()
    if not require("foguete.estado").FASES[S.phase] then
      printError(("Fase desconhecida no estado.txt: %s. Use 'voo reset' para comecar de novo."):format(tostring(S.phase)))
      return
    end
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
      local ctx0 = { S = S, cfg = CFG, log = L, trocar = setPhase, mot = Mot, chk = Chk, tela = Tela, sens = Sens,
        csvLine = csvLine }
      if not Plataforma.preparar(ctx0) then return end
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
    if S.phase == "DEORBIT" then orientThrottle(S.stage) end
    -- POUSO comeca com motor em 0: so acelera depois de apontar para cima
    -- (antes acendia com o foguete de lado e empurrava a nave para o lado)
    if S.phase == "POUSO" then setThrottle(S.stage, 0) end
    local memorias = {}
    for _, nome in ipairs(MODULOS_FASE) do memorias[nome] = porNome[nome].novaMemoria(S) end
    rcsDiscover()
    rcsOff()

    local burnStart = os.clock()
    local igniteT = os.clock()
    local boosterRetry = {}
    local lastDist, lastDistT, lastVel, lastT = nil, nil, nil, os.clock()
    local Tel = require("foguete.telemetria").novo(L, csvLine)
    local slowT = -1
    local orbT = -math.huge
    local vrOk, dumped = false, false
    local tick = 0
    -- valores lidos na parte lenta do loop (a cada 0.5s)
    local g, dsd, inSpace, thrust, ecc, dist, vr = gravity(), nil, false, 0, 0 / 0, 0 / 0, 0

    while true do
      local steerBefore = Ctl.steerCount()
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
          vrOk = true
        end
        if dsd and dsd.distanceToPlanet and dsd.distanceToPlanet ~= lastDist then
          lastDist, lastDistT = dsd.distanceToPlanet, now
        elseif vrOk and lastDistT and now - lastDistT > 3 then
          vr = 0  -- distancia parada ha 3 s: estamos no apoastro
        end
        thrust, spent = stageStatus(S.stage, now - burnStart)
        -- dados orbitais completos a cada 2s no espaco
        if inSpace and not dumped then
          -- uma vez: tudo que a Sputnik entrega (para descobrir campos e unidades)
          dumped = true
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

      local since = now - igniteT
      if slow and since > 0.5 and since < 4 then Sep.confirmarIgnicao(S.stage, since, boosterRetry) end

      if slow and now - burnStart > 1 then checkBoosterDrop(S.stage) end

      if slow and S.phase == "ASCENT" and now - burnStart > 2 then Mot.equilibrar(now) end

      -- troca de estagio
      if spent and now - burnStart > 3 and Sep.trocaEstagio(ship, inSpace) then
        burnStart, igniteT, boosterRetry = os.clock(), os.clock(), {}
      end

      local F = porFase[S.phase]
      if F then
        local ctx = {
          S = S, cfg = CFG, log = L, salvar = save, trocar = setPhase,
          mot = Mot, ctl = Ctl, sp = Sp, rcs = Rcs, sens = Sens, EAST = EAST,
          nave = ship, agora = now, dt = dt, lento = slow,
          orb = { dsd = dsd, inSpace = inSpace, ecc = ecc, dist = dist, vr = vr, g = g, vrOk = vrOk },
          saida = { tilt = tilt, err = err, gx = gx, gz = gz },
          mem = memorias[F.nome],
        }
        F.tick(ctx)
        ship = ctx.nave
        tilt, err, gx, gz = ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz
      end

      Tel.fisica(ship, now, thrust, g, err, gx, gz, Ctl.lastW())
      Tel.motores(now, burnStart, S, ship, Mot)

      -- estabilizador: desligado enquanto o Vector Thruster gira a nave, ligado quando ja esta alinhada
      local Fs = porFase[S.phase]
      stabilizer(Fs ~= nil and Fs.estabilizador({ S = S, cfg = CFG, mem = memorias[Fs.nome] }) or false)
      if S.phase == "ORBIT" or S.phase == "FALHA" or S.phase == "FIM" or S.phase == "POUSADO" then
        shutdown(S.stage)
        rcsOff()
        stabilizer(false)
        show({ "== VOO ENCERRADO: " .. S.phase .. " ==", ("Y %.0f  ECC %s"):format(ship.pos.y, tostring(ecc)),
          "Veja: logs erros" })
        break
      end

      lastVel, lastT = ship.vel, now
      tick = tick + 1

      if tick % 2 == 0 then
        Tel.csvLine({ os.epoch("utc") - (S.t0 or 0), S.phase, S.stage, ("%.1f"):format(ship.pos.y),
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
      if Ctl.steerCount() == steerBefore then sleep(0.05) end
    end
  end

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
        tostring(CFG.land_ceiling_y), tostring(CFG.land_speed))
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

  local function limpar()
    pcall(shutdown, S.stage)
    pcall(rcsOff)
    pcall(stabilizer, false)
  end

  return { voo = voo, descer = descer, teste = teste, rcsTeste = rcsTeste, S = S, limpar = limpar }
end

return M
