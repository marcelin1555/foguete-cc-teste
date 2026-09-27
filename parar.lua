-- parar.lua : DESLIGA todos os motores liquidos conectados (emergencia)
-- Boosters solidos nao podem ser desligados depois de acesos.
local n = 0
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name, "thruster") then
    local ok, d = pcall(peripheral.call, name, "getData")
    if ok and d and d.engine_type ~= "booster_thruster" then
      pcall(peripheral.call, name, "setThrust", 0)
      pcall(peripheral.call, name, "setActive", false)
      n = n + 1
      print("desligado: " .. name)
    end
  end
end
if fs.exists("estado.txt") then
  local f = fs.open("estado.txt", "r") local s = f.readAll() f.close()
  if s:find('phase = "ASCENT"') or s:find('phase = "CIRC"') or s:find('phase = "COAST"') then
    fs.delete("estado.txt")
    print("Voo em andamento cancelado (estado apagado).")
  end
end
print(("%d motores desligados."):format(n))
