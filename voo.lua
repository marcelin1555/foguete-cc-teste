-- voo.lua : piloto automatico ate a orbita (Create Cosmonautics + CC: Sable)
-- Uso: voo          -> checagem, espera o botao (ou retoma um voo em andamento)
--      voo teste    -> checagem completa + teste de gimbal, sem acender nada
--      voo reset    -> apaga o estado salvo (novo voo)
--      voo descer [Y]  -> deorbit (se no espaco) e pouso; Y = altura do chao, se souber
--      voo rcs      -> calibra os RCS (nave solta no ar/espaco) e testa por 15 s
-- Registros: um arquivo por voo em /logs, com data e hora no nome (use o programa 'logs')
-- O codigo fica em /lib/foguete (baixado pelo 'atualizar').

local args = { ... }
local MODULOS = { "log", "config", "estado", "mat", "sensores", "sputnik", "motores", "controle",
  "separacao", "checagem", "tela", "telemetria", "rcs", "laco", "fases/plataforma", "fases/subida",
  "fases/orbita", "fases/deorbit", "fases/reentrada", "fases/pouso" }
for _, m in ipairs(MODULOS) do
  if not fs.exists("/lib/foguete/" .. m .. ".lua") then
    printError(("Arquivo lib/foguete/%s.lua faltando, rode atualizar"):format(m))
    return
  end
end
package.path = "/lib/?.lua;" .. package.path

local DIR = fs.getDir(shell.getRunningProgram())
local function path(p) return fs.combine(DIR, p) end
local L = require("foguete.log")
local STATE_FILE = path("estado.txt")

if not fs.exists(path("config.lua")) then
  printError("Rode 'setup' primeiro.") return
end
local CFG, DESCONHECIDAS = require("foguete.config").carregar(path("config.lua"))

if args[1] == "reset" then
  -- registra no log do voo que esta sendo apagado
  if fs.exists(STATE_FILE) then
    local h = fs.open(STATE_FILE, "r") local t = textutils.unserialize(h.readAll()) h.close()
    if type(t) == "table" and t.logFile and fs.exists(t.logFile) then
      L.useFile(t.logFile)
      L.info("Estado apagado (voo reset)")
    end
  end
  fs.delete(STATE_FILE) print("Estado apagado. O proximo voo vai gravar num log novo.") return
end

local V = require("foguete.laco").novo(args, L, CFG, DESCONHECIDAS, STATE_FILE)
local main = (args[1] == "teste") and V.teste or (args[1] == "descer") and V.descer
  or (args[1] == "rcs") and V.rcsTeste or V.voo
local ok, e = xpcall(main, debug.traceback)
if not ok then
  if tostring(e):find("Terminated") then
    L.warn("Programa interrompido (Ctrl+T) na fase %s", tostring(V.S.phase))
  else
    L.err("CRASH do script: %s", tostring(e))
    printError("O script travou! Detalhes em: logs erros")
    printError(tostring(e))
  end
  V.limpar()
end
