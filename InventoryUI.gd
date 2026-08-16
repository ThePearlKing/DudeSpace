class_name InventoryUI
extends CanvasLayer
## Solid grid shop. A draggable coin chip sits top-left; drag it onto an
## item cell (or just click the cell) to buy -> the item lands in your
## 5-slot hotbar. Right-click a hotbar slot to drop that item.

var _coin_lbl: Label
var _grid: GridContainer
var _cells: Array = []          # [{id, panel, icon, cost}]
var _slot_panels: Array = []
var _slot_lbls: Array = []
var _tab: String = "Gear"
var _tab_btns: Array = []
var _creative_btn: Button
var _creative2_btn: Button
var _equip_slots: Array = []
var _eq_lbl: Label
var held: Dictionary = {"id": "", "n": 0}   # stack riding the cursor
var _held_cursor: Label

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()
	if _tab == "Creative":
		# only things that EXIST but aren't buyable in the normal tabs:
		# resources, drops, raw ore, weird loot. free.
		# everything the materials registry adds lives on CREATIVE 2 --
		# a hundred ores, dusts, bars and compounds buried this tab.
		var in_catalog := {}
		for it in Inventory.catalog:
			in_catalog[str(it.id)] = true
		for id in Inventory.weapons.keys() + Inventory.items.keys():
			if id == "fists" or id == "caged_animal" or id == "caged_human" or in_catalog.has(id):
				continue
			if Mats.has(str(id)):
				continue
			_grid.add_child(_make_cell({"id": id, "name": Inventory.hotbar_name(id), "desc": "creative: free"}))
	elif _tab == "Creative 2":
		# the mining and chemistry half: ore, dust, bars, alloys and every
		# compound, in the order the chain actually runs
		const KIND_ORDER := {"ore": 0, "dust": 1, "ingot": 2, "alloy": 3}
		var rows: Array = []
		for id in Mats.all().keys():
			var d: Dictionary = Mats.all()[id]
			rows.append([int(KIND_ORDER.get(str(d.get("kind", "")), 4)),
				int(d.get("tier", 0)), str(d.get("name", id)), str(id), d])
		rows.sort_custom(func(a, b):
			if int(a[0]) != int(b[0]):
				return int(a[0]) < int(b[0])
			if int(a[1]) != int(b[1]):
				return int(a[1]) < int(b[1])
			return str(a[2]) < str(b[2]))
		for row in rows:
			var d2: Dictionary = row[4]
			var kind := str(d2.get("kind", "material"))
			_grid.add_child(_make_cell({"id": str(row[3]),
				"name": str(row[2]),
				"desc": "creative: free  ·  %s, tier %d" % [kind, int(row[1])]}))
	else:
		for item in Inventory.catalog:
			if item.get("tab", "Gear") == _tab:
				_grid.add_child(_make_cell(item))
	_refresh()

func _ready() -> void:
	layer = 20
	visible = false
	add_to_group("closable_ui")

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
	panel.custom_minimum_size = Vector2(920, 660)
	panel.size = Vector2(920, 660)
	panel.position = Vector2(-460, -330)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#181822")             # SOLID, not transparent
	sb.border_color = Color("#3a3a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	# --- header: draggable coin chip + counts ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)
	var chip := _CoinChip.new()
	header.add_child(chip)
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 22)
	_coin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_coin_lbl)
	var help := Label.new()
	help.text = "drag coins onto an item  (or click it)  ·  E / Esc to close"
	help.modulate = Color(1, 1, 1, 0.55)
	help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(help)

	# --- the MONOLITH TRACKER: its own little plaque floating above the
	# menu's top-left corner. Eight triangle slots, dark until their
	# monolith drinks its tetrahedron. Ocarina rules.
	var mono := HBoxContainer.new()
	mono.add_theme_constant_override("separation", 6)
	mono.add_to_group("mono_tracker")
	mono.set_script(preload("res://MonoTracker.gd"))
	panel.add_child(mono)
	mono.position = Vector2(4, -42)
	(mono as Node).call("refresh")

	# --- tab row (scrolls sideways once there are too many tabs) ---
	var tabscroll := ScrollContainer.new()
	tabscroll.custom_minimum_size = Vector2(876, 48)
	tabscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(tabscroll)
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 8)
	tabscroll.add_child(tabrow)
	for t in Inventory.tabs + ["Creative", "Creative 2"]:
		var tb := Button.new()
		tb.text = t
		tb.custom_minimum_size = Vector2(125, 40)
		tb.pressed.connect(func() -> void:
			_tab = t
			_rebuild_grid()
			Sfx.play("click", -14.0))
		tabrow.add_child(tb)
		_tab_btns.append(tb)
		if t == "Creative":
			_creative_btn = tb
		elif t == "Creative 2":
			_creative2_btn = tb

	# --- shop grid ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(876, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	_rebuild_grid()

	# --- equipment: head/chest/legs/feet + the charm socket ---
	_eq_lbl = Label.new()
	_eq_lbl.add_theme_font_size_override("font_size", 14)
	col.add_child(_eq_lbl)
	var eqrow := HBoxContainer.new()
	eqrow.add_theme_constant_override("separation", 8)
	col.add_child(eqrow)
	for es in ["head", "chest", "legs", "boots", "charm"]:
		var ep := _EquipSlot.new()
		ep.slot_name = es
		ep.custom_minimum_size = Vector2(168, 46)
		eqrow.add_child(ep)
		_equip_slots.append(ep)

	# --- hotbar row (right-click a slot to drop it) ---
	var hb_lbl := Label.new()
	hb_lbl.text = "HOTBAR   (click = pick up / place · right-click = half / one · click outside = drop · 🗑 = delete · Q in-game drops)"
	hb_lbl.add_theme_font_size_override("font_size", 14)
	col.add_child(hb_lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	col.add_child(hb)
	for i in 5:
		var slot := _HotSlot.new()
		slot.index = i
		slot.custom_minimum_size = Vector2(120, 60)
		hb.add_child(slot)
		_slot_panels.append(slot)
		_slot_lbls.append(slot.label)
	# trash: click with a held stack to DELETE it forever
	var trash := _TrashSlot.new()
	trash.custom_minimum_size = Vector2(120, 60)
	hb.add_child(trash)

	_held_cursor = Label.new()
	_held_cursor.add_theme_font_size_override("font_size", 14)
	_held_cursor.z_index = 100
	_held_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_held_cursor)

	Inventory.changed.connect(_refresh)
	_refresh()

func _make_cell(item: Dictionary) -> Control:
	var cell := _ItemCell.new()
	cell.id = item.id
	cell.custom_minimum_size = Vector2(210, 96)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_bottom", 6)
	cell.add_child(mc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	mc.add_child(row)

	var icon := ColorRect.new()
	icon.color = _icon_color(item.id)
	icon.custom_minimum_size = Vector2(48, 48)
	# the color chip is the BACKGROUND; the item's real model spins
	# in front of it like a tiny shopping channel
	var spin := TextureRect.new()
	var itex := IconLib.tex(str(item.id), get_tree())
	if itex != null:
		spin.texture = itex
	spin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spin.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.add_child(spin)
	var iw := CenterContainer.new()
	iw.add_child(icon)
	row.add_child(iw)

	var txt := VBoxContainer.new()
	row.add_child(txt)
	var nm := Label.new()
	nm.text = item.name
	nm.add_theme_font_size_override("font_size", 16)
	nm.custom_minimum_size = Vector2(136, 0)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	txt.add_child(nm)
	if Inventory.armors.has(str(item.id)):
		var defl := Label.new()
		var alv9 := int(Inventory.enchant.get(str(item.id), 0))
		defl.text = "blocks %d%% damage" % int(
			float(Inventory.armors[str(item.id)]["def"])
			* (1.0 + 0.15 * float(alv9)))
		defl.add_theme_font_size_override("font_size", 12)
		defl.modulate = Color("#9adf9a")
		txt.add_child(defl)
	if Inventory.weapons.has(str(item.id)):
		var wd9: Dictionary = Inventory.weapons[str(item.id)]
		var wlv9 := int(Inventory.enchant.get(str(item.id), 0))
		var wdm9 := float(wd9["dmg"]) * (1.0 + 0.25 * float(wlv9))
		var dps9 := wdm9 / maxf(0.02, float(wd9["rate"]))
		var wl9 := Label.new()
		wl9.text = "%d damage · %d d/s" % [int(wdm9), int(dps9)]
		wl9.add_theme_font_size_override("font_size", 12)
		wl9.modulate = Color("#ffb347")
		txt.add_child(wl9)
	var cost := Label.new()
	cost.text = Inventory.cost_text(item.id)
	cost.add_theme_font_size_override("font_size", 12)
	cost.custom_minimum_size = Vector2(136, 0)
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.max_lines_visible = 3
	cost.modulate = Color("#ffe066")
	txt.add_child(cost)

	_cells.append({"id": item.id, "panel": cell, "cost": cost})
	_pass_through(mc)   # let clicks/drops reach the cell, not the labels
	return cell

func _pass_through(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_pass_through(c)

func _icon_color(id: String) -> Color:
	if Inventory.weapons.has(id):
		return Inventory.weapons[id]["color"]
	if Inventory.items.has(id):
		return Inventory.items[id]["color"]
	return Color("#8890a0")

## Only one card ever shows a count. Scrolling a second one clears the
## first, and buying anything at all clears the lot -- otherwise the grid
## fills up with stale multipliers nobody asked for.
func claim_mult(cell) -> void:
	for c in _cells:
		var node = c.get("panel")
		if node != null and node != cell and is_instance_valid(node) \
				and node.has_method("_set_mult"):
			node._set_mult(1)

func clear_mults() -> void:
	claim_mult(null)

func try_buy(id: String) -> void:
	if not Game.tut_can_buy(id):
		Sfx.play("denied", -14.0)   # tutorial: not this one, not yet
		return
	if Game.creative:
		# creative: EVERYTHING is free craft, wires included, any tab
		Inventory.give(id, 10 if Inventory.STACKABLE.has(id) else 1)
		Sfx.play("coin")
		return
	Inventory.buy(id)

func drop_slot(i: int) -> void:
	Inventory.drop_slot(i)

func select_slot(i: int) -> void:
	Inventory.select_slot(i)

func _refresh() -> void:
	# the Creative tab only EXISTS with the cheat on
	if _creative_btn:
		_creative_btn.visible = Game.creative
	if _creative2_btn:
		_creative2_btn.visible = Game.creative
	if _tab.begins_with("Creative") and not Game.creative:
		_tab = "Gear"
		_rebuild_grid()
	_coin_lbl.text = "COINS %d  ·  ingot %d  irid %d  ultima %d" % [
		Inventory.coins, Inventory.res_count("ingot"),
		Inventory.res_count("irid"), Inventory.res_count("ultima")]
	for c in _cells:
		var owned := Inventory.owned_unique(c["id"])
		var afford := Inventory.can_buy(c["id"])
		c["panel"].add_theme_stylebox_override("panel", _cell_style(owned, afford))
		# tutorial lockdown: everything but the current lesson's item grays out
		c["panel"].modulate = Color(1, 1, 1) if Game.tut_can_buy(c["id"]) \
			else Color(0.45, 0.45, 0.45, 0.5)
		if owned:
			c["cost"].text = "OWNED · " + Inventory.cost_text(c["id"])
			c["cost"].modulate = Color("#88ff88")
		elif Inventory.needs_recipe(c["id"]):
			c["cost"].text = "??? recipe unknown"
			c["cost"].modulate = Color("#ff5a5a")
		else:
			c["cost"].text = Inventory.cost_text(c["id"])
			# red when you can't afford it
			c["cost"].modulate = Color("#ffe066") if afford else Color("#ff5a5a")
	# tutorial lockdown: the tab holding the lesson's item glows green
	var lock := not Game.tutorial_allow.has("*")
	var hot_tabs := {}
	if lock:
		for it in Inventory.catalog:
			if Game.tut_can_buy(str(it.id)):
				hot_tabs[str(it.get("tab", "Gear"))] = true
	var tabnames: Array = Inventory.tabs + ["Creative", "Creative 2"]
	for i in mini(_tab_btns.size(), tabnames.size()):
		if not lock:
			_tab_btns[i].modulate = Color(1, 1, 1)
		elif hot_tabs.has(str(tabnames[i])):
			_tab_btns[i].modulate = Color("#7dff9a")
		else:
			_tab_btns[i].modulate = Color(0.5, 0.5, 0.5)
	for i in _slot_panels.size():
		_slot_lbls[i].text = Inventory.slot_text(Inventory.hotbar[i])
		var sid9 := str(Inventory.hotbar[i]["id"])
		var elv9 := int(Inventory.enchant.get(sid9, 0))
		if Inventory.weapons.has(sid9):
			var wd0: Dictionary = Inventory.weapons[sid9]
			var edm9 := float(wd0["dmg"]) * (1.0 + 0.25 * float(elv9))
			var tip9 := "%d damage · %d d/s" % [int(edm9),
				int(edm9 / maxf(0.02, float(wd0["rate"])))]
			if elv9 > 0:
				tip9 += "  (enchant +%d)" % elv9
			_slot_panels[i].tooltip_text = tip9
		elif Inventory.armors.has(sid9):
			var ad0 := float(Inventory.armors[sid9]["def"]) \
				* (1.0 + 0.15 * float(elv9))
			var atip9 := "blocks %d%% damage" % int(ad0)
			if elv9 > 0:
				atip9 += "  (enchant +%d)" % elv9
			_slot_panels[i].tooltip_text = atip9
		else:
			_slot_panels[i].tooltip_text = ""
		_slot_panels[i].add_theme_stylebox_override("panel", _hot_style(i == Inventory.selected))
		_slot_lbls[i].material = Inventory.ench_text_material() \
			if int(Inventory.enchant.get(str(Inventory.hotbar[i]["id"]), 0)) > 0 \
			else null
	for ep in _equip_slots:
		ep.refresh()
	if _eq_lbl:
		_eq_lbl.text = "EQUIPMENT — %d%% damage blocked (soft cap 60%%, hard 80%%)   (drag or right-click armor to wear · click a slot to take off)" \
			% roundi(Inventory.armor_reduction() * 100.0)

func _cell_style(owned: bool, afford: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	if owned:
		sb.bg_color = Color("#1a2a1a")
		sb.border_color = Color("#3a5a3a")
		sb.set_border_width_all(1)
	elif afford:
		sb.bg_color = Color("#23232e")
		sb.border_color = Color("#5a5a3a")
		sb.set_border_width_all(1)
	else:
		# can't afford -> clearly red
		sb.bg_color = Color("#2e1618")
		sb.border_color = Color("#ff5a5a")
		sb.set_border_width_all(2)
	return sb

func _hot_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#23232e")
	sb.set_corner_radius_all(6)
	sb.border_color = Color("#ffe066") if selected else Color("#3a3a48")
	sb.set_border_width_all(2 if selected else 1)
	return sb

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == Settings.key("inventory"):
		if Game.dead:
			return
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		_flush_held()
		if not Game.dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func close_ui() -> void:
	_flush_held()
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Anything still on the cursor goes back into your bags on close.
func _flush_held() -> void:
	if str(held["id"]) != "":
		Inventory.give(str(held["id"]), int(held["n"]))
		held = Inventory.empty_slot()

## Same click scheme as chests/backpacks: left = pick up / put down /
## swap a stack, right = pick up half / place exactly one.
func hot_click(i: int, btn: int) -> void:
	var slot: Dictionary = Inventory.hotbar[i]
	var sid := str(slot["id"])
	var hid := str(held["id"])
	if btn == MOUSE_BUTTON_LEFT:
		if hid == "":
			if sid == "":
				return
			held = {"id": sid, "n": int(slot["n"])}
			Inventory.hotbar[i] = Inventory.empty_slot()
		elif sid == "":
			Inventory.hotbar[i] = {"id": hid, "n": int(held["n"])}
			held = Inventory.empty_slot()
		elif sid == hid and Inventory.STACKABLE.has(hid):
			var room: int = Inventory.STACK_MAX - int(slot["n"])
			var put: int = mini(room, int(held["n"]))
			slot["n"] = int(slot["n"]) + put
			held["n"] = int(held["n"]) - put
			if int(held["n"]) <= 0:
				held = Inventory.empty_slot()
		else:
			Inventory.hotbar[i] = {"id": hid, "n": int(held["n"])}
			held = {"id": sid, "n": int(slot["n"])}
	elif btn == MOUSE_BUTTON_RIGHT:
		if hid == "":
			if sid == "":
				return
			# ARMOR: right-click wears it straight from the slot; whatever
			# you had on lands back in that slot
			if Inventory.armors.has(sid):
				var aslot := str(Inventory.armors[sid]["slot"])
				var worn := str(Inventory.equip.get(aslot, ""))
				Inventory.equip[aslot] = sid
				slot["n"] = int(slot["n"]) - 1
				if worn != "":
					Inventory.hotbar[i] = {"id": worn, "n": 1}
				elif int(slot["n"]) <= 0:
					Inventory.hotbar[i] = Inventory.empty_slot()
				Sfx.play("learn", -12.0)
				Inventory.changed.emit()
				return
			var take := ceili(int(slot["n"]) / 2.0)
			held = {"id": sid, "n": take}
			slot["n"] = int(slot["n"]) - take
			if int(slot["n"]) <= 0:
				Inventory.hotbar[i] = Inventory.empty_slot()
		else:
			if sid == "":
				Inventory.hotbar[i] = {"id": hid, "n": 1}
				held["n"] = int(held["n"]) - 1
			elif sid == hid and Inventory.STACKABLE.has(hid) and int(slot["n"]) < Inventory.STACK_MAX:
				slot["n"] = int(slot["n"]) + 1
				held["n"] = int(held["n"]) - 1
			else:
				return
			if int(held["n"]) <= 0:
				held = Inventory.empty_slot()
	Sfx.play("click", -18.0)
	Inventory.changed.emit()

func _process(_d: float) -> void:
	if not visible or _held_cursor == null:
		return
	_held_cursor.visible = str(held["id"]) != ""
	if _held_cursor.visible:
		_held_cursor.text = Inventory.slot_text(held)
		_held_cursor.position = get_viewport().get_mouse_position() + Vector2(14, -8)

# --------------------------------------------------------- inner widgets

class _CoinChip extends Panel:
	func _ready() -> void:
		custom_minimum_size = Vector2(120, 90)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#3a2f10")
		sb.border_color = Color("#ffe066")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "COINS\n⤳ drag"
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if Inventory.coins <= 0:
			return null
		var p := Label.new()
		p.text = "%d coins" % Inventory.coins
		set_drag_preview(p)
		return {"kind": "coins"}

## One worn-equipment slot. Click: unequip back into your bags.
class _EquipSlot extends Panel:
	var slot_name: String = ""
	var _lbl: Label

	func _ready() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#20202c")
		sb.border_color = Color("#4a4a5c")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		add_theme_stylebox_override("panel", sb)
		mouse_entered.connect(func() -> void: modulate = Color(1.25, 1.25, 1.25))
		mouse_exited.connect(func() -> void: modulate = Color(1, 1, 1))
		_lbl = Label.new()
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.add_theme_font_size_override("font_size", 12)
		_lbl.clip_text = true
		_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_lbl)
		refresh()

	func refresh() -> void:
		if _lbl == null:
			return
		var id := str(Inventory.equip.get(slot_name, ""))
		var nm := ""
		if id == "charm":
			nm = "Charm"
		elif Inventory.armors.has(id):
			nm = "%s  -%d%%" % [Inventory.armors[id]["name"], int(Inventory.armors[id]["def"])]
		_lbl.text = slot_name.to_upper() + "\n" + (nm if nm != "" else "—")
		if int(Inventory.enchant.get(id, 0)) > 0:
			# enchanted: orange with the moving shine, right in the slot
			_lbl.material = Inventory.ench_text_material()
			_lbl.modulate = Color(1, 1, 1)
		else:
			_lbl.material = null
			_lbl.modulate = Color("#9adf9a") if nm != "" else Color(1, 1, 1, 0.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# carrying a piece? clicking its slot WEARS it -- the drag
			# everyone kept trying finally does the thing
			var ui9: Node = self
			while ui9 != null and not (ui9 is InventoryUI):
				ui9 = ui9.get_parent()
			if ui9 != null and str((ui9 as InventoryUI).held["id"]) != "":
				var hid9 := str((ui9 as InventoryUI).held["id"])
				var fits9: bool = (slot_name == "charm" and hid9 == "charm") \
					or (Inventory.armors.has(hid9)
					and str(Inventory.armors[hid9]["slot"]) == slot_name)
				if not fits9:
					Sfx.play("denied", -20.0)
					return
				var prev9 := str(Inventory.equip.get(slot_name, ""))
				Inventory.equip[slot_name] = hid9
				(ui9 as InventoryUI).held["n"] = \
					int((ui9 as InventoryUI).held["n"]) - 1
				if int((ui9 as InventoryUI).held["n"]) <= 0:
					(ui9 as InventoryUI).held = Inventory.empty_slot()
				if prev9 != "":
					Inventory.give(prev9, 1)
				Sfx.play("click", -8.0)
				Inventory.changed.emit()
				refresh()
				return
			var id := str(Inventory.equip.get(slot_name, ""))
			if id == "":
				Sfx.play("denied", -20.0)
				return
			Inventory.equip[slot_name] = ""
			if Inventory.any_space():
				Inventory.give(id, 1)
			else:
				# bags full: the piece hits the floor at your feet
				var p = get_tree().get_first_node_in_group("player")
				if p != null and p is Node3D:
					var d := ItemDrop.new()
					d.id = id
					d.count = 1
					p.get_parent().add_child(d)
					d.global_position = p.global_position \
						+ Vector3(0, 0.5, 0) - p.global_transform.basis.z * 1.2
			Sfx.play("click", -12.0)
			Inventory.changed.emit()

	## drag a hotbar armor piece straight onto its slot to wear it
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and data.get("kind") == "hswap"):
			return false
		var id := Inventory.slot_id(int(data["i"]))
		if slot_name == "charm":
			return id == "charm"
		return Inventory.armors.has(id) and str(Inventory.armors[id]["slot"]) == slot_name

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var i: int = int(data["i"])
		var id := Inventory.slot_id(i)
		var old := str(Inventory.equip.get(slot_name, ""))
		Inventory.equip[slot_name] = id
		Inventory.hotbar[i]["n"] = int(Inventory.hotbar[i]["n"]) - 1
		if int(Inventory.hotbar[i]["n"]) <= 0:
			Inventory.hotbar[i] = Inventory.empty_slot()
		if old != "":
			Inventory.give(old, 1)   # worn piece back into your bags
		Sfx.play("click")
		Inventory.changed.emit()

class _ItemCell extends Panel:
	var id: String = ""
	var mult := 1
	var _mlbl: Label = null

	func _set_mult(v: int) -> void:
		mult = clampi(v, 1, 99)
		if _mlbl == null:
			_mlbl = Label.new()
			_mlbl.add_theme_font_size_override("font_size", 18)
			_mlbl.modulate = Color("#ffe066")
			_mlbl.position = Vector2(6, 4)
			_mlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_mlbl)
		_mlbl.text = "×%d" % mult if mult > 1 else ""

	func _ready() -> void:
		# hover glow + click flash (locked tutorial items stay gray)
		mouse_entered.connect(func() -> void:
			if Game.tut_can_buy(id):
				modulate = Color(1.25, 1.25, 1.25))
		mouse_exited.connect(func() -> void:
			if Game.tut_can_buy(id):
				modulate = Color(1, 1, 1))

	func _flash_click() -> void:
		modulate = Color(1.7, 1.7, 1.4)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color(1.25, 1.25, 1.25), 0.18)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("kind") == "coins"

	func _drop_data(_pos: Vector2, _data: Variant) -> void:
		var ui := _find_ui()
		if ui:
			_flash_click()
			ui.try_buy(id)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed):
			return
		# CTRL + scroll on a stackable picks HOW MANY to craft. Plain
		# scroll is left alone -- it belongs to the list -- and only ONE
		# card carries a count at a time.
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if not (event.ctrl_pressed and Inventory.STACKABLE.has(id)):
				return                      # not accepted: the list scrolls
			var ui2 := _find_ui()
			if ui2:
				ui2.claim_mult(self)        # any other card drops its count
			_set_mult(mult + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			accept_event()                  # ...and the list stays put
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var ui := _find_ui()
			if ui:
				_flash_click()
				var n9 := mult
				ui.clear_mults()
				for k9 in n9:
					if not Game.creative and not Inventory.can_buy(id):
						break
					ui.try_buy(id)

	func _find_ui() -> InventoryUI:
		var n: Node = self
		while n:
			if n is InventoryUI:
				return n
			n = n.get_parent()
		return null

## Click with a held stack: gone forever. Deliberate, clearly marked.
class _TrashSlot extends Panel:
	func _ready() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2e1414")
		sb.border_color = Color("#a04040")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "🗑 DELETE"
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.modulate = Color("#ff8080")
		add_child(l)
		mouse_entered.connect(func() -> void: modulate = Color(1.4, 1.1, 1.1))
		mouse_exited.connect(func() -> void: modulate = Color(1, 1, 1))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var ui: InventoryUI = null
			var n: Node = self
			while n:
				if n is InventoryUI:
					ui = n
					break
				n = n.get_parent()
			if ui and str(ui.held["id"]) != "":
				# deleting a backpack whose OWN bag still has items needs
				# a confirm -- the universe backpack is exempt, its
				# storage exists outside space and survives the pack
				var hid := str(ui.held["id"])
				var pstore: Array = []
				if hid == "backpack":
					pstore = Inventory.backpack_store
				elif hid == "backpack2":
					pstore = Inventory.prism_store
				var loaded := false
				for s9 in pstore:
					if str((s9 as Dictionary).get("id", "")) != "":
						loaded = true
						break
				if loaded:
					var dlg := ConfirmationDialog.new()
					dlg.title = "DELETE " + str(Inventory.items[hid]["name"]).to_upper() + "?"
					dlg.dialog_text = "This %s still has items in its bag.\nDelete the pack anyway?" \
						% str(Inventory.items[hid]["name"])
					dlg.ok_button_text = "DELETE"
					ui.add_child(dlg)
					dlg.confirmed.connect(func() -> void:
						ui.held = Inventory.empty_slot()
						Sfx.play("explode", -20.0)
						Inventory.changed.emit()
						dlg.queue_free())
					dlg.canceled.connect(func() -> void: dlg.queue_free())
					dlg.popup_centered()
					return
				ui.held = Inventory.empty_slot()
				Sfx.play("explode", -20.0)
				Inventory.changed.emit()

class _HotSlot extends Panel:
	var index: int = 0
	var label: Label

	func _ready() -> void:
		mouse_entered.connect(func() -> void: modulate = Color(1.25, 1.25, 1.25))
		mouse_exited.connect(func() -> void: modulate = Color(1, 1, 1))
		label = Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.clip_text = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var ui := _find_ui()
			if not ui:
				return
			modulate = Color(1.6, 1.6, 1.3)
			var tw := create_tween()
			tw.tween_property(self, "modulate", Color(1.25, 1.25, 1.25), 0.18)
			ui.hot_click(index, event.button_index)

	func _find_ui() -> InventoryUI:
		var n: Node = self
		while n:
			if n is InventoryUI:
				return n
			n = n.get_parent()
		return null
