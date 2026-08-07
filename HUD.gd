class_name HUD
extends CanvasLayer
## Always-on overlay: money/coins/score, wrath meter, contextual prompts,
## and the two end states (Pythagorean transform, TIN 618 trap).

var _stats: Label
var _health_fill: ColorRect
var _prompt: Label
var _hint: Label
var _over: Label
var _jet_on_shown := false   # last jet state painted (gate relayouts)
var _ride_lbl: Label
var _ride_shown := ""
var _flash: Label
var _flash_t: float = 0.0
var _slots: Array = []       # hotbar cell panels
var _slot_lbls: Array = []
var _slot_cds: Array = []
var _jet_lbl: Label
var _jet_bg: Panel
var _jet_fill: ColorRect
var _buff_lbl: Label

class _WaypointLayer extends Control:
	func _process(_d: float) -> void:
		queue_redraw()

	## Screen point for a world position. Offscreen or behind-camera
	## targets clamp to the screen edge instead of vanishing.
	func _screen_pt(cam: Camera3D, wp: Vector3) -> Vector2:
		var vp := get_viewport_rect().size
		var behind := cam.is_position_behind(wp)
		# a point EXACTLY on the camera plane can't unproject (p.d == 0
		# engine error) -- nudge it a hair forward first
		var rel := (wp - cam.global_position).dot(-cam.global_transform.basis.z)
		if absf(rel) < 0.01:
			wp += -cam.global_transform.basis.z * 0.05
		var sp := cam.unproject_position(wp)
		if behind:
			sp = vp - sp   # unproject mirrors behind the camera: flip back
		var margin := 30.0
		if not behind and sp.x >= margin and sp.y >= margin \
				and sp.x <= vp.x - margin and sp.y <= vp.y - margin:
			return sp
		var c := vp * 0.5
		var d := sp - c
		if d.length() < 0.001:
			d = Vector2(0, -1)
		var kx := (c.x - margin) / absf(d.x) if absf(d.x) > 0.001 else 1e9
		var ky := (c.y - margin) / absf(d.y) if absf(d.y) > 0.001 else 1e9
		return c + d * minf(kx, ky)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var me := cam.global_position
		for w in get_tree().get_nodes_in_group("waypoint"):
			if not (w is Waypoint) or not is_instance_valid(w) or not w.enabled:
				continue
			var wp: Vector3 = w.global_position + Vector3(0, 0.6, 0)
			# a waypoint inside a house/temple interior marks the EXTERIOR
			# spot on the planet -- unless you're in there with it
			if me.distance_to(wp) > 900.0:
				var ext := Zones.exterior_of(wp)
				if ext != wp:
					wp = ext
			var sp := _screen_pt(cam, wp)
			var c: Color = w.col()
			var pts := PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(9, 0),
				sp + Vector2(0, 9), sp + Vector2(-9, 0)])
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.85))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.2, 0.12, 0, 0.9), 1.5)
			var dist := me.distance_to(wp)
			var txt := "%.0f m" % dist if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
			draw_string(ThemeDB.fallback_font, sp + Vector2(12, 4), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.8, 0.8))
		# --- locator pings: bigger GREEN diamonds, time out on their own ---
		if Game.locator_until > Game.playtime:
			var g := Color("#2bff6a")
			for lp_v in Game.locator_targets:
				var lp: Vector3 = lp_v
				var sp2 := _screen_pt(cam, lp)
				var pts2 := PackedVector2Array([sp2 + Vector2(0, -13), sp2 + Vector2(13, 0),
					sp2 + Vector2(0, 13), sp2 + Vector2(-13, 0)])
				draw_polyline(PackedVector2Array([pts2[0], pts2[1], pts2[2], pts2[3], pts2[0]]),
					g, 2.5)
				var d2 := me.distance_to(lp) * Game.locator_lie
				var t2 := "%.0f m" % d2 if d2 < 1000.0 else "%.1f km" % (d2 / 1000.0)
				draw_string(ThemeDB.fallback_font, sp2 + Vector2(16, 4),
					Game.locator_label + "  " + t2,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, g)

func _ready() -> void:
	layer = 10
	add_to_group("hud")

	_stats = Label.new()
	_stats.position = Vector2(30, 26)
	_stats.add_theme_font_size_override("font_size", 22)
	_glow_label(_stats, Color("#ffe066"))
	add_child(_stats)

	var hl := Label.new()
	hl.text = "HEALTH"
	hl.position = Vector2(30, 118)
	hl.add_theme_font_size_override("font_size", 14)
	hl.modulate = Color("#6aff8a")
	_glow_label(hl, Color("#2bff6a"))
	add_child(hl)
	var health_bg := Panel.new()
	health_bg.position = Vector2(30, 138)
	health_bg.size = Vector2(360, 18)
	_glow_panel(health_bg, Color("#2bff6a"))
	add_child(health_bg)
	_health_fill = ColorRect.new()
	_health_fill.position = Vector2(2, 2)
	_health_fill.size = Vector2(356, 14)
	health_bg.add_child(_health_fill)

	_buff_lbl = Label.new()
	_buff_lbl.position = Vector2(400, 138)
	_buff_lbl.add_theme_font_size_override("font_size", 14)
	_buff_lbl.modulate = Color("#8aff9a")
	_glow_label(_buff_lbl, Color("#2bff6a"))
	add_child(_buff_lbl)

	_jet_lbl = Label.new()
	_jet_lbl.text = "JET FUEL"
	_jet_lbl.position = Vector2(30, 162)
	_jet_lbl.add_theme_font_size_override("font_size", 12)
	_jet_lbl.modulate = Color("#7cd8ff")
	add_child(_jet_lbl)
	_jet_bg = Panel.new()
	_jet_bg.position = Vector2(30, 180)
	_jet_bg.size = Vector2(240, 14)
	_glow_panel(_jet_bg, Color("#7cd8ff"))
	add_child(_jet_bg)
	_jet_fill = ColorRect.new()
	_jet_fill.position = Vector2(2, 2)
	_jet_fill.size = Vector2(236, 10)
	_jet_fill.color = Color("#7cd8ff")
	_jet_bg.add_child(_jet_fill)

	_build_hotbar()
	var wl := _WaypointLayer.new()
	wl.set_anchors_preset(Control.PRESET_FULL_RECT)
	wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wl)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-9, -17)
	add_child(cross)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-200, -140)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(30, -60)
	add_child(_hint)

	_flash = Label.new()
	_flash.add_theme_font_size_override("font_size", 34)
	_flash.modulate = Color("#ffe066")
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.position = Vector2(-360, 120)
	_flash.size = Vector2(720, 60)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.visible = false
	add_child(_flash)

	_ride_lbl = Label.new()
	_ride_lbl.anchor_left = 0.3
	_ride_lbl.anchor_right = 0.7
	_ride_lbl.anchor_top = 0.04
	_ride_lbl.anchor_bottom = 0.09
	_ride_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ride_lbl.add_theme_font_size_override("font_size", 16)
	_ride_lbl.add_theme_color_override("font_color", Color("#7cf9ff"))
	_ride_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ride_lbl.add_theme_constant_override("outline_size", 4)
	add_child(_ride_lbl)

	_over = Label.new()
	_over.add_theme_font_size_override("font_size", 40)
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_over.visible = false
	add_child(_over)

	Game.changed.connect(_refresh)
	Game.transformed.connect(_on_transformed)
	Game.killed.connect(_on_killed)
	Game.perma.connect(_on_perma)
	Inventory.changed.connect(_refresh)
	_refresh()

## Minecraft-style hotbar centred along the bottom.
func _build_hotbar() -> void:
	var cell := 62.0
	var gap := 6.0
	var total := 5.0 * cell + 4.0 * gap
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(root)
	for i in 5:
		var cellp := Panel.new()
		cellp.size = Vector2(cell, cell)
		cellp.position = Vector2(-total * 0.5 + float(i) * (cell + gap), -cell - 18.0)
		cellp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		cellp.position = Vector2(-total * 0.5 + float(i) * (cell + gap), -cell - 18.0)
		add_child(cellp)
		_slots.append(cellp)
		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 12)
		num.position = Vector2(4, 2)
		cellp.add_child(num)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.clip_text = true
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cellp.add_child(lbl)
		_slot_lbls.append(lbl)
		# cooldown veil: a dark sheet that drains downward as the
		# weapon comes back
		var cdv := ColorRect.new()
		cdv.color = Color(0, 0, 0, 0.55)
		cdv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cdv.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cdv.visible = false
		cellp.add_child(cdv)
		_slot_cds.append(cdv)

func _slot_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	sb.set_corner_radius_all(4)
	sb.border_color = Color("#ffe066") if selected else Color("#555566")
	sb.set_border_width_all(3 if selected else 1)
	if selected:
		sb.shadow_color = Color(1.0, 0.88, 0.4, 0.5)
		sb.shadow_size = 10
	return sb

## Soft neon glow for HUD text via a coloured outline.
func _glow_label(lbl: Label, glow: Color) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(glow.r, glow.g, glow.b, 0.55))
	lbl.add_theme_constant_override("outline_size", 8)

## Soft glow behind a HUD bar via a coloured stylebox shadow.
func _glow_panel(p: Panel, glow: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(glow.r, glow.g, glow.b, 0.5)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)

# --- SUN ABSORPTION: full-screen fire, fades after you respawn ---
var _fire: ColorRect
var _fire_a: float = 0.0

func sun_fire() -> void:
	_fire_a = 1.0

func _ensure_fire() -> void:
	if _fire:
		return
	_fire = ColorRect.new()
	_fire.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// flames rise: scroll noise upward, stronger near screen edges + bottom
	float n = noise(uv * vec2(6.0, 9.0) + vec2(0.0, -TIME * 2.4));
	n += 0.5 * noise(uv * vec2(13.0, 21.0) + vec2(3.7, -TIME * 4.0));
	float edge = max(1.0 - uv.y, 0.0) * 1.2 + pow(abs(uv.x - 0.5) * 2.0, 2.0) * 0.8 + pow(1.0 - uv.y, 3.0);
	float f = clamp(n * edge * (0.6 + strength), 0.0, 1.0) * strength;
	vec3 col = mix(vec3(0.05, 0.0, 0.0), vec3(1.0, 0.25, 0.02), f);
	col = mix(col, vec3(1.0, 0.9, 0.3), pow(f, 3.0));
	float a = clamp(strength * (0.35 + f), 0.0, 1.0);
	COLOR = vec4(col, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_fire.material = mat
	_fire.visible = false
	add_child(_fire)

var _zone_lbl: Label

## Steady top-centre room indicator ("" hides it).
func set_zone_text(t: String) -> void:
	if _zone_lbl == null:
		_zone_lbl = Label.new()
		_zone_lbl.add_theme_font_size_override("font_size", 30)
		_zone_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_zone_lbl.position = Vector2(-60, 24)
		_zone_lbl.custom_minimum_size = Vector2(120, 0)
		_zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glow_label(_zone_lbl, Color("#b388ff"))
		add_child(_zone_lbl)
	_zone_lbl.text = t
	_zone_lbl.visible = t != ""

var _recipe_pop: PanelContainer

## Big centred "NEW RECIPE" popup. Click / any key closes it.
func recipe_popup(title: String, body: String) -> void:
	if _recipe_pop:
		_recipe_pop.queue_free()
	_recipe_pop = PanelContainer.new()
	_recipe_pop.set_anchors_preset(Control.PRESET_CENTER)
	_recipe_pop.custom_minimum_size = Vector2(420, 170)
	_recipe_pop.position = Vector2(-210, -160)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#141420")
	sb.border_color = Color("#ffd166")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	_recipe_pop.add_theme_stylebox_override("panel", sb)
	add_child(_recipe_pop)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	_recipe_pop.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)
	var t := Label.new()
	t.text = "NEW RECIPE"
	t.add_theme_font_size_override("font_size", 15)
	t.modulate = Color("#ffd166")
	v.add_child(t)
	var n := Label.new()
	n.text = title
	n.add_theme_font_size_override("font_size", 26)
	v.add_child(n)
	var b := Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 13)
	b.modulate = Color(1, 1, 1, 0.7)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(370, 0)
	v.add_child(b)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(0, 36)
	ok.pressed.connect(func() -> void:
		if _recipe_pop:
			_recipe_pop.queue_free()
			_recipe_pop = null)
	v.add_child(ok)
	Sfx.play("learn")

func flash(msg: String) -> void:
	_flash.text = msg
	_flash.visible = true
	_flash_t = 3.0

func _process(delta: float) -> void:
	# fire overlay: holds while dead, melts away after respawn
	if _fire_a > 0.0:
		_ensure_fire()
		if not Game.dead:
			_fire_a = maxf(0.0, _fire_a - delta * 0.7)
		_fire.visible = _fire_a > 0.0
		(_fire.material as ShaderMaterial).set_shader_parameter("strength", _fire_a)
	elif _fire and _fire.visible:
		_fire.visible = false

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false

	# buff icons beside the health bar
	if _buff_lbl:
		var parts: Array = []
		if Game.salad_active():
			parts.append("[🥗 SALAD]")
		if Game.pet_following():
			parts.append("[♥ PET +2%]")
		var bt := "  ".join(parts)
		if _buff_lbl.text != bt:
			_buff_lbl.text = bt   # Label.text writes force relayout: gate them

	# jetpack ON indicator
	# passenger readout: who's flying, and how fast time is going for
	# them. No keybind prompts -- you're cargo.
	var pplayer = get_tree().get_first_node_in_group("player")
	var ride_txt := ""
	if pplayer != null and "riding_peer" in pplayer and pplayer.riding_peer != -1:
		var cs8 = get_tree().current_scene
		var w8 := 1.0
		if cs8 != null and cs8.has_method("peer_warp"):
			w8 = cs8.peer_warp(pplayer.riding_peer)
		ride_txt = "PASSENGER · pilot: %s" \
			% str(Net.player_names.get(pplayer.riding_peer, "?"))
		if w8 > 1.0:
			ride_txt += " · time warp x%d" % int(w8)
	if ride_txt != _ride_shown:
		_ride_shown = ride_txt
		_ride_lbl.text = ride_txt
	if Inventory.has_jetpack:
		var p := get_tree().get_first_node_in_group("player")
		var on: bool = p != null and p.has_method("jetting") and p.jetting()
		if on != _jet_on_shown:
			_jet_on_shown = on
			_jet_lbl.text = "JET FUEL  [ON]" if on else "JET FUEL"
			_jet_lbl.modulate = Color("#5aff8a") if on else Color("#7cd8ff")

	if Game.dead:
		return
	_prompt.text = ""
	if Game.mode == Game.Mode.ON_FOOT:
		_hint.text = "WASD move   L-click fire   R-click use/place   Space jump/jet   C jet down   V zoom   J jetpack   1-5 hotbar   E shop   M map   K calendar   F interact   F3 stats   F5 view"
	else:
		_hint.text = "WASD steer   Space engine   H hyperdrive   arrows RCS   1/2/3/5/0 time warp   L-click smash   F exit   M map"

func _refresh() -> void:
	if not is_inside_tree():
		return
	_stats.text = "COINS  %d   BANK  %d   ZB  %d\nSCORE  %d      %s %s%s" % [
		Inventory.coins, Inventory.bank_coins, Inventory.zeptobux, Game.score,
		Game.date_text(), Game.clock_text(),
		"  ·  UFO IN SYSTEM" if Game.is_ufo_day() else ""]
	var hp := Game.health / Game.HEALTH_MAX
	_health_fill.size.x = 356.0 * hp
	_health_fill.color = Color(1.0 - hp, hp, 0.2)
	var show_jet := Inventory.has_jetpack
	_jet_lbl.visible = show_jet
	_jet_bg.visible = show_jet
	if show_jet:
		_jet_fill.size.x = 236.0 * clampf(Inventory.jet_fuel / Inventory.jet_max, 0.0, 1.0)
	for i in _slots.size():
		_slots[i].add_theme_stylebox_override("panel", _slot_style(i == Inventory.selected))
		_slot_lbls[i].text = Inventory.slot_text(Inventory.hotbar[i])
		# COOLDOWN veil on every weapon except the zapper: the slot
		# darkens after a shot and drains open as the weapon returns
		var wid9 := str(Inventory.hotbar[i]["id"])
		var cdf := 0.0
		if Inventory.weapons.has(wid9) and wid9 != "zapper" \
				and i == Inventory.selected:
			var pl9 = get_tree().get_first_node_in_group("player")
			if pl9 != null and "_cooldown" in pl9:
				cdf = clampf(float(pl9._cooldown) \
					/ maxf(0.05, float(Inventory.weapons[wid9]["rate"])),
					0.0, 1.0)
		var cdv9: ColorRect = _slot_cds[i]
		cdv9.visible = cdf > 0.02
		if cdv9.visible:
			var ph9 := (cdv9.get_parent() as Control).size.y
			cdv9.offset_top = -ph9 * cdf
		_slot_lbls[i].material = Inventory.ench_text_material() \
			if int(Inventory.enchant.get(str(Inventory.hotbar[i]["id"]), 0)) > 0 \
			else null

func _on_killed() -> void:
	_over.visible = true
	_over.modulate = Color("#ff4444")
	_over.text = "KILLED BY %s\n\nscore  %d\n\npress R to respawn" \
		% [Game.death_cause.to_upper(), Game.score]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_transformed() -> void:
	_over.visible = true
	_over.modulate = Color("#ff5aa0")
	_over.text = "YOU ANGERED THE DESTRUCTION NOODLE GODS\n\nyou are now the Pythagorean theorem\n\na² + b² = c²\n\npress R to be reborn"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_perma() -> void:
	_over.visible = true
	_over.modulate = Color("#c0c0ff")
	_over.text = "PERMADEATH\n\nyour save is erased.\n\npress R to return to the title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
