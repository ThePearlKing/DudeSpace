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
	if OS.get_environment("CTD_TEST") == "49":
		_title_shot()
	Net.leave()   # back at the title = session over
	_build_background()
	_build_main_menu()
	add_child(HumanFaceEditor.new())   # F9 face editor works here too
	# save-doctor rig: CTD_LOAD=<slot> boots straight into that save with
	# writes disabled, so a broken world can be reproduced and read
	# WITHOUT the autosave touching the file
	var dbg := OS.get_environment("CTD_LOAD")
	if dbg != "":
		Save.load_slot(int(dbg))
		Save.ephemeral = true
		print("SAVEDOCTOR loading slot ", int(dbg), " name=", Save.slot_name(int(dbg)),
			" (read-only)")
		get_tree().change_scene_to_file.call_deferred("res://Main.tscn")
		return
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
	"tip: hold TAB for the player list -- every username, and how far away they are.",
	"tip: double-tap 0 in a rocket for a ten-second 20x overdrive. ninety second cooldown.",
	"tip: you step up small ledges automatically. stairs are a solved problem.",
	"tip: ATM deposits survive death. pocket coins do not.",
	"tip: the anti-death charm costs 3 ultima and disagrees with dying once.",
	"tip: right-click with a backpack held opens its bag.",
	"tip: the knife HARVESTS plants as items. fists just make salad confetti.",
	"tip: warp pads need a full charge AND 2000 coins. wire them early.",
	"tip: a coil on a machine makes it a switchable valve -- power decides if it runs.",
	"tip: Q drops the held item. the DELETE slot burns it forever.",
	"tip: time rifts rewind five minutes. placed machines are exempt.",
	"tip: the black hole has no death screen. it just keeps you.",
	"tip: glowing seams on crates mean OPENABLE.",
	"tip: Big Computer is worth a visit.",
	"tip: a Network Analyser wired anywhere reports your WHOLE grid: gained, lost, net EU/s.",
	"tip: hyperdrive: hold H in a rocket. point first, regret never.",
	"tip: jetpack: Space up, C down. zero-g turns it into a spaceship.",
	"tip: F1 hides the whole HUD. F1 brings it back. screenshots thank you.",
	"tip: sell stations pay double what the shop does.",
	"tip: spawn beacons place dormant. F claims one as YOUR respawn.",
	"tip: the shop shows ??? until you learn a recipe. temples teach.",
	"tip: fuel and jet fuel are different liquids. rockets are picky.",
	"tip: K opens the calendar. some visitors keep schedules.",
	"tip: number keys 1-9 warp time in a rocket. burning cancels it.",
	"tip: the Zapper fires twenty zaps a second. the math works out.",
	"tip: gas giants have no floor. your rocket also believes this.",
	"tip: Undros has no land. the sand floor is 40 meters down.",
	"tip: the universe has an edge. it pushes back. keep pushing anyway.",
	"tip: the dotted circle on the map is where everything ends.",
	"tip: how big the EYEBALL is -- the eyeball itself, not the god -- is its mood. small: safe. swollen: not.",
	"tip: scroll on a shop card to craft a whole stack of it at once.",
	"tip: the Furniture Placer builds benches, chairs, TABLES, beds -- 2 plantfiber each.",
	"tip: TVs sit on tables and catwalks, MOUNT on walls, and show ALIEN NEWS, spy cameras, and FORK TV.",
	"tip: wire a computer into a TV and the TV becomes its monitor.",
	"tip: the moon is made out of cheese. prepare your auto miners.",
	"tip: security cameras float ANYWHERE -- open space or bolted to a wall -- and F aims them rocket-style.",
	"tip: houses are bigger inside -- and machines, wires, and TVs all work in there.",
	"the fork is coming.",
	"tip: gas giants have no ground. do not go looking for the ground.",
	"tip: K opens the calendar. UFO trader Saturdays are predictable.",
	"tip: prism shards only grow under shader light.",
	"tip: a bioreactor accepts a permadeath apple. 500 EU. coward.",
	"tip: the sell station buys meat, salad, even coal. everything has a price.",
	"tip: humans may seem smart. they are dumb and inefficient.",
	"tip: crafting, furniture and houses can pull materials straight from your backpack.",
	"tip: F5 changes camera.",
	"tip: dying on a sun vaporizes your items. there is no going back for them.",
	"tip: want real logic and automation? the COMPUTER has ports for exactly that.",
	"tip: coils lose charge in under a second. switches should be snappy.",
	"tip: the Rocket 2.0's bubble seats a friend. press F on it while they fly.",
	"tip: Sanus spits lava at visitors. the ultima is real though.",
	"tip: gas giants eat rockets whole. parked, flying, doesn't matter.",
	"tip: the eye in the sky is always watching. when the eyeball itself swells bigger, its mood is worse.",
	"tip: spawn beacons place dormant. F claims one -- and un-claims all the others.",
	"tip: Earth's humans look dumb. press F on one and reconsider.",
	"tip: right-click the map in the teleport picker to warp straight there.",
	"tip: your face is drawable. your face is also saveable. skin library, character screen.",
	"tip: killing a Clawde crab pays well and costs more. Claude is cool.",
	"tip: full prism armor caps damage reduction on three pieces. the boots are a flex.",
	"tip: hyperdrives stay in the rocket's bones. dismantle it and the drive comes along.",
]

var _tip: Label

var _tip_bag: Array = []
func _roll_tip() -> void:
	if _tip == null:
		return
	# a shuffle bag: every tip appears once before any repeats
	if _tip_bag.is_empty():
		_tip_bag = range(TIPS.size())
		_tip_bag.shuffle()
	_tip.text = TIPS[_tip_bag.pop_back()]

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
	mk.call("ADVANCED (handbook, power, alloys, chemistry, automation)", "advanced")
	# the reactor sits at the BOTTOM on purpose: it is the last lesson,
	# and the advanced course hands off into it when it finishes
	mk.call("NUCLEAR REACTOR (guided startup, safe meltdowns)", "reactor")
	var back := Button.new()
	back.text = "back"
	back.custom_minimum_size = Vector2(380, 40)
	back.pressed.connect(lay.queue_free)
	col.add_child(back)

## CTD_TEST=49 -- proof shot of the menu, gas giant and all.
func _title_shot() -> void:
	await get_tree().create_timer(2.5).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/shots/title_gasgiant.png")
		print("TITLESHOT docs/shots/title_gasgiant.png")
	print("TITLESHOT done")
	get_tree().quit()

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
			# A REAL BANDED GIANT. Belts and zones alternate -- different
			# colours, different widths, streaming in OPPOSITE directions
			# -- with cloud filaments stretched along each band, curled
			# turbulence where two bands shear past each other, and storms
			# that sit INSIDE a band and drag the flow around themselves.
			frag = """
float hashf(float x){ return fract(sin(x * 127.1) * 43758.5453); }

// the belt/zone palette: pastel purples, mauves and creams. index picks
// a family, so neighbouring bands never come out the same colour
vec3 band_col(float h, vec3 bs, vec3 wt){
	vec3 cream  = mix(bs, vec3(1.00, 0.95, 0.86), 0.92);
	vec3 pale   = mix(bs, wt, 0.72);
	vec3 lilac  = mix(bs, vec3(0.86, 0.80, 1.00), 0.62);
	vec3 mauve  = mix(bs, vec3(0.72, 0.55, 0.82), 0.34);
	vec3 deepv  = mix(bs, vec3(0.35, 0.20, 0.55), 0.20);
	if (h < 0.22) return cream;
	if (h < 0.44) return pale;
	if (h < 0.66) return lilac;
	if (h < 0.85) return mauve;
	return deepv;
}

void fragment(){
	vec3 n = normalize(vn);
	float t = TIME;
	vec3 white = vec3(1.0, 0.98, 1.0);
	// spherical coordinates: bands are latitude, flow is longitude
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.z, n.x);
	// --- storms first: they DEFLECT the bands that run past them
	// longitudes chosen so the great spot faces the menu camera; the
	// case rotates, so the other two swing round behind it
	vec2 s1 = vec2(1.45, -0.32);  vec2 s2 = vec2(0.35, 0.46);
	vec2 s3 = vec2(2.55, 0.12);
	vec2 dv = vec2(0.0);
	float eye = 0.0; float wall = 0.0; float spin = 0.0;
	for (int i = 0; i < 3; i++){
		vec2 c = i == 0 ? s1 : (i == 1 ? s2 : s3);
		float rr = i == 0 ? 0.52 : (i == 1 ? 0.30 : 0.20);
		float dirn = i == 1 ? -1.0 : 1.0;
		// angular offset, longitude squeezed by latitude like a real map
		vec2 d = vec2((lon - c.x) * cos(lat), lat - c.y);
		d.y *= 1.9;                       // storms are wider than they are tall
		float r = length(d) / rr;
		float fall = smoothstep(1.25, 0.15, r);
		// drag the surrounding flow around the oval
		dv += vec2(-d.y, d.x) * dirn * fall * 0.55;
		float ang = atan(d.y, d.x) + (1.0 - r) * 4.5 * dirn + t * 0.25 * dirn;
		spin = mix(spin, 0.5 + 0.5 * sin(ang * 2.0 + r * 5.0), fall);
		wall = max(wall, smoothstep(0.55, 0.95, r) * smoothstep(1.2, 0.95, r));
		eye = max(eye, fall);
	}
	lon += dv.x; lat += dv.y * 0.5;
	// --- bands: fifteen of them, alternating direction and width
	float bandf = lat * 7.0;
	float id = floor(bandf);
	float fb = fract(bandf);
	float h = hashf(id * 3.7);
	float dirb = mod(id, 2.0) < 0.5 ? 1.0 : -1.0;
	float u = lon + dirb * t * 0.03 * (0.5 + 0.9 * h);
	// filaments: noise stretched LONG in longitude, thin in latitude
	float fil = fbm(vec3(u * 1.7, lat * 22.0, h * 9.0));
	float fine = fbm(vec3(u * 4.5, lat * 46.0, h * 3.0));
	// turbulence where two bands shear past each other: curls, not lines
	float seam = 1.0 - abs(fb - 0.5) * 2.0;
	float curl = fbm(vec3(u * 5.0 + fil * 2.2, lat * 34.0, 7.0));
	float ripple = smoothstep(0.55, 1.0, seam) * (0.5 + 0.5 * sin(u * 26.0 + curl * 9.0));
	// --- colour: this band, the next band, blended across the seam
	vec3 cA = band_col(h, base, white);
	vec3 cB = band_col(hashf((id + sign(fb - 0.5)) * 3.7), base, white);
	vec3 col = mix(cA, cB, smoothstep(0.34, 0.5, abs(fb - 0.5)) * 0.45);
	// layers INSIDE the band: bright filaments and darker lanes
	col = mix(col, mix(col, white, 0.55), smoothstep(0.45, 0.85, fil) * 0.55);
	col = mix(col, col * 0.82, smoothstep(0.55, 0.2, fil) * 0.5);
	col = mix(col, mix(col, white, 0.35), smoothstep(0.6, 0.9, fine) * 0.3);
	// the shear line itself: churned, half-lit, never a clean stripe
	col = mix(col, mix(col * 0.78, white, ripple * 0.55), smoothstep(0.5, 1.0, seam) * 0.6);
	// --- the storms sit on top, inside their band
	// the spot: warm cream arms wound round a bright core, ringed by a
	// darker violet eyewall so it sits IN the band instead of on it
	vec3 eyecol = mix(mix(base, vec3(1.0, 0.88, 0.78), 0.86),
		vec3(1.0, 0.97, 0.92), spin * 0.75);
	col = mix(col, eyecol, eye * 0.95);
	col = mix(col, mix(base, vec3(0.42, 0.26, 0.58), 0.45), wall * eye * 0.7);
	// polar hoods: colder, paler, and they eat the last band
	float pole = smoothstep(0.72, 1.0, abs(n.y));
	col = mix(col, mix(base, white, 0.62), pole * 0.7);
	// rim light
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = col;
	EMISSION = col * 0.16 + base * fres * 1.1 + white * eye * spin * 0.12;
	ROUGHNESS = 0.86;
	SPECULAR = 0.18;
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
