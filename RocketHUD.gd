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
	visible = Game.mode == Game.Mode.IN_ROCKET and not Game.trapped
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

		# readouts
		var alt := rocket.global_position.distance_to(body.center) - body.radius
		var lines := [
			"SPD  %6.1f m/s" % rocket.vel.length(),
			"ALT  %8.0f  (%s)" % [alt, body.name],
			"FUEL %6.1f / %.0f" % [Inventory.fuel, Inventory.fuel_max],
			"RCS  ON",
		]
		var y := c.y - rn - 10.0
		for i in lines.size():
			draw_string(font, Vector2(c.x + rn + 24, y + float(i) * 22.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

		# fuel bar
		var bw := 220.0
		var bx := c.x - rn - 24 - bw
		var by := c.y - rn
		draw_rect(Rect2(bx, by, bw, 16), Color(0, 0, 0, 0.5))
		var f := clampf(Inventory.fuel / maxf(1.0, Inventory.fuel_max), 0, 1)
		draw_rect(Rect2(bx + 2, by + 2, (bw - 4) * f, 12), Color("#ffd166"))

	func _marker(c: Vector2, rn: float, right: Vector3, up: Vector3, fwd: Vector3, dir: Vector3, col: Color, tag: String) -> void:
		if dir.length() < 0.001:
			return
		if dir.dot(fwd) <= 0.0:
			return   # behind the navball -> don't draw
		var sp := c + Vector2(dir.dot(right), -dir.dot(up)) * rn
		draw_circle(sp, 6.0, col)
		draw_string(ThemeDB.fallback_font, sp + Vector2(7, 4), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
