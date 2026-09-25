class_name MapData
extends RefCounted
## Map geometry + gameplay markers. Maps are scenes you edit in the Godot editor (maps/*.tscn, see
## MapRoot), read by load_map(). load_file() reads the web game's JSON (the dev map export with
## boxes as min/max, or a web editor map with boxes as center/size); tools/json_to_map.gd turns
## one into a map scene. The collision helpers mirror src/world.js exactly.


## An axis-aligned box. A ramp is a box whose top slopes: it rises toward +axis (ramp_dir 1) or
## -axis (ramp_dir -1), from min_y at the low end to max_y at the high end.
class Box:
	var min_x := 0.0
	var min_y := 0.0
	var min_z := 0.0
	var max_x := 0.0
	var max_y := 0.0
	var max_z := 0.0
	var kind := "block"
	var ramp_axis := -1 # -1 = plain box, 0 = x, 2 = z
	var ramp_dir := 0


## Octane-style jump pad: a trigger disc on the floor. dir = directional launcher.
class Pad:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var radius := 1.2
	var has_launch := false
	var launch := 0.0
	var has_forward := false
	var forward := 0.0
	var has_dir := false
	var dir_x := 0.0
	var dir_z := 0.0


var name := "Map"
var boxes: Array[Box] = []
var pads: Array[Pad] = []
var spawn := {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
var spawns: Array = [] # every spawn point (editor maps); the dev map has one
var targets: Array = [] # bean dummies: { x, y, z, move? }
var trial := {} # time trial course (dev map only): start, startLineZ, killY, finish, exit, board
var portals: Array = [] # hub portals to the time trial: { x, y, z, guns, label, sub }
var arena := {} # bot arena layout (for the future Bot Arena mode)
var view_scale := 1.0 # big maps push the haze out (MapRoot.view_scale)
var chests: Array = [] # chest spots {x, y, z, size, yaw} (MapChest); each run uses some

# nearby() looks boxes up in a grid of GRID_CELL m columns instead of scanning every box (big
# stages have hundreds, and every enemy steps through here each tick).
const GRID_CELL := 8.0
var _grid := {} # Vector2i cell -> PackedInt32Array of box indices, in map order
var _grid_of: Array[Box] = [] # the box list the grid was built from
var _grid_count := -1

const MAPS_DIR := "res://maps/"


## Map ids (file names in maps/), the dev map first.
static func list() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir:
		for f in dir.get_files():
			f = f.trim_suffix(".remap") # exported builds
			if f.ends_with(".tscn") and not out.has(f.get_basename()):
				out.append(f.get_basename())
	out.sort()
	if out.has("dev_map"):
		out.erase("dev_map")
		out.push_front("dev_map")
	return out


## The map's root node settings (name, card text and colors) without building it.
static func info(id: String) -> Dictionary:
	var root := _instance(id)
	if root == null:
		return {}
	var d := {"name": root.map_name, "tag": root.tag, "desc": root.desc, "art": root.art,
		"grad": [root.grad_from, root.grad_to]}
	root.free()
	return d


static func _instance(id: String, path := "") -> MapRoot:
	if path == "":
		path = MAPS_DIR + id + ".tscn"
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("No map scene at %s" % path)
		return null
	var root := ps.instantiate() as MapRoot
	if root == null:
		push_error("%s: the root node needs the MapRoot script" % path)
	return root


## Read a map scene (maps/<id>.tscn, or `path`). Boxes keep scene-tree order (collision checks
## them in map order).
static func load_map(id: String, path := "") -> MapData:
	var m := MapData.new()
	var root := _instance(id, path)
	if root == null:
		return m
	m.name = root.map_name
	m.arena = root.arena.duplicate(true)
	m.view_scale = root.view_scale
	_collect(root, m)
	if m.spawns.is_empty():
		m.spawns = [{"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}]
	m.spawn = m.spawns[0]
	root.free()
	return m


static func _collect(n: Node, m: MapData) -> void:
	for c in n.get_children():
		if c is MapTrial:
			m.trial = (c as MapTrial).to_dict()
			_collect_boxes_only(c, m) # the course's own start/exit aren't hub spawns/portals
			continue
		if c is MapVolume:
			pass # triggers aren't solid
		elif c is MapBox:
			m.boxes.append((c as MapBox).to_box())
		elif c is MapPad:
			m.pads.append((c as MapPad).to_pad())
		elif c is MapSpawn:
			var sp := c as MapSpawn
			m.spawns.append({"x": sp.at[0], "y": sp.at[1], "z": sp.at[2], "yaw": sp.yaw})
		elif c is MapTarget:
			m.targets.append((c as MapTarget).to_dict())
		elif c is MapPortal:
			m.portals.append((c as MapPortal).to_dict())
		elif c is MapChest:
			var ch := c as MapChest
			m.chests.append({"x": ch.at[0], "y": ch.at[1], "z": ch.at[2], "size": ch.size, "yaw": ch.yaw})
		_collect(c, m)


static func _collect_boxes_only(n: Node, m: MapData) -> void:
	for c in n.get_children():
		if c is MapBox and not c is MapVolume:
			m.boxes.append((c as MapBox).to_box())
		elif c is MapPad:
			m.pads.append((c as MapPad).to_pad())
		elif c is MapTarget:
			m.targets.append((c as MapTarget).to_dict())
		_collect_boxes_only(c, m)


static func load_file(path: String) -> MapData:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var m := MapData.new()
	m.name = data.get("name", "Map")
	for b: Dictionary in data.get("boxes", []):
		var box := Box.new()
		if b.has("min"):
			box.min_x = b.min.x
			box.min_y = b.min.y
			box.min_z = b.min.z
			box.max_x = b.max.x
			box.max_y = b.max.y
			box.max_z = b.max.z
		else:
			# Editor format: center x/z, size w/d/h, bottom y (same arithmetic as world.js box()).
			var cx: float = b.x
			var cz: float = b.z
			var w: float = b.w
			var d: float = b.d
			var h: float = b.h
			var y: float = b.get("y", 0.0)
			box.min_x = cx - w / 2
			box.max_x = cx + w / 2
			box.min_z = cz - d / 2
			box.max_z = cz + d / 2
			box.min_y = y
			box.max_y = y + h
		box.kind = b.get("kind", "block")
		var ramp = b.get("ramp")
		if ramp is String and ramp.length() == 2:
			box.ramp_axis = 0 if ramp[0] == "x" else 2
			box.ramp_dir = 1 if ramp[1] == "+" else -1
		elif ramp is Dictionary:
			box.ramp_axis = 0 if ramp.axis == "x" else 2
			box.ramp_dir = int(ramp.dir)
		m.boxes.append(box)
	for p: Dictionary in data.get("pads", []):
		var pad := Pad.new()
		pad.x = p.x
		pad.y = p.get("y", 0.0)
		pad.z = p.z
		pad.radius = p.get("radius", 1.2)
		if p.has("launch"):
			pad.has_launch = true
			pad.launch = p.launch
		if p.has("dir"):
			pad.has_dir = true
			pad.dir_x = p.dir.x
			pad.dir_z = p.dir.z
			pad.has_forward = true
			pad.forward = p.get("forward", 18.0)
		elif p.has("forward"):
			pad.has_forward = true
			pad.forward = p.forward
		m.pads.append(pad)
	if data.has("spawn"):
		m.spawn = data.spawn
		m.spawns = [data.spawn]
	elif data.get("spawns", []).size() > 0:
		m.spawns = data.spawns
		m.spawn = data.spawns[0]
	for key in ["x", "y", "z", "yaw"]:
		m.spawn[key] = float(m.spawn.get(key, 0.0))
	m.targets = data.get("targets", [])
	m.trial = data.get("trial", {})
	m.portals = data.get("portals", [])
	m.arena = data.get("arena", {})
	return m


## Boxes within r meters of a player standing at (x, y, z), in map order. Nothing can move a
## player more than ~0.5 m in one tick, so this list holds everything the tick could touch and the
## results are identical to checking the whole map (just much cheaper).
func nearby(x: float, y: float, z: float, r: float) -> Array[Box]:
	var out: Array[Box] = []
	var x0 := x - r
	var x1 := x + r
	var z0 := z - r
	var z1 := z + r
	var y0 := y - r
	var y1 := y + Cfg.PLAYER_HEIGHT + r
	var cx0 := floori(x0 / GRID_CELL)
	var cx1 := floori(x1 / GRID_CELL)
	var cz0 := floori(z0 / GRID_CELL)
	var cz1 := floori(z1 / GRID_CELL)
	if (cx1 - cx0 + 1) * (cz1 - cz0 + 1) > 16:
		# a wide query (a long enemy sight line): just check every box
		for b in boxes:
			if b.max_x < x0 or b.min_x > x1 or b.max_z < z0 or b.min_z > z1 or b.max_y < y0 or b.min_y > y1:
				continue
			out.append(b)
		return out
	_ensure_grid()
	# Candidates from the grid cells the query touches, then back into map order so the result
	# (and so the movement) is exactly what the full scan gives.
	var ids := PackedInt32Array()
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			ids.append_array(_grid.get(Vector2i(cx, cz), PackedInt32Array()))
	ids.sort()
	var last := -1
	for i in ids:
		if i == last:
			continue
		last = i
		var b := boxes[i]
		if b.max_x < x0 or b.min_x > x1 or b.max_z < z0 or b.min_z > z1 or b.max_y < y0 or b.min_y > y1:
			continue
		out.append(b)
	return out


## Boxes a ray from o along d (normalized) could hit within max_t, in map order: everything in
## the grid columns it passes over (walked cell by cell), so a ray tests a handful of boxes
## instead of every box on the map. Hits come out the same as testing every box.
func ray_boxes(o: Vector3, d: Vector3, max_t: float) -> Array[Box]:
	_ensure_grid()
	var ids := PackedInt32Array()
	var cx := floori(o.x / GRID_CELL)
	var cz := floori(o.z / GRID_CELL)
	var sx := 1 if d.x > 0 else -1
	var sz := 1 if d.z > 0 else -1
	var tx := INF
	var tz := INF
	var dx := INF
	var dz := INF
	if absf(d.x) > 1e-9:
		tx = ((cx + (1 if d.x > 0 else 0)) * GRID_CELL - o.x) / d.x
		dx = GRID_CELL / absf(d.x)
	if absf(d.z) > 1e-9:
		tz = ((cz + (1 if d.z > 0 else 0)) * GRID_CELL - o.z) / d.z
		dz = GRID_CELL / absf(d.z)
	for guard in 4096:
		ids.append_array(_grid.get(Vector2i(cx, cz), PackedInt32Array()))
		if minf(tx, tz) > max_t:
			break
		if tx < tz:
			cx += sx
			tx += dx
		else:
			cz += sz
			tz += dz
	ids.sort()
	var out: Array[Box] = []
	var last := -1
	for i in ids:
		if i != last:
			out.append(boxes[i])
			last = i
	return out


func _ensure_grid() -> void:
	if not is_same(_grid_of, boxes) or _grid_count != boxes.size():
		_build_grid()


## Bucket every box into the GRID_CELL-sized columns it covers (built on first use, and again if
## the box list is replaced or grows).
func _build_grid() -> void:
	_grid.clear()
	_grid_of = boxes
	_grid_count = boxes.size()
	for i in boxes.size():
		var b := boxes[i]
		for cx in range(floori(b.min_x / GRID_CELL), floori(b.max_x / GRID_CELL) + 1):
			for cz in range(floori(b.min_z / GRID_CELL), floori(b.max_z / GRID_CELL) + 1):
				var k := Vector2i(cx, cz)
				var cell: PackedInt32Array = _grid.get(k, PackedInt32Array())
				cell.append(i)
				_grid[k] = cell


# ---------- collision helpers (mirror src/world.js) ----------

## Height of a ramp's surface at coordinate v along its axis.
static func ramp_height_at(b: Box, v: float) -> float:
	var lo := b.min_x if b.ramp_axis == 0 else b.min_z
	var hi := b.max_x if b.ramp_axis == 0 else b.max_z
	var length := hi - lo
	var t := (v - lo) / length if b.ramp_dir > 0 else (hi - v) / length
	t = minf(1.0, maxf(0.0, t))
	return b.min_y + (b.max_y - b.min_y) * t


static func ramp_slope(b: Box) -> float:
	var length := (b.max_x - b.min_x) if b.ramp_axis == 0 else (b.max_z - b.min_z)
	return (b.max_y - b.min_y) / length


## Top of box b as seen by an AABB spanning [ax0, ax1] x [az0, az1]: a plain box's top, or the
## highest point of a ramp's slope under that AABB (world.js solidFor).
static func solid_top(b: Box, ax0: float, ax1: float, az0: float, az1: float) -> float:
	if b.ramp_axis < 0:
		return b.max_y
	var v: float
	if b.ramp_axis == 0:
		v = minf(ax1, b.max_x) if b.ramp_dir > 0 else maxf(ax0, b.min_x)
	else:
		v = minf(az1, b.max_z) if b.ramp_dir > 0 else maxf(az0, b.min_z)
	return ramp_height_at(b, v)


## Strict AABB overlap with box b whose top is `top` (touching doesn't count).
static func overlaps_top(ax0: float, ay0: float, az0: float, ax1: float, ay1: float, az1: float, b: Box, top: float) -> bool:
	const E := 1e-6
	return ax0 < b.max_x - E and ax1 > b.min_x + E \
		and ay0 < top - E and ay1 > b.min_y + E \
		and az0 < b.max_z - E and az1 > b.min_z + E
