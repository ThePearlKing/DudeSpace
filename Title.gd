extends Node
## Main scene. Title -> pick one of 3 save slots -> character creator ->
## launch the game world (Main.tscn).

var _title_ui: CanvasLayer
var _options: CanvasLayer
var _creator: CharacterCreator

var _bg_pivot: Node3D
var _orbits: Array = []
var _crab: ClawdeCrab
var _invader: Invader

func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	# back from a tutorial session: throw its world away
	Game.tutorial_session = false
	Game.tutorial_allow = ["*"]
	Save.ephemeral = false
	Universe.restore_full_universe()
	Net.leave()   # back at the title = session over
	_build_background()
	_build_main_menu()
	add_child(HumanFaceEditor.new())   # F9 face editor works here too
	# headless LAN test rig: CTD_NET=join connects to localhost as a guest
	if OS.get_environment("CTD_NET") == "join":
		Net.guest_name = "Tester"
		print("NETTEST join: connecting")
		_do_join("127.0.0.1", 25999)

## First screen: exactly four choices.
func _build_main_menu() -> void:
	_title_ui = CanvasLayer.new()
	add_child(_title_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_ui.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-220, -220)
	col.custom_minimum_size = Vector2(440, 440)
	col.add_theme_constant_override("separation", 14)
	_title_ui.add_child(col)

	var title := Label.new()
	title.text = "DUDESPACE"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "destroy everything. across a universe."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	col.add_child(sub)

	var entries: Array = [
		["SINGLEPLAYER", func() -> void:
			_title_ui.queue_free()
			_build_title()],
		["MULTIPLAYER", _open_multiplayer],
		["TUTORIAL", _start_tutorial],
		["OPTIONS", _open_options],
		["QUIT", func() -> void: get_tree().quit()],
	]
	for e in entries:
		var b := Button.new()
		b.text = e[0]
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(e[1])
		col.add_child(b)

	# rolling tip: rerolls every title visit, or click it for another
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(440, 0)
	_tip.add_theme_font_size_override("font_size", 14)
	_tip.modulate = Color(1, 1, 1, 0.55)
	_tip.mouse_filter = Control.MOUSE_FILTER_STOP
	_tip.mouse_entered.connect(func() -> void: _tip.modulate = Color("#ffe066"))
	_tip.mouse_exited.connect(func() -> void: _tip.modulate = Color(1, 1, 1, 0.55))
	_tip.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_roll_tip())
	col.add_child(_tip)
	_roll_tip()

## LAN server browser: hosts on the network announce themselves and show
## up here by name, Minecraft style. Manual IP entry as a fallback.
var _mp_ui: CanvasLayer
var _mp_list: VBoxContainer
var _mp_found: Dictionary = {}   # "ip:port" -> true

func _open_multiplayer() -> void:
	if _title_ui:
		_title_ui.queue_free()
	_mp_ui = CanvasLayer.new()
	add_child(_mp_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mp_ui.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-300, -260)
	col.custom_minimum_size = Vector2(600, 520)
	col.add_theme_constant_override("separation", 12)
	_mp_ui.add_child(col)

	var title := Label.new()
	title.text = "LAN GAMES"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "worlds opened to LAN on your network appear here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 280)
	col.add_child(scroll)
	_mp_list = VBoxContainer.new()
	_mp_list.add_theme_constant_override("separation", 8)
	_mp_list.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(_mp_list)

	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	col.add_child(nrow)
	var nlbl := Label.new()
	nlbl.text = "Your name"
	nrow.add_child(nlbl)
	var nedit := LineEdit.new()
	nedit.text = Settings.username if Settings.username != "" else "Dude"
	nedit.max_length = 24
	nedit.custom_minimum_size = Vector2(300, 44)
	nedit.text_changed.connect(func(t: String) -> void:
		Settings.username = t.strip_edges()
		Settings.save_cfg())
	nrow.add_child(nedit)
	if Settings.username == "":
		Settings.username = nedit.text
		Settings.save_cfg()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var ipedit := LineEdit.new()
	ipedit.placeholder_text = "or type an address: 192.168.1.50:24545"
	ipedit.custom_minimum_size = Vector2(430, 44)
	row.add_child(ipedit)
	var joinb := Button.new()
	joinb.text = "Join"
	joinb.custom_minimum_size = Vector2(140, 44)
	joinb.pressed.connect(func() -> void:
		var parts := ipedit.text.strip_edges().split(":")
		if parts.size() >= 1 and parts[0] != "":
			_join_lan(parts[0], int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else Net.DEFAULT_PORT))
	row.add_child(joinb)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(func() -> void:
		Net.stop_discovery()
		Net.server_found.disconnect(_on_server_found)
		_mp_ui.queue_free()
		_mp_ui = null
		_mp_found.clear()
		_build_main_menu())
	col.add_child(back)

	_mp_found.clear()
	Net.server_found.connect(_on_server_found)
	Net.start_discovery()

func _mp_note(text: String, col: Color) -> void:
	print("MP: ", text)
	if _mp_list and is_instance_valid(_mp_list):
		var l := Label.new()
		l.text = text
		l.modulate = col
		_mp_list.add_child(l)

func _on_server_found(ip: String, info: Dictionary) -> void:
	if _mp_list == null or not is_instance_valid(_mp_list):
		return
	var port := int(info.get("port", Net.DEFAULT_PORT))
	var key := "%s:%d" % [ip, port]
	if _mp_found.has(key):
		return
	_mp_found[key] = true
	var b := Button.new()
	b.text = "%s   ·   %s   ·   %d online" % [str(info.get("world", "world")), key, int(info.get("players", 1))]
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(func() -> void: _join_lan(ip, port))
	_mp_list.add_child(b)

## Joining = dress up first (the server sees your look), THEN connect.
func _join_lan(ip: String, port: int) -> void:
	if _mp_ui:
		_mp_ui.visible = false
	var cc := CharacterCreator.new()
	cc.guest_mode = true
	add_child(cc)
	cc.back.connect(func() -> void:
		cc.queue_free()
		if _mp_ui:
			_mp_ui.visible = true)
	cc.started.connect(func() -> void:
		cc.queue_free()
		if _mp_ui:
			_mp_ui.visible = true
		_do_join(ip, port))

## Enter the HOST's world. It arrives as a snapshot; your bags come from
## the server's memory of your name.
func _do_join(ip: String, port: int) -> void:
	var err := Net.join(ip, port)
	if err != "":
		_mp_note(err, Color("#ff8866"))
		return
	_mp_note("connecting to %s:%d…" % [ip, port], Color("#ffd166"))
	Net.stop_discovery()
	Net.world_snapshot_received.connect(func(snap: Dictionary, blob: Dictionary) -> void:
		Save.begin_guest_session(snap, blob)
		get_tree().change_scene_to_file("res://Main.tscn"),
		CONNECT_ONE_SHOT)

## Things the game never tells you but should. Dry, true, useful.
const TIPS := [
	"tip: your hotbar AND jetpack drop where you die. go back for them.",
	"One in-game day lasts 10 real minutes. Press K to see the calendar.",
	"tip: stuck in the black hole? Reset Character in the pause menu gets you out. costs half your coins.",
	"tip: the black hole eats dropped items too. don't die near it.",
	"tip: banked coins survive death. carried coins don't. the ATM is your friend.",
	"tip: Q drops the selected item. clicking outside an inventory drops the held stack.",
	"tip: mine veins grow back. no planet ever runs dry.",
	"tip: stick a waypoint ON a rocket and it tracks it in flight.",
	"tip: 1-9 warps time while coasting in a rocket. 0 is 10x. burning cancels it.",
	"tip: the electric seller pays 1.25x what the manual sell station does.",
	"tip: armor caps at 60%. cheap pieces can hit the cap together.",
	"tip: wire a computer output to a Light Box: instant status lamp.",
	"tip: hold TAB in multiplayer to see everyone's distance from you.",
	"tip: gas giants have no ground. do not go looking for the ground.",
	"tip: K opens the calendar. UFO trader Saturdays are predictable.",
	"tip: prism shards only grow under shader light.",
	"tip: a bioreactor accepts a permadeath apple. 500 EU. coward.",
	"tip: the sell station buys meat, salad, even coal. everything has a price.",
	"tip: humans may seem smart. they are dumb and inefficient.",
	"tip: F5 changes camera. G strikes a pose. combine responsibly.",
	"tip: dying on a sun vaporizes your items. there is no going back for them.",
	"tip: a control coil on a power extender is a valve. valves in a row are an AND gate.",
	"tip: coils lose charge in under a second. that's a feature -- it makes logic snappy.",
	"tip: the Rocket 2.0's bubble seats a friend. press F on it while they fly.",
	"tip: Sanus spits lava at visitors. the ultima is real though.",
	"tip: gas giants eat rockets whole. parked, flying, doesn't matter.",
	"tip: the eye in the sky is always watching. its color is its mood.",
	"tip: spawn beacons place dormant. F claims one -- and un-claims all the others.",
	"tip: Earth's humans look dumb. press F on one and reconsider.",
	"tip: right-click the map in the teleport picker to warp straight there.",
	"tip: the sell station got twice as fast. the e-seller is faster still.",
	"tip: your face is drawable. your face is also saveable. skin library, character screen.",
	"tip: killing a Clawde crab pays well and costs more. Claude is cool.",
	"tip: full prism armor caps damage reduction on three pieces. the boots are a flex.",
	"tip: hyperdrives stay in the rocket's bones. dismantle it and the drive comes along.",
]

var _tip: Label

func _roll_tip() -> void:
	if _tip:
		_tip.text = TIPS[randi() % TIPS.size()]

## Tutorial session: fresh throwaway world on the tutorial planet.
## Nothing it does is ever written to disk.
func _start_tutorial() -> void:
	Save.ephemeral = true
	Game.tutorial_session = true
	Save.new_slot(Save.next_id(), {"color": "#3aa0ff", "shader": "none"}, "TUTORIAL")
	get_tree().change_scene_to_file("res://Main.tscn")

func _process(delta: float) -> void:
	if _bg_pivot:
		_bg_pivot.rotate_y(delta * 0.15)
	for o in _orbits:
		o[0].rotate_y(delta * float(o[1]))
	if _crab and is_instance_valid(_crab):
		_crab.rotate_y(delta * 0.9)   # tumbling menace
		_crab.rotate_x(delta * 0.35)
	if _invader and is_instance_valid(_invader):
		_invader.rotate_y(delta * -0.7)
		_invader.rotate_z(delta * 0.25)

func _build_background() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sh := Shader.new()
	sh.code = "shader_type sky;\nvoid sky(){\n vec3 d=EYEDIR;\n vec3 cell=floor(d*150.0);\n float n=fract(sin(dot(cell,vec3(12.9898,78.233,37.719)))*43758.5453);\n float star=step(0.997,n);\n COLOR=vec3(0.02,0.02,0.05)+vec3(star)*0.9;\n}"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sky.sky_material = sm
	env.sky = sky
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 9.0)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -50, 0)
	light.light_energy = 1.2
	add_child(light)

	# a little solar system spins behind the menu...
	for spec in [[7.0, 0.9, 0.10, Color("#2f7d32")], [11.0, 1.4, -0.06, Color("#0e3b2e")],
			[15.0, 0.6, 0.14, Color("#c8a557")], [19.0, 1.1, -0.04, Color("#e8a3c0")]]:
		var orbit := Node3D.new()
		orbit.rotation_degrees = Vector3(randf_range(-14, 14), randf_range(0, 360), 0)
		add_child(orbit)
		var pl := MeshInstance3D.new()
		var pm2 := SphereMesh.new()
		pm2.radius = spec[1]
		pm2.height = spec[1] * 2.0
		pl.mesh = pm2
		pl.material_override = Destructible.make_material(spec[3], 0.15)
		pl.position = Vector3(spec[0], 0, 0)
		orbit.add_child(pl)
		_orbits.append([orbit, spec[2]])
	# ...and Clawde the space invader crab tumbles through it all
	var crab_orbit := Node3D.new()
	crab_orbit.rotation_degrees = Vector3(20, 0, 8)
	add_child(crab_orbit)
	_crab = ClawdeCrab.new()
	crab_orbit.add_child(_crab)
	_crab.position = Vector3(13.0, 2.0, 0)
	_crab.scale = Vector3.ONE * 0.22
	_crab.build()
	_orbits.append([crab_orbit, 0.08])
	# ...and a CLASSIC space invader drifts the other way
	var inv_orbit := Node3D.new()
	inv_orbit.rotation_degrees = Vector3(-14, 140, -6)
	add_child(inv_orbit)
	_invader = Invader.new()
	inv_orbit.add_child(_invader)
	_invader.position = Vector3(16.0, -1.5, 0)
	_invader.scale = Vector3.ONE * 0.16
	_invader.build(Color("#7dff6a"))
	_orbits.append([inv_orbit, -0.06])

	_bg_pivot = Node3D.new()
	_bg_pivot.position = Vector3(3.5, 0.5, 0)
	add_child(_bg_pivot)
	var planet := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 3.0
	pm.height = 6.0
	pm.radial_segments = 40
	pm.rings = 24
	planet.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#5a2d8f")
	mat.metallic = 0.2
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = Color("#7a1dbe")
	mat.emission_energy_multiplier = 0.3
	planet.material_override = mat
	_bg_pivot.add_child(planet)
	# a little moon
	var moon := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.7
	mm.height = 1.4
	moon.mesh = mm
	moon.material_override = Destructible.make_material(Color("#c8c8d8"), 0.1)
	moon.position = Vector3(-4.5, 1.2, 1.0)
	_bg_pivot.add_child(moon)

func _build_title() -> void:
	_title_ui = CanvasLayer.new()
	add_child(_title_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.55)   # translucent: the parade shows through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_ui.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-300, -300)
	col.custom_minimum_size = Vector2(600, 600)
	col.add_theme_constant_override("separation", 14)
	_title_ui.add_child(col)

	var title := Label.new()
	title.text = "DUDESPACE"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Label.new()
	sub.text = "destroy everything. across a universe."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	col.add_child(sub)

	# --- the save list lives right here, always ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(list)
	var ids := Save.list_saves()
	if ids.is_empty():
		var none := Label.new()
		none.text = "no saves yet. press NEW GAME."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.modulate = Color(1, 1, 1, 0.6)
		list.add_child(none)
	for id_v in ids:
		var id: int = id_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var play := Button.new()
		play.custom_minimum_size = Vector2(500, 50)
		play.text = "%s   ·   %s" % [Save.slot_name(id), Save.slot_summary(id)]
		play.pressed.connect(func() -> void:
			Save.load_slot(id)
			get_tree().change_scene_to_file("res://Main.tscn"))
		row.add_child(play)
		var del := Button.new()
		del.text = "🗑"
		del.custom_minimum_size = Vector2(50, 50)
		del.pressed.connect(func() -> void:
			Save.delete_slot(id)
			_refresh_title())
		row.add_child(del)
		list.add_child(row)

	# --- buttons at the BOTTOM ---
	var btnrow := HBoxContainer.new()
	btnrow.add_theme_constant_override("separation", 12)
	btnrow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btnrow)
	var newg := Button.new()
	newg.text = "NEW GAME"
	newg.custom_minimum_size = Vector2(220, 56)
	newg.pressed.connect(func() -> void:
		Save.current_slot = Save.next_id()
		_open_creator())
	btnrow.add_child(newg)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 56)
	back.pressed.connect(func() -> void:
		_title_ui.queue_free()
		_build_main_menu())
	btnrow.add_child(back)

func _refresh_title() -> void:
	if _title_ui:
		_title_ui.queue_free()
	_build_title()

func _open_creator() -> void:
	if _title_ui:
		_title_ui.hide()
	_creator = CharacterCreator.new()
	_creator.started.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	_creator.back.connect(func():
		_creator.queue_free()
		_creator = null
		if _title_ui:
			_title_ui.show())
	add_child(_creator)

func _open_options() -> void:
	if _options:
		return
	_options = CanvasLayer.new()
	_options.layer = 5
	var panel := OptionsPanel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-180, -140)
	panel.closed.connect(func():
		_options.queue_free()
		_options = null)
	_options.add_child(panel)
	add_child(_options)
