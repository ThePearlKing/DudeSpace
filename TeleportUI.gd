class_name TeleportUI
extends CanvasLayer
## Waystone-style warp menu. Rename YOUR pad up top; scroll list of every
## other pad below. Full charge + 2000 coins per jump.

var _pad
var _name_edit: LineEdit
var _list: VBoxContainer
var _status: Label

func _ready() -> void:
	layer = 23
	visible = false
	add_to_group("closable_ui")
	add_to_group("teleport_ui")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 560)
	panel.size = Vector2(520, 560)
	panel.position = Vector2(-260, -280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0c1422")
	sb.border_color = Color("#7cf9ff")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	col.position = Vector2(20, 16)
	panel.add_child(col)

	var title := Label.new()
	title.text = "WARP PAD"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color("#7cf9ff")
	col.add_child(title)

	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	col.add_child(nrow)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(340, 38)
	_name_edit.placeholder_text = "name this pad"
	nrow.add_child(_name_edit)
	var rn := Button.new()
	rn.text = "Rename"
	rn.custom_minimum_size = Vector2(120, 38)
	rn.pressed.connect(_rename)
	nrow.add_child(rn)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	col.add_child(_status)

	var dl := Label.new()
	dl.text = "DESTINATIONS"
	dl.add_theme_font_size_override("font_size", 14)
	dl.modulate = Color(1, 1, 1, 0.6)
	col.add_child(dl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(478, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_ui)
	col.add_child(close)

func open_pad(pad) -> void:
	_pad = pad
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_name_edit.text = pad.tname
	_rebuild()
	Sfx.play("click")

func close_ui() -> void:
	visible = false
	_pad = null
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _rename() -> void:
	if _pad and is_instance_valid(_pad):
		var t := _name_edit.text.strip_edges()
		if t != "":
			_pad.tname = t.substr(0, 24)
			Sfx.play("click", -12.0)
			_rebuild()

var _stat_t := 0.0
func _process(delta: float) -> void:
	# the pad charges while you stare at the panel -- show it happening
	if not visible or _pad == null or not is_instance_valid(_pad):
		return
	_stat_t -= delta
	if _stat_t <= 0.0:
		_stat_t = 0.2
		_status.text = "charge %.0f / %.0f EU  ·  %d coins per warp" % [
			_pad.buf, _pad.buf_cap, _pad.TP_COINS]

func _rebuild() -> void:
	if _pad == null or not is_instance_valid(_pad):
		return
	for c in _list.get_children():
		c.queue_free()
	_status.text = "charge %.0f / %.0f EU  ·  %d coins per warp" % [
		_pad.buf, _pad.buf_cap, _pad.TP_COINS]
	var any := false
	for t in get_tree().get_nodes_in_group("teleporter"):
		if t == _pad or not is_instance_valid(t):
			continue
		any = true
		var planet = Universe.nearest(t.global_position)
		var b := Button.new()
		b.text = "%s   ·   %s" % [t.tname, planet.name]
		b.custom_minimum_size = Vector2(460, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var dst = t
		b.pressed.connect(func() -> void: _warp_to(dst))
		_list.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "no other pads on the network. build more."
		l.modulate = Color(1, 1, 1, 0.5)
		_list.add_child(l)

func _warp_to(dst) -> void:
	if _pad == null or not is_instance_valid(_pad) or not is_instance_valid(dst):
		return
	if _pad.buf < _pad.buf_cap:
		Sfx.play("denied")
		_status.text = "NOT CHARGED: %.0f / %.0f EU" % [_pad.buf, _pad.buf_cap]
		_stat_t = 2.0
		return
	if Inventory.coins < _pad.TP_COINS:
		Sfx.play("denied")
		_status.text = "needs %d coins (you have %d)" % [_pad.TP_COINS, Inventory.coins]
		_stat_t = 2.0
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null or Game.mode != Game.Mode.ON_FOOT:
		Sfx.play("denied")
		return
	Inventory.coins -= _pad.TP_COINS
	_pad.buf = 0.0   # the pad eats EVERY drop of charge
	Inventory.changed.emit()
	var up: Vector3 = dst.global_transform.basis.y
	Game.zone = ""
	close_ui()
	p.respawn_at(dst.global_position + up * 1.5, up)
	Sfx.play("warp")
