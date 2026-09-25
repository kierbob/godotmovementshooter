extends SceneTree
## Builds maps/fantasy-village.tscn (stage 2) from the Medieval Village kit in assets/VillageFBX
## (Quaternius, CC0): houses put together from its walls, corners, windows, doors, roofs and
## gables, on invisible "hidden" boxes for collision (the walls as one block, each roof as two
## steep ramps you can run up), plus the town around them made of map boxes.
##   godot --headless --path . --script res://tools/make_village.gd
## Re-running it overwrites the map: edit this script for layout changes, or edit the scene in the
## editor afterwards and don't re-run.

const KIT := "res://assets/VillageFBX/"
const OUT := "res://maps/fantasy-village.tscn"
const STORY := 3.0 # wall pieces are 3 m tall (3.12 with the trim, which overlaps the next story)
## How far above the wall top a roof's surface is at the wall line, and its ridge (from the
## meshes: tools measured the top of each roof across its width).
const ROOF := {4: {"eave": 0.84, "ridge": 3.73}, 6: {"eave": 1.0, "ridge": 4.89}, 8: {"eave": 0.6, "ridge": 6.0}}
const ROOF_LENGTHS := {4: [4, 6, 8], 6: [6, 8, 10, 12, 14], 8: [8, 10, 12, 14]}

var town: MapRoot
var rng := RandomNumberGenerator.new()
var _groups := {}
var _n := 0
var _solids: Array[Rect2] = [] # footprints of houses, wagons, fields... (trees keep away)


func _init() -> void:
	rng.seed = 2026
	town = MapRoot.new()
	town.name = "FantasyVillage"
	town.map_name = "Fantasy Village"
	town.tag = "Stage 2"
	town.desc = "A big old town · a market square under a clock tower, the old town up on its hill, the river, the farms and the castle"
	town.art = "VILLAGE"
	town.grad_from = Color("6fc3ff")
	town.grad_to = Color("5a8f3c")
	town.view_scale = 1.8
	build()
	_own(town, town)
	var ps := PackedScene.new()
	var err := ps.pack(town)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("%s: %d nodes, %s" % [OUT, _n, error_string(err)])
	town.free()
	quit(0 if err == OK else 1)


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func build() -> void:
	ground()
	market()
	roads()
	old_town()
	river()
	castle()
	chapel()
	farms()
	edges()
	trees()


# ---------- the town ----------

const HALF := 160.0 # the map is 320 x 320 m
const RIVER_X0 := -96.0 # the river runs north-south between these
const RIVER_X1 := -80.0
const OLD_Y := 6.0 # the old town's plateau
const OLD := Rect2(40, -150, 110, 110) # x, z, w, d
const CASTLE_Y := 12.0


func ground() -> void:
	# the ground on both sides of the river, and the riverbed with its water
	box("Ground", "Grass", "grass", Vector3(-HALF, -1, -HALF), Vector3(RIVER_X0, 0, HALF))
	box("Ground", "Grass", "grass", Vector3(RIVER_X1, -1, -HALF), Vector3(HALF, 0, HALF))
	box("Ground", "Riverbed", "dirt", Vector3(RIVER_X0, -4, -HALF), Vector3(RIVER_X1, -3, HALF))
	box("Ground", "Water", "water", Vector3(RIVER_X0, -3, -HALF), Vector3(RIVER_X1, -2.3, HALF))


## The heart of town: a cobbled square under the clock tower, a well, market wagons and crates.
func market() -> void:
	var g := "Market"
	box(g, "Square", "cobble", Vector3(-36, -0.5, -32), Vector3(36, 0.02, 30))
	spawn("Spawn", Vector3(0, 0.02, 22), 0.0)
	# the clock tower (a pad at its foot, a belfry and spire on top)
	var t := Vector3(0, 0, -8)
	tower(g + "/ClockTower", t, 11.0, Vector3(0, 0, 1), true)
	chest(g + "/ClockTower", t + Vector3(-2.2, 11.0, 2.3), "large")

	pad(g, Vector3(-24, 0.02, 14), 0.0)
	pad(g, Vector3(24, 0.02, 14), 0.0)
	# the well
	var w := Vector3(0, 0, 10)
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, -2.2), w + Vector3(2.2, 1, -1.6))
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, 1.6), w + Vector3(2.2, 1, 2.2))
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, -1.6), w + Vector3(-1.6, 1, 1.6))
	box(g + "/Well", "Rim", "stone", w + Vector3(1.6, 0, -1.6), w + Vector3(2.2, 1, 1.6))
	box(g + "/Well", "Water", "water", w + Vector3(-1.6, 0, -1.6), w + Vector3(1.6, 0.5, 1.6))
	# market stalls: wagons and crates as cover
	for a: Array in [[Vector3(-22, 0, -2), 0.3], [Vector3(20, 0, -14), 1.9], [Vector3(-14, 0, -22), 1.3], [Vector3(26, 0, 4), -0.4], [Vector3(-28, 0, 20), 2.6]]:
		wagon(g, a[0], a[1])
	for c: Vector3 in [Vector3(-16, 0, 6), Vector3(14, 0, 2), Vector3(10, 0, -24), Vector3(-30, 0, -14), Vector3(30, 0, -26), Vector3(-8, 0, 24)]:
		crates(g, c, 2 + rng.randi() % 4)
	for c: Vector3 in [Vector3(-12, 0.02, 4), Vector3(12, 0.02, -2), Vector3(30, 0.02, 16), Vector3(-32, 0.02, -26)]:
		chest(g, c)
	# houses around the square, doors facing it
	var south := [[-28, 4], [-18, 3], [-8, 2], [8, 2], [18, 3], [28, 4]]
	for i in south.size():
		house(g + "/South", Vector3(south[i][0], 0, 40), 6, 8 if i % 2 == 0 else 6, south[i][1], "brick", Vector3(0, 0, -1))
	for z: float in [-26.0, -12.0, 2.0, 16.0]:
		house(g + "/West", Vector3(-46, 0, z), 8, 10 if z != 2.0 else 8, 2 + int(abs(z)) % 2, "brick", Vector3(1, 0, 0))
		house(g + "/East", Vector3(46, 0, z), 8, 10 if z != 2.0 else 8, 2 + (int(abs(z)) + 1) % 2, "brick", Vector3(-1, 0, 0))
	house(g + "/North", Vector3(-24, 0, -42), 6, 12, 3, "brick", Vector3(0, 0, 1))
	house(g + "/North", Vector3(24, 0, -42), 6, 12, 3, "brick", Vector3(0, 0, 1))


## Cobbled roads out of the square: north to the castle and old town, south to the farms, east to
## the chapel, west over the river.
func roads() -> void:
	var g := "Roads"
	box(g, "North", "cobble", Vector3(-6, -0.5, -HALF + 20), Vector3(6, 0.02, -32))
	box(g, "South", "cobble", Vector3(-6, -0.5, 30), Vector3(6, 0.02, 60))
	box(g, "East", "cobble", Vector3(36, -0.5, -6), Vector3(HALF - 20, 0.02, 6))
	box(g, "West", "cobble", Vector3(RIVER_X1, -0.5, -6), Vector3(-36, 0.02, 6))
	box(g, "Farm", "dirt", Vector3(-5, -0.5, 60), Vector3(5, 0.02, HALF - 16))
	for c: Vector3 in [Vector3(-10, 0.02, -60), Vector3(10, 0.02, 48), Vector3(70, 0.02, 10), Vector3(-60, 0.02, -10)]:
		chest(g, c)


## Up on a 6 m stone plateau: narrow lanes between tall houses, stairs up from the square's
## side and a ramp from the north road, and a guildhall in the middle.
func old_town() -> void:
	var g := "OldTown"
	var x0 := OLD.position.x
	var z0 := OLD.position.y
	var x1 := OLD.end.x
	var z1 := OLD.end.y
	box(g, "Plateau", "stone_dark", Vector3(x0, -1, z0), Vector3(x1, OLD_Y - 0.3, z1))
	box(g, "Top", "cobble", Vector3(x0, OLD_Y - 0.3, z0), Vector3(x1, OLD_Y, z1))
	# ways up: two stairs on its south side, a long ramp on its west side (from the north road)
	stairs(g + "/StairsSW", Vector3(56, 0, z1 + 12), Vector3(0, 0, -1), 6, int(OLD_Y))
	stairs(g + "/StairsSE", Vector3(124, 0, z1 + 12), Vector3(0, 0, -1), 6, int(OLD_Y))
	box(g, "Ramp", "cobble", Vector3(x0 - 30, 0, -126), Vector3(x0, OLD_Y, -114), "x+")
	pad(g, Vector3(90, 0.02, z1 + 6), 18.0, Vector2(0, -1), 8.0)
	# lanes of houses (rows along x, doors on the lanes)
	var y := OLD_Y
	for row: Array in [[-138, Vector3(0, 0, 1)], [-112, Vector3(0, 0, -1)], [-96, Vector3(0, 0, 1)], [-70, Vector3(0, 0, -1)], [-54, Vector3(0, 0, 1)]]:
		var z: float = row[0]
		var x := x0 + 8.0
		while x < x1 - 8:
			var w := [6, 8, 6, 4][rng.randi() % 4] as int
			var d := [8, 10, 12][rng.randi() % 3] as int
			if absf(x + w / 2.0 - 95) < 12 and z > -100 and z < -60:
				x += 26 # the guildhall's plaza
				continue
			house(g + "/Lanes", Vector3(x + w / 2.0, y, z), w, d, 2 + rng.randi() % 2, "brick" if rng.randf() < 0.6 else "plaster", row[1])
			x += w + [2, 4, 6][rng.randi() % 3]
	# the guildhall: 8 x 14, four stories, on its plaza; a chest on its ridge
	box(g, "Plaza", "stone", Vector3(80, y, -92), Vector3(110, y + 0.02, -62))
	house(g + "/Guildhall", Vector3(95, y, -77), 8, 14, 3, "brick", Vector3(0, 0, 1))
	chest(g, Vector3(95, y + 3 * STORY + ROOF[8].ridge, -77), "golden")
	pad(g, Vector3(104, y + 0.02, -77), 24.0) # straight up beside it: drift onto the roof
	for c: Vector3 in [Vector3(58, y, -125), Vector3(130, y, -83), Vector3(66, y, -62), Vector3(118, y, -125), Vector3(84, y, -104), Vector3(106, y, -46)]:
		chest(g, c)


## The river: a sunken channel with water, three bridges (stone on the west road, wood north and
## south), ramps out of the water, and a hamlet on the far bank.
func river() -> void:
	var g := "River"
	for z: float in [0.0, -95.0, 95.0]:
		var wood := z != 0.0
		var hw := 7.0 if not wood else 3.0
		box(g + "/Bridges", "Deck", "stone" if not wood else "plank", Vector3(RIVER_X0 - 2, -0.6, z - hw), Vector3(RIVER_X1 + 2, 0.4, z + hw))
		for s: float in [-1.0, 1.0]:
			if wood:
				fence(g + "/Bridges", Vector3(RIVER_X0 - 1, 0.4, z + s * (hw - 0.2)), Vector3(RIVER_X1 + 1, 0.4, z + s * (hw - 0.2)))
			else:
				box(g + "/Bridges", "Parapet", "stone", Vector3(RIVER_X0 - 2, 0.4, z + s * hw - 0.4), Vector3(RIVER_X1 + 2, 1.4, z + s * hw + 0.4))
		if not wood:
			box(g + "/Bridges", "Pier", "stone_dark", Vector3(-90, -4, -3), Vector3(-86, -0.6, 3))
	# ramps out of the water (so nothing is stuck in it)
	for z: float in [-140.0, -50.0, 45.0, 140.0]:
		box(g, "Ramp", "dirt", Vector3(RIVER_X0, -3, z - 3), Vector3(RIVER_X0 + 7, 0, z + 3), "x-")
		box(g, "Ramp", "dirt", Vector3(RIVER_X1 - 7, -3, z + 12), Vector3(RIVER_X1, 0, z + 18), "x+")
	# the hamlet on the west bank
	for h: Array in [[Vector3(-112, 0, -40), 6, 8], [Vector3(-130, 0, -22), 8, 10], [Vector3(-114, 0, 30), 6, 10], [Vector3(-134, 0, 48), 6, 6], [Vector3(-116, 0, 70), 8, 8], [Vector3(-136, 0, 88), 4, 6], [Vector3(-112, 0, 112), 6, 12]]:
		house(g + "/Hamlet", h[0], h[1], h[2], 1 + rng.randi() % 2, "plaster" if rng.randf() < 0.5 else "brick")
	for c: Vector3 in [Vector3(-88, -2.3, -30), Vector3(-104, 0, 8), Vector3(-126, 0, 64), Vector3(-104, 0, 96), Vector3(-146, 0, -6)]:
		chest(g, c)


## Castle hill in the north-west (west bank): terraces up to a keep with a walkable top, and a
## watchtower with a spire.
func castle() -> void:
	var g := "Castle"
	box(g, "Terrace1", "hill", Vector3(-HALF, -1, -HALF), Vector3(-100, 4, -84))
	box(g, "Terrace2", "hill", Vector3(-HALF, 4, -HALF), Vector3(-110, 8, -96))
	box(g, "Terrace3", "stone_dark", Vector3(-HALF, 8, -HALF), Vector3(-120, CASTLE_Y, -106))
	box(g, "RampUp1", "dirt", Vector3(-116, 0, -84), Vector3(-106, 4, -68), "z-") # from the town
	box(g, "RampUp2", "dirt", Vector3(-110, 4, -126), Vector3(-100, 8, -114), "x-")
	box(g, "RampUp3", "stone", Vector3(-140, 8, -106), Vector3(-130, CASTLE_Y, -96), "z-")
	# the keep: 22 x 22, 14 m, battlements on top
	var k0 := Vector3(-150, CASTLE_Y, -150)
	var kh := 10.0
	box(g + "/Keep", "Body", "stone", k0, k0 + Vector3(22, kh, 22))
	for i in 6:
		for s: int in [0, 1]:
			var a := 1.0 + i * 3.6
			box(g + "/Keep", "Merlon", "stone_dark", k0 + Vector3(a, kh, s * 21), k0 + Vector3(a + 1.6, kh + 1.2, s * 21 + 1))
			box(g + "/Keep", "Merlon", "stone_dark", k0 + Vector3(s * 21, kh, a), k0 + Vector3(s * 21 + 1, kh + 1.2, a + 1.6))
	chest(g, k0 + Vector3(11, kh, 11), "large")
	chest(g, k0 + Vector3(4, kh, 17))
	pad(g, k0 + Vector3(23.6, 0.02, 11), 24.0, Vector2(-1, 0), 4.0) # against the wall: up and onto the keep
	# the watchtower: a flat top with a low wall
	var t := Vector3(-126, CASTLE_Y, -114)
	tower(g + "/Tower", t, 10.5, Vector3(0, 0, 1), false)
	chest(g + "/Tower", t + Vector3(0, 10.5, 0), "large")
	for h: Array in [[Vector3(-146, 8, -102), 6, 8], [Vector3(-146, 4, -90), 6, 6], [Vector3(-124, 4, -90), 6, 6]]:
		house(g + "/Houses", h[0], h[1], h[2], 2, "brick")
	for p: Vector3 in [Vector3(-104, 4, -90), Vector3(-116, 8, -100), Vector3(-126, CASTLE_Y, -126)]:
		chest(g, p)


## The chapel quarter (east): a long chapel with a bell tower, a graveyard behind a fence, houses.
func chapel() -> void:
	var g := "Chapel"
	house(g, Vector3(100, 0, 30), 8, 14, 3, "brick", Vector3(-1, 0, 0))
	var t := Vector3(100, 0, 12)
	tower(g + "/Tower", t, 11.0, Vector3(-1, 0, 0), true)
	chest(g, t + Vector3(-2.3, 11.0, -2.2), "large")
	# the graveyard: stones in rows, a fence around
	var y0 := Vector3(116, 0, 18)
	fence(g + "/Graveyard", y0, y0 + Vector3(26, 0, 0))
	fence(g + "/Graveyard", y0 + Vector3(0, 0, 30), y0 + Vector3(26, 0, 30))
	fence(g + "/Graveyard", y0 + Vector3(26, 0, 0), y0 + Vector3(26, 0, 30))
	for i in 4:
		for j in 5:
			var at := y0 + Vector3(4 + i * 6, 0, 4 + j * 5.5)
			box(g + "/Graveyard", "Stone", "stone", at + Vector3(-0.5, 0, -0.15), at + Vector3(0.5, 1.1, 0.15))
	chest(g, y0 + Vector3(13, 0, 15), "shrine")
	for h: Array in [[Vector3(70, 0, 34), 6, 8, Vector3(0, 0, -1)], [Vector3(84, 0, 60), 6, 10, Vector3(-1, 0, 0)], [Vector3(130, 0, -30), 8, 8, Vector3(0, 0, 1)], [Vector3(96, 0, -28), 6, 12, Vector3(0, 0, 1)], [Vector3(66, 0, -26), 4, 6, Vector3(0, 0, 1)], [Vector3(140, 0, 70), 6, 8, Vector3(-1, 0, 0)]]:
		house(g + "/Houses", h[0], h[1], h[2], 2, "plaster" if rng.randf() < 0.5 else "brick", h[3])
	for c: Vector3 in [Vector3(80, 0, 16), Vector3(124, 0, 58), Vector3(146, 0, -10), Vector3(112, 0, -35)]:
		chest(g, c)


## Farms in the south: fields in rows, fences, hay, wagons, a big barn and farmhouses.
func farms() -> void:
	var g := "Farms"
	for f: Rect2 in [Rect2(-70, 70, 50, 34), Rect2(16, 70, 50, 34), Rect2(-70, 112, 50, 32), Rect2(80, 100, 50, 40)]:
		for r in int(f.size.y / 4):
			var z := f.position.y + r * 4 + 1
			box(g + "/Fields", "Row", "field", Vector3(f.position.x, 0, z), Vector3(f.end.x, 0.4, z + 2)) # low enough to walk over
		fence(g + "/Fences", Vector3(f.position.x, 0, f.position.y - 1), Vector3(f.end.x, 0, f.position.y - 1))
		fence(g + "/Fences", Vector3(f.position.x, 0, f.end.y + 1), Vector3(f.end.x, 0, f.end.y + 1))
	# the barn: 8 x 14, tall, doors to the road
	house(g + "/Barn", Vector3(40, 0, 128), 8, 14, 2, "plaster", Vector3(-1, 0, 0))
	house(g + "/Houses", Vector3(-24, 0, 128), 6, 8, 2, "brick", Vector3(1, 0, 0))
	house(g + "/Houses", Vector3(110, 0, 82), 6, 10, 1, "plaster", Vector3(0, 0, -1))
	house(g + "/Houses", Vector3(-110, 0, 140), 6, 8, 2, "brick", Vector3(1, 0, 0))
	for c: Vector3 in [Vector3(12, 0, 110), Vector3(-10, 0, 90), Vector3(70, 0, 88), Vector3(30, 0, 144)]:
		hay(g, c)
	for a: Array in [[Vector3(-12, 0, 70), 1.5], [Vector3(14, 0, 140), -0.3], [Vector3(66, 0, 120), 0.8]]:
		wagon(g, a[0], a[1])
	for c: Vector3 in [Vector3(-44, 0, 108), Vector3(44, 0, 108), Vector3(100, 0, 96), Vector3(-40, 0, 150), Vector3(8, 0, 150), Vector3(60, 0, 150)]:
		chest(g, c)
	chest(g, Vector3(40, 2 * STORY + ROOF[8].ridge, 128), "large")


## Hills all the way around, with an invisible wall above them.
func edges() -> void:
	var g := "Edges"
	for s: Array in [[Vector3(-HALF - 20, -1, -HALF - 20), Vector3(HALF + 20, 0, -HALF)], [Vector3(-HALF - 20, -1, HALF), Vector3(HALF + 20, 0, HALF + 20)],
			[Vector3(-HALF - 20, -1, -HALF), Vector3(-HALF, 0, HALF)], [Vector3(HALF, -1, -HALF), Vector3(HALF + 20, 0, HALF)]]:
		var lo: Vector3 = s[0]
		var hi: Vector3 = s[1]
		var along_x := hi.x - lo.x > hi.z - lo.z
		var n := int((hi.x - lo.x if along_x else hi.z - lo.z) / 20.0)
		for i in n:
			var h := 10.0 + rng.randf() * 18.0
			var a := lo + (Vector3(i * 20, 0, 0) if along_x else Vector3(0, 0, i * 20))
			var b := Vector3(a.x + (20 if along_x else hi.x - lo.x), h, a.z + (hi.z - lo.z if along_x else 20))
			box(g, "Hill", "hill", a, b)
		box(g, "Wall", "barrier", Vector3(lo.x, 0, lo.z), Vector3(hi.x, 70, hi.z))


## Trees here and there (not on roads, in houses or the river).
func trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 90 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-HALF + 6, HALF - 6), 0, rng.randf_range(-HALF + 6, HALF - 6))
		if absf(p.x) < 50 and absf(p.z) < 50: continue # the square
		if absf(p.x) < 10 or absf(p.z) < 10: continue # the roads
		if p.x > RIVER_X0 - 4 and p.x < RIVER_X1 + 4: continue
		if OLD.grow(6).has_point(Vector2(p.x, p.z)): continue
		if p.x < -96 and p.z < -80: continue # the castle
		if _near_building(p, 7.0): continue
		tree("Trees", p, 0.8 + rng.randf() * 0.7)
		placed += 1


func _near_building(p: Vector3, r: float) -> bool:
	for b in _solids:
		if b.grow(r).has_point(Vector2(p.x, p.z)):
			return true
	return false


# ---------- building blocks ----------

## A group node (by path, "A/B"), made on first use.
func group(path: String) -> Node3D:
	if _groups.has(path):
		return _groups[path]
	var parent: Node3D = town
	var parts := path.split("/")
	if parts.size() > 1:
		parent = group("/".join(parts.slice(0, parts.size() - 1)))
	var g := Node3D.new()
	g.name = parts[-1]
	parent.add_child(g)
	_groups[path] = g
	return g


func _name(g: Node3D, base: String) -> String:
	_n += 1
	return "%s%d" % [base, g.get_child_count() + 1]


static func r3(v: float) -> float:
	return round(v * 1000.0) / 1000.0


## A solid box from lo to hi (ramp: "x+" / "x-" / "z+" / "z-", rising that way).
func box(grp: String, base: String, kind: String, lo: Vector3, hi: Vector3, ramp := "none") -> MapBox:
	var g := group(grp)
	var b := MapBox.new()
	b.name = _name(g, base)
	b.kind = kind
	b.ramp = ramp
	b.box = PackedFloat64Array([r3(minf(lo.x, hi.x)), r3(minf(lo.y, hi.y)), r3(minf(lo.z, hi.z)),
		r3(maxf(lo.x, hi.x)), r3(maxf(lo.y, hi.y)), r3(maxf(lo.z, hi.z))])
	g.add_child(b)
	return b


## A kit piece at pos, turned yaw (radians).
func model(grp: String, file: String, pos: Vector3, yaw := 0.0, size := 1.0) -> MapModel:
	var g := group(grp)
	var m := MapModel.new()
	m.name = _name(g, file.get_basename().replace("_", ""))
	m.model = KIT + file + ".fbx"
	m.at = PackedFloat64Array([r3(pos.x), r3(pos.y), r3(pos.z)])
	m.yaw = r3(wrapf(yaw, -PI, PI))
	m.size = size
	g.add_child(m)
	return m


func spawn(base: String, pos: Vector3, yaw: float) -> void:
	var g := group("Spawns")
	var s := MapSpawn.new()
	s.name = _name(g, base)
	s.at = PackedFloat64Array([pos.x, pos.y, pos.z])
	s.yaw = yaw
	g.add_child(s)


func chest(grp: String, pos: Vector3, size := "any", yaw := 0.0) -> void:
	var g := group(grp)
	var c := MapChest.new()
	c.name = _name(g, "Chest")
	c.at = PackedFloat64Array([r3(pos.x), r3(pos.y), r3(pos.z)])
	c.size = size
	c.yaw = yaw
	g.add_child(c)


func pad(grp: String, pos: Vector3, launch := 0.0, dir := Vector2.ZERO, forward := 0.0) -> void:
	var g := group(grp)
	var p := MapPad.new()
	p.name = _name(g, "Pad")
	p.at = PackedFloat64Array([r3(pos.x), r3(pos.y), r3(pos.z)])
	p.launch = launch
	if dir != Vector2.ZERO:
		p.directional = true
		p.dir_x = dir.normalized().x
		p.dir_z = dir.normalized().y
		p.forward = forward
	g.add_child(p)


## Stairs from `base` (the bottom step's front edge, center) climbing along `dir`, `width` m wide
## (even), `rise` m (a meter per 2 m, like the kit's steps), with a ramp under them.
func stairs(grp: String, base: Vector3, dir: Vector3, width: int, rise: int) -> void:
	var across := Vector3(dir.z, 0, -dir.x)
	var yaw := atan2(dir.x, dir.z) + PI
	for k in rise:
		for j in width / 2:
			var off := across * (-(width / 2 - 1) + 2 * j)
			var piece := "Stairs_Exterior_Straight_Center"
			if j == 0:
				piece = "Stairs_Exterior_Straight_R"
			elif j == width / 2 - 1:
				piece = "Stairs_Exterior_Straight_L"
			model(grp, piece, base + dir * (1 + 2 * k) + off + Vector3(0, k, 0), yaw)
	var a := base - across * (width / 2.0)
	var b := base + across * (width / 2.0) + dir * (2 * rise)
	var ramp := ("x+" if dir.x > 0 else "x-") if dir.x != 0 else ("z+" if dir.z > 0 else "z-")
	box(grp, "Ramp", "hidden", Vector3(minf(a.x, b.x), base.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), base.y + rise, maxf(a.z, b.z)), ramp)


## A wooden fence from a to b (straight along x or z): kit fence pieces on a low solid rail you can
## jump.
func fence(grp: String, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var n := maxi(1, int(round(d.length() / 2.0)))
	var yaw := atan2(d.x, d.z) + PI / 2
	for i in n:
		model(grp, "Prop_WoodenFence_Single" if i % 3 == 0 else "Prop_WoodenFence_Extension%d" % (1 + i % 2), a + d * ((i + 0.5) / n), yaw)
	var lo := a.min(b) - Vector3(0.15, 0, 0.15)
	var hi := a.max(b) + Vector3(0.15, 0.85, 0.15)
	box(grp, "Rail", "hidden", lo, hi)


func wagon(grp: String, p: Vector3, yaw: float) -> void:
	# snap the turn to a quarter so the (axis-aligned) collision fits the wagon
	var q := roundi(yaw / (PI / 2))
	var y := q * PI / 2
	model(grp + "/Wagons", "Prop_Wagon", p + Basis(Vector3.UP, y) * Vector3(0, 0, 1.1), y)
	var along_z := q % 2 == 0
	var half := Vector3(1.0, 0, 2.0) if along_z else Vector3(2.0, 0, 1.0)
	box(grp + "/Wagons", "Wagon", "hidden", p - half, p + half + Vector3(0, 1.4, 0))
	_solids.append(Rect2(p.x - half.x, p.z - half.z, half.x * 2, half.z * 2))


## A stack of crates (n of them, up to two high).
func crates(grp: String, p: Vector3, n: int) -> void:
	for i in n:
		var at := p + Vector3((i % 2) * 1.1, (i / 2 % 2) * 1.06 if i >= 2 else 0.0, (i / 4) * 1.1)
		model(grp + "/Crates", "Prop_Crate", at, rng.randf_range(-0.1, 0.1))
		box(grp + "/Crates", "Crate", "hidden", at - Vector3(0.52, 0, 0.52), at + Vector3(0.52, 1.05, 0.52))


func hay(grp: String, p: Vector3) -> void:
	box(grp + "/Hay", "Bale", "hay", p + Vector3(-2, 0, -1), p + Vector3(2, 1.4, 1))
	box(grp + "/Hay", "Bale", "hay", p + Vector3(-1, 1.4, -1), p + Vector3(1.4, 2.6, 1))
	_solids.append(Rect2(p.x - 2, p.z - 1, 4, 2))


## A cartoon tree: a trunk and a few stacked boxes of leaves.
func tree(grp: String, p: Vector3, s: float) -> void:
	var h := 3.0 * s
	box(grp, "Trunk", "trunk", p + Vector3(-0.4, 0, -0.4) * s, p + Vector3(0.4 * s, h, 0.4 * s))
	box(grp, "Leaves", "leaves", p + Vector3(-2.2 * s, h, -2.2 * s), p + Vector3(2.2 * s, h + 2.4 * s, 2.2 * s))
	box(grp, "Leaves", "leaves", p + Vector3(-1.4 * s, h + 2.4 * s, -1.4 * s), p + Vector3(1.4 * s, h + 4.0 * s, 1.4 * s))


## A stone tower: 8 x 8 on a wider base, a walkable top at `top` (a pad reaches ~13 m) with a
## low wall around it, a launch pad at its foot on the `face` side (you slide up the wall and over
## the edge; the top is flush with the wall so nothing stops you on the way), and optionally a
## belfry with the kit's spire on top.
func tower(grp: String, t: Vector3, top: float, face: Vector3, belfry: bool) -> void:
	box(grp, "Base", "stone_dark", t + Vector3(-5, 0, -5), t + Vector3(5, 1.2, 5))
	box(grp, "Body", "stone", t + Vector3(-4, 1.2, -4), t + Vector3(4, top - 0.5, 4))
	box(grp, "Top", "stone_dark", t + Vector3(-4, top - 0.5, -4), t + Vector3(4, top, 4))
	for s: float in [-1.0, 1.0]:
		box(grp, "Rail", "stone", t + Vector3(-4, top, 3.6 * s - 0.4), t + Vector3(4, top + 0.9, 3.6 * s + 0.4))
		box(grp, "Rail", "stone", t + Vector3(3.6 * s - 0.4, top, -3.2), t + Vector3(3.6 * s + 0.4, top + 0.9, 3.2))
	if belfry:
		spire(grp, t + Vector3(0, top, 0), 2.2, 5.0)
	pad(grp, t + face * 6.2 + Vector3(0, 0.02, 0), 24.0, Vector2(-face.x, -face.z), 4.0)


## A tower's pointed roof (the kit's) on top of `p`, with stepped collision under it.
func spire(grp: String, p: Vector3, half: float, h: float) -> void:
	model(grp, "Roof_Tower_RoundTiles", p + Vector3(0, h, 0), 0.0, half / 2.4)
	box(grp, "Belfry", "stone", p + Vector3(-half + 0.4, 0, -half + 0.4), p + Vector3(half - 0.4, h, half - 0.4))
	box(grp, "Spire", "hidden", p + Vector3(-half * 0.6, h, -half * 0.6), p + Vector3(half * 0.6, h + 2.0, half * 0.6))


# ---------- houses ----------

## A house centered at c (on the ground at c.y): w x d meters (even; the roof spans the shorter
## side, which must be 4, 6 or 8), `floors` stories of STORY m. style: "brick" (a stone ground floor,
## plaster above) or "plaster". facing: the side with the door (+z, or +x when it's wider along
## z, unless given).
func house(grp: String, c: Vector3, w: int, d: int, floors: int, style := "brick", facing := Vector3.ZERO) -> void:
	var g := grp + "/House%d" % (group(grp).get_child_count() + 1)
	var across_x := w <= d # the roof spans x (its ridge runs along z)
	var span := w if across_x else d
	var length := d if across_x else w
	assert(ROOF.has(span), "a house's short side must be 4, 6 or 8")
	var x0 := c.x - w / 2.0
	var x1 := c.x + w / 2.0
	var z0 := c.z - d / 2.0
	var z1 := c.z + d / 2.0
	var top := c.y + floors * STORY
	# walls, story by story: a door on the front of the ground floor, windows around
	var front := facing if facing != Vector3.ZERO else (Vector3(0, 0, 1) if across_x else Vector3(1, 0, 0))
	for f in floors:
		var y := c.y + f * STORY
		var stone := style == "brick" and f == 0
		var mat := "UnevenBrick" if stone else "Plaster"
		for side: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
			var along := Vector3(side.z, 0, -side.x).abs()
			var n := (w if side.x == 0 else d) / 2
			var edge := Vector3(c.x + side.x * w / 2.0, y, c.z + side.z * d / 2.0)
			var yaw := atan2(side.x, side.z)
			for i in n:
				var p := edge + along * (-(n - 1) + 2 * i)
				var piece := "Wall_%s_Straight" % mat
				if f == 0 and side == front and i == n / 2:
					piece = "Wall_%s_Door_Round" % mat
					# the door sits in the arch, hinged on its left edge
					model(g, "Door_%d_Round" % [1, 2, 4, 8][rng.randi() % 4], p - Vector3(side.z, 0, -side.x) * 0.5, yaw)
				elif rng.randf() < 0.6:
					var kind: String = ["Wide_Round", "Thin_Round", "Wide_Flat"][rng.randi() % 3]
					piece = "Wall_%s_Window_%s" % [mat, kind]
					model(g, "Window_%s1" % kind.replace("_", "_"), p, yaw) # the frame and its glass
					if rng.randf() < 0.35:
						model(g, "WindowShutters_%s_%s" % [kind, "Open" if rng.randf() < 0.6 else "Closed"], p, yaw)
				elif not stone and rng.randf() < 0.4:
					piece = "Wall_Plaster_WoodGrid"
				model(g, piece, p, yaw)
		# corners
		for cx: float in [x0, x1]:
			for cz: float in [z0, z1]:
				model(g, "Corner_Exterior_Brick" if stone else "Corner_Exterior_Wood", Vector3(cx, y, cz), atan2(sign(cx - c.x), sign(cz - c.z)) - PI / 4)
	# the roof, its gable ends, and the collision
	var info: Dictionary = ROOF[span]
	var rl := _roof_length(span, length)
	model(g, "Roof_RoundTiles_%dx%d" % [span, rl], Vector3(c.x, top, c.z), 0.0 if across_x else PI / 2)
	for s: float in [-1.0, 1.0]:
		var at := Vector3(c.x, top, c.z + s * length / 2.0) if across_x else Vector3(c.x + s * length / 2.0, top, c.z)
		model(g, "Roof_Front_Brick%d" % span, at, (0.0 if s > 0 else PI) + (0.0 if across_x else PI / 2))
	if rng.randf() < 0.6: # a chimney through one side of the roof
		var off := (span / 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var along_off := (length / 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := Vector3(c.x + off, top, c.z + along_off) if across_x else Vector3(c.x + along_off, top, c.z + off)
		model(g, "Prop_Chimney" if rng.randf() < 0.5 else "Prop_Chimney2", at, 0.0, 1.0)
	_solids.append(Rect2(x0, z0, w, d))
	var eave := top + float(info.eave)
	var ridge := top + float(info.ridge)
	box(g, "Walls", "hidden", Vector3(x0 - 0.1, c.y, z0 - 0.1), Vector3(x1 + 0.1, eave, z1 + 0.1))
	if across_x:
		box(g, "RoofL", "hidden", Vector3(x0 - 0.1, eave, z0), Vector3(c.x, ridge, z1), "x+")
		box(g, "RoofR", "hidden", Vector3(c.x, eave, z0), Vector3(x1 + 0.1, ridge, z1), "x-")
	else:
		box(g, "RoofL", "hidden", Vector3(x0, eave, z0 - 0.1), Vector3(x1, ridge, c.z), "z+")
		box(g, "RoofR", "hidden", Vector3(x0, eave, c.z), Vector3(x1, ridge, z1 + 0.1), "z-")


## The roof model length for a house `length` long (the nearest the kit has).
func _roof_length(span: int, length: int) -> int:
	var best: int = ROOF_LENGTHS[span][0]
	for l: int in ROOF_LENGTHS[span]:
		if absi(l - length) < absi(best - length):
			best = l
	return best
