class_name ArcadeEngine
extends RefCounted
## THE ENGINE HALF OF THE MACHINE. The console underneath is a raster --
## cls, spr, print -- and writing a game against that alone means
## writing collision, gravity, camera follow and animation by hand every
## single time. Nobody should have to. This is the layer that means you
## do not:
##
##   p = add{x=60, y=40, w=12, h=16, spr=4, tag="player", gravity=true}
##   add{x=0, y=200, w=480, h=16, static=true, tag="ground"}
##   function _update()
##     p.vx = (btn(1) and 2 or 0) - (btn(0) and 2 or 0)
##     if btnp(4) and p.grounded then p.vy = -7 end
##   end
##
## and that is a platformer with real collision, on real hitboxes, that
## you did not write. Entities are plain Lua tables: the host reads the
## fields it knows (x, y, w, h, vx, vy, spr, tag...) and leaves every
## other field on them alone, so your own state lives on the same object.
##
## Everything here is optional. A cartridge that wants to do it all by
## hand still can -- the raw API has not moved.

const FIELDS := ["x", "y", "w", "h", "vx", "vy", "ax", "ay", "spr", "sw", "sh",
	"flip", "tag", "solid", "static", "gravity", "bounce", "friction",
	"grounded", "alive", "layer", "visible", "anim", "afps", "aframe",
	"maxvx", "maxvy", "hitw", "hith", "ox", "oy"]

var con = null                       # ArcadeConsole
var ents: Array = []                 # Array[LuaVM.Table]
var gravity: float = 0.0
var drag: float = 1.0
var cam_target = null
var cam_lerp: float = 0.12
var cam_x: float = 0.0
var cam_y: float = 0.0
var cam_bx0: float = -1e9
var cam_by0: float = -1e9
var cam_bx1: float = 1e9
var cam_by1: float = 1e9
var solid_flag: int = 0              # sprite flag that makes a tile solid
var tile_size: int = 16
var timers: Array = []
var tweens: Array = []
var parts: Array = []
var _vm: LuaVM = null

func setup(console, vm: LuaVM) -> void:
	con = console
	_vm = vm

func reset() -> void:
	ents.clear()
	timers.clear()
	tweens.clear()
	parts.clear()
	cam_target = null
	cam_x = 0.0
	cam_y = 0.0
	gravity = 0.0
	drag = 1.0

# ------------------------------------------------------------- helpers

static func gf(t, key: String, d: float) -> float:
	var v = (t as LuaVM.Table).rawget(key)
	if v is float:
		return v
	if v is int:
		return float(v)
	return d

static func gb(t, key: String, d: bool) -> bool:
	var v = (t as LuaVM.Table).rawget(key)
	if v == null:
		return d
	if v is bool:
		return v
	return true

static func gs(t, key: String, d: String) -> String:
	var v = (t as LuaVM.Table).rawget(key)
	return str(v) if v != null else d

static func sf(t, key: String, v) -> void:
	(t as LuaVM.Table).rawset(key, v)

## The hitbox of an entity: its own w/h unless it carries a smaller
## hitw/hith, offset by ox/oy. A sprite is often bigger than the part of
## it that should hurt you.
static func box(t) -> Rect2:
	var x := gf(t, "x", 0.0) + gf(t, "ox", 0.0)
	var y := gf(t, "y", 0.0) + gf(t, "oy", 0.0)
	var w := gf(t, "hitw", gf(t, "w", 8.0))
	var h := gf(t, "hith", gf(t, "h", 8.0))
	return Rect2(x, y, w, h)

# ------------------------------------------------------------ the frame

## Runs before the cartridge's _update: timers, tweens and particles are
## the machine's business, not the game's.
func pre_update(dt: float) -> void:
	for i in range(timers.size() - 1, -1, -1):
		var tm: Dictionary = timers[i]
		tm["t"] = float(tm["t"]) - dt
		if float(tm["t"]) <= 0.0:
			var fn = tm["fn"]
			if bool(tm.get("repeat", false)):
				tm["t"] = float(tm["every"])
			else:
				timers.remove_at(i)
			if _vm != null and fn != null:
				_vm.call_value(fn, [])
	for i in range(tweens.size() - 1, -1, -1):
		var tw: Dictionary = tweens[i]
		tw["t"] = float(tw["t"]) + dt
		var k: float = clampf(float(tw["t"]) / maxf(0.001, float(tw["dur"])), 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)          # smoothstep, always
		var obj = tw["obj"]
		if obj is LuaVM.Table:
			sf(obj, str(tw["key"]), lerpf(float(tw["from"]), float(tw["to"]), e))
		if k >= 1.0:
			tweens.remove_at(i)

## Runs after it: physics, collision, animation, camera, particles.
func post_update(dt: float) -> void:
	for i in range(ents.size() - 1, -1, -1):
		var e = ents[i]
		if not (e is LuaVM.Table) or not gb(e, "alive", true):
			ents.remove_at(i)
			continue
		if gb(e, "static", false):
			continue
		_step_ent(e, dt)
	_animate(dt)
	_camera(dt)
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p["x"] = float(p["x"]) + float(p["vx"])
		p["y"] = float(p["y"]) + float(p["vy"])
		p["vy"] = float(p["vy"]) + float(p.get("g", 0.0))
		p["life"] = float(p["life"]) - 1.0
		if float(p["life"]) <= 0.0:
			parts.remove_at(i)

func _step_ent(e, _dt: float) -> void:
	var vx := gf(e, "vx", 0.0)
	var vy := gf(e, "vy", 0.0)
	vx += gf(e, "ax", 0.0)
	vy += gf(e, "ay", 0.0)
	if gb(e, "gravity", false):
		vy += gravity
	var fr := gf(e, "friction", 1.0) * drag
	if fr != 1.0:
		vx *= fr
	var mx := gf(e, "maxvx", 1e9)
	var my := gf(e, "maxvy", 1e9)
	vx = clampf(vx, -mx, mx)
	vy = clampf(vy, -my, my)
	sf(e, "grounded", false)
	# move on each axis separately, so a slide along a wall still slides
	_move_axis(e, vx, 0.0)
	_move_axis(e, 0.0, vy)
	sf(e, "vx", gf(e, "vx", vx))
	sf(e, "vy", gf(e, "vy", vy))

func _move_axis(e, dx: float, dy: float) -> void:
	if dx == 0.0 and dy == 0.0:
		return
	var steps := maxi(1, int(ceil(maxf(absf(dx), absf(dy)) / 4.0)))
	var sx := dx / float(steps)
	var sy := dy / float(steps)
	var wants_solid := gb(e, "solid", true)
	for s in steps:
		sf(e, "x", gf(e, "x", 0.0) + sx)
		sf(e, "y", gf(e, "y", 0.0) + sy)
		if not wants_solid:
			continue
		var hit = _blocked(e)
		if hit == null:
			continue
		# back out of whatever we walked into and kill that axis
		sf(e, "x", gf(e, "x", 0.0) - sx)
		sf(e, "y", gf(e, "y", 0.0) - sy)
		if sy > 0.0:
			sf(e, "grounded", true)
		if dx != 0.0:
			sf(e, "vx", 0.0)
			if gb(e, "bounce", false):
				sf(e, "vx", -gf(e, "vx", 0.0) * gf(e, "bounce_k", 0.6))
		else:
			sf(e, "vy", 0.0)
			if gb(e, "bounce", false):
				sf(e, "vy", -gf(e, "vy", 0.0) * gf(e, "bounce_k", 0.6))
		if hit is LuaVM.Table and _vm != null:
			var cb = (e as LuaVM.Table).rawget("on_hit")
			if cb != null:
				_vm.call_value(cb, [e, hit])
		return

## What, if anything, this entity is standing in: a solid tile or
## another solid entity.
func _blocked(e):
	var b := box(e)
	if solid_flag >= 0 and con != null and con.cart != null:
		var t0x := int(floor(b.position.x / float(tile_size)))
		var t0y := int(floor(b.position.y / float(tile_size)))
		var t1x := int(floor((b.position.x + b.size.x - 1) / float(tile_size)))
		var t1y := int(floor((b.position.y + b.size.y - 1) / float(tile_size)))
		for ty in range(t0y, t1y + 1):
			for tx in range(t0x, t1x + 1):
				var tile: int = con.cart.mget(tx, ty)
				if tile != 0 and con.cart.fget(tile, solid_flag) != 0:
					return true
	for o in ents:
		if o == e or not (o is LuaVM.Table):
			continue
		if not gb(o, "solid", true) or not gb(o, "alive", true):
			continue
		if not gb(o, "static", false) and not gb(o, "blocks", false):
			continue                    # only static or explicit blockers stop you
		if b.intersects(box(o)):
			return o
	return null

func _animate(dt: float) -> void:
	for e in ents:
		if not (e is LuaVM.Table):
			continue
		var an = (e as LuaVM.Table).rawget("anim")
		if not (an is LuaVM.Table):
			continue
		var frames: Array = (an as LuaVM.Table).to_array()
		if frames.is_empty():
			continue
		var fps := gf(e, "afps", 8.0)
		var f := gf(e, "aframe", 0.0) + fps * dt
		if f >= float(frames.size()):
			f = fmod(f, float(frames.size()))
		sf(e, "aframe", f)
		sf(e, "spr", frames[int(f) % frames.size()])

func _camera(dt: float) -> void:
	if cam_target == null or not (cam_target is LuaVM.Table):
		return
	var b := box(cam_target)
	var want_x := b.position.x + b.size.x * 0.5 - float(con.game_w) * 0.5
	var want_y := b.position.y + b.size.y * 0.5 - float(con.game_h) * 0.5
	var k := clampf(cam_lerp * dt * 60.0, 0.0, 1.0)
	cam_x = lerpf(cam_x, want_x, k)
	cam_y = lerpf(cam_y, want_y, k)
	cam_x = clampf(cam_x, cam_bx0, maxf(cam_bx0, cam_bx1 - float(con.game_w)))
	cam_y = clampf(cam_y, cam_by0, maxf(cam_by0, cam_by1 - float(con.game_h)))

# --------------------------------------------------------------- drawing

## Draw every entity that has a sprite, back layer first, with the
## camera applied. A cartridge that wants to paint its own can skip it.
func draw_all() -> void:
	var order := ents.duplicate()
	order.sort_custom(func(a, b): return gf(a, "layer", 0.0) < gf(b, "layer", 0.0))
	con._target.camera(int(round(cam_x)), int(round(cam_y)))
	for e in order:
		if not (e is LuaVM.Table) or not gb(e, "visible", true):
			continue
		var sp := int(gf(e, "spr", -1.0))
		if sp < 0:
			continue
		var sw := maxi(1, int(gf(e, "sw", 1.0)))
		var sh := maxi(1, int(gf(e, "sh", 1.0)))
		con._target.blit(con.cart.sheet, ArcadeCart.SHEET_W,
			ArcadeCart.spr_x(sp), ArcadeCart.spr_y(sp),
			sw * ArcadeCart.SPR, sh * ArcadeCart.SPR,
			int(round(gf(e, "x", 0.0))), int(round(gf(e, "y", 0.0))),
			gb(e, "flip", false), gb(e, "flipy", false))
	for p in parts:
		con._target.pset(int(p["x"]), int(p["y"]), int(p["c"]))

## Every hitbox, drawn as a box. One call, and you can SEE why something
## is not colliding instead of guessing.
func draw_boxes(col: int) -> void:
	con._target.camera(int(round(cam_x)), int(round(cam_y)))
	for e in ents:
		if not (e is LuaVM.Table):
			continue
		var b := box(e)
		con._target.rect(int(b.position.x), int(b.position.y),
			int(b.position.x + b.size.x) - 1, int(b.position.y + b.size.y) - 1,
			col)
