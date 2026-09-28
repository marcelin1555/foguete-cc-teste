-- comandos: voo retomado em COAST, reset, teste, logs e diagnostico
local CONFIG = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]]
return {
  limite = 40,
  config = CONFIG,
  estado = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, q = { 0, 0, 0.3826834, 0.9238795 }, sputnik = "top",
    sputnikVel = "velocity", orbita = { a = 2760742, e = 0.0958, alt = 22100, subir = true },
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = {
    { "voo.lua", limite = 20 },
    { "voo.lua", limite = 10 },         -- retoma no estado que o anterior deixou
    { "voo.lua", "reset" },
    { "voo.lua", "teste", limite = 20 },
    { "logs.lua", "lista" },
    { "logs.lua", "erros" },
    { "diagnostico.lua" },
  },
}
