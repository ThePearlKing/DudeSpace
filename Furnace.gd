class_name Furnace
extends Machine
## Classic furnace: SLOW. Load raw ore (or meat), it smelts one item at a
## time into the output slot. Funnel-compatible. Electric furnace is the
## fast one.

const RECIPES := {"raw_ingot": "ingot", "raw_irid": "irid", "meat": "cooked_meat"}

## Ore and dust both smelt to the metal the registry says they do.
static func product_of(id: String) -> String:
	if RECIPES.has(id):
		return str(RECIPES[id])
	return Mats.smelts_to(id)
const SECS_PER_ITEM := 0.5

var _t: float = 0.0
var _fire: MeshInstance3D

func _init() -> void:
	title = "FURNACE"
	box_color = Color("#5a4a42")
	refund_id = "furnace"
	add_to_group("furnace")

func _ready() -> void:
	super._ready()
	dress_industrial(Color("#2c2420"))
	# tapered brick chimney with a soot cap
	var chim := CylinderMesh.new()
	chim.top_radius = 0.16
	chim.bottom_radius = 0.24
	chim.height = 1.2
	part(chim, Vector3(-0.35, box_size.y + 0.6, -0.3), Color("#4a3a32"), 0.08)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.24
	cap.bottom_radius = 0.24
	cap.height = 0.1
	part(cap, Vector3(-0.35, box_size.y + 1.22, -0.3), Color("#17130f"), 0.02)
	# arched firebox mouth: dark frame, glowing core (flares while smelting)
	var frame := BoxMesh.new()
	frame.size = Vector3(0.9, 0.7, 0.08)
	part(frame, Vector3(0, 0.5, box_size.z * 0.5 + 0.02), Color("#241c16"), 0.02)
	var core := BoxMesh.new()
	core.size = Vector3(0.66, 0.48, 0.1)
	_fire = part(core, Vector3(0, 0.48, box_size.z * 0.5 + 0.04), Color("#ff7a1a"), 0.5)
	# hearth lip below the mouth
	var lip := BoxMesh.new()
	lip.size = Vector3(1.0, 0.12, 0.34)
	part(lip, Vector3(0, 0.12, box_size.z * 0.5 + 0.12), Color("#2c2420"), 0.05)
	# side heat vents
	for sx in [-1.0, 1.0]:
		var vent := BoxMesh.new()
		vent.size = Vector3(0.06, 0.5, 0.7)
		part(vent, Vector3(sx * (box_size.x * 0.5 + 0.02), 0.9, 0), Color("#3a2c24"), 0.15)

func work(delta: float) -> void:
	var id := str(in_slot["id"])
	var lit := product_of(id) != "" and int(in_slot["n"]) > 0
	if _fire and _fire.material_override is StandardMaterial3D:
		_fire.material_override.emission_energy_multiplier = 4.0 if lit else 0.5
	if not lit:
		_t = 0.0
		return
	var product: String = product_of(id)
	if str(out_slot["id"]) != "" and str(out_slot["id"]) != product:
		return   # output blocked by a different item
	_t += delta
	if _t >= SECS_PER_ITEM:
		_t = 0.0
		in_slot["n"] = int(in_slot["n"]) - 1
		if int(in_slot["n"]) <= 0:
			in_slot = {"id": "", "n": 0}
		if str(out_slot["id"]) == "":
			out_slot = {"id": product, "n": 1}
		else:
			out_slot["n"] = int(out_slot["n"]) + 1

func accepts(id: String) -> bool:
	return product_of(id) != ""

func info_text() -> String:
	return "in:  %s\nout: %s\nsmelts 1 item / %.1fs" % [
		Inventory.slot_text(in_slot), Inventory.slot_text(out_slot), SECS_PER_ITEM]

func actions() -> Array:
	return [

	]
