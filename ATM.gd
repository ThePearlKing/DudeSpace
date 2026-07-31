class_name ATM
extends Machine
## Galactic ATM. ONE vault, in coins. Deposit coins, then withdraw as
## coins OR as ZeptoBux (10 coins = 1 ZB) straight from the balance --
## the conversion happens in the withdrawal, no extra button.

func _init() -> void:
	title = "ATM"
	box_color = Color("#1b2b4a")
	box_size = Vector3(2.0, 3.0, 1.2)
	refund_id = "atm"
	add_to_group("atm")

func _ready() -> void:
	super._ready()
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.4, 1.0, 0.1)
	screen.mesh = sm
	screen.position = Vector3(0, 2.0, -0.65)
	screen.material_override = Destructible.make_material(Color("#39ff14"), 4.0)
	add_child(screen)

func info_text() -> String:
	return "WALLET  %d coins · %d ZB\nBANK    %d coins  (= %d ZB)\n(bank = safe from death · 10 coins = 1 ZB)" % [
		Inventory.coins, Inventory.zeptobux,
		Inventory.bank_coins, Inventory.bank_coins / 10]

var _amount: LineEdit

## Custom panel: amount box + coin/ZB deposit-withdraw.
func build_ui(parent: Control) -> void:
	# legacy ZB sub-account folds into the coin vault (10 coins per ZB)
	if Inventory.bank_zepto > 0:
		Inventory.bank_coins += Inventory.bank_zepto * 10
		Inventory.bank_zepto = 0
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	var al := Label.new()
	al.text = "amount:"
	arow.add_child(al)
	_amount = LineEdit.new()
	_amount.placeholder_text = "empty = ALL"
	_amount.custom_minimum_size = Vector2(160, 38)
	arow.add_child(_amount)
	parent.add_child(arow)

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	crow.add_child(_mk_btn("Deposit coins", func() -> void: _move_coins(true)))
	crow.add_child(_mk_btn("Withdraw coins", func() -> void: _move_coins(false)))
	parent.add_child(crow)

	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 8)
	zrow.add_child(_mk_btn("Deposit ZB", func() -> void: _move_zb(true)))
	zrow.add_child(_mk_btn("Withdraw as ZB", func() -> void: _move_zb(false)))
	parent.add_child(zrow)


func _mk_btn(txt: String, cb: Callable, w: float = 185.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(w, 42)
	b.pressed.connect(cb)
	return b

## empty field = everything; otherwise the typed amount (capped at what exists)
func _amt(available: int) -> int:
	var t := _amount.text.strip_edges() if _amount else ""
	if t == "":
		return available
	return clampi(int(t.to_int()), 0, available)

func _move_coins(deposit: bool) -> void:
	var n := _amt(Inventory.coins if deposit else Inventory.bank_coins)
	if n <= 0:
		Sfx.play("denied")
		return
	if deposit:
		Inventory.coins -= n
		Inventory.bank_coins += n
	else:
		Inventory.bank_coins -= n
		Inventory.coins += n
	Sfx.play("coin")
	Inventory.changed.emit()

## ZB flows through the SAME coin vault: deposit turns ZB into banked
## coins, withdrawing turns banked coins into ZB. 10 coins = 1 ZB.
func _move_zb(deposit: bool) -> void:
	var n := _amt(Inventory.zeptobux if deposit else Inventory.bank_coins / 10)
	if n <= 0:
		Sfx.play("denied")
		return
	if deposit:
		Inventory.zeptobux -= n
		Inventory.bank_coins += n * 10
	else:
		Inventory.bank_coins -= n * 10
		Inventory.zeptobux += n
	Sfx.play("coin")
	Inventory.changed.emit()

