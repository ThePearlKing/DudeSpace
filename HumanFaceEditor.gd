class_name HumanFaceEditor
extends CanvasLayer
## DEV MENU (F9): draw the faces of humanity. Every face saved here goes
## into the pool that Earth's humans draw from at random. Browse, draw,
## save, delete. The species is what you make it.

var _pad: CharacterCreator._Pad
var _count_lbl: Label
var _sliders: Dictionary = {}   # axis -> HSlider
var _gallery: HBoxContainer
var _save_btn: Button
var _reset_btn: Button
var _reset_armed := false
var _browse_idx: int = -1   # -1 = fresh canvas
var _files: Array = []
var _skin_imp: OptionButton

const CURRENT_SKIN := "(current character)"

const DIR := "user://human_faces"

func _ready() -> void:
	layer = 24
	visible = false
	add_to_group("closable_ui")
	DirAccess.make_dir_recursive_absolute(DIR)
	_seed_defaults(false)   # empty pool? humanity ships with faces

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# fit the screen: everything past the edge scrolls instead of hanging off
	var vps := get_viewport().get_visible_rect().size
	var ph := minf(870.0, vps.y - 24.0)
	panel.custom_minimum_size = Vector2(470, ph)
	panel.size = Vector2(470, ph)
	panel.position = Vector2(-235, -ph * 0.5)
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
	var body_sc := ScrollContainer.new()
	body_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pad_m.add_child(body_sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_sc.add_child(col)

	var title := Label.new()
	title.text = "HUMAN FACE EDITOR  (dev · F9)"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("#e8956a")
	col.add_child(title)

	# the gallery: every existing face, click to edit
	var gscroll := ScrollContainer.new()
	gscroll.custom_minimum_size = Vector2(0, 76)
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	gscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(gscroll)
	_gallery = HBoxContainer.new()
	_gallery.add_theme_constant_override("separation", 6)
	gscroll.add_child(_gallery)

	_pad = CharacterCreator._Pad.new()
	_pad.custom_minimum_size = Vector2(230, 230)
	_pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	# any colour humanity deserves
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(52, 34)
	pick.color = Color("#1a1a1a")
	pick.color_changed.connect(func(c2: Color) -> void: _pad.set_ink(c2))
	pick.pressed.connect(func() -> void: _pad.set_ink(pick.color))
	inks.add_child(pick)
	var er := Button.new()
	er.text = "erase"
	er.pressed.connect(func() -> void: _pad.set_erase())
	inks.add_child(er)
	var cl := Button.new()
	cl.text = "clear"
	cl.pressed.connect(func() -> void: _pad.clear())
	inks.add_child(cl)

	# brush size: 1px liner to 128px roller
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	col.add_child(brow)
	var blbl := Label.new()
	blbl.text = "brush 7"
	blbl.custom_minimum_size = Vector2(76, 0)
	blbl.add_theme_font_size_override("font_size", 13)
	brow.add_child(blbl)
	var bsl := HSlider.new()
	bsl.min_value = 1
	bsl.max_value = 128
	bsl.value = 7
	bsl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bsl.value_changed.connect(func(v: float) -> void:
		_pad.set_brush(int(v))
		blbl.text = "brush %d" % int(v))
	# cyan dot marks the default (7) -- placed with the same inset math
	# the grabber uses, so dot and grabber line up exactly at 7
	bsl.draw.connect(func() -> void:
		var gw := 16.0
		var gicon := bsl.get_theme_icon("grabber", "HSlider")
		if gicon != null:
			gw = float(gicon.get_width())
		var ratio := 6.0 / 127.0
		bsl.draw_circle(Vector2(gw * 0.5 + ratio * (bsl.size.x - gw),
			bsl.size.y * 0.5), 3.0, Color("#35e0e0")))
	brow.add_child(bsl)

	# import a face straight off one of your saved skins (or the dude
	# you're wearing) -- edit it, Save new, and it joins the pool
	# humanity draws from
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 8)
	col.add_child(irow)
	_skin_imp = OptionButton.new()
	_skin_imp.custom_minimum_size = Vector2(200, 36)
	irow.add_child(_skin_imp)
	var ibtn := Button.new()
	ibtn.text = "Import skin face"
	ibtn.custom_minimum_size = Vector2(140, 36)
	ibtn.pressed.connect(_import_skin)
	irow.add_child(ibtn)
	_refresh_skin_imports()

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
	_save_btn = Button.new()
	_save_btn.text = "Save new"
	_save_btn.custom_minimum_size = Vector2(110, 42)
	_save_btn.pressed.connect(_save_face)
	actions.add_child(_save_btn)
	var newb := Button.new()
	newb.text = "New"
	newb.custom_minimum_size = Vector2(64, 42)
	newb.pressed.connect(func() -> void:
		_browse_idx = -1
		_pad.clear()
		for ax in _sliders:
			_sliders[ax].value = 25
		_refresh_files())
	actions.add_child(newb)
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
	var actions2 := HBoxContainer.new()
	actions2.add_theme_constant_override("separation", 8)
	col.add_child(actions2)
	var del := Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(90, 42)
	del.pressed.connect(_delete_face)
	actions2.add_child(del)
	var upd := Button.new()
	upd.text = "Update values"
	upd.custom_minimum_size = Vector2(130, 42)
	upd.pressed.connect(_update_values)
	actions2.add_child(upd)
	_reset_btn = Button.new()
	_reset_btn.text = "Reset to defaults"
	_reset_btn.custom_minimum_size = Vector2(150, 42)
	_reset_btn.pressed.connect(_reset_defaults)
	actions2.add_child(_reset_btn)

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

## Copy the shipped default faces (res://human_faces) into the pool.
## force=true wipes the pool first.
func _seed_defaults(force: bool) -> void:
	var user_d := DirAccess.open(DIR)
	if user_d == null:
		return
	if force:
		for f in user_d.get_files():
			if f.ends_with(".png") or f.ends_with(".json"):
				DirAccess.remove_absolute("%s/%s" % [DIR, f])
	else:
		for f in user_d.get_files():
			if f.ends_with(".png"):
				return   # pool already has faces: leave it alone
	var src := DirAccess.open("res://human_faces")
	if src == null:
		return
	for f in src.get_files():
		if f.ends_with(".png") or f.ends_with(".json"):
			var bytes := FileAccess.get_file_as_bytes("res://human_faces/" + f)
			var out := FileAccess.open("%s/%s" % [DIR, f], FileAccess.WRITE)
			if out:
				out.store_buffer(bytes)
				out.close()
	EarthHuman.reload_faces()

## Two presses: the first only asks. The second erases your pool and
## restores the shipped faces.
func _reset_defaults() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "Really reset? (wipes pool)"
		_reset_btn.modulate = Color("#ff8080")
		Sfx.play("denied", -14.0)
		return
	_reset_armed = false
	_reset_btn.text = "Reset to defaults"
	_reset_btn.modulate = Color(1, 1, 1)
	_seed_defaults(true)
	_browse_idx = -1
	_pad.clear()
	Sfx.play("explode", -16.0)
	_refresh_files()

func _refresh_files() -> void:
	_files.clear()
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				_files.append(f)
	_files.sort()
	if _save_btn:
		_save_btn.text = "Save changes" if _browse_idx >= 0 else "Save new"
	if _gallery:
		for c in _gallery.get_children():
			c.queue_free()
		for i in _files.size():
			var img := Image.new()
			if img.load("%s/%s" % [DIR, _files[i]]) != OK:
				continue
			var tb := TextureButton.new()
			tb.texture_normal = ImageTexture.create_from_image(img)
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_SCALE
			tb.custom_minimum_size = Vector2(64, 64)
			tb.modulate = Color(1.3, 1.3, 1.0) if i == _browse_idx else Color(1, 1, 1)
			var idx2 := i
			tb.pressed.connect(func() -> void: _select_face(idx2))
			_gallery.add_child(tb)
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
	var fname: String
	if _browse_idx >= 0 and _browse_idx < _files.size():
		fname = _files[_browse_idx]   # editing: overwrite in place
	else:
		var idx := 0
		while FileAccess.file_exists("%s/face_%03d.png" % [DIR, idx]):
			idx += 1
		fname = "face_%03d.png" % idx
	_pad.save_png("%s/%s" % [DIR, fname])
	_write_pers(fname)
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

func _select_face(i: int) -> void:
	if i < 0 or i >= _files.size():
		return
	_browse_idx = i
	_pad.load_png("%s/%s" % [DIR, _files[i]])
	var jp := "%s/%s.json" % [DIR, _files[i].trim_suffix(".png")]
	if FileAccess.file_exists(jp):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if parsed is Dictionary:
			for ax in _sliders:
				_sliders[ax].value = float(parsed.get(ax, 25.0))
	Sfx.play("click", -16.0)
	_refresh_files()

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

func _refresh_skin_imports() -> void:
	if _skin_imp == null:
		return
	_skin_imp.clear()
	_skin_imp.add_item(CURRENT_SKIN)
	var d := DirAccess.open(CharacterCreator.SKINS_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				_skin_imp.add_item(f.trim_suffix(".png"))

## Pull a saved skin's face paint onto the canvas as a NEW face.
func _import_skin() -> void:
	if _skin_imp == null or _skin_imp.selected < 0:
		return
	var nm := _skin_imp.get_item_text(_skin_imp.selected)
	var path := Save.paint_path(Save.current_slot) if nm == CURRENT_SKIN \
		else "%s/%s.png" % [CharacterCreator.SKINS_DIR, nm]
	if not FileAccess.file_exists(path):
		Sfx.play("denied", -14.0)
		return
	_browse_idx = -1   # it lands as a fresh face: Save new adds it to the pool
	_pad.load_png(path)
	Sfx.play("click", -12.0)
	_refresh_files()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_files()
	_refresh_skin_imports()

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
	elif visible and event is InputEventKey and event.pressed \
			and event.keycode == KEY_Z and event.ctrl_pressed:
		_pad.undo()
		get_viewport().set_input_as_handled()
