class_name Chest
extends Machine
## A placed container: 20 slots. F opens the transfer UI. Funnels work
## BOTH ways: pour items in, and it feeds its contents out through
## outgoing funnels (first stack first).

var storage: Array = []

func _init() -> void:
	title = "CHEST"
	box_color = Color("#a9713b")
	box_size = Vector3(1.4, 1.0, 1.0)
	refund_id = "chest"
	add_to_group("chest")
	for i in 20:
		storage.append(Inventory.empty_slot())

func _ready() -> void:
	super._ready()
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.44, 0.2, 1.04)
	lid.mesh = lm
	lid.position = Vector3(0, 1.05, 0)
	lid.material_override = Destructible.make_material(Color("#7d5228"), 0.15)
	add_child(lid)

func accepts(_id: String) -> bool:
	return true   # a chest takes anything

## Funnels pour items straight into storage.
func accept_item(id: String) -> bool:
	for s2 in storage:
		if str(s2["id"]) == id and Inventory.STACKABLE.has(id) and int(s2["n"]) < 999:
			s2["n"] = int(s2["n"]) + 1
			return true
	for s2 in storage:
		if str(s2["id"]) == "":
			s2["id"] = id
			s2["n"] = 1
			return true
	return false

## Keep the outgoing slot fed from storage so outgoing funnels can drain
## the chest one item at a time.
func work(_delta: float) -> void:
	if funnels_out.is_empty():
		return
	if str(out_slot["id"]) != "" and int(out_slot["n"]) > 0:
		return
	for s2 in storage:
		if str(s2["id"]) != "" and int(s2["n"]) > 0:
			out_slot = {"id": str(s2["id"]), "n": 1}
			s2["n"] = int(s2["n"]) - 1
			if int(s2["n"]) <= 0:
				s2["id"] = ""
				s2["n"] = 0
			return

func use() -> void:
	var ui := get_tree().get_first_node_in_group("storage_ui")
	if ui and ui.has_method("open"):
		ui.open(self)

## Breaking it: contents + the chest come back (cables clean up via super).
func _on_destroyed(push_dir: Vector3) -> void:
	for s2 in storage:
		if str(s2["id"]) != "":
			Inventory.give_at(str(s2["id"]), int(s2["n"]), global_position)
	super._on_destroyed(push_dir)
