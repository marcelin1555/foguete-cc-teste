-- ferramentas/sim/mundo.lua
-- Mundo simulado: nave (orientacao, posicao, velocidade), motores, Sputnik,
-- relays e separadores. A fisica e simplificada: serve para testar a logica.
local V = vector.new

local function qrot(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return V(v.x + qw * tx + (qy * tz - qz * ty), v.y + qw * ty + (qz * tx - qx * tz), v.z + qw * tz + (qx * ty - qy * tx))
end
local function qmul(a, b)
  return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end

return function(A, c)
  local M = {}
  local R, GM = 3000000, 91.9 * 3025000 ^ 2
  local nave = { q = c.q or { 0, 0, 0, 1 }, w = V(0, 0, 0), massa = c.massa or 159.5,
    pos = V(table.unpack(c.pos or { 0, 1130, 0 })), vel = V(table.unpack(c.vel or { 0, 0, 0 })) }
  local espaco = c.modo == "espaco"
  local orbita = c.orbita and { a = c.orbita.a, e = c.orbita.e, alt = c.orbita.alt, subir = c.orbita.subir } or nil
  local g = c.g or 11
  local motores, ordem = {}, {}
  for nome, m in pairs(c.motores or {}) do
    motores[nome] = { tipo = m.tipo, empuxo = 0, ativo = false, lava = m.lava or 1000, gx = 0, gz = 0,
      tq = m.tq, potencia = m.potencia or 1000, aceso = false, gasto = false, queima = m.queima or 15,
      semCarvao = m.semCarvao }
    ordem[#ordem + 1] = nome
  end
  table.sort(ordem)
  local extras = {}
  if c.sputnik then extras[c.sputnik] = "sputnik" end
  for _, r in ipairs(c.relays or {}) do extras[r] = "redstone_relay" end
  local estab, ultimo, semEmpuxo = false, A.relogio, 0

  local function passo()
    local dt = A.relogio - ultimo
    if dt <= 0 then return end
    ultimo = A.relogio
    local F, gx, gz = 0, 0, 0
    for _, n in ipairs(ordem) do
      local m = motores[n]
      if m then
        if m.tipo == "booster_thruster" then
          if m.aceso and not m.gasto then
            if A.relogio - m.t0 > m.queima then m.gasto = true else F = F + m.potencia end
          end
        elseif m.tipo ~= "rcs_thruster" and m.ativo and m.lava > 0 then
          F = F + m.empuxo
          m.lava = math.max(0, m.lava - m.empuxo * dt * 0.004)
        end
        if m.tipo == "vector_thruster" then gx, gz = m.gx, m.gz end
      end
    end
    local k = F / 5000 * 3.0
    nave.w = nave.w + V(gz * k, 0, -gx * k) * (dt * 5)
    for _, n in ipairs(ordem) do
      local m = motores[n]
      if m and m.tipo == "rcs_thruster" and m.ativo then nave.w = nave.w + V(m.tq[1], m.tq[2], m.tq[3]) * dt end
    end
    if estab then nave.w = nave.w * 0.2 end
    local ang = nave.w:length() * dt
    if ang > 1e-9 then
      local ax = nave.w:normalize()
      nave.q = qmul(nave.q, { ax.x * math.sin(ang / 2), ax.y * math.sin(ang / 2), ax.z * math.sin(ang / 2), math.cos(ang / 2) })
      local nq = math.sqrt(nave.q[1] ^ 2 + nave.q[2] ^ 2 + nave.q[3] ^ 2 + nave.q[4] ^ 2)
      for i = 1, 4 do nave.q[i] = nave.q[i] / nq end
    end
    local nariz = qrot(nave.q, V(0, 1, 0))
    if espaco then
      -- orbita Kepler simples; o prograde verdadeiro e +Z do mundo
      local dv = F / nave.massa * dt * 20 * nariz:dot(V(0, 0, 1))
      local r = R + orbita.alt
      local v = math.sqrt(GM * (2 / r - 1 / orbita.a)) + dv
      local a = 1 / (2 / r - v * v / GM)
      local rp = 2 * a - r
      local ra = math.max(r, rp) rp = math.min(r, rp)
      orbita.a, orbita.e = a, (ra - rp) / (ra + rp)
      if orbita.subir then
        orbita.alt = math.min(orbita.alt + 150 * dt, 25200)
        if orbita.alt >= 25200 then orbita.subir = false end
      end
      -- reentrada: periastro baixo e motores parados -> cai e volta ao overworld
      if c.reentra and a * (1 - orbita.e) - R < 21000 and F == 0 then
        semEmpuxo = semEmpuxo + dt
        if semEmpuxo > 2 then orbita.alt = orbita.alt - 500 * dt end
        if orbita.alt < 21000 then
          espaco = false
          nave.pos, nave.vel, nave.w = V(table.unpack(c.reentra.pos)), V(table.unpack(c.reentra.vel)), V(0, 0, 0)
          A.registrar("mundo voltou ao overworld")
          A.pedido = "reboot" -- o computador reinicia ao trocar de dimensao
        end
      else
        semEmpuxo = 0
      end
    else
      local acc = nariz * (F / nave.massa) + V(0, -g, 0)
      nave.vel = nave.vel + acc * dt
      nave.pos = nave.pos + nave.vel * dt
      if c.chao and nave.pos.y <= c.chao + 3 then
        nave.pos = V(nave.pos.x, c.chao + 3, nave.pos.z)
        if nave.vel.y < 0 then nave.vel = V(0, 0, 0) end
      end
    end
  end
  M.passo = passo

  local function sputnikDados()
    if not espaco then return { inDeepSpace = false } end
    local o = orbita
    local d = { inDeepSpace = true, eccentricity = o.e, semiMajorAxis = o.a, parentRadius = R,
      distanceToPlanet = math.floor(o.alt / 50) * 50, gravity = 91.8, speed = 15850, period = 995,
      inAtmosphere = false, parentBody = "overworld" }
    if c.sputnikVel == "velocity" then d.velocity = { x = 0, y = 0, z = 15850 } end
    if c.sputnikVel == "inverted" then d.velocity = { x = 0, y = 0, z = -15850 } end
    return d
  end

  function M.nomes()
    local t = {}
    for _, n in ipairs(ordem) do if motores[n] then t[#t + 1] = n end end
    for n in pairs(extras) do t[#t + 1] = n end
    table.sort(t)
    return t
  end
  function M.existe(n) return motores[n] ~= nil or extras[n] ~= nil end
  function M.tipo(n)
    if motores[n] then return motores[n].tipo end
    return extras[n]
  end
  function M.temTipo(n, t)
    local m = motores[n]
    if m then return t == "thruster" or (t == "fluid_storage" and m.tipo ~= "rcs_thruster") end
    return extras[n] == t
  end
  function M.chamar(n, fn, ...)
    local a = { ... }
    if extras[n] == "sputnik" then
      if fn == "getDeepSpaceData" then return sputnikDados() end
      return nil
    end
    if extras[n] == "redstone_relay" then
      if fn == "setOutput" then M.redstone(n, a[1], a[2]) end
      return nil
    end
    local m = motores[n]
    if not m then error("No such peripheral", 0) end
    if m.tipo == "booster_thruster" then
      if fn == "getData" then
        return { engine_type = "booster_thruster", ignited = m.aceso, is_spent = m.gasto, fuel_ticks = 0, thrust_power = m.potencia }
      end
      if fn == "setActive" then
        if a[1] and not m.aceso and not m.semCarvao then m.aceso, m.t0 = true, A.relogio end
        return
      end
      if fn == "getThrust" then return (m.aceso and not m.gasto) and m.potencia or 0 end
      return
    end
    if m.tipo == "rcs_thruster" then
      if fn == "getData" then return { engine_type = "rcs_thruster", active = m.ativo } end
      if fn == "setActive" then m.ativo = a[1] end
      return 0
    end
    if fn == "getData" then
      return { engine_type = m.tipo, active = m.ativo, fuel_amount = m.lava, fuel_capacity = 1000, fuel_usage = 40,
        throttle = 1, ignition_ticks = 0, warmup_time = 10 }
    end
    if fn == "getThrust" then return (m.ativo and m.lava > 0) and m.empuxo or 0 end
    if fn == "setThrust" then m.empuxo = a[1] return end
    if fn == "setActive" then m.ativo = a[1] return end
    if fn == "setGimbal" then m.gx, m.gz = a[1], a[3] return end
    if fn == "tanks" then return { { name = "minecraft:lava", amount = math.floor(m.lava) } } end
  end
  function M.redstone(origem, lado, v)
    local chave = origem .. ":" .. tostring(lado)
    if c.estabilizador == chave then estab = v end
    local sep = (c.separadores or {})[chave]
    if v and sep then
      for _, n in ipairs(sep) do motores[n] = nil end
      A.registrar("mundo separou %s", table.concat(sep, ","))
    end
  end
  function M.resumo()
    local o = orbita and (" a=%.0f e=%.4f"):format(orbita.a, orbita.e) or ""
    return ("mundo final: y=%.2f vy=%.2f espaco=%s%s"):format(nave.pos.y, nave.vel.y, tostring(espaco), o)
  end

  sublevel = {
    isInPlotGrid = function() return true end,
    getLogicalPose = function()
      passo()
      return { position = nave.pos, orientation = { x = nave.q[1], y = nave.q[2], z = nave.q[3], w = nave.q[4] } }
    end,
    getVelocity = function() return nave.vel end,
    getAngularVelocity = function() return qrot(nave.q, nave.w) end,
    getMass = function() return nave.massa end,
  }
  aero = { getGravity = function() if espaco then return V(0, 0, 0) end return V(0, -g, 0) end }
  return M
end
