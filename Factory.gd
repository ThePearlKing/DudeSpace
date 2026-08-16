class_name Factory
extends RefCounted
## The production machines: the CRUSHER that doubles what an ore is worth,
## and the ALLOY FURNACE that turns metals into the alloys everything
## worth building is made of. Both run on the same power net, the same
## funnels and the same wires as the rest of the base -- an alloy line is
## just machines pointed at each other.

# ------------------------------------------------------------- crusher

class Crusher extends Machine:
	const EU_PER := 7.0
	const SECS := 2.6
	var _t := 0.0
	var _rollers: Array = []

	func _init() -> void:
		title = "CRUSHER"
		box_color = Color("#5a5f6a")
		refund_id = "crusher"
		buf_cap = 300.0

	func _ready() -> void:
		super._ready()
		dress_industrial(Color("#20242b"))
		# hopper above, two rollers in the throat, a spout out the front
		var hop := CylinderMesh.new()
		hop.top_radius = 0.62
		hop.bottom_radius = 0.22
		hop.height = 0.6
		part(hop, Vector3(0, box_size.y + 0.32, 0), Color("#3a4048"), 0.08)
		for sx in [-1.0, 1.0]:
			var roll := CylinderMesh.new()
			roll.top_radius = 0.22
			roll.bottom_radius = 0.22
			roll.height = 0.8
			var mi := part(roll, Vector3(sx * 0.24, box_size.y - 0.15, 0),
				Color("#8d97a5"), 0.2, Vector3(0, 0, 90))
			_rollers.append(mi)
			for i in 6:
				var tooth := BoxMesh.new()
				tooth.size = Vector3(0.06, 0.86, 0.06)
				var t := part(tooth, Vector3(sx * 0.24, box_size.y - 0.15, 0),
					Color("#5b6472"), 0.1, Vector3(0, 0, 90))
				t.rotate_object_local(Vector3.UP, TAU * float(i) / 6.0)
				t.position += Vector3(cos(TAU * float(i) / 6.0),
					0, sin(TAU * float(i) / 6.0)) * 0.2
		var spout := BoxMesh.new()
		spout.size = Vector3(0.5, 0.18, 0.3)
		part(spout, Vector3(0, 0.3, box_size.z * 0.5 + 0.14), Color("#2a2f36"), 0.05)

	func accepts(id: String) -> bool:
		if id in ["raw_ingot", "raw_irid"]:
			return true
		return str(Mats.def(id).get("kind", "")) == "ore"

	## What one rock crushes into: two of the matching dust.
	static func dust_of(id: String) -> String:
		if id == "raw_ingot":
			return "dust_iron"
		if id == "raw_irid":
			return "dust_irid"
		if id.begins_with("raw_"):
			var d := "dust_" + id.substr(4)
			return d if Mats.has(d) else ""
		return ""

	func work(delta: float) -> void:
		var id := str(in_slot["id"])
		var dust := dust_of(id)
		var spin := 0.4
		if dust != "" and int(in_slot["n"]) > 0 and buf >= EU_PER \
				and (str(out_slot["id"]) == "" or str(out_slot["id"]) == dust):
			spin = 6.0
			_t += delta
			if _t >= SECS:
				_t = 0.0
				buf -= EU_PER
				in_slot["n"] = int(in_slot["n"]) - 1
				if int(in_slot["n"]) <= 0:
					in_slot = {"id": "", "n": 0}
				if str(out_slot["id"]) == "":
					out_slot = {"id": dust, "n": 2}
				else:
					out_slot["n"] = int(out_slot["n"]) + 2
				Sfx.play("hurt", -24.0)
		else:
			_t = 0.0
		for i in _rollers.size():
			if is_instance_valid(_rollers[i]):
				_rollers[i].rotate_object_local(Vector3.UP,
					delta * spin * (1.0 if i == 0 else -1.0))

	func info_text() -> String:
		var id := str(in_slot["id"])
		var dust := dust_of(id)
		return "energy: %.0f / %.0f EU (%.0f per rock)\nin: %s\nout: %s\n%s" % [
			buf, buf_cap, EU_PER, Inventory.slot_text(in_slot),
			Inventory.slot_text(out_slot),
			"crushing -> 2x %s" % Inventory.hotbar_name(dust) if dust != ""
			else "feed it ORE: one rock crushes into TWO dust, and dust smelts one for one. Crushing doubles every deposit you own."]

	func actions() -> Array:
		return [
			["Load ore from bags", func() -> void:
				var ids: Array = ["raw_ingot", "raw_irid"]
				for o in Mats.ores():
					ids.append(o)
				load_from_hotbar(ids)],
			["Take output", take_output],
			["Take input back", take_input],
		]

# ------------------------------------------------------- alloy furnace

## THE GLASSWARE BENCH. No power, no automation: three bottles, a
## burner and your hands. Every compound has its own sequence of
## operations and the bench will only tell you whether the last thing
## you did helped. Everything downstream -- every lab, every alloy that
## needs an acid -- starts here.
class BenchLab extends Machine:
	var bottles: Dictionary = {}      # id -> count poured in
	var steps: Array = []             # operations performed so far
	var last_note: String = "empty glassware. pour something in."
	var _burner: MeshInstance3D
	var _flame := 0.0

	func _init() -> void:
		title = "GLASSWARE BENCH"
		box_color = Color("#3f5a4a")
		refund_id = "benchlab"
		box_size = Vector3(1.6, 1.0, 1.0)
		buf_cap = 0.0                 # entirely manual. that is the point.

	func _ready() -> void:
		super._ready()
		dress_industrial(Color("#1a2420"))
		# three flasks on a rack, a burner, a condenser coil
		for i in 3:
			var flask := SphereMesh.new()
			flask.radius = 0.17
			flask.height = 0.3
			var fm := part(flask, Vector3(-0.45 + float(i) * 0.45, box_size.y + 0.2, 0),
				Color("#9fd8e8"), 0.35)
			var mat: StandardMaterial3D = fm.material_override
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.7, 0.9, 1.0, 0.4)
			var neck := CylinderMesh.new()
			neck.top_radius = 0.05
			neck.bottom_radius = 0.06
			neck.height = 0.22
			part(neck, Vector3(-0.45 + float(i) * 0.45, box_size.y + 0.42, 0),
				Color("#cfe8f2"), 0.2)
		_burner = MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.12
		bm.bottom_radius = 0.16
		bm.height = 0.14
		_burner.mesh = bm
		_burner.position = Vector3(0.0, box_size.y + 0.02, 0.3)
		_burner.material_override = Destructible.make_material(Color("#ff7a1a"), 0.4)
		add_child(_burner)
		var coil := TorusMesh.new()
		coil.inner_radius = 0.1
		coil.outer_radius = 0.14
		for i in 4:
			part(coil, Vector3(0.6, box_size.y + 0.1 + float(i) * 0.12, -0.25),
				Color("#cfe8f2"), 0.25, Vector3(90, 0, 0))

	func work(delta: float) -> void:
		_flame = maxf(0.0, _flame - delta * 1.5)
		if _burner and _burner.material_override is StandardMaterial3D:
			_burner.material_override.emission_energy_multiplier = 0.3 + _flame * 4.0

	## What the bottles could become, if the sequence is right.
	func target() -> String:
		return Mats.hand_match(bottles)

	func pour(id: String, n: int = 1) -> bool:
		if not Mats.has(id) and not Inventory.items.has(id):
			return false
		var have := Inventory.res_count(id)
		var take := mini(n, have)
		if take <= 0:
			Sfx.play("denied")
			last_note = "you have no %s to pour." % Inventory.hotbar_name(id)
			return false
		Inventory.remove_res(id, take)
		bottles[id] = int(bottles.get(id, 0)) + take
		steps.clear()
		var t := target()
		last_note = ("the glass could hold %s now. begin." % Inventory.hotbar_name(t)) \
			if t != "" else "nothing in there wants to become anything yet."
		Sfx.play("click", -16.0)
		return true

	func empty_glass() -> void:
		for k in bottles.keys():
			if int(bottles[k]) > 0:
				Inventory.give(str(k), int(bottles[k]))
		bottles.clear()
		steps.clear()
		last_note = "glassware rinsed."
		Sfx.play("click", -18.0)

	## One operation. Right one: progress. Wrong one: the batch settles
	## and you start the sequence again -- the ingredients survive.
	func do_op(op: String) -> void:
		if op == "HEAT":
			_flame = 1.0
		var t := target()
		if t == "":
			last_note = "nothing happens. there is not enough in the glass."
			Sfx.play("denied", -20.0)
			return
		var seq := Mats.hand_sequence(t)
		if steps.size() < seq.size() and op == str(seq[steps.size()]):
			steps.append(op)
			if steps.size() >= seq.size():
				_finish(t)
			else:
				last_note = "%s — something is happening. (%d of %d)" % [
					op.to_lower(), steps.size(), seq.size()]
				Sfx.play("learn", -14.0)
		else:
			steps.clear()
			last_note = "%s — the mixture settles. start the sequence again." % op.to_lower()
			Sfx.play("denied", -18.0)

	func _finish(t: String) -> void:
		var d := Mats.def(t)
		for k in (d["inputs"] as Dictionary).keys():
			bottles[k] = int(bottles.get(k, 0)) - int(d["inputs"][k])
			if int(bottles.get(k, 0)) <= 0:
				bottles.erase(k)
		var n := int(d.get("out_n", 1))
		if str(out_slot["id"]) == "" or str(out_slot["id"]) == t:
			if str(out_slot["id"]) == "":
				out_slot = {"id": t, "n": n}
			else:
				out_slot["n"] = int(out_slot["n"]) + n
		else:
			Inventory.give(t, n)
		steps.clear()
		last_note = "%s. it worked." % str(d.get("name", t)).to_upper()
		Sfx.play("coin", -8.0)

	func use() -> void:
		if get_tree().get_first_node_in_group("chem_ui") != null:
			return
		var ui := ChemUI.new()
		ui.bench = self
		get_tree().current_scene.add_child(ui)

	func info_text() -> String:
		return "manual glassware. F opens the bench."

## THE PROCESSORS. One machine class, four families and three tiers:
## the chemistry labs, the electrolyser, the air separator and the cryo
## plant all take a recipe from the registry, eat their inputs and their
## power, and hand back a product. Tier gates which recipes will run --
## nobody makes omegium in a starter lab.
class Processor extends Machine:
	var tier: int = 1
	var family: String = "chem"
	var recipe: String = ""
	var store: Dictionary = {}
	var _t: float = 0.0
	var _glow: float = 0.0
	var _vessel: MeshInstance3D

	const SPEED := [1.0, 2.2, 5.0]
	const EU_RATE := [4.0, 11.0, 26.0]
	const FAM_NAMES := {
		"chem": ["CHEM LAB I", "CHEM LAB II", "CHEM LAB III"],
		"electro": ["ELECTROLYSER", "ELECTROLYSER II", "ELECTROLYSER III"],
		"sep": ["AIR SEPARATOR", "SEPARATOR II", "SEPARATOR III"],
		"cryo": ["CRYO PLANT", "CRYO PLANT II", "CRYO PLANT III"],
	}
	const FAM_COLS := {"chem": "#2f6a4a", "electro": "#2a4a72",
		"sep": "#4a4a6a", "cryo": "#2f6a72"}
	const FAM_REFUND := {
		"chem": ["chemlab", "chemlab2", "chemlab3"],
		"electro": ["electrolyser", "electrolyser2", "electrolyser3"],
		"sep": ["separator", "separator2", "separator3"],
		"cryo": ["cryoplant", "cryoplant2", "cryoplant3"],
	}

	func setup(fam: String, t: int) -> Processor:
		family = fam
		tier = clampi(t, 1, 3)
		return self

	func _init() -> void:
		title = "CHEM LAB I"
		box_color = Color("#2f6a4a")
		buf_cap = 500.0

	func _ready() -> void:
		title = str((FAM_NAMES.get(family, FAM_NAMES["chem"]) as Array)[tier - 1])
		box_color = Color(str(FAM_COLS.get(family, "#2f6a4a")))
		refund_id = str((FAM_REFUND.get(family, FAM_REFUND["chem"]) as Array)[tier - 1])
		buf_cap = [500.0, 1200.0, 2600.0][tier - 1]
		var rl := Mats.recipes_for(family, tier)
		if recipe == "" or not rl.has(recipe):
			recipe = str(rl[0]) if rl.size() > 0 else ""
		super._ready()
		dress_industrial(Color("#141a18"))
		# a glass vessel on top, pipework, and tier bands round the body
		_vessel = MeshInstance3D.new()
		var vm := CylinderMesh.new()
		vm.top_radius = 0.42
		vm.bottom_radius = 0.5
		vm.height = 0.9
		_vessel.mesh = vm
		_vessel.position = Vector3(0, box_size.y + 0.45, 0)
		var vmat := StandardMaterial3D.new()
		vmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vmat.albedo_color = Color(0.7, 0.9, 1.0, 0.28)
		vmat.emission_enabled = true
		vmat.emission = box_color.lightened(0.4)
		vmat.emission_energy_multiplier = 0.4
		_vessel.material_override = vmat
		add_child(_vessel)
		for i in tier:
			var band := TorusMesh.new()
			band.inner_radius = box_size.x * 0.54
			band.outer_radius = box_size.x * 0.54 + 0.07
			part(band, Vector3(0, 0.32 + float(i) * 0.34, 0),
				[Color("#7dff9a"), Color("#7be8ff"), Color("#c86bff")][tier - 1], 1.1)
		for sx in [-1.0, 1.0]:
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.09
			pipe.bottom_radius = 0.09
			pipe.height = 1.1
			part(pipe, Vector3(sx * (box_size.x * 0.5 + 0.05), box_size.y * 0.65, 0.2),
				Color("#8d97a5"), 0.15)
			var valve := SphereMesh.new()
			valve.radius = 0.14
			valve.height = 0.28
			part(valve, Vector3(sx * (box_size.x * 0.5 + 0.05), box_size.y * 1.2, 0.2),
				Color("#c8722f"), 0.2)
		if family == "cryo":
			for i in 4:
				var fin := BoxMesh.new()
				fin.size = Vector3(box_size.x + 0.3, 0.05, 0.5)
				part(fin, Vector3(0, 0.4 + float(i) * 0.3, -box_size.z * 0.4),
					Color("#a8d8ff"), 0.5)

	func rate() -> float:
		return SPEED[tier - 1]

	func recipe_def() -> Dictionary:
		return Mats.def(recipe)

	func needs() -> Dictionary:
		return recipe_def().get("inputs", {})

	func accepts(id: String) -> bool:
		return needs().has(id) and int(store.get(id, 0)) < 999

	func accept_item(id: String) -> bool:
		if not accepts(id):
			return false
		store[id] = int(store.get(id, 0)) + 1
		return true

	func _has_all() -> bool:
		for k in needs().keys():
			if int(store.get(k, 0)) < int(needs()[k]):
				return false
		return true

	func work(delta: float) -> void:
		var d := recipe_def()
		if d.is_empty():
			return
		var blocked: bool = str(out_slot["id"]) != "" and str(out_slot["id"]) != recipe
		# an air separator pulls its feedstock out of the sky, so it runs
		# on power alone -- but only where there IS a sky
		var free_feed: bool = needs().is_empty()
		if free_feed and not _in_atmosphere():
			_glow = maxf(0.0, _glow - delta)
			return
		var running: bool = (free_feed or _has_all()) and not blocked and buf > 0.0
		if running:
			buf = maxf(0.0, buf - EU_RATE[tier - 1] * delta)
			_t += delta * rate()
			_glow = minf(1.0, _glow + delta * 3.0)
			if _t >= float(d.get("secs", 10.0)):
				_t = 0.0
				for k in needs().keys():
					store[k] = int(store[k]) - int(needs()[k])
					if int(store[k]) <= 0:
						store.erase(k)
				var n := int(d.get("out_n", 1))
				if str(out_slot["id"]) == "":
					out_slot = {"id": recipe, "n": n}
				else:
					out_slot["n"] = int(out_slot["n"]) + n
				Sfx.play("smelt", -20.0)
		else:
			_t = maxf(0.0, _t - delta * 0.5)
			_glow = maxf(0.0, _glow - delta * 2.0)
		if _vessel and _vessel.material_override is StandardMaterial3D:
			var mm: StandardMaterial3D = _vessel.material_override
			mm.emission = Color(recipe_def().get("color", Color("#7be8ff")))
			mm.emission_energy_multiplier = 0.2 + _glow * 3.5
			mm.albedo_color.a = 0.2 + _glow * 0.35

	## Air only exists where a planet is holding some.
	func _in_atmosphere() -> bool:
		var b = Universe.nearest(global_position)
		if b == null:
			return false
		if global_position.distance_to(b.center) > float(b.radius) + 60.0:
			return false
		return str(b.kind) in ["home", "life", "earth", "sand", "circuit", "logic",
			"pi", "venus", "mars", "gas", "tutorial", "volcanic", "crystal", "ocean"]

	func progress() -> float:
		return clampf(_t / maxf(float(recipe_def().get("secs", 10.0)), 0.01), 0.0, 1.0)

	func info_text() -> String:
		var d := recipe_def()
		var lines: Array = []
		lines.append("MAKING: %s  x%d every %.0fs  (tier %d runs %.1fx)" % [
			str(d.get("name", recipe)), int(d.get("out_n", 1)),
			float(d.get("secs", 10.0)) / rate(), tier, rate()])
		lines.append(str(d.get("desc", "")))
		if str(d.get("uses", "")) != "":
			lines.append("used for: " + str(d["uses"]))
		var parts: Array = []
		for k in needs().keys():
			parts.append("%s %d/%d" % [Inventory.hotbar_name(str(k)),
				int(store.get(k, 0)), int(needs()[k])])
		lines.append("charge: " + (", ".join(parts) if parts.size() > 0
			else "drawn from the air"))
		lines.append("energy: %.0f / %.0f EU  (%.0f EU/s while running)" % [
			buf, buf_cap, EU_RATE[tier - 1]])
		lines.append("progress: %d%%   out: %s" % [int(progress() * 100.0),
			Inventory.slot_text(out_slot)])
		if needs().is_empty() and not _in_atmosphere():
			lines.append("NO ATMOSPHERE HERE — this one needs air to pull apart")
		elif not needs().is_empty() and not _has_all():
			lines.append("waiting on feedstock")
		elif buf <= 0.0:
			lines.append("no power — wire it up")
		return "\n".join(lines)

	func actions() -> Array:
		return [
			["Recipe: " + str(recipe_def().get("name", recipe)) + "  (pick)",
				func() -> void:
					var opts: Array = []
					for rid in Mats.recipes_for(family, tier):
						var rd := Mats.def(rid)
						var ing: Array = []
						for k in (rd["inputs"] as Dictionary).keys():
							ing.append("%dx %s" % [int(rd["inputs"][k]),
								Inventory.hotbar_name(str(k))])
						opts.append({"id": rid, "label": "%s  <-  %s" % [
							str(rd["name"]),
							" + ".join(ing) if ing.size() > 0 else "thin air"]})
					var pui := PickUI.new().configure("RECIPE", opts,
						func(pick: String) -> void:
							recipe = pick
							_t = 0.0
							Sfx.play("click"))
					get_tree().current_scene.add_child(pui)
					use()],
			["Load feedstock from bags", func() -> void:
				var got := false
				for k in needs().keys():
					var want := int(needs()[k]) * 8
					var have := Inventory.res_count(str(k))
					var take := mini(want, have)
					if take > 0:
						Inventory.remove_res(str(k), take)
						store[k] = int(store.get(k, 0)) + take
						got = true
				Sfx.play("click" if got else "denied")],
			["Take output", take_output],
			["Empty the vessel", func() -> void:
				var any := false
				for k in store.keys():
					if int(store[k]) > 0:
						Inventory.give(str(k), int(store[k]))
						any = true
				store.clear()
				Sfx.play("click" if any else "denied")],
		]

	func _on_destroyed(push_dir: Vector3) -> void:
		for k in store.keys():
			if int(store[k]) > 0:
				Inventory.give_at(str(k), int(store[k]), global_position)
		store.clear()
		super._on_destroyed(push_dir)

class AlloyFurnace extends Machine:
	var tier: int = 1
	var recipe: String = "bronze"
	var store: Dictionary = {}        # what has been fed in so far
	var _t: float = 0.0
	var _pool: MeshInstance3D
	var _glow: float = 0.0

	const SPEED := [1.0, 3.0, 8.0]
	const EU_RATE := [3.0, 9.0, 20.0]
	const NAMES := ["ALLOY FURNACE I", "INDUCTION FURNACE II", "PLASMA FURNACE III"]
	const COLS := ["#6a4030", "#2f5a72", "#5a2f72"]

	func setup(t: int) -> AlloyFurnace:
		tier = clampi(t, 1, 3)
		return self

	func _init() -> void:
		title = "ALLOY FURNACE I"
		box_color = Color("#6a4030")
		refund_id = "alloyfurn"
		buf_cap = 400.0

	func _ready() -> void:
		title = NAMES[tier - 1]
		box_color = Color(COLS[tier - 1])
		refund_id = ["alloyfurn", "alloyfurn2", "alloyfurn3"][tier - 1]
		buf_cap = [400.0, 900.0, 2000.0][tier - 1]
		if not Mats.recipes_for_tier(tier).has(recipe):
			recipe = str(Mats.recipes_for_tier(tier)[0])
		super._ready()
		dress_industrial(Color("#1a1512"))
		# a crucible on a plinth, a pour spout, and a pool that glows
		# while it is actually pouring
		var cruc := CylinderMesh.new()
		cruc.top_radius = 0.55
		cruc.bottom_radius = 0.38
		cruc.height = 0.7
		part(cruc, Vector3(0, box_size.y + 0.3, 0), box_color.darkened(0.35), 0.05)
		_pool = MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.48
		pm.bottom_radius = 0.48
		pm.height = 0.06
		_pool.mesh = pm
		_pool.position = Vector3(0, box_size.y + 0.58, 0)
		_pool.material_override = Destructible.make_material(Color("#ff8a2a"), 1.0)
		add_child(_pool)
		var spout := BoxMesh.new()
		spout.size = Vector3(0.24, 0.1, 0.4)
		part(spout, Vector3(0, box_size.y + 0.2, box_size.z * 0.5 + 0.1),
			box_color.darkened(0.5), 0.05)
		# tier marks: one, two or three rings round the body
		for i in tier:
			var ring := TorusMesh.new()
			ring.inner_radius = box_size.x * 0.55
			ring.outer_radius = box_size.x * 0.55 + 0.07
			part(ring, Vector3(0, 0.3 + float(i) * 0.34, 0),
				[Color("#ffb347"), Color("#7be8ff"), Color("#c86bff")][tier - 1], 1.1)
		if tier >= 2:
			for sx in [-1.0, 1.0]:
				var coil := CylinderMesh.new()
				coil.top_radius = 0.07
				coil.bottom_radius = 0.07
				coil.height = 1.1
				part(coil, Vector3(sx * (box_size.x * 0.5 + 0.06), box_size.y * 0.6, 0),
					Color("#c8c8d2"), 0.3)

	func rate() -> float:
		return SPEED[tier - 1]

	func recipe_def() -> Dictionary:
		return Mats.def(recipe)

	func needs() -> Dictionary:
		return recipe_def().get("inputs", {})

	func accepts(id: String) -> bool:
		return needs().has(id) and int(store.get(id, 0)) < 999

	func accept_item(id: String) -> bool:
		if not accepts(id):
			return false
		store[id] = int(store.get(id, 0)) + 1
		return true

	func _has_all() -> bool:
		for k in needs().keys():
			if int(store.get(k, 0)) < int(needs()[k]):
				return false
		return true

	func work(delta: float) -> void:
		var d := recipe_def()
		if d.is_empty():
			return
		var out_id := recipe
		var blocked: bool = str(out_slot["id"]) != "" and str(out_slot["id"]) != out_id
		var running: bool = _has_all() and not blocked and buf > 0.0
		if running:
			var eu: float = EU_RATE[tier - 1] * delta
			buf = maxf(0.0, buf - eu)
			_t += delta * rate()
			_glow = minf(1.0, _glow + delta * 3.0)
			if _t >= float(d.get("secs", 8.0)):
				_t = 0.0
				for k in needs().keys():
					store[k] = int(store[k]) - int(needs()[k])
					if int(store[k]) <= 0:
						store.erase(k)
				var n := int(d.get("out_n", 1))
				if str(out_slot["id"]) == "":
					out_slot = {"id": out_id, "n": n}
				else:
					out_slot["n"] = int(out_slot["n"]) + n
				Sfx.play("smelt", -18.0)
		else:
			_t = maxf(0.0, _t - delta * 0.5)
			_glow = maxf(0.0, _glow - delta * 2.0)
		if _pool and _pool.material_override is StandardMaterial3D:
			var mm: StandardMaterial3D = _pool.material_override
			mm.emission = Color(Mats.def(recipe).get("color", Color("#ff8a2a")))
			mm.emission_energy_multiplier = 0.3 + _glow * 4.0

	func progress() -> float:
		var secs := float(recipe_def().get("secs", 8.0))
		return clampf(_t / maxf(secs, 0.01), 0.0, 1.0)

	func info_text() -> String:
		var d := recipe_def()
		var lines: Array = []
		lines.append("POURING: %s  x%d every %.0fs  (tier %d runs %.0fx)" % [
			str(d.get("name", recipe)), int(d.get("out_n", 1)),
			float(d.get("secs", 8.0)) / rate(), tier, rate()])
		lines.append(str(d.get("desc", "")))
		var parts: Array = []
		for k in needs().keys():
			parts.append("%s %d/%d" % [Inventory.hotbar_name(str(k)),
				int(store.get(k, 0)), int(needs()[k])])
		lines.append("charge: " + (", ".join(parts) if parts.size() > 0 else "-"))
		lines.append("energy: %.0f / %.0f EU  (%.0f EU/s while pouring)" % [
			buf, buf_cap, EU_RATE[tier - 1]])
		lines.append("progress: %d%%" % int(progress() * 100.0))
		lines.append("out: %s" % Inventory.slot_text(out_slot))
		if not _has_all():
			lines.append("waiting on metal — funnel it in, or load it from your bags")
		elif buf <= 0.0:
			lines.append("no power — wire it up")
		return "\n".join(lines)

	func actions() -> Array:
		var acts: Array = [
			["Recipe: " + str(recipe_def().get("name", recipe)) + "  (pick)",
				func() -> void:
					var opts: Array = []
					for rid in Mats.recipes_for_tier(tier):
						var rd := Mats.def(rid)
						var ing: Array = []
						for k in (rd["inputs"] as Dictionary).keys():
							ing.append("%dx %s" % [int(rd["inputs"][k]),
								Inventory.hotbar_name(str(k))])
						opts.append({"id": rid, "label": "%s  <-  %s" % [
							str(rd["name"]), " + ".join(ing)]})
					var pui := PickUI.new().configure("ALLOY RECIPE", opts,
						func(pick: String) -> void:
							recipe = pick
							_t = 0.0
							Sfx.play("click"))
					get_tree().current_scene.add_child(pui)
					use()],
			["Load metal from bags", func() -> void:
				var got := false
				for k in needs().keys():
					var want := int(needs()[k]) * 8
					var have := Inventory.res_count(str(k))
					var take := mini(want, have)
					if take > 0:
						Inventory.remove_res(str(k), take)
						store[k] = int(store.get(k, 0)) + take
						got = true
				Sfx.play("click" if got else "denied")],
			["Take output", take_output],
			["Empty the charge", func() -> void:
				var any := false
				for k in store.keys():
					if int(store[k]) > 0:
						Inventory.give(str(k), int(store[k]))
						any = true
				store.clear()
				Sfx.play("click" if any else "denied")],
		]
		return acts

	func _on_destroyed(push_dir: Vector3) -> void:
		for k in store.keys():
			if int(store[k]) > 0:
				Inventory.give_at(str(k), int(store[k]), global_position)
		store.clear()
		super._on_destroyed(push_dir)
