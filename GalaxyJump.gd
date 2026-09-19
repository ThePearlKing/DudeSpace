class_name GalaxyJump
extends StaticBody3D
## THE JUMP CONSOLE, bolted to the Nexus dock. It does not move you --
## it moves everything else.
##
## A rocket crosses distance. This does not. Press the throw and the
## universe you are standing in is torn down entirely: every planet,
## every star, every building you ever put down, gone in the same frame
## the next one arrives in. You do not travel to the other galaxy. The
## other galaxy is put around you.
##
## Both worlds are kept whole in the same save. The base you left in the
## Milky Way is exactly as you left it when you come back for it, and
## anything you build in Sloom is waiting the next time you jump out.

var _ui: GalaxyJumpUI
var _lamp: MeshInstance3D
var _t: float = 0.0
var accent := Color("#7be8ff")

func _ready() -> void:
	add_to_group("galaxy_jump")
	collision_layer = 1
	collision_mask = 0
	_build()

func _build() -> void:
	# a LECTERN, not a floating button: pedestal, angled desk, a screen
	# set into it and a throw switch beside the screen under a guard.
	_blk(Vector3(1.05, 0.22, 0.85), Vector3(0, 0.11, 0), Color("#2a3038"), 0.05)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		_blk(Vector3(0.13, 0.95, 0.13),
			Vector3(cos(a) * 0.38, 0.6, sin(a) * 0.38), Color("#4a515c"), 0.05)
	_blk(Vector3(1.0, 0.16, 0.78), Vector3(0, 1.06, 0), Color("#39414b"), 0.05)
	# the desk, tipped toward whoever is reading it
	_blk(Vector3(0.98, 0.1, 0.62), Vector3(0, 1.26, -0.06), Color("#20262e"),
		0.05, Vector3(-24.0, 0, 0))
	# the screen: the only bright thing on it
	var scr := _blk(Vector3(0.74, 0.02, 0.44), Vector3(0, 1.33, -0.09),
		accent, 1.9, Vector3(-24.0, 0, 0))
	_lamp = scr
	# scan lines across the glass so it reads as a display, not a panel
	for k in 5:
		_blk(Vector3(0.7, 0.024, 0.024),
			Vector3(0, 1.335 + float(k) * 0.006, -0.235 + float(k) * 0.09),
			Color("#0a1018"), 0.0, Vector3(-24.0, 0, 0))
	# the throw, under a hinged guard, because this is not a thing you
	# want to lean on by accident
	_blk(Vector3(0.2, 0.06, 0.2), Vector3(0.36, 1.31, 0.12),
		Color("#8c2a1a"), 0.25, Vector3(-24.0, 0, 0))
	_blk(Vector3(0.06, 0.2, 0.06), Vector3(0.36, 1.4, 0.1),
		Color("#d8442a"), 0.6, Vector3(-40.0, 0, 0))
	# hazard stripes along the front edge
	for k in 7:
		_blk(Vector3(0.1, 0.03, 0.12), Vector3(-0.42 + float(k) * 0.14, 1.19, 0.28),
			Color("#f2b13c") if k % 2 == 0 else Color("#1a1f26"), 0.15)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 1.5, 1.0)
	cs.shape = sh
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)

	var lbl := Label3D.new()
	lbl.text = "GALAXY JUMP [F]"
	lbl.font_size = 26
	lbl.pixel_size = 0.008
	lbl.modulate = accent
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.95, 0)
	add_child(lbl)

func _blk(size: Vector3, pos: Vector3, col: Color, emit := 0.1,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.rotation_degrees = rot
	m.material_override = Destructible.make_material(col, emit)
	add_child(m)
	return m

func _process(delta: float) -> void:
	_t += delta
	if _lamp != null and _lamp.material_override is StandardMaterial3D:
		var mm: StandardMaterial3D = _lamp.material_override
		mm.emission_energy_multiplier = 1.5 + 0.7 * sin(_t * 1.7)

## F on the console. The list is a real list of buttons -- there are two
## galaxies today and there will be more, and a thing you press twice to
## change its mind is not a control panel.
func use() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if Net.active:
		Sfx.play("denied")
		if hud:
			hud.flash("JUMP LOCKED — everyone in a LAN session shares one sky")
		return
	if Game.mode != Game.Mode.ON_FOOT:
		Sfx.play("denied")
		if hud:
			hud.flash("JUMP LOCKED — leave the rocket first")
		return
	if _ui == null or not is_instance_valid(_ui):
		_ui = GalaxyJumpUI.new()
		_ui.console = self
		get_tree().current_scene.add_child(_ui)
	_ui.open()
	Sfx.play("click")

## THE JUMP ITSELF.
##
## Order matters and every step of it is the difference between two
## saved worlds and one lost one:
##   1. the ship you docked with is lifted OUT of the world list, so the
##      indices machines wire each other with never shift under them;
##   2. the world as it stands is written to the galaxy being left;
##   3. the ship is written into the galaxy being entered;
##   4. the slot is committed to disk BEFORE anything is torn down.
## Only then does the scene reload, and Main builds the other universe
## from the first frame because Game.galaxy is already the other one.
func jump_to(dest: String) -> void:
	if dest == Game.galaxy or not Universe.GALAXIES.has(dest):
		return
	var main = get_tree().current_scene
	if main == null or not main.has_method("collect_world"):
		return
	var leaving := Game.galaxy
	Save.mark_jump_spawn()   # the bed you had HERE, filed with this sky
	# 1. the docked ship comes with you. Stripping placed_id is what
	# keeps it out of collect_world without disturbing anyone's index.
	var carried: Array = []
	for r in get_tree().get_nodes_in_group("rocket"):
		if not (r is Rocket) or not is_instance_valid(r) or r.piloted:
			continue
		if r.global_position.distance_to(main.NEXUS_POS) > 220.0:
			continue
		var up: Vector3 = -r.global_transform.basis.z
		carried.append({
			"id": "rocket2" if r.mk2 else "rocket",
			"hyper": r.hyperdrive,
			"up": [up.x, up.y, up.z],
		})
		if r.has_meta("placed_id"):
			r.remove_meta("placed_id")
	# 2. this world, as it stands, belongs to the sky we are leaving
	var here: Array = main.collect_world()
	Game.galaxy = dest
	var land: Vector3 = main.NEXUS_POS + NexusStation.dock_offset(dest)
	# 3. the ship is put down beside the far station
	var there: Array = Save.world_for(dest)
	for c in carried:
		var cp: Vector3 = land + Vector3(14.0, 4.0, 0)
		c["pos"] = [cp.x, cp.y, cp.z]
		there.append(c)
	Save.commit_jump(leaving, dest, here, there)
	# 4. arrive on foot, on the dock, in zero g -- and with a spawn out
	# here, because dying in Sloom must not wake you in the Milky Way
	Game.zone = ""
	Game.zone_g = 9.0
	if not Save.has_spawn_in(dest):
		Game.set_spawn(land, Vector3.UP)
	Save.set_player_pos(land, false, false)
	Save.save_progress()
	Sfx.play("warp")
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred("res://Main.tscn")


class GalaxyJumpUI:
	extends CanvasLayer

	var console: GalaxyJump
	var _list: VBoxContainer
	var _status: Label

	func _ready() -> void:
		layer = 24
		visible = false
		add_to_group("closable_ui")
		add_to_group("galaxy_jump_ui")
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.6)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.custom_minimum_size = Vector2(540, 440)
		panel.size = Vector2(540, 440)
		panel.position = Vector2(-270, -220)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0a1018")
		sb.border_color = Color("#7cf9ff")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		panel.add_theme_stylebox_override("panel", sb)
		add_child(panel)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 10)
		col.position = Vector2(22, 18)
		panel.add_child(col)
		var title := Label.new()
		title.text = "GALAXY JUMP"
		title.add_theme_font_size_override("font_size", 26)
		title.modulate = Color("#7cf9ff")
		col.add_child(title)
		var blurb := Label.new()
		blurb.text = "The station stays. Everything else is replaced.\nYour world in each sky is kept whole and separate."
		blurb.add_theme_font_size_override("font_size", 14)
		blurb.modulate = Color(1, 1, 1, 0.62)
		col.add_child(blurb)
		_status = Label.new()
		_status.add_theme_font_size_override("font_size", 15)
		col.add_child(_status)
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 8)
		col.add_child(_list)
		var close := Button.new()
		close.text = "Close"
		close.custom_minimum_size = Vector2(492, 40)
		close.pressed.connect(close_ui)
		col.add_child(close)

	func open() -> void:
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_rebuild()

	func close_ui() -> void:
		visible = false
		if not Game.dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func _rebuild() -> void:
		for c in _list.get_children():
			c.queue_free()
		_status.text = "CURRENT SKY:  %s" % Universe.galaxy_label(Game.galaxy)
		_status.modulate = Color("#9ef7a0")
		var docked := 0
		var main = get_tree().current_scene
		for r in get_tree().get_nodes_in_group("rocket"):
			if r is Rocket and is_instance_valid(r) and not r.piloted \
					and r.global_position.distance_to(main.NEXUS_POS) < 220.0:
				docked += 1
		for g in Universe.GALAXIES.keys():
			var gid := str(g)
			var b := Button.new()
			b.custom_minimum_size = Vector2(492, 56)
			b.add_theme_font_size_override("font_size", 19)
			if gid == Game.galaxy:
				b.text = "%s   — you are here" % Universe.galaxy_label(gid)
				b.disabled = true
			else:
				b.text = "JUMP TO %s" % Universe.galaxy_label(gid)
				b.pressed.connect(func() -> void:
					close_ui()
					console.jump_to(gid))
			_list.add_child(b)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 13)
		note.modulate = Color(1, 1, 1, 0.55)
		note.text = "%d ship%s docked — docked ships jump with you." \
			% [docked, "" if docked == 1 else "s"] if docked > 0 \
			else "No ship docked. Park within 220m of the station and it jumps with you."
		_list.add_child(note)
