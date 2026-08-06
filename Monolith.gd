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

const RISE_DEPTH := 14.0
const ITEM_IDS := ["ytetra", "ltetra", "otetra", "btetra", "rtetra",
	"ptetra", "ctetra", "wtetra"]

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
	# 1. the tetrahedron flies in and seats itself
	var tet := MeshInstance3D.new()
	tet.mesh = MainframeComplex._tetra_mesh(0.42)
	tet.material_override = Destructible.make_material(col.lightened(0.2), 2.0)
	add_child(tet)
	tet.global_position = sock_pos + (bas * Vector3(0, 0, 1)) * 4.0
	var tw0 := create_tween()
	tw0.tween_property(tet, "global_position", sock_pos, 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("learn", -8.0)
	await tw0.finished
	_socket_tet = tet
	# 2. ULTIMA glow: the seated piece goes fluid, bloom cranks hard
	tet.material_override = DatamoshStudio._fluid_material(col)
	var glow := MeshInstance3D.new()
	var gm2 := SphereMesh.new()
	gm2.radius = 1.1
	gm2.height = 2.2
	glow.mesh = gm2
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	gmat.emission_enabled = true
	gmat.emission = col
	gmat.emission_energy_multiplier = 3.0
	glow.material_override = gmat
	add_child(glow)
	glow.global_position = sock_pos
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
	add_child(sp)
	sp.global_position = top + dir * 6.0
	sp.play()
	# 4. the SKY fills with turning triangles of the piece's color
	var skyp := Node3D.new()
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
	skytw.tween_property(skyp, "rotation:y", TAU, 40.0) \
		.from(0.0).as_relative()
	for t9 in tris:
		var st9 := create_tween().set_loops()
		st9.tween_property(t9, "rotation", Vector3(TAU, TAU * 0.7, 0), 9.0) \
			.as_relative()
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
		var twg2 := create_tween()
		twg2.tween_property(glow, "global_position",
			sock_pos - dir * RISE_DEPTH, 14.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await twl.finished
		_root.visible = false
		tet.visible = false
		glow.visible = false
	# 6. hologram of the NEXT planet, then the floor pictogram
	var nxt: String = Game.MONO_PLANETS[stage + 1] if stage + 1 < 8 else ""
	if nxt != "":
		var nb = Universe.body_named(nxt)
		var holo := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 5.0
		hm.height = 10.0
		holo.mesh = hm
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(col.r, col.g, col.b, 0.5)
		hmat.emission_enabled = true
		hmat.emission = col
		holo.material_override = hmat
		add_child(holo)
		holo.global_position = top + dir * 8.0
		var htw := create_tween()
		htw.tween_property(holo, "rotation:y", TAU * 2.0, 6.0).as_relative()
		Sfx.play("warp", -8.0)
		await get_tree().create_timer(4.5).timeout
		var ftw := create_tween()
		ftw.tween_property(hmat, "albedo_color:a", 0.0, 2.0)
		await ftw.finished
		holo.queue_free()
		_floor_glyph(top, bas, col)
	# 7. wind down: sky fades, bloom eases back
	await get_tree().create_timer(3.0).timeout
	for t9 in tris:
		var ftw2 := create_tween()
		ftw2.tween_property(t9, "scale", Vector3(0.01, 0.01, 0.01), 2.5)
	if env != null:
		var twg3 := create_tween()
		twg3.tween_property(env, "glow_intensity", old_glow, 3.0)
	await get_tree().create_timer(3.0).timeout
	skyp.queue_free()
	sp.queue_free()
	# 8. the chain advances -- for EVERYBODY
	Game.monolith_stage = stage + 1
	Net.broadcast_monolith(Game.monolith_stage)
	_flash("the %s stone remembers" % ["yellow", "lime", "orange", "blue",
		"red", "pink", "cyan", "white"][stage])
	var m9 = get_tree().current_scene
	if m9 != null and m9.has_method("_on_monolith_advanced"):
		m9._on_monolith_advanced()
	_busy = false

## the permanent scar: a no-collide pictogram of the next planet, flat
## in the ground where the monolith stood
func _floor_glyph(top: Vector3, bas: Basis, col: Color) -> void:
	var g := Node3D.new()
	add_child(g)
	g.global_transform = Transform3D(bas, top + dir * 0.06)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 3.4
	rm.outer_radius = 3.8
	ring.mesh = rm
	ring.material_override = Destructible.make_material(col, 1.4)
	g.add_child(ring)
	# lat/long etch: reads as "a planet", whatever the planet
	for i in 3:
		var band := MeshInstance3D.new()
		var bm2 := TorusMesh.new()
		bm2.inner_radius = 3.4 - 1.0 * float(i + 1) * 0.8
		bm2.outer_radius = bm2.inner_radius + 0.18
		band.mesh = bm2
		band.material_override = Destructible.make_material(col.darkened(0.2), 1.0)
		g.add_child(band)
	var bar := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(6.8, 0.06, 0.2)
	bar.mesh = bbm
	bar.material_override = Destructible.make_material(col.darkened(0.1), 1.1)
	g.add_child(bar)

func _env() -> Environment:
	for c in get_tree().current_scene.get_children():
		if c is WorldEnvironment:
			return (c as WorldEnvironment).environment
	return null
