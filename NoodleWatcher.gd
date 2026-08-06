class_name NoodleWatcher
extends Node3D
## THE noodle god: a cosmic tangle with one enormous eye, parked in the
## sky no matter where you go. It drifts slowly, it always faces you,
## and its mood is legible at a glance -- calm gold coils when appeased,
## red pulsing glare as wrath climbs. Angry enough, it starts reaching
## into your head: zaps, shoves, scrambled hands. Annoying by design,
## lethal only if you let wrath max out -- then its JUDGMENT tendril
## descends (JudgmentFx below) and the geometry lesson begins.

const DIST := 60000.0   # a proper cosmic distance
const SCALE := 9.0      # and a proper cosmic size: farther AND bigger,
						# so parallax says "that thing is enormous"

var _dir: Vector3 = Vector3(0.4, 0.55, -0.73).normalized()
var _scramble_t: float = 6.0
var _scrambling: float = 0.0
var _eye_mat: StandardMaterial3D
var _pupil: MeshInstance3D
var _iris: MeshInstance3D
var _coils: Array = []
var _tendrils: Array = []
var _t: float = 0.0
var _mischief_t: float = 20.0
var _grudge: float = 0.0    # time spent hated: the effects compound
var _whisper_t: float = 9.0

func _ready() -> void:
	add_to_group("noodle_watcher")
	scale = Vector3.ONE * SCALE
	# the eye
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 620.0
	em.height = 1240.0
	eye.mesh = em
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color("#f5eee0")
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color("#ffcf40")
	_eye_mat.emission_energy_multiplier = 0.4
	eye.material_override = _eye_mat
	add_child(eye)
	_pupil = MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 300.0
	pm.height = 600.0
	_pupil.mesh = pm
	_pupil.position = Vector3(0, 0, -520.0)   # sits ON the eye, aimed at YOU
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color("#0e0a04")
	_pupil.material_override = pmat
	add_child(_pupil)
	# iris ring framing the pupil -- THIS is what reads as "looking"
	_iris = MeshInstance3D.new()
	var im := TorusMesh.new()
	im.inner_radius = 300.0
	im.outer_radius = 380.0
	_iris.mesh = im
	_iris.rotation_degrees = Vector3(90, 0, 0)
	_iris.position = Vector3(0, 0, -500.0)
	var imat := StandardMaterial3D.new()
	imat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	imat.albedo_color = Color("#c89020")
	imat.emission_enabled = true
	imat.emission = Color("#ffcf40")
	imat.emission_energy_multiplier = 0.8
	_iris.material_override = imat
	add_child(_iris)
	# the tangle: fat noodle coils wreathing the eye
	for i in 12:
		var coil := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = randf_range(520.0, 700.0)
		tm.outer_radius = tm.inner_radius + randf_range(90.0, 150.0)
		coil.mesh = tm
		coil.rotation_degrees = Vector3(randf_range(0, 180), randf_range(0, 180), randf_range(0, 180))
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color("#e8b830")
		cmat.emission_enabled = true
		cmat.emission = Color("#ffcf40")
		cmat.emission_energy_multiplier = 0.25
		coil.material_override = cmat
		add_child(coil)
		_coils.append(coil)
	# THE TENDRILS: one smooth shader-bent tube each, the god's own gold
	# with the crawling orange pulse. Calm: stubby nubs in the tangle.
	# Furious: they STRETCH -- kilometres of arm raking across the whole
	# sky, longer than any planet is wide. At skybox distance that reads
	# as something bigger than the universe it hangs over.
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * 640.0, sin(ang) * 640.0, 0)
		root.rotation_degrees = Vector3(0, 0, rad_to_deg(ang) - 90.0)
		add_child(root)
		var tendril := NoodleGod.make_tendril(3200.0, 230.0, randf() * TAU)
		tendril.material_override.set_shader_parameter("wave_amt", 420.0)
		tendril.material_override.set_shader_parameter("wave_speed", 0.6)
		root.add_child(tendril)
		root.scale = Vector3(1, 0.12, 1)   # sheathed until the mood sours
		_tendrils.append({"root": root, "mat": tendril.material_override,
			"ang": ang})

func _process(delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	_t += delta
	# slow celestial drift: it circles you like a thought you can't drop
	_dir = _dir.rotated(Vector3.UP, delta * 0.004)
	var wob := sin(_t * 0.05) * 0.06
	var d := (_dir + Vector3(0, wob, 0)).normalized()
	global_position = p.global_position + d * DIST
	# the god CANNOT leave. Step outside and he stays behind, pressed
	# against the inside of his own sky, staring out through the bars.
	if global_position.length() > Universe.BOUNDARY - 400.0:
		global_position = global_position.normalized() \
			* (Universe.BOUNDARY - 400.0)
	# the god CANNOT leave. Step outside and he presses against the
	# inside of the sky, staring out at you through his own bars.
	if global_position.length() > Universe.BOUNDARY - 400.0:
		global_position = global_position.normalized() \
			* (Universe.BOUNDARY - 400.0)
	# the -Z face (pupil + iris) points DEAD AT you, every frame, always
	var up_ref := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	look_at(p.global_position, up_ref)
	scale = Vector3.ONE * SCALE   # look_at eats the scale: put it back

	# mood on its face: gold and sleepy -> red and wide -> and then, when
	# the grudge is old enough, the lights start going OUT. an angry god
	# glows. an ancient one is a silhouette blotting out the stars.
	var w: float = Game.wrath / Game.WRATH_MAX
	# beyond the edge the god cannot reach you; past the eighth monolith
	# he has nothing left to police. Either way: he WATCHES -- and with
	# the sky broken he watches FURIOUS -- but he does not act.
	# INDOORS IS SANCTUARY: inside any pocket interior (a house, a
	# temple) the god cannot reach through the roof. He waits.
	var untouchable: bool = Game.zone != "" \
		or p.global_position.length() > Universe.BOUNDARY
	var sky_broken: bool = Game.monolith_stage >= 8
	if sky_broken:
		w = maxf(w, 0.85)   # the stare of a god who lost
	# after it kills you (or anything does), it BROODS: a few minutes of
	# locked red silence. still watching. still angry. not acting.
	var standby := Game.playtime < Game.god_standby_until
	if w > 0.6:
		_grudge = minf(60.0, _grudge + delta)     # it REMEMBERS
	elif w < 0.3:
		_grudge = maxf(0.0, _grudge - delta * 0.15)   # it forgets very slowly
	var gk := clampf(_grudge / 60.0, 0.0, 1.0)
	if standby:
		# brooding: pure steady red, slow pulse like a banked coal
		_eye_mat.emission = Color("#ff2b1a")
		_eye_mat.albedo_color = Color("#3a0d08")
		_eye_mat.emission_energy_multiplier = 1.1 + sin(_t * 1.1) * 0.25
	else:
		_eye_mat.emission = Color("#ffcf40").lerp(Color("#ff2b1a"), w)
		_eye_mat.albedo_color = Color("#f5eee0").lerp(Color("#050505"), gk * 0.9)
		_eye_mat.emission_energy_multiplier = (0.4 + w * (1.6 + sin(_t * 6.0) * 0.8 * w)) \
			* (1.0 - gk * 0.85)
	var ps := 0.55 + w * 0.65
	if w > 0.85:
		ps += sin(_t * 31.0) * 0.06 + randf_range(-0.02, 0.02)   # it twitches
	_pupil.scale = Vector3(ps, ps, ps * 0.45)   # flattened: reads as a pupil
	# its shape refuses to be memorized: every few seconds, for a tenth
	# of a second, the coils are ARRANGED DIFFERENTLY. blink and check.
	if w > 0.7:
		_scramble_t -= delta
		if _scramble_t <= 0.0:
			_scramble_t = randf_range(4.0, 9.0)
			_scrambling = 0.12
			for c in _coils:
				c.rotation_degrees = Vector3(randf_range(0, 180),
					randf_range(0, 180), randf_range(0, 180))
	_scrambling = maxf(0.0, _scrambling - delta)
	if _iris:
		_iris.material_override.emission = _eye_mat.emission
		_iris.scale = Vector3.ONE * (0.8 + w * 0.4)
	for i in _coils.size():
		var coil: MeshInstance3D = _coils[i]
		coil.rotation_degrees += Vector3(delta * (2.0 + w * 14.0), delta * 3.0, 0)
	# tendrils: length IS the mood. stubs when calm; at full fury each
	# arm stretches past 12km, raking the sky, whole crown whirling.
	for i in _tendrils.size():
		var e: Dictionary = _tendrils[i]
		var root: Node3D = e["root"]
		var reveal := clampf((w - float(i) / 8.0 * 0.6) * 3.0, 0.01, 1.0)
		var ext := 0.12 + reveal * (0.2 + w * w * 3.9)   # up to ~13km of arm
		if standby:
			ext = 0.12   # arms sheathed while it broods
		root.scale = root.scale.lerp(Vector3(1, ext, 1), delta * 1.5)
		e["ang"] += delta * (0.02 + w * w * 1.4)   # calm drift -> furious whirl
		root.position = Vector3(cos(e["ang"]) * 640.0, sin(e["ang"]) * 640.0, 0)
		root.rotation_degrees.z = rad_to_deg(e["ang"]) - 90.0
		var m: ShaderMaterial = e["mat"]
		# ALWAYS the noodle gold. the eye does the mood; the noodles are
		# the noodles.
		m.set_shader_parameter("glow", 0.5 + w * 1.8)
		m.set_shader_parameter("wave_amt", 300.0 + w * 900.0)
		m.set_shader_parameter("wave_speed", 0.5 + w * 3.2)

	# --- while brooding it does NOTHING. it just watches, red. ---
	if standby:
		return

	# --- the eldritch ambience: it gets under your skin and STAYS there ---
	if Game.wrath >= 60.0 and not Game.dead and not untouchable \
			and not sky_broken:
		# your view drifts, gently, wrongly -- like something else is
		# steering by a degree. maddening on purpose.
		if p is CharacterBody3D and "_look" in p and Game.mode == Game.Mode.ON_FOOT:
			p._look += Vector2(sin(_t * 0.7) + sin(_t * 1.9) * 0.5,
				cos(_t * 1.1)) * delta * 26.0 * (w - 0.55)
		# half-heard murmurs from nowhere in particular
		_whisper_t -= delta
		if _whisper_t <= 0.0:
			_whisper_t = randf_range(6.0, 14.0) / (1.0 + _grudge / 30.0)
			Sfx.play("hurt" if randf() < 0.5 else "denied", randf_range(-30.0, -24.0))

	# --- telepathic mischief: annoying, damaging, never a death sentence ---
	if Game.wrath < 30.0 or Game.dead or Game.mode != Game.Mode.ON_FOOT \
			or untouchable or sky_broken:
		return
	_mischief_t -= delta
	if _mischief_t > 0.0:
		return
	# angrier god, shorter patience -- the grudge compounds it, and every
	# brood it has survived makes it permanently quicker to act
	_mischief_t = lerpf(28.0, 8.0, w) / (1.0 + _grudge / 30.0) \
		/ (1.0 + float(Game.god_cycles) * 0.25) * randf_range(0.7, 1.3)
	match randi() % 5:
		0:
			# a zap: thin red thought-beam from the eye, small bite of damage
			_beam(p.global_position)
			# stings, never slays: won't take you below 5 hp.
			# (it stings HARDER each time it has brooded, though.)
			Game.hurt(clampf(Game.health - 5.0, 0.0,
				7.0 + 2.0 * float(Game.god_cycles)))
		1:
			# a shove: the sky flicks you like a crumb
			if p is CharacterBody3D:
				var kick := Vector3(randf_range(-1, 1), randf_range(0.3, 1), randf_range(-1, 1)).normalized()
				p.velocity += kick * randf_range(6.0, 11.0)
				if "_shake" in p:
					p._shake = 0.35
		2:
			# a scramble: your hand forgets what it was holding
			Inventory.select_slot(randi() % 5)
		3:
			# THE SMACK: a tendril reaches all the way down and swats you
			var smack := _SmackFx.new()
			smack.target = p
			get_tree().current_scene.add_child(smack)
			smack.global_position = p.global_position
		4:
			# THE GRAB: it takes you. it considers you. it discards you.
			# The full clutch-and-hurl is reserved for a god at 70+ wrath
			# -- when the eye is SMALL, you are not worth lifting.
			if Game.wrath < 70.0:
				return
			var grab := _GrabFx.new()
			grab.target = p
			get_tree().current_scene.add_child(grab)
			grab.global_position = p.global_position


## Attack fx are built along +Y; on a sphere, +Y must mean YOUR up.
static func orient_to_gravity(n: Node3D) -> void:
	var b = Universe.nearest(n.global_position)
	var up: Vector3 = (n.global_position - b.center).normalized()
	var x := up.cross(Vector3.RIGHT)
	if x.length() < 0.05:
		x = up.cross(Vector3.FORWARD)
	x = x.normalized()
	n.global_transform.basis = Basis(x, up, x.cross(up).normalized() * -1.0).orthonormalized()

## MAX WRATH: the terminal grab. One vast tendril descends over ~8 slow
## seconds -- your appeasement window. Get wrath under 40 (noodles, fast)
## and it withdraws. Fail, and it takes you: the Pythagorean sentence.
class JudgmentFx extends Node3D:
	var _oriented := false
	var target: Node = null
	var _life := 0.0
	var _tip: MeshInstance3D
	func _ready() -> void:
		_tip = NoodleGod.make_tendril(600.0, 14.0, randf() * TAU)
		_tip.rotation_degrees = Vector3(180, 0, 0)   # hangs DOWN from heaven
		_tip.position = Vector3(0, 900.0, 0)
		_tip.material_override.set_shader_parameter("wave_amt", 40.0)
		_tip.material_override.set_shader_parameter("glow", 2.4)
		add_child(_tip)
	func _process(delta: float) -> void:
		if not _oriented:
			_oriented = true
			NoodleWatcher.orient_to_gravity(self)
		_life += delta
		# mercy check, the whole way down
		if Game.wrath < 40.0:
			_tip.position.y += delta * 400.0   # withdraws, unhurried
			if _tip.position.y > 1400.0:
				Game.wrath_event_over(false)
				queue_free()
			return
		# descent: 8 seconds from heaven to your head
		_tip.position.y = maxf(40.0, 900.0 - _life * 108.0)
		if target and is_instance_valid(target):
			global_position = global_position.lerp(target.global_position, delta * 2.0)
			if _tip.position.y <= 40.5:
				# taken.
				Game.wrath_event_over(true)
				queue_free()

## A tendril tip that closes around you, hoists you into the sky, and
## hurls you across the landscape like something it's done judging.
class _GrabFx extends Node3D:
	var _oriented := false
	var target: Node = null
	var _life := 0.0
	var _tip: MeshInstance3D
	var _held := false
	func _ready() -> void:
		_tip = NoodleGod.make_tendril(90.0, 4.5, randf() * TAU)
		_tip.rotation_degrees = Vector3(180, 0, 0)   # hangs DOWN from the sky
		_tip.position = Vector3(0, 140.0, 0)
		add_child(_tip)
		Sfx.play("warp", -14.0)
	func _process(delta: float) -> void:
		if not _oriented:
			_oriented = true
			NoodleWatcher.orient_to_gravity(self)
		_life += delta
		# descend (0-0.8), clutch + hoist (0.8-2.0), HURL (2.0)
		if _life < 0.8:
			_tip.position.y = lerpf(140.0, 92.0, _life / 0.8)
		elif target and is_instance_valid(target):
			if not _held:
				_held = true
				Sfx.play("hurt", -14.0)
			if _life < 2.0:
				# hoisted: you dangle from the tip, rising
				var lift := (_life - 0.8) / 1.2
				target.global_position = global_position \
					+ global_transform.basis.y * (2.0 + lift * 34.0)
				if "velocity" in target:
					target.velocity = Vector3.ZERO
				if "_shake" in target:
					target._shake = 0.4
				_tip.position.y = 92.0 - lift * -34.0
			elif _life >= 2.0 and _held:
				_held = false
				# discarded: a flat, contemptuous hurl across the world
				if "velocity" in target:
					var b := global_transform.basis
					target.velocity = (b.x * randf_range(-1, 1) + b.y * 0.35 \
						+ b.z * randf_range(-1, 1)).normalized() * 34.0
				Game.hurt(clampf(Game.health - 5.0, 0.0,
						8.0 + 2.0 * float(Game.god_cycles)))
				Sfx.play("explode", -10.0)
		if _life > 3.4:
			queue_free()

## A god-sized noodle arm whipping down out of the sky onto your head.
class _SmackFx extends Node3D:
	var _oriented := false
	var target: Node = null
	var _life := 0.0
	var _segs: Array = []
	var _hit := false
	func _ready() -> void:
		# a fat golden arm hanging 60m overhead, tip aimed at the target
		for j in 6:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r := 6.0 * (1.0 - float(j) / 6.0 * 0.6)
			sm.radius = r
			sm.height = r * 2.4
			s.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#ffcf40")
			m.emission_enabled = true
			m.emission = Color("#ff8c1a")
			m.emission_energy_multiplier = 1.6
			s.material_override = m
			s.position = Vector3(0, 60.0 - float(j) * 9.0, 0)
			add_child(s)
			_segs.append(s)
	func _process(delta: float) -> void:
		if not _oriented:
			_oriented = true
			NoodleWatcher.orient_to_gravity(self)
		_life += delta
		# wind up (0-0.5), SNAP down (0.5-0.75), linger, gone
		var drop := 0.0
		if _life > 0.5:
			drop = clampf((_life - 0.5) / 0.25, 0.0, 1.0)
		for j in _segs.size():
			var s: MeshInstance3D = _segs[j]
			var k := float(j) / 5.0
			s.position.y = (60.0 - float(j) * 9.0) * (1.0 - drop * (0.4 + k * 0.6))
			s.position.x = sin(_life * 10.0 + k * 3.0) * (1.0 - drop) * 4.0 * k
		if drop >= 1.0 and not _hit:
			_hit = true
			Sfx.play("explode", -8.0)
			if target and is_instance_valid(target):
				Game.hurt(clampf(Game.health - 5.0, 0.0,
						10.0 + 2.0 * float(Game.god_cycles)))   # stings, never slays
				if target is CharacterBody3D:
					var b2 := global_transform.basis
					target.velocity += (b2.x * randf_range(-1, 1) + b2.y * 0.4 \
						+ b2.z * randf_range(-1, 1)).normalized() * 14.0
				if "_shake" in target:
					target._shake = 0.6
		if _life > 1.6:
			queue_free()

## Visible line of malice: eye to player, gone in half a second.
class _BeamFx extends Node3D:
	var life := 0.5
	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()

func _beam(target: Vector3) -> void:
	var fx := _BeamFx.new()
	get_parent().add_child(fx)
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#ff2b1a")
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color("#ff2b1a")
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(global_position - Vector3(0, 0, 0))
	im.surface_add_vertex(target)
	im.surface_end()
	mi.mesh = im
	fx.add_child(mi)
	Sfx.play("hurt", -18.0)
