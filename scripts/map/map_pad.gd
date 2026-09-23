@tool
class_name MapPad
extends MapPoint
## Octane-style jump pad: a trigger disc on the floor. Directional pads fling you along
## (dir_x, dir_z) at `forward` m/s.

@export var radius := 1.2:
	set(v):
		radius = v
		refresh()
## Upward launch speed (0 = the default from cfg.gd).
@export var launch := 0.0
## Extra forward speed (0 = default: none for normal pads, 18 m/s for directional ones).
@export var forward := 0.0
@export var directional := false:
	set(v):
		directional = v
		refresh()
@export var dir_x := 0.0:
	set(v):
		dir_x = v
		refresh()
@export var dir_z := -1.0:
	set(v):
		dir_z = v
		refresh()


func to_pad() -> MapData.Pad:
	var p := MapData.Pad.new()
	p.x = at[0]
	p.y = at[1]
	p.z = at[2]
	p.radius = radius
	if launch > 0:
		p.has_launch = true
		p.launch = launch
	if directional:
		p.has_dir = true
		p.dir_x = dir_x
		p.dir_z = dir_z
		p.has_forward = true
		p.forward = forward if forward > 0 else 18.0
	elif forward > 0:
		p.has_forward = true
		p.forward = forward
	return p


func _draw_view(v: Node3D) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius * 1.08
	disc.height = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position.y = 0.05
	mi.material_override = WorldView.toon_material(Color("ffa640") if directional else Color("38e1ff"), false, 0.6)
	v.add_child(mi)
	if directional:
		v.add_child(_arrow(atan2(-dir_x, -dir_z), Color("1b2233"), radius))
