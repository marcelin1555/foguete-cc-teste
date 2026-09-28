-- config_explicita: land_cc_gimbal = false no config tem que continuar false
return {
  semReferencia = true,
  limite = 30,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0}, land_cc_gimbal=false,
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:vector_thruster_1"}}}, sputnik_guidance=true,
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  mundo = { modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60,
    motores = { ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" } } },
  passos = { { "#arquivo", "t.lua", [[
package.path = "/lib/?.lua;" .. package.path
local cfg = require("foguete.config").carregar("config.lua")
print("land_cc_gimbal=" .. tostring(cfg.land_cc_gimbal) .. " ki=" .. tostring(cfg.ki))
]] }, { "t.lua" } },
  verificar = function(A)
    for _, l in ipairs(A.rastro) do
      if l:find("land_cc_gimbal=false ki=0.6", 1, true) then return {} end
    end
    return { "config.carregar nao preservou land_cc_gimbal=false ou nao aplicou ki=0.6" }
  end,
}
