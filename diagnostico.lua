-- diagnostico.lua : lista tudo que o computador enxerga (para achar motor/modem com problema)
-- Uso: diagnostico           -> mostra na tela e grava em /logs/..._diagnostico.txt

local lines = {}
local function out(fmt, ...)
  local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  lines[#lines + 1] = s
end

out("== DIAGNOSTICO %s ==", os.date("%d/%m/%Y %H:%M:%S"))

-- lados do computador: o que esta encostado direto
out("")
out("-- Lados do computador --")
for _, side in ipairs(redstone.getSides()) do
  local t = peripheral.getType(side)
  if t then
    local extra = ""
    if t == "modem" then
      local m = peripheral.wrap(side)
      extra = m.isWireless() and " (sem fio)" or (" (com fio, " .. #m.getNamesRemote() .. " perifericos na rede)")
    end
    out("%-6s %s%s", side, t, extra)
  end
end

-- tudo que esta na rede, sem repetir
out("")
out("-- Perifericos --")
local seen, names = {}, {}
for _, n in ipairs(peripheral.getNames()) do
  if not seen[n] then seen[n] = true names[#names + 1] = n end
end
table.sort(names)
local count = { vector = 0, rocket = 0, rcs = 0, booster = 0, outro = 0 }
for _, n in ipairs(names) do
  local types = { peripheral.getType(n) }
  local info = ""
  if peripheral.hasType(n, "thruster") then
    local ok, d = pcall(peripheral.call, n, "getData")
    local et = ok and type(d) == "table" and d.engine_type or "?"
    if et == "vector_thruster" then count.vector = count.vector + 1
    elseif et == "rocket_thruster" then count.rocket = count.rocket + 1
    elseif et == "rcs_thruster" then count.rcs = count.rcs + 1
    elseif et == "booster_thruster" then count.booster = count.booster + 1
    else count.outro = count.outro + 1 end
    info = " -> motor " .. tostring(et)
    if ok and type(d) == "table" and d.fuel_amount then
      info = info .. (" lava=%s/%s"):format(tostring(d.fuel_amount), tostring(d.fuel_capacity))
    end
  end
  out("%s [%s]%s", n, table.concat(types, ","), info)
end

-- config atual
out("")
out("-- config.lua --")
if fs.exists("config.lua") then
  local ok, cfg = pcall(dofile, "config.lua")
  if ok and type(cfg) == "table" then
    for i, st in ipairs(cfg.stages or {}) do
      out("estagio %d: %s", i, table.concat(st.engines or {}, ", "))
      for _, n in ipairs(st.engines or {}) do
        if not seen[n] then out("  ! %s esta na config mas NAO esta conectado", n) end
      end
    end
  else
    out("config.lua com erro: %s", tostring(cfg))
  end
else
  out("sem config.lua (rode setup)")
end

-- resumo
out("")
out("-- Resumo --")
out("Vector Thruster: %d | Rocket Thruster: %d | RCS: %d | Booster: %d", count.vector, count.rocket, count.rcs, count.booster)
if count.vector == 0 then
  out("SEM VECTOR THRUSTER NA REDE. Confira:")
  out(" 1. modem encostado no Vector Thruster e clicado (fica VERMELHO)")
  out(" 2. cabo ligando esse modem ate a rede do computador")
  out(" 3. se e o Vector Thruster do Cosmonautics (o do AeroIE nao aparece aqui)")
end

-- mostra e grava
textutils.pagedPrint(table.concat(lines, "\n"))
if not fs.exists("/logs") then fs.makeDir("/logs") end
local path = "/logs/" .. os.date("%Y-%m-%d_%H-%M-%S") .. "_diagnostico.txt"
local f = fs.open(path, "w")
f.write(table.concat(lines, "\n") .. "\n")
f.close()
print("Gravado em " .. path)
