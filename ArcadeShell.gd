class_name ArcadeShell
extends RefCounted
## THE FRONT OF HOUSE. Boot sequence, cartridge menu, pause, settings,
## crash screen -- everything the cabinet shows when a game is not the
## thing on screen. All of it is drawn into the console's UI layer with
## the console's own fonts, which means all of it lands on the pixel
## grid: there is no such thing as a half-pixel menu here.
##
## The editors live in ArcadeEdit and are driven from the same state
## machine; this file owns the chrome around them.

const S_BOOT := 0
const S_MENU := 1
const S_RUN := 2
const S_PAUSE := 3
const S_CRASH := 4
const S_EDIT := 5
const S_SETTINGS := 6
const S_DISC := 7

var con: ArcadeConsole = null
var edit = null                     # ArcadeEdit, set by the host
var state: int = S_BOOT
var t: float = 0.0                  # seconds in the current state
var total_t: float = 0.0
var carts: Array = []               # ArcadeCart list (built-ins + floppies)
var sel: int = 0
var pause_sel: int = 0
var set_sel: int = 0
var msg: String = ""
var msg_t: float = 0.0
var quit_requested: bool = false
var machine = null                  # the cabinet, for floppy access

## Selection glide: the highlight box eases toward the selected row
## instead of snapping, but always lands on whole pixels.
var _sel_y: float = 0.0
var _wipe: float = 0.0
var _wipe_dir: int = 0
var _next_state: int = -1

const MENU_ITEMS := ["RESUME", "RESTART", "EDIT THIS CART", "FLOPPY SLOT",
	"SETTINGS", "EJECT / SHELF", "LEAVE CABINET"]

var disc_sel: int = 0
var disc_side: int = 0          # 0 = discs you carry, 1 = things to write

func _init(c: ArcadeConsole) -> void:
	con = c

func go(s: int) -> void:
	_next_state = s
	_wipe_dir = 1
	_wipe = 0.0

func _enter(s: int) -> void:
	state = s
	t = 0.0
	if s == S_MENU:
		_sel_y = float(sel)

func note(m: String) -> void:
	msg = m
	msg_t = 2.6

# ================================================================ update

func update(delta: float) -> void:
	t += delta
	total_t += delta
	msg_t = maxf(0.0, msg_t - delta)
	# state wipe
	if _wipe_dir == 1:
		_wipe = minf(1.0, _wipe + delta * 5.0)
		if _wipe >= 1.0:
			_enter(_next_state)
			_wipe_dir = -1
	elif _wipe_dir == -1:
		_wipe = maxf(0.0, _wipe - delta * 5.0)
		if _wipe <= 0.0:
			_wipe_dir = 0
	match state:
		S_BOOT:
			if t > 3.4 or _any_start():
				go(S_MENU)
		S_MENU:
			_update_menu(delta)
		S_RUN:
			if con.crashed:
				go(S_CRASH)
			elif _hit(ArcadeConsole.B_START) or _key_hit(KEY_ESCAPE):
				pause_sel = 0
				go(S_PAUSE)
			else:
				con.step(delta)
		S_PAUSE:
			_update_pause()
		S_CRASH:
			if _any_start():
				go(S_MENU)
		S_SETTINGS:
			_update_settings()
		S_DISC:
			_update_disc()
		S_EDIT:
			if edit != null:
				edit.update(delta)

func _any_start() -> bool:
	return _hit(ArcadeConsole.B_A) or _hit(ArcadeConsole.B_START) \
		or _key_hit(KEY_ENTER) or _key_hit(KEY_SPACE)

func _hit(b: int) -> bool:
	return con.btn_hit[b]

func _key_hit(k: int) -> bool:
	return con.key_hits.has(k)

func _update_menu(delta: float) -> void:
	_sel_y = lerpf(_sel_y, float(sel), clampf(delta * 14.0, 0.0, 1.0))
	if carts.is_empty():
		return
	if _hit(ArcadeConsole.B_DOWN):
		sel = (sel + 1) % carts.size()
	if _hit(ArcadeConsole.B_UP):
		sel = (sel - 1 + carts.size()) % carts.size()
	if _hit(ArcadeConsole.B_A) or _key_hit(KEY_ENTER):
		_boot_selected()
	if _key_hit(KEY_N) and machine != null and machine.has_method("new_cart"):
		var fresh = machine.new_cart()
		sel = carts.find(fresh)
		if edit != null:
			edit.open(fresh)
			go(S_EDIT)
		note("new cartridge started")
	if _hit(ArcadeConsole.B_Y) or _key_hit(KEY_E):
		if edit != null:
			edit.open(carts[sel])
			go(S_EDIT)
	if _hit(ArcadeConsole.B_SELECT):
		go(S_SETTINGS)
	if _hit(ArcadeConsole.B_X) or _key_hit(KEY_F):
		go(S_DISC)
	if _hit(ArcadeConsole.B_B) or _key_hit(KEY_ESCAPE):
		quit_requested = true

func _boot_selected() -> void:
	if sel < 0 or sel >= carts.size():
		return
	con.boot(carts[sel])
	if con.sound != null and con.sound.has_method("load_cart"):
		con.sound.load_cart(carts[sel])
	go(S_CRASH if con.crashed else S_RUN)

func _update_pause() -> void:
	if _hit(ArcadeConsole.B_DOWN):
		pause_sel = (pause_sel + 1) % MENU_ITEMS.size()
	if _hit(ArcadeConsole.B_UP):
		pause_sel = (pause_sel - 1 + MENU_ITEMS.size()) % MENU_ITEMS.size()
	if _hit(ArcadeConsole.B_B):
		go(S_RUN)
		return
	if not (_hit(ArcadeConsole.B_A) or _key_hit(KEY_ENTER)):
		return
	match pause_sel:
		0: go(S_RUN)
		1:
			con.boot(carts[sel])
			go(S_RUN)
		2:
			if edit != null:
				edit.open(carts[sel])
				go(S_EDIT)
		3: go(S_DISC)
		4: go(S_SETTINGS)
		5: go(S_MENU)
		6: quit_requested = true

func _update_settings() -> void:
	var rows := 3
	if _hit(ArcadeConsole.B_DOWN):
		set_sel = (set_sel + 1) % rows
	if _hit(ArcadeConsole.B_UP):
		set_sel = (set_sel - 1 + rows) % rows
	if _hit(ArcadeConsole.B_LEFT) or _hit(ArcadeConsole.B_RIGHT):
		var dir := 1 if _hit(ArcadeConsole.B_RIGHT) else -1
		match set_sel:
			0:
				# GAME resolution. The console UI never changes size.
				if sel >= 0 and sel < carts.size():
					var c: ArcadeCart = carts[sel]
					var want := clampi(c.res_mode + dir, 0,
						ArcadeConsole.RES_MODES.size() - 1)
					var need := str(ArcadeConsole.RES_MODES[want]["needs"])
					if need != "" and not con.can(need):
						note("that canvas needs the %s board fitted" % (
							"expansion" if need == "expand" else "smooth motion"))
					else:
						c.res_mode = want
						note("game canvas: " + str(
							ArcadeConsole.RES_MODES[c.res_mode]["name"]))
			1:
				scanline = clampf(scanline + 0.1 * float(dir), 0.0, 1.0)
			2:
				volume = clampf(volume + 0.1 * float(dir), 0.0, 1.0)
	if _hit(ArcadeConsole.B_B) or _key_hit(KEY_ESCAPE):
		go(S_MENU)

var scanline: float = 0.35
var volume: float = 0.7

# ================================================================= draw

func draw() -> void:
	var u := con.ui
	u.clear(Pixel.CLEAR)
	match state:
		S_BOOT: _draw_boot(u)
		S_MENU: _draw_menu(u)
		S_RUN: _draw_run_overlay(u)
		S_PAUSE: _draw_pause(u)
		S_CRASH: _draw_crash(u)
		S_SETTINGS: _draw_settings(u)
		S_DISC: _draw_disc(u)
		S_EDIT:
			if edit != null:
				edit.draw(u)
	if msg_t > 0.0:
		_toast(u, msg)
	if _wipe > 0.0:
		_draw_wipe(u)

## Curtain wipe: solid columns march across, one pixel column at a time.
func _draw_wipe(u) -> void:
	var w := int(float(Pixel.UI_W) * _wipe)
	for x in w:
		var h := Pixel.UI_H
		u.vline(x, 0, h, Pixel.BLACK)
	u.vline(w, 0, Pixel.UI_H, Pixel.hue(10))
	u.vline(w + 1, 0, Pixel.UI_H, Pixel.dark(10))

func _toast(u, text: String) -> void:
	var wid := PixelFont.text_width(text, PixelFont.SYS) + 12
	var x := Pixel.UI_W / 2 - wid / 2
	var y := Pixel.UI_H - 26
	var a := clampf(msg_t / 0.4, 0.0, 1.0)
	if a < 1.0 and int(msg_t * 20.0) % 2 == 0:
		return
	u.rectfill(x, y, x + wid, y + 12, Pixel.BLACK)
	u.rect(x, y, x + wid, y + 12, Pixel.hue(9))
	PixelFont.draw(u, text, x + 6, y + 3, Pixel.light(9))

# --- boot --------------------------------------------------------------
## Power-on: the logo assembles out of scanning bars, the palette strip
## sweeps past underneath, and the machine says what it is.
func _draw_boot(u) -> void:
	u.clear(Pixel.BLACK)
	var cx := Pixel.UI_W / 2
	# scanning bars
	var phase := clampf(t / 1.1, 0.0, 1.0)
	for i in 18:
		var yy := int(fmod(float(i) * 15.0 + t * 90.0, float(Pixel.UI_H)))
		var c := Pixel.dark(9) if i % 2 == 0 else Pixel.dark(11)
		u.hline(0, int(float(Pixel.UI_W) * (1.0 - phase)), yy, c)
	# the logo drops in and settles
	var drop := 1.0 - pow(1.0 - clampf((t - 0.5) / 0.7, 0.0, 1.0), 3.0)
	var ly := int(lerpf(-40.0, 86.0, drop))
	if t > 0.5:
		PixelFont.draw_centered(u, "DUDE-16", cx, ly, Pixel.light(4),
			PixelFont.HUGE, PixelFont.SHADOW, Pixel.dark(0))
		PixelFont.draw_centered(u, "16-BIT ENTERTAINMENT SYSTEM", cx, ly + 30,
			Pixel.hue(9), PixelFont.SYS, PixelFont.PLAIN, 0, 1)
	# palette sweep: every colour the machine has, marching past
	if t > 1.4:
		var n := Pixel.color_count()
		var sweep := clampf((t - 1.4) / 0.9, 0.0, 1.0)
		for i in int(float(n) * sweep):
			var bx := 20 + (i % 37) * 12
			var by := 150 + (i / 37) * 12
			u.rectfill(bx, by, bx + 10, by + 10, i)
	if t > 2.4:
		var blink := int(t * 2.0) % 2 == 0
		if blink:
			PixelFont.draw_centered(u, "PRESS START", cx, 236, Pixel.WHITE,
				PixelFont.BOLD)
	PixelFont.draw(u, "%d COLOURS  %dx%d  LUA CARTRIDGE" % [Pixel.color_count(),
		Pixel.UI_W, Pixel.UI_H], 8, Pixel.UI_H - 12, Pixel.dark(23))

# --- menu --------------------------------------------------------------
## The shelf. Cartridge list on the left, big animated preview panel on
## the right, and a title bar that never stops moving.
func _draw_menu(u) -> void:
	u.clear(Pixel.dark(22))
	_draw_backdrop(u)
	# header
	u.rectfill(0, 0, Pixel.UI_W, 26, Pixel.BLACK)
	u.hline(0, Pixel.UI_W, 27, Pixel.hue(9))
	PixelFont.draw(u, "DUDE-16", 8, 6, Pixel.light(4), PixelFont.BOLD,
		PixelFont.SHADOW, Pixel.dark(4))
	PixelFont.draw(u, "CARTRIDGE SHELF", 92, 8, Pixel.hue(9), PixelFont.SYS,
		PixelFont.PLAIN, 0, 1, 1.0, total_t * 3.0)
	PixelFont.draw(u, "%d ON THE SHELF" % carts.size(), Pixel.UI_W - 96, 8,
		Pixel.dark(23))
	# list
	var lx := 10
	var ly := 40
	var row_h := 16
	var shown := mini(carts.size(), 11)
	var first := clampi(sel - shown / 2, 0, maxi(0, carts.size() - shown))
	u.rectfill(lx - 4, ly - 6, lx + 190, ly + shown * row_h + 4, Pixel.BLACK)
	u.rect(lx - 4, ly - 6, lx + 190, ly + shown * row_h + 4, Pixel.dark(9))
	# the glider
	var gy := ly + int(round((_sel_y - float(first)) * float(row_h))) - 3
	if gy > ly - 8 and gy < ly + shown * row_h:
		u.rectfill(lx - 2, gy, lx + 188, gy + 13, Pixel.dark(11))
		u.vline(lx - 2, gy, gy + 13, Pixel.light(4))
		u.vline(lx - 1, gy, gy + 13, Pixel.hue(4))
	for i in shown:
		var idx := first + i
		if idx >= carts.size():
			break
		var c: ArcadeCart = carts[idx]
		var y := ly + i * row_h
		var on := idx == sel
		var arrow := ">" if on else " "
		PixelFont.draw(u, "%s%s" % [arrow, c.name.substr(0, 20)], lx + 2, y,
			Pixel.WHITE if on else Pixel.GRAY, PixelFont.BOLD if on else PixelFont.SYS)
		if c.readonly:
			PixelFont.draw(u, "ROM", lx + 160, y + 1, Pixel.dark(4))
	# preview panel
	_draw_preview(u, 212, 40, 258, 190)
	# footer keys
	u.rectfill(0, Pixel.UI_H - 20, Pixel.UI_W, Pixel.UI_H, Pixel.BLACK)
	u.hline(0, Pixel.UI_W, Pixel.UI_H - 21, Pixel.dark(9))
	PixelFont.draw(u, "A PLAY   Y/E EDIT   N NEW CART   SELECT SETTINGS   B/ESC AWAY",
		8, Pixel.UI_H - 14, Pixel.hue(23))

## Slow diagonal drift behind the menus. Cheap, and it stops the screen
## from ever looking like a still image.
func _draw_backdrop(u) -> void:
	var off := int(total_t * 14.0)
	for i in 26:
		var x := (i * 24 - off) % (Pixel.UI_W + 60) - 30
		u.line(x, 0, x + 60, Pixel.UI_H, Pixel.dark(22))
	for i in 9:
		var y := (i * 34 + int(total_t * 5.0)) % Pixel.UI_H
		u.hline(0, Pixel.UI_W, y, Pixel.hue(22))

func _draw_preview(u, x: int, y: int, w: int, h: int) -> void:
	u.rectfill(x, y, x + w, y + h, Pixel.BLACK)
	u.rect(x, y, x + w, y + h, Pixel.hue(9))
	if carts.is_empty():
		PixelFont.draw_centered(u, "NO CARTRIDGES", x + w / 2, y + h / 2,
			Pixel.dark(23))
		return
	var c: ArcadeCart = carts[sel]
	PixelFont.draw(u, c.name.substr(0, 22), x + 8, y + 8, Pixel.light(4),
		PixelFont.WIDE)
	PixelFont.draw(u, "BY " + c.author.substr(0, 24), x + 8, y + 26, Pixel.hue(23))
	# a live window onto the cart's own art: sprites 0..23, bobbing
	var sx := x + 10
	var sy := y + 44
	for i in 24:
		var bob := int(round(sin(total_t * 3.0 + float(i) * 0.5) * 2.0))
		u.blit(c.sheet, ArcadeCart.SHEET_W, ArcadeCart.spr_x(i),
			ArcadeCart.spr_y(i), 16, 16, sx + (i % 8) * 18, sy + (i / 8) * 18 + bob)
	# stats block
	var lines := [
		"CANVAS  %s" % str(ArcadeConsole.RES_MODES[c.res_mode]["name"]),
		"CODE    %d lines" % (c.code.count("\n") + 1),
		"MUSIC   %s" % ("yes" if not c.song.is_empty() else "none"),
		"WRITE   %s" % ("locked (ROM)" if c.readonly else "editable"),
	]
	for i in lines.size():
		PixelFont.draw(u, str(lines[i]), x + 8, y + 116 + i * 11, Pixel.hue(9))
	# marquee
	var bar := int((sin(total_t * 2.0) * 0.5 + 0.5) * float(w - 16))
	u.rectfill(x + 8, y + h - 14, x + 8 + bar, y + h - 10, Pixel.hue(4))

# --- in-game overlay ---------------------------------------------------
func _draw_run_overlay(u) -> void:
	# nothing over the top of a running game except a fading hint
	if t < 2.0:
		var blink := int(t * 3.0) % 2 == 0
		if blink:
			PixelFont.draw(u, "START = PAUSE", 8, Pixel.UI_H - 14, Pixel.dark(23))

func _draw_pause(u) -> void:
	# the game stays visible underneath; this is the console's own layer
	var bx := Pixel.UI_W / 2 - 90
	var by := 60
	var pop := 1.0 - pow(1.0 - clampf(t / 0.18, 0.0, 1.0), 3.0)
	var hh := int(120.0 * pop)
	u.rectfill(bx, by, bx + 180, by + hh, Pixel.BLACK)
	u.rect(bx, by, bx + 180, by + hh, Pixel.hue(9))
	if pop < 0.9:
		return
	PixelFont.draw_centered(u, "PAUSED", bx + 90, by + 8, Pixel.light(4),
		PixelFont.BOLD)
	for i in MENU_ITEMS.size():
		var yy := by + 26 + i * 15
		var on := i == pause_sel
		if on:
			u.rectfill(bx + 6, yy - 3, bx + 174, yy + 9, Pixel.dark(11))
			PixelFont.draw(u, ">", bx + 10, yy, Pixel.light(4))
		PixelFont.draw(u, str(MENU_ITEMS[i]), bx + 22, yy,
			Pixel.WHITE if on else Pixel.GRAY)

func _draw_crash(u) -> void:
	u.clear(Pixel.dark(0))
	for i in 40:
		var yy := (i * 7 + int(total_t * 40.0)) % Pixel.UI_H
		u.hline(0, Pixel.UI_W, yy, Pixel.dark(0))
	PixelFont.draw_centered(u, "CARTRIDGE FAULT", Pixel.UI_W / 2, 40,
		Pixel.light(0), PixelFont.HUGE, PixelFont.SHADOW, Pixel.dark(0))
	u.rectfill(24, 90, Pixel.UI_W - 24, 170, Pixel.BLACK)
	u.rect(24, 90, Pixel.UI_W - 24, 170, Pixel.hue(0))
	var wrapped := _wrap(con.crash_msg, 68)
	for i in mini(wrapped.size(), 6):
		PixelFont.draw(u, str(wrapped[i]), 32, 100 + i * 11, Pixel.light(0))
	PixelFont.draw_centered(u, "the machine is fine. the code is not.",
		Pixel.UI_W / 2, 186, Pixel.hue(23))
	if int(total_t * 2.0) % 2 == 0:
		PixelFont.draw_centered(u, "PRESS START", Pixel.UI_W / 2, 216,
			Pixel.WHITE, PixelFont.BOLD)

static func _wrap(s: String, cols: int) -> Array:
	var out: Array = []
	for para in s.split("\n"):
		var line := ""
		for word in str(para).split(" "):
			if line.length() + str(word).length() + 1 > cols:
				out.append(line)
				line = str(word)
			else:
				line = (line + " " + str(word)) if line != "" else str(word)
		out.append(line)
	return out

func _draw_settings(u) -> void:
	u.clear(Pixel.dark(22))
	_draw_backdrop(u)
	var bx := 60
	var by := 50
	u.rectfill(bx, by, bx + 360, by + 150, Pixel.BLACK)
	u.rect(bx, by, bx + 360, by + 150, Pixel.hue(9))
	PixelFont.draw(u, "SETTINGS", bx + 12, by + 10, Pixel.light(4),
		PixelFont.WIDE)
	var c: ArcadeCart = carts[sel] if sel < carts.size() else null
	var rows := [
		["GAME CANVAS", str(ArcadeConsole.RES_MODES[c.res_mode]["name"]) if c else "-",
			str(ArcadeConsole.RES_MODES[c.res_mode]["desc"]) if c else ""],
		["SCANLINES", "%d%%" % int(scanline * 100.0), "how much CRT you want"],
		["VOLUME", "%d%%" % int(volume * 100.0), "the cabinet speaker"],
	]
	# what this particular cabinet is, and what it is not
	var fitted := "stock machine: two canvases, four voices, whole pixels only"
	if con.can("expand") and con.can("smooth"):
		fitted = "both boards fitted: everything unlocked"
	elif con.can("expand"):
		fitted = "expansion board: BIG canvas, eight voices, modulators"
	elif con.can("smooth"):
		fitted = "smooth motion board: free positioning"
	PixelFont.draw(u, fitted, bx + 12, by + 112, Pixel.light(9))
	for i in rows.size():
		var yy := by + 44 + i * 26
		var on := i == set_sel
		if on:
			u.rectfill(bx + 8, yy - 4, bx + 352, yy + 16, Pixel.dark(11))
		PixelFont.draw(u, str(rows[i][0]), bx + 16, yy,
			Pixel.WHITE if on else Pixel.GRAY, PixelFont.BOLD if on else PixelFont.SYS)
		PixelFont.draw(u, "< %s >" % str(rows[i][1]), bx + 160, yy,
			Pixel.light(4) if on else Pixel.hue(23))
		PixelFont.draw(u, str(rows[i][2]), bx + 16, yy + 10, Pixel.dark(23))
	PixelFont.draw(u, "the canvas size changes the GAME only -- this menu is",
		bx + 12, by + 124, Pixel.hue(23))
	PixelFont.draw(u, "always 480x270, whatever the cartridge is doing.",
		bx + 12, by + 134, Pixel.hue(23))

# --- the floppy slot ---------------------------------------------------
## Left: what you are carrying. Right: what this machine could write.
## Reading a disc does the obvious thing for its kind, and the one
## conversion that does not exist (song back into a patch) is simply not
## on the list.
func _write_options() -> Array:
	var out: Array = []
	if sel >= 0 and sel < carts.size():
		var c: ArcadeCart = carts[sel]
		out.append(["whole cartridge: " + c.name, "cart"])
		out.append(["just the code, as a script", "script"])
		out.append(["the song, for another cabinet", "song"])
	return out

func _update_disc() -> void:
	var carried: Array = ArcadeDisc.carried()
	var writes := _write_options()
	if _hit(ArcadeConsole.B_LEFT):
		disc_side = 0
	if _hit(ArcadeConsole.B_RIGHT):
		disc_side = 1
	var n := carried.size() if disc_side == 0 else writes.size()
	if n > 0:
		if _hit(ArcadeConsole.B_DOWN):
			disc_sel = (disc_sel + 1) % n
		if _hit(ArcadeConsole.B_UP):
			disc_sel = (disc_sel - 1 + n) % n
	if _hit(ArcadeConsole.B_B) or _key_hit(KEY_ESCAPE):
		go(S_MENU)
		return
	if not (_hit(ArcadeConsole.B_A) or _key_hit(KEY_ENTER)):
		return
	if disc_side == 0:
		if disc_sel < carried.size():
			_read_disc(disc_sel)
	elif disc_sel < writes.size():
		_write_disc(str(writes[disc_sel][1]))

func _read_disc(i: int) -> void:
	var d: Dictionary = ArcadeDisc.take(i)
	if d.is_empty():
		return
	match ArcadeDisc.kind_of(d):
		"cart":
			var c := ArcadeCart.from_dict(d)
			if machine != null and machine.has_method("adopt_cart"):
				machine.adopt_cart(c)
			carts = machine.shell.carts if machine != null else carts
			sel = carts.find(c)
			note("loaded cartridge: " + c.name)
		"script":
			if edit != null and sel < carts.size():
				if carts[sel].readonly:
					note("that cartridge is a ROM -- start a new one first (N)")
					return
				edit.open(carts[sel])
				edit.lines = str(d.get("code", "")).split("\n")
				edit.commit()
				note("script loaded into the code editor")
		"song":
			if edit != null:
				edit.song = ChipSound.Song.from_dict(d)
				edit.commit()
				if con.sound != null:
					con.sound.set_song(edit.song)
				note("song loaded: " + str(d.get("title", d.get("name", "?"))))
		"patch":
			if edit != null and edit.song != null:
				var inst := ArcadeDisc.patch_to_inst(d)
				if inst.sample.size() < 32:
					note("that patch made no sound to render")
					return
				edit.song.insts.append(inst)
				edit.trk_inst = edit.song.insts.size() - 1
				edit.commit()
				if con.sound != null:
					con.sound.set_song(edit.song)
				note("patch rendered into instrument %d: %s" % [
					edit.trk_inst, inst.name])
		_:
			note("this machine cannot read that disc")

func _write_disc(kind: String) -> void:
	if sel < 0 or sel >= carts.size():
		return
	var c: ArcadeCart = carts[sel]
	if Inventory.res_count("floppy") <= 0:
		note("no blank floppies -- cut some at a disc maker")
		return
	var payload: Dictionary = {}
	match kind:
		"cart":
			payload = ArcadeDisc.make("cart", c.name, c.to_dict())
		"script":
			payload = ArcadeDisc.make("script", c.name + " CODE", {"code": c.code})
		"song":
			var sd: Dictionary = edit.song.to_dict() if (edit != null
				and edit.song != null) else c.song
			if sd.is_empty():
				note("this cartridge has no song on it")
				return
			payload = ArcadeDisc.make("song", str(sd.get("title", c.name)), sd)
	if ArcadeDisc.write(payload):
		note("written: " + ArcadeDisc.label(payload))
		Sfx.play("coin", -14.0)

func _draw_disc(u) -> void:
	u.clear(Pixel.dark(22))
	_draw_backdrop(u)
	u.rectfill(0, 0, Pixel.UI_W, 24, Pixel.BLACK)
	PixelFont.draw(u, "FLOPPY SLOT", 8, 7, Pixel.light(9), PixelFont.BOLD)
	PixelFont.draw(u, "a disc holds anything. every machine reads what it knows.",
		120, 9, Pixel.hue(23))
	# left: the discs in your bags
	var carried: Array = ArcadeDisc.carried()
	u.rectfill(8, 34, 232, 224, Pixel.BLACK)
	u.rect(8, 34, 232, 224, Pixel.hue(9) if disc_side == 0 else Pixel.dark(9))
	PixelFont.draw(u, "IN YOUR BAGS (%d)" % carried.size(), 14, 38, Pixel.hue(4))
	if carried.is_empty():
		PixelFont.draw(u, "nothing written yet.", 14, 56, Pixel.dark(23))
		PixelFont.draw(u, "blanks are cut at a disc maker.", 14, 68, Pixel.dark(23))
	for i in mini(carried.size(), 12):
		var d: Dictionary = carried[i]
		var y := 54 + i * 14
		var on: bool = disc_side == 0 and i == disc_sel
		if on:
			u.rectfill(12, y - 2, 228, y + 10, Pixel.dark(11))
		PixelFont.draw(u, ArcadeDisc.label(d).substr(0, 30), 16, y,
			Pixel.WHITE if on else Pixel.GRAY)
	if disc_side == 0 and disc_sel < carried.size():
		PixelFont.draw(u, ArcadeDisc.describe(carried[disc_sel]).substr(0, 44),
			14, 210, Pixel.hue(9))
	# right: what this machine can put on a blank
	var writes := _write_options()
	u.rectfill(244, 34, Pixel.UI_W - 8, 224, Pixel.BLACK)
	u.rect(244, 34, Pixel.UI_W - 8, 224, Pixel.hue(9) if disc_side == 1 else Pixel.dark(9))
	PixelFont.draw(u, "WRITE A BLANK (%d spare)" % Inventory.res_count("floppy"),
		250, 38, Pixel.hue(4))
	for i in writes.size():
		var y2 := 58 + i * 16
		var on2: bool = disc_side == 1 and i == disc_sel
		if on2:
			u.rectfill(248, y2 - 3, Pixel.UI_W - 12, y2 + 10, Pixel.dark(11))
		PixelFont.draw(u, str(writes[i][0]).substr(0, 30), 252, y2,
			Pixel.WHITE if on2 else Pixel.GRAY)
	var notes := [
		"a patch from a modular synth loads here",
		"as a playable instrument in the tracker.",
		"",
		"a song will NOT go back the other way:",
		"the song is the notes, the patch is the",
		"machine that made them.",
	]
	for i in notes.size():
		PixelFont.draw(u, str(notes[i]), 250, 130 + i * 11, Pixel.hue(23))
	u.rectfill(0, Pixel.UI_H - 18, Pixel.UI_W, Pixel.UI_H, Pixel.BLACK)
	PixelFont.draw(u, "LEFT/RIGHT SIDE   A READ or WRITE   B BACK", 8,
		Pixel.UI_H - 13, Pixel.hue(23))
