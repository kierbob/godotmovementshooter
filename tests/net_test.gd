extends SceneTree
## Checks multiplayer headless: the codec round-trips, the server's simulation of a player agrees
## exactly with that player's own prediction, damage / kills / respawns / spawn protection,
## explosion knockback on other players, lag compensation, prediction correction after lag, and
## a real host and client talking over ENet on localhost.
##   godot --headless --path . --script res://tests/net_test.gd

var fails := 0
var map: MapData
var flat: MapData # open floor for the combat checks


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	seed(3)
	map = MapData.load_file("res://tests/maps/bean-street.json")
	flat = MapData.new()
	var floor_box := MapData.Box.new()
	floor_box.min_x = -100.0
	floor_box.min_y = -1.0
	floor_box.min_z = -100.0
	floor_box.max_x = 100.0
	floor_box.max_y = 0.0
	floor_box.max_z = 100.0
	flat.boxes = [floor_box]
	flat.spawns = [{"x": 40.0, "y": 0.0, "z": 40.0, "yaw": 0.0}, {"x": -40.0, "y": 0.0, "z": -40.0, "yaw": 0.0}]
	codec()
	prediction_matches_server()
	damage_and_respawn()
	knockback_and_lag_comp()
	correction_after_lag()
	await enet()
	print("\n%s" % ("all net checks passed" if fails == 0 else "%d net checks FAILED" % fails))
	quit(1 if fails > 0 else 0)


func rand_cmd(i: int) -> Cmd:
	var c := Cmd.new()
	c.forward = [1.0, 1.0, 0.0, -1.0][(i / 40) % 4]
	c.right = [0.0, 1.0, -1.0][(i / 70) % 3]
	c.sprint = (i / 90) % 2 == 0
	c.jump = i % 53 == 0
	c.jump_held = c.jump
	c.slide = (i / 110) % 3 == 1
	c.slide_pressed = i % 110 == 37
	c.crouch = c.slide
	c.fire = i % 97 < 3
	c.fire_pressed = i % 97 == 0
	c.yaw = sin(i * 0.013) * 3.0
	c.pitch = sin(i * 0.007) * 0.9
	return c


func codec() -> void:
	var cmds := []
	for i in 20:
		cmds.append([i + 1, 1000 + i, rand_cmd(i * 7)])
	var back := NetCodec.unpack_cmds(NetCodec.pack_cmds(cmds))
	var same := back.size() == NetCodec.MAX_CMDS
	for k in back.size():
		var a: Array = cmds[cmds.size() - back.size() + k]
		var b: Array = back[k]
		var ca: Cmd = a[2]
		var cb: Cmd = b[2]
		same = same and a[0] == b[0] and a[1] == b[1] and ca.forward == cb.forward and ca.right == cb.right \
			and ca.jump == cb.jump and ca.sprint == cb.sprint and ca.slide_pressed == cb.slide_pressed \
			and ca.fire == cb.fire and ca.fire_pressed == cb.fire_pressed and ca.yaw == cb.yaw and ca.pitch == cb.pitch
	check("inputs round-trip exactly (newest %d of %d kept, yaw/pitch bit for bit)" % [NetCodec.MAX_CMDS, cmds.size()], same)
	check("garbage input packets are dropped", NetCodec.unpack_cmds(PackedByteArray([5, 1, 2])).is_empty())

	var p := PlayerSim.new(3.0, 1.0, -2.0)
	for i in 200:
		p.step(rand_cmd(i), map, Cfg.TICK_DT)
	var st := p.save_state()
	var snap := {"tick": 77, "me": {"seq": 12, "respawn_in": 1.5, "state": st},
		"players": [{"id": 1, "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "pitch": -0.2, "flags": 5, "weapon": "rocket", "hp": 87.4, "kills": 3, "deaths": 2}],
		"proj": [{"owner": 1, "id": 9, "kind": "frag", "stuck": false, "pos": Vector3(1, 2, 3), "vel": Vector3(4, 5, 6)}]}
	var s2 := NetCodec.unpack_snapshot(NetCodec.pack_snapshot(snap))
	check("snapshots round-trip (own state bit for bit)", s2.tick == 77 and s2.me.seq == 12 and s2.me.state == st
		and s2.players[0].weapon == "rocket" and s2.players[0].hp == 88 and s2.players[0].kills == 3
		and s2.proj[0].kind == "frag" and s2.proj[0].vel == Vector3(4, 5, 6))
	check("a full snapshot fits in one UDP packet (%d bytes for 8 players, 20 projectiles)" % _big_snapshot_size(st),
		_big_snapshot_size(st) < 1200)

	# restoring a saved state and carrying on gives exactly the same run
	var q := PlayerSim.new()
	q.load_state(st)
	var same_run := true
	for i in range(200, 500):
		p.step(rand_cmd(i), map, Cfg.TICK_DT)
		q.step(rand_cmd(i), map, Cfg.TICK_DT)
		same_run = same_run and p.save_state() == q.save_state()
	check("a restored movement state carries on identically", same_run)


func _big_snapshot_size(st: PackedFloat64Array) -> int:
	var players := []
	for i in 8:
		players.append({"id": 100000 + i, "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "pitch": -0.2, "flags": 5, "weapon": "rocket", "hp": 87.0, "kills": 3, "deaths": 2})
	var proj := []
	for i in 20:
		proj.append({"owner": 1, "id": i, "kind": "frag", "stuck": false, "pos": Vector3(1, 2, 3), "vel": Vector3(4, 5, 6)})
	return NetCodec.pack_snapshot({"tick": 1, "me": {"seq": 1, "respawn_in": 0.0, "state": st}, "players": players, "proj": proj}).size()


## A client predicts its own movement + gun (knockback included) with the same inputs the server
## gets: the two must agree every tick.
func prediction_matches_server() -> void:
	var srv := MatchServer.new(map)
	var spawn := srv.add_player(1, "Host", {"primary": "shotgun", "secondary": "pistol", "ability": "impulse"})
	srv.add_player(2, "Far away", {})
	var far: MatchServer.Peer = srv.peers[2]
	far.sim.respawn(500, 50, 500) # out of the way (falls forever: the server respawns them; fine)
	var me := PlayerSim.new(spawn.x, spawn.y, spawn.z)
	var combat := Combat.new(map.boxes, [])
	combat.set_loadout(srv.peers[1].loadout)
	var srv_me: MatchServer.Peer = srv.peers[1]
	me.load_state(srv_me.sim.save_state()) # same spawn state (spawn protection etc.)
	var first_bad := -1
	var knock := 0
	for i in 900:
		var c := rand_cmd(i)
		combat.tick(me, c, Cfg.TICK_DT)
		me.step(c, map, Cfg.TICK_DT)
		srv.receive(1, [[i + 1, srv.tick, c]])
		srv.step()
		for e: Dictionary in combat.fx:
			if e.type == "shot":
				knock += 1
		combat.fx.clear()
		# the server also ticks spawn protection/regen, which the client doesn't: compare movement
		var a := me.save_state()
		var b := srv_me.sim.save_state()
		for k in [16, 18, 19, 20]:
			a[k] = 0.0
			b[k] = 0.0
		if a != b and first_bad < 0:
			first_bad = i
	check("the server's run of a player matches their prediction exactly (900 ticks, %d shotgun boosts)" % knock,
		first_bad < 0 and knock > 0)
	if first_bad >= 0:
		print("      first difference at tick %d" % first_bad)


func place(srv: MatchServer, id: int, x: float, z: float) -> MatchServer.Peer:
	var c: MatchServer.Peer = srv.peers[id]
	c.sim.respawn(x, 0.0, z)
	c.sim.invuln = 0.0
	for i in 3:
		c.sim.step(Cmd.new(), srv.map, Cfg.TICK_DT)
	return c


func aim_at(from: MatchServer.Peer, to: Vector3) -> Cmd:
	var eye := Vector3(from.sim.px, from.sim.eye_y(), from.sim.pz)
	var d := (to - eye).normalized()
	var c := Cmd.new()
	c.yaw = atan2(-d.x, -d.z)
	c.pitch = asin(d.y)
	return c


func run(srv: MatchServer, id: int, c: Cmd, n: int) -> void:
	var p: MatchServer.Peer = srv.peers[id]
	for i in n:
		srv.receive(id, [[p.queued_seq + 1, srv.tick, c]])
		srv.step()


func damage_and_respawn() -> void:
	var srv := MatchServer.new(flat)
	srv.add_player(1, "  Alice<script>  ", {"primary": "sniper", "secondary": "pistol", "ability": "frag"})
	srv.add_player(2, "", {"primary": "not-a-gun"})
	check("names are cleaned and defaulted", srv.peers[1].name == "Alicescript" and srv.peers[2].name == "Bean")
	check("bad loadouts fall back to the default", srv.peers[2].loadout.primary == Items.DEFAULT_LOADOUT.primary)
	check("everyone gets their own color", srv.peers[1].color != srv.peers[2].color)
	var a := place(srv, 1, 0.0, 0.0)
	var b := place(srv, 2, 0.0, -12.0)
	b.sim.invuln = 5.0
	srv.take_events()
	var c := aim_at(a, Vector3(b.sim.px, b.sim.py + 1.73, b.sim.pz)) # head
	c.fire = true
	c.fire_pressed = true
	run(srv, 1, c, 1)
	check("spawn protection blocks damage", b.sim.hp == b.sim.max_hp)
	b.sim.invuln = 0.0
	run(srv, 1, Cmd.new(), 200) # sniper: wait out the fire delay (and the shove it gave us)
	var hp0 := b.sim.hp
	c = aim_at(a, Vector3(b.sim.px, b.sim.py + 1.73, b.sim.pz))
	c.fire = true
	c.fire_pressed = true
	run(srv, 1, c, 1)
	var evs := srv.take_events()
	var hits := evs.filter(func(e: Dictionary) -> bool: return e.type == "hit")
	var kills := evs.filter(func(e: Dictionary) -> bool: return e.type == "kill")
	check("a sniper headshot kills a full-health player (hp %d -> %d)" % [hp0, b.sim.hp],
		b.sim.dead and hits.size() == 1 and hits[0].zone == "head" and hits[0].by == 1 and hits[0].target == 2)
	check("the kill is announced and counted", kills.size() == 1 and kills[0].killer == 1 and kills[0].victim == 2
		and a.kills == 1 and b.deaths == 1)
	var snap := srv.snapshot_for(2, srv.public_players(), srv.public_projectiles())
	check("the dead player's snapshot says when they respawn (%.2f s)" % snap.me.respawn_in, snap.me.respawn_in > 2.0)
	run(srv, 1, Cmd.new(), int(MatchServer.RESPAWN_DELAY * Cfg.TICK_RATE) + 2)
	evs = srv.take_events()
	check("they respawn after %.1f s with full health and spawn protection" % MatchServer.RESPAWN_DELAY,
		not b.sim.dead and b.sim.hp == b.sim.max_hp and b.sim.invuln > 0
		and evs.any(func(e: Dictionary) -> bool: return e.type == "respawn" and e.id == 2))
	# regen: hurt, wait, heal
	b.sim.invuln = 0.0
	b.sim.hp = 40.0
	b.target.hp = 40.0
	b.sim.regen_delay = MatchServer.REGEN_DELAY
	run(srv, 1, Cmd.new(), int((MatchServer.REGEN_DELAY + 1.0) * Cfg.TICK_RATE))
	check("health regenerates after %.0f s out of combat (%.0f hp)" % [MatchServer.REGEN_DELAY, b.sim.hp], b.sim.hp > 60.0)
	srv.remove_player(2)
	check("leaving removes the player and tells everyone", not srv.peers.has(2)
		and srv.take_events().any(func(e: Dictionary) -> bool: return e.type == "leave"))


func knockback_and_lag_comp() -> void:
	var srv := MatchServer.new(flat)
	srv.add_player(1, "A", {"primary": "rocket", "secondary": "pistol", "ability": "frag"})
	srv.add_player(2, "B", {})
	var a := place(srv, 1, 0.0, 0.0)
	var b := place(srv, 2, 0.0, -8.0)
	var c := aim_at(a, Vector3(b.sim.px, b.sim.py + 0.05, b.sim.pz + 0.6)) # the floor at their feet
	c.fire = true
	c.fire_pressed = true
	run(srv, 1, c, 1)
	var hurt := false
	var launched := false
	for i in 60:
		run(srv, 1, Cmd.new(), 1)
		for e: Dictionary in srv.take_events():
			if OS.get_environment("NET_DEBUG") != "":
				print("      ", e.type, " ", e.get("pos", ""), " ", e.get("target", ""))
		if b.sim.hp < b.sim.max_hp:
			hurt = true
		if b.sim.vy > 3.0 or b.sim.py > 0.3:
			launched = true
	check("a rocket at someone's feet hurts them and launches them", hurt and launched)

	# lag compensation: B strafes; A fires at where B was 150 ms ago, like a laggy screen would
	srv = MatchServer.new(flat)
	srv.add_player(1, "A", {"primary": "sniper", "secondary": "pistol", "ability": "frag"})
	srv.add_player(2, "B", {})
	a = place(srv, 1, 0.0, 0.0)
	b = place(srv, 2, -6.0, -14.0)
	var strafe := Cmd.new()
	strafe.right = 1.0
	strafe.sprint = true
	var seq_a := 0
	var seq_b := 0
	var past := {}
	for i in 120:
		seq_a += 1
		seq_b += 1
		srv.receive(1, [[seq_a, srv.tick, Cmd.new()]])
		srv.receive(2, [[seq_b, srv.tick, strafe]])
		srv.step()
		past[srv.tick] = Vector3(b.sim.px, b.sim.py, b.sim.pz)
	var then_tick := srv.tick - 18 # 150 ms
	var then_pos: Vector3 = past[then_tick]
	var now_pos := Vector3(b.sim.px, b.sim.py, b.sim.pz)
	var shot := aim_at(a, then_pos + Vector3(0, 0.8, 0))
	shot.fire = true
	shot.fire_pressed = true
	srv.take_events()
	seq_a += 1
	srv.receive(1, [[seq_a, then_tick, shot]])
	srv.receive(2, [[seq_b + 1, srv.tick, strafe]])
	srv.step()
	var evs := srv.take_events()
	check("lag compensation: a shot at where they were on your screen (%.1f m behind) hits" % then_pos.distance_to(now_pos),
		then_pos.distance_to(now_pos) > 1.0 and evs.any(func(e: Dictionary) -> bool: return e.type == "hit" and e.target == 2))
	# the same shot without rewinding (view tick = now) misses
	srv.peers[1].combat.state.primary.next_fire = 0.0
	srv.peers[1].combat.state.primary.ammo = 5
	seq_a += 1
	srv.receive(1, [[seq_a, srv.tick, shot]])
	srv.receive(2, [[seq_b + 2, srv.tick, strafe]])
	srv.step()
	evs = srv.take_events()
	check("...and the same shot judged against where they are now misses",
		not evs.any(func(e: Dictionary) -> bool: return e.type == "hit"))


## The client runs ahead of the server by the round trip. When the server's (older) state
## arrives, the client restores it and replays the newer inputs: it must land exactly where
## plain prediction put it (nothing to correct when nothing disagreed), and when the server did
## something the client couldn't know about (a knock from someone else's rocket), the correction
## must end up exactly on the server's truth.
func correction_after_lag() -> void:
	var srv := MatchServer.new(map)
	var spawn := srv.add_player(1, "Me", {})
	var sp: MatchServer.Peer = srv.peers[1]
	var me := PlayerSim.new()
	me.load_state(sp.sim.save_state())
	var combat := Combat.new(map.boxes, [])
	combat.set_loadout(sp.loadout)
	me.log_impulses = true
	var history := [] # [seq, cmd, impulses]
	var lag := 12 # ticks each way
	var in_flight := [] # [arrive_tick, cmds] to the server
	var back := [] # [arrive_tick, state, seq] to the client
	var worst := 0.0
	var knocked := false
	for t in 600:
		var c := rand_cmd(t)
		me.impulse_log = []
		combat.tick(me, c, Cfg.TICK_DT) # our own gun: shotgun boosts are predicted too
		combat.fx.clear()
		me.step(c, map, Cfg.TICK_DT)
		history.append([t + 1, c, me.impulse_log])
		in_flight.append([t + lag, [[t + 1, 0, c]]])
		while not in_flight.is_empty() and in_flight[0][0] <= t:
			srv.receive(1, in_flight.pop_front()[1])
		srv.step()
		if t == 300: # something only the server knows: a blast from another player
			sp.sim.apply_impulse(6.0, 9.0, 0.0, "rocket")
			knocked = true
		if t % 4 == 0:
			back.append([t + lag, sp.sim.save_state(), sp.last_seq])
		while not back.is_empty() and back[0][0] <= t:
			var m: Array = back.pop_front()
			var before := Vector3(me.px, me.py, me.pz)
			me.load_state(m[1])
			history = history.filter(func(h: Array) -> bool: return h[0] > m[2])
			me.quiet = true
			me.log_impulses = false
			for h: Array in history:
				for imp: Array in h[2]:
					me.apply_impulse(imp[0], imp[1], imp[2])
				me.step(h[1], map, Cfg.TICK_DT)
			me.quiet = false
			me.log_impulses = true
			if not knocked or t < 300:
				worst = maxf(worst, before.distance_to(Vector3(me.px, me.py, me.pz)))
	check("with 100 ms each way, corrections change nothing while nobody else interferes, shotgun boosts included (%.6f m)" % worst, worst == 0.0)
	# drain: after everything arrives, client and server agree
	for t in range(600, 640):
		var c := Cmd.new()
		me.step(c, map, Cfg.TICK_DT)
		history.append([t + 1, c, []])
		in_flight.append([t + lag, [[t + 1, 0, c]]])
		while not in_flight.is_empty() and in_flight[0][0] <= t:
			srv.receive(1, in_flight.pop_front()[1])
		srv.step()
	var st := sp.sim.save_state()
	me.load_state(st)
	var a := me.save_state()
	check("after a knock only the server saw, the corrected client ends up exactly on the server's state",
		knocked and a == st)


# ---------- real network ----------

func side(root_name: String) -> Net:
	var r := Node.new()
	r.name = root_name
	root.add_child(r)
	set_multiplayer(SceneMultiplayer.new(), r.get_path())
	var n := Net.new()
	n.name = "Net"
	r.add_child(n)
	return n


func wait_for(cond: Callable, ticks := 600) -> bool:
	for i in ticks:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func enet() -> void:
	await process_frame
	var host := side("HostSide")
	var client := side("ClientSide")
	var stage_sum := Net.map_checksum(MapData.load_map(Characters.FIRST_STAGE))

	var port := 7797
	var err := host.host(port, "Hosty", "bomber")
	check("hosting opens a lobby on UDP port %d (%s)" % [port, error_string(err)], err == OK and host.phase == "lobby")
	var got := {}
	client.joined.connect(func(w: Dictionary) -> void: got.welcome = w)
	client.failed.connect(func(why: String) -> void: got.failed = why)
	client.load_stage.connect(func(id: String) -> void: got.client_load = id)
	host.load_stage.connect(func(id: String) -> void: got.host_load = id)
	client.run_started.connect(func(st: Dictionary) -> void: got.client_go = st)
	host.run_started.connect(func(st: Dictionary) -> void: got.host_go = st)
	err = client.join("127.0.0.1:%d" % port, "Clienty", "sharpshooter")
	check("joining starts (%s)" % error_string(err), err == OK)
	await wait_for(func() -> bool: return got.has("welcome") or got.has("failed"))
	if not got.has("welcome"):
		check("the client is welcomed into the lobby", false)
		print("      ", got)
		host.leave()
		client.leave()
		return
	var cid := client.my_id
	await wait_for(func() -> bool: return client.lobby.size() == 2)
	check("the client is in the host's lobby, and both see both (names, characters)", client.phase == "lobby"
		and host.lobby.has(cid) and host.lobby[cid].character == "sharpshooter" and client.lobby.size() == 2
		and client.lobby[1].name == "Hosty" and client.lobby[1].character == "bomber")

	# ready up; un-readying during the countdown stops it
	host.set_me("bomber", true)
	client.set_me("brawler", true)
	await wait_for(func() -> bool: return host.countdown > 0)
	check("changing character and readying reaches the host; everyone ready starts the countdown",
		host.lobby[cid].character == "brawler" and host.lobby[cid].ready and host.countdown > 0)
	await wait_for(func() -> bool: return client.countdown > 0)
	check("the client sees the countdown", client.countdown > 0)
	client.set_me("brawler", false)
	await wait_for(func() -> bool: return host.countdown < 0)
	check("un-readying stops the countdown", host.countdown < 0 and host.phase == "lobby")
	client.set_me("brawler", true)
	await wait_for(func() -> bool: return got.has("host_load") and got.has("client_load"), 900)
	check("after the countdown everyone is told to load the first stage (%s)" % Characters.FIRST_STAGE,
		got.get("host_load", "") == Characters.FIRST_STAGE and got.get("client_load", "") == Characters.FIRST_STAGE)
	host.report_loaded(stage_sum)
	await wait_for(func() -> bool: return host.lobby[1].loaded, 60)
	check("the run waits for everyone to load", not got.has("host_go") and host.phase == "loading")
	client.report_loaded(stage_sum)
	await wait_for(func() -> bool: return got.has("host_go") and got.has("client_go"))
	check("when the last one has loaded, the run starts for everyone", got.has("host_go") and got.has("client_go")
		and host.server.peers.size() == 2 and host.phase == "run")
	check("everyone plays their character: kit and color", host.server.peers[cid].loadout == Characters.loadout("brawler")
		and host.server.peers[1].color == Characters.get_info("bomber").color)

	var start := Vector3(host.server.peers[cid].sim.px, 0, host.server.peers[cid].sim.pz)
	for i in 120:
		var c := Cmd.new()
		c.forward = 1.0
		c.sprint = true
		c.yaw = 0.3
		client.queue_cmd(c)
		host.queue_cmd(Cmd.new())
		await physics_frame
	for i in 30:
		host.queue_cmd(Cmd.new())
		await physics_frame
	var sp: MatchServer.Peer = host.server.peers[cid]
	var moved := Vector3(sp.sim.px, 0, sp.sim.pz).distance_to(start)
	check("the client's inputs reach the host and move them (%.1f m, %d inputs applied)" % [moved, sp.last_seq],
		moved > 5.0 and sp.last_seq >= 110)
	check("the client sees the host in its snapshots, with their name", client.remotes.has(1)
		and client.remotes[1].name == "Hosty" and client.sample(client.remotes[1]) != null)
	check("the host sees the client too", host.remotes.has(cid) and host.remotes[cid].name == "Clienty")
	var me_state: PackedFloat64Array = client.me.get("state", PackedFloat64Array())
	check("the client gets its own full state back, acknowledged up to its latest inputs",
		me_state.size() == PlayerSim.STATE_SIZE and client.me.seq >= 110)
	check("ping is measured (%.0f ms)" % client.ping, client.ping >= 0.0 and client.ping < 200.0)

	# someone joining mid-run loads and drops in; a different copy of the map is refused
	var late := side("LateSide")
	var late_got := {}
	late.load_stage.connect(func(id: String) -> void:
		late_got.load = id
		late.report_loaded(stage_sum))
	late.run_started.connect(func(_st: Dictionary) -> void: late_got.go = true)
	late.join("127.0.0.1:%d" % port, "Latey", "bomber")
	await wait_for(func() -> bool: return late_got.has("go"))
	check("joining mid-run loads the stage and drops you straight in", late_got.has("go")
		and host.server.peers.has(late.my_id))
	var bad := side("BadSide")
	var bad_got := {}
	bad.load_stage.connect(func(_id: String) -> void: bad.report_loaded(12345))
	bad.failed.connect(func(why: String) -> void: bad_got.failed = why)
	bad.run_started.connect(func(_st: Dictionary) -> void: bad_got.go = true)
	bad.join("localhost:%d" % port, "Other", "brawler")
	await wait_for(func() -> bool: return not bad_got.is_empty())
	check("a different copy of the map is refused with a reason", bad_got.has("failed")
		and String(bad_got.failed).contains("different"))

	client.leave()
	await wait_for(func() -> bool: return not host.server.peers.has(cid) and not host.lobby.has(cid), 240)
	check("when the client leaves, the host drops them", not host.server.peers.has(cid) and not host.lobby.has(cid))
	host.leave()
	late.leave()
	bad.leave()
	check("addresses parse: playit style, bare host, bad port", Net.parse_address("abc.gl.joinmc.link:12345") == ["abc.gl.joinmc.link", 12345]
		and Net.parse_address("192.168.1.5") == ["192.168.1.5", Net.DEFAULT_PORT] and Net.parse_address("x:99999").is_empty())
