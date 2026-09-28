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
