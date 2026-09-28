-- descida_pesada: como descida, com massa 40000 (a queima de deorbit dura varios ticks)
return {
  limite = 400,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]],
  estado = '{ phase = "ORBIT", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, massa = 40000, sputnik = "top", sputnikVel = "velocity", g = 11, chao = 60,
    orbita = { a = 3025200, e = 0, alt = 25200 }, reentra = { pos = { 0, 1500, 0 }, vel = { 3, -60, 0 } },
    estabilizador = "computador:right",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "descer", "60" } },
}
