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
