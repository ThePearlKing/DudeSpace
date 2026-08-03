class_name AppleCinematic
extends Node3D
## The Permadeath Apple, given the sendoff it deserves. The world pauses.
## Your dude eats the apple. Every planet in the universe detonates. Back
## on you, drifting in the void: limbs pop off one by one and burst, the
## head sails into a wormhole, and the screen says dead. THEN the save is
## erased. All hand-animated on an unpausable clock.

var _t: float = 0.0
var _cam: Camera3D
var _dude: Human
var _apple: MeshInstance3D
var _drifting: Array = []      # [{node, vel, spin, pop_at, popped}]
var _worm: Node3D
var _worm_ring: MeshInstance3D
var _head: MeshInstance3D
var _fade: ColorRect
var _dead_lbl: Label
var _planets_blown := false
var _detached := {}            # limb name -> true
var _done := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

	var p = get_tree().get_first_node_in_group("player")
	var base: Transform3D = p.global_transform if p else Transform3D()
	if p:
		p.visible = false
	global_transform = base

	# the star of the show: your actual dude
	_dude = Human.new()
	add_child(_dude)
	_dude.position = Vector3(0, -1.0, 0)
	_dude.build(Color.html(str(Save.character.get("color", "3aa0ff"))),
		str(Save.character.get("shader", "none")), Save.loaded_paint())
	_dude.dress(Inventory.equip)

	# the apple, in hand
	_apple = MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 0.16
	am.height = 0.3
	_apple.mesh = am
	_apple.material_override = Destructible.make_material(Color("#8b0000"), 1.4)
	add_child(_apple)
	_apple.position = Vector3(0.6, 0.35, -0.15)

	_cam = Camera3D.new()
	_cam.far = 90000.0
	add_child(_cam)
	_cam.position = Vector3(1.6, 0.9, -3.2)
	_cam.look_at_from_position(global_position + global_transform.basis * _cam.position,
		global_position + global_transform.basis.y * 0.8)
	_cam.current = true

	# the end-card, hidden until the end
	var ui := CanvasLayer.new()
	ui.layer = 40
	add_child(ui)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)
	_dead_lbl = Label.new()
	_dead_lbl.text = "dead"
	_dead_lbl.add_theme_font_size_override("font_size", 90)
	_dead_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_dead_lbl.position = Vector2(-110, -60)
	_dead_lbl.modulate = Color(0.7, 0.05, 0.05, 0.0)
	ui.add_child(_dead_lbl)

func _burst(at: Vector3, col: Color, size: float, amount: int) -> void:
	var parts := GPUParticles3D.new()
	parts.amount = amount
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 2.2
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = size * 0.4
	pm.initial_velocity_max = size * 1.3
	pm.gravity = Vector3.ZERO
	pm.scale_min = size * 0.01
	pm.scale_max = size * 0.05
	pm.color = col
	parts.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = Destructible.make_material(col, 3.0)
	parts.draw_pass_1 = mesh
	add_child(parts)
	parts.global_position = at
	parts.emitting = true

## Pull a limb off the dude, keep its world pose, let it drift.
func _detach(mi: MeshInstance3D, kick: Vector3, pop_delay: float) -> void:
	if mi == null or not is_instance_valid(mi) or _detached.has(mi):
		return
	_detached[mi] = true
	var tf := mi.global_transform
	mi.get_parent().remove_child(mi)
	add_child(mi)
	mi.global_transform = tf
	_drifting.append({"node": mi, "vel": kick, "spin": Vector3(randf_range(-3, 3),
		randf_range(-3, 3), randf_range(-3, 3)), "pop_at": _t + pop_delay, "popped": false})

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta

	# --- act 1: raise the apple, bite (0 - 2.2s) ---
	if _t < 2.0 and _apple.visible:
		var k := clampf(_t / 1.6, 0.0, 1.0)
		# apple travels hand -> mouth
		_apple.position = Vector3(0.6, 0.35, -0.15).lerp(Vector3(0.16, 1.25, -0.3), k)
		if _dude and is_instance_valid(_dude._arm_r):
			_dude._arm_r.rotation_degrees.x = lerpf(0.0, -130.0, k)
	elif _t >= 2.0 and _apple.visible:
		_apple.visible = false
		_burst(_apple.global_position, Color("#8b0000"), 3.0, 40)
		Sfx.play("eat")

	# --- act 2: the universe answers (2.8s) ---
	if _t >= 2.8 and not _planets_blown:
		_planets_blown = true
		Sfx.play("explode", 0.0)
		for b in Universe.bodies:
			if b.kind in ["sun", "blackhole"]:
				continue   # stars mourn; the hole does not care
			_burst(b.center, b.color, b.radius * 2.0, 200)
		var cs := get_tree().current_scene
		for n in cs.get_children():
			if n is Node3D and n.has_meta("body_name"):
				var bn = Universe.body_named(str(n.get_meta("body_name")))
				if bn and not (bn.kind in ["sun", "blackhole"]):
					n.visible = false
	# camera drinks it in: slow pan up during the fireworks
	if _t >= 2.8 and _t < 6.0:
		_cam.global_transform = _cam.global_transform.looking_at(
			global_position + global_transform.basis.y * (0.8 + (_t - 2.8) * 8.0),
			global_transform.basis.y)
	elif _t >= 6.0 and _t < 6.1:
		# --- act 3: back on you, alone in the dark ---
		_cam.look_at(global_position + global_transform.basis.y * 0.5, global_transform.basis.y)

	# limbs, on schedule
	if _dude and is_instance_valid(_dude):
		var B := global_transform.basis
		if _t >= 6.4:
			_detach(_dude._arm_l, B * Vector3(-0.8, 0.3, 0.2), 0.9)
		if _t >= 7.1:
			_detach(_dude._arm_r, B * Vector3(0.8, 0.4, -0.1), 0.9)
		if _t >= 7.8:
			_detach(_dude._leg_l, B * Vector3(-0.4, -0.7, 0.3), 0.9)
		if _t >= 8.5:
			_detach(_dude._leg_r, B * Vector3(0.5, -0.6, -0.2), 0.9)

	# --- act 4: the wormhole (9.4s), the head (9.9s) ---
	if _t >= 9.4 and _worm == null:
		_worm = Node3D.new()
		add_child(_worm)
		_worm.position = Vector3(0, 1.6, -6.0)
		_worm_ring = MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = 0.9
		wm.outer_radius = 1.25
		_worm_ring.mesh = wm
		_worm_ring.material_override = Destructible.make_material(Color("#b56cff"), 3.5)
		_worm.add_child(_worm_ring)
		var core := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.95
		cm.bottom_radius = 0.95
		cm.height = 0.05
		core.mesh = cm
		core.rotation_degrees = Vector3(90, 0, 0)
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color(0, 0, 0)
		core.material_override = cmat
		_worm.add_child(core)
		_worm.scale = Vector3.ONE * 0.01
	if _worm:
		_worm.scale = _worm.scale.lerp(Vector3.ONE if _t < 11.6 else Vector3.ONE * 0.01, delta * 6.0)
		if _worm_ring:
			_worm_ring.rotate_z(delta * 5.0)
	if _t >= 9.9 and _head == null and _dude and is_instance_valid(_dude._head_m):
		_head = _dude._head_m
		var tf := _head.global_transform
		_head.get_parent().remove_child(_head)
		add_child(_head)
		_head.global_transform = tf
		Sfx.play("explode", -14.0)
	if _head and is_instance_valid(_head) and _worm:
		var target := _worm.global_position
		_head.global_position = _head.global_position.lerp(target, delta * 2.2)
		_head.rotate_y(delta * 8.0)
		_head.scale = _head.scale.lerp(Vector3.ONE * 0.05, delta * 1.5)
		if _head.global_position.distance_to(target) < 0.3:
			_head.visible = false

	# drifting limbs: float, spin, pop
	for e in _drifting:
		var n = e["node"]
		if not is_instance_valid(n) or e["popped"]:
			continue
		n.global_position += e["vel"] * delta
		n.rotation += e["spin"] * delta
		if _t >= e["pop_at"]:
			e["popped"] = true
			_burst(n.global_position, Color("#c04040"), 2.0, 30)
			Sfx.play("explode", -16.0)
			n.visible = false

	# --- act 5: dead. (12.2s) ---
	if _t >= 12.2:
		_fade.color.a = minf(1.0, _fade.color.a + delta * 1.2)
		_dead_lbl.modulate.a = minf(1.0, _dead_lbl.modulate.a + delta * 0.8)
	if _t >= 14.5:
		_done = true
		get_tree().paused = false
		Game.permadeath()   # now it's official
