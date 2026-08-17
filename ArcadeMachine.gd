class_name ArcadeMachine
extends Machine
## THE CABINET. An upright arcade machine with a real screen, a real
## stick, and a DUDE-16 inside it. It does not want your electricity --
## whatever is in there has been running since before anybody found it
## and shows no sign of stopping.
##
## Idle, it plays the attract loop on its own screen so you can see it
## from across the room. Walk up and press F and the same console you
## were watching fills your view: same machine, same state, no reboot.

const CAB_W := 0.92
const CAB_H := 2.05
const CAB_D := 0.9

var con: ArcadeConsole = null
var shell: ArcadeShell = null
var edit = null
var sound = null
var floppy_in: Dictionary = {}          # the disc currently in the slot
## Boards fitted in the back. A stock cabinet is deliberately a lesser
## machine: two canvas sizes, four voices, no modulators, everything on
## whole pixels. The boards are how it grows.
var boards := {"expand": false, "smooth": false}
var user_carts: Array = []              # carts written on this machine

var _screen: MeshInstance3D
var _screen_mat: ShaderMaterial
var _tex_bg := ImageTexture.new()
var _tex_main := ImageTexture.new()
var _tex_ui := ImageTexture.new()
var _tex_pal := ImageTexture.new()
var _attract_t: float = 0.0
var _open: bool = false
var _marquee: MeshInstance3D
var _board_lamp: MeshInstance3D

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D bg_tex : filter_nearest, repeat_enable;
uniform sampler2D main_tex : filter_nearest, repeat_enable;
uniform sampler2D ui_tex : filter_nearest, repeat_enable;
uniform sampler2D pal_tex : filter_nearest, repeat_enable;
uniform vec2 ui_size = vec2(480.0, 270.0);
uniform vec2 game_size = vec2(480.0, 270.0);
uniform float scan : hint_range(0.0, 1.0) = 0.4;

vec4 look(sampler2D t, vec2 uv, vec2 size) {
	vec2 p = (floor(fract(uv) * size) + 0.5) / size;
	float idx = floor(texture(t, p).r * 255.0 + 0.5);
	return texture(pal_tex, vec2((idx + 0.5) / 256.0, 0.5));
}

void fragment() {
	vec2 uv = vec2(UV.x, UV.y);
	vec4 c = vec4(0.02, 0.02, 0.03, 1.0);
	vec4 b = look(bg_tex, uv, game_size);
	c = mix(c, vec4(b.rgb, 1.0), b.a);
	vec4 m = look(main_tex, uv, game_size);
	c = mix(c, vec4(m.rgb, 1.0), m.a);
	vec4 u = look(ui_tex, uv, ui_size);
	c = mix(c, vec4(u.rgb, 1.0), u.a);
	float line = floor(uv.y * game_size.y);
	c.rgb *= 1.0 - scan * 0.35 * mod(line, 2.0);
	// a CRT is a light source, not a painted board
	ALBEDO = c.rgb;
	EMISSION = c.rgb * 1.6;
}
"""

func _init() -> void:
	title = "ARCADE CABINET"
	box_color = Color("#1b1a24")
	box_size = Vector3(CAB_W, CAB_H, CAB_D)
	buf_cap = 0.0                       # NO electricity. It just runs.
	refund_id = "arcade"

func _ready() -> void:
	super._ready()
	_build_cabinet()
	con = ArcadeConsole.new()
	shell = ArcadeShell.new(con)
	shell.machine = self
	_refresh_shelf()
	edit = ArcadeEdit.new(con, shell)
	shell.edit = edit
	sound = ChipSound.new()
	add_child(sound)
	con.sound = sound
	edit.sound = sound
	_apply_boards()
	if not _pending.is_empty():
		_apply_data(_pending)
		_pending = {}
	shell.volume = 0.7

## The box, the stick, the buttons, the coin door, the light on top.
func _build_cabinet() -> void:
	var body := Color("#2a2338")
	var trim := Color("#12111a")
	var accent := Color("#ff5c7c")
	# the plain grey box the base class made is not a cabinet
	if _mesh:
		_mesh.visible = false
	var hw := CAB_W * 0.5
	var hd := CAB_D * 0.5
	# --- main body, in three stacked sections so it has a silhouette
	var lower := BoxMesh.new()
	lower.size = Vector3(CAB_W, 0.9, CAB_D)
	part(lower, Vector3(0, 0.45, 0), body, 0.06)
	var upper := BoxMesh.new()
	upper.size = Vector3(CAB_W, 0.95, CAB_D * 0.72)
	part(upper, Vector3(0, 1.42, -0.08), body, 0.06)
	var headbox := BoxMesh.new()
	headbox.size = Vector3(CAB_W, 0.22, CAB_D * 0.5)
	part(headbox, Vector3(0, 2.0, -0.14), trim, 0.05)
	# --- side art panels, inset, with two colour bands each
	for sx in [-1.0, 1.0]:
		var panel := BoxMesh.new()
		panel.size = Vector3(0.02, 0.86, CAB_D * 0.66)
		part(panel, Vector3(sx * (hw + 0.005), 1.42, -0.08),
			Color("#3b2f57"), 0.1)
		for i in 3:
			var band := BoxMesh.new()
			band.size = Vector3(0.024, 0.06, CAB_D * 0.6)
			part(band, Vector3(sx * (hw + 0.012), 1.15 + float(i) * 0.22, -0.08),
				[accent, Color("#4fa4ff"), Color("#feae34")][i], 0.9)
		var lowpanel := BoxMesh.new()
		lowpanel.size = Vector3(0.02, 0.8, CAB_D * 0.9)
		part(lowpanel, Vector3(sx * (hw + 0.005), 0.45, 0), Color("#241d33"), 0.08)
	# --- T-molding: bright edging down every corner, like the real thing
	for sx2 in [-1.0, 1.0]:
		var edge := BoxMesh.new()
		edge.size = Vector3(0.035, CAB_H - 0.1, 0.035)
		part(edge, Vector3(sx2 * hw, (CAB_H - 0.1) * 0.5, hd - 0.02),
			Color("#f2f2f7"), 0.35)
		var edge2 := BoxMesh.new()
		edge2.size = Vector3(0.035, CAB_H - 0.1, 0.035)
		part(edge2, Vector3(sx2 * hw, (CAB_H - 0.1) * 0.5, -hd + 0.02),
			Color("#f2f2f7"), 0.35)
	# --- marquee: a lit sign box over the screen
	var mar := BoxMesh.new()
	mar.size = Vector3(CAB_W - 0.06, 0.2, 0.06)
	_marquee = part(mar, Vector3(0, 1.87, hd - 0.24), Color("#ffe9a8"), 1.5)
	var marlip := BoxMesh.new()
	marlip.size = Vector3(CAB_W, 0.05, 0.16)
	part(marlip, Vector3(0, 1.99, hd - 0.28), trim, 0.05)
	var name_lbl := Label3D.new()
	name_lbl.text = "DUDE-16"
	name_lbl.font_size = 64
	name_lbl.pixel_size = 0.0016
	name_lbl.modulate = Color("#1b1230")
	name_lbl.position = Vector3(0, 1.87, hd - 0.205)
	name_lbl.no_depth_test = false
	add_child(name_lbl)
	# --- screen: recessed, tilted back, with a heavy bezel
	var bez := BoxMesh.new()
	bez.size = Vector3(CAB_W - 0.06, 0.66, 0.1)
	part(bez, Vector3(0, 1.48, hd - 0.2), Color("#0e0d14"), 0.03,
		Vector3(-11, 0, 0))
	var quad := QuadMesh.new()
	quad.size = Vector2(CAB_W - 0.16, 0.5)
	_screen = MeshInstance3D.new()
	_screen.mesh = quad
	_screen.position = Vector3(0, 1.49, hd - 0.145)
	_screen.rotation_degrees = Vector3(-11, 0, 0)
	var sh := Shader.new()
	sh.code = SCREEN_SHADER
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = sh
	_screen.material_override = _screen_mat
	add_child(_screen)
	# --- control deck: sloped, with a lip you could rest your wrists on
	var deck := BoxMesh.new()
	deck.size = Vector3(CAB_W, 0.06, 0.34)
	part(deck, Vector3(0, 1.02, hd - 0.02), Color("#1a1626"), 0.08,
		Vector3(-14, 0, 0))
	var lip := BoxMesh.new()
	lip.size = Vector3(CAB_W, 0.05, 0.05)
	part(lip, Vector3(0, 0.99, hd + 0.12), Color("#f2f2f7"), 0.3)
	# joystick: shaft, dust washer, ball
	var wash := CylinderMesh.new()
	wash.top_radius = 0.05
	wash.bottom_radius = 0.055
	wash.height = 0.012
	part(wash, Vector3(-0.24, 1.06, hd - 0.03), Color("#0d0c12"), 0.05)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.014
	shaft.height = 0.1
	part(shaft, Vector3(-0.24, 1.11, hd - 0.03), Color("#c8ccd4"), 0.4)
	var ball := SphereMesh.new()
	ball.radius = 0.038
	ball.height = 0.076
	part(ball, Vector3(-0.24, 1.17, hd - 0.03), Color("#e43b44"), 0.5)
	# six buttons, two rows, in cabinet colours
	var bcols := [Color("#feae34"), Color("#4fa4ff"), Color("#b6d53c"),
		Color("#ff5c7c"), Color("#26c2cd"), Color("#b04ad6")]
	for i in 6:
		var bx := -0.02 + float(i % 3) * 0.11
		var bz := hd - 0.09 + float(i / 3) * 0.1
		var btn := CylinderMesh.new()
		btn.top_radius = 0.028
		btn.bottom_radius = 0.03
		btn.height = 0.022
		part(btn, Vector3(bx, 1.075 + float(i / 3) * 0.022, bz),
			bcols[i], 0.7, Vector3(-14, 0, 0))
	for i in 2:
		var sbtn := CylinderMesh.new()
		sbtn.top_radius = 0.016
		sbtn.bottom_radius = 0.017
		sbtn.height = 0.016
		part(sbtn, Vector3(0.3 + float(i) * 0.06, 1.06, hd + 0.03),
			Color("#fdfdf5") if i == 0 else Color("#fee761"), 0.6,
			Vector3(-14, 0, 0))
	# --- the front, below the deck: art panel, stripes, and an emblem,
	# because a cabinet with a blank front is a fridge
	var artp := BoxMesh.new()
	artp.size = Vector3(CAB_W - 0.06, 0.62, 0.02)
	part(artp, Vector3(0, 0.5, hd + 0.005), Color("#20183a"), 0.12)
	for i in 3:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(CAB_W - 0.12, 0.05, 0.012)
		part(stripe, Vector3(0, 0.28 + float(i) * 0.09, hd + 0.014),
			[Color("#ff5c7c"), Color("#feae34"), Color("#4fa4ff")][i], 1.1,
			Vector3(0, 0, 6.0 - float(i) * 6.0))
	# a chunky pixel star, built the way the console would draw one
	var star_px := [[0, 3], [-1, 2], [1, 2], [-2, 1], [2, 1], [-1, 1], [0, 1],
		[1, 1], [-3, 0], [-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0], [3, 0],
		[-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [-2, -2], [2, -2],
		[-3, -3], [3, -3]]
	for px in star_px:
		var blk := BoxMesh.new()
		blk.size = Vector3(0.055, 0.055, 0.012)
		part(blk, Vector3(float(px[0]) * 0.055, 0.62 + float(px[1]) * 0.055,
			hd + 0.02), Color("#fee761"), 1.3)
	# neon down both front corners: the thing you see from across a room
	for nx in [-1.0, 1.0]:
		var neon := BoxMesh.new()
		neon.size = Vector3(0.02, 1.5, 0.02)
		part(neon, Vector3(nx * (hw - 0.015), 1.0, hd + 0.015),
			Color("#26c2cd") if nx < 0.0 else Color("#e14bd6"), 2.6)
	# --- coin door, return cup, and the floppy slot beside it
	var door := BoxMesh.new()
	door.size = Vector3(0.32, 0.22, 0.035)
	part(door, Vector3(0, 0.16, hd + 0.005), Color("#3a3446"), 0.1)
	var slot := BoxMesh.new()
	slot.size = Vector3(0.03, 0.08, 0.02)
	part(slot, Vector3(-0.07, 0.2, hd + 0.022), Color("#08080c"), 0.02)
	var cup := BoxMesh.new()
	cup.size = Vector3(0.14, 0.06, 0.03)
	part(cup, Vector3(0.06, 0.12, hd + 0.022), Color("#08080c"), 0.02)
	var fslot := BoxMesh.new()
	fslot.size = Vector3(0.2, 0.02, 0.03)
	part(fslot, Vector3(0.2, 0.93, hd + 0.005), Color("#08080c"), 0.02)
	var fplate := BoxMesh.new()
	fplate.size = Vector3(0.26, 0.09, 0.015)
	part(fplate, Vector3(0.2, 0.93, hd), Color("#2a2735"), 0.1)
	var bled := SphereMesh.new()
	bled.radius = 0.014
	bled.height = 0.028
	_board_lamp = part(bled, Vector3(-0.3, 0.86, hd + 0.01), Color("#2a2a30"), 0.2)
	var fled := SphereMesh.new()
	fled.radius = 0.012
	fled.height = 0.024
	part(fled, Vector3(0.34, 0.93, hd + 0.012), Color("#3aff6a"), 2.0)
	# --- speaker grilles under the marquee
	for i in 12:
		var hole := CylinderMesh.new()
		hole.top_radius = 0.012
		hole.bottom_radius = 0.012
		hole.height = 0.01
		part(hole, Vector3(-0.3 + float(i % 6) * 0.12, 1.76 + float(i / 6) * 0.04,
			hd - 0.16), Color("#0a0a10"), 0.02, Vector3(90, 0, 0))
	# --- kick plate and feet
	var kick := BoxMesh.new()
	kick.size = Vector3(CAB_W - 0.04, 0.14, 0.03)
	part(kick, Vector3(0, 0.09, hd), Color("#f2f2f7"), 0.25)
	for fx in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			var foot := CylinderMesh.new()
			foot.top_radius = 0.03
			foot.bottom_radius = 0.035
			foot.height = 0.05
			part(foot, Vector3(fx * (hw - 0.06), 0.025, fz * (hd - 0.06)),
				Color("#0d0c12"), 0.05)

# ================================================================= life

## Only ONE cabinet in the world animates at a time -- the one you are
## nearest. Every other screen holds its last frame. A room full of
## cabinets therefore costs what a single cabinet costs, which is the
## whole reason this check exists.
static var _live: ArcadeMachine = null
static var _live_d: float = 1e9
static var _live_frame: int = -1

func _process(delta: float) -> void:
	if _open:
		return                        # the player is inside it; UI drives
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var d := global_position.distance_to(p.global_position)
	if d > 22.0:
		return                        # too far to read: screen holds still
	# claim the "live screen" slot for this frame if we are the closest
	var fr := Engine.get_process_frames()
	if fr != _live_frame:
		_live_frame = fr
		_live = self
		_live_d = d
	elif d < _live_d:
		_live = self
		_live_d = d
	if _live != self:
		return
	_attract_t += delta
	# 18fps up close, 6fps across the room. An attract loop does not need
	# sixty, and a game playing itself still reads at eighteen.
	var tick := 1.0 / (18.0 if d < 9.0 else 6.0)
	if _attract_t < tick:
		return
	var step := _attract_t
	_attract_t = 0.0
	shell.attract_step(step)
	shell.draw()
	_push_screen()
	if _marquee:
		var m := _marquee.material_override as StandardMaterial3D
		if m:
			m.emission_energy_multiplier = 1.3 + sin(Time.get_ticks_msec() * 0.002) * 0.25

func _push_screen() -> void:
	_up(_tex_bg, con.bg)
	_up(_tex_main, con.main)
	_up(_tex_ui, con.ui)
	var pal := con.palette_image()
	if _tex_pal.get_width() != 256:
		_tex_pal.set_image(pal)
	else:
		_tex_pal.update(pal)
	_screen_mat.set_shader_parameter("bg_tex", _tex_bg)
	_screen_mat.set_shader_parameter("main_tex", _tex_main)
	_screen_mat.set_shader_parameter("ui_tex", _tex_ui)
	_screen_mat.set_shader_parameter("pal_tex", _tex_pal)
	_screen_mat.set_shader_parameter("ui_size", Vector2(Pixel.UI_W, Pixel.UI_H))
	_screen_mat.set_shader_parameter("game_size", Vector2(con.game_w, con.game_h))

func _up(tex: ImageTexture, layer_obj) -> void:
	var img: Image = layer_obj.to_image()
	if tex.get_width() != img.get_width() or tex.get_height() != img.get_height():
		tex.set_image(img)
	else:
		tex.update(img)

## F: sit down at it. The console keeps whatever state the attract loop
## left it in -- you are looking at the same machine, closer.
func use() -> void:
	var held := Inventory.slot_id(Inventory.selected)
	if held == "arcboard" or held == "arcsmooth":
		var kind := "expand" if held == "arcboard" else "smooth"
		var hud = get_tree().get_first_node_in_group("hud")
		if install_board(kind):
			Inventory.remove_res(held, 1)
			if hud:
				hud.flash("board fitted: " + ("expansion -- BIG canvas, eight voices, modulators"
					if kind == "expand" else "smooth motion -- free positioning unlocked"))
		elif hud:
			hud.flash("that board is already in this cabinet")
		return
	if _open:
		return
	_open = true
	shell.take_over()
	var ui := ArcadeUI.new()
	ui.con = con
	ui.shell = shell
	ui.machine = self
	shell.quit_requested = false
	get_tree().current_scene.add_child(ui)
	Sfx.play("click")

## Everything about this cabinet that must survive a rejoin.
func save_data() -> Dictionary:
	var carts: Array = []
	for c in user_carts:
		carts.append((c as ArcadeCart).to_dict())
	return {"boards": boards.duplicate(), "carts": carts,
		"floppy": floppy_in.duplicate(true), "sel": shell.sel if shell else 0}

var _pending: Dictionary = {}

## Restore runs BEFORE the node enters the tree, so this may arrive
## while there is no console to hand it to yet. Stash it and apply it the
## moment _ready has built one.
func load_data(d: Dictionary) -> void:
	if shell == null or con == null:
		_pending = d.duplicate(true)
		return
	_apply_data(d)

func _apply_data(d: Dictionary) -> void:
	var b = d.get("boards", {})
	if b is Dictionary:
		boards["expand"] = bool(b.get("expand", false))
		boards["smooth"] = bool(b.get("smooth", false))
	user_carts = []
	for cd in (d.get("carts", []) as Array):
		if cd is Dictionary:
			user_carts.append(ArcadeCart.from_dict(cd))
	var f = d.get("floppy", {})
	floppy_in = (f as Dictionary).duplicate(true) if f is Dictionary else {}
	_apply_boards()
	_refresh_shelf()
	if shell:
		shell.sel = clampi(int(d.get("sel", 0)), 0, maxi(0, shell.carts.size() - 1))

func on_ui_closed() -> void:
	_open = false
	_push_screen()

## The shelf is the ROMs plus whatever has been written on this machine.
func _refresh_shelf() -> void:
	var out: Array = []
	out.append_array(ArcadeCarts.shelf())
	out.append_array(user_carts)
	shell.carts = out
	shell.sel = clampi(shell.sel, 0, maxi(0, out.size() - 1))

## Start a new cartridge on this cabinet and open it in the workshop.
func new_cart() -> ArcadeCart:
	var c := ArcadeCart.blank("CART %d" % (user_carts.size() + 1))
	user_carts.append(c)
	_refresh_shelf()
	return c

## A cartridge read off a floppy joins this machine's own shelf.
func adopt_cart(c: ArcadeCart) -> void:
	c.readonly = false
	user_carts.append(c)
	_refresh_shelf()

## Push what is fitted through to the console and the sound chip.
func _apply_boards() -> void:
	if con != null:
		con.caps = {"expand": bool(boards.get("expand", false)),
			"smooth": bool(boards.get("smooth", false))}
	if sound != null:
		sound.expanded = bool(boards.get("expand", false))
	if _board_lamp != null:
		var m := _board_lamp.material_override as StandardMaterial3D
		if m:
			m.albedo_color = Color("#3aff6a") if boards.get("expand", false) \
				else Color("#2a2a30")
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 2.0 if boards.get("expand", false) else 0.2

func install_board(kind: String) -> bool:
	if bool(boards.get(kind, false)):
		return false
	boards[kind] = true
	_apply_boards()
	Sfx.play("coin", -8.0)
	return true

func info_text() -> String:
	var fitted: Array = []
	if boards.get("expand", false):
		fitted.append("expansion")
	if boards.get("smooth", false):
		fitted.append("smooth motion")
	return "A DUDE-16 cabinet. No power lead, no coin needed.\n" \
		+ "F to play. Games live on the shelf inside; floppies go in the slot.\n" \
		+ ("boards fitted: " + ", ".join(fitted) if not fitted.is_empty()
			else "stock machine -- no boards fitted") \
		+ "\n(hold a board and press F to fit it)"

func can_wire() -> bool:
	return false
