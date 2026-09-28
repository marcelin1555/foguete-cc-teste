-- lib/foguete/telemetria.lua : CSV do voo e linhas periodicas FISICA / MOTOR / COMBUSTIVEL
local M = {}

-- csvLine (opcional): reaproveita a escrita de outro objeto de telemetria,
-- para o CSV do voo ter um so arquivo aberto
function M.novo(L, csvLine)
  local csv
  csvLine = csvLine or function(fields)
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
