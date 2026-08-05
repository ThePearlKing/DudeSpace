class_name DatamoshStudio
extends Node3D
## The DATAMOSH talk-radio station, in the flesh: a mine-style hole on Datamosh's
## surface with a transmitter pole beside it, leading down to a studio
## pocket where four floating icosahedron aliens run the show LIVE --
## voices clear, no static, bodies swelling with their own volume.
## A TV on the back wall cuts between cameras around the world based on
## what they're talking about; when the topic is the humans, an Earth
## camera pivots onto one and ZOOMS. When they're talking about nothing
## much -- or about the listener -- the TV shows YOU, in the room, the
## shot creeping around you. An escape portal hides in the corner.

const POS := Vector3(-26000, 34000, 22000)   # pocket coords, far from houses

var _talk: AudioStreamPlayer3D
var _aliens: Array = []        # [{node, mat, base_y, host}]
var _turns: Array = []         # queued [host_idx, wav]
var _cur_host: int = -1
var _cooking := false
var _tv_cam: Camera3D
var _tv_vp: SubViewport
var _tv_mode := "player"       # "planet" | "humans" | "player"
var _tv_planet := ""
var _t := 0.0
var _human_pick_t := 0.0
var _human_target: Node3D = null
var _next_seg_t := 2.0
var _jitter_t := 0.0
var _cur_text := ""
var _bubble_linger := 0.9
var _bub_chars := -1   # letters currently shown (gate Label3D rebuilds)
# remote viewership: colony TVs ping this while someone is watching, so
# the show runs (and subtitles build) even with nobody at the studio.
# The voice stays a 3D emitter AT the studio -- a TV across the galaxy
# hears nothing, it only reads.
var remote_watch := 0.0
var _pcache = null     # cached player ref, validity-checked
var _annoy := 0.0          # keeps count of your bullets. decays. slowly.
var _annoy_cd := 0.0
var _cooking_callout := false

const ANNOY_WARN := ["dude. we are LIVE.",
	"stop shooting the hosts, dude.",
	"the orbs are not targets. the orbs are TALENT."]
const ANNOY_ANGRY := ["okay. dude. get out of the studio.",
	"security to the sofa area. it's the dude.",
	"OUT. the hole is where you came from. use it."]
const ANNOY_FINAL := ["GET. OUT. the show resumes without witnesses.",
	"we have voted. unanimously. LEAVE, dude.",
	"every orb in this room wants you gone. that includes the table."]
# and then the OTHERS pile on, each in their own register
const ANNOY_PILE := {
	0: ["and cut to break. no -- don't cut. let it see itself.",
		"this is going in the highlight reel."],
	1: ["i am adding this to the chart. the chart is upset.",
		"projectile behavior: logged. judged. logged again."],
	2: ["do bullets have feelings? these ones felt aimed.",
		"i flinched in four dimensions."],
	3: ["called it.", "this is why we can't have a lobby."]}
var _tv_bodies: Array = []
var _table: MeshInstance3D = null
var _ad_root: Node3D = null
var _ad_pivot: Node3D = null
var _ad_label: Label3D = null
var _ad_bg: MeshInstance3D = null

class _AlienShell extends StaticBody3D:
	var studio = null
	var idx := -1
	func destroy(_push: Vector3) -> void:
		if studio != null:
			studio.orb_hit(idx, global_position)

## A bullet meets an anchor: it DEFLECTS with a proper metallic ping,
## and only if THAT orb is mid-sentence does its voice jitter.
## Every hit is BROADCAST: your friend's bullets ping, jitter, and get
## complained about identically on every player's client -- the plan
## (who says what) is chosen by the shooter and shipped as text, and
## voices render deterministically from text, so everyone hears the
## same words. Radios tuned to DATAMOSH get the ping, the jitter, and the
## complaint pushed through their speaker too.
func orb_hit(idx: int, at: Vector3) -> void:
	var plan := _hit_plan(idx)
	_apply_hit(idx, at, plan)
	if Net.active:
		Net.wth_hit(idx, plan)

## Called via Net for OTHER players' shots: same effects, given plan.
func orb_hit_synced(idx: int, plan: Array) -> void:
	_annoy = minf(_annoy + 1.0, 12.0)
	if plan.size() > 0:
		_annoy_cd = 4.0
	var at: Vector3 = POS
	if idx >= 0 and idx < _aliens.size():
		at = (_aliens[idx]["node"] as Node3D).global_position
	_apply_hit(idx, at, plan)

## Decide whether this hit triggers a callout, and script it as text.
func _hit_plan(idx: int) -> Array:
	_annoy = minf(_annoy + 1.0, 12.0)
	if _annoy < 3.0 or _annoy_cd > 0.0 or _cooking_callout:
		return []
	_annoy_cd = 4.0
	var bank: Array = ANNOY_WARN
	if _annoy >= 9.0:
		bank = ANNOY_FINAL
	elif _annoy >= 6.0:
		bank = ANNOY_ANGRY
	var host := clampi(idx, 0, 3)
	var plan: Array = [[host, str(bank[randi() % bank.size()])]]
	var others: Array = [0, 1, 2, 3]
	others.erase(host)
	others.shuffle()
	for oi in 1 + randi() % 2:
		var oh := int(others[oi])
		var opts: Array = ANNOY_PILE[oh]
		plan.append([oh, str(opts[randi() % opts.size()])])
	return plan

func _apply_hit(idx: int, at: Vector3, plan: Array) -> void:
	_play_ping(at)
	if idx >= 0 and idx < _aliens.size():
		_aliens[idx]["flash"] = 0.14   # the whole orb FLASHES at impact
	if idx == _cur_host and _talk != null and _talk.playing:
		_jitter_t = 0.05
		_talk.pitch_scale = randf_range(0.55, 1.7)
	# radios tuned to DATAMOSH carry the assault live: ping + a jitter blip
	for r in _tuned_radios():
		_play_ping(r.global_position + r.global_transform.basis.y * 2.4)
		if r._talk != null and r._talk.playing:
			r._talk.pitch_scale = randf_range(0.6, 1.6)
			get_tree().create_timer(0.06).timeout.connect(func() -> void:
				if is_instance_valid(r) and r._talk != null:
					r._talk.pitch_scale = 1.0)
	if plan.is_empty():
		return
	_cooking_callout = true
	WorkerThreadPool.add_task(func() -> void:
		var cooked: Array = []
		for entry in plan:
			var w = HumanVoice.render(str(entry[1]),
				RadioLib.ALIEN_HOSTS[int(entry[0])])
			if w != null:
				cooked.append([int(entry[0]), w, str(entry[1])])
		_callout_ready.call_deferred(cooked))

## Radios currently locked to the DATAMOSH station and making sound.
func _tuned_radios() -> Array:
	var out: Array = []
	for r in get_tree().get_nodes_in_group("radio"):
		if r is RadioTower and is_instance_valid(r) \
				and r._cur_station >= 0 and r._cur_station < r.stations.size() \
				and str(r.stations[r._cur_station].get("type", "")) == "alien":
			out.append(r)
	return out

func _callout_ready(cooked: Array) -> void:
	if Game.quitting:
		return
	_cooking_callout = false
	if cooked.is_empty():
		return
	_talk.stop()   # the show interrupts ITSELF to tell you off
	for ci in range(cooked.size() - 1, -1, -1):
		_turns.push_front(cooked[ci])
	# and every radio tuned to DATAMOSH airs the complaint verbatim
	var bytes := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(int(22050 * 0.35) * 2)
	for entry in cooked:
		bytes.append_array((entry[1] as AudioStreamWAV).data)
		bytes.append_array(gap)
	var combined := AudioStreamWAV.new()
	combined.format = AudioStreamWAV.FORMAT_16_BITS
	combined.mix_rate = 22050
	combined.data = bytes
	for r in _tuned_radios():
		if r._talk != null:
			r._talk.stream = combined
			r._talk.play()

var _ping_wav: AudioStreamWAV = null

func _play_ping(at: Vector3) -> void:
	if _ping_wav == null:
		# a tight metallic ricochet: two ringing partials, fast decay
		var n := int(0.14 * 22050)
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		for i in n:
			var t := float(i) / 22050.0
			var v := (sin(TAU * 1900.0 * t) * 0.6 + sin(TAU * 2640.0 * t) * 0.35 \
				+ (randf() * 2.0 - 1.0) * 0.15 * exp(-t * 90.0)) * exp(-t * 34.0)
			bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 22000.0))
		_ping_wav = AudioStreamWAV.new()
		_ping_wav.format = AudioStreamWAV.FORMAT_16_BITS
		_ping_wav.mix_rate = 22050
		_ping_wav.data = bytes
	var pl := AudioStreamPlayer3D.new()
	pl.stream = _ping_wav
	pl.unit_size = 6.0
	pl.pitch_scale = randf_range(0.9, 1.15)
	add_child(pl)
	pl.global_position = at
	pl.play()
	pl.finished.connect(pl.queue_free)

func _ready() -> void:
	add_to_group("datamosh_studio")
	_build_surface()
	_build_studio()

## ---- the way in: a dug-out hole + the transmitter pole ----
func _build_surface() -> void:
	var wth = Universe.body_named("Datamosh")
	if wth == null:
		return
	var dir := Vector3(0.3, 0.9, 0.2).normalized()
	var base: Vector3 = wth.center + dir * float(wth.radius)
	var bs := _basis_up(dir)
	# the pit: a dark ring you climb down into, mine-entrance style
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(1.6, 0.9, 0.8)
		rim.mesh = rb
		rim.material_override = Surfaces.stone(Color("#1a2a24"))
		add_child(rim)
		rim.global_transform = Transform3D(bs, base + bs * Vector3(cos(ang) * 2.4, 0.25, sin(ang) * 2.4))
		rim.rotate_object_local(Vector3.UP, -ang)
	var pit := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 2.2
	pm.bottom_radius = 1.6
	pm.height = 2.4
	pit.mesh = pm
	pit.material_override = Surfaces.stone(Color("#050908"))
	add_child(pit)
	pit.global_transform = Transform3D(bs, base - dir * 1.0)
	var gate := Gate.new().configure({
		"target": POS + Vector3(0, -1.6, 5.0), "zone": "flat", "zone_g": 9.0,
		"label": "STATION DATAMOSH", "color": Color("#33ff99")})
	add_child(gate)
	gate.global_transform = Transform3D(bs, base - dir * 0.4)
	# the TRANSMITTER: a proper mast beside the hole, lamp blinking
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.07
	mm.bottom_radius = 0.16
	mm.height = 11.0
	mast.mesh = mm
	mast.material_override = Surfaces.metal(Color("#8a9098"))
	add_child(mast)
	mast.global_transform = Transform3D(bs, base + bs * Vector3(4.5, 5.5, 0))
	for hy in [3.0, 5.5, 8.0]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4 - hy * 0.15, 0.09, 0.09)
		bar.mesh = bm
		bar.material_override = Surfaces.metal(Color("#6a7078"))
		add_child(bar)
		bar.global_transform = Transform3D(bs, base + bs * Vector3(4.5, hy, 0))
	_beacon = MeshInstance3D.new()
	var bem := SphereMesh.new()
	bem.radius = 0.16
	bem.height = 0.32
	_beacon.mesh = bem
	_beacon_mat = Destructible.make_material(Color("#ff3030"), 3.0)
	_beacon.material_override = _beacon_mat
	add_child(_beacon)
	_beacon.global_transform = Transform3D(bs, base + bs * Vector3(4.5, 11.2, 0))

var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D

func _basis_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, up, x.cross(up).normalized() * -1.0).orthonormalized()

## ---- the studio pocket ----
func _build_studio() -> void:
	var size := Vector3(22, 6, 16)
	var half := size * 0.5
	for w in [[Vector3(size.x, 1, size.z), Vector3(0, -half.y, 0)],
			[Vector3(size.x, 1, size.z), Vector3(0, half.y, 0)],
			[Vector3(1, size.y, size.z), Vector3(-half.x, 0, 0)],
			[Vector3(1, size.y, size.z), Vector3(half.x, 0, 0)],
			[Vector3(size.x, size.y, 1), Vector3(0, 0, -half.z)],
			[Vector3(size.x, size.y, 1), Vector3(0, 0, half.z)]]:
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = w[0]
		mi.mesh = m
		mi.material_override = Surfaces.metal(Color("#10221c"))
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = w[0]
		col.shape = cs
		body.add_child(col)
		add_child(body)
		body.global_position = POS + w[1]
	var light := OmniLight3D.new()
	light.light_energy = 1.3
	light.light_color = Color("#7dffc8")
	light.omni_range = 26.0
	add_child(light)
	light.global_position = POS + Vector3(0, 2.2, 0)
	# the news TABLE: held up by alien floor tech, and parked well clear
	# of the sofas so the anchors stay visible. Two emitter pads on the
	# floor push translucent lift beams; the slab just... accepts it.
	for px2 in [-2.6, 2.6]:
		var pad := MeshInstance3D.new()
		var pdm := CylinderMesh.new()
		pdm.top_radius = 0.55
		pdm.bottom_radius = 0.65
		pdm.height = 0.16
		pad.mesh = pdm
		pad.material_override = Surfaces.metal(Color("#15332a"))
		add_child(pad)
		pad.global_position = POS + Vector3(px2, -2.42, -0.8)
		var ring := MeshInstance3D.new()
		var rgm := TorusMesh.new()
		rgm.inner_radius = 0.38
		rgm.outer_radius = 0.52
		ring.mesh = rgm
		ring.material_override = Surfaces.portal(Color("#33ff99"))
		add_child(ring)
		ring.global_position = POS + Vector3(px2, -2.32, -0.8)
		var beam := MeshInstance3D.new()
		var bmm := CylinderMesh.new()
		bmm.top_radius = 0.16
		bmm.bottom_radius = 0.34
		bmm.height = 0.9
		beam.mesh = bmm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(0.2, 1.0, 0.6, 0.22)
		bmat.emission_enabled = true
		bmat.emission = Color("#33ff99")
		bmat.emission_energy_multiplier = 0.9
		beam.material_override = bmat
		add_child(beam)
		beam.global_position = POS + Vector3(px2, -1.9, -0.8)
	_table = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(7.0, 0.16, 1.5)
	_table.mesh = dm
	_table.material_override = Surfaces.metal(Color("#1c3a30"))
	add_child(_table)
	_table.global_position = POS + Vector3(0, -1.42, -0.8)
	# solid: you can lean on the alien tech (collider rides the bob)
	var tbody := StaticBody3D.new()
	var tcol := CollisionShape3D.new()
	var tshape := BoxShape3D.new()
	tshape.size = Vector3(7.0, 0.16, 1.5)
	tcol.shape = tshape
	tbody.add_child(tcol)
	_table.add_child(tbody)
	var glowline := MeshInstance3D.new()
	var glm := BoxMesh.new()
	glm.size = Vector3(6.8, 0.04, 0.1)
	glowline.mesh = glm
	glowline.material_override = Destructible.make_material(Color("#33ff99"), 2.0)
	add_child(glowline)
	glowline.global_position = POS + Vector3(0, -1.5, -0.06)
	# the ANCHORS: four floating icosahedron-ish gems, fluid-glow skins
	for i in 4:
		var a := MeshInstance3D.new()
		var am := SphereMesh.new()
		am.radius = 0.65
		am.height = 1.3
		am.radial_segments = 5
		am.rings = 3
		a.mesh = am
		var mat := _fluid_material([Color("#33ff99"), Color("#ffcf40"),
			Color("#b388ff"), Color("#ff6a6a")][i])
		a.material_override = mat
		add_child(a)
		a.global_position = POS + Vector3(-4.5 + float(i) * 3.0, -0.6, -4.2)
		# the speech bubble: anchor-colored, fills letter by letter
		var bub := Label3D.new()
		bub.font_size = 26
		bub.pixel_size = 0.006
		bub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bub.modulate = [Color("#33ff99"), Color("#ffcf40"),
			Color("#b388ff"), Color("#ff6a6a")][i]
		bub.outline_size = 8
		bub.outline_modulate = Color(0, 0, 0, 0.85)
		bub.position = Vector3(0, 1.2, 0)
		bub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bub.width = 360.0
		a.add_child(bub)
		_aliens.append({"node": a, "mat": mat,
			"base": a.global_position, "phase": randf() * TAU, "bub": bub})
		# shootable, but not hurtable: bullets PLINK off and the voice
		# jitters for a blink. they are above harm. slightly below dignity.
		var shell := _AlienShell.new()
		shell.studio = self
		shell.idx = i
		var scol := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.75
		scol.shape = sph
		shell.add_child(scol)
		a.add_child(shell)
		# a small sofa parked under each anchor (they float above it,
		# obviously -- sitting is for bodies)
		var sofa := Furniture.new()
		sofa.kind = "sofa"
		sofa.yaw = PI   # back to the wall, facing the room
		add_child(sofa)
		# origin ON the floor top (floor slab tops out at POS.y - 2.5)
		sofa.global_position = Vector3(a.global_position.x, POS.y - 2.5,
			a.global_position.z + 0.1)
		sofa.scale = Vector3(0.72, 0.72, 0.72)
	# the TV: bezel + live screen on the back wall
	var bez := MeshInstance3D.new()
	var bzm := BoxMesh.new()
	bzm.size = Vector3(6.6, 3.9, 0.3)
	bez.mesh = bzm
	bez.material_override = Surfaces.metal(Color("#0a1410"))
	add_child(bez)
	bez.global_position = POS + Vector3(0, 0.6, -7.6)
	_tv_vp = SubViewport.new()
	_tv_vp.size = Vector2i(360, 220)
	_tv_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_tv_vp)
	_tv_vp.world_3d = get_viewport().world_3d if get_viewport() else null
	_tv_cam = Camera3D.new()
	_tv_cam.cull_mask = 0xFFFFF & ~(1 << 9)   # the TV sees YOU, not a hand
	_tv_vp.add_child(_tv_cam)
	var scr := MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2(6.0, 3.4)
	scr.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_texture = _tv_vp.get_texture()
	smat.emission_enabled = true
	smat.emission_texture = _tv_vp.get_texture()
	smat.emission_energy_multiplier = 0.8
	scr.material_override = smat
	add_child(scr)
	scr.global_position = POS + Vector3(0, 0.6, -7.42)
	# props: server racks + a sagging cable
	for rx in [-9.0, 9.0]:
		var rack := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(1.4, 3.2, 1.0)
		rack.mesh = rm
		rack.material_override = Surfaces.metal(Color("#152a22"))
		add_child(rack)
		rack.global_position = POS + Vector3(rx, -1.3, -6.4)
	# the ESCAPE PORTAL: tucked dark in a corner, no label, no ceremony
	var wth = Universe.body_named("Datamosh")
	if wth != null:
		var dir := Vector3(0.3, 0.9, 0.2).normalized()
		var out := Gate.new().configure({
			"target": wth.center + dir * (float(wth.radius) + 2.0),
			"zone": "", "label": "EXIT", "color": Color("#0a2a1e")})
		add_child(out)
		out.global_position = POS + Vector3(half.x - 1.4, -2.6, half.z - 1.2)
	# the AD SET: a hidden little product-shoot stage far below the
	# studio; the TV cuts to it during sponsor segments
	_ad_root = Node3D.new()
	add_child(_ad_root)
	_ad_root.global_position = POS + Vector3(0, -70, 0)
	_ad_bg = MeshInstance3D.new()
	var abgm := QuadMesh.new()
	abgm.size = Vector2(10, 6)
	_ad_bg.mesh = abgm
	_ad_root.add_child(_ad_bg)
	_ad_bg.position = Vector3(0, 0, -3)
	var adl := OmniLight3D.new()
	adl.light_energy = 2.0
	adl.omni_range = 16.0
	_ad_root.add_child(adl)
	adl.position = Vector3(2, 3, 4)
	_ad_pivot = Node3D.new()
	_ad_root.add_child(_ad_pivot)
	_ad_label = Label3D.new()
	_ad_label.font_size = 44
	_ad_label.pixel_size = 0.008
	_ad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ad_label.outline_size = 10
	_ad_root.add_child(_ad_label)
	_ad_label.position = Vector3(0, -1.8, 0)
	_talk = AudioStreamPlayer3D.new()
	if AudioServer.get_bus_index("Voice") >= 0:
		_talk.bus = "Voice"
	_talk.unit_size = 14.0
	_talk.max_distance = 60.0
	add_child(_talk)
	_talk.global_position = POS + Vector3(0, -0.5, -4.0)

## The fluid glow: the boiling fbm skin the user saved for later. Later
## is now. Per-anchor hue.
static func _fluid_material(col: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 vpos;
uniform vec3 tint = vec3(0.2, 1.0, 0.6);
uniform float amp = 1.0;
float hash31(vec3 p) { p = fract(p * 0.3183 + vec3(0.1, 0.2, 0.3)); p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i), b = hash31(i + vec3(1,0,0)), c = hash31(i + vec3(0,1,0)), d = hash31(i + vec3(1,1,0));
	float e = hash31(i + vec3(0,0,1)), g = hash31(i + vec3(1,0,1)), h = hash31(i + vec3(0,1,1)), k = hash31(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y), mix(mix(e,g,f.x), mix(h,k,f.x), f.y), f.z); }
float fbm3(vec3 p) { return vnoise(p) * 0.6 + vnoise(p * 2.3) * 0.4; }
void vertex() { vpos = VERTEX; }
void fragment() {
	float t = TIME;
	float sw = fbm3(vpos * 4.0 + vec3(t * 0.5, t * 0.35, t * 0.2));
	float ring = sin(sw * 12.0 - t * 2.2) * 0.5 + 0.5;
	ALBEDO = tint * 0.2;
	EMISSION = tint * (0.4 + 1.6 * pow(ring, 2.0) + sw * 0.5) * amp;
	ROUGHNESS = 0.3;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	return mat

## What the current speaker has said SO FAR -- the same letter-by-letter
## build the studio bubbles show. Remote TVs print this as subtitles.
func subtitle() -> String:
	if _talk == null or not _talk.playing or _cur_text == "":
		return ""
	return _cur_text.substr(0, maxi(0, _bub_chars))

## ...and in the SPEAKER'S bubble colour, exactly like the studio.
func subtitle_color() -> Color:
	if _cur_host >= 0 and _cur_host < 4:
		return [Color("#33ff99"), Color("#ffcf40"),
			Color("#b388ff"), Color("#ff6a6a")][_cur_host]
	return Color.WHITE

## ---- the live show ----
func _process(delta: float) -> void:
	_t += delta
	if _jitter_t > 0.0:
		_jitter_t -= delta
		if _jitter_t <= 0.0 and _talk != null:
			_talk.pitch_scale = 1.0
	_annoy = maxf(0.0, _annoy - delta * 0.15)
	_annoy_cd = maxf(0.0, _annoy_cd - delta)
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 3.0 if fmod(_t, 1.2) < 0.6 else 0.3
	if _table != null:
		_table.global_position.y = POS.y - 1.42 + sin(_t * 0.9) * 0.05
	if _pcache == null or not is_instance_valid(_pcache):
		_pcache = get_tree().get_first_node_in_group("player")
	var p = _pcache
	var here: bool = p != null and p.global_position.distance_to(POS) < 40.0
	remote_watch = maxf(0.0, remote_watch - delta)
	# the news room's own screen keeps rendering while ANY TV watches the
	# studio remotely -- the wall monitor must be alive INSIDE the relay
	# picture, not a dead slab behind the desk
	if _tv_vp != null:
		_tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS \
			if (here or remote_watch > 0.0) else SubViewport.UPDATE_DISABLED
	if not here and remote_watch <= 0.0:
		return
	# the show never stops: queue segments, play turn by turn
	if _turns.is_empty() and not _talk.playing:
		_next_seg_t -= delta
		if _next_seg_t <= 0.0 and not _cooking:
			_cooking = true
			# in_room only when the player is PHYSICALLY at the studio; a
			# colony TV viewer gets the WATCHED treatment instead -- the
			# hosts know, and they use it to point at Harold
			var ex := RadioLib.alien_exchange(here, remote_watch > 0.0)
			_apply_topic(RadioLib.last_alien_meta)
			WorkerThreadPool.add_task(func() -> void:
				var cooked: Array = []
				for turn in ex:
					var w = HumanVoice.render(str(turn[1]),
						RadioLib.ALIEN_HOSTS[int(turn[0])])
					if w != null:
						cooked.append([int(turn[0]), w, str(turn[1])])
				_deliver.call_deferred(cooked))
	if not _talk.playing and not _turns.is_empty():
		var t0: Array = _turns.pop_front()
		_cur_host = int(t0[0])
		_talk.stream = t0[1]
		_cur_text = str(t0[2]) if t0.size() > 2 else ""
		_talk.play()
	if not _talk.playing and _turns.is_empty():
		_cur_host = -1
	# bubbles: the CURRENT speaker's text builds letter by letter, timed
	# to the voice; everyone else's bubble is empty
	for i2 in _aliens.size():
		var bub: Label3D = _aliens[i2]["bub"]
		if i2 == _cur_host and _talk.playing and _cur_text != "":
			var tlen: float = maxf(0.2, _talk.stream.get_length() * 0.88)
			var n := int(float(_cur_text.length()) \
				* clampf(_talk.get_playback_position() / tlen, 0.0, 1.0))
			if n != _bub_chars:
				_bub_chars = n   # rebuild only when a NEW letter lands
				bub.text = _cur_text.substr(0, n)
		elif i2 != _cur_host or not _talk.playing:
			if bub.text != "" and (i2 != _cur_host or not _talk.playing):
				_bubble_linger -= delta
				if _bubble_linger <= 0.0 or i2 != _cur_host:
					bub.text = ""
			else:
				_bubble_linger = 0.9
	# anchors: float, bob, and SWELL with their own voice
	for i in _aliens.size():
		var a: Dictionary = _aliens[i]
		var n: Node3D = a["node"]
		n.global_position = a["base"] + Vector3(0,
			sin(_t * 1.1 + float(a["phase"])) * 0.22, 0)
		n.rotate_y(delta * 0.6)
		var talking: bool = i == _cur_host and _talk.playing
		var target_s: float = 1.0
		if talking:
			target_s = 1.0 + 0.35 * absf(sin(_t * 9.0)) + 0.15 * absf(sin(_t * 23.0))
		n.scale = n.scale.lerp(Vector3.ONE * target_s, delta * 10.0)
		var fl: float = float(a.get("flash", 0.0))
		if fl > 0.0:
			a["flash"] = fl - delta
		(a["mat"] as ShaderMaterial).set_shader_parameter("amp",
			(1.6 if talking else 0.8) + 7.0 * clampf(fl / 0.14, 0.0, 1.0))
	_drive_tv(delta, p)

func _deliver(cooked: Array) -> void:
	if Game.quitting:
		return
	_cooking = false
	_turns = cooked
	_next_seg_t = randf_range(3.0, 6.0)

func _apply_topic(meta: Dictionary) -> void:
	var topic := int(meta.get("topic", -1))
	_tv_planet = str(meta.get("planet", ""))
	var p2 := str(meta.get("planet2", ""))
	if topic == 9 or _tv_planet == "the humans":
		_tv_mode = "humans"
		_human_target = null
	elif topic in [1, 3] and _tv_planet != "" and p2 != "" and p2 != _tv_planet:
		# TWO planets in the conversation: frame them both, zoom each
		var ba = Universe.body_named(_tv_planet)
		var bb = Universe.body_named(p2)
		if ba != null and bb != null:
			_tv_mode = "duo"
			_tv_bodies = [ba, bb]
		else:
			_tv_mode = "player"
	elif topic in [0, 2, 5, 7] and _tv_planet != "":
		var b = Universe.body_named(_tv_planet)
		if b != null:
			_tv_mode = "planet"
			_tv_bodies = [b]
		else:
			_tv_mode = "player"
	elif topic == 6:
		# SPONSOR SEGMENT: cut to a freshly generated product shoot
		_gen_ad(str(meta.get("product", "product")), str(meta.get("slogan", "")))
		_tv_mode = "ad"
	else:
		# markets, fourth wall, nothing much: the camera is HERE,
		# in the room, and it is looking at YOU
		_tv_mode = "player"

## A one-off generated commercial: random brand palette, a random
## primitive sculpture as the "product", name + slogan on the card.
func _gen_ad(product: String, slogan: String) -> void:
	if _ad_pivot == null:
		return
	for ch in _ad_pivot.get_children():
		ch.queue_free()
	var hue := randf()
	var bgmat := StandardMaterial3D.new()
	bgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgmat.albedo_color = Color.from_hsv(hue, 0.55, 0.35)
	_ad_bg.material_override = bgmat
	var pcol := Color.from_hsv(fmod(hue + 0.45, 1.0), 0.7, 0.95)
	var acc := Color.from_hsv(fmod(hue + 0.13, 1.0), 0.8, 1.0)
	for i in 3 + randi() % 3:
		var mi := MeshInstance3D.new()
		match randi() % 4:
			0:
				var bm := BoxMesh.new()
				bm.size = Vector3(randf_range(0.3, 1.0), randf_range(0.3, 1.2),
					randf_range(0.3, 1.0))
				mi.mesh = bm
			1:
				var cm := CylinderMesh.new()
				cm.top_radius = randf_range(0.1, 0.4)
				cm.bottom_radius = randf_range(0.2, 0.5)
				cm.height = randf_range(0.4, 1.2)
				mi.mesh = cm
			2:
				var sm2 := SphereMesh.new()
				sm2.radius = randf_range(0.2, 0.5)
				sm2.height = sm2.radius * 2.0
				mi.mesh = sm2
			_:
				var tm2 := TorusMesh.new()
				tm2.inner_radius = randf_range(0.15, 0.3)
				tm2.outer_radius = randf_range(0.35, 0.6)
				mi.mesh = tm2
		mi.material_override = Destructible.make_material(
			pcol if i % 2 == 0 else acc, 0.6 if i % 2 == 0 else 1.4)
		mi.position = Vector3(randf_range(-0.7, 0.7), randf_range(-0.4, 0.9),
			randf_range(-0.4, 0.4))
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_ad_pivot.add_child(mi)
	_ad_label.text = "%s\n%s" % [product.to_upper(), slogan]
	_ad_label.modulate = acc

func _drive_tv(delta: float, p: Node3D) -> void:
	if _tv_cam == null:
		return
	match _tv_mode:
		"ad":
			# the product rotates. the camera believes in it.
			if _ad_pivot != null:
				_ad_pivot.rotation.y = _t * 0.8
				_tv_cam.global_position = _ad_root.global_position \
					+ Vector3(sin(_t * 0.2) * 1.2, 0.4, 5.0)
				_tv_cam.look_at(_ad_root.global_position + Vector3(0, -0.2, 0),
					Vector3.UP)
				_tv_cam.fov = 38.0 + 5.0 * sin(_t * 0.5)
		"planet":
			# ORBIT the subject: slow circle, breathing zoom
			if _tv_bodies.size() >= 1:
				var b0 = _tv_bodies[0]
				var orb2 := _t * 0.25
				var r0: float = float(b0.radius) * 2.6
				_tv_cam.global_position = b0.center + Vector3(cos(orb2) * r0,
					r0 * 0.35 * sin(_t * 0.17), sin(orb2) * r0)
				_tv_cam.look_at(b0.center, Vector3.UP)
				_tv_cam.fov = 44.0 + 16.0 * sin(_t * 0.4)
		"duo":
			# both in frame, then zoom one, then the other, forever
			if _tv_bodies.size() >= 2:
				var ba = _tv_bodies[0]
				var bb = _tv_bodies[1]
				var mid2: Vector3 = (ba.center + bb.center) * 0.5
				var sepv: Vector3 = bb.center - ba.center
				var phase := fmod(_t, 12.0)
				var orb3 := _t * 0.2
				var side := sepv.cross(Vector3.UP)
				if side.length() < 1.0:
					side = sepv.cross(Vector3.RIGHT)
				side = side.normalized()
				if phase < 4.0:
					var wd: float = sepv.length() * 0.9 + float(ba.radius) * 3.0
					_tv_cam.global_position = mid2 + side.rotated(sepv.normalized(),
						orb3) * wd
					_tv_cam.look_at(mid2, Vector3.UP)
					_tv_cam.fov = 58.0
				else:
					var tgt = ba if phase < 8.0 else bb
					# comfortable close-up: planet fills MOST of the frame,
					# not the whole lens pressed against it
					var rr: float = float(tgt.radius) * 3.4
					_tv_cam.global_position = tgt.center + Vector3(cos(orb3 * 2.0) * rr,
						rr * 0.3, sin(orb3 * 2.0) * rr)
					_tv_cam.look_at(tgt.center, Vector3.UP)
					_tv_cam.fov = lerpf(_tv_cam.fov, 40.0, 0.05)
		"humans":
			# an Earth camera pivots onto some human and ZOOMS. rude.
			_human_pick_t -= delta
			if _human_target == null or not is_instance_valid(_human_target) \
					or _human_pick_t <= 0.0:
				_human_pick_t = 5.0
				var best: Node3D = null
				for h in get_tree().get_nodes_in_group("earth_human"):
					if h is Node3D and is_instance_valid(h):
						best = h
						if randf() < 0.3:
							break
				_human_target = best
			if _human_target != null and is_instance_valid(_human_target):
				var up := (_human_target.global_position \
					- Universe.body_named("Earth").center).normalized()
				_tv_cam.global_position = _human_target.global_position \
					+ up * 9.0 + Vector3(3, 0, 2)
				_tv_cam.look_at(_human_target.global_position, up)
				_tv_cam.fov = lerpf(_tv_cam.fov, 22.0, delta * 0.8)
		"player":
			# the surveillance shot: not a view of the news room anymore.
			# A camera hangs metres ABOVE the dude, wherever they are,
			# upright in whatever gravity owns them
			if p != null:
				var b9 = Universe.nearest(p.global_position)
				var up9 := Vector3.UP
				if b9 != null:
					up9 = (p.global_position - (b9.center as Vector3)).normalized()
				var east9: Vector3 = up9.cross(Vector3(0, 0, 1))
				if east9.length() < 0.01:
					east9 = up9.cross(Vector3(1, 0, 0))
				east9 = east9.normalized()
				_tv_cam.global_position = p.global_position \
					+ up9 * (7.0 + 1.5 * sin(_t * 0.4)) + east9 * 1.4
				_tv_cam.look_at(p.global_position + up9 * 0.4, east9)
				_tv_cam.fov = 42.0 + 8.0 * sin(_t * 0.35)
		_:
			pass
