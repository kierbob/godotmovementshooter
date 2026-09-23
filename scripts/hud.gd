class_name Hud
extends CanvasLayer
## In-game overlay: stats panel (full / compact / off), crosshair and the speed readout.

var debug_mode := 1 # 0 off, 1 compact, 2 full
var _panel: PanelContainer
var _debug: Label
var _speed: Label
var _speed_sub: Label
var _cross: Control
var _in_game := false


func _ready() -> void:
	layer = 5
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.55)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", box)
	_panel.position = Vector2(8, 8)
	_debug = Label.new()
	_debug.add_theme_font_override("font", mono)
	_debug.add_theme_font_size_override("font_size", 13)
	_debug.add_theme_color_override("font_color", Color("e6edf3"))
	_panel.add_child(_debug)
	add_child(_panel)

	_cross = Crosshair.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)

	_speed = UiStyle.label("", 54)
	_speed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speed.offset_top = -130
	_speed.offset_bottom = -70
	_speed.offset_left = -200
	_speed.offset_right = 200
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_speed.add_theme_constant_override("outline_size", 8)
	add_child(_speed)
	_speed_sub = UiStyle.label("", 22, UiStyle.YELLOW)
	_speed_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speed_sub.offset_top = -74
	_speed_sub.offset_bottom = -44
	_speed_sub.offset_left = -200
	_speed_sub.offset_right = 200
	_speed_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_sub.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_speed_sub.add_theme_constant_override("outline_size", 6)
	add_child(_speed_sub)
	set_in_game(false)


## Everything except the stats panel is hidden in menus.
func set_in_game(on: bool) -> void:
	_in_game = on
	_cross.visible = on
	_speed.visible = on
	_speed_sub.visible = on
	_panel.visible = on and debug_mode > 0


func set_speed(speed: float, top: float) -> void:
	_speed.text = "%.1f" % speed
	_speed_sub.text = "M/S · TOP %.1f" % top


func set_debug(text: String) -> void:
	_panel.visible = _in_game and debug_mode > 0
	_debug.text = text
	_panel.size = Vector2.ZERO # shrink to fit


## full -> compact -> off -> full (the web game's F4). Returns the new mode.
func cycle_debug() -> int:
	debug_mode = (debug_mode + 2) % 3
	_panel.visible = _in_game and debug_mode > 0
	return debug_mode


## Dot + four lines.
class Crosshair:
	extends Control

	func _draw() -> void:
		var c := size / 2
		var col := Color.WHITE
		var dark := Color("1a1430")
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 9, c + d * 17, dark, 4.0)
			draw_line(c + d * 9, c + d * 17, col, 2.0)
		draw_circle(c, 3.2, dark)
		draw_circle(c, 2.2, col)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
