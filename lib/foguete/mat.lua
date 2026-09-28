-- lib/foguete/mat.lua : vetores, quaternions e utilidades
local M = {}
local V = vector.new
M.UP = V(0, 1, 0)

function M.clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- nomes dos perifericos sem repeticao (com 2 modems na mesma rede o CC lista cada um 2 vezes)
function M.periNames()
  local seen, out = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if not seen[n] then seen[n] = true out[#out + 1] = n end
  end
  return out
end

function M.qrot(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return V(v.x + qw * tx + (qy * tz - qz * ty),
           v.y + qw * ty + (qz * tx - qx * tz),
           v.z + qw * tz + (qx * ty - qy * tx))
end
function M.toLocal(q, v) return M.qrot({ -q[1], -q[2], -q[3], q[4] }, v) end

function M.quatParts(o)
  if o.v then return { o.v.x, o.v.y, o.v.z, o.a } end
  return { o.x, o.y, o.z, o.w }
end

return M
