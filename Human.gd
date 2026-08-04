class_name Human
extends Node3D
## The blocky humanoid (creator preview + third-person body). Now with
## ANIMATIONS: arm/leg swing while walking, idle breathing, jump tuck.

var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _torso: MeshInstance3D
var _head_m: MeshInstance3D
var _hand_mount: Node3D
var _cycle: float = 0.0
var _armor_nodes: Array = []

func build(color: Color, shader_kind: String, face_tex: Texture2D = null) -> void:
	var skin := ShaderLib.make(shader_kind, color)

	_torso = _part(Vector3(0.9, 1.2, 0.45), Vector3(0, 1.4, 0), skin)
	_head_m = _part(Vector3(0.55, 0.55, 0.55), Vector3(0, 2.3, 0), skin)      # head
	_arm_l = _part(Vector3(0.25, 1.1, 0.25), Vector3(-0.6, 1.4, 0), skin)
	_arm_r = _part(Vector3(0.25, 1.1, 0.25), Vector3(0.6, 1.4, 0), skin)
	# held-item mount at the right hand: whatever you hold rides the arm
	_hand_mount = Node3D.new()
	_hand_mount.position = Vector3(0, -0.62, -0.1)
	_hand_mount.rotation_degrees = Vector3(-90, 0, 0)   # -Z follows the arm
	_arm_r.add_child(_hand_mount)
	_leg_l = _part(Vector3(0.32, 1.1, 0.32), Vector3(-0.25, 0.35, 0), skin)
	_leg_r = _part(Vector3(0.32, 1.1, 0.32), Vector3(0.25, 0.35, 0), skin)

	# The drawing is a decal on the FRONT of the head only. The ink is on a
	# transparent sheet, so the skin colour shows through everywhere else.
	if face_tex:
		var face := MeshInstance3D.new()
		face_q = face
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		face.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = face_tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 2   # the face wins over any weird shader skin
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.material_override = mat
		# child of the HEAD, so wherever the head goes -- walk bob, poses,
		# a one-way trip into a wormhole -- the face rides along
		face.position = Vector3(0, 0, -0.281)   # front of the head (-Z)
		face.rotation_degrees = Vector3(0, 180, 0)
		_head_m.add_child(face)

var face_q: MeshInstance3D = null   # the face decal, swappable at runtime

## Neuralink surgery: put a different face (soul) on this head.
func set_face(tex: Texture2D) -> void:
	if face_q == null or not is_instance_valid(face_q):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_q.material_override = mat

func _part(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

## Dress the body in whatever is equipped. Each piece is its own model.
func dress(equip: Dictionary) -> void:
	for n in _armor_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_armor_nodes = []
	if _torso == null:
		return
	var head_id := str(equip.get("head", ""))
	if Inventory.armors.has(head_id):
		var hc: Color = Inventory.armors[head_id]["color"]
		# helmet: dome cap + brim, open face
		_armor_nodes.append(_bolt_on(_head_m, Vector3(0.62, 0.3, 0.62), Vector3(0, 0.22, 0), hc, head_id))
		_armor_nodes.append(_bolt_on(_head_m, Vector3(0.66, 0.1, 0.66), Vector3(0, 0.05, 0), hc, head_id))
	var chest_id := str(equip.get("chest", ""))
	if Inventory.armors.has(chest_id):
		var cc: Color = Inventory.armors[chest_id]["color"]
		# chestplate: front+back plates and shoulder pads
		_armor_nodes.append(_bolt_on(_torso, Vector3(0.96, 0.9, 0.14), Vector3(0, 0.1, -0.26), cc, chest_id))
		_armor_nodes.append(_bolt_on(_torso, Vector3(0.96, 0.9, 0.14), Vector3(0, 0.1, 0.26), cc, chest_id))
		_armor_nodes.append(_bolt_on(_torso, Vector3(0.34, 0.16, 0.5), Vector3(-0.44, 0.6, 0), cc, chest_id))
		_armor_nodes.append(_bolt_on(_torso, Vector3(0.34, 0.16, 0.5), Vector3(0.44, 0.6, 0), cc, chest_id))
	var legs_id := str(equip.get("legs", ""))
	if Inventory.armors.has(legs_id):
		var lc: Color = Inventory.armors[legs_id]["color"]
		# thigh guards riding the legs (they swing with the walk)
		_armor_nodes.append(_bolt_on(_leg_l, Vector3(0.38, 0.55, 0.38), Vector3(0, 0.22, 0), lc, legs_id))
		_armor_nodes.append(_bolt_on(_leg_r, Vector3(0.38, 0.55, 0.38), Vector3(0, 0.22, 0), lc, legs_id))
	var boots_id := str(equip.get("boots", ""))
	if Inventory.armors.has(boots_id):
		var bc: Color = Inventory.armors[boots_id]["color"]
		# chunky boots with a toe cap, on the feet
		for leg in [_leg_l, _leg_r]:
			_armor_nodes.append(_bolt_on(leg, Vector3(0.38, 0.26, 0.42), Vector3(0, -0.46, -0.03), bc, boots_id))
			_armor_nodes.append(_bolt_on(leg, Vector3(0.3, 0.14, 0.2), Vector3(0, -0.5, -0.24), bc.lightened(0.2), boots_id))
	if str(equip.get("charm", "")) == "charm":
		# the charm hangs glowing at the neck
		var gem := _bolt_on(_torso, Vector3(0.14, 0.18, 0.1), Vector3(0, 0.48, -0.3), Color("#b56cff"))
		gem.material_override = Destructible.make_material(Color("#b56cff"), 3.0)
		_armor_nodes.append(gem)

func _bolt_on(parent: MeshInstance3D, size: Vector3, pos: Vector3, c: Color, id: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	if id.begins_with("prism_"):
		mi.material_override = _prism_material()
	elif id.begins_with("ultima_"):
		mi.material_override = Surfaces.portal(Color("#7df9ff"))
	else:
		mi.material_override = Destructible.make_material(c, 0.35)
	parent.add_child(mi)
	return mi

static var _prism_mat: ShaderMaterial

## Iridescent shifting rainbow -- prism armor looks like the shards it costs.
static func _prism_material() -> ShaderMaterial:
	if _prism_mat:
		return _prism_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 vpos;
float hash31(vec3 p) { p = fract(p * 0.3183 + vec3(0.1, 0.2, 0.3)); p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i), b = hash31(i + vec3(1,0,0)), c = hash31(i + vec3(0,1,0)), d = hash31(i + vec3(1,1,0));
	float e = hash31(i + vec3(0,0,1)), g = hash31(i + vec3(1,0,1)), h = hash31(i + vec3(0,1,1)), k = hash31(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y), mix(mix(e,g,f.x), mix(h,k,f.x), f.y), f.z); }
float fbm3(vec3 p) { return vnoise(p) * 0.6 + vnoise(p * 2.3) * 0.4; }
void vertex() { vpos = VERTEX; }
void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	float hue = fract(fres * 0.9 + TIME * 0.12);
	vec3 rainbow = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0, 0.55, 0.92), rainbow, 0.7);
	METALLIC = 0.85;
	ROUGHNESS = 0.12;
	// the ACTUAL warp-portal glow (same boiling fbm rings as the gates),
	// riding above the rainbow at about a quarter strength
	float t = TIME;
	float sw = fbm3(vpos * 5.0 + vec3(t * 0.5, t * 0.35, t * 0.2));
	float ring = sin(sw * 12.0 - t * 2.2) * 0.5 + 0.5;
	EMISSION = rainbow * (0.25 + 0.55 * fres)
		+ rainbow * (0.32 * pow(ring, 2.0) + sw * 0.11);
}
"""
	_prism_mat = ShaderMaterial.new()
	_prism_mat.shader = sh
	return _prism_mat

var _punch_t: float = 0.0
var _jet_node: Node3D
var _flames: Array = []

## Third-person punch: right arm jabs forward.
func punch() -> void:
	_punch_t = 1.0

## Show/hide the jetpack on the back (+ flames while thrusting).
func set_jetpack(on: bool, thrusting: bool = false) -> void:
	if on and _jet_node == null:
		_jet_node = Node3D.new()
		add_child(_jet_node)
		for sx in [-0.22, 0.22]:
			var tank := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.16
			cm.height = 0.9
			tank.mesh = cm
			tank.material_override = Destructible.make_material(Color("#4cc9f0"), 0.4)
			tank.position = Vector3(sx, 1.5, 0.35)
			_jet_node.add_child(tank)
			var flame := MeshInstance3D.new()
			var fm := CylinderMesh.new()
			fm.top_radius = 0.12
			fm.bottom_radius = 0.02
			fm.height = 0.5
			flame.mesh = fm
			flame.material_override = Destructible.make_material(Color("#ffa020"), 6.0)
			flame.position = Vector3(sx, 0.95, 0.35)
			_jet_node.add_child(flame)
			_flames.append(flame)
	if _jet_node:
		_jet_node.visible = on
		for f in _flames:
			f.visible = on and thrusting
			if f.visible:
				f.scale.y = randf_range(0.7, 1.4)   # flicker

## Drive the pose. speed = horizontal m/s, grounded = on floor.
# photo poses (G cycles): 0 off · 1 T-pose · 2 flex · 3 point · 4 dab
var pose: int = 0
const POSE_NAMES := ["off", "T-POSE", "FLEX", "POINT", "DAB", "GUNSLINGER"]

var held_is_weapon: bool = false

func _holding() -> bool:
	return _hand_mount != null and _hand_mount.get_child_count() > 0

## The no-pose hold angle: weapons aim ALL the way up-forward, other
## items sit half-raised in the hand.
func _hold_angle() -> float:
	return 1.5 if held_is_weapon else 0.85

## Show a copy of the held-item model in the right hand (null clears).
func set_held(model: Node3D, is_weapon: bool = false) -> void:
	held_is_weapon = is_weapon
	if _hand_mount == null:
		return
	for c in _hand_mount.get_children():
		c.queue_free()
	if model:
		_hand_mount.add_child(model)
		model.position = Vector3.ZERO
		model.visible = true

## Always set poses through here: turning OFF fully resets the limbs
## (poses touch rotation axes the walk cycle never cleans up).
func set_pose(v: int) -> void:
	pose = v
	if _arm_l:
		for limb in [_arm_l, _arm_r, _leg_l, _leg_r, _torso, _head_m]:
			limb.rotation = Vector3.ZERO

func animate(speed: float, grounded: bool, delta: float, jetting: bool = false) -> void:
	if pose > 0 and _arm_l:
		match pose:
			1:   # T-pose: the classic
				_arm_l.rotation = Vector3(0, 0, -1.45)
				_arm_r.rotation = Vector3(0, 0, 1.45)
				_leg_l.rotation = Vector3.ZERO
				_leg_r.rotation = Vector3.ZERO
			2:   # flex: both arms up and bent
				_arm_l.rotation = Vector3(2.5, 0, -0.7)
				_arm_r.rotation = Vector3(2.5, 0, 0.7)
				_leg_l.rotation = Vector3(0, 0, -0.12)
				_leg_r.rotation = Vector3(0, 0, 0.12)
			3:   # point: right hand dead ahead, staring into destiny
				_arm_l.rotation = Vector3(0, 0, -0.15)
				_arm_r.rotation = Vector3(1.57, 0, 0)
				_leg_l.rotation = Vector3(0.25, 0, 0)
				_leg_r.rotation = Vector3(-0.25, 0, 0)
			4:   # dab. it had to exist.
				_arm_l.rotation = Vector3(2.7, 0, 0.9)
				_arm_r.rotation = Vector3(1.2, 0, -1.1)
				_leg_l.rotation = Vector3(0, 0, -0.2)
				_leg_r.rotation = Vector3(0.3, 0, 0.1)
			6:   # sitting: legs out over the seat edge, hands on the lap
				_arm_l.rotation = Vector3(0.5, 0, -0.15)
				_arm_r.rotation = Vector3(0.5, 0, 0.15)
				_leg_l.rotation = Vector3(1.5, 0, 0)
				_leg_r.rotation = Vector3(1.5, 0, 0)
			5:   # AK stance: BOTH arms parallel along one diagonal gun line.
				# same rotation on both arms + shoulder offset = right hand
				# lands at the grip, left hand further up the handguard.
				_arm_r.rotation = Vector3(1.5, 0.55, 0.0)
				_arm_l.rotation = Vector3(1.5, 0.55, 0.0)
				_torso.rotation = Vector3(0.06, 0.2, 0.0)      # chest follows the gun line
				_head_m.rotation = Vector3(0.0, 0.5, 0.0)      # eyes down the muzzle
				_leg_l.rotation = Vector3(0.45, 0, -0.05)      # front knee bent
				_leg_r.rotation = Vector3(-0.35, 0, 0.08)      # rear leg braced
		return
	if _arm_l == null:
		return
	_punch_t = maxf(0.0, _punch_t - delta * 4.0)
	if not grounded:
		# airborne / jetpack: legs tuck, arms out (or up when jetting)
		var arm_target := -1.2 if jetting else -2.4
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.7, delta * 8.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.5, delta * 8.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm_target, delta * 6.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_target, delta * 6.0)
	elif speed > 0.5:
		# walk/run cycle: opposite arm-leg swing, faster with speed
		_cycle += delta * clampf(speed, 2.0, 14.0) * 1.1
		var sw := sin(_cycle)
		_leg_l.rotation.x = sw * 0.8
		_leg_r.rotation.x = -sw * 0.8
		_arm_l.rotation.x = -sw * 0.6
		if _holding():
			_arm_r.rotation.x = _hold_angle() + sw * 0.15   # raised while walking
		else:
			_arm_r.rotation.x = sw * 0.6
		_torso.position.y = 1.4 + absf(sw) * 0.05
	else:
		# idle: settle limbs, breathe
		_cycle += delta * 2.0
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 10.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 10.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, delta * 10.0)
		# holding something: the arm stays UP, presenting the item
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, _hold_angle() if _holding() else 0.0, delta * 10.0)
		_torso.position.y = 1.4 + sin(_cycle) * 0.02
	# punch overrides the right arm: snappy jab, eased return
	if _punch_t > 0.0:
		var reach := sin(minf(1.0, (1.0 - _punch_t) * 3.0) * PI)
		_arm_r.rotation.x = -1.9 * reach
