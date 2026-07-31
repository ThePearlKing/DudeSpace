class_name StatsOverlay
extends CanvasLayer
## F3 debug stats: position, velocity, mode, planet, fps, meters.

var _lbl: Label
var _on: bool = false

func _ready() -> void:
	layer = 14
	_lbl = Label.new()
	_lbl.position = Vector2(0, 26)
	_lbl.add_theme_font_size_override("font_size", 15)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lbl.position = Vector2(-360, 26)
	_lbl.size = Vector2(340, 0)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_on = not _on
		visible = _on

func _process(_delta: float) -> void:
	if not _on:
		return
	var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
	var n := get_tree().get_first_node_in_group(g)
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	if n:
		pos = n.global_position
		if n is Rocket:
			vel = n.vel
		elif n is Player:
			vel = n.velocity
	var body := Universe.nearest(pos)
	var alt := pos.distance_to(body.center) - body.radius
	_lbl.text = "FPS %d\nmode %s\npos %.0f %.0f %.0f\nvel %.1f m/s\nplanet %s\nalt %.0f\nhealth %.0f  wrath %.0f\ncoins %d  bank %d\ntime x%.3f" % [
		Engine.get_frames_per_second(),
		"ROCKET" if Game.mode == Game.Mode.IN_ROCKET else "FOOT",
		pos.x, pos.y, pos.z, vel.length(), body.name, alt,
		Game.health, Game.wrath, Inventory.coins, Inventory.bank_coins, Game.dilation]
	if Game.cheated:
		_lbl.text += "\nILLEGITIMATE"
