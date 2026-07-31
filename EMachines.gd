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
		buf_cap = 200.0
	func _ready() -> void:
		super._ready()
		# exhaust stack + hot vent
		var stack := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.22
		cm.height = 1.0
		stack.mesh = cm
		stack.position = Vector3(0.4, box_size.y + 0.5, 0.3)
		stack.material_override = Destructible.make_material(Color("#22222a"), 0.1)
		add_child(stack)
		_vent = MeshInstance3D.new()
		var vm := BoxMesh.new()
		vm.size = Vector3(0.9, 0.5, 0.06)
		_vent.mesh = vm
		_vent.position = Vector3(0, 0.6, -box_size.z * 0.5 - 0.04)
		_vent.material_override = Destructible.make_material(Color("#ff7a1a"), 0.5)
		add_child(_vent)
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
	func _ready() -> void:
		super._ready()
		_bit = MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.3
		bm.bottom_radius = 0.05
		bm.height = 0.9
		_bit.mesh = bm
		_bit.position = Vector3(0, -0.35, 0)
		_bit.material_override = Destructible.make_material(Color("#8a8a96"), 0.6)
		add_child(_bit)
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
		for sx in [-0.55, 0.55]:   # cage bars
			var bar := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.05
			bm.bottom_radius = 0.05
			bm.height = 1.6
			bar.mesh = bm
			bar.material_override = Destructible.make_material(Color("#444455"), 0.2)
			bar.position = Vector3(sx, box_size.y + 0.7, 0)
			add_child(bar)
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
		_mouth = MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.8, 0.6, 0.08)
		_mouth.mesh = mm
		_mouth.position = Vector3(0, 0.6, -box_size.z * 0.5 - 0.05)
		_mouth.material_override = Destructible.make_material(Color("#ff5a1a"), 1.0)
		add_child(_mouth)
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
		buf_cap = 200.0
	func _ready() -> void:
		super._ready()
		_coin = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = 0.4
		cm.height = 0.08
		_coin.mesh = cm
		_coin.rotation_degrees = Vector3(90, 0, 0)
		_coin.position = Vector3(0, box_size.y + 0.6, 0)
		_coin.material_override = Destructible.make_material(Color("#ffd700"), 3.0)
		add_child(_coin)
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
		buf_cap = 60.0
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
		_omni.omni_range = 26.0
		_omni.light_energy = 0.0
		_omni.position = Vector3(0, box_size.y + 0.4, 0)
		add_child(_omni)
	func work(delta: float) -> void:
		var on := buf > 0.1
		if on:
			buf = maxf(0.0, buf - DRAIN * delta)
		if _omni:
			_omni.light_energy = lerpf(_omni.light_energy, 2.6 if on else 0.0, delta * 6.0)
		if _lamp and _lamp.material_override is StandardMaterial3D:
			_lamp.material_override.emission_energy_multiplier = 6.0 if on else 0.15
	func info_text() -> String:
		return "energy: %.0f / %.0f EU\ndrinks %.1f EU/s while lit" % [buf, buf_cap, DRAIN]


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
