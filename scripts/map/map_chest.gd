@tool
class_name MapChest
extends MapPoint
## A spot where a chest can appear. Each run puts chests on a random pick of the map's spots
## (Loot.CHESTS_PER_RUN), so place plenty: out in the open, and as rewards up high or tucked away.
## size "any" is usually a small chest, sometimes a large one; turn it to face the chest's front.

@export_enum("any", "small", "large") var size := "any":
	set(v):
		size = v
		refresh()
## Facing, in radians (the lid opens toward -Z at 0). Rewritten when you rotate the node.
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
	v.add_child(LootView.make_chest("large" if size == "large" else "small"))
	var l := _label("CHEST" if size == "any" else size.to_upper() + " CHEST", 36, Color("ffd84a"))
	l.position.y = 1.6
	v.add_child(l)
