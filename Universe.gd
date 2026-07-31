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
	func gm() -> float:
		return g_surf * radius * radius

var bodies: Array = []
var world_scale: float = 1.0

var BOUNDARY := 70000.0   # edge of the universe; cross it and the god throws you back

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
	BOUNDARY = 70000.0 * k

func _ready() -> void:
	_def("Sol",      Vector3(0, 7000, 0),        380.0, 25.0, "sun",     Color("#ffdd55"))
	_def("Home",     Vector3(0, 0, 0),           46.0,  5.0,  "home",    Color("#3a1d6e"))
	_def("Circuitia",Vector3(0, 0, 4200),        95.0,  9.0,  "circuit", Color("#0e3b2e"))
	_def("Logica",   Vector3(3600, 0, -2200),    72.0,  8.0,  "logic",   Color("#141820"))
	_def("Pi",       Vector3(-4200, 1500, 3000), 115.0, 11.0, "pi",      Color("#5a2a00"))
	# --- distant Shader System (a star + 4 shader planets + a moon) ---
	_def("ShaderSun",Vector3(0, 0, -25000),      320.0, 20.0, "sun",       Color("#ffcc33"))
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
	_def("TIN 618",  Vector3(30000, 0, 0),       220.0, 80.0, "blackhole", Color("#000000"))

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
