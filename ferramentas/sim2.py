import lupa, sys
L = lupa.LuaRuntime(unpack_returned_tuples=True)
src = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'sim.py')).read()
lua = src[src.index("L.execute(r'''")+len("L.execute(r'''"):src.index("''' % MODE)")] % "velocity"
# fs extra: pasta/lista
lua = lua.replace('function fs.open(p, m)', '''function fs.makeDir() end
function fs.list(d) d=d:gsub("^/","") local out={} for k in pairs(files) do local n=k:match("^"..d.."/(.+)$") if n then out[#out+1]=n end end return out end
function fs.open(p, m)''')
lua = lua.replace('function fs.delete(p) files[p:gsub("^/","")] = nil end','function fs.delete(p) p=p:gsub("^/","") files[p]=nil for k in pairs(files) do if k:sub(1,#p+1)==p.."/" then files[k]=nil end end end')
lua = lua.replace('os.date = function() return "sim" end','local dn=0 os.date = function(f) if f and f:find("%%Y") then dn=dn+1 return "2026-09-27_19-0"..dn.."-00" end return "27/09/2026 19:00:00" end')
lua = lua.replace('FILES["log.lua"] = io.open("log.lua"):read("a")','FILES["log.lua"] = io.open("log.lua"):read("a")\ntextutils.pagedPrint = function(s) io.write(s, "\\n") end\nprint = function(...) io.write(table.concat({...}," "), "\\n") end')
# roda: voo (COAST ate ORBIT) , depois "reinicia" no meio de um novo estado COAST para testar retomada
lua = lua.replace('local lf = loadfile("voo.lua")\nlocal ok, e = pcall(lf, table.unpack(ARGS))', '''local lf = loadfile("voo.lua")
FILES["estado.txt"] = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0 }'
local ok, e = pcall(lf)
if not ok then io.write("ERRO1 ", tostring(e), "\\n") end
io.write("estado depois do voo: ", FILES["estado.txt"], "\\n")
-- simula reinicio no meio: mesma fase COAST, mesmo logFile
local st = textutils.unserialize(FILES["estado.txt"])
FILES["estado.txt"] = '{ phase = "COAST", stage = 1, failed = {}, t0 = 0, logFile = "'..st.logFile..'" }'
package.loaded = package.loaded
ok, e = pcall(loadfile("voo.lua"))
if not ok then io.write("ERRO2 ", tostring(e), "\\n") end
ok, e = pcall(loadfile("voo.lua"), "reset")
ok, e = pcall(loadfile("voo.lua"), "teste")
if not ok then io.write("ERRO3 ", tostring(e), "\\n") end
io.write("\\n== logs lista ==\\n")
ok, e = pcall(loadfile("logs.lua"), "lista") if not ok then io.write("ERRO4 ", tostring(e), "\\n") end
io.write("\\n== logs 2 erros ==\\n")
ok, e = pcall(loadfile("logs.lua"), "2", "erros") if not ok then io.write("ERRO5 ", tostring(e), "\\n") end
io.write("\\n== arquivos ==\\n")
local ks = {} for k in pairs(FILES) do ks[#ks+1]=k end table.sort(ks) for _,k in ipairs(ks) do io.write(k, "  ", #FILES[k], "\\n") end''')
L.execute(lua)
