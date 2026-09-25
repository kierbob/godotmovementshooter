extends SceneTree
## Checks the stacking items (Upgrades), headless: the list itself, the console's name matching,
## that an empty inventory changes nothing, and every item doing what its card says (procs are
## forced with Four Leaf or enough stacks so nothing here is down to luck).
##   godot --headless --path . --script res://tests/item_test.gd

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


## A flat floor (plus a wall 10 m north for Ricochet), dummies at `dummies`, you at the origin.
func setup(dummies: Array = [], items := {}) -> void:
	map = MapData.new()
	map.boxes = [box(-150, -1, -150, 150, 0, 150), box(-20, 0, -11, 20, 6, -10)]
	player = PlayerSim.new(0, 0, 0)
	var ds := []
	for d: Vector3 in dummies:
		ds.append({"x": d.x, "y": d.y, "z": d.z})
	combat = Combat.new(map.boxes, ds)
	enemies = Enemies.new(map, combat)
	combat.up.rng.seed = 11
	for id: String in items:
		combat.up.add(id, items[id])
	for i in 5:
		step()


func step(c: Cmd = null) -> void:
	if c == null:
		c = Cmd.new()
	combat.tick(player, c, Cfg.TICK_DT)
	player.step(c, map, Cfg.TICK_DT)
	enemies.tick(player, Cfg.TICK_DT)


func run(secs: float) -> void:
	for i in int(secs * Cfg.TICK_RATE):
		step()


func hits(src := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in combat.fx:
		if e.type == "hit" and (src == "" or e.src == src):
			out.append(e)
	return out


## Hit dummy i with a gun for dmg (straight through Combat, like a bullet would).
func shoot(i: int, dmg: float, zone := "body") -> void:
	var t: Combat.Target = combat.targets[i]
	combat.damage_target(t, dmg, zone, t.pos + Vector3(0, 1, 0))


func dummy(i: int) -> Combat.Target:
	return combat.targets[i]


func _init() -> void:
	# ---- the list ----
	var by_rarity := {}
	var bad := []
	for id: String in Upgrades.LIST:
		var it: Dictionary = Upgrades.LIST[id]
		by_rarity[it.rarity] = by_rarity.get(it.rarity, 0) + 1
		for k in ["name", "rarity", "tag", "icon", "color", "desc", "stack"]:
			if not it.has(k):
				bad.append("%s.%s" % [id, k])
		if not Upgrades.RARITY.has(it.get("rarity", "")):
			bad.append(id + " rarity")
	var tags := {}
	for id: String in Upgrades.LIST:
		tags[Upgrades.LIST[id].tag] = true
	check("at least 25 items (%d: %s)" % [Upgrades.LIST.size(), str(by_rarity)], Upgrades.LIST.size() >= 25
		and by_rarity.get("common", 0) > 0 and by_rarity.get("uncommon", 0) > 0 and by_rarity.get("rare", 0) > 0)
	check("they cover every kind of thing (%s)" % ", ".join(tags.keys()), tags.size() >= 7)
	check("every item has a name, rarity, icon, color and text" + ("" if bad.is_empty() else " (%s)" % str(bad)), bad.is_empty())
	check("the console finds items by name or the start of it", Upgrades.find("match head") == "match_head"
		and Upgrades.find("triple") == "triple_tap" and Upgrades.find("rusty_nail") == "rusty_nail"
		and Upgrades.find("Four Leaf") == "four_leaf" and Upgrades.find("s") == "" and Upgrades.find("nope") == "")
	var words := AdminConsole.parse_give(["triple", "tap", "3"])
	check("'give triple tap 3' parses", words.get("id", "") == "triple_tap" and words.get("count", 0) == 3)
	check("'give random 5' parses", AdminConsole.parse_give(["random", "5"]).get("id", "") == "random")

	# ---- nothing held: nothing changes ----
	setup([Vector3(0, 0, -5)])
	shoot(0, 30.0)
	check("no items: a 30 damage hit does 30, no procs", absf(dummy(0).hp - (Combat.DUMMY_HP - 30.0)) < 0.001
		and dummy(0).status.is_empty() and combat.up.fire_dirs(Vector3.FORWARD).size() == 1)

	# ---- gun items ----
	setup([], {"extended_mag": 1, "quick_hands": 2, "hair_trigger": 1})
	combat.start_reload("primary")
	check("Quick Hands x2: reload 1.5 s -> %.2f s" % combat.state.primary.reload_t, absf(combat.state.primary.reload_t - 1.5 / 1.3) < 0.001)
	run(1.3)
	check("Extended Mag: the Boomstick reloads to 5 instead of 4", combat.mag_size("primary") == 5 and combat.state.primary.ammo == 5)
	check("Hair Trigger: fires 12% faster", absf(combat.up.fire_rate(10.0) - 11.2) < 0.001)

	setup([], {"triple_tap": 1})
	combat.set_loadout({"primary": "rocket", "secondary": "pistol", "ability": "knife"})
	var c := Cmd.new()
	c.fire = true
	c.fire_pressed = true
	c.pitch = -PI / 2 + 0.05 # at your feet: a rocket jump
	step(c)
	var rockets := combat.projectiles.filter(func(pr: Combat.Projectile) -> bool: return pr.kind == "rocket")
	var fan := []
	for pr: Combat.Projectile in rockets:
		fan.append(pr.copy)
	check("Triple Tap: one rocket becomes 3 (%d), two of them copies" % rockets.size(), rockets.size() == 3 and fan.count(true) == 2)
	c = Cmd.new()
	c.yaw = 0.0
	setup([], {"triple_tap": 1})
	combat.set_loadout({"primary": "rocket", "secondary": "pistol", "ability": "knife"})
	c.fire = true
	c.fire_pressed = true
	step(c)
	var dirs: Array = combat.projectiles.map(func(pr: Combat.Projectile) -> float: return rad_to_deg(atan2(pr.vel.x, -pr.vel.z)))
	dirs.sort()
	check("...fanned out in a V: %s degrees" % str(dirs.map(func(a: float) -> int: return roundi(a))), dirs.size() == 3
		and absf(dirs[0] + Upgrades.COPY_ANGLE) < 0.5 and absf(dirs[1]) < 0.5 and absf(dirs[2] - Upgrades.COPY_ANGLE) < 0.5)
	# only the real rocket launches you: same jump as a single rocket
	var jump_with := rocket_jump({"triple_tap": 2})
	var jump_without := rocket_jump({})
	check("...and only the real one pushes you (rocket jump %.1f vs %.1f m/s up)" % [jump_with, jump_without],
		jump_without > 5.0 and absf(jump_with - jump_without) < 0.01)
	setup([], {"triple_tap": 1})
	combat.set_loadout({"primary": "sniper", "secondary": "pistol", "ability": "knife"})
	step(c)
	var shots := combat.fx.filter(func(e: Dictionary) -> bool: return e.type == "shot")
	check("Triple Tap on a hitscan gun: 3 bullets", shots.size() == 1 and (shots[0].ends as Array).size() == 3)
	combat.fx.clear()
	var ab := Cmd.new()
	ab.ability = true
	step(ab)
	check("Triple Tap on a throw: 3 knives", combat.projectiles.filter(func(pr: Combat.Projectile) -> bool: return pr.kind == "knife").size() == 3)

	# ---- damage multipliers ----
	setup([Vector3(0, 0, -5), Vector3(0, 0, -30)], {"lucky_penny": 10})
	shoot(0, 10.0)
	check("Lucky Penny x10: every hit crits for double", hits()[0].crit and absf(hits()[0].dmg - 20.0) < 0.001)
	setup([Vector3(0, 0, -5), Vector3(0, 0, -30)], {"point_blank": 1})
	shoot(0, 10.0)
	shoot(1, 10.0)
	check("Point Blank: +25%% close (%.1f), nothing far (%.1f)" % [hits()[0].dmg, hits()[1].dmg],
		absf(hits()[0].dmg - 12.5) < 0.001 and absf(hits()[1].dmg - 10.0) < 0.001)
	setup([Vector3(0, 0, -30)], {"opening_act": 1})
	shoot(0, 20.0)
	shoot(0, 10.0)
	check("Opening Act: +50%% on a fresh enemy (%.1f), not after (%.1f)" % [hits()[0].dmg, hits()[1].dmg],
		absf(hits()[0].dmg - 30.0) < 0.001 and absf(hits()[1].dmg - 10.0) < 0.001)
	setup([Vector3(0, 0, -30)], {"headhunter": 2})
	shoot(0, 10.0, "head")
	check("Headhunter x2: headshots +80%", absf(hits()[0].dmg - 18.0) < 0.001)
	setup([Vector3(0, 0, -30)], {"sky_striker": 1, "momentum": 1})
	player.grounded = false
	player.vx = 19.0
	shoot(0, 10.0)
	check("Sky Striker + Momentum Engine: in the air at 19 m/s = +30%% +30%% (%.1f)" % hits()[0].dmg, absf(hits()[0].dmg - 16.0) < 0.001)
	setup([Vector3(0, 0, -30)], {"tracker_dart": 1})
	shoot(0, 10.0)
	shoot(0, 10.0)
	check("Tracker Dart: the second hit on a marked enemy +20%% (%.1f)" % hits()[1].dmg,
		absf(hits()[0].dmg - 10.0) < 0.001 and absf(hits()[1].dmg - 12.0) < 0.001)

	# ---- statuses ----
	setup([Vector3(0, 0, -30)], {"match_head": 10})
	shoot(0, 20.0)
	combat.fx.clear()
	run(3.2)
	var burn := hits("dot").filter(func(e: Dictionary) -> bool: return e.dot == "burn")
	var burned := 0.0
	for e: Dictionary in burn:
		burned += float(e.dmg)
	check("Match Head: sets them on fire for 3 s (%d ticks, %.0f damage), then it goes out" % [burn.size(), burned],
		burn.size() >= 5 and absf(burned - 30.0) < 1.5 and not dummy(0).status.has("burn"))
	setup([Vector3(0, 0, -30)], {"rusty_nail": 10})
	shoot(0, 5.0)
	shoot(0, 5.0)
	shoot(0, 5.0)
	combat.fx.clear()
	run(3.2)
	var bled := 0.0
	for e: Dictionary in hits("dot"):
		bled += float(e.dmg)
	check("Rusty Nail: 3 bleeds stack (%.0f damage over 3 s)" % bled, absf(bled - 3 * Upgrades.BLEED_DPS * Upgrades.BLEED_TIME) < 2.0)
	setup([Vector3(0, 0, -30)], {"sticky_bomb": 13})
	shoot(0, 10.0)
	var had_bomb: bool = dummy(0).status.has("bombs")
	combat.fx.clear()
	run(1.4)
	var booms := combat.fx.filter(func(e: Dictionary) -> bool: return e.type == "explosion" and e.kind == "bomb")
	check("Sticky Bomb: sticks, then blows up for 180%", had_bomb and booms.size() == 1 and hits("item").size() == 1
		and absf(float(hits("item")[0].dmg) - 18.0) < 2.0)

	# frost: chill slows an enemy, enough hits freeze it, frozen low ones shatter
	setup([], {"frost_tip": 1})
	var brute := enemies.spawn("brute", Vector3(0, 0, -20))
	combat.damage_target(brute.target, 1.0, "body", brute.center())
	check("Frost Tip: a hit chills (half speed)", Upgrades.time_scale(brute.target) == 0.5)
	for i in 5:
		combat.damage_target(brute.target, 1.0, "body", brute.center())
	check("...6 hits freeze it solid", Upgrades.time_scale(brute.target) == 0.0)
	var at := brute.target.pos
	run(1.0)
	check("...and a frozen enemy doesn't move", brute.target.pos.distance_to(at) < 0.05)
	combat.damage_target(brute.target, brute.target.hp - 90.0, "body", brute.center(), "item")
	run(0.05)
	check("...frozen below 25% health, it shatters", not brute.alive)

	# ---- spreading ----
	setup([Vector3(0, 0, -20), Vector3(3, 0, -20), Vector3(-3, 0, -20), Vector3(0, 0, -23)], {"static_coil": 1, "four_leaf": 25})
	shoot(0, 50.0)
	var zaps := combat.fx.filter(func(e: Dictionary) -> bool: return e.type == "zap")
	check("Static Coil: lightning arcs to 3 others for 60%% (%d zaps, %s)" % [zaps.size(), str(hits("item").map(func(e: Dictionary) -> int: return roundi(e.dmg)))],
		zaps.size() == 3 and hits("item").size() == 3 and hits("item").all(func(e: Dictionary) -> bool: return absf(e.dmg - 30.0) < 0.01))
	setup([Vector3(0, 0, -20), Vector3(2, 0, -20)], {"big_bang": 1})
	shoot(0, 50.0)
	check("Big Bang: the hit explodes, hurting the one next to it too", dummy(1).hp < Combat.DUMMY_HP and dummy(0).hp < Combat.DUMMY_HP - 50.0)
	setup([Vector3(0, 0, -20), Vector3(2, 0, -20)], {"party_popper": 1})
	shoot(0, 500.0)
	check("...(the kill doesn't pop on the same tick)", dummy(1).hp == Combat.DUMMY_HP)
	step()
	check("Party Popper: the dead one explodes next tick, hurting its neighbor", dummy(1).hp < Combat.DUMMY_HP)
	setup([Vector3(0, 0, -20), Vector3(8, 0, -26)], {"wisp_jar": 1})
	shoot(0, 500.0)
	step()
	var wisps := combat.projectiles.filter(func(pr: Combat.Projectile) -> bool: return pr.kind == "wisp").size()
	run(3.0)
	check("Wisp Jar: a kill lets out 2 wisps (%d) that hunt down the next enemy (%.0f damage)" % [wisps, Combat.DUMMY_HP - dummy(1).hp],
		wisps == 2 and absf(dummy(1).hp - (Combat.DUMMY_HP - 80.0)) < 0.01)
	setup([Vector3(6, 0, -9)], {"ricochet": 4})
	combat.set_loadout({"primary": "sniper", "secondary": "pistol", "ability": "knife"})
	var aim := Cmd.new()
	aim.fire = true
	aim.fire_pressed = true
	aim.yaw = 0.3 # at the wall, well left of the dummy
	step(aim)
	check("Ricochet: a bullet into the wall bounces into the dummy", dummy(0).hp < Combat.DUMMY_HP
		and combat.fx.any(func(e: Dictionary) -> bool: return e.type == "zap"))

	# ---- on kill ----
	setup([Vector3(0, 0, -20)], {"speed_loader": 1, "recharger": 2, "adrenaline": 1})
	combat.state.primary.ammo = 1
	combat.ability_cd = 5.0
	shoot(0, 500.0)
	step()
	check("Speed Loader: a kill refills your gun", combat.state.primary.ammo == combat.mag_size("primary"))
	check("Recharger x2: a kill takes 2 s off your ability (%.2f left)" % combat.ability_cd, absf(combat.ability_cd - (5.0 - 2.0 - 2 * Cfg.TICK_DT)) < 0.02)
	check("Adrenaline: a kill makes you 30% faster for a bit", absf(player.speed_mult - 1.3) < 0.001)
	run(2.1)
	check("...and it wears off", absf(player.speed_mult - 1.0) < 0.001)

	# ---- defense ----
	setup([], {"tough_skin": 2, "vampire_fangs": 1})
	check("Tough Skin x2: 150 max health, topped up", player.max_hp == 150.0 and player.hp == 150.0)
	combat.targets.append(enemies.spawn("brute", Vector3(0, 0, -20)).target)
	player.hp = 50.0
	combat.damage_target(enemies.list[0].target, 5.0, "body", Vector3.ZERO)
	check("Vampire Fangs: a hit heals 2", player.hp == 52.0)
	setup([], {"bubble_wrap": 200})
	var hurt_before := player.hp
	for i in 20:
		enemies.hurt_player(player, 10.0, Vector3.ZERO, "test")
	check("Bubble Wrap: blocks nearly everything with enough of it (took %.0f)" % (hurt_before - player.hp), hurt_before - player.hp <= 10.0)
	setup([], {"razor_wire": 1})
	var near := enemies.spawn("brute", Vector3(0, 0, -6))
	var far := enemies.spawn("brute", Vector3(0, 0, -40))
	enemies.hurt_player(player, 10.0, Vector3.ZERO, "test")
	check("Razor Wire: getting hurt lashes the one nearby (not the far one)", near.target.hp == 375.0 and far.target.hp == 400.0)

	# ---- movement ----
	setup([], {"running_shoes": 2})
	var run_cmd := Cmd.new()
	run_cmd.forward = 1.0
	run_cmd.sprint = true
	run_cmd.yaw = PI # away from the wall
	for i in 240:
		step(run_cmd)
	check("Running Shoes x2: sprint %.2f m/s (12.5 x 1.2)" % player.horizontal_speed(), absf(player.horizontal_speed() - 15.0) < 0.05)
	setup([], {"spring_heels": 1})
	var jump := Cmd.new()
	jump.jump = true
	jump.jump_held = true
	step(jump)
	for i in 40:
		step()
	var vy_before := player.vy
	step(jump)
	var vy_air := player.vy
	for i in 10:
		step()
	var vy_before2 := player.vy
	step(jump)
	check("Spring Heels: one jump in mid-air (%.1f -> %.1f m/s), not two" % [vy_before, vy_air], vy_air > 7.0 and vy_before < 0
		and player.vy < vy_before2)
	setup([], {"wall_grips": 2})
	check("Wall Grips x2: 6 wall jumps", player.extra_wall_jumps == 2)
	setup([Vector3(0, 0, -8)], {"slide_spikes": 1})
	var slide := Cmd.new()
	slide.forward = 1.0
	slide.sprint = true
	for i in 30:
		step(slide)
	slide.slide = true
	slide.slide_pressed = true
	slide.crouch = true
	step(slide)
	slide.slide_pressed = false
	for i in 60:
		step(slide)
	check("Slide Spikes: slide into it for 40", absf(dummy(0).hp - (Combat.DUMMY_HP - 40.0)) < 0.01)
	setup([Vector3(2, 0, 0)], {"stomp_boots": 1})
	player.respawn(0, 25, 0)
	run(2.0)
	check("Stomp Boots: landing from 25 m slams the dummy next to you (%.0f damage)" % (Combat.DUMMY_HP - dummy(0).hp), dummy(0).hp < Combat.DUMMY_HP - 50.0)
	setup([], {"knockout_glove": 3})
	var kb := enemies.spawn("gunner", Vector3(0, 0, 6)) # south, away from the wall
	enemies.frozen = true # stands still, so only the shove moves it
	run(0.3)
	var z0 := kb.target.pos.z
	combat.damage_target(kb.target, 1.0, "body", kb.center())
	run(0.4)
	check("Knockout Glove: hits shove them back (%.1f m)" % (kb.target.pos.z - z0), kb.target.pos.z - z0 > 1.0)

	# ---- legendaries ----
	var legends: Array = Upgrades.LIST.keys().filter(func(k: String) -> bool: return Upgrades.LIST[k].rarity == "legendary")
	check("6 legendaries (%s)" % ", ".join(legends), legends.size() == 6)
	setup([Vector3(0, 0, 8)], {"drone_buddy": 1}) # (south: the test wall is north)
	run(1.0)
	check("Drone Buddy: orbits you and shoots (%.0f damage in 1 s)" % (Combat.DUMMY_HP - dummy(0).hp),
		combat.up.drones.size() == 1 and absf((Combat.DUMMY_HP - dummy(0).hp) - 48.0) <= 12.0)
	setup([], {"orbital_strike": 1})
	var tough := enemies.spawn("brute", Vector3(0, 0, -20))
	var weak := enemies.spawn("swarmer", Vector3(8, 0, -20))
	enemies.frozen = true
	run(6.1)
	check("Orbital Strike: the toughest enemy near you gets 250 from the sky (brute %.0f / 400, swarmer untouched)" % tough.target.hp,
		tough.target.hp <= 400.0 - 250.0 and weak.target.hp == weak.target.max_hp)
	setup([Vector3(0, 0, 12)], {"hydra": 1})
	for i in Upgrades.HYDRA_EVERY:
		combat.up.on_fire(Vector3(0, 1.6, 0), Vector3(0, 0, 1))
	var missiles := combat.projectiles.filter(func(pr: Combat.Projectile) -> bool: return pr.kind == "missile").size()
	run(2.0)
	check("Hydra Launcher: every 5th shot launches 4 missiles (%d) that home in (%.0f damage)" % [missiles, Combat.DUMMY_HP - dummy(0).hp],
		missiles == 4 and dummy(0).hp < Combat.DUMMY_HP - 60.0)
	setup([], {"singularity": 1, "four_leaf": 30})
	var pulled := enemies.spawn("gunner", Vector3(6, 0, -20))
	var center := enemies.spawn("brute", Vector3(0, 0, -20))
	enemies.frozen = true
	combat.damage_target(center.target, 1.0, "body", center.center())
	var hole_at: Vector3 = combat.up.holes[0].pos if not combat.up.holes.is_empty() else Vector3.ZERO
	var d0 := Vector2(pulled.target.pos.x - hole_at.x, pulled.target.pos.z - hole_at.z).length()
	run(1.0)
	var d1 := Vector2(pulled.target.pos.x - hole_at.x, pulled.target.pos.z - hole_at.z).length()
	run(2.0)
	check("Singularity: a black hole drags them in (%.1f -> %.1f m), grinds and implodes (brute %.0f / 400)" % [d0, d1, center.target.hp],
		d1 < d0 - 1.0 and center.target.hp < 400.0 - 120.0 and combat.up.holes.is_empty())
	setup([], {"phoenix": 1})
	enemies.hurt_player(player, 500.0, Vector3.ZERO, "test")
	check("Phoenix Feather: a killing blow leaves you at half health, and the feather's gone",
		not player.dead and player.hp == player.max_hp * 0.5 and player.invuln > 0 and combat.up.count("phoenix") == 0)
	player.invuln = 0.0
	enemies.hurt_player(player, 500.0, Vector3.ZERO, "test")
	check("...once", player.dead)
	setup([Vector3(0, 0, -30)], {"glass_cannon": 1})
	shoot(0, 10.0)
	check("Glass Cannon: double damage (%.0f), half health (%.0f)" % [hits()[0].dmg, player.max_hp], absf(hits()[0].dmg - 20.0) < 0.001 and player.max_hp == 50.0)

	# ---- levels ----
	setup([Vector3(0, 0, -30)])
	player.hp = 40.0
	combat.up.add_xp(Upgrades.xp_to_next(1) - 1.0, player)
	check("not quite enough XP: still level 1", combat.up.level == 1 and player.hp == 40.0)
	combat.up.add_xp(1.0, player)
	check("level 2: +%.0f max health and a full heal (%.0f / %.0f)" % [Upgrades.LEVEL_HEALTH, player.hp, player.max_hp],
		combat.up.level == 2 and player.max_hp == 100.0 + Upgrades.LEVEL_HEALTH and player.hp == player.max_hp
		and combat.fx.any(func(e: Dictionary) -> bool: return e.type == "level_up"))
	shoot(0, 10.0)
	check("...and +10%% damage (%.1f)" % hits()[0].dmg, absf(hits()[0].dmg - 11.0) < 0.001)
	combat.up.add_xp(Upgrades.xp_to_next(2) + Upgrades.xp_to_next(3) + 0.5, player)
	check("a big XP gain can go up several levels (level %d)" % combat.up.level, combat.up.level == 4)
	check("each level needs more XP (%.0f, %.0f, %.0f)" % [Upgrades.xp_to_next(1), Upgrades.xp_to_next(2), Upgrades.xp_to_next(5)],
		Upgrades.xp_to_next(2) > Upgrades.xp_to_next(1) and Upgrades.xp_to_next(5) > 2.0 * Upgrades.xp_to_next(1))

	print("\n%s" % ("all item checks passed" if fails == 0 else "%d item check(s) failed" % fails))
	quit(1 if fails else 0)


## Fire a rocket at your feet with these items; returns your upward speed right after.
func rocket_jump(items: Dictionary) -> float:
	setup([], items)
	combat.set_loadout({"primary": "rocket", "secondary": "pistol", "ability": "knife"})
	var c := Cmd.new()
	c.fire = true
	c.fire_pressed = true
	c.pitch = -PI / 2 + 0.05
	var best := 0.0
	for i in 20:
		step(c)
		c.fire_pressed = false
		best = maxf(best, player.vy)
	return best
