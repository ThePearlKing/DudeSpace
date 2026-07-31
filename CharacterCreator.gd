class_name CharacterCreator
extends CanvasLayer
## Pick a base colour, a "weird shader" skin, and draw on your torso.
## Start -> saves the character to the current slot and launches the game.

signal started
signal back

var edit_mode: bool = false   # true = restyling an EXISTING dude from the pause menu

var _pivot: Node3D
var _human: Human
var _color: Color = Color("#3aa0ff")
var _shader: String = "none"
var _pad: _Pad
var _shaders := ["none", "pixel", "wth", "wireframe", "contrast"]
var _mode_opt: OptionButton
var _scale_opt: OptionButton
var _name_edit: LineEdit

func _ready() -> void:
	layer = 25
	var bg := ColorRect.new()
	bg.color = Color("#0a0a12")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.position = Vector2(-420, -240)
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(360, 0)
	row.add_child(col)

	var title := Label.new()
	title.text = "EDIT YOUR DUDE" if edit_mode else "CREATE YOUR DUDE"
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Save name (e.g. Noodle Run)"
	_name_edit.custom_minimum_size = Vector2(0, 40)
	col.add_child(_name_edit)

	var cpick := ColorPickerButton.new()
	cpick.custom_minimum_size = Vector2(0, 40)
	cpick.color = _color
	cpick.text = "Base Colour"
	cpick.color_changed.connect(func(c):
		_color = c
		_rebuild())
	col.add_child(cpick)

	var shl := Label.new()
	shl.text = "Weird Shader Skin"
	col.add_child(shl)
	var opt := OptionButton.new()
	for s in _shaders:
		opt.add_item(s)
	opt.item_selected.connect(func(i):
		_shader = _shaders[i]
		_rebuild())
	col.add_child(opt)

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

	var dl := Label.new()
	dl.text = "Draw your FACE:"
	col.add_child(dl)
	_pad = _Pad.new()
	_pad.custom_minimum_size = Vector2(220, 220)
	_pad.painted.connect(_rebuild)
	col.add_child(_pad)

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
		cpick.color = _color
		var si := _shaders.find(_shader)
		if si >= 0:
			opt.select(si)
		_pad.load_png(Save.paint_path(Save.current_slot))

	_rebuild()

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
	_human.build(_color, _shader, _pad.texture() if _pad else null)

func _on_start() -> void:
	if _pad:
		_pad.save_png(Save.paint_path(Save.current_slot))
	if edit_mode:
		Save.character["color"] = _color.to_html(false)
		Save.character["shader"] = _shader
		Sfx.play("learn")
		started.emit()
		return
	var scales := [1.0, 2.0, 4.0, 10.0]
	var data := {
		"color": _color.to_html(false), "shader": _shader,
		"hardcore": _mode_opt.selected == 1,
		"wscale": scales[_scale_opt.selected],
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
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var x := px.x + dx
				var y := px.y + dy
				if x >= 0 and x < 128 and y >= 0 and y < 128 and dx * dx + dy * dy <= 9:
					_img.set_pixel(x, y, Color(0, 0, 0, 0) if _erasing else ink)
		_tex.update(_img)
		queue_redraw()
		painted.emit()
