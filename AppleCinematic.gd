class_name AppleCinematic
extends Node3D
## The Permadeath Apple sendoff, feature length. The world pauses. Your
## dude eats the apple. The camera then TOURS the universe, planet by
## planet, watching each one detonate. Back on you: limbs pop, the head
## flies into a wormhole -- and the camera follows it in, through a
## shrieking psychedelic tunnel, out to a black screen that says dead.
## Then the save is erased. Runs on an unpausable clock, scored with sfx.

var _t: float = 0.0
var _cam: Camera3D
var _dude: Human
var _apple: MeshInstance3D
var _rig: Basis                 # player-aligned frame: no sideways cinema
var _origin: Vector3
var _drifting: Array = []
var _detached := {}
var _tour: Array = []           # bodies to visit and destroy, in order
var _tour_idx := -1
var _tour_boomed := false
var _worm: Node3D
var _worm_ring: MeshInstance3D
var _head: MeshInstance3D
var _tunnel: MeshInstance3D
var _in_tunnel := false
var _fade: ColorRect
var _dead_lbl: Label
var _title_btn: Button
var _done := false

# phase boundaries, computed once the tour size is known
var _tour_start := 2.4
var _tour_len := 0.0
var _back_at := 0.0
var _limbs_at := 0.0
var _worm_at := 0.0
var _head_at := 0.0
var _tunnel_at := 0.0
var _end_at := 0.0

const SHOT := 0.55   # seconds per planet execution

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.visible = false
		_rig = p.global_transform.basis.orthonormalized()
		_origin = p.global_position
	else:
		_rig = Basis.IDENTITY
	global_transform = Transform3D(_rig, _origin)

	for b in Universe.bodies:
		if not (b.kind in ["sun", "blackhole"]):
			_tour.append(b)
	_tour_len = _tour.size() * SHOT
	_back_at = _tour_start + _tour_len
	_limbs_at = _back_at + 1.2
	_worm_at = _limbs_at + 3.0
	_head_at = _worm_at + 0.5
	_tunnel_at = _head_at + 1.6
	_end_at = _tunnel_at + 4.5

	# your actual dude, standing where you stood, feet down YOUR down
	_dude = Human.new()
	add_child(_dude)
	_dude.position = Vector3(0, -1.0, 0)
	_dude.build(Color.html(str(Save.character.get("color", "3aa0ff"))),
		str(Save.character.get("shader", "none")), Save.loaded_paint())
	_dude.dress(Inventory.equip)

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
	_frame_dude()
	_cam.current = true

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

## Camera to its home shot: level with the dude, in the RIG frame.
func _frame_dude() -> void:
	_cam.global_position = _origin + _rig * Vector3(1.6, 0.7, -3.2)
	_cam.look_at(_origin + _rig.y * 0.6, _rig.y)

func _burst(at: Vector3, col: Color, size: float, amount: int) -> void:
	var parts := GPUParticles3D.new()
	parts.amount = amount
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 2.4
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

func _hide_body_node(bname: String) -> void:
	var cs := get_tree().current_scene
	for n in cs.get_children():
		if n is Node3D and n.has_meta("body_name") and str(n.get_meta("body_name")) == bname:
			n.visible = false

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
	_t += delta
	if _done:
		# epilogue: hold the black, then the door out fades slowly in
		if _t >= _end_at + 5.0 and _title_btn == null:
			_title_btn = Button.new()
			_title_btn.text = "Return to title"
			_title_btn.custom_minimum_size = Vector2(260, 52)
			_title_btn.set_anchors_preset(Control.PRESET_CENTER)
			_title_btn.position = Vector2(-130, 60)
			_title_btn.modulate = Color(1, 1, 1, 0.0)
			_title_btn.pressed.connect(func() -> void:
				Engine.time_scale = 1.0
				get_tree().change_scene_to_file("res://Title.tscn"))
			_fade.get_parent().add_child(_title_btn)
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED
		if _title_btn:
			_title_btn.modulate.a = minf(1.0, _title_btn.modulate.a + delta * 0.35)
		return

	# --- act 1: the bite (0 - 2.4) ---
	if _t < 2.0 and _apple.visible:
		var k := clampf(_t / 1.6, 0.0, 1.0)
		_apple.position = Vector3(0.6, 0.35, -0.15).lerp(Vector3(0.16, 1.25, -0.3), k)
		if _dude and is_instance_valid(_dude._arm_r):
			_dude._arm_r.rotation_degrees.x = lerpf(0.0, -130.0, k)
	elif _t >= 2.0 and _apple.visible:
		_apple.visible = false
		_burst(_apple.global_position, Color("#8b0000"), 3.0, 40)
		Sfx.play("eat")
		Sfx.play("denied", -6.0)   # the universe notices

	# --- act 2: the tour. every planet gets a close-up and a funeral ---
	if _t >= _tour_start and _t < _back_at:
		var idx := int((_t - _tour_start) / SHOT)
		var local := fmod(_t - _tour_start, SHOT)
		if idx != _tour_idx and idx < _tour.size():
			_tour_idx = idx
			_tour_boomed = false
			var b = _tour[idx]
			# hard cut: camera arrives at the doomed world
			var off: Vector3 = Vector3(0.8, 0.35, 0.6).normalized() * b.radius * 3.4
			_cam.global_position = b.center + off
			_cam.look_at(b.center, Vector3.UP)
		if _tour_idx >= 0 and _tour_idx < _tour.size():
			var b2 = _tour[_tour_idx]
			if not _tour_boomed and local >= 0.18:
				_tour_boomed = true
				_burst(b2.center, b2.color, b2.radius * 2.0, 200)
				_hide_body_node(b2.name)
				Sfx.play("explode", randf_range(-6.0, 0.0))
			# slow push-in while it burns
			_cam.global_position = _cam.global_position.lerp(b2.center, delta * 0.25)

	# --- act 3: back on you, alone now (no more planets) ---
	if _t >= _back_at and _t < _back_at + 0.1 and _tour_idx != -999:
		_tour_idx = -999
		_frame_dude()
		Sfx.play("warp", -10.0)

	if _dude and is_instance_valid(_dude):
		if _t >= _limbs_at:
			_detach(_dude._arm_l, _rig * Vector3(-0.8, 0.3, 0.2), 0.9)
		if _t >= _limbs_at + 0.7:
			_detach(_dude._arm_r, _rig * Vector3(0.8, 0.4, -0.1), 0.9)
		if _t >= _limbs_at + 1.4:
			_detach(_dude._leg_l, _rig * Vector3(-0.4, -0.7, 0.3), 0.9)
		if _t >= _limbs_at + 2.1:
			_detach(_dude._leg_r, _rig * Vector3(0.5, -0.6, -0.2), 0.9)

	# --- act 4: the wormhole opens, the head answers ---
	if _t >= _worm_at and _worm == null:
		_worm = Node3D.new()
		add_child(_worm)
		_worm.global_position = _origin + _rig * Vector3(0, 0.6, -7.0)
		_worm.global_transform.basis = _rig
		_worm_ring = MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = 0.9
		wm.outer_radius = 1.25
		_worm_ring.mesh = wm
		_worm_ring.rotation_degrees = Vector3(90, 0, 0)
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
		Sfx.play("warp", -4.0)
	if _worm and not _in_tunnel:
		_worm.scale = _worm.scale.lerp(Vector3.ONE, delta * 6.0)
		if _worm_ring:
			_worm_ring.rotate_y(delta * 5.0)

	if _t >= _head_at and _head == null and _dude and is_instance_valid(_dude._head_m):
		_head = _dude._head_m
		var tf := _head.global_transform
		_head.get_parent().remove_child(_head)
		add_child(_head)
		_head.global_transform = tf
		Sfx.play("explode", -12.0)
	if _head and is_instance_valid(_head) and _worm and not _in_tunnel:
		var target: Vector3 = _worm.global_position
		_head.global_position = _head.global_position.lerp(target, delta * 2.0)
		_head.rotate_y(delta * 8.0)
		# the camera gives chase: behind the head, flying with it
		var chase: Vector3 = _head.global_position - _rig.z * -3.0 + _rig.y * 0.7
		_cam.global_position = _cam.global_position.lerp(chase, delta * 3.0)
		_cam.look_at(_head.global_position, _rig.y)

	# --- act 5: THROUGH. the trip (psychedelic tunnel, camera inside) ---
	if _t >= _tunnel_at and not _in_tunnel:
		_in_tunnel = true
		Sfx.play("warp", 0.0)
		Sfx.alien_engine(true)
		if _worm:
			_worm.visible = false
		var tube := CylinderMesh.new()
		tube.top_radius = 7.0
		tube.bottom_radius = 7.0
		tube.height = 500.0
		tube.radial_segments = 32
		tube.cap_top = false
		tube.cap_bottom = false
		_tunnel = MeshInstance3D.new()
		_tunnel.mesh = tube
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, cull_front;
varying vec3 vp;
void vertex(){ vp = VERTEX; }
void fragment(){
	float ang = atan(vp.x, vp.z);
	float hue = fract(ang / 6.2831 + vp.y * 0.02 - TIME * 0.7);
	float bands = sin(vp.y * 0.6 - TIME * 16.0 + ang * 4.0) * 0.5 + 0.5;
	float pulse = sin(TIME * 9.0 + vp.y * 0.15) * 0.5 + 0.5;
	vec3 rainbow = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	ALBEDO = rainbow * (0.3 + bands);
	EMISSION = rainbow * (0.8 + bands * 2.0 + pulse * 1.2);
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_tunnel.material_override = mat
		add_child(_tunnel)
		# tube axis = camera forward: we are INSIDE, flying
		_tunnel.global_position = _cam.global_position + _rig.z * -180.0
		_tunnel.global_transform.basis = Basis(_rig.x, _rig.z, -_rig.y).orthonormalized()
		if _head and is_instance_valid(_head):
			_head.global_position = _cam.global_position + _rig.z * -8.0
			_head.scale = Vector3.ONE
	if _in_tunnel and _t < _end_at:
		# fly, roll, chase the head deeper. maximum trip.
		_cam.global_position += _rig.z * -22.0 * delta
		_cam.rotation += Vector3(0, 0, delta * 0.9)
		if _head and is_instance_valid(_head):
			_head.global_position += _rig.z * -23.0 * delta
			_head.rotate_x(delta * 6.0)
			_head.rotate_y(delta * 4.0)
			_cam.look_at(_head.global_position, _cam.global_transform.basis.y)
		if _tunnel:
			_tunnel.global_position += _rig.z * -22.0 * delta   # endless

	# drifting limbs
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

	# --- the end. ---
	if _t >= _end_at:
		Sfx.alien_engine(false)
		_fade.color.a = minf(1.0, _fade.color.a + delta * 1.2)
		_dead_lbl.modulate.a = minf(1.0, _dead_lbl.modulate.a + delta * 0.8)
	if _t >= _end_at + 2.3 and not _done:
		_done = true
		_fade.color.a = 1.0
		_dead_lbl.modulate.a = 1.0
		get_tree().paused = false
		Game.permadeath()   # now it's official
