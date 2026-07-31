class_name Furnace
extends Machine
## Classic furnace: SLOW. Load raw ore (or meat), it smelts one item at a
## time into the output slot. Funnel-compatible. Electric furnace is the
## fast one.

const RECIPES := {"raw_ingot": "ingot", "raw_irid": "irid", "meat": "cooked_meat"}
const SECS_PER_ITEM := 0.5

var _t: float = 0.0

func _init() -> void:
	title = "FURNACE"
	box_color = Color("#5a4a42")
	refund_id = "furnace"
	add_to_group("furnace")

func work(delta: float) -> void:
	var id := str(in_slot["id"])
	if not RECIPES.has(id) or int(in_slot["n"]) <= 0:
		_t = 0.0
		return
	var product: String = RECIPES[id]
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
	return RECIPES.has(id)

func info_text() -> String:
	return "in:  %s\nout: %s\nsmelts 1 item / %.1fs" % [
		Inventory.slot_text(in_slot), Inventory.slot_text(out_slot), SECS_PER_ITEM]

func actions() -> Array:
	return [

	]
