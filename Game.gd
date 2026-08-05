extends Node
## Autoload "Game". Run mode, score, and the noodle-god wrath meter.
## You do NOT die from lack of destruction anymore -- breaking earns
## coins. But the megalophobia destruction noodle gods grow angry when
## you loiter near giant structures without destroying. Max wrath ->
## you are turned into the Pythagorean theorem.

signal changed
signal transformed   # pythagoras "death"
signal killed        # slain by aliens
signal perma         # permadeath: save erased

enum Mode { ON_FOOT, IN_ROCKET }

const WRATH_MAX := 100.0
const HEALTH_MAX := 100.0

var mode: int = Mode.ON_FOOT
var score: int = 0
var wrath: float = 0.0          # rises ONLY from unholy acts (hidden meter)
var health: float = HEALTH_MAX
var dead: bool = false
var trapped: bool = false       # caught by TIN 618
var dilation: float = 1.0       # time-dilation factor near the black hole
var _since_hit: float = 0.0
var _salad_t: float = -1.0   # seconds since eating a salad (-1 = none)

func eat_salad() -> void:
	_salad_t = 0.0
	heal(5.0)   # barely anything... at first
	Sfx.play("eat")

func salad_active() -> bool:
	return _salad_t >= 0.0

# ------------------------------------------------------------- calendar
## One in-game day = 10 minutes of playtime. Week starts Monday.
const DAY_SECS := 600.0
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

func day_index() -> int:
	return int(playtime / DAY_SECS)

func weekday() -> int:
	return day_index() % 7

func weekday_name() -> String:
	return WEEKDAYS[weekday()]

const MONTHS := ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]
const MDAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static func is_leap_year(y: int) -> bool:
	return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)

static func days_in_month(m: int, y: int) -> int:
	return 29 if m == 1 and is_leap_year(y) else int(MDAYS[m])

static func days_in_year(y: int) -> int:
	return 366 if is_leap_year(y) else 365

## Day 0 = Monday, January 1, Year 1. Leap years follow the usual rule.
static func date_of(di: int) -> Dictionary:
	var y := 1
	while di >= days_in_year(y):
		di -= days_in_year(y)
		y += 1
	var m := 0
	while di >= days_in_month(m, y):
		di -= days_in_month(m, y)
		m += 1
	return {"year": y, "month": m, "day": di + 1}

## First day index of a given month (for calendar pages).
static func month_start_day(m: int, y: int) -> int:
	var di := 0
	for yy in range(1, y):
		di += days_in_year(yy)
	for mm in m:
		di += days_in_month(mm, y)
	return di

func date_text() -> String:
	var d := date_of(day_index())
	return "%s, %s %d, Year %d" % [weekday_name(), MONTHS[int(d.month)], int(d.day), int(d.year)]

## 24h clock inside the 10-minute day.
func clock_text() -> String:
	var mins := int(fposmod(playtime, DAY_SECS) / DAY_SECS * 24.0 * 60.0)
	return "%02d:%02d" % [mins / 60, mins % 60]

## The UFO market comes on Tuesdays, and SOMETIMES Saturdays.
## Seeded by day index -- deterministic, so the calendar can predict it.
func ufo_on_day(di: int) -> bool:
	var wd := di % 7
	if wd == 1:
		return true
	if wd == 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = di
		return rng.randf() < 0.5
	return false

func is_ufo_day() -> bool:
	return ufo_on_day(day_index())

func pet_following() -> bool:
	# benefits require the pet actually AT your side: following AND nearby
	var pet = get_tree().get_first_node_in_group("pet")
	if pet == null or not is_instance_valid(pet) or pet.staying:
		return false
	var p = get_tree().get_first_node_in_group("player")
	return p != null and pet.global_position.distance_to(p.global_position) < 30.0

var spawn_pos: Vector3 = Vector3.ZERO
var spawn_up: Vector3 = Vector3.UP
var has_saved_spawn: bool = false   # a save carried its own spawn point
var tutorial_done: bool = false     # interactive tutorial finished/skipped
var tutorial_session: bool = false  # throwaway tutorial world (set by Title, never saved)
var tutorial_mode: String = "basic" # which lesson: "basic" | "reactor"
var god_standby_until: float = -1.0 # after a death the god broods instead of acting
var god_cycles: int = 0             # every brood it wakes STRONGER and pettier
var world_seed: int = 0             # fixes terrain layout across reloads
# What the shop will sell right now. ["*"] = everything (normal play);
# [] = nothing; otherwise an allowlist of ids. The tutorial drives this so
# a new player can't blow their coins on the wrong thing mid-lesson.
var tutorial_allow: Array = ["*"]

func tut_can_buy(id: String) -> bool:
	return tutorial_allow.has("*") or tutorial_allow.has(id)

# Per-world LAN hosting rules (persisted in the save; host changes stick).
var host_cfg: Dictionary = {
	"allow_cheats": false, "allow_chat": true, "friendly_fire": false,
	"break_others": true, "port": 24545,
}
var trials_done: bool = false       # temple guardians dead -> maze door open

# --- locator gadget: a temporary green ping the HUD points at ---
var locator_mode: int = 0           # 0 alien ship · 1 invaders · 2 shadow temple · 3 ufo · 4 rifts · 5 mine · 6 connect 4
var locator_targets: Array = []     # Vector3 list -- multi-ping modes fill many
var locator_label: String = ""
var locator_until: float = -1.0
var locator_lie: float = 1.0   # displayed-distance multiplier (cosmic readings)
var locator_planet := ""   # planet-name lock: ping tracks it while it moves
var eh_log_t: float = 0.0      # EVENT HORIZON log: accumulated listen time
var eh_log_done: bool = false  # heard it all -- silent until world restart
var permadead: bool = false

# --- gravity zone for interior pocket dimensions ---
var zone: String = ""        # "" radial | "flat" fixed down | "zero" none
var zone_g: float = 9.0

var timewarp: float = 1.0    # rocket time acceleration (1/2/3x; 5/10x coasting)
var board_lock: float = 0.0  # playtime before which re-boarding is blocked

# --- progression flags ---
var door_open: bool = false   # euclid temple door (opens forever)
var mind_core: bool = false   # unlocks the pyramid
var playtime: float = 0.0     # for time-rift snapshots
var cheated: bool = false     # any cheat = save branded illegitimate forever
var hardcore: bool = false    # run mode: ANY death is permadeath
var godmode: bool = false     # cheat: no damage at all
var inf_fuel: bool = false    # cheat: tanks never drain
var creative: bool = false    # cheat: creative inventory tab
var keep_inv: bool = false    # cheat: no coin loss on death
var free_craft: bool = false  # cheat: buy/craft anything, pay nothing

## Irreversible death: erase the save. Black hole, or a Permadeath Apple.
## An Anti-Permadeath Charm in the hotbar is consumed to survive instead.
func permadeath() -> void:
	if permadead:
		return
	if Inventory.consume_charm():
		# saved by the charm: respawn, keep the rest of your items
		health = HEALTH_MAX
		dead = false
		mode = Mode.ON_FOOT
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("respawn_at"):
			p.respawn_at(spawn_pos, spawn_up)
		changed.emit()
		return
	permadead = true
	dead = true
	Save.delete_slot(Save.current_slot)
	perma.emit()
	changed.emit()

func set_spawn(pos: Vector3, up: Vector3) -> void:
	spawn_pos = pos
	spawn_up = up

## Strip carried items (keep coins + character) and send you to spawn.
func reset_character() -> void:
	# the KEEP INVENTORY cheat honors respawns too, not just deaths
	if not keep_inv:
		Inventory.lose_half()   # resetting costs you 50% of carried coins too
		Inventory.hotbar = []
		for i in 5:
			Inventory.hotbar.append(Inventory.empty_slot())
		Inventory.selected = 0
		Inventory.fuel = 0.0
		Inventory.jet_fuel = 0.0
		Inventory.has_jetpack = false
		Inventory.has_rcs = false
	health = HEALTH_MAX
	dead = false
	mode = Mode.ON_FOOT
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("respawn_at"):
		p.respawn_at(spawn_pos, spawn_up)
	Inventory.changed.emit()
	changed.emit()

func report_mega() -> void:
	pass   # loitering no longer angers the gods

## The gods rage at unholy deeds (leaving the universe, alien starships...).
func anger(amount: float) -> void:
	if dead:
		return
	wrath = minf(WRATH_MAX, wrath + amount)
	changed.emit()

var wrath_event: bool = false   # the noodle god is currently descending

## The descent ended: caught=true -> the pythagorean transformation,
## with full geometric ceremony first.
func wrath_event_over(caught: bool) -> void:
	wrath_event = false
	if not caught:
		return
	if hardcore:
		permadeath()
		changed.emit()
		return
	var cs := get_tree().current_scene
	if cs:
		cs.add_child(PythagorasCinematic.new())
	else:
		complete_transform()

## The proof is complete: the usual end screen takes it from here.
func complete_transform() -> void:
	dead = true
	god_standby_until = playtime + 180.0   # satisfied, for a while
	god_cycles += 1
	wrath = WRATH_MAX * 0.5                # the lesson bought you half a pardon
	if not keep_inv:
		Inventory.lose_half()
	transformed.emit()
	changed.emit()

var _hurt_sfx_t: float = 0.0

## Earth's four cities: [{dir, vibe, name, tint}]. Filled by worldgen,
## read by every human deciding where home is.
var earth_cities: Array = []
var earth_body = null
var earth_pop_target: int = 0   # census at worldgen: repopulation aims here
var player_proxy: Vector3 = Vector3.ZERO   # where the player 'is' on the
var has_proxy: bool = false                # planet while inside a pocket room

var death_cause := ""   # what got you -- shown on the death screen

func hurt(d: float, vaporize: bool = false, cause: String = "") -> void:
	if dead or godmode:
		return
	d *= 1.0 - Inventory.armor_reduction()   # worn armor soaks its share
	health = maxf(0.0, health - d)
	_since_hit = 0.0
	if playtime - _hurt_sfx_t > 0.55:   # throttle for per-frame burns
		_hurt_sfx_t = playtime
		Sfx.play("hurt", -16.0)
	if health <= 0.0:
		if hardcore:
			permadeath()   # hardcore: every death is THE death (charm can save)
			changed.emit()
			return
		dead = true
		death_cause = cause if cause != "" else "ALIENS"
		# even the god observes a mourning period. red, silent, watching.
		# and every time it broods, it wakes a little worse.
		god_standby_until = playtime + 180.0
		god_cycles += 1
		if not keep_inv:
			Inventory.lose_half()   # drop 50% of carried coins on death
			_spill_hotbar(vaporize)
		killed.emit()
	changed.emit()

## Death spills the hotbar -- and the jetpack off your back -- where you
## fell. Fly (well, walk) back and reclaim them. Suns, gas giants and
## black holes vaporize the lot instead.
func _spill_hotbar(vaporize: bool) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if Inventory.has_jetpack:
		if not vaporize and p and p.is_inside_tree():
			var jid := "jetpack"
			if Inventory.jet_max >= 1000.0:
				jid = "jetpack3"
			elif Inventory.jet_max >= 500.0:
				jid = "jetpack2"
			var jd := ItemDrop.new()
			jd.setup(jid, 1)
			p.get_parent().add_child(jd)
			jd.global_position = p.global_position \
				+ Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		Inventory.has_jetpack = false
		Inventory.jet_fuel = 0.0
		Inventory.jet_max = 100.0
		Inventory.jet_power = 1.0
		Inventory.jet_on = false
	for i in Inventory.hotbar.size():
		var sid := str(Inventory.hotbar[i].get("id", ""))
		if sid == "" or sid == "fists":
			continue
		if not vaporize and p and p.is_inside_tree():
			var dr := ItemDrop.new()
			dr.setup(sid, maxi(1, int(Inventory.hotbar[i].get("n", 1))))
			p.get_parent().add_child(dr)
			dr.global_position = p.global_position \
				+ Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		Inventory.hotbar[i] = Inventory.empty_slot()
	Inventory.changed.emit()

func heal(a: float) -> void:
	if dead:
		return
	health = minf(HEALTH_MAX, health + a)
	changed.emit()

func _process(delta: float) -> void:
	if dead:
		return
	playtime += delta
	if inf_fuel:
		Inventory.fuel = Inventory.fuel_max
		Inventory.jet_fuel = Inventory.jet_max
	# the gods do NOT forgive with time. only tribute (noodles) helps.
	# a FOLLOWING pet warms the heart: +2% regen
	var pet_mult := 1.02 if pet_following() else 1.0
	_since_hit += delta
	if _since_hit > 4.0 and health < HEALTH_MAX:  # slow regen out of combat
		health = minf(HEALTH_MAX, health + 5.0 * pet_mult * delta)

	# --- salad regen curve: nothing for 3s, then it ACCELERATES to a
	# ridiculous peak, then winds down and ends after about a minute ---
	if _salad_t >= 0.0:
		_salad_t += delta
		var t := _salad_t
		if t > 3.0:
			var rate := minf(pow(t - 3.0, 1.7) * 0.35, 22.0)   # accelerating ramp
			if t > 55.0:
				rate *= clampf(1.0 - (t - 55.0) / 15.0, 0.0, 1.0)   # winding down
			health = minf(HEALTH_MAX, health + rate * pet_mult * delta)
		if t > 70.0:
			_salad_t = -1.0
	# MAX WRATH: the god COMES for you (a whole event, not an instant death)
	if wrath >= WRATH_MAX and not wrath_event and playtime >= god_standby_until:
		wrath_event = true
		var cs := get_tree().current_scene
		if cs and cs.has_method("noodle_wrath_event"):
			cs.noodle_wrath_event()
		else:
			wrath_event_over(true)
	changed.emit()

signal broke   # something, somewhere, got smashed. worms have ears.

func register_break(size: Vector3, coins: int) -> void:
	if dead:
		return
	broke.emit()
	var vol := clampf(size.x * size.y * size.z, 1.0, 200.0)
	score += int(10.0 + vol)
	Inventory.add_coins(coins if coins > 0 else int(1.0 + vol * 0.5))
	changed.emit()

func reset() -> void:
	mode = Mode.ON_FOOT
	score = 0
	tutorial_done = false
	wrath = 0.0
	health = HEALTH_MAX
	dead = false
	trapped = false
	permadead = false
	dilation = 1.0
	timewarp = 1.0
	zone = ""
	zone_g = 9.0
	door_open = false
	mind_core = false
	cheated = false
	godmode = false
	inf_fuel = false
	creative = false
	keep_inv = false
	free_craft = false
	playtime = 0.0
	_since_hit = 0.0
	_salad_t = -1.0
	Inventory.reset()
	changed.emit()
