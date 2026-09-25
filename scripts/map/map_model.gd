@tool
class_name MapModel
extends MapPoint
## A model placed in the map (a piece of the village kit: a wall, a roof, a crate...): looks only,
## no collision. Put MapBoxes of kind "hidden" (solid, not drawn) under it for that. Move it with
## the gizmo and turn it (yaw); `size` scales it. In the game every copy of a model is drawn in
## one batch (WorldView.build_models), so a town of thousands of pieces stays cheap.
## The kit's materials come without textures, so each one gets a toon color by its name
## (WorldView.KIT_COLORS).

@export_file("*.fbx", "*.glb", "*.gltf", "*.tscn") var model := "":
	set(v):
		model = v
		refresh()
## Facing, in radians. Rewritten when you rotate the node.
@export var yaw := 0.0:
	set(v):
		yaw = v
		if not _pulling:
			_push()
@export var size := 1.0:
	set(v):
		size = v
		if not _pulling:
			_push()


func _push_extra() -> void:
	rotation = Vector3(0, yaw, 0)
	scale = Vector3.ONE * size


func _pull_extra() -> void:
	var r := global_rotation.y
	if absf(angle_difference(r, yaw)) > 0.0005:
		yaw = round(r * 1000.0) / 1000.0
	var s := global_transform.basis.get_scale().x
	if absf(s - size) > 0.0005:
		size = round(s * 1000.0) / 1000.0


func _draw_view(v: Node3D) -> void:
	if model == "" or not ResourceLoader.exists(model):
		return
	var ps := load(model) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	WorldView.recolor_kit(inst)
	v.add_child(inst)


## Where it sits in the world (for the game: position, turn and size).
func xform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), pos())


## Every model a map scene uses (read from the file, so the loading screen can load them on its
## thread before the scene is built).
static func paths_in(scene_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var text := FileAccess.get_file_as_string(scene_path)
	if text == "":
		return out
	var re := RegEx.create_from_string("model = \"(res://[^\"]+)\"")
	for m in re.search_all(text):
		var p := m.get_string(1)
		if not out.has(p):
			out.append(p)
	return out
