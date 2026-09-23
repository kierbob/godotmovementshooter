@tool
class_name MapTrial
extends Node3D
## The time trial course settings. Its children are the course's special spots: a MapSpawn
## named "Start", a MapPortal named "Exit", a MapVolume named "Finish" and a MapBoard named
## "Board". The course itself is ordinary MapBoxes.

## The clock starts when you cross this Z (running toward -Z).
@export var start_line_z := 0.0
## Falling below this height restarts the run.
@export var kill_y := -8.0


## The same shape as the old map JSON's "trial" (what TimeTrial reads).
func to_dict() -> Dictionary:
	var start := get_node_or_null("Start") as MapSpawn
	var exit := get_node_or_null("Exit") as MapPortal
	var finish := get_node_or_null("Finish") as MapVolume
	var board := get_node_or_null("Board") as MapBoard
	if start == null or exit == null or finish == null or board == null:
		push_warning("MapTrial needs Start, Exit, Finish and Board children; the time trial is off.")
		return {}
	return {
		"start": {"x": start.at[0], "y": start.at[1], "z": start.at[2], "yaw": start.yaw},
		"startLineZ": start_line_z,
		"killY": kill_y,
		"finish": finish.to_dict(),
		"exit": {"x": exit.at[0], "y": exit.at[1], "z": exit.at[2], "label": exit.label},
		"board": {"x": board.at[0], "y": board.at[1], "z": board.at[2], "w": board.w, "h": board.h},
	}
