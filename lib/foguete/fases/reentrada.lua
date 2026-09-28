-- lib/foguete/fases/reentrada.lua : motores desligados, esperando voltar ao overworld (REENTRADA)
local mat = require("foguete.mat")
local F = { fases = { "REENTRADA" } }

function F.novaMemoria(S) return {} end

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
  -- motores desligados, esperando voltar ao overworld
  if slow and dsd and not inSpace then
    ignite(S.stage)
    setThrottle(S.stage, 0)
    setPhase("POUSO", "voltou ao overworld")
  end
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
end

function F.estabilizador(ctx)
  return true
end

return F
