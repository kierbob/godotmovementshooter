class_name Upgrades
extends RefCounted
## Stacking items, Risk of Rain style: what you're carrying (`stacks`) and everything they do.
## Pure logic inside the sim tick, owned by Combat (`combat.up`), which calls the hooks:
##   fire_dirs()      Triple Tap: one aim direction -> the whole V of copies
##   modify_damage()  crits and the damage multipliers, on every hit you land
##   on_hit()         procs (burn, bleed, chill, chain lightning, bombs...), only for "gun" hits
##   on_kill()        kill effects, queued and run next tick so chain reactions ripple outward
##   on_hurt()        (from Enemies.hurt_player) blocking, Razor Wire
##   tick()           status effects on every target, movement stats, slide/stomp damage
## Damage sources: "gun" (your guns, rockets, knives: these proc), "dot" (burn/bleed ticks) and
## "item" (explosions, lightning, wisps...). Only "gun" procs, so nothing loops forever.
##
## Statuses live on Combat.Target.status (so dummies show them too); EnemyView draws them and
## Enemies reads time_scale() (chilled = half speed, frozen = stopped) and target.knock.
## With nothing picked up every hook returns right away and the game plays exactly as before.

const RARITY := {
	"common": {"name": "Common", "color": Color("e8e8f0"), "weight": 70},
	"uncommon": {"name": "Uncommon", "color": Color("6fdc6a"), "weight": 25},
	"rare": {"name": "Rare", "color": Color("ff5a5a"), "weight": 5},
	"legendary": {"name": "Legendary", "color": Color("ffb020"), "weight": 0}, # golden chests only
}

## Every item. desc = what one does, stack = what more of them add. tag groups them loosely;
## icon = two letters on the HUD chip, color = the chip's fill.
const LIST := {
	# ---- common ----
	"running_shoes": {"name": "Running Shoes", "rarity": "common", "tag": "move", "icon": "RS", "color": Color("5fb8ff"),
		"desc": "Run 10% faster.", "stack": "+10% speed"},
	"wall_grips": {"name": "Wall Grips", "rarity": "common", "tag": "move", "icon": "WG", "color": Color("9a8cff"),
		"desc": "+1 wall jump before you have to land.", "stack": "+1 wall jump"},
	"extended_mag": {"name": "Extended Mag", "rarity": "common", "tag": "gun", "icon": "EM", "color": Color("c9a26a"),
		"desc": "+25% magazine size.", "stack": "+25% magazine"},
	"quick_hands": {"name": "Quick Hands", "rarity": "common", "tag": "gun", "icon": "QH", "color": Color("ffcf6a"),
		"desc": "Reload 15% faster.", "stack": "+15% reload speed"},
	"hair_trigger": {"name": "Hair Trigger", "rarity": "common", "tag": "gun", "icon": "HT", "color": Color("ff9a5a"),
		"desc": "Fire 12% faster.", "stack": "+12% fire rate"},
	"lucky_penny": {"name": "Lucky Penny", "rarity": "common", "tag": "damage", "icon": "LP", "color": Color("ffd84a"),
		"desc": "10% chance to crit for double damage.", "stack": "+10% crit chance"},
	"point_blank": {"name": "Point Blank", "rarity": "common", "tag": "damage", "icon": "PB", "color": Color("ff7a45"),
		"desc": "+25% damage to enemies within 7 m.", "stack": "+25% damage"},
	"opening_act": {"name": "Opening Act", "rarity": "common", "tag": "damage", "icon": "OA", "color": Color("d9d9d9"),
		"desc": "+50% damage to enemies above 90% health.", "stack": "+50% damage"},
	"match_head": {"name": "Match Head", "rarity": "common", "tag": "status", "icon": "MH", "color": Color("ff8a30"),
		"desc": "10% chance on hit to set them on fire.", "stack": "+10% chance"},
	"rusty_nail": {"name": "Rusty Nail", "rarity": "common", "tag": "status", "icon": "RN", "color": Color("c0392b"),
		"desc": "10% chance on hit to make them bleed (bleeds stack).", "stack": "+10% chance"},
	"vampire_fangs": {"name": "Vampire Fangs", "rarity": "common", "tag": "defense", "icon": "VF", "color": Color("e04a7a"),
		"desc": "Heal 2 health on every hit.", "stack": "+2 health"},
	"tough_skin": {"name": "Tough Skin", "rarity": "common", "tag": "defense", "icon": "TS", "color": Color("7fd08a"),
		"desc": "+25 max health.", "stack": "+25 max health"},
	"bubble_wrap": {"name": "Bubble Wrap", "rarity": "common", "tag": "defense", "icon": "BW", "color": Color("bfe6ff"),
		"desc": "12% chance to block a hit completely.", "stack": "more blocking (never 100%)"},
	"adrenaline": {"name": "Adrenaline", "rarity": "common", "tag": "kill", "icon": "AD", "color": Color("ff5ab4"),
		"desc": "Kills make you 30% faster for 2 s.", "stack": "+1 s"},
	"sticky_bomb": {"name": "Sticky Bomb", "rarity": "common", "tag": "status", "icon": "SB", "color": Color("8fe36b"),
		"desc": "8% chance on hit to stick a bomb on them (explodes for 180%).", "stack": "+8% chance"},
	"knockout_glove": {"name": "Knockout Glove", "rarity": "common", "tag": "status", "icon": "KG", "color": Color("ff4a4a"),
		"desc": "Hits knock enemies back.", "stack": "harder knockback"},
	# ---- uncommon ----
	"frost_tip": {"name": "Frost Tip", "rarity": "uncommon", "tag": "status", "icon": "FT", "color": Color("8fd3ff"),
		"desc": "Hits chill enemies (half speed). Keep hitting a chilled one to freeze it solid; frozen ones shatter below 25% health.",
		"stack": "freezes in fewer hits"},
	"static_coil": {"name": "Static Coil", "rarity": "uncommon", "tag": "status", "icon": "SC", "color": Color("6fe0ff"),
		"desc": "20% chance on hit to arc lightning to 3 nearby enemies for 60%.", "stack": "+2 targets"},
	"party_popper": {"name": "Party Popper", "rarity": "uncommon", "tag": "kill", "icon": "PP", "color": Color("ffb13d"),
		"desc": "Enemies explode when they die (bigger ones, bigger boom).", "stack": "+damage, +1 m radius"},
	"speed_loader": {"name": "Speed Loader", "rarity": "uncommon", "tag": "kill", "icon": "SL", "color": Color("e0b03a"),
		"desc": "Kills refill the gun in your hands.", "stack": "2+: refills both guns"},
	"recharger": {"name": "Recharger", "rarity": "uncommon", "tag": "kill", "icon": "RC", "color": Color("5ee0a0"),
		"desc": "Kills take 1 s off your ability cooldown.", "stack": "+1 s"},
	"sky_striker": {"name": "Sky Striker", "rarity": "uncommon", "tag": "damage", "icon": "SS", "color": Color("7fb8ff"),
		"desc": "+30% damage while you're in the air.", "stack": "+30% damage"},
	"momentum": {"name": "Momentum Engine", "rarity": "uncommon", "tag": "damage", "icon": "ME", "color": Color("4fcf92"),
		"desc": "+3% damage for every m/s you're moving faster than a run.", "stack": "+3% per m/s"},
	"headhunter": {"name": "Headhunter", "rarity": "uncommon", "tag": "damage", "icon": "HH", "color": Color("f2c14e"),
		"desc": "Headshots deal +40% damage.", "stack": "+40% damage"},
	"spring_heels": {"name": "Spring Heels", "rarity": "uncommon", "tag": "move", "icon": "SH", "color": Color("a77be0"),
		"desc": "+1 jump in the air.", "stack": "+1 air jump"},
	"slide_spikes": {"name": "Slide Spikes", "rarity": "uncommon", "tag": "move", "icon": "SP", "color": Color("b0b8c8"),
		"desc": "Sliding into enemies deals 40 damage and launches them.", "stack": "+30 damage"},
	"razor_wire": {"name": "Razor Wire", "rarity": "uncommon", "tag": "defense", "icon": "RW", "color": Color("9e978a"),
		"desc": "Getting hurt lashes out at 3 enemies nearby for 25.", "stack": "+2 targets, +15 damage"},
	"ricochet": {"name": "Ricochet", "rarity": "uncommon", "tag": "gun", "icon": "RI", "color": Color("d6a86a"),
		"desc": "Bullets that hit a wall have a 25% chance to bounce into the nearest enemy.", "stack": "+25% chance"},
	"tracker_dart": {"name": "Tracker Dart", "rarity": "uncommon", "tag": "status", "icon": "TD", "color": Color("ff6a5a"),
		"desc": "Hits mark enemies for 4 s: marked enemies take +20% damage from everything.", "stack": "+20% damage"},
	# ---- rare ----
	"triple_tap": {"name": "Triple Tap", "rarity": "rare", "tag": "gun", "icon": "TT", "color": Color("ff5a5a"),
		"desc": "Every shot and throw fires 2 extra copies in a V. Only the real one pushes you.", "stack": "+2 copies, wider V"},
	"big_bang": {"name": "Big Bang", "rarity": "rare", "tag": "damage", "icon": "BB", "color": Color("ff8a30"),
		"desc": "Every hit explodes for 60% in a 3 m blast.", "stack": "+1 m radius"},
	"stomp_boots": {"name": "Stomp Boots", "rarity": "rare", "tag": "move", "icon": "ST", "color": Color("8a5cff"),
		"desc": "Landing from a big fall slams the ground: the faster you fall, the harder.", "stack": "+50% damage, +1 m"},
	"wisp_jar": {"name": "Wisp Jar", "rarity": "rare", "tag": "kill", "icon": "WJ", "color": Color("8fe8ff"),
		"desc": "Kills release 2 wisps that hunt down enemies for 40 each.", "stack": "+1 wisp"},
	"four_leaf": {"name": "Four Leaf", "rarity": "rare", "tag": "luck", "icon": "FL", "color": Color("3fbf5f"),
		"desc": "Every chance rolls twice, keeping the lucky one.", "stack": "+1 reroll"},
	# ---- legendary (golden chests) ----
	"drone_buddy": {"name": "Drone Buddy", "rarity": "legendary", "tag": "gun", "icon": "DB", "color": Color("6fe0ff"),
		"desc": "A drone orbits you and shoots the nearest enemy it can see (12 a shot, 4 a second).", "stack": "+1 drone"},
	"orbital_strike": {"name": "Orbital Strike", "rarity": "legendary", "tag": "damage", "icon": "OS", "color": Color("ff5ab4"),
		"desc": "Every 6 s a laser from the sky hits the toughest enemy near you for 250.", "stack": "fires 1 s sooner"},
	"hydra": {"name": "Hydra Launcher", "rarity": "legendary", "tag": "gun", "icon": "HY", "color": Color("ff8a30"),
		"desc": "Every 5th shot also launches 4 homing missiles (30 each, small blasts).", "stack": "+2 missiles"},
	"singularity": {"name": "Singularity", "rarity": "legendary", "tag": "status", "icon": "SG", "color": Color("a77be0"),
		"desc": "10% chance on hit to open a black hole: it drags enemies in and grinds them, then implodes for 120.", "stack": "+5% chance"},
	"phoenix": {"name": "Phoenix Feather", "rarity": "legendary", "tag": "defense", "icon": "PF", "color": Color("ffd84a"),
		"desc": "The hit that would kill you doesn't: you rise at half health, briefly untouchable. Burns up after.", "stack": "+1 life"},
	"glass_cannon": {"name": "Glass Cannon", "rarity": "legendary", "tag": "damage", "icon": "GC", "color": Color("dff4ff"),
		"desc": "Double damage. Half max health.", "stack": "double again, half again"},
}

## Status numbers.
const BURN_TIME := 3.0
const BLEED_TIME := 3.0
const BLEED_DPS := 6.0
const CHILL_TIME := 2.0
const FREEZE_TIME := 1.5
const MARK_TIME := 4.0
const BOMB_FUSE := 1.2
const DOT_EVERY := 0.5 # damage over time lands in chunks (one number, not 120 a second)
const WISP := {"speed": 16.0, "up": 0.0, "gravity": 0.0, "radius": 0.25, "impact": "wisp", "damage": 40.0,
	"head_mult": 1.0, "hit_pad": 0.35, "homing": 5.0, "life": 5.0, "inherit": false}
const COPY_ANGLE := 7.0 # degrees between Triple Tap copies
const DRONE := {"range": 35.0, "damage": 12.0, "rate": 4.0, "orbit": 1.3}
const ORBITAL := {"every": 6.0, "damage": 250.0, "range": 50.0, "radius": 3.0}
const HYDRA_EVERY := 5
const MISSILE := {"speed": 24.0, "up": 4.0, "gravity": 0.0, "radius": 0.18, "impact": "missile", "damage": 30.0,
	"head_mult": 1.0, "hit_pad": 0.3, "homing": 4.0, "life": 4.0, "inherit": false, "blast": 2.5}
const HOLE := {"time": 2.5, "pull_r": 9.0, "pull": 7.0, "grind_r": 3.0, "dps": 30.0, "implode": 120.0}
## Levels (Risk of Rain style): kills give XP; each level is +LEVEL_DAMAGE damage and
## +LEVEL_HEALTH max health, and a full heal. Level n -> n+1 takes XP_BASE * XP_GROWTH^(n-1).
const LEVEL_DAMAGE := 0.1
const LEVEL_HEALTH := 12.0
const XP_BASE := 20.0
const XP_GROWTH := 1.45

var combat: Combat: # weak: Combat owns us, and a reference loop would never be freed
	get:
		return _combat.get_ref()
var _combat: WeakRef
var stacks := {} # id -> how many
var total := 0 # items held
var level := 1
var xp := 0.0 # toward the next level
var active := false # anything to do at all (items or levels): false = every hook is a no-op
var rng := RandomNumberGenerator.new()
var adrenaline_t := 0.0
var _kills: Array[Combat.Target] = [] # waiting for their kill effects (next tick)
var _max_bonus := 0.0 # Tough Skin health already added to the player
var _was_grounded := true
var _fall_speed := 0.0 # how fast we were falling the tick before landing
var _slid := {} # target -> time until Slide Spikes can hit it again
var drones: Array[Vector3] = [] # where the Drone Buddies are (the view draws them there)
var _drone_cd := 0.0
var _orbital_t := 0.0
var _shots := 0 # gun shots fired (Hydra)
var holes: Array[Dictionary] = [] # black holes {pos, t, acc}
var _pull_t := 0.0
var _hole_acc := {} # target -> black hole damage built up (dealt in chunks)
var _hole_id := 0 # the view keys its black holes on this (a Dictionary's hash changes as it ticks)
var _time := 0.0


func _init(c: Combat) -> void:
	_combat = weakref(c)
	rng.randomize()


func count(id: String) -> int:
	return stacks.get(id, 0)


func add(id: String, n := 1) -> void:
	stacks[id] = maxi(0, count(id) + n)
	if stacks[id] == 0:
		stacks.erase(id)
	total = 0
	for k: String in stacks:
		total += stacks[k]
	active = total > 0 or level > 1


func clear() -> void:
	stacks.clear()
	total = 0
	active = level > 1


## XP needed to go from `lvl` to the next.
static func xp_to_next(lvl: int) -> float:
	return XP_BASE * pow(XP_GROWTH, lvl - 1)


## Kills pay XP (Loot calls this). Levelling up: stronger, tougher, and topped up.
func add_xp(amount: float, p: PlayerSim) -> void:
	xp += amount
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		active = true
		if p:
			_apply_stats(p)
			if not p.dead:
				p.hp = p.max_hp
		combat.fx.append({"type": "level_up", "level": level})


## A random item id, weighted by rarity (common 70%, uncommon 25%, rare 5%).
func random_id() -> String:
	var roll := rng.randf() * 100.0
	return random_of("common" if roll < 70 else "uncommon" if roll < 95 else "rare")


## A random item of one rarity.
func random_of(rarity: String) -> String:
	var ids: Array = LIST.keys().filter(func(k: String) -> bool: return LIST[k].rarity == rarity)
	return ids[rng.randi() % ids.size()]


## Did a p-chance roll hit? Four Leaf rerolls failures.
func roll(p: float) -> bool:
	for i in 1 + count("four_leaf"):
		if rng.randf() < p:
			return true
	return false


# ---------- guns ----------

## Triple Tap: the aim direction plus copies fanned out left and right (a flat V).
func fire_dirs(d: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = [d]
	var n := count("triple_tap")
	for i in n:
		for s: float in [-1.0, 1.0]:
			out.append(d.rotated(Vector3.UP, deg_to_rad(COPY_ANGLE * (i + 1)) * s))
	return out


func mag_size(base: int) -> int:
	return base if count("extended_mag") == 0 else ceili(base * (1.0 + 0.25 * count("extended_mag")))


func reload_time(base: float) -> float:
	return base / (1.0 + 0.15 * count("quick_hands"))


func fire_rate(base: float) -> float:
	return base * (1.0 + 0.12 * count("hair_trigger"))


# ---------- dealing damage ----------

## Every multiplier on a hit you deal: returns [damage, crit].
func modify_damage(t: Combat.Target, dmg: float, zone: String, point: Vector3, src: String) -> Array:
	var mult := 1.0
	var crit := false
	var p := combat.player
	if src == "gun" and p:
		if count("point_blank") > 0 and point.distance_to(Combat.eye_position(p)) < 7.0:
			mult += 0.25 * count("point_blank")
		if count("opening_act") > 0 and t.hp >= t.max_hp * 0.9:
			mult += 0.5 * count("opening_act")
		if count("sky_striker") > 0 and not p.grounded:
			mult += 0.3 * count("sky_striker")
		if count("momentum") > 0:
			mult += 0.03 * count("momentum") * maxf(0.0, p.horizontal_speed() - Cfg.MOVE_WALK_SPEED)
		if count("headhunter") > 0 and zone == "head":
			mult += 0.4 * count("headhunter")
		if count("lucky_penny") > 0 and roll(minf(1.0, 0.1 * count("lucky_penny"))):
			crit = true
	var mark: Dictionary = t.status.get("mark", {})
	if not mark.is_empty():
		mult += float(mark.mult)
	var lvl := 1.0 + LEVEL_DAMAGE * (level - 1) # everything you deal grows with your level
	var glass := pow(2.0, count("glass_cannon"))
	return [dmg * mult * lvl * glass * (2.0 if crit else 1.0), crit]


## A "gun" hit landed (after the damage): roll every proc.
func on_hit(t: Combat.Target, dmg: float, zone: String, point: Vector3) -> void:
	var p := combat.player
	if count("vampire_fangs") > 0 and p and not p.dead:
		p.hp = minf(p.max_hp, p.hp + 2.0 * count("vampire_fangs"))
	if count("big_bang") > 0:
		combat.item_explosion(point, 3.0 + (count("big_bang") - 1), dmg * 0.6, "bigbang")
	if count("static_coil") > 0 and roll(0.2):
		var chained := [t]
		var from := point
		for i in 3 + 2 * (count("static_coil") - 1):
			var next := _nearest(from, 14.0, chained)
			if next == null:
				break
			chained.append(next)
			var to := next.pos + Vector3(0, 1.0 * next.size, 0)
			combat.fx.append({"type": "zap", "from": from, "to": to, "color": Color("6fe0ff")})
			combat.damage_target(next, dmg * 0.6, "body", to, "item")
			from = to
	if t.dead:
		return # the rest sticks to them
	if count("knockout_glove") > 0:
		var away := t.pos - (Vector3(p.px, p.py, p.pz) if p else point)
		away.y = 0
		var push := away.normalized() * (4.0 + 2.0 * count("knockout_glove")) + Vector3(0, 3.0, 0)
		_push(t, push)
	if count("match_head") > 0 and roll(minf(1.0, 0.1 * count("match_head"))):
		var burn: Dictionary = t.status.get("burn", {"t": 0.0, "dps": 0.0, "acc": 0.0})
		burn.t = BURN_TIME
		burn.dps = maxf(burn.dps, maxf(8.0, dmg * 0.5))
		t.status.burn = burn
	if count("rusty_nail") > 0 and roll(minf(1.0, 0.1 * count("rusty_nail"))):
		var bleed: Dictionary = t.status.get("bleed", {"stacks": [], "acc": 0.0})
		(bleed.stacks as Array).append(BLEED_TIME)
		t.status.bleed = bleed
	if count("sticky_bomb") > 0 and roll(minf(1.0, 0.08 * count("sticky_bomb"))):
		var bombs: Array = t.status.get("bombs", [])
		bombs.append({"t": BOMB_FUSE, "dmg": dmg * 1.8})
		t.status.bombs = bombs
	if count("singularity") > 0 and roll(minf(1.0, 0.1 + 0.05 * (count("singularity") - 1))) and holes.size() < 3:
		_hole_id += 1
		holes.append({"id": _hole_id, "pos": t.pos + Vector3(0, 1.0 * t.size, 0), "t": HOLE.time})
		combat.fx.append({"type": "black_hole", "pos": t.pos + Vector3(0, 1.0 * t.size, 0)})
	if count("tracker_dart") > 0:
		t.status.mark = {"t": MARK_TIME, "mult": 0.2 * count("tracker_dart")}
	if count("frost_tip") > 0 and not t.status.has("freeze"):
		var chill: Dictionary = t.status.get("chill", {"t": 0.0, "hits": 0})
		chill.t = CHILL_TIME
		chill.hits += 1
		t.status.chill = chill
		if chill.hits >= maxi(2, 7 - count("frost_tip")):
			t.status.erase("chill")
			t.status.freeze = {"t": FREEZE_TIME}
			combat.fx.append({"type": "freeze", "pos": t.pos + Vector3(0, 1.0 * t.size, 0)})


## Ricochet: a bullet hit a wall at `point`; maybe bounce it into the nearest enemy.
func ricochet(point: Vector3, dmg: float) -> void:
	if count("ricochet") == 0 or not roll(minf(1.0, 0.25 * count("ricochet"))):
		return
	var t := _nearest(point, 20.0, [], true)
	if t == null:
		return
	var to := t.pos + Vector3(0, 1.0 * t.size, 0)
	combat.fx.append({"type": "zap", "from": point, "to": to, "color": Color("ffe07a"), "tracer": true})
	combat.damage_target(t, dmg * 0.75, "body", to, "gun")


## A target died (any cause). Its kill effects run next tick.
func on_kill(t: Combat.Target) -> void:
	if total > 0 and t.kind in ["enemy", "dummy"]:
		_kills.append(t)


func _kill_effects(t: Combat.Target) -> void:
	var center := t.pos + Vector3(0, 1.0 * t.size, 0)
	if count("adrenaline") > 0:
		adrenaline_t = 1.0 + count("adrenaline")
	if count("speed_loader") > 0:
		for slot: String in (["primary", "secondary"] if count("speed_loader") > 1 else [combat.active]):
			var s: Dictionary = combat.state[slot]
			s.ammo = combat.mag_size(slot)
			s.reload_t = 0.0
		combat.fx.append({"type": "item_proc", "item": "speed_loader"})
	if count("recharger") > 0:
		combat.ability_cd = maxf(0.0, combat.ability_cd - 1.0 * count("recharger"))
	if count("party_popper") > 0:
		var n := count("party_popper")
		combat.item_explosion(center, 4.0 + (n - 1), 20.0 * n + 0.15 * t.max_hp, "popper")
	if count("wisp_jar") > 0:
		for i in 1 + count("wisp_jar"):
			var a := TAU * i / float(1 + count("wisp_jar"))
			combat.spawn_item_projectile("wisp", WISP, center + Vector3(0, 0.5, 0), Vector3(cos(a), 1.2, sin(a)).normalized())


# ---------- getting hurt ----------

## Returns the damage you actually take (0 = blocked).
func on_hurt(p: PlayerSim, dmg: float) -> float:
	if total == 0:
		return dmg
	if count("phoenix") > 0 and dmg >= p.hp:
		add("phoenix", -1) # it burns up
		p.hp = p.max_hp * 0.5
		p.invuln = 2.0
		combat.fx.append({"type": "revive", "pos": Vector3(p.px, p.py, p.pz)})
		return 0.0
	var n := count("bubble_wrap")
	if n > 0 and roll(1.0 - 1.0 / (1.0 + 0.12 * n)):
		return 0.0
	if count("razor_wire") > 0:
		var r := count("razor_wire")
		var from := Vector3(p.px, p.py + 1.0, p.pz)
		var hit := []
		for i in 3 + 2 * (r - 1):
			var t := _nearest(from, 16.0, hit)
			if t == null:
				break
			hit.append(t)
			var to := t.pos + Vector3(0, 1.0 * t.size, 0)
			combat.fx.append({"type": "zap", "from": from, "to": to, "color": Color("d0c8b8")})
			combat.damage_target(t, 25.0 + 15.0 * (r - 1), "body", to, "item")
	return dmg


# ---------- every tick ----------

## Before the player moves (Combat.tick calls it).
func tick(p: PlayerSim, dt: float) -> void:
	var kills := _kills
	_kills = []
	for t in kills:
		_kill_effects(t)
	for t in combat.targets:
		if not t.status.is_empty():
			_tick_status(t, dt)
	_apply_stats(p) # also puts everything back after the items are dropped
	if total == 0:
		return
	_time += dt
	adrenaline_t = maxf(0.0, adrenaline_t - dt)
	if count("drone_buddy") > 0:
		_drones(p, dt)
	elif not drones.is_empty():
		drones.clear()
	if count("orbital_strike") > 0:
		_orbital_t += dt
		if _orbital_t >= maxf(2.0, ORBITAL.every - (count("orbital_strike") - 1)):
			_orbital_t = 0.0
			_orbital(p)
	if not holes.is_empty():
		_tick_holes(dt)
	if count("slide_spikes") > 0:
		_slide_spikes(p, dt)
	if count("stomp_boots") > 0:
		if p.grounded and not _was_grounded and _fall_speed > 14.0:
			_stomp(p, _fall_speed)
		_fall_speed = maxf(0.0, -p.vy) if not p.grounded else 0.0
	_was_grounded = p.grounded


## A gun fired (Combat._fire): Hydra counts the shots.
func on_fire(o: Vector3, d: Vector3) -> void:
	_shots += 1
	if count("hydra") > 0 and _shots % HYDRA_EVERY == 0:
		var n := 4 + 2 * (count("hydra") - 1)
		var side := d.cross(Vector3.UP).normalized()
		for i in n:
			var spread := (float(i) / maxf(1.0, n - 1) - 0.5) * 1.6
			combat.spawn_item_projectile("missile", MISSILE, o + side * spread * 0.4, (d + side * spread + Vector3(0, 0.6, 0)).normalized())
		combat.fx.append({"type": "hydra", "pos": o})


## Drone Buddies: circle over your shoulders, each shooting the nearest enemy it can see.
func _drones(p: PlayerSim, dt: float) -> void:
	var n := count("drone_buddy")
	drones.resize(n)
	var head := Vector3(p.px, p.py + p.height + 0.4, p.pz)
	for i in n:
		var a := _time * 1.6 + TAU * i / n
		drones[i] = head + Vector3(cos(a) * DRONE.orbit, sin(_time * 3.0 + i) * 0.15, sin(a) * DRONE.orbit)
	_drone_cd -= dt
	if _drone_cd > 0:
		return
	_drone_cd = 1.0 / (DRONE.rate * n) # the drones take turns
	var from: Vector3 = drones[(_shots + int(_time * 10.0)) % n]
	var t := _nearest(from, DRONE.range, [], true)
	if t == null:
		return
	var to := t.pos + Vector3(0, 1.0 * t.size, 0)
	combat.fx.append({"type": "zap", "from": from, "to": to, "color": Color("9ff0ff"), "tracer": true})
	combat.damage_target(t, DRONE.damage, "body", to, "item")


## Orbital Strike: the toughest enemy in range gets a laser from the sky.
func _orbital(p: PlayerSim) -> void:
	var me := Vector3(p.px, p.py, p.pz)
	var best: Combat.Target = null
	for t in combat.targets:
		if t.dead or t.kind not in ["enemy", "dummy"] or t.pos.distance_to(me) > ORBITAL.range:
			continue
		if best == null or t.hp > best.hp:
			best = t
	if best == null:
		return
	var at := best.pos
	combat.fx.append({"type": "orbital", "pos": at})
	combat.damage_target(best, ORBITAL.damage, "body", at + Vector3(0, 1.0 * best.size, 0), "item")
	combat.item_explosion(at + Vector3(0, 0.3, 0), ORBITAL.radius, ORBITAL.damage * 0.3, "orbital")


## Black holes: pull everything nearby in, grind what's inside, implode at the end.
func _tick_holes(dt: float) -> void:
	_pull_t -= dt
	var pull_now := _pull_t <= 0
	if pull_now:
		_pull_t = 0.1
	var left: Array[Dictionary] = []
	for h in holes:
		h.t -= dt
		var c: Vector3 = h.pos
		for t in combat.targets:
			if t.dead or t.kind not in ["enemy", "dummy"]:
				continue
			var mid := t.pos + Vector3(0, 1.0 * t.size, 0)
			var d := mid.distance_to(c)
			if d > HOLE.pull_r:
				continue
			if pull_now and d > 0.5 and t.kind == "enemy":
				# steer them in (at most HOLE.pull m/s, slower close up) rather than adding shoves:
				# stacked shoves flung them straight through and out the other side
				var want := c - mid
				want.y = 0.0
				want = want.normalized() * minf(HOLE.pull, want.length() * 2.5)
				if t.body:
					var dv := want - Vector3(t.body.vx, 0, t.body.vz)
					t.body.apply_impulse(dv.x, 1.0 if t.body.grounded else 0.0, dv.z, "item")
				else:
					t.knock += want * 0.3
			if d < HOLE.grind_r:
				_hole_acc[t] = float(_hole_acc.get(t, 0.0)) + HOLE.dps * dt
				if _hole_acc[t] >= 10.0:
					combat.damage_target(t, _hole_acc[t], "body", mid, "item")
					_hole_acc.erase(t)
		if h.t <= 0:
			combat.item_explosion(c, HOLE.pull_r * 0.6, HOLE.implode, "implode")
		else:
			left.append(h)
	holes = left
	if holes.is_empty():
		_hole_acc.clear()


## Items that change the player itself.
func _apply_stats(p: PlayerSim) -> void:
	p.speed_mult = 1.0 + 0.1 * count("running_shoes") + (0.3 if adrenaline_t > 0 else 0.0)
	p.extra_wall_jumps = count("wall_grips")
	p.air_jumps = count("spring_heels")
	# Glass Cannon halves the lot (the bonus can go negative: it's what's added to the 100 base)
	var bonus := (100.0 + 25.0 * count("tough_skin") + LEVEL_HEALTH * (level - 1)) * pow(0.5, count("glass_cannon")) - 100.0
	if bonus != _max_bonus:
		p.max_hp += bonus - _max_bonus
		if not p.dead:
			p.hp = clampf(p.hp + bonus - _max_bonus, 1.0, p.max_hp)
		_max_bonus = bonus


func _tick_status(t: Combat.Target, dt: float) -> void:
	var s := t.status
	if t.dead:
		s.clear()
		return
	var center := t.pos + Vector3(0, 1.0 * t.size, 0)
	s.dot_t = float(s.get("dot_t", DOT_EVERY)) - dt
	var land: bool = s.dot_t <= 0
	if land:
		s.dot_t = DOT_EVERY
	if s.has("burn"):
		var b: Dictionary = s.burn
		b.t -= dt
		b.acc += b.dps * dt
		if land or b.t <= 0:
			_dot(t, b, "burn", center)
		if b.t <= 0:
			s.erase("burn")
	if s.has("bleed"):
		var b: Dictionary = s.bleed
		var left := []
		for time_left: float in b.stacks:
			b.acc += BLEED_DPS * dt
			if time_left - dt > 0:
				left.append(time_left - dt)
		b.stacks = left
		if land or left.is_empty():
			_dot(t, b, "bleed", center)
		if left.is_empty():
			s.erase("bleed")
	for k: String in ["chill", "freeze", "mark"]:
		if s.has(k):
			s[k].t -= dt
			if s[k].t <= 0:
				s.erase(k)
	if s.has("freeze") and t.hp < t.max_hp * 0.25 and not t.dead:
		combat.fx.append({"type": "shatter", "pos": center})
		combat.damage_target(t, t.hp, "body", center, "item")
	if s.has("bombs"):
		var left := []
		for bomb: Dictionary in s.bombs:
			bomb.t -= dt
			if bomb.t <= 0:
				combat.item_explosion(center, 3.0, bomb.dmg, "bomb")
			else:
				left.append(bomb)
		if left.is_empty():
			s.erase("bombs")
		else:
			s.bombs = left
	if t.dead or s.keys() == ["dot_t"]:
		s.clear() # nothing left on it (the dot clock alone doesn't count)


func _dot(t: Combat.Target, b: Dictionary, kind: String, at: Vector3) -> void:
	if b.acc >= 0.5 and not t.dead:
		combat.damage_target(t, b.acc, "body", at, "dot", kind)
	b.acc = 0.0


func _slide_spikes(p: PlayerSim, dt: float) -> void:
	for t: Combat.Target in _slid.keys():
		_slid[t] -= dt
		if _slid[t] <= 0:
			_slid.erase(t)
	if not p.sliding or p.horizontal_speed() < 7.0:
		return
	for t in combat.targets:
		if t.dead or t.kind not in ["enemy", "dummy"] or _slid.has(t):
			continue
		var d := Vector2(t.pos.x - p.px, t.pos.z - p.pz).length()
		if d < 0.6 + 0.5 * t.size and absf(t.pos.y - p.py) < 1.5 * t.size:
			_slid[t] = 0.5
			var dmg := 40.0 + 30.0 * (count("slide_spikes") - 1)
			var dir := Vector3(p.vx, 0, p.vz).normalized()
			combat.damage_target(t, dmg, "body", t.pos + Vector3(0, 0.8 * t.size, 0), "gun")
			if not t.dead:
				_push(t, dir * 8.0 + Vector3(0, 9.0, 0))


func _stomp(p: PlayerSim, speed: float) -> void:
	var n := count("stomp_boots")
	var dmg := (speed - 10.0) * 5.0 * (1.0 + 0.5 * (n - 1))
	combat.item_explosion(Vector3(p.px, p.py + 0.3, p.pz), 5.0 + n, dmg, "stomp")


## Shove a target: ground enemies (and online players) through their body, flyers through knock.
func _push(t: Combat.Target, v: Vector3) -> void:
	if t.body:
		t.body.apply_impulse(v.x, v.y, v.z, "item")
	elif t.kind == "enemy":
		t.knock += v


## Nearest living enemy (or dummy) to `from` within `r`, skipping `skip`. see: needs a clear line.
func _nearest(from: Vector3, r: float, skip: Array, see := false) -> Combat.Target:
	var best: Combat.Target = null
	var best_d := r
	for t in combat.targets:
		if t.dead or t.kind not in ["enemy", "dummy"] or t in skip:
			continue
		var c := t.pos + Vector3(0, 1.0 * t.size, 0)
		var d := from.distance_to(c)
		if d >= best_d:
			continue
		if see:
			var dir := (c - from).normalized()
			var hit := combat.raycast(from + dir * 0.05, dir, d, 0.0, false)
			if hit:
				continue
		best = t
		best_d = d
	return best


# ---------- enemies read these ----------

## How fast a target's time runs: frozen 0, chilled 0.5, otherwise 1.
static func time_scale(t: Combat.Target) -> float:
	if t.status.is_empty():
		return 1.0
	if t.status.has("freeze"):
		return 0.0
	if t.status.has("chill"):
		return 0.5
	return 1.0


## For the console: an item id from typed words ("match head", "triple", "rusty_nail"), or "".
static func find(words: String) -> String:
	var q := words.strip_edges().to_lower().replace(" ", "_")
	if q == "":
		return ""
	if LIST.has(q):
		return q
	var flat := q.replace("_", "")
	var hits: Array = []
	for id: String in LIST:
		var name := String(LIST[id].name).to_lower().replace(" ", "")
		if name == flat:
			return id
		if id.begins_with(q) or name.begins_with(flat):
			hits.append(id)
	return hits[0] if hits.size() == 1 else ""
