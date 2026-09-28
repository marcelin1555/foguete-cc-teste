-- atualizar.lua : baixa a versao mais nova dos scripts do GitHub
-- Uso: atualizar          -> atualiza tudo (a lista vem do arquivos.txt do GitHub)
--      atualizar voo.lua  -> atualiza so um arquivo
-- Nao mexe em config.lua, estado.txt, rcs.cal nem nos logs.
-- Tudo ou nada: baixa e confere a sintaxe de todos os arquivos antes de gravar.

local REPO = "marcelin1555/foguete-cc-teste"
local BRANCH = "main"
local PROTEGIDOS = { ["config.lua"] = true, ["estado.txt"] = true, ["rcs.cal"] = true }

if not http then
  printError("HTTP desligado no CC: Tweaked (veja http.enabled no computercraft-server.toml)")
  return
end

local args = { ... }
local base = ("https://raw.githubusercontent.com/%s/%s/"):format(REPO, BRANCH)

local function baixar(nome)
  -- ?t= evita pegar uma copia antiga do cache do GitHub
  local res, err = http.get(base .. nome .. "?t=" .. os.epoch("utc"))
  if not res then return nil, tostring(err) end
  local body = res.readAll()
  res.close()
  return body
end

local function protegido(nome) return PROTEGIDOS[nome] or nome:match("^logs/") ~= nil end

-- lista de arquivos
local lista, remover = {}, {}
if #args > 0 then
  lista = args
else
  local txt, err = baixar("arquivos.txt")
  if not txt then printError("ERRO ao baixar arquivos.txt: " .. err .. ". Nada foi trocado.") return end
  local secao = lista
  for bruta in txt:gmatch("[^\r\n]+") do
    local linha = bruta:match("^%s*(.-)%s*$")
    if linha == "remover:" then secao = remover
    elseif linha ~= "" and not linha:match("^#") then secao[#secao + 1] = linha end
  end
end

-- 1) baixa e confere tudo antes de gravar qualquer coisa
local novos = {}
for _, nome in ipairs(lista) do
  if protegido(nome) then
    printError("ignorado (arquivo do foguete): " .. nome)
  else
    local body, err = baixar(nome)
    if not body then
      printError(("ERRO %s: %s. Nada foi trocado."):format(nome, err))
      return
    end
    if nome:match("%.lua$") then
      local fn, perr = load(body, nome)
      if not fn then
        printError(("ERRO %s veio com erro de sintaxe: %s. Nada foi trocado."):format(nome, perr))
        return
      end
    end
    novos[#novos + 1] = { nome = nome, body = body }
  end
end

-- 2) grava
local sputnikMudou = false
for _, a in ipairs(novos) do
  if a.nome == "sputnik_guiagem.lua" then
    local antigo
    if fs.exists(a.nome) then local f = fs.open(a.nome, "r") antigo = f.readAll() f.close() end
    sputnikMudou = antigo ~= a.body
  end
  local dir = fs.getDir(a.nome)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(a.nome, "w")
  f.write(a.body)
  f.close()
  print(("ok  %s (%d bytes)"):format(a.nome, #a.body))
end
for _, nome in ipairs(remover) do
  if not protegido(nome) and fs.exists(nome) then
    fs.delete(nome)
    print("removido " .. nome)
  end
end

print(("%d arquivos atualizados."):format(#novos))
if sputnikMudou then
  print("O sputnik_guiagem.lua mudou: copie o conteudo dele de novo para o no Lua Script da Sputnik.")
end
if not fs.exists("lib/foguete/laco.lua") then
  print("Rode 'atualizar' de novo para baixar a pasta /lib.")
end
