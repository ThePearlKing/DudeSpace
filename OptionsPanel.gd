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

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func(): closed.emit())
	col.add_child(back)

var _tut_panel: PanelContainer

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
