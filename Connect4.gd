class_name Connect4
extends Node3D
## The Connect 4 Zer0-Gravity Island: a connect-4-shaped island floating
## deep in space (no gravity out here). Play the board on top -- F on a
## column block drops your disc, the island answers. Beat it: gold.

const COLS := 7
const ROWS := 6
const REWARD := 5000       # the AI is rigged; beating it should pay like it
const TIE_REWARD := 350   # holding it to a draw still earns something

var grid: Array = []        # grid[c][r] : 0 empty, 1 you, 2 island
var busy: bool = false
var over: bool = false
var _discs: Array = []      # placed disc meshes, for reset

func _ready() -> void:
	_reset_grid()
	_build_island()
	_build_board()

func _reset_grid() -> void:
	grid = []
	for c in COLS:
		var col: Array = []
		for r in ROWS:
			col.append(0)
		grid.append(col)

func _build_island() -> void:
	# the island itself is a giant connect-4 board lying flat
	for c in COLS:
		for r in ROWS:
			var slab := MeshInstance3D.new()
			var m := CylinderMesh.new()
			m.top_radius = 2.6
			m.bottom_radius = 2.6
			m.height = 1.6
			slab.mesh = m
			var col := Color("#2255cc") if (c + r) % 2 == 0 else Color("#1a44aa")
			slab.material_override = Destructible.make_material(col, 0.15)
			add_child(slab)
			slab.position = Vector3((float(c) - 3.0) * 6.0, -2.0, (float(r) - 2.5) * 6.0)
	# walkable deck
	var deck := StaticBody3D.new()
	var dm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(44, 1, 38)
	dm.mesh = bm
	dm.material_override = Destructible.make_material(Color("#16337a"), 0.1)
	deck.add_child(dm)
	var dc := CollisionShape3D.new()
	var ds := BoxShape3D.new()
	ds.size = Vector3(44, 1, 38)
	dc.shape = ds
	deck.add_child(dc)
	add_child(deck)
	deck.position = Vector3(0, -0.6, 0)

func _build_board() -> void:
	# upright frame
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(COLS * 2.0 + 1.0, ROWS * 2.0 + 1.0, 0.5)
	frame.mesh = fm
	frame.material_override = Destructible.make_material(Color("#2b6be0"), 0.4)
	add_child(frame)
	frame.position = Vector3(0, float(ROWS) + 0.5, -12.0)
	# hole rings
	for c in COLS:
		for r in ROWS:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.55
			tm.outer_radius = 0.8
			ring.mesh = tm
			ring.material_override = Destructible.make_material(Color("#0a1a3a"), 0.2)
			add_child(ring)
			ring.position = _cell_pos(c, r)
	# column drop blocks
	for c in COLS:
		var btn := _Col.new()
		btn.board = self
		btn.col = c
		add_child(btn)
		btn.position = Vector3((float(c) - 3.0) * 2.0, float(ROWS) * 2.0 + 2.6, -12.0)

func _cell_pos(c: int, r: int) -> Vector3:
	return Vector3((float(c) - 3.0) * 2.0, 1.6 + float(r) * 2.0, -12.0)

func drop(c: int) -> void:
	if busy or over:
		Sfx.play("denied")
		return
	if not _place(c, 1):
		Sfx.play("denied")
		return
	Sfx.play("place")
	if _check_end():
		return
	busy = true
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(func() -> void:
		busy = false
		_ai_move()
		_check_end())

func _place(c: int, who: int) -> bool:
	for r in ROWS:
		if int(grid[c][r]) == 0:
			grid[c][r] = who
			var disc := MeshInstance3D.new()
			var m := SphereMesh.new()
			m.radius = 0.8
			m.height = 1.0
			disc.mesh = m
			var col := Color("#ffd700") if who == 1 else Color("#ff3b3b")
			disc.material_override = Destructible.make_material(col, 1.5)
			add_child(disc)
			disc.position = _cell_pos(c, r)
			_discs.append(disc)
			return true
	return false

func _ai_move() -> void:
	if over:
		return
	# win if possible, else block, else centre-ish random
	for who in [2, 1]:
		for c in COLS:
			var r := _next_row(c)
			if r < 0:
				continue
			grid[c][r] = who
			var wins: bool = _winner() == who
			grid[c][r] = 0
			if wins:
				_place(c, 2)
				Sfx.play("place", -14.0)
				return
	var order := [3, 2, 4, 1, 5, 0, 6]
	order.shuffle()
	order.sort_custom(func(a, b): return absi(a - 3) < absi(b - 3) if randf() < 0.7 else randf() < 0.5)
	for c in order:
		if _next_row(c) >= 0:
			_place(c, 2)
			Sfx.play("place", -14.0)
			return

func _next_row(c: int) -> int:
	for r in ROWS:
		if int(grid[c][r]) == 0:
			return r
	return -1

func _winner() -> int:
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for c in COLS:
		for r in ROWS:
			var who := int(grid[c][r])
			if who == 0:
				continue
			for d in dirs:
				var n := 1
				for k in range(1, 4):
					var cc: int = c + d.x * k
					var rr: int = r + d.y * k
					if cc < 0 or cc >= COLS or rr < 0 or rr >= ROWS:
						break
					if int(grid[cc][rr]) == who:
						n += 1
					else:
						break
				if n >= 4:
					return who
	return 0

func _check_end() -> bool:
	var w := _winner()
	var full := true
	for c in COLS:
		if _next_row(c) >= 0:
			full = false
	if w == 0 and not full:
		return false
	over = true
	var hud := get_tree().get_first_node_in_group("hud")
	if w == 1:
		Inventory.add_coins(REWARD)
		Sfx.play("learn")
		if hud:
			hud.flash("the island concedes. %d gold." % REWARD)
	elif w == 2:
		Sfx.play("denied")
		if hud:
			hud.flash("the island wins. it always plays red.")
	else:   # board full, no winner -- a draw
		Inventory.add_coins(TIE_REWARD)
		Sfx.play("click")
		if hud:
			hud.flash("draw. %d gold." % TIE_REWARD)
	# board resets after a moment
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func() -> void:
		for d2 in _discs:
			if is_instance_valid(d2):
				d2.queue_free()
		_discs.clear()
		_reset_grid()
		over = false)
	return true

class _Col extends StaticBody3D:
	var board: Connect4
	var col: int = 0

	func _ready() -> void:
		add_to_group("c4_col")
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(1.2, 1.2, 1.2)
		mi.mesh = m
		mi.material_override = Destructible.make_material(Color("#ffd700"), 0.8)
		add_child(mi)
		var c2 := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(1.3, 1.3, 1.3)
		c2.shape = cs
		add_child(c2)

	func use() -> void:
		if board and is_instance_valid(board):
			board.drop(col)
