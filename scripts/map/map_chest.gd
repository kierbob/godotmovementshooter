@tool
class_name MapChest
extends MapPoint
## A spot where a chest can appear. Each run fills a random pick of the map's spots
## (Loot.CHESTS_PER_RUN; barrels go on some of the rest), so place plenty: out in the open, and as
## rewards up high or tucked away. size "any" rolls what it is (Loot.KIND_WEIGHTS: mostly chests,
## sometimes a themed chest, a shrine, a shop, rarely a golden chest); a large spot is sometimes
## golden. Turn it to face the chest's front (a shop's three terminals line up across it).

@export_enum("any", "small", "large", "golden", "damage", "utility", "healing", "shop", "shrine") var size := "any":
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
	match size:
		"shop":
			v.add_child(LootView.make_terminal())
		"shrine":
			v.add_child(LootView.make_shrine())
		"any":
			v.add_child(LootView.make_chest("small"))
		_:
			v.add_child(LootView.make_chest(size))
	var l := _label("CHEST" if size == "any" else size.to_upper() + " CHEST", 36, Color("ffd84a"))
	l.position.y = 1.6
	v.add_child(l)
