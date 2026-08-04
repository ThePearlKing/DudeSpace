class_name NeuralinkUI
extends CanvasLayer
## The Neuralink screen. Dark gray, one X button, zero ethics review.
##
## Browse mode: every chipped human and animal, one button each.
## Control mode:
##   LEFT  -- their eyes (live view) + mind control. Click the view to
##            take the wheel: WASD walks them, P (or click) punches,
##            the chip auto-talks for them. Escape releases focus so
##            the mouse can use the right panel. X closes everything.
##   RIGHT -- their brain. Humans: the face, personality sliders that
##            rewrite the soul (and re-pick the matching face), then
##            friends and enemies with face icons. Animals: the dials
##            an animal has.

var target = null            # EarthHuman or Animal
var _focus := false          # mind-control focus: WASD captured
var _vp: SubViewport
var _cam: Camera3D
var _root: Panel
var _browse: VBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _face_rect: TextureRect
var _talk_t := 6.0
var _hint: Label
var _orbit := 0.0            # right-drag camera spin around the puppet
var _rmb := false
var _vitals: Label

const NEON := Color("#7bffb0")
const DIM := Color("#9aa3ad")

func _ready() -> void:
	layer = 20
	add_to_group("neuralink_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#191a1f")
	st.border_color = NEON.darkened(0.45)
	st.set_border_width_all(2)
	_root.add_theme_stylebox_override("panel", st)
	add_child(_root)
	# the wordmark: glowing, clinical, faintly menacing
	var wm := Label.new()
	wm.text = "◉  N E U R A L I N K"
	wm.add_theme_font_size_override("font_size", 30)
	wm.add_theme_color_override("font_color", NEON)
	wm.position = Vector2(28, 14)
	_root.add_child(wm)
	var sub := Label.new()
	sub.text = "remote cognition console  ·  v0.β  ·  ESC to leave"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", DIM)
	sub.position = Vector2(30, 52)
	_root.add_child(sub)
	var x := Button.new()
	x.text = "✕"
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-60, 14)
	x.custom_minimum_size = Vector2(46, 46)
	_style_btn(x)
	x.pressed.connect(close)
	_root.add_child(x)
	_show_browse()

func _style_btn(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color("#22242b")
	n.border_color = NEON.darkened(0.35)
	n.set_border_width_all(1)
	n.set_corner_radius_all(4)
	n.set_content_margin_all(8)
	var h := n.duplicate()
	h.bg_color = Color("#2c3038")
	h.border_color = NEON
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", NEON)
	b.add_theme_color_override("font_hover_color", Color.WHITE)

func _header(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", NEON)
	return l

## ---------- browse ----------

func _show_browse() -> void:
	_release_target()
	if _browse:
		_browse.queue_free()
	_browse = VBoxContainer.new()
	_browse.set_anchors_preset(Control.PRESET_CENTER)
	_browse.custom_minimum_size = Vector2(480, 0)
	_root.add_child(_browse)
	var title := Label.new()
	title.text = "CONNECTED MINDS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", NEON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browse.add_child(title)
	var n := 0
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h is EarthHuman and h.chipped:
			var b := Button.new()
			b.text = "◉  %s   ·   human" % h.human_name
			_style_btn(b)
			b.pressed.connect(select_target.bind(h))
			_browse.add_child(b)
			n += 1
	for a in get_tree().get_nodes_in_group("animal"):
		if a is Animal and a.get_meta("chipped", false):
			var b2 := Button.new()
			b2.text = "◉  critter   ·   animal"
			_style_btn(b2)
			b2.pressed.connect(select_target.bind(a))
			_browse.add_child(b2)
			n += 1
	if n == 0:
		var none := Label.new()
		none.text = "no chipped minds on the network.\ninstall chips (right-click near a head)."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_browse.add_child(none)

## ---------- control ----------

func select_target(t) -> void:
	if _browse:
		_browse.queue_free()
		_browse = null
	target = t
	target.minded = true
	target.mind_dir = Vector3.ZERO
	_orbit = 0.0
	if target is EarthHuman:
		target._release_seat()
		target._end_convo()
		target._hunt_t = 0.0
		target._target = null
		target._travel_to = -1
	_focus = true

	_left = VBoxContainer.new()
	_left.anchor_left = 0.02
	_left.anchor_top = 0.08
	_left.anchor_right = 0.55
	_left.anchor_bottom = 0.97
	_root.add_child(_left)
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks LAND here
	vc.gui_input.connect(_view_input)
	_left.add_child(vc)
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vc.add_child(_vp)
	_vp.world_3d = get_viewport().world_3d
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_left.add_child(_hint)
	var back := Button.new()
	back.text = "◂ all minds"
	_style_btn(back)
	back.pressed.connect(_show_browse)
	_left.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.58
	scroll.anchor_top = 0.08
	scroll.anchor_right = 0.96
	scroll.anchor_bottom = 0.97
	_root.add_child(scroll)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right)
	if target is EarthHuman:
		_build_human_brain()
	else:
		_build_animal_brain()

func _release_target() -> void:
	if target != null and is_instance_valid(target):
		target.minded = false
		target.mind_dir = Vector3.ZERO
	target = null
	_focus = false
	if _left:
		_left.queue_free()
		_left = null
	if _right:
		var sc := _right.get_parent()
		_right = null
		if sc:
			sc.queue_free()

func _other_ui_open() -> bool:
	# an inventory / storage / machine screen under us still needs the
	# mouse -- don't yank it back into capture on top of them
	for grp in ["storage_ui", "machine_ui"]:
		var n = get_tree().get_first_node_in_group(grp)
		if n != null and n is CanvasItem and n.visible:
			return true
	return false

func close() -> void:
	_release_target()
	queue_free()
	if not Game.dead and not _other_ui_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## ---------- the human brain panel ----------

func _build_human_brain() -> void:
	var t: EarthHuman = target
	var head := Label.new()
	head.text = "%s — BRAIN" % t.human_name
	head.add_theme_font_size_override("font_size", 22)
	_right.add_child(head)
	_vitals = Label.new()
	_vitals.add_theme_font_size_override("font_size", 15)
	_vitals.add_theme_color_override("font_color", NEON)
	_right.add_child(_vitals)
	_face_rect = TextureRect.new()
	_face_rect.custom_minimum_size = Vector2(128, 128)
	_face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var fc := EarthHuman.face_by_file(str(t.saved.get("face", "")))
	_face_rect.texture = fc.get("tex", null)
	_right.add_child(_face_rect)
	var plabel := Label.new()
	plabel.text = "PERSONALITY (rewriting live)"
	_right.add_child(plabel)
	for ax in EarthHuman.AXES:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = ax
		l.custom_minimum_size = Vector2(100, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.value = float(t._pers.get(ax, 25.0))
		s.custom_minimum_size = Vector2(200, 20)
		s.value_changed.connect(_on_axis.bind(ax))
		row.add_child(s)
		_right.add_child(row)
	var vhead := Label.new()
	vhead.text = "VOICE"
	vhead.add_theme_font_size_override("font_size", 18)
	_right.add_child(vhead)
	var vp2: Dictionary = t._voice
	var vary := float(vp2.get("var", 0.4))
	var vl := Label.new()
	vl.text = "  pitch: %.0f Hz\n  spread: %.2f%s\n  waveform: %s\n  speed: %.2fx\n  articulation: %.2fx" % [
		float(vp2.get("base", 300.0)), vary,
		" (monotone)" if vary < 0.1 else "",
		str(vp2.get("wave", "sine")), float(vp2.get("rate", 1.0)),
		float(vp2.get("artic", 1.0))]
	_right.add_child(vl)
	_right.add_child(_roster("FRIENDS", 40.0, true))
	_right.add_child(_roster("ENEMIES", -30.0, false))

func _on_axis(v: float, ax: String) -> void:
	if not (target is EarthHuman) or not is_instance_valid(target):
		return
	target._pers[ax] = v
	target.saved["pers"] = target._pers
	# the face IS the soul: find the pool face that best matches the
	# rewritten personality and put it on
	var best: Dictionary = {}
	var bd := 1e18
	for fc in EarthHuman._faces:
		var d := 0.0
		var fp: Dictionary = fc.get("pers", {})
		for a2 in EarthHuman.AXES:
			d += absf(float(fp.get(a2, 25.0)) - float(target._pers[a2]))
		if d < bd:
			bd = d
			best = fc
	if not best.is_empty():
		target.saved["face"] = str(best.get("file", ""))
		if target._body:
			target._body.set_face(best.get("tex", null))
		if _face_rect:
			_face_rect.texture = best.get("tex", null)

## Friends or enemies of the target, with face icons: skin, face, hair.
func _roster(title: String, cutoff: float, above: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 18)
	box.add_child(l)
	var t: EarthHuman = target
	var found := 0
	for h in get_tree().get_nodes_in_group("earth_human"):
		if not (h is EarthHuman) or h == t:
			continue
		var op := t._op(h.human_id)
		if (above and op > cutoff) or (not above and op < cutoff):
			box.add_child(_face_row(h, op))
			found += 1
	if found == 0:
		var none := Label.new()
		none.text = "  (nobody)"
		box.add_child(none)
	return box

func _face_row(h: EarthHuman, op: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(30, 30)
	var skin := ColorRect.new()
	skin.color = Color(str(h.saved.get("skin", "b58a6a")))
	skin.size = Vector2(26, 26)
	skin.position = Vector2(2, 2)
	icon.add_child(skin)
	var fc := EarthHuman.face_by_file(str(h.saved.get("face", "")))
	if fc.has("tex"):
		var fr := TextureRect.new()
		fr.texture = fc["tex"]
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.size = Vector2(26, 26)
		fr.position = Vector2(2, 2)
		icon.add_child(fr)
	var hair := ColorRect.new()
	hair.color = Color(str(h.saved.get("hair_col", "1a1410")))
	hair.size = Vector2(26, 6)
	hair.position = Vector2(2, 0)
	icon.add_child(hair)
	row.add_child(icon)
	var l := Label.new()
	# exact ledger, both directions: how the target rates them, and
	# how they rate the target back
	l.text = "%s   %+.1f  (they: %+.1f)" % [h.human_name, op,
		h._op((target as EarthHuman).human_id) if target is EarthHuman else 0.0]
	row.add_child(l)
	return row

## ---------- the animal brain panel ----------

func _build_animal_brain() -> void:
	var a: Animal = target
	var head := Label.new()
	head.text = "SPECIMEN — BRAIN (smooth)"
	head.add_theme_font_size_override("font_size", 22)
	_right.add_child(head)
	var hrow := HBoxContainer.new()
	var hl := Label.new()
	hl.text = "health"
	hl.custom_minimum_size = Vector2(100, 0)
	hrow.add_child(hl)
	var hs := HSlider.new()
	hs.min_value = 1
	hs.max_value = 60
	hs.value = a.hp
	hs.custom_minimum_size = Vector2(200, 20)
	hs.value_changed.connect(func(v: float) -> void:
		if is_instance_valid(a):
			a.hp = v)
	hrow.add_child(hs)
	_right.add_child(hrow)
	var tame := CheckBox.new()
	tame.text = "tamed (loyal to the blue dude)"
	tame.button_pressed = a.tamed
	tame.toggled.connect(func(on: bool) -> void:
		if is_instance_valid(a) and on and not a.tamed:
			a.tame())
	_right.add_child(tame)
	var note := Label.new()
	note.text = "friends: all of them\nenemies: none. it's an animal."
	_right.add_child(note)

## ---------- input + drive loop ----------

func _view_input(event: InputEvent) -> void:
	# no focus dance: LEFT click on the view punches, RIGHT drag spins
	# the camera around the puppet. WASD just always works.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
				and target is EarthHuman:
			target.mind_punch()
	elif event is InputEventMouseMotion and _rmb:
		_orbit += event.relative.x * 0.01

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_P and target != null and target is EarthHuman:
			target.mind_punch()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		if target != null:
			_show_browse()
		return
	# steering is always live: W/S along their facing, A/D STRAFE,
	# Q/E turns the facing itself
	var fwd: Vector3 = -target.global_transform.basis.z
	var right: Vector3 = target.global_transform.basis.x
	var d := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		d += fwd
	if Input.is_key_pressed(KEY_S):
		d -= fwd
	if Input.is_key_pressed(KEY_A):
		d -= right
	if Input.is_key_pressed(KEY_D):
		d += right
	target.mind_dir = d.normalized() if d.length() > 0.1 else Vector3.ZERO
	if target is EarthHuman:
		target.mind_turn = (2.6 if Input.is_key_pressed(KEY_Q) else 0.0) \
			- (2.6 if Input.is_key_pressed(KEY_E) else 0.0)
	if _hint:
		_hint.text = "▶ LINKED — WASD move (A/D strafe) · Q/E turn · click/P punch · right-drag spin · ESC leave"
		_hint.add_theme_color_override("font_color", NEON)
	if _vitals and target is EarthHuman:
		_vitals.text = "VITALS   hp %.0f / 30   ·   age %.0f%% of a life" % [
			maxf(0.0, target.hp), target.age / maxf(1.0, target.lifespan) * 100.0]
	# third person: hover behind and above, right-drag orbits
	var up: Vector3 = target.global_transform.basis.y
	var back2: Vector3 = target.global_transform.basis.z.rotated(
		target.global_transform.basis.y, _orbit)
	_cam.global_position = target.global_position + up * 2.3 + back2 * 4.4
	_cam.look_at(target.global_position + up * 0.9, up)
	# the chip talks for them
	if target is EarthHuman:
		_talk_t -= delta
		if _talk_t <= 0.0:
			_talk_t = randf_range(5.0, 10.0)
			target.mind_talk()
