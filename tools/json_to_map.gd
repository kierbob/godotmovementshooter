extends SceneTree
## Turns a map JSON (the web game's dev map export, or a map saved by the web game's map editor)
## into a map scene you can edit in the Godot editor (see MapConvert).
##   godot --headless --path . --script res://tools/json_to_map.gd -- <map.json> <id> [name]
## writes res://maps/<id>.tscn (over an existing map: keeps its card name/text/colors).


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <map.json> <id> [display name]")
		quit(1)
		return
	var id: String = args[1]
	var m := MapData.load_file(args[0])
	var root := MapConvert.from_file(args[0], id, args[2] if args.size() > 2 else "")
	var out := "res://maps/%s.tscn" % id
	if ResourceLoader.exists(out):
		# re-importing over an existing map keeps its card (name, text, colors)
		var old := (load(out) as PackedScene).instantiate() as MapRoot
		if old:
			for key: String in ["map_name", "tag", "desc", "art", "grad_from", "grad_to"]:
				if key != "map_name" or args.size() <= 2:
					root.set(key, old.get(key))
			old.free()
	var err := MapConvert.save(root, out)
	print("wrote res://maps/%s.tscn: %d boxes, %d pads, %d spawns, %d dummies, %d portals%s (%s)" % [id,
		m.boxes.size(), m.pads.size(), m.spawns.size(), m.targets.size(), m.portals.size(),
		", time trial" if not m.trial.is_empty() else "", error_string(err)])
	root.free()
	quit(0 if err == OK else 1)
