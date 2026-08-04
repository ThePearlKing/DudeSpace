class_name RadioUI
extends CanvasLayer
## The dish map: the whole universe from above, your radio, where the
## dish points, every station's body (and the noodle god). RIGHT-CLICK
## anything to swing the dish onto it. The frequency panel rides on top
## so you never have to leave the map to tune.

var radio = null
var _map: Control
var _spec: Control
var _freq_lbl: Label
var _slider: HSlider
var _act_box: VBoxContainer

const BG := Color("#14161c")
const NEON := Color("#7be8ff")

func _ready() -> void:
	layer = 20
	add_to_group("radio_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Panel.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = BG
	st.border_color = NEON.darkened(0.5)
	st.set_border_width_all(2)
	root.add_theme_stylebox_override("panel", st)
	add_child(root)
	var title := Label.new()
	title.text = "📡  DISH MAP — left-click a body to lock on · right-click to free-aim · ESC closes"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", NEON)
	title.position = Vector2(24, 12)
	root.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-56, 12)
	x.custom_minimum_size = Vector2(44, 44)
	x.pressed.connect(close)
	root.add_child(x)

	_map = Control.new()
	_map.anchor_left = 0.02
	_map.anchor_top = 0.09
	_map.anchor_right = 0.98
	_map.anchor_bottom = 0.72
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_map_input)
	root.add_child(_map)

	# frequency panel ON TOP of the map, bottom strip
	var strip := Panel.new()
	strip.anchor_left = 0.02
	strip.anchor_top = 0.74
	strip.anchor_right = 0.98
	strip.anchor_bottom = 0.97
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("#1a1d24")
	ss.border_color = NEON.darkened(0.6)
	ss.set_border_width_all(1)
	strip.add_theme_stylebox_override("panel", ss)
	root.add_child(strip)
	var col := HBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 16)
	strip.add_child(col)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(700, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(left)
	_freq_lbl = Label.new()
	_freq_lbl.add_theme_font_size_override("font_size", 24)
	_freq_lbl.add_theme_color_override("font_color", NEON)
	left.add_child(_freq_lbl)
	_slider = HSlider.new()
	_slider.min_value = 88.0
	_slider.max_value = 108.0
	_slider.step = 0.1
	_slider.custom_minimum_size = Vector2(680, 26)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value = radio.freq if radio else 98.0
	_slider.value_changed.connect(func(v: float) -> void:
		if radio:
			radio.freq = v)
	left.add_child(_slider)
	_spec = Control.new()
	# WIDE: close-together channels need room to read
	_spec.custom_minimum_size = Vector2(680, 96)
	_spec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spec.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spec.draw.connect(_draw_spec)
	left.add_child(_spec)
	var right := VBoxContainer.new()
	col.add_child(right)
	var ah := Label.new()
	ah.text = "ACTIVITY"
	ah.add_theme_font_size_override("font_size", 16)
	ah.add_theme_color_override("font_color", Color("#ffd166"))
	right.add_child(ah)
	_act_box = VBoxContainer.new()
	right.add_child(_act_box)

func close() -> void:
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- map

func _map_scale() -> float:
	var m := 1000.0
	for b in Universe.bodies:
		m = maxf(m, maxf(absf(b.center.x), absf(b.center.z)))
	return m * 1.06

func _to_px(world: Vector3) -> Vector2:
	var sc := _map_scale()
	var half := _map.size * 0.5
	return half + Vector2(world.x / sc, world.z / sc) * half

func _draw_map() -> void:
	if radio == null or not is_instance_valid(radio):
		return
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), Color("#0c0e14"))
	# bodies
	for b in Universe.bodies:
		if b.name == "interior":
			continue
		var px := _to_px(b.center)
		var r: float = clampf(float(b.radius) / _map_scale() * _map.size.x * 0.5, 2.0, 14.0)
		_map.draw_circle(px, r, Color(b.color.r, b.color.g, b.color.b, 0.9))
		# stations pulse
		for st in radio.stations:
			if st["body"] == b:
				var pulse := 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.004)
				_map.draw_arc(px, r + 4.0 + pulse * 3.0, 0, TAU, 24,
					NEON if str(st["type"]) != "alien" else Color("#ff66aa"), 1.5)
		if b.radius > 100.0 or b.name in ["Earth", "Wth", "Home"]:
			_map.draw_string(ThemeDB.fallback_font, px + Vector2(6, -6), b.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
	# the noodle god
	var w = get_tree().get_first_node_in_group("noodle_watcher")
	if w != null and w is Node3D:
		var np := _to_px(w.global_position)
		# the god parks WAY out past the planets: pin it to the map edge
		# and draw it COSMIC -- eye and tangle, bigger than any planet dot
		np = np.clamp(Vector2(40, 40), _map.size - Vector2(40, 40))
		for k in 5:
			_map.draw_arc(np, 24.0 + float(k) * 6.0, float(k) * 1.2,
				float(k) * 1.2 + TAU * 0.62, 28,
				Color(1.0, 0.81, 0.25, 0.45 - float(k) * 0.07), 2.0)
		_map.draw_circle(np, 18.0, Color(0.95, 0.9, 0.83, 0.92))
		_map.draw_circle(np, 8.0, Color(0.06, 0.04, 0.01))
		_map.draw_arc(np, 12.5, 0, TAU, 28, Color("#c89020"), 2.5)
		_map.draw_string(ThemeDB.fallback_font, np + Vector2(-38, 66), "noodle god",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffcf40"))
	# the radio + the dish's pointing line
	var rp := _to_px(radio.global_position)
	_map.draw_circle(rp, 4.0, Color("#7bffb0"))
	var aim2 := Vector2(radio.aim_dir.x, radio.aim_dir.z)
	if aim2.length() > 0.05:
		# the map stretches x and z by DIFFERENT amounts (widescreen fit);
		# stretch the beam the same way or it points beside its target
		var halfm := _map.size * 0.5
		var an := Vector2(aim2.x * halfm.x, aim2.y * halfm.y).normalized()
		# the BEAM: the actual ~5-degree pencil the dish can hear
		var reach := _map.size.length()
		var la := an.rotated(0.045)
		var ra := an.rotated(-0.045)
		_map.draw_colored_polygon(PackedVector2Array([
			rp, rp + la * reach, rp + ra * reach]),
			Color(0.48, 1.0, 0.69, 0.10))
		_map.draw_line(rp, rp + la * reach, Color(0.48, 1.0, 0.69, 0.3), 1.0)
		_map.draw_line(rp, rp + ra * reach, Color(0.48, 1.0, 0.69, 0.3), 1.0)
		var tip := rp + an * 200.0
		_map.draw_line(rp, tip, Color("#7bffb0"), 2.5)
		var perp := Vector2(-an.y, an.x)
		_map.draw_colored_polygon(PackedVector2Array([
			tip + an * 10.0, tip + perp * 5.0, tip - perp * 5.0]),
			Color("#7bffb0"))
	_map.draw_string(ThemeDB.fallback_font, rp + Vector2(6, 12), "radio",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#7bffb0"))

func _map_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		# LEFT: select a body (or the god) and lock the dish onto it
		var best = null
		var bd := 40.0
		for b in Universe.bodies:
			if b.name == "interior":
				continue
			var d: float = _to_px(b.center).distance_to(event.position)
			if d < bd:
				bd = d
				best = b
		var w = get_tree().get_first_node_in_group("noodle_watcher")
		if w != null and w is Node3D \
				and _to_px(w.global_position).distance_to(event.position) < bd:
			radio.track_body = null
			radio.track_node = w   # the dish follows the god around
			Sfx.play("click", -14.0)
			return
		if best != null:
			radio.track_node = null
			radio.track_body = best   # follow the planet as it moves
			radio.aim_at(best.center)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		# RIGHT: free-aim -- point the dish at the clicked spot on the map
		var sc := _map_scale()
		var half := _map.size * 0.5
		var rel: Vector2 = (event.position - half) / half
		var world := Vector3(rel.x * sc, radio.global_position.y, rel.y * sc)
		radio.track_body = null
		radio.track_node = null
		radio.aim_dir = (world - radio.global_position).normalized()
		Sfx.play("click", -18.0)

# ----------------------------------------------------------- spectrum

func _draw_spec() -> void:
	if radio == null or not is_instance_valid(radio):
		return
	var sz := _spec.size
	_spec.draw_rect(Rect2(Vector2.ZERO, sz), Color("#0c0e14"))
	for st in radio.stations:
		var a: float = radio.align_for(st)
		if a <= 0.02:
			continue
		var x := (float(st["freq"]) - 88.0) / 20.0 * sz.x
		var h := a * (sz.y - 8.0)
		var col: Color = NEON if radio.signal_for(st) > 0.3 else Color("#ffd166")
		_spec.draw_rect(Rect2(Vector2(x - 2, sz.y - h), Vector2(4, h)), col)
		# name the source ON the bar: know which planet is which song
		_spec.draw_string(ThemeDB.fallback_font,
			Vector2(clampf(x - 28.0, 2.0, sz.x - 80.0), maxf(sz.y - h - 3.0, 10.0)),
			str(st["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	# the needle
	var nx: float = (float(radio.freq) - 88.0) / 20.0 * _spec.size.x
	_spec.draw_line(Vector2(nx, 0), Vector2(nx, sz.y), Color("#ff5964"), 2.0)
	_spec.draw_string(ThemeDB.fallback_font, Vector2(2, 12), "88",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	_spec.draw_string(ThemeDB.fallback_font, Vector2(sz.x - 24, 12), "108",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))

func _process(_d: float) -> void:
	if radio == null or not is_instance_valid(radio):
		close()
		return
	_map.queue_redraw()
	_spec.queue_redraw()
	_freq_lbl.text = "%.1f MHz%s" % [radio.freq,
		"" if radio.powered else "   ·   NO POWER"]
	# activity rows: aligned stations you aren't tuned to
	for c in _act_box.get_children():
		c.queue_free()
	for st in radio.stations:
		if radio.align_for(st) > 0.4 and absf(radio.freq - float(st["freq"])) > 0.3:
			var l := Label.new()
			l.text = "%.1f MHz — %s" % [float(st["freq"]), str(st["name"])]
			_act_box.add_child(l)
