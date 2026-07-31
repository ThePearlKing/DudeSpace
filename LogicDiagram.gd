class_name LogicDiagram
extends Node3D
## A WORKING logic circuit standing in the world like a blueprint. Blank
## panels, no labels: inputs are the small blocks at the bottom (F to
## toggle), signal glow crawls up the wires, one output lamp at the top.
## Figure out what each gate does. Breaking panels pays decently.

var _nodes: Array = []     # {type, ins: [idx], out: bool, panel, pos}
var _wires: Array = []     # {a_idx, b_idx, mat}
var _inputs: Array = []    # node indices that are toggleable

func build() -> void:
	var rng_inputs := randi_range(2, 4)
	var layers := [rng_inputs, randi_range(2, 3), randi_range(1, 2), 1]
	var idx := 0
	for li in layers.size():
		var count: int = layers[li]
		for i in count:
			var x := (float(i) - float(count - 1) * 0.5) * 5.0
			var y := 2.0 + float(li) * 4.0
			var jitter := Vector3(randf_range(-0.7, 0.7), randf_range(-0.5, 0.5), 0)
			var n := {
				"type": "in" if li == 0 else (["and", "or", "xor", "not"][randi() % 4]),
				"ins": [], "out": false, "panel": null,
				"pos": Vector3(x, y, 0) + jitter, "layer": li, "idx": idx,
			}
			_nodes.append(n)
			if li == 0:
				_inputs.append(idx)
			idx += 1
	# wire each non-input to 1-2 nodes from the previous layer
	for i in _nodes.size():
		var n: Dictionary = _nodes[i]
		if n["type"] == "in":
			continue
		var prev: Array = []
		for j in _nodes.size():
			if _nodes[j]["layer"] == int(n["layer"]) - 1:
				prev.append(j)
		prev.shuffle()
		var want: int = 1 if n["type"] == "not" else mini(2, prev.size())
		for k in want:
			n["ins"].append(prev[k])
			_wires.append({"a": prev[k], "b": i, "mat": null})

	# --- visuals ---
	for i in _nodes.size():
		var n: Dictionary = _nodes[i]
		var is_in: bool = n["type"] == "in"
		var is_out: bool = int(n["layer"]) == 3
		var d := Destructible.new()
		var s := 1.0 if is_in else randf_range(1.2, 1.8)
		# breaking the machine pays: inputs 10, gates 20, the lamp 40
		var pay := 10 if is_in else (40 if is_out else 20)
		d.setup(Vector3(s, s, 0.35), Color("#20242c"), 1, pay, 0.05)
		add_child(d)
		d.position = n["pos"]
		n["panel"] = d
		if not is_in:
			_draw_gate_symbol(str(n["type"]), n["pos"] + Vector3(0, 0, 0.45), is_out)
		if is_in:
			var sw := _InputSwitch.new()
			sw.diagram = self
			sw.node_idx = i
			add_child(sw)
			sw.position = n["pos"] + Vector3(0, -1.2, 0)
	for w in _wires:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.albedo_color = Color("#dfe6ff")
		w["mat"] = mat
		var mi := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		im.surface_add_vertex(_nodes[w["a"]]["pos"])
		im.surface_add_vertex(_nodes[w["b"]]["pos"])
		im.surface_end()
		mi.mesh = im
		add_child(mi)
	evaluate()

func toggle(i: int) -> void:
	_nodes[i]["out"] = not bool(_nodes[i]["out"])
	Sfx.play("click")
	evaluate()

## Propagate signals layer by layer, light up wires + panels that carry 1.
func evaluate() -> void:
	for li in range(1, 4):
		for n in _nodes:
			if int(n["layer"]) != li:
				continue
			var vals: Array = []
			for j in n["ins"]:
				vals.append(bool(_nodes[j]["out"]))
			var v := false
			match n["type"]:
				"and":
					v = vals.size() > 0
					for x in vals:
						v = v and x
				"or":
					for x in vals:
						v = v or x
				"xor":
					for x in vals:
						v = (v != x)
				"not":
					v = not (vals[0] if vals.size() > 0 else false)
			n["out"] = v
	for w in _wires:
		var on: bool = bool(_nodes[w["a"]]["out"])
		var m: StandardMaterial3D = w["mat"]
		m.emission = Color("#39ff88") if on else Color("#dfe6ff")
		m.emission_energy_multiplier = 2.5 if on else 0.25
	for n in _nodes:
		var p = n["panel"]
		if p and is_instance_valid(p) and p.has_method("set_glow"):
			p.set_glow(bool(n["out"]))

## Draws the ANSI schematic symbol for a gate type as glowing polylines,
## pointing "up" (inputs enter from below, output leaves the top).
func _draw_gate_symbol(type: String, at: Vector3, is_out: bool) -> void:
	var polys: Array = []
	match type:
		"and":
			# D-shape: flat bottom, straight sides, semicircle top
			var p := PackedVector3Array()
			p.append(Vector3(-0.45, -0.45, 0))
			p.append(Vector3(0.45, -0.45, 0))
			p.append(Vector3(0.45, 0.0, 0))
			for k in 11:
				var a := PI * float(k) / 10.0
				p.append(Vector3(cos(a) * 0.45, sin(a) * 0.45, 0))
			p.append(Vector3(-0.45, -0.45, 0))
			polys.append(p)
		"or":
			# curved back, sides sweeping to a point at the top
			var p := PackedVector3Array()
			for k in 9:
				var t := float(k) / 8.0
				p.append(Vector3(lerpf(-0.45, 0.45, t), -0.45 + sin(t * PI) * 0.18, 0))
			polys.append(p)
			var l := PackedVector3Array()
			for k in 9:
				var t := float(k) / 8.0
				l.append(Vector3(lerpf(-0.45, 0.0, t), lerpf(-0.45, 0.62, t) + sin(t * PI) * 0.14, 0))
			polys.append(l)
			var r := PackedVector3Array()
			for k in 9:
				var t := float(k) / 8.0
				r.append(Vector3(lerpf(0.45, 0.0, t), lerpf(-0.45, 0.62, t) + sin(t * PI) * 0.14, 0))
			polys.append(r)
		"xor":
			# OR with the extra detached input arc below
			_draw_gate_symbol("or", at, false)
			var p := PackedVector3Array()
			for k in 9:
				var t := float(k) / 8.0
				p.append(Vector3(lerpf(-0.45, 0.45, t), -0.62 + sin(t * PI) * 0.18, 0))
			polys.append(p)
		"not":
			# triangle + inversion bubble
			var p := PackedVector3Array()
			p.append(Vector3(-0.4, -0.45, 0))
			p.append(Vector3(0.4, -0.45, 0))
			p.append(Vector3(0.0, 0.35, 0))
			p.append(Vector3(-0.4, -0.45, 0))
			polys.append(p)
			var c := PackedVector3Array()
			for k in 13:
				var a := TAU * float(k) / 12.0
				c.append(Vector3(cos(a) * 0.11, 0.47 + sin(a) * 0.11, 0))
			polys.append(c)
	var col := Color("#ffd166") if is_out else Color("#dfe6ff")
	for poly in polys:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.6
		mat.albedo_color = col
		var mi := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for v in poly:
			im.surface_add_vertex(at + v)
		im.surface_end()
		mi.mesh = im
		add_child(mi)

## The little toggle block under each input panel.
class _InputSwitch extends StaticBody3D:
	var diagram: LogicDiagram
	var node_idx: int = 0
	var _mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("logic_input")
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.6, 0.6, 0.6)
		mi.mesh = m
		_mat = Destructible.make_material(Color("#333340"), 0.2)
		mi.material_override = _mat
		add_child(mi)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(0.7, 0.7, 0.7)
		col.shape = cs
		add_child(col)

	func use() -> void:
		if diagram and is_instance_valid(diagram):
			diagram.toggle(node_idx)
			var on: bool = bool(diagram._nodes[node_idx]["out"])
			_mat.emission = Color("#39ff88") if on else Color("#333340")
			_mat.emission_energy_multiplier = 3.0 if on else 0.2
