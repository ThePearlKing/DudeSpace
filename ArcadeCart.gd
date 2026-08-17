class_name ArcadeCart
extends RefCounted
## ONE CARTRIDGE. Code, art, map, instruments, song, and the little
## patch of memory a game is allowed to keep between sessions. This is
## also exactly what gets written to a floppy: a cart is a dictionary,
## a floppy holds dictionaries, and the disc maker does not care which
## kind it is holding.

const SHEET_W := 256          # sprite sheet is 256x256 indices...
const SHEET_H := 256
const SPR := 16               # ...cut into 16x16 sprites: 256 of them
const SPR_COLS := 16
const MAP_W := 128            # tilemap, in tiles
const MAP_H := 64

var name: String = "UNTITLED"
var author: String = "nobody"
var code: String = ""
var res_mode: int = 1                       # 0 small, 1 normal, 2 big
var sheet := PackedByteArray()              # SHEET_W*SHEET_H palette indices
var flags := PackedByteArray()              # 256 sprites x 8 bits
var map_data := PackedByteArray()           # MAP_W*MAP_H tile ids
var song: Dictionary = {}                   # ChipSong.to_dict()
var sfx: Array = []                         # little one-shot sounds
var data: Dictionary = {}                   # dget/dset persistent memory
var readonly: bool = false                  # the built-ins ship locked

func _init() -> void:
	sheet.resize(SHEET_W * SHEET_H)
	sheet.fill(0)
	flags.resize(256)
	map_data.resize(MAP_W * MAP_H)

## Where sprite n starts in the sheet.
static func spr_x(n: int) -> int:
	return (n % SPR_COLS) * SPR

static func spr_y(n: int) -> int:
	return (n / SPR_COLS) * SPR

func mget(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
		return 0
	return int(map_data[y * MAP_W + x])

func mset(x: int, y: int, t: int) -> void:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
		return
	map_data[y * MAP_W + x] = t & 0xFF

func fget(n: int, bit: int = -1) -> int:
	if n < 0 or n >= 256:
		return 0
	var f := int(flags[n])
	if bit < 0:
		return f
	return 1 if (f & (1 << bit)) != 0 else 0

func fset(n: int, bit: int, on: bool) -> void:
	if n < 0 or n >= 256:
		return
	if bit < 0:
		flags[n] = 0
		return
	if on:
		flags[n] = int(flags[n]) | (1 << bit)
	else:
		flags[n] = int(flags[n]) & ~(1 << bit)

func duplicate_cart() -> ArcadeCart:
	return ArcadeCart.from_dict(to_dict())

# ---------------------------------------------------------- persistence

## Run-length encode a byte array, then base64 it. Sprite sheets are
## mostly one colour, so this turns 64KB of mostly-zero into a few
## hundred bytes -- which matters, because these ride along in the save
## file and on every floppy.
static func rle_encode(src: PackedByteArray) -> String:
	var out := PackedByteArray()
	var i := 0
	var n := src.size()
	while i < n:
		var v := src[i]
		var run := 1
		while i + run < n and src[i + run] == v and run < 255:
			run += 1
		out.append(v)
		out.append(run)
		i += run
	return Marshalls.raw_to_base64(out)

static func rle_decode(b64: String, expect: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(expect)
	out.fill(0)
	var raw := Marshalls.base64_to_raw(b64)
	var w := 0
	var i := 0
	while i + 1 < raw.size() and w < expect:
		var v := raw[i]
		var run := int(raw[i + 1])
		for k in run:
			if w >= expect:
				break
			out[w] = v
			w += 1
		i += 2
	return out

func to_dict() -> Dictionary:
	return {
		"kind": "cart",
		"name": name,
		"author": author,
		"code": code,
		"res": res_mode,
		"sheet": rle_encode(sheet),
		"flags": rle_encode(flags),
		"map": rle_encode(map_data),
		"song": song.duplicate(true),
		"sfx": sfx.duplicate(true),
		"data": data.duplicate(true),
	}

static func from_dict(d: Dictionary) -> ArcadeCart:
	var c := ArcadeCart.new()
	c.name = str(d.get("name", "UNTITLED"))
	c.author = str(d.get("author", "nobody"))
	c.code = str(d.get("code", ""))
	c.res_mode = int(d.get("res", 1))
	if d.has("sheet"):
		c.sheet = rle_decode(str(d["sheet"]), SHEET_W * SHEET_H)
	if d.has("flags"):
		c.flags = rle_decode(str(d["flags"]), 256)
	if d.has("map"):
		c.map_data = rle_decode(str(d["map"]), MAP_W * MAP_H)
	var sg = d.get("song", {})
	c.song = (sg as Dictionary).duplicate(true) if sg is Dictionary else {}
	var sx = d.get("sfx", [])
	c.sfx = (sx as Array).duplicate(true) if sx is Array else []
	var dd = d.get("data", {})
	c.data = (dd as Dictionary).duplicate(true) if dd is Dictionary else {}
	return c

## A blank cart with enough of a program on it that RUN does something.
static func blank(nm: String = "NEW CART") -> ArcadeCart:
	var c := ArcadeCart.new()
	c.name = nm
	c.code = """-- a new cartridge.
-- _init runs once, _update runs every frame, _draw paints.

function _init()
  x = 60
  y = 60
end

function _update()
  if btn(0) then x = x - 2 end
  if btn(1) then x = x + 2 end
  if btn(2) then y = y - 2 end
  if btn(3) then y = y + 2 end
end

function _draw()
  cls(38)
  circfill(x, y, 8, 14)
  print("hello. arrows move.", 8, 8, 1)
end
"""
	return c
