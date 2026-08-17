class_name DiscMaker
extends Machine
## THE DISC MAKER. Cuts blanks and writes whatever you hand it: a whole
## cartridge, a loose script, a modular synth patch, a chiptune song. It
## does not care which -- a floppy is a dictionary with a kind on it,
## and every machine that reads one takes the kinds it understands.
##
## The one thing it will not do is turn a song back into a patch. A
## song is notes; a patch is a machine. You can render one from the
## other, not the other way round.

var discs: Array = []            # floppies sitting in the tray
var _last_shell: int = 0         # colour of the last blank it cut

func _init() -> void:
	title = "DISC MAKER"
	box_color = Color("#3f3a56")
	box_size = Vector3(1.1, 1.15, 0.9)
	buf_cap = 240.0
	refund_id = "discmaker"

func _ready() -> void:
	super._ready()
	dress_industrial(Color("#191624"))
	# the slot, the eject light, and a stack of blanks in a hopper
	var slot := BoxMesh.new()
	slot.size = Vector3(0.42, 0.03, 0.05)
	part(slot, Vector3(0, 0.72, box_size.z * 0.5), Color("#08080c"), 0.02)
	var led := SphereMesh.new()
	led.radius = 0.022
	led.height = 0.044
	part(led, Vector3(0.28, 0.72, box_size.z * 0.5 + 0.01), Color("#3aff6a"), 2.2)
	for i in 5:
		var blank := BoxMesh.new()
		blank.size = Vector3(0.3, 0.02, 0.3)
		part(blank, Vector3(-0.02, 0.95 + float(i) * 0.022, -0.1),
			Color("#3a3f4a") if i % 2 == 0 else Color("#4a4f5a"), 0.1)
	var head := BoxMesh.new()
	head.size = Vector3(0.5, 0.12, 0.4)
	part(head, Vector3(0, 0.86, 0.1), Color("#2a2735"), 0.1)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.06
	lens.bottom_radius = 0.06
	lens.height = 0.03
	part(lens, Vector3(0, 0.93, 0.1), Color("#4fa4ff"), 1.4)

func info_text() -> String:
	var lines := ["Writes floppies. Anything a machine can hold, a floppy can carry.",
		"discs in the tray: %d" % discs.size()]
	for d in discs:
		lines.append("  - [%s] %s" % [str(d.get("kind", "?")), str(d.get("name", "?"))])
	lines.append("energy: %.0f / %.0f EU" % [buf, buf_cap])
	return "\n".join(lines)

func actions() -> Array:
	return [
		["Cut a blank floppy  (5 EU)", func() -> void:
			if buf < 5.0:
				Sfx.play("denied")
				return
			buf -= 5.0
			var shell := ArcadeDisc.cut_blank()
			_last_shell = shell
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash("blank cut: %s shell" % ArcadeDisc.SHELL_COLORS[shell])
			Sfx.play("click")],
		["Take everything in the tray", func() -> void:
			for d in discs:
				Inventory.floppy_data.append(d)
				Inventory.give("floppy_data", 1)
			discs.clear()
			Sfx.play("click")],
	]

## Write a payload to a blank the player is carrying.
func write_disc(payload: Dictionary) -> bool:
	if Inventory.res_count("floppy") <= 0:
		return false
	if buf < 8.0:
		return false
	buf -= 8.0
	if not ArcadeDisc.write(payload):
		return false
	Sfx.play("coin", -12.0)
	return true
