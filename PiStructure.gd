class_name PiStructure
extends Node3D
## Decorates the Pi planet: latitude "pi strips" of tablets stamped with
## the digits of pi, plus a glowing core. Built in local space at the
## planet's centre (Main places it at body.center).

const DIGITS := "31415926535897932384626433832795028841971693993751"

var _radius: float = 100.0
var _worms: Array = []   # {u, v, th, spd, f, ph, segs[], cd}

var _ring: Node3D
var _active: bool = false   # worms sleep until someone touches the ground
var _tease_w = null         # the one worm that sometimes surfaces anyway
var _tease_until: float = 0.0

func build(radius: float) -> void:
	_radius = radius
	Game.broke.connect(_on_heard_break)
	# --- golden semicircle arches: break one for the item. breaking one
	# also enrages every worm on YOUR side of the planet for 6 seconds ---
	for i in 10:
		var arc := PiArc.new()
		arc.owner_pi = self
		add_child(arc)
		var adir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		arc.position = adir * radius
		arc.transform.basis = _basis_from_up(adir)
	# --- a giant slow-spinning ring of digits, Saturn-style ---
	_ring = Node3D.new()
	_ring.rotation_degrees = Vector3(24, 0, 8)
	add_child(_ring)
	for i in 44:
		var gl := Label3D.new()
		gl.text = DIGITS[i % DIGITS.length()]
		gl.font_size = 120
		gl.pixel_size = 0.03
		gl.modulate = Color.from_hsv(fmod(float(i) * 0.023, 1.0), 0.35, 1.0)
		gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var ra := TAU * float(i) / 44.0
		gl.position = Vector3(cos(ra), 0, sin(ra)) * radius * 1.45
		_ring.add_child(gl)
	# --- the great pi rides the digit ring like a moon ---
	var big := Label3D.new()
	big.text = "π"
	big.font_size = 512
	big.pixel_size = 0.05
	big.modulate = Color("#ffd166")
	big.outline_modulate = Color("#7a3c00")
	big.outline_size = 40
	big.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	big.position = Vector3(radius * 1.65, 0, 0)
	_ring.add_child(big)
	# GIANT PI WORMS: strips of digits that breach like whales, arc through
	# the sky, burrow, tunnel through the planet and erupt somewhere else.
	# They sleep under the crust until a trespasser touches the ground.
	for i in 12:
		_make_worm(i)
	_set_worms_visible(false)
	# glowing core
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 0.45
	sm.height = radius * 0.9
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.emission_enabled = true
	cm.emission = Color("#ff8c1a")
	cm.emission_energy_multiplier = 3.0
	cm.albedo_color = Color("#ff8c1a")
	core.material_override = cm
	add_child(core)

	# latitude bands of digit tablets sitting on the surface
	var bands := 7
	var di := 0
	for b in bands:
		var lat := (float(b) / float(bands - 1) - 0.5) * PI * 0.8   # -72..+72 deg
		var y := sin(lat) * radius
		var ring_r := cos(lat) * radius
		var per := maxi(6, int(ring_r / 6.0))
		for j in per:
			var ang := TAU * float(j) / float(per)
			var dir := Vector3(cos(ang) * ring_r, y, sin(ang) * ring_r)
			var up := dir.normalized()
			var tablet := Destructible.new()
			var hue := Color.from_hsv(fmod(float(b) * 0.13, 1.0), 0.6, 1.0)
			tablet.setup(Vector3(2.2, 0.5, 2.2), hue, 1, 16, 0.5)
			add_child(tablet)
			tablet.position = dir + up * 0.3
			tablet.global_transform.basis = _basis_from_up(up)
			var lbl := Label3D.new()
			lbl.text = DIGITS[di % DIGITS.length()]
			di += 1
			lbl.font_size = 48
			lbl.modulate = Color("#fff2d0")
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(lbl)
			lbl.position = dir + up * 1.6

func _make_worm(idx: int) -> void:
	var u := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var v := u.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()).normalized()
	var segs: Array = []
	for k in 12:
		# the worm IS pi, made of pure floating glyphs: a giant 3 head,
		# a little . neck, then 1 4 1 5 9 2 ... trailing down the body
		var seg := WormSeg.new()
		seg.owner_pi = self
		seg.widx = idx
		seg.collision_layer = 2
		seg.collision_mask = 0
		var cc := CollisionShape3D.new()
		var cs := SphereShape3D.new()
		cs.radius = 2.4 if k == 0 else 1.7
		cc.shape = cs
		seg.add_child(cc)
		var lbl := Label3D.new()
		if k == 0:
			lbl.text = "3"
			lbl.font_size = 240
		elif k == 1:
			lbl.text = "."
			lbl.font_size = 160
		else:
			lbl.text = DIGITS[(k - 1) % DIGITS.length()]
			lbl.font_size = 150
		lbl.pixel_size = 0.022
		lbl.modulate = Color("#ffd166")
		lbl.outline_modulate = Color("#7a3c00")
		lbl.outline_size = 28
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = false
		seg.add_child(lbl)
		add_child(seg)
		segs.append(seg)
	_worms.append({
		"u": u, "v": v, "th": randf() * TAU,
		"spd": randf_range(0.10, 0.22),          # radians/s along its orbit
		"spd_target": randf_range(0.10, 0.26),
		"spd_t": randf_range(2.0, 6.0),
		"f": 2 + randi() % 3,                     # humps per orbit
		"f2": randf_range(1.2, 2.2),              # second, irrational hump wave
		"ph": randf() * TAU,
		"ph2": randf() * TAU,
		"axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
		"prec": randf_range(0.05, 0.18),          # orbit-plane drift speed
		"axis_t": randf_range(3.0, 8.0),
		"segs": segs, "cd": 0.0, "above": false, "hunt_t": 0.0, "aggro_t": 0.0,
	})

func _worm_pos(w: Dictionary, th: float) -> Vector3:
	# TWO overlapping waves with an irrational frequency ratio: the dive
	# points never repeat. Above surface on crests, deep inside on troughs.
	var r: float = _radius * (1.0 \
		+ 0.38 * sin(float(w["f"]) * th + float(w["ph"])) \
		+ 0.26 * sin(float(w["f2"]) * th * 1.6180339 + float(w["ph2"])))
	return (w["u"] * cos(th) + w["v"] * sin(th)) * r

## Breaking ANYTHING near the planet wakes them. They hear it.
func _on_heard_break() -> void:
	if _active:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p and to_local(p.global_position).length() < _radius * 2.5:
		_active = true
		_set_worms_visible(true)
		Sfx.play_at("rumble", p.global_position, 6.0)

func _set_worms_visible(on: bool) -> void:
	for w in _worms:
		for seg in w["segs"]:
			seg.visible = on

func _process(delta: float) -> void:
	if _ring:
		_ring.rotate_y(delta * 0.05)
	var p := get_tree().get_first_node_in_group("player")
	# dormant until someone TOUCHES the ground; back to sleep only when
	# the trespasser is super far away from the planet
	var pdist: float = to_local(p.global_position).length() if p else 1e9
	if not _active:
		if p and Game.mode == Game.Mode.ON_FOOT and not Game.dead and pdist < _radius + 4.0:
			_active = true
			_set_worms_visible(true)
			Sfx.play_at("rumble", p.global_position, 6.0)
		else:
			# once in a while ONE worm breaches anyway. watch from afar
			# long enough and the planet gives its secret away.
			if _tease_w == null and randf() < delta * 0.02:
				_tease_w = _worms[randi() % _worms.size()]
				_tease_until = 10.0
				for seg in _tease_w["segs"]:
					seg.visible = true
			if _tease_w != null:
				_tease_until -= delta
				_tease_w["th"] = fmod(float(_tease_w["th"]) + float(_tease_w["spd"]) * delta, TAU)
				var tsegs: Array = _tease_w["segs"]
				for k in tsegs.size():
					var tth: float = float(_tease_w["th"]) - float(k) * 0.045
					tsegs[k].position = _worm_pos(_tease_w, tth)
				var thead := _worm_pos(_tease_w, float(_tease_w["th"]))
				var tabove := thead.length() > _radius + 1.0
				if tabove != bool(_tease_w["above"]):
					_tease_w["above"] = tabove
					Sfx.play_at("rumble", to_global(thead.normalized() * _radius), 3.0)
				if _tease_until <= 0.0:
					for seg in tsegs:
						seg.visible = false
					_tease_w = null
			return
	elif pdist > _radius * 4.0:
		_active = false
		_set_worms_visible(false)
		return
	var can_hurt := p != null and Game.mode == Game.Mode.ON_FOOT and not Game.dead
	for w in _worms:
		w["th"] = fmod(float(w["th"]) + float(w["spd"]) * delta, TAU)
		w["cd"] = float(w["cd"]) - delta
		# speed wanders: lunges and lulls
		w["spd_t"] = float(w["spd_t"]) - delta
		if float(w["spd_t"]) <= 0.0:
			w["spd_t"] = randf_range(2.0, 6.0)
			w["spd_target"] = randf_range(0.08, 0.30)
		w["spd"] = lerpf(float(w["spd"]), float(w["spd_target"]), delta * 0.8)
		# the whole orbit plane slowly tumbles around a drifting axis --
		# unless the worm is HUNTING, in which case its aim stays locked
		w["axis_t"] = float(w["axis_t"]) - delta
		w["aggro_t"] = maxf(0.0, float(w["aggro_t"]) - delta)
		var hunting := float(w["hunt_t"]) > 0.0
		if hunting:
			w["hunt_t"] = float(w["hunt_t"]) - delta
			w["spd_target"] = 0.45   # closing speed
			if float(w["hunt_t"]) <= 0.0 and float(w["aggro_t"]) > 0.0:
				w["axis_t"] = 0.8   # missed, still furious: rewind fast
		elif float(w["axis_t"]) <= 0.0:
			w["axis_t"] = randf_range(3.0, 8.0)
			# sometimes it decides the trespasser IS the next digit.
			# a SHOT worm decides that every single time.
			var chance := 1.0 if float(w["aggro_t"]) > 0.0 else 0.30
			if can_hurt and randf() < chance \
					and to_local(p.global_position).length() < _radius * 2.2:
				_begin_hunt(w, p)
			else:
				w["axis"] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				w["prec"] = randf_range(0.05, 0.22)
		if not hunting:
			var rot := Basis(w["axis"], float(w["prec"]) * delta)
			w["u"] = (rot * w["u"]).normalized()
			var v2: Vector3 = rot * w["v"]
			w["v"] = (v2 - w["u"] * w["u"].dot(v2)).normalized()
		# ground-shaking rumble at the EXACT spot the head breaches/burrows
		var head_pos := _worm_pos(w, float(w["th"]))
		var above_now := head_pos.length() > _radius + 1.0
		if above_now != bool(w["above"]):
			w["above"] = above_now
			var breach_point := head_pos.normalized() * _radius
			Sfx.play_at("rumble", to_global(breach_point), 4.0)
		var segs: Array = w["segs"]
		for k in segs.size():
			var th: float = float(w["th"]) - float(k) * 0.045
			var seg: Node3D = segs[k]
			seg.position = _worm_pos(w, th)
		# worms bite: touch ANY segment = pain. A hunting worm's slam is brutal.
		if can_hurt and float(w["cd"]) <= 0.0:
			for k in segs.size():
				var sg: Node3D = segs[k]
				var reach := 5.0 if k == 0 else 3.4   # head is huge; body is thick
				if sg.global_position.distance_to(p.global_position) < reach:
					if float(w["hunt_t"]) > 0.0:
						Game.hurt(45.0)
						w["hunt_t"] = 0.0
						if "velocity" in p:
							p.velocity += (p.global_position - sg.global_position).normalized() * 18.0
					else:
						Game.hurt(12.0)
					w["cd"] = 0.8
					break

## Re-aim a worm so its next breach erupts exactly where YOU are standing.
func _begin_hunt(w: Dictionary, p: Node3D) -> void:
	var lp := to_local(p.global_position)
	if lp.length() < 1.0:
		return
	var udir := lp.normalized()
	var rnd := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var vdir := (rnd - udir * udir.dot(rnd)).normalized()
	if vdir.length() < 0.5:
		return
	w["u"] = udir
	w["v"] = vdir
	# solve the phase so the hump crests at the player's altitude at th = 0
	var s1 := clampf((lp.length() / _radius - 1.0 - 0.26 * sin(float(w["ph2"]))) / 0.38, -1.0, 1.0)
	w["ph"] = asin(s1)
	w["th"] = -0.55            # swoop in from just over the horizon
	w["spd"] = 0.25
	w["hunt_t"] = 6.0
	# no announcement. just the ground starting to shake under your feet.
	Sfx.play_at("rumble", p.global_position, 6.0)

## Breaking a semicircle enrages every worm on that side of the planet
## for 6 seconds (breaking another RESETS the clock, it does not stack).
func anger_side(at_local: Vector3) -> void:
	var side := at_local.normalized()
	for w in _worms:
		var head := _worm_pos(w, float(w["th"]))
		if head.normalized().dot(side) > 0.0:
			w["aggro_t"] = 6.0
			w["axis_t"] = minf(float(w["axis_t"]), 0.4)
	Sfx.play_at("rumble", to_global(side * _radius), 5.0)

## A golden half-circle arch standing on the surface. Smash it: +1
## semicircle item, and the local worms take it PERSONALLY.
class PiArc extends StaticBody3D:
	var owner_pi: PiStructure

	func _ready() -> void:
		var segs := 9
		for i in segs:
			var a := PI * float(i) / float(segs - 1)   # 0..180 deg
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.8, 0.8, 1.4)
			mi.mesh = bm
			mi.material_override = Destructible.make_material(Color("#ffd166"), 1.6)
			mi.position = Vector3(cos(a) * 2.6, sin(a) * 2.6 + 0.3, 0)
			mi.rotation = Vector3(0, 0, a)
			add_child(mi)
		var cc := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(5.6, 3.4, 1.4)
		cc.shape = cs
		cc.position = Vector3(0, 1.8, 0)
		add_child(cc)

	func take_damage(_d: float, dir: Vector3) -> void:
		destroy(dir)

	func destroy(push_dir: Vector3) -> void:
		Inventory.give("semicircle", 1)
		Destructible.spawn_debris(get_parent(), global_position, Vector3(1.2, 1.2, 1.2), Color("#ffd166"), push_dir)
		Sfx.play("explode", -14.0)
		if owner_pi and is_instance_valid(owner_pi):
			owner_pi.anger_side(owner_pi.to_local(global_position))
		queue_free()

## Shootable worm segment: bullets anger the whole worm.
class WormSeg extends StaticBody3D:
	var owner_pi: PiStructure
	var widx: int = -1
	func take_damage(_d: float, _dir: Vector3) -> void:
		if owner_pi and is_instance_valid(owner_pi):
			owner_pi.worm_shot(widx)

## A shot worm holds a 25s grudge: it re-aims at you again and again.
func worm_shot(i: int) -> void:
	if i < 0 or i >= _worms.size():
		return
	var w: Dictionary = _worms[i]
	var fresh := float(w["aggro_t"]) <= 0.0
	w["aggro_t"] = 25.0
	w["axis_t"] = minf(float(w["axis_t"]), 0.3)   # re-decide NOW
	Sfx.play_at("rumble", to_global(_worm_pos(w, float(w["th"]))), 4.0)
	if fresh:
		pass   # it does not announce itself. you'll know.

func _basis_from_up(up: Vector3) -> Basis:
	var t := Vector3(0, 1, 0)
	if absf(up.dot(t)) > 0.99:
		t = Vector3(1, 0, 0)
	var x := t.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).orthonormalized()
