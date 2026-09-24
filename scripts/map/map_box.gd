@tool
class_name MapBox
extends Node3D
## A solid box of the map (floor, wall, platform, ramp...). Move it and scale it with the normal
## gizmos in the editor: position is its center, scale is its size in meters. Collision is
## axis-aligned, so don't rotate boxes; use `ramp` for slopes.
##
## The exact edges live in `box` (64-bit, [min x, min y, min z, max x, max y, max z]) because the
## node's own transform is only 32-bit and movement has to match the web game to the last digit.
## Boxes that came from the web editor keep its numbers instead, in `web_box` ([center x, bottom y,
## center z, width, height, depth]), and their edges are worked out the same way the web game does
## (Godot can misread long 17-digit numbers saved in a scene, but never these short ones).
## Editing the box in the editor rewrites `box` from the transform, rounded to the millimeter, and
## clears `web_box`; boxes you don't touch keep their exact values.

## Its color (see WorldView.COLORS). "barrier" is an invisible wall: solid for players, not
## drawn in the game, and shots pass through it.
@export_enum("floor", "wall", "block", "stair", "pillar", "low", "test", "plat", "trialfloor", "arenafloor", "gate",
	"grass", "road", "sidewalk", "wood", "house_blue", "house_yellow", "trim", "roof", "fence", "hedge", "bus", "truck",
	"shed", "leaves", "trunk", "crate", "barrier", "sandstone", "cliff", "sand", "ruin", "ruin_dark", "sunstone")
var kind := "block":
	set(v):
		kind = v
		_refresh()
## Sloped top: rises toward +x / -x / +z / -z (from the box's bottom at the low end).
@export_enum("none", "x+", "x-", "z+", "z-") var ramp := "none":
	set(v):
		ramp = v
		_refresh()
@export var box := PackedFloat64Array([-0.5, 0.0, -0.5, 0.5, 1.0, 0.5]):
	set(v):
		if v.size() != 6:
			return
		box = v
		_push()
## Web editor numbers [x, y, z, w, h, d]; when set, the edges come from these (see above).
@export var web_box := PackedFloat64Array():
	set(v):
		if v.size() != 6 and not v.is_empty():
			return
		web_box = v
		_push()

var _view: MeshInstance3D
# The transform we last applied: change notifications arrive a frame late, so this tells our own
# update apart from an edit in the editor (see MapPoint).
var _pushed := Transform3D()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	_push()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() \
			and not global_transform.is_equal_approx(_pushed):
		_pull()


static func mm(v: float) -> float:
	# Division (not snappedf's multiply) gives the same double as parsing "12.35" from JSON.
	return round(v * 1000.0) / 1000.0


## Exact edges [min x, min y, min z, max x, max y, max z], 64-bit.
func edges() -> PackedFloat64Array:
	if web_box.size() != 6:
		return box
	# world.js box(): center x/z, size w/d/h, bottom y (MapData.load_file does the same)
	var cx := web_box[0]
	var y := web_box[1]
	var cz := web_box[2]
	var w := web_box[3]
	var h := web_box[4]
	var d := web_box[5]
	return PackedFloat64Array([cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2])


func min_corner() -> Vector3:
	var e := edges()
	return Vector3(e[0], e[1], e[2])


func max_corner() -> Vector3:
	var e := edges()
	return Vector3(e[3], e[4], e[5])


## Transform from the exact values (on load, or when `box` is typed into the Inspector).
func _push() -> void:
	var c := (min_corner() + max_corner()) / 2.0
	var s := (max_corner() - min_corner()).max(Vector3.ONE * 0.001)
	if is_inside_tree():
		global_transform = Transform3D(Basis.from_scale(s), c)
		_pushed = global_transform
	else:
		transform = Transform3D(Basis.from_scale(s), c)
	_refresh()


## Exact values from the transform, after you moved or scaled the box in the editor.
func _pull() -> void:
	var xf := global_transform
	var s := xf.basis.get_scale().abs()
	var lo := xf.origin - s / 2.0
	var hi := xf.origin + s / 2.0
	var cur_lo := min_corner()
	var cur_hi := max_corner()
	if lo.distance_to(cur_lo) < 0.0004 and hi.distance_to(cur_hi) < 0.0004:
		_refresh() # rotated or nothing that matters changed: just redraw
		return
	web_box = PackedFloat64Array() # edited in Godot now: plain edges from here on
	box = PackedFloat64Array([mm(lo.x), mm(lo.y), mm(lo.z), mm(hi.x), mm(hi.y), mm(hi.z)])


## The same box as the game's collision uses.
func to_box() -> MapData.Box:
	var e := edges()
	var b := MapData.Box.new()
	b.min_x = e[0]
	b.min_y = e[1]
	b.min_z = e[2]
	b.max_x = e[3]
	b.max_y = e[4]
	b.max_z = e[5]
	b.kind = kind
	if ramp != "none":
		b.ramp_axis = 0 if ramp[0] == "x" else 2
		b.ramp_dir = 1 if ramp[1] == "+" else -1
	return b


func _get_configuration_warnings() -> PackedStringArray:
	var q := global_transform.basis.get_rotation_quaternion()
	if q.angle_to(Quaternion.IDENTITY) > 0.001:
		return PackedStringArray(["Boxes can't be rotated: collision is axis-aligned. Use `ramp` for slopes."])
	return PackedStringArray()


# ---------- editor view ----------

func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _view == null:
		_view = MeshInstance3D.new()
		add_child(_view) # no owner: not saved into the scene
	# Built at true size (so the 1 m grid isn't stretched), then un-scaled against the node.
	var b := to_box()
	var half := (max_corner() - min_corner()) / 2.0
	b.min_x = -half.x
	b.min_y = -half.y
	b.min_z = -half.z
	b.max_x = half.x
	b.max_y = half.y
	b.max_z = half.z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if b.ramp_axis >= 0:
		WorldView._add_ramp(st, b)
	else:
		WorldView._add_box(st, b)
	_view.mesh = st.commit()
	var s := global_transform.basis.get_scale().abs().max(Vector3.ONE * 0.001)
	_view.scale = Vector3.ONE / s
	if kind == "barrier":
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.56, 0.83, 1.0, 0.18)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_view.material_override = m
		_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_view.material_override = WorldView.toon_material(WorldView.COLORS.get(kind, Color.WHITE), true)
	update_configuration_warnings()
