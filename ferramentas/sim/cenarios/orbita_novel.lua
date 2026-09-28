-- orbita_novel: COAST -> CIRC -> ORBIT sem o vetor de velocidade da Sputnik
local CONFIG = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]]
local function motores(comRcs)
  local m = {
    ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
    ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
  }
  if comRcs then
    local RT = { { 0.03, 0, 0.004 }, { -0.03, 0.002, 0 }, { 0, 0, 0.03 }, { 0.003, 0, -0.03 }, { 0, 0.02, 0 },
      { 0, -0.02, 0 }, { 0.021, 0, 0.021 }, { -0.021, 0, -0.021 } }
    for i, t in ipairs(RT) do m["rocketnautics:rcs_thruster_" .. i] = { tipo = "rcs_thruster", tq = t } end
  end
  return m
end
return {
  limite = 120,
  config = CONFIG,
  estado = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, q = { 0, 0, 0.3826834, 0.9238795 }, sputnik = "top",
    sputnikVel = nil, orbita = { a = 2760742, e = 0.0958, alt = 22100, subir = true },
    estabilizador = "computador:right", motores = motores(true),
  },
  passos = { { "voo.lua" } },
}
