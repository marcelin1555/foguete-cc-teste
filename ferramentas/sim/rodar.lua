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
