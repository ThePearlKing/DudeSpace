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
## Deep space, well clear of Home's well: no gravity, no horizon, perfect
## line of sight to everything.
## Out past the shader system, high above the plane and further out
## than anything else: the front edge of the universe, where there is
## nothing left between the array and everywhere else.
const NEXUS_POS := Vector3(600.0, 9200.0, -33000.0)
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
	"Mercury": Vector3(0.4, 0.6, 0.7).normalized(),
	"Mars": Vector3(-0.7, 0.4, -0.6).normalized(),
	"Extroma": Vector3(0.5, -0.6, 0.6).normalized(),
	"Xero": Vector3(-0.4, 0.7, 0.6).normalized(),
	"Tutoria": Tutorial.ORE_DIR.normalized(),   # the tutorial's teaching mine
}
var _dens: float = 1.0   # spawn-density multiplier (bscale worlds)

## The icosahedron apartment colonies bore into the BIGGEST shader
## planets. One mouth each; the tunnels do the rest.
var COLONY_DIRS := {
	"Wireframe": Vector3(0.5, 0.6, -0.62).normalized(),
	"Datamosh": Vector3(0.7, -0.5, 0.5).normalized(),
	# Pixel's dir is EXACTLY a sphere-mesh quad center: the 4.8m cut takes
	# that quad's two triangles and nothing else -- a clean square-ish
	# hole barely bigger than the shaft, very Pixel
	"Pixel": Vector3(-0.5646, 0.5163, 0.6439).normalized(),
}
# roll of the whole colony around its mouth axis, degrees -- used to
# line the square entrance up with the planet-mesh facets it cuts
var COLONY_ROLLS := {"Pixel": 59.5}
# the Mainframe facility's mouth (same porthole kit as colonies/mines)
var MAINFRAME_DIR := Vector3(0.35, 0.75, 0.56).normalized()

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

var _load_bar: ProgressBar = null
var _load_lbl: Label = null
var _load_layer: CanvasLayer = null

func _load_set(f: float, txt: String) -> void:
	if _load_bar != null:
		_load_bar.value = f * 100.0
		_load_lbl.text = txt
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	# LOADING SCREEN first: the world build is heavy and the bar below
	# is real -- each phase reports as it finishes
	_load_layer = CanvasLayer.new()
	_load_layer.layer = 99
	add_child(_load_layer)
	var ldim := ColorRect.new()
	ldim.color = Color("#05070c")
	ldim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_layer.add_child(ldim)
	var lbox := VBoxContainer.new()
	lbox.set_anchors_preset(Control.PRESET_CENTER)
	lbox.custom_minimum_size = Vector2(480, 120)
	lbox.position = Vector2(-240, -60)
	lbox.add_theme_constant_override("separation", 14)
	_load_layer.add_child(lbox)
	var lt := Label.new()
	lt.text = "LOADING WORLD"
	lt.add_theme_font_size_override("font_size", 30)
	lt.modulate = Color("#ffb000")
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbox.add_child(lt)
	_load_bar = ProgressBar.new()
	_load_bar.custom_minimum_size = Vector2(480, 26)
	_load_bar.show_percentage = false
	lbox.add_child(_load_bar)
	_load_lbl = Label.new()
	_load_lbl.text = ""
	_load_lbl.add_theme_font_size_override("font_size", 15)
	_load_lbl.modulate = Color(1, 1, 1, 0.65)
	_load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbox.add_child(_load_lbl)
	_boot()

func _boot() -> void:
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
	await _load_set(0.02, "environment")
	_setup_environment()
	_setup_light()
	_crater_spots.clear()
	var bnum := 0
	for b in Universe.bodies:
		_build_body(b)
		bnum += 1
		if bnum % 4 == 0:
			await _load_set(0.02 + 0.42 * float(bnum)
				/ float(Universe.bodies.size()),
				"planets: %s" % str(b.name))
	_build_boundary()
	await _load_set(0.46, "life support")
	if not Game.tutorial_session:
		_spawn_invaders()
	_spawn_player_and_rocket()

	if not Game.tutorial_session:
		Zones.build_shadow_temple(self, Universe.make_flat_body(Zones.SHADOW_POS))
		_spawn_rifts()
		_c4 = Connect4.new()
		_c4.add_to_group("connect4")
		add_child(_c4)
		_c4.global_position = C4_POS

	await _load_set(0.52, "temples and anomalies")
	if not Game.tutorial_session:
		add_child(NoodleWatcher.new())   # the god is ALWAYS watching
	add_child(DatamoshStudio.new())  # the DATAMOSH station: hole, mast, studio
	if not Game.tutorial_session:
		# icosahedron apartment colonies inside the big shader planets
		for cname in COLONY_DIRS:
			var cb = Universe.body_named(str(cname))
			if cb != null:
				await _load_set(0.56 + 0.05 * float(["Wireframe", "Datamosh",
					"Pixel"].find(str(cname))), "colony: %s" % str(cname))
				var col9 := IcosaColony.new()
				add_child(col9)
				col9.build(cb, COLONY_DIRS[cname],
					float(COLONY_ROLLS.get(cname, 0.0)))
		# the Mainframe facility: dude-built, automated, nobody home
		var mfb = Universe.body_named("Big Computer")
		if mfb != null:
			await _load_set(0.72, "BIG COMPUTER facility")
			var mfc := MainframeComplex.new()
			add_child(mfc)
			mfc.build(mfb, MAINFRAME_DIR)
	# the EARTH monolith: link 1. Buried until Harold's stone is fed;
	# already risen on saves past that point.
	var eb9 = Universe.body_named("Earth")
	if eb9 != null and not Game.tutorial_session:
		_earth_monolith = Monolith.new()
		add_child(_earth_monolith)
		_earth_monolith.stage = 1
		_earth_monolith.risen = Game.monolith_stage >= 1
		_build_monument(eb9, Vector3(0.3, 0.8, -0.52).normalized(),
			_earth_monolith)
		if not _earth_monolith.risen:
			_earth_monolith._root.global_position = \
				(eb9.center as Vector3) + _earth_monolith.dir \
				* (float(eb9.radius) - Monolith.RISE_DEPTH)
	# THE REST OF THE CHAIN: every remaining stele EXISTS on its planet
	# now -- identical monuments, buried until their turn. There is no
	# way to get their tetrahedra yet; the crowns wear placeholders.
	var chain_dirs := {
		"Euclid": Vector3(0.9, 0.1, 0.42),
		"Undros": Vector3(0.3, 0.8, 0.5),
		"Mars": Vector3(0.2, 0.75, -0.6),
		"Wobble": Vector3(-0.5, 0.6, 0.6),
		"Crystalia": Vector3(0.6, 0.5, -0.6),
		"Requiem": Vector3(0, 1, 0),
	}
	for st9 in range(2, 8):
		var pname9: String = Game.MONO_PLANETS[st9]
		var pb9 = Universe.body_named(pname9)
		if pb9 == null or not chain_dirs.has(pname9):
			continue
		var mono9 := Monolith.new()
		add_child(mono9)
		mono9.stage = st9
		mono9.risen = Game.monolith_stage >= st9
		_build_monument(pb9, (chain_dirs[pname9] as Vector3).normalized(),
			mono9)
		mono9.add_to_group("chain_stele")
		if not mono9.risen:
			mono9._root.global_position = (pb9.center as Vector3) \
				+ mono9.dir * (float(pb9.radius) - Monolith.RISE_DEPTH)
	# TIN 618 hums across space: you hear it long before you see it,
	# and well past Harold's orbit distance
	var bhb2 = Universe.body_named("TIN 618")
	if bhb2 != null:
		var bhum := AudioStreamPlayer3D.new()
		bhum.stream = RadioLib.bh_presence()   # deeper, godlier than the broadcast
		bhum.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		bhum.unit_size = 2600.0
		bhum.max_distance = 30000.0
		bhum.max_db = 0.0
		bhum.volume_db = -4.5
		add_child(bhum)
		bhum.global_position = bhb2.center
		bhum.play()

	# BACKGROUND MUSIC: the user's own tracks (res://music) drift in and
	# out while you're out in the world -- a soundtrack, not a station
	if RadioLib.custom_count() > 0:
		_bgm = AudioStreamPlayer.new()
		_bgm.volume_db = -8.0
		add_child(_bgm)
		_bgm_gap = randf_range(20.0, 60.0)   # the FIRST song finds you quickly

	await _load_set(0.9, "interface")
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

	await _load_set(0.95, "restoring your world")
	Game.reset()
	Save.apply_progress()   # restore this slot's run (no-op on a fresh slot)
	# the monolith chain state arrives AFTER the world built: snap the
	# steles and repaint the tracker triangles to match the save
	_monolith_snap()
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
	if OS.get_environment("CTD_TEST") == "21":
		_nuke_test()
	if OS.get_environment("CTD_TEST") == "22":
		_dish_test()
	if OS.get_environment("CTD_TEST") == "24":
		_colony_test()
	if OS.get_environment("CTD_TEST") == "25":
		_mouth_shot_test()
	if OS.get_environment("CTD_TEST") == "26":
		_mainframe_test()
	if OS.get_environment("CTD_TEST") == "27":
		_synth_test()
	if OS.get_environment("CTD_TEST") == "28":
		_readme_shots()
	if OS.get_environment("CTD_TEST") == "29":
		_hole_shot()
	if OS.get_environment("CTD_TEST") == "30":
		_edge_shots()
	if OS.get_environment("CTD_LOAD") != "":
		_savedoctor_report()
	if OS.get_environment("CTD_TEST") == "42":
		_synthsound_test()
	if OS.get_environment("CTD_TEST") == "41":
		_broadcast_test()
	if OS.get_environment("CTD_TEST") == "46":
		_icons_test()
	if OS.get_environment("CTD_TEST") == "47":
		_gravity_demo()
	if OS.get_environment("CTD_TEST") == "45":
		_ambient_test()
	if OS.get_environment("CTD_TEST") == "44":
		_reload_test()
	if OS.get_environment("CTD_TEST") == "53":
		_panel_audit()
	if OS.get_environment("CTD_TEST") == "52":
		_reverb_test()
	if OS.get_environment("CTD_TEST") == "51":
		_mystery_jack_test()
	if OS.get_environment("CTD_TEST") == "50":
		_gasgiant_shots()
	if OS.get_environment("CTD_TEST") == "48":
		_advtut_test()
	if OS.get_environment("CTD_TEST") == "43":
		_chem_test()
	if OS.get_environment("CTD_TEST") == "54":
		_arcade_test()
	if OS.get_environment("CTD_TEST") == "55":
		_arcade_shots()
	if OS.get_environment("CTD_TEST") == "40":
		_factory_test()
	if OS.get_environment("CTD_TEST") == "31":
		_savewipe_test()
	if OS.get_environment("CTD_TEST") == "32":
		_throat_shot()
	if OS.get_environment("CTD_TEST") == "39":
		_forktv_shot()
	if OS.get_environment("CTD_TEST") == "36":
		_skyshow_test()
	if OS.get_environment("CTD_TEST") == "37":
		_shatter_test()
	if OS.get_environment("CTD_TEST") == "38":
		_shatter_shot()
	if OS.get_environment("CTD_TEST") == "33":
		_harold_test()
	if OS.get_environment("CTD_TEST") == "34":
		_riddle_shot()
	# the interactive tutorial lives ONLY in the dedicated tutorial world
	if Game.tutorial_session and OS.get_environment("CTD_TEST") == "" \
			and OS.get_environment("CTD_NET") == "":
		if Game.tutorial_mode == "reactor":
			add_child(ReactorTutorial.new())
		elif Game.tutorial_mode == "advanced":
			add_child(AdvancedTutorial.new())
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
	_lod_sweep()
	await _load_set(1.0, "done")
	if _load_layer != null:
		_load_layer.queue_free()
		_load_layer = null
		_load_bar = null
		_load_lbl = null
		# NOW the window is real: take the mouse
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		# RESCUE: saved inside a pocket interior that no longer contains
		# that spot (a secret wing that moved, a demolished room) --
		# instead of waking sealed in the void, wake at the nearest
		# house door, or failing that at spawn
		if Game.zone == "flat":
			var best9 := 1.0e18
			var host9: Node = null
			for hn9 in get_tree().get_nodes_in_group("house"):
				if hn9 is House:
					var d9: float = sp.distance_to((hn9 as House).room_center())
					if d9 < best9:
						best9 = d9
						host9 = hn9
			if host9 == null or best9 > 60.0:
				if host9 != null and best9 < 220.0:
					_player.global_position = (host9 as House).interior_spawn()
				else:
					Game.zone = ""
					_player.global_position = Game.spawn_pos \
						+ Game.spawn_up * 1.5
		if Save.was_in_rocket():
			var rk := Rocket.new()
			rk.mk2 = Save.was_mk2()   # a 2.0 comes back AS a 2.0
			# without this meta the rocket would never save again once parked
			rk.set_meta("placed_id", "rocket2" if rk.mk2 else "rocket")
			add_child(rk)
			rk.global_position = sp
			rk.hyperdrive = Save.was_hyper()
			rk.board(_player)
			# the TRAJECTORY survives the rejoin: same velocity, same
			# orbit, same arc you logged out on
			rk.vel = Save.rocket_vel()
			rk.hyper_charge = Save.hyper_charge()
			rk.nuclear = Save.was_nuclear()
			rk.edge_won = Save.edge_won()

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
## CTD_TEST=21: force a meltdown next to the player, die, and report
## WHICH camera is live + where it looks for the funeral shot.
## CTD_TEST=22: watch a freshly-restored radio's dish for the startup
## ratchet -- sample a rim point at 50ms and print every jump.
## CTD_TEST=24: geometric connectivity probes for the icosahedron
## colony on Wireframe. Rays prove the drop path, both rings, the
## catch floor and leak-tightness of the crossing chamber.
func _colony_test() -> void:
	print("COLONYTEST starting")
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	print("COLONYTEST probing")
	var b = Universe.body_named("Wireframe")
	var u0: Vector3 = COLONY_DIRS["Wireframe"]
	var C: Vector3 = b.center
	var R: float = b.radius
	var r1 := R - 13.0
	var r2 := R - 24.0
	var e1 := u0.cross(Vector3(0, 0, 1)).normalized()
	var e2 := u0.cross(e1).normalized()
	var space := _player.get_world_3d().direct_space_state
	var cast := func(from: Vector3, to: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return -1.0
		return (hit["position"] as Vector3).distance_to(from)
	# 1. THE DROP: from inside the mouth straight down -- must be caught
	# at story two's solid crossing floor, not the core
	var d1: float = cast.call(C + u0 * (R - 1.0), C)
	var caught: float = (R - 1.0) - d1
	print("COLONYTEST drop: hit at radius %.1f (story2 floor expected ~%.1f) %s" % [
		caught, r2 - 2.45, "PASS" if absf(caught - (r2 - 2.45)) < 1.5 else "FAIL"])
	# 2. ring A clear along its corridor from the crossing
	var d2: float = cast.call(C + u0 * r1 + e1 * 3.0, C + u0 * r1 + e1 * 30.0)
	print("COLONYTEST ringA path: first hit %.1fm (want none <8) %s" % [d2,
		"PASS" if d2 < 0.0 or d2 > 8.0 else "FAIL"])
	# 3. ring B THROUGH the crossing (stub + window + tube alignment)
	var d3: float = cast.call(C + u0 * r1 + e2 * 12.0, C + u0 * r1 - e2 * 12.0)
	print("COLONYTEST ringB through-crossing: first hit %.1fm (want none <20) %s" % [d3,
		"PASS" if d3 < 0.0 or d3 > 20.0 else "FAIL"])
	# 4. leak sweep: diagonal + random rays from crossing center must ALL
	# hit structure within 15m (nothing opens into the hollow planet)
	var leaks := 0
	for i in 24:
		var ang := TAU * float(i) / 24.0
		var dirv := (e1 * cos(ang) + e2 * sin(ang)).normalized()
		if absf(dirv.dot(e1)) > 0.92 or absf(dirv.dot(e2)) > 0.92:
			continue   # corridor axes are SUPPOSED to run long
		var dl: float = cast.call(C + u0 * r1, C + u0 * r1 + dirv * 15.0)
		if dl < 0.0:
			leaks += 1
	print("COLONYTEST leak sweep: %d open diagonals (want 0) %s" % [leaks,
		"PASS" if leaks == 0 else "FAIL"])
	# 5. cafeteria drop from its ring segment. Offset sideways 2m: a
	# resident's collision shell floats dead-center under the hatch and
	# the probe must measure the floor, not an alien's head.
	var cafang := TAU * 3.0 / 28.0
	var cafdir := (u0 * cos(cafang) + e1 * sin(cafang)).normalized()
	var caftang := (-u0 * sin(cafang) + e1 * cos(cafang)).normalized()
	var d5: float = cast.call(C + cafdir * r2 + caftang * 2.0,
		C + caftang * 2.0)
	var cafr: float = r2 - d5
	print("COLONYTEST cafeteria drop: floor at radius %.1f (hall floor ~%.1f) %s" % [
		cafr, r2 - 9.45 - 4.0, "PASS" if absf(cafr - (r2 - 9.45 - 4.0)) < 2.0 else "FAIL"])
	print("COLONYTEST done")

## CTD_TEST=26: ray probes through the Mainframe facility -- drop path,
## the curved control deck's floor and ceiling at three arc angles, the
## server-hall drop, and both gate landing targets.
func _mainframe_test() -> void:
	print("MFTEST starting")
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	var b = Universe.body_named("Big Computer")
	var u0: Vector3 = MAINFRAME_DIR
	var C: Vector3 = b.center
	var R: float = b.radius
	var rF := R - 16.0
	var r2 := R - 26.0
	var e1 := u0.cross(Vector3(0, 0, 1)).normalized()
	var e2 := u0.cross(e1).normalized()
	var space := _player.get_world_3d().direct_space_state
	var cast := func(from: Vector3, to: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return -1.0
		return (hit["position"] as Vector3).distance_to(from)
	# 0. the mouth WORKS from outside: a ray from orbit must sail through
	# the shell hole + shaft + ceiling hatch and land on the atrium floor
	var d0: float = cast.call(C + u0 * (R + 20.0), C)
	var thru: float = (R + 20.0) - d0
	print("MFTEST mouth from orbit: first hit radius %.1f (atrium ~%.1f) %s" % [
		thru, rF, "PASS" if absf(thru - rF) < 1.0 else "FAIL"])
	# 1. the drop: mouth -> atrium floor (solid, hatch is ceiling-only)
	var d1: float = cast.call(C + u0 * (R - 1.0), C)
	var caught: float = (R - 1.0) - d1
	print("MFTEST drop: floor at radius %.1f (atrium ~%.1f) %s" % [caught, rF,
		"PASS" if absf(caught - rF) < 1.0 else "FAIL"])
	# 2. deck floor + ceiling at three angles along the curve
	var step := 4.6 / rF
	for a in [0.115 + step * 2.0, 0.115 + step * 5.0, 0.115 + step * 11.0]:
		var pd := (u0 * cos(a) + e1 * sin(a)).normalized()
		var df: float = cast.call(C + pd * (rF + 3.0), C)
		var fr9: float = (rF + 3.0) - df
		var dc: float = cast.call(C + pd * (rF + 3.0), C + pd * (rF + 20.0))
		var cr9: float = (rF + 3.0) + dc
		print("MFTEST deck a=%.2f: floor %.1f (~%.1f) ceil %.1f (~%.1f) %s" % [
			a, fr9, rF, cr9, rF + 6.0,
			"PASS" if absf(fr9 - rF) < 0.8 and absf(cr9 - (rF + 6.0)) < 0.8 else "FAIL"])
	# 3. server drop through deck hatch seg 7
	var ah := 0.115 + step * 7.0
	var hp := (u0 * cos(ah) + e1 * sin(ah)).normalized()
	var d3: float = cast.call(C + hp * (rF + 2.0), C)
	var srv: float = (rF + 2.0) - d3
	print("MFTEST server drop: floor at radius %.1f (hall ~%.1f) %s" % [srv, r2,
		"PASS" if absf(srv - r2) < 1.0 else "FAIL"])
	# 4. gate landings: server->atrium target and atrium->surface target
	var g1 := C + u0 * (rF + 0.4) + e2 * 3.0
	var d4: float = cast.call(g1, C)
	var g1r: float = (g1 - C).length() - d4
	print("MFTEST atrium gate target: floor %.1f (~%.1f) %s" % [g1r, rF,
		"PASS" if absf(g1r - rF) < 1.0 else "FAIL"])
	var g2 := C + u0 * (R + 1.5) + e1 * 7.0
	var d5: float = cast.call(g2, C)
	var g2r: float = (g2 - C).length() - d5
	print("MFTEST surface gate target: ground %.1f (~%.1f) %s" % [g2r, R,
		"PASS" if absf(g2r - R) < 1.2 else "FAIL"])
	# 5. the wings: a floor probe in every new space
	var floor_checks: Array = [
		["vent tube", (u0 * cos(0.263) - e1 * sin(0.263)).normalized(), rF, 1.5],
		["bunk hall", (u0 * cos(0.263) - e2 * sin(0.263)).normalized(), rF, 1.5],
		["gold suite", ((u0 * cos(4.6) + e1 * sin(4.6)) * 47.0
			- e2 * 10.2).normalized(), 48.09, 1.5],
		["assembly", (u0 * cos(0.722) - e1 * sin(0.722)).normalized(), rF, 3.0],
		["generator", (u0 * cos(0.978) - e1 * sin(0.978)).normalized(), rF, 3.0],
		["ringA east", (u0 * cos(2.0) + e1 * sin(2.0)).normalized(), rF, 2.5],
		["dude ai", (u0 * cos(2.685) + e1 * sin(2.685)).normalized(), rF, 3.5],
		["cockpit", (u0 * -1.0).normalized(), rF, 4.0],
		["server 2", (u0 * cos(3.775) + e1 * sin(3.775)).normalized(), rF, 3.0],
		["ringB east", (u0 * cos(1.0) + e2 * sin(1.0)).normalized(), rF, 2.5],
		["ringB west", (u0 * cos(4.4) + e2 * sin(4.4)).normalized(), rF, 2.5],
		["reactor flr", (u0 * cos(1.3708) + e1 * sin(1.3708)).normalized(), rF - 9.0, 4.0],
		["reactor balc", ((u0 * cos(1.3708) + e1 * sin(1.3708)) * cos(0.21)
			+ e2 * sin(0.21)).normalized(), rF, 2.0],
		["comms", ((u0 * cos(1.3708) + e1 * sin(1.3708)) * cos(0.3556)
			+ e2 * sin(0.3556)).normalized(), rF, 2.5],
	]
	for fc in floor_checks:
		var pd9: Vector3 = fc[1]
		var expr: float = float(fc[2])
		var from9: Vector3 = C + pd9 * (expr + float(fc[3]))
		var dd: float = cast.call(from9, from9 - pd9 * 6.0)
		var got: float = (expr + float(fc[3])) - dd
		print("MFTEST %s: floor %.1f (~%.1f) %s" % [str(fc[0]), got, expr,
			"PASS" if dd >= 0.0 and absf(got - expr) < 0.9 else "FAIL"])
	# 6. the old escape hole over the core doorway is SEALED
	var a13 := 0.115 + (4.6 / rF) * 13.0
	var pd13 := (u0 * cos(a13) + e1 * sin(a13)).normalized()
	var t13 := (-u0 * sin(a13) + e1 * cos(a13)).normalized()
	var dseal: float = cast.call(C + pd13 * (rF + 6.6),
		C + pd13 * (rF + 6.6) + t13 * 12.0)
	print("MFTEST core doorway band: hit at %.1fm (must hit) %s" % [dseal,
		"PASS" if dseal >= 0.0 else "FAIL"])
	# 7. the atrium wall vent dead-ends in its duct (hollow planet --
	# an unsealed vent is an escape hole). Expect the end cap ~4.3m in;
	# <2 means the ray hit the wall face (bad aim), miss/far means leak.
	var vfrom := C + u0 * (rF + 0.5) + e2 * 3.9 - e1 * 5.6
	var dv: float = cast.call(vfrom, vfrom - e1 * 30.0)
	print("MFTEST vent duct: hit at %.1fm (tunnel wall, no void) %s" % [dv,
		"PASS" if dv >= 2.0 else "FAIL"])
	# 8. the secret networks: every stored probe point (vent tunnel
	# mids, hubs, checkpoints, noodle room) has floor AND ceiling
	var mfc9: Node = null
	for ch9 in get_children():
		if ch9 is MainframeComplex:
			mfc9 = ch9
	if mfc9 != null and mfc9.has_meta("net_probes"):
		var idx9 := 0
		for pp in (mfc9.get_meta("net_probes") as Array):
			var pv: Vector3 = pp
			var upv := (pv - C).normalized()
			var st9 := pv + upv * 1.2
			var dflr: float = cast.call(st9, st9 - upv * 5.0)
			var dcei: float = cast.call(st9, st9 + upv * 5.0)
			print("MFTEST net probe %d: floor %.1f ceil %.1f %s" % [idx9,
				dflr, dcei,
				"PASS" if dflr >= 0.0 and dcei >= 0.0 else "FAIL"])
			idx9 += 1
	# 9. DOORWAY SWEEP: a knee-height ray THROUGH every deck side-room
	# door. Anything it hits inside the span is a step/blocker bug.
	for dspec in [[3, -1.0, "LAB"], [5, 1.0, "AQUARIUM"],
			[9, 1.0, "MAP ROOM"], [11, -1.0, "CARGO BAY"]]:
		var ad9: float = 0.115 + step * float(int(dspec[0]))
		var pd9b := (u0 * cos(ad9) + e1 * sin(ad9)).normalized()
		var tb9 := (-u0 * sin(ad9) + e1 * cos(ad9)).normalized()
		var e2b := pd9b.cross(tb9).normalized()
		var sgn9: float = float(dspec[1])
		var from9b := C + pd9b * (rF + 0.28) + e2b * sgn9 * 3.4
		var to9b := C + pd9b * (rF + 0.28) + e2b * sgn9 * 7.6
		var q9 := PhysicsRayQueryParameters3D.create(from9b, to9b)
		var hit9 := space.intersect_ray(q9)
		print("MFTEST door %s: knee ray %s" % [str(dspec[2]),
			"CLEAR PASS" if hit9.is_empty() else
			"BLOCKED at %.2fm FAIL" % (hit9.position as Vector3).distance_to(from9b)])
	print("MFTEST done")

## Windowed: hover a camera over the Pixel colony mouth and screenshot
## straight down -- checks the mesh-cut opening actually clears the
var _uw_layer: CanvasLayer = null
var _ocean_mats: Array = []

## fullscreen ocean effect: screen-space wave distortion + blue fog,
## the aquarium treatment applied to your whole eyeball
func _set_underwater(on: bool) -> void:
	Game.underwater = on
	for om in _ocean_mats:
		(om as ShaderMaterial).set_shader_parameter("submerged",
			1.0 if on else 0.0)
	if on and _uw_layer == null:
		_uw_layer = CanvasLayer.new()
		_uw_layer.layer = 20
		add_child(_uw_layer)
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh9 := Shader.new()
		sh9.code = """
shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
void fragment(){
	float t = TIME;
	vec2 w = vec2(sin(t * 1.3 + SCREEN_UV.y * 26.0 + SCREEN_UV.x * 9.0),
		cos(t * 1.0 + SCREEN_UV.x * 22.0)) * 0.008;
	vec3 bg = texture(scr, clamp(SCREEN_UV + w, vec2(0.001), vec2(0.999))).rgb;
	vec3 fogc = vec3(0.07, 0.28, 0.52);
	float shimmer = 0.04 * sin(t * 2.0 + SCREEN_UV.y * 50.0);
	COLOR = vec4(mix(bg, fogc, 0.38) + shimmer * fogc, 1.0);
}
"""
		var mt9 := ShaderMaterial.new()
		mt9.shader = sh9
		rect.material = mt9
		_uw_layer.add_child(rect)
	elif not on and _uw_layer != null:
		_uw_layer.queue_free()
		_uw_layer = null

## THE SKY SHOW: the universe itself cracking. A crack dome and two
## shells of giant triangles CENTERED ON YOU -- they follow the camera
## every frame like a skybox, so the broken sky is everywhere you go,
## for the whole six-minute afterglow. Planets still occlude them:
## the universe cracks BEHIND the world.
var _skyfx: Array = []   # nodes that track the player like a skybox
var _sky_tweens: Array = []   # every looped show tween -- killed on clear,
							  # or they step freed targets forever

func mono_sky_clear() -> void:
	for tw9 in _sky_tweens:
		if tw9 != null and (tw9 as Tween).is_valid():
			(tw9 as Tween).kill()
	_sky_tweens.clear()
	for n in get_tree().get_nodes_in_group("mono_sky"):
		if is_instance_valid(n):
			n.queue_free()
	_skyfx.clear()

func mono_sky_demo(stage: int) -> void:
	sky_show(Game.MONO_COLORS[clampi(stage, 0, 7)], clampi(stage, 0, 7), false)

## THE SHATTER: the boundary breaks. White flash, then the sky-shell
## bursts into giant glass shards that tumble inward and fade. The
## eighth activation's finale -- previewable from the cheat menu.
var _shatter_seq := false

func sky_shatter() -> void:
	# PHASE 1 -- THE BUILD-UP. The lattice stays hidden until the blast.
	_shatter_seq = true
	if _boundary_mesh != null:
		_boundary_mesh.visible = false
	var ckm := sky_show(Color(1.0, 0.97, 0.9), 7, false)
	Sfx.play("nuke", -30.0)
	var esc := create_tween()
	_sky_tweens.append(esc)
	esc.tween_method(func(v: float) -> void:
		if ckm != null:
			ckm.set_shader_parameter("boost", 1.0 + 2.6 * v * v)
			ckm.set_shader_parameter("speed", 0.35 + 5.0 * v * v),
		0.0, 1.0, 17.0)
	if _skyfx.size() > 0:
		# the shard sky spins up from a drift to a churn
		var shell9: Node3D = _skyfx.back()
		var acc := create_tween()
		_sky_tweens.append(acc)
		acc.tween_property(shell9, "rotation:y", TAU * 1.5, 17.0) \
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var boom := create_tween()
	boom.tween_interval(6.0)
	boom.tween_callback(func() -> void: Sfx.play("nuke", -22.0))
	boom.tween_interval(5.0)
	boom.tween_callback(func() -> void: Sfx.play("nuke", -15.0))
	boom.tween_interval(3.5)
	boom.tween_callback(func() -> void: Sfx.play("nuke", -11.0))
	var det := create_tween()
	det.tween_interval(17.0)
	det.tween_callback(_sky_detonate)

func _sky_detonate() -> void:
	Game.god_restrain(40.0)
	_shatter_seq = false
	mono_sky_clear()
	var flash := CanvasLayer.new()
	flash.layer = 60
	flash.add_to_group("mono_sky")
	add_child(flash)
	var fr := ColorRect.new()
	fr.color = Color(1, 1, 1, 0.0)
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.add_child(fr)
	var ftw := create_tween()
	ftw.tween_property(fr, "color:a", 0.9, 0.5)
	ftw.tween_property(fr, "color:a", 0.0, 2.0)
	ftw.tween_callback(flash.queue_free)
	# the sound of a universe losing its lid: the full nuke waveform,
	# sub punch and rolling rumble, at full voice
	Sfx.play("nuke", -8.0)
	# the ECHO: the same blast rolling back off everything, three times,
	# quieter each return -- and when the roar dies, the choir of the
	# OUTSIDE, heard through the new hole where the sky used to be
	var ech := create_tween()
	ech.tween_interval(1.3)
	ech.tween_callback(func() -> void: Sfx.play("nuke", -17.0))
	ech.tween_interval(1.5)
	ech.tween_callback(func() -> void: Sfx.play("nuke", -24.0))
	ech.tween_interval(1.7)
	ech.tween_callback(func() -> void: Sfx.play("nuke", -30.0))
	ech.tween_interval(1.0)
	ech.tween_callback(func() -> void:
		var gp := AudioStreamPlayer.new()
		gp.stream = _god_chord()
		gp.volume_db = -7.0
		add_child(gp)
		gp.play()
		var gtw := create_tween()
		gtw.tween_interval(13.0)
		gtw.tween_callback(gp.queue_free))
	# and out of the wreckage, the dying scaffold FADES IN -- the bars
	# were always there; now you get to see them
	if _boundary_mesh != null:
		# ABRUPT: the lattice is just THERE the instant the sky goes
		_boundary_mesh.visible = true
		for fm in _boundary_fade_mats:
			(fm as StandardMaterial3D).albedo_color.a = 0.12
			(fm as StandardMaterial3D).emission_energy_multiplier = 1.1
		if Game.monolith_stage < 8:
			# PREVIEW: the lattice shows off, then goes back to hiding
			var rtw := create_tween()
			rtw.tween_interval(12.0)
			rtw.tween_method(func(v: float) -> void:
				for fm in _boundary_fade_mats:
					(fm as StandardMaterial3D).albedo_color.a = 0.12 * v
					(fm as StandardMaterial3D).emission_energy_multiplier = 1.1 * v,
				1.0, 0.0, 5.0)
			rtw.tween_callback(func() -> void:
				if _boundary_mesh != null and Game.monolith_stage < 8:
					_boundary_mesh.visible = false)
	# THE FULL SHELL, for one breath: the border appears PACKED --
	# hundreds of triangles tiling the whole sphere, connected, flush --
	# then every one of them strays off on its own line and most of
	# them simply stop existing. What stays is the broken scaffold.
	var brng := RandomNumberGenerator.new()
	brng.seed = 424242
	var bshell := Node3D.new()
	bshell.add_to_group("mono_sky")
	add_child(bshell)
	bshell.global_position = Vector3.ZERO
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.25, 0.6, 1.0, 0.55)
	bmat.emission_enabled = true
	bmat.emission = Color(0.25, 0.6, 1.0)
	bmat.emission_energy_multiplier = 1.6
	bmat.render_priority = -3
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var b_lrad := Universe.BOUNDARY - 900.0
	# a TRUE geodesic shell: an icosphere (frequency 8, 1280 faces) so
	# every triangle SHARES its edges with its neighbours -- one perfect
	# unbroken ball of triangles, dead still. Then it falls apart.
	var phi9 := (1.0 + sqrt(5.0)) * 0.5
	var iv9: Array = [Vector3(-1, phi9, 0), Vector3(1, phi9, 0),
		Vector3(-1, -phi9, 0), Vector3(1, -phi9, 0),
		Vector3(0, -1, phi9), Vector3(0, 1, phi9),
		Vector3(0, -1, -phi9), Vector3(0, 1, -phi9),
		Vector3(phi9, 0, -1), Vector3(phi9, 0, 1),
		Vector3(-phi9, 0, -1), Vector3(-phi9, 0, 1)]
	var ifc9: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10],
		[0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
		[7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var FQ := 8
	var mk_plate := func(pa: Vector3, pb: Vector3, pc: Vector3) -> void:
		var cen := ((pa + pb + pc) / 3.0)
		var fn9 := (pb - pa).cross(pc - pa).normalized()
		var st9 := SurfaceTool.new()
		st9.begin(Mesh.PRIMITIVE_TRIANGLES)
		for eg in [[pa, pb], [pb, pc], [pc, pa]]:
			var e0: Vector3 = (eg[0] as Vector3) - cen
			var e1: Vector3 = (eg[1] as Vector3) - cen
			var sd := fn9.cross(e1 - e0).normalized() \
				* (e1 - e0).length() * 0.022
			st9.add_vertex(e0 - sd)
			st9.add_vertex(e0 + sd)
			st9.add_vertex(e1 + sd)
			st9.add_vertex(e0 - sd)
			st9.add_vertex(e1 + sd)
			st9.add_vertex(e1 - sd)
		var plate := Node3D.new()
		bshell.add_child(plate)
		plate.position = cen
		var pm9 := MeshInstance3D.new()
		pm9.mesh = st9.commit()
		pm9.material_override = bmat
		pm9.extra_cull_margin = 16384.0
		plate.add_child(pm9)
		# each shard dies on its own clock, up to ~3s apart
		var pfd := pm9.create_tween()
		pfd.tween_interval(1.2 + brng.randf() * 1.5)
		pfd.tween_property(pm9, "transparency", 1.0,
			4.5 + brng.randf() * 2.5)
		pfd.tween_callback(pm9.hide)
		# the FALL: perfectly still for a breath, then off it goes
		var dirn := cen.normalized()
		var txn := dirn.cross(Vector3(0, 1, 0))
		if txn.length() < 0.01:
			txn = dirn.cross(Vector3(1, 0, 0))
		txn = txn.normalized()
		var tzn := txn.cross(dirn).normalized()
		var away := (dirn * (0.8 if brng.randf() < 0.5 else -0.45)
			+ txn * brng.randf_range(-0.6, 0.6)
			+ tzn * brng.randf_range(-0.6, 0.6)).normalized()
		var sc9 := plate.create_tween()
		sc9.tween_interval(1.4 + brng.randf_range(0.0, 1.2))
		sc9.tween_property(plate, "position",
			away * Universe.BOUNDARY * brng.randf_range(0.2, 0.55),
			brng.randf_range(5.0, 9.0)) \
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var tb9 := plate.create_tween()
		tb9.tween_interval(1.4 + brng.randf_range(0.0, 1.2))
		tb9.tween_property(plate, "rotation",
			Vector3(brng.randf_range(-2.0, 2.0), brng.randf_range(-2.0, 2.0),
				brng.randf_range(-1.0, 1.0)), 8.0).as_relative()
	for f9 in ifc9:
		var A9 := (iv9[(f9 as Array)[0]] as Vector3).normalized()
		var B9 := (iv9[(f9 as Array)[1]] as Vector3).normalized()
		var C9 := (iv9[(f9 as Array)[2]] as Vector3).normalized()
		var pt := func(i9: int, j9: int) -> Vector3:
			var w0 := 1.0 - float(i9) / float(FQ)
			var w2 := float(j9) / float(FQ)
			var w1 := 1.0 - w0 - w2
			return (A9 * w0 + B9 * w1 + C9 * w2).normalized() * b_lrad
		for i9 in FQ:
			for j9 in i9 + 1:
				mk_plate.call(pt.call(i9, j9), pt.call(i9 + 1, j9),
					pt.call(i9 + 1, j9 + 1))
				if j9 < i9:
					mk_plate.call(pt.call(i9, j9), pt.call(i9 + 1, j9 + 1),
						pt.call(i9, j9 + 1))
	var bf9 := create_tween()
	_sky_tweens.append(bf9)
	bf9.tween_interval(12.0)
	bf9.tween_callback(func() -> void:
		if is_instance_valid(bshell):
			bshell.queue_free())
	var rng9 := RandomNumberGenerator.new()
	rng9.seed = 8888
	var shroot := Node3D.new()
	shroot.add_to_group("mono_sky")
	add_child(shroot)
	for i in 700:
		var d9 := Vector3(rng9.randf_range(-1, 1), rng9.randf_range(-1, 1),
			rng9.randf_range(-1, 1)).normalized()
		var shard := MeshInstance3D.new()
		var pm9 := PrismMesh.new()
		pm9.size = Vector3(rng9.randf_range(2200.0, 5200.0),
			rng9.randf_range(2600.0, 6200.0), 90.0)
		shard.mesh = pm9
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.55, 0.75, 1.0, 0.5)
		smat.emission_enabled = true
		smat.emission = Color(0.55, 0.75, 1.0)
		shard.material_override = smat
		shard.extra_cull_margin = 16384.0
		shroot.add_child(shard)
		shard.global_position = d9 * (Universe.BOUNDARY - 200.0)
		shard.rotation = Vector3(rng9.randf() * TAU, rng9.randf() * TAU, 0)
		var fall := create_tween()
		fall.tween_property(shard, "global_position",
			d9 * (Universe.BOUNDARY * rng9.randf_range(0.55, 0.8)),
			rng9.randf_range(9.0, 16.0)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(smat, "albedo_color:a", 0.0,
			rng9.randf_range(9.0, 16.0))
		var spin9 := create_tween().set_loops()
		_sky_tweens.append(spin9)
		spin9.tween_property(shard, "rotation",
			Vector3(TAU * rng9.randf_range(0.2, 0.7),
			TAU * rng9.randf_range(0.2, 0.7), 0), 8.0).as_relative()
	var cln := create_tween()
	cln.tween_interval(18.0)
	cln.tween_callback(func() -> void:
		# the shard spins are in _sky_tweens: kill them BEFORE their
		# targets free, or they step corpses forever
		for tw9 in _sky_tweens:
			if tw9 != null and (tw9 as Tween).is_valid():
				(tw9 as Tween).kill()
		_sky_tweens.clear()
		if is_instance_valid(shroot):
			shroot.queue_free())

## the shard EXPLOSION of a monolith sky show -- separable from the
## cracks so the stone can drop first and the sky burst after
func _sky_plates(skyp: Node3D, col: Color, stage: int) -> void:
	if not is_instance_valid(skyp):
		return
	var rngs := RandomNumberGenerator.new()
	rngs.seed = 991 + stage * 31
	var nplates := 84 + 14 * stage
	var srad := Universe.BOUNDARY - 3000.0
	var side := Universe.BOUNDARY * 0.048
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	rim_mat.emission_enabled = true
	rim_mat.emission = col
	rim_mat.emission_energy_multiplier = 1.5
	rim_mat.render_priority = -4
	for i in nplates:
		var ky := 1.0 - 2.0 * (float(i) + 0.5) / float(nplates)
		var kr := sqrt(maxf(0.0, 1.0 - ky * ky))
		var kphi := PI * (1.0 + sqrt(5.0)) * float(i)
		var dir9 := Vector3(cos(kphi) * kr, ky, sin(kphi) * kr)
		var tx := dir9.cross(Vector3(0, 1, 0))
		if tx.length() < 0.01:
			tx = dir9.cross(Vector3(1, 0, 0))
		tx = tx.normalized()
		var tz := tx.cross(dir9).normalized()
		var plate := Node3D.new()
		skyp.add_child(plate)
		plate.position = dir9 * srad
		plate.transform.basis = Basis(tx, dir9, tz).orthonormalized()
		plate.rotate_object_local(Vector3(0, 1, 0), rngs.randf() * TAU)
		plate.rotate_object_local(Vector3(1, 0, 0),
			deg_to_rad(rngs.randf_range(4.0, 34.0))
			* (-1.0 if rngs.randf() < 0.65 else 1.0))
		var s9 := side * rngs.randf_range(0.55, 1.25)
		for e9 in 3:
			var va := Vector3(cos(TAU * (float(e9) + 0.25) / 3.0), 0,
				sin(TAU * (float(e9) + 0.25) / 3.0)) * s9 * 0.577
			var vb := Vector3(cos(TAU * (float(e9) + 1.25) / 3.0), 0,
				sin(TAU * (float(e9) + 1.25) / 3.0)) * s9 * 0.577
			var ed := MeshInstance3D.new()
			var em9 := BoxMesh.new()
			em9.size = Vector3(va.distance_to(vb) * 1.02, s9 * 0.02, s9 * 0.02)
			ed.mesh = em9
			ed.material_override = rim_mat
			ed.extra_cull_margin = 16384.0
			plate.add_child(ed)
			ed.position = (va + vb) * 0.5
			ed.rotation.y = -atan2((vb - va).z, (vb - va).x)
		var tum := plate.create_tween().set_loops()
		tum.tween_property(plate, "rotation",
			Vector3(TAU * rngs.randf_range(0.2, 0.6),
				TAU * rngs.randf_range(0.3, 0.8),
				TAU * rngs.randf_range(0.1, 0.4)),
			18.0 + 20.0 * rngs.randf()).as_relative()
		# the RUSH: each shard tears off radially -- half dive inward,
		# half flee outward -- fast, and gone
		var rsign := 1.0 if rngs.randf() < 0.5 else -1.0
		var rush := plate.create_tween()
		rush.tween_property(plate, "position",
			dir9 * rsign * Universe.BOUNDARY * rngs.randf_range(0.3, 0.7),
			8.0 + 3.0 * rngs.randf()) \
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# the whole field fades away as it rushes; the cracks stay behind
	var pfade := create_tween()
	_sky_tweens.append(pfade)
	pfade.tween_interval(1.5)
	pfade.tween_property(rim_mat, "albedo_color:a", 0.0, 7.5)
	pfade.parallel().tween_property(rim_mat,
		"emission_energy_multiplier", 0.0, 7.5)
	pfade.tween_callback(func() -> void:
		if is_instance_valid(skyp):
			skyp.queue_free())

## FALLING GLASS: full transparent triangles raining out of the sky --
## the pink link sheds plenty, the cyan link sheds TONS: the universe
## is one feed away from done and it shows
func _sky_fall(skyp: Node3D, col: Color, stage: int) -> void:
	if not is_instance_valid(skyp):
		return
	var count := 0
	if stage == 5:
		count = 130
	elif stage >= 6:
		count = 300
	if count == 0:
		return
	var rngf := RandomNumberGenerator.new()
	rngf.seed = 5151 + stage
	for i in count:
		var d9 := Vector3(rngf.randf_range(-1, 1), rngf.randf_range(-1, 1),
			rngf.randf_range(-1, 1)).normalized()
		var shard := MeshInstance3D.new()
		var pm9 := PrismMesh.new()
		pm9.size = Vector3(rngf.randf_range(1800.0, 4600.0),
			rngf.randf_range(2200.0, 5400.0), 80.0)
		shard.mesh = pm9
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(col.r, col.g, col.b, 0.45)
		smat.emission_enabled = true
		smat.emission = col
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		shard.material_override = smat
		shard.extra_cull_margin = 16384.0
		skyp.add_child(shard)
		shard.global_position = d9 * (Universe.BOUNDARY - 1500.0)
		shard.rotation = Vector3(rngf.randf() * TAU, rngf.randf() * TAU, 0)
		var dur := rngf.randf_range(9.0, 17.0)
		var fall := shard.create_tween()
		fall.tween_property(shard, "global_position",
			d9 * (Universe.BOUNDARY * rngf.randf_range(0.45, 0.75)), dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(smat, "albedo_color:a", 0.0, dur)
		fall.tween_callback(shard.queue_free)
		var spin := shard.create_tween().set_loops()
		spin.tween_property(shard, "rotation",
			Vector3(TAU * rngf.randf_range(0.2, 0.6),
				TAU * rngf.randf_range(0.2, 0.6), 0), 8.0).as_relative()

func sky_show(col: Color, stage: int, linger: bool,
		burst_delay: float = 0.0) -> ShaderMaterial:
	mono_sky_clear()
	# CRACKS: a dome at cosmic distance, always around you
	var crack := MeshInstance3D.new()
	var ckm := SphereMesh.new()
	ckm.radius = Universe.BOUNDARY - 900.0
	ckm.height = ckm.radius * 2.0
	ckm.radial_segments = 64
	ckm.rings = 32
	crack.mesh = ckm
	var ckmat := ShaderMaterial.new()
	ckmat.shader = Monolith._crack_shader()
	ckmat.render_priority = -6   # behind world transparents, above veil
	ckmat.set_shader_parameter("ccol", Vector3(col.r, col.g, col.b))
	# density is PROGRESS: each link cracks the sky harder than the last
	ckmat.set_shader_parameter("intensity",
		0.12 + 0.88 * float(stage + 1) / 8.0)
	crack.material_override = ckmat
	crack.extra_cull_margin = 16384.0
	crack.add_to_group("mono_sky")
	add_child(crack)
	crack.global_position = Vector3.ZERO
	# not mercy, not approval -- the game simply holds the god off your
	# back while the sky performs, because getting smacked mid-ceremony
	# is bad theater. He is not glad. He is just not allowed.
	Game.god_restrain(400.0 if linger else 34.0)
	var cktw := create_tween()
	_sky_tweens.append(cktw)
	cktw.tween_method(func(v: float) -> void:
		if is_instance_valid(crack):
			ckmat.set_shader_parameter("fade", v), 0.0, 1.0, 0.1)
	# SHATTERED GLASS, on its own fuse: immediately by default, or
	# delayed so the burst lands after whatever deserves to go first
	var skyp := Node3D.new()
	skyp.add_to_group("mono_sky")
	add_child(skyp)
	skyp.global_position = Vector3.ZERO
	_skyfx.append(skyp)
	# NO boundary-glass triangles here: those are pieces of the actual
	# barrier and only the EIGHTH breaks it -- if link one shed them,
	# the lore would have the universe half-won at yellow. Links shed
	# only their falling glass rain (pink plenty, cyan tons).
	if burst_delay > 0.0:
		var bdt := skyp.create_tween()
		bdt.tween_interval(burst_delay)
		bdt.tween_callback(_sky_fall.bind(skyp, col, stage))
	else:
		_sky_fall(skyp, col, stage)
	var wheel := skyp.create_tween().set_loops()
	wheel.tween_property(skyp, "rotation:y", TAU, 480.0).as_relative()
	# lifecycle: demo = 30s and gone; the real thing lingers six minutes
	var hold := 26.0 if linger else 4.0
	var fade9 := 360.0 if linger else 24.0
	var life := create_tween()
	_sky_tweens.append(life)
	life.tween_interval(hold)
	life.tween_callback(func() -> void:
		var f2 := create_tween()
		_sky_tweens.append(f2)
		f2.tween_method(func(v: float) -> void:
			if is_instance_valid(crack):
				ckmat.set_shader_parameter("fade", v), 1.0, 0.0, fade9)
		pass)   # the shard burst fades itself; only the cracks linger
	life.tween_interval(fade9 + 2.0)
	life.tween_callback(func() -> void:
		for tw9 in _sky_tweens:
			if tw9 != null and (tw9 as Tween).is_valid():
				(tw9 as Tween).kill()
		_sky_tweens.clear()
		if is_instance_valid(crack):
			crack.queue_free()
		if is_instance_valid(skyp):
			skyp.queue_free()
		_skyfx.clear())
	return ckmat

## The EDGE OF THE UNIVERSE, visible when you get close: a red warning
## lattice that fades in over the last 2km before the god throws you
## back. Inward faces only.
func _build_boundary() -> void:
	# THE BROKEN SCAFFOLD: ~300 real triangle plates scattered over the
	# boundary sphere -- each one a thin wire OUTLINE, spaced apart,
	# and TILTED on its own axis (many leaning inward off the shell
	# entirely). Not a pattern on a sphere: actual shattered geometry.
	_boundary_mesh = Node3D.new()
	add_child(_boundary_mesh)
	_boundary_mesh.global_position = Vector3.ZERO
	_boundary_mesh.visible = Game.monolith_stage >= 8
	var rngb := RandomNumberGenerator.new()
	rngb.seed = 6180
	var mats: Array = []
	for c9 in [Color(0.20, 0.55, 1.0), Color(0.45, 0.30, 1.0),
			Color(0.4, 0.95, 1.0)]:
		var m9 := StandardMaterial3D.new()
		m9.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m9.albedo_color = Color(c9.r, c9.g, c9.b, 0.12)
		m9.emission_enabled = true
		m9.emission = c9
		m9.emission_energy_multiplier = 1.1
		mats.append(m9)
		_boundary_fade_mats.append(m9)
	# TWO shells of shards, Astroneer-artifact style: the sky fills with
	# tilted glowing triangles at two depths, each drifting on a clock
	# so slow you feel it more than see it
	for layer9 in 2:
		var N9 := 380 if layer9 == 0 else 260
		var lrad := (Universe.BOUNDARY - 900.0) if layer9 == 0 \
			else (Universe.BOUNDARY - 7500.0)
		var side := Universe.BOUNDARY * (0.052 if layer9 == 0 else 0.036)
		var ew := side * 0.03
		for i in N9:
			if rngb.randf() < 0.2:
				continue   # a broken shell has holes
			# fibonacci sphere point
			var ky := 1.0 - 2.0 * (float(i) + 0.5) / float(N9)
			var kr := sqrt(maxf(0.0, 1.0 - ky * ky))
			var kphi := PI * (1.0 + sqrt(5.0)) * float(i) + float(layer9) * 2.4
			var dir9 := Vector3(cos(kphi) * kr, ky, sin(kphi) * kr)
			var up9 := dir9
			var tx := up9.cross(Vector3(0, 1, 0))
			if tx.length() < 0.01:
				tx = up9.cross(Vector3(1, 0, 0))
			tx = tx.normalized()
			var tz := tx.cross(up9).normalized()
			var plate := Node3D.new()
			_boundary_mesh.add_child(plate)
			plate.global_position = dir9 * lrad
			plate.global_transform.basis = Basis(tx, up9, tz).orthonormalized()
			# the SHATTER: spin in plane, then LEAN -- up to 40 degrees,
			# biased inward: plates hang off the shell like broken glass
			plate.rotate_object_local(Vector3(0, 1, 0), rngb.randf() * TAU)
			var lean := deg_to_rad(rngb.randf_range(6.0, 40.0)) \
				* (-1.0 if rngb.randf() < 0.65 else 1.0)
			plate.rotate_object_local(Vector3(1, 0, 0), lean)
			# the DRIFT: each shard turns on its own normal, minutes per
			# revolution -- alive, never wobbling
			var dtw := plate.create_tween().set_loops()
			dtw.tween_property(plate, "rotation:y", TAU
				* (1.0 if rngb.randf() < 0.5 else -1.0),
				rngb.randf_range(200.0, 420.0)).as_relative()
			# wire-outline triangle: three thin bars, vertex up
			var mat9: StandardMaterial3D = mats[i % mats.size()]
			var vA := Vector3(0, 0, -side * 0.577)
			var vB := Vector3(-side * 0.5, 0, side * 0.289)
			var vC := Vector3(side * 0.5, 0, side * 0.289)
			for pr9 in [[vA, vB], [vB, vC], [vC, vA]]:
				var pa9: Vector3 = pr9[0]
				var pb9: Vector3 = pr9[1]
				var bar9 := MeshInstance3D.new()
				var bm9 := BoxMesh.new()
				bm9.size = Vector3(ew, ew, pa9.distance_to(pb9))
				bar9.mesh = bm9
				bar9.material_override = mat9
				plate.add_child(bar9)
				bar9.position = (pa9 + pb9) * 0.5
				bar9.look_at_from_position(bar9.global_position,
					plate.to_global(pb9), plate.global_transform.basis.y)
				bar9.extra_cull_margin = 999999.0
	# THE VOID ARCHITECTURE -- no overlays, only real geometry, so
	# depth sorting can never draw anything over a planet:
	# 1. a WHITE SHELL far outside everything (inward faces): the void's
	#    backdrop in every direction.
	# 2. a BLACK STAR BALL sitting exactly at the boundary (inward
	#    faces): from inside it IS the starry sky; from outside its far
	#    inner wall is a disc of night with stars, exactly where the
	#    universe is, with every planet drawn in FRONT of it by plain
	#    depth. Nothing curves around anything.
	var wshell := MeshInstance3D.new()
	var wsm := SphereMesh.new()
	wsm.radius = Universe.BOUNDARY * 1.5
	wsm.height = wsm.radius * 2.0
	wsm.radial_segments = 48
	wsm.rings = 24
	wshell.mesh = wsm
	var bshell := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = Universe.BOUNDARY * 4.0   # SUPER big: 285km of dark
	bsm.height = bsm.radius * 2.0
	bsm.radial_segments = 48
	bsm.rings = 24
	bshell.mesh = bsm
	var bkmat := StandardMaterial3D.new()
	bkmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bkmat.albedo_color = Color(0, 0, 0)
	bkmat.cull_mode = BaseMaterial3D.CULL_FRONT
	bshell.material_override = bkmat
	bshell.extra_cull_margin = 999999.0
	bshell.visible = false
	_void_shells.append(bshell)
	add_child(bshell)
	bshell.global_position = Vector3.ZERO
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.albedo_color = Color(1, 1, 1)
	wmat.cull_mode = BaseMaterial3D.CULL_FRONT
	wshell.material_override = wmat
	wshell.extra_cull_margin = 999999.0
	# OUTSIDE-ONLY: from inside, the sky must be the real infinite
	# starfield skybox -- never a wall the god can stand in front of
	wshell.visible = false
	_void_shells.append(wshell)
	add_child(wshell)
	wshell.global_position = Vector3.ZERO
	var starball := MeshInstance3D.new()
	var sbm := SphereMesh.new()
	sbm.radius = Universe.BOUNDARY - 200.0
	sbm.height = sbm.radius * 2.0
	sbm.radial_segments = 64
	sbm.rings = 32
	starball.mesh = sbm
	var ssh := Shader.new()
	ssh.code = """
shader_type spatial;
render_mode unshaded, cull_front;
varying vec3 vn;
void vertex(){ vn = normalize(VERTEX); }
float h31(vec3 p){ return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void fragment(){
	vec3 n = normalize(vn);
	vec3 cell = floor(n * 240.0);
	float star = step(0.9974, h31(cell));
	float tw = 0.6 + 0.4 * sin(TIME * (1.0 + h31(cell + 1.0) * 3.0)
		+ h31(cell + 2.0) * 6.28);
	ALBEDO = vec3(0.002, 0.003, 0.006) + vec3(1.0) * star * tw;
	EMISSION = vec3(0.9, 0.95, 1.0) * star * tw * 0.7;
}
"""
	var smt := ShaderMaterial.new()
	smt.shader = ssh
	starball.material_override = smt
	starball.extra_cull_margin = 999999.0
	starball.visible = false
	_void_shells.append(starball)
	add_child(starball)
	starball.global_position = Vector3.ZERO

## CTD_TEST=30: the EDGE diagnostics. Outside looking back (white void
## + star disc + planets in front), and inside looking out with the
## sky broken (lattice + cracks).
## CTD_TEST=38: detonate and LOOK -- the packed shell must be in frame
func _shatter_shot() -> void:
	await get_tree().create_timer(4.0).timeout
	Game.monolith_stage = 8
	_sky_detonate()
	var cam := Camera3D.new()
	cam.far = 1000000.0
	add_child(cam)
	var hb = Universe.body_named("Home")
	cam.global_position = hb.center + Vector3.UP * (hb.radius + 30.0)
	cam.look_at(cam.global_position + Vector3(0.3, 1, 0.2), Vector3.FORWARD)
	cam.current = true
	await get_tree().create_timer(2.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("SHATTERSHOT saved")
	get_tree().quit()

## CTD_TEST=37: the full break-the-universe sequence, timed
func _shatter_test() -> void:
	await get_tree().create_timer(3.0).timeout
	Game.monolith_stage = 8
	_on_monolith_advanced()
	sky_shatter()
	await get_tree().create_timer(3.0).timeout
	var cracks_mid := get_tree().get_nodes_in_group("mono_sky").size()
	var lat_mid: bool = _boundary_mesh != null and _boundary_mesh.visible
	print("SHATTER t+3: cracks=%d lattice_visible=%s (want cracks>0, lattice HIDDEN)"
		% [cracks_mid, str(lat_mid)])
	await get_tree().create_timer(17.0).timeout
	var cracks_end := 0
	for n9 in get_tree().get_nodes_in_group("mono_sky"):
		if is_instance_valid(n9) and not n9.is_queued_for_deletion():
			cracks_end += 1
	var lat_end: bool = _boundary_mesh != null and _boundary_mesh.visible
	print("SHATTER t+20: leftover=%d lattice_visible=%s %s" % [cracks_end,
		str(lat_end), "PASS" if cracks_mid > 0 and not lat_mid
		and lat_end else "FAIL"])
	get_tree().quit()

## CTD_TEST=39: capture the FORK TV studio feed itself
func _forktv_shot() -> void:
	await get_tree().create_timer(2.0).timeout
	var vp := TVSet.channel_feed(get_tree(), 1)
	TVSet.ping(1)
	await get_tree().create_timer(2.0).timeout
	TVSet.ping(1)
	await get_tree().create_timer(0.5).timeout
	var img := vp.get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("FORKSHOT saved")
	get_tree().quit()

## CTD_TEST=36: fire the monolith sky show headless and prove it built
func _skyshow_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var mat9 = sky_show(Game.MONO_COLORS[1], 1, true)
	await get_tree().create_timer(2.0).timeout
	var n9 := get_tree().get_nodes_in_group("mono_sky").size()
	var plates9 := 0
	for fx in _skyfx:
		if is_instance_valid(fx):
			plates9 = (fx as Node3D).get_child_count()
	print("SKYSHOW nodes=%d plates=%d mat=%s %s" % [n9, plates9,
		str(mat9 != null), "PASS" if n9 >= 2 and plates9 > 50
		and mat9 != null else "FAIL"])
	get_tree().quit()

## CTD_TEST=34: camera in the riddle room, looking at the far wall --
## the riddle must be READABLE in the frame
func _riddle_shot() -> void:
	await get_tree().create_timer(4.0).timeout
	var hh := House.new()
	hh.kind = "small"
	hh.harolds = true
	hh.slot = -99
	add_child(hh)
	hh.global_position = Vector3(300, 40, 300)
	await get_tree().create_timer(2.0).timeout
	var c := hh.room_center()
	var sz := hh.room_size()
	var fy := c.y - sz.y * 0.5
	var rc := c + Vector3(-sz.x * 0.5 - 6.6, fy - c.y - 11.0 - 1.6, -2.0) \
		+ Vector3(0, 0, -5.6)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = rc + Vector3(0, 0.2, 3.6)
	cam.look_at(rc + Vector3(0, 0.2, -4.0), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("RIDDLESHOT saved")
	get_tree().quit()

## CTD_TEST=33: headless probe of Harold's secret. Build the house,
## open the shelf, ray the shaft, solve the riddle, take the prize.
func _harold_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var hh := House.new()
	hh.kind = "small"
	hh.harolds = true
	hh.slot = -99
	add_child(hh)
	hh.global_position = Vector3(300, 40, 300)
	await get_tree().create_timer(2.0).timeout
	var c := hh.room_center()
	var sz := hh.room_size()
	var fy := c.y - sz.y * 0.5
	var hx := sz.x * 0.5
	var sp9 := get_viewport().get_world_3d().direct_space_state
	var cast := func(a: Vector3, b: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(a, b)
		var hit := sp9.intersect_ray(q)
		return a.distance_to(hit["position"]) if hit.size() > 0 else -1.0
	# 1. shelf closed: ray from room center toward the -X doorway hits
	# the BOOKSHELF (something within 0.8m of the wall plane)
	var d1: float = cast.call(Vector3(c.x, fy + 1.4, c.z - 2.0),
		Vector3(c.x - hx - 1.5, fy + 1.4, c.z - 2.0))
	print("HAROLD shelf blocks doorway: hit %.2f (< %.2f) %s" % [
		d1, hx + 0.6, "PASS" if d1 >= 0.0 and d1 < hx + 0.6 else "FAIL"])
	hh._harold_open_shelf()
	await get_tree().create_timer(3.0).timeout
	# 2. shelf open: the same ray now reaches into the corridor
	var d2: float = cast.call(Vector3(c.x, fy + 1.4, c.z - 2.0),
		Vector3(c.x - hx - 3.5, fy + 1.4, c.z - 2.0))
	print("HAROLD doorway opens: hit %.2f (miss or > %.2f) %s" % [
		d2, hx + 0.5, "PASS" if d2 < 0.0 or d2 > hx + 0.5 else "FAIL"])
	# 3. the shaft has a floor: drop a ray from the shaft top
	var shx := c.x - hx - 6.6
	var d3: float = cast.call(Vector3(shx, fy + 1.0, c.z - 2.0),
		Vector3(shx, fy - 40.0, c.z - 2.0))
	print("HAROLD shaft floored: hit %.2f (13.5-15.5: floor, not a cap) %s" % [
		d3, "PASS" if d3 > 13.5 and d3 < 15.5 else "FAIL"])
	# 4. riddle room floor exists
	var rcy := fy - 11.0 - 1.6
	var d4: float = cast.call(Vector3(shx, rcy, c.z - 7.6),
		Vector3(shx, rcy - 20.0, c.z - 7.6))
	print("HAROLD riddle room floored: hit %.2f (must hit) %s" % [
		d4, "PASS" if d4 >= 0.0 else "FAIL"])
	# 5. the riddle accepts its answer and the wall opens
	var want: String = House.RIDDLE_ITEMS[int(absi(Game.world_seed)) % 5]
	Inventory.add_res(want, 1)
	hh._harold_try_slot()
	print("HAROLD riddle solved with %s: wall_open=%s %s" % [
		want, str(Game.lime_wall_open),
		"PASS" if Game.lime_wall_open else "FAIL"])
	# 6. the prize is real and taking it works
	var lt9: Node = null
	for ch in hh._iroot.get_children():
		if ch is House.LimeTetra:
			lt9 = ch
	if lt9 != null:
		lt9.use()
	for ch3 in hh._iroot.get_children():
		if ch3 is Label3D and "BRING ME" in str(ch3.text):
			print("HAROLD riddle label: off=", ch3.global_position
				- (hh.room_center() + Vector3(0, 0, 0)), " rot=",
				ch3.rotation_degrees)
	var rc9 := Vector3(c.x - hx - 6.6, fy - 11.0 - 1.6, c.z - 2.0 - 5.6)
	var dwalk: float = cast.call(
		Vector3(rc9.x + 1.5, rc9.y - 0.9, rc9.z + 5.6),
		Vector3(rc9.x + 1.5, rc9.y - 0.9, rc9.z - 6.5))
	print("HAROLD walk path: hit %.1f (expect 9.0-10.4 = far wall) %s" % [
		dwalk, "PASS" if dwalk > 8.9 and dwalk < 10.5 else "FAIL"])
	var bkc := 0
	for ch2 in hh._hshelf.get_children():
		if ch2 is MeshInstance3D:
			bkc += 1
	print("HAROLD shelf meshes: %d (expect 70+) %s" % [bkc,
		"PASS" if bkc > 40 else "FAIL"])
	print("HAROLD lime tetra: found=%s count=%d %s" % [
		str(lt9 != null), Inventory.res_count("ltetra"),
		"PASS" if lt9 != null and Inventory.res_count("ltetra") == 1
		else "FAIL"])
	get_tree().quit()

## CTD_TEST=32: stand on the Big Computer atrium floor, look UP the
## shaft -- the way out must read OPEN (crust cut + sky at the top)
func _throat_shot() -> void:
	await get_tree().create_timer(4.0).timeout
	var b = Universe.body_named("Big Computer")
	var u0: Vector3 = MAINFRAME_DIR
	var cam := Camera3D.new()
	add_child(cam)
	var e1x := u0.cross(Vector3(0, 0, 1)).normalized()
	cam.global_position = b.center + u0 * (b.radius - 16.0 + 8.0) + e1x * 2.0
	cam.look_at(b.center + u0 * (b.radius + 30.0), e1x)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("THROATSHOT saved")
	get_tree().quit()

func _edge_shots() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().create_timer(1.0).timeout
	Game.monolith_stage = 8
	_on_monolith_advanced()
	if _boundary_mat != null:
		_boundary_mat.set_shader_parameter("reveal", 1.0)
	var cam := Camera3D.new()
	cam.far = 420000.0
	add_child(cam)
	cam.current = true
	var B := Universe.BOUNDARY
	cam.global_position = Vector3(B * 1.12, B * 0.05, 0)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/edge_outside.png")
	cam.global_position = Vector3(B * 0.35, 0, 0)
	cam.look_at(Vector3(B * 2.0, 0, 0), Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/edge_inside.png")
	print("EDGESHOT done")
	get_tree().quit()

## CTD_TEST=29: stand INSIDE the Pixel mouth, look outward + inward.
func _hole_shot() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().create_timer(1.0).timeout
	var b = Universe.body_named("Pixel")
	var u0: Vector3 = COLONY_DIRS["Pixel"]
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	# from INSIDE the shaft, 6m below the surface, looking OUT
	cam.global_position = b.center + u0 * (b.radius - 6.0)
	cam.look_at(b.center + u0 * (b.radius + 30.0), u0.cross(Vector3(0, 0, 1)).normalized())
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/hole_inside_out.png")
	# from the hollow, 25m below, looking UP at the mouth from inside
	cam.global_position = b.center + u0 * (b.radius - 25.0)
	cam.look_at(b.center + u0 * b.radius, u0.cross(Vector3(0, 0, 1)).normalized())
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/hole_hollow_up.png")
	print("HOLESHOT done")
	get_tree().quit()

## CTD_TEST=28: the README tour. Flies a camera to every showpiece and
## saves docs/shots/*.png.
func _readme_shots() -> void:
	# shot rig runs in a small window that never steals the screen
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().create_timer(3.0).timeout
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	var cam := Camera3D.new()
	cam.far = 60000.0
	add_child(cam)
	cam.current = true
	var mb = Universe.body_named("Big Computer")
	var mu: Vector3 = MAINFRAME_DIR
	var me1 := mu.cross(Vector3(0, 0, 1)).normalized()
	var me2 := mu.cross(me1).normalized()
	var mrF: float = mb.radius - 16.0
	var eb = Universe.body_named("Earth")
	var hb = Universe.body_named("Harold")
	var bh = Universe.body_named("TIN 618")
	var wb = Universe.body_named("Undros")
	var db = Universe.body_named("Datamosh")
	var mdd := (mu * cos(0.115 + 5.0 * 4.6 / mrF)
		+ me1 * sin(0.115 + 5.0 * 4.6 / mrF)).normalized()
	var cpd := (mu * cos(1.3708) + me1 * sin(1.3708)).normalized()
	var shots: Array = [
		["big_computer_orbit", mb.center + mu * (mb.radius + 150.0)
			+ me1 * 60.0, mb.center, mu.cross(me1)],
		["control_deck", mb.center + (mu * cos(0.115) + me1 * sin(0.115))
			.normalized() * (mrF + 2.2), mb.center + mdd * (mrF + 2.0),
			(mu * cos(0.3) + me1 * sin(0.3)).normalized()],
		["reactor_cavern", mb.center + cpd * (mrF + 1.8)
			- (-mu * sin(1.3708) + me1 * cos(1.3708)) * 12.0,
			mb.center + cpd * (mb.radius - 25.0), cpd],
		["cockpit", mb.center - mu * (mrF + 2.0) + me1 * 8.0,
			mb.center - mu * (mrF + 3.0), -mu],
		["earth", eb.center + Vector3(1, 0.35, 0.4).normalized()
			* (eb.radius + 130.0), eb.center, Vector3(0, 1, 0)],
		["black_hole_harold", hb.center + Vector3(0, 0.25, 1).normalized()
			* (hb.radius + 220.0), bh.center, Vector3(0, 1, 0)],
		["undros", wb.center + Vector3(0.4, 0.6, 0.6).normalized()
			* (wb.radius + 160.0), wb.center, Vector3(0, 1, 0)],
		["datamosh", db.center + Vector3(0.2, 0.5, 0.9).normalized()
			* (db.radius + 170.0), db.center, Vector3(0, 1, 0)],
	]
	for sh9 in shots:
		cam.global_position = sh9[1]
		cam.look_at(sh9[2], sh9[3])
		await get_tree().create_timer(0.35).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://docs/shots/%s.png" % str(sh9[0]))
		print("READMESHOT ", sh9[0])
	print("READMESHOT done")
	get_tree().quit()
	get_tree().quit()

## square entrance. CTD_SHOT names the png.
func _mouth_shot_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var b = Universe.body_named("Pixel")
	var u0: Vector3 = COLONY_DIRS["Pixel"]
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = b.center + u0 * (b.radius + 30.0)
	cam.look_at(b.center + u0 * b.radius, u0.cross(Vector3(0, 0, 1)).normalized())
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CTD_SHOT"))
	print("MOUTHSHOT saved")
	# second angle: inside a Wireframe apartment pod, corner view
	var wb = Universe.body_named("Wireframe")
	var wu: Vector3 = COLONY_DIRS["Wireframe"]
	var we1 := wu.cross(Vector3(0, 0, 1)).normalized()
	var aang := TAU * 3.0 / 28.0
	var apdir := (wu * cos(aang) + we1 * sin(aang)).normalized()
	var atang := (-wu * sin(aang) + we1 * cos(aang)).normalized()
	var asidev := apdir.cross(atang).normalized() * -1.0
	var arc: Vector3 = wb.center + apdir * (wb.radius - 13.0) + asidev * 7.8
	var abas := Basis(asidev, apdir, atang * -1.0).orthonormalized()
	cam.global_position = arc + abas * Vector3(-3.6, 1.7, -3.4)
	cam.look_at(arc + abas * Vector3(1.7, -1.5, 0.8), apdir)
	await get_tree().create_timer(0.6).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png(OS.get_environment("CTD_SHOT").replace(".png", "_apt.png"))
	print("MOUTHSHOT apt saved")
	# third: the Mainframe control deck, looking down the curve
	var mb = Universe.body_named("Big Computer")
	var mu: Vector3 = MAINFRAME_DIR
	var me1 := mu.cross(Vector3(0, 0, 1)).normalized()
	var mrF: float = mb.radius - 16.0
	var ma := 0.115 + (4.6 / mrF) * 2.0
	var mpd := (mu * cos(ma) + me1 * sin(ma)).normalized()
	var mtd := (-mu * sin(ma) + me1 * cos(ma)).normalized()
	var mla := ma + 0.22
	cam.global_position = mb.center + mpd * (mrF + 2.8) - mtd * 1.0
	cam.look_at(mb.center
		+ (mu * cos(mla) + me1 * sin(mla)).normalized() * (mrF + 1.4), mpd)
	await get_tree().create_timer(0.6).timeout
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png(OS.get_environment("CTD_SHOT").replace(".png", "_deck.png"))
	print("MOUTHSHOT deck saved")
	# fourth: Big Computer from orbit -- the hull must read as BUILT
	var ov := (mu + mu.cross(Vector3(0, 0, 1)).normalized() * 0.9).normalized()
	cam.global_position = mb.center + ov * (mb.radius * 2.7)
	cam.look_at(mb.center, mu)
	await get_tree().create_timer(0.6).timeout
	var img4 := get_viewport().get_texture().get_image()
	img4.save_png(OS.get_environment("CTD_SHOT").replace(".png", "_orbit.png"))
	print("MOUTHSHOT orbit saved")

func _dish_test() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var r := RadioTower.new()
	add_child(r)
	r.set_meta("placed_id", "radio")
	var b = Universe.nearest(_player.global_position)
	var up: Vector3 = (_player.global_position - b.center).normalized()
	r.global_transform = Transform3D(_basis_from_up(up),
		_player.global_position + _player.global_transform.basis.x * 4.0)
	# mimic the restore path: aim + track arrive a beat later
	await get_tree().create_timer(0.3).timeout
	r.aim_dir = (Universe.body_named("Circuitia").center - r.global_position).normalized()
	r.track_body = Universe.body_named("Circuitia")
	var last := Vector3.INF
	for i in 60:
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(r) or r._dish_pivot == null:
			break
		var rim: Vector3 = r._dish_pivot.global_transform * Vector3(0, 0, -0.85)
		if last != Vector3.INF and rim.distance_to(last) > 0.004:
			print("DISHTEST t=%.2f jump=%.4f rim=%v pivot=%v" % [float(i) * 0.05,
				rim.distance_to(last), rim, r._dish_pivot.global_position])
		last = rim
	print("DISHTEST done")

func _nuke_test() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var rx := EMachines.NuclearReactor.new()
	add_child(rx)
	rx.set_meta("placed_id", "nreactor")
	var b = Universe.nearest(_player.global_position)
	var up: Vector3 = (_player.global_position - b.center).normalized()
	rx.global_transform = Transform3D(_basis_from_up(up),
		_player.global_position + _player.global_transform.basis.x * 5.0)
	await get_tree().process_frame
	rx._meltdown()   # straight to the bad ending
	await get_tree().create_timer(1.5).timeout
	var cam := get_viewport().get_camera_3d()
	var mc = get_tree().current_scene.find_children("*", "MushroomCloud", true, false)
	print("NUKETEST dead=%s cam=%s cam_parent=%s clouds=%d" % [Game.dead,
		cam.get_class() if cam else "none",
		cam.get_parent().get_class() if cam and cam.get_parent() else "none",
		mc.size()])
	if mc.size() > 0 and cam != null:
		var cl: Node3D = mc[0]
		var toward: Vector3 = (cl.global_position - cam.global_position).normalized()
		print("NUKETEST cam_dist=%.1f facing_dot=%.2f cloud_pos_ok=%s" % [
			cam.global_position.distance_to(cl.global_position),
			(-cam.global_transform.basis.z).dot(toward),
			cl.global_position.distance_to(b.center) > float(b.radius) * 0.9])
		print("NUKETEST cloud=%v camg=%v fwd=%v up=%v cloud_up=%v" % [
			cl.global_position, cam.global_position,
			-cam.global_transform.basis.z, cam.global_transform.basis.y,
			cl.global_transform.basis.y])
		print("NUKETEST cam_local=%v cam_parent_is_cloud=%s" % [cam.position,
			cam.get_parent() == cl])
	await get_tree().create_timer(3.0).timeout
	var cam2 := get_viewport().get_camera_3d()
	print("NUKETEST t+3s cam_parent=%s" % [cam2.get_parent().get_class() if cam2 and cam2.get_parent() else "none"])

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
	# R on the death screen, as a single press: the per-frame poll alone
	# missed it if the frame it landed on was busy
	if Game.dead and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_R:
		_do_respawn()
		return
	# F1: toggle clean-screenshot mode -- HUD and hand vanish, F1 again
	# brings them back
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		Game.hud_hidden = not Game.hud_hidden
		if _hud:
			_hud.visible = not Game.hud_hidden
		var pl9 = get_tree().get_first_node_in_group("player")
		if pl9 != null and pl9._hand:
			pl9._hand.visible = pl9._view_mode == 0 and not Game.hud_hidden
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

var _bgm: AudioStreamPlayer = null
var _bgm_gap := 0.0
var _bgm_last := -1

var _rhot_t := 0.0
var _rhot := false

func _update_bgm(delta: float) -> void:
	if _bgm == null:
		return
	# a radio playing within earshot owns the airspace. The group scan
	# runs at 2.5Hz, not every frame -- radios don't teleport.
	_rhot_t -= delta
	if _rhot_t <= 0.0:
		_rhot_t = 0.4
		_rhot = false
		if _player != null:
			for r in get_tree().get_nodes_in_group("radio"):
				if r is RadioTower and is_instance_valid(r) \
						and r.global_position.distance_to(_player.global_position) < 45.0 \
						and ((r._talk != null and r._talk.playing) \
						or (r._hiss != null and r._hiss.playing)):
					# ANY radio noise counts -- static hiss included
					_rhot = true
					break
			# a running modular synth owns the airspace exactly like a
			# radio does: you cannot hear your patch over the soundtrack
			if not _rhot:
				for sy in get_tree().get_nodes_in_group("modsynth"):
					if sy is ModSynth and is_instance_valid(sy) and sy.powered \
							and sy._ply != null and sy._ply.playing \
							and sy.global_position.distance_to(_player.global_position) < 45.0:
						_rhot = true
						break
	var radio_hot := _rhot
	if _bgm.stream_paused:
		# the radio walked out of earshot: the song comes back mid-note
		if not radio_hot:
			_bgm.volume_db = -34.0
			_bgm.stream_paused = false
		return
	if _bgm.playing:
		# songs breathe: ~3s fade-in, ~4s fade-out at the natural end
		var want_db := -8.0
		if _outside_white:
			want_db = -60.0   # your music belongs to the universe
		var pos9 := _bgm.get_playback_position()
		var len9: float = _bgm.stream.get_length() if _bgm.stream != null else 0.0
		if pos9 < 3.0:
			want_db = lerpf(-34.0, -8.0, pos9 / 3.0)
		if len9 > 8.0 and len9 - pos9 < 4.0:
			want_db = lerpf(-8.0, -40.0, clampf((4.0 - (len9 - pos9)) / 4.0, 0.0, 1.0))
		want_db += Settings.music_db()   # the MUSIC VOLUME slider
		if radio_hot:
			want_db = -40.0
		_bgm.volume_db = lerpf(_bgm.volume_db, want_db, minf(1.0, delta * 2.5))
		if radio_hot and _bgm.volume_db < -38.0:
			_bgm.stream_paused = true   # HOLD the song -- it resumes where
			# it was when you leave the radio's range
		return
	if radio_hot:
		return
	_bgm_gap -= delta
	if _bgm_gap > 0.0:
		return
	# PURE chance every time: any track, never the same one twice in a
	# row -- and nothing about it saves, so a fresh launch predicts
	# nothing about what plays first
	var pick9 := randi() % RadioLib.custom_count()
	if RadioLib.custom_count() > 1 and pick9 == _bgm_last:
		pick9 = (pick9 + 1 + randi() % (RadioLib.custom_count() - 1)) \
			% RadioLib.custom_count()
	_bgm_last = pick9
	_bgm.stream = RadioLib.custom_track(pick9)
	_bgm.volume_db = -34.0   # fade-in starts from a whisper
	_bgm.play()
	# minecraft rules after that: songs are an EVENT, minutes apart
	_bgm_gap = randf_range(180.0, 420.0)

func _process(delta: float) -> void:
	_update_bgm(delta)
	_regen_crates(delta)
	_regen_ore(delta)
	_animate_avatars(delta)
	_update_stalkers(delta)
	# demographics: when the census dips, someone new steps off the rail
	# into a city. only while a player is around to live in
	_pop_t -= delta
	if _pop_t <= 0.0:
		_pop_t = randf_range(20.0, 40.0)
		_repopulate()
	var pos := _active_pos()
	_plod_t -= delta
	if _plod_t <= 0.0:
		_plod_t = 0.7
		_planet_lod_tick()
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
		var rvel := Vector3.ZERO
		var rv9 := _piloted_rocket()
		if Game.mode == Game.Mode.IN_ROCKET and rv9 != null:
			rvel = rv9.vel
		var rok9 := _piloted_rocket()
		Save.set_player_pos(pos, Game.mode == Game.Mode.IN_ROCKET, hyper, mk2,
			rvel, rok9.hyper_charge if rok9 != null else 4.0,
			rok9.nuclear if rok9 != null else false,
			rok9.edge_won if rok9 != null else false)
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
	if Game.zone != "" or pos.length() > Universe.BOUNDARY:
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
	# the white/starry split is pure GEOMETRY now (star ball inside the
	# boundary, white shell outside) -- position only decides the choir
	if Game.zone == "":
		var zr9 := pos.length()
		var wr9 := Universe.BOUNDARY * 1.5
		# three zones, hysteresis on both lines: universe / white / dark
		var zprev9 := _outzone
		if _outzone == 0 and zr9 > Universe.BOUNDARY + 50.0:
			_outzone = 1
		elif _outzone == 1 and zr9 < Universe.BOUNDARY - 50.0:
			_outzone = 0
		elif _outzone == 1 and zr9 > wr9 + 100.0:
			_outzone = 2
		elif _outzone == 2 and zr9 < wr9 - 100.0:
			_outzone = 1
		if _outzone != zprev9:
			_set_out_ambience()
		# THE WALL AT THE END OF THE DARK: 3.9x the boundary. Hitting it
		# is an EVENT: thud, flash, shake, bounce.
		var lim9 := Universe.BOUNDARY * 3.9
		_wall_fx_t = maxf(0.0, _wall_fx_t - delta)
		if zr9 > lim9:
			var an9 := _active_node()
			if an9 != null:
				var rd9: Vector3 = pos.normalized()
				(an9 as Node3D).global_position = rd9 * lim9
				if an9 is Rocket:
					an9.vel = (an9.vel as Vector3).bounce(rd9) * 0.25
					an9._cine_shake = maxf(an9._cine_shake, 0.9)
				elif "velocity" in an9:
					an9.velocity = (an9.velocity as Vector3) \
						.bounce(rd9) * 0.25
				if _wall_fx_t <= 0.0:
					_wall_fx_t = 1.2
					Sfx.play("rumble", -2.0)
					Sfx.play("hurt", -14.0)
					if _env_ref != null:
						var wtw9 := create_tween()
						wtw9.tween_property(_env_ref,
							"glow_intensity", 3.4, 0.08)
						wtw9.tween_property(_env_ref,
							"glow_intensity", 1.9, 0.7)
					if _hud:
						_hud.flash("the dark ends here.")
		var outside := _outzone >= 1
		if outside != _outside_white:
			_outside_white = outside
			for sh9 in _void_shells:
				(sh9 as Node3D).visible = outside
			if _env_ref != null:
				_env_ref.glow_intensity = 1.9 if outside else 0.8
				_env_ref.glow_bloom = 0.5 if outside else 0.25
		# THE EDGE OF THE WHITE: nothing weaker than a nuclear engine
		# leaves -- until the day one WINS. After that first full
		# escape the white zone stops pushing anybody, forever.
		if _wcut == 0 and not Game.white_beaten \
				and zr9 > Universe.BOUNDARY * 1.44:
			if Game.mode == Game.Mode.IN_ROCKET:
				var rr9: Rocket = null
				for rrr in get_tree().get_nodes_in_group("rocket"):
					if rrr is Rocket and rrr.piloted:
						rr9 = rrr
						break
				if rr9 != null and not rr9.edge_won:
					_wcut = 2 if rr9.nuclear else 1
					Game.timewarp = 1.0   # cutscenes run in real time
					_wcut_t = 0.0
					_wcut_r = rr9
					_wcut_p0 = rr9.global_position
					rr9.force_locked = true
					Sfx.play("rumble", -6.0)
					if _hud:
						_hud.flash("SOMETHING PUSHES BACK")
			elif _player != null and Game.mode == Game.Mode.ON_FOOT:
				# on foot the force just leans you home, no ceremony
				_player.velocity -= pos.normalized() * 80.0 * delta
		if _wcut > 0:
			_drive_edge_cutscene(delta)

	# the cracked sky follows you like a skybox
	for fx in _skyfx:
		if is_instance_valid(fx):
			(fx as Node3D).global_position = pos

	# UNDERWATER: inside an ocean world's water shell the whole screen
	# wobbles and drowns in blue fog, aquarium-style
	var wet := false
	if Game.zone == "":
		for ob9 in Universe.bodies:
			if ob9.kind == "ocean":
				var od9 := pos.distance_to(ob9.center)
				if od9 < ob9.radius - 0.5 and od9 > ob9.radius * 0.625:
					wet = true
	_set_underwater(wet)

	# the edge RESISTS first: over the last 1200m the boundary shoves
	# you back toward the center, harder the closer you get. Integrated,
	# the field stops anything slower than ~140 m/s -- come in hot
	# (overdrive, hyperdrive, a good burn) and you punch through to
	# meet the ME. Unless the sky is broken; then it is just space.
	if Game.zone == "" and Game.monolith_stage < 8:
		var edge_d := Universe.BOUNDARY - pos.length()
		if edge_d < 1200.0:
			var node0 := _active_node()
			if node0 != null and "velocity" in node0:
				var push := clampf(1.0 - edge_d / 1200.0, 0.0, 1.0)
				node0.velocity += -pos.normalized() * push * push * 25.0 \
					* get_physics_process_delta_time()
	if Game.zone == "" and pos.length() > Universe.BOUNDARY \
			and Game.monolith_stage < 8:
		# crossing the edge ANGERS the god -- but the colossal hand only
		# comes when he is already SUPER angry. Once you are OUT, space
		# itself lets you be: no shove follows you (leaving your rocket
		# out there used to catapult you home), only the wrath ledger
		# and, eventually, the hand.
		var node := _active_node()
		if not _threw_back:
			_threw_back = true
			Game.anger(15.0)
			if Game.wrath >= 70.0 and node != null \
					and Game.playtime >= Game.god_restrained_until:
				var gh := GodHand.new()
				add_child(gh)
				gh.begin(node, Vector3.ZERO)
				if _hud:
					_hud.flash("the god hurls you back. the sky is not broken yet")
	else:
		_threw_back = false

	# --- TIN 618 time dilation. No death screen: you just... slow. Forever. ---
	var bh := Universe.body_named("TIN 618")
	if bh:
		var d := pos.distance_to(bh.center)
		var horizon := bh.radius
		# dilation hugs the event horizon -- not a system-wide field
		var influence := horizon * 2.2
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
				Game.hurt(100000.0, true, str(b.name))   # star deaths vaporize your items
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
				Game.hurt(100000.0, true, str(b.name) + "'s clouds")
			elif gd < b.radius:
				Game.hurt(22.0 * delta, false, str(b.name) + "'s clouds")
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and is_instance_valid(r) and not r.piloted \
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
		_do_respawn()

## R on the death screen, whether it arrives as a held key or a single
## press -- the poll alone missed it if the frame it landed on was busy.
func _do_respawn() -> void:
	if not Game.dead:
		return
	if true:
		Engine.time_scale = 1.0
		if Game.permadead:
			get_tree().change_scene_to_file("res://Title.tscn")
		else:
			# death sends you HOME (or to your chosen beacon) -- never
			# back to the spot that just killed you. IN PLACE now: the
			# world is already built and unchanged, so there is nothing
			# to reload and no loading screen to sit through -- save,
			# reset, restore, teleport, done.
			Game.zone = ""
			if _world_load_ok:
				Save.set_world(collect_world())
			Save.set_player_pos(Game.spawn_pos + Game.spawn_up * 1.5, false, false)
			Save.save_progress()
			Game.reset()
			Save.apply_progress()
			_monolith_snap()
			if _player != null and is_instance_valid(_player):
				_player.respawn_at(Game.spawn_pos + Game.spawn_up * 1.5,
					Game.spawn_up)
				_player.restore_jet()

var _refocus_capture := false

func _notification(what: int) -> void:
	# window loses focus (alt-tab, click away): free the mouse so it is
	# never stuck in a windowed game; recapture on the way back in
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_refocus_capture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if _refocus_capture:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _refocus_capture:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_refocus_capture = false
		# focused game belongs on TOP -- no file explorer floating over it
		DisplayServer.window_move_to_foreground()
	# window closed mid-run: save the exact position on the way out
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.quitting = true   # cooked audio mid-flight must NOT land in
		# freed nodes -- that was the heap-corruption abort on exit
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
		RadioLib._varn_wav = null
		RadioLib._bh_presence_wav = null
		RadioLib._ice_wav = null
		RadioLib._custom.clear()
		RadioLib._custom_loaded = false
		EarthHuman._faces.clear()   # face textures held past teardown
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
		var rvel2 := Vector3.ZERO
		var rvA := _piloted_rocket()
		if Game.mode == Game.Mode.IN_ROCKET and rvA != null:
			rvel2 = rvA.vel
		var rokA := _piloted_rocket()
		Save.set_player_pos(_active_pos(), Game.mode == Game.Mode.IN_ROCKET,
			hyper, mk2, rvel2, rokA.hyper_charge if rokA != null else 4.0,
			rokA.nuclear if rokA != null else false,
			rokA.edge_won if rokA != null else false)
		Save.save_progress()

func _piloted_rocket() -> Rocket:
	for r in get_tree().get_nodes_in_group("rocket"):
		if r is Rocket and r.piloted:
			return r
	return null

func _active_node() -> Node:
	if Game.mode == Game.Mode.IN_ROCKET:
		# the FLOWN ship, not whichever parked hull joined the group first
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and r.piloted:
				return r
	var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
	return get_tree().get_first_node_in_group(g)

func _active_pos() -> Vector3:
	var n := _active_node()
	return n.global_position if n else Vector3.ZERO

# ------------------------------------------------------------- universe

var _env_ref: Environment = null
var _outside_white := false
var _void_amb: AudioStreamPlayer = null
var _dark_amb: AudioStreamPlayer = null
var _outzone := 0    # 0 universe · 1 white zone · 2 the dark
var _wcut := 0       # white-edge cutscene: 0 idle · 1 losing · 2 winning
var _wcut_t := 0.0
var _wcut_r: Rocket = null
var _wcut_p0 := Vector3.ZERO
var _wall_fx_t := 0.0

## the sound of the space OUTSIDE space: a vast slow choir that was
## here before the universe and will be here after. Detuned voice
## pairs beating against each other, a sub swell breathing underneath,
## and a thin silver shimmer far above.
func _void_ambience() -> AudioStreamWAV:
	var rate := 22050
	var secs := 14.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var ts := float(i) / float(rate)
		var v := 0.0
		# the choir: four voice-pairs, each pair detuned a few cents so
		# they BEAT slowly -- the classic endless-holy sound
		for vp in [[110.0, 0.09], [165.0, 0.07], [220.0, 0.06], [275.0, 0.05]]:
			var fq: float = vp[0]
			var amp: float = vp[1]
			# the detuned twin must land on an INTEGER cycle count per
			# loop or the seam clicks -- quantize it to the loop length
			var fq2: float = round(fq * 1.006 * secs) / secs
			var breathe := 0.6 + 0.4 * sin(TAU * ts / 14.0
				+ fq * 0.013)
			v += (sin(TAU * fq * ts) + sin(TAU * fq2 * ts)) \
				* amp * 0.5 * breathe
		# the sub swell: the void inhaling
		v += 0.10 * sin(TAU * (578.0 / secs) * ts) * (0.5 + 0.5 * sin(TAU * ts / 7.0))
		# silver shimmer, barely there
		v += 0.018 * sin(TAU * 1760.0 * ts + 3.0 * sin(TAU * ts / 7.0)) \
			* (0.5 + 0.5 * sin(TAU * ts / 7.0 + 2.0))
		var s9 := int(clampf(v, -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav

## the sound the universe makes when its god understands the sky is
## gone: one immense chord -- a dark open stack with bells ringing over
## it, swelling for two seconds and dying for ten. Nothing loops.
## crossfade the outer ambiences to match _outzone: the holy choir
## belongs to the white; past it, something deeper and calmer
func _set_out_ambience() -> void:
	if _outzone == 1:
		if _void_amb == null:
			_void_amb = AudioStreamPlayer.new()
			_void_amb.stream = _void_ambience()
			_void_amb.volume_db = -60.0
			add_child(_void_amb)
		if not _void_amb.playing:
			_void_amb.play()
		var vt := create_tween()
		vt.tween_property(_void_amb, "volume_db", -7.0, 3.0)
	elif _void_amb != null and _void_amb.playing:
		var vt2 := create_tween()
		vt2.tween_property(_void_amb, "volume_db", -60.0, 2.5)
		vt2.tween_callback(_void_amb.stop)
	if _outzone == 2:
		if _dark_amb == null:
			_dark_amb = AudioStreamPlayer.new()
			_dark_amb.stream = _dark_ambience()
			_dark_amb.volume_db = -60.0
			add_child(_dark_amb)
		if not _dark_amb.playing:
			_dark_amb.play()
		var dt := create_tween()
		dt.tween_property(_dark_amb, "volume_db", -5.0, 4.0)
	elif _dark_amb != null and _dark_amb.playing:
		var dt2 := create_tween()
		dt2.tween_property(_dark_amb, "volume_db", -60.0, 2.5)
		dt2.tween_callback(_dark_amb.stop)

## the white-edge cutscene, both endings. The ship strains, the force
## answers. Weak engines get walked home; the nuclear one wins.
func _drive_edge_cutscene(delta: float) -> void:
	var r := _wcut_r
	if r == null or not is_instance_valid(r) or not r.piloted:
		if r != null and is_instance_valid(r):
			r.force_locked = false
			r._cine_shake = 0.0
			r._cine_fov = 0.0
		_wcut = 0
		_wcut_r = null
		return
	Game.timewarp = 1.0   # no fast-forwarding the hand
	_wcut_t += delta
	var t9 := _wcut_t
	var out9 := _wcut_p0.normalized()
	if _wcut == 1:
		# LOSING: 5s pinned at the edge, engines screaming into a hand
		# that does not care -- then flung the whole way home, easing
		# out so the arrival is gentle
		if t9 < 5.0:
			r._cine_shake = 0.12 + t9 * 0.14
			r._cine_fov = t9 * 2.4
			r.vel = r.vel.lerp(Vector3.ZERO, delta * 2.2)
			r.global_position = r.global_position.lerp(_wcut_p0, delta * 2.0)
			if fmod(t9, 1.1) < delta:
				Sfx.play("rumble", -10.0 + t9)
		elif t9 < 14.0:
			var k9 := (t9 - 5.0) / 9.0
			var e9 := k9 * k9 * (3.0 - 2.0 * k9)
			var tgt := Game.spawn_pos + Game.spawn_up * 60.0
			r.global_position = _wcut_p0.lerp(tgt, e9)
			r.vel = (tgt - _wcut_p0) * (6.0 * k9 * (1.0 - k9)) / 9.0
			r._cine_shake = maxf(0.05, 0.8 * (1.0 - k9))
			r._cine_fov = maxf(0.0, 12.0 * (1.0 - k9))
		else:
			r.vel = Vector3.ZERO
			r.force_locked = false
			r._cine_shake = 0.0
			r._cine_fov = 0.0
			if _hud:
				_hud.flash("the white zone refused you. all the way home.")
			var nt9 := create_tween()
			nt9.tween_interval(3.4)
			nt9.tween_callback(func() -> void:
				if _hud:
					_hud.flash("NUCLEAR ENGINE available -- Rocket 2.0 ship part, bought with uranium. it can win."))
			_wcut = 0
			_wcut_r = null
	else:
		# WINNING: eight seconds of escalating violence -- shake
		# climbing, rumbles arriving faster and louder -- and then the
		# NUCLEAR ENGINE simply wins
		if t9 < 8.0:
			r._cine_shake = 0.15 + t9 * 0.22
			r._cine_fov = t9 * 3.2
			r.vel = r.vel.lerp(Vector3.ZERO, delta * 1.6)
			r.global_position = r.global_position.lerp(_wcut_p0, delta * 1.6)
			if fmod(t9, maxf(0.25, 1.0 - t9 * 0.09)) < delta:
				Sfx.play("rumble", -12.0 + t9 * 1.3)
		else:
			r.edge_won = true
			Game.white_beaten = true
			_white_force_break(r.global_position)
			r.force_locked = false
			r._cine_shake = 0.0
			r._cine_fov = 0.0
			r.vel = out9 * 1500.0
			Sfx.play("warp", -2.0)
			Sfx.play("nuke", -20.0)
			if _hud:
				_hud.flash("THE NUCLEAR ENGINE WINS. THE DARK IS YOURS.")
			_wcut = 0
			_wcut_r = null

## the moment the nuclear engine wins: the invisible force becomes
## VISIBLE for one second -- a vast white membrane flashing across the
## whole edge -- then it tears at the breach and dies. Disabled, shown.
func _white_force_break(at: Vector3) -> void:
	# 1. the membrane: the entire force-sphere lights up and bleeds out
	var mem := MeshInstance3D.new()
	var msm := SphereMesh.new()
	msm.radius = Universe.BOUNDARY * 1.47
	msm.height = msm.radius * 2.0
	msm.radial_segments = 48
	msm.rings = 24
	mem.mesh = msm
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.albedo_color = Color(1, 1, 1, 0.0)
	mmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mem.material_override = mmat
	mem.extra_cull_margin = 999999.0
	add_child(mem)
	mem.global_position = Vector3.ZERO
	var mt := mem.create_tween()
	mt.tween_property(mmat, "albedo_color:a", 0.22, 0.15)
	mt.tween_property(mmat, "albedo_color:a", 0.0, 2.6)
	mt.tween_callback(mem.queue_free)
	# 2. the tear: two shock rings blasting outward from the breach
	var rd := at.normalized()
	var rb := _basis_from_up(rd)
	for k9 in 2:
		var ring := MeshInstance3D.new()
		var tm9 := TorusMesh.new()
		tm9.inner_radius = 0.9
		tm9.outer_radius = 1.0
		ring.mesh = tm9
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(1, 1, 1, 0.85)
		rmat.emission_enabled = true
		rmat.emission = Color(1, 1, 1)
		rmat.emission_energy_multiplier = 2.0
		ring.material_override = rmat
		ring.extra_cull_margin = 999999.0
		add_child(ring)
		ring.global_transform = Transform3D(rb, at)
		ring.scale = Vector3.ONE * 40.0
		var rt9 := ring.create_tween()
		rt9.tween_interval(0.12 * float(k9))
		rt9.tween_property(ring, "scale",
			Vector3.ONE * (5200.0 - 1600.0 * float(k9)), 2.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt9.parallel().tween_property(rmat, "albedo_color:a", 0.0, 2.2)
		rt9.tween_callback(ring.queue_free)
	# 3. torn scraps of the force, fleeing the hole
	var srng := RandomNumberGenerator.new()
	srng.seed = 777
	for i in 26:
		var sc := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(srng.randf_range(60.0, 180.0),
			srng.randf_range(60.0, 200.0), 4.0)
		sc.mesh = pm
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(1, 1, 1, 0.8)
		sc.material_override = smat
		sc.extra_cull_margin = 999999.0
		add_child(sc)
		sc.global_position = at
		sc.rotation = Vector3(srng.randf() * TAU, srng.randf() * TAU, 0)
		var dirn := (rd + Vector3(srng.randf_range(-0.9, 0.9),
			srng.randf_range(-0.9, 0.9),
			srng.randf_range(-0.9, 0.9))).normalized()
		var st9 := sc.create_tween()
		st9.tween_property(sc, "global_position",
			at + dirn * srng.randf_range(1500.0, 4200.0),
			srng.randf_range(1.4, 2.6)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st9.parallel().tween_property(smat, "albedo_color:a", 0.0,
			srng.randf_range(1.4, 2.6))
		st9.tween_callback(sc.queue_free)
	if _hud:
		var ft9 := create_tween()
		ft9.tween_interval(2.2)
		ft9.tween_callback(func() -> void:
			if _hud:
				_hud.flash("the force at the edge is BROKEN. it will not push anyone again"))

func _dark_ambience() -> AudioStreamWAV:
	var rate := 22050
	var secs := 16.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var ts := float(i) / float(rate)
		var v := 0.0
		# deep drone pair, barely detuned -- an octave up from where it
		# was: 37Hz was felt, not heard. 74Hz is a voice.
		v += 0.16 * sin(TAU * (1176.0 / secs) * ts) \
			* (0.6 + 0.4 * sin(TAU * ts / 16.0))
		v += 0.14 * sin(TAU * (1184.0 / secs) * ts)
		v += 0.08 * sin(TAU * (2352.0 / secs) * ts) \
			* (0.6 + 0.4 * sin(TAU * ts / 16.0 + 1.3))
		# a soft open fifth far above: vast, calm, empty -- not evil
		v += 0.05 * sin(TAU * (3520.0 / secs) * ts) \
			* (0.5 + 0.5 * sin(TAU * ts / 8.0))
		v += 0.04 * sin(TAU * (5280.0 / secs) * ts) \
			* (0.5 + 0.5 * sin(TAU * ts / 8.0 + 2.1))
		var s9 := int(clampf(v, -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav

func _god_chord() -> AudioStreamWAV:
	var rate := 22050
	var secs := 12.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var ts := float(i) / float(rate)
		var env := pow(minf(ts / 2.2, 1.0), 1.6) \
			* exp(-maxf(ts - 2.2, 0.0) * 0.38)
		var v := 0.0
		for pt in [[73.42, 0.20], [110.0, 0.16], [146.83, 0.13],
				[174.61, 0.10], [220.0, 0.08]]:
			var f0: float = pt[0]
			var a0: float = pt[1]
			var vib := 1.0 + 0.004 * sin(TAU * 4.5 * ts + f0)
			v += sin(TAU * f0 * vib * ts) * a0
			v += sin(TAU * f0 * 2.0 * vib * ts) * a0 * 0.35
		v += 0.10 * sin(TAU * 587.3 * ts) * exp(-ts * 0.9)
		v += 0.07 * sin(TAU * 987.8 * ts) * exp(-ts * 1.3)
		v += 0.05 * sin(TAU * 1567.9 * ts) * exp(-ts * 1.7)
		v *= env
		var s9 := int(clampf(v, -1.0, 1.0) * 32000.0)
		data[i * 2] = s9 & 0xFF
		data[i * 2 + 1] = (s9 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	_env_ref = env
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

## -------------------------------------------------- PLANET LOD
## Far planets do not deserve per-pixel noise shaders: past ~30 radii
## the detailed material swaps for a FLAT color. Only what is close is
## expensive (and the noodle god is never a planet).
var _plod: Array = []
var _plod_t := 0.0

func _register_planet_lod(b, mi: MeshInstance3D) -> void:
	var flat := StandardMaterial3D.new()
	flat.albedo_color = b.color
	flat.roughness = 1.0
	if b.kind == "sun":
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.emission_enabled = true
		flat.emission = b.color
		flat.emission_energy_multiplier = 1.4
	elif b.kind == "blind":
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plod.append({"b": b, "mi": mi, "det": mi.material_override,
		"flat": flat, "is_flat": false})

func _planet_lod_tick() -> void:
	var pos := _active_pos()
	for e9 in _plod:
		var mi9: MeshInstance3D = e9["mi"]
		if not is_instance_valid(mi9):
			continue
		var b9 = e9["b"]
		var far9: bool = pos.distance_to(b9.center) \
			> maxf(float(b9.radius) * 30.0, 9000.0 * Universe.world_scale)
		if far9 != bool(e9["is_flat"]):
			e9["is_flat"] = far9
			mi9.material_override = e9["flat"] if far9 else e9["det"]

## one sweep after the world is built: every SMALL mesh gets a Godot
## visibility range so distant clutter (spikes, props, facility guts,
## signs) stops issuing draw calls from across the universe
func _lod_sweep(n: Node = null) -> void:
	if n == null:
		n = self
	# the player's own kit draws at any range it likes
	if n is Rocket or n is Player:
		return
	if n is GeometryInstance3D and not (n is CSGShape3D):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			var sz := 100000.0
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
				sz = (gi as MeshInstance3D).get_aabb().size.length() \
					* maxf(gi.scale.length() / 1.732, 1.0)
			elif gi is Label3D:
				sz = 8.0
			if sz < 60.0:
				gi.visibility_range_end = 5500.0 + sz * 40.0
			elif sz < 700.0:
				gi.visibility_range_end = 42000.0
	for c9 in n.get_children():
		_lod_sweep(c9)

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
	mi.material_override = _planet_material(b.kind, b.color, b.name)
	p.add_child(mi)
	_register_planet_lod(b, mi)
	var col := CollisionShape3D.new()
	var hole_specs: Array = []   # [dir, cut radius in metres]
	if MINE_DIRS.has(b.name):
		hole_specs.append([MINE_DIRS[b.name], 4.8])
	if COLONY_DIRS.has(b.name):
		hole_specs.append([COLONY_DIRS[b.name], 4.8])
	if b.name == "Big Computer":
		hole_specs.append([MAINFRAME_DIR, 4.8])
	if hole_specs.size() > 0:
		# Holed planet (mine mouths, colony mouths): BOTH the collider and
		# the VISIBLE mesh are a shell with every mouth cut out.
		# cut holes of near-CONSTANT radius regardless of planet size
		# (a fixed angle made huge walk-through gaps on big planets)
		for hs in hole_specs:
			hs.append(cos(float(hs[1]) / b.radius))
		var faces := sm.get_faces()
		var kept := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var centroid := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			var cn := centroid.normalized()
			var cut := false
			for hs in hole_specs:
				if cn.dot(hs[0]) > float(hs[2]):
					cut = true
					break
			if cut:
				continue   # cut this mouth
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
		# ocean worlds: the WATER has no collider -- you sink through the
		# whole sea until the sand floor catches you
		cs.radius = b.radius * 0.62 if b.kind == "ocean" else b.radius
		col.shape = cs
	if b.kind == "ocean":
		# the SAND FLOOR: a real opaque seabed where the collider lives
		var sand := MeshInstance3D.new()
		var sam := SphereMesh.new()
		sam.radius = b.radius * 0.625
		sam.height = sam.radius * 2.0
		sam.radial_segments = 48
		sam.rings = 24
		sand.mesh = sam
		sand.material_override = _rocky_material(Color("#cbb475"), 0.0, 5.0)
		p.add_child(sand)
		# CLOUDS: a thin drifting shell over the water
		var cl9 := MeshInstance3D.new()
		var clm9 := SphereMesh.new()
		clm9.radius = b.radius * 1.13
		clm9.height = clm9.radius * 2.0
		clm9.radial_segments = 48
		clm9.rings = 24
		cl9.mesh = clm9
		var csh9 := Shader.new()
		csh9.code = "shader_type spatial;\nrender_mode cull_disabled;\n" \
			+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	float cv = fbm(n * 5.0 + vec3(TIME * 0.012, 0.0, TIME * 0.007));
	float cl = smoothstep(0.52, 0.72, cv);
	ALBEDO = vec3(0.96, 0.98, 1.0);
	ALPHA = cl * 0.75;
	ROUGHNESS = 1.0;
}
"""
		var cmt9 := ShaderMaterial.new()
		cmt9.shader = csh9
		cmt9.render_priority = 2   # clouds draw AFTER the water: no
								   # transparency-sort flicker with it
		cl9.material_override = cmt9
		p.add_child(cl9)
	if b.kind == "ocean":
		# FISHIES: thirty of them, orbiting the deep on their own tilted
		# rings, nose-first, forever
		var frng := RandomNumberGenerator.new()
		frng.seed = 4242
		for fi9 in 30:
			var pivot := Node3D.new()
			p.add_child(pivot)
			pivot.rotation = Vector3(frng.randf() * TAU, frng.randf() * TAU,
				frng.randf() * TAU)
			var fish9 := Node3D.new()
			pivot.add_child(fish9)
			var forb: float = b.radius * frng.randf_range(0.66, 0.96)
			fish9.position = Vector3(forb, 0, 0)
			var fcol9: Color = [Color("#ffcf40"), Color("#ff6a6a"),
				Color("#7df9ff"), Color("#66ff99"), Color("#ff66aa"),
				Color("#b388ff")][fi9 % 6]
			var fsc := frng.randf_range(0.8, 2.6)
			var fbody9 := MeshInstance3D.new()
			var fcm9 := CapsuleMesh.new()
			fcm9.radius = 0.14 * fsc
			fcm9.height = 0.8 * fsc
			fbody9.mesh = fcm9
			fbody9.rotation_degrees = Vector3(0, 0, 90)
			fbody9.scale = Vector3(1.0, 0.55, 1.0)
			fbody9.material_override = Destructible.make_material(fcol9, 1.1)
			fish9.add_child(fbody9)
			var ftail9 := MeshInstance3D.new()
			var ftm9 := BoxMesh.new()
			ftm9.size = Vector3(0.05, 0.3, 0.3) * fsc
			ftail9.mesh = ftm9
			ftail9.position = Vector3(0.5 * fsc, 0, 0)
			ftail9.rotation_degrees = Vector3(0, 90, 0)
			ftail9.material_override = Destructible.make_material(
				fcol9.darkened(0.2), 0.9)
			fish9.add_child(ftail9)
			# swim: the pivot turns forever; nose leads (-X of orbit)
			fish9.rotation_degrees = Vector3(0, 180, 0)
			var ftw := pivot.create_tween().set_loops()
			ftw.tween_property(pivot, "rotation:y", TAU,
				frng.randf_range(70.0, 220.0) / fsc).as_relative()
	if b.kind == "ocean":
		# MEGAFAUNA: three big things share the deep with the fishies
		var mrng := RandomNumberGenerator.new()
		mrng.seed = 777
		# 1. THE WHALE: twenty meters of slow blue patience
		var wpiv := Node3D.new()
		p.add_child(wpiv)
		wpiv.rotation = Vector3(0.4, 1.1, 0.2)
		var whale9 := Node3D.new()
		wpiv.add_child(whale9)
		whale9.position = Vector3(b.radius * 0.8, 0, 0)
		whale9.rotation_degrees = Vector3(0, 180, 0)
		var wb9 := MeshInstance3D.new()
		var wcm9 := CapsuleMesh.new()
		wcm9.radius = 3.4
		wcm9.height = 20.0
		wb9.mesh = wcm9
		wb9.rotation_degrees = Vector3(0, 0, 90)
		wb9.scale = Vector3(1.0, 0.7, 1.0)
		wb9.material_override = Destructible.make_material(Color("#3a6fae"), 0.8)
		whale9.add_child(wb9)
		var wbe9 := MeshInstance3D.new()
		var wbc9 := CapsuleMesh.new()
		wbc9.radius = 2.2
		wbc9.height = 14.0
		wbe9.mesh = wbc9
		wbe9.rotation_degrees = Vector3(0, 0, 90)
		wbe9.position = Vector3(0.8, -1.6, 0)
		wbe9.material_override = Destructible.make_material(Color("#cfd8e2"), 0.6)
		whale9.add_child(wbe9)
		var wt9 := MeshInstance3D.new()
		var wtm9 := BoxMesh.new()
		wtm9.size = Vector3(0.5, 0.6, 6.4)
		wt9.mesh = wtm9
		wt9.position = Vector3(11.6, 0, 0)
		wt9.material_override = Destructible.make_material(Color("#2a5288"), 0.7)
		whale9.add_child(wt9)
		var wtw9 := wpiv.create_tween().set_loops()
		wtw9.tween_property(wpiv, "rotation:y", TAU, 420.0).as_relative()
		# 2. THE SERPENT: a fourteen-segment arc snaking its own ring
		var spiv := Node3D.new()
		p.add_child(spiv)
		spiv.rotation = Vector3(1.9, 0.3, 0.8)
		for si9 in 14:
			var sseg := MeshInstance3D.new()
			var scm9 := CapsuleMesh.new()
			scm9.radius = 1.5 - 0.08 * float(si9)
			scm9.height = 4.6
			sseg.mesh = scm9
			sseg.material_override = Destructible.make_material(
				Color("#3a8f5a") if si9 % 2 == 0 else Color("#2a6f42"), 0.8)
			spiv.add_child(sseg)
			var sang: float = float(si9) * (4.2 / (b.radius * 0.74))
			var srad: float = b.radius * 0.74 + sin(float(si9) * 0.8) * 1.6
			sseg.position = Vector3(cos(sang) * srad, sin(float(si9) * 0.6) * 2.2,
				sin(sang) * srad)
			sseg.rotation.y = -sang + PI * 0.5
			sseg.rotation_degrees.x = 90.0
		var stw9 := spiv.create_tween().set_loops()
		stw9.tween_property(spiv, "rotation:y", -TAU, 240.0).as_relative()
		# 3. THE CROWN JELLY: a six-meter bell drifting the shallows
		var jpiv := Node3D.new()
		p.add_child(jpiv)
		jpiv.rotation = Vector3(2.6, 0.9, 1.4)
		var jelly9 := Node3D.new()
		jpiv.add_child(jelly9)
		jelly9.position = Vector3(b.radius * 0.9, 0, 0)
		var jb9 := MeshInstance3D.new()
		var jbm9 := SphereMesh.new()
		jbm9.radius = 3.0
		jbm9.height = 4.0
		jbm9.is_hemisphere = true
		jb9.mesh = jbm9
		var jmat9 := StandardMaterial3D.new()
		jmat9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jmat9.albedo_color = Color(1.0, 0.5, 0.85, 0.4)
		jmat9.emission_enabled = true
		jmat9.emission = Color(1.0, 0.4, 0.8) * 0.5
		jb9.material_override = jmat9
		jelly9.add_child(jb9)
		for jt9 in 8:
			var tent9 := MeshInstance3D.new()
			var jtm9 := BoxMesh.new()
			jtm9.size = Vector3(0.16, 5.0, 0.16)
			tent9.mesh = jtm9
			tent9.position = Vector3(cos(TAU * float(jt9) / 8.0) * 1.7, -2.6,
				sin(TAU * float(jt9) / 8.0) * 1.7)
			tent9.material_override = Destructible.make_material(
				Color("#ff9ad9"), 0.7)
			jelly9.add_child(tent9)
		var jtw9 := jpiv.create_tween().set_loops()
		jtw9.tween_property(jpiv, "rotation:y", TAU, 520.0).as_relative()
	if b.kind != "gas":
		p.add_child(col)   # gas giants have NO surface. you fall in.
	else:
		col.free()   # orphaned colliders leak Jolt RIDs at exit
		# INSIDE a gas giant it is actually gas now: three nested haze
		# shells (backface) thicken toward a blind opaque core
		for gs9 in [[0.985, 0.45], [0.8, 0.75], [0.55, 1.0]]:
			var haze := MeshInstance3D.new()
			var hzm := SphereMesh.new()
			hzm.radius = b.radius * float(gs9[0])
			hzm.height = hzm.radius * 2.0
			hzm.radial_segments = 32
			hzm.rings = 16
			haze.mesh = hzm
			var hmat9 := StandardMaterial3D.new()
			hmat9.cull_mode = BaseMaterial3D.CULL_FRONT
			hmat9.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hmat9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hmat9.albedo_color = Color(b.color.r, b.color.g, b.color.b,
				float(gs9[1]))
			haze.material_override = hmat9
			p.add_child(haze)
	p.set_meta("body_name", b.name)   # the apple cinematic needs to find these
	add_child(p)
	p.global_position = b.center
	b.node = p   # movers (Harold) drag their visuals along

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
	EMISSION = base * rim * (0.8 + lick * 2.6) * 3.8;
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
	b.node = p   # movers (Harold) drag their visuals along
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
func _rocky_material(color: Color, cap: float = 0.0, texscale: float = 1.0) -> Material:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvarying vec3 vn;\nuniform vec3 base : source_color;\nuniform float capamt;\nuniform float tscale;\n" \
		+ _NOISE_GLSL + """
void vertex(){ vn = NORMAL; }
void fragment(){
	vec3 n = normalize(vn);
	float m1 = fbm(n * 7.0 * tscale);
	float m2 = fbm(n * 21.0 * tscale);
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
	m.set_shader_parameter("tscale", texscale)
	return m

## `pname` lets the named worlds wear their own weather (the Great Red
## Spot, the polar hexagon); anything else falls back to generic bands.
func _planet_material(kind: String, color: Color, pname: String = "") -> Material:
	match kind:
		"pixel", "datamosh", "wob", "contrast":
			return ShaderLib.make(kind, color)
		"dude":
			# the title screen's motherboard face, on a real planet:
			# copper traces cell by cell, glowing pads, pulsing
			var dsh := Shader.new()
			dsh.code = "shader_type spatial;\nuniform vec3 base : source_color;\n" \
				+ "uniform float clk = 1.0;\n" \
				+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	vec3 cell = floor(n * 9.0);
	vec3 f = fract(n * 9.0);
	float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float tr = 0.0;
	if (h < 0.34) { tr = step(abs(f.y - 0.5), 0.06); }
	else if (h < 0.67) { tr = step(abs(f.x - 0.5), 0.06); }
	else { tr = max(step(abs(f.x - 0.5), 0.06) * step(f.y, 0.5),
		step(abs(f.y - 0.5), 0.06) * step(f.x, 0.5)); }
	float pad = step(length(f.xy - vec2(0.5)), 0.11);
	vec3 board = base * (0.5 + 0.25 * fbm(n * 7.0));
	vec3 copper = vec3(0.85, 0.55, 0.2);
	vec3 col = mix(board, copper, clamp(tr, 0.0, 1.0) * 0.9);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.0 * clk + h * 12.0);
	// CURRENT: bright packets racing along the traces -- the visible
	// heartbeat the OVERCLOCK lever actually changes (x0.3 / x1 / x3)
	float lane = (h < 0.34) ? f.x : ((h < 0.67) ? f.y : f.x + f.y);
	float cur = tr * smoothstep(0.12, 0.0,
		abs(fract(lane * 2.0 - TIME * 0.8 * clk + h * 7.0) - 0.5));
	ALBEDO = col;
	EMISSION = vec3(0.3, 1.0, 0.5) * pad * (0.5 + pulse)
		+ copper * tr * 0.15
		+ vec3(1.0, 0.85, 0.3) * cur * (0.9 + 0.6 * pulse);
	METALLIC = tr * 0.7;
	ROUGHNESS = 0.5;
}
"""
			var dm9 := ShaderMaterial.new()
			dm9.shader = dsh
			dm9.set_shader_parameter("base", Vector3(color.r, color.g, color.b))
			return dm9
		"earth":
			return _earth_material()
		"luna", "mercury":
			# honest rock. the blinding-lamp moon experiment looked like a
			# glowing egg with craters -- reverted
			return _rocky_material(color)
		"harold":
			# big planet, small grain: 6x tighter noise so the rock still
			# reads as rock with your face against it
			return _rocky_material(color, 0.0, 6.0)
		"ocean":
			# open water all the way around: rolling swell, TRANSPARENT --
			# you can see the deep from orbit. There is no land up here.
			var osh := Shader.new()
			osh.code = preload("res://Title.gd")._TP_NOISE + """
uniform vec3 base : source_color;
void fragment(){
	vec3 n = normalize(vn);
	float sw = fbm(n * 6.0 + vec3(TIME * 0.05, 0.0, TIME * 0.03));
	float sw2 = fbm(n * 17.0 - vec3(0.0, TIME * 0.08, 0.0));
	vec3 deep = base * 0.45;
	vec3 watercol = mix(deep, base * 1.25, sw * 0.7 + sw2 * 0.3);
	float foam = smoothstep(0.72, 0.82, sw2);
	watercol = mix(watercol, vec3(0.85, 0.95, 1.0), foam * 0.35);
	if (FRONT_FACING) {
		// from OUTSIDE: honest blue-fog water -- translucent, deep-
		// tinted, foam riding the swell. (the wobble lives on the
		// fullscreen underwater effect, where it belongs)
		ALBEDO = watercol;
		ALPHA = 0.66;
	} else {
		// from UNDERNEATH: invisible until YOU are submerged, then a
		// ceiling of long smooth light-waves
		float wave = (0.5 + 0.5 * sin(n.x * 42.0 + n.y * 17.0 + TIME * 1.4))
			* (0.5 + 0.5 * sin(n.z * 36.0 - TIME * 1.1));
		ALBEDO = watercol * 0.25 * submerged
			+ vec3(0.10, 0.14, 0.18) * wave * submerged;
		ALPHA = clamp((0.12 + 0.3 * wave) * submerged, 0.0, 0.6);
	}
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	EMISSION = base * 0.05;
}
"""
			osh.code = "shader_type spatial;\nrender_mode cull_disabled;\n" \
				+ "uniform float submerged = 0.0;\n" \
				+ osh.code
			var om9 := ShaderMaterial.new()
			om9.shader = osh
			om9.set_shader_parameter("base", Vector3(color.r, color.g, color.b))
			_ocean_mats.append(om9)
			return om9
		"rogue":
			# Harold's rock gone WRONG: bone-grey crags like the old man,
			# but shadow bands crawl the surface, pale veins flicker like
			# something under the crust is thinking, and every so often
			# the whole face goes a shade too white
			var rsh := Shader.new()
			rsh.code = "shader_type spatial;\n" \
				+ "uniform vec3 base : source_color;\n" \
				+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	float rock = fbm(n * 9.0);
	float crag = fbm(n * 26.0);
	vec3 col = base * (0.3 + 0.45 * rock + 0.18 * crag);
	// frozen shadow bands: painted on the bone, going nowhere
	float band = 0.5 + 0.5 * sin(n.y * 6.0 + n.x * 3.0 + fbm(n * 3.0) * 2.0);
	col *= 0.68 + 0.32 * band;
	// dead pale veins, faint and still
	float vein = smoothstep(0.48, 0.5, abs(fract(fbm(n * 5.0) * 7.0) - 0.5));
	col = mix(col, vec3(0.82, 0.8, 0.76), (1.0 - vein) * 0.18);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
			var rgm9 := ShaderMaterial.new()
			rgm9.shader = rsh
			rgm9.set_shader_parameter("base", Vector3(color.r, color.g, color.b))
			return rgm9
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
			# THE REAL ONES, stylised: belts and zones alternate in their
			# own colours and stream in OPPOSITE directions, cloud
			# filaments stretch along each band, the shear lines curl, and
			# each world wears the feature it is actually known for --
			# Jupiter's Great Red Spot, Saturn's polar hexagon, Neptune's
			# dark spot and methane cirrus, Uranus' near-blank haze.
			var sh := Shader.new()
			sh.code = "shader_type spatial;\nrender_mode shadows_disabled;\n" \
				+ "uniform vec3 base : source_color;\n" \
				+ "uniform vec3 zone_c : source_color;\n" \
				+ "uniform vec3 belt_c : source_color;\n" \
				+ "uniform vec3 spot_c : source_color;\n" \
				+ "uniform float bands_n;\nuniform float turb;\n" \
				+ "uniform float spot_on;\nuniform float spot_lat;\n" \
				+ "uniform float spot_lon;\nuniform float spot_r;\n" \
				+ "uniform float hex_on;\nuniform float cirrus;\n" \
				+ "uniform float style;\nuniform float glow_amt;\n" \
				+ _NOISE_GLSL + """
float hashf(float x){ return fract(sin(x * 127.1) * 43758.5453); }
float gband(float lat, float c, float w){
	float d = (lat - c) / w;
	return exp(-d * d);
}

// where the DARK belts actually sit, per world, in radians of latitude.
// returns 0 = pale zone, 1 = dark belt. this is what makes each giant
// look like itself instead of like evenly spaced wallpaper.
float belts(float lat, float st){
	if (st < 0.5) {
		// Jupiter: wide pale equatorial zone, the two big equatorial
		// belts either side of it, then the temperate belts
		return clamp(gband(lat, 0.21, 0.085) * 1.0
			+ gband(lat, -0.26, 0.10) * 1.0
			+ gband(lat, 0.47, 0.055) * 0.75
			+ gband(lat, -0.55, 0.06) * 0.75
			+ gband(lat, 0.72, 0.05) * 0.5
			+ gband(lat, -0.75, 0.05) * 0.5, 0.0, 1.0);
	} else if (st < 1.5) {
		// Saturn: the same architecture, far softer and lower contrast
		return clamp(gband(lat, 0.24, 0.12) * 0.75
			+ gband(lat, -0.28, 0.13) * 0.75
			+ gband(lat, 0.55, 0.08) * 0.5
			+ gband(lat, -0.60, 0.08) * 0.5, 0.0, 1.0);
	} else if (st < 2.5) {
		// Uranus: essentially featureless, one faint polar collar
		return clamp(gband(lat, 0.62, 0.22) * 0.35
			+ gband(lat, -0.55, 0.25) * 0.25, 0.0, 1.0);
	} else if (st < 3.5) {
		// Neptune: a dark equatorial belt and two bright polar collars
		return clamp(gband(lat, 0.0, 0.20) * 0.85
			+ gband(lat, -0.62, 0.12) * 0.45
			+ gband(lat, 0.66, 0.12) * 0.45, 0.0, 1.0);
	}
	if (st < 4.5) {
		// Joule: tight fast jets, many of them, and a wide dark
		// equatorial belt where the glow comes from
		return clamp(gband(lat, 0.0, 0.16) * 0.9
			+ gband(lat, 0.34, 0.07) * 0.8
			+ gband(lat, -0.38, 0.07) * 0.8
			+ gband(lat, 0.66, 0.05) * 0.6
			+ gband(lat, -0.70, 0.05) * 0.6, 0.0, 1.0);
	}
	// anonymous giant: rhythmic, but still uneven
	return clamp(gband(lat, 0.18, 0.11) + gband(lat, -0.30, 0.12) * 0.9
		+ gband(lat, 0.60, 0.07) * 0.7 + gband(lat, -0.66, 0.07) * 0.7,
		0.0, 1.0);
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float t = TIME;
	vec3 white = vec3(1.0, 0.98, 0.95);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.z, n.x);
	// --- the named storm, and the way it drags the flow around itself
	float eye = 0.0; float spin = 0.0; float wall = 0.0;
	if (spot_on > 0.5) {
		vec2 d = vec2((lon - spot_lon) * cos(lat), (lat - spot_lat) * 2.0);
		float r = length(d) / spot_r;
		eye = smoothstep(1.15, 0.2, r);
		float ang = atan(d.y, d.x) + (1.0 - r) * 4.0 + t * 0.05;
		spin = 0.5 + 0.5 * sin(ang * 2.0 + r * 5.0);
		wall = smoothstep(0.6, 0.98, r) * smoothstep(1.18, 0.98, r);
		// the belts bend AROUND the oval instead of running through it
		lon += -d.y * eye * 0.5;
		lat += d.x * eye * 0.18;
	}
	// --- belts and zones: FEW and WIDE, with soft gradients between
	// them. bands are not evenly spaced either -- the latitude axis is
	// warped so some belts are fat and some are thin, like the real one
	float latw = lat + 0.16 * sin(lat * 2.7) + 0.07 * sin(lat * 5.3 + 1.2);
	float bandf = latw * bands_n;
	float id = floor(bandf);
	float fb = fract(bandf);
	float h = hashf(id * 3.7);
	float hn = hashf((id + 1.0) * 3.7);
	float dirb = mod(id, 2.0) < 0.5 ? 1.0 : -1.0;
	float u = lon + dirb * t * 0.004 * (0.5 + h);
	// filaments: noise stretched long in longitude, thin in latitude
	float fil = fbm(vec3(u * 1.5, latw * 13.0, h * 9.0));
	float fine = fbm(vec3(u * 3.8, latw * 30.0, h * 3.0));
	// the band profile is a smooth wave, not a step: belt fades into
	// zone over a third of the band, and the noise ruffles the boundary
	// the belts sit where that world's belts really sit; the filament
	// noise only ruffles their edges
	float prof = belts(lat + (fil - 0.5) * 0.045, style);
	float belt_amt = 1.0 - smoothstep(0.10, 0.75, prof);
	vec3 col = mix(belt_c, zone_c, belt_amt);
	// each band leans its own way in tone, blended into its neighbour so
	// no seam is ever a drawn line
	float lean = mix(h, hn, smoothstep(0.0, 1.0, fb)) - 0.5;
	col = mix(col, mix(col, white, 0.30), clamp(lean, 0.0, 0.5) * turb);
	col *= 1.0 - clamp(-lean, 0.0, 0.5) * 0.22 * turb;
	// layers INSIDE the band: bright filaments, darker lanes, fine grain
	col = mix(col, mix(col, white, 0.5), smoothstep(0.45, 0.9, fil) * 0.45 * turb);
	col = mix(col, col * 0.86, smoothstep(0.5, 0.15, fil) * 0.4 * turb);
	col = mix(col, mix(col, white, 0.28), smoothstep(0.6, 0.92, fine) * 0.28 * turb);
	// where two jets shear past each other the boundary curls
	float shear = 1.0 - abs(prof - 0.42) * 2.4;
	float curl = fbm(vec3(u * 4.0 + fil * 2.4, latw * 22.0, 7.0));
	float ripple = smoothstep(0.6, 1.0, shear)
		* (0.5 + 0.5 * sin(u * 16.0 + curl * 8.0));
	col = mix(col, mix(col * 0.88, white, ripple * 0.45),
		smoothstep(0.55, 1.0, shear) * 0.4 * turb);
	// --- Saturn's hexagon: the polar jet is a six-sided standing wave
	if (hex_on > 0.5) {
		float pl = (1.5708 - lat) / 0.42;           // 0 at the north pole
		float th = lon + t * 0.01;
		float hexr = cos(0.5236) / cos(mod(th, 1.0472) - 0.5236);
		float edge = abs(pl - hexr * 0.62);
		float hexline = smoothstep(0.16, 0.0, edge);
		float inside = smoothstep(0.03, -0.08, pl - hexr * 0.62);
		// smoothstep(1.30, 1.02, lat) reads ZERO at the pole -- the mask
		// has to RISE toward it, not fall away from it
		float polar = smoothstep(1.00, 1.28, lat);
		col = mix(col, mix(belt_c * 0.7, base, 0.35), inside * polar * 0.85);
		col = mix(col, mix(white, zone_c, 0.15), hexline * polar);
		// the eye sitting at the centre of the hexagon
		col = mix(col, mix(belt_c, vec3(0.0), 0.4),
			smoothstep(0.18, 0.0, pl) * polar);
	}
	// --- Neptune's methane cirrus: bright streaks ABOVE the bands
	if (cirrus > 0.01) {
		float cf = fbm(vec3(lon * 2.2 + t * 0.02, lat * 9.0, 4.0));
		float streak = smoothstep(0.62, 0.9, cf)
			* smoothstep(0.15, 0.45, abs(lat));
		col = mix(col, white, streak * cirrus);
	}
	// --- the spot, painted on top of the band it rides
	if (spot_on > 0.5) {
		vec3 eyecol = mix(spot_c, mix(spot_c, white, 0.55), spin * 0.7);
		col = mix(col, eyecol, eye * 0.95);
		col = mix(col, mix(spot_c, vec3(0.0), 0.35), wall * eye * 0.5);
	}
	// polar hoods (Saturn keeps its own, above)
	float pole = smoothstep(0.78, 1.15, abs(lat));
	col = mix(col, mix(base, white, 0.45), pole * 0.55 * (1.0 - hex_on * 0.7));
	// --- Joule's glow: the shear lines themselves are luminous, and the
	// poles carry aurorae that ripple on their own clock
	vec3 glow = vec3(0.0);
	if (glow_amt > 0.01) {
		float veins = smoothstep(0.55, 1.0, shear) * (0.35 + 0.65 * ripple);
		glow += mix(zone_c, white, 0.35) * veins * glow_amt;
		float aur = smoothstep(0.85, 1.25, abs(lat))
			* (0.45 + 0.55 * fbm(vec3(lon * 3.0 + t * 0.06, abs(lat) * 8.0, 2.0)));
		glow += mix(zone_c, vec3(0.6, 1.0, 0.8), 0.5) * aur * glow_amt * 1.4;
	}
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = col + glow * 0.35;
	EMISSION = base * fres * 0.5 + glow;
	ROUGHNESS = 0.9;
}
"""
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("base", color)
			# defaults: an anonymous giant, banded off its own colour
			var zone: Color = color.lightened(0.42)
			var belt: Color = color.darkened(0.34)
			var spot: Color = color.lightened(0.1)
			var bands_n := 5.0
			var turb := 0.85
			var spot_on := 0.0
			var spot_lat := -0.35
			var spot_lon := 1.4
			var spot_r := 0.45
			var hex_on := 0.0
			var cirrus := 0.0
			var style := 5.0
			var glow_amt := 0.0
			match pname:
				"Jupiter":
					# cream zones, ochre belts, and the Great Red Spot
					# riding the southern equatorial belt
					zone = Color("#efdcb4")
					belt = Color("#a4703f")
					spot = Color("#c9543a")
					bands_n = 6.5
					style = 0.0
					turb = 1.0
					spot_on = 1.0
					spot_lat = -0.36
					spot_lon = 1.4
					spot_r = 0.5
				"Saturn":
					# soft butter bands, very little contrast, and the
					# hexagon standing over the north pole
					zone = Color("#f3e3bb")
					belt = Color("#c9a768")
					bands_n = 5.5
					style = 1.0
					turb = 0.5
					hex_on = 1.0
				"Uranus":
					# famously featureless: haze over the faintest banding
					zone = Color("#bdeeeb")
					belt = Color("#8fd6d4")
					bands_n = 3.0
					style = 2.0
					turb = 0.16
				"Joule":
					# green, luminous, and busier than anything in Sol
					zone = Color("#7dffb8")
					belt = Color("#166b4a")
					spot = Color("#b6ff6a")
					bands_n = 7.0
					turb = 0.95
					style = 4.0
					glow_amt = 1.0
					spot_on = 1.0
					spot_lat = -0.22
					spot_lon = 1.4
					spot_r = 0.4
				"Neptune":
					# deep blue, white methane cirrus, and the dark spot
					zone = Color("#6f92f0")
					belt = Color("#2b4bb4")
					spot = Color("#16224f")
					bands_n = 4.5
					style = 3.0
					turb = 0.55
					cirrus = 0.55
					spot_on = 1.0
					spot_lat = 0.34
					spot_lon = 1.45
					spot_r = 0.34
			m.set_shader_parameter("zone_c", zone)
			m.set_shader_parameter("belt_c", belt)
			m.set_shader_parameter("spot_c", spot)
			m.set_shader_parameter("bands_n", bands_n)
			m.set_shader_parameter("turb", turb)
			m.set_shader_parameter("spot_on", spot_on)
			m.set_shader_parameter("spot_lat", spot_lat)
			m.set_shader_parameter("spot_lon", spot_lon)
			m.set_shader_parameter("spot_r", spot_r)
			m.set_shader_parameter("hex_on", hex_on)
			m.set_shader_parameter("cirrus", cirrus)
			m.set_shader_parameter("style", style)
			m.set_shader_parameter("glow_amt", glow_amt)
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
	EMISSION = surf * (4.8 + pow(facing, 2.0) * 8.0 + cells * 2.4);
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
		"datamosh":
			return "shader_type spatial;\nvoid fragment(){\n float t=TIME;\n float band=floor(VERTEX.y*4.0+t*6.0);\n float g=fract(sin(band)*43758.5453);\n vec3 c=vec3(fract(VERTEX.x*0.3+t),g,fract(VERTEX.z*0.3-t));\n if(g>0.7){c=vec3(1.0)-c;}\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wireframe":
			return "shader_type spatial;\nvoid fragment(){\n vec2 gr=abs(fract(UV*40.0)-0.5);\n float line=1.0-smoothstep(0.0,0.05,min(gr.x,gr.y));\n ALBEDO=vec3(0.02); EMISSION=vec3(0.1,0.9,0.5)*line;\n}"
		"contrast":
			return "shader_type spatial;\nvoid fragment(){\n float v=step(0.5,fract(VERTEX.y*0.15+VERTEX.x*0.1));\n ALBEDO=vec3(v); EMISSION=vec3(v);\n}"
	return "shader_type spatial;\nvoid fragment(){ ALBEDO=vec3(0.5); }"

# -------------------------------------------------------------- content

## a Requiem needle: Harold's spike grown wrong -- taller, paler,
## more of them
func _r_spike(b, cd: Vector3, hrng: RandomNumberGenerator) -> void:
	var sb8 := _basis_from_up(cd)
	var segs := 4 + hrng.randi() % 3
	var sh8 := 0.0
	var tall := 1.5 if hrng.randf() > 0.12 else 2.4   # some are MONSTERS
	var bw := hrng.randf_range(1.6, 3.0)
	for sg in segs:
		var nk := MeshInstance3D.new()
		var nkm := CylinderMesh.new()
		var frac := 1.0 - float(sg) / float(segs)
		nkm.bottom_radius = bw * frac
		nkm.top_radius = bw * maxf(0.05, frac - 1.0 / float(segs)) * 0.75
		nkm.height = hrng.randf_range(2.6, 5.2) * tall
		nkm.radial_segments = 6
		nk.mesh = nkm
		nk.material_override = Surfaces.stone(
			Color("#8a8378").darkened(float(sg) * 0.05))
		var nsh := CylinderShape3D.new()
		nsh.radius = maxf(0.12, nkm.bottom_radius * 0.8)
		nsh.height = nkm.height
		_rockify(nk, nsh)
		add_child(nk)
		nk.global_transform = Transform3D(sb8,
			b.center + cd * (float(b.radius) + sh8 + nkm.height * 0.5 - 0.4))
		nk.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
		sh8 += nkm.height * 0.94

## a harvestable Euclid succulent: F (or a whack) takes its fruit --
## a few coins' worth and something to eat. One harvest per plant.
class CactusPlant extends StaticBody3D:
	var harvested := false
	func use() -> void:
		take_damage(1.0, Vector3.ZERO)
	func take_damage(_d: float, _from: Vector3) -> void:
		if harvested:
			return
		harvested = true
		Sfx.play("eat", -10.0)
		Inventory.add_coins(2 + randi() % 5)
		if randi() % 5 < 3:   # 60%: ONE fruit. 40%: none. No fruit farms.
			var drop := ItemDrop.new()
			drop.setup("sucfruit", 1)
			get_parent().add_child(drop)
			drop.global_position = global_position \
				+ global_transform.basis.y * 1.2
		# HARVESTED means harvested: the plant comes apart
		Destructible.spawn_debris(get_parent(), global_position
			+ global_transform.basis.y * 0.8,
			Vector3(1.2, 1.8, 1.2), Color("#e8702a"), 
			global_transform.basis.y)
		queue_free()

## F3: dress every live hitbox in translucent green so collision truth
## is visible (blast radii draw themselves at detonation)
func set_hitbox_debug(on: bool) -> void:
	for n9 in get_tree().get_nodes_in_group("hb_dbg"):
		if is_instance_valid(n9):
			n9.queue_free()
	if not on:
		return
	var seen9 := {}
	# NOT the player: your camera lives inside your own capsule, and
	# painting it green paints the whole screen green
	for g9 in ["enemy", "stalker", "big_stalker", "animal", "machine",
			"waypoint"]:
		for b9 in get_tree().get_nodes_in_group(g9):
			if seen9.has(b9):
				continue
			seen9[b9] = true
			_hb_paint(b9)

func _hb_paint(root: Node) -> void:
	var stack9: Array = [root]
	while not stack9.is_empty():
		var n9: Node = stack9.pop_back()
		for c9 in n9.get_children():
			stack9.append(c9)
		if n9 is CollisionShape3D and (n9 as CollisionShape3D).shape != null:
			var sh9: Shape3D = (n9 as CollisionShape3D).shape
			var mi9 := MeshInstance3D.new()
			if sh9 is BoxShape3D:
				mi9.mesh = Surfaces.box_mesh((sh9 as BoxShape3D).size)
			elif sh9 is SphereShape3D:
				var sm9 := SphereMesh.new()
				sm9.radius = (sh9 as SphereShape3D).radius
				sm9.height = sm9.radius * 2.0
				mi9.mesh = sm9
			elif sh9 is CapsuleShape3D:
				var cm9 := CapsuleMesh.new()
				cm9.radius = (sh9 as CapsuleShape3D).radius
				cm9.height = (sh9 as CapsuleShape3D).height
				mi9.mesh = cm9
			elif sh9 is CylinderShape3D:
				var cy9 := CylinderMesh.new()
				cy9.top_radius = (sh9 as CylinderShape3D).radius
				cy9.bottom_radius = cy9.top_radius
				cy9.height = (sh9 as CylinderShape3D).height
				mi9.mesh = cy9
			else:
				continue
			var hm9 := StandardMaterial3D.new()
			hm9.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hm9.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hm9.albedo_color = Color(0.2, 1.0, 0.4, 0.22)
			hm9.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi9.material_override = hm9
			mi9.add_to_group("hb_dbg")
			n9.add_child(mi9)

func _populate(b) -> void:
	if str(b.name) == "Euclid":
		# EXOTIC FLORA, clustered: little stands of branching orange
		# growths. Each plant forks into curving branches, and every
		# branch ends in something FLOWERLIKE but wrong -- a whorl of
		# thin curved spines around a glowing heart, filament stalks
		# with bead tips leaning out of it. Some splayed wide, some
		# still furled shut.
		var erng := RandomNumberGenerator.new()
		erng.seed = 3141
		for ci9 in 26:
			var cd9 := Vector3(erng.randf_range(-1, 1),
				erng.randf_range(-1, 1),
				erng.randf_range(-1, 1)).normalized()
			if absf(cd9.y) > 0.85:
				continue   # poles belong to the temple and the pyramid
			var ct1 := cd9.cross(Vector3.UP)
			if ct1.length() < 0.01:
				ct1 = cd9.cross(Vector3.RIGHT)
			ct1 = ct1.normalized()
			var ct2 := cd9.cross(ct1).normalized()
			for pi9 in 3 + erng.randi() % 3:
				var pd9 := (cd9 + (ct1 * erng.randf_range(-1.0, 1.0)
					+ ct2 * erng.randf_range(-1.0, 1.0))
					* (4.5 / float(b.radius))).normalized()
				var pb9 := _basis_from_up(pd9)
				var root9 := Node3D.new()
				add_child(root9)
				root9.global_transform = Transform3D(pb9,
					b.center + pd9 * float(b.radius))
				root9.rotate_object_local(Vector3.UP, erng.randf() * TAU)
				var sh9 := erng.randf_range(1.0, 2.3)
				var stem := MeshInstance3D.new()
				var stm := CylinderMesh.new()
				stm.top_radius = 0.03
				stm.bottom_radius = 0.06
				stm.height = sh9
				stm.radial_segments = 5
				stem.mesh = stm
				stem.material_override = Destructible.make_material(
					Color("#ff7a2a"), 0.5)
				root9.add_child(stem)
				stem.position = Vector3(0, sh9 * 0.5, 0)
				var nbr := 2 + erng.randi() % 3
				for bk9 in nbr + 1:
					# branch 0 is the crown; the rest fork off the stem
					var bh9 := sh9 if bk9 == 0 \
						else sh9 * erng.randf_range(0.45, 0.8)
					var byaw := erng.randf() * TAU
					var btilt := 0.0 if bk9 == 0 \
						else erng.randf_range(0.5, 1.0)
					var bnode := Node3D.new()
					root9.add_child(bnode)
					bnode.position = Vector3(0, bh9, 0)
					bnode.rotation = Vector3(0, byaw, 0)
					var blen := 0.0
					if bk9 > 0:
						blen = erng.randf_range(0.45, 0.9)
						var br9 := MeshInstance3D.new()
						var brm := CylinderMesh.new()
						brm.top_radius = 0.02
						brm.bottom_radius = 0.035
						brm.height = blen
						brm.radial_segments = 5
						br9.mesh = brm
						br9.material_override = Destructible.make_material(
							Color("#ff8c3d"), 0.5)
						bnode.add_child(br9)
						br9.rotation = Vector3(0, 0, -btilt)
						br9.position = Vector3(sin(btilt) * blen * 0.5,
							cos(btilt) * blen * 0.5, 0)
					var head9 := Node3D.new()
					bnode.add_child(head9)
					head9.position = Vector3(sin(btilt) * blen,
						cos(btilt) * blen, 0)
					# THE BLOOM: curved spine whorl + heart + filaments
					var heart := MeshInstance3D.new()
					var hm9 := SphereMesh.new()
					hm9.radius = 0.08
					hm9.height = 0.16
					heart.mesh = hm9
					heart.material_override = Destructible.make_material(
						Color("#ffe066"), 2.0)
					head9.add_child(heart)
					var splay := erng.randf_range(0.25, 1.25)  # furled..wide
					var nsp := 6 + erng.randi() % 4
					for sk9 in nsp:
						var sa9 := TAU * float(sk9) / float(nsp)
						var sp9 := MeshInstance3D.new()
						var spm := CylinderMesh.new()
						spm.bottom_radius = 0.022
						spm.top_radius = 0.003
						spm.height = erng.randf_range(0.24, 0.4)
						spm.radial_segments = 4
						sp9.mesh = spm
						sp9.material_override = Destructible.make_material(
							Color("#ffd23f"), 1.3)
						head9.add_child(sp9)
						sp9.position = Vector3(cos(sa9) * 0.05, 0.03,
							sin(sa9) * 0.05)
						sp9.rotation = Vector3(sin(sa9) * splay, 0,
							-cos(sa9) * splay)
					for fk9 in 2 + erng.randi() % 2:
						var fa9 := erng.randf() * TAU
						var fil := MeshInstance3D.new()
						var fim := CylinderMesh.new()
						fim.top_radius = 0.006
						fim.bottom_radius = 0.006
						fim.height = 0.3
						fim.radial_segments = 3
						fil.mesh = fim
						fil.material_override = Destructible.make_material(
							Color("#ffb84d"), 0.9)
						head9.add_child(fil)
						fil.position = Vector3(cos(fa9) * 0.03, 0.16,
							sin(fa9) * 0.03)
						fil.rotation = Vector3(sin(fa9) * 0.35, 0,
							-cos(fa9) * 0.35)
						var bead := MeshInstance3D.new()
						var bem := SphereMesh.new()
						bem.radius = 0.03
						bem.height = 0.06
						bead.mesh = bem
						bead.material_override = Destructible.make_material(
							Color("#fff2a0"), 2.2)
						fil.add_child(bead)
						bead.position = Vector3(0, 0.16, 0)
	if str(b.name) == "Euclid":
		# CACTUS-LIKE SUCCULENTS around the flowering stands: fat
		# orange lobed columns, mostly bare -- only the odd one carries
		# a small yellow nub, so the flowers stay the rare thing
		var srng9 := RandomNumberGenerator.new()
		srng9.seed = 2718
		for ci9 in 26:
			var cd9 := Vector3(srng9.randf_range(-1, 1),
				srng9.randf_range(-1, 1),
				srng9.randf_range(-1, 1)).normalized()
			if absf(cd9.y) > 0.85:
				continue
			var ct1 := cd9.cross(Vector3.UP)
			if ct1.length() < 0.01:
				ct1 = cd9.cross(Vector3.RIGHT)
			ct1 = ct1.normalized()
			var ct2 := cd9.cross(ct1).normalized()
			for si9 in 3 + srng9.randi() % 3:
				var sd9 := (cd9 + (ct1 * srng9.randf_range(-1.4, 1.4)
					+ ct2 * srng9.randf_range(-1.4, 1.4))
					* (14.0 / float(b.radius))).normalized()
				var sb9 := _basis_from_up(sd9)
				var sroot := CactusPlant.new()
				var ch9 := srng9.randf_range(1.6, 3.4)
				if srng9.randf() < 0.15:
					ch9 = srng9.randf_range(4.2, 5.6)   # the tall ones
				var cr9 := srng9.randf_range(0.3, 0.5)
				var scs9 := CollisionShape3D.new()
				var scap9 := CapsuleShape3D.new()
				scap9.radius = cr9 + 0.1
				scap9.height = ch9
				scs9.shape = scap9
				scs9.position = Vector3(0, ch9 * 0.5, 0)
				sroot.add_child(scs9)
				add_child(sroot)
				sroot.global_transform = Transform3D(sb9,
					b.center + sd9 * float(b.radius))
				sroot.rotate_object_local(Vector3.UP, srng9.randf() * TAU)
				var ccol := Color("#e8702a").darkened(
					srng9.randf_range(0.0, 0.18))
				var col9 := MeshInstance3D.new()
				var cap9 := CapsuleMesh.new()
				cap9.radius = cr9
				cap9.height = ch9
				cap9.radial_segments = 10
				col9.mesh = cap9
				col9.material_override = Destructible.make_material(ccol, 0.3)
				sroot.add_child(col9)
				# base SUNK: the rounded bottom hides in the ground, so
				# no cactus balances on a curve like a circus act
				col9.position = Vector3(0, ch9 * 0.5 - 0.4, 0)
				# arms: the classic cactus silhouette, zero to two
				for ak9 in srng9.randi() % 3:
					var aa9 := srng9.randf() * TAU
					var arm := MeshInstance3D.new()
					var am9 := CapsuleMesh.new()
					am9.radius = cr9 * 0.55
					am9.height = srng9.randf_range(0.8, 1.5)
					am9.radial_segments = 8
					arm.mesh = am9
					arm.material_override = Destructible.make_material(ccol, 0.3)
					sroot.add_child(arm)
					arm.position = Vector3(cos(aa9) * (cr9 + 0.15),
						ch9 * srng9.randf_range(0.4, 0.7),
						sin(aa9) * (cr9 + 0.15))
					arm.rotation = Vector3(sin(aa9) * 0.6, 0, -cos(aa9) * 0.6)
				# GREEN PRICKS: thin spines bristling off the column
				for pk9 in 10 + srng9.randi() % 7:
					var pa9 := srng9.randf() * TAU
					var ph9 := srng9.randf_range(0.2, ch9 - 0.2)
					var prick := MeshInstance3D.new()
					var prm9 := CylinderMesh.new()
					prm9.bottom_radius = 0.015
					prm9.top_radius = 0.002
					prm9.height = srng9.randf_range(0.18, 0.3)
					prm9.radial_segments = 3
					prick.mesh = prm9
					prick.material_override = Destructible.make_material(
						Color("#3fae4a"), 0.7)
					sroot.add_child(prick)
					prick.position = Vector3(cos(pa9) * cr9, ph9,
						sin(pa9) * cr9)
					prick.rotation = Vector3(sin(pa9) * 1.45, 0,
						-cos(pa9) * 1.45)
				if srng9.randf() < 0.3:
					var nub := MeshInstance3D.new()
					var nm9 := SphereMesh.new()
					nm9.radius = 0.11
					nm9.height = 0.17
					nub.mesh = nm9
					nub.material_override = Destructible.make_material(
						Color("#ffd23f"), 1.4)
					sroot.add_child(nub)
					nub.position = Vector3(0, ch9 + 0.06, 0)
	if str(b.name) == "Requiem":
		# THE GRAVEYARD PROPER: not just needles. Spike clusters, yes --
		# but between them leaning gravestone slabs, bone-rib cages
		# arcing out of the ground, pale boulder gardens, and rings of
		# small shards like something burst upward. The crown (28
		# degrees around +Y) stays CLEAR for what will stand there.
		var qrng := RandomNumberGenerator.new()
		qrng.seed = 8008
		var qcap := cos(deg_to_rad(28.0))
		var qdir := func() -> Vector3:
			while true:
				var d9 := Vector3(qrng.randf_range(-1, 1),
					qrng.randf_range(-1, 1),
					qrng.randf_range(-1, 1)).normalized()
				if d9.y <= qcap:
					return d9
			return Vector3.DOWN
		var placed := 0
		while placed < 120:
			var cd9: Vector3 = qdir.call()
			var cluster := 3 + qrng.randi() % 4
			for ci9 in cluster:
				var cdir9 := (cd9 + Vector3(qrng.randf_range(-0.06, 0.06),
					qrng.randf_range(-0.06, 0.06),
					qrng.randf_range(-0.06, 0.06))).normalized()
				if cdir9.y > qcap:
					continue
				_r_spike(b, cdir9, qrng)
				placed += 1
		# GRAVESTONES: tall thin slabs, each leaning its own way
		for gi9 in 36:
			var gd9: Vector3 = qdir.call()
			var gb9 := _basis_from_up(gd9)
			var slab := MeshInstance3D.new()
			var sbm9 := BoxMesh.new()
			sbm9.size = Vector3(qrng.randf_range(1.6, 3.0),
				qrng.randf_range(4.0, 9.0), qrng.randf_range(0.6, 1.1))
			slab.mesh = sbm9
			slab.material_override = Surfaces.stone(Color("#7d7568")
				.darkened(qrng.randf_range(0.0, 0.25)))
			var sshp := BoxShape3D.new()
			sshp.size = sbm9.size
			_rockify(slab, sshp)
			add_child(slab)
			slab.global_transform = Transform3D(gb9,
				b.center + gd9 * (float(b.radius) + sbm9.size.y * 0.32))
			slab.rotate_object_local(Vector3.UP, qrng.randf() * TAU)
			slab.rotate_object_local(Vector3(1, 0, 0),
				qrng.randf_range(-0.35, 0.35))
			slab.rotate_object_local(Vector3(0, 0, 1),
				qrng.randf_range(-0.3, 0.3))
		# RIB CAGES: rows of paired bone arcs leaning toward each other
		for ri9 in 12:
			var rd9: Vector3 = qdir.call()
			var rb9 := _basis_from_up(rd9)
			var nrib := 4 + qrng.randi() % 3
			for k9 in nrib:
				for sgn9 in [-1.0, 1.0]:
					var rib := MeshInstance3D.new()
					var rcm9 := CylinderMesh.new()
					rcm9.bottom_radius = 0.45
					rcm9.top_radius = 0.12
					rcm9.height = qrng.randf_range(5.0, 8.0)
					rcm9.radial_segments = 6
					rib.mesh = rcm9
					rib.material_override = Surfaces.stone(Color("#a29a8c"))
					var rshp := CylinderShape3D.new()
					rshp.radius = 0.35
					rshp.height = rcm9.height
					_rockify(rib, rshp)
					add_child(rib)
					rib.global_transform = Transform3D(rb9,
						b.center + rd9 * (float(b.radius)
						+ rcm9.height * 0.3))
					rib.translate_object_local(Vector3(sgn9 * 2.6, 0,
						float(k9) * 2.2 - float(nrib) * 1.1))
					rib.rotate_object_local(Vector3(0, 0, 1),
						sgn9 * qrng.randf_range(0.5, 0.75))
		# BOULDER GARDENS: pale rounded stones leaning together
		for bi9 in 22:
			var bd9: Vector3 = qdir.call()
			var bb9 := _basis_from_up(bd9)
			for bj9 in 3 + qrng.randi() % 3:
				var bo9 := MeshInstance3D.new()
				var bom9 := SphereMesh.new()
				var br9 := qrng.randf_range(1.2, 3.4)
				bom9.radius = br9
				bom9.height = br9 * qrng.randf_range(1.3, 1.8)
				bo9.mesh = bom9
				bo9.material_override = Surfaces.stone(Color("#8d867c")
					.darkened(qrng.randf_range(0.0, 0.2)))
				var bshp9 := SphereShape3D.new()
				bshp9.radius = br9 * 0.9
				_rockify(bo9, bshp9)
				add_child(bo9)
				bo9.global_transform = Transform3D(bb9,
					b.center + bd9 * (float(b.radius) + br9 * 0.3))
				bo9.translate_object_local(Vector3(
					qrng.randf_range(-4.0, 4.0), 0,
					qrng.randf_range(-4.0, 4.0)))
				bo9.rotate_object_local(Vector3(1, 0, 0),
					qrng.randf_range(-0.4, 0.4))
		# SHARD RINGS: circles of small teeth, like something got out
		for si9 in 10:
			var sd9: Vector3 = qdir.call()
			var sb9 := _basis_from_up(sd9)
			var nsh9 := 7 + qrng.randi() % 4
			for k9 in nsh9:
				var sa9 := TAU * float(k9) / float(nsh9)
				var th9 := MeshInstance3D.new()
				var thm9 := CylinderMesh.new()
				thm9.bottom_radius = 0.5
				thm9.top_radius = 0.04
				thm9.height = qrng.randf_range(1.6, 3.2)
				thm9.radial_segments = 5
				th9.mesh = thm9
				th9.material_override = Surfaces.stone(Color("#97907f"))
				add_child(th9)
				th9.global_transform = Transform3D(sb9,
					b.center + sd9 * (float(b.radius) + thm9.height * 0.3))
				th9.translate_object_local(Vector3(cos(sa9) * 5.0, 0,
					sin(sa9) * 5.0))
				th9.rotate_object_local(Vector3(-sin(sa9), 0, cos(sa9)),
					-0.35)
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
		"dude":
			# Big Computer: the facility IS the content. No mine, no
			# enemies -- dead quiet. Salvage crates only.
			_register_crates(b, 24, 6)
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
			# no crate stacks littering the desert -- the living economy
			# here is the succulents
			_euclid_landmarks(b)   # Euclid is safe: no evil aliens
		"life":
			_register_crates(b, 10, 7)
			_spawn_flora(b)
			# Verdant digs COAL: the mine carries it, and dirt mounds on
			# the surface have lumps sticking out
			_build_mine(b, MINE_DIRS["Verdant"], "coal", 3, Color("#26262c"))
			_spawn_res_nodes(b, 8, "coal", 2)
		"pixel", "datamosh", "wob", "wireframe", "contrast":
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
			for i9 in _n(30):
				# Earth grows fiber too -- bring the knife
				var ep9 := Plant.new()
				add_child(ep9)
				var epd9 := _surface_dir()
				ep9.global_transform = Transform3D(_basis_from_up(epd9), b.center + epd9 * b.radius)
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
					# Harold's house hides in ONE seeded spot among all
					# twelve town houses -- a different town and door
					# every world, never just "the first one you check"
					if ti * 3 + hi == int(absi(Game.world_seed * 13 + 5)) % 12:
						hh2.harolds = true
						hh2.human_home = false
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
			# XERO: pale craters and translucent ice spires catching the
			# light -- and ultima veins twice as fat as Crystalia's
			_build_mine(b, MINE_DIRS["Xero"], "ultima", 2, Color("#7df9ff"), 12)
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
			# and a uranium shaft -- Sol pays for the trip
			_build_mine(b, MINE_DIRS["Mercury"], "uranium", 2, Color("#9aff2a"), 18)
			for i in _n(12):
				_crater(b, _surface_dir(), randf_range(1.0, 3.0), Color("#8a7d70"))
			_spawn_rocks(b, 14, Color("#7d7168"))
			_spawn_res_nodes(b, 10, "coal", 2)
			_spawn_res_nodes(b, 5, "uranium", 1)   # sun-baked pitchblende
		"harold":
			# HAROLD: dusty, rocky, quietly interesting. No craters --
			# he's had enough impacts for one lifetime. Geology is SEEDED:
			# spikes, highlands and mounds sit in the same spots every run,
			# like Earth's fixed features.
			var hrng := RandomNumberGenerator.new()
			hrng.seed = 618
			_spawn_rocks(b, 90, Color("#83786c"))   # rubble EVERYWHERE
			for i in _n(14):
				# dust drifts: soft half-buried mounds
				var dm4 := MeshInstance3D.new()
				var dmm := SphereMesh.new()
				var dr := hrng.randf_range(2.0, 5.5)
				dmm.radius = dr
				dmm.height = dr * 0.6
				dm4.mesh = dmm
				dm4.material_override = Surfaces.stone(Color("#988c7d"))
				var msh2 := SphereShape3D.new()
				msh2.radius = dr * 0.82
				_rockify(dm4, msh2)
				add_child(dm4)
				var dd := _h_dir(hrng)
				dm4.global_transform = Transform3D(_basis_from_up(dd),
					b.center + dd * (b.radius - dr * 0.25))
			for i in _n(8):
				# hoodoos: wind-carved stacked spires
				var hd := _h_dir(hrng)
				var hb := _basis_from_up(hd)
				var hy := 0.0
				for st9 in 3 + hrng.randi() % 3:
					var seg := MeshInstance3D.new()
					var sgm := BoxMesh.new()
					var sw9 := hrng.randf_range(1.0, 2.0) * (1.0 - float(st9) * 0.16)
					sgm.size = Vector3(sw9, hrng.randf_range(0.8, 1.6), sw9)
					seg.mesh = sgm
					seg.material_override = Surfaces.stone(
						Color("#7d7266").lightened(hrng.randf() * 0.12))
					var hsh := BoxShape3D.new()
					hsh.size = sgm.size
					_rockify(seg, hsh)
					add_child(seg)
					seg.global_transform = Transform3D(hb,
						b.center + hd * (b.radius + hy + sgm.size.y * 0.5))
					seg.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
					hy += sgm.size.y * 0.92
			for i in _n(6):
				# windswept ridges half-buried in the dust
				var rg := MeshInstance3D.new()
				var rgm := BoxMesh.new()
				rgm.size = Vector3(hrng.randf_range(6.0, 12.0), hrng.randf_range(1.0, 2.0),
					hrng.randf_range(1.4, 2.6))
				rg.mesh = rgm
				rg.material_override = Surfaces.stone(Color("#6f655a"))
				var rsh := BoxShape3D.new()
				rsh.size = rgm.size
				_rockify(rg, rsh)
				add_child(rg)
				var rd9 := _h_dir(hrng)
				rg.global_transform = Transform3D(_basis_from_up(rd9),
					b.center + rd9 * (b.radius + 0.3))
				rg.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
			for i in _n(10):
				# highlands: broad raised slabs -- terrain that climbs
				var md := _h_dir(hrng)
				var mb := _basis_from_up(md)
				var mh := 0.0
				for lyr in 2 + hrng.randi() % 2:
					var slab := MeshInstance3D.new()
					var slm := BoxMesh.new()
					var sw2 := hrng.randf_range(9.0, 18.0) * (1.0 - float(lyr) * 0.28)
					slm.size = Vector3(sw2, hrng.randf_range(1.6, 3.0), sw2 * hrng.randf_range(0.7, 1.0))
					slab.mesh = slm
					slab.material_override = Surfaces.stone(
						Color("#7d7266").lightened(float(lyr) * 0.07))
					var ssh := BoxShape3D.new()
					ssh.size = slm.size
					_rockify(slab, ssh)
					add_child(slab)
					slab.global_transform = Transform3D(mb,
						b.center + md * (b.radius + mh + slm.size.y * 0.35))
					slab.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
					mh += slm.size.y * 0.8
			# BIOME FIELD: seeded noise over the sphere (seed 618, same
			# every run). Sampled COARSE so regions come out as fat blobs,
			# not strings. The mesa is gone (it looked like a snake);
			# instead: spike forests, boulder gardens, shard flats, dunes.
			var bnoise := FastNoiseLite.new()
			bnoise.seed = 618
			bnoise.frequency = 1.0
			var spikes_left := _n(150)
			var boulders_left := _n(40)
			var shards_left := _n(34)
			var dunes_left := _n(34)
			for i in 3400:
				if spikes_left <= 0 and boulders_left <= 0 \
						and shards_left <= 0 and dunes_left <= 0:
					break
				var cd := _h_dir(hrng)
				var nv := bnoise.get_noise_3d(cd.x * 1.4, cd.y * 1.4, cd.z * 1.4)
				if nv > 0.18 and spikes_left > 0:
					# spike FOREST: blobby dense patches of needle clusters
					var cluster := 4 + hrng.randi() % 3
					spikes_left -= cluster
					for ci in cluster:
						var cdir: Vector3 = (cd + Vector3(
							hrng.randf_range(-0.07, 0.07), hrng.randf_range(-0.07, 0.07),
							hrng.randf_range(-0.07, 0.07))).normalized()
						_h_spike(b, cdir, b.radius, hrng)
				elif nv < -0.5 and boulders_left > 0:
					# boulder garden: fat rounded stones leaning together
					boulders_left -= 1
					var gb2 := _basis_from_up(cd)
					for bi2 in 3 + hrng.randi() % 3:
						var bo := MeshInstance3D.new()
						var bom := SphereMesh.new()
						var br2 := hrng.randf_range(1.2, 3.2)
						bom.radius = br2
						bom.height = br2 * hrng.randf_range(1.3, 1.9)
						bo.mesh = bom
						bo.material_override = Surfaces.stone(
							Color("#786d60").lightened(hrng.randf() * 0.1))
						var bsh := SphereShape3D.new()
						bsh.radius = br2 * 0.9
						_rockify(bo, bsh)
						add_child(bo)
						bo.global_transform = Transform3D(gb2,
							b.center + cd * (b.radius + br2 * 0.35))
						bo.position += gb2 * Vector3(hrng.randf_range(-4.0, 4.0), 0,
							hrng.randf_range(-4.0, 4.0))
						bo.rotate_object_local(Vector3.RIGHT, hrng.randf_range(-0.4, 0.4))
				elif nv >= -0.5 and nv < -0.34 and shards_left > 0:
					# shard flats: broken tilted plates, shattered pavement
					shards_left -= 1
					var pb2 := _basis_from_up(cd)
					for pi2 in 4 + hrng.randi() % 4:
						var pl := MeshInstance3D.new()
						var plm := BoxMesh.new()
						plm.size = Vector3(hrng.randf_range(2.4, 5.0),
							hrng.randf_range(0.35, 0.6), hrng.randf_range(2.0, 4.2))
						pl.mesh = plm
						pl.material_override = Surfaces.stone(Color("#6a6156"))
						var psh := BoxShape3D.new()
						psh.size = plm.size
						_rockify(pl, psh)
						add_child(pl)
						pl.global_transform = Transform3D(pb2,
							b.center + cd * (b.radius + 0.1))
						pl.position += pb2 * Vector3(hrng.randf_range(-5.0, 5.0), 0,
							hrng.randf_range(-5.0, 5.0))
						pl.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
						pl.rotate_object_local(Vector3.RIGHT, hrng.randf_range(-0.35, 0.35))
						pl.rotate_object_local(Vector3.BACK, hrng.randf_range(-0.35, 0.35))
				elif nv > 0.04 and nv < 0.14 and dunes_left > 0:
					# dune belts: long soft waves of dust lying on the ground
					dunes_left -= 1
					var db2 := _basis_from_up(cd)
					var du := MeshInstance3D.new()
					var dum := CapsuleMesh.new()
					dum.radius = hrng.randf_range(1.4, 2.4)
					dum.height = hrng.randf_range(9.0, 16.0)
					du.mesh = dum
					du.material_override = Surfaces.stone(Color("#9a8e7f"))
					var dsh := CapsuleShape3D.new()
					dsh.radius = dum.radius
					dsh.height = dum.height
					_rockify(du, dsh)
					add_child(du)
					du.global_transform = Transform3D(db2,
						b.center + cd * (b.radius - dum.radius * 0.45))
					du.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
					du.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			_spawn_res_nodes(b, 8, "coal", 2)
			_spawn_res_nodes(b, 5, "uranium", 1)
			# one bench, facing the black hole. he sits sometimes.
			var bhh = Universe.body_named("TIN 618")
			if bhh != null:
				var bd9 := _h_dir(hrng)
				var bb9 := _basis_from_up(bd9)
				var bpos: Vector3 = b.center + bd9 * b.radius
				var bench := Bench.new()
				bench.is_bench = true
				var tow: Vector3 = bb9.inverse() * (bhh.center - bpos)
				bench.yaw = atan2(tow.x, tow.z)
				add_child(bench)
				bench.global_transform = Transform3D(bb9, bpos)
			_h_monument(b, hrng)
		"venus":
			# the pressure-cooker: glowing fissures, sulfur crusting everything
			for i in _n(7):
				_venus_vent(b, _surface_dir())
			_add_shell(b, Color(0.9, 0.75, 0.4, 0.35), 1.09, false)
			_spawn_res_nodes(b, 12, "sulfur", 3)
			_spawn_enemies(b, 4, 2)   # even the locals are hostile. it's venus.
		"mars":
			# rust, ruins of exploration, and iridium under the dust --
			# the RICHEST iridium veins anywhere are down this shaft
			_build_mine(b, MINE_DIRS["Mars"], "raw_irid", 3, Color("#2a8f6a"), 14)
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
			# Extroma: geologically furious, economically generous -- its
			# uranium shaft out-yields everything in the Dude system
			_build_mine(b, MINE_DIRS["Extroma"], "uranium", 3, Color("#9aff2a"), 22)
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
			_spawn_res_nodes(b, 7, "coal", 2)   # forest coal under the pines
			for i in _n(40):
				# knife-harvestable undergrowth: plant fiber grows here
				var vp := Plant.new()
				add_child(vp)
				var vpd := _surface_dir()
				vp.global_transform = Transform3D(_basis_from_up(vpd),
					b.center + vpd * b.radius)
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
			for i in _n(26):
				# LAND animals only, and they are EVERYWHERE on the planet
				var an := Animal.new()
				an.setup(b, true)
				an.ground_locked = true   # Varnisol fauna NEVER leaves the dirt
				add_child(an)
				var ad := _surface_dir()
				an.global_transform = Transform3D(_basis_from_up(ad),
					b.center + ad * (b.radius + 1.5))
				_varnisolify(an)
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
	# older bubbles climb out of the way -- chat again and the new line
	# slides in underneath instead of stacking on top of the old one
	for c9 in target.get_children():
		if c9 is Node3D and c9.has_meta("chat_bub"):
			(c9 as Node3D).position.y += 0.62
	var root9 := Node3D.new()
	root9.set_meta("chat_bub", true)
	target.add_child(root9)
	root9.position = Vector3(0, 3.0, 0)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 30
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.outline_size = 8
	lbl.width = 460
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root9.add_child(lbl)
	# the CARD behind the words, human-bubble style
	var bg9 := MeshInstance3D.new()
	var bgm9 := QuadMesh.new()
	var lines9 := 1 + int(text.length() / 34)
	bgm9.size = Vector2(clampf(0.5 + float(text.length()) * 0.055, 0.9, 3.3),
		0.26 + float(lines9) * 0.24)
	bg9.mesh = bgm9
	var bmat9 := ShaderMaterial.new()
	var bsh9 := Shader.new()
	bsh9.code = EarthHuman.BUBBLE_SHADER
	bmat9.shader = bsh9
	bmat9.set_shader_parameter("alpha", 0.85)
	bmat9.render_priority = 9
	bg9.material_override = bmat9
	bg9.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg9.extra_cull_margin = 6.0
	root9.add_child(bg9)
	var tw := root9.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_method(func(v: float) -> void:
		bmat9.set_shader_parameter("alpha", v), 0.85, 0.0, 0.8)
	tw.tween_callback(root9.queue_free)

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
var _crater_spots := {}   # body name -> [[dir, size], ...] placed craters

func _crater(b, dir: Vector3, size: float, col: Color) -> void:
	# craters do not spawn inside each other: keep angular distance from
	# every crater already on this body, re-rolling up to 8 spots
	var ckey := str(b.name)
	if not _crater_spots.has(ckey):
		_crater_spots[ckey] = []
	var mouths: Array = []
	if MINE_DIRS.has(b.name):
		mouths.append(MINE_DIRS[b.name])
	if COLONY_DIRS.has(b.name):
		mouths.append(COLONY_DIRS[b.name])
	if b.name == "Big Computer":
		mouths.append(MAINFRAME_DIR)
	var tries := 0
	while tries < 8:
		var ok := true
		for e in _crater_spots[ckey]:
			var mind: float = (float(e[1]) + size) * 1.15 / float(b.radius)
			if (e[0] as Vector3).angle_to(dir) < mind:
				ok = false
				break
		# NEVER on a mouth: a crater floor disc over a mine hole reads
		# as a wall from both sides
		for mdir in mouths:
			if (mdir as Vector3).angle_to(dir) < (size + 7.0) / float(b.radius):
				ok = false
				break
		if ok:
			break
		dir = _surface_dir()
		tries += 1
	if tries >= 8:
		return   # crowded planet: skip rather than overlap
	_crater_spots[ckey].append([dir, size])
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
		# half-buried: deposits GROW out of the ground, they don't balance on it
		nd.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + s * 0.08))

## Every ore is ITS OWN THING: unique rock skin + embedded features,
## not a tinted cube. Ultima and prism boil with their glows; uranium is
## pitchblende -- near-black with sickly green veins.
## Ore deposits are CRYSTAL FORMATIONS: clusters of angular prisms
## growing out of the ground, tinted like the terrain they grew from.
## You spot them by shape and a low inner glow -- not traffic-cone paint.
func _dress_ore(nd: Node3D, res: String, s: float) -> void:
	if not is_instance_valid(nd):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(nd.global_position.x * 13.0 + nd.global_position.z * 7.0)) + 3
	var b = Universe.nearest(nd.global_position)
	var surf: Color = b.color if b != null else Color("#5a5a5e")
	var scol := surf.darkened(0.22)
	var look: Dictionary = RES_LOOK.get(res, {"col": Color("#c0c0c0")})
	var glow: Color = look["col"]
	# green worlds keep coal in DIRT: a soil mound with glossy black
	# lumps sticking out, instead of crystal shards
	var dirt_coal: bool = res == "coal" and b != null \
		and str(b.kind) in ["life", "varnisol", "earth"]
	# NO boulder: the old base rock is flattened into a flush terrain
	# pad, so the crystals rise straight out of the ground
	var rock_mat := Surfaces.stone(Color("#5a4630") if dirt_coal else scol)
	for ch in nd.get_children():
		if ch is MeshInstance3D:
			ch.material_override = rock_mat
			ch.scale = Vector3(1.15, 0.22 if dirt_coal else 0.16, 1.15)
			ch.position.y -= s * (0.24 if dirt_coal else 0.28)
	if dirt_coal:
		var gloss := StandardMaterial3D.new()
		gloss.albedo_color = Color("#0c0c10")
		gloss.roughness = 0.15
		gloss.metallic = 0.35
		for i in rng.randi_range(5, 7):
			var lump := MeshInstance3D.new()
			var lm := BoxMesh.new()
			var ls := s * rng.randf_range(0.2, 0.38)
			lm.size = Vector3(ls, ls, ls)
			lump.mesh = lm
			lump.material_override = gloss
			lump.position = Vector3(rng.randf_range(-0.45, 0.45) * s,
				rng.randf_range(0.0, 0.2) * s, rng.randf_range(-0.45, 0.45) * s)
			lump.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
			nd.add_child(lump)
		return
	# shards: surface-tinted crystal prisms with a faint ore-colored
	# inner light (ultima/prism keep their true materials -- they ARE glow)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = scol.lightened(0.14)
	shard_mat.roughness = 0.28
	shard_mat.metallic = 0.18
	shard_mat.emission_enabled = true
	shard_mat.emission = glow
	shard_mat.emission_energy_multiplier = 0.24
	var smat: Material = shard_mat
	if res == "ultima":
		smat = Surfaces.portal(Color("#7df9ff"))
	elif res == "prism":
		smat = Human._prism_material()
	for i in rng.randi_range(4, 7):
		var spk := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var hgt := s * rng.randf_range(0.7, 1.9)
		pm.size = Vector3(s * rng.randf_range(0.2, 0.34), hgt,
			s * rng.randf_range(0.2, 0.34))
		spk.mesh = pm
		spk.material_override = smat
		spk.position = Vector3(rng.randf_range(-0.42, 0.42) * s, hgt * 0.18,
			rng.randf_range(-0.42, 0.42) * s)
		spk.rotation = Vector3(rng.randf_range(-0.42, 0.42), rng.randf() * TAU,
			rng.randf_range(-0.42, 0.42))
		nd.add_child(spk)

## Plain breakable boulders: no ore, a little pocket change, pure geology.
func _spawn_rocks(b, count: int, col: Color) -> void:
	for i in _n(count):
		var nd := Destructible.new()
		nd.rock = true
		var s := randf_range(1.0, 2.4)
		nd.setup(Vector3(s, s * randf_range(0.7, 1.2), s), col, 2, 3, 0.1)
		add_child(nd)
		var d := _surface_dir()
		# half-buried: deposits GROW out of the ground, they don't balance on it
		nd.global_transform = Transform3D(_basis_from_up(d), b.center + d * (b.radius + s * 0.08))

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
	# the pyramid wears SANDSTONE BRICKS: staggered courses, mortar
	# seams, sun-baked grain -- and its base runs deep into the planet
	# so the curvature can never make it look like it is balancing
	var pyr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 26.2
	cm.height = 34.0
	cm.radial_segments = 4
	pyr.mesh = cm
	var bsh := Shader.new()
	bsh.code = """shader_type spatial;
varying vec2 buv;
void vertex(){ buv = UV; }
float h2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment(){
	vec2 uv = buv * vec2(28.0, 18.0);
	float row = floor(uv.y);
	uv.x += fract(row * 0.5);   // staggered courses
	vec2 c = floor(uv);
	vec2 f = fract(uv);
	float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(1.0, 0.94, f.x)
		* smoothstep(0.0, 0.09, f.y) * smoothstep(1.0, 0.91, f.y);
	float tone = 0.82 + 0.18 * h2(c);
	vec3 sand = vec3(0.71, 0.58, 0.33) * tone;
	vec3 seam = vec3(0.45, 0.36, 0.22);
	ALBEDO = mix(seam, sand, mortar);
	ROUGHNESS = 0.95;
}"""
	var bmat9 := ShaderMaterial.new()
	bmat9.shader = bsh
	pyr.material_override = bmat9
	add_child(pyr)
	pyr.global_transform = Transform3D(_basis_from_up(Vector3.DOWN),
		sp + Vector3.DOWN * 9.0)
	_pyramid_exit = sp + Vector3.DOWN * 2.0
	# THE DOOR: one framed opening at the base. Sealed by a slab until
	# the Mind Core has been activated; then F slides it into the sand.
	var dxf := Transform3D(_basis_from_up(Vector3.DOWN), sp + Vector3.DOWN * 2.0)
	var dyaw := PI / 4.0   # centered on one of the four faces
	var ddir := Vector3(cos(dyaw), 0, sin(dyaw))
	for fp9 in [[Vector3(0.6, 5.0, 0.8), Vector3(-2.2, 2.5, 0)],
			[Vector3(0.6, 5.0, 0.8), Vector3(2.2, 2.5, 0)],
			[Vector3(5.0, 0.6, 0.8), Vector3(0, 5.0, 0)]]:
		var fr9 := MeshInstance3D.new()
		fr9.mesh = Surfaces.box_mesh(fp9[0] as Vector3)
		fr9.material_override = Surfaces.stone(Color("#8a7038"))
		add_child(fr9)
		fr9.global_transform = dxf
		fr9.rotate_object_local(Vector3.UP, dyaw)
		fr9.translate_object_local(Vector3(0, 0, 14.0))
		fr9.translate_object_local(fp9[1] as Vector3)
	var pgate := Gate.new().configure({
		"target": Zones.pyramid_spawn(), "zone": "flat", "zone_g": 9.0,
		"label": "ENTER", "color": Color("#ffcf40"),
		"requires": "mindcore"})
	add_child(pgate)
	pgate.global_transform = dxf
	pgate.rotate_object_local(Vector3.UP, dyaw)
	pgate.translate_object_local(Vector3(0, 0.5, 13.9))
	# the interior is a POCKET REALM, Euclid-temple rules: the inside
	# is bigger than the outside and shaped like the outside
	Zones.build_pyramid_interior(self,
		dxf.translated_local(Vector3(0, 0, 0)).origin
		+ (dxf.basis * Basis(Vector3.UP, dyaw) * Vector3(0, 0, 1)) * 17.0
		+ (dxf.basis * Vector3(0, 1, 0)) * 1.0)
	var pdl := Label3D.new()
	pdl.text = "PYRAMID DOOR [F]"
	pdl.font_size = 26
	pdl.pixel_size = 0.008
	pdl.modulate = Color("#ffcf40")
	pdl.outline_size = 8
	pdl.outline_modulate = Color(0, 0, 0, 0.9)
	pdl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(pdl)
	pdl.global_transform = dxf
	pdl.rotate_object_local(Vector3.UP, dyaw)
	pdl.translate_object_local(Vector3(0, 5.8, 14.6))
	_build_nexus()
	# inside the pyramid: the MENGER SHRINE. F + prism shards = enchant.
	var shrine := MengerShrine.new()
	add_child(shrine)
	shrine.global_transform = Transform3D(_basis_from_up(Vector3.DOWN),
		sp + Vector3.DOWN * 4.6)

## THE NEXUS: parked far enough from every planet that gravity out there
## is effectively nothing, which is exactly why the array works so well.
func _build_nexus() -> void:
	if get_tree().get_first_node_in_group("nexus") != null:
		return
	var nx := NexusStation.new()
	add_child(nx)
	nx.global_position = NEXUS_POS
	# a lamp so it is findable from a long way out
	var beacon := OmniLight3D.new()
	beacon.light_color = Color("#7be8ff")
	beacon.light_energy = 6.0
	beacon.omni_range = 400.0
	nx.add_child(beacon)
	beacon.position = Vector3(0, 12.0, 0)

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
var _stalker_cd := 0.0

## The stalker-thulhus answer wrath. Above 40 they gather (three of
## them, one at a time); below 25 they fold away. They only ever watch.
var _stalker_scan_t := 0.0
var _big_cd := 0.0
var _big_seen := false

func _update_stalkers(delta: float) -> void:
	if Game.tutorial_session or Game.dead:
		return
	_stalker_cd -= delta
	# census at 2Hz: wrath doesn't change fast enough to justify a
	# per-frame group scan
	_stalker_scan_t -= delta
	if _stalker_scan_t > 0.0:
		return
	_stalker_scan_t = 0.5
	var live: Array = []
	for st in get_tree().get_nodes_in_group("stalker"):
		if is_instance_valid(st):
			live.append(st)
	var no_stalk: bool = Game.monolith_stage >= 8 or Game.zone != "" \
		or Game.playtime < Game.god_restrained_until \
		or (_player != null
		and Game.zone == ""
		and _player.global_position.length() > Universe.BOUNDARY)
	if no_stalk:
		for st9 in live:
			if st9.has_method("depart"):
				st9.depart()
		return
	var bigs9 := get_tree().get_nodes_in_group("big_stalker")
	if bigs9.is_empty():
		if _big_seen:
			_big_seen = false
			_big_cd = 240.0
	else:
		_big_seen = true
	_big_cd = maxf(0.0, _big_cd - 0.5)
	if Game.wrath >= 55.0:
		# deep wrath: the BIG one surfaces (one at a time is plenty),
		# and a slain one stays dead four minutes before another comes
		if bigs9.is_empty() and _big_cd <= 0.0 and _player != null:
			var big := BigStalker.new()
			add_child(big)
			var upB: Vector3 = _player.global_transform.basis.y
			var sideB: Vector3 = upB.cross(Vector3(randf_range(-1, 1),
				randf_range(-1, 1), randf_range(-1, 1))).normalized()
			if sideB.length() < 0.5:
				sideB = upB.cross(Vector3.RIGHT).normalized()
			big.global_position = _player.global_position \
				+ sideB * 220.0 + upB * randf_range(40.0, 80.0)
	if Game.wrath >= 40.0:
		if live.size() < 3 and _stalker_cd <= 0.0 and _player != null:
			_stalker_cd = 7.0
			var stk := Stalker.new()
			add_child(stk)
			var up9: Vector3 = _player.global_transform.basis.y
			var side9: Vector3 = up9.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1),
				randf_range(-1, 1))).normalized()
			if side9.length() < 0.5:
				side9 = up9.cross(Vector3.RIGHT).normalized()
			stk.global_position = _player.global_position \
				+ side9 * 45.0 + up9 * randf_range(4.0, 12.0)
	elif Game.wrath < 25.0:
		for st2 in live:
			st2.depart()

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

	# APRON: flush collision ring around the mouth. The mesh cut is
	# ragged triangles stretching past the square shaft; this invisible
	# floor stops jumps at the crack from slipping into the hollow
	var aout: float = clampf(4.8 + R * 0.14, 10.0, 30.0)
	var aw := aout - 4.45
	var amid := (aout + 4.45) * 0.5
	for aspec in [[Vector3(aout * 2.0, 0.5, aw), Vector3(0, 0, amid)],
			[Vector3(aout * 2.0, 0.5, aw), Vector3(0, 0, -amid)],
			[Vector3(aw, 0.5, 8.9), Vector3(amid, 0, 0)],
			[Vector3(aw, 0.5, 8.9), Vector3(-amid, 0, 0)]]:
		var ab9 := StaticBody3D.new()
		var acs := CollisionShape3D.new()
		var abs9 := BoxShape3D.new()
		abs9.size = aspec[0]
		acs.shape = abs9
		ab9.add_child(acs)
		add_child(ab9)
		ab9.global_transform = Transform3D(B, C + dir * (R - 0.27))
		ab9.translate_object_local(aspec[1])

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

	# collar: the cut faces gape wider than the shaft -- seal the gap
	for cspec9 in [[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, 3.4)],
			[Vector3(14.0, 9.0, 0.6), Vector3(0, 0, -3.4)],
			[Vector3(0.6, 9.0, 14.0), Vector3(3.4, 0, 0)],
			[Vector3(0.6, 9.0, 14.0), Vector3(-3.4, 0, 0)]]:
		var colb := StaticBody3D.new()
		var colcs := CollisionShape3D.new()
		var colbs := BoxShape3D.new()
		colbs.size = cspec9[0]
		colcs.shape = colbs
		colb.add_child(colcs)
		add_child(colb)
		colb.global_transform = Transform3D(B, C + dir * (R - 2.5))
		colb.translate_object_local(cspec9[1])
	var mine := {
		"body": b, "dir": dir, "B": B, "cham_y": cham_y,
		"group": "mine_" + str(b.name), "res": res_id, "res_n": res_n,
		"color": ore_col, "count": ore_count,
	}
	_mines.append(mine)
	_spawn_chamber_ore(mine, ore_count)
	# CAVE DRESSING: stalactites off the ceiling, stalagmites off the
	# floor, rubble -- and in the Dude system (Verdant excepted) the
	# shafts are TECHY: steel support ribs and glowing conduit strips.
	var techy: bool = b.center.length() < 12000.0 and str(b.kind) != "life"
	var drng := RandomNumberGenerator.new()
	drng.seed = int(b.radius * 77.0) + str(b.name).length()
	var rockc := Color("#3a2f48")
	for i in 26:
		var px := drng.randf_range(-15.0, 15.0)
		var pz := drng.randf_range(-15.0, 15.0)
		if absf(px) < 5.0 and absf(pz) < 5.0:
			continue   # the shaft landing stays clear
		var hang := drng.randf() < 0.5
		var tip := MeshInstance3D.new()
		var tcm := CylinderMesh.new()
		var trr := drng.randf_range(0.25, 0.55)
		tcm.top_radius = trr if hang else 0.0
		tcm.bottom_radius = 0.0 if hang else trr
		tcm.height = drng.randf_range(1.2, 3.6)
		tcm.radial_segments = 7
		tip.mesh = tcm
		tip.material_override = Surfaces.stone(rockc.lightened(drng.randf() * 0.18))
		add_child(tip)
		var ty := (cham_y + 5.4 - tcm.height * 0.5) if hang \
			else (cham_y - 5.4 + tcm.height * 0.5)
		tip.global_transform = Transform3D(B, C + B * Vector3(px, ty, pz))
	for i in 10:
		var rb9 := MeshInstance3D.new()
		var rbm9 := BoxMesh.new()
		var rs9 := drng.randf_range(0.4, 1.1)
		rbm9.size = Vector3(rs9, rs9 * 0.7, rs9)
		rb9.mesh = rbm9
		rb9.material_override = Surfaces.stone(rockc.lightened(drng.randf() * 0.12))
		add_child(rb9)
		rb9.global_transform = Transform3D(B, C + B * Vector3(
			drng.randf_range(-15.0, 15.0), cham_y - 5.3, drng.randf_range(-15.0, 15.0)))
		rb9.rotate_object_local(Vector3.UP, drng.randf() * TAU)
	if techy:
		var steel9 := Surfaces.metal(Color("#4a505c"))
		for i in 8:
			# steel support ribs pinned along the walls
			var along := drng.randf_range(-14.0, 14.0)
			var wall9 := i % 4
			var wx: float = [16.6, -16.6, along, along][wall9]
			var wz: float = [along, along, 16.6, -16.6][wall9]
			var rib := MeshInstance3D.new()
			var ribm := BoxMesh.new()
			ribm.size = Vector3(0.6, 11.5, 0.6)
			rib.mesh = ribm
			rib.material_override = steel9
			add_child(rib)
			rib.global_transform = Transform3D(B, C + B * Vector3(wx, cham_y, wz))
		for espec9 in [[Vector3(0, 5.55, 16.1), Vector3(32, 0.1, 0.3)],
				[Vector3(0, 5.55, -16.1), Vector3(32, 0.1, 0.3)],
				[Vector3(16.1, 5.55, 0), Vector3(0.3, 0.1, 32)],
				[Vector3(-16.1, 5.55, 0), Vector3(0.3, 0.1, 32)]]:
			# conduit glow strips tracing the ceiling edges
			var strip := MeshInstance3D.new()
			var stm9 := BoxMesh.new()
			stm9.size = espec9[1]
			strip.mesh = stm9
			strip.material_override = Destructible.make_material(Color("#5adfff"), 1.8)
			add_child(strip)
			strip.global_transform = Transform3D(B,
				C + B * (Vector3(espec9[0].x, cham_y + espec9[0].y, espec9[0].z)))
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
	# stone shader, not flat plastic -- caves are made of rock
	mi.material_override = Surfaces.stone(c.lightened(0.12)) if emit <= 0.25 \
		else Destructible.make_material(c, emit)
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

	# a starter ATM near spawn -- except in REACTOR SCHOOL, where a
	# mystery money box next to the lesson reads as reactor equipment
	if not (Game.tutorial_session and Game.tutorial_mode == "reactor"):
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
	e["warp"] = float(state.get("warp", 1.0))
	# flying friends show as a rocket, not a floating body
	_sync_peer_rocket(e, id, bool(state.get("mk2", false)))
	# player origin = capsule CENTRE; the avatar model's origin is its FEET
	var foot := pos - up.normalized() * (0.0 if e["in_rocket"] else 1.0)
	# INTERPOLATION TARGET, not a teleport: packets land at 10Hz; the
	# avatar chases the predicted position every frame in
	# _animate_avatars. Half-lerp-on-receive was both the stutter AND
	# the trailing-behind.
	var nowp := Time.get_ticks_msec() / 1000.0
	var dtp := clampf(nowp - float(e.get("pkt_t", nowp - 0.1)), 0.033, 0.3)
	var old_t: Vector3 = e.get("target", foot)
	e["tvel"] = (foot - old_t) / dtp
	e["target"] = foot
	e["pkt_t"] = nowp
	var x := up.cross(fwd)
	if x.length() > 0.001 and fwd.length() > 0.001:
		e["tbasis"] = Basis(x.normalized(), up.normalized(),
			-fwd.normalized()).orthonormalized()
	if av.global_position.distance_to(foot) > 40.0:
		av.global_position = foot   # true teleports snap
		e["tvel"] = Vector3.ZERO
	e["speed"] = lerpf(float(e["speed"]), (e["tvel"] as Vector3).length(), 0.5)
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
		# chase the predicted position: target + velocity * packet age.
		# smooth at every frame rate, no trailing, no 10Hz stutter.
		var av9: Node3D = e["root"]
		if is_instance_valid(av9) and e.has("target"):
			var age := clampf(Time.get_ticks_msec() / 1000.0 \
				- float(e.get("pkt_t", 0.0)), 0.0, 0.25)
			var pred: Vector3 = (e["target"] as Vector3) \
				+ (e.get("tvel", Vector3.ZERO) as Vector3) * age
			av9.global_position = av9.global_position.lerp(pred,
				minf(1.0, delta * 14.0))
			if e.has("tbasis"):
				av9.global_transform.basis = av9.global_transform.basis \
					.orthonormalized().slerp(e["tbasis"], minf(1.0, delta * 10.0))
		h.visible = not e["in_rocket"]
		if e["in_rocket"]:
			continue
		h.set_jetpack(e["jet"], e["jet"] and not e["grounded"])
		h.animate(float(e["speed"]), bool(e["grounded"]), delta,
			e["jet"] and not e["grounded"])

func peer_in_rocket(id: int) -> bool:
	return _remote_avatars.has(id) \
		and bool(_remote_avatars[id].get("in_rocket", false))

func peer_warp(id: int) -> float:
	if _remote_avatars.has(id):
		return float(_remote_avatars[id].get("warp", 1.0))
	return 1.0

## The pilot's rocket-display transform, for seating passengers ON the
## ship instead of on the pilot's head. Null while they're on foot.
func peer_rocket_tf(id: int):
	if not _remote_avatars.has(id):
		return null
	var rn = _remote_avatars[id].get("rocket_node")
	if rn != null and is_instance_valid(rn):
		return (rn as Node3D).global_transform
	return null

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
		# WHICH WAY IT FACED. Saving only 'up' meant every machine, TV
		# and camera came back on rejoin pointing wherever _basis_from_up
		# happened to land -- the synth case turned its back on the room.
		var fwdz: Vector3 = n.global_transform.basis.z
		var e := {
			"id": str(n.get_meta("placed_id")),
			"pos": [n.global_position.x, n.global_position.y, n.global_position.z],
			"up": [up.x, up.y, up.z],
			"fwd": [fwdz.x, fwdz.y, fwdz.z],
			"owner": str(n.get_meta("owner", "")),
		}
		if n is Machine:
			e["buf"] = n.buf
			e["slot_in"] = n.in_slot
			e["slot_out"] = n.out_slot
			var wo: Array = []
			for k in n.wires_out.size():
				var w = n.wires_out[k]
				# VALIDITY FIRST. A freed node blows up on `is`, and that
				# error aborts collect_world entirely -- which is how a
				# whole base once got saved as an empty world. Never ask
				# a dead reference what type it is.
				if not is_instance_valid(w):
					continue
				if w is Machine.CoilNode and is_instance_valid(w.host) and idx.has(w.host):
					wo.append([idx[w.host], -1])   # -1 = "that machine's coil"
				elif idx.has(w):
					wo.append([idx[w], int(n.wire_ports[k]) if k < n.wire_ports.size() else k + 1])
			var fo: Array = []
			for k2 in n.funnels_out.size():
				var f = n.funnels_out[k2]
				if not is_instance_valid(f):
					continue
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
		if n is Factory.BenchLab:
			e["bottles"] = n.bottles.duplicate()
		if n is ArcadeMachine:
			e["arcade"] = n.save_data()
		if n is Factory.AlloyFurnace or n is Factory.Processor:
			e["recipe"] = n.recipe
			e["charge"] = n.store.duplicate()
		if n is ModSynth:
			e["synth"] = n.patch_data()
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
		if n is Factory.BenchLab:
			var bt = e.get("bottles", {})
			if bt is Dictionary:
				for k in bt.keys():
					n.bottles[str(k)] = int(bt[k])
		if n is ArcadeMachine:
			var ad = e.get("arcade", {})
			if ad is Dictionary:
				n.load_data(ad)
		if n is Factory.AlloyFurnace or n is Factory.Processor:
			n.recipe = str(e.get("recipe", n.recipe))
			var chg = e.get("charge", {})
			if chg is Dictionary:
				for k in chg.keys():
					n.store[str(k)] = int(chg[k])
		if n is ModSynth:
			n.set_meta("synth_data", e.get("synth", {}))
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
			# the saved facing, replayed: flatten it against this spot's
			# up and rebuild the basis around it
			var gf = e.get("fwd", null)
			if gf is Array and (gf as Array).size() == 3 \
					and not (n is House) and not (n is Furniture):
				var gz := Vector3(float(gf[0]), float(gf[1]), float(gf[2]))
				gz = gz - up * gz.dot(up)
				if gz.length() > 0.01:
					gz = gz.normalized()
					n.global_transform = Transform3D(
						Basis(up.cross(gz).normalized(), up, gz).orthonormalized(), pos)
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

	# third pass: saved house links get their doorways and hallways
	# re-cut -- the data always survived rejoins, the holes didn't
	var relinked := {}
	for n5 in made:
		if not (n5 is House):
			continue
		for lv2 in n5.links:
			var partner: House = null
			for n6 in made:
				if n6 is House and n6.slot == int(lv2):
					partner = n6
					break
			if partner == null:
				continue
			var pk := "%d_%d" % [mini(n5.slot, partner.slot), maxi(n5.slot, partner.slot)]
			if relinked.has(pk):
				continue
			relinked[pk] = true
			n5.call_deferred("relink", partner)

func _spawn_world_obj(id: String) -> Node3D:
	match id:
		"tv": return TVSet.TV.new()
		"tvbig":
			var tvb := TVSet.TV.new()
			tvb.big = true
			return tvb
		"camtv": return TVSet.SpyCam.new()
		"chest": return Chest.new()
		"spawnbeacon": return SpawnBeacon.new()
		"furnace": return Furnace.new()
		"coinifier": return Coinifier.new()
		"autominer": return AutoMiner.new()
		"autominer2": return AutoMiner.new().setup(2)
		"autominer3": return AutoMiner.new().setup(3)
		"crusher": return Factory.Crusher.new()
		"benchlab": return Factory.BenchLab.new()
		"ultimabatt": return EMachines.UltimaBattery.new()
		"chemlab": return Factory.Processor.new().setup("chem", 1)
		"chemlab2": return Factory.Processor.new().setup("chem", 2)
		"chemlab3": return Factory.Processor.new().setup("chem", 3)
		"electrolyser": return Factory.Processor.new().setup("electro", 1)
		"electrolyser2": return Factory.Processor.new().setup("electro", 2)
		"separator": return Factory.Processor.new().setup("sep", 1)
		"separator2": return Factory.Processor.new().setup("sep", 2)
		"cryoplant": return Factory.Processor.new().setup("cryo", 1)
		"cryoplant2": return Factory.Processor.new().setup("cryo", 2)
		"voidsiphon": return Factory.Processor.new().setup("void", 3)
		"growthvat": return Factory.Processor.new().setup("vat", 3)
		"arcade": return ArcadeMachine.new()
		"discmaker": return DiscMaker.new()
		"alloyfurn": return Factory.AlloyFurnace.new().setup(1)
		"alloyfurn2": return Factory.AlloyFurnace.new().setup(2)
		"alloyfurn3": return Factory.AlloyFurnace.new().setup(3)
		"generator": return EMachines.Generator.new()
		"coaldrill": return EMachines.CoalDrill.new()
		"bioreactor": return EMachines.Bioreactor.new()
		"rtg": return EMachines.RTG.new()
		"netanalyser": return EMachines.NetworkAnalyser.new()
		"creativegen": return EMachines.CreativeGen.new()
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
		"modsynth": return ModSynth.new()
		"modsynth2":
			var ms2 := ModSynth.new()
			ms2.mk2 = true
			return ms2
		"modsynth3":
			var ms3 := ModSynth.new()
			ms3.mk3 = true
			return ms3
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

# --------------------------------------------------------------- helpers

func _surface_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

## Give a decorative mesh a real body: StaticBody3D + shape riding the
## mesh's transform, so Harold's geology is climbable, not a hologram.
func _rockify(mi: MeshInstance3D, shape: Shape3D) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	mi.add_child(sb)

## One carved rock needle at `alt` along `cd` (base shards only when
## it stands on actual ground).
func _h_spike(b, cd: Vector3, alt: float, hrng: RandomNumberGenerator) -> void:
	var sb8 := _basis_from_up(cd)
	var segs := 3 + hrng.randi() % 3
	var sh8 := 0.0
	var bw := hrng.randf_range(1.4, 2.6)
	for sg in segs:
		var nk := MeshInstance3D.new()
		var nkm := CylinderMesh.new()
		var frac := 1.0 - float(sg) / float(segs)
		nkm.bottom_radius = bw * frac
		nkm.top_radius = bw * maxf(0.06, frac - 1.0 / float(segs)) * 0.8
		nkm.height = hrng.randf_range(2.2, 4.6)
		nkm.radial_segments = 6
		nk.mesh = nkm
		nk.material_override = Surfaces.stone(
			Color("#6f655a").lightened(float(sg) * 0.06))
		var nsh := CylinderShape3D.new()
		nsh.radius = maxf(0.12, nkm.bottom_radius * 0.8)
		nsh.height = nkm.height
		_rockify(nk, nsh)
		add_child(nk)
		nk.global_transform = Transform3D(sb8,
			b.center + cd * (alt + sh8 + nkm.height * 0.5 - 0.4))
		nk.rotate_object_local(Vector3.UP, hrng.randf() * TAU)
		sh8 += nkm.height * 0.94
	if alt <= float(b.radius) + 0.01:
		for sh9 in 2:
			var lsh := MeshInstance3D.new()
			var lshm := BoxMesh.new()
			lshm.size = Vector3(0.5, hrng.randf_range(1.6, 3.0), 0.5)
			lsh.mesh = lshm
			lsh.material_override = Surfaces.stone(Color("#665c50"))
			var lbs := BoxShape3D.new()
			lbs.size = lshm.size
			_rockify(lsh, lbs)
			add_child(lsh)
			lsh.global_transform = Transform3D(sb8,
				b.center + cd * (alt + lshm.size.y * 0.3))
			lsh.rotate_object_local(Vector3.RIGHT, hrng.randf_range(-0.5, 0.5))
			lsh.rotate_object_local(Vector3.BACK, hrng.randf_range(-0.5, 0.5))
			lsh.position += sb8 * Vector3(hrng.randf_range(-2.2, 2.2), 0,
				hrng.randf_range(-2.2, 2.2))

## The ANCIENT of Harold: the stele again -- but softened. Tapering
## tiers with 45-degree diamond transition layers (nothing reads as a
## plain cube), and a crown only a little wider than the waist and
## SHORT, so the silhouette is a worn monolith, not a T. The waist
## carries a genuinely carved tetrahedral socket: the front plate is a
## custom mesh with the triangular mouth cut through it, three planar
## walls sinking to a black apex. Six pictograms ring the mouth.
## It does nothing. Yet.
var _h_monolith: Monolith = null
var _earth_monolith: Monolith = null
var _boundary_mesh: Node3D = null
var _boundary_mat: ShaderMaterial = null
var _boundary_fade_mats: Array = []
var _void_shells: Array = []   # white shell + star ball: outside-only

## a monolith was fed (locally or by a peer): raise the next stele,
## refresh every tracker strip
## instant (no animation) sync of everything monolith-stage-driven --
## used right after a save restores the stage
func _monolith_snap() -> void:
	if Game.monolith_stage == 0:
		# fresh chain: Harold stands on the surface, Earth sleeps below
		if _h_monolith != null and _h_monolith._root != null:
			_h_monolith._root.visible = true
			_h_monolith._root.global_position = \
				(_h_monolith.body.center as Vector3) + _h_monolith.dir \
				* float(_h_monolith.body.radius)
			_h_monolith._busy = false
		if _earth_monolith != null and _earth_monolith._root != null:
			_earth_monolith.risen = false
			_earth_monolith._root.global_position = \
				(_earth_monolith.body.center as Vector3) \
				+ _earth_monolith.dir \
				* (float(_earth_monolith.body.radius) - Monolith.RISE_DEPTH)
	if Game.monolith_stage >= 1:
		if _h_monolith != null and _h_monolith._root != null:
			_h_monolith._root.visible = false
			_h_monolith._root.global_position = _h_monolith.body.center \
				+ _h_monolith.dir * (float(_h_monolith.body.radius)
				- Monolith.RISE_DEPTH)
		if _earth_monolith != null and not _earth_monolith.risen:
			_earth_monolith.risen = true
			if _earth_monolith._root != null:
				_earth_monolith._root.global_position = \
					(_earth_monolith.body.center as Vector3) \
					+ _earth_monolith.dir * float(_earth_monolith.body.radius)
	if _boundary_mesh != null:
		_boundary_mesh.visible = Game.monolith_stage >= 8
	# THE UNIVERSE FROM OUTSIDE: a ball of night. Front faces only, so
	# it is invisible from within -- but stand in the white void and
	# look back, and there it is: black, full of stars, everything you
	# know inside it.
# (night veil removed -- the star ball + white shell do this with
	# real geometry now)
	for tr9 in get_tree().get_nodes_in_group("mono_tracker"):
		if tr9.has_method("refresh"):
			tr9.refresh()

func _on_monolith_advanced() -> void:
	if _boundary_mesh != null:
		_boundary_mesh.visible = Game.monolith_stage >= 8 and not _shatter_seq
	if Game.monolith_stage >= 1 and _earth_monolith != null \
			and not _earth_monolith.risen:
		_earth_monolith.rise()
	for cm9 in get_tree().get_nodes_in_group("chain_stele"):
		if cm9 is Monolith and cm9.stage <= Game.monolith_stage \
				and not cm9.risen:
			cm9.rise()
	for tr9 in get_tree().get_nodes_in_group("mono_tracker"):
		if tr9.has_method("refresh"):
			tr9.refresh()

func _h_monument(b, hrng: RandomNumberGenerator) -> void:
	# the YELLOW monolith: link 0 of the chain. Feeding it SPECIMEN 4
	# starts everything. Already fed on an older save? It sits sunk.
	_h_monolith = Monolith.new()
	add_child(_h_monolith)
	_h_monolith.stage = 0
	_build_monument(b, _h_dir(hrng), _h_monolith)
	if Game.monolith_stage > 0:
		_h_monolith._root.visible = false
		_h_monolith._root.global_position = (b.center as Vector3) \
			+ _h_monolith.dir * (float(b.radius) - Monolith.RISE_DEPTH)

## THE MONUMENT, shared by every link of the chain: identical stone
## everywhere -- tiers, diamonds, the tetrahedral socket, the glyph
## ring, the crown pictogram. Only the crown's LOCATION HINT differs
## per stele (and Earth's is a placeholder until the lime source is
## decided).
func _build_monument(b, dir: Vector3, mono: Monolith) -> void:
	# chips + weathering roll from the monument's own seeded dice so
	# every stele weathers identically-in-kind but uniquely-in-detail
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 618 + mono.stage * 77
	var bas := _basis_from_up(dir)
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(bas, (b.center as Vector3)
		+ dir * float(b.radius))
	mono.body = b
	mono.dir = dir
	mono._root = root
	var stone := Surfaces.stone(Color("#8a7f70"))
	var dark := Surfaces.stone(Color("#6b6154"))
	# tiers: [size, position, yaw_degrees] -- diamonds break the cubic
	# monotony; the waist sits back so its face never fills the mouth
	for spec in [[Vector3(11.0, 2.4, 7.0), Vector3(0, 0.8, 0), 0.0],
			[Vector3(8.0, 2.0, 5.5), Vector3(0, 2.9, 0), 0.0],
			[Vector3(5.6, 0.7, 5.6), Vector3(0, 4.2, 0), 45.0],
			[Vector3(5.0, 4.5, 1.6), Vector3(0, 6.35, -1.1), 0.0],
			[Vector3(4.2, 0.6, 4.2), Vector3(0, 8.85, 0), 45.0],
			[Vector3(6.0, 1.6, 3.0), Vector3(0, 9.9, 0), 0.0],
			[Vector3(3.6, 0.9, 2.4), Vector3(0, 11.1, 0), 0.0]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = dark if float(spec[2]) > 0.0 else stone
		mi.position = spec[1]
		mi.rotation_degrees.y = float(spec[2])
		var shp := BoxShape3D.new()
		shp.size = spec[0]
		_rockify(mi, shp)
		root.add_child(mi)
	# weathered chips: it has STOOD here
	for i in 5:
		var ch := MeshInstance3D.new()
		var chm := BoxMesh.new()
		chm.size = Vector3(hrng.randf_range(0.5, 1.2), hrng.randf_range(0.3, 0.7),
			hrng.randf_range(0.5, 1.0))
		ch.mesh = chm
		ch.material_override = dark
		ch.position = Vector3(hrng.randf_range(-4.5, 4.5), 0.3, hrng.randf_range(2.8, 4.4))
		ch.rotation = Vector3(hrng.randf_range(-0.3, 0.3), hrng.randf() * TAU, 0)
		root.add_child(ch)
	# THE SOCKET: the waist's front is a custom plate with the triangular
	# mouth REALLY cut through it -- ring plate, side skirts back to the
	# structural box, cavity walls to a black apex. True tetrahedron.
	var st8 := SurfaceTool.new()
	st8.begin(Mesh.PRIMITIVE_TRIANGLES)
	var N := 24
	var hx := 2.5
	var hy := 2.25
	var rt := 1.0
	var cy := 6.35
	var zf := 1.8
	# skirts run all the way back to the structural box, which now sits
	# ENTIRELY behind the cavity apex -- nothing left to block the view
	var zback := -0.28
	var apex := Vector3(0, cy, -0.2)
	var stC := Color(0.541, 0.498, 0.439)
	# cut faces: cleaner, cooler grey than the weathered outside -- fresh
	# stone where the tool went through, still fading to black at the apex
	var mouth := Color(0.4, 0.38, 0.35)
	var deep := Color(0.022, 0.022, 0.025)
	var rectp: Array = []
	var holep: Array = []
	for i in N:
		var th := deg_to_rad(90.0 + 360.0 * float(i) / float(N))
		var dv := Vector2(cos(th), sin(th))
		var rr := minf(hx / maxf(0.001, absf(dv.x)), hy / maxf(0.001, absf(dv.y)))
		rectp.append(Vector3(dv.x * rr, cy + dv.y * rr, zf))
		# regular-triangle radius along this ray (vertex at 90 degrees)
		var loc := fposmod(th - deg_to_rad(90.0), TAU / 3.0)
		var rtri := rt * cos(PI / 3.0) / cos(loc - PI / 3.0)
		holep.append(Vector3(dv.x * rtri, cy + dv.y * rtri, zf))
	var addv := func(p: Vector3, col: Color, nrm: Vector3) -> void:
		st8.set_normal(nrm)
		st8.set_color(col)
		st8.add_vertex(p)
	for i in N:
		var j := (i + 1) % N
		# face plate ring: the mouth is genuinely IN the plate
		addv.call(rectp[i], stC, Vector3.BACK)
		addv.call(holep[i], stC, Vector3.BACK)
		addv.call(rectp[j], stC, Vector3.BACK)
		addv.call(rectp[j], stC, Vector3.BACK)
		addv.call(holep[i], stC, Vector3.BACK)
		addv.call(holep[j], stC, Vector3.BACK)
		# cavity wall sinking to the apex
		var wn: Vector3 = ((holep[j] as Vector3) - holep[i]).cross(apex - holep[i]).normalized()
		if wn.z < 0.0:
			wn = -wn
		addv.call(holep[i], mouth, wn)
		addv.call(holep[j], mouth, wn)
		addv.call(apex, deep, wn)
		# skirt back to the structural box
		var rb := Vector3(rectp[i].x, rectp[i].y, zback)
		var jb := Vector3(rectp[j].x, rectp[j].y, zback)
		var rn := Vector3(rectp[i].x, rectp[i].y - cy, 0).normalized()
		addv.call(rectp[i], stC, rn)
		addv.call(rb, stC, rn)
		addv.call(rectp[j], stC, rn)
		addv.call(rectp[j], stC, rn)
		addv.call(rb, stC, rn)
		addv.call(jb, stC, rn)
	var plate := MeshInstance3D.new()
	plate.mesh = st8.commit()
	# the plate wears the SAME stone grain as the rest of the monument --
	# vertex colors carry the cavity's depth fade, the fbm carries the rock
	var psh2 := Shader.new()
	psh2.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 vpos;
varying vec4 vcol;
float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * amp;
		p *= 2.1;
		amp *= 0.5;
	}
	return v;
}
void vertex() {
	vpos = VERTEX;
	vcol = COLOR;
}
void fragment() {
	float n = fbm(vpos * 4.0);
	vec3 col = vcol.rgb * (0.72 + 0.4 * n);
	float seam = smoothstep(0.46, 0.5, abs(fract(fbm(vpos * 2.4) * 3.0) - 0.5));
	col *= 0.82 + 0.18 * seam;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
	var pmat := ShaderMaterial.new()
	pmat.shader = psh2
	plate.material_override = pmat
	# solid hitbox over the whole carved front -- you don't fit in the
	# mouth anyway, so the collider ignores the carving
	var pbody := Monolith.MonoSocket.new()
	pbody.host = mono
	var pcs := CollisionShape3D.new()
	var pbs := BoxShape3D.new()
	pbs.size = Vector3(hx * 2.0, hy * 2.0, zf - zback)
	pcs.shape = pbs
	pcs.position = Vector3(0, cy, (zf + zback) * 0.5)
	pbody.add_child(pcs)
	plate.add_child(pbody)
	root.add_child(plate)
	# six pictograms ringing the mouth
	# ring nudged up + tightened so the bottom glyph clears the diamond
	# tier instead of sinking into it
	for g in 6:
		var ga := TAU * float(g) / 6.0 + 0.26
		_h_glyph(root, g, Vector3(cos(ga) * 1.5, cy + 0.2 + sin(ga) * 1.5, 1.84))
	# and up TOP, alone on the big crown tier. NOBODY carved these --
	# the stele reflects what it points at; the glyphs are a magical
	# relation to the location of each piece. Harold's faces the
	# machine planet; Earth's shows a little house, because the lime
	# piece waits under a roof on Earth.
	_h_glyph(root, 6 if mono.stage == 0 else (7 if mono.stage == 1 else 8),
		Vector3(0, 9.9, 1.55))

## One carved pictogram, flat on the monument face, drawn with thin
## engraved bars. 0: the stalker-thulhus (tentacles going down). 1: the
## black hole with its ring. 2: an icosahedron down its five-fold axis.
## 3: the triangle -- the THING. 4: the noodle god (the eye, four
## reaching arms). 5: the fork.
func _h_glyph(root: Node3D, kind: int, at: Vector3) -> void:
	var ink := Surfaces.stone(Color("#332a1f"))
	var g := Node3D.new()
	g.position = at
	root.add_child(g)
	var bar := func(sz: Vector2, pos: Vector2, rot: float) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sz.x, sz.y, 0.05)
		mi.mesh = bm
		mi.material_override = ink
		mi.position = Vector3(pos.x, pos.y, 0)
		mi.rotation_degrees.z = rot
		g.add_child(mi)
	var ring := func(r_in: float, r_out: float, tilt: float) -> void:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r_in
		tm.outer_radius = r_out
		mi.mesh = tm
		mi.material_override = ink
		mi.rotation_degrees = Vector3(90, 0, tilt)
		g.add_child(mi)
	match kind:
		0:
			# the stalker-thulhus: the ring of flesh, the eye-dot, the
			# tentacles going down
			ring.call(0.18, 0.24, 0.0)
			bar.call(Vector2(0.08, 0.08), Vector2.ZERO, 0.0)
			for si in 3:
				bar.call(Vector2(0.05, 0.3), Vector2(-0.12 + 0.12 * float(si), -0.36), 18.0 - 14.0 * float(si))
				bar.call(Vector2(0.05, 0.18), Vector2(-0.14 + 0.12 * float(si), -0.52), -20.0 + 16.0 * float(si))
		1:
			# the hole and its ring
			ring.call(0.1, 0.2, 0.0)
			bar.call(Vector2(0.62, 0.05), Vector2.ZERO, -18.0)
			bar.call(Vector2(0.4, 0.04), Vector2(0, -0.07), -18.0)
		2:
			# an ACTUAL icosahedron in 3D perspective: the real solid's
			# projected vertices, all 30 edges -- hidden edges etched
			# thinner, front edges deep, like a proper technical carving
			for ed in [
				[0.380, -0.001, 0.169, -0.288, true],
				[0.380, -0.001, 0.171, 0.126, false],
				[0.380, -0.001, 0.170, -0.261, false],
				[0.380, -0.001, 0.169, 0.083, true],
				[0.380, -0.001, 0.170, 0.339, true],
				[-0.169, 0.288, 0.171, 0.126, false],
				[-0.169, 0.288, -0.169, -0.083, false],
				[-0.169, 0.288, -0.170, 0.261, true],
				[-0.169, 0.288, -0.380, 0.001, false],
				[-0.169, 0.288, 0.170, 0.339, false],
				[-0.170, -0.339, 0.169, -0.288, true],
				[-0.170, -0.339, -0.169, -0.083, false],
				[-0.170, -0.339, 0.170, -0.261, false],
				[-0.170, -0.339, -0.380, 0.001, false],
				[-0.170, -0.339, -0.171, -0.126, true],
				[0.169, -0.288, 0.170, -0.261, false],
				[0.169, -0.288, 0.169, 0.083, true],
				[0.169, -0.288, -0.171, -0.126, true],
				[0.171, 0.126, -0.169, -0.083, false],
				[0.171, 0.126, 0.170, -0.261, false],
				[0.171, 0.126, 0.170, 0.339, false],
				[-0.169, -0.083, 0.170, -0.261, false],
				[-0.169, -0.083, -0.380, 0.001, false],
				[-0.170, 0.261, -0.380, 0.001, true],
				[-0.170, 0.261, 0.169, 0.083, true],
				[-0.170, 0.261, -0.171, -0.126, true],
				[-0.170, 0.261, 0.170, 0.339, true],
				[-0.380, 0.001, -0.171, -0.126, true],
				[0.169, 0.083, -0.171, -0.126, true],
				[0.169, 0.083, 0.170, 0.339, true],
			]:
				var a4 := Vector2(float(ed[0]), float(ed[1]))
				var b4 := Vector2(float(ed[2]), float(ed[3]))
				bar.call(Vector2(a4.distance_to(b4), 0.045 if bool(ed[4]) else 0.022),
					(a4 + b4) * 0.5, rad_to_deg((b4 - a4).angle()))
		3:
			# the pyramid
			# exact endpoints: the sides MEET the base corners instead of
			# skidding past them
			var tA := Vector2(0, 0.3)
			var tB := Vector2(-0.28, -0.2)
			var tC := Vector2(0.28, -0.2)
			for pr in [[tA, tB], [tB, tC], [tC, tA]]:
				var a5: Vector2 = pr[0]
				var b5: Vector2 = pr[1]
				bar.call(Vector2(a5.distance_to(b5) - 0.01, 0.05), (a5 + b5) * 0.5,
					rad_to_deg((b5 - a5).angle()))
		4:
			# the noodle god: the eye and its four reaching arms
			ring.call(0.16, 0.22, 0.0)
			bar.call(Vector2(0.1, 0.1), Vector2.ZERO, 45.0)
			for ri in 4:
				var ra := TAU * float(ri) / 4.0 + TAU / 8.0
				bar.call(Vector2(0.14, 0.04), Vector2(cos(ra), sin(ra)) * 0.34, rad_to_deg(ra))
		5:
			# the fork. it is coming.
			bar.call(Vector2(0.06, 0.42), Vector2(0, -0.22), 0.0)
			bar.call(Vector2(0.34, 0.05), Vector2(0, 0.02), 0.0)
		6:
			# BIG COMPUTER: the machine planet itself -- a circle whose
			# FACE is etched with motherboard traces. Everything stays
			# inside the disc: stepped lines, right-angle bends, square
			# pads where they end. Reads as a planet wearing a circuit.
			ring.call(0.3, 0.38, 0.0)
			# trace 1: long horizontal across the upper face, pad at each end
			bar.call(Vector2(0.34, 0.035), Vector2(-0.02, 0.14), 0.0)
			bar.call(Vector2(0.055, 0.055), Vector2(-0.21, 0.14), 0.0)
			bar.call(Vector2(0.055, 0.055), Vector2(0.17, 0.14), 0.0)
			# trace 2: enters left, steps DOWN, runs to a centre pad
			bar.call(Vector2(0.16, 0.035), Vector2(-0.14, 0.0), 0.0)
			bar.call(Vector2(0.1, 0.035), Vector2(-0.06, -0.05), 90.0)
			bar.call(Vector2(0.12, 0.035), Vector2(0.0, -0.1), 0.0)
			bar.call(Vector2(0.055, 0.055), Vector2(0.08, -0.1), 0.0)
			# trace 3: lower right, steps up into the fat pad
			bar.call(Vector2(0.14, 0.035), Vector2(0.12, -0.22), 0.0)
			bar.call(Vector2(0.09, 0.035), Vector2(0.19, -0.18), 90.0)
			bar.call(Vector2(0.07, 0.07), Vector2(0.19, -0.1), 0.0)
			# lone pads: the glowing vias of the motherboard face
			bar.call(Vector2(0.045, 0.045), Vector2(-0.18, -0.2), 0.0)
			bar.call(Vector2(0.045, 0.045), Vector2(0.02, 0.26), 0.0)
			for pi3 in 3:
				bar.call(Vector2(0.05, 0.24), Vector2(-0.14 + 0.14 * float(pi3), 0.16), 0.0)
		8:
			# PLACEHOLDER: a ring holding a single silent bar. The stele
			# has not decided what it points at yet.
			ring.call(0.3, 0.38, 0.0)
			bar.call(Vector2(0.3, 0.05), Vector2.ZERO, 0.0)
		7:
			# HAROLD'S HOUSE: the lime piece hides under a roof. Ground
			# line, two walls, a gable, a door, and the crooked chimney
			# he never fixed.
			bar.call(Vector2(0.4, 0.035), Vector2(0, -0.3), 0.0)
			bar.call(Vector2(0.035, 0.3), Vector2(-0.17, -0.14), 0.0)
			bar.call(Vector2(0.035, 0.3), Vector2(0.17, -0.14), 0.0)
			bar.call(Vector2(0.27, 0.035), Vector2(-0.085, 0.12), 50.0)
			bar.call(Vector2(0.27, 0.035), Vector2(0.085, 0.12), -50.0)
			bar.call(Vector2(0.035, 0.14), Vector2(0.06, -0.24), 0.0)
			bar.call(Vector2(0.045, 0.12), Vector2(-0.11, 0.17), 8.0)

## Varnisol fauna is WEIRD: the gentle planet grows strange meat.
## Every animal wears something the rest of the universe doesn't --
## a glowing lantern stalk, forked antlers, or a moss pelt with
## bioluminescent spots. Sometimes two of those.
func _varnisolify(an: Animal) -> void:
	# EXOTIC two-tone hide first: alternating parts in a paired palette
	# no other planet uses. These are not verdant's animals.
	var pals: Array = [["#3ae0c8", "#7a2a8f"], ["#e05a9a", "#2a2f6e"],
		["#d8c84a", "#3a6a4a"], ["#ff8a3a", "#2a4a6e"], ["#b8e0e8", "#5a3a2a"]]
	var pal: Array = pals[randi() % pals.size()]
	# every individual gets its own silhouette too: one stretch vector
	# applied to all its parts -- lanky, squat, towering, wide
	var stretch := Vector3(randf_range(0.8, 1.2), randf_range(0.95, 1.6),
		randf_range(0.8, 1.2))
	var mi_i := 0
	for c in an.find_children("*", "MeshInstance3D", true, false):
		if c is MeshInstance3D:
			c.material_override = Destructible.make_material(
				Color(str(pal[mi_i % 2])), 0.3)
			c.scale = c.scale * stretch
			mi_i += 1
	# ALWAYS two distinct adornments: no plain animals on Varnisol
	var p1 := randi() % 5
	var picks: Array = [p1, (p1 + 1 + randi() % 4) % 5]
	for pick in picks:
		match int(pick):
			0:
				# lantern stalk: anglerfish of the pines
				var stalk := MeshInstance3D.new()
				var stm := CylinderMesh.new()
				stm.top_radius = 0.03
				stm.bottom_radius = 0.05
				stm.height = 0.9
				stalk.mesh = stm
				stalk.material_override = Destructible.make_material(Color("#3a4a3a"), 0.1)
				stalk.position = Vector3(0, 1.15, 0)
				stalk.rotation_degrees = Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
				an.add_child(stalk)
				var bulb := MeshInstance3D.new()
				var blm := SphereMesh.new()
				blm.radius = 0.15
				blm.height = 0.3
				bulb.mesh = blm
				bulb.material_override = Destructible.make_material(Color("#8fffe0"), 2.4)
				bulb.position = Vector3(0, 0.52, 0)
				stalk.add_child(bulb)
			1:
				# forked antlers, asymmetric on purpose
				for side in [-1.0, 1.0]:
					var beam := MeshInstance3D.new()
					var bem := CylinderMesh.new()
					bem.top_radius = 0.025
					bem.bottom_radius = 0.05
					bem.height = randf_range(0.55, 0.85)
					beam.mesh = bem
					beam.material_override = Destructible.make_material(Color("#6a5138"), 0.1)
					beam.position = Vector3(side * 0.22, 0.95, -0.1)
					beam.rotation_degrees = Vector3(randf_range(-20, 5), 0, side * randf_range(24, 40))
					an.add_child(beam)
					for tn in 2:
						var tine := MeshInstance3D.new()
						var tnm := CylinderMesh.new()
						tnm.top_radius = 0.012
						tnm.bottom_radius = 0.028
						tnm.height = randf_range(0.25, 0.4)
						tine.mesh = tnm
						tine.material_override = beam.material_override
						tine.position = Vector3(0, 0.1 + 0.22 * float(tn), 0)
						tine.rotation_degrees = Vector3(0, 0, side * randf_range(30, 55))
						beam.add_child(tine)
			2:
				# moss pelt with glow spots: the forest claims its own
				for mi2 in 3:
					var moss := MeshInstance3D.new()
					var mm2 := BoxMesh.new()
					mm2.size = Vector3(randf_range(0.3, 0.55), 0.08, randf_range(0.3, 0.5))
					moss.mesh = mm2
					moss.material_override = Destructible.make_material(Color("#2f5a30"), 0.15)
					moss.position = Vector3(randf_range(-0.25, 0.25), 0.75 + randf_range(0.0, 0.15),
						randf_range(-0.3, 0.3))
					moss.rotation_degrees.y = randf() * 360.0
					an.add_child(moss)
				for gi in 2:
					var spot := MeshInstance3D.new()
					var spm2 := SphereMesh.new()
					spm2.radius = 0.05
					spm2.height = 0.1
					spot.mesh = spm2
					spot.material_override = Destructible.make_material(Color("#a0ff6a"), 2.0)
					spot.position = Vector3(randf_range(-0.3, 0.3), 0.72, randf_range(-0.3, 0.3))
					an.add_child(spot)
			3:
				# quill fan: a peacock tail of thin spines
				for qi in 5:
					var quill := MeshInstance3D.new()
					var qm := CylinderMesh.new()
					qm.top_radius = 0.0
					qm.bottom_radius = 0.035
					qm.height = randf_range(0.6, 0.9)
					quill.mesh = qm
					quill.material_override = Destructible.make_material(
						Color(str(pal[qi % 2])), 0.8)
					quill.position = Vector3(0, 0.7, 0.35)
					quill.rotation_degrees = Vector3(-38.0, 0, -40.0 + 20.0 * float(qi))
					an.add_child(quill)
			4:
				# a single spiral horn: stacked shrinking rings up a cone
				var horn := MeshInstance3D.new()
				var hm9 := CylinderMesh.new()
				hm9.top_radius = 0.0
				hm9.bottom_radius = 0.09
				hm9.height = 0.85
				horn.mesh = hm9
				horn.material_override = Destructible.make_material(Color("#e8e0cc"), 0.4)
				horn.position = Vector3(0, 1.25, -0.15)
				horn.rotation_degrees = Vector3(randf_range(-12, 4), 0, 0)
				an.add_child(horn)
				for hr in 3:
					var band := MeshInstance3D.new()
					var btm := TorusMesh.new()
					btm.inner_radius = 0.05 - 0.012 * float(hr)
					btm.outer_radius = 0.085 - 0.018 * float(hr)
					band.mesh = btm
					band.material_override = Destructible.make_material(
						Color(str(pal[hr % 2])), 0.7)
					band.position = Vector3(0, -0.22 + 0.22 * float(hr), 0)
					horn.add_child(band)

## A seeded random surface direction (deterministic geology).
func _h_dir(r: RandomNumberGenerator) -> Vector3:
	var v := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))
	return v.normalized() if v.length() > 0.05 else Vector3.UP

func _basis_from_up(up: Vector3) -> Basis:
	var t := Vector3(0, 1, 0)
	if absf(up.dot(t)) > 0.99:
		t = Vector3(1, 0, 0)
	var x := t.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).orthonormalized()


## CTD_TEST=27 -- the modular synth: does the DSP make sound, does the
## rack build, does the patch survive a save?
func _synth_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var p = get_tree().get_first_node_in_group("player")
	# --- 1. the engine, offline: run blocks and listen to the numbers
	var e := SynthEngine.new()
	e.default_patch()
	print("SYNTHTEST shipped rack mods=", e.mods.size(),
		" cables=", e.cables.size(), " (unpatched by design)")
	# the shipped rack is wired but ungated: open the amp so the test
	# can hear whether the chain actually passes signal
	e.set_knob(3, 0, 0.8)   # open the amp: the shipped rack has no gate yet
	print("SYNTHTEST mods=", e.mods.size(), " cables=", e.cables.size(),
		" order=", e._order.size())
	var t0 := Time.get_ticks_usec()
	var peak := 0.0
	var rms := 0.0
	var n := 0
	for i in 400:
		e._block()
		for v in e._mix:
			peak = maxf(peak, absf(v.x))
			rms += v.x * v.x
			n += 1
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var audio_secs := 400.0 * float(SynthEngine.BLK) / SynthEngine.SR
	print("SYNTHTEST dsp %.3fs of cpu for %.3fs of audio (%.0f%% realtime)"
		% [dt, audio_secs, dt / audio_secs * 100.0])
	print("SYNTHTEST peak=%.4f rms=%.4f%s" % [peak, sqrt(rms / float(n)),
		"   <-- SILENT!" if peak < 0.001 else ""])
	# EVERY module in the catalogue must have DSP behind it
	var all_eng := SynthEngine.new()
	for id0 in SynthMods.ids():
		all_eng.add_mod(id0, "dude")
	for i in 8:
		all_eng._block()
	# draw every panel once: a widget with no drawing shows up as a blank
	var dummy := Control.new()
	add_child(dummy)
	for mi1 in all_eng.mods.size():
		SynthPaint.draw_module(dummy, all_eng.mods[mi1], Vector2.ZERO, 3.0,
			all_eng, mi1)
	dummy.queue_free()
	print("SYNTHTEST widgets with NO drawing: ", SynthPaint.undrawn.keys(),
		"   <-- BLANK PANELS" if SynthPaint.undrawn.size() > 0 else "   (all drawn)")
	print("SYNTHTEST modules with NO DSP: ", all_eng.unhandled.keys(),
		"   <-- SILENT MODULES" if all_eng.unhandled.size() > 0 else "   (all implemented)")
	# every module type, instantiated and run, to catch a bad branch
	for id in SynthMods.ids():
		var e2 := SynthEngine.new()
		e2.add_mod(id, "dude")
		e2.add_mod("out", "dude")
		for k in 8:
			e2._block()
		var bad := false
		for v in e2._bus:
			if is_nan(v) or is_inf(v):
				bad = true
				break
		print("SYNTHTEST module %-8s ok=%s fits=%s" % [id, not bad, SynthMods.fits(id)])
	# --- 2. the machine in the world
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var ms := ModSynth.new()
	add_child(ms)
	ms.set_meta("placed_id", "modsynth")
	ms.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 4.0)
	await get_tree().create_timer(0.6).timeout
	print("SYNTHTEST rack hw surfaces=", (ms._hw.mesh.get_surface_count() if ms._hw.mesh else 0),
		" cable surfaces=", (ms._cables.mesh.get_surface_count() if ms._cables.mesh else 0),
		" panel vp=", ms._vp.size)
	print("SYNTHTEST cores u=", ms.core_ultima, " n=", ms.core_uranium,
		" ready=", ms.ready_to_run(), " drain=%.2f" % ms.drain())
	ms.core_ultima = true
	ms.core_uranium = true
	ms.buf = 600.0
	for i in 6:
		ms.buf = 600.0
		await get_tree().create_timer(0.4).timeout
	print("SYNTHTEST powered=", ms.powered, " running=", ms.engine.running,
		" playing=", ms._ply.playing, " cpu=%.3f" % ms.engine.cpu)
	# --- 3. the patch survives the round trip
	var d := ms.patch_data()
	var ms2 := ModSynth.new()
	ms2.set_meta("synth_data", d)
	add_child(ms2)
	ms2.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 9.0)
	await get_tree().create_timer(0.4).timeout
	print("SYNTHTEST roundtrip mods=", ms2.engine.mods.size(), "/", ms.engine.mods.size(),
		" cables=", ms2.engine.cables.size(), "/", ms.engine.cables.size(),
		" cores=", ms2.core_ultima, ms2.core_uranium)
	# --- 4. patch editing while it runs
	var before := ms.engine.mods.size()
	# one panel from each house, so the shot proves they are not siblings
	ms.engine.add_mod("vkeys", "dude")
	ms.engine.add_mod("dudemix", "dude")
	ms.engine.add_mod("stonetrig", "mono")
	ms.engine.add_mod("watcher", "mono")
	ms.engine.add_mod("mystery", "mono")
	ms.engine.add_mod("eyefilter", "mono")
	ms.engine.add_mod("beatbox", "dude")
	ms.engine.add_mod("gravity", "mono")
	ms.engine.add_mod("slab", "mono")
	ms.engine.add_mod("wrathtap", "mono")
	ms.engine.add_mod("freeze", "mono")
	ms.engine.add_mod("dustgate", "mono")
	ms.engine.add_mod("roll", "icos")
	var added := ms.engine.add_mod("phaser", "icos")
	var patched: bool = ms.engine.patch(added, 0, 0, 0) if added >= 0 else false
	await get_tree().create_timer(0.5).timeout
	print("SYNTHTEST live edit added=", added, " now=", ms.engine.mods.size(),
		"/", before, " patched=", patched, " still running=", ms.engine.running)
	# --- 4b. the BEATBOX lanes: every one of T1..T4 must fire
	var e3 := SynthEngine.new()
	var bb := e3.add_mod("beatbox", "dude")
	var ck := e3.add_mod("clock", "dude")
	e3.patch(ck, 0, bb, 0)
	for lane in 4:
		for st4 in 16:
			e3.set_step(bb, lane * 16 + st4, 1.0 if st4 % 4 == lane else 0.0)
	var maxo := [0.0, 0.0, 0.0, 0.0, 0.0]
	for i in 900:
		e3._block()
		for oi in 5:
			var base := (1 + bb * SynthEngine.MAXOUT + oi) * SynthEngine.BLK
			for k in SynthEngine.BLK:
				maxo[oi] = maxf(maxo[oi], absf(e3._bus[base + k]))
	print("SYNTHTEST beatbox MIX=%.2f T1=%.1f T2=%.1f T3=%.1f T4=%.1f%s" % [
		maxo[0], maxo[1], maxo[2], maxo[3], maxo[4],
		"   <-- DEAD LANE" if (maxo[2] < 1.0 or maxo[3] < 1.0 or maxo[4] < 1.0) else ""])

	# --- 4c. the Mk2 case: twice the width, one more row
	var big := ModSynth.new()
	big.mk2 = true
	add_child(big)
	big.set_meta("placed_id", "modsynth2")
	big.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 16.0)
	await get_tree().create_timer(0.6).timeout
	print("SYNTHTEST mk2 rows=%d row_hp=%d rack=%.2f x %.2f box=%s vp=%s" % [
		big.engine.rows, big.engine.row_hp, big._rw, big._rh,
		str(big.box_size), str(big._vp.size)])
	var far := big.engine.add_mod("vco", "icos", 3, 150)
	print("SYNTHTEST mk2 far slot: mod=%d row=%d hp=%d (needs row 3 + hp>84 to prove the space is real)" % [
		far, big.engine.mods[far].row if far >= 0 else -1,
		big.engine.mods[far].hp if far >= 0 else -1])

	# --- 4d. the Mk3 case: three Mk1s wide, five rows
	var huge := ModSynth.new()
	huge.mk3 = true
	add_child(huge)
	huge.set_meta("placed_id", "modsynth3")
	huge.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 26.0)
	await get_tree().create_timer(0.6).timeout
	print("SYNTHTEST mk3 rows=%d row_hp=%d rack=%.2f x %.2f box=%s vp=%s" % [
		huge.engine.rows, huge.engine.row_hp, huge._rw, huge._rh,
		str(huge.box_size), str(huge._vp.size)])
	var far3 := huge.engine.add_mod("vco", "mono", 4, 230)
	print("SYNTHTEST mk3 far slot: mod=%d row=%d hp=%d (needs row 4 + hp>168 to prove the wall is real)" % [
		far3, huge.engine.mods[far3].row if far3 >= 0 else -1,
		huge.engine.mods[far3].hp if far3 >= 0 else -1])
	print("SYNTHTEST mk3 rack fits box: ", huge._rh < huge.box_size.y,
		"  ", huge._rw < huge.box_size.x)

	# --- 5. undo/redo on the editor itself
	var ui := SynthUI.new()
	ui.synth = ms
	add_child(ui)
	await get_tree().create_timer(0.4).timeout
	var n0 := ms.engine.mods.size()
	var c0 := ms.engine.cables.size()
	ui._snap("test add")
	ms.engine.add_mod("vco", "dude")
	ms.engine.patch(0, 0, 1, 3)
	var n1 := ms.engine.mods.size()
	ui._undo_step()
	await get_tree().create_timer(0.2).timeout
	var n2 := ms.engine.mods.size()
	ui._redo_step()
	await get_tree().create_timer(0.2).timeout
	# --- a cable must lift off EITHER jack with a plain drag
	var ui2 := SynthUI.new()
	ui2.synth = ms
	add_child(ui2)
	await get_tree().create_timer(0.3).timeout
	var e8 := ms.engine
	var before8 := e8.cables.size()
	var c8: Dictionary = e8.cables[0] if before8 > 0 else {}
	if not c8.is_empty():
		var sm8 := int(c8["sm"])
		var so8 := int(c8["so"])
		# simulate grabbing the OUTPUT end: the same path the UI takes
		var found8 := {}
		for cc in e8.cables:
			if int(cc["sm"]) == sm8 and int(cc["so"]) == so8:
				found8 = cc
		var lifted := false
		if not found8.is_empty():
			e8.unpatch(int(found8["dm"]), true, int(found8["di"]))
			lifted = e8.cables.size() == before8 - 1
			e8.patch(sm8, so8, int(found8["dm"]), int(found8["di"]))
		print("SYNTHTEST lift cable from OUTPUT end: %s (cables %d -> %d -> %d)" % [
			"works" if lifted else "FAILED", before8, before8 - 1, e8.cables.size()])
	ui2.queue_free()
	await get_tree().create_timer(0.2).timeout
	# --- cable opacity: set it, save it, reload the config, still there
	Settings.cable_alpha = 0.34
	Settings.save_cfg()
	Settings.cable_alpha = 1.0
	var cfx := ConfigFile.new()
	if cfx.load(Settings.CFG_PATH) == OK:
		Settings.cable_alpha = clampf(float(cfx.get_value("opts", "cable_alpha", 1.0)),
			0.12, 1.0)
	print("SYNTHTEST cable opacity survives a settings reload: %.2f%s" % [
		Settings.cable_alpha,
		"   (saved)" if absf(Settings.cable_alpha - 0.34) < 0.01 else "   <-- LOST"])
	Settings.cable_alpha = 1.0
	Settings.save_cfg()
	print("SYNTHTEST undo: %d -> %d -> undo %d -> redo %d  (cables %d -> %d)%s" % [
		n0, n1, n2, ms.engine.mods.size(), c0, ms.engine.cables.size(),
		"   <-- UNDO BROKEN" if n2 != n0 else ""])
	ui.queue_free()
	await get_tree().create_timer(0.3).timeout
	if OS.get_environment("CTD_SHOT") != "":
		# a camera parked in front of the case, looking straight at it
		var cam := Camera3D.new()
		add_child(cam)
		var fwd: Vector3 = ms.global_transform.basis.z
		cam.global_position = ms.global_position + up * 1.15 + fwd * 3.1
		cam.look_at(ms.global_position + up * 1.0, up)
		cam.current = true
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("res://docs/shots/synth_case.png")
		cam.global_position = ms.global_position + up * 1.15 + fwd * 1.25
		cam.look_at(ms.global_position + up * 1.05, up)
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("res://docs/shots/synth_close.png")
		ms._vp.get_texture().get_image().save_png("res://docs/shots/synth_panelart.png")
		ms.use()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("res://docs/shots/synth_ui.png")
	await get_tree().create_timer(0.5).timeout
	print("SYNTHTEST done")


## CTD_TEST=31 -- the base-eater. A machine wired to a machine that then
## dies used to leave a freed reference in wires_out; collect_world hit
## `w is Machine.CoilNode` on it, errored, aborted, and the autosave
## wrote an EMPTY world over somebody's base. Never again.
func _savewipe_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var home = Universe.nearest(p.global_position)
	var up: Vector3 = (p.global_position - home.center).normalized()
	var made: Array = []
	for i in 3:
		var g := EMachines.Generator.new()
		add_child(g)
		g.set_meta("placed_id", "generator")
		g.global_transform = Transform3D(_basis_from_up(up),
			p.global_position + _basis_from_up(up).x * (3.0 + float(i) * 2.0))
		made.append(g)
	await get_tree().create_timer(0.4).timeout
	made[0].connect_wire(made[1], "power")
	made[1].connect_wire(made[2], "power")
	made[0].add_coil()
	made[2].connect_wire(made[0].coil_node, "power")
	await get_tree().create_timer(0.3).timeout
	var before := collect_world().size()
	print("SAVEWIPE before=%d wires0=%d" % [before, made[0].wires_out.size()])
	# kill the middle machine WITHOUT touching the wires pointing at it
	made[1].free()
	var after := collect_world()
	print("SAVEWIPE after_free entries=%d%s" % [after.size(),
		"   <-- WORLD WOULD HAVE BEEN WIPED" if after.size() < before - 2 else ""])
	# ...and the guard: an empty collect must never reach the file
	var keep := Save.world_objs.size()
	Save.set_world(after)
	Save.set_world([])
	print("SAVEWIPE guard: stored=%d (was %d, empty write refused=%s)" % [
		Save.world_objs.size(), keep, Save.world_objs.size() > 0])
	# and the freed link is gone from the graph entirely
	await get_tree().create_timer(0.3).timeout
	print("SAVEWIPE pruned wires0=%d wires2=%d" % [
		made[0].wires_out.size(), made[2].wires_out.size()])
	print("SAVEWIPE done")


## CTD_LOAD=<slot> boots a real save read-only; this says what actually
## came back and what state the session is in.
func _savedoctor_report() -> void:
	await get_tree().create_timer(6.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var counts := {}
	for grp in ["house", "machine", "chest", "rocket", "furn", "nterm", "bench"]:
		counts[grp] = get_tree().get_nodes_in_group(grp).size()
	var nb = Universe.nearest(p.global_position) if p != null else null
	print("SAVEDOCTOR groups=", counts)
	print("SAVEDOCTOR saved_world_entries=", Save.saved_world().size(),
		" unrestored=", _unrestored.size(), " world_load_ok=", _world_load_ok)
	if p != null:
		print("SAVEDOCTOR player pos=", p.global_position,
			" nearest=", nb.name, " alt=%.0f" % (p.global_position.distance_to(nb.center) - float(nb.radius)))
	print("SAVEDOCTOR pause_menu=", get_tree().get_first_node_in_group("pause_menu") != null,
		" paused=", get_tree().paused, " mouse=", Input.mouse_mode,
		" dead=", Game.dead, " mode=", Game.mode, " zone='", Game.zone, "'")
	# is anything sitting on top of the input stack?
	var blockers: Array = []
	for n in get_tree().root.get_children():
		if n is CanvasLayer and n.visible:
			blockers.append(n.name)
	print("SAVEDOCTOR layers=", blockers)
	var lay: Array = []
	for n in get_children():
		if n is CanvasLayer and n.visible:
			lay.append([n.name, n.layer])
	print("SAVEDOCTOR main_layers=", lay)
	# any modular synth in this save: is its voice actually reaching the
	# speakers, or is a cable on the wrong jack again?
	for sy in get_tree().get_nodes_in_group("modsynth"):
		if not (sy is ModSynth):
			continue
		var eng = sy.engine
		var peak := 0.0
		for i in 600:
			eng._block()
			peak = maxf(peak, eng.cast_level)
		var lines: Array = []
		for c in eng.cables:
			var dd := SynthMods.def(eng.mods[int(c["dm"])].id)
			lines.append("%s->%s.%s" % [eng.mods[int(c["sm"])].id,
				eng.mods[int(c["dm"])].id,
				str((dd["ins"] as Array)[int(c["di"])])])
		print("SAVEDOCTOR synth mods=%d cables=%d master peak=%.4f%s" % [
			eng.mods.size(), eng.cables.size(), peak,
			"   <-- SILENT" if peak < 0.001 else "   (making sound)"])
		print("SAVEDOCTOR patch: ", " | ".join(lines))
		# does the arpeggiator actually climb?
		for ai in eng.mods.size():
			if eng.mods[ai].id != "arp":
				continue
			var seen: Array = []
			for t in 40:
				for i in 40:
					eng._block()
				var cvv: float = eng.jack_volts(ai, false, 0)
				var gv: float = eng.jack_volts(ai, false, 1)
				var tag := "%.2fV%s" % [cvv, "*" if gv > 1.0 else ""]
				if seen.is_empty() or str(seen[seen.size() - 1]) != tag:
					seen.append(tag)
			var mm2 = eng.mods[ai]
			print("SAVEDOCTOR arp state: step=%.2f held=%.2f lastclk=%.2f lastgate=%.2f  RANGE=%.2f SPREAD=%.2f  clkIn=%.2f gateIn=%.2f cvIn=%.2f  order=%d" % [
				mm2.s[3], mm2.s[4], mm2.s[1], mm2.s[2],
				eng.knob_value(ai, 0), eng.knob_value(ai, 1),
				eng.jack_volts(ai, true, 2), eng.jack_volts(ai, true, 1),
				eng.jack_volts(ai, true, 0), int(mm2.sw[0])])
			print("SAVEDOCTOR arp CV walk: ", " ".join(seen),
				"   <-- STUCK" if seen.size() <= 1 else "   (climbing)")
	print("SAVEDOCTOR done")


## CTD_TEST=33 -- the production chain: ore -> dust -> ingot -> alloy,
## plus the geology tables and the miner tier gates.
func _factory_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position - Universe.nearest(p.global_position).center).normalized()
	print("FACTORY materials=", Mats.all().size(), " ores=", Mats.ores().size(),
		" alloys=", Mats.alloys().size())
	for oid in Mats.ores():
		print("FACTORY  %-16s tier %d · miner mk%d · best: %s" % [oid,
			int(Mats.def(oid)["tier"]), Mats.miner_tier(oid), Mats.best_worlds(oid)])
	# every alloy recipe must be buildable from things that exist
	for aid in Mats.alloys():
		var rd := Mats.def(aid)
		for k in (rd["inputs"] as Dictionary).keys():
			if not (Mats.has(str(k)) or Inventory.items.has(str(k))):
				print("FACTORY  BROKEN RECIPE ", aid, " wants unknown ", k)
	# --- the machines, wired to a creative generator
	var gen := EMachines.CreativeGen.new()
	add_child(gen)
	gen.set_meta("placed_id", "creativegen")
	gen.global_transform = Transform3D(_basis_from_up(up), p.global_position + up * 0.2)
	var cr := Factory.Crusher.new()
	add_child(cr)
	cr.set_meta("placed_id", "crusher")
	cr.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 4.0)
	var fu := EMachines.EFurnace.new()
	add_child(fu)
	fu.set_meta("placed_id", "efurnace")
	fu.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 8.0)
	var af := Factory.AlloyFurnace.new().setup(1)
	add_child(af)
	af.set_meta("placed_id", "alloyfurn")
	af.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 12.0)
	await get_tree().create_timer(0.5).timeout
	cr.buf = 300.0
	fu.buf = 200.0
	af.buf = 400.0
	# crush four copper rocks
	cr.in_slot = {"id": "raw_copper", "n": 4}
	for i in 14:
		cr.buf = 300.0
		await get_tree().create_timer(0.5).timeout
	print("FACTORY crusher: 4 raw_copper -> ", cr.out_slot,
		"   (expect 8 dust_copper)")
	# smelt the dust
	fu.in_slot = {"id": "dust_copper", "n": int(cr.out_slot.get("n", 0))}
	for i in 8:
		fu.buf = 200.0
		await get_tree().create_timer(0.4).timeout
	print("FACTORY e-furnace: dust -> ", fu.out_slot, "   (expect copper)")
	# pour bronze: 3 copper + 1 tin
	af.recipe = "bronze"
	af.store = {"copper": 9, "tin": 3}
	for i in 16:
		af.buf = 400.0
		await get_tree().create_timer(0.5).timeout
	print("FACTORY alloy furnace I: ", af.store, " -> ", af.out_slot,
		" (%d%%)" % int(af.progress() * 100.0))
	# tier gates
	var t3 := Factory.AlloyFurnace.new().setup(3)
	print("FACTORY tier1 recipes=", Mats.recipes_for_tier(1).size(),
		" tier2=", Mats.recipes_for_tier(2).size(),
		" tier3=", Mats.recipes_for_tier(3).size(),
		" (t3 can pour synthanium=", Mats.recipes_for_tier(3).has("synthanium"), ")")
	t3.free()
	var mk1 := AutoMiner.new()
	var mk3 := AutoMiner.new().setup(3)
	print("FACTORY miner mk1 can target ", mk1.tier, " -> ",
		Mats.ores_for_miner(1).size(), " ores · mk3 -> ",
		Mats.ores_for_miner(3).size(), " ores")
	mk1.free()
	mk3.free()
	# --- a real miner, digging a real new ore out of a real planet
	var mn := AutoMiner.new().setup(2)
	add_child(mn)
	mn.set_meta("placed_id", "autominer2")
	mn.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).z * 6.0)
	mn.target_ore = "raw_copper"
	await get_tree().create_timer(0.6).timeout
	for i in 16:
		mn.buf = 900.0
		await get_tree().create_timer(0.5).timeout
	print("FACTORY miner mk2 on ", str(Universe.nearest(mn.global_position).name),
		" richness ", Mats.richness(Universe.nearest(mn.global_position), "raw_copper"),
		" -> ", mn.out_slot)
	mn.target_ore = "raw_dudium"
	await get_tree().create_timer(1.0).timeout
	print("FACTORY miner mk2 told to dig dudium (needs mk3): ",
		"REFUSED (correct)" if Mats.miner_tier("raw_dudium") > mn.tier else "accepted (WRONG)")
	# every material has a name and an inventory row
	var missing: Array = []
	for mid in Mats.all().keys():
		if not Inventory.items.has(mid):
			missing.append(mid)
	print("FACTORY items without an inventory row: ", missing)
	print("FACTORY done")


## CTD_TEST=41 -- the airwaves: two racks fighting over one frequency,
## a radio tuning in live, and the Nexus quality bonus.
func _broadcast_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var nx = get_tree().get_first_node_in_group("nexus")
	print("BCAST nexus built=", nx != null, " at ", nx.global_position if nx else "-",
		" gravity there=%.4f" % Universe.gravity_at(NEXUS_POS).length())
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	# --- rack A, on the ground, asks for 98.0
	var a := ModSynth.new()
	add_child(a)
	a.set_meta("placed_id", "modsynth")
	a.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 5.0)
	# --- rack B, floating in the Nexus, ALSO asks for 98.0
	var b := ModSynth.new()
	add_child(b)
	b.set_meta("placed_id", "modsynth")
	b.global_position = NEXUS_POS + Vector3(4, 2, 0)
	await get_tree().create_timer(0.6).timeout
	for r in [a, b]:
		r.core_ultima = true
		r.core_uranium = true
		r.buf = 600.0
		var ci: int = r.engine.add_mod("cast", "dude")
		r.engine.mods[ci].name_tag = "RACK A" if r == a else "NEXUS ONE"
		r.engine.set_knob(ci, 0, SynthMods.knob_norm(
			SynthMods.def("cast")["knobs"][0], 98.0))
	for i in 6:
		a.buf = 600.0
		b.buf = 600.0
		await get_tree().create_timer(0.4).timeout
	print("BCAST A wants 98.0 -> on ", a.on_air_freq, " (", a.station_name, ")")
	print("BCAST B wants 98.0 -> on ", b.on_air_freq, " (", b.station_name, ")",
		"  FORWARDED" if absf(b.on_air_freq - 98.0) > 0.01 else "  <-- COLLISION")
	print("BCAST B at nexus=", b.at_nexus(), "  A at nexus=", a.at_nexus())
	print("BCAST live dial: ", Airwaves.live_stations().size(), " stations")
	# --- a radio tunes rack B in
	var rad := RadioTower.new()
	add_child(rad)
	rad.set_meta("placed_id", "radio")
	rad.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 10.0)
	await get_tree().create_timer(0.8).timeout
	rad.buf = 300.0
	rad.freq = b.on_air_freq
	for i in 10:
		rad.buf = 300.0
		a.buf = 600.0
		b.buf = 600.0
		await get_tree().create_timer(0.4).timeout
	var live_found := false
	for st in rad.stations:
		if str(st.get("type", "")) == "live":
			live_found = true
	print("BCAST radio sees live stations=", live_found,
		" tuned=", rad._cur_station, " live_src=", rad._live_src != null,
		" playing=", rad._live.playing if rad._live else false)
	print("BCAST rack B listeners=", b.listeners, " casts=", b.engine.cast_count(),
		" running=", b.engine.running)
	# a far-away radio should still hear the NEXUS station clearly
	rad.global_position = p.global_position + up * 3.0 + Vector3(3000, 0, 0)
	await get_tree().create_timer(1.2).timeout
	print("BCAST from 3km away: signal=%.2f (nexus station should stay strong)" % rad._last_sig)
	if OS.get_environment("CTD_SHOT") != "":
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = NEXUS_POS + Vector3(115, 26, 115)
		cam.look_at(NEXUS_POS + Vector3(0, 6, 0), Vector3.UP)
		cam.current = true
		cam.far = 8000.0
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("res://docs/shots/nexus_station.png")
		cam.global_position = NEXUS_POS + Vector3(22, 30, 22)
		cam.look_at(NEXUS_POS + Vector3(0, 26, 0), Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("res://docs/shots/nexus_hub.png")
		b._paint.queue_redraw()
		await get_tree().create_timer(0.5).timeout
		b._vp.get_texture().get_image().save_png("res://docs/shots/synth_cast.png")
	print("BCAST done")


## CTD_TEST=42 -- "my synth makes no noise": follow the signal from the
## shipped patch all the way to the speaker.
func _synthsound_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	var ms := ModSynth.new()
	add_child(ms)
	ms.set_meta("placed_id", "modsynth")
	ms.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 3.0)
	await get_tree().create_timer(0.8).timeout
	print("SOUND fresh rack: mods=", ms.engine.mods.size(),
		" cables=", ms.engine.cables.size(), " cores=", ms.ready_to_run())
	for i in ms.engine.mods.size():
		var mm = ms.engine.mods[i]
		print("SOUND   %d %-8s row %d hp %d" % [i, mm.id, mm.row, mm.hp])
	for c in ms.engine.cables:
		print("SOUND   cable %d:%d -> %d:%d" % [int(c["sm"]), int(c["so"]),
			int(c["dm"]), int(c["di"])])
	# offline: does the patch itself produce anything?
	for i in 40:
		ms.engine._block()
	print("SOUND offline master peak=%.4f" % ms.engine.cast_level)
	# now power it like a player would
	ms.core_ultima = true
	ms.core_uranium = true
	for i in 8:
		ms.buf = 600.0
		await get_tree().create_timer(0.35).timeout
	print("SOUND powered=", ms.powered, " running=", ms.engine.running,
		" ply.playing=", ms._ply.playing, " master=", ms.engine.master,
		" live peak=%.4f" % ms.engine.cast_level)
	var bi := AudioServer.get_bus_index("SynthFX")
	print("SOUND bus SynthFX idx=", bi, " volume_db=",
		AudioServer.get_bus_volume_db(bi) if bi >= 0 else "none",
		" muted=", AudioServer.is_bus_mute(bi) if bi >= 0 else "-",
		" master_db=", AudioServer.get_bus_volume_db(0),
		" settings.radio_vol=", Settings.radio_vol)
	print("SOUND player distance=%.1f (HEAR_RANGE %.0f)" % [
		p.global_position.distance_to(ms.global_position), ModSynth.HEAR_RANGE])
	# --- a patch saved BEFORE the CV-jack rework must still play
	var legacy := {"mods": [
		{"id": "vco", "b": "dude", "r": 0, "x": 0, "p": [0.5, 0.5, 0.0, 0.5], "s": [1], "t": []},
		{"id": "vcf", "b": "dude", "r": 0, "x": 12, "p": [0.55, 0.35, 0.75, 0.0], "s": [0], "t": []},
		{"id": "vca", "b": "dude", "r": 0, "x": 24, "p": [0.3, 1.0], "s": [0], "t": []},
		{"id": "out", "b": "dude", "r": 0, "x": 30, "p": [0.7], "s": [0], "t": []}],
		"cables": [[0, 0, 1, 0, 0], [1, 0, 2, 0, 1], [2, 0, 3, 0, 2]]}
	var old := ModSynth.new()
	old.set_meta("placed_id", "modsynth")
	old.set_meta("synth_data", {"patch": legacy, "u": true, "n": true})
	add_child(old)
	old.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 7.0)
	await get_tree().create_timer(0.6).timeout
	var routed: Array = []
	for c in old.engine.cables:
		var dd := SynthMods.def(old.engine.mods[int(c["dm"])].id)
		routed.append("%s -> %s.%s" % [old.engine.mods[int(c["sm"])].id,
			old.engine.mods[int(c["dm"])].id,
			str((dd["ins"] as Array)[int(c["di"])])])
	print("SOUND legacy patch rerouted: ", routed)
	for i in 40:
		old.engine._block()
	print("SOUND legacy patch peak=%.4f%s" % [old.engine.cast_level,
		"   <-- STILL SILENT" if old.engine.cast_level < 0.001 else "   (plays)"])
	# --- two free-running clocks must KEEP their offset for as long as
	# the rack runs. This is the "my two clocks drifted into sync" test.
	var e4 := SynthEngine.new()
	var ca: int = e4.add_mod("clock", "dude")
	var cb: int = e4.add_mod("clock", "dude")
	e4.add_mod("out", "dude")
	# same tempo, deliberately started apart
	e4.mods[cb].s[0] = 0.37
	var blocks_per_sec := int(SynthEngine.SR / float(SynthEngine.BLK))
	for sec in 6:
		for i in blocks_per_sec * 10:
			e4._block()
		var d1: float = e4.mods[ca].s[0]
		var d2: float = e4.mods[cb].s[0]
		var gap: float = fposmod(d2 - d1, 1.0)
		print("SOUND t=%3ds  phase A %.4f  B %.4f  gap %.4f  countA %d countB %d" % [
			(sec + 1) * 10, d1, d2, gap, int(e4.mods[ca].s[1]), int(e4.mods[cb].s[1])])
	# --- and an UNDO must not re-sync them either (this is what actually
	# happened: restoring a patch rebuilt every module with zeroed state)
	var before_a: float = e4.mods[ca].s[0]
	var before_b: float = e4.mods[cb].s[0]
	var snap := e4.to_dict()
	var e5 := SynthEngine.new()
	e5.from_dict(snap)
	var gap_before := fposmod(before_b - before_a, 1.0)
	var gap_after := fposmod(e5.mods[cb].s[0] - e5.mods[ca].s[0], 1.0)
	print("SOUND undo/reload: gap %.4f -> %.4f%s" % [gap_before, gap_after,
		"   <-- RESYNCED (BAD)" if absf(gap_after) < 0.0001 and gap_before > 0.0001
			else "   (offset survived)"])
	# --- and the PHASE knob offsets two identical clocks on purpose
	var e6 := SynthEngine.new()
	var pa2: int = e6.add_mod("clock", "dude")
	var pb2: int = e6.add_mod("clock", "dude")
	e6.set_knob(pb2, 3, 0.5)                  # half a step out
	var hi_a := 0
	var hi_b := 0
	var both := 0
	for i in 2000:
		e6._block()
		var va: float = e6.jack_volts(pa2, false, 0)
		var vb: float = e6.jack_volts(pb2, false, 0)
		if va > 1.0:
			hi_a += 1
		if vb > 1.0:
			hi_b += 1
		if va > 1.0 and vb > 1.0:
			both += 1
	print("SOUND PHASE knob: A high %d blocks, B high %d, overlapping %d (0 = perfectly interleaved)"
		% [hi_a, hi_b, both])
	# --- two clocks "both at 120" must really both be at 120
	var e7 := SynthEngine.new()
	var qa: int = e7.add_mod("clock", "dude")
	var qb: int = e7.add_mod("clock", "dude")
	# set them from two knob positions that are CLOSE but not identical --
	# exactly what happens when you turn two knobs by hand
	e7.set_knob(qa, 0, 0.357)
	e7.set_knob(qb, 0, 0.3585)
	e7.mods[qb].s[0] = 0.4
	print("SOUND knob snap: A %.2f BPM  B %.2f BPM" % [
		e7.knob_value(qa, 0), e7.knob_value(qb, 0)])
	var g0 := fposmod(e7.mods[qb].s[0] - e7.mods[qa].s[0], 1.0)
	for i in int(SynthEngine.SR / float(SynthEngine.BLK)) * 60:
		e7._block()
	var g1 := fposmod(e7.mods[qb].s[0] - e7.mods[qa].s[0], 1.0)
	print("SOUND hand-set clocks after 60s: gap %.4f -> %.4f%s" % [g0, g1,
		"   (held)" if absf(g0 - g1) < 0.01 else "   <-- DRIFTED"])
	# --- is a SLOW sine actually smooth? (an LFO into a pitch input is
	# the most exposed thing in the rack: any stepping is audible)
	var e11 := SynthEngine.new()
	var l11: int = e11.add_mod("lfo", "dude")
	var kn11: Array = SynthMods.def("lfo")["knobs"]
	e11.set_knob(l11, 0, SynthMods.knob_norm(kn11[0], 0.05))   # 0.05 Hz
	e11.set_knob(l11, 1, SynthMods.knob_norm(kn11[1], 1.0))    # +-1 V
	var prev := 0.0
	var maxstep := 0.0
	var uniq := {}
	for i in 3000:
		e11._block()
		var base := (1 + l11 * SynthEngine.MAXOUT + 3) * SynthEngine.BLK
		for j in SynthEngine.BLK:
			var v: float = e11._bus[base + j]
			if i > 2:
				maxstep = maxf(maxstep, absf(v - prev))
			prev = v
			uniq[snappedf(v, 0.0001)] = true
	print("SOUND slow sine (0.05 Hz, +-1 V): largest sample-to-sample step %.6f V, %d distinct levels%s" % [
		maxstep, uniq.size(),
		"   <-- STEPPY" if maxstep > 0.001 or uniq.size() < 200 else "   (smooth)"])
	# --- the analyser trace must be STILL: capture the same waveform
	# twice, a moment apart, and the two screens must line up
	var e13 := SynthEngine.new()
	var v13: int = e13.add_mod("vco", "dude")
	var an13: int = e13.add_mod("analyser", "dude")
	e13.patch(v13, 0, an13, 0)     # SAW: the hardest case, a vertical edge
	for i in 900:
		e13._block()
	var snap1: Array = []
	for i in 256:
		snap1.append(e13.mods[an13].d[i])
	for i in 400:
		e13._block()
	var drift := 0.0
	var mean_drift := 0.0
	for i in 256:
		var dd: float = absf(float(snap1[i]) - e13.mods[an13].d[i])
		drift = maxf(drift, dd)
		mean_drift += dd
	mean_drift /= 256.0
	var pitch13 := e13.jack_volts(an13, false, 0)
	var mm13 = e13.mods[an13]
	print("SOUND analyser: mean drift %.4f V (worst point %.2f V, the vertical edge)%s   pitch %.2f V = %.0f Hz   period %.1f samples (true %.1f)" % [
		mean_drift, drift, "   <-- MOVING" if mean_drift > 0.08 else "   (locked)",
		pitch13, 261.6256 * pow(2.0, pitch13), mm13.s[2], 22050.0 / 261.6256])
	# --- and the hard case: a source with no honest period at all. The
	# trigger cannot help here (every refresh finds a different crossing),
	# so this is purely the frame matcher holding the picture still.
	for src in ["mystery", "noise", "lfo"]:
		var e14 := SynthEngine.new()
		var s14: int = e14.add_mod(src, "mono" if src == "mystery" else "dude")
		var a14: int = e14.add_mod("analyser", "dude")
		e14.patch(s14, 0, a14, 0)
		for i in 900:
			e14._block()
		var snapA: Array = []
		for i in 256:
			snapA.append(e14.mods[a14].d[i])
		for i in 400:
			e14._block()
		var md14 := 0.0
		var amp14 := 0.0
		for i in 256:
			md14 += absf(float(snapA[i]) - e14.mods[a14].d[i])
			amp14 = maxf(amp14, absf(float(snapA[i])))
		md14 /= 256.0
		print("SOUND analyser [%s]: mean drift %.4f V of %.2f V amplitude%s" % [
			src, md14, amp14,
			"   <-- MOVING" if md14 > maxf(0.08, amp14 * 0.15) else "   (locked)"])
	print("SOUND done")


## CTD_TEST=43 -- the chemistry: the manual bench, its per-compound
## sequences, the lab families, and the book that lists them all.
func _chem_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	var hand := Mats.hand_makeable()
	print("CHEM makeable by hand: ", hand.size(), " -> ", hand)
	# every sequence must be unique to its compound
	var seqs := {}
	var dupes: Array = []
	for id in Mats.all().keys():
		var d: Dictionary = Mats.all()[id]
		if not d.has("inputs"):
			continue
		var key := " ".join(Mats.hand_sequence(str(id)))
		if seqs.has(key):
			dupes.append([str(id), seqs[key]])
		seqs[key] = str(id)
	print("CHEM sequences: ", seqs.size(), " distinct, collisions: ", dupes)
	for id in hand:
		print("CHEM   %-12s %s  <- %s" % [id, " -> ".join(Mats.hand_sequence(id)),
			str(Mats.def(id)["inputs"])])
	# --- the bench itself
	var bench := Factory.BenchLab.new()
	add_child(bench)
	bench.set_meta("placed_id", "benchlab")
	bench.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 3.0)
	await get_tree().create_timer(0.5).timeout
	Inventory.add_res("coal", 20)
	Inventory.add_res("plantfiber", 20)
	Inventory.add_res("raw_ice", 20)
	Inventory.add_res("sulfur", 20)
	bench.pour("coal", 2)
	print("CHEM bench target with 2 coal: ", bench.target(), "  note: ", bench.last_note)
	var seq: Array = Mats.hand_sequence(bench.target())
	# a deliberately wrong step first
	var wrong := "HEAT" if str(seq[0]) != "HEAT" else "STIR"
	bench.do_op(wrong)
	print("CHEM wrong step (%s): steps=%d  note: %s" % [wrong, bench.steps.size(),
		bench.last_note])
	for op in seq:
		bench.do_op(str(op))
	print("CHEM ran the real sequence %s -> out=%s  note: %s" % [str(seq),
		str(bench.out_slot), bench.last_note])
	# --- the labs
	var lab := Factory.Processor.new().setup("chem", 1)
	add_child(lab)
	lab.set_meta("placed_id", "chemlab")
	lab.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 7.0)
	var sep := Factory.Processor.new().setup("sep", 1)
	add_child(sep)
	sep.set_meta("placed_id", "separator")
	sep.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 11.0)
	await get_tree().create_timer(0.6).timeout
	lab.recipe = "lye"
	lab.store = {"plantfiber": 9, "water": 3}
	sep.recipe = "nitrogen"
	for i in 26:
		lab.buf = 500.0
		sep.buf = 500.0
		await get_tree().create_timer(0.4).timeout
	print("CHEM lab I lye: store=", lab.store, " out=", lab.out_slot)
	print("CHEM separator (air only): atmosphere=", sep._in_atmosphere(),
		" out=", sep.out_slot)
	print("CHEM tier gates: lab1=", Mats.recipes_for("chem", 1).size(),
		" lab2=", Mats.recipes_for("chem", 2).size(),
		" lab3=", Mats.recipes_for("chem", 3).size(),
		" cryo=", Mats.recipes_for("cryo", 3).size(),
		" electro=", Mats.recipes_for("electro", 2).size())
	# --- every recipe must reference things that exist
	var broken: Array = []
	for id in Mats.all().keys():
		var d2: Dictionary = Mats.all()[id]
		if not d2.has("inputs"):
			continue
		for k in (d2["inputs"] as Dictionary).keys():
			if not (Mats.has(str(k)) or Inventory.items.has(str(k))):
				broken.append([str(id), str(k)])
	print("CHEM broken recipe references: ", broken)
	# --- the book
	Game.chem_manual = true
	var man := ManualUI.new()
	add_child(man)
	await get_tree().create_timer(0.5).timeout
	print("CHEM manual rows: ", man._grid.get_child_count(),
		"  (every alloy and compound in the game)")
	man.queue_free()
	# --- is the whole tree actually REACHABLE from things you can dig,
	# grow or shoot? Anything that isn't is a dead recipe.
	var reach: Dictionary = {}
	for mid in Mats.all().keys():
		if not (Mats.all()[mid] as Dictionary).has("inputs"):
			reach[str(mid)] = true          # ore, dust, ingot: dug up
	for iid in Inventory.items.keys():
		reach[str(iid)] = true              # bought, looted or butchered
	for extra in ["coal", "sulfur", "plantfiber", "meat", "prism", "ultima",
			"uranium", "ingot", "irid"]:
		reach[extra] = true
	var moved := true
	while moved:
		moved = false
		for mid in Mats.all().keys():
			var md: Dictionary = Mats.all()[mid]
			if reach.has(str(mid)) or not md.has("inputs"):
				continue
			var ok9 := true
			for k in (md["inputs"] as Dictionary).keys():
				if not reach.has(str(k)):
					ok9 = false
					break
			if ok9:
				reach[str(mid)] = true
				moved = true
	var dead: Array = []
	for mid in Mats.all().keys():
		if not reach.has(str(mid)):
			dead.append(str(mid))
	print("CHEM unreachable materials: ", dead, "   (must be empty)")
	# --- the void siphon: refuses to run anywhere but beside TIN 618
	var vs := Factory.Processor.new().setup("void", 3)
	add_child(vs)
	vs.set_meta("placed_id", "voidsiphon")
	vs.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 15.0)
	await get_tree().create_timer(0.4).timeout
	print("CHEM siphon at home: recipe=", vs.recipe, " feed_ok=", vs._feed_ok())
	var bh = Universe.body_named("TIN 618")
	var harold = Universe.body_named("Harold")
	vs.global_position = harold.center + Vector3(0, harold.radius + 1.0, 0)
	print("CHEM siphon on Harold (%.0fm out, gate %.0fm): feed_ok=%s" % [
		harold.center.distance_to(bh.center), bh.radius * 9.0,
		str(vs._feed_ok())])
	for i in 8:
		vs.buf = vs.buf_cap
		vs.work(4.0)
	print("CHEM siphon out: ", vs.out_slot)
	# --- the growth vat: meat, saltpetre, plasma gel, one ultima
	var gv := Factory.Processor.new().setup("vat", 3)
	add_child(gv)
	gv.set_meta("placed_id", "growthvat")
	gv.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 19.0)
	await get_tree().create_timer(0.4).timeout
	gv.store = {"meat": 4, "potnitrate": 12, "plasmagel": 1, "ultima": 1}
	for i in 6:
		gv.buf = gv.buf_cap
		gv.work(4.0)
	print("CHEM vat recipe=", gv.recipe, " out=", gv.out_slot,
		" leftover=", gv.store)
	vs.queue_free()
	gv.queue_free()
	# --- every compound must be REAL GLASSWARE in the hand and in the
	# bag, never the grey fallback cube
	var thin: Array = []
	for mid in Mats.all().keys():
		var k9 := str((Mats.all()[mid] as Dictionary).get("kind", ""))
		if not (k9 in ["liquid", "gas", "solid"]):
			continue
		var hand_m: Node3D = p.model_for(str(mid))
		var icon_m: Node3D = IconLib.build_model(str(mid), get_tree())
		if hand_m.get_child_count() < 3 or icon_m.get_child_count() < 3:
			thin.append([str(mid), hand_m.get_child_count(),
				icon_m.get_child_count()])
		hand_m.queue_free()
		icon_m.queue_free()
	print("CHEM compounds with no real model: ", thin, "   (must be empty)")
	print("CHEM done")


## CTD_TEST=44 -- "I rejoined and my main voice is silent". Build a real
## patch, run it, save it, load it into a fresh engine, and compare what
## is still making sound module by module.
func _reload_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var e := SynthEngine.new()
	var clk: int = e.add_mod("clock", "dude")
	var seq: int = e.add_mod("seq8", "dude")
	var vco: int = e.add_mod("vco", "dude")
	var vcf: int = e.add_mod("vcf", "dude")
	var adsr: int = e.add_mod("adsr", "dude")
	var vca: int = e.add_mod("vca", "dude")
	var dseq: int = e.add_mod("dseq", "dude")
	var voice: int = e.add_mod("voice", "dude")
	var mix: int = e.add_mod("mix4", "dude")
	var out: int = e.add_mod("out", "dude")
	e.patch(clk, 0, seq, 0)          # clock -> sequencer
	e.patch(clk, 0, dseq, 0)         # clock -> trigger seq
	e.patch(seq, 0, vco, 0)          # pitch -> vco
	e.patch(seq, 1, adsr, 4)         # gate -> adsr GATE
	e.patch(vco, 0, vcf, 3)          # saw -> filter in
	e.patch(vcf, 0, vca, 1)          # lp -> vca in
	e.patch(adsr, 0, vca, 0)         # env -> vca cv
	e.patch(vca, 0, mix, 0)
	e.patch(dseq, 0, voice, 1)       # trigger -> dude voice gate
	e.patch(voice, 0, mix, 1)
	e.patch(mix, 0, out, 0)
	var names := {clk: "clock", seq: "seq8", vco: "vco", vcf: "vcf",
		adsr: "adsr", vca: "vca", dseq: "dseq", voice: "voice", mix: "mix4"}

	var measure := func(eng, label: String) -> void:
		var peaks := {}
		for k in names.keys():
			peaks[k] = 0.0
		var master := 0.0
		for i in 900:
			eng._block()
			for k in names.keys():
				var base := (1 + int(k) * SynthEngine.MAXOUT) * SynthEngine.BLK
				for j in SynthEngine.BLK:
					peaks[k] = maxf(peaks[k], absf(eng._bus[base + j]))
			master = maxf(master, eng.cast_level)
		var parts: Array = []
		for k in names.keys():
			parts.append("%s %.2f%s" % [str(names[k]), float(peaks[k]),
				"  <-- SILENT" if float(peaks[k]) < 0.01 else ""])
		print("RELOAD %s master=%.4f | %s" % [label, master, "  ".join(parts)])

	measure.call(e, "before save")
	var snap := e.to_dict()
	var e2 := SynthEngine.new()
	e2.from_dict(snap)
	measure.call(e2, "after load ")
	# and again from a patch saved with NO running state, like an old save
	var old_snap := snap.duplicate(true)
	for md in old_snap["mods"]:
		md.erase("z")
	var e3 := SynthEngine.new()
	e3.from_dict(old_snap)
	measure.call(e3, "old-format")
	# --- the real failure: a patch built AFTER the jack rework but saved
	# BEFORE the version stamp existed. It must NOT be remapped.
	var gap := snap.duplicate(true)
	gap.erase("v")
	for cbl in gap["cables"]:
		while (cbl as Array).size() > 5:
			(cbl as Array).remove_at((cbl as Array).size() - 1)
	var e4 := SynthEngine.new()
	e4.from_dict(gap)
	var vca_in := ""
	var vca_cv := ""
	for c2 in e4.cables:
		if int(c2["dm"]) == vca:
			var nmz: String = str((SynthMods.def("vca")["ins"] as Array)[int(c2["di"])])
			if nmz == "IN":
				vca_in = e4.mods[int(c2["sm"])].id
			elif nmz == "CV":
				vca_cv = e4.mods[int(c2["sm"])].id
	print("RELOAD unstamped-but-new patch: VCA IN <- %s   VCA CV <- %s%s" % [
		vca_in, vca_cv,
		"   <-- AUDIO LOST" if vca_in == "" else "   (audio kept)"])
	measure.call(e4, "gap-format")
	# --- an ADSR must NOT hold a note open with no gate, however it was
	# left when the patch was saved
	var e9 := SynthEngine.new()
	var a9: int = e9.add_mod("adsr", "dude")
	var o9: int = e9.add_mod("out", "dude")
	e9.patch(a9, 0, o9, 0)
	e9.mods[a9].s[0] = 3.0        # pretend it was saved mid-sustain
	e9.mods[a9].s[1] = 0.7
	for i in 200:
		e9._block()
	var envv := e9.jack_volts(a9, false, 0)
	print("RELOAD ungated ADSR (restored mid-sustain): ENV = %.3f V%s" % [envv,
		"   <-- STUCK OPEN" if envv > 0.05 else "   (closed, correct)"])
	# and with a gate held it must still sustain
	var e10 := SynthEngine.new()
	var c10: int = e10.add_mod("const", "dude")
	var a10: int = e10.add_mod("adsr", "dude")
	e10.patch(c10, 3, a10, 4)     # V 4 (5 V) -> GATE
	for i in 400:
		e10._block()
	print("RELOAD gated ADSR: ENV = %.3f V (should sit at sustain)" % [
		e10.jack_volts(a10, false, 0)])
	print("RELOAD done")


## CTD_TEST=45 -- builds the ambient patch, proves it makes sound, and
## writes it out as JSON so it can be dropped into a save.
func _ambient_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var e := SynthEngine.new()
	e.rows = 4
	e.row_hp = 168
	var id_of := {}
	var put := func(id: String, brand: String, row: int, hp: int, key: String) -> void:
		var i: int = e.add_mod(id, brand, row, hp)
		if i < 0:
			print("AMBIENT could not place ", id)
		id_of[key] = i
	var knob := func(key: String, kname: String, val: float) -> void:
		var mi: int = int(id_of[key])
		var kn: Array = SynthMods.def(e.mods[mi].id)["knobs"]
		for k in kn.size():
			if str(kn[k]["n"]) == kname:
				e.set_knob(mi, k, SynthMods.knob_norm(kn[k], val))
				return
		print("AMBIENT no knob ", kname, " on ", e.mods[mi].id)
	var swi := func(key: String, val: int) -> void:
		e.set_sw(int(id_of[key]), 0, val)
	var wire := func(a: String, oname: String, b: String, iname: String) -> void:
		var am: int = int(id_of[a])
		var bm: int = int(id_of[b])
		var oi: int = (SynthMods.def(e.mods[am].id)["outs"] as Array).find(oname)
		var ii: int = (SynthMods.def(e.mods[bm].id)["ins"] as Array).find(iname)
		if oi < 0 or ii < 0:
			print("AMBIENT bad wire ", a, ".", oname, " -> ", b, ".", iname)
			return
		if not e.patch(am, oi, bm, ii):
			print("AMBIENT patch refused ", a, " -> ", b)

	# ---- the bed: a just-intonation drone and a sub
	put.call("drone", "mono", 0, 0, "drone")
	put.call("vco", "dude", 0, 16, "sub")
	# ---- the pad: twenty partials, filtered, swelling
	put.call("harmonic", "icos", 0, 32, "pad")
	put.call("vcf", "dude", 0, 62, "padf")
	put.call("adsr", "dude", 0, 78, "env")
	put.call("vca", "dude", 0, 94, "padvca")
	# ---- the top voice: the watcher through the formant filter
	put.call("watcher", "mono", 1, 0, "top")
	put.call("eyefilter", "mono", 1, 19, "eye")
	# ---- motion
	put.call("clock", "dude", 1, 36, "clk")
	put.call("euclid", "icos", 1, 47, "euc")
	put.call("turing", "icos", 1, 58, "tur")
	put.call("quant", "dude", 1, 71, "qnt")
	put.call("lfo", "dude", 1, 82, "lfo1")
	put.call("lfo", "dude", 1, 95, "lfo2")
	put.call("chaos", "icos", 1, 108, "chaos")
	# ---- the space
	put.call("tape", "dude", 2, 0, "tape")
	put.call("slab", "mono", 2, 13, "slab")
	put.call("cosmic", "icos", 2, 28, "verb")
	put.call("dudemix", "dude", 2, 45, "desk")
	put.call("out", "dude", 2, 76, "out")

	# ---- wiring
	wire.call("clk", "/8", "euc", "CLK")
	wire.call("clk", "/4", "tur", "CLK")
	wire.call("euc", "TRIG", "env", "GATE")
	wire.call("tur", "CV", "qnt", "IN")
	wire.call("qnt", "CV", "pad", "V/OCT")
	wire.call("qnt", "CV", "top", "V/OCT")
	wire.call("lfo1", "SINE", "padf", "CUTOFF")
	wire.call("lfo2", "TRI", "drone", "SPREAD CV")
	wire.call("chaos", "X", "eye", "SWEEP")
	wire.call("chaos", "Y", "top", "CHISEL CV")
	wire.call("pad", "OUT", "padf", "IN")
	wire.call("padf", "LP", "padvca", "IN")
	wire.call("env", "ENV", "padvca", "CV")
	wire.call("top", "CARVED", "eye", "IN")
	wire.call("drone", "OUT", "desk", "IN 1")
	wire.call("sub", "SINE", "desk", "IN 2")
	wire.call("padvca", "OUT", "desk", "IN 3")
	wire.call("eye", "OUT", "tape", "IN")
	wire.call("tape", "OUT", "desk", "IN 4")
	wire.call("padvca", "OUT", "slab", "IN")
	wire.call("slab", "OUT", "desk", "IN 5")
	wire.call("desk", "MONO", "verb", "IN")
	wire.call("verb", "L", "out", "L / MONO")
	wire.call("verb", "R", "out", "R")

	# ---- the settings that make it ambient rather than a test tone
	knob.call("clk", "BPM", 40.0)
	knob.call("clk", "WIDTH", 0.6)
	knob.call("euc", "STEPS", 16.0)
	knob.call("euc", "FILL", 2.0)
	knob.call("tur", "LOOP", 0.88)
	knob.call("tur", "LENGTH", 8.0)
	knob.call("tur", "RANGE", 1.4)
	swi.call("qnt", 3)                       # pentatonic
	knob.call("env", "ATTACK", 3.6)
	knob.call("env", "DECAY", 3.0)
	knob.call("env", "SUSTAIN", 0.22)
	knob.call("env", "RELEASE", 9.0)
	knob.call("padf", "CUTOFF", 700.0)
	knob.call("padf", "RES", 0.22)
	e.set_sw(int(id_of["padf"]), 0, 1)       # 24 dB
	knob.call("pad", "OCT", -1.0)
	knob.call("pad", "TILT", 0.5)
	knob.call("pad", "LEVEL", 0.38)
	knob.call("drone", "TUNE", -2.0)
	knob.call("drone", "SPREAD", 0.3)
	knob.call("drone", "LEVEL", 0.2)
	e.set_sw(int(id_of["drone"]), 0, 1)      # 1:3:5:7
	knob.call("sub", "OCT", -2.0)
	knob.call("top", "TUNE", 1.0)
	knob.call("top", "CHISEL", 0.45)
	knob.call("top", "GRAIN", 0.12)
	knob.call("eye", "SWEEP", 520.0)
	knob.call("eye", "RES", 0.85)
	knob.call("eye", "MIX", 0.8)
	knob.call("lfo1", "RATE", 0.045)
	knob.call("lfo1", "AMP", 1.6)
	knob.call("lfo2", "RATE", 0.03)
	knob.call("lfo2", "AMP", 2.0)
	knob.call("chaos", "RATE", 0.6)
	knob.call("chaos", "SPREAD", 1.6)
	knob.call("tape", "TIME", 0.62)
	knob.call("tape", "REPEATS", 0.45)
	knob.call("tape", "MIX", 0.4)
	knob.call("tape", "WOW", 0.3)
	knob.call("slab", "TIME", 0.9)
	knob.call("slab", "REPEATS", 0.45)
	knob.call("slab", "MIX", 0.5)
	knob.call("verb", "SIZE", 0.6)
	knob.call("verb", "SHIMMER", 0.35)
	knob.call("verb", "MIX", 0.45)
	knob.call("verb", "DAMP", 0.45)
	knob.call("verb", "DRIFT", 0.45)
	knob.call("verb", "WIDTH", 1.0)
	e.set_sw(int(id_of["verb"]), 0, 2)       # EVENT HORIZON
	knob.call("out", "VOLUME", 0.62)
	# the pad's twenty partials: a soft, odd-weighted spectrum
	var pm = e.mods[int(id_of["pad"])]
	for i in 20:
		var amp := 1.0 / pow(float(i + 1), 1.35)
		if i % 2 == 1:
			amp *= 0.45
		pm.st[i] = clampf(amp, 0.0, 1.0)
	# the desk: bring the voices up, spread them wide
	for spec in [["LVL 1", 0.22], ["LVL 2", 0.12], ["LVL 3", 0.3], ["LVL 4", 0.2],
			["LVL 5", 0.16], ["LVL 6", 0.0], ["PAN 1", -0.35], ["PAN 2", 0.0],
			["PAN 3", 0.3], ["PAN 4", -0.7], ["PAN 5", 0.7], ["MASTER", 0.5]]:
		knob.call("desk", str(spec[0]), float(spec[1]))

	# ---- does it actually breathe?
	var peak := 0.0
	var rms := 0.0
	var n := 0
	var quiet := 0
	for i in int(SynthEngine.SR / float(SynthEngine.BLK)) * 30:
		e._block()
		var blockpeak := 0.0
		for v in e._mix:
			peak = maxf(peak, absf(v.x))
			rms += v.x * v.x
			n += 1
			blockpeak = maxf(blockpeak, absf(v.x))
		if blockpeak < 0.001:
			quiet += 1
	print("AMBIENT modules=%d cables=%d  peak=%.3f rms=%.4f  silent blocks=%d/%d" % [
		e.mods.size(), e.cables.size(), peak, sqrt(rms / float(n)), quiet,
		int(SynthEngine.SR / float(SynthEngine.BLK)) * 30])
	# --- the long run: track EVERY module minute by minute, so whatever
	# is quietly accumulating has nowhere to hide
	var bps := int(SynthEngine.SR / float(SynthEngine.BLK))
	for minute in 4:
		var mpeak := 0.0
		var mods_peak := {}
		for k in id_of.keys():
			mods_peak[k] = 0.0
		for i in bps * 60:
			e._block()
			for v in e._mix:
				mpeak = maxf(mpeak, absf(v.x))
			if i % 8 == 0:
				for k in id_of.keys():
					var mi2: int = int(id_of[k])
					var base := (1 + mi2 * SynthEngine.MAXOUT) * SynthEngine.BLK
					var mv: float = float(mods_peak[k])
					for j in range(0, SynthEngine.MAXOUT * SynthEngine.BLK, 7):
						mv = maxf(mv, absf(e._bus[base + j]))
					mods_peak[k] = mv
		var hot: Array = []
		for k in mods_peak.keys():
			if float(mods_peak[k]) > 6.0:
				hot.append("%s %.1fV" % [str(k), float(mods_peak[k])])
		hot.sort()
		print("AMBIENT minute %d: out peak %.3f   over 6V: %s" % [
			minute + 1, mpeak, ", ".join(hot) if hot.size() > 0 else "none"])
	var f := FileAccess.open("user://ambient_patch.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e.to_dict()))
		f.close()
		print("AMBIENT written to user://ambient_patch.json")
	print("AMBIENT done")


## CTD_TEST=46 -- every icon in the game, asked for at once. Godot allows
## 64 viewports per scenario; the pool must stay under that no matter how
## many materials and machines get added.
func _icons_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var ids: Array = []
	for k in Inventory.items.keys():
		ids.append(str(k))
	for k in Inventory.weapons.keys():
		if not ids.has(str(k)):
			ids.append(str(k))
	print("ICONS distinct item ids in the game: ", ids.size())
	var made := 0
	var refused := 0
	for id in ids:
		var t = IconLib.tex(str(id), get_tree())
		if t == null:
			refused += 1
		else:
			made += 1
		if made % 12 == 0:
			await get_tree().process_frame
	print("ICONS pool size after asking for all of them: ", IconLib._pool.size(),
		" (cap ", IconLib.MAX_ICONS, ")   served=", made, " deferred=", refused)
	print("ICONS %s" % ("pool stayed under the limit" if IconLib._pool.size() <= IconLib.MAX_ICONS
		else "POOL OVER THE CAP"))
	await get_tree().create_timer(5.0).timeout
	# after a few seconds the old ones are recyclable again
	var t2 = IconLib.tex("timmy", get_tree())
	print("ICONS after the keep-window, a fresh icon: ",
		"served" if t2 != null else "still deferred",
		"   pool=", IconLib._pool.size())
	print("ICONS done")


## CTD_TEST=47 -- a rack built to SHOW what GRAVITY WELL does: a voltage
## dropped into a well, orbiting, escaping, and being kicked back in.
## Written to user://gravity_patch.json, not into anybody's save.
func _gravity_demo() -> void:
	await get_tree().create_timer(1.0).timeout
	var e := SynthEngine.new()
	e.rows = 4
	e.row_hp = 168
	var idx := {}
	var put := func(id: String, brand: String, row: int, hp: int, key: String) -> void:
		var i: int = e.add_mod(id, brand, row, hp)
		idx[key] = i
		if i < 0:
			print("GRAV could not place ", id)
	var knob := func(key: String, kname: String, val: float) -> void:
		var mi: int = int(idx[key])
		var kn: Array = SynthMods.def(e.mods[mi].id)["knobs"]
		for k in kn.size():
			if str(kn[k]["n"]) == kname:
				e.set_knob(mi, k, SynthMods.knob_norm(kn[k], val))
				return
	var wire := func(a2: String, oname: String, b2: String, iname: String) -> void:
		var am: int = int(idx[a2])
		var bm: int = int(idx[b2])
		var oi: int = (SynthMods.def(e.mods[am].id)["outs"] as Array).find(oname)
		var ii: int = (SynthMods.def(e.mods[bm].id)["ins"] as Array).find(iname)
		if oi < 0 or ii < 0 or not e.patch(am, oi, bm, ii):
			print("GRAV bad wire ", a2, ".", oname, " -> ", b2, ".", iname)

	# the well itself, and the clock that keeps kicking it
	put.call("gravity", "mono", 0, 0, "well")
	put.call("clock", "dude", 0, 14, "clk")
	put.call("euclid", "icos", 0, 26, "euc")
	put.call("const", "dude", 0, 38, "cen")
	# ORBIT drives pitch, VELOCITY opens the filter, ESCAPE fires a drum
	put.call("quant", "dude", 0, 48, "qnt")
	put.call("vco", "dude", 0, 60, "vco")
	put.call("vcf", "dude", 0, 76, "vcf")
	put.call("adsr", "dude", 1, 0, "env")
	put.call("vca", "dude", 1, 16, "vca")
	put.call("drum", "icos", 1, 25, "drum")
	put.call("watcher", "mono", 1, 41, "sub")
	# and the panels that SHOW it happening
	put.call("scope", "dude", 2, 0, "scope")
	put.call("vector", "icos", 2, 15, "vec")
	put.call("spectrum", "dude", 2, 30, "spec")
	put.call("vu", "dude", 2, 51, "vu")
	put.call("waterfall", "icos", 2, 62, "fall")
	put.call("dudemix", "dude", 3, 0, "desk")
	put.call("reverb", "icos", 3, 31, "verb")
	put.call("out", "dude", 3, 47, "out")

	wire.call("clk", "/4", "euc", "CLK")
	wire.call("euc", "TRIG", "well", "KICK")        # every hit shoves the mass
	wire.call("cen", "V 2", "well", "TARGET")       # where the well pulls toward
	wire.call("well", "ORBIT", "qnt", "IN")         # the orbit IS the melody
	wire.call("qnt", "CV", "vco", "V/OCT")
	wire.call("well", "VELOCITY", "vcf", "CUTOFF")  # speed opens the filter
	wire.call("euc", "TRIG", "env", "GATE")
	wire.call("vco", "SAW", "vcf", "IN")
	wire.call("vcf", "LP", "vca", "IN")
	wire.call("env", "ENV", "vca", "CV")
	wire.call("well", "ESCAPE", "drum", "TRIG")     # it only drums when it escapes
	wire.call("well", "ORBIT", "sub", "V/OCT")
	wire.call("vca", "OUT", "desk", "IN 1")
	wire.call("drum", "OUT", "desk", "IN 2")
	wire.call("sub", "CARVED", "desk", "IN 3")
	wire.call("desk", "MONO", "verb", "IN")
	wire.call("verb", "L", "out", "L / MONO")
	wire.call("verb", "R", "out", "R")
	# every visualiser watching a different part of it
	wire.call("well", "ORBIT", "scope", "IN A")
	wire.call("well", "VELOCITY", "scope", "IN B")
	wire.call("well", "ORBIT", "vec", "X")
	wire.call("well", "VELOCITY", "vec", "Y")
	wire.call("desk", "MONO", "spec", "IN")
	wire.call("desk", "MONO", "fall", "IN")
	wire.call("vca", "OUT", "vu", "IN 1")
	wire.call("drum", "OUT", "vu", "IN 2")

	knob.call("clk", "BPM", 96.0)
	knob.call("euc", "STEPS", 16.0)
	knob.call("euc", "FILL", 4.0)
	knob.call("cen", "V 2", 0.0)
	knob.call("well", "CENTRE", 0.0)
	knob.call("well", "MASS", 0.9)
	knob.call("well", "DRAG", 0.16)      # barely damped: it really orbits
	knob.call("well", "PUSH", 1.5)       # and the kicks are big enough to escape
	knob.call("vcf", "CUTOFF", 400.0)
	knob.call("vcf", "RES", 0.35)
	knob.call("env", "ATTACK", 0.01)
	knob.call("env", "DECAY", 0.35)
	knob.call("env", "SUSTAIN", 0.2)
	knob.call("env", "RELEASE", 0.8)
	knob.call("vca", "GAIN", 0.0)
	knob.call("sub", "TUNE", -2.0)
	knob.call("sub", "CHISEL", 0.4)
	knob.call("verb", "MIX", 0.3)
	knob.call("out", "VOLUME", 0.7)
	for spec in [["LVL 1", 0.62], ["LVL 2", 0.5], ["LVL 3", 0.34], ["MASTER", 0.75]]:
		knob.call("desk", str(spec[0]), float(spec[1]))

	# --- does the well actually orbit, and does it ever escape?
	var lo := 99.0
	var hi := -99.0
	var escapes := 0
	var peak := 0.0
	var wi: int = int(idx["well"])
	for i in int(SynthEngine.SR / float(SynthEngine.BLK)) * 40:
		e._block()
		var orb := e.jack_volts(wi, false, 0)
		lo = minf(lo, orb)
		hi = maxf(hi, orb)
		if e.jack_volts(wi, false, 2) > 1.0:
			escapes += 1
		for v in e._mix:
			peak = maxf(peak, absf(v.x))
	print("GRAV %d modules, %d cables" % [e.mods.size(), e.cables.size()])
	print("GRAV orbit swung %.2f V to %.2f V, escaped %d times in 40s, out peak %.3f" % [
		lo, hi, escapes, peak])
	var f := FileAccess.open("user://gravity_patch.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e.to_dict()))
		f.close()
		print("GRAV written to user://gravity_patch.json (NOT into any save)")
	print("GRAV done")


## CTD_TEST=48 -- the ADVANCED TUTORIAL and the handbook it teaches from.
## Walks every step's text, checks every id it names actually exists
## (kit items, shop allowlist, circled recipes, goal resources), then
## opens the handbook with a spotlight and counts the circles drawn.
func _advtut_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var t := AdvancedTutorial.new()
	add_child(t)
	await get_tree().process_frame
	var bad: Array = []
	for id in AdvancedTutorial.STEPS:
		if str(t._obj_text(str(id))).strip_edges() == "":
			bad.append("obj:" + str(id))
		if str(t._why_text(str(id))).strip_edges() == "":
			bad.append("why:" + str(id))
	print("ADVTUT steps: ", AdvancedTutorial.STEPS.size(), "  missing text: ", bad)
	# every recipe the book is told to circle must be a real material
	var badcirc: Array = []
	for k in AdvancedTutorial.CIRCLES.keys():
		if not AdvancedTutorial.STEPS.has(str(k)):
			badcirc.append("step?" + str(k))
		for mid in AdvancedTutorial.CIRCLES[k]:
			if not Mats.has(str(mid)):
				badcirc.append(str(k) + "->" + str(mid))
	print("ADVTUT bad circle ids: ", badcirc)
	# every shop id the lesson unlocks must be a real catalog entry
	var shop_ids := {}
	for e in Inventory.catalog:
		shop_ids[str(e["id"])] = true
	var badshop: Array = []
	for id in AdvancedTutorial.STEPS:
		for sid in t._allow_for(str(id)):
			if str(sid) != "*" and not shop_ids.has(str(sid)):
				badshop.append(str(id) + "->" + str(sid))
	print("ADVTUT bad shop ids: ", badshop)
	# the starter kit and every goal resource must be real items
	var goals := ["dust_copper", "bronze", "water", "sulfuric", "silica",
		"carbon", "steel", "ingot", "irid", "coal", "raw_copper", "raw_tin",
		"raw_ice", "raw_sand", "sulfur", "plantfiber", "uranium", "ultima"]
	var baditem: Array = []
	for g in goals:
		if not Inventory.items.has(g):
			baditem.append(g)
	print("ADVTUT bad item ids: ", baditem)
	print("ADVTUT kit given: coins ", Inventory.coins,
		"  ingot ", Inventory.res_count("ingot"),
		"  raw_copper ", Inventory.res_count("raw_copper"))
	# the handbook: centred, gridded, and circling what it was told to.
	# the lesson is freed FIRST -- a live tutorial re-points the book at
	# its own current step every frame and would wipe the test's ring
	t.queue_free()
	await get_tree().process_frame
	ManualUI.point_at(["bronze", "sulfuric"])
	var man := ManualUI.new()
	add_child(man)
	await get_tree().create_timer(0.6).timeout
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var centred: bool = absf(man._root.offset_left + man._root.offset_right) < 1.0 \
		and absf(man._root.offset_top + man._root.offset_bottom) < 1.0
	var circles := 0
	for c in man._grid.get_children():
		for ch in c.get_children():
			if ch is ManualUI._Ring:
				circles += 1
	print("ADVTUT handbook: rows ", man._grid.get_child_count(),
		"  columns ", man._grid.columns, "  centred ", centred,
		"  circles ", circles, "  (viewport ", vp, ")")
	# headless runs at 64x64, so also check the column formula at the
	# resolutions a player actually sees
	for w in [1280.0, 1600.0, 1920.0, 2560.0]:
		var bw: float = minf(4.0 * ManualUI.CARD_W + 5.0 * ManualUI.GAP + 48.0, w - 80.0)
		var cols: int = clampi(int((bw - 48.0 + ManualUI.GAP)
			/ (ManualUI.CARD_W + ManualUI.GAP)), 1, 4)
		print("ADVTUT columns at ", int(w), "px wide: ", cols)
	# visual proof when there is a real window: the book as the player
	# sees it, circles and all
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://docs/shots/handbook.png")
		print("ADVTUT shot: docs/shots/handbook.png")
	man.queue_free()
	print("ADVTUT done")


## CTD_TEST=50 -- portraits of the four gas giants, one shot each, so the
## belts, the Great Red Spot and the polar hexagon can be looked at
## instead of guessed at.
func _gasgiant_shots() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 1200))
	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	cam.far = 420000.0
	add_child(cam)
	cam.current = true
	for nm in ["Jupiter", "Saturn", "Uranus", "Neptune", "Joule"]:
		var b = Universe.body_named(nm)
		if b == null:
			print("GASSHOT missing body: ", nm)
			continue
		# straight-on portrait: the spot sits near longitude +1.4, which
		# is the +Z face, so the camera stands off along +Z
		cam.global_position = b.center + Vector3(0, b.radius * 0.28, b.radius * 3.1)
		cam.look_at(b.center, Vector3.UP)
		# the planet LOD watches the PLAYER, not this camera: without
		# dragging the player along, every portrait is the flat far-away
		# stand-in material instead of the shader
		var pl9 = get_tree().get_first_node_in_group("player")
		if pl9 != null:
			pl9.global_position = cam.global_position
			pl9.visible = false
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(
			"res://docs/shots/gas_%s.png" % str(nm).to_lower())
		print("GASSHOT ", nm)
		# Saturn also gets a pole-on shot: the hexagon is only a hexagon
		# from above
		if nm == "Saturn":
			cam.global_position = b.center + Vector3(0, b.radius * 3.0, b.radius * 0.6)
			cam.look_at(b.center, Vector3(0, 0, -1))
			var pl8 = get_tree().get_first_node_in_group("player")
			if pl8 != null:
				pl8.global_position = cam.global_position
			await get_tree().create_timer(0.8).timeout
			get_viewport().get_texture().get_image().save_png(
				"res://docs/shots/gas_saturn_pole.png")
			print("GASSHOT Saturn pole")
	print("GASSHOT done")
	get_tree().quit()


## CTD_TEST=51 -- the ????? panel's six input jacks. Three sit on the left
## edge, three sit under the twisty knobs; the complaint was that every
## one of them patched into the TOP jack. This walks each jack's own
## screen position back through the UI's hit-test and the engine.
func _mystery_jack_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	var ms := ModSynth.new()
	add_child(ms)
	ms.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 6.0)
	await get_tree().create_timer(0.6).timeout
	var e := ms.engine
	e.clear_cables()
	var qi := e.add_mod("mystery", "mono", 0, 40)
	var vi := e.add_mod("lfo", "dude", 1, 0)
	print("MYSTERY mods: ?????=", qi, " lfo=", vi)
	var ui := SynthUI.new()
	ui.synth = ms
	add_child(ui)
	await get_tree().create_timer(0.4).timeout
	var lay := SynthMods.layout("mystery")
	print("MYSTERY jin layout: ", lay["jin"])
	# 1. does the hit-test give back the jack you actually clicked?
	var bad: Array = []
	for ji in (lay["jin"] as Array).size():
		var scr := ui._jack_screen(qi, true, ji)
		var h := ui._hit(scr)
		if h.is_empty() or str(h.get("kind", "")) != "jin" \
				or int(h.get("mi", -1)) != qi or int(h.get("i", -1)) != ji:
			bad.append("%d -> %s" % [ji, str(h)])
	print("MYSTERY hit-test mismatches: ", bad)
	# 2. does a patch into each jack STAY on that jack, through a save
	# and a reload?
	for ji in (lay["jin"] as Array).size():
		e.patch(vi, 0, qi, ji)
	var landed: Array = []
	for c in e.cables:
		if int(c["dm"]) == qi:
			landed.append(int(c["di"]))
	landed.sort()
	print("MYSTERY cables landed on jacks: ", landed, "  (want [0, 1, 2, 3, 4, 5])")
	var data := e.to_dict()
	var e2 := SynthEngine.new()
	e2.rows = e.rows
	e2.row_hp = e.row_hp
	e2.from_dict(data)
	var reloaded: Array = []
	for c2 in e2.cables:
		if int(c2["dm"]) == qi:
			reloaded.append(int(c2["di"]))
	reloaded.sort()
	print("MYSTERY after save+load: ", reloaded, "  (want the same six)")
	# 3. do the three knob jacks actually reach the DSP? move one and the
	# output has to change
	print("MYSTERY done")
	get_tree().quit()


## CTD_TEST=52 -- the COSMIC REVERB, measured instead of guessed at.
## A reverb glitches in three ways you can catch offline: it runs away
## (feedback >= 1), it tears (a sample-to-sample jump far bigger than the
## signal), or it never decays. This drives one impulse through it and
## watches the tail.
func _reverb_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var e := SynthEngine.new()
	e.rows = 3
	e.row_hp = 84
	e.clear_cables()
	var vi := e.add_mod("vco", "dude", 0, 0)
	var ri := e.add_mod("cosmic", "icos", 0, 20)
	var oi := e.add_mod("out", "dude", 0, 60)
	var din: Array = SynthMods.def("cosmic")["ins"]
	var dout: Array = SynthMods.def("cosmic")["outs"]
	print("REVERB jacks in=", din, " out=", dout)
	var audio_in: int = maxi(0, din.find("IN"))
	e.patch(vi, 3, ri, audio_in)   # SINE out: a saw would be all edges
	e.patch(ri, 0, oi, 0)
	# DRIFT at zero was the worst case: the read head landed on the write
	# head and the tank fed back on itself with no delay at all
	e.mods[ri].p[4] = 0.0        # DRIFT = 0
	e.mods[ri].p[2] = 1.0        # MIX = fully wet
	var worst_jump := 0.0
	var peak_drive := 0.0
	var prev := 0.0
	var nan_seen := false
	# 1. drive it for a while, then cut the input and watch the tail
	for blk in 220:
		if blk == 60:
			# cut the source: silence in, tail only
			e.unpatch(ri, true, audio_in)
		e._block()
		var base := (1 + ri * SynthEngine.MAXOUT + 0) * SynthEngine.BLK
		for k in SynthEngine.BLK:
			var v: float = e._bus[base + k]
			if is_nan(v) or is_inf(v):
				nan_seen = true
				v = 0.0
			if blk < 60:
				peak_drive = maxf(peak_drive, absf(v))
			elif blk > 64:   # let the cut transient pass first
				
				worst_jump = maxf(worst_jump, absf(v - prev))
			prev = v
	# 2. the tail, sampled at three points after the input stopped
	var tail: Array = []
	for seg in 3:
		var mx := 0.0
		for blk2 in 40:
			e._block()
			var base2 := (1 + ri * SynthEngine.MAXOUT + 0) * SynthEngine.BLK
			for k2 in SynthEngine.BLK:
				mx = maxf(mx, absf(e._bus[base2 + k2]))
		tail.append(mx)
	print("REVERB driven peak=%.3f  NaN/inf=%s" % [peak_drive, str(nan_seen)])
	print("REVERB tail peaks: %.4f -> %.4f -> %.4f  (must fall)" % [
		tail[0], tail[1], tail[2]])
	print("REVERB worst sample jump in tail=%.3f  (a tear is a jump the size of the signal)" % worst_jump)
	var decays: bool = tail[2] < tail[0] * 0.9 and tail[2] < 8.0
	print("REVERB decays=", decays, "  bounded=", peak_drive < 9.5, "  clean=", not nan_seen)
	# baseline: the plain reverb, measured exactly the same way, so the
	# cosmic number means something instead of floating on its own
	var e2 := SynthEngine.new()
	e2.rows = 3
	e2.row_hp = 84
	e2.clear_cables()
	var v2 := e2.add_mod("vco", "dude", 0, 0)
	var r2i := e2.add_mod("reverb", "dude", 0, 20)
	var o2 := e2.add_mod("out", "dude", 0, 60)
	var din2: Array = SynthMods.def("reverb")["ins"]
	var ain2: int = maxi(0, din2.find("IN"))
	e2.patch(v2, 3, r2i, ain2)
	e2.patch(r2i, 0, o2, 0)
	var jump2 := 0.0
	var prev2 := 0.0
	var tailmax := 0.0
	for blk3 in 220:
		if blk3 == 60:
			e2.unpatch(r2i, true, ain2)
		e2._block()
		var base3 := (1 + r2i * SynthEngine.MAXOUT + 0) * SynthEngine.BLK
		for k3 in SynthEngine.BLK:
			var v3: float = e2._bus[base3 + k3]
			if blk3 > 64:
				jump2 = maxf(jump2, absf(v3 - prev2))
				tailmax = maxf(tailmax, absf(v3))
			prev2 = v3
	print("REVERB baseline (plain reverb): worst jump=%.3f over tail peak %.3f" % [
		jump2, tailmax])
	print("REVERB done")
	get_tree().quit()


## CTD_TEST=53 -- every synth panel, checked for controls sitting on top
## of each other or hanging off the faceplate. "no UI in the wrong place"
## as a number, not an opinion.
func _panel_audit() -> void:
	await get_tree().create_timer(1.0).timeout
	var JR := SynthMods.JACK_R * 1.5
	var KR := SynthMods.KNOB_R
	var bad := 0
	for id in SynthMods.ids():
		var d := SynthMods.def(id)
		var l := SynthMods.layout(id)
		var w: float = float(l["w"])
		var items: Array = []
		for i in (l["knobs"] as Array).size():
			var k: Vector2 = l["knobs"][i]
			items.append(["knob %d" % i, Rect2(k - Vector2(KR, KR), Vector2(KR * 2.0, KR * 2.0))])
		for i in (l["jin"] as Array).size():
			var j: Vector2 = l["jin"][i]
			items.append(["jin %d" % i, Rect2(j - Vector2(JR, JR), Vector2(JR * 2.0, JR * 2.0))])
		for i in (l["jout"] as Array).size():
			var j2: Vector2 = l["jout"][i]
			items.append(["jout %d" % i, Rect2(j2 - Vector2(JR, JR), Vector2(JR * 2.0, JR * 2.0))])
		for i in (l["sw"] as Array).size():
			items.append(["sw %d" % i, l["sw"][i] as Rect2])
		if str(d["widget"]) != "":
			items.append(["widget", l["widget"] as Rect2])
		var hits: Array = []
		for a in items.size():
			var ra: Rect2 = items[a][1]
			if ra.position.x < -0.5 or ra.position.y < -0.5 \
					or ra.end.x > w + 0.5 or ra.end.y > SynthMods.PANEL_H + 0.5:
				hits.append("%s OFF PANEL" % str(items[a][0]))
			for b in range(a + 1, items.size()):
				var rb: Rect2 = items[b][1]
				if ra.intersects(rb):
					var ov := ra.intersection(rb)
					if ov.size.x > 0.6 and ov.size.y > 0.6:
						hits.append("%s x %s" % [str(items[a][0]), str(items[b][0])])
		if hits.size() > 0:
			bad += 1
			print("PANEL ", id, " (", str(d["name"]), "): ", hits)
	print("PANEL overlaps: ", bad, " / ", SynthMods.ids().size(), " panels")
	print("PANEL done")
	get_tree().quit()


## CTD_TEST=54 -- the arcade: a real cabinet placed in the world, every
## built-in cartridge run, and the editor driven through its tabs. This
## is the one that catches "the console works but the machine does not".
func _arcade_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	# --- the cabinet itself
	var cab := ArcadeMachine.new()
	add_child(cab)
	cab.set_meta("placed_id", "arcade")
	cab.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 3.0)
	await get_tree().create_timer(0.6).timeout
	print("ARCADE cabinet: parts=", cab.get_child_count(),
		" needs_power=", cab.buf_cap > 0.0, " shelf=", cab.shell.carts.size())
	# --- the attract loop plays the games to an empty room
	for i in 30:
		cab.shell.attract_step(0.08)
	var first_state := cab.shell.state
	for i in 220:
		cab.shell.attract_step(0.08)
	print("ARCADE attract: state=%d cart=%s frames_run=%d (0=boot 2=running)" % [
		cab.shell.state, str(cab.shell.carts[cab.shell.sel].name), cab.con.frame])
	cab.shell.take_over()
	print("ARCADE take over: attract=%s state=%d (1=shelf)" % [cab.shell.attract,
		cab.shell.state if cab.shell._next_state < 0 else cab.shell._next_state])
	# --- every cartridge on the shelf actually runs
	var slowest := 0.0
	for c in ArcadeCarts.shelf():
		var con := ArcadeConsole.new()
		con.sound = cab.sound
		con.boot(c)
		var t0 := Time.get_ticks_usec()
		var frames := 0
		for i in 180:
			con.btn_held[ArcadeConsole.B_RIGHT] = (i / 20) % 2 == 0
			con.btn_held[ArcadeConsole.B_A] = (i % 7) == 0
			con.btn_held[ArcadeConsole.B_B] = (i % 31) == 0
			con.btn_held[ArcadeConsole.B_DOWN] = (i % 5) == 0
			con.step(1.0 / 60.0)
			frames += 1
			if con.crashed:
				break
		var per := float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(frames, 1))
		slowest = maxf(slowest, per)
		print("ARCADE cart %-12s %s frames=%d %.2f ms/frame %s" % [c.name,
			"ok" if not con.crashed else "CRASHED", frames, per, con.crash_msg])
	print("ARCADE slowest cartridge: %.2f ms/frame (a frame is 16.7)" % slowest)
	# --- the shell and every editor tab draw without complaint
	var sh: ArcadeShell = cab.shell
	sh._enter(ArcadeShell.S_MENU)
	var t1 := Time.get_ticks_usec()
	for i in 30:
		sh.update(1.0 / 60.0)
		sh.draw()
	print("ARCADE menu draw: %.2f ms/frame" % [
		float(Time.get_ticks_usec() - t1) / 30000.0])
	sh.edit.open(sh.carts[0])
	sh.state = ArcadeShell.S_EDIT
	for tb in [ArcadeEdit.T_CODE, ArcadeEdit.T_SPRITE, ArcadeEdit.T_MAP]:
		sh.edit.tab = tb
		var t2 := Time.get_ticks_usec()
		for i in 30:
			sh.update(1.0 / 60.0)
			sh.draw()
		print("ARCADE editor %-6s %.2f ms/frame" % [ArcadeEdit.TABS[tb],
			float(Time.get_ticks_usec() - t2) / 30000.0])
	# --- typing into the code editor really edits the cartridge
	sh.edit.tab = ArcadeEdit.T_CODE
	sh.edit.cart = ArcadeCart.blank("TYPED")
	sh.edit.open(sh.edit.cart)
	sh.edit.cur_l = 0
	sh.edit.cur_c = 0
	con_type(sh, "x=1")
	print("ARCADE typing: first line is now '", str(sh.edit.lines[0]), "'")
	# --- a cart written in the editor boots
	sh.edit.lines = ["function _draw() cls(3) print('made here', 10, 10, 1) end"]
	sh.edit.commit()
	var con2 := ArcadeConsole.new()
	con2.boot(sh.edit.cart)
	con2.step(1.0 / 60.0)
	print("ARCADE edited cart runs: crashed=", con2.crashed, " ", con2.crash_msg)
	# --- the palette is what was promised
	# --- boards: a stock cabinet must actually be the lesser machine
	print("ARCADE stock: canvases=", cab.con.allowed_res(3), " voices=",
		cab.sound.voices(), " (BIG and FREE MOTION should fall back to 1)")
	cab.install_board("expand")
	print("ARCADE with expansion: canvas cap=", cab.con.allowed_res(3),
		" voices=", cab.sound.voices())
	cab.install_board("smooth")
	print("ARCADE with both: canvas cap=", cab.con.allowed_res(3), " -> ",
		ArcadeConsole.RES_MODES[cab.con.allowed_res(3)]["name"])
	# --- a cabinet remembers its boards and its own cartridges
	var made := cab.new_cart()
	made.name = "HOMEMADE"
	made.code = "function _draw() cls(9) end"
	var saved := cab.save_data()
	var cab2 := ArcadeMachine.new()
	cab2.load_data(saved)
	add_child(cab2)
	cab2.global_transform = cab.global_transform
	await get_tree().create_timer(0.4).timeout
	print("ARCADE reload: boards=", cab2.boards, " own carts=",
		cab2.user_carts.size(), " first=",
		str(cab2.user_carts[0].name) if cab2.user_carts.size() > 0 else "-")
	cab2.queue_free()
	print("ARCADE palette: ", Pixel.color_count(), " colours (2 + ",
		Pixel.HUES.size(), " hues x 3)")
	print("ARCADE fonts: ", PixelFont.NAMES)
	print("ARCADE resolutions: ", ArcadeConsole.RES_MODES.map(
		func(m): return "%s %dx%d" % [m["name"], m["w"], m["h"]]))
	# --- the tracker: notes go in, the song changes, slides exist
	sh.edit.tab = ArcadeEdit.T_SOUND
	sh.edit.sound = cab.sound
	sh.edit.song = ChipSound.demo_song()
	sh.edit.cart = ArcadeCart.blank("SONGTEST")
	sh.edit.trk_row = 0
	sh.edit.trk_ch = 0
	sh.edit.trk_col = 0
	sh.edit.trk_oct = 4
	cab.con.key_hits.clear()
	cab.con.key_hits[KEY_Z] = true      # C in the current octave
	sh.edit.update(1.0 / 60.0)
	cab.con.key_hits.clear()
	var typed_cell: Array = sh.edit.song.cell(0, 0, 0)
	print("ARCADE tracker note entry: cell=", typed_cell, " name=",
		ArcadeEdit.note_name(int(typed_cell[0])))
	# a glide, written into the effect column
	sh.edit.song.set_cell(0, 4, 0, [60 + 2, 1, 0, 3, 6])
	sh.edit.song.sig_num = 3
	sh.edit.song.rows_per_beat = 6
	sh.edit.commit()
	var round_trip := ChipSound.Song.from_dict(sh.edit.cart.song)
	print("ARCADE song round-trip: %d/%d at %d rows/beat, %d bpm, cell4=%s" % [
		round_trip.sig_num, round_trip.sig_den, round_trip.rows_per_beat,
		round_trip.bpm, str(round_trip.cell(0, 4, 0))])
	var t4 := Time.get_ticks_usec()
	for i in 30:
		sh.update(1.0 / 60.0)
		sh.draw()
	print("ARCADE editor SOUND  %.2f ms/frame" % [
		float(Time.get_ticks_usec() - t4) / 30000.0])
	# --- holding the machine must cost nothing: a held copy is a MODEL
	var t9 := Time.get_ticks_usec()
	var held_model: Node3D = p.model_for("arcade")
	var build_us := Time.get_ticks_usec() - t9
	add_child(held_model)
	await get_tree().process_frame
	var woke := false
	for n in held_model.get_children():
		for n2 in n.get_children():
			if n2 is ArcadeMachine:
				woke = (n2 as ArcadeMachine)._woken
	print("ARCADE held model: %.2f ms to build, %d parts, console built=%s" % [
		float(build_us) / 1000.0, _deep_parts(held_model), woke])
	held_model.queue_free()
	# --- the new items are objects, not grey cubes
	var thin_items: Array = []
	for iid in ["arcade", "discmaker", "floppy", "floppy_data", "arcboard",
			"arcsmooth"]:
		var hm: Node3D = p.model_for(iid)
		var im: Node3D = IconLib.build_model(iid, get_tree())
		# a machine builds its parts in _ready, so the model has to be in
		# the tree before it is worth counting -- which is exactly what
		# the icon viewport does with it
		add_child(hm)
		add_child(im)
		await get_tree().process_frame
		if _deep_parts(hm) < 4 or _deep_parts(im) < 4:
			thin_items.append([iid, _deep_parts(hm), _deep_parts(im)])
		hm.queue_free()
		im.queue_free()
	print("ARCADE items with no model: ", thin_items, "  (must be empty)")
	# --- FREE MOTION: the double density canvas actually runs
	var fm := ArcadeCart.blank("SMOOTH")
	fm.res_mode = 3
	fm.code = "W,H=res() function _draw() cls(0) circfill(W/2,H/2,40,29) end"
	var fmcon := ArcadeConsole.new()
	fmcon.caps = {"expand": true, "smooth": true}
	fmcon.boot(fm)
	fmcon.step(1.0 / 60.0)
	print("ARCADE free motion canvas: %dx%d crashed=%s" % [fmcon.game_w,
		fmcon.game_h, fmcon.crashed])
	# --- floppies survive a save and a load
	Inventory.floppy_data = [ArcadeDisc.make("song", "SAVED SONG",
		ChipSound.demo_song().to_dict())]
	Save.save_progress()
	var wrote: bool = str(Save._progress.get("floppies", [])).contains("SAVED SONG")
	Inventory.floppy_data = []
	Save.apply_progress()
	print("ARCADE floppy persistence: written=%s, restored=%d disc(s), first=%s" % [
		wrote, Inventory.floppy_data.size(),
		str(Inventory.floppy_data[0].get("name", "?"))
			if Inventory.floppy_data.size() > 0 else "-"])
	# --- the sound chip: does it make a noise, and can it keep up?
	var snd: ChipSound = cab.sound
	snd.set_song(ChipSound.demo_song())
	snd.play_music(0)
	var peak := 0.0
	var rms := 0.0
	var n := 0
	var t3 := Time.get_ticks_usec()
	for b in 200:                       # 200 blocks = 1.16 s of audio
		snd._block()
		for i in ChipSound.BLK:
			var v: Vector2 = snd._mix[i]
			peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
			rms += v.x * v.x + v.y * v.y
			n += 2
	var dsp_ms := float(Time.get_ticks_usec() - t3) / 1000.0
	var audio_ms := 200.0 * float(ChipSound.BLK) / ChipSound.SR * 1000.0
	print("ARCADE sound: peak=%.3f rms=%.3f  %.1f ms of cpu for %.0f ms of audio (%.1f%% of one core)" % [
		peak, sqrt(rms / float(n)), dsp_ms, audio_ms, dsp_ms / audio_ms * 100.0])
	# stereo: the mix must not be two copies of the same channel
	var diff := 0.0
	var widest := 0.0
	var cnt := 0
	for b in 400:
		snd._block()
		for i in ChipSound.BLK:
			var v2: Vector2 = snd._mix[i]
			var d2 := absf(v2.x - v2.y)
			diff += d2
			widest = maxf(widest, d2)
			cnt += 1
	print("ARCADE sound stereo: mean spread %.3f, widest %.3f  instruments=%d channels=%d" % [
		diff / float(cnt), widest, snd.song.insts.size(), ChipSound.CHANS])
	# every instrument in the bank must actually sound
	var silent: Array = []
	for ii in snd.song.insts.size():
		snd.stop_music()
		for c in snd.chans:
			c.stage = 0
		snd.play_note(0, 60.0, 1.0, ii)
		var e := 0.0
		for b in 40:
			snd._block()
			for i in ChipSound.BLK:
				e += absf(snd._mix[i].x) + absf(snd._mix[i].y)
		if e < 0.5:
			silent.append(str(snd.song.insts[ii].name))
	print("ARCADE silent instruments: ", silent, "   (must be empty)")
	# --- does the triangle filler actually fill?
	var tc := ArcadeCart.blank("TRI")
	tc.code = "function _draw() cls(0) tri(10,10,100,10,60,60,2) " \
		+ "tri(120,60,220,60,170,10,14) end"
	var tcon := ArcadeConsole.new()
	tcon.boot(tc)
	tcon.step(1.0 / 60.0)
	var filled_a := 0
	var filled_b := 0
	for y in 70:
		for x in 240:
			var v := tcon.main.pget(x, y)
			if v == 2:
				filled_a += 1
			elif v == 14:
				filled_b += 1
	print("ARCADE trifill: point-down=%d px, point-up=%d px (both should be ~2000)" % [
		filled_a, filled_b])
	# --- how fast can a cartridge actually paint?
	var fc := ArcadeCart.blank("FILL")
	fc.code = "W,H=res() function _draw() for i=1,10 do rectfill(0,0,W,H,i) end end"
	var fcon := ArcadeConsole.new()
	fcon.boot(fc)
	var tf := Time.get_ticks_usec()
	for i in 20:
		fcon.step(1.0 / 60.0)
	var us_per_screen := float(Time.get_ticks_usec() - tf) / 200.0
	print("ARCADE fill rate: %.0f us per full screen (%d px), %.1f ms for ten" % [
		us_per_screen, fcon.game_w * fcon.game_h, us_per_screen * 10.0 / 1000.0])
	var tc2 := ArcadeCart.blank("TRIS")
	tc2.code = "W,H=res() function _draw() for i=1,40 do tri(0,0,W,0,W/2,H,i) end end"
	var tcon2 := ArcadeConsole.new()
	tcon2.boot(tc2)
	var tt := Time.get_ticks_usec()
	for i in 20:
		tcon2.step(1.0 / 60.0)
	print("ARCADE triangle rate: %.0f us per half-screen triangle" % [
		float(Time.get_ticks_usec() - tt) / 800.0])
	print("ARCADE lua speed: %.2f ms per 10k loop iterations" % [_lua_bench()])
	# --- floppies: one format, four kinds, and one conversion that is
	# deliberately impossible
	Inventory.floppy_data = []
	Inventory.add_res("floppy", 5)
	var romcart: ArcadeCart = ArcadeCarts.shelf()[1]
	print("ARCADE disc write cart: ", ArcadeDisc.write(ArcadeDisc.make(
		"cart", romcart.name, romcart.to_dict())))
	print("ARCADE disc write script: ", ArcadeDisc.write(ArcadeDisc.make(
		"script", "SORTER", {"code": "function route(x) return x*2 end\nport = route(3)"})))
	var back := ArcadeCart.from_dict(ArcadeDisc.take(0))
	print("ARCADE disc read cart: name=", back.name, " code=", back.code.length(),
		" chars  sheet=", back.sheet.size(), " bytes")
	# the same script runs on a computer, because it is the same Lua
	var res := LuaVM.run_env(str(ArcadeDisc.take(1).get("code", "")),
		{"port": 0}, {})
	print("ARCADE computer runs disc script: err=", res.get("err", "none"),
		" port=", LuaVM.tostr(res.get("env", {}).get("port", 0)))
	# a modular synth patch, rendered into an arcade instrument
	var ms := ModSynth.new()
	add_child(ms)
	ms.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 7.0)
	await get_tree().create_timer(0.8).timeout
	var patch_disc := ArcadeDisc.make("patch", "RACK", ms.patch_data())
	var inst := ArcadeDisc.patch_to_inst(patch_disc)
	print("ARCADE patch -> instrument: %s, %d samples rendered (%.2fs)" % [
		inst.name, inst.sample.size(), float(inst.sample.size()) / ChipSound.SR])
	print("ARCADE what reads what: patch->modsynth=%s patch->arcade=%s song->modsynth=%s song->arcade=%s script->computer=%s" % [
		ArcadeDisc.can_read(patch_disc, "modsynth"),
		ArcadeDisc.can_read(patch_disc, "arcade"),
		ArcadeDisc.can_read({"kind": "song"}, "modsynth"),
		ArcadeDisc.can_read({"kind": "song"}, "arcade"),
		ArcadeDisc.can_read({"kind": "script"}, "computer")])
	ms.queue_free()
	cab.queue_free()
	print("ARCADE done")


## Feed characters to the editor the way a keyboard would.
func con_type(sh, text: String) -> void:
	for i in text.length():
		sh.con.text_typed = text[i]
		sh.edit.update(1.0 / 60.0)
	sh.con.text_typed = ""


## CTD_TEST=55 -- pictures of the arcade, because a console is a thing
## you look at. Saves the boot screen, the shelf, two games, both
## editors and the cabinet itself into docs/shots.
func _arcade_shots() -> void:
	await get_tree().create_timer(2.5).timeout
	var p = get_tree().get_first_node_in_group("player")
	var up: Vector3 = (p.global_position
		- Universe.nearest(p.global_position).center).normalized()
	var cab := ArcadeMachine.new()
	add_child(cab)
	cab.set_meta("placed_id", "arcade")
	cab.global_transform = Transform3D(_basis_from_up(up),
		p.global_position + _basis_from_up(up).x * 4.0)
	cab.install_board("expand")
	await get_tree().create_timer(1.0).timeout
	var dir := "res://docs/shots/"
	# let the attract loop get into a game before the photograph
	for i in 60:
		cab.shell.attract_step(0.25)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var fwd: Vector3 = cab.global_transform.basis.z
	cam.global_position = cab.global_position + fwd * 2.6 + up * 1.5
	cam.look_at(cab.global_position + up * 1.4, up)
	for i in 40:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	await _shot(dir + "arcade_cabinet.png")
	# --- inside: the console UI itself
	var ui := ArcadeUI.new()
	ui.con = cab.con
	ui.shell = cab.shell
	ui.machine = cab
	get_tree().current_scene.add_child(ui)
	cab._open = true
	cab.shell._enter(ArcadeShell.S_BOOT)
	cab.shell.t = 2.6
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "arcade_boot.png")
	cab.shell._enter(ArcadeShell.S_MENU)
	await get_tree().create_timer(0.6).timeout
	await _shot(dir + "arcade_shelf.png")
	# --- a game, mid-play
	cab.shell.sel = 0
	cab.shell._boot_selected()
	cab.shell._enter(ArcadeShell.S_RUN)
	for i in 200:
		cab.con.btn_held[ArcadeConsole.B_A] = (i % 6) == 0
		cab.con.btn_held[ArcadeConsole.B_LEFT] = (i / 30) % 2 == 0
		await get_tree().process_frame
	await _shot(dir + "arcade_voidwing.png")
	cab.shell.sel = 2
	cab.shell._boot_selected()
	cab.shell._enter(ArcadeShell.S_RUN)
	for i in 240:
		cab.con.btn_held[ArcadeConsole.B_RIGHT] = true
		cab.con.btn_held[ArcadeConsole.B_A] = (i % 40) < 6
		await get_tree().process_frame
	await _shot(dir + "arcade_dudedash.png")
	cab.shell.sel = 3
	cab.shell._boot_selected()
	cab.shell._enter(ArcadeShell.S_RUN)
	for i in 260:
		cab.con.btn_held[ArcadeConsole.B_DOWN] = (i % 9) < 4
		cab.con.btn_held[ArcadeConsole.B_A] = (i % 23) == 0
		await get_tree().process_frame
	await _shot(dir + "arcade_blockparty.png")
	cab.shell.sel = 1
	cab.shell._boot_selected()
	cab.shell._enter(ArcadeShell.S_RUN)
	for i in 220:
		cab.con.btn_held[ArcadeConsole.B_LEFT] = (i / 40) % 2 == 0
		cab.con.btn_held[ArcadeConsole.B_RIGHT] = (i / 40) % 2 == 1
		await get_tree().process_frame
	await _shot(dir + "arcade_soulboard.png")
	cab.shell.sel = 2
	cab.shell._boot_selected()
	cab.shell._enter(ArcadeShell.S_RUN)
	for i in 300:
		cab.con.btn_held[ArcadeConsole.B_A] = true
		cab.con.btn_held[ArcadeConsole.B_RIGHT] = (i % 60) < 8
		cab.con.btn_held[ArcadeConsole.B_LEFT] = (i % 60) >= 30 and (i % 60) < 38
		await get_tree().process_frame
	await _shot(dir + "arcade_neondrift.png")
	# --- the workshop
	cab.shell.edit.open(cab.shell.carts[0])
	cab.shell.state = ArcadeShell.S_EDIT
	cab.shell.edit.tab = ArcadeEdit.T_CODE
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "arcade_code.png")
	cab.shell.edit.tab = ArcadeEdit.T_SPRITE
	# put something in the sprite editor worth photographing
	for y in 16:
		for x in 16:
			var v := 0
			if (x - 8) * (x - 8) + (y - 8) * (y - 8) < 40:
				v = 2 + ((x + y) % 8) * 3
			cab.shell.carts[0].sheet[y * ArcadeCart.SHEET_W + x] = v
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "arcade_sprite.png")
	cab.shell.edit.tab = ArcadeEdit.T_SOUND
	cab.shell.edit.song = ChipSound.demo_song()
	cab.sound.set_song(cab.shell.edit.song)
	cab.sound.play_music(0)
	await get_tree().create_timer(1.4).timeout
	await _shot(dir + "arcade_tracker.png")
	cab.shell.edit.trk_panel = 1
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "arcade_instrument.png")
	cab.shell.state = ArcadeShell.S_EDIT
	cab.shell.edit.tab = ArcadeEdit.T_INFO
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "arcade_cart.png")
	cab.shell.edit.tab = ArcadeEdit.T_MAP
	# put a few tiles down so the map tab has something on it
	for mx in 22:
		for my in range(9, 14):
			cab.shell.carts[0].mset(mx, my, 7 if my > 9 else 6)
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "arcade_map.png")
	cab.shell.state = ArcadeShell.S_DISC
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "arcade_disc.png")
	print("ARCADE SHOTS done")

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)


## How much Lua a cartridge can afford in a frame, measured rather than
## guessed. Ten thousand loop iterations of arithmetic.
func _lua_bench() -> float:
	var vm := LuaVM.new()
	vm.open_libs()
	vm.run("function work(n) local s=0 for i=1,n do s=s+i*2 end return s end")
	var t0 := Time.get_ticks_usec()
	vm.call_global("work", [10000.0])
	return float(Time.get_ticks_usec() - t0) / 1000.0


## Count the meshes in a model tree, however deep they are nested.
func _deep_parts(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			c += 1
		c += _deep_parts(ch)
	return c
