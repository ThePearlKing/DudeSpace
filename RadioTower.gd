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
var _last_sig: float = 0.0
# the AUDIO spectrogram: a real spectrum analyzer on the radio's bus,
# painted into a scrolling texture (time ->, frequency up)
var _spec_img: Image = null
var spec_tex: ImageTexture = null
var _an: AudioEffectSpectrumAnalyzerInstance = null
var _spec_t: float = 0.0
# audio synthesis is EXPENSIVE GDScript: cook streams on worker threads
# and hand them to the player when done -- never hitch the game
var _cooking: bool = false
var _cooked: AudioStreamWAV = null
var _cooked_for: int = -2
var _bad_t: float = 0.0   # how long the signal has been junk

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
	# a dedicated analyzer bus: everything the radio plays goes through
	# it, and the spectrogram reads the ACTUAL audio
	var bi := AudioServer.get_bus_index("RadioFX")
	if bi == -1:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "RadioFX")
		AudioServer.set_bus_send(bi, "Master")
		AudioServer.add_bus_effect(bi, AudioEffectSpectrumAnalyzer.new())
	_an = AudioServer.get_bus_effect_instance(bi, 0)
	_spec_img = Image.create(192, 64, false, Image.FORMAT_RGB8)
	_spec_img.fill(Color(0.015, 0.01, 0.0))
	spec_tex = ImageTexture.create_from_image(_spec_img)
	# little spectrogram SCREENS on the base -- mounted in a real bezel:
	# recessed dark housing, raised frame edges, a wee standby lamp
	for sxs in [-1.0, 1.0]:
		var mount := Node3D.new()
		mount.position = Vector3(sxs * (box_size.x * 0.5), 0.62, 0)
		mount.rotation_degrees.y = 90.0 * sxs
		add_child(mount)
		var housing := MeshInstance3D.new()
		var hbm := BoxMesh.new()
		hbm.size = Vector3(0.74, 0.5, 0.07)
		housing.mesh = hbm
		housing.position = Vector3(0, 0, 0.035)
		housing.material_override = Surfaces.metal(Color("#23262c"))
		mount.add_child(housing)
		for edge in [[Vector3(0.76, 0.045, 0.045), Vector3(0, 0.25, 0.06)],
				[Vector3(0.76, 0.045, 0.045), Vector3(0, -0.25, 0.06)],
				[Vector3(0.045, 0.5, 0.045), Vector3(0.375, 0, 0.06)],
				[Vector3(0.045, 0.5, 0.045), Vector3(-0.375, 0, 0.06)]]:
			var emi := MeshInstance3D.new()
			var ebm := BoxMesh.new()
			ebm.size = edge[0]
			emi.mesh = ebm
			emi.position = edge[1]
			emi.material_override = Surfaces.metal(Color("#5a616c"))
			mount.add_child(emi)
		var lamp := MeshInstance3D.new()
		var lbm := SphereMesh.new()
		lbm.radius = 0.02
		lbm.height = 0.04
		lamp.mesh = lbm
		lamp.position = Vector3(0.32, -0.19, 0.075)
		lamp.material_override = Destructible.make_material(Color("#3aff6a"), 2.5)
		mount.add_child(lamp)
		var scr := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.62, 0.4)
		scr.mesh = qm
		scr.position = Vector3(0, 0, 0.074)
		var sm2 := StandardMaterial3D.new()
		sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm2.albedo_texture = spec_tex
		sm2.emission_enabled = true
		sm2.emission_texture = spec_tex
		sm2.emission_energy_multiplier = 1.3
		scr.material_override = sm2
		scr.extra_cull_margin = 2.0
		mount.add_child(scr)
	_talk = AudioStreamPlayer3D.new()
	_talk.bus = "RadioFX"
	# loud beside it, NORMAL across your whole base, quiet only when
	# you're genuinely far (other-side-of-the-planet territory)
	_talk.unit_size = 40.0
	_talk.max_distance = 1200.0
	_talk.max_db = -1.0   # CAP: standing next to it must not blast you
	add_child(_talk)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.bus = "RadioFX"
	_hiss.unit_size = 24.0
	_hiss.max_distance = 600.0
	_hiss.max_db = -7.0
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
				st = {"name": "EARTH1", "type": "news"}
				stations.append({"name": "EARTH2", "type": "music",
					"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1),
					"body": b, "kind": "earth"})
				stations.append({"name": "EARTH3", "type": "rick",
					"freq": snappedf(rng.randf_range(88.5, 107.5), 0.1),
					"body": b, "kind": "rick"})
			"Wth":
				st = {"name": "??? (shader system)", "type": "alien"}
			"Pi", "Verdant", "Crystalia", "Donut", "Euclid", "Circuitia", "Sanus", "Varnisol", "Venus", "Xero":
				st = {"name": b.name.to_upper(), "type": "music"}
			"Jupiter":
				st = {"name": "JUPITER", "type": "music"}
			"TIN 618":
				# the black hole broadcasts. nobody asked it to.
				st = {"name": "TIN 618", "type": "music"}
			_:
				if kind == "sun":
					st = {"name": b.name.to_upper() + " ✶", "type": "music"}
				else:
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
	# NO two stations share a spot on the dial: hand out evenly spaced
	# frequencies, shuffled (seeded, so the dial is stable across runs)
	var slots: Array = []
	for i in stations.size():
		slots.append(snappedf(88.5 + 19.0 * float(i) / maxf(1.0, float(stations.size() - 1)), 0.1))
	for i in slots.size():
		var j := rng.randi() % slots.size()
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	for i in stations.size():
		stations[i]["freq"] = slots[i]

## Where this set counts as BEING for signal purposes. A radio inside a
## house uses the house's spot on the planet, not the pocket void's
## coordinates way out past everything.
var _site_cache := Vector3.INF
var _site_t := 0.0

func _site() -> Vector3:
	if _site_t > 0.0 and _site_cache != Vector3.INF:
		return _site_cache
	_site_t = 1.0
	_site_cache = Zones.exterior_of(global_position)
	return _site_cache

func station_dir(st: Dictionary) -> Vector3:
	var sp := _site()
	if st.has("fixed_dir"):
		return (st["fixed_dir"] - sp).normalized()
	if st["body"] != null:
		var bb = st["body"]
		if sp.distance_to(bb.center) < float(bb.radius) * 1.6:
			# standing ON the broadcaster: signal's everywhere here, so
			# the dish points at the SKY like a sensible local antenna
			return (sp - bb.center).normalized()
		return (bb.center - sp).normalized()
	var w = get_tree().get_first_node_in_group("noodle_watcher")
	if w != null and w is Node3D:
		return (w.global_position - sp).normalized()
	return (sp - Universe.nearest(sp).center).normalized()

## Where a station's signal physically comes from.
func _src_pos(st: Dictionary) -> Vector3:
	if st.has("fixed_dir"):
		return st["fixed_dir"]
	if st["body"] != null:
		return st["body"].center
	var wn = get_tree().get_first_node_in_group("noodle_watcher")
	if wn != null and wn is Node3D:
		return wn.global_position
	return _site()

func _is_local(st: Dictionary) -> bool:
	if st["body"] == null:
		return false
	return _site().distance_to(st["body"].center) < float(st["body"].radius) * 1.6

## Signal quality 0..1: dish alignment x frequency accuracy. Stations
## on the planet you're STANDING ON are omnidirectional: only the dial
## matters, and all of them are reachable.
func signal_for(st: Dictionary) -> float:
	var a := align_for(st)
	var ferr: float = absf(freq - float(st["freq"]))
	var f := clampf(1.0 - ferr / 1.2, 0.0, 1.0)
	return a * f

## Alignment (spectrum display: activity you COULD tune). PENCIL beam,
## ~5 degrees -- it barely spreads with distance, so you hear the one
## thing you aimed at, not every solar system stacked behind it.
func align_for(st: Dictionary) -> float:
	if _is_local(st):
		return 1.0
	# the beam only has to TOUCH the planet's field, not its center dot:
	# widen acceptance by the body's angular radius (x2.5 for the field)
	var slack := 0.0
	if st["body"] != null:
		var dist := _site().distance_to(st["body"].center)
		if dist > 1.0:
			var ang := asin(clampf(float(st["body"].radius) * 2.5 / dist, 0.0, 0.9))
			slack = 1.0 - cos(ang)
	return clampf((aim_dir.dot(station_dir(st)) - (0.996 - slack)) / 0.004, 0.0, 1.0)

var track_body = null       # left-click lock: the dish FOLLOWS this body
var track_node: Node3D = null   # ...or this node (the noodle god roams)

func _aim_toward(body_center: Vector3) -> void:
	var sp := _site()
	var nb = Universe.nearest(sp)
	if body_center.distance_to(nb.center) < 1.0 \
			and sp.distance_to(nb.center) < float(nb.radius) * 1.6:
		aim_dir = (sp - nb.center).normalized()   # local: aim UP
	else:
		aim_dir = (body_center - sp).normalized()

func aim_at(body_center: Vector3) -> void:
	_aim_toward(body_center)
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
	# frame, so dragging the dial/dish changes the sound LIVE. When two
	# stations are effectively tied, the CLOSEST one wins the receiver.
	var best := -1
	var bs := 0.0
	var bdist := 1e18
	for i in stations.size():
		var sgn := signal_for(stations[i])
		if sgn <= 0.0:
			continue
		var dd: float = _site().distance_to(_src_pos(stations[i]))
		if sgn > bs + 0.03 or (absf(sgn - bs) <= 0.03 and dd < bdist and best >= 0) \
				or best < 0:
			bs = maxf(bs, sgn)
			bdist = dd
			best = i
	# static bed always runs while powered; ducks under a good signal.
	# volumes SLEW toward targets: analog, not stepped.
	if not _hiss.playing:
		_hiss.play()
	# DISTANCE buries far stations in static: same alignment, worse SNR
	var clear := bs
	if best >= 0 and stations[best]["body"] != null:
		# planet stations fade into static with distance -- scaled to the
		# whole MAP, so cross-cluster (Sanus from Earth, ~105km) arrives
		# buried while a neighbour cluster (Euclid, ~56km) is just fuzzy.
		# The SAUCE and the unlabeled thing transmit at cosmic power.
		var far := clampf(_site().distance_to(_src_pos(stations[best])) / 140000.0, 0.0, 1.0)
		clear = bs * (1.0 - 0.9 * pow(far, 1.3))
	_last_sig = clear
	var hiss_target := linear_to_db(clampf(0.85 - clear * 0.8, 0.05, 1.0)) - 6.0
	_hiss.volume_db = lerpf(_hiss.volume_db, hiss_target, minf(1.0, delta * 14.0))
	# HYSTERESIS: the tuned station keeps the receiver unless something
	# CLEARLY beats it -- a beam grazing two stations must not flap
	if _cur_station >= 0 and best >= 0 and best != _cur_station \
			and _cur_station < stations.size():
		var cur_s := signal_for(stations[_cur_station])
		if cur_s > bs - 0.12 and cur_s > 0.05:
			best = _cur_station
			bs = cur_s
	if best != _cur_station:
		_cur_station = best
		_talk.stop()
		_sentence_cd = 0.15
	if best < 0 or bs < 0.05:
		# GRACE: momentary blips (walking, dish jitter) must not kill the
		# stream -- only a genuinely lost signal does
		_bad_t += delta
		if _bad_t > 0.6 and _talk.playing:
			_talk.stop()
		return
	_bad_t = 0.0
	var st: Dictionary = stations[best]
	var talk_target := linear_to_db(clampf(clear, 0.05, 1.0))
	_talk.volume_db = lerpf(_talk.volume_db, talk_target, minf(1.0, delta * 14.0))
	var freq_seed := int(st["freq"] * 10.0)
	var kind := str(st["kind"])
	match str(st["type"]):
		"music":
			if not _talk.playing:
				_serve(func() -> AudioStreamWAV:
					return RadioLib.music_loop(freq_seed, kind), true)
		"eerie":
			if not _talk.playing:
				_serve(func() -> AudioStreamWAV:
					return RadioLib.eerie_loop(), true)
		"rick":
			# RICK FM plays the hook. autotuned. with the band. forever.
			if not _talk.playing:
				_serve(func() -> AudioStreamWAV:
					return RadioLib.rick_song(), true)
		_:
			_sentence_cd -= delta
			if not _talk.playing and _sentence_cd <= 0.0:
				var t := str(st["type"])
				if _serve(func() -> AudioStreamWAV:
					match t:
						"news":
							return HumanVoice.render(RadioLib.news_line(),
								{"base": 185.0, "var": 0.42, "wave": "sine",
								"rate": 1.35, "artic": 1.6})
						"alien":
							# WTH runs a TALK SHOW: recurring hosts,
							# call-ins, planet news, weather, markets
							return RadioLib.alien_broadcast()
						"noodle":
							# the god does not talk. it PERFORMS.
							return RadioLib.noodle_broadcast()
					return null, t == "noodle"):
					_sentence_cd = randf_range(2.0, 4.5)

## Play a cooked stream if one is ready for this station; otherwise cook
## it on a worker thread. Returns true the moment playback starts.
func _serve(builder: Callable, clock_sync: bool) -> bool:
	if _cooked != null and _cooked_for == _cur_station:
		_talk.stream = _cooked
		_cooked = null
		if clock_sync:
			_talk.play(fmod(Game.playtime, _talk.stream.get_length()))
		else:
			_talk.play()
		return true
	if not _cooking:
		_cooking = true
		var idx := _cur_station
		WorkerThreadPool.add_task(func() -> void:
			var wav: AudioStreamWAV = builder.call()
			_deliver.call_deferred(wav, idx))
	return false

func _deliver(wav: AudioStreamWAV, idx: int) -> void:
	_cooking = false
	if wav != null:
		_cooked = wav
		_cooked_for = idx

func _process(d: float) -> void:
	super._process(d)
	_site_t -= d
	# paint the spectrogram: shift left, append the newest column
	_spec_t -= d
	if _spec_t <= 0.0 and _an != null and _spec_img != null:
		_spec_t = 1.0 / 15.0
		var region := _spec_img.get_region(Rect2i(1, 0, 191, 64))
		_spec_img.blit_rect(region, Rect2i(0, 0, 191, 64), Vector2i(0, 0))
		for b in 64:
			var f0 := 60.0 * pow(8000.0 / 60.0, float(b) / 64.0)
			var f1 := 60.0 * pow(8000.0 / 60.0, float(b + 1) / 64.0)
			var mag: float = _an.get_magnitude_for_frequency_range(f0, f1).length()
			var db := clampf((linear_to_db(maxf(mag, 0.00001)) + 55.0) / 55.0, 0.0, 1.0)
			# HD heat: near-black -> ember orange -> bright YELLOW
			var cc := Color(0.015, 0.01, 0.0).lerp(Color(0.85, 0.32, 0.03), minf(db / 0.6, 1.0))
			if db > 0.6:
				cc = cc.lerp(Color(1.0, 0.95, 0.35), (db - 0.6) / 0.4)
			_spec_img.set_pixel(191, 63 - b, cc)
		spec_tex.update(_spec_img)
	# a locked dish TRACKS its target as it moves
	if track_node != null and is_instance_valid(track_node):
		aim_dir = (track_node.global_position - _site()).normalized()
	elif track_body != null:
		_aim_toward(track_body.center)
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
