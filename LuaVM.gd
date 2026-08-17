class_name LuaVM
extends RefCounted
## A REAL Lua interpreter, in GDScript, for the arcade cabinets.
##
## MiniLua (the one the computers use) is a line-at-a-time toy: no
## functions, no loops, no tables. This is the other thing entirely --
## lexer, recursive-descent parser to an array-tagged AST, and a
## tree-walking interpreter with closures, tables, metatables, varargs,
## multiple returns, pcall and a working chunk of the standard library.
## Games on a DUDE-16 cartridge are written against it, so anything Lua
## can express, a cartridge can express.
##
## What it does NOT have: coroutines (a tree-walker cannot yield without
## a thread per coroutine) and goto. Everything else in 5.1 that a game
## actually reaches for is here.
##
## Errors never crash the host: every failure comes back as a string in
## `err`, and a step budget stops a runaway `while true do end` from
## taking the whole game down with it.

# ---------------------------------------------------------------- tokens
const T_EOF := 0
const T_NAME := 1
const T_NUM := 2
const T_STR := 3
const T_KW := 4
const T_OP := 5

const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "false",
	"for", "function", "if", "in", "local", "nil", "not", "or", "repeat",
	"return", "then", "true", "until", "while"]

# --------------------------------------------------------------- AST tags
const E_NIL := 0
const E_TRUE := 1
const E_FALSE := 2
const E_NUM := 3
const E_STR := 4
const E_VARARG := 5
const E_NAME := 6
const E_INDEX := 7
const E_CALL := 8
const E_METH := 9
const E_FUNC := 10
const E_TABLE := 11
const E_BIN := 12
const E_UN := 13
const E_AND := 14
const E_OR := 15
const E_PAREN := 16

const S_LOCAL := 20
const S_ASSIGN := 21
const S_CALL := 22
const S_IF := 23
const S_WHILE := 24
const S_REPEAT := 25
const S_NUMFOR := 26
const S_GENFOR := 27
const S_RET := 28
const S_BREAK := 29
const S_DO := 30
const S_LOCALFUNC := 31

# binary operators
const O_ADD := 0
const O_SUB := 1
const O_MUL := 2
const O_DIV := 3
const O_MOD := 4
const O_POW := 5
const O_CAT := 6
const O_EQ := 7
const O_NE := 8
const O_LT := 9
const O_LE := 10
const O_GT := 11
const O_GE := 12
# unary
const U_NEG := 0
const U_NOT := 1
const U_LEN := 2

# ============================================================ lua values

## A Lua table: one dictionary for everything, with number keys
## normalised to float so t[1] and t[1.0] are the same slot, plus the
## metatable and a cached array border for `#`.
class Table extends RefCounted:
	var h: Dictionary = {}
	var meta: Table = null
	var _n: int = -1            # cached border, -1 = unknown

	func rawget(k):
		if k is int:
			k = float(k)
		return h.get(k, null)

	func rawset(k, v) -> void:
		if k is int:
			k = float(k)
		if v == null:
			h.erase(k)
		else:
			h[k] = v
		_n = -1

	## The `#` border. Lua only promises "a border"; this walks up from
	## the cached one so appending in a loop stays cheap.
	func length() -> int:
		if _n >= 0 and h.has(float(_n)) and not h.has(float(_n + 1)):
			return _n
		var n := 0
		while h.has(float(n + 1)):
			n += 1
		_n = n
		return n

	func insert(v) -> void:
		rawset(float(length() + 1), v)

	## Array part as a plain Array (used by host code reading carts).
	func to_array() -> Array:
		var out: Array = []
		for i in length():
			out.append(h.get(float(i + 1), null))
		return out

	func keys() -> Array:
		return h.keys()


## A Lua function: parameter names, its body, and the scope it closed
## over. `self_name` is only for error messages.
class Func extends RefCounted:
	var params: Array = []
	var vararg: bool = false
	var body: Array = []
	var scope = null
	var name: String = "?"


## One lexical scope. Locals live here; a miss walks up the chain.
class Scope extends RefCounted:
	var v: Dictionary = {}
	var parent: Scope = null
	## Set the moment a closure captures this scope (or any child of it).
	## A captured scope can never be recycled by the loop that made it --
	## the closure is still holding it.
	var captured: bool = false

	func _init(p: Scope = null) -> void:
		parent = p

	func get_var(n: String):
		var s: Scope = self
		while s != null:
			if s.v.has(n):
				return s.v[n]
			s = s.parent
		return null

	func has_var(n: String) -> bool:
		var s: Scope = self
		while s != null:
			if s.v.has(n):
				return true
			s = s.parent
		return false

	func set_existing(n: String, val) -> bool:
		var s: Scope = self
		while s != null:
			if s.v.has(n):
				s.v[n] = val
				return true
			s = s.parent
		return false

	## Same walk, but for reads, with one probe per level.
	func lookup(n: String, miss):
		var s: Scope = self
		while s != null:
			var hit = s.v.get(n, miss)
			if not is_same(hit, miss):
				return hit
			s = s.parent
		return miss

	func declare(n: String, val) -> void:
		v[n] = val

# ================================================================= lexer

var _src: String = ""
var _pos: int = 0
var _line: int = 1
var _toks: Array = []
var err: String = ""

func _lex(src: String) -> bool:
	_src = src
	_pos = 0
	_line = 1
	_toks = []
	var n := src.length()
	while _pos < n:
		var c := src[_pos]
		if c == "\n":
			_line += 1
			_pos += 1
			continue
		if c == " " or c == "\t" or c == "\r":
			_pos += 1
			continue
		# comments
		if c == "-" and _pos + 1 < n and src[_pos + 1] == "-":
			_pos += 2
			if _pos + 1 < n and src[_pos] == "[" and src[_pos + 1] == "[":
				_pos += 2
				while _pos + 1 < n and not (src[_pos] == "]" and src[_pos + 1] == "]"):
					if src[_pos] == "\n":
						_line += 1
					_pos += 1
				_pos += 2
			else:
				while _pos < n and src[_pos] != "\n":
					_pos += 1
			continue
		# long string [[ ... ]]
		if c == "[" and _pos + 1 < n and src[_pos + 1] == "[":
			var start_line := _line
			_pos += 2
			var buf := ""
			while _pos + 1 < n and not (src[_pos] == "]" and src[_pos + 1] == "]"):
				if src[_pos] == "\n":
					_line += 1
				buf += src[_pos]
				_pos += 1
			_pos += 2
			_toks.append([T_STR, buf, start_line])
			continue
		# names and keywords
		if c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			var s := _pos
			while _pos < n:
				var d := src[_pos]
				if d == "_" or (d >= "a" and d <= "z") or (d >= "A" and d <= "Z") \
						or (d >= "0" and d <= "9"):
					_pos += 1
				else:
					break
			var word := src.substr(s, _pos - s)
			_toks.append([T_KW if KEYWORDS.has(word) else T_NAME, word, _line])
			continue
		# numbers (decimal, hex, float, exponent)
		if (c >= "0" and c <= "9") or (c == "." and _pos + 1 < n \
				and src[_pos + 1] >= "0" and src[_pos + 1] <= "9"):
			var s2 := _pos
			if c == "0" and _pos + 1 < n and (src[_pos + 1] == "x" or src[_pos + 1] == "X"):
				_pos += 2
				while _pos < n and _is_hex(src[_pos]):
					_pos += 1
				_toks.append([T_NUM, float(src.substr(s2, _pos - s2).hex_to_int()), _line])
				continue
			while _pos < n:
				var d2 := src[_pos]
				if (d2 >= "0" and d2 <= "9") or d2 == ".":
					_pos += 1
				elif d2 == "e" or d2 == "E":
					_pos += 1
					if _pos < n and (src[_pos] == "-" or src[_pos] == "+"):
						_pos += 1
				else:
					break
			_toks.append([T_NUM, float(src.substr(s2, _pos - s2)), _line])
			continue
		# strings
		if c == "\"" or c == "'":
			var q := c
			_pos += 1
			var buf2 := ""
			while _pos < n and src[_pos] != q:
				var d3 := src[_pos]
				if d3 == "\\" and _pos + 1 < n:
					_pos += 1
					var e := src[_pos]
					match e:
						"n": buf2 += "\n"
						"t": buf2 += "\t"
						"r": buf2 += "\r"
						"\\": buf2 += "\\"
						"\"": buf2 += "\""
						"'": buf2 += "'"
						"0": buf2 += char(0)
						_: buf2 += e
					_pos += 1
					continue
				if d3 == "\n":
					_line += 1
				buf2 += d3
				_pos += 1
			_pos += 1
			_toks.append([T_STR, buf2, _line])
			continue
		# operators, longest first
		var three := src.substr(_pos, 3)
		if three == "...":
			_toks.append([T_OP, "...", _line])
			_pos += 3
			continue
		var two := src.substr(_pos, 2)
		if two in ["==", "~=", "<=", ">=", "..", "::"]:
			_toks.append([T_OP, two, _line])
			_pos += 2
			continue
		if c in ["+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")",
				"{", "}", "[", "]", ";", ":", ",", "."]:
			_toks.append([T_OP, c, _line])
			_pos += 1
			continue
		err = "line %d: what is '%s' doing here?" % [_line, c]
		return false
	_toks.append([T_EOF, "", _line])
	return true

static func _is_hex(c: String) -> bool:
	return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")

# ================================================================ parser

var _ti: int = 0

func _peek() -> Array:
	return _toks[_ti]

func _next() -> Array:
	var t: Array = _toks[_ti]
	_ti += 1
	return t

func _check(type: int, val: String) -> bool:
	var t: Array = _toks[_ti]
	return int(t[0]) == type and str(t[1]) == val

func _accept(type: int, val: String) -> bool:
	if _check(type, val):
		_ti += 1
		return true
	return false

func _expect(type: int, val: String) -> bool:
	if _accept(type, val):
		return true
	if err == "":
		err = "line %d: expected '%s', found '%s'" % [int(_toks[_ti][2]), val,
			str(_toks[_ti][1]) if str(_toks[_ti][1]) != "" else "end of file"]
	return false

## chunk := statement* EOF
func parse(src: String) -> Array:
	err = ""
	if not _lex(src):
		return []
	_ti = 0
	var block := _parse_block()
	if err != "":
		return []
	if int(_peek()[0]) != T_EOF:
		err = "line %d: unexpected '%s'" % [int(_peek()[2]), str(_peek()[1])]
		return []
	return block

func _block_ends() -> bool:
	var t: Array = _peek()
	if int(t[0]) == T_EOF:
		return true
	if int(t[0]) == T_KW and str(t[1]) in ["end", "else", "elseif", "until"]:
		return true
	return false

func _parse_block() -> Array:
	var out: Array = []
	while not _block_ends() and err == "":
		var st = _parse_statement()
		if st != null:
			out.append(st)
	return out

func _parse_statement():
	while _accept(T_OP, ";"):
		pass
	if _block_ends():
		return null
	var t: Array = _peek()
	var line := int(t[2])
	if int(t[0]) == T_KW:
		match str(t[1]):
			"local":
				_next()
				if _accept(T_KW, "function"):
					var fname := str(_next()[1])
					var fn = _parse_funcbody(fname)
					return [S_LOCALFUNC, fname, fn]
				var names: Array = [str(_next()[1])]
				while _accept(T_OP, ","):
					names.append(str(_next()[1]))
				var exprs: Array = []
				if _accept(T_OP, "="):
					exprs = _parse_exprlist()
				return [S_LOCAL, names, exprs]
			"if":
				_next()
				var conds: Array = []
				var blocks: Array = []
				var c = _parse_expr()
				if not _expect(T_KW, "then"):
					return null
				conds.append(c)
				blocks.append(_parse_block())
				var els = null
				while true:
					if _accept(T_KW, "elseif"):
						var c2 = _parse_expr()
						if not _expect(T_KW, "then"):
							return null
						conds.append(c2)
						blocks.append(_parse_block())
						continue
					if _accept(T_KW, "else"):
						els = _parse_block()
					break
				_expect(T_KW, "end")
				return [S_IF, conds, blocks, els]
			"while":
				_next()
				var wc = _parse_expr()
				if not _expect(T_KW, "do"):
					return null
				var wb := _parse_block()
				_expect(T_KW, "end")
				return [S_WHILE, wc, wb]
			"repeat":
				_next()
				var rb := _parse_block()
				if not _expect(T_KW, "until"):
					return null
				var rc = _parse_expr()
				return [S_REPEAT, rb, rc]
			"for":
				_next()
				var n1 := str(_next()[1])
				if _accept(T_OP, "="):
					var e1 = _parse_expr()
					_expect(T_OP, ",")
					var e2 = _parse_expr()
					var e3 = null
					if _accept(T_OP, ","):
						e3 = _parse_expr()
					if not _expect(T_KW, "do"):
						return null
					var fb := _parse_block()
					_expect(T_KW, "end")
					return [S_NUMFOR, n1, e1, e2, e3, fb]
				var fnames: Array = [n1]
				while _accept(T_OP, ","):
					fnames.append(str(_next()[1]))
				if not _expect(T_KW, "in"):
					return null
				var fexprs := _parse_exprlist()
				if not _expect(T_KW, "do"):
					return null
				var gb := _parse_block()
				_expect(T_KW, "end")
				return [S_GENFOR, fnames, fexprs, gb]
			"function":
				_next()
				# function a.b.c:d() -- target is an lvalue chain
				var target = [E_NAME, str(_next()[1])]
				var mname := ""
				while true:
					if _accept(T_OP, "."):
						target = [E_INDEX, target, [E_STR, str(_next()[1])]]
						continue
					if _accept(T_OP, ":"):
						mname = str(_next()[1])
						target = [E_INDEX, target, [E_STR, mname]]
					break
				var fn2 = _parse_funcbody(mname, mname != "")
				return [S_ASSIGN, [target], [fn2], line]
			"return":
				_next()
				var rex: Array = []
				if not _block_ends() and not _check(T_OP, ";"):
					rex = _parse_exprlist()
				_accept(T_OP, ";")
				return [S_RET, rex, line]
			"break":
				_next()
				return [S_BREAK]
			"do":
				_next()
				var db := _parse_block()
				_expect(T_KW, "end")
				return [S_DO, db]
	# expression statement: call, or assignment
	var e = _parse_suffixed()
	if e == null:
		return null
	if _check(T_OP, "=") or _check(T_OP, ","):
		var targets: Array = [e]
		while _accept(T_OP, ","):
			targets.append(_parse_suffixed())
		if not _expect(T_OP, "="):
			return null
		var vals := _parse_exprlist()
		return [S_ASSIGN, targets, vals, line]
	if int(e[0]) != E_CALL and int(e[0]) != E_METH:
		err = "line %d: this line does nothing" % line
		return null
	return [S_CALL, e]

func _parse_funcbody(name: String, is_method: bool = false):
	if not _expect(T_OP, "("):
		return null
	var params: Array = []
	if is_method:
		params.append("self")
	var vararg := false
	if not _check(T_OP, ")"):
		while true:
			if _accept(T_OP, "..."):
				vararg = true
				break
			params.append(str(_next()[1]))
			if not _accept(T_OP, ","):
				break
	if not _expect(T_OP, ")"):
		return null
	var body := _parse_block()
	_expect(T_KW, "end")
	return [E_FUNC, params, vararg, body, name]

func _parse_exprlist() -> Array:
	var out: Array = [_parse_expr()]
	while _accept(T_OP, ","):
		out.append(_parse_expr())
	return out

const _BIN_PREC := {
	"or": 1, "and": 2,
	"<": 3, ">": 3, "<=": 3, ">=": 3, "~=": 3, "==": 3,
	"..": 4,
	"+": 5, "-": 5,
	"*": 6, "/": 6, "%": 6,
	"^": 8,
}
const _BIN_OP := {
	"+": O_ADD, "-": O_SUB, "*": O_MUL, "/": O_DIV, "%": O_MOD, "^": O_POW,
	"..": O_CAT, "==": O_EQ, "~=": O_NE, "<": O_LT, "<=": O_LE, ">": O_GT,
	">=": O_GE,
}

func _parse_expr(limit: int = 0):
	var left
	var t: Array = _peek()
	if (int(t[0]) == T_OP and (str(t[1]) == "-" or str(t[1]) == "#")) \
			or (int(t[0]) == T_KW and str(t[1]) == "not"):
		var ops := str(_next()[1])
		var operand = _parse_expr(7)          # unary binds tighter than binary
		var uop := U_NEG
		if ops == "#":
			uop = U_LEN
		elif ops == "not":
			uop = U_NOT
		left = [E_UN, uop, operand, int(t[2])]
	else:
		left = _parse_simple()
	if left == null:
		return null
	while err == "":
		var tk: Array = _peek()
		var name := str(tk[1])
		if not ((int(tk[0]) == T_OP or int(tk[0]) == T_KW) and _BIN_PREC.has(name)):
			break
		var prec := int(_BIN_PREC[name])
		if prec <= limit:
			break
		var line := int(tk[2])
		_next()
		# right-associative: ^ and ..
		var rhs = _parse_expr(prec - 1 if (name == "^" or name == "..") else prec)
		if name == "and":
			left = [E_AND, left, rhs]
		elif name == "or":
			left = [E_OR, left, rhs]
		else:
			left = [E_BIN, int(_BIN_OP[name]), left, rhs, line]
	return left

func _parse_simple():
	var t: Array = _peek()
	if int(t[0]) == T_NUM:
		_next()
		return [E_NUM, float(t[1])]
	if int(t[0]) == T_STR:
		_next()
		return [E_STR, str(t[1])]
	if int(t[0]) == T_KW:
		match str(t[1]):
			"nil":
				_next()
				return [E_NIL]
			"true":
				_next()
				return [E_TRUE]
			"false":
				_next()
				return [E_FALSE]
			"function":
				_next()
				return _parse_funcbody("anonymous")
	if int(t[0]) == T_OP:
		if str(t[1]) == "...":
			_next()
			return [E_VARARG]
		if str(t[1]) == "{":
			return _parse_table()
	return _parse_suffixed()

func _parse_table():
	_expect(T_OP, "{")
	var arr: Array = []
	var hash: Array = []
	while not _check(T_OP, "}") and err == "":
		if _check(T_OP, "["):
			_next()
			var k = _parse_expr()
			_expect(T_OP, "]")
			_expect(T_OP, "=")
			hash.append([k, _parse_expr()])
		elif int(_peek()[0]) == T_NAME and int(_toks[_ti + 1][0]) == T_OP \
				and str(_toks[_ti + 1][1]) == "=":
			var key := str(_next()[1])
			_next()
			hash.append([[E_STR, key], _parse_expr()])
		else:
			arr.append(_parse_expr())
		if not (_accept(T_OP, ",") or _accept(T_OP, ";")):
			break
	_expect(T_OP, "}")
	return [E_TABLE, arr, hash]

## primary with any run of .name [expr] (args) :name(args) after it
func _parse_suffixed():
	var t: Array = _peek()
	var e
	if int(t[0]) == T_NAME:
		_next()
		e = [E_NAME, str(t[1])]
	elif int(t[0]) == T_OP and str(t[1]) == "(":
		_next()
		e = _parse_expr()
		if not _expect(T_OP, ")"):
			return null
		# (f()) truncates to one value -- the paren wrapper is what stops
		# multiple returns from expanding any further
		if e != null and (int(e[0]) == E_CALL or int(e[0]) == E_METH \
				or int(e[0]) == E_VARARG):
			e = [E_PAREN, e]
	else:
		if err == "":
			err = "line %d: expected a value, found '%s'" % [int(t[2]),
				str(t[1]) if str(t[1]) != "" else "end of file"]
		return null
	while err == "":
		var tk: Array = _peek()
		if int(tk[0]) != T_OP:
			if int(tk[0]) == T_STR:
				# f"string" sugar
				_next()
				e = [E_CALL, e, [[E_STR, str(tk[1])]], int(tk[2])]
				continue
			break
		match str(tk[1]):
			".":
				_next()
				e = [E_INDEX, e, [E_STR, str(_next()[1])]]
			"[":
				_next()
				var k = _parse_expr()
				_expect(T_OP, "]")
				e = [E_INDEX, e, k]
			"(":
				_next()
				var args: Array = []
				if not _check(T_OP, ")"):
					args = _parse_exprlist()
				_expect(T_OP, ")")
				e = [E_CALL, e, args, int(tk[2])]
			":":
				_next()
				var mname := str(_next()[1])
				var margs: Array = []
				if _accept(T_OP, "("):
					if not _check(T_OP, ")"):
						margs = _parse_exprlist()
					_expect(T_OP, ")")
				elif int(_peek()[0]) == T_STR:
					margs = [[E_STR, str(_next()[1])]]
				elif _check(T_OP, "{"):
					margs = [_parse_table()]
				e = [E_METH, e, mname, margs, int(tk[2])]
			"{":
				e = [E_CALL, e, [_parse_table()], int(tk[2])]
			_:
				return e
	return e

# =========================================================== interpreter

var G := Table.new()               # globals
## Dictionary.get() needs a "definitely not a value" default. A stored
## object works: nothing a Lua program can produce is ever equal to it.
static var MISS := RefCounted.new()
var steps: int = 0                 # instruction counter
var budget: int = 4000000          # per-run ceiling; a runaway loop dies here
var line: int = 0                  # line currently executing, for errors
var _chunk: Array = []
var _depth: int = 0

const MAX_DEPTH := 190

func _rt(msg: String) -> void:
	if err == "":
		err = "line %d: %s" % [line, msg]

## Load a chunk. Returns false and fills `err` on a syntax error.
func load_src(src: String) -> bool:
	_chunk = parse(src)
	return err == ""

## Load and run a chunk top to bottom.
func run(src: String) -> bool:
	if not load_src(src):
		return false
	return exec_chunk()

## Run the loaded chunk (used after load_src so the host can inject
## globals in between).
func exec_chunk() -> bool:
	steps = 0
	err = ""
	var sc := Scope.new(null)
	_exec_block(_chunk, sc)
	return err == ""

## Call a Lua function value with GDScript arguments; returns its
## results as an Array (empty when it returned nothing).
func call_value(fn, args: Array = []) -> Array:
	if fn == null:
		return []
	steps = 0
	return _call(fn, args)

## Is this global a callable Lua function? (Cartridges are polled for
## _init/_update/_draw, and only some of them define each.)
func has_fn(name: String) -> bool:
	var v = G.rawget(name)
	return v is Func or v is Callable

func call_global(name: String, args: Array = []) -> Array:
	var v = G.rawget(name)
	if v == null:
		return []
	return call_value(v, args)

# ---------------------------------------------------------- statements

## Returns null (fell off the end), ["b"] (break) or ["r", values].
func _exec_block(block: Array, sc: Scope) -> Variant:
	for st in block:
		steps += 1
		if steps > budget:
			_rt("this script would not stop (over %d steps in one go)" % budget)
			return null
		if err != "":
			return null
		var tag := int(st[0])
		# assignment and bare calls are most of every program; skipping
		# the dispatch call for them is worth the duplication
		if tag == S_ASSIGN:
			var tg: Array = st[1]
			var ex: Array = st[2]
			if tg.size() == 1 and ex.size() == 1:
				var e0: Array = ex[0]
				var t0: int = e0[0]
				if t0 != E_CALL and t0 != E_METH and t0 != E_VARARG:
					line = int(st[3])
					_assign(tg[0], _eval(e0, sc), sc)
					continue
		elif tag == S_CALL:
			_eval_multi(st[1], sc)
			continue
		var r = _exec(st, sc)
		if r != null:
			return r
	return null

func _exec(st: Array, sc: Scope) -> Variant:
	match int(st[0]):
		S_LOCAL:
			var names: Array = st[1]
			var exprs: Array = st[2]
			if names.size() == 1 and exprs.size() == 1 \
					and int(exprs[0][0]) != E_CALL and int(exprs[0][0]) != E_METH \
					and int(exprs[0][0]) != E_VARARG:
				sc.v[str(names[0])] = _eval(exprs[0], sc)
				return null
			var vals := _eval_list(exprs, sc, names.size())
			for i in names.size():
				sc.v[str(names[i])] = vals[i] if i < vals.size() else null
		S_ASSIGN:
			line = int(st[3])
			var targets: Array = st[1]
			var exprs2: Array = st[2]
			if targets.size() == 1 and exprs2.size() == 1 \
					and int(exprs2[0][0]) != E_CALL and int(exprs2[0][0]) != E_METH \
					and int(exprs2[0][0]) != E_VARARG:
				_assign(targets[0], _eval(exprs2[0], sc), sc)
				return null
			var vals2 := _eval_list(exprs2, sc, targets.size())
			for i in targets.size():
				_assign(targets[i], vals2[i] if i < vals2.size() else null, sc)
		S_CALL:
			_eval_multi(st[1], sc)
		S_IF:
			var conds: Array = st[1]
			var blocks: Array = st[2]
			for i in conds.size():
				if _truthy(_eval(conds[i], sc)):
					return _exec_block(blocks[i], Scope.new(sc))
				if err != "":
					return null
			if st[3] != null:
				return _exec_block(st[3], Scope.new(sc))
		S_WHILE:
			var wbody: Array = st[2]
			var winner := Scope.new(sc)
			while _truthy(_eval(st[1], sc)):
				if err != "":
					return null
				steps += 1
				if steps > budget:
					_rt("this loop would not stop (over %d steps)" % budget)
					return null
				if winner.captured:
					winner = Scope.new(sc)
				else:
					winner.v.clear()
				var r = _exec_block(wbody, winner)
				if r != null:
					if str(r[0]) == "b":
						break
					return r
		S_REPEAT:
			while true:
				var inner := Scope.new(sc)
				var r2 = _exec_block(st[1], inner)
				if r2 != null:
					if str(r2[0]) == "b":
						break
					return r2
				if err != "":
					return null
				steps += 1
				if steps > budget:
					_rt("this loop would not stop (over %d steps)" % budget)
					return null
				# the until-condition can see the body's locals
				if _truthy(_eval(st[2], inner)):
					break
		S_NUMFOR:
			var a = _tonum(_eval(st[2], sc))
			var b = _tonum(_eval(st[3], sc))
			var step := 1.0
			if st[4] != null:
				step = _tonum(_eval(st[4], sc))
			if a == null or b == null or step == null:
				_rt("'for' wants numbers")
				return null
			var i2 := float(a)
			var bf := float(b)
			var sf := float(step)
			if sf == 0.0:
				_rt("'for' step is zero")
				return null
			var vname := str(st[1])
			var inner2 := Scope.new(sc)
			var fbody: Array = st[5]
			while (sf > 0.0 and i2 <= bf) or (sf < 0.0 and i2 >= bf):
				steps += 1
				if steps > budget:
					_rt("this loop would not stop (over %d steps)" % budget)
					return null
				if inner2.captured:
					inner2 = Scope.new(sc)      # a closure kept the old one
				else:
					inner2.v.clear()
				inner2.v[vname] = i2
				var r3 = _exec_block(fbody, inner2)
				if r3 != null:
					if str(r3[0]) == "b":
						break
					return r3
				if err != "":
					return null
				i2 += sf
		S_GENFOR:
			var ctrl := _eval_list(st[2], sc, 3)
			var f = ctrl[0] if ctrl.size() > 0 else null
			var state = ctrl[1] if ctrl.size() > 1 else null
			var key = ctrl[2] if ctrl.size() > 2 else null
			var names2: Array = st[1]
			var inner3 := Scope.new(sc)
			while true:
				steps += 1
				if steps > budget:
					_rt("this loop would not stop (over %d steps)" % budget)
					return null
				var res := _call(f, [state, key])
				if err != "":
					return null
				if res.is_empty() or res[0] == null:
					break
				key = res[0]
				if inner3.captured:
					inner3 = Scope.new(sc)
				else:
					inner3.v.clear()
				for i3 in names2.size():
					inner3.v[str(names2[i3])] = res[i3] if i3 < res.size() else null
				var r4 = _exec_block(st[3], inner3)
				if r4 != null:
					if str(r4[0]) == "b":
						break
					return r4
		S_RET:
			line = int(st[2])
			return ["r", _eval_list(st[1], sc, -1)]
		S_BREAK:
			return ["b"]
		S_DO:
			return _exec_block(st[1], Scope.new(sc))
		S_LOCALFUNC:
			# declared before the body is made, so it can recurse
			sc.declare(str(st[1]), null)
			var fn := _make_func(st[2], sc)
			sc.v[str(st[1])] = fn
	return null

func _assign(target: Array, val, sc: Scope) -> void:
	match int(target[0]):
		E_NAME:
			var n: String = target[1]
			var s: Scope = sc
			while s != null:
				if s.v.has(n):
					s.v[n] = val
					return
				s = s.parent
			G.rawset(n, val)
		E_INDEX:
			var obj = _eval(target[1], sc)
			var key = _eval(target[2], sc)
			_setindex(obj, key, val)
		_:
			_rt("cannot assign to that")

func _setindex(obj, key, val) -> void:
	if obj is Table:
		var t: Table = obj
		if t.meta != null and t.rawget(key) == null:
			var ni = t.meta.rawget("__newindex")
			if ni is Table:
				_setindex(ni, key, val)
				return
			if ni != null:
				_call(ni, [t, key, val])
				return
		if key == null:
			_rt("table index is nil")
			return
		t.rawset(key, val)
		return
	_rt("cannot index a %s" % type_name(obj))

# --------------------------------------------------------- expressions

func _eval(node, sc: Scope) -> Variant:
	if node == null:
		return null
	match int(node[0]):
		E_NAME:
			var n: String = node[1]
			var s: Scope = sc
			while s != null:
				var hit = s.v.get(n, MISS)
				if not is_same(hit, MISS):
					return hit
				s = s.parent
			return G.h.get(n, null)
		E_NUM: return node[1]
		E_STR: return node[1]
		E_NIL: return null
		E_TRUE: return true
		E_FALSE: return false
		E_INDEX:
			var obj = _eval(node[1], sc)
			var key = _eval(node[2], sc)
			if obj is Table:
				# plain table read, no metatable: straight out of the dict
				var tb: Table = obj
				if tb.meta == null:
					return tb.h.get(float(key) if key is int else key, null)
			return _index(obj, key)
		E_PAREN:
			var vs := _eval_multi(node[1], sc)
			return vs[0] if vs.size() > 0 else null
		E_CALL, E_METH:
			var vs2 := _eval_multi(node, sc)
			return vs2[0] if vs2.size() > 0 else null
		E_VARARG:
			var va = sc.get_var("...")
			if va is Array and (va as Array).size() > 0:
				return va[0]
			return null
		E_FUNC:
			return _make_func(node, sc)
		E_TABLE:
			var t := Table.new()
			var arr: Array = node[1]
			for i in arr.size():
				if i == arr.size() - 1:
					# the last array item spreads if it is a call or ...
					var tail := _eval_multi(arr[i], sc)
					for j in tail.size():
						t.rawset(float(i + 1 + j), tail[j])
				else:
					t.rawset(float(i + 1), _eval(arr[i], sc))
			for pair in (node[2] as Array):
				t.rawset(_eval(pair[0], sc), _eval(pair[1], sc))
			return t
		E_AND:
			var a = _eval(node[1], sc)
			if not _truthy(a):
				return a
			return _eval(node[2], sc)
		E_OR:
			var a2 = _eval(node[1], sc)
			if _truthy(a2):
				return a2
			return _eval(node[2], sc)
		E_UN:
			line = int(node[3])
			var v = _eval(node[2], sc)
			match int(node[1]):
				U_NOT: return not _truthy(v)
				U_NEG:
					var n2 = _tonum(v)
					if n2 == null:
						_rt("cannot negate a %s" % type_name(v))
						return null
					return -float(n2)
				U_LEN:
					if v is String:
						return float((v as String).length())
					if v is Table:
						var tv: Table = v
						if tv.meta != null:
							var ml = tv.meta.rawget("__len")
							if ml != null:
								var rr := _call(ml, [tv])
								return rr[0] if rr.size() > 0 else null
						return float(tv.length())
					_rt("cannot take the length of a %s" % type_name(v))
					return null
		E_BIN:
			# resolve number and name operands without recursing -- these
			# two cover nearly every operand in a real program
			var an: Array = node[2]
			var bn: Array = node[3]
			var av
			var bv
			var at: int = an[0]
			if at == E_NUM:
				av = an[1]
			elif at == E_NAME:
				var n1: String = an[1]
				var s1: Scope = sc
				av = null
				while s1 != null:
					if s1.v.has(n1):
						av = s1.v[n1]
						break
					s1 = s1.parent
				if s1 == null:
					av = G.h.get(n1, null)
			else:
				av = _eval(an, sc)
			var bt: int = bn[0]
			if bt == E_NUM:
				bv = bn[1]
			elif bt == E_NAME:
				var n2: String = bn[1]
				var s2: Scope = sc
				bv = null
				while s2 != null:
					if s2.v.has(n2):
						bv = s2.v[n2]
						break
					s2 = s2.parent
				if s2 == null:
					bv = G.h.get(n2, null)
			else:
				bv = _eval(bn, sc)
			if av is float and bv is float:
				# the hot path: number OP number, no metatables in sight
				match int(node[1]):
					O_ADD: return av + bv
					O_SUB: return av - bv
					O_MUL: return av * bv
					O_LT: return av < bv
					O_LE: return av <= bv
					O_GT: return av > bv
					O_GE: return av >= bv
					O_EQ: return av == bv
					O_NE: return av != bv
			line = int(node[4])
			return _binop(int(node[1]), av, bv)
	return null

## Everything that can produce more than one value comes through here.
func _eval_multi(node, sc: Scope) -> Array:
	if node == null:
		return []
	match int(node[0]):
		E_CALL:
			line = int(node[3])
			var f = _eval(node[1], sc)
			if f == null:
				_rt("tried to call %s, which is nil" % _describe(node[1]))
				return []
			var args := _eval_list(node[2], sc, -1)
			return _call(f, args)
		E_METH:
			line = int(node[4])
			var obj = _eval(node[1], sc)
			if obj == null:
				_rt("tried to call :%s on nil" % str(node[2]))
				return []
			var m = _index(obj, str(node[2]))
			if m == null:
				_rt("no method named '%s'" % str(node[2]))
				return []
			var args2 := _eval_list(node[3], sc, -1)
			args2.push_front(obj)
			return _call(m, args2)
		E_VARARG:
			var va = sc.get_var("...")
			return (va as Array).duplicate() if va is Array else []
	return [_eval(node, sc)]

## Evaluate an expression list. `want` = -1 keeps every value the last
## expression produced (call/vararg spread); otherwise it pads or trims.
func _eval_list(exprs: Array, sc: Scope, want: int) -> Array:
	var out: Array = []
	for i in exprs.size():
		if i == exprs.size() - 1:
			var tail := _eval_multi(exprs[i], sc)
			out.append_array(tail)
		else:
			out.append(_eval(exprs[i], sc))
	if want >= 0:
		while out.size() < want:
			out.append(null)
		if out.size() > want:
			out.resize(want)
	return out

func _make_func(node: Array, sc: Scope) -> Func:
	var s2: Scope = sc
	while s2 != null and not s2.captured:
		s2.captured = true
		s2 = s2.parent
	var f := Func.new()
	f.params = node[1]
	f.vararg = bool(node[2])
	f.body = node[3]
	f.name = str(node[4])
	f.scope = sc
	return f

## Call anything callable: a Lua function, a host Callable, or a table
## with a __call metamethod.
func _call(f, args: Array) -> Array:
	if err != "":
		return []
	steps += 1
	if steps > budget:
		_rt("this script would not stop (over %d steps in one go)" % budget)
		return []
	if f is Callable:
		var r = (f as Callable).call(args)
		if r is Array:
			return r
		if r == null:
			return []
		return [r]
	if f is Func:
		_depth += 1
		if _depth > MAX_DEPTH:
			_depth -= 1
			_rt("too many nested calls (is something calling itself forever?)")
			return []
		var fn: Func = f
		var sc := Scope.new(fn.scope)
		for i in fn.params.size():
			sc.declare(str(fn.params[i]), args[i] if i < args.size() else null)
		if fn.vararg:
			var rest: Array = []
			for i in range(fn.params.size(), args.size()):
				rest.append(args[i])
			sc.declare("...", rest)
		var r2 = _exec_block(fn.body, sc)
		_depth -= 1
		if r2 != null and str(r2[0]) == "r":
			return r2[1]
		return []
	if f is Table:
		var t: Table = f
		if t.meta != null:
			var c = t.meta.rawget("__call")
			if c != null:
				var a2 := args.duplicate()
				a2.push_front(t)
				return _call(c, a2)
	_rt("tried to call a %s" % type_name(f))
	return []

func _index(obj, key) -> Variant:
	if obj is Table:
		var t: Table = obj
		var v = t.rawget(key)
		if v != null:
			return v
		if t.meta != null:
			var idx = t.meta.rawget("__index")
			if idx is Table:
				return _index(idx, key)
			if idx != null:
				var r := _call(idx, [t, key])
				return r[0] if r.size() > 0 else null
		return null
	if obj is String:
		# "abc":upper() and string.upper("abc") are the same function
		var sl = G.rawget("string")
		if sl is Table:
			return (sl as Table).rawget(key)
		return null
	if obj == null:
		_rt("tried to index nil with '%s'" % str(key))
		return null
	_rt("cannot index a %s" % type_name(obj))
	return null

func _binop(op: int, a, b) -> Variant:
	match op:
		O_EQ: return _lua_eq(a, b)
		O_NE: return not _lua_eq(a, b)
		O_CAT:
			if (a is String or a is float or a is int) \
					and (b is String or b is float or b is int):
				return tostr(a) + tostr(b)
			var mc = _meta_bin(a, b, "__concat")
			if mc != null:
				return mc[0]
			_rt("cannot join a %s and a %s with .." % [type_name(a), type_name(b)])
			return null
		O_LT, O_LE, O_GT, O_GE:
			if a is String and b is String:
				var sa: String = a
				var sb: String = b
				match op:
					O_LT: return sa < sb
					O_LE: return sa <= sb
					O_GT: return sa > sb
					O_GE: return sa >= sb
			var na = _tonum(a)
			var nb = _tonum(b)
			if na == null or nb == null:
				var mm := "__lt" if (op == O_LT or op == O_GT) else "__le"
				var swap: bool = (op == O_GT or op == O_GE)
				var r = _meta_bin(b if swap else a, a if swap else b, mm)
				if r != null:
					return _truthy(r[0])
				_rt("cannot compare a %s with a %s" % [type_name(a), type_name(b)])
				return null
			match op:
				O_LT: return float(na) < float(nb)
				O_LE: return float(na) <= float(nb)
				O_GT: return float(na) > float(nb)
				O_GE: return float(na) >= float(nb)
	# arithmetic
	var x = _tonum(a)
	var y = _tonum(b)
	if x == null or y == null:
		var name: String = ["__add", "__sub", "__mul", "__div", "__mod", "__pow"][op]
		var r2 = _meta_bin(a, b, name)
		if r2 != null:
			return r2[0]
		_rt("cannot do arithmetic on a %s" % type_name(a if x == null else b))
		return null
	var fx := float(x)
	var fy := float(y)
	match op:
		O_ADD: return fx + fy
		O_SUB: return fx - fy
		O_MUL: return fx * fy
		O_DIV:
			return fx / fy if fy != 0.0 else (INF if fx > 0.0 else (-INF if fx < 0.0 else NAN))
		O_MOD:
			if fy == 0.0:
				return NAN
			return fx - floor(fx / fy) * fy
		O_POW: return pow(fx, fy)
	return null

func _meta_bin(a, b, name: String) -> Variant:
	for v in [a, b]:
		if v is Table and (v as Table).meta != null:
			var h = (v as Table).meta.rawget(name)
			if h != null:
				var r := _call(h, [a, b])
				return [r[0] if r.size() > 0 else null]
	return null

func _lua_eq(a, b) -> bool:
	if a == null and b == null:
		return true
	if a is bool or b is bool:
		return (a is bool and b is bool and a == b)
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	if a is String and b is String:
		return a == b
	if a is Table and b is Table:
		if a == b:
			return true
		var ta: Table = a
		if ta.meta != null:
			var eqh = ta.meta.rawget("__eq")
			if eqh != null:
				var r := _call(eqh, [a, b])
				return r.size() > 0 and _truthy(r[0])
		return false
	return a == b

# -------------------------------------------------------------- helpers

static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	return true

static func _tonum(v) -> Variant:
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is String:
		var s := (v as String).strip_edges()
		if s.is_valid_float():
			return s.to_float()
		if s.begins_with("0x") and s.substr(2).is_valid_hex_number():
			return float(s.substr(2).hex_to_int())
		return null
	return null

static func type_name(v) -> String:
	if v == null:
		return "nil"
	if v is bool:
		return "boolean"
	if v is float or v is int:
		return "number"
	if v is String:
		return "string"
	if v is Table:
		return "table"
	if v is Func or v is Callable:
		return "function"
	return "userdata"

## Lua's tostring: integers print without a trailing .0, like 5.1 does.
static func tostr(v) -> String:
	if v == null:
		return "nil"
	if v is bool:
		return "true" if v else "false"
	if v is String:
		return v
	if v is float or v is int:
		var f := float(v)
		if is_nan(f):
			return "nan"
		if is_inf(f):
			return "inf" if f > 0.0 else "-inf"
		if absf(f) < 1e15 and f == floor(f):
			return str(int(f))
		return String.num(f, 14).rstrip("0").rstrip(".")
	if v is Table:
		return "table: 0x%x" % (v as Table).get_instance_id()
	if v is Func:
		return "function: %s" % (v as Func).name
	if v is Callable:
		return "function: builtin"
	return str(v)

func _describe(node) -> String:
	if node is Array and int(node[0]) == E_NAME:
		return "'%s'" % str(node[1])
	if node is Array and int(node[0]) == E_INDEX and int(node[2][0]) == E_STR:
		return "'%s'" % str(node[2][1])
	return "that value"

# =========================================================== the library

## Install the standard library into the globals table. The host adds
## its own API (the console's spr/print/btn) on top of this.
func open_libs() -> void:
	G.rawset("_VERSION", "Lua (DudeSpace)")
	G.rawset("print", Callable(self, "_lb_print"))
	G.rawset("type", Callable(self, "_lb_type"))
	G.rawset("tostring", Callable(self, "_lb_tostring"))
	G.rawset("tonumber", Callable(self, "_lb_tonumber"))
	G.rawset("ipairs", Callable(self, "_lb_ipairs"))
	G.rawset("pairs", Callable(self, "_lb_pairs"))
	G.rawset("next", Callable(self, "_lb_next"))
	G.rawset("select", Callable(self, "_lb_select"))
	G.rawset("rawget", Callable(self, "_lb_rawget"))
	G.rawset("rawset", Callable(self, "_lb_rawset"))
	G.rawset("rawequal", Callable(self, "_lb_rawequal"))
	G.rawset("setmetatable", Callable(self, "_lb_setmeta"))
	G.rawset("getmetatable", Callable(self, "_lb_getmeta"))
	G.rawset("assert", Callable(self, "_lb_assert"))
	G.rawset("error", Callable(self, "_lb_error"))
	G.rawset("pcall", Callable(self, "_lb_pcall"))
	G.rawset("unpack", Callable(self, "_lb_unpack"))

	var m := Table.new()
	m.rawset("pi", PI)
	m.rawset("huge", INF)
	m.rawset("floor", Callable(self, "_m_floor"))
	m.rawset("ceil", Callable(self, "_m_ceil"))
	m.rawset("abs", Callable(self, "_m_abs"))
	m.rawset("sqrt", Callable(self, "_m_sqrt"))
	m.rawset("sin", Callable(self, "_m_sin"))
	m.rawset("cos", Callable(self, "_m_cos"))
	m.rawset("tan", Callable(self, "_m_tan"))
	m.rawset("atan", Callable(self, "_m_atan"))
	m.rawset("atan2", Callable(self, "_m_atan2"))
	m.rawset("asin", Callable(self, "_m_asin"))
	m.rawset("acos", Callable(self, "_m_acos"))
	m.rawset("exp", Callable(self, "_m_exp"))
	m.rawset("log", Callable(self, "_m_log"))
	m.rawset("pow", Callable(self, "_m_pow"))
	m.rawset("fmod", Callable(self, "_m_fmod"))
	m.rawset("modf", Callable(self, "_m_modf"))
	m.rawset("max", Callable(self, "_m_max"))
	m.rawset("min", Callable(self, "_m_min"))
	m.rawset("random", Callable(self, "_m_random"))
	m.rawset("randomseed", Callable(self, "_m_randomseed"))
	G.rawset("math", m)

	var s := Table.new()
	s.rawset("len", Callable(self, "_s_len"))
	s.rawset("sub", Callable(self, "_s_sub"))
	s.rawset("upper", Callable(self, "_s_upper"))
	s.rawset("lower", Callable(self, "_s_lower"))
	s.rawset("rep", Callable(self, "_s_rep"))
	s.rawset("reverse", Callable(self, "_s_reverse"))
	s.rawset("byte", Callable(self, "_s_byte"))
	s.rawset("char", Callable(self, "_s_char"))
	s.rawset("format", Callable(self, "_s_format"))
	s.rawset("find", Callable(self, "_s_find"))
	s.rawset("match", Callable(self, "_s_match"))
	s.rawset("gmatch", Callable(self, "_s_gmatch"))
	s.rawset("gsub", Callable(self, "_s_gsub"))
	G.rawset("string", s)

	var t := Table.new()
	t.rawset("insert", Callable(self, "_t_insert"))
	t.rawset("remove", Callable(self, "_t_remove"))
	t.rawset("concat", Callable(self, "_t_concat"))
	t.rawset("sort", Callable(self, "_t_sort"))
	t.rawset("getn", Callable(self, "_t_getn"))
	G.rawset("table", t)

var out_lines: Array = []          # everything print() has said
const OUT_MAX := 400

func _a(args: Array, i: int):
	return args[i] if i < args.size() else null

func _an(args: Array, i: int, d: float = 0.0) -> float:
	var v = _tonum(_a(args, i))
	return float(v) if v != null else d

func _as(args: Array, i: int, d: String = "") -> String:
	var v = _a(args, i)
	if v == null:
		return d
	return tostr(v)

func _lb_print(args: Array) -> Array:
	var parts: Array = []
	for v in args:
		parts.append(tostr(v))
	out_lines.append("\t".join(parts))
	if out_lines.size() > OUT_MAX:
		out_lines = out_lines.slice(out_lines.size() - OUT_MAX)
	return []

func _lb_type(args: Array) -> Array:
	return [type_name(_a(args, 0))]

func _lb_tostring(args: Array) -> Array:
	var v = _a(args, 0)
	if v is Table and (v as Table).meta != null:
		var h = (v as Table).meta.rawget("__tostring")
		if h != null:
			return _call(h, [v])
	return [tostr(v)]

func _lb_tonumber(args: Array) -> Array:
	var base := int(_an(args, 1, 10.0))
	if base != 10 and _a(args, 0) is String:
		var digits := "0123456789abcdefghijklmnopqrstuvwxyz"
		var sv := (_as(args, 0)).strip_edges().to_lower()
		var acc := 0.0
		if sv == "":
			return [null]
		for ch in sv:
			var d := digits.find(ch)
			if d < 0 or d >= base:
				return [null]
			acc = acc * float(base) + float(d)
		return [acc]
	return [_tonum(_a(args, 0))]

func _lb_ipairs(args: Array) -> Array:
	var t = _a(args, 0)
	if not (t is Table):
		_rt("ipairs wants a table")
		return []
	return [Callable(self, "_iter_i"), t, 0.0]

func _iter_i(args: Array) -> Array:
	var t: Table = _a(args, 0)
	var i := _an(args, 1) + 1.0
	var v = t.rawget(i)
	if v == null:
		return [null]
	return [i, v]

func _lb_pairs(args: Array) -> Array:
	var t = _a(args, 0)
	if not (t is Table):
		_rt("pairs wants a table")
		return []
	return [Callable(self, "_lb_next"), t, null]

func _lb_next(args: Array) -> Array:
	var t = _a(args, 0)
	if not (t is Table):
		return [null]
	var keys: Array = (t as Table).h.keys()
	var k = _a(args, 1)
	if k == null:
		if keys.is_empty():
			return [null]
		return [keys[0], (t as Table).h[keys[0]]]
	if k is int:
		k = float(k)
	var i := keys.find(k)
	if i < 0 or i + 1 >= keys.size():
		return [null]
	return [keys[i + 1], (t as Table).h[keys[i + 1]]]

func _lb_select(args: Array) -> Array:
	var n = _a(args, 0)
	if n is String and str(n) == "#":
		return [float(args.size() - 1)]
	var i := int(_an(args, 0, 1.0))
	var out: Array = []
	for j in range(i, args.size()):
		out.append(args[j])
	return out

func _lb_rawget(args: Array) -> Array:
	var t = _a(args, 0)
	return [(t as Table).rawget(_a(args, 1))] if t is Table else [null]

func _lb_rawset(args: Array) -> Array:
	var t = _a(args, 0)
	if t is Table:
		(t as Table).rawset(_a(args, 1), _a(args, 2))
	return [t]

func _lb_rawequal(args: Array) -> Array:
	return [_a(args, 0) == _a(args, 1)]

func _lb_setmeta(args: Array) -> Array:
	var t = _a(args, 0)
	var mt = _a(args, 1)
	if t is Table:
		(t as Table).meta = mt if mt is Table else null
	return [t]

func _lb_getmeta(args: Array) -> Array:
	var t = _a(args, 0)
	if t is Table and (t as Table).meta != null:
		return [(t as Table).meta]
	return [null]

func _lb_assert(args: Array) -> Array:
	if not _truthy(_a(args, 0)):
		_rt(_as(args, 1, "assertion failed!"))
		return []
	return args

func _lb_error(args: Array) -> Array:
	_rt(_as(args, 0, "error"))
	return []

## pcall: run it, and if the interpreter errored, hand the message back
## instead of killing the cartridge.
func _lb_pcall(args: Array) -> Array:
	var f = _a(args, 0)
	var rest: Array = []
	for i in range(1, args.size()):
		rest.append(args[i])
	var saved := err
	err = ""
	var r := _call(f, rest)
	if err != "":
		var msg := err
		err = saved
		return [false, msg]
	err = saved
	var out: Array = [true]
	out.append_array(r)
	return out

func _lb_unpack(args: Array) -> Array:
	var t = _a(args, 0)
	if not (t is Table):
		return []
	var tt: Table = t
	var i := int(_an(args, 1, 1.0))
	var j := int(_an(args, 2, float(tt.length())))
	var out: Array = []
	for k in range(i, j + 1):
		out.append(tt.rawget(float(k)))
	return out

# --- math
func _m_floor(a: Array) -> Array: return [floor(_an(a, 0))]
func _m_ceil(a: Array) -> Array: return [ceil(_an(a, 0))]
func _m_abs(a: Array) -> Array: return [absf(_an(a, 0))]
func _m_sqrt(a: Array) -> Array: return [sqrt(maxf(0.0, _an(a, 0)))]
func _m_sin(a: Array) -> Array: return [sin(_an(a, 0))]
func _m_cos(a: Array) -> Array: return [cos(_an(a, 0))]
func _m_tan(a: Array) -> Array: return [tan(_an(a, 0))]
func _m_atan(a: Array) -> Array: return [atan(_an(a, 0))]
func _m_atan2(a: Array) -> Array: return [atan2(_an(a, 0), _an(a, 1, 1.0))]
func _m_asin(a: Array) -> Array: return [asin(clampf(_an(a, 0), -1.0, 1.0))]
func _m_acos(a: Array) -> Array: return [acos(clampf(_an(a, 0), -1.0, 1.0))]
func _m_exp(a: Array) -> Array: return [exp(_an(a, 0))]
func _m_log(a: Array) -> Array: return [log(maxf(1e-12, _an(a, 0)))]
func _m_pow(a: Array) -> Array: return [pow(_an(a, 0), _an(a, 1))]
func _m_fmod(a: Array) -> Array: return [fmod(_an(a, 0), _an(a, 1, 1.0))]

func _m_modf(a: Array) -> Array:
	var v := _an(a, 0)
	var ip := floorf(absf(v)) * signf(v)
	return [ip, v - ip]

func _m_max(a: Array) -> Array:
	var best := -INF
	for v in a:
		best = maxf(best, float(_tonum(v)) if _tonum(v) != null else -INF)
	return [best]

func _m_min(a: Array) -> Array:
	var best := INF
	for v in a:
		best = minf(best, float(_tonum(v)) if _tonum(v) != null else INF)
	return [best]

var _rng := RandomNumberGenerator.new()

func _m_random(a: Array) -> Array:
	if a.is_empty():
		return [_rng.randf()]
	if a.size() == 1:
		return [float(_rng.randi_range(1, maxi(1, int(_an(a, 0, 1.0)))))]
	return [float(_rng.randi_range(int(_an(a, 0)), int(_an(a, 1))))]

func _m_randomseed(a: Array) -> Array:
	_rng.seed = int(_an(a, 0))
	return []

# --- string
func _s_len(a: Array) -> Array: return [float(_as(a, 0).length())]

## Lua string indices: 1-based, negatives count from the end.
static func _str_i(s: String, i: float, d: int) -> int:
	var n := s.length()
	var v := int(i)
	if v == 0:
		return d
	if v < 0:
		v = n + v + 1
	return v

func _s_sub(a: Array) -> Array:
	var s := _as(a, 0)
	var n := s.length()
	var i := _str_i(s, _an(a, 1, 1.0), 1)
	var j := _str_i(s, _an(a, 2, -1.0), n)
	i = maxi(1, i)
	j = mini(n, j)
	if i > j:
		return [""]
	return [s.substr(i - 1, j - i + 1)]

func _s_upper(a: Array) -> Array: return [_as(a, 0).to_upper()]
func _s_lower(a: Array) -> Array: return [_as(a, 0).to_lower()]

func _s_rep(a: Array) -> Array:
	var n := int(_an(a, 1))
	if n <= 0:
		return [""]
	return [_as(a, 0).repeat(mini(n, 100000))]

func _s_reverse(a: Array) -> Array: return [_as(a, 0).reverse()]

func _s_byte(a: Array) -> Array:
	var s := _as(a, 0)
	var i := _str_i(s, _an(a, 1, 1.0), 1)
	var j := _str_i(s, _an(a, 2, float(i)), i)
	var out: Array = []
	for k in range(maxi(1, i), mini(s.length(), j) + 1):
		out.append(float(s.unicode_at(k - 1)))
	return out

func _s_char(a: Array) -> Array:
	var s := ""
	for v in a:
		s += char(int(float(_tonum(v)) if _tonum(v) != null else 32.0))
	return [s]

## string.format with the specifiers a game actually uses: %d %i %s %f
## %.Nf %x %X %c %% and width/zero padding.
func _s_format(a: Array) -> Array:
	var f := _as(a, 0)
	var out := ""
	var ai := 1
	var i := 0
	while i < f.length():
		var c := f[i]
		if c != "%":
			out += c
			i += 1
			continue
		i += 1
		if i < f.length() and f[i] == "%":
			out += "%"
			i += 1
			continue
		var flags := ""
		while i < f.length() and f[i] in ["-", "+", " ", "0", "#"]:
			flags += f[i]
			i += 1
		var width := ""
		while i < f.length() and f[i] >= "0" and f[i] <= "9":
			width += f[i]
			i += 1
		var prec := ""
		if i < f.length() and f[i] == ".":
			i += 1
			while i < f.length() and f[i] >= "0" and f[i] <= "9":
				prec += f[i]
				i += 1
		if i >= f.length():
			break
		var conv := f[i]
		i += 1
		var piece := ""
		match conv:
			"d", "i":
				piece = str(int(_an(a, ai)))
				ai += 1
			"u":
				piece = str(absi(int(_an(a, ai))))
				ai += 1
			"f", "g":
				var digits := int(prec) if prec != "" else 6
				piece = String.num(_an(a, ai), digits)
				ai += 1
			"s":
				piece = tostr(_a(a, ai))
				if prec != "":
					piece = piece.substr(0, int(prec))
				ai += 1
			"x":
				piece = "%x" % int(_an(a, ai))
				ai += 1
			"X":
				piece = ("%x" % int(_an(a, ai))).to_upper()
				ai += 1
			"c":
				piece = char(int(_an(a, ai)))
				ai += 1
			_:
				piece = conv
		if width != "":
			var w := int(width)
			var pad := "0" if flags.contains("0") and not flags.contains("-") else " "
			while piece.length() < w:
				if flags.contains("-"):
					piece += " "
				else:
					piece = pad + piece
		out += piece
	return [out]

# --- Lua patterns. Classes %a %d %l %s %u %w %x %p, sets [] with ranges
# and negation, anchors ^ $, quantifiers * + - ?, captures ().
class Pat extends RefCounted:
	var p: String = ""
	var s: String = ""
	var caps: Array = []            # [start, len] (len -1 = position capture)

	func class_match(c: String, cl: String) -> bool:
		var r := false
		var lower := cl.to_lower()
		match lower:
			"a": r = _alpha(c)
			"d": r = c >= "0" and c <= "9"
			"l": r = c >= "a" and c <= "z"
			"s": r = c == " " or c == "\t" or c == "\n" or c == "\r"
			"u": r = c >= "A" and c <= "Z"
			"w": r = _alpha(c) or (c >= "0" and c <= "9")
			"x": r = _hexc(c)
			"p": r = _punct(c)
			"c": r = c.unicode_at(0) < 32
			_: return c == cl
		if cl != lower:
			return not r
		return r

	static func _hexc(c: String) -> bool:
		return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") \
			or (c >= "A" and c <= "F")

	static func _alpha(c: String) -> bool:
		return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

	static func _punct(c: String) -> bool:
		return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(c)

	## Does the single pattern item at pi match s[si]?
	func single(si: int, pi: int, ep: int) -> bool:
		if si >= s.length():
			return false
		var c := s[si]
		var pc := p[pi]
		if pc == ".":
			return true
		if pc == "%":
			return class_match(c, p[pi + 1])
		if pc == "[":
			return set_match(c, pi, ep)
		return pc == c

	func set_match(c: String, pi: int, ep: int) -> bool:
		var i := pi + 1
		var neg := false
		if i < p.length() and p[i] == "^":
			neg = true
			i += 1
		var hit := false
		while i < ep - 1:
			if p[i] == "%" and i + 1 < ep:
				i += 1
				if class_match(c, p[i]):
					hit = true
				i += 1
				continue
			if i + 2 < ep - 1 and p[i + 1] == "-":
				if p[i] <= c and c <= p[i + 2]:
					hit = true
				i += 3
				continue
			if p[i] == c:
				hit = true
			i += 1
		return hit != neg

	## Index just past the pattern item that starts at pi.
	func item_end(pi: int) -> int:
		var pc := p[pi]
		pi += 1
		if pc == "%":
			return pi + 1
		if pc == "[":
			if pi < p.length() and p[pi] == "^":
				pi += 1
			var first := true
			while pi < p.length() and (p[pi] != "]" or first):
				first = false
				if p[pi] == "%":
					pi += 1
				pi += 1
			return pi + 1
		return pi

	## The matcher itself. Returns the end index in s, or -1.
	func m(si: int, pi: int) -> int:
		while si <= s.length() or true:
			if pi >= p.length():
				return si
			var pc := p[pi]
			if pc == "(":
				if pi + 1 < p.length() and p[pi + 1] == ")":
					caps.append([si, -1])
					var r := m(si, pi + 2)
					if r < 0:
						caps.pop_back()
					return r
				caps.append([si, -2])          # -2 = still open
				var r2 := m(si, pi + 1)
				if r2 < 0:
					caps.pop_back()
				return r2
			if pc == ")":
				for k in range(caps.size() - 1, -1, -1):
					if int(caps[k][1]) == -2:
						caps[k][1] = si - int(caps[k][0])
						var r3 := m(si, pi + 1)
						if r3 < 0:
							caps[k][1] = -2
						return r3
				return -1
			if pc == "$" and pi + 1 == p.length():
				return si if si == s.length() else -1
			if pc == "%" and pi + 1 < p.length() and p[pi + 1] == "b":
				# %bxy: balanced pair
				if si >= s.length() or s[si] != p[pi + 2]:
					return -1
				var o := p[pi + 2]
				var cch := p[pi + 3]
				var depth := 1
				var j := si + 1
				while j < s.length():
					if s[j] == cch:
						depth -= 1
						if depth == 0:
							return m(j + 1, pi + 4)
					elif s[j] == o:
						depth += 1
					j += 1
				return -1
			var ep := item_end(pi)
			var suffix := p[ep] if ep < p.length() else ""
			if suffix == "?":
				if single(si, pi, ep):
					var r4 := m(si + 1, ep + 1)
					if r4 >= 0:
						return r4
				pi = ep + 1
				continue
			if suffix == "*":
				return max_expand(si, pi, ep)
			if suffix == "+":
				return max_expand(si + 1, pi, ep) if single(si, pi, ep) else -1
			if suffix == "-":
				return min_expand(si, pi, ep)
			if not single(si, pi, ep):
				return -1
			si += 1
			pi = ep
		return -1

	func max_expand(si: int, pi: int, ep: int) -> int:
		var i := 0
		while single(si + i, pi, ep):
			i += 1
		while i >= 0:
			var r := m(si + i, ep + 1)
			if r >= 0:
				return r
			i -= 1
		return -1

	func min_expand(si: int, pi: int, ep: int) -> int:
		while si <= s.length():
			var r := m(si, ep + 1)
			if r >= 0:
				return r
			if single(si, pi, ep):
				si += 1
			else:
				return -1
		return -1

## Run `pat` against `s` from `init`; returns [start, end, captures] or [].
func _pat_find(s: String, pat: String, init: int) -> Array:
	var anchored := pat.begins_with("^")
	var pp := pat.substr(1) if anchored else pat
	var si := maxi(0, init)
	while si <= s.length():
		var m := Pat.new()
		m.p = pp
		m.s = s
		var e := m.m(si, 0)
		if e >= 0:
			var caps: Array = []
			for c in m.caps:
				if int(c[1]) == -1:
					caps.append(float(int(c[0]) + 1))
				else:
					caps.append(s.substr(int(c[0]), maxi(0, int(c[1]))))
			return [si, e, caps]
		if anchored:
			break
		si += 1
	return []

func _s_find(a: Array) -> Array:
	var s := _as(a, 0)
	var pat := _as(a, 1)
	var init := _str_i(s, _an(a, 2, 1.0), 1) - 1
	var plain := _truthy(_a(a, 3))
	if plain:
		var idx := s.find(pat, maxi(0, init))
		if idx < 0:
			return [null]
		return [float(idx + 1), float(idx + pat.length())]
	var r := _pat_find(s, pat, init)
	if r.is_empty():
		return [null]
	var out: Array = [float(int(r[0]) + 1), float(int(r[1]))]
	out.append_array(r[2])
	return out

func _s_match(a: Array) -> Array:
	var s := _as(a, 0)
	var init := _str_i(s, _an(a, 2, 1.0), 1) - 1
	var r := _pat_find(s, _as(a, 1), init)
	if r.is_empty():
		return [null]
	if (r[2] as Array).is_empty():
		return [s.substr(int(r[0]), int(r[1]) - int(r[0]))]
	return r[2]

var _gm_state: Dictionary = {}

func _s_gmatch(a: Array) -> Array:
	var st := {"s": _as(a, 0), "p": _as(a, 1), "i": 0}
	var key := _gm_state.size()
	_gm_state[key] = st
	return [Callable(self, "_gm_step").bind(key)]

func _gm_step(_args: Array, key: int) -> Array:
	var st: Dictionary = _gm_state.get(key, {})
	if st.is_empty():
		return [null]
	var r := _pat_find(str(st["s"]), str(st["p"]), int(st["i"]))
	if r.is_empty():
		_gm_state.erase(key)
		return [null]
	var e := int(r[1])
	st["i"] = e if e > int(r[0]) else int(r[0]) + 1
	if (r[2] as Array).is_empty():
		return [str(st["s"]).substr(int(r[0]), e - int(r[0]))]
	return r[2]

func _s_gsub(a: Array) -> Array:
	var s := _as(a, 0)
	var pat := _as(a, 1)
	var rep = _a(a, 2)
	var limit := int(_an(a, 3, 1e9))
	var out := ""
	var i := 0
	var n := 0
	while i <= s.length() and n < limit:
		var r := _pat_find(s, pat, i)
		if r.is_empty():
			break
		var st := int(r[0])
		var e := int(r[1])
		var whole := s.substr(st, e - st)
		var caps: Array = r[2]
		if caps.is_empty():
			caps = [whole]
		out += s.substr(i, st - i)
		var piece := ""
		if rep is String:
			var rs: String = rep
			var k := 0
			while k < rs.length():
				if rs[k] == "%" and k + 1 < rs.length():
					var d := rs[k + 1]
					if d == "0":
						piece += whole
					elif d >= "1" and d <= "9":
						var ci := int(d) - 1
						piece += tostr(caps[ci]) if ci < caps.size() else ""
					else:
						piece += d
					k += 2
					continue
				piece += rs[k]
				k += 1
		elif rep is Table:
			var v = (rep as Table).rawget(caps[0])
			piece = tostr(v) if v != null else whole
		else:
			var rr := _call(rep, caps)
			piece = tostr(rr[0]) if rr.size() > 0 and rr[0] != null else whole
		out += piece
		n += 1
		if e > st:
			i = e
		else:
			if st < s.length():
				out += s[st]
			i = st + 1
	out += s.substr(i)
	return [out, float(n)]

# --- table
func _t_insert(a: Array) -> Array:
	var t = _a(a, 0)
	if not (t is Table):
		_rt("table.insert wants a table")
		return []
	var tt: Table = t
	if a.size() >= 3:
		var pos := int(_an(a, 1, 1.0))
		var n := tt.length()
		for k in range(n, pos - 1, -1):
			tt.rawset(float(k + 1), tt.rawget(float(k)))
		tt.rawset(float(pos), _a(a, 2))
	else:
		tt.rawset(float(tt.length() + 1), _a(a, 1))
	return []

func _t_remove(a: Array) -> Array:
	var t = _a(a, 0)
	if not (t is Table):
		return [null]
	var tt: Table = t
	var n := tt.length()
	if n == 0:
		return [null]
	var pos := int(_an(a, 1, float(n)))
	var v = tt.rawget(float(pos))
	for k in range(pos, n):
		tt.rawset(float(k), tt.rawget(float(k + 1)))
	tt.rawset(float(n), null)
	return [v]

func _t_concat(a: Array) -> Array:
	var t = _a(a, 0)
	if not (t is Table):
		return [""]
	var sep := _as(a, 1, "")
	var tt: Table = t
	var i := int(_an(a, 2, 1.0))
	var j := int(_an(a, 3, float(tt.length())))
	var parts: Array = []
	for k in range(i, j + 1):
		parts.append(tostr(tt.rawget(float(k))))
	return [sep.join(parts)]

func _t_getn(a: Array) -> Array:
	var t = _a(a, 0)
	return [float((t as Table).length())] if t is Table else [0.0]

func _t_sort(a: Array) -> Array:
	var t = _a(a, 0)
	if not (t is Table):
		return []
	var tt: Table = t
	var arr := tt.to_array()
	var cmp = _a(a, 1)
	if cmp == null:
		arr.sort_custom(func(x, y):
			if x is String and y is String:
				return (x as String) < (y as String)
			var nx = _tonum(x)
			var ny = _tonum(y)
			return float(nx if nx != null else 0.0) < float(ny if ny != null else 0.0))
	else:
		# a comparator that errors must not take the sort down with it
		arr.sort_custom(func(x, y):
			var r := _call(cmp, [x, y])
			return r.size() > 0 and _truthy(r[0]))
	for i in arr.size():
		tt.rawset(float(i + 1), arr[i])
	return []
