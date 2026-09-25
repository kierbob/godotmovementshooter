class_name Nav
extends RefCounted
## Where ground enemies can walk, and how to get from A to B: a grid of standing spots over the
## map (the tops of boxes and ramps, CELL m apart, only where a player-sized body fits), linked
## to their neighbors when you can walk, step, jump (up to CLIMB) or drop (up to DROP) between
## them, plus launch pads to where they throw you. Paths come from Godot's AStar3D (C++), so an
## enemy asking for one costs next to nothing; building takes a moment, on the loading screen.
##
## `comp` groups spots you can walk both ways between (drops and pads are one way): the director
## spawns enemies only in your group, so they never appear inside something, on a tree top or on
## a ledge they can't get down from.

const CELL := 1.5
const CLIMB := 1.0 # a jump is ~1.1 m
const DROP := 10.0
const HW := Cfg.PLAYER_HALF_WIDTH
const H := Cfg.PLAYER_HEIGHT
const E := 1e-4
const HALF_DIRS := [Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(2, -2)] # in lattice steps

var map: MapData
var astar := AStar3D.new()
var pos := PackedVector3Array() # node id -> standing spot (feet)
var comp := PackedInt32Array() # node id -> walk-both-ways group
var comp_size := {} # group -> spots in it
var biggest := -1 # the biggest group
var pad_edges := {} # Vector2i(a, b) -> pad index (a launch, not a walk)
var comp_to := {} # group -> groups a one-way link (a drop, a pad) leads to
var _reach := {} # Vector2i(from group, to group) -> can you get there
var _edges := PackedInt32Array() # every link while building, as from, to pairs
var _cols := {} # Vector2i column -> PackedInt32Array of its node ids (lowest first)
# Which boxes touch a body standing at each point of a half-CELL lattice (column centers and the
# midpoints between them), as linked lists in packed arrays: much cheaper than asking the map.
var _ox := 0.0
var _oz := 0.0
var _nx := 0
var _nz := 0
var _head := PackedInt32Array()
var _next := PackedInt32Array()
var _box := PackedInt32Array()


static func build(m: MapData) -> Nav:
	var n := Nav.new()
	n.map = m
	n._build()
	return n


func size() -> int:
	return pos.size()


## The standing spot for someone at p: in their column (or the next ones out), the highest spot at
## or just below their feet. up: how far above a spot they can be (in the air) and still count.
func node_near(p: Vector3, up := 3.0, rings := 2) -> int:
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	for r in rings + 1:
		var best := -1
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for id in _cols.get(Vector2i(cx + dx, cz + dz), PackedInt32Array()):
					var s := pos[id]
					var dy := p.y - s.y
					if dy < -0.6 or dy > up:
						continue
					var d := Vector2(s.x - p.x, s.z - p.z).length() + absf(dy) * 0.5
					if d < best_d:
						best_d = d
						best = id
		if best >= 0:
			return best
	return -1


## Node ids from a to b (as close as it gets, if b can't be reached; but that searches the whole
## map, so check can_reach first).
func path(a: int, b: int) -> PackedInt64Array:
	return astar.get_id_path(a, b, true)


## Is there ground all the way along the straight line from a to b (feet), no gap to fall into
## and no ledge too high, so walking straight at b gets there?
func walkable_line(a: Vector3, b: Vector3) -> bool:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var n := ceili(flat.length() / (CELL * 0.5))
	var h := a.y
	for i in range(1, n + 1):
		var t := float(i) / n
		var best := INF
		for id in _cols.get(Vector2i(floori((a.x + flat.x * t) / CELL), floori((a.z + flat.y * t) / CELL)), PackedInt32Array()):
			var y := pos[id].y
			if y >= h - 0.6 and y <= h + CLIMB and absf(y - h) < absf(best - h):
				best = y
		if best == INF:
			return false
		h = best
	return absf(h - b.y) < 1.2


## Where to step to take the link a -> b: the pad itself when it's a launch (its spot on the grid
## can be a meter or more off it), else spot b.
func step_to(a: int, b: int) -> Vector3:
	var pi: int = pad_edges.get(Vector2i(a, b), -1)
	if pi >= 0:
		var pd := map.pads[pi]
		return Vector3(pd.x, pd.y, pd.z)
	return pos[b]


## Can you walk (drop, launch) from spot a to spot b? From the groups: everything in a group
## reaches everything else in it, so only the one-way links between groups matter.
func can_reach(a: int, b: int) -> bool:
	var ca := comp[a]
	var cb := comp[b]
	if ca == cb:
		return true
	var k := Vector2i(ca, cb)
	if not _reach.has(k):
		var seen := {ca: true}
		var todo: Array = [ca]
		var found := false
		while not todo.is_empty() and not found:
			for c: int in comp_to.get(todo.pop_back(), []):
				if c == cb:
					found = true
					break
				if not seen.has(c):
					seen[c] = true
					todo.append(c)
		_reach[k] = found
	return _reach[k]


## The spot nearest p that someone at spot `from` can get to (p itself if it's reachable), or -1.
func reachable_near(from: int, p: Vector3, up := 8.0, rings := 8) -> int:
	var goal := node_near(p, up)
	if goal >= 0 and can_reach(from, goal):
		return goal
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	for r in rings + 1:
		var best := -1
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for id in _cols.get(Vector2i(cx + dx, cz + dz), PackedInt32Array()):
					var d := pos[id].distance_squared_to(p)
					if d < best_d and can_reach(from, id):
						best_d = d
						best = id
		if best >= 0:
			return best
	return -1


## The group to spawn enemies in for someone at p: theirs, unless it's a small patch (a tree top,
## a ledge you can only get onto by pad), then the map's main one.
func spawn_group(p: Vector3) -> int:
	var at := node_near(p, 8.0)
	if at >= 0 and comp_size.get(comp[at], 0) >= 200:
		return comp[at]
	return biggest


## A random spot r_min..r_max m (flat) from p in `group`, within dy_max of p's height, with room
## for a body `size` times a player's; -1 if tries run out.
func random_spot(rng: RandomNumberGenerator, p: Vector3, r_min: float, r_max: float, group: int,
		size := 1.0, dy_max := 12.0, tries := 24) -> int:
	for t in tries:
		var a := rng.randf() * TAU
		var r := rng.randf_range(r_min, r_max)
		var col: PackedInt32Array = _cols.get(Vector2i(floori((p.x + cos(a) * r) / CELL), floori((p.z + sin(a) * r) / CELL)), PackedInt32Array())
		var ok: Array[int] = []
		for id in col:
			if comp[id] == group and absf(pos[id].y - p.y) <= dy_max:
				ok.append(id)
		if ok.is_empty():
			continue
		var id := ok[rng.randi() % ok.size()]
		if fits(id, size):
			return id
	return -1


## Can a body `size` times a player's stand at spot id (the big ones need more room)?
func fits(id: int, size: float) -> bool:
	if size <= 1.0:
		return true
	var s := pos[id]
	var hw := HW * size
	for b in map.nearby(s.x, s.y, s.z, hw + 0.5):
		var top := MapData.solid_top(b, s.x - hw, s.x + hw, s.z - hw, s.z + hw)
		if MapData.overlaps_top(s.x - hw, s.y + 0.02, s.z - hw, s.x + hw, s.y + H * size, s.z + hw, b, top):
			return false
	return true


# ---------- building ----------

func _build() -> void:
	var boxes := map.boxes
	if boxes.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in boxes:
		lo = lo.min(Vector2(b.min_x, b.min_z))
		hi = hi.max(Vector2(b.max_x, b.max_z))
	# lattice point (i, j) sits at (_ox + i * CELL/2, _oz + j * CELL/2); odd i and j are the
	# column centers (the columns are floor(x / CELL)), the rest the edges and corners between
	var half := CELL * 0.5
	_ox = (floorf(lo.x / CELL) - 1) * CELL
	_oz = (floorf(lo.y / CELL) - 1) * CELL
	_nx = int(ceilf((hi.x - _ox) / half)) + 3
	_nz = int(ceilf((hi.y - _oz) / half)) + 3
	_head.resize(_nx * _nz)
	_head.fill(-1)
	for bi in boxes.size():
		var b := boxes[bi]
		var i0 := maxi(0, floori((b.min_x - HW - _ox) / half))
		var i1 := mini(_nx - 1, ceili((b.max_x + HW - _ox) / half))
		var j0 := maxi(0, floori((b.min_z - HW - _oz) / half))
		var j1 := mini(_nz - 1, ceili((b.max_z + HW - _oz) / half))
		for i in range(i0, i1 + 1):
			var x := _ox + i * half
			if not (b.min_x < x + HW - E and b.max_x > x - HW + E):
				continue
			for j in range(j0, j1 + 1):
				var z := _oz + j * half
				if not (b.min_z < z + HW - E and b.max_z > z - HW + E):
					continue
				var k := i * _nz + j
				_box.append(bi)
				_next.append(_head[k])
				_head[k] = _box.size() - 1

	# standing spots: every box top at every column center, where a body fits
	var ids_at := {} # lattice index -> node ids
	for i in range(1, _nx, 2):
		for j in range(1, _nz, 2):
			var k := i * _nz + j
			if _head[k] < 0:
				continue
			var x := _ox + i * half
			var z := _oz + j * half
			var tops := PackedFloat32Array()
			var e := _head[k]
			while e >= 0:
				var b := boxes[_box[e]]
				if b.kind != "barrier":
					tops.append(MapData.solid_top(b, x - HW, x + HW, z - HW, z + HW))
				e = _next[e]
			tops.sort()
			var mine := PackedInt32Array()
			var last := -INF
			for y in tops:
				if y - last < 0.05 or y < -29.0:
					continue
				last = y
				if _clear(k, x, z, y):
					var id := pos.size()
					pos.append(Vector3(x, y, z))
					astar.add_point(id, Vector3(x, y, z))
					mine.append(id)
			if not mine.is_empty():
				ids_at[k] = mine
				_cols[Vector2i(floori(x / CELL), floori(z / CELL))] = mine

	# links to the 8 neighbors
	comp.resize(pos.size())
	for id in pos.size():
		comp[id] = id # union-find parents for now
	for k: int in ids_at:
		var i := k / _nz
		var j := k % _nz
		for d: Vector2i in HALF_DIRS: # each pair of columns once, both ways
			var k2 := (i + d.x) * _nz + (j + d.y)
			if not ids_at.has(k2):
				continue
			var mid := (i + d.x / 2) * _nz + (j + d.y / 2)
			var mx := _ox + (i + d.x / 2) * half
			var mz := _oz + (j + d.y / 2) * half
			var here: PackedInt32Array = ids_at[k]
			var there: PackedInt32Array = ids_at[k2]
			var diag := d.x != 0 and d.y != 0
			var side_x: PackedInt32Array = ids_at.get((i + d.x) * _nz + j, PackedInt32Array()) if diag else PackedInt32Array()
			var side_z: PackedInt32Array = ids_at.get(i * _nz + (j + d.y), PackedInt32Array()) if diag else PackedInt32Array()
			for a in here:
				for b in there:
					var ab := _steps_to(pos[a].y, pos[b].y, there)
					var ba := _steps_to(pos[b].y, pos[a].y, here)
					if not (ab or ba) or not _clear(mid, mx, mz, maxf(pos[a].y, pos[b].y) + 0.02):
						continue
					if diag:
						# no cutting corners: ground at about this height in both columns beside
						# (else the corner is a wall's edge or the edge of a drop), and no
						# diagonal drops
						var y0 := minf(pos[a].y, pos[b].y)
						var y1 := maxf(pos[a].y, pos[b].y)
						if y1 - y0 > CLIMB or not _has_between(side_x, y0 - 0.6, y1 + 0.6) or not _has_between(side_z, y0 - 0.6, y1 + 0.6):
							continue
					if ab:
						astar.connect_points(a, b, false)
						_edges.append(a)
						_edges.append(b)
					if ba:
						astar.connect_points(b, a, false)
						_edges.append(b)
						_edges.append(a)
					if ab and ba:
						_union(a, b)
	_link_pads()
	for id in pos.size():
		comp[id] = _find(id)
	for id in pos.size():
		comp_size[comp[id]] = comp_size.get(comp[id], 0) + 1
	for e in range(0, _edges.size(), 2):
		var ca := comp[_edges[e]]
		var cb := comp[_edges[e + 1]]
		if ca != cb:
			var to: Array = comp_to.get(ca, [])
			if not to.has(cb):
				to.append(cb)
				comp_to[ca] = to
	_edges = PackedInt32Array()
	var most := 0
	for c: int in comp_size:
		if comp_size[c] > most:
			most = comp_size[c]
			biggest = c
	_head = PackedInt32Array()
	_next = PackedInt32Array()
	_box = PackedInt32Array()


func _has_between(ids: PackedInt32Array, lo: float, hi: float) -> bool:
	for id in ids:
		if pos[id].y >= lo and pos[id].y <= hi:
			return true
	return false


## From height y, does walking into the next column get you to the spot at height y2 (of the spots
## there)? Anything from a step down to a jump up; if there's none of those, a drop to the highest
## spot below.
func _steps_to(y: float, y2: float, there: PackedInt32Array) -> bool:
	var dy := y2 - y
	if dy >= -Cfg.PLAYER_STEP_HEIGHT:
		return dy <= CLIMB
	if dy < -DROP:
		return false
	for id in there: # a drop: only if nothing's in reach without falling, and none lower is higher
		var d2 := pos[id].y - y
		if d2 >= -Cfg.PLAYER_STEP_HEIGHT and d2 <= CLIMB:
			return false
		if d2 < -Cfg.PLAYER_STEP_HEIGHT and pos[id].y > y2:
			return false
	return true


## Does a body standing at height y on lattice point k fit (nothing solid from its feet to its
## head; the box it stands on only reaches its feet)?
func _clear(k: int, x: float, z: float, y: float) -> bool:
	var e := _head[k]
	while e >= 0:
		var b := map.boxes[_box[e]]
		var top := MapData.solid_top(b, x - HW, x + HW, z - HW, z + HW)
		if b.min_y < y + H - E and top > y + E:
			return false
		e = _next[e]
	return true


## Launch pads: where each directional one throws you (simulated like a player holding forward
## along its arrow), as a one-way link. Plain pads just bounce you in place.
func _link_pads() -> void:
	for pi in map.pads.size():
		var pd := map.pads[pi]
		if not pd.has_dir:
			continue
		var from := node_near(Vector3(pd.x, pd.y, pd.z), 0.8, 1)
		if from < 0:
			continue
		var p := PlayerSim.new(pd.x, pd.y, pd.z)
		p.quiet = true
		var c := Cmd.new()
		c.forward = 1.0
		c.yaw = atan2(-pd.dir_x, -pd.dir_z)
		var landed := false
		for t in 8 * Cfg.TICK_RATE:
			p.step(c, map, Cfg.TICK_DT)
			if p.grounded and p.pad_launches > 0 and t > 60:
				landed = true
				break
		if not landed:
			continue
		var to := node_near(Vector3(p.px, p.py, p.pz), 0.8, 2)
		if to < 0 or to == from or pos[to].distance_to(pos[from]) < 3.0:
			continue
		astar.connect_points(from, to, false)
		_edges.append(from)
		_edges.append(to)
		pad_edges[Vector2i(from, to)] = pi


func _find(a: int) -> int:
	while comp[a] != a:
		comp[a] = comp[comp[a]]
		a = comp[a]
	return a


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		comp[maxi(ra, rb)] = mini(ra, rb)
