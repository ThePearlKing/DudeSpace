class_name LocatorUI
extends CanvasLayer
## Right-click with the Locator: pick a target from a proper menu.
## Green ping appears on the HUD for 45s.

const TARGETS := ["ALIEN SHIP", "SPACE INVADERS", "SHADOW TEMPLE", "UFO", "TIME RIFT", "MINE ENTRANCE", "CONNECT 4 ARENA", "NOODLE GOD"]

var _status: Label

func _ready() -> void:
	layer = 23
	visible = false
	add_to_group("closable_ui")
	add_to_group("locator_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 540)
	panel.size = Vector2(360, 540)
	panel.position = Vector2(-180, -270)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a140c")
	sb.border_color = Color("#2bff6a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var title := Label.new()
	title.text = "LOCATOR"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color("#2bff6a")
	col.add_child(title)

	for i in TARGETS.size():
		var idx := i
		var b := Button.new()
		b.text = TARGETS[i]
		b.custom_minimum_size = Vector2(0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_entered.connect(func() -> void: b.modulate = Color(1.25, 1.25, 1.25))
		b.mouse_exited.connect(func() -> void: b.modulate = Color(1, 1, 1))
		b.pressed.connect(func() -> void:
			var p := get_tree().get_first_node_in_group("player")
			if p and p.has_method("locate"):
				p.locate(idx)
			close_ui())
		col.add_child(b)

	# planets: hand off to the map's picker -- right-click one there
	var pb := Button.new()
	pb.text = "PLANET (pick on the map)"
	pb.custom_minimum_size = Vector2(0, 46)
	pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pb.mouse_entered.connect(func() -> void: pb.modulate = Color(1.25, 1.25, 1.25))
	pb.mouse_exited.connect(func() -> void: pb.modulate = Color(1, 1, 1))
	pb.pressed.connect(func() -> void:
		close_ui()
		var mp = get_tree().get_first_node_in_group("map_ui")
		if mp != null:
			var hudl = get_tree().get_first_node_in_group("hud")
			if hudl:
				hudl.flash("RIGHT-CLICK a planet on the map to locate it (30s)")
			mp.open_select(func(b) -> void:
				var p := get_tree().get_first_node_in_group("player")
				if p and p.has_method("locate_planet"):
					p.locate_planet(b)))
	col.add_child(pb)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.text = "ping lasts 45s (planets 30s) · shows through planets"
	col.add_child(_status)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_ui)
	col.add_child(close)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("click", -14.0)

func close_ui() -> void:
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_ui()
		get_viewport().set_input_as_handled()
