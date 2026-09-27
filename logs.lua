-- logs.lua : mostra o log do foguete
-- Uso: logs            -> ultimas 40 linhas
--      logs erros      -> so avisos e erros
--      logs motores    -> estado dos motores
--      logs fisica     -> medicoes de aceleracao
--      logs tudo       -> arquivo inteiro
--      logs limpar     -> apaga os logs

local args = { ... }
local DIR = fs.getDir(shell.getRunningProgram())
local FILE = fs.combine(DIR, "log.txt")

if args[1] == "limpar" then
  for _, n in ipairs({ "log.txt", "log_antigo.txt", "voo.log" }) do fs.delete(fs.combine(DIR, n)) end
  print("Logs apagados.") return
end
if not fs.exists(FILE) then print("Ainda nao ha log.txt") return end

local filters = { erros = "AVISO|ERRO", motores = "MOTOR", fisica = "FISICA" }
local lines = {}
local h = fs.open(FILE, "r")
for line in h.readLine do
  local keep = true
  local flt = filters[args[1] or ""]
  if flt then
    keep = line:find("=====", 1, true) ~= nil
    for word in flt:gmatch("[^|]+") do
      if line:find(word, 1, true) then keep = true end
    end
  end
  if keep then table.insert(lines, line) end
end
h.close()

local from = (args[1] == "tudo") and 1 or math.max(1, #lines - 39)
local out = {}
for i = from, #lines do table.insert(out, lines[i]) end
textutils.pagedPrint(table.concat(out, "\n"))
