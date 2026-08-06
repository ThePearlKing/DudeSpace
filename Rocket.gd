class_name Rocket
extends Node3D
## Newtonian spacecraft. Real summed gravity + thrust along the nose,
## fuel-gated. Optional RCS gives lateral translation + fast attitude.
## Draws a forward-integrated trajectory prediction each frame.

const MAIN_THRUST := 16.0     # ~TWR 3 on Home: real liftoff, still responsive
const MAIN_BURN := 4.0
const RCS_THRUST := 10.0
const RCS_BURN := 1.5
const ROT_SLOW := 2.2
const ROT_FAST := 4.2
const MOUSE_SENS := 0.0030
const SMASH_RADIUS := 7.0

var vel: Vector3 = Vector3.ZERO
var piloted: bool = false
var landed: bool = false
var arcade: bool = false      # alien starship mode: unrealistic + angers gods
var hyperdrive: bool = false  # installed on THIS ship (right-click the item nearby)
var nuclear: bool = false     # NUCLEAR ENGINE: mk2-only. Hotter, thriftier,
                              # and strong enough to win against the white zone
var force_locked: bool = false  # a cutscene owns the ship: player input dies
var edge_won: bool = false      # this ship has beaten the white zone's edge
var _cine_shake := 0.0          # cutscene camera violence
var _cine_fov := 0.0
# the hyperdrive drinks ULTIMA, not rocket fuel: a shipboard charge
# measured in crystals. Empty tank = the drive is a paperweight until
# you feed it (holding H auto-loads crystals from your inventory).
const HYPER_MAX := 8.0
var hyper_charge: float = 4.0   # crafted ships ship HALF full
var _hyper_warn_t := 0.0
var mk2: bool = false         # Rocket 2.0: double tank, sips fuel, seats a friend

var _player: Player
var _cam: Camera3D
var _cam_pivot: Node3D
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.25
var _cam_dist: float = 14.0
const CAM_SENS := 0.005
var _smash_area: Area3D
var _traj: MeshInstance3D
var _traj_mesh: ImmediateMesh
var _traj_mat: StandardMaterial3D
var _look: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _engine_on: bool = false
var _f_held: bool = false
var _traj_t: float = 0.0
var _fuel_last: float = -1.0
var _cam_up_s := Vector3.UP   # smoothed camera reference (no SOI snap)

func _ready() -> void:
	add_to_group("rocket")
	_build_body()

	# free-orbit camera: a world-space pivot at the ship that the mouse
	# rotates, so the view does NOT spin with the ship's attitude.
	_cam_pivot = Node3D.new()
	_cam_pivot.top_level = true
	add_child(_cam_pivot)
	_cam = Camera3D.new()
	_cam.far = 420000.0
	_cam.cull_mask = 0xFFFFF & ~(1 << 9)
	_cam.position = Vector3(0, 2.5, 14.0)   # behind + above, looks toward ship (-Z)
	_cam_pivot.add_child(_cam)

	_smash_area = Area3D.new()
	_smash_area.monitoring = false   # parked rockets don't scan for overlaps
	var sc := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = SMASH_RADIUS
	sc.shape = sph
	sc.position = Vector3(0, 0, -6.0)
	_smash_area.add_child(sc)
	add_child(_smash_area)

	set_physics_process(false)

## Shootable hull: breaking a PARKED rocket refunds the item.
## Takes 3 hits -- no more one-tap losing your ride.
class _Hull extends StaticBody3D:
	var rocket: Rocket
	func destroy(push_dir: Vector3) -> void:
		if rocket and is_instance_valid(rocket):
			rocket.dismantle(push_dir)

var _hull_hp: int = 3

func dismantle(push_dir: Vector3) -> void:
	if piloted:
		return
	if not Net.can_break(str(get_meta("owner", ""))):
		Sfx.play("denied")
		return
	_hull_hp -= 1
	if _hull_hp > 0:
		Sfx.play("hurt", -8.0)
		return
	Net.broadcast_remove(global_position)
	Inventory.give("rocket2" if mk2 else "rocket", 1)
	if hyperdrive:
		Inventory.hyper_rockets += 1   # the drive stays IN the rocket's bones
	# a waypoint riding the hull comes back too
	for w in get_children():
		if w is Waypoint:
			Inventory.give("waypoint", 1)
	Destructible.spawn_debris(get_parent(), global_position, Vector3(1.6, 3.0, 1.6), Color("#d8d8e0"), push_dir)
	Sfx.play("explode", -10.0)
	queue_free()

func _build_body() -> void:
	var hull := _Hull.new()
	hull.rocket = self
	var hc := CollisionShape3D.new()
	var hcs := CapsuleShape3D.new()
	hcs.radius = 1.2
	hcs.height = 7.0
	hc.shape = hcs
	hc.rotation_degrees = Vector3(-90, 0, 0)
	hull.add_child(hc)
	add_child(hull)
	var hull_col := Color("#eef6ff") if mk2 else Color("#d8d8e0")
	var fin_col := Color("#7df9ff") if mk2 else Color("#4cc9f0")
	_add_mesh(_capsule(1.0, 5.6 if mk2 else 5.0, hull_col, 0.25), Vector3.ZERO, Vector3(-90, 0, 0))
	_add_mesh(_cone(1.0, 2.0, Color("#ff5964"), 0.3), Vector3(0, 0, -3.7 if mk2 else -3.4), Vector3(-90, 0, 0))
	for a in [0.0, 120.0, 240.0]:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.2, 1.4, 1.6)
		var mi := MeshInstance3D.new()
		mi.mesh = fin
		mi.material_override = Destructible.make_material(fin_col, 0.3)
		mi.position = Vector3(0, 0, 2.0).rotated(Vector3.FORWARD, deg_to_rad(a))
		mi.position += Vector3(sin(deg_to_rad(a)), cos(deg_to_rad(a)), 0) * 1.0
		add_child(mi)
	if mk2:
		# the 2.0 wears its upgrades: twin drop tanks + a passenger bubble
		for sx in [-1.0, 1.0]:
			_add_mesh(_capsule(0.42, 2.6, Color("#9fb8c8"), 0.2),
				Vector3(sx * 1.35, -0.2, 0.8), Vector3(-90, 0, 0))
		var bubble := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.55
		bm.height = 1.1
		bubble.mesh = bm
		bubble.position = Vector3(0, 0.95, -0.6)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(0.5, 0.95, 1.0, 0.35)
		glass.emission_enabled = true
		glass.emission = Color("#7df9ff")
		glass.emission_energy_multiplier = 0.4
		bubble.material_override = glass
		add_child(bubble)
	# engine glow
	_add_mesh(_capsule(0.4, 0.6, Color("#ffd166"), 4.0), Vector3(0, 0, 2.6), Vector3(-90, 0, 0))

func _capsule(r: float, h: float, c: Color, e: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	var mi_mat := Destructible.make_material(c, e)
	m.material = mi_mat
	return m

func _cone(r: float, h: float, c: Color, e: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.material = Destructible.make_material(c, e)
	return m

func _add_mesh(m: Mesh, pos: Vector3, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)

# ------------------------------------------------------------- boarding

func board(p: Player) -> void:
	# lifting off: the parked mirror on other machines comes with us
	Net.broadcast_remove(global_position)
	_player = p
	piloted = true
	_f_held = true   # swallow the same F press that boarded us
	Game.mode = Game.Mode.IN_ROCKET
	_smash_area.monitoring = true
	p.enter_vehicle()
	_cam.current = true
	_cam_up_s = (global_position - Universe.nearest(global_position).center).normalized()
	_ensure_traj()
	set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.changed.emit()

func _try_exit() -> void:
	var body := Universe.nearest(global_position)
	var up := (global_position - body.center).normalized()
	piloted = false
	set_physics_process(false)
	_smash_area.monitoring = false
	_cam.current = false
	Game.timewarp = 1.0
	_overdrive_until = 0.0
	Game.board_lock = Game.playtime + 0.5   # no instant re-board
	Sfx.engine(false)
	Sfx.alien_engine(false)
	if _traj:
		_traj.visible = false
	# parked again: everyone gets it back exactly where it landed
	Net.broadcast_place("rocket2" if mk2 else "rocket", global_position,
		-global_transform.basis.z)
	Game.mode = Game.Mode.ON_FOOT
	if is_instance_valid(_player):
		# hop out BESIDE the hull (clear of its collider), works in space too
		var side := global_transform.basis.x
		side = (side - up * side.dot(up))
		if side.length() < 0.1:
			side = global_transform.basis.y
		_player.exit_vehicle(global_position + side.normalized() * 3.0 + up * 1.5, up)
	Game.changed.emit()

# -------------------------------------------------------------- physics

func _unhandled_input(event: InputEvent) -> void:
	if not piloted:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and get_window().has_focus():
		_look += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(6.0, _cam_dist / 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(600.0, _cam_dist * 1.15)   # zoom WAY out
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == Settings.key("interact"):
			_try_exit()
			get_viewport().set_input_as_handled()   # or the player re-boards SAME press
			return
		# time warp: 1-9 = 1x-9x, 0 = 10x. NEVER while the engine burns.
		# DOUBLE-TAP 0: a 20x OVERDRIVE burst for 10s, then back to 10x.
		# Any warp key still works during the burst (including stopping).
		# 90s cooldown between bursts, interrupted or not.
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			if _engine_on:
				Sfx.play("denied")
				return
			var n: int = event.keycode - KEY_0
			# REAL milliseconds: playtime runs 10x fast after the first
			# tap, which crushed the double-tap window to 0.04s -- the
			# whole overdrive clock lives on wall time now
			var nowms := float(Time.get_ticks_msec())
			if n == 0 and nowms - _warp_tap_t < 400.0:
				if nowms >= _overdrive_cd:
					_overdrive_until = nowms + 10000.0
					# a fitted hyperdrive cools the warp coils too:
					# twenty-second cooldown instead of ninety
					_overdrive_cd = nowms \
						+ (20000.0 if hyperdrive else 90000.0)
					Game.timewarp = 20.0
					Sfx.play("warp", -10.0)
				else:
					Sfx.play("denied", -14.0)
			else:
				_overdrive_until = 0.0   # picking any warp cancels the burst
				Game.timewarp = 10.0 if n == 0 else float(n)
			_warp_tap_t = float(Time.get_ticks_msec()) if n == 0 else -1e9

var _warp_tap_t := -1e9       # last 0-tap, REAL ms (double-tap window)
var _overdrive_until := 0.0   # 20x burst active until this REAL ms
var _overdrive_cd := 0.0      # next burst allowed at this REAL ms

func _physics_process(delta: float) -> void:
	if not piloted or Game.dead:
		return
	_cam.fov = Settings.fov + _cine_fov
	var ui := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or force_locked

	# F to hop out. Polled unconditionally -- exiting must ALWAYS work
	# (except while a cutscene owns the ship).
	if Input.is_key_pressed(Settings.key("interact")) and not force_locked:
		if not _f_held:
			_f_held = true
			_try_exit()
			return
	else:
		_f_held = false

	# --- attitude: CAMERA-relative, so it always does what it looks like.
	# W = nose up on screen. S = down. A = left. D = right.
	var rot_rate := ROT_FAST
	if not ui:
		var r := rot_rate * delta
		var cb := _cam_pivot.global_transform.basis
		if Input.is_key_pressed(KEY_W):
			global_transform.basis = Basis(cb.x, r) * global_transform.basis
		if Input.is_key_pressed(KEY_S):
			global_transform.basis = Basis(cb.x, -r) * global_transform.basis
		if Input.is_key_pressed(KEY_A):
			global_transform.basis = Basis(cb.y, r) * global_transform.basis
		if Input.is_key_pressed(KEY_D):
			global_transform.basis = Basis(cb.y, -r) * global_transform.basis
		global_transform.basis = global_transform.basis.orthonormalized()
	# free-orbit camera driven by the mouse, independent of ship attitude
	if not ui:
		_cam_yaw -= _look.x * CAM_SENS
		_cam_pitch = clampf(_cam_pitch - _look.y * CAM_SENS, -1.35, 1.35)
	_look = Vector2.ZERO
	# KSP-style orbit camera: anchored to LOCAL UP (radial from the nearest
	# planet), NOT the ship's facing. The rocket tumbles freely in view; the
	# camera stays level with the world.
	# SMOOTHED reference up: crossing into another planet's influence
	# used to flip this vector instantly -- and with it the camera
	# frame, INVERTING the controls mid-flight. Now it eases over.
	var cam_up_raw := (global_position - Universe.nearest(global_position).center).normalized()
	_cam_up_s = _cam_up_s.slerp(cam_up_raw, minf(1.0, delta * 2.0)).normalized()
	var cam_up := _cam_up_s
	var ct := Vector3(0, 1, 0)
	if absf(cam_up.dot(ct)) > 0.99:
		ct = Vector3(1, 0, 0)
	var cx := ct.cross(cam_up).normalized()
	var cz := cx.cross(cam_up).normalized()
	var ref := Basis(cx, cam_up, cz)
	_cam_pivot.global_position = global_position
	_cam_pivot.global_transform.basis = (ref
		* Basis(Vector3.UP, _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch)).orthonormalized()
	_cam.position = Vector3(0, _cam_dist * 0.18, _cam_dist)
	if _cine_shake > 0.001:
		_cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1),
			randf_range(-0.3, 0.3)) * _cine_shake

	var fwd := -global_transform.basis.z
	_engine_on = false

	# --- main engine: Space (Mk2 upgrade = +60% thrust; the NUCLEAR
	# ENGINE stacks another +45% and burns half again cooler) ---
	var thrust := MAIN_THRUST * (1.6 if Inventory.engine_mk2 else 1.0) \
		* (1.45 if nuclear else 1.0)
	var burn_eff := 0.5 if mk2 else 1.0   # 2.0 sips where the 1.0 gulps
	if nuclear:
		burn_eff *= 0.6
	if not ui and Input.is_key_pressed(KEY_SPACE) and Inventory.fuel > 0.0:
		vel += fwd * thrust * delta
		Inventory.fuel = maxf(0.0, Inventory.fuel - MAIN_BURN * burn_eff * delta)
		_engine_on = true

	# --- hyperdrive: hold H, screams toward the nose. Ship-mounted,
	# ULTIMA-fueled: ~14 seconds a crystal, auto-loading from your
	# inventory as the charge runs dry. Faster and far thriftier on
	# rocket fuel than it used to be.
	_hyper_warn_t = maxf(0.0, _hyper_warn_t - delta)
	if hyperdrive and not ui and Input.is_key_pressed(Settings.key("hyper")) \
			and Inventory.fuel > 0.5:
		if not Game.inf_fuel and hyper_charge <= 0.0 \
				and Inventory.res_count("ultima") > 0:
			Inventory.remove_res("ultima", 1)
			hyper_charge += 1.0
			Sfx.play("smelt", -14.0)
		if hyper_charge > 0.0 or Game.inf_fuel:
			if not Game.inf_fuel:
				hyper_charge = maxf(0.0, hyper_charge - delta / 14.0)
			vel = vel.lerp(fwd * 1400.0, delta * 1.6)
			Inventory.fuel = maxf(0.0, Inventory.fuel - 4.0 * burn_eff * delta)
			_engine_on = true
		elif _hyper_warn_t <= 0.0:
			_hyper_warn_t = 2.5
			Sfx.play("denied", -16.0)
			var hudh = get_tree().get_first_node_in_group("hud")
			if hudh:
				hudh.flash("HYPERDRIVE INACTIVE -- no ultima aboard")

	# --- RCS translation (standard): arrows + Shift/Ctrl fore/aft ---
	if not ui and Inventory.fuel > 0.0:
		var t := Vector3.ZERO
		if Input.is_key_pressed(KEY_LEFT): t -= global_transform.basis.x
		if Input.is_key_pressed(KEY_RIGHT): t += global_transform.basis.x
		if Input.is_key_pressed(KEY_UP): t += global_transform.basis.y
		if Input.is_key_pressed(KEY_DOWN): t -= global_transform.basis.y
		if Input.is_key_pressed(KEY_SHIFT): t += fwd
		if Input.is_key_pressed(KEY_CTRL): t -= fwd
		if t != Vector3.ZERO:
			vel += t.normalized() * RCS_THRUST * delta
			Inventory.fuel = maxf(0.0, Inventory.fuel - RCS_BURN * burn_eff * delta)

	# --- gravity + integrate (semi-implicit Euler) ---
	if not arcade:
		vel += Universe.gravity_at(global_position) * delta
	else:
		vel = vel.lerp(Vector3.ZERO, delta * 0.3)   # arcade drift damping
		Game.anger(1.2 * delta)                     # the gods HATE this ship
	global_position += vel * delta
	if _engine_on and Game.timewarp > 1.0:
		Game.timewarp = 1.0   # burning instantly kills time warp
		_overdrive_until = 0.0
	# overdrive burst expires back down to a plain 10x
	if _overdrive_until > 0.0 \
			and float(Time.get_ticks_msec()) >= _overdrive_until:
		_overdrive_until = 0.0
		if Game.timewarp > 10.0:
			Game.timewarp = 10.0
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash("TIME WARP ×1 — engine burn")
	if arcade:
		# saucer hum: always on while piloted, pitch rises under thrust
		Sfx.engine(false)
		Sfx.alien_engine(true, 1.4 if _engine_on else 0.9)
	else:
		Sfx.engine(_engine_on)

	# --- surface collision / landing (spheres AND the torus) ---
	# the rocket collides with what COLLIDES: an ocean's water has no
	# collider, so the ship sinks through and lands on the sand floor
	var body := Universe.nearest(global_position)
	var alt := Universe.altitude(body, global_position)
	if body.kind == "ocean":
		alt = global_position.distance_to(body.center) - body.radius * 0.625
	if alt < 1.0:
		var up := Universe.surface_up(body, global_position)
		global_position += up * (1.0 - alt)
		var into := vel.dot(-up)
		if into > 0.0:
			vel += up * into           # cancel inward velocity
		vel *= 0.5                      # scrub on contact
		landed = vel.length() < 9.0
	else:
		landed = false

	_cooldown -= delta
	if not ui and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cooldown <= 0.0:
		_smash()
		_cooldown = 0.14

	# UI refresh only when the fuel number actually moved -- emitting
	# every physics frame made the whole HUD rebuild 60x/s
	if absf(Inventory.fuel - _fuel_last) > 0.01:
		_fuel_last = Inventory.fuel
		Inventory.changed.emit()
	# trajectory: ~7 Hz is indistinguishable from every-frame and ~10x
	# cheaper; this line was the single laggiest thing in the game
	_traj_t -= delta
	if _traj_t <= 0.0:
		_traj_t = 0.15
		_update_trajectory()

func _smash() -> void:
	for b in _smash_area.get_overlapping_bodies():
		if b.is_in_group("destructible") and b.has_method("destroy"):
			b.destroy(b.global_position - global_position)

# ---------------------------------------------------------- trajectory

func _ensure_traj() -> void:
	if _traj:
		_traj.visible = true
		return
	_traj_mat = StandardMaterial3D.new()
	_traj_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_traj_mat.emission_enabled = true
	_traj_mat.emission = Color("#7cf9ff")
	_traj_mat.emission_energy_multiplier = 3.0
	_traj_mat.albedo_color = Color("#7cf9ff")
	_traj = MeshInstance3D.new()
	_traj_mesh = ImmediateMesh.new()
	_traj.mesh = _traj_mesh
	_traj.top_level = true          # world-space, ignore rocket transform
	add_child(_traj)

func _update_trajectory() -> void:
	if not _traj:
		return
	_traj_mesh.clear_surfaces()
	var pts := PackedVector3Array()
	var p := global_position
	var v := vel
	# fine steps near NOW (where you're flying), coarse steps for the far
	# future; crash checks every 3rd coarse step. Same drawn horizon for a
	# fraction of the body-loop work.
	var dt := 0.5
	for i in 420:
		if i == 120:
			dt = 1.5
		v += Universe.gravity_at(p) * dt
		p += v * dt
		pts.append(p)
		if i < 30 or i % 3 == 0:
			var nb := Universe.nearest(p)
			if p.distance_to(nb.center) < nb.radius + 0.5:
				break
		# came back around near the start -> that's an orbit, loop is drawn
		if i > 60 and p.distance_to(global_position) < maxf(8.0, vel.length() * dt):
			break
	# A LINE_STRIP needs >= 2 vertices; sitting on the ground can yield 1.
	if pts.size() < 2:
		return
	_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _traj_mat)
	for pt in pts:
		_traj_mesh.surface_add_vertex(pt)
	_traj_mesh.surface_end()

# --------------------------------------------------------------- helpers

func god_throwback(to: Vector3) -> void:
	global_position = to
	vel = vel.normalized() * minf(vel.length(), 20.0) * -1.0
