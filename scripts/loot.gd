class_name Loot
extends RefCounted
## The run's economy, Risk of Rain style: kills pay gold (and XP), and gold buys items from the
## things placed around the stage. Pure logic in the sim tick (after the enemies); LootView draws
## it from `chests`, `drops` and the `events` queue.
##
## What you can find (CHESTS; `size` on a Chest is which one it is):
##   small / large       a random item: 79/20/1 common/uncommon/rare, or 80/20 uncommon/rare
##   golden              expensive, rare to find: always a legendary
##   damage / utility /  themed chests: only that kind of item (guns and damage, movement and kills,
##   healing             or staying alive), at a small chest's odds
##   shop                three terminals in a row, each showing its item: buy one, the others shut
##   shrine              pay to pray: sometimes an item, sometimes nothing; pricier every try, and
##                       it runs dry after two gifts
##   barrel              free: smash it for a little gold
## Chest spots are MapChest nodes in the map. Each run fills CHESTS_PER_RUN of them (what goes
## where: see KIND_WEIGHTS; a spot can also ask for a kind) and puts barrels on some of the rest.

## Gold per kill, by enemy type (tougher ones pay more). XP is the same.
const GOLD := {
	"swarmer": 3, "charger": 7, "gunner": 7, "lobber": 8, "sniper": 9, "brute": 18,
	"flyer_projectile": 8, "flyer_beam": 9, "flyer_healer": 10,
}
const SMALL_ODDS := {"common": 79.0, "uncommon": 20.0, "rare": 1.0}
const CHESTS := {
	"small": {"name": "Chest", "cost": 25, "odds": SMALL_ODDS},
	"large": {"name": "Large Chest", "cost": 50, "odds": {"uncommon": 80.0, "rare": 20.0}},
	"golden": {"name": "Golden Chest", "cost": 150, "odds": {"legendary": 100.0}},
	"damage": {"name": "Damage Chest", "cost": 30, "odds": SMALL_ODDS, "tags": ["damage", "gun", "status"]},
	"utility": {"name": "Utility Chest", "cost": 30, "odds": SMALL_ODDS, "tags": ["move", "kill", "luck"]},
	"healing": {"name": "Healing Chest", "cost": 30, "odds": SMALL_ODDS, "tags": ["defense"]},
	"shop": {"name": "Terminal", "cost": 35, "odds": {"common": 70.0, "uncommon": 27.0, "rare": 3.0}},
	"shrine": {"name": "Shrine of Chance", "cost": 20, "odds": {"common": 70.0, "uncommon": 25.0, "rare": 5.0}},
	"barrel": {"name": "Barrel", "cost": 0, "odds": {}},
}
## What an "any" spot becomes (weights). Spots can also ask for one kind ("large", "golden"...).
const KIND_WEIGHTS := {"small": 44, "large": 14, "damage": 9, "utility": 9, "healing": 7, "shrine": 8, "shop": 6, "golden": 3}
const CHESTS_PER_RUN := 14
const BARRELS_PER_RUN := 8
const SHRINE := {"chance": 0.45, "gifts": 2, "cost_up": 1.5}
const SHOP_GAP := 1.7 # meters between a shop's terminals
const REACH := 2.6 # how close you have to be to open one
const PICKUP_R := 1.3 # walk this close to an item to take it
const HOVER := 1.0 # items float this high over the ground
const GRAVITY := 20.0


class Chest:
	var id := 0
	var pos := Vector3.ZERO # on the ground
	var size := "small" # which kind (a key of CHESTS)
	var yaw := 0.0
	var cost := 0
	var opened := false
	var item := "" # shop terminals: the item on show
	var group := 0 # shop terminals: buying one shuts the rest of its group
	var gifts := 0 # shrines: items given so far


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
var events: Array[Dictionary] = [] # gold, chest_open, pickup, deny, shrine_fail, barrel
var rng := RandomNumberGenerator.new()
var _next_id := 1


func _init(m: MapData, u: Upgrades) -> void:
	map = m
	up = u
	rng.randomize()


## Fill this run's chests on a random pick of the map's chest spots, barrels on some of the rest.
func place_chests(count := CHESTS_PER_RUN, barrels := BARRELS_PER_RUN) -> void:
	var spots: Array = map.chests.duplicate()
	for i in spots.size(): # shuffle with our own rng (tests seed it)
		var j := rng.randi_range(i, spots.size() - 1)
		var tmp: Variant = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for s: Dictionary in spots.slice(0, count):
		var kind: String = s.size
		if kind == "any":
			kind = _pick_kind()
		elif kind == "large" and rng.randf() < 0.15:
			kind = "golden" # the good spots (up high, tucked away) sometimes hold the best
		var at := Vector3(s.x, s.y, s.z)
		var yaw := float(s.get("yaw", 0.0))
		if kind == "shop" and not _place_shop(at, yaw):
			kind = "small" # no room for three terminals here
		if kind != "shop":
			add_chest(at, kind, yaw)
	for s: Dictionary in spots.slice(count, count + barrels):
		add_chest(Vector3(s.x, s.y, s.z), "barrel", float(s.get("yaw", 0.0)))


func _pick_kind() -> String:
	var total := 0
	for k: String in KIND_WEIGHTS:
		total += KIND_WEIGHTS[k]
	var roll := rng.randi() % total
	for k: String in KIND_WEIGHTS:
		roll -= KIND_WEIGHTS[k]
		if roll < 0:
			return k
	return "small"


## Three terminals side by side (facing the same way as the spot), each with its item rolled now
## and on show. False if there's no floor for all three.
func _place_shop(at: Vector3, yaw: float) -> bool:
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var spots: Array[Vector3] = []
	for i: int in [-1, 0, 1]:
		var p := at + side * (SHOP_GAP * i)
		var g := _ground_under(p + Vector3(0, 1.0, 0))
		if absf(g - at.y) > 0.3:
			return false
		p.y = g
		if PlayerSim.new(p.x, p.y, p.z)._blocked(map.nearby(p.x, p.y, p.z, 1.0)):
			return false # a wall in the way
		spots.append(p)
	var group := _next_id
	var taken := {}
	for p in spots:
		var c := add_chest(p, "shop", yaw)
		c.group = group
		for tries in 10: # three different items
			c.item = roll_item("shop")
			if not taken.has(c.item):
				break
		taken[c.item] = true
	return true


func add_chest(pos: Vector3, size: String, yaw := 0.0) -> Chest:
	var c := Chest.new()
	c.id = _next_id
	_next_id += 1
	c.pos = pos
	c.size = size
	c.yaw = yaw
	c.cost = CHESTS[size].cost
	if size == "shop" and c.item == "":
		c.item = roll_item("shop")
	chests.append(c)
	return c


static func cost(c: Chest) -> int:
	return c.cost


## What the prompt says ("OPEN CHEST", "BUY DRONE BUDDY", "PRAY", "SMASH BARREL").
static func action(c: Chest) -> String:
	match c.size:
		"shop":
			return "BUY " + String(Upgrades.LIST[c.item].name).to_upper()
		"shrine":
			return "PRAY AT THE SHRINE"
		"barrel":
			return "SMASH BARREL"
	return "OPEN " + String(CHESTS[c.size].name).to_upper()


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


## Use it: pay, then whatever it does. False if you can't afford it (or it's used up).
func open(c: Chest, p: PlayerSim) -> bool:
	if c.opened:
		return false
	if gold < c.cost:
		events.append({"type": "deny", "pos": c.pos})
		return false
	gold -= c.cost
	match c.size:
		"barrel":
			c.opened = true
			var amount := rng.randi_range(6, 14)
			gold += amount
			up.add_xp(amount * 0.5, p)
			events.append({"type": "barrel", "id": c.id, "pos": c.pos, "amount": amount})
			return true
		"shrine":
			if rng.randf() >= SHRINE.chance:
				c.cost = int(round(c.cost * SHRINE.cost_up))
				events.append({"type": "shrine_fail", "id": c.id, "pos": c.pos})
				return true
			c.gifts += 1
			c.cost = int(round(c.cost * SHRINE.cost_up))
			c.opened = c.gifts >= SHRINE.gifts
			_drop(c, roll_item("shrine"), p)
			return true
		"shop":
			for o in chests:
				if o.group == c.group:
					o.opened = true
			_drop(c, c.item, p)
			return true
	c.opened = true
	_drop(c, roll_item(c.size), p)
	return true


func _drop(c: Chest, item: String, p: PlayerSim) -> void:
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
	events.append({"type": "chest_open", "id": c.id, "kind": c.size, "pos": c.pos, "item": item,
		"rarity": Upgrades.LIST[item].rarity})


## A random item for this kind of chest: its rarity odds, only its tags (themed chests). A themed
## chest that rolls a rarity it has nothing in gives one of its own tags at any rarity instead.
func roll_item(kind: String) -> String:
	var info: Dictionary = CHESTS[kind]
	var odds: Dictionary = info.odds
	var roll := rng.randf() * 100.0
	var rarity: String = odds.keys()[0]
	for r: String in odds:
		if roll < odds[r]:
			rarity = r
			break
		roll -= odds[r]
	var tags: Array = info.get("tags", [])
	var ids: Array = Upgrades.LIST.keys().filter(func(k: String) -> bool:
		return Upgrades.LIST[k].rarity == rarity and (tags.is_empty() or Upgrades.LIST[k].tag in tags))
	if ids.is_empty():
		ids = Upgrades.LIST.keys().filter(func(k: String) -> bool:
			return Upgrades.LIST[k].tag in tags and Upgrades.LIST[k].rarity != "legendary")
	return ids[rng.randi() % ids.size()]


## Gold (and XP) for kills (Enemies.deaths, this tick's), items flying and landing, picking them up.
func tick(p: PlayerSim, deaths: Array[Dictionary], dt: float) -> void:
	for dth in deaths:
		var amount: int = GOLD.get(dth.type, 5)
		gold += amount
		events.append({"type": "gold", "amount": amount, "pos": dth.pos})
		up.add_xp(amount, p) # XP: the same as the gold (tougher kills, more of both)
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
