class_name EMachines
extends RefCounted
## The electric machine family. All extend Machine; wire them together
## with the Wiring Tool (energy) and Funnel Tool (items).

## Burns coal -> energy.
class Generator extends Machine:
	var _vent: MeshInstance3D
	func _init() -> void:
		title = "GENERATOR"
		box_color = Color("#3a3a4a")
		refund_id = "generator"
		shows_out = false   # coal in, EU out, no items back
		buf_cap = 200.0
	func _ready() -> void:
		super._ready()
		dress_industrial()
		# twin exhaust stacks with soot caps
		for off in [Vector3(0.4, 0, 0.3), Vector3(0.1, 0, 0.3)]:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.13
			cm.bottom_radius = 0.19
			cm.height = 1.0 + off.x
			part(cm, Vector3(off.x, box_size.y + (1.0 + off.x) * 0.5, off.z), Color("#22222a"), 0.1)
			var capm := CylinderMesh.new()
			capm.top_radius = 0.2
			capm.bottom_radius = 0.2
			capm.height = 0.07
			part(capm, Vector3(off.x, box_size.y + 1.04 + off.x, off.z), Color("#121218"), 0.02)
		# hot vent grille + piston housing + intake pipe
		_vent = part(_grille(), Vector3(0, 0.6, -box_size.z * 0.5 - 0.04), Color("#ff7a1a"), 0.5)
		var piston := BoxMesh.new()
		piston.size = Vector3(0.7, 0.5, 0.5)
		part(piston, Vector3(-0.35, box_size.y + 0.25, -0.25), Color("#30303c"), 0.1)
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.1
		pipe.bottom_radius = 0.1
		pipe.height = 0.9
		part(pipe, Vector3(box_size.x * 0.5 + 0.02, 0.75, 0), Color("#2a2a34"), 0.1,
			Vector3(0, 0, 90))
	static func _grille() -> BoxMesh:
		var vm := BoxMesh.new()
		vm.size = Vector3(0.9, 0.5, 0.06)
		return vm
	func work(_d: float) -> void:
		if _vent and _vent.material_override is StandardMaterial3D:
			_vent.material_override.emission_energy_multiplier = 0.4 + (buf / buf_cap) * 4.0
		if str(in_slot["id"]) == "coal" and int(in_slot["n"]) > 0 and buf <= buf_cap - 25.0:
			in_slot["n"] = int(in_slot["n"]) - 1
			if int(in_slot["n"]) <= 0:
				in_slot = {"id": "", "n": 0}
			buf += 25.0
			Sfx.play("smelt", -20.0)
	func accepts(id: String) -> bool:
		return id == "coal"
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\ncoal in: %s\n1 coal -> 25 EU" % [buf, buf_cap, Inventory.slot_text(in_slot)]
	func actions() -> Array:
		return []

## Slowly digs coal out of whatever it's standing on.
class CoalDrill extends Machine:
	var _t := 0.0
	var _bit: MeshInstance3D
	func _init() -> void:
		title = "COAL DRILL"
		box_color = Color("#2a2a30")
		refund_id = "coaldrill"
		shows_in = false
	func _ready() -> void:
		super._ready()
		dress_industrial()
		_bit = MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.3
		bm.bottom_radius = 0.05
		bm.height = 0.9
		_bit.mesh = bm
		_bit.position = Vector3(0, -0.35, 0)
		_bit.material_override = Destructible.make_material(Color("#8a8a96"), 0.6)
		add_child(_bit)
		# derrick: four angled struts meeting over the drill axis + motor head
		for ang in [0.0, 90.0, 180.0, 270.0]:
			var strut := BoxMesh.new()
			strut.size = Vector3(0.09, 1.6, 0.09)
			var a := deg_to_rad(ang)
			part(strut, Vector3(cos(a) * 0.55, box_size.y + 0.55, sin(a) * 0.55),
				Color("#3a3a44"), 0.08, Vector3(cos(a) * -24.0, 0, sin(a) * 24.0))
		var motor := BoxMesh.new()
		motor.size = Vector3(0.5, 0.4, 0.5)
		part(motor, Vector3(0, box_size.y + 1.25, 0), Color("#2a2a32"), 0.1)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.07
		shaft.bottom_radius = 0.07
		shaft.height = 1.2
		part(shaft, Vector3(0, box_size.y + 0.6, 0), Color("#8a8a96"), 0.3)
	func _process(delta: float) -> void:
		super._process(delta)
		if _bit:
			_bit.rotate_y(delta * 9.0)
	func work(d: float) -> void:
		_t += d
		if _t >= 5.0:
			_t = 0.0
			if str(out_slot["id"]) == "" or str(out_slot["id"]) == "coal":
				out_slot = {"id": "coal", "n": int(out_slot.get("n", 0)) + 1}
	func info_text() -> String:
		return "coal out: %s\ndigs 1 coal / 5s" % Inventory.slot_text(out_slot)
	func actions() -> Array:
		return []

## Organic matter in, energy out. The apple is worth a LOT. Coward.
class Bioreactor extends Machine:
	const FUEL := {"meat": 15.0, "cooked_meat": 10.0, "banana": 8.0,
		"plantfiber": 4.0, "shroom": 6.0, "salad": 30.0, "permapple": 500.0}
	var _dome: MeshInstance3D
	var _puls: float = 0.0
	func _init() -> void:
		title = "BIOREACTOR"
		box_color = Color("#2a5a30")
		refund_id = "bioreactor"
		shows_out = false
		buf_cap = 300.0
	func _ready() -> void:
		super._ready()
		_dome = MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = 0.55
		dm.height = 1.1
		dm.is_hemisphere = true
		_dome.mesh = dm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.2, 0.9, 0.4, 0.45)
		mat.emission_enabled = true
		mat.emission = Color("#2bff5a")
		mat.emission_energy_multiplier = 1.0
		_dome.material_override = mat
		_dome.position = Vector3(0, box_size.y, 0)
		add_child(_dome)
		dress_industrial(Color("#1a3a20"))
		# nutrient pipes climbing the sides into the dome
		for sx in [-1.0, 1.0]:
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.09
			pipe.bottom_radius = 0.09
			pipe.height = box_size.y + 0.3
			part(pipe, Vector3(sx * (box_size.x * 0.5 - 0.1), (box_size.y + 0.3) * 0.5,
				box_size.z * 0.4), Color("#2f7d42"), 0.4)
			var elbow := SphereMesh.new()
			elbow.radius = 0.12
			elbow.height = 0.24
			part(elbow, Vector3(sx * (box_size.x * 0.5 - 0.1), box_size.y + 0.3,
				box_size.z * 0.4), Color("#2f7d42"), 0.4)
		# feed hopper on the front
		var hop := CylinderMesh.new()
		hop.top_radius = 0.3
		hop.bottom_radius = 0.12
		hop.height = 0.45
		part(hop, Vector3(0, box_size.y * 0.75, box_size.z * 0.5 + 0.16), Color("#234a2c"), 0.15)
	func _process(delta: float) -> void:
		super._process(delta)
		_puls += delta * (1.0 + buf / buf_cap * 6.0)
		if _dome:
			_dome.scale = Vector3.ONE * (1.0 + sin(_puls) * 0.08)   # it bubbles
	func work(_d: float) -> void:
		var id := str(in_slot["id"])
		if FUEL.has(id) and int(in_slot["n"]) > 0 and buf <= buf_cap - float(FUEL[id]):
			in_slot["n"] = int(in_slot["n"]) - 1
			if int(in_slot["n"]) <= 0:
				in_slot = {"id": "", "n": 0}
			buf += float(FUEL[id])
	func accepts(id: String) -> bool:
		return FUEL.has(id)
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\nfeed: %s\nmeat 15 · salad 30 · apple 500" % [buf, buf_cap, Inventory.slot_text(in_slot)]
	func actions() -> Array:
		return []

## Nuclear RTG: crafted around ultima crystals; trickles power forever.
class RTG extends Machine:
	var _core: MeshInstance3D
	var _spin: float = 0.0
	func _init() -> void:
		title = "RTG"
		box_color = Color("#1a4a4a")
		refund_id = "rtg"
		shows_in = false
		shows_out = false
		buf_cap = 150.0
		gen_rate = 2.0
	func _ready() -> void:
		super._ready()
		_core = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.35
		tm.outer_radius = 0.55
		_core.mesh = tm
		_core.material_override = Destructible.make_material(Color("#7df9ff"), 5.0)
		_core.position = Vector3(0, box_size.y + 0.5, 0)
		add_child(_core)
		dress_industrial(Color("#12303a"))
		# radiator fins fanned around the body -- it sheds heat forever
		for ang in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
			var fin := BoxMesh.new()
			fin.size = Vector3(0.05, box_size.y * 0.8, 0.42)
			var a := deg_to_rad(ang)
			part(fin, Vector3(cos(a) * (box_size.x * 0.5 + 0.18), box_size.y * 0.5,
				sin(a) * (box_size.z * 0.5 + 0.18)), Color("#2a5a66"), 0.4,
				Vector3(0, -ang, 0))
		# warning collar under the halo
		var collar := CylinderMesh.new()
		collar.top_radius = 0.3
		collar.bottom_radius = 0.34
		collar.height = 0.24
		part(collar, Vector3(0, box_size.y + 0.12, 0), Color("#ffd166"), 0.8)
	func _process(delta: float) -> void:
		super._process(delta)
		if _core:
			_core.rotate_y(delta * 1.2)
			_core.rotate_x(delta * 0.7)   # ominous nuclear halo
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\n+2 EU/s. forever. it hums." % [buf, buf_cap]

## Prism Reactor: shader-system exclusive. A caged rainbow shard that
## bends light into a fat 8 EU/s. The late-game generator.
class PrismReactor extends Machine:
	var _shard: MeshInstance3D
	var _smat: StandardMaterial3D
	var _hue: float = 0.0
	func _init() -> void:
		title = "PRISM REACTOR"
		box_color = Color("#2a1a3a")
		refund_id = "prisreactor"
		shows_in = false
		shows_out = false
		buf_cap = 400.0
		gen_rate = 8.0
	func _ready() -> void:
		super._ready()
		_shard = MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7, 1.1, 0.7)
		_shard.mesh = pm
		_smat = Destructible.make_material(Color("#ff7ce9"), 4.0)
		_shard.material_override = _smat
		_shard.position = Vector3(0, box_size.y + 0.75, 0)
		add_child(_shard)
		dress_industrial(Color("#1a1028"))
		# full cage around the shard + crown ring: contained rainbow
		for ang in [0.0, 90.0, 180.0, 270.0]:
			var a := deg_to_rad(ang)
			var bm := CylinderMesh.new()
			bm.top_radius = 0.05
			bm.bottom_radius = 0.05
			bm.height = 1.6
			part(bm, Vector3(cos(a) * 0.55, box_size.y + 0.7, sin(a) * 0.55), Color("#444455"), 0.2)
		var crown := TorusMesh.new()
		crown.inner_radius = 0.5
		crown.outer_radius = 0.62
		part(crown, Vector3(0, box_size.y + 1.5, 0), Color("#444455"), 0.2)
		# light-bleed vents on the body
		for sx in [-1.0, 1.0]:
			var vent := BoxMesh.new()
			vent.size = Vector3(0.06, 0.7, 0.5)
			part(vent, Vector3(sx * (box_size.x * 0.5 + 0.01), box_size.y * 0.5, 0),
				Color("#ff7ce9"), 1.2)
	func _process(delta: float) -> void:
		super._process(delta)
		if _shard:
			_shard.rotate_y(delta * 2.0)
			_hue = fmod(_hue + delta * 0.25, 1.0)
			_smat.emission = Color.from_hsv(_hue, 0.6, 1.0)   # slow rainbow cycle
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\n+8 EU/s. tastes like colours." % [buf, buf_cap]

## WARP PAD: the fast-travel network. Charge it full, pay 2000 coins,
## step across the universe. Name yours; pick a destination waystone-style.
class Teleporter extends Machine:
	const TP_COINS := 2000
	var tname: String = "WARP PAD"
	var _ring2: MeshInstance3D
	func _init() -> void:
		title = "WARP PAD"
		box_color = Color("#1a2a4a")
		box_size = Vector3(2.2, 0.5, 2.2)
		refund_id = "teleporter"
		shows_in = false
		shows_out = false
		buf_cap = 1000.0
	func _ready() -> void:
		super._ready()
		add_to_group("teleporter")
		_ring2 = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75
		tm.outer_radius = 1.0
		_ring2.mesh = tm
		_ring2.material_override = Destructible.make_material(Color("#7cf9ff"), 2.0)
		_ring2.position = Vector3(0, 1.2, 0)
		add_child(_ring2)
		# waystone pylons at the pad corners + inlaid glowing runway ring
		for ang in [45.0, 135.0, 225.0, 315.0]:
			var a := deg_to_rad(ang)
			var py := BoxMesh.new()
			py.size = Vector3(0.18, 1.1, 0.18)
			part(py, Vector3(cos(a) * 1.25, 0.55, sin(a) * 1.25), Color("#243a5e"), 0.2)
			var tip := SphereMesh.new()
			tip.radius = 0.12
			tip.height = 0.24
			part(tip, Vector3(cos(a) * 1.25, 1.16, sin(a) * 1.25), Color("#7cf9ff"), 2.5)
		var inlay := TorusMesh.new()
		inlay.inner_radius = 0.85
		inlay.outer_radius = 0.97
		var ring := part(inlay, Vector3(0, box_size.y + 0.02, 0), Color("#7cf9ff"), 1.4)
		ring.scale = Vector3(1, 0.08, 1)
	func _process(delta: float) -> void:
		super._process(delta)
		if _ring2:
			_ring2.rotate_y(delta * (0.3 + 3.0 * buf / buf_cap))
			_ring2.position.y = 1.2 + sin(Time.get_ticks_msec() / 400.0) * 0.15
	func use() -> void:
		var ui = get_tree().get_first_node_in_group("teleport_ui")
		if ui and ui.has_method("open_pad"):
			ui.open_pad(self)
	func info_text() -> String:
		return "%s\ncharge: %.0f / %.0f EU\nfull charge + %d coins = one warp" % [tname, buf, buf_cap, TP_COINS]

## EXTENDER: a relay pole. Power flows in and out, items funnel in and
## out. Exists purely to stretch your network across the terrain.
class Extender extends Machine:
	func _init() -> void:
		title = "EXTENDER"
		box_color = Color("#4a5560")
		box_size = Vector3(0.7, 0.7, 0.7)
		refund_id = "extender"
		buf_cap = 100.0
	func _ready() -> void:
		super._ready()
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.07
		pm.bottom_radius = 0.09
		pm.height = 2.2
		pole.mesh = pm
		pole.position = Vector3(0, 1.5, 0)
		pole.material_override = Destructible.make_material(Color("#3a3f46"), 0.15)
		add_child(pole)
		for i in 3:   # insulator rings
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.09
			tm.outer_radius = 0.16
			ring.mesh = tm
			ring.material_override = Destructible.make_material(Color("#5ad0ff"), 1.2)
			ring.position = Vector3(0, 1.7 + float(i) * 0.35, 0)
			add_child(ring)
		# crossarm + guy-wire anchors: a proper utility pole, not a stick
		var arm := BoxMesh.new()
		arm.size = Vector3(1.1, 0.09, 0.09)
		part(arm, Vector3(0, 2.35, 0), Color("#3a3f46"), 0.15)
		for sx in [-1.0, 1.0]:
			var anchor := BoxMesh.new()
			anchor.size = Vector3(0.14, 0.1, 0.14)
			part(anchor, Vector3(sx * 0.52, 2.42, 0), Color("#5ad0ff"), 0.9)
			var stay := CylinderMesh.new()
			stay.top_radius = 0.02
			stay.bottom_radius = 0.02
			stay.height = 1.3
			part(stay, Vector3(sx * 0.35, 0.6, 0.25), Color("#23262c"), 0.05,
				Vector3(0, 0, sx * -28.0))
	func work(_d: float) -> void:
		# items pass straight through: in -> out, funnels take it from there
		if str(in_slot["id"]) != "" and int(in_slot["n"]) > 0:
			var id := str(in_slot["id"])
			if str(out_slot["id"]) == "":
				out_slot = {"id": id, "n": int(in_slot["n"])}
				in_slot = {"id": "", "n": 0}
			elif str(out_slot["id"]) == id:
				out_slot["n"] = int(out_slot["n"]) + int(in_slot["n"])
				in_slot = {"id": "", "n": 0}
	func accepts(_id: String) -> bool:
		return true
	func info_text() -> String:
		return "relay: %.0f / %.0f EU\npassing: %s" % [buf, buf_cap, Inventory.slot_text(out_slot)]

## Shared capacitor look: transparent black shell, coloured edge outline,
## and a green charge core that visibly fills with stored energy.
static func cap_visual(m: Machine, outline: Color) -> MeshInstance3D:
	# shell: see-through black (keep it as _mat so selection glow works)
	var shell := StandardMaterial3D.new()
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.albedo_color = Color(0.0, 0.0, 0.0, 0.4)
	shell.emission_enabled = true
	shell.emission = Color(0, 0, 0)
	shell.roughness = 0.15
	m._mesh.material_override = shell
	m._mat = shell
	# edge outline: the 12 box edges
	var s: Vector3 = m.box_size * 0.5
	var yc: float = m.box_size.y * 0.5
	var pts := [
		Vector3(-s.x, -s.y, -s.z), Vector3(s.x, -s.y, -s.z),
		Vector3(s.x, -s.y, s.z), Vector3(-s.x, -s.y, s.z),
		Vector3(-s.x, s.y, -s.z), Vector3(s.x, s.y, -s.z),
		Vector3(s.x, s.y, s.z), Vector3(-s.x, s.y, s.z),
	]
	var edges := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.emission_enabled = true
	emat.emission = outline
	emat.emission_energy_multiplier = 1.6
	emat.albedo_color = outline
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, emat)
	for e in edges:
		im.surface_add_vertex(pts[e[0]] + Vector3(0, yc, 0))
		im.surface_add_vertex(pts[e[1]] + Vector3(0, yc, 0))
	im.surface_end()
	mi.mesh = im
	m.add_child(mi)
	# the green charge core
	var fill := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(m.box_size.x * 0.8, 1.0, m.box_size.z * 0.8)
	fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(0.15, 1.0, 0.35, 0.75)
	fmat.emission_enabled = true
	fmat.emission = Color("#2bff5a")
	fmat.emission_energy_multiplier = 1.8
	fill.material_override = fmat
	m.add_child(fill)
	return fill

static func cap_update_fill(m: Machine, fill: MeshInstance3D) -> void:
	if fill == null:
		return
	var ratio: float = clampf(m.buf / maxf(1.0, m.buf_cap), 0.001, 1.0)
	var h: float = (m.box_size.y * 0.92) * ratio
	fill.scale = Vector3(1, h, 1)
	fill.position = Vector3(0, 0.04 + h * 0.5, 0)

## Big dumb battery. 1 in, 1 out.
class Capacitor extends Machine:
	var _fill: MeshInstance3D
	func _init() -> void:
		title = "CAPACITOR"
		box_color = Color("#44446a")
		refund_id = "capacitor"
		shows_in = false
		shows_out = false
		buf_cap = 600.0
	func _ready() -> void:
		super._ready()
		_fill = EMachines.cap_visual(self, Color("#9a9aa8"))   # gray outline
	func work(_d: float) -> void:
		EMachines.cap_update_fill(self, _fill)
	func info_text() -> String:
		return "energy: %.0f / %.0f EU" % [buf, buf_cap]

## ULTRA capacitor: 10x the storage, feeds wires faster. Late game.
class UltraCapacitor extends Machine:
	var _fill: MeshInstance3D
	func _init() -> void:
		title = "ULTRA CAPACITOR"
		box_color = Color("#6a5aff")
		box_size = Vector3(1.8, 2.2, 1.8)
		refund_id = "ultracap"
		shows_in = false
		shows_out = false
		buf_cap = 6000.0
	func _ready() -> void:
		super._ready()
		_fill = EMachines.cap_visual(self, Color("#a06aff"))   # purple outline
	func work(_d: float) -> void:
		EMachines.cap_update_fill(self, _fill)
	func _process(delta: float) -> void:
		super._process(delta)
		# second push pass = effectively double wire throughput
		for w in wires_out:
			if is_instance_valid(w) and w.buf_cap > 0.0 and buf > 0.0:
				var t: float = minf(minf(WIRE_RATE * delta, buf), w.buf_cap - w.buf)
				if t > 0.0:
					buf -= t
					w.buf += t
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\ndouble-rate output wires" % [buf, buf_cap]

## Electric furnace: instant smelt, 4 EU per item.
class EFurnace extends Machine:
	const RECIPES := {"raw_ingot": "ingot", "raw_irid": "irid", "meat": "cooked_meat"}
	const EU_PER := 4.0
	var _t := 0.0
	var _mouth: MeshInstance3D
	var _last_buf := 0.0
	var _spent := 0.0        # EU burned by smelting this frame
	var _in_rate := 0.0      # measured incoming EU/s (smoothed)
	func _init() -> void:
		title = "E-FURNACE"
		box_color = Color("#7a3a1a")
		refund_id = "efurnace"
		buf_cap = 200.0
	func _ready() -> void:
		super._ready()
		dress_industrial(Color("#3a1c10"))
		_mouth = MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.8, 0.6, 0.08)
		_mouth.mesh = mm
		_mouth.position = Vector3(0, 0.6, -box_size.z * 0.5 - 0.05)
		_mouth.material_override = Destructible.make_material(Color("#ff5a1a"), 1.0)
		add_child(_mouth)
		# induction coils hug the body -- this thing smelts with ELECTRICITY
		for i in 3:
			var coil := TorusMesh.new()
			coil.inner_radius = box_size.x * 0.62
			coil.outer_radius = box_size.x * 0.62 + 0.09
			part(coil, Vector3(0, 0.35 + float(i) * 0.35, 0), Color("#ffb347"), 1.2)
		# power inlet mast with an insulator stack
		var mast := CylinderMesh.new()
		mast.top_radius = 0.06
		mast.bottom_radius = 0.06
		mast.height = 0.9
		part(mast, Vector3(-0.45, box_size.y + 0.45, -0.4), Color("#2a2a32"), 0.1)
		for i in 3:
			var ins := CylinderMesh.new()
			ins.top_radius = 0.12
			ins.bottom_radius = 0.12
			ins.height = 0.06
			part(ins, Vector3(-0.45, box_size.y + 0.55 + float(i) * 0.14, -0.4), Color("#c8c8d2"), 0.3)
	func _process(d: float) -> void:
		_spent = 0.0
		super._process(d)
		# inflow = observed buffer change + what smelting burned
		var inflow := (buf - _last_buf) + _spent
		_in_rate = lerpf(_in_rate, maxf(0.0, inflow / maxf(d, 0.001)), minf(d * 3.0, 1.0))
		_last_buf = buf
	func work(d: float) -> void:
		_t += d
		if _t < 0.1:
			return
		_t = 0.0
		var id := str(in_slot["id"])
		if not RECIPES.has(id) or int(in_slot["n"]) <= 0 or buf < EU_PER:
			return
		var product: String = RECIPES[id]
		if str(out_slot["id"]) != "" and str(out_slot["id"]) != product:
			return
		buf -= EU_PER
		_spent += EU_PER
		in_slot["n"] = int(in_slot["n"]) - 1
		if int(in_slot["n"]) <= 0:
			in_slot = {"id": "", "n": 0}
		if str(out_slot["id"]) == "":
			out_slot = {"id": product, "n": 1}
		else:
			out_slot["n"] = int(out_slot["n"]) + 1
		if _mouth and _mouth.material_override is StandardMaterial3D:
			_mouth.material_override.emission_energy_multiplier = 8.0   # flare
	func accepts(id: String) -> bool:
		return RECIPES.has(id)
	func info_text() -> String:
		# sustained rate = wire supply / cost, capped by the 10/s tick
		var sustained := minf(10.0, _in_rate / EU_PER)
		var burst := minf(10.0, (buf / EU_PER) if buf > 0.0 else 0.0)
		return "energy: %.0f / %.0f EU   (+%.1f EU/s in)\nin:  %s\nout: %s\n4 EU per item · sustained %.1f items/s · burst up to %.0f now" % [
			buf, buf_cap, _in_rate, Inventory.slot_text(in_slot), Inventory.slot_text(out_slot),
			sustained, burst]
	func actions() -> Array:
		return [

		]

## Electric seller: 2 EU per item, quick.
class ESeller extends Machine:
	const EU_PER := 2.0
	var _t := 0.0
	var _coin: MeshInstance3D
	func _init() -> void:
		title = "E-SELLER"
		box_color = Color("#7a6a10")
		refund_id = "eseller"
		shows_out = false   # coins go straight to your wallet
		buf_cap = 200.0
	func _ready() -> void:
		super._ready()
		dress_industrial(Color("#2a2408"))
		_coin = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = 0.4
		cm.height = 0.08
		_coin.mesh = cm
		_coin.rotation_degrees = Vector3(90, 0, 0)
		_coin.position = Vector3(0, box_size.y + 0.75, 0)
		_coin.material_override = Destructible.make_material(Color("#ffd700"), 3.0)
		add_child(_coin)
		# neon shop sign holding the coin + intake conveyor + cash chute
		var pole := CylinderMesh.new()
		pole.top_radius = 0.05
		pole.bottom_radius = 0.05
		pole.height = 0.7
		part(pole, Vector3(0, box_size.y + 0.35, 0), Color("#2a2a32"), 0.1)
		var belt := BoxMesh.new()
		belt.size = Vector3(0.8, 0.1, 0.5)
		part(belt, Vector3(0, box_size.y * 0.8, box_size.z * 0.5 + 0.24), Color("#1c1c22"), 0.1)
		for i in 3:
			var roller := CylinderMesh.new()
			roller.top_radius = 0.05
			roller.bottom_radius = 0.05
			roller.height = 0.76
			part(roller, Vector3(0, box_size.y * 0.8 + 0.06, box_size.z * 0.5 + 0.1 + float(i) * 0.15),
				Color("#4a4a55"), 0.2, Vector3(0, 0, 90))
		var chute := BoxMesh.new()
		chute.size = Vector3(0.5, 0.16, 0.2)
		part(chute, Vector3(0, 0.3, box_size.z * 0.5 + 0.1), Color("#3a3010"), 0.3)
	func _process(delta: float) -> void:
		super._process(delta)
		if _coin:
			_coin.rotate_z(delta * (0.5 + buf / buf_cap * 5.0))
	func work(d: float) -> void:
		_t += d
		if _t < 0.25:
			return
		_t = 0.0
		var id := str(in_slot["id"])
		if not Coinifier.PRICES.has(id) or int(in_slot["n"]) <= 0 or buf < EU_PER:
			return
		buf -= EU_PER
		in_slot["n"] = int(in_slot["n"]) - 1
		if int(in_slot["n"]) <= 0:
			in_slot = {"id": "", "n": 0}
		# pays 1.25x the manual sell station -- electricity has perks
		Inventory.add_coins(int(ceil(float(Coinifier.PRICES[id]) * 1.25)))
		Sfx.play("coin", -20.0)
	func accepts(id: String) -> bool:
		return Coinifier.PRICES.has(id)
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\nin: %s\n2 EU per sale, fast, pays 1.25x" % [buf, buf_cap, Inventory.slot_text(in_slot)]
	func actions() -> Array:
		return []


## Electric light: sips power, banishes the dark. Glows hard.
class ELight extends Machine:
	const DRAIN := 0.5
	var _lamp: MeshInstance3D
	var _omni: OmniLight3D
	func _init() -> void:
		title = "LIGHT"
		box_color = Color("#2a2a34")
		box_size = Vector3(0.5, 2.2, 0.5)
		refund_id = "elight"
		shows_in = false
		shows_out = false
		buf_cap = 2.0   # no battery: lit means the wire is live NOW
	func _ready() -> void:
		super._ready()
		_lamp = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		_lamp.mesh = sm
		_lamp.material_override = Destructible.make_material(Color("#fff2c8"), 0.2)
		_lamp.position = Vector3(0, box_size.y + 0.4, 0)
		add_child(_lamp)
		_omni = OmniLight3D.new()
		_omni.light_color = Color("#ffe9b8")
		_omni.omni_range = 64.0   # a street lamp owns its whole street
		_omni.light_energy = 0.0
		_omni.position = Vector3(0, box_size.y + 0.4, 0)
		add_child(_omni)
		# lamppost dressing: flared base, neck collar, cage ribs over the bulb
		var base := CylinderMesh.new()
		base.top_radius = 0.3
		base.bottom_radius = 0.45
		base.height = 0.25
		part(base, Vector3(0, 0.12, 0), Color("#1c1c24"), 0.1)
		var collar := CylinderMesh.new()
		collar.top_radius = 0.18
		collar.bottom_radius = 0.14
		collar.height = 0.2
		part(collar, Vector3(0, box_size.y - 0.05, 0), Color("#1c1c24"), 0.1)
		for ang in [0.0, 60.0, 120.0]:
			var rib := TorusMesh.new()
			rib.inner_radius = 0.46
			rib.outer_radius = 0.5
			part(rib, Vector3(0, box_size.y + 0.4, 0), Color("#2a2a34"), 0.15,
				Vector3(90, ang, 0))
	func work(delta: float) -> void:
		# lamps don't store power: wire cut = dark within a blink
		buf = maxf(0.0, buf - (DRAIN + buf * 6.0) * delta)
		_set_lit(buf > 0.1, delta)
	func gated_work(delta: float) -> void:
		# coil says no: dark, regardless of what the wire says
		buf = maxf(0.0, buf - (DRAIN + buf * 6.0) * delta)
		_set_lit(false, delta)
	func _set_lit(on: bool, delta: float) -> void:
		if _omni:
			_omni.light_energy = lerpf(_omni.light_energy, 2.6 if on else 0.0, delta * 6.0)
		if _lamp and _lamp.material_override is StandardMaterial3D:
			# NEON when lit: bloom-hot, unmistakable from across the base
			_lamp.material_override.emission_energy_multiplier = 16.0 if on else 0.15
			_lamp.material_override.albedo_color = Color("#fffbe8") if on else Color("#fff2c8")
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\ndrinks %.1f EU/s while lit" % [buf, buf_cap, DRAIN]


## NUCLEAR REACTOR: real fission, playably simplified. Uranium fuel rods
## react unless the CONTROL RODS are lowered into the core -- rods out =
## more reaction = more heat = more power. Passive cooling only carries
## ~60% output; run hotter and the core temperature CLIMBS. At 1000 deg
## it melts down: fire, a dead crater of your own machines, and you,
## if you're anywhere near it. Real reactors: also like this, roughly.
class NuclearReactor extends Machine:
	const MAX_EU_S := 16.0        # full-reaction output: the best in the game
	const HEAT_RATE := 14.0       # degrees/s at full reaction (of 100)
	const COOL_RATE := 8.0        # passive cooling degrees/s
	const FUEL_SECS := 60.0       # one uranium = a minute of full burn
	var rods: float = 1.0         # actual rod insertion (servo-driven, slow)
	var rods_target: float = 1.0  # where the operator ORDERED the rods
	var power: float = 0.0        # neutron power, 1.0 = 100% rated (can exceed)
	var xenon: float = 0.0        # neutron poison: builds at power, burns at power
	var temp: float = 0.0         # 0..100 internal, shown as 0..1000 deg C
	var press: float = 0.0        # primary loop pressure, 0..100 bar
	var coolant: float = 100.0    # coolant inventory %
	var flow: int = 2             # coolant flow: 0 off · 1 half · 2 full
	var _scram: bool = false      # rods dropping under gravity, not servo
	var mode: int = 0             # 0 SHUTDOWN · 1 STARTUP · 2 RUN (permissives)
	var breaker: bool = false     # turbine breaker: closed = exporting
	var trip_t: float = 0.0       # turbine trip lamp timer
	var _fuel: float = 0.0        # seconds of burn left in the loaded rod

	## Reactivity as the instruments see it.
	func rho_now() -> float:
		if _fuel <= 0.0:
			return -1.0
		return (0.65 - rods) * 0.9 - xenon * 0.5 - (temp / 100.0) * 0.25

	func out_eu_s() -> float:
		return MAX_EU_S * 1.4 * power * (float(flow) * 0.5) if breaker else 0.0

	## MODE keyswitch with real permissives: RUN needs a warm, critical
	## core; STARTUP needs coolant flow. SHUTDOWN always accepts.
	func set_mode(m: int) -> bool:
		if m == mode:
			return true
		if m == 1 and flow == 0:
			return false           # no startup without primary flow
		if m == 2 and (power < 0.03 or temp < 15.0):
			return false           # can't declare RUN on a cold core
		mode = m
		if mode == 0:
			rods_target = 1.0      # shutdown means shutdown
		return true

	## Rod orders respect the mode: none in SHUTDOWN, limited in STARTUP.
	func order_rods(d: float) -> bool:
		if mode == 0:
			return false
		var lo := 0.45 if mode == 1 else 0.0
		rods_target = clampf(rods_target + d, lo, 1.0)
		return true

	## Closing the breaker with weak steam TRIPS the turbine. Sync when
	## the plant is actually making steam, like a professional.
	func toggle_breaker() -> void:
		if breaker:
			breaker = false
			Sfx.play("click", -10.0)
			return
		if power * float(flow) * 0.5 < 0.12:
			trip_t = 5.0
			Sfx.play("denied", -4.0)
			return
		breaker = true
		Sfx.play("learn", -10.0)

	func do_scram() -> void:
		rods_target = 1.0
		_scram = true
		breaker = false
		Sfx.play("denied", -6.0)
	var _rod_meshes: Array = []
	var _glow: MeshInstance3D
	var _gauge: MeshInstance3D
	var _geiger_t: float = 0.0

	func _init() -> void:
		title = "NUCLEAR REACTOR"
		box_color = Color("#8a8d90")   # containment concrete
		box_size = Vector3(2.0, 2.4, 2.0)
		refund_id = "nreactor"
		shows_out = false
		buf_cap = 800.0

	func _ready() -> void:
		super._ready()
		dress_industrial(Color("#5a5d60"))
		# containment dome
		var dome := SphereMesh.new()
		dome.radius = 1.05
		dome.height = 1.4
		dome.is_hemisphere = true
		part(dome, Vector3(0, box_size.y, 0), Color("#9a9da0"), 0.05)
		# Cherenkov window: the blue glow of an open pool core
		var win := BoxMesh.new()
		win.size = Vector3(1.2, 0.5, 0.06)
		_glow = part(win, Vector3(0, 1.0, box_size.z * 0.5 + 0.03), Color("#2a9fff"), 0.3)
		# control rod actuators: four rods that VISIBLY sink into the dome
		for sx in [-0.45, 0.45]:
			for sz in [-0.45, 0.45]:
				var rod := CylinderMesh.new()
				rod.top_radius = 0.07
				rod.bottom_radius = 0.07
				rod.height = 1.1
				_rod_meshes.append(part(rod, Vector3(sx, box_size.y + 0.9, sz),
					Color("#2e3238"), 0.15))
		# temperature strip up the side + hazard stripes + vent stack
		var strip := BoxMesh.new()
		strip.size = Vector3(0.2, 1.8, 0.06)
		_gauge = part(strip, Vector3(-0.7, 1.2, box_size.z * 0.5 + 0.03), Color("#2bff5a"), 1.0)
		for i in 4:
			var stp := BoxMesh.new()
			stp.size = Vector3(0.24, 0.24, 0.03)
			part(stp, Vector3(0.72, 0.3 + float(i) * 0.3, box_size.z * 0.5 + 0.02),
				Color("#ffd166") if i % 2 == 0 else Color("#1c1c24"), 0.4, Vector3(0, 0, 45))
		var stack := CylinderMesh.new()
		stack.top_radius = 0.14
		stack.bottom_radius = 0.2
		stack.height = 1.4
		part(stack, Vector3(0.75, box_size.y + 0.7, -0.6), Color("#c8cbce"), 0.05)

	func work(delta: float) -> void:
		# feed: pull the next uranium rod from the hopper when spent
		if _fuel <= 0.0 and str(in_slot["id"]) == "uranium" and int(in_slot["n"]) > 0:
			in_slot["n"] = int(in_slot["n"]) - 1
			if int(in_slot["n"]) <= 0:
				in_slot = {"id": "", "n": 0}
			_fuel = FUEL_SECS
		# rod servos are SLOW. a scram is not: the rods just fall.
		rods = move_toward(rods, rods_target, delta * (1.5 if _scram else 0.06))
		if _scram and rods >= 1.0:
			_scram = false
		# --- neutron kinetics (the real thing, pocket-sized) ---
		# reactivity: rod worth, minus xenon poison, minus the negative
		# temperature coefficient that keeps a good core self-stabilizing
		var rho := (0.65 - rods) * 0.9 - xenon * 0.5 - (temp / 100.0) * 0.25
		if _fuel <= 0.0:
			rho = -1.0
		# exponential power response: pull too much and it RUNS
		power = clampf(power + power * rho * delta * 2.2, \
			0.002 if _fuel > 0.0 else 0.0, 2.0)
		# xenon-135: builds as you burn, eats neutrons, burns off at high
		# power. shut down hot and it PEAKS -- the restart trap is real
		xenon = clampf(xenon + (0.045 * power - 0.09 * power * xenon \
			- 0.012 * xenon) * delta, 0.0, 1.0)
		_fuel = maxf(0.0, _fuel - power * delta)
		# --- thermal-hydraulics: pump + coolant carry heat to the turbine ---
		var fl := float(flow) * 0.5   # 0 / 0.5 / 1.0
		var cooling := COOL_RATE * fl * (coolant / 100.0) + 1.5
		temp = clampf(temp + (power * HEAT_RATE - cooling) * delta, 0.0, 100.0)
		trip_t = maxf(0.0, trip_t - delta)
		# electricity flows when the coolant does AND the breaker is
		# closed: no steam, no sync, no export
		if breaker:
			buf = minf(buf_cap, buf + MAX_EU_S * 1.4 * power * fl * delta)
			if power * fl < 0.06:   # steam collapsed under load: trip
				breaker = false
				trip_t = 5.0
				Sfx.play("denied", -8.0)
		# pressure follows core temp; the relief margin is YOUR problem
		press = clampf(press + ((temp * 0.95) - press) * delta * 0.4, 0.0, 100.0)
		# condensers recover coolant when things are calm
		if temp < 40.0 and coolant < 100.0:
			coolant = minf(100.0, coolant + 1.2 * delta)
		# looks: rods sink with insertion, the pool glows with power,
		# the gauge walks green -> red
		for r in _rod_meshes:
			r.position.y = lerpf(r.position.y, box_size.y + 0.25 + (1.0 - rods) * 0.75,
				delta * 5.0)
		if _glow and _glow.material_override:
			_glow.material_override.emission_energy_multiplier = 0.2 + power * 3.2 \
				+ (temp / 100.0) * 2.0
		if _gauge and _gauge.material_override:
			_gauge.material_override.emission = Color("#2bff5a").lerp(Color("#ff2b1a"),
				temp / 100.0)
		# hot core clicks at you. that clicking is a WORD, and the word is RUN
		if temp > 70.0:
			_geiger_t -= delta
			if _geiger_t <= 0.0:
				_geiger_t = lerpf(0.9, 0.12, (temp - 70.0) / 30.0)
				Sfx.play("click", -14.0)
		if temp >= 100.0 or press >= 100.0:
			_meltdown()

	func _meltdown() -> void:
		var here := global_position
		Sfx.play("explode", 2.0)
		Game.anger(30.0)   # splitting atoms was ALREADY pushing it
		# fire: one giant burst + a lingering plume
		for burst in [[220, 26.0, 1.0], [80, 10.0, 2.6]]:
			var parts := GPUParticles3D.new()
			parts.amount = burst[0]
			parts.one_shot = true
			parts.explosiveness = 0.9
			parts.lifetime = burst[2]
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3.UP
			pm.spread = 80.0
			pm.initial_velocity_min = burst[1] * 0.4
			pm.initial_velocity_max = burst[1]
			pm.gravity = Vector3.ZERO
			pm.scale_min = 0.3
			pm.scale_max = 1.4
			pm.color = Color("#ff6a1a")
			parts.process_material = pm
			var mesh := SphereMesh.new()
			mesh.radius = 0.6
			mesh.height = 1.2
			mesh.radial_segments = 6
			mesh.rings = 3
			mesh.material = Destructible.make_material(Color("#ff8c2a"), 4.0)
			parts.draw_pass_1 = mesh
			get_parent().add_child(parts)
			parts.global_position = here
			parts.emitting = true
		# everything mechanical within 18m dies. no refunds. it's slag.
		for grp in ["machine", "chest", "autominer", "rocket", "spawn"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n == self or not (n is Node3D) or not is_instance_valid(n):
					continue
				if n.global_position.distance_to(here) < 18.0:
					Destructible.spawn_debris(get_parent(), n.global_position,
						Vector3(1.2, 1.2, 1.2), Color("#3a3a3a"), Vector3.UP)
					Net.broadcast_remove(n.global_position)
					n.queue_free()
		# and you, if you kept standing there reading the gauge
		var p = get_tree().get_first_node_in_group("player")
		if p and is_instance_valid(p):
			var d: float = p.global_position.distance_to(here)
			if d < 22.0:
				Game.hurt(220.0 * (1.0 - d / 22.0) + 20.0)
		Net.broadcast_remove(here)
		Destructible.spawn_debris(get_parent(), here, Vector3(2.4, 2.4, 2.4),
			Color("#8a8d90"), Vector3.UP)
		queue_free()

	func accepts(id: String) -> bool:
		return id == "uranium"

	## F opens the control ROOM, not a context menu. An operator's
	## station for an operator's machine.
	func use() -> void:
		if get_tree().get_first_node_in_group("reactor_ui") != null:
			return
		var ui := ReactorUI.new()
		ui.open(self)
		get_tree().current_scene.add_child(ui)
		Sfx.play("click", -14.0)

	func info_text() -> String:
		var rho := (0.65 - rods) * 0.9 - xenon * 0.5 - (temp / 100.0) * 0.25
		if _fuel <= 0.0:
			rho = -1.0
		var fl := float(flow) * 0.5
		var warn := ""
		if temp > 80.0 or press > 85.0:
			warn = "  ⚠ MELTDOWN IMMINENT"
		elif temp > 55.0 or press > 65.0:
			warn = "  ⚠ excursion in progress"
		elif xenon > 0.5 and power < 0.1:
			warn = "  ⚠ xenon peak: restart will fight you"
		return "energy: %.0f / %.0f EU   (+%.1f EU/s)\nPOWER %.0f%% rated   reactivity ρ %+.3f%s\nrods %.0f%% in (ordered %.0f%%)   xenon %.0f%%\ncore %.0f°C   pressure %.0f bar\ncoolant %.0f%%   flow %s\nfuel: %s%s" % [
			buf, buf_cap, MAX_EU_S * 1.4 * power * fl,
			power * 100.0, rho, warn,
			rods * 100.0, rods_target * 100.0, xenon * 100.0,
			temp * 10.0, press,
			coolant, ["OFF", "HALF", "FULL"][flow],
			("burning, %ds left" % int(_fuel)) if _fuel > 0.0 else "EMPTY",
			"  · hopper: " + Inventory.slot_text(in_slot) if str(in_slot["id"]) != "" else ""]

## LIGHT BOX: a small indicator cube. Wire it to a computer output (or
## anything) and it glows while fed -- a status lamp, not a floodlight.
class LightBox extends Machine:
	const DRAIN := 0.8
	var _omni: OmniLight3D
	func _init() -> void:
		title = "LIGHT BOX"
		box_color = Color("#3a3a2a")
		box_size = Vector3(0.6, 0.6, 0.6)
		refund_id = "lightbox"
		shows_in = false
		shows_out = false   # it is a LAMP
		buf_cap = 2.0   # holds nothing: lit = the wire is live, RIGHT NOW
	func _ready() -> void:
		super._ready()
		_omni = OmniLight3D.new()
		_omni.light_color = Color("#fff2c8")
		_omni.omni_range = 7.0    # lights the desk, not the planet
		_omni.light_energy = 0.0
		_omni.position = Vector3(0, box_size.y * 0.5, 0)
		add_child(_omni)
		# redstone-lamp build: the WHOLE cube is the bulb. A dark lattice
		# frame wraps it -- corner blocks + edge rails -- so each face
		# reads as an inset glowing panel.
		var s := box_size.x * 0.5
		var frame_col := Color("#241f14")
		for cx in [-1.0, 1.0]:
			for cy in [0.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var corner := BoxMesh.new()
					corner.size = Vector3(0.16, 0.16, 0.16)
					part(corner, Vector3(cx * s, cy * box_size.y, cz * s), frame_col, 0.08)
		# 12 edge rails, slim, connecting the corners
		var rail_l := box_size.x - 0.1
		for cy in [0.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var rx := BoxMesh.new()
				rx.size = Vector3(rail_l, 0.08, 0.08)
				part(rx, Vector3(0, cy * box_size.y, cz * s), frame_col, 0.08)
			for cx in [-1.0, 1.0]:
				var rz := BoxMesh.new()
				rz.size = Vector3(0.08, 0.08, rail_l)
				part(rz, Vector3(cx * s, cy * box_size.y, 0), frame_col, 0.08)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var ry := BoxMesh.new()
				ry.size = Vector3(0.08, rail_l, 0.08)
				part(ry, Vector3(cx * s, box_size.y * 0.5, cz * s), frame_col, 0.08)
		# cable stub out the back, so it reads as WIRED
		var stub := CylinderMesh.new()
		stub.top_radius = 0.05
		stub.bottom_radius = 0.05
		stub.height = 0.16
		part(stub, Vector3(0, 0.2, box_size.z * 0.5 + 0.06), Color("#2a2a32"), 0.1,
			Vector3(90, 0, 0))
	func work(delta: float) -> void:
		# no battery in a lamp: cut the wire and it dies within a blink
		buf = maxf(0.0, buf - (DRAIN + buf * 6.0) * delta)
		_set_lit(buf > 0.05, delta)
	func gated_work(delta: float) -> void:
		buf = maxf(0.0, buf - (DRAIN + buf * 6.0) * delta)
		_set_lit(false, delta)
	func _set_lit(on: bool, delta: float) -> void:
		if _omni:
			_omni.light_energy = lerpf(_omni.light_energy, 1.4 if on else 0.0, delta * 10.0)
		if _mat:
			# the whole cube IS the bulb: neon-hot lit, warm dark glass off
			_mat.emission = Color("#ffedb8")
			_mat.emission_energy_multiplier = 14.0 if on else 0.1
			_mat.albedo_color = Color("#fff6d8") if on else Color("#4a4232")
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\nglows while fed -- wire a computer output in" % [buf, buf_cap]

## Hand-operated power switch: energy flows through ONLY while ON.
## F toggles it. The simplest machine and somehow the most satisfying.
class Switch extends Machine:
	var on: bool = false
	var _lever: MeshInstance3D
	var _lamp_mat: StandardMaterial3D

	func _init() -> void:
		title = "SWITCH"
		box_color = Color("#4a4a52")
		box_size = Vector3(0.8, 1.2, 0.8)
		refund_id = "switch"
		shows_in = false
		shows_out = false
		buf_cap = 200.0

	func _ready() -> void:
		super._ready()
		_lever = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.16, 0.7, 0.16)
		_lever.mesh = lm
		_lever.position = Vector3(0, box_size.y + 0.25, 0)
		_lever.material_override = Destructible.make_material(Color("#c0c0c8"), 0.3)
		add_child(_lever)
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		lamp.mesh = sm
		lamp.position = Vector3(0, 0.6, -box_size.z * 0.5 - 0.08)
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp_mat.emission_enabled = true
		lamp.material_override = _lamp_mat
		add_child(lamp)
		# breaker-box dressing: hinge plate, lever pivot, hazard stripes
		var pivot := CylinderMesh.new()
		pivot.top_radius = 0.12
		pivot.bottom_radius = 0.12
		pivot.height = 0.3
		part(pivot, Vector3(0, box_size.y, 0), Color("#2a2a32"), 0.15, Vector3(0, 0, 90))
		var plate := BoxMesh.new()
		plate.size = Vector3(0.6, 0.35, 0.06)
		part(plate, Vector3(0, 0.6, -box_size.z * 0.5 - 0.02), Color("#1c1c24"), 0.1)
		for i in 3:
			var stripe := BoxMesh.new()
			stripe.size = Vector3(0.12, 0.35, 0.02)
			part(stripe, Vector3(-0.2 + float(i) * 0.2, 0.18, -box_size.z * 0.5 - 0.03),
				Color("#ffd166") if i % 2 == 0 else Color("#1c1c24"), 0.4,
				Vector3(0, 0, 24))
		_apply_visual()

	func _apply_visual() -> void:
		if _lever:
			var tw := create_tween()
			tw.tween_property(_lever, "rotation:x", -0.5 if on else 0.5, 0.15)
		if _lamp_mat:
			_lamp_mat.emission = Color("#2bff5a") if on else Color("#ff2b2b")
			_lamp_mat.emission_energy_multiplier = 4.0 if on else 1.5

	## F flips it. No menu. Clunk.
	func use() -> void:
		on = not on
		_apply_visual()
		Sfx.play("place", -10.0)

	func _process(delta: float) -> void:
		if on:
			super._process(delta)
		else:
			# OFF: incoming power still fills the buffer, nothing leaves
			var held := buf
			buf = 0.0
			super._process(delta)
			buf = held
