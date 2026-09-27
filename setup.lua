-- setup.lua : configura o foguete e gera config.lua
-- Rode com o foguete montado e todos os motores ligados por modem ao computador.

local function ask(prompt, default)
  write(prompt .. (default and (" [" .. tostring(default) .. "]") or "") .. ": ")
  local r = read()
  if r == "" then return default end
  return r
end

print("=== SETUP DO FOGUETE ===")
if not sublevel or not sublevel.isInPlotGrid() then
  printError("AVISO: este computador nao esta em uma nave (Sub-Level).")
  printError("Monte o foguete (Physics Assembler) antes de rodar o setup.")
end

-- Motores
local engines = {}
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name, "thruster") then
    local ok, data = pcall(peripheral.call, name, "getData")
    local t = ok and data.engine_type or "?"
    table.insert(engines, { name = name, type = t })
  end
end
if #engines == 0 then
  printError("Nenhum motor encontrado! Coloque um Wired Modem em cada motor,")
  printError("ligue com cabo ate o computador e clique no modem (fica vermelho).")
  return
end
table.sort(engines, function(a, b) return a.name < b.name end)

print(("Encontrei %d motores. Diga o estagio de cada um (1 = primeiro a queimar)."):format(#engines))
print("Dica: rode 'voo teste' depois para ver qual motor e qual.")
local nStages = 1
for _, e in ipairs(engines) do
  local def = (e.type == "booster_thruster") and 1 or nil
  local s
  repeat
    s = tonumber(ask(("  %s (%s) estagio"):format(e.name, e.type), def))
  until s and s >= 1
  e.stage = s
  if s > nStages then nStages = s end
end

-- Separadores
local stages = {}
for i = 1, nStages do
  local st = { engines = {} }
  for _, e in ipairs(engines) do
    if e.stage == i then table.insert(st.engines, e.name) end
  end
  if i < nStages then
    print(("Estagio %d -> separador. Lado do computador que manda o pulso"):format(i))
    local side = ask("  (top/bottom/left/right/front/back, ou nome de redstone_relay)", "back")
    if peripheral.hasType(side, "redstone_relay") then
      st.separator = { relay = side, side = ask("  lado do relay", "top") }
    else
      st.separator = { side = side }
    end
  end
  stages[i] = st
end

-- Sputnik / monitor
local sp = peripheral.find("sputnik")
local spName = sp and peripheral.getName(sp) or nil
if not spName then
  printError("Sem Sputnik! Ele e necessario para a fase orbital (e mantem o chunk carregado).")
end
local mon = peripheral.find("monitor")

local cfg = {
  stages = stages,
  sputnik = spName,
  monitor = mon and peripheral.getName(mon) or nil,
  launch_side = ask("Lado do computador ligado ao BOTAO de lancamento", "left"),
  east = { 1, 0, 0 },           -- direcao do gravity turn (+X)
  max_thrust_n = tonumber(ask("Empuxo maximo por motor em N (1000, ou 5000 com brokenBarrier)", 1000)),
  transfer_y = 20000,           -- altura em que o Overworld vira deep_space
  turn_start_alt = 250,         -- metros acima da plataforma para comecar a inclinar
  turn_end_y = 16000,           -- Y onde a inclinacao chega no maximo
  turn_end_angle = 55,          -- graus a partir da vertical no fim do turn
  max_twr = 2.5,                -- limita aceleracao nos motores liquidos
  min_twr = 1.15,               -- nao lanca abaixo disso
  kp = 1.5, kd = 0.8,           -- ganhos do controle de atitude
  max_gimbal = 0.6,            -- limite do gimbal (0..1)
  gimbal_sign = 1,              -- troque para -1 se o foguete corrigir para o lado errado
  steer_throttle = 0.08,        -- empuxo minimo usado so para girar no espaco
  ecc_target = 0.02,            -- excentricidade alvo da orbita
  countdown = 10,
}

local f = fs.open("config.lua", "w")
f.write("return " .. textutils.serialize(cfg))
f.close()
print("config.lua salvo! Rode 'voo teste' e depois reinicie o computador.")
