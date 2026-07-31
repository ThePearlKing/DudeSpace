class_name NoodleGod
extends Node3D
## A colossal megalophobia structure: a towering monolith crowned by a
## writhing "noodle". Loitering near it without destroying enrages the
## destruction gods (Game.wrath). Built in local space (local +Y = up).

const INFLUENCE := 70.0
const REVEAL_AT := 0.6   # gods stay invisible until wrath passes 60%

var _noodle: Array[Node3D] = []
var _mats: Array[StandardMaterial3D] = []
var _base_emit: Array[float] = []
var _label: Label3D

func build() -> void:
	# monolith
	var mono := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14, 90, 14)
	mono.mesh = bm
	mono.position = Vector3(0, 45, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#0b0b12")
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color("#6a0f6a")
	mat.emission_energy_multiplier = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mono.material_override = mat
	add_child(mono)
	_mats.append(mat)
	_base_emit.append(0.5)

	# the noodle: stacked spheres towering higher
	for i in 26:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 5.0
		sm.height = 10.0
		s.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ffcf40")
		m.emission_enabled = true
		m.emission = Color("#ff8c1a")
		m.emission_energy_multiplier = 0.8
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.material_override = m
		s.position = Vector3(0, 92 + float(i) * 6.0, 0)
		add_child(s)
		_noodle.append(s)
		_mats.append(m)
		_base_emit.append(0.8)

	# no label. you'll know it when you see it. (director's orders)

var _t: float = 0.0

func _process(delta: float) -> void:
	# Reveal with anger: fully invisible below 60% wrath, fading in above.
	var w := Game.wrath / Game.WRATH_MAX
	var vis := clampf((w - REVEAL_AT) / (1.0 - REVEAL_AT), 0.0, 1.0)
	visible = vis > 0.0
	if not visible:
		return
	for i in _mats.size():
		var m := _mats[i]
		m.albedo_color.a = vis
		m.emission_energy_multiplier = _base_emit[i] * vis

	# writhe
	_t += delta
	for i in _noodle.size():
		var n := _noodle[i]
		n.position.x = sin(_t * 1.3 + float(i) * 0.5) * (2.0 + float(i) * 0.5)
		n.position.z = cos(_t * 1.1 + float(i) * 0.4) * (2.0 + float(i) * 0.5)

	# anger the gods if something living lingers close
	var p := get_tree().get_first_node_in_group("player")
	var near := false
	if p and Game.mode == Game.Mode.ON_FOOT and is_instance_valid(p):
		near = global_position.distance_to(p.global_position) < INFLUENCE
	var r := get_tree().get_first_node_in_group("rocket")
	if r and Game.mode == Game.Mode.IN_ROCKET and is_instance_valid(r):
		near = near or global_position.distance_to(r.global_position) < INFLUENCE
	if near:
		Game.report_mega()
