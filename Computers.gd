class_name Computers
extends RefCounted
## The programmable machines. Scripts are Lua-ish (see MiniLua), edited
## in-game via the code editor, executed twice a second.

## ELECTRIC COMPUTER: reads its energy input, gates up to 8 output wires.
##   env in:  inp1 = stored EU (also inp2..inp8 = same, for future ports)
##   env out: out1..out8 = 1/0 -> enables/disables output wire 1..8
## example:
##   if inp1 > 50 then
##     out1 = 1
##   else
##     out1 = 0
##   end
class EComputer extends Machine:
	var script_src: String = "-- electric computer\n-- inp1 = stored EU. out1..out8 gate the wires.\nif inp1 > 50 then\n  out1 = 1\nelse\n  out1 = 0\nend"
	var outs: Array = [true, true, true, true, true, true, true, true]
	var last_err: String = ""
	var _tick: float = 0.0

	var _screen_mat: StandardMaterial3D
	var _leds: Array = []
	var _blink: float = 0.0

	func _init() -> void:
		title = "E-COMPUTER"
		box_color = Color("#1a2a3a")
		box_size = Vector3(1.2, 2.0, 1.2)
		refund_id = "ecomputer"
		buf_cap = 300.0

	func _ready() -> void:
		super._ready()
		# terminal screen on the front
		var scr := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.9, 0.7, 0.06)
		scr.mesh = sm
		scr.position = Vector3(0, 1.35, -box_size.z * 0.5 - 0.04)
		_screen_mat = StandardMaterial3D.new()
		_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_screen_mat.emission_enabled = true
		_screen_mat.emission = Color("#2bff5a")
		_screen_mat.emission_energy_multiplier = 1.5
		_screen_mat.albedo_color = Color("#0a1a0a")
		scr.material_override = _screen_mat
		add_child(scr)
		# 8 port LEDs down the right side, one per output port
		for i in 8:
			var led := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.1, 0.1, 0.06)
			led.mesh = lm
			led.position = Vector3(box_size.x * 0.5 + 0.04, 1.75 - float(i) * 0.18, -0.3)
			var lmat := StandardMaterial3D.new()
			lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lmat.emission_enabled = true
			led.material_override = lmat
			add_child(led)
			_leds.append(lmat)
		dress_industrial(Color("#101820"))
		# a real workstation: keyboard shelf, key rows, cable conduit,
		# cooling grille + spinning fan disc
		var shelf := BoxMesh.new()
		shelf.size = Vector3(0.9, 0.06, 0.4)
		part(shelf, Vector3(0, 0.9, -box_size.z * 0.5 - 0.2), Color("#1a222c"), 0.1)
		for r in 3:
			for c in 8:
				var key := BoxMesh.new()
				key.size = Vector3(0.08, 0.03, 0.08)
				part(key, Vector3(-0.38 + float(c) * 0.105, 0.945,
					-box_size.z * 0.5 - 0.1 - float(r) * 0.11),
					Color("#2e3a46") if (r + c) % 2 == 0 else Color("#27323d"), 0.15)
		var conduit := CylinderMesh.new()
		conduit.top_radius = 0.07
		conduit.bottom_radius = 0.07
		conduit.height = 1.6
		part(conduit, Vector3(-box_size.x * 0.5 - 0.04, 0.8, 0.2), Color("#0e141a"), 0.05)
		var grille := BoxMesh.new()
		grille.size = Vector3(0.5, 0.5, 0.04)
		part(grille, Vector3(0, 0.45, box_size.z * 0.5 + 0.02), Color("#0e141a"), 0.05)
		var fan := CylinderMesh.new()
		fan.top_radius = 0.18
		fan.bottom_radius = 0.18
		fan.height = 0.05
		_fan = part(fan, Vector3(0, 0.45, box_size.z * 0.5 + 0.05), Color("#3a4a5a"), 0.3,
			Vector3(90, 0, 0))

	var _fan: MeshInstance3D

	func _process(delta: float) -> void:
		_blink += delta
		if _fan:
			_fan.rotation_degrees.y += delta * (90.0 + 500.0 * buf / buf_cap)
		# screen: alive-green pulse while healthy, angry red on script error
		if _screen_mat:
			if last_err != "":
				_screen_mat.emission = Color("#ff2b2b")
				_screen_mat.emission_energy_multiplier = 1.0 + absf(sin(_blink * 8.0)) * 2.5
			else:
				_screen_mat.emission = Color("#2bff5a")
				_screen_mat.emission_energy_multiplier = 1.0 + absf(sin(_blink * 2.2)) * 0.8
		# LEDs mirror out1..out8 live
		for i in _leds.size():
			var on: bool = outs[i]
			_leds[i].emission = Color("#2bff5a") if on else Color("#401010")
			_leds[i].emission_energy_multiplier = 3.0 if on else 0.4
		_tick += delta
		if _tick >= 0.5:
			_tick = 0.0
			var env := {}
			for i in 8:
				env["inp%d" % (i + 1)] = buf
				env["out%d" % (i + 1)] = 1 if outs[i] else 0
			var funcs := {
				"print": func(args: Array): cprint(args); return 0,
				"clear": func(_a: Array): cclear(); return 0,
				"input": func(_a: Array): return console_input,
			}
			var res := MiniLua.run(script_src, env, funcs)
			if res.has("err"):
				last_err = res["err"]
			else:
				last_err = ""
				var e: Dictionary = res["env"]
				for i in 8:
					outs[i] = MiniLua._truthy(e.get("out%d" % (i + 1), 0))
		# push energy ONLY on enabled ports (port chosen with the wiring tool)
		for k in wires_out.size():
			var w = wires_out[k]
			var pt: int = int(wire_ports[k]) if k < wire_ports.size() else k + 1
			if pt >= 1 and pt <= 8 and not outs[pt - 1]:
				continue
			if is_instance_valid(w) and w.buf_cap > 0.0 and buf > 0.0:
				var t: float = minf(minf(WIRE_RATE * delta, buf), w.buf_cap - w.buf)
				if t > 0.0:
					buf -= t
					w.buf += t

	func port_count(kind: String) -> int:
		return 8 if kind == "power" else 1

	func info_text() -> String:
		var flags := ""
		for i in 8:
			flags += "%d" % (1 if outs[i] else 0)
		var ports := ""
		for k in wires_out.size():
			ports += "%d " % (int(wire_ports[k]) if k < wire_ports.size() else k + 1)
		var e := ("\nERR: " + last_err) if last_err != "" else ""
		return "energy: %.0f / %.0f EU\nout flags: %s\nwired to ports: %s%s" % [buf, buf_cap, flags, ports, e]

	func actions() -> Array:
		return [["Edit Code", func() -> void:
			var ui := get_tree().get_first_node_in_group("code_ui")
			if ui and ui.has_method("open_for"):
				ui.open_for(self)]]

## SORTER COMPUTER: items funnel IN, your script routes them out.
##   env: funnel = current item id (string), port starts 0 (= hold)
##   sort(funnel, 2) sends the item down funnel connection #2
## example:
##   if funnel == "coal" then
##     sort(funnel, 1)
##   else
##     sort(funnel, 2)
##   end
class SorterComputer extends Machine:
	var script_src: String = "-- sorter\n-- funnel = current item id. sort(funnel, port)\nif funnel == \"coal\" then\n  sort(funnel, 1)\nelse\n  sort(funnel, 2)\nend"
	var last_err: String = ""
	var _tick: float = 0.0
	var _route: int = 0

	var _screen_mat2: StandardMaterial3D
	var _blink2: float = 0.0

	func _init() -> void:
		title = "SORTER"
		box_color = Color("#3a2a4a")
		box_size = Vector3(1.3, 1.6, 1.3)
		refund_id = "scomputer"

	func _ready() -> void:
		super._ready()
		# hopper mouth on top: items pour in here
		var hop := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.65
		hm.bottom_radius = 0.25
		hm.height = 0.6
		hop.mesh = hm
		hop.position = Vector3(0, box_size.y + 0.3, 0)
		hop.material_override = Destructible.make_material(Color("#ffa040"), 0.6)
		add_child(hop)
		# routing screen
		var scr := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.9, 0.5, 0.06)
		scr.mesh = sm
		scr.position = Vector3(0, 1.0, -box_size.z * 0.5 - 0.04)
		_screen_mat2 = StandardMaterial3D.new()
		_screen_mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_screen_mat2.emission_enabled = true
		_screen_mat2.emission = Color("#c86bff")
		_screen_mat2.emission_energy_multiplier = 1.4
		_screen_mat2.albedo_color = Color("#140a1a")
		scr.material_override = _screen_mat2
		add_child(scr)
		dress_industrial(Color("#241a30"))
		# the sorting guts on display: two angled outlet chutes with port
		# lamps, a shaking sieve tray under the hopper
		for sd in [-1.0, 1.0]:
			var chute := CylinderMesh.new()
			chute.top_radius = 0.16
			chute.bottom_radius = 0.16
			chute.height = 0.9
			part(chute, Vector3(sd * (box_size.x * 0.5 + 0.2), 0.55, 0.2),
				Color("#4a3a5e"), 0.3, Vector3(0, 0, sd * 38.0))
			var lamp := SphereMesh.new()
			lamp.radius = 0.09
			lamp.height = 0.18
			part(lamp, Vector3(sd * (box_size.x * 0.5 + 0.34), 0.28, 0.2),
				Color("#c86bff"), 1.8)
		var sieve := BoxMesh.new()
		sieve.size = Vector3(0.9, 0.07, 0.9)
		_sieve = part(sieve, Vector3(0, box_size.y - 0.1, 0), Color("#2a2034"), 0.2)

	var _sieve: MeshInstance3D

	func port_count(kind: String) -> int:
		return 8 if kind == "item" else 1

	func accepts(_id: String) -> bool:
		return true   # eats anything, routes everything

	func _process(delta: float) -> void:
		_blink2 += delta
		if _sieve:
			# the sieve rattles harder the more it's routing
			_sieve.position.x = sin(_blink2 * 22.0) * (0.015 + 0.03 * minf(1.0, buf / 50.0))
		if _screen_mat2:
			if last_err != "":
				_screen_mat2.emission = Color("#ff2b2b")
				_screen_mat2.emission_energy_multiplier = 1.0 + absf(sin(_blink2 * 8.0)) * 2.5
			else:
				_screen_mat2.emission = Color("#c86bff")
				_screen_mat2.emission_energy_multiplier = 1.0 + absf(sin(_blink2 * 1.7)) * 0.7
		_tick += delta
		if _tick < 0.7:
			return
		_tick = 0.0
		var id := str(in_slot["id"])
		if id == "" or int(in_slot["n"]) <= 0:
			return
		_route = 0
		var env := {"funnel": id, "port": 0}
		var funcs := {
			"sort": func(args: Array):
				if args.size() >= 2:
					_route = int(MiniLua._numv(args[1]))
				return 0,
			"print": func(args: Array): cprint(args); return 0,
			"clear": func(_a: Array): cclear(); return 0,
			"input": func(_a: Array): return console_input,
		}
		var res := MiniLua.run(script_src, env, funcs)
		if res.has("err"):
			last_err = res["err"]
			return
		last_err = ""
		if _route >= 1:
			# find the funnel wired to that PORT number
			for k in funnels_out.size():
				var pt: int = int(funnel_ports[k]) if k < funnel_ports.size() else k + 1
				if pt != _route:
					continue
				var dst = funnels_out[k]
				if is_instance_valid(dst) and dst.accept_item(id):
					in_slot["n"] = int(in_slot["n"]) - 1
					if int(in_slot["n"]) <= 0:
						in_slot = {"id": "", "n": 0}
				break

	func info_text() -> String:
		var e := ("\nERR: " + last_err) if last_err != "" else ""
		return "holding: %s\nfunnel ports wired: %d%s" % [Inventory.slot_text(in_slot), funnels_out.size(), e]

	func actions() -> Array:
		return [
			["Edit Code", func() -> void:
				var ui := get_tree().get_first_node_in_group("code_ui")
				if ui and ui.has_method("open_for"):
					ui.open_for(self)],
		]

	func take_output_from_in() -> void:
		if str(in_slot["id"]) == "":
			Sfx.play("denied")
			return
		Inventory.add_res(str(in_slot["id"]), int(in_slot["n"]))
		in_slot = {"id": "", "n": 0}
		Sfx.play("coin")
