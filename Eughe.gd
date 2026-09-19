class_name Eughe
extends Node3D
## EUGHE, and the reason it is not a planet so much as an arrangement.
##
## In the middle is a cold core barely smaller than Earth: rainbow ice
## that breathes, changing colour the whole time, and the calmest place
## in Sloom. Nothing about it is attached to anything else.
##
## Everything you would call geography is somewhere else entirely --
## enormous slime continents hanging detached in the sky, well clear of
## the core, all of them moving, none of them where they were an hour
## ago. When two of them meet they crumple, and a mountain range that
## did not exist that morning is suddenly the tallest thing on the
## world. The geography of Eughe has a clock instead of an address.
##
## The slime is firm enough to stand on and that is the trap. Without
## slime boots it works like quicksand that chews: it takes hold, it
## pulls, and it is eating you the whole time you are arguing with it.
##
## This node owns the moving parts. The core and the moon are ordinary
## bodies built by Main; the continents are bodies too, but ones whose
## centres are recomputed every frame, so their built nodes have to be
## dragged along behind them.

const CARRY_ALT := 5.0      # stand this close and the continent takes you with it
const CHEW_DPS := 7.5       # what the slime costs you per second, unbooted
const SINK_RATE := 1.35     # how hard it presses you down, metres per second
const HOLD_KILL := 3.5      # seconds at full hold before it has finished

var _conts: Array = []      # [{body, node}]
var _ridge_cd: Dictionary = {}   # "a|b" -> seconds before they can crumple again
var _chew: float = 0.0      # how far in the slime has you, 0..1
var _held: float = 0.0      # seconds it has had full hold
var _warned: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	add_to_group("eughe")

## Main hands each built continent over as it makes it.
func register_continent(b, node: Node3D) -> void:
	_conts.append({"body": b, "node": node})

# ------------------------------------------------------------ materials

## THE COLD CORE. Rainbow ice that breathes: bands of colour drifting
## across a cracked, faceted shell, brightening and fading on a slow
## cycle so the whole planet looks like it is inhaling. It is the
## prettiest thing in the galaxy and it is also covered in spikes.
static func core_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	// the ice itself: big facets with cracks running between them
	float f = fbm(n * 6.0);
	float crack = smoothstep(0.46, 0.5, abs(fract(fbm(n * 11.0) * 4.0) - 0.5));
	// THE BREATH. One slow cycle in and out, and the colour band
	// sweeps the whole sphere while it happens -- the same patch of
	// ground is green, then blue, then rose, and back.
	float breath = 0.5 + 0.5 * sin(TIME * 0.22);
	float band = fbm(n * 2.3 + vec3(0.0, TIME * 0.035, 0.0)) * 3.2
		+ n.y * 1.4 + TIME * 0.06;
	vec3 hue = 0.5 + 0.5 * cos(6.28318 * (band + vec3(0.0, 0.33, 0.67)));
	vec3 ice = mix(vec3(0.74, 0.88, 0.97), hue, 0.55 + 0.25 * breath);
	ice = mix(ice * 0.72, ice, f);
	ALBEDO = mix(ice, vec3(0.52, 0.66, 0.78), crack * 0.8);
	// the glow rides the breath, so the planet dims and lifts
	EMISSION = hue * (0.10 + 0.20 * breath) * (1.0 - crack * 0.6);
	ROUGHNESS = 0.18 + 0.4 * crack;
	METALLIC = 0.0;
	SPECULAR = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## THE SLIME. Lime, wet, and see-through by the smallest margin that
## still reads -- you can just make out the far side of a continent
## through it, and the shapes moving inside it, and that is all.
## ONE shader, two materials. Every continent, every ridge thrown up by
## a collision and the moon are all the same stuff, and building a fresh
## Shader per mesh meant recompiling it dozens of times a session.
static var _slime_shader: Shader = null
static var _slime_mats := {}

static func shutdown() -> void:
	_slime_shader = null
	_slime_mats.clear()

static func slime_material(moon: bool = false) -> ShaderMaterial:
	if _slime_mats.has(moon):
		return _slime_mats[moon]
	if _slime_shader != null:
		var cached := ShaderMaterial.new()
		cached.shader = _slime_shader
		cached.set_shader_parameter("wet", 0.55 if moon else 1.0)
		cached.render_priority = 1
		_slime_mats[moon] = cached
		return cached
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode cull_disabled, depth_draw_always;\n" \
		+ "uniform float wet = 1.0;\n" \
		+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	// the surface CRAWLS. Slime is never still and never was.
	float a = fbm(n * 5.0 + vec3(TIME * 0.05, TIME * 0.03, 0.0));
	float b = fbm(n * 13.0 - vec3(0.0, TIME * 0.08, TIME * 0.04));
	vec3 deep = vec3(0.23, 0.44, 0.06);
	vec3 lit = vec3(0.68, 0.92, 0.20);
	vec3 col = mix(deep, lit, a * 0.7 + b * 0.35);
	// bubbles rising under the skin: bright rings that come and go
	float bub = smoothstep(0.72, 0.80, fbm(n * 21.0 + vec3(0.0, TIME * 0.22, 0.0)));
	ALBEDO = col + vec3(0.25, 0.42, 0.05) * bub;
	EMISSION = vec3(0.30, 0.62, 0.07) * (0.12 + 0.30 * bub) * wet;
	// BARELY see-through. Enough to catch shapes behind it; nowhere
	// near enough to make it glass.
	ALPHA = 0.88 - 0.05 * b;
	ROUGHNESS = 0.12 + 0.2 * a;
	SPECULAR = 0.95;
}
"""
	_slime_shader = sh
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wet", 0.55 if moon else 1.0)
	m.render_priority = 1
	_slime_mats[moon] = m
	return m

# ------------------------------------------------- continent geometry

## One slime continent: a huge squashed lump, ridged where it has been
## hit before, with a real collider so it is ground and not scenery.
## Deterministic off the body's name, so a continent is the same shape
## every time the save is opened.
static func continent_mesh(b, segs: int = 40, rings: int = 22) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b.name))
	var sm := SphereMesh.new()
	sm.radius = b.radius
	sm.height = b.radius * 2.0
	sm.radial_segments = segs
	sm.rings = rings
	var src := sm.get_faces()
	# a handful of lobes: a continent is a thing that grew, not a ball
	var lobes: Array = []
	for i in 6:
		lobes.append({
			"d": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5),
				rng.randf_range(-1, 1)).normalized(),
			"w": rng.randf_range(0.16, 0.40),
			"k": rng.randf_range(2.0, 5.0)})
	var out := PackedVector3Array()
	for i in src.size():
		var v := src[i]
		var n := v.normalized()
		var s := 1.0
		for lo in lobes:
			s += float(lo["w"]) * pow(maxf(0.0, n.dot(lo["d"])), float(lo["k"]))
		# ridges: the scars of every collision this thing has survived
		s += 0.055 * sin(n.x * 14.0 + n.y * 9.0) * cos(n.z * 11.0)
		# SQUASHED. A continent lies flat; it does not stand up.
		out.append(Vector3(n.x * s, n.y * s * Universe.SLIME_SQUASH,
			n.z * s) * b.radius)
	return [out]

## Faces into a real mesh with real normals. _mesh_from_faces assumes a
## sphere and points every normal straight out from the middle, which on
## a squashed lumpy slab lights the ridges backwards.
static func build_mesh(faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in faces.size():
		var v := faces[i]
		var n := v.normalized()
		st.set_uv(Vector2(atan2(n.z, n.x) / TAU + 0.5,
			acos(clampf(n.y, -1.0, 1.0)) / PI))
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()

# ----------------------------------------------------------- the tick

func _physics_process(delta: float) -> void:
	_t += delta
	if _conts.is_empty():
		return
	var before := {}
	for c in _conts:
		before[c["body"].name] = c["body"].center
	Universe.advance_orbits(delta)
	# drag every built continent to wherever its body went, and carry
	# anyone standing on it. A moving platform that leaves you behind is
	# just a wall with extra steps.
	var pl = get_tree().get_first_node_in_group("player")
	var riding = standing_on(pl)
	var moved := {}
	for c in _conts:
		var b = c["body"]
		var node: Node3D = c["node"]
		if not is_instance_valid(node):
			continue
		var d: Vector3 = b.center - (before[b.name] as Vector3)
		moved[str(b.name)] = d
		node.global_position = b.center
		if pl != null and is_instance_valid(pl) and riding == b:
			pl.global_position += d
	# the locals come along with their continent -- one pass over them,
	# not one pass per slab
	for e in get_tree().get_nodes_in_group("echegel"):
		if is_instance_valid(e) and moved.has(e.home_name):
			e.global_position += moved[e.home_name] as Vector3
	_crumple_check(delta)
	_chew_check(delta, pl, riding)

## WHEN TWO CONTINENTS MEET. They do not pass through each other and
## they do not bounce -- they crumple, and where they touched there is
## suddenly a mountain range. This is the entire geology of Eughe.
func _crumple_check(delta: float) -> void:
	for k in _ridge_cd.keys():
		_ridge_cd[k] = float(_ridge_cd[k]) - delta
	for i in _conts.size():
		for j in range(i + 1, _conts.size()):
			var a = _conts[i]["body"]
			var b = _conts[j]["body"]
			var gap: float = a.center.distance_to(b.center) \
				- (a.radius + b.radius)
			if gap > 6.0:
				continue
			var key := "%s|%s" % [a.name, b.name]
			if float(_ridge_cd.get(key, 0.0)) > 0.0:
				continue
			_ridge_cd[key] = 90.0
			_raise_ridge(_conts[i], (b.center - a.center).normalized())
			_raise_ridge(_conts[j], (a.center - b.center).normalized())
			_trim_ridges(_conts[i])
			_trim_ridges(_conts[j])
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and _near_player(a.center, 2500.0):
				hud.flash("%s AND %s ARE MEETING" % [str(a.name).to_upper(),
					str(b.name).to_upper()])
			Sfx.play("break", -6.0)

## A fresh range on the face that took the hit: teeth of slime shoved up
## out of the surface, biggest at the point of contact.
func _raise_ridge(c: Dictionary, dir: Vector3) -> void:
	var b = c["body"]
	var node: Node3D = c["node"]
	if not is_instance_valid(node):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b.name) + str(int(_t)))
	var range_root := Node3D.new()
	node.add_child(range_root)
	var ranges: Array = c.get("ranges", [])
	ranges.append(range_root)
	c["ranges"] = ranges
	var basis_up := dir.normalized()
	var side := basis_up.cross(Vector3.UP)
	if side.length() < 0.2:
		side = basis_up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := basis_up.cross(side).normalized()
	for k in 14:
		var u := rng.randf_range(-0.55, 0.55)
		var v := rng.randf_range(-0.55, 0.55)
		var d := (basis_up + side * u + fwd * v).normalized()
		var h := rng.randf_range(4.0, 15.0) * (1.0 - absf(u) - absf(v) * 0.5)
		if h < 1.5:
			continue
		var peak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = rng.randf_range(2.2, 5.5)
		cm.height = h
		cm.radial_segments = 7
		peak.mesh = cm
		peak.material_override = slime_material()
		range_root.add_child(peak)
		# the surface here is squashed; sit the peak on the skin
		var local: Vector3 = Vector3(d.x, d.y * Universe.SLIME_SQUASH,
			d.z) * float(b.radius)
		peak.position = local + d * h * 0.35
		peak.look_at_from_position(peak.position, peak.position + d, Vector3.UP)
		peak.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shp := CylinderShape3D.new()
		shp.radius = cm.bottom_radius * 0.7
		shp.height = h
		cs.shape = shp
		sb.add_child(cs)
		peak.add_child(sb)

## THE SLIME EATS. Stand on a continent without slime boots and it takes
## hold: it pulls you down, it hurts the whole time, and letting it
## finish means it has you. Boots and it is simply ground.
func _chew_check(delta: float, pl, on) -> void:
	if pl == null or not is_instance_valid(pl) or Game.dead:
		_chew = 0.0
		return
	if on == null:
		_chew = maxf(0.0, _chew - delta * 0.8)
		_held = 0.0
		return
	if str(Inventory.equip.get("boots", "")) == "slime_boots":
		_chew = maxf(0.0, _chew - delta)
		_held = 0.0
		return
	_chew = minf(1.0, _chew + delta * 0.22)
	# it PULLS: the slime takes you down toward the middle of the mass
	var down := -Universe.surface_up(on, pl.global_position)
	pl.global_position += down * SINK_RATE * delta * _chew
	Game.hurt(CHEW_DPS * delta * _chew, false, "the slime of %s" % str(on.name))
	# SWALLOWED. Depth is not the measure -- the slab is solid enough to
	# stand on, so it never actually opens under you. What finishes you
	# is TIME: once it has full hold and keeps it, it is done arguing.
	# Roughly four and a half seconds to take hold, three and a half
	# more to win, and it keeps everything you were carrying.
	if _chew >= 1.0:
		_held += delta
		if _held >= HOLD_KILL and not Game.dead:
			Game.hurt(Game.HEALTH_MAX * 3.0, true,
				"the slime of %s" % str(on.name))
			_held = 0.0
			return
	else:
		_held = 0.0
	_warned -= delta
	if _warned <= 0.0:
		_warned = 3.0
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash("THE SLIME HAS YOU — %d%% — you need slime boots"
				% int(_chew * 100.0))

## WHICH CONTINENT HAS YOU, if any. An altitude threshold alone cannot
## answer this: the lumps are half a radius tall, so the same number
## means "standing on a ridge" in one place and "twenty metres up" in
## another. What actually settles it is having ground under your feet
## with a continent as the nearest body -- or being under the skin,
## which means it already has you.
func standing_on(pl):
	if pl == null or not is_instance_valid(pl):
		return null
	var near = Universe.nearest(pl.global_position)
	if near == null or near.kind != "slime":
		return null
	var alt := Universe.altitude(near, pl.global_position)
	if alt < -1.0:
		return near   # inside it. That is not a foothold, that is a mouth.
	if pl.has_method("is_on_floor") and pl.is_on_floor():
		return near
	return null

## A continent keeps the scars of its last few meetings and no more.
## Left alone this grows without limit over a long session, and the
## oldest range is always the one furthest from anything happening.
const MAX_RANGES := 4

func _trim_ridges(c: Dictionary) -> void:
	var ranges: Array = c.get("ranges", [])
	while ranges.size() > MAX_RANGES:
		var old = ranges.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	c["ranges"] = ranges

func _near_player(p: Vector3, r: float) -> bool:
	var pl = get_tree().get_first_node_in_group("player")
	return pl != null and is_instance_valid(pl) \
		and pl.global_position.distance_to(p) < r
