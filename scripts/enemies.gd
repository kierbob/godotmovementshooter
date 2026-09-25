class_name Enemies
extends RefCounted
## The enemies: three families with three variants each, run inside the fixed sim tick (after the
## player's guns, like the web game's bots). Pure logic; EnemyView draws them from `list`,
## `projectiles` and the `events` queue.
##
##   Runners (melee):  Charger (winds up, then dashes), Brute (slow tank, ground slam you jump
##                     over), Swarmer (small, fast, weak, comes in packs)
##   Shooters:         Gunner (slow bursts), Lobber (arcing grenades with a landing marker),
##                     Sniper (a laser that tracks you, locks, then fires)
##   Boss:             Colossus (a giant: shockwave slams you jump, fans of slow orbs, calls in
##                     swarmers; each with a long windup)
##   Flyers:           Projectile (dodgeable orbs), Beam (Moira-style lock-on that breaks at range
##                     or behind cover), Healer (heals the enemies that fight, never another healer,
##                     never hurts you)
##
## Fair-play rules every attack follows (checked by tests/enemy_test.gd):
##   - a visible, audible windup of at least 0.25 s before anything can hurt you
##   - no attack without line of sight (nothing shoots through walls, beams break behind cover)
##   - projectiles are slow enough to dodge and aimed where you ARE, never led
##   - the sniper's aim locks before it fires, so moving after the lock dodges it
##
## Ground enemies move with PlayerSim (the same collision, ramps and jump pads as you); flyers
## steer freely and get pushed out of walls.

## Enemies think and move 60 times a second (every other tick, half of them on each), or 30 once
## they're LOD_FAR from you: the sim runs at 120 and moving a ground enemy costs as much as moving
## you, so a crowd ticked every tick eats the frame. Their timings are in seconds, so nothing gets
## faster or slower; their shots still fly every tick.
const LOD_FAR := 40.0
const SEP_RADIUS := 0.42 # enemies keep this x (their sizes added) apart: a bean's width
const SEP_CELL := 2.0
const SEP_MAX_STEP := 0.12 # most a push moves one in a tick
const REGEN_DELAY := 3.0 # the player heals this long after the last hit (same as online)
const REGEN_RATE := 30.0

## Every type. family groups them for the console ("spawn flyer"); hp, size (hitbox scale),
## color; move = how ground types walk ("walk" | "sprint" | "crouch"), max_speed = a cap on their
## own running speed (PlayerSim only walks at 9 or sprints at 12.5), speed = flyer top speed.
const TYPES := {
	"charger": {"family": "runner", "name": "Charger", "hp": 120.0, "size": 1.0, "color": Color("ff7a45"), "move": "walk"},
	"brute": {"family": "runner", "name": "Brute", "hp": 400.0, "size": 1.4, "color": Color("8a5cff"), "move": "crouch"},
	"swarmer": {"family": "runner", "name": "Swarmer", "hp": 30.0, "size": 0.6, "color": Color("8fe36b"), "move": "walk", "max_speed": 6.0},
	"gunner": {"family": "shooter", "name": "Gunner", "hp": 90.0, "size": 1.0, "color": Color("4fb3ff"), "move": "walk", "range": 14.0},
	"lobber": {"family": "shooter", "name": "Lobber", "hp": 100.0, "size": 1.0, "color": Color("ffb13d"), "move": "walk", "range": 16.0},
	"sniper": {"family": "shooter", "name": "Sniper", "hp": 80.0, "size": 1.0, "color": Color("e8e8f0"), "move": "walk", "range": 28.0},
	"flyer_projectile": {"family": "flyer", "name": "Projectile Flyer", "hp": 70.0, "size": 0.8, "color": Color("ffd84a"), "speed": 7.0, "range": 14.0},
	"flyer_beam": {"family": "flyer", "name": "Beam Flyer", "hp": 90.0, "size": 0.8, "color": Color("d65cff"), "speed": 9.0, "range": 8.0},
	"flyer_healer": {"family": "flyer", "name": "Healer Flyer", "hp": 110.0, "size": 0.8, "color": Color("5ee0a0"), "speed": 8.0, "range": 6.0},
	"colossus": {"family": "boss", "name": "Colossus", "hp": 2500.0, "size": 2.6, "color": Color("c0392b"), "move": "crouch"},
}
const FAMILIES := {
	"runner": ["charger", "brute", "swarmer"],
	"shooter": ["gunner", "lobber", "sniper"],
	"flyer": ["flyer_projectile", "flyer_beam", "flyer_healer"],
	"boss": ["colossus"],
}

# Attack numbers (seconds, meters, damage).
const CHARGER := {"reach": 9.0, "windup": 0.65, "dash_speed": 24.0, "dash_time": 0.35, "damage": 20.0, "recover": 0.5, "cooldown": 1.8}
const SWARMER := {"reach": 1.6, "windup": 0.25, "bite_reach": 2.1, "damage": 7.0, "cooldown": 0.8}
const BRUTE := {"reach": 6.0, "windup": 1.1, "wave_speed": 12.0, "wave_radius": 10.0, "wave_band": 0.9, "damage": 30.0, "cooldown": 3.0}
const GUNNER := {"reach": 30.0, "windup": 0.5, "shots": 3, "gap": 0.18, "speed": 20.0, "damage": 7.0, "cooldown": 2.2}
const LOBBER := {"reach": 32.0, "windup": 0.6, "gravity": 20.0, "radius": 3.2, "damage": 22.0, "cooldown": 3.0}
const SNIPER := {"reach": 60.0, "aim": 1.5, "lock": 0.4, "damage": 35.0, "cooldown": 4.0}
const FLYER_ORB := {"reach": 35.0, "windup": 0.35, "speed": 22.0, "damage": 10.0, "cooldown": 1.8}
const FLYER_BEAM := {"reach": 13.0, "break": 15.0, "windup": 0.6, "dps": 13.0, "max": 3.0, "cooldown": 3.0}
const HEALER := {"reach": 25.0, "hps": 30.0}
## The boss. Every third attack calls in swarmers; otherwise a slam when you're close (a big, fast
## shockwave: jump it) or a fan of slow orbs aimed where you are.
const COLOSSUS := {"slam_reach": 16.0, "slam_windup": 1.2, "wave_speed": 15.0, "wave_radius": 24.0, "wave_band": 1.1,
	"slam_damage": 35.0, "volley_windup": 0.8, "orbs": 7, "spread": 0.9, "orb_speed": 17.0, "orb_damage": 12.0,
	"summon_windup": 1.0, "summon": 4, "cooldown": 2.2, "recover": 0.8}
const FLY_MIN := 2.5 # flyers stay this far above the ground...
const FLY_MAX := 8.0 # ...and at most this far above it (or above you, if you're up high)


class Enemy:
	var id := 0
	var type := ""
	var def := {}
	var target: Combat.Target # its hitboxes (the player's guns hit this)
	var body: PlayerSim # ground types
	var pos := Vector3.ZERO # flyers (ground types use body)
	var vel := Vector3.ZERO # flyers
	var yaw := 0.0 # facing (camera convention: 0 looks down -Z)
	var state := "move" # move | windup | attack | aim | lock | recover
	var t := 0.0 # time in the current state
	var cd := 0.0 # attack cooldown
	var aim := Vector3.ZERO # locked aim point / direction
	var shots_left := 0
	var hit_done := false # this attack already hurt the player
	var los := false
	var los_t := 0.0 # time until the next line-of-sight check
	var stuck_t := 0.0
	var strafe_t := 0.0
	var strafe_dir := 1.0
	var heal_target: Enemy = null
	var wave_r := -1.0 # brute shockwave radius (-1 = none)
	var wave_at := Vector3.ZERO
	var attack := "" # the boss's attack being wound up
	var attacks := 0 # how many it has started (every third is a summon)
	var hp_mult := 1.0 # how much tougher than the base type (later waves, later stages)
	var beam_acc := 0.0 # beam damage built up, dealt in small chunks (one hurt flash, not 120 a second)
	var alive := true
	var acc := 0.0 # sim time since it last thought (see LOD_FAR)
	var ground_y := 0.0 # flyers: the ground under where they're heading (refreshed every GROUND_EVERY)
	var ground_t := 0.0
	var heal_los_t := 0.0 # healers: time until the next line-of-sight check on their patient

	func center() -> Vector3:
		return target.pos + Vector3(0, 1.0 * target.size, 0)


var map: MapData
var combat: Combat
var list: Array[Enemy] = []
var projectiles: Array[Dictionary] = [] # {id, pos, vel, radius, damage, kind, gravity, splash, owner, alive}
var events: Array[Dictionary] = [] # for the view and sounds; main clears it every frame
var deaths: Array[Dictionary] = [] # this tick's kills {type, pos} (Loot pays gold for them)
var god := false # admin: the player can't be hurt
var damage_mult := 1.0 # everything hurts this much more (the wave director turns it up)
var frozen := false # admin: enemies stand still and don't attack
var time := 0.0
var player_center := Vector3.ZERO # where the player was this tick (the view aims beams at it)
var _next_id := 10000
var _next_shot := 1 # enemy projectile ids (the view keys its meshes on these: a Dictionary changes as it flies)
var _rng := RandomNumberGenerator.new()


func _init(m: MapData, c: Combat) -> void:
	map = m
	combat = c
	if combat.grid == null and combat.boxes == m.boxes:
		combat.grid = m
	_rng.seed = 7


## Spawn one. pos is the feet for ground types, the body center for flyers.
## hp_mult: tougher than the type's base health (the wave director scales it up).
func spawn(type: String, pos: Vector3, hp_mult := 1.0) -> Enemy:
	var e := Enemy.new()
	e.hp_mult = hp_mult
	e.id = _next_id
	_next_id += 1
	e.type = type
	e.def = TYPES[type]
	e.target = Combat.Target.new()
	e.target.id = e.id
	e.target.kind = "enemy"
	e.target.name = e.def.name
	e.target.size = e.def.size
	e.target.hp = e.def.hp * hp_mult
	e.target.max_hp = e.def.hp * hp_mult
	e.cd = 1.0 # a moment to get their bearings: nothing attacks the instant it appears
	if e.def.family == "flyer":
		e.pos = pos
		e.target.pos = pos - Vector3(0, 1.0 * e.target.size, 0)
	else:
		e.body = PlayerSim.new(pos.x, pos.y, pos.z)
		e.body.quiet = true
		e.target.body = e.body # explosions launch them
		e.target.pos = pos
	e.strafe_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	e.acc = (e.id % 4) * Cfg.TICK_DT # spread them out, so each tick moves a share of the crowd
	list.append(e)
	combat.targets.append(e.target)
	events.append({"type": "spawn", "id": e.id, "enemy": type})
	return e


func clear() -> void:
	for e in list:
		combat.targets.erase(e.target)
	list.clear()
	projectiles.clear()


## One sim tick (after the player's guns and movement).
func tick(p: PlayerSim, dt: float) -> void:
	time += dt
	player_center = _player_center(p)
	deaths.clear()
	for e in list:
		if e.target.dead or e.target.hp <= 0:
			e.alive = false
			events.append({"type": "died", "id": e.id, "enemy": e.type, "pos": e.center()})
			deaths.append({"type": e.type, "pos": e.center()})
			continue
		if e.body and e.body.py < -30:
			e.alive = false # fell out of the world
			continue
		if e.target.knock != Vector3.ZERO: # an item shoved it (ground types get it through their body)
			e.vel += e.target.knock
			e.target.knock = Vector3.ZERO
		e.acc += dt
		var every := 4 if e.center().distance_squared_to(player_center) > LOD_FAR * LOD_FAR else 2
		if e.acc < every * dt - 1e-6:
			continue
		var step := e.acc
		e.acc = 0.0
		# Items slow time for it: chilled runs at half speed, frozen stops (and loses its attack).
		var edt := step * Upgrades.time_scale(e.target)
		if frozen or edt == 0.0:
			if edt == 0.0 and e.state != "move":
				_enter(e, "move")
				e.cd = maxf(e.cd, 0.5)
			_hold(e, step)
			continue
		e.cd = maxf(0.0, e.cd - edt)
		e.t += edt
		e.los_t -= edt
		if e.los_t <= 0:
			e.los_t = 0.2
			e.los = _can_see(_eye(e), _player_center(p))
		if e.def.family == "flyer":
			_tick_flyer(e, p, edt)
		else:
			_tick_ground(e, p, edt)
		if e.wave_r >= 0:
			_tick_wave(e, p, edt)
	var alive: Array[Enemy] = []
	for e in list:
		if e.alive:
			alive.append(e)
		else:
			combat.targets.erase(e.target)
	list = alive
	if not frozen:
		_separate()
	_tick_projectiles(p, dt)


## Enemies are solid to each other: any two standing inside one another get pushed apart (half
## each), so a crowd spreads out instead of stacking into one bean. Ground ones move through their
## body (walls still stop them), flyers get pushed out of walls afterwards. A 2 m grid keeps it
## cheap in a big crowd.
func _separate() -> void:
	if list.size() < 2:
		return
	var cells := {}
	for e in list:
		var c := e.target.pos
		var k := Vector2i(floori(c.x / SEP_CELL), floori(c.z / SEP_CELL))
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(e)
	var push := {} # enemy -> Vector3 (horizontal)
	for e in list:
		var a := e.target.pos
		var k := Vector2i(floori(a.x / SEP_CELL), floori(a.z / SEP_CELL))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for o: Enemy in cells.get(k + Vector2i(dx, dz), []):
					if o.id <= e.id:
						continue
					var b := o.target.pos
					if absf(a.y - b.y) > 1.6 * maxf(e.target.size, o.target.size):
						continue # one's on a ledge above the other
					var off := Vector3(a.x - b.x, 0, a.z - b.z)
					var d := off.length()
					var min_d := SEP_RADIUS * (e.target.size + o.target.size)
					if d >= min_d:
						continue
					var dir := off / d if d > 1e-4 else Vector3(cos(e.id), 0, sin(e.id)) # exactly on top: any way out
					var half := dir * (min_d - d) * 0.5
					push[e] = push.get(e, Vector3.ZERO) + half
					push[o] = push.get(o, Vector3.ZERO) - half
	for e: Enemy in push:
		var v: Vector3 = push[e]
		if v.length() > SEP_MAX_STEP:
			v = v.normalized() * SEP_MAX_STEP # a few ticks to untangle a pile, not a teleport
		if e.body:
			var boxes := map.nearby(e.body.px, e.body.py, e.body.pz, 1.0)
			e.body._move_axis(0, v.x, boxes)
			e.body._move_axis(2, v.z, boxes)
			e.target.pos = Vector3(e.body.px, e.body.py, e.body.pz)
		else:
			e.pos = _push_out(e.pos + v, 0.6 * e.target.size)
			e.target.pos = e.pos - Vector3(0, 1.0 * e.target.size, 0)


## The player takes a hit (from an enemy at `from`).
func hurt_player(p: PlayerSim, dmg: float, from: Vector3, by: String) -> void:
	if god or p.dead or p.invuln > 0:
		return
	dmg *= damage_mult
	dmg = combat.up.on_hurt(p, dmg) # Bubble Wrap may block it, Razor Wire lashes back
	if dmg <= 0:
		events.append({"type": "blocked", "from": from})
		return
	p.hp = maxf(0.0, p.hp - dmg)
	p.regen_delay = REGEN_DELAY
	events.append({"type": "hurt", "dmg": dmg, "from": from, "by": by})
	if p.hp <= 0:
		p.dead = true
		events.append({"type": "player_died", "by": by})


# ---------- ground types ----------

func _tick_ground(e: Enemy, p: PlayerSim, dt: float) -> void:
	var me := Vector3(e.body.px, e.body.py, e.body.pz)
	var to := Vector3(p.px, p.py, p.pz) - me
	var flat := Vector2(to.x, to.z)
	var dist := flat.length()
	var face := atan2(-to.x, -to.z)
	var c := Cmd.new()
	c.yaw = face
	var move := true
	match e.type:
		"charger":
			move = _charger(e, p, dist, dt)
			if move and dist < 5.0 and e.cd > 0:
				# Waiting on its cooldown: circle at a distance instead of walking into you, so
				# the next charge always comes from far enough away to side-step.
				c.right = e.strafe_dir
				c.forward = -0.5 if dist < 3.5 else 0.0
				move = false
				_apply_stuck(e, c, dt)
		"swarmer":
			move = _swarmer(e, p, dist) and dist > 1.0 # stop at your feet instead of running through you
		"brute":
			move = _brute(e, p, dist)
		"colossus":
			move = _colossus(e, p, dist) and dist > 4.0 # lumbers at you, but not into you
		_:
			move = _shooter(e, p, dist, dt)
			# Keep their distance: back off when you're close, strafe when in range.
			var want: float = e.def.range
			if move:
				if dist < want - 3:
					c.forward = -1.0
				elif dist > want + 3 or not e.los:
					c.forward = 1.0
				else:
					c.right = e.strafe_dir
				move = false # already chose the direction
				_apply_stuck(e, c, dt)
	if move and not p.dead:
		c.forward = 1.0
		_apply_stuck(e, c, dt)
	if e.state == "move":
		e.yaw = face
	c.yaw = e.yaw if e.state != "move" else face
	match e.def.move:
		"sprint":
			c.sprint = c.forward > 0
		"crouch":
			c.crouch = true
	if e.type == "charger" and e.state == "attack":
		# The dash: straight along the locked direction, ignoring steering.
		c = Cmd.new()
		c.yaw = e.yaw
		e.body.vx = e.aim.x * CHARGER.dash_speed
		e.body.vz = e.aim.z * CHARGER.dash_speed
	e.body.step(c, map, dt)
	# Slower than a walking player: cap their own running (not knockback: rockets still launch them).
	var cap: float = e.def.get("max_speed", 0.0)
	if cap > 0 and e.body.grounded and e.body.friction_grace <= 0 and e.body.horizontal_speed() > cap:
		e.body._set_horizontal_speed(cap)
	e.target.pos = Vector3(e.body.px, e.body.py, e.body.pz)


## Walking into a wall: jump, and if that doesn't help, sidestep for a bit.
func _apply_stuck(e: Enemy, c: Cmd, dt: float) -> void:
	if e.strafe_t > 0:
		e.strafe_t -= dt
		c.forward = 0.0
		c.right = e.strafe_dir
		return
	if (c.forward != 0 or c.right != 0) and e.body.horizontal_speed() < 1.0:
		e.stuck_t += dt
		if e.stuck_t > 0.25 and e.body.grounded:
			c.jump = true
			c.jump_held = true
		if e.stuck_t > 1.2:
			e.stuck_t = 0.0
			e.strafe_t = 0.8
			e.strafe_dir = -e.strafe_dir
	else:
		e.stuck_t = 0.0


## Returns whether it should keep walking at you.
func _charger(e: Enemy, p: PlayerSim, dist: float, dt: float) -> bool:
	match e.state:
		"move":
			if dist < CHARGER.reach and e.los and e.cd <= 0 and not p.dead:
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": CHARGER.windup})
				return false
			return true
		"windup":
			if e.t >= CHARGER.windup:
				# Lock the direction now: side-step during the dash and it misses.
				var to := Vector3(p.px - e.body.px, 0, p.pz - e.body.pz)
				e.aim = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
				e.yaw = atan2(-e.aim.x, -e.aim.z)
				e.hit_done = false
				_enter(e, "attack")
				events.append({"type": "dash", "id": e.id})
			return false
		"attack":
			if not e.hit_done and _touching(e, p, 0.5):
				e.hit_done = true
				hurt_player(p, CHARGER.damage, e.center(), e.def.name)
				p.apply_impulse(e.aim.x * 9.0, 5.0, e.aim.z * 9.0, "charger")
			if e.t >= CHARGER.dash_time:
				_enter(e, "recover")
			return false
		"recover":
			if e.t >= CHARGER.recover:
				e.cd = CHARGER.cooldown
				_enter(e, "move")
			return false
	return true


func _swarmer(e: Enemy, p: PlayerSim, dist: float) -> bool:
	match e.state:
		"move":
			if dist < SWARMER.reach and e.los and e.cd <= 0 and not p.dead:
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": SWARMER.windup})
			return true # keeps scrambling at you while it winds up the bite
		"windup":
			if e.t >= SWARMER.windup:
				if dist < SWARMER.bite_reach and e.los:
					hurt_player(p, SWARMER.damage, e.center(), e.def.name)
					events.append({"type": "bite", "id": e.id})
				e.cd = SWARMER.cooldown
				_enter(e, "move")
			return true
	return true


func _brute(e: Enemy, p: PlayerSim, dist: float) -> bool:
	match e.state:
		"move":
			if dist < BRUTE.reach and e.los and e.cd <= 0 and not p.dead:
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": BRUTE.windup})
				return false
			return true
		"windup":
			if e.t >= BRUTE.windup:
				e.wave_r = 0.0
				e.wave_at = Vector3(e.body.px, e.body.py, e.body.pz)
				e.hit_done = false
				events.append({"type": "slam", "id": e.id, "pos": e.wave_at, "radius": BRUTE.wave_radius})
				e.cd = BRUTE.cooldown
				_enter(e, "recover")
			return false
		"recover":
			if e.t >= 0.6:
				_enter(e, "move")
			return false
	return true


func _colossus(e: Enemy, p: PlayerSim, dist: float) -> bool:
	match e.state:
		"move":
			if e.cd <= 0 and e.los and not p.dead:
				e.attacks += 1
				e.attack = "summon" if e.attacks % 3 == 0 else ("slam" if dist < COLOSSUS.slam_reach else "volley")
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": COLOSSUS[e.attack + "_windup"]})
			return true
		"windup":
			if e.t >= COLOSSUS[e.attack + "_windup"]:
				match e.attack:
					"slam":
						e.wave_r = 0.0
						e.wave_at = Vector3(e.body.px, e.body.py, e.body.pz)
						e.hit_done = false
						events.append({"type": "slam", "id": e.id, "pos": e.wave_at, "radius": COLOSSUS.wave_radius})
					"volley":
						# a flat fan, the middle orb aimed where you are right now
						var from := _eye(e)
						var to := _player_center(p)
						var d := to - from
						var n: int = COLOSSUS.orbs
						for i in n:
							var a: float = (float(i) / (n - 1) - 0.5) * COLOSSUS.spread
							_fire(e, from, from + d.rotated(Vector3.UP, a), COLOSSUS.orb_speed, COLOSSUS.orb_damage, 0.35, "orb")
					"summon":
						for i in COLOSSUS.summon:
							var a := TAU * i / float(COLOSSUS.summon)
							var at := Vector3(e.body.px + cos(a) * 3.0, e.body.py + 0.5, e.body.pz + sin(a) * 3.0)
							spawn("swarmer", at, e.hp_mult).cd = 1.0
						events.append({"type": "summon", "id": e.id, "pos": e.center()})
				e.cd = COLOSSUS.cooldown
				_enter(e, "recover")
			return false
		"recover":
			if e.t >= COLOSSUS.recover:
				_enter(e, "move")
			return false
	return true


## The shockwave rolls out along the ground: jump over it. (The brute's, or the boss's bigger one.)
func _tick_wave(e: Enemy, p: PlayerSim, dt: float) -> void:
	var boss := e.type == "colossus"
	e.wave_r += (COLOSSUS.wave_speed if boss else BRUTE.wave_speed) * dt
	if e.wave_r > (COLOSSUS.wave_radius if boss else BRUTE.wave_radius):
		e.wave_r = -1.0
		return
	if e.hit_done:
		return
	var d := Vector2(p.px - e.wave_at.x, p.pz - e.wave_at.z).length()
	var on_ground := p.grounded and absf(p.py - e.wave_at.y) < 0.6
	if on_ground and absf(d - e.wave_r) < (COLOSSUS.wave_band if boss else BRUTE.wave_band):
		e.hit_done = true
		hurt_player(p, COLOSSUS.slam_damage if boss else BRUTE.damage, e.wave_at, e.def.name)
		p.apply_impulse(0.0, 8.0, 0.0, "slam")


## Gunner / lobber / sniper. Returns whether it's free to walk (not busy shooting).
func _shooter(e: Enemy, p: PlayerSim, dist: float, dt: float) -> bool:
	var eye := _eye(e)
	match e.type:
		"gunner":
			match e.state:
				"move":
					if e.los and dist < GUNNER.reach and e.cd <= 0 and not p.dead:
						_enter(e, "windup")
						events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": GUNNER.windup})
						return false
					return true
				"windup":
					if e.t >= GUNNER.windup:
						e.shots_left = GUNNER.shots
						_enter(e, "attack")
						e.t = GUNNER.gap # first shot right away
					return false
				"attack":
					if e.t >= GUNNER.gap:
						e.t = 0.0
						if e.los:
							_fire(e, eye, _player_center(p), GUNNER.speed, GUNNER.damage, 0.25, "bullet")
						e.shots_left -= 1
						if e.shots_left <= 0:
							e.cd = GUNNER.cooldown
							_enter(e, "move")
					return false
		"lobber":
			match e.state:
				"move":
					if e.los and dist < LOBBER.reach and e.cd <= 0 and not p.dead:
						_enter(e, "windup")
						events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": LOBBER.windup})
						return false
					return true
				"windup":
					if e.t >= LOBBER.windup:
						_lob(e, eye, Vector3(p.px, p.py, p.pz))
						e.cd = LOBBER.cooldown
						_enter(e, "move")
					return false
		"sniper":
			match e.state:
				"move":
					if e.los and dist < SNIPER.reach and e.cd <= 0 and not p.dead:
						_enter(e, "aim")
						events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": SNIPER.aim + SNIPER.lock})
						return false
					return true
				"aim":
					e.aim = _player_center(p) # the laser follows you...
					if not e.los:
						e.cd = 1.0 # lost you: try again soon
						_enter(e, "move")
					elif e.t >= SNIPER.aim:
						_enter(e, "lock") # ...then stops: move now and it misses
						events.append({"type": "lock", "id": e.id})
					return false
				"lock":
					if e.t >= SNIPER.lock:
						_snipe(e, eye, p)
						e.cd = SNIPER.cooldown
						_enter(e, "move")
					return false
	return true


# ---------- flyers ----------

func _tick_flyer(e: Enemy, p: PlayerSim, dt: float) -> void:
	var pc := _player_center(p)
	var desired := e.pos
	var speed: float = e.def.speed
	if e.type == "flyer_healer":
		desired = _healer(e, p, dt)
	else:
		# Circle the player at their range, a few meters up.
		var off := e.pos - pc
		off.y = 0
		if off.length() < 0.1:
			off = Vector3(1, 0, 0)
		var ang := atan2(off.z, off.x) + e.strafe_dir * 0.35 * dt * 3.0
		var r: float = e.def.range
		desired = pc + Vector3(cos(ang) * r, 3.5, sin(ang) * r)
		if e.type == "flyer_projectile":
			_flyer_orb(e, p, pc)
		else:
			_flyer_beam(e, p, pc, dt)
	# Hover height: over the ground, never climbing away (two healers each hovering over the other
	# used to ratchet up forever). Over you too when you're up on something high.
	e.ground_t -= dt
	if e.ground_t <= 0:
		e.ground_t = 0.2
		e.ground_y = _ground_under(desired)
	desired.y = clampf(desired.y, e.ground_y + FLY_MIN, maxf(e.ground_y, p.py) + FLY_MAX)
	var busy := e.state in ["windup", "attack"] and e.type == "flyer_projectile"
	var want := (desired - e.pos)
	var accel := 10.0
	var target_vel := want.normalized() * minf(speed, want.length() * 2.0) if want.length() > 0.05 else Vector3.ZERO
	if busy:
		target_vel *= 0.3 # hovers still while it shoots
	e.vel = e.vel.move_toward(target_vel, accel * dt)
	e.pos += e.vel * dt
	e.pos = _push_out(e.pos, 0.6 * e.target.size)
	var look := (pc - e.pos) if e.type != "flyer_healer" or e.heal_target == null else (e.heal_target.center() - e.pos)
	e.yaw = atan2(-look.x, -look.z)
	e.target.pos = e.pos - Vector3(0, 1.0 * e.target.size, 0)


func _flyer_orb(e: Enemy, p: PlayerSim, pc: Vector3) -> void:
	var dist := e.pos.distance_to(pc)
	match e.state:
		"move":
			if e.los and dist < FLYER_ORB.reach and e.cd <= 0 and not p.dead:
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": FLYER_ORB.windup})
		"windup":
			if e.t >= FLYER_ORB.windup:
				if e.los:
					_fire(e, e.pos, pc, FLYER_ORB.speed, FLYER_ORB.damage, 0.3, "orb")
				e.cd = FLYER_ORB.cooldown
				_enter(e, "move")


func _flyer_beam(e: Enemy, p: PlayerSim, pc: Vector3, dt: float) -> void:
	var dist := e.pos.distance_to(pc)
	match e.state:
		"move":
			if e.los and dist < FLYER_BEAM.reach and e.cd <= 0 and not p.dead:
				_enter(e, "windup")
				events.append({"type": "windup", "id": e.id, "enemy": e.type, "pos": e.center(), "time": FLYER_BEAM.windup})
		"windup":
			if e.t >= FLYER_BEAM.windup:
				_enter(e, "attack")
				events.append({"type": "beam_on", "id": e.id})
		"attack":
			# Locked on while you're close and in sight; out of range or behind cover breaks it.
			var sees := _can_see(e.pos, pc)
			if dist > FLYER_BEAM.break or not sees or e.t >= FLYER_BEAM.max or p.dead:
				e.cd = FLYER_BEAM.cooldown
				e.beam_acc = 0.0
				_enter(e, "move")
				events.append({"type": "beam_off", "id": e.id})
			else:
				e.beam_acc += FLYER_BEAM.dps * dt
				if e.beam_acc >= 3.0:
					hurt_player(p, e.beam_acc, e.pos, e.def.name)
					e.beam_acc = 0.0


## Picks the most hurt enemy it can see and keeps a beam on it; keeps away from the player.
func _healer(e: Enemy, p: PlayerSim, dt: float) -> Vector3:
	var pc := _player_center(p)
	if e.heal_target and (not e.heal_target.alive or e.heal_target.target.hp >= e.heal_target.target.max_hp):
		e.heal_target = null
		events.append({"type": "heal_off", "id": e.id})
	if e.heal_target == null and e.t > 0.3:
		e.t = 0.0
		# The most hurt one in reach that it can see. Never another healer: they can't hurt you, so
		# keeping each other alive would only drag the fight out. Sight is checked only for the few
		# most hurt: a ray to every enemy in a big crowd every search adds up.
		var hurt: Array[Enemy] = []
		for o in list:
			if o.type == "flyer_healer" or not o.alive or o.target.hp >= o.target.max_hp:
				continue
			if o.center().distance_to(e.pos) <= HEALER.reach:
				hurt.append(o)
		hurt.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.target.hp / a.target.max_hp < b.target.hp / b.target.max_hp)
		var best: Enemy = null
		for o in hurt.slice(0, 4):
			if _can_see(e.pos, o.center()):
				best = o
				break
		if best:
			e.heal_target = best
			events.append({"type": "heal_on", "id": e.id, "target": best.id})
	var anchor: Vector3
	if e.heal_target:
		var o := e.heal_target
		e.heal_los_t -= dt
		var lost := false
		if e.heal_los_t <= 0:
			e.heal_los_t = 0.25
			lost = not _can_see(e.pos, o.center())
		if lost or o.center().distance_to(e.pos) > HEALER.reach + 3:
			e.heal_target = null
			events.append({"type": "heal_off", "id": e.id})
			anchor = o.center()
		else:
			o.target.hp = minf(o.target.max_hp, o.target.hp + HEALER.hps * dt)
			anchor = o.center()
	else:
		# Nobody to heal: tag along with the nearest enemy that isn't another healer (following each
		# other they'd just drift off), or hang back from the player.
		var nearest: Enemy = null
		var nd := INF
		for o in list:
			if o != e and o.alive and o.type != "flyer_healer" and o.center().distance_to(e.pos) < nd:
				nd = o.center().distance_to(e.pos)
				nearest = o
		anchor = nearest.center() if nearest else pc + (e.pos - pc).normalized() * 14.0
	var desired := anchor + Vector3(0, 3.0, 0) + (e.pos - anchor).normalized() * HEALER.reach * 0.25
	# Flee if the player gets close.
	var away := e.pos - pc
	if away.length() < 8.0:
		desired += away.normalized() * 6.0
	return desired


# ---------- shots ----------

func _fire(e: Enemy, from: Vector3, at: Vector3, speed: float, dmg: float, radius: float, kind: String) -> void:
	var d := (at - from).normalized()
	projectiles.append({"id": _shot_id(), "pos": from + d * 0.6, "vel": d * speed, "radius": radius, "damage": dmg, "kind": kind,
		"gravity": 0.0, "splash": 0.0, "owner": e.def.name, "alive": true, "age": 0.0})
	events.append({"type": "enemy_shot", "id": e.id, "enemy": e.type, "pos": from})


## A grenade that lands where you stood when it was thrown (the view marks the spot).
func _lob(e: Enemy, from: Vector3, at: Vector3) -> void:
	var flat := Vector2(at.x - from.x, at.z - from.z)
	var t := clampf(flat.length() / 14.0, 0.8, 1.6)
	var g: float = LOBBER.gravity
	var vel := Vector3(flat.x / t, (at.y - from.y + 0.5 * g * t * t) / t, flat.y / t)
	projectiles.append({"id": _shot_id(), "pos": from, "vel": vel, "radius": 0.25, "damage": LOBBER.damage, "kind": "lob",
		"gravity": g, "splash": LOBBER.radius, "owner": e.def.name, "alive": true, "age": 0.0})
	events.append({"type": "lob", "id": e.id, "pos": from, "land": at, "time": t})


## Fires along the locked aim: hits if you're still on that line.
func _snipe(e: Enemy, from: Vector3, p: PlayerSim) -> void:
	var d := (e.aim - from).normalized()
	var far := 80.0
	var wall := _ray_walls(from, d, far)
	if wall >= 0:
		far = wall
	var hit_t := _ray_player(from, d, p, 0.1)
	var hit := hit_t >= 0 and hit_t < far
	if hit:
		hurt_player(p, SNIPER.damage, from, e.def.name)
	events.append({"type": "snipe", "id": e.id, "from": from, "to": from + d * (hit_t if hit else far), "hit": hit})


func _tick_projectiles(p: PlayerSim, dt: float) -> void:
	for pr in projectiles:
		pr.age += dt
		if pr.age > 6.0:
			pr.alive = false
			continue
		var vel: Vector3 = pr.vel
		vel.y -= float(pr.gravity) * dt
		pr.vel = vel
		var step := vel * dt
		var from: Vector3 = pr.pos
		var len := step.length()
		var d := step / maxf(len, 1e-6)
		# the player first (so a shot that reaches you this tick hits you, not the wall behind)
		var hp := _ray_player(from, d, p, pr.radius)
		var hw := _ray_walls(from, d, len + pr.radius)
		if hp >= 0 and hp <= len and (hw < 0 or hp <= hw):
			if pr.splash > 0:
				_explode(from + d * hp, pr, p)
			else:
				hurt_player(p, pr.damage, from, pr.owner)
				events.append({"type": "enemy_hit", "pos": from + d * hp})
			pr.alive = false
			continue
		if hw >= 0 and hw <= len + pr.radius:
			var at := from + d * maxf(0.0, hw - pr.radius)
			if pr.splash > 0:
				_explode(at, pr, p)
			else:
				events.append({"type": "enemy_impact", "pos": at})
			pr.alive = false
			continue
		pr.pos = from + step
	projectiles = projectiles.filter(func(pr: Dictionary) -> bool: return pr.alive)


func _shot_id() -> int:
	_next_shot += 1
	return _next_shot


func _explode(at: Vector3, pr: Dictionary, p: PlayerSim) -> void:
	var r: float = pr.splash
	var closest := Vector3(clampf(at.x, p.px - Cfg.PLAYER_HALF_WIDTH, p.px + Cfg.PLAYER_HALF_WIDTH),
		clampf(at.y, p.py, p.py + p.height), clampf(at.z, p.pz - Cfg.PLAYER_HALF_WIDTH, p.pz + Cfg.PLAYER_HALF_WIDTH))
	var d := closest.distance_to(at)
	if d < r and _can_see(at + Vector3(0, 0.3, 0), _player_center(p)):
		hurt_player(p, pr.damage * (1.0 - 0.6 * d / r), at, pr.owner)
		var push := (_player_center(p) - at).normalized() + Vector3(0, 0.6, 0)
		push = push.normalized() * 8.0 * (1.0 - d / r)
		p.apply_impulse(push.x, push.y, push.z, "lob")
	events.append({"type": "enemy_explosion", "pos": at, "radius": r})


# ---------- helpers ----------

func _enter(e: Enemy, s: String) -> void:
	e.state = s
	e.t = 0.0


## Frozen: stand still (ground types still fall and settle).
func _hold(e: Enemy, dt: float) -> void:
	if e.body:
		var c := Cmd.new()
		c.yaw = e.yaw
		e.body.step(c, map, dt)
		e.target.pos = Vector3(e.body.px, e.body.py, e.body.pz)


func _eye(e: Enemy) -> Vector3:
	if e.body:
		return Vector3(e.body.px, e.body.py + 1.5 * e.target.size, e.body.pz)
	return e.pos


static func _player_center(p: PlayerSim) -> Vector3:
	return Vector3(p.px, p.py + p.height * 0.55, p.pz)


func _touching(e: Enemy, p: PlayerSim, extra: float) -> bool:
	var c := e.center()
	var pc := _player_center(p)
	return Vector2(c.x - pc.x, c.z - pc.z).length() < 0.4 * e.target.size + Cfg.PLAYER_HALF_WIDTH + extra \
		and absf(c.y - pc.y) < 1.4


## Nothing in the way between a and b (walls only; invisible barriers don't block sight).
func _can_see(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return true
	var hit := _ray_walls(a, d / len, len)
	return hit < 0 or hit >= len - 0.05


## Distance along the ray to the first wall, or -1.
func _ray_walls(o: Vector3, d: Vector3, max_t: float) -> float:
	var best := -1.0
	var lim := max_t
	for b in map.ray_boxes(o, d, max_t):
		if b.kind == "barrier":
			continue
		var h := Combat.ray_box(o, d, b, lim)
		if not h.is_empty():
			lim = h[0]
			best = h[0]
	return best


## Distance along the ray to the player's box (grown by r), or -1.
static func _ray_player(o: Vector3, d: Vector3, p: PlayerSim, r: float) -> float:
	var lo := Vector3(p.px - Cfg.PLAYER_HALF_WIDTH - r, p.py - r, p.pz - Cfg.PLAYER_HALF_WIDTH - r)
	var hi := Vector3(p.px + Cfg.PLAYER_HALF_WIDTH + r, p.py + p.height + r, p.pz + Cfg.PLAYER_HALF_WIDTH + r)
	var tmin := 0.0
	var tmax := INF
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a]:
				return -1.0
			continue
		var t1 := (lo[a] - o[a]) / d[a]
		var t2 := (hi[a] - o[a]) / d[a]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
		if tmin > tmax:
			return -1.0
	return tmin


func _ground_under(at: Vector3) -> float:
	var h := _ray_walls(at + Vector3(0, 0.5, 0), Vector3.DOWN, 60.0)
	return at.y + 0.5 - h if h >= 0 else -30.0


## Keep a flyer (a ball of radius r) out of the walls.
func _push_out(at: Vector3, r: float) -> Vector3:
	var p := at
	for b in map.nearby(p.x, p.y, p.z, r + 1.0):
		if b.kind == "barrier":
			continue
		var top := MapData.solid_top(b, p.x - r, p.x + r, p.z - r, p.z + r)
		var c := Vector3(clampf(p.x, b.min_x, b.max_x), clampf(p.y, b.min_y, top), clampf(p.z, b.min_z, b.max_z))
		var off := p - c
		var dist := off.length()
		if dist < r:
			if dist < 1e-4:
				p.y = top + r # inside: pop out the top
			else:
				p = c + off / dist * r
	return p
