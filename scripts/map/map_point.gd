@tool
class_name MapPoint
extends Node3D
## Base for map things that sit at one spot (spawns, jump pads, dummies, portals...). Move them
## with the gizmo; their exact position lives in `at` (64-bit, like MapBox.box) and is rewritten
## from the gizmo, rounded to the millimeter, when you move them. Subclasses draw themselves in the
## editor in _draw_view().

@export var at := PackedFloat64Array([0.0, 0.0, 0.0]):
	set(v):
		if v.size() != 3:
			return
		at = v
		if not _pulling:
			_push()

var _view: Node3D
var _syncing := false # applying values to the transform (ignore the change notification)
var _pulling := false # reading values from the transform (don't re-apply half-read values)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	_push()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and not _syncing:
		_pull()


func pos() -> Vector3:
	return Vector3(at[0], at[1], at[2])


func _push() -> void:
	_syncing = true
	if is_inside_tree():
		global_position = pos()
	else:
		position = pos()
	_push_extra()
	_syncing = false
	refresh()


## Read everything from the gizmo first, then apply once (applying `at` alone would reset e.g. a
## spawn's rotation before its new yaw was read).
func _pull() -> void:
	_pulling = true
	var p := global_position
	if p.distance_to(pos()) >= 0.0004:
		at = PackedFloat64Array([MapBox.mm(p.x), MapBox.mm(p.y), MapBox.mm(p.z)])
	_pull_extra()
	_pulling = false
	_push()


## Subclasses: apply other exact values to the transform (e.g. a spawn's yaw).
func _push_extra() -> void:
	pass


## Subclasses: read other values back from the transform after an edit.
func _pull_extra() -> void:
	pass


## Rebuild the editor-only view (not saved into the scene).
func refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _view:
		_view.queue_free()
	_view = Node3D.new()
	add_child(_view)
	_draw_view(_view)


func _draw_view(_v: Node3D) -> void:
	pass


static func _label(text: String, size := 48, color := Color("ffe14d")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	l.font_size = size
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color("15151f")
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


## An arrow on the floor pointing along `yaw` (0 = -Z, like the player's yaw).
static func _arrow(yaw: float, color: Color, length := 1.2) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(-0.08, 0, 0), Vector3(0.08, 0, 0), Vector3(0.08, 0, -length),
			Vector3(-0.08, 0, 0), Vector3(0.08, 0, -length), Vector3(-0.08, 0, -length),
			Vector3(-0.25, 0, -length), Vector3(0.25, 0, -length), Vector3(0, 0, -length - 0.4)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	mi.material_override = m
	mi.position.y = 0.05
	mi.rotation.y = yaw
	return mi
