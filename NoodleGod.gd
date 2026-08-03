class_name NoodleGod
extends Node3D
## Home's connection to the thing in the sky: a nest of colossal golden
## tendrils that FADE INTO EXISTENCE only at full wrath -- the god
## reaching down through its roots. Get close and they grab you and
## fling you clean around the planet. Built in local space (+Y = up).

const INFLUENCE := 70.0
const REACH := 55.0       # grabbing range once manifested
const REVEAL_AT := 0.95   # invisible below 95% wrath

var _tendrils: Array = []   # [{root, mat: ShaderMaterial}]
var _t: float = 0.0
var _grab_cd: float = 4.0
var _grabbing: float = 0.0
var _grab_from: Vector3 = Vector3.ZERO

## One smooth, tapered, GPU-bent tendril tube. Curvature and writhe are
## all in the vertex shader -- a single connected surface, no bead chains.
## Colours are the god's own: golden flesh, hot orange pulse crawling
## along its length.
const TENDRIL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float height = 60.0;
uniform float phase = 0.0;
uniform float wave_amt = 6.0;
uniform float wave_speed = 1.5;
uniform float alpha = 1.0;
uniform float glow = 0.8;
uniform vec3 base_col : source_color = vec3(1.0, 0.81, 0.25);
uniform vec3 glow_col : source_color = vec3(1.0, 0.55, 0.1);
varying float vk;
void vertex(){
	float k = clamp((VERTEX.y + height * 0.5) / height, 0.0, 1.0);
	vk = k;
	// two incommensurate sine curves = organic, never-repeating bend
	vec2 bend = vec2(
		sin(TIME * wave_speed + phase + k * 3.1) + sin(TIME * wave_speed * 0.53 + phase * 2.0 + k * 5.7) * 0.5,
		cos(TIME * wave_speed * 0.82 + phase + k * 2.6) + cos(TIME * wave_speed * 0.31 + k * 4.9) * 0.5);
	VERTEX.xz += bend * wave_amt * k * k;
}
void fragment(){
	ALBEDO = base_col;
	// smooth, even glow -- one soft slow breath, NO banding (bands read
	// as suction cups. it is a noodle, not an octopus.)
	float breath = 0.85 + 0.15 * sin(TIME * 1.4 + phase);
	EMISSION = glow_col * glow * breath;
	ALPHA = alpha;
	ROUGHNESS = 0.6;
}
"""

static func make_tendril(length: float, base_r: float, phase: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = base_r
	cm.top_radius = base_r * 0.15
	cm.height = length
	cm.rings = 48          # enough spine to bend smoothly
	cm.radial_segments = 10
	mi.mesh = cm
	mi.position = Vector3(0, length * 0.5, 0)   # base sits at parent origin
	var sh := Shader.new()
	sh.code = TENDRIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("height", length)
	m.set_shader_parameter("phase", phase)
	mi.material_override = m
	return mi

func build() -> void:
	for i in 6:
		var ang := TAU * float(i) / 6.0 + randf_range(-0.3, 0.3)
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * randf_range(6.0, 16.0), 0,
			sin(ang) * randf_range(6.0, 16.0))
		# lean outward, like it burst through at an angle
		root.rotation_degrees = Vector3(randf_range(-18, 18), rad_to_deg(ang),
			randf_range(-18, 18))
		add_child(root)
		var tendril := make_tendril(randf_range(55.0, 85.0), randf_range(4.5, 7.0),
			randf() * TAU)
		root.add_child(tendril)
		_tendrils.append({"root": root, "mat": tendril.material_override})

func _process(delta: float) -> void:
	_t += delta
	var w := Game.wrath / Game.WRATH_MAX
	# manifest ONLY at full fury: below the threshold there is nothing
	# here at all. above it, they fade up out of the crust.
	var vis := clampf((w - REVEAL_AT) / (1.0 - REVEAL_AT), 0.0, 1.0)
	visible = vis > 0.01
	for e in _tendrils:
		var m: ShaderMaterial = e["mat"]
		m.set_shader_parameter("alpha", vis)
		m.set_shader_parameter("glow", (0.5 + w * 2.0) * vis)
		m.set_shader_parameter("wave_amt", 6.0 + w * 14.0)
		m.set_shader_parameter("wave_speed", 1.0 + w * 4.0)
	if not visible:
		return

	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return

	# --- the grab: wander into reach and a tendril takes you around the world ---
	if _grabbing > 0.0:
		_grabbing -= delta
		# reel you in toward the nest's heart...
		p.global_position = p.global_position.lerp(_grab_from, minf(1.0, delta * 8.0))
		if "velocity" in p:
			p.velocity = Vector3.ZERO
		if "_shake" in p:
			p._shake = 0.5
		if _grabbing <= 0.0 and p.has_method("_launch_orbit"):
			# ...and HURL. same physics as the orbit wand: a full lap.
			p._launch_orbit(p)
			Sfx.play("warp", -4.0)
	elif Game.mode == Game.Mode.ON_FOOT and not Game.dead:
		_grab_cd -= delta
		if _grab_cd <= 0.0 and global_position.distance_to(p.global_position) < REACH:
			_grab_cd = 9.0
			_grabbing = 0.6
			_grab_from = global_position + global_transform.basis.y * 14.0
			Sfx.play("hurt", -8.0)

	# lingering among the roots without tribute is noticed
	if global_position.distance_to(p.global_position) < INFLUENCE:
		Game.report_mega()
