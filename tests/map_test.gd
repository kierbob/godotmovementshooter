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
	var dev := MapData.load_map("dev_map")
	check("the dev map has its time trial and both portals", not dev.trial.is_empty() and dev.portals.size() == 2)

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
