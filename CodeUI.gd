class_name CodeUI
extends CanvasLayer
## The in-game code editor for computers. Monospace, live syntax check,
## Save & Run. Your script executes twice a second on the machine.

var _target
var _edit: TextEdit
var _status: Label
var _console: RichTextLabel
var _cin: LineEdit
var _con_len: int = -1

func _send_input(txt: String) -> void:
	if _target and is_instance_valid(_target):
		_target.console_input = txt
		_target.console.append("> " + txt)
	_cin.clear()
	Sfx.play("click", -16.0)

func _process(_delta: float) -> void:
	if not visible or _target == null or not is_instance_valid(_target):
		return
	# live console mirror (only rebuild when it changed)
	if _target.console.size() != _con_len:
		_con_len = _target.console.size()
		_console.clear()
		for line in _target.console:
			_console.append_text("[code]" + str(line) + "[/code]\n")

func _ready() -> void:
	layer = 27
	visible = false
	add_to_group("code_ui")
	add_to_group("closable_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 700)
	panel.size = Vector2(720, 700)
	panel.position = Vector2(-360, -350)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#101018")
	sb.border_color = Color("#5a3a6a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	col.position = Vector2(16, 12)
	panel.add_child(col)

	var title := Label.new()
	title.text = "CODE EDITOR   (Lua-ish · runs 2x/sec)"
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)

	_edit = TextEdit.new()
	_edit.custom_minimum_size = Vector2(688, 280)
	_edit.add_theme_font_size_override("font_size", 15)
	_edit.caret_blink = true
	col.add_child(_edit)

	# --- CONSOLE: print() output + input() feed ---
	var clab := Label.new()
	clab.text = "CONSOLE   (print / clear / input)"
	clab.add_theme_font_size_override("font_size", 13)
	clab.modulate = Color("#4dff9a")
	col.add_child(clab)
	_console = RichTextLabel.new()
	_console.custom_minimum_size = Vector2(688, 110)
	_console.add_theme_font_size_override("normal_font_size", 13)
	_console.add_theme_color_override("default_color", Color("#4dff9a"))
	_console.scroll_following = true
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#050a05")
	_console.add_theme_stylebox_override("normal", csb)
	col.add_child(_console)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 8)
	col.add_child(irow)
	_cin = LineEdit.new()
	_cin.placeholder_text = "type here -> your script reads it with input()"
	_cin.custom_minimum_size = Vector2(560, 34)
	_cin.text_submitted.connect(_send_input)
	irow.add_child(_cin)
	var send := Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(110, 34)
	send.pressed.connect(func() -> void: _send_input(_cin.text))
	irow.add_child(send)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	col.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var save := Button.new()
	save.text = "Save & Run"
	save.custom_minimum_size = Vector2(180, 44)
	save.pressed.connect(_save)
	row.add_child(save)
	var check := Button.new()
	check.text = "Check"
	check.custom_minimum_size = Vector2(120, 44)
	check.pressed.connect(_check)
	row.add_child(check)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 44)
	close.pressed.connect(close_ui)
	row.add_child(close)

func open_for(machine) -> void:
	_target = machine
	_con_len = -1
	_edit.text = machine.script_src
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "editing %s" % machine.title
	_status.modulate = Color(1, 1, 1, 0.7)
	_edit.grab_focus()
	Sfx.play("click")

func close_ui() -> void:
	visible = false
	_target = null
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _test(src: String) -> String:
	# dry-run against a dummy environment
	var env := {"funnel": "coal", "port": 0}
	for i in 8:
		env["inp%d" % (i + 1)] = 0.0
		env["out%d" % (i + 1)] = 0
	var funcs := {
		"sort": func(_a: Array): return 0,
		"print": func(_a: Array): return 0,
		"clear": func(_a: Array): return 0,
		"input": func(_a: Array): return "",
	}
	var res := MiniLua.run(src, env, funcs)
	return str(res.get("err", ""))

func _check() -> void:
	var e := _test(_edit.text)
	if e == "":
		_status.text = "✓ looks fine"
		_status.modulate = Color("#4dff9a")
	else:
		_status.text = "✗ " + e
		_status.modulate = Color("#ff5a5a")

func _save() -> void:
	var e := _test(_edit.text)
	if e != "":
		_status.text = "✗ not saved: " + e
		_status.modulate = Color("#ff5a5a")
		Sfx.play("denied")
		return
	if _target and is_instance_valid(_target):
		_target.script_src = _edit.text
	_status.text = "✓ saved. it's running."
	_status.modulate = Color("#4dff9a")
	Sfx.play("learn")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()