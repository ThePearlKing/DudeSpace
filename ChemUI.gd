class_name ChemUI
extends CanvasLayer
## THE GLASSWARE BENCH, up close. Drag a material out of your bags and
## drop it into a bottle, then work the sequence: heat it, stir it, cool
## it, whatever this particular compound wants. The bench tells you when
## a step lands and when it doesn't, and nothing else.
##
## Every chemical has its own sequence. The manual, if you bought one,
## lists them all.

var bench = null

var _root: Control
var _note: Label
var _hint: Label
var _title: Label
var _bagbox: VBoxContainer
var _stepbox: HBoxContainer
var _bottles: Control
var _drag_id: String = ""
var _drag_pos := Vector2.ZERO

const BG := Color("#0d1310")
const GLASS := Color("#9fd8e8")

func _ready() -> void:
	layer = 20
	add_to_group("chem_ui")
	add_to_group("closable_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = BG
	st.border_color = GLASS.darkened(0.5)
	st.set_border_width_all(2)
	_root.add_theme_stylebox_override("panel", st)
	_root.gui_input.connect(_root_input)
	add_child(_root)

	_title = Label.new()
	_title.text = "GLASSWARE BENCH"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", GLASS)
	_title.position = Vector2(20, 12)
	_root.add_child(_title)
	var x := Button.new()
	x.text = "✕"
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-56, 12)
	x.custom_minimum_size = Vector2(44, 40)
	x.pressed.connect(close)
	_root.add_child(x)

	# ---- the bag, on the left: everything you could pour
	var bagpanel := Panel.new()
	bagpanel.position = Vector2(20, 58)
	bagpanel.custom_minimum_size = Vector2(300, 620)
	bagpanel.size = Vector2(300, 620)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#121a16")
	bagpanel.add_theme_stylebox_override("panel", bs)
	_root.add_child(bagpanel)
	var bl := Label.new()
	bl.text = "  YOUR BAGS — drag into a bottle"
	bl.add_theme_font_size_override("font_size", 13)
	bl.add_theme_color_override("font_color", Color("#8fa8b8"))
	bagpanel.add_child(bl)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 24)
	scroll.custom_minimum_size = Vector2(292, 590)
	scroll.size = Vector2(292, 590)
	bagpanel.add_child(scroll)
	_bagbox = VBoxContainer.new()
	_bagbox.custom_minimum_size = Vector2(286, 0)
	scroll.add_child(_bagbox)

	# ---- the bottles
	_bottles = Control.new()
	_bottles.position = Vector2(350, 70)
	_bottles.custom_minimum_size = Vector2(560, 300)
	_bottles.size = Vector2(560, 300)
	_bottles.draw.connect(_draw_bottles)
	_bottles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bottles)

	# ---- the operations
	var oplbl := Label.new()
	oplbl.text = "OPERATIONS"
	oplbl.add_theme_font_size_override("font_size", 15)
	oplbl.add_theme_color_override("font_color", GLASS)
	oplbl.position = Vector2(350, 392)
	_root.add_child(oplbl)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(350, 416)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_root.add_child(grid)
	for op in Mats.HAND_OPS:
		var b := Button.new()
		b.text = str(op)
		b.custom_minimum_size = Vector2(180, 46)
		b.pressed.connect(func() -> void:
			bench.do_op(str(op))
			_refresh())
		grid.add_child(b)

	# ---- the sequence so far
	var sl := Label.new()
	sl.text = "SEQUENCE SO FAR"
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", Color("#8fa8b8"))
	sl.position = Vector2(960, 392)
	_root.add_child(sl)
	_stepbox = HBoxContainer.new()
	_stepbox.position = Vector2(960, 416)
	_stepbox.add_theme_constant_override("separation", 6)
	_root.add_child(_stepbox)

	_note = Label.new()
	_note.position = Vector2(350, 336)
	_note.custom_minimum_size = Vector2(900, 40)
	_note.add_theme_font_size_override("font_size", 17)
	_note.add_theme_color_override("font_color", Color("#ffd166"))
	_root.add_child(_note)

	var take := Button.new()
	take.text = "TAKE PRODUCT"
	take.position = Vector2(960, 470)
	take.custom_minimum_size = Vector2(200, 46)
	take.pressed.connect(func() -> void:
		bench.take_output()
		_refresh())
	_root.add_child(take)
	var emptyb := Button.new()
	emptyb.text = "RINSE GLASSWARE"
	emptyb.position = Vector2(960, 524)
	emptyb.custom_minimum_size = Vector2(200, 46)
	emptyb.pressed.connect(func() -> void:
		bench.empty_glass()
		_refresh())
	_root.add_child(emptyb)

	_hint = Label.new()
	_hint.position = Vector2(350, 600)
	_hint.custom_minimum_size = Vector2(900, 90)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("#8fa8b8"))
	_root.add_child(_hint)
	_refresh()

func close_ui() -> void:
	close()

func close() -> void:
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

## Everything in your bags that chemistry has any use for.
func _pourable() -> Array:
	var out: Array = []
	var seen := {}
	for id in Mats.hand_makeable():
		for k in (Mats.def(id)["inputs"] as Dictionary).keys():
			if not seen.has(k):
				seen[k] = true
				out.append(str(k))
	for extra in ["raw_ice", "raw_sand", "coal", "sulfur", "plantfiber", "water"]:
		if not seen.has(extra):
			seen[extra] = true
			out.append(extra)
	return out

func _refresh() -> void:
	for c in _bagbox.get_children():
		c.queue_free()
	for id in _pourable():
		var n := Inventory.res_count(id)
		var row := Panel.new()
		row.custom_minimum_size = Vector2(280, 34)
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color("#1b2620") if n > 0 else Color("#141a17")
		row.add_theme_stylebox_override("panel", rs)
		row.set_meta("mat", id)
		var lab := Label.new()
		lab.text = "  %s   x%d" % [Inventory.hotbar_name(id), n]
		lab.add_theme_font_size_override("font_size", 14)
		lab.add_theme_color_override("font_color",
			Color(Mats.def(id).get("color", Color("#c8ccd4"))) if Mats.has(id)
			else Color("#c8ccd4"))
		lab.position = Vector2(4, 6)
		row.add_child(lab)
		_bagbox.add_child(row)
	for c in _stepbox.get_children():
		c.queue_free()
	for stp in bench.steps:
		var chip := Label.new()
		chip.text = "  %s  " % str(stp)
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color", Color("#3aff6a"))
		_stepbox.add_child(chip)
	_note.text = str(bench.last_note)
	var t: String = bench.target()
	var hint := "Pour materials into the bottles, then work out the sequence. "
	if t != "":
		var d := Mats.def(t)
		hint += "The glass is holding enough for %s (%d steps). " % [
			str(d.get("name", t)), Mats.hand_sequence(t).size()]
		if Game.chem_manual:
			hint += "MANUAL: " + " -> ".join(Mats.hand_sequence(t)) + ". "
	hint += "A wrong operation just settles the mixture -- nothing is lost, "
	hint += "start the sequence again. The Chemistry Handbook lists every recipe."
	_hint.text = hint
	_bottles.queue_redraw()

func _bottle_rects() -> Array:
	var out: Array = []
	for i in 3:
		out.append(Rect2(Vector2(24 + float(i) * 180.0, 40), Vector2(150, 210)))
	return out

func _draw_bottles() -> void:
	var f := ThemeDB.fallback_font
	var ids: Array = bench.bottles.keys()
	var rects := _bottle_rects()
	for i in 3:
		var r: Rect2 = rects[i]
		# the flask: a neck, a bulb, and whatever is sloshing in it
		_bottles.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.4, 0),
			Vector2(r.size.x * 0.2, r.size.y * 0.28)), Color(0.6, 0.85, 0.95, 0.18))
		_bottles.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.28),
			Vector2(r.size.x, r.size.y * 0.72)), Color(0.6, 0.85, 0.95, 0.14))
		_bottles.draw_rect(r, GLASS * Color(1, 1, 1, 0.35), false, 2.0)
		if i < ids.size():
			var id := str(ids[i])
			var n := int(bench.bottles[id])
			var col: Color = Color(Mats.def(id).get("color", Color("#7be8ff")))
			var fill := clampf(float(n) / 8.0, 0.15, 1.0)
			var fh := r.size.y * 0.68 * fill
			_bottles.draw_rect(Rect2(r.position + Vector2(4, r.size.y - fh - 4),
				Vector2(r.size.x - 8, fh)), col * Color(1, 1, 1, 0.75))
			_bottles.draw_string(f, r.position + Vector2(6, r.size.y + 18),
				"%s x%d" % [Inventory.hotbar_name(id), n],
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x + 30, 14, Color("#d8e8e0"))
		else:
			_bottles.draw_string(f, r.position + Vector2(r.size.x * 0.5 - 22,
				r.size.y * 0.55), "empty", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1, 0.3))
	if _drag_id != "":
		var lp := _bottles.get_local_mouse_position()
		_bottles.draw_circle(lp, 12.0,
			Color(Mats.def(_drag_id).get("color", Color("#7be8ff"))))
		_bottles.draw_string(f, lp + Vector2(16, 5),
			Inventory.hotbar_name(_drag_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color("#ffffff"))

## Drag a row out of the bag and let go over the glassware.
func _root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for row in _bagbox.get_children():
				if row is Panel and row.get_global_rect().has_point(event.global_position):
					var id := str(row.get_meta("mat"))
					if Inventory.res_count(id) > 0:
						_drag_id = id
						Sfx.play("click", -20.0)
					return
		else:
			if _drag_id != "":
				var local: Vector2 = event.global_position - _bottles.global_position
				var hit := false
				for r in _bottle_rects():
					if (r as Rect2).has_point(local):
						hit = true
						break
				if hit:
					bench.pour(_drag_id, 5 if Input.is_key_pressed(KEY_SHIFT) else 1)
				_drag_id = ""
				_refresh()
	elif event is InputEventMouseMotion and _drag_id != "":
		_bottles.queue_redraw()

func _process(_d: float) -> void:
	if bench == null or not is_instance_valid(bench):
		close()
		return
	if _note.text != str(bench.last_note):
		_refresh()
