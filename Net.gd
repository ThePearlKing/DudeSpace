extends Node
## Autoload "Net". LAN multiplayer core: host/join over ENet, chat,
## player presence and position sync. v1 syncs PLAYERS and CHAT -- each
## peer still runs its own copy of the world (world-object sync later).

signal chat_received(from_name: String, text: String)
signal peer_joined(id: int, pname: String)
signal peer_left(id: int)
signal pos_update(id: int, pos: Vector3, up: Vector3, fwd: Vector3, state: Dictionary)
signal peer_punch(id: int)
signal session_changed
signal server_found(ip: String, info: Dictionary)
signal world_snapshot_received(snap: Dictionary, blob: Dictionary)
signal peer_identity(id: int)

const DEFAULT_PORT := 24545
const DISCOVERY_PORT := 24546   # Minecraft-style: hosts announce on the LAN
const DISCOVERY_ADDR := "224.0.2.61"   # multicast: loops back locally too

var active: bool = false
var is_host: bool = false
var guest_name: String = ""          # chosen on the join screen
var guest_paint: PackedByteArray = PackedByteArray()   # guest face, in memory only
var player_names: Dictionary = {}    # peer id -> display name
var player_infos: Dictionary = {}    # peer id -> {character, equip, paint}
var player_pos: Dictionary = {}      # peer id -> last known Vector3
var player_ups: Dictionary = {}      # peer id -> last known up axis
var host_settings: Dictionary = {}   # host's rules, mirrored to guests
var applying_remote: bool = false    # guard: mirrored events don't re-broadcast
var remote_owner: String = ""        # who placed the thing being mirrored
var _blob_t: float = 5.0
var _ident_t: float = 3.0
var _last_equip: String = ""

var _sync_t: float = 0.0
var _announce: PacketPeerUDP    # host: shouts presence onto the LAN
var _announce_t: float = 0.0
var _listen: PacketPeerUDP      # join screen: hears those shouts

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_lost)
	multiplayer.connection_failed.connect(_on_server_lost)

func my_name() -> String:
	# the settings username wins everywhere; save name is the fallback
	if Settings.username.strip_edges() != "":
		return Settings.username.strip_edges()
	if guest_name.strip_edges() != "":
		return guest_name.strip_edges()
	var n := str(Save.save_name).strip_edges()
	return n if n != "" else "Dude"

## What this player looks like, for everyone else's benefit.
func my_identity() -> Dictionary:
	var paint := guest_paint
	if paint.is_empty() and not Save.ephemeral:
		var pp := Save.paint_path(Save.current_slot)
		if FileAccess.file_exists(pp):
			paint = FileAccess.get_file_as_bytes(pp)
	return {"character": Save.character, "equip": Inventory.equip, "paint": paint}

## Start listening. Returns "" on success, else an error message.
func host(settings: Dictionary) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(settings.get("port", DEFAULT_PORT)), 16)
	if err != OK:
		return "port %d unavailable (error %d)" % [int(settings.get("port", DEFAULT_PORT)), err]
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	host_settings = settings.duplicate()
	player_names = {1: my_name()}
	_announce = PacketPeerUDP.new()
	_announce.set_broadcast_enabled(true)
	_announce.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	session_changed.emit()
	chat_received.emit("SERVER", "opened to LAN on port %d" % int(settings.get("port", DEFAULT_PORT)))
	return ""

func join(ip: String, port: int) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return "could not connect to %s:%d (error %d)" % [ip, port, err]
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	session_changed.emit()
	return ""

func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _announce:
		_announce.close()
		_announce = null
	var was := active
	active = false
	is_host = false
	player_names.clear()
	host_settings = {}
	if was:
		session_changed.emit()

# ------------------------------------------------- LAN discovery (MC-style)

## Join screen calls this: start hearing host announcements.
func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	_listen.bind(DISCOVERY_PORT)
	# multicast membership on every interface -- broadcast alone does not
	# loop back to listeners on the SAME machine
	for iface in IP.get_local_interfaces():
		_listen.join_multicast_group(DISCOVERY_ADDR, str(iface.get("name", "")))

func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null

# ------------------------------------------------------------------ chat

func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	if not active:
		# singleplayer: you, talking to yourself. valid lifestyle.
		chat_received.emit(my_name(), text)
		return
	if not is_host and not bool(host_settings.get("allow_chat", true)):
		chat_received.emit("SERVER", "chat is disabled on this server")
		return
	_chat.rpc(my_name(), text)
	chat_received.emit(my_name(), text)

@rpc("any_peer", "reliable")
func _chat(pname: String, text: String) -> void:
	if is_host and not bool(host_settings.get("allow_chat", true)):
		return   # host drops guest chat when the rule says so
	chat_received.emit(pname, text)

# -------------------------------------------------------------- presence

func _on_peer_connected(id: int) -> void:
	_hello.rpc_id(id, my_name(), my_identity())
	if is_host:
		_settings_sync.rpc_id(id, host_settings)

func _on_connected_to_server() -> void:
	# joined the server: ask the host for its world
	_req_world.rpc_id(1, my_name())

@rpc("any_peer", "reliable")
func _hello(pname: String, ident: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	player_names[id] = pname
	player_infos[id] = ident
	peer_joined.emit(id, pname)
	peer_identity.emit(id)
	chat_received.emit("SERVER", "%s joined" % pname)

## Armor changes etc: re-announce appearance to everyone.
func refresh_identity() -> void:
	if active:
		_ident_update.rpc(my_identity())

@rpc("any_peer", "reliable")
func _ident_update(ident: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	player_infos[id] = ident
	peer_identity.emit(id)

@rpc("authority", "reliable")
func _settings_sync(s: Dictionary) -> void:
	host_settings = s

func push_settings() -> void:
	if is_host and active:
		_settings_sync.rpc(host_settings)

func _on_peer_disconnected(id: int) -> void:
	var pname := str(player_names.get(id, "someone"))
	player_names.erase(id)
	player_infos.erase(id)
	player_pos.erase(id)
	peer_left.emit(id)
	chat_received.emit("SERVER", "%s left" % pname)

func _on_server_lost() -> void:
	leave()
	chat_received.emit("SERVER", "connection lost")

# ---------------------------------------------- the server's world (host)

## Guest asks; host answers with the live world + that player's saved data.
@rpc("any_peer", "reliable")
func _req_world(pname: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	player_names[id] = pname
	var m = get_tree().current_scene
	var snap := {
		"world": m.collect_world() if m and m.has_method("collect_world") else [],
		"playtime": Game.playtime,
		"spawn": [Game.spawn_pos.x, Game.spawn_pos.y, Game.spawn_pos.z],
		"spawn_up": [Game.spawn_up.x, Game.spawn_up.y, Game.spawn_up.z],
		"wseed": Game.world_seed,
	}
	_world_snapshot.rpc_id(id, snap, Save.guest_blob(pname))

@rpc("authority", "reliable")
func _world_snapshot(snap: Dictionary, blob: Dictionary) -> void:
	world_snapshot_received.emit(snap, blob)

# ------------------------------------------- live world events (mirrored)

## Grief rules: your own stuff always breaks; other people's only if
## the host allows it.
func can_break(owner: String) -> bool:
	if not active or owner == "" or owner == my_name():
		return true
	return bool(host_settings.get("break_others", true))

func broadcast_place(pid: String, pos: Vector3, up: Vector3) -> void:
	if active and not applying_remote:
		_ev_place.rpc(pid, pos, up)

@rpc("any_peer", "reliable")
func _ev_place(pid: String, pos: Vector3, up: Vector3) -> void:
	var m = get_tree().current_scene
	if m and m.has_method("net_place"):
		applying_remote = true
		var sender := multiplayer.get_remote_sender_id()
		remote_owner = str(player_names.get(sender, ""))
		m.net_place(pid, pos, up)
		applying_remote = false

func broadcast_remove(pos: Vector3) -> void:
	if active and not applying_remote:
		_ev_remove.rpc(pos)

@rpc("any_peer", "reliable")
func _ev_remove(pos: Vector3) -> void:
	var m = get_tree().current_scene
	if m and m.has_method("net_remove"):
		applying_remote = true
		m.net_remove(pos)
		applying_remote = false

func broadcast_break(pos: Vector3) -> void:
	if active and not applying_remote:
		_ev_break.rpc(pos)

@rpc("any_peer", "reliable")
func _ev_break(pos: Vector3) -> void:
	var m = get_tree().current_scene
	if m and m.has_method("net_break"):
		applying_remote = true
		m.net_break(pos)
		applying_remote = false

# ----------------------------------------------------------- PvP damage

## Shot another player's avatar. Only lands if the host allows it.
## silent = splash damage (grenades, meltdowns): no chat nag when FF is off.
func hit_player(peer_id: int, dmg: float, silent: bool = false) -> void:
	if not active:
		return
	if not bool(host_settings.get("friendly_fire", false)):
		if not silent:
			chat_received.emit("SERVER", "friendly fire is off")
		return
	_take_hit.rpc_id(peer_id, dmg)

@rpc("any_peer", "reliable")
func _take_hit(dmg: float) -> void:
	# victim double-checks the rule (host is authoritative via settings sync)
	if not bool(host_settings.get("friendly_fire", false)):
		return
	var attacker := str(player_names.get(multiplayer.get_remote_sender_id(), "someone"))
	Game.hurt(dmg, false, attacker)   # the death screen names your killer
	if Game.dead:
		chat_received.emit("SERVER", "%s was slain by %s" % [my_name(), attacker])

## A player shot a WTH studio orb: everyone plays the same ping,
## jitter, and scripted complaint (the shooter picked the words).
func wth_hit(idx: int, plan: Array) -> void:
	if active:
		_wth_hit_rpc.rpc(idx, plan)

@rpc("any_peer", "reliable")
func _wth_hit_rpc(idx: int, plan: Array) -> void:
	var st = get_tree().get_first_node_in_group("wth_studio")
	if st != null and st.has_method("orb_hit_synced"):
		st.orb_hit_synced(idx, plan)

## Where a peer's avatar stands right now (null if not rendered here).
func avatar_position(peer_id: int):
	var cs = get_tree().current_scene
	if cs == null:
		return null
	var av = cs.get("_remote_avatars")
	if av is Dictionary and av.has(peer_id):
		var rec = av[peer_id]
		if rec is Dictionary and is_instance_valid(rec.get("root")):
			return (rec["root"] as Node3D).global_position
	return null

# --------------------------- per-player data, stored on the host's save

@rpc("any_peer", "reliable")
func _store_blob(pname: String, blob: Dictionary) -> void:
	if is_host:
		Save.store_guest_blob(pname, blob)

## Guests obey the host's cheat rule; the host always may.
func cheats_allowed() -> bool:
	if not active or is_host:
		return true
	return bool(host_settings.get("allow_cheats", false))

# ----------------------------------------------- player position sync

func _process(delta: float) -> void:
	# join screen: surface every host shouting on the LAN
	if _listen:
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var parsed = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary:
				server_found.emit(ip, parsed)
	if not active:
		return
	# host: announce this world every 1.5s, Minecraft-LAN style
	if is_host and _announce:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = 1.5
			var info := {
				"world": my_name(), "port": int(host_settings.get("port", DEFAULT_PORT)),
				"players": player_names.size(),
			}
			var pkt := JSON.stringify(info).to_utf8_buffer()
			# shout via multicast (works locally) AND broadcast (older LANs)
			_announce.set_dest_address(DISCOVERY_ADDR, DISCOVERY_PORT)
			_announce.put_packet(pkt)
			_announce.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_announce.put_packet(pkt)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.1   # 10 Hz
		var p = get_tree().get_first_node_in_group("player")
		if p:
			var state := {"dead": Game.dead, "jet": Inventory.jet_on}
			if Game.mode == Game.Mode.IN_ROCKET:
				for r in get_tree().get_nodes_in_group("rocket"):
					if r is Rocket and r.piloted:
						# in flight: ship the ROCKET's attitude, not the body's
						state["rocket"] = true
						state["mk2"] = r.mk2
						_pos.rpc(r.global_position, r.global_transform.basis.y,
							-r.global_transform.basis.z, state)
						return
			_pos.rpc(p.global_position, p.global_transform.basis.y,
				-p.global_transform.basis.z, state)
	# armor changed? everyone gets the new look (checked every 3s)
	_ident_t -= delta
	if _ident_t <= 0.0:
		_ident_t = 3.0
		var e := JSON.stringify(Inventory.equip)
		if e != _last_equip:
			_last_equip = e
			refresh_identity()
	# guests: push our player data to the host every 5s (persists by
	# name -- position included, so rejoining puts you back where you were)
	if not is_host:
		_blob_t -= delta
		if _blob_t <= 0.0:
			_blob_t = 5.0
			_store_blob.rpc_id(1, my_name(), Save.build_player_blob())

@rpc("any_peer", "unreliable")
func _pos(pos: Vector3, up: Vector3, fwd: Vector3, state: Dictionary = {}) -> void:
	var id := multiplayer.get_remote_sender_id()
	if OS.get_environment("CTD_NET") != "" and not player_pos.has(id):
		print("NETTEST first pos from peer ", id, " at ", pos)
	player_pos[id] = pos
	player_ups[id] = up
	pos_update.emit(id, pos, up, fwd, state)

## A swing is half the fun -- everyone should see it land.
func punch() -> void:
	if active:
		_punch.rpc()

@rpc("any_peer", "unreliable")
func _punch() -> void:
	peer_punch.emit(multiplayer.get_remote_sender_id())
