class_name MapUI
extends CanvasLayer
## Toggle with M. Top-down (XZ) universe map. Free mouse: wheel zooms,
## LEFT-DRAG pans around. SOI rings + live rocket trajectory.

var _view: Control
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO     # world-space XZ offset from YOU
var _dragging: bool = false
var _last_scale: float = 0.001

var select_cb: Callable = Callable()   # set = click-a-planet picker mode
var _traj_pts: Array = []              # cached trajectory (world points)
var _traj_ms: int = 0
var _press_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = 15
	visible = false
	add_to_group("closable_ui")
	add_to_group("map_ui")
	_view = _MapView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.owner_ui = self
	add_child(_view)

## Teleport browser hands us a callback; the next planet clicked wins.
func open_select(cb: Callable) -> void:
	select_cb = cb
	visible = true
	pan = Vector2.ZERO
	_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	Sfx.play("click", -14.0)

## Which body sits under this screen point? (same transform as _draw)
func body_at(screen: Vector2) -> Variant:
	var vp := get_viewport().get_visible_rect().size
	var c := vp * 0.5
	var p = get_tree().get_first_node_in_group("player")
	var me: Vector3 = p.global_position if p else Vector3.ZERO
	var origin := Vector3(me.x + pan.x, 0, me.z + pan.y)
	# nearest CENTRE wins -- so a small planet sitting inside a big one's
	# disc is still clickable by aiming at its dot
	var best = null
	var best_d := 1e9
	for b in Universe.bodies:
		var sp: Vector2 = c + Vector2(b.center.x - origin.x, b.center.z - origin.z) * _last_scale
		var d := sp.distance_to(screen)
		if d <= maxf(14.0, b.radius * _last_scale + 6.0) and d < best_d:
			best = b
			best_d = d
	return best

func close_ui() -> void:
	visible = false
	_dragging = false
	select_cb = Callable()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == Settings.key("map"):
		if Game.dead:
			return
		if visible:
			close_ui()
		else:
			visible = true
			pan = Vector2.ZERO
			_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED   # free mouse to drag
		Sfx.play("click", -14.0)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = minf(zoom * 1.25, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = maxf(zoom / 1.25, 0.3)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		# drag the world under the cursor
		pan.x -= event.relative.x / _last_scale
		pan.y -= event.relative.y / _last_scale

## Picker right-click rides _input, ahead of ANY control that might eat
## the event -- _unhandled_input provably never received it.
func _input(event: InputEvent) -> void:
	if not visible or not select_cb.is_valid():
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		var b = body_at(event.position)
		if b != null:
			var cb := select_cb
			close_ui()
			cb.call(b)
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if visible:
		_view.queue_redraw()

class _MapView extends Control:
	var owner_ui: MapUI

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var vp := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0.02, 0.9))
		draw_string(font, Vector2(30, 40),
			"MAP  ·  RIGHT-CLICK A PLANET TO WARP  ·  wheel zoom  ·  drag pan" \
			if owner_ui.select_cb.is_valid() \
			else "MAP  ·  wheel zoom  ·  drag pan  ·  M close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color("#7dff9a") if owner_ui.select_cb.is_valid() else Color.WHITE)

		var me := _active_pos()
		var c := vp * 0.5
		var scale := (minf(vp.x, vp.y) * 0.5 - 60.0) / 42000.0 * owner_ui.zoom
		owner_ui._last_scale = scale
		var origin := Vector3(me.x + owner_ui.pan.x, 0, me.z + owner_ui.pan.y)

		# solar system names floating over their clusters
		for sysspec in [["DUDE SYSTEM", Vector2(0, 900)],
				["SOL SYSTEM", Vector2(-52000, 14000)],
				["TRIS SYSTEM", Vector2(52000, -15000)],
				["SHADER SYSTEM", Vector2(0, -24800)]]:
			var syp: Vector2 = c + (Vector2(sysspec[1]) - Vector2(origin.x, origin.z)) * scale
			draw_string(font, syp + Vector2(-110, -46), str(sysspec[0]),
				HORIZONTAL_ALIGNMENT_CENTER, 220, 19, Color(1, 1, 1, 0.3))
		for b in Universe.bodies:
			var p: Vector3 = b.center
			var sp := c + Vector2(p.x - origin.x, p.z - origin.z) * scale
			var rad: float = maxf(2.0, b.radius * scale)
			var col: Color = b.color
			if b.kind == "blackhole":
				col = Color(0.1, 0.1, 0.12)
				# the accretion bands, same radii + colours as the real disk
				for rs in [[1.25, 1.7, Color("#fff2c0", 0.5)],
						[1.7, 2.3, Color("#ff9a1a", 0.4)],
						[2.3, 3.1, Color("#ff4d1a", 0.3)],
						[3.1, 4.2, Color("#7a1aff", 0.25)]]:
					var mid: float = (float(rs[0]) + float(rs[1])) * 0.5
					var wid: float = maxf(1.5, (float(rs[1]) - float(rs[0])) * b.radius * scale)
					draw_arc(sp, b.radius * mid * scale, 0, TAU, 48, rs[2], wid)
			draw_arc(sp, maxf(rad * 8.0, 8.0), 0, TAU, 40, Color(1, 1, 1, 0.10), 1.0)
			draw_circle(sp, rad, col)
			draw_arc(sp, maxf(rad, 3.0), 0, TAU, 24, Color.WHITE, 1.0)
			draw_string(font, sp + Vector2(rad + 4, 4), b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))

		# rocket trajectory prediction -- SIMULATED at 10Hz, drawn every
		# frame. 240 gravity integrations per draw was the map's laptop
		# tax; the path doesn't change faster than the rocket does.
		var rk: Rocket = null
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and r.piloted:
				rk = r
				break
		if rk:
			var now := Time.get_ticks_msec()
			if now - owner_ui._traj_ms > 100 or owner_ui._traj_pts.is_empty():
				owner_ui._traj_ms = now
				owner_ui._traj_pts.clear()
				var pp: Vector3 = rk.global_position
				var vv: Vector3 = rk.vel
				for i in 240:
					vv += Universe.gravity_at(pp) * 1.0
					pp += vv * 1.0
					owner_ui._traj_pts.append(pp)
					var nb = Universe.nearest(pp)
					if pp.distance_to(nb.center) < nb.radius:
						break
			var pts := PackedVector2Array()
			for wp in owner_ui._traj_pts:
				pts.append(c + Vector2((wp as Vector3).x - origin.x,
					(wp as Vector3).z - origin.z) * scale)
			if pts.size() >= 2:
				draw_polyline(pts, Color("#7cf9ff", 0.8), 1.5)

		# shadow temple landmark
		var stp := c + Vector2(Zones.SHADOW_POS.x - origin.x, Zones.SHADOW_POS.z - origin.z) * scale
		var dcol := Color("#b36bff")
		var dpts := PackedVector2Array([stp + Vector2(0, -7), stp + Vector2(7, 0), stp + Vector2(0, 7), stp + Vector2(-7, 0)])
		draw_colored_polygon(dpts, Color(0.25, 0.05, 0.4, 0.9))
		draw_polyline(PackedVector2Array([dpts[0], dpts[1], dpts[2], dpts[3], dpts[0]]), dcol, 1.5)
		draw_string(font, stp + Vector2(10, 4), "SHADOW TEMPLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dcol)

		# THE NOODLE GOD: a cosmic entity on the chart. it follows you, so
		# it's always out there in the same direction, pinned to the edge
		# of the map, enormous, with a distance reading nobody trusts.
		var nwd = get_tree().get_first_node_in_group("noodle_watcher")
		if nwd != null and nwd is Node3D:
			var gp: Vector3 = nwd.global_position
			var gsp := c + Vector2(gp.x - origin.x, gp.z - origin.z) * scale
			var margin := 80.0
			var pinned := gsp.clamp(Vector2(margin, margin), vp - Vector2(margin, margin))
			var gc := Color("#ffcf40")
			for k in 8:   # the tangle: a nest that dwarfs every planet dot
				draw_arc(pinned, 62.0 + float(k) * 13.0, float(k) * 1.1,
					float(k) * 1.1 + TAU * 0.62, 40,
					Color(1.0, 0.81, 0.25, 0.45 - float(k) * 0.045), 4.0)
			draw_circle(pinned, 50.0, Color(0.95, 0.9, 0.83, 0.92))   # the eye
			draw_circle(pinned, 22.0, Color(0.06, 0.04, 0.01))
			draw_arc(pinned, 34.0, 0, TAU, 40, Color("#c89020"), 5.0)
			draw_string(font, pinned + Vector2(-72, 150), "THE NOODLE GOD",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, gc)
			draw_string(font, pinned + Vector2(-52, 168),
				"≈ %.0f km  (?)" % (me.distance_to(gp) * 4.0 / 1000.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.8, 0.3, 0.7))

		var mp := c + Vector2(me.x - origin.x, me.z - origin.z) * scale
		draw_circle(mp, 5.0, Color("#ffe066"))
		draw_string(font, mp + Vector2(8, -6), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffe066"))

	func _active_pos() -> Vector3:
		var g := "rocket" if Game.mode == Game.Mode.IN_ROCKET else "player"
		for n in get_tree().get_nodes_in_group(g):
			if g != "rocket" or (n is Rocket and n.piloted):
				return n.global_position
		var f := get_tree().get_first_node_in_group("player")
		return f.global_position if f else Vector3.ZERO
