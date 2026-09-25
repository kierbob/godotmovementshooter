class_name Loot
extends RefCounted
## The run's economy, Risk of Rain style: kills pay gold, chests around the stage cost gold, and
## opening one pops an item out that floats until you walk into it. Pure logic in the sim tick
## (after the enemies); LootView draws it from `chests`, `drops` and the `events` queue.
##
## Chest spots are MapChest nodes in the map; each run opens a random handful of them
## (CHESTS_PER_RUN), a spot marked "any" becoming a large chest now and then.

## Gold per kill, by enemy type (tougher ones pay more).
const GOLD := {
	"swarmer": 3, "charger": 7, "gunner": 7, "lobber": 8, "sniper": 9, "brute": 18,
	"flyer_projectile": 8, "flyer_beam": 9, "flyer_healer": 10,
}
## Chests: cost and rarity odds in % (a small chest is Risk of Rain's: 79 / 20 / 1).
const CHESTS := {
	"small": {"name": "Chest", "cost": 25, "odds": {"common": 79.0, "uncommon": 20.0, "rare": 1.0}},
	"large": {"name": "Large Chest", "cost": 50, "odds": {"uncommon": 80.0, "rare": 20.0}},
}
const CHESTS_PER_RUN := 14
const LARGE_CHANCE := 0.25 # an "any" spot is a large chest this often
const REACH := 2.6 # how close you have to be to open one
const PICKUP_R := 1.3 # walk this close to an item to take it
const HOVER := 1.0 # items float this high over the ground
const GRAVITY := 20.0


class Chest:
	var id := 0
	var pos := Vector3.ZERO # on the ground
	var size := "small"
	var yaw := 0.0
	var opened := false


class Drop:
	var id := 0
	var item := ""
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var landed := false
	var from := Vector3.ZERO # the chest it came out of (if it falls out of the world, back there)
	var taken := false


var map: MapData
var up: Upgrades
var gold := 0
var chests: Array[Chest] = []
var drops: Array[Drop] = []
var events: Array[Dictionary] = [] # gold, chest_open, pickup, deny: for the view, HUD and sounds
var rng := RandomNumberGenerator.new()
var _next_id := 1


func _init(m: MapData, u: Upgrades) -> void:
	map = m
	up = u
	rng.randomize()


## Put this run's chests on a random pick of the map's chest spots.
func place_chests(count := CHESTS_PER_RUN) -> void:
	var spots: Array = map.chests.duplicate()
	for i in spots.size(): # shuffle with our own rng (tests seed it)
		var j := rng.randi_range(i, spots.size() - 1)
		var tmp: Variant = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for s: Dictionary in spots.slice(0, count):
		var size: String = s.size
		if size == "any":
			size = "large" if rng.randf() < LARGE_CHANCE else "small"
		add_chest(Vector3(s.x, s.y, s.z), size, float(s.get("yaw", 0.0)))


func add_chest(pos: Vector3, size: String, yaw := 0.0) -> Chest:
	var c := Chest.new()
	c.id = _next_id
	_next_id += 1
	c.pos = pos
	c.size = size
	c.yaw = yaw
	chests.append(c)
	return c


static func cost(c: Chest) -> int:
	return CHESTS[c.size].cost


## The closed chest you're close enough to open (the nearest), or null.
func chest_in_reach(p: PlayerSim) -> Chest:
	var best: Chest = null
	var best_d := REACH
	var me := Vector3(p.px, p.py, p.pz)
	for c in chests:
		if c.opened or absf(c.pos.y - p.py) > 2.0:
			continue
		var d := Vector2(c.pos.x - me.x, c.pos.z - me.z).length()
		if d < best_d:
			best = c
			best_d = d
	return best


## Try to open it: pay, roll an item, throw it out toward you. False if you can't afford it.
func open(c: Chest, p: PlayerSim) -> bool:
	if c.opened:
		return false
	if gold < cost(c):
		events.append({"type": "deny", "pos": c.pos})
		return false
	gold -= cost(c)
	c.opened = true
	var item := roll_item(c.size)
	var d := Drop.new()
	d.id = _next_id
	_next_id += 1
	d.item = item
	d.from = c.pos + Vector3(0, 1.0, 0)
	d.pos = d.from
	var toward := Vector3(p.px - c.pos.x, 0, p.pz - c.pos.z)
	toward = toward.normalized() if toward.length() > 0.1 else Vector3.FORWARD
	d.vel = toward * 2.2 + Vector3(0, 7.5, 0) # a little hop out toward you
	drops.append(d)
	events.append({"type": "chest_open", "id": c.id, "pos": c.pos, "item": item, "rarity": Upgrades.LIST[item].rarity})
	return true


## A random item for this chest size, by its rarity odds.
func roll_item(size: String) -> String:
	var odds: Dictionary = CHESTS[size].odds
	var roll := rng.randf() * 100.0
	var rarity := "common"
	for r: String in odds:
		if roll < odds[r]:
			rarity = r
			break
		roll -= odds[r]
	var ids: Array = Upgrades.LIST.keys().filter(func(k: String) -> bool: return Upgrades.LIST[k].rarity == rarity)
	return ids[rng.randi() % ids.size()]


## Gold for kills (Enemies.deaths, this tick's), items flying and landing, and picking them up.
func tick(p: PlayerSim, deaths: Array[Dictionary], dt: float) -> void:
	for dth in deaths:
		var amount: int = GOLD.get(dth.type, 5)
		gold += amount
		events.append({"type": "gold", "amount": amount, "pos": dth.pos})
	for d in drops:
		d.age += dt
		if not d.landed:
			d.vel.y -= GRAVITY * dt
			var next := d.pos + d.vel * dt
			var ground := _ground_under(next)
			if d.vel.y < 0 and next.y <= ground + HOVER:
				next.y = ground + HOVER
				d.landed = true
			elif next.y < -30.0:
				next = d.from # fell out of the world: back to its chest
				d.vel = Vector3.ZERO
			d.pos = next
		if d.age > 0.5 and not p.dead:
			var off := Vector3(p.px, p.py + 0.9, p.pz) - d.pos
			if Vector2(off.x, off.z).length() < PICKUP_R and absf(off.y) < 1.8:
				d.taken = true
				up.add(d.item)
				events.append({"type": "pickup", "item": d.item, "count": up.count(d.item), "pos": d.pos})
	drops = drops.filter(func(d: Drop) -> bool: return not d.taken)


func _ground_under(at: Vector3) -> float:
	var o := at + Vector3(0, 0.5, 0)
	var best := -60.0
	for b in map.ray_boxes(o, Vector3.DOWN, 60.0):
		if b.kind == "barrier":
			continue
		var h := Combat.ray_box(o, Vector3.DOWN, b, 60.0)
		if not h.is_empty():
			best = maxf(best, o.y - float(h[0]))
	return best
