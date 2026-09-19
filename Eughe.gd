class_name Eughe
extends Node3D
## EUGHE, and the reason it is not a planet so much as an arrangement.
##
## THE CORE is small, cold and GREY. It stays grey. The colour on this
## world is not in the rock -- it is in the ice standing on it: rainbow
## scapes that breathe, changing hue on a slow cycle, grown so tall and
## so dense that from the ground they close over the sky like weather.
##
## THE CONTINENTS are somewhere else. Enormous lime-green slime
## landmasses floating clear of the core, and they are CONTINENTS: each
## one a piece of shell that still curves around the world it came off,
## long one way and ragged at the coast, not a ball and not a plate.
## They are part of the planet, not moons -- Eughe holds them and
## everyone standing on them with its own gravity, which is why it
## reaches so much further than a world that size has any business
## reaching.
##
## They move, and when two of them meet they crumple and throw up a
## mountain range that was not there that morning.
##
## The slime is firm enough to be geography and it is still dangerous:
## touching it costs you health for as long as you are touching it. It
## does not swallow you and there is nothing you can wear against it.

const BURN_DPS := 6.5       # what the slime costs you per second in contact
const TOUCH_ALT := 2.0      # within this of the skin counts as touching

var _conts: Array = []      # [{body, node, ranges}]

var _ridge_cd: Dictionary = {}
var _warned: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	add_to_group("eughe")

func register_continent(b, node: Node3D) -> void:
	_conts.append({"body": b, "node": node})

# --------------------------------------------------------------- noise
## A small seeded value noise, so a continent's coastline is the same
## coastline every time the save is opened.
static func _vnoise(p: Vector3, seed_i: int) -> float:
	var i := Vector3(floor(p.x), floor(p.y), floor(p.z))
	var f := p - i
	f = f * f * (Vector3(3, 3, 3) - 2.0 * f)
	var out := 0.0
	for cz in 2:
		for cy in 2:
			for cx in 2:
				var c := i + Vector3(cx, cy, cz)
				var h := fmod(absf(sin(c.x * 127.1 + c.y * 311.7 + c.z * 74.7
					+ float(seed_i) * 0.137) * 43758.5453), 1.0)
				var w := (f.x if cx == 1 else 1.0 - f.x) \
					* (f.y if cy == 1 else 1.0 - f.y) \
					* (f.z if cz == 1 else 1.0 - f.z)
				out += h * w
	return out

static func _fbm(p: Vector3, seed_i: int, oct: int = 4) -> float:
	var a := 0.5
	var v := 0.0
	var q := p
	for i in oct:
		v += a * _vnoise(q, seed_i + i * 17)
		q *= 2.03
		a *= 0.5
	return v

# ------------------------------------------------------------ materials

## THE CORE. Cold grey stone under old frost -- cracked, dusty, dead
## quiet. There is no rainbow anywhere in it: that belongs to the ice.
static func core_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	float f = fbm(n * 7.0);
	float grit = fbm(n * 23.0);
	float crack = smoothstep(0.47, 0.5, abs(fract(fbm(n * 12.0) * 5.0) - 0.5));
	// COLD grey, leaning blue, because any warmth in the albedo plus any
	// warmth in the lamp comes out tan -- and this planet is grey
	vec3 rock = mix(vec3(0.33, 0.36, 0.41), vec3(0.58, 0.62, 0.69), f);
	rock = mix(rock, vec3(0.74, 0.79, 0.86), grit * 0.4);   // frost dust
	ALBEDO = mix(rock, vec3(0.17, 0.19, 0.23), crack * 0.85);
	EMISSION = vec3(0.0);
	ROUGHNESS = 0.84 - 0.28 * grit;
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## THE ICE SCAPES. This is where the colour lives, and it is not a
## rainbow painted across a crystal -- it never was. Each crystal is ONE
## SOLID COLOUR at any moment, and that colour hue-shifts continuously,
## so a spire is solid green, then solid teal, then solid rose, all of
## it at once. And they are all at different points in the cycle, so a
## field of them is a field of different solid colours, drifting.
##
## One material for the lot: the phase offset rides per instance, which
## is what lets five hundred crystals each hold their own colour without
## five hundred materials.
static var _ice_mat: ShaderMaterial = null

static func ice_material() -> ShaderMaterial:
	if _ice_mat != null:
		return _ice_mat
	var sh := Shader.new()
	# depth_prepass_alpha, because without it a translucent surface and
	# everything behind it sort by object instead of by pixel -- which
	# is how a continent three hundred metres away drew in front of the
	# spire it was plainly behind
	sh.code = """shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;
// where in the cycle THIS crystal is, and how fast it runs
instance uniform float hue_off = 0.0;
instance uniform float hue_rate = 1.0;
void fragment(){
	float h = fract(hue_off + TIME * 0.045 * hue_rate);
	// one hue over the whole crystal. No band, no gradient, no texture.
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67)));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.0);
	ALBEDO = col;
	EMISSION = col * (0.55 + 0.75 * fres);
	ALPHA = 0.72 + 0.22 * fres;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 1.0;
}
"""
	_ice_mat = ShaderMaterial.new()
	_ice_mat.shader = sh
	return _ice_mat

## THE SLIME. Lime green, wet, firm, and OPAQUE. It used to be very
## slightly see-through, which put every continent in the transparent
## queue and drew them over ice they were behind. The thickness reads
## off the sheen and the rim now instead of off alpha, and it sorts like
## the solid geography it is.
static var _slime_mats := {}

static func shutdown() -> void:
	_ice_mat = null
	_slime_mats.clear()

static func slime_material(moon: bool = false) -> ShaderMaterial:
	if _slime_mats.has(moon):
		return _slime_mats[moon]
	var sh := Shader.new()
	# cull_disabled as well as the winding fix: a continent is a thing
	# you can stand under, and neither face of it should ever vanish
	sh.code = "shader_type spatial;\nrender_mode cull_disabled;\n" \
		+ "uniform float wet = 1.0;\n" \
		+ preload("res://Title.gd")._TP_NOISE + """
void fragment(){
	vec3 n = normalize(vn);
	// the surface CRAWLS. Slime is never still and never was.
	float a = fbm(n * 5.0 + vec3(TIME * 0.05, TIME * 0.03, 0.0));
	float b = fbm(n * 14.0 - vec3(0.0, TIME * 0.08, TIME * 0.04));
	// LIME GREEN, which is a GREEN. The old bright end was (0.78, 0.98,
	// 0.24) -- red nearly as high as green -- and that is yellow, which
	// is exactly what it looked like on screen.
	vec3 deep = vec3(0.07, 0.34, 0.09);
	vec3 lit  = vec3(0.27, 0.87, 0.24);
	vec3 col = mix(deep, lit, clamp(a * 0.8 + b * 0.4, 0.0, 1.0));
	float bub = smoothstep(0.70, 0.79, fbm(n * 20.0 + vec3(0.0, TIME * 0.22, 0.0)));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.4);
	ALBEDO = col + vec3(0.04, 0.20, 0.04) * bub;
	EMISSION = vec3(0.08, 0.50, 0.10) * (0.10 + 0.26 * bub + 0.30 * fres) * wet;
	ROUGHNESS = 0.10 + 0.18 * a;
	SPECULAR = 1.0;
	METALLIC = 0.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wet", 0.6 if moon else 1.0)
	_slime_mats[moon] = m
	return m

# ------------------------------------------------- continent geometry

## Samples across the footprint. At 40 a cell is about six metres of
## coastline and the steps are visible from the ground even after the
## boundary smoothing; 64 puts a cell under four metres, which with the
## smoothing on top reads as a coast.
const GRID := 64
const BLOCKS := 4           # collider chunks per axis (16 hulls)

## BUILD A CONTINENT. It is generated in the frame of the core it
## belongs to, as a patch of a shell at its float height, so every
## vertex sits on a sphere around the planet and the whole landmass
## CURVES with it. The outline comes off noise pulled in toward the rim,
## which is what gives it a coast with headlands and bays instead of the
## silhouette of an egg.
##
## Returns [ArrayMesh, Array of ConvexPolygonShape3D, Array of land
## directions] -- everything relative to the core.
static func build_continent(b) -> Array:
	var sd := int(absi(hash(str(b.name))) % 100000)
	var up: Vector3 = b.dir0.normalized()
	var axis: Vector3 = b.orbit_up.normalized()
	var side := axis.cross(up)
	if side.length() < 0.05:
		side = up.cross(Vector3(1, 0, 0))
	side = side.normalized()
	var fwd := up.cross(side).normalized()
	var tu := tan(b.arc_u)
	var tv := tan(b.arc_v)

	var dirs: Array = []
	var land: Array = []
	var fields: Array = []
	var top: Array = []
	var bot: Array = []
	for j in GRID + 1:
		var sv := float(j) / float(GRID) * 2.0 - 1.0
		for i in GRID + 1:
			var su := float(i) / float(GRID) * 2.0 - 1.0
			var d: Vector3 = (up + side * su * tu + fwd * sv * tv).normalized()
			var rad := sqrt(su * su + sv * sv)
			# a low octave decides where the LANDMASS is, so it comes out
			# as one connected body; a high one only ragges the coast.
			# The old single mid-frequency field left one half of the
			# patch solid and the other half nearly empty, which reads as
			# a continent that did not finish building.
			var field: float = _fbm(d * 1.8, sd) * 1.0 \
				+ _fbm(d * 5.5, sd + 31) * 0.30 \
				+ (1.0 - pow(rad, 1.6)) * 0.95
			var inside: bool = field > 0.78 and rad < 0.98
			# A COAST IS THIN. Giving every cell out to the water's edge
			# full relief and full depth made the rim a staircase of
			# slabs -- neighbouring cells stepping up and down by metres
			# with a sheer wall between them, and from outside it read
			# as machined. Relief and thickness now fade out as the
			# field approaches the shoreline, so a continent is deep and
			# mountainous inland and tapers to a lip at the edge.
			var shore: float = smoothstep(0.78, 1.18, field)
			var relief: float = _fbm(d * 9.0, sd + 5) * b.thick * 1.25 * shore
			var half: float = b.thick * 0.5 * (0.18 + 0.82 * shore)
			dirs.append(d)
			land.append(inside)
			fields.append(field)
			top.append(d * (b.orbit_r + half + relief))
			bot.append(d * (b.orbit_r - half - relief * 0.45))

	var row := GRID + 1
	# SMOOTH THE COAST. Including whole cells or not makes the outline a
	# staircase of little squares, and on a continent that is the first
	# thing you notice. Every land vertex that borders open sky is slid
	# along its own edges to where the field actually crosses the
	# threshold, so the silhouette follows the coastline instead of the
	# grid -- no extra triangles, and the steps go away.
	const THRESH := 0.78
	for j in row:
		for i in row:
			var k: int = j * row + i
			if not land[k]:
				continue
			var shift := Vector3.ZERO
			var hits := 0
			for e in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ni: int = i + int(e[0])
				var nj: int = j + int(e[1])
				if ni < 0 or nj < 0 or ni >= row or nj >= row:
					continue
				var nk: int = nj * row + ni
				if land[nk]:
					continue
				var f0: float = fields[k]
				var f1: float = fields[nk]
				var t: float = 1.0 if absf(f0 - f1) < 0.0001 \
					else clampf((f0 - THRESH) / (f0 - f1), 0.0, 1.0)
				shift += (top[nk] - top[k]) * t
				hits += 1
			if hits > 0:
				var avg: Vector3 = shift / float(hits)
				top[k] = (top[k] as Vector3) + avg
				bot[k] = (bot[k] as Vector3) + avg

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var land_dirs: Array = []
	for j in GRID:
		for i in GRID:
			var i00: int = j * row + i
			var i10: int = j * row + i + 1
			var i11: int = (j + 1) * row + i + 1
			var i01: int = (j + 1) * row + i
			if not (land[i00] and land[i10] and land[i11] and land[i01]):
				continue
			land_dirs.append(dirs[i00])
			_quad(st, top[i00], top[i10], top[i11], top[i01])
			_quad(st, bot[i01], bot[i11], bot[i10], bot[i00])
			# COASTS: a wall wherever the next cell along is open sky
			for e in [[-1, 0, i00, i01], [1, 0, i11, i10],
					[0, -1, i10, i00], [0, 1, i01, i11]]:
				var ni: int = i + int(e[0])
				var nj: int = j + int(e[1])
				var open := ni < 0 or nj < 0 or ni >= GRID or nj >= GRID
				if not open:
					open = not (land[nj * row + ni] and land[nj * row + ni + 1]
						and land[(nj + 1) * row + ni + 1]
						and land[(nj + 1) * row + ni])
				if open:
					var p: int = int(e[2])
					var q: int = int(e[3])
					_quad(st, top[p], top[q], bot[q], bot[p])
	st.generate_normals()
	var mesh := st.commit()

	# SOLID COLLIDERS, one convex chunk per block of the grid. A shell of
	# triangles is a sheet of paper to anything falling onto a surface
	# that is also moving, and everything that landed went through it.
	var hulls: Array = []
	var step: int = GRID / BLOCKS
	for bj in BLOCKS:
		for bi in BLOCKS:
			var pts := PackedVector3Array()
			for j in range(bj * step, bj * step + step + 1):
				for i in range(bi * step, bi * step + step + 1):
					var k: int = j * row + i
					if not land[k]:
						continue
					pts.append(top[k])
					pts.append(bot[k])
			if pts.size() >= 12:
				var hull := ConvexPolygonShape3D.new()
				hull.points = pts
				hulls.append(hull)
	return [mesh, hulls, land_dirs]

## INSIDE OUT. Wound a-b-c, generate_normals() hands back the normal of
## Plane(a,b,c), which is (a-c) x (a-b) -- and for a quad laid out along
## +side then +fwd that works out to MINUS the outward direction. Every
## continent was built with its faces pointing at its own middle, so
## back-face culling threw away the side you were looking at and left
## you staring through it at the far wall. Reversed, and the normals
## come out along the surface up where they belong.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	st.add_vertex(a)
	st.add_vertex(d)
	st.add_vertex(c)

# ----------------------------------------------------------- the tick

func _physics_process(delta: float) -> void:
	_t += delta
	if _conts.is_empty():
		return
	var pl = get_tree().get_first_node_in_group("player")
	var riding = standing_on(pl)
	var host = Universe.body_named("Eughe")
	if host == null:
		return
	var before := {}
	for c in _conts:
		before[str(c["body"].name)] = c["body"].orbit_phase
	Universe.advance_orbits(delta)
	# A CONTINENT SWINGS; IT DOES NOT SLIDE. Its node is pinned at the
	# core and turned about the same axis its body is, which is what
	# keeps a curved landmass hugging the world instead of flying off on
	# a tangent. Anyone standing on it turns with it.
	for c in _conts:
		var b = c["body"]
		var node: Node3D = c["node"]
		if not is_instance_valid(node):
			continue
		var axis: Vector3 = b.orbit_up.normalized()
		node.global_transform = Transform3D(Basis(axis, b.orbit_phase),
			host.center)
		if pl != null and is_instance_valid(pl) and riding == b:
			var da: float = b.orbit_phase - float(before[str(b.name)])
			if absf(da) > PI:
				da -= TAU * signf(da)
			pl.global_position = host.center \
				+ (pl.global_position - host.center).rotated(axis, da)
	_crumple_check(delta)
	_burn_check(delta, pl, riding)

## WHICH CONTINENT HAS YOU, if any. Ground under your feet with a
## continent as the nearest body -- an altitude number alone cannot
## answer it when the relief is as tall as the landmass is deep.
## WHICH SHELF HAS YOU, or nothing. Two hard requirements, and the bug
## that put a slime pit round a player standing on the core came from
## having neither: you must be INSIDE a shelf's footprint, and you must
## be at its surface. It used to ask `Universe.nearest` -- which happily
## handed back a continent two hundred metres overhead -- and then hold
## on for `thick * 1.6`, which is forty metres of "still in the slime"
## while you walk away from it.
func standing_on(pl):
	if pl == null or not is_instance_valid(pl):
		return null
	var pos: Vector3 = pl.global_position
	# already in one: you are out when you climb back above the height
	# it took you at, and not a moment later
	if _mired_on != null:
		if Universe.slime_contains(_mired_on, pos) \
				and Universe.altitude(_mired_on, pos) < _entry_alt + 0.6:
			return _mired_on
		return null
	for sh in Universe.eughe_shelves:
		if not Universe.slime_contains(sh, pos):
			continue
		var alt := Universe.altitude(sh, pos)
		# at the skin: a little above it, or already in the top of it
		if alt < TOUCH_ALT and alt > -sh.thick:
			return sh
	return null

## THE SLIME IS QUICKSAND. Step onto a continent and it takes your
## weight for a moment and then it does not: you sink, the surface
## bulges and closes around you, your legs stop working properly, and
## the whole time it is draining you. It is not an invisible damage
## plane you stand on top of -- you are IN it, and you can see that you
## are.
##
## It never simply takes you. Moving is struggling, and struggling
## works: fight and you climb out. Stand still and you go down.
##
## ONCE YOU ARE PAST SHALLOW it stops being terrain and starts being a
## mouth. You do not have to be buried -- about a third of the way down
## is enough. The slime around you parts into lobes that open and close,
## and every time they close they take you another bite.
const SINK_PER_SEC := 0.26       # how fast it takes you if you do nothing
const STRUGGLE_PER_SEC := 0.70   # how fast you climb out while fighting
const SINK_DEPTH := 1.7          # metres from the skin to fully under --
								 # chest deep, not buried: at 2.6 you were
								 # over your own head at the bottom of it
const CHEW_LINE := 0.35          # past this it starts biting -- not
								 # "deep", just past shallow: once it
								 # is over your knees it is working
const CHEW_PERIOD := 1.35        # seconds per bite
const CHEW_BITE := 0.07          # how much each closure takes

var _sink: float = 0.0
var _chew_t: float = 0.0
var _pit: Node3D = null
var _pit_jaws: Array = []
var _pit_bowl: MeshInstance3D = null
var _mired_on = null
var _entry_alt: float = 0.0

func _burn_check(delta: float, pl, on) -> void:
	if pl == null or not is_instance_valid(pl) or Game.dead:
		_release(pl)
		return
	if on == null:
		# OUT. Let go, give the legs back, and let the pit close.
		if _sink > 0.0:
			_sink = maxf(0.0, _sink - delta * 1.6)
			_shape_pit(pl, null)
			if "mire" in pl:
				pl.mire = _sink
			if _sink <= 0.0:
				_release(pl)
		return

	# STRUGGLING. How hard you are working against it, off your own
	# movement -- this is the escape, and it has to be the obvious one:
	# you are stuck, so you move, so you get out.
	var up := Universe.surface_up(on, pl.global_position)
	# STRUGGLING IS TRYING, not succeeding. Measuring it off the speed
	# you managed meant the deeper you were the less the slime believed
	# you were fighting, and at the bottom you could not get out at all.
	var struggle: float = float(pl.wish_len) if "wish_len" in pl else 0.0
	_sink = clampf(_sink + delta * (SINK_PER_SEC
		- STRUGGLE_PER_SEC * struggle), 0.0, 1.0)

	# THE CHEW. Past the line the slime works: lobes close, and each
	# closure takes a bite regardless of how hard you are fighting.
	if _sink > CHEW_LINE:
		_chew_t += delta
		if _chew_t >= CHEW_PERIOD:
			_chew_t -= CHEW_PERIOD
			_sink = minf(1.0, _sink + CHEW_BITE)
			Sfx.play("break", -14.0)
	else:
		_chew_t = 0.0

	# ride it down. The continent is solid, so being inside it means
	# being excused from its collider for as long as you are in there --
	# and then the SLIME has to hold you, because nothing else is. It
	# only used to push down, so with the collider gone the player fell
	# straight through the continent and kept going to the core.
	_grip(pl, on)
	var alt := Universe.altitude(on, pl.global_position)
	# depth is measured from the surface you were standing on when it
	# took you, because the ground up there is lumpy and the nominal
	# shell top can be several metres under your boots
	var want := _entry_alt - SINK_DEPTH * _sink
	pl.global_position += up * clampf(want - alt, -delta * 2.4, delta * 4.0)
	# it carries your weight while it has you: gravity does not get to
	# keep adding to a fall that the slime is not allowing
	if "velocity" in pl:
		pl.velocity -= up * pl.velocity.dot(up)
	if "mire" in pl:
		pl.mire = _sink
	_shape_pit(pl, on)
	# it drains you the whole time it has you, harder the deeper you are
	Game.hurt(BURN_DPS * delta * (0.45 + 0.85 * _sink), false, "Eughe's slime")

## Excuse the player from the continent's collider while they are inside
## it, and put it back the moment they are out -- otherwise the solid
## hull that stops you falling through also stops you sinking in.
func _grip(pl, on) -> void:
	if _mired_on == on:
		return
	_release(pl)
	_mired_on = on
	_entry_alt = Universe.altitude(on, pl.global_position)
	if on.node != null and is_instance_valid(on.node) \
			and pl.has_method("add_collision_exception_with"):
		pl.add_collision_exception_with(on.node)

func _release(pl) -> void:
	if _mired_on != null and pl != null and is_instance_valid(pl):
		if _mired_on.node != null and is_instance_valid(_mired_on.node) \
				and pl.has_method("remove_collision_exception_with"):
			pl.remove_collision_exception_with(_mired_on.node)
		if "mire" in pl:
			pl.mire = 0.0
	_mired_on = null
	_sink = 0.0
	_chew_t = 0.0
	if _pit != null and is_instance_valid(_pit):
		_pit.queue_free()
	_pit = null
	_pit_jaws.clear()
	_pit_bowl = null

## WHAT IT LOOKS LIKE. A bulge of slime heaped around you that grows as
## you go down, and past the chew line a ring of lobes over your head
## that open and close. Without this the whole thing is a number going
## down for no visible reason.
func _shape_pit(pl, on) -> void:
	if _sink <= 0.01 or on == null:
		if _pit != null and is_instance_valid(_pit):
			_pit.visible = false
		return
	var up := Universe.surface_up(on, pl.global_position)
	var skin: Vector3 = pl.global_position + up \
		* (SINK_DEPTH * _sink + 0.25)
	if _pit == null or not is_instance_valid(_pit):
		_pit = Node3D.new()
		add_child(_pit)
		# the heap: a ring of slime shoved up out of the surface
		_pit_bowl = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75
		tm.outer_radius = 1.9
		tm.rings = 10
		tm.ring_segments = 22
		_pit_bowl.mesh = tm
		_pit_bowl.material_override = slime_material()
		_pit.add_child(_pit_bowl)
		# the lobes. Four of them, folded flat until it starts biting.
		for k in 4:
			var jaw := MeshInstance3D.new()
			var jm := SphereMesh.new()
			jm.radius = 0.62
			jm.height = 1.5
			jm.radial_segments = 12
			jm.rings = 7
			jaw.mesh = jm
			jaw.material_override = slime_material()
			_pit.add_child(jaw)
			_pit_jaws.append(jaw)
	_pit.visible = true
	_pit.global_position = skin
	_pit.global_transform = Transform3D(_basis_from_up(up), skin)
	var g := 0.55 + 1.15 * _sink
	_pit_bowl.scale = Vector3(g, 0.35 + 0.5 * _sink, g)
	# the bite: closed lobes at the top of each cycle, open at the
	# bottom, and nothing at all until the chew line
	var bite := 0.0
	if _sink > CHEW_LINE:
		bite = 0.5 - 0.5 * cos(TAU * (_chew_t / CHEW_PERIOD))
	for k in _pit_jaws.size():
		var jaw: MeshInstance3D = _pit_jaws[k]
		if not is_instance_valid(jaw):
			continue
		jaw.visible = bite > 0.01
		if not jaw.visible:
			continue
		var a := TAU * float(k) / float(_pit_jaws.size())
		var reach: float = lerpf(1.55, 0.34, bite)
		jaw.position = Vector3(cos(a) * reach, 0.35 + 0.45 * bite,
			sin(a) * reach)
		jaw.rotation_degrees = Vector3(
			cos(a) * lerpf(-14.0, -62.0, bite), -rad_to_deg(a),
			sin(a) * lerpf(14.0, 62.0, bite))
		jaw.scale = Vector3(1.0, lerpf(0.8, 1.35, bite), 1.0)

static func _basis_from_up(up: Vector3) -> Basis:
	var u := up.normalized()
	var x := u.cross(Vector3(0, 1, 0))
	if x.length() < 0.01:
		x = u.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, u, x.cross(u).normalized())

## WHEN TWO CONTINENTS MEET they crumple, and where they touched there
## is a mountain range. This is the entire geology of Eughe.
func _crumple_check(delta: float) -> void:
	for k in _ridge_cd.keys():
		_ridge_cd[k] = float(_ridge_cd[k]) - delta
	for i in _conts.size():
		for j in range(i + 1, _conts.size()):
			var a = _conts[i]["body"]
			var b = _conts[j]["body"]
			var gap: float = a.center.distance_to(b.center) \
				- (a.radius + b.radius) * 0.55
			if gap > 4.0:
				continue
			var key := "%s|%s" % [a.name, b.name]
			if float(_ridge_cd.get(key, 0.0)) > 0.0:
				continue
			_ridge_cd[key] = 120.0
			_raise_ridge(_conts[i], (b.center - a.center).normalized())
			_raise_ridge(_conts[j], (a.center - b.center).normalized())
			_trim_ridges(_conts[i])
			_trim_ridges(_conts[j])
			# NO ANNOUNCEMENT. Two pieces of a planet's terrain meeting
			# is weather, not news, and a banner about it while you are
			# on the other side of the galaxy minding your own business
			# is the least immersive thing in the game. You hear it if
			# you are near enough to hear it. That is all.
			if _near_player(a.center, 900.0):
				Sfx.play("break", -6.0)

## A fresh range along the coast that took the hit.
func _raise_ridge(c: Dictionary, dir: Vector3) -> void:
	var b = c["body"]
	var node: Node3D = c["node"]
	var host = Universe.body_named("Eughe")
	if not is_instance_valid(node) or host == null:
		return
	var range_root := Node3D.new()
	node.add_child(range_root)
	var ranges: Array = c.get("ranges", [])
	ranges.append(range_root)
	c["ranges"] = ranges
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b.name) + str(int(_t)))
	var axis: Vector3 = b.orbit_up.normalized()
	# the impact face, back in the frame the continent was built in
	var local_dir: Vector3 = dir.rotated(axis, -b.orbit_phase)
	for k in 16:
		var d := (local_dir * 2.2
			+ Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
				rng.randf_range(-1, 1)) * 0.5).normalized()
		if not Universe.slime_contains(b,
				host.center + d.rotated(axis, b.orbit_phase) * b.orbit_r):
			continue
		var h := rng.randf_range(10.0, 34.0)
		var peak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = rng.randf_range(4.0, 11.0)
		cm.height = h
		cm.radial_segments = 7
		peak.mesh = cm
		peak.material_override = slime_material()
		range_root.add_child(peak)
		peak.position = d * (b.orbit_r + b.thick * 0.5 + h * 0.3)
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

const MAX_RANGES := 3

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
