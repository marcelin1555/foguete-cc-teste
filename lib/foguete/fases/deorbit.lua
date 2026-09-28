-- lib/foguete/fases/deorbit.lua : queima contra o movimento orbital ate o periastro baixar (DEORBIT)
local mat = require("foguete.mat")
local F = { fases = { "DEORBIT" } }

function F.novaMemoria(S) return { sign = S.deorbitSign or 1, lastPeri = nil, lastT = os.clock(), flips = 0 } end

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
  local deorbit = ctx.mem
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
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
end

function F.estabilizador(ctx)
  return ctx.mem.burning == true
end

return F
