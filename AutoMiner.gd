class_name AutoMiner
extends Machine
## ELECTRIC auto-miner. Works ANYWHERE -- but parked next to ore it's
## fast and cheap; out in the void it drills slow and drinks POWER.
## F: pick which ore it fabricates (no crystals. they refuse).

const NEAR_EU := 8.0
const NEAR_SECS := 5.0
const FAR_EU := 40.0
const FAR_SECS := 9.0
const FOREIGN_EU := 60.0    # ore this planet doesn't even have
const FOREIGN_SECS := 60.0  # fabricating from planetary dust. glacial.

var target_ore: String = "raw_ingot"
## 1 = the basic rig (iron, copper, tin, coal). 2 adds gold, zinc,
## titanium, aerinite. 3 is the only thing that will touch abyssite,
## neptunium or dudium.
var tier: int = 1
const TIER_NAMES := ["AUTO-MINER", "AUTO-MINER MK2", "DEEP-CORE MINER MK3"]
const TIER_SPEED := [1.0, 0.62, 0.34]     # multiplier on seconds-per-rock
var _t: float = 0.0
var _drill: MeshInstance3D
var _site_t: float = 0.0        # cached surveys, refreshed every few secs
var _grounded := false
var _native := false

func setup(t: int) -> AutoMiner:
	tier = clampi(t, 1, 3)
	return self

func _init() -> void:
	title = "AUTO-MINER"
	box_color = Color("#3a5a6a")
	refund_id = "autominer"
	shows_in = false   # it digs, it does not eat
	buf_cap = 400.0
	add_to_group("autominer")

func _ready() -> void:
	title = TIER_NAMES[tier - 1]
	refund_id = ["autominer", "autominer2", "autominer3"][tier - 1]
	box_color = [Color("#3a5a6a"), Color("#2f6a5a"), Color("#5a2f6a")][tier - 1]
	buf_cap = [400.0, 900.0, 1800.0][tier - 1]
	super._ready()
	_drill = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.1
	dm.bottom_radius = 0.35
	dm.height = 1.2
	_drill.mesh = dm
	_drill.position = Vector3(0, box_size.y + 0.5, 0)
	_drill.material_override = Destructible.make_material(Color("#8fe8ff"), 1.5)
	add_child(_drill)
	dress_industrial(Color("#12222a"))
	# rig hardware: A-frame gantry over the drill, hydraulic rams, ore bin
	for sx in [-1.0, 1.0]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.1, 1.7, 0.1)
		part(leg, Vector3(sx * 0.55, box_size.y + 0.6, 0), Color("#26363e"), 0.1,
			Vector3(0, 0, sx * -18.0))
		var ram := CylinderMesh.new()
		ram.top_radius = 0.06
		ram.bottom_radius = 0.09
		ram.height = 0.8
		part(ram, Vector3(sx * (box_size.x * 0.5 - 0.1), box_size.y * 0.6,
			box_size.z * 0.4), Color("#8fe8ff"), 0.5, Vector3(0, 0, sx * 12.0))
	var beam := BoxMesh.new()
	beam.size = Vector3(1.3, 0.12, 0.12)
	part(beam, Vector3(0, box_size.y + 1.4, 0), Color("#26363e"), 0.1)
	var bin := BoxMesh.new()
	bin.size = Vector3(0.7, 0.4, 0.5)
	part(bin, Vector3(0, 0.3, box_size.z * 0.5 + 0.28), Color("#1a2a32"), 0.15)

func work(delta: float) -> void:
	_survey(delta)
	if not _grounded:
		# no planet under the pads: the drill has nothing to chew
		if _drill:
			_drill.rotate_y(delta * 0.15)
		return
	if Mats.miner_tier(target_ore) > tier:
		if _drill:
			_drill.rotate_y(delta * 0.1)
		return          # this rig physically cannot bite that rock
	var near := _ore_nearby()
	var rich := _richness()
	var otier := int(Mats.def(target_ore).get("tier", 0))
	var eu: float
	var secs: float
	if Mats.has(target_ore):
		# a NEW ore: how much this planet has decides everything
		if rich <= 0:
			eu = FOREIGN_EU * (1.0 + float(otier) * 0.5)
			secs = FOREIGN_SECS * TIER_SPEED[tier - 1]
		else:
			eu = (8.0 + 9.0 * float(otier)) / (1.0 + 0.25 * float(rich))
			secs = maxf(2.5, (13.0 - 1.7 * float(rich)) * TIER_SPEED[tier - 1])
	else:
		eu = NEAR_EU if near else (FAR_EU if _native else FOREIGN_EU)
		secs = (NEAR_SECS if near else (FAR_SECS if _native else FOREIGN_SECS)) \
			* TIER_SPEED[tier - 1]
	if _drill:
		_drill.rotate_y(delta * (7.0 if buf >= eu else 0.4))
	_t += delta
	if _t < secs:
		return
	_t = 0.0
	if buf < eu:
		return
	if str(out_slot["id"]) != "" and str(out_slot["id"]) != target_ore:
		return
	buf -= eu
	if str(out_slot["id"]) == "":
		out_slot = {"id": target_ore, "n": 1}
	else:
		out_slot["n"] = int(out_slot["n"]) + 1
	Sfx.play("smelt", -22.0)

## Where are we, and does this planet even HAVE the target ore?
## Surveyed every 4s, not every frame -- geology is slow.
func _survey(delta: float) -> void:
	_site_t -= delta
	if _site_t > 0.0:
		return
	_site_t = 4.0
	_grounded = false
	_native = false
	# pocket interiors (houses, temples) map elsewhere: not a surface
	if Zones.exterior_of(global_position) != global_position:
		return
	# station decks are floors, not planets
	for h in get_tree().get_nodes_in_group("house"):
		if h is House and h.kind == "station" \
				and h.global_position.distance_to(global_position) < 26.0:
			return
	var b = Universe.nearest(global_position)
	if b == null or global_position.distance_to(b.center) > float(b.radius) + 25.0:
		return
	_grounded = true
	if target_ore == "cheese":
		# the moon IS the deposit
		_native = str(b.name) == "The Moon"
		return
	# native = a surface deposit of the target ore exists on THIS planet
	for o in get_tree().get_nodes_in_group("destructible"):
		if o is Destructible and is_instance_valid(o) and o._res_id == target_ore \
				and o.global_position.distance_to(b.center) < float(b.radius) * 1.3:
			_native = true
			return

## 0..5: how thick this ore is in the ground under the pads.
func _richness() -> int:
	var b = Universe.nearest(global_position)
	return Mats.richness(b, target_ore)

func _ore_nearby() -> bool:
	for o in get_tree().get_nodes_in_group("mine_ore"):
		if global_position.distance_to(o.global_position) < 25.0:
			return true
	return false

func info_text() -> String:
	var near := _ore_nearby()
	var mode: String
	if Mats.miner_tier(target_ore) > tier:
		return "TIER %d RIG\ntarget: %s needs a MK%d miner -- this one cannot bite it.\n%s is found on: %s" % [
			tier, Inventory.hotbar_name(target_ore), Mats.miner_tier(target_ore),
			Inventory.hotbar_name(target_ore), Mats.best_worlds(target_ore)]
	if Mats.has(target_ore):
		var b2 = Universe.nearest(global_position)
		var r2 := _richness()
		return "TIER %d RIG · energy %.0f / %.0f EU\ntarget: %s\nout: %s\n%s: richness %d/5%s\nrichest worlds: %s" % [
			tier, buf, buf_cap, Inventory.hotbar_name(target_ore),
			Inventory.slot_text(out_slot),
			str(b2.name) if b2 != null else "nowhere", r2,
			"  (none here -- fabricating from dust, glacially)" if r2 <= 0 else "",
			Mats.best_worlds(target_ore)]
	if not _grounded:
		mode = "OFFLINE: needs bare planet surface (no houses, no station decks)"
	elif near:
		mode = "NEAR ORE: %d EU / %ds" % [int(NEAR_EU), int(NEAR_SECS)]
	elif _native:
		mode = "REMOTE: %d EU / %ds (thirsty)" % [int(FAR_EU), int(FAR_SECS)]
	else:
		mode = "FOREIGN ORE: %d EU / %ds (this planet has none. glacial.)" % [int(FOREIGN_EU), int(FOREIGN_SECS)]
	return "energy: %.0f / %.0f EU\ntarget: %s\nout: %s\n%s" % [
		buf, buf_cap, Inventory.hotbar_name(target_ore), Inventory.slot_text(out_slot), mode]

func actions() -> Array:
	return [
		["Target: " + Inventory.hotbar_name(target_ore) + "  (pick)", func() -> void:
			var b9 = Universe.nearest(global_position)
			var opts: Array = []
			for oid in Mats.ores_for_miner(tier):
				var r9 := Mats.richness(b9, str(oid))
				opts.append({"id": str(oid), "label": "%s   %s  ·  best: %s" % [
					Inventory.hotbar_name(str(oid)),
					("richness %d/5 here" % r9) if r9 > 0 else "NONE here (glacial)",
					Mats.best_worlds(str(oid), 2)]})
			for oid2 in Mats.ores():
				if Mats.miner_tier(str(oid2)) > tier:
					opts.append({"id": str(oid2), "label": "%s   [needs MK%d rig]" % [
						Inventory.hotbar_name(str(oid2)), Mats.miner_tier(str(oid2))]})
			if b9 != null and str(b9.name) == "The Moon":
				opts.append({"id": "cheese", "label": "CHEESE (this IS the moon)"})
			var pui := PickUI.new().configure("MINER TARGET", opts,
				func(pick: String) -> void:
					target_ore = pick
					_site_t = 0.0
					Sfx.play("click"))
			get_tree().current_scene.add_child(pui)
			use()],
	]
