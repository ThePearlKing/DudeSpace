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
var _mouth_dir := Vector3.UP
var _mouth_e1 := Vector3.RIGHT

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

var _style := ""   # per-planet identity: wireframe / datamosh / pixel

func _wallc() -> Color:
	match _style:
		"wireframe": return Color("#0c1016")   # near-black, neon-lit
		"datamosh": return [Color("#232c24"), Color("#2c2331"),
			Color("#332a22"), Color("#20242c")][randi() % 4]   # glitch tints
		"pixel": return Color("#2c2438")       # chunky pastel dark
	return Color("#20242c")

func build(b, dir: Vector3) -> void:
	_b = b
	_style = str(b.kind)
	_mouth_dir = dir.normalized()
	var R: float = b.radius
	var C: Vector3 = b.center
	var u0 := dir.normalized()
	var e1 := u0.cross(Vector3(0, 0, 1))
	if e1.length() < 0.01:
		e1 = u0.cross(Vector3(1, 0, 0))
	e1 = e1.normalized()
	_mouth_e1 = e1
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
	# COLLAR: the mesh cut is a ragged triangle bigger than the shaft --
	# four wide plates seal the gap so nobody slips into the hollow
	for cspec in [[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, 3.4)],
			[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, -3.4)],
			[Vector3(0.6, 9.0, 14.0), Vector3(3.4, 0, 0)],
			[Vector3(0.6, 9.0, 14.0), Vector3(-3.4, 0, 0)]]:
		var cb9 := StaticBody3D.new()
		var ccs := CollisionShape3D.new()
		var cbs := BoxShape3D.new()
		cbs.size = cspec[0]
		ccs.shape = cbs
		cb9.add_child(ccs)
		add_child(cb9)
		cb9.global_transform = Transform3D(_bup(u0), C + u0 * (R - 2.5))
		cb9.translate_object_local(cspec[1])
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
			# crossing segments open their CEILING (the mouth shaft used
			# to dead-end on a corridor roof) and their FLOOR (the drop
			# chute to story two continues straight down)
			# THE FLOOR PLAN, finally thought through: rings run FULLY
			# sealed (no skipped segments, no gaps). At the two crossings
			# ring A keeps its tube but its side walls carry a corridor-
			# sized WINDOW (5.8m) exactly where ring B passes -- corners
			# seal themselves. Ring B yields its crossing segments; its
			# traffic walks ring A's floor for those 5.6 meters.
			var junction := i == 0 or i == NS / 2
			if junction and ering_v == e2:
				continue   # ring B yields at crossings
			var pod_side := 0
			if (i % 2 == 1) and not near_mouth and not junction:
				pod_side = 1 if (i / 2) % 2 == 0 else -1
			_tube_seg(C + pdir * r1, pdir, tang, 2.0 * PI * r1 / float(NS) + 0.8,
				_wallc(), accent, 2 if junction else pod_side,
				junction and i == 0, junction and i == 0)
			if pod_side != 0:
				_apartment(C, pdir, tang, r1, accent, pod_side)
	# STORY TWO: one ring, four cafeteria halls at the diagonals
	for i in NS:
		var ang := TAU * float(i) / float(NS)
		var pdir := (u0 * cos(ang) + e1 * sin(ang)).normalized()
		var tang := (-u0 * sin(ang) + e1 * cos(ang)).normalized()
		# the crossing opens BOTH ways (story-one hatch above, premium
		# core chute below); cafeteria segments open their floor too --
		# the halls are a LOWER FLOOR now, not side rooms
		var caf_here := i in [3, 10, 17, 24]
		_tube_seg(C + pdir * r2, pdir, tang, 2.0 * PI * r2 / float(NS) + 0.8,
			_wallc().darkened(0.2), accent, 0, i == 0, i == 0 or caf_here)
		if caf_here:
			_cafeteria(C, pdir, tang, r2, accent)
	# exit gate at the story-one crossing, back to the mouth's doorstep
	var out := Gate.new().configure({
		"target": C + u0 * (R + 1.5) + e1 * 9.0, "zone": "",
		"label": "COLONY EXIT", "color": accent, "cube": true})
	add_child(out)
	out.global_transform = Transform3D(_bup(u0),
		C + u0 * (r1 - 1.6) + (e1 + e2).normalized() * 2.1)
	# PREMIUM SUITES: a third, tiny ring hugging the core. Bigger rooms,
	# gold trim, a window slab facing the exact center of the planet.
	# location, location, location.
	# ONE core penthouse, directly under the chute -- four sealed suites
	# in a ring were unreachable (audit finding: no doors, chute ended
	# on a roof). The chute now lands THROUGH its ceiling hatch.
	var r3: float = maxf(10.0, R * 0.22)
	_premium(C, u0, e2, r3, accent)
	# drop chute continues: shaft three, story two -> the core ring
	for sspec3 in [[Vector3(0.5, 1.0, 6.0), Vector3(3.0, 0, 0)],
			[Vector3(0.5, 1.0, 6.0), Vector3(-3.0, 0, 0)],
			[Vector3(6.0, 1.0, 0.5), Vector3(0, 0, 3.0)],
			[Vector3(6.0, 1.0, 0.5), Vector3(0, 0, -3.0)]]:
		var wb3 := StaticBody3D.new()
		var mi3 := MeshInstance3D.new()
		var bm3 := BoxMesh.new()
		var ln3: float = (r2 - 2.6) - (r3 + 5.4)   # meets the penthouse roof
		bm3.size = Vector3(sspec3[0].x, ln3, sspec3[0].z)
		mi3.mesh = bm3
		mi3.material_override = Surfaces.metal(_wallc())
		wb3.add_child(mi3)
		var cs3 := CollisionShape3D.new()
		var bs3 := BoxShape3D.new()
		bs3.size = bm3.size
		cs3.shape = bs3
		wb3.add_child(cs3)
		add_child(wb3)
		wb3.global_transform = Transform3D(_bup(u0),
			C + u0 * ((r2 - 2.6 + r3 + 5.4) * 0.5))
		wb3.translate_object_local(Vector3(sspec3[1].x, 0, sspec3[1].z))
	var out2 := Gate.new().configure({
		"target": C + u0 * (R + 1.5) + e1 * 9.0, "zone": "",
		"label": "COLONY EXIT", "color": accent, "cube": true})
	add_child(out2)
	out2.global_transform = Transform3D(_bup(u0), C + u0 * (r2 - 1.6) + e1 * 2.3)

func _bup(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized()).orthonormalized()

## One corridor tube segment: floor, ceiling, two walls (one openable
## for pods), plus a ceiling light strip. Single body, four shapes.
func _tube_seg(center: Vector3, up: Vector3, along: Vector3, ln: float,
		wallc: Color, accent: Color, open_side: int, open_top: bool,
		open_floor: bool) -> void:
	var bas := Basis(up.cross(along).normalized(), up, along).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, center)
	var mat := Surfaces.metal(wallc)
	var parts: Array = []
	# open segments keep MOST of their slab: just a 5.2m hatch matching
	# the shaft, not the whole roof missing
	var hole := minf(5.2, ln - 2.0)
	var flank := (ln - hole) * 0.5
	if open_floor and flank > 0.3:
		parts.append([Vector3(5.6, 0.5, flank), Vector3(0, -2.2, (hole + flank) * 0.5)])
		parts.append([Vector3(5.6, 0.5, flank), Vector3(0, -2.2, -(hole + flank) * 0.5)])
	elif not open_floor:
		parts.append([Vector3(5.6, 0.5, ln), Vector3(0, -2.2, 0)])
	if open_top and flank > 0.3:
		parts.append([Vector3(5.6, 0.5, flank), Vector3(0, 2.2, (hole + flank) * 0.5)])
		parts.append([Vector3(5.6, 0.5, flank), Vector3(0, 2.2, -(hole + flank) * 0.5)])
	elif not open_top:
		parts.append([Vector3(5.6, 0.5, ln), Vector3(0, 2.2, 0)])
	# apartment segments get a real DOORWAY, not a missing wall: two
	# flanks, a header, and a glowing frame around a 1.8m opening.
	# open_side == 2 is a JUNCTION: both walls gone so the crossing
	# ring is walkable straight through -- the + turns at the +.
	for wsgn in [-1, 1]:
		if open_side == 2:
			# crossing window: wall flanks leave a 5.8m full-height
			# opening centered where the other ring's corridor passes
			var wfl := (ln - 5.8) * 0.5
			if wfl > 0.3:
				parts.append([Vector3(0.4, 4.9, wfl),
					Vector3(2.8 * float(wsgn), 0, (5.8 + wfl) * 0.5)])
				parts.append([Vector3(0.4, 4.9, wfl),
					Vector3(2.8 * float(wsgn), 0, -(5.8 + wfl) * 0.5)])
			continue
		elif open_side == wsgn:
			var dfl := (ln - 1.8) * 0.5
			parts.append([Vector3(0.4, 4.9, dfl),
				Vector3(2.8 * float(wsgn), 0, (1.8 + dfl) * 0.5)])
			parts.append([Vector3(0.4, 4.9, dfl),
				Vector3(2.8 * float(wsgn), 0, -(1.8 + dfl) * 0.5)])
			parts.append([Vector3(0.4, 1.3, 1.8),
				Vector3(2.8 * float(wsgn), 1.8, 0)])
		else:
			parts.append([Vector3(0.4, 4.9, ln), Vector3(2.8 * float(wsgn), 0, 0)])
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
	# ceiling light strip in the planet's accent -- unless the top is
	# open, in which case the shaft light does the talking
	if not open_top:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.5, 0.08, ln * 0.8)
		strip.mesh = sm
		strip.position = Vector3(0, 1.9, 0)
		strip.material_override = Destructible.make_material(accent, 2.2)
		body.add_child(strip)
	match _style:
		"wireframe":
			# glowing edge rails along the corners: the planet's grid
			# follows you inside
			for ex9 in [-2.6, 2.6]:
				for ey9 in [-1.95, 1.95]:
					var rail9 := MeshInstance3D.new()
					var rbm9 := BoxMesh.new()
					rbm9.size = Vector3(0.07, 0.07, ln)
					rail9.mesh = rbm9
					rail9.position = Vector3(ex9, ey9, 0)
					rail9.material_override = Destructible.make_material(accent, 1.4)
					body.add_child(rail9)
		"pixel":
			# checker floor tiles, big and proud
			var tile9 := MeshInstance3D.new()
			var tbm9 := BoxMesh.new()
			tbm9.size = Vector3(2.6, 0.08, ln * 0.5)
			tile9.mesh = tbm9
			tile9.position = Vector3(1.3, -1.92, 0)
			tile9.material_override = Destructible.make_material(
				Color("#ff66aa").darkened(0.3), 0.3)
			body.add_child(tile9)
		"datamosh":
			# one panel per segment sits WRONG. on purpose. probably.
			if randf() < 0.5:
				var gl9 := MeshInstance3D.new()
				var gbm9 := BoxMesh.new()
				gbm9.size = Vector3(0.3, 1.6, 1.6)
				gl9.mesh = gbm9
				gl9.position = Vector3(-2.5, 0.4, 0)
				gl9.rotation_degrees = Vector3(randf_range(-14, 14),
					randf_range(-14, 14), randf_range(-14, 14))
				gl9.material_override = Destructible.make_material(
					accent.darkened(0.4), 0.8)
				body.add_child(gl9)

## An apartment pod hanging off the ring's open side: five slabs, a
## sleep shelf, a desk, a lamp, and one resident who is doing fine.
func _apartment(C: Vector3, pdir: Vector3, tang: Vector3, r1: float,
		accent: Color, sgn: int = 1) -> void:
	var side := pdir.cross(tang).normalized() * float(sgn)
	var room_c := C + pdir * r1 + side * 7.8
	var bas := Basis(side, pdir, tang).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, room_c)
	# doorway TUNNEL collar: seals the sliver between corridor wall and
	# room wall so nothing slips into the raw planet between them
	for tcol in [[Vector3(1.2, 0.4, 2.6), Vector3(-4.55, 1.35, 0)],
			[Vector3(1.2, 0.4, 2.6), Vector3(-4.55, -2.35, 0)],
			[Vector3(1.2, 3.6, 0.4), Vector3(-4.55, -0.4, 1.35)],
			[Vector3(1.2, 3.6, 0.4), Vector3(-4.55, -0.4, -1.35)]]:
		var tb9 := StaticBody3D.new()
		var tm9 := MeshInstance3D.new()
		var tbm9 := BoxMesh.new()
		tbm9.size = tcol[0]
		tm9.mesh = tbm9
		tm9.material_override = Surfaces.metal(Color("#2a2f3a"))
		tb9.add_child(tm9)
		var tc9 := CollisionShape3D.new()
		var ts9 := BoxShape3D.new()
		ts9.size = tcol[0]
		tc9.shape = ts9
		tb9.add_child(tc9)
		body.add_child(tb9)
		tb9.position = tcol[1]
	# the DOOR: a glowing frame at the corridor end plus a slid-open
	# panel -- someone lives here and left it ajar
	for dpost in [-1.0, 1.0]:
		var dp := MeshInstance3D.new()
		var dpm := BoxMesh.new()
		dpm.size = Vector3(0.14, 3.4, 0.14)
		dp.mesh = dpm
		dp.position = Vector3(-4.9, -0.4, dpost * 1.0)
		dp.material_override = Destructible.make_material(accent, 1.5)
		body.add_child(dp)
	var doorp := MeshInstance3D.new()
	var doorm := BoxMesh.new()
	doorm.size = Vector3(0.12, 3.2, 1.2)
	doorp.mesh = doorm
	doorp.position = Vector3(-4.85, -0.5, 1.5)   # slid mostly open
	doorp.material_override = Surfaces.metal(Color("#3a4254"))
	body.add_child(doorp)
	var mat := Surfaces.plaster(Color("#2a2f3a"))
	for spec in [[Vector3(10.0, 0.5, 10.0), Vector3(0, -2.5, 0)],
			[Vector3(10.0, 0.5, 10.0), Vector3(0, 2.5, 0)],
			[Vector3(0.4, 5.5, 10.0), Vector3(4.8, 0, 0)],
			[Vector3(10.0, 5.5, 0.4), Vector3(0, 0, 4.8)],
			[Vector3(10.0, 5.5, 0.4), Vector3(0, 0, -4.8)]]:
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
	_tv(body, Vector3(4.5, -0.4, 2.8), Vector3(0, 0, 90))
	# living details: rug, ceiling fixture, wall art, shelf with glow
	# trinkets, a crystal plant -- someone LIVES here
	var rug := MeshInstance3D.new()
	var rugm := BoxMesh.new()
	rugm.size = Vector3(4.6, 0.06, 3.4)
	rug.mesh = rugm
	rug.position = Vector3(0.4, -2.2, 0.4)
	rug.material_override = Destructible.make_material(accent.darkened(0.55), 0.15)
	body.add_child(rug)
	var cl := MeshInstance3D.new()
	var clm := CylinderMesh.new()
	clm.top_radius = 0.7
	clm.bottom_radius = 0.7
	clm.height = 0.1
	cl.mesh = clm
	cl.position = Vector3(0, 2.15, 0)
	cl.material_override = Destructible.make_material(Color("#f2ead8"), 1.6)
	body.add_child(cl)
	for ai in 2:
		var art := MeshInstance3D.new()
		var artm := BoxMesh.new()
		artm.size = Vector3(0.08, 1.1, 1.4)
		art.mesh = artm
		art.position = Vector3(4.55, 0.4, -1.6 + 3.2 * float(ai))
		if _style == "datamosh" and ai == 1:
			art.rotation_degrees.x = 9.0   # one frame hangs WRONG. home.
		art.material_override = Destructible.make_material(
			accent.lerp(Color.WHITE, 0.25 * float(ai)), 0.7)
		body.add_child(art)
	for si2 in 2:
		var shl := MeshInstance3D.new()
		var shm2 := BoxMesh.new()
		shm2.size = Vector3(0.3, 0.08, 2.6)
		shl.mesh = shm2
		shl.position = Vector3(-4.5, 0.2 + 0.9 * float(si2), 2.6)
		shl.material_override = Surfaces.metal(Color("#3a4254"))
		body.add_child(shl)
		for bi3 in 2:
			var kn2 := MeshInstance3D.new()
			var knm2 := BoxMesh.new()
			knm2.size = Vector3(0.2, 0.24, 0.2)
			kn2.mesh = knm2
			kn2.position = Vector3(-4.5, 0.36 + 0.9 * float(si2),
				2.0 + 1.1 * float(bi3))
			kn2.material_override = Destructible.make_material(
				HUES[(si2 * 2 + bi3) % 4], 1.2)
			body.add_child(kn2)
	var plant := MeshInstance3D.new()
	var plm2 := CylinderMesh.new()
	plm2.top_radius = 0.0
	plm2.bottom_radius = 0.22
	plm2.height = 1.0
	plm2.radial_segments = 5
	plant.mesh = plm2
	plant.position = Vector3(4.1, -1.9, -4.1)
	plant.material_override = Destructible.make_material(accent, 0.9)
	body.add_child(plant)
	_spawn_resident(room_c + pdir * 0.4, pdir)

## A cafeteria hall: double-height, long tables, hanging light orbs,
## and residents mid-conversation about things you'd need a run-up for.
func _cafeteria(C: Vector3, pdir: Vector3, tang: Vector3, r2: float,
		accent: Color) -> void:
	# the hall hangs BELOW the ring: drop through the floor hatch, land
	# among the tables. A short chute bridges ring floor to hall roof.
	var side := pdir.cross(tang).normalized()
	var room_c := C + pdir * (r2 - 8.2)
	var bas := Basis(side, pdir, tang).orthonormalized()
	for cwall in [[Vector3(0.5, 3.6, 6.0), Vector3(3.0, 0, 0)],
			[Vector3(0.5, 3.6, 6.0), Vector3(-3.0, 0, 0)],
			[Vector3(6.0, 3.6, 0.5), Vector3(0, 0, 3.0)],
			[Vector3(6.0, 3.6, 0.5), Vector3(0, 0, -3.0)]]:
		var chb := StaticBody3D.new()
		var chm := MeshInstance3D.new()
		var chbm := BoxMesh.new()
		chbm.size = cwall[0]
		chm.mesh = chbm
		chm.material_override = Surfaces.metal(_wallc())
		chb.add_child(chm)
		var chc := CollisionShape3D.new()
		var chs := BoxShape3D.new()
		chs.size = cwall[0]
		chc.shape = chs
		chb.add_child(chc)
		add_child(chb)
		chb.global_transform = Transform3D(_bup(pdir), C + pdir * (r2 - 4.0))
		chb.translate_object_local(cwall[1])
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, room_c)
	var mat := Surfaces.plaster(Color("#232834"))
	var specs: Array = [[Vector3(16.0, 0.5, 16.0), Vector3(0, -3.0, 0)],
		[Vector3(0.4, 6.5, 16.0), Vector3(7.8, 0, 0)],
		[Vector3(0.4, 6.5, 16.0), Vector3(-7.8, 0, 0)],
		[Vector3(16.0, 6.5, 0.4), Vector3(0, 0, 7.8)],
		[Vector3(16.0, 6.5, 0.4), Vector3(0, 0, -7.8)],
		[Vector3(16.0, 0.5, 5.2), Vector3(0, 3.0, 5.4)],
		[Vector3(16.0, 0.5, 5.2), Vector3(0, 3.0, -5.4)],
		[Vector3(5.2, 0.5, 5.6), Vector3(-5.4, 3.0, 0)],
		[Vector3(5.2, 0.5, 5.6), Vector3(5.4, 3.0, 0)]]
	for spec in specs:
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
	# serving counter along one wall, bowls of something luminous
	var cnt := MeshInstance3D.new()
	var cntm := BoxMesh.new()
	cntm.size = Vector3(2.0, 1.1, 12.0)
	cnt.mesh = cntm
	cnt.position = Vector3(6.4, -2.4, 0)
	cnt.material_override = Surfaces.metal(Color("#454e62"))
	body.add_child(cnt)
	for bw in 4:
		var bwl := MeshInstance3D.new()
		var bwm := SphereMesh.new()
		bwm.radius = 0.34
		bwm.height = 0.34
		bwm.is_hemisphere = true
		bwl.mesh = bwm
		bwl.position = Vector3(6.4, -1.82, -4.5 + 3.0 * float(bw))
		bwl.material_override = Destructible.make_material(
			HUES[bw % 4].lightened(0.2), 1.4)
		body.add_child(bwl)
	for wy in 2:
		var stripe := MeshInstance3D.new()
		var stm2 := BoxMesh.new()
		stm2.size = Vector3(0.08, 0.16, 15.2)
		stripe.mesh = stm2
		stripe.position = Vector3(-7.7, -1.0 + 2.4 * float(wy), 0)
		stripe.material_override = Destructible.make_material(accent, 1.5)
		body.add_child(stripe)
	for ti in 3:
		var tb := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = Vector3(10.0, 0.25, 1.6)
		tb.mesh = tbm
		tb.position = Vector3(0, -1.9, -4.5 + 4.5 * float(ti))
		tb.material_override = Surfaces.metal(Color("#3a4254"))
		body.add_child(tb)
		# hanging FIXTURE: cord from the ceiling, smaller shade -- they
		# read as lamps now, not mystery spheres over dinner
		var cord := MeshInstance3D.new()
		var cdm := CylinderMesh.new()
		cdm.top_radius = 0.03
		cdm.bottom_radius = 0.03
		cdm.height = 0.7
		cord.mesh = cdm
		cord.position = Vector3(0, 2.55, -4.5 + 4.5 * float(ti))
		cord.material_override = Surfaces.metal(Color("#22262e"))
		body.add_child(cord)
		var orb := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.26
		om.height = 0.52
		orb.mesh = om
		orb.position = Vector3(0, 2.1, -4.5 + 4.5 * float(ti))
		orb.material_override = Destructible.make_material(accent, 2.6)
		body.add_child(orb)
	for ri in 3:
		_spawn_resident(room_c + pdir * 0.6
			+ tang * (-4.0 + 4.0 * float(ri)), pdir)
	# core gravity is INSANE: the lift takes you back UP to this hall's
	# own entrance in the ring corridor -- not all the way topside
	var lift := Gate.new().configure({
		"target": C + pdir * (r2 - 1.0), "zone": "",
		"label": "BACK UP", "color": accent, "cube": true})
	add_child(lift)
	lift.global_transform = Transform3D(bas, room_c)
	lift.translate_object_local(Vector3(-6.4, -2.6, 6.4))

## A premium core suite: double the floor, gold trim, a glass slab in
## the floor looking at the naked center of the planet.
func _premium(C: Vector3, pdir: Vector3, tang: Vector3, r3: float,
		accent: Color) -> void:
	var side := pdir.cross(tang).normalized()
	var room_c := C + pdir * (r3 + 3.0)
	var bas := Basis(side, pdir, tang).orthonormalized()
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(bas, room_c)
	var mat := Surfaces.plaster(Color("#2e2a3a"))
	# ceiling in four pieces around a 5.2m landing hatch
	for spec in [[Vector3(10.0, 0.5, 10.0), Vector3(0, -2.6, 0)],
			[Vector3(10.0, 0.5, 2.4), Vector3(0, 2.6, 3.8)],
			[Vector3(10.0, 0.5, 2.4), Vector3(0, 2.6, -3.8)],
			[Vector3(2.4, 0.5, 5.2), Vector3(-3.8, 2.6, 0)],
			[Vector3(2.4, 0.5, 5.2), Vector3(3.8, 2.6, 0)],
			[Vector3(0.4, 5.7, 10.0), Vector3(4.8, 0, 0)],
			[Vector3(0.4, 5.7, 10.0), Vector3(-4.8, 0, 0)],
			[Vector3(10.0, 5.7, 0.4), Vector3(0, 0, 4.8)],
			[Vector3(10.0, 5.7, 0.4), Vector3(0, 0, -4.8)]]:
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
	for gy in [-2.3, 2.3]:
		var trim := MeshInstance3D.new()
		var trm := BoxMesh.new()
		trm.size = Vector3(9.6, 0.1, 0.1)
		trim.mesh = trm
		trim.position = Vector3(0, gy, 4.6)
		trim.material_override = Destructible.make_material(Color("#ffd94a"), 1.2)
		body.add_child(trim)
	# the TRAPDOOR: a glowing grate lying across the ceiling hatch --
	# no collision, you drop straight through the flap
	for gb2 in 4:
		var bar9 := MeshInstance3D.new()
		var brm9 := BoxMesh.new()
		brm9.size = Vector3(5.0, 0.06, 0.18)
		bar9.mesh = brm9
		bar9.position = Vector3(0, 2.62, -1.9 + 1.25 * float(gb2))
		bar9.material_override = Destructible.make_material(accent, 1.1)
		body.add_child(bar9)
	var glass := MeshInstance3D.new()
	var glm := BoxMesh.new()
	glm.size = Vector3(3.4, 0.15, 3.4)
	glass.mesh = glm
	glass.position = Vector3(0, -2.45, 0)
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.6, 0.8, 1.0, 0.18)
	glass.material_override = gmat
	body.add_child(glass)
	for fspec in [[Vector3(3.4, 0.4, 2.0), Vector3(2.6, -2.1, -3.0), Color("#4a4266"), 0.15],
			[Vector3(4.0, 0.14, 1.2), Vector3(2.4, -1.1, 3.2), Color("#5a5276"), 0.1],
			[Vector3(0.32, 1.1, 0.32), Vector3(-3.8, -1.8, 3.8), accent, 2.0],
			[Vector3(0.32, 1.1, 0.32), Vector3(-3.8, -1.8, -3.8), accent, 2.0]]:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = fspec[0]
		f.mesh = fm
		f.position = fspec[1]
		f.material_override = Destructible.make_material(fspec[2], float(fspec[3]))
		body.add_child(f)
	_tv(body, Vector3(4.5, -0.6, 0), Vector3(0, 0, 90))
	# back up to the story-two junction you dropped in from
	var lift2 := Gate.new().configure({
		"target": _b.center + _mouth_dir * (float(_b.radius) - 25.0), "zone": "",
		"label": "BACK UP", "color": accent, "cube": true})
	add_child(lift2)
	lift2.global_transform = Transform3D(bas, room_c)
	lift2.translate_object_local(Vector3(3.8, -2.7, -3.8))
	_spawn_resident(room_c + pdir * 0.4, pdir)

## Apartment television: a shared colony feed of the Datamosh studio
## (one SubViewport for the WHOLE colony, proximity-gated) or a
## procedural test-pattern channel. It only renders with someone there.
func _tv(body: Node3D, at: Vector3, rot: Vector3) -> void:
	var frame := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(0.12, 0.9, 1.4)
	frame.mesh = fbm
	frame.position = at
	frame.rotation_degrees = rot
	frame.material_override = Surfaces.metal(Color("#14171c"))
	body.add_child(frame)
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.24, 0.74)
	scr.mesh = qm
	scr.position = Vector3(-0.08, 0, 0)
	scr.rotation_degrees = Vector3(0, 90, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if randf() < 0.6:
		_ensure_tv_feed()
		m.albedo_texture = _tv_vp.get_texture()
		scr.material_override = m
	else:
		# the other channel: scrolling colour bars with a rolling glitch
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded;
void fragment(){
	float band = floor(fract(UV.x + TIME * 0.03) * 7.0);
	vec3 col = vec3(fract(band * 0.37), fract(band * 0.61), fract(band * 0.83));
	float roll = step(0.97, fract(UV.y * 1.0 - TIME * 0.4));
	ALBEDO = mix(col * 0.8, vec3(1.0), roll);
}
"""
		var sm2 := ShaderMaterial.new()
		sm2.shader = sh
		scr.material_override = sm2
	frame.add_child(scr)

var _tv_vp: SubViewport = null

func _ensure_tv_feed() -> void:
	if _tv_vp != null:
		return
	_tv_vp = SubViewport.new()
	_tv_vp.size = Vector2i(220, 130)
	_tv_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_tv_vp)
	_tv_vp.world_3d = get_viewport().world_3d if is_inside_tree() else null
	var cam := Camera3D.new()
	_tv_vp.add_child(cam)
	cam.global_position = DatamoshStudio.POS + Vector3(0, 0.4, 3.5)
	cam.look_at(DatamoshStudio.POS + Vector3(0, -0.6, -4.2), Vector3.UP)
	cam.cull_mask = 0xFFFFF & ~(1 << 9)

func _spawn_resident(at: Vector3, up: Vector3) -> void:
	var a := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 0.55
	am.height = 1.1
	am.radial_segments = 5
	am.rings = 3
	a.mesh = am
	# the SAME fluid glow the studio anchors wear -- they're one species
	var rhue := Color.from_hsv(randf(), randf_range(0.55, 0.9), 1.0)
	a.material_override = DatamoshStudio._fluid_material(rhue)
	add_child(a)
	a.global_transform = Transform3D(_bup(up), at)
	# EXACT studio bubble spec: same font, scale, outline, colour
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 26
	lbl.pixel_size = 0.006
	lbl.modulate = rhue
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.text = ""
	a.add_child(lbl)
	lbl.position = Vector3(0, 1.1, 0)
	var lines := WISDOM.duplicate()
	lines.shuffle()
	# every resident gets its OWN voice, rolled fresh -- same species as
	# the news desk, not the same four throats
	var prof: Dictionary = {"base": randf_range(140.0, 380.0),
		"var": randf_range(0.1, 0.5),
		"wave": ["sine", "square", "saw"][randi() % 3],
		"rate": randf_range(0.9, 1.5), "artic": randf_range(1.3, 2.0)}
	var shell := _ResShell.new()
	shell.colony = self
	shell.ridx = _residents.size()
	var shc := CollisionShape3D.new()
	var shs := SphereShape3D.new()
	shs.radius = 0.7
	shc.shape = shs
	shell.add_child(shc)
	a.add_child(shell)
	_residents.append({"node": a, "base": at, "phase": randf() * TAU,
		"lbl": lbl, "lines": lines, "line_i": randi() % lines.size(), "up": up,
		"voice": prof, "full": "", "say": null, "flash": 0.0})

func _process(delta: float) -> void:
	# residents bob gently, always
	var t := Time.get_ticks_msec() / 1000.0
	for r in _residents:
		var nd: Node3D = r["node"]
		if is_instance_valid(nd):
			nd.global_position = (r["base"] as Vector3) \
				+ (r["up"] as Vector3) * sin(t * 0.9 + float(r["phase"])) * 0.18
			nd.rotate_object_local(Vector3.UP, delta * 0.4)
			# hit flash rides the fluid shader's amp, then settles
			if float(r.get("flash", 0.0)) > 0.0:
				r["flash"] = maxf(0.0, float(r["flash"]) - delta)
				var fm9 = (nd as MeshInstance3D).material_override
				if fm9 is ShaderMaterial:
					(fm9 as ShaderMaterial).set_shader_parameter("amp",
						1.0 + float(r["flash"]) * 45.0)
			# the name text hangs along GRAVITY's up, explicitly -- not
			# whatever +Y the parent happens to think it has
			var lb9: Label3D = r["lbl"]
			if is_instance_valid(lb9):
				lb9.global_position = nd.global_position + (r["up"] as Vector3) * 1.1
	# dialog: the nearest resident to the player speaks, rotating
	# through its shuffled deck. checked at 5Hz, not per frame.
	_dialog_t -= delta
	if _dialog_t > 0.0:
		return
	_dialog_t = 0.2
	# TV feed only renders with someone in the colony -- 220x130 once,
	# shared by every screen, off the moment you leave the planet
	if _tv_vp != null and _b != null:
		var pv = get_tree().get_first_node_in_group("player")
		var inside: bool = pv != null and pv.global_position.distance_to(
			_b.center) < float(_b.radius) + 4.0
		_tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if inside \
			else SubViewport.UPDATE_DISABLED
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
		var sp = r["say"]
		if near:
			# letter-by-letter reveal riding the voice, studio style
			if sp != null and is_instance_valid(sp) and sp.playing \
					and sp.stream != null:
				var frac: float = clampf(sp.get_playback_position() \
					/ maxf(0.2, sp.stream.get_length() * 0.9), 0.0, 1.0)
				lbl.text = str(r["full"]).substr(0,
					int(float(str(r["full"]).length()) * frac))
			elif str(r["full"]) != "" and lbl.text != str(r["full"]):
				lbl.text = str(r["full"])
			if str(r["full"]) == "" or (randf() < 0.04 \
					and (sp == null or not is_instance_valid(sp) or not sp.playing)):
				var line := _wise_line()
				r["full"] = line
				lbl.text = ""
				if not _cooking_say:
					_cooking_say = true
					var prof: Dictionary = r["voice"]
					WorkerThreadPool.add_task(func() -> void:
						var w = HumanVoice.render(line, prof)
						_say_ready.call_deferred(r, w))
		else:
			if lbl.text != "":
				lbl.text = ""
			r["full"] = ""
			if sp != null and is_instance_valid(sp):
				sp.queue_free()
				r["say"] = null

## Resident dialog is COMPOSED, not recited: 40% classics (the starter
## home line lives forever), 60% assembled fresh from the show's own
## vocabulary. Casually above you, never mean about it.
const WISE_T := [
	"we discussed %s at breakfast. it went %s. we let it.",
	"the %s is %s. we checked. twice. both answers were right.",
	"i thought about %s for nine seconds today. a heavy day.",
	"%s called. it wants advice about %s. we said: be round about it.",
	"your %s is a lovely starter %s.",
	"we predicted %s would end up %s. it did. we clapped politely.",
	"the cafeteria soup tastes like %s tonight. this is considered lucky.",
	"somewhere, %s is %s. we find that comforting. you should too.",
]
const WISE_FILL_A := ["the black hole", "your sun", "the fork", "gravity",
	"the tesselation", "entropy", "the noodle broadcast", "your rocket",
	"the third dimension", "the horizon"]

func _wise_line() -> String:
	if randf() < 0.4:
		return WISDOM[randi() % WISDOM.size()]
	var t: String = WISE_T[randi() % WISE_T.size()]
	var c := t.count("%s")
	if c == 0:
		return t
	var fills: Array = []
	for i in c:
		if randf() < 0.5:
			fills.append(WISE_FILL_A[randi() % WISE_FILL_A.size()])
		elif randf() < 0.5:
			fills.append(RadioLib.AP_STATES[randi() % RadioLib.AP_STATES.size()])
		else:
			fills.append(RadioLib.AP_VERDICTS[randi() % RadioLib.AP_VERDICTS.size()])
	return t % fills

## Bullets treat residents like the news desk treats them: deflected
## with a ping, a flash of the fluid glow, a voice jitter, and -- if
## you keep it up -- commentary.
class _ResShell extends StaticBody3D:
	var colony = null
	var ridx := -1
	func destroy(_push: Vector3) -> void:
		if colony != null:
			colony.resident_hit(ridx)

const RES_OW := ["ow. statistically.",
	"we felt that in dimensions you don't rent.",
	"this is a RESIDENCE. the news desk gets paid for that. we don't.",
	"noted. forever.",
	"the soup will remember this.",
	"violence. in MY apartment ring. bold.",
	"your bullet has been recycled into an opinion."]

var _ping_wav: AudioStreamWAV = null

func _colony_ping(at: Vector3) -> void:
	if _ping_wav == null:
		var n9 := int(0.14 * 22050)
		var bytes := PackedByteArray()
		bytes.resize(n9 * 2)
		for i in n9:
			var t := float(i) / 22050.0
			var v := (sin(TAU * 1900.0 * t) * 0.5 + sin(TAU * 2640.0 * t) * 0.35) \
				* exp(-t * 26.0)
			bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 22000.0))
		_ping_wav = AudioStreamWAV.new()
		_ping_wav.format = AudioStreamWAV.FORMAT_16_BITS
		_ping_wav.mix_rate = 22050
		_ping_wav.data = bytes
	var p := AudioStreamPlayer3D.new()
	p.stream = _ping_wav
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)

func resident_hit(i: int) -> void:
	if i < 0 or i >= _residents.size():
		return
	var r: Dictionary = _residents[i]
	var nd = r.get("node")
	if nd == null or not is_instance_valid(nd):
		return
	_colony_ping((nd as Node3D).global_position)
	r["flash"] = 0.15
	var sp = r.get("say")
	if sp != null and is_instance_valid(sp) and sp.playing:
		sp.pitch_scale = randf_range(0.55, 1.7)
		get_tree().create_timer(0.06).timeout.connect(func() -> void:
			if is_instance_valid(sp):
				sp.pitch_scale = 1.0)
	if randf() < 0.35 and not _cooking_say:
		var line := str(RES_OW[randi() % RES_OW.size()])
		r["full"] = line
		var prof: Dictionary = r["voice"]
		_cooking_say = true
		WorkerThreadPool.add_task(func() -> void:
			var w = HumanVoice.render(line, prof)
			_say_ready.call_deferred(r, w))

var _cooking_say := false

func _say_ready(r: Dictionary, wav) -> void:
	_cooking_say = false
	if Game.quitting or wav == null:
		return
	var nd = r.get("node")
	if nd == null or not is_instance_valid(nd):
		return
	var old = r.get("say")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var sp := AudioStreamPlayer3D.new()
	sp.stream = wav
	sp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	sp.unit_size = 2.5
	sp.max_distance = 16.0
	sp.max_db = -6.0
	sp.volume_db = -8.0
	if AudioServer.get_bus_index("Voice") >= 0:
		sp.bus = "Voice"
	(nd as Node3D).add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)
	r["say"] = sp
