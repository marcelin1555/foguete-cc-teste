-- lib/foguete/config.lua : carrega o config.lua do foguete com todos os valores padrao
local M = {}

-- Chaves opcionais e seus padroes (os mesmos valores que ficavam soltos no voo.lua)
M.PADROES = {
  -- apontar antes de acender (espaco e pouso)
  align_deg = 5, align_keep_deg = 15, align_rate = 0.05, orient_throttle = 0.35,
  -- equilibrio de empuxo na subida
  balance_every = 1.5, balance_min = 100, balance_spread = 0.2,
  -- controle de direcao: termo integral
  ki = 0.6, imax = 0.5,
  -- orbita
  orbit_peri_alt = 23000, circ_slow_m = 50000, deorbit_peri = 8000,
  -- pouso
  land_align_deg = 15, land_ceiling_y = 400, land_h_accel = 8, land_max_speed = 120,
  land_max_tilt = 25, land_max_tilt_high = 60, land_offset = 3, land_slow_h = 40, land_speed = 3,
  land_cc_gimbal = true,
  -- Magnetic Stabilizer ligado tambem na subida
  stab_ascent = false,
  -- RCS (so age com rcs_enabled = true)
  rcs_enabled = false, rcs_cal_time = 1.0, rcs_cos = 0.5, rcs_deadband = 0.01, rcs_kd = 1.2,
  rcs_kp = 0.4, rcs_min_resp = 0.002, rcs_timeout = 30,
}

-- Chaves sem padrao (o setup escreve) ou opcionais que ficam vazias
M.OUTRAS = { "stages", "east", "kp", "kd", "max_gimbal", "gimbal_sign", "max_thrust_n", "max_twr", "min_twr",
  "launch_side", "countdown", "transfer_y", "turn_start_alt", "turn_end_y", "turn_end_angle",
  "sputnik", "sputnik_guidance", "stabilizer", "monitor", "ground_y", "steer_throttle", "ecc_target" }

-- devolve a config com os padroes e a lista de chaves desconhecidas (erro de digitacao?)
function M.carregar(caminho)
  local cfg = dofile(caminho)
  local conhecidas = {}
  for k in pairs(M.PADROES) do conhecidas[k] = true end
  for _, k in ipairs(M.OUTRAS) do conhecidas[k] = true end
  local desconhecidas = {}
  for k in pairs(cfg) do
    if not conhecidas[k] then desconhecidas[#desconhecidas + 1] = tostring(k) end
  end
  table.sort(desconhecidas)
  for k, v in pairs(M.PADROES) do
    if cfg[k] == nil then cfg[k] = v end
  end
  for _, st in ipairs(cfg.stages or {}) do
    local seen, list = {}, {}
    for _, n in ipairs(st.engines or {}) do
      if not seen[n] then seen[n] = true list[#list + 1] = n end
    end
    st.engines = list
  end
  return cfg, desconhecidas
end

return M
