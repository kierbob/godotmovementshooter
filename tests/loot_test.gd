extends SceneTree
## Checks gold, chests and dropped items (Loot), headless: kills pay gold, a chest needs its price,
## opening one throws out an item that lands, floats and is yours when you walk into it, the
## rarity odds, and each run's chests on Sunstone Valley's chest spots.
##   godot --headless --path . --script res://tests/loot_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	var map := MapData.load_map("sunstone-valley")
	var combat := Combat.new(map.boxes, [])
	combat.grid = map
	var enemies := Enemies.new(map, combat)
	var loot := Loot.new(map, combat.up)
	loot.rng.seed = 5

	# ---- the stage's chests ----
	check("Sunstone Valley has chest spots (%d)" % map.chests.size(), map.chests.size() >= 20)
	loot.place_chests()
	var on_spots := loot.chests.all(func(c: Loot.Chest) -> bool:
		return map.chests.any(func(s: Dictionary) -> bool: return Vector3(s.x, s.y, s.z).distance_to(c.pos) < 0.01))
	check("a run puts %d chests on a random pick of them" % Loot.CHESTS_PER_RUN, loot.chests.size() == Loot.CHESTS_PER_RUN and on_spots)
	var other := Loot.new(map, combat.up)
	other.rng.seed = 99
	other.place_chests()
	check("...a different pick next run", other.chests.map(func(c: Loot.Chest) -> Vector3: return c.pos) != loot.chests.map(func(c: Loot.Chest) -> Vector3: return c.pos))
	var big := 0
	for i in 40:
		var l := Loot.new(map, combat.up)
		l.rng.seed = i
		l.place_chests()
		big += l.chests.filter(func(c: Loot.Chest) -> bool: return c.size == "large").size()
	check("some are large chests (%.1f a run)" % (big / 40.0), big > 40 and big < 40 * Loot.CHESTS_PER_RUN / 2)

	# ---- gold ----
	var player := PlayerSim.new(0, 0, 46)
	for i in 5:
		player.step(Cmd.new(), map, Cfg.TICK_DT)
	loot = Loot.new(map, combat.up)
	loot.rng.seed = 7
	var gunner := enemies.spawn("gunner", Vector3(0, 0, 30))
	var brute := enemies.spawn("brute", Vector3(6, 0, 30))
	combat.damage_target(gunner.target, 999, "body", gunner.center())
	combat.damage_target(brute.target, 999, "body", brute.center())
	enemies.tick(player, Cfg.TICK_DT)
	loot.tick(player, enemies.deaths, Cfg.TICK_DT)
	check("kills pay gold (gunner %d + brute %d = %d)" % [Loot.GOLD.gunner, Loot.GOLD.brute, loot.gold],
		loot.gold == Loot.GOLD.gunner + Loot.GOLD.brute and loot.events.filter(func(e: Dictionary) -> bool: return e.type == "gold").size() == 2)
	enemies.tick(player, Cfg.TICK_DT)
	loot.tick(player, enemies.deaths, Cfg.TICK_DT)
	check("...once each", loot.gold == Loot.GOLD.gunner + Loot.GOLD.brute)

	# ---- a chest ----
	loot.gold = 10
	var chest := loot.add_chest(Vector3(0, 0, 44), "small")
	check("standing next to a chest, it's in reach", loot.chest_in_reach(player) == chest)
	loot.events.clear()
	check("$10 can't open a $%d chest" % Loot.CHESTS.small.cost, not loot.open(chest, player) and not chest.opened
		and loot.events.any(func(e: Dictionary) -> bool: return e.type == "deny"))
	loot.gold = 30
	var total_before := combat.up.total
	check("$30 opens it (and leaves $%d)" % (30 - Loot.CHESTS.small.cost), loot.open(chest, player) and chest.opened
		and loot.gold == 30 - Loot.CHESTS.small.cost and loot.drops.size() == 1)
	check("an opened chest is out of reach and won't open again", loot.chest_in_reach(player) == null and not loot.open(chest, player))
	var drop: Loot.Drop = loot.drops[0]
	# stand back so it can land first
	var away := PlayerSim.new(8, 0, 50)
	for i in 240:
		loot.tick(away, [] as Array[Dictionary], Cfg.TICK_DT)
	check("the item hops out and lands, floating %.1f m up (at %.2f)" % [Loot.HOVER, drop.pos.y], drop.landed and absf(drop.pos.y - Loot.HOVER) < 0.01
		and drop.pos.distance_to(chest.pos) < 4.0 and combat.up.total == total_before)
	var walker := PlayerSim.new(drop.pos.x, 0, drop.pos.z + 3.0)
	var c := Cmd.new()
	c.forward = 1.0
	for i in 60:
		walker.step(c, map, Cfg.TICK_DT)
		loot.tick(walker, [] as Array[Dictionary], Cfg.TICK_DT)
	check("walking into it picks it up (%s)" % Upgrades.LIST[drop.item].name, loot.drops.is_empty() and combat.up.count(drop.item) >= 1
		and combat.up.total == total_before + 1 and loot.events.any(func(e: Dictionary) -> bool: return e.type == "pickup"))

	# ---- odds ----
	loot.rng.seed = 1
	var got := {"common": 0, "uncommon": 0, "rare": 0}
	for i in 20000:
		got[Upgrades.LIST[loot.roll_item("small")].rarity] += 1
	check("small chests: %.1f%% common, %.1f%% uncommon, %.1f%% rare (79 / 20 / 1)" % [got.common / 200.0, got.uncommon / 200.0, got.rare / 200.0],
		absf(got.common / 200.0 - 79.0) < 1.5 and absf(got.uncommon / 200.0 - 20.0) < 1.5 and absf(got.rare / 200.0 - 1.0) < 0.5)
	got = {"common": 0, "uncommon": 0, "rare": 0}
	for i in 20000:
		got[Upgrades.LIST[loot.roll_item("large")].rarity] += 1
	check("large chests: never common, %.1f%% uncommon, %.1f%% rare (80 / 20)" % [got.uncommon / 200.0, got.rare / 200.0],
		got.common == 0 and absf(got.uncommon / 200.0 - 80.0) < 1.5)

	# ---- items can't get lost ----
	loot.gold = 100
	var edge := loot.add_chest(Vector3(0, 0, 44), "small")
	loot.open(edge, player)
	var lost: Loot.Drop = loot.drops[0]
	lost.pos = Vector3(0, -29.9, 44)
	lost.vel = Vector3(0, -30, 0) # past the -30 m kill height this tick
	lost.landed = false
	loot.tick(away, [] as Array[Dictionary], Cfg.TICK_DT)
	check("an item that falls out of the world comes back to its chest", lost.pos.y > 0.0)

	print("\n%s" % ("all loot checks passed" if fails == 0 else "%d loot check(s) failed" % fails))
	quit(1 if fails else 0)
