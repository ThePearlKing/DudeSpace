extends SceneTree
## Scratch harness: run Lua snippets through LuaVM headless.
func _init() -> void:
	var cases := [
		["basics", "x = 1 + 2 * 3 print(x) print(10 % 3, 2^10, 7/2) print('a'..'b'..1)"],
		["locals", "local a = 5 do local a = 6 print(a) end print(a)"],
		["if", "for i=1,5 do if i%2==0 then print(i,'even') elseif i==5 then print(i,'five') else print(i,'odd') end end"],
		["while+break", "local i=0 while true do i=i+1 if i>3 then break end end print(i)"],
		["repeat", "local i=0 repeat i=i+1 local j=i*2 until j>=6 print(i)"],
		["functions", "function add(a,b) return a+b end print(add(2,3)) local f = function(x) return x*x end print(f(9))"],
		["closures", "function counter() local n=0 return function() n=n+1 return n end end local c=counter() c() c() print(c())"],
		["multiret", "function two() return 1,2 end local a,b = two() print(a,b) print(two()) print((two()))"],
		["varargs", "function sum(...) local t={...} local s=0 for i=1,#t do s=s+t[i] end return s, select('#',...) end print(sum(1,2,3,4))"],
		["tables", "local t={10,20,30,x=1} t[4]=40 print(#t, t[2], t.x) table.insert(t,2,15) print(table.concat(t,',')) table.remove(t,1) print(t[1], #t)"],
		["pairs", "local t={a=1,b=2} local n=0 for k,v in pairs(t) do n=n+v end print(n) local m=0 for i,v in ipairs({5,6,7}) do m=m+v end print(m)"],
		["oop", "\n".join([
			"Dude = {} Dude.__index = Dude",
			"function Dude.new(n) local s=setmetatable({},Dude) s.name=n s.hp=10 return s end",
			"function Dude:hit(d) self.hp = self.hp - d return self.hp end",
			"function Dude:__tostring() return 'dude '..self.name end",
			"local d = Dude.new('kev') d:hit(3) print(d.name, d:hit(2)) print(tostring(d))"])],
		["inherit", "\n".join([
			"Base={} Base.__index=Base function Base.new() return setmetatable({},Base) end",
			"function Base:who() return 'base' end",
			"Sub=setmetatable({},{__index=Base}) Sub.__index=Sub",
			"function Sub.new() return setmetatable({},Sub) end",
			"local s=Sub.new() print(s:who())"])],
		["metaarith", "local V={} V.__index=V V.__add=function(a,b) return setmetatable({x=a.x+b.x},V) end local a=setmetatable({x=1},V) local b=setmetatable({x=2},V) print((a+b).x)"],
		["strings", "print(('hello'):upper(), string.sub('arcade',2,4), #'abc') print(string.format('%d/%03d %.2f %s %x', 7, 5, 3.14159, 'ok', 255))"],
		["patterns", "print(string.match('score: 1200', '%d+')) print(string.gsub('a b c', ' ', '-')) for w in string.gmatch('one,two,three', '[^,]+') do print(w) end print(string.find('hello world','wor'))"],
		["sort", "local t={5,2,9,1} table.sort(t) print(table.concat(t,',')) table.sort(t, function(a,b) return a>b end) print(table.concat(t,','))"],
		["pcall", "local ok, e = pcall(function() error('boom') end) print(ok, e) print(pcall(function() return 42 end))"],
		["math", "print(math.floor(3.7), math.max(1,9,4), math.min(3,2), math.abs(-5)) print(math.floor(math.sqrt(16)))"],
		["recursion", "function fib(n) if n<2 then return n end return fib(n-1)+fib(n-2) end print(fib(18))"],
		["nested", "local grid={} for y=1,3 do grid[y]={} for x=1,3 do grid[y][x]=x*y end end local s=0 for y=1,3 do for x=1,3 do s=s+grid[y][x] end end print(s)"],
		["callbacks", "function _update() count = (count or 0) + 1 end"],
	]
	var fails := 0
	for c in cases:
		var vm := LuaVM.new()
		vm.open_libs()
		var ok := vm.run(str(c[1]))
		if not ok:
			fails += 1
		print("[%s] %-12s %s" % ["ok " if ok else "FAIL", str(c[0]),
			("  ERR: " + vm.err) if not ok else " | ".join(vm.out_lines)])
	# callbacks are how a cartridge actually runs
	var vm3 := LuaVM.new()
	vm3.open_libs()
	vm3.run("n=0 function _update() n=n+1 end")
	for i in 5:
		vm3.call_global("_update")
	print("[%s] callback loop  n=%s" % ["ok " if str(LuaVM.tostr(vm3.G.rawget("n"))) == "5" else "FAIL",
		LuaVM.tostr(vm3.G.rawget("n"))])
	# runaway protection
	var vm2 := LuaVM.new()
	vm2.open_libs()
	vm2.budget = 50000
	var ok2 := vm2.run("while true do end")
	print("[%s] runaway guard  %s" % ["ok " if not ok2 else "FAIL", vm2.err])
	# speed: how much Lua can a cartridge afford per frame?
	var vm4 := LuaVM.new()
	vm4.open_libs()
	vm4.run("function work(n) local s=0 for i=1,n do s=s+i*2 end return s end")
	var t0 := Time.get_ticks_usec()
	vm4.call_global("work", [100000.0])
	var us := Time.get_ticks_usec() - t0
	print("SPEED 100k loop iterations: %.1f ms  (~%d steps/frame at 60fps)" % [
		float(us) / 1000.0, int(100000.0 / (float(us) / 16666.0))])
	print("LUA fails: ", fails)
	quit()
