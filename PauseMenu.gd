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
	if not (Net.active and not Net.is_host):
		# guests don't get to open someone ELSE'S world to LAN
		col.add_child(_btn("Open to LAN", _open_lan))
	col.add_child(_btn("Options", _open_options))
	col.add_child(_btn("Cheats", _open_cheats))
	col.add_child(_btn("Edit Character (look)", _open_editor))
	col.add_child(_btn("Pose (photo)", _open_poses))
	col.add_child(_btn("Screenshots Folder", func() -> void:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		OS.shell_open(ProjectSettings.globalize_path("user://screenshots"))))
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

var _lan_panel: PanelContainer
var _lan_status: Label
var _lan_btn: Button

## Minecraft-style: open THIS world to the LAN. Rules persist in the save.
func _open_lan() -> void:
	if _lan_panel:
		_panel.visible = false
		_refresh_lan()
		_lan_panel.visible = true
		return
	_lan_panel = PanelContainer.new()
	_lan_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lan_panel.position = Vector2(-220, -220)
	add_child(_lan_panel)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	_lan_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	var title := Label.new()
	title.text = "OPEN TO LAN"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)

	var rules := [
		["allow_cheats", "Guests may use cheats"],
		["allow_chat", "Guests may chat"],
		["friendly_fire", "Friendly fire"],
		["break_others", "Players may break others' machines"],
	]
	for r in rules:
		var key: String = r[0]
		var cb := CheckBox.new()
		cb.text = r[1]
		cb.button_pressed = bool(Game.host_cfg.get(key, false))
		cb.toggled.connect(func(on: bool) -> void:
			Game.host_cfg[key] = on
			if Net.is_host:
				Net.host_settings[key] = on
				Net.push_settings())   # rule changes reach guests live
		col.add_child(cb)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	col.add_child(prow)
	var plbl := Label.new()
	plbl.text = "Port"
	prow.add_child(plbl)
	var pedit := LineEdit.new()
	pedit.text = str(int(Game.host_cfg.get("port", 24545)))
	pedit.custom_minimum_size = Vector2(120, 36)
	pedit.text_changed.connect(func(t: String) -> void:
		if t.is_valid_int():
			Game.host_cfg["port"] = clampi(int(t), 1024, 65535))
	prow.add_child(pedit)

	_lan_status = Label.new()
	_lan_status.add_theme_font_size_override("font_size", 13)
	_lan_status.modulate = Color(1, 1, 1, 0.7)
	_lan_status.custom_minimum_size = Vector2(380, 0)
	_lan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_lan_status)

	_lan_btn = Button.new()
	_lan_btn.custom_minimum_size = Vector2(0, 44)
	_lan_btn.pressed.connect(_toggle_hosting)
	col.add_child(_lan_btn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func() -> void:
		_lan_panel.visible = false
		_panel.visible = true)
	col.add_child(back)

	_panel.visible = false
	_refresh_lan()

func _toggle_hosting() -> void:
	if Net.is_host:
		Net.leave()
	else:
		var err := Net.host(Game.host_cfg)
		if err != "" and _lan_status:
			_lan_status.text = err
	_refresh_lan()

func _refresh_lan() -> void:
	if _lan_btn == null:
		return
	_lan_btn.text = "Stop hosting" if Net.is_host else "Start hosting"
	if Net.is_host:
		var ips: Array = []
		for a in IP.get_local_addresses():
			if str(a).count(".") == 3 and not str(a).begins_with("127."):
				ips.append(str(a))
		_lan_status.text = "LIVE -- players on your network will see this world in their LAN list.\nYour addresses: %s · port %d · %d connected" \
			% [", ".join(ips) if not ips.is_empty() else "?", int(Game.host_cfg.get("port", 24545)), Net.player_names.size()]
	else:
		_lan_status.text = "Rules are saved with this world and enforced for guests while hosting."

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# placement hologram up? Esc cancels the construction, not the game
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and "_ghost" in pl and pl._ghost != null:
			pl._cancel_ghost()
			Sfx.play("click", -18.0)
			get_viewport().set_input_as_handled()
			return
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
	# in a multiplayer session the WORLD never pauses -- freezing your
	# own sim just parks you blind while everyone else keeps moving.
	# The menu still opens; the universe keeps going behind it.
	get_tree().paused = _paused and not Net.active
	if _paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
var _cheat_upds: Array = []

func _open_cheats() -> void:
	if not Net.cheats_allowed():
		Sfx.play("denied")   # host said no guest cheats
		return
	if _cheats:
		_panel.visible = false
		_cheats.visible = true
		for u in _cheat_upds:
			u.call()
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
	# toggles GLOW while active -- you can see what's on at a glance
	_cheat_upds.clear()
	var mkc := func(text: String, get_on: Callable, tog: Callable) -> void:
		var b := _btn(text, func() -> void: pass)
		b.pressed.connect(func() -> void:
			Game.cheated = true
			tog.call()
			for u in _cheat_upds:
				u.call())
		col.add_child(b)
		_cheat_upds.append(func() -> void:
			var on: bool = get_on.call()
			b.modulate = Color(0.55, 1.0, 0.65) if on else Color(1, 1, 1)
			b.text = text + ("   ● ON" if on else ""))
	mkc.call("Godmode",
		func() -> bool: return Game.godmode,
		func() -> void:
			Game.godmode = not Game.godmode
			Sfx.play("learn" if Game.godmode else "click"))
	mkc.call("Keep Inventory",
		func() -> bool: return Game.keep_inv,
		func() -> void:
			Game.keep_inv = not Game.keep_inv
			Sfx.play("learn" if Game.keep_inv else "click"))
	mkc.call("Creative (free craft + creative tab)",
		func() -> bool: return Game.creative or Game.free_craft,
		func() -> void:
			Game.creative = not Game.creative
			Game.free_craft = Game.creative
			Sfx.play("learn" if Game.creative else "click"))
	mkc.call("Infinite Fuel",
		func() -> bool: return Game.inf_fuel,
		func() -> void:
			Game.inf_fuel = not Game.inf_fuel
			Sfx.play("learn" if Game.inf_fuel else "click"))
	mkc.call("Noclip (fast fly)",
		func() -> bool:
			var p := get_tree().get_first_node_in_group("player")
			return p != null and p.noclip,
		func() -> void:
			var p := get_tree().get_first_node_in_group("player")
			if p:
				p.noclip = not p.noclip
				Sfx.play("warp" if p.noclip else "click"))
	for u0 in _cheat_upds:
		u0.call()
	# the gods, on a leash
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 8)
	col.add_child(grow)
	var calm := Button.new()
	calm.text = "Calm gods"
	calm.custom_minimum_size = Vector2(146, 44)
	calm.pressed.connect(func() -> void:
		Game.cheated = true
		Game.wrath = 0.0
		Game.changed.emit()
		Sfx.play("click"))
	grow.add_child(calm)
	var anger := Button.new()
	anger.text = "Anger gods"
	anger.custom_minimum_size = Vector2(146, 44)
	anger.pressed.connect(func() -> void:
		Game.cheated = true
		Game.wrath = Game.WRATH_MAX
		Game.changed.emit()
		_toggle())
	grow.add_child(anger)
	col.add_child(_btn("Summon UFO trader", func() -> void:
		Game.cheated = true
		var cs := get_tree().current_scene
		if cs and cs.has_method("summon_ufo"):
			cs.summon_ufo()))
	col.add_child(_btn("Teleport to planet…", _open_tp))
	col.add_child(_btn("Monolith cheats…  ⚠ SPOILERS", _open_mono))
	col.add_child(_btn("Back", func() -> void:
		_cheats.visible = false
		_panel.visible = true))
	_panel.visible = false

var _mono: PanelContainer

func _open_mono() -> void:
	_cheats.visible = false
	if _mono:
		_mono.visible = true
		return
	_mono = PanelContainer.new()
	_mono.set_anchors_preset(Control.PRESET_CENTER)
	_mono.position = Vector2(-190, -200)
	OptionsPanel._glow(_mono)
	add_child(_mono)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	_mono.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var title := Label.new()
	title.text = "MONOLITH CHEATS"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	var warn := Label.new()
	warn.text = "⚠ SPOILERS AHEAD. these touch the chain,\nthe sky, and the edge of the universe."
	warn.add_theme_font_size_override("font_size", 13)
	warn.modulate = Color("#ff5a5a")
	col.add_child(warn)
	var msync := func() -> void:
		var cs := get_tree().current_scene
		if cs and cs.has_method("_on_monolith_advanced"):
			cs._on_monolith_advanced()
		if cs and cs.has_method("_monolith_snap"):
			cs._monolith_snap()
	col.add_child(_btn("Activate every built monolith", func() -> void:
		Game.cheated = true
		Game.monolith_stage = 2
		msync.call()
		Sfx.play("learn")))
	col.add_child(_btn("BREAK THE UNIVERSE (set stage 8)", func() -> void:
		Game.cheated = true
		Game.monolith_stage = 8
		msync.call()
		var cs2 := get_tree().current_scene
		if cs2 and cs2.has_method("sky_shatter"):
			cs2.sky_shatter()))
	col.add_child(_btn("Reset ALL monolith progress", func() -> void:
		Game.cheated = true
		Game.monolith_stage = 0
		msync.call()
		Sfx.play("click")))
	col.add_child(_btn("Clear sky effects", func() -> void:
		Game.cheated = true
		var cs := get_tree().current_scene
		if cs and cs.has_method("mono_sky_clear"):
			cs.mono_sky_clear()
		Sfx.play("click")))
	var sk := Label.new()
	sk.text = "preview a sky (VISUAL ONLY -- the god still guards the edge\nunless you BREAK THE UNIVERSE above):"
	sk.add_theme_font_size_override("font_size", 13)
	col.add_child(sk)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	col.add_child(srow)
	for si in 8:
		var sb2 := Button.new()
		sb2.text = str(si + 1) if si < 7 else "8💥"
		sb2.custom_minimum_size = Vector2(38, 38)
		sb2.modulate = Game.MONO_COLORS[si]
		var idx := si
		sb2.pressed.connect(func() -> void:
			Game.cheated = true
			var cs := get_tree().current_scene
			# 8 previews the SHATTER itself; 1-7 preview crack skies.
			# previews are VISUAL ONLY -- the boundary still stands
			# unless you BREAK THE UNIVERSE above.
			if idx == 7:
				if cs and cs.has_method("sky_shatter"):
					cs.sky_shatter()
			elif cs and cs.has_method("mono_sky_demo"):
				cs.mono_sky_demo(idx)
			Sfx.play("warp", -12.0))
		srow.add_child(sb2)
	col.add_child(_btn("Toggle universe boundary lattice", func() -> void:
		Game.cheated = true
		var cs := get_tree().current_scene
		if cs and "_boundary_mesh" in cs and cs._boundary_mesh != null:
			cs._boundary_mesh.visible = not cs._boundary_mesh.visible
		Sfx.play("click")))
	col.add_child(_btn("Back", func() -> void:
		_mono.visible = false
		_cheats.visible = true))

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
	# pick straight off the star map instead of scrolling a list
	var mapb := Button.new()
	mapb.text = "🗺 Pick on map"
	mapb.custom_minimum_size = Vector2(250, 42)
	mapb.pressed.connect(func() -> void:
		var m = get_tree().get_first_node_in_group("map_ui")
		if m and m.has_method("open_select"):
			_toggle()   # unpause; the map takes over
			m.open_select(func(body) -> void: _tp_to(body)))
	col.add_child(mapb)
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
	# your FRIENDS are destinations too
	if Net.active:
		for pid in Net.player_names.keys():
			var pd := int(pid)
			var pbtn := Button.new()
			pbtn.text = "→ %s" % str(Net.player_names[pid])
			pbtn.custom_minimum_size = Vector2(250, 38)
			pbtn.pressed.connect(func() -> void:
				if Net.player_pos.has(pd):
					var pup: Vector3 = Net.player_ups.get(pd, Vector3.UP)
					_tp_pos((Net.player_pos[pd] as Vector3) + pup * 1.5, Game.zone, Game.zone_g))
			list.add_child(pbtn)
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
	# save the EXACT spot, not the last 5s autosave -- and the FLOWN
	# ship, not whichever parked hull joined the group first
	var n: Node = null
	if Game.mode == Game.Mode.IN_ROCKET:
		for r9 in get_tree().get_nodes_in_group("rocket"):
			if r9 is Rocket and r9.piloted:
				n = r9
				break
	if n == null:
		var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
		n = get_tree().get_first_node_in_group(g)
	if n:
		Save.set_player_pos(n.global_position, Game.mode == Game.Mode.IN_ROCKET,
			n.hyperdrive if n is Rocket else false,
			n.mk2 if n is Rocket else false,
			n.vel if n is Rocket else Vector3.ZERO,
			n.hyper_charge if n is Rocket else 4.0,
			n.nuclear if n is Rocket else false,
			n.edge_won if n is Rocket else false)
	var cs := get_tree().current_scene
	if cs and cs.has_method("collect_world") and cs.get("_world_load_ok"):
		Save.set_world(cs.collect_world())
	Save.save_progress()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://Title.tscn")

func _any_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group("closable_ui"):
		if ui.visible:
			return true
	return false
