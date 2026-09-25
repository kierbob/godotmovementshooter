class_name RunHud
extends Control
## The run's HUD: the wave counter under your gold ("WAVE 3 / 8", "12 LEFT", "NEXT WAVE IN 5"),
## big banners ("WAVE 3", "BOSS INCOMING", "STAGE CLEARED"), the boss's health bar across the top,
## markers on the enemies left to find (EnemyMarkers), and the results screen when a run ends (with
## buttons to go again or back to the menu).

signal again
signal main_menu

var _wave: Label
var _wave_sub: Label
var _banner: VBoxContainer
var _b_title: Label
var _b_sub: Label
var _banner_t := 0.0
var _boss: VBoxContainer
var _boss_name: Label
var _boss_fill: ColorRect
var _results: PanelContainer
var _stats: VBoxContainer
var _res_title: Label
var _comic: Font
var markers: EnemyMarkers


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comic = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	markers = EnemyMarkers.new()
	add_child(markers) # first, so everything else draws over it
	_wave = _text(28, Color.WHITE)
	_wave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_wave.offset_left = -300
	_wave.offset_right = -28
	_wave.offset_top = 92
	_wave.offset_bottom = 124
	_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_wave)
	_wave_sub = _text(18, UiStyle.MUTED)
	_wave_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_wave_sub.offset_left = -300
	_wave_sub.offset_right = -28
	_wave_sub.offset_top = 122
	_wave_sub.offset_bottom = 146
	_wave_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_wave_sub)

	_banner = VBoxContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -400
	_banner.offset_right = 400
	_banner.offset_top = 150
	_banner.offset_bottom = 260
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_b_title = _text(64, Color.WHITE)
	_b_sub = _text(22, UiStyle.TEXT)
	_banner.add_child(_b_title)
	_banner.add_child(_b_sub)
	_banner.modulate.a = 0.0

	_boss = VBoxContainer.new()
	_boss.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss.offset_left = -320
	_boss.offset_right = 320
	_boss.offset_top = 70
	_boss.offset_bottom = 120
	_boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss.visible = false
	add_child(_boss)
	_boss_name = _text(28, Color("ff6a5a"))
	_boss.add_child(_boss_name)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.custom_minimum_size = Vector2(640, 14)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss.add_child(bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color("e5534b")
	_boss_fill.size = Vector2(640, 14)
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_boss_fill)

	_results = PanelContainer.new()
	_results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_results.offset_left = -300
	_results.offset_right = 300
	_results.offset_top = -230
	_results.offset_bottom = 230
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.04, 0.12, 0.92)
	st.border_color = UiStyle.YELLOW
	st.set_border_width_all(3)
	st.set_corner_radius_all(10)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 20
	st.content_margin_bottom = 24
	_results.add_theme_stylebox_override("panel", st)
	_results.theme = UiStyle.theme()
	_results.visible = false
	add_child(_results)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_results.add_child(col)
	_res_title = _text(72, Color("ff6a5a"))
	col.add_child(_res_title)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 4)
	col.add_child(_stats)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	buttons.add_child(UiStyle.button("TRY AGAIN", "", func() -> void: again.emit()))
	buttons.add_child(UiStyle.button("MAIN MENU", "", func() -> void: main_menu.emit()))


func _text(size: int, color: Color) -> Label:
	var l := UiStyle.label("", size, color)
	l.add_theme_font_override("font", _comic)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Every frame, from the director (null: not in a run, hide it all but the results).
func update(dt: float, d: Director, enemies: Enemies) -> void:
	_banner_t = maxf(0.0, _banner_t - dt)
	_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	_wave.visible = d != null
	_wave_sub.visible = d != null
	if d == null:
		_boss.visible = false
		return
	match d.phase:
		"start":
			_wave.text = "STAGE %d" % d.stage
			_wave_sub.text = "FIRST WAVE IN %d" % ceili(d.t)
		"wave":
			_wave.text = "WAVE %d / %d" % [d.wave, Director.WAVES]
			_wave_sub.text = "%d LEFT" % d.left()
		"break":
			_wave.text = "WAVE %d / %d" % [d.wave, Director.WAVES]
			_wave_sub.text = "NEXT WAVE IN %d" % ceili(d.t)
		"boss_warn", "boss":
			_wave.text = "BOSS"
			_wave_sub.text = "STAGE %d" % d.stage
		"cleared", "next":
			_wave.text = "STAGE CLEARED"
			_wave_sub.text = "NEXT STAGE IN %d" % ceili(maxf(0.0, d.t))
	var b := d.boss
	_boss.visible = b != null and b.alive and not b.target.dead
	if _boss.visible:
		_boss_name.text = String(b.def.name).to_upper()
		_boss_fill.size.x = 640.0 * clampf(b.target.hp / b.target.max_hp, 0.0, 1.0)


func banner(title: String, sub := "", color := Color.WHITE, time := 2.6) -> void:
	_b_title.text = title
	_b_title.add_theme_color_override("font_color", color)
	_b_sub.text = sub
	_banner_t = time


## The run is over: what you did, and the way out. stats: [[label, value], ...]
func show_results(title: String, color: Color, stats: Array) -> void:
	_res_title.text = title
	_res_title.add_theme_color_override("font_color", color)
	for c in _stats.get_children():
		c.queue_free()
	for row: Array in stats:
		var r := HBoxContainer.new()
		var k := UiStyle.label(String(row[0]).to_upper(), 20, UiStyle.MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(k)
		r.add_child(UiStyle.label(str(row[1]), 24, UiStyle.TEXT))
		_stats.add_child(r)
	_banner_t = 0.0 # no banner over it
	_results.visible = true


func hide_results() -> void:
	_results.visible = false


func results_up() -> bool:
	return _results.visible
