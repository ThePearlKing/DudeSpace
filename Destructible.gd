class_name Destructible
extends StaticBody3D
## Generic smashable box. Optional hp (tough blocks take several hits)
## and coin value. Shatters into physics debris that falls under the
## nearest planet's gravity.

var _size: Vector3 = Vector3.ONE
var _color: Color = Color.WHITE
var _hp: int = 1
var _coins: int = -1        # -1 => derive from volume
var _emit: float = 0.5
var _anger: float = 0.0     # destroying this angers the noodle gods
var _res_id: String = ""    # resource dropped on break ("ore", "ultima"...)
var _res_n: int = 0
var _dead: bool = false
var _mesh: MeshInstance3D

func setup(size: Vector3, color: Color, hp: int = 1, coins: int = -1, emit: float = 0.5, anger: float = 0.0, res_id: String = "", res_n: int = 0) -> void:
	_size = size
	_color = color
	_hp = maxi(1, hp)
	_coins = coins
	_emit = emit
	_anger = anger
	_res_id = res_id
	_res_n = res_n

var rock: bool = false   # lumpy low-poly boulder instead of a box

func _ready() -> void:
	add_to_group("destructible")
	_mesh = MeshInstance3D.new()
	if rock:
		var sm := SphereMesh.new()
		sm.radius = _size.x * 0.62
		sm.height = _size.y
		sm.radial_segments = 6
		sm.rings = 3
		_mesh.mesh = sm
		_mesh.rotation_degrees = Vector3(randf_range(0, 30), randf_range(0, 180), randf_range(0, 30))
	else:
		var box := BoxMesh.new()
		box.size = _size
		_mesh.mesh = box
	_mesh.material_override = make_material(_color, _emit)
	add_child(_mesh)
	var col := CollisionShape3D.new()
	if rock:
		var ss := SphereShape3D.new()
		ss.radius = _size.x * 0.6
		col.shape = ss
	else:
		var shape := BoxShape3D.new()
		shape.size = _size
		col.shape = shape
	add_child(col)

## Used by LogicDiagram: light the panel while its node outputs 1.
func set_glow(on: bool) -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.material_override = make_material(
			Color("#1a4d2e") if on else _color, 2.0 if on else _emit)

static func make_material(c: Color, emit: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = emit
	mat.metallic = 0.1
	mat.roughness = 0.6
	return mat

func destroy(push_dir: Vector3) -> void:
	if _dead:
		return
	_hp -= 1
	if _hp > 0:
		# tough block: flash + shrug it off
		if _mesh:
			_mesh.material_override = make_material(_color.lightened(0.5), _emit + 1.5)
			# method callable: auto-disconnects if we die before it fires
			get_tree().create_timer(0.08).timeout.connect(_unflash)
		return
	_dead = true
	remove_from_group("destructible")
	Net.broadcast_break(global_position)   # other players see it die too
	spawn_debris(get_parent(), global_position, _size, _color, push_dir)
	Game.register_break(_size, _coins)
	if _res_id != "" and _res_n > 0:
		Inventory.add_res(_res_id, _res_n)
	if _anger > 0.0:
		Game.anger(_anger)   # Claude is cool; the gods rage when you break him
	Sfx.play("explode", -12.0)
	queue_free()

## Mirrored network death: debris only -- rewards went to whoever broke it.
func net_destroy() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("destructible")
	spawn_debris(get_parent(), global_position, _size, _color, Vector3.UP)
	queue_free()

func _unflash() -> void:
	if _mesh:
		_mesh.material_override = make_material(_color, _emit)

## Shared shatter: N small rigid chunks flung outward.
static func spawn_debris(world: Node, origin: Vector3, size: Vector3, color: Color, push_dir: Vector3) -> void:
	if not is_instance_valid(world):
		return
	var csize := size / 2.2
	for i in 8:
		var frag := Debris.new()
		frag.mass = 0.4
		var fm := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		fbox.size = csize
		fm.mesh = fbox
		fm.material_override = make_material(color, 1.2)
		frag.add_child(fm)
		var fcol := CollisionShape3D.new()
		var fshape := BoxShape3D.new()
		fshape.size = csize
		fcol.shape = fshape
		frag.add_child(fcol)
		world.add_child(frag)
		frag.global_position = origin + Vector3(
			randf_range(-0.5, 0.5), randf_range(0.0, 1.0), randf_range(-0.5, 0.5))
		var kick := push_dir.normalized() * randf_range(4.0, 9.0)
		kick += Vector3(randf_range(-3, 3), randf_range(3, 8), randf_range(-3, 3))
		frag.apply_impulse(kick)
		frag.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		frag.life = randf_range(2.5, 4.0)   # self-expiring: no timer lambda
