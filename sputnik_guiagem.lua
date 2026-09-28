-- versao: 1
-- GUIAGEM DO FOGUETE (cole num no "Lua Script" do Sputnik)
-- Roda a cada tick no servidor. Enquanto algum Vector Thruster estiver queimando,
-- aponta o nariz do foguete (+Y do foguete como construido):
--   subindo  -> gravity turn;
--   no espaco, na volta e no pouso -> nao mexe (o computador CC controla).
-- O computador CC cuida de contagem, ignicao, estagios e logs.
-- Tambem deixa o acelerador de todo RCS em 100% (o CC nao consegue; ele so liga/desliga).

---------------- PARAMETROS (ajuste aqui) ----------------
local KP, KD      = 1.5, 0.8   -- forca da correcao / amortecimento
local KI, IMAX    = 0.6, 0.5   -- integral: tira o erro que fica parado (centro de massa torto, motor fraco)
local MAXG        = 0.6        -- gimbal maximo (0..1)
local SIGN        = 1          -- troque para -1 se corrigir para o lado errado
local TURN_START  = 250        -- blocos acima da plataforma para comecar a inclinar
local TURN_END_Y  = 16000      -- Y onde a inclinacao chega no maximo
local TURN_ANGLE  = 55         -- graus a partir da vertical no fim do turn
local EX, EZ      = 1, 0       -- direcao do turn no mundo (1,0 = leste +X)
----------------------------------------------------------

local function qmul(a, b)
  return {
    a[4]*b[1] + a[1]*b[4] + a[2]*b[3] - a[3]*b[2],
    a[4]*b[2] - a[1]*b[3] + a[2]*b[4] + a[3]*b[1],
    a[4]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[4],
    a[4]*b[4] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3] }
end
-- rotaciona o vetor (x,y,z) pelo quaternion q
local function qrot(q, x, y, z)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * z - qz * y)
  local ty = 2 * (qz * x - qx * z)
  local tz = 2 * (qx * y - qy * x)
  return x + qw * tx + (qy * tz - qz * ty),
         y + qw * ty + (qz * tx - qx * tz),
         z + qw * tz + (qx * ty - qy * tx)
end
local function conj(q) return { -q[1], -q[2], -q[3], q[4] } end

-- orientacao atual: getOrientation = Euler YXZ em graus (pitch=X, yaw=Y, roll=Z)
local p, y, r = getOrientation()
p, y, r = math.rad(p) / 2, math.rad(y) / 2, math.rad(r) / 2
local q = qmul(qmul({ 0, math.sin(y), 0, math.cos(y) }, { math.sin(p), 0, 0, math.cos(p) }),
               { 0, 0, math.sin(r), math.cos(r) })

-- velocidade angular no referencial do foguete (rad/s) pela diferenca entre ticks
local wx, wz = 0, 0
if _G.prevQ then
  local dq = qmul(conj(_G.prevQ), q)
  if dq[4] < 0 then dq = { -dq[1], -dq[2], -dq[3], -dq[4] } end
  wx, wz = 2 * dq[1] / 0.05, 2 * dq[3] / 0.05
end
_G.prevQ = q

-- motores vetoriais e se algum esta queimando
local vectors, running = {}, false
for _, id in ipairs(getPeripheralIds() or {}) do
  local t = tostring(getPeripheralType(id))
  if t == "vector_engine" then
    vectors[#vectors + 1] = id
    if (readPeripheral(id, "thrust") or 0) > 1 then running = true end
  elseif t == "rcs" and (readPeripheral(id, "throttle") or 0) < 0.99 then
    -- o computador CC so liga/desliga o RCS; o acelerador dele so da para ajustar daqui
    writePeripheral(id, "throttle", 1)
  end
end

local alt = getAltitude()
local vx, vy, vz = getVelocity()
local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
if not running then
  _G.padY = nil -- no chao: memoriza a plataforma na proxima ignicao
  _G.ix, _G.iz = 0, 0 -- zera o integral entre voos
  if speed < 0.5 then _G.voltando = nil end -- parado no chao: proximo voo e uma subida
  return
end
_G.padY = _G.padY or alt

-- direcao alvo no mundo
local tx, ty, tz
local inSpace = (getDimension and tostring(getDimension()):find("deep_space")) ~= nil
if inSpace then _G.voltando = true end
if inSpace or _G.voltando or vy < -2 then
  -- no espaco e em toda a volta (deorbit, reentrada, pouso) quem aponta e o
  -- computador CC. Se os dois mexerem no gimbal ao mesmo tempo, eles brigam.
  return
else
  local tilt = 0
  local above = alt - _G.padY
  if above > TURN_START then
    local f = math.min(1, math.max(0, (above - TURN_START) / (TURN_END_Y - _G.padY - TURN_START)))
    tilt = TURN_ANGLE * f ^ 0.6
  end
  local rt = math.rad(tilt)
  tx, ty, tz = EX * math.sin(rt), math.cos(rt), EZ * math.sin(rt)
end

-- alvo no referencial do foguete (nariz = +Y)
local dx, dy, dz = qrot(conj(q), tx, ty, tz)
if dy < 0 then -- alvo atras: esterca no maximo
  local m = math.sqrt(dx * dx + dz * dz)
  if m < 1e-6 then dx, m = 1, 1 end
  dx, dz = dx / m, dz / m
end

-- integral (20 ticks/s): cresce enquanto sobrar erro, limitado para nao embalar
_G.ix = math.max(-IMAX, math.min(IMAX, (_G.ix or 0) + dx * 0.05))
_G.iz = math.max(-IMAX, math.min(IMAX, (_G.iz or 0) + dz * 0.05))
local gx = math.max(-MAXG, math.min(MAXG, SIGN * (KP * dx + KD * wz + KI * _G.ix)))
local gz = math.max(-MAXG, math.min(MAXG, SIGN * (KP * dz - KD * wx + KI * _G.iz)))
for _, id in ipairs(vectors) do
  writePeripheralValues(id, "gimbal", gx, gz)
end
