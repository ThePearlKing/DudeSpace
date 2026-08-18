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

## THE ICOSAHEDRON SCRIPT. Not our letters in a costume: every glyph is
## an enclosed sigil -- a box, a diamond, a wedge, an arch, a vessel or a
## ladder -- with ticks set inside it and a foot or a hook attached. No
## glyph shares a skeleton with any letter of ours, which is the whole
## point: you can see that it says something, and you cannot read it.
const ALIEN_HEX := "00000000000000040004000400040a0a00000000000a1f0a1f0a0000180e0a0e0a0e001c0a1115110a0418040a151f000004040000000000060808080808060c02020202020c150e1f0e15000004041f041f0000000000000408000000001f0000000000000400000001020408100000040a1911130a04000e0a0a0a0e00000a0e0a0e0a04000a1115110e04001f0a0e0a0a0400040e151f000e040a1315190a0e180e0a0a0a0e00180a0e0a0e0a00030a1111110e000004000004000000040004080000040e0a0a0a0e00001f001f001f0004040a111f00000e110600040000040a1911130e00040a1515150a0400040a111f000e040a1315190e00030a0e0e0e0a00001f0a0e0a0a00040a1115110a04000a0e0e0e0a041c0a111f110a04000a0e0e0e0a0e030a111f110e00180e0a0e0a0e00030e0e0e0e0e0000040a111f0000000a1911130e0e000e0a0e0a0e04000e0a0e0a0e04041f0e0e0e0a0018040a151f0000181f0a0a0a0a0000040a1f1f0000041f0a0a0a0a001c0a1111110a04000a1515150e0e030a0e0e0e0a00001f0a0e0a0a0e04040a151f0000040a1315190a0e00040a151f000e001f0a0e0a0a0e000a1315190e0e000a0e0e0e0a0e000e0a0a0a0e0e040a1515150a0400040a111f000e040a1315190e00030a0e0e0e0a00001f0a0e0a0a00040a1115110a04000a0e0e0e0a041c0a111f110a04000a0e0e0e0a0e030a111f110e00180e0a0e0a0e00030e0e0e0e0e0000040a111f0000000a1911130e0e000e0a0e0a0e04000e0a0e0a0e04041f0e0e0e0a0018040a151f0000181f0a0a0a0a0000040a1f1f0000041f0a0a0a0a001c0a1111110a04000a1515150e0e030a0e0e0e0a00001f0a0e0a0a0e04040a151f0000041f0e0e0e0a00040a1515150e00040a0e0e0e0a00040e0a0e0a0e00"

## DUDE TINY, authored at three by five rather than squeezed down from
## the master: at this size a squeezed glyph is mush, and a drawn one
## still reads.
const TINY_HEX := "00000000000202020002050500000005070507050601020002050102040506010200020202000000010202020104020202040502070205000207020000000002040000070000000000000201010204040205050502020602020706010204070601020106050507010107040601060304060502070102020202050205020205030106000200020000020002040102040201000700070004020102040601020002060102000202050705050605060506030404040306050505060704060407070406040403040505030505070505070202020701010105020505060505040404040705070705050507070705020505050206050604040205050603060506050503040201060702020202050505050205050502020505070705050502050505050202020701020407030202020306010200020602020206060102000200000000070601020002020507050506050605060304040403060505050607040604070704060404030405050305050705050702020207010101050205050605050404040407050707050505070707050205050502060506040402050506030605060505030402010607020202020505050502050505020205050707050505020505050502020207010204070601020002020202020206010200020601020002"

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

## THE ALIEN SCRIPT IS NOT A CIPHER. A one-glyph-per-letter face still
## reads as English in a costume: same word shapes, same letter count,
## same spacing. So this script behaves like a script -- each rune has
## three contextual forms and which one appears depends on where it sits
## in the word and what it follows, certain pairs fuse into a single
## wider rune so the letter count stops matching, and runes inside a word
## are joined by a spine. Two different words that use the same letters
## do not come out looking the same.
static var _alien_forms: Array = []

static func alien_forms() -> Array:
	if not _alien_forms.is_empty():
		return _alien_forms
	var base := _from_hex(ALIEN_HEX, 5, 7, 6, 9)
	_alien_forms = [base, _alien_variant(base, 1), _alien_variant(base, 2)]
	return _alien_forms

## A second and third form of every rune: the same hand, writing the same
## sound in a different position. Not noise -- the stem stays, the
## strokes move.
static func _alien_variant(src: Face, which: int) -> Face:
	var f := Face.new()
	f.w = src.w
	f.h = src.h
	f.adv = src.adv
	f.line_h = src.line_h
	var n := (LAST - FIRST + 1)
	f.mask.resize(n * f.w * f.h)
	for gi in n:
		for y in src.h:
			for x in src.w:
				if src.mask[gi * src.w * src.h + y * src.w + x] == 0:
					continue
				var ty := y
				var tx := x
				if which == 1:
					ty = src.h - 1 - y            # written upside down
				else:
					tx = src.w - 1 - x            # written mirrored
				f.mask[gi * f.w * f.h + ty * f.w + tx] = 1
		# and a mark that only this form carries
		if which == 1:
			f.mask[gi * f.w * f.h + 0 * f.w + 0] = 1
		else:
			f.mask[gi * f.w * f.h + (src.h - 1) * f.w + (src.w - 1)] = 1
	return f

static func faces() -> Array:
	if _faces.size() > 0:
		return _faces
	var base := _build_base()
	_faces = [base, _embolden(base), _stretch(base, 2, 1), _stretch(base, 1, 2),
		_shear(base), _stretch(_embolden(base), 2, 2),
		_from_hex(TINY_HEX, 3, 5, 4, 6),
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
	if face_id == ALIEN:
		# fused pairs make alien text shorter than its letter count
		var wdt := 0
		var i := 0
		while i < txt.length():
			var code := txt.unicode_at(i)
			var nxt := txt.unicode_at(i + 1) if i + 1 < txt.length() else 0
			if code == 32:
				wdt += 5 + tracking
				i += 1
				continue
			if nxt > 32 and ((code * 7 + nxt * 3) % 5 == 0):
				wdt += f.adv + 2 + tracking
				i += 2
				continue
			wdt += f.adv + tracking
			i += 1
		return wdt
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
	if face_id == ALIEN:
		return _draw_alien(layer, txt, x, y, col, tracking)
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

## Writing, rather than substituting. Runes take their form from where
## they sit, some pairs fuse, and a word is joined along a spine.
static func _draw_alien(layer, txt: String, x: int, y: int, col: int,
		tracking: int) -> int:
	var forms := alien_forms()
	var pen := x
	var i := 0
	var word_pos := 0
	var prev := 0
	while i < txt.length():
		var code := txt.unicode_at(i)
		if code == 10:
			pen = x
			y += 10
			word_pos = 0
			prev = 0
			i += 1
			continue
		if code == 32:
			pen += 5 + tracking
			word_pos = 0
			prev = 0
			i += 1
			continue
		var nxt := txt.unicode_at(i + 1) if i + 1 < txt.length() else 0
		# a pair that fuses: one rune carries both sounds, so the word
		# stops having the same number of marks as the English did
		var fused: bool = nxt > 32 and ((code * 7 + nxt * 3) % 5 == 0)
		var form: int = (code + word_pos * 2 + prev) % 3
		var fa: Face = forms[form]
		_glyph(layer, fa, code, pen, y, col)
		if fused:
			var fb: Face = forms[(form + 1) % 3]
			_glyph(layer, fb, nxt, pen + 2, y + 1, col)
			i += 1
		# the spine: runes inside a word are written joined
		if word_pos > 0:
			layer.pset(pen - 1, y + 3, col)
			layer.pset(pen - 2, y + 3, col)
		pen += fa.adv + (2 if fused else 0) + tracking
		word_pos += 1
		prev = code
		i += 1
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
