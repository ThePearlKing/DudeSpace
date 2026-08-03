class_name Tutorial
extends CanvasLayer
## Interactive tutorial: the ACTUAL early game, start to orbit.
## Scavenge crates for startup coins -> real mine -> buy your own furnace
## and sell station -> run the economic loop -> armor -> jetpack + fuel ->
## rocket + fuel -> fly to the moon. Nothing is pre-built or given away;
## every machine and tool is earned and bought like in a real run.
## A green HUD ping leads to location objectives. Steps advance only when
## the player actually does the thing, with a pause between steps to read.

## Fixed surface direction of Tutoria's mine (Main builds it there;
## the tutorial points its ping at the same spot).
const ORE_DIR := Vector3(1.0, 0.25, 0.3)

const SESSION_STEPS := ["walk", "look", "jump", "crates", "findmine", "mine",
	"exit", "buyfurnace", "smelt", "buysell", "sell", "loop", "boots",
	"buyjet", "fueljet", "jet", "moonhop", "rocket", "fuelrocket", "board",
	"liftoff", "flyrocket", "land"]
const BASIC_STEPS := ["walk", "look", "jump", "inv"]

const MOVE_SECS := 4.0
const LOOK_PX := 600.0
const JUMPS := 3
const STEP_GAP := 3.5    # seconds the "done" confirmation stays up
const CRATE_COINS := 100
const ORE_GOAL := 12
const SMELT_GOAL := 12
const SELL_GOAL := 90
const LOOP_COINS := 480  # boots 40 + jetpack 130 + 2 jet fuel 50 + rocket 150 + 2 rocket fuel 60 + slack

var _steps: Array = []
var _step: int = 0
var _move_t: float = 0.0
var _look_px: float = 0.0
var _jumps: int = 0
var _space_held: bool = false
var _coins_gained: int = 0
var _last_coins: int = 0
var _base_gained: int = 0   # _coins_gained snapshot at step entry
var _gap: float = 0.0       # pause between steps so each one can be read
var _step_t: float = 0.0    # time the current step has been on screen
var _done_text: String = ""
var _obj: Label
var _why: Label

func _ready() -> void:
	layer = 15
	add_to_group("tutorial")
	_steps = SESSION_STEPS if Game.tutorial_session else BASIC_STEPS
	_last_coins = Inventory.coins

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.custom_minimum_size = Vector2(1500, 0)
	col.position = Vector2(-750, 20)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_obj = Label.new()
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.add_theme_font_size_override("font_size", 44)
	_obj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_obj.add_theme_constant_override("outline_size", 14)
	_obj.modulate = Color("#aaffc0")
	col.add_child(_obj)

	_why = Label.new()
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.add_theme_font_size_override("font_size", 26)
	_why.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_why.add_theme_constant_override("outline_size", 10)
	_why.modulate = Color(1, 1, 1, 0.92)
	col.add_child(_why)

func _input(event: InputEvent) -> void:
	# only count looking while the LOOK step is actually up -- otherwise
	# it is pre-completed before the player ever reads it
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _gap <= 0.0 and _step < _steps.size() and _steps[_step] == "look":
		_look_px += event.relative.length()

func _process(delta: float) -> void:
	if Game.dead or _step >= _steps.size():
		return
	if Inventory.coins > _last_coins:
		_coins_gained += Inventory.coins - _last_coins
	_last_coins = Inventory.coins

	# breathing room: hold the "done" confirmation, ignore inputs meanwhile
	if _gap > 0.0:
		_gap -= delta
		_obj.text = _done_text
		_why.text = ""
		_space_held = Input.is_key_pressed(KEY_SPACE)
		return

	var id: String = _steps[_step]
	Game.tutorial_allow = _allow_for(id)
	# every step stays readable for 2s before it can complete
	_step_t += delta
	if _step_t < 2.0:
		_obj.text = "TUTORIAL %d/%d — %s" % [_step + 1, _steps.size(), _obj_text(id)]
		_why.text = _why_text(id)
		_space_held = Input.is_key_pressed(KEY_SPACE)
		return
	match id:
		"walk":
			if Game.mode == Game.Mode.ON_FOOT and (Input.is_key_pressed(KEY_W)
					or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S)
					or Input.is_key_pressed(KEY_D)):
				_move_t += delta
			if _move_t >= MOVE_SECS:
				_advance()
		"look":
			if _look_px >= LOOK_PX:
				_advance()
		"jump":
			var sp := Input.is_key_pressed(KEY_SPACE)
			if sp and not _space_held and Game.mode == Game.Mode.ON_FOOT:
				_jumps += 1
			_space_held = sp
			if _jumps >= JUMPS:
				_advance()
		"crates":
			if _coins_gained - _base_gained >= CRATE_COINS:
				_advance()
		"findmine":
			_ping(_mine_mouth(), "MINE ENTRANCE")
			var pf = get_tree().get_first_node_in_group("player")
			if pf and pf.global_position.distance_to(_mine_mouth()) < 10.0:
				_advance()
		"mine":
			_ping(_mine_chamber(), "ORE VEINS")
			if Inventory.res_count("raw_ingot") >= ORE_GOAL:
				_advance()
		"exit":
			var b = Universe.body_named("Tutoria")
			var pe = get_tree().get_first_node_in_group("player")
			if b and pe and pe.global_position.distance_to(b.center) > b.radius - 2.0:
				_advance()
		"buyfurnace":
			if _count_placed(Furnace) >= 1:
				_advance()
		"smelt":
			var f := _placed_node(Furnace)
			if f:
				_ping(f.global_position, "YOUR FURNACE")
			if Inventory.res_count("ingot") >= SMELT_GOAL:
				_advance()
		"buysell":
			if _count_placed(Coinifier) >= 1:
				_advance()
		"sell":
			var c := _placed_node(Coinifier)
			if c:
				_ping(c.global_position, "YOUR SELL STATION")
			if _coins_gained - _base_gained >= SELL_GOAL:
				_advance()
		"loop":
			if Inventory.coins >= LOOP_COINS:
				_advance()
		"boots":
			if str(Inventory.equip.get("boots", "")) != "":
				_advance()
		"buyjet":
			if Inventory.has_jetpack:
				_advance()
		"fueljet":
			if Inventory.jet_fuel >= Inventory.jet_max - 0.5:
				_advance()
		"jet":
			if Inventory.jet_on:
				_advance()
		"rocket":
			if get_tree().get_nodes_in_group("rocket").size() > 0:
				_advance()
		"fuelrocket":
			if Inventory.fuel >= Inventory.fuel_max - 0.5:
				_advance()
		"moonhop":
			var moon = Universe.body_named("Tutoria Moon")
			if moon == null:
				_advance()
			else:
				_ping(moon.center, "THE MOON")
				if _near_body(moon):
					_advance()
		"board":
			if Game.mode == Game.Mode.IN_ROCKET:
				_advance()
		"liftoff":
			var rp0 = Universe.body_named("Rocketia")
			var rk := _piloted_rocket()
			if rp0:
				_ping(rp0.center, "ROCKETIA")
			if rk and rp0:
				var to: Vector3 = (rp0.center - rk.global_position).normalized()
				# moving, and drifting AT the target: aim + burn, no wasteful climb
				if rk.vel.length() > 8.0 and rk.vel.normalized().dot(to) > 0.85:
					_advance()
		"flyrocket":
			var rp = Universe.body_named("Rocketia")
			if rp == null:
				_finish("TUTORIAL COMPLETE")
				return
			_ping(rp.center, "ROCKETIA")
			if _near_body(rp, 60.0):
				_advance()
		"land":
			var rp2 = Universe.body_named("Rocketia")
			var pl = get_tree().get_first_node_in_group("player")
			if rp2 == null or (pl and Game.mode == Game.Mode.ON_FOOT
					and pl.global_position.distance_to(rp2.center) < rp2.radius + 6.0):
				_finish("TUTORIAL COMPLETE -- Esc, Save & Quit returns to the title")
				return

	# anti-softlock: once a fuel lesson is passed, never let that tank
	# strand the player -- the tutorial quietly tops it back up
	if Game.tutorial_session:
		if _step > _steps.find("fueljet") and Inventory.jet_fuel < 20.0:
			Inventory.jet_fuel = 50.0
			_flash("jet fuel topped up -- TUTORIAL ONLY, real runs never refill you")
		if _step > _steps.find("fuelrocket") and Inventory.fuel < 20.0:
			Inventory.fuel = 60.0
			_flash("rocket fuel topped up -- TUTORIAL ONLY, real runs never refill you")
	if _step >= _steps.size():
		return
	_obj.text = "TUTORIAL %d/%d — %s" % [_step + 1, _steps.size(), _obj_text(id)]
	_why.text = _why_text(id)

func _obj_text(id: String) -> String:
	match id:
		"walk": return "Move around with WASD"
		"look": return "Look around with the mouse"
		"jump": return "Jump with SPACE (%d / %d)" % [_jumps, JUMPS]
		"crates": return "Smash the glowing crates: collect %d coins (%d / %d)" \
			% [CRATE_COINS, maxi(0, _coins_gained - _base_gained), CRATE_COINS]
		"findmine": return "Follow the green marker to the MINE ENTRANCE (the glowing ring)"
		"mine": return "Jump down the shaft: smash the purple veins for Raw Ingot (%d / %d)" \
			% [Inventory.res_count("raw_ingot"), ORE_GOAL]
		"exit": return "Press F on the glowing MINE EXIT gate to return to the surface"
		"buyfurnace": return "Press E: buy a FURNACE (Machines tab, 40 coins), right-click to place it"
		"smelt": return "Press F on your furnace: load the raw ore, smelt %d ingots (%d / %d)" \
			% [SMELT_GOAL, Inventory.res_count("ingot"), SMELT_GOAL]
		"buysell": return "Press E: buy a SELL STATION (Machines tab, 40 coins), place it next to the furnace"
		"sell": return "Press F on the Sell Station: load your ingots (%d / %d coins earned)" \
			% [maxi(0, _coins_gained - _base_gained), SELL_GOAL]
		"loop": return "Run the loop -- mine, smelt, sell -- until you hold %d coins (%d / %d)" \
			% [LOOP_COINS, Inventory.coins, LOOP_COINS]
		"boots": return "Press E: buy GRAV BOOTS (Armor tab), drag them onto the FEET slot"
		"buyjet": return "Press E: buy a JETPACK (Gear tab, 130 coins), right-click to strap it on"
		"fueljet": return "Press E: buy 2x JET FUEL (25 coins each), right-click both -- fill the tank FULL (%d / %d)" \
			% [int(Inventory.jet_fuel), int(Inventory.jet_max)]
		"jet": return "Press J to ignite the jetpack -- SPACE climbs, C descends"
		"moonhop": return "Jetpack to the marked MOON: aim up, hold SPACE, commit"
		"rocket": return "Press E: buy a ROCKET (Rocket tab, 150 coins), right-click to place it upright"
		"fuelrocket": return "Press E: buy 2x ROCKET FUEL (30 each), right-click NEAR the rocket -- fill the tank FULL (%d / %d)" \
			% [int(Inventory.fuel), int(Inventory.fuel_max)]
		"board": return "Press F on the rocket to board it"
		"liftoff": return "Tilt the yellow nose onto the marker with WASD, hold SPACE until P sits on it too"
		"flyrocket": return "Coast to ROCKETIA -- small tilts + short burns keep P (prograde) on the marker"
		"land": return "Ride it down to the surface and press F to hop out"
		"inv": return "Press E to open your inventory and the shop"
	return ""

func _why_text(id: String) -> String:
	match id:
		"walk":
			return "Standard first-person movement. Every planet pulls with its own gravity, so get a feel for your weight before relying on machines to move you."
		"look":
			return "The crosshair is how you mine, aim, buy, and interact. V zooms in when something is far away."
		"jump":
			return "Gravity is real here: small worlds barely hold you down, heavy ones pin you. This planet is gentle."
		"crates":
			return "Fresh starts are broke. Crates scattered on every planet hold your first coins -- scavenging them is how every run kickstarts, because machines cost money."
		"findmine":
			return "Coins from crates run out. The real economy is ore -- most planets hide a mine, and a purple glowing ring marks the mouth of the shaft."
		"mine":
			return "Veins grow back over time, so mines never run dry. Richer planets grow richer ore -- iridium, ultima -- but their mines are guarded."
		"exit":
			return "Every mine has a marked exit gate so you never climb the shaft. Gates teleport you -- you will meet much bigger ones out there."
		"buyfurnace":
			return "Raw ore sells for nothing -- it must be smelted first. The E menu is where everything is bought and crafted. This furnace is YOURS: the first machine of your first base."
		"smelt":
			return "Furnaces cook raw ore into ingots over time and keep working while you do other things. Come back and take the finished ingots out."
		"buysell":
			return "Machines placed near each other become a base. Later, funnels and wires connect them so ore flows in and coins flow out with no clicks at all."
		"sell":
			return "The Sell Station pays per item, one at a time. Ingots are worth 8 coins each -- this is your income engine."
		"loop":
			return "Mine, smelt, sell. That loop funds everything in the game: armor, jetpacks, rockets, and the machines that eventually automate the loop itself."
		"boots":
			return "Armor soaks damage -- each worn piece cuts it by a percentage. Materials rank up: iron, then ultima, then prism. Boots are the cheap start."
		"buyjet":
			return "The jetpack is your first flight. Strapping it on is permanent gear, not a hotbar item."
		"fueljet":
			return "Nothing flies for free: the jetpack burns jet fuel, shown as the blue bar. Canisters add 50 each -- always top up BEFORE flying. Out here the tutorial refills you if you run dry; the real game never will."
		"jet":
			return "J toggles the jetpack. It drinks fuel while lit, so switch it off when your feet work fine."
		"moonhop":
			return "A jetpack can cross to a nearby moon, but that is its limit -- watch how much of the blue bar this one hop eats. Real travel needs a rocket."
		"rocket":
			return "The rocket is the single most important purchase in the game -- every other planet, mine, and secret is out of jetpack range. Place it on open ground."
		"fuelrocket":
			return "Rockets have their own tank, separate from jet fuel. Fill it FULL before boarding -- in the real game, running dry between worlds strands you in the void, and nobody comes to refill you."
		"board":
			return "F boards and exits. Once inside, the rocket is your body: it takes the hits, it holds the fuel."
		"liftoff":
			return "Never climb straight up -- that wastes fuel. Point the nose AT where you want to go and burn until the green P marker (your drift direction) covers the target. The instrument legend on screen explains every marker."
		"flyrocket":
			return "In space, coasting is free -- momentum carries you. Burn only to correct: if P slides off the marker, tilt and give a short burst. Long coast? Press 1-9 (or 0 for 10x) to TIME WARP -- the chips at the top show your setting. Burning cancels warp."
		"land":
			return "No landing ceremony here -- gravity does the work, just let it pull you in. F hops out, F boards again. Your rocket stays parked where you leave it."
		"inv":
			return "Everything you buy or craft lands in the 5 hotbar slots. Right-click uses or places whatever is selected."
	return ""

# ------------------------------------------------------------- helpers

## Shop allowlist for the current step: buying is locked to exactly what
## the lesson needs, so starter coins can't be wasted. Normal saves and
## the finished tutorial leave the shop fully open.
func _allow_for(id: String) -> Array:
	if not Game.tutorial_session:
		return ["*"]
	match id:
		"buyfurnace": return ["furnace"]
		"buysell": return ["coinifier"]
		"boots": return ["boots"]
		"buyjet": return ["jetpack"]
		"fueljet": return ["jetfuel"]
		"moonhop": return ["jetfuel"]
		"rocket": return ["rocket"]
		"fuelrocket": return ["fuel"]
		"board", "liftoff", "flyrocket", "land": return ["fuel", "jetfuel"]
	return []   # non-shopping steps: window-shop, spend nothing

func _mine_mouth() -> Vector3:
	var b = Universe.body_named("Tutoria")
	if b == null:
		return Vector3.ZERO
	return b.center + ORE_DIR.normalized() * (b.radius + 0.5)

func _mine_chamber() -> Vector3:
	var b = Universe.body_named("Tutoria")
	if b == null:
		return Vector3.ZERO
	return b.center + ORE_DIR.normalized() * (b.radius - 19.0)

func _piloted_rocket() -> Rocket:
	for r in get_tree().get_nodes_in_group("rocket"):
		if r is Rocket and r.piloted:
			return r
	return null

func _near_body(b, pad: float = 30.0) -> bool:
	var p = get_tree().get_first_node_in_group("player")
	if p and p.global_position.distance_to(b.center) < b.radius + pad:
		return true
	for r in get_tree().get_nodes_in_group("rocket"):
		if is_instance_valid(r) and r.global_position.distance_to(b.center) < b.radius + pad:
			return true
	return false

## Player altitude above a body's surface (rocket rides count).
func _alt(b) -> float:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return 0.0
	return p.global_position.distance_to(b.center) - b.radius

func _flash(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash(msg)

## Green HUD diamond on the current objective (kept alive while relevant).
func _ping(pos: Vector3, label: String) -> void:
	Game.locator_targets = [pos]
	Game.locator_label = label
	Game.locator_until = Game.playtime + 2.0

func _placed_node(type) -> Node3D:
	for n in get_tree().get_nodes_in_group("machine"):
		if is_instance_valid(n) and is_instance_of(n, type):
			return n
	return null

func _count_placed(type) -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("machine"):
		if is_instance_valid(n) and is_instance_of(n, type):
			c += 1
	return c

func _inv_open() -> bool:
	for n in get_tree().get_nodes_in_group("closable_ui"):
		if n is InventoryUI and n.visible:
			return true
	return false

func _advance() -> void:
	_done_text = "✓ %s" % _obj_text(_steps[_step])
	_step += 1
	_base_gained = _coins_gained
	_step_t = 0.0
	_gap = STEP_GAP
	Game.locator_until = -1.0
	Sfx.play("learn", -12.0)

func _finish(msg: String) -> void:
	Game.tutorial_done = true
	Game.tutorial_allow = ["*"]
	Game.locator_until = -1.0
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash(msg)
	Sfx.play("learn")
	queue_free()
