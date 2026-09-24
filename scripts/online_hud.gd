class_name OnlineHud
extends Control
## The multiplayer part of the HUD (web hud.js): health bar with the number, red edges when you're
## hit or low, an arrow toward whoever shot you, the "SPLATTED!" screen with the respawn timer,
## the kill feed (top right), the hold-Tab scoreboard and an "ONLINE · 3 PLAYERS · 40 MS" badge.

const FEED_LIFE := 5.0

var _comic: Font
var _health: Control
var _hp_num: Label
var _hp_bar: Panel
var _hp_fill: ColorRect
var _vignette: TextureRect
var _dir_arrow: DamageArrow
var _death: Control
var _death_word: Label
var _death_sub: Label
var _death_age := 0.0
var _feed: VBoxContainer
var _feed_items: Array = [] # [{node, age}]
var _board: PanelContainer
var _board_rows: VBoxContainer
var _board_key := ""
var _badge: Label
var _hurt := 0.0
var _dmg_from: Variant = null # Vector3 of whoever last hit us
var _dmg_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comic = Models.font("res://assets/fonts/Bangers-Regular.ttf")

	# red edges (behind everything else)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.9, 0.05, 0.05, 0.0), Color(0.9, 0.05, 0.05, 0.0), Color(0.85, 0.02, 0.02, 0.75)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_dir_arrow = DamageArrow.new()
	_dir_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dir_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dir_arrow)

	# health, bottom left
	_health = VBoxContainer.new()
	_health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health.offset_left = 28
	_health.offset_right = 290
	_health.offset_top = -104
	_health.offset_bottom = -24
	_health.add_theme_constant_override("separation", 2)
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health)
	_hp_num = _label(56, Color.WHITE)
	_health.add_child(_hp_num)
	_hp_bar = Panel.new()
	_hp_bar.custom_minimum_size = Vector2(260, 14)
	var bar_box := StyleBoxFlat.new()
	bar_box.bg_color = Color(0, 0, 0, 0.45)
	bar_box.set_border_width_all(2)
	bar_box.border_color = Color("15151f")
	bar_box.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("panel", bar_box)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(256, 10)
	_hp_fill.color = Color("5ee06a")
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_child(_hp_fill)
	_health.add_child(_hp_bar)

	# kill feed, top right
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -520
	_feed.offset_right = -18
	_feed.offset_top = 14
	_feed.offset_bottom = 300
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	# online badge, top center
	_badge = UiStyle.label("", 16, UiStyle.MUTED)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_badge.offset_left = -240
	_badge.offset_right = 240
	_badge.offset_top = 8
	_badge.offset_bottom = 30
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_badge.add_theme_constant_override("outline_size", 4)
	add_child(_badge)

	# death screen
	_death = VBoxContainer.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death.offset_left = -400
	_death.offset_right = 400
	_death.offset_top = -150
	_death.offset_bottom = 60
	_death.alignment = BoxContainer.ALIGNMENT_CENTER
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_word = _label(130, Color("ff4a4a"))
	_death_word.text = "SPLATTED!"
	_death_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_word.add_theme_constant_override("outline_size", 14)
	_death_word.add_theme_constant_override("shadow_offset_x", 6)
	_death_word.add_theme_constant_override("shadow_offset_y", 6)
	_death.add_child(_death_word)
	_death_sub = UiStyle.label("", 28)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_sub.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_death_sub.add_theme_constant_override("outline_size", 6)
	_death.add_child(_death_sub)
	_death.visible = false
	add_child(_death)

	# scoreboard (hold Tab)
	_board = PanelContainer.new()
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(0.03, 0.047, 0.157, 0.9)
	bb.set_border_width_all(2)
	bb.border_color = Color(1, 1, 1, 0.2)
	bb.content_margin_left = 24
	bb.content_margin_right = 24
	bb.content_margin_top = 16
	bb.content_margin_bottom = 18
	_board.add_theme_stylebox_override("panel", bb)
	_board.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_board.offset_left = -300
	_board.offset_right = 300
	_board.offset_top = 90
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_rows = VBoxContainer.new()
	_board_rows.add_theme_constant_override("separation", 4)
	_board.add_child(_board_rows)
	_board.visible = false
	add_child(_board)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	if _comic:
		l.add_theme_font_override("font", _comic)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("15151f"))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## We got hit: red flash, and the arrow points at the shooter for a moment.
func hurt(dmg: float, from: Variant) -> void:
	_hurt = minf(1.0, _hurt + 0.35 + dmg * 0.02)
	if from != null:
		_dmg_from = from
		_dmg_t = 1.5


## Kill feed line: [[text, color], ...] pieces. style "mine" (your kill) / "died" (you died).
func feed(pieces: Array, style := "") -> void:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.047, 0.157, 0.78)
	st.border_width_left = 3
	st.border_color = UiStyle.YELLOW if style == "mine" else Color("ff4a4a") if style == "died" else Color(1, 1, 1, 0.25)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for piece: Array in pieces:
		var l := _label(20, piece[1])
		l.add_theme_constant_override("outline_size", 4)
		l.text = piece[0]
		row.add_child(l)
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(p)
	_feed.move_child(p, 0) # newest on top
	_feed_items.append({"node": p, "age": 0.0})
	if _feed_items.size() > 5:
		(_feed_items.pop_front().node as Node).queue_free()


## Once per frame while online.
func update(dt: float, player: PlayerSim, yaw: float, respawn_in: float, killer: String, badge: String) -> void:
	var frac := clampf(player.hp / player.max_hp, 0.0, 1.0)
	_hp_num.text = str(ceili(player.hp))
	_hp_num.add_theme_color_override("font_color", Color("ff6a5a") if frac <= 0.3 else Color.WHITE)
	_hp_fill.size.x = 256 * frac
	_hp_fill.color = Color("e5534b") if frac <= 0.3 else Color("5ee06a")
	var bar_box := _hp_bar.get_theme_stylebox("panel") as StyleBoxFlat
	bar_box.border_color = Color("7ab8ff") if player.invuln > 0 else Color("15151f") # spawn protection
	_hurt = maxf(0.0, _hurt - dt * 2.2)
	_vignette.modulate.a = minf(1.0, _hurt + ((0.35 - frac) * 1.4 if frac < 0.35 and not player.dead else 0.0))
	_dmg_t = maxf(0.0, _dmg_t - dt)
	if _dmg_from != null and _dmg_t > 0:
		var from: Vector3 = _dmg_from
		var dx := from.x - player.px
		var dz := from.z - player.pz
		var right := dx * cos(yaw) - dz * sin(yaw)
		var fwd := -dx * sin(yaw) - dz * cos(yaw)
		_dir_arrow.angle = atan2(right, fwd)
		_dir_arrow.modulate.a = minf(1.0, _dmg_t)
		_dir_arrow.visible = true
	else:
		_dir_arrow.visible = false
	if player.dead:
		if not _death.visible:
			_death_age = 0.0
		_death_age += dt
		_death.visible = true
		var t := _death_age / 0.5
		_death_word.pivot_offset = _death_word.size / 2
		_death_word.scale = Vector2.ONE * (lerpf(0.4, 1.15, t / 0.6) if t < 0.6 else lerpf(1.15, 1.0, minf(1.0, (t - 0.6) / 0.4)))
		_death_sub.text = ("%s got you · " % killer if killer != "" else "") + "Respawning in %.1f" % maxf(0.0, respawn_in)
	else:
		_death.visible = false
	var keep: Array = []
	for f: Dictionary in _feed_items:
		f.age += dt
		var n: Control = f.node
		if f.age > FEED_LIFE:
			n.queue_free()
			continue
		n.modulate.a = 1.0 if f.age < FEED_LIFE - 1 else FEED_LIFE - f.age
		keep.append(f)
	_feed_items = keep
	if _badge.text != badge:
		_badge.text = badge


## rows: [{name, kills, deaths, color, you}]
func scoreboard(show: bool, rows: Array) -> void:
	_board.visible = show
	if not show:
		_board_key = ""
		return
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	var key := str(sorted)
	if key == _board_key:
		return
	_board_key = key
	for c in _board_rows.get_children():
		c.queue_free()
	var title := _label(40, UiStyle.YELLOW)
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board_rows.add_child(title)
	_board_rows.add_child(_board_row("#", "PLAYER", "K", "D", UiStyle.MUTED, Color.TRANSPARENT))
	for i in sorted.size():
		var r: Dictionary = sorted[i]
		var col: Color = UiStyle.YELLOW if r.you else UiStyle.TEXT
		_board_rows.add_child(_board_row(str(i + 1), r.name + ("  (you)" if r.you else ""), str(r.kills), str(r.deaths), col, r.color))


func _board_row(num: String, player_name: String, k: String, d: String, col: Color, dot: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var cells := [[num, 40], [player_name, 330], [k, 60], [d, 60]]
	for i in cells.size():
		if i == 1:
			var sw := ColorRect.new()
			sw.color = dot
			sw.custom_minimum_size = Vector2(14, 14)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sw)
		var l := UiStyle.label(cells[i][0], 24, col)
		l.custom_minimum_size.x = cells[i][1]
		if i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## A red wedge circling the crosshair, pointing toward whoever hit you (0 = straight ahead).
class DamageArrow:
	extends Control
	var angle := 0.0

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2
		var dir := Vector2(sin(angle), -cos(angle))
		var side := Vector2(-dir.y, dir.x)
		var tip := c + dir * 118
		var pts := PackedVector2Array([tip, c + dir * 88 + side * 22, c + dir * 94, c + dir * 88 - side * 22])
		draw_colored_polygon(pts, Color(1, 0.25, 0.2, 0.9))
		pts.append(tip)
		draw_polyline(pts, Color("15151f"), 3.0, true)
