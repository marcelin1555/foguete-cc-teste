-- atualizar.lua : baixa a versao mais nova dos scripts do GitHub
-- Uso: atualizar          -> atualiza todos os scripts
--      atualizar voo.lua  -> atualiza so um arquivo
-- Nao mexe em config.lua, estado.txt nem nos logs.

local REPO = "marcelin1555/foguete-cc-teste"
local BRANCH = "main"
local FILES = {
  "voo.lua", "setup.lua", "log.lua", "logs.lua", "parar.lua",
  "startup.lua", "atualizar.lua", "sputnik_guiagem.lua",
}

if not http then
  printError("HTTP desligado no CC: Tweaked (veja http.enabled no computercraft-server.toml)")
  return
end

local args = { ... }
local list = #args > 0 and args or FILES
local base = ("https://raw.githubusercontent.com/%s/%s/"):format(REPO, BRANCH)
local ok, fail = 0, 0

for _, name in ipairs(list) do
  -- ?t= evita pegar uma copia antiga do cache do GitHub
  local res, err = http.get(base .. name .. "?t=" .. os.epoch("utc"))
  if not res then
    printError(("ERRO %s: %s"):format(name, tostring(err)))
    fail = fail + 1
  else
    local body = res.readAll()
    res.close()
    -- confere a sintaxe antes de trocar o arquivo (sputnik_guiagem usa funcoes da Sputnik, mas compila)
    local fn, perr = load(body, name)
    if not fn then
      printError(("ERRO %s veio com erro de sintaxe, arquivo antigo mantido: %s"):format(name, perr))
      fail = fail + 1
    else
      local f = fs.open(name, "w")
      f.write(body)
      f.close()
      print(("ok  %s (%d bytes)"):format(name, #body))
      ok = ok + 1
    end
  end
end

print(("%d atualizados, %d com erro."):format(ok, fail))
if ok > 0 then
  print("Se mudou o sputnik_guiagem.lua, copie o conteudo dele de novo para o no Lua Script da Sputnik.")
end
