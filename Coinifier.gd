class_name Coinifier
extends Machine
## SELL STATION (was: coinifier -- and it paid WAY too much). Load items,
## it sells them one at a time. Nerfed prices, takes time. Funnel your
## ingots in and let it drip coins.

const PRICES := {
	"ingot": 8, "irid": 20, "ultima": 100, "prism": 60, "circle": 95,
	"cooked_meat": 5, "meat": 2, "banana": 2, "shroom": 3, "salad": 15, "coal": 1,
}
const SECS_PER_ITEM := 0.5

var _t: float = 0.0

func _init() -> void:
	title = "SELL STATION"
	box_color = Color("#8a7a20")
	refund_id = "coinifier"
	add_to_group("coinifier")

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
		Inventory.add_coins(int(PRICES[id]))
		Sfx.play("coin", -18.0)

func accepts(id: String) -> bool:
	return PRICES.has(id)

func info_text() -> String:
	return "in: %s\nsells 1 item / %.1fs\ningot 8 · irid 20 · ultima 100" % [
		Inventory.slot_text(in_slot), SECS_PER_ITEM]

func actions() -> Array:
	return []
