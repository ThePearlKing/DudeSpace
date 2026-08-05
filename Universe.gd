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
	var node: Node3D = null   # the built visual/collider root (movers need it)
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
	BOUNDARY = 95000.0 * k

func _ready() -> void:
	_def("Yorox",    Vector3(-6500, 5200, -7000), 380.0, 25.0, "sun",    Color("#ffdd55"))
	_def("Home",     Vector3(0, 0, 0),           46.0,  5.0,  "home",    Color("#3a1d6e"))
	_def("Circuitia",Vector3(0, 0, 4200),        95.0,  9.0,  "circuit", Color("#0e3b2e"))
	_def("Logica",   Vector3(3600, 0, -2200),    72.0,  8.0,  "logic",   Color("#141820"))
	_def("Pi",       Vector3(-4200, 1500, 3000), 115.0, 11.0, "pi",      Color("#5a2a00"))
	# --- distant Shader System (a star + 4 shader planets + a moon) ---
	_def("ShaderSun",Vector3(0, 0, -25000),      235.0, 20.0, "sun",       Color("#ff7a0f"))
	_def("Contrast", Vector3(0, 0, -24100),      60.0,  9.0,  "contrast",  Color("#ffffff"))
	_def("Pixel",    Vector3(1600, 0, -25000),   82.0,  8.0,  "pixel",     Color("#ff66aa"))
	_def("Wth",      Vector3(-1700, 300, -24000),88.0,  8.0,  "wth",       Color("#33ff99"))
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
	_def("Sanus",    TC + Vector3(-1050, 80, 260),    70.0, 9.5,  "lava",     Color("#8a1f10"))
	_def("Extroma",  TC + Vector3(1900, -240, -700),  85.0, 9.0,  "volcanic", Color("#c8a83a"))
	_def("Varnisol", TC + Vector3(-3400, 420, 1500), 100.0, 9.0,  "varnisol", Color("#3f8f3a"))
	# --- Xero: Varnisol's ice moon. Light blue, cold, quietly beautiful. ---
	_def("Xero",     TC + Vector3(-3400, 540, 2150), 60.0, 5.0,  "ice",      Color("#6ec2ff"))

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

## Height above a body's SURFACE (works for spheres and the torus).
func altitude(b: Body, pos: Vector3) -> float:
	if b.kind == "torus":
		return torus_delta(b, pos).length() - b.radius
	return pos.distance_to(b.center) - b.radius

## Local "up" off a body's surface at pos.
func surface_up(b: Body, pos: Vector3) -> Vector3:
	if b.kind == "torus":
		return torus_delta(b, pos).normalized()
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
		var r: float = d.length()
		if r < 1.0:
			continue
		a += d / r * (b.gm() / (r * r))
	return a

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
