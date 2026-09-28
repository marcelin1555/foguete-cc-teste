-- voo.lua : piloto automatico ate a orbita (Create Cosmonautics + CC: Sable)
-- Uso: voo          -> checagem, espera o botao (ou retoma um voo em andamento)
--      voo teste    -> checagem completa + teste de gimbal, sem acender nada
--      voo reset    -> apaga o estado salvo (novo voo)
--      voo descer [Y]  -> deorbit (se no espaco) e pouso; Y = altura do chao, se souber
--      voo rcs      -> calibra os RCS (nave solta no ar/espaco) e testa por 15 s
-- Registros: um arquivo por voo em /logs, com data e hora no nome (use o programa 'logs')

local args = { ... }
package.path = "/lib/?.lua;" .. package.path
local DIR = fs.getDir(shell.getRunningProgram())
local function path(p) return fs.combine(DIR, p) end
local L = require("foguete.log")
local STATE_FILE = path("estado.txt")

if not fs.exists(path("config.lua")) then
  printError("Rode 'setup' primeiro.") return
end
local CFG, DESCONHECIDAS = require("foguete.config").carregar(path("config.lua"))

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
  if S.phase == "DEORBIT" then orientThrottle(S.stage) end
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
  local Tel = require("foguete.telemetria").novo(L, csvLine)
  local slowT = -1
  local orbT = -math.huge
  local tiltT = nil
  local orb = { flips = 0 }
  local bestEcc = math.huge
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

    local since = now - igniteT
    if slow and since > 0.5 and since < 4 then Sep.confirmarIgnicao(S.stage, since, boosterRetry) end

    if slow and now - burnStart > 1 then checkBoosterDrop(S.stage) end

    if slow and S.phase == "ASCENT" and now - burnStart > 2 then Mot.equilibrar(now) end

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
        if S.phase == "ASCENT" then setThrottle(S.stage, 1) else orientThrottle(S.stage) end
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
      local alvo = CFG.deorbit_peri
      if slow and dsd and not inSpace then
        setPhase("POUSO", "saiu do espaco durante o deorbit")
      elseif dsd and dsd.velocity and dsd.velocity.x == dsd.velocity.x then
        local dv = V(dsd.velocity.x, dsd.velocity.y, dsd.velocity.z)
        local target = dv:length() > 1e-6 and dv:normalize() * (-deorbit.sign) or UP
        err, gx, gz = steer(ship, target, true)
        local burning = alignedFor(deorbit, err, ship)
        if burning then setThrottle(S.stage, 1) else orientThrottle(S.stage) end
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
      local off = CFG.land_offset          -- altura do centro de massa com a nave no chao
      local h = groundY and (ship.pos.y - groundY - off) or nil
      local slowTop = groundY and (groundY + off + (CFG.land_slow_h)) or (CFG.land_ceiling_y)
      local hTop = ship.pos.y - slowTop          -- altura acima da zona de descida lenta

      local nEng = 0
      for _, n in ipairs(stageEngines(S.stage)) do
        if typeOf(n) ~= "booster_thruster" then nEng = nEng + 1 end
      end
      local Fmax = nEng * CFG.max_thrust_n
      local aMax = Fmax / math.max(ship.mass, 1) - gUse
      local vFinal = CFG.land_speed

      -- velocidade vertical alvo
      local vT
      if hTop > 0 then
        local aB = math.max(aMax * 0.5, 0.5)
        vT = -math.max(vFinal, math.sqrt(2 * aB * hTop))
        vT = math.max(vT, -(CFG.land_max_speed))
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
        local aHmax = CFG.land_h_accel
        if aH:length() > aHmax then aH = aH * (aHmax / aH:length()) end
      end
      -- inclinacao maxima: 60 graus longe do chao, 25 graus perto
      local tanMax = math.tan(math.rad(hTop > 0 and (CFG.land_max_tilt_high) or (CFG.land_max_tilt)))
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
      if aMax <= 0.5 then
        thr = 1
        if slow then L.err("Empuxo insuficiente para pousar (a_max=%.2f)", aMax) end
      end
      -- primeiro aponta, depois acende: desalinhado, so o Vector Thruster empurra (para girar)
      local okAng = land.lastErr < (CFG.land_align_deg)
      if okAng then
        setThrottle(S.stage, thr)
      elseif rcsReady() then
        setThrottle(S.stage, 0)
      else
        orientThrottle(S.stage)
      end

      err, gx, gz = steer(ship, tgt, CFG.land_cc_gimbal)
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
      land.lastVy, land.lastThr, land.lastErr = vy, (Mot.ultimoAcelerador(S.stage) or 0), err
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
        if err >= 10 and now - orb.rcsT > (CFG.rcs_timeout) then
          rcs.failed = true
          rcsOff()
          L.warn("RCS nao conseguiu apontar a nave em %ds (erro %.0f): girando com o motor principal", CFG.rcs_timeout, err)
          useRcs = false
        end
      end
      local peri = periAlt(dsd)
      local sma = dsd and dsd.semiMajorAxis
      local alvo = math.min(CFG.orbit_peri_alt, (dist == dist and dist or 1e9) - 300)

      if S.phase == "COAST" then
        -- ja vai apontando para a queima: com RCS nao gasta lava; sem RCS so o Vector Thruster empurra
        -- histerese: comeca a girar acima de 5 graus e so para quando estiver a menos de 2 e quase sem girar
        local w = ship.angv and ship.angv:length() or 0
        if err > (CFG.align_deg) then orb.orienting = true end
        if err < 2 and w < 0.02 then orb.orienting = false end
        if not useRcs and orb.orienting then orientThrottle(S.stage) else setThrottle(S.stage, 0) end
        if slow and dsd and ((orb.vrOk and vr <= 1) or (peri == peri and peri >= alvo)) then
          bestEcc = math.huge
          setPhase("CIRC", ("apoastro, vr=%.2f ecc=%s periastro=%.0f alvo=%.0f"):format(vr, tostring(ecc), peri, alvo))
        end
      else
        local aligned = alignedFor(orb, err, ship)
        -- perto do alvo reduz o empuxo para nao passar do ponto
        local falta = (peri == peri) and (alvo - peri) or math.huge
        local full = clamp(falta / (CFG.circ_slow_m), 0.2, 1)
        if aligned then
          setThrottle(S.stage, full)
        elseif useRcs then
          setThrottle(S.stage, 0)
        else
          orientThrottle(S.stage)
        end
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

    Tel.fisica(ship, now, thrust, g, err, gx, gz, Ctl.lastW())
    Tel.motores(now, burnStart, S, ship, Mot)

    -- estabilizador: desligado enquanto o Vector Thruster gira a nave, ligado quando ja esta alinhada
    local wantStab = false
    if S.phase == "COAST" then wantStab = not orb.orienting
    elseif S.phase == "CIRC" then wantStab = orb.burning == true
    elseif S.phase == "DEORBIT" then wantStab = deorbit.burning == true
    elseif S.phase == "REENTRADA" then wantStab = true
    elseif S.phase == "POUSO" then wantStab = land.lastErr < (CFG.land_align_deg)
    elseif S.phase == "ASCENT" or S.phase == "BALISTICO" then wantStab = CFG.stab_ascent == true
    end
    stabilizer(wantStab)
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
  pcall(stabilizer, false)
end
