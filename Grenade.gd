class_name Grenade
extends Node3D
## A thrown grenade. Arcs under whatever gravity is local, cooks for a
## short fuse (or pops on landing), then solves problems in an area:
## machines point-blank are GONE, machines a bit out take 1 damage
## (three and they're gone too), and every player, monster, human and
## animal in range learns about shrapnel.

const FUSE := 2.2
const KILL_R := 3.5      # machines inside this: instant scrap
const DENT_R := 7.0      # machines inside this: +1 damage (3 = dead)
const HURT_R := 8.0      # creatures inside this: scaled damage

var vel: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.16
	m.height = 0.32
	_mesh.mesh = m
	_mesh.material_override = Destructible.make_material(Color("#3a4a3a"), 0.1)
	add_child(_mesh)
	var pin := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.06, 0.08, 0.06)
	pin.mesh = pm
	pin.position = Vector3(0, 0.18, 0)
	pin.material_override = Destructible.make_material(Color("#c0c0c8"), 0.4)
	add_child(pin)

func _physics_process(delta: float) -> void:
	_t += delta
	vel += Universe.gravity_at(global_position) * delta
	global_position += vel * delta
	_mesh.rotate_x(delta * 9.0)
	# landed? (planet surface contact, the honest way)
	var b = Universe.nearest(global_position)
	if b and global_position.distance_to(b.center) <= b.radius + 0.2:
		_boom()
		return
	if _t >= FUSE:
		_boom()

func _boom() -> void:
	var pos := global_position
	# machines: scrap the close ones, dent the near ones
	for grp in ["machine", "chest", "autominer", "bench", "nterm"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var d: float = pos.distance_to(n.global_position)
			if d > DENT_R:
				continue
			if not Net.can_break(str(n.get_meta("owner", ""))):
				continue   # host says other people's stuff is off-limits
			if n is EMachines.NuclearReactor:
				continue   # containment shrugs off grenades. use a wrench.
			var dmg := 3 if d <= KILL_R else 1
			var hits := int(n.get_meta("g_dmg", 0)) + dmg
			if hits >= 3:
				Destructible.spawn_debris(get_parent(), n.global_position,
					Vector3(1.2, 1.2, 1.2), Color("#8890a0"), Vector3.UP)
				n.queue_free()
			else:
				n.set_meta("g_dmg", hits)
	# creatures: everyone in range, falloff by distance
	for grp2 in ["enemy", "earth_human", "animal"]:
		for c in get_tree().get_nodes_in_group(grp2):
			if not (c is Node3D) or not is_instance_valid(c):
				continue
			var dc: float = pos.distance_to(c.global_position)
			if dc > HURT_R:
				continue
			var fall := 1.0 - dc / HURT_R
			if c.has_method("take_damage"):
				c.take_damage(34.0 * fall, (c.global_position - pos).normalized())
	# the thrower is not exempt. physics has no favorites.
	var p = get_tree().get_first_node_in_group("player")
	if p != null:
		var dp: float = pos.distance_to(p.global_position)
		if dp < HURT_R:
			Game.hurt(30.0 * (1.0 - dp / HURT_R), false, "your own grenade")
	# friends in the blast: friendly fire law applies (hit_player
	# silently refuses when the host forbids it)
	if Net.active:
		for pid in Net.player_names.keys():
			var av = Net.avatar_position(int(pid))
			if av == null:
				continue
			var dpe: float = (av as Vector3).distance_to(pos)
			if dpe < HURT_R:
				Net.hit_player(int(pid), 30.0 * (1.0 - dpe / HURT_R), true)
	# the show
	var parts := GPUParticles3D.new()
	parts.amount = 70
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 1.6
	var ppm := ParticleProcessMaterial.new()
	ppm.direction = Vector3.ZERO
	ppm.spread = 180.0
	ppm.initial_velocity_min = 5.0
	ppm.initial_velocity_max = 16.0
	ppm.gravity = Vector3.ZERO
	ppm.scale_min = 0.08
	ppm.scale_max = 0.3
	ppm.color = Color("#ff8030")
	parts.process_material = ppm
	var pmesh := SphereMesh.new()
	pmesh.radius = 1.0
	pmesh.height = 2.0
	pmesh.radial_segments = 6
	pmesh.rings = 3
	pmesh.material = Destructible.make_material(Color("#ff8030"), 3.0)
	parts.draw_pass_1 = pmesh
	get_parent().add_child(parts)
	parts.global_position = pos
	parts.emitting = true
	get_tree().create_timer(2.5).timeout.connect(parts.queue_free)
	Sfx.play("explode", -4.0)
	queue_free()
