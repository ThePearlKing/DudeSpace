class_name Gate
extends StaticBody3D
## Universal interactable (F). Either teleports the player somewhere
## (optionally switching the gravity zone) or fires a one-shot action
## (learn recipe / activate mind core / claim artifact / open terminal).

var target: Vector3 = Vector3.ZERO
var zone: String = ""          # "", "flat", "zero"
var zone_g: float = 9.0
var label_text: String = "GATE"
var color: Color = Color("#7cf9ff")
var action: String = ""        # "", "recipe", "mindcore", "artifact", "terminal"
var requires: String = ""      # "", "door_open", "mindcore"
var warn_jetpack: bool = false
var flash_msg: String = ""

func configure(cfg: Dictionary) -> Gate:
	target = cfg.get("target", Vector3.ZERO)
	zone = cfg.get("zone", "")
	zone_g = cfg.get("zone_g", 9.0)
	label_text = cfg.get("label", "GATE")
	color = cfg.get("color", Color("#7cf9ff"))
	action = cfg.get("action", "")
	requires = cfg.get("requires", "")
	warn_jetpack = cfg.get("warn_jetpack", false)
	flash_msg = cfg.get("msg", "")
	return self

func _ready() -> void:
	add_to_group("gate")
	var mi := MeshInstance3D.new()
	var lbl_y := 3.2
	var col_size := Vector3(1.6, 2.6, 0.4)
	if action == "":
		# TELEPORT PORTAL: tall glowing doorway
		var m := BoxMesh.new()
		m.size = Vector3(1.6, 2.6, 0.4)
		mi.mesh = m
		mi.position = Vector3(0, 1.3, 0)
	else:
		# BUTTON / TABLET: small block -- clearly NOT a portal
		var m2 := BoxMesh.new()
		m2.size = Vector3(0.9, 0.9, 0.9)
		mi.mesh = m2
		mi.position = Vector3(0, 0.45, 0)
		lbl_y = 1.6
		col_size = Vector3(1.0, 1.0, 1.0)
	mi.material_override = Destructible.make_material(color, 2.0)
	add_child(mi)
	if label_text != "":
		var lbl := Label3D.new()
		lbl.text = label_text + "  [F]"
		lbl.font_size = 34
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, lbl_y, 0)
		add_child(lbl)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = col_size
	col.shape = cs
	col.position = Vector3(0, col_size.y * 0.5, 0)
	add_child(col)

func use(player: Player) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	match action:
		"recipe":
			if not Inventory.ak47_recipe:
				Inventory.ak47_recipe = true
				if hud and hud.has_method("recipe_popup"):
					hud.recipe_popup("AK-47", "The tablet's markings resolve into a weapon. Craft it in the shop's Weapons tab: 20 ingot + 6 ultima.")
			return
		"mindcore":
			if not Game.mind_core:
				Game.mind_core = true
				Sfx.play("learn")
				if hud: hud.flash("MIND CORE ACTIVATED — the pyramid on Euclid unseals")
			return
		"artifact":
			if not Inventory.artifact_taken and Inventory.any_space():
				Inventory.artifact_taken = true
				Inventory.give_to_hotbar("voidhammer")
				Sfx.play("learn")
				if hud: hud.flash("THE VOIDHAMMER IS YOURS")
			return
		"pishrine":
			var pq := get_tree().get_first_node_in_group("pi_quiz")
			if pq and pq.has_method("open"):
				pq.open()
			return
		"terminal":
			var term := get_tree().get_first_node_in_group("terminal_ui")
			if term and term.has_method("open"):
				term.open()
			return
		"trials":
			var main := get_tree().current_scene
			if main and main.has_method("start_trials"):
				main.start_trials()
			return

	# --- teleport flow ---
	if requires == "door_open" and not Game.door_open:
		Sfx.play("denied")
		if hud: hud.flash("The temple door is sealed. Press the button. Solve the terminal.")
		return
	if requires == "trials_done" and not Game.trials_done:
		Sfx.play("denied")
		if hud: hud.flash("SEALED — the guardians still stand")
		return
	if requires == "mindcore" and not Game.mind_core:
		Sfx.play("denied")
		if hud: hud.flash("SEALED — activate the Mind Core in the Euclid Temple")
		return
	if warn_jetpack and not Inventory.has_jetpack:
		if hud: hud.flash("WARNING: zero gravity inside. You have NO JETPACK.")
	Game.zone = zone
	Game.zone_g = zone_g
	var up := Vector3.UP if zone != "" else (target - Universe.nearest(target).center).normalized()
	player.respawn_at(target, up)
	Sfx.play("warp")
	if flash_msg != "" and hud:
		hud.flash(flash_msg)
