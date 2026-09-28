import lupa, math, sys
L = lupa.LuaRuntime(unpack_returned_tuples=True)
MODE = sys.argv[1] if len(sys.argv) > 1 else "velocity"   # velocity | novel | inverted
L.execute(r'''
MODE = "%s"
RCSN = tonumber(os.getenv("RCSN") or "8")
STABCFG = os.getenv("STAB") ~= nil
RCS_THROTTLE = os.getenv("NOTHR") == nil
ARGS = { os.getenv("ARG1") }
local files = {}
fs = {}
function fs.getDir(p) return "" end
function fs.combine(a,b) local r = (a=="" and b) or (a.."/"..b) return (r:gsub("^/+","")) end
function fs.exists(p) p=p:gsub("^/+","") if files[p] then return true end for k in pairs(files) do if k:sub(1,#p+1)==p.."/" then return true end end return false end
function fs.delete(p) files[p:gsub("^/","")] = nil end
function fs.getSize(p) return #(files[p:gsub("^/","")] or "") end
function fs.move(a,b) files[b:gsub("^/","")] = files[a:gsub("^/","")] files[a:gsub("^/","")] = nil end
function fs.makeDir() end
function fs.list(d) d=d:gsub("^/+","") local out={} for k in pairs(files) do local n=k:match("^"..d.."/(.+)$") if n then out[#out+1]=n end end return out end
function fs.open(p, m)
  p = p:gsub("^/","")
  if m == "r" then local c = files[p] or "" local it = c:gmatch("([^\n]*)\n") return { readAll=function() return c end, readLine=function() return it() end, close=function() end } end
  if m == "w" then files[p] = "" end
  files[p] = files[p] or ""
  return { write=function(s) files[p]=files[p]..s end, writeLine=function(s) files[p]=files[p]..s.."\n" end,
           flush=function() end, close=function() end }
end
FILES = files
shell = { getRunningProgram=function() return "voo.lua" end }
textutils = { serialize=function(t) local function ser(v) if type(v)=="table" then local r={} for k,x in pairs(v) do r[#r+1]=tostring(k).."="..ser(x) end return "{"..table.concat(r,",").."}" elseif type(v)=="string" then return string.format("%%q",v) else return tostring(v) end end return ser(t) end,
  unserialize=function(s) return load("return "..s)() end }
local clock = 0
os.clock = function() return clock end
os.epoch = function() return math.floor(clock*1000) end
os.date = function(f) if f and f:find("%%Y") then return "2026-09-27_20-00-00" end return "sim" end
function sleep(t) clock = clock + (t or 0.05) end
os.pullEvent = function() clock = clock + 0.05 return "timer" end
os.startTimer = function() return 1 end
parallel = { waitForAll=function(...) for _,f in ipairs({...}) do f() end clock = clock + 0.05 end,
             waitForAny=function(f) f() end }
term = { clear=function() end, setCursorPos=function() end, getCursorPos=function() return 1,1 end, write=function() end }
function print(...) end
function printError(...) io.write("ERR ", table.concat({...}," "), "\n") end
STAB = false STABLOG = {}
redstone = { getInput=function() return false end, setOutput=function(side, v)
  if side == "right" and STAB ~= v then STAB = v STABLOG[#STABLOG+1] = (v and "ON@" or "off@") .. string.format("%%.1f", os.clock()) end
end }

-- vetores
local vmt = {}
vmt.__index = vmt
function vector_new(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vmt) end
vmt.__add=function(a,b) return vector_new(a.x+b.x,a.y+b.y,a.z+b.z) end
vmt.__sub=function(a,b) return vector_new(a.x-b.x,a.y-b.y,a.z-b.z) end
vmt.__mul=function(a,b) if type(a)=="number" then a,b=b,a end return vector_new(a.x*b,a.y*b,a.z*b) end
vmt.__div=function(a,b) return vector_new(a.x/b,a.y/b,a.z/b) end
vmt.__unm=function(a) return vector_new(-a.x,-a.y,-a.z) end
function vmt.length(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vmt.normalize(a) local l=a:length() return vector_new(a.x/l,a.y/l,a.z/l) end
function vmt.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
vector = { new = vector_new }

-- nave: orientacao por quaternion, girada pelo gimbal quando ha empuxo
local ship = { q = {0,0,0.3826834,0.9238795}, w = vector_new(0,0,0), mass=159.5 }  -- comeca inclinada 45 graus
local engines = {}
for i=0,3 do engines["rocketnautics:rocket_thruster_"..i] = {type="rocket_thruster", thrust=0, active=false, lava=1000} end
engines["rocketnautics:vector_thruster_1"] = {type="vector_thruster", thrust=0, active=false, lava=1000, gx=0, gz=0}
-- 8 RCS: giro local (rad/s2) que cada um causa -- o script NAO sabe disso
local RT = { {0.03,0,0.004}, {-0.03,0.002,0}, {0,0,0.03}, {0.003,0,-0.03}, {0,0.02,0}, {0,-0.02,0}, {0.021,0,0.021}, {-0.021,0,-0.021} }
if RCSN == 0 then RT = {} end
-- 4 RCS no nariz apontando para os 4 lados: inclinam nos 2 sentidos de X e Z (e empurram um pouco de lado)
if RCSN == 4 then RT = { {0.028,0,0.002}, {-0.028,0,-0.001}, {0.001,0,0.028}, {0,0,-0.028} } end
-- 4 RCS mal posicionados: todos girando so na rolagem
if RCSN == 44 then RT = { {0,0.02,0}, {0,-0.02,0}, {0,0.02,0}, {0,-0.02,0} } end
for i, t in ipairs(RT) do engines["rocketnautics:rcs_thruster_"..i] = {type="rcs_thruster", active=false, tq=t} end
local function qrot(q, v)
  local qx,qy,qz,qw=q[1],q[2],q[3],q[4]
  local tx=2*(qy*v.z-qz*v.y) local ty=2*(qz*v.x-qx*v.z) local tz=2*(qx*v.y-qy*v.x)
  return vector_new(v.x+qw*tx+(qy*tz-qz*ty), v.y+qw*ty+(qz*tx-qx*tz), v.z+qw*tz+(qx*ty-qy*tx))
end
local function qmul(a,b) return {
  a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2], a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
  a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4], a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]} end

-- orbita: estado Kepler simples (so sma/ecc), prograde real = +Z do mundo
local R, GM = 3000000, 91.9*3025000^2
local orbit = { a=2760742, e=0.0958, alt=22100, vrs=1 }
local truePro = vector_new(0,0,1)
local lastStep = 0
local function step()
  local dt = clock - lastStep
  if dt <= 0 then return end
  lastStep = clock
  -- empuxo total e torque
  local F, gx, gz = 0, 0, 0
  for n,e in pairs(engines) do
    if e.type ~= "rcs_thruster" and e.active and e.lava > 0 then F = F + e.thrust e.lava = math.max(0, e.lava - e.thrust*dt*0.004) end
    if e.type=="vector_thruster" then gx, gz = e.gx, e.gz end
  end
  -- gimbal gira a nave (proporcional ao empuxo) com amortecimento
  local k = F/5000*3.0
  ship.w = ship.w + vector_new(gz*k, 0, -gx*k) * dt * 5
  for n,e in pairs(engines) do
    if e.type=="rcs_thruster" and e.active and RCS_THROTTLE then ship.w = ship.w + vector_new(e.tq[1],e.tq[2],e.tq[3]) * dt end
  end
  if STAB then ship.w = ship.w * 0.2 end
  local ang = ship.w:length()*dt
  if ang > 1e-9 then
    local ax = ship.w:normalize()
    local dq = {ax.x*math.sin(ang/2), ax.y*math.sin(ang/2), ax.z*math.sin(ang/2), math.cos(ang/2)}
    ship.q = qmul(ship.q, dq)
    local n = math.sqrt(ship.q[1]^2+ship.q[2]^2+ship.q[3]^2+ship.q[4]^2)
    for i=1,4 do ship.q[i]=ship.q[i]/n end
  end
  -- empuxo na direcao do nariz muda a orbita (escala desconhecida: 20 unidades orbitais por m/s)
  local nose = qrot(ship.q, vector_new(0,1,0))
  local dv = F/ship.mass*dt*20*nose:dot(truePro)
  local r = R + orbit.alt
  local v = math.sqrt(GM*(2/r - 1/orbit.a)) + dv
  local a = 1/(2/r - v*v/GM)
  -- no apoastro: novo periastro = 2a - r_apo (aprox, queima horizontal)
  local rp = 2*a - r
  local ra = math.max(r, rp) rp = math.min(r, rp)
  orbit.a = a orbit.e = (ra-rp)/(ra+rp)
  -- sobe ate o apoastro e para
  if orbit.vrs > 0 then orbit.alt = math.min(orbit.alt + 150*dt, 25200) if orbit.alt >= 25200 then orbit.vrs = 0 end end
end
SIM = { ship=ship, orbit=orbit, engines=engines }

peripheral = {}
local function names() local t={} for n in pairs(engines) do t[#t+1]=n end t[#t+1]="top" table.sort(t) return t end
function peripheral.getNames() return names() end
function peripheral.isPresent(n) return engines[n] ~= nil or n=="top" end
function peripheral.hasType(n, t) if engines[n] then return t=="thruster" or (t=="fluid_storage" and engines[n].type~="rcs_thruster") end return false end
function peripheral.wrap() return nil end
function peripheral.call(n, fn, ...)
  step()
  local a = {...}
  if n == "top" and fn == "getDeepSpaceData" then
    local o = orbit
    local d = { inDeepSpace=true, eccentricity=o.e, semiMajorAxis=o.a, parentRadius=R, distanceToPlanet=math.floor(o.alt/50)*50,
      gravity=91.8, speed=15850, period=995, inAtmosphere=false, parentBody="overworld" }
    if MODE == "velocity" then d.velocity = {x=0,y=0,z=15850} end
    if MODE == "inverted" then d.velocity = {x=0,y=0,z=-15850} end
    return d
  end
  local e = engines[n]
  if fn == "getData" and e.type == "rcs_thruster" then return { engine_type="rcs_thruster", active=e.active } end
  if e.type == "rcs_thruster" then if fn == "setActive" then e.active = a[1] end return 0 end
  if fn == "getData" then return { engine_type=e.type, active=e.active, fuel_amount=e.lava, fuel_capacity=1000, fuel_usage=40, throttle=1, ignition_ticks=0, warmup_time=10 } end
  if fn == "getThrust" then return (e.active and e.lava>0) and e.thrust or 0 end
  if fn == "setThrust" then e.thrust = a[1] return end
  if fn == "setActive" then e.active = a[1] return end
  if fn == "setGimbal" then e.gx, e.gz = a[1], a[3] return end
  if fn == "tanks" and e.lava then return { { name="minecraft:lava", amount=math.floor(e.lava) } } end
end
sublevel = {
  isInPlotGrid=function() return true end,
  getLogicalPose=function() step() return { position=vector_new(0,1130,0), orientation={x=ship.q[1],y=ship.q[2],z=ship.q[3],w=ship.q[4]} } end,
  getVelocity=function() return vector_new(0,0,0) end,
  getAngularVelocity=function() return qrot(ship.q, ship.w) end,
  getMass=function() return ship.mass end,
}
aero = { getGravity=function() return vector_new(0,0,0) end }
FILES["config.lua"] = [[return { sputnik_guidance=true, max_thrust_n=1000, max_twr=2.5, kp=1.5, kd=0.8, east={1,0,0},
 turn_start_alt=250, turn_end_angle=55, stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}},
 max_gimbal=0.6, launch_side="left", min_twr=1.15, countdown=10, ecc_target=0.02, sputnik="top", turn_end_y=16000,
 steer_throttle=0.08, gimbal_sign=1, transfer_y=20000, stabilizer = STABCFG and {side="right"} or nil }]]
FILES["estado.txt"] = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }'
FILES["log.lua"] = io.open("log.lua"):read("a")
dofile = function(p) p = p:gsub("^/","") return assert(load(FILES[p], p))() end
local lf = loadfile("voo.lua")
local ok, e = pcall(lf, table.unpack(ARGS))
if not ok then print_real = io.write io.write("SCRIPT ERRO: ", tostring(e), "\n") end
io.write("ESTABILIZADOR: ", table.concat(STABLOG, " "), "\n")
''' % MODE)
files = L.globals().FILES
log = ""
for k in files.keys():
    if str(k).endswith(".txt") and "logs/" in str(k): log += files[k]
lines = [l for l in log.split("\n") if "MOTOR" not in l]
print("\n".join(lines[:int(sys.argv[2]) if len(sys.argv)>2 else 40]))
o = L.globals().SIM.orbit
print("FINAL a=%.0f e=%.4f peri=%.0f" % (o.a, o.e, o.a*(1-o.e)-3000000))
print("estado:", files["estado.txt"])
