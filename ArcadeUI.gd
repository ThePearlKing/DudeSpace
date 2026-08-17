class_name ArcadeUI
extends CanvasLayer
## THE CABINET, FULL SCREEN. Uploads the console's three index layers as
## R8 textures and lets one shader look every byte up in the palette --
## which is why a palette fade or a scrolling background costs the CPU
## nothing, and why nothing on screen can drift off the pixel grid.
##
## The picture is drawn at an INTEGER scale and centred, so one console
## pixel is always an exact square block of screen pixels. No smoothing,
## no half pixels, no bilinear anything.

var con: ArcadeConsole = null
var shell: ArcadeShell = null
var machine = null

var _rect: ColorRect
var _mat: ShaderMaterial
var _tex_bg := ImageTexture.new()
var _tex_main := ImageTexture.new()
var _tex_ui := ImageTexture.new()
var _tex_pal := ImageTexture.new()
var _last_pal_hash: int = -1
var _scale: int = 1
var _origin := Vector2i.ZERO

const SHADER := """
shader_type canvas_item;
// Three indexed layers and one palette strip. Every colour on screen is
// a byte that lands in pal_tex; nothing here interpolates.
uniform sampler2D bg_tex : filter_nearest, repeat_enable;
uniform sampler2D main_tex : filter_nearest, repeat_enable;
uniform sampler2D ui_tex : filter_nearest, repeat_enable;
uniform sampler2D pal_tex : filter_nearest, repeat_enable;
uniform vec2 ui_size = vec2(480.0, 270.0);
uniform vec2 game_size = vec2(480.0, 270.0);
uniform vec2 bg_off = vec2(0.0, 0.0);
uniform float scan : hint_range(0.0, 1.0) = 0.35;
uniform float glow : hint_range(0.0, 1.0) = 0.25;

vec4 look(sampler2D t, vec2 uv, vec2 size) {
	// wrap, so a scrolled background tiles instead of running off the
	// edge of its own texture and going black
	// wrap, so a scrolled background tiles instead of running off its
	// own texture; the other layers never sample outside 0..1 anyway
	vec2 p = (floor(fract(uv) * size) + 0.5) / size;
	float idx = floor(texture(t, p).r * 255.0 + 0.5);
	return texture(pal_tex, vec2((idx + 0.5) / 256.0, 0.5));
}

void fragment() {
	vec4 c = vec4(0.0, 0.0, 0.0, 1.0);
	vec2 bg_uv = UV + bg_off / game_size;
	vec4 b = look(bg_tex, bg_uv, game_size);
	c = mix(c, vec4(b.rgb, 1.0), b.a);
	vec4 m = look(main_tex, UV, game_size);
	c = mix(c, vec4(m.rgb, 1.0), m.a);
	vec4 u = look(ui_tex, UV, ui_size);
	c = mix(c, vec4(u.rgb, 1.0), u.a);
	// CRT: darken every other GAME line, and bloom the bright bits a
	// little. Both are computed on whole lines, never between them.
	float line = floor(UV.y * game_size.y);
	float dim = 1.0 - scan * 0.30 * mod(line, 2.0);
	c.rgb *= dim;
	float lum = max(c.r, max(c.g, c.b));
	c.rgb += c.rgb * glow * lum * 0.5;
	COLOR = vec4(c.rgb, 1.0);
}
"""

func _ready() -> void:
	layer = 40
	add_to_group("arcade_ui")
	add_to_group("closable_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)

	if con == null:
		con = ArcadeConsole.new()
	if shell == null:
		shell = ArcadeShell.new(con)
	_upload_palette(true)
	_layout()
	get_viewport().size_changed.connect(_layout)

## Integer scale, centred: one console pixel = one square block.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := int(floor(minf(vp.x / float(Pixel.UI_W), vp.y / float(Pixel.UI_H))))
	_scale = maxi(1, s)
	var w := Pixel.UI_W * _scale
	var h := Pixel.UI_H * _scale
	_origin = Vector2i(int((vp.x - float(w)) * 0.5), int((vp.y - float(h)) * 0.5))
	_rect.position = Vector2(_origin)
	_rect.size = Vector2(w, h)

func _process(delta: float) -> void:
	if con == null or shell == null:
		return
	con.mouse_hit = _mouse_hit_latch
	_mouse_hit_latch = false
	shell.update(delta)
	shell.draw()
	_upload()
	if shell.quit_requested:
		close()

func _upload() -> void:
	_update_tex(_tex_bg, con.bg)
	_update_tex(_tex_main, con.main)
	_update_tex(_tex_ui, con.ui)
	_upload_palette(false)
	_mat.set_shader_parameter("bg_tex", _tex_bg)
	_mat.set_shader_parameter("main_tex", _tex_main)
	_mat.set_shader_parameter("ui_tex", _tex_ui)
	_mat.set_shader_parameter("pal_tex", _tex_pal)
	_mat.set_shader_parameter("ui_size", Vector2(Pixel.UI_W, Pixel.UI_H))
	_mat.set_shader_parameter("game_size", Vector2(con.game_w, con.game_h))
	_mat.set_shader_parameter("bg_off", Vector2(con.bg_scroll()))
	_mat.set_shader_parameter("scan", shell.scanline)

func _update_tex(tex: ImageTexture, layer_obj) -> void:
	var img: Image = layer_obj.to_image()
	if tex.get_width() != img.get_width() or tex.get_height() != img.get_height():
		tex.set_image(img)
	else:
		tex.update(img)

func _upload_palette(force: bool) -> void:
	var img := con.palette_image()
	var h := hash(img.get_data())
	if force or h != _last_pal_hash:
		_last_pal_hash = h
		if _tex_pal.get_width() != 256:
			_tex_pal.set_image(img)
		else:
			_tex_pal.update(img)

# =============================================================== input

const KEY_MAP := {
	KEY_LEFT: ArcadeConsole.B_LEFT, KEY_A: ArcadeConsole.B_LEFT,
	KEY_RIGHT: ArcadeConsole.B_RIGHT, KEY_D: ArcadeConsole.B_RIGHT,
	KEY_UP: ArcadeConsole.B_UP, KEY_W: ArcadeConsole.B_UP,
	KEY_DOWN: ArcadeConsole.B_DOWN, KEY_S: ArcadeConsole.B_DOWN,
	KEY_Z: ArcadeConsole.B_A, KEY_J: ArcadeConsole.B_A,
	KEY_X: ArcadeConsole.B_B, KEY_K: ArcadeConsole.B_B,
	KEY_C: ArcadeConsole.B_X, KEY_L: ArcadeConsole.B_X,
	KEY_V: ArcadeConsole.B_Y, KEY_SEMICOLON: ArcadeConsole.B_Y,
	KEY_ENTER: ArcadeConsole.B_START,
	KEY_SHIFT: ArcadeConsole.B_SELECT,
}

var _mouse_hit_latch: bool = false

func _input(event: InputEvent) -> void:
	if con == null:
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		var code := k.keycode
		if k.pressed and not k.echo:
			con.key_hits[code] = true
			con.key_held[code] = true
			if k.unicode >= 32 and k.unicode < 127:
				con.text_typed += char(k.unicode)
		elif not k.pressed:
			con.key_held.erase(code)
		# an editor that is typing must not also be steering a d-pad
		var typing: bool = shell != null and shell.edit != null \
			and shell.state == ArcadeShell.S_EDIT and shell.edit.typing()
		if not typing and KEY_MAP.has(code):
			con.btn_held[int(KEY_MAP[code])] = k.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		var pos: Vector2 = (event as InputEventMouse).position
		var local := (pos - Vector2(_origin)) / float(_scale)
		con.mouse_x = int(floor(local.x))
		con.mouse_y = int(floor(local.y))
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_LEFT:
				con.mouse_down = mb.pressed
				if mb.pressed:
					_mouse_hit_latch = true
			if shell != null and shell.edit != null \
					and shell.state == ArcadeShell.S_EDIT:
				shell.edit.wheel(mb)
			get_viewport().set_input_as_handled()

## Feed the cabinet's gamepad -- the real game's controls, so the player
## does not have to change hands to play a game inside the game.
func _physics_process(_d: float) -> void:
	if con == null:
		return
	var typing: bool = shell != null and shell.edit != null \
		and shell.state == ArcadeShell.S_EDIT and shell.edit.typing()
	if typing:
		return
	con.btn_held[ArcadeConsole.B_LEFT] = con.btn_held[ArcadeConsole.B_LEFT] \
		or Input.is_action_pressed("ui_left")
	con.btn_held[ArcadeConsole.B_RIGHT] = con.btn_held[ArcadeConsole.B_RIGHT] \
		or Input.is_action_pressed("ui_right")
	con.btn_held[ArcadeConsole.B_UP] = con.btn_held[ArcadeConsole.B_UP] \
		or Input.is_action_pressed("ui_up")
	con.btn_held[ArcadeConsole.B_DOWN] = con.btn_held[ArcadeConsole.B_DOWN] \
		or Input.is_action_pressed("ui_down")

func close() -> void:
	if machine != null and is_instance_valid(machine) \
			and machine.has_method("on_ui_closed"):
		machine.on_ui_closed()
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
