extends Node
## Autoload "Inventory". Coins, the 5-slot hotbar + 10-slot backpack of
## STACKED items (weapons, tools, and resources like ore ×64), upgrade
## flags, and the tabbed shop/craft catalog.
## A slot is {"id": String, "n": int}; empty slot has id "".

signal changed

const STACKABLE := ["raw_ingot", "raw_irid", "ingot", "irid", "ultima", "prism", "uranium", "sulfur", "semicircle", "circle", "waypoint",
	"plantfiber", "shroom", "banana", "salad", "meat", "cooked_meat", "coal", "wire"]
const STACK_MAX := 999

var coins: int = 0            # carried coins (lose 50% on death)
var bank_coins: int = 0       # deposited at an ATM -> safe from death
var zeptobux: int = 0         # alien-trader currency (traders: planned)
var bank_zepto: int = 0

var fuel: float = 0.0
var fuel_max: float = 100.0
var jet_fuel: float = 0.0
var jet_max: float = 100.0
var jet_power: float = 1.0        # thrust multiplier (Jetpack 3.0 = 2x)
var jet_on: bool = false          # was the jetpack toggled ON (persisted)
var enchant: Dictionary = {}      # weapon id -> shrine enchant level
var hyper_rockets: int = 0        # broken rockets that still hold a hyperdrive

# --- armor & equipment ---
var armors: Dictionary = {
	"boots":        {"name": "Grav Boots",   "slot": "boots", "def": 3,  "color": Color("#444455")},
	"iron_helmet":  {"name": "Iron Helmet",  "slot": "head",  "def": 5,  "color": Color("#b8bcc8")},
	"iron_chest":   {"name": "Iron Chestplate", "slot": "chest", "def": 10, "color": Color("#b8bcc8")},
	"iron_legs":    {"name": "Iron Leggings","slot": "legs",  "def": 7,  "color": Color("#b8bcc8")},
	"prism_helmet": {"name": "Prism Helmet", "slot": "head",  "def": 16, "color": Color("#ff7ce9")},
	"prism_chest":  {"name": "Prism Chestplate", "slot": "chest", "def": 28, "color": Color("#ff7ce9")},
	"prism_legs":   {"name": "Prism Leggings","slot": "legs", "def": 21, "color": Color("#ff7ce9")},
	"prism_boots":  {"name": "Prism Boots",  "slot": "boots", "def": 12, "color": Color("#ff7ce9")},
	"ultima_helmet": {"name": "Ultima Helmet",  "slot": "head",  "def": 14, "color": Color("#7df9ff")},
	"ultima_chest":  {"name": "Ultima Chestplate", "slot": "chest", "def": 24, "color": Color("#7df9ff")},
	"ultima_legs":   {"name": "Ultima Leggings","slot": "legs",  "def": 18, "color": Color("#7df9ff")},
	"ultima_boots":  {"name": "Ultima Boots",  "slot": "boots", "def": 10, "color": Color("#7df9ff")},
}
var equip: Dictionary = {"head": "", "chest": "", "legs": "", "boots": "", "charm": ""}

## Total damage reduction from worn armor (capped at 60%).
## Menger-enchanted pieces protect 15% more per level.
func armor_reduction() -> float:
	var total := 0.0
	for slot in ["head", "chest", "legs", "boots"]:
		var id := str(equip.get(slot, ""))
		if armors.has(id):
			total += float(armors[id]["def"]) \
				* (1.0 + 0.15 * float(enchant.get(id, 0)))
	return minf(0.6, total / 100.0)

var has_rcs: bool = false
var has_jetpack: bool = false
var wrath_ward: bool = false
var engine_mk2: bool = false
var ak47_recipe: bool = false      # learned in the shadow temple
var artifact_taken: bool = false   # euclid maze artifact claimed

# --- weapons ---
var weapons: Dictionary = {
	"fists":     {"name": "Fists",       "dmg": 8.0,  "rate": 0.35, "range": 4.0,   "color": Color("#dddddd")},
	"blaster":   {"name": "Blaster",     "dmg": 15.0, "rate": 0.18, "range": 120.0, "color": Color("#4cc9f0")},
	"ak47":      {"name": "AK-47",       "dmg": 22.0, "rate": 0.09, "range": 200.0, "color": Color("#ffb347")},
	"plasma":    {"name": "Plasma Rifle","dmg": 30.0, "rate": 0.12, "range": 160.0, "color": Color("#b388ff")},
	"voidhammer":{"name": "Voidhammer",  "dmg": 60.0, "rate": 0.45, "range": 8.0,   "color": Color("#7a1dbe")},
	"knife":     {"name": "Knife",       "dmg": 6.0,  "rate": 0.22, "range": 4.0,   "color": Color("#c8c8d0")},
	"raygun":    {"name": "Ray Gun",     "dmg": 45.0, "rate": 0.14, "range": 220.0, "color": Color("#4dff9a")},
	"rail":      {"name": "Rail Cannon", "dmg": 90.0, "rate": 0.70, "range": 400.0, "color": Color("#ff5964")},
}

# Non-weapon items (tools, placeables, and resources).
var items: Dictionary = {
	"raw_ingot":  {"name": "Raw Ingot",        "color": Color("#a24bff")},
	"raw_irid":   {"name": "Raw Iridium",      "color": Color("#2a8f6a")},
	"ingot":      {"name": "Ingot",            "color": Color("#d8d8e8")},
	"irid":       {"name": "Iridium",          "color": Color("#59ffc4")},
	"ultima":     {"name": "Ultima Crystal",   "color": Color("#7df9ff")},
	"prism":      {"name": "Prism Shard",      "color": Color("#ff7ce9")},
	"uranium":    {"name": "Uranium",          "color": Color("#5aff3a")},
	"sulfur":     {"name": "Sulfur",           "color": Color("#e8d44a")},
	"semicircle": {"name": "Semicircle",       "color": Color("#ffd166")},
	"circle":     {"name": "Circle",           "color": Color("#ffe9a0")},
	"prisreactor": {"name": "Prism Reactor",   "color": Color("#2a1a3a")},
	"nreactor":   {"name": "Nuclear Reactor",  "color": Color("#8a8d90")},
	"charm":      {"name": "Anti-Death Charm", "color": Color("#b56cff")},
	"permapple":  {"name": "Permadeath Apple", "color": Color("#8b0000")},
	"chest":      {"name": "Chest",            "color": Color("#a9713b")},
	"furnace":    {"name": "Furnace",          "color": Color("#ff7a1a")},
	"coinifier":  {"name": "Sell Station",     "color": Color("#ffe066")},
	"autominer":  {"name": "Auto-Miner",       "color": Color("#8fe8ff")},
	"backpack":   {"name": "Backpack",         "color": Color("#7d9c4a")},
	"spawnbeacon":{"name": "Spawn Beacon",     "color": Color("#2bff6a")},
	"rocket":     {"name": "Rocket",           "color": Color("#ff5964")},
	"rocket2":    {"name": "Rocket 2.0",       "color": Color("#7df9ff")},
	"fuel":       {"name": "Rocket Fuel",      "color": Color("#ffd166")},
	"jetfuel":    {"name": "Jet Fuel",         "color": Color("#ffd166")},
	"jetpack":    {"name": "Jetpack",          "color": Color("#4cc9f0")},
	"jetpack2":   {"name": "Jetpack 2.0",      "color": Color("#1a8fd0")},
	"jetpack3":   {"name": "Jetpack 3.0",      "color": Color("#7df9ff")},
	"jetfuel4":   {"name": "Jet Fuel x4",      "color": Color("#ffb347")},
	"tankxl":     {"name": "Tank XL",          "color": Color("#ffa040")},
	"engine_mk2": {"name": "Engine Mk2",       "color": Color("#ff8c42")},
	"hyperdrive": {"name": "Hyperdrive",       "color": Color("#c86bff")},
	"ward":       {"name": "Noodle Ward",      "color": Color("#ff6aa0")},
	"noodle":     {"name": "Appeasement Noodle","color": Color("#ffcf40")},
	"plantfiber": {"name": "Plant Fiber",      "color": Color("#4caf50")},
	"meat":       {"name": "Meat",             "color": Color("#c05050")},
	"cooked_meat":{"name": "Cooked Meat",      "color": Color("#8a4a2a")},
	"coal":       {"name": "Coal",             "color": Color("#1a1a1a")},
	"wire":       {"name": "Wire",             "color": Color("#5ad0ff")},
	"wiretool":   {"name": "Wiring Tool",      "color": Color("#5ad0ff")},
	"funneltool": {"name": "Funnel Tool",      "color": Color("#ffa040")},
	"generator":  {"name": "Generator",        "color": Color("#3a3a4a")},
	"coaldrill":  {"name": "Coal Drill",       "color": Color("#2a2a30")},
	"bioreactor": {"name": "Bioreactor",       "color": Color("#2a5a30")},
	"rtg":        {"name": "RTG",              "color": Color("#1a4a4a")},
	"capacitor":  {"name": "Capacitor",        "color": Color("#44446a")},
	"ultracap":   {"name": "Ultra Capacitor",  "color": Color("#6a5aff")},
	"elight":     {"name": "Electric Light",   "color": Color("#fff2c8")},
	"lightbox":   {"name": "Light Box",        "color": Color("#d8cfa0")},
	"coil":       {"name": "Control Coil",     "color": Color("#ff9a3c")},
	"switch":     {"name": "Power Switch",     "color": Color("#4a4a52")},
	"efurnace":   {"name": "Electric Furnace", "color": Color("#7a3a1a")},
	"eseller":    {"name": "Electric Seller",  "color": Color("#7a6a10")},
	"atm":        {"name": "ATM",              "color": Color("#1b2b4a")},
	"ecomputer":  {"name": "Electric Computer","color": Color("#2a4a6a")},
	"scomputer":  {"name": "Sorter Computer",  "color": Color("#5a3a6a")},
	"carkeys":    {"name": "Space Car Keys",   "color": Color("#4dff9a")},
	"shroom":     {"name": "Mushroom",         "color": Color("#d13a3a")},
	"banana":     {"name": "Banana",           "color": Color("#ffe135")},
	"salad":      {"name": "Salad",            "color": Color("#7ddc5a")},
	"cage":       {"name": "Animal Cage",      "color": Color("#b0b0b8")},
	"caged_animal":{"name": "Caged Animal",   "color": Color("#7d9c4a")},
	"caged_human": {"name": "Caged Human",    "color": Color("#c8a078")},
	"catfood":    {"name": "Cat Food",         "color": Color("#e8956a")},
	"boots":      {"name": "Grav Boots",       "color": Color("#888899")},
	"magnet":     {"name": "Coin Magnet",      "color": Color("#ffcc22")},
	"orbitwand":  {"name": "Orbit Wand",       "color": Color("#9a6bff")},
	"teleporter": {"name": "Warp Pad",         "color": Color("#1a2a4a")},
	"extender":   {"name": "Extender",         "color": Color("#4a5560")},
	"warpshard":  {"name": "Warp Shard",       "color": Color("#7cf9ff")},
	"waypoint":   {"name": "Waypoint",         "color": Color("#ffd166")},
	"locator":    {"name": "Locator",          "color": Color("#8a9099")},
	"backpack2":  {"name": "Prism Backpack",   "color": Color("#ff7ce9")},
	"ubackpack":  {"name": "Universe Backpack","color": Color("#7df9ff")},
	"iron_helmet": {"name": "Iron Helmet",     "color": Color("#b8bcc8")},
	"iron_chest": {"name": "Iron Chestplate",  "color": Color("#b8bcc8")},
	"iron_legs":  {"name": "Iron Leggings",    "color": Color("#b8bcc8")},
	"prism_helmet":{"name": "Prism Helmet",    "color": Color("#ff7ce9")},
	"prism_chest":{"name": "Prism Chestplate", "color": Color("#ff7ce9")},
	"prism_legs": {"name": "Prism Leggings",   "color": Color("#ff7ce9")},
	"prism_boots":{"name": "Prism Boots",      "color": Color("#ff7ce9")},
	"ultima_helmet":{"name": "Ultima Helmet",  "color": Color("#7df9ff")},
	"ultima_chest":{"name": "Ultima Chestplate","color": Color("#7df9ff")},
	"ultima_legs": {"name": "Ultima Leggings", "color": Color("#7df9ff")},
	"ultima_boots":{"name": "Ultima Boots",    "color": Color("#7df9ff")},
}
var placeables: Array = ["chest", "spawnbeacon", "rocket", "furnace", "coinifier", "autominer",
	"generator", "coaldrill", "bioreactor", "rtg", "prisreactor", "capacitor", "efurnace", "eseller",
	"atm", "ecomputer", "scomputer", "ultracap", "elight", "switch", "teleporter", "extender"]

var hotbar: Array = []
var backpack_store: Array = []   # basic pack: 20
var prism_store: Array = []      # prism pack: 40, its own bag
var universe_store: Array = []   # universe pack: 20, ender-style (all universe packs share it)
var selected: int = 0
var caged_data: Array = []   # genomes of caged animals (persisted)

# --- the tabbed catalog. "cost" may mix coins + resources. ---
var tabs: Array = ["Gear", "Rocket", "Machines", "Electric", "Armor", "Weapons"]
var catalog: Array = []

static func empty_slot() -> Dictionary:
	return {"id": "", "n": 0}

func _init() -> void:
	_blank_containers()

func _blank_containers() -> void:
	hotbar = []
	for i in 5:
		hotbar.append(empty_slot())
	backpack_store = []
	for i in 20:
		backpack_store.append(empty_slot())
	prism_store = []
	for i in 40:
		prism_store.append(empty_slot())
	universe_store = []
	for i in 20:
		universe_store.append(empty_slot())

func _ready() -> void:
	catalog = [
		{"id": "blaster",   "tab": "Gear",     "name": "Blaster",        "cost": {"coins": 90},  "desc": "Basic energy weapon."},
		{"id": "jetpack",   "tab": "Gear",     "name": "Jetpack",        "cost": {"coins": 130}, "desc": "Right-click to strap on. J to toggle, Space up, C down."},
		{"id": "jetfuel",   "tab": "Gear",     "name": "Jet Fuel +50",   "cost": {"coins": 25},  "desc": "Right-click to refuel the jetpack."},
		{"id": "backpack",  "tab": "Gear",     "name": "Backpack",       "cost": {"coins": 120}, "desc": "+20 storage (chest-sized). Right-click to open."},
		{"id": "jetpack2",  "tab": "Gear",     "name": "Jetpack 2.0",    "cost": {"coins": 900, "irid": 12}, "desc": "5x the tank (500). Canisters still give +50 each."},
		{"id": "jetpack3",  "tab": "Gear",     "name": "Jetpack 3.0",    "cost": {"coins": 4000, "irid": 40, "ultima": 12, "prism": 30}, "desc": "2x Jetpack 2.0: 1000 tank + DOUBLE thrust. Prism-cored."},
		{"id": "jetfuel4",  "tab": "Gear",     "name": "Jet Fuel x4 Canister", "cost": {"coins": 85}, "desc": "Right-click: +200 jet fuel in one gulp."},
		{"id": "charm",     "tab": "Gear",     "name": "Anti-Death Charm","cost": {"ultima": 10}, "desc": "In hotbar/backpack: survives one permadeath (consumed)."},
		{"id": "circle",    "tab": "Gear",     "name": "Circle",         "cost": {"semicircle": 2}, "desc": "Two halves make a whole. Sells for 95. Semicircles alone sell for NOTHING."},
		{"id": "knife",     "tab": "Gear",     "name": "Knife",          "cost": {"coins": 70},  "desc": "Harvests plants/mushrooms/bananas as ITEMS instead of smashing them."},
		{"id": "salad",     "tab": "Gear",     "name": "Salad (craft)",  "cost": {"shroom": 2, "banana": 1, "plantfiber": 4}, "desc": "Eat: weak at first. Wait 3s. Then WATCH the regen. Fades after a minute."},
		{"id": "cage",      "tab": "Gear",     "name": "Animal Cage",    "cost": {"coins": 90},  "desc": "Right-click near an animal: catch it. Release anywhere. Cage survives."},
		{"id": "catfood",   "tab": "Gear",     "name": "Cat Food",       "cost": {"coins": 60},  "desc": "Right-click near an animal: TAMED. Follows you across the universe."},
		{"id": "boots",     "tab": "Armor",    "name": "Grav Boots",     "cost": {"coins": 40},  "desc": "FEET. 3% damage off. Right-click to wear."},
		{"id": "iron_helmet","tab": "Armor",   "name": "Iron Helmet",    "cost": {"ingot": 6},  "desc": "HEAD. 5% damage off. Right-click to wear."},
		{"id": "iron_chest","tab": "Armor",    "name": "Iron Chestplate","cost": {"ingot": 10}, "desc": "CHEST. 10% damage off. Right-click to wear."},
		{"id": "iron_legs", "tab": "Armor",    "name": "Iron Leggings",  "cost": {"ingot": 8},  "desc": "LEGS. 7% damage off. Right-click to wear."},
		{"id": "ultima_helmet","tab": "Armor", "name": "Ultima Helmet",  "cost": {"ultima": 8, "prism": 6},  "desc": "HEAD. 14% damage off. Crystal-grown."},
		{"id": "ultima_chest","tab": "Armor",  "name": "Ultima Chestplate","cost": {"ultima": 15, "prism": 10}, "desc": "CHEST. 24% damage off. Crystal-grown."},
		{"id": "ultima_legs","tab": "Armor",   "name": "Ultima Leggings","cost": {"ultima": 11, "prism": 8}, "desc": "LEGS. 18% damage off. Crystal-grown."},
		{"id": "ultima_boots","tab": "Armor",  "name": "Ultima Boots",   "cost": {"ultima": 6, "prism": 5},  "desc": "FEET. 10% damage off. Crystal-grown."},
		{"id": "prism_helmet","tab": "Armor",  "name": "Prism Helmet",   "cost": {"prism": 20, "irid": 8},   "desc": "HEAD. 16% damage off. Shader-forged."},
		{"id": "prism_chest","tab": "Armor",   "name": "Prism Chestplate","cost": {"prism": 25, "irid": 12},"desc": "CHEST. 28% damage off. Shader-forged."},
		{"id": "prism_legs","tab": "Armor",    "name": "Prism Leggings", "cost": {"prism": 22, "irid": 10},  "desc": "LEGS. 21% damage off. Shader-forged."},
		{"id": "prism_boots","tab": "Armor",   "name": "Prism Boots",    "cost": {"prism": 18, "irid": 6},   "desc": "FEET. 12% damage off. Shader-forged."},
		{"id": "magnet",    "tab": "Gear",     "name": "Coin Magnet",    "cost": {"coins": 55},  "desc": "Flavor. Coins feel closer."},
		{"id": "backpack2", "tab": "Gear",     "name": "Prism Backpack", "cost": {"prism": 8, "irid": 6, "coins": 400}, "desc": "Its OWN 40-slot bag. Right-click to open."},
		{"id": "ubackpack", "tab": "Gear",     "name": "Universe Backpack", "cost": {"ultima": 8, "prism": 6, "coins": 1000}, "desc": "20 slots that exist OUTSIDE SPACE. Every universe backpack opens the same storage."},
		{"id": "locator",   "tab": "Gear",     "name": "Locator",        "cost": {"ultima": 4, "irid": 12}, "desc": "Right-click: cycle target (alien ship / invaders / shadow temple / UFO / rifts / mines) + green ping through walls."},
		{"id": "waypoint",  "tab": "Gear",     "name": "Waypoint ×3",    "cost": {"ultima": 6}, "desc": "Place anywhere (or ON a rocket). F toggles. HUD diamond marks it through planets.", "count": 3},
		{"id": "warpshard", "tab": "Gear",     "name": "Warp Shard",     "cost": {"coins": 400, "irid": 3}, "desc": "Single use. Right-click: snap back to your spawn point. Crumbles after."},
		{"id": "orbitwand", "tab": "Gear",     "name": "Orbit Wand",     "cost": {"coins": 2000, "irid": 15, "ultima": 5, "prism": 12, "circle": 5}, "desc": "Click an animal or enemy: YEET into orbit. F: yeet yourself. An orbit IS a circle."},

		{"id": "rocket",    "tab": "Rocket",   "name": "Rocket",         "cost": {"coins": 150}, "desc": "Right-click to place upright. F to board."},
		{"id": "rocket2",   "tab": "Rocket",   "name": "Rocket 2.0",     "cost": {"coins": 800, "irid": 15, "ultima": 4}, "desc": "Double tank (200), fuel loads double, burns 40% less. Passenger bubble: a friend can ride."},
		{"id": "fuel",      "tab": "Rocket",   "name": "Rocket Fuel +50","cost": {"coins": 30},  "desc": "Right-click near your rocket to fill it."},
		{"id": "tankxl",    "tab": "Rocket",   "name": "Tank XL +50",    "cost": {"coins": 200}, "desc": "Right-click to install. Raises max fuel."},
		{"id": "engine_mk2","tab": "Rocket",   "name": "Engine Mk2",     "cost": {"coins": 700, "irid": 10}, "desc": "+60% thrust. Iridium: found off-world."},
		{"id": "hyperdrive","tab": "Rocket",   "name": "Hyperdrive",     "cost": {"coins": 2500, "irid": 25, "ultima": 10}, "desc": "SHIP PART. Right-click near a ship to install. Hold H: scream."},

		{"id": "chest",     "tab": "Machines", "name": "Chest",          "cost": {"coins": 60},  "desc": "Right-click to place. F to open (10 slots)."},
		{"id": "furnace",   "tab": "Machines", "name": "Furnace",        "cost": {"coins": 40},  "desc": "Place it. F: smelts all your ore into ingots."},
		{"id": "coinifier", "tab": "Machines", "name": "Sell Station",   "cost": {"coins": 40},  "desc": "Place it. Load items, it sells them over time. Slowly."},
		{"id": "autominer", "tab": "Electric", "name": "Auto-Miner",     "cost": {"ingot": 6, "irid": 2}, "desc": "ELECTRIC. Wire power in, park near ore: 8 EU per raw ingot."},
		{"id": "atm",       "tab": "Machines", "name": "ATM",            "cost": {"coins": 200}, "desc": "Bank + coin->ZeptoBux exchange. No power needed."},
		{"id": "spawnbeacon","tab": "Machines","name": "Spawn Beacon",   "cost": {"coins": 1200},"desc": "Right-click to place. F to set spawn (glows green)."},

		{"id": "wiretool",  "tab": "Electric", "name": "Wiring Tool",    "cost": {"ingot": 2},   "desc": "R-click machine A (output), then machine B (input): energy wire w/ arrow. Uses 1 Wire."},
		{"id": "funneltool","tab": "Electric", "name": "Funnel Tool",    "cost": {"ingot": 2},   "desc": "Same, but moves ITEMS: output slot -> input slot. Uses 1 Wire."},
		{"id": "wire",      "tab": "Electric", "name": "Wire ×4",        "cost": {"ingot": 1},   "desc": "Iron drawn into wire. Each connection eats one.", "count": 4},
		{"id": "generator", "tab": "Electric", "name": "Generator",      "cost": {"ingot": 8},   "desc": "Burns coal: 1 coal -> 25 EU."},
		{"id": "coaldrill", "tab": "Electric", "name": "Coal Drill",     "cost": {"ingot": 6, "irid": 2}, "desc": "Digs 1 coal / 5s. Funnel it into a generator."},
		{"id": "bioreactor","tab": "Electric", "name": "Bioreactor",     "cost": {"ingot": 6, "plantfiber": 6}, "desc": "Meat, plants, bananas, even THE APPLE -> energy."},
		{"id": "capacitor", "tab": "Electric", "name": "Capacitor",      "cost": {"ingot": 4, "irid": 1}, "desc": "Stores 600 EU. One in, one out."},
		{"id": "lightbox", "tab": "Electric", "name": "Light Box",     "cost": {"coins": 60, "ingot": 4}, "desc": "Small indicator lamp. Glows while fed power -- wire a computer output to it. Lights the desk, not the planet."},
		{"id": "elight",    "tab": "Electric", "name": "Electric Light", "cost": {"coins": 30, "ingot": 1}, "desc": "Sips 0.5 EU/s, floods the area with light."},
		{"id": "extender",  "tab": "Electric", "name": "Extender",       "cost": {"ingot": 2}, "desc": "Relay pole: wires AND funnels in/out. Stretches any network."},
		{"id": "switch",    "tab": "Electric", "name": "Power Switch",   "cost": {"ingot": 2},   "desc": "F toggles it. ON = power flows through. OFF = wall."},
		{"id": "coil",      "tab": "Electric", "name": "Control Coil",   "cost": {"ingot": 3, "irid": 1}, "desc": "Right-click ON a machine: it now only runs while the coil gets power. Automate via computer ports."},
		{"id": "ultracap",  "tab": "Electric", "name": "Ultra Capacitor", "cost": {"ingot": 40, "irid": 25, "ultima": 6}, "desc": "6,000 EU tank, double-rate output wires. The battery."},
		{"id": "rtg",       "tab": "Electric", "name": "Nuclear RTG",    "cost": {"irid": 20, "ultima": 15}, "desc": "+2 EU/s forever off ultima decay."},
		{"id": "teleporter", "tab": "Electric", "name": "Warp Pad",      "cost": {"ultima": 10, "prism": 15, "ingot": 40, "irid": 25}, "desc": "Fast-travel network. Full 1000 EU charge + 2000 coins per warp. F: pick a destination."},
		{"id": "prisreactor", "tab": "Electric", "name": "Prism Reactor", "cost": {"prism": 35, "irid": 40, "ultima": 8}, "desc": "+8 EU/s forever. Prism shards only grow in the shader system."},
		{"id": "nreactor",  "tab": "Electric", "name": "Nuclear Reactor", "cost": {"ingot": 30, "irid": 20, "ultima": 6, "uranium": 10}, "desc": "Fission: up to +16 EU/s. Feed uranium, raise the control rods, mind the core temperature. Cooling only carries ~60% power -- run hotter and it CLIMBS. At 1000°C it takes your base with it."},
		{"id": "efurnace",  "tab": "Electric", "name": "Electric Furnace","cost": {"ingot": 25, "irid": 12}, "desc": "INSTANT smelt, 4 EU per item. Wire power in, funnel ore in."},
		{"id": "ecomputer", "tab": "Electric", "name": "Electric Computer","cost": {"ingot": 20, "irid": 10}, "desc": "Programmable power gate: inp1, out1..out8. Lua-ish."},
		{"id": "scomputer", "tab": "Electric", "name": "Sorter Computer", "cost": {"ingot": 20, "irid": 10}, "desc": "Programmable item router: sort(funnel, port)."},
		{"id": "eseller",   "tab": "Electric", "name": "Electric Seller","cost": {"ingot": 25, "irid": 15}, "desc": "Sells fast at 1.25x price, 2 EU per sale."},

		{"id": "plasma",    "tab": "Weapons",  "name": "Plasma Rifle",   "cost": {"coins": 6000, "irid": 10}, "desc": "Heavy energy damage. 250 DPS does not come cheap."},
		{"id": "ak47",      "tab": "Weapons",  "name": "AK-47",          "cost": {"ingot": 20, "ultima": 6}, "desc": "CRAFT. Needs the recipe from the Shadow Temple.", "recipe": true},
		{"id": "rail",      "tab": "Weapons",  "name": "Rail Cannon",    "cost": {"coins": 2800},"desc": "Huge single-shot damage, long range."},
		{"id": "ward",      "tab": "Weapons",  "name": "Noodle Ward",    "cost": {"coins": 300}, "desc": "Right-click: halves how fast the gods anger."},
		{"id": "noodle",    "tab": "Weapons",  "name": "Appeasement Noodle","cost": {"coins": 700},"desc": "Right-click: resets god wrath fully."},
	]

# ---------------------------------------------------------------- slots

func slot_id(i: int) -> String:
	return str(hotbar[i]["id"])

func slot_text(slot: Dictionary) -> String:
	var id := str(slot["id"])
	if id == "":
		return ""
	var nm := hotbar_name(id)
	return "%s ×%d" % [nm, int(slot["n"])] if int(slot["n"]) > 1 else nm

func hotbar_name(id: String) -> String:
	if id == "":
		return ""
	if id == "caged_human":
		# the box says who's in it (the next one out, specifically)
		for i in range(caged_data.size() - 1, -1, -1):
			var e: Dictionary = caged_data[i]
			if e is Dictionary and e.has("human"):
				return "Caged Human (%s)" % str(e["human"].get("name", "?"))
		return "Caged Human"
	if weapons.has(id):
		return weapons[id]["name"]
	if items.has(id):
		return items[id]["name"]
	return id

func hotbar_has_space() -> bool:
	for s in hotbar:
		if str(s["id"]) == "":
			return true
	return false

## Room ANYWHERE (hotbar or backpack) -- give() overflows automatically.
func any_space() -> bool:
	for cont in [hotbar, backpack_store]:
		for s in cont:
			if str(s["id"]) == "":
				return true
	return false

## Add n of an item. Stacks stackables, overflows into the backpack.
## Returns how many did NOT fit (0 = all good).
## give() but overflow falls to the FLOOR as a pickup instead of vanishing.
func give(id: String, n: int = 1) -> int:
	var p = get_tree().get_first_node_in_group("player")
	return give_at(id, n, p.global_position if p else Vector3.ZERO)

## Same, but overflow drops at a SPECIFIC spot (e.g. the broken machine).
func give_at(id: String, n: int, pos: Vector3) -> int:
	var left := give_no_drop(id, n)
	if left > 0:
		var cs = get_tree().current_scene
		if cs:
			var d := ItemDrop.new()
			d.setup(id, left)
			cs.add_child(d)
			d.global_position = pos \
				+ Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.5, 1.5))
			left = 0
	return left

func give_no_drop(id: String, n: int = 1) -> int:
	var left := n
	for cont in [hotbar, backpack_store]:
		if left <= 0:
			break
		if STACKABLE.has(id):
			for s in cont:
				if str(s["id"]) == id and int(s["n"]) < STACK_MAX:
					var take: int = mini(left, STACK_MAX - int(s["n"]))
					s["n"] = int(s["n"]) + take
					left -= take
					if left <= 0:
						break
		for s in cont:
			if left <= 0:
				break
			if str(s["id"]) == "":
				var take2: int = mini(left, STACK_MAX if STACKABLE.has(id) else 1)
				s["id"] = id
				s["n"] = take2
				left -= take2
				if not STACKABLE.has(id):
					break
	changed.emit()
	return left

func give_to_hotbar(id: String) -> int:
	return give(id, 1)

func add_res(id: String, n: int) -> void:
	var lost := give(id, n)
	if lost > 0:
		Sfx.play("denied")

func res_count(id: String) -> int:
	var total := 0
	for cont in [hotbar, backpack_store]:
		for s in cont:
			if str(s["id"]) == id:
				total += int(s["n"])
	return total

func remove_res(id: String, n: int) -> void:
	var left := n
	for cont in [hotbar, backpack_store]:
		for s in cont:
			if left <= 0:
				return
			if str(s["id"]) == id:
				var take: int = mini(left, int(s["n"]))
				s["n"] = int(s["n"]) - take
				left -= take
				if int(s["n"]) <= 0:
					s["id"] = ""
					s["n"] = 0
	changed.emit()

func clear_slot(i: int) -> void:
	if i >= 0 and i < 5:
		# consume ONE from a stack; drop the whole slot otherwise
		if STACKABLE.has(str(hotbar[i]["id"])) and int(hotbar[i]["n"]) > 1:
			hotbar[i]["n"] = int(hotbar[i]["n"]) - 1
		else:
			hotbar[i] = empty_slot()
		changed.emit()

## Toss any stack onto the floor ahead of the player as a real pickup.
func drop_stack(id: String, n: int) -> void:
	if id == "" or id == "fists" or n <= 0:
		return
	var cs = get_tree().current_scene
	var p = get_tree().get_first_node_in_group("player")
	if cs:
		var d := ItemDrop.new()
		d.setup(id, n)
		cs.add_child(d)
		var pos: Vector3 = p.global_position if p else Vector3.ZERO
		if p:
			pos += -p.global_transform.basis.z * 3.0   # tossed ahead
		d.global_position = pos
	Sfx.play("click", -18.0)
	changed.emit()

## Drop a hotbar slot onto the floor (never deletes).
func drop_slot(i: int) -> void:
	if i >= 0 and i < 5:
		drop_stack(str(hotbar[i]["id"]), int(hotbar[i]["n"]))
		hotbar[i] = empty_slot()
		changed.emit()

func select_slot(i: int) -> void:
	if i >= 0 and i < 5:
		selected = i
		changed.emit()

func current_weapon() -> Dictionary:
	var id := slot_id(clampi(selected, 0, 4))
	var w: Dictionary = (weapons[id] if weapons.has(id) else weapons["fists"]).duplicate()
	var lvl := int(enchant.get(id, 0))
	if lvl > 0:
		w["dmg"] = float(w["dmg"]) * (1.0 + 0.25 * float(lvl))   # shrine enchant
	return w

func is_placeable(id: String) -> bool:
	return placeables.has(id)

func has_charm() -> bool:
	for cont in [hotbar, backpack_store]:
		for s in cont:
			if str(s["id"]) == "charm":
				return true
	return false

func consume_item(id: String) -> bool:
	for cont in [hotbar, backpack_store]:
		for s2 in cont:
			if str(s2["id"]) == id:
				s2["n"] = int(s2["n"]) - 1
				if int(s2["n"]) <= 0:
					s2["id"] = ""
					s2["n"] = 0
				changed.emit()
				return true
	return false

func consume_charm() -> bool:
	# the charm only protects you from its SLOT. pockets don't count.
	if str(equip.get("charm", "")) == "charm":
		equip["charm"] = ""
		changed.emit()
		return true
	return false

## Apply a consumable/upgrade item and consume it. Returns true if used.
func use_item(slot: int) -> bool:
	var id := slot_id(slot)
	# armor: right-click = WEAR (old piece returns to your bags)
	if armors.has(id):
		var aslot := str(armors[id]["slot"])
		var old := str(equip.get(aslot, ""))
		equip[aslot] = id
		clear_slot(slot)   # the worn piece leaves your hand
		if old != "":
			give(old, 1)
		Sfx.play("click")
		return true
	if id == "warpshard":
		var pw = get_tree().get_first_node_in_group("player")
		if pw and pw.has_method("respawn_at") and Game.mode == Game.Mode.ON_FOOT:
			Game.zone = ""
			clear_slot(slot)   # single use: it crumbles
			pw.respawn_at(Game.spawn_pos + Game.spawn_up * 1.5, Game.spawn_up)
			Sfx.play("warp")
			return true
		return false
	if id == "charm":
		var oldc := str(equip.get("charm", ""))
		equip["charm"] = "charm"
		clear_slot(slot)
		if oldc != "":
			give(oldc, 1)
		Sfx.play("learn")
		return true
	match id:
		"jetfuel": jet_fuel = minf(jet_max, jet_fuel + 50.0)
		"jetfuel4": jet_fuel = minf(jet_max, jet_fuel + 200.0)
		"jetpack": has_jetpack = true
		"tankxl": fuel_max += 50.0
		"engine_mk2": engine_mk2 = true
		"jetpack2":
			has_jetpack = true
			jet_max = maxf(jet_max, 500.0)
		"jetpack3":
			has_jetpack = true
			jet_max = 1000.0
			jet_power = 2.0
		"ward": wrath_ward = true
		"noodle":
			# a brooding god will NOT be bribed -- the noodle stays yours
			if Game.playtime < Game.god_standby_until:
				Sfx.play("denied")
				return false
			# and each brood it survives, tribute means less to it
			Game.wrath = maxf(0.0, Game.wrath \
				- maxf(3.0, 12.0 - 2.0 * float(Game.god_cycles)))
		"banana":
			Game.heal(15.0)
			Sfx.play("eat")
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash("Pottasium.")
		"shroom":
			Game.heal(22.0)
			Sfx.play("eat")
		"meat":
			Game.heal(6.0)   # raw. gross.
			Sfx.play("eat")
		"cooked_meat":
			Game.heal(40.0)
			Sfx.play("eat")
		"salad":
			Game.eat_salad()
		_:
			return false
	clear_slot(slot)
	Sfx.play("click")
	return true

# ------------------------------------------------------------- currency

func add_coins(n: int) -> void:
	coins += n
	changed.emit()

func lose_half() -> void:
	coins = coins / 2
	zeptobux = zeptobux / 2
	changed.emit()

func deposit_all() -> void:
	bank_coins += coins
	coins = 0
	bank_zepto += zeptobux
	zeptobux = 0
	changed.emit()

func withdraw_all() -> void:
	coins += bank_coins
	bank_coins = 0
	zeptobux += bank_zepto
	bank_zepto = 0
	changed.emit()

# ----------------------------------------------------------------- shop

func cost_of(id: String) -> Dictionary:
	for it in catalog:
		if it.id == id:
			return it["cost"]
	return {"coins": 999999}

func cost_text(id: String) -> String:
	var parts: Array = []
	var c := cost_of(id)
	if c.has("coins"):
		parts.append("%d coins" % int(c["coins"]))
	for r in STACKABLE:
		if c.has(r):
			parts.append("%d %s" % [int(c[r]), r])
	return " + ".join(parts)

func needs_recipe(id: String) -> bool:
	if Game.free_craft:
		return false
	for it in catalog:
		if it.id == id:
			return bool(it.get("recipe", false)) and not ak47_recipe
	return false

func owned_unique(id: String) -> bool:
	if weapons.has(id):
		for cont in [hotbar, backpack_store]:
			for s in cont:
				if str(s["id"]) == id:
					return true
		return false
	match id:
		"jetpack": return has_jetpack
		"jetpack2": return jet_max >= 500.0
		"jetpack3": return jet_max >= 1000.0
		"ward": return wrath_ward
		"engine_mk2": return engine_mk2
		# hyperdrive: rebuyable -- one per ship
	return false

func can_afford(id: String) -> bool:
	if Game.free_craft:
		return true
	var c := cost_of(id)
	if coins < int(c.get("coins", 0)):
		return false
	for r in STACKABLE:
		if res_count(r) < int(c.get(r, 0)):
			return false
	return true

func can_buy(id: String) -> bool:
	if owned_unique(id) or needs_recipe(id):
		return false
	return can_afford(id) and any_space()

## Buying/crafting: pays coins + resource stacks -> item lands in hotbar.
func buy(id: String) -> bool:
	if not can_buy(id):
		Sfx.play("denied")
		return false
	var c := cost_of(id)
	if not Game.free_craft:
		coins -= int(c.get("coins", 0))
		for r in STACKABLE:
			if c.has(r):
				remove_res(r, int(c[r]))
	var cnt := 1
	for it in catalog:
		if it.id == id:
			cnt = int(it.get("count", 1))
	give(id, cnt)
	Sfx.play("coin")
	changed.emit()
	return true

func reset() -> void:
	coins = 0
	bank_coins = 0
	zeptobux = 0
	bank_zepto = 0
	fuel = 0.0
	fuel_max = 100.0
	jet_fuel = 0.0
	jet_max = 100.0
	jet_power = 1.0
	jet_on = false
	has_rcs = false
	has_jetpack = false
	wrath_ward = false
	engine_mk2 = false
	ak47_recipe = false
	artifact_taken = false
	_blank_containers()
	selected = 0
	caged_data = []
	equip = {"head": "", "chest": "", "legs": "", "boots": "", "charm": ""}
	changed.emit()
