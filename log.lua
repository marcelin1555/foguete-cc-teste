-- log.lua : registro de eventos do foguete (log.txt)
-- Niveis: INFO, AVISO, ERRO. Mensagens repetidas sao agrupadas para nao lotar o disco.

local M = {}
-- os arquivos ficam na raiz do computador
local FILE = "/log.txt"
local OLD = "/log_antigo.txt"
local MAX_SIZE = 150 * 1024

local f
local failed = false
local t0 = os.epoch("utc")
local counts = {}
M.recent = {} -- ultimos avisos/erros para mostrar na tela

local function open()
  if f or failed then return f ~= nil end
  pcall(function()
    if fs.exists(FILE) and fs.getSize(FILE) > MAX_SIZE then
      if fs.exists(OLD) then fs.delete(OLD) end
      fs.move(FILE, OLD)
    end
  end)
  local err
  f, err = fs.open(FILE, "a")
  if not f then
    failed = true
    printError("Nao consegui abrir " .. FILE .. ": " .. tostring(err) .. " (disco cheio?)")
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
  f.writeLine(("========== %s  (%s) =========="):format(title, os.date("%d/%m %H:%M:%S")))
  f.flush()
end

return M
