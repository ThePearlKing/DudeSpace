class_name Zones
extends RefCounted
## Static builders for interior "pocket dimensions" placed at far-away
## coordinates (never inside planet colliders). Gravity there is flat
## (Game.zone = "flat") or zero (Game.zone = "zero").

const CAVERN_POS := Vector3(0, -40000, -40000)
const TEMPLE_POS := Vector3(40000, 12000, 40000)
const PYRAMID_POS := Vector3(85000, 52000, 85000)   # far from TIN 618's hum
static var pyramid_exit := Vector3.ZERO
const SHADOW_POS := Vector3(-16000, -4000, -14000)   # exterior temple, in space

static var temple_exit := Vector3.ZERO   # where the Euclid temple door is, outside

## Where a pocket-interior position "really is" in the outside world:
## house interiors map to their house's exterior, the Euclid temple
## interior maps to the pyramid door. Everything else maps to itself.
static func exterior_of(p: Vector3) -> Vector3:
	if pyramid_exit != Vector3.ZERO and p.distance_to(PYRAMID_POS) < 2600.0:
		return pyramid_exit
	if temple_exit != Vector3.ZERO and p.distance_to(TEMPLE_POS) < 2600.0:
		return temple_exit
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for h in tree.get_nodes_in_group("house"):
			if h is House and is_instance_valid(h) \
					and p.distance_to(h.room_center()) < 380.0:
				return h.global_position + h.global_transform.basis.y * 2.0
	return p

# ------------------------------------------------------------ mine cavern

# (the Home mine is now a REAL hole in the planet -- built in Main.gd)

# --------------------------------------------------------- euclid temple

static func build_temple_interior(root: Node3D, exit_target: Vector3, dummy_body) -> void:
	temple_exit = exit_target
	var p := TEMPLE_POS
	# TARDIS: huge inside
	_room(root, p, Vector3(120, 30, 120), Color("#d8c48a"), 0.1)
	var fy := -14.0   # floor level of the big hall
	# (trials auto-start 2s after you walk in -- no button)
	# mind core
	var core := Gate.new().configure({
		"action": "mindcore", "label": "MIND CORE", "color": Color("#ff5aa0")})
	root.add_child(core)
	core.global_position = p + Vector3(0, fy, -50)
	# breakables
	for i in 20:
		var d := Destructible.new()
		var s := randf_range(1.0, 2.4)
		d.setup(Vector3(s, s, s), Color("#e8d9a8"), 1, 14)
		root.add_child(d)
		d.global_position = p + Vector3(randf_range(-50, 50), fy + s * 0.5, randf_range(-50, 50))
	# exit
	var out := Gate.new().configure({
		"target": exit_target, "zone": "", "label": "EXIT",
		"color": Color("#ffe066")})
	root.add_child(out)
	out.global_position = p + Vector3(0, fy, 55)
	# non-euclidean maze: 4 disconnected corridor pods linked by gates
	var maze_base := p + Vector3(0, 200, 0)
	var pods := 4
	var pod_cols := [Color("#b8a878"), Color("#3a5a8a"), Color("#6a2a2a"), Color("#2a5a3a")]
	for k in pods:
		var mp := maze_base + Vector3(float(k) * 400.0, 0, 0)
		_room(root, mp, Vector3(30, 10, 30), pod_cols[k], 0.12)
		# every room is its own PLACE, not a copy
		match k:
			0:   # sandstone pillars
				for pi2 in 4:
					var ang2 := TAU * float(pi2) / 4.0
					var pil := MeshInstance3D.new()
					var pm2 := CylinderMesh.new()
					pm2.top_radius = 0.5
					pm2.bottom_radius = 0.7
					pm2.height = 9.0
					pil.mesh = pm2
					pil.material_override = Destructible.make_material(Color("#c9b47e"), 0.1)
					root.add_child(pil)
					pil.global_position = mp + Vector3(cos(ang2) * 9.0, 0, sin(ang2) * 9.0)
			1:   # blue room: cubes hang in the air
				for ci2 in 7:
					var cb := MeshInstance3D.new()
					var cbm := BoxMesh.new()
					cbm.size = Vector3.ONE * randf_range(0.8, 1.8)
					cb.mesh = cbm
					cb.material_override = Destructible.make_material(Color("#7cb8ff"), 0.7)
					root.add_child(cb)
					cb.global_position = mp + Vector3(randf_range(-10, 10), randf_range(-2, 3), randf_range(-10, 10))
					cb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			2:   # red room: tilted slabs jut from the floor
				for si2 in 6:
					var sl := MeshInstance3D.new()
					var slm := BoxMesh.new()
					slm.size = Vector3(2.4, 5.0, 0.5)
					sl.mesh = slm
					sl.material_override = Destructible.make_material(Color("#a03a3a"), 0.35)
					root.add_child(sl)
					sl.global_position = mp + Vector3(randf_range(-10, 10), -3.0, randf_range(-10, 10))
					sl.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
			3:   # green room: a ring of glowing orbs around the artifact
				for oi2 in 10:
					var ang3 := TAU * float(oi2) / 10.0
					var ob2 := MeshInstance3D.new()
					var obm := SphereMesh.new()
					obm.radius = 0.35
					obm.height = 0.7
					ob2.mesh = obm
					ob2.material_override = Destructible.make_material(Color("#4dff9a"), 2.0)
					root.add_child(ob2)
					ob2.global_position = mp + Vector3(cos(ang3) * 8.0, -2.0, sin(ang3) * 8.0)
		if k < pods - 1:
			# each pod's far door jumps to a pod you can't see -> feels non-euclidean
			var nxt := Gate.new().configure({
				"target": maze_base + Vector3(float(k + 1) * 400.0, -2, 0),
				"zone": "flat", "zone_g": 9.0, "label": "FOLD DOOR",
				"color": Color("#b388ff")})
			root.add_child(nxt)
			nxt.global_position = mp + Vector3(0, -4.0, -12)
		else:
			# beat all 4 rooms -> a BUTTON hands you the artifact
			var art := Gate.new().configure({
				"action": "artifact", "label": "CLAIM ARTIFACT [F]", "color": Color("#c22")})
			root.add_child(art)
			art.global_position = mp + Vector3(0, -4.0, -12)
			# the way back. nobody deserves to live in the hammer room.
			var ret := Gate.new().configure({
				"target": temple_spawn(), "zone": "flat", "zone_g": 9.0,
				"label": "WAY BACK", "color": Color("#ffe066")})
			root.add_child(ret)
			ret.global_position = mp + Vector3(0, -4.0, 12)
		# a guard per pod
		var e := Enemy.new()
		e.setup(5 + k, dummy_body, true)
		root.add_child(e)
		e.global_position = mp + Vector3(4, -3.0, 4)
	# maze entrance from the main hall
	var maze_in := Gate.new().configure({
		"target": maze_base + Vector3(0, -2, 0), "zone": "flat", "zone_g": 9.0,
		"requires": "trials_done",
		"label": "MAZE DOOR", "color": Color("#b388ff")})
	root.add_child(maze_in)
	maze_in.global_position = p + Vector3(-50, fy, -50)

static func temple_spawn() -> Vector3:
	return TEMPLE_POS + Vector3(0, 2, 10)

# --------------------------------------------------------- shadow temple

## THE PYRAMID'S INSIDE: a pocket realm, Euclid-temple rules -- small
## outside, cathedral inside, and the cathedral is ITSELF a pyramid:
## four brick slopes meeting at an apex over the dressed Menger shrine.
static func build_pyramid_interior(root: Node3D, exit_target: Vector3) -> void:
	pyramid_exit = exit_target
	var p := PYRAMID_POS
	var base := 96.0
	var hgt := 58.0
	var brick := Surfaces.stone(Color("#b5934f"))
	# floor
	var fl := StaticBody3D.new()
	var flm := MeshInstance3D.new()
	flm.mesh = Surfaces.box_mesh(Vector3(base + 8.0, 1.0, base + 8.0))
	flm.material_override = Surfaces.stone(Color("#8a7443"))
	fl.add_child(flm)
	var flc := CollisionShape3D.new()
	flc.shape = Surfaces.box_shape(Vector3(base + 8.0, 1.0, base + 8.0))
	fl.add_child(flc)
	root.add_child(fl)
	fl.global_position = p
	# the hall is ONE four-sided cone, seamless: same form as the
	# pyramid outside, walls visible from within, collidable everywhere
	var shell := StaticBody3D.new()
	var shm := MeshInstance3D.new()
	var scm9 := CylinderMesh.new()
	scm9.top_radius = 0.0
	scm9.bottom_radius = base * 0.62
	scm9.height = hgt
	scm9.radial_segments = 4
	shm.mesh = scm9
	var bsh9 := Shader.new()
	bsh9.code = """shader_type spatial;
render_mode cull_disabled;
varying vec2 buv;
void vertex(){ buv = UV; }
float h2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment(){
	vec2 uv = buv * vec2(36.0, 22.0);
	float row = floor(uv.y);
	uv.x += fract(row * 0.5);
	vec2 c = floor(uv);
	vec2 f = fract(uv);
	float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(1.0, 0.94, f.x)
		* smoothstep(0.0, 0.09, f.y) * smoothstep(1.0, 0.91, f.y);
	vec3 sand = vec3(0.71, 0.58, 0.33) * (0.82 + 0.18 * h2(c));
	ALBEDO = mix(vec3(0.45, 0.36, 0.22), sand, mortar);
	ROUGHNESS = 0.95;
}"""
	var swall := ShaderMaterial.new()
	swall.shader = bsh9
	shm.material_override = swall
	shell.add_child(shm)
	var shc9 := CollisionShape3D.new()
	var shcs := ConcavePolygonShape3D.new()
	shcs.backface_collision = true
	shcs.set_faces(scm9.get_faces())
	shc9.shape = shcs
	shell.add_child(shc9)
	root.add_child(shell)
	shell.global_position = p + Vector3(0, hgt * 0.5, 0)
	# cornice trim + corner pillars: no flat plastic down here
	for ci9 in 4:
		var ca9 := TAU * float(ci9) / 4.0 + PI / 4.0
		var pil := MeshInstance3D.new()
		var pm9 := CylinderMesh.new()
		pm9.top_radius = 0.7
		pm9.bottom_radius = 0.95
		pm9.height = 10.0
		pil.mesh = pm9
		pil.material_override = Surfaces.stone(Color("#96793e"))
		root.add_child(pil)
		pil.global_position = p + Vector3(cos(ca9) * base * 0.32, 5.0,
			sin(ca9) * base * 0.32)
	# the DRESSED shrine: stepped tiers, gold ring, the shrine itself
	for ti9 in 3:
		var tier := MeshInstance3D.new()
		tier.mesh = Surfaces.box_mesh(Vector3(9.0 - float(ti9) * 2.2, 0.6,
			9.0 - float(ti9) * 2.2))
		tier.material_override = Surfaces.stone(Color("#a08040"))
		root.add_child(tier)
		tier.global_position = p + Vector3(0, 0.8 + float(ti9) * 0.6, 0)
	var gring := MeshInstance3D.new()
	var grm := TorusMesh.new()
	grm.inner_radius = 5.2
	grm.outer_radius = 5.7
	gring.mesh = grm
	gring.material_override = Destructible.make_material(Color("#ffd166"), 1.1)
	root.add_child(gring)
	gring.global_position = p + Vector3(0, 0.7, 0)
	var shrine := MengerShrine.new()
	root.add_child(shrine)
	# the sponge is centered on its origin (spans +-3.5): seat it ON
	# the top tier, not waist-deep in the floor
	shrine.global_position = p + Vector3(0, 6.1, 0)
	# a warm hall light high under the apex
	var hl9 := OmniLight3D.new()
	hl9.light_color = Color("#ffcf8a")
	hl9.light_energy = 1.8
	hl9.omni_range = 90.0
	root.add_child(hl9)
	hl9.global_position = p + Vector3(0, hgt * 0.6, 0)
	# the hall's OWN air: a deep stone drone with a thin whistle far
	# above -- positional, so it exists only in here
	var amb := AudioStreamPlayer3D.new()
	amb.stream = _pyramid_air()
	amb.max_distance = 160.0
	amb.volume_db = -10.0
	amb.autoplay = true
	root.add_child(amb)
	amb.global_position = p + Vector3(0, 6.0, 0)
	# exit back to the sand
	var out := Gate.new().configure({
		"target": exit_target, "zone": "", "label": "EXIT",
		"color": Color("#ffe066")})
	root.add_child(out)
	out.global_position = p + Vector3(0, 0.5, base * 0.42)

## seamless 12s loop: every partial an integer cycle count
static func _pyramid_air() -> AudioStreamWAV:
	var rate := 22050
	var secs := 12.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var ts := float(i) / float(rate)
		var v := 0.12 * sin(TAU * (804.0 / secs) * ts) \
			* (0.6 + 0.4 * sin(TAU * ts / 12.0))
		v += 0.08 * sin(TAU * (1008.0 / secs) * ts)
		v += 0.02 * sin(TAU * (10800.0 / secs) * ts) \
			* (0.5 + 0.5 * sin(TAU * ts / 6.0 + 1.7))
		var s9 := int(clampf(v, -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav

static func pyramid_spawn() -> Vector3:
	return PYRAMID_POS + Vector3(0, 2.0, PYRAMID_POS.length() * 0.0 + 34.0)

static func build_shadow_temple(root: Node3D, dummy_body) -> void:
	var p := SHADOW_POS
	# barely-lit black temple floating in the dark
	_room(root, p, Vector3(90, 16, 90), Color("#060608"), 0.03)
	# the way IN: a gate bolted to the outer hull (park your ship, float over)
	var enter := Gate.new().configure({
		"target": p + Vector3(0, -5, 38), "zone": "flat", "zone_g": 9.0,
		"label": "SHADOW DOOR", "color": Color("#1a0a2a")})
	root.add_child(enter)
	enter.global_position = p + Vector3(0, 0, 46.5)
	# the way OUT (back to your ship)
	var leave := Gate.new().configure({
		"target": p + Vector3(0, 2, 52), "zone": "",
		"label": "EXIT DOOR", "color": Color("#1a0a2a")})
	root.add_child(leave)
	leave.global_position = p + Vector3(0, -7.0, 40)
	var tablet := Gate.new().configure({
		"action": "recipe", "label": "RECIPE TABLET", "color": Color("#3a0a0a")})
	root.add_child(tablet)
	tablet.global_position = p + Vector3(0, -7.0, -40)
	# --- a little maze between the door and the tablet ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337   # same maze every visit
	var n := 7
	var cell2 := 90.0 / float(n)
	var org := p + Vector3(-45, 0, -45)
	var wv: Array = []   # wv[i][j]: wall on x-boundary i, cell row j
	var wh: Array = []   # wh[i][j]: wall on z-boundary j, cell col i
	for i in n + 1:
		var row: Array = []
		for j in n:
			row.append(true)
		wv.append(row)
	for i in n:
		var row2: Array = []
		for j in n + 1:
			row2.append(true)
		wh.append(row2)
	var seen: Array = []
	for i in n:
		var row3: Array = []
		for j in n:
			row3.append(false)
		seen.append(row3)
	var stack: Array = [Vector2i(0, 0)]
	seen[0][0] = true
	while not stack.is_empty():
		var cc: Vector2i = stack.back()
		var opts: Array = []
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cc + dv
			if nb.x >= 0 and nb.x < n and nb.y >= 0 and nb.y < n and not seen[nb.x][nb.y]:
				opts.append(dv)
		if opts.is_empty():
			stack.pop_back()
			continue
		var dv2: Vector2i = opts[rng.randi() % opts.size()]
		var nb2: Vector2i = cc + dv2
		if dv2.x == 1:
			wv[cc.x + 1][cc.y] = false
		elif dv2.x == -1:
			wv[cc.x][cc.y] = false
		elif dv2.y == 1:
			wh[cc.x][cc.y + 1] = false
		else:
			wh[cc.x][cc.y] = false
		seen[nb2.x][nb2.y] = true
		stack.append(nb2)
	# a couple of loops so it isn't a pure dead-end crawl
	for i in 3:
		if rng.randi() % 2 == 0:
			wv[1 + rng.randi() % (n - 1)][rng.randi() % n] = false
		else:
			wh[rng.randi() % n][1 + rng.randi() % (n - 1)] = false
	var wcol := Color("#0d0a16")
	for i in range(1, n):        # interior x-boundary walls
		for j in n:
			if wv[i][j]:
				_wall_box(root, org + Vector3(float(i) * cell2, 0.0, (float(j) + 0.5) * cell2),
					Vector3(0.6, 16.2, cell2 + 0.6), wcol)
	for i in n:                  # interior z-boundary walls
		for j in range(1, n):
			if wh[i][j]:
				_wall_box(root, org + Vector3((float(i) + 0.5) * cell2, 0.0, float(j) * cell2),
					Vector3(cell2 + 0.6, 16.2, 0.6), wcol)
	for i in 3:
		var m := ShadowMonster.new()
		m.home = p
		root.add_child(m)
		# never near the door (door bay is at z=+38): deep-maze spawns only
		var mx := randf_range(-35, 35)
		var mz := randf_range(-35, 8)
		while Vector2(mx, mz).distance_to(Vector2(0, 38)) < 35.0:
			mx = randf_range(-35, 35)
			mz = randf_range(-35, 8)
		m.global_position = p + Vector3(mx, 3, mz)
	# faint markers
	for i in 6:
		var g := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.2
		gm.height = 0.4
		g.mesh = gm
		g.material_override = Destructible.make_material(Color("#301040"), 1.0)
		root.add_child(g)
		g.global_position = p + Vector3(randf_range(-35, 35), randf_range(1, 9), randf_range(-35, 35))

static func shadow_temple_spawn() -> Vector3:
	return SHADOW_POS + Vector3(0, 2, 38)

# --------------------------------------------------------------- helpers

## One solid maze wall.
static func _wall_box(root: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = Destructible.make_material(color, 0.06)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = size
	col.shape = cs
	body.add_child(col)
	root.add_child(body)
	body.global_position = center

## A lit box room: floor, ceiling, 4 walls (StaticBody3D), inner light.
static func _room(root: Node3D, center: Vector3, size: Vector3, color: Color, emit: float) -> void:
	var half := size * 0.5
	var walls := [
		[Vector3(size.x, 1, size.z), Vector3(0, -half.y, 0)],
		[Vector3(size.x, 1, size.z), Vector3(0, half.y, 0)],
		[Vector3(1, size.y, size.z), Vector3(-half.x, 0, 0)],
		[Vector3(1, size.y, size.z), Vector3(half.x, 0, 0)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, -half.z)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, half.z)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = w[0]
		mi.mesh = m
		mi.material_override = Destructible.make_material(color, emit)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = w[0]
		col.shape = cs
		body.add_child(col)
		root.add_child(body)
		body.global_position = center + w[1]
	var light := OmniLight3D.new()
	light.light_energy = 1.6
	light.omni_range = maxf(size.x, size.z) * 1.2
	root.add_child(light)
	light.global_position = center + Vector3(0, half.y - 2.0, 0)
