-- lib/foguete/fases/orbita.lua : espera o apoastro (COAST) e circulariza (CIRC)
local mat = require("foguete.mat")
local F = { fases = { "COAST", "CIRC" } }

function F.novaMemoria(S) return { flips = 0, bestEcc = math.huge } end

function F.tick(ctx)
  local S, CFG, L, save, setPhase = ctx.S, ctx.cfg, ctx.log, ctx.salvar, ctx.trocar
  local Mot, Ctl, Sp, Rcs, Sens = ctx.mot, ctx.ctl, ctx.sp, ctx.rcs, ctx.sens
  local setThrottle, orientThrottle, shutdown, ignite = Mot.setThrottle, Mot.orientThrottle, Mot.shutdown, Mot.ignite
  local stageEngines, typeOf, logEngines = Mot.stageEngines, Mot.typeOf, Mot.logEngines
  local steer, alignedFor = Ctl.steer, Ctl.alignedFor
  local orbitDir, periAlt, readShip = Sp.orbitDir, Sp.periAlt, Sens.readShip
  local rcs, rcsReady, rcsControl, rcsCalibrate, rcsOff = Rcs.estado, Rcs.ready, Rcs.control, Rcs.calibrate, Rcs.off
  local V, UP, EAST, clamp, qrot = vector.new, mat.UP, ctx.EAST, mat.clamp, mat.qrot
  local ship, now, dt, slow = ctx.nave, ctx.agora, ctx.dt, ctx.lento
  local o = ctx.orb
  local g, dsd, inSpace, ecc, dist, vr = o.g, o.dsd, o.inSpace, o.ecc, o.dist, o.vr
  local tilt, err, gx, gz = 0, 0, 0, 0
  local orb = ctx.mem
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
    if slow and dsd and ((o.vrOk and vr <= 1) or (peri == peri and peri >= alvo)) then
      orb.bestEcc = math.huge
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
    if ecc == ecc and ecc < orb.bestEcc then orb.bestEcc = ecc end
    if slow and peri == peri and peri >= alvo then
      shutdown(S.stage)
      setPhase("ORBIT", ("periastro=%.0f ecc=%s"):format(peri, tostring(ecc)))
    elseif slow and ecc == ecc and orb.bestEcc < 0.3 and ecc > orb.bestEcc + 0.005 and peri == peri and peri > 0 then
      -- passou do ponto: a queima comecou a esticar a orbita do outro lado
      shutdown(S.stage)
      setPhase("ORBIT", ("ecc voltou a subir, periastro=%.0f ecc=%.4f"):format(peri, ecc))
    end
  end
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
end

function F.estabilizador(ctx)
  if ctx.S.phase == "COAST" then return not ctx.mem.orienting end
  return ctx.mem.burning == true
end

return F
