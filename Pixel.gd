class_name Pixel
extends RefCounted
## THE DUDE-16 RASTER. Everything an arcade cabinet draws goes through
## here: indexed byte layers, one palette, and no floating point anywhere
## near a pixel. Nothing in the console -- not a game, not the menu, not
## the tracker -- can land between two pixels, because a pixel is a byte
## index and there is nowhere between two bytes to land.
##
## Layers are composited on the GPU: each is uploaded as an R8 texture,
## and one shader looks every index up in a 256x1 palette strip. That is
## what makes a full-screen palette fade, a flash, or a scrolling
## background cost nothing on the CPU.

## 255 is "nothing here" -- the layer above shows through.
const CLEAR := 255

## The screen the CONSOLE itself always uses. Cartridges pick their own
## (see ArcadeConsole.RES_MODES); this is the one the menus, the editors
## and every bit of chrome are drawn at, so the UI never changes size.
const UI_W := 480
const UI_H := 270

# ------------------------------------------------------------- palette
## Black, white, and twenty-four hues -- each hue in a dark, a base and
## a light, so anything drawn has somewhere to shade and somewhere to
## highlight without leaving the palette.
const HUES := [
	["red", "#e43b44"], ["rose", "#ff5c7c"], ["orange", "#f77622"],
	["amber", "#feae34"], ["yellow", "#fee761"], ["lime", "#b6d53c"],
	["green", "#3ea24a"], ["emerald", "#1ebc73"], ["teal", "#0b8a8f"],
	["cyan", "#26c2cd"], ["sky", "#4fa4ff"], ["azure", "#285cc4"],
	["blue", "#1a34c9"], ["indigo", "#5a3fd6"], ["violet", "#8b5ce8"],
	["purple", "#b04ad6"], ["magenta", "#e14bd6"], ["pink", "#ff89c9"],
	["brown", "#8a4836"], ["tan", "#c98f6a"], ["sand", "#e4c9a0"],
	["olive", "#6f7c2a"], ["slate", "#4b5b78"], ["gray", "#97a3b6"],
]

const BLACK := 0
const WHITE := 1
## Index of the base tone of hue `i` (0-23). Dark is +1, light is +2.
static func hue(i: int) -> int:
	return 2 + (i % HUES.size()) * 3

static func dark(i: int) -> int:
	return hue(i) + 1

static func light(i: int) -> int:
	return hue(i) + 2

## Named shortcuts, so console code reads like colour and not arithmetic.
const RED := 2
const ROSE := 5
const ORANGE := 8
const AMBER := 11
const YELLOW := 14
const LIME := 17
const GREEN := 20
const EMERALD := 23
const TEAL := 26
const CYAN := 29
const SKY := 32
const AZURE := 35
const BLUE := 38
const INDIGO := 41
const VIOLET := 44
const PURPLE := 47
const MAGENTA := 50
const PINK := 53
const BROWN := 56
const TAN := 59
const SAND := 62
const OLIVE := 65
const SLATE := 68
const GRAY := 71

static var _pal_colors: PackedColorArray = PackedColorArray()

## The whole palette as colours, index 0..73. Built once.
static func colors() -> PackedColorArray:
	if _pal_colors.size() > 0:
		return _pal_colors
	var out := PackedColorArray()
	out.append(Color("#0b0b10"))          # 0: black, but not a dead black
	out.append(Color("#fdfdf5"))          # 1: white, slightly warm
	for h in HUES:
		var base := Color(str(h[1]))
		out.append(base)
		out.append(base.darkened(0.38).lerp(Color("#0b0b18"), 0.18))
		out.append(base.lightened(0.36).lerp(Color("#fffdf0"), 0.12))
	_pal_colors = out
	return out

static func color_count() -> int:
	return colors().size()

## The palette as a 256x1 texture for the composite shader. `shift` is a
## palette remap (index -> index) so a cartridge can fade or flash the
## whole screen without touching a single pixel.
static func palette_image(remap: PackedByteArray = PackedByteArray()) -> Image:
	var cols := colors()
	var img := Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
	for i in 256:
		var src := i
		if remap.size() == 256:
			src = int(remap[i])
		if src < cols.size():
			img.set_pixel(i, 0, cols[src])
		elif i == CLEAR:
			img.set_pixel(i, 0, Color(0, 0, 0, 0))
		else:
			img.set_pixel(i, 0, Color(0, 0, 0, 0))
	img.set_pixel(CLEAR, 0, Color(0, 0, 0, 0))
	return img

# ================================================================ layer

## One indexed drawing surface. All the console's drawing lands here.
class Layer extends RefCounted:
	var w: int = 480
	var h: int = 270
	var buf := PackedByteArray()
	## Everything drawn is offset by this (the camera). Integers only.
	var cam_x: int = 0
	var cam_y: int = 0
	## Clip rectangle, in screen pixels.
	var cx: int = 0
	var cy: int = 0
	var cw: int = 480
	var ch: int = 270
	## Colour remap for sprite blits (pal()), and which index is see-through.
	var pal_map := PackedByteArray()
	var transparent: int = 0

	func _init(width: int = 480, height: int = 270, fill_with: int = CLEAR) -> void:
		w = width
		h = height
		buf.resize(w * h)
		buf.fill(fill_with)
		cw = w
		ch = h
		reset_pal()

	func reset_pal() -> void:
		pal_map.resize(256)
		for i in 256:
			pal_map[i] = i
		transparent = 0

	func resize(width: int, height: int) -> void:
		if width == w and height == h:
			return
		w = width
		h = height
		buf.resize(w * h)
		buf.fill(CLEAR)
		clip_reset()

	func clip(x: int, y: int, width: int, height: int) -> void:
		cx = maxi(0, x)
		cy = maxi(0, y)
		cw = mini(w - cx, width)
		ch = mini(h - cy, height)

	func clip_reset() -> void:
		cx = 0
		cy = 0
		cw = w
		ch = h

	func camera(x: int, y: int) -> void:
		cam_x = x
		cam_y = y

	## Whole-surface fill. One native memset -- this is why cls() is free.
	func clear(idx: int = CLEAR) -> void:
		buf.fill(idx)

	func pset(x: int, y: int, idx: int) -> void:
		var px := x - cam_x
		var py := y - cam_y
		if px < cx or py < cy or px >= cx + cw or py >= cy + ch:
			return
		buf[py * w + px] = idx

	func pget(x: int, y: int) -> int:
		var px := x - cam_x
		var py := y - cam_y
		if px < 0 or py < 0 or px >= w or py >= h:
			return 0
		return int(buf[py * w + px])

	## Horizontal run. Every filled shape in here bottoms out in this.
	func hline(x0: int, x1: int, y: int, idx: int) -> void:
		var py := y - cam_y
		if py < cy or py >= cy + ch:
			return
		var a := mini(x0, x1) - cam_x
		var b := maxi(x0, x1) - cam_x
		a = maxi(a, cx)
		b = mini(b, cx + cw - 1)
		if a > b:
			return
		var row := py * w
		for x in range(a, b + 1):
			buf[row + x] = idx

	func vline(x: int, y0: int, y1: int, idx: int) -> void:
		var px := x - cam_x
		if px < cx or px >= cx + cw:
			return
		var a := maxi(mini(y0, y1) - cam_y, cy)
		var b := mini(maxi(y0, y1) - cam_y, cy + ch - 1)
		for y in range(a, b + 1):
			buf[y * w + px] = idx

	func rectfill(x: int, y: int, x2: int, y2: int, idx: int) -> void:
		var y0 := mini(y, y2)
		var y1 := maxi(y, y2)
		var a := maxi(mini(x, x2) - cam_x, cx)
		var b := mini(maxi(x, x2) - cam_x, cx + cw - 1)
		var ya := maxi(y0 - cam_y, cy)
		var yb := mini(y1 - cam_y, cy + ch - 1)
		if a > b or ya > yb:
			return
		var span := b - a + 1
		if span * (yb - ya + 1) < 20000:
			for yy in range(ya, yb + 1):
				var row := yy * w
				for xx in range(a, b + 1):
					buf[row + xx] = idx
			return
		# big fill: work through a local alias so the writes stop going
		# through a member lookup. Worth the one copy-on-write above
		# twenty thousand pixels, never below it.
		var arr := buf
		for yy in range(ya, yb + 1):
			var row2 := yy * w
			for xx in range(a, b + 1):
				arr[row2 + xx] = idx
		buf = arr

	func rect(x: int, y: int, x2: int, y2: int, idx: int) -> void:
		hline(x, x2, y, idx)
		hline(x, x2, y2, idx)
		vline(x, y, y2, idx)
		vline(x2, y, y2, idx)

	## Bresenham, so a diagonal is a run of pixels and not a smear.
	func line(x0: int, y0: int, x1: int, y1: int, idx: int) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var e := dx + dy
		var x := x0
		var y := y0
		while true:
			pset(x, y, idx)
			if x == x1 and y == y1:
				break
			var e2 := e * 2
			if e2 >= dy:
				e += dy
				x += sx
			if e2 <= dx:
				e += dx
				y += sy

	func circ(xm: int, ym: int, r: int, idx: int) -> void:
		if r <= 0:
			pset(xm, ym, idx)
			return
		var x := -r
		var y := 0
		var e := 2 - 2 * r
		while x < 0:
			pset(xm - x, ym + y, idx)
			pset(xm - y, ym - x, idx)
			pset(xm + x, ym - y, idx)
			pset(xm + y, ym + x, idx)
			r = e
			if r <= y:
				y += 1
				e += y * 2 + 1
			if r > x or e > y:
				x += 1
				e += x * 2 + 1

	func circfill(xm: int, ym: int, r: int, idx: int) -> void:
		if r <= 0:
			pset(xm, ym, idx)
			return
		for dy in range(-r, r + 1):
			var dx := int(sqrt(float(r * r - dy * dy)))
			hline(xm - dx, xm + dx, ym + dy, idx)

	## Flat-filled triangle, scanline style. The three points are sorted
	## by hand: this gets called a few hundred times a frame by anything
	## drawing a road or a fan, and an Array plus a sort lambda per call
	## costs more than the fill does.
	func trifill(x0: int, y0: int, x1: int, y1: int, x2: int, y2: int,
			idx: int) -> void:
		var ax := x0
		var ay := y0
		var bx := x1
		var by := y1
		var cx2 := x2
		var cy2 := y2
		var t := 0
		if ay > by:
			t = ax
			ax = bx
			bx = t
			t = ay
			ay = by
			by = t
		if by > cy2:
			t = bx
			bx = cx2
			cx2 = t
			t = by
			by = cy2
			cy2 = t
		if ay > by:
			t = ax
			ax = bx
			bx = t
			t = ay
			ay = by
			by = t
		if cy2 == ay:
			hline(mini(ax, mini(bx, cx2)), maxi(ax, maxi(bx, cx2)), ay, idx)
			return
		# clip vertically before walking the scanlines
		var y_from := maxi(ay, cy + cam_y)
		var y_to := mini(cy2, cy + ch - 1 + cam_y)
		var long_dx := float(cx2 - ax) / float(cy2 - ay)
		for y in range(y_from, y_to + 1):
			var xa := ax + int(float(y - ay) * long_dx)
			var xb := 0
			if y < by:
				xb = ax if by == ay else ax + int(float(x1 - x0) * 0.0) \
					+ int(float(bx - ax) * float(y - ay) / float(by - ay))
			else:
				xb = bx if cy2 == by else bx \
					+ int(float(cx2 - bx) * float(y - by) / float(cy2 - by))
			hline(xa, xb, y, idx)

	static func _edge(x0: int, y0: int, x1: int, y1: int, y: int) -> int:
		if y1 == y0:
			return x1
		return x0 + int(float(x1 - x0) * float(y - y0) / float(y1 - y0))

	## Copy a rectangle out of a sprite sheet. This is the workhorse:
	## every sprite, tile and glyph in the console arrives through it.
	func blit(src: PackedByteArray, src_w: int, sx: int, sy: int,
			bw: int, bh: int, dx: int, dy: int, flip_x: bool = false,
			flip_y: bool = false, use_pal: bool = true) -> void:
		var px := dx - cam_x
		var py := dy - cam_y
		var x_from := maxi(0, cx - px)
		var y_from := maxi(0, cy - py)
		var x_to := mini(bw, cx + cw - px)
		var y_to := mini(bh, cy + ch - py)
		if x_from >= x_to or y_from >= y_to:
			return
		var tr := transparent
		var pm := pal_map
		for yy in range(y_from, y_to):
			var syy := (bh - 1 - yy) if flip_y else yy
			var srow := (sy + syy) * src_w + sx
			var drow := (py + yy) * w + px
			for xx in range(x_from, x_to):
				var sxx := (bw - 1 - xx) if flip_x else xx
				var v := int(src[srow + sxx])
				if v == tr:
					continue
				buf[drow + xx] = int(pm[v]) if use_pal else v

	## Stretched blit -- integer scale only, so it stays on the grid.
	func blit_scaled(src: PackedByteArray, src_w: int, sx: int, sy: int,
			bw: int, bh: int, dx: int, dy: int, scale: int,
			flip_x: bool = false, flip_y: bool = false) -> void:
		if scale <= 1:
			blit(src, src_w, sx, sy, bw, bh, dx, dy, flip_x, flip_y)
			return
		var tr := transparent
		for yy in bh:
			var syy := (bh - 1 - yy) if flip_y else yy
			for xx in bw:
				var sxx := (bw - 1 - xx) if flip_x else xx
				var v := int(src[(sy + syy) * src_w + sx + sxx])
				if v == tr:
					continue
				rectfill(dx + xx * scale, dy + yy * scale,
					dx + xx * scale + scale - 1, dy + yy * scale + scale - 1,
					int(pal_map[v]))

	## One call per character instead of one per pixel: the font hands
	## over a glyph mask and this walks it inline. Text is most of what
	## the editors draw, so this is the difference between a workshop
	## that keeps up and one that does not.
	func glyph(mask: PackedByteArray, base: int, gw: int, gh: int,
			x: int, y: int, col: int) -> void:
		var px := x - cam_x
		var py := y - cam_y
		var x_from := maxi(0, cx - px)
		var y_from := maxi(0, cy - py)
		var x_to := mini(gw, cx + cw - px)
		var y_to := mini(gh, cy + ch - py)
		if x_from >= x_to or y_from >= y_to:
			return
		for gy in range(y_from, y_to):
			var mrow := base + gy * gw
			var drow := (py + gy) * w + px
			for gx in range(x_from, x_to):
				if mask[mrow + gx] != 0:
					buf[drow + gx] = col

	## Copy this whole layer out (for undo stacks and screen wipes).
	func snapshot() -> PackedByteArray:
		return buf.duplicate()

	func restore(snap: PackedByteArray) -> void:
		if snap.size() == buf.size():
			buf = snap.duplicate()

	## Scroll the contents. Used by the editors' transitions.
	func scroll(dx: int, dy: int, fill_with: int = CLEAR) -> void:
		var old := buf.duplicate()
		buf.fill(fill_with)
		for y in h:
			var sy := y - dy
			if sy < 0 or sy >= h:
				continue
			for x in w:
				var sx := x - dx
				if sx < 0 or sx >= w:
					continue
				buf[y * w + x] = old[sy * w + sx]

	## Dissolve: knock out pixels on a deterministic pattern. The console
	## uses it for wipes between editor tabs.
	func dissolve(amount: float, seed_v: int = 1) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var n := buf.size()
		for i in n:
			if rng.randf() < amount:
				buf[i] = CLEAR

	func to_image() -> Image:
		return Image.create_from_data(w, h, false, Image.FORMAT_R8, buf)
