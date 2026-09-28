-- lib/foguete/fases/pouso.lua : pouso controlado: perfil de velocidade, freio lateral e toque no chao (POUSO)
local mat = require("foguete.mat")
local F = { fases = { "POUSO" } }

function F.novaMemoria(S) return { lastErr = 180, lastThr = 0, I = 0 } end

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
  local land = ctx.mem
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
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
end

function F.estabilizador(ctx)
  return ctx.mem.lastErr < (ctx.cfg.land_align_deg)
end

return F
