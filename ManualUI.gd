class_name ManualUI
extends CanvasLayer
## THE CHEMISTRY HANDBOOK. Every recipe in the game, in one book:
## what goes in, what comes out, how long it takes, which machine runs
## it, what the product is good for -- and, for anything you can make by
## hand, the exact sequence of operations the glassware wants.
##
## The book sits centred on the screen and lays its recipes out as a
## grid of cards, so a whole tier is readable at a glance instead of
## one long column you have to scroll through.

var _grid: GridContainer
var _root: Panel
var _scroll: ScrollContainer
var _filter: String = "ALL"
var _search: LineEdit

const BG := Color("#12100c")
const INK := Color("#e8dcc0")
const ACCENT := Color("#c8a227")

## card metrics -- the column count is derived from these, so changing
## the card width is enough to re-flow the whole book
const CARD_W := 452.0
const GAP := 12.0

## The tutorial (and anything else that wants to teach) can point the
## handbook at specific recipes: those cards get a pen circle drawn
## round them and the book scrolls itself open on the first one.
static var spotlight: Array = []

## Point the book at a set of material ids. Redraws a book already open.
static func point_at(ids: Array) -> void:
	spotlight = ids.duplicate()
	if _open_book != null and is_instance_valid(_open_book) \
			and _open_book.has_method("_rebuild"):
		_open_book._rebuild()

## One book, ever. A second copy deletes itself before it draws -- an
## earlier bug spawned one per frame and no amount of ESC could keep up.
static var _open_book: Node = null

func _ready() -> void:
	if _open_book != null and is_instance_valid(_open_book) and _open_book != self:
		queue_free()
		return
	_open_book = self
	layer = 20
	add_to_group("manual_ui")
	add_to_group("closable_ui")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root = Panel.new()
	# centred on the screen, sized to the viewport but never wider than
	# four card columns plus the margins
	_root.anchor_left = 0.5
	_root.anchor_top = 0.5
	_root.anchor_right = 0.5
	_root.anchor_bottom = 0.5
	var st := StyleBoxFlat.new()
	st.bg_color = BG
	st.border_color = ACCENT.darkened(0.4)
	st.set_border_width_all(3)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 18
	_root.add_theme_stylebox_override("panel", st)
	add_child(_root)
	var title := Label.new()
	title.text = "CHEMISTRY HANDBOOK"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	title.position = Vector2(24, 14)
	_root.add_child(title)
	var sub := Label.new()
	sub.text = "every recipe anybody has written down, including what the glassware wants"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#9a8f78"))
	sub.position = Vector2(26, 46)
	_root.add_child(sub)
	var x := Button.new()
	x.text = "✕"
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-56, 14)
	x.custom_minimum_size = Vector2(44, 40)
	x.pressed.connect(close)
	_root.add_child(x)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(24, 74)
	tabs.add_theme_constant_override("separation", 8)
	_root.add_child(tabs)
	for t in ["ALL", "BY HAND", "ALLOYS", "CHEM LAB", "ELECTROLYSER",
			"SEPARATOR", "CRYO", "VOID", "VAT"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(104, 34)
		b.pressed.connect(func() -> void:
			_filter = t
			_rebuild())
		tabs.add_child(b)
	_search = LineEdit.new()
	_search.placeholder_text = "search..."
	_search.position = Vector2(24, 118)
	_search.custom_minimum_size = Vector2(360, 34)
	_search.size = Vector2(360, 34)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	_root.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 24
	scroll.offset_top = 162
	scroll.offset_right = -24
	scroll.offset_bottom = -20
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_scroll = scroll
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	scroll.add_child(_grid)
	_fit()
	get_viewport().size_changed.connect(_fit)
	_rebuild()

## size the book to the current window and pick the column count that
## fits, then re-flow if the count actually changed
func _fit() -> void:
	if not is_instance_valid(_root):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(4.0 * CARD_W + 5.0 * GAP + 48.0, vp.x - 80.0)
	var h: float = minf(1000.0, vp.y - 70.0)
	_root.offset_left = -w * 0.5
	_root.offset_right = w * 0.5
	_root.offset_top = -h * 0.5
	_root.offset_bottom = h * 0.5
	var inner: float = w - 48.0
	var cols: int = clampi(int((inner + GAP) / (CARD_W + GAP)), 1, 4)
	if _grid != null and _grid.columns != cols:
		_grid.columns = cols

func close_ui() -> void:
	close()

func close() -> void:
	if _open_book == self:
		_open_book = null
	queue_free()
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

const FAM_LABEL := {"alloy": "ALLOY FURNACE", "chem": "CHEM LAB",
	"electro": "ELECTROLYSER", "sep": "SEPARATOR", "cryo": "CRYO PLANT",
	"void": "VOID SIPHON", "vat": "GROWTH VAT"}

func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	var hand := Mats.hand_makeable()
	var rows: Array = []
	for id in Mats.all().keys():
		var d: Dictionary = Mats.all()[id]
		if not d.has("inputs"):
			continue
		var fam := str(d.get("family", ""))
		var by_hand: bool = hand.has(str(id))
		match _filter:
			"BY HAND":
				if not by_hand:
					continue
			"ALLOYS":
				if fam != "alloy":
					continue
			"CHEM LAB":
				if fam != "chem":
					continue
			"ELECTROLYSER":
				if fam != "electro":
					continue
			"SEPARATOR":
				if fam != "sep":
					continue
			"CRYO":
				if fam != "cryo":
					continue
			"VOID":
				if fam != "void":
					continue
			"VAT":
				if fam != "vat":
					continue
		if q != "" and not str(d["name"]).to_lower().contains(q) \
				and not str(id).to_lower().contains(q):
			continue
		rows.append([str(id), d, by_hand])
	rows.sort_custom(func(a, b):
		var da: Dictionary = a[1]
		var db: Dictionary = b[1]
		if int(da["tier"]) != int(db["tier"]):
			return int(da["tier"]) < int(db["tier"])
		return str(da["name"]) < str(db["name"]))
	var first_circled: Control = null
	for row in rows:
		var card := _entry(str(row[0]), row[1], bool(row[2]))
		_grid.add_child(card)
		if first_circled == null and spotlight.has(str(row[0])):
			first_circled = card
	if first_circled != null:
		_scroll_to.call_deferred(first_circled)
	if rows.is_empty():
		var none := Label.new()
		none.text = "  nothing under that heading."
		none.add_theme_color_override("font_color", Color("#8a7f70"))
		_grid.add_child(none)

## one recipe card: colour chip + heading, the reaction itself, what the
## product is for, and the hand sequence when the glassware can do it
func _entry(id: String, d: Dictionary, by_hand: bool) -> Control:
	var col := Color(d.get("color", INK))
	var circled: bool = spotlight.has(id)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(CARD_W, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#191510")
	ps.border_color = col * Color(1, 1, 1, 0.5)
	ps.border_width_left = 4
	if circled:
		ps.bg_color = Color("#1f1a10")
		ps.border_color = ACCENT
		ps.set_border_width_all(2)
		ps.border_width_left = 4
	ps.set_content_margin_all(10)
	ps.corner_radius_top_right = 4
	ps.corner_radius_bottom_right = 4
	p.add_theme_stylebox_override("panel", ps)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	p.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var chip := ColorRect.new()
	chip.color = col
	chip.custom_minimum_size = Vector2(14, 14)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chip)
	var nm := Label.new()
	nm.text = str(d["name"])
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var tag := Label.new()
	tag.text = "T%d · %s" % [int(d["tier"]),
		str(FAM_LABEL.get(str(d.get("family", "")), "?"))]
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color",
		ACCENT if circled else Color("#9a8f78"))
	head.add_child(tag)
	var ing: Array = []
	for k in (d["inputs"] as Dictionary).keys():
		ing.append("%d x %s" % [int(d["inputs"][k]), Inventory.hotbar_name(str(k))])
	var line := Label.new()
	line.text = "%s  ->  %d x %s   (%.0fs)" % [
		" + ".join(ing) if ing.size() > 0 else "thin air",
		int(d.get("out_n", 1)), str(d["name"]), float(d.get("secs", 8.0))]
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_color_override("font_color", INK)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(line)
	var uses := Label.new()
	uses.text = "used for: " + (str(d.get("uses", "")) if str(d.get("uses", "")) != ""
		else "building machines and the tiers above it")
	uses.add_theme_font_size_override("font_size", 13)
	uses.add_theme_color_override("font_color", Color("#9a8f78"))
	uses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(uses)
	if circled:
		var ring := _Ring.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(ring)
	if by_hand:
		var seq := Label.new()
		seq.text = "BY HAND:  " + "  ->  ".join(Mats.hand_sequence(id))
		seq.add_theme_font_size_override("font_size", 14)
		seq.add_theme_color_override("font_color", Color("#3aff6a"))
		seq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(seq)
	return p


func _exit_tree() -> void:
	if _open_book == self:
		_open_book = null


## Bring a circled card into view once the grid has laid itself out.
func _scroll_to(card: Control) -> void:
	if not is_instance_valid(_scroll) or not is_instance_valid(card):
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll) and is_instance_valid(card):
		_scroll.ensure_control_visible(card)


## A pen circle round a recipe -- deliberately not a rectangle: it reads
## as somebody's hand ringing the entry in their own copy of the book.
## The wobble is baked from the node's index so it never crawls.
class _Ring extends Control:
	var _t: float = 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r: Vector2 = size
		if r.x < 8.0 or r.y < 8.0:
			return
		var mid: Vector2 = r * 0.5
		var rad: Vector2 = Vector2(r.x * 0.5 - 3.0, r.y * 0.5 - 3.0)
		var pulse: float = 0.72 + 0.28 * sin(_t * 3.0)
		var pts := PackedVector2Array()
		var n := 72
		for i in range(n + 5):
			var a: float = float(i) / float(n) * TAU
			# hand-drawn wobble: the pen never closes a circle cleanly
			var w: float = 1.0 + 0.022 * sin(a * 3.0 + 1.1) + 0.014 * sin(a * 7.0)
			pts.append(mid + Vector2(cos(a) * rad.x * w, sin(a) * rad.y * w))
		# thin enough to read straight through: the circle marks the card,
		# it does not black out the recipe underneath it
		draw_polyline(pts, Color(0.78, 0.63, 0.15, 0.18 * pulse), 6.0, true)
		draw_polyline(pts, Color(1.0, 0.85, 0.28, 0.85 * pulse), 2.0, true)
