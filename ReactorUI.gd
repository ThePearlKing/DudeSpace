class_name ReactorUI
extends CanvasLayer
## The reactor CONTROL ROOM. Not a right-click menu -- a panel, with
## everything a licensed operator expects: a mode keyswitch with real
## permissive interlocks, fine and coarse rod control, primary loop
## flow, a turbine breaker you can trip by syncing too early, a
## GUARDED pressure vent (arm it first, like the switch covers say),
## an annunciator lamp grid, live instrumentation, and one big SCRAM.

const AMBER := Color("#ffb347")
const GREEN := Color("#5aff8a")
const RED := Color("#ff4040")
const DARKL := Color("#3a3126")

var rx = null   # the NuclearReactor being operated
var _read: Label
var _pool_view: Control
var _lamps := {}
var _arm_t := 0.0
var _vent_b: Button
var _mode_btns: Array = []

func open(reactor) -> void:
	rx = reactor

func _ready() -> void:
	layer = 19
	add_to_group("reactor_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Panel.new()
	# COMPACT window, slightly transparent -- the world stays visible
	root.anchor_left = 0.2
	root.anchor_top = 0.1
	root.anchor_right = 0.8
	root.anchor_bottom = 0.9
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.11, 0.114, 0.125, 0.86)
	st.border_color = AMBER.darkened(0.5)
	st.set_border_width_all(2)
	root.add_theme_stylebox_override("panel", st)
	add_child(root)
	var title := Label.new()
	title.text = "☢  REACTOR CONTROL — UNIT 1"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", AMBER)
	title.position = Vector2(28, 14)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "ESC closes the panel. the core does not pause with you."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#8a8d90"))
	sub.position = Vector2(30, 50)
	root.add_child(sub)
	var x := Button.new()
	x.text = "✕"
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-60, 14)
	x.custom_minimum_size = Vector2(46, 46)
	x.pressed.connect(close)
	root.add_child(x)

	# LEFT: annunciator grid. lamps you learn to fear.
	var lam := GridContainer.new()
	lam.columns = 2
	lam.anchor_left = 0.03
	lam.anchor_top = 0.14
	lam.anchor_right = 0.3
	lam.anchor_bottom = 0.6
	root.add_child(lam)
	for key in ["HI TEMP", "HI PRESS", "LO COOLANT", "XENON PEAK",
			"ρ POSITIVE", "TURB TRIP", "FUEL LOW", "SCRAM"]:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(112, 34)
		var cs := StyleBoxFlat.new()
		cs.bg_color = DARKL
		cs.set_border_width_all(1)
		cs.border_color = Color("#000")
		cell.add_theme_stylebox_override("panel", cs)
		var cl := Label.new()
		cl.text = key
		cl.set_anchors_preset(Control.PRESET_CENTER)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_theme_font_size_override("font_size", 14)
		cl.add_theme_color_override("font_color", Color("#6a6255"))
		cell.add_child(cl)
		lam.add_child(cell)
		_lamps[key] = {"cell": cell, "style": cs, "label": cl}

	# MIDDLE: instrumentation
	_read = Label.new()
	_read.anchor_left = 0.33
	_read.anchor_top = 0.14
	_read.add_theme_font_size_override("font_size", 14)
	_read.add_theme_color_override("font_color", GREEN)
	root.add_child(_read)
	# CORE POOL PREVIEW: the bundle, live, exactly as blue as it is
	_pool_view = Control.new()
	_pool_view.anchor_left = 0.33
	_pool_view.anchor_top = 0.6
	_pool_view.anchor_right = 0.58
	_pool_view.anchor_bottom = 0.93
	_pool_view.draw.connect(_draw_pool)
	root.add_child(_pool_view)

	# RIGHT: the controls
	var col := VBoxContainer.new()
	col.anchor_left = 0.62
	col.anchor_top = 0.12
	col.anchor_right = 0.97
	col.anchor_bottom = 0.97
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)

	col.add_child(_section("MODE  (permissive interlocks)"))
	var modes := HBoxContainer.new()
	for i in 3:
		var mb := Button.new()
		mb.text = ["SHUTDOWN", "STARTUP", "RUN"][i]
		mb.custom_minimum_size = Vector2(88, 34)
		mb.pressed.connect(_set_mode.bind(i))
		modes.add_child(mb)
		_mode_btns.append(mb)
	col.add_child(modes)

	col.add_child(_section("CONTROL RODS  (servo-driven)"))
	var rodrow := HBoxContainer.new()
	for spec in [["OUT 5%", -0.05], ["OUT 1%", -0.01], ["IN 1%", 0.01], ["IN 5%", 0.05]]:
		var rb := Button.new()
		rb.text = spec[0]
		rb.custom_minimum_size = Vector2(84, 40)
		rb.pressed.connect(_rods.bind(float(spec[1])))
		rodrow.add_child(rb)
	col.add_child(rodrow)

	col.add_child(_section("PRIMARY LOOP / TURBINE"))
	var prow := HBoxContainer.new()
	var fb := Button.new()
	fb.text = "FLOW: cycle"
	fb.custom_minimum_size = Vector2(96, 34)
	fb.pressed.connect(func() -> void:
		if rx:
			rx.flow = (rx.flow + 1) % 3
			Sfx.play("click", -12.0))
	prow.add_child(fb)
	var bb := Button.new()
	bb.text = "BREAKER"
	bb.custom_minimum_size = Vector2(96, 34)
	bb.pressed.connect(func() -> void:
		if rx:
			rx.toggle_breaker())
	prow.add_child(bb)
	col.add_child(prow)

	col.add_child(_section("RELIEF VENT  (guarded)"))
	var vrow := HBoxContainer.new()
	var ab := Button.new()
	ab.text = "ARM"
	ab.custom_minimum_size = Vector2(84, 40)
	ab.pressed.connect(func() -> void:
		_arm_t = 3.0
		Sfx.play("click", -10.0))
	vrow.add_child(ab)
	_vent_b = Button.new()
	_vent_b.text = "VENT"
	_vent_b.custom_minimum_size = Vector2(84, 40)
	_vent_b.disabled = true
	_vent_b.pressed.connect(func() -> void:
		if rx and _arm_t > 0.0:
			rx.press = maxf(0.0, rx.press - 30.0)
			rx.coolant = maxf(0.0, rx.coolant - 12.0)
			_arm_t = 0.0
			Sfx.play("hurt", -16.0))
	vrow.add_child(_vent_b)
	col.add_child(vrow)

	var man := Button.new()
	man.text = "OPERATOR'S MANUAL"
	man.custom_minimum_size = Vector2(200, 36)
	man.pressed.connect(_open_manual)
	col.add_child(man)

	col.add_child(_section("FUEL"))
	var lb := Button.new()
	lb.text = "LOAD URANIUM ROD (from inventory)"
	lb.custom_minimum_size = Vector2(200, 40)
	lb.pressed.connect(func() -> void:
		if rx and Inventory.res_count("uranium") > 0:
			Inventory.remove_res("uranium", 1)
			if str(rx.in_slot["id"]) == "uranium":
				rx.in_slot["n"] = int(rx.in_slot["n"]) + 1
			else:
				rx.in_slot = {"id": "uranium", "n": 1}
			Sfx.play("place")
		else:
			Sfx.play("denied"))
	col.add_child(lb)

	var scram := Button.new()
	scram.text = "S C R A M"
	scram.custom_minimum_size = Vector2(220, 64)
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("#7a1616")
	ss.border_color = RED
	ss.set_border_width_all(2)
	ss.set_corner_radius_all(32)
	scram.add_theme_stylebox_override("normal", ss)
	var sh := ss.duplicate()
	sh.bg_color = Color("#a82020")
	scram.add_theme_stylebox_override("hover", sh)
	scram.add_theme_stylebox_override("pressed", sh)
	scram.add_theme_color_override("font_color", Color.WHITE)
	scram.add_theme_font_size_override("font_size", 24)
	scram.pressed.connect(func() -> void:
		if rx:
			rx.do_scram())
	col.add_child(scram)

## The rod, described like the maintenance sheet would.
func _fuel_line() -> String:
	if rx._fuel > 0.0:
		var bu: float = rx.rod_burnup() * 100.0
		var cond := "fresh"
		if bu > 85.0:
			cond = "nearly spent"
		elif bu > 55.0:
			cond = "worn"
		elif bu > 20.0:
			cond = "in service"
		return "rod %.0f%% burned (%s) · %ds left" % [bu, cond, int(rx._fuel)]
	var hopper := int(rx.in_slot["n"]) if str(rx.in_slot["id"]) == "uranium" else 0
	return "NO ROD IN CORE · hopper: %d" % hopper

func _section(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", AMBER)
	return l

func _set_mode(m: int) -> void:
	if rx == null:
		return
	if not rx.set_mode(m):
		Sfx.play("denied")   # permissive not met. read the placard.
	else:
		Sfx.play("click", -10.0)

func _rods(d: float) -> void:
	if rx == null:
		return
	if not rx.order_rods(d):
		Sfx.play("denied")
	else:
		Sfx.play("click", -14.0)

func _other_ui_open() -> bool:
	# an inventory / storage / machine screen under us still needs the
	# mouse -- don't yank it back into capture on top of them
	for grp in ["storage_ui", "machine_ui"]:
		var n = get_tree().get_first_node_in_group(grp)
		if n != null and n is CanvasItem and n.visible:
			return true
	return false

var _manual: Panel = null

## The startup procedure, as taught to every operator who is still alive.
func _open_manual() -> void:
	if _manual != null:
		_manual.queue_free()
		_manual = null
		return
	_manual = Panel.new()
	# left side, nudged DOWN past the lamp grid. that's it. that's the fix.
	_manual.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	var vps := get_viewport().get_visible_rect().size
	_manual.custom_minimum_size = Vector2(470, minf(620.0, vps.y - 140.0))
	_manual.size = _manual.custom_minimum_size
	_manual.position = Vector2(8, -_manual.size.y * 0.5 + 100.0)
	var st2 := StyleBoxFlat.new()
	st2.bg_color = Color("#26241c")
	st2.border_color = AMBER
	st2.set_border_width_all(2)
	_manual.add_theme_stylebox_override("panel", st2)
	get_child(0).add_child(_manual)
	var msc := ScrollContainer.new()
	msc.set_anchors_preset(Control.PRESET_FULL_RECT)
	msc.offset_left = 18
	msc.offset_top = 14
	msc.offset_right = -14
	msc.offset_bottom = -14
	_manual.add_child(msc)
	var t2 := Label.new()
	t2.text = """OPERATOR'S MANUAL — DO NOT LAMINATE

STARTUP (in this order, no improvising):
 1. LOAD a uranium rod. an empty core does nothing.
 2. COOLANT FLOW to HALF or FULL. no flow, no startup mode.
 3. MODE: STARTUP. rods now move, but only down to 45%%.
 4. Rods OUT until insertion drops BELOW 65%%. that's the
    magic number: above 65%% in, ρ stays negative and power
    just sinks -- pulling "a little" does NOTHING. head for
    ~55%% (startup floor is 45%%) and watch ρ flip positive.
 4b. ρ positive = power RISING, exponentially. small positive
    is a startup. big positive is a headline.
 5. When POWER > 3%% and CORE >= 150°C, MODE: RUN.
    (both numbers are on the readout. no vibes required.)
 6. Rods OUT slowly toward criticality. the hot core and the
    xenon both push ρ down -- that's the core stabilizing
    itself. let it.
 7. When steam is real (power x flow), close the BREAKER.
    too early = turbine trip. that's embarrassing, not fatal.

FUEL, OR: WHY ρ JUST SLAMMED NEGATIVE
 · one rod = ~60 seconds of full-power burn. burn slower,
   it lasts longer.
 · at FUEL 0%% the core physically cannot react: ρ pins to
   -1.0 instantly and power dies. that's not a malfunction,
   that's an empty furnace.
 · watch the FUEL %% on the readout; the FUEL LOW lamp and
   the coach line warn you near the end. keep rods in the
   hopper -- a FUNNEL can restock it automatically.

RULES OF NOT EXPLODING:
 · CORE temp climbs when power beats cooling. above ~550°C
   you are spending margin. at 1000°C you are news.
 · PRESSURE follows temp. the guarded VENT dumps 30 bar and
   costs coolant. coolant comes back only when the core is calm.
 · XENON, in dude terms: burning fuel makes an invisible
   ASH (xenon) that soaks up your reaction. the XENON %% on
   the readout is how much. it's why power sinks while RODS
   and FUEL look fine.

HOW TO SET POWER (you can't. you steer it):
 · there is no power dial. RODS steer ρ, and ρ steers power:
   ρ positive = power climbs. ρ negative = power falls.
   ρ near zero = power HOLDS where it is.
 · so to get to, say, 60%%: rods OUT until ρ reads ~+0.05,
   watch POWER climb, and when it reaches ~60%%, rods back IN
   until ρ reads ~0. that's it. that's driving a reactor.

HOW TO NOT LET THE ASH RUIN YOUR DAY (the playbook):
 1. CRUISE at 50-70%% power, FLOW FULL. this is the sweet
    spot: steady heat, and the ash levels off instead of
    piling. 100%%+ overheats the core AND maxes the ash.
 2. the ash takes a few minutes to settle in. as it does,
    expect to pull rods a few extra %% now and then to hold
    power -- that's normal upkeep, not a malfunction.
 3. move rods in ~5%% steps. after each step, WAIT and watch
    ρ. keep ρ between about -0.05 and +0.05. big pulls are
    how headlines happen.
 4. do NOT shut down from high power unless it's an actual
    emergency: the ash keeps working after shutdown, and the
    restart will fight you.
 5. if you're already in the pit (power sinking, ρ negative,
    fuel fine): EITHER rods further out in RUN and hover --
    the ash burns off and the reaction will surge as it does,
    so push rods back in the moment ρ goes past +0.1 --
    OR rods full in, walk away ~2 minutes, ash fades free.
 · in doubt: SCRAM. rods fall, breaker opens, you live. the
   xenon will make restart annoying. annoying beats glowing.

(click MANUAL again to close)"""
	t2.add_theme_font_size_override("font_size", 12)
	t2.add_theme_color_override("font_color", Color("#e8dcb8"))
	msc.add_child(t2)
	Sfx.play("click", -16.0)

## The pool, painted: water glow, five rods lerping gray -> Cherenkov
## blue with the reaction, blades sinking to their real insertion.
func _draw_pool() -> void:
	if rx == null or not is_instance_valid(rx):
		return
	var szp := _pool_view.size
	var glow := clampf(0.08 + rx.power * 0.8 + rx.temp / 100.0 * 0.4, 0.0, 1.0)
	var blue := Color(0.22, 0.78, 1.0)
	_pool_view.draw_rect(Rect2(Vector2.ZERO, szp),
		Color(0.02, 0.05 + glow * 0.12, 0.1 + glow * 0.3, 0.9))
	for i in 5:
		var x := szp.x * (0.15 + 0.175 * float(i))
		if glow > 0.05:
			_pool_view.draw_rect(Rect2(Vector2(x - 8, szp.y * 0.1),
				Vector2(16, szp.y * 0.8)), Color(blue.r, blue.g, blue.b, glow * 0.28))
		_pool_view.draw_rect(Rect2(Vector2(x - 4, szp.y * 0.12),
			Vector2(8, szp.y * 0.76)), Color(0.27, 0.29, 0.32).lerp(blue, glow))
	var bh := szp.y * 0.76 * clampf(rx.rods, 0.0, 1.0)
	for i in 4:
		var bx := szp.x * (0.2375 + 0.175 * float(i))
		_pool_view.draw_rect(Rect2(Vector2(bx - 3, szp.y * 0.12), Vector2(6, bh)),
			Color(0.12, 0.13, 0.16))
	_pool_view.draw_string(ThemeDB.fallback_font, Vector2(6, 16), "CORE POOL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4))

func close() -> void:
	queue_free()
	if not Game.dead and not _other_ui_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _pool_view != null:
		_pool_view.queue_redraw()
	if rx == null or not is_instance_valid(rx):
		close()
		return
	_arm_t = maxf(0.0, _arm_t - delta)
	if _vent_b:
		_vent_b.disabled = _arm_t <= 0.0
		_vent_b.text = "VENT (%.0fs)" % _arm_t if _arm_t > 0.0 else "VENT"
	# mode button highlight
	for i in _mode_btns.size():
		_mode_btns[i].modulate = Color(1, 1, 1, 1.0) if rx.mode == i else Color(1, 1, 1, 0.45)
	var rho: float = rx.rho_now()
	# the coach line: says exactly what the core is waiting for
	var coach := ""
	if rx._fuel <= 0.0:
		coach = "\n>> FUEL SPENT: ρ pinned at -1 until you LOAD URANIUM"
	elif rx._fuel < 12.0:
		coach = "\n>> FUEL LOW: ~%.0fs of burn left -- restock the hopper" % rx._fuel
	elif rx.mode == 1 and rho <= 0.0:
		coach = "\n>> ρ negative: rods below 65%% before power can rise"
	elif rx.mode == 1 and rx.power < 0.03:
		coach = "\n>> ρ positive -- power climbing, hold on"
	elif rx.mode == 1 and rx.temp < 15.0:
		coach = "\n>> warming: power heats the core toward RUN (150°C)"
	elif rx.mode == 2 and rho > 0.1:
		coach = "\n>> ρ HIGH: power is running away -- rods IN, now"
	elif rx.mode == 2 and rx.power > 0.75:
		coach = "\n>> high power piles heat AND ash -- ease rods IN, settle 50-70%"
	elif rx.mode == 2 and rx.power < 0.45 and rho <= 0.005 and rx.xenon < 0.4:
		coach = "\n>> to raise power: rods OUT until ρ ~ +0.05, ride it up,\n   rods back IN when POWER hits your number"
	elif rx.mode == 2 and absf(rho) < 0.03 and rx.power >= 0.45:
		coach = "\n>> cruising. hold ρ near 0: nudge rods only when POWER drifts"
	elif rho <= 0.0 and rx.xenon * 0.5 > (0.65 - rx.rods) * 0.9:
		# the XENON PIT: the poison alone is out-arguing the rods
		coach = "\n>> XENON (the ash) is smothering the reaction." \
			+ "\n   fuel is FINE. either pull rods further out (RUN)" \
			+ "\n   to burn the ash off -- then ease them back in --" \
			+ "\n   or shut down ~2 min and it fades on its own."
	_read.text = ("POWER    %6.1f %% rated\nρ        %+0.3f\nRODS     %5.1f %% in  (ordered %.0f%%)\nXENON    %5.1f %%\nCORE     %5.0f °C\nPRESS    %5.1f bar\nCOOLANT  %5.1f %%   flow %s\nBREAKER  %s\nOUTPUT   %+5.1f EU/s   charge %.0f/%.0f\nFUEL     %s" + coach) % [
		rx.power * 100.0, rho, rx.rods * 100.0, rx.rods_target * 100.0,
		rx.xenon * 100.0, rx.temp * 10.0, rx.press,
		rx.coolant, ["OFF", "HALF", "FULL"][rx.flow],
		"CLOSED (exporting)" if rx.breaker else "OPEN",
		rx.out_eu_s(), rx.buf, rx.buf_cap,
		_fuel_line()]
	_lamp("HI TEMP", rx.temp > 55.0, rx.temp > 80.0)
	_lamp("HI PRESS", rx.press > 65.0, rx.press > 85.0)
	_lamp("LO COOLANT", rx.coolant < 55.0, rx.coolant < 30.0)
	_lamp("XENON PEAK", rx.xenon > 0.5, rx.xenon > 0.75)
	_lamp("ρ POSITIVE", rho > 0.0, rho > 0.12)
	_lamp("TURB TRIP", rx.trip_t > 0.0, false)
	_lamp("FUEL LOW", rx._fuel < 15.0 and str(rx.in_slot["id"]) == "", rx._fuel <= 0.0)
	_lamp("SCRAM", rx._scram, false)

func _lamp(key: String, on: bool, urgent: bool) -> void:
	var l: Dictionary = _lamps[key]
	var col: Color = DARKL
	var fcol := Color("#6a6255")
	if urgent:
		col = RED if int(Time.get_ticks_msec() / 250) % 2 == 0 else DARKL
		fcol = Color.WHITE
	elif on:
		col = AMBER.darkened(0.15)
		fcol = Color("#1c1d20")
	l["style"].bg_color = col
	l["label"].add_theme_color_override("font_color", fcol)
