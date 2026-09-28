-- lancamento: preflight na plataforma, tecla L, contagem e subida
return {
  limite = 45,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=3, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]],
  eventos = { { "char", "l" } },
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, g = 11, sputnik = "top", estabilizador = "computador:right",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua" } },
}
