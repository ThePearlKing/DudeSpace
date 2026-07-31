class_name CircuitSolver
extends RefCounted
## A tiny but real DC circuit simulator.
## Nodal analysis: build the conductance matrix G, solve G*v = i by
## Gaussian elimination. Node 0 is ground (0 V). Ideal voltage sources
## are fixed nodes. NPN transistors are modelled as voltage-controlled
## switches (conduct when V(base)-V(emitter) > 0.6 V) and resolved by
## fixed-point iteration since that makes the system nonlinear.

const VBE_ON := 0.6
const R_ON := 5.0        # collector-emitter on-resistance (ohms)

## resistors: Array of [a, b, ohms]
## fixed:     Dictionary {node: volts}   (voltage sources to ground etc.)
## trans:     Array of [base, collector, emitter]
## Returns {"v": PackedFloat64Array, "on": Array[bool]}
static func solve(n: int, resistors: Array, fixed: Dictionary, trans: Array) -> Dictionary:
	var on: Array = []
	for t in trans:
		on.append(false)
	var v := PackedFloat64Array()
	v.resize(n)

	for _iter in 10:
		var g: Array = []
		var b := PackedFloat64Array()
		b.resize(n)
		for i in n:
			var row := PackedFloat64Array()
			row.resize(n)
			g.append(row)

		for r in resistors:
			_stamp(g, int(r[0]), int(r[1]), 1.0 / float(r[2]))
		for k in trans.size():
			if on[k]:
				_stamp(g, int(trans[k][1]), int(trans[k][2]), 1.0 / R_ON)

		# Ground + fixed voltage nodes.
		_fix(g, b, 0, 0.0)
		for node in fixed:
			_fix(g, b, int(node), float(fixed[node]))

		v = _gauss(g, b, n)

		var stable := true
		for k in trans.size():
			var conduct: bool = (v[int(trans[k][0])] - v[int(trans[k][2])]) > VBE_ON
			if conduct != on[k]:
				on[k] = conduct
				stable = false
		if stable:
			break

	return {"v": v, "on": on}

static func _stamp(g: Array, a: int, b: int, cond: float) -> void:
	g[a][a] += cond
	g[b][b] += cond
	g[a][b] -= cond
	g[b][a] -= cond

## Force node `node` to `val` volts and move the known term to the RHS.
static func _fix(g: Array, b: PackedFloat64Array, node: int, val: float) -> void:
	var n := b.size()
	for i in n:
		if i != node:
			b[i] -= g[i][node] * val
			g[i][node] = 0.0
			g[node][i] = 0.0
	g[node][node] = 1.0
	b[node] = val

## Gaussian elimination with partial pivoting. Returns solution vector.
static func _gauss(g: Array, b: PackedFloat64Array, n: int) -> PackedFloat64Array:
	for col in n:
		var piv := col
		var best := absf(g[col][col])
		for r in range(col + 1, n):
			if absf(g[r][col]) > best:
				best = absf(g[r][col])
				piv = r
		if best < 1e-12:
			continue   # singular column, skip
		if piv != col:
			var tmp: PackedFloat64Array = g[col]
			g[col] = g[piv]
			g[piv] = tmp
			var tb := b[col]; b[col] = b[piv]; b[piv] = tb
		var d: float = g[col][col]
		for r in n:
			if r == col:
				continue
			var f: float = g[r][col] / d
			if f == 0.0:
				continue
			for c in range(col, n):
				g[r][c] -= f * g[col][c]
			b[r] -= f * b[col]
	var x := PackedFloat64Array()
	x.resize(n)
	for i in n:
		if absf(g[i][i]) > 1e-12:
			x[i] = b[i] / g[i][i]
		else:
			x[i] = 0.0
	return x
