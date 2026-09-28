-- lib/foguete/separacao.lua : Stage Separators e boosters
local M = {}

function M.novo(CFG, E, L, Mot)
  local S = E.proxy
  local function save() E.salvar() end
  local call, typeOf, short, stageEngines, engineLine = Mot.call, Mot.typeOf, Mot.short, Mot.stageEngines, Mot.engineLine

  -- pulso de redstone num Stage Separator (lado do computador ou redstone_relay)
  local function pulse(sep)
    local function set(v)
      if sep.relay then call(sep.relay, "setOutput", sep.side, v)
      else redstone.setOutput(sep.side, v) end
    end
    set(true) sleep(0.3) set(false)
  end

  local function separate(i)
    local sep = CFG.stages[i].separator
    if not sep then return end
    L.info("Separando estagio %d (%s)", i, textutils.serialize(sep, { compact = true }))
    pulse(sep)
  end

  -- boosters em paralelo: acendem junto com os motores liquidos do mesmo estagio e,
  -- quando TODOS acabam, o separador deles solta so os boosters; os liquidos continuam
  local function checkBoosterDrop(i)
    local st = CFG.stages[i]
    if not st or not st.booster_separator then return end
    S.boostersDropped = S.boostersDropped or {}
    if S.boostersDropped[i] then return end
    local boosters = {}
    for _, n in ipairs(st.engines) do
      if typeOf(n) == "booster_thruster" then boosters[#boosters + 1] = n end
    end
    if #boosters == 0 then return end
    local done, fns = {}, {}
    for k, n in ipairs(boosters) do
      fns[k] = function()
        local d = peripheral.isPresent(n) and call(n, "getData") or nil
        done[k] = (not d) or d.is_spent or (S.failed and S.failed[n]) or false
      end
    end
    parallel.waitForAll(table.unpack(fns))
    for k = 1, #boosters do if not done[k] then return end end
    L.info("Boosters do estagio %d esgotados: separando (%s)", i,
      textutils.serialize(st.booster_separator, { compact = true }))
    pulse(st.booster_separator)
    S.boostersDropped[i] = true
    save()
  end

  -- confirma que cada booster acendeu (ate 4 s apos a ignicao; tenta de novo antes de desistir)
  local function confirmarIgnicao(i, since, boosterRetry)
    local fns = {}
    for _, n in ipairs(stageEngines(i)) do
      if typeOf(n) == "booster_thruster" and not S.failed[n] then fns[#fns + 1] = function()
        local d = call(n, "getData")
        if d and not d.ignited and not d.is_spent then
          boosterRetry[n] = (boosterRetry[n] or 0) + 1
          if since < 3 then
            if boosterRetry[n] == 1 then L.warn("%s nao acendeu, tentando de novo", short(n)) end
            call(n, "setActive", true)
          else
            S.failed[n] = true save()
            L.err("%s NAO ACENDEU: sem bloco de carvao logo acima dele, ou potencia 0. %s", short(n), engineLine(n))
          end
        elseif d and d.ignited and boosterRetry[n] and boosterRetry[n] > 0 and not S.failed[n] then
          L.info("%s acendeu apos %d tentativas", short(n), boosterRetry[n])
          boosterRetry[n] = -1
        end
      end end
    end
    if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
  end

  -- troca de estagio quando a lava do estagio acaba; devolve true se acendeu o proximo
  local function trocaEstagio(ship, inSpace)
    L.info("Estagio %d esgotado", S.stage)
    Mot.logEngines("fim_estagio")
    Mot.shutdown(S.stage)
    if S.stage < #CFG.stages then
      separate(S.stage)
      S.stage = S.stage + 1
      save()
      sleep(1)
      Mot.ignite(S.stage)
      if S.phase == "ASCENT" then Mot.setThrottle(S.stage, 1) else Mot.orientThrottle(S.stage) end
      return true
    elseif not S.fuelOut then
      S.fuelOut = true
      if S.phase == "DEORBIT" then
        L.err("Combustivel acabou durante o DEORBIT. Periastro pode nao ter baixado o suficiente.")
        E.trocar("REENTRADA", "sem combustivel no deorbit")
      elseif S.phase == "POUSO" or S.phase == "REENTRADA" then
        L.err("SEM COMBUSTIVEL PARA O POUSO! Y=%.0f vy=%.1f", ship.pos.y, ship.vel.y)
      elseif inSpace or S.phase == "COAST" or S.phase == "CIRC" then
        E.trocar("FIM", "combustivel acabou no espaco")
      else
        E.trocar("BALISTICO", ("combustivel acabou em Y=%.0f, subindo por inercia"):format(ship.pos.y))
      end
    end
    return false
  end

  return { pulse = pulse, separate = separate, checkBoosterDrop = checkBoosterDrop, confirmarIgnicao = confirmarIgnicao,
    trocaEstagio = trocaEstagio }
end

return M
