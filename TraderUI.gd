class_name TraderUI
extends CanvasLayer
## The alien's shop. Everything costs ZeptoBux (exchange coins at any
## powered ATM). He has the car keys. He knows you want them.

var _zb_lbl: Label
var _rows: Array = []

const STOCK := [
	["hyperdrive", "Hyperdrive (alien surplus)", 30, "Ship part. Slightly dented."],
	["charm", "Anti-Death Charm", 40, "\"very good luck. probably.\""],
	["ultima5", "Ultima Crystals ×5", 20, "Fell off a comet, allegedly."],
	["raygun", "Ray Gun", 350, "Genuine alien sidearm. zap zap."],
]

func _ready() -> void:
	layer = 23
	visible = false
	add_to_group("trader_ui")
	add_to_group("closable_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0.06, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 460)
	panel.size = Vector2(560, 460)
	panel.position = Vector2(-280, -230)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a1a0f")
	sb.border_color = Color("#4dff9a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	col.position = Vector2(22, 18)
	panel.add_child(col)

	var title := Label.new()
	title.text = "「 greetings, dense biped 」"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color("#4dff9a")
	col.add_child(title)
	_zb_lbl = Label.new()
	_zb_lbl.add_theme_font_size_override("font_size", 18)
	col.add_child(_zb_lbl)

	for entry in STOCK:
		var e = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		info.custom_minimum_size = Vector2(360, 0)
		info.text = "%s — %d ZB\n%s" % [e[1], e[2], e[3]]
		info.add_theme_font_size_override("font_size", 14)
		row.add_child(info)
		var buy := Button.new()
		buy.text = "BUY"
		buy.custom_minimum_size = Vector2(110, 44)
		buy.pressed.connect(func() -> void: _buy(str(e[0]), int(e[2])))
		row.add_child(buy)
		col.add_child(row)
		_rows.append([e, buy])

	var close := Label.new()
	close.text = "F / E / Esc to leave"
	close.modulate = Color(1, 1, 1, 0.5)
	col.add_child(close)
	Inventory.changed.connect(_refresh)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("learn", -8.0)
	_refresh()

func close_ui() -> void:
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh() -> void:
	_zb_lbl.text = "your ZeptoBux:  %d ZB   (exchange coins at a powered ATM)" % Inventory.zeptobux
	for r in _rows:
		r[1].disabled = Inventory.zeptobux < int(r[0][2]) or not Inventory.any_space()

func _buy(id: String, price: int) -> void:
	if Inventory.zeptobux < price or not Inventory.any_space():
		Sfx.play("denied")
		return
	Inventory.zeptobux -= price
	match id:
		"ultima5":
			Inventory.give("ultima", 5)
		_:
			Inventory.give(id, 1)
	Sfx.play("coin")
	Inventory.changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_F, KEY_ESCAPE]:
		close_ui()
		get_viewport().set_input_as_handled()
