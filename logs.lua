-- logs.lua : mostra os logs do foguete (um arquivo por voo em /logs)
-- Uso: logs              -> ultimas 40 linhas do voo mais recente
--      logs lista        -> todos os arquivos, do mais novo (1) ao mais velho
--      logs 3            -> ultimas 40 linhas do arquivo 3 da lista
--      logs erros        -> so avisos e erros     (logs 3 erros: do arquivo 3)
--      logs motores      -> estado dos motores
--      logs fisica       -> medicoes de aceleracao
--      logs tudo         -> arquivo inteiro
--      logs limpar       -> apaga todos os logs

local args = { ... }
local DIR = "/logs"

-- arquivos de eventos (.txt), do mais novo para o mais velho
local function listFiles()
  local out = {}
  if fs.exists(DIR) then
    for _, n in ipairs(fs.list(DIR)) do
      if n:match("%.txt$") then out[#out + 1] = n end
    end
  end
  table.sort(out, function(a, b) return a > b end)
  return out
end

if args[1] == "limpar" then
  fs.delete(DIR)
  for _, n in ipairs({ "/log.txt", "/log_antigo.txt", "/voo.log" }) do fs.delete(n) end
  print("Logs apagados.") return
end

local files = listFiles()

if args[1] == "lista" then
  if #files == 0 then print("Nenhum log ainda.") return end
  local lines = {}
  for i, n in ipairs(files) do
    local size = fs.getSize(fs.combine(DIR, n))
    lines[#lines + 1] = ("%2d  %s  (%d KB)"):format(i, n, math.ceil(size / 1024))
  end
  textutils.pagedPrint(table.concat(lines, "\n"))
  return
end

-- qual arquivo: numero da lista (1 = mais novo) ou o mais novo
local pick = 1
if tonumber(args[1]) then pick = tonumber(table.remove(args, 1)) end
local path
if files[pick] then
  path = fs.combine(DIR, files[pick])
elseif fs.exists("/log.txt") and #files == 0 then
  path = "/log.txt" -- log antigo, de antes da pasta /logs
else
  print(#files == 0 and "Ainda nao ha logs." or ("Nao existe o arquivo " .. pick .. ". Veja: logs lista"))
  return
end

local filters = { erros = "AVISO|ERRO", motores = "MOTOR", fisica = "FISICA" }
local flt = filters[args[1] or ""]
local lines = {}
local h = fs.open(path, "r")
for line in h.readLine do
  local keep = true
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
local out = { "--- " .. path .. " ---" }
for i = from, #lines do table.insert(out, lines[i]) end
textutils.pagedPrint(table.concat(out, "\n"))
