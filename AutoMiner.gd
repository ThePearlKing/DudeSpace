class_name AutoMiner
extends Machine
## ELECTRIC auto-miner. Works ANYWHERE -- but parked next to ore it's
## fast and cheap; out in the void it drills slow and drinks POWER.
## F: pick which ore it fabricates (no crystals. they refuse).

const NEAR_EU := 8.0
const NEAR_SECS := 5.0
const FAR_EU := 40.0
const FAR_SECS := 9.0

var target_ore: String = "raw_ingot"
var _t: float = 0.0
var _drill: MeshInstance3D

func _init() -> void:
	title = "AUTO-MINER"
	box_color = Color("#3a5a6a")
	refund_id = "autominer"
	buf_cap = 400.0
	add_to_group("autominer")

func _ready() -> void:
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

func work(delta: float) -> void:
	var near := _ore_nearby()
	var eu := NEAR_EU if near else FAR_EU
	var secs := NEAR_SECS if near else FAR_SECS
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

func _ore_nearby() -> bool:
	for o in get_tree().get_nodes_in_group("mine_ore"):
		if global_position.distance_to(o.global_position) < 25.0:
			return true
	return false

func info_text() -> String:
	var near := _ore_nearby()
	var mode := "NEAR ORE: %d EU / %ds" % [int(NEAR_EU), int(NEAR_SECS)] if near \
		else "REMOTE: %d EU / %ds (thirsty)" % [int(FAR_EU), int(FAR_SECS)]
	return "energy: %.0f / %.0f EU\ntarget: %s\nout: %s\n%s" % [
		buf, buf_cap, Inventory.hotbar_name(target_ore), Inventory.slot_text(out_slot), mode]

func actions() -> Array:
	return [
		["Target: " + Inventory.hotbar_name(target_ore) + "  (switch)", func() -> void:
			target_ore = "raw_irid" if target_ore == "raw_ingot" else "raw_ingot"
			Sfx.play("click")
			use()],
	]
