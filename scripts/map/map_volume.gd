@tool
class_name MapVolume
extends MapBox
## A trigger zone, not a solid box (the time trial's finish gate). Move and scale it like a box;
## you walk through it.


func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _view == null:
		_view = MeshInstance3D.new()
		_view.mesh = BoxMesh.new() # unit cube, scaled by the node
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.2, 0.25)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_view.material_override = m
		add_child(_view)


## {min: {x,y,z}, max: {x,y,z}} like the map JSON.
func to_dict() -> Dictionary:
	return {"min": {"x": box[0], "y": box[1], "z": box[2]}, "max": {"x": box[3], "y": box[4], "z": box[5]}}
