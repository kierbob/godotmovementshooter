extends SceneTree
## Checks the editable map scenes: converting a map JSON to a scene and reading it back gives
## exactly the same numbers (so movement can't change), the maps in maps/ load, and moving or
## rotating map nodes rewrites their exact values the way the editor does.
##   godot --headless --path . --script res://tests/map_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	await run()
	print("\n%s" % ("all map checks passed" if fails == 0 else "%d map checks FAILED" % fails))
	quit(1 if fails > 0 else 0)


static func same_box(a: MapData.Box, b: MapData.Box) -> bool:
	return a.min_x == b.min_x and a.min_y == b.min_y and a.min_z == b.min_z and a.max_x == b.max_x \
		and a.max_y == b.max_y and a.max_z == b.max_z and a.kind == b.kind and a.ramp_axis == b.ramp_axis \
		and a.ramp_dir == b.ramp_dir


static func same_pad(a: MapData.Pad, b: MapData.Pad) -> bool:
	return a.x == b.x and a.y == b.y and a.z == b.z and a.radius == b.radius and a.has_launch == b.has_launch \
		and a.launch == b.launch and a.has_forward == b.has_forward and a.forward == b.forward \
		and a.has_dir == b.has_dir and a.dir_x == b.dir_x and a.dir_z == b.dir_z


## Dictionaries with the same keys and exactly equal numbers (JSON ints vs floats don't matter).
static func same_data(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k: Variant in a:
			if not b.has(k) or not same_data(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same_data(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	return a == b


func run() -> void:
	# ---- JSON -> scene -> MapData is exact (on the frozen copies of the web game's maps) ----
	for id: String in ["dev_map", "bean-street"]:
		var m1 := MapData.load_file("res://tests/maps/%s.json" % id)
		var scene := MapConvert.from_file("res://tests/maps/%s.json" % id, id)
		var path := "user://map_test_%s.tscn" % id
		var err := MapConvert.save(scene, path)
		scene.free()
		var m2 := MapData.load_map(id, path)
		var boxes_ok := m1.boxes.size() == m2.boxes.size()
		for i in mini(m1.boxes.size(), m2.boxes.size()):
			boxes_ok = boxes_ok and same_box(m1.boxes[i], m2.boxes[i])
		var pads_ok := m1.pads.size() == m2.pads.size()
		for i in mini(m1.pads.size(), m2.pads.size()):
			pads_ok = pads_ok and same_pad(m1.pads[i], m2.pads[i])
		check("%s: saved as a scene (%s)" % [id, error_string(err)], err == OK)
		check("%s: all %d boxes identical, in the same order" % [id, m1.boxes.size()], boxes_ok)
		check("%s: jump pads identical" % id, pads_ok)
		check("%s: spawns identical" % id, same_data(m1.spawns, m2.spawns) and same_data(m1.spawn, m2.spawn))
		check("%s: dummies, portals, time trial and arena identical" % id, same_data(m1.targets, m2.targets)
			and same_data(m1.portals, m2.portals) and same_data(m1.trial, m2.trial) and same_data(m1.arena, m2.arena))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# ---- the real maps ----
	var ids := MapData.list()
	check("maps/ lists the maps, dev map first (%s)" % ", ".join(ids), ids.size() >= 2 and ids[0] == "dev_map")
	for id in ids:
		var m := MapData.load_map(id)
		var info := MapData.info(id)
		check("%s loads (%d boxes, %d spawns) with a card name '%s'" % [id, m.boxes.size(), m.spawns.size(), info.get("name", "")],
			m.boxes.size() > 0 and not m.spawns.is_empty() and info.get("name", "") != "")
	for id in ids:
		var m := MapData.load_map(id)
		var bad := []
		for s: Dictionary in m.spawns:
			var p := PlayerSim.new(s.x, s.y, s.z)
			var stuck := p._blocked(m.nearby(p.px, p.py, p.pz, 2.0))
			for i in 60:
				p.step(Cmd.new(), m, Cfg.TICK_DT)
			if stuck or not p.grounded or absf(p.py - float(s.y)) > 0.5:
				bad.append(Vector3(s.x, s.y, s.z))
		check("%s: every spawn is clear of walls and stands on something" % id, bad.is_empty())
		if not bad.is_empty():
			print("      bad spawns: ", bad)
		# ramp meshes: every triangle faces outward (Godot culls the back), slopes face up
		var ramps := 0
		var wrong := 0
		for b in m.boxes:
			if b.ramp_axis < 0:
				continue
			ramps += 1
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			WorldView._add_ramp(st, b)
			var arr := st.commit_to_arrays()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in range(0, v.size(), 3):
				var front := -(v[i + 1] - v[i]).cross(v[i + 2] - v[i]) # Godot's front faces wind clockwise
				var slope := absf(n[i].y) > 0.01 and absf(n[i].y) < 0.99
				if front.dot(n[i]) <= 0 or (slope and n[i].y < 0):
					wrong += 1
		check("%s: all %d ramps face outward (none invisible from outside)" % [id, ramps], wrong == 0)
		# the collision grid finds exactly what scanning every box finds, in the same order
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for b in m.boxes:
			lo = lo.min(Vector3(b.min_x, b.min_y, b.min_z))
			hi = hi.max(Vector3(b.max_x, b.max_y, b.max_z))
		var mismatch := 0
		for i in 3000:
			var q := Vector3(rng.randf_range(lo.x, hi.x), rng.randf_range(maxf(lo.y, -20.0), minf(hi.y, 50.0)), rng.randf_range(lo.z, hi.z))
			var r: float = [0.5, 2.0, 5.0, 12.0][i % 4]
			var got := m.nearby(q.x, q.y, q.z, r)
			var want: Array[MapData.Box] = []
			for b in m.boxes:
				if b.max_x < q.x - r or b.min_x > q.x + r or b.max_z < q.z - r or b.min_z > q.z + r \
						or b.max_y < q.y - r or b.min_y > q.y + Cfg.PLAYER_HEIGHT + r:
					continue
				want.append(b)
			if got != want:
				mismatch += 1
		check("%s: the collision grid finds the same boxes as a full scan" % id, mismatch == 0)
		# rays walked through the grid hit exactly what testing every box hits
		var slow := Combat.new(m.boxes, [])
		var fast := Combat.new(m.boxes, [])
		fast.grid = m
		var ray_miss := 0
		for i in 2000:
			var o := Vector3(rng.randf_range(lo.x, hi.x), rng.randf_range(maxf(lo.y, -20.0), minf(hi.y, 50.0)), rng.randf_range(lo.z, hi.z))
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			if i % 5 == 0:
				d = Vector3.DOWN # straight down: one grid column (flyers ask for the ground under them)
			var a := slow.raycast(o, d, 120.0, 0.0, false)
			var b := fast.raycast(o, d, 120.0, 0.0, false)
			if (a == null) != (b == null) or (a and (absf(a.t - b.t) > 1e-9 or a.normal != b.normal)):
				ray_miss += 1
		check("%s: rays through the grid hit the same as testing every box" % id, ray_miss == 0)
		# every launcher (directional pad) throws you onto something, not out of the map: stand on
		# it holding forward along its arrow until you land. (Plain pads are trampolines: you land
		# back on them.)
		var lost := []
		var launchers := 0
		for pd in m.pads:
			if not pd.has_dir:
				continue
			launchers += 1
			var p := PlayerSim.new(pd.x, pd.y, pd.z)
			var c := Cmd.new()
			c.forward = 1.0
			c.yaw = atan2(-pd.dir_x, -pd.dir_z)
			for i in 8 * Cfg.TICK_RATE:
				p.step(c, m, Cfg.TICK_DT)
				if p.grounded and p.pad_launches > 0 and i > 60:
					break
			if not p.grounded:
				lost.append(Vector3(pd.x, pd.y, pd.z))
		check("%s: all %d launch pads land you on something" % [id, launchers], lost.is_empty())
		# every chest spot: a chest-sized body fits there, standing on something (not in a roof,
		# not in the air)
		var bad_chests := []
		for c: Dictionary in m.chests:
			var cp := PlayerSim.new(c.x, c.y, c.z)
			var clear := not cp._blocked(m.nearby(c.x, c.y, c.z, 1.0))
			cp.py -= 0.08
			var on_ground := cp._blocked(m.nearby(c.x, c.y - 0.08, c.z, 1.0))
			if not (clear and on_ground):
				bad_chests.append(Vector3(c.x, c.y, c.z))
		check("%s: all %d chest spots are clear and on the ground" % [id, m.chests.size()], bad_chests.is_empty())
		if not bad_chests.is_empty():
			print("      chests: ", bad_chests)
		if not lost.is_empty():
			print("      pads: ", lost)
	var dev := MapData.load_map("dev_map")
	check("the dev map has its time trial and both portals", not dev.trial.is_empty() and dev.portals.size() == 2)
	ramp_collision()

	# ---- editing: what the editor does after you drag a gizmo ----
	await process_frame # the tree only takes nodes once the main loop runs
	var holder := Node3D.new()
	root.add_child(holder)
	var b := MapBox.new()
	b.box = PackedFloat64Array([0.0, 0.0, 0.0, 2.0, 1.0, 4.0])
	holder.add_child(b)
	check("a box's transform follows its exact values", b.global_position.is_equal_approx(Vector3(1, 0.5, 2))
		and b.scale.is_equal_approx(Vector3(2, 1, 4)))
	b.global_position += Vector3(0.12345, 0, 0)
	b._pull()
	check("moving a box rewrites its edges, rounded to the millimeter", b.box[0] == 0.123 and b.box[3] == 2.123)
	b.scale = Vector3(3, 1, 4)
	b._pull()
	check("scaling a box resizes it around its center", absf(b.box[3] - b.box[0] - 3.0) < 1e-9)
	var before := b.box.duplicate()
	b._pull()
	check("an edit that changes nothing keeps the exact values", b.box == before)
	holder.position = Vector3(10, 0, 0)
	b._pull()
	check("moving a group moves the boxes in it", absf(b.box[0] - (before[0] + 10.0)) < 1e-9)
	var sp := MapSpawn.new()
	holder.add_child(sp)
	sp.global_position = Vector3(5, 0, 5)
	sp.global_rotation = Vector3(0, 1.5, 0)
	sp._pull()
	check("moving and turning a spawn sets both its spot and its facing", sp.at[0] == 5.0 and sp.yaw == 1.5
		and is_equal_approx(sp.global_rotation.y, 1.5))
	holder.queue_free()
	await process_frame


## Jumping or flying into a ramp uphill rides up onto it. (The web game pushes you out to the
## ramp's low end instead, a teleport of meters; see PlayerSim._move_horizontal.)
func ramp_collision() -> void:
	var m := MapData.new()
	var floor_box := MapData.Box.new()
	floor_box.min_x = -30.0
	floor_box.min_y = -1.0
	floor_box.min_z = -5.0
	floor_box.max_x = 30.0
	floor_box.max_y = 0.0
	floor_box.max_z = 5.0
	var ramp := MapData.Box.new()
	ramp.min_x = 0.0
	ramp.min_y = 0.0
	ramp.min_z = -2.0
	ramp.max_x = 5.0
	ramp.max_y = 3.0
	ramp.max_z = 2.0
	ramp.ramp_axis = 0
	ramp.ramp_dir = 1
	m.boxes = [floor_box, ramp]
	# jump at several moments so the landing hits the slope at different heights
	var worst := 0.0
	var tops := 0
	for jump_tick in range(40, 80, 4):
		var p := PlayerSim.new(-10.0, 0.0, 0.0)
		for i in 240:
			var c := Cmd.new()
			c.forward = 1.0
			c.sprint = true
			c.yaw = -PI / 2 # +x, uphill
			c.jump = i == jump_tick
			c.jump_held = c.jump
			var ox := p.px
			p.step(c, m, Cfg.TICK_DT)
			worst = maxf(worst, ox - p.px)
		if p.px > 5.0:
			tops += 1
	check("jumping onto a ramp uphill rides up it (no push back: %.2f m)" % worst, worst < 0.01 and tops == 10)
