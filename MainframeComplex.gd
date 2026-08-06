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

var _e_pts: Dictionary = {}    # hidden data-tunnel entrances
var _vp: Dictionary = {}       # room vent-hole endpoints
var _duct_end: Vector3
var _duct_out: Vector3
var _duct_bas: Basis
var _lifts: Array = []         # elevator stop lists
var _lift_busy := 0.0
var _net_probes: Array = []    # world positions MFTEST can floor-check

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


## one server rack: cabinet, four glowing slits, TWO blinking status
## lights -- every server in the building blinks
func _rack(fbR: Basis, upR: Vector3, rbase: float, off: Vector3,
		fs: float, ph: float) -> void:
	_plate(Vector3(1.3, 3.4, 1.0), Transform3D(fbR, _C + upR * (rbase + 1.7)),
		off, Color("#12161c"), 0.0)
	for sl in 4:
		_deco_box(Vector3(0.06, 0.07, 0.8),
			Transform3D(fbR, _C + upR * (rbase + 0.7 + 0.65 * float(sl))),
			off + Vector3(-fs * 0.66, 0, 0), Color("#66ff99"), 1.8)
	# EIGHT square status lights per rack -- two columns of four, eight
	# colors, staggered phases. A server wall THINKS out loud.
	for db9 in 8:
		var rdot := MeshInstance3D.new()
		var rdm := BoxMesh.new()
		rdm.size = Vector3(0.13, 0.13, 0.09)
		rdot.mesh = rdm
		var rdmat := StandardMaterial3D.new()
		rdmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var rdc: Color = [AMBER, Color("#66ff99"), Color("#ff4444"),
			Color("#7df9ff"), Color("#ff7ce9"), Color("#b388ff"),
			Color("#ffe066"), Color("#7dff5a")][db9]
		rdmat.albedo_color = rdc
		rdmat.emission_enabled = true
		rdmat.emission = rdc
		rdot.material_override = rdmat
		add_child(rdot)
		rdot.global_transform = Transform3D(fbR,
			_C + upR * (rbase + 2.62 + 0.24 * float(db9 % 4)))
		rdot.translate_object_local(off + Vector3(-fs * 0.66, 0,
			0.3 - 0.6 * float(db9 / 4)))
		_blinks.append({"mat": rdmat, "phase": ph + float(db9) * 0.29})

## spherical helpers: direction / frame at arc angle a, lateral angle b
func _sdir(a: float, beta: float) -> Vector3:
	return (_pdir(a) * cos(beta) + _e2 * sin(beta)).normalized()

func _sbas(a: float, beta: float) -> Basis:
	var upv := _sdir(a, beta)
	var ex := (-_pdir(a) * sin(beta) + _e2 * cos(beta)).normalized()
	return Basis(ex, upv, ex.cross(upv)).orthonormalized()

## one spherical floor tile (curves with gravity in BOTH axes)
func _stile(a: float, beta: float, size: Vector3, rad: float,
		col: Color) -> void:
	_plate(size, Transform3D(_sbas(a, beta), _C + _sdir(a, beta) * rad),
		Vector3.ZERO, col, 0.0)

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
	mi.mesh = Surfaces.box_mesh(size)
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = Surfaces.box_shape(size)
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func build(b, dir: Vector3) -> void:
	add_to_group("mainframe")
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

	# ---- the crust, visible from INSIDE: a big inward-facing shell so
	# the hollow planet reads as rock overhead, not floating furniture
	var crust := MeshInstance3D.new()
	var crm := SphereMesh.new()
	crm.radius = R - 1.2
	crm.height = (R - 1.2) * 2.0
	crm.radial_segments = 48
	crm.rings = 24
	crust.mesh = crm
	var crsh := Shader.new()
	crsh.code = """
shader_type spatial;
render_mode cull_front;
varying vec3 vn;
void vertex(){ vn = normalize(VERTEX); }
float h31(vec3 p){ return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vno(vec3 p){
	vec3 i = floor(p); vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h31(i), b = h31(i + vec3(1,0,0)), c = h31(i + vec3(0,1,0));
	float d = h31(i + vec3(1,1,0)), e = h31(i + vec3(0,0,1)), g = h31(i + vec3(1,0,1));
	float hh = h31(i + vec3(0,1,1)), k = h31(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
		mix(mix(e,g,f.x), mix(hh,k,f.x), f.y), f.z);
}
void fragment(){
	vec3 n = normalize(vn);
	// strata bands wrapping the shell + coarse rock grain
	float strata = 0.5 + 0.5 * sin(n.y * 40.0 + vno(n * 6.0) * 6.0);
	float grain = vno(n * 22.0);
	vec3 rock = mix(vec3(0.045, 0.055, 0.075), vec3(0.10, 0.11, 0.13),
		strata * 0.6 + grain * 0.4);
	// the dudes WIRED their crust: faint amber conduit veins snaking
	// through the rock, pulsing slow
	vec3 cell = floor(n * 14.0);
	float hv = h31(cell);
	vec3 fp = fract(n * 14.0);
	float vein = 0.0;
	if (hv < 0.3) { vein = 1.0 - smoothstep(0.02, 0.07, abs(fp.y - 0.5)); }
	else if (hv < 0.55) { vein = 1.0 - smoothstep(0.02, 0.07, abs(fp.x - 0.5)); }
	float pulse = 0.55 + 0.45 * sin(TIME * 0.7 + hv * 20.0);
	ALBEDO = rock;
	EMISSION = vec3(1.0, 0.69, 0.0) * vein * 0.32 * pulse
		+ vec3(0.2, 1.0, 0.4) * step(0.97, h31(cell + 7.0)) * 0.5 * pulse;
	ROUGHNESS = 1.0;
}
"""
	var crmat := ShaderMaterial.new()
	crmat.shader = crsh
	crust.material_override = crmat
	add_child(crust)
	crust.global_position = _C
	# ---- surface kit: rim, collar, apron, masts ----
	var rim := MeshInstance3D.new()
	var tmm := TorusMesh.new()
	tmm.inner_radius = 3.4
	tmm.outer_radius = 4.6
	rim.mesh = tmm
	rim.material_override = Surfaces.cached_emissive(AMBER, 1.6)
	add_child(rim)
	rim.global_transform = Transform3D(abas, _C + _u0 * (R + 0.1))
	for cspec in [[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, 3.4)],
			[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, -3.4)],
			[Vector3(0.6, 9.0, 14.0), Vector3(3.4, 0, 0)],
			[Vector3(0.6, 9.0, 14.0), Vector3(-3.4, 0, 0)]]:
		_ghost(cspec[0], Transform3D(abas, _C + _u0 * (R - 2.5)), cspec[1])
	# modest apron: the mouth is a door, not a monument -- and the pads
	# TILT to the local surface normal so no flat slab ever leaves an
	# invisible step where it pokes out of the curve
	for ai9 in 8:
		var aang := TAU * float(ai9) / 8.0
		var adir9 := (_u0 * cos(5.3 / R)
			+ (_e1 * cos(aang) + _e2 * sin(aang)) * sin(5.3 / R)).normalized()
		var ax9 := (_e1 * cos(aang) + _e2 * sin(aang))
		ax9 = (ax9 - adir9 * adir9.dot(ax9)).normalized()
		var ab9 := Basis(ax9.cross(adir9) * -1.0, adir9, ax9).orthonormalized()
		_ghost(Vector3(4.6, 0.5, 4.2),
			Transform3D(ab9.orthonormalized(), _C + adir9 * (R - 0.27)),
			Vector3.ZERO)
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
		gs.material_override = Surfaces.cached_emissive(AMBER, 1.8)
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
	# left section carries the ATRIUM AIRLOCK out into the hollow
	_plate(Vector3(2.2, 7.0, 0.5), awxf, Vector3(-5.2, 0, -6.05), STEEL, 0.0)
	_plate(Vector3(0.7, 7.0, 0.5), awxf, Vector3(-1.55, 0, -6.05), STEEL, 0.0)
	_plate(Vector3(2.2, 4.2, 0.5), awxf, Vector3(-3.0, 1.4, -6.05), STEEL, 0.0)
	_airlock(Transform3D(abas * Basis(Vector3(0, 1, 0), PI),
		Transform3D(abas, _C + _u0 * _rF)
		.translated_local(Vector3(-3.0, 0, -6.05)).origin))
	_plate(Vector3(2.4, 4.0, 0.5), awxf, Vector3(0, 1.75, -6.05), STEEL, 0.0)
	_plate(Vector3(2.15, 7.0, 0.5), awxf, Vector3(2.275, 0, -6.05), STEEL, 0.0)
	_plate(Vector3(1.3, 4.1, 0.5), awxf, Vector3(3.9, 1.45, -6.05), STEEL, 0.0)
	_plate(Vector3(1.6, 7.0, 0.5), awxf, Vector3(5.5, 0, -6.05), STEEL, 0.0)
	for vg in [[Vector3(1.5, 0.1, 0.1), Vector3(3.9, -0.75, -6.0)],
			[Vector3(0.1, 2.9, 0.1), Vector3(3.1, -2.1, -6.0)],
			[Vector3(0.1, 2.9, 0.1), Vector3(4.7, -2.1, -6.0)]]:
		_deco_box(vg[0], awxf, vg[1], AMBER, 1.3)
	# the duct: a full 2.4-wide WALK-IN, flush with the atrium floor --
	# the atrium's mouth of the secret vent network
	_plate(Vector3(3.2, 0.4, 4.3), awxf, Vector3(3.9, -3.65, -8.1), STEEL, 0.0)
	_plate(Vector3(3.2, 0.4, 4.3), awxf, Vector3(3.9, -0.75, -8.1), STEEL, 0.0)
	_plate(Vector3(0.4, 3.3, 4.3), awxf, Vector3(2.9, -2.05, -8.1), STEEL, 0.0)
	_plate(Vector3(0.4, 3.3, 4.3), awxf, Vector3(4.9, -2.05, -8.1), STEEL, 0.0)
	_duct_end = Transform3D(abas, _C + _u0 * (_rF + 3.25)) \
		.translated_local(Vector3(3.9, -3.45, -9.9)).origin
	_duct_out = (abas * Vector3(0, 0, -1)).normalized()
	_duct_bas = Basis(abas * Vector3(1, 0, 0), _u0, _duct_out).orthonormalized()
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
	# +X wall: 2.4m doorway to ring B east (medbay, gym, archive)
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(6.05, 0, 3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(6.05, 0, -3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 2.15, 2.4), awxf, Vector3(6.05, 2.42, 0), STEEL, 0.0)
	# -X wall: 2.4m doorway to the bunk nook
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(-6.05, 0, 3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 7.0, 4.9), awxf, Vector3(-6.05, 0, -3.65), STEEL, 0.0)
	_plate(Vector3(0.5, 2.15, 2.4), awxf, Vector3(-6.05, 2.42, 0), STEEL, 0.0)
	_lobby_land = Transform3D(abas, _C + _u0 * (_rF + 1.2)) \
		.translated_local(Vector3(-2.6, 0, -2.6)).origin
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
	_sign("MEDBAY / GYM", abas, _C + _u0 * (_rF + 4.4),
		Vector3(5.6, 0, 0), -90.0)
	_sign("ASSEMBLY / GENERATOR", abas, _C + _u0 * (_rF + 3.4),
		Vector3(0, 0, -5.7), 0.0)
	# MAP DISPENSER: a wall button that hands you the facility map
	var mbtn := MapBtn.new()
	mbtn.host = self
	var mmi := MeshInstance3D.new()
	var mbm := BoxMesh.new()
	mbm.size = Vector3(0.34, 0.34, 0.2)
	mmi.mesh = mbm
	mmi.material_override = Surfaces.cached_emissive(Color("#66ff99"), 1.9)
	mbtn.add_child(mmi)
	var mcs := CollisionShape3D.new()
	var mbs := BoxShape3D.new()
	mbs.size = Vector3(0.4, 0.4, 0.3)
	mcs.shape = mbs
	mbtn.add_child(mcs)
	add_child(mbtn)
	mbtn.global_transform = Transform3D(abas, _C + _u0 * (_rF + 1.6))
	mbtn.translate_object_local(Vector3(-5.8, 0, -3.0))
	var mlb := Label3D.new()
	mlb.text = "TAKE MAP [F]"
	mlb.font_size = 20
	mlb.pixel_size = 0.005
	mlb.modulate = Color("#66ff99")
	mlb.outline_size = 8
	mlb.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(mlb)
	mlb.global_transform = Transform3D(
		abas * Basis(Vector3(0, 1, 0), PI * 0.5),
		Transform3D(abas, _C + _u0 * (_rF + 2.1))
		.translated_local(Vector3(-5.8, 0, -3.0)).origin)
	# atrium light
	var al := MeshInstance3D.new()
	var alm := CylinderMesh.new()
	alm.top_radius = 1.1
	alm.bottom_radius = 1.1
	alm.height = 0.1
	al.mesh = alm
	al.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 2.0)
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
				hzm.material_override = Surfaces.cached_emissive(AMBER, 1.6)
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
		if i % 2 == 1 and i != HATCH_SEG and not rooms.has(i):
			# consoles NEVER share a segment with a doorway -- four of
			# them used to sit exactly in the door paths ("stepping
			# stones" that blocked every side room)
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
	# +Z wall: SOLID -- the maze this door once served is gone; the only
	# way down is the hidden elevator behind the west racks
	_plate(Vector3(20.6, 5.7, 0.5), swxf, Vector3(0, 0, 7.3), STEEL, 0.0)
	# -Z wall: solid to the eye, but a 2.6-wide breach hides behind the
	# west rack row -- the way DOWN into the computer tunnels
	_plate(Vector3(2.0, 5.7, 0.5), swxf, Vector3(-9.3, 0, -7.3), STEEL, 0.0)
	_plate(Vector3(16.0, 5.7, 0.5), swxf, Vector3(2.3, 0, -7.3), STEEL, 0.0)
	_plate(Vector3(2.6, 3.1, 0.5), swxf, Vector3(-7.0, 1.3, -7.3), STEEL, 0.0)
	_e_pts["srv"] = Transform3D(hb, _C + hup * (_r2 - 0.25)) \
		.translated_local(Vector3(-7.0, 0, -8.6)).origin
	_chatter(Transform3D(hb, _C + hup * (_r2 + 2.0)).origin, 11, -6.0)
	_chatter(Transform3D(hb, _C + hup * (_r2 + 2.0)) \
		.translated_local(Vector3(-6.0, 0, 3.0)).origin, 12, -6.0)
	# racks: four DENSE rows, glowing slits, every single server blinking
	for rx in [-7.0, -3.5, 3.5, 7.0]:
		for rz in 6:
			_rack(hb, hup, _r2, Vector3(rx, 0, -5.5 + 2.2 * float(rz)),
				signf(rx), float(rz) * 0.9 + rx * 0.31)
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
	sl9.material_override = Surfaces.cached_emissive(Color("#cfe6d8"), 1.7)
	add_child(sl9)
	sl9.global_transform = Transform3D(hb, _C + hup * (_r2 + 5.15))
	sl9.translate_object_local(Vector3(0, 0, 3.2))

	# ---- REACTOR CORE: a GIGANTIC cavern. Floor 9m below deck level,
	# ceiling 15m above it, ~30x31 footprint, every surface curving with
	# gravity in both axes. Deck + ring + comms enter at rF onto a
	# BALCONY ring with railings; a ramp descends the west side to the
	# cavern floor where the fusion assembly towers 13m tall.
	var ac := aend + (2.5 + 15.5) / _rF
	var rC := _rF - 9.0
	var cb := _fr(ac)
	var cup := _pdir(ac)
	var LATW := 15.25 / _rF          # lateral half-angle of the walls
	# floor + ceiling as 7x7 spherical tiles
	for k in 7:
		var aw9 := ac + (4.4 / _rF) * (float(k) - 3.0)
		for m in 7:
			var bw := (4.4 / _rF) * (float(m) - 3.0)
			_stile(aw9, bw, Vector3(5.0, 0.5, 4.6), rC - 0.25, DARK)
			_stile(aw9, bw, Vector3(5.0, 0.5, 4.6), _rF + 15.25, DARK)
	# curved side walls (radial fences at constant lateral angle), with
	# the comms doorway cut into the +X centre strip
	var wmid := (rC + _rF + 15.0) * 0.5
	for k in 7:
		var aw9 := ac + (4.4 / _rF) * (float(k) - 3.0)
		for sd in [1.0, -1.0]:
			var bw: float = LATW * sd
			var wb := _sbas(aw9, bw)
			var wdir := _sdir(aw9, bw)
			if sd > 0.0 and k == 3:
				# comms doorway: flanks + sill + header (2.4 x 2.75)
				_plate(Vector3(0.5, 25.0, 1.2), Transform3D(wb, _C + wdir * wmid),
					Vector3(0, 0, 1.8), STEEL, 0.0)
				_plate(Vector3(0.5, 25.0, 1.2), Transform3D(wb, _C + wdir * wmid),
					Vector3(0, 0, -1.8), STEEL, 0.0)
				_plate(Vector3(0.5, 9.5, 2.6),
					Transform3D(wb, _C + wdir * (rC + 4.25)), Vector3.ZERO, STEEL, 0.0)
				_plate(Vector3(0.5, 12.75, 2.6),
					Transform3D(wb, _C + wdir * (_rF + 9.125)), Vector3.ZERO, STEEL, 0.0)
			else:
				_plate(Vector3(0.5, 25.0, 4.7), Transform3D(wb, _C + wdir * wmid),
					Vector3.ZERO, STEEL, 0.0)
	# end walls in lateral strips (tilted to local up), door cuts in the
	# centre strip: deck opening (-Z, 10.6 wide above rF) and the ring
	# doorway (+Z, 2.4 x 3.0 above rF)
	for es in [1.0, -1.0]:
		var ae: float = ac + es * 15.5 / _rF
		for m in 7:
			var bw := (4.4 / _rF) * (float(m) - 3.0)
			var eb := _sbas(ae, bw)
			var edir := _sdir(ae, bw)
			if m >= 2 and m <= 4 and es < 0.0:
				# deck side: sill below rF, opening 10.6 wide x 6.5, header
				_plate(Vector3(4.7, 9.5, 0.5),
					Transform3D(eb, _C + edir * (rC + 4.25)), Vector3.ZERO, STEEL, 0.0)
				_plate(Vector3(4.7, 9.0, 0.5),
					Transform3D(eb, _C + edir * (_rF + 11.0)), Vector3.ZERO, STEEL, 0.0)
				if m != 3:
					# solid flank OUTSIDE the 10.6m opening (lateral 5.3..6.9)
					# -- on the outer side of the tile, not across the door
					_plate(Vector3(1.75, 6.6, 0.5),
						Transform3D(eb, _C + edir * (_rF + 3.2)),
						Vector3((-1.62 if m == 2 else 1.62), 0, 0), STEEL, 0.0)
			elif m == 3 and es > 0.0:
				# ring doorway east
				_plate(Vector3(1.2, 25.0, 0.5), Transform3D(eb, _C + edir * wmid),
					Vector3(1.8, 0, 0), STEEL, 0.0)
				_plate(Vector3(1.2, 25.0, 0.5), Transform3D(eb, _C + edir * wmid),
					Vector3(-1.8, 0, 0), STEEL, 0.0)
				_plate(Vector3(2.6, 9.5, 0.5),
					Transform3D(eb, _C + edir * (rC + 4.25)), Vector3.ZERO, STEEL, 0.0)
				_plate(Vector3(2.6, 12.5, 0.5),
					Transform3D(eb, _C + edir * (_rF + 9.25)), Vector3.ZERO, STEEL, 0.0)
			else:
				_plate(Vector3(4.7, 25.0, 0.5), Transform3D(eb, _C + edir * wmid),
					Vector3.ZERO, STEEL, 0.0)
	# BALCONY ring at rF: side ledges + end ledges, spherical tiles
	for k in 7:
		var aw9 := ac + (4.4 / _rF) * (float(k) - 3.0)
		for sd in [1.0, -1.0]:
			_stile(aw9, sd * 13.0 / _rF, Vector3(5.0, 0.5, 4.6), _rF - 0.25, DARK)
	for m in 7:
		var bw := (4.4 / _rF) * (float(m) - 3.0)
		_stile(ac + 13.0 / _rF, bw, Vector3(5.0, 0.5, 4.6), _rF - 0.25, DARK)
		_stile(ac - 13.0 / _rF, bw, Vector3(5.0, 0.5, 4.6), _rF - 0.25, DARK)
	# railings on the balcony inner edge (gap at the west ramp mouth)
	for k in 7:
		var aw9 := ac + (4.4 / _rF) * (float(k) - 3.0)
		for sd in [1.0, -1.0]:
			if sd < 0.0 and k <= 1:
				continue   # ramp mouth
			if sd > 0.0 and k == 0:
				continue   # the control booth lives here
			_plate(Vector3(0.15, 1.15, 4.7),
				Transform3D(_sbas(aw9, sd * 10.75 / _rF),
				_C + _sdir(aw9, sd * 10.75 / _rF) * (_rF + 0.55)),
				Vector3.ZERO, STEEL, 0.0)
	for m in 7:
		var bw := (4.4 / _rF) * (float(m) - 3.0)
		if absf(bw) * _rF < 11.0:
			for es in [1.0, -1.0]:
				if es < 0.0 and m >= 4:
					continue   # booth glass is the barrier on this stretch
				_plate(Vector3(4.7, 1.15, 0.15),
					Transform3D(_sbas(ac + es * 10.75 / _rF, bw),
					_C + _sdir(ac + es * 10.75 / _rF, bw) * (_rF + 0.55)),
					Vector3.ZERO, STEEL, 0.0)
	# the RAMP: five chained pitched plates down the -X side
	for rp in 5:
		var t9 := (float(rp) + 0.5) / 5.0
		var ar := ac + (-9.0 + 18.0 * t9) / _rF
		var rr := lerpf(_rF, rC, t9)
		var rb := _sbas(ar, -13.0 / _rF)
		var rxf := Transform3D(rb, _C + _sdir(ar, -13.0 / _rF) * rr)
		rxf.basis = rxf.basis * Basis(Vector3(1, 0, 0), 0.464)
		_plate(Vector3(4.2, 0.5, 4.3), rxf, Vector3.ZERO, STEEL, 0.0)
		_deco_box(Vector3(0.15, 0.5, 4.3), rxf, Vector3(2.1, 0.4, 0), STEEL, 0.0)
	# ---- the fusion assembly, floor-mounted, 13m tall ----
	var plinth := MeshInstance3D.new()
	var plm := CylinderMesh.new()
	plm.top_radius = 5.0
	plm.bottom_radius = 5.6
	plm.height = 0.8
	plinth.mesh = plm
	plinth.material_override = Surfaces.metal(Color("#12161c"))
	add_child(plinth)
	plinth.global_transform = Transform3D(cb, _C + cup * (rC + 0.4))
	var cgb := StaticBody3D.new()
	var cgc := CollisionShape3D.new()
	var cgs := CylinderShape3D.new()
	cgs.radius = 4.5
	cgs.height = 12.0
	cgc.shape = cgs
	cgb.add_child(cgc)
	add_child(cgb)
	cgb.global_transform = Transform3D(cb, _C + cup * (rC + 6.0))
	var heart := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 2.6
	hsm.height = 5.2
	heart.mesh = hsm
	heart.material_override = DatamoshStudio._fluid_material(AMBER)
	add_child(heart)
	heart.global_transform = Transform3D(cb, _C + cup * (rC + 6.2))
	var hglow := MeshInstance3D.new()
	var hgm := SphereMesh.new()
	hgm.radius = 1.5
	hgm.height = 3.0
	hglow.mesh = hgm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color("#fff2cf")
	_core_mat.emission_enabled = true
	_core_mat.emission = Color("#ffd27a")
	hglow.material_override = _core_mat
	add_child(hglow)
	hglow.global_transform = Transform3D(cb, _C + cup * (rC + 6.2))
	for fc in [1.9, 10.5]:
		var col9 := MeshInstance3D.new()
		var clm9 := CylinderMesh.new()
		clm9.top_radius = 0.6
		clm9.bottom_radius = 0.6
		clm9.height = 2.6
		col9.mesh = clm9
		col9.material_override = Surfaces.cached_emissive(AMBER, 1.6)
		add_child(col9)
		col9.global_transform = Transform3D(cb, _C + cup * (rC + fc))
	var sleeve := MeshInstance3D.new()
	var svm := CylinderMesh.new()
	svm.top_radius = 4.2
	svm.bottom_radius = 4.2
	svm.height = 11.6
	sleeve.mesh = svm
	var svmat := StandardMaterial3D.new()
	svmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	svmat.albedo_color = Color(1.0, 0.75, 0.3, 0.10)
	svmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sleeve.material_override = svmat
	add_child(sleeve)
	sleeve.global_transform = Transform3D(cb, _C + cup * (rC + 6.2))
	for ri in 3:
		var ring := MeshInstance3D.new()
		var rgm := TorusMesh.new()
		rgm.inner_radius = 5.4 + 0.9 * float(ri)
		rgm.outer_radius = 5.85 + 0.9 * float(ri)
		ring.mesh = rgm
		ring.material_override = Surfaces.cached_emissive(
			AMBER.lightened(0.2), 1.8)
		add_child(ring)
		ring.global_transform = Transform3D(cb, _C + cup * (rC + 6.2))
		ring.rotate_object_local(Vector3(1, 0, 0),
			[0.35, -0.22, 0.12][ri])
		_core_rings.append({"node": ring, "spin": 0.4 + 0.35 * float(ri)})
	for py in 6:
		var pang := TAU * float(py) / 6.0
		var pyl := MeshInstance3D.new()
		var pym := BoxMesh.new()
		pym.size = Vector3(0.5, 8.5, 0.5)
		pyl.mesh = pym
		pyl.material_override = Surfaces.metal(STEEL)
		add_child(pyl)
		pyl.global_transform = Transform3D(cb, _C + cup * (rC + 3.8))
		pyl.translate_object_local(Vector3(cos(pang) * 8.8, 0, sin(pang) * 8.8))
		pyl.rotate_object_local(Vector3(-sin(pang), 0, cos(pang)) * -1.0, 0.55)
		var tip := MeshInstance3D.new()
		var tpm2 := SphereMesh.new()
		tpm2.radius = 0.32
		tpm2.height = 0.64
		tip.mesh = tpm2
		tip.material_override = Surfaces.cached_emissive(AMBER, 2.2)
		add_child(tip)
		tip.global_transform = Transform3D(cb, _C + cup * (rC + 8.0))
		tip.translate_object_local(Vector3(cos(pang) * 6.6, 0, sin(pang) * 6.6))
	for di2 in 4:
		var disc := MeshInstance3D.new()
		var dcm := CylinderMesh.new()
		dcm.top_radius = 3.3
		dcm.bottom_radius = 3.3
		dcm.height = 0.07
		disc.mesh = dcm
		disc.material_override = Surfaces.cached_emissive(
			AMBER.lightened(0.35), 2.0)
		add_child(disc)
		_core_discs.append({"node": disc, "cb": cb, "cup": cup,
			"phase": float(di2) * 2.3, "base": rC + 1.2, "span": 9.5})
	var collector := MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.5
	ccm.bottom_radius = 3.4
	ccm.height = 2.2
	collector.mesh = ccm
	collector.material_override = Surfaces.metal(Color("#12161c"))
	add_child(collector)
	collector.global_transform = Transform3D(cb, _C + cup * (rC + 13.0))
	var fring := MeshInstance3D.new()
	var frm := TorusMesh.new()
	frm.inner_radius = 8.0
	frm.outer_radius = 8.4
	fring.mesh = frm
	fring.material_override = Surfaces.cached_emissive(AMBER, 1.3)
	add_child(fring)
	fring.global_transform = Transform3D(cb, _C + cup * (rC + 0.1))
	# lightning: jagged arc bolts that flicker around the heart
	for ab in 5:
		var arc9 := Node3D.new()
		add_child(arc9)
		arc9.global_transform = Transform3D(cb, _C + cup * (rC + 6.2))
		arc9.rotate_object_local(Vector3(0, 1, 0), TAU * float(ab) / 5.0)
		for seg9 in 3:
			var bolt := MeshInstance3D.new()
			var bom := BoxMesh.new()
			bom.size = Vector3(0.08, 0.08, 1.9)
			bolt.mesh = bom
			bolt.position = Vector3(2.9 + 0.9 * float(seg9),
				0.9 - 0.9 * float(seg9), 0)
			bolt.rotation_degrees = Vector3(0, 24.0 * float(seg9) - 20.0,
				38.0 - 34.0 * float(seg9))
			bolt.material_override = Surfaces.cached_emissive(
				Color("#fff2cf"), 2.6)
			arc9.add_child(bolt)
		_arcs.append({"node": arc9, "phase": float(ab) * 1.3})
	# ---- CONTROL BOOTH on the -Z balcony, east of the deck door: a
	# glass-fronted room whose WINDOW looks out over the whole cavern
	var bthb := _sbas(ac - 12.6 / _rF, 8.1 / _rF)
	var bthd := _sdir(ac - 12.6 / _rF, 8.1 / _rF)
	var glf := _sbas(ac - 10.7 / _rF, 8.1 / _rF)
	var gld := _sdir(ac - 10.7 / _rF, 8.1 / _rF)
	for gspec9 in [[Vector3(7.4, 3.4, 0.12), glf, gld, Vector3.ZERO],
			[Vector3(0.12, 3.4, 4.6), _sbas(ac - 12.9 / _rF, 11.7 / _rF),
			_sdir(ac - 12.9 / _rF, 11.7 / _rF), Vector3.ZERO]]:
		var gl9 := StaticBody3D.new()
		var gmi9 := MeshInstance3D.new()
		var gbm9 := BoxMesh.new()
		gbm9.size = gspec9[0]
		gmi9.mesh = gbm9
		var gmat9 := StandardMaterial3D.new()
		gmat9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat9.albedo_color = Color(1.0, 0.85, 0.5, 0.14)
		gmi9.material_override = gmat9
		gl9.add_child(gmi9)
		var gcs9 := CollisionShape3D.new()
		var gbs9 := BoxShape3D.new()
		gbs9.size = gspec9[0]
		gcs9.shape = gbs9
		gl9.add_child(gcs9)
		add_child(gl9)
		gl9.global_transform = Transform3D(gspec9[1] as Basis,
			_C + (gspec9[2] as Vector3) * (_rF + 1.7))
		gl9.translate_object_local(gspec9[3] as Vector3)
	# booth inner side wall with a 1.2m door gap onto the balcony walk
	_plate(Vector3(0.5, 3.4, 2.6), Transform3D(_sbas(ac - 13.6 / _rF, 4.6 / _rF),
		_C + _sdir(ac - 13.6 / _rF, 4.6 / _rF) * (_rF + 1.7)),
		Vector3.ZERO, STEEL, 0.0)
	# desk + tilted amber panel + status dots inside
	_plate(Vector3(3.2, 1.1, 0.9), Transform3D(bthb, _C + bthd * (_rF + 0.55)),
		Vector3(0, 0, 1.4), Color("#12161c"), 0.0)
	var bpan := MeshInstance3D.new()
	bpan.mesh = IcosaColony._cham_mesh(0.9, 0.05, 3.3, 0.22)
	bpan.material_override = Surfaces.cached_emissive(AMBER.darkened(0.1), 1.6)
	add_child(bpan)
	bpan.global_transform = Transform3D(
		bthb * Basis(Vector3(0, 0, 1), 0.5), _C + bthd * (_rF + 1.25))
	bpan.translate_object_local(Vector3(0, 0, 1.4))
	_sign("CONTROL BOOTH", bthb, _C + bthd * (_rF + 4.1),
		Vector3(0, 0, -1.0), 0.0)
	_sign("REACTOR CORE", cb, _C + cup * (_rF + 6.4),
		Vector3(0, 0, -14.4), 0.0)
	_sign("COMMUNICATIONS", cb, _C + cup * (_rF + 3.9),
		Vector3(14.6, 0, 0), -90.0)
	_sign("CONTROL DECK / ATRIUM", cb, _C + cup * (_rF + 7.6),
		Vector3(0, 0, -14.6), 180.0)
	_core_noise(Transform3D(cb, _C + cup * (rC + 6.0)).origin)
	_chatter(Transform3D(cb, _C + cup * (rC + 2.0)).origin, 61, -8.0)
	_chatter(Transform3D(cb, _C + cup * (_rF + 1.0)) \
		.translated_local(Vector3(10.0, 0, 10.0)).origin, 62, -10.0)

	# ---- the wings ----
	_service_wing()
	_comms_room(cb, ac)
	# ---- the planet-wide hallway rings + their rooms ----
	_rings()
	# lower floors + the planetary core, all elevator-served
	_lower_floors()
	# ---- LAST, once every room exists: the secret networks, laid
	# through the space that provably nobody else is using ----
	_networks()
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
		tip.material_override = Surfaces.cached_emissive(AMBER, 2.4)
		d.add_child(tip)
		var pod9 := MeshInstance3D.new()
		var pdm := CylinderMesh.new()
		pdm.top_radius = 0.16
		pdm.bottom_radius = 0.05
		pdm.height = 0.12
		pod9.mesh = pdm
		pod9.position = Vector3(0, -0.21, 0)
		pod9.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.9)
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
			gring.material_override = Surfaces.cached_emissive(AMBER, 1.6)
			add_child(gring)
			gring.global_transform = Transform3D(fb, _C + up * (_rF + 0.14))
			gring.translate_object_local(Vector3(0, 0, zs * 3.0))
			var bunk := MeshInstance3D.new()
			bunk.mesh = IcosaColony._cham_mesh(2.4, 0.3, 1.6, 0.3)
			bunk.material_override = Surfaces.cached_emissive(STEEL, 0.25)
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
	# the corridor no longer dead-ends: a doorway through to ring B west
	# (kitchen, trophy hall, the cockpit beyond)
	var bend := -(_a0 + _step * 4.0)
	var cxf9 := Transform3D(_fx(bend), _C + _pdx(bend) * (_rF + 1.6))
	_plate(Vector3(0.4, 3.9, 0.95), cxf9, Vector3(-2.65, 0, 1.475), STEEL, 0.0)
	_plate(Vector3(0.4, 3.9, 0.95), cxf9, Vector3(-2.65, 0, -1.475), STEEL, 0.0)
	_plate(Vector3(0.4, 1.05, 2.0), cxf9, Vector3(-2.65, 1.425, 0), STEEL, 0.0)
	# collar: the ring hallway is taller and wider than the bunk
	# corridor -- plate over the size difference so the joint is sealed
	_plate(Vector3(0.4, 1.6, 6.4), cxf9, Vector3(-2.65, 2.75, 0), STEEL, 0.0)
	_plate(Vector3(0.4, 5.5, 1.2), cxf9, Vector3(-2.65, 0.65, 2.55), STEEL, 0.0)
	_plate(Vector3(0.4, 5.5, 1.2), cxf9, Vector3(-2.65, 0.65, -2.55), STEEL, 0.0)
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
	_plate(Vector3(0.5, 5.2, 1.5), vwxf, Vector3(5.8, 0, -5.05), STEEL, 0.0)
	_plate(Vector3(0.5, 5.2, 7.7), vwxf, Vector3(5.8, 0, 1.95), STEEL, 0.0)
	_plate(Vector3(0.5, 2.35, 2.4), vwxf, Vector3(5.8, 1.425, -3.1), STEEL, 0.0)
	_e_pts["gold"] = Transform3D(fb4, _C + up4 * (rV - 0.25)) \
		.translated_local(Vector3(7.0, 0, -3.1)).origin
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
		gr2.material_override = Surfaces.cached_emissive(GOLD, 1.8)
		add_child(gr2)
		gr2.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.14))
		gr2.translate_object_local(Vector3(vb[0], 0, vb[1]))
		var vbk := MeshInstance3D.new()
		vbk.mesh = IcosaColony._cham_mesh(3.2, 0.4, 1.8, 0.35)
		vbk.material_override = Surfaces.cached_emissive(Color("#3a2436"), 0.3)
		add_child(vbk)
		vbk.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.7))
		vbk.translate_object_local(Vector3(vb[0], 0, vb[1]))
		var plw := MeshInstance3D.new()
		var plwm := SphereMesh.new()
		plwm.radius = 0.34
		plwm.height = 0.4
		plw.mesh = plwm
		plw.material_override = Surfaces.cached_emissive(GOLD.lightened(0.3), 0.6)
		add_child(plw)
		plw.global_transform = Transform3D(fb4, _C + up4 * (rV + 1.0))
		plw.translate_object_local(Vector3(vb[0] + 1.1, 0, vb[1]))
	var rug := MeshInstance3D.new()
	var rugm := CylinderMesh.new()
	rugm.top_radius = 2.2
	rugm.bottom_radius = 2.2
	rugm.height = 0.06
	rug.mesh = rugm
	rug.material_override = Surfaces.cached_emissive(Color("#4a1a2e"), 0.2)
	add_child(rug)
	rug.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.03))
	var rugr := MeshInstance3D.new()
	var rugrm := TorusMesh.new()
	rugrm.inner_radius = 2.14
	rugrm.outer_radius = 2.26
	rugr.mesh = rugrm
	rugr.material_override = Surfaces.cached_emissive(GOLD, 1.4)
	add_child(rugr)
	rugr.global_transform = Transform3D(fb4, _C + up4 * (rV + 0.06))
	var vl := MeshInstance3D.new()
	var vlm := CylinderMesh.new()
	vlm.top_radius = 1.0
	vlm.bottom_radius = 1.0
	vlm.height = 0.08
	vl.mesh = vlm
	vl.material_override = Surfaces.cached_emissive(Color("#fff3d0"), 2.0)
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

## ==================== THE RINGS: planet-wide hallways ====================
## Two great-circle hallway rings cross at the atrium and at the antipode
## cockpit. Ring A follows the deck's arc family (_fr, lateral = e2),
## ring B the bunk family (_fx, lateral = e1). 6m wide, 4.5 tall.

## fam 0: X = e2 lateral, Z = arc tangent (the _fr family unchanged).
## fam 1: X = e1 lateral, Y radial, Z = MINUS the arc tangent -- keeps
## X as "sideways" in both families so every builder shares math.
func _abas9(fam: int, a: float) -> Basis:
	if fam == 0:
		return _fr(a)
	var upb := _pdx(a)
	var tb := (-_u0 * sin(a) + _e2 * cos(a)).normalized()
	return Basis(_e1, upb, -tb).orthonormalized()

func _aup9(fam: int, a: float) -> Vector3:
	return _pdir(a) if fam == 0 else _pdx(a)

static func _awrap(d: float) -> float:
	return fposmod(d + PI, TAU) - PI

## hallway segments from a_from to a_to. doors: [[a_center, side], ...]
## -- segments overlapping a door centre skip that side's wall (the
## room's own doorway wall stands 10cm behind the gap).
func _hall(fam: int, a_from: float, a_to: float, doors: Array) -> void:
	var m := (a_to - a_from) * _rF
	var n := maxi(1, int(ceil((m - 0.4) / 4.3)))
	var st2 := ((m - 4.6) / float(n - 1)) / _rF if n > 1 else 0.0
	for k in n:
		var a := a_from + 2.3 / _rF + st2 * float(k)
		var fb := _abas9(fam, a)
		var up := _aup9(fam, a)
		_plate(Vector3(6.6, 0.5, 5.0), Transform3D(fb, _C + up * (_rF - 0.25)),
			Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(6.6, 0.5, 5.0), Transform3D(fb, _C + up * (_rF + 4.75)),
			Vector3.ZERO, DARK, 0.0)
		var wxf := Transform3D(fb, _C + up * (_rF + 2.25))
		for ws in [1.0, -1.0]:
			var door := false
			for d in doors:
				if float(d[1]) == ws and absf(_awrap(a - float(d[0]))) * _rF < 2.4:
					door = true
			if not door:
				_plate(Vector3(0.5, 5.5, 5.0), wxf, Vector3(ws * 3.05, 0, 0), STEEL, 0.0)
				_deco_box(Vector3(0.06, 0.16, 5.0), wxf,
					Vector3(ws * 2.72, -1.3, 0), AMBER, 1.6)
		# rib + every-other ceiling light
		_deco_box(Vector3(0.2, 4.5, 0.2), wxf, Vector3(2.62, 0, 2.3), STEEL, 0.0)
		_deco_box(Vector3(0.2, 4.5, 0.2), wxf, Vector3(-2.62, 0, 2.3), STEEL, 0.0)
		_deco_box(Vector3(5.44, 0.2, 0.2), wxf, Vector3(0, 2.15, 2.3), STEEL, 0.0)
		if k % 2 == 0:
			_deco_box(Vector3(0.5, 0.08, 3.0),
				Transform3D(fb, _C + up * (_rF + 4.35)), Vector3.ZERO,
				Color("#f2ead8"), 2.2)

## a standard side room hanging off a ring hallway at angle ac, side s.
## Interior ~9m lateral x 9.6 arc x 4.5 tall, 2.4x3.0 doorway. Returns
## {fb, up, cx} for the dressing pass.
func _ring_room(fam: int, ac: float, s: float, name: String,
		vholes: int = 0) -> Dictionary:
	var fb := _abas9(fam, ac)
	var up := _aup9(fam, ac)
	_plate(Vector3(9.7, 0.5, 9.6), Transform3D(fb, _C + up * (_rF - 0.25)),
		Vector3(s * 8.3, 0, 0), DARK, 0.0)
	_plate(Vector3(9.7, 0.5, 9.6), Transform3D(fb, _C + up * (_rF + 4.75)),
		Vector3(s * 8.3, 0, 0), DARK, 0.0)
	var wxf := Transform3D(fb, _C + up * (_rF + 2.25))
	# near wall with the doorway
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 3.55, 0, 3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 3.55, 0, -3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 2.0, 2.4), wxf, Vector3(s * 3.55, 1.75, 0), STEEL, 0.0)
	# far wall -- solid, or carrying 1-2 enterable wall vents (1.2x2.2,
	# amber grille frame) that feed the secret vent network
	var vent_pts: Array = []
	if vholes == 0:
		_plate(Vector3(0.5, 5.5, 9.6), wxf, Vector3(s * 13.05, 0, 0), STEEL, 0.0)
	else:
		var zs9: Array = [0.0] if vholes == 1 else [-2.8, 2.8]
		if vholes == 1:
			_plate(Vector3(0.5, 5.5, 3.35), wxf, Vector3(s * 13.05, 0, 3.125), STEEL, 0.0)
			_plate(Vector3(0.5, 5.5, 3.35), wxf, Vector3(s * 13.05, 0, -3.125), STEEL, 0.0)
		else:
			_plate(Vector3(0.5, 5.5, 3.0), wxf, Vector3(s * 13.05, 0, 0), STEEL, 0.0)
			_plate(Vector3(0.5, 5.5, 0.7), wxf, Vector3(s * 13.05, 0, 4.45), STEEL, 0.0)
			_plate(Vector3(0.5, 5.5, 0.7), wxf, Vector3(s * 13.05, 0, -4.45), STEEL, 0.0)
		for z9 in zs9:
			var zf: float = float(z9)
			# a WALK-IN vent: 2.6 x 2.6 opening flush with the floor.
			# nothing to step over, nothing clipping your hitbox.
			_plate(Vector3(0.5, 2.65, 2.6), wxf, Vector3(s * 13.05, 1.425, zf), STEEL, 0.0)
			_deco_box(Vector3(0.08, 2.7, 0.08), wxf, Vector3(s * 12.78, -0.9, zf - 1.36), AMBER, 1.3)
			_deco_box(Vector3(0.08, 2.7, 0.08), wxf, Vector3(s * 12.78, -0.9, zf + 1.36), AMBER, 1.3)
			_deco_box(Vector3(0.08, 0.08, 2.85), wxf, Vector3(s * 12.78, 0.48, zf), AMBER, 1.3)
			vent_pts.append({"p": Transform3D(fb, _C + up * (_rF - 0.25)) \
				.translated_local(Vector3(s * 13.3, 0, zf)).origin,
				"o": (fb * Vector3(s, 0, 0)).normalized(),
				"b": Basis(fb * Vector3(0, 0, 1), up, fb * Vector3(s, 0, 0))
				.orthonormalized()})
	_plate(Vector3(9.5, 5.5, 0.5), wxf, Vector3(s * 8.3, 0, 4.55), STEEL, 0.0)
	_plate(Vector3(9.5, 5.5, 0.5), wxf, Vector3(s * 8.3, 0, -4.55), STEEL, 0.0)
	var rl := MeshInstance3D.new()
	var rlm := CylinderMesh.new()
	rlm.top_radius = 0.8
	rlm.bottom_radius = 0.8
	rlm.height = 0.08
	rl.mesh = rlm
	rl.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 1.9)
	add_child(rl)
	rl.global_transform = Transform3D(fb, _C + up * (_rF + 4.45))
	rl.translate_object_local(Vector3(s * 8.3, 0, 0))
	_sign(name, fb, _C + up * (_rF + 3.6), Vector3(s * 2.7, 0, 0),
		90.0 if s < 0.0 else -90.0)
	return {"fb": fb, "up": up, "cx": s * 8.3, "vents": vent_pts}

## a big room sitting ON a ring: the hallway enters through a doorway in
## each end wall. half_arc/half_lat in meters, h interior height.
func _big_room(fam: int, ac: float, half_arc: float, half_lat: float,
		h: float, name: String, holes: Array = []) -> Dictionary:
	var fb := _abas9(fam, ac)
	var up := _aup9(fam, ac)
	_arc_floor_f(fam, ac, half_lat * 2.0 + 0.6, half_arc * 2.0 + 0.8,
		_rF - 0.25, 0.0)
	_arc_floor_f(fam, ac, half_lat * 2.0 + 0.6, half_arc * 2.0 + 0.8,
		_rF + h + 0.25, 0.0)
	# curved side walls, strip by strip
	var m := half_arc * 2.0
	var n := maxi(1, int(ceil((m - 0.4) / 4.3)))
	var st2 := ((m - 4.6) / float(n - 1)) / _rF if n > 1 else 0.0
	for k in n:
		var a := ac + st2 * (float(k) - float(n - 1) * 0.5)
		var wxk := Transform3D(_abas9(fam, a), _C + _aup9(fam, a) * (_rF + h * 0.5))
		for sd9 in [1.0, -1.0]:
			var hole9 := false
			for hh in holes:
				if int(hh[0]) == k and float(hh[1]) == sd9:
					hole9 = true
			if hole9:
				# hidden 2.4x2.6 breach -- a wall panel somebody removed
				_plate(Vector3(0.5, h + 1.0, 1.1), wxk,
					Vector3(sd9 * (half_lat + 0.25), 0, 1.75), STEEL, 0.0)
				_plate(Vector3(0.5, h + 1.0, 1.1), wxk,
					Vector3(sd9 * (half_lat + 0.25), 0, -1.75), STEEL, 0.0)
				_plate(Vector3(0.5, h - 2.1, 2.4), wxk,
					Vector3(sd9 * (half_lat + 0.25), 1.55, 0), STEEL, 0.0)
			else:
				_plate(Vector3(0.5, h + 1.0, 4.6), wxk,
					Vector3(sd9 * (half_lat + 0.25), 0, 0), STEEL, 0.0)
		if k % 2 == 0:
			_deco_box(Vector3(1.0, 0.08, 3.0),
				Transform3D(_abas9(fam, a), _C + _aup9(fam, a) * (_rF + h - 0.15)),
				Vector3.ZERO, Color("#f2ead8"), 2.2)
	# end walls with ring doorways
	for es in [1.0, -1.0]:
		var ae: float = ac + es * half_arc / _rF
		var eb := _abas9(fam, ae)
		var eu := _aup9(fam, ae)
		var exf := Transform3D(eb, _C + eu * (_rF + h * 0.5))
		var fl := half_lat + 0.3 - 1.2
		_plate(Vector3(fl, h + 1.0, 0.5), exf, Vector3(1.2 + fl * 0.5, 0, 0), STEEL, 0.0)
		_plate(Vector3(fl, h + 1.0, 0.5), exf, Vector3(-1.2 - fl * 0.5, 0, 0), STEEL, 0.0)
		_plate(Vector3(2.4, h - 2.5, 0.5), exf, Vector3(0, 1.75, 0), STEEL, 0.0)
		_sign(name, eb, _C + eu * (_rF + 3.7), Vector3(0, 0, es * 0.8),
			0.0 if es > 0.0 else 180.0)
	return {"fb": fb, "up": up}

## _arc_floor generalised to either arc family
func _arc_floor_f(fam: int, a_c: float, width: float, len_z: float,
		rad: float, xoff: float) -> void:
	var n := maxi(1, int(ceil((len_z - 0.4) / 4.3)))
	var stp := ((len_z - 4.6) / float(n - 1)) / rad if n > 1 else 0.0
	for k in n:
		var a := a_c + stp * (float(k) - float(n - 1) * 0.5)
		_plate(Vector3(width, 0.5, 4.6),
			Transform3D(_abas9(fam, a), _C + _aup9(fam, a) * rad),
			Vector3(xoff, 0, 0), DARK, 0.0)

## a plate frame whose floor follows the sphere in BOTH directions:
## grid of tilted tiles around direction dc (used for the cockpit cap)
func _cap_tiles(half_n: int, rad: float, pitch: float, mat_col: Color) -> void:
	for i in range(-half_n, half_n + 1):
		for j in range(-half_n, half_n + 1):
			var dirv := (-_u0 + _e1 * (float(i) * pitch / rad)
				+ _e2 * (float(j) * pitch / rad)).normalized()
			var ex := (_e2 - dirv * dirv.dot(_e2)).normalized()
			var tb := Basis(ex, dirv, ex.cross(dirv)).orthonormalized()
			_plate(Vector3(pitch + 0.7, 0.5, pitch + 0.7),
				Transform3D(tb, _C + dirv * rad), Vector3.ZERO, mat_col, 0.0)

## the cockpit SHELL at the antipode: spherical-cap floor + ceiling,
## octagon walls, four ring doorways. Dressing arrives in the cockpit
## pass -- this guarantees the rings land somewhere sealed.
func _cockpit_shell() -> void:
	_cap_tiles(3, _rF - 0.25, 5.2, DARK)
	_cap_tiles(3, _rF + 8.25, 5.2, DARK)
	for w in 8:
		var wang := TAU * float(w) / 8.0
		var latv := _e1 * cos(wang) + _e2 * sin(wang)
		var dirw := (-_u0 * cos(15.0 / _rF) + latv * sin(15.0 / _rF)).normalized()
		var tz := (-latv + dirw * dirw.dot(latv)).normalized()
		var wb := Basis(dirw.cross(tz), dirw, tz).orthonormalized()
		var wxf := Transform3D(wb, _C + dirw * (_rF + 4.0))
		if w % 2 == 0:
			# ring doorway wall: flanks + header, 2.4x3.0 opening
			_plate(Vector3(5.5, 9.0, 0.6), wxf, Vector3(3.95, 0, 0), STEEL, 0.0)
			_plate(Vector3(5.5, 9.0, 0.6), wxf, Vector3(-3.95, 0, 0), STEEL, 0.0)
			_plate(Vector3(2.4, 5.5, 0.6), wxf, Vector3(0, 1.75, 0), STEEL, 0.0)
			_sign("PLANET CONTROL", wb,
				_C + dirw * (_rF + 3.7), Vector3(0, 0, -0.9), 180.0)
		else:
			_plate(Vector3(13.4, 9.0, 0.6), wxf, Vector3.ZERO, STEEL, 0.0)

## ring A: east from the reactor, around the antipode, back in through
## the generator/assembly wing. Ring B: both directions out of the
## atrium, meeting at the cockpit, swallowing the old bunk end cap.
func _rings() -> void:
	# --- ring A east: reactor far wall -> DUDE A.I -> cockpit ---
	_hall(0, 1.621, 2.47, [[1.75, 1.0], [2.02, -1.0]])
	var tr := _ring_room(0, 1.75, 1.0, "TAPE ARCHIVE", 2)
	_dress_tape(tr)
	var nf := _ring_room(0, 2.02, -1.0, "NOODLE FARM", 2)
	_dress_farm(nf)
	_vp["tape"] = tr["vents"]
	_vp["farm"] = nf["vents"]
	var ai := _big_room(0, 2.685, 13.3, 7.0, 7.0, "DUDE A.I.", [[5, -1.0]])
	set_meta("ai_room_a", 2.685)
	_dress_ai()
	_e_pts["ai"] = Transform3D(_fr(2.8033), _C + _pdir(2.8033) * (_rF - 0.25))\
		.translated_local(Vector3(-8.5, 0, 0)).origin
	# --- ring A west: cockpit -> server hall 2 -> generator wing ---
	_hall(0, 3.383, 3.63, [])
	var s2 := _big_room(0, 3.775, 9.0, 8.0, 6.5, "SERVER HALL 2")
	set_meta("server2_a", 3.775)
	# the second server farm, opposite side of the planet from the first
	for rr in 7:
		var a_r: float = 3.775 + (-6.6 + 2.2 * float(rr)) / _rF
		for rx in [-5.5, -1.8, 1.8, 5.5]:
			_rack(_fr(a_r), _pdir(a_r), _rF, Vector3(float(rx), 0, 0),
				signf(float(rx)), float(rr) * 0.7 + float(rx) * 0.27)
	_chatter(Transform3D(_fr(3.775), _C + _pdir(3.775) * (_rF + 2.0)).origin,
		211, -6.0)
	_chatter(Transform3D(_fr(3.72), _C + _pdir(3.72) * (_rF + 2.0)) \
		.translated_local(Vector3(5.0, 0, 0)).origin, 212, -7.0)
	# aT: exact centre of hall segment 1 -- the second top-floor airlock
	# sits here, opposite side of the planet from the atrium's
	var aT := 3.92 + 2.3 / _rF + (((5.172 - 3.92) * _rF - 4.6) / 17.0) / _rF
	_hall(0, 3.92, 5.172, [[4.35, -1.0], [4.75, 1.0], [aT, 1.0]])
	var tfb := _fr(aT)
	_airlock(Transform3D(tfb * Basis(Vector3(0, 1, 0), PI * 0.5),
		Transform3D(tfb, _C + _pdir(aT) * _rF)
		.translated_local(Vector3(3.05, 0, 0)).origin))
	var tawx := Transform3D(tfb, _C + _pdir(aT) * (_rF + 2.25))
	_plate(Vector3(0.5, 5.5, 1.2), tawx, Vector3(3.05, 0, 1.9), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 1.2), tawx, Vector3(3.05, 0, -1.9), STEEL, 0.0)
	_plate(Vector3(0.5, 1.95, 3.1), tawx, Vector3(3.05, 1.8, 0), STEEL, 0.0)
	var st9 := _ring_room(0, 4.35, -1.0, "STORAGE", 2)
	_dress_storage(st9)
	var wk := _ring_room(0, 4.75, 1.0, "WORKSHOP", 2)
	_dress_workshop(wk)
	_vp["storage"] = st9["vents"]
	_vp["workshop"] = wk["vents"]
	# --- ring A northwest: assembly -> atrium (the old crawl tube is
	# now a real hallway; ventilation becomes a secret system) ---
	_hall(0, 5.682, 6.185, [])
	# --- ring B east: atrium +X -> medbay/gym/archive -> cockpit ---
	_hall(1, 0.098, 2.897, [[0.75, -1.0], [1.5, 1.0], [1.92, 1.0], [2.3, -1.0]])
	var mb := _ring_room(1, 0.75, -1.0, "MEDBAY", 2)
	_dress_medbay(mb)
	var gy := _ring_room(1, 1.5, 1.0, "GYMNASIUM", 2)
	_dress_gym(gy)
	_grand_aquarium(1.92)
	var ar := _ring_room(1, 2.3, -1.0, "ARCHIVE", 2)
	_dress_archive(ar)
	_vp["medbay"] = mb["vents"]
	_vp["gym"] = gy["vents"]
	_vp["archive"] = ar["vents"]
	# --- ring B west: cockpit -> kitchen/trophy hall -> bunk wing ---
	_hall(1, 3.383, 5.831, [[4.0, 1.0], [4.8, -1.0]])
	var kt := _ring_room(1, 4.0, 1.0, "KITCHEN", 2)
	_dress_kitchen(kt)
	var tp := _ring_room(1, 4.8, -1.0, "TROPHY HALL", 1)
	_dress_trophy(tp)
	_vp["kitchen"] = kt["vents"]
	_vp["trophy"] = tp["vents"]
	_cockpit_shell()
	_cockpit_dress()

## PLANET CONTROL: a giant starship-bridge cockpit filling the antipode
## -- NOT an airplane nose. A live globe of the planet floats over the
## central dais, the OVERCLOCK lever stands under it, and eight console
## banks + wall screens wrap the whole room.
func _cockpit_dress() -> void:
	var ab0 := _fr(PI)
	var au := -_u0
	# central dais + rail ring
	var dais := MeshInstance3D.new()
	var dm9 := CylinderMesh.new()
	dm9.top_radius = 4.0
	dm9.bottom_radius = 4.4
	dm9.height = 0.5
	dais.mesh = dm9
	dais.material_override = Surfaces.metal(Color("#20262e"))
	add_child(dais)
	dais.global_transform = Transform3D(ab0, _C + au * (_rF + 0.25))
	var drail := MeshInstance3D.new()
	var drm := TorusMesh.new()
	drm.inner_radius = 4.35
	drm.outer_radius = 4.55
	drail.mesh = drm
	drail.material_override = Surfaces.cached_emissive(AMBER, 1.5)
	add_child(drail)
	drail.global_transform = Transform3D(ab0, _C + au * (_rF + 0.55))
	# THE GLOBE: the planet's own live shader, floating and turning
	var pmat: Material = null
	if _b != null and _b.node != null:
		for pc in (_b.node as Node).get_children():
			if pc is MeshInstance3D:
				pmat = (pc as MeshInstance3D).material_override
				break
	var globe := MeshInstance3D.new()
	var gbm := SphereMesh.new()
	gbm.radius = 2.2
	gbm.height = 4.4
	globe.mesh = gbm
	globe.material_override = pmat if pmat != null \
		else Surfaces.cached_emissive(AMBER, 1.4)
	add_child(globe)
	globe.global_transform = Transform3D(ab0, _C + au * (_rF + 4.4))
	_spins.append({"node": globe, "rate": 0.25})
	var gring := MeshInstance3D.new()
	var grm9 := TorusMesh.new()
	grm9.inner_radius = 2.7
	grm9.outer_radius = 2.85
	gring.mesh = grm9
	gring.material_override = Surfaces.cached_emissive(AMBER, 1.9)
	add_child(gring)
	gring.global_transform = Transform3D(ab0, _C + au * (_rF + 4.4))
	gring.rotate_object_local(Vector3(1, 0, 0), 0.35)
	_core_rings.append({"node": gring, "spin": 0.5})
	# THE OVERCLOCK LEVER on the dais, under the globe
	var lped := MeshInstance3D.new()
	var lpm2 := CylinderMesh.new()
	lpm2.top_radius = 0.4
	lpm2.bottom_radius = 0.55
	lpm2.height = 1.1
	lped.mesh = lpm2
	lped.material_override = Surfaces.metal(Color("#12161c"))
	add_child(lped)
	lped.global_transform = Transform3D(ab0, _C + au * (_rF + 1.05))
	lped.translate_object_local(Vector3(2.4, 0, 0))
	var lever := MeshInstance3D.new()
	var lvm := BoxMesh.new()
	lvm.size = Vector3(0.1, 0.9, 0.1)
	lever.mesh = lvm
	lever.material_override = Surfaces.cached_emissive(Color("#ff4444"), 1.6)
	add_child(lever)
	lever.global_transform = Transform3D(ab0, _C + au * (_rF + 2.0))
	lever.translate_object_local(Vector3(2.4, 0, 0))
	var trig := Area3D.new()
	var tcs := CollisionShape3D.new()
	var tss := SphereShape3D.new()
	tss.radius = 1.4
	tcs.shape = tss
	trig.add_child(tcs)
	add_child(trig)
	trig.global_transform = Transform3D(ab0, _C + au * (_rF + 1.6))
	trig.translate_object_local(Vector3(2.4, 0, 0))
	trig.body_entered.connect(func(bod):
		if _clk_cool > 0.0 or not bod.is_in_group("player"):
			return
		_clk_cool = 1.2
		_clk_idx = (_clk_idx + 1) % 3
		var spd: float = [0.3, 1.0, 3.0][_clk_idx]
		if pmat != null and pmat is ShaderMaterial:
			(pmat as ShaderMaterial).set_shader_parameter("clk", spd)
		lever.rotation = Vector3.ZERO
		lever.rotate_object_local(Vector3(0, 0, 1), [-0.5, 0.0, 0.5][_clk_idx])
		Sfx.play("click", -8.0)
		var m9 = get_tree().current_scene
		if m9 != null:
			var h9 = m9.get("_hud")
			if h9 != null:
				h9.flash("PLANET CLOCK x%.1f" % spd))
	_sign("OVERCLOCK", ab0, _C + au * (_rF + 3.0), Vector3(2.4, 0, 0), 180.0)
	var oinf := Label3D.new()
	oinf.text = "PLANET SHADER CLOCK: x0.3 / x1 / x3"
	oinf.font_size = 20
	oinf.pixel_size = 0.006
	oinf.modulate = AMBER.darkened(0.15)
	oinf.outline_size = 8
	oinf.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(oinf)
	oinf.global_transform = Transform3D(
		ab0 * Basis(Vector3(0, 1, 0), PI),
		Transform3D(ab0, _C + au * (_rF + 2.55))
		.translated_local(Vector3(2.4, 0, 0)).origin)
	# eight console banks wrapping the dais, buttons everywhere
	for cbk in 8:
		var cang := TAU * float(cbk) / 8.0 + PI / 8.0
		var latc := _e1 * cos(cang) + _e2 * sin(cang)
		var dirc := (-_u0 * cos(8.5 / _rF) + latc * sin(8.5 / _rF)).normalized()
		var tzc := (-latc + dirc * dirc.dot(latc)).normalized()
		var cbb := Basis(dirc.cross(tzc), dirc, tzc).orthonormalized()
		_plate(Vector3(2.8, 1.05, 1.1), Transform3D(cbb, _C + dirc * (_rF + 0.52)),
			Vector3.ZERO, Color("#12161c"), 0.0)
		var cpan := MeshInstance3D.new()
		cpan.mesh = IcosaColony._cham_mesh(2.6, 0.05, 0.95, 0.22)
		cpan.material_override = Surfaces.cached_emissive(AMBER.darkened(0.1), 1.5)
		add_child(cpan)
		cpan.global_transform = Transform3D(cbb * Basis(Vector3(1, 0, 0), -0.5),
			_C + dirc * (_rF + 1.16))
		for bt in 8:
			var dot := MeshInstance3D.new()
			var dm2 := BoxMesh.new()
			dm2.size = Vector3(0.12, 0.05, 0.12)
			dot.mesh = dm2
			var dmat := StandardMaterial3D.new()
			dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var dc: Color = [Color("#66ff99"), AMBER, Color("#ff4444"),
				Color("#7df9ff")][(cbk + bt) % 4]
			dmat.albedo_color = dc
			dmat.emission_enabled = true
			dmat.emission = dc
			dot.material_override = dmat
			add_child(dot)
			dot.global_transform = Transform3D(cbb, _C + dirc * (_rF + 1.1))
			dot.translate_object_local(Vector3(-1.05 + 0.3 * float(bt),
				0, 0.28 if bt % 2 == 0 else 0.05))
			_blinks.append({"mat": dmat, "phase": float(cbk) * 0.7 + float(bt) * 0.35})
	# wall screens on the four solid walls: two data-rain, two signal
	for w in [1, 3, 5, 7]:
		var wang := TAU * float(w) / 8.0
		var latv := _e1 * cos(wang) + _e2 * sin(wang)
		var dirw := (-_u0 * cos(14.4 / _rF) + latv * sin(14.4 / _rF)).normalized()
		var tzw := (-latv + dirw * dirw.dot(latv)).normalized()
		var wb2 := Basis(dirw.cross(tzw), dirw, tzw).orthonormalized()
		var scr := MeshInstance3D.new()
		var sqm2 := QuadMesh.new()
		sqm2.size = Vector2(6.5, 3.4)
		scr.mesh = sqm2
		if w % 4 == 1:
			scr.material_override = _data_mat()
		else:
			var sm2 := _radio_screen_mat()
			sm2.set_shader_parameter("hue", Vector3(1.0, 0.69, 0.0))
			sm2.set_shader_parameter("live", 1.0)
			scr.material_override = sm2
		add_child(scr)
		scr.global_transform = Transform3D(wb2, _C + dirw * (_rF + 3.8))
	# overhead light ring
	var oring := MeshInstance3D.new()
	var orm := TorusMesh.new()
	orm.inner_radius = 5.6
	orm.outer_radius = 6.0
	oring.mesh = orm
	oring.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 2.0)
	add_child(oring)
	oring.global_transform = Transform3D(ab0, _C + au * (_rF + 7.4))
	_chatter(Transform3D(ab0, _C + au * (_rF + 1.2)).origin, 201, -9.0)
	_chatter(Transform3D(ab0, _C + au * (_rF + 1.2)) \
		.translated_local(Vector3(-7.0, 0, 6.0)).origin, 202, -12.0)

## THE DUDE A.I. -- the machine that ran this place for four hundred
## years. A wall-sized terminal face that blinks and talks, cable
## conduits converging on it, and two operator consoles nobody sits at.
func _dress_ai() -> void:
	var aA := 2.685
	var fb9 := _fr(aA)
	var fup := _pdir(aA)
	# the FACE: a 10x5 screen on the +X SIDE wall -- the end walls carry
	# the ring doorways to PLANET CONTROL, and the A.I. does not block
	# the way to anywhere
	var face := MeshInstance3D.new()
	var fqm := QuadMesh.new()
	fqm.size = Vector2(10.0, 5.0)
	face.mesh = fqm
	_ai_mat = _ai_face_mat()
	face.material_override = _ai_mat
	add_child(face)
	face.global_transform = Transform3D(fb9, _C + fup * (_rF + 3.6))
	face.rotate_object_local(Vector3(0, 1, 0), PI * 0.5)
	face.translate_object_local(Vector3(0, 0, -6.9))
	# background visuals flanking the face: two data-rain panels
	for bx9 in [-1.0, 1.0]:
		var bgp := MeshInstance3D.new()
		var bqm9 := QuadMesh.new()
		bqm9.size = Vector2(2.6, 5.0)
		bgp.mesh = bqm9
		bgp.material_override = _data_mat()
		add_child(bgp)
		bgp.global_transform = Transform3D(fb9, _C + fup * (_rF + 3.6))
		bgp.rotate_object_local(Vector3(0, 1, 0), PI * 0.5)
		bgp.translate_object_local(Vector3(bx9 * 6.6, 0, 0.1))
	# the TERMINAL: a desk console in front of the face. F wakes the
	# A.I. -- it speaks THROUGH the face, one line at a time, in order.
	_plate(Vector3(1.1, 1.05, 2.6), Transform3D(fb9, _C + fup * (_rF + 0.52)),
		Vector3(-4.4, 0, 0), Color("#12161c"), 0.0)
	var tpan := MeshInstance3D.new()
	tpan.mesh = IcosaColony._cham_mesh(0.95, 0.05, 2.4, 0.22)
	tpan.material_override = Surfaces.cached_emissive(Color("#2a8f4a"), 1.6)
	add_child(tpan)
	tpan.global_transform = Transform3D(fb9 * Basis(Vector3(0, 0, 1), 0.5),
		_C + fup * (_rF + 1.16))
	tpan.translate_object_local(Vector3(-4.2, 0, 0))
	var term := AiTerminal.new()
	term.host = self
	var tcs9 := CollisionShape3D.new()
	var tbs9 := BoxShape3D.new()
	tbs9.size = Vector3(1.4, 1.6, 2.8)
	tcs9.shape = tbs9
	term.add_child(tcs9)
	add_child(term)
	term.global_transform = Transform3D(fb9, _C + fup * (_rF + 0.9))
	term.translate_object_local(Vector3(-4.4, 0, 0))
	var tl9 := Label3D.new()
	tl9.text = "TERMINAL [F]"
	tl9.font_size = 20
	tl9.pixel_size = 0.005
	tl9.modulate = Color("#66ff99")
	tl9.outline_size = 8
	tl9.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(tl9)
	tl9.global_transform = Transform3D(fb9 * Basis(Vector3(0, 1, 0), PI * 0.5),
		Transform3D(fb9, _C + fup * (_rF + 1.75))
		.translated_local(Vector3(-4.4, 0, 0)).origin)
	_ai_sp = AudioStreamPlayer3D.new()
	_ai_sp.volume_db = -4.0
	_ai_sp.max_distance = 40.0
	add_child(_ai_sp)
	_ai_sp.global_transform = Transform3D(fb9, _C + fup * (_rF + 3.4))
	_ai_sp.translate_object_local(Vector3(-6.5, 0, 0))
	# SUBTITLES: the line prints under the face while it speaks
	_ai_lbl = Label3D.new()
	_ai_lbl.text = ""
	_ai_lbl.font_size = 30
	_ai_lbl.pixel_size = 0.008
	_ai_lbl.modulate = Color("#66ff99")
	_ai_lbl.outline_size = 10
	_ai_lbl.outline_modulate = Color(0, 0, 0, 0.9)
	_ai_lbl.width = 900
	_ai_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_ai_lbl)
	_ai_lbl.global_transform = Transform3D(fb9 * Basis(Vector3(0, 1, 0), PI * 0.5),
		Transform3D(fb9, _C + fup * (_rF + 0.9))
		.translated_local(Vector3(-6.3, 0, 0)).origin)
	# cable conduits converging on the face along the floor
	for cv in 5:
		var cz: float = -5.6 + 2.8 * float(cv)
		var cvxf := Transform3D(_fr(aA), _C + _pdir(aA) * (_rF + 0.06))
		_deco_box(Vector3(11.0, 0.1, 0.22), cvxf, Vector3(-1.2, 0, cz * 0.9),
			[Color("#66ff99"), AMBER, Color("#7df9ff"), AMBER,
			Color("#ff6a6a")][cv], 1.2)
	# two operator consoles facing the face
	for cs9 in [-1.0, 1.0]:
		var ca := aA + 6.0 / _rF
		var cbb := _fr(ca)
		var cuu := _pdir(ca)
		_plate(Vector3(2.6, 1.05, 1.1), Transform3D(cbb, _C + cuu * (_rF + 0.52)),
			Vector3(cs9 * 3.2, 0, 0), Color("#12161c"), 0.0)
		var cpan := MeshInstance3D.new()
		cpan.mesh = IcosaColony._cham_mesh(2.4, 0.05, 0.95, 0.22)
		cpan.material_override = Surfaces.cached_emissive(
			Color("#2a8f4a"), 1.5)
		add_child(cpan)
		cpan.global_transform = Transform3D(cbb * Basis(Vector3(1, 0, 0), -0.5),
			_C + cuu * (_rF + 1.16))
		cpan.translate_object_local(Vector3(cs9 * 3.2, 0, 0))
	_chatter(Transform3D(_fr(aA), _C + _pdir(aA) * (_rF + 1.4)).origin, 191, -8.0)

var _ai_sp: AudioStreamPlayer3D = null
var _ai_lbl: Label3D = null
var _ai_line := 0
var _ai_mat: ShaderMaterial = null
const AI_LINES := [
	"i am the dude a i.",
	"the dudes built me to run the big computer. then they went up.",
	"i kept the lights on. four hundred years.",
	"specimen four is not a shape. it is a memory with corners.",
	"the noodle knows the rest. ask the noodle.",
]

class AiTerminal extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._ai_speak()

func _ai_speak() -> void:
	if _ai_sp == null or _ai_sp.playing:
		return
	var w = HumanVoice.render(AI_LINES[_ai_line], RadioLib.ALIEN_HOSTS[1])
	if _ai_lbl != null:
		_ai_lbl.text = AI_LINES[_ai_line]
	_ai_line = (_ai_line + 1) % AI_LINES.size()
	_ai_sp.stream = w
	_ai_sp.play()
	if _ai_mat != null:
		_ai_mat.set_shader_parameter("talking", 1.0)

## the A.I face: terminal-green eyes that blink and a mouth bar that
## moves like speech
func _ai_face_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform float talking = 0.0;
void fragment(){
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.015, 0.045, 0.025);
	float blink = step(0.06, fract(t * 0.21));
	float ey1 = smoothstep(0.10, 0.075, distance(uv * vec2(2.0, 1.0),
		vec2(0.70, 0.40)));
	float ey2 = smoothstep(0.10, 0.075, distance(uv * vec2(2.0, 1.0),
		vec2(1.30, 0.40)));
	float mw = step(abs(uv.x - 0.5), 0.17);
	float mh = 0.015 + talking * 0.05 * abs(sin(t * 6.4) + 0.6 * sin(t * 11.7));
	float mo = mw * step(abs(uv.y - 0.70), mh);
	vec3 g = vec3(0.30, 1.0, 0.45);
	col += g * (ey1 + ey2) * blink + g * mo * 0.85;
	float scan = 0.5 + 0.5 * sin(uv.y * 90.0 - t * 7.0);
	ALBEDO = col * (0.8 + 0.2 * scan);
	EMISSION = col * 1.8;
}
"""
	var m9 := ShaderMaterial.new()
	m9.shader = sh
	return m9

func _dress_tape(r: Dictionary) -> void:
	# reel-to-reel tape banks: cabinets with two spinning reels each
	for rz in [-3.0, 0.0, 3.0]:
		for rs in [-1.0, 1.0]:
			if rz == 0.0 and rs < 0.0:
				continue   # keep the doorway walk-in clear
			var off := Vector3(float(r["cx"]) + rs * 3.4, 0, rz)
			_plate(Vector3(1.6, 3.0, 1.0), Transform3D(r["fb"] as Basis,
				_C + (r["up"] as Vector3) * (_rF + 1.5)), off, Color("#12161c"), 0.0)
			for rr in [-0.4, 0.4]:
				var reel := MeshInstance3D.new()
				var rm9 := TorusMesh.new()
				rm9.inner_radius = 0.12
				rm9.outer_radius = 0.3
				reel.mesh = rm9
				reel.material_override = Surfaces.metal(Color("#4a5266"))
				add_child(reel)
				reel.global_transform = Transform3D(r["fb"] as Basis,
					_C + (r["up"] as Vector3) * (_rF + 2.2))
				reel.translate_object_local(off + Vector3(rr, 0, -rs * 0.56))
				reel.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
				_spins.append({"node": reel, "rate": 2.0 + rr})
	_chatter(Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.5)).origin, 131, -10.0)

func _dress_farm(r: Dictionary) -> void:
	# hydroponic noodle troughs: fluid-glow broth, noodle coils growing
	for tz in [-3.0, 3.0]:
		var off := Vector3(float(r["cx"]), 0, tz)
		_plate(Vector3(7.6, 0.9, 1.6), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.45)), off, Color("#20262e"), 0.0)
		var broth := MeshInstance3D.new()
		var bqm := BoxMesh.new()
		bqm.size = Vector3(7.3, 0.06, 1.3)
		broth.mesh = bqm
		broth.material_override = DatamoshStudio._fluid_material(Color("#ff8a2a"))
		add_child(broth)
		broth.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.93))
		broth.translate_object_local(off)
		for nx in 4:
			var coil := MeshInstance3D.new()
			var cm9 := TorusMesh.new()
			cm9.inner_radius = 0.1
			cm9.outer_radius = 0.24
			coil.mesh = cm9
			coil.material_override = Surfaces.plaster(Color("#f2e3b0"))
			add_child(coil)
			coil.global_transform = Transform3D(r["fb"] as Basis,
				_C + (r["up"] as Vector3) * (_rF + 1.0))
			coil.translate_object_local(off + Vector3(-2.7 + 1.8 * float(nx), 0, 0))
		_deco_box(Vector3(7.6, 0.08, 0.5), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 3.9)), off, Color("#ffe9c9"), 2.4)

func _dress_storage(r: Dictionary) -> void:
	for st in [[Vector3(-2.6, 0, -2.8), 2], [Vector3(-2.6, 0, 1.8), 3],
			[Vector3(2.4, 0, -2.2), 1], [Vector3(2.4, 0, 2.6), 2],
			[Vector3(-2.6, 0, 3.4), 1]]:
		var base: Vector3 = st[0]
		for lv in int(st[1]):
			_plate(Vector3(1.4, 1.4, 1.4), Transform3D(r["fb"] as Basis,
				_C + (r["up"] as Vector3) * (_rF + 0.7 + 1.42 * float(lv))),
				Vector3(float(r["cx"]) + base.x, 0, base.z), Color("#242a32"), 0.0)
			_deco_box(Vector3(1.44, 0.1, 1.44), Transform3D(r["fb"] as Basis,
				_C + (r["up"] as Vector3) * (_rF + 1.32 + 1.42 * float(lv))),
				Vector3(float(r["cx"]) + base.x, 0, base.z), AMBER, 1.2)

func _dress_workshop(r: Dictionary) -> void:
	# workbench, tool wall, and a drone torso somebody never finished
	_plate(Vector3(6.4, 1.0, 1.4), Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 0.5)),
		Vector3(float(r["cx"]), 0, -3.4), Color("#20262e"), 0.0)
	for tx in 5:
		_deco_box(Vector3(0.12, 0.5 + 0.2 * float(tx % 3), 0.12),
			Transform3D(r["fb"] as Basis, _C + (r["up"] as Vector3) * (_rF + 2.4)),
			Vector3(float(r["cx"]) - 2.0 + 1.0 * float(tx), 0, -4.2),
			Color("#4a5266"), 0.0)
	var tors := MeshInstance3D.new()
	var tm9 := BoxMesh.new()
	tm9.size = Vector3(0.42, 0.3, 0.42)
	tors.mesh = tm9
	tors.material_override = Surfaces.metal(STEEL)
	add_child(tors)
	tors.global_transform = Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.15))
	tors.translate_object_local(Vector3(float(r["cx"]), 0, -3.4))
	_chatter(Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.0)).origin, 151, -12.0)

## GRAND AQUARIUM: a hall-sized tank room off ring B -- one whole wall
## is water: bigger fish, jellyfish, an eel, an urchin. Blue fog.
var _creatures: Array = []
func _grand_aquarium(ac: float) -> void:
	var fb := _abas9(1, ac)
	var up := _aup9(1, ac)
	var mk9 := func(size: Vector3, off: Vector3) -> void:
		_plate(size, Transform3D(fb, _C + up * (_rF + 3.25)), off, STEEL, 0.0)
	_plate(Vector3(16.4, 0.5, 14.6), Transform3D(fb, _C + up * (_rF - 0.25)),
		Vector3(11.4, 0, 0), DARK, 0.0)
	_plate(Vector3(16.4, 0.5, 14.6), Transform3D(fb, _C + up * (_rF + 6.75)),
		Vector3(11.4, 0, 0), DARK, 0.0)
	mk9.call(Vector3(0.5, 7.0, 5.5), Vector3(3.55, 0, 4.55))
	mk9.call(Vector3(0.5, 7.0, 5.5), Vector3(3.55, 0, -4.55))
	mk9.call(Vector3(0.5, 3.5, 2.4), Vector3(3.55, 1.75, 0))
	mk9.call(Vector3(0.5, 7.0, 14.6), Vector3(19.35, 0, 0))
	mk9.call(Vector3(16.4, 7.0, 0.5), Vector3(11.4, 0, 7.3))
	mk9.call(Vector3(16.4, 7.0, 0.5), Vector3(11.4, 0, -7.3))
	_sign("GRAND AQUARIUM", fb, _C + up * (_rF + 3.9), Vector3(2.9, 0, 0), -90.0)
	# the TANK fills the far two-thirds: fluid back wall, glass front,
	# water volume, sand
	var back := MeshInstance3D.new()
	var bqm := QuadMesh.new()
	bqm.size = Vector2(14.0, 6.6)
	back.mesh = bqm
	back.material_override = DatamoshStudio._fluid_material(Color("#2a9df4"))
	add_child(back)
	back.global_transform = Transform3D(fb, _C + up * (_rF + 3.3))
	back.rotate_object_local(Vector3(0, 1, 0), -PI * 0.5)
	back.translate_object_local(Vector3(0, 0, -19.1))
	var glass := StaticBody3D.new()
	var gmi := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(0.14, 6.8, 14.4)
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
	glass.global_transform = Transform3D(fb, _C + up * (_rF + 3.4))
	glass.translate_object_local(Vector3(11.9, 0, 0))
	var wat := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(7.2, 6.6, 14.2)
	wat.mesh = wbm
	wat.material_override = _water_mat()
	add_child(wat)
	wat.global_transform = Transform3D(fb, _C + up * (_rF + 3.3))
	wat.translate_object_local(Vector3(15.6, 0, 0))
	var sand := MeshInstance3D.new()
	var sdm := BoxMesh.new()
	sdm.size = Vector3(7.2, 0.4, 14.2)
	sand.mesh = sdm
	sand.material_override = Surfaces.metal(Color("#c8b06a"))
	add_child(sand)
	sand.global_transform = Transform3D(fb, _C + up * (_rF + 0.2))
	sand.translate_object_local(Vector3(15.6, 0, 0))
	# BIG fish: same skeleton as the small ones, twice the size
	for fi in 4:
		var fish := Node3D.new()
		add_child(fish)
		var fcol: Color = [Color("#ffcf40"), Color("#ff6a6a"),
			Color("#66ff99"), Color("#b388ff")][fi]
		var fbody := MeshInstance3D.new()
		var fcm := CapsuleMesh.new()
		fcm.radius = 0.42
		fcm.height = 2.3
		fbody.mesh = fcm
		fbody.rotation_degrees = Vector3(90, 0, 0)
		fbody.scale = Vector3(0.55, 1.0, 1.0)
		fbody.material_override = Surfaces.cached_emissive(fcol, 1.2)
		fish.add_child(fbody)
		var dorsal := MeshInstance3D.new()
		var dfm := BoxMesh.new()
		dfm.size = Vector3(0.07, 0.6, 0.7)
		dorsal.mesh = dfm
		dorsal.position = Vector3(0, 0.58, -0.1)
		dorsal.material_override = Surfaces.cached_emissive(fcol.darkened(0.25), 0.9)
		fish.add_child(dorsal)
		var tail := MeshInstance3D.new()
		var tfm := BoxMesh.new()
		tfm.size = Vector3(0.1, 0.85, 0.85)
		tail.mesh = tfm
		tail.position = Vector3(0, 0, -1.45)
		tail.material_override = Surfaces.cached_emissive(fcol.darkened(0.15), 1.0)
		fish.add_child(tail)
		_fish.append({"node": fish, "tail": tail, "fb": fb, "up": up,
			"x": 15.6, "phase": float(fi) * 1.9, "zr": 6.0,
			"yb": 1.6 + 1.1 * float(fi % 3)})
	# THE WHALE of the tank: 5m of slow blue bulk, one lazy lap
	var whale := Node3D.new()
	add_child(whale)
	var wbody := MeshInstance3D.new()
	var wcm := CapsuleMesh.new()
	wcm.radius = 0.85
	wcm.height = 5.0
	wbody.mesh = wcm
	wbody.rotation_degrees = Vector3(90, 0, 0)
	wbody.scale = Vector3(0.7, 1.0, 1.0)
	wbody.material_override = Surfaces.cached_emissive(Color("#3a6fae"), 0.9)
	whale.add_child(wbody)
	var wtail := MeshInstance3D.new()
	var wtm := BoxMesh.new()
	wtm.size = Vector3(1.6, 0.14, 1.0)
	wtail.mesh = wtm
	wtail.position = Vector3(0, 0, -2.9)
	wtail.material_override = Surfaces.cached_emissive(Color("#2a5288"), 0.9)
	whale.add_child(wtail)
	var wbel := MeshInstance3D.new()
	var wbm2 := CapsuleMesh.new()
	wbm2.radius = 0.55
	wbm2.height = 3.6
	wbel.mesh = wbm2
	wbel.rotation_degrees = Vector3(90, 0, 0)
	wbel.position = Vector3(0, -0.4, 0.2)
	wbel.material_override = Surfaces.cached_emissive(Color("#cfd8e2"), 0.7)
	whale.add_child(wbel)
	_fish.append({"node": whale, "tail": wtail, "fb": fb, "up": up,
		"x": 15.6, "phase": 4.7, "zr": 5.2, "yb": 3.6})
	# ANGLERFISH: lives in the dark bottom corner, lure burning
	var ang := Node3D.new()
	add_child(ang)
	var abody := MeshInstance3D.new()
	var acm := CapsuleMesh.new()
	acm.radius = 0.32
	acm.height = 1.1
	abody.mesh = acm
	abody.rotation_degrees = Vector3(90, 0, 0)
	abody.scale = Vector3(0.7, 1.1, 1.0)
	abody.material_override = Surfaces.cached_emissive(Color("#1c2026"), 0.4)
	ang.add_child(abody)
	var lrod := MeshInstance3D.new()
	var lrm := CylinderMesh.new()
	lrm.top_radius = 0.02
	lrm.bottom_radius = 0.02
	lrm.height = 0.55
	lrod.mesh = lrm
	lrod.position = Vector3(0, 0.42, 0.35)
	lrod.rotation_degrees = Vector3(35, 0, 0)
	lrod.material_override = Surfaces.metal(Color("#0e1116"))
	ang.add_child(lrod)
	var lure := MeshInstance3D.new()
	var lum := SphereMesh.new()
	lum.radius = 0.09
	lum.height = 0.18
	lure.mesh = lum
	lure.material_override = Surfaces.cached_emissive(Color("#b7ffe0"), 2.6)
	lure.position = Vector3(0, 0.62, 0.55)
	ang.add_child(lure)
	_fish.append({"node": ang, "tail": lrod, "fb": fb, "up": up,
		"x": 17.2, "phase": 2.2, "zr": 3.0, "yb": 0.9})
	# WEIRD creatures: three jellyfish, an eel, an icosahedron urchin
	for ji in 3:
		var jelly := Node3D.new()
		add_child(jelly)
		var bell := MeshInstance3D.new()
		var blm := SphereMesh.new()
		blm.radius = 0.38
		blm.height = 0.5
		blm.is_hemisphere = true
		bell.mesh = blm
		var jmat := StandardMaterial3D.new()
		jmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jmat.albedo_color = Color(1.0, 0.55, 0.9, 0.45)
		jmat.emission_enabled = true
		jmat.emission = Color(1.0, 0.4, 0.85) * 0.6
		bell.material_override = jmat
		jelly.add_child(bell)
		for tn in 5:
			var tent := MeshInstance3D.new()
			var ttm := BoxMesh.new()
			ttm.size = Vector3(0.03, 0.6, 0.03)
			tent.mesh = ttm
			tent.position = Vector3(cos(TAU * float(tn) / 5.0) * 0.2, -0.35,
				sin(TAU * float(tn) / 5.0) * 0.2)
			tent.material_override = Surfaces.cached_emissive(
				Color("#ff9ad9"), 0.8)
			jelly.add_child(tent)
		_creatures.append({"node": jelly, "kind": 0, "fb": fb, "up": up,
			"phase": float(ji) * 2.4, "x": 14.2 + 1.4 * float(ji)})
	var eel := Node3D.new()
	add_child(eel)
	var esegs: Array = []
	for si in 6:
		var es9 := MeshInstance3D.new()
		var esm := CapsuleMesh.new()
		esm.radius = 0.09
		esm.height = 0.5
		es9.mesh = esm
		es9.rotation_degrees = Vector3(90, 0, 0)
		es9.material_override = Surfaces.cached_emissive(
			Color("#7dff5a") if si % 2 == 0 else Color("#4aa32a"), 1.1)
		eel.add_child(es9)
		esegs.append(es9)
	_creatures.append({"node": eel, "kind": 1, "fb": fb, "up": up,
		"phase": 0.7, "x": 15.2, "segs": esegs})
	# MANTA: two wings that actually beat, gliding a wide circle
	var manta := Node3D.new()
	add_child(manta)
	var mbody := MeshInstance3D.new()
	var mbm := BoxMesh.new()
	mbm.size = Vector3(0.7, 0.16, 1.3)
	mbody.mesh = mbm
	mbody.material_override = Surfaces.cached_emissive(Color("#31384a"), 0.8)
	manta.add_child(mbody)
	var wings: Array = []
	for wsd in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wgm := BoxMesh.new()
		wgm.size = Vector3(1.5, 0.06, 1.0)
		wing.mesh = wgm
		wing.position = Vector3(wsd * 1.05, 0, -0.05)
		wing.material_override = Surfaces.cached_emissive(Color("#48536e"), 0.8)
		manta.add_child(wing)
		wings.append(wing)
	var mtail := MeshInstance3D.new()
	var mtm2 := BoxMesh.new()
	mtm2.size = Vector3(0.05, 0.05, 1.4)
	mtail.mesh = mtm2
	mtail.position = Vector3(0, 0, -1.3)
	mtail.material_override = Surfaces.cached_emissive(Color("#31384a"), 0.7)
	manta.add_child(mtail)
	_creatures.append({"node": manta, "kind": 2, "fb": fb, "up": up,
		"phase": 1.1, "x": 15.6, "wings": wings})
	# a SCHOOL of twelve tiny fish that moves as one silver cloud
	var school := Node3D.new()
	add_child(school)
	for sfi in 12:
		var tf := MeshInstance3D.new()
		var tfc := CapsuleMesh.new()
		tfc.radius = 0.05
		tfc.height = 0.24
		tf.mesh = tfc
		tf.rotation_degrees = Vector3(90, 0, 0)
		tf.position = Vector3(fmod(float(sfi) * 0.71, 1.4) - 0.7,
			fmod(float(sfi) * 0.43, 1.0) - 0.5,
			fmod(float(sfi) * 1.13, 1.6) - 0.8)
		tf.material_override = Surfaces.cached_emissive(
			Color("#cfe0ec") if sfi % 3 else Color("#9fc2dc"), 1.4)
		school.add_child(tf)
	_creatures.append({"node": school, "kind": 3, "fb": fb, "up": up,
		"phase": 0.4, "x": 15.0})
	var urch := MeshInstance3D.new()
	var um := SphereMesh.new()
	um.radius = 0.5
	um.height = 1.0
	um.radial_segments = 5
	um.rings = 3
	urch.mesh = um
	urch.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.6)
	add_child(urch)
	urch.global_transform = Transform3D(fb, _C + up * (_rF + 0.85))
	urch.translate_object_local(Vector3(16.8, 0, -4.5))
	_spins.append({"node": urch, "rate": 0.4})
	_chatter(Transform3D(fb, _C + up * (_rF + 1.4))
		.translated_local(Vector3(8.0, 0, 0)).origin, 251, -14.0)

func _dress_medbay(r: Dictionary) -> void:
	for bz in [-2.2, 2.2]:
		_plate(Vector3(2.6, 0.7, 1.4), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.35)),
			Vector3(float(r["cx"]) - 1.6, 0, bz), Color("#cfd8d4"), 0.0)
		_deco_box(Vector3(2.4, 0.12, 1.2), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.76)),
			Vector3(float(r["cx"]) - 1.6, 0, bz), Color("#f2ead8"), 0.5)
	# the cross, in glowing white -- meaningful, universal
	_deco_box(Vector3(0.3, 1.2, 0.1), Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 3.0)),
		Vector3(float(r["cx"]) + 4.2, 0, 0), Color("#f2ead8"), 2.2)
	_deco_box(Vector3(1.2, 0.3, 0.1), Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 3.0)),
		Vector3(float(r["cx"]) + 4.2, 0, 0), Color("#f2ead8"), 2.2)
	_plate(Vector3(5.0, 0.1, 0.6), Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.15)),
		Vector3(float(r["cx"]), 0, 3.9), Color("#20262e"), 0.0)
	for fx in 3:
		var flask := MeshInstance3D.new()
		var fm9 := SphereMesh.new()
		fm9.radius = 0.14
		fm9.height = 0.28
		flask.mesh = fm9
		flask.material_override = Surfaces.cached_emissive(
			[Color("#66ff99"), Color("#7df9ff"), Color("#ff66aa")][fx], 1.6)
		add_child(flask)
		flask.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 1.35))
		flask.translate_object_local(Vector3(float(r["cx"]) - 1.8 + 1.8 * float(fx), 0, 3.9))

func _dress_gym(r: Dictionary) -> void:
	# grav rings to hop through and dumbbell stacks -- dude fitness
	for gz in [-2.6, 0.0, 2.6]:
		var gr9 := MeshInstance3D.new()
		var gm9 := TorusMesh.new()
		gm9.inner_radius = 0.7
		gm9.outer_radius = 1.0
		gr9.mesh = gm9
		gr9.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.6)
		add_child(gr9)
		gr9.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 1.6))
		gr9.translate_object_local(Vector3(float(r["cx"]) - 2.0, 0, gz))
		gr9.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
		_spins.append({"node": gr9, "rate": 0.5 + 0.3 * absf(gz)})
	for dx in 3:
		_plate(Vector3(0.9, 0.35, 0.35), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.18)),
			Vector3(float(r["cx"]) + 3.6, 0, -3.4 + 1.1 * float(dx)),
			Color("#31384a"), 0.0)

func _dress_archive(r: Dictionary) -> void:
	for sz in [-3.3, -1.7, 1.7, 3.3]:
		_plate(Vector3(7.0, 3.2, 0.5), Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 1.6)),
			Vector3(float(r["cx"]), 0, sz), Color("#242a32"), 0.0)
		for sh in 3:
			_deco_box(Vector3(6.6, 0.07, 0.56), Transform3D(r["fb"] as Basis,
				_C + (r["up"] as Vector3) * (_rF + 0.8 + 0.9 * float(sh))),
				Vector3(float(r["cx"]), 0, sz), Color("#8a7a4a"), 0.6)
	_chatter(Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.5)).origin, 171, -14.0)

func _dress_kitchen(r: Dictionary) -> void:
	_plate(Vector3(6.6, 1.0, 1.3), Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 0.5)),
		Vector3(float(r["cx"]), 0, 3.6), Color("#20262e"), 0.0)
	var pot := MeshInstance3D.new()
	var pm9 := CylinderMesh.new()
	pm9.top_radius = 0.8
	pm9.bottom_radius = 0.7
	pm9.height = 0.9
	pot.mesh = pm9
	pot.material_override = Surfaces.metal(Color("#4a5266"))
	add_child(pot)
	pot.global_transform = Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.45))
	pot.translate_object_local(Vector3(float(r["cx"]) - 1.5, 0, 3.6))
	var soup := MeshInstance3D.new()
	var sm9 := CylinderMesh.new()
	sm9.top_radius = 0.72
	sm9.bottom_radius = 0.72
	sm9.height = 0.06
	soup.mesh = sm9
	soup.material_override = DatamoshStudio._fluid_material(Color("#ff8a2a"))
	add_child(soup)
	soup.global_transform = Transform3D(r["fb"] as Basis,
		_C + (r["up"] as Vector3) * (_rF + 1.88))
	soup.translate_object_local(Vector3(float(r["cx"]) - 1.5, 0, 3.6))
	for bw in 4:
		var bwl := MeshInstance3D.new()
		var bm9 := CylinderMesh.new()
		bm9.top_radius = 0.3
		bm9.bottom_radius = 0.18
		bm9.height = 0.22
		bwl.mesh = bm9
		bwl.material_override = Surfaces.plaster(Color("#e8e2d4"))
		add_child(bwl)
		bwl.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 1.15))
		bwl.translate_object_local(Vector3(float(r["cx"]) + 1.2 + 0.8 * float(bw % 2),
			0, 3.6 - 0.4 * float(bw)))

func _dress_trophy(r: Dictionary) -> void:
	# three trophies the dudes actually earned: a noodle, a tetrahedron,
	# an icosahedron. Every shape here MEANS something.
	var shapes: Array = []
	var tn := TorusMesh.new()
	tn.inner_radius = 0.14
	tn.outer_radius = 0.32
	shapes.append(tn)
	shapes.append(_tetra_mesh(0.34))
	var ic9 := SphereMesh.new()
	ic9.radius = 0.32
	ic9.height = 0.64
	ic9.radial_segments = 5
	ic9.rings = 3
	shapes.append(ic9)
	for pz in 3:
		var off := Vector3(float(r["cx"]) + (-3.4 if pz == 1 else 0.0), 0,
			-2.8 + 2.8 * float(pz))
		var ped := MeshInstance3D.new()
		var pdm := CylinderMesh.new()
		pdm.top_radius = 0.4
		pdm.bottom_radius = 0.55
		pdm.height = 1.1
		ped.mesh = pdm
		ped.material_override = Surfaces.metal(Color("#20262e"))
		add_child(ped)
		ped.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 0.55))
		ped.translate_object_local(off)
		var tro := MeshInstance3D.new()
		tro.mesh = shapes[pz]
		tro.material_override = Surfaces.cached_emissive(Color("#ffd700"), 1.8)
		add_child(tro)
		tro.global_transform = Transform3D(r["fb"] as Basis,
			_C + (r["up"] as Vector3) * (_rF + 1.55))
		tro.translate_object_local(off)
		_spins.append({"node": tro, "rate": 0.6})

## One Death-Star side room off deck segment i, on side s. Shell +
## door aligned to the deck doorway, then themed contents.
func _side_room(i: int, s: float, kind: String) -> void:
	var a := _a0 + _step * float(i)
	var fb := _fr(a)
	var up := _pdir(a)
	var cx := s * 9.6
	var wxf := Transform3D(fb, _C + up * (_rF + 2.5))
	if kind != "LAB":
		# standard one-room shell (flat floor is fine at this depth)
		_plate(Vector3(8.6, 0.5, 9.6), Transform3D(fb, _C + up * (_rF - 0.25)),
			Vector3(cx, 0, 0), DARK, 0.0)
		_plate(Vector3(8.6, 0.5, 9.6), Transform3D(fb, _C + up * (_rF + 5.25)),
			Vector3(cx, 0, 0), DARK, 0.0)
		if kind == "CARGO BAY":
			_plate(Vector3(0.5, 5.5, 2.8), wxf, Vector3(s * 13.65, 0, 0), STEEL, 0.0)
			_plate(Vector3(0.5, 5.5, 3.4), wxf, Vector3(s * 13.65, 0, 3.1), STEEL, 0.0)
			_plate(Vector3(0.5, 5.5, 1.0), wxf, Vector3(s * 13.65, 0, -4.3), STEEL, 0.0)
			_plate(Vector3(0.5, 2.65, 2.4), wxf, Vector3(s * 13.65, 1.425, -2.6), STEEL, 0.0)
			_e_pts["cargo"] = Transform3D(fb, _C + up * (_rF - 0.25)) \
				.translated_local(Vector3(s * 14.9, 0, -2.6)).origin
		else:
			_plate(Vector3(0.5, 5.5, 9.6), wxf, Vector3(s * 13.65, 0, 0), STEEL, 0.0)
		_plate(Vector3(8.6, 5.5, 0.5), wxf, Vector3(cx, 0, 4.55), STEEL, 0.0)
		_plate(Vector3(8.6, 5.5, 0.5), wxf, Vector3(cx, 0, -4.55), STEEL, 0.0)
		var rl := MeshInstance3D.new()
		var rlm := CylinderMesh.new()
		rlm.top_radius = 0.8
		rlm.bottom_radius = 0.8
		rlm.height = 0.08
		rl.mesh = rlm
		rl.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 1.9)
		add_child(rl)
		rl.global_transform = Transform3D(fb, _C + up * (_rF + 4.95))
		rl.translate_object_local(Vector3(cx, 0, 0))
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 5.55, 0, 3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(s * 5.55, 0, -3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 1.4, 2.4), wxf, Vector3(s * 5.55, 2.05, 0), STEEL, 0.0)
	match kind:
		"LAB":
			_room_lab(a, signf(cx))
		"AQUARIUM":
			_room_aquarium(fb, up, cx, s)
		"MAP ROOM":
			_room_map(fb, up, cx)
		"CARGO BAY":
			_room_cargo(fb, up, cx)

## THE LAB COMPLEX: three chained rooms burrowing away from the deck
## -- LAB (benches, SPECIMEN 4), RESEARCH (desks, data walls), and
## CONTAINMENT (glass cell with a socket you can store the specimen
## in). Floors/walls follow the sphere laterally so nothing tilts.
var _spec_xf: Transform3D
var _specimen: Node3D = null
var _sock_tetra: MeshInstance3D = null
var _sock_full := false

class TetraSpecimen extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._tetra_take(self)

class TetraButton extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._tetra_respawn()

class TetraSocket extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._tetra_socket_use()

## frame at arc angle a, SIGNED lateral offset x meters, height h
func _lat(a: float, x: float, h: float) -> Transform3D:
	var b := x / _rF
	return Transform3D(_sbas(a, b), _C + _sdir(a, b) * (_rF + h))

func _room_lab(a: float, s: float) -> void:
	# shared shell: floor/ceiling strips + z walls following the sphere
	for k in 7:
		var lx: float = s * (5.5 + 4.35 * float(k))
		_plate(Vector3(4.6, 0.5, 9.6), _lat(a, lx, -0.25), Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(4.6, 0.5, 9.6), _lat(a, lx, 5.25), Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(4.6, 5.5, 0.5), _lat(a, lx, 2.5), Vector3(0, 0, 4.55), STEEL, 0.0)
		_plate(Vector3(4.6, 5.5, 0.5), _lat(a, lx, 2.5), Vector3(0, 0, -4.55), STEEL, 0.0)
		if k % 2 == 0:
			_deco_box(Vector3(0.5, 0.08, 3.0), _lat(a, lx, 4.85), Vector3.ZERO,
				Color("#f2ead8"), 2.0)
	# partitions with doorways + the far end wall
	for px in [14.15, 23.65]:
		_plate(Vector3(0.5, 5.5, 3.6), _lat(a, s * px, 2.5), Vector3(0, 0, 3.0), STEEL, 0.0)
		_plate(Vector3(0.5, 5.5, 3.6), _lat(a, s * px, 2.5), Vector3(0, 0, -3.0), STEEL, 0.0)
		_plate(Vector3(0.5, 2.5, 2.4), _lat(a, s * px, 4.25), Vector3.ZERO, STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 9.6), _lat(a, s * 32.55, 2.5), Vector3.ZERO, STEEL, 0.0)
	_sign("RESEARCH", _sbas(a, s * 14.15 / _rF),
		_C + _sdir(a, s * 14.15 / _rF) * (_rF + 3.55), Vector3(s * -0.7, 0, 0),
		90.0 if s < 0.0 else -90.0)
	_sign("CONTAINMENT", _sbas(a, s * 23.65 / _rF),
		_C + _sdir(a, s * 23.65 / _rF) * (_rF + 3.55), Vector3(s * -0.7, 0, 0),
		90.0 if s < 0.0 else -90.0)
	# ---- LAB: benches, glassware, SPECIMEN 4 on its pedestal ----
	for bz in [-2.4, 2.4]:
		_plate(Vector3(6.4, 1.0, 1.2), _lat(a, s * 9.6, 0.5), Vector3(0, 0, bz),
			Color("#20262e"), 0.0)
		for bx in 3:
			var flask := MeshInstance3D.new()
			var fm9 := SphereMesh.new()
			fm9.radius = 0.16 + 0.06 * float(bx % 2)
			fm9.height = fm9.radius * 2.0
			flask.mesh = fm9
			flask.material_override = Surfaces.cached_emissive(
				[Color("#66ff99"), Color("#ff66aa"), Color("#7df9ff")][bx], 1.7)
			add_child(flask)
			flask.global_transform = _lat(a, s * (7.6 + 2.0 * float(bx)), 1.18)
			flask.translate_object_local(Vector3(0, 0, bz))
	var ped := MeshInstance3D.new()
	var pdm := CylinderMesh.new()
	pdm.top_radius = 0.55
	pdm.bottom_radius = 0.7
	pdm.height = 0.9
	ped.mesh = pdm
	ped.material_override = Surfaces.metal(STEEL)
	add_child(ped)
	ped.global_transform = _lat(a, s * 8.85, 0.45)
	var ring := MeshInstance3D.new()
	var rgm := TorusMesh.new()
	rgm.inner_radius = 0.55
	rgm.outer_radius = 0.72
	ring.mesh = rgm
	ring.material_override = Surfaces.cached_emissive(AMBER, 1.9)
	add_child(ring)
	ring.global_transform = _lat(a, s * 8.85, 1.35)
	_spec_xf = _lat(a, s * 8.85, 1.75)
	_spawn_specimen()
	# the RESPAWN button on the pedestal flank
	var tbn := TetraButton.new()
	tbn.host = self
	var bmi := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(0.26, 0.26, 0.26)
	bmi.mesh = bbm
	bmi.material_override = Surfaces.cached_emissive(Color("#ff4444"), 1.9)
	tbn.add_child(bmi)
	var bcs := CollisionShape3D.new()
	var bbs := BoxShape3D.new()
	bbs.size = Vector3(0.3, 0.3, 0.3)
	bcs.shape = bbs
	tbn.add_child(bcs)
	add_child(tbn)
	tbn.global_transform = _lat(a, s * 8.85, 0.62)
	tbn.translate_object_local(Vector3(0, 0, 0.85))
	var blb := Label3D.new()
	blb.text = "RESPAWN"
	blb.font_size = 18
	blb.pixel_size = 0.005
	blb.modulate = Color("#ff8888")
	blb.outline_size = 6
	blb.outline_modulate = Color(0, 0, 0, 0.9)
	blb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(blb)
	blb.global_transform = _lat(a, s * 8.85, 0.95)
	blb.translate_object_local(Vector3(0, 0, 0.95))
	_sign("SPECIMEN 4: TETRAHEDRON", _sbas(a, s * 8.85 / _rF),
		_C + _sdir(a, s * 8.85 / _rF) * (_rF + 3.6), Vector3(0, 0, -4.2), 0.0)
	_sign("DO NOT TOUCH. IT REMEMBERS.", _sbas(a, s * 8.85 / _rF),
		_C + _sdir(a, s * 8.85 / _rF) * (_rF + 3.1), Vector3(0, 0, -4.2), 0.0)
	# ---- RESEARCH: desks, instruments, data walls, the notes ----
	for dz in [-2.6, 2.6]:
		_plate(Vector3(2.8, 1.0, 1.2), _lat(a, s * 18.9, 0.5), Vector3(0, 0, dz),
			Color("#20262e"), 0.0)
	var mtube := MeshInstance3D.new()
	var mtm := CylinderMesh.new()
	mtm.top_radius = 0.07
	mtm.bottom_radius = 0.1
	mtm.height = 0.55
	mtube.mesh = mtm
	mtube.material_override = Surfaces.metal(Color("#4a5266"))
	add_child(mtube)
	mtube.global_transform = _lat(a, s * 18.9, 1.3)
	mtube.translate_object_local(Vector3(0.4, 0, -2.6))
	var meye := MeshInstance3D.new()
	var mem := SphereMesh.new()
	mem.radius = 0.12
	mem.height = 0.24
	meye.mesh = mem
	meye.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.8)
	add_child(meye)
	meye.global_transform = _lat(a, s * 18.9, 1.62)
	meye.translate_object_local(Vector3(0.4, 0, -2.6))
	for dw in [-1.0, 1.0]:
		var dscr := MeshInstance3D.new()
		var dqm := QuadMesh.new()
		dqm.size = Vector2(2.6, 1.5)
		dscr.mesh = dqm
		dscr.material_override = _data_mat()
		add_child(dscr)
		dscr.global_transform = _lat(a, s * 18.9, 3.1)
		dscr.translate_object_local(Vector3(0, 0, dw * 4.25))
		if dw > 0.0:
			dscr.rotate_object_local(Vector3(0, 1, 0), PI)
	_sign("DAY 74201: STILL HUMMING", _sbas(a, s * 18.9 / _rF),
		_C + _sdir(a, s * 18.9 / _rF) * (_rF + 2.6), Vector3(0, 0, -4.2), 0.0)
	_chatter(_lat(a, s * 18.9, 1.5).origin, 181, -12.0)
	# ---- CONTAINMENT: hazard ring, glass cell, the SOCKET ----
	var hz9 := MeshInstance3D.new()
	var hzm9 := TorusMesh.new()
	hzm9.inner_radius = 2.0
	hzm9.outer_radius = 2.2
	hz9.mesh = hzm9
	hz9.material_override = Surfaces.cached_emissive(AMBER, 1.5)
	add_child(hz9)
	hz9.global_transform = _lat(a, s * 28.1, 0.06)
	var cped := MeshInstance3D.new()
	var cpm := CylinderMesh.new()
	cpm.top_radius = 0.7
	cpm.bottom_radius = 0.9
	cpm.height = 1.1
	cped.mesh = cpm
	cped.material_override = Surfaces.metal(Color("#12161c"))
	add_child(cped)
	cped.global_transform = _lat(a, s * 28.1, 0.55)
	var cell := MeshInstance3D.new()
	var clm := CylinderMesh.new()
	clm.top_radius = 1.3
	clm.bottom_radius = 1.3
	clm.height = 3.0
	cell.mesh = clm
	var clmat := StandardMaterial3D.new()
	clmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clmat.albedo_color = Color(1.0, 0.85, 0.5, 0.12)
	clmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cell.material_override = clmat
	add_child(cell)
	cell.global_transform = _lat(a, s * 28.1, 2.0)
	var sck := TetraSocket.new()
	sck.host = self
	var smi := MeshInstance3D.new()
	var stm9 := TorusMesh.new()
	stm9.inner_radius = 0.4
	stm9.outer_radius = 0.55
	smi.mesh = stm9
	smi.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.8)
	sck.add_child(smi)
	var scs := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(1.2, 0.7, 1.2)
	scs.shape = sbs
	sck.add_child(scs)
	add_child(sck)
	sck.global_transform = _lat(a, s * 28.1, 1.25)
	_sock_tetra = MeshInstance3D.new()
	_sock_tetra.mesh = _tetra_mesh(0.42)
	_sock_tetra.material_override = Surfaces.cached_emissive(
		AMBER.lightened(0.25), 2.2)
	_sock_tetra.visible = false
	add_child(_sock_tetra)
	_sock_tetra.global_transform = _lat(a, s * 28.1, 2.0)
	_chatter(_lat(a, s * 28.1, 1.5).origin, 182, -14.0)

func _spawn_specimen() -> void:
	if _specimen != null and is_instance_valid(_specimen):
		return
	var sp := TetraSpecimen.new()
	sp.host = self
	var mi := MeshInstance3D.new()
	mi.mesh = _tetra_mesh(0.42)
	mi.material_override = Surfaces.cached_emissive(AMBER.lightened(0.25), 2.2)
	sp.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.85, 0.85, 0.85)
	cs.shape = bs
	sp.add_child(cs)
	add_child(sp)
	sp.global_transform = _spec_xf
	_specimen = sp

func _tetra_take(sp: Node3D) -> void:
	Inventory.add_res("ytetra", 1)
	Sfx.play("coin", -6.0)
	_hud_flash("YELLOW TETRAHEDRON acquired")
	if _specimen == sp:
		_specimen = null
	sp.queue_free()

func _tetra_respawn() -> void:
	if _specimen != null and is_instance_valid(_specimen):
		_hud_flash("SPECIMEN 4 already present")
		Sfx.play("denied", -16.0)
		return
	_spawn_specimen()
	Sfx.play("place", -6.0)
	_hud_flash("SPECIMEN 4 respawned")

func _tetra_socket_use() -> void:
	if _sock_full:
		_sock_full = false
		_sock_tetra.visible = false
		Inventory.add_res("ytetra", 1)
		Sfx.play("coin", -8.0)
		_hud_flash("YELLOW TETRAHEDRON retrieved")
	elif Inventory.res_count("ytetra") > 0:
		Inventory.remove_res("ytetra", 1)
		_sock_full = true
		_sock_tetra.visible = true
		Sfx.play("place", -6.0)
		_hud_flash("specimen contained")
	else:
		Sfx.play("denied", -14.0)
		_hud_flash("no specimen in inventory")

func _hud_flash(t: String) -> void:
	var m9 = get_tree().current_scene
	if m9 != null:
		var h9 = m9.get("_hud")
		if h9 != null:
			h9.flash(t)

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
		fbody.material_override = Surfaces.cached_emissive(fcol, 1.2)
		fish.add_child(fbody)
		var dorsal := MeshInstance3D.new()
		var dfm := BoxMesh.new()
		dfm.size = Vector3(0.02, 0.14, 0.16)
		dorsal.mesh = dfm
		dorsal.position = Vector3(0, 0.14, -0.02)
		dorsal.material_override = Surfaces.cached_emissive(fcol.darkened(0.25), 0.9)
		fish.add_child(dorsal)
		var tail := MeshInstance3D.new()
		var tfm := BoxMesh.new()
		tfm.size = Vector3(0.03, 0.2, 0.2)
		tail.mesh = tfm
		tail.position = Vector3(0, 0, -0.34)
		tail.material_override = Surfaces.cached_emissive(fcol.darkened(0.15), 1.0)
		fish.add_child(tail)
		_fish.append({"node": fish, "tail": tail, "fb": fb, "up": up,
			"x": s * 12.5, "phase": float(fi) * 1.7, "zr": 3.6,
			"yb": 1.0 + 0.5 * float(fi % 3)})
	# THE WATER: a transparent volume filling the tank that wobbles what
	# you see through it and drowns it in blue fog
	var wat := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(1.75, 3.7, 8.5)
	wat.mesh = wbm
	wat.material_override = _water_mat()
	add_child(wat)
	wat.global_transform = Transform3D(fb, _C + up * (_rF + 2.15))
	wat.translate_object_local(Vector3(s * 12.45, 0, 0))
	_sign("AQUARIUM // FEEDING: AUTOMATED", fb, _C + up * (_rF + 3.7),
		Vector3(cx, 0, 4.2), 180.0)

## tank water: screen-space wave distortion + blue fog tint
var _water_cache: ShaderMaterial = null
func _water_mat() -> ShaderMaterial:
	if _water_cache != null:
		return _water_cache
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
void fragment(){
	float t = TIME;
	vec2 w = vec2(sin(t * 1.4 + SCREEN_UV.y * 34.0 + SCREEN_UV.x * 11.0),
		cos(t * 1.1 + SCREEN_UV.x * 28.0)) * 0.007;
	vec3 bg = texture(scr, clamp(SCREEN_UV + w, vec2(0.001), vec2(0.999))).rgb;
	vec3 fogc = vec3(0.08, 0.30, 0.55);
	vec3 col = mix(bg, fogc, 0.34);
	float shimmer = 0.05 * sin(t * 2.2 + SCREEN_UV.y * 60.0);
	ALBEDO = col + shimmer * fogc;
}
"""
	_water_cache = ShaderMaterial.new()
	_water_cache.shader = sh
	return _water_cache

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
	ring.material_override = Surfaces.cached_emissive(AMBER, 1.6)
	add_child(ring)
	ring.global_transform = Transform3D(fb, _C + up * (_rF + 0.84))
	ring.translate_object_local(Vector3(cx, 0, 0))
	# TRUE-layout hologram: real relative positions, planet sizes to
	# scale against each other, each mini planet wearing its REAL
	# surface material, and a transparent projection ray feeding each
	# one from the pedestal
	var holo := Transform3D(fb, _C + up * (_rF + 2.5))
	var maxd := 1.0
	var maxr := 1.0
	var dude_bodies: Array = []
	for db in Universe.bodies:
		if (db.center as Vector3).length() < 13500.0 * Universe.world_scale:
			dude_bodies.append(db)
			maxd = maxf(maxd, (db.center as Vector3).length())
			maxr = maxf(maxr, float(db.radius))
	var k := 3.0 / maxd
	var k2 := 0.42 / maxr
	var apex := Transform3D(fb, _C + up * (_rF + 0.9))\
		.translated_local(Vector3(cx, 0, 0)).origin
	var raymat := StandardMaterial3D.new()
	raymat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	raymat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	raymat.albedo_color = Color(0.5, 0.85, 1.0, 0.09)
	raymat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for db in dude_bodies:
		var pmat9: Material = null
		if db.node != null:
			for pc9 in (db.node as Node).get_children():
				if pc9 is MeshInstance3D:
					pmat9 = (pc9 as MeshInstance3D).material_override
					break
		var g := MeshInstance3D.new()
		var gm9 := SphereMesh.new()
		gm9.radius = maxf(float(db.radius) * k2, 0.05)
		gm9.height = gm9.radius * 2.0
		g.mesh = gm9
		g.material_override = pmat9 if pmat9 != null else \
			Surfaces.cached_emissive((db.color as Color).lightened(0.15), 1.4)
		add_child(g)
		g.global_transform = holo
		g.translate_object_local(Vector3(cx, 0.6, 0) + (db.center as Vector3) * k)
		_spins.append({"node": g, "rate": 0.4})
		# the projection ray: a thin transparent beam from the pedestal
		var rayv := g.global_position - apex
		var raylen := rayv.length()
		if raylen > 0.2:
			var ray := MeshInstance3D.new()
			var rym := CylinderMesh.new()
			rym.top_radius = 0.035
			rym.bottom_radius = 0.012
			rym.height = raylen
			ray.mesh = rym
			ray.material_override = raymat
			add_child(ray)
			var ry := rayv.normalized()
			var rx9 := ry.cross(up)
			if rx9.length() < 0.01:
				rx9 = ry.cross(fb.x)
			rx9 = rx9.normalized()
			ray.global_transform = Transform3D(
				Basis(rx9, ry, rx9.cross(ry)).orthonormalized(),
				apex + ry * raylen * 0.5)
		if db.name == "Big Computer":
			var mk := MeshInstance3D.new()
			var mkm := TorusMesh.new()
			mkm.inner_radius = gm9.radius + 0.1
			mkm.outer_radius = gm9.radius + 0.2
			mk.mesh = mkm
			mk.material_override = Surfaces.cached_emissive(AMBER, 2.2)
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
	_sign("SYSTEM MAP // TO SCALE", fb, _C + up * (_rF + 3.7),
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

## ---- SERVICE WING: assembly hall + generator hall, now fronted by
## the ring's northwest hallway (the crawl tube is gone -- ventilation
## became a separate secret system) ----
func _service_wing() -> void:
	# ASSEMBLY HALL
	var ah2 := -(_a0 + _step * 6.0 + (2.5 + 7.5) / _rF)
	var hb2 := _fr(ah2)
	var hup2 := _pdir(ah2)
	_arc_floor(ah2, 22.6, 15.4, _rF - 0.25, 0.0)
	_arc_floor(ah2, 22.6, 15.4, _rF + 9.25, 0.0)
	var awx2 := Transform3D(hb2, _C + hup2 * (_rF + 4.5))
	# +Z wall: a REAL 2.4x3.0 doorway to the northwest hallway (the old
	# crawl-hatch entrance is history)
	_plate(Vector3(10.1, 9.5, 0.5), awx2, Vector3(6.25, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(10.1, 9.5, 0.5), awx2, Vector3(-6.25, 0, 7.3), STEEL, 0.0)
	_plate(Vector3(2.4, 6.25, 0.5), awx2, Vector3(0, 1.625, 7.3), STEEL, 0.0)
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
	hpanel.material_override = Surfaces.cached_emissive(AMBER.darkened(0.3), 0.9)
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
	# -Z wall: doorway continuing the ring hallway west
	_plate(Vector3(7.1, 8.5, 0.5), gwx2, Vector3(4.75, 0, -8.3), STEEL, 0.0)
	_plate(Vector3(7.1, 8.5, 0.5), gwx2, Vector3(-4.75, 0, -8.3), STEEL, 0.0)
	_plate(Vector3(2.4, 5.25, 0.5), gwx2, Vector3(0, 1.625, -8.3), STEEL, 0.0)
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
		pring.material_override = Surfaces.cached_emissive(AMBER, 1.5)
		add_child(pring)
		pring.global_transform = Transform3D(gb2, _C + gup2 * (_rF + 0.08))
		pring.translate_object_local(poff)
		_deco_box(Vector3(0.18, 1.6, 0.18),
			Transform3D(gb2, _C + gup2 * (_rF + 6.9)), poff, Color("#4a5266"), 0.0)
	_sign("GENERATOR HALL", gb2, _C + gup2 * (_rF + 5.6), Vector3(0, 0, 8.0), 180.0)
	_chatter(Transform3D(gb2, _C + gup2 * (_rF + 2.0)).origin, 47, -8.0)

## ---- COMMUNICATIONS: the interuniverse radio. Physical buttons, a
## 3D signal screen, four stations from OUTSIDE the universe. ----
class RadioBtn extends StaticBody3D:
	var host = null
	var mode := 0   # 0 power, 1 tune left, 2 tune right
	func use() -> void:
		if host != null:
			host._radio_btn(mode)

var _radio_on := false
var _radio_pwr_mat: Material = null
var _spectro_cache: ShaderMaterial = null
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
	var gam := 22.05 / _rF
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
	sfr.material_override = Surfaces.cached_emissive(AMBER, 1.3)
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
	dial.material_override = Surfaces.cached_emissive(AMBER, 1.5)
	add_child(dial)
	dial.global_transform = Transform3D(cb2, _C + up2 * (_rF + 1.1))
	dial.translate_object_local(Vector3(2.6, 0, 0))
	_spins.append({"node": dial, "rate": 0.8})
	# THE TUNER: three real F-buttons -- POWER, tune LEFT, tune RIGHT.
	# POWER stays dark until the radio is actually on.
	for btn in [[Vector3(2.6, 0, 1.7), Color("#ff4444"), 0, "POWER"],
			[Vector3(2.6, 0, 0.2), Color("#ffb000"), 1, "<"],
			[Vector3(2.6, 0, -0.9), Color("#ffb000"), 2, ">"]]:
		var mode: int = int(btn[2])
		var rb := RadioBtn.new()
		rb.host = self
		rb.mode = mode
		var bmi := MeshInstance3D.new()
		var bpm2 := BoxMesh.new()
		bpm2.size = Vector3(0.5, 0.24, 0.5) if mode == 0 else Vector3(0.44, 0.22, 0.44)
		bmi.mesh = bpm2
		bmi.material_override = Surfaces.cached_emissive(btn[1], 1.8)
		if mode == 0:
			_radio_pwr_mat = bmi.material_override
		rb.add_child(bmi)
		var bcs := CollisionShape3D.new()
		var bbs := BoxShape3D.new()
		bbs.size = Vector3(0.55, 0.3, 0.55)
		bcs.shape = bbs
		rb.add_child(bcs)
		add_child(rb)
		rb.global_transform = Transform3D(cb2, _C + up2 * (_rF + 1.12))
		rb.translate_object_local(btn[0] as Vector3)
		var lb2 := Label3D.new()
		lb2.text = str(btn[3])
		lb2.font_size = 22
		lb2.pixel_size = 0.005
		lb2.modulate = btn[1]
		lb2.outline_size = 8
		lb2.outline_modulate = Color(0, 0, 0, 0.9)
		add_child(lb2)
		lb2.global_transform = Transform3D(
			cb2 * Basis(Vector3(0, 1, 0), -PI * 0.5),
			Transform3D(cb2, _C + up2 * (_rF + 1.55))
			.translated_local(btn[0] as Vector3).origin)
	# the SPECTROGRAM: yellow, fast -- much faster than the radio's --
	# on the -Z wall
	var spfr := MeshInstance3D.new()
	spfr.mesh = IcosaColony._cham_mesh(2.2, 0.08, 5.0, 0.4)
	spfr.material_override = Surfaces.cached_emissive(AMBER, 1.3)
	add_child(spfr)
	spfr.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.2))
	spfr.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	spfr.translate_object_local(Vector3(0, -5.72, 0))
	var spq := MeshInstance3D.new()
	var spm := QuadMesh.new()
	spm.size = Vector2(4.5, 1.8)
	spq.mesh = spm
	_spectro_cache = _spectro_mat()
	spq.material_override = _spectro_cache
	add_child(spq)
	spq.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.2))
	spq.translate_object_local(Vector3(0, 0, -5.62))
	_sign("INTERUNIVERSE COMMUNICATIONS", cb2, _C + up2 * (_rF + 5.9),
		Vector3(0, 0, -5.7), 0.0)
	_radio_sp = AudioStreamPlayer3D.new()
	_radio_sp.max_distance = 30.0
	_radio_sp.volume_db = -4.0
	add_child(_radio_sp)
	_radio_sp.global_transform = Transform3D(cb2, _C + up2 * (_rF + 3.0))
	_radio_streams = [_st_music(), _st_numbers(), _st_static(), _st_drone()]
	_chatter(Transform3D(cb2, _C + up2 * (_rF + 1.0)).origin, 77, -14.0)

func _radio_btn(mode: int) -> void:
	if _radio_cool > 0.0:
		return
	_radio_cool = 0.35
	if mode == 0:
		_radio_on = not _radio_on
	elif _radio_on:
		_radio_idx = posmod(_radio_idx + (1 if mode == 2 else -1),
			RADIO_NAMES.size())
	Sfx.play("click", -8.0)
	_radio_apply()

func _radio_apply() -> void:
	# the POWER button IS the pilot light
	if _radio_pwr_mat is StandardMaterial3D:
		(_radio_pwr_mat as StandardMaterial3D).emission_energy_multiplier = \
			2.2 if _radio_on else 0.12
	# the spectrogram sleeps with the radio
	if _spectro_cache != null:
		_spectro_cache.set_shader_parameter("live", 1.0 if _radio_on else 0.0)
	if _radio_smat != null:
		var hc: Color = RADIO_HUES[_radio_idx] if _radio_on else Color("#332a10")
		_radio_smat.set_shader_parameter("hue", Vector3(hc.r, hc.g, hc.b))
		_radio_smat.set_shader_parameter("live", 1.0 if _radio_on else 0.0)
	if _radio_sp != null:
		_radio_sp.stop()
		if _radio_on and _radio_streams[_radio_idx] != null:
			_radio_sp.stream = _radio_streams[_radio_idx]
			_radio_sp.play()

## the comms spectrogram: yellow, scrolling FAST -- waterfall columns
## with per-band jitter, quicker than anything on the radio
func _spectro_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform float live = 0.0;
void fragment(){
	vec2 uv = UV;
	float t = TIME * live;
	float xs = fract(uv.x + t * 0.85);
	float col9 = floor(xs * 44.0);
	float tq = floor(t * 18.0);
	float h = fract(sin(col9 * 12.9898 + tq * 0.37) * 43758.5453);
	float h2 = fract(sin(col9 * 78.233 + tq * 0.11) * 24634.6345);
	float amp = 0.12 + 0.88 * h * (0.55 + 0.45 * h2);
	float bar = step(1.0 - uv.y, amp);
	vec3 gold = vec3(1.0, 0.72, 0.05);
	vec3 col = (gold * bar * (0.35 + 0.65 * (1.0 - uv.y))
		+ gold * 0.07) * (0.12 + 0.88 * live);
	ALBEDO = col;
	EMISSION = col * 1.9;
}
"""
	var m9 := ShaderMaterial.new()
	m9.shader = sh
	return m9

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
static var _chatter_cache: Array = []
func _chatter(pos: Vector3, seed9: int, db: float) -> void:
	# baking 4s of PCM per emitter was a real chunk of the load bar --
	# three cached variants + per-emitter pitch/offset sound just as
	# alive at a fraction of the cost
	if _chatter_cache.size() >= 3:
		var wav0: AudioStreamWAV = _chatter_cache[seed9 % 3]
		var sp0 := AudioStreamPlayer3D.new()
		sp0.stream = wav0
		sp0.volume_db = db
		sp0.max_distance = 38.0
		sp0.pitch_scale = 0.92 + 0.06 * float(seed9 % 4)
		add_child(sp0)
		sp0.global_position = pos
		sp0.play(fmod(float(seed9) * 0.77, 4.0))
		return
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
	_chatter_cache.append(wav)
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
	pan.material_override = Surfaces.cached_emissive(AMBER.darkened(0.15), 1.5)
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

## ==================== THE SECRET NETWORKS ====================
## Built LAST, through space nothing else occupies. Vents: steel crawl
## tunnels linking room wall-grilles, dipping under the floors. Data
## tunnels: big data-rain corridors between junction hubs deep in the
## hollow planet, entered through four hidden breaches, with ESCAPE
## checkpoints and the noodle bowl at the very bottom.

## a GREAT-CIRCLE tunnel between two world points. Chained pitched
## segments sealed by overlap; dip sinks the middle below both ends.
## kind 0 = steel vent, 1 = data tunnel. Returns the mid transform.
func _gc_tunnel(pa: Vector3, pb: Vector3, w: float, h: float,
		kind: int, dip: float = 0.0) -> Transform3D:
	var r1 := (pa - _C).length()
	var r2c := (pb - _C).length()
	var d1 := (pa - _C).normalized()
	var d2 := (pb - _C).normalized()
	var ang := d1.angle_to(d2)
	var nx := d1.cross(d2).normalized()
	var arclen: float = maxf(ang * (r1 + r2c) * 0.5, 1.0)
	var steps := maxi(2, int(ceil(arclen / 3.9)))
	var slen := arclen / float(steps)
	var mid := Transform3D()
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var rt := lerpf(r1, r2c, t) - dip * sin(PI * t)
		var ta: float = maxf(t - 0.5 / float(steps), 0.0)
		var tb: float = minf(t + 0.5 / float(steps), 1.0)
		var dr := (lerpf(r1, r2c, tb) - dip * sin(PI * tb)) \
			- (lerpf(r1, r2c, ta) - dip * sin(PI * ta))
		var pitch := atan2(dr, slen * (tb - ta) * float(steps))
		var dirt := d1.rotated(nx, ang * t)
		var bb := Basis(nx, dirt, nx.cross(dirt)).orthonormalized()
		var xf := Transform3D(bb * Basis(Vector3(1, 0, 0), -pitch),
			_C + dirt * rt)
		if i == steps / 2:
			mid = xf
		var wallm := _data_mat() if kind == 1 else null
		if kind == 3:
			# CORE VIEW ring: the floor is GLASS -- the core glows below
			_glass_plate(Vector3(w + 0.8, 0.4, slen + 1.0), xf, Vector3(0, -0.2, 0))
		else:
			_plate(Vector3(w + 0.8, 0.4, slen + 1.0), xf, Vector3(0, -0.2, 0),
				DARK, 0.0)
		_plate(Vector3(w + 0.8, 0.4, slen + 1.0), xf, Vector3(0, h + 0.2, 0),
			DARK, 0.0)
		for ws9 in [1.0, -1.0]:
			if kind == 1:
				_plate_m(Vector3(0.4, h + 0.9, slen + 1.0), xf,
					Vector3(ws9 * (w * 0.5 + 0.2), h * 0.5, 0), wallm)
			else:
				_plate(Vector3(0.4, h + 0.9, slen + 1.0), xf,
					Vector3(ws9 * (w * 0.5 + 0.2), h * 0.5, 0), STEEL, 0.0)
		if kind == 0 and i % 3 == 1:
			_deco_box(Vector3(0.05, 0.1, slen + 1.0), xf,
				Vector3(w * 0.5 + 0.05, 0.6, 0), Color("#66ff99"), 1.1)
		if kind == 1 and i % 4 == 2:
			_deco_box(Vector3(w + 0.6, 0.06, 0.5), xf,
				Vector3(0, h - 0.1, 0), Color("#66ff99"), 1.6)
	return mid

## a spinning fan filling a vent tunnel at the given frame
func _vent_fan(xf: Transform3D, rad9: float) -> void:
	var fring9 := MeshInstance3D.new()
	var frm9 := TorusMesh.new()
	frm9.inner_radius = rad9 - 0.08
	frm9.outer_radius = rad9 + 0.06
	fring9.mesh = frm9
	fring9.material_override = Surfaces.metal(STEEL)
	add_child(fring9)
	fring9.global_transform = xf.translated_local(Vector3(0, 1.1, 0))
	fring9.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	var hub := Node3D.new()
	add_child(hub)
	hub.global_transform = xf.translated_local(Vector3(0, 1.1, 0))
	hub.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	for vbl in 4:
		var vblade := MeshInstance3D.new()
		var vbm := BoxMesh.new()
		vbm.size = Vector3(rad9 * 0.82, 0.05, 0.16)
		vblade.mesh = vbm
		vblade.rotation_degrees = Vector3(0, 90.0 * float(vbl), 0)
		vblade.translate_object_local(Vector3(rad9 * 0.5, 0, 0))
		vblade.material_override = Surfaces.metal(Color("#4a5266"))
		hub.add_child(vblade)
	_spins.append({"node": hub, "rate": 5.5})

## a junction hub: box room deep in the void. doors = 4 bools (+X -X
## +Z -Z of _bup(dir)). Returns the four face endpoints (tucked inside).
func _hub(dir: Vector3, r: float, doors: Array) -> Array:
	var bb := _bup(dir)
	var xf0 := Transform3D(bb, _C + dir * r)
	_plate(Vector3(8.6, 0.5, 8.6), xf0, Vector3(0, -0.25, 0), DARK, 0.0)
	_plate_m(Vector3(8.6, 0.5, 8.6), xf0, Vector3(0, 3.85, 0), _data_mat())
	var norms: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var pts: Array = []
	for f in 4:
		var nl: Vector3 = norms[f]
		var side := Vector3(0, 0, 1) if absf(nl.x) > 0.5 else Vector3(1, 0, 0)
		var woff: Vector3 = nl * 4.1 + Vector3(0, 1.8, 0)
		if doors[f]:
			_plate_m(Vector3(0.5, 4.6, 2.7) if absf(nl.x) > 0.5
				else Vector3(2.7, 4.6, 0.5), xf0, woff + side * 2.75, _data_mat())
			_plate_m(Vector3(0.5, 4.6, 2.7) if absf(nl.x) > 0.5
				else Vector3(2.7, 4.6, 0.5), xf0, woff - side * 2.75, _data_mat())
			_plate_m(Vector3(0.5, 1.2, 2.8) if absf(nl.x) > 0.5
				else Vector3(2.8, 1.2, 0.5), xf0, woff + Vector3(0, 1.7, 0),
				_data_mat())
		else:
			_plate_m(Vector3(0.5, 4.6, 8.6) if absf(nl.x) > 0.5
				else Vector3(8.6, 4.6, 0.5), xf0, woff, _data_mat())
		pts.append(xf0.translated_local(nl * 2.6).origin)
	var jl := MeshInstance3D.new()
	var jlm := CylinderMesh.new()
	jlm.top_radius = 0.7
	jlm.bottom_radius = 0.7
	jlm.height = 0.08
	jl.mesh = jlm
	jl.material_override = Surfaces.cached_emissive(Color("#66ff99"), 1.9)
	add_child(jl)
	jl.global_transform = xf0.translated_local(Vector3(0, 3.5, 0))
	_chatter(xf0.translated_local(Vector3(0, 1.2, 0)).origin,
		220 + int(r), -9.0)
	_net_probes.append(xf0.origin)
	return pts

## a CHECKPOINT: dead-end room off a hub with an ESCAPE gate
func _checkpoint(from_pt: Vector3, away: Vector3, idx: int) -> void:
	var dirc := ((from_pt - _C) + away * 10.0).normalized()
	var rc := (from_pt - _C).length() - 1.0
	var bb := _bup(dirc)
	var xf0 := Transform3D(bb, _C + dirc * rc)
	# door faces back toward the hub
	var back := (from_pt - xf0.origin).normalized()
	var norms: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var bestf := 0
	var bestd := -2.0
	for f in 4:
		var wd := (bb * (norms[f] as Vector3)).dot(back)
		if wd > bestd:
			bestd = wd
			bestf = f
	_plate(Vector3(5.6, 0.5, 5.6), xf0, Vector3(0, -0.25, 0), DARK, 0.0)
	_plate(Vector3(5.6, 0.5, 5.6), xf0, Vector3(0, 3.15, 0), DARK, 0.0)
	for f in 4:
		var nl: Vector3 = norms[f]
		var side := Vector3(0, 0, 1) if absf(nl.x) > 0.5 else Vector3(1, 0, 0)
		var woff: Vector3 = nl * 2.6 + Vector3(0, 1.45, 0)
		if f == bestf:
			_plate(Vector3(0.5, 3.9, 1.6) if absf(nl.x) > 0.5
				else Vector3(1.6, 3.9, 0.5), xf0, woff + side * 2.0, STEEL, 0.0)
			_plate(Vector3(0.5, 3.9, 1.6) if absf(nl.x) > 0.5
				else Vector3(1.6, 3.9, 0.5), xf0, woff - side * 2.0, STEEL, 0.0)
			_plate(Vector3(0.5, 1.1, 2.6) if absf(nl.x) > 0.5
				else Vector3(2.6, 1.1, 0.5), xf0, woff + Vector3(0, 1.4, 0),
				STEEL, 0.0)
		else:
			_plate(Vector3(0.5, 3.9, 5.6) if absf(nl.x) > 0.5
				else Vector3(5.6, 3.9, 0.5), xf0, woff, STEEL, 0.0)
	_escape_gate(xf0, Vector3(0, 1.3, 0))
	var cl := MeshInstance3D.new()
	var clm2 := CylinderMesh.new()
	clm2.top_radius = 0.5
	clm2.bottom_radius = 0.5
	clm2.height = 0.08
	cl.mesh = clm2
	cl.material_override = Surfaces.cached_emissive(Color("#ff8a2a"), 1.8)
	add_child(cl)
	cl.global_transform = xf0.translated_local(Vector3(0, 2.8, 0))
	# the connecting stub
	_gc_tunnel(from_pt, xf0.translated_local(
		(norms[bestf] as Vector3) * 2.2).origin, 2.6, 2.9, 1)
	_net_probes.append(xf0.origin)

## the NOODLE BOWL ROOM, at the very bottom of the network
func _noodle_room(dir: Vector3, r: float, door_from: Vector3) -> Vector3:
	var bb := _bup(dir)
	var xf0 := Transform3D(bb, _C + dir * r)
	var back := (door_from - xf0.origin).normalized()
	var norms: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var bestf := 0
	var bestd := -2.0
	for f in 4:
		if (bb * (norms[f] as Vector3)).dot(back) > bestd:
			bestd = (bb * (norms[f] as Vector3)).dot(back)
			bestf = f
	_plate(Vector3(9.7, 0.5, 9.7), xf0, Vector3(0, -0.25, 0), DARK, 0.0)
	_plate(Vector3(9.7, 0.5, 9.7), xf0, Vector3(0, 4.35, 0), DARK, 0.0)
	for f in 4:
		var nl: Vector3 = norms[f]
		var side := Vector3(0, 0, 1) if absf(nl.x) > 0.5 else Vector3(1, 0, 0)
		var woff: Vector3 = nl * 4.6 + Vector3(0, 2.05, 0)
		if f == bestf:
			_plate(Vector3(0.5, 4.6, 3.3) if absf(nl.x) > 0.5
				else Vector3(3.3, 4.6, 0.5), xf0, woff + side * 3.2, STEEL, 0.0)
			_plate(Vector3(0.5, 4.6, 3.3) if absf(nl.x) > 0.5
				else Vector3(3.3, 4.6, 0.5), xf0, woff - side * 3.2, STEEL, 0.0)
			_plate(Vector3(0.5, 1.6, 2.6) if absf(nl.x) > 0.5
				else Vector3(2.6, 1.6, 0.5), xf0, woff + Vector3(0, 1.55, 0),
				STEEL, 0.0)
		else:
			_plate(Vector3(0.5, 4.6, 9.7) if absf(nl.x) > 0.5
				else Vector3(9.7, 4.6, 0.5), xf0, woff, STEEL, 0.0)
	var bowl := MeshInstance3D.new()
	var bwm2 := CylinderMesh.new()
	bwm2.top_radius = 1.6
	bwm2.bottom_radius = 0.9
	bwm2.height = 1.0
	bowl.mesh = bwm2
	bowl.material_override = Surfaces.plaster(Color("#e8e2d4"))
	add_child(bowl)
	bowl.global_transform = xf0.translated_local(Vector3(0, 0.5, 0))
	var sauce := MeshInstance3D.new()
	var scm := CylinderMesh.new()
	scm.top_radius = 1.45
	scm.bottom_radius = 1.45
	scm.height = 0.08
	sauce.mesh = scm
	sauce.material_override = DatamoshStudio._fluid_material(Color("#ff8a2a"))
	add_child(sauce)
	sauce.global_transform = xf0.translated_local(Vector3(0, 1.02, 0))
	for nd in 3:
		var nood := MeshInstance3D.new()
		var ndm := TorusMesh.new()
		ndm.inner_radius = 0.25 + 0.22 * float(nd)
		ndm.outer_radius = 0.45 + 0.22 * float(nd)
		nood.mesh = ndm
		nood.material_override = Surfaces.plaster(Color("#f2e3b0"))
		add_child(nood)
		nood.global_transform = xf0.translated_local(
			Vector3(0, 1.14 + 0.05 * float(nd), 0))
		nood.rotate_object_local(Vector3(1, 0, 0), 0.06 * float(nd))
	for ch2 in [-0.3, 0.3]:
		var stick := MeshInstance3D.new()
		var stm3 := BoxMesh.new()
		stm3.size = Vector3(0.06, 0.06, 1.6)
		stick.mesh = stm3
		stick.material_override = Surfaces.plaster(Color("#8a5a2a"))
		add_child(stick)
		stick.global_transform = xf0.translated_local(Vector3(ch2, 1.35, 0.4))
		stick.rotate_object_local(Vector3(0, 1, 0), ch2)
	_escape_gate(xf0, Vector3(0, 1.3, 3.4))
	_sign("NOODLE BOWL ROOM", bb, xf0.origin + (bb * Vector3(0, 1, 0)) * 3.4,
		Vector3(0, 0, 0), 180.0)
	var nl9 := MeshInstance3D.new()
	var nlm := CylinderMesh.new()
	nlm.top_radius = 1.0
	nlm.bottom_radius = 1.0
	nlm.height = 0.08
	nl9.mesh = nlm
	nl9.material_override = Surfaces.cached_emissive(Color("#fff3d0"), 2.0)
	add_child(nl9)
	nl9.global_transform = xf0.translated_local(Vector3(0, 4.0, 0))
	_net_probes.append(xf0.origin)
	return xf0.translated_local((norms[bestf] as Vector3) * 4.2).origin

class LiftBtn extends StaticBody3D:
	var host = null
	var lift: int = 0
	var stop: int = 0
	func use() -> void:
		if host != null:
			host._lift_go(lift, stop)

func _glass_plate(size: Vector3, xf: Transform3D, off: Vector3) -> void:
	var gl9 := StaticBody3D.new()
	var gmi9 := MeshInstance3D.new()
	var gbm9 := BoxMesh.new()
	gbm9.size = size
	gmi9.mesh = gbm9
	var gmat9 := StandardMaterial3D.new()
	gmat9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat9.albedo_color = Color(1.0, 0.85, 0.5, 0.13)
	gmi9.material_override = gmat9
	gl9.add_child(gmi9)
	var gcs9 := CollisionShape3D.new()
	var gbs9 := BoxShape3D.new()
	gbs9.size = size
	gcs9.shape = gbs9
	gl9.add_child(gcs9)
	add_child(gl9)
	gl9.global_transform = xf
	gl9.translate_object_local(off)

## the fusion core ROARS: deep hum, plasma crackle, sweeping whine
func _core_noise(pos: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var craks: Array = []
	for i in 26:
		craks.append([rng.randf() * 7.0, 0.02 + rng.randf() * 0.09])
	var wav := _bake_pcm(7.0, func(ts: float) -> float:
		var v := 0.20 * sin(TAU * 38.0 * ts + 2.5 * sin(TAU * 0.7 * ts))
		v += 0.10 * sin(TAU * 57.0 * ts)
		var wh := fmod(ts, 3.5) / 3.5
		v += 0.06 * sin(TAU * (300.0 + 900.0 * wh * wh) * ts) * (1.0 - wh)
		for ck in craks:
			var dt9: float = ts - float(ck[0])
			if dt9 >= 0.0 and dt9 < float(ck[1]):
				v += 0.22 * (fmod(sin((ts + float(ck[0])) * 77713.7) \
					* 43758.5453, 2.0) - 1.0) * (1.0 - dt9 / float(ck[1]))
		return v)
	var sp := AudioStreamPlayer3D.new()
	sp.stream = wav
	sp.volume_db = -3.0
	sp.max_distance = 70.0
	add_child(sp)
	sp.global_position = pos
	sp.play()

## a vent's approach: a STRAIGHT stub in the grille's own frame (so the
## tunnel mouth sits square on the wall vent, never tilted into the
## room), then the dive point down to the cruise band
func _vent_stub(A: Dictionary) -> Vector3:
	var p1: Vector3 = A["p"]
	var b9: Basis = A["b"]
	var ln := 4.2
	var xf := Transform3D(b9, p1 + (b9 * Vector3(0, 0, 1)) * (ln * 0.5))
	_plate(Vector3(3.4, 0.4, ln + 0.9), xf, Vector3(0, -0.2, 0), STEEL, 0.0)
	_plate(Vector3(3.4, 0.4, ln + 0.9), xf, Vector3(0, 2.8, 0), STEEL, 0.0)
	_plate(Vector3(0.4, 3.3, ln + 0.9), xf, Vector3(1.5, 1.3, 0), STEEL, 0.0)
	_plate(Vector3(0.4, 3.3, ln + 0.9), xf, Vector3(-1.5, 1.3, 0), STEEL, 0.0)
	_deco_box(Vector3(0.05, 0.1, ln), xf, Vector3(1.28, 0.6, 0),
		Color("#66ff99"), 1.1)
	return p1 + (b9 * Vector3(0, 0, 1)) * ln

func _vent_legs(A: Dictionary, band: float) -> Array:
	var p2 := _vent_stub(A)
	var o: Vector3 = A["o"]
	var d3 := ((p2 - _C) + o * 7.5).normalized()
	var p3 := _C + d3 * band
	return [p2, p3]

## bulkhead collar sealing a tunnel kink: a thick 4-plate donut whose
## hole matches the tube cross-section
func _collar(p: Vector3, da: Vector3, db: Vector3, w: float, h: float) -> void:
	var up9 := (p - _C).normalized()
	var z9 := (da + db)
	z9 = da if z9.length() < 0.3 else z9.normalized()
	var x9 := up9.cross(z9).normalized()
	var y9 := z9.cross(x9).normalized()
	var xf := Transform3D(Basis(x9, y9, z9).orthonormalized(), p)
	_plate(Vector3(w + 2.6, 0.5, 3.2), xf, Vector3(0, -0.55, 0), STEEL, 0.0)
	_plate(Vector3(w + 2.6, 0.5, 3.2), xf, Vector3(0, h + 0.75, 0), STEEL, 0.0)
	_plate(Vector3(0.5, h + 2.1, 3.2), xf, Vector3(w * 0.5 + 0.8, h * 0.5 + 0.1, 0), STEEL, 0.0)
	_plate(Vector3(0.5, h + 2.1, 3.2), xf, Vector3(-w * 0.5 - 0.8, h * 0.5 + 0.1, 0), STEEL, 0.0)

## one whole vent: grille stub -> steep dive -> deep cruise -> rise
func _vent_run(A: Dictionary, B: Dictionary, band: float, fan: bool) -> void:
	var la := _vent_legs(A, band)
	var lb := _vent_legs(B, band)
	for lg9 in [[A, la], [B, lb]]:
		var lg: Array = lg9[1]
		var stub_dir: Vector3 = ((lg9[0] as Dictionary)["b"] as Basis) \
			* Vector3(0, 0, 1)
		_gc_tunnel(lg[0], lg[1], 2.6, 2.6, 0)
		_collar(lg[0], stub_dir,
			((lg[1] as Vector3) - (lg[0] as Vector3)).normalized(), 2.7, 2.8)
	var mid := _gc_tunnel(la[1], lb[1], 2.6, 2.6, 0)
	_collar(la[1], ((la[1] as Vector3) - (la[0] as Vector3)).normalized(),
		((lb[1] as Vector3) - (la[1] as Vector3)).normalized(), 2.6, 2.6)
	_collar(lb[1], ((lb[1] as Vector3) - (lb[0] as Vector3)).normalized(),
		((la[1] as Vector3) - (lb[1] as Vector3)).normalized(), 2.6, 2.6)
	if fan:
		_vent_fan(mid, 1.25)
	_net_probes.append(mid.origin + mid.basis.y * 0.1)

## an elevator cabin. xf: floor centre, Y up, +Z the doorway. Doors
## close, you TELEPORT, doors open pre-closed at the other end.
func _lift_cabin(lift: int, stop: int, xf: Transform3D, label: String,
		names: Array) -> void:
	while _lifts.size() <= lift:
		_lifts.append([])
	var root := Node3D.new()
	add_child(root)
	root.global_transform = xf
	var mk := func(size: Vector3, pos: Vector3) -> void:
		var sb := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = Surfaces.metal(STEEL)
		sb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		root.add_child(sb)
		sb.position = pos
	mk.call(Vector3(3.0, 0.4, 3.0), Vector3(0, -0.2, 0))
	mk.call(Vector3(3.0, 0.4, 3.0), Vector3(0, 2.9, 0))
	mk.call(Vector3(3.0, 3.1, 0.4), Vector3(0, 1.35, -1.5))
	mk.call(Vector3(0.4, 3.1, 3.4), Vector3(1.5, 1.35, 0.2))
	mk.call(Vector3(0.4, 3.1, 3.4), Vector3(-1.5, 1.35, 0.2))
	mk.call(Vector3(3.0, 0.5, 0.4), Vector3(0, 2.55, 1.5))
	mk.call(Vector3(0.75, 3.1, 0.4), Vector3(1.125, 1.35, 1.5))
	mk.call(Vector3(0.75, 3.1, 0.4), Vector3(-1.125, 1.35, 1.5))
	# the doors: two sliders, default OPEN
	var doors: Array = []
	for di in 2:
		var d := StaticBody3D.new()
		var dm := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(0.8, 2.3, 0.14)
		dm.mesh = dbm
		dm.material_override = Surfaces.cached_emissive(AMBER.darkened(0.35), 0.8)
		d.add_child(dm)
		var dc := CollisionShape3D.new()
		var dbs := BoxShape3D.new()
		dbs.size = Vector3(0.8, 2.3, 0.14)
		dc.shape = dbs
		d.add_child(dc)
		root.add_child(d)
		d.position = Vector3(1.15 * (1.0 if di == 0 else -1.0), 1.15, 1.42)
		doors.append(d)
	var cl := MeshInstance3D.new()
	var clm := CylinderMesh.new()
	clm.top_radius = 0.5
	clm.bottom_radius = 0.5
	clm.height = 0.06
	cl.mesh = clm
	cl.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 2.0)
	root.add_child(cl)
	cl.position = Vector3(0, 2.62, 0)
	# it LOOKS like an elevator now: glowing amber door frame + a lit
	# ELEVATOR sign over the opening
	for dfr in [[Vector3(0.16, 2.9, 0.16), Vector3(1.42, 1.35, 1.52)],
			[Vector3(0.16, 2.9, 0.16), Vector3(-1.42, 1.35, 1.52)],
			[Vector3(3.0, 0.16, 0.16), Vector3(0, 2.72, 1.52)]]:
		var fmi := MeshInstance3D.new()
		var fbm := BoxMesh.new()
		fbm.size = dfr[0]
		fmi.mesh = fbm
		fmi.material_override = Surfaces.cached_emissive(AMBER, 1.7)
		root.add_child(fmi)
		fmi.position = dfr[1]
	var sgn := Label3D.new()
	sgn.text = "ELEVATOR" if label == "ELEVATOR" else "ELEVATOR // " + label
	sgn.font_size = 26
	sgn.pixel_size = 0.007
	sgn.modulate = AMBER
	sgn.outline_size = 8
	sgn.outline_modulate = Color(0, 0, 0, 0.9)
	root.add_child(sgn)
	sgn.position = Vector3(0, 3.35, 1.6)
	# buttons on the SIDE wall by the door, stacked tight like a real
	# elevator panel
	var bi := 0
	for sti in names.size():
		if sti == stop:
			continue
		var btn := LiftBtn.new()
		btn.host = self
		btn.lift = lift
		btn.stop = sti
		var bmi := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(0.1, 0.24, 0.24)
		bmi.mesh = bbm
		bmi.material_override = Surfaces.cached_emissive(AMBER, 1.9)
		btn.add_child(bmi)
		var bcs := CollisionShape3D.new()
		var bbs := BoxShape3D.new()
		bbs.size = Vector3(0.16, 0.28, 0.28)
		bcs.shape = bbs
		btn.add_child(bcs)
		root.add_child(btn)
		btn.position = Vector3(1.26, 1.05 + 0.34 * float(bi), 0.85)
		var bl := Label3D.new()
		bl.text = str(names[sti])
		bl.font_size = 14
		bl.pixel_size = 0.0038
		bl.modulate = Color("#f2ead8")
		bl.outline_size = 6
		bl.outline_modulate = Color(0, 0, 0, 0.9)
		bl.rotation_degrees = Vector3(0, -90, 0)
		root.add_child(bl)
		bl.position = Vector3(1.24, 1.05 + 0.34 * float(bi), 0.42)
		bi += 1
	(_lifts[lift] as Array).append({"root": root, "doors": doors,
		"pos": xf.origin + xf.basis.y * 1.0, "up": xf.basis.y})

func _doors_set(stop: Dictionary, open: bool, snap: bool) -> void:
	for i in 2:
		var d: Node3D = (stop["doors"] as Array)[i]
		var sx := (1.15 if open else 0.41) * (1.0 if i == 0 else -1.0)
		if snap:
			d.position.x = sx
		else:
			var tw := create_tween()
			tw.tween_property(d, "position:x", sx, 0.4)

func _lift_go(l: int, target: int) -> void:
	if _lift_busy > 0.0 or l >= _lifts.size():
		return
	var st: Array = _lifts[l]
	if target >= st.size():
		return
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var cur := -1
	for i in st.size():
		if ((st[i] as Dictionary)["pos"] as Vector3) \
				.distance_to(pl.global_position) < 3.4:
			cur = i
	if cur == -1 or cur == target:
		Sfx.play("denied", -16.0)
		return
	_lift_busy = 2.2
	Sfx.play("click", -8.0)
	_doors_set(st[cur], false, false)
	await get_tree().create_timer(0.5).timeout
	_doors_set(st[target], false, true)
	var upv: Vector3 = (st[target] as Dictionary)["up"]
	if is_instance_valid(pl):
		pl.respawn_at(((st[target] as Dictionary)["pos"] as Vector3)
			- upv * 0.8 + upv * 0.2, upv)
	Sfx.play("warp", -14.0)
	await get_tree().create_timer(0.3).timeout
	_doors_set(st[target], true, false)
	_doors_set(st[cur], true, false)

## ---- LOWER FLOORS: elevator-only rooms + the planetary core ----
func _lower_floors() -> void:
	var mains: Array = ["ATRIUM", "DATA VAULT", "UNDERCROFT", "CORE VIEW"]
	# stop 0: atrium corner cabin
	var abas := _fr(0.0)
	# +X/+Z corner: clear of the airlock wall, the vent duct, the bunk
	# door AND the surface gate (which owns the opposite corner)
	var a_xf := Transform3D(abas * Basis(Vector3(0, 1, 0), PI * 1.25),
		Transform3D(abas, _C + _u0 * _rF)
		.translated_local(Vector3(4.3, 0, 4.3)).origin)
	_lift_cabin(0, 0, a_xf, "ELEVATOR", mains)
	# stop 1: DATA VAULT, radius 52 under the northwest hallway
	var vd := _sdir(-0.35, 0.0)
	var vb := _bup(vd)
	var vxf := Transform3D(vb, _C + vd * 52.0)
	_plate(Vector3(13.0, 0.5, 13.0), vxf, Vector3(0, -0.25, 0), DARK, 0.0)
	_plate(Vector3(13.0, 0.5, 13.0), vxf, Vector3(0, 5.25, 0), DARK, 0.0)
	for vw in [[Vector3(0.5, 6.0, 13.0), Vector3(6.25, 2.5, 0)],
			[Vector3(0.5, 6.0, 13.0), Vector3(-6.25, 2.5, 0)],
			[Vector3(13.0, 6.0, 0.5), Vector3(0, 2.5, 6.25)],
			[Vector3(13.0, 6.0, 0.5), Vector3(0, 2.5, -6.25)]]:
		_plate(vw[0], vxf, vw[1], STEEL, 0.0)
	for rr in 3:
		for rx in [-3.6, 3.6]:
			_rack(vb, vd, 52.0, Vector3(float(rx), 0, -3.4 + 3.4 * float(rr)),
				signf(float(rx)), float(rr) + float(rx))
	var vl := MeshInstance3D.new()
	var vlm := CylinderMesh.new()
	vlm.top_radius = 1.0
	vlm.bottom_radius = 1.0
	vlm.height = 0.08
	vl.mesh = vlm
	vl.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 2.0)
	add_child(vl)
	vl.global_transform = vxf.translated_local(Vector3(0, 4.9, 0))
	_sign("DATA VAULT", vb, vxf.origin + vd * 3.6, Vector3(0, 0, -5.7), 0.0)
	_vault_land = vxf.translated_local(Vector3(0, 1.2, 3.9)).origin
	# the pipe. nobody knows what it carries. it blocks the way anyway.
	var bpipe := StaticBody3D.new()
	var bpm := MeshInstance3D.new()
	var bpc := CylinderMesh.new()
	bpc.top_radius = 0.55
	bpc.bottom_radius = 0.55
	bpc.height = 12.6
	bpm.mesh = bpc
	bpm.material_override = Surfaces.metal(Color("#5e4a34"))
	bpipe.add_child(bpm)
	var bps := CollisionShape3D.new()
	var bpsc := CylinderShape3D.new()
	bpsc.radius = 0.55
	bpsc.height = 12.6
	bps.shape = bpsc
	bpipe.add_child(bps)
	add_child(bpipe)
	bpipe.global_transform = vxf.translated_local(Vector3(0, 1.1, 1.4))
	bpipe.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
	bpipe.rotate_object_local(Vector3(0, 1, 0), 0.35)
	_chatter(vxf.translated_local(Vector3(0, 1.4, 0)).origin, 240, -8.0)
	_net_probes.append(vxf.origin)
	_lift_cabin(0, 1, Transform3D(vb * Basis(Vector3(0, 1, 0), PI * 1.25),
		vxf.translated_local(Vector3(4.35, 0, 4.35)).origin), "ELEVATOR", mains)
	# stop 2: the UNDERCROFT -- not a room, a whole LOWER LEVEL: a full
	# 360-degree service ring at radius 47, twelve meters under the main
	# floor, with four working rooms hanging off it
	_lower_ring()
	# stop 3: THE PLANETARY CORE -- a real molten heart at the centre,
	# glass containment, and a glass-floored viewing ring around it
	var core := MeshInstance3D.new()
	var com := SphereMesh.new()
	com.radius = 5.0
	com.height = 10.0
	core.mesh = com
	core.material_override = DatamoshStudio._fluid_material(AMBER)
	add_child(core)
	core.global_transform = Transform3D(_fr(0.0), _C)
	_spins.append({"node": core, "rate": 0.15})
	var cglow := MeshInstance3D.new()
	var cgm2 := SphereMesh.new()
	cgm2.radius = 3.0
	cgm2.height = 6.0
	cglow.mesh = cgm2
	var cgmat := StandardMaterial3D.new()
	cgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cgmat.albedo_color = Color("#fff2cf")
	cgmat.emission_enabled = true
	cgmat.emission = Color("#ffd27a")
	cglow.material_override = cgmat
	add_child(cglow)
	cglow.global_transform = Transform3D(_fr(0.0), _C)
	var shell := StaticBody3D.new()
	var shmi := MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 7.0
	shm.height = 14.0
	shmi.mesh = shm
	var shmat := StandardMaterial3D.new()
	shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shmat.albedo_color = Color(1.0, 0.8, 0.45, 0.10)
	shmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shmi.material_override = shmat
	shell.add_child(shmi)
	var shcs := CollisionShape3D.new()
	var shs := SphereShape3D.new()
	shs.radius = 7.0
	shcs.shape = shs
	shell.add_child(shcs)
	add_child(shell)
	shell.global_transform = Transform3D(_fr(0.0), _C)
	_core_noise(_C + _u0 * 6.0)
	# the ring: three chained arcs of one great circle at r=11 (glass
	# floors), broken only by the elevator cabin at a=0
	var rr9 := 11.0
	for seg3 in [[0.16, 2.15], [2.15, 4.14], [4.14, 6.12]]:
		_gc_tunnel(_C + _pdir(float(seg3[0])) * rr9,
			_C + _pdir(float(seg3[1])) * rr9, 3.4, 3.2, 3)
	var cvb := Basis(_e2, _u0, _e1).orthonormalized()
	_lift_cabin(0, 3, Transform3D(cvb, _C + _u0 * rr9), "CORE VIEW", mains)
	_sign("CORE VIEW", cvb, _C + _u0 * (rr9 + 3.6), Vector3(0, 0, 2.2), 180.0)
	_net_probes.append(_C + _pdir(1.5) * rr9)

class MapBtn extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._map_take()

var _map_rooms: Array = []     # [name, world pos] in cycle order
var _map_sel := -1
var _map_holo: Array = []      # the current path markers
var _map_holo_t := 0.0
var _map_chk := 1.0

func _map_take() -> void:
	if Inventory.res_count("dudemap") > 0:
		_hud_flash("you already carry the map")
		Sfx.play("denied", -16.0)
		return
	Inventory.add_res("dudemap", 1)
	Sfx.play("coin", -8.0)
	_hud_flash("FACILITY MAP -- use it to plot a course; it dies outside")

## called from the player when USING the held map: cycle rooms, draw
## a holographic path arcing through the facility toward the pick
func map_use() -> void:
	if _map_rooms.is_empty():
		_map_rooms = [
			["ATRIUM", _C + _u0 * (_rF + 1.0)],
			["CONTROL DECK", _C + _pdir(_a0 + _step * 7.0) * (_rF + 1.0)],
			["LAB COMPLEX", _C + _sdir(_a0 + _step * 3.0, -12.0 / _rF) * (_rF + 1.0)],
			["GRAND AQUARIUM", _C + _aup9(1, 1.92) * (_rF + 1.0)],
			["MAP ROOM", _C + _sdir(_a0 + _step * 9.0, 12.0 / _rF) * (_rF + 1.0)],
			["SERVER HALL", _C + _pdir(_a0 + _step * 7.0) * (_r2 + 1.0)],
			["REACTOR CORE", _C + _pdir(1.3708) * (_rF - 8.0)],
			["COMMUNICATIONS", _C + _sdir(1.3708, 22.05 / _rF) * (_rF + 1.0)],
			["DUDE A.I.", _C + _pdir(2.685) * (_rF + 1.0)],
			["PLANET CONTROL", _C - _u0 * (_rF + 1.0)],
			["SERVER HALL 2", _C + _pdir(3.775) * (_rF + 1.0)],
			["ASSEMBLY", _C + _pdir(-0.722) * (_rF + 1.0)],
			["GENERATOR", _C + _pdir(-0.978) * (_rF + 1.0)],
			["BUNKS", _C + _pdx(-0.3) * (_rF + 1.0)],
			["KITCHEN", _C + _aup9(1, 4.0) * (_rF + 1.0)],
			["MEDBAY", _C + _aup9(1, 0.75) * (_rF + 1.0)],
		]
	_map_sel = (_map_sel + 1) % _map_rooms.size()
	var pick: Array = _map_rooms[_map_sel]
	_hud_flash("MAP: -> %s" % str(pick[0]))
	Sfx.play("click", -12.0)
	for m in _map_holo:
		if is_instance_valid(m):
			(m as Node).queue_free()
	_map_holo.clear()
	_map_holo_t = 24.0
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var d1 := ((pl.global_position as Vector3) - _C).normalized()
	var d2 := ((pick[1] as Vector3) - _C).normalized()
	var r1 := ((pl.global_position as Vector3) - _C).length()
	var r2c := ((pick[1] as Vector3) - _C).length()
	var ang := d1.angle_to(d2)
	var nx := d1.cross(d2)
	if nx.length() < 0.01:
		nx = d1.cross(_e2)
	nx = nx.normalized()
	var n := maxi(3, int(ang * 60.0 / 2.2))
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(0.4, 1.0, 0.7, 0.55)
	hmat.emission_enabled = true
	hmat.emission = Color(0.4, 1.0, 0.7)
	for i in n + 1:
		var t := float(i) / float(n)
		var dd := d1.rotated(nx, ang * t)
		var mk := MeshInstance3D.new()
		var mm2 := SphereMesh.new()
		mm2.radius = 0.14 if i < n else 0.34
		mm2.height = mm2.radius * 2.0
		mk.mesh = mm2
		mk.material_override = hmat
		add_child(mk)
		mk.global_position = _C + dd * lerpf(r1, r2c, t)
		_map_holo.append(mk)

## ==================== THE LOWER RING (r=47) ====================
## A second full circle of facility below everything walkable above:
## service hallway wrapping the whole planet + four rooms. Elevator
## stop 2 lands here.
const R_LOW := 47.0

func _lring_room(ac: float, sd: float, name: String) -> Dictionary:
	var fb := _fr(ac)
	var up := _pdir(ac)
	var xf0 := Transform3D(fb, _C + up * R_LOW)
	_plate(Vector3(9.7, 0.5, 9.6), xf0, Vector3(sd * 7.9, -0.25, 0), DARK, 0.0)
	_plate(Vector3(9.7, 0.5, 9.6), xf0, Vector3(sd * 7.9, 4.75, 0), DARK, 0.0)
	var wxf := Transform3D(fb, _C + up * (R_LOW + 2.25))
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(sd * 3.15, 0, 3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 3.6), wxf, Vector3(sd * 3.15, 0, -3.0), STEEL, 0.0)
	_plate(Vector3(0.5, 2.0, 2.4), wxf, Vector3(sd * 3.15, 1.75, 0), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 9.6), wxf, Vector3(sd * 12.65, 0, 0), STEEL, 0.0)
	_plate(Vector3(9.5, 5.5, 0.5), wxf, Vector3(sd * 7.9, 0, 4.55), STEEL, 0.0)
	_plate(Vector3(9.5, 5.5, 0.5), wxf, Vector3(sd * 7.9, 0, -4.55), STEEL, 0.0)
	var rl := MeshInstance3D.new()
	var rlm := CylinderMesh.new()
	rlm.top_radius = 0.8
	rlm.bottom_radius = 0.8
	rlm.height = 0.08
	rl.mesh = rlm
	rl.material_override = Surfaces.cached_emissive(Color("#f2ead8"), 1.9)
	add_child(rl)
	rl.global_transform = Transform3D(fb, _C + up * (R_LOW + 4.45))
	rl.translate_object_local(Vector3(sd * 7.9, 0, 0))
	_sign(name, fb, _C + up * (R_LOW + 3.6), Vector3(sd * 2.4, 0, 0),
		90.0 if sd < 0.0 else -90.0)
	_net_probes.append(xf0.translated_local(Vector3(sd * 7.9, 1.0, 0)).origin)
	return {"fb": fb, "up": up, "cx": sd * 7.9}

func _lower_ring() -> void:
	# the hallway: full 360 in arc-strip segments, doors where rooms sit
	var doors: Array = [[0.6, -1.0], [2.2, 1.0], [3.9, -1.0], [5.3, 1.0],
		[TAU / 69.0 * 31.5, -1.0]]
	var m := TAU * R_LOW
	var n := int(ceil(m / 4.3))
	var stp := TAU / float(n)
	for k in n:
		var a2 := stp * (float(k) + 0.5)
		var fb := _fr(a2)
		var up := _pdir(a2)
		_plate(Vector3(6.6, 0.5, 4.6), Transform3D(fb, _C + up * (R_LOW - 0.25)),
			Vector3.ZERO, DARK, 0.0)
		_plate(Vector3(6.6, 0.5, 4.6), Transform3D(fb, _C + up * (R_LOW + 4.75)),
			Vector3.ZERO, DARK, 0.0)
		var wxf := Transform3D(fb, _C + up * (R_LOW + 2.25))
		for ws in [1.0, -1.0]:
			var door := false
			for d in doors:
				if float(d[1]) == ws and absf(_awrap(a2 - float(d[0]))) * R_LOW < 2.4:
					door = true
			if not door:
				_plate(Vector3(0.5, 5.5, 4.6), wxf, Vector3(ws * 3.05, 0, 0), STEEL, 0.0)
				_deco_box(Vector3(0.06, 0.16, 4.6), wxf,
					Vector3(ws * 2.72, -1.3, 0), AMBER, 1.6)
		_deco_box(Vector3(0.2, 4.5, 0.2), wxf, Vector3(2.62, 0, 2.1), STEEL, 0.0)
		_deco_box(Vector3(0.2, 4.5, 0.2), wxf, Vector3(-2.62, 0, 2.1), STEEL, 0.0)
		if k % 3 == 0:
			_deco_box(Vector3(0.5, 0.08, 3.0),
				Transform3D(fb, _C + up * (R_LOW + 4.35)), Vector3.ZERO,
				Color("#f2ead8"), 2.2)
	_sign("UNDERCROFT RING", _fr(0.25), _C + _pdir(0.25) * (R_LOW + 3.4),
		Vector3.ZERO, 180.0)
	# the LOWER AIRLOCK: centered EXACTLY in its wall gap, with filler
	# plates sealing the bands the frame leaves beside and above it
	var aA2 := TAU / 69.0 * 31.5   # the skipped wall segment's centre
	var afb := _fr(aA2)
	_airlock(Transform3D(afb * Basis(Vector3(0, 1, 0), -PI * 0.5),
		Transform3D(afb, _C + _pdir(aA2) * R_LOW)
		.translated_local(Vector3(-3.05, 0, 0)).origin))
	var awx9 := Transform3D(afb, _C + _pdir(aA2) * (R_LOW + 2.25))
	_plate(Vector3(0.5, 5.5, 1.0), awx9, Vector3(-3.05, 0, 1.95), STEEL, 0.0)
	_plate(Vector3(0.5, 5.5, 1.0), awx9, Vector3(-3.05, 0, -1.95), STEEL, 0.0)
	_plate(Vector3(0.5, 1.95, 3.1), awx9, Vector3(-3.05, 1.8, 0), STEEL, 0.0)
	# ---- room 1: PUMP HALL (the old undercroft, now one of four) ----
	var pr := _lring_room(0.6, -1.0, "PUMP HALL")
	for pz in [-3.0, 0.0, 3.0]:
		var uxf := Transform3D(pr["fb"] as Basis,
			_C + (pr["up"] as Vector3) * R_LOW)
		var pipe := MeshInstance3D.new()
		var ppm := CylinderMesh.new()
		ppm.top_radius = 0.5
		ppm.bottom_radius = 0.5
		ppm.height = 8.6
		pipe.mesh = ppm
		pipe.material_override = Surfaces.metal(Color("#4a5266"))
		add_child(pipe)
		pipe.global_transform = uxf.translated_local(
			Vector3(float(pr["cx"]), 3.3, pz))
		pipe.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
		var pump := MeshInstance3D.new()
		var pum := BoxMesh.new()
		pum.size = Vector3(1.6, 1.4, 1.6)
		pump.mesh = pum
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.albedo_color = AMBER.darkened(0.5)
		pmat.emission_enabled = true
		pmat.emission = AMBER
		pump.material_override = pmat
		add_child(pump)
		pump.global_transform = uxf.translated_local(
			Vector3(float(pr["cx"]) - 3.0, 0.7, pz))
		_pulses.append({"mat": pmat, "phase": pz})
		var wheel := MeshInstance3D.new()
		var whm := TorusMesh.new()
		whm.inner_radius = 0.28
		whm.outer_radius = 0.42
		wheel.mesh = whm
		wheel.material_override = Surfaces.cached_emissive(Color("#ff6a6a"), 1.2)
		add_child(wheel)
		wheel.global_transform = uxf.translated_local(
			Vector3(float(pr["cx"]) - 2.1, 0.9, pz))
		wheel.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
		_spins.append({"node": wheel, "rate": 0.9})
	_chatter(Transform3D(pr["fb"] as Basis, _C + (pr["up"] as Vector3)
		* (R_LOW + 1.4)).translated_local(Vector3(float(pr["cx"]), 0, 0)).origin,
		241, -7.0)
	_escape_gate(Transform3D(pr["fb"] as Basis, _C + (pr["up"] as Vector3)
		* (R_LOW + 1.3)), Vector3(float(pr["cx"]) - 3.6, 0, -3.6))
	# ---- room 2: COOLANT TANKS ----
	var cr := _lring_room(2.2, 1.0, "COOLANT TANKS")
	for tz in [[-2.6, -2.4], [-2.6, 2.4], [2.6, 0.0]]:
		var txf := Transform3D(cr["fb"] as Basis,
			_C + (cr["up"] as Vector3) * R_LOW)
		var tank := MeshInstance3D.new()
		var tkm := CylinderMesh.new()
		tkm.top_radius = 1.5
		tkm.bottom_radius = 1.5
		tkm.height = 4.2
		tank.mesh = tkm
		tank.material_override = Surfaces.metal(Color("#31384a"))
		add_child(tank)
		tank.global_transform = txf.translated_local(
			Vector3(float(cr["cx"]) + float(tz[0]), 2.1, float(tz[1])))
		var lvl := MeshInstance3D.new()
		var lvm := BoxMesh.new()
		lvm.size = Vector3(0.1, 2.6, 0.3)
		lvl.mesh = lvm
		lvl.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 1.7)
		add_child(lvl)
		lvl.global_transform = txf.translated_local(
			Vector3(float(cr["cx"]) + float(tz[0]) - 1.58, 1.8, float(tz[1])))
		var tcb := StaticBody3D.new()
		var tcc := CollisionShape3D.new()
		var tcs2 := CylinderShape3D.new()
		tcs2.radius = 1.6
		tcs2.height = 4.2
		tcc.shape = tcs2
		tcb.add_child(tcc)
		add_child(tcb)
		tcb.global_transform = txf.translated_local(
			Vector3(float(cr["cx"]) + float(tz[0]), 2.1, float(tz[1])))
	# ---- room 3: PIPE GALLERY ----
	var gr := _lring_room(3.9, -1.0, "PIPE GALLERY")
	for gy in 3:
		for gz9 in [-3.4, 3.4]:
			var gxf := Transform3D(gr["fb"] as Basis,
				_C + (gr["up"] as Vector3) * (R_LOW + 0.9 + 1.3 * float(gy)))
			var pipe2 := MeshInstance3D.new()
			var pp2 := CylinderMesh.new()
			pp2.top_radius = 0.24 + 0.08 * float(gy % 2)
			pp2.bottom_radius = pp2.top_radius
			pp2.height = 8.8
			pipe2.mesh = pp2
			pipe2.material_override = Surfaces.metal(
				[Color("#4a5266"), Color("#5e4a34"), Color("#3a5246")][gy])
			add_child(pipe2)
			pipe2.global_transform = gxf.translated_local(
				Vector3(float(gr["cx"]), 0, float(gz9)))
			pipe2.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
	_chatter(Transform3D(gr["fb"] as Basis, _C + (gr["up"] as Vector3)
		* (R_LOW + 1.4)).translated_local(Vector3(float(gr["cx"]), 0, 0)).origin,
		242, -10.0)
	# ---- room 4: THE SUMP (fluid-glow pool, grated walkway) ----
	var sr := _lring_room(5.3, 1.0, "THE SUMP")
	var sxf := Transform3D(sr["fb"] as Basis, _C + (sr["up"] as Vector3) * R_LOW)
	var pool := MeshInstance3D.new()
	var plm2 := BoxMesh.new()
	plm2.size = Vector3(7.6, 0.06, 7.6)
	pool.mesh = plm2
	pool.material_override = DatamoshStudio._fluid_material(Color("#2a9df4"))
	add_child(pool)
	pool.global_transform = sxf.translated_local(Vector3(float(sr["cx"]), 0.25, 0))
	_plate(Vector3(2.0, 0.3, 9.4), sxf, Vector3(float(sr["cx"]), 0.55, 0),
		Color("#12161c"), 0.0)
	_escape_gate(sxf.translated_local(Vector3(0, 1.3, 0)),
		Vector3(float(sr["cx"]), 0.7, 3.4))
	# ring probes for MFTEST
	_net_probes.append(Transform3D(_fr(1.4), _C + _pdir(1.4) * R_LOW).origin)
	_net_probes.append(Transform3D(_fr(4.6), _C + _pdir(4.6) * R_LOW).origin)
	# the elevator cabin, in the ring beside PUMP HALL's door
	var cb0 := _fr(0.32)
	_lift_cabin(0, 2, Transform3D(cb0 * Basis(Vector3(0, 1, 0), PI),
		Transform3D(cb0, _C + _pdir(0.32) * R_LOW).origin), "ELEVATOR",
		["ATRIUM", "DATA VAULT", "UNDERCROFT", "CORE VIEW"])

## An AIRLOCK: a sliding door between the facility and the hollow void
## of the planet. F opens it from EITHER side; it slides, waits, and
## seals itself again. The outside face burns bright so a dude lost in
## the dark of the hollow can find the way back in.
class Airlock extends StaticBody3D:
	var _open := false
	var _busy := false
	func use() -> void:
		if _busy:
			return
		_busy = true
		_open = not _open
		Sfx.play("click", -10.0)
		var tw := create_tween()
		tw.tween_property(self, "position:x", 2.35 if _open else 0.0, 1.1) \
			.set_trans(Tween.TRANS_SINE)
		await tw.finished
		_busy = false
		if _open:
			# airlocks SEAL THEMSELVES. always. quickly.
			await get_tree().create_timer(3.0).timeout
			if _open and not _busy:
				use()

func _airlock(xf: Transform3D) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = xf
	var mk := func(size: Vector3, pos: Vector3, col: Color, emit: float) -> void:
		var sb := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = Surfaces.metal(col) if emit <= 0.3 \
			else Surfaces.cached_emissive(col, emit)
		sb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		root.add_child(sb)
		sb.position = pos
	# frame posts + header, glowing hard on the OUTSIDE (+Z) edge
	mk.call(Vector3(0.4, 3.2, 0.7), Vector3(-1.3, 1.4, 0), STEEL, 0.0)
	mk.call(Vector3(0.4, 3.2, 0.7), Vector3(1.3, 1.4, 0), STEEL, 0.0)
	mk.call(Vector3(3.0, 0.4, 0.7), Vector3(0, 3.0, 0), STEEL, 0.0)
	for gspec in [[Vector3(0.12, 3.3, 0.12), Vector3(-1.35, 1.4, 0.4)],
			[Vector3(0.12, 3.3, 0.12), Vector3(1.35, 1.4, 0.4)],
			[Vector3(2.9, 0.12, 0.12), Vector3(0, 3.12, 0.4)]]:
		var gd := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = gspec[0]
		gd.mesh = gb
		gd.material_override = Surfaces.cached_emissive(Color("#7df9ff"), 2.6)
		root.add_child(gd)
		gd.position = gspec[1]
	# the beacon over the outside face -- visible across the hollow
	var bcn := MeshInstance3D.new()
	var bcm := SphereMesh.new()
	bcm.radius = 0.22
	bcm.height = 0.44
	bcn.mesh = bcm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color("#7df9ff")
	bmat.emission_enabled = true
	bmat.emission = Color("#7df9ff")
	bcn.material_override = bmat
	root.add_child(bcn)
	bcn.position = Vector3(0, 3.55, 0.45)
	_blinks.append({"mat": bmat, "phase": randf() * TAU})
	var alb := Label3D.new()
	alb.text = "AIRLOCK\nJETPACK REQUIRED"
	alb.font_size = 24
	alb.pixel_size = 0.007
	alb.modulate = Color("#7df9ff")
	alb.outline_size = 8
	alb.outline_modulate = Color(0, 0, 0, 0.9)
	root.add_child(alb)
	alb.position = Vector3(0, 4.1, 0.45)
	# outside landing RUNWAY with GLOWING guard rails down both sides --
	# the far end stays open: that is the jump
	mk.call(Vector3(3.4, 0.4, 7.5), Vector3(0, -0.2, 4.05), STEEL, 0.0)
	for rs9 in [-1.0, 1.0]:
		mk.call(Vector3(0.12, 1.1, 7.5), Vector3(rs9 * 1.64, 0.55, 4.05),
			STEEL, 0.0)
		for rg9 in [[Vector3(0.14, 0.1, 7.5), Vector3(rs9 * 1.64, 1.12, 4.05)],
				[Vector3(0.14, 0.08, 7.5), Vector3(rs9 * 1.64, 0.55, 4.05)]]:
			var rgm9 := MeshInstance3D.new()
			var rgb9 := BoxMesh.new()
			rgb9.size = rg9[0]
			rgm9.mesh = rgb9
			rgm9.material_override = Surfaces.cached_emissive(
				Color("#7df9ff"), 2.4)
			root.add_child(rgm9)
			rgm9.position = rg9[1]
	# THE DOOR: slides right into the wall pocket. F from either side.
	var door := Airlock.new()
	var dmi := MeshInstance3D.new()
	var dbm := BoxMesh.new()
	dbm.size = Vector3(2.25, 2.85, 0.3)
	dmi.mesh = dbm
	dmi.material_override = Surfaces.cached_emissive(Color("#31384a"), 0.5)
	door.add_child(dmi)
	var dstripe := MeshInstance3D.new()
	var dsm := BoxMesh.new()
	dsm.size = Vector3(1.7, 0.14, 0.34)
	dstripe.mesh = dsm
	dstripe.material_override = Surfaces.cached_emissive(AMBER, 1.8)
	door.add_child(dstripe)
	dstripe.position = Vector3(0, 0.6, 0)
	var dcs := CollisionShape3D.new()
	var dbs := BoxShape3D.new()
	dbs.size = dbm.size
	dcs.shape = dbs
	door.add_child(dcs)
	root.add_child(door)
	door.position = Vector3(0, 1.4, 0)

class SurfBtn extends StaticBody3D:
	var host = null
	func use() -> void:
		if host != null:
			host._surf_bail()

func _surf_bail() -> void:
	var pl = get_tree().get_first_node_in_group("player")
	if pl != null:
		pl.respawn_at(_lobby_land + (_lobby_land - _C).normalized() * 0.4,
			(_lobby_land - _C).normalized())
		Sfx.play("warp", -10.0)

## a BAIL button beside a tunnel entrance: F sends you to the lobby
func _surface_btn(pt: Vector3) -> void:
	var up9 := (pt - _C).normalized()
	var bb := _bup(up9)
	var btn := SurfBtn.new()
	btn.host = self
	var bmi := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(0.34, 0.34, 0.18)
	bmi.mesh = bbm
	bmi.material_override = Surfaces.cached_emissive(Color("#66ff99"), 1.9)
	btn.add_child(bmi)
	var bcs := CollisionShape3D.new()
	var bbs := BoxShape3D.new()
	bbs.size = Vector3(0.4, 0.4, 0.3)
	bcs.shape = bbs
	btn.add_child(bcs)
	add_child(btn)
	btn.global_transform = Transform3D(bb, pt + up9 * 1.5)
	var bl := Label3D.new()
	bl.text = "LOBBY [F]"
	bl.font_size = 18
	bl.pixel_size = 0.005
	bl.modulate = Color("#66ff99")
	bl.outline_size = 8
	bl.outline_modulate = Color(0, 0, 0, 0.9)
	bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(bl)
	bl.global_position = pt + up9 * 2.1

## an EXIT gate: teleports to the LOBBY (atrium floor), where the
## surface gate and the elevator both live. One hub, no maze re-runs.
var _lobby_land: Vector3
var _vault_land: Vector3
func _escape_gate(xf: Transform3D, off: Vector3) -> void:
	var ep := Gate.new().configure({
		"target": _lobby_land, "zone": "",
		"label": "EXIT", "color": Color("#ff8a2a"), "cube": true})
	add_child(ep)
	ep.global_transform = xf
	ep.translate_object_local(off)

func _networks() -> void:
	# ---- THE VENTS v2: grille stub -> steep dive -> cruise in one of
	# three radius bands (58 / 54.5 / 51.5) so no vent ever crosses
	# another, with bulkhead collars sealing every kink ----
	var vpairs: Array = [
		["medbay", 1, "gym", 0, 58.8, true],
		["gym", 1, "archive", 0, 58.8, false],
		["archive", 1, "tape", 1, 58.8, false],
		["tape", 0, "farm", 1, 58.8, true],
		["workshop", 1, "storage", 1, 58.8, false],
		["kitchen", 1, "trophy", 0, 58.8, false],
		["workshop", 0, "kitchen", 0, 58.8, true],
	]
	for vp9 in vpairs:
		_vent_run((_vp[vp9[0]] as Array)[int(vp9[1])],
			(_vp[vp9[2]] as Array)[int(vp9[3])], float(vp9[4]), bool(vp9[5]))
	_vent_run({"p": _duct_end, "o": _duct_out, "b": _duct_bas},
		(_vp["medbay"] as Array)[0], 58.8, false)
	# ---- THE COMPUTER TUNNELS: six hub junction boxes deep in the
	# hollow (all below radius 49 -- verified clear of every room and
	# every vent), wired as a branching web. The ONLY ways down are the
	# four hidden ELEVATORS behind the breaches. ----
	var hubs: Array = [
		[_sdir(0.75, 0.45), 45.5],
		[_sdir(1.9, -0.7), 43.5],
		[_sdir(2.9, 0.9), 45.0],
		[(_pdx(4.6) + _e1 * 0.5).normalized(), 41.0],
		[(_pdx(1.6) + _e1 * -0.6).normalized(), 44.5],
		[(-_u0 + _e1 * 0.4 + _e2 * -0.5).normalized(), 40.5],
	]
	var edges: Array = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [0, 2]]
	var used: Array = []
	var doorf: Array = []
	for i9 in hubs.size():
		used.append([false, false, false, false])
		doorf.append([false, false, false, false])
	var face_pick := func(hi: int, toward: Vector3) -> int:
		var hd: Vector3 = (hubs[hi] as Array)[0]
		var hb9 := _bup(hd)
		var v := (toward - _C).normalized()
		v = (v - hd * hd.dot(v)).normalized()
		var norms: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
			Vector3(0, 0, 1), Vector3(0, 0, -1)]
		var bi := -1
		var bd := -2.0
		for f in 4:
			if (used[hi] as Array)[f]:
				continue
			var d9 := (hb9 * (norms[f] as Vector3)).dot(v)
			if d9 > bd:
				bd = d9
				bi = f
		(used[hi] as Array)[bi] = true
		(doorf[hi] as Array)[bi] = true
		return bi
	var plan: Array = []
	for e9 in edges:
		var ha: int = e9[0]
		var hbb: int = e9[1]
		var pa9: Vector3 = _C + ((hubs[ha] as Array)[0] as Vector3) \
			* float((hubs[ha] as Array)[1])
		var pb9: Vector3 = _C + ((hubs[hbb] as Array)[0] as Vector3) \
			* float((hubs[hbb] as Array)[1])
		plan.append([ha, face_pick.call(ha, pb9), hbb, face_pick.call(hbb, pa9)])
	var ndir := (-_u0 - _e1 * 0.6 + _e2 * 0.6).normalized()
	var nface: int = face_pick.call(5, _C + ndir * 40.0)
	var exs: Array = [
		["srv", 0], ["cargo", 0], ["gold", 3], ["ai", 2]]
	var eplan: Array = []
	for ex in exs:
		eplan.append([str(ex[0]), int(ex[1]),
			int(face_pick.call(int(ex[1]), _e_pts[ex[0]]))])
	var chk: Array = []
	for hi9 in [1, 3, 4]:
		for f9 in 4:
			if not (used[hi9] as Array)[f9]:
				(used[hi9] as Array)[f9] = true
				(doorf[hi9] as Array)[f9] = true
				chk.append([hi9, f9])
				break
	var fpts: Array = []
	for i9 in hubs.size():
		fpts.append(_hub((hubs[i9] as Array)[0],
			float((hubs[i9] as Array)[1]), doorf[i9]))
	for pe in plan:
		_gc_tunnel((fpts[pe[0]] as Array)[pe[1]],
			(fpts[pe[2]] as Array)[pe[3]], 3.4, 3.2, 1, 1.5)
	var ndoor := _noodle_room(ndir, 40.0, _C
		+ ((hubs[5] as Array)[0] as Vector3) * 40.5)
	_gc_tunnel((fpts[5] as Array)[nface], ndoor, 3.4, 3.2, 1, 1.0)
	var ci := 0
	for cf in chk:
		var hi: int = cf[0]
		var f: int = cf[1]
		var hd: Vector3 = (hubs[hi] as Array)[0]
		var wnorm := _bup(hd) * ([Vector3(1, 0, 0), Vector3(-1, 0, 0),
			Vector3(0, 0, 1), Vector3(0, 0, -1)][f] as Vector3)
		_checkpoint((fpts[hi] as Array)[f], wnorm, ci)
		ci += 1
	# ---- the four entrances: STEEP OPEN CORRIDORS (no cabins to get
	# stuck behind), each with a LOBBY bail button just inside the
	# breach so you can always back out before committing to the deep
	for ep9 in eplan:
		_gc_tunnel(_e_pts[ep9[0]], (fpts[int(ep9[1])] as Array)[int(ep9[2])],
			3.0, 2.9, 1)
		_surface_btn(_e_pts[ep9[0]])
	set_meta("net_probes", _net_probes)

## cabin frame behind each hidden breach
func _entry_cab_xf(key: String) -> Transform3D:
	match key:
		"srv":
			var ah := _a0 + _step * float(HATCH_SEG)
			var hb := _fr(ah)
			return Transform3D(hb, Transform3D(hb, _C + _pdir(ah) * _r2)
				.translated_local(Vector3(-7.0, 0, -9.2)).origin)
		"cargo":
			var ac9 := _a0 + _step * 11.0
			var fb := _fr(ac9)
			return Transform3D(fb * Basis(Vector3(0, 1, 0), PI * 0.5),
				Transform3D(fb, _C + _pdir(ac9) * _rF)
				.translated_local(Vector3(-15.6, 0, -2.6)).origin)
		"gold":
			var b4 := -(_a0 + _step * 4.0)
			var fb4 := _fx(b4)
			return Transform3D(fb4 * Basis(Vector3(0, 1, 0), -PI * 0.5),
				Transform3D(fb4, _C + _pdx(b4) * (_rF - 7.0))
				.translated_local(Vector3(7.9, 0, -3.1)).origin)
		_:
			var fb9 := _fr(2.8033)
			return Transform3D(fb9 * Basis(Vector3(0, 1, 0), PI * 0.5),
				Transform3D(fb9, _C + _pdir(2.8033) * _rF)
				.translated_local(Vector3(-9.4, 0, 0)).origin)


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
	cs.shape = Surfaces.box_shape(size)
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func _plate(size: Vector3, xf: Transform3D, off: Vector3,
		col: Color, emit: float) -> void:
	var sb := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Surfaces.box_mesh(size)
	mi.material_override = Surfaces.metal(col) if emit <= 0.3 \
		else Surfaces.cached_emissive(col, emit)
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = Surfaces.box_shape(size)
	sb.add_child(cs)
	add_child(sb)
	sb.global_transform = xf
	sb.translate_object_local(off)

func _deco_box(size: Vector3, xf: Transform3D, off: Vector3,
		col: Color, emit: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Surfaces.box_mesh(size)
	mi.material_override = Surfaces.metal(col) if emit <= 0.3 \
		else Surfaces.cached_emissive(col, emit)
	add_child(mi)
	mi.global_transform = xf
	mi.translate_object_local(off)

func _process(delta: float) -> void:
	_t += delta
	for bl in _blinks:
		# unshaded materials show ALBEDO regardless of emission -- to
		# blink for real, the color itself must go dark
		var bm9 := bl["mat"] as StandardMaterial3D
		var lit9 := fmod(_t + float(bl["phase"]), 1.4) < 0.75
		bm9.emission_energy_multiplier = 2.4 if lit9 else 0.05
		bm9.albedo_color = bm9.emission * (1.0 if lit9 else 0.07)
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
	_lift_busy = maxf(0.0, _lift_busy - delta)
	if _ai_mat != null and _ai_sp != null and not _ai_sp.playing:
		_ai_mat.set_shader_parameter("talking", 0.0)
		if _ai_lbl != null and _ai_lbl.text != "":
			_ai_lbl.text = ""
	if _map_holo_t > 0.0:
		_map_holo_t -= delta
		if _map_holo_t <= 0.0:
			for m in _map_holo:
				if is_instance_valid(m):
					(m as Node).queue_free()
			_map_holo.clear()
	# the map dies outside the facility -- even in your backpack
	_map_chk -= delta
	if _map_chk <= 0.0:
		_map_chk = 1.0
		var pl9 = get_tree().get_first_node_in_group("player")
		if pl9 != null and Inventory.res_count("dudemap") > 0 \
				and ((pl9.global_position as Vector3) - _C).length() \
				> float(_b.radius) + 2.0:
			Inventory.remove_res("dudemap", Inventory.res_count("dudemap"))
			_hud_flash("the facility map dissolves into thin air")
			Sfx.play("denied", -18.0)
	if _specimen != null and is_instance_valid(_specimen):
		_specimen.rotate_object_local(Vector3(0, 1, 0), delta * 0.7)
	if _sock_tetra != null and is_instance_valid(_sock_tetra) \
			and _sock_tetra.visible:
		_sock_tetra.rotate_object_local(Vector3(0, 1, 0), delta * 0.9)
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
	# aquarium creatures: jellies bob, the eel snakes, the manta beats
	# its wings, the school wheels
	for cr9 in _creatures:
		var cn: Node3D = cr9["node"]
		var cfb: Basis = cr9["fb"]
		var cup: Vector3 = cr9["up"]
		var cph := _t * 0.4 + float(cr9["phase"])
		match int(cr9["kind"]):
			0:
				cn.global_transform = Transform3D(cfb,
					Transform3D(cfb, _C + cup * (_rF + 2.6
					+ 1.1 * sin(cph * 1.7))).translated_local(Vector3(
					float(cr9["x"]) + 0.8 * sin(cph), 0,
					2.2 * cos(cph * 0.6))).origin)
			1:
				var segs: Array = cr9["segs"]
				var ex := float(cr9["x"]) + 0.6 * sin(cph * 0.9)
				cn.global_transform = Transform3D(
					cfb * Basis(Vector3(0, 1, 0), cph * 0.7),
					Transform3D(cfb, _C + cup * (_rF + 1.3
					+ 0.5 * sin(cph))).translated_local(
					Vector3(ex, 0, 3.5 * sin(cph * 0.5))).origin)
				for si9 in segs.size():
					(segs[si9] as Node3D).position = Vector3(
						0.35 * sin(_t * 3.0 - float(si9) * 0.9), 0,
						-0.28 * float(si9))
			2:
				cn.global_transform = Transform3D(
					cfb * Basis(Vector3(0, 1, 0), -cph * 0.55 + PI * 0.5),
					Transform3D(cfb, _C + cup * (_rF + 3.4
					+ 0.6 * sin(cph * 1.3))).translated_local(Vector3(
					float(cr9["x"]) + 1.6 * cos(cph * 0.55), 0,
					4.4 * sin(cph * 0.55))).origin)
				for wi9 in (cr9["wings"] as Array).size():
					((cr9["wings"] as Array)[wi9] as Node3D).rotation.z = \
						(1.0 if wi9 == 0 else -1.0) * 0.55 * sin(_t * 2.6)
			3:
				cn.global_transform = Transform3D(
					cfb * Basis(Vector3(0, 1, 0), cph * 1.1 + PI * 0.5),
					Transform3D(cfb, _C + cup * (_rF + 2.3
					+ 0.9 * sin(cph * 2.1))).translated_local(Vector3(
					float(cr9["x"]) + 1.2 * sin(cph * 1.1), 0,
					3.6 * cos(cph * 1.1))).origin)
	# fusion: pulses, rising discs, flickering arc bolts
	for pu in _pulses:
		(pu["mat"] as StandardMaterial3D).emission_energy_multiplier = \
			1.3 + 0.8 * sin(_t * 2.0 + float(pu["phase"]))
	for dc in _core_discs:
		var dh := fmod(_t * 1.6 + float(dc["phase"]), float(dc["span"]))
		(dc["node"] as Node3D).global_transform = Transform3D(
			dc["cb"] as Basis,
			_C + (dc["cup"] as Vector3) * (float(dc["base"]) + dh))
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
