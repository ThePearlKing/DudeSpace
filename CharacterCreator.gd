class_name CharacterCreator
extends CanvasLayer
## Pick a base colour, a "weird shader" skin, and draw on your torso.
## Start -> saves the character to the current slot and launches the game.

signal started
signal back

var edit_mode: bool = false    # true = restyling an EXISTING dude from the pause menu
var guest_mode: bool = false   # true = dressing up before joining a LAN server

const SKINS_DIR := "user://skins"

var _pivot: Node3D
var _human: Human
var _color: Color = Color("#3aa0ff")
var _shader: String = "none"
var _pad: _Pad
var _shaders := ["none", "pixel", "wth", "wireframe", "contrast", "effect"]
var _fx := {"strength": 1.0, "speed": 1.0, "nscale": 5.0, "sharp": 2.0,
	"rainbow": 0.0, "fluid": 0.0}
var _fx_box: VBoxContainer
var _fx_sliders := {}
var _mode_opt: OptionButton
var _scale_opt: OptionButton
var _bscale_cb: CheckBox
var _name_edit: LineEdit
var _cpick: ColorPickerButton
var _shader_opt: OptionButton
var _skin_name: LineEdit
var _skin_opt: OptionButton

func _ready() -> void:
	layer = 25
	var bg := ColorRect.new()
	bg.color = Color("#0a0a12")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	# anchored high: the effect panel made the column tall enough to run
	# off the bottom when centered
	row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	row.position = Vector2(-420, 24)
	row.add_theme_constant_override("separation", 30)
	add_child(row)

	# --- 3D preview ---
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(380, 460)
	row.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.size = Vector2i(380, 460)
	svc.add_child(sv)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#12121e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8890a0")
	env.ambient_light_energy = 1.0
	we.environment = env
	sv.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 4.6)
	cam.rotation_degrees = Vector3(-3, 0, 0)
	sv.add_child(cam)
	var light := OmniLight3D.new()
	light.position = Vector3(3, 4, 4)
	light.light_energy = 4.0
	light.omni_range = 30.0
	sv.add_child(light)
	_pivot = Node3D.new()
	sv.add_child(_pivot)

	# --- controls ---
	var csc := ScrollContainer.new()
	csc.custom_minimum_size = Vector2(390, 0)
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vps2 := get_viewport().get_visible_rect().size
	csc.custom_minimum_size.y = vps2.y - 60.0
	row.add_child(csc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(360, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csc.add_child(col)

	var title := Label.new()
	title.text = "DRESS FOR THE SERVER" if guest_mode \
		else ("EDIT YOUR DUDE" if edit_mode else "CREATE YOUR DUDE")
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Save name (e.g. Noodle Run)"
	_name_edit.custom_minimum_size = Vector2(0, 40)
	col.add_child(_name_edit)

	_cpick = ColorPickerButton.new()
	_cpick.custom_minimum_size = Vector2(0, 40)
	_cpick.color = _color
	_cpick.text = "Base Colour"
	_cpick.color_changed.connect(func(c):
		_color = c
		_rebuild())
	col.add_child(_cpick)
	var cpick := _cpick

	var shl := Label.new()
	shl.text = "Weird Shader Skin"
	col.add_child(shl)
	_shader_opt = OptionButton.new()
	for s in _shaders:
		_shader_opt.add_item(s)
	_shader_opt.item_selected.connect(func(i):
		_shader = _shaders[i]
		if _fx_box != null:
			_fx_box.visible = _shader == "effect"
		_rebuild())
	col.add_child(_shader_opt)
	var opt := _shader_opt

	# --- EFFECT: the parameterised glow, dials + presets ---
	_fx_box = VBoxContainer.new()
	_fx_box.visible = false
	_fx_box.add_theme_constant_override("separation", 4)
	col.add_child(_fx_box)
	var fxl := Label.new()
	fxl.text = "EFFECT — parameters"
	_fx_box.add_child(fxl)
	for spec in [["strength", 0.0, 2.5], ["speed", 0.1, 3.0],
			["nscale", 1.0, 12.0], ["sharp", 0.5, 4.0]]:
		var key: String = str(spec[0])
		var frow := HBoxContainer.new()
		var fl2 := Label.new()
		fl2.text = key
		fl2.custom_minimum_size = Vector2(80, 0)
		frow.add_child(fl2)
		var sl := HSlider.new()
		sl.min_value = float(spec[1])
		sl.max_value = float(spec[2])
		sl.step = 0.05
		sl.value = float(_fx[key])
		sl.custom_minimum_size = Vector2(220, 22)
		sl.value_changed.connect(func(v: float) -> void:
			_fx[key] = v
			_rebuild())
		frow.add_child(sl)
		_fx_sliders[key] = sl
		_fx_box.add_child(frow)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	_fx_box.add_child(rrow)
	var rb := CheckBox.new()
	rb.text = "rainbow (prism mode)"
	rb.toggled.connect(func(v: bool) -> void:
		_fx["rainbow"] = 1.0 if v else 0.0
		_rebuild())
	_fx_sliders["rainbow"] = rb
	rrow.add_child(rb)
	var fb := CheckBox.new()
	fb.text = "fluid (smooth liquid boil)"
	fb.toggled.connect(func(v: bool) -> void:
		_fx["fluid"] = 1.0 if v else 0.0
		_rebuild())
	_fx_sliders["fluid"] = fb
	_fx_box.add_child(fb)
	var pl2 := Label.new()
	pl2.text = "EFFECT PRESETS"
	_fx_box.add_child(pl2)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	_fx_box.add_child(prow)
	for pr in [["Ultima glow", {"strength": 1.0, "speed": 1.0, "nscale": 5.0,
				"sharp": 2.0, "rainbow": 0.0, "fluid": 0.0}],
			["Prism glow", {"strength": 1.0, "speed": 1.0, "nscale": 5.0,
				"sharp": 2.0, "rainbow": 1.0, "fluid": 0.0}],
			["Fluid", {"strength": 0.7, "speed": 0.5, "nscale": 4.0,
				"sharp": 1.0, "rainbow": 0.0, "fluid": 1.0}]]:
		var pb := Button.new()
		pb.text = str(pr[0])
		var preset: Dictionary = pr[1]
		pb.pressed.connect(func() -> void:
			for k in preset:
				_fx[k] = preset[k]
			_sync_fx_ui()
			_rebuild())
		prow.add_child(pb)

	# run settings
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	col.add_child(mrow)
	var ml := Label.new()
	ml.text = "Mode"
	ml.custom_minimum_size = Vector2(110, 0)
	mrow.add_child(ml)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Normal")
	_mode_opt.add_item("HARDCORE (any death = permadeath)")
	mrow.add_child(_mode_opt)

	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 10)
	col.add_child(wrow)
	var wl := Label.new()
	wl.text = "World size"
	wl.custom_minimum_size = Vector2(110, 0)
	wrow.add_child(wl)
	_scale_opt = OptionButton.new()
	_scale_opt.add_item("1x")
	_scale_opt.add_item("2x (big planets, long hauls)")
	_scale_opt.add_item("4x (absurd. good luck)")
	_scale_opt.add_item("10x (NOT RECOMMENDED. way too big)")
	wrow.add_child(_scale_opt)

	# big worlds get sparse -- opt into loot density that keeps up
	_bscale_cb = CheckBox.new()
	_bscale_cb.text = "Loot density scales with world size"
	_bscale_cb.disabled = true   # meaningless at 1x
	col.add_child(_bscale_cb)
	_scale_opt.item_selected.connect(func(i: int) -> void:
		_bscale_cb.disabled = i == 0
		if i == 0:
			_bscale_cb.button_pressed = false)

	var dl := Label.new()
	dl.text = "Draw your FACE:"
	col.add_child(dl)
	_pad = _Pad.new()
	_pad.custom_minimum_size = Vector2(220, 220)
	# SQUARE. the canvas is square, the face is square, the pad is
	# square. no more stretching into a rectangle inside the column.
	_pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pad.painted.connect(_rebuild)
	col.add_child(_pad)

	# --- skin library: save the whole look locally, reuse it anywhere ---
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	col.add_child(srow)
	_skin_name = LineEdit.new()
	_skin_name.placeholder_text = "skin name"
	_skin_name.custom_minimum_size = Vector2(180, 36)
	srow.add_child(_skin_name)
	var sbtn := Button.new()
	sbtn.text = "Save Skin"
	sbtn.custom_minimum_size = Vector2(120, 36)
	sbtn.pressed.connect(_save_skin)
	srow.add_child(sbtn)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	col.add_child(lrow)
	_skin_opt = OptionButton.new()
	_skin_opt.custom_minimum_size = Vector2(180, 36)
	lrow.add_child(_skin_opt)
	var lbtn := Button.new()
	lbtn.text = "Load"
	lbtn.custom_minimum_size = Vector2(120, 36)
	lbtn.pressed.connect(_load_selected_skin)
	lrow.add_child(lbtn)
	_refresh_skins()

	# colour palette + eraser
	var pal := HBoxContainer.new()
	pal.add_theme_constant_override("separation", 4)
	col.add_child(pal)
	var colours := ["#20140a", "#e23b3b", "#ff8c1a", "#ffd21a", "#2ecc40",
		"#3aa0ff", "#b56cff", "#ffffff", "#000000"]
	for hex in colours:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(28, 28)
		var sbn := StyleBoxFlat.new()
		sbn.bg_color = Color(hex)
		sbn.set_corner_radius_all(4)
		sw.add_theme_stylebox_override("normal", sbn)
		sw.add_theme_stylebox_override("hover", sbn)
		sw.add_theme_stylebox_override("pressed", sbn)
		sw.pressed.connect(func(): _pad.set_ink(Color(hex)))
		pal.add_child(sw)
	var inkpick := ColorPickerButton.new()
	inkpick.custom_minimum_size = Vector2(28, 28)
	inkpick.color = Color("#20140a")
	inkpick.tooltip_text = "any ink colour"
	inkpick.color_changed.connect(func(c): _pad.set_ink(c))
	pal.add_child(inkpick)
	var erase := Button.new()
	erase.text = "Erase"
	erase.pressed.connect(func(): _pad.set_erase())
	pal.add_child(erase)
	var clr := Button.new()
	clr.text = "Clear"
	clr.pressed.connect(func():
		_pad.clear()
		_rebuild())
	pal.add_child(clr)

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
	bsl.custom_minimum_size = Vector2(220, 22)
	bsl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bsl.value_changed.connect(func(v: float) -> void:
		_pad.set_brush(int(v))
		blbl.text = "brush %d" % int(v))
	brow.add_child(bsl)

	var start := Button.new()
	start.text = "APPLY" if edit_mode else "START"
	start.custom_minimum_size = Vector2(0, 46)
	start.pressed.connect(_on_start)
	col.add_child(start)
	var bk := Button.new()
	bk.text = "Back"
	bk.pressed.connect(func(): back.emit())
	col.add_child(bk)

	if edit_mode:
		# restyle: keep the run, load the dude as-is
		_name_edit.visible = false
		mrow.visible = false
		wrow.visible = false
		_color = Color.html(str(Save.character.get("color", "3aa0ff")))
		_shader = str(Save.character.get("shader", "none"))
		var sfx = Save.character.get("fx", {})
		if sfx is Dictionary:
			for k in sfx:
				_fx[k] = sfx[k]
		_sync_fx_ui()
		_fx_box.visible = _shader == "effect"
		cpick.color = _color
		var si := _shaders.find(_shader)
		if si >= 0:
			opt.select(si)
		_pad.load_png(Save.paint_path(Save.current_slot))
	elif guest_mode:
		# joining a server: look only -- no run settings, no save name.
		# start from the current look so you're not redrawing every visit
		_name_edit.visible = false
		mrow.visible = false
		wrow.visible = false
		_color = Color.html(str(Save.character.get("color", "3aa0ff")))
		_shader = str(Save.character.get("shader", "none"))
		cpick.color = _color
		var sig := _shaders.find(_shader)
		if sig >= 0:
			opt.select(sig)
		_pad.load_png(Save.paint_path(Save.current_slot))

	_rebuild()

func _sync_fx_ui() -> void:
	for k in ["strength", "speed", "nscale", "sharp"]:
		if _fx_sliders.has(k):
			_fx_sliders[k].set_value_no_signal(float(_fx.get(k, 1.0)))
	if _fx_sliders.has("rainbow"):
		_fx_sliders["rainbow"].set_pressed_no_signal(float(_fx["rainbow"]) > 0.5)
	if _fx_sliders.has("fluid"):
		_fx_sliders["fluid"].set_pressed_no_signal(float(_fx.get("fluid", 0.0)) > 0.5)

func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotate_y(delta * 0.7)

func _rebuild() -> void:
	if _pad:
		_pad.bg_color = _color
		_pad.queue_redraw()
	if _human and is_instance_valid(_human):
		_human.queue_free()
	_human = Human.new()
	_pivot.add_child(_human)
	_human.build(_color, _shader, _pad.texture() if _pad else null, _fx)

# --------------------------------------------------------- skin library

func _refresh_skins() -> void:
	if _skin_opt == null:
		return
	_skin_opt.clear()
	DirAccess.make_dir_recursive_absolute(SKINS_DIR)
	var d := DirAccess.open(SKINS_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			_skin_opt.add_item(f.trim_suffix(".json"))

func _save_skin() -> void:
	var nm := _skin_name.text.strip_edges().validate_filename()
	if nm == "":
		return
	DirAccess.make_dir_recursive_absolute(SKINS_DIR)
	var f := FileAccess.open("%s/%s.json" % [SKINS_DIR, nm], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"color": _color.to_html(false),
			"shader": _shader, "fx": _fx}))
		f.close()
	if _pad:
		_pad.save_png("%s/%s.png" % [SKINS_DIR, nm])
	Sfx.play("learn", -12.0)
	_refresh_skins()

func _load_selected_skin() -> void:
	if _skin_opt == null or _skin_opt.selected < 0:
		return
	var nm := _skin_opt.get_item_text(_skin_opt.selected)
	var raw := FileAccess.get_file_as_string("%s/%s.json" % [SKINS_DIR, nm])
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		_color = Color.html(str(parsed.get("color", "3aa0ff")))
		_shader = str(parsed.get("shader", "none"))
		var pfx = parsed.get("fx", {})
		if pfx is Dictionary:
			for k in pfx:
				_fx[k] = pfx[k]
		_sync_fx_ui()
		if _fx_box:
			_fx_box.visible = _shader == "effect"
		if _cpick:
			_cpick.color = _color
		var si := _shaders.find(_shader)
		if si >= 0 and _shader_opt:
			_shader_opt.select(si)
	if _pad:
		_pad.load_png("%s/%s.png" % [SKINS_DIR, nm])
	_skin_name.text = nm
	Sfx.play("click", -12.0)
	_rebuild()

func _on_start() -> void:
	if guest_mode:
		# server visit: the look lives in memory, never on this disk
		Save.character = {"color": _color.to_html(false), "shader": _shader,
			"fx": _fx}
		Net.guest_paint = _pad.png_bytes() if _pad else PackedByteArray()
		Sfx.play("learn")
		started.emit()
		return
	if _pad:
		_pad.save_png(Save.paint_path(Save.current_slot))
	if edit_mode:
		Save.character["color"] = _color.to_html(false)
		Save.character["shader"] = _shader
		Save.character["fx"] = _fx
		Sfx.play("learn")
		started.emit()
		return
	var scales := [1.0, 2.0, 4.0, 10.0]
	var data := {
		"color": _color.to_html(false), "shader": _shader, "fx": _fx,
		"hardcore": _mode_opt.selected == 1,
		"wscale": scales[_scale_opt.selected],
		"bscale": _bscale_cb != null and _bscale_cb.button_pressed,
	}
	Save.new_slot(Save.current_slot, data, _name_edit.text if _name_edit else "")
	started.emit()

## A tiny paint canvas.
class _Pad extends Control:
	signal painted
	var _img: Image
	var _tex: ImageTexture
	var ink: Color = Color("#20140a")
	var bg_color: Color = Color("#c8b89a")   # preview backdrop (real skin shows in 3D)
	var _erasing: bool = false
	var brush: int = 7   # stroke width in canvas pixels (1..128)

	func set_brush(b: int) -> void:
		brush = clampi(b, 1, 128)

	func set_ink(c: Color) -> void:
		ink = c
		_erasing = false

	func set_erase() -> void:
		_erasing = true

	func _ready() -> void:
		# transparent sheet: ink opaque, undrawn stays clear so skin shows through
		_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		_img.fill(Color(0, 0, 0, 0))
		_tex = ImageTexture.create_from_image(_img)

	func texture() -> Texture2D:
		return _tex

	func save_png(path: String) -> void:
		_img.save_png(path)

	func png_bytes() -> PackedByteArray:
		return _img.save_png_to_buffer()

	func clear() -> void:
		_img.fill(Color(0, 0, 0, 0))
		_tex.update(_img)
		queue_redraw()
		painted.emit()

	func load_png(path: String) -> void:
		if not FileAccess.file_exists(path):
			return
		var im := Image.new()
		if im.load(path) != OK:
			return
		im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != 128 or im.get_height() != 128:
			im.resize(128, 128)
		_img = im
		_tex.update(_img)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), bg_color)           # skin backdrop
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color("#ffffff"), false, 2.0)

	func _gui_input(event: InputEvent) -> void:
		var painting := false
		var p := Vector2.ZERO
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			p = event.position
			painting = true
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			p = event.position
			painting = true
		if not painting:
			return
		var uv := (p / size).clamp(Vector2.ZERO, Vector2.ONE)
		var px := Vector2i(uv * Vector2(127, 127))
		var r := brush >> 1
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var x := px.x + dx
				var y := px.y + dy
				if x >= 0 and x < 128 and y >= 0 and y < 128 \
						and dx * dx + dy * dy <= r * r + r:
					_img.set_pixel(x, y, Color(0, 0, 0, 0) if _erasing else ink)
		_tex.update(_img)
		queue_redraw()
		painted.emit()
