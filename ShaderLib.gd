class_name ShaderLib
extends RefCounted
## Shared inline shaders + material builder, used by the planets and the
## character-creator skins so they match.
##   pixel     - chunky pixelated surface
##   contrast  - crushed, extreme high-contrast terminator
##   datamosh  - actually broken/glitchy datamosh
##   wob       - the old datamosh (legacy wobble bands)
##   wireframe - fake grid (planets get a REAL polygon wireframe in Main)

static func shader_code(kind: String) -> String:
	match kind:
		"pixel":
			# TRUE screen-space pixelation: every ~6x6 block of YOUR SCREEN
			# gets one colour (world position reconstructed at each virtual
			# pixel centre via derivatives), like the planet renders at 200p.
			return "shader_type spatial;\nfloat h3(vec3 p){return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453);}\nvoid fragment(){\n vec2 res=vec2(200.0,112.0);\n vec2 cell=(floor(SCREEN_UV*res)+0.5)/res;\n vec2 dpx=(cell-SCREEN_UV)*VIEWPORT_SIZE;\n vec3 wp=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;\n vec3 wpc=wp+dFdx(wp)*dpx.x+dFdy(wp)*dpx.y;\n float n=h3(floor(wpc*0.3));\n vec3 c=n<0.2?vec3(0.95,0.3,0.62):n<0.4?vec3(0.2,0.55,0.95):n<0.6?vec3(1.0,0.85,0.2):n<0.8?vec3(0.3,0.9,0.5):vec3(0.5,0.25,0.8);\n ALBEDO=c; EMISSION=c*0.2; ROUGHNESS=1.0;\n}"
		"contrast":
			return "shader_type spatial;\nvoid fragment(){\n float v=dot(normalize(NORMAL),normalize(VIEW));\n v=clamp((v-0.5)*7.0+0.5,0.0,1.0);\n ALBEDO=mix(vec3(0.02,0.0,0.06),vec3(1.0,0.97,0.85),v);\n EMISSION=vec3(step(0.88,v))*0.8;\n METALLIC=0.0; ROUGHNESS=0.4;\n}"
		"datamosh":
			# STILL broken, but broken in slow motion: spikes GROW and
			# retract (interpolated between corruption seeds), the row
			# tear eases in and out, and the blackouts/inversions are
			# slow faded dips instead of strobe cuts. seizure-safe glitch.
			return "shader_type spatial;\nfloat h(vec3 p){return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453);}\nvoid vertex(){\n float ph=TIME*0.9; float t0=floor(ph); float f=fract(ph); f=f*f*(3.0-2.0*f);\n vec3 cell=floor(VERTEX*0.5);\n float r0=max(h(cell+vec3(t0))-0.9,0.0);\n float r1=max(h(cell+vec3(t0+1.0))-0.9,0.0);\n VERTEX += NORMAL*mix(r0,r1,f)*180.0;\n float ph2=TIME*0.35; float s0=floor(ph2); float f2=fract(ph2); f2=f2*f2*(3.0-2.0*f2);\n float tear=mix(step(0.75,h(vec3(s0,1.0,2.0))), step(0.75,h(vec3(s0+1.0,1.0,2.0))), f2);\n VERTEX.x += sin(VERTEX.y*0.2+TIME*0.6)*6.0*tear;\n}\nvoid fragment(){\n float ph=TIME*1.2; float t0=floor(ph); float f=fract(ph); f=f*f*(3.0-2.0*f);\n float row=floor(UV.y*40.0);\n vec3 c0=vec3(h(vec3(row,t0,1.0)),h(vec3(row,t0,2.0)),h(vec3(row,t0,3.0)));\n vec3 c1=vec3(h(vec3(row,t0+1.0,1.0)),h(vec3(row,t0+1.0,2.0)),h(vec3(row,t0+1.0,3.0)));\n float m0=step(0.5,h(vec3(row,t0,0.0))); float m1=step(0.5,h(vec3(row,t0+1.0,0.0)));\n vec3 mag=vec3(1.0,0.0,1.0);\n vec3 c=mix(mix(mag,c0,m0),mix(mag,c1,m1),f);\n float dark=smoothstep(0.92,1.0,sin(TIME*0.9)*0.5+0.5);\n c*=1.0-0.85*dark;\n float inv=smoothstep(0.94,1.0,sin(TIME*0.57+2.0)*0.5+0.5);\n c=mix(c,vec3(1.0)-c,inv);\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wob":
			return "shader_type spatial;\nvoid fragment(){\n float t=TIME;\n float band=floor(VERTEX.y*4.0+t*6.0);\n float g=fract(sin(band)*43758.5453);\n vec3 c=vec3(fract(VERTEX.x*0.3+t),g,fract(VERTEX.z*0.3-t));\n if(g>0.7){c=vec3(1.0)-c;}\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wireframe":
			return "shader_type spatial;\nvoid fragment(){\n vec2 gr=abs(fract(UV*40.0)-0.5);\n float line=1.0-smoothstep(0.0,0.05,min(gr.x,gr.y));\n ALBEDO=vec3(0.02); EMISSION=vec3(0.1,0.9,0.5)*line;\n}"
	return ""

static func is_shader(kind: String) -> bool:
	return kind in ["pixel", "datamosh", "wob", "wireframe", "contrast"]

static var _fx_shader: Shader = null

## The customisable EFFECT skin: the portal/prism family with every dial
## exposed. Presets are just parameter sets.
static func effect_material(color: Color, fx: Dictionary) -> ShaderMaterial:
	if _fx_shader == null:
		_fx_shader = Shader.new()
		_fx_shader.code = """
shader_type spatial;
varying vec3 vpos;
uniform vec3 tint = vec3(0.5, 1.0, 1.0);
uniform float strength = 1.0;
uniform float speed = 1.0;
uniform float nscale = 5.0;
uniform float sharp = 2.0;
uniform float rainbow = 0.0;
uniform float fluid = 0.0;
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
// THE fluid algorithm, preserved exactly from the build the user liked:
// a different hash entirely, two soft octaves, faint additive glow.
float hash31(vec3 p) { p = fract(p * 0.3183 + vec3(0.1, 0.2, 0.3)); p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise31(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i), b = hash31(i + vec3(1,0,0)), c = hash31(i + vec3(0,1,0)), d = hash31(i + vec3(1,1,0));
	float e = hash31(i + vec3(0,0,1)), g = hash31(i + vec3(1,0,1)), h = hash31(i + vec3(0,1,1)), k = hash31(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y), mix(mix(e,g,f.x), mix(h,k,f.x), f.y), f.z); }
float fbm31(vec3 p) { return vnoise31(p) * 0.6 + vnoise31(p * 2.3) * 0.4; }
void fragment() {
	float t = TIME * speed;
	vec3 drift = vec3(t * 0.5, t * 0.35, t * 0.2);
	float sw = fluid > 0.5 ? fbm31(vpos * nscale + drift) : fbm(vpos * nscale + drift);
	float ring = sin(sw * 12.0 - t * 2.2) * 0.5 + 0.5;
	// fluid mode: the ORIGINAL fluid emission formula. portal mode: the
	// gate formula. same dials drive both.
	float body = fluid > 0.5
		? (0.32 * pow(ring, sharp) + sw * 0.11) * 2.6
		: (0.35 + 1.9 * pow(ring, sharp) + sw * 0.7);
	if (rainbow > 0.5) {
		float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
		float hue = fract(fres * 0.9 + TIME * 0.12);
		vec3 rb = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
		ALBEDO = mix(vec3(1.0, 0.55, 0.92), rb, 0.7);
		METALLIC = 0.85;
		ROUGHNESS = 0.12;
		EMISSION = rb * (0.25 + 0.55 * fres) + rb * body * 0.33 * strength;
	} else {
		ALBEDO = tint * 0.15;
		EMISSION = tint * body * strength;
		ROUGHNESS = 0.4;
	}
}
"""
	var m := ShaderMaterial.new()
	m.shader = _fx_shader
	# the effect wears YOUR color -- no separate tint
	m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	var defs := {"strength": 1.0, "speed": 1.0, "nscale": 5.0,
		"sharp": 2.0, "rainbow": 0.0, "fluid": 0.0}
	for k in defs:
		m.set_shader_parameter(k, float(fx.get(k, defs[k])))
	return m

static func make(kind: String, color: Color, tex: Texture2D = null,
		fx: Dictionary = {}) -> Material:
	if kind == "wth":
		kind = "datamosh"   # saved characters predate the rename
	if kind == "effect":
		return effect_material(color, fx)
	if is_shader(kind):
		var sh := Shader.new()
		sh.code = shader_code(kind)
		var sm := ShaderMaterial.new()
		sm.shader = sh
		return sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if tex:
		mat.albedo_texture = tex
	return mat
