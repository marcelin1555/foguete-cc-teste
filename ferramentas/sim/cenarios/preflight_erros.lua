-- preflight_erros: sem Vector Thruster e TWR baixo -> erros na checagem
return {
  limite = 20,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, sputnik="top", turn_end_y=16000,
 gimbal_sign=1, transfer_y=20000, kp_errado=3 }]],
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, massa = 400, sputnik = "top",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_9"] = { tipo = "rocket_thruster" },
    },
  },
  passos = { { "voo.lua", "teste" } },
}
