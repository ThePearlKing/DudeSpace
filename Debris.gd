class_name Debris
extends RigidBody3D
## A shatter chunk that falls under the summed gravity of all planets,
## so it behaves on every world -- and floats freely in deep space.

var life: float = 3.0   # seconds until the chunk expires

func _ready() -> void:
	gravity_scale = 0.0   # we apply gravity ourselves

func _physics_process(delta: float) -> void:
	apply_central_force(Universe.gravity_at(global_position) * mass)
	life -= delta
	if life <= 0.0:
		queue_free()
