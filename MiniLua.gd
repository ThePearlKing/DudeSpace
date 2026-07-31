class_name MiniLua
extends RefCounted
## A tiny Lua-ish interpreter for the in-game computers. Supports:
##   x = expr            assignments
##   if expr then / elseif expr then / else / end
##   sort(expr, expr)    (and any function the host injects)
##   numbers, strings "coal", vars, + - * / % ..
##   == ~= < > <= >=, and or not, ( ), -- comments
## Host passes env vars in, gets them back out. Errors: {"err": "line N: ..."}

static func run(src: String, env: Dictionary, funcs: Dictionary = {}) -> Dictionary:
	var lines := src.split("\n")
	var err := ""
	# condition stack: each entry true/false; execute only when all true
	var stack: Array = []
	var taken: Array = []   # has any branch of this if-chain fired yet?
	for li in lines.size():
		var raw := lines[li]
		var c := raw.find("--")
		if c >= 0:
			raw = raw.substr(0, c)
		var line := raw.strip_edges()
		if line == "":
			continue
		var active := true
		for s in stack:
			if not s:
				active = false
		if line.begins_with("if ") and line.ends_with(" then"):
			var cond := false
			if active:
				var r := _eval(line.substr(3, line.length() - 8), env, funcs)
				if r.has("err"):
					return {"err": "line %d: %s" % [li + 1, r["err"]]}
				cond = _truthy(r["v"])
			stack.append(cond)
			taken.append(cond)
		elif line.begins_with("elseif ") and line.ends_with(" then"):
			if stack.is_empty():
				return {"err": "line %d: elseif without if" % (li + 1)}
			var parent_active := true
			for k in stack.size() - 1:
				if not stack[k]:
					parent_active = false
			var cond2 := false
			if parent_active and not taken[taken.size() - 1]:
				var r2 := _eval(line.substr(7, line.length() - 12), env, funcs)
				if r2.has("err"):
					return {"err": "line %d: %s" % [li + 1, r2["err"]]}
				cond2 = _truthy(r2["v"])
			stack[stack.size() - 1] = cond2
			if cond2:
				taken[taken.size() - 1] = true
		elif line == "else":
			if stack.is_empty():
				return {"err": "line %d: else without if" % (li + 1)}
			stack[stack.size() - 1] = not taken[taken.size() - 1]
			taken[taken.size() - 1] = true
		elif line == "end":
			if stack.is_empty():
				return {"err": "line %d: end without if" % (li + 1)}
			stack.pop_back()
			taken.pop_back()
		else:
			if not active:
				continue
			var eq := _find_assign(line)
			if eq >= 0:
				var name := line.substr(0, eq).strip_edges()
				if not _is_ident(name):
					return {"err": "line %d: bad variable '%s'" % [li + 1, name]}
				var r3 := _eval(line.substr(eq + 1), env, funcs)
				if r3.has("err"):
					return {"err": "line %d: %s" % [li + 1, r3["err"]]}
				env[name] = r3["v"]
			else:
				# expression statement (function calls like sort(...))
				var r4 := _eval(line, env, funcs)
				if r4.has("err"):
					return {"err": "line %d: %s" % [li + 1, r4["err"]]}
	if not stack.is_empty():
		return {"err": "missing 'end'"}
	return {"env": env}

static func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return float(v) != 0.0
	if v is String:
		return v != ""
	return v != null

## find top-level '=' that isn't ==, ~=, <=, >=
static func _find_assign(line: String) -> int:
	var depth := 0
	for i in line.length():
		var ch := line[i]
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif ch == "=" and depth == 0:
			var prev := line[i - 1] if i > 0 else " "
			var next := line[i + 1] if i < line.length() - 1 else " "
			if prev in ["=", "~", "<", ">"] or next == "=":
				continue
			return i
	return -1

static func _is_ident(s: String) -> bool:
	if s == "" or not (s[0] == "_" or (s[0] >= "a" and s[0] <= "z") or (s[0] >= "A" and s[0] <= "Z")):
		return false
	for ch in s:
		if not (ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true

# ------------------------------------------------------------ expressions

static func _eval(expr: String, env: Dictionary, funcs: Dictionary) -> Dictionary:
	var toks := _tokenize(expr)
	if toks.is_empty():
		return {"err": "empty expression"}
	var state := {"toks": toks, "i": 0, "env": env, "funcs": funcs, "err": ""}
	var v = _p_or(state)
	if state["err"] != "":
		return {"err": state["err"]}
	if int(state["i"]) < toks.size():
		return {"err": "unexpected '%s'" % str(toks[state["i"]]["v"])}
	return {"v": v}

static func _tokenize(s: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == " " or ch == "\t":
			i += 1
			continue
		if ch >= "0" and ch <= "9":
			var j := i
			while j < s.length() and ((s[j] >= "0" and s[j] <= "9") or s[j] == "."):
				j += 1
			out.append({"t": "num", "v": s.substr(i, j - i).to_float()})
			i = j
			continue
		if ch == "\"" or ch == "'":
			var j2 := i + 1
			while j2 < s.length() and s[j2] != ch:
				j2 += 1
			out.append({"t": "str", "v": s.substr(i + 1, j2 - i - 1)})
			i = j2 + 1
			continue
		if _is_ident(ch):
			var j3 := i
			while j3 < s.length() and _is_ident(s.substr(i, j3 - i + 1)):
				j3 += 1
			out.append({"t": "id", "v": s.substr(i, j3 - i)})
			i = j3
			continue
		var two := s.substr(i, 2)
		if two in ["==", "~=", "<=", ">=", ".."]:
			out.append({"t": "op", "v": two})
			i += 2
			continue
		if ch in ["+", "-", "*", "/", "%", "<", ">", "(", ")", ","]:
			out.append({"t": "op", "v": ch})
			i += 1
			continue
		out.append({"t": "op", "v": ch})
		i += 1
	return out

static func _peek(st: Dictionary):
	var toks: Array = st["toks"]
	var i: int = st["i"]
	return toks[i] if i < toks.size() else null

static func _next(st: Dictionary):
	var t = _peek(st)
	st["i"] = int(st["i"]) + 1
	return t

static func _p_or(st: Dictionary):
	var v = _p_and(st)
	while true:
		var t = _peek(st)
		if t != null and t["t"] == "id" and t["v"] == "or":
			_next(st)
			var r = _p_and(st)
			v = _truthy(v) or _truthy(r)
		else:
			break
	return v

static func _p_and(st: Dictionary):
	var v = _p_cmp(st)
	while true:
		var t = _peek(st)
		if t != null and t["t"] == "id" and t["v"] == "and":
			_next(st)
			var r = _p_cmp(st)
			v = _truthy(v) and _truthy(r)
		else:
			break
	return v

static func _p_cmp(st: Dictionary):
	var v = _p_add(st)
	var t = _peek(st)
	if t != null and t["t"] == "op" and t["v"] in ["==", "~=", "<", ">", "<=", ">="]:
		_next(st)
		var r = _p_add(st)
		match t["v"]:
			"==": return _eq(v, r)
			"~=": return not _eq(v, r)
			"<": return _numv(v) < _numv(r)
			">": return _numv(v) > _numv(r)
			"<=": return _numv(v) <= _numv(r)
			">=": return _numv(v) >= _numv(r)
	return v

static func _eq(a, b) -> bool:
	if a is String or b is String:
		return str(a) == str(b)
	return _numv(a) == _numv(b)

static func _numv(v) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	if v is float or v is int:
		return float(v)
	return 0.0

static func _p_add(st: Dictionary):
	var v = _p_mul(st)
	while true:
		var t = _peek(st)
		if t != null and t["t"] == "op" and t["v"] in ["+", "-", ".."]:
			_next(st)
			var r = _p_mul(st)
			if t["v"] == "..":
				v = str(v) + str(r)
			elif t["v"] == "+":
				v = _numv(v) + _numv(r)
			else:
				v = _numv(v) - _numv(r)
		else:
			break
	return v

static func _p_mul(st: Dictionary):
	var v = _p_unary(st)
	while true:
		var t = _peek(st)
		if t != null and t["t"] == "op" and t["v"] in ["*", "/", "%"]:
			_next(st)
			var r = _p_unary(st)
			if t["v"] == "*":
				v = _numv(v) * _numv(r)
			elif t["v"] == "/":
				v = _numv(v) / maxf(0.000001, _numv(r))
			else:
				v = fmod(_numv(v), maxf(0.000001, _numv(r)))
		else:
			break
	return v

static func _p_unary(st: Dictionary):
	var t = _peek(st)
	if t != null and t["t"] == "id" and t["v"] == "not":
		_next(st)
		return not _truthy(_p_unary(st))
	if t != null and t["t"] == "op" and t["v"] == "-":
		_next(st)
		return -_numv(_p_unary(st))
	return _p_atom(st)

static func _p_atom(st: Dictionary):
	var t = _next(st)
	if t == null:
		st["err"] = "unexpected end of expression"
		return null
	if t["t"] == "num" or t["t"] == "str":
		return t["v"]
	if t["t"] == "op" and t["v"] == "(":
		var v = _p_or(st)
		var t2 = _next(st)
		if t2 == null or t2["v"] != ")":
			st["err"] = "missing ')'"
		return v
	if t["t"] == "id":
		match t["v"]:
			"true": return true
			"false": return false
			"nil": return null
		# function call?
		var t3 = _peek(st)
		if t3 != null and t3["t"] == "op" and t3["v"] == "(":
			_next(st)
			var args: Array = []
			if _peek(st) != null and _peek(st)["v"] != ")":
				args.append(_p_or(st))
				while _peek(st) != null and _peek(st)["v"] == ",":
					_next(st)
					args.append(_p_or(st))
			var t4 = _next(st)
			if t4 == null or t4["v"] != ")":
				st["err"] = "missing ')' in call"
				return null
			var funcs: Dictionary = st["funcs"]
			if funcs.has(t["v"]):
				return funcs[t["v"]].call(args)
			st["err"] = "unknown function '%s'" % t["v"]
			return null
		var env: Dictionary = st["env"]
		return env.get(t["v"], null)
	st["err"] = "unexpected '%s'" % str(t["v"])
	return null
