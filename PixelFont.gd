class_name PixelFont
extends RefCounted
## THE CONSOLE'S TYPE. One face is drawn by hand -- 95 glyphs, five
## pixels by seven -- and the rest are cut from it the way a type
## foundry would: emboldened, doubled, sheared, stretched. They are all
## pixel faces and none of them are the same face, so a title screen and
## a tracker row do not have to look alike.
##
## Every glyph is a byte-per-pixel mask. Drawing one is a run of byte
## writes into a Pixel.Layer, which keeps text exactly as on-grid as
## everything else in the machine.

const FIRST := 32
const LAST := 126

## THE RUNES. Not a cipher of our letters -- a script: angular strokes
## with a mark hung under each one, the way the icosahedron colonies
## write. It maps onto ASCII so any string can be rendered in it, and
## nothing in it is a hexagon.
const ALIEN_HEX := "00000000000000040404000400040a0a00000000000a1f0a1f0a04000e1102040004000e1102040004000e11020400040004040000000000060808080600040c0202020c0004150e1f0e15000404041f04040000000000000404080000001f00040000000000000404010204081004000e1315190e0004040c04040e00040c1202041e04001e020c021e040012121e020204001e101c021c040006081c120c04001e0204080804000c120c120c04000c120e020c040000040000040000000400000408000e110204000400001f001f0004000e1102040004000e1102040004000e110204000400040a1115040a111c121c121c040606081012100806181412121418041e101c101e08081e101c121010120e1016120e020411111f11110a040e0404040e0004030101110e040812141814120011101010101e0408111b151111040a111915131108020e1111110e040a1c121c101008120e11110e0402011c121c141200110e100c021c04081f040404040a11111111110e040411110a0a04040a1111151b110a04110a040a11040a110a0404040a111f0204081f040a0e1102040004000e1102040004000e1102040004000e1102040004000e1102040004000e110204000400040a1115040a111c121c121c040606081012100806181412121418041e101c101e08081e101c121010120e1016120e020411111f11110a040e0404040e0004030101110e040812141814120011101010101e0408111b151111040a111915131108020e1111110e040a1c121c101008120e11110e0402011c121c141200110e100c021c04081f040404040a11111111110e040411110a0a04040a1111151b110a04110a040a11040a110a0404040a111f0204081f040a0e1102040004000e1102040004000e1102040004000e110204000400"

## The hand-authored 5x7 master, seven bytes per glyph, low five bits.
const BASE_HEX := "00000000000000040404040400040a0a00000000000a0a1f0a1f0a0a040f140e051e04181902040813030c12140815120d04040000000000020408080804020804020202040800150e1f0e15000004041f040400000000000604080000001f00000000000000000606000102040810000e11131519110e040c040404040e0e11010204081f1f02040201110e02060a121f02021f101e0101110e0608101e11110e1f0102040808080e11110e11110e0e11110f01020c00060600060600000606000604080204081008040200001f001f0000080402010204080e1101020400040e11171517100f040a11111f11111e11111e11111e0e11101010110e1c12111111121c1f10101e10101f1f10101e1010100e11101711110f1111111f1111110e04040404040e0702020202120c111214181412111010101010101f111b1515111111111119151311110e11111111110e1e11111e1010100e11111115120d1e11111e1412110f10100e01011e1f0404040404041111111111110e11111111110a0411111115151b1111110a040a111111110a040404041f01020408101f0e08080808080e001008040201000e02020202020e040a11000000000000000000001f0804000000000000000e010f110f10101e1111111e00000e1010110e01010f1111110f00000e111f100e0609081e080808000f11110f010e10101e1111111104000c0404040e0200060202120c101012141814120c04040404040e00001a1515111100001e1111111100000e1111110e001e11111e1010000f11110f01010000161910101000000f100e011e08081e080809060000111111130d00001111110a040000111115150a0000110a040a11001111110f010e00001f0204081f06040408040406040404040404040c04040204040c00000d12000000"

## Face ids, in the order the editors offer them.
const SYS := 0        # 5x7  -- the system face, everything default
const BOLD := 1       # 6x7  -- emboldened, for headings and buttons
const WIDE := 2       # 10x7 -- doubled across, for logos
const TALL := 3       # 5x14 -- doubled down, a condensed display face
const SLANT := 4      # 8x7  -- sheared, for anything in a hurry
const HUGE := 5       # 12x14 -- bold and doubled both ways: title cards
const TINY := 6       # 4x6  -- for when a line has to fit and nothing else will
const ALIEN := 7      # 5x7  -- the runes they use in the icosahedron towns
const NAMES := ["SYS", "BOLD", "WIDE", "TALL", "SLANT", "HUGE", "TINY", "ALIEN"]

# style flags
const PLAIN := 0
const OUTLINE := 1
const SHADOW := 2

static var _faces: Array = []

class Face extends RefCounted:
	var w: int = 5
	var h: int = 7
	var adv: int = 6          # pen movement per character
	var line_h: int = 9
	var mask := PackedByteArray()   # (LAST-FIRST+1) * w * h, 1 = ink

	func glyph_at(code: int) -> int:
		if code < FIRST or code > LAST:
			code = 63           # '?'
		return (code - FIRST) * w * h

static func faces() -> Array:
	if _faces.size() > 0:
		return _faces
	var base := _build_base()
	_faces = [base, _embolden(base), _stretch(base, 2, 1), _stretch(base, 1, 2),
		_shear(base), _stretch(_embolden(base), 2, 2), _condense(base),
		_from_hex(ALIEN_HEX, 5, 7, 6, 9)]
	return _faces

static func face(id: int) -> Face:
	var f := faces()
	return f[clampi(id, 0, f.size() - 1)]

## Build a face straight from authored data rather than deriving it.
static func _from_hex(data: String, w: int, h: int, adv: int,
		line_h: int) -> Face:
	var f := Face.new()
	f.w = w
	f.h = h
	f.adv = adv
	f.line_h = line_h
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * w * h)
	for gi in n:
		for row in h:
			var byte := data.substr((gi * h + row) * 2, 2).hex_to_int()
			for col in w:
				if (byte & (1 << (w - 1 - col))) != 0:
					f.mask[gi * w * h + row * w + col] = 1
	return f

static func _build_base() -> Face:
	var f := Face.new()
	f.w = 5
	f.h = 7
	f.adv = 6
	f.line_h = 9
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * 5 * 7)
	for gi in n:
		for row in 7:
			var byte := BASE_HEX.substr((gi * 7 + row) * 2, 2).hex_to_int()
			for col in 5:
				if (byte & (1 << (4 - col))) != 0:
					f.mask[gi * 35 + row * 5 + col] = 1
	return f

## Bold: every inked pixel also inks the one to its right. Same shapes,
## heavier stroke, one pixel wider.
static func _embolden(src: Face) -> Face:
	var f := Face.new()
	f.w = src.w + 1
	f.h = src.h
	f.adv = src.adv + 1
	f.line_h = src.line_h
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * f.w * f.h)
	for gi in n:
		for y in src.h:
			for x in src.w:
				if src.mask[gi * src.w * src.h + y * src.w + x] == 0:
					continue
				f.mask[gi * f.w * f.h + y * f.w + x] = 1
				f.mask[gi * f.w * f.h + y * f.w + x + 1] = 1
	return f

## Integer stretch. No filtering, no half pixels -- each source pixel
## becomes a solid block.
static func _stretch(src: Face, sx: int, sy: int) -> Face:
	var f := Face.new()
	f.w = src.w * sx
	f.h = src.h * sy
	f.adv = src.adv * sx
	f.line_h = src.line_h * sy
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * f.w * f.h)
	for gi in n:
		for y in src.h:
			for x in src.w:
				if src.mask[gi * src.w * src.h + y * src.w + x] == 0:
					continue
				for oy in sy:
					for ox in sx:
						f.mask[gi * f.w * f.h + (y * sy + oy) * f.w + x * sx + ox] = 1
	return f

## DUDE TINY: the master squeezed to four by six. The last two columns
## and the last two rows each fold into one, which keeps a stem a stem
## and a bowl a bowl at a size where one wrong pixel is a different
## letter. Five characters fit where four did.
static func _condense(src: Face) -> Face:
	var f := Face.new()
	f.w = 4
	f.h = 6
	f.adv = 5
	f.line_h = 7
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * f.w * f.h)
	for gi in n:
		for y in src.h:
			var ty := y if y < 5 else 5
			for x in src.w:
				if src.mask[gi * src.w * src.h + y * src.w + x] == 0:
					continue
				var tx := x if x < 3 else 3
				f.mask[gi * f.w * f.h + ty * f.w + tx] = 1
	return f

## Italic by shear: the top rows lean right, one pixel every two rows.
static func _shear(src: Face) -> Face:
	var f := Face.new()
	f.w = src.w + 3
	f.h = src.h
	f.adv = src.adv + 1
	f.line_h = src.line_h
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * f.w * f.h)
	for gi in n:
		for y in src.h:
			var off := (src.h - 1 - y) / 2
			for x in src.w:
				if src.mask[gi * src.w * src.h + y * src.w + x] == 0:
					continue
				f.mask[gi * f.w * f.h + y * f.w + x + off] = 1
	return f

# ------------------------------------------------------------- drawing

static func text_width(txt: String, face_id: int = SYS, tracking: int = 0) -> int:
	var f := face(face_id)
	return txt.length() * (f.adv + tracking)

static func line_height(face_id: int = SYS) -> int:
	return face(face_id).line_h

## Draw a string into a layer. `wave` lifts each character on a sine
## (the editors use it for headings), `tracking` opens the letter
## spacing, and style adds an outline or a drop shadow -- both drawn on
## the grid, both a whole pixel.
static func draw(layer, txt: String, x: int, y: int, col: int,
		face_id: int = SYS, style: int = PLAIN, style_col: int = 0,
		tracking: int = 0, wave: float = 0.0, wave_t: float = 0.0) -> int:
	var f := face(face_id)
	var pen := x
	for i in txt.length():
		var code := txt.unicode_at(i)
		if code == 10:
			pen = x
			y += f.line_h
			continue
		var oy := 0
		if wave > 0.0:
			oy = int(round(sin(wave_t + float(i) * 0.6) * wave))
		if style == OUTLINE:
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1],
					[-1, 1], [1, 1]]:
				_glyph(layer, f, code, pen + int(d[0]), y + oy + int(d[1]), style_col)
		elif style == SHADOW:
			_glyph(layer, f, code, pen + 1, y + oy + 1, style_col)
		_glyph(layer, f, code, pen, y + oy, col)
		pen += f.adv + tracking
	return pen - x

static func _glyph(layer, f: Face, code: int, x: int, y: int, col: int) -> void:
	if code == 32:
		return
	layer.glyph(f.mask, f.glyph_at(code), f.w, f.h, x, y, col)

## Centre a string in a box. Used everywhere in the menus, and the
## reason nothing in this machine ever sits on a half pixel.
static func draw_centered(layer, txt: String, cx: int, y: int, col: int,
		face_id: int = SYS, style: int = PLAIN, style_col: int = 0,
		tracking: int = 0) -> void:
	var wid := text_width(txt, face_id, tracking)
	draw(layer, txt, cx - wid / 2, y, col, face_id, style, style_col, tracking)
