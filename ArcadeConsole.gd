class_name ArcadeConsole
extends RefCounted
## THE DUDE-16 ITSELF. Owns the three drawing layers, the palette, the
## Lua machine a cartridge runs on, and the loop that ties them together.
##
## Layers, bottom to top:
##   BG    -- game resolution, scrolls independently (parallax, static art)
##   MAIN  -- game resolution, cleared and repainted by _draw every frame
##   UI    -- console resolution, ALWAYS 480x270: menus, editors, chrome
## The three are composited on the GPU by one shader that looks every
## byte up in the palette, so the console UI never changes size when a
## cartridge changes resolution, and a full-screen fade costs nothing.

## The game canvas has four settings. The console's own UI never moves,
## whichever one is picked. The last two need boards in the back of the
## cabinet -- a stock machine will not run them.
const RES_MODES := [
	{"name": "SMALL", "w": 320, "h": 180, "desc": "chunkier pixels, less room",
		"needs": ""},
	{"name": "NORMAL", "w": 480, "h": 270, "desc": "the house resolution",
		"needs": ""},
	{"name": "BIG", "w": 640, "h": 360, "desc": "finer pixels, more room",
		"needs": "expand"},
	{"name": "FREE MOTION", "w": 960, "h": 540,
		"desc": "double density: motion stops landing on whole screen pixels",
		"needs": "smooth"},
]

## What is fitted to this cabinet. The shell and the tracker read these
## before they offer anything the machine cannot do.
var caps := {"expand": false, "smooth": false}

func can(what: String) -> bool:
	return bool(caps.get(what, false))

## The highest canvas this cabinet is allowed to run.
func allowed_res(mode: int) -> int:
	var m := clampi(mode, 0, RES_MODES.size() - 1)
	while m > 0 and str(RES_MODES[m]["needs"]) != "" \
			and not can(str(RES_MODES[m]["needs"])):
		m -= 1
	return m

# buttons, in the order btn() sees them
const B_LEFT := 0
const B_RIGHT := 1
const B_UP := 2
const B_DOWN := 3
const B_A := 4
const B_B := 5
const B_X := 6
const B_Y := 7
const B_START := 8
const B_SELECT := 9
const BTN_COUNT := 10

var cart: ArcadeCart = null
var vm: LuaVM = null

var bg: Pixel.Layer = null
var main: Pixel.Layer = null
var ui: Pixel.Layer = null

var game_w: int = 480
var game_h: int = 270

var frame: int = 0
var run_time: float = 0.0
var running: bool = false
var crashed: bool = false
var crash_msg: String = ""
var log_lines: Array = []

## Buttons currently held, and the ones that went down this frame.
var btn_held: Array = []
var btn_hit: Array = []
var btn_prev: Array = []
var mouse_x: int = 0
var mouse_y: int = 0
var mouse_down: bool = false
var mouse_hit: bool = false
## Right button, tracked separately: in the editors it erases.
var mouse_right: bool = false
var mouse_right_hit: bool = false
var key_hits: Dictionary = {}          # keycode -> true, one frame
var key_held: Dictionary = {}
var text_typed: String = ""            # unicode typed this frame

## Wired up by the shell so cartridges can make noise.
var sound = null

var _pal_remap := PackedByteArray()
var _bg_scroll := Vector2i.ZERO
var _cur_font: int = PixelFont.SYS
var _target = null                     # the layer cartridge draws into

func _init() -> void:
	btn_held.resize(BTN_COUNT)
	btn_hit.resize(BTN_COUNT)
	btn_prev.resize(BTN_COUNT)
	for i in BTN_COUNT:
		btn_held[i] = false
		btn_hit[i] = false
		btn_prev[i] = false
	ui = Pixel.Layer.new(Pixel.UI_W, Pixel.UI_H, Pixel.CLEAR)
	_set_res(1)
	_pal_remap.resize(256)
	for i in 256:
		_pal_remap[i] = i

func _set_res(mode: int) -> void:
	var m: Dictionary = RES_MODES[allowed_res(mode)]
	game_w = int(m["w"])
	game_h = int(m["h"])
	if bg == null:
		bg = Pixel.Layer.new(game_w, game_h, Pixel.CLEAR)
		main = Pixel.Layer.new(game_w, game_h, Pixel.CLEAR)
	else:
		bg.resize(game_w, game_h)
		main.resize(game_w, game_h)
	_target = main

func res_mode_name() -> String:
	for i in RES_MODES.size():
		if int(RES_MODES[i]["w"]) == game_w:
			return str(RES_MODES[i]["name"])
	return "?"

# =============================================================== running

## Load a cartridge and run its _init. Any error comes back as a crash
## screen, never as a broken game.
func boot(c: ArcadeCart) -> void:
	cart = c
	frame = 0
	run_time = 0.0
	crashed = false
	crash_msg = ""
	log_lines = []
	_set_res(c.res_mode)
	bg.clear(Pixel.CLEAR)
	main.clear(Pixel.BLACK)
	main.clip_reset()
	main.camera(0, 0)
	main.reset_pal()
	vm = LuaVM.new()
	vm.open_libs()
	_bind_api()
	vm.budget = 6000000
	if not vm.load_src(c.code):
		_crash(vm.err)
		return
	if not vm.exec_chunk():
		_crash(vm.err)
		return
	if vm.has_fn("_init"):
		vm.call_global("_init")
		if vm.err != "":
			_crash(vm.err)
			return
	running = true

func stop() -> void:
	running = false

func _crash(msg: String) -> void:
	crashed = true
	running = false
	crash_msg = msg
	log_lines.append("!! " + msg)

## Edge-detect the buttons for THIS frame. Called once a frame by
## whatever is driving the console -- the shell needs presses in its
## menus just as much as a cartridge needs them in a game, and this used
## to happen inside step(), which only runs while a game is running.
## That is why nothing in the menus responded.
func poll_buttons() -> void:
	for i in BTN_COUNT:
		btn_hit[i] = btn_held[i] and not btn_prev[i]
		btn_prev[i] = btn_held[i]

## Clear the one-frame input latches. The driver calls this after
## everything that wanted to read them has read them.
func end_frame() -> void:
	mouse_hit = false
	mouse_right_hit = false
	key_hits.clear()
	text_typed = ""

## One frame of the cartridge: _update then _draw, both fenced.
func step(delta: float) -> void:
	if not running or crashed or vm == null:
		return
	run_time += delta
	frame += 1
	vm.steps = 0
	if vm.has_fn("_update"):
		vm.call_global("_update")
		if vm.err != "":
			_crash(vm.err)
			return
	if vm.has_fn("_draw"):
		vm.steps = 0
		_target = main
		vm.call_global("_draw")
		if vm.err != "":
			_crash(vm.err)
			return

# ============================================================ the api
## Everything below is what a cartridge can call. The names are short on
## purpose -- this is a console, not an application framework.

func _bind_api() -> void:
	var g := vm.G
	# --- drawing
	g.rawset("cls", Callable(self, "_api_cls"))
	g.rawset("pset", Callable(self, "_api_pset"))
	g.rawset("pget", Callable(self, "_api_pget"))
	g.rawset("line", Callable(self, "_api_line"))
	g.rawset("rect", Callable(self, "_api_rect"))
	g.rawset("rectfill", Callable(self, "_api_rectfill"))
	g.rawset("circ", Callable(self, "_api_circ"))
	g.rawset("circfill", Callable(self, "_api_circfill"))
	g.rawset("tri", Callable(self, "_api_tri"))
	g.rawset("spr", Callable(self, "_api_spr"))
	g.rawset("sspr", Callable(self, "_api_sspr"))
	g.rawset("map", Callable(self, "_api_map"))
	g.rawset("mget", Callable(self, "_api_mget"))
	g.rawset("mset", Callable(self, "_api_mset"))
	g.rawset("fget", Callable(self, "_api_fget"))
	g.rawset("fset", Callable(self, "_api_fset"))
	g.rawset("print", Callable(self, "_api_print"))
	g.rawset("printc", Callable(self, "_api_printc"))
	g.rawset("textw", Callable(self, "_api_textw"))
	g.rawset("font", Callable(self, "_api_font"))
	g.rawset("camera", Callable(self, "_api_camera"))
	g.rawset("clip", Callable(self, "_api_clip"))
	g.rawset("pal", Callable(self, "_api_pal"))
	g.rawset("palt", Callable(self, "_api_palt"))
	g.rawset("fade", Callable(self, "_api_fade"))
	g.rawset("layer", Callable(self, "_api_layer"))
	g.rawset("bgscroll", Callable(self, "_api_bgscroll"))
	g.rawset("res", Callable(self, "_api_res"))
	# --- input
	g.rawset("btn", Callable(self, "_api_btn"))
	g.rawset("btnp", Callable(self, "_api_btnp"))
	g.rawset("mouse", Callable(self, "_api_mouse"))
	g.rawset("key", Callable(self, "_api_key"))
	# --- time and numbers
	g.rawset("t", Callable(self, "_api_t"))
	g.rawset("frames", Callable(self, "_api_frames"))
	g.rawset("rnd", Callable(self, "_api_rnd"))
	g.rawset("flr", Callable(self, "_api_flr"))
	g.rawset("ceil", Callable(self, "_api_ceil"))
	g.rawset("abs", Callable(self, "_api_abs"))
	g.rawset("min", Callable(self, "_api_min"))
	g.rawset("max", Callable(self, "_api_max"))
	g.rawset("mid", Callable(self, "_api_mid"))
	g.rawset("sgn", Callable(self, "_api_sgn"))
	g.rawset("sqrt", Callable(self, "_api_sqrt"))
	g.rawset("sin", Callable(self, "_api_sin"))
	g.rawset("cos", Callable(self, "_api_cos"))
	g.rawset("atan2", Callable(self, "_api_atan2"))
	# --- sound
	g.rawset("sfx", Callable(self, "_api_sfx"))
	g.rawset("music", Callable(self, "_api_music"))
	g.rawset("note", Callable(self, "_api_note"))
	# --- memory that survives the power going off
	g.rawset("dget", Callable(self, "_api_dget"))
	g.rawset("dset", Callable(self, "_api_dset"))
	g.rawset("log", Callable(self, "_api_log"))

func _n(a: Array, i: int, d: float = 0.0) -> float:
	if i >= a.size():
		return d
	var v = LuaVM._tonum(a[i])
	return float(v) if v != null else d

func _i(a: Array, i: int, d: int = 0) -> int:
	return int(_n(a, i, float(d)))

func _b(a: Array, i: int) -> bool:
	return i < a.size() and LuaVM._truthy(a[i])

# --- drawing -----------------------------------------------------------
func _api_cls(a: Array) -> Array:
	_target.clear(_i(a, 0, Pixel.BLACK))
	_target.camera(0, 0)
	return []

func _api_pset(a: Array) -> Array:
	_target.pset(_i(a, 0), _i(a, 1), _i(a, 2, 1))
	return []

func _api_pget(a: Array) -> Array:
	return [float(_target.pget(_i(a, 0), _i(a, 1)))]

func _api_line(a: Array) -> Array:
	_target.line(_i(a, 0), _i(a, 1), _i(a, 2), _i(a, 3), _i(a, 4, 1))
	return []

func _api_rect(a: Array) -> Array:
	_target.rect(_i(a, 0), _i(a, 1), _i(a, 2), _i(a, 3), _i(a, 4, 1))
	return []

func _api_rectfill(a: Array) -> Array:
	_target.rectfill(_i(a, 0), _i(a, 1), _i(a, 2), _i(a, 3), _i(a, 4, 1))
	return []

func _api_circ(a: Array) -> Array:
	_target.circ(_i(a, 0), _i(a, 1), _i(a, 2, 1), _i(a, 3, 1))
	return []

func _api_circfill(a: Array) -> Array:
	_target.circfill(_i(a, 0), _i(a, 1), _i(a, 2, 1), _i(a, 3, 1))
	return []

func _api_tri(a: Array) -> Array:
	_target.trifill(_i(a, 0), _i(a, 1), _i(a, 2), _i(a, 3), _i(a, 4), _i(a, 5),
		_i(a, 6, 1))
	return []

## spr(n, x, y, [w, h, flipx, flipy, scale]) -- w/h count SPRITES, so
## spr(0, x, y, 2, 2) draws a 32x32 block starting at sprite 0.
func _api_spr(a: Array) -> Array:
	if cart == null:
		return []
	var n := _i(a, 0)
	var sw := maxi(1, _i(a, 3, 1))
	var sh := maxi(1, _i(a, 4, 1))
	var scale := maxi(1, _i(a, 7, 1))
	var sx := ArcadeCart.spr_x(n)
	var sy := ArcadeCart.spr_y(n)
	if scale > 1:
		_target.blit_scaled(cart.sheet, ArcadeCart.SHEET_W, sx, sy,
			sw * ArcadeCart.SPR, sh * ArcadeCart.SPR, _i(a, 1), _i(a, 2),
			scale, _b(a, 5), _b(a, 6))
	else:
		_target.blit(cart.sheet, ArcadeCart.SHEET_W, sx, sy,
			sw * ArcadeCart.SPR, sh * ArcadeCart.SPR, _i(a, 1), _i(a, 2),
			_b(a, 5), _b(a, 6))
	return []

## sspr(sx, sy, sw, sh, dx, dy, [scale, flipx, flipy]) -- any rectangle
## of the sheet, not just sprite-aligned.
func _api_sspr(a: Array) -> Array:
	if cart == null:
		return []
	var scale := maxi(1, _i(a, 6, 1))
	if scale > 1:
		_target.blit_scaled(cart.sheet, ArcadeCart.SHEET_W, _i(a, 0), _i(a, 1),
			_i(a, 2, 16), _i(a, 3, 16), _i(a, 4), _i(a, 5), scale,
			_b(a, 7), _b(a, 8))
	else:
		_target.blit(cart.sheet, ArcadeCart.SHEET_W, _i(a, 0), _i(a, 1),
			_i(a, 2, 16), _i(a, 3, 16), _i(a, 4), _i(a, 5), _b(a, 7), _b(a, 8))
	return []

## map(cell_x, cell_y, screen_x, screen_y, cols, rows, [layer_flag])
func _api_map(a: Array) -> Array:
	if cart == null:
		return []
	var cx := _i(a, 0)
	var cy := _i(a, 1)
	var sx := _i(a, 2)
	var sy := _i(a, 3)
	var cols := _i(a, 4, 16)
	var rows := _i(a, 5, 16)
	var want := _i(a, 6, -1)
	for ty in rows:
		for tx in cols:
			var tile := cart.mget(cx + tx, cy + ty)
			if tile == 0:
				continue
			if want >= 0 and cart.fget(tile, want) == 0:
				continue
			_target.blit(cart.sheet, ArcadeCart.SHEET_W,
				ArcadeCart.spr_x(tile), ArcadeCart.spr_y(tile),
				ArcadeCart.SPR, ArcadeCart.SPR,
				sx + tx * ArcadeCart.SPR, sy + ty * ArcadeCart.SPR)
	return []

func _api_mget(a: Array) -> Array:
	return [float(cart.mget(_i(a, 0), _i(a, 1)))] if cart else [0.0]

func _api_mset(a: Array) -> Array:
	if cart:
		cart.mset(_i(a, 0), _i(a, 1), _i(a, 2))
	return []

func _api_fget(a: Array) -> Array:
	if cart == null:
		return [0.0]
	var bit := _i(a, 1, -1)
	return [float(cart.fget(_i(a, 0), bit))]

func _api_fset(a: Array) -> Array:
	if cart:
		cart.fset(_i(a, 0), _i(a, 1, -1), _b(a, 2))
	return []

## print(text, x, y, [col, face, style, style_col]) -- faces are the
## console's own: 0 SYS, 1 BOLD, 2 WIDE, 3 TALL, 4 SLANT, 5 HUGE.
func _api_print(a: Array) -> Array:
	var txt := LuaVM.tostr(a[0]) if a.size() > 0 else ""
	var face := _i(a, 4, _cur_font)
	PixelFont.draw(_target, txt, _i(a, 1), _i(a, 2), _i(a, 3, 1), face,
		_i(a, 5, PixelFont.PLAIN), _i(a, 6, Pixel.BLACK))
	return []

func _api_printc(a: Array) -> Array:
	var txt := LuaVM.tostr(a[0]) if a.size() > 0 else ""
	PixelFont.draw_centered(_target, txt, _i(a, 1), _i(a, 2), _i(a, 3, 1),
		_i(a, 4, _cur_font), _i(a, 5, PixelFont.PLAIN), _i(a, 6, Pixel.BLACK))
	return []

func _api_textw(a: Array) -> Array:
	var txt := LuaVM.tostr(a[0]) if a.size() > 0 else ""
	return [float(PixelFont.text_width(txt, _i(a, 1, _cur_font)))]

func _api_font(a: Array) -> Array:
	_cur_font = clampi(_i(a, 0), 0, PixelFont.NAMES.size() - 1)
	return []

func _api_camera(a: Array) -> Array:
	_target.camera(_i(a, 0), _i(a, 1))
	return []

func _api_clip(a: Array) -> Array:
	if a.is_empty():
		_target.clip_reset()
	else:
		_target.clip(_i(a, 0), _i(a, 1), _i(a, 2, game_w), _i(a, 3, game_h))
	return []

## pal(from, to) swaps a colour for everything drawn afterwards;
## pal() alone puts it back.
func _api_pal(a: Array) -> Array:
	if a.is_empty():
		_target.reset_pal()
		return []
	var f := _i(a, 0) & 0xFF
	var t := _i(a, 1) & 0xFF
	_target.pal_map[f] = t
	return []

func _api_palt(a: Array) -> Array:
	_target.transparent = _i(a, 0, 0) & 0xFF
	return []

## fade(amount, [towards]) -- a whole-screen palette fade, done in the
## palette strip, so it costs nothing per pixel.
func _api_fade(a: Array) -> Array:
	var amt := clampf(_n(a, 0, 0.0), 0.0, 1.0)
	var towards := _i(a, 1, Pixel.BLACK)
	set_fade(amt, towards)
	return []

func _api_layer(a: Array) -> Array:
	var which := _i(a, 0, 1)
	_target = bg if which == 0 else main
	return []

func _api_bgscroll(a: Array) -> Array:
	_bg_scroll = Vector2i(_i(a, 0), _i(a, 1))
	return []

func _api_res(a: Array) -> Array:
	return [float(game_w), float(game_h)]

# --- input -------------------------------------------------------------
func _api_btn(a: Array) -> Array:
	if a.is_empty():
		var mask := 0.0
		for i in BTN_COUNT:
			if btn_held[i]:
				mask += pow(2.0, float(i))
		return [mask]
	var i2 := _i(a, 0)
	return [i2 >= 0 and i2 < BTN_COUNT and btn_held[i2]]

func _api_btnp(a: Array) -> Array:
	var i2 := _i(a, 0)
	return [i2 >= 0 and i2 < BTN_COUNT and btn_hit[i2]]

## The mouse, in the cartridge's own pixels. The console UI is always
## 480x270; a game may not be, and handing it UI coordinates puts the
## pointer somewhere the game never drew.
func _api_mouse(a: Array) -> Array:
	var gx := int(round(float(mouse_x) * float(game_w) / float(Pixel.UI_W)))
	var gy := int(round(float(mouse_y) * float(game_h) / float(Pixel.UI_H)))
	return [float(gx), float(gy), mouse_down, mouse_hit]

func _api_key(a: Array) -> Array:
	var k := LuaVM.tostr(a[0]) if a.size() > 0 else ""
	var code := OS.find_keycode_from_string(k.to_upper())
	if _b(a, 1):
		return [key_hits.has(code)]
	return [key_held.has(code)]

# --- numbers and time --------------------------------------------------
func _api_t(_a: Array) -> Array: return [run_time]
func _api_frames(_a: Array) -> Array: return [float(frame)]
func _api_flr(a: Array) -> Array: return [floorf(_n(a, 0))]
func _api_ceil(a: Array) -> Array: return [ceilf(_n(a, 0))]
func _api_abs(a: Array) -> Array: return [absf(_n(a, 0))]
func _api_sqrt(a: Array) -> Array: return [sqrt(maxf(0.0, _n(a, 0)))]
func _api_sin(a: Array) -> Array: return [sin(_n(a, 0))]
func _api_cos(a: Array) -> Array: return [cos(_n(a, 0))]
func _api_atan2(a: Array) -> Array: return [atan2(_n(a, 0), _n(a, 1))]
func _api_sgn(a: Array) -> Array: return [signf(_n(a, 0))]

func _api_min(a: Array) -> Array: return [minf(_n(a, 0), _n(a, 1))]
func _api_max(a: Array) -> Array: return [maxf(_n(a, 0), _n(a, 1))]

func _api_mid(a: Array) -> Array:
	var v := [_n(a, 0), _n(a, 1), _n(a, 2)]
	v.sort()
	return [v[1]]

var _rng := RandomNumberGenerator.new()

func _api_rnd(a: Array) -> Array:
	if a.is_empty():
		return [_rng.randf()]
	return [_rng.randf() * _n(a, 0, 1.0)]

# --- sound -------------------------------------------------------------
func _api_sfx(a: Array) -> Array:
	if sound != null and sound.has_method("play_sfx"):
		sound.play_sfx(_i(a, 0), _i(a, 1, -1))
	return []

func _api_music(a: Array) -> Array:
	if sound != null and sound.has_method("play_music"):
		sound.play_music(_i(a, 0, 0), _n(a, 1, 0.0))
	return []

## note(channel, semitone, volume, [instrument]) -- live, one note, for
## cartridges that would rather drive the sound chip themselves.
func _api_note(a: Array) -> Array:
	if sound != null and sound.has_method("play_note"):
		sound.play_note(_i(a, 0), _n(a, 1, 24.0), _n(a, 2, 1.0), _i(a, 3, 0))
	return []

# --- cart memory -------------------------------------------------------
func _api_dget(a: Array) -> Array:
	if cart == null:
		return [0.0]
	return [float(cart.data.get(str(_i(a, 0)), 0.0))]

func _api_dset(a: Array) -> Array:
	if cart != null:
		cart.data[str(_i(a, 0))] = _n(a, 1)
	return []

func _api_log(a: Array) -> Array:
	var parts: Array = []
	for v in a:
		parts.append(LuaVM.tostr(v))
	log_lines.append(" ".join(parts))
	if log_lines.size() > 200:
		log_lines = log_lines.slice(log_lines.size() - 200)
	return []

# ============================================================ presenting

## The palette strip, with any fade already folded in.
func palette_image() -> Image:
	return Pixel.palette_image(_pal_remap)

## Fold a fade into the palette: every colour moves `amt` of the way
## towards `towards`, and the strip is rebuilt. Pixels never move.
func set_fade(amt: float, towards: int = Pixel.BLACK) -> void:
	var cols := Pixel.colors()
	if amt <= 0.001:
		for i in 256:
			_pal_remap[i] = i
		return
	var dst: Color = cols[clampi(towards, 0, cols.size() - 1)]
	for i in 256:
		if i >= cols.size():
			_pal_remap[i] = i
			continue
		var c: Color = cols[i]
		var want := c.lerp(dst, amt)
		# nearest entry in the palette to the faded colour
		var best := i
		var bd := 999.0
		for j in cols.size():
			var o: Color = cols[j]
			var d := absf(o.r - want.r) + absf(o.g - want.g) + absf(o.b - want.b)
			if d < bd:
				bd = d
				best = j
		_pal_remap[i] = best

func bg_scroll() -> Vector2i:
	return _bg_scroll
