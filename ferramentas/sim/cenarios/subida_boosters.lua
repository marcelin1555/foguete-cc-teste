-- subida_boosters: ASCENT com 4 boosters (um sem carvao), largada dos boosters pelo separador
return {
  limite = 60,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:booster_thruster_0","rocketnautics:booster_thruster_1",
 "rocketnautics:booster_thruster_2","rocketnautics:booster_thruster_3","rocketnautics:rocket_thruster_2",
 "rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}, booster_separator={side="bottom"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0, padY = 1127 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 1130, 0 }, massa = 400, g = 11, sputnik = "top",
    separadores = { ["computador:bottom"] = { "rocketnautics:booster_thruster_0", "rocketnautics:booster_thruster_1",
      "rocketnautics:booster_thruster_2", "rocketnautics:booster_thruster_3" } },
    motores = {
      ["rocketnautics:booster_thruster_0"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_1"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_2"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_3"] = { tipo = "booster_thruster", queima = 15, semCarvao = true },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua" } },
}
