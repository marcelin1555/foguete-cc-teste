-- dois_estagios: subida com 2 estagios; a lava do 1o acaba, o separador solta ele e o 2o acende
return {
  limite = 80,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={
 {engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1","rocketnautics:vector_thruster_1"}, separator={side="back"}},
 {engines={"rocketnautics:rocket_thruster_2","rocketnautics:vector_thruster_2"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0, padY = 1127 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 1130, 0 }, massa = 150, g = 11, sputnik = "top",
    separadores = { ["computador:back"] = { "rocketnautics:rocket_thruster_0", "rocketnautics:rocket_thruster_1",
      "rocketnautics:vector_thruster_1" } },
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster", lava = 60 },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster", lava = 60 },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster", lava = 60 },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster", lava = 60 },
      ["rocketnautics:vector_thruster_2"] = { tipo = "vector_thruster", lava = 60 },
    },
  },
  passos = { { "voo.lua" } },
}
