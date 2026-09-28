-- lib/foguete/controle.lua : aponta a nave (gimbal PD+I) e liga o Magnetic Stabilizer
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot)
  local S = E.proxy
  local V = vector.new
  local clamp, toLocal = mat.clamp, mat.toLocal
  local call, typeOf, stageEngines = Mot.call, Mot.typeOf, Mot.stageEngines

  -- alinhado de verdade: erro pequeno e a nave quase sem girar (com folga enquanto ja queima)
  local function alignedFor(state, err, ship)
    local w = ship.angv and ship.angv:length() or 0
    local limit = state.burning and (CFG.align_keep_deg) or (CFG.align_deg)
    state.burning = err < limit and (state.burning or w < (CFG.align_rate))
    return state.burning
  end

  local lastW = V(0, 0, 0) -- velocidade angular local (para o log)
  local steerCount = 0      -- quantas vezes o gimbal foi comandado
  -- force = true: o CC controla o gimbal mesmo com sputnik_guidance (manobras no espaco)
  local integ = { x = 0, z = 0, t = nil }
  -- integ = true: acumula o erro (tira o erro parado); so na subida, com motor ligado
  local function steer(ship, target, force, useInteg)
    local d = toLocal(ship.q, target:normalize())
    local ex, ez = d.x, d.z
    if d.y < 0 then
      local m = math.sqrt(ex * ex + ez * ez)
      if m < 1e-6 then ex, m = 1, 1 end
      ex, ez = ex / m, ez / m
    end
    local w = toLocal(ship.q, ship.angv)
    local s, lim = CFG.gimbal_sign, CFG.max_gimbal
    local now = os.clock()
    local ki, imax = CFG.ki, CFG.imax
    if useInteg and integ.t then
      local dt = math.min(now - integ.t, 0.5)
      integ.x = clamp(integ.x + ex * dt, -imax, imax)
      integ.z = clamp(integ.z + ez * dt, -imax, imax)
    elseif not useInteg then
      integ.x, integ.z = 0, 0
    end
    integ.t = now
    local gx = clamp(s * (CFG.kp * ex + CFG.kd * w.z + ki * integ.x), -lim, lim)
    local gz = clamp(s * (CFG.kp * ez - CFG.kd * w.x + ki * integ.z), -lim, lim)
    -- todos os vector thrusters no mesmo tick
    -- (com sputnik_guidance o Sputnik controla o gimbal; o CC so mede o erro)
    local fns = {}
    if force or not CFG.sputnik_guidance then
      for _, name in ipairs(stageEngines(S.stage)) do
        if typeOf(name) == "vector_thruster" then
          fns[#fns + 1] = function() call(name, "setGimbal", gx, 0, gz) end
        end
      end
    end
    if #fns > 0 then parallel.waitForAll(table.unpack(fns)) else sleep(0.05) end
    lastW = w
    steerCount = steerCount + 1
    return math.deg(math.acos(clamp(d.y, -1, 1))), gx, gz
  end

  -- Magnetic Stabilizer (Cosmonautics): com redstone ligado ele FREIA a rotacao da nave.
  -- Nao aponta para nada: o Vector Thruster gira ate o angulo certo e o estabilizador segura ali.
  local stabOn = nil
  local function stabilizer(on)
    local st = CFG.stabilizer
    if not st or stabOn == on then return end
    stabOn = on
    if st.relay then call(st.relay, "setOutput", st.side, on) else redstone.setOutput(st.side, on) end
    L.info("ESTABILIZADOR %s", on and "ligado (segurando o angulo)" or "desligado (livre para girar)")
  end

  return {
    steer = steer, alignedFor = alignedFor, stabilizer = stabilizer,
    lastW = function() return lastW end, steerCount = function() return steerCount end,
  }
end

return M
