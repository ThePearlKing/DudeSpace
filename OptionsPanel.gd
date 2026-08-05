class_name OptionsPanel
extends PanelContainer
## Reusable options widget (title screen + pause menu). Mouse sensitivity
## + fullscreen. Emits `closed` when the Back button is pressed.

signal closed

func _ready() -> void:
	_glow(self)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pad.add_child(col)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)

	# multiplayer display name -- shown in chat, over your head, TAB list
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 12)
	col.add_child(urow)
	var ulabel := Label.new()
	ulabel.text = "Username"
	ulabel.custom_minimum_size = Vector2(200, 0)
	urow.add_child(ulabel)
	var uedit := LineEdit.new()
	uedit.text = Settings.username
	uedit.placeholder_text = "Dude"
	uedit.max_length = 24
	uedit.custom_minimum_size = Vector2(240, 38)
	uedit.text_changed.connect(func(t: String) -> void:
		Settings.username = t.strip_edges()
		Settings.save_cfg())
	urow.add_child(uedit)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	col.add_child(srow)
	var slabel := Label.new()
	slabel.text = "Mouse Sensitivity"
	slabel.custom_minimum_size = Vector2(200, 0)
	srow.add_child(slabel)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = Settings.mouse_sensitivity
	slider.custom_minimum_size = Vector2(240, 0)
	slider.value_changed.connect(func(v): Settings.mouse_sensitivity = v)
	srow.add_child(slider)

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	col.add_child(frow)
	var flabel := Label.new()
	flabel.text = "Field of View"
	flabel.custom_minimum_size = Vector2(200, 0)
	frow.add_child(flabel)
	var fov := HSlider.new()
	fov.min_value = 60.0
	fov.max_value = 120.0
	fov.step = 1.0
	fov.value = Settings.fov
	fov.custom_minimum_size = Vector2(240, 0)
	fov.value_changed.connect(func(v): Settings.fov = v)
	frow.add_child(fov)

	# volumes: music (the soundtrack) and SFX (everything punchy)
	for vspec in [["Music Volume", "music_vol"], ["SFX Volume", "sfx_vol"]]:
		var vrow := HBoxContainer.new()
		vrow.add_theme_constant_override("separation", 12)
		col.add_child(vrow)
		var vlabel := Label.new()
		vlabel.text = str(vspec[0])
		vlabel.custom_minimum_size = Vector2(200, 0)
		vrow.add_child(vlabel)
		var vsl := HSlider.new()
		vsl.min_value = 0.0
		vsl.max_value = 1.0
		vsl.step = 0.05
		vsl.value = float(Settings.get(str(vspec[1])))
		vsl.custom_minimum_size = Vector2(240, 0)
		var prop: String = str(vspec[1])
		vsl.value_changed.connect(func(v: float) -> void:
			Settings.set(prop, v)
			if prop == "sfx_vol":
				Sfx.play("click", -14.0))   # instant preview
		vrow.add_child(vsl)

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.apply_fullscreen(on))
	col.add_child(fs)

	var tut := Button.new()
	tut.text = "How to Play"
	tut.custom_minimum_size = Vector2(0, 42)
	tut.pressed.connect(_open_tutorial)
	col.add_child(tut)

	var ctl := Button.new()
	ctl.text = "Controls"
	ctl.custom_minimum_size = Vector2(0, 42)
	ctl.pressed.connect(_open_controls)
	col.add_child(ctl)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func():
		Settings.save_cfg()
		closed.emit())
	col.add_child(back)

var _tut_panel: PanelContainer
var _ctl_panel: PanelContainer
var _rebind_action := ""      # controls panel: waiting for a key for this
var _rebind_btns: Dictionary = {}

func _input(event: InputEvent) -> void:
	# rebind capture: the next key pressed becomes the binding
	if _rebind_action == "" or not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode != KEY_ESCAPE:
		Settings.keys[_rebind_action] = event.keycode
		Settings.save_cfg()
	var btn: Button = _rebind_btns.get(_rebind_action)
	if btn != null and is_instance_valid(btn):
		btn.text = OS.get_keycode_string(Settings.key(_rebind_action))
	_rebind_action = ""
	get_viewport().set_input_as_handled()

## Every keybind in the game, one place.
func _open_controls() -> void:
	if _ctl_panel:
		_ctl_panel.visible = true
		return
	_ctl_panel = PanelContainer.new()
	_ctl_panel.set_anchors_preset(Control.PRESET_CENTER)
	_ctl_panel.position = Vector2(-330, -300)
	_glow(_ctl_panel)
	get_parent().add_child(_ctl_panel)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 20)
	_ctl_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	# REBINDS: click a key, press the new one (Esc cancels)
	var rl := Label.new()
	rl.text = "click a binding, then press the new key"
	rl.add_theme_font_size_override("font_size", 13)
	rl.modulate = Color(1, 1, 1, 0.65)
	col.add_child(rl)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for aspec in [["interact", "Interact"], ["inventory", "Inventory"],
			["jetpack", "Jetpack"], ["jet_down", "Jet descend"],
			["zoom", "Zoom"], ["map", "Map"], ["calendar", "Calendar"],
			["chat", "Chat"], ["pose", "Pose"], ["drop", "Drop item"],
			["hyper", "Hyperdrive"]]:
		var an9 := str(aspec[0])
		var al9 := Label.new()
		al9.text = str(aspec[1])
		al9.add_theme_font_size_override("font_size", 14)
		grid.add_child(al9)
		var ab9 := Button.new()
		ab9.text = OS.get_keycode_string(Settings.key(an9))
		ab9.custom_minimum_size = Vector2(84, 32)
		ab9.pressed.connect(func() -> void:
			_rebind_action = an9
			ab9.text = "...")
		grid.add_child(ab9)
		_rebind_btns[an9] = ab9
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var txt := Label.new()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(620, 0)
	txt.add_theme_font_size_override("font_size", 15)
	txt.text = """ON FOOT
WASD -- move · mouse -- look · Space -- jump (hold: jetpack thrust)
Left click -- attack / mine · Right click -- use / place selected item
F -- interact (machines, gates, board rocket) · E -- inventory + shop
1-5 / scroll -- hotbar select · Q -- drop selected item · J -- jetpack on/off · C -- jetpack descend
V -- zoom · G -- cycle pose · R -- respawn (when dead)
M -- map · K -- calendar · T -- chat · TAB (hold) -- player list (LAN)
F3 -- stats overlay · F5 -- first/third person · Esc -- pause menu

IN ROCKET
Space -- burn engine · WASD -- tilt nose (camera-relative)
1-9 -- time warp 1-9x · 0 -- 10x (coasting only; burning cancels warp)
H -- hyperdrive (if fitted) · arrow keys + Shift/Ctrl -- RCS (if fitted)
F -- exit rocket · M -- map · L-click -- smash

INVENTORY / CHESTS
Click -- pick up / put down stack · Right click -- half / place one
Scroll over slot -- stream items across · drag armor onto slot to wear
Right-click armor in hand -- wear it
Click OUTSIDE the panel -- drop held stack on the floor
🗑 DELETE slot -- click with a held stack to destroy it

MAP
Wheel -- zoom · left-drag -- pan"""
	scroll.add_child(txt)
	var cls := Button.new()
	cls.text = "Close"
	cls.custom_minimum_size = Vector2(0, 40)
	cls.pressed.connect(func() -> void: _ctl_panel.visible = false)
	col.add_child(cls)

func _open_tutorial() -> void:
	if _tut_panel:
		_tut_panel.visible = true
		return
	_tut_panel = PanelContainer.new()
	_tut_panel.set_anchors_preset(Control.PRESET_CENTER)
	_tut_panel.position = Vector2(-330, -280)
	_glow(_tut_panel)
	# attach beside the options panel, whatever parent we're in
	get_parent().add_child(_tut_panel)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	_tut_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var txt := Label.new()
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(600, 0)
	txt.add_theme_font_size_override("font_size", 15)
	txt.text = """BREAK THINGS. Left-click smashes crates, ore, aliens. Coins come out. That's the game.

ORES + MONEY -- Follow the yellow arrows on Home to the glowing ring: an open mine shaft. Jump in. Smash the purple blocks (Raw Ingot), use the FURNACE down there (F) to smelt, then buy + place a COINIFIER and mint coins. Other planets have mines too -- richer stuff, no arrows.

HOTBAR -- Everything you buy or craft lands in the 5 slots (1-5 keys, scroll wheel). RIGHT-CLICK uses/places the selected item. Right-click a jetpack to strap it on, a chest to place it, fuel near a rocket to fill it.

JETPACK -- J toggles it. Hold Space to thrust up, C to descend, WASD to steer mid-air. Watch the blue fuel bar; canisters refill +50.

ROCKETS -- Buy one, right-click to place it upright, F to board. Space burns the engine, WASD steers relative to your camera, Z/C rolls, F hops out. Fill fuel BEFORE launching. Arrows + Shift/Ctrl fire RCS if you own the kit. Numbers 1-9,0 warp time while coasting.

PORTALS + BUTTONS -- Tall glowing doorways teleport you (F). Small blocks are buttons/tablets: terminals, trial starters, recipe pickups. Labels tell you which is which.

FOOD -- Knife harvests plants/mushrooms/bananas as items. Eat from the hotbar. Craft a SALAD and wait 3 seconds. You'll see.

DANGER -- Suns burn. The black hole does not let go. Shadow monsters send you somewhere bad. The noodle gods are watching. Do not eat the apple."""
	scroll.add_child(txt)
	var cls := Button.new()
	cls.text = "Close"
	cls.custom_minimum_size = Vector2(0, 40)
	cls.pressed.connect(func() -> void: _tut_panel.visible = false)
	col.add_child(cls)

## Plain opaque menu panel (no glow -- glow is reserved for the in-game HUD).
static func _glow(c: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#141420")
	sb.border_color = Color("#3a3a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	c.add_theme_stylebox_override("panel", sb)
