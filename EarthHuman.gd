class_name EarthHuman
extends CharacterBody3D
## Earth's native species: the Human. Observably one of the dumbest
## creatures in the universe -- walks into rocks, stares at nothing,
## jumps for no reason, follows you around. But press F and you get a
## glimpse of the inner life, which is somehow vast. Just like the
## real thing.

const WALK_SPEED := 2.6
const PANIC_SPEED := 6.5

## What they are DOING (visible, dumb). Feet stay on the ground -- they
## are dumb, not astronauts.
const ACTS := ["wander", "stare", "circle", "spin", "follow"]

## What they are THINKING (hidden, vast). F to ask.
const THOUGHTS := [
	"I hunger, therefore I am.",
	"what if the sky is just a very big floor",
	"I have walked into that rock four times. The rock and I have history now.",
	"sometimes I stand still so the universe can find me",
	"do the stars know my name? do I know my name? note to self: get a name",
	"today I will be productive. tomorrow. definitely tomorrow.",
	"the mortgage isn't real if I don't think about it",
	"I am 70% water pretending to be busy",
	"spinning feels right. I don't question it anymore.",
	"I miss someone I haven't met yet",
	"circles are just walking that comes back. profound.",
	"what if I'm the main character. what if I'm NOT.",
	"I should call my mother. do I have a mother? I should call someone.",
	"the void stares back but honestly it started it",
	"every day the sun leaves and every day I forgive it",
	"my knees hurt in a way that feels philosophical",
	"I could have been anything. I chose: standing here.",
	"one day I will die. anyway, time to walk in circles.",
	"is the blue dude a god? he has a jetpack. gods have jetpacks.",
	"I contain multitudes. mostly snacks.",
]

var _home = null            # Universe body we live on
var _body: Human
var _dir: Vector3 = Vector3.ZERO
var _act: String = "wander"
var _act_t: float = 0.0
var _panic_t: float = 0.0
var _bubble: Label3D
var _bubble_t: float = 0.0
var _grounded: bool = false

func setup(home_body) -> void:
	_home = home_body

func _ready() -> void:
	add_to_group("earth_human")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	col.shape = cap
	add_child(col)

	_body = Human.new()
	_body.position = Vector3(0, -0.95, 0)
	add_child(_body)
	# every Human its own regrettable outfit colour
	var skin := Color.from_hsv(randf(), randf_range(0.3, 0.8), randf_range(0.5, 0.95))
	_body.build(skin, "none")
	_body.scale = Vector3(0.85, 0.85, 0.85)   # slightly small. slightly sad.

	_bubble = Label3D.new()
	_bubble.font_size = 22
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 1.6, 0)
	_bubble.modulate = Color(1, 1, 1, 0.0)
	_bubble.outline_size = 8
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_bubble)

	_pick_act()

func _pick_act() -> void:
	_act = ACTS[randi() % ACTS.size()]
	_act_t = randf_range(2.5, 7.0)
	var up := _up()
	var tang := up.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
	_dir = tang.normalized() if tang.length() > 0.01 else Vector3.ZERO

func _up() -> Vector3:
	if _home == null:
		return Vector3.UP
	return (global_position - _home.center).normalized()

## F: ask what's on their mind. There is always something on their mind.
func use() -> void:
	_bubble.text = THOUGHTS[randi() % THOUGHTS.size()]
	_bubble_t = 4.5
	Sfx.play("click", -20.0)

func take_damage(_dmg: float, dir: Vector3) -> void:
	# violence: observably effective, emotionally complicated
	_panic_t = 5.0
	_dir = (dir - _up() * dir.dot(_up())).normalized()
	_bubble.text = "WHY"
	_bubble_t = 2.0
	Sfx.play("hurt", -16.0)

func _physics_process(delta: float) -> void:
	if _home == null:
		return
	var up := _up()
	var g := Universe.gravity_at(global_position)

	# thought bubble fades like the thought itself
	if _bubble_t > 0.0:
		_bubble_t -= delta
		_bubble.modulate.a = clampf(_bubble_t / 0.8, 0.0, 1.0)

	_act_t -= delta
	if _act_t <= 0.0 and _panic_t <= 0.0:
		_pick_act()

	var speed := 0.0
	if _panic_t > 0.0:
		_panic_t -= delta
		speed = PANIC_SPEED
	else:
		match _act:
			"wander":
				speed = WALK_SPEED
			"stare":
				speed = 0.0
			"circle":
				speed = WALK_SPEED * 0.8
				_dir = _dir.rotated(up, delta * 1.6)   # walking that comes back
			"spin":
				speed = 0.0
				_dir = _dir.rotated(up, delta * 2.4)   # rotating. contemplating.
			"follow":
				var p = get_tree().get_first_node_in_group("player")
				if p and global_position.distance_to(p.global_position) < 40.0:
					var to: Vector3 = p.global_position - global_position
					_dir = (to - up * to.dot(up)).normalized()
					if to.length() > 4.0:
						speed = WALK_SPEED
				else:
					speed = WALK_SPEED   # "following" nothing. still counts.

	var v_up := velocity.dot(up)
	v_up += g.dot(up) * delta
	velocity = _dir * speed + up * v_up
	up_direction = up
	move_and_slide()
	_grounded = is_on_floor()
	# hard leash: whatever physics thinks it's doing, a Human belongs on
	# the ground. no accidental astronauts.
	var alt: float = global_position.distance_to(_home.center) - _home.radius
	if alt > 3.0:
		global_position = _home.center + up * (_home.radius + 1.1)
		velocity = Vector3.ZERO

	# face where we walk, feet planted along gravity
	if speed > 0.1 and _dir.length() > 0.1:
		var x := up.cross(_dir).normalized()
		global_transform.basis = Basis(x, up, -_dir).orthonormalized()
	if _body:
		_body.animate(speed, _grounded, delta)
