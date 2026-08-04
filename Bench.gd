class_name Bench
extends StaticBody3D
## Public seating: a park bench (two seats) or a lone chair (one).
## Humans claim the seat markers on their own schedule. The player
## presses F. Everyone sits on the same street furniture -- placed
## benches included. Civic infrastructure at its purest.

var is_bench: bool = true
var yaw: float = -1.0   # < 0 = roll a random one at build time

func _ready() -> void:
	add_to_group("bench")
	var wood := Destructible.make_material(Color("#7a5a34"), 0.05)
	var dark := Destructible.make_material(Color("#3a3a3e"), 0.02)
	var w := 1.8 if is_bench else 0.6
	var seat := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(w, 0.08, 0.55)
	seat.mesh = sm
	seat.position = Vector3(0, 0.55, 0)
	seat.material_override = wood
	add_child(seat)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.5, 0.08)
	back.mesh = bm
	back.position = Vector3(0, 0.85, 0.28)
	back.material_override = wood
	add_child(back)
	for lx in [-w * 0.45, w * 0.45]:
		for lz in [-0.22, 0.22]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.07, 0.55, 0.07)
			leg.mesh = lm
			leg.position = Vector3(lx, 0.27, lz)
			leg.material_override = dark
			add_child(leg)
	# the interact/collision body: the seat plank
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(w, 0.66, 0.6)
	col.shape = cs
	col.position = Vector3(0, 0.33, 0)
	add_child(col)
	# seat markers: the points humans (and the player) actually claim
	var offs: Array = [-0.45, 0.45] if is_bench else [0.0]
	for ox in offs:
		var s := Node3D.new()
		s.position = Vector3(ox, 0.55, 0)
		s.add_to_group("seat")
		s.set_meta("taken", false)
		add_child(s)
	if yaw < 0.0:
		yaw = randf() * TAU
	rotate_object_local(Vector3.UP, yaw)

## F: take a load off. Nearest free seat wins.
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
	else:
		Sfx.play("denied")   # bench full. city life.
