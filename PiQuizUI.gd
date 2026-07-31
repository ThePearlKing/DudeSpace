class_name PiQuizUI
extends CanvasLayer
## THE PI SHRINE. Recite pi digit by digit from memory. Each correct digit
## pays your current streak in coins (it adds up FAST). Every 10 digits:
## an ultima crystal. One mistake: pain, and you start over from 3.

const PI_DIGITS := "1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679"

var _streak: int = 0
var _best: int = 0
var _shown: Label
var _status: Label
var _title: Label

func _ready() -> void:
	layer = 24
	visible = false
	add_to_group("closable_ui")
	add_to_group("pi_quiz")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 400)
	panel.size = Vector2(520, 400)
	panel.position = Vector2(-260, -200)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#160f04")
	sb.border_color = Color("#ff8c1a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(24, 18)
	panel.add_child(col)

	_title = Label.new()
	_title.text = "THE PI SHRINE"
	_title.add_theme_font_size_override("font_size", 26)
	_title.modulate = Color("#ff8c1a")
	col.add_child(_title)

	var rules := Label.new()
	rules.text = "Recite pi. Each digit pays 5x your streak in coins.\nEvery 10: 2 ULTIMA. Every 25: 4 semicircles. All 100: 25 PRISM.\nMiss once: ouch, start over. The worms know you're busy."
	rules.add_theme_font_size_override("font_size", 13)
	rules.modulate = Color(1, 1, 1, 0.7)
	col.add_child(rules)

	_shown = Label.new()
	_shown.add_theme_font_size_override("font_size", 24)
	_shown.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_shown.custom_minimum_size = Vector2(470, 90)
	col.add_child(_shown)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for d in 10:
		var digit := d
		var b := Button.new()
		b.text = str(d)
		b.custom_minimum_size = Vector2(84, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.mouse_entered.connect(func() -> void: b.modulate = Color(1.25, 1.25, 1.25))
		b.mouse_exited.connect(func() -> void: b.modulate = Color(1, 1, 1))
		b.pressed.connect(func() -> void: _guess(digit))
		grid.add_child(b)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	col.add_child(_status)

	var close := Button.new()
	close.text = "Walk away"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_ui)
	col.add_child(close)

func open() -> void:
	visible = true
	_streak = 0
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_refresh()
	Sfx.play("click")

func close_ui() -> void:
	visible = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh() -> void:
	_shown.text = "3." + PI_DIGITS.substr(0, _streak) + " _"
	_status.text = "streak %d  ·  next digit pays %d coins  ·  best this visit: %d" % [
		_streak, (_streak + 1) * 5, _best]

func _guess(d: int) -> void:
	if _streak >= PI_DIGITS.length():
		_status.text = "you have exhausted the shrine's memory. go outside."
		return
	if str(d) == PI_DIGITS[_streak]:
		_streak += 1
		_best = maxi(_best, _streak)
		Inventory.add_coins(_streak * 5)
		Sfx.play("coin", -16.0)
		var hud := get_tree().get_first_node_in_group("hud")
		if _streak % 10 == 0:
			Inventory.give("ultima", 2)
			Sfx.play("learn")
			if hud:
				hud.flash("+2 ULTIMA")
		if _streak % 25 == 0:
			Inventory.give("semicircle", 4)
			if hud:
				hud.flash("+4 SEMICIRCLES")
		if _streak >= PI_DIGITS.length():
			Inventory.give("prism", 25)
			Sfx.play("learn")
			if hud:
				hud.flash("100 DIGITS: +25 PRISM")
	else:
		Game.hurt(10.0)
		Sfx.play("denied")
		_streak = 0
		_status.text = "WRONG. the shrine disapproves. from the top."
		_shown.text = "3. _"
		return
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# type the digits straight from the keyboard
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_guess(event.keycode - KEY_0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()
