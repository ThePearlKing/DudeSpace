class_name House
extends StaticBody3D
## A house: small on the outside, a whole flat-gravity room on the
## inside (TARDIS school of architecture, same tech as the temples).
##
## The exterior sinks a real foundation into the planet so nothing
## floats on curvy ground. On the wall: 3 POWER ports and 3 ITEM ports,
## each its own labeled box with its own hitbox -- wire or funnel into
## them outside and the twin port inside the house carries it through.
## A window on the outside shows the interior in miniature (live: the
## furniture, the humans, the player). A window on the inside shows the
## actual outside world (planets, creatures, the noodle god, all of it).
##
## Kinds: small · two_story · box · basement · factory · tower.
## Any machine works inside except drills (nothing to drill up there).
## Reactors and RTGs make the place RADIOACTIVE (cancer is a mechanic).
## A generator indoors fills the room with smoke. Read a book instead.

const KINDS := ["small", "two_story", "box", "basement", "factory", "tower", "moonbase"]

## A wall port: a light-gray socket box, barely proud of the wall,
## little square panels on every face. NOT an extender -- a PORTAL:
## whatever lands in it (power or items) teleports to its twin in the
## exact home it belongs to.
class Port extends Machine:
	var twin = null
	var is_power := true
	var home_label := ""

	func _init() -> void:
		title = ""   # sockets don't introduce themselves
		box_color = Color("#c8cbd0")
		box_size = Vector3(0.52, 0.52, 0.24)
		buf_cap = 200.0
		shows_out = false

	func _ready() -> void:
		super._ready()
		# inset squares on all sides, like it was stamped, not built
		var sq := BoxMesh.new()
		sq.size = Vector3(0.24, 0.24, 0.035)
		var scol := Color("#8ecf9f") if is_power else Color("#e0a860")
		var pmat := Surfaces.portal(scol)
		for spec in [[sq, Vector3(0, 0.26, 0.11)], [sq, Vector3(0, 0.26, -0.11)]]:
			var mi0 := MeshInstance3D.new()
			mi0.mesh = spec[0]
			mi0.position = spec[1]
			mi0.material_override = pmat
			add_child(mi0)
		var sq2 := BoxMesh.new()
		sq2.size = Vector3(0.035, 0.24, 0.1)
		for sx0 in [0.25, -0.25]:
			var mi1 := MeshInstance3D.new()
			mi1.mesh = sq2
			mi1.position = Vector3(sx0, 0.26, 0)
			mi1.material_override = pmat
			add_child(mi1)
		var sq3 := BoxMesh.new()
		sq3.size = Vector3(0.24, 0.035, 0.1)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = sq3
		mi2.position = Vector3(0, 0.51, 0)
		mi2.material_override = pmat
		add_child(mi2)

	func work(delta: float) -> void:
		if twin == null or not is_instance_valid(twin):
			return
		if is_power:
			# energy steps through the wall like it isn't there
			var t: float = minf(buf, 80.0 * delta)
			if t > 0.0 and twin.buf < twin.buf_cap:
				t = minf(t, twin.buf_cap - twin.buf)
				buf -= t
				twin.buf += t
		else:
			if str(in_slot["id"]) != "" and str(twin.out_slot["id"]) == "":
				twin.out_slot = in_slot.duplicate()
				in_slot = {"id": "", "n": 0}

	func accepts(id: String) -> bool:
		return not is_power

	## No machine screen, no slots UI: it's a SOCKET. Wire into it.
	func use() -> void:
		Sfx.play("click", -22.0)

	var num: int = 0

	func info_text() -> String:
		return "%s PORTAL %d\n→ %s" % ["POWER" if is_power else "ITEM", num, home_label]
const BASE := Vector3(60000, 24000, -60000)   # pocket-interior estate
const SLOT_SPACING := 800.0

var kind: String = "small"
var slot: int = -1              # which pocket lot this house owns
var human_home: bool = false    # town house: humans only, no dudes
var owner_uid: int = 0          # claiming human's id (human homes)
var owner_name: String = ""     # claiming human's NAME (for the sign)
var roommate_name: String = ""  # a friend who moved in. rent is emotional

var _iroot: Node3D              # interior nodes live under here
var _in_ports: Array = []       # interior port machines
var _out_ports: Array = []      # exterior port machines
var _win_out_mesh: MeshInstance3D    # exterior window pane
var _win_in_mesh: MeshInstance3D     # interior window pane
var _views: Array = []          # every window viewport (paused when unseen)
var _mb_dome_out: MeshInstance3D = null   # moonbase: orange dome (exterior)
var _mb_dome_in: MeshInstance3D = null    # moonbase: dome ceiling (interior)
var _isurf: int = Surfaces.PLASTER   # this interior's wall surface
var _haz_t := 0.0
var _rad := false
var _smoke := false
var _smoke_node: GPUParticles3D
var _door_pos := Vector3.ZERO   # local door spot (exterior)
var _w := 5.0                   # exterior footprint (set at build)

## Where a polite visitor should WALK to: just outside the front door.
func door_spot() -> Vector3:
	return global_position - global_transform.basis.z * (_w * 0.5 + 1.3) \
		+ global_transform.basis.y * 0.6
var _tag: Label3D

## What this home is called, on the sign and on every portal.
func display_name() -> String:
	if human_home:
		if owner_name == "":
			return "Nobody's house"
		if roommate_name != "":
			return "%s & %s's house" % [owner_name, roommate_name]
		return "%s's house" % owner_name
	return "%s #%d" % [kind.capitalize().replace("_", "-"), slot]

func refresh_tag() -> void:
	if _tag == null:
		return
	_tag.text = display_name() + ("" if human_home else "  [F]")

static var _next_slot := 0

var room_offset: Vector3 = Vector3.ZERO   # pocket-space shift after door-merges
var links: Array = []                     # slots of houses docked to this one

func base_center() -> Vector3:
	return BASE + Vector3(float(slot) * SLOT_SPACING, 0, 0)

func room_center() -> Vector3:
	return base_center() + room_offset

func interior_spawn() -> Vector3:
	return room_center() + Vector3(0, -room_size().y * 0.5 + 1.5, room_size().z * 0.5 - 3.0)

func room_size() -> Vector3:
	match kind:
		"two_story":
			return Vector3(14, 10, 14)
		"box":
			return Vector3(12, 12, 12)
		"basement":
			return Vector3(14, 5.5, 14)
		"factory":
			return Vector3(26, 9, 26)
		"tower":
			return Vector3(16, 20, 16)
		"moonbase":
			return Vector3(26, 4.5, 10)   # hub + two wings, one sealed hull
		_:
			return Vector3(13, 5.5, 13)

func _ready() -> void:
	add_to_group("house")
	if slot == -1:
		slot = _next_slot   # -1 = unassigned; deep negatives are town lots
	_next_slot = maxi(_next_slot, slot + 1)
	_build_exterior()
	_build_interior()
	_build_ports()
	_build_windows()

# ------------------------------------------------------------- exterior

func _wallmat(c: Color, e := 0.05, surf := Surfaces.PLASTER) -> Material:
	if e > 0.5:
		return Destructible.make_material(c, e)   # glowing things stay glowing
	return Surfaces.mat(surf, c)

func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, e := 0.05) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = _wallmat(c, e)
	parent.add_child(mi)
	return mi

func _build_exterior() -> void:
	var wall := Color("#c9b8a0")
	var roofc := Color("#7a4a3a")
	match kind:
		"box":
			wall = Color("#8a8f96")
		"factory":
			wall = Color("#7a7f88")
			roofc = Color("#4a4f58")
		"tower":
			wall = Color("#3a4452")
		"two_story":
			wall = Color("#d8cbb2")
	var w := 5.0
	var h := 3.4
	match kind:
		"two_story":
			h = 6.2
		"factory":
			w = 8.0
			h = 4.5
		"tower":
			w = 4.0
			h = 11.0
		"box":
			w = 3.4
			h = 3.0
		"moonbase":
			w = 7.0
			h = 3.0
	_w = w
	# FOUNDATION: a deep plug so the house never floats on curvature
	var found := _box(self, Vector3(w + 0.6, 6.0, w + 0.6), Vector3(0, -3.0, 0),
		wall.darkened(0.35))
	found.material_override = Surfaces.stone(wall.darkened(0.35))
	# main shell (the moonbase is all domes; it skips the cottage)
	if kind != "moonbase":
		_box(self, Vector3(w, h, w), Vector3(0, h * 0.5, 0), wall)
	if kind == "tower":
		# glassy bands up the shaft
		for f in int(h / 3.0):
			_box(self, Vector3(w + 0.08, 0.9, w + 0.08),
				Vector3(0, 1.6 + float(f) * 3.0, 0), Color("#6fb6dd"), 0.6)
		_box(self, Vector3(w * 0.5, 1.4, w * 0.5), Vector3(0, h + 0.7, 0), wall.darkened(0.2))
	elif kind == "factory":
		# sawtooth roof + stack
		for i in 3:
			_box(self, Vector3(w, 1.2, w / 3.0),
				Vector3(0, h + 0.6, -w / 3.0 + float(i) * (w / 3.0)), roofc)
		var stack := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.3
		sm.bottom_radius = 0.42
		sm.height = 3.0
		stack.mesh = sm
		stack.position = Vector3(w * 0.3, h + 1.5, w * 0.3)
		stack.material_override = _wallmat(Color("#5a5f68"))
		add_child(stack)
	elif kind == "box":
		# it LOOKS like a machine because it basically is one: grilles,
		# a status stripe, corner trim. no windows. boxes don't gaze.
		var grille := Destructible.make_material(Color("#5a5f66"), 0.08)
		for gy in [0.8, 1.4, 2.0]:
			var gb := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(w * 0.7, 0.12, 0.06)
			gb.mesh = gm
			gb.position = Vector3(0, gy, w * 0.5 + 0.03)
			gb.material_override = grille
			add_child(gb)
		_box(self, Vector3(0.6, 0.25, 0.05), Vector3(w * 0.28, 2.5, -w * 0.5 - 0.03),
			Color("#7bffb0"), 1.4)
	elif kind == "moonbase":
		pass   # domes are their own roof
	elif true:
		# pitched roof (two slabs)
		for sgn in [-1.0, 1.0]:
			var slab := _box(self, Vector3(w + 0.6, 0.22, w * 0.62),
				Vector3(0, h + w * 0.15, sgn * w * 0.24), roofc)
			slab.rotation_degrees.x = sgn * 32.0   # apex UP. a roof, not a funnel
		# ridge beam capping the apex
		_box(self, Vector3(w + 0.7, 0.16, 0.3), Vector3(0, h + w * 0.31, 0),
			roofc.darkened(0.25))
	if kind == "moonbase":
		_moonbase_exterior(w)
	# per-kind exterior dressing: the part that makes it look DESIGNED
	match kind:
		"small", "basement":
			# chimney, corner posts, doorstep
			_box(self, Vector3(0.5, 1.6, 0.5), Vector3(w * 0.3, h + 0.7, w * 0.28),
				Color("#8a6a4a"))
			for cxe in [-1.0, 1.0]:
				for cze in [-1.0, 1.0]:
					_box(self, Vector3(0.22, h, 0.22),
						Vector3(cxe * w * 0.5, h * 0.5, cze * w * 0.5),
						wall.darkened(0.3))
			_box(self, Vector3(1.6, 0.18, 0.8), Vector3(0, 0.09, -w * 0.5 - 0.35),
				wall.darkened(0.4))
		"two_story":
			# floor divider band + a little balcony rail up top
			_box(self, Vector3(w + 0.1, 0.22, w + 0.1), Vector3(0, h * 0.5, 0),
				wall.darkened(0.35))
			_box(self, Vector3(1.8, 0.08, 0.5), Vector3(0, h * 0.55, -w * 0.5 - 0.25),
				wall.darkened(0.3))
			for bx in [-0.8, 0.0, 0.8]:
				_box(self, Vector3(0.06, 0.5, 0.06),
					Vector3(bx, h * 0.55 + 0.28, -w * 0.5 - 0.45), wall.darkened(0.4))
			_box(self, Vector3(1.8, 0.06, 0.06),
				Vector3(0, h * 0.55 + 0.55, -w * 0.5 - 0.45), wall.darkened(0.4))
		"tower":
			# entrance canopy + rooftop antenna cluster + base plinth
			_box(self, Vector3(2.2, 0.12, 1.2), Vector3(0, 2.5, -w * 0.5 - 0.55),
				Color("#1c2430"))
			_box(self, Vector3(w + 1.0, 0.5, w + 1.0), Vector3(0, 0.25, 0),
				wall.darkened(0.25))
			for ax in [[-0.6, 1.4], [0.4, 2.0], [0.9, 1.1]]:
				var ant := MeshInstance3D.new()
				var am2 := CylinderMesh.new()
				am2.top_radius = 0.02
				am2.bottom_radius = 0.05
				am2.height = ax[1]
				ant.mesh = am2
				ant.position = Vector3(ax[0], h + 1.4 + ax[1] * 0.5, 0.3)
				ant.material_override = _wallmat(Color("#aab0b8"), 0.4)
				add_child(ant)
			var beacon := MeshInstance3D.new()
			var bem := SphereMesh.new()
			bem.radius = 0.09
			bem.height = 0.18
			beacon.mesh = bem
			beacon.position = Vector3(0.4, h + 3.5, 0.3)
			beacon.material_override = _wallmat(Color("#ff4040"), 3.0)
			add_child(beacon)
		"factory":
			# side tank, intake pipes, hazard stripes by the door
			var tank := MeshInstance3D.new()
			var tkm := CylinderMesh.new()
			tkm.top_radius = 0.9
			tkm.bottom_radius = 0.9
			tkm.height = 2.6
			tank.mesh = tkm
			tank.position = Vector3(w * 0.5 + 1.0, 1.3, w * 0.2)
			tank.material_override = _wallmat(Color("#8a8f98"))
			add_child(tank)
			var pipe := MeshInstance3D.new()
			var ppm := CylinderMesh.new()
			ppm.top_radius = 0.16
			ppm.bottom_radius = 0.16
			ppm.height = 1.6
			pipe.mesh = ppm
			pipe.rotation_degrees.z = 90.0
			pipe.position = Vector3(w * 0.5 + 0.4, 2.2, w * 0.2)
			pipe.material_override = _wallmat(Color("#6a6f78"))
			add_child(pipe)
			for hi3 in 4:
				_box(self, Vector3(0.3, 0.3, 0.04),
					Vector3(-1.2 + float(hi3) * 0.32, 0.6, -w * 0.5 - 0.03),
					Color("#ffd166") if hi3 % 2 == 0 else Color("#1c1c24"))
	# door (dark inset) on -Z face
	_door_pos = Vector3(0, 1.1, -w * 0.5 - 0.05)
	_box(self, Vector3(1.2, 2.2, 0.12), _door_pos, Color("#3a2c20"), 0.02)
	_tag = Label3D.new()
	_tag.font_size = 30
	_tag.no_depth_test = true
	_tag.render_priority = 8
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, h + 1.6, 0)
	_tag.modulate = Color(1, 1, 1, 0.75)
	_tag.outline_size = 5
	add_child(_tag)
	refresh_tag()
	# collider for the shell (also the interact hitbox)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(w, h, w)
	col.shape = cs
	col.position = Vector3(0, h * 0.5, 0)
	add_child(col)

## Moonbase shell: gray domes, orange dome windows, an airlock snout.
func _moonbase_exterior(w: float) -> void:
	var gray := Surfaces.metal(Color("#9aa0a8"))
	# THE dome: the whole hab is one big orange dome, like an actual
	# moonbase. it doubles as the screen showing the inside.
	var main_dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = w * 0.62
	dm.height = w * 0.62
	dm.is_hemisphere = true
	main_dome.mesh = dm
	main_dome.position = Vector3(0, 0.1, 0)
	var oplace := StandardMaterial3D.new()
	oplace.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	oplace.emission_enabled = true
	oplace.emission = Color(1.0, 0.45, 0.1)
	oplace.emission_energy_multiplier = 0.5
	main_dome.material_override = oplace
	add_child(main_dome)
	_mb_dome_out = main_dome
	var ring := MeshInstance3D.new()
	var rm2 := CylinderMesh.new()
	rm2.top_radius = w * 0.64
	rm2.bottom_radius = w * 0.66
	rm2.height = 0.5
	ring.mesh = rm2
	ring.position = Vector3(0, 0.25, 0)
	ring.material_override = gray
	add_child(ring)
	for sd in [[-w * 0.55, w * 0.34], [w * 0.55, 0.3 * w]]:
		var d2 := MeshInstance3D.new()
		var dm2 := SphereMesh.new()
		dm2.radius = sd[1]
		dm2.height = sd[1]
		dm2.is_hemisphere = true
		d2.mesh = dm2
		d2.position = Vector3(sd[0], 0.1, 0.2)
		d2.material_override = gray
		add_child(d2)
	# the AIRLOCK: cylindrical snout with a round hatch, front and center
	var snout := MeshInstance3D.new()
	var sn := CylinderMesh.new()
	sn.top_radius = 1.0
	sn.bottom_radius = 1.0
	sn.height = 1.6
	snout.mesh = sn
	snout.rotation_degrees.x = 90.0
	snout.position = Vector3(0, 1.1, -w * 0.5 - 0.6)
	snout.material_override = Surfaces.metal(Color("#7a8088"))
	add_child(snout)
	var hatch := MeshInstance3D.new()
	var hm2 := CylinderMesh.new()
	hm2.top_radius = 0.7
	hm2.bottom_radius = 0.7
	hm2.height = 0.12
	hatch.mesh = hm2
	hatch.rotation_degrees.x = 90.0
	hatch.position = Vector3(0, 1.1, -w * 0.5 - 1.45)
	hatch.material_override = Surfaces.portal(Color("#ffa040"))
	add_child(hatch)

# ------------------------------------------------------------- interior

func _iroom(center: Vector3, size: Vector3, c: Color, e := 0.12, skip: Array = []) -> void:
	var half := size * 0.5
	var wi := -1
	for wspec in [
		[Vector3(size.x, 1, size.z), Vector3(0, -half.y, 0)],
		[Vector3(size.x, 1, size.z), Vector3(0, half.y, 0)],
		[Vector3(1, size.y, size.z), Vector3(-half.x, 0, 0)],
		[Vector3(1, size.y, size.z), Vector3(half.x, 0, 0)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, -half.z)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, half.z)],
	]:
		wi += 1
		if wi in skip:
			continue
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = wspec[0]
		mi.mesh = m
		mi.material_override = _wallmat(c, e, _isurf)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = wspec[0]
		col.shape = bs
		body.add_child(col)
		_iroot.add_child(body)
		body.global_position = center + wspec[1]
	# big flat walls are boring: baseboards, crown molding, and panel
	# seams give them real detail (geometry, not grime)
	var trim := Surfaces.wood(c.darkened(0.35)) if _isurf == Surfaces.PLASTER \
		else Surfaces.metal(c.darkened(0.3))
	for ring in [[-half.y + 0.14, 0.24], [half.y - 0.14, 0.18]]:
		for wallside in 4:
			var bar := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			var along_x := wallside < 2
			bm2.size = Vector3(size.x - 1.0, ring[1], 0.1) if along_x \
				else Vector3(0.1, ring[1], size.z - 1.0)
			bar.mesh = bm2
			bar.material_override = trim
			_iroot.add_child(bar)
			var off := (half.z - 0.55) if along_x else (half.x - 0.55)
			var sgn2 := -1.0 if wallside % 2 == 0 else 1.0
			bar.global_position = center + (Vector3(0, ring[0], sgn2 * off) \
				if along_x else Vector3(sgn2 * off, ring[0], 0))
	# vertical seams every few meters on the long walls
	var nseam := int(size.x / 3.0)
	for si in range(1, nseam):
		for zs in [-1.0, 1.0]:
			var seam := MeshInstance3D.new()
			var smz := BoxMesh.new()
			smz.size = Vector3(0.07, size.y - 0.6, 0.06)
			seam.mesh = smz
			seam.material_override = trim
			_iroot.add_child(seam)
			seam.global_position = center + Vector3(-half.x + float(si) * 3.0,
				0, zs * (half.z - 0.53))
	var light := OmniLight3D.new()
	light.light_energy = 1.4
	light.omni_range = maxf(size.x, size.z) * 1.3
	_iroot.add_child(light)
	light.global_position = center + Vector3(0, half.y - 1.0, 0)

func _build_interior() -> void:
	_iroot = Node3D.new()
	get_tree().current_scene.add_child.call_deferred(_iroot)
	await get_tree().process_frame
	var c := room_center()
	var sz := room_size()
	var warm := Color("#d8c8ae") if not (kind in ["factory", "box", "tower"]) else Color("#9aa0a8")
	_isurf = Surfaces.METAL if kind in ["factory", "box", "tower", "moonbase"] else Surfaces.PLASTER
	# the basement supplies its own floor (the one with the HOLE in it)
	_iroom(c, sz, warm, 0.12,
		[0] if kind == "basement" else ([1] if kind == "moonbase" else []))
	var fy := c.y - sz.y * 0.5
	# every home: a visible ceiling light fixture and a wall trim band
	# (moonbase hub is open dome overhead -- its lights hang in the wings)
	if kind == "moonbase":
		for lx in [-9.0, 9.0]:
			_deco(c + Vector3(lx, sz.y * 0.5 - 0.55, 0), Vector3(1.2, 0.12, 1.2),
				Color("#fff2c8"), 1.8)
	else:
		_deco(c + Vector3(0, sz.y * 0.5 - 0.35, 0), Vector3(1.4, 0.12, 1.4),
			Color("#fff2c8"), 1.8)
	_deco(c + Vector3(0, fy - c.y + 1.1, sz.z * 0.5 - 0.45),
		Vector3(sz.x - 0.8, 0.14, 0.06), warm.darkened(0.3))
	match kind:
		"two_story":
			# upper slab + a REAL staircase: steps, stringer, landing
			# that actually meets the slab, railing on the open edge
			_solid(c + Vector3(-sz.x * 0.15, 0.0, 0),
				Vector3(sz.x * 0.7, 0.4, sz.z - 1.0), warm.darkened(0.15))
			_stairs(c + Vector3(sz.x * 0.5 - 1.4, fy - c.y, sz.z * 0.5 - 1.6),
				Vector3(2.2, 0, -0.95), 10, sz.y * 0.5, warm.darkened(0.25))
			# landing bridge: from the stair top ONTO the slab edge
			_solid(c + Vector3(sz.x * 0.35 - 0.6, 0.0, sz.z * 0.5 - 1.6 - 0.95 * 9.0 - 1.1),
				Vector3(sz.x * 0.32, 0.4, 2.6), warm.darkened(0.15))
			# railing along the slab's open edge -- STOPPING before the
			# landing so the stair top stays walkable
			for rz in 4:
				_deco(c + Vector3(sz.x * 0.2, 0.8, 0.2 + float(rz) * 1.6),
					Vector3(0.08, 1.2, 0.08), warm.darkened(0.4))
			_deco(c + Vector3(sz.x * 0.2, 1.4, 2.6), Vector3(0.1, 0.08, 5.2),
				warm.darkened(0.4))
			# fireplace on the ground floor
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
			_wood_floor(Vector3(c.x, fy + 0.2, c.z), Vector2(sz.x - 1.2, sz.z - 1.2))
			_wood_floor(Vector3(c.x - sz.x * 0.15, c.y + 0.21, c.z),
				Vector2(sz.x * 0.7 - 0.2, sz.z - 1.2))
			_counter(c + Vector3(-sz.x * 0.3, 0.26, -sz.z * 0.35), 2.4)
			_rug(Vector3(c.x - 1.5, fy + 0.28, c.z + 1.5), Vector2(3.2, 2.4), Color("#5a8a5a"))
			_plant(c + Vector3(-sz.x * 0.5 + 1.0, fy - c.y + 0.26, sz.z * 0.5 - 1.0))
		"basement":
			# the cellar below (the upper room is already built,
			# floorless, by the generic pass above)
			_isurf = Surfaces.STONE
			_iroom(c + Vector3(0, -sz.y, 0), sz, Color("#8a8272"), 0.06, [1])  # cellar, no ceiling
			_isurf = Surfaces.PLASTER
			var hole := Rect2(2.5, 1.0, 3.0, 4.0)                # x0,z0,w,h
			_hole_floor(Vector3(c.x, fy, c.z), Vector2(sz.x, sz.z), hole,
				warm.darkened(0.15))
			_wood_floor(Vector3(c.x - 2.5, fy + 0.2, c.z), Vector2(sz.x - 6.0, sz.z - 1.0))
			# ONE straight flight, REVERSED: you step into the hole at its
			# far edge and walk down toward the middle of the cellar --
			# full drop, never meets a wall, no orphan landings
			var cellar_floor := -sz.y * 1.5 + 0.3
			_stairs(c + Vector3(4.0, cellar_floor, -1.3),
				Vector3(0, 0, 0.5), 13, sz.y, Color("#6a6255"), 0.12, -0.3)
			# railing around the open hole so nobody just falls in
			_deco(c + Vector3(2.35, fy - c.y + 0.8, 3.0), Vector3(0.08, 1.1, 4.2),
				warm.darkened(0.4))
			_deco(c + Vector3(4.0, fy - c.y + 0.8, 0.85), Vector3(3.4, 1.1, 0.08),
				warm.darkened(0.4))
			# cellar dressing along the WALLS only -- nothing parked in the
			# middle of the room to trip over. The rug has no collision, so
			# placing things on top of it works fine.
			_deco(c + Vector3(0, -sz.y - 0.6 + sz.y * 0.5, 0), Vector3(0.5, 0.1, 0.5),
				Color("#fff2c8"), 1.6)
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
			_counter(c + Vector3(-sz.x * 0.5 + 1.2, fy - c.y + 0.2, -sz.z * 0.35), 3.0)
			_plant(c + Vector3(sz.x * 0.5 - 1.0, fy - c.y + 0.2, sz.z * 0.5 - 1.0))
			_rug(Vector3(c.x - 2.0, fy + 0.28, c.z), Vector2(3.4, 2.4), Color("#8a3a3a"))
			# one barrel, IN the corner, bothering nobody
			_deco(c + Vector3(-sz.x * 0.5 + 0.9, -sz.y * 1.5 + 1.0, -sz.z * 0.5 + 0.9),
				Vector3(0.7, 1.4, 0.7), Color("#4a4438"))
		"tower":
			# floors every 5 units. slabs leave a stair bay along -X;
			# a switchback staircase LIVES in that bay and actually
			# reaches each slab. railings included. elevator energy.
			var nf := int(sz.y / 5.0)
			for f in range(1, nf):
				_solid(c + Vector3(1.5, -sz.y * 0.5 + float(f) * 5.0, 0),
					Vector3(sz.x - 5.0, 0.4, sz.z - 1.0), Color("#7a8090"))
				# glowing floor-number strip at each landing
				_deco(c + Vector3(-sz.x * 0.5 + 0.6, -sz.y * 0.5 + float(f) * 5.0 + 1.6,
					-sz.z * 0.35), Vector3(0.06, 0.5, 0.5), Color("#7bffb0"), 1.2)
			for f2 in range(0, nf - 1):
				var base_y := fy - c.y + float(f2) * 5.0
				# straight run up the -X bay, landing at the slab edge
				_stairs(c + Vector3(-sz.x * 0.5 + 1.2, base_y, sz.z * 0.5 - 1.4),
					Vector3(2.0, 0, -0.72), 10, 5.0, Color("#5a6070"))
				# top landing: meets the last step AND the slab edge
				_solid(c + Vector3(-sz.x * 0.5 + 2.6, base_y + 5.0,
					sz.z * 0.5 - 1.4 - 0.72 * 9.0 - 1.1),
					Vector3(4.4, 0.4, 2.4), Color("#7a8090"))
			# tiled checker lobby floor, corporate as anything
			for tz in range(0, int(sz.z - 3.0)):
				for tx in range(0, int(sz.x - 3.0)):
					if (tx + tz) % 2 == 0:
						continue
					_deco(c + Vector3(-sz.x * 0.5 + 2.0 + float(tx),
						fy - c.y + 0.035, -sz.z * 0.5 + 2.0 + float(tz)),
						Vector3(0.96, 0.05, 0.96), Color("#3c4452"))
			# lobby carpet strip + a plant per landing (corporate law)
			_deco(c + Vector3(1.5, fy - c.y + 0.22, sz.z * 0.5 - 3.0),
				Vector3(4.0, 0.05, 2.2), Color("#7a2a2a"))
			for f3 in range(1, nf):
				_plant(c + Vector3(sz.x * 0.5 - 1.2,
					-sz.y * 0.5 + float(f3) * 5.0 + 0.26, sz.z * 0.5 - 1.2))
			# core columns
			for cxz in [[-1.5, -1.5], [1.5, 1.5], [-1.5, 1.5], [1.5, -1.5]]:
				_deco(c + Vector3(cxz[0] * 1.6, 0, cxz[1] * 1.6),
					Vector3(0.5, sz.y - 0.6, 0.5), Color("#5a6070"))
		"factory":
			# work lines, gantry, ceiling pipes, support columns, catwalk
			_solid(c + Vector3(0, -sz.y * 0.5 + 0.06, 0),
				Vector3(sz.x - 4.0, 0.05, 2.0), Color("#c9a83a"), 0.3)
			_solid(c + Vector3(0, sz.y * 0.5 - 1.2, 0),
				Vector3(sz.x - 2.0, 0.5, 0.5), Color("#5a5f68"))
			for px in [-0.3, 0.3]:
				_deco(c + Vector3(sz.x * px, sz.y * 0.5 - 0.6, 0),
					Vector3(0.35, 0.35, sz.z - 2.0), Color("#8a5a2a"))
			for cx2 in [-0.35, 0.35]:
				for cz2 in [-0.35, 0.35]:
					_deco(c + Vector3(sz.x * cx2, 0, sz.z * cz2),
						Vector3(0.6, sz.y - 0.6, 0.6), Color("#4a4f58"))
			# CATWALK NETWORK: raised grid, rails, two access stairs --
			# a factory without catwalks is just a warehouse
			var cw := Color("#6a6f78")
			var cwy := 2.6
			_solid(c + Vector3(0, cwy, -sz.z * 0.5 + 1.2),
				Vector3(sz.x - 4.0, 0.25, 1.8), cw)
			_solid(c + Vector3(0, cwy, sz.z * 0.5 - 1.2),
				Vector3(sz.x - 4.0, 0.25, 1.8), cw)
			_solid(c + Vector3(-sz.x * 0.5 + 1.2, cwy, 0),
				Vector3(1.8, 0.25, sz.z - 4.0), cw)
			_solid(c + Vector3(0, cwy, 0), Vector3(1.8, 0.25, sz.z - 4.0), cw)
			for rz2 in [-sz.z * 0.5 + 0.4, sz.z * 0.5 - 0.4]:
				_deco(c + Vector3(0, cwy + 0.6, rz2),
					Vector3(sz.x - 4.0, 0.07, 0.07), cw.darkened(0.2))
			_stairs(c + Vector3(sz.x * 0.35, -sz.y * 0.5 + 0.3, -sz.z * 0.5 + 2.6),
				Vector3(0, 0, 0.6), 6, cwy + sz.y * 0.5 - 0.3, cw.darkened(0.15))
			_stairs(c + Vector3(-sz.x * 0.35, -sz.y * 0.5 + 0.3, sz.z * 0.5 - 2.6),
				Vector3(0, 0, -0.6), 6, cwy + sz.y * 0.5 - 0.3, cw.darkened(0.15))
		"moonbase":
			# one sealed hull, divided into hub + two wings by walls
			# with real doorways: hallway energy, zero leaks to space
			var mgray := Color("#9aa0a8")
			for dx in [-5.0, 5.0]:
				# piers either side of a centered doorway + header
				for zs3 in [-1.0, 1.0]:
					_solid(c + Vector3(dx, 0, zs3 * (sz.z * 0.25 + 0.6)),
						Vector3(0.5, sz.y - 0.2, sz.z * 0.5 - 1.2), mgray)
				_solid(c + Vector3(dx, sz.y * 0.5 - 0.7, 0),
					Vector3(0.5, 1.2, 2.6), mgray)
			# corridor light strips over each doorway
			for dx2 in [-5.0, 5.0]:
				_deco(c + Vector3(dx2, sz.y * 0.5 - 1.35, 0),
					Vector3(0.6, 0.06, 2.2), Color("#fff2c8"), 1.4)
			# the ROOF IS A DOME: the generic ceiling is skipped for the
			# moonbase; flat panels cover only the wings, and the hub gets
			# a big dome you can actually SEE from inside (cull off),
			# showing the sky like the window it is
			for wx in [-1.0, 1.0]:
				_solid(c + Vector3(wx * (5.0 + (sz.x * 0.5 - 5.0) * 0.5),
					sz.y * 0.5, 0), Vector3(sz.x * 0.5 - 5.0, 0.4, sz.z), mgray)
			var odome := MeshInstance3D.new()
			var odm := SphereMesh.new()
			odm.radius = 5.6
			odm.height = 4.5
			odm.is_hemisphere = true
			var omat2 := StandardMaterial3D.new()
			omat2.albedo_color = Color(1.0, 0.55, 0.15, 0.6)
			omat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			omat2.emission_enabled = true
			omat2.emission = Color(1.0, 0.5, 0.12)
			omat2.emission_energy_multiplier = 0.8
			omat2.cull_mode = BaseMaterial3D.CULL_DISABLED
			odome.mesh = odm
			odome.material_override = omat2
			odome.extra_cull_margin = 8.0
			_iroot.add_child(odome)
			odome.global_position = c + Vector3(0, sz.y * 0.5 - 0.1, 0)
			_mb_dome_in = odome
			# the dome is SOLID: a convex shell collider so nobody flies
			# out through the glass into the pocket void
			var pts := PackedVector3Array()
			for ring in 4:
				var vy := float(ring) / 3.0
				var rr := 5.6 * sqrt(1.0 - vy * vy)
				for k in 12:
					var aa := TAU * float(k) / 12.0
					pts.append(Vector3(cos(aa) * rr, vy * 4.5, sin(aa) * rr))
			pts.append(Vector3(0, 4.5, 0))
			var dbody := StaticBody3D.new()
			var dcol := CollisionShape3D.new()
			var cvx := ConvexPolygonShape3D.new()
			cvx.points = pts
			dcol.shape = cvx
			dbody.add_child(dcol)
			_iroot.add_child(dbody)
			dbody.global_position = odome.global_position
			# wing dressing: bunk west, console east, floor decals
			_deco(c + Vector3(-9.5, fy - c.y + 0.55, 2.5),
				Vector3(1.1, 0.5, 2.2), Color("#5a7aa0"))
			_deco(c + Vector3(9.5, fy - c.y + 0.5, -2.5),
				Vector3(2.2, 1.0, 0.7), Color("#2a2f38"))
			_deco(c + Vector3(9.5, fy - c.y + 1.15, -2.5),
				Vector3(1.8, 0.5, 0.1), Color("#7bffb0"), 1.3)
			_deco(c + Vector3(0, fy - c.y + 0.04, 0), Vector3(5.5, 0.05, 5.5),
				Color("#7a8088"))
			_deco(c + Vector3(0, fy - c.y + 0.08, 0), Vector3(1.5, 0.05, 1.5),
				Color("#ffa040"), 0.8)
		"box":
			pass   # a blank canvas. bring your own everything.
		_:
			# small house: wood floor, kitchen corner, plants, a hearth
			_wood_floor(Vector3(c.x, fy + 0.2, c.z), Vector2(sz.x - 1.2, sz.z - 1.2))
			_counter(c + Vector3(-sz.x * 0.5 + 1.2, fy - c.y + 0.26, -sz.z * 0.35), 3.2)
			_rug(Vector3(c.x, fy + 0.28, c.z + 1.0), Vector2(3.6, 2.6), Color("#3a5a8a"))
			_plant(c + Vector3(sz.x * 0.5 - 1.0, fy - c.y + 0.26, sz.z * 0.5 - 1.0))
			_plant(c + Vector3(sz.x * 0.5 - 1.0, fy - c.y + 0.26, -sz.z * 0.5 + 1.0))
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
	# EXIT door pad, back wall
	var out := Gate.new().configure({
		"action": "house_exit", "label": "LEAVE HOUSE",
		"color": Color("#ffe066")})
	_iroot.add_child(out)
	out.global_position = c + Vector3(0, fy - c.y + 1.0, sz.z * 0.5 - 1.4)
	out.set_meta("house", self)
	if not human_home:
		# the red button: owner-only, press twice, house becomes a kit
		var dem := Gate.new().configure({
			"action": "house_demolish", "label": "DEMOLISH",
			"color": Color("#a82020"), "wall_button": true})
		_iroot.add_child(dem)
		dem.global_position = c + Vector3(-sz.x * 0.5 + 1.6, fy - c.y,
			sz.z * 0.5 - 0.58)
		dem.set_meta("house", self)

## A wood floor: warm overlay plus darker plank seams. Rooms stop
## looking like the inside of a shipping box.
func _wood_floor(center: Vector3, size: Vector2) -> void:
	var fl := MeshInstance3D.new()
	var fm2 := BoxMesh.new()
	fm2.size = Vector3(size.x, 0.06, size.y)
	fl.mesh = fm2
	fl.material_override = Surfaces.wood(Color("#a07848"))
	_iroot.add_child(fl)
	fl.global_position = center + Vector3(0, 0.03, 0)
	var n := int(size.y / 1.2)
	for i in n:
		_deco(center + Vector3(0, 0.07, -size.y * 0.5 + 0.6 + float(i) * 1.2),
			Vector3(size.x, 0.012, 0.05), Color("#7a5830"))

## A floor slab with a rectangular stairwell HOLE: four strips.
## hole = (x0, z0, x1, z1) relative to center.
func _hole_floor(center: Vector3, size: Vector2, hole: Rect2, c: Color) -> void:
	var hx0 := hole.position.x
	var hz0 := hole.position.y
	var hx1 := hole.end.x
	var hz1 := hole.end.y
	var half := size * 0.5
	if hx0 > -half.x:
		_solid(center + Vector3((hx0 - half.x) * 0.5, 0, 0),
			Vector3(hx0 + half.x, 0.4, size.y), c)
	if hx1 < half.x:
		_solid(center + Vector3((hx1 + half.x) * 0.5, 0, 0),
			Vector3(half.x - hx1, 0.4, size.y), c)
	if hz0 > -half.y:
		_solid(center + Vector3((hx0 + hx1) * 0.5, 0, (hz0 - half.y) * 0.5),
			Vector3(hx1 - hx0, 0.4, hz0 + half.y), c)
	if hz1 < half.y:
		_solid(center + Vector3((hx0 + hx1) * 0.5, 0, (hz1 + half.y) * 0.5),
			Vector3(hx1 - hx0, 0.4, half.y - hz1), c)

## A soft rug: fabric, warm, zero collision. Room glue.
func _rug(gpos: Vector3, size: Vector2, col: Color) -> void:
	var r := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(size.x, 0.04, size.y)
	r.mesh = m
	r.material_override = Surfaces.fabric(col)
	_iroot.add_child(r)
	r.global_position = gpos + Vector3(0, 0.06, 0)

## A potted plant. Every good room has one. It knows things.
func _plant(gpos: Vector3) -> void:
	_deco(gpos, Vector3(0.34, 0.4, 0.34), Color("#8a5a34"))
	var bush := MeshInstance3D.new()
	var bmz := SphereMesh.new()
	bmz.radius = 0.32
	bmz.height = 0.55
	bush.mesh = bmz
	bush.material_override = _wallmat(Color("#3f7d3f"), 0.08)
	_iroot.add_child(bush)
	bush.global_position = gpos + Vector3(0, 0.5, 0)

## A kitchen counter run: cabinets, top, a sink block.
func _counter(gpos: Vector3, length: float) -> void:
	_deco(gpos + Vector3(0, 0.45, 0), Vector3(length, 0.9, 0.7), Color("#6a5434"))
	_deco(gpos + Vector3(0, 0.94, 0), Vector3(length + 0.1, 0.08, 0.8),
		Color("#c9c4b8"))
	_deco(gpos + Vector3(length * 0.25, 1.0, 0), Vector3(0.5, 0.1, 0.4),
		Color("#8a8f98"))

## A real staircase: N steps climbing `rise` along `step_vec` (x,z per
## step), each with collision. The last step tops out AT the rise.
func _stairs(base: Vector3, step_vec: Vector3, steps: int, rise: float,
		col: Color, ramp_lift := 0.12, overhang := 0.2) -> void:
	for st in steps:
		var t := float(st + 1) / float(steps)
		_solid(base + Vector3(0, rise * t - 0.2, step_vec.z * float(st)),
			Vector3(2.2, 0.42, absf(step_vec.z) + 0.35), col)
	# the part that makes them a SLOPE: an invisible ramp lying over the
	# steps, so walking up is walking, not parkour. ramp_lift/overhang
	# tune how proud it sits -- a ramp that outgrows its stairwell pokes
	# an invisible lip through the floor above.
	var run := step_vec.z * float(steps - 1)
	var length := sqrt(run * run + rise * rise) + overhang
	var ramp := StaticBody3D.new()
	var rcol := CollisionShape3D.new()
	var rbs := BoxShape3D.new()
	rbs.size = Vector3(2.2, 0.12, length)
	rcol.shape = rbs
	ramp.add_child(rcol)
	_iroot.add_child(ramp)
	ramp.global_position = base + Vector3(0, rise * 0.5 + ramp_lift, run * 0.5)
	ramp.rotation.x = atan2(rise, -run) if run < 0.0 else -atan2(rise, run)

## Cosmetic block (no collision): trim, beams, railings, clutter.
func _deco(gpos: Vector3, size: Vector3, c: Color, e := 0.08) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _wallmat(c, e)
	_iroot.add_child(mi)
	mi.global_position = gpos

## A fireplace: stone surround, dark hearth, ember glow. Cozy tech.
func _fireplace(gpos: Vector3) -> void:
	_deco(gpos, Vector3(0.6, 1.8, 1.6), Color("#8a8272"))
	_deco(gpos + Vector3(0.12, -0.35, 0), Vector3(0.5, 0.9, 1.0), Color("#181410"))
	_deco(gpos + Vector3(0.2, -0.6, 0), Vector3(0.3, 0.25, 0.7), Color("#ff7a2a"), 2.2)

func _solid(gpos: Vector3, size: Vector3, c: Color, e := 0.08) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _wallmat(c, e)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	_iroot.add_child(body)
	body.global_position = gpos

# --------------------------------------------------------------- ports

## 3 power + 3 item ports: each an Extender machine OUTSIDE, hard-wired
## to a twin INSIDE. Wire/funnel to the box on the wall; the house wall
## stops mattering. Each box has its own body, its own hitbox.
func _build_ports() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var c := room_center()
	var sz := room_size()
	for i in 6:
		var is_power := i < 3
		var outp := Port.new()
		outp.is_power = is_power
		outp.home_label = display_name()
		outp.set_meta("house_port", true)
		get_tree().current_scene.add_child(outp)
		# tidy: power 1-2-3 stacked on the LEFT wall, item 1-2-3 on the
		# RIGHT wall. no interleaving, no guessing.
		var side := -1.0 if is_power else 1.0
		var w := 5.0 if kind != "factory" else 8.0
		if kind == "tower":
			w = 4.0
		if kind == "box":
			w = 3.4
		if kind == "moonbase":
			w = 7.0
		outp.global_transform = global_transform
		if kind == "moonbase":
			# the big orange dome (r = w*0.62) swallowed the old wall
			# positions -- mount the trios on the FRONT of each little
			# metal dome instead, stacked and reachable
			outp.global_position = global_position \
				+ global_transform.basis.x * (side * w * 0.55) \
				+ global_transform.basis.z * (0.34 * w + 0.3) \
				+ global_transform.basis.y * (0.7 + float(i % 3) * 0.85)
			outp.rotate_object_local(Vector3.UP, PI)
		else:
			outp.global_position = global_position \
				+ global_transform.basis.x * (side * (w * 0.5 + 0.08)) \
				+ global_transform.basis.y * (0.7 + float(i % 3) * 0.85)
			outp.rotate_object_local(Vector3.UP, PI * 0.5 * side)
		_port_number(outp, i % 3 + 1)
		_out_ports.append(outp)
		var inp := Port.new()
		inp.is_power = is_power
		inp.home_label = display_name() + " (inside)"
		inp.set_meta("house_port", true)
		get_tree().current_scene.add_child(inp)
		# inside mirrors it: power trio left of the back wall, item trio
		# right, numbered to match their outside twins
		inp.global_position = c + Vector3(
			(-sz.x * 0.25 if is_power else sz.x * 0.25) \
				+ float(i % 3 - 1) * 1.2,
			-sz.y * 0.5 + 1.0, -sz.z * 0.5 + 2.85)   # 2m clear of the wall
		_port_number(inp, i % 3 + 1)
		_in_ports.append(inp)
		# the pairing: outside pours into inside. no wires, no visuals,
		# no lines to the far side of the solar system
		outp.twin = inp

# ------------------------------------------------------------- windows

func _build_windows() -> void:
	await get_tree().process_frame
	var c := room_center()
	var sz := room_size()
	var w := 5.0 if kind != "factory" else 8.0
	if kind == "tower":
		w = 4.0
	if kind == "box":
		w = 3.4
	if kind == "moonbase":
		# the DOME pair: outside dome shows the hub (orange-tinted,
		# warped over the hemisphere); inside dome shows the sky the
		# same warped way. windows, but round.
		var ev := _mk_view(Vector2i(256, 200))
		var iv := _mk_view(Vector2i(320, 240))
		var ecam: Camera3D = ev[1]
		ecam.global_position = c + Vector3(0, sz.y * 0.5 - 0.9, 0.01)
		ecam.look_at(c + Vector3(0, -sz.y * 0.5, 0), Vector3.FORWARD)
		var icam: Camera3D = iv[1]
		icam.fov = 95.0   # wide: the dome shows a lot of sky
		var upv: Vector3 = global_transform.basis.y
		icam.global_position = global_position + upv * 5.5
		icam.look_at(icam.global_position + upv, -global_transform.basis.z)
		if _mb_dome_out:
			var em := StandardMaterial3D.new()
			em.albedo_texture = ev[0].get_texture()
			em.albedo_color = Color(1.0, 0.62, 0.25, 0.62)   # SEE-THROUGH orange
			em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.uv1_triplanar = true
			var orad: float = 5.0
			if _mb_dome_out.mesh is SphereMesh:
				orad = (_mb_dome_out.mesh as SphereMesh).radius
			em.uv1_scale = Vector3.ONE * (1.0 / (orad * 2.0))
			em.uv1_offset = Vector3.ONE * 0.5
			_mb_dome_out.material_override = em
		if _mb_dome_in:
			var im := StandardMaterial3D.new()
			im.albedo_texture = iv[0].get_texture()
			im.albedo_color = Color(1.0, 0.62, 0.25, 0.85)
			im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			im.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible from BELOW
			# TRIPLANAR: project the sky image straight down onto the dome
			# instead of smearing it around the polar UVs (the warp)
			im.uv1_triplanar = true
			im.uv1_scale = Vector3.ONE * (1.0 / 11.2)
			im.uv1_offset = Vector3.ONE * 0.5
			_mb_dome_in.material_override = im
		return
	if kind == "box":
		# the skylight pair: roof glass <-> ceiling glass, one camera
		# at each end, looking through like the hole was real
		_win_pair(Vector3(0, 3.05, 0), Vector3(0, -90, 0),
			Vector3(c.x, c.y + sz.y * 0.5 - 0.62, c.z), Vector3(0, 90, 0),
			global_transform.basis.y,            # outward = up
			Vector3.DOWN,                        # into the room = down
			Vector2(w - 0.5, w - 0.5), Vector2(sz.x - 1.6, sz.z - 1.6), false)
		return
	var floors := 1
	match kind:
		"two_story": floors = 2
		"tower": floors = 3
	var ifloors := floors if kind != "tower" else mini(int(sz.y / 5.0), floors)
	for f in mini(floors, ifloors):
		var wy := 1.7 + float(f) * (3.0 if kind != "two_story" else 2.9)
		var fy2 := c.y - sz.y * 0.5 + 1.6 + float(f) * 5.0
		if kind == "two_story":
			fy2 = c.y - sz.y * 0.5 + 1.6 + float(f) * (sz.y * 0.5)
		var fwd: Vector3 = -global_transform.basis.z   # house front normal
		var back: Vector3 = global_transform.basis.z
		# two small front windows flanking the door, exact twins inside
		var zoff := 0.02 if kind != "tower" else -0.12   # clear of the bands
		for fxs in [-1.0, 1.0]:
			_win_pair(Vector3(fxs * w * 0.28, wy, -w * 0.5 + zoff),
				Vector3.ZERO,
				Vector3(c.x + fxs * sz.x * 0.28, fy2 + 1.4, c.z - (sz.z * 0.5 - 0.62)),
				Vector3(0, 180, 0),
				fwd, Vector3(0, 0, 1),
				Vector2(1.1, 1.0), Vector2(1.8, 1.4))
		# one wide back window
		_win_pair(Vector3(-w * 0.18, wy, w * 0.5 - zoff), Vector3(0, 180, 0),
			Vector3(c.x - sz.x * 0.18, fy2 + 0.5, c.z + (sz.z * 0.5 - 0.62)),
			Vector3.ZERO,
			back, Vector3(0, 0, -1),
			Vector2(2.0, 1.5), Vector2(2.8, 1.8))

func _mk_view(px: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = px
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	vp.world_3d = get_viewport().world_3d
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 78.0
	_views.append(vp)
	return [vp, cam]

## A matched window PAIR, portal-style: the outside pane renders from a
## camera standing AT the inside window looking into the room; the
## inside pane renders from a camera AT the outside window looking out.
## Same spot, same axis, both directions. Like glass. Imagine.
func _win_pair(ext_local: Vector3, ext_rot_deg: Vector3,
		int_gpos: Vector3, int_rot_deg: Vector3,
		out_dir: Vector3, in_dir: Vector3,
		ext_size: Vector2, int_size: Vector2, cavity := true) -> void:
	var ev := _mk_view(Vector2i(224, 170))   # feeds the EXTERIOR pane
	var iv := _mk_view(Vector2i(320, 240))   # feeds the INTERIOR pane
	# exterior pane's camera: at the interior window, looking into the room
	var ecam: Camera3D = ev[1]
	ecam.global_position = int_gpos + in_dir * 0.15
	ecam.look_at(int_gpos + in_dir * 2.0,
		Vector3.UP if absf(in_dir.y) < 0.9 else Vector3.FORWARD)
	# interior pane's camera: at the exterior window, looking outward
	var egpos := global_transform * ext_local
	var icam: Camera3D = iv[1]
	icam.global_position = egpos + out_dir * 0.15
	icam.look_at(egpos + out_dir * 2.0,
		global_transform.basis.y if absf(out_dir.dot(global_transform.basis.y)) < 0.9 \
		else -global_transform.basis.z)
	# the two units
	var eu := Node3D.new()
	add_child(eu)
	eu.position = ext_local
	eu.rotation_degrees = ext_rot_deg
	if ext_rot_deg.y == -90.0 and ext_local.y > 2.0:
		eu.rotation_degrees = Vector3(90, 0, 0)   # flat, glass facing UP
	_win_frame_on(eu, ev[0].get_texture(), ext_size, cavity)
	var iu := Node3D.new()
	_iroot.add_child(iu)
	iu.global_position = int_gpos
	iu.rotation_degrees = int_rot_deg
	if absf(in_dir.y) > 0.9:
		iu.rotation_degrees = Vector3(-90, 0, 0)   # ceiling glass faces DOWN
	_win_frame_on(iu, iv[0].get_texture(), int_size, cavity)

func _win_frame_on(u: Node3D, tex: Texture2D, wsize: Vector2, cavity := true) -> void:
	_win_frame(u, tex, wsize, cavity)

## One window UNIT: recessed cavity, frame, sill -- a window with
## actual depth, whose glass happens to be a live screen.
func _win_unit(parent: Node3D, pos: Vector3, yaw: float, tex: Texture2D,
		wsize: Vector2) -> void:
	var u := Node3D.new()
	parent.add_child(u)
	u.position = pos
	u.rotation_degrees.y = yaw
	_win_frame(u, tex, wsize)

func _win_frame(u: Node3D, tex: Texture2D, wsize: Vector2, cavity := true) -> void:
	var frame_c := Color("#4a3c2c") if not (kind in ["tower", "factory", "box"]) \
		else Color("#2c3038")
	var fm: Material = Surfaces.wood(frame_c)
	# the recess: a dark cavity sunk INTO the wall (0.10..0.30 deep --
	# every element gets its own depth plane, nothing coplanar)
	if cavity:
		var cav := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(wsize.x, wsize.y, 0.2)
		cav.mesh = cm
		cav.position = Vector3(0, 0, 0.2)
		cav.material_override = Destructible.make_material(Color("#101014"), 0.02)
		u.add_child(cav)
	# frame borders, slightly proud of the wall
	for spec in [
		[Vector3(wsize.x + 0.16, 0.08, 0.12), Vector3(0, wsize.y * 0.5 + 0.04, 0)],
		[Vector3(wsize.x + 0.16, 0.08, 0.12), Vector3(0, -wsize.y * 0.5 - 0.04, 0)],
		[Vector3(0.08, wsize.y + 0.16, 0.12), Vector3(wsize.x * 0.5 + 0.04, 0, 0)],
		[Vector3(0.08, wsize.y + 0.16, 0.12), Vector3(-wsize.x * 0.5 - 0.04, 0, 0)],
	]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		bar.mesh = bm
		bar.position = spec[1]
		bar.material_override = fm
		u.add_child(bar)
	# the sill: a ledge under the glass, like windows have
	var sill := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(wsize.x + 0.24, 0.06, 0.2)
	sill.mesh = sm
	sill.position = Vector3(0, -wsize.y * 0.5 - 0.1, -0.05)
	sill.material_override = fm
	u.add_child(sill)
	# center mullion: the cross-bar that says "window", not "screen"
	var mull := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.05, wsize.y, 0.05)
	mull.mesh = mm
	mull.position = Vector3(0, 0, -0.09)
	mull.material_override = fm
	u.add_child(mull)
	# the glass, recessed into the cavity: technically a screen. shh.
	var pane := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = wsize
	pane.mesh = qm
	pane.position = Vector3(0, 0, -0.09)
	pane.rotation_degrees.y = 180.0
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = tex
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pane.material_override = pm
	u.add_child(pane)


# ----------------------------------------------------------- use / tick

func use() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	# human homes: you may VISIT (see the residents, judge the decor),
	# you just can't claim the place
	enter(p)

func enter(p: Node3D) -> void:
	Game.zone = "flat"
	Game.zone_g = 9.0
	p.global_position = interior_spawn()
	p.velocity = Vector3.ZERO
	Sfx.play("click", -12.0)

func exit_to_door(p: Node3D) -> void:
	Game.zone = ""
	p.global_position = global_position + global_transform.basis.y * 1.2 \
		- global_transform.basis.z * 2.0
	p.velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	_haz_t -= delta
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var inside: bool = p.global_position.distance_to(room_center()) < room_size().length()
	var nearby: bool = p.global_position.distance_to(global_position) < 30.0
	if inside:
		# while you're in here, the world outside carries on around the
		# HOUSE, not around a point 60km away in a pocket dimension
		Game.player_proxy = global_position
		Game.has_proxy = true
	# the name over the roof: big, on top of everything, only nearby
	if _tag:
		_tag.visible = p.global_position.distance_to(global_position) < 45.0
	# window rendering only when someone can see the glass
	var live := inside or nearby
	for v in _views:
		if is_instance_valid(v):
			v.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live \
				else SubViewport.UPDATE_DISABLED
	if _haz_t <= 0.0:
		_haz_t = 2.0
		_scan_hazards()
	if inside:
		if _rad:
			Game.hurt(1.2)   # cancer, the slow kind
			if randf() < 0.5:
				Sfx.play("click", -16.0)   # the geiger disagrees with your choices
		if _smoke:
			Game.hurt(0.6)   # generator smoke: lungs disagree too

## What did you PUT in there. Reactors and RTGs irradiate the room;
## a generator fills it with smoke.
func _scan_hazards() -> void:
	_rad = false
	_smoke = false
	var c := room_center()
	var r := room_size().length()
	for m in get_tree().get_nodes_in_group("machine"):
		if not (m is Node3D) or not is_instance_valid(m):
			continue
		if m.global_position.distance_to(c) > r:
			continue
		if m is EMachines.NuclearReactor or m is EMachines.RTG:
			_rad = true
		if m is EMachines.Generator:
			_smoke = true
	if _smoke and _smoke_node == null:
		_smoke_node = GPUParticles3D.new()
		_smoke_node.amount = 40
		_smoke_node.lifetime = 3.0
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 60.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.4
		pm.scale_max = 1.2
		pm.color = Color(0.25, 0.25, 0.28, 0.5)
		_smoke_node.process_material = pm
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh.material = Destructible.make_material(Color(0.2, 0.2, 0.22), 0.0)
		_smoke_node.draw_pass_1 = mesh
		_iroot.add_child(_smoke_node)
		_smoke_node.global_position = c
	if _smoke_node:
		_smoke_node.emitting = _smoke

## Stamp a number on a port so outside 3 is obviously inside 3.
func _port_number(prt: Node3D, n: int) -> void:
	prt.num = n
	var lbl := Label3D.new()
	lbl.text = str(n)
	lbl.font_size = 30
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 0.72, 0)
	lbl.modulate = Color("#e8f0e8")
	lbl.outline_size = 6
	prt.add_child(lbl)

## A claiming human decorates to taste. The furniture is real: their
## guests will sit on it, and you can watch through the window.
func furnish_for(pers: Dictionary) -> void:
	var picks: Array = ["carpet"]
	if float(pers.get("dreamy", 25.0)) > 50.0:
		picks.append("bed")
	if float(pers.get("goofy", 25.0)) > 50.0:
		picks.append("sofa")
	if float(pers.get("grumpy", 25.0)) > 50.0:
		picks.append("chair")
	picks.append(Furniture.KINDS[randi() % Furniture.KINDS.size()])
	var c := room_center()
	var sz := room_size()
	for i in picks.size():
		var f := Furniture.new()
		f.kind = str(picks[i])
		get_tree().current_scene.add_child(f)
		f.global_position = c + Vector3(
			randf_range(-sz.x * 0.3, sz.x * 0.3),
			-sz.y * 0.5 + 0.55,
			randf_range(-sz.z * 0.3, sz.z * 0.3))

# ------------------------------------------------- door-merge machinery

## Every unlinked doorframe standing inside this house's rooms.
## The house whose room contains a pocket-space point (or null).
static func house_at(p: Vector3) -> House:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for h in tree.get_nodes_in_group("house"):
		if h is House and is_instance_valid(h):
			var sz: Vector3 = h.room_size()
			var rel: Vector3 = p - h.room_center()
			if absf(rel.x) < sz.x * 0.75 and absf(rel.z) < sz.z * 0.75 \
					and absf(rel.y) < sz.y * 1.2:
				return h
	return null

## Every frame in this room, linked or not (wall-occupancy checks).
func all_frames() -> Array:
	var out: Array = []
	var c := room_center()
	var r := room_size().length()
	for f in get_tree().get_nodes_in_group("doorframe"):
		if f is Furniture and is_instance_valid(f) \
				and f.global_position.distance_to(c) < r:
			out.append(f)
	return out

func my_frames() -> Array:
	var out: Array = []
	var c := room_center()
	var r := room_size().length()
	for f in get_tree().get_nodes_in_group("doorframe"):
		if f is Furniture and is_instance_valid(f) \
				and not bool(f.get_meta("linked", false)) \
				and f.global_position.distance_to(c) < r:
			out.append(f)
	return out

## Move this house's ENTIRE interior world (rooms, ports, furniture,
## machines, humans, players) by a pocket-space delta.
func shift_rooms(delta: Vector3) -> void:
	var c := room_center()
	var r := room_size().length() + 6.0
	room_offset += delta
	if _iroot and is_instance_valid(_iroot):
		for ch in _iroot.get_children():
			if ch is Node3D:
				ch.global_position += delta
	for prt in _in_ports:
		if is_instance_valid(prt):
			prt.global_position += delta
	for grp in ["machine", "chest", "bench", "itemdrop", "earth_human",
			"doorframe", "seat", "player"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D and is_instance_valid(n) \
					and n.global_position.distance_to(c) < r \
					and not (_iroot and n.get_parent() == _iroot):
				n.global_position += delta

## The whole docked complex this house belongs to (BFS over links).
func complex() -> Array:
	var seen := {slot: self}
	var queue := [self]
	while not queue.is_empty():
		var h = queue.pop_back()
		for other in get_tree().get_nodes_in_group("house"):
			if other is House and is_instance_valid(other) \
					and not seen.has(other.slot) and other.slot in h.links:
				seen[other.slot] = other
				queue.append(other)
	return seen.values()

## Would the moved cluster collide with any house OUTSIDE the moving set?
func _area_free(delta: Vector3, moving: Array) -> bool:
	for h in moving:
		var c: Vector3 = h.room_center() + delta
		var r: float = maxf(h.room_size().x, h.room_size().z) * 0.5 + 0.2
		for other in get_tree().get_nodes_in_group("house"):
			if other is House and is_instance_valid(other) and not moving.has(other):
				var orr: float = maxf(other.room_size().x, other.room_size().z) * 0.5 + 0.2
				# docked neighbours are SUPPOSED to touch: skip linked pairs
				if other.slot in h.links:
					continue
				if c.distance_to(other.room_center()) < r + orr:
					return false
	return true

## Cut a doorway through the wall nearest the frame: the wall body is
## replaced by three segments leaving a walkable gap.
func cut_doorway(frame: Node3D) -> void:
	var best: StaticBody3D = null
	var bd := 4.5
	if _iroot == null or not is_instance_valid(_iroot):
		return
	for ch in _iroot.get_children():
		if ch is StaticBody3D and ch.get_child_count() >= 2:
			# walls only (tall boxes), ranked by how close the frame
			# stands to the wall's PLANE, not its center
			var cc2: CollisionShape3D = null
			for k in ch.get_children():
				if k is CollisionShape3D:
					cc2 = k
			if cc2 == null or not (cc2.shape is BoxShape3D):
				continue
			var bsz: Vector3 = cc2.shape.size
			if bsz.y < 2.0 or (bsz.x < 2.0 and bsz.z < 2.0):
				continue
			var rel: Vector3 = frame.global_position - ch.global_position
			var plane_d: float = absf(rel.z) if bsz.x > bsz.z else absf(rel.x)
			if plane_d < bd and absf(rel.y) < bsz.y:
				bd = plane_d
				best = ch
	if best == null:
		return
	var col: CollisionShape3D = null
	for cc in best.get_children():
		if cc is CollisionShape3D:
			col = cc
	if col == null or not (col.shape is BoxShape3D):
		return
	var wsz: Vector3 = col.shape.size
	var wpos := best.global_position
	var mat: Material = null
	for mm in best.get_children():
		if mm is MeshInstance3D:
			mat = mm.material_override
	best.queue_free()
	# the wall runs along its LONG horizontal axis; the gap is centered
	# on the frame's position along that axis
	var along_x := wsz.x > wsz.z
	var gapw := 2.0
	var gaph := 2.7
	var fl: float = (frame.global_position.x - wpos.x) if along_x \
		else (frame.global_position.z - wpos.z)
	var span: float = wsz.x if along_x else wsz.z
	var lw: float = span * 0.5 + fl - gapw * 0.5
	var rw: float = span * 0.5 - fl - gapw * 0.5
	var yb: float = wpos.y - wsz.y * 0.5
	for seg in [
		[lw, (-span * 0.5 + lw * 0.5), 0.0, wsz.y, wpos.y],
		[rw, (span * 0.5 - rw * 0.5), 0.0, wsz.y, wpos.y],
		[gapw, fl, 0.0, wsz.y - gaph, yb + gaph + (wsz.y - gaph) * 0.5],
	]:
		if seg[0] < 0.15 or seg[3] < 0.15:
			continue
		var b2 := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m2 := BoxMesh.new()
		m2.size = Vector3(seg[0], seg[3], wsz.z) if along_x \
			else Vector3(wsz.x, seg[3], seg[0])
		mi.mesh = m2
		mi.material_override = mat
		b2.add_child(mi)
		var c2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		bs2.size = m2.size
		c2.shape = bs2
		b2.add_child(c2)
		_iroot.add_child(b2)
		b2.global_position = Vector3(wpos.x + seg[1], seg[4], wpos.z) if along_x \
			else Vector3(wpos.x, seg[4], wpos.z + seg[1])

## The little hallway between two cut walls, plus the outside tunnel.
func build_link_visuals(other) -> void:
	var fa_p := Vector3.ZERO
	var fb_p := Vector3.ZERO
	# nearest pair of frames between the two houses
	var bd := 1e9
	for fa in get_tree().get_nodes_in_group("doorframe"):
		if not (fa is Node3D) or fa.global_position.distance_to(room_center()) > room_size().length():
			continue
		for fb in get_tree().get_nodes_in_group("doorframe"):
			if not (fb is Node3D) or fb.global_position.distance_to(other.room_center()) > other.room_size().length():
				continue
			var d: float = fa.global_position.distance_to(fb.global_position)
			if d < bd:
				bd = d
				fa_p = fa.global_position
				fb_p = fb.global_position
	if bd > 16.0:
		return
	var mid := (fa_p + fb_p) * 0.5 + Vector3(0, 1.35, 0)
	var dirv := (fb_p - fa_p)
	dirv.y = 0.0
	# SEAMLESS: run the tube long enough to bite through both walls,
	# floor top flush with the room floors
	var L := dirv.length() + 2.8
	if dirv.length() < 0.1:
		return
	dirv = dirv.normalized()
	var xr := dirv.cross(Vector3.UP).normalized()
	var gray := Surfaces.metal(Color("#8a9098"))
	for spec in [
		[Vector3(2.6, 0.3, L), Vector3(0, -1.3, 0)],
		[Vector3(2.6, 0.3, L), Vector3(0, 1.55, 0)],
		[Vector3(0.3, 3.1, L), Vector3(-1.3, 0, 0)],
		[Vector3(0.3, 3.1, L), Vector3(1.3, 0, 0)],
	]:
		var b3 := StaticBody3D.new()
		var mi3 := MeshInstance3D.new()
		var m3 := BoxMesh.new()
		m3.size = spec[0]
		mi3.mesh = m3
		mi3.material_override = gray
		b3.add_child(mi3)
		var c3 := CollisionShape3D.new()
		var bs3 := BoxShape3D.new()
		bs3.size = spec[0]
		c3.shape = bs3
		b3.add_child(c3)
		_iroot.add_child(b3)
		b3.global_transform = Transform3D(
			Basis(xr, Vector3.UP, dirv).orthonormalized(), mid) \
			* Transform3D(Basis(), spec[1])
	# the outside: a skewed connector between the two shells, with a
	# glowing seam and a label saying WHO is docked to WHOM
	if is_instance_valid(other):
		var a_out := global_position + global_transform.basis.y * 1.4
		var b_out: Vector3 = other.global_position + other.global_transform.basis.y * 1.4
		var seg2 := b_out - a_out
		if seg2.length() > 0.5:
			var tube := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(1.4, 1.4, maxf(seg2.length() - 1.0, 1.2))
			tube.mesh = tm
			tube.material_override = Surfaces.metal(Color("#9aa0a8"))
			get_tree().current_scene.add_child(tube)
			tube.global_position = (a_out + b_out) * 0.5
			var upm: Vector3 = (global_transform.basis.y + other.global_transform.basis.y).normalized()
			if absf(seg2.normalized().dot(upm)) > 0.95:
				upm = global_transform.basis.x
			tube.look_at(tube.global_position + seg2.normalized(), upm)
			var seam := MeshInstance3D.new()
			var sm3 := BoxMesh.new()
			sm3.size = Vector3(1.5, 0.16, tm.size.z + 0.1)
			seam.mesh = sm3
			seam.material_override = Surfaces.portal(Color("#7bffb0"))
			tube.add_child(seam)
			seam.position = Vector3(0, 0.72, 0)
			var linklbl := Label3D.new()
			linklbl.text = "%s  ⇄  %s" % [display_name(), other.display_name()]
			linklbl.font_size = 20
			linklbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			linklbl.no_depth_test = true
			linklbl.outline_size = 6
			linklbl.modulate = Color(0.6, 1.0, 0.75, 0.9)
			tube.add_child(linklbl)
			linklbl.position = Vector3(0, 1.6, 0)

## Would docking `other` through these two frames work? Returns
## {ok, reason, delta, moving} -- the door tool asks BEFORE cutting.
func dock_check(fa: Node3D, other, fb: Node3D) -> Dictionary:
	if other == self or other == null or not is_instance_valid(other):
		return {"ok": false, "reason": "same house", "delta": Vector3.ZERO}
	if other.slot in links:
		return {"ok": false, "reason": "already connected", "delta": Vector3.ZERO}
	var fwd_a: Vector3 = -fa.global_transform.basis.z
	fwd_a.y = 0.0
	if fwd_a.length() < 0.1:
		fwd_a = Vector3.FORWARD
	fwd_a = fwd_a.normalized()
	var target_fb := fa.global_position + fwd_a * 7.5   # a real 6m hallway
	var delta := target_fb - fb.global_position
	delta.y = fa.global_position.y - fb.global_position.y
	var moving: Array = other.complex()
	if moving.has(self):
		return {"ok": false, "reason": "same complex -- that fold is non-euclidean",
			"delta": Vector3.ZERO}
	if not _area_free(delta, moving):
		return {"ok": false, "reason": "rooms would collide", "delta": delta}
	return {"ok": true, "reason": "", "delta": delta, "moving": moving}

## THE MERGE, via two specific frames (the door tool's chosen pair).
func connect_frames(fa: Node3D, other, fb: Node3D) -> bool:
	var ck := dock_check(fa, other, fb)
	if not bool(ck["ok"]):
		return false
	for h in ck["moving"]:
		h.shift_rooms(ck["delta"])
	links.append(other.slot)
	other.links.append(slot)
	fa.set_meta("linked", true)
	fb.set_meta("linked", true)
	for nm in ["shimmer", "clickpane"]:
		var sh = fa.get_node_or_null(nm)
		if sh:
			sh.queue_free()
		var sh2 = fb.get_node_or_null(nm)
		if sh2:
			sh2.queue_free()
	cut_doorway(fa)
	other.cut_doorway(fb)
	build_link_visuals(other)
	Sfx.play("learn", -6.0)
	return true

## Legacy path (tests, nearest-frame docking): first free frame each.
func connect_house(other) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	var mine := my_frames()
	var theirs: Array = other.my_frames()
	if mine.is_empty() or theirs.is_empty():
		return false
	return connect_frames(mine[0], other, theirs[0])

func _exit_tree() -> void:
	# demolition severs every docking link so neighbours don't keep a
	# phantom slot in their graph (a dead complex should split cleanly)
	for other in get_tree().get_nodes_in_group("house"):
		if other is House and other != self and is_instance_valid(other):
			other.links.erase(slot)
	if _iroot and is_instance_valid(_iroot):
		_iroot.queue_free()
	for prt in _out_ports + _in_ports:
		if is_instance_valid(prt):
			prt.queue_free()
