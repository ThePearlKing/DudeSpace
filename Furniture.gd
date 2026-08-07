class_name Furniture
extends StaticBody3D
## Furniture: bench, chair, sofa, carpet, bed. Placed by the Furniture
## Placer tool, usable by every human (and the player, F). A carpet is
## furniture with no ambitions. A bed is a seat you take lying down.

const KINDS := ["bench", "chair", "sofa", "carpet", "bed", "table", "catwalk", "doorframe"]

var kind: String = "bench"
var yaw: float = -1.0

func _ready() -> void:
	add_to_group("bench")   # rides the same save group as benches
	if yaw < 0.0:
		yaw = randf() * TAU
	var wood := Destructible.make_material(Color("#7a5a34"), 0.05)
	var dark := Destructible.make_material(Color("#3a3a3e"), 0.02)
	var cloth := Destructible.make_material(
		Color.from_hsv(randf(), randf_range(0.35, 0.6), randf_range(0.5, 0.8)), 0.06)
	var seats: Array = []
	match kind:
		"table":
			# a proper table: slab top, apron, four legs -- and a real
			# SURFACE: TVs and clutter can stand on it
			_m(Vector3(1.6, 0.09, 1.0), Vector3(0, 0.86, 0), wood)
			_m(Vector3(1.4, 0.12, 0.84), Vector3(0, 0.76, 0), dark)
			_legs(1.3, dark)
			_hitbox(Vector3(1.6, 0.95, 1.0), Vector3(0, 0.45, 0))
		"chair":
			_m(Vector3(0.6, 0.08, 0.55), Vector3(0, 0.55, 0), wood)
			_m(Vector3(0.6, 0.5, 0.08), Vector3(0, 0.85, 0.28), wood)
			_legs(0.6, dark)
			seats = [Vector3(0, 0.55, 0)]
			_hitbox(Vector3(0.7, 1.1, 0.7), Vector3(0, 0.55, 0))
		"sofa":
			_m(Vector3(2.2, 0.5, 0.8), Vector3(0, 0.35, 0), cloth)
			_m(Vector3(2.2, 0.6, 0.22), Vector3(0, 0.9, 0.32), cloth)
			for ax in [-1.05, 1.05]:
				_m(Vector3(0.22, 0.45, 0.8), Vector3(ax, 0.75, 0), cloth)
			seats = [Vector3(-0.65, 0.62, 0), Vector3(0, 0.62, 0), Vector3(0.65, 0.62, 0)]
			_hitbox(Vector3(2.4, 1.2, 0.9), Vector3(0, 0.6, 0))
		"carpet":
			# big, flat, and NO collision: a carpet you trip on is a rug
			# with a grudge
			_m(Vector3(4.2, 0.05, 3.0), Vector3(0, 0.03, 0), cloth)
			_m(Vector3(4.4, 0.04, 3.2), Vector3(0, 0.015, 0),
				Destructible.make_material(cloth.albedo_color.darkened(0.3), 0.03))
		"doorframe":
			# a doorway waiting for a door: jambs, lintel, and a faint
			# shimmer where the wall will stop existing. place it against
			# an interior wall; connect two of them with the Door tool
			# from OUTSIDE and the houses become one build.
			var jamb: Material = Surfaces.wood(Color("#5a4428"))
			for jx in [-0.95, 0.95]:
				_m(Vector3(0.18, 2.6, 0.18), Vector3(jx, 1.3, 0), jamb)
			_m(Vector3(2.1, 0.2, 0.2), Vector3(0, 2.7, 0), jamb)
			var shim := MeshInstance3D.new()
			var shm := BoxMesh.new()
			shm.size = Vector3(1.7, 2.5, 0.05)
			shim.mesh = shm
			shim.position = Vector3(0, 1.3, 0)
			shim.material_override = Surfaces.portal(Color("#8ab8ff"))
			shim.name = "shimmer"
			add_child(shim)
			# hitboxes on the JAMBS and lintel only: a doorframe you
			# can't walk through is a wall with delusions
			_hitbox(Vector3(0.2, 2.6, 0.2), Vector3(-0.95, 1.3, 0))
			_hitbox(Vector3(0.2, 2.6, 0.2), Vector3(0.95, 1.3, 0))
			_hitbox(Vector3(2.1, 0.2, 0.2), Vector3(0, 2.7, 0))
			# the shimmer is CLICKABLE: a ray-only pane (layer 2) fills the
			# opening so the door tool works aimed anywhere at the frame.
			# movement ignores layer 2; the pane leaves with the shimmer.
			var pane := StaticBody3D.new()
			pane.collision_layer = 2
			var pc := CollisionShape3D.new()
			var pcs := BoxShape3D.new()
			pcs.size = Vector3(1.7, 2.5, 0.1)
			pc.shape = pcs
			pc.position = Vector3(0, 1.3, 0)
			pane.add_child(pc)
			pane.name = "clickpane"
			add_child(pane)
			add_to_group("doorframe")
			set_meta("linked", false)
			# frames are ALWAYS square on their wall: snap after the world
			# finishes moving us (covers placement AND save-restore)
			call_deferred("_snap_wall")
		"catwalk":
			# industrial platform: legs, deck, rails. machines welcome
			# on top. house-interior use only, per the placer.
			var steel: Material = Surfaces.metal(Color("#6a6f78"))
			_m(Vector3(5.4, 0.22, 2.0), Vector3(0, 1.5, 0), steel)
			for lx2 in [-2.4, 0.0, 2.4]:
				for lz2 in [-0.8, 0.8]:
					_m(Vector3(0.14, 1.5, 0.14), Vector3(lx2, 0.75, lz2), steel)
			for rz3 in [-0.95, 0.95]:
				_m(Vector3(5.4, 0.07, 0.07), Vector3(0, 2.25, rz3), steel)
				for px2 in [-2.4, -0.8, 0.8, 2.4]:
					_m(Vector3(0.06, 0.6, 0.06), Vector3(px2, 1.95, rz3), steel)
			_hitbox(Vector3(5.4, 0.25, 2.0), Vector3(0, 1.5, 0))
			# ramp up one end so you can walk onto it
			var rmp := StaticBody3D.new()
			var rmc := CollisionShape3D.new()
			var rmb := BoxShape3D.new()
			rmb.size = Vector3(1.2, 0.1, 2.6)
			rmc.shape = rmb
			rmp.add_child(rmc)
			add_child(rmp)
			rmp.position = Vector3(3.2, 0.8, 0)
			rmp.rotation.z = atan2(1.6, 2.2)
		"bed":
			_m(Vector3(1.2, 0.35, 2.3), Vector3(0, 0.28, 0), wood)
			_m(Vector3(1.1, 0.16, 2.1), Vector3(0, 0.53, 0), cloth)
			_m(Vector3(1.0, 0.14, 0.5), Vector3(0, 0.65, -0.75),
				Destructible.make_material(Color("#e8e2d4"), 0.1))
			_m(Vector3(1.2, 0.7, 0.12), Vector3(0, 0.6, -1.15), wood)
			seats = [Vector3(0, 0.62, 0.2)]
			_hitbox(Vector3(1.3, 0.8, 2.4), Vector3(0, 0.4, 0))
		_:   # bench
			_m(Vector3(1.8, 0.08, 0.55), Vector3(0, 0.55, 0), wood)
			_m(Vector3(1.8, 0.5, 0.08), Vector3(0, 0.85, 0.28), wood)
			_legs(1.8, dark)
			seats = [Vector3(-0.45, 0.55, 0), Vector3(0.45, 0.55, 0)]
			_hitbox(Vector3(1.9, 1.1, 0.7), Vector3(0, 0.55, 0))
	for sp in seats:
		var s := Node3D.new()
		s.position = sp
		s.add_to_group("seat")
		s.set_meta("taken", false)
		add_child(s)
	rotate_object_local(Vector3.UP, yaw)

func _snap_wall() -> void:
	if kind != "doorframe" or not is_inside_tree() \
			or bool(get_meta("linked", false)):
		return
	var outv := Vector3.ZERO
	var hh = House.house_at(global_position)
	if hh != null:
		var rel: Vector3 = global_position - hh.room_center()
		outv = Vector3(signf(rel.x), 0, 0) if absf(rel.x) > absf(rel.z) \
			else Vector3(0, 0, signf(rel.z))
	else:
		# no owning room found (hallways, odd spots): RAYCAST for the
		# nearest wall and face it -- a frame is never allowed sideways
		var space := get_world_3d().direct_space_state
		var org := global_position + Vector3(0, 1.3, 0)
		var best_d := 6.0
		for dirv in [Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var q := PhysicsRayQueryParameters3D.create(org, org + dirv * 6.0)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit:
				var d: float = (hit.position - org).length()
				if d < best_d:
					best_d = d
					outv = dirv
	if outv != Vector3.ZERO:
		global_transform.basis = Basis(Vector3.UP, atan2(-outv.x, -outv.z))

func _m(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _legs(w: float, mat: Material) -> void:
	for lx in [-w * 0.45, w * 0.45]:
		for lz in [-0.22, 0.22]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.55, 0.07)
			mi.mesh = bm
			mi.position = Vector3(lx, 0.27, lz)
			mi.material_override = mat
			add_child(mi)

func _hitbox(size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = size
	col.shape = cs
	col.position = pos
	add_child(col)

## F: sit (or lie, we don't police it) on the nearest free spot.
func use() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("sit_on"):
		return
	var best: Node3D = null
	var bd := 1e9
	for c in get_children():
		if c is Node3D and c.is_in_group("seat") and not bool(c.get_meta("taken", false)):
			var d: float = c.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = c
	if best != null:
		p.sit_on(best)
		Sfx.play("click", -22.0)
	elif kind != "carpet":
		Sfx.play("denied")
