@tool
class_name MapTarget
extends MapPoint
## A bean dummy to shoot. `move_axis` makes it slide back and forth for tracking practice.

@export_enum("none", "x", "z") var move_axis := "none"
@export var move_amp := 0.0 ## meters either side
@export var move_speed := 0.0 ## radians per second of the sine wave


## The same shape the map JSON used: {x, y, z, move?: {axis, amp, speed}}.
func to_dict() -> Dictionary:
	var d := {"x": at[0], "y": at[1], "z": at[2]}
	if move_axis != "none":
		d.move = {"axis": move_axis, "amp": move_amp, "speed": move_speed}
	return d


func _draw_view(v: Node3D) -> void:
	v.add_child(WorldView.make_bean())
