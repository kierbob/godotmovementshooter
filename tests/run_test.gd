extends SceneTree
## Checks a run's stage (Director), headless on Sunstone Valley: waves arrive on their own around
## you, get bigger and tougher, unlock new enemies, a wave ends when it's all dead, the boss comes
## after the last one, killing it clears the stage and calls the next; later stages are harder and
## pay more. With the stage's nav grid: nothing ever spawns inside anything, ground enemies find
## their way to you around walls and up to ledges, lost ones are brought back, and the last few of
## a wave (and the boss) are marked.
##   godot --headless --path . --script res://tests/run_test.gd

var fails := 0
var map: MapData
var player: PlayerSim
var combat: Combat
var enemies: Enemies
var director: Director
var nav: Nav


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func setup(stage := 1) -> void:
	player = PlayerSim.new(map.spawn.x, map.spawn.y, map.spawn.z)
	combat = Combat.new(map.boxes, [])
	combat.grid = map
	enemies = Enemies.new(map, combat)
	enemies.nav = nav
	enemies.god = true
	director = Director.new(enemies, map, stage)
	director.rng.seed = 4
	for i in 5:
		step()


var seen := {} # every enemy id so far
var spawned_inside := 0
var spawned := 0


func step() -> void:
	combat.tick(player, Cmd.new(), Cfg.TICK_DT)
	player.step(Cmd.new(), map, Cfg.TICK_DT)
	enemies.tick(player, Cfg.TICK_DT)
	director.tick(player, Cfg.TICK_DT)
	for e in enemies.list:
		if not seen.has(e.id):
			seen[e.id] = true
			spawned += 1
			if not fits(e):
				spawned_inside += 1


func run(secs: float) -> Array[Dictionary]:
	var evs: Array[Dictionary] = []
	for i in int(secs * Cfg.TICK_RATE):
		step()
		evs.append_array(director.events)
		director.events.clear()
		enemies.events.clear()
	return evs


func kill_all() -> void:
	for e in enemies.list:
		e.target.hp = 0.0
		e.target.dead = true


## Let the wave arrive, then kill it all (repeatedly, as the rest comes in) until it's over.
func clear_wave() -> Array[Dictionary]:
	var evs: Array[Dictionary] = []
	for i in 40:
		evs.append_array(run(0.5))
		kill_all()
		if director.phase != "wave":
			break
	evs.append_array(run(0.1))
	return evs


## Is an enemy where it fits: a ground one's whole body clear of every box, a flyer's ball too?
func fits(e: Enemies.Enemy) -> bool:
	if e.body:
		return enemies._body_fits(Vector3(e.body.px, e.body.py, e.body.pz), e.def.size)
	return enemies._push_out(e.pos, 0.5 * e.def.size).distance_to(e.pos) < 0.01


func _init() -> void:
	map = MapData.load_map("sunstone-valley")
	var t0 := Time.get_ticks_msec()
	nav = Nav.build(map)
	var sp := nav.node_near(Vector3(map.spawn.x, map.spawn.y, map.spawn.z))
	check("the nav grid: %d spots in %d ms, the spawn is in the main area (%d spots), %d launch pads linked" % [nav.size(), Time.get_ticks_msec() - t0, nav.comp_size.get(nav.comp[sp], 0) if sp >= 0 else 0, nav.pad_edges.size()],
		nav.size() > 10000 and sp >= 0 and nav.comp[sp] == nav.biggest and nav.pad_edges.size() > 0)
	setup()
	var evs := run(Director.FIRST_BREAK + 0.2)
	var start: Array = evs.filter(func(e: Dictionary) -> bool: return e.type == "wave_start")
	check("wave 1 starts on its own after %.0f s (%d enemies)" % [Director.FIRST_BREAK, start[0].count if not start.is_empty() else 0],
		start.size() == 1 and director.wave == 1 and director.phase == "wave")
	var first := {} # id -> how far from you it appeared
	for i in int(6.0 * Cfg.TICK_RATE):
		step()
		director.events.clear()
		enemies.events.clear()
		for e in enemies.list:
			if not first.has(e.id):
				first[e.id] = Vector2(e.target.pos.x - player.px, e.target.pos.z - player.pz).length()
	var dists: Array = first.values()
	var far_ok := dists.all(func(d: float) -> bool: return d > Director.SPAWN_MIN - 3.0 and d < Director.SPAWN_MAX + 3.0)
	check("they arrive around you, 16-34 m out (%d so far, %.0f-%.0f m)" % [dists.size(), dists.min() if not dists.is_empty() else 0.0, dists.max() if not dists.is_empty() else 0.0],
		dists.size() > 3 and far_ok)
	var wave1: Array = enemies.list.map(func(e: Enemies.Enemy) -> String: return e.type)
	var bad := enemies.list.filter(func(e: Enemies.Enemy) -> bool: return not fits(e))
	check("...each where it fits, never inside anything (%d inside)" % bad.size(), bad.is_empty() and not enemies.list.is_empty())
	check("wave 1 is swarmers, chargers and gunners only (%s)" % str(wave1.duplicate()), wave1.all(func(t: String) -> bool: return Director.UNLOCK[t] <= 1))
	var hp1: float = enemies.list[0].target.max_hp / Enemies.TYPES[enemies.list[0].type].hp
	evs = clear_wave()
	check("killing all of it ends the wave, then a break", evs.any(func(e: Dictionary) -> bool: return e.type == "wave_clear") and director.phase == "break")
	evs = run(Director.BREAK + 0.2)
	start = evs.filter(func(e: Dictionary) -> bool: return e.type == "wave_start")
	check("wave 2 comes after the break, with a bigger budget (%d enemies)" % [start[0].count if not start.is_empty() else 0],
		director.wave == 2 and not start.is_empty() and int(start[0].count) >= 1 and Director.budget(2, 1) > Director.budget(1, 1))
	run(4.0)
	var hp2: float = enemies.list[0].target.max_hp / Enemies.TYPES[enemies.list[0].type].hp if not enemies.list.is_empty() else 0.0
	check("...and tougher (health x%.2f, then x%.2f; they hit x%.2f)" % [hp1, hp2, enemies.damage_mult], hp2 > hp1 and enemies.damage_mult > 1.0)

	# every wave, then the boss
	for w in range(director.wave, Director.WAVES + 1):
		clear_wave()
		if director.phase == "break":
			run(Director.BREAK + 0.2)
	check("after wave %d: BOSS INCOMING" % Director.WAVES, director.wave == Director.WAVES and director.phase in ["boss_warn", "boss"])
	evs = run(Director.BOSS_WARN + 0.5)
	var boss := director.boss
	check("the boss lands (%s, %.0f health)" % [boss.def.name if boss else "none", boss.target.max_hp if boss else 0.0],
		boss != null and director.phase == "boss" and evs.any(func(e: Dictionary) -> bool: return e.type == "boss"))
	run(3.0)
	check("...and nothing else spawns while it's up", enemies.list.filter(func(e: Enemies.Enemy) -> bool: return e.type != "colossus" and e.type != "swarmer").is_empty())
	boss.target.hp = 0.0
	boss.target.dead = true
	evs = run(0.5)
	check("killing the boss clears the stage", director.phase == "cleared" and evs.any(func(e: Dictionary) -> bool: return e.type == "stage_clear"))
	evs = run(Director.CLEARED_TIME + 0.5)
	check("...then it calls the next stage", evs.any(func(e: Dictionary) -> bool: return e.type == "next_stage" and e.stage == 2))
	check("the run counted every kill (%d)" % director.kills, director.kills > 30)
	check("all %d enemies of the stage (the boss's swarmers too) appeared where they fit (%d inside anything)" % [spawned, spawned_inside],
		spawned > 100 and spawned_inside == 0)

	# safe spots for every type, all over the map
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tried := 0
	var inside := 0
	for i in 400:
		var at := nav.pos[rng.randi() % nav.size()]
		for type: String in Enemies.TYPES:
			var s := enemies.safe_spot(at, 2.0, 30.0, type, -1, rng)
			if s == Vector3.INF:
				continue
			tried += 1
			if Enemies.TYPES[type].family == "flyer":
				if enemies._push_out(s, 0.5 * Enemies.TYPES[type].size).distance_to(s) > 0.01:
					inside += 1
			elif not enemies._body_fits(s, Enemies.TYPES[type].size):
				inside += 1
	check("safe spots all over the map, every type, sized to fit (%d spots, %d inside anything)" % [tried, inside], tried > 2000 and inside == 0)

	# paths: an enemy with no straight way to you gets there anyway
	setup()
	director.phase = "cleared" # no waves: just these
	director.t = 1e9
	enemies.clear()
	var got := 0
	var pairs := 0
	var straight := 0
	var tries := 0
	while pairs < 10 and tries < 20000:
		tries += 1
		var a := rng.randi() % nav.size()
		var b := rng.randi() % nav.size()
		var pa := nav.pos[a]
		var pb := nav.pos[b]
		var d := Vector2(pa.x - pb.x, pa.z - pb.z).length()
		if nav.comp[a] != nav.biggest or nav.comp[b] != nav.biggest or d < 15 or d > 35:
			continue
		if enemies._can_see(pa + Vector3(0, 1.6, 0), pb + Vector3(0, 1.0, 0)):
			continue # it has to go around something...
		var route := nav.path(a, b)
		var plen := 0.0
		for r in range(1, route.size()):
			plen += nav.pos[route[r]].distance_to(nav.pos[route[r - 1]])
		if plen < d * 1.5 and absf(pa.y - pb.y) < 3.0:
			continue # ...a long way round, or up or down a level
		pairs += 1
		for with_nav in [true, false]:
			enemies.clear()
			enemies.nav = nav if with_nav else null
			player = PlayerSim.new(pb.x, pb.y, pb.z)
			var sw := enemies.spawn("swarmer", pa)
			sw.cd = 1e9 # just walking
			var arrived := false
			for t in int(40.0 * Cfg.TICK_RATE):
				player.step(Cmd.new(), map, Cfg.TICK_DT)
				enemies.tick(player, Cfg.TICK_DT)
				if Vector3(sw.body.px, sw.body.py, sw.body.pz).distance_to(Vector3(player.px, player.py, player.pz)) < 3.0:
					arrived = true
					break
			if with_nav and arrived:
				got += 1
			elif with_nav:
				print("      didn't make it: %s -> %s (stuck at %s)" % [pa, pb, Vector3(sw.body.px, sw.body.py, sw.body.pz)])
			elif not with_nav and arrived:
				straight += 1
	enemies.nav = nav
	check("around walls, up ramps, off ledges, over pads: %d / %d swarmers with a long way round reach you in 40 s (walking straight at you: %d)" % [got, pairs, straight],
		pairs == 10 and got >= 9 and straight < got)

	# the last few are marked; a lost one comes back
	setup()
	run(Director.FIRST_BREAK + 8.0)
	var tries2 := 0
	while director.left() > 3 and tries2 < 40:
		tries2 += 1
		var some: Array = enemies.list.filter(func(e: Enemies.Enemy) -> bool: return e.alive)
		if some.size() > 3:
			some[0].target.hp = 0.0
			some[0].target.dead = true
		run(0.3)
	var marks := director.marked()
	check("the last %d of the wave are marked (and only them)" % director.left(), director.left() <= Director.MARK_LEFT and marks.size() == director.left() and director.left() > 0)
	var lost: Enemies.Enemy = marks[0] if not marks.is_empty() else null
	if lost:
		var far := nav.random_spot(rng, Vector3(player.px, player.py, player.pz), 80.0, 110.0, nav.biggest, 1.0, 40.0, 200)
		enemies.move_to(lost, nav.pos[far] + (Vector3(0, 4, 0) if lost.body == null else Vector3.ZERO))
		lost.los_t = 1e9 # can't see you (as if behind a hill)
		lost.los = false
		evs = run(Director.LOST_TIME + 1.0)
		var back := lost.center().distance_to(Vector3(player.px, player.py, player.pz))
		check("one that's lost for %.0f s comes back around you (%.0f m away)" % [Director.LOST_TIME, back],
			evs.any(func(e: Dictionary) -> bool: return e.type == "fetched" and e.id == lost.id) and back < Director.SPAWN_MAX + 6.0 and fits(lost))
	director.skip_to_boss()
	run(1.5)
	check("the boss is marked", director.marked().size() == 1 and director.marked()[0] == director.boss)

	# later stages
	setup(2)
	check("stage 2: everything tougher, hits harder, pays more (health x%.1f, damage x%.2f, money x%.1f)" % [director.hp_mult(), enemies.damage_mult, director.money_mult()],
		director.hp_mult() > 1.5 and enemies.damage_mult > 1.2 and director.money_mult() > 1.2)
	check("the stage list: stage 1 is %s, and a stage whose map isn't built yet is skipped (stage 2: %s)" % [Characters.stage_map(1), Characters.stage_map(2)],
		Characters.stage_map(1) == Characters.FIRST_STAGE and MapData.list().has(Characters.stage_map(2)))

	# stage 2: the Fantasy Village
	map = MapData.load_map("fantasy-village")
	t0 = Time.get_ticks_msec()
	nav = Nav.build(map)
	sp = nav.node_near(Vector3(map.spawn.x, map.spawn.y, map.spawn.z))
	check("Fantasy Village: a big map (%d nav spots in %d ms, the spawn's area %d), %d chest spots, %d kit pieces" % [nav.size(), Time.get_ticks_msec() - t0, nav.comp_size.get(nav.comp[sp], 0) if sp >= 0 else 0, map.chests.size(), map.models.size()],
		nav.size() > 30000 and sp >= 0 and nav.comp[sp] == nav.biggest and map.chests.size() >= Loot.CHESTS_PER_RUN + Loot.BARRELS_PER_RUN and map.models.size() > 3000)
	spawned = 0
	spawned_inside = 0
	seen.clear()
	setup(2)
	run(Director.FIRST_BREAK + 8.0)
	check("...its first wave (%d enemies) all appear where they fit (%d inside anything)" % [spawned, spawned_inside], spawned > 5 and spawned_inside == 0)
	tried = 0
	inside = 0
	for i in 300:
		var at := nav.pos[rng.randi() % nav.size()]
		for type: String in Enemies.TYPES:
			var s := enemies.safe_spot(at, 2.0, 30.0, type, -1, rng)
			if s == Vector3.INF:
				continue
			tried += 1
			if Enemies.TYPES[type].family == "flyer":
				if enemies._push_out(s, 0.5 * Enemies.TYPES[type].size).distance_to(s) > 0.01:
					inside += 1
			elif not enemies._body_fits(s, Enemies.TYPES[type].size):
				inside += 1
	check("...and safe spots all over it, every type (%d spots, %d inside anything: houses, roofs, walls)" % [tried, inside], tried > 1500 and inside == 0)
	check("the stage list: stage 2 is the Fantasy Village now", Characters.stage_map(2) == "fantasy-village")

	print("\n%s" % ("all run checks passed" if fails == 0 else "%d run check(s) failed" % fails))
	quit(1 if fails else 0)
