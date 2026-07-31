class_name TerminalUI
extends CanvasLayer
## The Euclid Temple door terminal. A tiny unix-ish shell; ./run.sh runs a
## BLIND ascii maze (you only see next to you). Beat it -> the button
## crumbles and the temple door opens forever (Game.door_open).

var _panel: Panel
var _out: RichTextLabel
var _input: LineEdit
var _mode: String = "shell"    # shell | maze

# maze state
var _maze: Array = []
var _mw: int = 0
var _mh: int = 0
var _px: int = 1
var _py: int = 1
var _moves: int = 0

func _ready() -> void:
	layer = 26
	visible = false
	add_to_group("terminal_ui")
	add_to_group("closable_ui")

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(700, 520)
	_panel.size = Vector2(700, 520)
	_panel.position = Vector2(-350, -260)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#050a05")
	sb.border_color = Color("#2bff6a")
	sb.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	_out = RichTextLabel.new()
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.add_theme_font_size_override("normal_font_size", 15)
	_out.add_theme_font_size_override("mono_font_size", 15)
	_out.add_theme_color_override("default_color", Color("#2bff6a"))
	# REAL monospace, so the maze grid lines up
	var mono := SystemFont.new()
	mono.font_names = ["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"]
	_out.add_theme_font_override("mono_font", mono)
	_out.scroll_following = true
	col.add_child(_out)

	_input = LineEdit.new()
	_input.custom_minimum_size = Vector2(0, 40)
	_input.placeholder_text = "type a command..."
	_input.text_submitted.connect(_on_submit)
	col.add_child(_input)

func open() -> void:
	visible = true
	_mode = "shell"
	_out.scroll_following = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_out.clear()
	_print("EUCLID TEMPLE OS v3.14")
	if Game.door_open:
		_print("door status: OPEN (forever)")
	_print("type 'help' for commands")
	_print("hint: list files with 'ls'... executables run with ./")
	_input.editable = true
	_input.grab_focus()
	Sfx.play("click")

func close_ui() -> void:
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _print(s: String) -> void:
	_out.append_text("[code]" + s + "[/code]\n")

func _on_submit(cmd: String) -> void:
	_input.clear()
	cmd = cmd.strip_edges()
	_print("$ " + cmd)
	match cmd:
		"help":
			_print("ls · cat readme.txt · ./run.sh · exit")
		"ls":
			_print("run.sh   readme.txt")
		"cat readme.txt":
			_print("the door yields to those who walk blind\nand think in truth tables. ./run.sh")
		"./run.sh", "sh run.sh", "bash run.sh":
			if Game.door_open:
				_print("door already open forever.")
			else:
				_start_maze()
		"exit":
			close_ui()
		_:
			if cmd != "":
				_print("sh: %s: command not found" % cmd)

# ------------------------------------------------------------------ maze

func _start_maze() -> void:
	_mode = "maze"
	_input.editable = false
	_mw = 15
	_mh = 15
	# fresh maze EVERY run, and provably solvable before it's shown
	for attempt in 20:
		_generate_maze()
		if _solvable():
			break
	_px = 1
	_py = 1
	_moves = 0
	_render_maze()

func _generate_maze() -> void:
	_maze = []
	for y in _mh:
		var row: Array = []
		for x in _mw:
			row.append(true)   # wall
		_maze.append(row)
	# recursive backtracker
	var stack: Array = [Vector2i(1, 1)]
	_maze[1][1] = false
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var dirs: Array = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
		dirs.shuffle()
		var moved := false
		for d in dirs:
			var n: Vector2i = c + d
			if n.x > 0 and n.x < _mw - 1 and n.y > 0 and n.y < _mh - 1 and _maze[n.y][n.x]:
				_maze[n.y][n.x] = false
				_maze[c.y + d.y / 2][c.x + d.x / 2] = false
				stack.append(n)
				moved = true
				break
		if not moved:
			stack.pop_back()

## BFS from start to the X: never hand the player a broken maze.
func _solvable() -> bool:
	var seen := {}
	var q: Array = [Vector2i(1, 1)]
	seen[Vector2i(1, 1)] = true
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == Vector2i(_mw - 2, _mh - 2):
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x > 0 and n.y > 0 and n.x < _mw - 1 and n.y < _mh - 1 \
					and not _maze[n.y][n.x] and not seen.has(n):
				seen[n] = true
				q.append(n)
	return false

## The WHOLE maze fills the window and stays put -- you move through it.
## Everything is dark except a small lit pool around you.
func _render_maze() -> void:
	_out.clear()
	_out.scroll_following = false
	var s := ""
	for y in _mh:
		var line := ""
		for x in _mw:
			var lit: bool = maxi(absi(x - _px), absi(y - _py)) <= 2
			if x == _px and y == _py:
				line += "@ "
			elif not lit:
				line += "  "   # darkness. borders included. good luck.
			elif x == _mw - 2 and y == _mh - 2:
				line += "X "
			else:
				line += "# " if _maze[y][x] else ". "
		s += line + "\n"
	_out.append_text("[font_size=22][code]" + s + "[/code][/font_size]")
	_out.scroll_to_line(0)

func _render_victory() -> void:
	_out.scroll_following = true
	_out.clear()
	_print("DOOR OPENED")

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _mode != "maze":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var d := Vector2i.ZERO
		match event.keycode:
			KEY_W, KEY_UP: d = Vector2i(0, -1)
			KEY_S, KEY_DOWN: d = Vector2i(0, 1)
			KEY_A, KEY_LEFT: d = Vector2i(-1, 0)
			KEY_D, KEY_RIGHT: d = Vector2i(1, 0)
			KEY_ESCAPE:
				close_ui()
				return
		if d == Vector2i.ZERO:
			return
		get_viewport().set_input_as_handled()
		var nx := _px + d.x
		var ny := _py + d.y
		if nx > 0 and ny > 0 and nx < _mw and ny < _mh and not _maze[ny][nx]:
			_px = nx
			_py = ny
			Sfx.play("click", -18.0)
		if _px == _mw - 2 and _py == _mh - 2:
			_render_victory()
			Sfx.play("learn")
			Game.door_open = true
			var main := get_tree().current_scene
			if main and main.has_method("open_temple_door"):
				main.open_temple_door()
			_mode = "shell"
			_input.editable = true
			_input.grab_focus()
		else:
			_render_maze()
