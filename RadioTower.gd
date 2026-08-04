class_name RadioTower
extends Machine
## The intergalactic radio: a dish you aim at the sky, a frequency you
## sweep, and the universe talking back. Earth runs a news desk. The
## shader system leaks something that was a voice once. The noodle god
## broadcasts, because of course it does. Most other planets just hum
## their own procedurally generated music.
##
## Runs on electricity (wire it), and only bothers to exist while a
## player is within planet-scale range. F opens the dish map.

const DRAIN := 1.2
const HEAR_RANGE := 1500.0

var freq: float = 98.0          # MHz-ish dial, 88..108
var aim_dir: Vector3 = Vector3.UP
var stations: Array = []        # {name, freq, dir_of, kind, body}
var _dish: MeshInstance3D
var _dish_pivot: Node3D
var _talk: AudioStreamPlayer3D  # the tuned station's output
var _hiss: AudioStreamPlayer3D  # static bed
var _cur_station: int = -1
var _sentence_cd: float = 0.0
var powered: bool = false

func _init() -> void:
	title = "RADIO"
	box_color = Color("#2a3038")
	box_size = Vector3(1.2, 1.0, 1.2)
	refund_id = "radio"
	shows_in = false
	shows_out = false
	buf_cap = 300.0

func _ready() -> void:
	super._ready()
	add_to_group("radio")
	dress_industrial(Color("#1c2128"))
	# mast + dish on a pivot so the aim is VISIBLE
	var mast := CylinderMesh.new()
	mast.top_radius = 0.06
	mast.bottom_radius = 0.09
	mast.height = 1.6
	part(mast, Vector3(0, box_size.y + 0.8, 0), Color("#8a9098"), 0.1)
	_dish_pivot = Node3D.new()
	_dish_pivot.position = Vector3(0, box_size.y + 1.7, 0)
	add_child(_dish_pivot)
	_dish = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.85
	dm.height = 0.5
	dm.is_hemisphere = true
	_dish.mesh = dm
	_dish.rotation_degrees.x = 90.0
	_dish.material_override = Surfaces.metal(Color("#c8ccd4"))
	_dish_pivot.add_child(_dish)
	var feed := CylinderMesh.new()
	feed.top_radius = 0.03
	feed.bottom_radius = 0.03
	feed.height = 0.7
	var fmi := MeshInstance3D.new()
	fmi.mesh = feed
	fmi.rotation_degrees.x = 90.0
	fmi.position = Vector3(0, 0, -0.4)
	fmi.material_override = Surfaces.metal(Color("#8a9098"))
	_dish_pivot.add_child(fmi)
	_talk = AudioStreamPlayer3D.new()
	_talk.unit_size = 9.0
	_talk.max_distance = 120.0
	add_child(_talk)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.unit_size = 7.0
	_hiss.max_distance = 60.0
	_hiss.stream = RadioLib.static_noise()
	add_child(_hiss)
	_build_stations()

## The dial of the universe: who is broadcasting, from where, on what.
func _build_stations() -> void:
	stations.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for b in Universe.bodies:
		var kind := str(b.kind) if "kind" in b else ""
		var st := {}
		match b.name:
			"Earth":
				st = {"name": "EARTH NEWS", "type": "news"}
				stations.append({"name": "EARTH CLASSICS", "type": "music",
					"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1),
					"body": b, "kind": "earth"})
				stations.append({"name": "RICK FM", "type": "rick",
					"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1),
					"body": b, "kind": "rick"})
			"Wth":
				st = {"name": "??? (shader system)", "type": "alien"}
			"Pi", "Verdant", "Crystalia", "Donut", "Euclid", "Circuitia", "Sanus", "Varnisol":
				st = {"name": "%s FM" % b.name, "type": "music"}
			"Jupiter":
				st = {"name": "JUPITER JAZZ", "type": "music"}
			_:
				continue
		st["freq"] = snappedf(rng.randf_range(88.5, 107.5), 0.1)
		st["body"] = b
		st["kind"] = kind
		stations.append(st)
	# the noodle god's own frequency, from wherever it broods
	stations.append({"name": "THE SAUCE", "type": "noodle",
		"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1), "body": null,
		"kind": "noodle"})
	# and something out by the shadow temple that isn't music and isn't
	# words. don't listen too long.
	stations.append({"name": "(unlabeled)", "type": "eerie",
		"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1), "body": null,
		"kind": "eerie", "fixed_dir": Zones.SHADOW_POS})

func station_dir(st: Dictionary) -> Vector3:
	if st.has("fixed_dir"):
		return (st["fixed_dir"] - global_position).normalized()
	if st["body"] != null:
		var bb = st["body"]
		if global_position.distance_to(bb.center) < float(bb.radius) * 1.6:
			# standing ON the broadcaster: signal's everywhere here, so
			# the dish points at the SKY like a sensible local antenna
			return (global_position - bb.center).normalized()
		return (bb.center - global_position).normalized()
	var w = get_tree().get_first_node_in_group("noodle_watcher")
	if w != null and w is Node3D:
		return (w.global_position - global_position).normalized()
	return (global_position - Universe.nearest(global_position).center).normalized()

func _is_local(st: Dictionary) -> bool:
	if st["body"] == null:
		return false
	return global_position.distance_to(st["body"].center) < float(st["body"].radius) * 1.6

## Signal quality 0..1: dish alignment x frequency accuracy. Stations
## on the planet you're STANDING ON are omnidirectional: only the dial
## matters, and all of them are reachable.
func signal_for(st: Dictionary) -> float:
	var a := align_for(st)
	var ferr: float = absf(freq - float(st["freq"]))
	var f := clampf(1.0 - ferr / 1.2, 0.0, 1.0)
	return a * f

## Alignment (spectrum display: activity you COULD tune). NARROW beam,
## ~20 degrees -- distant clusters bunch in angle, and a fat cone was
## hearing three galaxies at once.
func align_for(st: Dictionary) -> float:
	if _is_local(st):
		return 1.0
	return clampf((aim_dir.dot(station_dir(st)) - 0.94) / 0.06, 0.0, 1.0)

func aim_at(body_center: Vector3) -> void:
	var nb = Universe.nearest(global_position)
	if body_center.distance_to(nb.center) < 1.0 \
			and global_position.distance_to(nb.center) < float(nb.radius) * 1.6:
		aim_dir = (global_position - nb.center).normalized()   # local: aim UP
	else:
		aim_dir = (body_center - global_position).normalized()
	Sfx.play("click", -16.0)

func use() -> void:
	if get_tree().get_first_node_in_group("radio_ui") != null:
		return
	var ui := RadioUI.new()
	ui.radio = self
	get_tree().current_scene.add_child(ui)

func work(delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	var near: bool = p != null \
		and p.global_position.distance_to(global_position) < HEAR_RANGE
	powered = buf > 0.0 and near
	if not powered:
		if _talk.playing:
			_talk.stop()
		if _hiss.playing:
			_hiss.stop()
		_cur_station = -1
		return
	buf = maxf(0.0, buf - DRAIN * delta)
	# find the strongest signal on the current dial + aim -- every
	# frame, so dragging the dial/dish changes the sound LIVE
	var best := -1
	var bs := 0.0
	for i in stations.size():
		var sgn := signal_for(stations[i])
		if sgn > bs:
			bs = sgn
			best = i
	# static bed always runs while powered; ducks under a good signal.
	# volumes SLEW toward targets: analog, not stepped.
	if not _hiss.playing:
		_hiss.play()
	var hiss_target := linear_to_db(clampf(0.85 - bs * 0.8, 0.05, 1.0)) - 6.0
	_hiss.volume_db = lerpf(_hiss.volume_db, hiss_target, minf(1.0, delta * 14.0))
	if best != _cur_station:
		_cur_station = best
		_talk.stop()
		_sentence_cd = 0.15
	if best < 0 or bs < 0.05:
		if _talk.playing:
			_talk.stop()
		return
	var st: Dictionary = stations[best]
	var talk_target := linear_to_db(clampf(bs, 0.05, 1.0))
	_talk.volume_db = lerpf(_talk.volume_db, talk_target, minf(1.0, delta * 14.0))
	match str(st["type"]):
		"music":
			if not _talk.playing:
				_talk.stream = RadioLib.music_loop(int(st["freq"] * 10.0), str(st["kind"]))
				_talk.play()
		"eerie":
			if not _talk.playing:
				_talk.stream = RadioLib.eerie_loop()
				_talk.play()
		_:
			_sentence_cd -= delta
			if not _talk.playing and _sentence_cd <= 0.0:
				var wav: AudioStreamWAV = null
				match str(st["type"]):
					"news":
						wav = HumanVoice.render(RadioLib.news_line(),
							{"base": 185.0, "var": 0.42, "wave": "sine",
							"rate": 1.35, "artic": 1.6})
					"rick":
						# the smoothest voice on the dial. suspicious.
						wav = HumanVoice.render(RadioLib.rick_line(),
							{"base": 150.0, "var": 0.55, "wave": "sine",
							"rate": 1.25, "artic": 1.4})
					"alien":
						wav = HumanVoice.render(RadioLib.alien_line(),
							RadioLib.alien_profile())
					"noodle":
						wav = HumanVoice.render(RadioLib.noodle_line(),
							RadioLib.noodle_profile())
				if wav != null:
					_talk.stream = wav
					_talk.play()
				_sentence_cd = randf_range(2.0, 4.5)

func _process(d: float) -> void:
	super._process(d)
	# the dish TRACKS the aim always -- powered or not, you can see
	# where it's pointed from across the yard
	if _dish_pivot and aim_dir.length() > 0.1:
		var gz := -aim_dir
		var gx := aim_dir.cross(global_transform.basis.y)
		if gx.length() < 0.05:
			gx = aim_dir.cross(global_transform.basis.x)
		gx = gx.normalized()
		_dish_pivot.global_transform.basis = Basis(gx,
			gx.cross(gz).normalized() * -1.0, gz).orthonormalized()
	# a discharged control coil silences the set COMPLETELY
	if has_coil and coil_node != null and is_instance_valid(coil_node) \
			and coil_node.buf <= 0.0:
		if _talk.playing:
			_talk.stop()
		if _hiss.playing:
			_hiss.stop()
		_cur_station = -1

func info_text() -> String:
	var act := ""
	for st in stations:
		if align_for(st) > 0.4 and signal_for(st) < 0.3:
			act = "\nactivity near %.1f MHz -- open the dish map [F]" % float(st["freq"])
			break
	return "energy: %.0f / %.0f EU (drain %.1f/s)\ntuned: %.1f MHz%s" % [
		buf, buf_cap, DRAIN, freq, act]
