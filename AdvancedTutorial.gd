class_name AdvancedTutorial
extends CanvasLayer
## THE ADVANCED TUTORIAL: the middle of the game, taught the same way the
## basic one teaches the start -- by watching you actually do it.
##
## It hands you the early game (coins, iron, iridium, ore, ice, sulfur)
## so no time is spent re-learning the pickaxe, and then walks the whole
## machine chain: the Chemistry Handbook, power and wires, the crusher's
## double yield, alloys, the glassware bench, the chem lab, automation,
## and -- last, because it is the exam -- the nuclear reactor, which
## hands off to the reactor lesson itself.
##
## Every step that has a recipe behind it CIRCLES that recipe in the
## handbook (ManualUI.point_at), so the book is a working instrument in
## this tutorial rather than a wall of text.

const STEPS := ["kit", "handbook", "read", "generator", "coal", "crusher",
	"wire", "crush", "smelt", "alloy", "bronze", "bench", "water", "sulfuric",
	"silica", "chemlab", "carbon", "steel", "automate", "reactor"]

## What each step wants circled in the handbook.
const CIRCLES := {
	"read": ["bronze", "sulfuric"],
	"alloy": ["bronze", "brass", "steel"],
	"bronze": ["bronze"],
	"bench": ["water", "carbon"],
	"water": ["water"],
	"sulfuric": ["sulfuric", "oxygen", "water"],
	"silica": ["silica"],
	"chemlab": ["sulfuric", "silica"],
	"carbon": ["carbon"],
	"steel": ["steel"],
}

const STEP_GAP := 3.5      # seconds the "done" confirmation stays up
const READ_SECS := 5.0     # how long the handbook must stay open on step 3
const DUST_GOAL := 6
const COPPER_GOAL := 6
const TIN_GOAL := 2
const BRONZE_GOAL := 4
const SULFURIC_GOAL := 4
const SILICA_GOAL := 2
const CARBON_GOAL := 2
const STEEL_GOAL := 6

var _step: int = 0
var _gap: float = 0.0
var _step_t: float = 0.0
var _read_t: float = 0.0
var _done_text: String = ""
var _obj: Label
var _why: Label
var _kit_given: bool = false
var _handed_off: bool = false

func _ready() -> void:
	layer = 15
	add_to_group("tutorial")
	add_to_group("advanced_tutorial")
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.custom_minimum_size = Vector2(1500, 0)
	col.position = Vector2(-750, 20)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_obj = Label.new()
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj.add_theme_font_size_override("font_size", 40)
	_obj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_obj.add_theme_constant_override("outline_size", 14)
	_obj.modulate = Color("#aaffc0")
	col.add_child(_obj)
	_why = Label.new()
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.add_theme_font_size_override("font_size", 24)
	_why.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_why.add_theme_constant_override("outline_size", 10)
	_why.modulate = Color(1, 1, 1, 0.92)
	col.add_child(_why)
	_give_kit.call_deferred()

## The early game, handed over. This tutorial is about machines, not
## about swinging a pickaxe for an hour first -- so it starts you where
## a real run gets after its first few hours: money, metal, and rocks.
func _give_kit() -> void:
	if _kit_given:
		return
	_kit_given = true
	Inventory.add_coins(1500)
	var kit := {
		"ingot": 90, "irid": 40, "ultima": 8, "uranium": 12,
		"coal": 60, "plantfiber": 16, "sulfur": 30,
		"raw_copper": 40, "raw_tin": 16, "raw_ice": 40, "raw_sand": 16,
	}
	for id in kit.keys():
		Inventory.add_res(str(id), int(kit[id]))
	_flash("starter kit: 1500 coins, iron, iridium, ore, ice, sulfur, uranium")

func _process(delta: float) -> void:
	if Game.dead or _step >= STEPS.size():
		return
	if _gap > 0.0:
		_gap -= delta
		_obj.text = _done_text
		_why.text = ""
		return
	var id: String = STEPS[_step]
	Game.tutorial_allow = _allow_for(id)
	_step_t += delta
	# every step is readable for two seconds before it can complete, and
	# the handbook gets pointed at this step's recipes as it opens
	if _step_t < 2.0:
		if _step_t <= delta * 2.0:
			ManualUI.point_at(CIRCLES.get(id, []))
		_paint(id)
		return
	match id:
		"kit":
			if _inv_open():
				_advance()
		"handbook":
			if Game.chem_manual:
				_advance()
		"read":
			if _book_open():
				_read_t += delta
			if _read_t >= READ_SECS:
				_advance()
		"generator":
			if _placed(EMachines.Generator) != null:
				_advance()
		"coal":
			var g = _placed(EMachines.Generator)
			if g != null:
				_ping(g.global_position, "YOUR GENERATOR")
				if g.buf > 1.0:
					_advance()
		"crusher":
			if _placed(Factory.Crusher) != null:
				_advance()
		"wire":
			var cr = _placed(Factory.Crusher)
			if cr != null:
				_ping(cr.global_position, "YOUR CRUSHER")
				if _wired_to(cr):
					_advance()
		"crush":
			var cr2 = _placed(Factory.Crusher)
			if cr2 != null:
				_ping(cr2.global_position, "YOUR CRUSHER")
			if Inventory.res_count("dust_copper") >= DUST_GOAL:
				_advance()
		"smelt":
			var fu = _placed(Furnace)
			if fu != null:
				_ping(fu.global_position, "YOUR FURNACE")
			if Inventory.res_count("copper") >= COPPER_GOAL \
					and Inventory.res_count("tin") >= TIN_GOAL:
				_advance()
		"alloy":
			var af = _placed(Factory.AlloyFurnace)
			if af != null and _wired_to(af):
				_advance()
		"bronze":
			var af2 = _placed(Factory.AlloyFurnace)
			if af2 != null:
				_ping(af2.global_position, "YOUR ALLOY FURNACE")
			if Inventory.res_count("bronze") >= BRONZE_GOAL:
				_advance()
		"bench":
			if _placed(Factory.BenchLab) != null:
				_advance()
		"water":
			var bl = _placed(Factory.BenchLab)
			if bl != null:
				_ping(bl.global_position, "YOUR GLASSWARE BENCH")
			if Inventory.res_count("water") >= 2:
				_advance()
		"sulfuric":
			var bl2 = _placed(Factory.BenchLab)
			if bl2 != null:
				_ping(bl2.global_position, "YOUR GLASSWARE BENCH")
			if Inventory.res_count("sulfuric") >= SULFURIC_GOAL:
				_advance()
		"silica":
			if Inventory.res_count("silica") >= SILICA_GOAL:
				_advance()
		"chemlab":
			var cl = _chemlab()
			if cl != null and _wired_to(cl):
				_advance()
		"carbon":
			var cl2 = _chemlab()
			if cl2 != null:
				_ping(cl2.global_position, "YOUR CHEM LAB")
			if Inventory.res_count("carbon") >= CARBON_GOAL:
				_advance()
		"steel":
			if Inventory.res_count("steel") >= STEEL_GOAL:
				_advance()
		"automate":
			var am = _placed(AutoMiner)
			if am != null and _wired_to(am):
				_advance()
		"reactor":
			# the exam, and the handoff: the reactor lesson takes over
			# from here and finishes the course
			if not _handed_off:
				_handed_off = true
				_hand_off_to_reactor()
	if _step >= STEPS.size():
		return
	_paint(STEPS[_step])

func _paint(id: String) -> void:
	_obj.text = "ADVANCED %d/%d — %s" % [_step + 1, STEPS.size(), _obj_text(id)]
	_why.text = _why_text(id)

func _obj_text(id: String) -> String:
	match id:
		"kit": return "Press E: this is a mid-game start -- 1500 coins, iron, iridium, ore, ice and sulfur are already yours"
		"handbook": return "Buy the CHEMISTRY HANDBOOK (Gear tab, 300 coins) and right-click it to open it"
		"read": return "Read the circled recipes -- BRONZE and SULFURIC ACID are ringed in gold (%d / %d s)" \
			% [int(_read_t), int(READ_SECS)]
		"generator": return "Buy a GENERATOR (Electric tab, 8 iron ingots) and right-click to place it"
		"coal": return "Press F on the generator and feed it COAL -- watch the EU buffer fill"
		"crusher": return "Buy a CRUSHER (Machines tab, 12 ingots + 4 iridium) and place it beside the generator"
		"wire": return "Buy WIRE (Electric tab) and run a wire FROM the generator TO the crusher"
		"crush": return "Press F on the crusher: load Copper Ore and crush it into dust (%d / %d)" \
			% [Inventory.res_count("dust_copper"), DUST_GOAL]
		"smelt": return "Buy a FURNACE (40 coins) and smelt your dust into metal: Copper %d/%d, Tin %d/%d" \
			% [Inventory.res_count("copper"), COPPER_GOAL,
			Inventory.res_count("tin"), TIN_GOAL]
		"alloy": return "Buy an ALLOY FURNACE I (20 ingots + 8 coal), place it and wire it to the generator"
		"bronze": return "Smelt your dust to Copper and Tin, then pour BRONZE -- 3 copper + 1 tin (%d / %d)" \
			% [Inventory.res_count("bronze"), BRONZE_GOAL]
		"bench": return "Buy the GLASSWARE BENCH (6 ingots + 4 wire + 4 plant fiber) and place it -- it needs no power"
		"water": return "Press F on the bench: melt ICE into WATER by hand, following the circled sequence (%d / 2)" \
			% Inventory.res_count("water")
		"sulfuric": return "Make SULFURIC ACID by hand: sulfur + oxygen + water, in the order the book circles (%d / %d)" \
			% [Inventory.res_count("sulfuric"), SULFURIC_GOAL]
		"silica": return "Make SILICA GEL by hand: sand + your own acid (%d / %d)" \
			% [Inventory.res_count("silica"), SILICA_GOAL]
		"chemlab": return "Build CHEM LAB I (it costs the acid and silica you just made), place it and wire it"
		"carbon": return "Press F on the Chem Lab: run COAL into CARBON POWDER (%d / %d)" \
			% [Inventory.res_count("carbon"), CARBON_GOAL]
		"steel": return "Back to the alloy furnace: pour STEEL -- 2 iron + 1 coal (%d / %d)" \
			% [Inventory.res_count("steel"), STEEL_GOAL]
		"automate": return "Buy an AUTO-MINER (Electric tab), park it on ore and wire it -- now the line feeds itself"
		"reactor": return "Final lesson: THE NUCLEAR REACTOR"
	return ""

func _why_text(id: String) -> String:
	match id:
		"kit":
			return "The basic tutorial covers digging and selling. This one starts after that: everything here is about machines, so the early game is handed to you. Nothing in this world is saved."
		"handbook":
			return "The handbook is the single best 300 coins in the game: every alloy, every compound, what it is for, and the exact glassware sequence for anything you can make by hand. From here on, this tutorial circles the page it wants you on."
		"read":
			return "Cards ringed in gold are the recipe the current step needs. The tabs filter by machine, the search box finds anything by name, and BY HAND lists everything the bench can make with no power at all."
		"generator":
			return "Machines past the furnace run on EU, not on hope. The generator burns coal into 12 EU a lump and pushes it down wires -- it is the root of every factory you will ever build."
		"coal":
			return "Fuel goes IN the generator, not in the machine that needs the power. A generator with an empty buffer is why a whole line silently stops."
		"crusher":
			return "The crusher is the first machine that pays for itself: one rock in, TWO dust out, and dust smelts one-for-one. Every deposit you own is worth double the moment this is in the line."
		"wire":
			return "Power flows FROM the machine you start the wire on TO the one you finish on -- direction matters. Each wire connection eats one wire item, and a wire carries 40 EU/s."
		"crush":
			return "Ore -> dust -> ingot. The middle step is the whole point: skipping the crusher halves everything you dig for the rest of the run."
		"smelt":
			return "Dust smelts one for one, so the dust you just crushed is worth double the ore it came from. The plain furnace is slow and needs no power at all; the electric furnace is the upgrade you buy later."
		"alloy":
			return "Alloys are two metals poured together, and they are what the good machines are actually built from. Tier I pours bronze, brass, steel and electrum; the higher tiers need alloys of their own to build."
		"bronze":
			return "Feed BOTH metals in and the furnace pours the bar. Ratios are real -- 3 copper to 1 tin -- which is exactly what the circled card in the handbook is telling you."
		"bench":
			return "Chemistry starts by hand. The bench has three bottles, a burner and no automation whatsoever: you pour materials in and work the operations yourself. Everything downstream of it depends on it."
		"water":
			return "Every compound has its own sequence of operations, and the handbook lists all of them. Get one wrong and the mixture just settles -- nothing is lost, start again."
		"sulfuric":
			return "The workhorse acid, and the gate to the whole chemistry tree: the Chem Lab literally cannot be built until you have made acid with your own hands."
		"silica":
			return "Sand dissolved in your own acid and set again. This is the point where the chain starts eating its own products -- the shape of everything later in the game."
		"chemlab":
			return "The lab does by machine what you just did by hand, over and over, while you are somewhere else. It costs 4 acid and 2 silica because the game wants you to have done it manually first."
		"carbon":
			return "A running lab takes power and time and gives compounds back. Tier II and III are faster and unlock deeper families -- electrolysers, separators that run on nothing but air, cryo plants."
		"steel":
			return "Steel is the spine of the factory: auto-miners, higher furnaces and most late machines are built on it. Iron plus coal, poured hot."
		"automate":
			return "The auto-miner closes the loop: it digs while you are gone, funnels feed the crusher, the crusher feeds the furnace, and the factory earns money without you standing in it."
		"reactor":
			return "Coal will not carry a real base. Fission gives up to 16 EU/s -- and takes your base with it at 1000°C. The reactor lesson takes over now: it spawns a real core and walks the startup, and if you melt it down it explains exactly why and gives you a fresh one."
	return ""

## Shop allowlist per step: this tutorial hands out a lot of money, so
## the shop stays pointed at the lesson instead of at the toy box.
func _allow_for(id: String) -> Array:
	if not Game.tutorial_session:
		return ["*"]
	match id:
		"kit", "handbook", "read": return ["chemmanual"]
		"generator", "coal": return ["generator", "coal"]
		"crusher": return ["crusher", "coal"]
		"wire": return ["wire", "coal"]
		"crush": return ["wire", "coal"]
		"smelt": return ["furnace", "wire", "coal"]
		"alloy", "bronze": return ["alloyfurn", "furnace", "wire", "coal"]
		"bench", "water", "sulfuric", "silica": return ["benchlab", "wire", "coal"]
		"chemlab", "carbon": return ["chemlab", "wire", "coal"]
		"steel": return ["wire", "coal"]
		"automate": return ["autominer", "wire", "coal"]
		"reactor": return ["*"]
	return ["coal"]

# ------------------------------------------------------------- helpers

func _hand_off_to_reactor() -> void:
	Game.tutorial_allow = ["*"]
	ManualUI.point_at([])
	Game.locator_until = -1.0
	_flash("ADVANCED TUTORIAL COMPLETE -- the reactor lesson takes it from here")
	Sfx.play("learn")
	var rt := ReactorTutorial.new()
	get_tree().current_scene.add_child(rt)
	queue_free()

func _placed(type) -> Node3D:
	for n in get_tree().get_nodes_in_group("machine"):
		if is_instance_valid(n) and is_instance_of(n, type):
			return n
	return null

## The chem lab is a Processor with the chem family -- an electrolyser is
## the same class with a different family and must not count.
func _chemlab() -> Node3D:
	for n in get_tree().get_nodes_in_group("machine"):
		if is_instance_valid(n) and n is Factory.Processor and n.family == "chem":
			return n
	return null

## Is anything feeding this machine energy? Either a wire runs into it or
## it is already holding EU it did not generate itself.
func _wired_to(m: Node) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	if m is Machine and m.buf > 0.5:
		return true
	for n in get_tree().get_nodes_in_group("machine"):
		if is_instance_valid(n) and n is Machine and n != m and n.wires_out.has(m):
			return true
	return false

func _book_open() -> bool:
	return get_tree().get_first_node_in_group("manual_ui") != null

func _inv_open() -> bool:
	for n in get_tree().get_nodes_in_group("closable_ui"):
		if n is InventoryUI and n.visible:
			return true
	return false

func _flash(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash(msg)

func _ping(pos: Vector3, label: String) -> void:
	Game.locator_targets = [pos]
	Game.locator_label = label
	Game.locator_until = Game.playtime + 2.0

func _advance() -> void:
	_done_text = "✓ %s" % _obj_text(STEPS[_step])
	_step += 1
	_step_t = 0.0
	_read_t = 0.0
	_gap = STEP_GAP
	Game.locator_until = -1.0
	Sfx.play("learn", -12.0)
	if _step < STEPS.size():
		ManualUI.point_at(CIRCLES.get(STEPS[_step], []))


## The circles belong to this lesson only -- a real save loaded later in
## the same process must not open a book with tutorial rings in it.
func _exit_tree() -> void:
	if not _handed_off:
		ManualUI.point_at([])
