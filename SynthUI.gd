class_name SynthUI
extends CanvasLayer
## THE PATCH EDITOR. The rack, full screen, exactly as it is bolted into
## the case outside: drag a cable from any output to any input, turn the
## knobs, program the sequencers, add and remove modules from three
## different manufacturers. Everything you do here happens to the real
## machine immediately -- the sound, and the cables hanging off its face.
##
## LMB drag a jack -> patch it.      RMB a jack   -> yank the cable.
## LMB drag a knob -> turn it.       RMB a panel  -> module menu.
## LMB drag a panel title -> move it in the rack. Wheel -> zoom.

var synth: ModSynth = null

var _rack: Control
var _status: Label
var _hint: Label
var _pal: VBoxContainer
var _pow: Label
var _menu: PopupMenu
var _swmenu: PopupMenu

var _z: float = 3.1                  # pixels per panel unit
var _pan := Vector2(10, 10)
var _brand: String = "dude"          # what the palette builds
var _cat: String = "ALL"             # palette filter: one kind of module

var _drag := ""                      # "", "knob", "cable", "move", "pan", "step", "gate", "cell", "key"
var _dmod: int = -1
var _di: int = 0
var _dval: float = 0.0
var _dstart := Vector2.ZERO
var _dfrom_out: bool = true
var _hover := {}                     # hit under the cursor
var _core_btns: Array = []
var _undo: Array = []                # patch snapshots, newest last
var _redo: Array = []
const UNDO_MAX := 60
var _menu_mod: int = -1
var _menu_sw: int = -1

const BG := Color("#0b0d11")
## Width of the top-right button row: 128+128+96+112+72+132+40 of buttons
## plus the separations between them, with a little air.
const BAR_W := 736.0
const NEON := Color("#7be8ff")

func _ready() -> void:
	layer = 20
	add_to_group("synth_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Panel.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var stb := StyleBoxFlat.new()
	stb.bg_color = BG
	stb.border_color = NEON.darkened(0.6)
	stb.set_border_width_all(2)
	root.add_theme_stylebox_override("panel", stb)
	add_child(root)

	# ------------------------------------------------------------ top bar
	var top := Panel.new()
	top.anchor_right = 1.0
	top.offset_bottom = 54
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("#141821")
	top.add_theme_stylebox_override("panel", tsb)
	root.add_child(top)
	var title := Label.new()
	title.text = "MODULAR SYNTHESIZER" + ("  MK2" if synth != null and synth.mk2 else "")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", NEON)
	title.position = Vector2(18, 12)
	top.add_child(title)
	_pow = Label.new()
	_pow.add_theme_font_size_override("font_size", 14)
	_pow.position = Vector2(268, 8)
	_pow.custom_minimum_size = Vector2(340, 40)
	_pow.clip_text = true
	top.add_child(_pow)
	# pinned to the right edge by ANCHORS, not by a guessed offset: the row
	# is wider than the old -690 allowed for, so the cable slider and the
	# close button were being pushed off the side of the screen
	var bx := HBoxContainer.new()
	bx.anchor_left = 1.0
	bx.anchor_right = 1.0
	bx.offset_left = -BAR_W
	bx.offset_right = -12.0
	bx.offset_top = 9.0
	bx.offset_bottom = 45.0
	top.add_child(bx)
	for spec in [["ULTIMA CORE", "ultima"], ["URANIUM CELL", "uranium"]]:
		var bb := Button.new()
		bb.text = str(spec[0])
		bb.custom_minimum_size = Vector2(128, 34)
		bb.pressed.connect(_toggle_core.bind(str(spec[1])))
		bb.set_meta("core", str(spec[1]))
		bx.add_child(bb)
		_core_btns.append(bb)
	var initb := Button.new()
	initb.text = "INIT PATCH"
	initb.custom_minimum_size = Vector2(96, 34)
	initb.pressed.connect(func() -> void:
		_snap("init patch")
		synth.engine.default_patch()
		_flash("rack reset to the factory patch"))
	bx.add_child(initb)
	var unp := Button.new()
	unp.text = "UNPATCH ALL"
	unp.custom_minimum_size = Vector2(112, 34)
	unp.pressed.connect(func() -> void:
		var n := synth.engine.cables.size()
		_snap("unpatch all")
		synth.engine.clear_cables()
		Sfx.play("click", -10.0)
		_flash("%d cables pulled — the rack keeps its modules" % n))
	bx.add_child(unp)
	var clr := Button.new()
	clr.text = "CLEAR"
	clr.custom_minimum_size = Vector2(72, 34)
	clr.pressed.connect(func() -> void:
		_snap("clear rack")
		synth.engine.clear_patch()
		_flash("rack emptied"))
	bx.add_child(clr)
	# how solid the cables are drawn -- a full rack disappears under its
	# own cabling otherwise. Saved with your settings, not the world.
	var cab := VBoxContainer.new()
	cab.custom_minimum_size = Vector2(132, 34)
	var cablbl := Label.new()
	cablbl.text = "CABLES  %d%%" % int(Settings.cable_alpha * 100.0)
	cablbl.add_theme_font_size_override("font_size", 11)
	cablbl.add_theme_color_override("font_color", Color("#8fa8b8"))
	cab.add_child(cablbl)
	var cabsl := HSlider.new()
	cabsl.min_value = 0.12
	cabsl.max_value = 1.0
	cabsl.step = 0.02
	cabsl.value = Settings.cable_alpha
	cabsl.custom_minimum_size = Vector2(132, 16)
	cabsl.value_changed.connect(func(v: float) -> void:
		Settings.cable_alpha = v
		cablbl.text = "CABLES  %d%%" % int(v * 100.0)
		Settings.save_cfg())
	cab.add_child(cabsl)
	bx.add_child(cab)
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(40, 34)
	x.pressed.connect(close)
	bx.add_child(x)

	# ------------------------------------------------------------ palette
	var side := Panel.new()
	side.anchor_bottom = 1.0
	side.offset_top = 54
	side.offset_right = 236
	side.offset_bottom = -46
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color("#10141c")
	side.add_theme_stylebox_override("panel", ssb)
	root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.add_child(scroll)
	_pal = VBoxContainer.new()
	_pal.custom_minimum_size = Vector2(220, 0)
	_pal.add_theme_constant_override("separation", 2)
	scroll.add_child(_pal)
	_build_palette()

	# ------------------------------------------------------------ the rack
	_rack = Control.new()
	_rack.anchor_right = 1.0
	_rack.anchor_bottom = 1.0
	_rack.offset_left = 240
	_rack.offset_top = 54
	_rack.offset_bottom = -46
	_rack.clip_contents = true
	_rack.draw.connect(_draw_rack)
	_rack.gui_input.connect(_rack_input)
	_rack.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_rack)

	# ---------------------------------------------------------- bottom bar
	var bot := Panel.new()
	bot.anchor_top = 1.0
	bot.anchor_right = 1.0
	bot.anchor_bottom = 1.0
	bot.offset_top = -46
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#141821")
	bot.add_theme_stylebox_override("panel", bsb)
	root.add_child(bot)
	_hint = Label.new()
	_hint.position = Vector2(16, 4)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("#8fa8b8"))
	_hint.text = "right-click a knob to TYPE a value · Ctrl+Z undoes · drag EITHER END of a patched cable to move it (SHIFT+drag a used output for a second cable) · drag a cable by its middle to move that end · drop on empty rack to bin it · drag OUT jack → IN jack to patch · grab a cable anywhere to re-route it, drop it on empty rack to bin it · RMB a jack or cable yanks it · RMB a panel for its menu · drag a title to move it · wheel zooms · ESC closes"
	bot.add_child(_hint)
	_status = Label.new()
	_status.position = Vector2(16, 24)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("#ffd166"))
	bot.add_child(_status)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_menu_pick)
	add_child(_menu)
	_swmenu = PopupMenu.new()
	_swmenu.id_pressed.connect(_swmenu_pick)
	add_child(_swmenu)

## The palette: manufacturer at the top, then a filter so you can ask
## for one kind of module -- every modulator, every clock -- instead of
## scrolling the whole catalogue.
const CAT_LABEL := {
	"ALL": "EVERYTHING", "INPUT": "CONTROLLERS", "SOURCE": "SOUND SOURCES",
	"MODULATE": "MODULATORS", "FILTER": "FILTERS", "PROCESS": "PROCESSORS",
	"CLOCK": "CLOCKS", "LOGIC": "LOGIC", "SEQUENCE": "SEQUENCERS",
	"FX": "EFFECTS", "VISUAL": "VISUALISERS", "UTILITY": "UTILITIES",
}

func _build_palette() -> void:
	for c in _pal.get_children():
		c.queue_free()
	var bl := Label.new()
	bl.text = "  MANUFACTURER"
	bl.add_theme_font_size_override("font_size", 13)
	bl.add_theme_color_override("font_color", Color("#8fa8b8"))
	_pal.add_child(bl)
	for b in SynthMods.BRANDS:
		var stl := SynthMods.brand_style(b)
		var bt := Button.new()
		bt.text = ("● " if b == _brand else "○ ") + str(stl["name"])
		bt.tooltip_text = str(stl["blurb"])
		bt.custom_minimum_size = Vector2(214, 30)
		bt.add_theme_color_override("font_color", stl["trim"])
		bt.pressed.connect(func() -> void:
			_brand = b
			_build_palette()
			_flash("new modules will be built by %s" % str(stl["name"])))
		_pal.add_child(bt)
	var fl := Label.new()
	fl.text = "  SHOW"
	fl.add_theme_font_size_override("font_size", 13)
	fl.add_theme_color_override("font_color", Color("#8fa8b8"))
	_pal.add_child(fl)
	var cats: Array = ["ALL"]
	for g in SynthMods.groups():
		cats.append(g)
	for cg in cats:
		var count := 0
		for id0 in SynthMods.ids():
			var d0 := SynthMods.def(id0)
			var only0 := SynthMods.exclusive_to(id0)
			if only0 != "" and only0 != _brand:
				continue
			if cg == "ALL" or str(d0["grp"]) == cg:
				count += 1
		var cb := Button.new()
		cb.text = "%s %s  (%d)" % ["▸" if cg == _cat else " ",
			str(CAT_LABEL.get(cg, cg)), count]
		cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cb.custom_minimum_size = Vector2(214, 26)
		cb.add_theme_color_override("font_color",
			NEON if cg == _cat else Color("#8fa8b8"))
		cb.pressed.connect(func() -> void:
			_cat = cg
			_build_palette())
		_pal.add_child(cb)
	var sep := Label.new()
	sep.text = ""
	_pal.add_child(sep)
	for g in SynthMods.groups():
		if _cat != "ALL" and g != _cat:
			continue
		var rows: Array = []
		for id in SynthMods.ids():
			var d := SynthMods.def(id)
			if str(d["grp"]) != g:
				continue
			var only := SynthMods.exclusive_to(id)
			if only != "" and only != _brand:
				continue
			rows.append(id)
		if rows.is_empty():
			continue
		var hl := Label.new()
		hl.text = "  " + str(CAT_LABEL.get(g, g))
		hl.add_theme_font_size_override("font_size", 13)
		hl.add_theme_color_override("font_color", NEON.darkened(0.2))
		_pal.add_child(hl)
		for id in rows:
			var d2 := SynthMods.def(id)
			var b2 := Button.new()
			b2.text = ("★ " if SynthMods.exclusive_to(id) != "" else "") \
				+ "%s   %d HP" % [str(d2["name"]), int(d2["hp"])]
			b2.tooltip_text = str(d2["desc"])
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b2.custom_minimum_size = Vector2(214, 26)
			b2.add_theme_color_override("font_color", d2["col"])
			b2.pressed.connect(_add_mod.bind(id))
			_pal.add_child(b2)

func _add_mod(id: String) -> void:
	_snap("add %s" % str(SynthMods.def(id)["name"]))
	var only := SynthMods.exclusive_to(id)
	var i := synth.engine.add_mod(id, only if only != "" else _brand)
	if i < 0:
		_flash("no room left in the rack — pull something out first")
		Sfx.play("denied")
	else:
		_flash("%s (%s) bolted in" % [str(SynthMods.def(id)["name"]),
			SynthMods.brand_name(_brand)])
		Sfx.play("click", -12.0)

func _toggle_core(id: String) -> void:
	var seated: bool = synth.core_ultima if id == "ultima" else synth.core_uranium
	if seated:
		synth.pull_core(id)
		_flash("%s pulled — the rack goes quiet" % id)
	elif synth.seat_core(id):
		_flash("%s seated" % id)

## Snapshot the whole patch BEFORE a change, so Ctrl+Z can put it back.
## Called at the START of a drag, not per mouse-move: turning a knob is
## one undo step, not four hundred.
func _snap(label: String) -> void:
	if synth == null or not is_instance_valid(synth):
		return
	_undo.append({"d": synth.engine.to_dict(), "l": label})
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()

func _undo_step() -> void:
	if _undo.is_empty():
		_flash("nothing left to undo")
		Sfx.play("denied", -22.0)
		return
	var entry: Dictionary = _undo.pop_back()
	_redo.append({"d": synth.engine.to_dict(), "l": str(entry["l"])})
	synth.engine.from_dict(entry["d"])
	Sfx.play("click", -14.0)
	_flash("undid: %s   (Ctrl+Shift+Z redoes)" % str(entry["l"]))

func _redo_step() -> void:
	if _redo.is_empty():
		_flash("nothing to redo")
		Sfx.play("denied", -22.0)
		return
	var entry: Dictionary = _redo.pop_back()
	_undo.append({"d": synth.engine.to_dict(), "l": str(entry["l"])})
	synth.engine.from_dict(entry["d"])
	Sfx.play("click", -14.0)
	_flash("redid: %s" % str(entry["l"]))

## Which key of a vertical keyboard is under this point (widget-local).
## Blacks are drawn on the left and straddle the join between two
## whites, so they get first refusal.
func _vkey_note(wsize: Vector2, lp: Vector2) -> int:
	var whv := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
	var lpk := lp
	var wk := wsize
	var khv := wk.y / float(whv.size())
	if lpk.x < wk.x * 0.56:
		for i in whv.size() - 1:
			if not (int(whv[i]) % 12 in [0, 2, 5, 7, 9]):
				continue
			var yb := wk.y - khv * float(i + 1)
			if lpk.y >= yb - khv * 0.32 and lpk.y <= yb + khv * 0.32:
				return int(whv[i]) + 1
	var iv := clampi(int((wk.y - lpk.y) / khv), 0, whv.size() - 1)
	return int(whv[iv])

## Right-click a knob and type the value you actually want. Knobs are
## fine for sweeping and hopeless for "exactly 0.02 Hz".
func _type_knob(mi: int, ki: int) -> void:
	var m = synth.engine.mods[mi]
	var kn: Array = SynthMods.def(m.id)["knobs"]
	if ki < 0 or ki >= kn.size():
		return
	var kd: Dictionary = kn[ki]
	var dlg := AcceptDialog.new()
	dlg.title = "%s — %s" % [str(SynthMods.def(m.id)["name"]), str(kd["n"])]
	var box := VBoxContainer.new()
	var lab := Label.new()
	lab.text = "range %s to %s        (now %s)" % [
		String.num(float(kd["min"]), 4).rstrip("0").rstrip("."),
		String.num(float(kd["max"]), 4).rstrip("0").rstrip("."),
		SynthMods.knob_text(kd, m.p[ki])]
	lab.add_theme_color_override("font_color", Color("#8fa8b8"))
	box.add_child(lab)
	var le := LineEdit.new()
	le.text = String.num(SynthMods.knob_val(kd, m.p[ki]), 4).rstrip("0").rstrip(".")
	le.custom_minimum_size = Vector2(320, 40)
	le.select_all_on_focus = true
	box.add_child(le)
	dlg.add_child(box)
	var apply := func() -> void:
		var txt := le.text.strip_edges()
		if not txt.is_valid_float():
			_flash("that is not a number")
			return
		_snap("set %s" % str(kd["n"]))
		var v := clampf(txt.to_float(), float(kd["min"]), float(kd["max"]))
		synth.engine.set_knob(mi, ki, SynthMods.knob_norm(kd, v))
		_flash("%s set to %s" % [str(kd["n"]), SynthMods.knob_text(kd, m.p[ki])])
		Sfx.play("click", -12.0)
	dlg.confirmed.connect(apply)
	le.text_submitted.connect(func(_t: String) -> void:
		apply.call()
		dlg.hide())
	add_child(dlg)
	dlg.popup_centered(Vector2i(400, 160))
	le.grab_focus()

## Retype a broadcast station's name, right on the panel.
func _rename_station(mi: int) -> void:
	var m = synth.engine.mods[mi]
	var dlg := AcceptDialog.new()
	dlg.title = "STATION NAME"
	dlg.dialog_hide_on_ok = true
	var le := LineEdit.new()
	le.text = str(m.name_tag) if str(m.name_tag) != "" else "DUDE FM"
	le.max_length = 22
	le.custom_minimum_size = Vector2(360, 40)
	le.select_all_on_focus = true
	dlg.add_child(le)
	dlg.confirmed.connect(func() -> void:
		_snap("rename station")
		m.name_tag = le.text.strip_edges()
		synth._claimed_name = ""      # force the claim to refresh
		Airwaves.rename(synth, m.name_tag)
		_flash("station renamed to %s" % m.name_tag)
		Sfx.play("click", -12.0))
	le.text_submitted.connect(func(_t: String) -> void:
		dlg.confirmed.emit()
		dlg.hide())
	add_child(dlg)
	dlg.popup_centered(Vector2i(420, 140))
	le.grab_focus()

func _flash(s: String) -> void:
	_status.text = s

func close() -> void:
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE and not event.echo:
		close()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo_step()
		else:
			_undo_step()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_step()
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	if synth == null or not is_instance_valid(synth):
		close()
		return
	_rack.queue_redraw()
	var e := synth.engine
	var st := "OFFLINE"
	var col := Color("#ff5964")
	if not synth.ready_to_run():
		st = "CORES MISSING — seat %s%s" % [
			"an ULTIMA CRYSTAL " if not synth.core_ultima else "",
			"a URANIUM CELL" if not synth.core_uranium else ""]
	elif synth.buf <= 0.0:
		st = "NO POWER — wire %.1f EU/s into the case" % synth.drain()
	elif synth.powered:
		st = "RUNNING"
		col = Color("#3aff6a")
	_pow.text = "%s     buffer %.0f/%.0f EU     drain %.1f EU/s     %d modules · %d cables     dsp %.0f%%" % [
		st, synth.buf, synth.buf_cap, synth.drain(), e.mods.size(),
		e.cables.size(), clampf(e.cpu, 0.0, 9.9) * 100.0]
	_pow.add_theme_color_override("font_color", col)
	for b in _core_btns:
		var cid: String = str(b.get_meta("core"))
		var seated: bool = synth.core_ultima if cid == "ultima" else synth.core_uranium
		var want: String = ("PULL " if seated else "SEAT ") \
			+ ("ULTIMA CORE" if cid == "ultima" else "URANIUM CELL")
		if b.text != want:
			b.text = want
		b.add_theme_color_override("font_color",
			Color("#7df9ff") if (seated and cid == "ultima")
			else (Color("#5aff3a") if seated else Color("#ff8a7a")))

# ------------------------------------------------------------ rack space

func _to_screen(abs_pt: Vector2) -> Vector2:
	return _pan + abs_pt * _z

func _to_panel(scr: Vector2) -> Vector2:
	return (scr - _pan) / _z

func _mod_org(m) -> Vector2:
	return Vector2(float(m.hp) * SynthMods.HPW,
		float(m.row) * (SynthMods.PANEL_H + ModSynth.GAPU))

func _jack_screen(mi: int, is_in: bool, ji: int) -> Vector2:
	var m = synth.engine.mods[mi]
	var lay := SynthMods.layout(m.id)
	var arr: Array = lay["jin"] if is_in else lay["jout"]
	if ji >= arr.size():
		return Vector2.ZERO
	return _to_screen(_mod_org(m) + (arr[ji] as Vector2))

## What is under this point? Panels are searched front to back.
func _hit(scr: Vector2) -> Dictionary:
	var p := _to_panel(scr)
	var e := synth.engine
	for mi in range(e.mods.size() - 1, -1, -1):
		var m = e.mods[mi]
		var d := SynthMods.def(m.id)
		var lay := SynthMods.layout(m.id)
		var org := _mod_org(m)
		var r := Rect2(org, Vector2(float(lay["w"]), SynthMods.PANEL_H))
		if not r.has_point(p):
			continue
		var lp := p - org
		for pass_i in 2:
			var arr: Array = lay["jin"] if pass_i == 0 else lay["jout"]
			for ji in arr.size():
				if lp.distance_to(arr[ji]) < SynthMods.JACK_R * 1.7:
					return {"mi": mi, "kind": ("jin" if pass_i == 0 else "jout"), "i": ji}
		for ki in (lay["knobs"] as Array).size():
			if lp.distance_to(lay["knobs"][ki]) < SynthMods.KNOB_R * 1.35:
				return {"mi": mi, "kind": "knob", "i": ki}
		for si in (lay["sw"] as Array).size():
			if (lay["sw"][si] as Rect2).has_point(lp):
				return {"mi": mi, "kind": "sw", "i": si}
		if str(d["widget"]) != "" and (lay["widget"] as Rect2).has_point(lp):
			return {"mi": mi, "kind": "widget", "i": 0,
				"lp": lp - (lay["widget"] as Rect2).position,
				"wr": lay["widget"]}
		if lp.y < 15.0:
			return {"mi": mi, "kind": "title", "i": 0}
		return {"mi": mi, "kind": "body", "i": 0}
	return {}

## The 15-point sag the cable is DRAWN with, so hit-testing matches
## what your eye sees.
func _cable_pts(c: Dictionary) -> PackedVector2Array:
	var e := synth.engine
	var a := _jack_screen(int(c["sm"]), false, int(c["so"]))
	var b := _jack_screen(int(c["dm"]), true, int(c["di"]))
	var pts := PackedVector2Array()
	var droop := minf(a.distance_to(b) * 0.32, 110.0) + 8.0
	for i in 15:
		var t := float(i) / 14.0
		var p := a.lerp(b, t)
		p.y += sin(PI * t) * droop
		pts.append(p)
	return pts

## Which cable is under the cursor, and which END of it is nearer.
func _cable_hit(scr: Vector2) -> Dictionary:
	var e := synth.engine
	var best := {}
	var bestd := 12.0 + _z * 1.5
	for ci in e.cables.size():
		var c: Dictionary = e.cables[ci]
		if int(c["sm"]) >= e.mods.size() or int(c["dm"]) >= e.mods.size():
			continue
		var pts := _cable_pts(c)
		for i in pts.size() - 1:
			var d := _seg_dist(scr, pts[i], pts[i + 1])
			if d < bestd:
				bestd = d
				var head: bool = float(i) / float(pts.size() - 2) < 0.5
				best = {"ci": ci, "grab_out": head}
	return best

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Grab an existing cable by its body: the end you grabbed comes off the
## jack and follows the mouse. Drop it on a jack to re-route it, drop it
## on empty rack and it is GONE.
func _grab_cable(hit: Dictionary) -> void:
	var e := synth.engine
	_snap("move cable")
	var c: Dictionary = e.cables[int(hit["ci"])]
	var sm := int(c["sm"])
	var so := int(c["so"])
	var dm := int(c["dm"])
	var di := int(c["di"])
	e.unpatch(dm, true, di)
	_drag = "cable"
	if bool(hit["grab_out"]):
		# grabbed the output end: the input jack is the anchor now
		_dmod = dm
		_di = di
		_dfrom_out = false
	else:
		_dmod = sm
		_di = so
		_dfrom_out = true
	Sfx.play("click", -18.0)
	_flash("cable in hand — drop it on a jack, or on empty rack to bin it")

func _rack_input(event: InputEvent) -> void:
	var e := synth.engine
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
		match _drag:
			"knob":
				var fine: bool = Input.is_key_pressed(KEY_SHIFT)
				var dy: float = (_dstart.y - event.position.y) * (0.0009 if fine else 0.005)
				e.set_knob(_dmod, _di, clampf(_dval + dy, 0.0, 1.0))
			"pan":
				_pan += event.relative
			"move":
				var p := _to_panel(event.position)
				var row := clampi(int(p.y / (SynthMods.PANEL_H + ModSynth.GAPU)), 0, e.rows - 1)
				var hp := int(round((p.x - _dval) / SynthMods.HPW))
				e.move_mod(_dmod, row, hp)
			"step":
				var m = e.mods[_dmod]
				var wr: Rect2 = SynthMods.layout(m.id)["widget"]
				var _nsx: int = int(SynthMods.def(m.id).get("steps", 8))
				var lp := _to_panel(event.position) - _mod_org(m) - wr.position
				var v := clampf(1.0 - lp.y / (wr.size.y * 0.62), 0.0, 1.0)
				e.set_step(_dmod, _di, v)
			"bars":
				var mb = e.mods[_dmod]
				var wrb: Rect2 = SynthMods.layout(mb.id)["widget"]
				var lpb := _to_panel(event.position) - _mod_org(mb) - wrb.position
				var nb4: int = int(SynthMods.def(mb.id).get("steps", 20))
				var ib2 := clampi(int(lpb.x / (wrb.size.x / float(nb4))), 0, nb4 - 1)
				e.set_step(_dmod, ib2, clampf(1.0 - lpb.y / wrb.size.y, 0.0, 1.0))
			"roll":
				var mr = e.mods[_dmod]
				var wrr: Rect2 = SynthMods.layout(mr.id)["widget"]
				var lpr := _to_panel(event.position) - _mod_org(mr) - wrr.position
				var npr3: int = int(SynthMods.def(mr.id).get("patterns", 1))
				var grh2 := wrr.size.y - (9.0 if npr3 > 1 else 0.0)
				if lpr.y <= grh2:
					var colR2 := clampi(int(lpr.x / (wrr.size.x / 16.0)), 0, 15)
					var pitchR2 := 11 - clampi(int(lpr.y / (grh2 / 12.0)), 0, 11)
					var pb2: int = int(mr.s[7]) * 16 if mr.s.size() > 7 else 0
					e.set_step(_dmod, pb2 + colR2, float(pitchR2))
			"padxy":
				var mx = e.mods[_dmod]
				var wrx: Rect2 = SynthMods.layout(mx.id)["widget"]
				var lpx := _to_panel(event.position) - _mod_org(mx) - wrx.position
				e.set_xy(_dmod, lpx.x / wrx.size.x, lpx.y / wrx.size.y, true)
			"vkey":
				# hold and drag: every key you pass over gets hit
				var mk2 = e.mods[_dmod]
				var wrv: Rect2 = SynthMods.layout(mk2.id)["widget"]
				var lpv := _to_panel(event.position) - _mod_org(mk2) - wrv.position
				if lpv.x >= 0.0 and lpv.x <= wrv.size.x \
						and lpv.y >= 0.0 and lpv.y <= wrv.size.y:
					var nn := _vkey_note(wrv.size, lpv)
					if int(mk2.st[0]) != nn or mk2.st[1] < 0.5:
						e.key_press(_dmod, float(nn), true)
			"deskfader", "deskpan":
				var md2 = e.mods[_dmod]
				var wrd: Rect2 = SynthMods.layout(md2.id)["widget"]
				var lpd := _to_panel(event.position) - _mod_org(md2) - wrd.position
				var swd := wrd.size.x / 7.0
				if _drag == "deskpan":
					e.set_knob(_dmod, 6 + _di, clampf((lpd.x - swd * float(_di) - 2.0)
						/ maxf(swd - 4.0, 1.0), 0.0, 1.0))
				else:
					var topd := (9.0 if _di < 6 else 2.0)
					var fhd := wrd.size.y - topd - 8.0 - 4.0
					e.set_knob(_dmod, _di, clampf(1.0 - (lpd.y - topd - 5.0)
						/ maxf(fhd - 10.0, 1.0), 0.0, 1.0))
			"columncell":
				var mc = e.mods[_dmod]
				var wrc: Rect2 = SynthMods.layout(mc.id)["widget"]
				var lpc := _to_panel(event.position) - _mod_org(mc) - wrc.position
				var nSc3: int = int(SynthMods.def(mc.id).get("steps", 8))
				var pb3: int = (int(mc.s[7]) if mc.s.size() > 7 else 0) * nSc3
				if lpc.x <= wrc.size.x - 7.0:
					e.set_step(_dmod, pb3 + clampi(int(lpc.y
						/ (wrc.size.y / float(nSc3))), 0, nSc3 - 1), _dval)
			"kitcell":
				var mk = e.mods[_dmod]
				var wrk: Rect2 = SynthMods.layout(mk.id)["widget"]
				var lpk := _to_panel(event.position) - _mod_org(mk) - wrk.position
				var colK2 := clampi(int((lpk.x - 7.0) / ((wrk.size.x - 7.0) / 16.0)), 0, 15)
				var laneK2 := clampi(int(lpk.y / (wrk.size.y / 8.0)), 0, 7)
				e.set_step(_dmod, laneK2 * 16 + colK2, _dval)
			"gridcell":
				var mg = e.mods[_dmod]
				var wrg: Rect2 = SynthMods.layout(mg.id)["widget"]
				var lpg := _to_panel(event.position) - _mod_org(mg) - wrg.position
				var rhg2 := wrg.size.y / 4.0
				var laneg2 := float(int(_di % 64) / 16)
				var frg := clampf(1.0 - (lpg.y - rhg2 * laneg2) / rhg2, 0.0, 1.0)
				e.set_step(_dmod, _di, frg)
			"cell":
				var m2 = e.mods[_dmod]
				var wr2: Rect2 = SynthMods.layout(m2.id)["widget"]
				var lp2 := _to_panel(event.position) - _mod_org(m2) - wr2.position
				var col2 := clampi(int(lp2.x / (wr2.size.x / 16.0)), 0, 15)
				var lane := clampi(int(lp2.y / (wr2.size.y / 4.0)), 0, 3)
				e.set_step(_dmod, lane * 16 + col2, _dval)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.12, event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.0 / 1.12, event.position)
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if event.pressed else ""
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var h := _hit(event.position)
			if h.is_empty() or str(h.get("kind", "")) in ["body", "title"]:
				var ch := _cable_hit(event.position)
				if not ch.is_empty():
					var c2: Dictionary = e.cables[int(ch["ci"])]
					_snap("pull cable")
					e.unpatch(int(c2["dm"]), true, int(c2["di"]))
					Sfx.play("click", -14.0)
					_flash("cable pulled")
					return
			if h.is_empty():
				return
			match str(h["kind"]):
				"jin":
					_snap("pull cable")
					if e.unpatch(int(h["mi"]), true, int(h["i"])) > 0:
						Sfx.play("click", -14.0)
						_flash("cable pulled")
				"jout":
					_snap("pull cables")
					var n := e.unpatch(int(h["mi"]), false, int(h["i"]))
					if n > 0:
						Sfx.play("click", -14.0)
						_flash("%d cable(s) pulled" % n)
				"knob":
					_type_knob(int(h["mi"]), int(h["i"]))
				"widget":
					# right-click empties a chance cell; every other panel
					# keeps its ordinary right-click menu
					var mw = e.mods[int(h["mi"])]
					if str(SynthMods.def(mw.id)["widget"]) == "grid":
						var wrw: Rect2 = SynthMods.layout(mw.id)["widget"]
						var lpw := _to_panel(event.position) - _mod_org(mw) - wrw.position
						var cw3 := clampi(int(lpw.x / (wrw.size.x / 16.0)), 0, 15)
						var lw4 := clampi(int(lpw.y / (wrw.size.y / 4.0)), 0, 3)
						var pw2: int = clampi(int(round(
							e.knob_value(int(h["mi"]), 2))) - 1, 0, 3)
						_snap("clear cell")
						e.set_step(int(h["mi"]), pw2 * 64 + lw4 * 16 + cw3, 0.0)
						Sfx.play("click", -18.0)
						_flash("cell emptied")
					else:
						_open_menu(int(h["mi"]), event.position)
				_:
					_open_menu(int(h["mi"]), event.position)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not event.pressed:
			_release(event.position)
			return
		var h2 := _hit(event.position)
		if h2.is_empty() or str(h2.get("kind", "")) in ["body", "title"]:
			var ch2 := _cable_hit(event.position)
			if not ch2.is_empty():
				_grab_cable(ch2)
				return
		if h2.is_empty():
			_drag = "pan"
			return
		_dmod = int(h2["mi"])
		var m3 = e.mods[_dmod]
		match str(h2["kind"]):
			"knob":
				_snap("turn %s" % str((SynthMods.def(m3.id)["knobs"][int(h2["i"])])["n"]))
				_drag = "knob"
				_di = int(h2["i"])
				_dval = m3.p[_di]
				_dstart = event.position
			"sw":
				_open_sw(_dmod, int(h2["i"]), event.position)
			"jin", "jout":
				_snap("patch")
				_drag = "cable"
				_di = int(h2["i"])
				_dfrom_out = str(h2["kind"]) == "jout"
				if not _dfrom_out:
					# pulling on a patched input takes the cable WITH you
					var c := e.cable_at_input(_dmod, _di)
					if not c.is_empty():
						e.unpatch(_dmod, true, _di)
						_dmod = int(c["sm"])
						_di = int(c["so"])
						_dfrom_out = true
				elif not Input.is_key_pressed(KEY_SHIFT):
					# an output with a cable in it hands that cable over,
					# exactly like an input does. Hold SHIFT on a used
					# output if you want a SECOND cable out of it (that
					# is what a mult is, and outputs can drive many
					# inputs at once).
					var found := {}
					for c2 in e.cables:
						if int(c2["sm"]) == _dmod and int(c2["so"]) == _di:
							found = c2
					if not found.is_empty():
						var dm2 := int(found["dm"])
						var di2 := int(found["di"])
						e.unpatch(dm2, true, di2)
						_dmod = dm2
						_di = di2
						_dfrom_out = false
						_flash("cable lifted — drop it on another output, or on empty rack to bin it")
			"title":
				_snap("move panel")
				_drag = "move"
				_dval = _to_panel(event.position).x - float(m3.hp) * SynthMods.HPW
			"widget":
				_widget_press(m3, h2, event.position)
			_:
				_drag = "pan"

func _widget_press(m, h: Dictionary, scr: Vector2) -> void:
	var e := synth.engine
	_snap("edit %s" % str(SynthMods.def(m.id)["name"]))
	var wr: Rect2 = h["wr"]
	var lp: Vector2 = h["lp"]
	match str(SynthMods.def(m.id)["widget"]):
		"seq8", "seqn":
			var nst: int = int(SynthMods.def(m.id).get("steps", 8))
			var col := clampi(int(lp.x / (wr.size.x / float(nst))), 0, nst - 1)
			if lp.y > wr.size.y * 0.66:
				var on: bool = m.st[nst + col] > 0.5
				e.set_step(_dmod, nst + col, 0.0 if on else 1.0)
				Sfx.play("click", -18.0)
			else:
				_drag = "step"
				_di = col
				e.set_step(_dmod, col, clampf(1.0 - lp.y / (wr.size.y * 0.62), 0.0, 1.0))
		"roll":
			var npr2: int = int(SynthMods.def(m.id).get("patterns", 1))
			var strip2: float = 9.0 if npr2 > 1 else 0.0
			if npr2 > 1 and lp.y > wr.size.y - strip2:
				# the bar strip: jump straight to that pattern for editing
				var pick := clampi(int(lp.x / (wr.size.x / float(npr2))), 0, npr2 - 1)
				var kd: Array = SynthMods.def(m.id)["knobs"]
				e.set_knob(_dmod, 1, SynthMods.knob_norm(kd[1], float(pick + 1)))
				Sfx.play("click", -16.0)
				_flash("editing pattern %d of %d" % [pick + 1, npr2])
				return
			var grh := wr.size.y - strip2
			var colR := clampi(int(lp.x / (wr.size.x / 16.0)), 0, 15)
			var pitchR := 11 - clampi(int(lp.y / (grh / 12.0)), 0, 11)
			var pbase: int = int(m.s[7]) * 16 if m.s.size() > 7 else 0
			var wasR: float = m.st[pbase + colR]
			# clicking the note that is already there clears the step
			e.set_step(_dmod, pbase + colR, -1.0 if int(wasR) == pitchR else float(pitchR))
			_drag = "roll"
			_dval = float(pitchR)
			Sfx.play("click", -18.0)
		"bars":
			var nb3: int = int(SynthMods.def(m.id).get("steps", 20))
			var ib := clampi(int(lp.x / (wr.size.x / float(nb3))), 0, nb3 - 1)
			e.set_step(_dmod, ib, clampf(1.0 - lp.y / wr.size.y, 0.0, 1.0))
			_drag = "bars"
		"cast":
			# the name plate band: type a new station name
			if lp.y > wr.size.y * 0.30 and lp.y < wr.size.y * 0.64:
				_rename_station(_dmod)
			_drag = ""
		"buttons":
			_di = 0 if lp.x < wr.size.x * 0.5 else 1
			e.press_button(_dmod, _di, true)
			_drag = "btn"
			Sfx.play("click", -14.0)
		"xy":
			_drag = "padxy"
			e.set_xy(_dmod, lp.x / wr.size.x, lp.y / wr.size.y, true)
		"column":
			var nSc2: int = int(SynthMods.def(m.id).get("steps", 8))
			var nPc2: int = int(SynthMods.def(m.id).get("patterns", 1))
			var strip4: float = 7.0 if nPc2 > 1 else 0.0
			if nPc2 > 1 and lp.x > wr.size.x - strip4:
				var pick2 := clampi(int(lp.y / (wr.size.y / float(nPc2))), 0, nPc2 - 1)
				e.set_step(_dmod, 32, float(pick2))
				_flash("cutting column %d of %d" % [pick2 + 1, nPc2])
				Sfx.play("click", -16.0)
				return
			var iC := clampi(int(lp.y / (wr.size.y / float(nSc2))), 0, nSc2 - 1)
			var pbase2: int = (int(m.s[7]) if m.s.size() > 7 else 0) * nSc2
			var onC: bool = m.st[pbase2 + iC] > 0.5
			_dval = 0.0 if onC else 1.0
			e.set_step(_dmod, pbase2 + iC, _dval)
			_drag = "columncell"
			Sfx.play("click", -18.0)
		"kit":
			var lw3 := 7.0
			var colK := clampi(int((lp.x - lw3) / ((wr.size.x - lw3) / 16.0)), 0, 15)
			var laneK := clampi(int(lp.y / (wr.size.y / 8.0)), 0, 7)
			var onK2: bool = m.st[laneK * 16 + colK] > 0.5
			_dval = 0.0 if onK2 else 1.0
			_drag = "kitcell"
			e.set_step(_dmod, laneK * 16 + colK, _dval)
			Sfx.play("click", -18.0)
		"grid":
			# a cell is ODDS, so it is dragged, not toggled: grab it and
			# slide up for surer, down for rarer. A click at the very top
			# of a cell means "always", at the very bottom "never".
			var colG := clampi(int(lp.x / (wr.size.x / 16.0)), 0, 15)
			var laneG := clampi(int(lp.y / (wr.size.y / 4.0)), 0, 3)
			var patG2: int = clampi(int(round(e.knob_value(_dmod, 2))) - 1, 0, 3)
			_di = patG2 * 64 + laneG * 16 + colG
			var rhG := wr.size.y / 4.0
			var fr: float = clampf(1.0 - (lp.y - rhG * float(laneG)) / rhG, 0.0, 1.0)
			_dval = 0.0 if fr < 0.06 else (1.0 if fr > 0.94 else fr)
			e.set_step(_dmod, _di, _dval)
			_drag = "gridcell"
			_flash("%d%% chance" % int(_dval * 100.0))
			Sfx.play("click", -18.0)
		"dseq":
			var col2 := clampi(int(lp.x / (wr.size.x / 16.0)), 0, 15)
			var lane := clampi(int(lp.y / (wr.size.y / 4.0)), 0, 3)
			var on2: bool = m.st[lane * 16 + col2] > 0.5
			_dval = 0.0 if on2 else 1.0
			_drag = "cell"
			e.set_step(_dmod, lane * 16 + col2, _dval)
			Sfx.play("click", -18.0)
		"desk":
			var nch2 := 6
			var sw2 := wr.size.x / float(nch2 + 1)
			var chi := clampi(int(lp.x / sw2), 0, nch2)
			var panh2 := 9.0
			var muteh2 := 8.0
			if chi < nch2 and lp.y > wr.size.y - muteh2:
				# MUTE
				var was: float = m.st[chi] if m.st.size() > chi else 0.0
				e.set_step(_dmod, chi, 0.0 if was > 0.5 else 1.0)
				Sfx.play("click", -16.0)
				return
			if chi < nch2 and lp.y < panh2:
				_drag = "deskpan"
				_di = chi
				var fr3 := clampf((lp.x - sw2 * float(chi) - 2.0)
					/ maxf(sw2 - 4.0, 1.0), 0.0, 1.0)
				e.set_knob(_dmod, 6 + chi, fr3)
				return
			_drag = "deskfader"
			_di = chi if chi < nch2 else 12
			var top2 := (panh2 if chi < nch2 else 2.0)
			var fh2 := wr.size.y - top2 - muteh2 - 4.0
			e.set_knob(_dmod, _di, clampf(1.0 - (lp.y - top2 - 5.0)
				/ maxf(fh2 - 10.0, 1.0), 0.0, 1.0))
		"vkeys":
			e.key_press(_dmod, float(_vkey_note(wr.size, lp)), true)
			_drag = "vkey"
		"keys":
			var whites := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
			var kw := wr.size.x / float(whites.size())
			var i := clampi(int(lp.x / kw), 0, whites.size() - 1)
			var note: int = whites[i]
			if lp.y < wr.size.y * 0.62:
				# black keys ride the seam between two whites
				var frac := lp.x / kw - float(i)
				if frac > 0.7 and note % 12 in [0, 2, 5, 7, 9]:
					note += 1
				elif frac < 0.3 and i > 0 and int(whites[i - 1]) % 12 in [0, 2, 5, 7, 9]:
					note = int(whites[i - 1]) + 1
			e.key_press(_dmod, float(note), true)
			_drag = "key"
		_:
			_drag = "pan"

func _release(_scr: Vector2) -> void:
	var e := synth.engine
	if _drag == "cable":
		var h := _hover
		if h.is_empty() or not (str(h.get("kind", "")) in ["jin", "jout"]):
			_flash("cable binned")
			Sfx.play("denied", -22.0)
		if not h.is_empty():
			var want: String = "jin" if _dfrom_out else "jout"
			if str(h.get("kind", "")) == want:
				var ok: bool = e.patch(_dmod, _di, int(h["mi"]), int(h["i"])) if _dfrom_out \
					else e.patch(int(h["mi"]), int(h["i"]), _dmod, _di)
				if ok:
					Sfx.play("click", -10.0)
					_flash("patched")
			elif str(h.get("kind", "")) == ("jout" if _dfrom_out else "jin"):
				_flash("outputs go to inputs — that end is the wrong sex")
				Sfx.play("denied", -16.0)
	elif _drag == "key":
		e.key_press(_dmod, -1.0, false)
	elif _drag == "vkey":
		# LATCH holds the last note; MOMENTARY lets go with the mouse
		var mv = e.mods[_dmod]
		if mv.sw.size() > 0 and mv.sw[0] == 1:
			pass
		else:
			e.key_press(_dmod, mv.st[0], false)
	elif _drag == "btn":
		e.press_button(_dmod, _di, false)
	elif _drag == "padxy":
		var mz = e.mods[_dmod]
		e.set_xy(_dmod, mz.st[0], mz.st[1], false)
	_drag = ""

func _zoom(f: float, at: Vector2) -> void:
	var before := _to_panel(at)
	_z = clampf(_z * f, 1.4, 12.0)
	_pan = at - before * _z

func _open_menu(mi: int, at: Vector2) -> void:
	_menu_mod = mi
	var m = synth.engine.mods[mi]
	_menu.clear()
	_menu.add_item("%s — %s" % [str(SynthMods.def(m.id)["name"]),
		SynthMods.brand_name(m.brand)], 99)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	var only2 := SynthMods.exclusive_to(m.id)
	if only2 != "":
		_menu.add_item("house exclusive — cannot be rebranded", 98)
		_menu.set_item_disabled(_menu.item_count - 1, true)
	else:
		for i in SynthMods.BRANDS.size():
			var b: String = SynthMods.BRANDS[i]
			_menu.add_item(("✓ " if m.brand == b else "   ") + "rebrand: "
				+ SynthMods.brand_name(b), i)
	_menu.add_separator()
	_menu.add_item("DUPLICATE  (same settings)", 51)
	_menu.add_item("PULL MODULE OUT", 50)
	_menu.position = Vector2i(_rack.global_position + at) + Vector2i(0, 0)
	_menu.popup()

func _menu_pick(id: int) -> void:
	if _menu_mod < 0:
		return
	if id == 51:
		var nm2: String = str(SynthMods.def(synth.engine.mods[_menu_mod].id)["name"])
		_snap("duplicate %s" % nm2)
		if synth.engine.duplicate_mod(_menu_mod) < 0:
			_flash("no room in the rack for another %s" % nm2)
			Sfx.play("denied")
		else:
			_flash("%s duplicated" % nm2)
			Sfx.play("click", -12.0)
		_menu_mod = -1
		return
	if id == 50:
		_snap("pull %s" % str(SynthMods.def(synth.engine.mods[_menu_mod].id)["name"]))
		synth.engine.remove_mod(_menu_mod)
		Sfx.play("explode", -22.0)
		_flash("module pulled out of the rack")
	elif id >= 0 and id < SynthMods.BRANDS.size() \
			and SynthMods.exclusive_to(synth.engine.mods[_menu_mod].id) == "":
		_snap("rebrand")
		synth.engine.set_brand(_menu_mod, SynthMods.BRANDS[id])
		_flash("panel swapped for a %s one" % SynthMods.brand_name(SynthMods.BRANDS[id]))
	_menu_mod = -1

func _open_sw(mi: int, si: int, at: Vector2) -> void:
	var m = synth.engine.mods[mi]
	var sws: Array = SynthMods.def(m.id)["sw"]
	var opts: Array = sws[si]["opts"]
	if opts.size() == 2:
		_snap("switch %s" % str(sws[si]["n"]))
		synth.engine.set_sw(mi, si, 1 - m.sw[si])
		Sfx.play("click", -16.0)
		return
	_menu_mod = mi
	_menu_sw = si
	_swmenu.clear()
	_swmenu.add_item(str(sws[si]["n"]), 99)
	_swmenu.set_item_disabled(0, true)
	_swmenu.add_separator()
	for i in opts.size():
		_swmenu.add_item(("✓ " if m.sw[si] == i else "   ") + str(opts[i]), i)
	_swmenu.position = Vector2i(_rack.global_position + at)
	_swmenu.popup()

func _swmenu_pick(id: int) -> void:
	if _menu_mod >= 0 and _menu_sw >= 0 and id < 90:
		_snap("switch")
		synth.engine.set_sw(_menu_mod, _menu_sw, id)
		Sfx.play("click", -16.0)
	_menu_mod = -1
	_menu_sw = -1

# ------------------------------------------------------------- rendering

func _draw_rack() -> void:
	var e := synth.engine
	var sz := _rack.size
	_rack.draw_rect(Rect2(Vector2.ZERO, sz), Color("#07080b"))
	# the empty case: rails, HP ticks, row numbers
	for r in e.rows:
		var y0 := _to_screen(Vector2(0, float(r) * (SynthMods.PANEL_H + ModSynth.GAPU))).y
		var h := SynthMods.PANEL_H * _z
		var x0 := _to_screen(Vector2.ZERO).x
		var w := float(e.row_hp) * SynthMods.HPW * _z
		_rack.draw_rect(Rect2(Vector2(x0, y0), Vector2(w, h)), Color("#12151b"))
		_rack.draw_rect(Rect2(Vector2(x0, y0 - 3.0), Vector2(w, 4.0)), Color("#39404d"))
		_rack.draw_rect(Rect2(Vector2(x0, y0 + h - 1.0), Vector2(w, 4.0)), Color("#39404d"))
		for i in int(e.row_hp / 4):
			var xx := x0 + float(i) * SynthMods.HPW * 4.0 * _z
			_rack.draw_line(Vector2(xx, y0), Vector2(xx, y0 + h), Color(1, 1, 1, 0.035), 1.0)
	# panels
	for mi in e.mods.size():
		var m = e.mods[mi]
		var hot := {}
		if not _hover.is_empty() and int(_hover.get("mi", -1)) == mi:
			hot = {"kind": str(_hover.get("kind", "")), "i": int(_hover.get("i", -1))}
		SynthPaint.draw_module(_rack, m, _to_screen(_mod_org(m)), _z, e, mi, hot)
	# cables over the top of everything, like real ones
	for c in e.cables:
		var sm := int(c["sm"])
		var dm := int(c["dm"])
		if sm >= e.mods.size() or dm >= e.mods.size():
			continue
		var a := _jack_screen(sm, false, int(c["so"]))
		var b := _jack_screen(dm, true, int(c["di"]))
		SynthPaint.draw_cable(_rack, a, b,
			SynthEngine.CABLE_COLS[int(c["col"]) % SynthEngine.CABLE_COLS.size()],
			maxf(2.0, _z * 1.6))
	# the cable in your hand
	if _drag == "cable":
		var a2 := _jack_screen(_dmod, not _dfrom_out, _di)
		SynthPaint.draw_cable(_rack, a2, _rack.get_local_mouse_position(),
			Color("#ffffff"), maxf(2.0, _z * 1.4), 0.18)
		# every jack it could legally land in, lit up
		for mi2 in e.mods.size():
			var d2 := SynthMods.def(e.mods[mi2].id)
			var lst: Array = d2["ins"] if _dfrom_out else d2["outs"]
			for ji in lst.size():
				var jp := _jack_screen(mi2, _dfrom_out, ji)
				_rack.draw_arc(jp, SynthMods.JACK_R * _z * 2.1, 0.0, TAU, 14,
					Color("#3aff6a") * Color(1, 1, 1, 0.75), 2.0)
	# probe: what is actually on the jack under the cursor, right now
	if not _hover.is_empty() and str(_hover.get("kind", "")) in ["jin", "jout"]:
		var mi3 := int(_hover["mi"])
		var isin: bool = str(_hover["kind"]) == "jin"
		var v: float = e.jack_volts(mi3, isin, int(_hover["i"]))
		var d3 := SynthMods.def(e.mods[mi3].id)
		var nm: String = str((d3["ins"] if isin else d3["outs"])[int(_hover["i"])])
		var jp2 := _jack_screen(mi3, isin, int(_hover["i"]))
		var txt := "%s  %+.2f V" % [nm, v]
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bpos := jp2 + Vector2(-tw * 0.5 - 6.0, -34.0)
		_rack.draw_rect(Rect2(bpos, Vector2(tw + 12.0, 22.0)), Color(0, 0, 0, 0.82))
		_rack.draw_rect(Rect2(bpos, Vector2(tw + 12.0, 22.0)), NEON, false, 1.0)
		_rack.draw_string(f, bpos + Vector2(6.0, 16.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#e8f4ff"))
	elif not _hover.is_empty() and str(_hover.get("kind", "")) == "knob":
		var m4 = e.mods[int(_hover["mi"])]
		var kn: Array = SynthMods.def(m4.id)["knobs"]
		var ki := int(_hover["i"])
		var kp := _to_screen(_mod_org(m4) + (SynthMods.layout(m4.id)["knobs"][ki] as Vector2))
		var txt2 := "%s  %s" % [str(kn[ki]["n"]), SynthMods.knob_text(kn[ki], m4.p[ki])]
		var f2 := ThemeDB.fallback_font
		var tw2 := f2.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bp2 := kp + Vector2(-tw2 * 0.5 - 6.0, -30.0)
		_rack.draw_rect(Rect2(bp2, Vector2(tw2 + 12.0, 22.0)), Color(0, 0, 0, 0.82))
		_rack.draw_rect(Rect2(bp2, Vector2(tw2 + 12.0, 22.0)), NEON, false, 1.0)
		_rack.draw_string(f2, bp2 + Vector2(6.0, 16.0), txt2,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#e8f4ff"))
