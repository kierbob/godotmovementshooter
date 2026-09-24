class_name MatchServer
extends RefCounted
## The multiplayer match itself: every player's movement and combat, run on the host at 120
## ticks/s with the same PlayerSim and Combat code everyone's screen uses (a port of the web
## game's server/server.js). Net feeds it inputs and sends out what it makes (snapshots and
## events); it never touches the network, so tests can drive it directly.
##
## Each player is stepped exactly once per input they sent, the same steps their own screen
## predicted, so prediction and server agree exactly. Shots are checked against where everyone
## else was on the shooter's screen (lag compensation, up to 250 ms back).

const MAX_PLAYERS := 8
const SNAP_EVERY := 4 # ticks between snapshots (30 per second)
const MAX_QUEUE := 12 # buffered inputs per player before we skip ahead
const HISTORY := 128 # ticks of positions kept for lag compensation (~1 s)
const MAX_REWIND := 30 # never rewind more than 250 ms
const RESPAWN_DELAY := 2.5
const SPAWN_PROTECTION := 1.5
const REGEN_DELAY := 3.0
const REGEN_RATE := 30.0
const COLORS := [Color("4fc3ff"), Color("ff6b6b"), Color("7ee787"), Color("ffd35a"), Color("c792ea"),
	Color("ff9e3d"), Color("5ce1e6"), Color("ff7eb6")]


class Peer:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var sim: PlayerSim
	var combat: Combat
	var target: Combat.Target # this player's hitboxes, as everyone else's Combat sees them
	var loadout := {}
	var queue: Array = [] # [[seq, view_tick, Cmd]] waiting to be applied
	var last_seq := 0 # newest input applied
	var queued_seq := 0 # newest input received
	var budget := 0.0
	var last_cmd := Cmd.new()
	var history: Array = [] # ring of [tick, Vector3]
	var kills := 0
	var deaths := 0
	var respawn_t := 0.0


var map: MapData
var peers := {} # id -> Peer, in join order
var tick := 0
var events: Array = [] # since the last take_events(): sent to everyone, reliably


func _init(m: MapData) -> void:
	map = m


func is_full() -> bool:
	return peers.size() >= MAX_PLAYERS


static func clean_name(raw: String) -> String:
	var ok := ""
	for ch in raw.strip_edges():
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in " -.!?_":
			ok += ch
	ok = " ".join(ok.split(" ", false)).substr(0, 16)
	return ok if ok != "" else "Bean"


static func clean_loadout(lo: Dictionary) -> Dictionary:
	var out := Items.DEFAULT_LOADOUT.duplicate()
	for slot: String in out:
		var id: String = str(lo.get(slot, ""))
		if Items.is_valid(slot, id):
			out[slot] = id
	return out


## Adds a player and spawns them. Returns their spawn point ({x, y, z, yaw}).
func add_player(id: int, player_name: String, loadout: Dictionary, color := Color(0, 0, 0, 0)) -> Dictionary:
	var c := Peer.new()
	c.id = id
	c.name = clean_name(player_name)
	c.color = color if color.a > 0 else _free_color() # their character's color, if given
	c.loadout = clean_loadout(loadout)
	c.sim = PlayerSim.new()
	c.sim.quiet = true # nobody reads the server's movement log
	c.combat = Combat.new(map.boxes, [])
	c.target = Combat.Target.new()
	c.target.id = id
	c.target.kind = "player"
	c.target.name = c.name
	c.target.body = c.sim
	c.target.max_hp = c.sim.max_hp
	c.history.resize(HISTORY)
	peers[id] = c
	var s := _spawn(c)
	events.append({"type": "join", "id": id, "name": c.name})
	return s


func remove_player(id: int) -> void:
	var c: Peer = peers.get(id)
	if c == null:
		return
	peers.erase(id)
	events.append({"type": "leave", "id": id, "name": c.name})


## Everyone's name and color (sent reliably whenever someone joins or leaves).
func roster() -> Array:
	var out := []
	for c: Peer in peers.values():
		out.append({"id": c.id, "name": c.name, "color": c.color})
	return out


## Inputs from a player: [[seq, view_tick, Cmd], ...]. Old or repeated ones are ignored (clients
## resend everything the server hasn't acknowledged yet, in case a packet was lost).
func receive(id: int, cmds: Array) -> void:
	var c: Peer = peers.get(id)
	if c == null:
		return
	for e: Array in cmds:
		if e[0] <= c.queued_seq:
			continue
		c.queued_seq = e[0]
		c.queue.append(e)
	# A client that fell far behind (hitch, alt-tab) skips ahead instead of lagging forever.
	if c.queue.size() > MAX_QUEUE:
		c.queue = c.queue.slice(c.queue.size() - MAX_QUEUE)


func step() -> void:
	tick += 1
	var all: Array = peers.values()
	for c: Peer in all:
		_sync_target(c)
	for c: Peer in all:
		var p := c.sim
		# One input per server tick on average (no speed hacks by sending faster), with a little
		# slack to catch up after a network hiccup.
		c.budget = minf(c.budget + 1, MAX_QUEUE)
		if p.dead:
			# Swallow inputs while dead so the client's correction stays in step.
			for e: Array in c.queue:
				c.last_seq = e[0]
			c.queue.clear()
			c.respawn_t -= Cfg.TICK_DT
			if c.respawn_t <= 0:
				var s := _spawn(c)
				events.append({"type": "respawn", "id": c.id, "yaw": s.yaw})
			continue
		p.invuln = maxf(0.0, p.invuln - Cfg.TICK_DT)
		p.regen_delay = maxf(0.0, p.regen_delay - Cfg.TICK_DT)
		if p.regen_delay == 0 and p.hp < p.max_hp:
			p.hp = minf(p.max_hp, p.hp + REGEN_RATE * Cfg.TICK_DT)
			c.target.hp = p.hp
		while not c.queue.is_empty() and c.budget >= 1 and not p.dead:
			var e: Array = c.queue.pop_front()
			c.budget -= 1
			c.last_seq = e[0]
			var cmd: Cmd = e[2]
			c.last_cmd = cmd
			# Combat first (so knockback applies this step), with everyone else put back where
			# this player saw them when they pressed the button.
			var others: Array[Combat.Target] = []
			for o: Peer in all:
				if o != c:
					others.append(o.target)
			c.combat.targets = others
			var saved := _rewind(c, e[1])
			c.combat.tick(p, cmd, Cfg.TICK_DT)
			for s: Array in saved:
				(s[0] as Combat.Target).pos = s[1]
			_collect(c)
			p.step(cmd, map, Cfg.TICK_DT)
			if p.py < -30:
				# Fell out: back to a spawn point, guns untouched (the player's screen keeps
				# predicting their gun, and a surprise reload there would put the two out of step).
				_spawn(c, false)
	for c: Peer in all:
		c.history[tick % HISTORY] = [tick, Vector3(c.sim.px, c.sim.py, c.sim.pz)]


func take_events() -> Array:
	var e := events
	events = []
	return e


## What player `id` gets in a snapshot: everyone's public state, every live projectile, and their
## own full movement state for exact prediction correction.
func snapshot_for(id: int, players: Array, proj: Array) -> Dictionary:
	var c: Peer = peers[id]
	return {
		"tick": tick,
		"me": {"seq": c.last_seq, "respawn_in": maxf(0.0, c.respawn_t) if c.sim.dead else 0.0, "state": c.sim.save_state()},
		"players": players,
		"proj": proj,
	}


func public_players() -> Array:
	var out := []
	for c: Peer in peers.values():
		var p := c.sim
		var flags := 0
		if p.crouching:
			flags |= NetCodec.F_CROUCH
		if p.sliding:
			flags |= NetCodec.F_SLIDE
		if p.grounded:
			flags |= NetCodec.F_GROUNDED
		if p.dead:
			flags |= NetCodec.F_DEAD
		if p.invuln > 0:
			flags |= NetCodec.F_PROTECTED
		out.append({"id": c.id, "x": p.px, "y": p.py, "z": p.pz, "yaw": c.last_cmd.yaw, "pitch": c.last_cmd.pitch,
			"flags": flags, "weapon": c.combat.weapon().id, "hp": p.hp, "kills": c.kills, "deaths": c.deaths})
	return out


func public_projectiles() -> Array:
	var out := []
	for c: Peer in peers.values():
		for pr in c.combat.projectiles:
			out.append({"owner": c.id, "id": pr.id, "kind": pr.kind, "stuck": pr.stuck, "pos": pr.pos, "vel": pr.vel})
	return out


# ---------- internals ----------

func _free_color() -> Color:
	var used := {}
	for c: Peer in peers.values():
		used[c.color] = true
	for col: Color in COLORS:
		if not used.has(col):
			return col
	return COLORS[peers.size() % COLORS.size()]


## Farthest spawn from everyone alive (random among the best few so it isn't predictable).
func _pick_spawn(exclude: Peer) -> Dictionary:
	var others: Array[Vector3] = []
	for c: Peer in peers.values():
		if c != exclude and not c.sim.dead:
			others.append(Vector3(c.sim.px, 0, c.sim.pz))
	var scored := []
	for s: Dictionary in map.spawns:
		var d := randf()
		if not others.is_empty():
			d = INF
			for o in others:
				d = minf(d, Vector2(o.x - float(s.x), o.z - float(s.z)).length())
		scored.append([d, s])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored[randi() % mini(3, scored.size())][1]


func _spawn(c: Peer, fresh_loadout := true) -> Dictionary:
	var s := _pick_spawn(c)
	var p := c.sim
	p.respawn(float(s.x), float(s.y), float(s.z))
	p.hp = p.max_hp
	p.dead = false
	p.invuln = SPAWN_PROTECTION
	p.regen_delay = 0.0
	c.target.hp = c.target.max_hp
	c.target.dead = false
	if fresh_loadout:
		c.combat.set_loadout(c.loadout) # fresh ammo and ability
	c.last_cmd = Cmd.new()
	c.last_cmd.yaw = float(s.get("yaw", 0.0))
	c.respawn_t = 0.0
	return {"x": float(s.x), "y": float(s.y), "z": float(s.z), "yaw": float(s.get("yaw", 0.0))}


func _sync_target(c: Peer) -> void:
	c.target.pos = Vector3(c.sim.px, c.sim.py, c.sim.pz)
	c.target.dead = c.sim.dead
	c.target.hp = c.sim.hp


## Moves everyone but the shooter back to where they were at server tick `vt`. Returns what to
## put back: [[target, pos], ...].
func _rewind(shooter: Peer, vt: int) -> Array:
	var back := maxi(tick - MAX_REWIND, mini(tick, vt))
	var saved := []
	for o: Peer in peers.values():
		if o == shooter:
			continue
		var h: Variant = o.history[back % HISTORY]
		if h == null or h[0] != back:
			continue
		saved.append([o.target, o.target.pos])
		o.target.pos = h[1]
	return saved


## This player's combat events become everyone's: damage, kills, and effects to show.
func _collect(c: Peer) -> void:
	for e: Dictionary in c.combat.fx:
		if e.type == "reload" or e.type == "switch":
			continue # only their own screen cares
		e.by = c.id
		events.append(e)
		if e.type != "hit":
			continue
		var victim: Peer = peers.get(e.target)
		if victim == null:
			continue
		victim.sim.hp = victim.target.hp
		victim.sim.regen_delay = REGEN_DELAY
		if e.kill and not victim.sim.dead:
			victim.sim.dead = true
			victim.respawn_t = RESPAWN_DELAY
			victim.deaths += 1
			c.kills += 1
			events.append({"type": "kill", "killer": c.id, "victim": victim.id, "weapon": c.combat.weapon().id})
	c.combat.fx.clear()
