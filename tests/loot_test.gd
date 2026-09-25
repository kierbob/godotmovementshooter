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
	var spot_at := func(c: Loot.Chest) -> bool:
		return map.chests.any(func(s: Dictionary) -> bool: return Vector3(s.x, s.y, s.z).distance_to(c.pos) < 0.01)
	var main_ones := loot.chests.filter(func(c: Loot.Chest) -> bool: return c.size != "barrel" and (c.size != "shop" or spot_at.call(c)))
	var barrels := loot.chests.filter(func(c: Loot.Chest) -> bool: return c.size == "barrel")
	check("a run fills %d chest spots (%d) and puts barrels on some of the rest (%d)" % [Loot.CHESTS_PER_RUN, main_ones.size(), barrels.size()],
		main_ones.size() == Loot.CHESTS_PER_RUN and main_ones.all(spot_at) and barrels.size() == Loot.BARRELS_PER_RUN and barrels.all(spot_at))
	var other := Loot.new(map, combat.up)
	other.rng.seed = 99
	other.place_chests()
	check("...a different pick next run", other.chests.map(func(c: Loot.Chest) -> Vector3: return c.pos) != loot.chests.map(func(c: Loot.Chest) -> Vector3: return c.pos))
	var kinds := {}
	var shops_ok := true
	for i in 60:
		var l := Loot.new(map, combat.up)
		l.rng.seed = i
		l.place_chests()
		for c in l.chests:
			kinds[c.size] = kinds.get(c.size, 0) + 1
		var groups := {}
		for c in l.chests:
			if c.size == "shop":
				groups[c.group] = groups.get(c.group, []) + [c.item]
		for g: Variant in groups:
			var items: Array = groups[g]
			if items.size() != 3 or items[0] == items[1] or items[1] == items[2] or items[0] == items[2]:
				shops_ok = false
	check("runs mix every kind of thing (%s)" % str(kinds), Loot.CHESTS.keys().all(func(k: String) -> bool: return kinds.get(k, 0) > 0))
	check("shops come as three terminals with three different items", kinds.get("shop", 0) > 0 and shops_ok)

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
	check("kills give XP too (%.0f toward level 2, or level %d)" % [combat.up.xp, combat.up.level],
		combat.up.level == 2 and absf(combat.up.xp - (Loot.GOLD.gunner + Loot.GOLD.brute - Upgrades.xp_to_next(1))) < 0.001)

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
	var got := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	for i in 20000:
		got[Upgrades.LIST[loot.roll_item("small")].rarity] += 1
	var so: Dictionary = Loot.SMALL_ODDS
	check("small chests: %.1f%% common, %.1f%% uncommon, %.1f%% rare (%.0f / %.0f / %.0f)" % [got.common / 200.0, got.uncommon / 200.0, got.rare / 200.0, so.common, so.uncommon, so.rare],
		absf(got.common / 200.0 - so.common) < 1.5 and absf(got.uncommon / 200.0 - so.uncommon) < 1.5 and absf(got.rare / 200.0 - so.rare) < 0.8)
	got = {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	for i in 20000:
		got[Upgrades.LIST[loot.roll_item("large")].rarity] += 1
	var lo: Dictionary = Loot.CHESTS.large.odds
	check("large chests: never common, %.1f%% uncommon, %.1f%% rare, %.1f%% legendary (%.0f / %.0f / %.0f)" % [got.uncommon / 200.0, got.rare / 200.0, got.legendary / 200.0, lo.uncommon, lo.rare, lo.legendary],
		got.common == 0 and absf(got.uncommon / 200.0 - lo.uncommon) < 1.5 and got.legendary > 0)
	# a cleared wave's item: better the later the wave
	var early := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	var late := early.duplicate()
	for i in 4000:
		early[Upgrades.LIST[loot.roll_wave_item(1)].rarity] += 1
		late[Upgrades.LIST[loot.roll_wave_item(7)].rarity] += 1
	check("wave items: wave 1 mostly uncommon, no legendaries (%s); wave 7 no commons, mostly rare (%s)" % [str(early), str(late)],
		early.legendary == 0 and early.uncommon > early.common and late.common == 0 and late.rare > late.uncommon and late.legendary > 0)

	# ---- every kind ----
	var buyer := PlayerSim.new(0, 0, 46)
	for i in 5:
		buyer.step(Cmd.new(), map, Cfg.TICK_DT)
	loot = Loot.new(map, combat.up)
	loot.rng.seed = 3
	loot.gold = 100000
	var golden := loot.add_chest(Vector3(0, 0, 44), "golden")
	loot.open(golden, buyer)
	check("a golden chest ($%d) always holds a legendary (%s)" % [Loot.CHESTS.golden.cost, loot.drops[0].item],
		Upgrades.LIST[loot.drops[0].item].rarity == "legendary")
	var themed_ok := true
	for kind: String in ["damage", "utility", "healing"]:
		for i in 60:
			var it := loot.roll_item(kind)
			if Upgrades.LIST[it].tag not in Loot.CHESTS[kind].tags:
				themed_ok = false
	check("themed chests only hold their kind of item (damage / utility / healing)", themed_ok)
	loot.drops.clear()
	loot._place_shop(Vector3(0, 0, 40), 0.0)
	var terms := loot.chests.filter(func(c: Loot.Chest) -> bool: return c.size == "shop")
	var pick: Loot.Chest = terms[1]
	loot.open(pick, buyer)
	check("buying from one terminal gives its item and shuts the other two", loot.drops.size() == 1
		and loot.drops[0].item == pick.item and terms.all(func(c: Loot.Chest) -> bool: return c.opened))
	loot.drops.clear()
	var tries := 0
	var gifts := 0
	var rising := true
	var dry := true
	for n in 10:
		loot.drops.clear()
		var shrine := loot.add_chest(Vector3(0, 0, 36), "shrine")
		var last := 0
		while not shrine.opened and tries < 500:
			rising = rising and shrine.cost > last
			last = shrine.cost
			loot.open(shrine, buyer)
			tries += 1
		gifts += loot.drops.size()
		dry = dry and shrine.opened and loot.drops.size() == Loot.SHRINE.gifts
	check("shrines: sometimes nothing (%d prayers for %d gifts), pricier every try, dry after %d gifts" % [tries, gifts, Loot.SHRINE.gifts],
		tries > gifts and rising and dry)
	loot.gold = 0
	var barrel := loot.add_chest(Vector3(0, 0, 32), "barrel")
	check("barrels are free: smash one for a little gold ($%d)" % (0 if not loot.open(barrel, buyer) else loot.gold),
		barrel.opened and loot.gold >= 6 and loot.gold <= 14)

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
