-- lib/foguete/fases/plataforma.lua : checagem, espera do botao e contagem (fase PAD)
local F = {}

-- devolve false se a contagem foi abortada
function F.preparar(ctx)
  local S, CFG, L = ctx.S, ctx.cfg, ctx.log
  local safeAll, preflight, show = ctx.mot.safeAll, ctx.chk.preflight, ctx.tela.show
  local readShip, setPhase, csvLine = ctx.sens.readShip, ctx.trocar, ctx.csvLine
  L.section("PREPARACAO")
  safeAll("foguete na plataforma")
  local errs, warns, twr = preflight()
  local lines = { "== FOGUETE NA PLATAFORMA ==", ("TWR E1: %.2f  estagios: %d"):format(twr or 0, #CFG.stages) }
  for _, e in ipairs(errs) do table.insert(lines, "ERRO: " .. e) end
  for _, w in ipairs(warns) do table.insert(lines, "AVISO: " .. w) end
  if #errs > 0 then
    table.insert(lines, "Corrija os erros. F = forcar mesmo assim")
  else
    table.insert(lines, "Aperte o botao (" .. CFG.launch_side .. ") ou digite L")
  end
  show(lines)
  parallel.waitForAny(
    function()
      if #errs > 0 then while true do os.pullEvent("redstone") end end
      repeat os.pullEvent("redstone") until redstone.getInput(CFG.launch_side)
    end,
    function()
      while true do
        local _, c = os.pullEvent("char")
        c = c:lower()
        if (c == "l" and #errs == 0) or c == "f" then
          if c == "f" then L.warn("Lancamento FORCADO com %d erros", #errs) end
          return
        end
      end
    end)
  for t = CFG.countdown, 1, -1 do
    show({ "== CONTAGEM ==", ("T-%d"):format(t), "Digite A para abortar" })
    local timer = os.startTimer(1)
    while true do
      local ev, p = os.pullEvent()
      if ev == "timer" and p == timer then break end
      if ev == "char" and (p == "a" or p == "A") then
        L.info("Contagem abortada pelo piloto") show({ "ABORTADO" }) return false
      end
    end
  end
  L.section("VOO")
  S.padY = readShip().pos.y
  S.stage, S.t0, S.failed = 1, os.epoch("utc"), {}
  setPhase("ASCENT", "lancamento")
  csvLine({ "t", "fase", "est", "y", "vel", "vy", "massa", "empuxo", "incl", "erro", "gx", "gz", "ecc", "dist" })
  return true
end

return F
