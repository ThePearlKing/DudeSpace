class_name ModSynth
extends Machine
## THE MODULAR SYNTHESIZER. A real eurorack case bolted to a stand: three
## rows of panels from three different houses, every knob and jack on the
## panel where the editor says it is, and the patch cables you drew in
## the editor hanging off the FRONT of the case in the world.
##
## It eats electricity, and it will not power on without an ultima core
## seated and a uranium cell in the holder -- the crystal keeps the
## clock honest, the cell runs the rails. Break the case and you get
## both back.
##
## F opens the patch editor. The sound is DSP, not samples: see
## SynthEngine. It only bothers to run while somebody is near enough to
## hear it.

const HEAR_RANGE := 700.0
const BASE_DRAIN := 1.4          # EU/s just being switched on
const PER_MOD_DRAIN := 0.11      # ...and per module in the rack

const RW := 1.82                 # Mk1 rack front width, metres (84 HP)
const GAPU := 10.0               # gap between rows, panel units
const PX := 3.2                  # panel texture pixels per panel unit

## The Mk2 case: twice the width, one more row. Same panels, same
## engine, four times the rack.
var mk2: bool = false
var _rw: float = RW
var _px: float = PX
var _paint_t: float = 0.0            # counts down to the next panel repaint

var engine: SynthEngine = null
var core_ultima: bool = false
var core_uranium: bool = false
var powered: bool = false

var _rack: Node3D
var _vp: SubViewport
var _paint: Control
var _screen: MeshInstance3D
var _hw: MeshInstance3D          # knobs + jacks, one batched mesh
var _cables: MeshInstance3D      # the patch, in the world
var _seen_version: int = -1
var _cable_alpha_shown: float = 1.0
var _ply: AudioStreamPlayer3D
var _gen: AudioStreamGenerator
var _near: bool = false
var _warn_cd: float = 0.0
var _core_u_mesh: MeshInstance3D
var _core_n_mesh: MeshInstance3D
var _rebuild_cd: float = 0.0
## Broadcasting. `listeners` is set by the radios currently tuned in --
## a rack with an audience keeps running even with nobody standing at it.
var listeners: int = 0
var on_air_freq: float = -1.0
var station_name: String = "DUDE FM"
var _air_t: float = 0.0
var _claimed_want: float = -1.0
var _claimed_name: String = ""

var _s_m: float = RW / (float(SynthMods.ROW_HP) * SynthMods.HPW)
var _rows: int = SynthMods.ROWS
var _rowhp: int = SynthMods.ROW_HP
var _rh: float = 0.0

func _init() -> void:
	title = "MODULAR SYNTH"
	box_color = Color("#1e2128")
	box_size = Vector3(2.05, 1.86, 0.62)
	refund_id = "modsynth"
	shows_in = false
	shows_out = false
	buf_cap = 600.0

func _ready() -> void:
	# the Mk2 is a bigger BOX, so its dimensions have to be settled
	# before Machine builds the chassis
	if mk2:
		title = "MODULAR SYNTH MK2"
		refund_id = "modsynth2"
		_rows = SynthMods.ROWS + 1
		_rowhp = SynthMods.ROW_HP * 2
		_rw = RW * 2.0
		_px = PX * 0.72          # same panel size on screen, sane texture
		box_size = Vector3(4.1, 2.32, 0.66)
		buf_cap = 1400.0
	_s_m = _rw / (float(_rowhp) * SynthMods.HPW)
	_rh = (float(_rows) * SynthMods.PANEL_H
		+ float(_rows - 1) * GAPU) * _s_m
	super._ready()
	add_to_group("modsynth")
	engine = SynthEngine.new()
	engine.rows = _rows
	engine.row_hp = _rowhp
	# a restored case comes back with its patch; a fresh one ships with
	# the factory rack already making music
	var saved = get_meta("synth_data") if has_meta("synth_data") else null
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		apply_data(saved)
	if engine.mods.is_empty():
		engine.default_patch()
	dress_industrial(Color("#14161b"))
	_build_case()
	_build_rack()
	_ensure_bus()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = SynthEngine.SR
	# keep the generator buffer SHORT: every queued frame is latency you
	# hear as the panel running ahead of the sound. 70 ms is under a
	# 16th note at any sane tempo and the DSP thread fills it easily.
	_gen.buffer_length = 0.07
	_ply = AudioStreamPlayer3D.new()
	_ply.stream = _gen
	_ply.bus = "SynthFX"
	_ply.unit_size = 26.0
	_ply.max_distance = 500.0
	_ply.max_db = -2.0
	add_child(_ply)

static func _ensure_bus() -> void:
	if AudioServer.get_bus_index("SynthFX") != -1:
		return
	AudioServer.add_bus()
	var bi := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bi, "SynthFX")
	AudioServer.set_bus_send(bi, "Master")
	AudioServer.set_bus_volume_db(bi, linear_to_db(
		clampf(Settings.radio_vol, 0.0005, 1.0)))

func _exit_tree() -> void:
	Airwaves.release(self)
	if engine != null:
		engine.running = false
		engine.stop()

# ---------------------------------------------------------------- the box

func _build_case() -> void:
	var hx := box_size.x * 0.5
	# --- wooden cheeks either side, because every rack has them
	for sx in [-1.0, 1.0]:
		var cheek := BoxMesh.new()
		cheek.size = Vector3(0.11, box_size.y * 0.95, box_size.z + 0.12)
		part(cheek, Vector3(sx * (hx - 0.02), box_size.y * 0.5, 0.02),
			Color("#5a3f28"), 0.02)
		for i in 3:
			var grain := BoxMesh.new()
			grain.size = Vector3(0.115, 0.02, box_size.z + 0.13)
			part(grain, Vector3(sx * (hx - 0.02), 0.28 + float(i) * 0.38, 0.02),
				Color("#43301e"), 0.02)
	# --- top plate + two monitor speakers, which is where the sound is
	var top := BoxMesh.new()
	top.size = Vector3(box_size.x + 0.06, 0.07, box_size.z + 0.16)
	part(top, Vector3(0, box_size.y + 0.03, 0.02), Color("#191c22"), 0.05)
	for sx2 in [-1.0, 1.0]:
		var cab := BoxMesh.new()
		cab.size = Vector3(0.34, 0.4, 0.3)
		part(cab, Vector3(sx2 * (hx - 0.24), box_size.y + 0.27, 0.0),
			Color("#2a2018"), 0.03)
		var grille := BoxMesh.new()
		grille.size = Vector3(0.27, 0.31, 0.02)
		part(grille, Vector3(sx2 * (hx - 0.24), box_size.y + 0.27, 0.16),
			Color("#0c0e12"), 0.02)
		for gy in 7:
			var slat := BoxMesh.new()
			slat.size = Vector3(0.26, 0.012, 0.006)
			part(slat, Vector3(sx2 * (hx - 0.24), box_size.y + 0.14 + float(gy) * 0.042, 0.172),
				Color("#22262e"), 0.02)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.075
		cone.bottom_radius = 0.045
		cone.height = 0.03
		part(cone, Vector3(sx2 * (hx - 0.24), box_size.y + 0.27, 0.178),
			Color("#15181e"), 0.03, Vector3(90, 0, 0))
	# --- power inlet + the two cores, down on the left cheek face
	var inlet := BoxMesh.new()
	inlet.size = Vector3(0.16, 0.12, 0.06)
	part(inlet, Vector3(-hx + 0.28, 0.14, box_size.z * 0.5 + 0.02),
		Color("#101318"), 0.02)
	for i in 3:
		var pin := CylinderMesh.new()
		pin.top_radius = 0.014
		pin.bottom_radius = 0.014
		pin.height = 0.03
		part(pin, Vector3(-hx + 0.24 + float(i) * 0.04, 0.14, box_size.z * 0.5 + 0.05),
			Color("#c8b06a"), 0.15, Vector3(90, 0, 0))
	# ULTIMA CORE socket
	var sock := CylinderMesh.new()
	sock.top_radius = 0.09
	sock.bottom_radius = 0.09
	sock.height = 0.05
	part(sock, Vector3(hx - 0.5, 0.15, box_size.z * 0.5 + 0.015),
		Color("#0e1116"), 0.02, Vector3(90, 0, 0))
	_core_u_mesh = MeshInstance3D.new()
	var oct := SphereMesh.new()
	oct.radius = 0.062
	oct.height = 0.16
	oct.radial_segments = 6
	oct.rings = 3
	_core_u_mesh.mesh = oct
	_core_u_mesh.position = Vector3(hx - 0.5, 0.15, box_size.z * 0.5 + 0.06)
	_core_u_mesh.material_override = Surfaces.portal(Color("#7df9ff"))
	add_child(_core_u_mesh)
	# URANIUM CELL holder
	var hold := BoxMesh.new()
	hold.size = Vector3(0.13, 0.2, 0.07)
	part(hold, Vector3(hx - 0.24, 0.16, box_size.z * 0.5 + 0.02),
		Color("#0e1116"), 0.02)
	_core_n_mesh = MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.035
	rod.bottom_radius = 0.035
	rod.height = 0.17
	_core_n_mesh.mesh = rod
	_core_n_mesh.position = Vector3(hx - 0.24, 0.16, box_size.z * 0.5 + 0.055)
	_core_n_mesh.material_override = Destructible.make_material(Color("#5aff3a"), 2.4)
	add_child(_core_n_mesh)
	# --- the stand: legs and a cross brace, so it isn't a floating slab
	for sx3 in [-1.0, 1.0]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.09, 0.1, 0.5)
		part(leg, Vector3(sx3 * (hx - 0.1), 0.05, -0.18), Color("#14161b"), 0.02)

## Three rows of panels on a leaning frame, with the panel ART rendered
## from the very same painter the editor uses.
func _build_rack() -> void:
	_rack = Node3D.new()
	# lean, but only as far as the case front allows -- at 11 degrees the
	# top row sank INTO the cabinet box and rendered black
	_rack.position = Vector3(0, box_size.y * 0.52, box_size.z * 0.5 + 0.1)
	_rack.rotation_degrees.x = -5.0
	add_child(_rack)
	# frame + rails
	var back := BoxMesh.new()
	back.size = Vector3(_rw + 0.1, _rh + 0.11, 0.05)
	var bmi := MeshInstance3D.new()
	bmi.mesh = back
	bmi.position = Vector3(0, 0, -0.03)
	bmi.material_override = Surfaces.metal(Color("#101318"))
	_rack.add_child(bmi)
	for r in _rows:
		var ry := _rh * 0.5 - (float(r) * (SynthMods.PANEL_H + GAPU)) * _s_m
		for e in [0.0, -SynthMods.PANEL_H * _s_m]:
			var rail := BoxMesh.new()
			rail.size = Vector3(_rw + 0.02, 0.022, 0.03)
			var rmi := MeshInstance3D.new()
			rmi.mesh = rail
			rmi.position = Vector3(0, ry + e, 0.012)
			rmi.material_override = Surfaces.metal(Color("#8e97a6"))
			_rack.add_child(rmi)
	# the panel art: one viewport, painted by SynthPaint, live when close
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(float(_rowhp) * SynthMods.HPW * _px),
		int((float(_rows) * SynthMods.PANEL_H
			+ float(_rows - 1) * GAPU) * _px))
	_vp.transparent_bg = false
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_paint = Control.new()
	_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint.draw.connect(_draw_panels)
	_vp.add_child(_paint)
	_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(_rw, _rh)
	_screen.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _vp.get_texture()
	sm.emission_enabled = true
	sm.emission_texture = _vp.get_texture()
	sm.emission_energy_multiplier = 0.55
	sm.roughness = 0.75
	_screen.mesh.material = sm
	_screen.position = Vector3(0, 0, 0.004)
	_rack.add_child(_screen)
	_hw = MeshInstance3D.new()
	_rack.add_child(_hw)
	_cables = MeshInstance3D.new()
	_cables.position = Vector3(0, 0, 0.0)
	_rack.add_child(_cables)
	_rebuild_3d()

func _draw_panels() -> void:
	var sz := _vp.size
	_paint.draw_rect(Rect2(Vector2.ZERO, Vector2(sz)), Color("#0b0d11"))
	# empty rack space still looks like rack space
	for r in _rows:
		var y0 := float(r) * (SynthMods.PANEL_H + GAPU) * _px
		_paint.draw_rect(Rect2(Vector2(0, y0),
			Vector2(float(sz.x), SynthMods.PANEL_H * _px)), Color("#16191f"))
		for i in int(float(_rowhp) / 4.0):
			var xx := float(i) * SynthMods.HPW * 4.0 * _px
			_paint.draw_line(Vector2(xx, y0), Vector2(xx, y0 + SynthMods.PANEL_H * _px),
				Color(1, 1, 1, 0.03), 1.0)
	for mi in engine.mods.size():
		var m = engine.mods[mi]
		var org := Vector2(float(m.hp) * SynthMods.HPW * _px,
			float(m.row) * (SynthMods.PANEL_H + GAPU) * _px)
		SynthPaint.draw_module(_paint, m, org, _px, engine, mi)

# ------------------------------------------------------- panel to world

## Panel-space point (absolute panel units, origin top-left of the rack)
## to a position in the rack's local frame.
func _panel_pt(px: float, py: float, z: float = 0.0) -> Vector3:
	return Vector3(-_rw * 0.5 + px * _s_m, _rh * 0.5 - py * _s_m, z)

func _mod_org(m) -> Vector2:
	return Vector2(float(m.hp) * SynthMods.HPW,
		float(m.row) * (SynthMods.PANEL_H + GAPU))

func jack_local(mi: int, is_input: bool, ji: int) -> Vector3:
	var m = engine.mods[mi]
	var lay := SynthMods.layout(m.id)
	var arr: Array = lay["jin"] if is_input else lay["jout"]
	if ji >= arr.size():
		return Vector3.ZERO
	var org := _mod_org(m)
	var p: Vector2 = arr[ji]
	return _panel_pt(org.x + p.x, org.y + p.y, 0.028)

## Real hardware on top of the art: knob bodies, jack sockets, and the
## cables, all batched into three meshes so the case is cheap to draw.
func _rebuild_3d() -> void:
	var stw := SurfaceTool.new()
	stw.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mi in engine.mods.size():
		var m = engine.mods[mi]
		var d := SynthMods.def(m.id)
		var lay := SynthMods.layout(m.id)
		var stl := SynthMods.brand_style(m.brand)
		var org := _mod_org(m)
		# the LAYOUT decides what is on the faceplate: a desk draws its
		# own faders, so its knobs are never placed
		for ki in (lay["knobs"] as Array).size():
			var kp: Vector2 = lay["knobs"][ki]
			var c := _panel_pt(org.x + kp.x, org.y + kp.y, 0.006)
			# each house cuts its knobs differently: turned round (dude),
			# faceted hex (icosa), squared stone (monolithic)
			var kseg: int = 10 if m.brand == "dude" else (6 if m.brand == "icos" else 4)
			_cyl(stw, c, SynthMods.KNOB_R * _s_m, 0.017, stl["knob"], kseg)
			_cyl(stw, c + Vector3(0, 0, 0.017), SynthMods.KNOB_R * _s_m * 0.62,
				0.006, stl["cap"], kseg)
			var ang: float = PI * 0.75 + TAU * 0.75 \
				* clampf(m.p[ki] if ki < m.p.size() else 0.0, 0.0, 1.0)
			var tip := c + Vector3(cos(ang), -sin(ang), 0.0) * (SynthMods.KNOB_R * _s_m * 0.7)
			_cyl(stw, tip + Vector3(0, 0, 0.018), 0.006, 0.006, stl["pointer"])
		for pass_i in 2:
			var arr: Array = lay["jin"] if pass_i == 0 else lay["jout"]
			for ji in arr.size():
				var jp: Vector2 = arr[ji]
				var c2 := _panel_pt(org.x + jp.x, org.y + jp.y, 0.004)
				var jseg: int = 10 if m.brand == "dude" else (6 if m.brand == "icos" else 4)
				_cyl(stw, c2, SynthMods.JACK_R * _s_m * 1.6, 0.008, stl["ring"], jseg)
				_cyl(stw, c2 + Vector3(0, 0, 0.008), SynthMods.JACK_R * _s_m * 0.8,
					0.004, Color("#07090c"), 8)
	var mesh := stw.commit()
	_hw.mesh = mesh
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.45
	hm.metallic = 0.35
	_hw.material_override = hm
	_rebuild_cables()

## The patch, physically: cables that leave the panel, sag, and plug in.
func _rebuild_cables() -> void:
	var stc := SurfaceTool.new()
	stc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in engine.cables:
		var sm := int(c["sm"])
		var dm := int(c["dm"])
		if sm >= engine.mods.size() or dm >= engine.mods.size():
			continue
		var a := jack_local(sm, false, int(c["so"]))
		var b := jack_local(dm, true, int(c["di"]))
		var col: Color = SynthEngine.CABLE_COLS[int(c["col"]) % SynthEngine.CABLE_COLS.size()]
		# plug barrels
		_cyl(stc, a, 0.016, 0.03, col.darkened(0.5))
		_cyl(stc, b, 0.016, 0.03, col.darkened(0.5))
		var dist := a.distance_to(b)
		var sag := minf(0.12, 0.03 + dist * 0.16)
		var pts: Array[Vector3] = []
		for i in 11:
			var t := float(i) / 10.0
			var p: Vector3 = a.lerp(b, t)
			p.y -= sin(PI * t) * sag
			p.z += 0.014 + sin(PI * t) * (0.012 + dist * 0.03)
			pts.append(p)
		for i in pts.size() - 1:
			_tube(stc, pts[i], pts[i + 1], 0.0075, col)
		any = true
	if any:
		_cables.mesh = stc.commit()
	else:
		_cables.mesh = null
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.6
	# the cables on the real machine fade with the same setting as the
	# ones in the editor, so the case matches what you patched
	var ca2: float = clampf(Settings.cable_alpha, 0.12, 1.0)
	if ca2 < 0.99:
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.albedo_color = Color(1, 1, 1, ca2)
	_cables.material_override = cm
	_cable_alpha_shown = ca2

## A short cylinder standing off the panel along +Z.
func _cyl(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color,
		seg: int = 10) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, 0)
		var q0 := p0 + Vector3(0, 0, h)
		var q1 := p1 + Vector3(0, 0, h)
		var top := c + Vector3(0, 0, h)
		for tri in [[p0, p1, q1], [p0, q1, q0], [top, q0, q1]]:
			for v in tri:
				st.set_color(col)
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(v)

## A four-sided tube segment: enough to read as a cable, cheap enough
## to have thirty of them.
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var dir := (b - a)
	if dir.length() < 0.0001:
		return
	dir = dir.normalized()
	var up := Vector3(0, 0, 1) if absf(dir.z) < 0.9 else Vector3(0, 1, 0)
	var s1 := dir.cross(up).normalized() * r
	var s2 := dir.cross(s1).normalized() * r
	for i in 4:
		var a0 := TAU * float(i) / 4.0
		var a1 := TAU * float(i + 1) / 4.0
		var o0 := s1 * cos(a0) + s2 * sin(a0)
		var o1 := s1 * cos(a1) + s2 * sin(a1)
		for tri in [[a + o0, a + o1, b + o1], [a + o0, b + o1, b + o0]]:
			for v in tri:
				st.set_color(col)
				st.set_normal((v - (a + b) * 0.5).normalized())
				st.add_vertex(v)

# --------------------------------------------------------------- running

func drain() -> float:
	return BASE_DRAIN + PER_MOD_DRAIN * float(engine.mods.size())

func ready_to_run() -> bool:
	return core_ultima and core_uranium

func work(delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	_near = p != null and p.global_position.distance_to(global_position) < HEAR_RANGE
	# an audience counts as a reason to run: a station with a listener
	# stays on air even when nobody is standing at the case
	var want: bool = (_near or listeners > 0) and ready_to_run() and buf > 0.0
	if want:
		buf = maxf(0.0, buf - drain() * delta)
	powered = want
	_warn_cd -= delta
	if _near and ready_to_run() and buf <= 0.0 and _warn_cd <= 0.0:
		_warn_cd = 15.0
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash("SYNTH BROWNOUT — the rack needs %.1f EU/s" % drain())
	# --- the DSP thread only exists while somebody can hear it
	if powered and not engine.running:
		_ply.play()
		var pb = _ply.get_stream_playback()
		if pb != null:
			engine.running = true
			engine.master = 1.0
			engine.start(pb)
	elif not powered and engine.running:
		engine.running = false
		engine.stop()
		_ply.stop()
	if _core_u_mesh:
		_core_u_mesh.visible = core_ultima
	if _core_n_mesh:
		_core_n_mesh.visible = core_uranium
	# --- the BROADCAST panel: claim a frequency, report what we got
	_air_t -= delta
	if _air_t <= 0.0:
		_air_t = 0.5
		_update_air()
	# --- what a WORLD SENSOR panel hears about the world outside
	var dnear: float = p.global_position.distance_to(global_position) if p != null else 999.0
	engine.world[0] = clampf(5.0 - dnear * 0.25, 0.0, 5.0)
	engine.world[1] = fmod(Game.playtime / 60.0, 1.0) * 5.0
	engine.world[2] = clampf(buf / maxf(buf_cap, 1.0), 0.0, 1.0) * 5.0
	var nw2 = get_tree().get_first_node_in_group("noodle_watcher")
	engine.world[3] = clampf(float(nw2.wrath) / 100.0, 0.0, 1.0) * 5.0 \
		if (nw2 != null and "wrath" in nw2) else 0.0
	# --- panel art. Repainting a full rack is THOUSANDS of script-side
	# draw calls -- every knob, jack, cable and screen on every panel --
	# so doing it at the display rate costs more than the whole rest of
	# the frame. It is repainted on a clock instead, and the clock slows
	# down with distance: nothing on a faceplate moves fast enough for
	# the difference to be visible, and two racks in a room stop being a
	# frame-rate problem.
	var dist: float = p.global_position.distance_to(global_position) if p != null else 999.0
	if _vp != null:
		if dist > 26.0:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		else:
			var every: float = 1.0 / 24.0 if dist < 5.0 else \
				(1.0 / 12.0 if dist < 11.0 else 1.0 / 5.0)
			# a rack you are not looking at does not need repainting at
			# all: the texture it is holding is already correct
			if p != null and p.has_method("look_dir"):
				var to_me: Vector3 = (global_position - p.global_position).normalized()
				if to_me.dot(p.look_dir()) < -0.1:
					every = 1.0
			_paint_t -= delta
			if _paint_t <= 0.0:
				_paint_t = every
				# ONCE, not ALWAYS: the viewport renders exactly the
				# frames we ask it to and sleeps in between
				_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				_paint.queue_redraw()
	# --- and follows the cable-opacity setting
	if absf(_cable_alpha_shown - clampf(Settings.cable_alpha, 0.12, 1.0)) > 0.01:
		_rebuild_cables()
	# --- the physical rack follows the patch
	_rebuild_cd -= delta
	if engine.version != _seen_version and _rebuild_cd <= 0.0:
		_seen_version = engine.version
		_rebuild_cd = 0.25
		_rebuild_3d()
		if _paint != null:
			_paint.queue_redraw()
			if _vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
				_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## The rack's own transmitter. One BROADCAST panel per case is enough;
## the first one switched ON AIR owns the claim.
func _update_air() -> void:
	var cast_mod = null
	var cast_i := -1
	for i in engine.mods.size():
		var mm = engine.mods[i]
		if mm.id == "cast" and mm.sw.size() > 0 and mm.sw[0] == 1:
			cast_mod = mm
			cast_i = i
			break
	if cast_mod == null or not ready_to_run() or buf <= 0.0:
		if on_air_freq >= 0.0:
			Airwaves.release(self)
			on_air_freq = -1.0
			_claimed_want = -1.0
		for mm2 in engine.mods:
			if mm2.id == "cast":
				mm2.s[0] = 0.0
				mm2.s[1] = 0.0
				mm2.s[2] = 0.0
		return
	station_name = cast_mod.name_tag if str(cast_mod.name_tag) != "" else "DUDE FM"
	var want: float = engine.knob_value(cast_i, 0)
	if absf(want - _claimed_want) > 0.01 or station_name != _claimed_name \
			or on_air_freq < 0.0:
		on_air_freq = Airwaves.claim(self, want, station_name)
		_claimed_want = want
		_claimed_name = station_name
	var fb := Airwaves.fallback_of(self)
	cast_mod.s[0] = on_air_freq
	cast_mod.s[1] = 1.0 if bool(fb.get("bumped", false)) else 0.0
	cast_mod.s[2] = float(listeners)
	cast_mod.s[4] = 1.0 if at_nexus() else 0.0
	# every slot in the band taken -- which takes a thousand racks, but
	# the panel should still say what happened instead of going quiet
	cast_mod.s[5] = 1.0 if on_air_freq < 0.0 else 0.0
	if on_air_freq < 0.0 and _warn_cd <= 0.0:
		_warn_cd = 20.0
		var hudb = get_tree().get_first_node_in_group("hud")
		if hudb:
			hudb.flash("BAND FULL — every frequency from 88.0 to 108.0 is taken")

## A rack standing inside the Nexus array transmits from the best
## antenna in the system: distance barely touches its signal.
func at_nexus() -> bool:
	var nx = get_tree().get_first_node_in_group("nexus")
	return nx != null and is_instance_valid(nx) \
		and global_position.distance_to(nx.global_position) < 900.0

func _exit_tree_air() -> void:
	Airwaves.release(self)

func gated_work(_delta: float) -> void:
	# control coil starved: the rack dies mid-note, like the mains cut
	if engine.running:
		engine.running = false
		engine.stop()
		_ply.stop()
	powered = false

# ------------------------------------------------------------ the cores

func accepts(id: String) -> bool:
	if id == "ultima":
		return not core_ultima
	if id == "uranium":
		return not core_uranium
	return false

func accept_item(id: String) -> bool:
	if id == "ultima" and not core_ultima:
		core_ultima = true
		return true
	if id == "uranium" and not core_uranium:
		core_uranium = true
		return true
	return false

## Seat a core from your bags (the editor's two buttons).
func seat_core(id: String) -> bool:
	if not accepts(id):
		Sfx.play("denied")
		return false
	if not Game.creative:
		if Inventory.res_count(id) <= 0:
			Sfx.play("denied")
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash("no %s in your bags" % ("ultima crystal" if id == "ultima" else "uranium"))
			return false
		Inventory.remove_res(id, 1)
	accept_item(id)
	Sfx.play("click")
	return true

func pull_core(id: String) -> bool:
	if id == "ultima" and core_ultima:
		core_ultima = false
	elif id == "uranium" and core_uranium:
		core_uranium = false
	else:
		Sfx.play("denied")
		return false
	Inventory.give(id, 1)
	Sfx.play("click")
	return true

func _on_destroyed(push_dir: Vector3) -> void:
	if core_ultima:
		Inventory.give_at("ultima", 1, global_position)
	if core_uranium:
		Inventory.give_at("uranium", 1, global_position)
	if engine != null:
		engine.running = false
		engine.stop()
	super._on_destroyed(push_dir)

# ------------------------------------------------------------------- UI

func use() -> void:
	if get_tree().get_first_node_in_group("synth_ui") != null:
		return
	var ui := SynthUI.new()
	ui.synth = self
	get_tree().current_scene.add_child(ui)

func info_text() -> String:
	return "%d modules · %d cables · %.1f EU/s" % [engine.mods.size(),
		engine.cables.size(), drain()]

# ------------------------------------------------------------ save/load

func patch_data() -> Dictionary:
	return {"patch": engine.to_dict(), "u": core_ultima, "n": core_uranium}

func apply_data(d: Dictionary) -> void:
	core_ultima = bool(d.get("u", false))
	core_uranium = bool(d.get("n", false))
	var p = d.get("patch", null)
	if p is Dictionary and (p.get("mods", []) as Array).size() > 0:
		engine.from_dict(p)
	_seen_version = -1
