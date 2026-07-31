extends Node3D
## Builds the whole universe in code: every planet (with its shader or
## material), its content, the player + rocket, and all UI. Runs the two
## global rules each frame: the universe-edge throwback and TIN 618's
## time dilation.

var _player: Player
var _rocket: Rocket
var _hud: HUD
var _rocket_hud: RocketHUD
var _threw_back: bool = false
var _crate_beds: Array = []
var _regen_t: float = 6.0
var _save_t: float = 5.0
var _ore_t: float = 4.0
var _mines: Array = []   # per-planet mine registry
var _last_soi: String = ""
var _pyramid_exit: Vector3 = Vector3.ZERO
var _temple_btn: Gate
var _temple_np: Vector3 = Vector3.ZERO
var _temple_B: Basis = Basis.IDENTITY
var _temple_opened: bool = false
var _trials_started: bool = false
var MINE_DIRS := {
	"Home": Vector3(0.6, 0.45, -0.66).normalized(),
	"Circuitia": Vector3(-0.5, 0.7, 0.4).normalized(),
	"Logica": Vector3(0.8, -0.3, 0.5).normalized(),
	"Pi": Vector3(-0.3, -0.8, 0.5).normalized(),
	"Verdant": Vector3(0.7, 0.2, 0.7).normalized(),
	"Crystalia": Vector3(-0.6, 0.5, -0.6).normalized(),
}
var _snap_t: float = 60.0
var _rifts: Array = []                 # rift positions
var _rift_cd: float = 0.0
const C4_POS := Vector3(9000, 6000, -9000)
var _c4: Connect4
var _c4_zone: bool = false
var _burn_t: float = 0.0
var _trial_check_t: float = 1.0
var _ufo: UFO
var _ufo_day: int = -1

var _palette := [
	Color("#ff5964"), Color("#ffd166"), Color("#06d6a0"),
	Color("#4cc9f0"), Color("#b388ff"), Color("#ff8c42"),
]

func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	get_window().grab_focus()
	# per-slot run settings: world scale + hardcore
	Universe.apply_scale(float(Save.character.get("wscale", 1.0)))
	Game.hardcore = bool(Save.character.get("hardcore", false))
	_setup_environment()
	_setup_light()
	for b in Universe.bodies:
		_build_body(b)
	_spawn_invaders()
	_spawn_player_and_rocket()

	Zones.build_shadow_temple(self, Universe.make_flat_body(Zones.SHADOW_POS))
	_spawn_rifts()
	_spawn_starship()
	_c4 = Connect4.new()
	add_child(_c4)
	_c4.global_position = C4_POS

	_hud = HUD.new()
	add_child(_hud)
	add_child(InventoryUI.new())
	add_child(StorageUI.new())
	add_child(MachineUI.new())
	add_child(MapUI.new())
	add_child(TerminalUI.new())
	add_child(TraderUI.new())
	add_child(CodeUI.new())
	add_child(PiQuizUI.new())
	add_child(TeleportUI.new())
	add_child(PauseMenu.new())
	add_child(StatsOverlay.new())
	_rocket_hud = RocketHUD.new()
	add_child(_rocket_hud)
	_rocket_hud.set_rocket(_rocket)

	Game.reset()
	Save.apply_progress()   # restore this slot's run (no-op on a fresh slot)
	if OS.get_environment("CTD_TEST") == "1":
		_self_test()
	if _player:
		_player.restore_jet()   # jetpack comes back ON if you left it on
	if Game.door_open:
		open_temple_door()   # temple stays open across sessions
	restore_world()          # your machines, chests, wires: still there
	if Save.had_pet() and _player:
		# your buddy waited for you -- the SAME buddy (genome restored)
		var pet := Animal.new()
		pet.setup(Universe.nearest(_player.global_position), false, false, Save.pet_genome())
		add_child(pet)
		pet.global_position = _player.global_position + Vector3(2, 1, 0)
		pet.tame()
		pet.staying = Save.pet_stay()
	# Come back exactly where you left -- gravity zone included, so
	# interior respawns behave. (And yes: still trapped in TIN 618.)
	var sp = Save.saved_pos()
	if sp != null and _player:
		_player.global_position = sp
		if Save.was_in_rocket():
			var rk := Rocket.new()
			add_child(rk)
			rk.global_position = sp
			rk.hyperdrive = Save.was_hyper()
			rk.board(_player)

## Headless regression test: build a small base, save-cycle it, count.
func _self_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var g := EMachines.Generator.new()
	add_child(g)
	g.set_meta("placed_id", "generator")
	g.global_position = Vector3(0, 60, 0)
	var c := EMachines.Capacitor.new()
	add_child(c)
	c.set_meta("placed_id", "capacitor")
	c.global_position = Vector3(6, 60, 0)
	var ch := Chest.new()
	add_child(ch)
	ch.set_meta("placed_id", "chest")
	ch.global_position = Vector3(3, 60, 3)
	var wpt := Waypoint.new()
	add_child(wpt)
	wpt.set_meta("placed_id", "waypoint")
	wpt.global_position = Vector3(-3, 60, 0)
	var everything := ["furnace", "coinifier", "autominer", "atm", "spawnbeacon",
		"coaldrill", "bioreactor", "rtg", "prisreactor", "capacitor", "ultracap",
		"efurnace", "eseller", "elight", "switch", "ecomputer", "scomputer",
		"teleporter", "extender", "rocket"]
	var xoff := 10.0
	for pid in everything:
		var node := _spawn_world_obj(pid)
		if node == null:
			print("SELFTEST factory MISSING: ", pid)
			continue
		add_child(node)
		node.set_meta("placed_id", pid)
		node.global_position = Vector3(xoff, 60, 0)
		xoff += 4.0
	var dr := ItemDrop.new()
	dr.setup("irid", 5)
	add_child(dr)
	dr.global_position = Vector3(0, 60, -3)
	await get_tree().process_frame
	g.connect_wire(c, "power", 0)
	g.connect_wire(ch, "item", 2)
	g.add_coil()
	c.connect_wire(g.coil_node, "power", 0)
	var w := collect_world()
	print("SELFTEST collect=", w.size(), " json_len=", JSON.stringify(w).length())
	# full disk-style JSON roundtrip, like a real save file
	var blob := JSON.stringify({"world": w})
	var parsed = JSON.parse_string(blob)
	Save.set_world(parsed["world"])
	Save._progress["world"] = parsed["world"]
	restore_world()
	await get_tree().process_frame
	var w2 := collect_world()
	print("SELFTEST recollect=", w2.size(), " (expected ", w.size() * 2, " after respawn beside originals)")

func _process(delta: float) -> void:
	_regen_crates(delta)
	_regen_ore(delta)
	var pos := _active_pos()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 5.0
		var hyper := false
		if Game.mode == Game.Mode.IN_ROCKET:
			for r in get_tree().get_nodes_in_group("rocket"):
				if r is Rocket and r.piloted:
					hyper = r.hyperdrive
					break
		var petn = get_tree().get_first_node_in_group("pet")
		if petn != null and is_instance_valid(petn):
			Save.set_pet(true, petn.genome, petn.staying)
		else:
			Save.set_pet(false)
		if _world_load_ok:
			Save.set_world(collect_world())
		Save.set_player_pos(pos, Game.mode == Game.Mode.IN_ROCKET, hyper)
		Save.save_progress()

	# --- time-rift snapshots: one per minute, keep the last 6 ---
	_snap_t -= delta
	if _snap_t <= 0.0 and not Game.dead:
		_snap_t = 60.0
		Save.snaps.append(_make_snapshot(pos))
		while Save.snaps.size() > 6:
			Save.snaps.pop_front()

	# --- the Connect 4 island has no gravity. it's deep space. obviously. ---
	if Game.mode == Game.Mode.ON_FOOT:
		var c4d := pos.distance_to(C4_POS)
		if not _c4_zone and Game.zone == "" and c4d < 120.0:
			Game.zone = "zero"
			_c4_zone = true
		elif _c4_zone and c4d > 140.0:
			Game.zone = ""
			_c4_zone = false

	# --- the UFO market: Tuesdays (and some Saturdays), new spot each time ---
	var day := Game.day_index()
	if day != _ufo_day:
		_ufo_day = day
		if _ufo and is_instance_valid(_ufo):
			_ufo.queue_free()
			_ufo = null
		if Game.is_ufo_day():
			_ufo = UFO.new()
			add_child(_ufo)
			var rng := RandomNumberGenerator.new()
			rng.seed = day * 977
			_ufo.global_position = Vector3(
				rng.randf_range(-6000, 6000), rng.randf_range(-2000, 3000),
				rng.randf_range(-6000, 6000)) * Universe.world_scale
			if _hud:
				_hud.flash("a saucer slid into the system. it's %s." % Game.weekday_name())

	# --- rifts: warped patches of space; fly through -> 5 min into the past ---
	_rift_cd = maxf(0.0, _rift_cd - delta)
	if _rift_cd <= 0.0 and not Game.dead:
		for r in _rifts:
			if pos.distance_to(r) < 10.0:
				_enter_rift()
				break

	# sphere-of-influence change notice (KSP-style)
	var soi := Universe.nearest(pos).name
	if soi != _last_soi:
		if _last_soi != "" and _hud:
			_hud.flash("Leaving %s SOI  →  entering %s SOI" % [_last_soi, soi])
		_last_soi = soi

	# --- universe edge: the god throws you back in (an unholy act) ---
	# pocket dimensions live OUTSIDE the map on purpose -- the god only
	# polices real space, not the sponge/temples
	if Game.zone == "" and pos.length() > Universe.BOUNDARY:
		var target := pos.normalized() * (Universe.BOUNDARY * 0.85)
		var node := _active_node()
		if node and node.has_method("god_throwback"):
			node.god_throwback(target)
		if not _threw_back:
			_threw_back = true
			Game.anger(15.0)
			if _hud:
				_hud.flash("THE UNIVERSE GOD (ThePearlKing) HURLS YOU BACK IN")
	else:
		_threw_back = false

	# --- TIN 618 time dilation. No death screen: you just... slow. Forever. ---
	var bh := Universe.body_named("TIN 618")
	if bh:
		var d := pos.distance_to(bh.center)
		var horizon := bh.radius
		var influence := horizon * 10.0
		if d < influence:
			var t := clampf((d - horizon) / (influence - horizon), 0.0, 1.0)
			Game.dilation = maxf(0.005, pow(t, 1.8))
			if d < horizon * 1.3:
				Game.trapped = true   # silently. it's like that when you come back.
		else:
			Game.dilation = 1.0
	Engine.time_scale = Game.dilation * Game.timewarp

	# --- suns burn. You do not walk on a star. You do not park in one. ---
	if not Game.dead:
		for b in Universe.bodies:
			if b.kind != "sun":
				continue
			var sd: float = pos.distance_to(b.center)
			if sd < b.radius * 1.05:
				# TOUCHED the star: absorbed. instantly.
				if _hud:
					_hud.sun_fire()
					_hud.flash("ABSORBED BY %s" % str(b.name).to_upper())
				Game.hurt(100000.0)
			elif sd < b.radius * 1.6:
				Game.hurt(50.0 * delta)
				if _burn_t <= 0.0:
					_burn_t = 2.0
					if _hud:
						_hud.flash("BURNING")
	_burn_t = maxf(0.0, _burn_t - delta)

	# which fold-maze room are you standing in? (number on screen)
	if _hud and _player and Game.mode == Game.Mode.ON_FOOT:
		var mb := Zones.TEMPLE_POS + Vector3(0, 200, 0)
		var room := 0
		if Game.zone == "flat":
			for rk in 4:
				if _player.global_position.distance_to(mb + Vector3(float(rk) * 400.0, 0, 0)) < 80.0:
					room = rk + 1
					break
		_hud.set_zone_text(str(room) if room > 0 else "")

	if _trials_started and not Game.trials_done:
		_trial_check_t -= delta
		if _trial_check_t <= 0.0:
			_trial_check_t = 1.0
			var alive := 0
			for en in get_tree().get_nodes_in_group("enemy"):
				if en is Enemy and en.pyramid and is_instance_valid(en):
					alive += 1
			if alive == 0:
				Game.trials_done = true
				Sfx.play("learn")
				if _hud:
					_hud.flash("MAZE DOOR UNSEALED")

	if Game.dead and Input.is_key_pressed(KEY_R):
		Engine.time_scale = 1.0
		if Game.permadead:
			get_tree().change_scene_to_file("res://Title.tscn")
		else:
			Game.reset()
			# death sends you HOME (or to your chosen beacon) -- never
			# back to the spot that just killed you
			Game.zone = ""
			Save.set_player_pos(Game.spawn_pos + Game.spawn_up * 1.5, false, false)
			get_tree().reload_current_scene()

func _notification(what: int) -> void:
	# window closed mid-run: save the exact position on the way out
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var petc = get_tree().get_first_node_in_group("pet")
		if petc != null and is_instance_valid(petc):
			Save.set_pet(true, petc.genome, petc.staying)
		var hyper := false
		if Game.mode == Game.Mode.IN_ROCKET:
			for r in get_tree().get_nodes_in_group("rocket"):
				if r is Rocket and r.piloted:
					hyper = r.hyperdrive
		if _world_load_ok:
			Save.set_world(collect_world())
		Save.set_player_pos(_active_pos(), Game.mode == Game.Mode.IN_ROCKET, hyper)
		Save.save_progress()

func _active_node() -> Node:
	var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
	return get_tree().get_first_node_in_group(g)

func _active_pos() -> Vector3:
	var n := _active_node()
	return n.global_position if n else Vector3.ZERO

# ------------------------------------------------------------- universe

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# subtle starfield sky (not distracting)
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_sh := Shader.new()
	sky_sh.code = "shader_type sky;\nvoid sky(){\n vec3 d = EYEDIR;\n vec3 cell = floor(d*160.0);\n float n = fract(sin(dot(cell, vec3(12.9898,78.233,37.719)))*43758.5453);\n float star = step(0.9975, n) * 0.7;\n COLOR = vec3(0.015,0.015,0.03) + vec3(star);\n}"
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_sh
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#404058")
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("#ffe6f2")
	add_child(sun)

func _build_body(b) -> void:
	if b.kind == "torus":
		_build_torus(b)
		return
	var p := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = b.radius
	sm.height = b.radius * 2.0
	sm.radial_segments = 48
	sm.rings = 28
	mi.mesh = sm
	mi.material_override = _planet_material(b.kind, b.color)
	p.add_child(mi)
	var col := CollisionShape3D.new()
	if MINE_DIRS.has(b.name):
		# Mined planet: BOTH the collider and the VISIBLE mesh are a shell
		# with the mouth cut out -- you can see straight down the shaft.
		var mdir: Vector3 = MINE_DIRS[b.name]
		# cut a hole of CONSTANT ~5m radius regardless of planet size
		# (a fixed angle made huge walk-through gaps on big planets)
		var thresh := cos(4.8 / b.radius)   # matches the shaft's outer walls
		var faces := sm.get_faces()
		var kept := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var centroid := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			if centroid.normalized().dot(mdir) > thresh:
				continue   # cut the mouth
			kept.append(faces[i])
			kept.append(faces[i + 1])
			kept.append(faces[i + 2])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(kept)
		col.shape = shape
		mi.mesh = _mesh_from_faces(kept)   # visual hole matches
	else:
		var cs := SphereShape3D.new()
		cs.radius = b.radius
		col.shape = cs
	p.add_child(col)
	add_child(p)
	p.global_position = b.center

	if b.kind in ["home", "life", "sand", "pi"]:
		_add_aurora(b)   # polar lights on the pretty planets
	if b.kind == "wireframe":
		_wireframe_overlay(p, sm)   # real polygon edges over a dark sphere
	if b.kind == "blackhole":
		_accretion(b)
	if b.kind == "sun":
		var ol := OmniLight3D.new()
		ol.light_energy = 4.0
		ol.omni_range = 4000.0
		ol.light_color = Color("#ffcc55")
		p.add_child(ol)

	_populate(b)

## Polar auroras: thin undulating light curtains LEVITATING high above
## each pole (like the real thing) -- green skirts, violet-red crowns,
## slow waves. Scales with the planet (and the world-size multiplier).
func _add_aurora(b) -> void:
	for pole in [1.0, -1.0]:
		for ring in [[0.34, 0.0], [0.24, 2.7]]:   # two curtains for depth
			var curtain := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = b.radius * float(ring[0])
			cm.bottom_radius = b.radius * float(ring[0]) * 1.06
			cm.height = b.radius * 0.12
			cm.cap_top = false
			cm.cap_bottom = false
			cm.radial_segments = 96
			cm.rings = 6
			curtain.mesh = cm
			var sh := Shader.new()
			sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float seed;
float h(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void vertex(){
	// the whole curtain slowly undulates like a ribbon in solar wind
	float a = UV.x * 6.28318;
	VERTEX.x += sin(a*3.0 + TIME*0.22 + seed) * 0.035 * length(VERTEX.xz);
	VERTEX.z += cos(a*2.0 - TIME*0.17 + seed) * 0.035 * length(VERTEX.xz);
	VERTEX.y += sin(a*4.0 + TIME*0.13 + seed*2.0) * 0.12 * abs(VERTEX.y);
}
void fragment(){
	float x = UV.x * 140.0;
	// vertical ray columns that drift and flicker slowly
	float col_id = floor(x);
	float r1 = h(vec2(col_id, seed));
	float ray = 0.25 + 0.75 * pow(0.5 + 0.5*sin(x*0.9 + TIME*(0.15+r1*0.2) + r1*6.28), 3.0);
	float v = UV.y;
	// bright thin base, long faint tail upward (curtain look)
	float band = smoothstep(0.0, 0.06, v) * pow(1.0 - v, 1.8);
	// real aurora colours: green skirt -> violet/red crown
	vec3 lowc = vec3(0.10, 0.95, 0.35);
	vec3 hic  = vec3(0.55, 0.15, 0.60);
	vec3 col = mix(lowc, hic, pow(v, 1.4));
	ALBEDO = col;
	ALPHA = band * ray * 0.22;
	EMISSION = col * band * ray * 2.2;
}"""
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("seed", randf() * 100.0 + float(ring[1]))
			curtain.material_override = mat
			add_child(curtain)
			# levitates ABOVE the surface, in the sky over the pole
			curtain.global_position = b.center + Vector3.UP * pole * (b.radius * 1.14)
			if pole < 0.0:
				curtain.rotation_degrees = Vector3(180, 0, 0)

## Rebuild a lit, UV-mapped mesh from raw triangle soup (used for the
## see-through mined-planet shells). Spherical UVs so surface shaders work.
func _mesh_from_faces(faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in faces.size():
		var v := faces[i]
		var n := v.normalized()
		st.set_normal(n)
		st.set_uv(Vector2(atan2(n.z, n.x) / TAU + 0.5, acos(clampf(n.y, -1.0, 1.0)) / PI))
		st.add_vertex(v)
	return st.commit()

func _build_torus(b) -> void:
	var p := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = b.major - b.radius
	tm.outer_radius = b.major + b.radius
	tm.rings = 64
	tm.ring_segments = 32
	mi.mesh = tm
	mi.material_override = _surface_material("rock", b.color)
	p.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tm.get_faces())
	col.shape = shape
	p.add_child(col)
	add_child(p)
	p.global_position = b.center
	# crates all around the tube -- outside, inside the hole, everywhere
	for i in 40:
		var theta := randf() * TAU
		var phi := randf() * TAU
		var ring_dir := Vector3(cos(theta), 0, sin(theta))
		var tube_dir := (ring_dir * cos(phi) + Vector3.UP * sin(phi)).normalized()
		var s := randf_range(1.2, 2.4)
		var d := Destructible.new()
		d.setup(Vector3(s, s, s), _palette[randi() % _palette.size()], 1, 14)
		add_child(d)
		var pos: Vector3 = b.center + ring_dir * b.major + tube_dir * (b.radius + s * 0.5)
		d.global_transform = Transform3D(_basis_from_up(tube_dir), pos)

func _accretion(b) -> void:
	# A cool multi-band accretion disk: several tilted, colour-graded rings.
	var specs := [
		[1.25, 1.7, Color("#fff2c0"), 8.0],
		[1.7, 2.3, Color("#ff9a1a"), 6.0],
		[2.3, 3.1, Color("#ff4d1a"), 4.0],
		[3.1, 4.2, Color("#7a1aff"), 2.5],
	]
	for s in specs:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = b.radius * float(s[0])
		tm.outer_radius = b.radius * float(s[1])
		tm.rings = 64
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = s[2]
		m.emission_energy_multiplier = float(s[3])
		m.albedo_color = s[2]
		ring.material_override = m
		ring.rotation_degrees = Vector3(78, 0, 6)
		add_child(ring)
		ring.global_position = b.center
	# faint photon halo
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = b.radius * 1.08
	hm.height = b.radius * 2.16
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(1.0, 0.7, 0.3, 0.15)
	hmat.emission_enabled = true
	hmat.emission = Color("#ffb060")
	hmat.emission_energy_multiplier = 1.5
	halo.material_override = hmat
	add_child(halo)
	halo.global_position = b.center

func _planet_material(kind: String, color: Color) -> Material:
	match kind:
		"pixel", "wth", "wob", "contrast":
			return ShaderLib.make(kind, color)
		"wireframe":
			# dark base; real polygon edges added as an overlay in _build_body
			return _unshaded(Color("#020308"), 1.0)
		"blind":
			return _unshaded(Color.WHITE, 4.0)
		"sun":
			return _unshaded(Color("#ffcc33"), 4.0)
		"blackhole":
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.albedo_color = Color.BLACK
			return bm
		_:
			return _surface_material(kind, color)

## Lit procedural surface texture for ordinary planets.
func _surface_material(kind: String, color: Color) -> ShaderMaterial:
	var style := "rock"
	match kind:
		"home": style = "crystal"
		"sand": style = "sand"
		"life": style = "organic"
	var sh := Shader.new()
	sh.code = _surface_shader(style)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("base", Vector3(color.r, color.g, color.b))
	return mat

func _surface_shader(style: String) -> String:
	var head := "shader_type spatial;\nuniform vec3 base;\nfloat h(vec2 p){return fract(sin(dot(p,vec2(41.3,289.1)))*43758.5);}\n"
	match style:
		"crystal":
			return head + "void fragment(){\n vec2 uv=UV*24.0; vec2 c=floor(uv); vec2 f=fract(uv);\n float tri=step(f.x+f.y,1.0);\n float sh=mix(0.7,1.1,h(c+tri*0.5));\n float edge=smoothstep(0.0,0.05,abs(f.x+f.y-1.0));\n ALBEDO=base*sh*mix(0.55,1.0,edge);\n METALLIC=0.35; ROUGHNESS=0.3;\n}"
		"sand":
			return head + "void fragment(){\n vec2 uv=UV*vec2(70.0,70.0);\n float grain=h(floor(uv));\n float dune=sin(UV.y*44.0+sin(UV.x*11.0)*3.0)*0.5+0.5;\n ALBEDO=base*(0.82+0.18*grain)*(0.85+0.15*dune);\n ROUGHNESS=0.95;\n}"
		"organic":
			return head + "void fragment(){\n vec2 uv=UV*18.0;\n float n=h(floor(uv))*0.5+h(floor(uv*2.3))*0.5;\n ALBEDO=mix(base*0.55,base*1.25,n);\n ROUGHNESS=0.8;\n}"
	return head + "void fragment(){\n vec2 uv=UV*30.0;\n float n=h(floor(uv))*0.6+h(floor(uv*0.5))*0.4;\n ALBEDO=base*(0.65+0.5*n);\n METALLIC=0.2; ROUGHNESS=0.7;\n}"

func _wireframe_overlay(parent: Node3D, sphere: SphereMesh) -> void:
	var faces := sphere.get_faces()
	var pts := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		pts.append(a); pts.append(b)
		pts.append(b); pts.append(c)
		pts.append(c); pts.append(a)
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#12ff9a")
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color("#12ff9a")
	mi.material_override = mat
	parent.add_child(mi)

func _unshaded(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _shader_code(kind: String) -> String:
	match kind:
		"pixel":
			return "shader_type spatial;\nvoid fragment(){\n vec3 q=floor(VERTEX*0.7);\n float n=fract(sin(dot(q,vec3(12.9898,78.233,37.719)))*43758.5453);\n vec3 c=vec3(step(0.5,n),step(0.33,fract(n*3.0)),step(0.66,fract(n*7.0)));\n ALBEDO=c; EMISSION=c*0.4;\n}"
		"wth":
			return "shader_type spatial;\nvoid fragment(){\n float t=TIME;\n float band=floor(VERTEX.y*4.0+t*6.0);\n float g=fract(sin(band)*43758.5453);\n vec3 c=vec3(fract(VERTEX.x*0.3+t),g,fract(VERTEX.z*0.3-t));\n if(g>0.7){c=vec3(1.0)-c;}\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wireframe":
			return "shader_type spatial;\nvoid fragment(){\n vec2 gr=abs(fract(UV*40.0)-0.5);\n float line=1.0-smoothstep(0.0,0.05,min(gr.x,gr.y));\n ALBEDO=vec3(0.02); EMISSION=vec3(0.1,0.9,0.5)*line;\n}"
		"contrast":
			return "shader_type spatial;\nvoid fragment(){\n float v=step(0.5,fract(VERTEX.y*0.15+VERTEX.x*0.1));\n ALBEDO=vec3(v); EMISSION=vec3(v);\n}"
	return "shader_type spatial;\nvoid fragment(){ ALBEDO=vec3(0.5); }"

# -------------------------------------------------------------- content

func _populate(b) -> void:
	# Coin value per crate rises far from Home, so late-game gear forces
	# you out to the dangerous planets. (value, target crate count)
	match b.kind:
		"home":
			_register_crates(b, 60, 2)     # cheap: enough for a rocket + basics
			_place_on_surface(b, NoodleGod.new(), _surface_dir(), func(n): n.build())
			_spawn_mine_clues(b)
		"circuit":
			_register_crates(b, 40, 9)
			for i in 4:
				_place_on_surface(b, Circuit.new(), _surface_dir(), func(n): n.build())
			_spawn_enemies(b, 5, 1)
			_spawn_res_nodes(b, 8, "raw_irid", 2)
			_build_mine(b, MINE_DIRS["Circuitia"], "raw_ingot", 8, Color("#a24bff"))
		"logic":
			_register_crates(b, 30, 16)
			for i in 2:
				_place_on_surface(b, LogicDiagram.new(), _surface_dir(), func(n): n.build())
			_spawn_enemies(b, 6, 2)
			_spawn_res_nodes(b, 10, "raw_irid", 2)
			_build_mine(b, MINE_DIRS["Logica"], "raw_irid", 4, Color("#2a8f6a"))
		"pi":
			var ps := PiStructure.new()
			add_child(ps)
			ps.global_position = b.center
			ps.build(b.radius)
			_register_crates(b, 24, 26)
			_spawn_enemies(b, 6, 3)
			var shrine := Gate.new().configure({
				"action": "pishrine", "label": "PI SHRINE",
				"color": Color("#ff8c1a")})
			add_child(shrine)
			var sdir := _surface_dir()
			shrine.global_transform = Transform3D(_basis_from_up(sdir), b.center + sdir * b.radius)
			# --- a proper ROUND shrine around the gate ---
			# stacked stone dais: three shrinking discs
			var tiers := [[5.0, 0.7, 0.0], [3.8, 0.6, 0.7], [2.6, 0.6, 1.3]]
			for tr in tiers:
				var disc := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = tr[0]
				dm.bottom_radius = tr[0] + 0.3
				dm.height = tr[1]
				disc.mesh = dm
				disc.material_override = Destructible.make_material(Color("#c9a45e"), 0.15)
				shrine.add_child(disc)
				disc.position = Vector3(0, tr[2] + tr[1] * 0.5, 0)
			# ring of round pillars with glowing caps
			for pi2 in 6:
				var pang := TAU * float(pi2) / 6.0
				var pil := MeshInstance3D.new()
				var pm3 := CylinderMesh.new()
				pm3.top_radius = 0.28
				pm3.bottom_radius = 0.34
				pm3.height = 4.2
				pil.mesh = pm3
				pil.material_override = Destructible.make_material(Color("#b8924e"), 0.1)
				shrine.add_child(pil)
				pil.position = Vector3(cos(pang) * 4.2, 2.4, sin(pang) * 4.2)
				var cap := MeshInstance3D.new()
				var cm3 := SphereMesh.new()
				cm3.radius = 0.4
				cm3.height = 0.8
				cap.mesh = cm3
				cap.material_override = Destructible.make_material(Color("#ff8c1a"), 2.2)
				shrine.add_child(cap)
				cap.position = Vector3(cos(pang) * 4.2, 4.8, sin(pang) * 4.2)
			# the floating golden pi, visible from orbit
			var pig := Label3D.new()
			pig.text = "π"
			pig.font_size = 400
			pig.pixel_size = 0.03
			pig.modulate = Color("#ffd166")
			pig.outline_modulate = Color("#7a3c00")
			pig.outline_size = 36
			pig.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			shrine.add_child(pig)
			pig.position = Vector3(0, 8.5, 0)
			var slight := OmniLight3D.new()
			slight.light_color = Color("#ffb04a")
			slight.light_energy = 2.5
			slight.omni_range = 26.0
			shrine.add_child(slight)
			slight.position = Vector3(0, 5.0, 0)
			_spawn_res_nodes(b, 12, "raw_irid", 3)
			_build_mine(b, MINE_DIRS["Pi"], "raw_irid", 5, Color("#2a8f6a"))
		"sand":
			_register_crates(b, 50, 12)
			_euclid_landmarks(b)   # Euclid is safe: no evil aliens
		"life":
			_register_crates(b, 10, 7)
			_spawn_flora(b)
			_build_mine(b, MINE_DIRS["Verdant"], "raw_ingot", 4, Color("#a24bff"))
		"pixel", "wth", "wob", "wireframe", "contrast":
			_register_crates(b, 18, 40)
			# prism shards: ONLY grow under shader light
			for i in 14:
				var pr := Destructible.new()
				var ph := randf_range(1.8, 4.5)
				pr.setup(Vector3(randf_range(0.5, 0.9), ph, randf_range(0.5, 0.9)),
					Color("#ff7ce9"), 2, 5, 4.0, 0.0, "prism", 1)
				add_child(pr)
				var pd := _surface_dir()
				pr.global_transform = Transform3D(_basis_from_up(pd), b.center + pd * (b.radius + ph * 0.5))
			_spawn_enemies(b, 6, 5)   # shooters + flyers guard the shards
		"blind":
			_register_crates(b, 12, 30)
		"crystal":
			# ultima crystals: guarded, far, worth the trip
			for i in 22:
				var cr := Destructible.new()
				var h := randf_range(2.5, 6.0)
				cr.setup(Vector3(randf_range(0.8, 1.4), h, randf_range(0.8, 1.4)),
					Color("#7df9ff"), 3, 5, 3.0, 0.0, "ultima", 1)
				add_child(cr)
				var cd := _surface_dir()
				cr.global_transform = Transform3D(_basis_from_up(cd), b.center + cd * (b.radius + h * 0.5))
			_register_crates(b, 12, 30)
			_spawn_enemies(b, 10, 6)   # heavily guarded
			_build_mine(b, MINE_DIRS["Crystalia"], "ultima", 2, Color("#7df9ff"))
		_:
			pass

## Off-world resource nodes (mid-game: raw iridium etc).
func _spawn_res_nodes(b, count: int, res: String, per: int) -> void:
	for i in count:
		var nd := Destructible.new()
		var s := randf_range(1.2, 2.0)
		nd.setup(Vector3(s, s * 1.6, s), Color("#2a8f6a"), 2, 4, 2.2, 0.0, res, per)
		add_child(nd)
		var d := _surface_dir()
		nd.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + s * 0.8))

func _spawn_enemies(b, count: int, level: int) -> void:
	for i in count:
		var e := Enemy.new()
		e.setup(level, b)
		add_child(e)
		var dir := _surface_dir()
		e.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * (b.radius + 2.0))

func _spawn_flora(b) -> void:
	# FORESTS: dense clusters around a few centres; the rest scattered.
	var forests: Array = []
	for i in 4:
		forests.append(_surface_dir())
	for i in 130:
		var pl := Plant.new()
		add_child(pl)
		var d: Vector3
		if i < 80:
			# forest member: perturb around a forest centre
			var f: Vector3 = forests[i % forests.size()]
			d = (f + Vector3(randf_range(-0.14, 0.14), randf_range(-0.14, 0.14), randf_range(-0.14, 0.14))).normalized()
		else:
			d = _surface_dir()
		pl.global_transform = Transform3D(_basis_from_up(d), b.center + d * b.radius)
	var shroom_dirs: Array = []
	for i in 55:
		var mu := Mushroom.new()
		add_child(mu)
		var d2 := _surface_dir()
		shroom_dirs.append(d2)
		mu.global_transform = Transform3D(_basis_from_up(d2), b.center + d2 * b.radius)
	# animals: LAND ones live in the forests, FLIERS fill the skies elsewhere
	for i in 30:
		var an := Animal.new()
		var d3: Vector3
		if i < 20:
			var f2: Vector3 = forests[i % forests.size()]
			d3 = (f2 + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))).normalized()
			an.setup(b, true)    # grounded: walkers + tiny hoppers
		else:
			d3 = _surface_dir()
			an.setup(b, false)   # flier
		add_child(an)
		an.global_transform = Transform3D(_basis_from_up(d3), b.center + d3 * (b.radius + 1.0))
	# tiny bugs scuttling around the mushrooms
	for i in 14:
		var bug := Animal.new()
		bug.setup(b, true, true)
		add_child(bug)
		var md: Vector3 = shroom_dirs[randi() % shroom_dirs.size()]
		md = (md + Vector3(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), randf_range(-0.02, 0.02))).normalized()
		bug.global_transform = Transform3D(_basis_from_up(md), b.center + md * (b.radius + 0.4))
	# a few Permadeath Apples hidden among the plants
	for i in 3:
		var pa := PermaApple.new()
		add_child(pa)
		var d := _surface_dir()
		pa.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + 1.5))

func _euclid_landmarks(b) -> void:
	# North pole: a TINY temple. Doctor-Who rules: small outside,
	# cathedral inside. No signs.
	var np: Vector3 = b.center + Vector3.UP * b.radius
	var tiers := [Vector3(8, 1.6, 8), Vector3(6, 1.6, 6), Vector3(4, 2.4, 4)]
	var y := 0.0
	for t in tiers:
		var step := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = t
		step.mesh = m
		step.material_override = Destructible.make_material(Color("#d8c48a"), 0.08)
		add_child(step)
		step.global_transform = Transform3D(_basis_from_up(Vector3.UP), np + Vector3.UP * (y + t.y * 0.5))
		y += t.y
	for ci in 4:
		var ang := TAU * float(ci) / 4.0 + PI / 4.0
		var colmn := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.3
		cm2.bottom_radius = 0.4
		cm2.height = 3.0
		colmn.mesh = cm2
		colmn.material_override = Destructible.make_material(Color("#c9b47e"), 0.05)
		add_child(colmn)
		colmn.global_transform = Transform3D(_basis_from_up(Vector3.UP),
			np + Vector3(cos(ang) * 5.5, 1.5, sin(ang) * 5.5))
	# a small red button block by the base. figure it out.
	_temple_np = np
	_temple_B = _basis_from_up(Vector3.UP)
	_temple_btn = Gate.new().configure({
		"action": "terminal", "label": "DOOR TERMINAL", "color": Color("#c22")})
	add_child(_temple_btn)
	_temple_btn.global_transform = Transform3D(_temple_B, np + Vector3(0, 0, 8.0))
	Zones.build_temple_interior(self, np + Vector3(0, 2, 20),
		Universe.make_flat_body(Zones.TEMPLE_POS))

	# South pole: the sealed pyramid. Mind Core opens it. Zero-g inside.
	var sp: Vector3 = b.center + Vector3.DOWN * b.radius
	var pyr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 20.0
	cm.height = 26.0
	cm.radial_segments = 4
	pyr.mesh = cm
	pyr.material_override = Destructible.make_material(Color("#b5934f"), 0.1)
	add_child(pyr)
	pyr.global_transform = Transform3D(_basis_from_up(Vector3.DOWN), sp + Vector3.DOWN * 13.0)
	_pyramid_exit = sp + Vector3.DOWN * 2.0
	# inside the pyramid: the MENGER SHRINE. F + prism shards = enchant.
	var shrine := MengerShrine.new()
	add_child(shrine)
	shrine.global_transform = Transform3D(_basis_from_up(Vector3.DOWN), sp + Vector3.DOWN * 10.0)

func _register_crates(b, count: int, value: int) -> void:
	var grp := "brk_" + str(b.name)
	_crate_beds.append({"body": b, "value": value, "group": grp, "target": count})
	_scatter_crates(b, count, value, grp)

func _scatter_crates(b, count: int, value: int, grp: String) -> void:
	for i in count:
		var d := Destructible.new()
		var kind := randi() % 3
		var size: Vector3
		match kind:
			0:
				var s := randf_range(1.2, 2.6)
				size = Vector3(s, s, s)
			1:
				size = Vector3(randf_range(1.4, 2.8), randf_range(3.0, 7.0), randf_range(1.4, 2.8))
			_:
				size = Vector3(randf_range(2.4, 4.5), randf_range(0.7, 1.4), randf_range(2.4, 4.5))
		d.setup(size, _palette[randi() % _palette.size()], 1, value)
		add_child(d)
		d.add_to_group(grp)
		var dir := _surface_dir()
		d.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * (b.radius + size.y * 0.5))

## The rocket appears next to you the moment you own one (bought in shop).
func _spawn_bought_rocket() -> void:
	if not Inventory.has_rocket or (_rocket and is_instance_valid(_rocket)):
		return
	if Game.mode != Game.Mode.ON_FOOT or not _player:
		return
	var up := (_player.global_position - Universe.nearest(_player.global_position).center).normalized()
	_rocket = Rocket.new()
	add_child(_rocket)
	var side := _player.global_transform.basis.x
	_rocket.global_transform = Transform3D(_basis_from_up(up), _player.global_position + side * 5.0 + up * 1.5)
	if _rocket_hud:
		_rocket_hud.set_rocket(_rocket)

## A bought Spawn Beacon drops at the player and becomes the active spawn.
func _place_spawn_beacon() -> void:
	if not Inventory.want_spawn_beacon or Game.mode != Game.Mode.ON_FOOT or not _player:
		return
	Inventory.want_spawn_beacon = false
	var up := (_player.global_position - Universe.nearest(_player.global_position).center).normalized()
	var bcn := SpawnBeacon.new()
	add_child(bcn)
	bcn.global_transform = Transform3D(_basis_from_up(up), _player.global_position - up * 1.0)
	bcn.activate_spawn()

## Slowly restock destroyed crates on every planet.
func _regen_crates(delta: float) -> void:
	_regen_t -= delta
	if _regen_t > 0.0:
		return
	_regen_t = 6.0
	for bed in _crate_beds:
		var have := get_tree().get_nodes_in_group(bed["group"]).size()
		if have < int(bed["target"]):
			_scatter_crates(bed["body"], mini(int(bed["target"]) - have, 12), int(bed["value"]), bed["group"])

func _place_on_surface(b, node: Node3D, dir: Vector3, after: Callable) -> void:
	add_child(node)
	node.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	after.call(node)

## The mine on Home gets clue ARROWS. Other planets have mines too --
## no arrows there, just an open hole you can SEE INTO. Figure it out.
func _spawn_mine_clues(b) -> void:
	var dir: Vector3 = MINE_DIRS["Home"]
	_build_mine(b, dir, "raw_ingot", 6, Color("#a24bff"))
	var mine_pos: Vector3 = b.center + dir * b.radius
	for i in 9:
		var d := _surface_dir()
		var pos: Vector3 = b.center + d * b.radius
		var to_mine: Vector3 = mine_pos - pos
		var tangent := to_mine - d * to_mine.dot(d)
		if tangent.length() < 2.0:
			continue
		_arrow(pos + d * 0.15, d, tangent.normalized())

## A full mine: open see-through mouth, shaft into the planet, ore
## chamber with a furnace, exit gate that drops you BESIDE the hole.
func _build_mine(b, dir: Vector3, res_id: String, res_n: int, ore_col: Color) -> void:
	var C: Vector3 = b.center
	var R: float = b.radius
	var B := _basis_from_up(dir)
	var cham_y := R - 21.0

	# glowing rim marking the mouth
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.4
	tm.outer_radius = 4.6
	rim.mesh = tm
	rim.material_override = Destructible.make_material(Color("#6a3aa0"), 1.2)
	add_child(rim)
	rim.global_transform = Transform3D(B, C + dir * (R + 0.3))

	# shaft: 4 walls, open top and bottom -- wide enough to jetpack out
	var shaft_specs := [
		[Vector3(0.6, 17, 8.6), Vector3(4.3, 0, 0)],
		[Vector3(0.6, 17, 8.6), Vector3(-4.3, 0, 0)],
		[Vector3(8.6, 17, 0.6), Vector3(0, 0, 4.3)],
		[Vector3(8.6, 17, 0.6), Vector3(0, 0, -4.3)],
	]
	for sspec in shaft_specs:
		_mine_box(B, C + B * (Vector3(sspec[1].x, R - 6.5, sspec[1].z)), sspec[0], Color("#241436"), 0.2)

	# chamber: floor, walls, ceiling with an 8x8 hole where the shaft lands
	_mine_box(B, C + B * Vector3(0, cham_y - 6.0, 0), Vector3(36, 1, 36), Color("#241436"), 0.15)
	for w in [[Vector3(1, 12, 36), Vector3(17.5, 0, 0)], [Vector3(1, 12, 36), Vector3(-17.5, 0, 0)],
			[Vector3(36, 12, 1), Vector3(0, 0, 17.5)], [Vector3(36, 12, 1), Vector3(0, 0, -17.5)]]:
		_mine_box(B, C + B * (Vector3(w[1].x, cham_y, w[1].z)), w[0], Color("#241436"), 0.1)
	for cspec in [[Vector3(36, 1, 14.0), Vector3(0, 6, 11.0)], [Vector3(36, 1, 14.0), Vector3(0, 6, -11.0)],
			[Vector3(14.0, 1, 8.0), Vector3(11.0, 6, 0)], [Vector3(14.0, 1, 8.0), Vector3(-11.0, 6, 0)]]:
		_mine_box(B, C + B * (Vector3(cspec[1].x, cham_y + cspec[1].y, cspec[1].z)), cspec[0], Color("#241436"), 0.1)
	# glowing beam marking the way out
	var beam := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 0.15
	bm2.bottom_radius = 0.15
	bm2.height = 20.0
	beam.mesh = bm2
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(1.0, 0.88, 0.4, 0.25)
	bmat.emission_enabled = true
	bmat.emission = Color("#ffe066")
	bmat.emission_energy_multiplier = 1.5
	beam.material_override = bmat
	add_child(beam)
	beam.global_transform = Transform3D(B, C + dir * (R - 12.0))

	# light it
	for ly in [R - 8.0, cham_y]:
		var l := OmniLight3D.new()
		l.light_energy = 1.8
		l.omni_range = 40.0
		add_child(l)
		l.global_position = C + dir * ly

	var mine := {
		"body": b, "dir": dir, "B": B, "cham_y": cham_y,
		"group": "mine_" + str(b.name), "res": res_id, "res_n": res_n,
		"color": ore_col,
	}
	_mines.append(mine)
	_spawn_chamber_ore(mine, 26)
	# no free furnace. bring your own machines.
	# exit drops you BESIDE the mouth, not back down the hole
	var out := Gate.new().configure({
		"target": C + dir * (R + 1.5) + B.x * 9.0, "zone": "",
		"label": "MINE EXIT", "color": Color("#ffe066")})
	add_child(out)
	out.global_transform = Transform3D(B, C + B * Vector3(0, cham_y - 5.5, -14))

func _mine_box(B: Basis, pos: Vector3, size: Vector3, c: Color, emit: float) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = Destructible.make_material(c, emit)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = size
	col.shape = cs
	body.add_child(col)
	add_child(body)
	body.global_transform = Transform3D(B, pos)

## Rich chamber ore for one mine (what it drops depends on the planet).
func _spawn_chamber_ore(m: Dictionary, n: int) -> void:
	var b = m["body"]
	var B: Basis = m["B"]
	var cham_y: float = m["cham_y"]
	for i in n:
		var ore := Destructible.new()
		var s := randf_range(1.4, 2.6)
		ore.setup(Vector3(s, s, s), m["color"], 2, 5, 1.8, 0.0, str(m["res"]), int(m["res_n"]))
		add_child(ore)
		ore.add_to_group(str(m["group"]))
		ore.add_to_group("mine_ore")
		ore.global_transform = Transform3D(B,
			b.center + B * Vector3(randf_range(-15, 15), cham_y - 5.5 + s * 0.5, randf_range(-15, 15)))

func _regen_ore(delta: float) -> void:
	_ore_t -= delta
	if _ore_t > 0.0:
		return
	_ore_t = 4.0
	for m in _mines:
		var have := get_tree().get_nodes_in_group(str(m["group"])).size()
		if have < 26:
			_spawn_chamber_ore(m, mini(26 - have, 8))

func _arrow(pos: Vector3, up: Vector3, fwd: Vector3) -> void:
	var x := up.cross(fwd).normalized()
	var node := Node3D.new()
	add_child(node)
	node.global_transform = Transform3D(Basis(x, up, fwd).orthonormalized(), pos)
	var mat := Destructible.make_material(Color("#ffe066"), 4.0)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.12, 1.8)
	shaft.mesh = bm
	shaft.material_override = mat
	shaft.position = Vector3(0, 0, -0.2)
	node.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.6
	hm.height = 1.0
	hm.radial_segments = 4
	head.mesh = hm
	head.rotation_degrees = Vector3(90, 0, 0)   # point the cone along +Z
	head.position = Vector3(0, 0, 1.2)
	head.material_override = mat
	node.add_child(head)

func _spawn_invaders() -> void:
	# Deep-space voids, far from any planet (zero gravity out here).
	# a few fixed classics + a whole scattered fleet, everywhere you fly
	var spots: Array = [
		Vector3(0, 13000, 9000), Vector3(16000, 3000, -9000), Vector3(-11000, -13000, 7000),
	]
	for i in 22:
		var cand := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() \
			* randf_range(2500.0, 26000.0)
		var nb = Universe.nearest(cand)
		if cand.distance_to(nb.center) > nb.radius + 800.0:
			spots.append(cand)
	for s in spots:
		var inv := Invader.new()
		add_child(inv)
		inv.global_position = s
		inv.build(Color("#8cff5a"))
	# Clawde crabs -- valuable but breaking them angers the gods.
	for s in [Vector3(700, -300, 1200), Vector3(-900, 500, -600),
			Vector3(2200, 1400, -2600), Vector3(-2600, -1100, 2400)]:
		var crab := ClawdeCrab.new()
		add_child(crab)
		crab.global_position = s
		crab.build()

func _spawn_player_and_rocket() -> void:
	var home := Universe.body_named("Home")
	_player = Player.new()
	add_child(_player)
	_player.global_position = home.center + Vector3.UP * (home.radius + 2.0)
	if not Game.has_saved_spawn:   # a save may carry a beacon spawn already
		Game.set_spawn(_player.global_position, Vector3.UP)

	# No pre-placed rocket. It appears only once you BUY it (see _process).

	# a starter ATM near spawn
	var atm := ATM.new()
	add_child(atm)
	var adir := Vector3(-0.15, 1.0, 0.12).normalized()
	atm.global_transform = Transform3D(_basis_from_up(adir), home.center + adir * home.radius)

# -------------------------------------------------- world persistence

## Serialize every PLAYER-PLACED thing (machines, chests, beacons,
## parked rockets) including contents, energy, scripts, and the wire
## graph (as indices into this same list).
func collect_world() -> Array:
	var nodes: Array = []
	for grp in ["machine", "chest", "spawn", "autominer", "rocket", "waypoint", "itemdrop"]:
		for n in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n) and (n.has_meta("placed_id") or n is ItemDrop) and not nodes.has(n):
				if n is Rocket and n.piloted:
					continue   # in-flight rocket saves via its own path
				nodes.append(n)
	var idx := {}
	for i in nodes.size():
		idx[nodes[i]] = i
	var out: Array = []
	out.append_array(_unrestored)   # data we couldn't spawn survives untouched
	for n in nodes:
		var up: Vector3 = n.global_transform.basis.y
		if n is Rocket:
			up = -n.global_transform.basis.z   # nose = surface up for rockets
		if n is ItemDrop:
			out.append({"id": "itemdrop", "drop_id": n.id, "n": n.count,
				"pos": [n.global_position.x, n.global_position.y, n.global_position.z],
				"up": [up.x, up.y, up.z]})
			continue
		var e := {
			"id": str(n.get_meta("placed_id")),
			"pos": [n.global_position.x, n.global_position.y, n.global_position.z],
			"up": [up.x, up.y, up.z],
		}
		if n is Machine:
			e["buf"] = n.buf
			e["slot_in"] = n.in_slot
			e["slot_out"] = n.out_slot
			var wo: Array = []
			for k in n.wires_out.size():
				var w = n.wires_out[k]
				if w is Machine.CoilNode and is_instance_valid(w) and idx.has(w.host):
					wo.append([idx[w.host], -1])   # -1 = "that machine's coil"
				elif idx.has(w):
					wo.append([idx[w], int(n.wire_ports[k]) if k < n.wire_ports.size() else k + 1])
			var fo: Array = []
			for k2 in n.funnels_out.size():
				var f = n.funnels_out[k2]
				if idx.has(f):
					fo.append([idx[f], int(n.funnel_ports[k2]) if k2 < n.funnel_ports.size() else k2 + 1])
			e["wires"] = wo
			e["funnels"] = fo
			e["coil"] = n.has_coil
			if "tname" in n:
				e["tname"] = n.tname
			if "on" in n:
				e["sw_on"] = n.on
			if "script_src" in n:
				e["script"] = n.script_src
		if n is Chest:
			e["storage"] = n.storage
		if n is Rocket:
			e["hyper"] = n.hyperdrive
		out.append(e)
	return out

var _world_load_ok := false   # only a CLEAN restore may overwrite the save
var _unrestored: Array = []   # entries we couldn't spawn: carried forward, never deleted

func restore_world() -> void:
	_world_load_ok = false
	_unrestored = []
	var entries := Save.saved_world()
	var made: Array = []
	for e in entries:
		var n := _spawn_world_obj(str(e.get("id", "")))
		made.append(n)
		if n == null:
			_unrestored.append(e)   # unknown/broken id: keep its data verbatim
			continue
		if n is ItemDrop:
			n.setup(str(e.get("drop_id", "coal")), int(e.get("n", 1)))
		add_child(n)
		n.set_meta("placed_id", e["id"])
		var p = e.get("pos", [0, 0, 0])
		var u = e.get("up", [0, 1, 0])
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var up := Vector3(float(u[0]), float(u[1]), float(u[2])).normalized()
		if n is Rocket:
			var z := -up
			var x := up.cross(Vector3(0, 1, 0))
			if x.length() < 0.01:
				x = up.cross(Vector3(1, 0, 0))
			x = x.normalized()
			n.global_transform = Transform3D(Basis(x, z.cross(x).normalized(), z).orthonormalized(), pos)
			n.hyperdrive = bool(e.get("hyper", false))
		else:
			n.global_transform = Transform3D(_basis_from_up(up), pos)
		if n is Machine:
			n.buf = float(e.get("buf", 0.0))
			var si = e.get("slot_in", null)
			if si is Dictionary:
				n.in_slot = {"id": str(si.get("id", "")), "n": int(si.get("n", 0))}
			var so = e.get("slot_out", null)
			if so is Dictionary:
				n.out_slot = {"id": str(so.get("id", "")), "n": int(so.get("n", 0))}
			if "script_src" in n and e.has("script"):
				n.script_src = str(e["script"])
			if bool(e.get("coil", false)):
				n.add_coil()
			if e.has("tname") and "tname" in n:
				n.tname = str(e["tname"])
			if e.has("sw_on") and "on" in n:
				n.on = bool(e["sw_on"])
				if n.has_method("_apply_visual"):
					n._apply_visual()
		if n is Chest and e.has("storage"):
			n.storage = Save.parse_slots(e["storage"], 20)
	# second pass: rebuild the wire graph (visual arrows included)
	for i in entries.size():
		var n2 = made[i]
		if n2 == null or not n2 is Machine:
			continue
		for wi in entries[i].get("wires", []):
			var widx: int = int(wi[0]) if wi is Array else int(wi)
			var wport: int = int(wi[1]) if wi is Array and wi.size() > 1 else 0
			var dst = made[widx] if widx < made.size() else null
			if dst != null and wport == -1 and dst is Machine and dst.coil_node != null:
				n2.connect_wire(dst.coil_node, "power", 0)
			elif dst != null:
				n2.connect_wire(dst, "power", wport)
		for fi in entries[i].get("funnels", []):
			var fidx: int = int(fi[0]) if fi is Array else int(fi)
			var fport: int = int(fi[1]) if fi is Array and fi.size() > 1 else 0
			var dst2 = made[fidx] if fidx < made.size() else null
			if dst2 != null:
				n2.connect_wire(dst2, "item", fport)
	_world_load_ok = true   # reached the end: this session may save the world

func _spawn_world_obj(id: String) -> Node3D:
	match id:
		"chest": return Chest.new()
		"spawnbeacon": return SpawnBeacon.new()
		"furnace": return Furnace.new()
		"coinifier": return Coinifier.new()
		"autominer": return AutoMiner.new()
		"generator": return EMachines.Generator.new()
		"coaldrill": return EMachines.CoalDrill.new()
		"bioreactor": return EMachines.Bioreactor.new()
		"rtg": return EMachines.RTG.new()
		"prisreactor": return EMachines.PrismReactor.new()
		"teleporter": return EMachines.Teleporter.new()
		"extender": return EMachines.Extender.new()
		"itemdrop": return ItemDrop.new()
		"waypoint": return Waypoint.new()
		"capacitor": return EMachines.Capacitor.new()
		"efurnace": return EMachines.EFurnace.new()
		"eseller": return EMachines.ESeller.new()
		"atm": return ATM.new()
		"ecomputer": return Computers.EComputer.new()
		"scomputer": return Computers.SorterComputer.new()
		"ultracap": return EMachines.UltraCapacitor.new()
		"elight": return EMachines.ELight.new()
		"switch": return EMachines.Switch.new()
		"rocket": return Rocket.new()
	return null

# --------------------------------------------------------------- animals

var _caged: Array = []   # actual Animal nodes riding along in cages

func stash_animal(a: Animal) -> void:
	_caged.append(a)

func unstash_animal() -> Animal:
	while not _caged.is_empty():
		var a = _caged.pop_back()
		if is_instance_valid(a):
			return a
	return null

# ------------------------------------------------------------ the temple

## Maze beaten: the button crumbles, a REAL doorway opens in the temple
## base. Walk into the dark opening -> you're inside (bigger inside).
func open_temple_door() -> void:
	if _temple_opened:
		return
	_temple_opened = true
	if _temple_btn and is_instance_valid(_temple_btn):
		_temple_btn.queue_free()
	# the dark opening
	var mouth := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(2.2, 3.0, 0.5)
	mouth.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.01, 0.02)
	mouth.material_override = mat
	add_child(mouth)
	mouth.global_transform = Transform3D(_temple_B, _temple_np + _temple_B * Vector3(0, 1.5, 4.05))
	# walking into it teleports you inside -- seamless, no key needed
	var zone := Area3D.new()
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(1.8, 2.6, 1.4)
	col.shape = cs
	zone.add_child(col)
	add_child(zone)
	zone.global_transform = Transform3D(_temple_B, _temple_np + _temple_B * Vector3(0, 1.3, 4.5))
	zone.body_entered.connect(func(bdy: Node3D) -> void:
		if bdy is Player and Game.mode == Game.Mode.ON_FOOT:
			Game.zone = "flat"
			Game.zone_g = 9.0
			bdy.respawn_at(Zones.temple_spawn(), Vector3.UP)
			Sfx.play("warp")
			if _hud:
				_hud.flash("it is bigger on the inside")
			# the hall wakes up 2 seconds after you step in
			if not _trials_started:
				get_tree().create_timer(2.0).timeout.connect(start_trials))

## Trial button inside the hall: NOW the pyramids come. Never on top of you.
## Wrath maxed: spawn the descending noodle god above the player.
func noodle_wrath_event() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		Game.wrath_event_over(true)
		return
	var g := NoodleWrath.new()
	add_child(g)
	var up: Vector3 = (p.global_position - Universe.nearest(p.global_position).center).normalized()
	g.global_position = p.global_position + up * 900.0
	Sfx.play_at("rumble", p.global_position, 8.0)

## Every mine entrance in the universe (for the locator).
func mine_positions() -> Array:
	var out: Array = []
	for pname in MINE_DIRS:
		var b = Universe.body_named(pname)
		if b != null:
			out.append(b.center + MINE_DIRS[pname].normalized() * b.radius)
	return out

func start_trials() -> void:
	if _trials_started:
		return
	_trials_started = true
	var dummy = Universe.make_flat_body(Zones.TEMPLE_POS)
	var ppos := _player.global_position if _player else Zones.TEMPLE_POS
	var spawned := 0
	var tries := 0
	while spawned < 5 and tries < 60:
		tries += 1
		var cand: Vector3 = Zones.TEMPLE_POS + Vector3(randf_range(-45, 45), -12.0, randf_range(-45, 45))
		if cand.distance_to(ppos) < 18.0:
			continue   # NOT inside the player. ever.
		var e := Enemy.new()
		e.setup(4, dummy, true, spawned % 3 == 2)   # every 3rd: green TANK
		add_child(e)
		e.global_position = cand
		spawned += 1
	Sfx.play("warp", -6.0)
	if _hud:
		_hud.flash("THE TRIAL BEGINS")

## Cheat: drag the trader here, whatever day it is. He is not happy.
func summon_ufo() -> void:
	if _ufo and is_instance_valid(_ufo):
		_ufo.queue_free()
	_ufo = UFO.new()
	add_child(_ufo)
	var pos := _active_pos()
	var up := Universe.surface_up(Universe.nearest(pos), pos)
	_ufo.global_position = pos + up * 60.0 + Vector3(40, 0, 0)
	if _hud:
		_hud.flash("the saucer arrives, annoyed. \"this isn't tuesday.\"")
	Sfx.play("warp")

# ---------------------------------------------------------- rifts + time

func _spawn_rifts() -> void:
	# OFF the main travel lanes -- you should find these, not trip on them.
	_rifts = [
		Vector3(1500, 2400, -1800), Vector3(-2800, -2200, 3400),
		Vector3(5200, 3800, -5600), Vector3(-6500, 1500, -7000),
	]
	for r in _rifts:
		# a refraction bubble that VISIBLY warps the stars behind it...
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 9.0
		sm.height = 18.0
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.06)
		mat.refraction_enabled = true
		mat.refraction_scale = 0.12
		mat.roughness = 0.0
		mi.material_override = mat
		add_child(mi)
		mi.global_position = r
		# ...plus a shimmering rim so you can actually SEE the thing
		var rim := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 8.6
		rm.outer_radius = 9.4
		rim.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(0.7, 0.4, 1.0, 0.35)
		rmat.emission_enabled = true
		rmat.emission = Color("#a060ff")
		rmat.emission_energy_multiplier = 1.2
		rim.material_override = rmat
		rim.rotation_degrees = Vector3(randf_range(0, 180), randf_range(0, 180), 0)
		add_child(rim)
		rim.global_position = r

func _make_snapshot(pos: Vector3) -> Dictionary:
	return {
		"t": Game.playtime,
		"pos": [pos.x, pos.y, pos.z],
		"coins": Inventory.coins,
		"health": Game.health,
		"wrath": Game.wrath,
		"score": Game.score,
		"fuel": Inventory.fuel,
		"jet": Inventory.jet_fuel,
		"hotbar": Inventory.hotbar.duplicate(true),
		"backpack": Inventory.backpack_store.duplicate(true),
	}

func _enter_rift() -> void:
	if Save.snaps.is_empty():
		return
	_rift_cd = 20.0
	# 5 minutes back if we have it, else the oldest we know
	var chosen: Dictionary = Save.snaps[0]
	for s in Save.snaps:
		if float(s["t"]) <= Game.playtime - 300.0:
			chosen = s
	var p = chosen["pos"]
	var target := Vector3(float(p[0]), float(p[1]), float(p[2]))
	Inventory.coins = int(chosen["coins"])
	Game.health = float(chosen["health"])
	Game.wrath = float(chosen["wrath"])
	Game.score = int(chosen["score"])
	Inventory.fuel = float(chosen["fuel"])
	Inventory.jet_fuel = float(chosen["jet"])
	var hb = chosen["hotbar"]
	if hb is Array and hb.size() == 5:
		Inventory.hotbar = Save.parse_slots(hb, 5)
	var bp = chosen.get("backpack", [])
	if bp is Array and bp.size() == 10:
		Inventory.backpack_store = Save.parse_slots(bp, 10)
	Save.snaps.clear()   # the past resets; rifting again won't take you far
	var node := _active_node()
	if node is Rocket:
		node.global_position = target
		node.vel = Vector3.ZERO
	if _player:
		_player.global_position = target
		_player.velocity = Vector3.ZERO
	Sfx.play("warp", -2.0)
	if _hud:
		_hud.flash("the rift takes you. this already happened.")
	Inventory.changed.emit()
	Game.changed.emit()

# -------------------------------------------------------------- starship

func _spawn_starship() -> void:
	var ship := Starship.new()
	add_child(ship)
	ship.global_position = Vector3(1500, 700, 2200)
	ship.rotation_degrees = Vector3(20, 40, 65)   # derelict tilt

# --------------------------------------------------------------- helpers

func _surface_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _basis_from_up(up: Vector3) -> Basis:
	var t := Vector3(0, 1, 0)
	if absf(up.dot(t)) > 0.99:
		t = Vector3(1, 0, 0)
	var x := t.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).orthonormalized()
