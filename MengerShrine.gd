class_name MengerShrine
extends StaticBody3D
## A hyper-detailed menger sponge floating inside the sealed pyramid.
## F with a weapon in hand: enchants it (+25% damage per level), for a
## rising price in prism shards.

const SIZE := 7.0
const MAX_LEVEL := 5

var _spin: Node3D

func _ready() -> void:
	add_to_group("shrine")
	_spin = Node3D.new()
	add_child(_spin)

	# depth-3 sponge: 8000 sub-blocks in one MultiMesh. REAL detail.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	var bs := SIZE / 27.0
	bm.size = Vector3(bs, bs, bs) * 0.96
	bm.material = Destructible.make_material(Color("#c9b8ff"), 0.8)
	mm.mesh = bm
	var xforms: Array = []
	for a in 27:
		var A := Vector3i(a % 3, (a / 3) % 3, a / 9)
		if int(A.x == 1) + int(A.y == 1) + int(A.z == 1) >= 2:
			continue
		for b in 27:
			var B := Vector3i(b % 3, (b / 3) % 3, b / 9)
			if int(B.x == 1) + int(B.y == 1) + int(B.z == 1) >= 2:
				continue
			for c in 27:
				var C := Vector3i(c % 3, (c / 3) % 3, c / 9)
				if int(C.x == 1) + int(C.y == 1) + int(C.z == 1) >= 2:
					continue
				var pos := Vector3(
					(float(A.x) - 1.0) * SIZE / 3.0 + (float(B.x) - 1.0) * SIZE / 9.0 + (float(C.x) - 1.0) * bs,
					(float(A.y) - 1.0) * SIZE / 3.0 + (float(B.y) - 1.0) * SIZE / 9.0 + (float(C.y) - 1.0) * bs,
					(float(A.z) - 1.0) * SIZE / 3.0 + (float(B.z) - 1.0) * SIZE / 9.0 + (float(C.z) - 1.0) * bs)
				xforms.append(pos)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, xforms[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_spin.add_child(mmi)

	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3.ONE * (SIZE + 1.0)
	col.shape = cs
	add_child(col)

	var lbl := Label3D.new()
	lbl.text = "[F] enchant weapon / armor"
	lbl.font_size = 30
	lbl.modulate = Color("#c9b8ff")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, SIZE * 0.75 + 1.0, 0)
	add_child(lbl)

	var light := OmniLight3D.new()
	light.light_color = Color("#b49aff")
	light.light_energy = 2.0
	light.omni_range = 30.0
	add_child(light)

func _process(delta: float) -> void:
	_spin.rotate_y(delta * 0.2)
	_spin.rotate_x(delta * 0.07)

func use(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	var id := Inventory.slot_id(Inventory.selected)
	var is_weapon := Inventory.weapons.has(id) and id != "fists"
	var is_armor := Inventory.armors.has(id)
	if not is_weapon and not is_armor:
		Sfx.play("denied")
		if hud:
			hud.flash("hold a weapon or armor piece")
		return
	var nm: String = str(Inventory.weapons[id]["name"]) if is_weapon \
		else str(Inventory.armors[id]["name"])
	var lvl := int(Inventory.enchant.get(id, 0))
	if lvl >= MAX_LEVEL:
		Sfx.play("denied")
		if hud:
			hud.flash("%s is at max enchant" % nm)
		return
	var cost := 5 * (lvl + 1)
	if Inventory.res_count("prism") < cost:
		Sfx.play("denied")
		if hud:
			hud.flash("needs %d prism shards" % cost)
		return
	Inventory.remove_res("prism", cost)
	Inventory.enchant[id] = lvl + 1
	Inventory.changed.emit()
	# fractal power is not free: the gods HATE the menger
	Game.anger(12.0)
	Sfx.play("learn")
	if hud:
		if is_weapon:
			hud.flash("%s +%d  (damage x%.2f)" % [nm, lvl + 1, 1.0 + 0.25 * float(lvl + 1)])
		else:
			hud.flash("%s +%d  (armor x%.2f)" % [nm, lvl + 1, 1.0 + 0.15 * float(lvl + 1)])
