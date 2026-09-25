extends SceneTree
## Checks the enemies play fair, headless: every attacker can hurt you but only after a visible
## windup, nobody hurts you through walls, moving dodges the projectiles / the sniper / the charge,
## jumping clears the brute's shockwave, the beam breaks when you leave its range, the healer only
## heals, and your guns kill them. Plus the admin console's commands.
##   godot --headless --path . --script res://tests/enemy_test.gd

const MIN_WINDUP := 0.25

var fails := 0
var map: MapData
var player: PlayerSim
var combat: Combat
var enemies: Enemies


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> MapData.Box:
	var b := MapData.Box.new()
	b.min_x = x0
	b.min_y = y0
	b.min_z = z0
	b.max_x = x1
	b.max_y = y1
	b.max_z = z1
	return b


## An open floor, plus (optionally) a sealed room around the origin.
func make_map(room: bool) -> MapData:
	var m := MapData.new()
	m.boxes = [box(-150, -1, -150, 150, 0, 150)]
	if room:
		m.boxes.append_array([box(-4, 0, -4.5, 4, 5, -4), box(-4, 0, 4, 4, 5, 4.5), box(-4.5, 0, -4.5, -4, 5, 4.5),
			box(4, 0, -4.5, 4.5, 5, 4.5), box(-4.5, 5, -4.5, 4.5, 5.5, 4.5)])
	m.spawns = [{"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}]
	return m


func setup(room := false) -> void:
	map = make_map(room)
	player = PlayerSim.new(0, 0, 0)
	player.hp = 100000.0 # so long fights don't end: we count damage, not deaths
	player.max_hp = 100000.0
	combat = Combat.new(map.boxes, [])
	enemies = Enemies.new(map, combat)
	for i in 5:
		player.step(Cmd.new(), map, Cfg.TICK_DT)


## Run the sim for `secs`; move(t) -> Cmd drives the player. Returns every event.
func run(secs: float, move := Callable()) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for i in int(secs * Cfg.TICK_RATE):
		var t := i * Cfg.TICK_DT
		var c: Cmd = move.call(t) if move.is_valid() else Cmd.new()
		combat.tick(player, c, Cfg.TICK_DT)
		player.step(c, map, Cfg.TICK_DT)
		enemies.tick(player, Cfg.TICK_DT)
		for e in enemies.events:
			e.t = t
			all.append(e)
		enemies.events.clear()
	return all


func damage(evs: Array[Dictionary]) -> float:
	var d := 0.0
	for e in evs:
		if e.type == "hurt":
			d += float(e.dmg)
	return d


## Seconds from the first windup to the first hit (INF if it never hit, -1 if it hit with no windup).
func windup_to_hit(evs: Array[Dictionary]) -> float:
	var w := -1.0
	for e in evs:
		if e.type == "windup" and w < 0:
			w = e.t
		if e.type == "hurt":
			return e.t - w if w >= 0 else -1.0
	return INF


## Keep moving sideways (the way you'd dodge: aimed shots go where you were).
func strafe(_t: float) -> Cmd:
	var c := Cmd.new()
	c.right = 1.0
	c.sprint = true
	return c


func _init() -> void:
	# where each type starts: ground types on the floor, flyers in the air
	var start := {"charger": Vector3(0, 0, -7), "brute": Vector3(0, 0, -4.5), "swarmer": Vector3(0, 0, -5),
		"gunner": Vector3(0, 0, -14), "lobber": Vector3(0, 0, -16), "sniper": Vector3(0, 0, -28),
		"flyer_projectile": Vector3(0, 4, -12), "flyer_beam": Vector3(0, 4, -8), "flyer_healer": Vector3(0, 4, -6),
		"colossus": Vector3(0, 0, -12)}

	for type: String in Enemies.TYPES:
		setup()
		enemies.spawn(type, start[type])
		var evs := run(8.0)
		var dmg := damage(evs)
		if type == "flyer_healer":
			check("the healer never hurts you (%.0f damage in 8 s)" % dmg, dmg == 0.0)
			continue
		var wt := windup_to_hit(evs)
		check("%s hurts a player standing in the open (%.0f damage in 8 s)" % [Enemies.TYPES[type].name, dmg], dmg > 0)
		check("%s winds up before its first hit (%.2f s)" % [Enemies.TYPES[type].name, wt], wt >= MIN_WINDUP and wt < INF)

	# swarmers: slower than you walking, so you can outrun a pack
	setup()
	var sw := enemies.spawn("swarmer", Vector3(0, 0, -30))
	var top := 0.0
	for i in int(3.0 * Cfg.TICK_RATE):
		player.step(Cmd.new(), map, Cfg.TICK_DT)
		enemies.tick(player, Cfg.TICK_DT)
		top = maxf(top, sw.body.horizontal_speed())
	enemies.events.clear()
	check("swarmers run at most %.1f m/s (you walk at %.1f): %.2f m/s" % [Enemies.TYPES.swarmer.max_speed, Cfg.MOVE_WALK_SPEED, top],
		top <= Enemies.TYPES.swarmer.max_speed + 0.01 and top < Cfg.MOVE_WALK_SPEED)

	# through walls: sealed in a room, nothing ranged can touch you
	for type: String in ["gunner", "lobber", "sniper", "flyer_projectile", "flyer_beam"]:
		setup(true)
		var at: Vector3 = start[type] + Vector3(0, 0, -6)
		enemies.spawn(type, at)
		var dmg := damage(run(8.0))
		check("%s can't hurt you through walls (%.0f)" % [Enemies.TYPES[type].name, dmg], dmg == 0.0)

	# dodging: strafing beats the aimed shots
	for type: String in ["gunner", "sniper", "flyer_projectile"]:
		setup()
		enemies.spawn(type, start[type])
		var still := damage(run(8.0))
		setup()
		enemies.spawn(type, start[type])
		var moving := damage(run(8.0, strafe))
		check("strafing dodges most of the %s's shots (%.0f standing, %.0f strafing)" % [Enemies.TYPES[type].name, still, moving],
			moving < still * 0.5)
	# the sniper's lock: moving after it locks makes it miss
	setup()
	enemies.spawn("sniper", start.sniper)
	var locked_at := -1.0
	var evs: Array[Dictionary] = []
	for i in int(6.0 * Cfg.TICK_RATE):
		var t := i * Cfg.TICK_DT
		var c := Cmd.new()
		if locked_at >= 0: # it locked: move now
			c.right = 1.0
			c.sprint = true
		player.step(c, map, Cfg.TICK_DT)
		enemies.tick(player, Cfg.TICK_DT)
		for e in enemies.events:
			if e.type == "lock" and locked_at < 0:
				locked_at = t
			e.t = t
			evs.append(e)
		enemies.events.clear()
	var shots := evs.filter(func(e: Dictionary) -> bool: return e.type == "snipe")
	check("the sniper locks its aim before firing, and moving after the lock dodges it",
		locked_at >= 0 and not shots.is_empty() and not shots[0].hit)

	# the brute's shockwave: jumping clears it
	setup()
	enemies.spawn("brute", start.brute)
	var hop := func(t: float) -> Cmd:
		var c := Cmd.new()
		c.jump = true # keeps hopping: in the air when the wave rolls past
		c.jump_held = true
		return c
	var hopped := damage(run(6.0, hop))
	setup()
	enemies.spawn("brute", start.brute)
	var stood := damage(run(6.0))
	check("jumping clears the brute's shockwave (%.0f standing, %.0f hopping)" % [stood, hopped], stood > 0 and hopped < stood)

	# the charger: side-step after it winds up and the dash misses
	setup()
	enemies.spawn("charger", Vector3(0, 0, -8))
	var wind_at := -1.0
	evs = []
	for i in int(3.0 * Cfg.TICK_RATE):
		var t := i * Cfg.TICK_DT
		var c := Cmd.new()
		if wind_at >= 0 and t > wind_at + 0.3:
			c.right = 1.0
			c.sprint = true
		player.step(c, map, Cfg.TICK_DT)
		enemies.tick(player, Cfg.TICK_DT)
		for e in enemies.events:
			if e.type == "windup" and wind_at < 0:
				wind_at = t
			evs.append(e)
		enemies.events.clear()
	check("side-stepping the charger's windup makes its dash miss", wind_at >= 0 and damage(evs) == 0.0)

	# the beam breaks when you run out of its range
	setup()
	var beamer := enemies.spawn("flyer_beam", start.flyer_beam)
	var on_at := -1.0
	var off_at := -1.0
	var dmg_after := 0.0
	for i in int(6.0 * Cfg.TICK_RATE):
		var t := i * Cfg.TICK_DT
		var c := Cmd.new()
		if on_at >= 0:
			c.forward = 1.0 # run straight away from it (it faces -Z; we run +Z)
			c.yaw = PI
			c.sprint = true
		player.step(c, map, Cfg.TICK_DT)
		beamer.pos.z = minf(beamer.pos.z, -8.0) # hold it in place so the player can outrun it
		enemies.tick(player, Cfg.TICK_DT)
		for e in enemies.events:
			if e.type == "beam_on" and on_at < 0:
				on_at = t
			if e.type == "beam_off" and on_at >= 0 and off_at < 0:
				off_at = t
			if e.type == "hurt" and off_at >= 0:
				dmg_after += float(e.dmg)
		enemies.events.clear()
	check("running out of the beam's range breaks it (on %.2f s, off %.2f s)" % [on_at, off_at],
		on_at >= 0 and off_at > on_at and dmg_after == 0.0)

	# the healer heals a hurt enemy
	setup()
	var hurt_one := enemies.spawn("gunner", Vector3(0, 0, -30))
	hurt_one.target.hp = 30.0
	enemies.spawn("flyer_healer", Vector3(3, 4, -30))
	evs = run(3.0)
	check("the healer heals a hurt enemy (30 -> %.0f hp)" % hurt_one.target.hp, hurt_one.target.hp > 60.0
		and evs.any(func(e: Dictionary) -> bool: return e.type == "heal_on"))

	# healers never heal each other (they can't hurt you: that would only drag the fight out), and
	# never float off (two used to climb forever, hovering over each other)
	setup()
	var h1 := enemies.spawn("flyer_healer", Vector3(0, 4, -30))
	var h2 := enemies.spawn("flyer_healer", Vector3(4, 4, -30))
	h1.target.hp = 40.0
	h2.target.hp = 40.0
	var highest := 0.0
	for i in 8:
		run(1.0)
		highest = maxf(highest, maxf(h1.pos.y, h2.pos.y))
	check("two hurt healers don't heal each other (still %.0f and %.0f hp)" % [h1.target.hp, h2.target.hp],
		h1.target.hp == 40.0 and h2.target.hp == 40.0)
	check("...and stay low (highest %.1f m, cap %.0f m over the ground)" % [highest, Enemies.FLY_MAX], highest <= Enemies.FLY_MAX + 0.5)
	setup()
	for i in 6:
		enemies.spawn("flyer_projectile" if i % 2 else "flyer_beam", Vector3(i * 3 - 8, 4, -14))
	highest = 0.0
	for i in 6:
		run(1.0)
		for e in enemies.list:
			highest = maxf(highest, e.pos.y)
	check("attacking flyers hover within reach too (highest %.1f m)" % highest, highest <= Enemies.FLY_MAX + 0.5 and highest >= Enemies.FLY_MIN)

	# enemies are solid to each other: a pile spawned on one spot spreads out
	setup()
	for i in 12:
		enemies.spawn("swarmer" if i % 2 else "charger", Vector3(0.02 * i, 0, -20))
	enemies.god = true
	run(3.0)
	var closest := INF
	for a_e in enemies.list:
		for b_e in enemies.list:
			if a_e != b_e and absf(a_e.target.pos.y - b_e.target.pos.y) < 1.0:
				closest = minf(closest, Vector2(a_e.target.pos.x - b_e.target.pos.x, a_e.target.pos.z - b_e.target.pos.z).length())
	check("enemies don't stand inside each other (closest pair %.2f m apart)" % closest, closest > 0.4)

	# a crowd far away thinks less often, but still gets where it's going
	setup()
	var far_one := enemies.spawn("charger", Vector3(0, 0, -60))
	run(2.0)
	check("a far enemy (updated 30x a second) still walks at you (%.1f m closer)" % (far_one.target.pos.z + 60.0),
		far_one.target.pos.z > -60.0 + 8.0)

	# your guns kill them
	setup()
	combat.set_loadout({"primary": "sniper", "secondary": "pistol", "ability": "frag"})
	var target := enemies.spawn("swarmer", Vector3(0, 0, -10))
	enemies.frozen = true
	run(0.5)
	var eye := Vector3(player.px, player.eye_y(), player.pz)
	var d := (target.center() - eye).normalized()
	var shoot := func(_t: float) -> Cmd:
		var c := Cmd.new()
		c.yaw = atan2(-d.x, -d.z)
		c.pitch = asin(d.y)
		c.fire = true
		c.fire_pressed = true
		return c
	evs = run(0.1, shoot)
	check("your guns kill enemies (a swarmer to a sniper shot), and they're removed",
		evs.any(func(e: Dictionary) -> bool: return e.type == "died") and enemies.list.is_empty()
		and not combat.targets.has(target.target))

	# the player can die, god mode stops it
	setup()
	player.hp = 20.0
	player.max_hp = 100.0
	enemies.spawn("gunner", start.gunner)
	evs = run(8.0)
	check("enough damage splats the player", player.dead and evs.any(func(e: Dictionary) -> bool: return e.type == "player_died"))
	setup()
	player.hp = 20.0
	enemies.god = true
	enemies.spawn("gunner", start.gunner)
	run(8.0)
	check("god mode: no damage", player.hp == 20.0)

	console()
	print("\n%s" % ("all enemy checks passed" if fails == 0 else "%d enemy checks FAILED" % fails))
	quit(1 if fails > 0 else 0)


## The admin console understands what you'd type.
func console() -> void:
	var cases := {
		"spawn flyer beam": ["flyer_beam", 1], "spawn beam": ["flyer_beam", 1],
		"spawn healer 3": ["flyer_healer", 3], "SPAWN SWARMER 5": ["swarmer", 5], "spawn charger": ["charger", 1],
		"spawn flyer healer 2": ["flyer_healer", 2], "spawn sniper": ["sniper", 1], "spawn projectile flyer": ["flyer_projectile", 1],
	}
	var ok := true
	for text: String in cases:
		var r := AdminConsole.parse_spawn(text.to_lower().split(" ", false).slice(1))
		if r.is_empty() or r.type != cases[text][0] or r.count != cases[text][1]:
			ok = false
			print("      '%s' -> %s" % [text, r])
	check("the console understands spawn commands (Spawn Flyer, spawn flyer beam, spawn swarmer 5...)", ok)
	var fam := AdminConsole.parse_spawn("Spawn Flyer".to_lower().split(" ", false).slice(1))
	check("'Spawn Flyer' spawns one of the flyers", not fam.is_empty() and Enemies.FAMILIES.flyer.has(fam.type))
	fam = AdminConsole.parse_spawn(["runners", "3"])
	check("spawning a family picks one of its variants", not fam.is_empty() and Enemies.FAMILIES.runner.has(fam.type) and fam.count == 3)
	check("nonsense is rejected", AdminConsole.parse_spawn(["banana"]).is_empty())
