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

func _show_epilepsy_note() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -140)
	dim.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var t := Label.new()
	t.text = "  PHOTOSENSITIVITY WARNING  "
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color("#ffd166"))
	col.add_child(t)
	var b := Label.new()
	b.text = "Parts of this game (notably the shader system's planets)\ncontain flashing imagery, rapid color changes, and moving\npatterns that may affect photosensitive players.\nIf you feel dizzy or unwell, stop playing."
	b.add_theme_font_size_override("font_size", 15)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(500, 0)
	col.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var ok := Button.new()
	ok.text = "Continue"
	ok.custom_minimum_size = Vector2(240, 46)
	ok.pressed.connect(layer.queue_free)
	row.add_child(ok)
	var never := Button.new()
	never.text = "Don't show again"
	never.custom_minimum_size = Vector2(240, 46)
	never.pressed.connect(func() -> void:
		Settings.epilepsy_seen = true
		Settings.save_cfg()
		layer.queue_free())
	row.add_child(never)

func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Settings.epilepsy_seen:
		_show_epilepsy_note.call_deferred()
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
		["QUIT", func() -> void:
			Surfaces.shutdown()
			IconLib.shutdown(get_tree())
			get_tree().quit()],
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
	"tip: 1-9 warps time while coasting in a rocket. 0 is 10x. double-tap 0: 20x for a burst (cooldown). burning cancels it.",
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
	"tip: crafting, furniture and houses can pull materials straight from your backpack.",
	"tip: F5 changes camera. G strikes a pose. combine responsibly.",
	"tip: dying on a sun vaporizes your items. there is no going back for them.",
	"tip: a coil on a power extender IS an AND gate (control input x power input).",
	"tip: coils lose charge in under a second. that's a feature -- it makes logic snappy.",
	"tip: the Rocket 2.0's bubble seats a friend. press F on it while they fly.",
	"tip: Sanus spits lava at visitors. the ultima is real though.",
	"tip: gas giants eat rockets whole. parked, flying, doesn't matter.",
	"tip: the eye in the sky is always watching. its color is its mood.",
	"tip: spawn beacons place dormant. F claims one -- and un-claims all the others.",
	"tip: Earth's humans look dumb. press F on one and reconsider.",
	"tip: right-click the map in the teleport picker to warp straight there.",
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
	# a MENU of lessons, not a single track. It lives on its OWN
	# CanvasLayer ABOVE the title UI -- parented to the 3D root it drew
	# UNDER the buttons and looked like a pile-up instead of a popup.
	var lay := CanvasLayer.new()
	lay.layer = 30
	add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-190, -130)
	OptionsPanel._glow(panel)
	dim.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "  WHICH TUTORIAL?  "
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	var mk := func(txt: String, mode: String) -> void:
		var b := Button.new()
		b.text = txt
		b.custom_minimum_size = Vector2(380, 48)
		b.pressed.connect(func() -> void:
			Game.tutorial_mode = mode
			Save.ephemeral = true
			Game.tutorial_session = true
			Save.new_slot(Save.next_id(), {"color": "#3aa0ff", "shader": "none"}, "TUTORIAL")
			get_tree().change_scene_to_file("res://Main.tscn"))
		col.add_child(b)
	mk.call("BASIC SURVIVAL (mine, craft, fly)", "basic")
	mk.call("NUCLEAR REACTOR (guided startup, safe meltdowns)", "reactor")
	var back := Button.new()
	back.text = "back"
	back.custom_minimum_size = Vector2(380, 40)
	back.pressed.connect(lay.queue_free)
	col.add_child(back)

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

const _TP_NOISE := """
varying vec3 vn;
float hash3(vec3 p){ return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p){
	vec3 i = floor(p); vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
float fbm(vec3 p){
	float v = 0.0; float amp = 0.55;
	for (int i = 0; i < 4; i++){ v += vnoise(p) * amp; p *= 2.1; amp *= 0.5; }
	return v;
}
void vertex(){ vn = NORMAL; }
"""

## Title planets get real faces, keyed off their colour.
func _tp_mat(style: String, c: Color) -> ShaderMaterial:
	var frag := ""
	match style:
		"gas":
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	float t = TIME * 0.04;
	float band = sin(n.y * 16.0 + fbm(n * 3.0 + vec3(t, 0.0, t)) * 4.0);
	vec3 col = mix(base * 0.55, base * 1.25, band * 0.5 + 0.5);
	float storm = smoothstep(0.22, 0.0, length(n.xy - vec2(0.45, -0.25)));
	col = mix(col, vec3(0.85, 0.4, 0.25), storm * 0.8);
	ALBEDO = col; ROUGHNESS = 0.9;
	EMISSION = col * 0.25;
}
"""
		"cont":
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	float m = fbm(n * 4.0);
	vec3 sea = base * 0.35 + vec3(0.0, 0.03, 0.14);
	vec3 land = base * (0.9 + 0.5 * fbm(n * 9.0));
	vec3 col = mix(sea, land, smoothstep(0.45, 0.55, m));
	col = mix(col, vec3(0.92), smoothstep(0.82, 0.92, abs(n.y)));
	ALBEDO = col; ROUGHNESS = 0.8;
}
"""
		"circuit":
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	vec3 g = fract(n * 6.0);
	float tr = max(max(step(0.88, g.x), step(0.88, g.y)), step(0.88, g.z));
	float tile = mod(floor(n.x * 6.0) + floor(n.y * 6.0) + floor(n.z * 6.0), 2.0);
	vec3 col = base * (0.4 + 0.3 * tile + 0.2 * fbm(n * 8.0));
	float pulse = 0.5 + 0.5 * sin(TIME * 2.2 + floor(n.x * 6.0) * 1.7 + floor(n.z * 6.0));
	ALBEDO = col;
	EMISSION = vec3(0.25, 1.0, 0.6) * tr * (0.6 + 1.4 * pulse);
	ROUGHNESS = 0.55;
}
"""
		"dude":
			frag = """
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
	float pulse = 0.5 + 0.5 * sin(TIME * 2.0 + h * 12.0);
	ALBEDO = col;
	EMISSION = vec3(0.3, 1.0, 0.5) * pad * (0.5 + pulse) + copper * tr * 0.15;
	METALLIC = tr * 0.7;
	ROUGHNESS = 0.5;
}
"""
		"rock":
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	vec3 col = base * (0.62 + 0.5 * fbm(n * 6.0));
	float cr = smoothstep(0.16, 0.1, abs(fbm(n * 4.0) - 0.45));
	col *= 1.0 - 0.35 * cr;
	ALBEDO = col; ROUGHNESS = 1.0;
}
"""
		"dune":
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	float d = sin(n.y * 26.0 + fbm(n * 5.0) * 6.0);
	vec3 col = mix(base * 0.7, base * 1.2, d * 0.5 + 0.5);
	col *= 0.85 + 0.3 * fbm(n * 11.0);
	ALBEDO = col; ROUGHNESS = 1.0;
}
"""
		_:
			frag = """
void fragment(){
	vec3 n = normalize(vn);
	float sw = fbm(n * 3.0 + fbm(n * 6.0) * 1.8);
	vec3 col = mix(base * 0.75, vec3(1.0, 0.95, 0.98), smoothstep(0.35, 0.75, sw));
	ALBEDO = col; ROUGHNESS = 0.6;
}
"""
	var sh9 := Shader.new()
	sh9.code = "shader_type spatial;\nuniform vec3 base : source_color;\n" + _TP_NOISE + frag
	var m9 := ShaderMaterial.new()
	m9.shader = sh9
	m9.set_shader_parameter("base", Vector3(c.r, c.g, c.b))
	return m9

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

	# the ORIGINAL little solar system, untouched layout -- same sizes,
	# same colours, same orbits. Only the surfaces changed: flat plastic
	# became living continents, dude-built circuit traces (two of those
	# -- this IS the Dude system), banded dunes, candy marble.
	for spec in [[7.0, 0.9, 0.10, Color("#2f7d32"), "cont"],
			[11.0, 1.4, -0.06, Color("#0e3b2e"), "dude"],
			[15.0, 0.6, 0.14, Color("#c8a557"), "dune"],
			[19.0, 1.1, -0.04, Color("#e8a3c0"), "circuit"]]:
		var orbit := Node3D.new()
		orbit.rotation_degrees = Vector3(randf_range(-14, 14), randf_range(0, 360), 0)
		add_child(orbit)
		var pl := MeshInstance3D.new()
		var pm2 := SphereMesh.new()
		pm2.radius = spec[1]
		pm2.height = spec[1] * 2.0
		pm2.radial_segments = 36
		pm2.rings = 24
		pl.mesh = pm2
		pl.material_override = _tp_mat(str(spec[4]), spec[3])
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
	pm.radial_segments = 48
	pm.rings = 32
	planet.mesh = pm
	# the OG purple giant, now DETAILED: churning banded gas, storm eye,
	# same colour it always was
	planet.material_override = _tp_mat("gas", Color("#5a2d8f"))
	_bg_pivot.add_child(planet)
	# a little moon
	var moon := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.7
	mm.height = 1.4
	moon.mesh = mm
	moon.material_override = _tp_mat("rock", Color("#c8c8d8"))   # no plastic moons
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
		var ren := Button.new()
		ren.text = "✏"
		ren.custom_minimum_size = Vector2(50, 50)
		ren.pressed.connect(func() -> void:
			var dlg := AcceptDialog.new()
			dlg.title = "Rename world"
			var le := LineEdit.new()
			le.text = Save.slot_name(id)
			le.custom_minimum_size = Vector2(320, 42)
			dlg.add_child(le)
			dlg.register_text_enter(le)
			dlg.confirmed.connect(func() -> void:
				Save.rename_slot(id, le.text)
				_refresh_title())
			add_child(dlg)
			dlg.popup_centered()
			le.grab_focus()
			le.select_all())
		row.add_child(ren)
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
