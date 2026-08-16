class_name NexusStation
extends StaticBody3D
## THE NEXUS. A real station: a vertical stack of pressurised modules,
## collared together, with four solar wings out on booms and a comms
## truss on top. Nobody built a platform out here -- they bolted tubes
## end to end because that is how you build in vacuum.
##
## It sits past the shader system on the front edge of the universe,
## where there is nothing left to block a signal. Zero gravity, and the
## best antenna anybody has: a rack broadcasting from inside this thing
## is heard across the whole system at full strength.

const R_CORE := 3.6          # radius of a pressurised module
const H_MOD := 9.0           # length of one module
const N_MOD := 5             # how many are stacked
const R_COLLAR := 2.3
const H_COLLAR := 2.2
const WING_LEN := 62.0
const WING_W := 6.5

var _lights: Array = []
var _panels: Array = []
var _t: float = 0.0

func _ready() -> void:
	add_to_group("nexus")
	add_to_group("nexus_station")
	collision_layer = 1
	collision_mask = 0
	_build_spine()
	_build_wings()
	_build_truss()
	_build_dock()
	_build_sign()

# ------------------------------------------------------------- helpers

func _mi(mesh: Mesh, pos: Vector3, col: Color, emit: float = 0.12,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot
	m.material_override = Destructible.make_material(col, emit)
	add_child(m)
	return m

func _cyl(r: float, h: float, pos: Vector3, col: Color, emit := 0.12,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	return _mi(c, pos, col, emit, rot)

func _bx(size: Vector3, pos: Vector3, col: Color, emit := 0.1,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, pos, col, emit, rot)

func _col_cyl(r: float, h: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = pos
	add_child(cs)

func _col_box(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	cs.rotation_degrees = rot
	add_child(cs)

# --------------------------------------------------------------- spine

## Five pressurised modules stacked nose to tail, collared together,
## ribbed like real hull sections and lit from inside.
func _build_spine() -> void:
	var total := float(N_MOD) * H_MOD + float(N_MOD - 1) * H_COLLAR
	var y := -total * 0.5 + H_MOD * 0.5
	for i in N_MOD:
		var pale: bool = i % 2 == 0
		var hull := Color("#d8dce4") if pale else Color("#b9c2cc")
		_cyl(R_CORE, H_MOD, Vector3(0, y, 0), hull, 0.06)
		_col_cyl(R_CORE, H_MOD, Vector3(0, y, 0))
		# hull ribs: raised bands every couple of metres
		for k in 4:
			var ry := y - H_MOD * 0.5 + H_MOD * (float(k) + 0.5) / 4.0
			var rib := TorusMesh.new()
			rib.inner_radius = R_CORE - 0.02
			rib.outer_radius = R_CORE + 0.22
			rib.rings = 8
			rib.ring_segments = 20
			_mi(rib, Vector3(0, ry, 0), Color("#8f98a4"), 0.05)
		# a run of windows round the middle of each module
		for k in 8:
			var a := TAU * float(k) / 8.0
			var wpos := Vector3(cos(a) * (R_CORE + 0.06), y + 0.4, sin(a) * (R_CORE + 0.06))
			var w := _bx(Vector3(0.9, 0.5, 0.12), wpos, Color("#ffe9a8"), 2.2,
				Vector3(0, -rad_to_deg(a), 0))
			_lights.append(w)
			# a frame around the glass so it is not a glowing sticker
			_bx(Vector3(1.15, 0.75, 0.06), wpos + Vector3(cos(a), 0, sin(a)) * -0.04,
				Color("#6c7480"), 0.04, Vector3(0, -rad_to_deg(a), 0))
		# handrails down the outside: this is a place people work
		for k in 2:
			var ha := PI * float(k)
			for step in 5:
				_bx(Vector3(0.12, 0.5, 0.12),
					Vector3(cos(ha) * (R_CORE + 0.3),
						y - H_MOD * 0.5 + 1.0 + float(step) * 1.8,
						sin(ha) * (R_CORE + 0.3)), Color("#f2b13c"), 0.15)
		# the collar to the next module up
		if i < N_MOD - 1:
			var cy := y + H_MOD * 0.5 + H_COLLAR * 0.5
			_cyl(R_COLLAR, H_COLLAR, Vector3(0, cy, 0), Color("#6c7480"), 0.05)
			_col_cyl(R_COLLAR, H_COLLAR, Vector3(0, cy, 0))
			for k in 12:
				var ba := TAU * float(k) / 12.0
				_bx(Vector3(0.16, H_COLLAR * 0.9, 0.16),
					Vector3(cos(ba) * (R_COLLAR + 0.1), cy, sin(ba) * (R_COLLAR + 0.1)),
					Color("#4a515c"), 0.04)
		y += H_MOD + H_COLLAR

## Four wings on booms, at ninety degrees, ISS style: a lattice arm and
## a gold-backed cell array that tracks nothing but looks like it might.
func _build_wings() -> void:
	for i in 4:
		var a := TAU * float(i) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var deg := -rad_to_deg(a)
		# the boom: a lattice, not a stick
		var blen := 9.0
		_bx(Vector3(blen, 0.5, 0.5), dir * (R_CORE + blen * 0.5), Color("#9aa3ae"),
			0.06, Vector3(0, deg, 0))
		for k in 5:
			var t := (float(k) + 0.5) / 5.0
			var bp: Vector3 = dir * (R_CORE + blen * t)
			_bx(Vector3(0.14, 1.5, 0.14), bp + Vector3(0, 0.0, 0), Color("#6c7480"), 0.04,
				Vector3(0, deg, 35.0))
			_bx(Vector3(0.14, 1.5, 0.14), bp, Color("#6c7480"), 0.04,
				Vector3(0, deg, -35.0))
		_col_box(Vector3(blen, 0.6, 0.6), dir * (R_CORE + blen * 0.5), Vector3(0, deg, 0))
		# the rotary joint the wing hangs off
		var joint := R_CORE + blen
		_cyl(0.9, 1.4, dir * joint, Color("#4a515c"), 0.05, Vector3(0, 0, 90.0))
		# the array itself: a long panel of cells in a gold frame
		var mid: Vector3 = dir * (joint + WING_LEN * 0.5 + 0.8)
		var frame := _bx(Vector3(WING_LEN, 0.16, WING_W + 0.5), mid,
			Color("#c8a227"), 0.08, Vector3(0, deg, 0))
		_col_box(Vector3(WING_LEN, 0.3, WING_W + 0.5), mid, Vector3(0, deg, 0))
		_panels.append(frame)
		# the mast the array unfolds along
		_bx(Vector3(WING_LEN, 0.3, 0.5), mid + Vector3(0, 0.2, 0),
			Color("#8f98a4"), 0.06, Vector3(0, deg, 0))
		for cx in 22:
			for cz in 3:
				var off := Vector3(
					-WING_LEN * 0.5 + WING_LEN * (float(cx) + 0.5) / 22.0,
					0.11,
					-WING_W * 0.5 + WING_W * (float(cz) + 0.5) / 3.0)
				var world := mid + Basis(Vector3.UP, a) * Vector3(off.x, off.y, off.z)
				var cell := _bx(Vector3(WING_LEN / 22.0 - 0.18, 0.06, WING_W / 3.0 - 0.25),
					world, Color("#16214a") if (cx + cz) % 2 == 0 else Color("#1d2b5e"),
					0.14, Vector3(0, deg, 0))
				_panels.append(cell)

## The comms truss: this is the whole reason the station exists.
func _build_truss() -> void:
	var top := (float(N_MOD) * H_MOD + float(N_MOD - 1) * H_COLLAR) * 0.5
	_cyl(1.1, 6.0, Vector3(0, top + 3.0, 0), Color("#8f98a4"), 0.06)
	_col_cyl(1.2, 6.0, Vector3(0, top + 3.0, 0))
	for k in 3:
		var ty := top + 1.5 + float(k) * 2.0
		var ring := TorusMesh.new()
		ring.inner_radius = 1.2
		ring.outer_radius = 1.5
		_mi(ring, Vector3(0, ty, 0), Color("#4a515c"), 0.05)
	# three steerable dishes on gimbals. A dish is not a disc: it is a
	# curved reflector with a rim, a feed horn out at the focus on three
	# struts, ribs across the back and a yoke it swings in.
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var base := Vector3(cos(a) * 1.9, top + 4.4, sin(a) * 1.9)
		_dish(base, a, 3.2 if i == 0 else 2.3)
	# a pair of long yagi antennas, because not every band needs a dish
	for i in 2:
		var ya := PI * float(i) + PI * 0.5
		var yb := Vector3(cos(ya) * 1.4, top + 7.6, sin(ya) * 1.4)
		_cyl(0.1, 9.0, yb + Vector3(0, 4.0, 0), Color("#c8ccd4"), 0.12,
			Vector3(rad_to_deg(ya) * 0.0 + 24.0, rad_to_deg(ya), 0))
		for k in 7:
			var t := float(k) / 6.0
			var eb := yb + Vector3(cos(ya), 0, sin(ya)) * (t * 3.4) \
				+ Vector3(0, 1.2 + t * 7.4, 0)
			_bx(Vector3(0.06, 0.06, 2.6 - t * 1.4), eb, Color("#e8ecf2"), 0.16,
				Vector3(0, rad_to_deg(ya), 0))
	# the mast, and a beacon nobody can miss
	_cyl(0.16, 7.0, Vector3(0, top + 9.5, 0), Color("#c8ccd4"), 0.15)
	for k in 4:
		_bx(Vector3(1.4, 0.08, 0.08), Vector3(0, top + 7.0 + float(k) * 1.8, 0),
			Color("#c8ccd4"), 0.15, Vector3(0, float(k) * 40.0, 0))
	var beacon := SphereMesh.new()
	beacon.radius = 0.45
	beacon.height = 0.9
	_lights.append(_mi(beacon, Vector3(0, top + 13.2, 0), Color("#ff3a2a"), 3.0))

## One parabolic antenna: reflector, rim, ribbed back, feed horn on a
## three-strut tripod, and a yoke and pedestal it steers in.
func _dish(base: Vector3, aim: float, rad: float) -> void:
	var deg := rad_to_deg(aim)
	var tilt := -52.0
	# pedestal and yoke
	_cyl(0.26, 1.3, base + Vector3(0, 0.65, 0), Color("#6c7480"), 0.05)
	_cyl(0.5, 0.5, base + Vector3(0, 1.35, 0), Color("#4a515c"), 0.05)
	for sgn in [-1.0, 1.0]:
		var arm: Vector3 = Vector3(-sin(aim), 0, cos(aim)) * (rad * 0.55 * float(sgn))
		_bx(Vector3(0.16, 1.5, 0.16), base + arm + Vector3(0, 2.0, 0),
			Color("#8f98a4"), 0.05, Vector3(0, deg, sgn * 12.0))
	var hub := base + Vector3(0, 2.7, 0)
	_cyl(0.3, 0.9, hub, Color("#4a515c"), 0.05, Vector3(90.0, deg, 0))
	# the reflector: a real curved bowl, deep enough to read as one
	var bowl := SphereMesh.new()
	bowl.radius = rad
	bowl.height = rad * 1.35
	bowl.is_hemisphere = true
	bowl.radial_segments = 24
	bowl.rings = 8
	var refl := _mi(bowl, hub, Color("#e8ecf2"), 0.10, Vector3(tilt, deg, 0))
	refl.scale = Vector3(1.0, 0.62, 1.0)
	var rm: StandardMaterial3D = refl.material_override
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	# the rim
	var rim := TorusMesh.new()
	rim.inner_radius = rad - 0.12
	rim.outer_radius = rad + 0.06
	rim.rings = 8
	rim.ring_segments = 24
	_mi(rim, hub, Color("#9aa3ae"), 0.08, Vector3(tilt + 90.0, deg, 0))
	# ribs across the back of the bowl
	var back_n := Vector3(sin(aim) * cos(deg_to_rad(tilt)), -sin(deg_to_rad(tilt)),
		cos(aim) * cos(deg_to_rad(tilt))).normalized()
	for k in 6:
		_bx(Vector3(rad * 1.9, 0.09, 0.09), hub - back_n * 0.35,
			Color("#8f98a4"), 0.05,
			Vector3(tilt, deg + float(k) * 30.0, 0))
	# the feed horn, out at the focus on three struts
	var focus := hub + Vector3(sin(aim) * 0.0, 0, 0)
	var fdir := Vector3(cos(deg_to_rad(tilt + 90.0)) * sin(aim),
		sin(deg_to_rad(tilt + 90.0)), cos(deg_to_rad(tilt + 90.0)) * cos(aim)).normalized()
	var fpos := hub + fdir * (rad * 0.85)
	for k in 3:
		var sa := TAU * float(k) / 3.0
		var edge: Vector3 = hub + (Vector3(cos(sa), 0, sin(sa)) * rad * 0.8).rotated(
			Vector3(cos(aim), 0, -sin(aim)).normalized(), deg_to_rad(tilt))
		var mid2 := (edge + fpos) * 0.5
		var len2 := edge.distance_to(fpos)
		var st2 := _bx(Vector3(0.07, len2, 0.07), mid2, Color("#c8ccd4"), 0.1)
		st2.look_at_from_position(mid2, fpos, Vector3.UP)
		st2.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var horn := CylinderMesh.new()
	horn.top_radius = 0.30
	horn.bottom_radius = 0.12
	horn.height = 0.8
	var hm := _mi(horn, fpos, Color("#f2b13c"), 0.5)
	hm.look_at_from_position(fpos, hub, Vector3.UP)
	hm.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_col_cyl(rad * 0.8, 1.0, hub)

## The bottom end: utility module, tanks, and a collar to dock against.
func _build_dock() -> void:
	var bot := -(float(N_MOD) * H_MOD + float(N_MOD - 1) * H_COLLAR) * 0.5
	_cyl(R_CORE + 0.6, 1.6, Vector3(0, bot - 0.8, 0), Color("#6c7480"), 0.05)
	_col_cyl(R_CORE + 0.6, 1.6, Vector3(0, bot - 0.8, 0))
	# docking petals round the port
	for k in 8:
		var a := TAU * float(k) / 8.0
		_bx(Vector3(0.7, 0.5, 0.25),
			Vector3(cos(a) * (R_CORE * 0.55), bot - 1.7, sin(a) * (R_CORE * 0.55)),
			Color("#f2b13c"), 0.25, Vector3(0, -rad_to_deg(a), 0))
	_cyl(1.5, 0.7, Vector3(0, bot - 1.9, 0), Color("#2a3038"), 0.04)
	# propellant and water tanks strapped to the outside
	for k in 4:
		var a2 := TAU * float(k) / 4.0 + PI * 0.25
		_cyl(0.75, 3.2, Vector3(cos(a2) * (R_CORE + 0.7), bot + 2.2, sin(a2) * (R_CORE + 0.7)),
			Color("#e8ecf2"), 0.08)
		_col_cyl(0.8, 3.2, Vector3(cos(a2) * (R_CORE + 0.7), bot + 2.2,
			sin(a2) * (R_CORE + 0.7)))
	# two radiator panels, edge on, white and ribbed
	for k in 2:
		var a3 := PI * float(k) + PI * 0.5
		var rp: Vector3 = Vector3(cos(a3), 0, sin(a3)) * (R_CORE + 5.5) + Vector3(0, bot + 4.0, 0)
		_bx(Vector3(9.0, 0.12, 3.4), rp, Color("#f2f4f7"), 0.06,
			Vector3(0, -rad_to_deg(a3), 0))
		for j in 6:
			_bx(Vector3(9.0, 0.16, 0.1),
				rp + Vector3(0, 0.08, -1.5 + float(j) * 0.6), Color("#c8ccd4"), 0.05,
				Vector3(0, -rad_to_deg(a3), 0))
		_col_box(Vector3(9.0, 0.3, 3.4), rp, Vector3(0, -rad_to_deg(a3), 0))

func _build_sign() -> void:
	var top := (float(N_MOD) * H_MOD + float(N_MOD - 1) * H_COLLAR) * 0.5
	var lbl := Label3D.new()
	lbl.text = "NEXUS STATION"
	lbl.font_size = 180
	lbl.pixel_size = 0.02
	lbl.modulate = Color("#7be8ff")
	lbl.outline_size = 24
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, top + 17.0, 0)
	lbl.no_depth_test = true
	add_child(lbl)
	var sub := Label3D.new()
	sub.text = "zero g · deep-space relay · claim a frequency"
	sub.font_size = 80
	sub.pixel_size = 0.02
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.outline_size = 16
	sub.outline_modulate = Color(0, 0, 0, 0.9)
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.position = Vector3(0, top + 15.4, 0)
	add_child(sub)

func _process(delta: float) -> void:
	_t += delta
	var live := Airwaves.live_stations().size()
	for i in _lights.size():
		var l: MeshInstance3D = _lights[i]
		if not is_instance_valid(l) or not (l.material_override is StandardMaterial3D):
			continue
		var mm: StandardMaterial3D = l.material_override
		mm.emission_energy_multiplier = 1.4 + 0.9 * sin(_t * 1.3 + float(i) * 0.6) \
			+ float(live) * 0.6
