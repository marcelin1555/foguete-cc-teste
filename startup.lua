-- startup.lua : liga o piloto automatico sozinho (e retoma o voo se o computador reiniciar
-- ao trocar de dimensao em Y=20000)
if fs.exists("config.lua") then
  shell.run("voo")
else
  print("Foguete sem configuracao. Rode: setup")
end
