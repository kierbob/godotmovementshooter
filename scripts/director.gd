class_name Director
extends RefCounted
## A stage of a run: WAVES waves of enemies, then the boss; kill it and the stage is cleared (main
## loads the next one). Pure logic in the sim tick, after the enemies; the HUD and sounds read
## `events` and the state below.
##
## Each wave has a budget (more every wave, more every stage) spent on enemies by COST, from the
## types unlocked so far (UNLOCK: wave 1 is swarmers, chargers and gunners; brutes and healers
## join later). They arrive in small groups over the first seconds of the wave, 16-34 m from you
## on open ground, and get tougher and hit harder as the waves and stages go by. A wave is over
## when all of it is dead; a short break, then the next.

const WAVES := 8
const FIRST_BREAK := 5.0 # before wave 1 (a moment to look around)
const BREAK := 7.0 # between waves
const BOSS_WARN := 4.0 # "BOSS INCOMING" before it lands
const CLEARED_TIME := 12.0 # after the boss: grab the loot, then on to the next stage
const SPAWN_EVERY := 0.9 # a group arrives this often while a wave is coming in
const SPAWN_MIN := 16.0
const SPAWN_MAX := 34.0
const MAX_ALIVE := 36 # the rest of a wave waits for room (a frame rate to keep)
const COST := {"swarmer": 2, "charger": 4, "gunner": 4, "lobber": 5, "flyer_projectile": 5, "sniper": 6,
	"flyer_beam": 6, "flyer_healer": 7, "brute": 10}
const UNLOCK := {"swarmer": 1, "charger": 1, "gunner": 1, "lobber": 2, "flyer_projectile": 2, "sniper": 3,
	"flyer_beam": 3, "brute": 4, "flyer_healer": 5}
const BOSS := "colossus"

var enemies: Enemies
var map: MapData
var stage := 1
var wave := 0
var phase := "start" # start | wave | break | boss_warn | boss | cleared | next
var t := 0.0 # time left in this phase (start, break, boss_warn, cleared)
var time := 0.0 # the whole stage so far
var kills := 0
var boss: Enemies.Enemy
var events: Array[Dictionary] = [] # wave_start, wave_clear, boss_warn, boss, stage_clear, next_stage
var rng := RandomNumberGenerator.new()
var _queue: Array[String] = [] # this wave's enemies still to come
var _wave_ids := {} # this wave's enemies still alive
var _spawn_t := 0.0


func _init(e: Enemies, m: MapData, stage_n := 1) -> void:
	enemies = e
	map = m
	stage = stage_n
	t = FIRST_BREAK
	rng.randomize()
	enemies.damage_mult = damage_mult()


## How much tougher and harder-hitting things are now (the wave and the stage).
func hp_mult() -> float:
	return (1.0 + 0.15 * maxi(0, wave - 1)) * (1.0 + 0.6 * (stage - 1))


func damage_mult() -> float:
	return (1.0 + 0.06 * maxi(0, wave - 1)) * (1.0 + 0.3 * (stage - 1))


## Gold and prices scale with the stage (so a later chest costs more, and kills pay more).
func money_mult() -> float:
	return 1.0 + 0.5 * (stage - 1)


## What a wave spends on enemies (more every wave, more every stage).
static func budget(w: int, stage_n: int) -> int:
	return int((18 + 10 * w) * (1.0 + 0.5 * (stage_n - 1)))


## Enemies of this wave left (alive + still to come).
func left() -> int:
	return _queue.size() + _wave_ids.size()


func tick(p: PlayerSim, dt: float) -> void:
	time += dt
	for d in enemies.deaths:
		kills += 1
	var living := {}
	for e in enemies.list:
		if e.alive and not e.target.dead:
			living[e.id] = true
	for id: int in _wave_ids.keys():
		if not living.has(id):
			_wave_ids.erase(id)
	match phase:
		"start", "break":
			t -= dt
			if t <= 0:
				_start_wave()
		"wave":
			_spawn_t -= dt
			if _spawn_t <= 0 and not _queue.is_empty() and enemies.list.size() < MAX_ALIVE:
				_spawn_t = SPAWN_EVERY
				_spawn_group(p)
			if _queue.is_empty() and _wave_ids.is_empty():
				events.append({"type": "wave_clear", "wave": wave})
				if wave >= WAVES:
					phase = "boss_warn"
					t = BOSS_WARN
					events.append({"type": "boss_warn"})
				else:
					phase = "break"
					t = BREAK
		"boss_warn":
			t -= dt
			if t <= 0:
				_spawn_boss(p)
		"boss":
			if boss == null or not boss.alive or boss.target.dead:
				phase = "cleared"
				t = CLEARED_TIME
				events.append({"type": "stage_clear", "stage": stage, "pos": boss.center() if boss else Vector3.ZERO})
		"cleared":
			t -= dt
			if t <= 0:
				phase = "next"
				events.append({"type": "next_stage", "stage": stage + 1})


## Jump straight to wave n (the console, for testing): this wave's enemies are dropped.
func skip_to(n: int) -> void:
	wave = clampi(n, 1, WAVES) - 1
	_queue.clear()
	_wave_ids.clear()
	phase = "break"
	t = 0.5


## Straight to the boss (the console).
func skip_to_boss() -> void:
	wave = WAVES
	_queue.clear()
	_wave_ids.clear()
	phase = "boss_warn"
	t = 1.0
	events.append({"type": "boss_warn"})


func _start_wave() -> void:
	wave += 1
	phase = "wave"
	_spawn_t = 0.0
	enemies.damage_mult = damage_mult()
	var budget := Director.budget(wave, stage)
	var types: Array = COST.keys().filter(func(k: String) -> bool: return UNLOCK[k] <= wave)
	_queue.clear()
	while budget > 0:
		var can: Array = types.filter(func(k: String) -> bool: return COST[k] <= budget)
		if can.is_empty():
			break
		var pick: String = can[rng.randi() % can.size()]
		var n := 3 if pick == "swarmer" else 1 # swarmers come in packs
		for i in n:
			_queue.append(pick)
		budget -= COST[pick] * n
	events.append({"type": "wave_start", "wave": wave, "of": WAVES, "count": _queue.size()})


## A few of the queue arrive together, somewhere around you.
func _spawn_group(p: PlayerSim) -> void:
	var n := mini(_queue.size(), 1 + rng.randi() % 3)
	var at := _spawn_point(p)
	if at == Vector3.INF:
		return # nowhere good this time: try again next group
	for i in n:
		var type: String = _queue.pop_front()
		var off := Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
		var pos := at + off
		if Enemies.TYPES[type].family == "flyer":
			pos.y += 4.0
		var e := enemies.spawn(type, pos, hp_mult())
		_wave_ids[e.id] = true


## Open ground 16-34 m from you, not too far above or below, not inside anything; INF if a few
## tries find nothing.
func _spawn_point(p: PlayerSim) -> Vector3:
	for tries in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var at := Vector3(p.px + cos(a) * r, p.py, p.pz + sin(a) * r)
		var g := enemies._ground_under(at + Vector3(0, 12, 0))
		if g < -29 or absf(g - p.py) > 12.0:
			continue
		at.y = g
		if PlayerSim.new(at.x, at.y, at.z)._blocked(map.nearby(at.x, at.y, at.z, 1.5)):
			continue
		return at
	return Vector3.INF


func _spawn_boss(p: PlayerSim) -> void:
	var at := _spawn_point(p)
	if at == Vector3.INF:
		at = Vector3(map.spawn.x, map.spawn.y, map.spawn.z)
	boss = enemies.spawn(BOSS, at, 1.0 + 0.6 * (stage - 1))
	boss.cd = 2.0 # a moment to see it before it starts
	phase = "boss"
	events.append({"type": "boss", "id": boss.id, "name": boss.def.name, "pos": at})

