-- lib/foguete/fases/subida.lua : subida com gravity turn (ASCENT) e subida sem combustivel (BALISTICO)
local mat = require("foguete.mat")
local F = { fases = { "ASCENT", "BALISTICO" } }

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
  local mem = ctx.mem
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
      mem.tiltT = mem.tiltT or now
      if now - mem.tiltT > 1 then
        L.err("FOGUETE TOMBANDO: erro de atitude %.0f graus em Y=%.1f. Motores liquidos cortados.", err, ship.pos.y)
        logEngines("tombou")
        shutdown(S.stage)
        setPhase("FALHA", "tombou")
      end
    else
      mem.tiltT = nil
    end
    if S.phase == "BALISTICO" and ship.vel.y < -2 then
      L.err("Sem combustivel antes do espaco: pico Y=%.0f, faltaram %.0f blocos", ship.pos.y, CFG.transfer_y - ship.pos.y)
      setPhase("FALHA", "caindo sem combustivel")
    end
  end
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
end

function F.estabilizador(ctx)
  return ctx.cfg.stab_ascent == true
end

return F
