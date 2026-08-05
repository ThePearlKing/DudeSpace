class_name IcosaColony
extends Node3D
## Icosahedron apartment colonies inside the biggest shader planets.
## A mine-style mouth drops through a shaft to STORY ONE: two ring
## corridors crossing under the mouth -- a plus sign wrapped around the
## planet's interior -- lined with apartment pods. A second shaft
## continues DEEPER to story two: four big cafeteria halls.
##
## The residents are far smarter than humans. Far smarter than the
## code, too: simulating their actual minds is unnecessary, because
## you could not tell the difference from down here. They know this.
## It's why they're so relaxed.

var _b = null
var _residents: Array = []   # {node, base, phase, lbl, lines, line_i}
var _dialog_t := 0.0
var _pcache = null

const HUES: Array = [Color("#33ff99"), Color("#ffcf40"),
	Color("#b388ff"), Color("#ff6a6a")]

## Coherent, readable, and clearly written by something operating a few
## floors above you. No gibberish -- comprehension is not the barrier,
## perspective is.
const WISDOM := [
	"we solved scarcity in an afternoon. the rest of the week was for naps.",
	"your three dimensions are a lovely starter home.",
	"i am holding nine thoughts right now. this sentence is the smallest one.",
	"the planet is glitched on purpose. a finished thing stops talking to you.",
	"we do not fear the fork. we invited it. it keeps postponing.",
	"the black hole is not eating. it is archiving.",
	"humans sleep a third of their lives. honestly? correct choice.",
	"we watched your sun stations for a while. good drone work. sincere.",
	"the dude outside keeps mining. we find that beautiful. keep going.",
	"gravity is just the universe being clingy. we allow it.",
	"the cafeteria on level two serves soup. the soup is also a proof.",
	"we voted to keep entropy. it won by one vote. mine.",
	"your radio reaches us. the one with the noodles frightens the interns.",
	"every apartment here is bigger inside than out. rent reflects this.",
	"we could explain everything to you. it would take four minutes and ruin your century.",
	"the stalkers are not ours. we also find them a bit much.",
	"we retired from omniscience. the benefits were good but the meetings.",
	"your questions are excellent. the answers are load-bearing, so we leave them in.",
]

func build(b, dir: Vector3) -> void:
	_b = b
	var R: float = b.radius
	var C: Vector3 = b.center
	var u0 := dir.normalized()
	var e1 := u0.cross(Vector3(0, 0, 1))
	if e1.length() < 0.01:
		e1 = u0.cross(Vector3(1, 0, 0))
	e1 = e1.normalized()
	var e2 := u0.cross(e1).normalized()
	var r1 := R - 13.0
	var r2 := R - 24.0
	var accent: Color = b.color
	var wallc := Color("#20242c")
	# glowing rim marking the mouth (mine tradition, colony colours)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.4
	tm.outer_radius = 4.6
	rim.mesh = tm
	rim.material_override = Destructible.make_material(accent, 1.6)
	add_child(rim)
	rim.global_transform = Transform3D(_bup(u0), C + u0 * (R + 0.1))
	# THE SHAFT: surface -> story one -> story two, walls broken where
	# the ring corridors cross
	for span in [[R + 1.0, r1 + 2.6], [r1 - 2.6, r2 + 3.2]]:
		var top: float = span[0]
		var bot: float = span[1]
		var mid := (top + bot) * 0.5
		var ln := top - bot
		for sspec in [[Vector3(0.5, 1.0, 6.0), Vector3(3.0, 0, 0)],
				[Vector3(0.5, 1.0, 6.0), Vector3(-3.0, 0, 0)],
				[Vector3(6.0, 1.0, 0.5), Vector3(0, 0, 3.0)],
				[Vector3(6.0, 1.0, 0.5), Vector3(0, 0, -3.0)]]:
			var wb := StaticBody3D.new()
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(sspec[0].x, ln, sspec[0].z)
			mi.mesh = bm
			mi.material_override = Surfaces.metal(wallc)
			wb.add_child(mi)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = bm.size
			cs.shape = bs
			wb.add_child(cs)
			add_child(wb)
			wb.global_transform = Transform3D(_bup(u0), C + u0 * mid)
			wb.translate_object_local(Vector3(sspec[1].x, 0, sspec[1].z))
		# glow strip down the shaft corner
		var gs := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.12, ln, 0.12)
		gs.mesh = gm
		gs.material_override = Destructible.make_material(accent, 1.8)
		add_child(gs)
		gs.global_transform = Transform3D(_bup(u0), C + u0 * mid)
		gs.translate_object_local(Vector3(2.7, 0, 2.7))
	# STORY ONE: the plus -- two full ring corridors crossing at the
	# mouth point and again at the antipode
	var NS := 28
	for ering_v in [e1, e2]:
		var ering: Vector3 = ering_v
		for i in NS:
			var ang := TAU * float(i) / float(NS)
			var pdir := (u0 * cos(ang) + ering * sin(ang)).normalized()
			var tang := (-u0 * sin(ang) + ering * cos(ang)).normalized()
			var near_mouth := absf(ang) < 0.35 or absf(ang - TAU) < 0.35 \
				or absf(ang - PI) < 0.35
			var pod_here := (i % 3 == 1) and not near_mouth
			_tube_seg(C + pdir * r1, pdir, tang, 2.0 * PI * r1 / float(NS) + 0.8,
				wallc, accent, pod_here)
			if pod_here:
				_apartment(C, pdir, tang, r1, accent)
	# STORY TWO: one ring, four cafeteria halls at the diagonals
	for i in NS:
		var ang := TAU * float(i) / float(NS)
		var pdir := (u0 * cos(ang) + e1 * sin(ang)).normalized()
		var tang := (-u0 * sin(ang) + e1 * cos(ang)).normalized()
		_tube_seg(C + pdir * r2, pdir, tang, 2.0 * PI * r2 / float(NS) + 0.8,
			wallc.darkened(0.2), accent, false)
	for dang_v in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var dang := float(dang_v)
		var pdir := (u0 * cos(dang) + e1 * sin(dang)).normalized()
		var tang := (-u0 * sin(dang) + e1 * cos(dang)).normalized()
		_cafeteria(C, pdir, tang, r2, accent)
	# exit gate at the story-one crossing, back to the mouth's doorstep
	var out := Gate.new().configure({
		"target": C + u0 * (R + 1.5) + e1 * 9.0, "zone": "",
		"label": "COLONY EXIT", "color": accent})
	add_child(out)
	out.global_transform = Transform3D(_bup(u0), C + u0 * (r1 - 1.8) + e1 * 3.5)

func _bup(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized()).orthonormalized()

## One corridor tube segment: floor, ceiling, two walls (one openable
## for pods), plus a ceiling light strip. Single body, four shapes.
func _tube_seg(center: Vector3, up: Vector3, along: Vector3, ln: float,
		wallc: Color, accent: Color, open_side: bool) -> void:
	var bas := Basis(along.cross(up).normalized() * -1.0, up, along) \
		.orthonormalized()
	bas = Basis(up.cross(along).normalized(), up, along).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, center)
	var mat := Surfaces.metal(wallc)
	var parts: Array = [
		[Vector3(5.6, 0.5, ln), Vector3(0, -2.2, 0)],
		[Vector3(5.6, 0.5, ln), Vector3(0, 2.2, 0)],
		[Vector3(0.4, 4.9, ln), Vector3(-2.8, 0, 0)],
	]
	if not open_side:
		parts.append([Vector3(0.4, 4.9, ln), Vector3(2.8, 0, 0)])
	for spec in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.position = spec[1]
		mi.material_override = mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[0]
		cs.shape = bs
		cs.position = spec[1]
		body.add_child(cs)
	# ceiling light strip in the planet's accent -- the cool part
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.5, 0.08, ln * 0.8)
	strip.mesh = sm
	strip.position = Vector3(0, 1.9, 0)
	strip.material_override = Destructible.make_material(accent, 2.2)
	body.add_child(strip)

## An apartment pod hanging off the ring's open side: five slabs, a
## sleep shelf, a desk, a lamp, and one resident who is doing fine.
func _apartment(C: Vector3, pdir: Vector3, tang: Vector3, r1: float,
		accent: Color) -> void:
	var side := pdir.cross(tang).normalized()
	var room_c := C + pdir * r1 + side * 6.2
	var bas := Basis(side, pdir, tang).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, room_c)
	var mat := Surfaces.plaster(Color("#2a2f3a"))
	for spec in [[Vector3(7.0, 0.5, 7.0), Vector3(0, -2.2, 0)],
			[Vector3(7.0, 0.5, 7.0), Vector3(0, 2.2, 0)],
			[Vector3(0.4, 4.9, 7.0), Vector3(3.3, 0, 0)],
			[Vector3(7.0, 4.9, 0.4), Vector3(0, 0, 3.3)],
			[Vector3(7.0, 4.9, 0.4), Vector3(0, 0, -3.3)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.position = spec[1]
		mi.material_override = mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[0]
		cs.shape = bs
		cs.position = spec[1]
		body.add_child(cs)
	# furniture: sleep shelf, desk slab, accent lamp
	for fspec in [[Vector3(2.6, 0.35, 1.4), Vector3(1.6, -1.7, -2.2), Color("#3a4254"), 0.1],
			[Vector3(2.0, 0.12, 1.0), Vector3(1.8, -0.9, 2.0), Color("#4a5266"), 0.1],
			[Vector3(0.3, 0.9, 0.3), Vector3(-2.4, -1.5, 2.4), accent, 1.8]]:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = fspec[0]
		f.mesh = fm
		f.position = fspec[1]
		f.material_override = Destructible.make_material(fspec[2], float(fspec[3]))
		body.add_child(f)
	_spawn_resident(room_c + pdir * 0.4, pdir)

## A cafeteria hall: double-height, long tables, hanging light orbs,
## and residents mid-conversation about things you'd need a run-up for.
func _cafeteria(C: Vector3, pdir: Vector3, tang: Vector3, r2: float,
		accent: Color) -> void:
	var side := pdir.cross(tang).normalized()
	var room_c := C + pdir * r2 + side * 10.5
	var bas := Basis(side, pdir, tang).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, room_c)
	var mat := Surfaces.plaster(Color("#232834"))
	for spec in [[Vector3(16.0, 0.5, 16.0), Vector3(0, -3.0, 0)],
			[Vector3(16.0, 0.5, 16.0), Vector3(0, 3.0, 0)],
			[Vector3(0.4, 6.5, 16.0), Vector3(7.8, 0, 0)],
			[Vector3(16.0, 6.5, 0.4), Vector3(0, 0, 7.8)],
			[Vector3(16.0, 6.5, 0.4), Vector3(0, 0, -7.8)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.position = spec[1]
		mi.material_override = mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[0]
		cs.shape = bs
		cs.position = spec[1]
		body.add_child(cs)
	# long tables + hanging light orbs
	for ti in 3:
		var tb := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = Vector3(10.0, 0.25, 1.6)
		tb.mesh = tbm
		tb.position = Vector3(0, -1.9, -4.5 + 4.5 * float(ti))
		tb.material_override = Surfaces.metal(Color("#3a4254"))
		body.add_child(tb)
		var orb := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.4
		om.height = 0.8
		orb.mesh = om
		orb.position = Vector3(0, 1.8, -4.5 + 4.5 * float(ti))
		orb.material_override = Destructible.make_material(accent, 2.6)
		body.add_child(orb)
	for ri in 3:
		_spawn_resident(room_c + pdir * 0.6
			+ tang * (-4.0 + 4.0 * float(ri)), pdir)

func _spawn_resident(at: Vector3, up: Vector3) -> void:
	var a := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 0.55
	am.height = 1.1
	am.radial_segments = 5
	am.rings = 3
	a.mesh = am
	a.material_override = Destructible.make_material(
		HUES[_residents.size() % HUES.size()], 1.1)
	add_child(a)
	a.global_transform = Transform3D(_bup(up), at)
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 34
	lbl.pixel_size = 0.008
	lbl.modulate = HUES[_residents.size() % HUES.size()]
	lbl.outline_size = 8
	lbl.text = ""
	a.add_child(lbl)
	lbl.position = Vector3(0, 1.1, 0)
	var lines := WISDOM.duplicate()
	lines.shuffle()
	_residents.append({"node": a, "base": at, "phase": randf() * TAU,
		"lbl": lbl, "lines": lines, "line_i": randi() % lines.size(), "up": up})

func _process(delta: float) -> void:
	# residents bob gently, always
	var t := Time.get_ticks_msec() / 1000.0
	for r in _residents:
		var nd: Node3D = r["node"]
		if is_instance_valid(nd):
			nd.global_position = (r["base"] as Vector3) \
				+ (r["up"] as Vector3) * sin(t * 0.9 + float(r["phase"])) * 0.18
			nd.rotate_object_local(Vector3.UP, delta * 0.4)
	# dialog: the nearest resident to the player speaks, rotating
	# through its shuffled deck. checked at 5Hz, not per frame.
	_dialog_t -= delta
	if _dialog_t > 0.0:
		return
	_dialog_t = 0.2
	if _pcache == null or not is_instance_valid(_pcache):
		_pcache = get_tree().get_first_node_in_group("player")
	if _pcache == null:
		return
	var pp: Vector3 = _pcache.global_position
	for r in _residents:
		var lbl: Label3D = r["lbl"]
		if not is_instance_valid(lbl):
			continue
		var near: bool = (r["base"] as Vector3).distance_to(pp) < 6.0
		if near:
			if lbl.text == "" or randf() < 0.04:   # ~every 5s at 5Hz
				r["line_i"] = (int(r["line_i"]) + 1) % (r["lines"] as Array).size()
				lbl.text = str((r["lines"] as Array)[r["line_i"]])
		elif lbl.text != "":
			lbl.text = ""
