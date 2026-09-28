# Refatoração em módulos: plano de implementação

> **Para quem for executar:** SUB-SKILL OBRIGATÓRIA: usar superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar tarefa por tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** dividir o `voo.lua` (1406 linhas) em módulos pequenos em `/lib/foguete/`, sem mudar o comportamento do voo, e provar isso com um simulador que compara o código novo com uma referência gravada do código antigo.

**Arquitetura:** um simulador em Lua (`ferramentas/sim/`) imita o CC: Tweaked e o mundo, e grava um "rastro" (comandos aos periféricos, redstone, textos na tela, logs e estado final). Primeiro se grava a referência com o código atual; depois cada extração de módulo precisa reproduzir o rastro **exatamente**. O código é **movido**, não reescrito: os trechos saem do `voo.lua` para os módulos com o mínimo de alterações (troca de nomes listada em cada tarefa).

**Tecnologia:** Lua 5.x (CC: Tweaked), Python 3 com `lupa` (Lua 5.4) para rodar o simulador.

**Spec:** `docs/superpowers/specs/2026-09-28-refatoracao-modulos-design.md`

## Restrições globais

- Commits no nome `marcelin1555 <147268877+marcelin1555@users.noreply.github.com>`, **sem** trailer de IA e **sem** `Co-Authored-By`.
- Mensagens de commit, comentários e textos em português, sem acentos dentro dos arquivos `.lua` (padrão do projeto).
- Nomes de fase, campos do `estado.txt`, nomes de chaves do `config.lua`, comandos digitados e textos das linhas de log **não mudam**.
- `sputnik_guiagem.lua` só ganha a linha `-- versao: 1` no topo.
- `parar.lua`, `diagnostico.lua`, `logs.lua`, `setup.lua` e `startup.lua` não mudam.
- Nenhum módulo passa de ~250 linhas.
- Depois de cada tarefa de extração, `py ferramentas/sim/testar.py` tem que terminar sem `DIFERENTE`.
- Diretório de trabalho: raiz do clone do repositório, branch `refatoracao-modulos`.

## Pontos de atenção na revisão

1. **Atualização interrompida** (rede cai no meio do `atualizar`): nenhum arquivo pode ser trocado. Teste no cenário `atualizar` (Tarefa 9).
2. **Chave booleana explícita `false` no config** (`land_cc_gimbal = false`): o padrão não pode sobrescrever o `false`. Teste no cenário `config_explicita` (Tarefa 3).
3. **Instalação incompleta** (falta um arquivo de `/lib/foguete`): o `voo` tem que mostrar "Arquivo lib/foguete/X.lua faltando, rode atualizar" e não acionar nenhum motor. Teste no cenário `instalacao_incompleta` (Tarefa 8).
4. **`estado.txt` com fase desconhecida:** o `voo` não pode acender motores; ele mostra a mensagem para usar `voo reset`. Teste no cenário `fase_desconhecida` (Tarefa 8).
5. **Reboot na troca de dimensão durante a descida:** o voo precisa continuar da REENTRADA para o POUSO no mesmo log. Teste no cenário `descida` (Tarefa 2, referência).

---

## Mapa de arquivos

| Arquivo | Tarefa | Responsabilidade |
|---|---|---|
| `ferramentas/sim/ambiente.lua` | 1 | CC imitado + gravador do rastro |
| `ferramentas/sim/mundo.lua` | 1 | Nave, motores, Sputnik, relays, física |
| `ferramentas/sim/rodar.lua` | 1 | Executa um cenário e devolve o rastro |
| `ferramentas/sim/testar.py` | 1 | Roda os cenários, grava ou compara a referência |
| `ferramentas/sim/cenarios/*.lua` | 1, 2, 3, 8, 9 | Cenários |
| `ferramentas/sim/referencia/*.txt` | 2 | Rastros gravados com o código antigo |
| `lib/foguete/log.lua` | 3 | Movido da raiz, sem alteração |
| `lib/foguete/mat.lua` | 3 | clamp, qrot, toLocal, quatParts, periNames, UP |
| `lib/foguete/config.lua` | 3 | Padrões + carregamento + chaves desconhecidas |
| `lib/foguete/estado.lua` | 3 | estado.txt: salvar, carregar, trocar |
| `lib/foguete/sensores.lua` | 4 | readShip, gravity |
| `lib/foguete/motores.lua` | 4 | Periféricos de motor, acelerador, equilíbrio |
| `lib/foguete/sputnik.lua` | 4 | Dados da Sputnik, orbitDir, periAlt |
| `lib/foguete/controle.lua` | 5 | steer, alignedFor, stabilizer |
| `lib/foguete/separacao.lua` | 5 | Pulsos, separar, boosters |
| `lib/foguete/tela.lua` | 5 | show |
| `lib/foguete/telemetria.lua` | 5 | CSV, FISICA, COMBUSTIVEL/MOTOR periódicos |
| `lib/foguete/rcs.lua` | 6 | RCS (inerte sem `rcs_enabled`) + `voo rcs` |
| `lib/foguete/checagem.lua` | 6 | preflight, teste |
| `lib/foguete/fases/*.lua` | 7 | plataforma, subida, orbita, deorbit, reentrada, pouso |
| `lib/foguete/laco.lua` | 7 | Laço principal, descer, reset |
| `voo.lua` | 3–8 | Vira só a entrada (argumentos, checagem de arquivos, xpcall) |
| `arquivos.txt` | 9 | Lista do atualizador |
| `atualizar.lua` | 9 | Tudo ou nada, lê `arquivos.txt` |
| `README.md`, `HANDOFF.md` | 10 | Documentação |

Linhas citadas como "voo.lua:A-B" referem-se ao `voo.lua` do commit `0108ff2` (antes da refatoração). Para consultar: `git show 0108ff2:voo.lua | sed -n 'A,Bp'`.

---

### Tarefa 1: simulador unificado

**Arquivos:**
- Criar: `ferramentas/sim/ambiente.lua`, `ferramentas/sim/mundo.lua`, `ferramentas/sim/rodar.lua`, `ferramentas/sim/testar.py`, `ferramentas/sim/cenarios/fumaca.lua`

**Interfaces:**
- Produz: `testar.py [nomes...] [--gravar]`. Um cenário é um arquivo Lua que devolve `{ limite, config, estado, mundo, passos, eventos, entradas, arquivos, semReferencia, servirRepo, verificar }`. Passos: `{ "prog.lua", args..., limite = N }`; pseudo-passos `{ "#arquivo", caminho, conteudo_ou_false }` e `{ "#servidor", caminho, conteudo_ou_false }`.
- O mundo aceita: `modo` ("espaco"/"atmosfera"), `q`, `pos`, `vel`, `massa`, `g`, `chao`, `motores` (nome → `{tipo, lava, tq, potencia, queima, semCarvao}`), `sputnik` (nome do periférico), `sputnikVel` ("velocity"/"inverted"/nil), `orbita` `{a, e, alt, subir}`, `reentra` `{pos, vel}`, `relays`, `separadores` ("origem:lado" → lista de motores), `estabilizador` ("origem:lado").

- [ ] **Passo 1: criar `ferramentas/sim/ambiente.lua`**

```lua
-- ferramentas/sim/ambiente.lua
-- CC: Tweaked imitado para rodar os scripts do foguete fora do jogo.
-- Define as APIs globais (fs, os, peripheral, parallel...) e grava um "rastro"
-- (A.rastro) com o que o script faz de visivel: comandos aos perifericos,
-- redstone e textos na tela. A fisica fica em mundo.lua.
local A = {}
A.arquivos = {}          -- sistema de arquivos em memoria: caminho -> conteudo
A.servidor = {}          -- arquivos servidos pelo "GitHub" (http.get)
A.relogio = 0            -- segundos simulados
A.rastro = {}
A.eventos = {}           -- fila de eventos: { "char", "l" }
A.limite = 120           -- relogio em que o programa atual e encerrado
A.entradas = {}          -- respostas de read()
A.redstoneEntrada = {}   -- lado -> true
A.passo = function() end -- mundo.lua troca por sua fisica
A.PARAR = {}             -- sentinela: encerra o programa sem passar pelos pcall dele
A.pedido = nil           -- "fim" (tempo esgotado) ou "reboot" (troca de dimensao)
A.filhos = setmetatable({}, { __mode = "k" })

local files = A.arquivos
local function norm(p) return (tostring(p):gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")) end
A.norm = norm

function A.registrar(fmt, ...)
  A.rastro[#A.rastro + 1] = ("%8.2f "):format(A.relogio) .. fmt:format(...)
end

local function checarParada()
  if A.pedido then coroutine.yield(A.PARAR) end
end
A.checarParada = checarParada

local function avancar(dt)
  A.relogio = A.relogio + dt
  A.passo()
  if A.relogio > A.limite and not A.pedido then A.pedido = "fim" end
  checarParada()
end
A.avancar = avancar

---------------------------------------------------------------- fs
fs = {}
function fs.getDir(p) p = norm(p) return p:match("^(.*)/[^/]*$") or "" end
function fs.getName(p) return norm(p):match("([^/]*)$") end
function fs.combine(...)
  local r = {}
  for _, s in ipairs({ ... }) do s = norm(s) if s ~= "" then r[#r + 1] = s end end
  return table.concat(r, "/")
end
local function temFilhos(p)
  for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
  return false
end
function fs.exists(p) p = norm(p) return p == "" or files[p] ~= nil or temFilhos(p) end
function fs.isDir(p) p = norm(p) return p == "" or (files[p] == nil and temFilhos(p)) end
function fs.delete(p)
  p = norm(p)
  files[p] = nil
  for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then files[k] = nil end end
end
function fs.getSize(p) return #(files[norm(p)] or "") end
function fs.move(a, b) files[norm(b)] = files[norm(a)] files[norm(a)] = nil end
function fs.copy(a, b) files[norm(b)] = files[norm(a)] end
function fs.makeDir() end
function fs.list(d)
  d = norm(d)
  local seen, out = {}, {}
  for k in pairs(files) do
    local rest = (d == "" and k) or (k:sub(1, #d + 1) == d .. "/" and k:sub(#d + 2)) or nil
    if rest then
      local n = rest:match("^[^/]+")
      if not seen[n] then seen[n] = true out[#out + 1] = n end
    end
  end
  table.sort(out)
  return out
end
function fs.open(p, modo)
  p = norm(p)
  if modo == "r" then
    local c = files[p]
    if not c then return nil, "/" .. p .. ": No such file" end
    local linhas, i = {}, 0
    for l in (c .. "\n"):gmatch("([^\n]*)\n") do linhas[#linhas + 1] = l end
    if c == "" or c:sub(-1) == "\n" then linhas[#linhas] = nil end
    return { readAll = function() return c end, readLine = function() i = i + 1 return linhas[i] end,
      close = function() end }
  end
  if modo == "w" or files[p] == nil then files[p] = "" end
  return {
    write = function(s) files[p] = files[p] .. tostring(s) end,
    writeLine = function(s) files[p] = files[p] .. tostring(s) .. "\n" end,
    flush = function() end, close = function() end,
  }
end

---------------------------------------------------------------- textutils (chaves em ordem: rastro deterministico)
local function ser(v)
  if type(v) == "table" then
    local ks = {}
    for k in pairs(v) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    local r = {}
    for _, k in ipairs(ks) do
      local kk
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then kk = k
      elseif type(k) == "string" then kk = ("[%q]"):format(k)
      else kk = "[" .. tostring(k) .. "]" end
      r[#r + 1] = kk .. "=" .. ser(v[k])
    end
    return "{" .. table.concat(r, ",") .. "}"
  elseif type(v) == "string" then
    return ("%q"):format(v)
  end
  return tostring(v)
end
textutils = {
  serialize = function(v) return ser(v) end,
  unserialize = function(s)
    local f = load("return " .. tostring(s))
    if not f then return nil end
    local ok, r = pcall(f)
    return ok and r or nil
  end,
  pagedPrint = function(s)
    for l in (tostring(s) .. "\n"):gmatch("([^\n]*)\n") do A.registrar("tela %s", l) end
  end,
}

---------------------------------------------------------------- os, eventos, parallel
os.clock = function() return A.relogio end
os.epoch = function() return math.floor(A.relogio * 1000 + 0.5) end
local nData = 0
os.date = function(f)
  if f and f:find("%%Y") then nData = nData + 1 return ("2026-09-27_20-%02d-00"):format(nData) end
  return "27/09 20:00:00"
end
os.startTimer = function() return 1 end
os.getComputerID = function() return 0 end
os.queueEvent = function(...) A.eventos[#A.eventos + 1] = { ... } end
function A.proximoEvento(filtro)
  while true do
    local ev = table.remove(A.eventos, 1)
    if not ev then avancar(0.05) ev = { "timer", 1 } end
    if filtro == nil or ev[1] == filtro then return table.unpack(ev) end
  end
end
os.pullEvent = function(filtro)
  if A.filhos[coroutine.running()] then return coroutine.yield(filtro) end
  return A.proximoEvento(filtro)
end
os.pullEventRaw = os.pullEvent
function sleep(t) avancar(t or 0.05) end
os.sleep = sleep

parallel = {}
function parallel.waitForAll(...)
  for _, f in ipairs({ ... }) do f() end
  avancar(0.05)
end
function parallel.waitForAny(...)
  local cos, filtros = {}, {}
  local function continuar(i, ...)
    local ok, r = coroutine.resume(cos[i], ...)
    if not ok then error(r, 0) end
    if r == A.PARAR then coroutine.yield(A.PARAR) end
    filtros[i] = r
    return coroutine.status(cos[i]) == "dead"
  end
  for i, f in ipairs({ ... }) do
    cos[i] = coroutine.create(f)
    A.filhos[cos[i]] = true
    if continuar(i) then return i end
  end
  while true do
    local ev = { A.proximoEvento() }
    for i = 1, #cos do
      if filtros[i] == nil or filtros[i] == ev[1] then
        if continuar(i, table.unpack(ev)) then return i end
      end
    end
  end
end

---------------------------------------------------------------- tela, entrada
term = {
  clear = function() end, clearLine = function() end, setCursorPos = function() end,
  getCursorPos = function() return 1, 1 end, getSize = function() return 51, 19 end,
  write = function() end, setTextColor = function() end, setTextColour = function() end,
  setBackgroundColor = function() end, isColor = function() return false end,
}
colors = setmetatable({}, { __index = function() return 1 end })
colours = colors
local function juntar(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  return table.concat(t, " ")
end
function print(...) A.registrar("tela %s", juntar(...)) end
function printError(...) A.registrar("erro %s", juntar(...)) end
function write(s) A.registrar("tela %s", tostring(s)) end
function read()
  local r = table.remove(A.entradas, 1) or ""
  A.registrar("digitou %s", r)
  return r
end

---------------------------------------------------------------- redstone, perifericos, http
redstone = {
  getInput = function(lado) return A.redstoneEntrada[lado] == true end,
  setOutput = function(lado, v)
    A.registrar("redstone %s %s", tostring(lado), tostring(v))
    A.mundo.redstone("computador", lado, v)
  end,
}
rs = redstone

local MUDA = { setThrust = true, setActive = true, setGimbal = true, setOutput = true, setMode = true }
local function fmt(v) if type(v) == "number" then return ("%.3f"):format(v) end return tostring(v) end
peripheral = {}
function peripheral.getNames() return A.mundo.nomes() end
function peripheral.isPresent(n) return A.mundo.existe(n) end
function peripheral.hasType(n, t) return A.mundo.temTipo(n, t) end
function peripheral.getType(n) return A.mundo.tipo(n) end
function peripheral.call(n, fn, ...)
  if MUDA[fn] then
    local t = {}
    for i = 1, select("#", ...) do t[i] = fmt((select(i, ...))) end
    A.registrar("call %s.%s(%s)", tostring(n), tostring(fn), table.concat(t, ","))
  end
  A.passo()
  local r = table.pack(A.mundo.chamar(n, fn, ...))
  checarParada()
  return table.unpack(r, 1, r.n)
end
function peripheral.wrap(n)
  if not A.mundo.existe(n) then return nil end
  return setmetatable({ __nome = n }, { __index = function(_, fn)
    return function(...) return peripheral.call(n, fn, ...) end
  end })
end
function peripheral.getName(w) return w.__nome end
function peripheral.find(t)
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, t) then return peripheral.wrap(n) end
  end
end

http = {
  get = function(url)
    local caminho = tostring(url):match("^https://raw%.githubusercontent%.com/[^/]+/[^/]+/[^/]+/([^?]+)")
    A.registrar("http %s", tostring(caminho))
    local c = caminho and A.servidor[caminho]
    if not c then return nil, "404 Not Found" end
    return { readAll = function() return c end, close = function() end }
  end,
}

---------------------------------------------------------------- vetores
local vmt = {}
vmt.__index = vmt
local function vnew(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmt) end
vmt.__add = function(a, b) return vnew(a.x + b.x, a.y + b.y, a.z + b.z) end
vmt.__sub = function(a, b) return vnew(a.x - b.x, a.y - b.y, a.z - b.z) end
vmt.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return vnew(a.x * b, a.y * b, a.z * b) end
vmt.__div = function(a, b) return vnew(a.x / b, a.y / b, a.z / b) end
vmt.__unm = function(a) return vnew(-a.x, -a.y, -a.z) end
vmt.__tostring = function(a) return ("%s,%s,%s"):format(a.x, a.y, a.z) end
function vmt.length(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vmt.normalize(a) local l = a:length() return vnew(a.x / l, a.y / l, a.z / l) end
function vmt.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function vmt.cross(a, b) return vnew(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
function vmt.add(a, b) return a + b end
function vmt.sub(a, b) return a - b end
function vmt.mul(a, b) return a * b end
vector = { new = vnew }

---------------------------------------------------------------- programas
shell = {
  getRunningProgram = function() return A.programa end,
  run = function(p, ...) return A.rodarPrograma(p, ...) end,
  dir = function() return "" end,
  resolve = function(p) return norm(p) end,
}
function dofile(p)
  local c = files[norm(p)]
  if not c then error("File not found: " .. tostring(p), 2) end
  return assert(load(c, "@" .. norm(p)))()
end
function loadfile(p, modo, env)
  local c = files[norm(p)]
  if not c then return nil, "File not found" end
  return load(c, "@" .. norm(p), modo, env)
end
package = { loaded = {}, path = "?;?.lua;?/init.lua" }
function require(nome)
  if package.loaded[nome] ~= nil then return package.loaded[nome] end
  local base = nome:gsub("%.", "/")
  for padrao in package.path:gmatch("[^;]+") do
    local p = norm((padrao:gsub("%?", base)))
    if files[p] then
      local r = assert(load(files[p], "@" .. p))(nome)
      if r == nil then r = true end
      package.loaded[nome] = r
      return r
    end
  end
  error("module '" .. nome .. "' not found", 2)
end

function A.rodarPrograma(prog, ...)
  prog = norm(prog)
  if not files[prog] and files[prog .. ".lua"] then prog = prog .. ".lua" end
  local c = files[prog]
  if not c then A.registrar("erro No such program %s", prog) return false end
  local anterior = A.programa
  A.programa = prog
  package.loaded = {}                         -- cada programa do CC tem o seu require
  package.path = "?;?.lua;?/init.lua"
  local fn, erro = load(c, "@" .. prog)
  if not fn then A.registrar("ERRO DE SINTAXE %s", erro) A.programa = anterior return false end
  local ok, e = pcall(fn, ...)
  if not ok then A.registrar("SCRIPT ERRO %s", tostring(e)) end
  A.programa = anterior
  return ok
end

-- roda um programa ate ele terminar, esgotar o tempo ou pedir reboot
function A.executar(prog, ...)
  A.pedido = nil
  local args = table.pack(...)
  local co = coroutine.create(function() return A.rodarPrograma(prog, table.unpack(args, 1, args.n)) end)
  local ok, r = coroutine.resume(co)
  if not ok then A.registrar("SIM ERRO %s", tostring(r)) end
  local pedido = A.pedido
  A.registrar("fim de %s%s", prog, pedido and (" (" .. pedido .. ")") or "")
  A.pedido = nil
  return pedido
end

return A
```

- [ ] **Passo 2: criar `ferramentas/sim/mundo.lua`**

```lua
-- ferramentas/sim/mundo.lua
-- Mundo simulado: nave (orientacao, posicao, velocidade), motores, Sputnik,
-- relays e separadores. A fisica e simplificada: serve para testar a logica.
local V = vector.new

local function qrot(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return V(v.x + qw * tx + (qy * tz - qz * ty), v.y + qw * ty + (qz * tx - qx * tz), v.z + qw * tz + (qx * ty - qy * tx))
end
local function qmul(a, b)
  return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end

return function(A, c)
  local M = {}
  local R, GM = 3000000, 91.9 * 3025000 ^ 2
  local nave = { q = c.q or { 0, 0, 0, 1 }, w = V(0, 0, 0), massa = c.massa or 159.5,
    pos = V(table.unpack(c.pos or { 0, 1130, 0 })), vel = V(table.unpack(c.vel or { 0, 0, 0 })) }
  local espaco = c.modo == "espaco"
  local orbita = c.orbita and { a = c.orbita.a, e = c.orbita.e, alt = c.orbita.alt, subir = c.orbita.subir } or nil
  local g = c.g or 11
  local motores, ordem = {}, {}
  for nome, m in pairs(c.motores or {}) do
    motores[nome] = { tipo = m.tipo, empuxo = 0, ativo = false, lava = m.lava or 1000, gx = 0, gz = 0,
      tq = m.tq, potencia = m.potencia or 1000, aceso = false, gasto = false, queima = m.queima or 15,
      semCarvao = m.semCarvao }
    ordem[#ordem + 1] = nome
  end
  table.sort(ordem)
  local extras = {}
  if c.sputnik then extras[c.sputnik] = "sputnik" end
  for _, r in ipairs(c.relays or {}) do extras[r] = "redstone_relay" end
  local estab, ultimo, semEmpuxo = false, A.relogio, 0

  local function passo()
    local dt = A.relogio - ultimo
    if dt <= 0 then return end
    ultimo = A.relogio
    local F, gx, gz = 0, 0, 0
    for _, n in ipairs(ordem) do
      local m = motores[n]
      if m then
        if m.tipo == "booster_thruster" then
          if m.aceso and not m.gasto then
            if A.relogio - m.t0 > m.queima then m.gasto = true else F = F + m.potencia end
          end
        elseif m.tipo ~= "rcs_thruster" and m.ativo and m.lava > 0 then
          F = F + m.empuxo
          m.lava = math.max(0, m.lava - m.empuxo * dt * 0.004)
        end
        if m.tipo == "vector_thruster" then gx, gz = m.gx, m.gz end
      end
    end
    local k = F / 5000 * 3.0
    nave.w = nave.w + V(gz * k, 0, -gx * k) * (dt * 5)
    for _, n in ipairs(ordem) do
      local m = motores[n]
      if m and m.tipo == "rcs_thruster" and m.ativo then nave.w = nave.w + V(m.tq[1], m.tq[2], m.tq[3]) * dt end
    end
    if estab then nave.w = nave.w * 0.2 end
    local ang = nave.w:length() * dt
    if ang > 1e-9 then
      local ax = nave.w:normalize()
      nave.q = qmul(nave.q, { ax.x * math.sin(ang / 2), ax.y * math.sin(ang / 2), ax.z * math.sin(ang / 2), math.cos(ang / 2) })
      local nq = math.sqrt(nave.q[1] ^ 2 + nave.q[2] ^ 2 + nave.q[3] ^ 2 + nave.q[4] ^ 2)
      for i = 1, 4 do nave.q[i] = nave.q[i] / nq end
    end
    local nariz = qrot(nave.q, V(0, 1, 0))
    if espaco then
      -- orbita Kepler simples; o prograde verdadeiro e +Z do mundo
      local dv = F / nave.massa * dt * 20 * nariz:dot(V(0, 0, 1))
      local r = R + orbita.alt
      local v = math.sqrt(GM * (2 / r - 1 / orbita.a)) + dv
      local a = 1 / (2 / r - v * v / GM)
      local rp = 2 * a - r
      local ra = math.max(r, rp) rp = math.min(r, rp)
      orbita.a, orbita.e = a, (ra - rp) / (ra + rp)
      if orbita.subir then
        orbita.alt = math.min(orbita.alt + 150 * dt, 25200)
        if orbita.alt >= 25200 then orbita.subir = false end
      end
      -- reentrada: periastro baixo e motores parados -> cai e volta ao overworld
      if c.reentra and a * (1 - orbita.e) - R < 21000 and F == 0 then
        semEmpuxo = semEmpuxo + dt
        if semEmpuxo > 2 then orbita.alt = orbita.alt - 500 * dt end
        if orbita.alt < 21000 then
          espaco = false
          nave.pos, nave.vel, nave.w = V(table.unpack(c.reentra.pos)), V(table.unpack(c.reentra.vel)), V(0, 0, 0)
          A.registrar("mundo voltou ao overworld")
          A.pedido = "reboot" -- o computador reinicia ao trocar de dimensao
        end
      else
        semEmpuxo = 0
      end
    else
      local acc = nariz * (F / nave.massa) + V(0, -g, 0)
      nave.vel = nave.vel + acc * dt
      nave.pos = nave.pos + nave.vel * dt
      if c.chao and nave.pos.y <= c.chao + 3 then
        nave.pos = V(nave.pos.x, c.chao + 3, nave.pos.z)
        if nave.vel.y < 0 then nave.vel = V(0, 0, 0) end
      end
    end
  end
  M.passo = passo

  local function sputnikDados()
    if not espaco then return { inDeepSpace = false } end
    local o = orbita
    local d = { inDeepSpace = true, eccentricity = o.e, semiMajorAxis = o.a, parentRadius = R,
      distanceToPlanet = math.floor(o.alt / 50) * 50, gravity = 91.8, speed = 15850, period = 995,
      inAtmosphere = false, parentBody = "overworld" }
    if c.sputnikVel == "velocity" then d.velocity = { x = 0, y = 0, z = 15850 } end
    if c.sputnikVel == "inverted" then d.velocity = { x = 0, y = 0, z = -15850 } end
    return d
  end

  function M.nomes()
    local t = {}
    for _, n in ipairs(ordem) do if motores[n] then t[#t + 1] = n end end
    for n in pairs(extras) do t[#t + 1] = n end
    table.sort(t)
    return t
  end
  function M.existe(n) return motores[n] ~= nil or extras[n] ~= nil end
  function M.tipo(n)
    if motores[n] then return motores[n].tipo end
    return extras[n]
  end
  function M.temTipo(n, t)
    local m = motores[n]
    if m then return t == "thruster" or (t == "fluid_storage" and m.tipo ~= "rcs_thruster") end
    return extras[n] == t
  end
  function M.chamar(n, fn, ...)
    local a = { ... }
    if extras[n] == "sputnik" then
      if fn == "getDeepSpaceData" then return sputnikDados() end
      return nil
    end
    if extras[n] == "redstone_relay" then
      if fn == "setOutput" then M.redstone(n, a[1], a[2]) end
      return nil
    end
    local m = motores[n]
    if not m then error("No such peripheral", 0) end
    if m.tipo == "booster_thruster" then
      if fn == "getData" then
        return { engine_type = "booster_thruster", ignited = m.aceso, is_spent = m.gasto, fuel_ticks = 0, thrust_power = m.potencia }
      end
      if fn == "setActive" then
        if a[1] and not m.aceso and not m.semCarvao then m.aceso, m.t0 = true, A.relogio end
        return
      end
      if fn == "getThrust" then return (m.aceso and not m.gasto) and m.potencia or 0 end
      return
    end
    if m.tipo == "rcs_thruster" then
      if fn == "getData" then return { engine_type = "rcs_thruster", active = m.ativo } end
      if fn == "setActive" then m.ativo = a[1] end
      return 0
    end
    if fn == "getData" then
      return { engine_type = m.tipo, active = m.ativo, fuel_amount = m.lava, fuel_capacity = 1000, fuel_usage = 40,
        throttle = 1, ignition_ticks = 0, warmup_time = 10 }
    end
    if fn == "getThrust" then return (m.ativo and m.lava > 0) and m.empuxo or 0 end
    if fn == "setThrust" then m.empuxo = a[1] return end
    if fn == "setActive" then m.ativo = a[1] return end
    if fn == "setGimbal" then m.gx, m.gz = a[1], a[3] return end
    if fn == "tanks" then return { { name = "minecraft:lava", amount = math.floor(m.lava) } } end
  end
  function M.redstone(origem, lado, v)
    local chave = origem .. ":" .. tostring(lado)
    if c.estabilizador == chave then estab = v end
    local sep = (c.separadores or {})[chave]
    if v and sep then
      for _, n in ipairs(sep) do motores[n] = nil end
      A.registrar("mundo separou %s", table.concat(sep, ","))
    end
  end
  function M.resumo()
    local o = orbita and (" a=%.0f e=%.4f"):format(orbita.a, orbita.e) or ""
    return ("mundo final: y=%.2f vy=%.2f espaco=%s%s"):format(nave.pos.y, nave.vel.y, tostring(espaco), o)
  end

  sublevel = {
    isInPlotGrid = function() return true end,
    getLogicalPose = function()
      passo()
      return { position = nave.pos, orientation = { x = nave.q[1], y = nave.q[2], z = nave.q[3], w = nave.q[4] } }
    end,
    getVelocity = function() return nave.vel end,
    getAngularVelocity = function() return qrot(nave.q, nave.w) end,
    getMass = function() return nave.massa end,
  }
  aero = { getGravity = function() if espaco then return V(0, 0, 0) end return V(0, -g, 0) end }
  return M
end
```

- [ ] **Passo 3: criar `ferramentas/sim/rodar.lua`**

```lua
-- ferramentas/sim/rodar.lua
-- Roda um cenario: carrega o repositorio no fs em memoria, monta o mundo,
-- executa os passos e devolve o rastro completo como texto.
return function(A, criarMundo, cen, repo)
  for p, c in pairs(repo) do A.arquivos[p] = c end
  if cen.servirRepo then for p, c in pairs(repo) do A.servidor[p] = c end end
  if cen.config then A.arquivos["config.lua"] = cen.config end
  if cen.estado then A.arquivos["estado.txt"] = cen.estado end
  for p, c in pairs(cen.arquivos or {}) do A.arquivos[p] = c or nil end
  for _, e in ipairs(cen.eventos or {}) do A.eventos[#A.eventos + 1] = e end
  for _, e in ipairs(cen.entradas or {}) do A.entradas[#A.entradas + 1] = e end
  for k, v in pairs(cen.redstone or {}) do A.redstoneEntrada[k] = v end
  local M = criarMundo(A, cen.mundo or {})
  A.mundo, A.passo = M, M.passo
  for _, p in ipairs(cen.passos) do
    if p[1] == "#arquivo" then
      A.arquivos[p[2]] = p[3] or nil
    elseif p[1] == "#servidor" then
      A.servidor[p[2]] = p[3] or nil
    else
      A.limite = A.relogio + (p.limite or cen.limite or 120)
      local pedido = A.executar(table.unpack(p))
      local reboots = 0
      while pedido == "reboot" and reboots < 3 do
        reboots = reboots + 1
        A.limite = A.relogio + (p.limite or cen.limite or 120)
        pedido = A.executar("startup.lua")
      end
    end
  end
  local out = { table.concat(A.rastro, "\n") }
  local ks = {}
  for k in pairs(A.arquivos) do
    if k:match("^logs/") or k == "estado.txt" or k == "config.lua" or k == "rcs.cal" then ks[#ks + 1] = k end
  end
  table.sort(ks)
  for _, k in ipairs(ks) do
    out[#out + 1] = "==== arquivo " .. k
    out[#out + 1] = A.arquivos[k]
  end
  out[#out + 1] = M.resumo()
  if cen.verificar then
    local erros = cen.verificar(A) or {}
    out[#out + 1] = #erros == 0 and "VERIFICACAO ok" or ("VERIFICACAO FALHOU: " .. table.concat(erros, " | "))
  end
  return table.concat(out, "\n")
end
```

- [ ] **Passo 4: criar `ferramentas/sim/testar.py`**

```python
"""Roda os cenarios do simulador e compara com a referencia gravada.

Uso (na raiz do repositorio):
  py ferramentas/sim/testar.py                   compara todos os cenarios
  py ferramentas/sim/testar.py orbita_velocity   so um cenario
  py ferramentas/sim/testar.py --gravar          regrava a referencia
Precisa de Python 3 com lupa (pip install lupa).
"""
import difflib
import glob
import os
import sys

import lupa

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
REF = os.path.join(AQUI, "referencia")
CEN = os.path.join(AQUI, "cenarios")


def ler(p):
    with open(p, encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def arquivos_do_repo():
    caminhos = glob.glob(os.path.join(RAIZ, "*.lua")) + glob.glob(os.path.join(RAIZ, "*.txt"))
    caminhos += glob.glob(os.path.join(RAIZ, "lib", "**", "*.lua"), recursive=True)
    out = {}
    for p in caminhos:
        out[os.path.relpath(p, RAIZ).replace(os.sep, "/")] = ler(p)
    return out


def rodar(nome):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    A = L.execute(ler(os.path.join(AQUI, "ambiente.lua")))
    criar = L.execute(ler(os.path.join(AQUI, "mundo.lua")))
    rodar_lua = L.execute(ler(os.path.join(AQUI, "rodar.lua")))
    cen = L.execute(ler(os.path.join(CEN, nome + ".lua")))
    saida = rodar_lua(A, criar, cen, L.table_from(arquivos_do_repo()))
    return saida, bool(cen["semReferencia"])


def main():
    gravar = "--gravar" in sys.argv
    nomes = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not nomes:
        nomes = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(CEN, "*.lua")))
    falhas = 0
    for nome in nomes:
        saida, sem_ref = rodar(nome)
        quebrou = "SCRIPT ERRO" in saida or "SIM ERRO" in saida or "VERIFICACAO FALHOU" in saida
        if sem_ref:
            print(("FALHOU    " if quebrou else "ok        ") + nome)
            if quebrou:
                falhas += 1
                print("\n".join("    " + l for l in saida.splitlines() if "ERRO" in l or "FALHOU" in l))
            continue
        ref = os.path.join(REF, nome + ".txt")
        if gravar:
            os.makedirs(REF, exist_ok=True)
            with open(ref, "w", encoding="utf-8", newline="\n") as f:
                f.write(saida)
            print("gravado   " + nome + ("  (ATENCAO: tem ERRO no rastro)" if quebrou else ""))
            continue
        if not os.path.exists(ref):
            print("SEM REF   " + nome)
            falhas += 1
            continue
        esperado = ler(ref)
        if esperado == saida:
            print("ok        " + nome)
        else:
            falhas += 1
            print("DIFERENTE " + nome)
            diff = difflib.unified_diff(esperado.splitlines(), saida.splitlines(), "referencia", "atual", lineterm="", n=2)
            for linha in list(diff)[:80]:
                print("    " + linha)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Passo 5: criar o cenário de fumaça `ferramentas/sim/cenarios/fumaca.lua`**

```lua
-- fumaca: 'voo teste' no chao com 4 Rocket + 1 Vector (confere que o simulador roda)
return {
  semReferencia = true,
  limite = 30,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, sputnik = "top",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "teste" } },
  verificar = function(A)
    local erros = {}
    local log = ""
    for k, v in pairs(A.arquivos) do if k:match("^logs/.*teste%.txt$") then log = v end end
    if not log:find("CHECAGEM empuxo_max=5000", 1, true) then erros[#erros + 1] = "preflight nao registrou o empuxo" end
    if not log:find("Teste concluido", 1, true) then erros[#erros + 1] = "teste nao terminou" end
    return erros
  end,
}
```

- [ ] **Passo 6: rodar o cenário de fumaça**

Run: `py ferramentas/sim/testar.py fumaca`
Esperado: `ok        fumaca`. Se aparecer `FALHOU`, as linhas com `ERRO` mostram a API do CC que falta no `ambiente.lua`. Acrescente essa API e rode de novo.

- [ ] **Passo 7: conferir que o rastro é determinístico**

Run: `py -c "import sys; sys.path.insert(0,'ferramentas/sim'); import testar; a=testar.rodar('fumaca')[0]; b=testar.rodar('fumaca')[0]; print('igual' if a==b else 'DIFERENTE')"`
Esperado: `igual`.

- [ ] **Passo 8: commit**

```bash
git add ferramentas/sim
git commit -m "Simulador unificado do foguete (ambiente, mundo e comparador)"
```

---

### Tarefa 2: cenários e referência com o código atual

**Arquivos:**
- Criar: `ferramentas/sim/cenarios/{orbita_velocity,orbita_novel,orbita_inverted,subida_boosters,lancamento,comandos,preflight_erros,descida,retomada_pouso,config_minima}.lua`
- Criar: `ferramentas/sim/referencia/*.txt` (gerados)
- Apagar: `ferramentas/sim.py`, `ferramentas/sim2.py`, `ferramentas/sim3.py`

**Interfaces:**
- Consome: formato de cenário da Tarefa 1.
- Produz: arquivos de referência usados em todas as tarefas seguintes.

Configuração comum usada nos cenários (copiada do `sim.py` antigo). Cada cenário tem uma cópia própria, sem dependência entre arquivos:

```lua
local CONFIG = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]]
```

Motores comuns (4 Rocket + 1 Vector) e os 8 RCS do `sim.py` antigo:

```lua
local function motores(comRcs)
  local m = {
    ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
    ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
  }
  if comRcs then
    local RT = { { 0.03, 0, 0.004 }, { -0.03, 0.002, 0 }, { 0, 0, 0.03 }, { 0.003, 0, -0.03 }, { 0, 0.02, 0 },
      { 0, -0.02, 0 }, { 0.021, 0, 0.021 }, { -0.021, 0, -0.021 } }
    for i, t in ipairs(RT) do m["rocketnautics:rcs_thruster_" .. i] = { tipo = "rcs_thruster", tq = t } end
  end
  return m
end
```

- [ ] **Passo 1: criar os 3 cenários de órbita**

`ferramentas/sim/cenarios/orbita_velocity.lua` (os outros dois são iguais, trocando o nome no comentário e `sputnikVel`: `orbita_novel` usa `sputnikVel = nil`, `orbita_inverted` usa `sputnikVel = "inverted"`):

```lua
-- orbita_velocity: COAST -> CIRC -> ORBIT com a Sputnik dando o vetor de velocidade
local CONFIG = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]]
local function motores(comRcs)
  local m = {
    ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
    ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
    ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
  }
  if comRcs then
    local RT = { { 0.03, 0, 0.004 }, { -0.03, 0.002, 0 }, { 0, 0, 0.03 }, { 0.003, 0, -0.03 }, { 0, 0.02, 0 },
      { 0, -0.02, 0 }, { 0.021, 0, 0.021 }, { -0.021, 0, -0.021 } }
    for i, t in ipairs(RT) do m["rocketnautics:rcs_thruster_" .. i] = { tipo = "rcs_thruster", tq = t } end
  end
  return m
end
return {
  limite = 120,
  config = CONFIG,
  estado = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, q = { 0, 0, 0.3826834, 0.9238795 }, sputnik = "top",
    sputnikVel = "velocity", orbita = { a = 2760742, e = 0.0958, alt = 22100, subir = true },
    estabilizador = "computador:right", motores = motores(true),
  },
  passos = { { "voo.lua" } },
}
```

- [ ] **Passo 2: criar `subida_boosters.lua`** (substitui o `sim3.py`)

Usa o mesmo `CONFIG` do passo 1, mas com `stages` trocado por:
`stages={{engines={"rocketnautics:booster_thruster_0","rocketnautics:booster_thruster_1","rocketnautics:booster_thruster_2","rocketnautics:booster_thruster_3","rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}, booster_separator={side="bottom"}}}`

```lua
return {
  limite = 60,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:booster_thruster_0","rocketnautics:booster_thruster_1",
 "rocketnautics:booster_thruster_2","rocketnautics:booster_thruster_3","rocketnautics:rocket_thruster_2",
 "rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}, booster_separator={side="bottom"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0, padY = 1127 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 1130, 0 }, massa = 400, g = 11, sputnik = "top",
    separadores = { ["computador:bottom"] = { "rocketnautics:booster_thruster_0", "rocketnautics:booster_thruster_1",
      "rocketnautics:booster_thruster_2", "rocketnautics:booster_thruster_3" } },
    motores = {
      ["rocketnautics:booster_thruster_0"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_1"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_2"] = { tipo = "booster_thruster", queima = 15 },
      ["rocketnautics:booster_thruster_3"] = { tipo = "booster_thruster", queima = 15, semCarvao = true },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua" } },
}
```
(`booster_thruster_3` sem carvão cobre o caminho "NAO ACENDEU".)

- [ ] **Passo 3: criar `lancamento.lua`** (PAD → contagem → ASCENT)

```lua
-- lancamento: preflight na plataforma, tecla L, contagem e subida
return {
  limite = 45,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=3, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]],
  eventos = { { "char", "l" } },
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, g = 11, sputnik = "top", estabilizador = "computador:right",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua" } },
}
```

- [ ] **Passo 4: criar `comandos.lua`** (substitui o `sim2.py`)

```lua
-- comandos: voo retomado em COAST, reset, teste, logs e diagnostico
local CONFIG = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]]
return {
  limite = 40,
  config = CONFIG,
  estado = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, q = { 0, 0, 0.3826834, 0.9238795 }, sputnik = "top",
    sputnikVel = "velocity", orbita = { a = 2760742, e = 0.0958, alt = 22100, subir = true },
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = {
    { "voo.lua", limite = 20 },
    { "voo.lua", limite = 10 },         -- retoma no estado que o anterior deixou
    { "voo.lua", "reset" },
    { "voo.lua", "teste", limite = 20 },
    { "logs.lua", "lista" },
    { "logs.lua", "erros" },
    { "diagnostico.lua" },
  },
}
```

- [ ] **Passo 5: criar `preflight_erros.lua`**

```lua
-- preflight_erros: sem Vector Thruster e TWR baixo -> erros na checagem
return {
  limite = 20,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, sputnik="top", turn_end_y=16000,
 gimbal_sign=1, transfer_y=20000, kp_errado=3 }]],
  mundo = {
    modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60, massa = 400, sputnik = "top",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_9"] = { tipo = "rocket_thruster" },
    },
  },
  passos = { { "voo.lua", "teste" } },
}
```
(`kp_errado` é uma chave desconhecida: no código antigo não gera nada; no novo gera o AVISO combinado na spec. Essa é a diferença esperada nº 2. `rocket_thruster_9` está conectado mas fora da config.)

- [ ] **Passo 6: criar `descida.lua`** (DEORBIT → REENTRADA → reboot → POUSO → POUSADO)

```lua
-- descida: 'voo descer 60' em orbita; reentra, o computador reinicia e pousa no Y=60
return {
  limite = 400,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer={side="right"} }]],
  estado = '{ phase = "ORBIT", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "espaco", pos = { 0, 1130, 0 }, sputnik = "top", sputnikVel = "velocity", g = 11, chao = 60,
    orbita = { a = 3025200, e = 0, alt = 25200 }, reentra = { pos = { 0, 1500, 0 }, vel = { 3, -60, 0 } },
    estabilizador = "computador:right",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "descer", "60" } },
}
```

- [ ] **Passo 7: criar `retomada_pouso.lua`**

```lua
-- retomada_pouso: o computador liga (startup) com o voo parado no meio do POUSO
return {
  limite = 120,
  config = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "POUSO", stage = 1, failed = {}, t0 = 0, groundY = 60 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 800, 0 }, vel = { 0, -40, 0 }, g = 11, chao = 60, sputnik = "top",
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "startup.lua" } },
}
```

- [ ] **Passo 8: criar `config_minima.lua`** (só as chaves sem padrão: prova que a tabela de padrões é igual aos `or` antigos)

```lua
-- config_minima: config sem nenhuma chave opcional; pouso usa os padroes
return {
  limite = 120,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "POUSO", stage = 1, failed = {}, t0 = 0 }',
  mundo = {
    modo = "atmosfera", pos = { 0, 700, 0 }, vel = { 2, -30, 0 }, g = 11, chao = 60,
    motores = {
      ["rocketnautics:rocket_thruster_0"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_1"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_2"] = { tipo = "rocket_thruster" },
      ["rocketnautics:rocket_thruster_3"] = { tipo = "rocket_thruster" },
      ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" },
    },
  },
  passos = { { "voo.lua", "teste", limite = 20 }, { "voo.lua" } },
}
```

- [ ] **Passo 9: gravar a referência com o código atual**

Run: `py ferramentas/sim/testar.py --gravar`
Esperado: uma linha `gravado` por cenário (a `fumaca` aparece como `ok`). Abra cada `referencia/*.txt` e confira que:
- as `orbita_*` terminam com `FASE ... -> ORBIT`;
- a `descida` tem `DEORBIT`, `REENTRADA`, `mundo voltou ao overworld`, `fim de voo.lua (reboot)` e depois `POUSO`;
- a `subida_boosters` tem `booster_thruster_3 NAO ACENDEU` e `mundo separou`.

Se algum cenário tiver `SCRIPT ERRO`, corrija o **cenário** (não o `voo.lua`) e grave de novo.

- [ ] **Passo 10: conferir que a referência se repete**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`.

- [ ] **Passo 11: apagar os simuladores antigos e fazer o commit**

```bash
git rm ferramentas/sim.py ferramentas/sim2.py ferramentas/sim3.py
git add ferramentas/sim
git commit -m "Cenarios do simulador e referencia gravada com o voo.lua atual"
```

---

### Tarefa 3: base (`log`, `mat`, `config`, `estado`) e `voo.lua` usando os módulos

**Arquivos:**
- Mover: `log.lua` → `lib/foguete/log.lua` (`git mv`, sem alteração de conteúdo)
- Criar: `lib/foguete/mat.lua`, `lib/foguete/config.lua`, `lib/foguete/estado.lua`, `ferramentas/sim/cenarios/config_explicita.lua`
- Modificar: `voo.lua` (topo e seções matemática/estado)

**Interfaces:**
- Produz:
  - `mat.clamp(x,a,b)`, `mat.qrot(q,v)`, `mat.toLocal(q,v)`, `mat.quatParts(o)`, `mat.periNames()`, `mat.UP`
  - `config.carregar(caminho) -> cfg, desconhecidas` (lista ordenada de nomes); `config.PADROES`
  - `estado.novo(caminho, L) -> E` com `E.S` (tabela real), `E.proxy` (lê e escreve em `E.S` atual), `E.salvar()`, `E.carregar()`, `E.trocar(fase, motivo)`; `estado.FASES` (conjunto de nomes válidos)

- [ ] **Passo 1: escrever o cenário da chave booleana explícita (falha até o config novo existir)**

`ferramentas/sim/cenarios/config_explicita.lua`:

```lua
-- config_explicita: land_cc_gimbal = false no config tem que continuar false
return {
  semReferencia = true,
  limite = 30,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0}, land_cc_gimbal=false,
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:vector_thruster_1"}}}, sputnik_guidance=true,
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  mundo = { modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60,
    motores = { ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" } } },
  passos = { { "#arquivo", "t.lua", [[
package.path = "/lib/?.lua;" .. package.path
local cfg = require("foguete.config").carregar("config.lua")
print("land_cc_gimbal=" .. tostring(cfg.land_cc_gimbal) .. " ki=" .. tostring(cfg.ki))
]] }, { "t.lua" } },
  verificar = function(A)
    for _, l in ipairs(A.rastro) do
      if l:find("land_cc_gimbal=false ki=0.6", 1, true) then return {} end
    end
    return { "config.carregar nao preservou land_cc_gimbal=false ou nao aplicou ki=0.6" }
  end,
}
```

Run: `py ferramentas/sim/testar.py config_explicita`
Esperado: `FALHOU` (o módulo ainda não existe).

- [ ] **Passo 2: mover o log**

```bash
git mv log.lua lib/foguete/log.lua
```

- [ ] **Passo 3: criar `lib/foguete/mat.lua`**

```lua
-- lib/foguete/mat.lua : vetores, quaternions e utilidades
local M = {}
local V = vector.new
M.UP = V(0, 1, 0)

function M.clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- nomes dos perifericos sem repeticao (com 2 modems na mesma rede o CC lista cada um 2 vezes)
function M.periNames()
  local seen, out = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if not seen[n] then seen[n] = true out[#out + 1] = n end
  end
  return out
end

function M.qrot(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return V(v.x + qw * tx + (qy * tz - qz * ty),
           v.y + qw * ty + (qz * tx - qx * tz),
           v.z + qw * tz + (qx * ty - qy * tx))
end
function M.toLocal(q, v) return M.qrot({ -q[1], -q[2], -q[3], q[4] }, v) end

function M.quatParts(o)
  if o.v then return { o.v.x, o.v.y, o.v.z, o.a } end
  return { o.x, o.y, o.z, o.w }
end

return M
```

- [ ] **Passo 4: criar `lib/foguete/config.lua`**

```lua
-- lib/foguete/config.lua : carrega o config.lua do foguete com todos os valores padrao
local M = {}

-- Chaves opcionais e seus padroes (os mesmos valores que ficavam soltos no voo.lua)
M.PADROES = {
  -- apontar antes de acender (espaco e pouso)
  align_deg = 5, align_keep_deg = 15, align_rate = 0.05, orient_throttle = 0.35,
  -- equilibrio de empuxo na subida
  balance_every = 1.5, balance_min = 100, balance_spread = 0.2,
  -- controle de direcao: termo integral
  ki = 0.6, imax = 0.5,
  -- orbita
  orbit_peri_alt = 23000, circ_slow_m = 50000, deorbit_peri = 8000,
  -- pouso
  land_align_deg = 15, land_ceiling_y = 400, land_h_accel = 8, land_max_speed = 120,
  land_max_tilt = 25, land_max_tilt_high = 60, land_offset = 3, land_slow_h = 40, land_speed = 3,
  land_cc_gimbal = true,
  -- Magnetic Stabilizer ligado tambem na subida
  stab_ascent = false,
  -- RCS (so age com rcs_enabled = true)
  rcs_enabled = false, rcs_cal_time = 1.0, rcs_cos = 0.5, rcs_deadband = 0.01, rcs_kd = 1.2,
  rcs_kp = 0.4, rcs_min_resp = 0.002, rcs_timeout = 30,
}

-- Chaves sem padrao (o setup escreve) ou opcionais que ficam vazias
M.OUTRAS = { "stages", "east", "kp", "kd", "max_gimbal", "gimbal_sign", "max_thrust_n", "max_twr", "min_twr",
  "launch_side", "countdown", "transfer_y", "turn_start_alt", "turn_end_y", "turn_end_angle",
  "sputnik", "sputnik_guidance", "stabilizer", "monitor", "ground_y", "steer_throttle", "ecc_target" }

-- devolve a config com os padroes e a lista de chaves desconhecidas (erro de digitacao?)
function M.carregar(caminho)
  local cfg = dofile(caminho)
  local conhecidas = {}
  for k in pairs(M.PADROES) do conhecidas[k] = true end
  for _, k in ipairs(M.OUTRAS) do conhecidas[k] = true end
  local desconhecidas = {}
  for k in pairs(cfg) do
    if not conhecidas[k] then desconhecidas[#desconhecidas + 1] = tostring(k) end
  end
  table.sort(desconhecidas)
  for k, v in pairs(M.PADROES) do
    if cfg[k] == nil then cfg[k] = v end
  end
  for _, st in ipairs(cfg.stages or {}) do
    local seen, list = {}, {}
    for _, n in ipairs(st.engines or {}) do
      if not seen[n] then seen[n] = true list[#list + 1] = n end
    end
    st.engines = list
  end
  return cfg, desconhecidas
end

return M
```

- [ ] **Passo 5: criar `lib/foguete/estado.lua`**

```lua
-- lib/foguete/estado.lua : estado persistente do voo (estado.txt)
local M = {}

M.FASES = { PAD = true, ASCENT = true, BALISTICO = true, COAST = true, CIRC = true, ORBIT = true,
  DEORBIT = true, REENTRADA = true, POUSO = true, POUSADO = true, FALHA = true, FIM = true }

function M.novo(caminho, L)
  local E = { S = { phase = "PAD", stage = 1, failed = {} } }
  -- 'proxy' le e escreve sempre no estado atual, mesmo depois de carregar()
  E.proxy = setmetatable({}, {
    __index = function(_, k) return E.S[k] end,
    __newindex = function(_, k, v) E.S[k] = v end,
  })
  function E.salvar()
    local f = fs.open(caminho, "w") f.write(textutils.serialize(E.S)) f.close()
  end
  function E.carregar()
    if not fs.exists(caminho) then return end
    local f = fs.open(caminho, "r") local t = textutils.unserialize(f.readAll()) f.close()
    if t then E.S = t end
  end
  function E.trocar(p, why)
    L.info("FASE %s -> %s (%s)", E.S.phase, p, why)
    E.S.phase = p
    if p ~= "ASCENT" and p ~= "BALISTICO" then E.S.thrCap = nil end -- equilibrio so vale na subida
    E.salvar()
  end
  return E
end

return M
```

- [ ] **Passo 6: `voo.lua` passa a usar os quatro módulos**

Substituir `voo.lua:9-44` (de `local args = { ... }` até `local function clamp...`) e `voo.lua:46-69` (periNames, qrot, toLocal, quatParts) por:

```lua
local args = { ... }
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

---------------------------------------------------------------- matematica
local mat = require("foguete.mat")
local V = vector.new
local UP = mat.UP
local EAST = V(CFG.east[1], CFG.east[2], CFG.east[3]):normalize()
local clamp, periNames, qrot, toLocal, quatParts = mat.clamp, mat.periNames, mat.qrot, mat.toLocal, mat.quatParts
```

Substituir `voo.lua:95-110` (seção estado: `local S`, `save`, `load`, `setPhase`) por:

```lua
---------------------------------------------------------------- estado
local E = require("foguete.estado").novo(STATE_FILE, L)
local S = E.proxy
local save, load, setPhase = E.salvar, E.carregar, E.trocar
```

Remover a linha `voo.lua:271` (`S.failed = S.failed or {}`), porque o estado inicial de `estado.novo` já tem `failed = {}`.

No `preflight` (antes de `if not CFG.sputnik or not peripheral.isPresent(CFG.sputnik)` em `voo.lua:715`), acrescentar:

```lua
  for _, k in ipairs(DESCONHECIDAS) do
    W("chave desconhecida no config.lua: %s (erro de digitacao?)", k)
  end
```

Trocar os 30 usos `CFG.x or <numero>` pelo simples `CFG.x`, e `CFG.land_cc_gimbal ~= false` por `CFG.land_cc_gimbal`. Assim os padrões ficam só em `config.lua`. Conferir com:

Run: `grep -n "CFG\.[a-z_]* or [0-9]" voo.lua`
Esperado: nada (as ocorrências `CFG.land_ceiling_y or 400` e `CFG.land_speed or 3` dentro do `L.warn` do `descer` também viram `CFG.land_ceiling_y` e `CFG.land_speed`).

- [ ] **Passo 7: rodar todos os cenários**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`, exceto `preflight_erros`, que mostra `DIFERENTE` apenas com as linhas novas `AVISO CHECAGEM chave desconhecida no config.lua: kp_errado (erro de digitacao?)` (diferença esperada nº 2) e `config_explicita` como `ok`.

- [ ] **Passo 8: regravar só o `preflight_erros` e confirmar**

Run: `py ferramentas/sim/testar.py --gravar preflight_erros` e depois `py ferramentas/sim/testar.py`
Esperado: todos `ok`.

- [ ] **Passo 9: commit**

```bash
git add -A lib voo.lua ferramentas/sim
git commit -m "Modulos base: log, mat, config com padroes e estado"
```

---

### Tarefa 4: `sensores`, `motores` e `sputnik`

**Arquivos:**
- Criar: `lib/foguete/sensores.lua`, `lib/foguete/motores.lua`, `lib/foguete/sputnik.lua`
- Modificar: `voo.lua`

**Interfaces:**
- Consome: `mat`, `estado` (`E.proxy`, `E.salvar`), `L`, `CFG`.
- Produz:
  - `sensores.readShip()`, `sensores.gravity()`
  - `motores.novo(CFG, E, L) -> Mot` com `call, typeOf, short, stageEngines, allEngines, engineLine, logEngines, setThrottle, orientThrottle, ignite, shutdown, safeAll, stageStatus, lavaTotal, equilibrar(now), ultimoAcelerador(i)`. O laço só chama `equilibrar` na fase ASCENT, no tick lento e com mais de 2 s de queima.
  - `sputnik.novo(CFG, Mot) -> Sp` com `dados(), orbitDir(d), periAlt(d)`

Todas as fábricas `novo(...)` seguem o mesmo começo, para que o código movido funcione sem alteração:

```lua
local S = E.proxy
local function save() E.salvar() end
```

- [ ] **Passo 1: criar `lib/foguete/sensores.lua`**

```lua
-- lib/foguete/sensores.lua : leitura da nave (CC: Sable) e gravidade
local mat = require("foguete.mat")
local M = {}

-- as 4 leituras em paralelo: cada uma pode custar 1 tick se feita em sequencia
function M.readShip()
  local pose, vel, angv, mass
  parallel.waitForAll(
    function() pose = sublevel.getLogicalPose() end,
    function() vel = sublevel.getVelocity() end,
    function() angv = sublevel.getAngularVelocity() end,
    function() mass = sublevel.getMass() end)
  return {
    pos = pose.position,
    q = mat.quatParts(pose.orientation),
    vel = vel,
    angv = angv,
    mass = mass,
  }
end

function M.gravity()
  local ok, g = pcall(aero.getGravity)
  if ok and g and g:length() > 0.01 then return g:length() end
  return 9.81
end

return M
```

- [ ] **Passo 2: criar `lib/foguete/motores.lua`**

Estrutura do arquivo. O corpo de cada função é o de `voo.lua` nas linhas indicadas, **copiado sem alteração**:

```lua
-- lib/foguete/motores.lua : motores (perifericos), acelerador, ignicao e equilibrio de empuxo
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L)
  local S = E.proxy
  local function save() E.salvar() end
  local clamp, periNames = mat.clamp, mat.periNames

  -- voo.lua:113-124  call
  -- voo.lua:126-133  engineType + typeOf
  -- voo.lua:135      short
  -- voo.lua:137-149  stageEngines
  -- voo.lua:151-157  allEngines
  -- voo.lua:159-174  engineLine
  -- voo.lua:176-183  logEngines
  -- voo.lua:185-215  lastThrottleN, lastEngineN, quantN, setThrottle
  -- voo.lua:217-220  orientThrottle
  -- voo.lua:230-244  ignite, shutdown
  -- voo.lua:246-268  safeAll
  -- voo.lua:272-296  stageStatus (sem a linha 271)
  -- voo.lua:417-439  lavaTotal

  -- equilibrio de empuxo (antes voo.lua:915-955, que ficava no laco)
  local bal = {}
  local function equilibrar(now)
    if now - (bal.balT or -99) <= CFG.balance_every then return end
    bal.balT = now
    -- corpo de voo.lua:919-954 sem alteracao, trocando 'orb.capUpT' por 'bal.capUpT'
  end

  local function ultimoAcelerador(i) return lastThrottleN[i] end

  return {
    call = call, typeOf = typeOf, short = short, stageEngines = stageEngines, allEngines = allEngines,
    engineLine = engineLine, logEngines = logEngines, setThrottle = setThrottle, orientThrottle = orientThrottle,
    ignite = ignite, shutdown = shutdown, safeAll = safeAll, stageStatus = stageStatus, lavaTotal = lavaTotal,
    equilibrar = equilibrar, ultimoAcelerador = ultimoAcelerador,
  }
end

return M
```

A condição de fora de `voo.lua:917` fica no laço (passo 4). Dentro do `equilibrar` fica só o teste de tempo, porque `orb.balT` vira `bal.balT`.

- [ ] **Passo 3: criar `lib/foguete/sputnik.lua`**

```lua
-- lib/foguete/sputnik.lua : dados orbitais da Sputnik
local M = {}

function M.novo(CFG, Mot)
  local V = vector.new
  local function dados()
    if not CFG.sputnik then return nil end
    return Mot.call(CFG.sputnik, "getDeepSpaceData")
  end
  -- direcao da velocidade orbital (prograde) no mundo da nave, se a Sputnik der o vetor
  local function orbitDir(d)
    local v = d and d.velocity
    if type(v) == "table" and v.x and v.x == v.x then
      local w = V(v.x, v.y or 0, v.z or 0)
      if w:length() > 1e-6 then return w:normalize() end
    end
    return nil
  end
  -- altura do periastro acima da superficie
  local function periAlt(d)
    if not d or not d.semiMajorAxis or not d.eccentricity then return 0 / 0 end
    return d.semiMajorAxis * (1 - d.eccentricity) - (d.parentRadius or 0)
  end
  return { dados = dados, orbitDir = orbitDir, periAlt = periAlt }
end

return M
```

- [ ] **Passo 4: `voo.lua` usa os três módulos**

- Apagar `voo.lua:71-93` (readShip, gravity) e, no lugar, colocar:

```lua
local Sens = require("foguete.sensores")
local readShip, gravity = Sens.readShip, Sens.gravity
```

- Apagar `voo.lua:112-296` e `voo.lua:417-439` e, no lugar da primeira, colocar:

```lua
---------------------------------------------------------------- motores
local Mot = require("foguete.motores").novo(CFG, E, L)
local call, typeOf, short, stageEngines, allEngines = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.allEngines
local engineLine, logEngines, setThrottle, orientThrottle = Mot.engineLine, Mot.logEngines, Mot.setThrottle, Mot.orientThrottle
local ignite, shutdown, safeAll, stageStatus, lavaTotal = Mot.ignite, Mot.shutdown, Mot.safeAll, Mot.stageStatus, Mot.lavaTotal
```

- `alignedFor` (`voo.lua:222-228`) continua no `voo.lua` até a Tarefa 5.
- Apagar `voo.lua:396-415` (sputnik, orbitDir, periAlt) e colocar:

```lua
local Sp = require("foguete.sputnik").novo(CFG, Mot)
local sputnik, orbitDir, periAlt = Sp.dados, Sp.orbitDir, Sp.periAlt
```

- No laço, trocar o bloco `voo.lua:915-955` por:

```lua
    if slow and S.phase == "ASCENT" and now - burnStart > 2 then Mot.equilibrar(now) end
```

- No POUSO, trocar `(lastThrottleN[S.stage] or 0)` (`voo.lua:1163`) por `(Mot.ultimoAcelerador(S.stage) or 0)`.

- [ ] **Passo 5: rodar os cenários**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`.

- [ ] **Passo 6: commit**

```bash
git add -A lib voo.lua
git commit -m "Modulos de sensores, motores e Sputnik"
```

---

### Tarefa 5: `controle`, `separacao`, `tela` e `telemetria`

**Arquivos:**
- Criar: `lib/foguete/controle.lua`, `lib/foguete/separacao.lua`, `lib/foguete/tela.lua`, `lib/foguete/telemetria.lua`
- Modificar: `voo.lua`

**Interfaces:**
- Consome: `Mot` (Tarefa 4), `mat`, `E`, `L`, `CFG`.
- Produz:
  - `controle.novo(CFG, E, L, Mot) -> Ctl` com `steer(ship, target, force, useInteg) -> err, gx, gz`, `alignedFor(state, err, ship) -> bool`, `stabilizer(on)`, `lastW()`, `steerCount()`
  - `separacao.novo(CFG, E, L, Mot) -> Sep` com `pulse(sep)`, `separate(i)`, `checkBoosterDrop(i)`, `confirmarIgnicao(i, since, retry)`
  - `tela.novo(CFG, L) -> Tela` com `show(linhas)`
  - `telemetria.novo(L) -> Tel` com `csvLine(campos)`, `fisica(ship, now, thrust, g, err, gx, gz, lastW)`, `motores(now, burnStart, S, ship, Mot)`

- [ ] **Passo 1: criar `lib/foguete/controle.lua`**

```lua
-- lib/foguete/controle.lua : aponta a nave (gimbal PD+I) e liga o Magnetic Stabilizer
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot)
  local S = E.proxy
  local V = vector.new
  local clamp, toLocal = mat.clamp, mat.toLocal
  local call, typeOf, stageEngines = Mot.call, Mot.typeOf, Mot.stageEngines

  -- voo.lua:222-228  alignedFor
  -- voo.lua:298-339  lastW, steerCount, integ, steer
  -- voo.lua:350-359  stabOn, stabilizer

  return {
    steer = steer, alignedFor = alignedFor, stabilizer = stabilizer,
    lastW = function() return lastW end, steerCount = function() return steerCount end,
  }
end

return M
```

- [ ] **Passo 2: criar `lib/foguete/separacao.lua`**

```lua
-- lib/foguete/separacao.lua : Stage Separators e boosters
local M = {}

function M.novo(CFG, E, L, Mot)
  local S = E.proxy
  local function save() E.salvar() end
  local call, typeOf, short, stageEngines, engineLine = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.engineLine

  -- voo.lua:341-348  pulse
  -- voo.lua:361-366  separate
  -- voo.lua:368-394  checkBoosterDrop

  -- confirma que cada booster acendeu (antes voo.lua:889-911, dentro do laco)
  local function confirmarIgnicao(i, since, boosterRetry)
    -- corpo de voo.lua:891-910 sem alteracao, trocando 'S.stage' por 'i'
  end

  return { pulse = pulse, separate = separate, checkBoosterDrop = checkBoosterDrop, confirmarIgnicao = confirmarIgnicao }
end

return M
```

- [ ] **Passo 3: criar `lib/foguete/tela.lua`**

```lua
-- lib/foguete/tela.lua : mostra o estado do voo no terminal e no monitor
local M = {}

function M.novo(CFG, L)
  local mon = CFG.monitor and peripheral.wrap(CFG.monitor)
  local function show(t)
    local all = {}
    for _, l in ipairs(t) do table.insert(all, l) end
    for _, r in ipairs(L.recent) do table.insert(all, r) end
    for _, out in ipairs({ term, mon }) do
      if out then
        out.clear() out.setCursorPos(1, 1)
        for _, l in ipairs(all) do
          local _, y = out.getCursorPos()
          out.write(l) out.setCursorPos(1, y + 1)
        end
      end
    end
  end
  return { show = show }
end

return M
```

- [ ] **Passo 4: criar `lib/foguete/telemetria.lua`**

```lua
-- lib/foguete/telemetria.lua : CSV do voo e linhas periodicas FISICA / MOTOR / COMBUSTIVEL
local M = {}

function M.novo(L)
  local csv
  local function csvLine(fields)
    if not csv then csv = fs.open(L.csvPath(), "a") end
    csv.writeLine(table.concat(fields, ",")) csv.flush()
  end

  -- fisica: aceleracao medida x esperada (calibra unidades de massa/empuxo)
  local cal = { t = os.clock(), vy = nil, ticks = 0 }
  local function fisica(ship, now, thrust, g, err, gx, gz, lastW)
    cal.ticks = cal.ticks + 1
    if now - cal.t >= 1 then
      if cal.vy then
        local aMed = (ship.vel.y - cal.vy) / (now - cal.t)
        L.info("FISICA y=%.1f vy=%.2f a_medida=%.2f F/m=%.2f g=%.2f massa=%.1f F=%.0f erro=%.1f gimbal=(%.2f,%.2f) w=(%.2f,%.2f,%.2f) loop=%.1fHz",
          ship.pos.y, ship.vel.y, aMed, thrust / math.max(ship.mass, 1e-6), g, ship.mass, thrust, err,
          gx, gz, lastW.x, lastW.y, lastW.z, cal.ticks / (now - cal.t))
      end
      cal.t, cal.vy, cal.ticks = now, ship.vel.y, 0
    end
  end

  -- motores: a cada 5s no inicio, depois a cada 20s (em paralelo)
  local engT = os.clock()
  local function motores(now, burnStart, S, ship, Mot)
    local engEvery = (now - burnStart < 30) and 5 or 20
    if now - engT >= engEvery then
      Mot.logEngines(S.phase)
      local lava, nt = Mot.lavaTotal()
      L.info("COMBUSTIVEL lava=%d mB em %d tanques/motores (fase %s, Y=%.0f)", lava, nt, S.phase, ship.pos.y)
      engT = now
    end
  end

  return { csvLine = csvLine, fisica = fisica, motores = motores }
end

return M
```

`telemetria.novo` precisa ser chamado **no mesmo ponto** em que o laço antigo criava `calT` e `engT` (`voo.lua:834-835`). Só assim os relógios iniciais ficam iguais. O `csvLine` do `descer` e da plataforma usa um objeto de telemetria criado antes, e isso não muda o rastro, porque `csv` só é aberto na primeira linha.

- [ ] **Passo 5: `voo.lua` usa os quatro módulos**

- Apagar `voo.lua:222-228`, `298-366`, `368-394`, `610-631` e colocar:

```lua
local Ctl = require("foguete.controle").novo(CFG, E, L, Mot)
local steer, alignedFor, stabilizer = Ctl.steer, Ctl.alignedFor, Ctl.stabilizer
local Sep = require("foguete.separacao").novo(CFG, E, L, Mot)
local pulse, separate, checkBoosterDrop = Sep.pulse, Sep.separate, Sep.checkBoosterDrop
local Tela = require("foguete.tela").novo(CFG, L)
local show = Tela.show
local TelCsv = require("foguete.telemetria").novo(L)
local csvLine = TelCsv.csvLine
```

- No laço:
  - trocar `local steerBefore = steerCount` por `local steerBefore = Ctl.steerCount()`;
  - trocar `if steerCount == steerBefore then sleep(0.05) end` por `if Ctl.steerCount() == steerBefore then sleep(0.05) end`;
  - trocar o bloco `voo.lua:888-911` por:

```lua
    local since = now - igniteT
    if slow and since > 0.5 and since < 4 then Sep.confirmarIgnicao(S.stage, since, boosterRetry) end
```

  - trocar `local calT, calVy, calTicks = os.clock(), nil, 0` e `local engT = os.clock()` por `local Tel = require("foguete.telemetria").novo(L)`;
  - trocar `voo.lua:1272-1290` por:

```lua
    Tel.fisica(ship, now, thrust, g, err, gx, gz, Ctl.lastW())
    Tel.motores(now, burnStart, S, ship, Mot)
```

  - trocar os `csvLine(...)` do laço por `Tel.csvLine(...)`. O `Tel` do laço e o `TelCsv` escrevem no mesmo arquivo `L.csvPath()`, e as chamadas mantêm a ordem.

- [ ] **Passo 6: rodar os cenários**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`.

- [ ] **Passo 7: commit**

```bash
git add -A lib voo.lua
git commit -m "Modulos de controle, separacao, tela e telemetria"
```

---

### Tarefa 6: `rcs` e `checagem`; Gyrodyne sai

**Arquivos:**
- Criar: `lib/foguete/rcs.lua`, `lib/foguete/checagem.lua`
- Modificar: `voo.lua`

**Interfaces:**
- Consome: `Mot`, `Ctl`, `Sens`, `mat`, `E`, `L`, `CFG`, `DESCONHECIDAS`.
- Produz:
  - `rcs.novo(CFG, E, L, Mot, Sens) -> Rcs` com `discover()`, `missing()`, `ready()`, `set(list)`, `off()`, `control(ship, target)`, `calibrate(why)`, `teste()`, `estado` (tabela `{names, cal, on, failed}`)
  - `checagem.novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS) -> Chk` com `preflight() -> errs, warns, twr` e `teste()`

- [ ] **Passo 1: criar `lib/foguete/rcs.lua`**

```lua
-- lib/foguete/rcs.lua : RCS (so age com rcs_enabled = true no config.lua)
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot, Sens)
  local V = vector.new
  local UP = mat.UP
  local clamp, toLocal, periNames = mat.clamp, mat.toLocal, mat.periNames
  local call, typeOf, short = Mot.call, Mot.typeOf, Mot.short
  local readShip = Sens.readShip
  local RCS_FILE = "rcs.cal"

  -- voo.lua:469-608  rcs, rcsDiscover, rcsMissing, rcsReady, rcsSet, rcsOff, rcsControl, rcsCalibrate
  -- voo.lua:1364-1389  rcsTeste

  return {
    estado = rcs, discover = rcsDiscover, missing = rcsMissing, ready = rcsReady, set = rcsSet, off = rcsOff,
    control = rcsControl, calibrate = rcsCalibrate, teste = rcsTeste,
  }
end

return M
```

- [ ] **Passo 2: criar `lib/foguete/checagem.lua`**

```lua
-- lib/foguete/checagem.lua : checagem antes do voo (preflight) e 'voo teste'
local mat = require("foguete.mat")
local M = {}

function M.novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS)
  local periNames = mat.periNames
  local call, typeOf, short, stageEngines, allEngines = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.allEngines
  local engineLine, lavaTotal, safeAll = Mot.engineLine, Mot.lavaTotal, Mot.safeAll
  local readShip, gravity = Sens.readShip, Sens.gravity
  local stabilizer = Ctl.stabilizer
  local rcs, rcsDiscover, rcsReady = Rcs.estado, Rcs.discover, Rcs.ready

  -- voo.lua:633-718  preflight, SEM as linhas 702-704 (Gyrodyne), COM o laco de DESCONHECIDAS da Tarefa 3
  -- voo.lua:720-745  teste

  return { preflight = preflight, teste = teste }
end

return M
```

- [ ] **Passo 3: `voo.lua` usa os módulos e perde o Gyrodyne**

- Apagar `voo.lua:441-461` (Gyrodyne), `463-608` (RCS), `633-745` (checagem e teste) e `1364-1389` (rcsTeste). No lugar, colocar:

```lua
local Rcs = require("foguete.rcs").novo(CFG, E, L, Mot, Sens)
local rcs, rcsDiscover, rcsReady, rcsOff = Rcs.estado, Rcs.discover, Rcs.ready, Rcs.off
local rcsControl, rcsCalibrate, rcsTeste = Rcs.control, Rcs.calibrate, Rcs.teste
local Chk = require("foguete.checagem").novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS)
local preflight, teste = Chk.preflight, Chk.teste
```

- Apagar as chamadas ao Gyrodyne:
  - `voo.lua:1130-1131`: o comentário e `if vy < -2 and speed > 3 then gyroMode(...) else ... end`;
  - `voo.lua:1292`: `if S.phase ~= "POUSO" then gyroMode("off") end`;
  - `voo.lua:1306`: `gyroMode("off")`;
  - `voo.lua:1404`: `pcall(gyroMode, "off")`.

Run: `grep -n "gyro" voo.lua lib -r`
Esperado: nada.

- [ ] **Passo 4: rodar os cenários**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`. Não há Gyrodyne nos cenários, então a remoção não gera diferença (diferença esperada nº 1: nenhuma chamada a menos aparece).

- [ ] **Passo 5: commit**

```bash
git add -A lib voo.lua
git commit -m "Modulos de RCS e checagem; remove o suporte ao Gyrodyne"
```

---

### Tarefa 7: fases e laço principal

**Arquivos:**
- Criar: `lib/foguete/fases/plataforma.lua`, `subida.lua`, `orbita.lua`, `deorbit.lua`, `reentrada.lua`, `pouso.lua`, `lib/foguete/laco.lua`
- Modificar: `voo.lua` (fica só a entrada)

**Interfaces:**
- Consome: todos os módulos anteriores.
- Produz:
  - Cada `fases/X.lua` devolve `{ fases = {...}, novaMemoria = function() ... end, tick = function(ctx) end, estabilizador = function(ctx) return bool end }`. A plataforma devolve `{ preparar = function(ctx) return true|false end }`.
  - `laco.novo(args, L, CFG, DESCONHECIDAS, caminhoEstado) -> V` com `voo()`, `descer()`, `teste()`, `rcsTeste()`, `S` (proxy) e `limpar()` (desliga tudo depois de um crash).

**Contexto `ctx`** (montado por `laco.lua` a cada tick):

```lua
ctx = {
  S = S, cfg = CFG, log = L, trocar = setPhase,
  mot = Mot, ctl = Ctl, sp = Sp, rcs = Rcs, sens = Sens, sep = Sep, tela = Tela, chk = Chk, tel = Tel,
  EAST = EAST,
  nave = ship, speed = speed, agora = now, dt = dt, lento = slow,
  orb = { dsd = dsd, inSpace = inSpace, ecc = ecc, dist = dist, vr = vr, g = g, vrOk = vrOk },
  saida = { tilt = 0, err = 0, gx = 0, gz = 0 },
  mem = memorias[modulo],
}
```

**Regra de tradução do código movido para dentro de `tick(ctx)`** (vale para todas as fases). O `tick` começa sempre com:

```lua
  local S, CFG, L = ctx.S, ctx.cfg, ctx.log
  local setPhase = ctx.trocar
  local Mot, Ctl, Sp, Rcs, Sens = ctx.mot, ctx.ctl, ctx.sp, ctx.rcs, ctx.sens
  local setThrottle, orientThrottle, shutdown, ignite = Mot.setThrottle, Mot.orientThrottle, Mot.shutdown, Mot.ignite
  local stageEngines, typeOf, logEngines = Mot.stageEngines, Mot.typeOf, Mot.logEngines
  local steer, alignedFor = Ctl.steer, Ctl.alignedFor
  local V, UP, EAST, clamp, qrot = vector.new, mat.UP, ctx.EAST, mat.clamp, mat.qrot
  local ship, speed, now, dt, slow = ctx.nave, ctx.speed, ctx.agora, ctx.dt, ctx.lento
  local o = ctx.orb
  local g, dsd, inSpace, ecc, dist, vr = o.g, o.dsd, o.inSpace, o.ecc, o.dist, o.vr
  local tilt, err, gx, gz = 0, 0, 0, 0
```

Em seguida vem o corpo do ramo do `if/elseif` antigo, **sem alteração**, e ele termina com:

```lua
  ctx.nave = ship
  ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz = tilt, err, gx, gz
```

Trocas de nome dentro do corpo: `orb` → `ctx.mem` (orbita), `deorbit` → `ctx.mem` (deorbit), `land` → `ctx.mem` (pouso), `tiltT` → `ctx.mem.tiltT` (subida), `bestEcc` → `ctx.mem.bestEcc` (orbita), `orb.vrOk` → `o.vrOk`, `rcs.names` → `Rcs.estado.names`, `rcs.failed` → `Rcs.estado.failed`, `rcsReady()` → `Rcs.ready()`, `rcsControl(` → `Rcs.control(`, `rcsCalibrate(` → `Rcs.calibrate(`, `rcsOff()` → `Rcs.off()`, `readShip()` → `Sens.readShip()`, `orbitDir(` → `Sp.orbitDir(`, `periAlt(` → `Sp.periAlt(`, `lastThrottleN[S.stage]` → `Mot.ultimoAcelerador(S.stage)`.

- [ ] **Passo 1: criar `lib/foguete/fases/subida.lua`** (ASCENT e BALISTICO)

```lua
-- lib/foguete/fases/subida.lua : subida com gravity turn (ASCENT) e subida sem combustivel (BALISTICO)
local mat = require("foguete.mat")
local F = { fases = { "ASCENT", "BALISTICO" } }

function F.novaMemoria() return {} end

function F.tick(ctx)
  -- (cabecalho padrao do ctx)
  -- corpo de voo.lua:986-1016 (dentro do 'if S.phase == "ASCENT" or S.phase == "BALISTICO" then'),
  -- com 'tiltT' -> 'ctx.mem.tiltT'
  -- (rodape padrao)
end

function F.estabilizador(ctx) return ctx.cfg.stab_ascent == true end

return F
```

- [ ] **Passo 2: criar `lib/foguete/fases/orbita.lua`** (COAST e CIRC)

```lua
-- lib/foguete/fases/orbita.lua : espera o apoastro (COAST) e circulariza (CIRC)
local mat = require("foguete.mat")
local F = { fases = { "COAST", "CIRC" } }

function F.novaMemoria() return { flips = 0, bestEcc = math.huge } end

function F.tick(ctx)
  -- (cabecalho padrao do ctx)
  local orb = ctx.mem
  -- corpo de voo.lua:1170-1269 sem alteracao, com:
  --   'bestEcc' -> 'orb.bestEcc'; 'orb.vrOk' -> 'o.vrOk'; RCS pela regra de traducao;
  --   'ship = readShip()' -> 'ship = Sens.readShip()'
  -- (rodape padrao)
end

function F.estabilizador(ctx)
  if ctx.S.phase == "COAST" then return not ctx.mem.orienting end
  return ctx.mem.burning == true
end

return F
```

- [ ] **Passo 3: criar `deorbit.lua`, `reentrada.lua` e `pouso.lua`**

```lua
-- lib/foguete/fases/deorbit.lua : queima contra o movimento orbital ate o periastro baixar
local mat = require("foguete.mat")
local F = { fases = { "DEORBIT" } }
function F.novaMemoria(S) return { sign = S.deorbitSign or 1, lastPeri = nil, lastT = os.clock(), flips = 0 } end
function F.tick(ctx)
  -- (cabecalho padrao do ctx)
  local deorbit = ctx.mem
  -- corpo de voo.lua:1020-1049 sem alteracao
  -- (rodape padrao)
end
function F.estabilizador(ctx) return ctx.mem.burning == true end
return F
```

```lua
-- lib/foguete/fases/reentrada.lua : motores desligados, esperando voltar ao overworld
local F = { fases = { "REENTRADA" } }
function F.novaMemoria() return {} end
function F.tick(ctx)
  local S, dsd, inSpace = ctx.S, ctx.orb.dsd, ctx.orb.inSpace
  if ctx.lento and dsd and not inSpace then
    ctx.mot.ignite(S.stage)
    ctx.mot.setThrottle(S.stage, 0)
    ctx.trocar("POUSO", "voltou ao overworld")
  end
end
function F.estabilizador() return true end
return F
```

```lua
-- lib/foguete/fases/pouso.lua : pouso controlado (perfil de velocidade + freio lateral + toque no chao)
local mat = require("foguete.mat")
local F = { fases = { "POUSO" } }
function F.novaMemoria() return { lastErr = 180, lastThr = 0, I = 0 } end
function F.tick(ctx)
  -- (cabecalho padrao do ctx)
  local land = ctx.mem
  -- corpo de voo.lua:1060-1167 sem alteracao (ja sem o Gyrodyne da Tarefa 6), com:
  --   'rcsReady()' -> 'ctx.rcs.ready()', 'rcsControl(' -> 'ctx.rcs.control(',
  --   '(lastThrottleN[S.stage] or 0)' -> '(Mot.ultimoAcelerador(S.stage) or 0)'
  -- (rodape padrao)
end
function F.estabilizador(ctx) return ctx.mem.lastErr < ctx.cfg.land_align_deg end
return F
```

`novaMemoria` do deorbit recebe `S`. O laço chama `F.novaMemoria(S)` para todos os módulos, e os outros ignoram o parâmetro.

- [ ] **Passo 4: criar `lib/foguete/fases/plataforma.lua`**

```lua
-- lib/foguete/fases/plataforma.lua : checagem, espera do botao e contagem (fase PAD)
local F = {}

-- devolve false se a contagem foi abortada
function F.preparar(ctx)
  local S, CFG, L = ctx.S, ctx.cfg, ctx.log
  local safeAll, preflight, show = ctx.mot.safeAll, ctx.chk.preflight, ctx.tela.show
  local readShip, setPhase, csvLine = ctx.sens.readShip, ctx.trocar, ctx.tel.csvLine
  -- corpo de voo.lua:761-803 sem alteracao, trocando o 'return' de dentro da contagem (linha 795) por 'return false'
  return true
end

return F
```

- [ ] **Passo 5: criar `lib/foguete/laco.lua`**

```lua
-- lib/foguete/laco.lua : laco principal do voo, 'voo descer' e limpeza apos crash
local mat = require("foguete.mat")
local estado = require("foguete.estado")
local M = {}

local MODULOS_FASE = { "subida", "orbita", "deorbit", "reentrada", "pouso" }

function M.novo(args, L, CFG, DESCONHECIDAS, STATE_FILE)
  local V = vector.new
  local UP = mat.UP
  local EAST = V(CFG.east[1], CFG.east[2], CFG.east[3]):normalize()
  local clamp = mat.clamp
  local E = estado.novo(STATE_FILE, L)
  local S = E.proxy
  local save, load, setPhase = E.salvar, E.carregar, E.trocar
  local Sens = require("foguete.sensores")
  local readShip, gravity = Sens.readShip, Sens.gravity
  local Mot = require("foguete.motores").novo(CFG, E, L)
  local shutdown, ignite, setThrottle, orientThrottle = Mot.shutdown, Mot.ignite, Mot.setThrottle, Mot.orientThrottle
  local logEngines, stageStatus = Mot.logEngines, Mot.stageStatus
  local Sp = require("foguete.sputnik").novo(CFG, Mot)
  local sputnik = Sp.dados
  local Ctl = require("foguete.controle").novo(CFG, E, L, Mot)
  local stabilizer = Ctl.stabilizer
  local Sep = require("foguete.separacao").novo(CFG, E, L, Mot)
  local separate, checkBoosterDrop = Sep.separate, Sep.checkBoosterDrop
  local Tela = require("foguete.tela").novo(CFG, L)
  local show = Tela.show
  local TelCsv = require("foguete.telemetria").novo(L)
  local csvLine = TelCsv.csvLine
  local Rcs = require("foguete.rcs").novo(CFG, E, L, Mot, Sens)
  local Chk = require("foguete.checagem").novo(CFG, E, L, Mot, Sens, Ctl, Rcs, DESCONHECIDAS)
  local Plataforma = require("foguete.fases.plataforma")
  local porFase = {}
  for _, nome in ipairs(MODULOS_FASE) do
    local F = require("foguete.fases." .. nome)
    F.nome = nome
    for _, f in ipairs(F.fases) do porFase[f] = F end
  end

  local function voo()
    load()
    if not estado.FASES[S.phase] then
      printError(("Fase desconhecida no estado.txt: %s. Use 'voo reset' para comecar de novo."):format(tostring(S.phase)))
      return
    end
    -- corpo de voo.lua:750-758 (logFile, failed, isInPlotGrid) sem alteracao
    if S.phase == "PAD" then
      local ctx0 = { S = S, cfg = CFG, log = L, trocar = setPhase, mot = Mot, chk = Chk, tela = Tela, sens = Sens, tel = TelCsv }
      if not Plataforma.preparar(ctx0) then return end
    else
      L.section("RETOMANDO VOO na fase " .. S.phase)
    end
    -- corpo de voo.lua:808-824 sem alteracao (fases terminais, comandos ao retomar),
    -- trocando 'rcsDiscover() rcsOff()' por 'Rcs.discover() Rcs.off()'
    local memorias = {}
    for _, nome in ipairs(MODULOS_FASE) do
      memorias[nome] = require("foguete.fases." .. nome).novaMemoria(S)
    end
    -- variaveis do laco: voo.lua:830-843, SEM 'land', 'deorbit', 'orb', 'bestEcc',
    -- 'calT/calVy/calTicks' e 'engT', e COM:
    local Tel = require("foguete.telemetria").novo(L)
    local vrOk = false
    while true do
      -- inicio do tick: voo.lua:846-886 sem alteracao, com 'orb.vrOk = true' -> 'vrOk = true'
      --   e 'orb.dumped' -> 'vrState.dumped' (declarar 'local vrState = {}' antes do while)
      -- boosters: Sep.confirmarIgnicao (Tarefa 5) e checkBoosterDrop (voo.lua:913)
      -- equilibrio: Mot.equilibrar (Tarefa 4)
      -- troca de estagio: voo.lua:957-983 sem alteracao
      local F = porFase[S.phase]
      local tilt, err, gx, gz = 0, 0, 0, 0
      if F then
        local ctx = {
          S = S, cfg = CFG, log = L, trocar = setPhase,
          mot = Mot, ctl = Ctl, sp = Sp, rcs = Rcs, sens = Sens, sep = Sep, tela = Tela, chk = Chk, tel = Tel,
          EAST = EAST, nave = ship, speed = speed, agora = now, dt = dt, lento = slow,
          orb = { dsd = dsd, inSpace = inSpace, ecc = ecc, dist = dist, vr = vr, g = g, vrOk = vrOk },
          saida = { tilt = 0, err = 0, gx = 0, gz = 0 },
          mem = memorias[F.nome],
        }
        F.tick(ctx)
        ship = ctx.nave
        tilt, err, gx, gz = ctx.saida.tilt, ctx.saida.err, ctx.saida.gx, ctx.saida.gz
      end
      Tel.fisica(ship, now, thrust, g, err, gx, gz, Ctl.lastW())
      Tel.motores(now, burnStart, S, ship, Mot)
      local Fs = porFase[S.phase]
      stabilizer(Fs and Fs.estabilizador({ S = S, cfg = CFG, mem = memorias[Fs.nome] }) or false)
      -- fim do tick: voo.lua:1303-1330 sem alteracao (ja sem Gyrodyne), com 'rcsOff()' -> 'Rcs.off()',
      --   'csvLine(' -> 'Tel.csvLine(' e 'steerCount' -> 'Ctl.steerCount()'
    end
  end

  local function descer()
    -- corpo de voo.lua:1337-1361 sem alteracao, com 'args[2]' vindo do parametro 'args'
  end

  local function limpar()
    pcall(shutdown, S.stage)
    pcall(Rcs.off)
    pcall(stabilizer, false)
  end

  return { voo = voo, descer = descer, teste = Chk.teste, rcsTeste = Rcs.teste, S = S, limpar = limpar }
end

return M
```

**Atenção à ordem:** a decisão do estabilizador usa a fase **depois** do tick (`porFase[S.phase]`), como no código antigo (`voo.lua:1294-1302` roda depois da troca de fase feita dentro do ramo). A fase terminal não tem módulo, então dá `false`, igual ao `wantStab = false` inicial.

- [ ] **Passo 6: `voo.lua` vira só a entrada**

Substituir o `voo.lua` inteiro por:

```lua
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
```

- [ ] **Passo 7: rodar os cenários**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`. Se algum der `DIFERENTE`, o `diff` mostra o primeiro comando fora de ordem. A causa quase sempre é um trecho movido para fora do lugar ou uma variável do laço que devia estar em `ctx.mem` (ou o contrário). Corrija o módulo e rode de novo. **Não regrave a referência.**

- [ ] **Passo 8: conferir o tamanho dos arquivos**

Run: `wc -l voo.lua lib/foguete/*.lua lib/foguete/fases/*.lua`
Esperado: nenhum arquivo acima de ~250 linhas. Se o `laco.lua` passar disso, mover a troca de estágio (`voo.lua:957-983`) para uma função `trocaEstagio(...)` em `lib/foguete/separacao.lua`, na mesma posição de chamada.

- [ ] **Passo 9: commit**

```bash
git add -A lib voo.lua
git commit -m "Uma fase por arquivo e laco principal separado; voo.lua vira so a entrada"
```

---

### Tarefa 8: proteções novas (instalação incompleta e fase desconhecida)

**Arquivos:**
- Criar: `ferramentas/sim/cenarios/instalacao_incompleta.lua`, `ferramentas/sim/cenarios/fase_desconhecida.lua`

**Interfaces:**
- Consome: `voo.lua` e `laco.lua` da Tarefa 7.

- [ ] **Passo 1: cenário de instalação incompleta**

```lua
-- instalacao_incompleta: falta um modulo em /lib -> mensagem clara e nenhum motor acionado
return {
  semReferencia = true,
  limite = 10,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0}, turn_start_alt=250,
 turn_end_angle=55, stages={{engines={"rocketnautics:vector_thruster_1"}}}, max_gimbal=0.6, launch_side="left",
 min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0 }',
  mundo = { modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60,
    motores = { ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" } } },
  passos = { { "#arquivo", "lib/foguete/fases/pouso.lua", false }, { "voo.lua" } },
  verificar = function(A)
    local erros, msg = {}, false
    for _, l in ipairs(A.rastro) do
      if l:find("call ", 1, true) then erros[#erros + 1] = "acionou periferico: " .. l end
      if l:find("Arquivo lib/foguete/fases/pouso.lua faltando, rode atualizar", 1, true) then msg = true end
    end
    if not msg then erros[#erros + 1] = "sem a mensagem de arquivo faltando" end
    return erros
  end,
}
```

- [ ] **Passo 2: cenário de fase desconhecida**

```lua
-- fase_desconhecida: estado.txt com fase invalida -> mensagem e nenhum motor acionado
return {
  semReferencia = true,
  limite = 10,
  config = [[return { max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0}, turn_start_alt=250,
 turn_end_angle=55, stages={{engines={"rocketnautics:vector_thruster_1"}}}, max_gimbal=0.6, launch_side="left",
 min_twr=1.15, countdown=10, turn_end_y=16000, gimbal_sign=1, transfer_y=20000 }]],
  estado = '{ phase = "VOANDO", stage = 1, failed = {}, t0 = 0 }',
  mundo = { modo = "atmosfera", pos = { 0, 63, 0 }, chao = 60,
    motores = { ["rocketnautics:vector_thruster_1"] = { tipo = "vector_thruster" } } },
  passos = { { "voo.lua" } },
  verificar = function(A)
    local erros, msg = {}, false
    for _, l in ipairs(A.rastro) do
      if l:find("call ", 1, true) then erros[#erros + 1] = "acionou periferico: " .. l end
      if l:find("Fase desconhecida no estado.txt: VOANDO", 1, true) then msg = true end
    end
    if not msg then erros[#erros + 1] = "sem a mensagem de fase desconhecida" end
    return erros
  end,
}
```

- [ ] **Passo 3: rodar**

Run: `py ferramentas/sim/testar.py instalacao_incompleta fase_desconhecida`
Esperado: os dois `ok` (as proteções já foram escritas na Tarefa 7). Se algum `FALHOU`, corrija `voo.lua` (checagem de `MODULOS`) ou `laco.lua` (checagem de `estado.FASES`).

- [ ] **Passo 4: rodar tudo e fazer o commit**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`.

```bash
git add ferramentas/sim/cenarios
git commit -m "Testes de instalacao incompleta e fase desconhecida"
```

---

### Tarefa 9: `arquivos.txt`, atualizador "tudo ou nada" e versão da Sputnik

**Arquivos:**
- Criar: `arquivos.txt`, `ferramentas/sim/cenarios/atualizar.lua`
- Modificar: `atualizar.lua` (reescrito), `sputnik_guiagem.lua` (só a primeira linha)

**Interfaces:**
- Consome: `http` do simulador (Tarefa 1), `servirRepo`.
- Produz: `atualizar` que lê `arquivos.txt`.

- [ ] **Passo 1: escrever o cenário do atualizador (falha com o atualizador antigo)**

```lua
-- atualizar: instalacao completa; depois falha de rede e erro de sintaxe nao trocam nada
local function tem(A, p) return A.arquivos[p] ~= nil end
return {
  semReferencia = true,
  servirRepo = true,
  limite = 30,
  arquivos = {
    -- computador com a instalacao antiga
    ["lib/foguete/laco.lua"] = false, ["lib/foguete/log.lua"] = false,
    ["log.lua"] = "-- log antigo\nreturn {}\n",
    ["voo.lua"] = "-- voo antigo\n",
    ["config.lua"] = "return { meu = true }\n",
    ["estado.txt"] = '{ phase = "COAST" }',
  },
  passos = {
    { "atualizar.lua" },
    { "#arquivo", "voo.lua", "-- marcador\n" },
    { "#servidor", "lib/foguete/pouso_extra.lua", false },
    { "#servidor", "arquivos.txt", "voo.lua\nlib/foguete/nao_existe.lua\n" },
    { "atualizar.lua" },
    { "#servidor", "arquivos.txt", "voo.lua\nsetup.lua\n" },
    { "#servidor", "setup.lua", "isto nao compila (\n" },
    { "atualizar.lua" },
  },
  verificar = function(A)
    local e = {}
    if not tem(A, "lib/foguete/laco.lua") then e[#e + 1] = "nao baixou lib/foguete/laco.lua" end
    if tem(A, "log.lua") then e[#e + 1] = "nao removeu o log.lua antigo da raiz" end
    if A.arquivos["config.lua"] ~= "return { meu = true }\n" then e[#e + 1] = "mexeu no config.lua" end
    if A.arquivos["estado.txt"] ~= '{ phase = "COAST" }' then e[#e + 1] = "mexeu no estado.txt" end
    if A.arquivos["voo.lua"] ~= "-- marcador\n" then e[#e + 1] = "trocou voo.lua mesmo com falha de rede ou de sintaxe" end
    if A.arquivos["setup.lua"] == "isto nao compila (\n" then e[#e + 1] = "gravou arquivo com erro de sintaxe" end
    return e
  end,
}
```

Run: `py ferramentas/sim/testar.py atualizar`
Esperado: `FALHOU` (o atualizador antigo não conhece `arquivos.txt` nem `/lib`).

- [ ] **Passo 2: criar `arquivos.txt`**

```text
# Arquivos baixados pelo 'atualizar' (um por linha). Linhas depois de "remover:" sao apagadas.
voo.lua
setup.lua
logs.lua
parar.lua
startup.lua
atualizar.lua
diagnostico.lua
sputnik_guiagem.lua
lib/foguete/log.lua
lib/foguete/config.lua
lib/foguete/estado.lua
lib/foguete/mat.lua
lib/foguete/sensores.lua
lib/foguete/sputnik.lua
lib/foguete/motores.lua
lib/foguete/controle.lua
lib/foguete/separacao.lua
lib/foguete/checagem.lua
lib/foguete/tela.lua
lib/foguete/telemetria.lua
lib/foguete/rcs.lua
lib/foguete/laco.lua
lib/foguete/fases/plataforma.lua
lib/foguete/fases/subida.lua
lib/foguete/fases/orbita.lua
lib/foguete/fases/deorbit.lua
lib/foguete/fases/reentrada.lua
lib/foguete/fases/pouso.lua
remover:
log.lua
```

- [ ] **Passo 3: reescrever `atualizar.lua`**

```lua
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
  for linha in txt:gmatch("[^\r\n]+") do
    linha = linha:match("^%s*(.-)%s*$")
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
```

- [ ] **Passo 4: versão no `sputnik_guiagem.lua`**

Inserir como **primeira linha** do arquivo: `-- versao: 1`

- [ ] **Passo 5: rodar**

Run: `py ferramentas/sim/testar.py`
Esperado: todos `ok`, incluindo `atualizar`.

- [ ] **Passo 6: commit**

```bash
git add arquivos.txt atualizar.lua sputnik_guiagem.lua ferramentas/sim/cenarios/atualizar.lua
git commit -m "Atualizador tudo-ou-nada com lista em arquivos.txt"
```

---

### Tarefa 10: documentação

**Arquivos:**
- Modificar: `README.md`, `HANDOFF.md`

- [ ] **Passo 1: `README.md`**
  - Seção de instalação: primeira vez com `wget .../atualizar.lua` e depois `atualizar` **duas vezes** (a primeira baixa o atualizador novo; a segunda, a pasta `/lib`).
  - Seção "Arquivos": a tabela de comandos da raiz e a de módulos de `/lib/foguete`, copiadas da spec (seção 1).
  - Seção "Simulador": `pip install lupa` e `py ferramentas/sim/testar.py` (e `--gravar`), no lugar dos `sim*.py`.

- [ ] **Passo 2: `HANDOFF.md`**
  - Tabela "Arquivos" com o mapa novo.
  - Seção "Como o voo funciona" dizendo que cada fase fica em `lib/foguete/fases/` e que os padrões do config ficam em `lib/foguete/config.lua` (`PADROES`).
  - Seção "Simulador" com `ferramentas/sim/`, os cenários e a regra: **toda mudança de comportamento regrava a referência de propósito, com o motivo no commit**.
  - Remover a menção ao Gyrodyne em "Como o voo funciona".

- [ ] **Passo 3: conferir os links e os comandos citados**

Run: `grep -n "sim.py\|sim2\|sim3\|gyro" README.md HANDOFF.md`
Esperado: só a menção histórica à remoção do Gyrodyne, se houver.

- [ ] **Passo 4: commit e push do branch**

```bash
git add README.md HANDOFF.md
git commit -m "Documentacao da nova organizacao em modulos"
git push origin refatoracao-modulos
```

---

## Validação final no jogo (pelo dono, depois da Tarefa 10)

1. No computador do foguete: `atualizar` e depois `atualizar` de novo.
2. `voo teste`: mesmo resultado de antes (TWR, avisos).
3. Voo normal. Mandar o log (`logs lista`) para comparar com um voo anterior.
4. O `sputnik_guiagem.lua` só ganhou a linha `-- versao: 1`, então **não é preciso** colar de novo na Sputnik.
5. Merge de `refatoracao-modulos` no `main` depois do teste.
