class_name PickUI
extends CanvasLayer
## A small centered chooser: title, one button per option, Esc/X out.
## Used by the House Construction Kit and the Furniture Placer.

var title_text := "PICK"
var options: Array = []   # [{id, label}]
var on_pick: Callable

func configure(t: String, opts: Array, cb: Callable) -> PickUI:
	title_text = t
	options = opts
	on_pick = cb
	return self

func _ready() -> void:
	layer = 21
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Panel.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(360, 120 + options.size() * 46)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1e1f24")
	st.border_color = Color("#5a5f68")
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	root.add_theme_stylebox_override("panel", st)
	add_child(root)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	for o in options:
		var b := Button.new()
		b.text = str(o["label"])
		b.custom_minimum_size = Vector2(0, 38)
		var oid := str(o["id"])
		b.pressed.connect(func() -> void:
			var cb := on_pick
			_close()
			cb.call(oid))
		col.add_child(b)
	var c := Button.new()
	c.text = "cancel"
	c.custom_minimum_size = Vector2(0, 32)
	c.pressed.connect(_close)
	col.add_child(c)

func _close() -> void:
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
