class_name PythagorasCinematic
extends Node3D
## The gods caught you. Punishment is EDUCATIONAL: your body is
## deconstructed and reassembled as a 3-4-5 right triangle, and the
## squares on its sides unfold until you are, personally, the proof.
## a² + b² = c². You are now the Pythagorean theorem. World pauses,
## runs on an unpausable clock, hands off to the usual death screen.

var _t: float = 0.0
var _cam: Camera3D
var _dude: Human
var _rig: Basis
var _origin: Vector3
var _parts: Array = []      # the dude's meshes, to be shrunk into geometry
var _bars: Array = []       # [{node, from, to, done_len}]
var _squares: Array = []    # [{node, at}]
var _fade: ColorRect
var _done := false

# the sacred proportions (scaled to fit a person)
const A := 2.4
const B := 3.2
const C := 4.0   # 3-4-5, as the ancients demanded

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	Sfx.play("warp", -8.0)

	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.visible = false
		_rig = p.global_transform.basis.orthonormalized()
		_origin = p.global_position
	else:
		_rig = Basis.IDENTITY
	global_transform = Transform3D(_rig, _origin)

	_dude = Human.new()
	add_child(_dude)
	_dude.position = Vector3(0, -1.0, 0)
	_dude.build(Color.html(str(Save.character.get("color", "3aa0ff"))),
		str(Save.character.get("shader", "none")), Save.loaded_paint())
	_dude.dress(Inventory.equip)
	for m in [_dude._head_m, _dude._torso, _dude._arm_l, _dude._arm_r,
			_dude._leg_l, _dude._leg_r]:
		if m and is_instance_valid(m):
			_parts.append(m)

	_cam = Camera3D.new()
	_cam.far = 90000.0
	add_child(_cam)
	_cam.position = Vector3(1.2, 1.2, -7.5)
	_cam.look_at(_origin + _rig * Vector3(1.0, 1.2, 0), _rig.y)
	_cam.current = true

	var ui := CanvasLayer.new()
	ui.layer = 40
	add_child(ui)
	_fade = ColorRect.new()
	_fade.color = Color(1.0, 0.35, 0.63, 0.0)   # the pink of enlightenment
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)

## A glowing golden bar from `a` to `b` in diagram space (local XY plane).
func _make_bar(a: Vector2, b: Vector2) -> Dictionary:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.26, 0.26)   # scaled up along X to full length
	mi.mesh = bm
	mi.material_override = Destructible.make_material(Color("#ffd166"), 2.2)
	add_child(mi)
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, mid.y, 0)
	mi.rotation.z = (b - a).angle()
	mi.scale = Vector3(0.02, 1, 1)
	return {"node": mi, "len": a.distance_to(b)}

## The square erected on edge a->b, unfolding OUTWARD (to the right of
## the a->b direction -- pass edges wound so "outward" is away from the
## triangle's interior).
func _make_square(a: Vector2, b: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := a.distance_to(b)
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s, 0.1)
	mi.mesh = bm
	var mat := Destructible.make_material(Color("#ffcf40"), 1.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.81, 0.25, 0.55)
	mi.material_override = mat
	add_child(mi)
	var dirv := (b - a).normalized()
	var out := Vector2(dirv.y, -dirv.x)   # right-hand normal
	var centre := (a + b) * 0.5 + out * (s * 0.5)
	mi.position = Vector3(centre.x, centre.y, 0.1)
	mi.rotation.z = dirv.angle()
	mi.scale = Vector3(0.02, 0.02, 1)
	return mi

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta

	# act 1 (0-1.6): lifted. considered. found approximately triangular.
	if _t < 1.6:
		_dude.position.y = lerpf(-1.0, 0.4, _t / 1.6)
		_dude.rotation.y += delta * (0.4 + _t * 1.2)

	# act 2 (1.6-3.6): deconstruction into the sacred sides
	if _t >= 1.6 and _bars.is_empty():
		Sfx.play("explode", -12.0)
		# right angle at origin of diagram space; a along X, b up Y.
		# edges wound so every square unfolds AWAY from the triangle.
		_bars.append(_make_bar(Vector2(0, 0), Vector2(A, 0)))       # a
		_bars.append(_make_bar(Vector2(0, B), Vector2(0, 0)))       # b
		_bars.append(_make_bar(Vector2(A, 0), Vector2(0, B)))       # c
	if not _bars.is_empty() and _t < 3.6:
		var k := clampf((_t - 1.6) / 2.0, 0.0, 1.0)
		for e in _bars:
			e["node"].scale = Vector3(maxf(0.02, k * e["len"] / 0.26), 1, 1)
		for m in _parts:
			if is_instance_valid(m):
				m.scale = Vector3.ONE * (1.0 - k)   # you, redistributed
		_dude.rotation.y += delta * 3.0

	# act 3 (3.6-6.6): the squares unfold, smallest first. the proof builds.
	if _t >= 3.6 and _squares.is_empty():
		Sfx.play("learn", -8.0)
		_squares.append({"node": _make_square(Vector2(0, 0), Vector2(A, 0)), "at": 3.6})     # a²
		_squares.append({"node": _make_square(Vector2(0, B), Vector2(0, 0)), "at": 4.5})     # b²
		_squares.append({"node": _make_square(Vector2(A, 0), Vector2(0, B)), "at": 5.4})     # c²
	for e in _squares:
		var kk := clampf((_t - float(e["at"])) / 0.8, 0.0, 1.0)
		if kk > 0.0:
			e["node"].scale = Vector3(maxf(0.02, kk), maxf(0.02, kk), 1)
			if kk >= 1.0 and not e.get("rang", false):
				e["rang"] = true
				Sfx.play("coin", -10.0)

	# act 4 (6.6-9.0): pull back and admire what you have become
	if _t >= 6.6:
		_cam.global_position = _cam.global_position.lerp(
			_origin + _rig * Vector3(1.2, 1.4, -13.0), delta * 1.5)
		_cam.look_at(_origin + _rig * Vector3(1.0, 1.4, 0), _rig.y)
		rotate_object_local(Vector3.UP, delta * 0.25)   # the theorem turns
	if _t >= 8.2:
		_fade.color.a = minf(0.85, _fade.color.a + delta * 0.8)

	# handoff: the classic death screen finishes the sentence
	if _t >= 9.6:
		_done = true
		get_tree().paused = false
		Game.complete_transform()
		queue_free()
