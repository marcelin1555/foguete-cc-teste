import lupa
L = lupa.LuaRuntime(unpack_returned_tuples=True)
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'sim.py')).read()
lua = src[src.index("L.execute(r'''")+len("L.execute(r'''"):src.index("''' % MODE)")] % "ascent"
# nave reta, sem espaco
lua = lua.replace('local ship = { q = {0,0,0.3826834,0.9238795}', 'local ship = { q = {0,0,0,1}')
lua = lua.replace('''    return d
  end''', '''    if MODE == "ascent" then return { inDeepSpace=false } end
    return d
  end''',1)
# boosters: 4, queimam 15 s depois de acesos
lua = lua.replace('''if RCSN == 0 then RT = {} end''','''if RCSN == 0 then RT = {} end
for i=0,3 do engines["rocketnautics:booster_thruster_"..i] = {type="booster_thruster", ignited=false, t0=nil, spent=false} end
engines["rocketnautics:rocket_thruster_0"] = nil engines["rocketnautics:rocket_thruster_1"] = nil''')
lua = lua.replace('''  if fn == "getData" and e.type == "rcs_thruster" then''','''  if e and e.type == "booster_thruster" then
    if e.ignited and not e.spent and clock - e.t0 > 15 then e.spent = true end
    if fn == "getData" then return { engine_type="booster_thruster", ignited=e.ignited, is_spent=e.spent, fuel_ticks=0, thrust_power=1000 } end
    if fn == "setActive" then if a[1] and not e.ignited then e.ignited=true e.t0=clock end return end
    if fn == "getThrust" then return (e.ignited and not e.spent) and 1000 or 0 end
    return
  end
  if fn == "getData" and e.type == "rcs_thruster" then''')
# separador: pulso no lado "bottom" solta os boosters
lua = lua.replace('''STAB = false STABLOG = {}''', '''STAB = false STABLOG = {}
PULSOS = {}''')
lua = lua.replace('''  if side == "right" and STAB ~= v then''', '''  if v then PULSOS[#PULSOS+1] = side .. "@" .. string.format("%.1f", os.clock()) end
  if v and side == "bottom" then for n in pairs(SIM.engines) do if n:find("booster") then SIM.engines[n] = nil end end end
  if side == "right" and STAB ~= v then''')
lua = lua.replace('''local function step()
  local dt = clock - lastStep''','''local function step()
  if clock > 60 then error("FIM_SIM") end
  local dt = clock - lastStep''')
lua = lua.replace('''  if MODE == "velocity" then''','''  if false then''')
lua = lua.replace('''stages={{engines={"rocketnautics:rocket_thruster_0","rocketnautics:rocket_thruster_1",
 "rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"}}}''','''stages={{engines={"rocketnautics:booster_thruster_0","rocketnautics:booster_thruster_1","rocketnautics:booster_thruster_2",
 "rocketnautics:booster_thruster_3","rocketnautics:rocket_thruster_2","rocketnautics:rocket_thruster_3","rocketnautics:vector_thruster_1"},
 booster_separator={side="bottom"}}}''')
lua = lua.replace('''FILES["estado.txt"] = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }\'''','''FILES["estado.txt"] = '{ phase = "ASCENT", stage = 1, failed = {}, t0 = 0, padY = 1100 }\'''')
lua = lua.replace('''if not ok then print_real = io.write io.write("SCRIPT ERRO: ", tostring(e), "\\n") end''','''if not ok and not tostring(e):find("FIM_SIM") then io.write("SCRIPT ERRO: ", tostring(e), "\\n") end
io.write("PULSOS: ", table.concat(PULSOS, " "), "\\n")
local left = {} for n in pairs(SIM.engines) do left[#left+1] = n end table.sort(left)
io.write("MOTORES NA NAVE: ", table.concat(left, ", "), "\\n")
io.write("ESTADO: ", FILES["estado.txt"], "\\n")''')
lua = lua.replace('''  if fn == "getThrust" then return (e.active and e.lava>0) and e.thrust or 0 end''', '''  if fn == "getThrust" then
    local t = (e.active and e.lava>0) and e.thrust or 0
    if FRACO and n == "rocketnautics:rocket_thruster_2" then t = math.min(t, 400) end
    return t
  end''')
lua = "FRACO = " + ("true" if __import__("os").getenv("FRACO") else "false") + "\n" + lua
L.execute(lua)
files = L.globals().FILES
log = "".join(str(files[k]) for k in files.keys() if str(k).startswith("logs/") and str(k).endswith(".txt"))
for l in log.split("\n"):
    if any(w in l for w in ("Booster","booster","esgotad","FASE","ERRO","AVISO","Separando","Acendendo","limite")) and "MOTOR" not in l:
        print(l)
