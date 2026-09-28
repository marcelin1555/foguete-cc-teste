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
