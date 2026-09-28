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
