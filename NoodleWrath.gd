class_name NoodleWrath
extends Node3D
## MAX WRATH: the noodle god itself descends. A building-sized mass of
## writhing noodles with eyes, coming straight down at YOU. Appease the
## gods (wrath below 40) and it withdraws; let it reach you and you are
## the hypotenuse now.

const FALL_SPEED := 14.0
const CATCH_DIST := 40.0

var _tendrils: Array = []   # [{node, phase, base}]
var _t: float = 0.0
var _rumble_t: float = 0.0
var _retreating: bool = false

func _ready() -> void:
	# the core: a colossal pale meatball
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 55.0
	cm.height = 110.0
	core.mesh = cm
	core.material_override = Destructible.make_material(Color("#e8cf9a"), 0.4)
	add_child(core)
	# two vast red eyes
	for sx in [-22.0, 22.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 7.0
		em.height = 14.0
		e.mesh = em
		e.material_override = Destructible.make_material(Color("#ff2b2b"), 6.0)
		e.position = Vector3(sx, -12, -48)
		add_child(e)
	# hanging noodle tendrils: segmented, they writhe
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * 38.0, -35.0, sin(ang) * 38.0)
		add_child(root)
		var y := 0.0
		for k in 6:
			var seg := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 6.5 - float(k) * 0.7
			sm.bottom_radius = 6.0 - float(k) * 0.7
			sm.height = 34.0
			seg.mesh = sm
			seg.material_override = Destructible.make_material(Color("#f0d9a8"), 0.3)
			seg.position = Vector3(0, y - 17.0, 0)
			root.add_child(seg)
			y -= 32.0
		_tendrils.append({"node": root, "phase": randf() * TAU})

func _process(delta: float) -> void:
	_t += delta
	# noodles writhe
	for td in _tendrils:
		var n: Node3D = td["node"]
		n.rotation.x = sin(_t * 0.8 + float(td["phase"])) * 0.18
		n.rotation.z = cos(_t * 0.6 + float(td["phase"])) * 0.18
	var p := get_tree().get_first_node_in_group("player")
	if p == null or Game.dead:
		queue_free()
		return
	# appeasement: wrath calmed -> it withdraws into the sky
	if not _retreating and Game.wrath < 40.0:
		_retreating = true
	var dir: Vector3
	if _retreating:
		dir = (global_position - p.global_position).normalized()
		global_position += dir * FALL_SPEED * 3.0 * delta
		if global_position.distance_to(p.global_position) > 1500.0:
			Game.wrath_event_over(false)
			queue_free()
		return
	# descend on the trespasser. slowly. inevitably.
	dir = (p.global_position - global_position).normalized()
	global_position += dir * FALL_SPEED * delta
	look_at(p.global_position, Vector3.UP)
	_rumble_t -= delta
	if _rumble_t <= 0.0:
		_rumble_t = 1.6
		Sfx.play_at("rumble", global_position, 8.0)
	if global_position.distance_to(p.global_position) < CATCH_DIST:
		Game.wrath_event_over(true)
		queue_free()
