class_name ShaderLib
extends RefCounted
## Shared inline shaders + material builder, used by the planets and the
## character-creator skins so they match.
##   pixel     - chunky pixelated surface
##   contrast  - crushed, extreme high-contrast terminator
##   wth       - actually broken/glitchy datamosh
##   wob       - the old "wth" (legacy wobble bands)
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
		"wth":
			# ACTUALLY broken: the geometry itself corrupts. Vertices spike
			# off the mesh, positions snap like a dying PS1, rows of the
			# surface tear sideways; texture falls back to missing-asset
			# magenta, frames drop to black, colours invert at random.
			return "shader_type spatial;\nfloat h(vec3 p){return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453);}\nvoid vertex(){\n float t=floor(TIME*7.0);\n float r=h(floor(VERTEX*0.5)+vec3(t));\n if(r>0.93){ VERTEX += NORMAL*(r-0.93)*260.0; }\n VERTEX = floor(VERTEX*0.35)/0.35;\n if(h(vec3(t,1.0,2.0))>0.75){ VERTEX.x += sin(VERTEX.y*0.2+t)*6.0; }\n}\nvoid fragment(){\n float t=TIME;\n float row=floor(UV.y*40.0);\n float g=h(vec3(row,floor(t*9.0),0.0));\n vec3 c=vec3(1.0,0.0,1.0);\n if(g>0.5){ c=vec3(h(vec3(row,floor(t*9.0),1.0)),h(vec3(row,floor(t*9.0),2.0)),h(vec3(row,floor(t*9.0),3.0))); }\n if(fract(t*5.0)<0.04){ c=vec3(0.0); }\n if(fract(t*3.1)<0.03){ c=vec3(1.0)-c; }\n ALBEDO=c; EMISSION=c*0.7;\n}"
		"wob":
			return "shader_type spatial;\nvoid fragment(){\n float t=TIME;\n float band=floor(VERTEX.y*4.0+t*6.0);\n float g=fract(sin(band)*43758.5453);\n vec3 c=vec3(fract(VERTEX.x*0.3+t),g,fract(VERTEX.z*0.3-t));\n if(g>0.7){c=vec3(1.0)-c;}\n ALBEDO=c; EMISSION=c*0.6;\n}"
		"wireframe":
			return "shader_type spatial;\nvoid fragment(){\n vec2 gr=abs(fract(UV*40.0)-0.5);\n float line=1.0-smoothstep(0.0,0.05,min(gr.x,gr.y));\n ALBEDO=vec3(0.02); EMISSION=vec3(0.1,0.9,0.5)*line;\n}"
	return ""

static func is_shader(kind: String) -> bool:
	return kind in ["pixel", "wth", "wob", "wireframe", "contrast"]

static func make(kind: String, color: Color, tex: Texture2D = null) -> Material:
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
