extends Node
## Autoload "Save". Three persistent slots on disk. Each stores the
## character (colour, shader skin, drawing) plus run progress.

var current_slot: int = 0
var character: Dictionary = {"color": "#3aa0ff", "shader": "none"}
var ephemeral: bool = false   # tutorial session: never write anything to disk
var save_name: String = ""
var _progress: Dictionary = {}

const SAVE_DIR := "user://saves"

func _ready() -> void:
	var root := DirAccess.open("user://")
	if root and not root.dir_exists("saves"):
		root.make_dir("saves")
	_migrate_legacy()

## Old fixed slots (slot0-2.json) move into the unlimited system untouched.
func _migrate_legacy() -> void:
	for n in 3:
		var old := "user://slot%d.json" % n
		if not FileAccess.file_exists(old):
			continue
		var id := next_id()
		var f := FileAccess.open(old, FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				parsed["name"] = "SLOT %d" % (n + 1)   # legacy badge of honour
				txt = JSON.stringify(parsed)
			var g := FileAccess.open(slot_path(id), FileAccess.WRITE)
			if g:
				g.store_string(txt)
				g.close()
			DirAccess.remove_absolute(old)
		var oldp := "user://slot%d_paint.png" % n
		if FileAccess.file_exists(oldp):
			DirAccess.rename_absolute(oldp, paint_path(id))
	# backfill: saves migrated before naming existed get their legacy name
	for id2 in list_saves():
		var d := _read(id2)
		if not d.is_empty() and not d.has("name"):
			d["name"] = "SLOT %d" % (int(id2) + 1)
			_write(id2, d)

func slot_path(n: int) -> String:
	return "%s/save_%d.json" % [SAVE_DIR, n]

func paint_path(n: int) -> String:
	return "%s/save_%d_paint.png" % [SAVE_DIR, n]

## Every save id on disk, in order.
func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("save_") and f.ends_with(".json"):
			out.append(int(f.trim_prefix("save_").trim_suffix(".json")))
	out.sort()
	return out

func next_id() -> int:
	var ids := list_saves()
	return (int(ids.back()) + 1) if not ids.is_empty() else 0

func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))

func slot_summary(n: int) -> String:
	if not slot_exists(n):
		return "— empty —"
	var d := _read(n)
	var s := "coins %d · score %d" % [int(d.get("coins", 0)), int(d.get("score", 0))]
	if bool(d.get("cheated", false)):
		s += " · ILLEGITIMATE"
	return s

func _read(n: int) -> Dictionary:
	if not slot_exists(n):
		return {}
	var f := FileAccess.open(slot_path(n), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

var _backed: Dictionary = {}   # slots already backed up this session

func _write(n: int, d: Dictionary) -> void:
	# first write of the session: keep yesterday's file as .bak so a bad
	# load can NEVER destroy a base beyond recovery
	if not _backed.has(n) and FileAccess.file_exists(slot_path(n)):
		var src := FileAccess.open(slot_path(n), FileAccess.READ)
		if src:
			var bak := FileAccess.open(slot_path(n) + ".bak", FileAccess.WRITE)
			if bak:
				bak.store_string(src.get_as_text())
				bak.close()
			src.close()
		_backed[n] = true
	if ephemeral:
		return   # tutorial session: nothing ever touches disk
	var f := FileAccess.open(slot_path(n), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()

func load_slot(n: int) -> void:
	current_slot = n
	_progress = _read(n)
	character = _progress.get("character", {"color": "#3aa0ff", "shader": "none"})
	save_name = str(_progress.get("name", "SAVE %d" % n))

func new_slot(n: int, char_data: Dictionary, sname: String = "") -> void:
	current_slot = n
	character = char_data
	save_name = sname if sname.strip_edges() != "" else "Dude %d" % (n + 1)
	_progress = {"character": char_data, "name": save_name}
	_write(n, _progress)

func slot_name(n: int) -> String:
	var d := _read(n)
	return str(d.get("name", "SAVE %d" % n))

func loaded_paint() -> Texture2D:
	# LAN guests keep their face in memory, never on disk
	if ephemeral and Net.guest_paint.size() > 0:
		var gimg := Image.new()
		if gimg.load_png_from_buffer(Net.guest_paint) == OK:
			return ImageTexture.create_from_image(gimg)
	var p := paint_path(current_slot)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load(p) != OK:
		return null
	return ImageTexture.create_from_image(img)

var snaps: Array = []   # time-rift snapshots (persisted)
var world_objs: Array = []   # player-placed machines/chests/etc

var _world_set: bool = false

## THE WORLD GUARD. A healthy world array always has content in it (the
## human census alone is dozens of entries), so an EMPTY one means the
## collector broke, not that the player bulldozed the planet. Refusing
## the write is what stands between a script error and somebody's base.
func set_world(w: Array) -> void:
	if w.is_empty() and not world_objs.is_empty():
		push_warning("save: refused to overwrite %d world objects with an empty list"
			% world_objs.size())
		return
	world_objs = w
	_world_set = true

# ------------------------------------------------ LAN guest data (host side)

## The host's save remembers every guest by name -- their bags, coins and
## character come back next time they join, Minecraft-server style.
func guest_blob(pname: String) -> Dictionary:
	var gd = _progress.get("guest_data", {})
	return gd.get(pname, {}) if gd is Dictionary else {}

func store_guest_blob(pname: String, blob: Dictionary) -> void:
	var gd = _progress.get("guest_data", {})
	if not (gd is Dictionary):
		gd = {}
	gd[pname] = blob
	_progress["guest_data"] = gd

## Everything that makes THIS player themselves (synced to the host).
func build_player_blob() -> Dictionary:
	var blob := {
		"character": character,
		"coins": Inventory.coins,
		"equip": Inventory.equip,
		"hotbar": Inventory.hotbar,
		"backpack": Inventory.backpack_store,
		"prism_pack": Inventory.prism_store,
		"has_jetpack": Inventory.has_jetpack,
		"jet_fuel": Inventory.jet_fuel,
		"jet_max": Inventory.jet_max,
		"jet_power": Inventory.jet_power,
		"fuel": Inventory.fuel,
		"fuel_max": Inventory.fuel_max,
	}
	# where I'm standing rides along: rejoining puts me back HERE, not
	# at the server spawn on the north pole
	var p = get_tree().get_first_node_in_group("player")
	if p:
		blob["pos"] = [p.global_position.x, p.global_position.y, p.global_position.z]
	return blob

## Guest joining a LAN server: boot into the HOST's world snapshot.
## Ephemeral -- this machine's disk is never touched.
func begin_guest_session(snap: Dictionary, blob: Dictionary) -> void:
	ephemeral = true
	current_slot = 99
	_progress = {
		"world": snap.get("world", []),
		"playtime": float(snap.get("playtime", 0.0)),
		"spawn": snap.get("spawn", null),
		"spawn_up": snap.get("spawn_up", [0, 1, 0]),
		"pos": snap.get("spawn", null),   # fallback: the server spawn
		# (a returning player's blob overrides this below -- you come
		# back exactly where you logged out)
		"wseed": snap.get("wseed", 0),    # guests build the HOST's terrain
	}
	# the HOST's world scale + density rule the terrain: a guest whose
	# own slot used a different wscale was generating planets at the
	# wrong size -- cities, mines, everything landed somewhere else
	character["wscale"] = float(snap.get("wscale", 1.0))
	character["bscale"] = bool(snap.get("bscale", false))
	for k in blob.keys():
		if k == "character":
			continue   # you just dressed for this visit -- local look wins
		_progress[k] = blob[k]
	_progress["character"] = character
	save_name = Net.my_name()

func saved_world() -> Array:
	var w = _progress.get("world", [])
	return w if w is Array else []

## Push saved run progress into the live Inventory/Game (called by Main).
func apply_progress() -> void:
	if _progress.is_empty():
		return
	Inventory.coins = int(_progress.get("coins", 0))
	Inventory.bank_coins = int(_progress.get("bank_coins", 0))
	Inventory.zeptobux = int(_progress.get("zeptobux", 0))
	Inventory.bank_zepto = int(_progress.get("bank_zepto", 0))
	Inventory.fuel = float(_progress.get("fuel", 0.0))
	Inventory.fuel_max = float(_progress.get("fuel_max", 100.0))
	Inventory.jet_fuel = float(_progress.get("jet_fuel", 0.0))
	Inventory.jet_max = float(_progress.get("jet_max", 100.0))
	Inventory.jet_power = float(_progress.get("jet_power", 1.0))
	Inventory.jet_on = bool(_progress.get("jet_on", false))
	Inventory.enchant = _progress.get("enchant", {})
	Inventory.hyper_rockets = int(_progress.get("hyper_rockets", 0))
	var eq = _progress.get("equip", null)
	if eq is Dictionary:
		for k in ["head", "chest", "legs", "boots", "charm"]:
			Inventory.equip[k] = str(eq.get(k, ""))
	var svp = _progress.get("spawn", null)
	if svp is Array and svp.size() == 3:
		var svu = _progress.get("spawn_up", [0, 1, 0])
		Game.set_spawn(Vector3(float(svp[0]), float(svp[1]), float(svp[2])),
			Vector3(float(svu[0]), float(svu[1]), float(svu[2])).normalized())
		Game.has_saved_spawn = true
	else:
		Game.has_saved_spawn = false
	Game.tutorial_done = bool(_progress.get("tut_done", false))
	Game.god_cycles = int(_progress.get("god_cycles", 0))
	# world seed: minted once per save, permanent after -- terrain stops
	# rerolling itself every time you rejoin
	Game.world_seed = int(_progress.get("wseed", 0))
	if Game.world_seed == 0:
		Game.world_seed = randi() | 1
		_progress["wseed"] = Game.world_seed
	Game.god_standby_until = float(_progress.get("god_standby_until", -1.0))
	var hc = _progress.get("host_cfg", null)
	if hc is Dictionary:
		for k in Game.host_cfg.keys():
			if hc.has(k):
				Game.host_cfg[k] = hc[k]
	Inventory.has_rcs = bool(_progress.get("has_rcs", false))
	Inventory.has_jetpack = bool(_progress.get("has_jetpack", false))
	Inventory.wrath_ward = bool(_progress.get("wrath_ward", false))
	Inventory.engine_mk2 = bool(_progress.get("engine_mk2", false))
	Inventory.ak47_recipe = bool(_progress.get("ak47_recipe", false))
	Inventory.artifact_taken = bool(_progress.get("artifact_taken", false))
	Inventory.hotbar = parse_slots(_progress.get("hotbar", []), 5)
	# migration: an old 40-slot upgraded backpack splits 20/20 into prism
	var rawbp = _progress.get("backpack", [])
	Inventory.backpack_store = parse_slots(rawbp, 20)
	Inventory.prism_store = parse_slots(_progress.get("prism_pack", []), 40)
	if rawbp is Array and rawbp.size() > 20:
		var extra := parse_slots(rawbp.slice(20), 20)
		for i in extra.size():
			if str(extra[i]["id"]) != "":
				Inventory.prism_store[i] = extra[i]
	Inventory.universe_store = parse_slots(_progress.get("universe_pack", []), 20)
	Inventory.selected = int(_progress.get("selected", 0))
	Game.score = int(_progress.get("score", 0))
	Game.wrath = float(_progress.get("wrath", 0.0))
	Game.god_peace = float(_progress.get("god_peace", 0.0))
	Game.door_open = bool(_progress.get("door_open", false))
	Game.monolith_stage = int(_progress.get("monolith_stage", 0))
	Game.void_loot = _progress.get("void_loot", {})
	Game.ai_blessed = bool(_progress.get("ai_blessed", false))
	Game.chem_manual = bool(_progress.get("chem_manual", false))
	Game.charts_unlocked = bool(_progress.get("charts_unlocked", false))
	Game.white_beaten = bool(_progress.get("white_beaten", false))
	Game.lime_taken = bool(_progress.get("lime_taken", false))
	Game.lime_wall_open = bool(_progress.get("lime_wall_open", false))
	Game.harold_shelf_open = bool(_progress.get("harold_shelf_open", false))
	Game.facility_power = float(_progress.get("facility_power", 1800.0))
	Game.mind_core = bool(_progress.get("mind_core", false))
	Game.cheated = bool(_progress.get("cheated", false))
	Game.godmode = bool(_progress.get("c_god", false))
	Game.inf_fuel = bool(_progress.get("c_fuel", false))
	Game.creative = bool(_progress.get("c_creative", false))
	Game.keep_inv = bool(_progress.get("c_keepinv", false))
	Game.free_craft = bool(_progress.get("c_freecraft", false))
	Game.zone = str(_progress.get("zone", ""))
	Game.zone_g = float(_progress.get("zone_g", 9.0))
	Game.playtime = float(_progress.get("playtime", 0.0))
	var sn = _progress.get("snaps", [])
	snaps = sn if sn is Array else []
	var cg = _progress.get("caged", [])
	Inventory.caged_data = cg if cg is Array else []
	var fl = _progress.get("floppies", [])
	Inventory.floppy_data = fl if fl is Array else []
	Inventory.changed.emit()
	Game.changed.emit()

## Normalize a saved container to size `n` of {"id","n"} slots.
## Accepts legacy plain-string arrays too.
static func parse_slots(raw, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": "", "n": 0})
	if raw is Array:
		for i in mini(raw.size(), n):
			var e = raw[i]
			if e is Dictionary and e.has("id"):
				out[i] = {"id": str(e["id"]), "n": maxi(1, int(e.get("n", 1))) if str(e["id"]) != "" else 0}
			elif e is String and e != "":
				out[i] = {"id": e, "n": 1}
	return out

func was_in_rocket() -> bool:
	return bool(_progress.get("in_rocket", false))

## Saved position (so a black-hole trap is still a trap when you come back).
func saved_pos() -> Variant:
	var p = _progress.get("pos", null)
	if p is Array and p.size() == 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return null

func save_progress() -> void:
	# (player pos supplied by Main via set_player_pos)
	_progress = {
		"character": character,
		"name": save_name,
		"coins": Inventory.coins,
		"bank_coins": Inventory.bank_coins,
		"zeptobux": Inventory.zeptobux,
		"bank_zepto": Inventory.bank_zepto,
		"fuel": Inventory.fuel,
		"fuel_max": Inventory.fuel_max,
		"jet_fuel": Inventory.jet_fuel,
		"jet_max": Inventory.jet_max,
		"jet_power": Inventory.jet_power,
		"jet_on": Inventory.jet_on,
		"enchant": Inventory.enchant,
		"hyper_rockets": Inventory.hyper_rockets,
		"equip": Inventory.equip,
		"spawn": [Game.spawn_pos.x, Game.spawn_pos.y, Game.spawn_pos.z],
		"spawn_up": [Game.spawn_up.x, Game.spawn_up.y, Game.spawn_up.z],
		"tut_done": Game.tutorial_done,
		"god_cycles": Game.god_cycles,
		"wseed": Game.world_seed,
		"god_standby_until": Game.god_standby_until,
		"host_cfg": Game.host_cfg,
		"guest_data": _progress.get("guest_data", {}),
		"has_rcs": Inventory.has_rcs,
		"has_jetpack": Inventory.has_jetpack,
		"wrath_ward": Inventory.wrath_ward,
		"engine_mk2": Inventory.engine_mk2,
		"ak47_recipe": Inventory.ak47_recipe,
		"artifact_taken": Inventory.artifact_taken,
		"hotbar": Inventory.hotbar,
		"backpack": Inventory.backpack_store,
		"prism_pack": Inventory.prism_store,
		"universe_pack": Inventory.universe_store,
		"selected": Inventory.selected,
		"score": Game.score,
		"wrath": Game.wrath,
		"door_open": Game.door_open,
		"monolith_stage": Game.monolith_stage,
		"void_loot": Game.void_loot,
		"ai_blessed": Game.ai_blessed,
		"chem_manual": Game.chem_manual,
		"charts_unlocked": Game.charts_unlocked,
		"white_beaten": Game.white_beaten,
		"god_peace": Game.god_peace,
		"lime_taken": Game.lime_taken,
		"lime_wall_open": Game.lime_wall_open,
		"harold_shelf_open": Game.harold_shelf_open,
		"facility_power": Game.facility_power,
		"mind_core": Game.mind_core,
		"cheated": Game.cheated,
		"c_god": Game.godmode,
		"c_fuel": Game.inf_fuel,
		"c_creative": Game.creative,
		"c_keepinv": Game.keep_inv,
		"c_freecraft": Game.free_craft,
		"zone": Game.zone,
		"zone_g": Game.zone_g,
		"playtime": Game.playtime,
		"snaps": snaps,
		"world": world_objs if _world_set else _progress.get("world", []),
		"caged": Inventory.caged_data,
		"floppies": Inventory.floppy_data,
		"pet_g": _pet_genome,
		"pet_stay": _pet_stay,
		"pos": _last_pos,
		"in_rocket": _last_in_rocket,
		"in_rocket_hyper": _last_hyper,
		"in_rocket_mk2": _last_mk2,
		"in_rocket_nuc": _last_nuc,
		"in_rocket_edge": _last_edgew,
		"rocket_vel": [_last_vel.x, _last_vel.y, _last_vel.z],
		"hyper_charge": _last_hyperq,
		"pet": _last_pet,
	}
	_write(current_slot, _progress)

var _last_pos: Array = []
var _last_in_rocket: bool = false
var _last_vel: Vector3 = Vector3.ZERO
var _last_hyperq: float = 4.0

func hyper_charge() -> float:
	return float(_progress.get("hyper_charge", 4.0))

func rocket_vel() -> Vector3:
	var a = _progress.get("rocket_vel", [0.0, 0.0, 0.0])
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
var _last_hyper: bool = false
var _last_mk2: bool = false
var _last_nuc: bool = false
var _last_edgew: bool = false
var _last_pet: bool = false
var _pet_genome: int = -1
var _pet_stay: bool = false

func set_pet(has: bool, genome: int = -1, stay: bool = false) -> void:
	_last_pet = has
	_pet_genome = genome
	_pet_stay = stay

func pet_genome() -> int:
	return int(_progress.get("pet_g", -1))

func pet_stay() -> bool:
	return bool(_progress.get("pet_stay", false))

func had_pet() -> bool:
	return bool(_progress.get("pet", false))

func set_player_pos(p: Vector3, in_rocket: bool = false, hyper: bool = false,
		mk2: bool = false, vel: Vector3 = Vector3.ZERO,
		hyperq: float = 4.0, nuc: bool = false, edgew: bool = false) -> void:
	_last_pos = [p.x, p.y, p.z]
	_last_in_rocket = in_rocket
	_last_hyper = hyper
	_last_mk2 = mk2
	_last_vel = vel
	_last_hyperq = hyperq
	_last_nuc = nuc
	_last_edgew = edgew

func was_hyper() -> bool:
	return bool(_progress.get("in_rocket_hyper", false))

func was_mk2() -> bool:
	return bool(_progress.get("in_rocket_mk2", false))

func was_nuclear() -> bool:
	return bool(_progress.get("in_rocket_nuc", false))

func edge_won() -> bool:
	return bool(_progress.get("in_rocket_edge", false))

## Give a world a new name without touching anything else in it.
func rename_slot(n: int, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name == "" or not slot_exists(n):
		return
	var d := _read(n)
	d["name"] = new_name
	var f := FileAccess.open(slot_path(n), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
	if current_slot == n:
		save_name = new_name

func delete_slot(n: int) -> void:
	if slot_exists(n):
		DirAccess.remove_absolute(slot_path(n))
	if FileAccess.file_exists(paint_path(n)):
		DirAccess.remove_absolute(paint_path(n))
