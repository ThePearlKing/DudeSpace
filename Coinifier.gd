class_name Coinifier
extends Machine
## SELL STATION (was: coinifier -- and it paid WAY too much). Load items,
## it sells them one at a time. Nerfed prices, takes time. Funnel your
## ingots in and let it drip coins.

const PRICES := {
	"ingot": 8, "irid": 20, "ultima": 100, "prism": 60, "circle": 95, "uranium": 45, "sulfur": 12,
	"cooked_meat": 5, "meat": 2, "banana": 2, "shroom": 3, "salad": 15, "coal": 1,
	"cheese": -10,   # the market HATES cheese. usually.
}
const SECS_PER_ITEM := 0.5

var _t: float = 0.0
var _cheese_warned := false
var _coin: MeshInstance3D
var _spin: float = 0.0

func _init() -> void:
	title = "SELL STATION"
	box_color = Color("#8a7a20")
	refund_id = "coinifier"
	add_to_group("coinifier")
	shows_out = false   # coins go straight to your wallet

func _ready() -> void:
	super._ready()
	dress_industrial(Color("#2a2410"))
	# striped kiosk awning over the front
	for i in 4:
		var slat := BoxMesh.new()
		slat.size = Vector3(0.36, 0.05, 0.55)
		part(slat, Vector3(-0.54 + float(i) * 0.36, box_size.y + 0.16 - float(i % 2) * 0.03,
			box_size.z * 0.5 + 0.1),
			Color("#ffe066") if i % 2 == 0 else Color("#3a3020"), 0.3, Vector3(-14, 0, 0))
	# big golden coin spinning above (the whole sales pitch)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.34
	cm.height = 0.09
	_coin = part(cm, Vector3(0, box_size.y + 0.85, 0), Color("#ffd700"), 2.2, Vector3(90, 0, 0))
	# coin slot + payout tray on the front
	var slotm := BoxMesh.new()
	slotm.size = Vector3(0.5, 0.08, 0.06)
	part(slotm, Vector3(0, 1.0, box_size.z * 0.5 + 0.03), Color("#141410"), 0.02)
	var tray := BoxMesh.new()
	tray.size = Vector3(0.7, 0.1, 0.3)
	part(tray, Vector3(0, 0.35, box_size.z * 0.5 + 0.14), Color("#2a2410"), 0.05)

func _process(delta: float) -> void:
	super._process(delta)
	if _coin:
		# showcase spin: standing coin turning around the machine's up axis
		_spin += delta * 130.0
		_coin.rotation_degrees = Vector3(90, _spin, 0)

func work(delta: float) -> void:
	var id := str(in_slot["id"])
	if not PRICES.has(id) or int(in_slot["n"]) <= 0:
		_t = 0.0
		return
	_t += delta
	if _t >= SECS_PER_ITEM:
		_t = 0.0
		in_slot["n"] = int(in_slot["n"]) - 1
		if int(in_slot["n"]) <= 0:
			in_slot = {"id": "", "n": 0}
		if id == "cheese":
			# cheese DRAINS the bank -- unless the market briefly loses
			# its mind (a small chance of 20-400 back)
			if randf() < 0.06:
				Inventory.add_coins(20 + randi() % 381)
				Sfx.play("coin", -6.0)
			else:
				Inventory.bank_coins = maxi(0, Inventory.bank_coins - 10)
				if Inventory.bank_coins <= 0:
					Inventory.coins = maxi(0, Inventory.coins - 10)
				Inventory.changed.emit()
				Sfx.play("denied", -20.0)
				if not _cheese_warned:
					_cheese_warned = true
					var hud = get_tree().get_first_node_in_group("hud")
					if hud:
						hud.flash("WARNING: cheese sells at -10. it is DRAINING your bank account")
		else:
			Inventory.add_coins(int(PRICES[id]))
			Sfx.play("coin", -18.0)

func accepts(id: String) -> bool:
	return PRICES.has(id)

func info_text() -> String:
	return "in: %s\nsells 1 item / %.1fs\ningot 8 · irid 20 · ultima 100\nCHEESE: -10/ea (drains BANK). rare payouts happen. allegedly." % [
		Inventory.slot_text(in_slot), SECS_PER_ITEM]

func actions() -> Array:
	return []
