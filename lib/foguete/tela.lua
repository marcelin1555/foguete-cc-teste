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
