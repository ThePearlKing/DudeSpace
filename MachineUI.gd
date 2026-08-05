class_name MachineUI
extends CanvasLayer
## Machine panel (F on any machine). REAL SLOTS, minecraft rules:
## IN slot -> arrow -> OUT slot, your hotbar underneath, and a cursor
## stack. Click grab/place, right-click half/one, scroll moves one item
## between the machine and your hotbar.

var _m: Machine
var _title: Label
var _info: Label
var _btn_box: VBoxContainer
var _in_cell: _MSlot
var _out_cell: _MSlot
var _arrow: Label
var _hb_cells: Array = []
var held: Dictionary = {"id": "", "n": 0}   # stack riding the cursor
var _cursor: Label

func _ready() -> void:
	layer = 22
	visible = false
	add_to_group("machine_ui")
	add_to_group("closable_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(500, 520)
	panel.size = Vector2(500, 520)
	panel.position = Vector2(-250, -260)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#181822")
	sb.border_color = Color("#3a3a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	col.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)

	# --- the slots: IN -> OUT ---
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 14)
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(srow)
	_in_cell = _MSlot.new()
	_in_cell.which = "in"
	_in_cell.custom_minimum_size = Vector2(150, 64)
	srow.add_child(_in_cell)
	_arrow = Label.new()
	_arrow.text = "→"
	_arrow.add_theme_font_size_override("font_size", 30)
	_arrow.modulate = Color(1, 1, 1, 0.6)
	srow.add_child(_arrow)
	_out_cell = _MSlot.new()
	_out_cell.which = "out"
	_out_cell.custom_minimum_size = Vector2(150, 64)
	srow.add_child(_out_cell)

	_btn_box = VBoxContainer.new()
	_btn_box.add_theme_constant_override("separation", 8)
	col.add_child(_btn_box)

	# --- your hotbar: full minecraft slots ---
	var hb_lbl := Label.new()
	hb_lbl.text = "HOTBAR"
	hb_lbl.add_theme_font_size_override("font_size", 12)
	hb_lbl.modulate = Color(1, 1, 1, 0.55)
	col.add_child(hb_lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(hb)
	for i in 5:
		var cell := _MSlot.new()
		cell.which = "hot"
		cell.index = i
		cell.custom_minimum_size = Vector2(86, 52)
		hb.add_child(cell)
		_hb_cells.append(cell)

	var close := Label.new()
	close.text = "F / E / Esc close · click grab · r-click half/one · scroll moves 1"
	close.add_theme_font_size_override("font_size", 12)
	close.modulate = Color(1, 1, 1, 0.5)
	col.add_child(close)

	# cursor stack label
	_cursor = Label.new()
	_cursor.add_theme_font_size_override("font_size", 14)
	_cursor.z_index = 100
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)

func open_machine(m: Machine) -> void:
	_m = m
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("click")
	for c in _btn_box.get_children():
		c.queue_free()
	var show_slots := true
	if m.has_method("build_ui"):
		m.build_ui(_btn_box)   # machine brings its own controls (e.g. ATM)
		show_slots = false
	else:
		for act in m.actions():
			var b := Button.new()
			b.text = str(act[0])
			b.custom_minimum_size = Vector2(0, 40)
			b.pressed.connect(act[1])
			_btn_box.add_child(b)
	# machines only show the slots they actually use
	_in_cell.get_parent().visible = show_slots and (m.shows_in or m.shows_out)
	_in_cell.visible = m.shows_in
	_out_cell.visible = m.shows_out
	_arrow.visible = m.shows_in and m.shows_out
	_refresh()

func close_ui() -> void:
	if str(held["id"]) != "":
		Inventory.give(str(held["id"]), int(held["n"]))   # overflow DROPS, never deletes
		held = {"id": "", "n": 0}
	visible = false
	_m = null
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh()
	_cursor.visible = str(held["id"]) != ""
	if _cursor.visible:
		_cursor.text = Inventory.slot_text(held)
		_cursor.position = get_viewport().get_mouse_position() + Vector2(14, -8)

func _refresh() -> void:
	if _m == null or not is_instance_valid(_m):
		close_ui()
		return
	_title.text = _m.title
	_info.text = _m.info_text()
	_in_cell.refresh(_m, self)
	_out_cell.refresh(_m, self)
	for c in _hb_cells:
		c.refresh(_m, self)

# ------------------------------------------------ minecraft slot logic

func _slot_of(cell: _MSlot) -> Dictionary:
	match cell.which:
		"in": return _m.in_slot
		"out": return _m.out_slot
		_: return Inventory.hotbar[cell.index]

func _set_slot(cell: _MSlot, v: Dictionary) -> void:
	match cell.which:
		"in": _m.in_slot = v
		"out": _m.out_slot = v
		_: Inventory.hotbar[cell.index] = v

## Can this cell RECEIVE this item?
func _can_place(cell: _MSlot, id: String) -> bool:
	if cell.which == "hot":
		return true
	if cell.which == "out":
		return false
	return _m != null and _m.accepts(id)

func cell_click(cell: _MSlot, btn: int) -> void:
	if _m == null:
		return
	var slot := _slot_of(cell)
	var sid := str(slot["id"])
	var hid := str(held["id"])
	if btn == MOUSE_BUTTON_LEFT:
		if hid == "":
			if sid == "":
				return
			held = {"id": sid, "n": int(slot["n"])}
			_set_slot(cell, Inventory.empty_slot())
		elif sid == "":
			if not _can_place(cell, hid):
				Sfx.play("denied", -20.0)
				return
			_set_slot(cell, {"id": hid, "n": int(held["n"])})
			held = {"id": "", "n": 0}
		elif sid == hid and Inventory.STACKABLE.has(hid) and _can_place(cell, hid):
			var room: int = Inventory.STACK_MAX - int(slot["n"])
			var put: int = mini(room, int(held["n"]))
			slot["n"] = int(slot["n"]) + put
			held["n"] = int(held["n"]) - put
			if int(held["n"]) <= 0:
				held = {"id": "", "n": 0}
		else:
			if not _can_place(cell, hid):
				Sfx.play("denied", -20.0)
				return
			_set_slot(cell, {"id": hid, "n": int(held["n"])})
			held = {"id": sid, "n": int(slot["n"])}
	elif btn == MOUSE_BUTTON_RIGHT:
		if hid == "":
			if sid == "":
				return
			var take := ceili(int(slot["n"]) / 2.0)
			held = {"id": sid, "n": take}
			slot["n"] = int(slot["n"]) - take
			if int(slot["n"]) <= 0:
				_set_slot(cell, Inventory.empty_slot())
		else:
			if not _can_place(cell, hid):
				Sfx.play("denied", -20.0)
				return
			if sid == "":
				_set_slot(cell, {"id": hid, "n": 1})
			elif sid == hid and Inventory.STACKABLE.has(hid) and int(slot["n"]) < Inventory.STACK_MAX:
				slot["n"] = int(slot["n"]) + 1
			else:
				return
			held["n"] = int(held["n"]) - 1
			if int(held["n"]) <= 0:
				held = {"id": "", "n": 0}
	Sfx.play("click", -18.0)
	Inventory.changed.emit()

## Scroll: ONE item hops between the machine and the hotbar.
func cell_scroll(cell: _MSlot) -> void:
	if _m == null:
		return
	var slot := _slot_of(cell)
	var sid := str(slot["id"])
	if cell.which == "hot":
		# hotbar -> machine IN
		if sid == "" or not _m.accepts(sid):
			return
		var dst := _m.in_slot
		if str(dst["id"]) == "":
			_m.in_slot = {"id": sid, "n": 1}
		elif str(dst["id"]) == sid and int(dst["n"]) < Inventory.STACK_MAX:
			dst["n"] = int(dst["n"]) + 1
		else:
			return
		slot["n"] = int(slot["n"]) - 1
		if int(slot["n"]) <= 0:
			Inventory.hotbar[cell.index] = Inventory.empty_slot()
	else:
		# machine -> hotbar
		if sid == "" or int(slot["n"]) <= 0:
			return
		var placed := false
		for s2 in Inventory.hotbar:
			if str(s2["id"]) == sid and Inventory.STACKABLE.has(sid) and int(s2["n"]) < Inventory.STACK_MAX:
				s2["n"] = int(s2["n"]) + 1
				placed = true
				break
		if not placed:
			for i in Inventory.hotbar.size():
				if str(Inventory.hotbar[i]["id"]) == "":
					Inventory.hotbar[i] = {"id": sid, "n": 1}
					placed = true
					break
		if not placed:
			Sfx.play("denied", -20.0)
			return
		slot["n"] = int(slot["n"]) - 1
		if int(slot["n"]) <= 0:
			_set_slot(cell, Inventory.empty_slot())
	Sfx.play("click", -20.0)
	Inventory.changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_F, KEY_ESCAPE]:
		close_ui()
		get_viewport().set_input_as_handled()

## One slot cell: label + minecraft mouse handling.
class _MSlot extends Panel:
	var which: String = "hot"   # "in" | "out" | "hot"
	var index: int = 0
	var _lbl: Label
	var _tag: Label

	func _ready() -> void:
		mouse_entered.connect(func() -> void: modulate = Color(1.25, 1.25, 1.25))
		mouse_exited.connect(func() -> void: modulate = Color(1, 1, 1))
		_tag = Label.new()
		_tag.text = {"in": "IN", "out": "OUT", "hot": str(index + 1)}[which]
		_tag.add_theme_font_size_override("font_size", 10)
		_tag.modulate = Color(1, 1, 1, 0.45)
		_tag.position = Vector2(5, 2)
		add_child(_tag)
		_lbl = Label.new()
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.add_theme_font_size_override("font_size", 12)
		_lbl.clip_text = true
		_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lbl)

	func refresh(m: Machine, ui: MachineUI) -> void:
		if _lbl == null:
			return
		var slot: Dictionary
		var selected := false
		match which:
			"in": slot = m.in_slot
			"out": slot = m.out_slot
			_:
				slot = Inventory.hotbar[index]
				selected = index == Inventory.selected
		_lbl.text = Inventory.slot_text(slot)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#23232e")
		sb.border_color = Color("#ffe066") if selected else Color("#3a3a48")
		sb.set_border_width_all(2 if selected else 1)
		sb.set_corner_radius_all(5)
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not event.pressed:
			return
		var ui: Node = self
		while ui and not ui is MachineUI:
			ui = ui.get_parent()
		if ui == null:
			return
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			modulate = Color(1.6, 1.6, 1.3)
			var tw := create_tween()
			tw.tween_property(self, "modulate", Color(1.25, 1.25, 1.25), 0.18)
			ui.cell_click(self, event.button_index)
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			ui.cell_scroll(self)
