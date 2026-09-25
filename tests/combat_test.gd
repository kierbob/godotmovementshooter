extends SceneTree
## Checks the guns headless: firing, fire rate, reloads, switching, hits on the bean dummies,
## knockback (shotgun boost, rocket jump) and abilities. Runs Combat + PlayerSim tick by tick on
## the dev map, the way main.gd does.
##   godot --headless --path . --script res://tests/combat_test.gd

const DIST := 8.0 # the player stands at z -7, a dummy stands at (0, 0, -15)

var fails := 0
var map: MapData
var player: PlayerSim
var combat: Combat


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


## Fresh player standing at (x, 0, z) and a fresh combat with this loadout.
func setup(lo: Dictionary, x := 0.0, z := -7.0) -> void:
	player = PlayerSim.new(x, 0.0, z)
	combat = Combat.new(map.boxes, map.targets)
	combat.set_loadout(lo)
	# Let the player settle onto the floor.
	for i in 5:
		player.step(Cmd.new(), map, Cfg.TICK_DT)


func cmd(yaw := 0.0, pitch := 0.0) -> Cmd:
	var c := Cmd.new()
	c.yaw = yaw
	c.pitch = pitch
	return c


## One sim tick, combat first (same order as main.gd).
func tick(c: Cmd) -> void:
	combat.tick(player, c, Cfg.TICK_DT)
	player.step(c, map, Cfg.TICK_DT)


func ticks(n: int, c: Cmd) -> void:
	for i in n:
		tick(c)


func count(type: String) -> int:
	return combat.fx.filter(func(e: Dictionary) -> bool: return e.type == type).size()


## Pitch from the eye to height y on a dummy dist meters straight ahead.
func pitch_to(y: float, dist: float) -> float:
	return atan2(y - Cfg.PLAYER_EYE_HEIGHT, dist)


func _init() -> void:
	seed(1) # spread is random; keep runs repeatable
	map = MapData.load_file("res://tests/maps/dev_map.json")
	var shotgun := {"primary": "shotgun", "secondary": "pistol", "ability": "frag"}

	# ---- firing, fire rate, ammo ----
	setup(shotgun)
	check("default loadout is Boomstick / Sidearm / Impact Grenade",
		combat.slots.primary.id == "shotgun" and combat.slots.secondary.id == "pistol" and combat.ability.id == "frag")
	var hold := cmd(PI) # facing away from the dummies
	hold.fire = true
	ticks(10, hold)
	check("holding fire doesn't shoot a semi-auto gun", combat.state.primary.ammo == 4 and count("shot") == 0)
	var click := cmd(PI)
	click.fire = true
	click.fire_pressed = true
	tick(click)
	check("a click fires once", combat.state.primary.ammo == 3 and count("shot") == 1)
	tick(click)
	ticks(20, hold)
	check("can't fire again before 1/fire_rate", combat.state.primary.ammo == 3)
	ticks(int(Cfg.TICK_RATE / 1.3) - 10, cmd(PI))
	tick(click)
	check("fires again once the gun is ready", combat.state.primary.ammo == 2)

	# ---- reload ----
	var r := cmd(PI)
	r.reload = true
	tick(r)
	check("R starts a reload", combat.state.primary.reload_t > 0 and count("reload") == 1)
	ticks(int(1.5 * Cfg.TICK_RATE) + 2, cmd(PI))
	check("reload refills the magazine after 1.5 s", combat.state.primary.ammo == 4 and combat.state.primary.reload_t == 0)
	for i in 4:
		tick(click)
		ticks(int(Cfg.TICK_RATE / 1.3) + 1, cmd(PI))
	check("emptying the magazine reloads by itself", combat.state.primary.reload_t > 0 or combat.state.primary.ammo == 4)

	# ---- switching ----
	setup(shotgun)
	var sw := cmd(PI)
	sw.slot = "secondary"
	tick(sw)
	check("2 switches to the secondary", combat.active == "secondary" and combat.draw_t > 0)
	var pclick := cmd(PI)
	pclick.fire_pressed = true
	tick(pclick)
	check("can't fire while drawing", combat.state.secondary.ammo == 12)
	ticks(int((Combat.SWITCH_TIME - 0.1) * Cfg.TICK_RATE), cmd(PI))
	tick(pclick)
	ticks(int(0.1 * Cfg.TICK_RATE), cmd(PI))
	check("a click just before the draw ends still fires (0.12 s buffer)", combat.state.secondary.ammo == 11)
	var wheel := cmd(PI)
	wheel.cycle = 1
	tick(wheel)
	check("mouse wheel cycles back to the primary", combat.active == "primary")

	# ---- hits on the dummies ----
	setup({"primary": "sniper", "secondary": "pistol", "ability": "knife"})
	var dummy: Combat.Target = combat.targets[0]
	var body := cmd(0.0, pitch_to(0.72, DIST))
	body.slot = "secondary"
	tick(body)
	ticks(int(Combat.SWITCH_TIME * Cfg.TICK_RATE) + 1, cmd())
	body.slot = ""
	body.fire_pressed = true
	tick(body)
	var pd: float = Items.WEAPONS.pistol.damage
	check("pistol body shot: %d damage" % pd, is_equal_approx(dummy.hp, Combat.DUMMY_HP - pd) and count("hit") == 1)
	ticks(int(Cfg.TICK_RATE / 6.0) + 1, cmd())
	var head := cmd(0.0, pitch_to(1.73, DIST))
	head.fire_pressed = true
	tick(head)
	check("pistol headshot: %d damage (2x)" % (pd * 2), is_equal_approx(dummy.hp, Combat.DUMMY_HP - pd * 3))
	var hits := combat.fx.filter(func(e: Dictionary) -> bool: return e.type == "hit")
	check("headshot is reported as a head hit", hits.size() == 2 and hits[1].zone == "head")

	var knife := cmd(0.0, pitch_to(0.72, DIST))
	knife.ability = true
	ticks(20, knife)
	check("throwing knife kills the dummy (200 damage)",
		dummy.dead and combat.fx.any(func(e: Dictionary) -> bool: return e.type == "hit" and e.kill))
	check("ability goes on cooldown (4 s knife)", combat.ability_cd > 3.5 and combat.projectiles.size() == 0)
	ticks(int(Combat.DUMMY_RESPAWN * Cfg.TICK_RATE) + 2, cmd())
	check("dummy respawns with full health", not dummy.dead and dummy.hp == Combat.DUMMY_HP)

	# ---- knockback ----
	setup(shotgun)
	var down := cmd(0.0, -PI / 2 + 0.001)
	down.fire_pressed = true
	tick(down)
	check("shotgun at the floor launches you (16 m/s up)", player.vy > 14 and not player.grounded)

	setup(shotgun)
	var fwd := cmd(0.0, 0.0)
	fwd.fire_pressed = true
	tick(fwd)
	check("shotgun pushes you backwards", player.vz > 10)

	setup({"primary": "rocket", "secondary": "pistol", "ability": "impulse"})
	var rj := cmd(0.0, -PI / 2 + 0.001)
	rj.fire_pressed = true
	var max_vy := 0.0
	for i in 20:
		tick(rj)
		rj.fire_pressed = false
		max_vy = maxf(max_vy, player.vy)
	check("rocket at your feet explodes and rocket-jumps you", count("explosion") == 1 and max_vy > 10)

	setup({"primary": "rocket", "secondary": "pistol", "ability": "frag"})
	var nade := cmd(0.0, pitch_to(0.5, DIST))
	nade.ability = true
	for i in 120:
		tick(nade)
		nade.ability = false
	dummy = combat.targets[0]
	check("impact grenade explodes on the dummy and hurts it", count("explosion") == 1 and dummy.hp < Combat.DUMMY_HP)
	var again := cmd()
	again.ability = true
	tick(again)
	check("can't throw again while recharging", combat.projectiles.size() == 0)

	# ---- Combat Dash (the Commando): a burst where you look, then a cooldown ----
	setup(Characters.loadout("commando"))
	check("the Commando carries the Pulse Rifle, the Deagle and the Dash", combat.slots.primary.id == "rifle"
		and combat.slots.secondary.id == "deagle" and combat.ability.id == "dash")
	var dash := cmd(PI / 2) # facing -x
	dash.ability = true
	tick(dash)
	check("dashing: %.1f m/s toward where you look, a little hop, no projectile" % player.horizontal_speed(),
		player.vx < -21.0 and absf(player.vz) < 0.01 and player.vy > 0.0 and combat.projectiles.is_empty() and count("dash") == 1)
	ticks(30, cmd(PI / 2))
	var fast := player.horizontal_speed()
	var dash2 := cmd(PI / 2)
	dash2.ability = true
	tick(dash2)
	check("can't dash again while it recharges (%.1f s)" % combat.ability_cd, combat.ability_cd > 3.0 and player.horizontal_speed() <= fast + 0.1)

	# ---- ramps (Bean Street): rays hit the sloped top, not the bounding box ----
	var street := MapData.load_file("res://tests/maps/bean-street.json")
	var walls := Combat.new(street.boxes, [])
	var ramps := 0
	var on_slope := 0
	for b in street.boxes:
		if b.ramp_axis < 0:
			continue
		ramps += 1
		var cx := (b.min_x + b.max_x) / 2
		var cz := (b.min_z + b.max_z) / 2
		var surface := MapData.ramp_height_at(b, cx if b.ramp_axis == 0 else cz)
		var h := walls.raycast(Vector3(cx, b.max_y + 0.5, cz), Vector3.DOWN, 20, 0, false)
		if h and absf(h.point.y - surface) < 0.01 and h.normal.y < 1.0 and h.normal.y > 0.5:
			on_slope += 1
	check("shots straight down hit each ramp's slope (%d/%d)" % [on_slope, ramps], ramps > 0 and on_slope == ramps)

	print("\n%s" % ("all combat checks passed" if fails == 0 else "%d combat checks FAILED" % fails))
	quit(1 if fails > 0 else 0)
