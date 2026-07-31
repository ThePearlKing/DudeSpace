class_name Starship
extends Rocket
## A derelict alien starship drifting in space. It only starts with its
## KEYS (F) -- buy them from the UFO trader. Flying it is gloriously
## unrealistic -- and the noodle gods hate every second of it.

var repaired: bool = false
var _hull_mats: Array = []

func _ready() -> void:
	super._ready()
	arcade = true
	remove_from_group("rocket")          # can't board a wreck
	add_to_group("starship_wreck")
	add_to_group("starship")
	var lbl := Label3D.new()
	lbl.text = "[F]"
	lbl.font_size = 30
	lbl.modulate = Color(1, 1, 1, 0.6)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 4.5, 0)
	add_child(lbl)
	# alien recolor: sickly green glow
	for c in get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override
			m.albedo_color = Color("#2a4a30")
			m.emission = Color("#39ff88")
			m.emission_energy_multiplier = 0.15
			_hull_mats.append(m)

func try_repair() -> void:
	if repaired:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if not Inventory.consume_item("carkeys"):
		Sfx.play("denied")
		if hud:
			hud.flash("no keyhole damage, no hotwiring. it wants its KEYS. ask the aliens.")
		return
	repaired = true
	remove_from_group("starship_wreck")
	add_to_group("rocket")               # F now boards it
	rotation = Vector3.ZERO
	for m in _hull_mats:
		m.emission_energy_multiplier = 2.0
	Sfx.play("smelt")
	if hud:
		hud.flash("the hull hums awake. something is watching.")
	Inventory.changed.emit()
