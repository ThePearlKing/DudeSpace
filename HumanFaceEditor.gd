class_name HumanFaceEditor
extends CanvasLayer
## DEV MENU (F9): draw the faces of humanity. Every face saved here goes
## into the pool that Earth's humans draw from at random. Browse, draw,
## save, delete. The species is what you make it.

var _pad: CharacterCreator._Pad
var _count_lbl: Label
var _sliders: Dictionary = {}   # axis -> HSlider
var _browse_idx: int = -1   # -1 = fresh canvas
var _files: Array = []

const DIR := "user://human_faces"

func _ready() -> void:
	layer = 24
	visible = false
	add_to_group("closable_ui")
	DirAccess.make_dir_recursive_absolute(DIR)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 800)
	panel.size = Vector2(460, 800)
	panel.position = Vector2(-230, -400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#141414")
	sb.border_color = Color("#e8956a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var pad_m := MarginContainer.new()
	pad_m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad_m.add_theme_constant_override(side, 18)
	panel.add_child(pad_m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad_m.add_child(col)

	var title := Label.new()
	title.text = "HUMAN FACE EDITOR  (dev · F9)"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("#e8956a")
	col.add_child(title)

	_pad = CharacterCreator._Pad.new()
	_pad.custom_minimum_size = Vector2(260, 260)
	_pad.bg_color = Color("#c8996e")   # a face-ish canvas tone
	var padrow := HBoxContainer.new()
	padrow.alignment = BoxContainer.ALIGNMENT_CENTER
	padrow.add_child(_pad)
	col.add_child(padrow)

	# ink palette + eraser + clear
	var inks := HBoxContainer.new()
	inks.add_theme_constant_override("separation", 6)
	inks.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(inks)
	for c in [Color("#1a1a1a"), Color.WHITE, Color("#d94a3a"), Color("#3a6ed9"),
			Color("#3aa04a"), Color("#e8c46a"), Color("#8a4aa0")]:
		var ib := Button.new()
		ib.custom_minimum_size = Vector2(34, 34)
		var ibs := StyleBoxFlat.new()
		ibs.bg_color = c
		ibs.set_corner_radius_all(6)
		ib.add_theme_stylebox_override("normal", ibs)
		ib.add_theme_stylebox_override("hover", ibs)
		ib.add_theme_stylebox_override("pressed", ibs)
		var cc: Color = c
		ib.pressed.connect(func() -> void: _pad.set_ink(cc))
		inks.add_child(ib)
	var er := Button.new()
	er.text = "erase"
	er.pressed.connect(func() -> void: _pad.set_erase())
	inks.add_child(er)
	var cl := Button.new()
	cl.text = "clear"
	cl.pressed.connect(func() -> void: _pad.clear())
	inks.add_child(cl)

	# the soul: personality sliders, saved with the face
	var plbl := Label.new()
	plbl.text = "PERSONALITY  (this face thinks + acts like this)"
	plbl.add_theme_font_size_override("font_size", 13)
	plbl.modulate = Color(1, 1, 1, 0.7)
	col.add_child(plbl)
	for ax in EarthHuman.AXES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var al := Label.new()
		al.text = ax
		al.custom_minimum_size = Vector2(90, 0)
		al.add_theme_font_size_override("font_size", 13)
		row.add_child(al)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.value = 25
		sl.custom_minimum_size = Vector2(280, 22)
		row.add_child(sl)
		_sliders[ax] = sl

	# save / browse / delete
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	var save := Button.new()
	save.text = "Save face"
	save.custom_minimum_size = Vector2(120, 42)
	save.pressed.connect(_save_face)
	actions.add_child(save)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 42)
	prev.pressed.connect(func() -> void: _browse(-1))
	actions.add_child(prev)
	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 42)
	next.pressed.connect(func() -> void: _browse(1))
	actions.add_child(next)
	var del := Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(90, 42)
	del.pressed.connect(_delete_face)
	actions.add_child(del)
	var upd := Button.new()
	upd.text = "Update values"
	upd.custom_minimum_size = Vector2(130, 42)
	upd.pressed.connect(_update_values)
	actions.add_child(upd)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 13)
	_count_lbl.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_count_lbl)

	var close := Button.new()
	close.text = "Close (F9)"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_ui)
	col.add_child(close)
	_refresh_files()

func _refresh_files() -> void:
	_files.clear()
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				_files.append(f)
	_files.sort()
	_count_lbl.text = "%d faces in the pool · humans pick at random" % _files.size() \
		+ ("   · viewing %d/%d" % [_browse_idx + 1, _files.size()] if _browse_idx >= 0 else "   · fresh canvas")

func _pers_from_sliders() -> Dictionary:
	var out := {}
	for ax in _sliders:
		out[ax] = float(_sliders[ax].value)
	return out

func _write_pers(png_name: String) -> void:
	var f := FileAccess.open("%s/%s.json" % [DIR, png_name.trim_suffix(".png")],
		FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_pers_from_sliders()))
		f.close()

func _save_face() -> void:
	var idx := 0
	while FileAccess.file_exists("%s/face_%03d.png" % [DIR, idx]):
		idx += 1
	var fname := "face_%03d.png" % idx
	_pad.save_png("%s/%s" % [DIR, fname])
	_write_pers(fname)
	_browse_idx = -1
	EarthHuman.reload_faces()
	Sfx.play("learn", -10.0)
	_refresh_files()

## Re-save just the personality for the face being viewed.
func _update_values() -> void:
	if _browse_idx < 0 or _browse_idx >= _files.size():
		return
	_write_pers(_files[_browse_idx])
	EarthHuman.reload_faces()
	Sfx.play("click", -10.0)

func _browse(dir: int) -> void:
	if _files.is_empty():
		return
	_browse_idx = wrapi(_browse_idx + dir, 0, _files.size())
	_pad.load_png("%s/%s" % [DIR, _files[_browse_idx]])
	# pull this face's soul into the sliders
	var jp := "%s/%s.json" % [DIR, _files[_browse_idx].trim_suffix(".png")]
	if FileAccess.file_exists(jp):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if parsed is Dictionary:
			for ax in _sliders:
				_sliders[ax].value = float(parsed.get(ax, 25.0))
	_refresh_files()

func _delete_face() -> void:
	if _browse_idx < 0 or _browse_idx >= _files.size():
		return
	DirAccess.remove_absolute("%s/%s" % [DIR, _files[_browse_idx]])
	var jp2 := "%s/%s.json" % [DIR, _files[_browse_idx].trim_suffix(".png")]
	if FileAccess.file_exists(jp2):
		DirAccess.remove_absolute(jp2)
	_browse_idx = -1
	_pad.clear()
	EarthHuman.reload_faces()
	Sfx.play("explode", -20.0)
	_refresh_files()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_refresh_files()

func close_ui() -> void:
	visible = false
	# only recapture the mouse in-world -- on the title screen it stays free
	if not Game.dead and get_tree().get_first_node_in_group("player"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F9:
		if visible:
			close_ui()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()
