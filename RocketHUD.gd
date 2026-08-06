class_name RocketHUD
extends CanvasLayer
## Flight instruments, shown only while piloting: a navball at bottom
## centre (attitude + prograde/retro/radial markers) plus speed,
## altitude and fuel readouts.

var _rocket: Rocket
var _view: _NavView

func _ready() -> void:
	layer = 12
	visible = false
	_view = _NavView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE   # don't eat mouse/keys
	add_child(_view)

func set_rocket(r: Rocket) -> void:
	_rocket = r
	_view.rocket = r

func _process(_delta: float) -> void:
	visible = Game.mode == Game.Mode.IN_ROCKET and not Game.trapped \
		and not Game.hud_hidden
	if visible:
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and r.piloted:
				_view.rocket = r
				break
		_view.queue_redraw()

class _NavView extends Control:
	var rocket: Rocket

	func _draw() -> void:
		if rocket == null or not is_instance_valid(rocket):
			return
		var font := ThemeDB.fallback_font
		var vp := get_viewport_rect().size
		var rn := 90.0
		var c := Vector2(vp.x * 0.5, vp.y - rn - 30.0)

		var b := rocket.global_transform.basis
		var right := b.x
		var cup := b.y
		var fwd := -b.z
		var body := Universe.nearest(rocket.global_position)
		var pu := (rocket.global_position - body.center).normalized()   # planet up

		# ball orientation from planet-up
		var ball_up := Vector2(pu.dot(right), pu.dot(cup))
		if ball_up.length() < 0.001:
			ball_up = Vector2(0, 1)
		ball_up = ball_up.normalized()
		var pitch_dot := pu.dot(fwd)
		var offset := -pitch_dot * rn

		# split circle into sky / ground segments about the horizon line
		var sky := PackedVector2Array()
		var ground := PackedVector2Array()
		var steps := 48
		for i in steps + 1:
			var a := TAU * float(i) / float(steps)
			var pt := Vector2(cos(a), sin(a)) * rn
			var d := pt.dot(ball_up) - offset
			if d >= 0.0:
				sky.append(c + pt)
			else:
				ground.append(c + pt)
		if sky.size() >= 3:
			draw_colored_polygon(sky, Color("#12233f"))
		if ground.size() >= 3:
			draw_colored_polygon(ground, body.color.darkened(0.2))
		draw_arc(c, rn, 0, TAU, 48, Color.WHITE, 2.0)

		# markers
		_marker(c, rn, right, cup, fwd, rocket.vel.normalized(), Color("#4dff88"), "P")     # prograde
		_marker(c, rn, right, cup, fwd, -rocket.vel.normalized(), Color("#ff5566"), "R")    # retrograde
		_marker(c, rn, right, cup, fwd, pu, Color("#7cc8ff"), "^")                          # radial out
		# nose reticle
		draw_arc(c, 6.0, 0, TAU, 12, Color("#ffe066"), 2.0)
		draw_line(c - Vector2(12, 0), c - Vector2(6, 0), Color("#ffe066"), 2.0)
		draw_line(c + Vector2(6, 0), c + Vector2(12, 0), Color("#ffe066"), 2.0)

		# readouts (the 2.0 carries a double-size tank)
		var cap := Inventory.fuel_max * (2.0 if rocket.mk2 else 1.0)
		var alt := rocket.global_position.distance_to(body.center) - body.radius
		var lines := [
			"SPD  %6.1f m/s" % rocket.vel.length(),
			"ALT  %8.0f  (%s)" % [alt, body.name],
			"FUEL %6.1f / %.0f" % [Inventory.fuel, cap],
			"RCS  ON",
		]
		if rocket.hyperdrive:
			lines.append("HYPR %5.1f / %.0f ultima" % [rocket.hyper_charge,
				rocket.HYPER_MAX] if rocket.hyper_charge > 0.0
				or Inventory.res_count("ultima") > 0
				else "HYPR INACTIVE -- no ultima")
		var y := c.y - rn - 10.0
		for i in lines.size():
			draw_string(font, Vector2(c.x + rn + 24, y + float(i) * 22.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

		# --- time warp chips: keys 1-9 = 1-9x, 0 = 10x. active one lit. ---
		var tw := int(round(Game.timewarp))
		var chip_w := 36.0
		var total_w := chip_w * 10.0 + 9.0 * 4.0
		var tx := vp.x * 0.5 - total_w * 0.5
		var ty := 30.0
		draw_string(font, Vector2(tx, ty - 8),
			"TIME WARP   1-9 keys · 0 = 10x · double-tap 0 = 20x · coasting only",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
		# OVERDRIVE chip: lives past the 10x chip, lit only at 20x
		var orect := Rect2(tx + 10.0 * (chip_w + 4.0) + 8.0, ty, chip_w + 10.0, 26.0)
		var od := tw >= 20
		draw_rect(orect, Color("#ff8a2a") if od else Color(0, 0, 0, 0.45))
		if not od:
			draw_rect(orect, Color(1, 0.7, 0.3, 0.25), false, 1.0)
		draw_string(font, Vector2(orect.position.x, orect.position.y + 19.0),
			"20x", HORIZONTAL_ALIGNMENT_CENTER, orect.size.x, 15,
			Color(0.1, 0.05, 0, 1) if od else Color(1, 0.75, 0.4, 0.6))
		for i in 10:
			var val := i + 1
			var r := Rect2(tx + float(i) * (chip_w + 4.0), ty, chip_w, 26.0)
			var active := tw == val
			draw_rect(r, Color("#ffd166") if active else Color(0, 0, 0, 0.45))
			if not active:
				draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)
			draw_string(font, Vector2(r.position.x, r.position.y + 19.0), "%dx" % val,
				HORIZONTAL_ALIGNMENT_CENTER, chip_w,
				15, Color(0.1, 0.08, 0, 1) if active else Color(1, 1, 1, 0.7))

		# fuel bar
		var bw := 220.0
		var bx := c.x - rn - 24 - bw
		var by := c.y - rn
		draw_rect(Rect2(bx, by, bw, 16), Color(0, 0, 0, 0.5))
		var f := clampf(Inventory.fuel / maxf(1.0, cap), 0, 1)
		draw_rect(Rect2(bx + 2, by + 2, (bw - 4) * f, 12), Color("#ffd166"))

		# tutorial: colour-keyed legend explaining every instrument
		if Game.tutorial_session:
			var hl := [
				["#ffe066", "yellow ring = your NOSE -- thrust pushes this way"],
				["#4dff88", "P = prograde: the direction you are drifting"],
				["#ff5566", "R = retrograde: burn toward it to brake"],
				["#7cc8ff", "^ = straight up, away from the planet"],
				["#ffd166", "left bar = rocket fuel -- empty means stranded"],
				["#ffffff", "SPD / ALT = speed + height over the nearest world"],
			]
			var lx := bx
			var ly := by - 40.0 - float(hl.size()) * 24.0
			draw_string(font, Vector2(lx, ly - 8), "INSTRUMENTS",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#aaffc0"))
			for i in hl.size():
				draw_string(font, Vector2(lx, ly + 18 + float(i) * 24.0), str(hl[i][1]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(str(hl[i][0])))

	func _marker(c: Vector2, rn: float, right: Vector3, up: Vector3, fwd: Vector3, dir: Vector3, col: Color, tag: String) -> void:
		if dir.length() < 0.001:
			return
		if dir.dot(fwd) <= 0.0:
			return   # behind the navball -> don't draw
		var sp := c + Vector2(dir.dot(right), -dir.dot(up)) * rn
		draw_circle(sp, 6.0, col)
		draw_string(ThemeDB.fallback_font, sp + Vector2(7, 4), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
