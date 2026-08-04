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

const KINDS := ["small", "two_story", "box", "basement", "factory", "tower"]

## A wall port: a light-gray socket box, barely proud of the wall,
## little square panels on every face. NOT an extender -- a PORTAL:
## whatever lands in it (power or items) teleports to its twin in the
## exact home it belongs to.
class Port extends Machine:
	var twin = null
	var is_power := true
	var home_label := ""

	func _init() -> void:
		title = "HOUSE PORT"
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
		part(sq, Vector3(0, 0.26, 0.11), scol, 0.5)
		part(sq, Vector3(0, 0.26, -0.11), scol, 0.5)
		var sq2 := BoxMesh.new()
		sq2.size = Vector3(0.035, 0.24, 0.1)
		part(sq2, Vector3(0.25, 0.26, 0), scol, 0.5)
		part(sq2, Vector3(-0.25, 0.26, 0), scol, 0.5)
		var sq3 := BoxMesh.new()
		sq3.size = Vector3(0.24, 0.035, 0.1)
		part(sq3, Vector3(0, 0.51, 0), scol, 0.5)

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
var _vp_out: SubViewport        # renders interior (for the outside pane)
var _vp_in: SubViewport         # renders outside (for the inside pane)
var _cam_out: Camera3D
var _cam_in: Camera3D
var _haz_t := 0.0
var _rad := false
var _smoke := false
var _smoke_node: GPUParticles3D
var _door_pos := Vector3.ZERO   # local door spot (exterior)
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

func room_center() -> Vector3:
	return BASE + Vector3(float(slot) * SLOT_SPACING, 0, 0)

func interior_spawn() -> Vector3:
	return room_center() + Vector3(0, -room_size().y * 0.5 + 1.5, room_size().z * 0.5 - 3.0)

func room_size() -> Vector3:
	match kind:
		"two_story":
			return Vector3(14, 10, 14)
		"box":
			return Vector3(8, 8, 8)
		"basement":
			return Vector3(14, 5.5, 14)
		"factory":
			return Vector3(26, 9, 26)
		"tower":
			return Vector3(16, 20, 16)
		_:
			return Vector3(13, 5.5, 13)

func _ready() -> void:
	add_to_group("house")
	if slot < 0:
		slot = _next_slot
	_next_slot = maxi(_next_slot, slot + 1)
	_build_exterior()
	_build_interior()
	_build_ports()
	_build_windows()

# ------------------------------------------------------------- exterior

func _wallmat(c: Color, e := 0.05) -> StandardMaterial3D:
	return Destructible.make_material(c, e)

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
	# FOUNDATION: a deep plug so the house never floats on curvature
	_box(self, Vector3(w + 0.6, 6.0, w + 0.6), Vector3(0, -3.0, 0), wall.darkened(0.35))
	# main shell
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
	elif true:
		# pitched roof (two slabs)
		for sgn in [-1.0, 1.0]:
			var slab := _box(self, Vector3(w + 0.6, 0.22, w * 0.62),
				Vector3(0, h + w * 0.15, sgn * w * 0.24), roofc)
			slab.rotation_degrees.x = sgn * 32.0   # apex UP. a roof, not a funnel
		# ridge beam capping the apex
		_box(self, Vector3(w + 0.7, 0.16, 0.3), Vector3(0, h + w * 0.31, 0),
			roofc.darkened(0.25))
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
	_tag.font_size = 16
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

# ------------------------------------------------------------- interior

func _iroom(center: Vector3, size: Vector3, c: Color, e := 0.12) -> void:
	var half := size * 0.5
	for wspec in [
		[Vector3(size.x, 1, size.z), Vector3(0, -half.y, 0)],
		[Vector3(size.x, 1, size.z), Vector3(0, half.y, 0)],
		[Vector3(1, size.y, size.z), Vector3(-half.x, 0, 0)],
		[Vector3(1, size.y, size.z), Vector3(half.x, 0, 0)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, -half.z)],
		[Vector3(size.x, size.y, 1), Vector3(0, 0, half.z)],
	]:
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = wspec[0]
		mi.mesh = m
		mi.material_override = _wallmat(c, e)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = wspec[0]
		col.shape = bs
		body.add_child(col)
		_iroot.add_child(body)
		body.global_position = center + wspec[1]
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
	_iroom(c, sz, warm)
	var fy := c.y - sz.y * 0.5
	# every home: a visible ceiling light fixture and a wall trim band
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
			# railing along the slab's open edge
			for rz in 5:
				_deco(c + Vector3(sz.x * 0.2, 0.8, -sz.z * 0.45 + float(rz) * (sz.z * 0.22)),
					Vector3(0.08, 1.2, 0.08), warm.darkened(0.4))
			_deco(c + Vector3(sz.x * 0.2, 1.4, 0), Vector3(0.1, 0.08, sz.z - 1.0),
				warm.darkened(0.4))
			# fireplace on the ground floor
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
		"basement":
			# the cellar: a real second room below, reached by a HATCH
			# (gates, because you cannot cut a hole in a BoxMesh floor)
			var bc := c + Vector3(0, -sz.y - 2.0, 0)
			_iroom(bc, Vector3(sz.x - 2.0, sz.y, sz.z - 2.0), Color("#8a8272"), 0.06)
			var down := Gate.new().configure({
				"target": bc + Vector3(0, -sz.y * 0.5 + 1.2, 2.0),
				"zone": "flat", "label": "CELLAR", "color": Color("#6a5434")})
			_iroot.add_child(down)
			down.global_position = c + Vector3(sz.x * 0.5 - 2.0, fy - c.y + 0.4,
				-sz.z * 0.5 + 2.0)
			var upg := Gate.new().configure({
				"target": c + Vector3(sz.x * 0.5 - 3.5, fy - c.y + 1.2, -sz.z * 0.5 + 2.0),
				"zone": "flat", "label": "UP", "color": Color("#c9b47e")})
			_iroot.add_child(upg)
			upg.global_position = bc + Vector3(0, -sz.y * 0.5 + 0.4, 3.5)
			# cellar clutter: crates, a shelf, one suspicious barrel
			for i in 3:
				_deco(bc + Vector3(-2.0 + float(i) * 1.6, -sz.y * 0.5 + 0.55,
					(float(sz.z) - 2.0) * 0.3), Vector3(0.9, 0.9, 0.9), Color("#6a5434"))
			_deco(bc + Vector3(2.8, -sz.y * 0.5 + 0.7, -2.0),
				Vector3(0.7, 1.4, 0.7), Color("#4a4438"))
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
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
			_solid(c + Vector3(0, 0.8, -sz.z * 0.5 + 1.2),
				Vector3(sz.x - 6.0, 0.3, 1.8), Color("#6a6f78"))
		_:
			# small house: a hearth makes it a home
			_fireplace(c + Vector3(-sz.x * 0.5 + 0.7, fy - c.y + 0.9, 0))
	# EXIT door pad, back wall
	var out := Gate.new().configure({
		"action": "house_exit", "label": "LEAVE HOUSE",
		"color": Color("#ffe066")})
	_iroot.add_child(out)
	out.global_position = c + Vector3(0, fy - c.y + 1.0, sz.z * 0.5 - 1.4)
	out.set_meta("house", self)

## A real staircase: N steps climbing `rise` along `step_vec` (x,z per
## step), each with collision. The last step tops out AT the rise.
func _stairs(base: Vector3, step_vec: Vector3, steps: int, rise: float,
		col: Color) -> void:
	for st in steps:
		var t := float(st + 1) / float(steps)
		_solid(base + Vector3(step_vec.x * 0.0, rise * t - 0.2,
			step_vec.z * float(st)) + Vector3(0, 0, 0),
			Vector3(2.2 if step_vec.x != 0.0 else 2.0, 0.42,
				absf(step_vec.z) + 0.35 if step_vec.z != 0.0 else 1.0), col)

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
		outp.global_transform = global_transform
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
			-sz.y * 0.5 + 1.0, -sz.z * 0.5 + 0.85)
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
	# shared screens: ONE camera looks at the interior (for every
	# outside pane), one looks out from the wall (for every inside pane)
	_vp_out = SubViewport.new()
	_vp_out.size = Vector2i(256, 192)
	_vp_out.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp_out)
	_vp_out.world_3d = get_viewport().world_3d
	_cam_out = Camera3D.new()
	_vp_out.add_child(_cam_out)
	_cam_out.fov = 65.0
	_cam_out.global_position = c + Vector3(0, 0.5, sz.z * 0.5 - 1.0)
	_cam_out.look_at(c + Vector3(0, -sz.y * 0.25, 0), Vector3.UP)
	_vp_in = SubViewport.new()
	_vp_in.size = Vector2i(384, 288)
	_vp_in.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp_in)
	_vp_in.world_3d = get_viewport().world_3d
	_cam_in = Camera3D.new()
	_vp_in.add_child(_cam_in)
	_cam_in.fov = 70.0
	var otex := _vp_out.get_texture()
	var itex := _vp_in.get_texture()
	if kind == "box":
		# the SKYLIGHT IS the ceiling: glass roof outside showing the
		# cube's contents, glass ceiling inside showing the sky
		_cam_out.global_position = c + Vector3(0, sz.y * 0.5 - 0.7, 0.01)
		_cam_out.look_at(c + Vector3(0, -sz.y * 0.5, 0), Vector3.FORWARD)
		var tu := Node3D.new()
		add_child(tu)
		tu.position = Vector3(0, 3.05, 0)
		tu.rotation_degrees.x = -90.0
		_win_frame(tu, otex, Vector2(w - 0.5, w - 0.5))
		var cu := Node3D.new()
		_iroot.add_child(cu)
		cu.global_position = c + Vector3(0, sz.y * 0.5 - 0.62, 0)
		cu.rotation_degrees.x = 90.0
		_win_frame(cu, itex, Vector2(sz.x - 1.6, sz.z - 1.6))
		return
	# windows per floor on the FRONT and BACK faces (never the sides),
	# inside and outside in matching places, properly sized
	var floors := 1
	match kind:
		"two_story": floors = 2
		"tower": floors = 3
	var ifloors := floors if kind != "tower" else int(sz.y / 5.0)
	for f in floors:
		var wy := 1.7 + float(f) * (3.0 if kind != "two_story" else 2.9)
		# front: beside the door on floor 0, centered above
		var fx := 1.4 if f == 0 else 0.0
		_win_unit(self, Vector3(fx, wy, -w * 0.5 + 0.02), 0.0, otex,
			Vector2(1.4, 1.2))
		_win_unit(self, Vector3(0, wy, w * 0.5 - 0.02), 180.0, otex,
			Vector2(1.4, 1.2))
	for f2 in ifloors:
		var fy2 := c.y - sz.y * 0.5 + 1.6 + float(f2) * 5.0
		if kind == "two_story":
			fy2 = c.y - sz.y * 0.5 + 1.6 + float(f2) * (sz.y * 0.5)
		for zside in [-1.0, 1.0]:
			var iu := Node3D.new()
			_iroot.add_child(iu)
			iu.global_position = Vector3(c.x, fy2, c.z + zside * (sz.z * 0.5 - 0.62))
			iu.rotation_degrees.y = 0.0 if zside > 0.0 else 180.0
			_win_frame(iu, itex, Vector2(3.2, 2.2))

## One window UNIT: recessed cavity, frame, sill -- a window with
## actual depth, whose glass happens to be a live screen.
func _win_unit(parent: Node3D, pos: Vector3, yaw: float, tex: Texture2D,
		wsize: Vector2) -> void:
	var u := Node3D.new()
	parent.add_child(u)
	u.position = pos
	u.rotation_degrees.y = yaw
	_win_frame(u, tex, wsize)

func _win_frame(u: Node3D, tex: Texture2D, wsize: Vector2) -> void:
	var frame_c := Color("#4a3c2c") if not (kind in ["tower", "factory", "box"]) \
		else Color("#2c3038")
	var fm := Destructible.make_material(frame_c, 0.05)
	# the recess: a dark cavity sunk INTO the wall (0.10..0.30 deep --
	# every element gets its own depth plane, nothing coplanar)
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
	if human_home:
		Sfx.play("denied")   # it's SOMEONE'S. have some decency.
		return
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
	# window rendering only when someone can see the glass
	if _vp_out:
		_vp_out.render_target_update_mode = SubViewport.UPDATE_ALWAYS if nearby \
			else SubViewport.UPDATE_DISABLED
	if _vp_in:
		_vp_in.render_target_update_mode = SubViewport.UPDATE_ALWAYS if inside \
			else SubViewport.UPDATE_DISABLED
		if inside and _cam_in:
			var wy: Vector3 = global_transform.basis.y
			if kind == "box":
				# the ceiling is glass: the view is UP
				var cpos0: Vector3 = global_position + wy * 4.0
				_cam_in.global_position = cpos0
				_cam_in.look_at(cpos0 + wy, -global_transform.basis.z)
			else:
				# windows face front/back: the view is the front yard
				var wz: Vector3 = -global_transform.basis.z
				var cpos: Vector3 = global_position + wz * 3.6 + wy * 1.8
				_cam_in.global_position = cpos
				_cam_in.look_at(cpos + wz, wy)
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

func _exit_tree() -> void:
	if _iroot and is_instance_valid(_iroot):
		_iroot.queue_free()
	for prt in _out_ports + _in_ports:
		if is_instance_valid(prt):
			prt.queue_free()
