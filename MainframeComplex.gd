class_name MainframeComplex
extends Node3D
## The MAINFRAME installation: a dude-built control facility INSIDE the
## planet Mainframe. Not a colony -- no residents, no apartments, no
## NPCs. The dudes built it, automated it, and left. Steel ribs,
## conduit strips, consoles, drones, signage.
##
## ============================ FLOOR PLAN ============================
## Frames: every room uses Basis(e2, up, along) -- X is ALWAYS e2 (the
##   arc's side axis, constant along the whole curve), Y radial up,
##   Z the arc tangent. No mirrored bases, no axis guessing.
## SURFACE: rim + collar + apron + square shaft down u0. Three antenna
##   masts with red blinkers circle the mouth.
## ATRIUM (floor top rF = R-16, interior 12.6 x 12.6, 6.5 tall): the
##   drop lands on its SOLID floor (the hatch is in the CEILING only).
##   +Z opens full-width to the CONTROL DECK. -X has a doorway to the
##   BUNK NOOK. SURFACE gate sits at (+4.5, -4.5) -- never under the
##   ceiling hatch.
## CONTROL DECK: 14 chained segments arcing along +Z, floor top rF,
##   interior 10 wide x 6 tall, each segment tilted to its own radial
##   up -- the deck CURVES with gravity (~4cm ridges, plates overlap).
##   Ribs every segment, conduit strips both walls, consoles alternate.
## SIDE ROOMS (Death-Star style, off the deck through 2.4m doorways):
##   seg 3 -X LAB (a tetrahedron specimen floats in containment),
##   seg 5 +X AQUARIUM (fluid tank, live fish), seg 9 -X MAP ROOM
##   (orbiting planet holograms), seg 11 +X CARGO BAY (crate stacks).
##   Rooms are 8 deep so the flat floor never fights the curve hard.
## SERVER HALL (floor top r2 = R-26, interior 20 x 14 x 5.5): under
##   deck segment 7 via a 3.4m floor hatch + chute. GATE back up lands
##   on the atrium floor at +X*3 (solid -- ceiling hatch is centered).
## CORE ROOM (past deck end, floor top rF, interior 13.6, 7.5 tall):
##   the reactor cylinder + spinning rings. Walk back via the deck.
## SIGNS: amber Label3D wayfinding at every junction. Informational.
## Proof: CTD_TEST=26 fires rays through all of the above.
## ====================================================================

var _b = null
var _drones: Array = []
var _blinks: Array = []
var _fish: Array = []
var _spins: Array = []
var _pulses: Array = []      # {mat, phase} pulsing emissive columns
var _core_discs: Array = []  # rising energy discs inside the core sleeve
var _arcs: Array = []        # flickering lightning bolts around the heart
var _clk_idx := 1            # planet clock state (OVERCLOCK lever)
var _clk_cool := 0.0
var _core_mat: StandardMaterial3D = null
var _core_rings: Array = []
var _t := 0.0

const AMBER := Color("#ffb000")
const STEEL := Color("#3a4254")
const DARK := Color("#1c2026")
const SEGS := 14
const HATCH_SEG := 7

var _C: Vector3
var _u0: Vector3
var _e1: Vector3
var _e2: Vector3
var _rF: float
var _r2: float
var _a0: float
var _step: float

func _pdir(a: float) -> Vector3:
	return (_u0 * cos(a) + _e1 * sin(a)).normalized()

func _tang(a: float) -> Vector3:
	return (-_u0 * sin(a) + _e1 * cos(a)).normalized()

func _fr(a: float) -> Basis:
	return Basis(_e2, _pdir(a), _tang(a)).orthonormalized()

func _bup(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized()).orthonormalized()

## floor/ceiling as chained ARC STRIPS: every big room curves with
## gravity exactly like the deck. len_z is the FULL span to cover --
## strips are laid edge to edge so the floor always reaches the walls
## (short floors were the mystery door-steps).
func _arc_floor(a_c: float, width: float, len_z: float, rad: float,
		xoff: float) -> void:
	var n := maxi(1, int(ceil((len_z - 0.4) / 4.3)))
	var stp := ((len_z - 4.6) / float(n - 1)) / rad if n > 1 else 0.0
	for k in n:
		var a := a_c + stp * (float(k) - float(n - 1) * 0.5)
		_plate(Vector3(width, 0.5, 4.6),
			Transform3D(_fr(a), _C + _pdir(a) * rad), Vector3(xoff, 0, 0),
			DARK, 0.0)

## a REGULAR tetrahedron (4 vertices, 4 faces, flat normals). Not a
## cone, not a pyramid.
static func _tetra_mesh(s: float) -> ArrayMesh:
	var v := [Vector3(1, 1, 1), Vector3(1, -1, -1),
		Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3) * (s / sqrt(3.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]:
		for idx in f:
			st.add_vertex(v[idx])
	st.generate_normals()
	return st.commit()

## visible plate with an EXPLICIT material (maze walls etc)
func _plate_m(size: Vector3, xf: Transform3D, off: Vector3,
		mat: Material) -> void:
	var sb := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func build(b, dir: Vector3) -> void:
	_b = b
	var R: float = b.radius
	_C = b.center
	_u0 = dir.normalized()
	_e1 = _u0.cross(Vector3(0, 0, 1))
	if _e1.length() < 0.01:
		_e1 = _u0.cross(Vector3(1, 0, 0))
	_e1 = _e1.normalized()
	_e2 = _u0.cross(_e1).normalized()
	_rF = R - 16.0
	_r2 = R - 26.0
	_step = 4.6 / _rF
	_a0 = 0.115
	var abas := _fr(0.0)

	# ---- surface kit: rim, collar, apron, masts ----
	var rim := MeshInstance3D.new()
	var tmm := TorusMesh.new()
	tmm.inner_radius = 3.4
	tmm.outer_radius = 4.6
	rim.mesh = tmm
	rim.material_override = Destructible.make_material(AMBER, 1.6)
	add_child(rim)
	rim.global_transform = Transform3D(abas, _C + _u0 * (R + 0.1))
	for cspec in [[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, 3.4)],
			[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, -3.4)],
			[Vector3(0.6, 9.0, 14.0), Vector3(3.4, 0, 0)],
			[Vector3(0.6, 9.0, 14.0), Vector3(-3.4, 0, 0)]]:
		_ghost(cspec[0], Transform3D(abas, _C + _u0 * (R - 2.5)), cspec[1])
	var aout: float = clampf(4.8 + R * 0.14, 10.0, 30.0)
	var aw := aout - 3.35
	var amid := (aout + 3.35) * 0.5
	for aspec in [[Vector3(aout * 2.0, 0.5, aw), Vector3(0, 0, amid)],
			[Vector3(aout * 2.0, 0.5, aw), Vector3(0, 0, -amid)],
			[Vector3(aw, 0.5, 6.7), Vector3(amid, 0, 0)],
			[Vector3(aw, 0.5, 6.7), Vector3(-amid, 0, 0)]]:
		_ghost(aspec[0], Transform3D(abas, _C + _u0 * (R - 0.27)), aspec[1])
	for mi9 in 3:
		var mang := TAU * float(mi9) / 3.0
		var mdir := (_u0 * cos(0.09)
			+ (_e1 * cos(mang) + _e2 * sin(mang)) * sin(0.09)).normalized()
		var mpos := _C + mdir * R
		var mast := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.06
		mm.bottom_radius = 0.14
		mm.height = 5.0
		mast.mesh = mm
		mast.material_override = Surfaces.metal(STEEL)
		add_child(mast)
		mast.global_transform = Transform3D(_fr(0.0), mpos + mdir * 2.5)
		var blk := MeshInstance3D.new()
		var bmm := SphereMesh.new()
		bmm.radius = 0.16
		bmm.height = 0.32
		blk.mesh = bmm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color("#ff4444")
		bmat.emission_enabled = true
		bmat.emission = Color("#ff4444")
		blk.material_override = bmat
		add_child(blk)
		blk.global_position = mpos + mdir * 5.15
		_blinks.append({"mat": bmat, "phase": float(mi9) * 2.1})

	# ---- shaft: surface -> atrium ceiling hatch ----
	var shtop := R + 1.0
	var shbot := _rF + 6.75
	var shln := shtop - shbot
	var shxf := Transform3D(abas, _C + _u0 * ((shtop + shbot) * 0.5))
	for sspec in [[Vector3(0.5, shln, 6.0), Vector3(3.0, 0, 0)],
			[Vector3(0.5, shln, 6.0), Vector3(-3.0, 0, 0)],
			[Vector3(6.0, shln, 0.5), Vector3(0, 0, 3.0)],
			[Vector3(6.0, shln, 0.5), Vector3(0, 0, -3.0)]]:
		_plate(sspec[0], shxf, sspec[1], DARK, 0.0)
	for gsx in [Vector3(2.9, 0, 2.9), Vector3(-2.9, 0, -2.9)]:
		var gs := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.12, shln, 0.12)
		gs.mesh = gm
		gs.material_override = Destructible.make_material(AMBER, 1.8)
		add_child(gs)
		gs.global_transform = shxf
		gs.translate_object_local(gsx)

	# ---- atrium ----
	# floor in three ARC STRIPS like the deck: flat plates meeting the
	# curved deck used to leave a step lip right in the doorway
	_arc_floor(0.0, 12.6, 13.4, _rF - 0.25, 0.0)
	var acxf := Transform3D(abas, _C + _u0 * (_rF + 6.75))
	_plate(Vector3(12.6, 0.5, 3.7), acxf, Vector3(0, 0, 4.45), DARK, 0.0)
	_plate(Vector3(12.6, 0.5, 3.7), acxf, Vector3(0, 0, -4.45), DARK, 0.0)
	_plate(Vector3(3.7, 0.5, 5.2), acxf, Vector3(4.45, 0, 0), DARK, 0.0)
	_plate(Vector3(3.7, 0.5, 5.2), acxf, Vector3(-4.45, 0, 0), DARK, 0.0)
	# walls 7.0 tall, top overlapping the ceiling plate: no seam band
	var awxf := Transform3D(abas, _C + _u0 * (_rF + 3.25))
	# -Z wall: a PROPER 2.4x3.0 doorway to the service hallway, plus a
	# little grated wall vent with a fan turning in the duct behind it
	_plate(Vector3(5.1, 7.0, 0.5), awxf, Vector3(-3.75, 0, -6.05), STEEL, 0.0)
	_plate(Vector3(2.4, 4.0, 0.5), awxf, Vector3(0, 1.75, -6.05), STEEL, 0.0)
	_plate(Vector3(2.15, 7.0, 0.5), awxf, Vector3(2.275, 0, -6.05), STEEL, 0.0)
	_plate(Vector3(1.1, 5.55, 0.5), awxf, Vector3(3.9, 0.725, -6.05), STEEL, 0.0)
	_plate(Vector3(1.85, 7.0, 0.5), awxf, Vector3(5.375, 0, -6.05), STEEL, 0.0)
	for vg in [[Vector3(1.3, 0.1, 0.1), Vector3(3.9, -2.0, -6.0)],
			[Vector3(1.3, 0.1, 0.1), Vector3(3.9, -3.3, -6.0)],
			[Vector3(0.1, 1.3, 0.1), Vector3(3.25, -2.6, -6.0)],
			[Vector3(0.1, 1.3, 0.1), Vector3(4.55, -2.6, -6.0)]]:
		_deco_box(vg[0], awxf, vg[1], AMBER, 1.3)
	# the duct itself: a short sealed run behind the grille (the planet
	# is hollow -- an open vent would be an escape hole)
	_plate(Vector3(1.9, 0.4, 3.6), awxf, Vector3(3.9, -3.65, -8.1), STEEL, 0.0)
	_plate(Vector3(1.9, 0.4, 3.6), awxf, Vector3(3.9, -1.85, -8.1), STEEL, 0.0)
	_plate(Vector3(0.4, 2.2, 3.6), awxf, Vector3(3.15, -2.75, -8.1), STEEL, 0.0)
	_plate(Vector3(0.4, 2.2, 3.6), awxf, Vector3(4.65, -2.75, -8.1), STEEL, 0.0)
	_plate(Vector3(1.9, 2.4, 0.4), awxf, Vector3(3.9, -2.75, -10.1), STEEL, 0.0)
	_deco_box(Vector3(0.04, 0.08, 3.4), awxf, Vector3(3.4, -2.2, -8.1),
		Color("#66ff99"), 1.1)
	var vring := MeshInstance3D.new()
	var vrm := TorusMesh.new()
	vrm.inner_radius = 0.42
	vrm.outer_radius = 0.5
	vring.mesh = vrm
	vring.material_override = Surfaces.metal(STEEL)
	add_child(vring)
	vring.global_transform = Transform3D(abas, _C + _u0 * (_rF + 3.25))
	vring.translate_object_local(Vector3(3.9, -2.75, -9.7))
	vring.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	var vhub := Node3D.new()
	add_child(vhub)
	vhub.global_transform = Transform3D(abas, _C + _u0 * (_rF + 3.25))
	vhub.translate_object_local(Vector3(3.9, -2.75, -9.7))
	vhub.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	for vbl in 4:
		var vblade := MeshInstance3D.new()
		var vbm := BoxMesh.new()
		vbm.size = Vector3(0.4, 0.04, 0.11)
		vblade.mesh = vbm
		vblade.rotation_degrees = Vector3(0, 90.0 * float(vbl), 0)
		vblade.translate_object_local(Vector3(0.24, 0, 0))
		vblade.material_override = Surfaces.metal(Color("#4a5266"))
		vhub.add_child(vblade)
	_spins.append({"node": vhub, "rate": 5.0})
	_plate(Vector3(1.3, 7.0, 0.5), awxf, Vector3(5.65, 0, 6.05), STEEL, 0.0)
	_plate(Vector3(1.3, 7.0, 0.5), awxf, Vector3(-5.65, 0, 6.05), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 12.6), awxf, Vector3(6.05, 0, 0), STEEL, 0.0)
	# -X wall: 2.4m doorway to the bunk nook
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(-6.05, 0, 3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(-6.05, 0, -3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 2.15, 2.4), awxf, Vector3(-6.05, 2.42, 0), STEEL, 0.0)
	# surface gate, in the corner AWAY from both openings
	var sg := Gate.new().configure({
		"target": _C + _u0 * (R + 1.5) + _e1 * 7.0, "zone": "",
		"label": "SURFACE", "color": AMBER, "cube": true})
	add_child(sg)
	sg.global_transform = Transform3D(abas, _C + _u0 * (_rF + 1.4))
	sg.translate_object_local(Vector3(4.5, 0, -4.5))
	_sign("CONTROL DECK", abas, _C + _u0 * (_rF + 4.9),
		Vector3(0, 0, 5.7), 180.0)
	_sign("BUNKS", abas, _C + _u0 * (_rF + 4.4),
		Vector3(-5.6, 0, 0), 90.0)
	_sign("VENTILATION", abas, _C + _u0 * (_rF + 3.4),
		Vector3(0, 0, -5.7), 0.0)
	# atrium light
	var al := MeshInstance3D.new()
	var alm := CylinderMesh.new()
	alm.top_radius = 1.1
	alm.bottom_radius = 1.1
	alm.height = 0.1
	al.mesh = alm
	al.material_override = Destructible.make_material(Color("#f2ead8"), 2.0)
	add_child(al)
	al.global_transform = Transform3D(abas, _C + _u0 * (_rF + 6.4))
	al.translate_object_local(Vector3(3.2, 0, 0))

	# ---- bunk WING (-X of atrium): a long barracks hallway that curves
	# with gravity on the SECOND arc family (frames rotate about e1),
	# bunk alcoves both sides, and a lower gold deck for special dudes
	_bunk_wing()

	# ---- control deck: the curved room ----
	for i in SEGS:
		var a := _a0 + _step * float(i)
		var fb := _fr(a)
		var up := _pdir(a)
		var flxf := Transform3D(fb, _C + up * (_rF - 0.25))
		if i == HATCH_SEG:
			_plate(Vector3(3.55, 0.5, 5.0), flxf, Vector3(3.475, 0, 0), DARK, 0.0)
			_plate(Vector3(3.55, 0.5, 5.0), flxf, Vector3(-3.475, 0, 0), DARK, 0.0)
			_plate(Vector3(3.4, 0.5, 0.8), flxf, Vector3(0, 0, 2.1), DARK, 0.0)
			_plate(Vector3(3.4, 0.5, 0.8), flxf, Vector3(0, 0, -2.1), DARK, 0.0)
			# hazard border: amber strips framing the hatch
			for hz in [[Vector3(3.6, 0.1, 0.14), Vector3(0, 0.3, 1.78)],
					[Vector3(3.6, 0.1, 0.14), Vector3(0, 0.3, -1.78)],
					[Vector3(0.14, 0.1, 3.6), Vector3(1.78, 0.3, 0)],
					[Vector3(0.14, 0.1, 3.6), Vector3(-1.78, 0.3, 0)]]:
				var hzm := MeshInstance3D.new()
				var hzb := BoxMesh.new()
				hzb.size = hz[0]
				hzm.mesh = hzb
				hzm.material_override = Destructible.make_material(AMBER, 1.6)
				add_child(hzm)
				hzm.global_transform = flxf
				hzm.translate_object_local(hz[1])
			_sign("v SERVER HALL v", fb, _C + up * (_rF + 3.4),
				Vector3(-4.8, 0, 0), 90.0)
		else:
			_plate(Vector3(10.5, 0.5, 5.0), flxf, Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(10.5, 0.5, 5.0),
			Transform3D(fb, _C + up * (_rF + 6.25)), Vector3.ZERO, DARK, 0.0)
		# walls 6.5 tall, centre rF+3.0: top edge OVERLAPS the ceiling
		# plate -- no open seam band anywhere
		var wxf := Transform3D(fb, _C + up * (_rF + 3.0))
		var rooms := {3: [-1.0, "LAB"], 5: [1.0, "AQUARIUM"],
			9: [1.0, "MAP ROOM"], 11: [-1.0, "CARGO BAY"]}
		for ws in [1.0, -1.0]:
			if rooms.has(i) and float((rooms[i] as Array)[0]) == ws:
				# doorway to the side room: flanks + full-height header.
				# The sign is the room's NAME above its own door -- no
				# arrow, the door is right there
				_plate(Vector3(0.5, 6.5, 1.3), wxf, Vector3(ws * 5.25, 0, 1.85), STEEL, 0.0)
				_plate(Vector3(0.5, 6.5, 1.3), wxf, Vector3(ws * 5.25, 0, -1.85), STEEL, 0.0)
				_plate(Vector3(0.5, 2.3, 2.4), wxf, Vector3(ws * 5.25, 2.1, 0), STEEL, 0.0)
				_sign(str((rooms[i] as Array)[1]), fb, _C + up * (_rF + 4.35),
					Vector3(ws * 4.55, 0, 0), 90.0 if ws < 0.0 else -90.0)
			else:
				_plate(Vector3(0.5, 6.5, 5.0), wxf, Vector3(ws * 5.25, 0, 0), STEEL, 0.0)
		if rooms.has(i):
			_side_room(i, float((rooms[i] as Array)[0]), str((rooms[i] as Array)[1]))
		# steel RIB: two studs + lintel, every segment
		_deco_box(Vector3(0.24, 6.5, 0.24), wxf, Vector3(5.0, 0, 2.3), STEEL, 0.0)
		_deco_box(Vector3(0.24, 6.5, 0.24), wxf, Vector3(-5.0, 0, 2.3), STEEL, 0.0)
		_deco_box(Vector3(10.24, 0.24, 0.24), wxf, Vector3(0, 3.15, 2.3), STEEL, 0.0)
		# conduit strips, both walls -- split around doorways so no
		# glowing stripe ever floats across an opening
		for cs9 in [1.0, -1.0]:
			if rooms.has(i) and float((rooms[i] as Array)[0]) == cs9:
				_deco_box(Vector3(0.06, 0.16, 1.3), wxf, Vector3(cs9 * 4.9, -1.85, 1.85), AMBER, 1.6)
				_deco_box(Vector3(0.06, 0.16, 1.3), wxf, Vector3(cs9 * 4.9, -1.85, -1.85), AMBER, 1.6)
			else:
				_deco_box(Vector3(0.06, 0.16, 5.0), wxf, Vector3(cs9 * 4.9, -1.85, 0), AMBER, 1.6)
		if i % 2 == 0:
			_deco_box(Vector3(0.5, 0.08, 3.4),
				Transform3D(fb, _C + up * (_rF + 5.85)), Vector3.ZERO,
				Color("#f2ead8"), 2.2)
		if i % 2 == 1 and i != HATCH_SEG:
			_console(fb, up, 1.0 if (i / 2) % 2 == 0 else -1.0)
	var aend := _a0 + _step * float(SEGS - 1)
	_sign("CORE >>", _fr(aend), _C + _pdir(aend) * (_rF + 4.6),
		Vector3(0, 0, 2.4), 180.0)

	# ---- server hall ----
	var ah := _a0 + _step * float(HATCH_SEG)
	var hb := _fr(ah)
	var hup := _pdir(ah)
	var chln := _rF - (_r2 + 5.5)
	var chxf := Transform3D(hb, _C + hup * ((_rF + _r2 + 5.5) * 0.5))
	for chs in [[Vector3(0.5, chln, 3.6), Vector3(1.95, 0, 0)],
			[Vector3(0.5, chln, 3.6), Vector3(-1.95, 0, 0)],
			[Vector3(3.6, chln, 0.5), Vector3(0, 0, 1.95)],
			[Vector3(3.6, chln, 0.5), Vector3(0, 0, -1.95)]]:
		_plate(chs[0], chxf, chs[1], DARK, 0.0)
	_plate(Vector3(20.6, 0.5, 14.6),
		Transform3D(hb, _C + hup * (_r2 - 0.25)), Vector3.ZERO, DARK, 0.0)
	var scxf := Transform3D(hb, _C + hup * (_r2 + 5.5))
	_plate(Vector3(20.6, 0.5, 5.6), scxf, Vector3(0, 0, 4.5), DARK, 0.0)
	_plate(Vector3(20.6, 0.5, 5.6), scxf, Vector3(0, 0, -4.5), DARK, 0.0)
	_plate(Vector3(8.6, 0.5, 3.4), scxf, Vector3(6.0, 0, 0), DARK, 0.0)
	_plate(Vector3(8.6, 0.5, 3.4), scxf, Vector3(-6.0, 0, 0), DARK, 0.0)
	var swxf := Transform3D(hb, _C + hup * (_r2 + 2.6))
	_plate(Vector3(0.5, 5.7, 14.6), swxf, Vector3(10.3, 0, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.7, 14.6), swxf, Vector3(-10.3, 0, 0), STEEL, 0.0)
	# +Z wall: doorway into the DATA MAZE
	_plate(Vector3(9.4, 5.7, 0.5), swxf, Vector3(5.6, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(9.4, 5.7, 0.5), swxf, Vector3(-5.6, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(1.8, 3.25, 0.5), swxf, Vector3(0, 1.225, 7.3), STEEL, 0.0)
	_plate(Vector3(20.6, 5.7, 0.5), swxf, Vector3(0, 0, -7.3), STEEL, 0.0)
	_chatter(Transform3D(hb, _C + hup * (_r2 + 2.0)).origin, 11, -6.0)
	_chatter(Transform3D(hb, _C + hup * (_r2 + 2.0))
		.translated_local(Vector3(-6.0, 0, 3.0)).origin, 12, -6.0)
	# racks: two rows, glowing slits, one blinker each
	for rz in 5:
		for rs in [-1.0, 1.0]:
			var rxf := Transform3D(hb, _C + hup * (_r2 + 1.6))
			var roff := Vector3(rs * 4.2, 0, -5.0 + 2.5 * float(rz))
			_plate(Vector3(1.3, 3.2, 1.0), rxf, roff, Color("#12161c"), 0.0)
			for sl in 3:
				_deco_box(Vector3(0.06, 0.07, 0.8),
					Transform3D(hb, _C + hup * (_r2 + 1.0 + 0.7 * float(sl))),
					roff + Vector3(-rs * 0.66, 0, 0), Color("#66ff99"), 1.8)
			var rdot := MeshInstance3D.new()
			var rdm := BoxMesh.new()
			rdm.size = Vector3(0.09, 0.09, 0.09)
			rdot.mesh = rdm
			var rdmat := StandardMaterial3D.new()
			rdmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rdmat.albedo_color = AMBER
			rdmat.emission_enabled = true
			rdmat.emission = AMBER
			rdot.material_override = rdmat
			add_child(rdot)
			rdot.global_transform = Transform3D(hb, _C + hup * (_r2 + 3.0))
			rdot.translate_object_local(roff + Vector3(-rs * 0.66, 0, 0.3))
			_blinks.append({"mat": rdmat,
				"phase": float(rz) * 0.9 + (0.5 if rs > 0.0 else 0.0)})
	# cooling pipes along the ceiling
	for ps in [-1.0, 1.0]:
		var pipe := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.18
		pm.bottom_radius = 0.18
		pm.height = 13.5
		pipe.mesh = pm
		pipe.material_override = Surfaces.metal(Color("#4a5266"))
		add_child(pipe)
		pipe.global_transform = Transform3D(hb, _C + hup * (_r2 + 4.9))
		pipe.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
		pipe.translate_object_local(Vector3(ps * 2.2, 0, 0))
	var ag := Gate.new().configure({
		"target": _C + _u0 * (_rF + 0.4) + _e2 * 3.0, "zone": "",
		"label": "ATRIUM", "color": AMBER, "cube": true})
	add_child(ag)
	ag.global_transform = Transform3D(hb, _C + hup * (_r2 + 1.4))
	ag.translate_object_local(Vector3(8.0, 0, 5.6))
	_sign("^ GATE -> ATRIUM ^", hb, _C + hup * (_r2 + 3.7),
		Vector3(8.0, 0, 6.9), 180.0)
	var sl9 := MeshInstance3D.new()
	var slm := CylinderMesh.new()
	slm.top_radius = 1.0
	slm.bottom_radius = 1.0
	slm.height = 0.08
	sl9.mesh = slm
	sl9.material_override = Destructible.make_material(Color("#cfe6d8"), 1.7)
	add_child(sl9)
	sl9.global_transform = Transform3D(hb, _C + hup * (_r2 + 5.15))
	sl9.translate_object_local(Vector3(0, 0, 3.2))

	# ---- REACTOR CORE: a GIANT chamber (22x22x12, arc floors) with a
	# fusion assembly in the middle and a raised control booth inside
	var ac := aend + (2.5 + 11.55) / _rF
	var cb := _fr(ac)
	var cup := _pdir(ac)
	_arc_floor(ac, 22.6, 23.4, _rF - 0.25, 0.0)
	_arc_floor(ac, 22.6, 23.4, _rF + 12.25, 0.0)
	var cwxf := Transform3D(cb, _C + cup * (_rF + 6.0))
	# -Z wall: deck-sized opening + a DEEP header sealing the band above
	# the deck ceiling (the old escape hole)
	_plate(Vector3(6.3, 12.5, 0.5), cwxf, Vector3(8.15, 0, -11.3), STEEL, 0.0)
	_plate(Vector3(6.3, 12.5, 0.5), cwxf, Vector3(-8.15, 0, -11.3), STEEL, 0.0)
	_plate(Vector3(10.6, 6.5, 0.5), cwxf, Vector3(0, 3.0, -11.3), STEEL, 0.0)
	_plate(Vector3(22.6, 12.5, 0.5), cwxf, Vector3(0, 0, 11.3), STEEL, 0.0)
	# +X wall: doorway to COMMUNICATIONS
	_plate(Vector3(0.5, 12.5, 10.1), cwxf, Vector3(11.3, 0, 6.25), STEEL, 0.0)
	_plate(Vector3(0.5, 12.5, 10.1), cwxf, Vector3(11.3, 0, -6.25), STEEL, 0.0)
	_plate(Vector3(0.5, 9.5, 2.4), cwxf, Vector3(11.3, 1.5, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 12.5, 22.6), cwxf, Vector3(-11.3, 0, 0), STEEL, 0.0)
	_sign("COMMUNICATIONS", cb, _C + cup * (_rF + 5.7),
		Vector3(10.7, 0, 0), -90.0)
	# fusion assembly: plinth, plasma heart in a translucent sleeve,
	# feed columns, three tilted spin rings, six pylons, rising discs
	var plinth := MeshInstance3D.new()
	var plm := CylinderMesh.new()
	plm.top_radius = 2.8
	plm.bottom_radius = 3.2
	plm.height = 0.6
	plinth.mesh = plm
	plinth.material_override = Surfaces.metal(Color("#12161c"))
	add_child(plinth)
	plinth.global_transform = Transform3D(cb, _C + cup * (_rF + 0.3))
	var cgb := StaticBody3D.new()
	var cgc := CollisionShape3D.new()
	var cgs := CylinderShape3D.new()
	cgs.radius = 2.6
	cgs.height = 6.5
	cgc.shape = cgs
	cgb.add_child(cgc)
	add_child(cgb)
	cgb.global_transform = Transform3D(cb, _C + cup * (_rF + 3.25))
	var heart := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 1.5
	hsm.height = 3.0
	heart.mesh = hsm
	heart.material_override = DatamoshStudio._fluid_material(AMBER)
	add_child(heart)
	heart.global_transform = Transform3D(cb, _C + cup * (_rF + 3.4))
	var hglow := MeshInstance3D.new()
	var hgm := SphereMesh.new()
	hgm.radius = 0.85
	hgm.height = 1.7
	hglow.mesh = hgm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color("#fff2cf")
	_core_mat.emission_enabled = true
	_core_mat.emission = Color("#ffd27a")
	hglow.material_override = _core_mat
	add_child(hglow)
	hglow.global_transform = Transform3D(cb, _C + cup * (_rF + 3.4))
	for fc in [1.1, 5.7]:
		var col9 := MeshInstance3D.new()
		var clm9 := CylinderMesh.new()
		clm9.top_radius = 0.32
		clm9.bottom_radius = 0.32
		clm9.height = 1.6
		col9.mesh = clm9
		col9.material_override = Destructible.make_material(AMBER, 1.6)
		add_child(col9)
		col9.global_transform = Transform3D(cb, _C + cup * (_rF + fc))
	var sleeve := MeshInstance3D.new()
	var svm := CylinderMesh.new()
	svm.top_radius = 2.5
	svm.bottom_radius = 2.5
	svm.height = 6.0
	sleeve.mesh = svm
	var svmat := StandardMaterial3D.new()
	svmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	svmat.albedo_color = Color(1.0, 0.75, 0.3, 0.10)
	svmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sleeve.material_override = svmat
	add_child(sleeve)
	sleeve.global_transform = Transform3D(cb, _C + cup * (_rF + 3.4))
	for ri in 3:
		var ring := MeshInstance3D.new()
		var rgm := TorusMesh.new()
		rgm.inner_radius = 3.0 + 0.5 * float(ri)
		rgm.outer_radius = 3.25 + 0.5 * float(ri)
		ring.mesh = rgm
		ring.material_override = Destructible.make_material(
			AMBER.lightened(0.2), 1.8)
		add_child(ring)
		ring.global_transform = Transform3D(cb, _C + cup * (_rF + 3.4))
		ring.rotate_object_local(Vector3(1, 0, 0),
			[0.35, -0.22, 0.12][ri])
		_core_rings.append({"node": ring, "spin": 0.4 + 0.35 * float(ri)})
	for py in 6:
		var pang := TAU * float(py) / 6.0
		var pyl := MeshInstance3D.new()
		var pym := BoxMesh.new()
		pym.size = Vector3(0.35, 5.0, 0.35)
		pyl.mesh = pym
		pyl.material_override = Surfaces.metal(STEEL)
		add_child(pyl)
		pyl.global_transform = Transform3D(cb, _C + cup * (_rF + 2.2))
		pyl.translate_object_local(Vector3(cos(pang) * 5.2, 0, sin(pang) * 5.2))
		pyl.rotate_object_local(Vector3(-sin(pang), 0, cos(pang)) * -1.0, 0.55)
		var tip := MeshInstance3D.new()
		var tpm2 := SphereMesh.new()
		tpm2.radius = 0.22
		tpm2.height = 0.44
		tip.mesh = tpm2
		tip.material_override = Destructible.make_material(AMBER, 2.2)
		add_child(tip)
		tip.global_transform = Transform3D(cb, _C + cup * (_rF + 4.6))
		tip.translate_object_local(Vector3(cos(pang) * 3.9, 0, sin(pang) * 3.9))
	for di2 in 4:
		var disc := MeshInstance3D.new()
		var dcm := CylinderMesh.new()
		dcm.top_radius = 2.0
		dcm.bottom_radius = 2.0
		dcm.height = 0.06
		disc.mesh = dcm
		disc.material_override = Destructible.make_material(
			AMBER.lightened(0.35), 2.0)
		add_child(disc)
		_core_discs.append({"node": disc, "cb": cb, "cup": cup,
			"phase": float(di2) * 1.4})
	var collector := MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.3
	ccm.bottom_radius = 2.0
	ccm.height = 1.4
	collector.mesh = ccm
	collector.material_override = Surfaces.metal(Color("#12161c"))
	add_child(collector)
	collector.global_transform = Transform3D(cb, _C + cup * (_rF + 7.2))
	var fring := MeshInstance3D.new()
	var frm := TorusMesh.new()
	frm.inner_radius = 4.7
	frm.outer_radius = 4.95
	fring.mesh = frm
	fring.material_override = Destructible.make_material(AMBER, 1.3)
	add_child(fring)
	fring.global_transform = Transform3D(cb, _C + cup * (_rF + 0.08))
	# lightning: jagged arc bolts that flicker around the heart
	for ab in 5:
		var arc9 := Node3D.new()
		add_child(arc9)
		arc9.global_transform = Transform3D(cb, _C + cup * (_rF + 3.4))
		arc9.rotate_object_local(Vector3(0, 1, 0), TAU * float(ab) / 5.0)
		for seg9 in 3:
			var bolt := MeshInstance3D.new()
			var bom := BoxMesh.new()
			bom.size = Vector3(0.06, 0.06, 1.1)
			bolt.mesh = bom
			bolt.position = Vector3(1.6 + 0.5 * float(seg9),
				0.5 - 0.5 * float(seg9), 0)
			bolt.rotation_degrees = Vector3(0, 24.0 * float(seg9) - 20.0,
				38.0 - 34.0 * float(seg9))
			bolt.material_override = Destructible.make_material(
				Color("#fff2cf"), 2.6)
			arc9.add_child(bolt)
		_arcs.append({"node": arc9, "phase": float(ab) * 1.3})
	# control booth INSIDE the chamber: raised glass box overlooking the
	# core, reached by a ramp
	var bpx := 7.2
	var bpz := 7.6
	_plate(Vector3(7.0, 0.6, 5.4), Transform3D(cb, _C + cup * (_rF + 2.1)),
		Vector3(bpx, 0, bpz), STEEL, 0.0)
	_plate(Vector3(2.6, 0.5, 5.8),
		Transform3D(cb * Basis(Vector3(1, 0, 0), -0.46),
		_C + cup * (_rF + 1.1)), Vector3(bpx - 1.4, 0, bpz - 5.15), STEEL, 0.0)
	for gw9 in [[Vector3(7.0, 2.4, 0.12), Vector3(bpx, 3.6, bpz - 2.7)],
			[Vector3(0.12, 2.4, 5.4), Vector3(bpx - 3.45, 3.6, bpz)]]:
		var gl9 := StaticBody3D.new()
		var gmi9 := MeshInstance3D.new()
		var gbm9 := BoxMesh.new()
		gbm9.size = gw9[0]
		gmi9.mesh = gbm9
		var gmat9 := StandardMaterial3D.new()
		gmat9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat9.albedo_color = Color(1.0, 0.85, 0.5, 0.14)
		gmi9.material_override = gmat9
		gl9.add_child(gmi9)
		var gcs9 := CollisionShape3D.new()
		var gbs9 := BoxShape3D.new()
		gbs9.size = gw9[0]
		gcs9.shape = gbs9
		gl9.add_child(gcs9)
		add_child(gl9)
		gl9.global_transform = Transform3D(cb, _C + cup * _rF)
		gl9.translate_object_local(gw9[1])
	_plate(Vector3(3.2, 1.1, 0.9), Transform3D(cb, _C + cup * (_rF + 2.95)),
		Vector3(bpx, 0, bpz - 2.2), Color("#12161c"), 0.0)
	var bpan := MeshInstance3D.new()
	bpan.mesh = IcosaColony._cham_mesh(0.9, 0.05, 3.3, 0.22)
	bpan.material_override = Destructible.make_material(AMBER.darkened(0.1), 1.6)
	add_child(bpan)
	bpan.global_transform = Transform3D(
		cb * Basis(Vector3(0, 0, 1), 0.5), _C + cup * (_rF + 3.62))
	bpan.translate_object_local(Vector3(bpx * 0.88, 0, bpz - 2.2))
	_sign("REACTOR CORE", cb, _C + cup * (_rF + 8.6),
		Vector3(0, 0, 10.9), 180.0)
	_sign("CONTROL BOOTH", cb, _C + cup * (_rF + 5.4),
		Vector3(bpx, 0, bpz + 2.6), 180.0)
	_sign("CONTROL DECK / ATRIUM", cb, _C + cup * (_rF + 5.2),
		Vector3(0, 0, -10.9), 0.0)

	# ---- the wings ----
	_service_wing()
	_comms_room(cb, ac)
	# ---- four GIANT antennas on different sides of the planet ----
	for an9 in 4:
		var aang := TAU * float(an9) / 4.0 + 0.5
		var adir := (_u0 * cos(1.15)
			+ (_e1 * cos(aang) + _e2 * sin(aang)) * sin(1.15)).normalized()
		var abup := _bup(adir)
		var apos := _C + adir * R
		_plate(Vector3(3.4, 1.2, 3.4), Transform3D(abup, apos + adir * 0.4),
			Vector3.ZERO, DARK, 0.0)
		for sec in 3:
			var mast9 := MeshInstance3D.new()
			var mm9 := CylinderMesh.new()
			mm9.top_radius = 0.55 - 0.15 * float(sec)
			mm9.bottom_radius = 0.7 - 0.15 * float(sec)
			mm9.height = 6.0
			mast9.mesh = mm9
			mast9.material_override = Surfaces.metal(STEEL)
			add_child(mast9)
			mast9.global_transform = Transform3D(abup,
				apos + adir * (3.6 + 6.0 * float(sec)))
		var dish9 := MeshInstance3D.new()
		var dhm := CylinderMesh.new()
		dhm.top_radius = 3.2
		dhm.bottom_radius = 0.4
		dhm.height = 1.6
		dish9.mesh = dhm
		dish9.material_override = Surfaces.metal(Color("#31384a"))
		add_child(dish9)
		dish9.global_transform = Transform3D(abup, apos + adir * 21.5)
		dish9.rotate_object_local(Vector3(0, 0, 1), 0.5)
		_deco_box(Vector3(0.14, 18.0, 0.14), Transform3D(abup, apos + adir * 12.0),
			Vector3(0.5, 0, 0.5), AMBER, 1.4)
		var ab9 := MeshInstance3D.new()
		var abm9 := SphereMesh.new()
		abm9.radius = 0.3
		abm9.height = 0.6
		ab9.mesh = abm9
		var abmat := StandardMaterial3D.new()
		abmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		abmat.albedo_color = Color("#ff4444")
		abmat.emission_enabled = true
		abmat.emission = Color("#ff4444")
		ab9.material_override = abmat
		add_child(ab9)
		ab9.global_position = apos + adir * 22.6
		_blinks.append({"mat": abmat, "phase": float(an9) * 1.1})
	# ---- maintenance drones: the only staff left ----
	for di in 3:
		var d := Node3D.new()
		add_child(d)
		var body9 := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(0.42, 0.3, 0.42)
		body9.mesh = dbm
		body9.material_override = Surfaces.metal(STEEL)
		d.add_child(body9)
		var ant := MeshInstance3D.new()
		var anm := CylinderMesh.new()
		anm.top_radius = 0.015
		anm.bottom_radius = 0.015
		anm.height = 0.4
		ant.mesh = anm
		ant.position = Vector3(0, 0.35, 0)
		ant.material_override = Surfaces.metal(Color("#4a5266"))
		d.add_child(ant)
		var tip := MeshInstance3D.new()
		var tpm := SphereMesh.new()
		tpm.radius = 0.05
		tpm.height = 0.1
		tip.mesh = tpm
		tip.position = Vector3(0, 0.58, 0)
		tip.material_override = Destructible.make_material(AMBER, 2.4)
		d.add_child(tip)
		var pod9 := MeshInstance3D.new()
		var pdm := CylinderMesh.new()
		pdm.top_radius = 0.16
		pdm.bottom_radius = 0.05
		pdm.height = 0.12
		pod9.mesh = pdm
		pod9.position = Vector3(0, -0.21, 0)
		pod9.material_override = Destructible.make_material(Color("#7df9ff"), 1.9)
		d.add_child(pod9)
		_drones.append({"node": d, "lane": -2.5 + 2.5 * float(di),
			"phase": float(di) * 2.3, "speed": 0.10 + 0.03 * float(di)})

## SECOND arc family: frames curving along e2 (lateral). X = lateral
## tangent, Y = radial up, Z = e1. Right-handed by construction.
func _pdx(b: float) -> Vector3:
	return (_u0 * cos(b) + _e2 * sin(b)).normalized()

func _fx(b: float) -> Basis:
	var upb := _pdx(b)
	var tb := (-_u0 * sin(b) + _e2 * cos(b)).normalized()
	return Basis(tb, upb, _e1).orthonormalized()

## ---- BUNK WING: barracks hallway + the gold deck below ----
func _bunk_wing() -> void:
	var rV := _rF - 7.0
	for i in 5:
		var b := -(_a0 + _step * float(i))
		var fb := _fx(b)
		var up := _pdx(b)
		var flxf := Transform3D(fb, _C + up * (_rF - 0.25))
		if i == 4:
			# end segment: 2.6m hatch down to the special-dudes deck
			_plate(Vector3(1.0, 0.5, 3.8), flxf, Vector3(-2.0, 0, 0), DARK, 0.0)
			_plate(Vector3(1.0, 0.5, 3.8), flxf, Vector3(2.0, 0, 0), DARK, 0.0)
			_plate(Vector3(3.0, 0.5, 0.5), flxf, Vector3(0, 0, 1.65), DARK, 0.0)
			_plate(Vector3(3.0, 0.5, 0.5), flxf, Vector3(0, 0, -1.65), DARK, 0.0)
			_sign("SPECIAL BUNKS BELOW", fb, _C + up * (_rF + 2.5),
				Vector3(-1.8, 0, 0), 90.0)
		else:
			_plate(Vector3(5.0, 0.5, 3.8), flxf, Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(5.0, 0.5, 3.8),
			Transform3D(fb, _C + up * (_rF + 3.45)), Vector3.ZERO, DARK, 0.0)
		var wxf := Transform3D(fb, _C + up * (_rF + 1.6))
		for zs in [1.0, -1.0]:
			# alcove opening framed by posts + a top band
			_plate(Vector3(1.2, 3.7, 0.4), wxf, Vector3(1.9, 0, zs * 1.9), STEEL, 0.0)
			_plate(Vector3(1.2, 3.7, 0.4), wxf, Vector3(-1.9, 0, zs * 1.9), STEEL, 0.0)
			_plate(Vector3(2.6, 1.8, 0.4), wxf, Vector3(0, 0.95, zs * 1.9), STEEL, 0.0)
			# the alcove pocket
			_plate(Vector3(3.4, 0.5, 2.4), flxf, Vector3(0, 0, zs * 2.9), DARK, 0.0)
			_plate(Vector3(3.4, 0.5, 2.4),
				Transform3D(fb, _C + up * (_rF + 2.35)), Vector3(0, 0, zs * 2.9), DARK, 0.0)
			_plate(Vector3(0.4, 2.6, 2.4),
				Transform3D(fb, _C + up * (_rF + 1.05)), Vector3(1.7, 0, zs * 2.9), STEEL, 0.0)
			_plate(Vector3(0.4, 2.6, 2.4),
				Transform3D(fb, _C + up * (_rF + 1.05)), Vector3(-1.7, 0, zs * 2.9), STEEL, 0.0)
			_plate(Vector3(3.4, 2.6, 0.4),
				Transform3D(fb, _C + up * (_rF + 1.05)), Vector3(0, 0, zs * 4.0), STEEL, 0.0)
			# the bunk: bigger deck, grav ring, reading light
			var gring := MeshInstance3D.new()
			var grm := TorusMesh.new()
			grm.inner_radius = 0.6
			grm.outer_radius = 1.0
			gring.mesh = grm
			gring.material_override = Destructible.make_material(AMBER, 1.6)
			add_child(gring)
			gring.global_transform = Transform3D(fb, _C + up * (_rF + 0.14))
			gring.translate_object_local(Vector3(0, 0, zs * 3.0))
			var bunk := MeshInstance3D.new()
			bunk.mesh = IcosaColony._cham_mesh(2.4, 0.3, 1.6, 0.3)
			bunk.material_override = Destructible.make_material(STEEL, 0.25)
			add_child(bunk)
			bunk.global_transform = Transform3D(fb, _C + up * (_rF + 0.6))
			bunk.translate_object_local(Vector3(0, 0, zs * 3.0))
			_deco_box(Vector3(0.5, 0.06, 0.5),
				Transform3D(fb, _C + up * (_rF + 2.28)),
				Vector3(0, 0, zs * 2.9), Color("#f2ead8"), 1.7)
		# OUTER SHELL: belt-and-braces backing behind and above the
		# alcoves -- no sight line into the hollow planet anywhere
		_plate(Vector3(5.0, 4.6, 0.5), Transform3D(fb, _C + up * (_rF + 1.85)),
			Vector3(0, 0, 4.45), STEEL, 0.0)
		_plate(Vector3(5.0, 4.6, 0.5), Transform3D(fb, _C + up * (_rF + 1.85)),
			Vector3(0, 0, -4.45), STEEL, 0.0)
		_plate(Vector3(5.0, 0.5, 3.1), Transform3D(fb, _C + up * (_rF + 2.85)),
			Vector3(0, 0, 2.95), STEEL, 0.0)
		_plate(Vector3(5.0, 0.5, 3.1), Transform3D(fb, _C + up * (_rF + 2.85)),
			Vector3(0, 0, -2.95), STEEL, 0.0)
		# corridor conduits + every-other ceiling light
		_deco_box(Vector3(5.0, 0.1, 0.08), wxf, Vector3(0, 1.3, 1.66), AMBER, 1.5)
		_deco_box(Vector3(5.0, 0.1, 0.08), wxf, Vector3(0, 1.3, -1.66), AMBER, 1.5)
		if i % 2 == 0:
			_deco_box(Vector3(2.6, 0.08, 0.5),
				Transform3D(fb, _C + up * (_rF + 3.15)), Vector3.ZERO,
				Color("#f2ead8"), 2.0)
	# END CAP: the corridor stops HERE, sealed -- no hole into the rock
	var bend := -(_a0 + _step * 4.0)
	var cxf9 := Transform3D(_fx(bend), _C + _pdx(bend) * (_rF + 1.6))
	_plate(Vector3(0.4, 3.9, 3.9), cxf9, Vector3(-2.65, 0, 0), STEEL, 0.0)
	# chute + the SPECIAL DUDES deck
	var b4 := -(_a0 + _step * 4.0)
	var fb4 := _fx(b4)
	var up4 := _pdx(b4)
	var chln := _rF - (rV + 4.2)
	var chxf := Transform3D(fb4, _C + up4 * ((_rF + rV + 4.2) * 0.5))
	for chs in [[Vector3(0.5, chln, 2.8), Vector3(1.55, 0, 0)],
			[Vector3(0.5, chln, 2.8), Vector3(-1.55, 0, 0)],
			[Vector3(2.8, chln, 0.5), Vector3(0, 0, 1.55)],
			[Vector3(2.8, chln, 0.5), Vector3(0, 0, -1.55)]]:
		_plate(chs[0], chxf, chs[1], DARK, 0.0)
	_plate(Vector3(11.6, 0.5, 11.6),
		Transform3D(fb4, _C + up4 * (rV - 0.25)), Vector3.ZERO, DARK, 0.0)
	var vcxf := Transform3D(fb4, _C + up4 * (rV + 4.2))
	_plate(Vector3(11.6, 0.5, 4.15), vcxf, Vector3(0, 0, 3.725), DARK, 0.0)
	_plate(Vector3(11.6, 0.5, 4.15), vcxf, Vector3(0, 0, -3.725), DARK, 0.0)
	_plate(Vector3(4.15, 0.5, 3.3), vcxf, Vector3(3.725, 0, 0), DARK, 0.0)
	_plate(Vector3(4.15, 0.5, 3.3), vcxf, Vector3(-3.725, 0, 0), DARK, 0.0)
	var vwxf := Transform3D(fb4, _C + up4 * (rV + 2.1))
	_plate(Vector3(0.5, 5.2, 11.6), vwxf, Vector3(5.8, 0, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.2, 11.6), vwxf, Vector3(-5.8, 0, 0), STEEL, 0.0)
	_plate(Vector3(11.6, 5.2, 0.5), vwxf, Vector3(0, 0, 5.8), STEEL, 0.0)
	_plate(Vector3(11.6, 5.2, 0.5), vwxf, Vector3(0, 0, -5.8), STEEL, 0.0)
	var GOLD := Color("#ffd700")
	for gw in [[Vector3(11.0, 0.12, 0.12), Vector3(0, 0, 5.45)],
			[Vector3(11.0, 0.12, 0.12), Vector3(0, 0, -5.45)],
			[Vector3(0.12, 0.12, 11.0), Vector3(5.45, 0, 0)],
			[Vector3(0.12, 0.12, 11.0), Vector3(-5.45, 0, 0)]]:
		_deco_box(gw[0], Transform3D(fb4, _C + up4 * (rV + 1.2)), gw[1], GOLD, 1.6)
	for vb in [[-3.4, 3.4], [3.4, 3.4], [-3.4, -3.4], [3.4, -3.4]]:
		var gr2 := MeshInstance3D.new()
		var gr2m := TorusMesh.new()
		gr2m.inner_radius = 0.7
		gr2m.outer_radius = 1.15
		gr2.mesh = gr2m
		gr2.material_override = Destructible.make_material(GOLD, 1.8)
		add_child(gr2)
		gr2.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.14))
		gr2.translate_object_local(Vector3(vb[0], 0, vb[1]))
		var vbk := MeshInstance3D.new()
		vbk.mesh = IcosaColony._cham_mesh(3.2, 0.4, 1.8, 0.35)
		vbk.material_override = Destructible.make_material(Color("#3a2436"), 0.3)
		add_child(vbk)
		vbk.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.7))
		vbk.translate_object_local(Vector3(vb[0], 0, vb[1]))
		var plw := MeshInstance3D.new()
		var plwm := SphereMesh.new()
		plwm.radius = 0.34
		plwm.height = 0.4
		plw.mesh = plwm
		plw.material_override = Destructible.make_material(GOLD.lightened(0.3), 0.6)
		add_child(plw)
		plw.global_transform = Transform3D(fb4, _C + up4 * (rV + 1.0))
		plw.translate_object_local(Vector3(vb[0] + 1.1, 0, vb[1]))
	var rug := MeshInstance3D.new()
	var rugm := CylinderMesh.new()
	rugm.top_radius = 2.2
	rugm.bottom_radius = 2.2
	rugm.height = 0.06
	rug.mesh = rugm
	rug.material_override = Destructible.make_material(Color("#4a1a2e"), 0.2)
	add_child(rug)
	rug.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.03))
	var rugr := MeshInstance3D.new()
	var rugrm := TorusMesh.new()
	rugrm.inner_radius = 2.14
	rugrm.outer_radius = 2.26
	rugr.mesh = rugrm
	rugr.material_override = Destructible.make_material(GOLD, 1.4)
	add_child(rugr)
	rugr.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.06))
	var vl := MeshInstance3D.new()
	var vlm := CylinderMesh.new()
	vlm.top_radius = 1.0
	vlm.bottom_radius = 1.0
	vlm.height = 0.08
	vl.mesh = vlm
	vl.material_override = Destructible.make_material(Color("#fff3d0"), 2.0)
	add_child(vl)
	vl.global_transform = Transform3D(fb4, _C + up4 * (rV + 3.9))
	_sign("SPECIAL DUDES ONLY", fb4, _C + up4 * (rV + 3.0),
		Vector3(0, 0, -5.4), 0.0)
	var bg := Gate.new().configure({
		"target": _C + up4 * (_rF + 0.45) - _fx(b4).x * 3.4, "zone": "",
		"label": "BUNK HALL", "color": GOLD, "cube": true})
	add_child(bg)
	bg.global_transform = Transform3D(fb4, _C + up4 * (rV + 1.3))
	bg.translate_object_local(Vector3(0, 0, 4.6))

## One Death-Star side room off deck segment i, on side s. Shell +
## door aligned to the deck doorway, then themed contents.
func _side_room(i: int, s: float, kind: String) -> void:
	var a := _a0 + _step * float(i)
	var fb := _fr(a)
	var up := _pdir(a)
	var cx := s * 9.6
	_plate(Vector3(8.6, 0.5, 9.6), Transform3D(fb, _C + up * (_rF - 0.25)),
		Vector3(cx, 0, 0), DARK, 0.0)
	_plate(Vector3(8.6, 0.5, 9.6), Transform3D(fb, _C + up * (_rF + 5.25)),
		Vector3(cx, 0, 0), DARK, 0.0)
	var wxf := Transform3D(fb, _C + up * (_rF + 2.5))
	_plate(Vector3(0.5, 5.5, 9.6), wxf, Vector3(s * 13.65, 0, 0), STEEL, 0.0)
	_plate(Vector3(8.6, 5.5, 0.5), wxf, Vector3(cx, 0, 4.55), STEEL, 0.0)
	_plate(Vector3(8.6, 5.5, 0.5), wxf, Vector3(cx, 0, -4.55), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 5.55, 0, 3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 5.55, 0, -3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 1.4, 2.4), wxf, Vector3(s * 5.55, 2.05, 0), STEEL, 0.0)
	var rl := MeshInstance3D.new()
	var rlm := CylinderMesh.new()
	rlm.top_radius = 0.8
	rlm.bottom_radius = 0.8
	rlm.height = 0.08
	rl.mesh = rlm
	rl.material_override = Destructible.make_material(Color("#f2ead8"), 1.9)
	add_child(rl)
	rl.global_transform = Transform3D(fb, _C + up * (_rF + 4.95))
	rl.translate_object_local(Vector3(cx, 0, 0))
	match kind:
		"LAB":
			_room_lab(fb, up, cx)
		"AQUARIUM":
			_room_aquarium(fb, up, cx, s)
		"MAP ROOM":
			_room_map(fb, up, cx)
		"CARGO BAY":
			_room_cargo(fb, up, cx)

func _room_lab(fb: Basis, up: Vector3, cx: float) -> void:
	# two benches, glowing glassware, and SPECIMEN 4: a tetrahedron in a
	# containment ring. The dudes were studying something Harold-shaped.
	for bz in [-2.4, 2.4]:
		_plate(Vector3(6.4, 1.0, 1.2), Transform3D(fb, _C + up * (_rF + 0.5)),
			Vector3(cx, 0, bz), Color("#20262e"), 0.0)
		for bx in 3:
			var flask := MeshInstance3D.new()
			var fm9 := SphereMesh.new()
			fm9.radius = 0.16 + 0.06 * float(bx % 2)
			fm9.height = fm9.radius * 2.0
			flask.mesh = fm9
			flask.material_override = Destructible.make_material(
				[Color("#66ff99"), Color("#ff66aa"), Color("#7df9ff")][bx], 1.7)
			add_child(flask)
			flask.global_transform = Transform3D(fb, _C + up * (_rF + 1.18))
			flask.translate_object_local(Vector3(cx - 2.0 + 2.0 * float(bx), 0, bz))
	var ped := MeshInstance3D.new()
	var pdm := CylinderMesh.new()
	pdm.top_radius = 0.55
	pdm.bottom_radius = 0.7
	pdm.height = 0.9
	ped.mesh = pdm
	ped.material_override = Surfaces.metal(STEEL)
	add_child(ped)
	ped.global_transform = Transform3D(fb, _C + up * (_rF + 0.45))
	ped.translate_object_local(Vector3(cx, 0, 0))
	var ring := MeshInstance3D.new()
	var rgm := TorusMesh.new()
	rgm.inner_radius = 0.55
	rgm.outer_radius = 0.72
	ring.mesh = rgm
	ring.material_override = Destructible.make_material(AMBER, 1.9)
	add_child(ring)
	ring.global_transform = Transform3D(fb, _C + up * (_rF + 1.35))
	ring.translate_object_local(Vector3(cx, 0, 0))
	var tet := MeshInstance3D.new()
	tet.mesh = _tetra_mesh(0.42)
	tet.material_override = Destructible.make_material(AMBER.lightened(0.25), 2.2)
	add_child(tet)
	tet.global_transform = Transform3D(fb, _C + up * (_rF + 1.75))
	tet.translate_object_local(Vector3(cx, 0, 0))
	_spins.append({"node": tet, "rate": 0.7})
	_sign("SPECIMEN 4: TETRAHEDRON", fb, _C + up * (_rF + 3.6),
		Vector3(cx, 0, -4.2), 0.0)
	_sign("DO NOT TOUCH. IT REMEMBERS.", fb, _C + up * (_rF + 3.1),
		Vector3(cx, 0, -4.2), 0.0)

func _room_aquarium(fb: Basis, up: Vector3, cx: float, s: float) -> void:
	# a full-wall tank: fluid-glow backdrop, glass front, live fish.
	# Somebody fed them for two hundred years. Nobody knows who.
	var back := MeshInstance3D.new()
	var bqm := QuadMesh.new()
	bqm.size = Vector2(8.4, 3.6)
	back.mesh = bqm
	back.material_override = DatamoshStudio._fluid_material(Color("#2a9df4"))
	add_child(back)
	back.global_transform = Transform3D(fb, _C + up * (_rF + 2.1))
	back.translate_object_local(Vector3(s * 13.3, 0, 0))
	back.rotate_object_local(Vector3(0, 1, 0), -s * PI * 0.5)
	var glass := StaticBody3D.new()
	var gmi := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(0.12, 3.8, 8.6)
	gmi.mesh = gbm
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.5, 0.8, 1.0, 0.18)
	gmi.material_override = gmat
	glass.add_child(gmi)
	var gcs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = gbm.size
	gcs.shape = gbs
	glass.add_child(gcs)
	add_child(glass)
	glass.global_transform = Transform3D(fb, _C + up * (_rF + 2.15))
	glass.translate_object_local(Vector3(s * 11.5, 0, 0))
	var sand := MeshInstance3D.new()
	var sdm := BoxMesh.new()
	sdm.size = Vector3(1.9, 0.3, 8.6)
	sand.mesh = sdm
	sand.material_override = Surfaces.metal(Color("#c8b06a"))
	add_child(sand)
	sand.global_transform = Transform3D(fb, _C + up * (_rF + 0.15))
	sand.translate_object_local(Vector3(s * 12.5, 0, 0))
	for fi in 5:
		# a real fish: body, wagging tail fin, dorsal fin -- swims with
		# its NOSE forward, tail beating
		var fish := Node3D.new()
		add_child(fish)
		var fcol: Color = [Color("#ffcf40"), Color("#ff6a6a"), Color("#7df9ff"),
			Color("#66ff99"), Color("#ff66aa")][fi]
		var fbody := MeshInstance3D.new()
		var fcm := CapsuleMesh.new()
		fcm.radius = 0.1
		fcm.height = 0.52
		fbody.mesh = fcm
		fbody.rotation_degrees = Vector3(90, 0, 0)
		fbody.scale = Vector3(0.55, 1.0, 1.0)
		fbody.material_override = Destructible.make_material(fcol, 1.2)
		fish.add_child(fbody)
		var dorsal := MeshInstance3D.new()
		var dfm := BoxMesh.new()
		dfm.size = Vector3(0.02, 0.14, 0.16)
		dorsal.mesh = dfm
		dorsal.position = Vector3(0, 0.14, -0.02)
		dorsal.material_override = Destructible.make_material(fcol.darkened(0.25), 0.9)
		fish.add_child(dorsal)
		var tail := MeshInstance3D.new()
		var tfm := BoxMesh.new()
		tfm.size = Vector3(0.03, 0.2, 0.2)
		tail.mesh = tfm
		tail.position = Vector3(0, 0, -0.34)
		tail.material_override = Destructible.make_material(fcol.darkened(0.15), 1.0)
		fish.add_child(tail)
		_fish.append({"node": fish, "tail": tail, "fb": fb, "up": up,
			"x": s * 12.5, "phase": float(fi) * 1.7, "zr": 3.6,
			"yb": 1.0 + 0.5 * float(fi % 3)})
	_sign("AQUARIUM // FEEDING: AUTOMATED", fb, _C + up * (_rF + 3.7),
		Vector3(cx, 0, 4.2), 180.0)

func _room_map(fb: Basis, up: Vector3, cx: float) -> void:
	# a STATIC hologram of the actual Dude system, built from the live
	# Universe registry -- real relative positions, and YOU ARE HERE
	var ped := MeshInstance3D.new()
	var pdm := CylinderMesh.new()
	pdm.top_radius = 1.3
	pdm.bottom_radius = 1.6
	pdm.height = 0.8
	ped.mesh = pdm
	ped.material_override = Surfaces.metal(Color("#20262e"))
	add_child(ped)
	ped.global_transform = Transform3D(fb, _C + up * (_rF + 0.4))
	ped.translate_object_local(Vector3(cx, 0, 0))
	var ring := MeshInstance3D.new()
	var rgm := TorusMesh.new()
	rgm.inner_radius = 1.5
	rgm.outer_radius = 1.66
	ring.mesh = rgm
	ring.material_override = Destructible.make_material(AMBER, 1.6)
	add_child(ring)
	ring.global_transform = Transform3D(fb, _C + up * (_rF + 0.84))
	ring.translate_object_local(Vector3(cx, 0, 0))
	var holo := Transform3D(fb, _C + up * (_rF + 2.5))
	var maxd := 1.0
	var dude_bodies: Array = []
	for db in Universe.bodies:
		if (db.center as Vector3).length() < 13500.0 * Universe.world_scale:
			dude_bodies.append(db)
			maxd = maxf(maxd, (db.center as Vector3).length())
	var k := 3.0 / maxd
	for db in dude_bodies:
		var g := MeshInstance3D.new()
		var gm9 := SphereMesh.new()
		gm9.radius = clampf(float(db.radius) * k * 12.0, 0.07, 0.4)
		gm9.height = gm9.radius * 2.0
		g.mesh = gm9
		g.material_override = Destructible.make_material(
			(db.color as Color).lightened(0.15), 1.4)
		add_child(g)
		g.global_transform = holo
		g.translate_object_local(Vector3(cx, 0.6, 0) + (db.center as Vector3) * k)
		if db.name == "Big Computer":
			var mk := MeshInstance3D.new()
			var mkm := TorusMesh.new()
			mkm.inner_radius = gm9.radius + 0.1
			mkm.outer_radius = gm9.radius + 0.2
			mk.mesh = mkm
			mk.material_override = Destructible.make_material(AMBER, 2.2)
			add_child(mk)
			mk.global_transform = g.global_transform
			var yah := Label3D.new()
			yah.text = "YOU ARE HERE"
			yah.font_size = 30
			yah.pixel_size = 0.006
			yah.modulate = AMBER
			yah.outline_size = 8
			yah.outline_modulate = Color(0, 0, 0, 0.9)
			yah.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(yah)
			yah.global_position = g.global_position + up * 0.55
	_sign("SYSTEM MAP // NOT TO SCALE", fb, _C + up * (_rF + 3.7),
		Vector3(cx, 0, -4.2), 0.0)

func _room_cargo(fb: Basis, up: Vector3, cx: float) -> void:
	# crate stacks in neat rows -- somebody inventoried these once
	for st in [[Vector3(-2.4, 0, -2.6), 2], [Vector3(-2.4, 0, 0.4), 1],
			[Vector3(-2.4, 0, 2.8), 3], [Vector3(2.2, 0, -2.2), 1],
			[Vector3(2.2, 0, 1.6), 2]]:
		var base: Vector3 = st[0]
		for lv in int(st[1]):
			_plate(Vector3(1.4, 1.4, 1.4),
				Transform3D(fb, _C + up * (_rF + 0.7 + 1.42 * float(lv))),
				Vector3(cx + base.x, 0, base.z), Color("#242a32"), 0.0)
			_deco_box(Vector3(1.44, 0.1, 1.44),
				Transform3D(fb, _C + up * (_rF + 1.32 + 1.42 * float(lv))),
				Vector3(cx + base.x, 0, base.z), AMBER, 1.2)
	_sign("CARGO BAY // MANIFEST LOST", fb, _C + up * (_rF + 3.7),
		Vector3(cx, 0, 4.2), 180.0)

## ---- SERVICE WING: tight vents -> assembly hall -> generator hall ----
func _service_wing() -> void:
	for i in 6:
		var a := -(_a0 + _step * float(i))
		var fb := _fr(a)
		var up := _pdir(a)
		_plate(Vector3(3.0, 0.4, 5.0), Transform3D(fb, _C + up * (_rF - 0.2)),
			Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(3.4, 0.4, 5.0), Transform3D(fb, _C + up * (_rF + 2.5)),
			Vector3.ZERO, DARK, 0.0)
		var wxf := Transform3D(fb, _C + up * (_rF + 1.15))
		_plate(Vector3(0.4, 2.7, 5.0), wxf, Vector3(1.5, 0, 0), STEEL, 0.0)
		_plate(Vector3(0.4, 2.7, 5.0), wxf, Vector3(-1.5, 0, 0), STEEL, 0.0)
		# floor grates + a dim strip -- crawlspace dressing
		_deco_box(Vector3(2.8, 0.05, 0.2), Transform3D(fb, _C + up * (_rF + 0.03)),
			Vector3(0, 0, 1.2), Color("#12161c"), 0.0)
		_deco_box(Vector3(2.8, 0.05, 0.2), Transform3D(fb, _C + up * (_rF + 0.03)),
			Vector3(0, 0, -1.2), Color("#12161c"), 0.0)
		_deco_box(Vector3(0.05, 0.1, 5.0), wxf, Vector3(1.35, -0.5, 0),
			Color("#66ff99"), 1.1)
		if i % 3 == 2:
			# a FAN: ring + spinning blades filling the tube
			var fring9 := MeshInstance3D.new()
			var frm9 := TorusMesh.new()
			frm9.inner_radius = 1.0
			frm9.outer_radius = 1.18
			fring9.mesh = frm9
			fring9.material_override = Surfaces.metal(STEEL)
			add_child(fring9)
			fring9.global_transform = Transform3D(fb, _C + up * (_rF + 1.25))
			fring9.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
			var hub := Node3D.new()
			add_child(hub)
			hub.global_transform = Transform3D(fb, _C + up * (_rF + 1.25))
			for bl in 4:
				var blade := MeshInstance3D.new()
				var blm := BoxMesh.new()
				blm.size = Vector3(0.22, 0.9, 0.05)
				blade.mesh = blm
				blade.position = Vector3(0, 0, 0)
				blade.rotation_degrees = Vector3(0, 0, 90.0 * float(bl))
				blade.translate_object_local(Vector3(0, 0.5, 0))
				blade.material_override = Surfaces.metal(Color("#4a5266"))
				hub.add_child(blade)
			_spins.append({"node": hub, "rate": 6.5})
	_sign("ATRIUM", _fr(-_a0), _C + _pdir(-_a0) * (_rF + 1.9),
		Vector3(1.3, 0, 0), -90.0)
	# ASSEMBLY HALL
	var ah2 := -(_a0 + _step * 6.0 + (2.5 + 7.5) / _rF)
	var hb2 := _fr(ah2)
	var hup2 := _pdir(ah2)
	_arc_floor(ah2, 22.6, 15.4, _rF - 0.25, 0.0)
	_arc_floor(ah2, 22.6, 15.4, _rF + 9.25, 0.0)
	var awx2 := Transform3D(hb2, _C + hup2 * (_rF + 4.5))
	_plate(Vector3(10.4, 9.5, 0.5), awx2, Vector3(6.1, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(10.4, 9.5, 0.5), awx2, Vector3(-6.1, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(1.8, 7.3, 0.5), awx2, Vector3(0, 1.1, 7.3), STEEL, 0.0)
	_plate(Vector3(10.0, 9.5, 0.5), awx2, Vector3(6.3, 0, -7.3), STEEL, 0.0)
	_plate(Vector3(10.0, 9.5, 0.5), awx2, Vector3(-6.3, 0, -7.3), STEEL, 0.0)
	_plate(Vector3(2.6, 6.25, 0.5), awx2, Vector3(0, 1.625, -7.3), STEEL, 0.0)
	_plate(Vector3(0.5, 9.5, 14.6), awx2, Vector3(11.3, 0, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 9.5, 14.6), awx2, Vector3(-11.3, 0, 0), STEEL, 0.0)
	_plate(Vector3(7.0, 0.7, 5.0), Transform3D(hb2, _C + hup2 * (_rF + 0.35)),
		Vector3(-5.0, 0, 2.0), Color("#20262e"), 0.0)
	var hd := MeshInstance3D.new()
	var hdm := BoxMesh.new()
	hdm.size = Vector3(1.7, 1.7, 1.7)
	hd.mesh = hdm
	hd.material_override = Surfaces.metal(STEEL)
	add_child(hd)
	hd.global_transform = Transform3D(hb2, _C + hup2 * (_rF + 1.6))
	hd.translate_object_local(Vector3(-5.0, 0, 2.0))
	var hpanel := MeshInstance3D.new()
	var hpm2 := BoxMesh.new()
	hpm2.size = Vector3(1.1, 1.1, 0.1)
	hpanel.mesh = hpm2
	hpanel.material_override = Destructible.make_material(AMBER.darkened(0.3), 0.9)
	add_child(hpanel)
	hpanel.global_transform = Transform3D(hb2, _C + hup2 * (_rF + 1.5))
	hpanel.translate_object_local(Vector3(-3.9, 0, 2.9))
	hpanel.rotate_object_local(Vector3(0, 1, 0), 0.6)
	for rl2 in [-3.0, 3.0]:
		_deco_box(Vector3(0.35, 0.35, 13.6),
			Transform3D(hb2, _C + hup2 * (_rF + 8.4)), Vector3(rl2, 0, 0),
			STEEL, 0.0)
	_deco_box(Vector3(6.6, 0.4, 0.4), Transform3D(hb2, _C + hup2 * (_rF + 8.1)),
		Vector3(0, 0, -1.5), STEEL, 0.0)
	_deco_box(Vector3(0.08, 2.6, 0.08), Transform3D(hb2, _C + hup2 * (_rF + 6.7)),
		Vector3(0, 0, -1.5), Color("#4a5266"), 0.0)
	_deco_box(Vector3(0.5, 0.5, 0.5), Transform3D(hb2, _C + hup2 * (_rF + 5.2)),
		Vector3(0, 0, -1.5), AMBER, 1.2)
	for cs2 in [[7.5, -4.0, 2], [7.5, 0.5, 1], [7.5, 4.0, 3]]:
		for lv2 in int(cs2[2]):
			_plate(Vector3(1.4, 1.4, 1.4),
				Transform3D(hb2, _C + hup2 * (_rF + 0.7 + 1.42 * float(lv2))),
				Vector3(float(cs2[0]), 0, float(cs2[1])), Color("#242a32"), 0.0)
			_deco_box(Vector3(1.44, 0.1, 1.44),
				Transform3D(hb2, _C + hup2 * (_rF + 1.32 + 1.42 * float(lv2))),
				Vector3(float(cs2[0]), 0, float(cs2[1])), AMBER, 1.2)
	for lb2 in [-3.5, 3.5]:
		_deco_box(Vector3(4.0, 0.08, 0.6),
			Transform3D(hb2, _C + hup2 * (_rF + 8.85)), Vector3(lb2, 0, 3.0),
			Color("#f2ead8"), 2.2)
	_sign("ASSEMBLY", hb2, _C + hup2 * (_rF + 6.4), Vector3(0, 0, 6.9), 180.0)
	_sign("GENERATOR", hb2, _C + hup2 * (_rF + 4.6), Vector3(0, 0, -6.9), 0.0)
	_chatter(Transform3D(hb2, _C + hup2 * (_rF + 2.0)).origin, 31, -10.0)
	# GENERATOR HALL
	var ag2 := ah2 - (7.3 + 8.55) / _rF
	var gb2 := _fr(ag2)
	var gup2 := _pdir(ag2)
	_arc_floor(ag2, 16.6, 17.4, _rF - 0.25, 0.0)
	_arc_floor(ag2, 16.6, 17.4, _rF + 8.25, 0.0)
	var gwx2 := Transform3D(gb2, _C + gup2 * (_rF + 4.0))
	_plate(Vector3(7.0, 8.5, 0.5), gwx2, Vector3(4.8, 0, 8.3), STEEL, 0.0)
	_plate(Vector3(7.0, 8.5, 0.5), gwx2, Vector3(-4.8, 0, 8.3), STEEL, 0.0)
	_plate(Vector3(2.6, 5.25, 0.5), gwx2, Vector3(0, 1.875, 8.3), STEEL, 0.0)
	_plate(Vector3(16.6, 8.5, 0.5), gwx2, Vector3(0, 0, -8.3), STEEL, 0.0)
	_plate(Vector3(0.5, 8.5, 16.6), gwx2, Vector3(8.3, 0, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 8.5, 16.6), gwx2, Vector3(-8.3, 0, 0), STEEL, 0.0)
	for pp in [[-3.5, -2.5], [3.5, -2.5], [0.0, 3.5]]:
		var poff := Vector3(float(pp[0]), 0, float(pp[1]))
		_plate(Vector3(2.6, 0.6, 2.6), Transform3D(gb2, _C + gup2 * (_rF + 0.3)),
			poff, Color("#12161c"), 0.0)
		var pil := MeshInstance3D.new()
		var pim2 := CylinderMesh.new()
		pim2.top_radius = 0.95
		pim2.bottom_radius = 0.95
		pim2.height = 5.4
		pil.mesh = pim2
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.albedo_color = AMBER.darkened(0.4)
		pmat.emission_enabled = true
		pmat.emission = AMBER
		pil.material_override = pmat
		add_child(pil)
		pil.global_transform = Transform3D(gb2, _C + gup2 * (_rF + 3.3))
		pil.translate_object_local(poff)
		_pulses.append({"mat": pmat, "phase": float(pp[0]) + float(pp[1])})
		var pcb := StaticBody3D.new()
		var pcc := CollisionShape3D.new()
		var pcs := CylinderShape3D.new()
		pcs.radius = 1.15
		pcs.height = 5.4
		pcc.shape = pcs
		pcb.add_child(pcc)
		add_child(pcb)
		pcb.global_transform = Transform3D(gb2, _C + gup2 * (_rF + 3.3))
		pcb.translate_object_local(poff)
		var pring := MeshInstance3D.new()
		var prm := TorusMesh.new()
		prm.inner_radius = 1.4
		prm.outer_radius = 1.6
		pring.mesh = prm
		pring.material_override = Destructible.make_material(AMBER, 1.5)
		add_child(pring)
		pring.global_transform = Transform3D(gb2, _C + gup2 * (_rF + 0.08))
		pring.translate_object_local(poff)
		_deco_box(Vector3(0.18, 1.6, 0.18),
			Transform3D(gb2, _C + gup2 * (_rF + 6.9)), poff, Color("#4a5266"), 0.0)
	_sign("GENERATOR HALL", gb2, _C + gup2 * (_rF + 5.6), Vector3(0, 0, 8.0), 180.0)
	_chatter(Transform3D(gb2, _C + gup2 * (_rF + 2.0)).origin, 47, -8.0)

## ---- COMMUNICATIONS: the interuniverse radio. Physical buttons, a
## 3D signal screen, four stations from OUTSIDE the universe. ----
var _radio_on := false
var _radio_idx := 0
var _radio_cool := 0.0
var _radio_sp: AudioStreamPlayer3D = null
var _radio_lbl: Label3D = null
var _radio_smat: ShaderMaterial = null
var _radio_streams: Array = []
const RADIO_NAMES := ["CHANNEL 1", "CHANNEL 2", "CHANNEL 3", "CHANNEL 4"]
const RADIO_HUES := [Color("#b388ff"), Color("#66ff99"),
	Color("#7df9ff"), Color("#ff6a6a")]

func _comms_room(cb: Basis, _ac: float) -> void:
	# the room hangs off the core's +X wall, on its own lateral arc
	# frame so the floor still agrees with gravity
	var gam := 16.6 / _rF
	var cb2 := cb.rotated((cb * Vector3(0, 0, 1)).normalized(), -gam)
	var up2 := (cb2 * Vector3(0, 1, 0)).normalized()
	_plate(Vector3(12.6, 0.5, 12.6), Transform3D(cb2, _C + up2 * (_rF - 0.25)),
		Vector3.ZERO, DARK, 0.0)
	_plate(Vector3(12.6, 0.5, 12.6), Transform3D(cb2, _C + up2 * (_rF + 6.75)),
		Vector3.ZERO, DARK, 0.0)
	var cwx2 := Transform3D(cb2, _C + up2 * (_rF + 3.25))
	_plate(Vector3(0.5, 7.0, 5.1), cwx2, Vector3(-6.05, 0, 3.75), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 5.1), cwx2, Vector3(-6.05, 0, -3.75), STEEL, 0.0)
	_plate(Vector3(0.5, 4.0, 2.4), cwx2, Vector3(-6.05, 1.5, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 12.6), cwx2, Vector3(6.05, 0, 0), STEEL, 0.0)
	_plate(Vector3(12.6, 7.0, 0.5), cwx2, Vector3(0, 0, 6.05), STEEL, 0.0)
	_plate(Vector3(12.6, 7.0, 0.5), cwx2, Vector3(0, 0, -6.05), STEEL, 0.0)
	# the 3D SIGNAL SCREEN on the +X wall
	var sfr := MeshInstance3D.new()
	sfr.mesh = IcosaColony._cham_mesh(3.0, 0.08, 6.0, 0.45)
	sfr.material_override = Destructible.make_material(AMBER, 1.3)
	add_child(sfr)
	sfr.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.4))
	sfr.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
	sfr.translate_object_local(Vector3(0, 5.72, 0))
	var scr9 := MeshInstance3D.new()
	var sqm := QuadMesh.new()
	sqm.size = Vector2(5.4, 2.5)
	scr9.mesh = sqm
	_radio_smat = _radio_screen_mat()
	scr9.material_override = _radio_smat
	add_child(scr9)
	scr9.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.4))
	scr9.rotate_object_local(Vector3(0, 1, 0), -PI * 0.5)
	scr9.translate_object_local(Vector3(0, 0, -5.62))
	# no titles: the screen's colour and the sound ARE the channel
	# console desk + two physical buttons: POWER and STATION
	_plate(Vector3(1.4, 1.0, 5.0), Transform3D(cb2, _C + up2 * (_rF + 0.5)),
		Vector3(2.6, 0, 0), Color("#12161c"), 0.0)
	var dial := MeshInstance3D.new()
	var dlm := CylinderMesh.new()
	dlm.top_radius = 0.5
	dlm.bottom_radius = 0.5
	dlm.height = 0.14
	dial.mesh = dlm
	dial.material_override = Destructible.make_material(AMBER, 1.5)
	add_child(dial)
	dial.global_transform = Transform3D(cb2, _C + up2 * (_rF + 1.1))
	dial.translate_object_local(Vector3(2.6, 0, 0))
	_spins.append({"node": dial, "rate": 0.8})
	for btn in [[Vector3(2.6, 0, 1.7), Color("#ff4444"), "POWER"],
			[Vector3(2.6, 0, -1.7), Color("#66ff99"), "STATION"]]:
		var bped := MeshInstance3D.new()
		var bpm2 := BoxMesh.new()
		bpm2.size = Vector3(0.5, 0.24, 0.5)
		bped.mesh = bpm2
		bped.material_override = Destructible.make_material(btn[1], 1.8)
		add_child(bped)
		bped.global_transform = Transform3D(cb2, _C + up2 * (_rF + 1.12))
		bped.translate_object_local(btn[0])
		var lb2 := Label3D.new()
		lb2.text = str(btn[2])
		lb2.font_size = 22
		lb2.pixel_size = 0.005
		lb2.modulate = btn[1]
		lb2.outline_size = 8
		lb2.outline_modulate = Color(0, 0, 0, 0.9)
		add_child(lb2)
		lb2.global_transform = Transform3D(
			cb2 * Basis(Vector3(0, 1, 0), -PI * 0.5),
			Transform3D(cb2, _C + up2 * (_rF + 1.55))
			.translated_local(btn[0]).origin)
		var trig := Area3D.new()
		var tcs := CollisionShape3D.new()
		var tss := SphereShape3D.new()
		tss.radius = 0.9
		tcs.shape = tss
		trig.add_child(tcs)
		add_child(trig)
		trig.global_transform = Transform3D(cb2, _C + up2 * (_rF + 1.3))
		trig.translate_object_local(btn[0])
		var is_power: bool = str(btn[2]) == "POWER"
		trig.body_entered.connect(func(bod):
			if _radio_cool > 0.0 or not bod.is_in_group("player"):
				return
			_radio_cool = 1.0
			if is_power:
				_radio_on = not _radio_on
			else:
				_radio_idx = (_radio_idx + 1) % RADIO_NAMES.size()
			Sfx.play("click", -8.0)
			_radio_apply())
	_sign("INTERUNIVERSE COMMUNICATIONS", cb2, _C + up2 * (_rF + 5.9),
		Vector3(0, 0, -5.7), 0.0)
	_radio_sp = AudioStreamPlayer3D.new()
	_radio_sp.max_distance = 30.0
	_radio_sp.volume_db = -4.0
	add_child(_radio_sp)
	_radio_sp.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.0))
	_radio_streams = [_st_music(), _st_numbers(), _st_static(), _st_drone()]
	_chatter(Transform3D(cb2, _C + up2 * (_rF + 1.0)).origin, 77, -14.0)

func _radio_apply() -> void:
	if _radio_smat != null:
		var hc: Color = RADIO_HUES[_radio_idx] if _radio_on else Color("#332a10")
		_radio_smat.set_shader_parameter("hue", Vector3(hc.r, hc.g, hc.b))
		_radio_smat.set_shader_parameter("live", 1.0 if _radio_on else 0.0)
	if _radio_sp != null:
		_radio_sp.stop()
		if _radio_on and _radio_streams[_radio_idx] != null:
			_radio_sp.stream = _radio_streams[_radio_idx]
			_radio_sp.play()

func _radio_screen_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform vec3 hue = vec3(1.0, 0.7, 0.1);
uniform float live = 0.0;
void fragment(){
	vec2 uv = UV;
	float t = TIME;
	float col9 = floor(uv.x * 24.0);
	float h = fract(sin(col9 * 12.9898) * 43758.5453);
	float bar = step(abs(uv.y - 0.5) * 2.0,
		(0.15 + 0.85 * abs(sin(t * (1.5 + h * 4.0) + col9))) * live + 0.04);
	float scan = 0.5 + 0.5 * sin(uv.y * 60.0 - t * 8.0);
	vec3 col = hue * bar + hue * 0.12 * scan;
	ALBEDO = col;
	EMISSION = col * 1.6;
}
"""
	var m9 := ShaderMaterial.new()
	m9.shader = sh
	return m9

func _bake_pcm(secs: float, f: Callable) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s9 := int(clampf(float(f.call(float(i) / float(rate))), -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav

func _st_music() -> AudioStreamWAV:
	# a waltz from the void: detuned pentatonic thirds in 3/4
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var notes: Array = []
	for i in 12:
		notes.append([0, 3, 5, 7, 10][rng.randi() % 5] + (12 if rng.randf() < 0.3 else 0))
	return _bake_pcm(9.6, func(ts: float) -> float:
		var beat := int(ts / 0.8) % 12
		var frac := fmod(ts, 0.8) / 0.8
		var fq := 196.0 * pow(2.0, float(notes[beat]) / 12.0)
		var env := (1.0 - frac) * (0.5 if beat % 3 != 0 else 0.9)
		return (0.16 * sin(TAU * fq * ts) + 0.1 * sin(TAU * fq * 1.005 * ts)
			+ 0.05 * sin(TAU * fq * 0.5 * ts)) * env)

func _st_numbers():
	# a numbers station: an alien voice reading digits, forever
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var digits := ""
	for i in 10:
		digits += str(rng.randi() % 10) + ". "
	var w = HumanVoice.render(digits, RadioLib.ALIEN_HOSTS[2])
	if w is AudioStreamWAV:
		(w as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(w as AudioStreamWAV).loop_end = (w as AudioStreamWAV).data.size() / 2
	return w

func _st_static() -> AudioStreamWAV:
	# the static sea -- and underneath, REAL morse. It spells HAROLD.
	# dit=1u dah=3u, gaps 1/3/7, standard timing at 0.09s a unit.
	const MORSE := {"H": "....", "A": ".-", "R": ".-.", "O": "---",
		"L": ".-..", "D": "-.."}
	var unit := 0.09
	var tones: Array = []   # [start, length]
	var tcur := 0.8
	for chr9 in "HAROLD":
		for sym in MORSE[chr9]:
			var ln := unit if sym == "." else unit * 3.0
			tones.append([tcur, ln])
			tcur += ln + unit
		tcur += unit * 2.0   # char gap totals 3u with the trailing 1u
	var total := tcur + unit * 7.0 + 0.8
	return _bake_pcm(total, func(ts: float) -> float:
		var v := 0.07 * (fmod(sin(ts * 91731.7) * 43758.5453, 2.0) - 1.0)
		v += 0.03 * sin(TAU * 0.4 * ts) * (fmod(sin(ts * 55117.1) * 12345.6, 2.0) - 1.0)
		for tp in tones:
			var dt9: float = ts - float(tp[0])
			if dt9 >= 0.0 and dt9 < float(tp[1]):
				v += 0.16 * sin(TAU * 620.0 * ts)
		return v)

func _st_drone() -> AudioStreamWAV:
	# five voices holding a chord since before the universe
	return _bake_pcm(8.0, func(ts: float) -> float:
		var v := 0.0
		var fqs := [55.0, 110.0, 164.8, 220.0, 329.6]
		for i in fqs.size():
			v += 0.07 * sin(TAU * float(fqs[i]) * ts) \
				* (0.6 + 0.4 * sin(TAU * ts / 8.0 + float(i) * 1.3))
		return v)

## the DATA WALL shader: scrolling glyph blocks, scanlines, alive
var _data_mat_cache: ShaderMaterial = null
func _data_mat() -> ShaderMaterial:
	if _data_mat_cache != null:
		return _data_mat_cache
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
void fragment(){
	vec2 uv = UV;
	float t = TIME;
	vec2 g = floor(uv * vec2(14.0, 7.0) + vec2(0.0, floor(t * 7.0)));
	float h = fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453);
	float on = step(0.55, fract(h + t * 0.23));
	vec3 base9 = mix(vec3(0.0, 0.05, 0.02), vec3(0.08, 1.0, 0.35), on * h);
	vec3 warm = vec3(1.0, 0.62, 0.1) * step(0.93, h) * on;
	float scan = 0.5 + 0.5 * sin(uv.y * 46.0 - t * 10.0);
	vec3 col = base9 + warm;
	ALBEDO = col * (0.7 + 0.3 * scan);
	EMISSION = col * (1.1 + 0.5 * scan);
}
"""
	_data_mat_cache = ShaderMaterial.new()
	_data_mat_cache.shader = sh
	return _data_mat_cache

## a positional COMPUTER CHATTER emitter: baked PCM loop of hums,
## beeps and data ticks. The facility never shuts up.
func _chatter(pos: Vector3, seed9: int, db: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed9
	var rate := 22050
	var secs := 4.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var beeps: Array = []
	for bi in 14:
		beeps.append([rng.randf() * secs, 0.05 + rng.randf() * 0.2,
			300.0 + rng.randf() * 1900.0])
	for i in n:
		var ts := float(i) / float(rate)
		var v := 0.05 * sin(TAU * 46.0 * ts) + 0.02 * sin(TAU * 91.0 * ts)
		for b9 in beeps:
			var dt9: float = ts - float(b9[0])
			if dt9 >= 0.0 and dt9 < float(b9[1]):
				v += 0.14 * sin(TAU * float(b9[2]) * ts) \
					* (1.0 - dt9 / float(b9[1]))
		if i % int(rate * 0.25) < 40:
			v += 0.06 * (rng.randf() * 2.0 - 1.0)
		var s9 := int(clampf(v, -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	var sp := AudioStreamPlayer3D.new()
	sp.stream = wav
	sp.volume_db = db
	sp.max_distance = 38.0
	add_child(sp)
	sp.global_position = pos
	sp.play(rng.randf() * secs)

func _console(fb: Basis, up: Vector3, s: float) -> void:
	var bxf := Transform3D(fb, _C + up * (_rF + 0.52))
	_plate(Vector3(1.1, 1.05, 2.4), bxf, Vector3(s * 4.35, 0, 0), Color("#12161c"), 0.0)
	var pan := MeshInstance3D.new()
	pan.mesh = IcosaColony._cham_mesh(0.95, 0.05, 2.45, 0.22)
	pan.material_override = Destructible.make_material(AMBER.darkened(0.15), 1.5)
	add_child(pan)
	pan.global_transform = Transform3D(
		fb * Basis(Vector3(0, 0, 1), deg_to_rad(-s * 28.0)),
		_C + up * (_rF + 1.14))
	pan.translate_object_local(Vector3(s * 4.15, 0, 0))
	for bd in 3:
		var dot := MeshInstance3D.new()
		var dm9 := BoxMesh.new()
		dm9.size = Vector3(0.1, 0.03, 0.1)
		dot.mesh = dm9
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var dc: Color = [Color("#66ff99"), AMBER, Color("#ff4444")][bd]
		dmat.albedo_color = dc
		dmat.emission_enabled = true
		dmat.emission = dc
		dot.material_override = dmat
		dot.position = Vector3(0.25, 0.05, -0.7 + 0.7 * float(bd))
		pan.add_child(dot)
		_blinks.append({"mat": dmat, "phase": randf() * TAU})

func _sign(txt: String, bas: Basis, pos: Vector3, off: Vector3,
		yaw_deg: float) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 44
	l.pixel_size = 0.01
	l.modulate = AMBER
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(l)
	l.global_transform = Transform3D(
		bas * Basis(Vector3(0, 1, 0), deg_to_rad(yaw_deg)),
		Transform3D(bas, pos).translated_local(off).origin)

func _ghost(size: Vector3, xf: Transform3D, off: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func _plate(size: Vector3, xf: Transform3D, off: Vector3,
		col: Color, emit: float) -> void:
	var sb := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Surfaces.metal(col) if emit <= 0.3 \
		else Destructible.make_material(col, emit)
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func _deco_box(size: Vector3, xf: Transform3D, off: Vector3,
		col: Color, emit: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Surfaces.metal(col) if emit <= 0.3 \
		else Destructible.make_material(col, emit)
	add_child(mi)
	mi.global_transform = xf
	mi.translate_object_local(off)

func _process(delta: float) -> void:
	_t += delta
	for bl in _blinks:
		(bl["mat"] as StandardMaterial3D).emission_energy_multiplier = \
			2.4 if fmod(_t + float(bl["phase"]), 1.4) < 0.75 else 0.35
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = 1.5 + 0.8 * sin(_t * 2.2)
	for cr in _core_rings:
		var n: Node3D = cr["node"]
		n.rotate_object_local(Vector3(0, 1, 0), delta * float(cr["spin"]))
	for sp in _spins:
		(sp["node"] as Node3D).rotate_object_local(Vector3(0, 1, 0),
			delta * float(sp["rate"]))
	_clk_cool = maxf(0.0, _clk_cool - delta)
	_radio_cool = maxf(0.0, _radio_cool - delta)
	# fish swim nose-first, tails beating
	for f in _fish:
		var fn: Node3D = f["node"]
		var ph := _t * 0.5 + float(f["phase"])
		var fz := sin(ph) * float(f["zr"])
		var fx := float(f["x"]) + 0.5 * sin(ph * 2.3)
		var yaw := atan2(0.5 * 2.3 * cos(ph * 2.3), cos(ph) * float(f["zr"]))
		fn.global_transform = Transform3D(
			(f["fb"] as Basis) * Basis(Vector3(0, 1, 0), yaw),
			Transform3D(f["fb"] as Basis,
			_C + (f["up"] as Vector3) * (_rF + float(f["yb"])
			+ 0.25 * sin(ph * 1.4))).translated_local(Vector3(fx, 0, fz)).origin)
		(f["tail"] as Node3D).rotation = Vector3(0,
			sin(_t * 9.0 + float(f["phase"]) * 3.0) * 0.5, 0)
	# fusion: pulses, rising discs, flickering arc bolts
	for pu in _pulses:
		(pu["mat"] as StandardMaterial3D).emission_energy_multiplier = \
			1.3 + 0.8 * sin(_t * 2.0 + float(pu["phase"]))
	for dc in _core_discs:
		var dh := fmod(_t * 1.1 + float(dc["phase"]), 4.4)
		(dc["node"] as Node3D).global_transform = Transform3D(
			dc["cb"] as Basis,
			_C + (dc["cup"] as Vector3) * (_rF + 0.8 + dh))
	for ar in _arcs:
		var an: Node3D = ar["node"]
		var fl := fmod(_t * 1.7 + float(ar["phase"]), 1.0)
		an.visible = fl < 0.22
		if fl < 0.02:
			an.rotate_object_local(Vector3(0, 1, 0), 1.7 + float(ar["phase"]))
	# drones patrol the deck arc, bobbing, always upright in gravity
	var aspan := _step * float(SEGS - 1)
	for dr in _drones:
		var ph := _t * float(dr["speed"]) + float(dr["phase"])
		var a := _a0 + aspan * (0.5 + 0.5 * sin(ph))
		var up := _pdir(a)
		var d: Node3D = dr["node"]
		d.global_transform = Transform3D(_fr(a),
			_C + up * (_rF + 1.55 + 0.18 * sin(_t * 1.7 + float(dr["phase"])))
			+ _e2 * float(dr["lane"]))
		d.rotate_object_local(Vector3(0, 1, 0), _t * 0.9 + float(dr["phase"]))
