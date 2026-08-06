class_name Monolith
extends Node3D
## One monolith of the chain. Nobody carved these -- each is a magical
## relation to the location of its piece. Feed it the RIGHT color of
## tetrahedron and: the piece sinks into the socket, the stone drinks
## the light, the sky fills with turning triangles, the monolith lowers
## into the ground, and a hologram of the NEXT planet burns itself into
## the floor. Then, somewhere else, the next monolith rises.

var stage: int = 0            # which link of the chain this is (0 = Harold)
var body = null               # Universe.Body it stands on
var dir: Vector3 = Vector3.UP
var risen := true             # false = still buried, waiting for its turn
var _root: Node3D = null      # the stone itself (lowered/raised/removed)
var _socket_tet: MeshInstance3D = null
var _busy := false
var _show_tweens: Array = []   # looped tweens killed at cleanup -- a
                               # freed target + set_loops = infinite-loop spam

const RISE_DEPTH := 14.0
const ITEM_IDS := ["ytetra", "ltetra", "otetra", "btetra", "rtetra",
	"ptetra", "ctetra", "wtetra"]

static var _crack_sh: Shader = null
static func _crack_shader() -> Shader:
	if _crack_sh != null:
		return _crack_sh
	_crack_sh = Shader.new()
	_crack_sh.code = """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec3 ccol = vec3(1.0, 0.82, 0.25);
uniform float intensity = 0.3;
uniform float fade = 0.0;
vec2 h2(vec2 p){
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
void fragment(){
	vec2 uv = UV * vec2(10.0, 5.0);
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h2(i + g);
			float d = length(g + o - f);
			if (d < f1) { f2 = f1; f1 = d; }
			else if (d < f2) { f2 = d; }
		}
	}
	float edge = 1.0 - smoothstep(0.0, 0.09, f2 - f1);
	ALBEDO = ccol;
	EMISSION = ccol * edge * 2.2 * intensity * fade;
	ALPHA = edge * intensity * fade * 0.9;
}
"""
	return _crack_sh

class MonoSocket extends StaticBody3D:
	var host: Monolith = null
	func use() -> void:
		if host != null:
			host.try_feed()

## Generic stele build (Earth onward). Harold keeps its bespoke
## monument; Main wires that one to a Monolith with an external root.
func build_stele(b, d: Vector3) -> void:
	body = b
	dir = d.normalized()
	stage = stage_of_planet(b.name)
	var bas := _bup(dir)
	_root = Node3D.new()
	add_child(_root)
	_root.global_transform = Transform3D(bas,
		(b.center as Vector3) + dir * float(b.radius))
	var col: Color = Game.MONO_COLORS[clampi(stage, 0, 7)]
	var stone := Surfaces.stone(Color("#8a7f70"))
	var dark := Surfaces.stone(Color("#6b6154"))
	for spec in [[Vector3(7.0, 2.0, 4.6), Vector3(0, 0.7, 0), 0.0],
			[Vector3(5.0, 1.6, 3.4), Vector3(0, 2.4, 0), 0.0],
			[Vector3(3.6, 0.6, 3.6), Vector3(0, 3.5, 0), 45.0],
			[Vector3(3.4, 3.8, 1.3), Vector3(0, 5.4, -0.8), 0.0],
			[Vector3(2.6, 0.7, 1.8), Vector3(0, 7.6, 0), 0.0]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = dark if float(spec[2]) > 0.0 else stone
		mi.position = spec[1]
		mi.rotation_degrees.y = float(spec[2])
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = spec[0]
		cs.shape = shp
		sb.add_child(cs)
		mi.add_child(sb)
		_root.add_child(mi)
	# the triangular socket mouth on the waist face
	var sock := MonoSocket.new()
	sock.host = self
	var smi := MeshInstance3D.new()
	smi.mesh = MainframeComplex._tetra_mesh(0.55)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.05, 0.05, 0.06)
	smi.material_override = smat
	sock.add_child(smi)
	var scs := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(1.4, 1.4, 1.0)
	scs.shape = sbs
	sock.add_child(scs)
	_root.add_child(sock)
	sock.position = Vector3(0, 5.4, 0.6)
	# the glyph ring hint: this stele wants THIS color
	var gl := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 0.75
	gm.outer_radius = 0.85
	gl.mesh = gm
	gl.material_override = Destructible.make_material(col, 1.2)
	_root.add_child(gl)
	gl.position = Vector3(0, 5.4, 0.62)
	gl.rotation_degrees.x = 90.0
	if not risen:
		_root.global_position = (b.center as Vector3) \
			+ dir * (float(b.radius) - RISE_DEPTH)

static func stage_of_planet(pname: String) -> int:
	return Game.MONO_PLANETS.find(pname)

static func _bup(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized()).orthonormalized()

## RISE: the buried stele grinds up out of the ground over ten seconds.
func rise() -> void:
	if risen or _root == null:
		return
	risen = true
	var tw := create_tween()
	tw.tween_property(_root, "global_position",
		(body.center as Vector3) + dir * float(body.radius), 10.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	Sfx.play("place", -6.0)

## F on the socket: feed it the right tetrahedron, run the whole show.
func try_feed() -> void:
	if _busy or not risen:
		return
	if Game.monolith_stage != stage:
		_flash("the stone is silent")
		Sfx.play("denied", -14.0)
		return
	var want: String = ITEM_IDS[stage]
	if Inventory.res_count(want) <= 0:
		_flash("the socket wants a %s tetrahedron" % ["yellow", "lime",
			"orange", "blue", "red", "pink", "cyan", "white"][stage])
		Sfx.play("denied", -14.0)
		return
	Inventory.remove_res(want, 1)
	activate()

func _flash(t: String) -> void:
	var m9 = get_tree().current_scene
	if m9 != null:
		var h9 = m9.get("_hud")
		if h9 != null:
			h9.flash(t)

## THE SEQUENCE. Runs on the monolith's own planet, ~26 seconds.
func activate() -> void:
	_busy = true
	var col: Color = Game.MONO_COLORS[stage]
	var bas := _bup(dir)
	var top: Vector3 = (body.center as Vector3) + dir * float(body.radius)
	var sock_pos: Vector3 = _root.global_transform \
		.translated_local(Vector3(0, 5.4, 0.9)).origin if _root != null else top
	# 1. the tetrahedron flies to the FRONT of the socket, then slides
	# INTO the mouth -- a real insertion, not a teleport
	var mbas: Basis = _root.global_transform.basis if _root != null else bas
	var mouth_out := mbas * Vector3(0, 0, 1)
	var tet := MeshInstance3D.new()
	tet.mesh = MainframeComplex._tetra_mesh(0.42)
	tet.material_override = Destructible.make_material(col.lightened(0.2), 2.0)
	add_child(tet)
	tet.global_position = sock_pos + mouth_out * 5.0 + (mbas * Vector3(0, 1, 0)) * 1.2
	var tw0 := create_tween()
	tw0.tween_property(tet, "global_position", sock_pos + mouth_out * 1.6, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("learn", -8.0)
	await tw0.finished
	# the slide IN: slow, deliberate, past the lip into the cavity
	var tw1 := create_tween()
	tw1.tween_property(tet, "global_position", sock_pos - mouth_out * 0.35, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw1.parallel().tween_property(tet, "rotation", tet.rotation
		+ mbas * Vector3(0, 0, 1) * 0.0 + Vector3(0.4, 0.9, 0.2), 1.8)
	await tw1.finished
	_socket_tet = tet
	# 2. seated: the piece ITSELF goes molten with the ultima fluid
	# treatment as the sound begins -- no stand-in glow ball
	tet.material_override = DatamoshStudio._fluid_material(col)
	var env := _env()
	var old_glow := 0.8
	if env != null:
		old_glow = env.glow_intensity
		var twg := create_tween()
		twg.tween_property(env, "glow_intensity", 2.6, 2.0)
	# 3. the black hole's voice, with ECHO
	var bus_idx := AudioServer.get_bus_index("MonolithEcho")
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "MonolithEcho")
		var rev := AudioEffectReverb.new()
		rev.wet = 0.6
		rev.room_size = 1.0
		AudioServer.add_bus_effect(bus_idx, rev)
		var dly := AudioEffectDelay.new()
		dly.tap1_active = true
		dly.tap1_delay_ms = 420.0
		dly.tap1_level_db = -8.0
		dly.tap2_active = true
		dly.tap2_delay_ms = 900.0
		dly.tap2_level_db = -16.0
		AudioServer.add_bus_effect(bus_idx, dly)
	var sp := AudioStreamPlayer3D.new()
	sp.stream = RadioLib.bh_presence()
	sp.bus = "MonolithEcho"
	sp.volume_db = -2.0
	sp.max_distance = 400.0
	sp.add_to_group("mono_sky")
	add_child(sp)
	sp.global_position = top + dir * 6.0
	sp.play()
	# 4. the SKY fills with turning triangles of the piece's color
	var skyp := Node3D.new()
	skyp.add_to_group("mono_sky")
	add_child(skyp)
	skyp.global_transform = Transform3D(bas, body.center as Vector3)
	var tris: Array = []
	for i in 36:
		var t9 := MeshInstance3D.new()
		t9.mesh = MainframeComplex._tetra_mesh(
			14.0 + 10.0 * fmod(float(i) * 0.618, 1.0))
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = col
		tmat.emission_enabled = true
		tmat.emission = col
		skyp.add_child(t9)
		t9.material_override = tmat
		var ph := TAU * float(i) / 36.0
		var lat := -0.9 + 1.8 * fmod(float(i) * 0.382, 1.0)
		t9.position = Vector3(cos(ph) * cos(lat), sin(lat),
			sin(ph) * cos(lat)) * (float(body.radius) + 320.0)
		tris.append(t9)
	# second ring, counter-turning, smaller and brighter -- the sky gets
	# DEPTH: two shells of triangles wheeling against each other, each
	# piece breathing light
	for i in 20:
		var t9 := MeshInstance3D.new()
		t9.mesh = MainframeComplex._tetra_mesh(
			7.0 + 6.0 * fmod(float(i) * 0.618, 1.0))
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = col.lightened(0.35)
		tmat.emission_enabled = true
		tmat.emission = col.lightened(0.2)
		var t2 := Node3D.new()
		skyp.add_child(t2)
		t2.add_child(t9)
		t9.material_override = tmat
		var ph2 := TAU * float(i) / 20.0
		var lat2 := -0.6 + 1.2 * fmod(float(i) * 0.382, 1.0)
		t9.position = Vector3(cos(ph2) * cos(lat2), sin(lat2),
			sin(ph2) * cos(lat2)) * (float(body.radius) + 210.0)
		tris.append(t9)
		var brt := create_tween().set_loops()
		_show_tweens.append(brt)
		brt.tween_property(tmat, "emission_energy_multiplier", 2.6,
			1.6 + 0.8 * fmod(float(i) * 0.7, 1.0)).from(0.7) \
			.set_trans(Tween.TRANS_SINE)
		brt.tween_property(tmat, "emission_energy_multiplier", 0.7,
			1.6 + 0.8 * fmod(float(i) * 0.7, 1.0)).set_trans(Tween.TRANS_SINE)
		var ctw := create_tween().set_loops()
		_show_tweens.append(ctw)
		ctw.tween_property(t2, "rotation:y", -TAU, 28.0).as_relative()
	var skytw := create_tween().set_loops()
	_show_tweens.append(skytw)
	skytw.tween_property(skyp, "rotation:y", TAU, 40.0) \
		.from(0.0).as_relative()
	for t9 in tris:
		var st9 := create_tween().set_loops()
		_show_tweens.append(st9)
		st9.tween_property(t9, "rotation", Vector3(TAU, TAU * 0.7, 0), 9.0) \
			.as_relative()
	# THE CRACKS: glowing fractures spread across the sky in the piece's
	# color -- brighter with every monolith fed. At the eighth the sky
	# is meant to SHATTER and take the universe boundary with it (that
	# finale is planned, not yet staged -- the boundary already yields
	# once monolith_stage hits 8).
	var crack := MeshInstance3D.new()
	var ckm := SphereMesh.new()
	ckm.radius = float(body.radius) + 600.0
	ckm.height = ckm.radius * 2.0
	ckm.radial_segments = 32
	ckm.rings = 16
	crack.mesh = ckm
	var cksh := _crack_shader()
	var ckmat := ShaderMaterial.new()
	ckmat.shader = cksh
	ckmat.set_shader_parameter("ccol", Vector3(col.r, col.g, col.b))
	ckmat.set_shader_parameter("intensity",
		0.25 + 0.75 * float(stage + 1) / 8.0)
	crack.material_override = ckmat
	crack.add_to_group("mono_sky")
	add_child(crack)
	crack.global_position = body.center as Vector3
	var cktw := create_tween()
	cktw.tween_method(func(v: float) -> void:
		ckmat.set_shader_parameter("fade", v), 0.0, 1.0, 2.5)
	# 5. the monolith lowers into the ground while all of it happens
	if _root != null:
		var twl := create_tween()
		twl.tween_property(_root, "global_position",
			(body.center as Vector3) + dir * (float(body.radius) - RISE_DEPTH),
			14.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var twt := create_tween()
		twt.tween_property(tet, "global_position",
			sock_pos - dir * RISE_DEPTH, 14.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await twl.finished
		_root.visible = false
		tet.visible = false
	# 6. hologram: a PROJECTOR PUCK left in the ground beams up a flat
	# 2D pictogram of the next planet -- ring, latitude bands, a bar --
	# in the piece's color, with a visible cone of light from the
	# emitter. Fades, then burns the same pictogram into the floor.
	var nxt: String = Game.MONO_PLANETS[stage + 1] if stage + 1 < 8 else ""
	if nxt != "":
		var puck := MeshInstance3D.new()
		var pkm := CylinderMesh.new()
		pkm.top_radius = 0.5
		pkm.bottom_radius = 0.7
		pkm.height = 0.4
		puck.mesh = pkm
		puck.material_override = Surfaces.metal(Color("#12161c"))
		add_child(puck)
		puck.global_transform = Transform3D(bas, top + dir * 0.2)
		var cone := MeshInstance3D.new()
		var cnm := CylinderMesh.new()
		cnm.top_radius = 3.6
		cnm.bottom_radius = 0.3
		cnm.height = 7.0
		cone.mesh = cnm
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.albedo_color = Color(col.r, col.g, col.b, 0.10)
		cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material_override = cmat
		add_child(cone)
		cone.global_transform = Transform3D(bas, top + dir * 3.9)
		var holo := Node3D.new()
		add_child(holo)
		holo.global_transform = Transform3D(bas, top + dir * 7.6)
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(col.r, col.g, col.b, 0.75)
		hmat.emission_enabled = true
		hmat.emission = col
		_planet_pictogram(holo, hmat, nxt)
		var htw := create_tween()
		htw.tween_property(holo, "rotation:y", TAU * 2.0, 6.0).as_relative()
		Sfx.play("warp", -8.0)
		await get_tree().create_timer(4.5).timeout
		var ftw := create_tween()
		ftw.tween_property(hmat, "albedo_color:a", 0.0, 2.0)
		ftw.parallel().tween_property(cmat, "albedo_color:a", 0.0, 2.0)
		await ftw.finished
		holo.queue_free()
		cone.queue_free()
		_floor_glyph(top, bas, col)
		# 7. the AFTERMATH lingers: bloom eases back now, but the triangles
	# keep wheeling and the cracks keep glowing for six more minutes,
	# fading out so slowly you only notice when they are gone. The
	# sound stays too -- quieter, coming off the planet.
	if env != null:
		var twg3 := create_tween()
		twg3.tween_property(env, "glow_intensity", old_glow, 3.0)
	var svtw := create_tween()
	svtw.tween_property(sp, "volume_db", -16.0, 4.0)
	var cktw2 := create_tween()
	cktw2.tween_method(func(v: float) -> void:
		if is_instance_valid(crack):
			ckmat.set_shader_parameter("fade", v), 1.0, 0.0, 360.0)
	for t9 in tris:
		var ftw2 := create_tween()
		ftw2.tween_property(t9, "scale", Vector3(0.01, 0.01, 0.01), 360.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var cleanup := create_tween()
	cleanup.tween_interval(362.0)
	cleanup.tween_callback(func() -> void:
		for tw9 in _show_tweens:
			if tw9 != null and (tw9 as Tween).is_valid():
				(tw9 as Tween).kill()
		_show_tweens.clear()
		if is_instance_valid(skyp):
			skyp.queue_free()
		if is_instance_valid(sp):
			sp.queue_free()
		if is_instance_valid(crack):
			crack.queue_free())
	# 8. the chain advances -- for EVERYBODY
	Game.monolith_stage = stage + 1
	Net.broadcast_monolith(Game.monolith_stage)
	# the noodle god HATES this. and the closer the chain gets to
	# breaking the universe, the harder he takes it.
	Game.anger(10.0 + 8.0 * float(stage))
	_flash("the %s stone remembers" % ["yellow", "lime", "orange", "blue",
		"red", "pink", "cyan", "white"][stage])
	var m9 = get_tree().current_scene
	if m9 != null and m9.has_method("_on_monolith_advanced"):
		m9._on_monolith_advanced()
	_busy = false

## CHEAT/demo: only the sky show -- both triangle shells + the cracks,
## thirty seconds, then gone (the node frees itself).
func sky_only(col: Color) -> void:
	var bas := _bup(dir)
	var skyp := Node3D.new()
	skyp.add_to_group("mono_sky")
	add_child(skyp)
	skyp.global_transform = Transform3D(bas, body.center as Vector3)
	var tris: Array = []
	for i in 36:
		var t9 := MeshInstance3D.new()
		t9.mesh = MainframeComplex._tetra_mesh(
			14.0 + 10.0 * fmod(float(i) * 0.618, 1.0))
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = col
		tmat.emission_enabled = true
		tmat.emission = col
		skyp.add_child(t9)
		t9.material_override = tmat
		var ph := TAU * float(i) / 36.0
		var lat := -0.9 + 1.8 * fmod(float(i) * 0.382, 1.0)
		t9.position = Vector3(cos(ph) * cos(lat), sin(lat),
			sin(ph) * cos(lat)) * (float(body.radius) + 320.0)
		tris.append(t9)
	var skytw := create_tween().set_loops()
	_show_tweens.append(skytw)
	skytw.tween_property(skyp, "rotation:y", TAU, 40.0).from(0.0).as_relative()
	for t9 in tris:
		var st9 := create_tween().set_loops()
		_show_tweens.append(st9)
		st9.tween_property(t9, "rotation", Vector3(TAU, TAU * 0.7, 0), 9.0) \
			.as_relative()
	var crack := MeshInstance3D.new()
	var ckm := SphereMesh.new()
	ckm.radius = float(body.radius) + 600.0
	ckm.height = ckm.radius * 2.0
	ckm.radial_segments = 32
	ckm.rings = 16
	crack.mesh = ckm
	var ckmat := ShaderMaterial.new()
	ckmat.shader = _crack_shader()
	ckmat.set_shader_parameter("ccol", Vector3(col.r, col.g, col.b))
	ckmat.set_shader_parameter("intensity", 0.25 + 0.75 * float(stage + 1) / 8.0)
	ckmat.set_shader_parameter("fade", 1.0)
	crack.material_override = ckmat
	crack.add_to_group("mono_sky")
	add_child(crack)
	crack.global_position = body.center as Vector3
	var cleanup := create_tween()
	cleanup.tween_interval(30.0)
	cleanup.tween_callback(func() -> void:
		for tw9 in _show_tweens:
			if tw9 != null and (tw9 as Tween).is_valid():
				(tw9 as Tween).kill()
		queue_free())

## the flat 2D planet pictogram: outline ring, three latitude bands,
## an equator bar. Drawn in the XZ plane of its parent, engraved-bar
## style like the Harold glyphs.
func _planet_pictogram(parent: Node3D, mat: Material,
		pname: String = "") -> void:
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 3.3
	rm.outer_radius = 3.6
	ring.mesh = rm
	ring.material_override = mat
	parent.add_child(ring)
	if pname != "Earth":
		for i in 3:
			var band := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			var half := sqrt(maxf(0.1, 3.3 * 3.3 - pow(1.1 * float(i + 1), 2.0)))
			bm2.size = Vector3(half * 2.0, 0.06, 0.22)
			band.mesh = bm2
			band.material_override = mat
			band.position = Vector3(0, 0, -1.1 * float(i + 1))
			parent.add_child(band)
			if i > 0:
				var band2 := MeshInstance3D.new()
				band2.mesh = bm2
				band2.material_override = mat
				band2.position = Vector3(0, 0, 1.1 * float(i))
				parent.add_child(band2)
	if pname == "Earth":
		# EARTH: the bands become continents -- clustered land blobs,
		# one long diagonal, a small moon dot off the rim
		for lb9 in [[Vector3(1.6, 0.06, 0.9), Vector3(-1.2, 0, -0.9), 25.0],
				[Vector3(1.1, 0.06, 0.7), Vector3(-1.7, 0, 0.9), -15.0],
				[Vector3(2.0, 0.06, 1.1), Vector3(1.1, 0, -0.5), -30.0],
				[Vector3(1.3, 0.06, 0.8), Vector3(1.5, 0, 1.2), 10.0],
				[Vector3(0.8, 0.06, 0.5), Vector3(0.1, 0, 1.9), 40.0]]:
			var land := MeshInstance3D.new()
			land.mesh = Surfaces.box_mesh(lb9[0] as Vector3)
			land.material_override = mat
			land.position = lb9[1] as Vector3
			land.rotation_degrees.y = float(lb9[2])
			parent.add_child(land)
		var moon := MeshInstance3D.new()
		var mm9 := CylinderMesh.new()
		mm9.top_radius = 0.35
		mm9.bottom_radius = 0.35
		mm9.height = 0.06
		moon.mesh = mm9
		moon.material_override = mat
		moon.position = Vector3(4.6, 0, -1.4)
		parent.add_child(moon)
	else:
		var bar := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(6.6, 0.06, 0.26)
		bar.mesh = bbm
		bar.material_override = mat
		parent.add_child(bar)

## the permanent scar: the same pictogram, burned flat into the ground
## where the monolith stood
func _floor_glyph(top: Vector3, bas: Basis, col: Color) -> void:
	var g := Node3D.new()
	add_child(g)
	g.global_transform = Transform3D(bas, top + dir * 0.06)
	_planet_pictogram(g, Destructible.make_material(col, 1.4),
		Game.MONO_PLANETS[stage + 1] if stage + 1 < 8 else "")

func _env() -> Environment:
	for c in get_tree().current_scene.get_children():
		if c is WorldEnvironment:
			return (c as WorldEnvironment).environment
	return null
