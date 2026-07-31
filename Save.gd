extends Node
## Autoload "Save". Three persistent slots on disk. Each stores the
## character (colour, shader skin, drawing) plus run progress.

var current_slot: int = 0
var character: Dictionary = {"color": "#3aa0ff", "shader": "none"}
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

func set_world(w: Array) -> void:
	world_objs = w
	_world_set = true

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
	Inventory.has_rcs = bool(_progress.get("has_rcs", false))
	Inventory.has_jetpack = bool(_progress.get("has_jetpack", false))
	Inventory.wrath_ward = bool(_progress.get("wrath_ward", false))
	Inventory.engine_mk2 = bool(_progress.get("engine_mk2", false))
	Inventory.ak47_recipe = bool(_progress.get("ak47_recipe", false))
	Inventory.artifact_taken = bool(_progress.get("artifact_taken", false))
	Inventory.hotbar = parse_slots(_progress.get("hotbar", []), 5)
	Inventory.backpack_store = parse_slots(_progress.get("backpack", []),
		maxi(20, int(_progress.get("pack_size", 20))))
	Inventory.selected = int(_progress.get("selected", 0))
	Game.score = int(_progress.get("score", 0))
	Game.wrath = float(_progress.get("wrath", 0.0))
	Game.door_open = bool(_progress.get("door_open", false))
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
		"has_rcs": Inventory.has_rcs,
		"has_jetpack": Inventory.has_jetpack,
		"wrath_ward": Inventory.wrath_ward,
		"engine_mk2": Inventory.engine_mk2,
		"ak47_recipe": Inventory.ak47_recipe,
		"artifact_taken": Inventory.artifact_taken,
		"hotbar": Inventory.hotbar,
		"backpack": Inventory.backpack_store,
		"pack_size": Inventory.backpack_store.size(),
		"selected": Inventory.selected,
		"score": Game.score,
		"wrath": Game.wrath,
		"door_open": Game.door_open,
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
		"pet_g": _pet_genome,
		"pet_stay": _pet_stay,
		"pos": _last_pos,
		"in_rocket": _last_in_rocket,
		"in_rocket_hyper": _last_hyper,
		"pet": _last_pet,
	}
	_write(current_slot, _progress)

var _last_pos: Array = []
var _last_in_rocket: bool = false
var _last_hyper: bool = false
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

func set_player_pos(p: Vector3, in_rocket: bool = false, hyper: bool = false) -> void:
	_last_pos = [p.x, p.y, p.z]
	_last_in_rocket = in_rocket
	_last_hyper = hyper

func was_hyper() -> bool:
	return bool(_progress.get("in_rocket_hyper", false))

func delete_slot(n: int) -> void:
	if slot_exists(n):
		DirAccess.remove_absolute(slot_path(n))
	if FileAccess.file_exists(paint_path(n)):
		DirAccess.remove_absolute(paint_path(n))
