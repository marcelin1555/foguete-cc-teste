-- config_minima: config sem nenhuma chave opcional; 'voo teste' e pouso ('voo descer 60') usam os padroes
return {
  limite = 120,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "POUSO", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 700, 0 }, vel = { 2, -30, 0 }, g = 11, chao = 60,
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "teste", limite = 20 }, { "voo.lua", "descer", "60" } },
}
