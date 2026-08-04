class_name WthStudio
extends Node3D
## The WTH talk-radio station, in the flesh: a mine-style hole on Wth's
## surface with a transmitter pole beside it, leading down to a studio
## pocket where four floating icosahedron aliens run the show LIVE --
## voices clear, no static, bodies swelling with their own volume.
## A TV on the back wall cuts between cameras around the world based on
## what they're talking about; when the topic is the humans, an Earth
## camera pivots onto one and ZOOMS. When they're talking about nothing
## much -- or about the listener -- the TV shows YOU, in the room, the
## shot creeping around you. An escape portal hides in the corner.

const POS := Vector3(-26000, 34000, 22000)   # pocket coords, far from houses

var _talk: AudioStreamPlayer3D
var _aliens: Array = []        # [{node, mat, base_y, host}]
var _turns: Array = []         # queued [host_idx, wav]
var _cur_host: int = -1
var _cooking := false
var _tv_cam: Camera3D
var _tv_vp: SubViewport
var _tv_mode := "player"       # "planet" | "humans" | "player"
var _tv_planet := ""
var _t := 0.0
var _human_pick_t := 0.0
var _human_target: Node3D = null
var _next_seg_t := 2.0

func _ready() -> void:
	_build_surface()
	_build_studio()

## ---- the way in: a dug-out hole + the transmitter pole ----
func _build_surface() -> void:
	var wth = Universe.body_named("Wth")
	if wth == null:
		return
	var dir := Vector3(0.3, 0.9, 0.2).normalized()
	var base: Vector3 = wth.center + dir * float(wth.radius)
	var bs := _basis_up(dir)
	# the pit: a dark ring you climb down into, mine-entrance style
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(1.6, 0.9, 0.8)
		rim.mesh = rb
		rim.material_override = Surfaces.stone(Color("#1a2a24"))
		add_child(rim)
		rim.global_transform = Transform3D(bs, base + bs * Vector3(cos(ang) * 2.4, 0.25, sin(ang) * 2.4))
		rim.rotate_object_local(Vector3.UP, -ang)
	var pit := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 2.2
	pm.bottom_radius = 1.6
	pm.height = 2.4
	pit.mesh = pm
	pit.material_override = Surfaces.stone(Color("#050908"))
	add_child(pit)
	pit.global_transform = Transform3D(bs, base - dir * 1.0)
	var gate := Gate.new().configure({
		"target": POS + Vector3(0, -1.6, 5.0), "zone": "flat", "zone_g": 9.0,
		"label": "STATION WTH", "color": Color("#33ff99")})
	add_child(gate)
	gate.global_transform = Transform3D(bs, base - dir * 0.4)
	# the TRANSMITTER: a proper mast beside the hole, lamp blinking
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.07
	mm.bottom_radius = 0.16
	mm.height = 11.0
	mast.mesh = mm
	mast.material_override = Surfaces.metal(Color("#8a9098"))
	add_child(mast)
	mast.global_transform = Transform3D(bs, base + bs * Vector3(4.5, 5.5, 0))
	for hy in [3.0, 5.5, 8.0]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4 - hy * 0.15, 0.09, 0.09)
		bar.mesh = bm
		bar.material_override = Surfaces.metal(Color("#6a7078"))
		add_child(bar)
		bar.global_transform = Transform3D(bs, base + bs * Vector3(4.5, hy, 0))
	_beacon = MeshInstance3D.new()
	var bem := SphereMesh.new()
	bem.radius = 0.16
	bem.height = 0.32
	_beacon.mesh = bem
	_beacon_mat = Destructible.make_material(Color("#ff3030"), 3.0)
	_beacon.material_override = _beacon_mat
	add_child(_beacon)
	_beacon.global_transform = Transform3D(bs, base + bs * Vector3(4.5, 11.2, 0))

var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D

func _basis_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized() * -1.0).orthonormalized()

## ---- the studio pocket ----
func _build_studio() -> void:
	var size := Vector3(22, 6, 16)
	var half := size * 0.5
	for w in [[Vector3(size.x, 1, size.z), Vector3(0, -half.y, 0)],
			[Vector3(size.x, 1, size.z), Vector3(0, half.y, 0)],
			[Vector3(1, size.y, size.z), Vector3(-half.x, 0, 0)],
			[Vector3(1, size.y, size.z), Vector3(half.x, 0, 0)],
			[Vector3(size.x, size.y, 1), Vector3(0, 0, -half.z)],
			[Vector3(size.x, size.y, 1), Vector3(0, 0, half.z)]]:
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = w[0]
		mi.mesh = m
		mi.material_override = Surfaces.metal(Color("#10221c"))
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = w[0]
		col.shape = cs
		body.add_child(col)
		add_child(body)
		body.global_position = POS + w[1]
	var light := OmniLight3D.new()
	light.light_energy = 1.3
	light.light_color = Color("#7dffc8")
	light.omni_range = 26.0
	add_child(light)
	light.global_position = POS + Vector3(0, 2.2, 0)
	# the news DESK: long curved-ish counter the anchors float behind
	var desk := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(9.0, 1.1, 1.6)
	desk.mesh = dm
	desk.material_override = Surfaces.metal(Color("#1c3a30"))
	add_child(desk)
	desk.global_position = POS + Vector3(0, -2.35, -3.0)
	# the ANCHORS: four floating icosahedron-ish gems, fluid-glow skins
	for i in 4:
		var a := MeshInstance3D.new()
		var am := SphereMesh.new()
		am.radius = 0.65
		am.height = 1.3
		am.radial_segments = 5
		am.rings = 3
		a.mesh = am
		var mat := _fluid_material([Color("#33ff99"), Color("#ffcf40"),
			Color("#b388ff"), Color("#ff6a6a")][i])
		a.material_override = mat
		add_child(a)
		a.global_position = POS + Vector3(-4.5 + float(i) * 3.0, -0.6, -4.2)
		_aliens.append({"node": a, "mat": mat,
			"base": a.global_position, "phase": randf() * TAU})
	# the TV: bezel + live screen on the back wall
	var bez := MeshInstance3D.new()
	var bzm := BoxMesh.new()
	bzm.size = Vector3(6.6, 3.9, 0.3)
	bez.mesh = bzm
	bez.material_override = Surfaces.metal(Color("#0a1410"))
	add_child(bez)
	bez.global_position = POS + Vector3(0, 0.6, -7.6)
	_tv_vp = SubViewport.new()
	_tv_vp.size = Vector2i(360, 220)
	_tv_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_tv_vp)
	_tv_vp.world_3d = get_viewport().world_3d if get_viewport() else null
	_tv_cam = Camera3D.new()
	_tv_vp.add_child(_tv_cam)
	var scr := MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2(6.0, 3.4)
	scr.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_texture = _tv_vp.get_texture()
	smat.emission_enabled = true
	smat.emission_texture = _tv_vp.get_texture()
	smat.emission_energy_multiplier = 0.8
	scr.material_override = smat
	add_child(scr)
	scr.global_position = POS + Vector3(0, 0.6, -7.42)
	# props: server racks + a sagging cable
	for rx in [-9.0, 9.0]:
		var rack := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(1.4, 3.2, 1.0)
		rack.mesh = rm
		rack.material_override = Surfaces.metal(Color("#152a22"))
		add_child(rack)
		rack.global_position = POS + Vector3(rx, -1.3, -6.4)
	# the ESCAPE PORTAL: tucked dark in a corner, no label, no ceremony
	var wth = Universe.body_named("Wth")
	if wth != null:
		var dir := Vector3(0.3, 0.9, 0.2).normalized()
		var out := Gate.new().configure({
			"target": wth.center + dir * (float(wth.radius) + 2.0),
			"zone": "", "label": "", "color": Color("#0a2a1e")})
		add_child(out)
		out.global_position = POS + Vector3(half.x - 1.4, -2.6, half.z - 1.2)
	_talk = AudioStreamPlayer3D.new()
	_talk.unit_size = 14.0
	_talk.max_distance = 60.0
	add_child(_talk)
	_talk.global_position = POS + Vector3(0, -0.5, -4.0)

## The fluid glow: the boiling fbm skin the user saved for later. Later
## is now. Per-anchor hue.
func _fluid_material(col: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 vpos;
uniform vec3 tint = vec3(0.2, 1.0, 0.6);
uniform float amp = 1.0;
float hash31(vec3 p) { p = fract(p * 0.3183 + vec3(0.1, 0.2, 0.3)); p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i), b = hash31(i + vec3(1,0,0)), c = hash31(i + vec3(0,1,0)), d = hash31(i + vec3(1,1,0));
	float e = hash31(i + vec3(0,0,1)), g = hash31(i + vec3(1,0,1)), h = hash31(i + vec3(0,1,1)), k = hash31(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y), mix(mix(e,g,f.x), mix(h,k,f.x), f.y), f.z); }
float fbm3(vec3 p) { return vnoise(p) * 0.6 + vnoise(p * 2.3) * 0.4; }
void vertex() { vpos = VERTEX; }
void fragment() {
	float t = TIME;
	float sw = fbm3(vpos * 4.0 + vec3(t * 0.5, t * 0.35, t * 0.2));
	float ring = sin(sw * 12.0 - t * 2.2) * 0.5 + 0.5;
	ALBEDO = tint * 0.2;
	EMISSION = tint * (0.4 + 1.6 * pow(ring, 2.0) + sw * 0.5) * amp;
	ROUGHNESS = 0.3;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	return mat

## ---- the live show ----
func _process(delta: float) -> void:
	_t += delta
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 3.0 if fmod(_t, 1.2) < 0.6 else 0.3
	var p = get_tree().get_first_node_in_group("player")
	var here: bool = p != null and p.global_position.distance_to(POS) < 40.0
	if _tv_vp != null:
		_tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if here \
			else SubViewport.UPDATE_DISABLED
	if not here:
		return
	# the show never stops: queue segments, play turn by turn
	if _turns.is_empty() and not _talk.playing:
		_next_seg_t -= delta
		if _next_seg_t <= 0.0 and not _cooking:
			_cooking = true
			var ex := RadioLib.alien_exchange()
			_apply_topic(RadioLib.last_alien_meta)
			WorkerThreadPool.add_task(func() -> void:
				var cooked: Array = []
				for turn in ex:
					var w = HumanVoice.render(str(turn[1]),
						RadioLib.ALIEN_HOSTS[int(turn[0])])
					if w != null:
						cooked.append([int(turn[0]), w])
				_deliver.call_deferred(cooked))
	if not _talk.playing and not _turns.is_empty():
		var t0: Array = _turns.pop_front()
		_cur_host = int(t0[0])
		_talk.stream = t0[1]
		_talk.play()
	if not _talk.playing and _turns.is_empty():
		_cur_host = -1
	# anchors: float, bob, and SWELL with their own voice
	for i in _aliens.size():
		var a: Dictionary = _aliens[i]
		var n: Node3D = a["node"]
		n.global_position = a["base"] + Vector3(0,
			sin(_t * 1.1 + float(a["phase"])) * 0.22, 0)
		n.rotate_y(delta * 0.6)
		var talking: bool = i == _cur_host and _talk.playing
		var target_s: float = 1.0
		if talking:
			target_s = 1.0 + 0.35 * absf(sin(_t * 9.0)) + 0.15 * absf(sin(_t * 23.0))
		n.scale = n.scale.lerp(Vector3.ONE * target_s, delta * 10.0)
		(a["mat"] as ShaderMaterial).set_shader_parameter("amp",
			1.6 if talking else 0.8)
	_drive_tv(delta, p)

func _deliver(cooked: Array) -> void:
	_cooking = false
	_turns = cooked
	_next_seg_t = randf_range(3.0, 6.0)

func _apply_topic(meta: Dictionary) -> void:
	var topic := int(meta.get("topic", -1))
	_tv_planet = str(meta.get("planet", ""))
	if topic == 9:
		_tv_mode = "humans"
		_human_target = null
	elif topic in [0, 2, 3, 5, 7] and _tv_planet != "":
		_tv_mode = "planet"
		var b = Universe.body_named(_tv_planet)
		if b != null and _tv_cam != null:
			var off := Vector3(1, 0.4, 0.7).normalized() * (float(b.radius) * 2.6)
			_tv_cam.global_position = b.center + off
			_tv_cam.look_at(b.center, Vector3.UP)
			_tv_cam.fov = 50.0
	else:
		# markets, ads, fourth wall, nothing much: the camera is HERE,
		# in the room, and it is looking at YOU
		_tv_mode = "player"

func _drive_tv(delta: float, p: Node3D) -> void:
	if _tv_cam == null:
		return
	match _tv_mode:
		"humans":
			# an Earth camera pivots onto some human and ZOOMS. rude.
			_human_pick_t -= delta
			if _human_target == null or not is_instance_valid(_human_target) \
					or _human_pick_t <= 0.0:
				_human_pick_t = 5.0
				var best: Node3D = null
				for h in get_tree().get_nodes_in_group("earth_human"):
					if h is Node3D and is_instance_valid(h):
						best = h
						if randf() < 0.3:
							break
				_human_target = best
			if _human_target != null and is_instance_valid(_human_target):
				var up := (_human_target.global_position \
					- Universe.body_named("Earth").center).normalized()
				_tv_cam.global_position = _human_target.global_position \
					+ up * 9.0 + Vector3(3, 0, 2)
				_tv_cam.look_at(_human_target.global_position, up)
				_tv_cam.fov = lerpf(_tv_cam.fov, 22.0, delta * 0.8)
		"player":
			if p != null:
				var orb := _t * 0.5
				_tv_cam.global_position = POS + Vector3(cos(orb) * 6.0,
					1.0 + sin(_t * 0.7) * 1.2, sin(orb) * 5.0)
				_tv_cam.look_at(p.global_position + Vector3(0, 0.8, 0), Vector3.UP)
				_tv_cam.fov = 42.0 + 18.0 * sin(_t * 0.35)
		_:
			pass   # planet shot is parked where _apply_topic left it
