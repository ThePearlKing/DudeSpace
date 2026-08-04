class_name Surfaces
extends RefCounted
## Procedural SURFACES, so things stop looking like flat plastic.
## One shader, five materials: plaster mottle, wood grain, stone
## blotch, brushed metal, fabric weave -- all noise, no textures,
## cached per kind+color.

const PLASTER := 0
const WOOD := 1
const STONE := 2
const METAL := 3
const FABRIC := 4
const PORTAL := 5

static var _cache := {}

const _SH := """
shader_type spatial;
uniform vec4 base : source_color;
uniform float grain = 7.0;
uniform float rough = 0.85;
uniform int kind = 0;
varying vec3 vpos;
float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * amp;
		p *= 2.1;
		amp *= 0.5;
	}
	return v;
}
void vertex() { vpos = VERTEX; }
void fragment() {
	float n = fbm(vpos * grain);
	vec3 col = base.rgb;
	float r = rough;
	if (kind == 1) {
		// wood: rings drifting with the grain
		float ring = sin(vpos.x * 34.0 + fbm(vpos * 5.0) * 7.0) * 0.5 + 0.5;
		col *= 0.8 + 0.2 * ring;
		col *= 0.9 + 0.18 * n;
	} else if (kind == 2) {
		// stone: blotches, seams, a life outdoors
		col *= 0.72 + 0.4 * n;
		float seam = smoothstep(0.46, 0.5, abs(fract(fbm(vpos * 2.4) * 3.0) - 0.5));
		col *= 0.82 + 0.18 * seam;
	} else if (kind == 3) {
		// metal: brushed lines under fingerprints
		float brush = sin(vpos.y * 150.0 + n * 8.0) * 0.5 + 0.5;
		col *= 0.88 + 0.1 * brush;
		col *= 0.92 + 0.12 * n;
		METALLIC = 0.55;
		r = rough - 0.35;
	} else if (kind == 4) {
		// fabric: a fine weave, slightly worn where the noise says
		float wv = (sin(vpos.x * 200.0) + sin(vpos.z * 200.0)) * 0.22 + 0.56;
		col *= 0.88 + 0.12 * wv;
		col *= 0.92 + 0.12 * n;
	} else if (kind == 5) {
		// portal: slow-boiling glow, rings crawling through the noise
		float t = TIME;
		float sw = fbm(vpos * 5.0 + vec3(t * 0.5, t * 0.35, t * 0.2));
		float ring = sin(sw * 12.0 - t * 2.2) * 0.5 + 0.5;
		col = base.rgb * 0.15;
		EMISSION = base.rgb * (0.35 + 1.9 * pow(ring, 2.0) + sw * 0.7);
		r = 0.4;
	} else {
		// plaster: CLEAN, barely-there variation. painted, not dirty.
		col *= 0.975 + 0.035 * n;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(r - n * 0.15, 0.05, 1.0);
}
"""

static var _shader: Shader = null

static func mat(kind: int, color: Color, grain := 7.0, rough := 0.85) -> ShaderMaterial:
	var key := "%d_%s_%.1f" % [kind, color.to_html(false), grain]
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SH
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("base", color)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("rough", rough)
	_cache[key] = m
	return m

static func plaster(c: Color) -> ShaderMaterial:
	return mat(PLASTER, c, 6.0, 0.9)

static func wood(c: Color) -> ShaderMaterial:
	return mat(WOOD, c, 8.0, 0.75)

static func stone(c: Color) -> ShaderMaterial:
	return mat(STONE, c, 4.0, 0.95)

static func metal(c: Color) -> ShaderMaterial:
	return mat(METAL, c, 10.0, 0.7)

static func fabric(c: Color) -> ShaderMaterial:
	return mat(FABRIC, c, 9.0, 0.95)

static func portal(c: Color) -> ShaderMaterial:
	return mat(PORTAL, c, 5.0, 0.4)
