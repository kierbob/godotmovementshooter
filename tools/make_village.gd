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
	var out := OUT
	if "--audit" in OS.get_cmdline_user_args():
		# one house of every size and height in a row, to look at from all sides
		out = "res://maps/zz-audit.tscn"
		town.map_name = "Audit"
		audit()
	else:
		build()
		var problems := check_layout()
		for pr in problems:
			print("  LAYOUT: ", pr)
		if not problems.is_empty():
			print("%d layout problems" % problems.size())
	_own(town, town)
	var ps := PackedScene.new()
	var err := ps.pack(town)
	if err == OK:
		err = ResourceSaver.save(ps, out)
	print("%s: %d nodes, %s" % [out, _n, error_string(err)])
	town.free()
	quit(0 if err == OK else 1)


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func audit() -> void:
	box("Ground", "Grass", "grass", Vector3(-100, -1, -60), Vector3(100, 0, 60))
	spawn("Spawn", Vector3(0, 0, 40), 0.0)
	var z := -36.0
	for span: int in [4, 6, 8]:
		var x := -80.0
		for l: int in ROOF_LENGTHS[span]:
			for floors: int in [1, 3]:
				house("Houses", Vector3(x, 0, z), span, l, floors, "brick" if floors > 1 else "plaster")
				x += span + 8
		z += 30.0


func build() -> void:
	ground()
	terraces()
	roads()
	market()
	lower_town()
	upper_town()
	high_town()
	chapel()
	river()
	castle()
	farms()
	edges()
	trees()


# ---------- the town ----------
# Levels: the market and the lowlands at 0; the upper town terrace (4 m) across the north with
# the high town (8 m) behind it; the chapel rise (3 m) in the east; castle hill (4, 8, 12 m) in the
# north-west past the river, which runs sunken down the west side. Streets are cobbled boxes a
# hair above their level; houses line them, doors to the street, alleys between.

const HALF := 160.0 # the map is 320 x 320 m
const RIVER_X0 := -96.0 # the river runs north-south between these
const RIVER_X1 := -80.0
const UPPER_Y := 4.0
const UPPER := Rect2(-30, -160, 190, 116) # x -30..160, z -160..-44 (to the map's edge: no ditch behind)
const HIGH_Y := 8.0
const HIGH := Rect2(40, -160, 120, 60) # x 40..160, z -160..-100
const RISE_Y := 3.0
const RISE := Rect2(92, -20, 68, 90) # x 92..160, z -20..70
const CASTLE_Y := 12.0

var _roads: Array[Rect2] = [] # streets (trees keep off them)
var _houses: Array = [] # [footprint Rect2, ground y] of every house (check_layout)
var _blocks: Array[Rect2] = [] # stairs, wagons, towers... (houses mustn't overlap them)


## Houses that overlap each other, a street, a field or stairs, or hang over a level change.
func check_layout() -> Array[String]:
	var out: Array[String] = []
	for i in _houses.size():
		var r: Rect2 = _houses[i][0]
		var y: float = _houses[i][1]
		var inner := r.grow(-0.05)
		for j in range(i + 1, _houses.size()):
			if inner.intersects((_houses[j][0] as Rect2).grow(-0.05)):
				out.append("houses overlap at %s and %s" % [r, _houses[j][0]])
		for rd in _roads:
			if inner.intersects(rd):
				out.append("house %s on a street %s" % [r, rd])
		for b in _blocks:
			if inner.intersects(b):
				out.append("house %s on %s" % [r, b])
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, r.get_center()]:
			var q := p + (r.get_center() - p).normalized() * 0.3
			if absf(level_at(q.x, q.y) - y) > 0.05 and absf(level_at(q.x, q.y) + 0.02 - y) > 0.05:
				out.append("house %s at y %.2f hangs over ground at %.1f (%s)" % [r, y, level_at(q.x, q.y), q])
				break
	return out


## The ground height at (x, z) (the level it's on).
func level_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if x <= -120 and z <= -106: return CASTLE_Y
	if x <= -110 and z <= -96: return 8.0
	if x <= -100 and z <= -84: return 4.0
	if HIGH.has_point(p): return HIGH_Y
	if UPPER.has_point(p): return UPPER_Y
	if RISE.has_point(p): return RISE_Y
	return 0.0


func ground() -> void:
	# the ground on both sides of the river, and the riverbed with its water
	box("Ground", "Grass", "grass", Vector3(-HALF, -1, -HALF), Vector3(RIVER_X0, 0, HALF))
	box("Ground", "Grass", "grass", Vector3(RIVER_X1, -1, -HALF), Vector3(HALF, 0, HALF))
	box("Ground", "Riverbed", "dirt", Vector3(RIVER_X0, -4, -HALF), Vector3(RIVER_X1, -3, HALF))
	box("Ground", "Water", "water", Vector3(RIVER_X0, -3, -HALF), Vector3(RIVER_X1, -2.3, HALF))


## A raised level: stone retaining walls with grass on top.
func terrace(grp: String, r: Rect2, y: float, top := "grass") -> void:
	box(grp, "Wall", "stone_dark", Vector3(r.position.x, -1, r.position.y), Vector3(r.end.x, y - 0.3, r.end.y))
	box(grp, "Top", top, Vector3(r.position.x, y - 0.3, r.position.y), Vector3(r.end.x, y, r.end.y))


func terraces() -> void:
	terrace("Terraces/Upper", UPPER, UPPER_Y)
	terrace("Terraces/High", HIGH, HIGH_Y)
	terrace("Terraces/Rise", RISE, RISE_Y)


## A cobbled street on level y (a hair above it, so it reads as paving).
func street(grp: String, r: Rect2, y: float, kind := "cobble") -> void:
	box(grp, "Street", kind, Vector3(r.position.x, y - 0.5, r.position.y), Vector3(r.end.x, y + 0.02, r.end.y))
	_roads.append(r)


func roads() -> void:
	var g := "Streets"
	# level 0
	street(g, Rect2(-36, -30, 72, 60), 0.0) # the market square
	street(g, Rect2(-6, 30, 12, 126), 0.0) # King's Road south, to the farms
	street(g, Rect2(-114, -6, 78, 12), 0.0) # the west road, over the bridge
	street(g, Rect2(36, -6, 44, 12), 0.0) # the east road
	street(g, Rect2(-76, -150, 8, 144), 0.0) # the east bank lane
	street(g, Rect2(-124, -68, 10, 224), 0.0) # the west bank lane
	# up to the upper town: King's Road climbs out of the square; stairs either side
	box(g, "KingsRamp", "cobble", Vector3(-6, 0, -44), Vector3(6, UPPER_Y + 0.02, -30), "z-")
	_roads.append(Rect2(-6, -44, 12, 14))
	stairs(g + "/StairsWest", Vector3(-26, 0, -36), Vector3(0, 0, -1), 6, int(UPPER_Y))
	stairs(g + "/StairsEast", Vector3(26, 0, -36), Vector3(0, 0, -1), 6, int(UPPER_Y))
	stairs(g + "/StairsRiver", Vector3(-38, 0, -100), Vector3(1, 0, 0), 6, int(UPPER_Y))
	stairs(g + "/StairsUpperWest", Vector3(-38, 0, -67), Vector3(1, 0, 0), 6, int(UPPER_Y)) # Upper Street's west end
	pad(g, Vector3(90, 0.02, -34), 18.0, Vector2(0, -1), 8.0) # a launcher up onto the upper town
	# up to the chapel rise
	box(g, "RiseRamp", "cobble", Vector3(80, 0, -6), Vector3(92, RISE_Y + 0.02, 6), "x+")
	_roads.append(Rect2(80, -6, 12, 12))
	street(g, Rect2(92, -6, 68, 12), RISE_Y)
	# the upper town
	street(g, Rect2(-6, -160, 12, 116), UPPER_Y) # King's Road north, out through the north gate
	street(g, Rect2(-30, -72, 180, 10), UPPER_Y) # Upper Street
	street(g, Rect2(58, -86, 12, 14), UPPER_Y) # Tanner's Lane, then a ramp up to the high town
	box(g, "TannersRamp", "cobble", Vector3(58, UPPER_Y, -100), Vector3(70, HIGH_Y + 0.02, -86), "z-")
	_roads.append(Rect2(58, -100, 12, 14))
	stairs(g + "/StairsHigh", Vector3(130, UPPER_Y, -92), Vector3(0, 0, -1), 6, int(HIGH_Y - UPPER_Y))
	# the high town
	street(g, Rect2(40, -128, 120, 8), HIGH_Y) # High Street


## The heart of town: the square under the clock tower, a well, market wagons and crates; the
## upper town's retaining wall and stairs on its north side.
func market() -> void:
	var g := "Market"
	spawn("Spawn", Vector3(0, 0.02, 22), 0.0)
	var t := Vector3(0, 0, -10)
	tower(g + "/ClockTower", t, 11.0, Vector3(0, 0, 1), true)
	chest(g + "/ClockTower", t + Vector3(-2.2, 11.0, 2.3), "large")
	pad(g, Vector3(-24, 0.02, 14), 0.0)
	pad(g, Vector3(24, 0.02, 14), 0.0)
	var w := Vector3(0, 0, 12)
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, -2.2), w + Vector3(2.2, 1, -1.6))
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, 1.6), w + Vector3(2.2, 1, 2.2))
	box(g + "/Well", "Rim", "stone", w + Vector3(-2.2, 0, -1.6), w + Vector3(-1.6, 1, 1.6))
	box(g + "/Well", "Rim", "stone", w + Vector3(1.6, 0, -1.6), w + Vector3(2.2, 1, 1.6))
	box(g + "/Well", "Water", "water", w + Vector3(-1.6, 0, -1.6), w + Vector3(1.6, 0.5, 1.6))
	for a: Array in [[Vector3(-22, 0, -4), 0.0], [Vector3(20, 0, -16), 1.6], [Vector3(-14, 0, -22), 1.6], [Vector3(26, 0, 6), 0.0]]:
		wagon(g, a[0], a[1])
	for c: Vector3 in [Vector3(-16, 0, 6), Vector3(14, 0, 2), Vector3(10, 0, -24), Vector3(-30, 0, -14), Vector3(30, 0, -26), Vector3(-8, 0, 24)]:
		crates(g, c, 2 + rng.randi() % 4)
	for c: Vector3 in [Vector3(-12, 0.02, 4), Vector3(12, 0.02, -4), Vector3(30, 0.02, 20), Vector3(-30, 0.02, -26)]:
		chest(g, c)
	# houses around three sides, doors onto the square
	row(g + "/West", Vector3(-36, 0, -28), Vector3(-36, 0, -8), Vector3(-1, 0, 0), 12.0)
	row(g + "/West", Vector3(-36, 0, 8), Vector3(-36, 0, 28), Vector3(-1, 0, 0), 12.0)
	row(g + "/East", Vector3(36, 0, -28), Vector3(36, 0, -8), Vector3(1, 0, 0), 12.0)
	row(g + "/East", Vector3(36, 0, 8), Vector3(36, 0, 28), Vector3(1, 0, 0), 12.0)
	row(g + "/South", Vector3(-34, 0, 30), Vector3(-8, 0, 30), Vector3(0, 0, 1), 12.0)
	row(g + "/South", Vector3(8, 0, 30), Vector3(34, 0, 30), Vector3(0, 0, 1), 12.0)


## The lowland streets: King's Road south, the west and east roads, the east bank lane.
func lower_town() -> void:
	var g := "LowerTown"
	row(g + "/KingsSouth", Vector3(-6, 0, 46), Vector3(-6, 0, 70), Vector3(-1, 0, 0), 10.0)
	row(g + "/KingsSouth", Vector3(6, 0, 46), Vector3(6, 0, 70), Vector3(1, 0, 0), 10.0)
	row(g + "/WestRoad", Vector3(-78, 0, 6), Vector3(-52, 0, 6), Vector3(0, 0, 1), 12.0)
	row(g + "/EastRoad", Vector3(52, 0, -6), Vector3(78, 0, -6), Vector3(0, 0, -1), 12.0)
	row(g + "/EastRoad", Vector3(52, 0, 6), Vector3(78, 0, 6), Vector3(0, 0, 1), 12.0)
	row(g + "/EastBank", Vector3(-68, 0, -140), Vector3(-68, 0, -12), Vector3(1, 0, 0), 12.0)
	# a green between the east bank houses and the upper town
	for c: Vector3 in [Vector3(-44, 0, -60), Vector3(-48, 0, -130), Vector3(-52, 0, -24)]:
		chest(g, c)


## Up on the terrace: King's Road north and Upper Street lined with taller houses, a well court.
func upper_town() -> void:
	var g := "UpperTown"
	var y := UPPER_Y
	row(g + "/KingsNorth", Vector3(-6, y, -148), Vector3(-6, y, -76), Vector3(-1, 0, 0), 10.0, 2, 3)
	row(g + "/KingsNorth", Vector3(6, y, -148), Vector3(6, y, -76), Vector3(1, 0, 0), 10.0, 2, 3)
	row(g + "/UpperNorth", Vector3(20, y, -72), Vector3(56, y, -72), Vector3(0, 0, -1), 12.0, 2, 3)
	row(g + "/UpperNorth", Vector3(72, y, -72), Vector3(158, y, -72), Vector3(0, 0, -1), 12.0, 2, 3)
	row(g + "/UpperSouth", Vector3(-28, y, -62), Vector3(-8, y, -62), Vector3(0, 0, 1), 14.0, 2, 3)
	row(g + "/UpperSouth", Vector3(8, y, -62), Vector3(158, y, -62), Vector3(0, 0, 1), 14.0, 2, 3)
	# the north gate at the end of King's Road: two towers and an arch over the road
	for sx: float in [-1.0, 1.0]:
		box(g + "/NorthGate", "Tower", "stone", Vector3(sx * 6.0, y, -160), Vector3(sx * 12.0, y + 11, -152))
		for i in 3:
			var mx := sx * (6.4 + i * 2.2)
			box(g + "/NorthGate", "Merlon", "stone_dark", Vector3(mx - 0.6, y + 11, -154), Vector3(mx + 0.6, y + 12.2, -152))
	box(g + "/NorthGate", "Arch", "stone_dark", Vector3(-6, y + 7.5, -159), Vector3(6, y + 10, -153))
	# the well court west of the high town
	var c := Vector3(30, y, -120)
	box(g + "/Court", "Paving", "stone", c + Vector3(-12, 0, -16), c + Vector3(8, 0.02, 16))
	crates(g + "/Court", c + Vector3(-6, 0.02, -10), 4)
	wagon(g + "/Court", c + Vector3(2, 0.02, 8), 0.0)
	for p: Vector3 in [c + Vector3(-4, 0.02, 0), c + Vector3(4, 0.02, -12), Vector3(100, y, -92), Vector3(-24, y, -100), Vector3(40, y, -80)]:
		chest(g, p)


## The high town: High Street between tall houses, and the guildhall on its plaza.
func high_town() -> void:
	var g := "HighTown"
	var y := HIGH_Y
	row(g + "/North", Vector3(42, y, -128), Vector3(78, y, -128), Vector3(0, 0, -1), 14.0, 2, 3)
	row(g + "/North", Vector3(112, y, -128), Vector3(158, y, -128), Vector3(0, 0, -1), 14.0, 2, 3)
	row(g + "/South", Vector3(42, y, -120), Vector3(158, y, -120), Vector3(0, 0, 1), 14.0, 2, 3)
	box(g, "Plaza", "stone", Vector3(80, y, -158), Vector3(110, y + 0.02, -128))
	house(g + "/Guildhall", Vector3(95, y + 0.02, -141), 14, 8, 3, "brick", Vector3(0, 0, 1))
	chest(g, Vector3(95, y + 0.02 + 3 * STORY + ROOF[8].ridge, -141), "golden")
	pad(g, Vector3(95, y + 0.02, -131.5), 24.0) # straight up beside it: drift onto the roof
	for p: Vector3 in [Vector3(84, y + 0.02, -131), Vector3(108, y + 0.02, -148)]:
		chest(g, p)


## The chapel rise (east): a long chapel, its bell tower, a walled graveyard with a shrine.
func chapel() -> void:
	var g := "Chapel"
	var y := RISE_Y
	house(g, Vector3(106, y, 26), 14, 8, 3, "brick", Vector3(0, 0, -1))
	var t := Vector3(124, y, 18)
	tower(g + "/Tower", t, 11.0, Vector3(-1, 0, 0), true)
	chest(g, t + Vector3(-2.3, 11.0, -2.2), "large")
	var y0 := Vector3(130, y, 32)
	fence(g + "/Graveyard", y0, y0 + Vector3(18, 0, 0))
	fence(g + "/Graveyard", y0 + Vector3(0, 0, 32), y0 + Vector3(18, 0, 32))
	fence(g + "/Graveyard", y0, y0 + Vector3(0, 0, 32))
	for i in 3:
		for j in 5:
			var at := y0 + Vector3(4 + i * 5, 0, 5 + j * 5.5)
			box(g + "/Graveyard", "Stone", "stone", at + Vector3(-0.5, 0, -0.15), at + Vector3(0.5, 1.1, 0.15))
	chest(g, y0 + Vector3(9, 0, 30), "shrine")
	row(g + "/Houses", Vector3(96, y, -6), Vector3(158, y, -6), Vector3(0, 0, -1), 12.0)
	row(g + "/Houses", Vector3(134, y, 6), Vector3(158, y, 6), Vector3(0, 0, 1), 10.0)
	for c: Vector3 in [Vector3(96, y, 12), Vector3(98, y, 46), Vector3(118, y, 62)]:
		chest(g, c)


## The river: bridges (stone on the west road, wood north and south), ramps out of the water,
## and the west bank lane of houses.
func river() -> void:
	var g := "River"
	for z: float in [0.0, -40.0, 95.0]:
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
	for z: float in [-140.0, -70.0, 45.0, 140.0]:
		box(g, "Ramp", "dirt", Vector3(RIVER_X0, -3, z - 3), Vector3(RIVER_X0 + 7, 0, z + 3), "x-")
		box(g, "Ramp", "dirt", Vector3(RIVER_X1 - 7, -3, z + 12), Vector3(RIVER_X1, 0, z + 18), "x+")
	# the west bank lane (from the castle's foot down to the farms), houses both sides
	# (gaps where the bridges come ashore)
	row(g + "/WestBank", Vector3(-114, 0, -30), Vector3(-114, 0, -10), Vector3(1, 0, 0), 12.0)
	row(g + "/WestBank", Vector3(-114, 0, 10), Vector3(-114, 0, 86), Vector3(1, 0, 0), 12.0)
	row(g + "/WestBank", Vector3(-114, 0, 104), Vector3(-114, 0, 150), Vector3(1, 0, 0), 12.0)
	row(g + "/WestBank", Vector3(-124, 0, -54), Vector3(-124, 0, -10), Vector3(-1, 0, 0), 12.0)
	row(g + "/WestBank", Vector3(-124, 0, 10), Vector3(-124, 0, 150), Vector3(-1, 0, 0), 12.0)
	for c: Vector3 in [Vector3(-88, -2.3, -110), Vector3(-104, 0, 8), Vector3(-146, 0, -6), Vector3(-88, -2.3, 60)]:
		chest(g, c)


## Castle hill in the north-west (west bank): terraces up to a keep with battlements (a pad up its
## wall) and a watchtower.
func castle() -> void:
	var g := "Castle"
	terrace(g + "/Terrace1", Rect2(-HALF, -HALF, 60, 76), 4.0)
	terrace(g + "/Terrace2", Rect2(-HALF, -HALF, 50, 64), 8.0)
	terrace(g + "/Terrace3", Rect2(-HALF, -HALF, 40, 54), CASTLE_Y, "stone")
	box(g, "RampUp1", "dirt", Vector3(-124, 0, -84), Vector3(-114, 4, -68), "z-") # from the west bank lane
	box(g, "RampUp2", "dirt", Vector3(-110, 4, -126), Vector3(-100, 8, -114), "x-")
	box(g, "RampUp3", "stone", Vector3(-140, 8, -106), Vector3(-130, CASTLE_Y, -96), "z-")
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
	var t := Vector3(-126, CASTLE_Y, -114)
	tower(g + "/Tower", t, 10.5, Vector3(0, 0, 1), false)
	chest(g + "/Tower", t + Vector3(0, 10.5, 0), "large")
	house(g + "/Houses", Vector3(-146, 8, -101), 6, 8, 2, "brick", Vector3(0, 0, 1))
	house(g + "/Houses", Vector3(-146, 4, -90), 6, 6, 2, "brick", Vector3(0, 0, 1))
	house(g + "/Houses", Vector3(-134, 4, -90), 6, 6, 1, "brick", Vector3(0, 0, 1))
	for p: Vector3 in [Vector3(-104, 4, -90), Vector3(-116, 8, -100), Vector3(-126, CASTLE_Y, -126)]:
		chest(g, p)


## Farms in the south: fields in rows, fences, hay, wagons, a big barn and farmhouses.
func farms() -> void:
	var g := "Farms"
	for f: Rect2 in [Rect2(-70, 78, 50, 32), Rect2(16, 78, 50, 32), Rect2(-70, 118, 50, 30), Rect2(80, 100, 50, 40)]:
		for r in int(f.size.y / 4):
			var z := f.position.y + r * 4 + 1
			box(g + "/Fields", "Row", "field", Vector3(f.position.x, 0, z), Vector3(f.end.x, 0.4, z + 2)) # low enough to walk over
		fence(g + "/Fences", Vector3(f.position.x, 0, f.position.y - 1), Vector3(f.end.x, 0, f.position.y - 1))
		fence(g + "/Fences", Vector3(f.position.x, 0, f.end.y + 1), Vector3(f.end.x, 0, f.end.y + 1))
		_solids.append(f)
		_blocks.append(f.grow(1.2))
	house(g + "/Barn", Vector3(40, 0, 132), 14, 8, 2, "plaster", Vector3(-1, 0, 0))
	house(g + "/Houses", Vector3(-14, 0, 130), 6, 8, 2, "brick", Vector3(1, 0, 0))
	house(g + "/Houses", Vector3(110, 0, 84), 10, 6, 1, "plaster", Vector3(0, 0, -1))
	for c: Vector3 in [Vector3(12, 0, 114), Vector3(-10, 0, 96), Vector3(72, 0, 92), Vector3(24, 0, 146)]:
		hay(g, c)
	for a: Array in [[Vector3(-12, 0, 76), 0.0], [Vector3(14, 0, 142), 1.6], [Vector3(70, 0, 124), 0.0]]:
		wagon(g, a[0], a[1])
	for c: Vector3 in [Vector3(-44, 0, 114), Vector3(44, 0, 114), Vector3(100, 0, 96), Vector3(-40, 0, 152), Vector3(8, 0, 152), Vector3(60, 0, 152)]:
		chest(g, c)
	chest(g, Vector3(40, 2 * STORY + ROOF[8].ridge, 132), "large")


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
			var h := 12.0 + rng.randf() * 18.0
			var a := lo + (Vector3(i * 20, 0, 0) if along_x else Vector3(0, 0, i * 20))
			var b := Vector3(a.x + (20 if along_x else hi.x - lo.x), h, a.z + (hi.z - lo.z if along_x else 20))
			box(g, "Hill", "hill", a, b)
		box(g, "Wall", "barrier", Vector3(lo.x, 0, lo.z), Vector3(hi.x, 70, hi.z))


## Trees wherever there's room (not on streets, in houses, on fields or in the river), on
## whatever level the ground is.
func trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 110 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-HALF + 6, HALF - 6)
		var z := rng.randf_range(-HALF + 6, HALF - 6)
		if x > RIVER_X0 - 4 and x < RIVER_X1 + 4: continue
		if Rect2(-40, -34, 80, 68).has_point(Vector2(x, z)): continue # the square
		if x < -96 and z < -80: continue # the castle
		if _near(Vector2(x, z), 5.0): continue
		if _edge_near(Vector2(x, z), 4.0): continue # not right at a terrace's edge
		tree("Trees", Vector3(x, level_at(x, z), z), 0.8 + rng.randf() * 0.7)
		_solids.append(Rect2(x - 2, z - 2, 4, 4))
		placed += 1


func _near(p: Vector2, r: float) -> bool:
	for b in _solids:
		if b.grow(r).has_point(p):
			return true
	for b in _roads:
		if b.grow(r).has_point(p):
			return true
	return false


## Within r of a level change (a terrace edge): a tree there would hang over the drop.
func _edge_near(p: Vector2, r: float) -> bool:
	var h := level_at(p.x, p.y)
	for d: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r), Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r)]:
		if level_at(p.x + d.x, p.y + d.y) != h:
			return true
	return false


## Houses along one side of a straight street, from a to b (the street's edge, at its level),
## doors to the street, up to max_depth deep (out: from the street toward the houses). Sizes are
## ones the kit has a roof for; some gables face the street, some eaves; alleys between, and
## sometimes a chest in one.
func row(grp: String, a: Vector3, b: Vector3, out: Vector3, max_depth: float, min_floors := 1, max_floors := 3) -> void:
	var dir := (b - a).normalized()
	var total := a.distance_to(b)
	var t := rng.randf_range(0.0, 1.5)
	var options: Array = []
	for span: int in ROOF_LENGTHS:
		for l: int in ROOF_LENGTHS[span]:
			options.append([span, l]) # gable to the street
			if l != span:
				options.append([l, span]) # eaves to the street
	while true:
		var fits := options.filter(func(o: Array) -> bool: return o[0] <= total - t and o[1] <= max_depth and o[0] <= 12)
		if fits.is_empty():
			break
		var o: Array = fits[rng.randi() % fits.size()]
		var along: int = o[0]
		var depth: int = o[1]
		var c := a + dir * (t + along / 2.0) + out * (0.6 + depth / 2.0)
		var w := along if absf(dir.x) > 0.5 else depth
		var d := depth if absf(dir.x) > 0.5 else along
		var floors := rng.randi_range(min_floors, max_floors)
		house(grp, c, w, d, floors, "brick" if floors > 1 or rng.randf() < 0.4 else "plaster", -out)
		t += along
		var gap := rng.randf_range(2.5, 6.0)
		if gap > 3.5 and t + gap < total and rng.randf() < 0.3:
			chest(grp, a + dir * (t + gap / 2.0) + out * 3.0) # tucked in the alley
		t += gap


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
	_blocks.append(Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z))))
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
	_blocks.append(Rect2(p.x - half.x, p.z - half.z, half.x * 2, half.z * 2))


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
	_blocks.append(Rect2(t.x - 5, t.z - 5, 10, 10))
	_blocks.append(Rect2(t.x + face.x * 6.2 - 1.3, t.z + face.z * 6.2 - 1.3, 2.6, 2.6)) # its pad
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
	# the roof (and its gable ends) must be exactly as long as the house, or there'd be gaps
	# you can see through and collision where no roof is drawn
	assert(ROOF_LENGTHS[span].has(length), "no %dx%d roof in the kit" % [span, length])
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
	model(g, "Roof_RoundTiles_%dx%d" % [span, length], Vector3(c.x, top, c.z), 0.0 if across_x else PI / 2)
	for s: float in [-1.0, 1.0]:
		var at := Vector3(c.x, top, c.z + s * length / 2.0) if across_x else Vector3(c.x + s * length / 2.0, top, c.z)
		model(g, "Roof_Front_Brick%d" % span, at, (0.0 if s > 0 else PI) + (0.0 if across_x else PI / 2))
	if rng.randf() < 0.6: # a chimney through one side of the roof
		var off := (span / 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var along_off := (length / 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := Vector3(c.x + off, top, c.z + along_off) if across_x else Vector3(c.x + along_off, top, c.z + off)
		model(g, "Prop_Chimney" if rng.randf() < 0.5 else "Prop_Chimney2", at, 0.0, 1.0)
	_solids.append(Rect2(x0, z0, w, d))
	_houses.append([Rect2(x0, z0, w, d), c.y])
	var eave := top + float(info.eave)
	var ridge := top + float(info.ridge)
	box(g, "Walls", "hidden", Vector3(x0 - 0.1, c.y, z0 - 0.1), Vector3(x1 + 0.1, eave, z1 + 0.1))
	if across_x:
		box(g, "RoofL", "hidden", Vector3(x0 - 0.1, eave, z0), Vector3(c.x, ridge, z1), "x+")
		box(g, "RoofR", "hidden", Vector3(c.x, eave, z0), Vector3(x1 + 0.1, ridge, z1), "x-")
	else:
		box(g, "RoofL", "hidden", Vector3(x0, eave, z0 - 0.1), Vector3(x1, ridge, c.z), "z+")
		box(g, "RoofR", "hidden", Vector3(x0, eave, c.z), Vector3(x1, ridge, z1 + 0.1), "z-")
