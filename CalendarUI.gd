class_name CalendarUI
extends CanvasLayer
## Toggle with K. Month calendar: weeks run Mon-Sun, today highlighted,
## UFO days marked (Tuesdays always, some Saturdays -- seeded, so future
## pages are accurate). Header shows the full date and the 24h clock.

var _month: int = 0
var _year: int = 1
var _title: Label
var _clock: Label
var _grid: GridContainer
var _cells: Array = []

func _ready() -> void:
	layer = 21
	visible = false
	add_to_group("closable_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 560)
	panel.size = Vector2(640, 560)
	panel.position = Vector2(-320, -280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0c1018")
	sb.border_color = Color("#ffd166")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", 15)
	_clock.modulate = Color("#aaddff")
	col.add_child(_clock)

	# month header with page buttons
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	col.add_child(nav)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(46, 40)
	prev.pressed.connect(_page.bind(-1))
	nav.add_child(prev)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.modulate = Color("#ffd166")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(_title)
	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(46, 40)
	next.pressed.connect(_page.bind(1))
	nav.add_child(next)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(_grid)
	for wd in ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]:
		var h := Label.new()
		h.text = wd
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size = Vector2(82, 24)
		h.add_theme_font_size_override("font_size", 13)
		h.modulate = Color(1, 1, 1, 0.6)
		_grid.add_child(h)
	for i in 42:   # 6 weeks covers any month
		var c := Panel.new()
		c.custom_minimum_size = Vector2(82, 58)
		var l := Label.new()
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		c.add_child(l)
		_grid.add_child(c)
		_cells.append({"panel": c, "lbl": l})

	var legend := Label.new()
	legend.text = "UFO = trader saucer in system that day (Tuesdays + some Saturdays)"
	legend.add_theme_font_size_override("font_size", 12)
	legend.modulate = Color(1, 1, 1, 0.55)
	col.add_child(legend)

	var close := Button.new()
	close.text = "Close (K)"
	close.custom_minimum_size = Vector2(0, 38)
	close.pressed.connect(close_ui)
	col.add_child(close)

func open() -> void:
	var d := Game.date_of(Game.day_index())
	_month = int(d.month)
	_year = int(d.year)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_rebuild()
	Sfx.play("click", -14.0)

func close_ui() -> void:
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _page(dir: int) -> void:
	_month += dir
	if _month < 0:
		if _year <= 1:
			_month = 0   # time starts at January, Year 1. nothing before.
			return
		_month = 11
		_year -= 1
	elif _month > 11:
		_month = 0
		_year += 1
	_rebuild()
	Sfx.play("click", -18.0)

func _rebuild() -> void:
	_title.text = "%s · Year %d" % [Game.MONTHS[_month], _year]
	var start := Game.month_start_day(_month, _year)
	var ndays := Game.days_in_month(_month, _year)
	var lead := start % 7   # weekday of the 1st (0 = Monday)
	var today := Game.day_index()
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		var day := i - lead
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		if day < 0 or day >= ndays:
			cell["lbl"].text = ""
			sb.bg_color = Color(1, 1, 1, 0.03)
			cell["panel"].add_theme_stylebox_override("panel", sb)
			continue
		var di := start + day
		var txt := str(day + 1)
		if Game.ufo_on_day(di):
			txt += "\nUFO"
		cell["lbl"].text = txt
		cell["lbl"].modulate = Color("#9adf9a") if Game.ufo_on_day(di) else Color(1, 1, 1, 0.9)
		sb.bg_color = Color(1, 1, 1, 0.07)
		if di == today:
			sb.bg_color = Color(1.0, 0.82, 0.4, 0.25)
			sb.border_color = Color("#ffd166")
			sb.set_border_width_all(2)
		elif di < today:
			sb.bg_color = Color(1, 1, 1, 0.04)
			cell["lbl"].modulate.a = 0.45
		cell["panel"].add_theme_stylebox_override("panel", sb)

func _process(_d: float) -> void:
	if visible:
		_clock.text = "%s   ·   %s" % [Game.date_text(), Game.clock_text()]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == Settings.key("calendar"):
		if Game.dead:
			return
		if visible:
			close_ui()
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()
