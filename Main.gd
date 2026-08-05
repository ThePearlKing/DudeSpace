extends Node3D
## Builds the whole universe in code: every planet (with its shader or
## material), its content, the player + rocket, and all UI. Runs the two
## global rules each frame: the universe-edge throwback and TIN 618's
## time dilation.

var _player: Player
var _rocket: Rocket
var _hud: HUD
var _rocket_hud: RocketHUD
var _threw_back: bool = false
var _crate_beds: Array = []
var _regen_t: float = 6.0
var _save_t: float = 5.0
var _ore_t: float = 4.0
var _mines: Array = []   # per-planet mine registry
var _last_soi: String = ""
var _pyramid_exit: Vector3 = Vector3.ZERO
var _temple_btn: Gate
var _temple_np: Vector3 = Vector3.ZERO
var _temple_B: Basis = Basis.IDENTITY
var _temple_opened: bool = false
var _trials_started: bool = false
var MINE_DIRS := {
	"Home": Vector3(0.6, 0.45, -0.66).normalized(),
	"Circuitia": Vector3(-0.5, 0.7, 0.4).normalized(),
	"Logica": Vector3(0.8, -0.3, 0.5).normalized(),
	"Pi": Vector3(-0.3, -0.8, 0.5).normalized(),
	"Verdant": Vector3(0.7, 0.2, 0.7).normalized(),
	"Crystalia": Vector3(-0.6, 0.5, -0.6).normalized(),
	"Tutoria": Tutorial.ORE_DIR.normalized(),   # the tutorial's teaching mine
}
var _dens: float = 1.0   # spawn-density multiplier (bscale worlds)

func _n(base: int) -> int:
	return maxi(1, int(round(float(base) * _dens)))

var _snap_t: float = 0.0   # first snapshot IMMEDIATELY, then one per minute
var _arc_t: float = 3.0    # next Sanus lava arc
var _rifts: Array = []                 # rift positions
var _rift_cd: float = 0.0
var _rift_prev: Vector3 = Vector3.ZERO
const C4_POS := Vector3(9000, 6000, -9000)
var _c4: Connect4
var _c4_zone: bool = false
var _burn_t: float = 0.0
var _trial_check_t: float = 1.0
var _ufo: UFO
var _ufo_day: int = -1

var _palette := [
	Color("#ff5964"), Color("#ffd166"), Color("#06d6a0"),
	Color("#4cc9f0"), Color("#b388ff"), Color("#ff8c42"),
]

func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	get_window().grab_focus()
	# per-slot run settings: world scale + hardcore
	Universe.apply_scale(float(Save.character.get("wscale", 1.0)))
	Game.hardcore = bool(Save.character.get("hardcore", false))
	if Game.tutorial_session:
		Universe.enter_tutorial_universe()
	# opt-in loot/object density that keeps up with giant worlds
	if bool(Save.character.get("bscale", false)):
		_dens = Universe.world_scale
	_setup_environment()
	_setup_light()
	for b in Universe.bodies:
		_build_body(b)
	if not Game.tutorial_session:
		_spawn_invaders()
	_spawn_player_and_rocket()

	if not Game.tutorial_session:
		Zones.build_shadow_temple(self, Universe.make_flat_body(Zones.SHADOW_POS))
		_spawn_rifts()
		_spawn_starship()
		_c4 = Connect4.new()
		_c4.add_to_group("connect4")
		add_child(_c4)
		_c4.global_position = C4_POS

	if not Game.tutorial_session:
		add_child(NoodleWatcher.new())   # the god is ALWAYS watching
	add_child(WthStudio.new())       # the WTH station: hole, mast, studio

	_hud = HUD.new()
	add_child(_hud)
	add_child(InventoryUI.new())
	add_child(CalendarUI.new())
	add_child(ChatUI.new())
	add_child(HumanFaceEditor.new())   # F9: dev face editor
	Net.pos_update.connect(_on_net_pos)
	Net.peer_left.connect(_on_net_left)
	Net.peer_identity.connect(_on_net_identity)
	Net.peer_punch.connect(_on_net_punch)
	# session over = every avatar (and its hitboxes) leaves with it
	Net.session_changed.connect(func() -> void:
		if not Net.active:
			for id in _remote_avatars.keys():
				if is_instance_valid(_remote_avatars[id]["root"]):
					_remote_avatars[id]["root"].queue_free()
			_remote_avatars.clear())
	add_child(StorageUI.new())
	add_child(MachineUI.new())
	add_child(MapUI.new())
	add_child(TerminalUI.new())
	add_child(TraderUI.new())
	add_child(CodeUI.new())
	add_child(PiQuizUI.new())
	add_child(TeleportUI.new())
	add_child(LocatorUI.new())
	add_child(PauseMenu.new())
	add_child(StatsOverlay.new())
	_rocket_hud = RocketHUD.new()
	add_child(_rocket_hud)
	_rocket_hud.set_rocket(_rocket)

	Game.reset()
	Save.apply_progress()   # restore this slot's run (no-op on a fresh slot)
	# deterministic world-gen: same save, same Earth, every single time
	seed(Game.world_seed)
	if OS.get_environment("CTD_TEST") != "":
		Save.ephemeral = true   # test rigs NEVER touch real saves again
	if OS.get_environment("CTD_TEST") == "1":
		_self_test()
	if OS.get_environment("CTD_TEST") == "2":
		_rift_test()
	if OS.get_environment("CTD_TEST") == "3":
		_map_pick_test()
	if OS.get_environment("CTD_TEST") == "4":
		_board_test()
	if OS.get_environment("CTD_TEST") == "5":
		_talk_test()
	if OS.get_environment("CTD_TEST") == "6":
		_convo_test()
	if OS.get_environment("CTD_TEST") == "7":
		_apple_test()
	if OS.get_environment("CTD_TEST") == "8":
		_cage_test()
	if OS.get_environment("CTD_TEST") == "9":
		_sit_test()
	if OS.get_environment("CTD_TEST") == "10":
		_gang_test()
	if OS.get_environment("CTD_TEST") == "11":
		_shirt_test()
	if OS.get_environment("CTD_TEST") == "12":
		_neuro_test()
	if OS.get_environment("CTD_TEST") == "13":
		_nade_test()
	if OS.get_environment("CTD_TEST") == "14":
		_sitshirt_test()
	if OS.get_environment("CTD_TEST") == "15":
		_reactor_test()
	if OS.get_environment("CTD_TEST") == "16":
		_house_test()
	if OS.get_environment("CTD_TEST") == "17":
		_winshot_test()
	if OS.get_environment("CTD_TEST") == "18":
		_hole_test()
	if OS.get_environment("CTD_TEST") == "19":
		_door_test()
	if OS.get_environment("CTD_TEST") == "20":
		_radio_test()
	# the interactive tutorial lives ONLY in the dedicated tutorial world
	if Game.tutorial_session and OS.get_environment("CTD_TEST") == "" \
			and OS.get_environment("CTD_NET") == "":
		if Game.tutorial_mode == "reactor":
			add_child(ReactorTutorial.new())
		else:
			add_child(Tutorial.new())
	# headless LAN test rig: CTD_NET=host opens this world to LAN (ephemeral)
	if OS.get_environment("CTD_NET") == "host":
		Save.ephemeral = true   # never touch real slots from a test run
		var cfg := Game.host_cfg.duplicate()
		cfg["port"] = 25999   # off the real port so tests never collide
		print("NETTEST host: ", Net.host(cfg))
	# housing raises the carrying capacity: every human home is +1
	var homes := 0
	for hn0 in get_tree().get_nodes_in_group("house"):
		if hn0 is House and hn0.human_home:
			homes += 1
	Game.earth_pop_target = get_tree().get_nodes_in_group("earth_human").size() + homes
	randomize()   # world built: gameplay dice go back to being dice
	if _player:
		_player.restore_jet()   # jetpack comes back ON if you left it on
	if Game.door_open:
		open_temple_door()   # temple stays open across sessions
	restore_world()          # your machines, chests, wires: still there
	if Save.had_pet() and _player:
		# your buddy waited for you -- the SAME buddy (genome restored)
		var pet := Animal.new()
		pet.setup(Universe.nearest(_player.global_position), false, false, Save.pet_genome())
		add_child(pet)
		pet.global_position = _player.global_position + Vector3(2, 1, 0)
		pet.tame()
		pet.staying = Save.pet_stay()
	# Come back exactly where you left -- gravity zone included, so
	# interior respawns behave. (And yes: still trapped in TIN 618.)
	var sp = Save.saved_pos()
	if sp != null and _player:
		_player.global_position = sp
		if Save.was_in_rocket():
			var rk := Rocket.new()
			rk.mk2 = Save.was_mk2()   # a 2.0 comes back AS a 2.0
			# without this meta the rocket would never save again once parked
			rk.set_meta("placed_id", "rocket2" if rk.mk2 else "rocket")
			add_child(rk)
			rk.global_position = sp
			rk.hyperdrive = Save.was_hyper()
			rk.board(_player)

## Headless: park a Human in front of the player's face and press F.
func _talk_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = p.camera()
	var hum := EarthHuman.new()
	hum.setup(Universe.nearest(p.global_position))
	add_child(hum)
	hum.global_position = cam.global_position - cam.global_transform.basis.z * 4.0
	await get_tree().create_timer(0.5).timeout
	p._interact()
	await get_tree().create_timer(0.3).timeout
	print("TALKTEST bubble: '", hum._bubble.text, "'  alpha: ", hum._bubble.modulate.a)

## Headless: drop a grumpy Kevin next to a mild John, force a chat,
## watch the ledger. Prints every line said plus final opinions.
func _convo_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var kevin := EarthHuman.new()
	var john := EarthHuman.new()
	kevin.setup(home)
	john.setup(home)
	add_child(kevin)
	add_child(john)
	kevin.global_position = p.global_position + Vector3(3, 0, 0)
	john.global_position = p.global_position + Vector3(5, 0, 0)
	await get_tree().create_timer(0.3).timeout
	kevin.human_name = "Kevin"
	john.human_name = "John"
	kevin._pers = {"anxious": 5, "confident": 40, "dreamy": 5, "dumb": 20,
		"grumpy": 95, "goofy": 5, "edgy": 70, "awkward": 5}
	john._pers = {"anxious": 60, "confident": 20, "dreamy": 40, "dumb": 20,
		"grumpy": 10, "goofy": 30, "edgy": 5, "awkward": 40}
	kevin._start_convo(john)
	var k_last := ""
	var j_last := ""
	for i in 120:
		await get_tree().create_timer(0.25).timeout
		if kevin._bubble.text != k_last:
			k_last = kevin._bubble.text
			print("CONVOTEST Kevin: ", k_last)
		if john._bubble.text != j_last:
			j_last = john._bubble.text
			print("CONVOTEST John:  ", j_last)
		if kevin._partner == null and john._partner == null and i > 20:
			break
	print("CONVOTEST john's opinion of kevin: ", john._op(kevin.human_id))
	print("CONVOTEST kevin's opinion of john: ", kevin._op(john.human_id))
	print("CONVOTEST john panicking (fled/punched): ", john._panic_t > 0.0)

## Headless: one human, one dropped permadeath apple. Watch the whole
## arc: lure, bite, boom, meat -- then kill a second one the crude way.
func _apple_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var hum := EarthHuman.new()
	hum.setup(home)
	add_child(hum)
	hum.global_position = p.global_position + Vector3(6, 0, 0)
	var witness := EarthHuman.new()
	witness.setup(home)
	add_child(witness)
	witness.global_position = p.global_position + Vector3(6, 0, 4)
	var ap := ItemDrop.new()
	ap.setup("permapple", 1)
	add_child(ap)
	ap.global_position = p.global_position + Vector3(10, 0, 0)
	for i in 80:
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(hum):
			break
	var meat := 0
	for d in get_tree().get_nodes_in_group("itemdrop"):
		if d is ItemDrop and d.id == "meat":
			meat += d.count
	print("APPLETEST exploded: ", not is_instance_valid(hum),
		"  apple gone: ", not is_instance_valid(ap), "  meat: ", meat)
	print("APPLETEST witness opinion of player: ", witness._op(-1))
	var hum2 := EarthHuman.new()
	hum2.setup(home)
	add_child(hum2)
	hum2.global_position = p.global_position + Vector3(-6, 0, 0)
	await get_tree().create_timer(0.3).timeout
	hum2.take_damage(100.0, Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	var meat2 := 0
	for d in get_tree().get_nodes_in_group("itemdrop"):
		if d is ItemDrop and d.id == "meat":
			meat2 += d.count
	print("APPLETEST killed dead: ", not is_instance_valid(hum2),
		"  meat now: ", meat2)
	print("APPLETEST witness opinion after kill: ", witness._op(-1))

## Headless: box a human, JSON round-trip the box (as a real save would),
## release, and check the same person walked back out.
func _cage_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var a := EarthHuman.new()
	a.setup(home)
	add_child(a)
	a.global_position = p.global_position + Vector3(6, 0, 0)
	await get_tree().create_timer(0.3).timeout
	a._op_add(12345, -60.0)   # a grudge to carry through the cage
	var box: Dictionary = a.capture()
	a.queue_free()
	var b := EarthHuman.new()
	b.saved = JSON.parse_string(JSON.stringify(box))
	b.setup(home)
	add_child(b)
	b.global_position = p.global_position + Vector3(6, 0, 0)
	await get_tree().create_timer(0.3).timeout
	print("CAGETEST name ok: ", b.human_name == str(box["name"]),
		"  id ok: ", b.human_id == int(box["id"]),
		"  grudge ok: ", b._op(12345) == -60.0)
	print("CAGETEST slogan ok: ", str(b.saved.get("slogan", "-")) == str(box.get("slogan", "-")),
		"  hair ok: ", int(b.saved.get("hair", -1)) == int(box.get("hair", -1)),
		"  skin ok: ", str(b.saved.get("skin", "-")) == str(box.get("skin", "-")))
	# JSON text rounds the last float bits; anything under a thousandth
	# of a personality point is the same soul
	print("CAGETEST pers ok: ",
		absf(float(b._pers["grumpy"]) - float(box["pers"]["grumpy"])) < 0.001)

## Headless: street fight between two enemies, then a gang-up rally on
## the player. Verifies swings land, hp drops, hunt triggers, Game.hurt.
func _gang_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var a := EarthHuman.new()
	var b := EarthHuman.new()
	a.setup(home)
	b.setup(home)
	add_child(a)
	add_child(b)
	a.global_position = p.global_position + Vector3(8, 0, 0)
	b.global_position = p.global_position + Vector3(11, 0, 0)
	await get_tree().create_timer(0.3).timeout
	a._op_add(b.human_id, -60.0)
	b._op_add(a.human_id, -60.0)
	a._start_fight(b)
	var hp_a0: float = a.hp
	var hp_b0: float = b.hp
	await get_tree().create_timer(6.0).timeout
	print("GANGTEST fight: a targets b: ", is_instance_valid(a) and a._target == b,
		"  hp lost a: ", (hp_a0 - a.hp) if is_instance_valid(a) else 99.0,
		"  hp lost b: ", (hp_b0 - b.hp) if is_instance_valid(b) else 99.0)
	# now the rally: c hates the player, d is c's friend who dislikes him
	var c := EarthHuman.new()
	var d := EarthHuman.new()
	c.setup(home)
	d.setup(home)
	add_child(c)
	add_child(d)
	c.global_position = p.global_position + Vector3(-6, 0, 0)
	d.global_position = p.global_position + Vector3(-8, 0, 0)
	await get_tree().create_timer(0.3).timeout
	c._op_add(-1, -80.0)
	c._op_add(d.human_id, 60.0)
	d._op_add(-1, -40.0)
	var php0: float = Game.health
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if c._hunt_t > 0.0 and Game.health < php0:
			break
	print("GANGTEST rally: c hunting: ", c._hunt_t > 0.0,
		"  d hunting: ", d._hunt_t > 0.0,
		"  player hp lost: ", php0 - Game.health)

## Windowed: park a camera dead ahead of a slogan shirt and screenshot
## it, so backwards-text reports can be checked with actual eyes.
func _shirt_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var hum := EarthHuman.new()
	hum.saved = {"shirt_roll": 0.9, "slogan": "CERTIFIED MOON NOODLE"}
	hum.setup(home)
	add_child(hum)
	hum.global_position = p.global_position + Vector3(4, 0, 0)
	await get_tree().create_timer(0.8).timeout
	hum._act = "stare"
	hum._act_t = 999.0
	var cam := Camera3D.new()
	add_child(cam)
	var fwd: Vector3 = -hum.global_transform.basis.z
	cam.global_position = hum.global_position + fwd * 2.4 + hum._up() * 0.2
	cam.look_at(hum.global_position + hum._up() * 0.2, hum._up())
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("SHIRTTEST saved front shot")
	# and one from behind: should show NO text at all
	cam.global_position = hum.global_position - fwd * 2.4 + hum._up() * 0.2
	cam.look_at(hum.global_position + hum._up() * 0.2, hum._up())
	await get_tree().create_timer(0.6).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png(OS.get_environment("CTD_SHOT").replace(".png", "_back.png"))
	print("SHIRTTEST saved back shot")

## Windowed: a human seated on a chair, camera on their facing side.
## Screenshot both sides -- chasing the sitting-mirrors-shirts report.
func _sitshirt_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var hum := EarthHuman.new()
	hum.saved = {"shirt_roll": 0.9, "slogan": "CERTIFIED MOON NOODLE"}
	hum.setup(home)
	add_child(hum)
	hum.global_position = p.global_position + Vector3(5, 0, 0)
	var crng := RandomNumberGenerator.new()
	crng.seed = 1
	var dir: Vector3 = ((p.global_position + Vector3(7, 0, 0)) - home.center).normalized()
	_seat_prop(home, dir, crng, false)
	await get_tree().create_timer(0.5).timeout
	var seat: Node3D = null
	var bd := 1e9
	for sn in get_tree().get_nodes_in_group("seat"):
		var d: float = sn.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			seat = sn
	seat.set_meta("taken", true)
	hum._seat = seat
	hum._act = "goseat"
	hum._act_t = 25.0
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		if hum._act == "sit":
			break
	await get_tree().create_timer(0.5).timeout
	var cam := Camera3D.new()
	add_child(cam)
	var fwd: Vector3 = -hum.global_transform.basis.z
	var hup: Vector3 = hum.global_transform.basis.y
	cam.global_position = hum.global_position + fwd * 2.6 + hup * 0.3
	cam.look_at(hum.global_position + hup * 0.3, hup)
	cam.current = true
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("CTD_SHOT"))
	print("SITSHIRT saved  act=", hum._act)

## Births, immigration, whatever it is: keep the planet peopled.
func _repopulate() -> void:
	if Game.earth_body == null or Game.earth_cities.is_empty() \
			or _player == null or Game.earth_pop_target <= 0:
		return
	var b = Game.earth_body
	var ppos: Vector3 = _player.global_position
	if Game.zone != "" and Game.has_proxy:
		ppos = Game.player_proxy   # indoors still counts as present
	if ppos.distance_to(b.center) > float(b.radius) + 250.0:
		return   # nobody's watching: the sim is paused, so is the stork
	var n := 0
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h is EarthHuman and not h._dead:
			n += 1
	if n >= Game.earth_pop_target:
		return
	var ci := randi() % Game.earth_cities.size()
	var city: Dictionary = Game.earth_cities[ci]
	var cd: Vector3 = (city["dir"] + Vector3(randf_range(-0.15, 0.15),
		randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))).normalized()
	var hm := EarthHuman.new()
	hm.saved = {"age": randf_range(0.0, 800.0)}   # young. new in town.
	hm.setup(b)
	hm.home_city = ci
	add_child(hm)
	hm.global_transform = Transform3D(_basis_from_up(cd),
		b.center + cd * (float(b.radius) + 1.2))

## Headless: two houses, a doorframe in each, one Door connect. Verify
## the rooms docked, the walls opened, and the link persisted.
## Headless: spawn a powered radio, aim at station 0, verify sound flow.
func _radio_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var r := RadioTower.new()
	add_child(r)
	r.set_meta("placed_id", "radio")
	r.global_position = p.global_position + Vector3(3, 0, 0)
	await get_tree().create_timer(0.5).timeout
	print("RADIOTEST buses=", AudioServer.bus_count,
		" fxidx=", AudioServer.get_bus_index("RadioFX"),
		" talkbus=", r._talk.bus, " stations=", r.stations.size())
	r.buf = 300.0
	var pick = r.stations[0]
	for st0 in r.stations:
		if str(st0["type"]) == "noodle":
			pick = st0
	r.freq = float(pick["freq"])
	var wgod = get_tree().get_first_node_in_group("noodle_watcher")
	if wgod != null:
		r.track_node = wgod
	print("RADIOTEST aimed at ", pick["name"], " f=", pick["freq"])
	var lastpos := -1.0
	for w8 in 80:
		r.buf = 300.0
		await get_tree().create_timer(0.5).timeout
		var pos := r._talk.get_playback_position() if r._talk.playing else -1.0
		var jumped := pos >= 0.0 and lastpos >= 0.0 and pos < lastpos - 1.0
		print("RADIOTEST t=%.1f talk=%s cur=%d pos=%.2f%s" % [
			float(w8) * 0.5, r._talk.playing, r._cur_station, pos,
			"  <-- RESTART/JUMP" if jumped else ""])
		lastpos = pos

func _door_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var ha := House.new()
	ha.kind = "small"
	add_child(ha)
	ha.global_transform = Transform3D(_basis_from_up(up), home.center + up * home.radius)
	var hb := House.new()
	hb.kind = "box"
	add_child(hb)
	hb.global_transform = Transform3D(_basis_from_up(up),
		home.center + up * home.radius + Vector3(15, 0, 0))
	await get_tree().create_timer(1.5).timeout
	# a frame against the +Z inner wall of each room, facing +Z (-Z out)
	var fa := Furniture.new()
	fa.kind = "doorframe"
	fa.yaw = 0.0
	add_child(fa)
	fa.global_position = ha.room_center() + Vector3(0,
		-ha.room_size().y * 0.5 + 0.3, ha.room_size().z * 0.5 - 0.9)
	fa.rotation_degrees.y = 180.0   # -Z (its "through") points at the wall
	var fb := Furniture.new()
	fb.kind = "doorframe"
	fb.yaw = 0.0
	add_child(fb)
	fb.global_position = hb.room_center() + Vector3(0,
		-hb.room_size().y * 0.5 + 0.3, -hb.room_size().z * 0.5 + 0.9)
	await get_tree().create_timer(0.4).timeout
	print("DOORTEST frames seen: ", ha.my_frames().size(), "/", hb.my_frames().size())
	var b_before: Vector3 = hb.room_center()
	var okc: bool = ha.connect_house(hb)
	await get_tree().create_timer(0.5).timeout
	print("DOORTEST connected: ", okc, "  b moved: %.1f" % b_before.distance_to(hb.room_center()),
		"  links: ", ha.links, "/", hb.links)
	# walk-through probe: horizontal ray from A's room through the cut
	var space := get_tree().root.world_3d.direct_space_state
	var from := ha.room_center() + Vector3(0, -ha.room_size().y * 0.5 + 1.2,
		ha.room_size().z * 0.5 - 1.1)   # past the exit gate, at the wall
	var q := PhysicsRayQueryParameters3D.create(from,
		from + Vector3(0, 0, 6.0))
	var hit := space.intersect_ray(q)
	var reach: float = (hit.position.z - from.z) if hit else 99.0
	print("DOORTEST doorway open: ", reach > 1.6,
		"  (ray travelled %.1f past the wall line)" % reach)

## Headless: raycast down through the basement stairwell hole. If the
## ray stops at the ground floor, the hole is a lie.
func _hole_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var hs := House.new()
	hs.kind = "basement"
	add_child(hs)
	hs.global_transform = Transform3D(_basis_from_up(up), home.center + up * home.radius)
	await get_tree().create_timer(1.5).timeout
	var c := hs.room_center()
	var sz := hs.room_size()
	var fy := c.y - sz.y * 0.5
	var space := get_tree().root.world_3d.direct_space_state
	for probe in [[4.0, 3.0, "HOLE CENTER"], [0.0, 0.0, "solid floor"],
			[4.0, -3.0, "front strip"]]:
		var from := c + Vector3(probe[0], 0.0, probe[1])
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -12, 0))
		var hit := space.intersect_ray(q)
		var drop := -1.0
		var what := "nothing"
		if hit:
			drop = from.y - hit.position.y
			what = str(hit.collider) + " y=" + str(snappedf(hit.position.y, 0.01))
		print("HOLETEST %s: dropped %.2f hit %s (floor top %.2f, c.y %.2f)" % [
			probe[2], drop, what, fy + 0.2, c.y])

## Windowed: a player-style house; screenshot a front window from
## outside, then an interior window from inside.
func _winshot_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var hs := House.new()
	hs.kind = OS.get_environment("CTD_KIND") if OS.get_environment("CTD_KIND") != "" else "small"
	add_child(hs)
	hs.set_meta("placed_id", "house")
	hs.global_transform = Transform3D(_basis_from_up(up), home.center + up * home.radius)
	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	# shot 1: outside, facing the front wall windows
	var fwd: Vector3 = -hs.global_transform.basis.z
	cam.global_position = hs.global_position + fwd * 5.0 + up * 2.0
	cam.look_at(hs.global_position + up * 1.8, up)
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("CTD_SHOT"))
	print("WINSHOT exterior saved")
	# shot 2: inside, facing the interior front windows
	var c := hs.room_center()
	var sz := hs.room_size()
	if hs.kind == "basement":
		# stand over the stairwell corner, look down the hole
		cam.global_position = c + Vector3(0.5, 0.5, -1.5)
		cam.look_at(c + Vector3(4.0, -sz.y, 3.0), Vector3.UP)
	elif hs.kind == "moonbase":
		# from the hub floor, look UP at the dome roof
		cam.global_position = c + Vector3(0, -sz.y * 0.5 + 1.2, 3.0)
		cam.look_at(c + Vector3(0, sz.y * 0.5 + 2.0, 0), Vector3.FORWARD)
	else:
		cam.global_position = c + Vector3(0, 0, 2.0)
		cam.look_at(c + Vector3(0, 0.6, -sz.z * 0.5), Vector3.UP)
	Game.zone = "flat"
	p.global_position = hs.interior_spawn()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(
		OS.get_environment("CTD_SHOT").replace(".png", "_in.png"))
	print("WINSHOT interior saved")

## Headless: place a house, walk in, count the ports, poison the air.
func _house_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var hs := House.new()
	hs.kind = "two_story"
	add_child(hs)
	hs.set_meta("placed_id", "house")
	hs.global_transform = Transform3D(_basis_from_up(up),
		home.center + up * home.radius)
	await get_tree().create_timer(1.0).timeout
	print("HOUSETEST ports out/in: ", hs._out_ports.size(), "/", hs._in_ports.size(),
		"  interior built: ", hs._iroot != null and is_instance_valid(hs._iroot))
	hs.enter(p)
	await get_tree().create_timer(0.3).timeout
	print("HOUSETEST inside: ", p.global_position.distance_to(hs.room_center()) < 30.0,
		"  zone: ", Game.zone)
	# a reactor in the living room. what could go wrong.
	var rx := EMachines.NuclearReactor.new()
	add_child(rx)
	rx.global_position = hs.room_center() + Vector3(3, -1.5, 0)
	var hp0: float = Game.health
	await get_tree().create_timer(4.5).timeout
	print("HOUSETEST radioactive: ", hs._rad, "  cancer dmg: ", hp0 - Game.health > 0.0)
	hs.exit_to_door(p)
	await get_tree().create_timer(0.2).timeout
	print("HOUSETEST back outside: ", p.global_position.distance_to(hs.global_position) < 10.0,
		"  zone cleared: ", Game.zone == "")
	# a human claims a town house and furnishes it
	var th := House.new()
	th.kind = "small"
	th.human_home = true
	add_child(th)
	th.global_transform = Transform3D(_basis_from_up(up),
		home.center + up * home.radius + Vector3(12, 0, 0))
	var hu := EarthHuman.new()
	hu.setup(home)
	add_child(hu)
	hu.global_position = th.global_position + Vector3(3, 1, 0)
	await get_tree().create_timer(1.0).timeout
	hu.my_house = th
	th.owner_uid = hu.human_id
	th.furnish_for(hu._pers)
	hu._goal_house = th
	hu._act = "gohouse"
	hu._act_t = 40.0
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		if i % 12 == 0:
			print("HOUSETEST walk: act=", hu._act, " d=%.1f" % \
				hu.global_position.distance_to(th.door_spot()))
		if hu.flat_house != null:
			break
	print("HOUSETEST human moved in: ", hu.flat_house == th)
	var furn := 0
	for f in get_tree().get_nodes_in_group("bench"):
		if f is Furniture and f.global_position.distance_to(th.room_center()) < 20.0:
			furn += 1
	print("HOUSETEST furnished pieces: ", furn)

## Headless: exercise the reactor control-room interlocks.
func _reactor_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var rx := EMachines.NuclearReactor.new()
	add_child(rx)
	rx.global_position = Vector3(0, 200, 0)
	await get_tree().create_timer(0.3).timeout
	print("RXTEST rods in shutdown refused: ", not rx.order_rods(-0.05))
	rx.flow = 0
	print("RXTEST startup w/o flow refused: ", not rx.set_mode(1))
	rx.flow = 2
	print("RXTEST startup w/ flow ok: ", rx.set_mode(1))
	rx.order_rods(-0.5)
	rx.order_rods(-0.5)
	print("RXTEST startup rod floor 45%%: ", absf(rx.rods_target - 0.45) < 0.001)
	print("RXTEST RUN on cold core refused: ", not rx.set_mode(2))
	rx.power = 0.5
	rx.temp = 30.0
	print("RXTEST RUN on hot core ok: ", rx.set_mode(2))
	rx.power = 0.01
	rx.toggle_breaker()
	print("RXTEST weak-steam sync trips: ", not rx.breaker and rx.trip_t > 0.0)
	rx.power = 0.8
	rx.toggle_breaker()
	print("RXTEST good sync closes: ", rx.breaker)
	rx.do_scram()
	print("RXTEST scram: ", rx._scram and rx.rods_target == 1.0 and not rx.breaker)

## Headless: one grenade, one point-blank furnace, one furnace at 5m,
## one bystander. Count the casualties.
func _nade_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var ground: Vector3 = home.center + up * (home.radius + 0.5)
	var close := Furnace.new()
	add_child(close)
	close.set_meta("placed_id", "furnace")
	close.global_position = ground + Vector3(1.5, 0, 0)
	var far := Furnace.new()
	add_child(far)
	far.set_meta("placed_id", "furnace")
	far.global_position = ground + Vector3(5.5, 0, 0)
	var hum := EarthHuman.new()
	hum.setup(home)
	add_child(hum)
	hum.global_position = ground + Vector3(0, 0, 4)
	await get_tree().create_timer(0.4).timeout
	var php: float = Game.health
	var hhp: float = hum.hp
	var g := Grenade.new()
	add_child(g)
	g.global_position = ground + up * 0.5
	g._boom()
	await get_tree().create_timer(0.3).timeout
	print("NADETEST close machine gone: ", not is_instance_valid(close))
	print("NADETEST far machine dented: ",
		is_instance_valid(far) and int(far.get_meta("g_dmg", 0)) == 1)
	print("NADETEST human hurt: ", (not is_instance_valid(hum)) or hum.hp < hhp)
	print("NADETEST player hurt: ", Game.health < php or php <= 0.0)

## Headless: chip a human, open the terminal UI, take the wheel, walk
## them, punch a bystander, rewrite the soul. The full violation.
func _neuro_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var hum := EarthHuman.new()
	hum.setup(home)
	add_child(hum)
	hum.global_position = p.global_position + Vector3(5, 0, 0)
	var victim := EarthHuman.new()
	victim.setup(home)
	add_child(victim)
	victim.global_position = p.global_position + Vector3(6.5, 0, 0)
	await get_tree().create_timer(0.4).timeout
	hum.chipped = true
	var ui := NeuralinkUI.new()
	add_child(ui)
	await get_tree().create_timer(0.3).timeout
	ui.select_target(hum)
	await get_tree().create_timer(0.2).timeout
	print("NEUROTEST minded: ", hum.minded, "  focus: ", ui._focus)
	var start: Vector3 = hum.global_position
	var evw := InputEventKey.new()
	evw.keycode = KEY_W
	evw.physical_keycode = KEY_W
	evw.pressed = true
	Input.parse_input_event(evw)
	await get_tree().create_timer(1.5).timeout
	print("NEUROTEST walked: %.1f m" % start.distance_to(hum.global_position))
	var evr := InputEventKey.new()
	evr.keycode = KEY_W
	evr.physical_keycode = KEY_W
	evr.pressed = false
	Input.parse_input_event(evr)
	hum.global_position = victim.global_position + Vector3(1.0, 0, 0)
	await get_tree().create_timer(0.2).timeout
	var vhp: float = victim.hp
	hum.mind_punch()
	await get_tree().create_timer(0.2).timeout
	print("NEUROTEST punch landed: ", victim.hp < vhp)
	ui._on_axis(95.0, "goofy")
	print("NEUROTEST face repicked: ", str(hum.saved.get("face", "")))
	ui.close()
	await get_tree().create_timer(0.2).timeout
	print("NEUROTEST released: ", not hum.minded)

## Headless: a human and a chair. Verify walk-to-seat, the sit, the pose.
func _sit_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var hum := EarthHuman.new()
	hum.setup(home)
	add_child(hum)
	hum.global_position = p.global_position + Vector3(4, 0, 0)
	var crng := RandomNumberGenerator.new()
	crng.seed = 1
	var dir: Vector3 = ((p.global_position + Vector3(8, 0, 0)) - home.center).normalized()
	_seat_prop(home, dir, crng, false)
	await get_tree().create_timer(0.5).timeout
	var seat: Node3D = null
	var bd := 1e9
	for sn in get_tree().get_nodes_in_group("seat"):
		var d: float = sn.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			seat = sn
	seat.set_meta("taken", true)
	hum._seat = seat
	hum._act = "goseat"
	hum._act_t = 25.0
	for i in 80:
		await get_tree().create_timer(0.25).timeout
		if hum._act == "sit":
			break
	print("SITTEST act: ", hum._act, "  pose: ", hum._body.pose,
		"  dist: ", hum.global_position.distance_to(seat.global_position))
	# and the getting-up half: shove them and check the seat frees up
	hum.take_damage(1.0, Vector3(1, 0, 0))
	await get_tree().create_timer(0.5).timeout
	print("SITTEST stood up: ", hum._act != "sit",
		"  seat freed: ", not seat.get_meta("taken"))

## Headless: park a rocket in front of the player's face and press F.
func _board_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = p.camera()
	var rk := Rocket.new()
	add_child(rk)
	rk.set_meta("placed_id", "rocket")
	rk.global_position = cam.global_position - cam.global_transform.basis.z * 5.0
	await get_tree().create_timer(0.5).timeout
	print("BOARDTEST mode before: ", Game.mode, " board_lock: ", Game.board_lock,
		" playtime: ", Game.playtime)
	p._interact()
	await get_tree().create_timer(0.5).timeout
	print("BOARDTEST mode after: ", Game.mode, " (1 = IN_ROCKET)")

## Headless: drive the map picker with a synthetic right-click.
func _map_pick_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var m = get_tree().get_first_node_in_group("map_ui")
	print("MAPTEST map found: ", m != null)
	m.open_select(func(b) -> void: print("MAPTEST picked: ", b.name))
	m._last_scale = 0.01   # headless never draws; fake the draw transform
	await get_tree().create_timer(0.5).timeout
	var home = Universe.body_named("Home")
	var p = get_tree().get_first_node_in_group("player")
	var vpsz := get_viewport().get_visible_rect().size
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = vpsz * 0.5 + Vector2(home.center.x - p.global_position.x,
		home.center.z - p.global_position.z) * 0.01
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.5).timeout
	print("MAPTEST after parse_input_event, cb still set: ", m.select_cb.is_valid())
	if m.select_cb.is_valid():
		# delivery vs logic: feed the handler directly
		m._unhandled_input(ev)
		print("MAPTEST after direct call, cb still set: ", m.select_cb.is_valid())
		print("MAPTEST body_at says: ", m.body_at(ev.position))

func _unhandled_key_input(event: InputEvent) -> void:
	# F12: screenshot into user://screenshots, timestamped
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F12:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		var img := get_viewport().get_texture().get_image()
		var fn := "user://screenshots/shot_%s.png" % \
			Time.get_datetime_string_from_system().replace(":", "-")
		img.save_png(fn)
		Sfx.play("click", -20.0)
		print("screenshot: ", ProjectSettings.globalize_path(fn))

## Headless regression test: build a small base, save-cycle it, count.
func _self_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var g := EMachines.Generator.new()
	add_child(g)
	g.set_meta("placed_id", "generator")
	g.global_position = Vector3(0, 60, 0)
	var c := EMachines.Capacitor.new()
	add_child(c)
	c.set_meta("placed_id", "capacitor")
	c.global_position = Vector3(6, 60, 0)
	var ch := Chest.new()
	add_child(ch)
	ch.set_meta("placed_id", "chest")
	ch.global_position = Vector3(3, 60, 3)
	var wpt := Waypoint.new()
	add_child(wpt)
	wpt.set_meta("placed_id", "waypoint")
	wpt.global_position = Vector3(-3, 60, 0)
	var everything := ["furnace", "coinifier", "autominer", "atm", "spawnbeacon",
		"coaldrill", "bioreactor", "rtg", "prisreactor", "capacitor", "ultracap",
		"efurnace", "eseller", "elight", "switch", "ecomputer", "scomputer",
		"teleporter", "extender", "rocket"]
	var xoff := 10.0
	for pid in everything:
		var node := _spawn_world_obj(pid)
		if node == null:
			print("SELFTEST factory MISSING: ", pid)
			continue
		add_child(node)
		node.set_meta("placed_id", pid)
		node.global_position = Vector3(xoff, 60, 0)
		xoff += 4.0
	var dr := ItemDrop.new()
	dr.setup("irid", 5)
	add_child(dr)
	dr.global_position = Vector3(0, 60, -3)
	await get_tree().process_frame
	g.connect_wire(c, "power", 0)
	g.connect_wire(ch, "item", 2)
	g.add_coil()
	c.connect_wire(g.coil_node, "power", 0)
	var w := collect_world()
	print("SELFTEST collect=", w.size(), " json_len=", JSON.stringify(w).length())
	# full disk-style JSON roundtrip, like a real save file
	var blob := JSON.stringify({"world": w})
	var parsed = JSON.parse_string(blob)
	Save.set_world(parsed["world"])
	Save._progress["world"] = parsed["world"]
	restore_world()
	await get_tree().process_frame
	var w2 := collect_world()
	var census := 0
	for e3 in w:
		if e3 is Dictionary and str(e3.get("id", "")) == "human":
			census += 1
	# machines respawn BESIDE originals (doubling); the human census
	# REPLACES the population (same size). expectation splits the two.
	print("SELFTEST recollect=", w2.size(), " (expected ", (w.size() - census) * 2 + census, ")")

func _rift_test() -> void:
	await get_tree().create_timer(0.5).timeout
	Save.snaps.clear()
	Save.snaps.append(_make_snapshot(Vector3(123, 456, 789)))
	Save.snaps[0]["t"] = -999.0   # definitely "5 minutes ago"
	_player.global_position = _rifts[0]
	print("RIFTTEST placed at ", _rifts[0])
	await get_tree().create_timer(1.0).timeout
	print("RIFTTEST player now at ", _player.global_position, "  (want ~123,456,789)")

var _pop_t: float = 30.0

func _process(delta: float) -> void:
	_regen_crates(delta)
	_regen_ore(delta)
	_animate_avatars(delta)
	# demographics: when the census dips, someone new steps off the rail
	# into a city. only while a player is around to live in
	_pop_t -= delta
	if _pop_t <= 0.0:
		_pop_t = randf_range(20.0, 40.0)
		_repopulate()
	var pos := _active_pos()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 5.0
		var hyper := false
		var mk2 := false
		if Game.mode == Game.Mode.IN_ROCKET:
			for r in get_tree().get_nodes_in_group("rocket"):
				if r is Rocket and r.piloted:
					hyper = r.hyperdrive
					mk2 = r.mk2
					break
		var petn = get_tree().get_first_node_in_group("pet")
		if petn != null and is_instance_valid(petn):
			Save.set_pet(true, petn.genome, petn.staying)
		else:
			Save.set_pet(false)
		if _world_load_ok:
			Save.set_world(collect_world())
		Save.set_player_pos(pos, Game.mode == Game.Mode.IN_ROCKET, hyper, mk2)
		Save.save_progress()

	# --- time-rift snapshots: one per minute, keep the last 6 ---
	_snap_t -= delta
	if _snap_t <= 0.0 and not Game.dead:
		_snap_t = 60.0
		Save.snaps.append(_make_snapshot(pos))
		while Save.snaps.size() > 6:
			Save.snaps.pop_front()

	# --- the Connect 4 island has no gravity. it's deep space. obviously. ---
	if Game.mode == Game.Mode.ON_FOOT:
		var c4d := pos.distance_to(C4_POS)
		if not _c4_zone and Game.zone == "" and c4d < 120.0:
			Game.zone = "zero"
			_c4_zone = true
		elif _c4_zone and c4d > 140.0:
			Game.zone = ""
			_c4_zone = false

	# --- the UFO market: Tuesdays (and some Saturdays), new spot each time ---
	var day := Game.day_index()
	if day != _ufo_day:
		_ufo_day = day
		if _ufo and is_instance_valid(_ufo):
			_ufo.queue_free()
			_ufo = null
		if Game.is_ufo_day():
			_ufo = UFO.new()
			add_child(_ufo)
			var rng := RandomNumberGenerator.new()
			rng.seed = day * 977
			_ufo.global_position = Vector3(
				rng.randf_range(-6000, 6000), rng.randf_range(-2000, 3000),
				rng.randf_range(-6000, 6000)) * Universe.world_scale
			if _hud:
				_hud.flash("a saucer slid into the system. it's %s." % Game.weekday_name())

	# --- rifts: warped patches of space; fly through -> 5 min into the past.
	# SWEPT check: even a 10x-timewarp rocket crossing the bubble between
	# two frames still counts. No tunneling through time holes. ---
	_rift_cd = maxf(0.0, _rift_cd - delta)
	if _rift_cd <= 0.0 and not Game.dead:
		for r in _rifts:
			var seg := pos - _rift_prev
			var t2 := 0.0
			if seg.length_squared() > 0.0001:
				t2 = clampf((r - _rift_prev).dot(seg) / seg.length_squared(), 0.0, 1.0)
			var closest := _rift_prev + seg * t2
			if closest.distance_to(r) < 28.0:
				_enter_rift()
				break
	_rift_prev = pos

	# sphere-of-influence change notice (KSP-style) -- suppressed in
	# pocket dimensions: walking into your living room is not a
	# gravitational event
	if Game.zone != "":
		_last_soi = ""
	else:
		var soi := Universe.nearest(pos).name
		if soi != _last_soi:
			if _last_soi != "" and _hud:
				_hud.flash("Leaving %s SOI  →  entering %s SOI" % [_last_soi, soi])
			_last_soi = soi

	# --- universe edge: the god throws you back in (an unholy act) ---
	# pocket dimensions live OUTSIDE the map on purpose -- the god only
	# polices real space, not the sponge/temples
	if Game.zone == "" and pos.length() > Universe.BOUNDARY:
		var target := pos.normalized() * (Universe.BOUNDARY * 0.85)
		var node := _active_node()
		if node and node.has_method("god_throwback"):
			node.god_throwback(target)
		if not _threw_back:
			_threw_back = true
			Game.anger(15.0)
			if _hud:
				_hud.flash("THE UNIVERSE GOD (ThePearlKing) HURLS YOU BACK IN")
	else:
		_threw_back = false

	# --- TIN 618 time dilation. No death screen: you just... slow. Forever. ---
	var bh := Universe.body_named("TIN 618")
	if bh:
		var d := pos.distance_to(bh.center)
		var horizon := bh.radius
		var influence := horizon * 10.0
		if d < influence:
			var t := clampf((d - horizon) / (influence - horizon), 0.0, 1.0)
			Game.dilation = maxf(0.005, pow(t, 1.8))
			if d < horizon * 1.3:
				Game.trapped = true   # silently. it's like that when you come back.
		else:
			Game.dilation = 1.0
	Engine.time_scale = Game.dilation * Game.timewarp

	# --- suns burn. You do not walk on a star. You do not park in one. ---
	if not Game.dead:
		for b in Universe.bodies:
			if b.kind != "sun":
				continue
			var sd: float = pos.distance_to(b.center)
			if sd < b.radius * 1.05:
				# TOUCHED the star: absorbed. instantly.
				if _hud:
					_hud.sun_fire()
					_hud.flash("ABSORBED BY %s" % str(b.name).to_upper())
				Game.hurt(100000.0, true)   # star deaths vaporize your items
			elif sd < b.radius * 1.6:
				Game.hurt(50.0 * delta, true)
				if _burn_t <= 0.0:
					_burn_t = 2.0
					if _hud:
						_hud.flash("BURNING")
	# --- gas giants: clouds all the way down. no message needed --
	# the sky ate you, you were there. Rockets don't survive it either.
	for b in Universe.bodies:
		if b.kind != "gas":
			continue
		var gd: float = pos.distance_to(b.center)
		if not Game.dead:
			if gd < b.radius * 0.75:
				Game.hurt(100000.0, true)
			elif gd < b.radius:
				Game.hurt(22.0 * delta)
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and is_instance_valid(r) \
					and r.global_position.distance_to(b.center) < b.radius * 0.75:
				Destructible.spawn_debris(self, r.global_position,
					Vector3(1.6, 3.0, 1.6), Color("#d8d8e0"), Vector3.UP)
				Net.broadcast_remove(r.global_position)
				r.queue_free()
	# --- Sanus spits lava at visitors. The loot is priced accordingly. ---
	if not Game.dead:
		var sb = Universe.body_named("Sanus")
		if sb and pos.distance_to(sb.center) < sb.radius + 90.0:
			_arc_t -= delta
			if _arc_t <= 0.0:
				_arc_t = randf_range(0.4, 1.4)   # constant, erratic, everywhere
				_spawn_lava_arc(sb, pos)
	_burn_t = maxf(0.0, _burn_t - delta)

	# which fold-maze room are you standing in? (number on screen)
	if _hud and _player and Game.mode == Game.Mode.ON_FOOT:
		var mb := Zones.TEMPLE_POS + Vector3(0, 200, 0)
		var room := 0
		if Game.zone == "flat":
			for rk in 4:
				if _player.global_position.distance_to(mb + Vector3(float(rk) * 400.0, 0, 0)) < 80.0:
					room = rk + 1
					break
		_hud.set_zone_text(str(room) if room > 0 else "")

	if _trials_started and not Game.trials_done:
		_trial_check_t -= delta
		if _trial_check_t <= 0.0:
			_trial_check_t = 1.0
			var alive := 0
			for en in get_tree().get_nodes_in_group("enemy"):
				if en is Enemy and en.pyramid and is_instance_valid(en):
					alive += 1
			if alive == 0:
				Game.trials_done = true
				Sfx.play("learn")
				if _hud:
					_hud.flash("MAZE DOOR UNSEALED")

	if Game.dead and Input.is_key_pressed(KEY_R):
		Engine.time_scale = 1.0
		if Game.permadead:
			get_tree().change_scene_to_file("res://Title.tscn")
		else:
			# death sends you HOME (or to your chosen beacon) -- never back
			# to the spot that just killed you. The reload reads the SAVE's
			# pos, so write the save NOW (and before reset(), which wipes
			# cheats/score that the reload then restores from this save).
			Game.zone = ""
			if _world_load_ok:
				Save.set_world(collect_world())   # spilled items survive reload
			Save.set_player_pos(Game.spawn_pos + Game.spawn_up * 1.5, false, false)
			Save.save_progress()
			Game.reset()
			get_tree().reload_current_scene()

func _notification(what: int) -> void:
	# window closed mid-run: save the exact position on the way out
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# static caches held render resources past teardown -> the wall
		# of "leaked at exit" warnings on quit. Drop them first.
		Surfaces.shutdown()
		IconLib.shutdown(get_tree())
		Human._prism_mat = null
		ShaderLib._fx_shader = null
		RadioLib._music_cache.clear()
		RadioLib._static_wav = null
		RadioLib._eerie_wav = null
		RadioLib._rick_wav = null
		var petc = get_tree().get_first_node_in_group("pet")
		if petc != null and is_instance_valid(petc):
			Save.set_pet(true, petc.genome, petc.staying)
		var hyper := false
		var mk2 := false
		if Game.mode == Game.Mode.IN_ROCKET:
			for r in get_tree().get_nodes_in_group("rocket"):
				if r is Rocket and r.piloted:
					hyper = r.hyperdrive
					mk2 = r.mk2
		if _world_load_ok:
			Save.set_world(collect_world())
		Save.set_player_pos(_active_pos(), Game.mode == Game.Mode.IN_ROCKET, hyper, mk2)
		Save.save_progress()

func _active_node() -> Node:
	var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
	return get_tree().get_first_node_in_group(g)

func _active_pos() -> Vector3:
	var n := _active_node()
	return n.global_position if n else Vector3.ZERO

# ------------------------------------------------------------- universe

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# subtle starfield sky (not distracting)
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_sh := Shader.new()
	sky_sh.code = "shader_type sky;\nvoid sky(){\n vec3 d = EYEDIR;\n vec3 cell = floor(d*160.0);\n float n = fract(sin(dot(cell, vec3(12.9898,78.233,37.719)))*43758.5453);\n float star = step(0.9975, n) * 0.7;\n COLOR = vec3(0.015,0.015,0.03) + vec3(star);\n}"
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_sh
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#404058")
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("#ffe6f2")
	add_child(sun)

func _build_body(b) -> void:
	if b.kind == "torus":
		_build_torus(b)
		return
	var p := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = b.radius
	sm.height = b.radius * 2.0
	sm.radial_segments = 48
	sm.rings = 28
	mi.mesh = sm
	mi.material_override = _planet_material(b.kind, b.color)
	p.add_child(mi)
	var col := CollisionShape3D.new()
	if MINE_DIRS.has(b.name):
		# Mined planet: BOTH the collider and the VISIBLE mesh are a shell
		# with the mouth cut out -- you can see straight down the shaft.
		var mdir: Vector3 = MINE_DIRS[b.name]
		# cut a hole of CONSTANT ~5m radius regardless of planet size
		# (a fixed angle made huge walk-through gaps on big planets)
		var thresh := cos(4.8 / b.radius)   # matches the shaft's outer walls
		var faces := sm.get_faces()
		var kept := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var centroid := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			if centroid.normalized().dot(mdir) > thresh:
				continue   # cut the mouth
			kept.append(faces[i])
			kept.append(faces[i + 1])
			kept.append(faces[i + 2])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(kept)
		col.shape = shape
		mi.mesh = _mesh_from_faces(kept)   # visual hole matches
	else:
		var cs := SphereShape3D.new()
		cs.radius = b.radius
		col.shape = cs
	if b.kind != "gas":
		p.add_child(col)   # gas giants have NO surface. you fall in.
	p.set_meta("body_name", b.name)   # the apple cinematic needs to find these
	add_child(p)
	p.global_position = b.center

	if b.kind in ["home", "life", "sand", "pi"]:
		_add_aurora(b)   # polar lights on the pretty planets
	if b.kind == "wireframe":
		_wireframe_overlay(p, sm)   # real polygon edges over a dark sphere
	if b.kind == "blackhole":
		_accretion(b)
	if b.kind == "sun":
		var ol := OmniLight3D.new()
		ol.light_energy = 4.0
		ol.omni_range = 4000.0
		ol.light_color = b.color.lerp(Color.WHITE, 0.25)   # blue stars glow blue
		p.add_child(ol)
		# corona: a licking rim of flame around the disc, always moving
		var cor := MeshInstance3D.new()
		var corm := SphereMesh.new()
		corm.radius = b.radius * 1.38
		corm.height = b.radius * 2.76
		corm.radial_segments = 48
		corm.rings = 24
		cor.mesh = corm
		var csh2 := Shader.new()
		csh2.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_back;\nvarying vec3 vn;\nuniform vec3 base : source_color;\n" \
			+ _NOISE_GLSL + """
void vertex(){
	vn = NORMAL;
	VERTEX += NORMAL * (fbm(NORMAL * 3.0 + vec3(TIME * 0.3)) - 0.35) * length(VERTEX) * 0.22;
}
void fragment(){
	vec3 n = normalize(vn);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.3);
	float lick = fbm(n * 6.0 + vec3(0.0, TIME * 0.5, TIME * 0.3));
	ALBEDO = vec3(0.0);
	EMISSION = base * rim * (0.8 + lick * 2.6) * 2.6;
	ALPHA = clamp(rim * (0.45 + lick * 1.0), 0.0, 1.0);
}
"""
		var cmat2 := ShaderMaterial.new()
		cmat2.shader = csh2
		cmat2.set_shader_parameter("base", b.color)
		cor.material_override = cmat2
		p.add_child(cor)
		# rim fire: a billboard ring of flame that ALWAYS faces you --
		# transparent over the disc, so the fire lives only AROUND the
		# star, licking outward from its edge
		var fire := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(b.radius * 6.0, b.radius * 6.0)
		fire.mesh = fq
		var fsh := Shader.new()
		fsh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled;\nuniform vec3 base : source_color;\n" \
			+ _NOISE_GLSL + """
void vertex(){
	// billboard: the quad turns to face every camera, always
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment(){
	vec2 pp = UV * 2.0 - 1.0;
	float r = length(pp);
	// seamless angular noise: sample on a circle so there's no wrap line
	vec3 np = vec3(pp.x / max(r, 0.001) * 2.0, pp.y / max(r, 0.001) * 2.0, r * 3.0 - TIME * 0.9);
	float lick = fbm(np) + fbm(np * 2.3 + 7.0) * 0.5;
	// flames: root at the disc edge (r=0.334), noisy tips reaching out
	float tip = 0.36 + lick * 0.4;
	float body = smoothstep(tip, 0.34, r);
	float hole = smoothstep(0.328, 0.345, r);   // NOTHING over the disc
	float a = body * hole;
	vec3 hot = mix(vec3(1.0, 0.95, 0.7), base, 0.35);
	vec3 cool = mix(vec3(1.0, 0.35, 0.05), base, 0.3);
	ALBEDO = vec3(0.0);
	EMISSION = mix(hot, cool, smoothstep(0.34, 0.75, r)) * a * 2.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
		var fmat2 := ShaderMaterial.new()
		fmat2.shader = fsh
		fmat2.set_shader_parameter("base", b.color)
		fire.material_override = fmat2
		p.add_child(fire)
		# the GLARE: a huge soft halo + four diffraction spikes, always
		# facing you. THIS is what makes it read as a star from anywhere
		# in the system instead of a glowing ball
		var halo := MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(b.radius * 16.0, b.radius * 16.0)
		halo.mesh = hq
		var hsh := Shader.new()
		hsh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 base : source_color;
void vertex(){
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment(){
	vec2 pp = UV * 2.0 - 1.0;
	float r = length(pp);
	// soft blinding core glow, wide falloff
	float glow = pow(clamp(1.0 - r, 0.0, 1.0), 3.5) * 2.2
		+ pow(clamp(1.0 - r, 0.0, 1.0), 9.0) * 3.0;
	// four glare spikes, slowly breathing
	float sp = 0.0;
	float breathe = 0.85 + 0.15 * sin(TIME * 0.7);
	sp += pow(max(0.0, 1.0 - abs(pp.y) * 26.0), 2.0) * max(0.0, 1.0 - abs(pp.x)) * breathe;
	sp += pow(max(0.0, 1.0 - abs(pp.x) * 26.0), 2.0) * max(0.0, 1.0 - abs(pp.y)) * breathe;
	vec3 col = mix(vec3(1.0), base, clamp(r * 1.6, 0.0, 0.85));
	float a = clamp(glow + sp * 0.9, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = col * a * 2.2;
	ALPHA = a;
}
"""
		var hmat := ShaderMaterial.new()
		hmat.shader = hsh
		hmat.set_shader_parameter("base", b.color)
		halo.material_override = hmat
		p.add_child(halo)
	# Saturn + Uranus wear their rings (Uranus' famously sideways)
	if b.name in ["Saturn", "Uranus"]:
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = b.radius * 1.35
		rm.outer_radius = b.radius * 2.1
		ring.mesh = rm
		ring.scale = Vector3(1, 0.04, 1)   # squashed torus = flat ring disc
		var rmat := StandardMaterial3D.new()
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(0.9, 0.85, 0.7, 0.35) if b.name == "Saturn" \
			else Color(0.7, 0.9, 0.9, 0.25)
		rmat.emission_enabled = true
		rmat.emission = rmat.albedo_color
		rmat.emission_energy_multiplier = 0.4
		ring.material_override = rmat
		if b.name == "Uranus":
			ring.rotation_degrees = Vector3(0, 0, 82)   # rolls on its side
		else:
			ring.rotation_degrees = Vector3(12, 0, 0)
		p.add_child(ring)

	_populate(b)

## Polar auroras: thin undulating light curtains LEVITATING high above
## each pole (like the real thing) -- green skirts, violet-red crowns,
## slow waves. Scales with the planet (and the world-size multiplier).
func _add_aurora(b) -> void:
	for pole in [1.0, -1.0]:
		for ring in [[0.34, 0.0], [0.24, 2.7]]:   # two curtains for depth
			var curtain := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = b.radius * float(ring[0])
			cm.bottom_radius = b.radius * float(ring[0]) * 1.06
			cm.height = b.radius * 0.12
			cm.cap_top = false
			cm.cap_bottom = false
			cm.radial_segments = 96
			cm.rings = 6
			curtain.mesh = cm
			var sh := Shader.new()
			sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float seed;
float h(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void vertex(){
	// the whole curtain slowly undulates like a ribbon in solar wind
	float a = UV.x * 6.28318;
	VERTEX.x += sin(a*3.0 + TIME*0.22 + seed) * 0.035 * length(VERTEX.xz);
	VERTEX.z += cos(a*2.0 - TIME*0.17 + seed) * 0.035 * length(VERTEX.xz);
	VERTEX.y += sin(a*4.0 + TIME*0.13 + seed*2.0) * 0.12 * abs(VERTEX.y);
}
void fragment(){
	float x = UV.x * 140.0;
	// vertical ray columns that drift and flicker slowly
	float col_id = floor(x);
	float r1 = h(vec2(col_id, seed));
	float ray = 0.25 + 0.75 * pow(0.5 + 0.5*sin(x*0.9 + TIME*(0.15+r1*0.2) + r1*6.28), 3.0);
	float v = UV.y;
	// bright thin base, long faint tail upward (curtain look)
	float band = smoothstep(0.0, 0.06, v) * pow(1.0 - v, 1.8);
	// real aurora colours: green skirt -> violet/red crown
	vec3 lowc = vec3(0.10, 0.95, 0.35);
	vec3 hic  = vec3(0.55, 0.15, 0.60);
	vec3 col = mix(lowc, hic, pow(v, 1.4));
	ALBEDO = col;
	ALPHA = band * ray * 0.22;
	EMISSION = col * band * ray * 2.2;
}"""
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("seed", randf() * 100.0 + float(ring[1]))
			curtain.material_override = mat
			add_child(curtain)
			# levitates ABOVE the surface, in the sky over the pole
			curtain.global_position = b.center + Vector3.UP * pole * (b.radius * 1.14)
			if pole < 0.0:
				curtain.rotation_degrees = Vector3(180, 0, 0)

## Rebuild a lit, UV-mapped mesh from raw triangle soup (used for the
## see-through mined-planet shells). Spherical UVs so surface shaders work.
func _mesh_from_faces(faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in faces.size():
		var v := faces[i]
		var n := v.normalized()
		st.set_normal(n)
		st.set_uv(Vector2(atan2(n.z, n.x) / TAU + 0.5, acos(clampf(n.y, -1.0, 1.0)) / PI))
		st.add_vertex(v)
	return st.commit()

func _build_torus(b) -> void:
	var p := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = b.major - b.radius
	tm.outer_radius = b.major + b.radius
	tm.rings = 64
	tm.ring_segments = 32
	mi.mesh = tm
	mi.material_override = _surface_material("rock", b.color)
	p.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tm.get_faces())
	col.shape = shape
	p.add_child(col)
	add_child(p)
	p.global_position = b.center
	# crates all around the tube -- outside, inside the hole, everywhere
	for i in 40:
		var theta := randf() * TAU
		var phi := randf() * TAU
		var ring_dir := Vector3(cos(theta), 0, sin(theta))
		var tube_dir := (ring_dir * cos(phi) + Vector3.UP * sin(phi)).normalized()
		var s := randf_range(1.2, 2.4)
		var d := Destructible.new()
		d.setup(Vector3(s, s, s), _palette[randi() % _palette.size()], 1, 14)
		add_child(d)
		var pos: Vector3 = b.center + ring_dir * b.major + tube_dir * (b.radius + s * 0.5)
		d.global_transform = Transform3D(_basis_from_up(tube_dir), pos)

func _accretion(b) -> void:
	# A cool multi-band accretion disk: several tilted, colour-graded rings.
	var specs := [
		[1.25, 1.7, Color("#fff2c0"), 8.0],
		[1.7, 2.3, Color("#ff9a1a"), 6.0],
		[2.3, 3.1, Color("#ff4d1a"), 4.0],
		[3.1, 4.2, Color("#7a1aff"), 2.5],
	]
	for s in specs:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = b.radius * float(s[0])
		tm.outer_radius = b.radius * float(s[1])
		tm.rings = 64
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = s[2]
		m.emission_energy_multiplier = float(s[3])
		m.albedo_color = s[2]
		ring.material_override = m
		ring.rotation_degrees = Vector3(78, 0, 6)
		add_child(ring)
		ring.global_position = b.center
	# faint photon halo
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = b.radius * 1.08
	hm.height = b.radius * 2.16
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(1.0, 0.7, 0.3, 0.15)
	hmat.emission_enabled = true
	hmat.emission = Color("#ffb060")
	hmat.emission_energy_multiplier = 1.5
	halo.material_override = hmat
	add_child(halo)
	halo.global_position = b.center

## Shared GLSL noise header for planet-surface shaders.
const _NOISE_GLSL := """
float h31(vec3 p){ return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }
float vnoise(vec3 p){
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = h31(i), b = h31(i + vec3(1,0,0)), c = h31(i + vec3(0,1,0)), d = h31(i + vec3(1,1,0));
	float e = h31(i + vec3(0,0,1)), f2 = h31(i + vec3(1,0,1)), g = h31(i + vec3(0,1,1)), k = h31(i + vec3(1,1,1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
		mix(mix(e, f2, f.x), mix(g, k, f.x), f.y), f.z);
}
float fbm(vec3 p){
	float v = 0.0; float amp = 0.5;
	for (int i = 0; i < 4; i++){ v += amp * vnoise(p); p *= 2.13; amp *= 0.5; }
	return v;
}
"""

## Earth from orbit: oceans, continents, shallows, polar ice.
func _earth_material() -> Material:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvarying vec3 vn;\n" + _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float land = fbm(n * 3.1);
	// snowline wobbles with the terrain, not a clean latitude ring
	float caps = smoothstep(0.7, 0.82, abs(n.y) + fbm(n * 6.0 + 3.0) * 0.09);
	vec3 ocean = vec3(0.06, 0.22, 0.5);
	vec3 shallow = vec3(0.1, 0.42, 0.6);
	vec3 grass = vec3(0.18, 0.46, 0.18);
	vec3 rock = vec3(0.42, 0.38, 0.28);
	vec3 col;
	if (land > 0.52) { col = mix(grass, rock, smoothstep(0.52, 0.72, land)); }
	else { col = mix(ocean, shallow, smoothstep(0.38, 0.52, land)); }
	// SNOW with texture: bright powder over blue-shadowed drifts,
	// wind-carved bands, dark rock poking through near the snowline
	vec3 snow = mix(vec3(0.78, 0.83, 0.92), vec3(0.97, 0.98, 1.0), fbm(n * 14.0));
	snow *= 0.93 + 0.07 * sin(fbm(n * 9.0 + 5.0) * 22.0);
	float poke = smoothstep(0.55, 0.72, fbm(n * 11.0 + 7.0))
		* (1.0 - smoothstep(0.85, 0.96, abs(n.y)));
	vec3 capped;
	if (land > 0.52) {
		capped = mix(snow, rock * 0.65, poke * 0.55);
	} else {
		// polar SEA stays a sea: open water with drifting floes,
		// not a solid white lid
		float floe = smoothstep(0.55, 0.72, fbm(n * 13.0 + 2.0));
		capped = mix(col, mix(vec3(0.8, 0.88, 0.96), snow, 0.5), floe);
	}
	col = mix(col, capped, caps);
	ALBEDO = col;
	float baseR = land > 0.52 ? 0.9 : 0.25;
	ROUGHNESS = mix(baseR, land > 0.52 ? 0.55 : 0.15, caps);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## Rocky worlds: base colour with mottled noise + optional polar caps.
func _rocky_material(color: Color, cap: float = 0.0) -> Material:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvarying vec3 vn;\nuniform vec3 base : source_color;\nuniform float capamt;\n" \
		+ _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float m1 = fbm(n * 7.0);
	float m2 = fbm(n * 21.0);
	vec3 col = base * (0.72 + 0.42 * m1 + 0.16 * m2);
	if (capamt > 0.0) {
		col = mix(col, vec3(0.95), smoothstep(0.86 - capamt * 0.1, 0.92, abs(n.y)));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base", color)
	m.set_shader_parameter("capamt", cap)
	return m

func _planet_material(kind: String, color: Color) -> Material:
	match kind:
		"pixel", "wth", "wob", "contrast":
			return ShaderLib.make(kind, color)
		"earth":
			return _earth_material()
		"luna", "mercury":
			return _rocky_material(color)
		"ice":
			# glacial: saturated blue with a frosty sheen
			var im2 := _rocky_material(Color("#5ab4f2"))
			if im2 is StandardMaterial3D:
				im2.roughness = 0.35
				im2.metallic = 0.15
			return im2
		"mars":
			return _rocky_material(color, 1.0)
		"venus":
			# Venus from orbit is nothing but cloud: slow cream-and-sulfur
			# swirls, fully opaque, faintly glowing with trapped heat
			var vsh := Shader.new()
			vsh.code = "shader_type spatial;\nvarying vec3 vn;\n" + _NOISE_GLSL + """
void fragment(){
	vec3 n = normalize(vn);
	float sw = fbm(n * 4.0 + vec3(fbm(n * 2.0 + TIME * 0.008)) * 1.4);
	float band = sin(n.y * 9.0 + sw * 4.0) * 0.5 + 0.5;
	vec3 cream = vec3(0.93, 0.85, 0.62);
	vec3 sulfur = vec3(0.78, 0.62, 0.3);
	ALBEDO = mix(sulfur, cream, band * 0.7 + sw * 0.3);
	EMISSION = vec3(0.25, 0.15, 0.02) * (0.3 + sw * 0.4);
	ROUGHNESS = 0.6;
}
void vertex(){ vn = NORMAL; }
"""
			var vm := ShaderMaterial.new()
			vm.shader = vsh
			return vm
		"gas":
			# swirling latitude bands + one big slow storm eye. all clouds,
			# no ground -- the look warns you before the physics does
			var sh := Shader.new()
			sh.code = """shader_type spatial;
render_mode shadows_disabled;
uniform vec3 base : source_color;
float band(vec3 n, float t) {
	float lat = n.y;
	float w = sin(lat * 14.0 + sin(lat * 5.0 + t * 0.05) * 1.5
		+ sin(n.x * 3.0 + t * 0.1) * 0.4);
	return w * 0.5 + 0.5;
}
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float b1 = band(n, TIME);
	vec3 dark = base * 0.55;
	vec3 light = mix(base, vec3(1.0), 0.35);
	vec3 col = mix(dark, light, b1);
	// the storm: an oval eye drifting slowly around the equator
	vec2 eye = vec2(cos(TIME * 0.02), sin(TIME * 0.02));
	float d = length(vec2(dot(n.xz, eye), (n.y + 0.25) * 2.2));
	col = mix(base * vec3(1.25, 0.75, 0.65), col, smoothstep(0.12, 0.3, d));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
"""
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("base", color)
			return m
		"wireframe":
			# dark base; real polygon edges added as an overlay in _build_body
			return _unshaded(Color("#020308"), 1.0)
		"blind":
			return _unshaded(Color.WHITE, 4.0)
		"sun":
			# a star SURFACE: churning fire cells, hot rising plumes
			var ssh := Shader.new()
			ssh.code = "shader_type spatial;\nrender_mode unshaded;\nvarying vec3 vn;\nuniform vec3 base : source_color;\n" \
				+ _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float f1 = fbm(n * 4.0 + vec3(TIME * 0.10, TIME * 0.07, 0.0));
	float f2 = fbm(n * 9.0 - vec3(0.0, TIME * 0.16, TIME * 0.09));
	float cells = f1 * 0.6 + f2 * 0.4;
	// limb darkening, like a real photosphere: the centre of the disc
	// BLOWS OUT white-hot, the edge cools toward the star's colour
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	vec3 hot = mix(base, vec3(1.0), 0.85);
	vec3 cool = base * 0.7;
	vec3 surf = mix(cool, hot, smoothstep(0.3, 0.75, cells));
	surf = mix(surf, vec3(1.0), pow(facing, 2.0) * 0.7);
	ALBEDO = surf;
	EMISSION = surf * (3.0 + pow(facing, 2.0) * 5.0 + cells * 1.5);
}
"""
			var smm := ShaderMaterial.new()
			smm.shader = ssh
			smm.set_shader_parameter("base", color)
			return smm
		"lava":
			# Sanus: charred crust laced with glowing lava veins
			var lsh := Shader.new()
			lsh.code = "shader_type spatial;\nvarying vec3 vn;\n" + _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float rock = fbm(n * 6.0);
	float vein = abs(fbm(n * 9.0 + 3.7) - 0.5);
	float glow = 1.0 - smoothstep(0.02, 0.09, vein);
	vec3 crust = mix(vec3(0.12, 0.04, 0.03), vec3(0.3, 0.1, 0.06), rock);
	ALBEDO = mix(crust, vec3(1.0, 0.35, 0.05), glow * 0.8);
	EMISSION = vec3(1.0, 0.3, 0.02) * glow * (1.6 + sin(TIME * 2.0 + rock * 12.0) * 0.5);
	ROUGHNESS = 0.9;
}
"""
			var lmm := ShaderMaterial.new()
			lmm.shader = lsh
			return lmm
		"volcanic":
			# Extroma: Io's ugly cousin -- sulfur blotches, scorch rings,
			# orange cracks bleeding heat between them
			var xsh := Shader.new()
			xsh.code = "shader_type spatial;\nvarying vec3 vn;\n" + _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float blotch = fbm(n * 5.0);
	float spots = fbm(n * 12.0 + 7.0);
	float crack = abs(fbm(n * 8.0 + 19.0) - 0.5);
	float glow = 1.0 - smoothstep(0.015, 0.06, crack);
	vec3 sulfur = vec3(0.85, 0.72, 0.25);
	vec3 olive = vec3(0.55, 0.5, 0.2);
	vec3 scorch = vec3(0.25, 0.16, 0.1);
	vec3 col = mix(olive, sulfur, blotch);
	col = mix(col, scorch, smoothstep(0.6, 0.75, spots));
	ALBEDO = mix(col, vec3(1.0, 0.4, 0.05), glow * 0.6);
	EMISSION = vec3(1.0, 0.3, 0.02) * glow * 0.9;
	ROUGHNESS = 0.95;
}
"""
			var xmm := ShaderMaterial.new()
			xmm.shader = xsh
			return xmm
		"varnisol":
			# grassland + darker forest patches + dirt scars + snow poles
			var gsh := Shader.new()
			gsh.code = "shader_type spatial;\nvarying vec3 vn;\n" + _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float g = fbm(n * 4.0);
	float f = fbm(n * 8.0 + 11.0);
	vec3 grass = vec3(0.24, 0.52, 0.2);
	vec3 forest = vec3(0.1, 0.3, 0.12);
	vec3 dirt = vec3(0.42, 0.34, 0.22);
	vec3 col = mix(grass, forest, smoothstep(0.5, 0.62, f));
	col = mix(col, dirt, smoothstep(0.62, 0.75, g));
	col = mix(col, vec3(0.93, 0.95, 1.0), smoothstep(0.8, 0.88, abs(n.y)));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
			var gmm := ShaderMaterial.new()
			gmm.shader = gsh
			return gmm
		"blackhole":
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.albedo_color = Color.BLACK
			return bm
		_:
			return _surface_material(kind, color)

## Lit procedural surface texture for ordinary planets.
func _surface_material(kind: String, color: Color) -> ShaderMaterial:
	var style := "rock"
	match kind:
		"home": style = "crystal"
		"sand": style = "sand"
		"life": style = "organic"
	var sh := Shader.new()
	sh.code = _surface_shader(style)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("base", Vector3(color.r, color.g, color.b))
	return mat

func _surface_shader(style: String) -> String:
	var head := "shader_type spatial;\nuniform vec3 base;\nfloat h(vec2 p){return fract(sin(dot(p,vec2(41.3,289.1)))*43758.5);}\n"
	match style:
		"crystal":
			return head + "void fragment(){\n vec2 uv=UV*24.0; vec2 c=floor(uv); vec2 f=fract(uv);\n float tri=step(f.x+f.y,1.0);\n float sh=mix(0.7,1.1,h(c+tri*0.5));\n float edge=smoothstep(0.0,0.05,abs(f.x+f.y-1.0));\n ALBEDO=base*sh*mix(0.55,1.0,edge);\n METALLIC=0.35; ROUGHNESS=0.3;\n}"
		"sand":
			return head + "void fragment(){\n vec2 uv=UV*vec2(70.0,70.0);\n float grain=h(floor(uv));\n float dune=sin(UV.y*44.0+sin(UV.x*11.0)*3.0)*0.5+0.5;\n ALBEDO=base*(0.82+0.18*grain)*(0.85+0.15*dune);\n ROUGHNESS=0.95;\n}"
		"organic":
			return head + "void fragment(){\n vec2 uv=UV*18.0;\n float n=h(floor(uv))*0.5+h(floor(uv*2.3))*0.5;\n ALBEDO=mix(base*0.55,base*1.25,n);\n ROUGHNESS=0.8;\n}"
	return head + "void fragment(){\n vec2 uv=UV*30.0;\n float n=h(floor(uv))*0.6+h(floor(uv*0.5))*0.4;\n ALBEDO=base*(0.65+0.5*n);\n METALLIC=0.2; ROUGHNESS=0.7;\n}"

func _wireframe_overlay(parent: Node3D, sphere: SphereMesh) -> void:
	var faces := sphere.get_faces()
	var pts := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		pts.append(a); pts.append(b)
		pts.append(b); pts.append(c)
		pts.append(c); pts.append(a)
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#12ff9a")
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color("#12ff9a")
	mi.material_override = mat
	parent.add_child(mi)

func _unshaded(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _shader_code(kind: String) -> String:
	match kind:
		"pixel":
			return "shader_type spatial;\nvoid fragment(){\n vec3 q=floor(VERTEX*0.7);\n float n=fract(sin(dot(q,vec3(12.9898,78.233,37.719)))*43758.5453);\n vec3 c=vec3(step(0.5,n),step(0.33,fract(n*3.0)),step(0.66,fract(n*7.0)));\n ALBEDO=c; EMISSION=c*0.4;\n}"
		"wth":
			return "shader_type spatial;\nvoid fragment(){\n float t=TIME;\n float band=floor(VERTEX.y*4.0+t*6.0);\n float g=fract(sin(band)*43758.5453);\n vec3 c=vec3(fract(VERTEX.x*0.3+t),g,fract(VERTEX.z*0.3-t));\n if(g>0.7){c=vec3(1.0)-c;}\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wireframe":
			return "shader_type spatial;\nvoid fragment(){\n vec2 gr=abs(fract(UV*40.0)-0.5);\n float line=1.0-smoothstep(0.0,0.05,min(gr.x,gr.y));\n ALBEDO=vec3(0.02); EMISSION=vec3(0.1,0.9,0.5)*line;\n}"
		"contrast":
			return "shader_type spatial;\nvoid fragment(){\n float v=step(0.5,fract(VERTEX.y*0.15+VERTEX.x*0.1));\n ALBEDO=vec3(v); EMISSION=vec3(v);\n}"
	return "shader_type spatial;\nvoid fragment(){ ALBEDO=vec3(0.5); }"

# -------------------------------------------------------------- content

func _populate(b) -> void:
	# Coin value per crate rises far from Home, so late-game gear forces
	# you out to the dangerous planets. (value, target crate count)
	match b.kind:
		"tutorial":
			# crates = startup capital, exactly like a real fresh planet
			_register_crates(b, 35, 10)
			# a REAL mine, same as every mined planet: shaft, chamber,
			# respawning veins, exit gate. NOTHING is pre-built -- the
			# tutorial teaches earning and buying every machine yourself.
			_build_mine(b, MINE_DIRS["Tutoria"], "raw_ingot", 2, Color("#a24bff"), 20)
		"tutorial_moon":
			_register_crates(b, 20, 4)
		"tutorial_rocket":
			_register_crates(b, 25, 5)
		"home":
			_register_crates(b, 60, 2)     # cheap: enough for a rocket + basics
			_spawn_mine_clues(b)
		"circuit":
			_register_crates(b, 40, 9)
			for i in 4:
				_place_on_surface(b, Circuit.new(), _surface_dir(), func(n): n.build())
			_spawn_enemies(b, 5, 1)
			_spawn_res_nodes(b, 8, "raw_irid", 2)
			_build_mine(b, MINE_DIRS["Circuitia"], "raw_ingot", 8, Color("#a24bff"))
		"logic":
			_register_crates(b, 30, 16)
			for i in 2:
				_place_on_surface(b, LogicDiagram.new(), _surface_dir(), func(n): n.build())
			_spawn_enemies(b, 6, 2)
			_spawn_res_nodes(b, 10, "raw_irid", 2)
			_build_mine(b, MINE_DIRS["Logica"], "raw_irid", 4, Color("#2a8f6a"))
		"pi":
			var ps := PiStructure.new()
			add_child(ps)
			ps.global_position = b.center
			ps.build(b.radius)
			_register_crates(b, 24, 26)
			_spawn_enemies(b, 6, 3)
			var shrine := Gate.new().configure({
				"action": "pishrine", "label": "PI SHRINE",
				"color": Color("#ff8c1a")})
			add_child(shrine)
			var sdir := _surface_dir()
			# gate sits ON TOP of the dais so F always has a clear shot at it
			shrine.global_transform = Transform3D(_basis_from_up(sdir), b.center + sdir * (b.radius + 1.9))
			# --- a proper ROUND shrine around the gate ---
			# stacked stone dais BELOW the gate: three shrinking discs
			var tiers := [[5.0, 0.7, -1.9], [3.8, 0.6, -1.2], [2.6, 0.6, -0.6]]
			for tr in tiers:
				var disc := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = tr[0]
				dm.bottom_radius = tr[0] + 0.3
				dm.height = tr[1]
				disc.mesh = dm
				disc.material_override = Destructible.make_material(Color("#c9a45e"), 0.15)
				shrine.add_child(disc)
				disc.position = Vector3(0, tr[2] + tr[1] * 0.5, 0)
			# ring of round pillars with glowing caps
			for pi2 in 6:
				var pang := TAU * float(pi2) / 6.0
				var pil := MeshInstance3D.new()
				var pm3 := CylinderMesh.new()
				pm3.top_radius = 0.28
				pm3.bottom_radius = 0.34
				pm3.height = 4.2
				pil.mesh = pm3
				pil.material_override = Destructible.make_material(Color("#b8924e"), 0.1)
				shrine.add_child(pil)
				pil.position = Vector3(cos(pang) * 4.2, 0.5, sin(pang) * 4.2)
				var cap := MeshInstance3D.new()
				var cm3 := SphereMesh.new()
				cm3.radius = 0.4
				cm3.height = 0.8
				cap.mesh = cm3
				cap.material_override = Destructible.make_material(Color("#ff8c1a"), 2.2)
				shrine.add_child(cap)
				cap.position = Vector3(cos(pang) * 4.2, 2.9, sin(pang) * 4.2)
			# the floating golden pi, visible from orbit
			var pig := Label3D.new()
			pig.text = "π"
			pig.font_size = 400
			pig.pixel_size = 0.03
			pig.modulate = Color("#ffd166")
			pig.outline_modulate = Color("#7a3c00")
			pig.outline_size = 36
			pig.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			shrine.add_child(pig)
			pig.position = Vector3(0, 6.5, 0)
			var slight := OmniLight3D.new()
			slight.light_color = Color("#ffb04a")
			slight.light_energy = 2.5
			slight.omni_range = 26.0
			shrine.add_child(slight)
			slight.position = Vector3(0, 3.0, 0)
			_spawn_res_nodes(b, 12, "raw_irid", 3)
			_build_mine(b, MINE_DIRS["Pi"], "raw_irid", 5, Color("#2a8f6a"))
		"sand":
			_register_crates(b, 50, 12)
			_euclid_landmarks(b)   # Euclid is safe: no evil aliens
		"life":
			_register_crates(b, 10, 7)
			_spawn_flora(b)
			_build_mine(b, MINE_DIRS["Verdant"], "raw_ingot", 4, Color("#a24bff"))
		"pixel", "wth", "wob", "wireframe", "contrast":
			_register_crates(b, 18, 40)
			# prism shards: ONLY grow under shader light
			for i in 14:
				var pr := Destructible.new()
				var ph := randf_range(1.8, 4.5)
				pr.setup(Vector3(randf_range(0.5, 0.9), ph, randf_range(0.5, 0.9)),
					Color("#ff7ce9"), 2, 5, 4.0, 0.0, "prism", 1)
				add_child(pr)
				_prismify(pr)
				var pd := _surface_dir()
				pr.global_transform = Transform3D(_basis_from_up(pd), b.center + pd * (b.radius + ph * 0.5))
			_spawn_enemies(b, 6, 5)   # shooters + flyers guard the shards
		"blind":
			_register_crates(b, 12, 30)
		"earth":
			# the most famous planet in the universe, populated by its
			# dumbest species. trees, lakescape greens, wandering Humans.
			# earth trees only -- no alien Verdant flora here. brown bark,
			# green canopy, planted in loose woods
			var woods: Array = []
			for i in 3:
				woods.append(_surface_dir())
			for i in _n(40):
				var td: Vector3
				if i < _n(28):
					var w: Vector3 = woods[i % woods.size()]
					td = (w + Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12),
						randf_range(-0.12, 0.12))).normalized()
				else:
					td = _surface_dir()
				_earth_tree(b, td)
			for i in _n(12):
				var hum := EarthHuman.new()
				hum.setup(b)
				add_child(hum)
				var hd := _surface_dir()
				hum.global_transform = Transform3D(_basis_from_up(hd),
					b.center + hd * (b.radius + 1.2))
			# FOUR cities, each with its own vibe, linked by a railway
			# ring. city LAYOUT gets its OWN world-seeded dice: the
			# shared stream drifts with density settings, but a city is
			# an address. it stays put.
			var crng := RandomNumberGenerator.new()
			crng.seed = hash(str(Game.world_seed) + "::cities")
			Game.earth_body = b
			Game.earth_cities = []
			var vibes: Array = [
				{"vibe": "goofy", "name": "Accident", "tint": Color("#ffb347"),
					"arch": "goofy"},
				{"vibe": "grumpy", "name": "Gary", "tint": Color("#50505a"),
					"arch": "concrete"},
				{"vibe": "dreamy", "name": "Heliopolis", "tint": Color("#9ad0ff"),
					"arch": "ancient"},
				{"vibe": "confident", "name": "Meridian City", "tint": Color("#ffd166"),
					"arch": "glass"},
			]
			for ci in 4:
				var centre := Vector3.ZERO
				while centre.length() < 0.1:
					centre = Vector3(crng.randf_range(-1, 1),
						crng.randf_range(-1, 1), crng.randf_range(-1, 1))
				centre = centre.normalized()
				Game.earth_cities.append({"dir": centre,
					"vibe": vibes[ci]["vibe"], "name": vibes[ci]["name"],
					"tint": vibes[ci]["tint"]})
				for i in _n(8):
					var bd := (centre + Vector3(crng.randf_range(-0.16, 0.16),
						crng.randf_range(-0.16, 0.16), crng.randf_range(-0.16, 0.16))).normalized()
					match str(vibes[ci]["arch"]):
						"glass":
							_glass_tower(b, bd)
						"ancient":
							_ancient_building(b, bd)
						"goofy":
							_goofy_building(b, bd)
						_:
							_city_building(b, bd, vibes[ci]["tint"])
				for i in _n(16):
					var ch := EarthHuman.new()
					ch.setup(b)
					ch.home_city = ci
					add_child(ch)
					var cd := (centre + Vector3(crng.randf_range(-0.2, 0.2),
						crng.randf_range(-0.2, 0.2), crng.randf_range(-0.2, 0.2))).normalized()
					ch.global_transform = Transform3D(_basis_from_up(cd),
						b.center + cd * (b.radius + 1.2))
				# street furniture: benches and the odd lone chair.
				for i in 4:
					_seat_prop(b, (centre + Vector3(crng.randf_range(-0.18, 0.18),
						crng.randf_range(-0.18, 0.18),
						crng.randf_range(-0.18, 0.18))).normalized(), crng, true)
				for i in 2:
					_seat_prop(b, (centre + Vector3(crng.randf_range(-0.18, 0.18),
						crng.randf_range(-0.18, 0.18),
						crng.randf_range(-0.18, 0.18))).normalized(), crng, false)
			# the railway ring: every city linked to the next one over
			for ci in 4:
				_rail(b, Game.earth_cities[ci]["dir"],
					Game.earth_cities[(ci + 1) % 4]["dir"])
			# welcome signs: TWO per city, standing right where each
			# railway leaves town -- on the outskirts, never inside a
			# building (the old fixed offset could land in one)
			for ci in 4:
				var cdir: Vector3 = Game.earth_cities[ci]["dir"]
				for nb in [(ci + 1) % 4, (ci + 3) % 4]:
					var ndir: Vector3 = Game.earth_cities[int(nb)]["dir"]
					var saxis := cdir.cross(ndir)
					if saxis.length() < 0.001:
						continue
					var sdir := cdir.rotated(saxis.normalized(), 0.22)
					_city_sign(b, sdir, str(vibes[ci]["name"]),
						str(vibes[ci]["arch"]), ndir)
			# hamlets: little clusters of unclaimed human houses out in
			# the country. dudes can't enter; humans move in, furnish
			# them to taste, and have people over
			for ti in 4:
				# every city gets a hamlet in its countryside: close
				# enough to visit, far enough to never overlap
				var cty2: Dictionary = Game.earth_cities[ti]
				var cdir: Vector3 = cty2["dir"]
				var ring_r := crng.randf_range(55.0, 95.0) / float(b.radius)
				var ring_a := crng.randf() * TAU
				var t1 := cdir.cross(Vector3.UP)
				if t1.length() < 0.01:
					t1 = cdir.cross(Vector3.RIGHT)
				t1 = t1.normalized()
				var t2 := cdir.cross(t1).normalized()
				var tc := (cdir + (t1 * cos(ring_a) + t2 * sin(ring_a)) \
					* tan(ring_r)).normalized()
				# three houses on a little ring, ~14m apart: a hamlet,
				# not a house pileup
				var ht1 := tc.cross(Vector3.UP)
				if ht1.length() < 0.01:
					ht1 = tc.cross(Vector3.RIGHT)
				ht1 = ht1.normalized()
				var ht2 := tc.cross(ht1).normalized()
				for hi in 3:
					var ha := TAU * float(hi) / 3.0 + crng.randf_range(-0.3, 0.3)
					var hr := 9.0 / float(b.radius)
					var hd3 := (tc + (ht1 * cos(ha) + ht2 * sin(ha)) \
						* tan(hr)).normalized()
					var hh2 := House.new()
					hh2.kind = "small"
					hh2.human_home = true
					# town houses live in a NEGATIVE pocket-lot band so
					# they can never share an interior with a restored
					# player house carrying the same saved slot number
					hh2.slot = -(ti * 10 + hi + 1)
					add_child(hh2)
					hh2.global_transform = Transform3D(_basis_from_up(hd3),
						b.center + hd3 * b.radius)
					hh2.rotate_object_local(Vector3.UP, crng.randf() * TAU)
				for hi2 in 3:
					var hu4 := EarthHuman.new()
					hu4.setup(b)
					add_child(hu4)
					var hud := (tc + Vector3(crng.randf_range(-0.06, 0.06),
						crng.randf_range(-0.06, 0.06), crng.randf_range(-0.06, 0.06))).normalized()
					hu4.global_transform = Transform3D(_basis_from_up(hud),
						b.center + hud * (b.radius + 1.2))
			for i in _n(8):
				_earth_mountain(b, _surface_dir())
			_add_shell(b, Color.WHITE, 1.06, true)   # drifting cloud deck
		"luna":
			# barren. gray. historic. no loot -- the Moon has nothing to sell
			for i in _n(16):
				_crater(b, _surface_dir(), randf_range(1.5, 4.5), Color("#a8a8ac"))
			_moon_flag(b)
		"ice":
			# XERO: pale craters and translucent ice spires catching the light
			for i in _n(10):
				_crater(b, _surface_dir(), randf_range(1.5, 4.0), Color("#4aa8f0"))
			for i in 12:
				var sp := Destructible.new()
				var sh := randf_range(1.8, 4.5)
				sp.setup(Vector3(randf_range(0.6, 1.1), sh, randf_range(0.6, 1.1)),
					Color("#7cd0ff"), 2, 4, 1.8)
				add_child(sp)
				var sd := _surface_dir()
				sp.global_transform = Transform3D(_basis_from_up(sd),
					b.center + sd * (b.radius + sh * 0.5))
			_spawn_rocks(b, 8, Color("#9cd2f2"))
		"mercury":
			# scorched crater field: baked boulders to smash, coal in the dark ones
			for i in _n(12):
				_crater(b, _surface_dir(), randf_range(1.0, 3.0), Color("#8a7d70"))
			_spawn_rocks(b, 14, Color("#7d7168"))
			_spawn_res_nodes(b, 10, "coal", 2)
			_spawn_res_nodes(b, 5, "uranium", 1)   # sun-baked pitchblende
		"venus":
			# the pressure-cooker: glowing fissures, sulfur crusting everything
			for i in _n(7):
				_venus_vent(b, _surface_dir())
			_add_shell(b, Color(0.9, 0.75, 0.4, 0.35), 1.09, false)
			_spawn_res_nodes(b, 12, "sulfur", 3)
			_spawn_enemies(b, 4, 2)   # even the locals are hostile. it's venus.
		"mars":
			# rust, ruins of exploration, and iridium under the dust
			for i in _n(8):
				_crater(b, _surface_dir(), randf_range(1.2, 3.5), Color("#a5502f"))
			_spawn_res_nodes(b, 10, "raw_irid", 2)
			_mars_rover(b)
		"gas":
			pass   # no surface, no loot. just clouds all the way down.
		"lava":
			# Sanus: the wealth is IN the ground, guarded by the sky.
			# deposits here are half-melted -- glowing slag you crack open
			_spawn_res_nodes(b, 10, "ultima", 2, Color("#ff5a1a"), 2.2)
			_spawn_res_nodes(b, 8, "raw_irid", 3, Color("#b8300a"), 1.4)
			_spawn_rocks(b, 10, Color("#2a0c06"))   # cooled slag boulders
		"volcanic":
			# Extroma: geologically furious, economically generous
			for i in _n(9):
				_volcano(b, _surface_dir())
			for i in _n(8):
				_boiling_spring(b, _surface_dir())
			_spawn_res_nodes(b, 8, "coal", 3)
			_spawn_res_nodes(b, 6, "raw_irid", 2)
			_spawn_res_nodes(b, 10, "uranium", 2)   # the volcanic gut glows green
			_spawn_res_nodes(b, 10, "sulfur", 3)   # sulfur crusts the springs
		"varnisol":
			# Varnisol: the gentle one. Pine woods, a big lake, wildlife.
			var grove := _surface_dir()
			for i in _n(34):
				var pd := (grove + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2),
					randf_range(-0.2, 0.2))).normalized() if i < _n(24) else _surface_dir()
				_pine(b, pd)
			_earth_lake(b, (grove + Vector3(0.3, 0.0, 0.25)).normalized())
			for i in _n(3):
				_earth_lake(b, _surface_dir())
			for i in _n(6):
				_earth_mountain(b, _surface_dir())
			for i in _n(8):
				var an := Animal.new()
				an.setup(b)
				add_child(an)
				var ad := _surface_dir()
				an.global_position = b.center + ad * (b.radius + 1.5)
		"crystal":
			# ultima crystals: guarded, far, worth the trip
			for i in 22:
				var cr := Destructible.new()
				var h := randf_range(2.5, 6.0)
				cr.setup(Vector3(randf_range(0.8, 1.4), h, randf_range(0.8, 1.4)),
					Color("#7df9ff"), 3, 5, 3.0, 0.0, "ultima", 1)
				add_child(cr)
				var cd := _surface_dir()
				cr.global_transform = Transform3D(_basis_from_up(cd), b.center + cd * (b.radius + h * 0.5))
			_register_crates(b, 12, 30)
			_spawn_enemies(b, 10, 6)   # heavily guarded
			# nerfed: was 2 ultima x 26 veins -- it printed ultima
			_build_mine(b, MINE_DIRS["Crystalia"], "ultima", 1, Color("#7df9ff"), 14)
		_:
			pass

## A railway between two city centres: plank segments laid along the
## great-circle line, sleepers every few ties. Humans ride it standing,
## because trains are a state of mind.
func _rail(b, d1: Vector3, d2: Vector3) -> void:
	var ang := acos(clampf(d1.dot(d2), -1.0, 1.0))
	if ang < 0.01:
		return
	var steps := maxi(2, int(ang * b.radius / 3.0))
	var dark := Destructible.make_material(Color("#3c3430"), 0.03)
	var light := Destructible.make_material(Color("#6a5a40"), 0.05)
	for i in steps:
		var dir := d1.slerp(d2, float(i) / steps).normalized()
		var nxt := d1.slerp(d2, float(i + 1) / steps).normalized()
		var p0: Vector3 = b.center + dir * (b.radius + 0.12)
		var p1: Vector3 = b.center + nxt * (b.radius + 0.12)
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.3, 0.1, p0.distance_to(p1) + 0.3)
		seg.mesh = bm
		seg.material_override = light if i % 3 == 0 else dark
		add_child(seg)
		var upr := dir
		var fwd := (p1 - p0).normalized()
		fwd = (fwd - upr * fwd.dot(upr)).normalized()
		var xr := upr.cross(fwd).normalized()
		seg.global_transform = Transform3D(Basis(xr, upr, -fwd).orthonormalized(),
			(p0 + p1) * 0.5)

## Somewhere to sit: a park bench (two seats) or a lone chair (one).
## Humans find these on their own. It is very important to them.
func _seat_prop(b, dir: Vector3, rng: RandomNumberGenerator, bench: bool) -> void:
	var root := Bench.new()
	root.is_bench = bench
	root.yaw = rng.randf() * TAU
	add_child(root)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Paint every mesh of a node with the shifting prism rainbow.
func _prismify(n: Node) -> void:
	(func() -> void:
		for ch in n.get_children():
			if ch is MeshInstance3D:
				ch.material_override = Human._prism_material()).call_deferred()

## Chat lines float over heads, human-bubble style.
func show_chat_bubble(pname: String, text: String) -> void:
	var target: Node3D = null
	if pname == Net.my_name():
		target = _player
	else:
		for id in Net.player_names:
			if str(Net.player_names[id]) == pname and _remote_avatars.has(id):
				target = _remote_avatars[id]["root"]
				break
	if target == null or not is_instance_valid(target):
		return
	var old := target.get_node_or_null("chatbubble")
	if old:
		old.queue_free()
	var lbl := Label3D.new()
	lbl.name = "chatbubble"
	lbl.text = text
	lbl.font_size = 22
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.outline_size = 8
	lbl.width = 420
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector3(0, 3.0, 0)
	target.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

## WELCOME TO <city>: a roadside sign dressed like its city.
func _city_sign(b, dir: Vector3, cname: String, arch: String,
		face_along: Vector3 = Vector3.ZERO) -> void:
	var root := Node3D.new()
	add_child(root)
	var board_col := Color("#3a4048")
	var post_col := Color("#5a5f66")
	var text_col := Color.WHITE
	match arch:
		"glass":
			board_col = Color("#101820")
			text_col = Color("#7bffd0")
		"ancient":
			board_col = Color("#c9b47e")
			post_col = Color("#b0a070")
			text_col = Color("#4a3a20")
		"goofy":
			board_col = Color.from_hsv(randf(), 0.6, 0.9)
			post_col = Color.from_hsv(randf(), 0.6, 0.8)
	for px in [-1.75, 1.75]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.11
		pm.height = 2.4
		post.mesh = pm
		post.position = Vector3(px, 1.2, 0)
		post.material_override = Destructible.make_material(post_col, 0.05)
		root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 1.1, 0.14)
	board.mesh = bm
	board.position = Vector3(0, 2.2, 0)
	if arch == "goofy":
		board.rotation_degrees.z = randf_range(-4.0, 4.0)   # kinda goofy. only kinda.
	board.material_override = Destructible.make_material(board_col,
		0.9 if arch == "glass" else 0.1)
	root.add_child(board)
	# DOUBLE-SIDED: a label on each face, posts moved out past the board
	# ends so neither side's text hides behind a pole
	for lz in [-0.09, 0.09]:
		var lbl := Label3D.new()
		lbl.text = "WELCOME TO\n%s" % cname.to_upper()
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate = text_col
		lbl.position = Vector3(0, 0, lz)
		if lz < 0.0:
			lbl.rotation_degrees.y = 180.0
		board.add_child(lbl)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	if face_along.length() > 0.01:
		# face SQUARE ACROSS the road (text toward travelers), and step
		# aside so the sign stands NEXT to the rails, never on them
		var tang := (face_along - dir * dir.dot(face_along)).normalized()
		var lb := root.global_transform.basis.inverse() * tang
		root.rotate_object_local(Vector3.UP, atan2(lb.x, lb.z))
		var lat := tang.cross(dir).normalized()
		root.global_position += lat * 3.5
	else:
		root.rotate_object_local(Vector3.UP, randf() * TAU)

## Peak City: glass curtain-wall skyscrapers. Tall, smug, lit like a
## quarterly report that beat expectations.
func _glass_tower(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var h := randf_range(12.0, 26.0)
	var w := randf_range(2.6, 4.2)
	# dark structural core
	var core := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(w, h, w)
	core.mesh = cm
	core.position = Vector3(0, h * 0.5 - 0.3, 0)
	core.material_override = Destructible.make_material(Color("#1c2430"), 0.05)
	root.add_child(core)
	# glass curtain: four slightly-inset glowing faces
	var glass := Destructible.make_material(Color("#6fb6dd"), 0.55)
	for face in 4:
		var pane := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(w * 0.92, h * 0.94, 0.05)
		pane.mesh = pm
		pane.position = Vector3(0, h * 0.5 - 0.3, 0)
		pane.rotation_degrees.y = face * 90.0
		pane.translate_object_local(Vector3(0, 0, w * 0.5 + 0.01))
		pane.material_override = glass
		root.add_child(pane)
	# mullions: horizontal floor lines across the glass
	var mull := Destructible.make_material(Color("#141a22"), 0.02)
	var floors := int(h / 2.2)
	for f2 in floors:
		var band := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(w + 0.12, 0.12, w + 0.12)
		band.mesh = bm2
		band.position = Vector3(0, 1.0 + float(f2) * 2.2, 0)
		band.material_override = mull
		root.add_child(band)
	# spire. of course there's a spire.
	var spire := MeshInstance3D.new()
	var sm2 := CylinderMesh.new()
	sm2.top_radius = 0.02
	sm2.bottom_radius = 0.08
	sm2.height = 2.4
	spire.mesh = sm2
	spire.position = Vector3(0, h + 0.9, 0)
	spire.material_override = Destructible.make_material(Color("#c8ccd4"), 0.8)
	root.add_child(spire)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	root.rotate_object_local(Vector3.UP, randf() * TAU)

## Eldenport: ancient architecture that goes UP -- weathered stone
## tower-houses, tapering story by story, banded and columned, like a
## city that was already old when the planet got its name.
func _ancient_building(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var stone := Destructible.make_material(Color("#d8c49a"), 0.03)
	var worn := Destructible.make_material(Color("#c2ab7e"), 0.02)
	var dark := Destructible.make_material(Color("#a08a5e"), 0.02)
	var stories := randi_range(3, 6)
	var w := randf_range(2.6, 3.6)
	var y := -0.2
	for st in stories:
		var sw := w * (1.0 - float(st) * 0.07)
		var sh := randf_range(2.2, 3.0)
		var lvl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sw, sh, sw)
		lvl.mesh = bm
		lvl.position = Vector3(0, y + sh * 0.5, 0)
		lvl.material_override = stone if st % 2 == 0 else worn
		root.add_child(lvl)
		# banded cornice between stories
		var band := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(sw + 0.3, 0.22, sw + 0.3)
		band.mesh = bbm
		band.position = Vector3(0, y + sh, 0)
		band.material_override = dark
		root.add_child(band)
		# slender window slits
		for face in 2:
			var slit := MeshInstance3D.new()
			var slm := BoxMesh.new()
			slm.size = Vector3(0.22, sh * 0.5, 0.06)
			slit.mesh = slm
			slit.position = Vector3(sw * 0.2 * (1 if face == 0 else -1),
				y + sh * 0.55, -sw * 0.5 - 0.02)
			slit.material_override = Destructible.make_material(Color("#4a3a20"), 0.4)
			root.add_child(slit)
		y += sh + 0.22
	# columned porch at the door
	for cx in [-0.9, 0.9]:
		var colm := MeshInstance3D.new()
		var clm := CylinderMesh.new()
		clm.top_radius = 0.16
		clm.bottom_radius = 0.2
		clm.height = 2.2
		colm.mesh = clm
		colm.position = Vector3(cx, 1.1, -w * 0.5 - 0.7)
		colm.material_override = stone
		root.add_child(colm)
	var lintel := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(2.4, 0.35, 1.0)
	lintel.mesh = lbm
	lintel.position = Vector3(0, 2.35, -w * 0.5 - 0.7)
	lintel.material_override = worn
	root.add_child(lintel)
	# small dome cap
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = w * 0.4
	dm.height = w * 0.4
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.position = Vector3(0, y, 0)
	dome.material_override = worn
	root.add_child(dome)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	root.rotate_object_local(Vector3.UP, randf() * TAU)

## Honkton: architecture by committee, where the committee was geese.
## Crooked stacked boxes in loud colors, porthole windows, party-hat
## roofs. Structurally reviewed by nobody. Still standing. Somehow.
func _goofy_building(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var levels := randi_range(2, 4)
	var y := -0.2
	var pw := randf_range(2.6, 3.6)
	for lv in levels:
		var lw := pw * randf_range(0.75, 1.05)
		var lh := randf_range(1.6, 2.6)
		var box := MeshInstance3D.new()
		var bm4 := BoxMesh.new()
		bm4.size = Vector3(lw, lh, lw)
		box.mesh = bm4
		box.position = Vector3(randf_range(-0.18, 0.18), y + lh * 0.5,
			randf_range(-0.18, 0.18))
		box.rotation_degrees.y = randf_range(-6.0, 6.0)   # kinda goofy. only kinda
		box.material_override = Destructible.make_material(
			Color.from_hsv(randf(), randf_range(0.3, 0.55), randf_range(0.65, 0.9)), 0.12)
		root.add_child(box)
		# porthole window: one glowing circle per level
		var port := MeshInstance3D.new()
		var pmz := CylinderMesh.new()
		pmz.top_radius = 0.3
		pmz.bottom_radius = 0.3
		pmz.height = 0.06
		port.mesh = pmz
		port.rotation_degrees.x = 90.0
		port.position = Vector3(0, y + lh * 0.55, -lw * 0.5 - 0.02)
		port.material_override = Destructible.make_material(Color("#fff2a8"), 1.8)
		box.add_child(port)
		y += lh
		pw = lw
	# a hat, most of the time. sometimes restraint wins
	if randf() < 0.6:
		var roof := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.0
		rm.bottom_radius = pw * 0.7
		rm.height = randf_range(1.0, 1.8)
		roof.mesh = rm
		roof.position = Vector3(0, y + rm.height * 0.5, 0)
		roof.material_override = Destructible.make_material(
			Color.from_hsv(randf(), 0.5, 0.85), 0.3)
		root.add_child(roof)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	root.rotate_object_local(Vector3.UP, randf() * TAU)

## A city tower: concrete box, lit windows scattered up its faces, roof
## lip. Humanity's whole architectural output, honestly.
func _city_building(b, dir: Vector3, tint: Color = Color(0.5, 0.5, 0.5)) -> void:
	var root := Node3D.new()
	add_child(root)
	var h := randf_range(5.0, 15.0)
	var w := randf_range(2.5, 4.5)
	var d := randf_range(2.5, 4.5)
	var tone := randf_range(0.45, 0.7)
	var tower := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(w, h, d)
	tower.mesh = tm
	tower.position = Vector3(0, h * 0.5 - 0.3, 0)
	tower.material_override = Destructible.make_material(
		Color(tone, tone, tone * 1.04).lerp(tint, 0.25), 0.03)
	root.add_child(tower)
	var lip := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(w + 0.3, 0.25, d + 0.3)
	lip.mesh = lm
	lip.position = Vector3(0, h - 0.2, 0)
	lip.material_override = Destructible.make_material(Color(tone * 0.7, tone * 0.7, tone * 0.72), 0.02)
	root.add_child(lip)
	# lit windows: some floors home, some floors not
	for i in randi_range(6, 14):
		var win := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.5, 0.35, 0.06)
		win.mesh = wm
		var face := randi() % 4
		var fx := randf_range(-w * 0.35, w * 0.35)
		var fy := randf_range(0.8, h - 1.0)
		match face:
			0: win.position = Vector3(fx, fy, -d * 0.5 - 0.03)
			1: win.position = Vector3(fx, fy, d * 0.5 + 0.03)
			2:
				win.position = Vector3(-w * 0.5 - 0.03, fy, fx)
				win.rotation_degrees.y = 90
			3:
				win.position = Vector3(w * 0.5 + 0.03, fy, fx)
				win.rotation_degrees.y = 90
		win.material_override = Destructible.make_material(
			Color("#ffe9a8") if randf() < 0.7 else Color("#9adfff"), 1.6)
		root.add_child(win)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	root.rotate_object_local(Vector3.UP, randf() * TAU)

## Earth trees: proper trunk + leafy blobs. Not Verdant's alien flora --
## the boring, beautiful, regular kind.
func _earth_tree(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var polar := absf(dir.y) > 0.68   # up in the snow latitudes
	var h := randf_range(3.0, 5.5)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.3
	tm.height = h
	trunk.mesh = tm
	trunk.position = Vector3(0, h * 0.5, 0)
	trunk.material_override = Destructible.make_material(Color("#6b4a2a"), 0.05)
	root.add_child(trunk)
	for i in 3:
		var leaf := MeshInstance3D.new()
		var lm := SphereMesh.new()
		var r := randf_range(1.0, 1.8)
		lm.radius = r
		lm.height = r * 1.7
		leaf.mesh = lm
		leaf.position = Vector3(randf_range(-0.7, 0.7), h - 0.4 + randf_range(0.0, 1.0),
			randf_range(-0.7, 0.7))
		var leafc := Color("#2f7d32").lerp(Color("#5aa53f"), randf())
		if polar:
			leafc = leafc.lerp(Color("#dfe8f0"), 0.75)   # snow-loaded canopy
		leaf.material_override = Destructible.make_material(leafc, 0.08)
		root.add_child(leaf)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

# ------------------------------------ Tris system surface features

## Small volcano: jagged cone with a glowing throat and a smoke wisp.
func _volcano(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var h := randf_range(4.0, 8.0)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = h * 0.22
	cm.bottom_radius = h * 0.6
	cm.height = h
	cm.radial_segments = 8
	cone.mesh = cm
	cone.position = Vector3(0, h * 0.5 - 0.3, 0)
	cone.material_override = Destructible.make_material(Color("#7a6428"), 0.05)
	root.add_child(cone)
	var throat := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = h * 0.18
	tm.bottom_radius = h * 0.1
	tm.height = 0.3
	throat.mesh = tm
	throat.position = Vector3(0, h - 0.25, 0)
	throat.material_override = Destructible.make_material(Color("#ff5a1a"), 2.5)
	root.add_child(throat)
	var smoke := MeshInstance3D.new()
	var sm5 := SphereMesh.new()
	sm5.radius = h * 0.2
	sm5.height = h * 0.4
	smoke.mesh = sm5
	smoke.position = Vector3(h * 0.06, h + 0.6, 0)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.3, 0.28, 0.26, 0.45)
	smoke.material_override = smat
	root.add_child(smoke)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Boiling spring: milky turquoise pool, mineral rim, rising bubbles.
func _boiling_spring(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var r := randf_range(1.6, 3.2)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r * 1.2
	rm.bottom_radius = r * 1.25
	rm.height = 0.22
	rim.mesh = rm
	rim.material_override = Destructible.make_material(Color("#d8c890"), 0.1)
	root.add_child(rim)
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = r
	pm.bottom_radius = r
	pm.height = 0.14
	pool.mesh = pm
	pool.position = Vector3(0, 0.08, 0)
	pool.material_override = Destructible.make_material(Color("#5ad8c8"), 1.2)
	root.add_child(pool)
	for i in 5:
		var bub := MeshInstance3D.new()
		var bm2 := SphereMesh.new()
		bm2.radius = randf_range(0.08, 0.18)
		bm2.height = bm2.radius * 2.0
		bub.mesh = bm2
		bub.position = Vector3(randf_range(-r * 0.6, r * 0.6),
			randf_range(0.2, 0.7), randf_range(-r * 0.6, r * 0.6))
		bub.material_override = Destructible.make_material(Color("#bff2ea"), 0.8)
		root.add_child(bub)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Pine: straight trunk, three stacked dark-green cones. Varnisol's tree.
func _pine(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var h := randf_range(4.0, 7.0)
	var trunk := MeshInstance3D.new()
	var tm2 := CylinderMesh.new()
	tm2.top_radius = 0.12
	tm2.bottom_radius = 0.2
	tm2.height = h * 0.4
	trunk.mesh = tm2
	trunk.position = Vector3(0, h * 0.2, 0)
	trunk.material_override = Destructible.make_material(Color("#5e4020"), 0.05)
	root.add_child(trunk)
	for i in 3:
		var tier := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.0
		cm2.bottom_radius = h * (0.3 - float(i) * 0.07)
		cm2.height = h * 0.34
		tier.mesh = cm2
		tier.position = Vector3(0, h * 0.35 + float(i) * h * 0.22, 0)
		tier.material_override = Destructible.make_material(
			Color("#1d4a26").lerp(Color("#2f6b34"), randf()), 0.06)
		root.add_child(tier)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Sanus lava arc: a burst of molten blobs near the player. Fx cleans
## itself up; standing near the strike hurts A LOT.
class _ArcFx extends Node3D:
	var life := 1.2
	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()

## Fire erupts from a random surface point near the player: a fast,
## unpredictable particle jet arcing back down under gravity.
func _spawn_lava_arc(b, player_pos: Vector3) -> void:
	var up: Vector3 = (player_pos - b.center).normalized()
	var tang := up.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
	if tang.length() < 0.01:
		tang = up.cross(Vector3.RIGHT)
	tang = tang.normalized()
	# anywhere around you, not at you -- unpredictable like the worms
	var strike: Vector3 = b.center + (up + tang * randf_range(0.0, 0.5)).normalized() * b.radius
	var fx := _ArcFx.new()
	fx.life = 2.4
	add_child(fx)
	fx.global_position = strike
	var parts := GPUParticles3D.new()
	parts.amount = 140
	parts.one_shot = true
	parts.explosiveness = 0.9
	parts.lifetime = 1.4
	var pm2 := ParticleProcessMaterial.new()
	pm2.direction = Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))
	pm2.spread = 22.0
	pm2.initial_velocity_min = 26.0
	pm2.initial_velocity_max = 58.0
	pm2.gravity = -up * 24.0   # arcs bend back to the ground
	pm2.scale_min = 0.12
	pm2.scale_max = 0.4
	pm2.color = Color("#ff5a1a")
	parts.process_material = pm2
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.5
	pmesh.height = 1.0
	pmesh.radial_segments = 6
	pmesh.rings = 3
	pmesh.material = Destructible.make_material(Color("#ff7a2a"), 4.0)
	parts.draw_pass_1 = pmesh
	fx.add_child(parts)
	parts.emitting = true
	Sfx.play("explode", -14.0)
	var p = get_tree().get_first_node_in_group("player")
	if p and p.global_position.distance_to(strike) < 8.0:
		Game.hurt(35.0)   # the flying molten rock is its own announcement

# ------------------------------------------- Sol system surface features

## Crater: a flattened rim ring + darker floor disc, dug into the shading.
func _crater(b, dir: Vector3, size: float, col: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = size * 0.7
	tm.outer_radius = size
	rim.mesh = tm
	rim.scale = Vector3(1, 0.35, 1)
	rim.material_override = Destructible.make_material(col.lightened(0.15), 0.05)
	root.add_child(rim)
	var floor_m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size * 0.72
	cm.bottom_radius = size * 0.72
	cm.height = 0.1
	floor_m.mesh = cm
	floor_m.position = Vector3(0, -0.05, 0)
	floor_m.material_override = Destructible.make_material(col.darkened(0.35), 0.02)
	root.add_child(floor_m)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## The flag. You know the one. Planted by somebody, sometime.
func _moon_flag(b) -> void:
	var dir := Vector3(0.3, 0.9, 0.2).normalized()
	var root := Node3D.new()
	add_child(root)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = 2.4
	pole.mesh = pm
	pole.position = Vector3(0, 1.2, 0)
	pole.material_override = Destructible.make_material(Color("#c8c8d0"), 0.3)
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	var flm := BoxMesh.new()
	flm.size = Vector3(1.1, 0.7, 0.04)
	cloth.mesh = flm
	cloth.position = Vector3(0.57, 2.0, 0)
	cloth.material_override = Destructible.make_material(Color("#d94a3a"), 0.5)
	root.add_child(cloth)
	# footprints leading away from it, going nowhere
	for i in 6:
		var fp := MeshInstance3D.new()
		var fpm := BoxMesh.new()
		fpm.size = Vector3(0.14, 0.02, 0.3)
		fp.mesh = fpm
		fp.position = Vector3(0.6 + float(i) * 0.5, 0.01, 0.4 + sin(float(i) * 1.2) * 0.3)
		fp.material_override = Destructible.make_material(Color("#8a8a90"), 0.02)
		root.add_child(fp)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## An abandoned rover, still faithfully parked. F reads its status.
func _mars_rover(b) -> void:
	var dir := Vector3(-0.5, 0.6, 0.4).normalized()
	var root := Node3D.new()
	add_child(root)
	var bodym := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.4, 0.9)
	bodym.mesh = bm
	bodym.position = Vector3(0, 0.55, 0)
	bodym.material_override = Destructible.make_material(Color("#d8d8e0"), 0.3)
	root.add_child(bodym)
	for sx in [-0.55, 0.55]:
		for szp in [-0.35, 0.0, 0.35]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.18
			wm.bottom_radius = 0.18
			wm.height = 0.12
			wheel.mesh = wm
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(sx, 0.18, szp)
			wheel.material_override = Destructible.make_material(Color("#2a2a30"), 0.1)
			root.add_child(wheel)
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.03
	mm.bottom_radius = 0.03
	mm.height = 0.7
	mast.mesh = mm
	mast.position = Vector3(0.35, 1.1, 0)
	mast.material_override = Destructible.make_material(Color("#8a8a94"), 0.2)
	root.add_child(mast)
	var cam := MeshInstance3D.new()
	var cmm := BoxMesh.new()
	cmm.size = Vector3(0.22, 0.12, 0.1)
	cam.mesh = cmm
	cam.position = Vector3(0.35, 1.5, 0)
	cam.material_override = Destructible.make_material(Color("#3a3a44"), 0.3)
	root.add_child(cam)
	var panel := MeshInstance3D.new()
	var pnm := BoxMesh.new()
	pnm.size = Vector3(0.9, 0.03, 0.5)
	panel.mesh = pnm
	panel.position = Vector3(-0.2, 0.8, 0)
	panel.rotation_degrees = Vector3(0, 0, 8)
	panel.material_override = Destructible.make_material(Color("#1a3a6e"), 0.6)
	root.add_child(panel)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Snow-capped mountain: stone cone with a white tip.
func _earth_mountain(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	# mountains belong to their planet: bigger world, bigger ranges
	var sf: float = maxf(1.0, b.radius / 62.0)
	var h := randf_range(6.0, 12.0) * sf
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = h * 0.55
	cm.height = h
	cm.radial_segments = 7   # jagged, not perfect
	cone.mesh = cm
	cone.position = Vector3(0, h * 0.5 - 0.4, 0)
	# polar ranges are snowed in to the roots, not just capped
	var rockc := Color("#dfe6ee") if absf(dir.y) > 0.68 else Color("#5a564e")
	cone.material_override = Destructible.make_material(rockc, 0.05)
	root.add_child(cone)
	var snow := MeshInstance3D.new()
	var sm2 := CylinderMesh.new()
	sm2.top_radius = 0.0
	sm2.bottom_radius = h * 0.18
	sm2.height = h * 0.32
	sm2.radial_segments = 7
	snow.mesh = sm2
	snow.position = Vector3(0, h - h * 0.16 - 0.4, 0)
	snow.material_override = Destructible.make_material(Color("#eef2f6"), 0.2)
	root.add_child(snow)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## A lake: glassy blue disc with a sandy rim, flush with the ground.
func _earth_lake(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	# lakes scale with their world too
	var sf: float = maxf(1.0, b.radius / 62.0)
	var r := randf_range(4.0, 8.0) * sf
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r * 1.15
	rm.bottom_radius = r * 1.15
	rm.height = 0.08
	rim.mesh = rm
	rim.material_override = Destructible.make_material(Color("#c8b078"), 0.05)
	root.add_child(rim)
	var water := MeshInstance3D.new()
	var wm2 := CylinderMesh.new()
	wm2.top_radius = r
	wm2.bottom_radius = r
	wm2.height = 0.1
	water.mesh = wm2
	water.position = Vector3(0, 0.04, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.35, 0.6, 0.85)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.05
	wmat.metallic = 0.4
	water.material_override = wmat
	root.add_child(water)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Venus fissure: a glowing crack venting the heat below.
func _venus_vent(b, dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	for i in 4:
		var seg := MeshInstance3D.new()
		var sm3 := BoxMesh.new()
		sm3.size = Vector3(randf_range(0.4, 0.8), 0.15, randf_range(1.6, 3.0))
		seg.mesh = sm3
		seg.position = Vector3(randf_range(-0.8, 0.8), 0.02, float(i) * 2.2 - 3.3)
		seg.rotation_degrees = Vector3(0, randf_range(-25, 25), 0)
		seg.material_override = Destructible.make_material(Color("#ff6a1a"), 2.2)
		root.add_child(seg)
	root.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)

## Translucent atmosphere shell (venus haze, earth cloud deck).
func _add_shell(b, col: Color, scale_f: float, cloudy: bool) -> void:
	var shell := MeshInstance3D.new()
	var sm4 := SphereMesh.new()
	sm4.radius = b.radius * scale_f
	sm4.height = b.radius * scale_f * 2.0
	sm4.radial_segments = 48
	sm4.rings = 24
	shell.mesh = sm4
	if cloudy:
		var csh := Shader.new()
		csh.code = "shader_type spatial;\nrender_mode blend_mix, cull_back, shadows_disabled;\nvarying vec3 vn;\n" \
			+ _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float c = fbm(n * 4.0 + vec3(TIME * 0.006, 0.0, TIME * 0.004));
	ALBEDO = vec3(1.0);
	ALPHA = smoothstep(0.52, 0.72, c) * 0.75;
	ROUGHNESS = 1.0;
}
"""
		var cmat := ShaderMaterial.new()
		cmat.shader = csh
		shell.material_override = cmat
	else:
		var hmat := StandardMaterial3D.new()
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = col
		hmat.roughness = 1.0
		shell.material_override = hmat
	add_child(shell)
	shell.global_position = b.center

## Off-world resource nodes (mid-game: raw iridium etc).
## Resource deposits look like WHAT THEY ARE: boulders in the resource's
## colour -- glowing only when the ore itself glows. No more green towers.
const RES_LOOK := {
	"coal":      {"col": Color("#1e1e22"), "emit": 0.1},
	"raw_ingot": {"col": Color("#a24bff"), "emit": 0.8},
	"raw_irid":  {"col": Color("#2a8f6a"), "emit": 0.8},
	"ultima":    {"col": Color("#7df9ff"), "emit": 2.2},
	"uranium":   {"col": Color("#5aff3a"), "emit": 2.5},
	"sulfur":    {"col": Color("#e8d44a"), "emit": 0.5},
}

func _spawn_res_nodes(b, count: int, res: String, per: int,
		col_override: Color = Color.BLACK, emit_override: float = -1.0) -> void:
	count = _n(count)
	var look: Dictionary = RES_LOOK.get(res, {"col": Color("#2a8f6a"), "emit": 1.0})
	if col_override != Color.BLACK:
		look = {"col": col_override, "emit": emit_override if emit_override >= 0.0 else 1.0}
	for i in count:
		var nd := Destructible.new()
		nd.rock = true
		var s := randf_range(1.2, 2.2)
		nd.setup(Vector3(s, s * randf_range(0.8, 1.3), s), look["col"], 2, 4,
			float(look["emit"]), 0.0, res, per)
		add_child(nd)
		(func() -> void:
			_dress_ore(nd, res, s)).call_deferred()
		var d := _surface_dir()
		nd.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + s * 0.45))

## Every ore is ITS OWN THING: unique rock skin + embedded features,
## not a tinted cube. Ultima and prism boil with their glows; uranium is
## pitchblende -- near-black with sickly green veins.
func _dress_ore(nd: Node3D, res: String, s: float) -> void:
	if not is_instance_valid(nd):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(nd.global_position.x * 13.0 + nd.global_position.z * 7.0)) + 3
	var base_mat: Material = null
	match res:
		"coal":
			base_mat = Surfaces.stone(Color("#17171a"))
		"raw_irid":
			base_mat = Surfaces.stone(Color("#4a4e58"))
		"sulfur":
			base_mat = Surfaces.stone(Color("#b8a24a"))
		"uranium":
			var mu := StandardMaterial3D.new()
			mu.albedo_color = Color("#10140c")
			mu.roughness = 0.8
			base_mat = mu
		"ultima":
			base_mat = Surfaces.stone(Color("#0e2a30"))
		"prism":
			base_mat = Surfaces.stone(Color("#2a1030"))
		"raw_ingot":
			base_mat = Surfaces.stone(Color("#5a4634"))
	if base_mat != null:
		for ch in nd.get_children():
			if ch is MeshInstance3D:
				ch.material_override = base_mat
	match res:
		"coal":
			# glossy black lumps half-buried in the matte rock
			var glossy := StandardMaterial3D.new()
			glossy.albedo_color = Color("#0a0a0c")
			glossy.roughness = 0.12
			glossy.metallic = 0.4
			for i in 5:
				var lump := MeshInstance3D.new()
				var lm := BoxMesh.new()
				var ls := s * rng.randf_range(0.16, 0.3)
				lm.size = Vector3(ls, ls, ls)
				lump.mesh = lm
				lump.material_override = glossy
				lump.position = Vector3(rng.randf_range(-0.4, 0.4) * s,
					rng.randf_range(0.1, 0.6) * s, rng.randf_range(-0.4, 0.4) * s)
				lump.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
				nd.add_child(lump)
		"raw_irid", "raw_ingot":
			# angular metallic shards jutting out
			var met := StandardMaterial3D.new()
			if res == "raw_irid":
				met.albedo_color = Color("#8a5ac8")
				met.emission_enabled = true
				met.emission = Color("#40e0d0")
				met.emission_energy_multiplier = 0.35
			else:
				met.albedo_color = Color("#b87848")
			met.metallic = 0.95
			met.roughness = 0.2
			for i in 4:
				var shard := MeshInstance3D.new()
				var shm := BoxMesh.new()
				shm.size = Vector3(0.12 * s, rng.randf_range(0.35, 0.6) * s, 0.16 * s)
				shard.mesh = shm
				shard.material_override = met
				shard.position = Vector3(rng.randf_range(-0.35, 0.35) * s,
					rng.randf_range(0.2, 0.6) * s, rng.randf_range(-0.35, 0.35) * s)
				shard.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU,
					rng.randf_range(-0.6, 0.6))
				nd.add_child(shard)
		"sulfur":
			# bright crusty clusters caked on top
			var crust := StandardMaterial3D.new()
			crust.albedo_color = Color("#ffe81a")
			crust.roughness = 0.95
			crust.emission_enabled = true
			crust.emission = Color("#ffdf40")
			crust.emission_energy_multiplier = 0.15
			for i in 6:
				var pod := MeshInstance3D.new()
				var pmm := SphereMesh.new()
				pmm.radius = s * rng.randf_range(0.09, 0.17)
				pmm.height = pmm.radius * 1.6
				pod.mesh = pmm
				pod.material_override = crust
				pod.position = Vector3(rng.randf_range(-0.38, 0.38) * s,
					rng.randf_range(0.3, 0.62) * s, rng.randf_range(-0.38, 0.38) * s)
				nd.add_child(pod)
		"uranium":
			# pitchblende veins: thin sickly-green seams wrapping the rock
			var vein := StandardMaterial3D.new()
			vein.albedo_color = Color("#26330e")
			vein.emission_enabled = true
			vein.emission = Color("#9aff2a")
			vein.emission_energy_multiplier = 0.8
			for i in 4:
				var vn := MeshInstance3D.new()
				var vm := BoxMesh.new()
				vm.size = Vector3(s * rng.randf_range(0.7, 1.05), 0.05 * s, 0.07 * s)
				vn.mesh = vm
				vn.material_override = vein
				vn.position = Vector3(0, rng.randf_range(0.15, 0.65) * s, 0)
				vn.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU,
					rng.randf_range(-0.5, 0.5))
				nd.add_child(vn)
		"ultima":
			for i in 4:
				var spk := MeshInstance3D.new()
				var sm2 := CylinderMesh.new()
				sm2.top_radius = 0.0
				sm2.bottom_radius = 0.1 * s
				sm2.height = rng.randf_range(0.5, 0.9) * s
				sm2.radial_segments = 5
				spk.mesh = sm2
				spk.material_override = Surfaces.portal(Color("#7df9ff"))
				spk.position = Vector3(rng.randf_range(-0.3, 0.3) * s,
					rng.randf_range(0.35, 0.6) * s, rng.randf_range(-0.3, 0.3) * s)
				spk.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0,
					rng.randf_range(-0.5, 0.5))
				nd.add_child(spk)
		"prism":
			for i in 4:
				var spk2 := MeshInstance3D.new()
				var sm3 := CylinderMesh.new()
				sm3.top_radius = 0.0
				sm3.bottom_radius = 0.09 * s
				sm3.height = rng.randf_range(0.5, 0.85) * s
				sm3.radial_segments = 5
				spk2.mesh = sm3
				spk2.material_override = Human._prism_material()
				spk2.position = Vector3(rng.randf_range(-0.3, 0.3) * s,
					rng.randf_range(0.35, 0.6) * s, rng.randf_range(-0.3, 0.3) * s)
				spk2.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0,
					rng.randf_range(-0.5, 0.5))
				nd.add_child(spk2)

## Plain breakable boulders: no ore, a little pocket change, pure geology.
func _spawn_rocks(b, count: int, col: Color) -> void:
	for i in _n(count):
		var nd := Destructible.new()
		nd.rock = true
		var s := randf_range(1.0, 2.4)
		nd.setup(Vector3(s, s * randf_range(0.7, 1.2), s), col, 2, 3, 0.1)
		add_child(nd)
		var d := _surface_dir()
		nd.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + s * 0.45))

func _spawn_enemies(b, count: int, level: int) -> void:
	for i in _n(count):
		var e := Enemy.new()
		e.setup(level, b)
		add_child(e)
		var dir := _surface_dir()
		e.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * (b.radius + 2.0))

func _spawn_flora(b) -> void:
	# FORESTS: dense clusters around a few centres; the rest scattered.
	var forests: Array = []
	for i in 4:
		forests.append(_surface_dir())
	for i in _n(130):
		var pl := Plant.new()
		add_child(pl)
		var d: Vector3
		if i < 80:
			# forest member: perturb around a forest centre
			var f: Vector3 = forests[i % forests.size()]
			d = (f + Vector3(randf_range(-0.14, 0.14), randf_range(-0.14, 0.14), randf_range(-0.14, 0.14))).normalized()
		else:
			d = _surface_dir()
		pl.global_transform = Transform3D(_basis_from_up(d), b.center + d * b.radius)
	var shroom_dirs: Array = []
	for i in 55:
		var mu := Mushroom.new()
		add_child(mu)
		var d2 := _surface_dir()
		shroom_dirs.append(d2)
		mu.global_transform = Transform3D(_basis_from_up(d2), b.center + d2 * b.radius)
	# animals: LAND ones live in the forests, FLIERS fill the skies elsewhere
	for i in 30:
		var an := Animal.new()
		var d3: Vector3
		if i < 20:
			var f2: Vector3 = forests[i % forests.size()]
			d3 = (f2 + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))).normalized()
			an.setup(b, true)    # grounded: walkers + tiny hoppers
		else:
			d3 = _surface_dir()
			an.setup(b, false)   # flier
		add_child(an)
		an.global_transform = Transform3D(_basis_from_up(d3), b.center + d3 * (b.radius + 1.0))
	# tiny bugs scuttling around the mushrooms
	for i in 14:
		var bug := Animal.new()
		bug.setup(b, true, true)
		add_child(bug)
		var md: Vector3 = shroom_dirs[randi() % shroom_dirs.size()]
		md = (md + Vector3(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), randf_range(-0.02, 0.02))).normalized()
		bug.global_transform = Transform3D(_basis_from_up(md), b.center + md * (b.radius + 0.4))
	# a few Permadeath Apples hidden among the plants
	for i in 3:
		var pa := PermaApple.new()
		add_child(pa)
		var d := _surface_dir()
		pa.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + 1.5))

func _euclid_landmarks(b) -> void:
	# North pole: a TINY temple. Doctor-Who rules: small outside,
	# cathedral inside. No signs.
	var np: Vector3 = b.center + Vector3.UP * b.radius
	var tiers := [Vector3(8, 1.6, 8), Vector3(6, 1.6, 6), Vector3(4, 2.4, 4)]
	var y := 0.0
	for t in tiers:
		var step := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = t
		step.mesh = m
		step.material_override = Destructible.make_material(Color("#d8c48a"), 0.08)
		add_child(step)
		step.global_transform = Transform3D(_basis_from_up(Vector3.UP), np + Vector3.UP * (y + t.y * 0.5))
		y += t.y
	for ci in 4:
		var ang := TAU * float(ci) / 4.0 + PI / 4.0
		var colmn := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.3
		cm2.bottom_radius = 0.4
		cm2.height = 3.0
		colmn.mesh = cm2
		colmn.material_override = Destructible.make_material(Color("#c9b47e"), 0.05)
		add_child(colmn)
		colmn.global_transform = Transform3D(_basis_from_up(Vector3.UP),
			np + Vector3(cos(ang) * 5.5, 1.5, sin(ang) * 5.5))
	# a small red button block by the base. figure it out.
	_temple_np = np
	_temple_B = _basis_from_up(Vector3.UP)
	_temple_btn = Gate.new().configure({
		"action": "terminal", "label": "DOOR TERMINAL", "color": Color("#c22")})
	add_child(_temple_btn)
	_temple_btn.global_transform = Transform3D(_temple_B, np + Vector3(0, 0, 8.0))
	Zones.build_temple_interior(self, np + Vector3(0, 2, 20),
		Universe.make_flat_body(Zones.TEMPLE_POS))

	# South pole: the sealed pyramid. Mind Core opens it. Zero-g inside.
	var sp: Vector3 = b.center + Vector3.DOWN * b.radius
	var pyr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 20.0
	cm.height = 26.0
	cm.radial_segments = 4
	pyr.mesh = cm
	pyr.material_override = Destructible.make_material(Color("#b5934f"), 0.1)
	add_child(pyr)
	pyr.global_transform = Transform3D(_basis_from_up(Vector3.DOWN), sp + Vector3.DOWN * 13.0)
	_pyramid_exit = sp + Vector3.DOWN * 2.0
	# inside the pyramid: the MENGER SHRINE. F + prism shards = enchant.
	var shrine := MengerShrine.new()
	add_child(shrine)
	shrine.global_transform = Transform3D(_basis_from_up(Vector3.DOWN), sp + Vector3.DOWN * 10.0)

func _register_crates(b, count: int, value: int) -> void:
	count = _n(count)
	var grp := "brk_" + str(b.name)
	_crate_beds.append({"body": b, "value": value, "group": grp, "target": count})
	_scatter_crates(b, count, value, grp)

func _scatter_crates(b, count: int, value: int, grp: String) -> void:
	for i in count:
		var d := Destructible.new()
		var kind := randi() % 3
		var size: Vector3
		match kind:
			0:
				var s := randf_range(1.2, 2.6)
				size = Vector3(s, s, s)
			1:
				size = Vector3(randf_range(1.4, 2.8), randf_range(3.0, 7.0), randf_range(1.4, 2.8))
			_:
				size = Vector3(randf_range(2.4, 4.5), randf_range(0.7, 1.4), randf_range(2.4, 4.5))
		d.setup(size, _palette[randi() % _palette.size()], 1, value)
		add_child(d)
		d.add_to_group(grp)
		var dir := _surface_dir()
		d.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * (b.radius + size.y * 0.5))

## The rocket appears next to you the moment you own one (bought in shop).
func _spawn_bought_rocket() -> void:
	if not Inventory.has_rocket or (_rocket and is_instance_valid(_rocket)):
		return
	if Game.mode != Game.Mode.ON_FOOT or not _player:
		return
	var up := (_player.global_position - Universe.nearest(_player.global_position).center).normalized()
	_rocket = Rocket.new()
	add_child(_rocket)
	var side := _player.global_transform.basis.x
	_rocket.global_transform = Transform3D(_basis_from_up(up), _player.global_position + side * 5.0 + up * 1.5)
	if _rocket_hud:
		_rocket_hud.set_rocket(_rocket)

## A bought Spawn Beacon drops at the player and becomes the active spawn.
func _place_spawn_beacon() -> void:
	if not Inventory.want_spawn_beacon or Game.mode != Game.Mode.ON_FOOT or not _player:
		return
	Inventory.want_spawn_beacon = false
	var up := (_player.global_position - Universe.nearest(_player.global_position).center).normalized()
	var bcn := SpawnBeacon.new()
	add_child(bcn)
	bcn.global_transform = Transform3D(_basis_from_up(up), _player.global_position - up * 1.0)
	bcn.activate_spawn()

## Slowly restock destroyed crates on every planet.
func _regen_crates(delta: float) -> void:
	_regen_t -= delta
	if _regen_t > 0.0:
		return
	_regen_t = 6.0
	for bed in _crate_beds:
		var have := get_tree().get_nodes_in_group(bed["group"]).size()
		if have < int(bed["target"]):
			_scatter_crates(bed["body"], mini(int(bed["target"]) - have, 12), int(bed["value"]), bed["group"])

func _place_on_surface(b, node: Node3D, dir: Vector3, after: Callable) -> void:
	add_child(node)
	node.global_transform = Transform3D(_basis_from_up(dir), b.center + dir * b.radius)
	after.call(node)

## The mine on Home gets clue ARROWS. Other planets have mines too --
## no arrows there, just an open hole you can SEE INTO. Figure it out.
func _spawn_mine_clues(b) -> void:
	var dir: Vector3 = MINE_DIRS["Home"]
	_build_mine(b, dir, "raw_ingot", 6, Color("#a24bff"))
	var mine_pos: Vector3 = b.center + dir * b.radius
	for i in 9:
		var d := _surface_dir()
		var pos: Vector3 = b.center + d * b.radius
		var to_mine: Vector3 = mine_pos - pos
		var tangent := to_mine - d * to_mine.dot(d)
		if tangent.length() < 2.0:
			continue
		_arrow(pos + d * 0.15, d, tangent.normalized())

## A full mine: open see-through mouth, shaft into the planet, ore
## chamber with a furnace, exit gate that drops you BESIDE the hole.
func _build_mine(b, dir: Vector3, res_id: String, res_n: int, ore_col: Color, ore_count: int = 26) -> void:
	var C: Vector3 = b.center
	var R: float = b.radius
	var B := _basis_from_up(dir)
	var cham_y := R - 21.0

	# glowing rim marking the mouth
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.4
	tm.outer_radius = 4.6
	rim.mesh = tm
	rim.material_override = Destructible.make_material(Color("#6a3aa0"), 1.2)
	add_child(rim)
	rim.global_transform = Transform3D(B, C + dir * (R + 0.3))

	# shaft: 4 walls, open top and bottom -- wide enough to jetpack out
	var shaft_specs := [
		[Vector3(0.6, 17, 8.6), Vector3(4.3, 0, 0)],
		[Vector3(0.6, 17, 8.6), Vector3(-4.3, 0, 0)],
		[Vector3(8.6, 17, 0.6), Vector3(0, 0, 4.3)],
		[Vector3(8.6, 17, 0.6), Vector3(0, 0, -4.3)],
	]
	for sspec in shaft_specs:
		_mine_box(B, C + B * (Vector3(sspec[1].x, R - 6.5, sspec[1].z)), sspec[0], Color("#241436"), 0.2)

	# chamber: floor, walls, ceiling with an 8x8 hole where the shaft lands
	_mine_box(B, C + B * Vector3(0, cham_y - 6.0, 0), Vector3(36, 1, 36), Color("#241436"), 0.15)
	for w in [[Vector3(1, 12, 36), Vector3(17.5, 0, 0)], [Vector3(1, 12, 36), Vector3(-17.5, 0, 0)],
			[Vector3(36, 12, 1), Vector3(0, 0, 17.5)], [Vector3(36, 12, 1), Vector3(0, 0, -17.5)]]:
		_mine_box(B, C + B * (Vector3(w[1].x, cham_y, w[1].z)), w[0], Color("#241436"), 0.1)
	for cspec in [[Vector3(36, 1, 14.0), Vector3(0, 6, 11.0)], [Vector3(36, 1, 14.0), Vector3(0, 6, -11.0)],
			[Vector3(14.0, 1, 8.0), Vector3(11.0, 6, 0)], [Vector3(14.0, 1, 8.0), Vector3(-11.0, 6, 0)]]:
		_mine_box(B, C + B * (Vector3(cspec[1].x, cham_y + cspec[1].y, cspec[1].z)), cspec[0], Color("#241436"), 0.1)
	# glowing beam marking the way out
	var beam := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 0.15
	bm2.bottom_radius = 0.15
	bm2.height = 20.0
	beam.mesh = bm2
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(1.0, 0.88, 0.4, 0.25)
	bmat.emission_enabled = true
	bmat.emission = Color("#ffe066")
	bmat.emission_energy_multiplier = 1.5
	beam.material_override = bmat
	add_child(beam)
	beam.global_transform = Transform3D(B, C + dir * (R - 12.0))

	# light it
	for ly in [R - 8.0, cham_y]:
		var l := OmniLight3D.new()
		l.light_energy = 1.8
		l.omni_range = 40.0
		add_child(l)
		l.global_position = C + dir * ly

	var mine := {
		"body": b, "dir": dir, "B": B, "cham_y": cham_y,
		"group": "mine_" + str(b.name), "res": res_id, "res_n": res_n,
		"color": ore_col, "count": ore_count,
	}
	_mines.append(mine)
	_spawn_chamber_ore(mine, ore_count)
	# no free furnace. bring your own machines.
	# exit drops you BESIDE the mouth, not back down the hole
	var out := Gate.new().configure({
		"target": C + dir * (R + 1.5) + B.x * 9.0, "zone": "",
		"label": "MINE EXIT", "color": Color("#ffe066")})
	add_child(out)
	out.global_transform = Transform3D(B, C + B * Vector3(0, cham_y - 5.5, -14))

func _mine_box(B: Basis, pos: Vector3, size: Vector3, c: Color, emit: float) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = Destructible.make_material(c, emit)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = size
	col.shape = cs
	body.add_child(col)
	add_child(body)
	body.global_transform = Transform3D(B, pos)

## Rich chamber ore for one mine (what it drops depends on the planet).
func _spawn_chamber_ore(m: Dictionary, n: int) -> void:
	var b = m["body"]
	var B: Basis = m["B"]
	var cham_y: float = m["cham_y"]
	for i in n:
		var ore := Destructible.new()
		var s := randf_range(1.4, 2.6)
		ore.setup(Vector3(s, s, s), m["color"], 2, 5, 1.8, 0.0, str(m["res"]), int(m["res_n"]))
		add_child(ore)
		var res_name := str(m["res"])
		(func() -> void:
			_dress_ore(ore, res_name, s)).call_deferred()
		ore.add_to_group(str(m["group"]))
		ore.add_to_group("mine_ore")
		ore.global_transform = Transform3D(B,
			b.center + B * Vector3(randf_range(-15, 15), cham_y - 5.5 + s * 0.5, randf_range(-15, 15)))

func _regen_ore(delta: float) -> void:
	_ore_t -= delta
	if _ore_t > 0.0:
		return
	_ore_t = 4.0
	for m in _mines:
		var cap := int(m.get("count", 26))
		var have := get_tree().get_nodes_in_group(str(m["group"])).size()
		if have < cap:
			_spawn_chamber_ore(m, mini(cap - have, 8))

func _arrow(pos: Vector3, up: Vector3, fwd: Vector3) -> void:
	var x := up.cross(fwd).normalized()
	var node := Node3D.new()
	add_child(node)
	node.global_transform = Transform3D(Basis(x, up, fwd).orthonormalized(), pos)
	var mat := Destructible.make_material(Color("#ffe066"), 4.0)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.12, 1.8)
	shaft.mesh = bm
	shaft.material_override = mat
	shaft.position = Vector3(0, 0, -0.2)
	node.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.6
	hm.height = 1.0
	hm.radial_segments = 4
	head.mesh = hm
	head.rotation_degrees = Vector3(90, 0, 0)   # point the cone along +Z
	head.position = Vector3(0, 0, 1.2)
	head.material_override = mat
	node.add_child(head)

func _spawn_invaders() -> void:
	# Deep-space voids, far from any planet (zero gravity out here).
	# a few fixed classics + a whole scattered fleet, everywhere you fly
	var spots: Array = [
		Vector3(0, 13000, 9000), Vector3(16000, 3000, -9000), Vector3(-11000, -13000, 7000),
	]
	for i in 22:
		var cand := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() \
			* randf_range(2500.0, 26000.0)
		var nb = Universe.nearest(cand)
		if cand.distance_to(nb.center) > nb.radius + 800.0:
			spots.append(cand)
	for s in spots:
		var inv := Invader.new()
		add_child(inv)
		inv.global_position = s
		inv.build(Color("#8cff5a"))
	# Clawde crabs -- valuable but breaking them angers the gods.
	for s in [Vector3(700, -300, 1200), Vector3(-900, 500, -600),
			Vector3(2200, 1400, -2600), Vector3(-2600, -1100, 2400)]:
		var crab := ClawdeCrab.new()
		add_child(crab)
		crab.global_position = s
		crab.build()

func _spawn_player_and_rocket() -> void:
	var home := Universe.body_named("Tutoria") if Game.tutorial_session \
		else Universe.body_named("Home")
	_player = Player.new()
	add_child(_player)
	_player.global_position = home.center + Vector3.UP * (home.radius + 2.0)
	if not Game.has_saved_spawn:   # a save may carry a beacon spawn already
		Game.set_spawn(_player.global_position, Vector3.UP)

	# No pre-placed rocket. It appears only once you BUY it (see _process).

	# a starter ATM near spawn
	var atm := ATM.new()
	add_child(atm)
	var adir := Vector3(-0.15, 1.0, 0.12).normalized()
	atm.global_transform = Transform3D(_basis_from_up(adir), home.center + adir * home.radius)

# ------------------------------------------------- LAN player avatars
## peer id -> {root, human, rocket_node, speed, jet, grounded, in_rocket}
var _remote_avatars: Dictionary = {}

## Build (or rebuild) a peer's avatar from their real character data:
## body color, shader skin, painted face, worn armor.
func _make_avatar(id: int) -> void:
	var keep_tf := Transform3D()
	var had := false
	if _remote_avatars.has(id) and is_instance_valid(_remote_avatars[id]["root"]):
		keep_tf = _remote_avatars[id]["root"].global_transform
		had = true
		_remote_avatars[id]["root"].queue_free()
	_remote_avatars.erase(id)
	_spawn_avatar(id)
	if had:
		_remote_avatars[id]["root"].global_transform = keep_tf

func _spawn_avatar(id: int) -> void:
	var info: Dictionary = Net.player_infos.get(id, {})
	var ch: Dictionary = info.get("character", {})
	var root := Node3D.new()
	add_child(root)
	var body := Human.new()
	root.add_child(body)
	var face: Texture2D = null
	var paint: PackedByteArray = info.get("paint", PackedByteArray())
	if paint.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(paint) == OK:
			face = ImageTexture.create_from_image(img)
	body.build(Color.html(str(ch.get("color", "3aa0ff"))), str(ch.get("shader", "none")), face,
		ch.get("fx", {}) if ch.get("fx", {}) is Dictionary else {})
	var eq = info.get("equip", null)
	if eq is Dictionary:
		body.dress(eq)
	var tag := Label3D.new()
	tag.text = str(Net.player_names.get(id, "dude"))
	tag.font_size = 26
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.4, 0)
	root.add_child(tag)
	# hitbox so weapons can land on them (friendly fire permitting)
	var hb := StaticBody3D.new()
	hb.set_meta("net_peer", id)
	hb.collision_layer = 2   # raycast-only: you can't stand on a player
	hb.collision_mask = 0
	var hbc := CollisionShape3D.new()
	var hcs := CapsuleShape3D.new()
	hcs.radius = 0.55
	hcs.height = 2.0
	hbc.shape = hcs
	hbc.position = Vector3(0, 1.0, 0)
	hb.add_child(hbc)
	root.add_child(hb)
	_remote_avatars[id] = {"root": root, "human": body, "rocket_node": null,
		"speed": 0.0, "jet": false, "grounded": true, "in_rocket": false}
	if OS.get_environment("CTD_NET") != "":
		print("NETTEST avatar spawned for peer ", id)

func _on_net_identity(id: int) -> void:
	_make_avatar(id)

func _on_net_punch(id: int) -> void:
	if _remote_avatars.has(id):
		var h = _remote_avatars[id]["human"]
		if is_instance_valid(h):
			h.punch()

func _on_net_pos(id: int, pos: Vector3, up: Vector3, fwd: Vector3, state: Dictionary) -> void:
	if not _remote_avatars.has(id) or not is_instance_valid(_remote_avatars[id]["root"]):
		_spawn_avatar(id)
	var e: Dictionary = _remote_avatars[id]
	var av: Node3D = e["root"]
	# death screen = gone from the world: burst once, hide until respawn
	if bool(state.get("dead", false)):
		if av.visible:
			Destructible.spawn_debris(self, pos + Vector3(0, 1, 0),
				Vector3(0.9, 1.8, 0.5), Color("#c04040"), Vector3.UP)
			Sfx.play("explode", -14.0)
			av.visible = false
		return
	av.visible = true
	e["jet"] = bool(state.get("jet", false))
	e["in_rocket"] = bool(state.get("rocket", false))
	# flying friends show as a rocket, not a floating body
	_sync_peer_rocket(e, id, bool(state.get("mk2", false)))
	# player origin = capsule CENTRE; the avatar model's origin is its FEET
	var foot := pos - up.normalized() * (0.0 if e["in_rocket"] else 1.0)
	var prev: Vector3 = av.global_position
	var x := up.cross(fwd)
	if x.length() > 0.001 and fwd.length() > 0.001:
		av.global_transform = Transform3D(
			Basis(x.normalized(), up.normalized(), -fwd.normalized()).orthonormalized(),
			prev.lerp(foot, 0.5) if prev.distance_to(foot) < 40.0 else foot)
	else:
		av.global_position = foot
	# walking speed from packet spacing (10 Hz), smoothed; grounded guess
	e["speed"] = lerpf(float(e["speed"]), prev.distance_to(av.global_position) * 10.0, 0.5)
	var b = Universe.nearest(pos)
	e["grounded"] = pos.distance_to(b.center) < b.radius + 2.2

## Everyone else's dudes actually LIVE: walk cycles, idle breathing,
## jetpack flames, tucked legs mid-air. Runs every frame, not per packet.
func _animate_avatars(delta: float) -> void:
	for id in _remote_avatars:
		var e: Dictionary = _remote_avatars[id]
		var h = e["human"]
		if not is_instance_valid(h):
			continue
		h.visible = not e["in_rocket"]
		if e["in_rocket"]:
			continue
		h.set_jetpack(e["jet"], e["jet"] and not e["grounded"])
		h.animate(float(e["speed"]), bool(e["grounded"]), delta,
			e["jet"] and not e["grounded"])

## While a peer flies, their avatar node carries a rocket model.
func _sync_peer_rocket(e: Dictionary, id: int, mk2: bool) -> void:
	var want: bool = e["in_rocket"]
	var node = e["rocket_node"]
	if want and (node == null or not is_instance_valid(node)):
		node = _build_peer_rocket(id, mk2)
		e["root"].add_child(node)
		e["rocket_node"] = node
	elif not want and node != null and is_instance_valid(node):
		node.queue_free()
		e["rocket_node"] = null

## Lightweight rocket lookalike: hull, cone, fins, engine glow. The body
## is a raycast-only collider so a friend can press F to hop on (mk2).
func _build_peer_rocket(id: int, mk2: bool) -> Node3D:
	var root := Node3D.new()
	var hull_col := Color("#7df9ff") if mk2 else Color("#d8d8e0")
	var hull := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.9
	hm.bottom_radius = 1.1
	hm.height = 5.0
	hull.mesh = hm
	hull.rotation_degrees = Vector3(-90, 0, 0)   # nose along -Z
	hull.material_override = Destructible.make_material(hull_col, 0.4)
	root.add_child(hull)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.9
	cm.height = 1.6
	cone.mesh = cm
	cone.rotation_degrees = Vector3(-90, 0, 0)
	cone.position = Vector3(0, 0, -3.3)
	cone.material_override = Destructible.make_material(Color("#ff5964"), 0.6)
	root.add_child(cone)
	for ang in [0.0, 120.0, 240.0]:
		var fin := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.12, 1.2, 1.4)
		fin.mesh = fm
		var a := deg_to_rad(ang)
		fin.position = Vector3(cos(a) * 1.1, sin(a) * 1.1, 2.0)
		fin.rotation_degrees = Vector3(0, 0, ang)
		fin.material_override = Destructible.make_material(hull_col.darkened(0.3), 0.2)
		root.add_child(fin)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.7
	gm.height = 1.4
	glow.mesh = gm
	glow.position = Vector3(0, 0, 2.8)
	glow.material_override = Destructible.make_material(Color("#ffb347"), 3.0)
	root.add_child(glow)
	var body := StaticBody3D.new()
	body.set_meta("net_pilot", id)
	body.set_meta("net_mk2", mk2)
	body.collision_layer = 2
	body.collision_mask = 0
	var bc := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 1.3
	cs.height = 6.5
	bc.shape = cs
	bc.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(bc)
	root.add_child(body)
	return root

func _on_net_left(id: int) -> void:
	if _remote_avatars.has(id):
		if is_instance_valid(_remote_avatars[id]["root"]):
			_remote_avatars[id]["root"].queue_free()
		_remote_avatars.erase(id)

## Another peer placed something: mirror it into this world.
func net_place(pid: String, pos: Vector3, up: Vector3) -> void:
	var n := _spawn_world_obj(pid)
	if n == null:
		return
	add_child(n)
	n.set_meta("placed_id", pid)
	n.set_meta("owner", Net.remote_owner)
	if n is Rocket:
		var z := -up
		var x := up.cross(Vector3(0, 1, 0))
		if x.length() < 0.01:
			x = up.cross(Vector3(1, 0, 0))
		x = x.normalized()
		n.global_transform = Transform3D(Basis(x, z.cross(x).normalized(), z).orthonormalized(), pos)
	else:
		n.global_transform = Transform3D(_basis_from_up(up), pos)

## Another peer removed a placed thing near this position: mirror, silently
## (no refund here -- the peer who broke it got that).
func net_remove(pos: Vector3) -> void:
	for grp in ["machine", "rocket", "waypoint", "spawn"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D and is_instance_valid(n) \
					and n.global_position.distance_to(pos) < 1.2:
				Destructible.spawn_debris(self, n.global_position,
					Vector3(1.0, 1.0, 1.0), Color("#8890a0"), Vector3.UP)
				n.queue_free()
				return

## Another peer smashed a destructible near this position: mirror, without
## paying out resources twice.
func net_break(pos: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("destructible"):
		if n is Destructible and is_instance_valid(n) \
				and n.global_position.distance_to(pos) < 1.0:
			n.net_destroy()
			return

# -------------------------------------------------- world persistence

## Serialize every PLAYER-PLACED thing (machines, chests, beacons,
## parked rockets) including contents, energy, scripts, and the wire
## graph (as indices into this same list).
func collect_world() -> Array:
	var nodes: Array = []
	for grp in ["machine", "chest", "spawn", "autominer", "rocket", "waypoint", "itemdrop", "bench", "nterm", "house"]:
		for n in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n) and (n.has_meta("placed_id") or n is ItemDrop) and not nodes.has(n):
				if n is Rocket and n.piloted:
					continue   # in-flight rocket saves via its own path
				nodes.append(n)
	var idx := {}
	for i in nodes.size():
		idx[nodes[i]] = i
	var out: Array = []
	out.append_array(_unrestored)   # data we couldn't spawn survives untouched
	for n in nodes:
		var up: Vector3 = n.global_transform.basis.y
		if n is Rocket:
			up = -n.global_transform.basis.z   # nose = surface up for rockets
		if n is ItemDrop:
			out.append({"id": "itemdrop", "drop_id": n.id, "n": n.count,
				"pos": [n.global_position.x, n.global_position.y, n.global_position.z],
				"up": [up.x, up.y, up.z]})
			continue
		var e := {
			"id": str(n.get_meta("placed_id")),
			"pos": [n.global_position.x, n.global_position.y, n.global_position.z],
			"up": [up.x, up.y, up.z],
			"owner": str(n.get_meta("owner", "")),
		}
		if n is Machine:
			e["buf"] = n.buf
			e["slot_in"] = n.in_slot
			e["slot_out"] = n.out_slot
			var wo: Array = []
			for k in n.wires_out.size():
				var w = n.wires_out[k]
				if w is Machine.CoilNode and is_instance_valid(w) and idx.has(w.host):
					wo.append([idx[w.host], -1])   # -1 = "that machine's coil"
				elif idx.has(w):
					wo.append([idx[w], int(n.wire_ports[k]) if k < n.wire_ports.size() else k + 1])
			var fo: Array = []
			for k2 in n.funnels_out.size():
				var f = n.funnels_out[k2]
				if idx.has(f):
					fo.append([idx[f], int(n.funnel_ports[k2]) if k2 < n.funnel_ports.size() else k2 + 1])
			e["wires"] = wo
			e["funnels"] = fo
			e["coil"] = n.has_coil
			if "tname" in n:
				e["tname"] = n.tname
			if "on" in n:
				e["sw_on"] = n.on
			if "script_src" in n:
				e["script"] = n.script_src
		if n is Chest:
			e["storage"] = n.storage
		if n is House:
			e["kind"] = n.kind
			e["hslot"] = n.slot
			e["hh"] = n.human_home
			e["howner"] = n.owner_uid
			e["howner_n"] = n.owner_name
			e["hroom_n"] = n.roommate_name
			e["hoff"] = [n.room_offset.x, n.room_offset.y, n.room_offset.z]
			e["hlinks"] = n.links.duplicate()
			# yaw relative to the restore basis: docked/ring stations kept
			# rotating on rejoin because only 'up' survived the save
			var hrefb: Basis = _basis_from_up(up)
			var hzz: Vector3 = hrefb.inverse() * n.global_transform.basis.z
			e["hyaw"] = atan2(hzz.x, hzz.z)
			# the FULL forward too: near the poles _basis_from_up's
			# reference axis flips on float rounding and hyaw replays in
			# the wrong frame -- hfwd needs no reference at all
			var hbz: Vector3 = n.global_transform.basis.z
			e["hfwd"] = [hbz.x, hbz.y, hbz.z]
		if n is Furniture:
			e["fkind"] = n.kind
			# ACTUAL orientation, as yaw relative to the restore basis --
			# rejoining used to randomize it and doorframes went sideways
			var refb: Basis = _basis_from_up(up)
			var zz: Vector3 = refb.inverse() * n.global_transform.basis.z
			e["fyaw"] = atan2(zz.x, zz.z)
		if n is RadioTower:
			e["rfreq"] = n.freq
			e["raim"] = [n.aim_dir.x, n.aim_dir.y, n.aim_dir.z]
			e["rtrack"] = "@noodle" if n.track_node != null \
				else (str(n.track_body.name) if n.track_body != null else "")
		if n is Waypoint:
			e["wcol"] = n.col_i
			e["won"] = n.enabled
		if n is Rocket:
			e["hyper"] = n.hyperdrive
		out.append(e)
	# the census: every living human rides the world save -- same souls
	# on rejoin, same grudges, same shirts
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h is EarthHuman and is_instance_valid(h) and not h._dead:
			out.append({"id": "human",
				"pos": [h.global_position.x, h.global_position.y, h.global_position.z],
				"data": h.capture()})
	return out

var _world_load_ok := false   # only a CLEAN restore may overwrite the save
var _unrestored: Array = []   # entries we couldn't spawn: carried forward, never deleted

func restore_world() -> void:
	_world_load_ok = false
	_unrestored = []
	var entries := Save.saved_world()
	var made: Array = []
	# a saved census replaces the freshly generated population wholesale
	var has_census := false
	for e0 in entries:
		if e0 is Dictionary and str(e0.get("id", "")) == "human":
			has_census = true
			break
	if has_census:
		for h0 in get_tree().get_nodes_in_group("earth_human"):
			h0.queue_free()
	for e in entries:
		if str(e.get("id", "")) == "human":
			var hm := EarthHuman.new()
			hm.saved = e.get("data", {})
			var hp4 = e.get("pos", [0, 0, 0])
			var hpos := Vector3(float(hp4[0]), float(hp4[1]), float(hp4[2]))
			hm.setup(Universe.nearest(hpos))
			add_child(hm)
			var hup := (hpos - Universe.nearest(hpos).center).normalized()
			hm.global_transform = Transform3D(_basis_from_up(hup), hpos)
			made.append(hm)
			continue
		var n := _spawn_world_obj(str(e.get("id", "")))
		made.append(n)
		if n == null:
			_unrestored.append(e)   # unknown/broken id: keep its data verbatim
			continue
		if n is ItemDrop:
			n.setup(str(e.get("drop_id", "coal")), int(e.get("n", 1)))
		if n is House:
			n.kind = str(e.get("kind", "small"))
			n.slot = int(e.get("hslot", -1))
			n.human_home = bool(e.get("hh", false))
			n.owner_uid = int(e.get("howner", 0))
			n.owner_name = str(e.get("howner_n", ""))
			n.roommate_name = str(e.get("hroom_n", ""))
			var ho = e.get("hoff", [0, 0, 0])
			n.room_offset = Vector3(float(ho[0]), float(ho[1]), float(ho[2]))
			for lv in e.get("hlinks", []):
				n.links.append(int(lv))
		if n is Furniture:
			n.kind = str(e.get("fkind", "bench"))
		if n is RadioTower:
			n.freq = float(e.get("rfreq", 98.0))
			var ra = e.get("raim", [0, 1, 0])
			n.aim_dir = Vector3(float(ra[0]), float(ra[1]), float(ra[2])).normalized()
			var rtn := str(e.get("rtrack", ""))
			if rtn == "@noodle":
				var nw = get_tree().get_first_node_in_group("noodle_watcher")
				if nw != null and nw is Node3D:
					n.track_node = nw
			elif rtn != "":
				n.track_body = Universe.body_named(rtn)
		if n is Waypoint:
			n.col_i = int(e.get("wcol", 0))
			n.enabled = bool(e.get("won", true))
		add_child(n)
		n.set_meta("placed_id", e["id"])
		n.set_meta("owner", str(e.get("owner", "")))
		var p = e.get("pos", [0, 0, 0])
		var u = e.get("up", [0, 1, 0])
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var up := Vector3(float(u[0]), float(u[1]), float(u[2])).normalized()
		if n is Rocket:
			var z := -up
			var x := up.cross(Vector3(0, 1, 0))
			if x.length() < 0.01:
				x = up.cross(Vector3(1, 0, 0))
			x = x.normalized()
			n.global_transform = Transform3D(Basis(x, z.cross(x).normalized(), z).orthonormalized(), pos)
			n.hyperdrive = bool(e.get("hyper", false))
		else:
			n.global_transform = Transform3D(_basis_from_up(up), pos)
			if n is Furniture:
				n.rotate_object_local(Vector3.UP, float(e.get("fyaw", 0.0)))
			if n is House:
				var hf = e.get("hfwd", null)
				var fz := Vector3.ZERO
				if hf is Array and hf.size() == 3:
					fz = Vector3(float(hf[0]), float(hf[1]), float(hf[2]))
					fz = (fz - up * fz.dot(up)).normalized()
				if fz.length() > 0.5:
					n.global_transform = Transform3D(
						Basis(up.cross(fz).normalized(), up, fz).orthonormalized(), pos)
				else:
					n.rotate_object_local(Vector3.UP, float(e.get("hyaw", 0.0)))
		if n is Machine:
			n.buf = float(e.get("buf", 0.0))
			var si = e.get("slot_in", null)
			if si is Dictionary:
				n.in_slot = {"id": str(si.get("id", "")), "n": int(si.get("n", 0))}
			var so = e.get("slot_out", null)
			if so is Dictionary:
				n.out_slot = {"id": str(so.get("id", "")), "n": int(so.get("n", 0))}
			if "script_src" in n and e.has("script"):
				n.script_src = str(e["script"])
			if bool(e.get("coil", false)):
				n.add_coil()
			if e.has("tname") and "tname" in n:
				n.tname = str(e["tname"])
			if e.has("sw_on") and "on" in n:
				n.on = bool(e["sw_on"])
				if n.has_method("_apply_visual"):
					n._apply_visual()
				if n.has_method("_refresh_state_lbl"):
					n._refresh_state_lbl()
		if n is Chest and e.has("storage"):
			n.storage = Save.parse_slots(e["storage"], 20)
	# second pass: rebuild the wire graph (visual arrows included)
	for i in entries.size():
		var n2 = made[i]
		if n2 == null or not n2 is Machine:
			continue
		for wi in entries[i].get("wires", []):
			var widx: int = int(wi[0]) if wi is Array else int(wi)
			var wport: int = int(wi[1]) if wi is Array and wi.size() > 1 else 0
			var dst = made[widx] if widx < made.size() else null
			if dst != null and wport == -1 and dst is Machine and dst.coil_node != null:
				n2.connect_wire(dst.coil_node, "power", 0)
			elif dst != null:
				n2.connect_wire(dst, "power", wport)
		for fi in entries[i].get("funnels", []):
			var fidx: int = int(fi[0]) if fi is Array else int(fi)
			var fport: int = int(fi[1]) if fi is Array and fi.size() > 1 else 0
			var dst2 = made[fidx] if fidx < made.size() else null
			if dst2 != null:
				n2.connect_wire(dst2, "item", fport)
	_world_load_ok = true   # reached the end: this session may save the world

func _spawn_world_obj(id: String) -> Node3D:
	match id:
		"chest": return Chest.new()
		"spawnbeacon": return SpawnBeacon.new()
		"furnace": return Furnace.new()
		"coinifier": return Coinifier.new()
		"autominer": return AutoMiner.new()
		"generator": return EMachines.Generator.new()
		"coaldrill": return EMachines.CoalDrill.new()
		"bioreactor": return EMachines.Bioreactor.new()
		"rtg": return EMachines.RTG.new()
		"prisreactor": return EMachines.PrismReactor.new()
		"teleporter": return EMachines.Teleporter.new()
		"extender": return EMachines.Extender.new()
		"itemdrop": return ItemDrop.new()
		"waypoint": return Waypoint.new()
		"capacitor": return EMachines.Capacitor.new()
		"efurnace": return EMachines.EFurnace.new()
		"eseller": return EMachines.ESeller.new()
		"atm": return ATM.new()
		"ecomputer": return Computers.EComputer.new()
		"scomputer": return Computers.SorterComputer.new()
		"ultracap": return EMachines.UltraCapacitor.new()
		"elight": return EMachines.ELight.new()
		"switch": return EMachines.Switch.new()
		"lightbox": return EMachines.LightBox.new()
		"bench":
			var bn := Bench.new()
			return bn
		"nterm": return NeuralinkTerminal.new()
		"radio": return RadioTower.new()
		"house": return House.new()
		"furn": return Furniture.new()
		"chairseat":
			var cn := Bench.new()
			cn.is_bench = false
			return cn
		"nreactor": return EMachines.NuclearReactor.new()
		"rocket": return Rocket.new()
		"rocket2":
			var r2 := Rocket.new()
			r2.mk2 = true
			return r2
	return null

# --------------------------------------------------------------- animals

var _caged: Array = []   # actual Animal nodes riding along in cages

func stash_animal(a: Animal) -> void:
	_caged.append(a)

func unstash_animal() -> Animal:
	while not _caged.is_empty():
		var a = _caged.pop_back()
		if is_instance_valid(a):
			return a
	return null

# ------------------------------------------------------------ the temple

## Maze beaten: the button crumbles, a REAL doorway opens in the temple
## base. Walk into the dark opening -> you're inside (bigger inside).
func open_temple_door() -> void:
	if _temple_opened:
		return
	_temple_opened = true
	if _temple_btn and is_instance_valid(_temple_btn):
		_temple_btn.queue_free()
	# the dark opening
	var mouth := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(2.2, 3.0, 0.5)
	mouth.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.01, 0.01, 0.02)
	mouth.material_override = mat
	add_child(mouth)
	mouth.global_transform = Transform3D(_temple_B, _temple_np + _temple_B * Vector3(0, 1.5, 4.05))
	# walking into it teleports you inside -- seamless, no key needed
	var zone := Area3D.new()
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(1.8, 2.6, 1.4)
	col.shape = cs
	zone.add_child(col)
	add_child(zone)
	zone.global_transform = Transform3D(_temple_B, _temple_np + _temple_B * Vector3(0, 1.3, 4.5))
	zone.body_entered.connect(_temple_door_entered)

## Teleport DEFERRED: moving the body inside the area callback upsets
## the physics server (Jolt "ref_count" flush errors).
func _temple_door_entered(bdy: Node3D) -> void:
	if bdy is Player and Game.mode == Game.Mode.ON_FOOT:
		_temple_teleport.call_deferred(bdy)

func _temple_teleport(bdy: Node3D) -> void:
	if not is_instance_valid(bdy) or Game.mode != Game.Mode.ON_FOOT:
		return
	Game.zone = "flat"
	Game.zone_g = 9.0
	bdy.respawn_at(Zones.temple_spawn(), Vector3.UP)
	Sfx.play("warp")
	if _hud:
		_hud.flash("it is bigger on the inside")
	# the hall wakes up 2 seconds after you step in
	if not _trials_started:
		get_tree().create_timer(2.0).timeout.connect(start_trials)

## Trial button inside the hall: NOW the pyramids come. Never on top of you.
## Wrath maxed: spawn the descending noodle god above the player.
## Max wrath: no chasing monster anymore. JUDGMENT comes from the sky --
## the watcher's own tendril takes you. Appease below 40 before it
## closes and it lets go.
func noodle_wrath_event() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		Game.wrath_event_over(true)
		return
	var j := NoodleWatcher.JudgmentFx.new()
	j.target = p
	add_child(j)
	j.global_position = p.global_position
	Sfx.play_at("rumble", p.global_position, 8.0)

## Every mine entrance in the universe (for the locator).
func mine_positions() -> Array:
	var out: Array = []
	for pname in MINE_DIRS:
		var b = Universe.body_named(pname)
		if b != null:
			out.append(b.center + MINE_DIRS[pname].normalized() * b.radius)
	return out

func start_trials() -> void:
	if _trials_started:
		return
	_trials_started = true
	var dummy = Universe.make_flat_body(Zones.TEMPLE_POS)
	var ppos := _player.global_position if _player else Zones.TEMPLE_POS
	var spawned := 0
	var tries := 0
	while spawned < 5 and tries < 60:
		tries += 1
		var cand: Vector3 = Zones.TEMPLE_POS + Vector3(randf_range(-45, 45), -12.0, randf_range(-45, 45))
		if cand.distance_to(ppos) < 18.0:
			continue   # NOT inside the player. ever.
		var e := Enemy.new()
		e.setup(4, dummy, true, spawned % 3 == 2)   # every 3rd: green TANK
		add_child(e)
		e.global_position = cand
		spawned += 1
	Sfx.play("warp", -6.0)
	if _hud:
		_hud.flash("THE TRIAL BEGINS")

## Cheat: drag the trader here, whatever day it is. He is not happy.
func summon_ufo() -> void:
	if _ufo and is_instance_valid(_ufo):
		_ufo.queue_free()
	_ufo = UFO.new()
	add_child(_ufo)
	var pos := _active_pos()
	var up := Universe.surface_up(Universe.nearest(pos), pos)
	_ufo.global_position = pos + up * 60.0 + Vector3(40, 0, 0)
	if _hud:
		_hud.flash("the saucer arrives, annoyed. \"this isn't tuesday.\"")
	Sfx.play("warp")

# ---------------------------------------------------------- rifts + time

func _spawn_rifts() -> void:
	# OFF the main travel lanes -- you should find these, not trip on them.
	_rifts = [
		Vector3(1500, 2400, -1800), Vector3(-2800, -2200, 3400),
		Vector3(5200, 3800, -5600), Vector3(-6500, 1500, -7000),
	]
	# INVISIBLE space-warp: a big bubble that bends whatever is behind it.
	# No rim, no glow. You spot it by the stars smearing. Good luck.
	var wsh := Shader.new()
	wsh.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 nv = normalize(NORMAL);
	float edge = 1.0 - abs(dot(nv, normalize(-VERTEX)));
	vec2 off = nv.xy * 0.10 * (0.35 + edge) + vec2(sin(TIME * 0.7 + VERTEX.y * 0.2), cos(TIME * 0.5 + VERTEX.x * 0.2)) * 0.012;
	ALBEDO = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999))).rgb;
}
"""
	for r in _rifts:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 28.0
		sm.height = 56.0
		sm.radial_segments = 48
		sm.rings = 32
		mi.mesh = sm
		var wmat := ShaderMaterial.new()
		wmat.shader = wsh
		mi.material_override = wmat
		add_child(mi)
		mi.global_position = r

func _make_snapshot(pos: Vector3) -> Dictionary:
	return {
		"t": Game.playtime,
		"pos": [pos.x, pos.y, pos.z],
		"coins": Inventory.coins,
		"health": Game.health,
		"wrath": Game.wrath,
		"score": Game.score,
		"fuel": Inventory.fuel,
		"jet": Inventory.jet_fuel,
		"hotbar": Inventory.hotbar.duplicate(true),
		"backpack": Inventory.backpack_store.duplicate(true),
	}

func _enter_rift() -> void:
	if Save.snaps.is_empty():
		_rift_cd = 5.0
		if _hud:
			_hud.flash("the rift has no past to return you to yet")
		return
	_rift_cd = 20.0
	# 5 minutes back if we have it, else the oldest we know
	var chosen: Dictionary = Save.snaps[0]
	for s in Save.snaps:
		if float(s["t"]) <= Game.playtime - 300.0:
			chosen = s
	var p = chosen["pos"]
	var target := Vector3(float(p[0]), float(p[1]), float(p[2]))
	Inventory.coins = int(chosen["coins"])
	Game.health = float(chosen["health"])
	Game.wrath = float(chosen["wrath"])
	Game.score = int(chosen["score"])
	Inventory.fuel = float(chosen["fuel"])
	Inventory.jet_fuel = float(chosen["jet"])
	var hb = chosen["hotbar"]
	if hb is Array and hb.size() == 5:
		Inventory.hotbar = Save.parse_slots(hb, 5)
	var bp = chosen.get("backpack", [])
	if bp is Array and not bp.is_empty():
		Inventory.backpack_store = Save.parse_slots(bp, 20)
	Save.snaps.clear()   # the past resets; rifting again won't take you far
	var node := _active_node()
	if node is Rocket:
		node.global_position = target
		node.vel = Vector3.ZERO
	if _player:
		_player.global_position = target
		_player.velocity = Vector3.ZERO
	Sfx.play("warp", -2.0)
	if _hud:
		_hud.flash("the rift takes you. this already happened.")
	Inventory.changed.emit()
	Game.changed.emit()

# -------------------------------------------------------------- starship

func _spawn_starship() -> void:
	var ship := Starship.new()
	add_child(ship)
	ship.global_position = Vector3(1500, 700, 2200)
	ship.rotation_degrees = Vector3(20, 40, 65)   # derelict tilt

# --------------------------------------------------------------- helpers

func _surface_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _basis_from_up(up: Vector3) -> Basis:
	var t := Vector3(0, 1, 0)
	if absf(up.dot(t)) > 0.99:
		t = Vector3(1, 0, 0)
	var x := t.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).orthonormalized()
