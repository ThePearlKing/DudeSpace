class_name StorageUI
extends CanvasLayer
## Opened by a chest (F). Two rows: the chest's 10 slots and your 5 hotbar
## slots. Click an item to move it to the first free slot in the other row.

var _chest    # anything with a `storage` Array: Chest, or the backpack ref
var _chest_cells: Array = []
var _hot_cells: Array = []
var _title: Label
var held: Dictionary = {"id": "", "n": 0}   # the stack ON YOUR CURSOR
var _cursor: Label

## Wrapper so any carried pack opens like a chest.
class PackRef:
	var storage: Array
	func _init(arr: Array = []) -> void:
		storage = arr if not arr.is_empty() else Inventory.backpack_store

func _ready() -> void:
	layer = 22
	visible = false
	add_to_group("closable_ui")
	add_to_group("storage_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# click OUTSIDE the panel while holding a stack -> toss it on the floor
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and str(held["id"]) != "":
			Inventory.drop_stack(str(held["id"]), int(held["n"]))
			held = Inventory.empty_slot()
			Inventory.changed.emit())
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 560)
	panel.size = Vector2(760, 560)
	panel.position = Vector2(-380, -280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#181822")
	sb.border_color = Color("#3a3a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(20, 18)
	panel.add_child(col)

	_title = Label.new()
	_title.text = "CHEST"
	_title.add_theme_font_size_override("font_size", 20)
	col.add_child(_title)
	var chest_grid := GridContainer.new()
	chest_grid.columns = 5
	chest_grid.add_theme_constant_override("h_separation", 8)
	chest_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(chest_grid)
	for i in 40:
		var c := _Slot.new()
		c.where = "chest"
		c.index = i
		c.custom_minimum_size = Vector2(130, 44)
		chest_grid.add_child(c)
		_chest_cells.append(c)

	var t2 := Label.new()
	t2.text = "HOTBAR   (click = move · click outside = drop · 🗑 = delete)"
	t2.add_theme_font_size_override("font_size", 16)
	col.add_child(t2)
	var hot := HBoxContainer.new()
	hot.add_theme_constant_override("separation", 8)
	col.add_child(hot)
	for i in 5:
		var c := _Slot.new()
		c.where = "hotbar"
		c.index = i
		c.custom_minimum_size = Vector2(130, 54)
		hot.add_child(c)
		_hot_cells.append(c)
	var trash := Panel.new()
	trash.custom_minimum_size = Vector2(130, 54)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("#2e1414")
	tsb.border_color = Color("#a04040")
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(6)
	trash.add_theme_stylebox_override("panel", tsb)
	var tl := Label.new()
	tl.text = "🗑 DELETE"
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 13)
	tl.modulate = Color("#ff8080")
	trash.add_child(tl)
	trash.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT and str(held["id"]) != "":
			held = Inventory.empty_slot()
			Sfx.play("explode", -20.0)
			Inventory.changed.emit())
	hot.add_child(trash)

	var close := Label.new()
	close.text = "F / E / Esc to close"
	close.modulate = Color(1, 1, 1, 0.55)
	col.add_child(close)

	# the stack riding the mouse
	_cursor = Label.new()
	_cursor.add_theme_font_size_override("font_size", 14)
	_cursor.z_index = 100
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)

	Inventory.changed.connect(_refresh)

func _process(_delta: float) -> void:
	if not visible or _cursor == null:
		return
	_cursor.visible = str(held["id"]) != ""
	if _cursor.visible:
		_cursor.text = Inventory.slot_text(held)
		_cursor.position = get_viewport().get_mouse_position() + Vector2(14, -8)

func open(chest) -> void:
	_chest = chest
	_title.text = "CHEST"
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func open_backpack(kind: String = "backpack") -> void:
	match kind:
		"backpack2":
			_chest = PackRef.new(Inventory.prism_store)
			_title.text = "PRISM BACKPACK"
		"ubackpack":
			_chest = PackRef.new(Inventory.universe_store)
			_title.text = "UNIVERSE BACKPACK"
		_:
			_chest = PackRef.new(Inventory.backpack_store)
			_title.text = "BACKPACK"
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("click")
	_refresh()

func close_ui() -> void:
	if str(held["id"]) != "":
		Inventory.give(str(held["id"]), int(held["n"]))
		held = {"id": "", "n": 0}
	visible = false
	_chest = null
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## MINECRAFT RULES.
## Left: pick up stack / put down stack / swap.
## Right: pick up HALF / deposit exactly ONE.
## Scroll: stream items one at a time into the other container.
func slot_click(where: String, index: int, btn: int) -> void:
	if _chest == null:
		return
	var cont := container_of(where)
	if index >= cont.size():
		return
	var slot: Dictionary = cont[index]
	var sid := str(slot["id"])
	var hid := str(held["id"])
	# no backpacks inside the backpack. the universe would fold.
	if _chest is PackRef and where == "chest" and hid in ["backpack", "backpack2", "ubackpack"]:
		Sfx.play("denied")
		return
	if btn == MOUSE_BUTTON_LEFT:
		if hid == "":
			if sid == "":
				return
			held = {"id": sid, "n": int(slot["n"])}
			cont[index] = Inventory.empty_slot()
		elif sid == "":
			cont[index] = {"id": hid, "n": int(held["n"])}
			held = {"id": "", "n": 0}
		elif sid == hid and Inventory.STACKABLE.has(hid):
			var room: int = Inventory.STACK_MAX - int(slot["n"])
			var put: int = mini(room, int(held["n"]))
			slot["n"] = int(slot["n"]) + put
			held["n"] = int(held["n"]) - put
			if int(held["n"]) <= 0:
				held = {"id": "", "n": 0}
		else:
			cont[index] = {"id": hid, "n": int(held["n"])}
			held = {"id": sid, "n": int(slot["n"])}
	elif btn == MOUSE_BUTTON_RIGHT:
		if hid == "":
			if sid == "":
				return
			var take := ceili(int(slot["n"]) / 2.0)
			held = {"id": sid, "n": take}
			slot["n"] = int(slot["n"]) - take
			if int(slot["n"]) <= 0:
				cont[index] = Inventory.empty_slot()
		else:
			if sid == "":
				cont[index] = {"id": hid, "n": 1}
				held["n"] = int(held["n"]) - 1
			elif sid == hid and Inventory.STACKABLE.has(hid) and int(slot["n"]) < Inventory.STACK_MAX:
				slot["n"] = int(slot["n"]) + 1
				held["n"] = int(held["n"]) - 1
			else:
				return
			if int(held["n"]) <= 0:
				held = {"id": "", "n": 0}
	Sfx.play("click", -18.0)
	Inventory.changed.emit()

## Wheel over a slot: ONE item hops to the other container per notch.
func slot_scroll(where: String, index: int) -> void:
	if _chest == null:
		return
	var src := container_of(where)
	if index >= src.size():
		return
	var slot: Dictionary = src[index]
	var sid := str(slot["id"])
	if sid == "" or int(slot["n"]) <= 0:
		return
	var dst: Array = Inventory.hotbar if where == "chest" else _chest.storage
	if _chest is PackRef and where != "chest" and sid in ["backpack", "backpack2", "ubackpack"]:
		Sfx.play("denied")
		return
	# merge first, then first empty
	for s2 in dst:
		if str(s2["id"]) == sid and Inventory.STACKABLE.has(sid) and int(s2["n"]) < Inventory.STACK_MAX:
			s2["n"] = int(s2["n"]) + 1
			_take_one(src, index)
			return
	for i in dst.size():
		if str(dst[i]["id"]) == "":
			dst[i] = {"id": sid, "n": 1}
			_take_one(src, index)
			return
	Sfx.play("denied", -20.0)

func _take_one(src: Array, index: int) -> void:
	src[index]["n"] = int(src[index]["n"]) - 1
	if int(src[index]["n"]) <= 0:
		src[index] = Inventory.empty_slot()
	Sfx.play("click", -20.0)
	Inventory.changed.emit()

func move(where: String, index: int) -> void:
	if _chest == null:
		return
	var src: Array = _chest.storage if where == "chest" else Inventory.hotbar
	var dst: Array = Inventory.hotbar if where == "chest" else _chest.storage
	if index >= src.size():
		return
	var slot: Dictionary = src[index]
	var id := str(slot["id"])
	if id == "":
		return
	# no backpacks inside the backpack. the universe would fold.
	if id in ["backpack", "backpack2", "ubackpack"] and _chest is PackRef and where != "chest":
		Sfx.play("denied")
		return
	# merge into an existing stack
	if Inventory.STACKABLE.has(id):
		for s in dst:
			if str(s["id"]) == id:
				s["n"] = int(s["n"]) + int(slot["n"])
				src[index] = Inventory.empty_slot()
				Sfx.play("click", -14.0)
				Inventory.changed.emit()
				return
	for i in dst.size():
		if str(dst[i]["id"]) == "":
			dst[i] = {"id": id, "n": int(slot["n"])}
			src[index] = Inventory.empty_slot()
			Sfx.play("click", -14.0)
			Inventory.changed.emit()
			return
	Sfx.play("denied")

func _refresh() -> void:
	if not visible or _chest == null:
		return
	for i in _chest_cells.size():
		if i < _chest.storage.size():
			_chest_cells[i].visible = true
			_chest_cells[i].set_item(Inventory.slot_text(_chest.storage[i]))
		else:
			_chest_cells[i].visible = false
	for i in _hot_cells.size():
		_hot_cells[i].set_item(Inventory.slot_text(Inventory.hotbar[i]))

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_F, KEY_ESCAPE]:
		close_ui()
		get_viewport().set_input_as_handled()

func container_of(where: String) -> Array:
	return _chest.storage if where == "chest" else Inventory.hotbar

## drag between any two slots (chest <-> hotbar included)
func drag_swap(w1: String, i1: int, w2: String, i2: int) -> void:
	var a := container_of(w1)
	var b := container_of(w2)
	if i1 >= a.size() or i2 >= b.size():
		return
	# never a backpack inside the backpack
	if _chest is PackRef:
		var moving_in := (w2 == "chest" and str(a[i1]["id"]) == "backpack") \
			or (w1 == "chest" and str(b[i2]["id"]) == "backpack")
		if moving_in:
			Sfx.play("denied")
			return
	var t: Dictionary = a[i1]
	a[i1] = b[i2]
	b[i2] = t
	Sfx.play("click", -14.0)
	Inventory.changed.emit()

class _Slot extends Panel:
	var where: String = ""
	var index: int = 0
	var _lbl: Label

	func _ui() -> StorageUI:
		var n: Node = self
		while n:
			if n is StorageUI:
				return n
			n = n.get_parent()
		return null

	func _ready() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#23232e")
		sb.border_color = Color("#3a3a48")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		add_theme_stylebox_override("panel", sb)
		# hover glow, like everywhere else
		mouse_entered.connect(func() -> void: modulate = Color(1.25, 1.25, 1.25))
		mouse_exited.connect(func() -> void: modulate = Color(1, 1, 1))
		_lbl = Label.new()
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.add_theme_font_size_override("font_size", 13)
		_lbl.clip_text = true
		_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(_lbl)

	func set_item(txt: String) -> void:
		if _lbl:
			_lbl.text = txt

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var ui := _ui()
			if ui == null:
				return
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				modulate = Color(1.6, 1.6, 1.3)
				var tw := create_tween()
				tw.tween_property(self, "modulate", Color(1.25, 1.25, 1.25), 0.18)
				ui.slot_click(where, index, event.button_index)
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				ui.slot_scroll(where, index)
