class_name Circuit
extends Node3D
## A LIVE breadboard circuit on Circuitia. Real DC nodal analysis
## (CircuitSolver: Ohm's law + Gaussian elimination + transistors) re-runs
## every time you flip a switch (F). Node pillars rise to their solved
## voltage, wires glow with current, transistors light when conducting.

const SRC_V := 9.0

var _n: int = 0
var _pos2d: Array = []          # ground positions per node (local)
var _resistors: Array = []      # [a, b, ohms, switch_idx (-1 = none)]
var _trans: Array = []          # [base, collector, emitter]
var _switch_state: Array = []   # bool per switch
var _switch_nodes: Array = []   # _Switch instances
var _pillars: Array = []        # MeshInstance3D per node
var _pillar_mats: Array = []
var _wire_mats: Array = []      # per resistor
var _trans_mats: Array = []

func build() -> void:
	_n = randi_range(6, 9)
	for i in _n:
		var ang := TAU * float(i) / float(_n)
		_pos2d.append(Vector3(cos(ang) * 7.0, 0.0, sin(ang) * 7.0))

	# random resistor mesh; some resistors run through a SWITCH
	var switch_count := randi_range(2, 3)
	for i in range(1, _n):
		var sw := -1
		if _switch_state.size() < switch_count and randf() < 0.5:
			sw = _switch_state.size()
			_switch_state.append(true)
		_resistors.append([i, randi_range(0, i - 1), float(randi_range(20, 400)), sw])
	for _k in randi_range(1, 3):
		var a := randi_range(0, _n - 1)
		var b := randi_range(0, _n - 1)
		if a != b:
			_resistors.append([a, b, float(randi_range(50, 800)), -1])
	while _switch_state.size() < switch_count:
		# guarantee the switches exist: retrofit one onto a random resistor
		var r: Array = _resistors[randi() % _resistors.size()]
		if int(r[3]) == -1:
			r[3] = _switch_state.size()
			_switch_state.append(true)

	for _k in randi_range(1, 3):
		var base := randi_range(1, _n - 1)
		var coll := randi_range(1, _n - 1)
		var emit := randi_range(0, _n - 1)
		if base != coll and coll != emit:
			_trans.append([base, coll, emit])

	_build_visuals()
	resolve()

func _build_visuals() -> void:
	# node pillars: live voltage bars (unshaded, scaled on resolve)
	for i in _n:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.8, 1.0, 0.8)
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mi.material_override = mat
		add_child(mi)
		mi.position = _pos2d[i]
		_pillars.append(mi)
		_pillar_mats.append(mat)
	# the source node gets a marker post
	var src := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.2
	sm.bottom_radius = 0.2
	sm.height = 7.0
	src.mesh = sm
	src.material_override = Destructible.make_material(Color("#ffd166"), 3.0)
	add_child(src)
	src.position = _pos2d[1] + Vector3(0, 3.5, 0)

	# wires (drawn at solve-time heights: node-top to node-top)
	for r in _resistors:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.albedo_color = Color("#6fe0ff")
		var mi := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		im.surface_add_vertex(_pos2d[int(r[0])] + Vector3(0, 6.4, 0))
		im.surface_add_vertex(_pos2d[int(r[1])] + Vector3(0, 6.4, 0))
		im.surface_end()
		mi.mesh = im
		add_child(mi)
		_wire_mats.append(mat)
		# switch block sits at the wire midpoint
		if int(r[3]) >= 0:
			var sw := _Switch.new()
			sw.circuit = self
			sw.idx = int(r[3])
			add_child(sw)
			sw.position = (_pos2d[int(r[0])] + _pos2d[int(r[1])]) * 0.5
			_switch_nodes.append(sw)

	# transistors
	for t in _trans:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(1.0, 1.0, 1.0)
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mi.material_override = mat
		add_child(mi)
		mi.position = (_pos2d[int(t[1])] + _pos2d[int(t[2])]) * 0.5 + Vector3(0, 1.2, 0)
		_trans_mats.append(mat)

	# some breakables around the board (it IS still that kind of game)
	for i in 6:
		var d := Destructible.new()
		var s := randf_range(0.8, 1.6)
		d.setup(Vector3(s, s, s), Color("#0e6b4e"), 1, 8, 0.4)
		add_child(d)
		var ang := randf() * TAU
		d.position = Vector3(cos(ang) * 11.0, s * 0.5, sin(ang) * 11.0)

func toggle(idx: int) -> void:
	_switch_state[idx] = not _switch_state[idx]
	Sfx.play("click")
	resolve()

## Re-run the REAL DC solve with the current switch states.
func resolve() -> void:
	var active: Array = []
	for r in _resistors:
		if int(r[3]) == -1 or _switch_state[int(r[3])]:
			active.append([r[0], r[1], r[2]])
	var sol := CircuitSolver.solve(_n, active, {1: SRC_V}, _trans)
	var v: PackedFloat64Array = sol["v"]
	var on: Array = sol["on"]

	for i in _n:
		var volt := clampf(float(v[i]) / SRC_V, 0.0, 1.0)
		var h := volt * 6.0 + 0.4
		_pillars[i].scale = Vector3(1, h, 1)
		_pillars[i].position = _pos2d[i] + Vector3(0, h * 0.5, 0)
		var mat: StandardMaterial3D = _pillar_mats[i]
		mat.albedo_color = Color(volt, 0.2, 1.0 - volt)
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.6 + volt * 2.0
	for k in _resistors.size():
		var r: Array = _resistors[k]
		var mat2: StandardMaterial3D = _wire_mats[k]
		var live: bool = int(r[3]) == -1 or _switch_state[int(r[3])]
		if not live:
			mat2.emission = Color("#552222")
			mat2.emission_energy_multiplier = 0.15
			continue
		var cur := absf(float(v[int(r[0])]) - float(v[int(r[1])])) / float(r[2])
		mat2.emission = Color("#6fe0ff")
		mat2.emission_energy_multiplier = clampf(cur * 40.0, 0.2, 8.0)
	for k in _trans.size():
		var lit: bool = on[k]
		var mat3: StandardMaterial3D = _trans_mats[k]
		mat3.albedo_color = Color("#ffd166") if lit else Color("#33321a")
		mat3.emission = mat3.albedo_color
		mat3.emission_energy_multiplier = 5.0 if lit else 0.2
	for sw in _switch_nodes:
		sw.refresh(_switch_state[sw.idx])

## Breadboard switch block. F flips it; the whole board re-solves.
class _Switch extends StaticBody3D:
	var circuit: Circuit
	var idx: int = 0
	var _mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("logic_input")   # same F-interact group as diagram inputs
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.8, 0.8, 0.8)
		mi.mesh = m
		_mat = StandardMaterial3D.new()
		_mat.emission_enabled = true
		mi.material_override = _mat
		mi.position = Vector3(0, 0.4, 0)
		add_child(mi)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(0.9, 0.9, 0.9)
		col.shape = cs
		col.position = Vector3(0, 0.4, 0)
		add_child(col)
		var lbl := Label3D.new()
		lbl.text = "[F]"
		lbl.font_size = 22
		lbl.modulate = Color(1, 1, 1, 0.6)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.3, 0)
		add_child(lbl)

	func refresh(closed: bool) -> void:
		if _mat:
			_mat.albedo_color = Color("#2bff6a") if closed else Color("#ff3b3b")
			_mat.emission = _mat.albedo_color
			_mat.emission_energy_multiplier = 2.5 if closed else 1.2

	func use() -> void:
		if circuit and is_instance_valid(circuit):
			circuit.toggle(idx)
