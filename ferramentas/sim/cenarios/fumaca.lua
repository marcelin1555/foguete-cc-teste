-- fumaca: 'voo teste' no chao com 4 Rocket + 1 Vector (confere que o simulador roda)
return {
  semReferencia = true,
  limite = 30,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, sputnik = "top",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "teste" } },
  verificar = function(A)
    local erros = {}
    local log = ""
    for k, v in pairs(A.arquivos) do if k:match("^logs/.*teste%.txt$") then log = v end end
    if not log:find("CHECAGEM empuxo_max=5000", 1, true) then erros[#erros + 1] = "preflight nao registrou o empuxo" end
    if not log:find("Teste concluido", 1, true) then erros[#erros + 1] = "teste nao terminou" end
    return erros
  end,
}
