class_name SynthPaint
extends RefCounted
## The faceplate painter. ONE routine draws a module -- the editor uses
## it for the rack you patch, and the machine renders the same routine
## into a texture for the panel bolted into the real case. What you see
## on screen is literally what is screwed into the rack outside.
##
## Three houses build these panels and they do NOT look alike:
##   DUDE AUDIO      grey-into-blue brushed gradients, honest silkscreen
##   ICOSA INSTR.    icosahedron field, vibrant caps, buttons that shout
##   MONOLITHIC      dark stone grey, engraved seams, and a red eye

static var _grad: Dictionary = {}

static func _gradient(b: String) -> GradientTexture2D:
	if _grad.has(b):
		return _grad[b]
	var st := SynthMods.brand_style(b)
	var g := Gradient.new()
	g.set_color(0, st["bg"])
	g.set_color(1, st["bg2"])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0.25, 1)
	t.width = 64
	t.height = 128
	_grad[b] = t
	return t

static func font() -> Font:
	return ThemeDB.fallback_font

## Draw one module. `org` is the panel's top-left in canvas pixels, `s`
## is pixels per panel unit. `eng` (optional) feeds the live widgets.
static func draw_module(ci: CanvasItem, m, org: Vector2, s: float,
		eng = null, mi: int = -1, hot: Dictionary = {}) -> void:
	var d := SynthMods.def(m.id)
	var lay := SynthMods.layout(m.id)
	var st := SynthMods.brand_style(m.brand)
	var w: float = float(lay["w"]) * s
	var h: float = SynthMods.PANEL_H * s
	var rect := Rect2(org, Vector2(w, h))
	var acc: Color = d["col"]
	# ---------------------------------------------------------- faceplate
	ci.draw_texture_rect(_gradient(m.brand), rect, false)
	match str(st["motif"]):
		"grad":
			# brushed aluminium: fine horizontal grain + a cool sheen
			for i in int(h / (2.5 * s / 2.0)):
				var yy: float = org.y + float(i) * 2.5 * (s / 2.0)
				ci.draw_line(Vector2(org.x, yy), Vector2(org.x + w, yy),
					Color(1, 1, 1, 0.022), 1.0)
			ci.draw_rect(Rect2(org + Vector2(2.0 * s, 2.0 * s),
				Vector2(w - 4.0 * s, h - 4.0 * s)), Color(1, 1, 1, 0.05), false, maxf(1.0, s * 0.5))
		"icosa":
			# a field of twenty-sided shapes, because of course it is --
			# every one of them kept INSIDE its own faceplate: a panel's
			# artwork stops at the panel, it does not bleed onto its
			# neighbours in the rack
			var seedv: int = int(m.art) + m.id.length()
			for i in 5:
				var rr: float = (0.08 + 0.12 * float((seedv + i * 13) % 5) / 4.0) * h
				rr = minf(rr, minf(w, h) * 0.42)
				var fx: float = fposmod(float(seedv * (i + 3) * 37 % 100) / 100.0, 1.0)
				var fy: float = fposmod(float(seedv * (i + 5) * 53 % 100) / 100.0, 1.0)
				var cx: float = org.x + rr + fx * maxf(0.0, w - rr * 2.0)
				var cy: float = org.y + rr + fy * maxf(0.0, h - rr * 2.0)
				_icosa(ci, Vector2(cx, cy), rr,
					SynthMods.ICOS_HUES[(i + seedv) % 4] * Color(1, 1, 1, 0.16))
			ci.draw_rect(Rect2(org + Vector2(0, h - 3.0 * s), Vector2(w, 3.0 * s)),
				SynthMods.ICOS_HUES[int(m.art) % 4])
		"eye":
			# monolithic panels watch you patch them: small tilted eyes
			# scattered over the plate -- a red outline, a red circle
			# inside, nothing else. They sit UNDER the hardware.
			var sv: int = int(m.art) * 13 + m.id.length() * 29 + 7
			var placed: Array[Vector3] = []   # x, y, r
			for i in 7:
				if placed.size() >= 4:
					break
				var er: float = (0.050 + 0.030 * float((sv + i * 17) % 4) / 3.0) * h
				er = minf(er, w * 0.30)
				var fx2: float = float((sv * (i + 2) * 41) % 100) / 100.0
				var fy2: float = float((sv * (i + 5) * 67) % 100) / 100.0
				var cx2: float = org.x + er + fx2 * maxf(0.0, w - er * 2.0)
				var cy2: float = org.y + er + fy2 * maxf(0.0, h - er * 2.0)
				var clash := false
				for pv in placed:
					if Vector2(pv.x, pv.y).distance_to(Vector2(cx2, cy2)) < pv.z + er + 4.0 * s:
						clash = true
						break
				if clash:
					continue
				placed.append(Vector3(cx2, cy2, er))
				var ang2: float = (float((sv * (i + 3) * 23) % 200) / 100.0 - 1.0) * 1.1
				_eye(ci, Vector2(cx2, cy2), er, ang2, maxf(1.0, s * 0.45))
			for i in 3:
				var yy2: float = org.y + h * (0.30 + 0.22 * float(i))
				ci.draw_line(Vector2(org.x + 2.0 * s, yy2), Vector2(org.x + w - 2.0 * s, yy2),
					Color(0, 0, 0, 0.30), maxf(1.0, s * 0.4))
	# rack ears + screws
	ci.draw_rect(rect, Color(0, 0, 0, 0.55), false, maxf(1.0, s * 0.7))
	for sx in [0.2, 0.8]:
		for sy in [0.022, 0.978]:
			var sp := org + Vector2(w * sx, h * sy)
			ci.draw_circle(sp, maxf(1.0, s * 1.1), Color(0, 0, 0, 0.5))
			ci.draw_circle(sp - Vector2(0, maxf(0.4, s * 0.25)), maxf(0.8, s * 0.8),
				Color(st["ring"]) * Color(1, 1, 1, 0.8))
	# ------------------------------------------------------------- title
	var f := font()
	var tsz: int = maxi(7, int(s * 5.2))
	var nm: String = str(d["name"])
	var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	while tw > w - 4.0 * s and tsz > 6:
		tsz -= 1
		tw = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	match str(st["motif"]):
		"grad":
			ci.draw_rect(Rect2(org, Vector2(w, 14.0 * s)), Color(0, 0, 0, 0.30))
			ci.draw_string(f, org + Vector2((w - tw) * 0.5, 11.0 * s), nm,
				HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, st["text"])
			ci.draw_rect(Rect2(org + Vector2(0, 14.0 * s), Vector2(w, 1.2 * s)), acc)
		"icosa":
			# the name sits ON the colour, hard left, no apologies
			ci.draw_rect(Rect2(org, Vector2(w, 15.0 * s)),
				SynthMods.ICOS_HUES[int(m.art) % 4])
			ci.draw_string(f, org + Vector2(2.5 * s, 11.5 * s), nm,
				HORIZONTAL_ALIGNMENT_LEFT, w - 4.0 * s, tsz, Color("#0b0d12"))
		_:
			# carved: rules above and below, the name floating between
			ci.draw_rect(Rect2(org, Vector2(w, 15.0 * s)), Color(0, 0, 0, 0.42))
			ci.draw_line(org + Vector2(2.0 * s, 3.0 * s),
				org + Vector2(w - 2.0 * s, 3.0 * s), Color("#c8342a") * Color(1, 1, 1, 0.7),
				maxf(1.0, s * 0.5))
			ci.draw_string(f, org + Vector2((w - tw) * 0.5, 12.0 * s), nm,
				HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, st["text"])
			ci.draw_line(org + Vector2(2.0 * s, 15.0 * s),
				org + Vector2(w - 2.0 * s, 15.0 * s), Color("#c8342a") * Color(1, 1, 1, 0.7),
				maxf(1.0, s * 0.5))
	# brand mark down at the bottom edge
	var bsz: int = maxi(5, int(s * 2.4))
	ci.draw_string(f, org + Vector2(2.5 * s, h - 1.5 * s), str(st["name"]),
		HORIZONTAL_ALIGNMENT_LEFT, w - 4.0 * s, bsz,
		Color(st["trim"]) * Color(1, 1, 1, 0.75))
	# ------------------------------------------------------------- knobs
	var motif := str(st["motif"])
	var kn: Array = d["knobs"]
	# a panel that draws its own controls (the desk's faders) has no
	# placed knobs -- follow the LAYOUT, not the catalogue
	for i in (lay["knobs"] as Array).size():
		var kp: Vector2 = org + (lay["knobs"][i] as Vector2) * s
		var val: float = m.p[i] if i < m.p.size() else 0.0
		var kr := SynthMods.KNOB_R * s
		var lit: bool = hot.get("kind", "") == "knob" and int(hot.get("i", -1)) == i
		var a0 := PI * 0.75
		var a1 := PI * 0.75 + TAU * 0.75 * clampf(val, 0.0, 1.0)
		ci.draw_circle(kp + Vector2(0, kr * 0.18), kr * 1.05, Color(0, 0, 0, 0.45))
		match motif:
			"grad":
				# DUDE AUDIO: turned aluminium, chrome skirt, cyan arc
				ci.draw_circle(kp, kr, st["knob"])
				ci.draw_arc(kp, kr * 0.98, 0.0, TAU, 22,
					Color(st["cap"]) * (Color(1, 1, 1, 1) if lit else Color(1, 1, 1, 0.75)),
					maxf(1.0, s * 0.9))
				ci.draw_arc(kp, kr * 0.55, 0.0, TAU, 16, Color(1, 1, 1, 0.10), maxf(1.0, s * 0.5))
				ci.draw_arc(kp, kr * 1.30, a0, a1, 18, acc, maxf(1.2, s * 1.1))
				ci.draw_line(kp, kp + Vector2(cos(a1), sin(a1)) * kr * 0.9,
					st["pointer"], maxf(1.2, s * 1.0))
			"icosa":
				# ICOSA: a faceted hex cap, a fat wedge, dots round the rim
				var hue: Color = SynthMods.ICOS_HUES[i % 4]
				var hexp := PackedVector2Array()
				for k in 6:
					var aa := TAU * float(k) / 6.0 + a1
					hexp.append(kp + Vector2(cos(aa), sin(aa)) * kr)
				ci.draw_colored_polygon(hexp, hue if lit else hue.darkened(0.12))
				var inner := PackedVector2Array()
				for k in 6:
					var ab := TAU * float(k) / 6.0 + a1
					inner.append(kp + Vector2(cos(ab), sin(ab)) * kr * 0.52)
				ci.draw_colored_polygon(inner, Color("#0e1220"))
				var wedge := PackedVector2Array([
					kp + Vector2(cos(a1), sin(a1)) * kr * 1.0,
					kp + Vector2(cos(a1 + 0.34), sin(a1 + 0.34)) * kr * 0.42,
					kp + Vector2(cos(a1 - 0.34), sin(a1 - 0.34)) * kr * 0.42])
				ci.draw_colored_polygon(wedge, Color("#0b0d12"))
				for k in 9:
					var t2 := float(k) / 8.0
					var ad := a0 + TAU * 0.75 * t2
					ci.draw_circle(kp + Vector2(cos(ad), sin(ad)) * kr * 1.34,
						maxf(0.8, s * 0.5),
						hue if t2 <= clampf(val, 0.0, 1.0) else Color(1, 1, 1, 0.18))
			_:
				# MONOLITHIC: a squared stone cap, cut ticks, a red mark
				var sq := PackedVector2Array()
				for k in 4:
					var ac := TAU * float(k) / 4.0 + a1 + PI * 0.25
					sq.append(kp + Vector2(cos(ac), sin(ac)) * kr * 1.12)
				ci.draw_colored_polygon(sq, st["knob"])
				ci.draw_circle(kp, kr * 0.74, Color(st["cap"]) * Color(1, 1, 1, 0.55 if not lit else 0.9))
				for k in 11:
					var ae := a0 + TAU * 0.75 * float(k) / 10.0
					ci.draw_line(kp + Vector2(cos(ae), sin(ae)) * kr * 1.24,
						kp + Vector2(cos(ae), sin(ae)) * kr * 1.42,
						Color(0, 0, 0, 0.5), maxf(1.0, s * 0.5))
				ci.draw_line(kp, kp + Vector2(cos(a1), sin(a1)) * kr * 0.92,
					Color("#c8342a"), maxf(1.4, s * 1.2))
				ci.draw_circle(kp, kr * 0.16, Color("#ff3a2a") * Color(1, 1, 1, 0.8))
		if s > 2.4:
			var lbl: String = str(kn[i]["n"])
			var lsz: int = maxi(5, int(s * 3.0))
			var lw := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
			ci.draw_string(f, kp + Vector2(-lw * 0.5, kr + 4.6 * s), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, Color(st["text"]) * Color(1, 1, 1, 0.8))
	# ---------------------------------------------------------- switches
	var sws: Array = d["sw"]
	for i in sws.size():
		var r2: Rect2 = Rect2((lay["sw"][i] as Rect2).position * s + org,
			(lay["sw"][i] as Rect2).size * s)
		var on: int = m.sw[i] if i < m.sw.size() else 0
		var opts: Array = sws[i]["opts"]
		var txt: String = str(sws[i]["n"]) + ": " + str(opts[clampi(on, 0, opts.size() - 1)])
		var fsz: int = maxi(5, int(s * 3.4))
		var tw2 := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var tcol: Color = st["text"]
		match motif:
			"grad":
				ci.draw_rect(r2, acc.darkened(0.6))
				ci.draw_rect(Rect2(r2.position, Vector2(r2.size.x, r2.size.y * 0.45)),
					Color(1, 1, 1, 0.07))
				ci.draw_rect(r2, Color(0, 0, 0, 0.55), false, maxf(1.0, s * 0.5))
			"icosa":
				ci.draw_rect(Rect2(r2.position + Vector2(0, maxf(1.0, s * 0.8)), r2.size),
					Color(0, 0, 0, 0.5))
				ci.draw_rect(r2, SynthMods.ICOS_HUES[i % 4])
				ci.draw_rect(r2, Color(1, 1, 1, 0.35), false, maxf(1.0, s * 0.5))
				tcol = Color("#0b0d12")
			_:
				ci.draw_rect(r2, Color(0, 0, 0, 0.45))
				ci.draw_line(r2.position, r2.position + Vector2(r2.size.x, 0),
					Color(0, 0, 0, 0.7), maxf(1.0, s * 0.6))
				ci.draw_line(r2.position + Vector2(0, r2.size.y), r2.end,
					Color(1, 1, 1, 0.10), maxf(1.0, s * 0.5))
				tcol = Color("#ff3a2a")
		ci.draw_string(f, r2.position + Vector2(maxf(2.0, (r2.size.x - tw2) * 0.5),
			r2.size.y * 0.78), txt, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x, fsz, tcol)
	# ----------------------------------------------------------- widgets
	var wg := str(d["widget"])
	if wg != "":
		var wr: Rect2 = Rect2((lay["widget"] as Rect2).position * s + org,
			(lay["widget"] as Rect2).size * s)
		_widget(ci, m, wg, wr, s, st, acc, eng, mi)
	# ------------------------------------------------------------- jacks
	for pass_i in 2:
		var lst: Array = d["ins"] if pass_i == 0 else d["outs"]
		var pos: Array = lay["jin"] if pass_i == 0 else lay["jout"]
		for i in lst.size():
			var jp: Vector2 = org + (pos[i] as Vector2) * s
			var jr := SynthMods.JACK_R * s
			var is_out := pass_i == 1
			var lit2: bool = hot.get("kind", "") == ("jin" if pass_i == 0 else "jout") \
				and int(hot.get("i", -1)) == i
			var ringc: Color = Color("#ffffff") if lit2 else Color(st["ring"])
			match motif:
				"grad":
					ci.draw_circle(jp, jr * 1.55, ringc)
					ci.draw_circle(jp, jr * 1.55, Color(0, 0, 0, 0.35), false, maxf(1.0, s * 0.4))
					ci.draw_circle(jp, jr * 0.95, st["jack"])
					if is_out:
						ci.draw_arc(jp, jr * 1.55, 0.0, TAU, 16, acc, maxf(1.0, s * 0.55))
				"icosa":
					var nut := PackedVector2Array()
					for k in 6:
						var an := TAU * float(k) / 6.0 + PI / 6.0
						nut.append(jp + Vector2(cos(an), sin(an)) * jr * 1.7)
					ci.draw_colored_polygon(nut, ringc if not is_out
						else SynthMods.ICOS_HUES[i % 4])
					ci.draw_circle(jp, jr * 0.95, st["jack"])
				_:
					ci.draw_rect(Rect2(jp - Vector2(jr * 1.5, jr * 1.5),
						Vector2(jr * 3.0, jr * 3.0)), ringc)
					ci.draw_rect(Rect2(jp - Vector2(jr * 1.5, jr * 1.5),
						Vector2(jr * 3.0, jr * 3.0)),
						Color("#c8342a") if is_out else Color(0, 0, 0, 0.6),
						false, maxf(1.0, s * 0.5))
					ci.draw_circle(jp, jr * 0.95, st["jack"])
			if s > 2.4 and not (pass_i == 0 and i < int(lay.get("under", 0))) \
					and str(lst[i]) != "" and not bool(d.get("blank_labels", false)):
				var jl: String = str(lst[i])
				var jsz: int = maxi(5, int(s * 2.7))
				var jw := f.get_string_size(jl, HORIZONTAL_ALIGNMENT_LEFT, -1, jsz).x
				ci.draw_string(f, jp + Vector2(-jw * 0.5, -jr * 1.9 - 0.6 * s), jl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, jsz,
					Color(st["text"]) * Color(1, 1, 1, 0.85))
	# ---------------------------------------------------------- the lamp
	var led: float = clampf(m.led, 0.0, 1.0)
	var lp := org + Vector2(w - 3.4 * s, 7.4 * s)
	var lc: Color = Color(st["led"]) * Color(1, 1, 1, 0.25 + 0.75 * led)
	match motif:
		"grad":
			ci.draw_circle(lp, 1.9 * s, Color(0, 0, 0, 0.6))
			ci.draw_circle(lp, 1.4 * s, lc)
		"icosa":
			ci.draw_colored_polygon(PackedVector2Array([lp + Vector2(0, -2.1 * s),
				lp + Vector2(1.9 * s, 1.4 * s), lp + Vector2(-1.9 * s, 1.4 * s)]),
				Color(0, 0, 0, 0.6))
			ci.draw_colored_polygon(PackedVector2Array([lp + Vector2(0, -1.5 * s),
				lp + Vector2(1.3 * s, 1.0 * s), lp + Vector2(-1.3 * s, 1.0 * s)]), lc)
		_:
			ci.draw_rect(Rect2(lp - Vector2(1.9 * s, 1.9 * s),
				Vector2(3.8 * s, 3.8 * s)), Color(0, 0, 0, 0.6))
			ci.draw_rect(Rect2(lp - Vector2(1.3 * s, 1.3 * s),
				Vector2(2.6 * s, 2.6 * s)), lc)

## One monolithic eye: a red outline, a red circle inside. Tilted.
static func _eye(ci: CanvasItem, c: Vector2, r: float, ang: float, thick: float) -> void:
	var pts := PackedVector2Array()
	var ca := cos(ang)
	var sa := sin(ang)
	for i in 25:
		var t := TAU * float(i) / 24.0
		var x := cos(t) * r
		var y := sin(t) * r * 0.72
		pts.append(c + Vector2(x * ca - y * sa, x * sa + y * ca))
	ci.draw_polyline(pts, Color("#ff3a2a") * Color(1, 1, 1, 0.6), thick)
	ci.draw_circle(c, r * 0.34, Color("#ff3a2a") * Color(1, 1, 1, 0.55))

static func _icosa(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	# a flat-shaded icosahedron: hex silhouette, six spokes, inner ring
	var outer := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 - PI / 6.0
		outer.append(c + Vector2(cos(a), sin(a)) * r)
	var inner := PackedVector2Array()
	for i in 6:
		var a2 := TAU * float(i) / 6.0
		inner.append(c + Vector2(cos(a2), sin(a2)) * r * 0.5)
	ci.draw_colored_polygon(outer, col)
	for i in 6:
		ci.draw_line(outer[i], inner[i], col * Color(1, 1, 1, 2.2), 1.5)
		ci.draw_line(inner[i], inner[(i + 1) % 6], col * Color(1, 1, 1, 2.2), 1.5)
		ci.draw_line(outer[i], outer[(i + 1) % 6], col * Color(1, 1, 1, 2.6), 1.5)

## Widget names the painter has no drawing for. Empty is the only
## acceptable value -- four of these went missing once and the panels
## just rendered as blank boxes.
static var undrawn: Dictionary = {}

static func _widget(ci: CanvasItem, m, wg: String, r: Rect2, s: float,
		st: Dictionary, acc: Color, eng, mi: int) -> void:
	var f := font()
	ci.draw_rect(r, Color(0, 0, 0, 0.45))
	ci.draw_rect(r, Color(st["ring"]) * Color(1, 1, 1, 0.5), false, maxf(1.0, s * 0.4))
	match wg:
		"seq8", "seqn":
			var nst: int = int(SynthMods.def(m.id).get("steps", 8))
			var cur: int = int(m.s[0]) if m.s.size() > 0 else 0
			var cw := r.size.x / float(nst)
			for i in nst:
				var cr := Rect2(r.position + Vector2(cw * float(i) + 1.0, 2.0),
					Vector2(cw - 2.0, r.size.y * 0.62))
				ci.draw_rect(cr, Color(0, 0, 0, 0.5))
				var v: float = m.st[i] if m.st.size() > i else 0.5
				var bh := cr.size.y * clampf(v, 0.0, 1.0)
				ci.draw_rect(Rect2(cr.position + Vector2(0, cr.size.y - bh),
					Vector2(cr.size.x, bh)), acc)
				if i == cur:
					ci.draw_rect(cr, Color("#ffffff"), false, maxf(1.0, s * 0.6))
				var gr := Rect2(r.position + Vector2(cw * float(i) + 2.0,
					r.size.y * 0.68), Vector2(maxf(2.0, cw - 4.0), r.size.y * 0.26))
				var gon: bool = m.st.size() > nst + i and m.st[nst + i] > 0.5
				ci.draw_rect(gr, acc if gon else Color(0, 0, 0, 0.6))
				ci.draw_rect(gr, Color(st["ring"]) * Color(1, 1, 1, 0.6), false, 1.0)
		"roll":
			# eight bars of piano roll: the bar strip along the bottom,
			# the twelve semitones of the CURRENT bar above it
			var npr: int = int(SynthMods.def(m.id).get("patterns", 1))
			if eng != null and mi >= 0 and (SynthMods.def(m.id)["knobs"] as Array).size() > 2:
				npr = clampi(int(round(eng.knob_value(mi, 2))), 1, npr)
			var curR: int = int(m.s[0]) if m.s.size() > 0 else 0
			var patR: int = int(m.s[7]) if m.s.size() > 7 else 0
			var strip: float = 9.0 * s if npr > 1 else 0.0
			var gr2 := Rect2(r.position, Vector2(r.size.x, r.size.y - strip))
			var cwR := gr2.size.x / 16.0
			var rhR := gr2.size.y / 12.0
			for pitch in 12:
				var black: bool = pitch in [1, 3, 6, 8, 10]
				ci.draw_rect(Rect2(gr2.position + Vector2(0, rhR * float(11 - pitch)),
					Vector2(gr2.size.x, rhR)),
					Color(0, 0, 0, 0.35) if black else Color(1, 1, 1, 0.04))
			for i in 16:
				if i % 4 == 0:
					ci.draw_line(gr2.position + Vector2(cwR * float(i), 0),
						gr2.position + Vector2(cwR * float(i), gr2.size.y),
						Color(1, 1, 1, 0.16), 1.0)
				if i == curR:
					ci.draw_rect(Rect2(gr2.position + Vector2(cwR * float(i), 0),
						Vector2(cwR, gr2.size.y)), Color(1, 1, 1, 0.10))
				var nv: float = m.st[patR * 16 + i] if m.st.size() > patR * 16 + i else -1.0
				if nv >= 0.0:
					var pi2 := clampi(int(nv), 0, 11)
					ci.draw_rect(Rect2(gr2.position + Vector2(cwR * float(i) + 1.0,
						rhR * float(11 - pi2) + 1.0),
						Vector2(maxf(2.0, cwR - 2.0), maxf(2.0, rhR - 2.0))),
						acc if i != curR else Color("#ffffff"))
			if npr > 1:
				var bw := r.size.x / float(npr)
				for pi3 in npr:
					var br4 := Rect2(r.position + Vector2(bw * float(pi3) + 1.0,
						r.size.y - strip + 1.0), Vector2(bw - 2.0, strip - 2.0))
					var used := false
					for st3 in 16:
						if m.st.size() > pi3 * 16 + st3 and m.st[pi3 * 16 + st3] >= 0.0:
							used = true
							break
					ci.draw_rect(br4, Color("#ffffff") if pi3 == patR
						else (acc.darkened(0.35) if used else Color(0, 0, 0, 0.45)))
					var lsz3: int = maxi(5, int(s * 3.0))
					ci.draw_string(f, br4.position + Vector2(br4.size.x * 0.5 - s * 0.9,
						br4.size.y * 0.82), str(pi3 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
						lsz3, Color("#0b0d12") if pi3 == patR else Color(1, 1, 1, 0.75))
		"buttons":
			for bi in 2:
				var br2 := Rect2(r.position + Vector2(4.0 + r.size.x * 0.5 * float(bi),
					4.0), Vector2(r.size.x * 0.5 - 8.0, r.size.y - 8.0))
				var down: bool = m.st.size() > bi * 2 and m.st[bi * 2] > 0.5
				var latch: bool = m.st.size() > bi * 2 + 1 and m.st[bi * 2 + 1] > 0.5
				# the shadow the button sits in, then the cap on top of it
				ci.draw_rect(Rect2(br2.position + Vector2(0, 3.0), br2.size),
					Color(0, 0, 0, 0.55))
				var bcol: Color = acc if down else (acc.darkened(0.35) if latch
					else acc.darkened(0.62))
				ci.draw_rect(Rect2(br2.position + Vector2(0, 3.0 if down else 0.0),
					br2.size), bcol)
				ci.draw_line(br2.position + Vector2(0, 1.0),
					br2.position + Vector2(br2.size.x, 1.0), Color(1, 1, 1, 0.35), 1.0)
				ci.draw_rect(br2, Color(st["ring"]) * Color(1, 1, 1, 0.7), false,
					maxf(1.0, s * 0.5))
				var bl2 := "A" if bi == 0 else "B"
				var bsz2: int = maxi(6, int(s * 5.0))
				ci.draw_string(f, br2.position + Vector2(br2.size.x * 0.5 - s * 1.6,
					br2.size.y * 0.72), bl2, HORIZONTAL_ALIGNMENT_LEFT, -1, bsz2,
					Color("#0b0d12") if (down or latch) else st["text"])
		"xy":
			var px: float = m.st[0] if m.st.size() > 0 else 0.5
			var py: float = m.st[1] if m.st.size() > 1 else 0.5
			var hld: bool = m.st.size() > 2 and m.st[2] > 0.5
			for gi in 5:
				var gt2 := float(gi) / 4.0
				ci.draw_line(Vector2(r.position.x + r.size.x * gt2, r.position.y),
					Vector2(r.position.x + r.size.x * gt2, r.end.y), Color(1, 1, 1, 0.08), 1.0)
				ci.draw_line(Vector2(r.position.x, r.position.y + r.size.y * gt2),
					Vector2(r.end.x, r.position.y + r.size.y * gt2), Color(1, 1, 1, 0.08), 1.0)
			var puck := r.position + Vector2(r.size.x * px, r.size.y * py)
			ci.draw_line(Vector2(r.position.x, puck.y), Vector2(r.end.x, puck.y),
				acc * Color(1, 1, 1, 0.35), 1.0)
			ci.draw_line(Vector2(puck.x, r.position.y), Vector2(puck.x, r.end.y),
				acc * Color(1, 1, 1, 0.35), 1.0)
			ci.draw_circle(puck, maxf(3.0, s * 2.6), acc if hld else acc.darkened(0.3))
			ci.draw_arc(puck, maxf(5.0, s * 4.2), 0.0, TAU, 18,
				Color("#ffffff") * Color(1, 1, 1, 0.9 if hld else 0.35), 1.5)
		"carve":
			# the waveform, cut into the slab
			var cvw: float = clampf(m.s[1] if m.s.size() > 1 else 0.0, 0.0, 1.0)
			ci.draw_rect(r, Color(0, 0, 0, 0.25))
			var pts5 := PackedVector2Array()
			var ph7: float = float(m.art % 100) * 0.01
			for i in 40:
				var t7 := float(i) / 39.0
				var v7 := 0.0
				for k in 6:
					var kn3 := float(k + 1)
					v7 += sin(TAU * (t7 * 2.0 + ph7) * kn3) / kn3
				pts5.append(Vector2(r.position.x + r.size.x * t7,
					r.get_center().y - v7 * r.size.y * 0.28))
			# the cut: a dark groove under a lit edge
			var shadow := PackedVector2Array()
			for q in pts5:
				shadow.append(q + Vector2(0, maxf(1.0, s * 0.6)))
			ci.draw_polyline(shadow, Color(0, 0, 0, 0.55), maxf(1.2, s * 0.7))
			ci.draw_polyline(pts5, Color("#c8a89a") * Color(1, 1, 1, 0.9), maxf(1.2, s * 0.6))
			# chisel marks along the groove
			for i in 9:
				var xx3 := r.position.x + r.size.x * (float(i) + 0.5) / 9.0
				ci.draw_line(Vector2(xx3, r.position.y + r.size.y * 0.78),
					Vector2(xx3, r.position.y + r.size.y * 0.92),
					Color("#ff3a2a") * Color(1, 1, 1, 0.25 + 0.5 * cvw), maxf(1.0, s * 0.4))
		"glyph":
			# whatever it is doing, drawn. no key, no legend, no units.
			var cg := r.get_center()
			var rg: float = minf(r.size.x, r.size.y) * 0.46
			for k in 3:
				ci.draw_arc(cg, rg * (0.42 + 0.24 * float(k)),
					float(k) * 1.7, float(k) * 1.7 + TAU * (0.45 + 0.2 * float(k)), 26,
					Color("#c8342a") * Color(1, 1, 1, 0.22 + 0.1 * float(k)),
					maxf(1.0, s * 0.4))
			var pts3 := PackedVector2Array()
			for i in 24:
				var vx: float = m.s[8 + i] if m.s.size() > 8 + i else 0.0
				var ang3 := TAU * float(i) / 24.0
				pts3.append(cg + Vector2(cos(ang3), sin(ang3)) * rg
					* clampf(0.25 + absf(vx) * 0.7, 0.1, 1.0))
			if pts3.size() > 2:
				pts3.append(pts3[0])
				ci.draw_polyline(pts3, Color("#ff3a2a") * Color(1, 1, 1, 0.8),
					maxf(1.0, s * 0.5))
			for i in 6:
				var a6 := TAU * float(i) / 6.0 + float(m.art % 100) * 0.06
				ci.draw_line(cg + Vector2(cos(a6), sin(a6)) * rg * 0.2,
					cg + Vector2(cos(a6), sin(a6)) * rg * 1.02,
					Color(0, 0, 0, 0.35), maxf(1.0, s * 0.4))
			ci.draw_circle(cg, rg * 0.1, Color("#c8342a")
				* Color(1, 1, 1, 0.4 + 0.6 * clampf(m.led, 0.0, 1.0)))
		"column":
			# eight big carved stones, and the four columns down the side
			var nSc: int = int(SynthMods.def(m.id).get("steps", 8))
			var nPc: int = int(SynthMods.def(m.id).get("patterns", 1))
			var curC: int = int(m.s[0]) if m.s.size() > 0 else 0
			var patC: int = int(m.s[7]) if m.s.size() > 7 else 0
			var strip3: float = 11.0 * s if nPc > 1 else 0.0
			var gw2 := r.size.x - strip3
			var chC: float = r.size.y / float(nSc)
			for i in nSc:
				var cr2 := Rect2(r.position + Vector2(2.0, chC * float(i) + 1.5),
					Vector2(gw2 - 4.0, chC - 3.0))
				var onC: bool = m.st.size() > patC * nSc + i \
					and m.st[patC * nSc + i] > 0.5
				ci.draw_rect(cr2, Color("#c8342a").darkened(0.1) if onC
					else Color(0, 0, 0, 0.45))
				# cut, not painted: a lit top edge and a shadowed bottom
				ci.draw_line(cr2.position, cr2.position + Vector2(cr2.size.x, 0),
					Color(1, 1, 1, 0.12), maxf(1.0, s * 0.4))
				ci.draw_line(cr2.position + Vector2(0, cr2.size.y), cr2.end,
					Color(0, 0, 0, 0.55), maxf(1.0, s * 0.4))
				if onC:
					ci.draw_circle(cr2.get_center(), minf(cr2.size.y, cr2.size.x) * 0.22,
						Color("#ff6a5a") * Color(1, 1, 1, 0.55))
				if i == curC:
					ci.draw_rect(cr2, Color("#ff3a2a"), false, maxf(1.4, s * 0.8))
			if nPc > 1:
				var bh := r.size.y / float(nPc)
				for pi4 in nPc:
					var br5 := Rect2(r.position + Vector2(gw2 + 1.0, bh * float(pi4) + 1.5),
						Vector2(strip3 - 2.0, bh - 3.0))
					var used2 := false
					for st5 in nSc:
						if m.st.size() > pi4 * nSc + st5 and m.st[pi4 * nSc + st5] > 0.5:
							used2 = true
							break
					ci.draw_rect(br5, Color("#c8342a") if pi4 == patC
						else (Color("#5a2a24") if used2 else Color(0, 0, 0, 0.5)))
					ci.draw_rect(br5, Color(0, 0, 0, 0.5), false, 1.0)
					var lsz4: int = maxi(5, int(s * 3.4))
					ci.draw_string(f, br5.position + Vector2(br5.size.x * 0.5 - s * 1.0,
						br5.size.y * 0.72), str(pi4 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1,
						lsz4, Color("#140a09") if pi4 == patC else Color(1, 1, 1, 0.6))
		"kit":
			# eight drum lanes, each labelled with the voice inside it
			var lanes := ["K", "S", "H", "O", "C", "T", "R", "B"]
			var curK: int = int(m.s[0]) if m.s.size() > 0 else 0
			var lw2 := 7.0 * s
			var gw := r.size.x - lw2
			var cwK := gw / 16.0
			var rhK := r.size.y / 8.0
			for lane in 8:
				ci.draw_string(f, r.position + Vector2(1.0, rhK * float(lane) + rhK * 0.78),
					str(lanes[lane]), HORIZONTAL_ALIGNMENT_LEFT, lw2,
					maxi(5, int(s * 3.2)), Color(st["text"]) * Color(1, 1, 1, 0.6))
				for i in 16:
					var cell2 := Rect2(r.position + Vector2(lw2 + cwK * float(i) + 1.0,
						rhK * float(lane) + 1.0), Vector2(cwK - 2.0, rhK - 2.0))
					var onK: bool = m.st.size() > lane * 16 + i and m.st[lane * 16 + i] > 0.5
					var beatK: bool = i % 4 == 0
					ci.draw_rect(cell2, acc.lerp(Color("#ffffff"), 0.12) if onK
						else (Color(1, 1, 1, 0.10) if beatK else Color(0, 0, 0, 0.45)))
					if i == curK:
						ci.draw_rect(cell2, Color("#ffffff") * Color(1, 1, 1, 0.6), false, 1.0)
		"grid":
			# sixty-four cells of ODDS: the fill height of a cell is the
			# chance that cell fires, and the cell lights up on the pass
			# where it actually did
			var patg: int = clampi(int(m.s[4]) if m.s.size() > 4 else 0, 0, 3)
			var curg: int = int(m.s[0]) if m.s.size() > 0 else 0
			var cwg := r.size.x / 16.0
			var rhg := r.size.y / 4.0
			for lane in 4:
				var fired: bool = m.s.size() > 8 + lane and m.s[8 + lane] > 1.0
				for i in 16:
					var cellg := Rect2(r.position + Vector2(cwg * float(i) + 1.0,
						rhg * float(lane) + 1.0), Vector2(cwg - 2.0, rhg - 2.0))
					var idxg: int = patg * 64 + lane * 16 + i
					var odds: float = m.st[idxg] if m.st.size() > idxg else 0.0
					var beatg: bool = i % 4 == 0
					ci.draw_rect(cellg, Color(1, 1, 1, 0.09) if beatg
						else Color(0, 0, 0, 0.45))
					if odds > 0.001:
						# the odds, as a column standing in the cell
						var hh: float = cellg.size.y * clampf(odds, 0.0, 1.0)
						var barg := Rect2(cellg.position
							+ Vector2(0.0, cellg.size.y - hh),
							Vector2(cellg.size.x, hh))
						var certain: bool = odds > 0.985
						ci.draw_rect(barg, acc.lerp(Color("#ffffff"),
							0.35 if certain else 0.05)
							* Color(1, 1, 1, 0.45 + odds * 0.55))
					if i == curg:
						ci.draw_rect(cellg, Color("#ffffff")
							* Color(1, 1, 1, 0.85 if fired else 0.35), false, 1.0)
			# which of the four patterns is loaded
			for pp in 4:
				ci.draw_circle(r.position + Vector2(r.size.x - 4.0 - float(3 - pp) * 5.0,
					-3.0), 1.6, Color("#ffffff") * Color(1, 1, 1,
					0.85 if pp == patg else 0.22))
		"muse":
			# the phrase it is playing right now, as notes on a stave of
			# its own: height is pitch, a filled note is a gate, a tall
			# one is accented
			var lnm: int = 8
			if eng != null and mi >= 0:
				lnm = clampi(int(round(eng.knob_value(mi, 1))), 2, 16)
			var curm: int = int(m.s[0]) if m.s.size() > 0 else 0
			var cwm := r.size.x / float(lnm)
			var hi := 1.0
			for i in lnm:
				hi = maxf(hi, m.st[i] if m.st.size() > i else 0.0)
			ci.draw_line(r.position + Vector2(0.0, r.size.y - 1.0),
				r.position + Vector2(r.size.x, r.size.y - 1.0),
				Color(1, 1, 1, 0.12), 1.0)
			for i in lnm:
				var deg: float = m.st[i] if m.st.size() > i else 0.0
				var gt: float = m.st[16 + i] if m.st.size() > 16 + i else 0.0
				var yv: float = r.size.y - 3.0 - (deg / hi) * (r.size.y - 8.0)
				var nx := r.position.x + cwm * float(i) + 1.0
				if gt < 0.5:
					# a rest: the place the note would have been, left empty
					ci.draw_rect(Rect2(nx, r.position.y + yv - 0.5,
						cwm - 2.0, 1.0), Color(1, 1, 1, 0.13))
					continue
				var nc: Color = acc if gt < 1.5 else acc.lerp(Color("#ffffff"), 0.55)
				ci.draw_rect(Rect2(nx, r.position.y + yv - (2.0 if gt > 1.5 else 1.2),
					cwm - 2.0, (4.0 if gt > 1.5 else 2.4)), nc)
				if i == curm:
					ci.draw_rect(Rect2(nx - 1.0, r.position.y + 1.0,
						cwm, r.size.y - 2.0), Color(1, 1, 1, 0.14))
		"chords":
			# the progression, with the bar it is on lit
			var barc: int = int(m.s[0]) if m.s.size() > 0 else 0
			var romans := ["I", "II", "III", "IV", "V", "VI", "VII"]
			var dgc: int = int(m.s[4]) if m.s.size() > 4 else 0
			var cwc := r.size.x / 4.0
			for bb2 in 4:
				var cell4 := Rect2(r.position + Vector2(cwc * float(bb2) + 1.0, 1.0),
					Vector2(cwc - 2.0, r.size.y - 2.0))
				var here: bool = bb2 == barc
				ci.draw_rect(cell4, acc * Color(1, 1, 1, 0.30) if here
					else Color(0, 0, 0, 0.40))
				var lbl: String = str(romans[dgc % 7]) if here else "·"
				ci.draw_string(f, cell4.position + Vector2(3.0, cell4.size.y * 0.72),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, cell4.size.x,
					maxi(5, int(s * 4.0)), Color(st["text"])
					* Color(1, 1, 1, 0.95 if here else 0.35))
			# the four voices it is holding, as a stack of ticks
			for t in 4:
				var vv2: float = m.s[8 + t] if m.s.size() > 8 + t else 0.0
				var yy: float = r.position.y + r.size.y - 2.0 - float(t) * 2.0
				ci.draw_line(Vector2(r.position.x + r.size.x - 14.0, yy),
					Vector2(r.position.x + r.size.x - 14.0
						+ clampf(vv2 * 4.0, -12.0, 12.0), yy),
					acc * Color(1, 1, 1, 0.7), 1.0)
		"dseq":
			var cur2: int = int(m.s[0]) if m.s.size() > 0 else 0
			var cw2 := r.size.x / 16.0
			var rh := r.size.y / 4.0
			for lane in 4:
				for i in 16:
					var cell := Rect2(r.position + Vector2(cw2 * float(i) + 1.0,
						rh * float(lane) + 1.0), Vector2(cw2 - 2.0, rh - 2.0))
					var on: bool = m.st.size() > lane * 16 + i and m.st[lane * 16 + i] > 0.5
					var beat: bool = i % 4 == 0
					var base := Color(1, 1, 1, 0.10) if beat else Color(0, 0, 0, 0.45)
					ci.draw_rect(cell, acc.lerp(Color("#ffffff"), 0.15) if on else base)
					if i == cur2:
						ci.draw_rect(cell, Color("#ffffff") * Color(1, 1, 1, 0.6), false, 1.0)
		"euclid":
			var steps: int = 16
			var fill: int = 4
			var rot: int = 0
			if eng != null and mi >= 0:
				steps = clampi(int(round(eng.knob_value(mi, 0))), 1, 32)
				fill = clampi(int(round(eng.knob_value(mi, 1))), 0, steps)
				rot = int(round(eng.knob_value(mi, 2)))
			var c := r.get_center()
			var rad: float = minf(r.size.x, r.size.y) * 0.42
			var cur3: int = int(m.s[5]) if m.s.size() > 5 else 0
			for i in steps:
				var a := TAU * float(i) / float(steps) - PI * 0.5
				var p := c + Vector2(cos(a), sin(a)) * rad
				var hit: bool = fill > 0 and ((i * fill) % steps) < fill
				ci.draw_circle(p, maxf(1.5, s * 1.7), acc if hit else Color(1, 1, 1, 0.22))
				if posmod(i - rot, steps) == posmod(cur3, steps):
					ci.draw_arc(p, maxf(2.5, s * 3.0), 0.0, TAU, 10, Color("#ffffff"), 1.2)
		"cast":
			# what the transmitter is actually doing right now
			var on_air: bool = m.sw.size() > 0 and m.sw[0] == 1
			var gfreq: float = m.s[0] if m.s.size() > 0 else 0.0
			var bumped: bool = m.s.size() > 1 and m.s[1] > 0.5
			var lis: int = int(m.s[2]) if m.s.size() > 2 else 0
			var lvl4: float = m.s[3] if m.s.size() > 3 else 0.0
			var nexus: bool = m.s.size() > 4 and m.s[4] > 0.5
			var fsz2: int = maxi(8, int(s * 8.0))
			var full: bool = m.s.size() > 5 and m.s[5] > 0.5
			var big := ("%.1f FM" % gfreq) if (on_air and gfreq > 0.0) \
				else ("BAND FULL" if full else "-- OFF AIR --")
			var bcol: Color = Color("#3aff6a") if (on_air and gfreq > 0.0) \
				else (Color("#ffd166") if full else Color("#ff5964"))
			ci.draw_string(f, r.position + Vector2(4.0, r.size.y * 0.30), big,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0, fsz2, bcol)
			if on_air:
				var dotc: Color = Color("#ff3a2a")
				ci.draw_circle(r.position + Vector2(r.size.x - 6.0 * s, r.size.y * 0.18),
					2.4 * s, dotc * Color(1, 1, 1, 0.35 + 0.65 * clampf(lvl4 * 3.0, 0.0, 1.0)))
			# the name plate: click it to retype the station name
			var np := Rect2(r.position + Vector2(3.0, r.size.y * 0.34),
				Vector2(r.size.x - 6.0, r.size.y * 0.26))
			ci.draw_rect(np, Color(0, 0, 0, 0.5))
			ci.draw_rect(np, Color(st["ring"]) * Color(1, 1, 1, 0.6), false, 1.0)
			var nm2: String = str(m.name_tag) if str(m.name_tag) != "" else "DUDE FM"
			ci.draw_string(f, np.position + Vector2(4.0, np.size.y * 0.76), nm2,
				HORIZONTAL_ALIGNMENT_LEFT, np.size.x - 8.0, maxi(6, int(s * 4.4)),
				Color(st["text"]))
			# the fallback line: it says so when it got bumped up the band
			var msg := ""
			var mcol: Color = Color(st["text"]) * Color(1, 1, 1, 0.7)
			if full:
				msg = "every slot 88.0-108.0 is claimed — nothing left to take"
				mcol = Color("#ffd166")
			elif not on_air:
				msg = "switch AIR on to claim a frequency"
			elif bumped:
				msg = "REQUESTED SLOT TAKEN — FORWARDED UP THE BAND"
				mcol = Color("#ffd166")
			elif nexus:
				msg = "NEXUS ARRAY — full strength system-wide"
				mcol = Color("#7be8ff")
			else:
				msg = "local transmitter — fades with distance. Park the case in the NEXUS STATION array for system-wide range."
			ci.draw_string(f, r.position + Vector2(4.0, r.size.y * 0.72), msg,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0, maxi(5, int(s * 3.2)), mcol)
			# listeners + level
			ci.draw_string(f, r.position + Vector2(4.0, r.size.y * 0.95),
				"%d listening" % lis, HORIZONTAL_ALIGNMENT_LEFT, -1,
				maxi(5, int(s * 3.4)),
				Color("#3aff6a") if lis > 0 else Color(1, 1, 1, 0.45))
			var mw := (r.size.x - 8.0) * 0.45
			var mr := Rect2(r.position + Vector2(r.size.x - 4.0 - mw, r.size.y * 0.86),
				Vector2(mw, r.size.y * 0.10))
			ci.draw_rect(mr, Color(0, 0, 0, 0.5))
			ci.draw_rect(Rect2(mr.position, Vector2(mr.size.x * clampf(lvl4 * 2.0, 0.0, 1.0),
				mr.size.y)), Color("#3aff6a").lerp(Color("#ff5964"),
				clampf(lvl4 * 2.4 - 0.6, 0.0, 1.0)))
		"bars":
			# an additive spectrum you draw with the mouse
			var nb: int = int(SynthMods.def(m.id).get("steps", 20))
			var cwb := r.size.x / float(nb)
			for i in nb:
				var hb: float = clampf(m.st[i] if m.st.size() > i else 0.0, 0.0, 1.0)
				var br3 := Rect2(r.position + Vector2(cwb * float(i) + 1.0,
					r.size.y * (1.0 - hb)), Vector2(maxf(1.5, cwb - 2.0), r.size.y * hb))
				ci.draw_rect(br3, SynthMods.ICOS_HUES[i % 4] if str(st["motif"]) == "icosa"
					else acc)
				if i % 5 == 0:
					ci.draw_line(r.position + Vector2(cwb * float(i), 0),
						r.position + Vector2(cwb * float(i), r.size.y),
						Color(1, 1, 1, 0.12), 1.0)
		"turing":
			var n := 16
			var cw3 := r.size.x / float(n)
			for i in n:
				var on2: bool = m.s.size() > 8 + i and m.s[8 + i] > 0.5
				ci.draw_rect(Rect2(r.position + Vector2(cw3 * float(i) + 1.0, 2.0),
					Vector2(cw3 - 2.0, r.size.y - 4.0)),
					acc if on2 else Color(0, 0, 0, 0.55))
		"analyser":
			# the wave itself on top, and what it actually IS underneath
			var trace := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.52))
			ci.draw_rect(trace, Color(0, 0, 0, 0.4))
			ci.draw_line(Vector2(trace.position.x, trace.get_center().y),
				Vector2(trace.end.x, trace.get_center().y), Color(1, 1, 1, 0.14), 1.0)
			for gx3 in 4:
				var gxx := trace.position.x + trace.size.x * (float(gx3) + 1.0) / 5.0
				ci.draw_line(Vector2(gxx, trace.position.y), Vector2(gxx, trace.end.y),
					Color(1, 1, 1, 0.07), 1.0)
			if m.d.size() >= 256:
				# the capture always starts on a rising edge, so it is
				# read straight through from the beginning and the wave
				# sits still
				var pts7 := PackedVector2Array()
				for i in 256:
					var yv2: float = clampf(m.d[i] / 5.0, -1.0, 1.0)
					pts7.append(Vector2(trace.position.x + trace.size.x * float(i) / 255.0,
						trace.get_center().y - yv2 * trace.size.y * 0.44))
				if pts7.size() > 2:
					ci.draw_polyline(pts7, acc, maxf(1.2, s * 0.6))
					# the trigger point, marked where the sweep begins
					ci.draw_line(Vector2(trace.position.x + 1.0, trace.get_center().y - 3.0 * s),
						Vector2(trace.position.x + 1.0, trace.get_center().y + 3.0 * s),
						Color("#3aff6a") * Color(1, 1, 1, 0.7), maxf(1.0, s * 0.4))
			# the numbers
			var freq2: float = m.s[10] if m.s.size() > 10 else 0.0
			var pk5: float = m.s[11] if m.s.size() > 11 else 0.0
			var rms3: float = m.s[12] if m.s.size() > 12 else 0.0
			var dc2: float = m.s[13] if m.s.size() > 13 else 0.0
			var duty: float = m.s[14] if m.s.size() > 14 else 0.0
			var shape: int = int(m.s[15]) if m.s.size() > 15 else 4
			var refhz: float = 440.0
			if eng != null and mi >= 0:
				refhz = eng.knob_value(mi, 2)
			var shapes := ["SQUARE-ISH", "SINE-ISH", "SAW / TRI", "SPIKY / NOISE", "-- no signal --"]
			var note := "--"
			var cents := 0.0
			if freq2 > 8.0:
				var midi: float = 69.0 + 12.0 * log(freq2 / refhz) / log(2.0)
				var nn := int(round(midi))
				cents = (midi - float(nn)) * 100.0
				var names := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
				note = "%s%d" % [str(names[posmod(nn, 12)]), int(floor(float(nn) / 12.0)) - 1]
			var fsz3: int = maxi(6, int(s * 4.2))
			var fsz4: int = maxi(5, int(s * 3.2))
			var ty := trace.end.y + fsz3 + 1.0
			var big2 := "-- Hz" if freq2 <= 8.0 else ("%.1f Hz" % freq2 if freq2 < 1000.0
				else "%.2f kHz" % (freq2 / 1000.0))
			ci.draw_string(f, Vector2(r.position.x + 3.0, ty), big2,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fsz3, Color(st["text"]))
			ci.draw_string(f, Vector2(r.position.x + r.size.x * 0.52, ty),
				"%s %+.0f\u00a2" % [note, cents] if freq2 > 8.0 else "",
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.48, fsz3,
				Color("#3aff6a") if absf(cents) < 6.0 else Color("#ffd166"))
			ci.draw_string(f, Vector2(r.position.x + 3.0, ty + fsz4 + 3.0),
				"pk %.2f V   rms %.2f V   crest %.2f" % [pk5, rms3,
					pk5 / maxf(rms3, 0.0001)],
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fsz4,
				Color(st["text"]) * Color(1, 1, 1, 0.8))
			ci.draw_string(f, Vector2(r.position.x + 3.0, ty + (fsz4 + 3.0) * 2.0),
				"duty %d%%   dc %+.2f V" % [int(duty * 100.0), dc2],
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fsz4,
				Color(st["text"]) * Color(1, 1, 1, 0.65))
			ci.draw_string(f, Vector2(r.position.x + 3.0, ty + (fsz4 + 3.0) * 3.0),
				str(shapes[clampi(shape, 0, 4)]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x,
				fsz4, acc)
		"spectrum":
			# twelve bars, with the picked band called out
			var nbz := 12
			var bw2 := r.size.x / float(nbz)
			var pick2: int = 0
			if eng != null and mi >= 0:
				pick2 = clampi(int(round(eng.knob_value(mi, 4))) - 1, 0, 11)
			for bi2 in nbz:
				var hgt: float = clampf(m.s[24 + bi2] if m.s.size() > 24 + bi2 else 0.0,
					0.0, 1.0)
				var br6 := Rect2(r.position + Vector2(bw2 * float(bi2) + 1.0,
					r.size.y * (1.0 - hgt)), Vector2(bw2 - 2.0, r.size.y * hgt))
				var bc: Color = acc.lerp(Color("#ff5964"), clampf(hgt * 1.3 - 0.3, 0.0, 1.0))
				ci.draw_rect(br6, bc if bi2 != pick2 else Color("#ffffff"))
				# the cap sits on top so a quiet band is still visible
				ci.draw_rect(Rect2(br6.position + Vector2(0, -1.5),
					Vector2(br6.size.x, 1.5)), bc.lightened(0.4))
			for gl in 3:
				var gy := r.position.y + r.size.y * (float(gl) + 1.0) / 4.0
				ci.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy),
					Color(1, 1, 1, 0.08), 1.0)
		"waterfall":
			# frequency up the panel, time across it, brightness for level
			var cols := 64
			var rows := 12
			var cwf := r.size.x / float(cols)
			var rhf := r.size.y / float(rows)
			var head: int = int(m.s[37]) if m.s.size() > 37 else 0
			for cx2 in cols:
				var src3: int = (head + cx2) % cols
				for ry in rows:
					var v10: float = m.d[ry * 64 + src3] if m.d.size() > ry * 64 + src3 else 0.0
					if v10 < 0.02:
						continue
					var cc2: Color = Color("#0b1c2a").lerp(acc, clampf(v10 * 1.6, 0.0, 1.0))
					if v10 > 0.75:
						cc2 = cc2.lerp(Color("#fff2c8"), (v10 - 0.75) * 4.0)
					ci.draw_rect(Rect2(r.position + Vector2(cwf * float(cx2),
						r.size.y - rhf * float(ry + 1)),
						Vector2(cwf + 0.6, rhf + 0.6)), cc2)
		"vector":
			# one signal against the other: tuning, made visible
			var gainv: float = 1.0
			var trail: float = 0.6
			if eng != null and mi >= 0:
				gainv = eng.knob_value(mi, 0)
				trail = eng.knob_value(mi, 1)
			ci.draw_line(Vector2(r.position.x, r.get_center().y),
				Vector2(r.end.x, r.get_center().y), Color(1, 1, 1, 0.10), 1.0)
			ci.draw_line(Vector2(r.get_center().x, r.position.y),
				Vector2(r.get_center().x, r.end.y), Color(1, 1, 1, 0.10), 1.0)
			if m.d.size() >= 1024:
				var wv: int = int(m.s[0])
				var n11 := int(lerpf(90.0, 460.0, clampf(trail, 0.0, 1.0)))
				var pts6 := PackedVector2Array()
				for i in n11:
					var si2 := (wv - n11 + i + 512) % 512
					var xv: float = clampf(m.d[si2] / 5.0 * gainv, -1.0, 1.0)
					var yv: float = clampf(m.d[512 + si2] / 5.0 * gainv, -1.0, 1.0)
					pts6.append(r.get_center() + Vector2(xv * r.size.x * 0.46,
						-yv * r.size.y * 0.46))
				if pts6.size() > 2:
					ci.draw_polyline(pts6, acc * Color(1, 1, 1, 0.55), maxf(1.0, s * 0.45))
					ci.draw_circle(pts6[pts6.size() - 1], maxf(1.5, s * 1.1),
						Color("#ffffff"))
		"vu":
			# four needles on an arc, each with a peak that hangs
			var chn := 4
			var cw4 := r.size.x / float(chn)
			for ch3 in chn:
				var cr4 := Rect2(r.position + Vector2(cw4 * float(ch3) + 1.0, 1.0),
					Vector2(cw4 - 2.0, r.size.y - 2.0))
				ci.draw_rect(cr4, Color("#1a1710"))
				var piv := Vector2(cr4.get_center().x, cr4.end.y - 2.0)
				var rad2: float = minf(cr4.size.x, cr4.size.y) * 0.86
				ci.draw_arc(piv, rad2, PI, TAU, 20, Color(1, 1, 1, 0.18), 1.0)
				# the red end of the scale
				ci.draw_arc(piv, rad2, PI * 1.75, TAU, 8, Color("#ff5964") * Color(1, 1, 1, 0.5),
					maxf(1.2, s * 0.6))
				var lv3: float = clampf(m.s[ch3] if m.s.size() > ch3 else 0.0, 0.0, 1.2)
				var ang4 := PI + PI * clampf(lv3, 0.0, 1.0)
				ci.draw_line(piv, piv + Vector2(cos(ang4), sin(ang4)) * rad2 * 0.92,
					Color("#f2f4f7"), maxf(1.2, s * 0.6))
				var pk3: float = clampf(m.s[4 + ch3] if m.s.size() > 4 + ch3 else 0.0, 0.0, 1.2)
				var angp := PI + PI * clampf(pk3, 0.0, 1.0)
				ci.draw_line(piv + Vector2(cos(angp), sin(angp)) * rad2 * 0.72,
					piv + Vector2(cos(angp), sin(angp)) * rad2 * 0.98,
					Color("#ff5964") if pk3 > 0.98 else Color("#ffd166"), maxf(1.0, s * 0.5))
				ci.draw_circle(piv, maxf(1.2, s * 0.9), Color("#8a7f70"))
		"scope":
			var pts := PackedVector2Array()
			var pts2 := PackedVector2Array()
			if m.d.size() >= 1024:
				var gain: float = 1.0
				if eng != null and mi >= 0:
					gain = eng.knob_value(mi, 1)
				var wp: int = int(m.s[0])
				for i in 128:
					var si := (wp + i * 4) % 512
					var x := r.position.x + r.size.x * float(i) / 127.0
					var y1 := r.get_center().y - clampf(m.d[si] / 5.0 * gain, -1.0, 1.0) * r.size.y * 0.45
					var y2 := r.get_center().y - clampf(m.d[512 + si] / 5.0 * gain, -1.0, 1.0) * r.size.y * 0.45
					pts.append(Vector2(x, y1))
					pts2.append(Vector2(x, y2))
			ci.draw_line(Vector2(r.position.x, r.get_center().y),
				Vector2(r.end.x, r.get_center().y), Color(1, 1, 1, 0.18), 1.0)
			if pts.size() > 1:
				ci.draw_polyline(pts2, Color("#ff9a3c") * Color(1, 1, 1, 0.8), maxf(1.0, s * 0.5))
				ci.draw_polyline(pts, Color("#3aff6a"), maxf(1.2, s * 0.7))
		"desk":
			# six channel strips and a master: pan pot, fader, mute, meter
			var nch := 6
			var stripw := r.size.x / float(nch + 1)
			var panh := 9.0 * s
			var muteh := 8.0 * s
			for ch in nch + 1:
				var master: bool = ch == nch
				var sx2 := r.position.x + stripw * float(ch)
				var body := Rect2(Vector2(sx2 + 1.0, r.position.y),
					Vector2(stripw - 2.0, r.size.y))
				ci.draw_rect(body, Color(0, 0, 0, 0.30) if not master
					else Color(0.9, 0.9, 1.0, 0.06))
				# --- pan, across the top (channels only)
				var top := body.position.y
				if not master:
					var pv: float = 0.0
					if eng != null and mi >= 0:
						pv = eng.knob_value(mi, 6 + ch)
					var pr := Rect2(Vector2(body.position.x + 2.0, top + 2.0),
						Vector2(body.size.x - 4.0, panh - 4.0))
					ci.draw_rect(pr, Color(0, 0, 0, 0.45))
					ci.draw_line(Vector2(pr.get_center().x, pr.position.y),
						Vector2(pr.get_center().x, pr.end.y), Color(1, 1, 1, 0.18), 1.0)
					var px2 := pr.position.x + pr.size.x * clampf((pv + 1.0) * 0.5, 0.0, 1.0)
					ci.draw_rect(Rect2(Vector2(px2 - 1.5 * s, pr.position.y),
						Vector2(3.0 * s, pr.size.y)), acc)
				# --- the fader
				var ftop := top + (panh if not master else 2.0)
				var fh := r.size.y - (panh if not master else 2.0) - muteh - 4.0
				var fr := Rect2(Vector2(body.position.x + 2.0, ftop),
					Vector2(body.size.x - 4.0, fh))
				ci.draw_rect(fr, Color(0, 0, 0, 0.40))
				# the slot the cap runs in
				ci.draw_rect(Rect2(Vector2(fr.get_center().x - 1.0 * s, fr.position.y + 3.0),
					Vector2(2.0 * s, fr.size.y - 6.0)), Color(1, 1, 1, 0.13))
				var lv2: float = 0.0
				if eng != null and mi >= 0:
					lv2 = eng.mods[mi].p[ch if not master else 12]
				var capy := fr.end.y - 4.0 - (fr.size.y - 10.0) * clampf(lv2, 0.0, 1.0)
				var cap2 := Rect2(Vector2(fr.position.x + 1.0, capy - 2.5 * s),
					Vector2(fr.size.x - 2.0, 5.0 * s))
				var muted: bool = (not master) and m.st.size() > ch and m.st[ch] > 0.5
				ci.draw_rect(Rect2(cap2.position + Vector2(0, 1.5), cap2.size),
					Color(0, 0, 0, 0.5))
				ci.draw_rect(cap2, Color("#8a9098") if muted
					else (Color("#e6f0ff") if master else acc))
				ci.draw_line(cap2.position + Vector2(0, cap2.size.y * 0.5),
					cap2.position + Vector2(cap2.size.x, cap2.size.y * 0.5),
					Color(0, 0, 0, 0.45), 1.0)
				# --- the meter, hard against the fader
				if not master:
					var mv: float = clampf(m.s[8 + ch] if m.s.size() > 8 + ch else 0.0,
						0.0, 1.0)
					var mr2 := Rect2(Vector2(fr.end.x - 2.5 * s, fr.position.y + 3.0),
						Vector2(2.0 * s, fr.size.y - 6.0))
					ci.draw_rect(mr2, Color(0, 0, 0, 0.5))
					ci.draw_rect(Rect2(Vector2(mr2.position.x,
						mr2.end.y - mr2.size.y * mv), Vector2(mr2.size.x, mr2.size.y * mv)),
						Color("#3aff6a").lerp(Color("#ff5964"),
							clampf(mv * 1.4 - 0.4, 0.0, 1.0)))
				# --- mute, at the bottom
				var mb := Rect2(Vector2(body.position.x + 2.0, body.end.y - muteh),
					Vector2(body.size.x - 4.0, muteh - 2.0))
				if master:
					if s > 2.4:
						ci.draw_string(f, mb.position + Vector2(1.0, mb.size.y * 0.85),
							"MAIN", HORIZONTAL_ALIGNMENT_LEFT, mb.size.x,
							maxi(5, int(s * 2.8)), Color(st["text"]) * Color(1, 1, 1, 0.7))
				else:
					ci.draw_rect(mb, Color("#ff5964") if muted else Color(0, 0, 0, 0.5))
					ci.draw_rect(mb, Color(st["ring"]) * Color(1, 1, 1, 0.5), false, 1.0)
					if s > 2.4:
						ci.draw_string(f, mb.position + Vector2(1.5, mb.size.y * 0.82),
							str(ch + 1), HORIZONTAL_ALIGNMENT_LEFT, mb.size.x,
							maxi(5, int(s * 3.0)),
							Color("#0b0d12") if muted else Color(st["text"]))
		"vkeys":
			# an actual keyboard, stood on its end: whites running up the
			# panel, blacks short and down the LEFT, each one cut in
			# where it belongs between two whites
			var whitesV := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
			var noteV: float = m.st[0] if m.st.size() > 0 else -1.0
			var heldV: bool = m.st.size() > 1 and m.st[1] > 0.5
			var kh := r.size.y / float(whitesV.size())
			# the felt strip the keys are bedded into
			ci.draw_rect(Rect2(r.position - Vector2(0, 1.0),
				Vector2(r.size.x, r.size.y + 2.0)), Color("#141013"))
			for i in whitesV.size():
				var y0v := r.position.y + r.size.y - kh * float(i + 1)
				var kr3 := Rect2(Vector2(r.position.x + 1.0, y0v + 0.6),
					Vector2(r.size.x - 2.0, kh - 1.2))
				var onV: bool = heldV and int(noteV) == int(whitesV[i])
				var face: Color = acc.lerp(Color("#ffffff"), 0.35) if onV \
					else Color("#f2f4f7")
				ci.draw_rect(kr3, face)
				# ivory: a lit top edge, a shadow at the bottom, and the
				# key pushed a hair right when it is down
				ci.draw_line(kr3.position, kr3.position + Vector2(kr3.size.x, 0),
					Color(1, 1, 1, 0.9), maxf(1.0, s * 0.4))
				ci.draw_line(kr3.position + Vector2(0, kr3.size.y), kr3.end,
					Color(0, 0, 0, 0.35), maxf(1.0, s * 0.5))
				ci.draw_rect(Rect2(kr3.position + Vector2(kr3.size.x - 2.0 * s, 0),
					Vector2(2.0 * s, kr3.size.y)), Color(0, 0, 0, 0.10))
				if onV:
					ci.draw_rect(kr3, Color(0, 0, 0, 0.18), false, maxf(1.0, s * 0.6))
				if int(whitesV[i]) % 12 == 0 and s > 2.6:
					ci.draw_string(f, Vector2(kr3.end.x - 6.0 * s,
						kr3.position.y + kr3.size.y * 0.8),
						"C", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(5, int(s * 3.0)),
						Color(0, 0, 0, 0.35))
			for i in whitesV.size() - 1:
				var semiV: int = whitesV[i]
				if not (semiV % 12 in [0, 2, 5, 7, 9]):
					continue
				# the black key straddles the join between two whites
				var yb := r.position.y + r.size.y - kh * float(i + 1)
				var bkr := Rect2(Vector2(r.position.x + 1.0, yb - kh * 0.32),
					Vector2(r.size.x * 0.56, kh * 0.64))
				var onB: bool = heldV and int(noteV) == semiV + 1
				ci.draw_rect(Rect2(bkr.position + Vector2(0, 1.5), bkr.size),
					Color(0, 0, 0, 0.45))
				ci.draw_rect(bkr, acc.darkened(0.45) if onB else Color("#171a20"))
				ci.draw_line(bkr.position, bkr.position + Vector2(bkr.size.x, 0),
					Color(1, 1, 1, 0.16), 1.0)
				ci.draw_rect(Rect2(bkr.position + Vector2(bkr.size.x - 1.5 * s, 0),
					Vector2(1.5 * s, bkr.size.y)), Color(1, 1, 1, 0.06))
		"keys":
			var whites := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
			var note: float = m.st[0] if m.st.size() > 0 else -1.0
			var held: bool = m.st.size() > 1 and m.st[1] > 0.5
			var kw := r.size.x / float(whites.size())
			for i in whites.size():
				var kr2 := Rect2(r.position + Vector2(kw * float(i) + 0.5, 0.5),
					Vector2(kw - 1.0, r.size.y - 1.0))
				var on3: bool = held and int(note) == int(whites[i])
				ci.draw_rect(kr2, acc if on3 else Color("#e8ecf2"))
				ci.draw_rect(kr2, Color(0, 0, 0, 0.6), false, 1.0)
			for i in whites.size():
				var semi: int = whites[i]
				if semi % 12 in [0, 2, 5, 7, 9]:
					var bk := Rect2(r.position + Vector2(kw * float(i + 1) - kw * 0.3, 0.5),
						Vector2(kw * 0.6, r.size.y * 0.62))
					var on4: bool = held and int(note) == semi + 1
					ci.draw_rect(bk, acc.darkened(0.3) if on4 else Color("#14171c"))
		"meter":
			var lv: float = clampf(m.led, 0.0, 1.0)
			for ch in 2:
				var br := Rect2(r.position + Vector2(2.0, 2.0 + float(ch) * (r.size.y * 0.5)),
					Vector2((r.size.x - 4.0) * lv, r.size.y * 0.5 - 3.0))
				ci.draw_rect(Rect2(r.position + Vector2(2.0, br.position.y - r.position.y),
					Vector2(r.size.x - 4.0, br.size.y)), Color(0, 0, 0, 0.5))
				ci.draw_rect(br, Color("#3aff6a").lerp(Color("#ff5964"), clampf(lv * 1.3 - 0.3, 0.0, 1.0)))
			var lsz2: int = maxi(5, int(s * 2.8))
			ci.draw_string(f, r.position + Vector2(2.0, r.size.y + 3.0 * s), "OUT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, lsz2, Color(st["text"]) * Color(1, 1, 1, 0.7))
		_:
			if not undrawn.has(wg):
				undrawn[wg] = true

## A patch cable: real cables SAG, and you can tell them apart.
static func draw_cable(ci: CanvasItem, a: Vector2, b: Vector2, col: Color,
		thick: float = 3.0, sag: float = 0.32) -> void:
	# a busy rack vanishes under its own cabling: the player decides how
	# solid these are, and the setting follows them between worlds
	var ca: float = clampf(Settings.cable_alpha, 0.12, 1.0)
	col = Color(col.r, col.g, col.b, col.a * ca)
	var pts := PackedVector2Array()
	var dist := a.distance_to(b)
	var droop := minf(dist * sag, 110.0) + 8.0
	for i in 15:
		var t := float(i) / 14.0
		var p := a.lerp(b, t)
		p.y += sin(PI * t) * droop
		pts.append(p)
	ci.draw_polyline(pts, Color(0, 0, 0, 0.5 * ca), thick + 2.0)
	ci.draw_polyline(pts, col, thick)
	ci.draw_polyline(PackedVector2Array([pts[1], pts[3]]),
		Color(col.lightened(0.45), col.a), thick * 0.6)
	for p2 in [a, b]:
		# the plugs stay readable even when the cable is a ghost
		ci.draw_circle(p2, thick * 1.5, Color(col.darkened(0.45),
			minf(1.0, col.a + 0.35)))
		ci.draw_circle(p2, thick * 0.8, Color(col.lightened(0.3),
			minf(1.0, col.a + 0.35)))
