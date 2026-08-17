class_name Mats
extends RefCounted
## THE MATERIAL REGISTRY. Every ore, dust, ingot and alloy in the game,
## what it looks like, which planets actually have it, and what it turns
## into. One table, read by the auto-miners, the crushers, the alloy
## furnaces, the shop and the inventory alike -- adding a material is
## adding a row here, not editing six files.
##
## Richness is 0..5 per planet: 5 means the ground is thick with it, 1
## means traces, 0 means the planet has none and a miner has to fabricate
## it out of dust (glacially, expensively). If you want gold, go to
## Euclid. If you want dudium, go to Logica.

# ------------------------------------------------------------ materials

## kind: "ore" raw dug rock · "dust" crushed · "ingot" smelted metal
##       "alloy" furnace product
static var _m: Dictionary = {}
static var _ores: Array[String] = []
static var _alloys: Array[String] = []
static var _products: Array[String] = []

static func _row(id: String, name: String, col: String, kind: String,
		tier: int, extra: Dictionary = {}) -> void:
	var d := {"id": id, "name": name, "color": Color(col), "kind": kind, "tier": tier}
	d.merge(extra)
	_m[id] = d

static func _build() -> void:
	if not _m.is_empty():
		return
	# --- the nine mined metals. raw_x is what comes out of the ground,
	# x is the ingot it smelts into, dust_x is the crushed middle step
	# (crush first and one rock gives TWO ingots instead of one)
	var metals := [
		["copper", "Copper", "#c8722f", 1],
		["tin", "Tin", "#c9c9cf", 1],
		["zinc", "Zinc", "#a8b6bd", 2],
		["gold", "Gold", "#ffd23f", 2],
		["titanium", "Titanium", "#9fb3c8", 3],
		["aerinite", "Aerinite", "#5ad0ff", 3],
		["abyssite", "Abyssite", "#2a1f4a", 4],
		["neptunium", "Neptunium", "#3a6bff", 4],
		["dudium", "Dudium", "#7dff9a", 5],
	]
	for mt in metals:
		var id: String = mt[0]
		_row("raw_" + id, str(mt[1]) + " Ore", str(mt[2]), "ore", int(mt[3]),
			{"ingot": id})
		_row("dust_" + id, str(mt[1]) + " Dust", str(mt[2]), "dust", int(mt[3]),
			{"ingot": id})
		# aerinite is a MINERAL, not a metal -- a blue calcium-iron
		# aluminosilicate, the pigment on half the old murals in the
		# universe. It refines into a block of pigment-grade stone; it
		# does not pour into an ingot, whatever the furnace says.
		_row(id, ("Refined " + str(mt[1])) if id == "aerinite"
			else (str(mt[1]) + " Ingot"), str(mt[2]), "ingot", int(mt[3]))
		_ores.append("raw_" + id)
	# --- the non-metal diggings: ice for water, sand for silica, and
	# astronite, which only exists near a reactor core
	_row("raw_ice", "Ice", "#a8e8ff", "ore", 1, {})
	_row("raw_sand", "Silica Sand", "#e8d9a8", "ore", 1, {})
	_row("astronite", "Astronite", "#ffd23f", "ore", 5, {})
	_ores.append("raw_ice")
	_ores.append("raw_sand")
	_ores.append("astronite")
	# the two metals that were already here get dust + richness too
	_row("dust_iron", "Iron Dust", "#d8d8e8", "dust", 0, {"ingot": "ingot"})
	_row("dust_irid", "Iridium Dust", "#59ffc4", "dust", 3, {"ingot": "irid"})

	# --- alloys. tier = the FURNACE tier needed to pour it
	_alloy("bronze", "Bronze", "#b87333", 1,
		{"copper": 3, "tin": 1}, 4, 6.0,
		"The first alloy anybody ever made. Tough, cheap, everywhere.")
	_alloy("brass", "Brass", "#d4b03c", 1,
		{"copper": 2, "zinc": 1}, 3, 6.0,
		"Machines like brass. Gears, fittings, anything that has to turn.")
	_alloy("steel", "Steel", "#8f9ba8", 1,
		{"ingot": 2, "coal": 1}, 2, 8.0,
		"Iron with the softness burned out of it. The spine of every factory.")
	_alloy("electrum", "Electrum", "#f5d76e", 1,
		{"gold": 3, "tin": 1}, 4, 9.0,
		"Gold cut with enough else to be useful. Conducts like a rumour.")
	_alloy("aerinsteel", "Aerinsteel", "#7fd6e8", 2,
		{"steel": 2, "aerinite": 1}, 2, 11.0,
		"Steel that weighs almost nothing. Aerinite does that.")
	_alloy("invar", "Invar", "#6f7f93", 2,
		{"ingot": 2, "neptunium": 1}, 2, 12.0,
		"Refuses to expand when heated. Everything precise is made of it.")
	_alloy("nichrome", "Nichrome", "#c46a4a", 2,
		{"steel": 1, "titanium": 1, "zinc": 1}, 2, 12.0,
		"Glows instead of melting. Heating elements, and the good furnaces.")
	_alloy("duralumin", "Duralumin", "#b9c6d4", 2,
		{"aerinite": 3, "copper": 1}, 3, 12.0,
		"Light, hard, and the reason anything flies.")
	_alloy("stainless", "Stainless", "#c3ccd6", 2,
		{"steel": 2, "titanium": 1}, 2, 13.0,
		"Never rusts, never stains, never forgives a bad weld.")
	_alloy("abyssbronze", "Abyssal Bronze", "#4a3f6e", 3,
		{"bronze": 2, "abyssite": 1}, 2, 16.0,
		"Bronze poured in the dark and cooled in something colder than water.")
	_alloy("abyssitanium", "Abyssitanium", "#5c6bb0", 3,
		{"abyssite": 2, "titanium": 2}, 2, 20.0,
		"Abyssite holds titanium the way a black hole holds a rumour.")
	_alloy("neptunite", "Neptunite", "#3f7bd8", 3,
		{"neptunium": 3, "irid": 1}, 2, 22.0,
		"Cold-blue and faintly wrong. Neptune's whole export economy.")
	_alloy("dudalloy", "Dudalloy", "#6fdc86", 3,
		{"dudium": 2, "steel": 2}, 3, 24.0,
		"Dudium refuses to alloy with anything that isn't trying its best.")
	_alloy("oxidium_alloy", "Oxidium Alloy", "#ff8a2a", 3,
		{"oxidium": 2, "brass": 2, "titanium": 1}, 2, 24.0,
		"Oxidium beaten into something a machinist will accept.")
	_alloy("orilium", "Orilium Alloy", "#f5d76e", 3,
		{"electrum": 20, "abyssitanium": 25, "dudalloy": 6, "aerinsteel": 30}, 4, 75.0,
		"Twenty parts gold-cut, twenty-five parts abyss, and a great deal of patience.")
	_alloy("ultimium", "Ultimium", "#7df9ff", 3,
		{"bronze": 4, "brass": 4, "steel": 4, "electrum": 4, "aerinsteel": 2,
			"invar": 2, "nichrome": 2, "duralumin": 2, "stainless": 2,
			"abyssbronze": 1, "abyssitanium": 1, "neptunite": 1, "dudalloy": 1}, 2, 55.0,
		"A little of everything anybody has ever poured. Not the hardest thing to make -- just the longest list.")
	_alloy("synthanium", "Synthanium", "#9a6bff", 3,
		{"electrum": 2, "aerinsteel": 2, "dudium": 1}, 2, 26.0,
		"Rings when struck and holds the note. Every module panel worth owning is cut from it.")

	# =============================================================== CHEMISTRY
	# Three tiers of lab, and every compound earns its place by being
	# used for at least two other things. Early chemistry comes out of
	# water, air, rock and ash; late chemistry needs the alloys.

	# --- tier 1: the electrolyser, the separator, and Lab I ------------
	_make("water", "Water", "#4a9fd8", "liquid", "sep", 1,
		{"raw_ice": 1}, 2, 4.0,
		"Melted ice. The start of nearly everything wet.",
		"electrolysis · toothpaste · coolant · concrete")
	_make("hydrogen", "Hydrogen", "#d8e8ff", "gas", "electro", 1,
		{"water": 2}, 2, 5.0,
		"Split out of water and desperate to leave.",
		"ammonia · rocket fuel · reduction of ores")
	_make("oxygen", "Oxygen", "#7be8ff", "gas", "electro", 1,
		{"water": 2}, 1, 5.0,
		"The other half of water, and the reason furnaces get hot.",
		"sulfuric acid · liquid oxygen · cutting torches")
	_make("nitrogen", "Nitrogen", "#9fb3c8", "gas", "sep", 1,
		{}, 2, 6.0,
		"Pulled straight out of the air. Four fifths of it, in fact.",
		"ammonia · liquid nitrogen · inert packing")
	_make("argon", "Argon", "#b388ff", "gas", "sep", 1,
		{}, 1, 8.0,
		"Refuses to react with anything, which is exactly the point.",
		"welding shields · plasma furnaces · lamp filling")
	_make("carbon", "Carbon Powder", "#1a1a1a", "solid", "chem", 1,
		{"coal": 2}, 3, 4.0,
		"Coal with everything else burned off it.",
		"steel · gunpowder · filters")
	_make("lye", "Lye", "#e8e0c8", "solid", "chem", 1,
		{"plantfiber": 3, "water": 1}, 2, 6.0,
		"Ash and water, boiled down. Older than metallurgy.",
		"potash · soap-grade cleaner · etching circuit boards")
	_make("potash", "Potash", "#d8c86a", "solid", "chem", 1,
		{"lye": 2, "carbon": 1}, 2, 7.0,
		"Potassium, finally, in a form you can weigh.",
		"potassium nitrate · fertiliser · glassmaking")
	_make("sulfuric", "Sulfuric Acid", "#e8d44a", "liquid", "chem", 1,
		{"sulfur": 2, "oxygen": 1, "water": 1}, 2, 8.0,
		"The workhorse acid. Eats most things, politely.",
		"batteries · leaching ore · nitric acid")
	_make("silica", "Silica Gel", "#cfd8e6", "solid", "chem", 1,
		{"raw_sand": 2, "sulfuric": 1}, 2, 7.0,
		"Sand, dissolved and set again as something useful.",
		"toothpaste · circuit substrate · desiccant")

	# --- tier 2: Lab II, the cryo plant, real industry ----------------
	_make("ammonia", "Ammonia", "#c8ffd8", "gas", "chem", 2,
		{"nitrogen": 2, "hydrogen": 3}, 2, 10.0,
		"Nitrogen persuaded to hold hands with hydrogen. Under protest.",
		"nitric acid · coolant · fertiliser")
	_make("nitric", "Nitric Acid", "#ffd166", "liquid", "chem", 2,
		{"ammonia": 2, "oxygen": 2}, 2, 11.0,
		"Ammonia burned in air and caught in water.",
		"potassium nitrate · aqua regia · etching")
	_make("potnitrate", "Potassium Nitrate", "#f2f2c8", "solid", "chem", 2,
		{"nitric": 2, "potash": 2}, 3, 12.0,
		"Saltpetre. The line where chemistry stops being a hobby.",
		"gunpowder · toothpaste · Timmy's Substance · rocket oxidiser")
	_make("gunpowder", "Gunpowder", "#3a3a3a", "solid", "chem", 2,
		{"potnitrate": 3, "sulfur": 1, "carbon": 2}, 4, 8.0,
		"Saltpetre, sulfur and charcoal. Do not put it near the furnace.",
		"grenades · mining charges · rocket boosters")
	_make("glycerin", "Glycerin", "#e8f0d8", "liquid", "chem", 2,
		{"plantfiber": 4, "lye": 1}, 2, 9.0,
		"Sweet, thick, and quietly explosive in the wrong company.",
		"toothpaste · antifreeze · resin")
	_make("resin", "Polymer Resin", "#9a6bff", "liquid", "chem", 2,
		{"glycerin": 2, "sulfuric": 1, "carbon": 2}, 3, 10.0,
		"Long molecules that hold hands and refuse to let go.",
		"circuit boards · machine housings · insulation")
	_make("coolant", "Coolant", "#5ad0ff", "liquid", "chem", 2,
		{"water": 2, "ammonia": 1, "glycerin": 1}, 3, 9.0,
		"Keeps a reactor from becoming an event.",
		"nuclear reactors · plasma furnaces · deep-core miners")
	_make("chlorine", "Chlorine", "#c8ff6a", "gas", "electro", 2,
		{"water": 2, "sulfur": 1}, 2, 9.0,
		"Green, heavy, and extremely opinionated.",
		"aqua regia · purification · bleaching prism dust")
	_make("aquaregia", "Aqua Regia", "#ff9a3c", "liquid", "chem", 2,
		{"nitric": 1, "chlorine": 3}, 2, 14.0,
		"The one acid gold takes seriously.",
		"refining gold · dissolving iridium · abyssite leaching")
	_make("neon", "Neon Gas", "#ff6ac1", "gas", "sep", 2,
		{"argon": 2}, 1, 14.0,
		"Rare, inert, and the exact colour of a good sign.",
		"neonastroxidium · lamps · plasma ignition")
	_make("liqnitrogen", "Liquid Nitrogen", "#7be8ff", "liquid", "cryo", 2,
		{"nitrogen": 4}, 2, 12.0,
		"Nitrogen, squeezed until it gives up and lies down.",
		"Timmy's Substance · superconductors · flash-freezing samples")
	_make("liqoxygen", "Liquid Oxygen", "#a8d8ff", "liquid", "cryo", 2,
		{"oxygen": 4}, 2, 12.0,
		"Rocket-grade. Handle with the respect it is owed.",
		"rocket fuel · plasma furnaces · cutting alloys")
	_make("thermite", "Thermite", "#ff5964", "solid", "chem", 2,
		{"dust_iron": 3, "dust_aerinite": 2, "oxygen": 1}, 3, 11.0,
		"Burns hot enough to argue with a planet.",
		"welding rails · breaching charges · starting plasma furnaces")

	# --- tier 3: Lab III, the end of the periodic table ---------------
	_make("plasmagel", "Plasma Gel", "#c86bff", "liquid", "chem", 3,
		{"resin": 2, "argon": 2, "prism": 1}, 2, 16.0,
		"A liquid that has been talked into holding a charge.",
		"plasma furnaces · ultima batteries · hard light panels")
	_make("oxidium", "Oxidium", "#ff8a2a", "solid", "chem", 3,
		{"aquaregia": 2, "titanium": 2, "oxygen": 3}, 2, 18.0,
		"An oxide that behaves like a metal and sulks like a gas.",
		"oxidium alloy · neonastroxidium · reactor linings")
	_make("astronium", "Astronium", "#ffd23f", "solid", "chem", 3,
		{"astronite": 2, "plasmagel": 1, "argon": 2}, 2, 22.0,
		"Refined from reactor-core astronite. Still warm. Always warm.",
		"neonastroxidium · star-grade alloys · hyperdrive cores")
	_make("ultranium", "Ultranium", "#7df9ff", "solid", "chem", 3,
		{"ultimium": 2}, 1, 30.0,
		"Two ingots of ultimium folded into one. Same list of ingredients, twice as much of everything, half the size.",
		"ultra toothpaste · omegium · endgame tooling")
	_make("omegium", "Omegium", "#ff3a2a", "solid", "chem", 3,
		{"ultranium": 2}, 1, 45.0,
		"Two of ultranium, which was two of ultimium, which was some of everything. Four folds deep and still stable.",
		"omega toothpaste · Timmy's Substance · final-tier machine frames")
	_make("neonastro", "Neonastroxidium", "#ff6ac1", "solid", "chem", 3,
		{"oxidium_alloy": 15, "neon": 20, "astronium": 50}, 1, 60.0,
		"Neon, astronium and oxidium held in one lattice. It hums.",
		"Timmy's Substance · the only coolant a 4D line will accept")

	# --- the far end. Neither of these is made in a lab. One is drawn
	# off a horizon, the other is grown, and both want their own machine.
	_make("liqblackhole", "Liquid Black Hole", "#1a0d2a", "liquid", "void", 3,
		{}, 1, 120.0,
		"A thread of horizon, wound off slowly and kept in a bottle that never touches it.",
		"Timmy's Substance · the only thing that will hold a 4D line open")
	_make("dna4d", "4D Potassium-Overclocked DNA", "#7dff9a", "solid", "vat", 3,
		{"meat": 4, "potnitrate": 12, "plasmagel": 1, "ultima": 1}, 1, 80.0,
		"Living code fed saltpetre until it started counting in four directions.",
		"Timmy's Substance · overclocked growth vats")
	_make("trunc_synth", "Truncated Synthanium", "#9a6bff", "solid", "chem", 3,
		{"synthanium": 8, "raw_sand": 12, "aquaregia": 2}, 1, 48.0,
		"Synthanium with its corners taken off. Twelve faces short of a solid and all the better for it.",
		"Timmy's Substance · module panels that ring true · precision optics")
	_make("timmy", "Timmy's Substance", "#ffffff", "solid", "chem", 3,
		{"omega_toothpaste": 1, "neonastro": 1, "orilium": 4, "trunc_synth": 1,
			"dna4d": 1, "potnitrate": 1, "liqblackhole": 1, "liqnitrogen": 1}, 1, 240.0,
		"The most complicated material anybody has made. It is not clear that anybody meant to.",
		"nobody has found a second use for it yet, and nobody is looking very hard")

	# --- the toothpaste line, which is a real production chain --------
	_make("toothpaste", "Toothpaste", "#f2f2f2", "solid", "chem", 2,
		{"potnitrate": 2, "silica": 2, "glycerin": 1, "water": 1}, 3, 10.0,
		"Mint not included. Cleans teeth, polishes contacts, seals threads.",
		"ultimate toothpaste · polishing optics · sealing pipe joins")
	_make("ulti_toothpaste", "Ultimate Toothpaste", "#e8f9ff", "solid", "chem", 3,
		{"toothpaste": 2, "ultimium": 1}, 1, 24.0,
		"Toothpaste that has seen things.",
		"ultra toothpaste · enamel-grade abrasive for prism cutting")
	_make("ultra_toothpaste", "Ultra Toothpaste", "#b388ff", "solid", "chem", 3,
		{"ultranium": 3, "potnitrate": 20, "ulti_toothpaste": 17}, 1, 40.0,
		"At this point it is no longer for teeth.",
		"omega toothpaste · abrasive for cutting synthanium")
	_make("omega_toothpaste", "Omega Toothpaste", "#ff3a2a", "solid", "chem", 3,
		{"omegium": 15, "potnitrate": 60, "ultra_toothpaste": 25}, 1, 90.0,
		"The final paste. Nobody remembers who started this.",
		"Timmy's Substance")

static func _alloy(id: String, name: String, col: String, tier: int,
		inputs: Dictionary, out_n: int, secs: float, desc: String) -> void:
	_row(id, name, col, "alloy", tier,
		{"inputs": inputs, "out_n": out_n, "secs": secs, "desc": desc,
		"family": "alloy"})
	_alloys.append(id)

## A recipe for one of the OTHER machine families: "chem" (the labs),
## "sep" (the separator), "cryo" (the condenser), "electro" (the
## electrolyser). Tier is the machine tier needed to run it.
static func _make(id: String, name: String, col: String, kind: String,
		family: String, tier: int, inputs: Dictionary, out_n: int, secs: float,
		desc: String, uses: String = "") -> void:
	_row(id, name, col, kind, tier,
		{"inputs": inputs, "out_n": out_n, "secs": secs, "desc": desc,
		"family": family, "uses": uses})
	_products.append(id)

static func all() -> Dictionary:
	_build()
	return _m

static func has(id: String) -> bool:
	_build()
	return _m.has(id)

static func def(id: String) -> Dictionary:
	_build()
	return _m.get(id, {})

static func ores() -> Array[String]:
	_build()
	return _ores

static func alloys() -> Array[String]:
	_build()
	return _alloys

## Everything an alloy furnace of this tier (and below) can pour.
static func recipes_for_tier(tier: int) -> Array:
	return recipes_for("alloy", tier)

## Every recipe a machine of this family and tier can run.
static func recipes_for(family: String, tier: int) -> Array:
	_build()
	var out: Array = []
	for id in _m.keys():
		var d: Dictionary = _m[id]
		if str(d.get("family", "")) == family and int(d.get("tier", 9)) <= tier \
				and d.has("inputs"):
			out.append(str(id))
	out.sort_custom(func(a3, b3): return int(_m[a3]["tier"]) < int(_m[b3]["tier"]))
	return out

## Is this thing a gas or a liquid? (Some machines only take one.)
static func is_fluid(id: String) -> bool:
	var k := str(def(id).get("kind", ""))
	return k == "gas" or k == "liquid"

## Ore -> the ingot it smelts into (dust smelts to the same thing).
static func smelts_to(id: String) -> String:
	_build()
	var d: Dictionary = _m.get(id, {})
	return str(d.get("ingot", ""))

# ------------------------------------------------------- where it lives

## Richness 0..5 of `ore_id` on a planet. Named planets first, then a
## fallback by planet KIND so new worlds still have geology.
const RICH := {
	"raw_copper":    {"Home": 4, "Circuitia": 3, "Verdant": 2, "Mars": 2, "Earth": 2},
	"raw_tin":       {"Verdant": 4, "Home": 3, "Earth": 2, "Donut": 3},
	"raw_zinc":      {"Extroma": 5, "Sanus": 3, "Venus": 3, "Mercury": 2},
	"raw_gold":      {"Euclid": 5, "Mercury": 4, "Venus": 2, "Home": 1},
	"raw_titanium":  {"Mars": 5, "Sanus": 4, "Crystalia": 2, "Mercury": 3},
	"raw_aerinite":  {"Wobble": 5, "Xero": 4, "Wireframe": 3, "Pixel": 2, "Blind": 2},
	"raw_abyssite":  {"Undros": 5, "Requiem": 3, "Contrast": 2, "Datamosh": 2},
	"raw_neptunium": {"Neptune": 5, "Uranus": 3, "Xero": 2, "Saturn": 2},
	"raw_dudium":    {"Logica": 5, "Circuitia": 3, "Pi": 2, "Harold": 1},
	"raw_ice":       {"Xero": 5, "Neptune": 3, "Uranus": 3, "Blind": 2, "Verdant": 1},
	"raw_sand":      {"Euclid": 5, "Mars": 3, "Home": 2, "Mercury": 2},
	"astronite":     {},
}
const RICH_KIND := {
	"raw_copper":    {"home": 4, "circuit": 3, "life": 2, "rock": 2},
	"raw_tin":       {"life": 3, "home": 3, "earth": 2},
	"raw_zinc":      {"volcanic": 4, "lava": 3, "venus": 3},
	"raw_gold":      {"sand": 4, "mercury": 4, "crystal": 2},
	"raw_titanium":  {"mars": 4, "lava": 3, "crystal": 2},
	"raw_aerinite":  {"wob": 4, "ice": 4, "wireframe": 3, "pixel": 2},
	"raw_abyssite":  {"ocean": 4, "contrast": 2, "datamosh": 2},
	"raw_neptunium": {"gas": 3, "ice": 2},
	"raw_dudium":    {"logic": 5, "circuit": 3, "pi": 2},
	"raw_ice":       {"ice": 5, "gas": 2, "blind": 2},
	"raw_sand":      {"sand": 5, "mars": 3, "home": 2, "mercury": 2},
}

static func richness(body, ore_id: String) -> int:
	if body == null:
		return 0
	var byname: Dictionary = RICH.get(ore_id, {})
	if byname.has(str(body.name)):
		return int(byname[str(body.name)])
	var bykind: Dictionary = RICH_KIND.get(ore_id, {})
	if bykind.has(str(body.kind)):
		return int(bykind[str(body.kind)])
	# the two originals are common everywhere solid
	if ore_id == "raw_ingot":
		return 3
	if ore_id == "raw_irid":
		return 2
	return 0

## Human-readable: where should I actually go for this?
static func best_worlds(ore_id: String, n: int = 3) -> String:
	var byname: Dictionary = RICH.get(ore_id, {})
	var pairs: Array = []
	for k in byname.keys():
		pairs.append([str(k), int(byname[k])])
	pairs.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var parts: Array = []
	for i in mini(n, pairs.size()):
		parts.append("%s %d/5" % [pairs[i][0], pairs[i][1]])
	return ", ".join(parts) if parts.size() > 0 else "nowhere in particular"

# ------------------------------------------------- glassware chemistry
## Before there were labs there was a bench, three bottles and a burner.
## Every compound has its OWN sequence of operations, and the only way
## to learn one is to work it out -- the bench tells you whether the
## last thing you did helped, not what to do next.

const HAND_OPS: Array[String] = ["HEAT", "STIR", "COOL", "SHAKE",
	"FILTER", "ELECTRIFY", "GRIND", "SETTLE", "DISTILL"]

## Deterministic, unique-ish per compound: the same recipe every game,
## a different one for every chemical.
static func hand_sequence(id: String) -> Array:
	var h := 0
	for i in id.length():
		h = (h * 31 + id.unicode_at(i)) % 100003
	var n := 3 + (h % 3)                      # three to five steps
	var seq: Array = []
	var last := -1
	for i in n:
		h = (h * 131 + 17) % 100003
		var pick := h % HAND_OPS.size()
		if pick == last:                      # never the same step twice running
			pick = (pick + 1 + (h % 3)) % HAND_OPS.size()
		last = pick
		seq.append(HAND_OPS[pick])
	return seq

## What a bench can actually make: the first rung of every family.
static func hand_makeable() -> Array:
	_build()
	var out: Array = []
	for id in _m.keys():
		var d: Dictionary = _m[id]
		if not d.has("inputs"):
			continue
		if int(d.get("tier", 9)) <= 1 and str(d.get("family", "")) in ["chem", "electro", "sep"]:
			out.append(str(id))
	out.sort()
	return out

## Which compound (if any) these bottles could become.
static func hand_match(bottles: Dictionary) -> String:
	for id in hand_makeable():
		var need: Dictionary = def(id).get("inputs", {})
		if need.is_empty():
			continue
		var ok := true
		for k in need.keys():
			if int(bottles.get(k, 0)) < int(need[k]):
				ok = false
				break
		if ok:
			return str(id)
	return ""

# ------------------------------------------------------------- miners

## Which auto-miner tier can pull this ore out of the ground at all.
static func miner_tier(ore_id: String) -> int:
	_build()
	var t := int(def(ore_id).get("tier", 0))
	if t <= 1:
		return 1
	if t <= 3:
		return 2
	return 3

## Every ore a miner of this tier may target, in tier order.
static func ores_for_miner(tier: int) -> Array:
	_build()
	var out: Array = ["raw_ingot", "raw_irid"]
	for id in _ores:
		if miner_tier(id) <= tier:
			out.append(id)
	return out
