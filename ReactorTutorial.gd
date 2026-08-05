class_name ReactorTutorial
extends CanvasLayer
## The NUCLEAR REACTOR tutorial: better than the manual because it
## watches you do it. It spawns a reactor, walks the real startup one
## verified step at a time, and when you break something it tells you
## exactly WHY, wipes the core, spawns a fresh one, and restarts the
## sequence. Meltdowns are a lesson plan here, not a headline.

var rx = null
var _step := 0
var _obj: Label
var _why: Label
var _tip: Label            # the live rho ADVISOR: numbers + exact rod call
var _why_t := 0.0
var _hold_t := 0.0
var _gap := 0.0
var _done := false
var _neg_t := 0.0          # how long rho has been negative unattended
var _coach_cd := 0.0       # anti-spam for the negative-rho lecture
var _tip_t := 0.0

const STEPS := ["open", "fuel", "flow", "startup", "rods", "power",
	"warm", "run", "cruise", "breaker", "done"]

func _ready() -> void:
	layer = 12
	_obj = Label.new()
	_obj.anchor_left = 0.14
	_obj.anchor_right = 0.86
	_obj.anchor_top = 0.02
	_obj.anchor_bottom = 0.1
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.add_theme_font_size_override("font_size", 20)
	_obj.add_theme_color_override("font_color", Color("#ffd166"))
	_obj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_obj.add_theme_constant_override("outline_size", 5)
	add_child(_obj)
	_why = Label.new()
	_why.anchor_left = 0.14
	_why.anchor_right = 0.86
	_why.anchor_top = 0.1
	_why.anchor_bottom = 0.2
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.add_theme_font_size_override("font_size", 16)
	_why.add_theme_color_override("font_color", Color("#ff6a6a"))
	_why.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_why.add_theme_constant_override("outline_size", 5)
	add_child(_why)
	_tip = Label.new()
	_tip.anchor_left = 0.14
	_tip.anchor_right = 0.86
	_tip.anchor_top = 0.2
	_tip.anchor_bottom = 0.27
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 15)
	_tip.add_theme_color_override("font_color", Color("#7de8ff"))
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_tip.add_theme_constant_override("outline_size", 5)
	add_child(_tip)
	_spawn_reactor.call_deferred()

## The part the manual never does: live numbers with an exact rod call.
## rho = rod worth - xenon tax - heat tax; the advisor solves for the
## rod position that gives +0.05 (climb) and 0 (hold) RIGHT NOW.
func _advise(delta: float) -> void:
	_tip_t -= delta
	_coach_cd -= delta
	if rx == null or not is_instance_valid(rx) or _step < STEPS.find("rods"):
		_tip.text = ""
		return
	var rho: float = rx.rho_now()
	var xtax: float = rx.xenon * 0.5
	var htax: float = (rx.temp / 100.0) * 0.25
	var climb := clampf(0.65 - (0.05 + xtax + htax) / 0.9, 0.0, 1.0)
	var hold := clampf(0.65 - (xtax + htax) / 0.9, 0.0, 1.0)
	if _tip_t <= 0.0:
		_tip_t = 1.0
		_tip.text = "ρ %+.2f   rods %d%%  ·  climb: pull to ~%d%%  ·  hold: ~%d%%  ·  taxes: heat %.2f, xenon %.2f (they GROW as you run -- keep easing rods out)" \
			% [rho, int(rx.rods_target * 100.0), int(climb * 100.0),
			int(hold * 100.0), htax, xtax]
		if rx.temp > 25.0:
			# TEMPERATURE SCHOOL, live: heat in = power, heat out = flow.
			_tip.text += "\nTEMP %d°C · flow %s — heat IN is power, heat OUT is flow: raise FLOW to cool, trim power (rods in a nudge) to hold. cruise happy zone 150-700°C; past 800 you are negotiating with physics." \
				% [int(rx.temp * 10.0), ["OFF", "HALF", "FULL"][rx.flow]]
	# the watchdog: rho quietly negative while the rods sit still is the
	# classic silent stall -- power bleeds away and nothing explains it.
	# THIS explains it, fast, with the exact fix.
	if _step >= STEPS.find("power") and _step <= STEPS.find("cruise") \
			and rho < -0.01 and rx.rods_target > climb + 0.01:
		_neg_t += delta
		if _neg_t > 2.5 and _coach_cd <= 0.0:
			_coach_cd = 12.0
			_say_why("ρ is NEGATIVE (%+.2f) -- that's why power is bleeding away. Not a mystery: heat tax %.2f + xenon tax %.2f grew while your rods sat at %d%%. Pull rods to ~%d%% and ρ goes positive again." \
				% [rho, htax, xtax, int(rx.rods_target * 100.0), int(climb * 100.0)])
	else:
		_neg_t = 0.0

func _spawn_reactor() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var b = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - b.center).normalized()
	var side: Vector3 = up.cross(Vector3(0, 0, 1))
	if side.length() < 0.01:
		side = up.cross(Vector3(1, 0, 0))
	side = side.normalized()
	rx = EMachines.NuclearReactor.new()
	get_tree().current_scene.add_child(rx)
	rx.set_meta("placed_id", "nreactor")
	rx.set_meta("owner", Net.my_name())
	var pos: Vector3 = b.center + (up * float(b.radius))
	pos += side * 6.0
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	rx.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized() * -1.0)
		.orthonormalized(), pos)
	# fuel for the lesson (and the retries)
	if Inventory.res_count("uranium") < 3:
		Inventory.give("uranium", 3 - Inventory.res_count("uranium"))

## Explain the failure, wipe the core, hand out a fresh one, restart.
func _reset(reason: String) -> void:
	_say_why(reason + "  — resetting with a fresh core.")
	if rx != null and is_instance_valid(rx):
		rx.queue_free()
	rx = null
	_step = 0
	_hold_t = 0.0
	_gap = 1.5
	_spawn_reactor.call_deferred()
	Sfx.play("denied", -10.0)

func _say_why(t: String) -> void:
	_why.text = t
	_why_t = 9.0

func _process(delta: float) -> void:
	_why_t -= delta
	if _why_t <= 0.0:
		_why.text = ""
	_advise(delta)
	if _done:
		return
	_gap = maxf(0.0, _gap - delta)
	if _gap > 0.0:
		return
	if rx == null or not is_instance_valid(rx):
		if _step > 0:
			# it existed and now it doesn't: that's a meltdown
			_reset("MELTDOWN: heat outran cooling until temp/pressure hit the ceiling and containment let go")
		return
	# live coaching on dangerous trends, any step
	if rx.temp > 80.0:
		_say_why("core running HOT (%d°C): rods IN a step or flow FULL, or this ends loudly" % int(rx.temp * 10.0))
	# wrong-turn detection with reasons
	if _step < STEPS.find("breaker") and rx.trip_t > 0.0:
		_say_why("turbine TRIP: you closed the breaker before the steam was real (power x flow too weak). steer power up first")
	if rx._scram and _step > STEPS.find("startup"):
		_reset("SCRAM: everything dropped. right move in a real emergency -- but the startup is over, and the xenon it leaves makes restarts fight you")
		return
	if _step in [STEPS.find("power"), STEPS.find("warm")] \
			and rx.rho_now() < -0.08 and rx.rods_target <= 0.46:
		_reset("XENON PIT: the ash built faster than the startup-floor rods can argue, so power can only sink from here")
		return
	var id: String = STEPS[_step]
	_obj.text = "REACTOR SCHOOL %d/%d — %s" % [_step + 1, STEPS.size() - 1, _text(id)]
	if _check(id):
		_step += 1
		_gap = 1.2
		Sfx.play("learn", -14.0)
		if STEPS[_step] == "done":
			_done = true
			_obj.text = "REACTOR SCHOOL — LICENSED. it runs as long as it's fed and cooled. the manual covers the xenon ash; you've met everything else."
			Sfx.play("learn")

func _text(id: String) -> String:
	match id:
		"open":
			return "that machine is a NUCLEAR REACTOR. walk over and press F to open the control room."
		"fuel":
			return "FUEL section: LOAD URANIUM ROD. you're carrying three."
		"flow":
			return "COOLANT FLOW: set it FULL. no flow, no startup — steam is the whole business."
		"rods":
			return "pull RODS below 65% (aim ~55%). above 65% insertion ρ stays negative and power can only sink."
		"startup":
			return "MODE: STARTUP. interlocks now let the rods move, down to a 45% floor."
		"power":
			return "keep ρ POSITIVE (advisor below shows the exact rod % -- it changes as the core heats). power climbs while ρ > 0, bleeds while ρ < 0. wait for POWER ≥ 3%."
		"warm":
			return "the reaction heats the core -- and HEAT TAXES ρ. as temp climbs you must keep pulling rods out to stay positive (the advisor tracks it). reach 150°C."
		"run":
			return "MODE: RUN. the startup floor is gone — full rod authority."
		"cruise":
			return "steer power into 45–75% and HOLD it 6s: rods toward the advisor's CLIMB number to rise, toward HOLD to level off. there is no power dial — you ARE the dial."
		"breaker":
			return "close the BREAKER. steam is real now: the turbine syncs and you EXPORT."
	return ""

func _check(id: String) -> bool:
	match id:
		"open":
			return get_tree().get_first_node_in_group("reactor_ui") != null
		"fuel":
			return rx._fuel > 0.0 or str(rx.in_slot["id"]) == "uranium"
		"flow":
			return rx.flow == 2
		"startup":
			return rx.mode >= 1
		"rods":
			return rx.rods_target <= 0.65
		"power":
			return rx.power >= 0.03
		"warm":
			return rx.temp >= 15.0
		"run":
			return rx.mode == 2
		"cruise":
			if rx.power >= 0.45 and rx.power <= 0.75:
				_hold_t += get_process_delta_time()
			else:
				_hold_t = 0.0
			return _hold_t >= 6.0
		"breaker":
			return rx.breaker
	return false
