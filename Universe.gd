extends Node
## Autoload "Universe". Registry of celestial bodies + Newtonian gravity.
## GM is derived from surface gravity so g at the surface == g_surf.

class Body:
	var name: String
	var center: Vector3
	var radius: float    # sphere radius; for torus: TUBE (minor) radius
	var major: float = 0.0   # torus ring radius (0 = not a torus)
	var g_surf: float
	var kind: String     # home / circuit / logic / pi / torus / ...
	var color: Color
	var hidden: bool = false   # off the map, off the locator. it exists anyway
	## HOW FAR THIS WORLD REACHES. Normally a planet's pull dies off as
	## an inverse square and is nothing a few radii out. Eughe does not
	## work like that: its continents float hundreds of metres up and
	## are still its ground, so it holds on out there almost as hard as
	## it does at the core. Zero means the ordinary law.
	var heavy_r: float = 0.0
	var node: Node3D = null   # the built visual/collider root (movers need it)
	# MOVERS. A body with orbit_of set is not parked: its centre is
	# recomputed every frame and its built node is dragged with it.
	# Eughe's slime continents are the only things that do this, and
	# they are why that planet has no fixed geography.
	var orbit_of: String = ""
	var orbit_r: float = 0.0
	var orbit_up: Vector3 = Vector3.UP
	var orbit_phase: float = 0.0
	var orbit_speed: float = 0.0
	# A SLIME CONTINENT IS NOT A BLOB AND IT IS NOT A PLATE. It is a
	# piece of shell: a continent lifted off a globe and floated out,
	# still curving around the world it came from. So it is described
	# the way a continent on a map is -- a direction it sits in, how far
	# out it floats, how much sky it covers each way, and how deep it
	# is -- and never as a radius.
	var dir: Vector3 = Vector3.UP     # where it is now, from the core
	var dir0: Vector3 = Vector3.UP    # where it started
	var arc_u: float = 0.5            # angular half-extent, one way
	var arc_v: float = 0.3            # and the other: continents are long
	var thick: float = 18.0
	func gm() -> float:
		return g_surf * radius * radius

var bodies: Array = []
var world_scale: float = 1.0

var BOUNDARY := 95000.0   # edge of the universe; cross it and the god throws you back

## Multiply the whole universe: radii, distances, boundary. Gravity
## follows automatically (gm = g_surf * r^2 -> heavier worlds, same
## surface pull, much longer trips). Call BEFORE Main builds bodies.
func apply_scale(k: float) -> void:
	if k == world_scale or k <= 0.0:
		return
	var f := k / world_scale
	world_scale = k
	for b in bodies:
		b.center *= f
		b.radius *= f
		b.major *= f
		b.heavy_r *= f
	for sh in eughe_shelves:
		sh.center *= f
		sh.radius *= f
		sh.orbit_r *= f
		sh.thick *= f
	BOUNDARY = 95000.0 * k

func _ready() -> void:
	# OPT-IN quiet runs: CTD_QUIET=1 puts the window small, cornered and
	# unfocusable from the first frame -- autoloads run before the first
	# scene, so it covers the loading screen too. Without the variable
	# nothing here happens and the game launches exactly as always.
	if OS.get_environment("CTD_QUIET") != "":
		var qw := get_window()
		if qw != null:
			qw.mode = Window.MODE_WINDOWED
			qw.size = Vector2i(960, 540)
			var sc := DisplayServer.screen_get_size()
			qw.position = Vector2i(maxi(0, sc.x - 980), maxi(0, sc.y - 620))
			qw.unfocusable = true
			qw.always_on_top = false
			qw.set_flag(Window.FLAG_NO_FOCUS, true)
	enter_galaxy("milky")

## --------------------------------------------------------- GALAXIES
## The universe is not a place you travel across -- it is a place that
## gets REPLACED. A galaxy jump tears down every body and builds the
## other set in the same coordinates, so nothing is "far away": the sky
## you were under simply stops existing and another one is there.
var galaxy: String = "milky"

## EUGHE'S SHELVES. These are NOT in `bodies` and never were meant to
## be. A floating continent is a piece of Eughe -- terrain, like a
## mountain range -- and being a Body made it a little planet of its
## own with a name, a slot in every loop that walks the sky, an entry
## wherever the game says what world you are near, and its own answer to
## "which way is up". It gets none of that now. It is a shape, hanging
## off the planet it belongs to, and the planet does the rest.
var eughe_shelves: Array = []

const GALAXIES := {
	"milky": "THE MILKY WAY",
	"sloom": "SLOOM",
}

## Tear the body list down and build the named galaxy in its place.
## Scale is re-applied afterwards: the definitions are always authored
## at 1.0 and a big-world save stretches them on the way in.
func enter_galaxy(g: String) -> void:
	if not GALAXIES.has(g):
		g = "milky"
	galaxy = g
	var k := world_scale
	world_scale = 1.0
	BOUNDARY = 95000.0
	bodies = []
	eughe_shelves = []
	_full_bodies = []
	match g:
		"sloom":
			_build_sloom()
		_:
			_build_milky()
	if k != 1.0:
		apply_scale(k)

func galaxy_label(g: String = "") -> String:
	return str(GALAXIES.get(g if g != "" else galaxy, "THE MILKY WAY"))

func _build_milky() -> void:
	_def("Yorox",    Vector3(-6500, 5200, -7000), 380.0, 25.0, "sun",    Color("#ffdd55"))
	_def("Home",     Vector3(0, 0, 0),           46.0,  5.0,  "home",    Color("#3a1d6e"))
	_def("Circuitia",Vector3(0, 0, 4200),        95.0,  9.0,  "circuit", Color("#0e3b2e"))
	_def("Logica",   Vector3(3600, 0, -2200),    72.0,  8.0,  "logic",   Color("#141820"))
	_def("Pi",       Vector3(-4200, 1500, 3000), 115.0, 11.0, "pi",      Color("#5a2a00"))
	# Big Computer: the dudes' control planet -- a MOTHERBOARD in space,
	# the same board-and-traces face the title screen's dude planets
	# wear. The facility inside runs itself; nobody home.
	_def("Big Computer",Vector3(1800, 2600, 1400),  78.0,  8.0,  "dude", Color("#16283e"))
	# --- distant Shader System (a star + 4 shader planets + a moon) ---
	_def("ShaderSun",Vector3(0, 0, -25000),      235.0, 20.0, "sun",       Color("#ff7a0f"))
	_def("Contrast", Vector3(0, 0, -24100),      60.0,  9.0,  "contrast",  Color("#ffffff"))
	_def("Pixel",    Vector3(1600, 0, -25000),   82.0,  8.0,  "pixel",     Color("#ff66aa"))
	_def("Datamosh", Vector3(-1700, 300, -24000),88.0,  8.0,  "datamosh",  Color("#33ff99"))
	_def("Wireframe",Vector3(0, 1300, -26600),   92.0,  9.0,  "wireframe", Color("#0affaf"))
	_def("Blind",    Vector3(320, 1300, -26600), 40.0,  4.0,  "blind",     Color("#ffffff"))
	_def("Wobble",   Vector3(2600, -900, -23500),78.0,  8.0,  "wob",       Color("#ff9a3c"))
	# --- Euclid: big safe sand planet. Temple (N pole) + pyramid (S pole). ---
	_def("Euclid",   Vector3(5000, 0, 3000),     170.0, 10.0, "sand",      Color("#c8a557"))
	# --- Donut: a torus planet. Gravity pulls to the ring: walk ALL of it. ---
	var donut := _def_ret("Donut", Vector3(4200, -2600, -3800), 26.0, 8.0, "torus", Color("#e8a3c0"))
	donut.major = 75.0
	# --- Verdant: life planet. Procedural plants, mushrooms, animals. ---
	_def("Verdant",  Vector3(-3000, -1200, 1200),88.0,  8.0,  "life",      Color("#2f7d32"))
	# --- Crystalia: far, dangerous, alien-guarded. Ultima crystals. ---
	_def("Crystalia",Vector3(-9000, 4000, -8000),90.0,  9.0,  "crystal",   Color("#40e0d0"))
	# --- TIN 618: a black hole. Extreme pull, endless fall, time dilation. ---
	_def("TIN 618",  Vector3(40000, -3000, 34000), 1100.0, 80.0, "blackhole", Color("#000000"))
	# Harold: a tired old rock parked beside the black hole, 8200m out.
	# Dilation only bites within ~2400m of the horizon now. He's fine.
	_def("Harold",   Vector3(40000 + 8200, -3000, 34000), 130.0, 8.0, "harold", Color("#8f8377"))
	# --- the ACTUAL Sol system. Yes, that one. Far out in -X, long haul. ---
	var SC := Vector3(-52000, 3000, 14000)   # Sol system centre
	_def("Sol",      SC,                          420.0, 26.0, "sun",     Color("#fff4d6"))
	_def("Mercury",  SC + Vector3(950, 60, -180),   24.0, 4.0, "mercury", Color("#9c8f84"))
	_def("Venus",    SC + Vector3(-1500, -120, 700), 58.0, 8.5, "venus",   Color("#e8c46a"))
	_def("Earth",    SC + Vector3(2300, 200, 900),   62.0, 9.0, "earth",   Color("#3a7bd5"))
	_def("The Moon", SC + Vector3(2300, 230, 1040),  17.0, 2.5, "luna",    Color("#c8c8cc"))
	_def("Mars",     SC + Vector3(-3100, 400, -1400), 34.0, 5.5, "mars",   Color("#c1533a"))
	_def("Jupiter",  SC + Vector3(5400, -600, 2200), 280.0, 16.0, "gas",   Color("#c99a6b"))
	_def("Saturn",   SC + Vector3(-7300, 900, 3400), 230.0, 14.0, "gas",   Color("#e3cf9a"))
	_def("Uranus",   SC + Vector3(9600, 1600, -3800), 155.0, 11.0, "gas",  Color("#9fe3e0"))
	_def("Neptune",  SC + Vector3(-11800, -1400, -5200), 150.0, 11.0, "gas", Color("#4a6fe3"))
	# --- the Tris system: a pale-blue giant on the FAR side of everything ---
	var TC := Vector3(52000, -2500, -15000)
	_def("Tris",     TC,                             460.0, 27.0, "sun",      Color("#9fd8ff"))
	# scattered for real: every orbit on its own tilt, nobody sharing a
	# plane, nobody lining up from any angle
	_def("Sanus",    TC + Vector3(-820, 640, 460),    70.0, 9.5,  "lava",     Color("#8a1f10"))
	_def("Extroma",  TC + Vector3(1700, -980, -1150), 85.0, 9.0,  "volcanic", Color("#c8a83a"))
	_def("Varnisol", TC + Vector3(-3050, 1350, 1750), 100.0, 9.0, "varnisol", Color("#3f8f3a"))
	# --- Xero: Varnisol's ice moon. Light blue, cold, quietly beautiful. ---
	_def("Xero",     TC + Vector3(-3050, 1500, 2390), 60.0, 5.0,  "ice",      Color("#6ec2ff"))
	# --- Undros: the Tris system's ocean world, out past Varnisol.
	# ALL water, no land -- you sink through the whole ocean until the
	# sand floor catches you. The blue monolith waits down there. ---
	_def("Undros",   TC + Vector3(-4900, -1750, 3050), 110.0, 8.5, "ocean", Color("#1a5fae"))
	# --- Joule: the Tris system's gas giant. Green, because whatever is
	# in that atmosphere is not ammonia -- the belts glow along their
	# shear lines and the poles burn with aurorae the whole system can
	# see. Biggest thing in Tris that is not the star. ---
	_def("Joule",    TC + Vector3(6100, 2200, -4300), 300.0, 17.0, "gas",
		Color("#3fd98a"))

	# --- the rogue: alone in the high dark, farther from everything
	# than anything -- and furthest of all from the black hole. On no
	# map, on no locator. The white monolith waits there. ---
	var rog := _def_ret("Requiem", Vector3(-30000, 42000, 52000), 64.0, 7.0,
		"rogue", Color("#d8d4cc"))
	rog.hidden = true

## ------------------------------------------------------------ SLOOM
## The other galaxy. Not a far corner of this one -- a different sky
## entirely, reached only through the Nexus. It is mostly empty so far;
## what is in it is Eughe, and Eughe is enough.
##
## OGREK is the star: a red one, burning oranger and far deeper than
## the shader sun ever did.
##
## EUGHE is the joke that turned out to be a planet. The world proper
## is a cold core barely smaller than Earth, wrapped in rainbow ice
## that breathes. Everything that looks like geography is somewhere
## else: enormous slime continents hanging detached in the sky, all of
## them moving, none of them attached to anything. They are real
## bodies -- their own gravity, their own surface, their own weather of
## sorts -- and they are registered here so the map, the locator and
## every gravity sum treat them as the places they are.
const SLOOM_C := Vector3(0, 4000, -38000)       # Ogrek's seat
const EUGHE_C := Vector3(2400, 3400, -36500)    # the cold core
## HOW FAR EUGHE HOLDS ON. Its continents float hundreds of metres over
## the ice and are still its ground, so the planet's reach goes out past
## the furthest of them.
const EUGHE_REACH := 420.0
## THE CONTINENTS. Sixteen of them, and they are NOT places -- they are
## Eughe's terrain, the way a mountain range is terrain. They have no
## names anybody says, they are not on the chart, you cannot warp to one
## any more than you can warp to a hillside, and nothing they do is
## announced to a player on the other side of the galaxy.
##
## They are laid out on a Fibonacci sphere so the cover is EVEN: from
## anywhere on the core there is slime overhead, the way there is
## always cloud overhead. They used to be hand-placed and clustered,
## which left one hemisphere with an empty sky.
## HOW MANY, AND HOW HIGH. Cloud cover means clouds AND sky: at
## twenty-eight wide ones there was no sky left at all.
##
## And there is ONE LAYER. Spreading them from 168 to 344 stacked them
## into decks you could count from the ground, which is not what a sky
## full of continents looks like -- they all float at the same height,
## and the only variation is the few metres that keeps them from
## looking stamped out.
const SLIME_COUNT := 14
const SLIME_R_MIN := 236.0
const SLIME_R_MAX := 252.0

func _build_sloom() -> void:
	# a RED star. Oranger and deeper than the shader sun, which next to
	# this thing reads like a streetlight.
	_def("Ogrek",  SLOOM_C, 300.0, 22.0, "sun", Color("#ff4410"))
	# THE COLD CORE. Grey, and it stays grey -- the colour on Eughe is
	# in the ice standing on it, not in the rock. Earth is 62 across in
	# this universe; Eughe is 58, and barely smaller is the point.
	var eu := _def_ret("Eughe", EUGHE_C, 58.0, 9.0, "eughe", Color("#8e949c"))
	eu.heavy_r = EUGHE_REACH
	# the continents. Enormous, lime, curving round the core, evenly
	# spread over it, and part of the planet rather than places of their
	# own -- so their ids are internal and never shown to anybody.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5514
	var ga := PI * (3.0 - sqrt(5.0))   # golden angle
	for i in SLIME_COUNT:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(SLIME_COUNT)
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var th := ga * float(i)
		var d0 := Vector3(cos(th) * rr, y, sin(th) * rr).normalized()
		# the axis it swings on is perpendicular to where it sits, so it
		# sweeps a great circle through its own patch and the cover stays
		# even however long you watch
		var pick := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
			rng.randf_range(-1, 1))
		var axis := d0.cross(pick)
		if axis.length() < 0.15:
			axis = d0.cross(Vector3(1, 0, 0))
		axis = axis.normalized()
		# a shape, not a world: built by hand and kept out of `bodies`
		var cb := Body.new()
		cb.name = "eughe_shelf_%d" % i
		cb.kind = "slime"
		cb.color = Color("#39c24a")
		cb.hidden = true
		cb.g_surf = 0.0
		cb.orbit_of = "Eughe"
		cb.orbit_r = rng.randf_range(SLIME_R_MIN, SLIME_R_MAX)
		cb.radius = cb.orbit_r * 0.5
		cb.center = EUGHE_C + d0 * cb.orbit_r
		cb.orbit_up = axis
		cb.orbit_phase = 0.0
		cb.orbit_speed = rng.randf_range(0.006, 0.019) \
			* (1.0 if rng.randf() < 0.5 else -1.0)
		cb.dir = d0
		cb.dir0 = d0
		cb.arc_u = rng.randf_range(0.34, 0.66)
		cb.arc_v = rng.randf_range(0.20, 0.40)
		cb.thick = rng.randf_range(14.0, 30.0)
		eughe_shelves.append(cb)
	# the moon, which is also slime, and which has one thing on it.
	_def("Ex23 Florgus", EUGHE_C + Vector3(1350.0, 260.0, -880.0), 21.0, 2.6,
		"florgus", Color("#9ee02c"))

## Tutorial universe: ONLY the tutorial planet + its moon exist. The real
## body list is stashed and put back when the title screen returns.
var _full_bodies: Array = []

func enter_tutorial_universe() -> void:
	if _full_bodies.is_empty():
		_full_bodies = bodies
	bodies = []
	_def("Tutoria",      Vector3(0, 0, 0) * world_scale,   55.0 * world_scale, 7.0, "tutorial",      Color("#3f7fbf"))
	_def("Tutoria Moon", Vector3(0, 0, 320) * world_scale, 20.0 * world_scale, 4.0, "tutorial_moon", Color("#9fb8c8"))
	# far enough that only a rocket gets you there -- the flight lesson
	_def("Rocketia",     Vector3(600, 300, 1500) * world_scale, 40.0 * world_scale, 6.0, "tutorial_rocket", Color("#c96a3f"))

func restore_full_universe() -> void:
	if not _full_bodies.is_empty():
		bodies = _full_bodies
		_full_bodies = []

## Step every orbiting body forward. Called once a frame by Main, which
## then drags each body's built node to its new centre. Eughe's slime
## continents are on this: their geography has a clock, not an address.
func advance_orbits(dt: float) -> void:
	for b in eughe_shelves:
		var host := body_named(b.orbit_of)
		if host == null:
			continue
		b.orbit_phase = fposmod(b.orbit_phase + b.orbit_speed * dt, TAU)
		# it SWINGS round the world it belongs to, keeping its face to
		# the core the whole way -- which is why a continent stays a
		# continent instead of tumbling
		b.dir = b.dir0.rotated(b.orbit_up.normalized(), b.orbit_phase)
		b.center = host.center + b.dir * b.orbit_r

func _def(n: String, c: Vector3, r: float, g: float, k: String, col: Color) -> void:
	_def_ret(n, c, r, g, k, col)

func _def_ret(n: String, c: Vector3, r: float, g: float, k: String, col: Color) -> Body:
	var b := Body.new()
	b.name = n
	b.center = c
	b.radius = r
	b.g_surf = g
	b.kind = k
	b.color = col
	bodies.append(b)
	return b

## Vector from the nearest point on a torus body's ring to `pos`.
func torus_delta(b: Body, pos: Vector3) -> Vector3:
	var v := pos - b.center
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() < 0.01:
		flat = Vector3(1, 0, 0)
	return pos - (b.center + flat.normalized() * b.major)

## Height above a body's SURFACE (spheres, the torus, and the slime
## continents). Measuring a flat plate as if it were a ball says you are
## twenty metres underground while you stand on top of it.
func altitude(b: Body, pos: Vector3) -> float:
	if b.kind == "torus":
		return torus_delta(b, pos).length() - b.radius
	if b.kind == "slime":
		return _shell_altitude(b, pos)
	return pos.distance_to(b.center) - b.radius

## How far you are off a continent. Inside its footprint that is simply
## how high above the top skin you are, measured out from the core it
## curves around; outside the footprint it is how far you would have to
## travel sideways to be over it at all. Both in metres, so `nearest`
## can still compare it against every other body in the sky.
func _shell_altitude(b: Body, pos: Vector3) -> float:
	var host := body_named(b.orbit_of)
	var origin: Vector3 = host.center if host != null else Vector3.ZERO
	var v := pos - origin
	var r := v.length()
	if r < 0.001:
		return b.orbit_r
	var ang := acos(clampf(v.normalized().dot(b.dir), -1.0, 1.0))
	var over := maxf(0.0, ang - _arc_at(b, v.normalized()))
	var lateral := over * r
	var vertical := r - (b.orbit_r + b.thick * 0.5)
	if lateral <= 0.0:
		return vertical
	if vertical <= 0.0:
		return lateral
	return sqrt(lateral * lateral + vertical * vertical)

## The footprint is not a circle: a continent is long one way. This is
## its angular half-extent in whatever direction the sample lies.
func _arc_at(b: Body, n: Vector3) -> float:
	var side := b.orbit_up.cross(b.dir)
	if side.length() < 0.05:
		side = b.dir.cross(Vector3(1, 0, 0))
	side = side.normalized()
	var fwd := b.dir.cross(side).normalized()
	var du := n.dot(side)
	var dv := n.dot(fwd)
	var m := sqrt(du * du + dv * dv)
	if m < 0.0001:
		return maxf(b.arc_u, b.arc_v)
	du /= m
	dv /= m
	return 1.0 / sqrt((du / b.arc_u) * (du / b.arc_u)
		+ (dv / b.arc_v) * (dv / b.arc_v))

## Is this point over the continent at all (rather than out past its
## coast)? Used by anything that must not walk off the edge.
func slime_contains(b: Body, pos: Vector3) -> bool:
	var host := body_named(b.orbit_of)
	var origin: Vector3 = host.center if host != null else Vector3.ZERO
	var n := (pos - origin).normalized()
	return acos(clampf(n.dot(b.dir), -1.0, 1.0)) < _arc_at(b, n)

## Local "up" off a body's surface at pos. On a squashed continent that
## is the ellipsoid normal, not the line back to the middle -- otherwise
## everything standing on the flat top leans inward.
func surface_up(b: Body, pos: Vector3) -> Vector3:
	if b.kind == "torus":
		return torus_delta(b, pos).normalized()
	if b.kind == "slime":
		# up on a continent is up off the WORLD it curves around: stand
		# on one and the core is under your feet, which is the whole
		# reason it reads as a landmass and not a raft
		var host := body_named(b.orbit_of)
		if host != null:
			return (pos - host.center).normalized()
	return (pos - b.center).normalized()

## Summed gravitational acceleration at a world point.
func gravity_at(pos: Vector3) -> Vector3:
	var a := Vector3.ZERO
	for b in bodies:
		if b.kind == "torus":
			# pull toward the nearest point on the RING
			var td := torus_delta(b, pos)
			var r2: float = td.length()
			if r2 < 1.0:
				continue
			a += -td / r2 * (b.gm() / (r2 * r2))
			continue
		var d: Vector3 = b.center - pos
		# squared-distance cull FIRST: bodies whose pull is under
		# 0.0004 m/s^2 contribute nothing you could ever feel, and
		# skipping them skips a sqrt + normalize per body per call --
		# this function runs 240x per frame under the map's trajectory
		var rsq: float = d.length_squared()
		if rsq < 1.0:
			continue
		if b.gm() / rsq < 0.0004 \
				and not (b.heavy_r > 0.0 and rsq < b.heavy_r * b.heavy_r):
			continue
		var r: float = sqrt(rsq)
		var pull: float = b.gm() / rsq
		# INSIDE a body, gravity tapers like a solid sphere: g_surf * r/R.
		# The point-mass formula would crush anyone in a facility interior
		# and hit hundreds of m/s^2 near the planetary core.
		if r < b.radius:
			pull = b.g_surf * (r / b.radius)
		elif b.heavy_r > b.radius and r < b.heavy_r:
			# a HEAVY RANGE: the pull eases from full surface gravity to
			# half of it across the whole reach instead of collapsing in
			# the first few radii, so everything floating inside that
			# reach is still standing on this planet
			pull = lerpf(b.g_surf, b.g_surf * 0.5,
				(r - b.radius) / (b.heavy_r - b.radius))
		elif b.heavy_r > b.radius:
			var edge: float = b.g_surf * 0.5 * b.heavy_r * b.heavy_r
			pull = edge / rsq
		a += d / r * pull
	return a

## true when pos is INSIDE a planet's shell -- colony interiors, the Big
## Computer facility, mine shafts. No rockets or machines down there.
func inside_body(pos: Vector3) -> bool:
	for b in bodies:
		if b.kind == "torus":
			continue
		if pos.distance_to(b.center) < b.radius - 0.5:
			return true
	return false

## Body whose surface is closest to pos.
func nearest(pos: Vector3) -> Body:
	var best: Body = null
	var bd := INF
	for b in bodies:
		var d := altitude(b, pos)
		if d < bd:
			bd = d
			best = b
	return best

func body_named(n: String) -> Body:
	if n == "Wth":
		n = "Datamosh"   # the planet got renamed; old saves didn't
	for b in bodies:
		if b.name == n:
			return b
	return null

## A fake body whose centre is far below `pos` -> near-flat "down" gravity.
## Used by enemies inside interior pocket dimensions. Not in `bodies`.
func make_flat_body(pos: Vector3) -> Body:
	var b := Body.new()
	b.name = "interior"
	b.center = pos + Vector3.DOWN * 100000.0
	b.radius = 99990.0
	b.g_surf = 9.0
	b.kind = "interior"
	b.color = Color.WHITE
	return b
