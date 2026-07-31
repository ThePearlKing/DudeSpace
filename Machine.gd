class_name Machine
extends StaticBody3D
## Base for all processing machines: an energy buffer (EU), an input and
## an output item slot, energy WIRES out, item FUNNELS out, timed work,
## and selection/hover glow for the wiring tools.

var title: String = "MACHINE"
var box_color: Color = Color("#666677")
var box_size: Vector3 = Vector3(1.4, 1.4, 1.4)
var refund_id: String = ""        # what breaking it gives back

var buf: float = 0.0              # stored energy (EU)
var buf_cap: float = 0.0          # 0 = not on the power net
var gen_rate: float = 0.0         # passive EU/s
const WIRE_RATE := 40.0           # EU/s per wire

var in_slot: Dictionary = {"id": "", "n": 0}
var out_slot: Dictionary = {"id": "", "n": 0}
var wires_out: Array = []         # Machines receiving energy
var wire_ports: Array = []        # port number per wire (computers use these)
var funnels_out: Array = []       # Machines receiving items
var funnel_ports: Array = []      # port number per funnel
var _conn_vis: Array = []         # {t, kind, nodes[]} cable visuals
var has_coil: bool = false        # control coil: machine runs only if powered
var coil_buf: float = 0.0
const COIL_CAP := 30.0
const COIL_DRAIN := 0.5
var _coil_mat: StandardMaterial3D
var _funnel_t: float = 0.0
var _mat: StandardMaterial3D
var _base_emit: float = 0.3
var _sel: bool = false
var _hov: bool = false
var _role: int = 0   # tool highlight: 0 none · 1 can-output (blue) · 2 can-input (green)

var _mesh: MeshInstance3D

# --- computer console (used by the programmable machines) ---
var console: Array = []           # printed lines
var console_input: String = ""    # what the user last typed into the console

func cprint(args: Array) -> void:
	var parts: Array = []
	for a in args:
		parts.append(str(a))
	console.append(" ".join(parts))
	while console.size() > 80:
		console.pop_front()

func cclear() -> void:
	console.clear()

func _ready() -> void:
	add_to_group("machine")
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = box_size
	mi.mesh = m
	mi.position = Vector3(0, box_size.y * 0.5, 0)
	_mat = Destructible.make_material(box_color, _base_emit)
	mi.material_override = _mat
	add_child(mi)
	_mesh = mi
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = box_size
	col.shape = cs
	col.position = Vector3(0, box_size.y * 0.5, 0)
	add_child(col)
	var lbl := Label3D.new()
	lbl.text = title + "  [F]"
	lbl.font_size = 26
	lbl.modulate = Color(1, 1, 1, 0.75)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, box_size.y + 0.9, 0)
	add_child(lbl)

func _process(delta: float) -> void:
	if _hits > 0:
		_hit_reset_t -= delta
		if _hit_reset_t <= 0.0:
			_hits = 0
	# prune connections whose far end died -> their cables vanish too
	for entry in _conn_vis.duplicate():
		if not is_instance_valid(entry["t"]):
			for nd in entry["nodes"]:
				if is_instance_valid(nd):
					nd.queue_free()
			_conn_vis.erase(entry)
			_drop_conn(entry["t"], entry["kind"])
	# --- control coil (separate node): no charge in it = machine OFF ---
	var gated := has_coil and coil_node != null and coil_node.buf <= 0.0
	if not gated:
		if gen_rate > 0.0 and buf_cap > 0.0:
			buf = minf(buf_cap, buf + gen_rate * delta)
		work(delta)
	# --- push energy along wires (a coil is just another receiver) ---
	for w in wires_out:
		if not is_instance_valid(w) or buf <= 0.0:
			continue
		if "buf_cap" in w and w.buf_cap > 0.0 and buf > 0.0:
			var t: float = minf(minf(WIRE_RATE * delta, buf), w.buf_cap - w.buf)
			if t > 0.0:
				buf -= t
				w.buf += t
	# --- push items along funnels (1 item / 0.7s per funnel) ---
	_funnel_t -= delta
	if _funnel_t <= 0.0 and not gated:
		_funnel_t = 0.7
		for f in funnels_out:
			if not is_instance_valid(f):
				continue
			var id := str(out_slot["id"])
			if id == "" or int(out_slot["n"]) <= 0:
				break
			if f.has_method("accept_item") and f.accept_item(id):
				out_slot["n"] = int(out_slot["n"]) - 1
				if int(out_slot["n"]) <= 0:
					out_slot = {"id": "", "n": 0}

## Try to push one item of `id` into this machine's input slot.
func accept_item(id: String) -> bool:
	if not accepts(id):
		return false
	if str(in_slot["id"]) == "":
		in_slot = {"id": id, "n": 1}
		return true
	if str(in_slot["id"]) == id and int(in_slot["n"]) < 999:
		in_slot["n"] = int(in_slot["n"]) + 1
		return true
	return false

# ------------------------------------------------------------- virtuals

func work(_delta: float) -> void:
	pass

func accepts(_id: String) -> bool:
	return false

func info_text() -> String:
	return ""

## UI actions: Array of [button label, Callable]
func actions() -> Array:
	return []

# --------------------------------------------------------------- UI/use

func use() -> void:
	var ui := get_tree().get_first_node_in_group("machine_ui")
	if ui and ui.has_method("open_machine"):
		ui.open_machine(self)

func load_from_hotbar(ids: Array) -> void:
	# the machine UI's amount box decides how many go in (-1 = all)
	var want := -1
	var ui = get_tree().get_first_node_in_group("machine_ui")
	if ui and ui.has_method("load_amount"):
		want = ui.load_amount()
	for id in ids:
		var have := Inventory.res_count(id)
		if have <= 0:
			continue
		if str(in_slot["id"]) != "" and str(in_slot["id"]) != id:
			continue
		var take := have if want < 0 else mini(want, have)
		if take <= 0:
			continue
		Inventory.remove_res(id, take)
		if str(in_slot["id"]) == "":
			in_slot = {"id": id, "n": take}
		else:
			in_slot["n"] = int(in_slot["n"]) + take
		Sfx.play("click")
		return
	Sfx.play("denied")

## Everything in the input slot goes back to your bags.
func take_input() -> void:
	if str(in_slot["id"]) == "" or int(in_slot["n"]) <= 0:
		Sfx.play("denied")
		return
	Inventory.give(str(in_slot["id"]), int(in_slot["n"]))
	in_slot = {"id": "", "n": 0}
	Sfx.play("click")

func take_output() -> void:
	if str(out_slot["id"]) == "" or int(out_slot["n"]) <= 0:
		Sfx.play("denied")
		return
	Inventory.add_res(str(out_slot["id"]), int(out_slot["n"]))
	out_slot = {"id": "", "n": 0}
	Sfx.play("coin")

# ------------------------------------------------------------ wiring fx

func set_selected(on: bool) -> void:
	_sel = on
	_update_glow()

func set_hover(on: bool) -> void:
	_hov = on
	_update_glow()

func set_role_glow(r: int) -> void:
	if _role != r:
		_role = r
		_update_glow()

## Can this machine act as a source/target for a cable kind?
func can_role(kind: String, as_input: bool) -> bool:
	if kind == "power":
		if as_input:
			return buf_cap > 0.0 or has_coil
		return buf_cap > 0.0 or gen_rate > 0.0
	# items
	if as_input:
		return has_method("accept_item") and _accepts_anything()
	return true   # anything with an output slot may feed a funnel

func _accepts_anything() -> bool:
	for id in ["raw_ingot", "raw_irid", "coal", "ingot", "irid", "ultima",
			"meat", "cooked_meat", "banana", "plantfiber", "shroom", "salad", "permapple"]:
		if accepts(id):
			return true
	return false

func _update_glow() -> void:
	if _mat == null:
		return
	if _sel:
		_mat.emission = Color("#ffffff")
		_mat.emission_energy_multiplier = 3.0
	elif _hov:
		_mat.emission = box_color.lightened(0.4)
		_mat.emission_energy_multiplier = 1.5
	elif _role == 1:
		_mat.emission = Color("#3a8aff")   # blue: valid OUTPUT
		_mat.emission_energy_multiplier = 1.0
	elif _role == 2:
		_mat.emission = Color("#2bff5a")   # green: valid INPUT
		_mat.emission_energy_multiplier = 1.0
	else:
		_mat.emission = box_color
		_mat.emission_energy_multiplier = _base_emit

## Connect this machine's OUTPUT to dst's INPUT ("power" or "item").
## Draws a solid cable (funnels are THICKER) with a direction arrow.
## Multiple connections spread sideways so they never share one line.
## How many selectable ports this machine offers for a cable kind.
func port_count(_kind: String) -> int:
	return 1

## The control coil as its OWN node: a separate wire target from the
## machine block. Wire power INTO the coil; it drains constantly; while
## it holds charge the host machine is allowed to run.
class CoilNode extends StaticBody3D:
	var host: Machine
	var buf: float = 0.0
	var buf_cap: float = 30.0
	var box_size := Vector3(0.9, 3.4, 0.9)   # duck-typed for cable endpoints
	var _mat2: StandardMaterial3D

	func _ready() -> void:
		add_to_group("machine")   # role-glow + targeting like any machine
		collision_layer = 2       # clickable, not a wall
		collision_mask = 0
		_mat2 = Destructible.make_material(Color("#ff9a3c"), 0.5)
		var rod := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.08
		rm.bottom_radius = 0.08
		rm.height = 1.5
		rod.mesh = rm
		rod.position = Vector3(0, 0.75, 0)
		rod.material_override = Destructible.make_material(Color("#3a3a42"), 0.1)
		add_child(rod)
		for i in 7:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.2
			tm.outer_radius = 0.36
			ring.mesh = tm
			ring.material_override = _mat2
			ring.position = Vector3(0, 0.15 + float(i) * 0.19, 0)
			add_child(ring)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		tip.mesh = sm
		tip.material_override = _mat2
		tip.position = Vector3(0, 1.6, 0)
		add_child(tip)
		var cc := CollisionShape3D.new()
		var cs2 := CapsuleShape3D.new()
		cs2.radius = 0.45
		cs2.height = 1.9
		cc.shape = cs2
		cc.position = Vector3(0, 0.85, 0)
		add_child(cc)

	func _process(delta: float) -> void:
		buf = maxf(0.0, buf - 0.5 * delta)
		if _mat2:
			_mat2.emission_energy_multiplier = 0.2 + (buf / buf_cap) * 4.0

	# duck-typed hooks so the wiring tool treats it politely
	func set_selected(_on: bool) -> void:
		pass
	func set_hover(on: bool) -> void:
		if _mat2:
			_mat2.emission_energy_multiplier = 2.5 if on else 0.2 + (buf / buf_cap) * 4.0
	var _role2: int = 0
	func set_role_glow(r: int) -> void:
		_role2 = r
		if _mat2:
			_mat2.emission = Color("#2bff5a") if r == 2 else Color("#ff9a3c")
	func can_role(kind: String, as_input: bool) -> bool:
		return kind == "power" and as_input

## Clickable cable body: the tools can cut a cable by shooting it.
class CableBody extends StaticBody3D:
	var owner_m: Machine
	var dst_m: Node3D
	var kind_s: String

func _drop_conn(dst: Node3D, kind: String) -> void:
	if kind == "power":
		var i := wires_out.find(dst)
		if i >= 0:
			wires_out.remove_at(i)
			if i < wire_ports.size():
				wire_ports.remove_at(i)
	else:
		var i2 := funnels_out.find(dst)
		if i2 >= 0:
			funnels_out.remove_at(i2)
			if i2 < funnel_ports.size():
				funnel_ports.remove_at(i2)

func connect_wire(dst: Node3D, kind: String, port: int = 0) -> void:
	# how many cables already leave this machine -> lateral slot
	var idx := wires_out.size() + funnels_out.size()
	if kind == "power":
		wires_out.append(dst)
		wire_ports.append(port if port > 0 else wires_out.size())
	else:
		funnels_out.append(dst)
		funnel_ports.append(port if port > 0 else funnels_out.size())
	var col := Color("#5ad0ff") if kind == "power" else Color("#ffa040")
	var radius := 0.05 if kind == "power" else 0.14   # funnels are pipes
	var a := global_position + Vector3(0, box_size.y * 0.5, 0)
	var dh: float = dst.box_size.y * 0.5 if "box_size" in dst else 0.8
	var b := dst.global_position + Vector3(0, dh, 0)
	var dir := (b - a).normalized()
	# spread: 0, +0.45, -0.45, +0.9, -0.9 ... SIDEWAYS along the local
	# surface (machine's up), never down into the ground
	var upv := global_transform.basis.y
	var perp := dir.cross(upv)
	if perp.length() < 0.05:
		perp = dir.cross(Vector3.RIGHT)
	if perp.length() < 0.05:
		perp = dir.cross(Vector3.UP)
	perp = perp.normalized()
	var off := perp * (ceilf(float(idx) / 2.0) * 0.45) * (1.0 if idx % 2 == 1 else -1.0)
	if idx == 0:
		off = Vector3.ZERO
	a += off
	b += off

	var parent := get_parent()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mat.albedo_color = col
	# --- sample the cable path: on a planet it HUGS the surface arc
	# instead of chording straight through the dirt ---
	var pts: Array = []
	var nseg := clampi(int(a.distance_to(b) / 5.0), 1, 32)
	var body0 = Universe.nearest(a)
	var bc: Vector3 = body0.center
	var da: Vector3 = a - bc
	var db: Vector3 = b - bc
	var arc: bool = Game.zone == "" \
		and da.length() < float(body0.radius) * 2.0 and db.length() < float(body0.radius) * 2.0 \
		and da.normalized().dot(db.normalized()) > -0.95
	for i in nseg + 1:
		var t := float(i) / float(nseg)
		if arc:
			var d3: Vector3 = da.normalized().slerp(db.normalized(), t)
			pts.append(bc + d3 * lerpf(da.length(), db.length(), t))
		else:
			pts.append(a.lerp(b, t))
	var nodes_local: Array = []
	for i in nseg:
		var pa: Vector3 = pts[i]
		var pb: Vector3 = pts[i + 1]
		var sdir := (pb - pa).normalized()
		var seg := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = radius
		cm2.bottom_radius = radius
		cm2.height = pa.distance_to(pb) + 0.05
		seg.mesh = cm2
		seg.material_override = mat
		parent.add_child(seg)
		seg.global_position = (pa + pb) * 0.5
		var axis2 := Vector3.UP.cross(sdir)
		if axis2.length() > 0.01:
			seg.rotate(axis2.normalized(), Vector3.UP.angle_to(sdir))
		nodes_local.append(seg)
	# the ARROW: cone past the midpoint pointing at the receiver
	var ai := int(float(nseg) * 0.55)
	var adir: Vector3 = (pts[mini(ai + 1, nseg)] - pts[ai]).normalized()
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius + 0.16
	cm.height = 0.7
	cone.mesh = cm
	cone.material_override = mat
	parent.add_child(cone)
	cone.global_position = pts[ai]
	var axis := Vector3.UP.cross(adir)
	if axis.length() > 0.01:
		cone.rotate(axis.normalized(), Vector3.UP.angle_to(adir))
	# invisible clickable bodies riding each cable segment (tools cut it)
	for i in nseg:
		var pa2: Vector3 = pts[i]
		var pb2: Vector3 = pts[i + 1]
		var sdir2 := (pb2 - pa2).normalized()
		var cbody := CableBody.new()
		cbody.owner_m = self
		cbody.dst_m = dst
		cbody.kind_s = kind
		cbody.collision_layer = 2   # raycast-only: the player walks through
		cbody.collision_mask = 0
		var ccol := CollisionShape3D.new()
		var ccs := CapsuleShape3D.new()
		ccs.radius = radius + 0.18
		ccs.height = pa2.distance_to(pb2) + 0.1
		ccol.shape = ccs
		ccol.rotation_degrees = Vector3(90, 0, 0)
		cbody.add_child(ccol)
		parent.add_child(cbody)
		cbody.global_position = (pa2 + pb2) * 0.5
		var axc := Vector3.UP.cross(sdir2)
		if axc.length() > 0.01:
			cbody.rotate(axc.normalized(), Vector3.UP.angle_to(sdir2))
		nodes_local.append(cbody)
	nodes_local.append(cone)
	_conn_vis.append({"t": dst, "kind": kind, "nodes": nodes_local, "port": port})

## Remove an existing connection (tool clicked src -> dst again).
## Returns true if one was removed; its cable disappears.
func disconnect_wire(dst: Node3D, kind: String) -> bool:
	for entry in _conn_vis:
		if entry["t"] == dst and entry["kind"] == kind:
			for nd in entry["nodes"]:
				if is_instance_valid(nd):
					nd.queue_free()
			_conn_vis.erase(entry)
			_drop_conn(dst, kind)
			return true
	return false

## Slap a control coil on top: a SEPARATE node. Wire power into the
## coil itself -- while it holds charge, this machine is allowed to run.
var coil_node: CoilNode = null

func add_coil() -> void:
	if has_coil:
		return
	has_coil = true
	coil_node = CoilNode.new()
	coil_node.host = self
	add_child(coil_node)
	coil_node.position = Vector3(0, box_size.y + 0.2, 0)

var _hits: int = 0
var _hit_reset_t: float = 0.0

## Machines take 3 HITS to break (no more one-tap capacitor accidents).
## The count forgives itself after a minute.
func destroy(push_dir: Vector3) -> void:
	_hits += 1
	_hit_reset_t = 60.0
	if _hits < 3:
		Sfx.play("hurt", -14.0)
		if _mat:
			_mat.emission = Color("#ffffff")
			_mat.emission_energy_multiplier = 3.5
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_callback(_update_glow)
		return
	_on_destroyed(push_dir)

func _on_destroyed(push_dir: Vector3) -> void:
	if has_coil:
		Inventory.give_at("coil", 1, global_position)
	# take our outgoing cables with us
	for entry in _conn_vis:
		for nd in entry["nodes"]:
			if is_instance_valid(nd):
				nd.queue_free()
	if refund_id != "":
		Inventory.give_at(refund_id, 1, global_position)
	if str(in_slot["id"]) != "":
		Inventory.give_at(str(in_slot["id"]), int(in_slot["n"]), global_position)
	if str(out_slot["id"]) != "":
		Inventory.give_at(str(out_slot["id"]), int(out_slot["n"]), global_position)
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.7, 0), box_size * 0.8, box_color, push_dir)
	Sfx.play("explode", -12.0)
	queue_free()
