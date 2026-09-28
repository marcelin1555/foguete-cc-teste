-- instalacao_incompleta: falta um modulo em /lib -> mensagem clara e nenhum motor acionado
return {
  semReferencia = true,
  limite = 10,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0}, turn_start_alt=250,
 turn_end_angle=55, stages={{engines={"rocketnautics:vector_thruster_1"}}}, max_gimbal=0.6, launch_side="left",
 min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0 }',
  mundo = { modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60,
    motores = { ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" } } },
  passos = { { "#arquivo", "lib/foguete/fases/pouso.lua", false }, { "voo.lua" } },
  verificar = function(A)
    local erros, msg = {}, false
    for _, l in ipairs(A.rastro) do
      if l:find("call ", 1, true) then erros[#erros + 1] = "acionou periferico: " .. l end
      if l:find("Arquivo lib/foguete/fases/pouso.lua faltando, rode atualizar", 1, true) then msg = true end
    end
    if not msg then erros[#erros + 1] = "sem a mensagem de arquivo faltando" end
    return erros
  end,
}
