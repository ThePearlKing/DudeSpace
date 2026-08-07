class_name TVSet
extends Node
## TVs, the spy cameras they watch, and FORK TV -- the noodle god's own
## broadcast, rendered in a studio that exists inside a SubViewport and
## nowhere else. One studio feeds every screen in the universe.

static var cams: Dictionary = {}      # camera name -> SpyCam node
static var fork_channel := 0
static var _fork_vp: SubViewport = null
static var _fork_drv: Node = null
static var _dance_vp: SubViewport = null
static var dance_ping_ms := 0
static var fork_sub := ""             # current FORK TV subtitle line

const CHANNELS := ["THE DANCE", "NOODLE GOD TV", "MISSING DUDES",
	"COOKING WITH NOODLE", "EXERCISE HOUR"]

## ---------------------------------------------------------- FORK TV
## the studio lives inside its own SubViewport world: no pocket, no
## collisions, unreachable by anything but a screen.
## a small dedicated studio locked to THE DANCE, for machine screens.
## Renders only while something nearby keeps pinging it.
static func dance_feed(tree: SceneTree) -> SubViewport:
	if _dance_vp != null and is_instance_valid(_dance_vp):
		return _dance_vp
	_dance_vp = SubViewport.new()
	_dance_vp.size = Vector2i(200, 120)
	_dance_vp.own_world_3d = true
	_dance_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.current_scene.add_child(_dance_vp)
	var drv := _ForkStudio.new()
	drv.lock_channel = 0
	drv.sleepy = true
	_dance_vp.add_child(drv)
	return _dance_vp

static func fork_feed(tree: SceneTree) -> SubViewport:
	if _fork_vp != null and is_instance_valid(_fork_vp):
		return _fork_vp
	_fork_vp = SubViewport.new()
	_fork_vp.size = Vector2i(360, 220)
	_fork_vp.own_world_3d = true
	_fork_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.current_scene.add_child(_fork_vp)
	var drv := _ForkStudio.new()
	_fork_vp.add_child(drv)
	_fork_drv = drv
	return _fork_vp

class _ForkStudio extends Node3D:
	var lock_channel := -1     # >=0: this studio airs ONE channel forever
	var sleepy := false        # pauses its viewport when nobody pings
	var _t := 0.0
	var _sub_t := 0.0
	var _sub_i := 0
	var _body: Node3D
	var _eye: Node3D
	var _pupil: MeshInstance3D
	var _arm_l: Node3D
	var _arm_r: Node3D
	var _leg_l: Node3D
	var _leg_r: Node3D
	var _tents: Array = []
	var _props: Dictionary = {}   # channel -> prop root

	const SUBS := {
		1: ["welcome back to NOODLE GOD TV. i am the noodle god.",
			"today's topic: being watched. i am for it.",
			"the eye sees all. the eye is also very handsome.",
			"we will be right back. i never leave."],
		2: ["MISSING: several dudes. last seen going UP.",
			"i watched them go. nobody goes up. they went up.",
			"if you have seen these dudes, look UP and tell me.",
			"the posters are accurate. the dudes are not here.",
			"one of them waved. i did not wave back. i regret this."],
		3: ["today we cook NOODLES. this is not cannibalism.",
			"stir SLOWLY. the noodle feels everything.",
			"season with wrath. a pinch. no more.",
			"the secret ingredient is the eye. watching. always."],
		4: ["and STRETCH. two. three. four.",
			"squat like the universe is watching. it is. i am.",
			"feel the burn. i am made of burn.",
			"hydrate. noodles are 90 percent water. probably."]}

	func _ready() -> void:
		# the stage: floor, back wall, a light, the camera
		var fl := MeshInstance3D.new()
		fl.mesh = Surfaces.box_mesh(Vector3(16, 0.4, 12))
		fl.material_override = Destructible.make_material(Color("#2a2233"), 0.1)
		add_child(fl)
		var bw := MeshInstance3D.new()
		bw.mesh = Surfaces.box_mesh(Vector3(16, 9, 0.4))
		bw.material_override = Destructible.make_material(Color("#3a2a4a"), 0.15)
		add_child(bw)
		bw.position = Vector3(0, 4.5, -4.5)
		var lt := OmniLight3D.new()
		lt.light_energy = 1.6
		lt.omni_range = 30.0
		add_child(lt)
		lt.position = Vector3(0, 6, 6)
		var cam := Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0, 2.6, 7.5)
		cam.look_at(Vector3(0, 2.0, 0), Vector3.UP)
		cam.current = true
		_build_puppet()
		_build_props()
		set_channel(TVSet.fork_channel)

	## the FORK TV host: a mini noodle god with 4 small tentacles, two
	## arms, two legs -- and the rings live BEHIND him, never crossing
	## the eye
	func _build_puppet() -> void:
		_body = Node3D.new()
		add_child(_body)
		_body.position = Vector3(0, 2.2, 0)
		var core := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.9
		cm.height = 1.8
		core.mesh = cm
		core.material_override = Destructible.make_material(Color("#e8cf9a"), 0.6)
		_body.add_child(core)
		# rings BEHIND the body, tilted away -- the eye stays clear
		for rr in [[1.3, -0.9], [1.6, -1.2]]:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = float(rr[0]) - 0.06
			tm.outer_radius = float(rr[0])
			ring.mesh = tm
			ring.material_override = Destructible.make_material(
				Color("#ffcf40"), 1.2)
			_body.add_child(ring)
			ring.position = Vector3(0, 0.2, rr[1])
			ring.rotation_degrees = Vector3(70, 0, 0)
		# THE EYE, front and center, unblocked forever
		_eye = Node3D.new()
		_body.add_child(_eye)
		_eye.position = Vector3(0, 0.15, 0.75)
		var white := MeshInstance3D.new()
		var wm := SphereMesh.new()
		wm.radius = 0.23
		wm.height = 0.46
		white.mesh = wm
		white.material_override = Destructible.make_material(Color("#f2f2ee"), 0.9)
		_eye.add_child(white)
		_pupil = MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.09
		pm.height = 0.18
		_pupil.mesh = pm
		_pupil.material_override = Destructible.make_material(Color("#1a1016"), 0.2)
		_eye.add_child(_pupil)
		_pupil.position = Vector3(0, 0, 0.16)
		# limbs: noodly boxes on pivot nodes
		_arm_l = _limb(Vector3(-0.95, 0.35, 0), Color("#e8cf9a"))
		_arm_r = _limb(Vector3(0.95, 0.35, 0), Color("#e8cf9a"))
		_leg_l = _limb(Vector3(-0.4, -0.85, 0), Color("#d8bf8a"))
		_leg_r = _limb(Vector3(0.4, -0.85, 0), Color("#d8bf8a"))
		# four SMALL tentacles fringing the underside
		for i in 4:
			var a := -0.9 + 0.6 * float(i)
			var tp := Node3D.new()
			_body.add_child(tp)
			tp.position = Vector3(a * 0.55, -0.8, 0.25)
			var tm2 := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.03
			tc.bottom_radius = 0.09
			tc.height = 0.6
			tm2.mesh = tc
			tm2.material_override = Destructible.make_material(Color("#e8cf9a"), 0.5)
			tp.add_child(tm2)
			tm2.position = Vector3(0, -0.3, 0)
			_tents.append(tp)

	func _limb(at: Vector3, col: Color) -> Node3D:
		var piv := Node3D.new()
		_body.add_child(piv)
		piv.position = at
		var m := MeshInstance3D.new()
		m.mesh = Surfaces.box_mesh(Vector3(0.22, 0.85, 0.22))
		m.material_override = Destructible.make_material(col, 0.5)
		piv.add_child(m)
		m.position = Vector3(0, -0.42, 0)
		return piv

	func _build_props() -> void:
		# per-channel set dressing, hidden until its channel airs
		var desk := Node3D.new()
		var dm := MeshInstance3D.new()
		dm.mesh = Surfaces.box_mesh(Vector3(3.2, 0.9, 1.1))
		dm.material_override = Destructible.make_material(Color("#4a3a5c"), 0.2)
		desk.add_child(dm)
		dm.position = Vector3(0, 0.45, 0)
		add_child(desk)
		desk.position = Vector3(0, 0, 1.2)
		_props[1] = desk
		var board := Node3D.new()
		var bm := MeshInstance3D.new()
		bm.mesh = Surfaces.box_mesh(Vector3(3.4, 2.4, 0.15))
		bm.material_override = Destructible.make_material(Color("#d8d0c0"), 0.3)
		board.add_child(bm)
		for i in 3:
			var sil := MeshInstance3D.new()
			sil.mesh = Surfaces.box_mesh(Vector3(0.5, 0.9, 0.05))
			sil.material_override = Destructible.make_material(Color("#22242c"), 0.1)
			board.add_child(sil)
			sil.position = Vector3(-1.0 + float(i), -0.1, 0.09)
		var ml := Label3D.new()
		ml.text = "MISSING"
		ml.font_size = 64
		ml.pixel_size = 0.01
		ml.modulate = Color("#c22")
		board.add_child(ml)
		ml.position = Vector3(0, 0.95, 0.1)
		add_child(board)
		board.position = Vector3(2.6, 2.6, -2.8)
		board.rotation_degrees = Vector3(0, -18, 0)
		_props[2] = board
		var pot := Node3D.new()
		var pb := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.8
		pc.bottom_radius = 0.65
		pc.height = 0.7
		pb.mesh = pc
		pb.material_override = Destructible.make_material(Color("#44484f"), 0.4)
		pot.add_child(pb)
		pb.position = Vector3(0, 0.35, 0)
		var soup := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.72
		sc.bottom_radius = 0.72
		sc.height = 0.08
		soup.mesh = sc
		soup.material_override = DatamoshStudio._fluid_material(Color("#ffcf40"))
		pot.add_child(soup)
		soup.position = Vector3(0, 0.68, 0)
		add_child(pot)
		pot.position = Vector3(0, 0.6, 1.4)
		_props[3] = pot

	func set_channel(ch: int) -> void:
		for k in _props:
			(_props[k] as Node3D).visible = int(k) == ch
		_sub_i = 0
		_sub_t = 0.0
		TVSet.fork_sub = "" if not SUBS.has(ch) else str(SUBS[ch][0])

	func _process(delta: float) -> void:
		_t += delta
		if sleepy:
			# nobody near a screen? the studio stops rendering entirely
			var idle: bool = Time.get_ticks_msec() - TVSet.dance_ping_ms > 4000
			(get_parent() as SubViewport).render_target_update_mode = \
				SubViewport.UPDATE_DISABLED if idle \
				else SubViewport.UPDATE_ALWAYS
			if idle:
				return
		var ch := lock_channel if lock_channel >= 0 else TVSet.fork_channel
		# subtitles roll on every talking channel
		if SUBS.has(ch):
			_sub_t += delta
			if _sub_t > 5.0:
				_sub_t = 0.0
				_sub_i = (_sub_i + 1) % (SUBS[ch] as Array).size()
				TVSet.fork_sub = str((SUBS[ch] as Array)[_sub_i])
		else:
			TVSet.fork_sub = ""
		# tentacles always drift
		for i in _tents.size():
			(_tents[i] as Node3D).rotation.z = sin(_t * 2.0 + float(i)) * 0.25
		match ch:
			0:
				# THE DANCE: the default dance, forever
				var b := _t * 5.2
				_body.position = Vector3(0, 2.2 + absf(sin(b)) * 0.18, 0)
				_body.rotation.y = sin(b * 0.5) * 0.4
				_arm_l.rotation.z = 1.1 + sin(b) * 0.9
				_arm_r.rotation.z = -1.1 + sin(b) * 0.9
				_arm_l.rotation.x = cos(b) * 0.7
				_arm_r.rotation.x = -cos(b) * 0.7
				_leg_l.rotation.x = sin(b) * 0.5
				_leg_r.rotation.x = -sin(b) * 0.5
			1:
				# desk show: leaning, gesturing at nothing
				_body.position = Vector3(0, 2.2, -0.2)
				_body.rotation.y = sin(_t * 0.6) * 0.15
				_arm_l.rotation.z = 0.5 + sin(_t * 1.7) * 0.25
				_arm_r.rotation.z = -0.5 - cos(_t * 1.3) * 0.25
				_leg_l.rotation.x = 0.0
				_leg_r.rotation.x = 0.0
			2:
				# missing dudes: turned to the board, pointing at it
				_body.rotation.y = 0.5 + sin(_t * 0.4) * 0.1
				_arm_r.rotation.z = -1.9 + sin(_t * 0.8) * 0.1
				_arm_l.rotation.z = 0.2
			3:
				# cooking: stirring, endlessly
				_body.rotation.y = sin(_t * 0.5) * 0.1
				_arm_r.rotation.x = 0.9 + sin(_t * 3.0) * 0.3
				_arm_r.rotation.z = -0.6 + cos(_t * 3.0) * 0.3
				_arm_l.rotation.z = 0.4
			4:
				# exercise hour: squats
				var q := absf(sin(_t * 2.0))
				_body.position = Vector3(0, 2.2 - q * 0.5, 0)
				_leg_l.rotation.x = q * 1.1
				_leg_r.rotation.x = q * 1.1
				_arm_l.rotation.z = 1.5
				_arm_r.rotation.z = -1.5
		# the pupil finds the camera and stays there. of course it does.
		_pupil.position = Vector3(0, 0, 0.16)

## ---------------------------------------------------------- SPY CAM
class SpyCam extends StaticBody3D:
	var cam_name := "camera"
	var _vis: Node3D = null
	var _head: Node3D = null      # the aimable part; the mount never moves
	var _ht := 0.0
	var _aiming := false
	var _aimcam: Camera3D = null

	func _process(delta: float) -> void:
		# the HOUSING floats -- a gentle hover bob on the visuals only.
		# The node (and the feed anchored to it) never moves: no wobble
		# on any TV watching through this lens.
		_ht += delta
		if _vis != null:
			_vis.position.y = sin(_ht * 1.3) * 0.05
			_vis.rotation.z = sin(_ht * 0.9) * 0.03
		if _aiming:
			# ROCKET-STYLE attitude: W/S pitch, A/D yaw, relative to
			# what the lens sees. Only the head turns; the mount holds.
			var r := 1.6 * delta
			if Input.is_key_pressed(KEY_W):
				_head.rotate_object_local(Vector3(1, 0, 0), -r)
			if Input.is_key_pressed(KEY_S):
				_head.rotate_object_local(Vector3(1, 0, 0), r)
			if Input.is_key_pressed(KEY_A):
				_head.rotate_object_local(Vector3(0, 1, 0), r)
			if Input.is_key_pressed(KEY_D):
				_head.rotate_object_local(Vector3(0, 1, 0), -r)
			if Input.is_key_pressed(KEY_F) and not _f_latch:
				aim_end()
			_f_latch = Input.is_key_pressed(KEY_F)

	var _f_latch := true

	## your view rides the camera itself: watch it turn from inside
	func aim_begin() -> void:
		_aiming = true
		_f_latch = true
		Game.cam_aiming = true
		if _aimcam == null:
			_aimcam = Camera3D.new()
			_head.add_child(_aimcam)
			_aimcam.position = Vector3(0, 0.22, -0.4)
		_aimcam.current = true
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash("AIMING %s -- W/S pitch, A/D yaw, F done" % cam_name)

	func aim_end() -> void:
		_aiming = false
		Game.cam_aiming = false
		var pl = get_tree().get_first_node_in_group("player")
		if pl != null and "_camera" in pl and pl._camera != null:
			pl._camera.current = true

	## against a wall? grow a mount arm, snap the head to face OUT
	func _wall_check() -> void:
		if not is_inside_tree():
			return
		var sp := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			global_position + global_transform.basis.y * 0.25,
			global_position + global_transform.basis.y * 0.25
			+ global_transform.basis.z * 0.7)
		q.exclude = [get_rid()]
		var hit := sp.intersect_ray(q)
		if hit.size() == 0 or absf((hit["normal"] as Vector3)
				.dot(global_transform.basis.y)) > 0.4:
			return
		# mount plate on the wall + short arm; lens looks along the
		# wall normal, straight out
		var n9: Vector3 = hit["normal"]
		global_position = (hit["position"] as Vector3) + n9 * 0.02
		look_at(global_position + n9, global_transform.basis.y)
		var plate := MeshInstance3D.new()
		plate.mesh = Surfaces.box_mesh(Vector3(0.3, 0.3, 0.06))
		plate.material_override = Destructible.make_material(Color("#2a2f38"), 0.4)
		add_child(plate)
		plate.position = Vector3(0, 0.22, 0.03)
		var arm := MeshInstance3D.new()
		arm.mesh = Surfaces.box_mesh(Vector3(0.08, 0.08, 0.3))
		arm.material_override = Destructible.make_material(Color("#3a3f48"), 0.4)
		add_child(arm)
		arm.position = Vector3(0, 0.22, -0.12)
		_head.position = Vector3(0, 0, -0.3)

	func _ready() -> void:
		add_to_group("spycam")
		_head = Node3D.new()
		add_child(_head)
		_vis = Node3D.new()
		_head.add_child(_vis)
		call_deferred("_wall_check")
		var body := MeshInstance3D.new()
		body.mesh = Surfaces.box_mesh(Vector3(0.3, 0.22, 0.44))
		body.material_override = Destructible.make_material(Color("#2a2f38"), 0.4)
		_vis.add_child(body)
		body.position = Vector3(0, 0.22, 0)
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.09
		lm.bottom_radius = 0.11
		lm.height = 0.14
		lens.mesh = lm
		lens.material_override = Destructible.make_material(Color("#7df9ff"), 1.4)
		_vis.add_child(lens)
		lens.position = Vector3(0, 0.22, -0.26)
		lens.rotation_degrees = Vector3(90, 0, 0)
		var dot := MeshInstance3D.new()
		var dm2 := SphereMesh.new()
		dm2.radius = 0.03
		dm2.height = 0.06
		dot.mesh = dm2
		dot.material_override = Destructible.make_material(Color("#ff3030"), 2.2)
		_vis.add_child(dot)
		dot.position = Vector3(0.1, 0.34, 0)
		# THE FLOAT: three blue rings hanging under the housing -- the
		# anti-grav that keeps it up
		for ri in 3:
			var ring := MeshInstance3D.new()
			var rt := TorusMesh.new()
			rt.outer_radius = 0.16 - float(ri) * 0.035
			rt.inner_radius = rt.outer_radius - 0.03
			ring.mesh = rt
			ring.material_override = Destructible.make_material(
				Color("#7df9ff"), 1.6 - float(ri) * 0.3)
			_vis.add_child(ring)
			ring.position = Vector3(0, -0.06 - float(ri) * 0.09, 0)
		# THE FLOAT: three blue rings hanging under the housing, the
		# anti-grav that keeps it up
		for ri in 3:
			var ring := MeshInstance3D.new()
			var rt := TorusMesh.new()
			rt.outer_radius = 0.16 - float(ri) * 0.035
			rt.inner_radius = rt.outer_radius - 0.03
			ring.mesh = rt
			ring.material_override = Destructible.make_material(
				Color("#7df9ff"), 1.6 - float(ri) * 0.3)
			_vis.add_child(ring)
			ring.position = Vector3(0, -0.06 - float(ri) * 0.09, 0)
		var cs := CollisionShape3D.new()
		cs.shape = Surfaces.box_shape(Vector3(0.4, 0.4, 0.5))
		cs.position = Vector3(0, 0.22, 0)
		add_child(cs)
		var lbl := Label3D.new()
		lbl.name = "tag"
		lbl.text = cam_name + "  [F rename]"
		lbl.font_size = 18
		lbl.pixel_size = 0.005
		lbl.modulate = Color("#7df9ff")
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0, 0, 0, 0.9)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
		lbl.position = Vector3(0, 0.62, 0)
		TVSet.cams[cam_name] = self
		tree_exiting.connect(func() -> void:
			if TVSet.cams.get(cam_name) == self:
				TVSet.cams.erase(cam_name))

	func use() -> void:
		var pui := PickUI.new().configure("SECURITY CAMERA", [
			{"id": "aim", "label": "AIM CAMERA (see through it)"},
			{"id": "rename", "label": "RENAME"}],
			func(pick: String) -> void:
				if pick == "aim":
					aim_begin()
				elif pick == "rename":
					_rename_box())
		get_tree().current_scene.add_child(pui)

	func _rename_box() -> void:
		# rename: a real text box, not a cycle
		var lay := CanvasLayer.new()
		lay.layer = 46
		get_tree().current_scene.add_child(lay)
		var pc := PanelContainer.new()
		pc.set_anchors_preset(Control.PRESET_CENTER)
		lay.add_child(pc)
		var vb := VBoxContainer.new()
		pc.add_child(vb)
		var tl := Label.new()
		tl.text = "CAMERA NAME"
		vb.add_child(tl)
		var le := LineEdit.new()
		le.text = cam_name
		le.custom_minimum_size = Vector2(260, 40)
		vb.add_child(le)
		var ok := Button.new()
		ok.text = "save"
		vb.add_child(ok)
		var was_mouse := Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		le.grab_focus()
		var done := func() -> void:
			var nn := le.text.strip_edges()
			if nn != "" and (not TVSet.cams.has(nn) or TVSet.cams[nn] == self):
				TVSet.cams.erase(cam_name)
				cam_name = nn
				TVSet.cams[cam_name] = self
				(get_node("tag") as Label3D).text = cam_name + "  [F rename]"
			lay.queue_free()
			Input.mouse_mode = was_mouse
		ok.pressed.connect(done)
		le.text_submitted.connect(func(_t2: String) -> void: done.call())

## ---------------------------------------------------------- THE TV
class TV extends StaticBody3D:
	var big := false
	var wall := false
	var mode := "menu"        # menu | camera | alien | fork | console
	var cam_pick := ""
	var _screen: MeshInstance3D
	var _stand: MeshInstance3D = null
	var _sub: Label3D
	var _vp: SubViewport = null
	var _vcam: Camera3D = null
	var _menu_lbl: Label3D
	var _con_lbl: Label3D
	var _tick := 0.0

	func _sw() -> float:
		return 2.6 if big else 1.15

	func _sh() -> float:
		return 1.5 if big else 0.7

	func _ready() -> void:
		add_to_group("tv")
		var frame := MeshInstance3D.new()
		frame.mesh = Surfaces.box_mesh(Vector3(_sw() + 0.14, _sh() + 0.14, 0.12))
		frame.material_override = Destructible.make_material(Color("#1c1e24"), 0.3)
		add_child(frame)
		frame.position = Vector3(0, _sh() * 0.5 + 0.35, 0)
		_screen = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(_sw(), _sh())
		_screen.mesh = qm
		add_child(_screen)
		_screen.position = frame.position + Vector3(0, 0, 0.07)
		_stand = MeshInstance3D.new()
		_stand.mesh = Surfaces.box_mesh(Vector3(0.3, 0.36, 0.3))
		_stand.material_override = Destructible.make_material(Color("#2a2f38"), 0.3)
		add_child(_stand)
		_stand.position = Vector3(0, 0.17, 0)
		var cs := CollisionShape3D.new()
		cs.shape = Surfaces.box_shape(Vector3(_sw() + 0.2, _sh() + 0.6, 0.4))
		cs.position = Vector3(0, _sh() * 0.5 + 0.3, 0)
		add_child(cs)
		_menu_lbl = Label3D.new()
		_menu_lbl.font_size = 30 if big else 20
		_menu_lbl.pixel_size = 0.006
		_menu_lbl.modulate = Color("#7dff9a")
		_menu_lbl.outline_size = 8
		_menu_lbl.outline_modulate = Color(0, 0, 0, 0.9)
		add_child(_menu_lbl)
		_menu_lbl.position = _screen.position + Vector3(0, 0, 0.02)
		_sub = Label3D.new()
		_sub.font_size = 22 if big else 16
		_sub.pixel_size = 0.005
		_sub.width = 400.0
		_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sub.modulate = Color.WHITE
		_sub.outline_size = 10
		_sub.outline_modulate = Color(0, 0, 0, 0.95)
		add_child(_sub)
		_sub.position = _screen.position + Vector3(0, -_sh() * 0.34, 0.03)
		_con_lbl = Label3D.new()
		_con_lbl.font_size = 16
		_con_lbl.pixel_size = 0.0045
		_con_lbl.modulate = Color("#7dff9a")
		_con_lbl.outline_size = 6
		_con_lbl.outline_modulate = Color(0, 0, 0, 0.9)
		_con_lbl.width = 380.0
		_con_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_con_lbl)
		_con_lbl.position = _screen.position + Vector3(0, 0, 0.02)
		_con_lbl.visible = false
		_apply_screen()
		call_deferred("_mount_check")

	## placed against a wall? snap flush, face out, drop the stand
	func _mount_check() -> void:
		if not is_inside_tree():
			return
		var sp := get_world_3d().direct_space_state
		var back := global_transform.basis.z
		var q := PhysicsRayQueryParameters3D.create(
			global_position + global_transform.basis.y * (_sh() * 0.5 + 0.35),
			global_position + global_transform.basis.y * (_sh() * 0.5 + 0.35)
			+ back * 0.9)
		q.exclude = [get_rid()]
		var hit := sp.intersect_ray(q)
		if hit.size() > 0 and absf((hit["normal"] as Vector3)
				.dot(global_transform.basis.y)) < 0.4:
			wall = true
			if _stand != null:
				_stand.queue_free()
				_stand = null

	func _menu_text() -> String:
		return "[F]  TV MENU\n1  SELECT CAMERA\n2  ALIEN NEWS\n3  FORK TV"

	func _apply_screen() -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_menu_lbl.visible = mode == "menu"
		_con_lbl.visible = mode == "console"
		_sub.text = ""
		if _vcam != null:
			_vcam.queue_free()
			_vcam = null
		match mode:
			"menu":
				m.albedo_color = Color(0.03, 0.05, 0.08)
				_menu_lbl.text = _menu_text()
				_screen.material_override = m
			"console":
				m.albedo_color = Color(0.02, 0.06, 0.03)
				_screen.material_override = m
			"camera":
				_ensure_vp()
				_vcam = Camera3D.new()
				_vp.add_child(_vcam)
				_vcam.current = true
				m.albedo_texture = _vp.get_texture()
				m.albedo_color = Color.WHITE
				_screen.material_override = m
			"alien":
				_ensure_vp()
				_vcam = Camera3D.new()
				_vp.add_child(_vcam)
				_vcam.current = true
				m.albedo_texture = _vp.get_texture()
				m.albedo_color = Color.WHITE
				_screen.material_override = m
			"fork":
				var fvp := TVSet.fork_feed(get_tree())
				m.albedo_texture = fvp.get_texture()
				m.albedo_color = Color.WHITE
				_screen.material_override = m

	func _ensure_vp() -> void:
		if _vp == null:
			_vp = SubViewport.new()
			_vp.size = Vector2i(400, 240)
			_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(_vp)

	func use() -> void:
		var opts: Array = [
			{"id": "cam", "label": "SELECT CAMERA"},
			{"id": "alien", "label": "ALIEN NEWS"},
			{"id": "fork", "label": "FORK TV"},
			{"id": "off", "label": "back to menu"}]
		if mode == "fork":
			opts = []
			for ci in TVSet.CHANNELS.size():
				opts.append({"id": "ch%d" % ci,
					"label": "FORK: " + str(TVSet.CHANNELS[ci])})
			opts.append({"id": "off", "label": "back to menu"})
		var pui := PickUI.new().configure("TV", opts,
			func(pick: String) -> void:
				if pick == "off":
					mode = "menu"
					_apply_screen()
				elif pick == "alien":
					mode = "alien"
					_apply_screen()
				elif pick == "fork":
					mode = "fork"
					_apply_screen()
				elif pick.begins_with("ch"):
					TVSet.fork_channel = int(pick.substr(2))
					if TVSet._fork_drv != null \
							and is_instance_valid(TVSet._fork_drv):
						TVSet._fork_drv.set_channel(TVSet.fork_channel)
				elif pick == "cam":
					_pick_camera())
		get_tree().current_scene.add_child(pui)

	func _pick_camera() -> void:
		var opts: Array = []
		for nm in TVSet.cams.keys():
			opts.append({"id": str(nm), "label": str(nm)})
		if opts.is_empty():
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash("no cameras placed. place a Security Camera and name it")
			return
		var pui := PickUI.new().configure("CAMERAS", opts,
			func(pick: String) -> void:
				cam_pick = pick
				mode = "camera"
				_apply_screen())
		get_tree().current_scene.add_child(pui)

	func _process(delta: float) -> void:
		_tick += delta
		if _tick < 0.1:
			return
		_tick = 0.0
		match mode:
			"camera":
				var cn = TVSet.cams.get(cam_pick)
				if cn == null or not is_instance_valid(cn):
					mode = "menu"
					_apply_screen()
				elif _vcam != null:
					var anchor: Node3D = cn._head if "_head" in cn \
						and cn._head != null else (cn as Node3D)
					_vcam.global_transform = anchor.global_transform \
						.translated_local(Vector3(0, 0.22, -0.3))
			"alien":
				var ds: DatamoshStudio = null
				for c in get_tree().current_scene.get_children():
					if c is DatamoshStudio:
						ds = c
						break
				if ds != null and _vcam != null and ds._tv_cam != null \
						and is_instance_valid(ds._tv_cam):
					ds.remote_watch = 6.0
					_vcam.global_transform = ds._tv_cam.global_transform
					_sub.text = str(ds._cur_text)
			"fork":
				_sub.text = TVSet.fork_sub
			"menu":
				for c3 in get_tree().get_nodes_in_group("machine"):
					if "wires_out" in c3 and (c3.wires_out as Array).has(self):
						mode = "console"
						_apply_screen()
						break
			"console":
				var src: Node = null
				for c2 in get_tree().get_nodes_in_group("machine"):
					if "wires_out" in c2 and (c2.wires_out as Array).has(self):
						src = c2
						break
				if src != null and src.has_method("info_text"):
					_con_lbl.text = str(src.info_text())
				else:
					_con_lbl.text = "NO SIGNAL\nwire a computer into the TV"
