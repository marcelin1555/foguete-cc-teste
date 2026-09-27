-- log.lua : registro de eventos do foguete
-- Cada voo grava num arquivo proprio dentro de /logs, com data e hora no nome:
--   /logs/2026-09-27_19-32-50_voo.txt            eventos (use o programa 'logs')
--   /logs/2026-09-27_19-32-50_voo_telemetria.csv telemetria do voo
-- Niveis: INFO, AVISO, ERRO. Mensagens repetidas sao agrupadas para nao lotar o disco.
-- Os arquivos mais antigos sao apagados quando a pasta passa do limite.

local M = {}
M.DIR = "/logs"
local MAX_FILES = 40            -- arquivos na pasta (eventos + telemetria)
local MAX_TOTAL = 500 * 1024    -- bytes somando todos os arquivos
local MAX_FILE = 200 * 1024     -- um arquivo de eventos nao passa disso

local file         -- caminho do arquivo de eventos em uso
local f
local failed = false
local t0 = os.epoch("utc")
local counts = {}
M.recent = {} -- ultimos avisos/erros para mostrar na tela

-- apaga os arquivos mais antigos (o nome comeca com a data, entao ordem alfabetica = ordem de tempo)
local function cleanup()
  if not fs.exists(M.DIR) then return end
  local names = fs.list(M.DIR)
  table.sort(names)
  local total = 0
  for _, n in ipairs(names) do total = total + fs.getSize(fs.combine(M.DIR, n)) end
  local i = 1
  while i <= #names and (#names - i + 1 > MAX_FILES or total > MAX_TOTAL) do
    local p = "/" .. (fs.combine(M.DIR, names[i]):gsub("^/+", ""))
    if p ~= file then
      total = total - fs.getSize(p)
      fs.delete(p)
    end
    i = i + 1
  end
end

local function closeFile()
  if f then pcall(f.close) end
  f = nil
end

-- comeca um arquivo novo: /logs/AAAA-MM-DD_HH-MM-SS_<tipo>.txt
function M.newFile(kind)
  closeFile()
  failed = false
  if not fs.exists(M.DIR) then fs.makeDir(M.DIR) end
  local base = os.date("%Y-%m-%d_%H-%M-%S") .. (kind and ("_" .. kind) or "")
  file = "/" .. (fs.combine(M.DIR, base .. ".txt"):gsub("^/+", ""))
  pcall(cleanup)
  return file
end

-- continua num arquivo que ja existe (voo retomado depois de reiniciar o computador)
function M.useFile(path)
  if not path then return M.newFile("voo") end
  closeFile()
  failed = false
  file = path
  return file
end

function M.currentFile() return file end

-- arquivo de telemetria que acompanha o arquivo de eventos atual
function M.csvPath()
  if not file then M.newFile("sessao") end
  return (file:gsub("%.txt$", "")) .. "_telemetria.csv"
end

local function open()
  if f then return true end
  if failed then return false end
  if not file then M.newFile("sessao") end
  if fs.exists(file) and fs.getSize(file) > MAX_FILE then
    -- arquivo grande demais: continua numa parte 2, 3...
    local n = tonumber(file:match("_parte(%d+)%.txt$") or "1") + 1
    file = file:gsub("_parte%d+%.txt$", ".txt"):gsub("%.txt$", "_parte" .. n .. ".txt")
  end
  local err
  f, err = fs.open(file, "a")
  if not f then
    failed = true
    printError("Nao consegui abrir " .. file .. ": " .. tostring(err) .. " (disco cheio? rode: logs limpar)")
  end
  return f ~= nil
end

function M.write(level, msg, ...)
  msg = tostring(msg)
  if select("#", ...) > 0 then
    local ok, s = pcall(string.format, msg, ...)
    msg = ok and s or (msg .. " [erro de formato]")
  end
  counts[level .. msg] = (counts[level .. msg] or 0) + 1
  local n = counts[level .. msg]
  if n > 3 and n % 50 ~= 0 then return end
  local line = ("[%7.2f] %-5s %s%s"):format((os.epoch("utc") - t0) / 1000, level, msg,
    n > 3 and (" (repetido x" .. n .. ")") or "")
  if open() then
    f.writeLine(line)
    f.flush()
  end
  if level ~= "INFO" then
    table.insert(M.recent, level .. " " .. msg)
    if #M.recent > 3 then table.remove(M.recent, 1) end
  end
end

function M.info(...) M.write("INFO", ...) end
function M.warn(...) M.write("AVISO", ...) end
function M.err(...) M.write("ERRO", ...) end

function M.section(title)
  t0 = os.epoch("utc")
  counts = {}
  if not open() then return end
  f.writeLine("")
  f.writeLine(("========== %s  (%s) =========="):format(title, os.date("%d/%m/%Y %H:%M:%S")))
  f.flush()
end

return M
