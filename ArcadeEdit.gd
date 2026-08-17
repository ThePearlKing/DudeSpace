class_name ArcadeEdit
extends RefCounted
## THE CARTRIDGE WORKSHOP. Code, art, map, sound -- every tab drawn with
## the console's own fonts into the console's own UI layer, which is the
## only way a machine like this stays honest: the editor cannot use a
## pixel the games cannot use.
##
## The chrome animates because a workshop that sits perfectly still
## looks broken: the tab bar slides, the active tab breathes, panels
## arrive from the edge they belong to, and the caret blinks on a beat.

const T_CODE := 0
const T_SPRITE := 1
const T_MAP := 2
const T_SOUND := 3
const T_INFO := 4
const TABS := ["CODE", "SPRITE", "MAP", "SOUND", "CART"]

var con: ArcadeConsole
var shell: ArcadeShell
var cart: ArcadeCart = null
var tab: int = T_CODE
var t: float = 0.0
var _tab_glide: float = 0.0
var _panel_in: float = 0.0

# --- code editor state
var lines: Array = ["-- new cart"]
var cur_l: int = 0
var cur_c: int = 0
var scroll_l: int = 0
var scroll_c: int = 0
var sel_anchor: Vector2i = Vector2i(-1, -1)
var err_line: int = -1
var err_text: String = ""
var _blink: float = 0.0

# --- sprite editor state
var spr_sel: int = 0
var spr_color: int = 1
var spr_zoom: int = 12
var spr_tool: int = 0                  # 0 pencil 1 fill 2 line 3 pick
var _spr_drag: bool = false
var _line_from: Vector2i = Vector2i(-1, -1)
var undo_stack: Array = []

# --- tracker state
var trk_row: int = 0
var trk_ch: int = 0
var trk_col: int = 0            # 0 note, 1 instrument, 2 volume, 3 fx, 4 param
var trk_pat: int = 0
var trk_oct: int = 4
var trk_step: int = 1
var trk_inst: int = 0
var trk_panel: int = 0          # 0 pattern, 1 instrument, 2 song
var trk_ip: int = 0             # selected instrument parameter
var _clip_row: Array = []
var song: ChipSound.Song = null
var sound = null                # the ChipSound node, set by the shell

const NOTE_NAMES := ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#",
	"A-", "A#", "B-"]
## Effect column, tracker-style. The three slide effects are the ones
## that make a melody sing instead of step.
const FX_NAMES := {
	0: "ARP", 1: "SLIDE UP", 2: "SLIDE DOWN", 3: "GLIDE TO NOTE",
	8: "PAN", 10: "VOL SLIDE", 11: "JUMP", 12: "CUT", 13: "BREAK", 15: "SPEED",
}
## The piano, laid over the keyboard the way every tracker does it.
const PIANO := {
	KEY_Z: 0, KEY_S: 1, KEY_X: 2, KEY_D: 3, KEY_C: 4, KEY_V: 5, KEY_G: 6,
	KEY_B: 7, KEY_H: 8, KEY_N: 9, KEY_J: 10, KEY_M: 11,
	KEY_Q: 12, KEY_2: 13, KEY_W: 14, KEY_3: 15, KEY_E: 16, KEY_R: 17,
	KEY_5: 18, KEY_T: 19, KEY_6: 20, KEY_Y: 21, KEY_7: 22, KEY_U: 23,
	KEY_I: 24, KEY_9: 25, KEY_O: 26, KEY_0: 27, KEY_P: 28,
}
## Everything the stock chip cannot do. Visible in the list either way --
## you should be able to see what the board would buy you -- but greyed
## out and refusing to move until one is fitted.
const EXPAND_PARAMS := ["pwm_rate", "pwm_depth", "vib_rate", "vib_depth",
	"vib_delay", "cut", "res", "cut_env", "cut_time", "delay_send", "room_send"]

const INST_PARAMS := [
	["WAVE", "wave", 0.0, 6.0, 1.0],
	["DUTY", "duty", 0.05, 0.95, 0.05],
	["PWM RATE", "pwm_rate", 0.0, 12.0, 0.25],
	["PWM DEPTH", "pwm_depth", 0.0, 0.45, 0.02],
	["ATTACK", "atk", 0.001, 2.0, 0.01],
	["DECAY", "dec", 0.005, 2.0, 0.01],
	["SUSTAIN", "sus", 0.0, 1.0, 0.05],
	["RELEASE", "rel", 0.005, 3.0, 0.02],
	["PITCH ENV", "pitch_env", -48.0, 48.0, 1.0],
	["PITCH TIME", "pitch_time", 0.005, 1.0, 0.005],
	["VIB RATE", "vib_rate", 0.0, 14.0, 0.25],
	["VIB DEPTH", "vib_depth", 0.0, 3.0, 0.05],
	["VIB DELAY", "vib_delay", 0.0, 1.0, 0.02],
	["CUTOFF", "cut", 0.02, 1.0, 0.02],
	["RESONANCE", "res", 0.0, 0.95, 0.05],
	["CUT ENV", "cut_env", -1.0, 1.0, 0.05],
	["CUT TIME", "cut_time", 0.01, 2.0, 0.02],
	["NOISE MIX", "noise_mix", 0.0, 1.0, 0.05],
	["PAN", "pan", -1.0, 1.0, 0.1],
	["VOLUME", "vol", 0.0, 1.2, 0.05],
	["DELAY SEND", "delay_send", 0.0, 1.0, 0.05],
	["ROOM SEND", "room_send", 0.0, 1.0, 0.05],
]

# --- map editor state
var map_cam: Vector2i = Vector2i.ZERO
var map_tile: int = 1
var map_zoom: int = 12

const TOOLS := ["PENCIL", "FILL", "LINE", "PICK"]

func _init(c: ArcadeConsole, s: ArcadeShell) -> void:
	con = c
	shell = s

func open(c: ArcadeCart) -> void:
	cart = c
	song = ChipSound.Song.from_dict(c.song) if not c.song.is_empty() \
		else ChipSound.demo_song()
	lines = c.code.split("\n")
	if lines.is_empty():
		lines = [""]
	cur_l = 0
	cur_c = 0
	scroll_l = 0
	err_line = -1
	err_text = ""
	_panel_in = 0.0
	t = 0.0

func typing() -> bool:
	return tab == T_CODE or tab == T_SOUND

func commit() -> void:
	if cart == null or cart.readonly:
		return
	cart.code = "\n".join(lines)
	if song != null:
		cart.song = song.to_dict()

func wheel(mb: InputEventMouseButton) -> void:
	if not mb.pressed:
		return
	var dir := 0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = -3
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = 3
	if dir == 0:
		return
	match tab:
		T_CODE:
			scroll_l = clampi(scroll_l + dir, 0, maxi(0, lines.size() - 1))
		T_SPRITE:
			spr_sel = clampi(spr_sel + (1 if dir > 0 else -1), 0, 255)
		T_MAP:
			map_zoom = clampi(map_zoom + (1 if dir > 0 else -1), 4, 24)

# ================================================================ update

func update(delta: float) -> void:
	t += delta
	_blink += delta
	_panel_in = minf(1.0, _panel_in + delta * 6.0)
	_tab_glide = lerpf(_tab_glide, float(tab), clampf(delta * 16.0, 0.0, 1.0))
	# tab switching is always available, even mid-type
	if con.key_hits.has(KEY_F1):
		_set_tab(T_CODE)
	if con.key_hits.has(KEY_F2):
		_set_tab(T_SPRITE)
	if con.key_hits.has(KEY_F3):
		_set_tab(T_MAP)
	if con.key_hits.has(KEY_F4):
		_set_tab(T_SOUND)
	if con.key_hits.has(KEY_F5):
		_run()
		return
	if con.key_hits.has(KEY_ESCAPE):
		commit()
		shell.go(ArcadeShell.S_MENU)
		return
	match tab:
		T_CODE: _update_code()
		T_SPRITE: _update_sprite()
		T_MAP: _update_map()
		T_SOUND: _update_sound()
		T_INFO: _update_info()

func _set_tab(n: int) -> void:
	if n == tab:
		return
	commit()
	tab = n
	_panel_in = 0.0
	Sfx.play("click", -20.0)

func _run() -> void:
	commit()
	if cart == null:
		return
	con.boot(cart)
	if con.sound != null and con.sound.has_method("load_cart"):
		con.sound.load_cart(cart)
	shell.go(ArcadeShell.S_CRASH if con.crashed else ArcadeShell.S_RUN)

# --- code --------------------------------------------------------------
func _update_code() -> void:
	var ctrl := con.key_held.has(KEY_CTRL)
	var locked: bool = cart != null and cart.readonly
	for code in con.key_hits.keys():
		match int(code):
			KEY_LEFT:
				if cur_c > 0:
					cur_c -= 1
				elif cur_l > 0:
					cur_l -= 1
					cur_c = str(lines[cur_l]).length()
			KEY_RIGHT:
				if cur_c < str(lines[cur_l]).length():
					cur_c += 1
				elif cur_l < lines.size() - 1:
					cur_l += 1
					cur_c = 0
			KEY_UP:
				cur_l = maxi(0, cur_l - 1)
				cur_c = mini(cur_c, str(lines[cur_l]).length())
			KEY_DOWN:
				cur_l = mini(lines.size() - 1, cur_l + 1)
				cur_c = mini(cur_c, str(lines[cur_l]).length())
			KEY_HOME: cur_c = 0
			KEY_END: cur_c = str(lines[cur_l]).length()
			KEY_PAGEUP: cur_l = maxi(0, cur_l - 20)
			KEY_PAGEDOWN: cur_l = mini(lines.size() - 1, cur_l + 20)
			KEY_BACKSPACE:
				if locked:
					pass
				elif cur_c > 0:
					var s: String = lines[cur_l]
					lines[cur_l] = s.substr(0, cur_c - 1) + s.substr(cur_c)
					cur_c -= 1
				elif cur_l > 0:
					var prev: String = lines[cur_l - 1]
					cur_c = prev.length()
					lines[cur_l - 1] = prev + str(lines[cur_l])
					lines.remove_at(cur_l)
					cur_l -= 1
			KEY_DELETE:
				var s2: String = lines[cur_l]
				if locked:
					pass
				elif cur_c < s2.length():
					lines[cur_l] = s2.substr(0, cur_c) + s2.substr(cur_c + 1)
				elif cur_l < lines.size() - 1:
					lines[cur_l] = s2 + str(lines[cur_l + 1])
					lines.remove_at(cur_l + 1)
			KEY_ENTER, KEY_KP_ENTER:
				if locked:
					pass
				else:
					_newline()
			KEY_TAB:
				if not locked:
					var s4: String = lines[cur_l]
					lines[cur_l] = s4.substr(0, cur_c) + "  " + s4.substr(cur_c)
					cur_c += 2
	if con.text_typed != "" and not ctrl:
		if locked:
			shell.note("this cartridge is a ROM -- copy it to a floppy to edit")
		else:
			var s5: String = lines[cur_l]
			lines[cur_l] = s5.substr(0, cur_c) + con.text_typed + s5.substr(cur_c)
			cur_c += con.text_typed.length()
	_follow_caret()

## Enter: split the line here, carry the indent, and open one more level
## after anything that starts a block.
func _newline() -> void:
	var s3: String = lines[cur_l]
	var head := s3.substr(0, cur_c)
	var tail := s3.substr(cur_c)
	var indent := ""
	for ch in head:
		if ch == " " or ch == "\t":
			indent += ch
		else:
			break
	var trimmed := head.strip_edges()
	if trimmed.ends_with("then") or trimmed.ends_with("do") \
			or trimmed.ends_with("else") or trimmed.begins_with("function") \
			or trimmed.ends_with("{"):
		indent += "  "
	lines[cur_l] = head
	lines.insert(cur_l + 1, indent + tail)
	cur_l += 1
	cur_c = indent.length()

## Keep the caret on screen, in both directions.
func _follow_caret() -> void:
	var rows := _code_rows()
	if cur_l < scroll_l:
		scroll_l = cur_l
	if cur_l >= scroll_l + rows:
		scroll_l = cur_l - rows + 1
	var cols := _code_cols()
	if cur_c < scroll_c:
		scroll_c = cur_c
	if cur_c >= scroll_c + cols:
		scroll_c = cur_c - cols + 1

func _code_rows() -> int:
	return 18

func _code_cols() -> int:
	return 74

# --- sprite ------------------------------------------------------------
func _update_sprite() -> void:
	for code in con.key_hits.keys():
		match int(code):
			KEY_LEFT: spr_sel = maxi(0, spr_sel - 1)
			KEY_RIGHT: spr_sel = mini(255, spr_sel + 1)
			KEY_UP: spr_sel = maxi(0, spr_sel - 16)
			KEY_DOWN: spr_sel = mini(255, spr_sel + 16)
			KEY_1: spr_tool = 0
			KEY_2: spr_tool = 1
			KEY_3: spr_tool = 2
			KEY_4: spr_tool = 3
			KEY_Z:
				if con.key_held.has(KEY_CTRL):
					_undo()
	_sprite_mouse()

func _sprite_canvas_rect() -> Rect2i:
	return Rect2i(14, 44, 16 * spr_zoom, 16 * spr_zoom)

func _sprite_mouse() -> void:
	if cart == null:
		return
	var r := _sprite_canvas_rect()
	var mx := con.mouse_x
	var my := con.mouse_y
	# palette strip click
	var pr := _palette_rect()
	if con.mouse_down and pr.has_point(Vector2i(mx, my)):
		var col := (mx - pr.position.x) / 10
		var row := (my - pr.position.y) / 10
		var idx := row * 8 + col
		if idx >= 0 and idx < Pixel.color_count():
			spr_color = idx
		return
	# sprite picker grid
	var gr := _sheet_rect()
	if con.mouse_down and gr.has_point(Vector2i(mx, my)):
		var gx := (mx - gr.position.x) / 11
		var gy := (my - gr.position.y) / 11
		spr_sel = clampi(gy * 16 + gx, 0, 255)
		return
	if not r.has_point(Vector2i(mx, my)):
		_spr_drag = false
		return
	var px := (mx - r.position.x) / spr_zoom
	var py := (my - r.position.y) / spr_zoom
	if not con.mouse_down:
		if _spr_drag and spr_tool == 2 and _line_from.x >= 0:
			_stroke_line(_line_from, Vector2i(px, py))
			_line_from = Vector2i(-1, -1)
		_spr_drag = false
		return
	if not _spr_drag:
		_push_undo()
		_spr_drag = true
		if spr_tool == 2:
			_line_from = Vector2i(px, py)
	match spr_tool:
		0: _spr_set(px, py, spr_color)
		1:
			if con.mouse_hit:
				_flood(px, py, spr_color)
		2: pass
		3:
			spr_color = _spr_get(px, py)
			_spr_drag = false

func _spr_set(x: int, y: int, col: int) -> void:
	if cart == null or cart.readonly or x < 0 or y < 0 or x > 15 or y > 15:
		return
	var sx := ArcadeCart.spr_x(spr_sel) + x
	var sy := ArcadeCart.spr_y(spr_sel) + y
	cart.sheet[sy * ArcadeCart.SHEET_W + sx] = col

func _spr_get(x: int, y: int) -> int:
	if cart == null:
		return 0
	var sx := ArcadeCart.spr_x(spr_sel) + clampi(x, 0, 15)
	var sy := ArcadeCart.spr_y(spr_sel) + clampi(y, 0, 15)
	return int(cart.sheet[sy * ArcadeCart.SHEET_W + sx])

func _stroke_line(a: Vector2i, b: Vector2i) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var e := dx + dy
	var x := a.x
	var y := a.y
	while true:
		_spr_set(x, y, spr_color)
		if x == b.x and y == b.y:
			break
		var e2 := e * 2
		if e2 >= dy:
			e += dy
			x += sx
		if e2 <= dx:
			e += dx
			y += sy

func _flood(x: int, y: int, col: int) -> void:
	var target := _spr_get(x, y)
	if target == col:
		return
	var stack: Array = [Vector2i(x, y)]
	var seen := {}
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x > 15 or p.y > 15:
			continue
		if seen.has(p):
			continue
		seen[p] = true
		if _spr_get(p.x, p.y) != target:
			continue
		_spr_set(p.x, p.y, col)
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))

func _push_undo() -> void:
	if cart == null:
		return
	undo_stack.append(cart.sheet.duplicate())
	if undo_stack.size() > 24:
		undo_stack.pop_front()

func _undo() -> void:
	if cart == null or undo_stack.is_empty():
		return
	cart.sheet = undo_stack.pop_back()
	shell.note("undo")

# --- map ---------------------------------------------------------------
func _update_map() -> void:
	var sp := 1
	if con.key_held.has(KEY_SHIFT):
		sp = 4
	if con.btn_held[ArcadeConsole.B_LEFT] or con.key_held.has(KEY_LEFT):
		map_cam.x = maxi(0, map_cam.x - sp)
	if con.btn_held[ArcadeConsole.B_RIGHT] or con.key_held.has(KEY_RIGHT):
		map_cam.x = mini(ArcadeCart.MAP_W - 8, map_cam.x + sp)
	if con.btn_held[ArcadeConsole.B_UP] or con.key_held.has(KEY_UP):
		map_cam.y = maxi(0, map_cam.y - sp)
	if con.btn_held[ArcadeConsole.B_DOWN] or con.key_held.has(KEY_DOWN):
		map_cam.y = mini(ArcadeCart.MAP_H - 8, map_cam.y + sp)
	if cart == null or cart.readonly:
		return
	var r := _map_rect()
	var mp := Vector2i(con.mouse_x, con.mouse_y)
	if con.mouse_down and r.has_point(mp):
		var tx := map_cam.x + (mp.x - r.position.x) / map_zoom
		var ty := map_cam.y + (mp.y - r.position.y) / map_zoom
		cart.mset(tx, ty, map_tile)
	var gr := _sheet_rect()
	if con.mouse_down and gr.has_point(mp):
		map_tile = clampi(((mp.y - gr.position.y) / 11) * 16
			+ (mp.x - gr.position.x) / 11, 0, 255)

func _update_info() -> void:
	pass

# ================================================================== draw

func draw(u) -> void:
	u.clear(Pixel.dark(22))
	_draw_frame(u)
	match tab:
		T_CODE: _draw_code(u)
		T_SPRITE: _draw_sprite(u)
		T_MAP: _draw_map(u)
		T_SOUND: _draw_sound(u)
		T_INFO: _draw_info(u)
	_draw_status(u)

## Tab bar: a sliding lit block behind the active tab, and a scanning
## highlight that runs along the bar so it never reads as a static strip.
func _draw_frame(u) -> void:
	u.rectfill(0, 0, Pixel.UI_W, 22, Pixel.BLACK)
	var tab_w := 60
	var glide := int(round(_tab_glide * float(tab_w)))
	u.rectfill(8 + glide, 2, 8 + glide + tab_w - 4, 19, Pixel.dark(11))
	u.hline(8 + glide, 8 + glide + tab_w - 4, 20, Pixel.hue(4))
	for i in TABS.size():
		var x := 8 + i * tab_w
		var on := i == tab
		PixelFont.draw(u, str(TABS[i]), x + 8, 7,
			Pixel.WHITE if on else Pixel.hue(23),
			PixelFont.BOLD if on else PixelFont.SYS)
		PixelFont.draw(u, "F%d" % (i + 1), x + 8, 15, Pixel.dark(23))
	# running highlight
	var sweep := int(fmod(t * 90.0, float(Pixel.UI_W)))
	u.hline(sweep, sweep + 24, 21, Pixel.hue(9))
	u.hline(0, Pixel.UI_W, 22, Pixel.dark(9))
	# cart name, right side
	if cart != null:
		var nm := cart.name + ("  [ROM]" if cart.readonly else "")
		PixelFont.draw(u, nm, Pixel.UI_W - PixelFont.text_width(nm) - 8, 8,
			Pixel.light(4))

func _draw_status(u) -> void:
	u.rectfill(0, Pixel.UI_H - 14, Pixel.UI_W, Pixel.UI_H, Pixel.BLACK)
	u.hline(0, Pixel.UI_W, Pixel.UI_H - 15, Pixel.dark(9))
	var hint := ""
	match tab:
		T_CODE:
			hint = "F5 RUN   ESC SHELF   ln %d/%d  col %d" % [cur_l + 1,
				lines.size(), cur_c + 1]
		T_SPRITE:
			hint = "1-4 TOOL (%s)   CTRL+Z UNDO   SPRITE %d   COLOUR %d" % [
				TOOLS[spr_tool], spr_sel, spr_color]
		T_MAP:
			hint = "DRAG TO PAINT   ARROWS SCROLL   TILE %d   %d,%d" % [
				map_tile, map_cam.x, map_cam.y]
		T_SOUND:
			hint = "SPACE PLAY   TAB PANEL   OCT %d   INST %d   %d/%d @ %d BPM" % [
				trk_oct, trk_inst, song.sig_num if song else 4,
				song.sig_den if song else 4, song.bpm if song else 120]
		_:
			hint = "ESC SHELF"
	PixelFont.draw(u, hint, 8, Pixel.UI_H - 10, Pixel.hue(23))

# --- code tab ----------------------------------------------------------
func _draw_code(u) -> void:
	var x0 := 8
	var y0 := 30 + int((1.0 - _panel_in) * 40.0)
	var rows := _code_rows()
	u.rectfill(x0, y0, Pixel.UI_W - 8, y0 + rows * 11 + 6, Pixel.BLACK)
	u.rect(x0, y0, Pixel.UI_W - 8, y0 + rows * 11 + 6, Pixel.dark(9))
	# gutter
	u.rectfill(x0 + 1, y0 + 1, x0 + 26, y0 + rows * 11 + 5, Pixel.dark(22))
	for i in rows:
		var li := scroll_l + i
		if li >= lines.size():
			break
		var y := y0 + 4 + i * 11
		var num := str(li + 1)
		PixelFont.draw(u, num, x0 + 24 - PixelFont.text_width(num), y,
			Pixel.hue(23) if li == cur_l else Pixel.dark(23))
		if li == err_line:
			u.rectfill(x0 + 28, y - 2, Pixel.UI_W - 10, y + 8, Pixel.dark(0))
		_draw_lua_line(u, str(lines[li]), x0 + 30, y)
	# caret, blinking on a beat
	if fmod(_blink, 1.0) < 0.55:
		var cx := x0 + 30 + (cur_c - scroll_c) * 6
		var cy := y0 + 4 + (cur_l - scroll_l) * 11
		u.rectfill(cx, cy - 1, cx + 1, cy + 8, Pixel.light(4))
	# error banner
	if err_text != "":
		u.rectfill(x0, Pixel.UI_H - 34, Pixel.UI_W - 8, Pixel.UI_H - 18, Pixel.dark(0))
		PixelFont.draw(u, err_text.substr(0, 74), x0 + 6, Pixel.UI_H - 30,
			Pixel.light(0))

const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "false",
	"for", "function", "if", "in", "local", "nil", "not", "or", "repeat",
	"return", "then", "true", "until", "while"]
const API_WORDS := ["cls", "spr", "sspr", "map", "print", "printc", "btn",
	"btnp", "circ", "circfill", "rect", "rectfill", "line", "pset", "pget",
	"camera", "clip", "pal", "palt", "fade", "sfx", "music", "note", "rnd",
	"flr", "min", "max", "mid", "sgn", "abs", "sqrt", "sin", "cos", "atan2",
	"mget", "mset", "fget", "fset", "dget", "dset", "font", "layer", "res",
	"mouse", "key", "t", "log", "textw", "bgscroll", "tri", "frames"]

## Syntax colouring, one token at a time. Comments grey, strings green,
## numbers amber, keywords pink, console API cyan.
func _draw_lua_line(u, src: String, x: int, y: int) -> void:
	var vis := src.substr(scroll_c, _code_cols())
	var i := 0
	var pen := x
	while i < vis.length():
		var ch := vis[i]
		if ch == "-" and i + 1 < vis.length() and vis[i + 1] == "-":
			PixelFont.draw(u, vis.substr(i), pen, y, Pixel.dark(23))
			return
		if ch == "\"" or ch == "'":
			var j := i + 1
			while j < vis.length() and vis[j] != ch:
				j += 1
			var lit := vis.substr(i, j - i + 1)
			PixelFont.draw(u, lit, pen, y, Pixel.hue(7))
			pen += PixelFont.text_width(lit)
			i = j + 1
			continue
		if ch >= "0" and ch <= "9":
			var j2 := i
			while j2 < vis.length() and ((vis[j2] >= "0" and vis[j2] <= "9")
					or vis[j2] == "."):
				j2 += 1
			var num := vis.substr(i, j2 - i)
			PixelFont.draw(u, num, pen, y, Pixel.hue(3))
			pen += PixelFont.text_width(num)
			i = j2
			continue
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_":
			var j3 := i
			while j3 < vis.length() and ((vis[j3] >= "a" and vis[j3] <= "z")
					or (vis[j3] >= "A" and vis[j3] <= "Z")
					or (vis[j3] >= "0" and vis[j3] <= "9") or vis[j3] == "_"):
				j3 += 1
			var word := vis.substr(i, j3 - i)
			var col := Pixel.GRAY
			if KEYWORDS.has(word):
				col = Pixel.hue(1)
			elif API_WORDS.has(word):
				col = Pixel.light(9)
			PixelFont.draw(u, word, pen, y, col)
			pen += PixelFont.text_width(word)
			i = j3
			continue
		PixelFont.draw(u, ch, pen, y, Pixel.hue(23))
		pen += 6
		i += 1

# --- sprite tab --------------------------------------------------------
## The palette sits beside the canvas, thirteen to a row, so all
## seventy-four colours are on screen at once and none of them fall off
## the bottom of it.
func _palette_rect() -> Rect2i:
	return Rect2i(212, 98, 8 * 10, 10 * 10)

func _sheet_rect() -> Rect2i:
	return Rect2i(300, 44, 16 * 11, 16 * 11)

func _draw_sprite(u) -> void:
	if cart == null:
		return
	var slide := int((1.0 - _panel_in) * 30.0)
	var r := _sprite_canvas_rect()
	# tools
	for i in TOOLS.size():
		var tx := 14 + i * 46
		var on := i == spr_tool
		u.rectfill(tx, 26, tx + 42, 40, Pixel.dark(11) if on else Pixel.BLACK)
		u.rect(tx, 26, tx + 42, 40, Pixel.hue(4) if on else Pixel.dark(9))
		PixelFont.draw(u, str(TOOLS[i]), tx + 4, 30,
			Pixel.WHITE if on else Pixel.hue(23))
		PixelFont.draw(u, str(i + 1), tx + 36, 31, Pixel.dark(23))
	# canvas: checkerboard under the transparent index, then the pixels
	u.rectfill(r.position.x - 2, r.position.y - 2 - slide,
		r.position.x + r.size.x + 1, r.position.y + r.size.y + 1 - slide,
		Pixel.dark(9))
	for py in 16:
		for px in 16:
			var v := _spr_get(px, py)
			var dx := r.position.x + px * spr_zoom
			var dy := r.position.y + py * spr_zoom - slide
			if v == 0:
				var checker := ((px + py) % 2 == 0)
				u.rectfill(dx, dy, dx + spr_zoom - 1, dy + spr_zoom - 1,
					Pixel.dark(22) if checker else Pixel.dark(23))
			else:
				u.rectfill(dx, dy, dx + spr_zoom - 1, dy + spr_zoom - 1, v)
	for g in range(0, 17, 4):
		u.vline(r.position.x + g * spr_zoom, r.position.y - slide,
			r.position.y + r.size.y - slide, Pixel.dark(9))
		u.hline(r.position.x, r.position.x + r.size.x,
			r.position.y + g * spr_zoom - slide, Pixel.dark(9))
	# 1:1 preview, and the same sprite doubled, both bobbing gently
	var bob := int(round(sin(t * 3.0) * 1.0))
	var pvx := 212
	u.rectfill(pvx, 44, pvx + 78, 90, Pixel.BLACK)
	u.rect(pvx, 44, pvx + 78, 90, Pixel.dark(9))
	PixelFont.draw(u, "SPRITE %d" % spr_sel, pvx + 3, 47, Pixel.hue(23))
	u.blit(cart.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(spr_sel),
		ArcadeCart.spr_y(spr_sel), 16, 16, pvx + 5, 62 + bob)
	u.blit_scaled(cart.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(spr_sel),
		ArcadeCart.spr_y(spr_sel), 16, 16, pvx + 30, 58 + bob, 2)
	# palette: every colour the machine has, thirteen to a row
	var pr := _palette_rect()
	PixelFont.draw(u, "PALETTE %d" % Pixel.color_count(),
		pr.position.x, pr.position.y - 10, Pixel.hue(23))
	for i in Pixel.color_count():
		var px2 := pr.position.x + (i % 8) * 10
		var py2 := pr.position.y + (i / 8) * 10
		u.rectfill(px2, py2, px2 + 8, py2 + 8, i)
		if i == spr_color:
			u.rect(px2 - 1, py2 - 1, px2 + 9, py2 + 9, Pixel.WHITE)
	PixelFont.draw(u, "COLOUR %d" % spr_color, pr.position.x,
		pr.position.y + 104, Pixel.light(4))
	u.rectfill(pr.position.x + 56, pr.position.y + 102, pr.position.x + 76,
		pr.position.y + 112, spr_color)
	# the sheet: all 256 sprites with the selected one ringed
	var gr := _sheet_rect()
	var gx := gr.position.x + int((1.0 - _panel_in) * 60.0)
	u.rectfill(gx - 3, gr.position.y - 12, gx + gr.size.x + 3,
		gr.position.y + gr.size.y + 3, Pixel.BLACK)
	u.rect(gx - 3, gr.position.y - 12, gx + gr.size.x + 3,
		gr.position.y + gr.size.y + 3, Pixel.dark(9))
	PixelFont.draw(u, "SHEET  256 sprites", gx, gr.position.y - 10, Pixel.hue(9))
	for i in 256:
		var sx := gx + (i % 16) * 11
		var sy := gr.position.y + (i / 16) * 11
		if (i / 16 + i % 16) % 2 == 0:
			u.rectfill(sx, sy, sx + 10, sy + 10, Pixel.dark(22))
		u.blit(cart.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(i),
			ArcadeCart.spr_y(i), 11, 11, sx, sy)
	u.rect(gx + (spr_sel % 16) * 11 - 1, gr.position.y + (spr_sel / 16) * 11 - 1,
		gx + (spr_sel % 16) * 11 + 11, gr.position.y + (spr_sel / 16) * 11 + 11,
		Pixel.light(4))

# --- map tab -----------------------------------------------------------
func _map_rect() -> Rect2i:
	return Rect2i(12, 34, 22 * map_zoom, 14 * map_zoom)

func _draw_map(u) -> void:
	if cart == null:
		return
	var r := _map_rect()
	u.rectfill(r.position.x - 2, r.position.y - 2, r.position.x + r.size.x + 1,
		r.position.y + r.size.y + 1, Pixel.BLACK)
	for ty in 14:
		for tx in 22:
			var tile := cart.mget(map_cam.x + tx, map_cam.y + ty)
			var dx := r.position.x + tx * map_zoom
			var dy := r.position.y + ty * map_zoom
			if tile == 0:
				if (tx + ty) % 2 == 0:
					u.rectfill(dx, dy, dx + map_zoom - 1, dy + map_zoom - 1,
						Pixel.dark(22))
				continue
			u.blit_scaled(cart.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(tile),
				ArcadeCart.spr_y(tile), 16, 16, dx, dy, 1)
	# minimap of the whole 128x64 field, with the view window marked
	var mm_x := Pixel.UI_W - 150
	var mm_y := Pixel.UI_H - 90
	u.rectfill(mm_x, mm_y, mm_x + 128, mm_y + 64, Pixel.BLACK)
	for y in 64:
		for x in 128:
			if cart.mget(x, y) != 0:
				u.pset(mm_x + x, mm_y + y, Pixel.hue(9))
	u.rect(mm_x + map_cam.x, mm_y + map_cam.y, mm_x + map_cam.x + 22,
		mm_y + map_cam.y + 14, Pixel.light(4))
	# tile picker
	var gr := _sheet_rect()
	PixelFont.draw(u, "TILES", gr.position.x, gr.position.y - 10, Pixel.hue(9))
	for i in 256:
		var sx := gr.position.x + (i % 16) * 11
		var sy := gr.position.y + (i / 16) * 11
		if (i / 16 + i % 16) % 2 == 0:
			u.rectfill(sx, sy, sx + 10, sy + 10, Pixel.dark(22))
		u.blit(cart.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(i),
			ArcadeCart.spr_y(i), 11, 11, sx, sy)
	u.rect(gr.position.x + (map_tile % 16) * 11 - 1,
		gr.position.y + (map_tile / 16) * 11 - 1,
		gr.position.x + (map_tile % 16) * 11 + 11,
		gr.position.y + (map_tile / 16) * 11 + 11, Pixel.light(4))

# --- tracker -----------------------------------------------------------
func _update_sound() -> void:
	if song == null:
		song = ChipSound.demo_song()
	if sound == null:
		sound = con.sound
	var shift := con.key_held.has(KEY_SHIFT)
	var ctrl := con.key_held.has(KEY_CTRL)
	var voices: int = sound.voices() if sound != null else ChipSound.CHANS
	if trk_ch >= voices:
		trk_ch = voices - 1
	# follow the playhead while it is running
	if sound != null and sound.playing and sound.follow:
		var pos: Array = sound.position()
		trk_row = int(pos[1])
	for code in con.key_hits.keys():
		var k := int(code)
		match k:
			KEY_TAB:
				trk_panel = (trk_panel + 1) % 3
			KEY_SPACE:
				if sound != null:
					sound.set_song(song)
					sound.toggle()
			KEY_UP:
				if trk_panel == 1:
					trk_ip = (trk_ip - 1 + INST_PARAMS.size()) % INST_PARAMS.size()
				else:
					trk_row = (trk_row - 1 + song.rows) % song.rows
			KEY_DOWN:
				if trk_panel == 1:
					trk_ip = (trk_ip + 1) % INST_PARAMS.size()
				else:
					trk_row = (trk_row + 1) % song.rows
			KEY_LEFT:
				if trk_panel == 1:
					_inst_nudge(-1, shift)
				elif trk_panel == 2:
					_song_nudge(-1, shift)
				else:
					trk_col -= 1
					if trk_col < 0:
						trk_col = 4
						trk_ch = (trk_ch - 1 + voices) % voices
			KEY_RIGHT:
				if trk_panel == 1:
					_inst_nudge(1, shift)
				elif trk_panel == 2:
					_song_nudge(1, shift)
				else:
					trk_col += 1
					if trk_col > 4:
						trk_col = 0
						trk_ch = (trk_ch + 1) % voices
			KEY_PAGEUP:
				trk_row = maxi(0, trk_row - song.rows_per_beat * song.sig_num)
			KEY_PAGEDOWN:
				trk_row = mini(song.rows - 1, trk_row + song.rows_per_beat * song.sig_num)
			KEY_BRACKETLEFT:
				trk_oct = maxi(0, trk_oct - 1)
			KEY_BRACKETRIGHT:
				trk_oct = mini(8, trk_oct + 1)
			KEY_MINUS:
				trk_inst = maxi(0, trk_inst - 1)
			KEY_EQUAL:
				trk_inst = mini(song.insts.size() - 1, trk_inst + 1)
			KEY_DELETE, KEY_BACKSPACE:
				if not _locked():
					song.set_cell(trk_pat, trk_row, trk_ch, [0, 0, 0, 0, 0])
					trk_row = (trk_row + trk_step) % song.rows
			KEY_F7:
				if sound != null:
					sound.set_song(song)
					sound.play_music(0)
			KEY_F8:
				if sound != null:
					sound.stop_music()
			KEY_1:
				if trk_panel == 2:
					song.sig_num = maxi(2, song.sig_num - 1)
			KEY_2:
				if trk_panel == 2:
					song.sig_num = mini(12, song.sig_num + 1)
	# note entry, when the pattern has focus
	if trk_panel == 0 and not ctrl:
		for code in con.key_hits.keys():
			var k2 := int(code)
			if PIANO.has(k2) and not _locked():
				var semi := trk_oct * 12 + int(PIANO[k2])
				if trk_col == 0:
					song.set_cell(trk_pat, trk_row, trk_ch,
						[semi + 2, trk_inst + 1, 0, 0, 0])
					if sound != null:
						sound.set_song(song)
						sound.preview(trk_inst, float(semi))
					trk_row = (trk_row + trk_step) % song.rows
			if k2 == KEY_APOSTROPHE and not _locked():
				song.set_cell(trk_pat, trk_row, trk_ch, [1, 0, 0, 0, 0])
				trk_row = (trk_row + trk_step) % song.rows
		# the numeric columns take digits
		if con.text_typed != "" and trk_col > 0 and not _locked():
			var ch := con.text_typed[con.text_typed.length() - 1]
			var digit := "0123456789abcdef".find(ch.to_lower())
			if digit >= 0:
				var cell := song.cell(trk_pat, trk_row, trk_ch)
				match trk_col:
					1: cell[1] = clampi(digit, 0, song.insts.size())
					2: cell[2] = clampi(digit * 4 + 1, 0, 65)
					3: cell[3] = digit
					4: cell[4] = ((int(cell[4]) << 4) & 0xF0) | digit
				song.set_cell(trk_pat, trk_row, trk_ch, cell)

func _locked() -> bool:
	return cart != null and cart.readonly

func _inst_nudge(dir: int, big: bool) -> void:
	if song.insts.is_empty():
		return
	var inst: ChipSound.Inst = song.insts[clampi(trk_inst, 0, song.insts.size() - 1)]
	var p: Array = INST_PARAMS[trk_ip]
	if EXPAND_PARAMS.has(str(p[1])) and not con.can("expand"):
		shell.note("that one needs the expansion board fitted")
		return
	var step := float(p[4]) * (4.0 if big else 1.0)
	var cur := float(inst.get(str(p[1])))
	var nv := clampf(cur + step * float(dir), float(p[2]), float(p[3]))
	inst.set(str(p[1]), int(nv) if str(p[1]) == "wave" else nv)
	if sound != null:
		sound.set_song(song)
		sound.preview(trk_inst, float(trk_oct * 12))

func _song_nudge(dir: int, big: bool) -> void:
	var d := dir * (10 if big else 1)
	match trk_ip % 6:
		0: song.bpm = clampi(song.bpm + d, 40, 300)
		1: song.speed = clampi(song.speed + dir, 1, 16)
		2: song.rows_per_beat = clampi(song.rows_per_beat + dir, 1, 16)
		3: song.sig_num = clampi(song.sig_num + dir, 2, 12)
		4: song.delay_fb = clampf(song.delay_fb + float(dir) * 0.05, 0.0, 0.85)
		5: song.room = clampf(song.room + float(dir) * 0.05, 0.0, 1.0)
	if sound != null:
		sound.set_song(song)
		sound._recalc_tempo()

static func note_name(n: int) -> String:
	if n == 0:
		return "---"
	if n == 1:
		return "==="
	var semi := n - 2
	return "%s%d" % [NOTE_NAMES[semi % 12], semi / 12]

func _draw_sound(u) -> void:
	if song == null:
		return
	# Six channels on screen at a time, scrolling to keep the cursor in
	# view: a column needs room for a note, an instrument, a volume and
	# an effect without any of them touching.
	var x0 := 6
	var y0 := 46
	var row_h := 9
	var col_w := 46
	var shown_ch := 6
	var first_ch := clampi(trk_ch - shown_ch / 2, 0,
		maxi(0, ChipSound.CHANS - shown_ch))
	var grid_w := 22 + shown_ch * col_w
	var shown := 20
	var first := clampi(trk_row - shown / 2, 0, maxi(0, song.rows - shown))
	u.rectfill(x0, y0 - 18, x0 + grid_w, y0 + shown * row_h + 4, Pixel.BLACK)
	var meters: Array = sound.meters() if sound != null else []
	var voices: int = sound.voices() if sound != null else ChipSound.CHANS
	for i in shown_ch:
		var ch := first_ch + i
		if ch >= ChipSound.CHANS:
			break
		var cx := x0 + 22 + i * col_w
		var locked_ch: bool = ch >= voices
		PixelFont.draw(u, "CH%d" % (ch + 1), cx, y0 - 17,
			Pixel.dark(22) if locked_ch else (Pixel.WHITE if ch == trk_ch
				else Pixel.hue(23)))
		if locked_ch:
			PixelFont.draw(u, "LOCKED", cx + 4, y0 - 8, Pixel.dark(0))
			continue
		var lvl := int(clampf(float(meters[ch]) if ch < meters.size() else 0.0,
			0.0, 1.0) * 9.0)
		u.rectfill(cx, y0 - 8, cx + 36, y0 - 4, Pixel.dark(22))
		if lvl > 0:
			u.rectfill(cx, y0 - 8, cx + lvl * 4, y0 - 4,
				Pixel.hue(9) if lvl < 7 else Pixel.hue(0))
	for i in shown:
		var r := first + i
		if r >= song.rows:
			break
		var y := y0 + i * row_h
		var beat := r % song.rows_per_beat == 0
		var bar := r % (song.rows_per_beat * maxi(1, song.sig_num)) == 0
		if bar:
			u.rectfill(x0, y - 1, x0 + grid_w, y + row_h - 2, Pixel.dark(11))
		elif beat:
			u.rectfill(x0, y - 1, x0 + grid_w, y + row_h - 2, Pixel.dark(22))
		if r == trk_row:
			u.rectfill(x0, y - 1, x0 + grid_w, y + row_h - 2, Pixel.dark(9))
		PixelFont.draw(u, "%02d" % r, x0 + 2, y,
			Pixel.light(4) if bar else Pixel.hue(23))
		for i2 in shown_ch:
			var ch2 := first_ch + i2
			if ch2 >= voices:
				continue
			var cell := song.cell(trk_pat, r, ch2)
			var cx2 := x0 + 22 + i2 * col_w
			var nn := note_name(int(cell[0]))
			var ncol := Pixel.dark(23)
			if int(cell[0]) >= 2:
				ncol = Pixel.light(9)
			elif int(cell[0]) == 1:
				ncol = Pixel.hue(0)
			PixelFont.draw(u, nn, cx2, y, ncol)
			PixelFont.draw(u, "%X" % int(cell[1]) if int(cell[1]) > 0 else ".",
				cx2 + 21, y, Pixel.hue(4) if int(cell[1]) > 0 else Pixel.dark(22))
			PixelFont.draw(u, "%X" % mini(15, int(cell[2]) / 4) if int(cell[2]) > 0
				else ".", cx2 + 28, y,
				Pixel.hue(7) if int(cell[2]) > 0 else Pixel.dark(22))
			var has_fx: bool = int(cell[3]) > 0 or int(cell[4]) > 0
			PixelFont.draw(u, "%X%X" % [int(cell[3]), int(cell[4]) & 0xF]
				if has_fx else "..", cx2 + 35, y,
				Pixel.hue(6) if has_fx else Pixel.dark(22))
	# the cursor sits under whichever sub-column is being edited
	var cyy := y0 + (trk_row - first) * row_h
	var cxx: int = x0 + 22 + (trk_ch - first_ch) * col_w \
		+ int([0, 21, 28, 35, 41][trk_col])
	u.rect(cxx - 1, cyy - 1, cxx + int([17, 5, 5, 5, 5][trk_col]), cyy + 7,
		Pixel.light(4) if fmod(t, 0.6) < 0.4 else Pixel.hue(4))
	if ChipSound.CHANS > shown_ch:
		PixelFont.draw(u, "<%d-%d of %d>" % [first_ch + 1,
			first_ch + shown_ch, ChipSound.CHANS], x0 + 2, y0 + shown * row_h + 6,
			Pixel.dark(23))
	# --- right hand panel
	var px := x0 + grid_w + 6
	u.rectfill(px, 26, Pixel.UI_W - 4, Pixel.UI_H - 18, Pixel.BLACK)
	u.rect(px, 26, Pixel.UI_W - 4, Pixel.UI_H - 18, Pixel.dark(9))
	var titles := ["PATTERN", "INSTRUMENT", "SONG"]
	PixelFont.draw(u, str(titles[trk_panel]), px + 6, 30, Pixel.light(4),
		PixelFont.BOLD)
	PixelFont.draw(u, "TAB switches panel", px + 6, 40, Pixel.dark(23))
	if trk_panel == 1:
		_draw_inst_panel(u, px, 52)
	elif trk_panel == 2:
		_draw_song_panel(u, px, 52)
	else:
		_draw_pattern_panel(u, px, 52)

func _draw_pattern_panel(u, px: int, y: int) -> void:
	var inst_name := "-"
	if trk_inst < song.insts.size():
		inst_name = str(song.insts[trk_inst].name)
	var rows := [
		"INST  %d %s" % [trk_inst, inst_name.substr(0, 11)],
		"OCTAVE %d  [ ] change" % trk_oct,
		"STEP  %d" % trk_step,
		"PATTERN %d/%d" % [trk_pat, song.patterns.size()],
		"",
		"SPACE play or stop",
		"ZSXDCV.. is the piano",
		"Q2W3E.. octave above",
		"'  note off",
		"-/= pick instrument",
		"",
		"EFFECT COLUMN",
		" 1xx slide up",
		" 2xx slide down",
		" 3xx glide to note",
		" 0xy arpeggio",
		" 8xx pan",
		" Axy volume slide",
		" Fxx speed",
	]
	for i in rows.size():
		PixelFont.draw(u, str(rows[i]), px + 6, y + i * 10,
			Pixel.hue(23) if i > 4 else Pixel.WHITE)

func _draw_inst_panel(u, px: int, y: int) -> void:
	if song.insts.is_empty():
		return
	var inst: ChipSound.Inst = song.insts[clampi(trk_inst, 0, song.insts.size() - 1)]
	PixelFont.draw(u, "%d %s" % [trk_inst, inst.name], px + 6, y, Pixel.light(9))
	PixelFont.draw(u, "arrows edit, shift x4", px + 6, y + 9, Pixel.dark(23))
	var top := clampi(trk_ip - 8, 0, maxi(0, INST_PARAMS.size() - 17))
	for i in mini(17, INST_PARAMS.size()):
		var pi := top + i
		if pi >= INST_PARAMS.size():
			break
		var p: Array = INST_PARAMS[pi]
		var yy := y + 22 + i * 10
		var on := pi == trk_ip
		if on:
			u.rectfill(px + 4, yy - 1, Pixel.UI_W - 8, yy + 7, Pixel.dark(11))
		var val := float(inst.get(str(p[1])))
		var txt := ""
		if str(p[1]) == "wave":
			txt = ChipSound.WAVE_NAMES[clampi(int(val), 0,
				ChipSound.WAVE_NAMES.size() - 1)]
		else:
			txt = "%.2f" % val
		var locked_p: bool = EXPAND_PARAMS.has(str(p[1])) and not con.can("expand")
		PixelFont.draw(u, str(p[0]), px + 8, yy,
			Pixel.dark(23) if locked_p else (Pixel.WHITE if on else Pixel.hue(23)))
		PixelFont.draw(u, txt, px + 78, yy,
			Pixel.dark(23) if locked_p else (Pixel.light(4) if on else Pixel.GRAY))
		if locked_p:
			PixelFont.draw(u, "x", px + 138, yy, Pixel.hue(0))
		# a little bar so the value is readable at a glance
		var frac := clampf((val - float(p[2])) / maxf(0.001,
			float(p[3]) - float(p[2])), 0.0, 1.0)
		u.rectfill(px + 112, yy + 2, px + 112 + int(frac * 22.0), yy + 5,
			Pixel.hue(9))

func _draw_song_panel(u, px: int, y: int) -> void:
	var rows := [
		"BPM        %d" % song.bpm,
		"SPEED      %d ticks/row" % song.speed,
		"ROWS/BEAT  %d" % song.rows_per_beat,
		"SIGNATURE  %d/%d" % [song.sig_num, song.sig_den],
		"DELAY FB   %.2f" % song.delay_fb,
		"ROOM       %.2f" % song.room,
	]
	for i in rows.size():
		var yy := y + i * 12
		var on := (trk_ip % 6) == i
		if on:
			u.rectfill(px + 4, yy - 1, Pixel.UI_W - 8, yy + 8, Pixel.dark(11))
		PixelFont.draw(u, str(rows[i]), px + 8, yy,
			Pixel.WHITE if on else Pixel.hue(23))
	PixelFont.draw(u, "up/down pick a row,", px + 6, y + 80, Pixel.dark(23))
	PixelFont.draw(u, "left/right change it", px + 6, y + 90, Pixel.dark(23))
	PixelFont.draw(u, "a bar = %d rows" % [song.rows_per_beat * song.sig_num],
		px + 6, y + 106, Pixel.hue(9))
	PixelFont.draw(u, "F7 play  F8 stop", px + 6, y + 120, Pixel.hue(23))

func _draw_info(u) -> void:
	pass
