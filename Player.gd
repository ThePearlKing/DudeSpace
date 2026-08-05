class_name Player
extends CharacterBody3D
## On-foot dude. Gravity comes from the nearest planet, so you can walk
## the whole surface of any world. Smash for coins, board a nearby
## rocket with F, toggle the jetpack with J.

const WALK_SPEED := 9.0
const JUMP_VEL := 8.0        # fixed launch speed -> low gravity = higher jump
const MOUSE_SENS := 0.0025
const SMASH_COOLDOWN := 0.16
const SMASH_RADIUS := 4.5
const JET_THRUST := 16.0
const JET_BURN := 6.0
const AIR_ACCEL := 8.0        # limited steering while airborne / in flight

var _head: Node3D
var _camera: Camera3D
var _smash_area: Area3D
var _pitch: float = 0.0
var _look: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _shake: float = 0.0
var _jetting: bool = false
var _g: float = 5.0
var _hand: Node3D
var _held: Node3D
var _punch: float = 0.0
var _body: Human
var _view_mode: int = 0   # 0 fps · 1 third (behind) · 2 second (face cam)
var noclip: bool = false  # cheat: fast free flight, no gravity, no walls
var freecam: bool = false # photo mode: camera flies, your DUDE stays put
var _fc: Camera3D = null
var _zoom_f: float = 1.0    # C = spyglass zoom (when C isn't jet-down)
var _zooming: bool = false
var _zoom_extra: float = 1.0   # wheel while zoomed: a touch tighter

func set_body_pose(v: int) -> void:
	if _body:
		_body.set_pose(v)

func toggle_freecam() -> void:
	freecam = not freecam
	if freecam:
		_fc = Camera3D.new()
		_fc.fov = Settings.fov
		get_tree().current_scene.add_child(_fc)
		_fc.global_transform = _camera.global_transform
		_fc.current = true
		_fc.cull_mask = 0xFFFFF & ~(1 << 9)   # face cam never sees the hand
		_apply_body_vis()
		if _hand:
			_hand.visible = false
	else:
		if _fc and is_instance_valid(_fc):
			_fc.queue_free()
		_fc = null
		_camera.current = true
		if _hand:
			_hand.visible = _view_mode == 0
		_apply_body_vis()

func _apply_body_vis() -> void:
	# the body is ALWAYS visible -- what changes is which cameras may
	# render it. fps: layer 11 only (your camera masks it out; windows,
	# TVs, friends see you whole). third person: plain layer 1.
	if _body == null:
		return
	_body.visible = true
	_set_layers(_body, (1 << 10) if _view_mode == 0 else 1)

func _set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D:
		n.layers = mask
	for c in n.get_children():
		_set_layers(c, mask)

func _ready() -> void:
	add_to_group("player")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 2.0
	cap.radius = 0.4
	col.shape = cap
	add_child(col)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.7, 0)
	add_child(_head)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 120000.0
	# your OWN body lives on layer 11: every other camera sees it, yours
	# doesn't -- so windows and TVs show a person, not a floating hand
	_camera.cull_mask = 0xFFFFF & ~(1 << 10)
	_head.add_child(_camera)

	_smash_area = Area3D.new()
	_smash_area.monitoring = true
	var sc := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = SMASH_RADIUS
	sc.shape = sph
	sc.position = Vector3(0, 0, -3.5)
	_smash_area.add_child(sc)
	_camera.add_child(_smash_area)

	_build_hand()
	_build_body()
	_jetting = Inventory.jet_on and Inventory.has_jetpack   # as you left it
	Inventory.changed.connect(func() -> void:
		if _body and is_instance_valid(_body):
			_body.dress(Inventory.equip)
			# fresh armor meshes spawn on layer 1 -- re-layer at once or the
			# chestplate photobombs first person for a frame on hotbar scroll
			_apply_body_vis())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _char_color() -> Color:
	var hex: String = Save.character.get("color", "3aa0ff")
	var c := Color.html(hex)
	return c if c != Color(0, 0, 0, 1) or hex.begins_with("00") else Color("#3aa0ff")

func _char_shader() -> String:
	return Save.character.get("shader", "none")

func _build_hand() -> void:
	# First-person arm wears YOUR character skin (colour + weird shader
	# + the EFFECT parameters, fluid and all).
	var skin := ShaderLib.make(_char_shader(), _char_color(), null,
		Save.character.get("fx", {}))
	_hand = Node3D.new()
	_camera.add_child(_hand)
	_hand.position = HAND_REST
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.22, 0.22, 0.6)
	arm.mesh = am
	arm.material_override = skin
	arm.position = Vector3(0, 0, 0.35)
	_hand.add_child(arm)
	var fist := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.3, 0.32, 0.34)
	fist.mesh = fm
	fist.material_override = skin   # same skin as the arm, fx included
	_hand.add_child(fist)

	# held item shown in front of the fist (a tiny MODEL, not a cube)
	_held = Node3D.new()
	_held.position = Vector3(0, 0.05, -0.4)
	_hand.add_child(_held)
	_held.visible = false

func _build_body() -> void:
	# Third-person body: the full character, hidden in first person.
	_body = Human.new()
	add_child(_body)
	_body.position = Vector3(0, -1.0, 0)
	_body.build(_char_color(), _char_shader(), Save.loaded_paint(),
		Save.character.get("fx", {}))
	_body.dress(Inventory.equip)
	_apply_body_vis()

## Called after the save is applied (the save loads AFTER the player
## spawns, so the J-state must be re-read).
func restore_jet() -> void:
	_jetting = Inventory.jet_on and Inventory.has_jetpack

## Re-skin after an Edit Character session (pause menu).
func refresh_look() -> void:
	if _body and is_instance_valid(_body):
		_body.queue_free()
	_build_body()
	_body.visible = _view_mode != 0
	if _hand and is_instance_valid(_hand):
		_hand.queue_free()
	_build_hand()
	_hand.visible = _view_mode == 0
	_update_held()

func _toggle_view() -> void:
	_view_mode = (_view_mode + 1) % 3
	match _view_mode:
		0:   # first person
			_camera.position = Vector3.ZERO
			_camera.rotation = Vector3.ZERO
		1:   # third person, behind
			_camera.position = Vector3(0, 1.4, 6.0)
			_camera.rotation = Vector3.ZERO
		2:   # second person: in front, looking back at your face
			_camera.position = Vector3(0, 1.4, -6.0)
			_camera.rotation = Vector3(0, PI, 0)
	if _hand:
		_hand.visible = _view_mode == 0
	if _body:
		_apply_body_vis()

func camera() -> Camera3D:
	return _camera

func _ui_open() -> bool:
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if Game.mode != Game.Mode.ON_FOOT or Game.dead:
		return
	if _ghost != null and event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_confirm_ghost()   # either button places. Esc cancels.
		get_viewport().set_input_as_handled()
		return
	# door/DESTROY modes only bite while the Furniture Placer is in hand;
	# swap items and your clicks are punches again, no funeral
	if (_door_mode or _wreck_mode) \
			and Inventory.slot_id(Inventory.selected) != "furnkit":
		if _door_mode or _wreck_mode:
			_door_mode = false
			_wreck_mode = false
			_door_frame = null
			var hudm = get_tree().get_first_node_in_group("hud")
			if hudm:
				hudm.flash("door/destroy tool sleeps — hold the Furniture Placer to use it")
	if _door_mode and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_door_click()
		get_viewport().set_input_as_handled()
		return
	if _door_mode and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_door_mode = false
		_door_frame = null
		Sfx.play("click", -18.0)
		get_viewport().set_input_as_handled()
		return
	if _wreck_mode and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_wreck_click()
		get_viewport().set_input_as_handled()
		return
	if _wreck_mode and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_wreck_mode = false
		Sfx.play("click", -18.0)
		get_viewport().set_input_as_handled()
		return
	# house DELETE tool: lives on the House Kit the same way DESTROY
	# lives on the Furniture Placer
	if _hwreck_mode and Inventory.slot_id(Inventory.selected) != "housekit":
		_hwreck_mode = false
	# right-click ALWAYS backs out of the destroy tools (Esc can get
	# eaten by the pause menu -- nobody stays trapped in delete mode)
	if (_hwreck_mode or _wreck_mode) and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_hwreck_mode = false
		_wreck_mode = false
		var hudc = get_tree().get_first_node_in_group("hud")
		if hudc:
			hudc.flash("delete tool off")
		Sfx.play("click", -18.0)
		get_viewport().set_input_as_handled()
		return
	if _hwreck_mode and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_hwreck_click()
		get_viewport().set_input_as_handled()
		return
	if _hwreck_mode and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_hwreck_mode = false
		Sfx.play("click", -18.0)
		get_viewport().set_input_as_handled()
		return
	if _ghost != null and event is InputEventKey and event.pressed 			and event.keycode == KEY_ESCAPE:
		_cancel_ghost()
		get_viewport().set_input_as_handled()
		return
	if _ghost != null and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if _ghost_kind != "doorframe":
			_ghost_yaw += PI * 0.25   # R: rotate the hologram
		get_viewport().set_input_as_handled()
		return
	if _ghost != null and _ghost_kind == "station" and event is InputEventKey \
			and event.pressed and event.keycode == KEY_T:
		_ring_snap = not _ring_snap
		var hudr = get_tree().get_first_node_in_group("hud")
		if hudr:
			hudr.flash("RING SNAP %s — docked pieces %s" % [
				"ON" if _ring_snap else "OFF",
				"curve around the planet" if _ring_snap else "extend dead flat"])
		Sfx.play("click", -14.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and get_window().has_focus():
		_look += event.relative
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_interact()
			KEY_J:
				if Inventory.has_jetpack:
					_jetting = not _jetting
					Inventory.jet_on = _jetting
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				Inventory.select_slot(event.keycode - KEY_1)
			KEY_F5:
				_toggle_view()
			KEY_Q:
				Inventory.drop_slot(Inventory.selected)
			KEY_G:
				if _body:
					_body.set_pose((_body.pose + 1) % 6)
					var hudp = get_tree().get_first_node_in_group("hud")
					if hudp:
						hudp.flash("pose: " + Human.POSE_NAMES[_body.pose])
					Sfx.play("click", -16.0)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_use_selected()
			MOUSE_BUTTON_WHEEL_DOWN:
				if not _ui_open():
					if _zooming:
						_zoom_extra = minf(1.0, _zoom_extra / 0.82)   # ease back out
					elif _port_picking():
						_cycle_port(-1)
					else:
						Inventory.select_slot((Inventory.selected + 1) % 5)
			MOUSE_BUTTON_WHEEL_UP:
				if not _ui_open():
					if _zooming:
						_zoom_extra = maxf(0.10, _zoom_extra * 0.82)  # telescope territory
					elif _port_picking():
						_cycle_port(1)
					else:
						Inventory.select_slot((Inventory.selected + 4) % 5)

func jetting() -> bool:
	return _jetting

var seated: Node3D = null   # bench seat marker we're parked on
var _ghost: Node3D = null   # placement preview hologram
var _ghost_cat := ""        # "house" | "furn"
var _ghost_kind := ""
var _ghost_yaw := 0.0
var _door_mode: bool = false      # door tool armed: clicks select frames
var _door_frame: Node3D = null    # first frame clicked
var _wreck_mode: bool = false     # DESTROY tool: clicks break furniture
var _hwreck_mode: bool = false    # DELETE tool: one click demolishes houses/machines
var _ring_snap: bool = true       # station docks curve around the planet (T)
var _ghost_dock = null            # station preview's dock tf -- placement USES IT
var _hwreck_hl: MeshInstance3D = null   # red preview box over the doomed target
var _hwreck_target = null

## The Door tool: OUTSIDE, pick house A (with a free frame), then
## house B. They dock into one build, hallway and all.
## DOOR TOOL v2: works like the wiring tool. Arm it, then LEFT-CLICK a
## door frame, then click a second frame -- a hologram over the first
## frame previews the merged layout (green = docks, red = why not).
func _door_tool() -> void:
	_door_mode = true
	_wreck_mode = false
	if _door_frame != null and not is_instance_valid(_door_frame):
		_door_frame = null
	Sfx.play("click", -12.0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash("frame A still armed — click frame B" if _door_frame != null \
			else "DOOR TOOL — click the first door frame (Esc puts it away)")

var _deck_hit := Vector3.ZERO

## The station platform you're aiming at, if any (12m reach).
func _deck_under_crosshair() -> House:
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from,
		from - _camera.global_transform.basis.z * 12.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n is House and n.kind == "station":
				_deck_hit = hit.position
				return n
			n = n.get_parent()
	return null

func _frame_under_crosshair() -> Node3D:
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from,
		from - _camera.global_transform.basis.z * 9.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n.is_in_group("doorframe"):
				return n
			n = n.get_parent()
	return null

func _door_click() -> void:
	_cooldown = 0.3   # the same click must not also punch
	var hud = get_tree().get_first_node_in_group("hud")
	var fr := _frame_under_crosshair()
	if fr == null:
		Sfx.play("denied", -18.0)
		return
	if bool(fr.get_meta("linked", false)):
		Sfx.play("denied")
		if hud:
			hud.flash("that frame already has a door")
		return
	if _door_frame == null or not is_instance_valid(_door_frame):
		_door_frame = fr
		Sfx.play("click", -10.0)
		var ha = House.house_at(fr.global_position)
		if ha != null:
			_door_holo(fr, [[ha, Color("#7be8ff")]], Vector3.ZERO, 2.5)
		if hud:
			hud.flash("frame A armed — click frame B")
		return
	if fr == _door_frame:
		Sfx.play("click", -18.0)
		return
	var ha2 = House.house_at(_door_frame.global_position)
	var hb = House.house_at(fr.global_position)
	if ha2 == null or hb == null:
		Sfx.play("denied")
		if hud:
			hud.flash("DOOR: %s frame isn't inside a room" % \
				("first" if ha2 == null else "second"))
		return
	var ck: Dictionary = ha2.dock_check(_door_frame, hb, fr)
	if not bool(ck["ok"]):
		Sfx.play("denied")
		if hud:
			hud.flash("DOOR: " + str(ck["reason"]))
		_door_holo(_door_frame, [[ha2, Color("#7be8ff")], [hb, Color("#ff5964")]],
			ck["delta"], 2.5)
		return
	# valid: flash the merged layout GREEN, then dock for real
	_door_holo(_door_frame, [[ha2, Color("#7be8ff")], [hb, Color("#4dff9a")]],
		ck["delta"], 1.4)
	ha2.connect_frames(_door_frame, hb, fr)
	_door_frame = null
	_door_mode = false
	if hud:
		hud.flash("DOORWAY CUT — houses merged")

func _furn_under_crosshair() -> Furniture:
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from,
		from - _camera.global_transform.basis.z * 9.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n is Furniture:
				return n
			n = n.get_parent()
	return null

## What the DELETE tool would eat: any house or ANY machine (chests,
## electric, radio -- everything that extends Machine).
func _delete_target_under_crosshair() -> Node3D:
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from,
		from - _camera.global_transform.basis.z * 60.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n is House or n is Machine:
				return n
			n = n.get_parent()
	return null

func _delete_size(t: Node3D) -> Vector3:
	if t is House:
		match t.kind:
			"station": return Vector3(26.4, 1.7, 26.4)
			"moonbase": return Vector3(16.0, 6.0, 12.0)
			"two_story": return Vector3(5.8, 6.6, 5.8)
			"factory": return Vector3(8.6, 5.0, 8.6)
			"tower": return Vector3(4.6, 18.4, 4.6)
			"box": return Vector3(4.0, 3.4, 4.0)
			_: return Vector3(5.8, 3.9, 5.8)
	if t is Machine:
		return t.box_size + Vector3(0.4, 1.2, 0.4)   # stacks poke above the box
	return Vector3(1.6, 1.6, 1.6)

func _delete_center(t: Node3D) -> Vector3:
	if t is House and t.kind == "station":
		return t.global_position
	var sz := _delete_size(t)
	return t.global_position + t.global_transform.basis.y * (sz.y * 0.45)

## Red hologram over whatever the DELETE tool is aimed at, so a
## misclick is impossible: you always see what dies before it does.
func _update_hwreck_preview() -> void:
	var t: Node3D = _delete_target_under_crosshair() if _hwreck_mode else null
	if t != null and not is_instance_valid(t):
		t = null
	# a FREED target compares equal to null, so 'did it change' never
	# fired after a delete and the red box lingered. Purge stale refs
	# explicitly before comparing.
	if _hwreck_target != null and not is_instance_valid(_hwreck_target):
		_hwreck_target = null
		if _hwreck_hl and is_instance_valid(_hwreck_hl):
			_hwreck_hl.queue_free()
		_hwreck_hl = null
	if t != _hwreck_target:
		_hwreck_target = t
		if _hwreck_hl and is_instance_valid(_hwreck_hl):
			_hwreck_hl.queue_free()
		_hwreck_hl = null
		if t != null:
			_hwreck_hl = MeshInstance3D.new()
			var bm3 := BoxMesh.new()
			bm3.size = _delete_size(t)
			_hwreck_hl.mesh = bm3
			var m3 := StandardMaterial3D.new()
			m3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m3.cull_mode = BaseMaterial3D.CULL_DISABLED
			m3.albedo_color = Color(1.0, 0.14, 0.1, 0.26)
			_hwreck_hl.material_override = m3
			get_tree().current_scene.add_child(_hwreck_hl)
	if _hwreck_hl != null and t != null:
		_hwreck_hl.global_transform = Transform3D(
			t.global_transform.basis, _delete_center(t))
		# breathing pulse so it reads as a warning, not decoration
		var mm := _hwreck_hl.material_override as StandardMaterial3D
		mm.albedo_color.a = 0.18 + 0.12 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))

## DELETE tool: ONE click, no confirm -- the preview box IS the
## confirmation. Houses refund the kit; machines refund themselves.
func _hwreck_click() -> void:
	_cooldown = 0.3
	var t := _delete_target_under_crosshair()
	if t == null:
		Sfx.play("denied", -18.0)
		return
	if not Net.can_break(str(t.get_meta("owner", ""))):
		Sfx.play("denied")
		return
	if t is House:
		if not Game.creative:
			Inventory.give("housekit", 1)
		Destructible.spawn_debris(t.get_parent(), t.global_position,
			Vector3(2.2, 2.2, 2.2), Color("#c9b8a0"), Vector3.UP)
		Sfx.play("explode", -10.0)
		t.queue_free()
	elif t is Machine:
		t._on_destroyed(Vector3.UP)   # refunds itself + slots, drops cables

func _wreck_click() -> void:
	_cooldown = 0.3
	var hud = get_tree().get_first_node_in_group("hud")
	var f := _furn_under_crosshair()
	if f == null:
		Sfx.play("denied", -18.0)
		return
	if not Net.can_break(str(f.get_meta("owner", ""))):
		Sfx.play("denied")
		return
	if f.kind == "doorframe" and bool(f.get_meta("linked", false)):
		_collapse_door(f)
		if hud:
			hud.flash("door connection collapsed — doorways walled up")
	else:
		if not Game.creative:
			Inventory.give("plantfiber", 2)
		Destructible.spawn_debris(get_parent(),
			f.global_position + Vector3(0, 0.8, 0),
			Vector3(1.0, 1.0, 1.0), Color("#7a5a34"), Vector3.UP)
		f.queue_free()
	Sfx.play("explode", -14.0)

## Destroying a LINKED doorframe collapses the whole connection: the
## link is severed, BOTH frames go, and each doorway is walled back up.
func _collapse_door(f: Furniture) -> void:
	var partner: Furniture = null
	for o in get_tree().get_nodes_in_group("doorframe"):
		if o != f and o is Furniture and is_instance_valid(o) \
				and bool(o.get_meta("linked", false)) \
				and o.global_position.distance_to(f.global_position) < 9.5:
			partner = o
			break
	var ha = House.house_at(f.global_position)
	var hb = House.house_at(partner.global_position) if partner != null else null
	if ha != null and hb != null:
		ha.links.erase(hb.slot)
		hb.links.erase(ha.slot)
	var frames: Array = [f]
	if partner != null:
		frames.append(partner)
	for fr in frames:
		var plug := StaticBody3D.new()
		var pm := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(2.4, 3.2, 0.5)
		pm.mesh = pbm
		pm.material_override = Surfaces.plaster(Color("#b8b0a0"))
		plug.add_child(pm)
		var pc2 := CollisionShape3D.new()
		var ps2 := BoxShape3D.new()
		ps2.size = Vector3(2.4, 3.2, 0.5)
		pc2.shape = ps2
		plug.add_child(pc2)
		get_parent().add_child(plug)
		plug.global_transform = Transform3D(fr.global_transform.basis,
			fr.global_position + Vector3(0, 1.5, 0) \
			- fr.global_transform.basis.z * 0.4)
		Inventory.give("plantfiber", 2)
		fr.queue_free()

## A tabletop HOLOGRAM floating over the frame: every room of each
## complex as a translucent box, set 1+ drawn at its DOCKED position.
func _door_holo(anchor: Node3D, sets: Array, delta_b: Vector3, secs: float) -> void:
	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_position = anchor.global_position + Vector3(0, 2.5, 0)
	var sc := 0.02
	var origin: Vector3 = anchor.global_position
	for si in sets.size():
		var hh0 = sets[si][0]
		var colr: Color = sets[si][1]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(colr.r, colr.g, colr.b, 0.4)
		mat.emission_enabled = true
		mat.emission = colr
		mat.emission_energy_multiplier = 0.8
		for h in hh0.complex():
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = h.room_size() * sc
			mi.mesh = bm
			mi.material_override = mat
			root.add_child(mi)
			var off: Vector3 = h.room_center() - origin
			if si > 0:
				off += delta_b
			mi.position = off * sc
	get_tree().create_timer(secs).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())

func _start_ghost(cat: String, kind: String) -> void:
	if cat == "house" and Game.zone != "":
		Sfx.play("denied")   # a house inside a house is asking for trouble
		return
	if kind == "station" and Game.zone != "":
		Sfx.play("denied")
		return
	if kind == "station":
		var hudg = get_tree().get_first_node_in_group("hud")
		if hudg:
			hudg.flash("RING SNAP %s — [T] toggles · hold CTRL to place free (no dock)" % ("ON" if _ring_snap else "OFF"))
	_ghost_cat = cat
	_ghost_kind = kind
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	if cat == "house":
		var w := 5.0
		var hh := 3.4
		match kind:
			"station":
				w = 26.0
				hh = 1.2
			"two_story": hh = 6.2
			"factory":
				w = 8.0
				hh = 4.5
			"tower":
				w = 4.0
				hh = 18.0
			"box":
				w = 3.4
				hh = 3.0
		bm.size = Vector3(w, hh, w)
	else:
		match kind:
			"carpet":
				bm.size = Vector3(4.4, 0.08, 3.2)
			"bench":
				bm.size = Vector3(1.9, 1.1, 0.7)
			"sofa":
				bm.size = Vector3(2.4, 1.2, 0.9)
			"bed":
				bm.size = Vector3(1.3, 0.8, 2.4)
			"catwalk":
				bm.size = Vector3(5.4, 2.3, 2.0)
			"moonbase":
				bm.size = Vector3(7.0, 3.5, 7.0)
			"doorframe":
				bm.size = Vector3(2.1, 2.8, 0.4)
			_:
				bm.size = Vector3(0.7, 1.1, 0.7)
	_ghost.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 1.0, 0.6, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = gm
	get_parent().add_child(_ghost)

## Docked transform for a station piece joining near_st. Sides are
## ranked by where you stand -- and standing dead-center (on a STACKED
## deck the probe is centered) falls back to where you LOOK. Sides
## already holding a station are skipped; all four taken -> null.
func _station_dock_tf(near_st: House, probe: Vector3):
	var gb: Basis = near_st.global_transform.basis
	var rel: Vector3 = gb.inverse() * (probe - near_st.global_position)
	var lookw: Vector3 = gb.inverse() * (-_camera.global_transform.basis.z)
	var sx := rel.x if absf(rel.x) > 0.8 else lookw.x * 26.0
	var sz := rel.z if absf(rel.z) > 0.8 else lookw.z * 26.0
	var vx := Vector3(26.0 * (1.0 if sx >= 0.0 else -1.0), 0, 0)
	var vz := Vector3(0, 0, 26.0 * (1.0 if sz >= 0.0 else -1.0))
	var cands: Array = [vx, vz, -vz, -vx] if absf(sx) >= absf(sz) \
		else [vz, vx, -vx, -vz]
	for side_v in cands:
		var tf := _dock_tf_for(near_st, side_v)
		var free := true
		for h in get_tree().get_nodes_in_group("house"):
			if h is House and h != near_st and h.kind == "station" \
					and is_instance_valid(h):
				var lrel: Vector3 = gb.inverse() * (h.global_position - tf.origin)
				if absf(lrel.y) < 2.0 and absf(lrel.x) < 20.0 and absf(lrel.z) < 20.0:
					free = false
					break
		if free:
			return tf
	return null

## The raw dock math for ONE side. With ring snap the piece is ROTATED
## around the planet by the exact panel angle (2*atan(13/r)) so the
## edges kiss and a chain of decks closes into a ring instead of
## shearing off on a tangent.
func _dock_tf_for(near_st: House, side_v: Vector3) -> Transform3D:
	var gb: Basis = near_st.global_transform.basis
	if _ring_snap:
		var b = Universe.nearest(near_st.global_position)
		if b != null:
			var np: Vector3 = near_st.global_position
			var r := np.distance_to(b.center)
			var sd: Vector3 = (gb * side_v).normalized()
			var u: Vector3 = (np - b.center).normalized()
			var ax: Vector3 = sd.cross(u)
			if r > 27.0 and ax.length() > 0.3:
				var rot := Basis(ax.normalized(), -2.0 * atan(13.0 / r))
				return Transform3D((rot * gb).orthonormalized(),
					b.center + rot * (np - b.center))
	return Transform3D(gb, near_st.global_position + gb * side_v)

func _update_ghost() -> void:
	if _ghost == null:
		return
	if _ghost_cat == "house" and _ghost_kind == "station":
		# stations preview UNDER YOUR FEET -- and near another station,
		# the preview SNAPS to the docked position so you see exactly
		# where the decks will join before you click
		var upS := global_transform.basis.y
		var foot := global_position - upS * 1.6
		var near_g: House = null
		var ngd := 45.0
		if not Input.is_key_pressed(KEY_CTRL):   # CTRL: place free, no dock
			for h in get_tree().get_nodes_in_group("house"):
				if h is House and h.kind == "station" and is_instance_valid(h):
					var d: float = h.global_position.distance_to(foot)
					if d < ngd:
						ngd = d
						near_g = h
		_ghost_dock = null
		if near_g != null:
			var dock = _station_dock_tf(near_g, foot)
			if dock != null:
				_ghost_dock = dock   # what you SEE is what gets placed
				_ghost.global_transform = Transform3D(dock.basis,
					dock.origin + dock.basis.y * 0.6)
			else:
				# every edge taken: preview floats free underfoot
				_ghost.global_transform = Transform3D(_basis_from_up(upS), foot)
				_ghost.rotate_object_local(Vector3.UP, _ghost_yaw)
		else:
			_ghost.global_transform = Transform3D(_basis_from_up(upS), foot)
			_ghost.rotate_object_local(Vector3.UP, _ghost_yaw)
		_ghost.visible = true
		return
	var sp := get_world_3d().direct_space_state
	var f := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(f, f - _camera.global_transform.basis.z * 22.0)
	q.exclude = [get_rid()]
	var hit := sp.intersect_ray(q)
	if hit:
		var up2: Vector3 = (hit.position - Universe.nearest(hit.position).center).normalized()
		if Game.zone != "":
			up2 = Vector3.UP
		if _ghost_cat == "furn":
			# furniture stands on FLOORS: if you aimed at a wall, drop
			# the point to the ground beneath it
			var q2 := PhysicsRayQueryParameters3D.create(
				hit.position + up2 * 0.3, hit.position - up2 * 8.0)
			q2.exclude = [get_rid()]
			var hit2 := sp.intersect_ray(q2)
			if hit2:
				hit.position = hit2.position
		_ghost.global_transform = Transform3D(_basis_from_up(up2),
			hit.position + up2 * (_ghost.mesh.size.y * 0.5 if _ghost_cat == "house" else 0.4))
		_ghost.rotate_object_local(Vector3.UP, _ghost_yaw)
		_ghost.visible = true
	else:
		_ghost.visible = false

func _confirm_ghost() -> void:
	if _ghost == null or not _ghost.visible:
		return
	var tf := _ghost.global_transform
	var base_pos: Vector3 = tf.origin - tf.basis.y * (_ghost.mesh.size.y * 0.5 if _ghost_cat == "house" else 0.4)
	if _ghost_cat == "house" and _ghost_kind == "station":
		# SPACE ONLY, and stations SNAP to each other edge-to-edge
		var hudn = get_tree().get_first_node_in_group("hud")
		var sbasis := tf.basis
		var spos := base_pos
		if _ghost_dock != null:
			# the placement IS the preview -- same transform, no re-deriving
			sbasis = _ghost_dock.basis
			spos = _ghost_dock.origin
		else:
			var nb3 = Universe.nearest(base_pos)
			# NEXT TO planets is the whole point (orbit!) -- just not
			# inside the terrain. planet gravity still applies; the
			# station simply adds none of its own.
			if base_pos.distance_to(nb3.center) < float(nb3.radius) + 6.0:
				Sfx.play("denied")
				if hudn:
					hudn.flash("clear the terrain first — a few meters up will do")
				_cancel_ghost()
				return
			sbasis = _basis_from_up(global_transform.basis.y)
		var sn := House.new()
		sn.kind = "station"
		get_parent().add_child(sn)
		sn.set_meta("placed_id", "house")
		sn.set_meta("owner", Net.my_name())
		sn.global_transform = Transform3D(sbasis, spos)
		if not Game.creative:
			Inventory.remove_res("housekit", 1)
		Sfx.play("place")
		_cancel_ghost()
		return
	if _ghost_cat == "house":
		var hn := House.new()
		hn.kind = _ghost_kind
		get_parent().add_child(hn)
		hn.set_meta("placed_id", "house")
		hn.set_meta("owner", Net.my_name())
		# aiming at a station deck? the house BUILDS ON IT, aligned
		var hdeck := _deck_under_crosshair()
		if hdeck != null:
			hn.global_transform = Transform3D(hdeck.global_transform.basis,
				_deck_hit + hdeck.global_transform.basis.y * 0.6)
		else:
			hn.global_transform = Transform3D(tf.basis, base_pos)
			hn.rotate_object_local(Vector3.UP, randf() * TAU)
		if not Game.creative:
			Inventory.remove_res("housekit", 1)
		Sfx.play("place")
	else:
		if _ghost_kind in ["catwalk", "doorframe"] and Game.zone == "":
			Sfx.play("denied")   # indoor equipment. read the label.
			_cancel_ghost()
			return
		if not Game.creative:
			if Inventory.res_count("plantfiber") < 2:
				Sfx.play("denied")
				_cancel_ghost()
				return
			Inventory.remove_res("plantfiber", 2)
		if _ghost_kind == "doorframe":
			var hh2 = House.house_at(base_pos)
			if hh2 != null:
				var rel: Vector3 = base_pos - hh2.room_center()
				var side := ""
				var outv := Vector3.ZERO
				if absf(rel.x) > absf(rel.z):
					side = "x+" if rel.x > 0.0 else "x-"
					outv = Vector3(signf(rel.x), 0, 0)
				else:
					side = "z+" if rel.z > 0.0 else "z-"
					outv = Vector3(0, 0, signf(rel.z))
				for fr2 in hh2.all_frames():
					var r3: Vector3 = fr2.global_position - hh2.room_center()
					var s2: String = ("x+" if r3.x > 0.0 else "x-") \
						if absf(r3.x) > absf(r3.z) \
						else ("z+" if r3.z > 0.0 else "z-")
					if s2 == side:
						Sfx.play("denied")
						var hud3 = get_tree().get_first_node_in_group("hud")
						if hud3:
							hud3.flash("ONE door frame per wall")
						_cancel_ghost()
						return
				# snap: the frame faces OUT through its wall (docking
				# throws the hallway out the local -Z)
				tf = Transform3D(Basis(Vector3.UP, atan2(-outv.x, -outv.z)), tf.origin)
		var fn := Furniture.new()
		fn.kind = _ghost_kind
		get_parent().add_child(fn)
		fn.set_meta("placed_id", "furn")
		fn.set_meta("owner", Net.my_name())
		fn.global_transform = Transform3D(tf.basis, base_pos)
		Sfx.play("place")
	_cancel_ghost()

func _cancel_ghost() -> void:
	_ghost_dock = null
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_cat = ""

func sit_on(seat: Node3D) -> void:
	seated = seat
	seat.set_meta("taken", true)
	velocity = Vector3.ZERO
	if _body and is_instance_valid(_body):
		_body.pose = 6   # the third-person body actually SITS

func _physics_process(delta: float) -> void:
	if Game.mode != Game.Mode.ON_FOOT:
		return
	# parked on a bench: pinned until a movement key. the humans sit on
	# their side, you sit on yours. equality.
	if _ghost != null:
		_update_ghost()
	if seated != null:
		if not is_instance_valid(seated):
			seated = null
		elif Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) \
				or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D) \
				or Input.is_key_pressed(KEY_SPACE):
			seated.set_meta("taken", false)
			var su := (global_position - Universe.nearest(global_position).center).normalized()
			global_position += su * 0.4
			seated = null
			if _body and is_instance_valid(_body):
				_body.pose = 0
			_head.rotation.y = 0.0
		else:
			var su2: Vector3 = seated.global_transform.basis.y
			global_position = seated.global_position + su2 * 0.6
			velocity = Vector3.ZERO
			# seated: the BODY stays put -- only the head turns
			if not _ui_open() and not Game.dead:
				var ssens := MOUSE_SENS * Settings.mouse_sensitivity
				_head.rotation.y = clampf(_head.rotation.y - _look.x * ssens,
					-1.5, 1.5)
				_pitch = clampf(_pitch - _look.y * ssens, -1.4, 1.4)
				_head.rotation.x = _pitch
			_look = Vector2.ZERO
			return
	# passenger seat: glued to the pilot's synced rocket, no physics of ours
	if riding_peer != -1:
		if not Net.active or not Net.player_pos.has(riding_peer):
			riding_peer = -1   # pilot gone: back on our own feet
		else:
			var seat_up: Vector3 = Net.player_ups.get(riding_peer, Vector3.UP)
			global_position = global_position.lerp(
				Net.player_pos[riding_peer] + seat_up * 1.6, minf(1.0, delta * 12.0))
			velocity = Vector3.ZERO
			return
	# C zooms whenever it isn't busy meaning "down" (jetpack/zero-g/fly modes)
	# V = zoom, always. C keeps meaning "down".
	_zooming = Input.is_key_pressed(KEY_V) and not _ui_open() and not Game.dead and not freecam
	if not _zooming:
		_zoom_extra = 1.0
	_zoom_f = lerpf(_zoom_f, 0.42 * _zoom_extra if _zooming else 1.0, delta * 9.0)
	_camera.fov = Settings.fov * _zoom_f

	# --- FREECAM: the camera flies, the body stays planted for its photo ---
	if freecam and _fc and is_instance_valid(_fc):
		if not _ui_open() and not Game.dead:
			var sens2 := MOUSE_SENS * Settings.mouse_sensitivity
			_fc.rotate_y(-_look.x * sens2)
			_fc.rotate_object_local(Vector3.RIGHT, -_look.y * sens2)
		_look = Vector2.ZERO
		if not _ui_open() and not Game.dead:
			var cb2 := _fc.global_transform.basis
			var fly2 := Vector3.ZERO
			if Input.is_key_pressed(KEY_W): fly2 -= cb2.z
			if Input.is_key_pressed(KEY_S): fly2 += cb2.z
			if Input.is_key_pressed(KEY_A): fly2 -= cb2.x
			if Input.is_key_pressed(KEY_D): fly2 += cb2.x
			if Input.is_key_pressed(KEY_SPACE): fly2 += cb2.y
			if Input.is_key_pressed(KEY_C): fly2 -= cb2.y
			if fly2.length() > 0.1:
				var spd2 := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 12.0
				_fc.global_position += fly2.normalized() * spd2 * delta
		velocity = Vector3.ZERO
		if _body:
			_body.animate(0.0, true, delta, false)
		return

	# --- NOCLIP: fully outside gravity. No alignment, no zones, no falls.
	# Camera keeps ITS orientation no matter what planet slides past. ---
	if noclip:
		if not _ui_open() and not Game.dead:
			var sens := MOUSE_SENS * Settings.mouse_sensitivity
			if _look.x != 0.0:
				rotate_object_local(Vector3.UP, -_look.x * sens)
			_pitch = clampf(_pitch - _look.y * sens, -1.4, 1.4)
			_head.rotation.x = _pitch
		_look = Vector2.ZERO
		if not _ui_open() and not Game.dead:
			var cb := _camera.global_transform.basis
			var fly := Vector3.ZERO
			if Input.is_key_pressed(KEY_W): fly -= cb.z
			if Input.is_key_pressed(KEY_S): fly += cb.z
			if Input.is_key_pressed(KEY_A): fly -= cb.x
			if Input.is_key_pressed(KEY_D): fly += cb.x
			if Input.is_key_pressed(KEY_SPACE): fly += global_transform.basis.y
			if Input.is_key_pressed(KEY_C): fly -= global_transform.basis.y
			if fly.length() > 0.1:
				var spd := 8000.0 if Input.is_key_pressed(KEY_SHIFT) else 600.0
				global_position += fly.normalized() * spd * delta
		velocity = Vector3.ZERO
		_update_shake(delta)
		_update_hand(delta)
		return

	# --- gravity frame: radial around planets, flat/zero inside pockets ---
	var up: Vector3
	match Game.zone:
		"flat":
			up = Vector3.UP
			_g = Game.zone_g
		"zero":
			up = Vector3.UP
			_g = 0.0
		_:
			var body := Universe.nearest(global_position)
			_g = body.g_surf
			up = Universe.surface_up(body, global_position)

	if not _ui_open() and not Game.dead:
		_align_up(up)
		var sens := MOUSE_SENS * Settings.mouse_sensitivity * _zoom_f
		if _look.x != 0.0:
			global_transform.basis = Basis(up, -_look.x * sens) * global_transform.basis
			global_transform.basis = global_transform.basis.orthonormalized()
		_pitch = clampf(_pitch - _look.y * sens, -1.4, 1.4)
		_head.rotation.x = _pitch
	_look = Vector2.ZERO

	# orbit-wand ride: one sideways kick at the top of the arc = orbit
	if _orbit_boost_t > 0.0:
		_orbit_boost_t -= delta
		if is_on_floor():
			_orbit_boost_t = 0.0
		else:
			var ob = Universe.nearest(global_position)
			var oup: Vector3 = (global_position - ob.center).normalized()
			var alt: float = global_position.distance_to(ob.center)
			if alt > ob.radius * 1.15 and velocity.dot(oup) <= 0.0:
				var vt := velocity - oup * velocity.dot(oup)
				if vt.length() < 0.5:
					vt = oup.cross(Vector3.UP)
					if vt.length() < 0.05:
						vt = oup.cross(Vector3.RIGHT)
				velocity = vt.normalized() * sqrt(ob.g_surf * ob.radius * ob.radius / alt)
				_orbit_boost_t = 0.0
				Sfx.play("warp", -14.0)

	var b := global_transform.basis
	var input := Vector3.ZERO
	if not _ui_open() and not Game.dead:
		if Input.is_key_pressed(KEY_W): input.z -= 1.0
		if Input.is_key_pressed(KEY_S): input.z += 1.0
		if Input.is_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_key_pressed(KEY_D): input.x += 1.0
	var wish := b.x * input.x + b.z * input.z
	wish = wish - up * wish.dot(up)
	wish = wish.normalized() if wish.length() > 0.01 else Vector3.ZERO

	var can_input := not _ui_open() and not Game.dead
	var jet_ok := _jetting and Inventory.has_jetpack and Inventory.jet_fuel > 0.0 and can_input

	if Game.zone == "zero":
		# ZERO-G: drift. Jetpack is your only authority.
		if jet_ok:
			var jp := JET_THRUST * Inventory.jet_power
			var thrust := wish * jp
			if Input.is_key_pressed(KEY_SPACE): thrust += up * jp
			if Input.is_key_pressed(KEY_C): thrust -= up * jp
			if thrust.length() > 0.1:
				velocity += thrust.normalized() * jp * delta
				Inventory.jet_fuel = maxf(0.0, Inventory.jet_fuel - JET_BURN * 0.6 * delta)
		velocity = velocity.lerp(Vector3.ZERO, delta * 0.15)
	elif is_on_floor() and not (jet_ok and Input.is_key_pressed(KEY_SPACE)):
		# WALK
		var v_up := maxf(velocity.dot(up), 0.0)
		if can_input and Input.is_key_pressed(KEY_SPACE):
			v_up = JUMP_VEL              # fixed launch -> low gravity jumps higher
		v_up -= _g * delta
		velocity = wish * WALK_SPEED + up * v_up
	else:
		# AIRBORNE free body: momentum + gravity. Barely steerable...
		if Game.zone == "":
			velocity += Universe.gravity_at(global_position) * delta
		else:
			velocity -= up * _g * delta
		if jet_ok:
			# ...unless the jetpack is on: Space up, C down, WASD real force.
			if Input.is_key_pressed(KEY_SPACE):
				velocity += up * JET_THRUST * Inventory.jet_power * delta
				Inventory.jet_fuel = maxf(0.0, Inventory.jet_fuel - JET_BURN * delta)
			if Input.is_key_pressed(KEY_C):
				velocity -= up * JET_THRUST * Inventory.jet_power * 0.8 * delta
				Inventory.jet_fuel = maxf(0.0, Inventory.jet_fuel - JET_BURN * 0.5 * delta)
			velocity += wish * AIR_ACCEL * delta
		else:
			velocity += wish * 1.2 * delta   # nearly no air control without jetpack
	# NOTE: jetpack stays toggled on at 0 fuel -- it just can't thrust
	# until you feed it another canister.

	up_direction = up
	move_and_slide()

	_cooldown -= delta
	if not _ui_open() and not Game.dead and not _door_mode and not _wreck_mode \
			and not _hwreck_mode \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cooldown <= 0.0:
		_fire()
		_cooldown = float(Inventory.current_weapon()["rate"])
	_update_shake(delta)
	_update_hand(delta)
	_update_hwreck_preview()
	_update_tool_hover()

	# third-person body animation + jetpack on the back
	if _body:
		var thrusting := jet_ok and (Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_C))
		_body.set_jetpack(Inventory.has_jetpack, thrusting,
			3 if Inventory.jet_max >= 1000.0 \
			else (2 if Inventory.jet_max >= 500.0 else 1))
		var hspd := (velocity - up * velocity.dot(up)).length()
		_body.animate(hspd, is_on_floor(), delta, thrusting)

const HAND_REST := Vector3(0.5, -0.45, -0.95)
const HAND_JAB := Vector3(0.26, -0.30, -1.55)

func _update_hand(delta: float) -> void:
	if not _hand:
		return
	_punch = maxf(0.0, _punch - delta / 0.22)      # ~0.22s total
	var e := 1.0 - _punch                          # progress 0..1
	# fast snap out (first 35%), smoother pull back
	var reach := (e / 0.35) if e < 0.35 else (1.0 - (e - 0.35) / 0.65)
	reach = clampf(reach, 0.0, 1.0)
	reach = reach * reach * (3.0 - 2.0 * reach)    # smoothstep
	_hand.position = HAND_REST.lerp(HAND_JAB, reach)
	_hand.rotation.x = -reach * 0.5
	_update_held()

func _update_held_layers() -> void:
	if _hand != null:
		_set_layers(_hand, 1 << 9)

func _update_held() -> void:
	if not _held:
		return
	for c in _held.get_children():
		c.queue_free()
	var id: String = Inventory.slot_id(Inventory.selected)
	if id == "" or id == "fists":
		_held.visible = false
		if _body and is_instance_valid(_body):
			_body.set_held(null)
			_apply_body_vis()
		return
	_held.visible = true
	_make_held_model(id)
	# mirror the model into the third-person hand
	if _body and is_instance_valid(_body):
		_body.set_held(_held.duplicate(), Inventory.weapons.has(id))
		# the body's copy joins the body layer: cameras see it, YOU don't
		# (no phantom second AK floating in first person)
		_apply_body_vis()

## Build the SAME model the hand would hold, as a free-standing node.
## Icons and dropped items borrow it so nothing is ever a mystery cube.
	_update_held_layers()

func model_for(id: String) -> Node3D:
	var keep := _held
	var out := Node3D.new()
	_held = out
	_make_held_model(id)
	_held = keep
	return out

# --- tiny in-hand models -------------------------------------------------

func _hm_box(sz: Vector3, pos: Vector3, col: Color, emit: float = 0.4) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.material_override = Destructible.make_material(col, emit)
	mi.position = pos
	_held.add_child(mi)
	return mi

func _hm_cyl(r: float, h: float, pos: Vector3, col: Color, emit: float = 0.4, top_r: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top_r < 0.0 else top_r
	m.height = h
	mi.mesh = m
	mi.material_override = Destructible.make_material(col, emit)
	mi.position = pos
	_held.add_child(mi)
	return mi

## Every placeable machine you hold IS the machine -- the real model,
## shrunk to hand size, turned so its face points screen-left. No more
## mystery cubes that look nothing like what you're about to place.
const HELD_MACHINE_IDS := ["chest", "furnace", "coinifier", "autominer",
	"spawnbeacon", "generator", "coaldrill", "bioreactor", "rtg", "prisreactor",
	"capacitor", "ultracap", "efurnace", "eseller", "atm", "ecomputer",
	"scomputer", "elight", "lightbox", "switch", "teleporter", "extender",
	"nreactor", "waypoint"]

func _held_machine(id: String) -> bool:
	if not HELD_MACHINE_IDS.has(id):
		return false
	var cs := get_tree().current_scene
	if cs == null or not cs.has_method("_spawn_world_obj"):
		return false
	var mach: Node3D = cs._spawn_world_obj(id)
	if mach == null:
		return false
	mach.process_mode = Node.PROCESS_MODE_DISABLED   # a model, not a machine
	_held.add_child(mach)
	_strip_held(mach)
	mach.scale = Vector3.ONE * 0.14
	mach.position = Vector3(0, -0.16, 0)
	mach.rotation_degrees = Vector3(0, -90, 0)   # face turned to the left
	return true

## Kill everything about the copy that isn't looks: collision (it would
## eat your own F-ray), labels, sensor areas.
func _strip_held(n: Node) -> void:
	if n is CollisionObject3D:
		n.collision_layer = 0
		n.collision_mask = 0
	if n is Area3D:
		n.monitoring = false
	if n is Label3D:
		n.visible = false
	for c in n.get_children():
		_strip_held(c)

func _make_held_model(id: String) -> void:
	if _held_machine(id):
		return
	var col := _held_color(id)
	var dark := Color("#2a2a30")
	if Inventory.weapons.has(id):
		match id:
			"ak47":
				var wood := Color("#7a4a22")
				var metal := Color("#23252a")
				_hm_box(Vector3(0.09, 0.13, 0.34), Vector3(0, 0.01, 0.1), metal, 0.15)      # receiver
				_hm_box(Vector3(0.08, 0.11, 0.22), Vector3(0, 0.1, 0.42), wood, 0.1)        # stock (slopes up-back)
				_hm_box(Vector3(0.08, 0.05, 0.14), Vector3(0, -0.02, 0.31), wood, 0.1)      # grip wrist
				_hm_box(Vector3(0.06, 0.14, 0.07), Vector3(0, -0.12, 0.2), wood, 0.1)       # pistol grip
				var mag := _hm_box(Vector3(0.055, 0.2, 0.09), Vector3(0, -0.14, 0.02), metal, 0.15)
				mag.rotation_degrees = Vector3(-18, 0, 0)                                    # curved-forward mag
				_hm_box(Vector3(0.08, 0.08, 0.24), Vector3(0, 0.0, -0.16), wood, 0.1)       # handguard
				_hm_cyl(0.022, 0.34, Vector3(0, 0.02, -0.4), metal, 0.2).rotation_degrees = Vector3(90, 0, 0)  # barrel
				_hm_cyl(0.018, 0.05, Vector3(0, 0.02, -0.52), metal, 0.2).rotation_degrees = Vector3(90, 0, 0) # muzzle brake
				_hm_box(Vector3(0.02, 0.07, 0.02), Vector3(0, 0.07, -0.44), metal, 0.15)    # front sight post
				return
			"knife":
				_hm_box(Vector3(0.07, 0.09, 0.22), Vector3(0, -0.02, 0.18), Color("#4a3020"), 0.1)
				_hm_box(Vector3(0.025, 0.11, 0.42), Vector3(0, 0.02, -0.14), Color("#d8d8e2"), 0.7)
			"voidhammer":
				_hm_cyl(0.035, 0.6, Vector3(0, 0, 0.05), Color("#3a2a4a"), 0.2).rotation_degrees = Vector3(90, 0, 0)
				_hm_box(Vector3(0.3, 0.2, 0.2), Vector3(0, 0, -0.32), col, 1.4)
			"rail":
				_hm_box(Vector3(0.2, 0.22, 0.5), Vector3(0, 0, 0.1), dark, 0.2)
				_hm_cyl(0.05, 0.8, Vector3(0, 0.02, -0.4), col, 1.0).rotation_degrees = Vector3(90, 0, 0)
				_hm_box(Vector3(0.08, 0.2, 0.1), Vector3(0, -0.18, 0.25), dark, 0.1)
			"raygun":
				_hm_box(Vector3(0.12, 0.14, 0.3), Vector3(0, 0, 0.1), dark, 0.2)
				_hm_cyl(0.04, 0.4, Vector3(0, 0.02, -0.2), col, 1.2).rotation_degrees = Vector3(90, 0, 0)
				_hm_cyl(0.11, 0.04, Vector3(0, 0.02, -0.38), col, 1.6).rotation_degrees = Vector3(90, 0, 0)
				_hm_box(Vector3(0.07, 0.18, 0.09), Vector3(0, -0.14, 0.2), dark, 0.1)
			_:
				# generic gun: body + barrel + grip, tinted per weapon
				_hm_box(Vector3(0.14, 0.16, 0.4), Vector3(0, 0, 0.12), dark, 0.2)
				_hm_cyl(0.035, 0.55, Vector3(0, 0.03, -0.25), col, 0.9).rotation_degrees = Vector3(90, 0, 0)
				_hm_box(Vector3(0.07, 0.2, 0.1), Vector3(0, -0.16, 0.26), dark, 0.1)
		return
	match id:
		"rocket":
			_hm_cyl(0.11, 0.42, Vector3(0, -0.05, 0), Color("#d8d8e0"), 0.4)
			_hm_cyl(0.11, 0.16, Vector3(0, 0.24, 0), Color("#ff5964"), 0.6, 0.0)
			for fx in [-0.12, 0.12]:
				_hm_box(Vector3(0.05, 0.14, 0.02), Vector3(fx, -0.22, 0), Color("#ff5964"), 0.4)
		"nchip":
			# the neuralink chip: a proper little implant, not a pebble --
			# rounded disc, gold pin ring, glowing trace cross
			var chip := _hm_cyl(0.11, 0.035, Vector3(0, 0, 0), Color("#e8ecf2"), 0.25)
			chip.rotation_degrees = Vector3(90, 0, 0)
			for pang in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
				var pin := _hm_cyl(0.008, 0.05, Vector3(cos(deg_to_rad(pang)) * 0.08,
					0, sin(deg_to_rad(pang)) * 0.08 - 0.0), Color("#c8a030"), 0.4)
				pin.rotation_degrees = Vector3(0, 0, 0)
			_hm_box(Vector3(0.12, 0.012, 0.015), Vector3(0, 0.022, 0), Color("#7be8ff"), 2.0)
			_hm_box(Vector3(0.015, 0.012, 0.12), Vector3(0, 0.022, 0), Color("#7be8ff"), 2.0)
			_hm_box(Vector3(0.04, 0.014, 0.04), Vector3(0, 0.028, 0), Color("#2a2f38"), 0.3)
		"housekit":
			# rolled blueprint + the little demo house from the box art
			_hm_cyl(0.05, 0.42, Vector3(-0.14, 0.02, 0), Color("#7cb8ff"), 0.5).rotation_degrees = Vector3(0, 0, 90)
			_hm_box(Vector3(0.22, 0.16, 0.22), Vector3(0.1, -0.05, 0), Color("#c9b8a0"), 0.2)
			var kroof := MeshInstance3D.new()
			var krm := CylinderMesh.new()
			krm.top_radius = 0.0
			krm.bottom_radius = 0.17
			krm.height = 0.14
			krm.radial_segments = 4
			kroof.mesh = krm
			kroof.position = Vector3(0.1, 0.1, 0)
			kroof.rotation_degrees.y = 45.0
			kroof.material_override = Destructible.make_material(Color("#7a4a3a"), 0.15)
			_held.add_child(kroof)
			_hm_box(Vector3(0.05, 0.08, 0.01), Vector3(0.1, -0.09, 0.11), Color("#4a3a28"), 0.1)
		"furnkit":
			# the placer: wooden mallet + a pocket chair sample
			var khandle := _hm_cyl(0.03, 0.3, Vector3(-0.12, -0.02, 0), Color("#7a5a34"), 0.2)
			khandle.rotation_degrees = Vector3(0, 0, 12)
			_hm_box(Vector3(0.16, 0.09, 0.09), Vector3(-0.15, 0.14, 0), Color("#5a4428"), 0.2)
			_hm_box(Vector3(0.12, 0.02, 0.1), Vector3(0.12, 0.0, 0), Color("#7a5a34"), 0.25)
			_hm_box(Vector3(0.12, 0.11, 0.02), Vector3(0.12, 0.06, 0.05), Color("#7a5a34"), 0.25)
			for klx in [-0.045, 0.045]:
				_hm_box(Vector3(0.02, 0.07, 0.02), Vector3(0.12 + klx, -0.05, 0), Color("#3a3a3e"), 0.1)
		"cage", "caged_animal", "caged_human":
			var cm2 := IconLib.build_model(id, get_tree())
			cm2.scale = Vector3(0.55, 0.55, 0.55)
			_held.add_child(cm2)
		"jetpack", "jetpack2", "jetpack3":
			var jmat: Material = null
			if id == "jetpack3":
				jmat = Human._prism_material()
			elif id == "jetpack2":
				jmat = Surfaces.portal(Color("#16394a"))   # dim portal glow
			for fx in [-0.11, 0.11]:
				var tk := _hm_cyl(0.09, 0.4, Vector3(fx, 0, 0), col, 0.6)
				var tip := _hm_cyl(0.09, 0.08, Vector3(fx, 0.24, 0), col.lightened(0.3), 0.9, 0.0)
				if jmat != null:
					tk.material_override = jmat
					tip.material_override = jmat
			_hm_box(Vector3(0.3, 0.16, 0.06), Vector3(0, -0.05, 0.1), dark, 0.2)
		"jetfuel", "fuel":
			var cc := Color("#ffd166") if id == "jetfuel" else Color("#ff8844")
			_hm_cyl(0.12, 0.36, Vector3(0, 0, 0), cc, 0.6)
			_hm_cyl(0.05, 0.08, Vector3(0, 0.22, 0), Color("#888890"), 0.3)
		"jetfuel4":
			for gx in [[-0.08, -0.08], [-0.08, 0.08], [0.08, -0.08], [0.08, 0.08]]:
				_hm_cyl(0.075, 0.4, Vector3(gx[0], 0, gx[1]), Color("#ffb347"), 0.6)
				_hm_cyl(0.03, 0.06, Vector3(gx[0], 0.23, gx[1]), Color("#888890"), 0.3)
		"tankxl":
			_hm_cyl(0.16, 0.42, Vector3(0, 0, 0), Color("#ffa040"), 0.6)
			_hm_cyl(0.06, 0.1, Vector3(0, 0.26, 0), Color("#888890"), 0.3)
		"spawnbeacon":
			_hm_box(Vector3(0.4, 0.04, 0.4), Vector3(0, -0.06, 0), Color("#1a2a20"), 0.2)
			_hm_box(Vector3(0.3, 0.05, 0.3), Vector3(0, -0.02, 0), Color("#2bff6a"), 1.4)
		"locator":
			_hm_box(Vector3(0.26, 0.34, 0.1), Vector3(0, 0, 0), Color("#8a9099"), 0.25)
			_hm_box(Vector3(0.18, 0.14, 0.02), Vector3(0, 0.05, -0.06), Color("#2bff6a"), 2.0)
			_hm_box(Vector3(0.05, 0.05, 0.02), Vector3(-0.07, -0.1, -0.06), Color("#33343a"), 0.1)
			_hm_box(Vector3(0.05, 0.05, 0.02), Vector3(0.02, -0.1, -0.06), Color("#33343a"), 0.1)
			_hm_cyl(0.012, 0.3, Vector3(0.1, 0.3, 0), Color("#b8bcc8"), 0.4)
			var tip2 := MeshInstance3D.new()
			var tm2 := SphereMesh.new()
			tm2.radius = 0.03
			tm2.height = 0.06
			tip2.mesh = tm2
			tip2.position = Vector3(0.1, 0.45, 0)
			tip2.material_override = Destructible.make_material(Color("#ff4444"), 3.0)
			_held.add_child(tip2)
		"orbitwand":
			_hm_cyl(0.025, 0.5, Vector3(0, 0, 0.05), Color("#3a2a4a"), 0.3).rotation_degrees = Vector3(90, 0, 0)
			var ring := MeshInstance3D.new()
			var rm2 := TorusMesh.new()
			rm2.inner_radius = 0.07
			rm2.outer_radius = 0.11
			ring.mesh = rm2
			ring.position = Vector3(0, 0, -0.28)
			ring.material_override = Destructible.make_material(Color("#9a6bff"), 2.0)
			_held.add_child(ring)
			var orb := MeshInstance3D.new()
			var om := SphereMesh.new()
			om.radius = 0.05
			om.height = 0.1
			orb.mesh = om
			orb.position = Vector3(0, 0, -0.28)
			orb.material_override = Destructible.make_material(Color("#d0b8ff"), 3.0)
			_held.add_child(orb)
		"wire":
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.09
			tm.outer_radius = 0.16
			t.mesh = tm
			t.material_override = Destructible.make_material(Color("#4cc9f0"), 0.8)
			_held.add_child(t)
		"wiretool":
			# lineman's pliers with a wire spool on the hip of the handle
			_hm_box(Vector3(0.05, 0.05, 0.24), Vector3(-0.035, 0, 0.14), Color("#c03a3a"), 0.2).rotation_degrees = Vector3(0, 6, 0)
			_hm_box(Vector3(0.05, 0.05, 0.24), Vector3(0.035, 0, 0.14), Color("#c03a3a"), 0.2).rotation_degrees = Vector3(0, -6, 0)
			_hm_box(Vector3(0.04, 0.06, 0.14), Vector3(-0.02, 0, -0.08), Color("#8a8a94"), 0.3).rotation_degrees = Vector3(0, -8, 0)
			_hm_box(Vector3(0.04, 0.06, 0.14), Vector3(0.02, 0, -0.08), Color("#8a8a94"), 0.3).rotation_degrees = Vector3(0, 8, 0)
			var spool := _hm_cyl(0.08, 0.1, Vector3(0, -0.1, 0.2), Color("#5ad0ff"), 0.8)
			spool.rotation_degrees = Vector3(0, 0, 90)
		"funneltool":
			# a funnel on a grip: wide cone, spout, orange service handle
			_hm_cyl(0.16, 0.16, Vector3(0, 0.08, -0.1), Color("#ffa040"), 0.5, 0.05)
			_hm_cyl(0.035, 0.16, Vector3(0, -0.07, -0.1), Color("#c87830"), 0.4)
			_hm_box(Vector3(0.06, 0.07, 0.2), Vector3(0, -0.02, 0.12), Color("#2a2a30"), 0.2)
		"charm":
			var gem := _hm_box(Vector3(0.12, 0.16, 0.1), Vector3(0, -0.02, 0), Color("#b56cff"), 2.5)
			gem.rotation_degrees = Vector3(45, 0, 45)
			var loop := MeshInstance3D.new()
			var lm2 := TorusMesh.new()
			lm2.inner_radius = 0.05
			lm2.outer_radius = 0.08
			loop.mesh = lm2
			loop.position = Vector3(0, 0.14, 0)
			loop.material_override = Destructible.make_material(Color("#ffd166"), 0.6)
			_held.add_child(loop)
		"warpshard":
			var sh := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.14, 0.34, 0.1)
			sh.mesh = pm
			sh.rotation_degrees = Vector3(0, 0, 12)
			sh.material_override = Destructible.make_material(Color("#7cf9ff"), 2.5)
			_held.add_child(sh)
		"cage", "caged_animal":
			_hm_box(Vector3(0.34, 0.04, 0.34), Vector3(0, -0.16, 0), dark, 0.2)
			_hm_box(Vector3(0.34, 0.04, 0.34), Vector3(0, 0.16, 0), dark, 0.2)
			for bx in [-0.15, -0.05, 0.05, 0.15]:
				_hm_cyl(0.012, 0.32, Vector3(bx, 0, -0.15), Color("#b0b0b8"), 0.3)
				_hm_cyl(0.012, 0.32, Vector3(bx, 0, 0.15), Color("#b0b0b8"), 0.3)
			if id == "caged_animal":
				_hm_box(Vector3(0.16, 0.12, 0.16), Vector3(0, -0.08, 0), Color("#7d9c4a"), 0.4)
		"catfood":
			_hm_cyl(0.11, 0.16, Vector3(0, 0, 0), Color("#e8956a"), 0.4)
			_hm_box(Vector3(0.16, 0.02, 0.1), Vector3(0, 0.09, 0), Color("#c8c8d0"), 0.5)
		"noodle":
			_hm_cyl(0.15, 0.12, Vector3(0, -0.04, 0), Color("#e8e0d0"), 0.3, 0.11)
			for nx in [-0.06, 0.0, 0.06]:
				_hm_cyl(0.015, 0.16, Vector3(nx, 0.08, 0), Color("#ffcf40"), 0.8).rotation_degrees = Vector3(0, 0, nx * 120.0)
		"ward":
			_hm_cyl(0.05, 0.4, Vector3(0, 0, 0), Color("#5a3020"), 0.2)
			_hm_box(Vector3(0.2, 0.08, 0.06), Vector3(0, 0.14, 0), Color("#ff6aa0"), 1.2)
			_hm_box(Vector3(0.14, 0.08, 0.06), Vector3(0, 0.0, 0), Color("#ff6aa0"), 0.9)
		"permapple":
			var ap := MeshInstance3D.new()
			var am2 := SphereMesh.new()
			am2.radius = 0.14
			am2.height = 0.26
			ap.mesh = am2
			ap.material_override = Destructible.make_material(Color("#8b0000"), 1.2)
			_held.add_child(ap)
			_hm_cyl(0.015, 0.08, Vector3(0, 0.16, 0), Color("#4a3020"), 0.2)
		"banana":
			for i2 in 3:
				var seg := _hm_box(Vector3(0.07, 0.07, 0.14), Vector3(0, -0.02 + float(i2) * 0.035, -0.1 + float(i2) * 0.11), Color("#ffe135"), 0.5)
				seg.rotation_degrees = Vector3(-24.0 + float(i2) * 24.0, 0, 0)
		"shroom":
			_hm_cyl(0.05, 0.14, Vector3(0, -0.06, 0), Color("#e8e0d0"), 0.3)
			var cap2 := MeshInstance3D.new()
			var cm2 := SphereMesh.new()
			cm2.radius = 0.13
			cm2.height = 0.14
			cm2.is_hemisphere = true
			cap2.mesh = cm2
			cap2.position = Vector3(0, 0.01, 0)
			cap2.material_override = Destructible.make_material(Color("#d13a3a"), 0.6)
			_held.add_child(cap2)
		"meat", "cooked_meat":
			var mc := Color("#c05050") if id == "meat" else Color("#8a4a2a")
			_hm_box(Vector3(0.14, 0.12, 0.2), Vector3(0, 0, -0.04), mc, 0.3)
			_hm_cyl(0.025, 0.16, Vector3(0, 0, 0.14), Color("#e8e0d0"), 0.3).rotation_degrees = Vector3(90, 0, 0)
		"salad":
			_hm_cyl(0.15, 0.1, Vector3(0, -0.05, 0), Color("#3a5a2a"), 0.3, 0.12)
			for sx2 in [-0.06, 0.0, 0.06]:
				_hm_box(Vector3(0.07, 0.05, 0.07), Vector3(sx2, 0.03, sx2 * 0.5), Color("#7ddc5a"), 0.6)
		"backpack", "backpack2", "ubackpack":
			var bc2 := Color("#7d9c4a") if id == "backpack" else (Color("#ff7ce9") if id == "backpack2" else Color("#c86bff"))
			_hm_box(Vector3(0.26, 0.32, 0.14), Vector3(0, 0, 0), bc2, 0.4)
			_hm_box(Vector3(0.18, 0.12, 0.06), Vector3(0, 0.04, -0.1), bc2.darkened(0.3), 0.3)
			for sx3 in [-0.09, 0.09]:
				_hm_box(Vector3(0.04, 0.3, 0.02), Vector3(sx3, 0, 0.09), Color("#3a3a30"), 0.2)
		"hyperdrive":
			var hd := MeshInstance3D.new()
			var hm2 := TorusMesh.new()
			hm2.inner_radius = 0.09
			hm2.outer_radius = 0.16
			hd.mesh = hm2
			hd.material_override = Destructible.make_material(Color("#c86bff"), 2.0)
			_held.add_child(hd)
			_hm_cyl(0.05, 0.2, Vector3(0, 0, 0), Color("#3a2a4a"), 0.8).rotation_degrees = Vector3(90, 0, 0)
		"engine_mk2":
			_hm_cyl(0.14, 0.2, Vector3(0, 0.06, 0), Color("#ff8c42"), 0.5, 0.08)
			_hm_cyl(0.16, 0.12, Vector3(0, -0.1, 0), Color("#2a2a30"), 0.9, 0.2)
		"carkeys":
			_hm_cyl(0.06, 0.02, Vector3(0, 0.08, 0), Color("#4dff9a"), 0.8)
			_hm_box(Vector3(0.035, 0.18, 0.015), Vector3(0, -0.05, 0), Color("#c8c8d0"), 0.5)
			_hm_box(Vector3(0.06, 0.02, 0.015), Vector3(0.02, -0.13, 0), Color("#c8c8d0"), 0.5)
		"rcs":
			_hm_box(Vector3(0.18, 0.18, 0.18), Vector3.ZERO, Color("#8fe8ff"), 0.5)
			for rd in [Vector3(0.12, 0, 0), Vector3(-0.12, 0, 0), Vector3(0, 0.12, 0), Vector3(0, -0.12, 0)]:
				_hm_cyl(0.03, 0.07, rd, Color("#2a2a30"), 0.6, 0.05).rotation_degrees = \
					Vector3(0, 0, 90) if absf(rd.x) > 0.0 else Vector3.ZERO
		"plantfiber":
			for fx2 in [-0.04, 0.0, 0.04]:
				_hm_cyl(0.012, 0.3, Vector3(fx2, 0, fx2), Color("#4caf50"), 0.5).rotation_degrees = Vector3(0, 0, fx2 * 200.0)
		"coal":
			# a fist of glossy black lumps, not a grey mystery cube
			for lofs in [Vector3(0, -0.03, 0), Vector3(0.09, 0.02, 0.05),
					Vector3(-0.08, 0.04, -0.04), Vector3(0.01, 0.1, -0.07),
					Vector3(-0.03, 0.08, 0.07)]:
				var lump := _hm_box(Vector3(0.13, 0.1, 0.11), lofs, Color("#101014"), 0.03)
				lump.rotation_degrees = Vector3(lofs.x * 260.0, lofs.y * 340.0, lofs.z * 300.0)
		_:
			if Inventory.placeables.has(id):
				# mini machine: coloured body, dark base, glow dot
				_hm_box(Vector3(0.36, 0.3, 0.36), Vector3(0, 0.02, 0), col, 0.5)
				_hm_box(Vector3(0.42, 0.08, 0.42), Vector3(0, -0.17, 0), dark, 0.15)
				_hm_box(Vector3(0.08, 0.08, 0.02), Vector3(0, 0.06, -0.19), col.lightened(0.5), 2.0)
			else:
				_hm_box(Vector3(0.42, 0.42, 0.42), Vector3.ZERO, col, 0.6)

func _held_color(id: String) -> Color:
	if Inventory.weapons.has(id):
		return Inventory.weapons[id]["color"]
	if Inventory.items.has(id):
		return Inventory.items[id]["color"]
	match id:
		"rocket": return Color("#ff5964")
		"fuel", "jetfuel", "jetfuel4": return Color("#ffd166")
		"jetpack": return Color("#4cc9f0")
		"rcs": return Color("#8fe8ff")
		"spawnbeacon": return Color("#2bff6a")
		"ward", "noodle": return Color("#ff6aa0")
		"tankxl": return Color("#ffa040")
	return Color("#c0c0c0")

func _align_up(up: Vector3) -> void:
	var cur := global_transform.basis.y
	var axis := cur.cross(up)
	var ang := cur.angle_to(up)
	if axis.length() > 0.0001 and ang > 0.0001:
		global_transform.basis = Basis(axis.normalized(), ang) * global_transform.basis
		global_transform.basis = global_transform.basis.orthonormalized()

func _cancel_wire() -> void:
	if _wire_src and is_instance_valid(_wire_src):
		_wire_src.set_selected(false)
		Sfx.play("click", -16.0)
	_wire_src = null

func _fire() -> void:
	# left-click with a wiring tool: CUT the cable you're aiming at,
	# otherwise cancel the current selection
	if Inventory.slot_id(Inventory.selected) in ["wiretool", "funneltool"]:
		# hop THROUGH whatever is in the way (pads, props) hunting a cable
		var space2 := get_world_3d().direct_space_state
		var from2 := _camera.global_position
		var excl: Array = [get_rid()]
		for hop in 5:
			var q2 := PhysicsRayQueryParameters3D.create(from2, from2 - _camera.global_transform.basis.z * 10.0)
			q2.exclude = excl
			var hit2 := space2.intersect_ray(q2)
			if not hit2:
				break
			if hit2.collider is Machine.CableBody:
				var cb: Machine.CableBody = hit2.collider
				if is_instance_valid(cb.owner_m) and cb.owner_m.disconnect_wire(cb.dst_m, cb.kind_s):
					Inventory.give("wire", 1)
					Sfx.play("explode", -18.0)
					return
			excl.append(hit2.collider.get_rid())
		_cancel_wire()
		return
	if Inventory.slot_id(Inventory.selected) == "orbitwand":
		var sw := get_world_3d().direct_space_state
		var fw := _camera.global_position
		var qw := PhysicsRayQueryParameters3D.create(fw, fw - _camera.global_transform.basis.z * 140.0)
		qw.exclude = [get_rid()]
		var hw := sw.intersect_ray(qw)
		if hw:
			var tn: Node = hw.collider
			while tn:
				if tn is Enemy or tn is Animal:
					_launch_orbit(tn)
					return
				tn = tn.get_parent()
		Sfx.play("denied")
		return
	var w := Inventory.current_weapon()
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var to := from + dir * float(w["range"])
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end := to
	if hit:
		end = hit.position
		var c = hit.collider
		# the knife HARVESTS flora instead of smashing it
		if Inventory.slot_id(Inventory.selected) == "knife" and c.has_method("harvest"):
			c.harvest()
		elif c.has_meta("net_peer"):
			Net.hit_player(int(c.get_meta("net_peer")), float(w["dmg"]))
		elif c.has_method("take_damage"):
			c.take_damage(float(w["dmg"]), dir)
		elif c.has_method("destroy"):
			c.destroy(dir)
	_tracer(from - _camera.global_transform.basis.y * 0.25, end, w["color"])
	Sfx.play("shoot", -14.0)
	_shake = 0.12
	_punch = 1.0
	if _body and _body.visible:
		_body.punch()   # third-person jab too
	Net.punch()   # and everyone else sees the swing

func _tracer(a: Vector3, b: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	get_parent().add_child(mi)
	# method callable on mi: auto-disconnects if the scene frees it first
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

func _update_shake(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		_camera.h_offset = randf_range(-_shake, _shake) * 0.3
		_camera.v_offset = randf_range(-_shake, _shake) * 0.3
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

func _use_selected() -> void:
	if _ui_open() or Game.dead or Game.mode != Game.Mode.ON_FOOT:
		return
	var slot := Inventory.selected
	var id: String = Inventory.slot_id(slot)
	# right-click a PET (crosshair ON it) with anything that isn't
	# food/cage -> stay / follow
	if id not in ["catfood", "cage", "caged_animal", "caged_human"]:
		var sp2 := get_world_3d().direct_space_state
		var fp2 := _camera.global_position
		var qp2 := PhysicsRayQueryParameters3D.create(fp2, fp2 - _camera.global_transform.basis.z * 7.0)
		qp2.exclude = [get_rid()]
		var hp2 := sp2.intersect_ray(qp2)
		if hp2:
			var pn: Node = hp2.collider
			while pn:
				if pn is Animal and pn.is_in_group("pet"):
					pn.toggle_stay()
					return
				pn = pn.get_parent()
	if id == "":
		return
	if id == "locator":
		var lui = get_tree().get_first_node_in_group("locator_ui")
		if lui and lui.has_method("open"):
			lui.open()
		return
	# the wiring tools
	if id == "wiretool":
		_tool_connect("power")
		return
	if id == "funneltool":
		_tool_connect("item")
		return
	var body := Universe.nearest(global_position)
	var ahead := global_position - global_transform.basis.z * 3.0
	var up := (ahead - body.center).normalized()
	var place := body.center + up * body.radius
	# a SPACE STATION DECK under the crosshair hosts machines directly
	var deck := _deck_under_crosshair()
	if deck != null:
		up = deck.global_transform.basis.y
		place = _deck_hit + up * 0.0
	elif Game.zone != "":
		# indoors: machines go where you LOOK, snapped down to the
		# floor or a catwalk deck -- never embedded in a wall
		up = Vector3.UP
		var isp := get_world_3d().direct_space_state
		var f0 := _camera.global_position
		var iq := PhysicsRayQueryParameters3D.create(f0,
			f0 - _camera.global_transform.basis.z * 10.0)
		iq.exclude = [get_rid()]
		var ih := isp.intersect_ray(iq)
		if ih:
			var drop := PhysicsRayQueryParameters3D.create(
				ih.position + Vector3.UP * 0.3, ih.position + Vector3.DOWN * 8.0)
			drop.exclude = [get_rid()]
			var gh := isp.intersect_ray(drop)
			if gh and gh.normal.dot(Vector3.UP) > 0.7:
				place = gh.position
			else:
				Sfx.play("denied")   # that's a wall. walls hold paintings.
				return
		else:
			place = global_position - global_transform.basis.z * 3.0
	match id:
		"chest", "furnace", "coinifier", "autominer", "spawnbeacon", \
		"generator", "coaldrill", "bioreactor", "rtg", "prisreactor", "nreactor", "capacitor", "efurnace", "eseller", \
		"atm", "ecomputer", "scomputer", "ultracap", "elight", "lightbox", "switch", "teleporter", "extender", "bench", "nterm", "radio":
			if id in ["coaldrill", "autominer"] and Game.zone != "":
				Sfx.play("denied")   # nothing to drill in a pocket dimension
				return
			var n: Node3D
			match id:
				"chest": n = Chest.new()
				"furnace": n = Furnace.new()
				"coinifier": n = Coinifier.new()
				"autominer": n = AutoMiner.new()
				"spawnbeacon": n = SpawnBeacon.new()
				"generator": n = EMachines.Generator.new()
				"coaldrill": n = EMachines.CoalDrill.new()
				"bioreactor": n = EMachines.Bioreactor.new()
				"rtg": n = EMachines.RTG.new()
				"prisreactor": n = EMachines.PrismReactor.new()
				"nreactor": n = EMachines.NuclearReactor.new()
				"capacitor": n = EMachines.Capacitor.new()
				"efurnace": n = EMachines.EFurnace.new()
				"eseller": n = EMachines.ESeller.new()
				"atm": n = ATM.new()
				"ecomputer": n = Computers.EComputer.new()
				"scomputer": n = Computers.SorterComputer.new()
				"ultracap": n = EMachines.UltraCapacitor.new()
				"elight": n = EMachines.ELight.new()
				"lightbox": n = EMachines.LightBox.new()
				"switch": n = EMachines.Switch.new()
				"bench": n = Bench.new()
				"nterm": n = NeuralinkTerminal.new()
				"radio": n = RadioTower.new()
				"teleporter": n = EMachines.Teleporter.new()
				"extender": n = EMachines.Extender.new()
			get_parent().add_child(n)
			n.set_meta("placed_id", id)
			n.set_meta("owner", Net.my_name())
			n.global_transform = Transform3D(_basis_from_up(up), place)
			Net.broadcast_place(id, n.global_position, up)
			# spawn beacons place DORMANT -- press F to claim one
			Inventory.clear_slot(slot)
			Sfx.play("place")
		"waypoint":
			var wnode := Waypoint.new()
			# aiming at a rocket? the waypoint rides IT
			var wsp := get_world_3d().direct_space_state
			var wf := _camera.global_position
			var wq := PhysicsRayQueryParameters3D.create(wf, wf - _camera.global_transform.basis.z * 10.0)
			wq.exclude = [get_rid()]
			var wh := wsp.intersect_ray(wq)
			var wrk: Node = null
			if wh:
				var wn: Node = wh.collider
				while wn:
					if wn is Rocket:
						wrk = wn
						break
					wn = wn.get_parent()
			if wrk:
				wrk.add_child(wnode)
				wnode.set_meta("placed_id", "waypoint")
				wnode.set_meta("owner", Net.my_name())
				wnode.global_position = wh.position
			else:
				get_parent().add_child(wnode)
				wnode.set_meta("placed_id", "waypoint")
				wnode.set_meta("owner", Net.my_name())
				wnode.global_transform = Transform3D(_basis_from_up(up), place)
			Net.broadcast_place("waypoint", wnode.global_position, up)
			Inventory.remove_res("waypoint", 1)
			Sfx.play("place")
		"rocket", "rocket2":
			if Game.zone == "flat":
				# houses and temple interiors: no launch pads in pockets
				Sfx.play("denied")
				var hudr = get_tree().get_first_node_in_group("hud")
				if hudr:
					hudr.flash("can't place rockets in here")
				return
			var rk := Rocket.new()
			rk.mk2 = id == "rocket2"
			get_parent().add_child(rk)
			rk.set_meta("placed_id", id)
			rk.set_meta("owner", Net.my_name())
			# deep space: park it floating right in front of you
			var nb2 = Universe.nearest(global_position)
			if Game.zone == "" and global_position.distance_to(nb2.center) > nb2.radius + 40.0:
				up = global_transform.basis.y
				rk.global_transform = Transform3D(_rocket_basis(up),
					global_position - global_transform.basis.z * 10.0)
			else:
				rk.global_transform = Transform3D(_rocket_basis(up), place + up * 3.0)
			if Inventory.hyper_rockets > 0:   # this hull still has its drive
				Inventory.hyper_rockets -= 1
				rk.hyperdrive = true
			# rockets serialize their NOSE as "up", same as the world save
			Net.broadcast_place(id, rk.global_position, -rk.global_transform.basis.z)
			Inventory.clear_slot(slot)
			Sfx.play("place")
		"fuel":
			var r := _nearest_in("rocket", 8.0)
			if r:
				# Rocket 2.0: double-size tank AND canisters load double
				var fmult: float = 2.0 if (r is Rocket and r.mk2) else 1.0
				Inventory.fuel = minf(Inventory.fuel_max * fmult,
					Inventory.fuel + 50.0 * fmult)
				Inventory.clear_slot(slot)
				Sfx.play("smelt")
				Inventory.changed.emit()
			else:
				Sfx.play("denied")
		"hyperdrive":
			# ship equipment: install it ON a nearby rocket/starship
			var rh := _nearest_in("rocket", 8.0)
			if rh and rh is Rocket and not rh.hyperdrive:
				rh.hyperdrive = true
				Inventory.clear_slot(slot)
				Sfx.play("learn")
			else:
				Sfx.play("denied")
		"coil":
			var cm := _machine_under_crosshair()
			if cm and cm is Machine and not cm.has_coil:
				cm.add_coil()
				Inventory.clear_slot(slot)
				Sfx.play("learn")
			else:
				Sfx.play("denied")
		"backpack", "backpack2", "ubackpack":
			var ui := get_tree().get_first_node_in_group("storage_ui")
			if ui and ui.has_method("open_backpack"):
				ui.open_backpack(id)
		"permapple":
			_apple_prompt(slot)
		"cage":
			var an := _nearest_in("animal", 6.0)
			var hu := _nearest_in("earth_human", 6.0)
			if an and an is Animal:
				# store its GENOME -- the exact same creature comes back
				# out, even after saving and quitting
				Inventory.caged_data.append({
					"g": an.genome, "tamed": an.tamed,
					"ground": an._ground_only, "bug": an._bug,
				})
				an.queue_free()
				Inventory.clear_slot(slot)
				Inventory.give("caged_animal", 1)
				Sfx.play("place")
			elif hu and hu is EarthHuman:
				# humans fit in cages too. same guy comes back out --
				# name, face, shirt, grudges, everything
				hu._release_seat()
				Inventory.caged_data.append({"human": hu.capture()})
				IconLib._pool.erase("caged_human")   # the box has a new face
				hu.queue_free()
				Inventory.clear_slot(slot)
				Inventory.give("caged_human", 1)
				Sfx.play("place")
			else:
				Sfx.play("denied")
		"caged_animal":
			var body2 := Universe.nearest(global_position)
			# pop the newest ANIMAL box (humans travel under their own item)
			var d2: Dictionary = {}
			for ci in range(Inventory.caged_data.size() - 1, -1, -1):
				if not Inventory.caged_data[ci].has("human"):
					d2 = Inventory.caged_data[ci]
					Inventory.caged_data.remove_at(ci)
					break
			var out := Animal.new()
			if not d2.is_empty():
				out.setup(body2, bool(d2.get("ground", false)), bool(d2.get("bug", false)), int(d2.get("g", -1)))
				get_parent().add_child(out)
				if bool(d2.get("tamed", false)):
					out.tame()
			else:
				out.setup(body2)
				get_parent().add_child(out)
			out.global_position = place + up * 1.0
			out.flat_home = Game.zone == "flat"   # released indoors: floor pet
			Inventory.clear_slot(slot)
			Inventory.give("cage", 1)   # the cage survives
			Sfx.play("place")
		"caged_human":
			var bodyh := Universe.nearest(global_position)
			var dh: Dictionary = {}
			for ci in range(Inventory.caged_data.size() - 1, -1, -1):
				if Inventory.caged_data[ci].has("human"):
					dh = Inventory.caged_data[ci]
					Inventory.caged_data.remove_at(ci)
					break
			var outh := EarthHuman.new()
			if dh.has("human"):
				outh.saved = dh["human"]
			outh.setup(bodyh)
			get_parent().add_child(outh)
			outh.global_position = place + up * 1.0
			Inventory.clear_slot(slot)
			Inventory.give("cage", 1)   # the cage survives
			Sfx.play("place")
		"housekit":
			var hopts: Array = []
			for k in House.KINDS:
				hopts.append({"id": k, "label": {"small": "Small House",
					"two_story": "Two-Story House", "box": "Compact Box",
					"basement": "House w/ Basement", "factory": "Factory House",
					"tower": "Skyscraper", "moonbase": "Moonbase",
					"station": "Space Station Platform (SPACE only)"}[k]})
			hopts.append({"id": "demolish", "label": "DELETE (click a house)"})
			var pui := PickUI.new().configure("HOUSE TYPE", hopts,
				func(kind: String) -> void:
					if kind == "demolish":
						_hwreck_mode = true
						_door_mode = false
						_wreck_mode = false
						var hudh = get_tree().get_first_node_in_group("hud")
						if hudh:
							hudh.flash("DELETE — click any house or machine. ONE click. the red box shows what dies (right-click cancels)")
					else:
						_start_ghost("house", kind))
			get_tree().current_scene.add_child(pui)
		"furnkit":
			var fopts: Array = []
			for k2 in Furniture.KINDS:
				var lbl2: String = k2.capitalize()
				if k2 == "doorframe":
					lbl2 = "Door Frame (place INSIDE, on a wall)"
				fopts.append({"id": k2, "label": lbl2})
			fopts.append({"id": "door", "label": "Door Tool (click two door frames)"})
			fopts.append({"id": "wreck", "label": "DESTROY (click any furniture)"})
			var pui2 := PickUI.new().configure("FURNITURE (2 plantfiber)", fopts,
				func(kind: String) -> void:
					if kind == "door":
						_door_tool()
					elif kind == "wreck":
						_wreck_mode = true
						_door_mode = false
						var hudw = get_tree().get_first_node_in_group("hud")
						if hudw:
							hudw.flash("DESTROY — click furniture to break it (right-click cancels)")
					else:
						_start_ghost("furn", kind))
			get_tree().current_scene.add_child(pui2)
		"grenade":
			var gr := Grenade.new()
			get_parent().add_child(gr)
			gr.global_position = _camera.global_position - _camera.global_transform.basis.z * 1.0
			gr.vel = -_camera.global_transform.basis.z * 18.0 + global_transform.basis.y * 4.0
			Inventory.remove_res("grenade", 1)
			Sfx.play("click", -14.0)
		"nchip":
			# brain surgery, field edition: nearest head within reach
			var hu2 := _nearest_in("earth_human", 6.0)
			var an3 := _nearest_in("animal", 6.0)
			if hu2 and hu2 is EarthHuman:
				hu2.chipped = true
				hu2.add_chip_visual()
				Inventory.clear_slot(slot)
				Sfx.play("learn")
			elif an3 and an3 is Animal:
				an3.set_meta("chipped", true)
				Inventory.clear_slot(slot)
				Sfx.play("learn")
			else:
				Sfx.play("denied")
		"catfood":
			var an2 := _nearest_in("animal", 6.0)
			if an2 and an2 is Animal and not an2.tamed:
				an2.tame()
				Inventory.clear_slot(slot)
			else:
				Sfx.play("denied")
		_:
			Inventory.use_item(slot)

## The apple deserves ceremony: game pauses, mouse frees, and the run
## ends only on an explicit, deliberate click.
func _apple_prompt(slot: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 200)
	panel.size = Vector2(460, 200)
	panel.position = Vector2(-230, -100)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a0808")
	sb.border_color = Color("#8b0000")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 14)
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	panel.add_child(pad)
	pad.add_child(col)
	var q := Label.new()
	q.text = "Eat the apple?"
	q.add_theme_font_size_override("font_size", 26)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q)
	var warn := Label.new()
	warn.text = "(Warning: this will end your run)"
	warn.add_theme_font_size_override("font_size", 14)
	warn.modulate = Color("#ff5a5a")
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var eat := Button.new()
	eat.text = "Eat it"
	eat.custom_minimum_size = Vector2(160, 46)
	eat.modulate = Color("#ff8080")
	row.add_child(eat)
	var no := Button.new()
	no.text = "No"
	no.custom_minimum_size = Vector2(160, 46)
	row.add_child(no)

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	var closer := func(eaten: bool) -> void:
		layer.queue_free()
		get_tree().paused = false
		if eaten:
			Inventory.clear_slot(slot)
			if str(Inventory.equip.get("charm", "")) == "charm":
				Game.permadeath()   # the charm eats the death quietly
			else:
				# no charm, no mercy: roll the sendoff
				get_tree().current_scene.add_child(AppleCinematic.new())
		elif not Game.dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# two yeses to die: the first press only asks harder
	var armed := [false]
	eat.pressed.connect(func() -> void:
		if armed[0]:
			closer.call(true)
		else:
			armed[0] = true
			q.text = "Are you sure?"
			eat.text = "Yes"
			eat.modulate = Color("#ff4040")
			Sfx.play("denied", -12.0))
	no.pressed.connect(func() -> void: closer.call(false))

var _wire_src: Machine = null
var _wire_port: int = 1
var _hover_machine: Machine = null
var _apple_warn_t: float = -99.0

## Wiring/Funnel tool: first right-click selects the SOURCE machine
## (its output, glows white), second connects to the TARGET's input.
## Costs 1 Wire. Click the source again to cancel.
## While a multi-port source is selected, the scroll wheel picks the port.
func _port_picking() -> bool:
	if _wire_src == null or not is_instance_valid(_wire_src):
		return false
	var kind := "power" if Inventory.slot_id(Inventory.selected) == "wiretool" else "item"
	return _wire_src.port_count(kind) > 1

func _cycle_port(dir: int) -> void:
	var kind := "power" if Inventory.slot_id(Inventory.selected) == "wiretool" else "item"
	var maxp: int = _wire_src.port_count(kind)
	_wire_port = ((_wire_port - 1 + dir + maxp) % maxp) + 1
	Sfx.play("click", -18.0)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash("%s OUTPUT PORT %d" % [_wire_src.title, _wire_port])

func _tool_connect(kind: String) -> void:
	var m := _machine_under_crosshair()
	if m == null:
		Sfx.play("denied")
		return
	# coils: power-INPUT targets only
	if m is Machine.CoilNode and (kind != "power" or _wire_src == null):
		Sfx.play("denied")
		return
	if _wire_src == null or not is_instance_valid(_wire_src):
		_wire_src = m
		_wire_port = 1
		m.set_selected(true)
		Sfx.play("click")
		if m is Machine and m.port_count(kind) > 1:
			var hud2 := get_tree().get_first_node_in_group("hud")
			if hud2:
				hud2.flash("%s: scroll to pick OUTPUT PORT (1-%d)" % [m.title, m.port_count(kind)])
	elif _wire_src == m:
		m.set_selected(false)
		_wire_src = null
		Sfx.play("click", -14.0)
	else:
		# already connected? the tool CUTS it instead (wire refunded)
		if _wire_src.disconnect_wire(m, kind):
			Inventory.give("wire", 1)
			_wire_src.set_selected(false)
			_wire_src = null
			Sfx.play("explode", -18.0)
			return
		if not (Game.creative or Game.free_craft) \
				and Inventory.res_count("wire") < 1:
			Sfx.play("denied")
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash("no Wire. craft some (Electric tab).")
			return
		if not (Game.creative or Game.free_craft):
			Inventory.remove_res("wire", 1)
		var srcm = _wire_src
		var dstm = m
		if kind == "power" and srcm is Machine and dstm is Machine \
				and srcm.gen_rate <= 0.0 and dstm.gen_rate > 0.0:
			# sink -> source is backwards and delivers nothing; flip it so
			# the electricity actually arrives
			srcm = m
			dstm = _wire_src
			var hudf = get_tree().get_first_node_in_group("hud")
			if hudf:
				hudf.flash("wire flipped: power flows %s → %s" % [srcm.title, dstm.title])
		srcm.connect_wire(dstm, kind, _wire_port if srcm.port_count(kind) > 1 else 0)
		_wire_src.set_selected(false)
		_wire_src = null
		Sfx.play("learn")

func _machine_under_crosshair() -> Node3D:
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - _camera.global_transform.basis.z * 9.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n is Machine or n is Chest or n is Machine.CoilNode:
				return n
			n = n.get_parent()
	return null

## Holding a wiring tool: highlight whatever machine you're aiming at.
func _update_tool_hover() -> void:
	var held := Inventory.slot_id(Inventory.selected)
	var want := held in ["wiretool", "funneltool"]
	# put the tool away -> selection cancels itself
	if not want and _wire_src != null:
		_cancel_wire()
	var m := _machine_under_crosshair() if want else null
	if _hover_machine != m:
		if _hover_machine and is_instance_valid(_hover_machine):
			_hover_machine.set_hover(false)
		_hover_machine = m
		if _hover_machine:
			_hover_machine.set_hover(true)
	# role glow: BLUE = valid outputs (pick a source), GREEN = valid inputs
	var kind := "power" if held == "wiretool" else "item"
	var picking_target := _wire_src != null and is_instance_valid(_wire_src)
	for n in get_tree().get_nodes_in_group("machine"):
		if not (n is Machine or n is Machine.CoilNode):
			continue
		if not want or n == _wire_src:
			n.set_role_glow(0)
			continue
		if global_position.distance_to(n.global_position) > 50.0:
			n.set_role_glow(0)
			continue
		if picking_target:
			n.set_role_glow(2 if n.can_role(kind, true) else 0)
		else:
			n.set_role_glow(1 if n.can_role(kind, false) else 0)

## Rocket stands upright: its nose (local -Z) points along the surface up.
func _rocket_basis(up: Vector3) -> Basis:
	var z := -up
	var x := up.cross(Vector3(0, 1, 0))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z).orthonormalized()

var _orbit_boost_t: float = 0.0   # waiting to circularize at the top of the arc

## FLING a body skyward; at the top of the arc it gets one clean sideways
## kick onto a circular orbit. No teleporting -- you watch the whole ride.
func _launch_orbit(n: Node3D) -> void:
	var b = Universe.nearest(n.global_position)
	var up: Vector3 = (n.global_position - b.center).normalized()
	var tang := up.cross(Vector3.UP)
	if tang.length() < 0.05:
		tang = up.cross(Vector3.RIGHT)
	tang = tang.normalized()
	# vertical speed that coasts up to ~1.6R, plus a sideways nudge
	var v_up: float = sqrt(0.78 * b.g_surf * b.radius)
	var v0: Vector3 = up * v_up + tang * v_up * 0.22
	if n is Enemy or n is Animal:
		n.orbit_t = 600.0
		n.orbit_boost = true
		n.velocity = v0
	elif n == self:
		velocity = v0
		_orbit_boost_t = 40.0
	elif n is CharacterBody3D:
		n.velocity = v0
	elif "vel" in n:
		n.vel = v0
	Game.zone = ""   # you can't orbit inside a pocket dimension
	Sfx.play("warp", -8.0)
	_shake = 0.2

## The locator: single-instance targets ping alone, mine entrance pings the
## nearest one on this planet, swarm targets (invaders, rifts) ping ALL of
## them at once. 45s green HUD waypoints.
func locate(mode: int) -> void:
	Game.locator_mode = mode
	var label := ""
	var targets: Array = []
	match Game.locator_mode:
		0:
			label = "ALIEN SHIP"
			var best := 1e18
			for n in get_tree().get_nodes_in_group("starship"):
				var d2: float = global_position.distance_squared_to(n.global_position)
				if d2 < best:
					best = d2
					targets = [n.global_position]
		1:
			label = "SPACE INVADERS"
			for n in get_tree().get_nodes_in_group("invader"):
				targets.append(n.global_position)
		2:
			label = "SHADOW TEMPLE"
			targets = [Zones.SHADOW_POS]
		3:
			label = "UFO"
			var u = get_tree().get_first_node_in_group("ufo")
			if u:
				targets = [u.global_position]
		5:
			label = "MINE ENTRANCE"
			var cs2 := get_tree().current_scene
			if cs2 and cs2.has_method("mine_positions"):
				var best4 := 1e18
				for mpos in cs2.mine_positions():
					var d5: float = global_position.distance_squared_to(mpos)
					if d5 < best4:
						best4 = d5
						targets = [mpos]
		6:
			label = "CONNECT 4 ARENA"
			var c4 = get_tree().get_first_node_in_group("connect4")
			if c4:
				targets = [c4.global_position]
		4:
			label = "TIME RIFT"
			var cs := get_tree().current_scene
			var rifts = cs.get("_rifts") if cs else null
			if rifts is Array:
				for r in rifts:
					targets.append(r)
		7:
			label = "NOODLE GOD"
			var nwl = get_tree().get_first_node_in_group("noodle_watcher")
			if nwl != null and nwl is Node3D:
				targets = [nwl.global_position]
	var hud = get_tree().get_first_node_in_group("hud")
	if targets.is_empty():
		Game.locator_until = -1.0
		Sfx.play("denied", -16.0)
		if hud:
			hud.flash("LOCATOR: no %s found" % label)
		return
	Game.locator_targets = targets
	Game.locator_label = label
	# the god reads FALSE: the locator insists it's 4x farther than it is.
	# instruments agree it is enormous. instruments refuse to agree where.
	Game.locator_lie = 4.0 if Game.locator_mode == 7 else 1.0
	Game.locator_until = Game.playtime + 45.0
	Sfx.play("click", -10.0)
	if hud:
		if targets.size() > 1:
			hud.flash("LOCATOR: %s x%d" % [label, targets.size()])
		else:
			hud.flash("LOCATOR: " + label)

var riding_peer: int = -1   # sitting in a friend's Rocket 2.0 bubble

func _interact() -> void:
	# riding shotgun: F hops off
	if riding_peer != -1:
		riding_peer = -1
		var hud0 = get_tree().get_first_node_in_group("hud")
		if hud0:
			hud0.flash("hopped off")
		return
	# holding the ORBIT WAND: F sends YOU around the planet
	if Inventory.slot_id(Inventory.selected) == "orbitwand":
		_launch_orbit(self)
		return
	# FIRST: whatever you're LOOKING at (camera ray). Fallback: nearest.
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - _camera.global_transform.basis.z * 8.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var n: Node = hit.collider
		while n:
			if n.has_meta("net_pilot") and Net.active \
					and Net.player_names.has(int(n.get_meta("net_pilot"))):
				# only a LIVE pilot's rocket counts -- stale displays never
				# swallow your F press
				var hudp = get_tree().get_first_node_in_group("hud")
				if n.get_meta("net_mk2", false):
					riding_peer = int(n.get_meta("net_pilot"))
					if hudp:
						hudp.flash("riding with %s -- F to hop off" \
							% str(Net.player_names.get(riding_peer, "them")))
					Sfx.play("click")
				elif hudp:
					hudp.flash("no passenger seat -- only a Rocket 2.0 carries two")
				return
			if n is Gate or n is MengerShrine:
				n.use(self)
				return
			if n is SpawnBeacon:
				n.activate_spawn()
				Sfx.play("click")
				return
			if n is Starship and not n.repaired:
				n.try_repair()
				return
			if n is Rocket and not n.piloted:
				if Game.playtime >= Game.board_lock and n.has_method("board"):
					n.board(self)
				return
			if n.has_method("use") and not n is Player:
				n.use()
				return
			n = n.get_parent()

	# nothing under the crosshair = nothing happens. F is aim-only.
	Sfx.play("denied", -22.0)

func _nearest_in(grp: String, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for n in get_tree().get_nodes_in_group(grp):
		var d: float = global_position.distance_to(n.global_position)
		if d < bd:
			bd = d
			best = n
	return best

func respawn_at(pos: Vector3, up: Vector3) -> void:
	visible = true
	set_physics_process(true)
	if _hand:
		_hand.visible = _view_mode == 0
	if _body:
		_apply_body_vis()
	_camera.current = true
	global_position = pos
	global_transform.basis = _basis_from_up(up)
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _try_board() -> void:
	if Game.playtime < Game.board_lock:
		return   # just exited -- don't bounce straight back in
	for r in get_tree().get_nodes_in_group("rocket"):
		if global_position.distance_to(r.global_position) < 8.0 and r.has_method("board"):
			r.board(self)
			return

## Called by the rocket when boarding.
func enter_vehicle() -> void:
	visible = false
	set_physics_process(false)
	_camera.current = false

## Called by the rocket when disembarking onto a planet surface.
func exit_vehicle(pos: Vector3, up: Vector3) -> void:
	visible = true
	set_physics_process(true)
	global_position = pos
	global_transform.basis = _basis_from_up(up)
	velocity = Vector3.ZERO
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func god_throwback(to: Vector3) -> void:
	global_position = to
	velocity = Vector3.ZERO

func _basis_from_up(up: Vector3) -> Basis:
	var t := Vector3(0, 1, 0)
	if absf(up.dot(t)) > 0.99:
		t = Vector3(1, 0, 0)
	var x := t.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).orthonormalized()
