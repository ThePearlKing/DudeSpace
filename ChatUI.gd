class_name ChatUI
extends CanvasLayer
## Minecraft-style chat. T opens the input line, Enter sends, Esc closes.
## Messages stack bottom-left and fade out. Works in singleplayer too --
## in a LAN session everyone connected sees them.

const MAX_LINES := 8
const LINE_LIFE := 12.0

var _log: VBoxContainer
var _input: LineEdit
var _lines: Array = []   # [{label, t}]

func _ready() -> void:
	layer = 18
	add_to_group("chat_ui")
	Net.chat_received.connect(_on_chat)

	_log = VBoxContainer.new()
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.position = Vector2(24, -260)
	_log.custom_minimum_size = Vector2(620, 0)
	_log.add_theme_constant_override("separation", 2)
	_log.alignment = BoxContainer.ALIGNMENT_END
	add_child(_log)

	_input = LineEdit.new()
	_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_input.position = Vector2(24, -46)
	_input.custom_minimum_size = Vector2(620, 34)
	_input.placeholder_text = "chat…"
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	ist.border_color = Color(0.4, 0.45, 0.5)
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(4)
	ist.set_content_margin_all(8)
	_input.add_theme_stylebox_override("normal", ist)
	_input.add_theme_stylebox_override("focus", ist)
	_input.visible = false
	_input.text_submitted.connect(_send)
	_input.gui_input.connect(_line_key)
	add_child(_input)

func _on_chat(from_name: String, text: String) -> void:
	var m = get_tree().current_scene
	if m and m.has_method("show_chat_bubble"):
		m.show_chat_bubble(from_name, text)
	var l := Label.new()
	l.text = "<%s> %s" % [from_name, text] if from_name != "SERVER" else "· %s" % text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.modulate = Color(1, 1, 1, 0.95) if from_name != "SERVER" else Color("#ffd166")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(l)
	_lines.append({"label": l, "t": LINE_LIFE})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		if is_instance_valid(old["label"]):
			old["label"].queue_free()

var _tab: PanelContainer
var _tabrows: VBoxContainer
var _face_cache: Dictionary = {}   # peer id (0 = me) -> ImageTexture

func _face_tex(id: int) -> Texture2D:
	if _face_cache.has(id):
		return _face_cache[id]
	var bytes := PackedByteArray()
	if id == 0:
		bytes = Net.my_identity().get("paint", PackedByteArray())
	elif Net.player_infos.has(id):
		bytes = Net.player_infos[id].get("paint", PackedByteArray())
	var tex: Texture2D = null
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			tex = ImageTexture.create_from_image(img)
	_face_cache[id] = tex
	return tex

func _tab_row(tex: Texture2D, txt: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if tex != null:
		var tr9 := TextureRect.new()
		tr9.texture = tex
		tr9.custom_minimum_size = Vector2(34, 34)
		tr9.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr9.stretch_mode = TextureRect.STRETCH_SCALE
		row.add_child(tr9)
	else:
		var ph := ColorRect.new()
		ph.color = Color(1, 1, 1, 0.12)
		ph.custom_minimum_size = Vector2(34, 34)
		row.add_child(ph)
	var lb := Label.new()
	lb.text = txt
	lb.add_theme_font_size_override("font_size", 19)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("outline_size", 7)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lb)
	_tabrows.add_child(row)

func _process(delta: float) -> void:
	# hold TAB: the player roster -- face, username, distance
	if _tab == null:
		_tab = PanelContainer.new()
		_tab.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_tab.position = Vector2(-190, 150)
		_tab.custom_minimum_size = Vector2(380, 0)
		var sb9 := StyleBoxFlat.new()
		sb9.bg_color = Color(0.04, 0.05, 0.09, 0.82)
		sb9.set_corner_radius_all(10)
		sb9.set_content_margin_all(12)
		_tab.add_theme_stylebox_override("panel", sb9)
		add_child(_tab)
		_tabrows = VBoxContainer.new()
		_tabrows.add_theme_constant_override("separation", 6)
		_tab.add_child(_tabrows)
	var want_tab := Input.is_key_pressed(KEY_TAB) and not _input.visible \
		and not Game.dead
	if want_tab and not _tab.visible:
		_face_cache.erase(0)   # repaint between holds is possible
	_tab.visible = want_tab
	if _tab.visible:
		for c in _tabrows.get_children():
			c.queue_free()
		var me = get_tree().get_first_node_in_group("player")
		var hd := Label.new()
		hd.text = "— PLAYERS (%d) —" % maxi(Net.player_names.size(), 1)
		hd.add_theme_font_size_override("font_size", 17)
		hd.modulate = Color(1, 1, 1, 0.7)
		_tabrows.add_child(hd)
		_tab_row(_face_tex(0), "%s (you)" % Net.my_name())
		for id in Net.player_names:
			if id == multiplayer.get_unique_id():
				continue
			var line := str(Net.player_names[id])
			if me and Net.player_pos.has(id):
				var d: float = me.global_position.distance_to(Net.player_pos[id])
				line += "   ·   %s" % ("%.0f m" % d if d < 1000.0 else "%.1f km" % (d / 1000.0))
			_tab_row(_face_tex(id), line)
	# chat open: the input owns the keyboard, no matter what got clicked
	if _input.visible and not _input.has_focus():
		_input.grab_focus()
	for e in _lines:
		if _input.visible:
			e["label"].modulate.a = 1.0   # chat open: full log visible
			continue
		e["t"] -= delta
		e["label"].modulate.a = clampf(e["t"] / 3.0, 0.0, 1.0)

func open() -> void:
	_input.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input.grab_focus()

func close_chat() -> void:
	_input.visible = false
	_input.text = ""
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _send(text: String) -> void:
	close_chat()
	if text.strip_edges() != "":
		Net.send_chat(text)

## The focused LineEdit sees keys FIRST -- catch Escape right there,
## before the pause menu or anything else can react to it.
func _line_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close_chat()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _input.visible:
		if event.keycode == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	# T opens chat only while actually playing (mouse captured = no UI open)
	if event.keycode == Settings.key("chat") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not Game.dead:
		open()
		get_viewport().set_input_as_handled()
