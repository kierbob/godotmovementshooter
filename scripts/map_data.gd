class_name MapData
extends RefCounted
## Map geometry + gameplay markers, loaded from the web game's JSON: either the dev map export
## (data/dev_map.json, boxes as min/max) or a map from the web editor (boxes as center/size).
## The collision helpers mirror src/world.js exactly.


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
	for b in boxes:
		if b.max_x < x0 or b.min_x > x1 or b.max_z < z0 or b.min_z > z1 or b.max_y < y0 or b.min_y > y1:
			continue
		out.append(b)
	return out


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
