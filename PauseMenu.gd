class_name PauseMenu
extends CanvasLayer
## Esc pause menu. Esc closes the inventory/map first if one is open;
## otherwise it toggles the pause menu. Resume / Options / Quit to title.

var _panel: PanelContainer
var _options: OptionsPanel
var _paused: bool = false

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while paused
	visible = false

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(320, 300)
	_panel.position = Vector2(-160, -150)
	OptionsPanel._glow(_panel)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(pad)
	pad.add_child(col)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(_btn("Resume", _toggle))
	col.add_child(_btn("Options", _open_options))
	col.add_child(_btn("Cheats", _open_cheats))
	col.add_child(_btn("Edit Character (look)", _open_editor))
	col.add_child(_btn("Pose (photo)", _open_poses))
	col.add_child(_btn("Reset Character (to spawn)", _reset_char))
	col.add_child(_btn("Save & Quit to Title", _quit_title))

	_options = OptionsPanel.new()
	_options.set_anchors_preset(Control.PRESET_CENTER)
	_options.position = Vector2(-180, -140)
	_options.visible = false
	_options.closed.connect(func():
		_options.visible = false
		_panel.visible = true)
	add_child(_options)

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if Game.dead:
			return
		if _creator:
			_close_editor()
			get_viewport().set_input_as_handled()
			return
		# Esc closes an open inventory/map before it opens the pause menu.
		for ui in get_tree().get_nodes_in_group("closable_ui"):
			if ui.visible:
				ui.close_ui()
				get_viewport().set_input_as_handled()
				return
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	_paused = not _paused
	visible = _paused
	_panel.visible = _paused
	_options.visible = false
	if _poses:
		_poses.visible = false
	if _cheats:
		_cheats.visible = false
	if _tp:
		_tp.visible = false
	get_tree().paused = _paused
	if _paused:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	elif not Game.dead and not _any_ui_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

var _creator: CharacterCreator

func _open_editor() -> void:
	if _creator:
		_creator.queue_free()
	_creator = CharacterCreator.new()
	_creator.edit_mode = true
	add_child(_creator)
	_panel.visible = false
	_creator.started.connect(func() -> void:
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("refresh_look"):
			p.refresh_look()
		_close_editor()
		_toggle())
	_creator.back.connect(_close_editor)

func _close_editor() -> void:
	if _creator:
		_creator.queue_free()
		_creator = null
	_panel.visible = true

var _poses: PanelContainer

func _open_poses() -> void:
	_panel.visible = false
	if _poses:
		_poses.visible = true
		return
	_poses = PanelContainer.new()
	_poses.set_anchors_preset(Control.PRESET_CENTER)
	_poses.position = Vector2(-140, -170)
	OptionsPanel._glow(_poses)
	add_child(_poses)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	_poses.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	var title := Label.new()
	title.text = "POSE   (G also cycles)"
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)
	for i in Human.POSE_NAMES.size():
		var idx := i
		col.add_child(_btn(Human.POSE_NAMES[i], func() -> void:
			var pp := get_tree().get_first_node_in_group("player")
			if pp and pp.has_method("set_body_pose"):
				pp.set_body_pose(idx)
				Sfx.play("click", -14.0)))
	col.add_child(_btn("Back", func() -> void:
		_poses.visible = false
		_panel.visible = true))

var _cheats: PanelContainer

func _open_cheats() -> void:
	if _cheats:
		_panel.visible = false
		_cheats.visible = true
		return
	_cheats = PanelContainer.new()
	_cheats.set_anchors_preset(Control.PRESET_CENTER)
	_cheats.position = Vector2(-170, -190)
	OptionsPanel._glow(_cheats)
	add_child(_cheats)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	_cheats.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var title := Label.new()
	title.text = "CHEATS"
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)
	var warn := Label.new()
	warn.text = "using ANY of these brands the save\nILLEGITIMATE. forever."
	warn.add_theme_font_size_override("font_size", 13)
	warn.modulate = Color("#ff5a5a")
	col.add_child(warn)
	col.add_child(_btn("∞ Coins (+999,999)", func() -> void:
		Game.cheated = true
		Inventory.add_coins(999999)
		Sfx.play("coin")))
	col.add_child(_btn("+99 ingot/irid/ultima", func() -> void:
		Game.cheated = true
		Inventory.add_res("ingot", 99)
		Inventory.add_res("irid", 99)
		Inventory.add_res("ultima", 99)
		Sfx.play("coin")))
	col.add_child(_btn("Refill health + fuel", func() -> void:
		Game.cheated = true
		Game.health = Game.HEALTH_MAX
		Inventory.fuel = Inventory.fuel_max
		Inventory.jet_fuel = Inventory.jet_max
		Inventory.changed.emit()
		Game.changed.emit()))
	col.add_child(_btn("Unlock everything", func() -> void:
		Game.cheated = true
		Inventory.ak47_recipe = true
		Game.door_open = true
		Game.mind_core = true
		Inventory.has_jetpack = true
		Inventory.engine_mk2 = true
		Inventory.give("hyperdrive", 1)
		Sfx.play("learn")
		Inventory.changed.emit()))
	col.add_child(_btn("Calm the gods", func() -> void:
		Game.cheated = true
		Game.wrath = 0.0
		Game.changed.emit()))
	col.add_child(_btn("Toggle GODMODE", func() -> void:
		Game.cheated = true
		Game.godmode = not Game.godmode
		Sfx.play("learn" if Game.godmode else "click")))
	col.add_child(_btn("Toggle INFINITE FUEL", func() -> void:
		Game.cheated = true
		Game.inf_fuel = not Game.inf_fuel
		Sfx.play("learn" if Game.inf_fuel else "click")))
	col.add_child(_btn("Toggle CREATIVE inventory", func() -> void:
		Game.cheated = true
		Game.creative = not Game.creative
		Sfx.play("learn" if Game.creative else "click")))
	col.add_child(_btn("Toggle FREE CRAFT", func() -> void:
		Game.cheated = true
		Game.free_craft = not Game.free_craft
		Sfx.play("learn" if Game.free_craft else "click")))
	col.add_child(_btn("Toggle KEEP INVENTORY", func() -> void:
		Game.cheated = true
		Game.keep_inv = not Game.keep_inv
		Sfx.play("learn" if Game.keep_inv else "click")))
	col.add_child(_btn("Toggle FREECAM (photo mode)", func() -> void:
		var pf := get_tree().get_first_node_in_group("player")
		if pf and pf.has_method("toggle_freecam"):
			pf.toggle_freecam()
			Sfx.play("click")))
	col.add_child(_btn("Toggle NOCLIP (fast fly)", func() -> void:
		Game.cheated = true
		var p := get_tree().get_first_node_in_group("player")
		if p:
			p.noclip = not p.noclip
			Sfx.play("warp" if p.noclip else "click")))
	col.add_child(_btn("Anger the noodle gods", func() -> void:
		Game.cheated = true
		Game.wrath = Game.WRATH_MAX
		Game.changed.emit()
		_toggle()))
	col.add_child(_btn("Summon UFO trader", func() -> void:
		Game.cheated = true
		var cs := get_tree().current_scene
		if cs and cs.has_method("summon_ufo"):
			cs.summon_ufo()))
	col.add_child(_btn("Teleport to planet…", _open_tp))
	col.add_child(_btn("Back", func() -> void:
		_cheats.visible = false
		_panel.visible = true))
	_panel.visible = false

var _tp: PanelContainer

func _open_tp() -> void:
	_cheats.visible = false
	if _tp:
		_tp.visible = true
		return
	_tp = PanelContainer.new()
	_tp.set_anchors_preset(Control.PRESET_CENTER)
	_tp.position = Vector2(-160, -260)
	OptionsPanel._glow(_tp)
	add_child(_tp)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	_tp.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	var title := Label.new()
	title.text = "TELEPORT  (cheat)"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for b in Universe.bodies:
		var body = b
		var btn := Button.new()
		btn.text = body.name
		btn.custom_minimum_size = Vector2(250, 38)
		btn.pressed.connect(func() -> void:
			_tp_to(body))
		list.add_child(btn)
	# places that aren't planets
	var pois := [
		["Shadow Temple", Zones.shadow_temple_spawn(), "flat", 9.0],
		["Connect-4 Island", Vector3(9000, 6000, -9000) + Vector3(0, 2, 8), "", 9.0],
		["Euclid Temple (interior)", Zones.temple_spawn(), "flat", 9.0],
	]
	for poi in pois:
		var e = poi
		var btn2 := Button.new()
		btn2.text = str(e[0])
		btn2.custom_minimum_size = Vector2(250, 38)
		btn2.pressed.connect(func() -> void:
			_tp_pos(e[1], str(e[2]), float(e[3])))
		list.add_child(btn2)
	col.add_child(_btn("Back", func() -> void:
		_tp.visible = false
		_cheats.visible = true))

func _tp_to(body) -> void:
	var r: float = body.major + body.radius if body.kind == "torus" else body.radius
	_tp_pos(body.center + Vector3.UP * (r + 3.0), "", 9.0)

func _tp_pos(target: Vector3, zone: String, zone_g: float) -> void:
	Game.cheated = true
	Game.zone = zone
	Game.zone_g = zone_g
	if Game.mode == Game.Mode.IN_ROCKET:
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and r.piloted:
				r.global_position = target + Vector3.UP * 3.0
				r.vel = Vector3.ZERO
				break
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("respawn_at") and Game.mode == Game.Mode.ON_FOOT:
		p.respawn_at(target, Vector3.UP)
	elif p:
		p.global_position = target
	Sfx.play("warp")
	_toggle()   # unpause and go

func _reset_char() -> void:
	Game.reset_character()
	_toggle()

func _open_options() -> void:
	_panel.visible = false
	_options.visible = true

func _quit_title() -> void:
	# pet state, fresh -- not whatever the last autosave happened to see
	var petq = get_tree().get_first_node_in_group("pet")
	if petq != null and is_instance_valid(petq):
		Save.set_pet(true, petq.genome, petq.staying)
	else:
		Save.set_pet(false)
	# save the EXACT spot, not the last 5s autosave
	var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
	var n := get_tree().get_first_node_in_group(g)
	if n:
		Save.set_player_pos(n.global_position, Game.mode == Game.Mode.IN_ROCKET,
			n.hyperdrive if n is Rocket else false)
	var cs := get_tree().current_scene
	if cs and cs.has_method("collect_world") and cs.get("_world_load_ok"):
		Save.set_world(cs.collect_world())
	Save.save_progress()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	get_tree().change_scene_to_file("res://Title.tscn")

func _any_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group("closable_ui"):
		if ui.visible:
			return true
	return false
