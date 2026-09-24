class_name Net
extends Node
## Multiplayer transport over ENet (UDP, so it works through a playit.gg tunnel). One player
## hosts: their game runs the MatchServer and plays on it like everyone else, just without the
## trip over the network. Others join by address. Port of the web game's src/net.js (client side)
## plus the socket half of server/server.js.
##
## Client side: every sim tick main.gd queues its input here; unacknowledged inputs are sent every
## other tick (a lost packet is covered by the next one). Snapshots come back 30 times a second:
## other players are drawn 100 ms in the past, blended between two snapshots, and our own full
## movement state is handed to main.gd to correct its prediction.
##
## The node lives under the scene tree's root, not in the game scene, so the connection survives
## reloading into the host's map. Net.instance is the live one.

signal joined(welcome: Dictionary) # connected and in the match (welcome: id, map, spawn)
signal failed(reason: String) # couldn't connect / refused
signal left(reason: String) # connection lost or closed by the host

const PROTOCOL := 1 # bump when the messages change: older clients get a clear "update" message
const DEFAULT_PORT := 7777
const INTERP_DELAY := 100.0 # ms other players are shown in the past (must exceed the snapshot gap)
const HOST_INTERP_DELAY := 45.0 # the host gets snapshots with no network in between
const SEND_EVERY := 2 # physics ticks between input packets (60 per second)

static var instance: Net

var server: MatchServer # set when hosting
var local_player := true # hosting: does this game also play? (false = dedicated server)
var my_id := 0
var connected := false
var map_id := ""
var welcome := {} # the last welcome (id, map, spawn, roster)
var ping := 0.0 # ms

# client side
var remotes := {} # id -> {name, color, buf: [[at_ms, player dict]]}
var roster := {} # id -> {name, color}
var players: Array = [] # latest public player list (scoreboard)
var me: Dictionary = {} # our latest authoritative state: {seq, respawn_in, state}
var me_fresh := false # a new `me` arrived that hasn't been applied yet
var proj: Array = [] # every live projectile on the server (latest snapshot)
var proj_fresh := false
var events: Array = [] # gameplay events not yet handled by the game
var _seq := 0
var _unacked: Array = [] # [[seq, view_tick, Cmd]]
var _timeline: Array = [] # [[at_ms, tick]] of received snapshots (for lag compensation)
var _send_tick := 0
var _ping_t := 0.0
var _hello := {} # what to say once the connection is up
var _peer: ENetMultiplayerPeer


func _ready() -> void:
	process_physics_priority = 100 # after main.gd's tick, so the host's own input is in first
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(func() -> void: _drop("The host closed the match."))


## Quitting mid-match hangs up properly, so the host drops us at once instead of timing out.
func _exit_tree() -> void:
	leave()


## The shared one, created on first use under the tree's root.
static func get_instance(tree: SceneTree) -> Net:
	if instance == null or not is_instance_valid(instance):
		instance = Net.new()
		instance.name = "Net"
		tree.root.add_child(instance)
	return instance


## "host:port", "host" (default port), "ws://host:port"... -> [host, port], or [] if unusable.
static func parse_address(raw: String) -> Array:
	var s := raw.strip_edges()
	for scheme in ["udp://", "ws://", "wss://", "http://", "https://"]:
		if s.begins_with(scheme):
			s = s.substr(scheme.length())
	s = s.trim_suffix("/")
	if s == "":
		return []
	var port := DEFAULT_PORT
	var colon := s.rfind(":")
	if colon > 0 and s.count(":") == 1:
		var p := s.substr(colon + 1)
		if not p.is_valid_int() or int(p) <= 0 or int(p) > 65535:
			return []
		port = int(p)
		s = s.substr(0, colon)
	return [s, port]


## A fingerprint of a map's collision, so a client with a different copy of the map (an edited
## one) gets told instead of rubber-banding everywhere.
static func map_checksum(m: MapData) -> int:
	var parts := PackedStringArray()
	for b in m.boxes:
		parts.append("%s,%s,%s,%s,%s,%s,%d,%d" % [b.min_x, b.min_y, b.min_z, b.max_x, b.max_y, b.max_z, b.ramp_axis, b.ramp_dir])
	for p in m.pads:
		parts.append("%s,%s,%s,%s" % [p.x, p.y, p.z, p.radius])
	return ";".join(parts).hash()


# ---------- start / stop ----------

## Host a match on `map`. The host's own game joins it straight away (unless dedicated).
func host(port: int, map: String, m: MapData, player_name: String, loadout: Dictionary, play := true) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MatchServer.MAX_PLAYERS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	server = MatchServer.new(m)
	server.set_meta("checksum", map_checksum(m))
	map_id = map
	local_player = play
	if play:
		var spawn := server.add_player(1, player_name, loadout)
		_welcome_local({"id": 1, "map": map, "spawn": spawn, "tick": server.tick, "roster": server.roster()})
	return OK


## Join a match at "host:port". Answers with `joined` or `failed`.
func join(address: String, player_name: String, loadout: Dictionary, checksums: Dictionary) -> Error:
	leave()
	var a := parse_address(address)
	if a.is_empty():
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(a[0], a[1])
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	_hello = {"name": player_name, "loadout": loadout, "protocol": PROTOCOL, "checksums": checksums}
	return OK


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	server = null
	connected = false
	my_id = 0
	map_id = ""
	remotes.clear()
	roster.clear()
	players = []
	me = {}
	me_fresh = false
	proj = []
	events = []
	_unacked = []
	_timeline = []
	_seq = 0


func is_host() -> bool:
	return server != null


# ---------- client: inputs ----------

## Called once per sim tick with the input the local player just used. Returns its sequence number.
func queue_cmd(c: Cmd) -> int:
	_seq += 1
	var e := [_seq, view_tick(), c]
	if is_host():
		server.receive(1, [e]) # no network in between
	else:
		_unacked.append(e)
		if _unacked.size() > 120:
			_unacked = _unacked.slice(_unacked.size() - 120)
	return _seq


## The server tick other players are being drawn at right now (they're shown INTERP_DELAY in the
## past). Sent with every input so the server can rewind hitboxes to match what you saw.
func view_tick(now := -1.0) -> int:
	var t: float = (now if now >= 0 else float(Time.get_ticks_msec())) - _delay()
	var tl := _timeline
	if tl.is_empty():
		return 0
	if t <= tl[0][0]:
		return tl[0][1]
	for i in range(tl.size() - 1, 0, -1):
		var a: Array = tl[i - 1]
		var b: Array = tl[i]
		if t >= a[0] and t <= b[0]:
			return roundi(a[1] + (b[1] - a[1]) * ((t - a[0]) / maxf(1.0, b[0] - a[0])))
	return tl[tl.size() - 1][1]


func _delay() -> float:
	return HOST_INTERP_DELAY if is_host() else INTERP_DELAY


func take_events() -> Array:
	var e := events
	events = []
	return e


## Where to draw a remote player right now: INTERP_DELAY in the past, blended between the two
## snapshots around that moment. null if we know nothing yet.
func sample(r: Dictionary, now := -1.0) -> Variant:
	var t: float = (now if now >= 0 else float(Time.get_ticks_msec())) - _delay()
	var b: Array = r.buf
	if b.is_empty():
		return null
	if t <= b[0][0]:
		return b[0][1]
	for i in range(b.size() - 1, 0, -1):
		var a: Array = b[i - 1]
		var c: Array = b[i]
		if t >= a[0] and t <= c[0]:
			var k: float = (t - a[0]) / maxf(1.0, c[0] - a[0])
			var pa: Dictionary = a[1]
			var pc: Dictionary = c[1]
			# Don't blend across a respawn (it would slide the bean across the map).
			if Vector2(pc.x - pa.x, pc.z - pa.z).length() > 8:
				return pc
			var out := pc.duplicate()
			out.x = lerpf(pa.x, pc.x, k)
			out.y = lerpf(pa.y, pc.y, k)
			out.z = lerpf(pa.z, pc.z, k)
			out.yaw = lerp_angle(pa.yaw, pc.yaw, k)
			out.pitch = lerpf(pa.pitch, pc.pitch, k)
			return out
	return b[b.size() - 1][1] # nothing newer yet: hold the latest


# ---------- the loop ----------

func _physics_process(_delta: float) -> void:
	if _peer == null:
		return
	if server:
		_server_tick()
	elif connected:
		_send_tick += 1
		if _send_tick >= SEND_EVERY and not _unacked.is_empty():
			_send_tick = 0
			_inputs.rpc_id(1, NetCodec.pack_cmds(_unacked))
		_ping_t += Cfg.TICK_DT
		if _ping_t >= 1.0:
			_ping_t = 0.0
			_ping.rpc_id(1, Time.get_ticks_msec())


func _server_tick() -> void:
	server.step()
	var evs := server.take_events()
	var roster_changed := false
	for e: Dictionary in evs:
		if e.type == "join" or e.type == "leave":
			roster_changed = true
	if roster_changed:
		evs.append({"type": "roster", "roster": server.roster()})
	if not evs.is_empty():
		for id: int in server.peers:
			if id != 1 and multiplayer.get_peers().has(id):
				_events.rpc_id(id, evs) # reliable
		if local_player:
			_on_events(evs)
	if server.tick % MatchServer.SNAP_EVERY == 0:
		var pl := server.public_players()
		var pj := server.public_projectiles()
		for id: int in server.peers:
			var data := NetCodec.pack_snapshot(server.snapshot_for(id, pl, pj))
			if id == 1:
				_on_snapshot(data)
			elif multiplayer.get_peers().has(id):
				_snap.rpc_id(id, data)


# ---------- connection events ----------

func _on_connected() -> void:
	_quick_timeout(1)
	_hello_rpc.rpc_id(1, _hello)


func _on_peer_connected(id: int) -> void:
	_quick_timeout(id) # they introduce themselves with _hello_rpc


## Notice a vanished peer (crash, pulled cable) in seconds instead of ENet's default half minute.
func _quick_timeout(id: int) -> void:
	if _peer == null:
		return
	var p := _peer.get_peer(id)
	if p:
		p.set_timeout(32, 4000, 8000)


func _on_peer_disconnected(id: int) -> void:
	if server:
		server.remove_player(id)


func _fail(reason: String) -> void:
	leave()
	failed.emit(reason)


func _drop(reason: String) -> void:
	var was := connected
	leave()
	if was:
		left.emit(reason)
	else:
		failed.emit(reason)


func _welcome_local(w: Dictionary) -> void:
	welcome = w
	my_id = w.id
	map_id = w.map
	connected = true
	roster.clear()
	for r: Dictionary in w.roster:
		roster[r.id] = {"name": r.name, "color": r.color}
	joined.emit.call_deferred(w)


# ---------- messages ----------

@rpc("any_peer", "call_remote", "reliable")
func _hello_rpc(hello: Dictionary) -> void:
	if server == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var why := ""
	if int(hello.get("protocol", 0)) != PROTOCOL:
		why = "The host is on a different version of the game. Update so you both have the same one."
	elif server.is_full():
		why = "That match is full (%d players)." % MatchServer.MAX_PLAYERS
	elif server.peers.has(id):
		return
	else:
		var sums: Dictionary = hello.get("checksums", {})
		if not sums.has(map_id):
			why = "The host is playing a map you don't have (%s)." % map_id
		elif int(sums[map_id]) != int(server.get_meta("checksum")):
			why = "Your copy of the map \"%s\" is different from the host's. Get the same version of the game." % map_id
	if why != "":
		_refused.rpc_id(id, why)
		# Let the message go out, then hang up on them.
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if _peer and multiplayer.get_peers().has(id):
				_peer.disconnect_peer(id))
		return
	var spawn := server.add_player(id, str(hello.get("name", "")), hello.get("loadout", {}) as Dictionary)
	_welcome.rpc_id(id, {"id": id, "map": map_id, "spawn": spawn, "tick": server.tick, "roster": server.roster()})


@rpc("authority", "call_remote", "reliable")
func _welcome(w: Dictionary) -> void:
	_welcome_local(w)


@rpc("authority", "call_remote", "reliable")
func _refused(why: String) -> void:
	_fail(why)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _inputs(data: PackedByteArray) -> void:
	if server:
		server.receive(multiplayer.get_remote_sender_id(), NetCodec.unpack_cmds(data))


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snap(data: PackedByteArray) -> void:
	_on_snapshot(data)


@rpc("authority", "call_remote", "reliable")
func _events(evs: Array) -> void:
	_on_events(evs)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(t: int) -> void:
	if server:
		_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("authority", "call_remote", "unreliable")
func _pong(t: int) -> void:
	ping = Time.get_ticks_msec() - t


func _on_events(evs: Array) -> void:
	if not connected:
		return
	for e: Dictionary in evs:
		if e.type == "roster":
			roster.clear()
			for r: Dictionary in e.roster:
				roster[r.id] = {"name": r.name, "color": r.color}
			continue
		events.append(e)


func _on_snapshot(data: PackedByteArray) -> void:
	if not connected:
		return
	var snap := NetCodec.unpack_snapshot(data)
	var at := float(Time.get_ticks_msec())
	_timeline.append([at, snap.tick])
	if _timeline.size() > 20:
		_timeline.pop_front()
	me = snap.me
	me_fresh = true
	var acked: int = me.seq
	while not _unacked.is_empty() and _unacked[0][0] <= acked:
		_unacked.pop_front()
	proj = snap.proj
	proj_fresh = true
	players = snap.players
	var seen := {}
	for p: Dictionary in snap.players:
		if p.id == my_id:
			continue
		seen[p.id] = true
		var r: Dictionary = remotes.get(p.id, {})
		if r.is_empty():
			r = {"id": p.id, "buf": []}
			remotes[p.id] = r
		var info: Dictionary = roster.get(p.id, {"name": "Bean", "color": Color.WHITE})
		r.name = info.name
		r.color = info.color
		(r.buf as Array).append([at, p])
		if r.buf.size() > 20:
			(r.buf as Array).pop_front()
	for id: int in remotes.keys():
		if not seen.has(id):
			remotes.erase(id)
