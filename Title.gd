extends Node
## Main scene. Title -> pick one of 3 save slots -> character creator ->
## launch the game world (Main.tscn).

var _title_ui: CanvasLayer
var _options: CanvasLayer
var _creator: CharacterCreator

var _bg_pivot: Node3D
var _orbits: Array = []
var _crab: ClawdeCrab
var _invader: Invader

func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_build_background()
	_build_title()

func _process(delta: float) -> void:
	if _bg_pivot:
		_bg_pivot.rotate_y(delta * 0.15)
	for o in _orbits:
		o[0].rotate_y(delta * float(o[1]))
	if _crab and is_instance_valid(_crab):
		_crab.rotate_y(delta * 0.9)   # tumbling menace
		_crab.rotate_x(delta * 0.35)
	if _invader and is_instance_valid(_invader):
		_invader.rotate_y(delta * -0.7)
		_invader.rotate_z(delta * 0.25)

func _build_background() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sh := Shader.new()
	sh.code = "shader_type sky;\nvoid sky(){\n vec3 d=EYEDIR;\n vec3 cell=floor(d*150.0);\n float n=fract(sin(dot(cell,vec3(12.9898,78.233,37.719)))*43758.5453);\n float star=step(0.997,n);\n COLOR=vec3(0.02,0.02,0.05)+vec3(star)*0.9;\n}"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sky.sky_material = sm
	env.sky = sky
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 9.0)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -50, 0)
	light.light_energy = 1.2
	add_child(light)

	# a little solar system spins behind the menu...
	for spec in [[7.0, 0.9, 0.10, Color("#2f7d32")], [11.0, 1.4, -0.06, Color("#0e3b2e")],
			[15.0, 0.6, 0.14, Color("#c8a557")], [19.0, 1.1, -0.04, Color("#e8a3c0")]]:
		var orbit := Node3D.new()
		orbit.rotation_degrees = Vector3(randf_range(-14, 14), randf_range(0, 360), 0)
		add_child(orbit)
		var pl := MeshInstance3D.new()
		var pm2 := SphereMesh.new()
		pm2.radius = spec[1]
		pm2.height = spec[1] * 2.0
		pl.mesh = pm2
		pl.material_override = Destructible.make_material(spec[3], 0.15)
		pl.position = Vector3(spec[0], 0, 0)
		orbit.add_child(pl)
		_orbits.append([orbit, spec[2]])
	# ...and Clawde the space invader crab tumbles through it all
	var crab_orbit := Node3D.new()
	crab_orbit.rotation_degrees = Vector3(20, 0, 8)
	add_child(crab_orbit)
	_crab = ClawdeCrab.new()
	crab_orbit.add_child(_crab)
	_crab.position = Vector3(13.0, 2.0, 0)
	_crab.scale = Vector3.ONE * 0.22
	_crab.build()
	_orbits.append([crab_orbit, 0.08])
	# ...and a CLASSIC space invader drifts the other way
	var inv_orbit := Node3D.new()
	inv_orbit.rotation_degrees = Vector3(-14, 140, -6)
	add_child(inv_orbit)
	_invader = Invader.new()
	inv_orbit.add_child(_invader)
	_invader.position = Vector3(16.0, -1.5, 0)
	_invader.scale = Vector3.ONE * 0.16
	_invader.build(Color("#7dff6a"))
	_orbits.append([inv_orbit, -0.06])

	_bg_pivot = Node3D.new()
	_bg_pivot.position = Vector3(3.5, 0.5, 0)
	add_child(_bg_pivot)
	var planet := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 3.0
	pm.height = 6.0
	pm.radial_segments = 40
	pm.rings = 24
	planet.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#5a2d8f")
	mat.metallic = 0.2
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = Color("#7a1dbe")
	mat.emission_energy_multiplier = 0.3
	planet.material_override = mat
	_bg_pivot.add_child(planet)
	# a little moon
	var moon := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.7
	mm.height = 1.4
	moon.mesh = mm
	moon.material_override = Destructible.make_material(Color("#c8c8d8"), 0.1)
	moon.position = Vector3(-4.5, 1.2, 1.0)
	_bg_pivot.add_child(moon)

func _build_title() -> void:
	_title_ui = CanvasLayer.new()
	add_child(_title_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.55)   # translucent: the parade shows through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_ui.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-300, -300)
	col.custom_minimum_size = Vector2(600, 600)
	col.add_theme_constant_override("separation", 14)
	_title_ui.add_child(col)

	var title := Label.new()
	title.text = "CLAUDE  THE  DUDE"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Label.new()
	sub.text = "destroy everything. across a universe."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	col.add_child(sub)

	# --- the save list lives right here, always ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(list)
	var ids := Save.list_saves()
	if ids.is_empty():
		var none := Label.new()
		none.text = "no saves yet. press NEW GAME."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.modulate = Color(1, 1, 1, 0.6)
		list.add_child(none)
	for id_v in ids:
		var id: int = id_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var play := Button.new()
		play.custom_minimum_size = Vector2(500, 50)
		play.text = "%s   ·   %s" % [Save.slot_name(id), Save.slot_summary(id)]
		play.pressed.connect(func() -> void:
			Save.load_slot(id)
			get_tree().change_scene_to_file("res://Main.tscn"))
		row.add_child(play)
		var del := Button.new()
		del.text = "🗑"
		del.custom_minimum_size = Vector2(50, 50)
		del.pressed.connect(func() -> void:
			Save.delete_slot(id)
			_refresh_title())
		row.add_child(del)
		list.add_child(row)

	# --- buttons at the BOTTOM ---
	var btnrow := HBoxContainer.new()
	btnrow.add_theme_constant_override("separation", 12)
	btnrow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btnrow)
	var newg := Button.new()
	newg.text = "NEW GAME"
	newg.custom_minimum_size = Vector2(220, 56)
	newg.pressed.connect(func() -> void:
		Save.current_slot = Save.next_id()
		_open_creator())
	btnrow.add_child(newg)
	var opt := Button.new()
	opt.text = "Options"
	opt.custom_minimum_size = Vector2(160, 56)
	opt.pressed.connect(_open_options)
	btnrow.add_child(opt)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(120, 56)
	quit.pressed.connect(func(): get_tree().quit())
	btnrow.add_child(quit)

func _refresh_title() -> void:
	if _title_ui:
		_title_ui.queue_free()
	_build_title()

func _open_creator() -> void:
	if _title_ui:
		_title_ui.hide()
	_creator = CharacterCreator.new()
	_creator.started.connect(func(): get_tree().change_scene_to_file("res://Main.tscn"))
	_creator.back.connect(func():
		_creator.queue_free()
		_creator = null
		if _title_ui:
			_title_ui.show())
	add_child(_creator)

func _open_options() -> void:
	if _options:
		return
	_options = CanvasLayer.new()
	_options.layer = 5
	var panel := OptionsPanel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-180, -140)
	panel.closed.connect(func():
		_options.queue_free()
		_options = null)
	_options.add_child(panel)
	add_child(_options)
