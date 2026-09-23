@tool
class_name MapPortal
extends MapPoint
## A teleport portal. In the hub it takes you onto the time trial (guns on or off); the course's
## "Exit" portal brings you back.

@export var guns := false:
	set(v):
		guns = v
		refresh()
@export var label := "TIME TRIAL":
	set(v):
		label = v
		refresh()
@export var sub := "":
	set(v):
		sub = v
		refresh()


func to_dict() -> Dictionary:
	return {"x": at[0], "y": at[1], "z": at[2], "guns": guns, "label": label, "sub": sub}


func _draw_view(v: Node3D) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.24
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.position.y = 1.35
	ring.rotation.x = PI / 2
	ring.material_override = WorldView.toon_material(Color("ff9a3c") if guns else Color("3cf0a0"))
	v.add_child(ring)
	var l := _label(label, 56)
	l.position.y = 3.4
	v.add_child(l)
	if sub != "":
		var s := _label(sub, 44, Color.WHITE)
		s.position.y = 2.9
		v.add_child(s)
