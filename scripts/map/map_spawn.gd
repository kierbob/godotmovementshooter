@tool
class_name MapSpawn
extends MapPoint
## Where the player starts (the first spawn in the map is the one used). Turn it around Y with
## the rotate gizmo to set which way you face; the arrow shows it.

## Facing, in radians (0 = looking toward -Z). Exact value; rewritten when you rotate the node.
@export var yaw := 0.0:
	set(v):
		yaw = v
		if not _pulling:
			_push()


func _push_extra() -> void:
	rotation = Vector3(0, yaw, 0)


func _pull_extra() -> void:
	var r := global_rotation.y
	if absf(angle_difference(r, yaw)) > 0.0005:
		yaw = round(r * 1000.0) / 1000.0


func _draw_view(v: Node3D) -> void:
	var bean := WorldView.make_bean(Color("4fc3ff"), Color("9fe2ff"))
	bean.rotation.y = PI # beans face +Z; the player looks toward -Z
	v.add_child(bean)
	v.add_child(_arrow(0.0, Color("4fc3ff")))
	var l := _label("SPAWN", 40, Color("9fe2ff"))
	l.position.y = 2.3
	v.add_child(l)
