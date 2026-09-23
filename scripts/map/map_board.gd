@tool
class_name MapBoard
extends MapPoint
## The time trial's timer board (w x h meters, facing +Z toward the start room).

@export var w := 9.0:
	set(v):
		w = v
		refresh()
@export var h := 3.4:
	set(v):
		h = v
		refresh()


func _draw_view(v: Node3D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("141a3a")
	mi.material_override = m
	v.add_child(mi)
	var l := _label("TIMER BOARD", 64)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position.z = 0.02
	v.add_child(l)
