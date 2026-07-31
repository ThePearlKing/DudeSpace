class_name ShadowMonster
extends Node3D
## A horror you can't quite see. Drifts toward you in the shadow temple;
## touch it and it locks you in the SHADOW REALM.

var _t: float = 0.0
var _mat: StandardMaterial3D
var home: Vector3 = Vector3.INF     # temple centre; monsters can't leave
const ROAM := Vector3(42.0, 6.5, 42.0)   # half-extent of allowed box
var _atk_t: float = 0.0
var _wander: Vector3 = Vector3.ZERO
var _wander_t: float = 0.0

func _ready() -> void:
	add_to_group("shadow_monster")
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.8
	m.height = 3.2
	mi.mesh = m
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.02, 0.0, 0.05, 0.22)   # barely there
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color("#12001e")
	_mat.emission_energy_multiplier = 0.4
	mi.material_override = _mat
	add_child(mi)
	# two dim eyes
	for sx in [-0.22, 0.22]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.07
		em.height = 0.14
		e.mesh = em
		e.material_override = Destructible.make_material(Color("#4a0a2a"), 1.2)
		e.position = Vector3(sx, 1.2, -0.6)
		add_child(e)

func _process(delta: float) -> void:
	_t += delta
	# flicker in and out of visibility
	_mat.albedo_color.a = 0.06 + 0.18 * absf(sin(_t * 0.7))
	var p := get_tree().get_first_node_in_group("player")
	if p == null or Game.mode != Game.Mode.ON_FOOT or Game.dead:
		return
	_atk_t -= delta
	var d: float = global_position.distance_to(p.global_position)
	if d < 70.0 and d > 2.6:
		# each monster stalks its OWN drifting point near you, so the
		# pack spreads out and comes from different directions
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 5.0)
			_wander = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		var tgt: Vector3 = p.global_position + (_wander if d > 8.0 else Vector3.ZERO)
		var dir: Vector3 = (tgt - global_position).normalized()
		# personal space: shadows repel shadows
		for m in get_tree().get_nodes_in_group("shadow_monster"):
			if m != self and is_instance_valid(m):
				var md: float = global_position.distance_to(m.global_position)
				if md < 7.0 and md > 0.01:
					dir += (global_position - m.global_position).normalized() * (7.0 - md) * 0.25
		dir = dir.normalized()
		global_position += dir * 5.6 * delta
		look_at(p.global_position, Vector3.UP)
	elif d <= 2.6 and _atk_t <= 0.0:
		# a cold swipe from the dark. two swipes and you're basically done.
		_atk_t = 0.8
		Game.hurt(40.0)
		if "vel" in p:
			p.vel += (p.global_position - global_position).normalized() * 6.0 + Vector3(0, 3, 0)
	# monsters are BOUND to the temple: never past its walls
	if home != Vector3.INF:
		global_position = global_position.clamp(home - ROAM, home + ROAM)
