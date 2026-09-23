class_name MapConvert
## Builds a map scene (MapRoot and its nodes, see scripts/map/) from MapData read out of a map JSON
## (MapData.load_file). Every value is copied exactly and boxes keep their order, so movement on
## the scene is identical to the JSON. Used by tools/json_to_map.gd and tests/map_test.gd.
## Boxes are grouped for a tidy scene tree: the hub, the time trial course (x > 150) and the bot
## arena (x < -150).

const TRIAL_X := 150.0


static func _group(parent: Node, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


## A map JSON file straight to a scene root (see build()).
static func from_file(path: String, id: String, display_name := "") -> MapRoot:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return build(MapData.load_file(path), id, display_name, data.get("boxes", []))


## The map as a scene root (owners set, ready to pack). Free it when done. raw_boxes = the JSON's
## box entries: web-editor boxes (center/size) keep those short numbers rather than computed edges.
static func build(m: MapData, id: String, display_name := "", raw_boxes := []) -> MapRoot:
	var root := MapRoot.new()
	root.name = id.to_pascal_case()
	root.map_name = display_name if display_name != "" else m.name
	root.arena = m.arena

	# Boxes: consecutive runs go into hub / course / arena groups, in the original order.
	var hub := _group(root, "Boxes")
	var trial_node: MapTrial = null
	var course: Node3D = null
	var arena: Node3D = null
	var seen_trial := false
	var seen_arena := false
	var last_group := ""
	for i in m.boxes.size():
		var b: MapData.Box = m.boxes[i]
		var cx := (b.min_x + b.max_x) / 2
		var grp := "course" if cx > TRIAL_X and not m.trial.is_empty() else "arena" if cx < -TRIAL_X and not m.arena.is_empty() else "hub"
		if grp != last_group:
			# A group can only be entered once, or tree order would differ from the JSON order.
			assert(not (grp == "course" and seen_trial) and not (grp == "arena" and seen_arena), "box %d breaks the group order" % i)
			assert(not (grp == "hub" and last_group != ""), "box %d: hub boxes after course/arena boxes" % i)
			if grp == "course":
				seen_trial = true
				trial_node = MapTrial.new()
				trial_node.name = "TimeTrial"
				root.add_child(trial_node)
				course = _group(trial_node, "Course")
			elif grp == "arena":
				seen_arena = true
				arena = _group(root, "Arena")
			last_group = grp
		var mb := MapBox.new()
		mb.name = "%s%d" % [b.kind.capitalize(), i]
		mb.kind = b.kind
		if b.ramp_axis >= 0:
			mb.ramp = ("x" if b.ramp_axis == 0 else "z") + ("+" if b.ramp_dir > 0 else "-")
		var raw: Dictionary = raw_boxes[i] if i < raw_boxes.size() else {}
		if raw.has("w"):
			mb.web_box = PackedFloat64Array([float(raw.x), float(raw.get("y", 0.0)), float(raw.z),
				float(raw.w), float(raw.h), float(raw.d)])
		else:
			mb.box = PackedFloat64Array([b.min_x, b.min_y, b.min_z, b.max_x, b.max_y, b.max_z])
		(course if grp == "course" else arena if grp == "arena" else hub).add_child(mb)

	# Pads, spawns, dummies and portals, each in their own group, in the original order.
	var pads := _group(root, "Pads")
	for i in m.pads.size():
		var p: MapData.Pad = m.pads[i]
		var mp := MapPad.new()
		mp.name = "Pad%d" % i
		mp.at = PackedFloat64Array([p.x, p.y, p.z])
		mp.radius = p.radius
		if p.has_launch:
			mp.launch = p.launch
		if p.has_dir:
			mp.directional = true
			mp.dir_x = p.dir_x
			mp.dir_z = p.dir_z
		if p.has_forward:
			mp.forward = p.forward
		pads.add_child(mp)
	var spawns := _group(root, "Spawns")
	for i in m.spawns.size():
		var s: Dictionary = m.spawns[i]
		var ms := MapSpawn.new()
		ms.name = "Spawn%d" % i
		ms.at = PackedFloat64Array([float(s.x), float(s.y), float(s.z)])
		ms.yaw = float(s.get("yaw", 0.0))
		spawns.add_child(ms)
	if not m.targets.is_empty():
		var targets := _group(root, "Dummies")
		for i in m.targets.size():
			var t: Dictionary = m.targets[i]
			var mt := MapTarget.new()
			mt.name = "Dummy%d" % i
			mt.at = PackedFloat64Array([float(t.x), float(t.y), float(t.z)])
			if t.has("move"):
				mt.move_axis = t.move.axis
				mt.move_amp = float(t.move.amp)
				mt.move_speed = float(t.move.speed)
			targets.add_child(mt)
	if not m.portals.is_empty():
		var portals := _group(root, "Portals")
		for i in m.portals.size():
			var p: Dictionary = m.portals[i]
			var po := MapPortal.new()
			po.name = "Portal%d" % i
			po.at = PackedFloat64Array([float(p.x), float(p.y), float(p.z)])
			po.guns = p.get("guns", false)
			po.label = p.get("label", "TIME TRIAL")
			po.sub = p.get("sub", "")
			portals.add_child(po)

	# Time trial specials
	if not m.trial.is_empty():
		var tr: Dictionary = m.trial
		if trial_node == null:
			trial_node = MapTrial.new()
			trial_node.name = "TimeTrial"
			root.add_child(trial_node)
		trial_node.start_line_z = float(tr.startLineZ)
		trial_node.kill_y = float(tr.killY)
		var st := MapSpawn.new()
		st.name = "Start"
		st.at = PackedFloat64Array([float(tr.start.x), float(tr.start.y), float(tr.start.z)])
		st.yaw = float(tr.start.get("yaw", 0.0))
		trial_node.add_child(st)
		var ex := MapPortal.new()
		ex.name = "Exit"
		ex.at = PackedFloat64Array([float(tr.exit.x), float(tr.exit.y), float(tr.exit.z)])
		ex.label = tr.exit.get("label", "BACK TO HUB")
		trial_node.add_child(ex)
		var fin := MapVolume.new()
		fin.name = "Finish"
		fin.box = PackedFloat64Array([float(tr.finish.min.x), float(tr.finish.min.y), float(tr.finish.min.z),
			float(tr.finish.max.x), float(tr.finish.max.y), float(tr.finish.max.z)])
		trial_node.add_child(fin)
		var bd := MapBoard.new()
		bd.name = "Board"
		bd.at = PackedFloat64Array([float(tr.board.x), float(tr.board.y), float(tr.board.z)])
		bd.w = float(tr.board.w)
		bd.h = float(tr.board.h)
		trial_node.add_child(bd)

	_own(root, root)
	return root


## Pack and save to res://maps/<id>.tscn (or `path`).
static func save(root: MapRoot, path: String) -> Error:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		err = ResourceSaver.save(ps, path)
	return err
