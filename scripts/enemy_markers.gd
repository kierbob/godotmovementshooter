class_name EnemyMarkers
extends Control
## Points out the enemies you have to find (the last few of a wave, the boss): a red marker over
## each one, seen through walls, with how far it is. Off screen (or behind you), the marker sits
## on the edge of the screen as an arrow pointing toward it.

const EDGE := 56.0 # how far in from the screen edge the arrows sit
const COLOR := Color("ff4a4a")
const BOSS_COLOR := Color("ffcf3a")

var _marks: Array[Dictionary] = [] # {pos: Vector2, dist: float, off: bool, angle: float, boss: bool}
var _font: Font
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = Models.font("res://assets/fonts/Bangers-Regular.ttf")


## Every frame: where each enemy in `list` is on screen from `camera` (boss: the one to draw gold).
func update(dt: float, camera: Camera3D, list: Array[Enemies.Enemy], boss: Enemies.Enemy) -> void:
	_t += dt
	_marks.clear()
	if camera == null or list.is_empty():
		queue_redraw()
		return
	var view := get_viewport_rect().size
	var mid := view / 2
	var cam := camera.global_position
	for e in list:
		var head := e.center() + Vector3(0, 1.1 * e.target.size + 0.5, 0)
		var dist := cam.distance_to(head)
		var behind := camera.is_position_behind(head)
		var sp := camera.unproject_position(head)
		var inside := not behind and sp.x > EDGE and sp.x < view.x - EDGE and sp.y > EDGE and sp.y < view.y - EDGE
		var m := {"dist": dist, "off": not inside, "boss": e == boss}
		if inside:
			m.pos = sp
		else:
			# which way to turn: the direction on screen (flipped when it's behind you), pushed out
			# to the edge of the screen
			var d := sp - mid
			if behind:
				d = -d
			if d.length() < 1.0:
				d = Vector2(0, 1)
			var half := mid - Vector2(EDGE, EDGE)
			var k := minf(half.x / maxf(absf(d.x), 1e-3), half.y / maxf(absf(d.y), 1e-3))
			m.pos = mid + d * k
			m.angle = d.angle()
		_marks.append(m)
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 5.0) * 3.0
	for m in _marks:
		var col: Color = BOSS_COLOR if m.boss else COLOR
		var p: Vector2 = m.pos
		if m.off:
			# an arrow on the edge, pointing at it
			var a: float = m.angle
			var tip := p + Vector2.from_angle(a) * 18.0
			var l := p + Vector2.from_angle(a + 2.5) * 14.0
			var r := p + Vector2.from_angle(a - 2.5) * 14.0
			draw_colored_polygon(PackedVector2Array([tip, l, r]), col)
			draw_polyline(PackedVector2Array([tip, l, r, tip]), UiStyle.OUTLINE, 2.5, true)
			_label(p - Vector2.from_angle(a) * 22.0 + Vector2(0, 6), "%dm" % roundi(m.dist), col)
		else:
			# a downward chevron over its head, bobbing
			var c := p + Vector2(0, bob)
			var s := 11.0 if not m.boss else 15.0
			var pts := PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(0, s * 0.4)])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), UiStyle.OUTLINE, 2.5, true)
			_label(c + Vector2(0, -s - 6), "%dm" % roundi(m.dist), col)


func _label(at: Vector2, text: String, col: Color) -> void:
	var size := 20
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := at - Vector2(w / 2, 0)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, UiStyle.OUTLINE)
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## How many are on screen (tests).
func count() -> int:
	return _marks.size()
