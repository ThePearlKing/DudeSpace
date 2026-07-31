class_name Plant
extends StaticBody3D
## A recursively generated plant: a main stalk whose joints can fork into
## WHOLE child branches (own segments, leaves, crowns, sub-branches),
## all part of one generation pass. Bananas grow on branch tips.

var _stalk_col: Color
var _leaf_col: Color
var _main_h: float = 0.0

func _ready() -> void:
	add_to_group("destructible")
	var hue := randf_range(0.25, 0.42)   # greens
	_stalk_col = Color.from_hsv(hue, 0.6, 0.7)
	_leaf_col = Color.from_hsv(hue, 0.7, 0.9)
	var r := randf_range(0.25, 0.5)
	var lean := (Vector3.UP + Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15))).normalized()
	_grow(Vector3.ZERO, lean, r, randi_range(3, 7), 2, true)

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.height = maxf(1.0, _main_h)
	cs.radius = maxf(0.4, r * 2.0)
	col.shape = cs
	col.position = Vector3(0, _main_h * 0.5, 0)
	add_child(col)

## Grows one stalk from `base` along `dir`. Joints may fork into full
## child branches (depth-1), which fork again. THAT's a branch.
func _grow(base: Vector3, dir: Vector3, r: float, segs: int, depth: int, is_main: bool) -> void:
	var pos := base
	var d := dir
	for s in segs:
		var h := randf_range(0.8, 1.6) * (1.0 - float(s) / float(segs) * 0.4) * (1.0 if is_main else 0.75)
		var rr := r * (1.0 - float(s) / float(segs) * 0.6)
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = rr
		cm.top_radius = maxf(rr * 0.75, 0.03)
		cm.height = h
		seg.mesh = cm
		seg.material_override = Destructible.make_material(_stalk_col.darkened(0.0 if is_main else 0.08), 0.1)
		seg.position = pos + d * h * 0.5
		_aim(seg, d)
		add_child(seg)

		# leaves at the joint
		if s > 0 and randf() < 0.7:
			var lf := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(randf_range(0.6, 1.2), 0.06, randf_range(0.3, 0.6)) * (1.0 if is_main else 0.7)
			lf.mesh = lm
			lf.material_override = Destructible.make_material(_leaf_col, 0.2)
			var a := randf() * TAU
			lf.position = pos + Vector3(cos(a) * rr, 0, sin(a) * rr)
			lf.rotation = Vector3(0, a, randf_range(-0.6, 0.6))
			add_child(lf)

		# FORK: a whole child branch grows from this joint
		if depth > 0 and s > 0 and randf() < 0.4:
			var tilt := randf_range(0.6, 1.15)
			var ba := randf() * TAU
			var side := Vector3(cos(ba), 0, sin(ba))
			var child_dir := (d * cos(tilt) + side * sin(tilt)).normalized()
			_grow(pos, child_dir, r * 0.55, maxi(2, segs - randi_range(2, 3)), depth - 1, false)

		pos += d * h
		# stalks wander a little as they climb
		d = (d + Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.06), randf_range(-0.12, 0.12))).normalized()
	if is_main:
		_main_h = pos.y

	# every stalk ends in a crown
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = maxf(r * 2.0, 0.25) * (1.0 if is_main else 0.8)
	sm.height = sm.radius * 1.6
	crown.mesh = sm
	crown.material_override = Destructible.make_material(_leaf_col.lightened(0.1), 0.3)
	crown.position = pos
	add_child(crown)
	# bananas hang under branch crowns. Pottasium.
	if not is_main and randf() < 0.35:
		var nana := Banana.new()
		add_child(nana)
		nana.position = pos + Vector3(0, -0.45, 0)

func _aim(mi: MeshInstance3D, dir: Vector3) -> void:
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.01:
		mi.rotate(axis.normalized(), Vector3.UP.angle_to(dir))

func destroy(push_dir: Vector3) -> void:
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 1, 0), Vector3(0.6, 0.6, 0.6), Color("#4caf50"), push_dir)
	Game.register_break(Vector3(1.5, 2, 1.5), 5)
	queue_free()

## Knife: harvest fiber instead of smashing.
func harvest() -> void:
	Inventory.add_res("plantfiber", randi_range(1, 3))
	Sfx.play("eat", -14.0)
	queue_free()