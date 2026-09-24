class_name Menu
extends CanvasLayer
## The menus, Risk of Rain style: main screen (singleplayer / multiplayer / practice / settings),
## the lobby (character select + ready, LobbyScreen), host/join, the practice map picker, settings
## and the pause menu. The game (main.gd) listens to the signals and decides what happens.

signal play(map_id: String) # practice on a map
signal play_trial(guns: bool) # straight onto the dev map's time trial course
signal lobby_character(id: String)
signal lobby_ready(on: bool)
signal lobby_leave
signal resume
signal to_main_menu
signal quit_game
signal host_match(port: int)
signal join_match(address: String)
signal cancel_online
signal settings_changed(what: String) # "video" | "quality" | "lighting" | "audio" | "mouse" | "binds"

## Map cards come from each map scene's root (MapRoot: name, tag, desc, art, colors).
var map_info := {} # id -> {name, tag, desc, art, grad}
## Maps on the practice screen (stages are for runs).
const PRACTICE_MAPS := ["dev_map"]
## Time trial cards on the map screen (not maps you can select: they start the course right away).
const TRIAL_INFO := {
	"trial_off": {
		"tag": "Time trial", "name": "Guns Off", "art": "RUN",
		"desc": "Pure movement · slide, gap jumps, wall jumps, launcher · best time saved",
		"grad": [Color("19c98a"), Color("1f6dff")],
	},
	"trial_on": {
		"tag": "Time trial", "name": "Guns On", "art": "BOOM",
		"desc": "Same course, guns allowed · shotgun boosts and rocket jumps · best time saved",
		"grad": [Color("ff9a3c"), Color("ff3c7a")],
	},
}

var screen := ""
var listening := "" # action waiting for a new key while rebinding
var map_name := "" # shown on the pause menu
var _settings_back := "main"
var _settings_tab := "mouse"

var _root: Control
var _screens := {}
var lobby: LobbyScreen
var lobby_mode := "" # "solo" | "host" | "client" while the lobby is up
var _hint: Label
var _map_grid: HBoxContainer
var _trial_grid: HBoxContainer
var _settings_body: VBoxContainer
var _settings_scroll: ScrollContainer
var _side_tabs := {}
var _pause_mode: Label
var _key_buttons := {}
var online := false # in a multiplayer match: the pause menu says so
var _online_status: Label
var _online_cancel: Button
var _online_ips: Label
var _pause_title: Label
var _pause_leave: Button
var _pause_note: Label


func _ready() -> void:
	layer = 10
	for id in MapData.list():
		map_info[id] = MapData.info(id)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiStyle.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_screens.main = _build_main()
	_screens.maps = _build_maps()
	_screens.settings = _build_settings()
	_screens.online = _build_online()
	lobby = LobbyScreen.new()
	_root.add_child(lobby)
	lobby.character_picked.connect(func(id: String) -> void: lobby_character.emit(id))
	lobby.ready_toggled.connect(func(on: bool) -> void: lobby_ready.emit(on))
	lobby.leave.connect(func() -> void: lobby_leave.emit())
	_screens.lobby = lobby
	_screens.pause = _build_pause()
	show_screen("")


func show_screen(s: String) -> void:
	screen = s
	listening = ""
	visible = s != ""
	for k: String in _screens:
		(_screens[k] as Control).visible = k == s
	if s != "lobby":
		lobby_mode = ""
	match s:
		"main": _refresh_main()
		"maps": _refresh_maps()
		"settings": _refresh_settings()
		"online": _refresh_online()
		"pause": _refresh_pause()


func open_settings(from: String) -> void:
	_settings_back = from
	show_screen("settings")


func set_hint(text: String) -> void:
	_hint.text = text


# ---------- input: rebinding + Esc ----------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if listening != "":
		var is_press: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)
		if not is_press:
			return
		get_viewport().set_input_as_handled()
		if not (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
			Settings.bind(listening, Settings.bind_for(event))
			Settings.save_settings()
			settings_changed.emit("binds")
		listening = ""
		_refresh_binds()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		match screen:
			"settings": show_screen(_settings_back)
			"maps": show_screen("main")
			"lobby": lobby_leave.emit()
			"online":
				cancel_online.emit()
				show_screen("main")
			"pause": resume.emit()
			_: return
		get_viewport().set_input_as_handled()


# ---------- main ----------

## Risk of Rain style: the title and a column of big buttons over the orbiting map.
func _build_main() -> Control:
	var s := _screen_root()
	s.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.02, 0.03, 0.12, 0.92), Color(0.02, 0.03, 0.12, 0.7),
		Color(0.02, 0.03, 0.12, 0.0)]), 0, PackedFloat32Array([0.0, 0.35, 0.75])))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 80
	col.offset_top = 70
	col.offset_right = 700
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 6)
	s.add_child(col)
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -34)
	logo.add_child(UiStyle.label("MOVEMENT", 110, UiStyle.TEXT, true))
	logo.add_child(UiStyle.label("SHOOTER", 110, UiStyle.YELLOW, true))
	col.add_child(logo)
	col.add_child(_spacer(0, 40))
	for t: Array in [
		["SINGLEPLAYER", func() -> void: open_lobby("solo")],
		["MULTIPLAYER", func() -> void: show_screen("online")],
		["PRACTICE", func() -> void: show_screen("maps")],
		["SETTINGS", func() -> void: open_settings("main")],
	]:
		var b := UiStyle.button(t[0], "NavButton", t[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = 420
		if t[0] == "MULTIPLAYER":
			# Parked while the solo roguelite comes together (the code is still there).
			b.disabled = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.add_child(b)
			var soon := UiStyle.label("COMING LATER", 20, UiStyle.MUTED)
			soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(soon)
			col.add_child(row)
			continue
		col.add_child(b)
	var quit := UiStyle.button("QUIT", "DangerNav", func() -> void: quit_game.emit())
	quit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit.custom_minimum_size.x = 420
	col.add_child(quit)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(push)
	_hint = UiStyle.note("", 14, Color("ffb86b"))
	col.add_child(_hint)
	col.add_child(UiStyle.note("Esc pauses · F4 stats · F11 fullscreen · Godot build", 13))
	return s


func _refresh_main() -> void:
	pass


# ---------- lobby ----------

## The character select / ready screen before a run. mode: "solo" | "host" | "client".
func open_lobby(mode: String, host_note := "") -> void:
	show_screen("lobby")
	lobby_mode = mode
	lobby.open(mode, host_note)

# ---------- map picker ----------

func _build_maps() -> Control:
	var s := _screen_root()
	s.add_child(_menu_backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80
	col.offset_top = 36
	col.offset_right = -80
	col.add_theme_constant_override("separation", 26)
	col.add_child(_screen_head("Free play with the dummies · time trials", "Practice", func() -> void: show_screen("main")))
	_map_grid = HBoxContainer.new()
	_map_grid.add_theme_constant_override("separation", 28)
	col.add_child(_map_grid)
	col.add_child(UiStyle.kicker("Time trials · on the Dev Arena course"))
	_trial_grid = HBoxContainer.new()
	_trial_grid.add_theme_constant_override("separation", 28)
	col.add_child(_trial_grid)
	s.add_child(col)
	return s


func _refresh_maps() -> void:
	for c in _map_grid.get_children():
		c.queue_free()
	for id: String in PRACTICE_MAPS:
		if map_info.has(id):
			_map_grid.add_child(_map_card(id, "PLAY", func() -> void: play.emit(id)))
	for c in _trial_grid.get_children():
		c.queue_free()
	for id: String in TRIAL_INFO:
		var guns := id == "trial_on"
		var card := _map_card(id, "PLAY", func() -> void: play_trial.emit(guns), false, 64)
		card.custom_minimum_size.y = 210 # art strip + the info block (the card is a Button: it needs a real size to be clickable)
		_trial_grid.add_child(card)


## Card with gradient art, a big faded label, a badge, and the map's name + blurb.
func _map_card(id: String, badge: String, on_press: Callable, selected := false, art_h := 150) -> Button:
	var info: Dictionary = map_info.get(id, TRIAL_INFO.get(id, {"tag": "", "name": id, "art": "", "desc": "",
		"grad": [Color("2f6bff"), Color("8a3dff")]}))
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(400, 292)
	card.clip_contents = false
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.set_border_width_all(3)
	border.border_color = UiStyle.YELLOW if selected else Color(1, 1, 1, 0.85)
	border.set_expand_margin_all(3)
	var border_hover := border.duplicate() as StyleBoxFlat
	border_hover.border_color = UiStyle.YELLOW
	for st in ["normal", "focus", "disabled"]:
		card.add_theme_stylebox_override(st, border)
	for st in ["hover", "pressed", "hover_pressed"]:
		card.add_theme_stylebox_override(st, border_hover)
	card.pressed.connect(on_press)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	var art := Control.new()
	art.custom_minimum_size.y = art_h
	art.clip_contents = true
	art.add_child(UiStyle.gradient_rect(PackedColorArray(info.grad), 2))
	var big := UiStyle.label(info.art, 150, Color(1, 1, 1, 0.2), true)
	big.remove_theme_color_override("font_shadow_color")
	big.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	big.offset_left = -420
	big.offset_top = -150
	big.offset_right = 14
	big.offset_bottom = 34
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	art.add_child(big)
	if badge != "":
		var bp := PanelContainer.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = UiStyle.YELLOW if badge == "SELECTED" else Color(0.03, 0.047, 0.157, 0.8)
		bs.content_margin_left = 10
		bs.content_margin_right = 10
		bs.content_margin_top = 1
		bs.content_margin_bottom = 1
		bp.add_theme_stylebox_override("panel", bs)
		bp.position = Vector2(12, 10)
		bp.add_child(UiStyle.label(badge, 17, UiStyle.INK if badge == "SELECTED" else UiStyle.TEXT))
		art.add_child(bp)
	v.add_child(art)
	var info_box := PanelContainer.new()
	var ib := StyleBoxFlat.new()
	ib.bg_color = UiStyle.INK
	ib.content_margin_left = 16
	ib.content_margin_right = 16
	ib.content_margin_top = 8
	ib.content_margin_bottom = 12
	info_box.add_theme_stylebox_override("panel", ib)
	info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	iv.add_child(UiStyle.label(String(info.tag).to_upper(), 17, UiStyle.YELLOW))
	iv.add_child(UiStyle.label(String(info.name).to_upper(), 42))
	iv.add_child(UiStyle.note(info.desc, 13))
	info_box.add_child(iv)
	v.add_child(info_box)
	_ignore_mouse(v)
	return card


# ---------- settings ----------

func _build_settings() -> Control:
	var s := _screen_root()
	s.add_child(_menu_backdrop())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	s.add_child(row)
	# left: title + tabs + back
	var nav := Control.new()
	nav.custom_minimum_size.x = 300
	nav.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.02, 0.03, 0.11, 0.9), Color(0.02, 0.03, 0.11, 0.5)])))
	var edge := UiStyle.fill_rect(UiStyle.LINE)
	edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	edge.offset_left = -2
	nav.add_child(edge)
	var nv := VBoxContainer.new()
	nv.set_anchors_preset(Control.PRESET_FULL_RECT)
	nv.offset_left = 28
	nv.offset_top = 22
	nv.offset_right = -22
	nv.offset_bottom = -22
	nv.add_theme_constant_override("separation", 8)
	nv.add_child(UiStyle.label("SETTINGS", 56, UiStyle.TEXT, true))
	var group := ButtonGroup.new()
	for t: Array in [["mouse", "MOUSE"], ["video", "VIDEO"], ["audio", "AUDIO"], ["controls", "CONTROLS"]]:
		var b := UiStyle.button(t[1], "SideTab")
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_settings_tab = t[0]
			_refresh_settings())
		_side_tabs[t[0]] = b
		nv.add_child(b)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nv.add_child(push)
	var back := UiStyle.button("BACK  ·  ESC", "", func() -> void: show_screen(_settings_back))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	nv.add_child(back)
	nav.add_child(nv)
	row.add_child(nav)
	# right: the selected tab's content
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	_settings_body = VBoxContainer.new()
	_settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_body.add_theme_constant_override("separation", 14)
	margin.add_child(_settings_body)
	_settings_scroll.add_child(margin)
	row.add_child(_settings_scroll)
	return s


func _refresh_settings() -> void:
	for k: String in _side_tabs:
		(_side_tabs[k] as Button).set_pressed_no_signal(k == _settings_tab)
	# Over the paused game the backdrop is see-through, so you can still see where you are.
	var backdrop: Control = (_screens.settings as Control).get_child(0)
	backdrop.modulate.a = 0.8 if _settings_back == "pause" else 1.0
	for c in _settings_body.get_children():
		c.queue_free()
	_key_buttons.clear()
	_settings_scroll.scroll_vertical = 0
	match _settings_tab:
		"mouse": _tab_mouse()
		"video": _tab_video()
		"audio": _tab_audio()
		"controls": _tab_controls()


func _section(kicker: String, title: String) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", -6)
	head.add_child(UiStyle.kicker(kicker))
	head.add_child(UiStyle.label(title.to_upper(), 78, UiStyle.TEXT, true))
	_settings_body.add_child(head)
	_settings_body.add_child(_spacer(0, 6))


func _row(label_text: String, content: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 20)
	var l := UiStyle.label(label_text.to_upper(), 28)
	l.custom_minimum_size.x = 210
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(l)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(content)
	_settings_body.add_child(r)
	return r


## Slider with a live value readout. fmt formats the value; on_change(v) is called while dragging.
func _slider_row(label_text: String, lo: float, hi: float, step: float, value: float, fmt: Callable, on_change: Callable) -> HSlider:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.y = 30
	sl.focus_mode = Control.FOCUS_NONE
	var val := UiStyle.label(fmt.call(value), 28)
	val.custom_minimum_size.x = 90
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		on_change.call(v))
	box.add_child(sl)
	box.add_child(val)
	_row(label_text, box)
	return sl


func _tab_mouse() -> void:
	_section("Aim", "Mouse")
	var info := UiStyle.note("", 14)
	var cm_text := func() -> String:
		return "%.1f cm/360° at 800 DPI · %.1f cm/360° at 1600 DPI" % [Settings.cm_per_360(800), Settings.cm_per_360(1600)]
	# Slider for dragging + a box for typing an exact value.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	var sl := HSlider.new()
	sl.min_value = 0.1
	sl.max_value = 10.0
	sl.step = 0.01
	sl.value = Settings.sensitivity
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.y = 30
	sl.focus_mode = Control.FOCUS_NONE
	var num := LineEdit.new()
	num.text = "%.2f" % Settings.sensitivity
	num.custom_minimum_size.x = 110
	num.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var set_sens := func(v: float, from_box: bool) -> void:
		if not is_finite(v) or v <= 0:
			return
		Settings.sensitivity = clampf(v, 0.05, 20.0)
		Settings.save_settings()
		if from_box:
			sl.set_value_no_signal(Settings.sensitivity)
		num.text = "%.2f" % Settings.sensitivity
		info.text = cm_text.call()
		settings_changed.emit("mouse")
	sl.value_changed.connect(func(v: float) -> void: set_sens.call(v, false))
	num.text_submitted.connect(func(t: String) -> void:
		set_sens.call(t.to_float(), true)
		num.release_focus())
	num.focus_exited.connect(func() -> void: set_sens.call(num.text.to_float(), true))
	box.add_child(sl)
	box.add_child(num)
	_row("Sensitivity", box)
	info.text = cm_text.call()
	_settings_body.add_child(_indent(info))
	_settings_body.add_child(_indent(UiStyle.note("Same scale as CS2 / Apex, so use your usual sens. Raw mouse input, no Windows acceleration.", 14)))
	_settings_body.add_child(_spacer(0, 10))
	_slider_row("Field of view", 60, 110, 1, Settings.fov, func(v: float) -> String: return "%d°" % v,
		func(v: float) -> void:
			Settings.fov = v
			Settings.save_settings()
			settings_changed.emit("mouse"))
	_settings_body.add_child(_indent(UiStyle.note("Vertical FOV (80 = the web game). It widens a little more when you're fast.", 14)))


func _tab_video() -> void:
	_section("Look & performance", "Video")
	var pick := func(field: String, what: String) -> Callable:
		return func(v: Variant) -> void:
			match field:
				"fullscreen": Settings.fullscreen = v
				"vsync": Settings.vsync = v
				"max_fps": Settings.max_fps = v
				"quality": Settings.quality = v
				"lighting": Settings.lighting = v
			Settings.save_settings()
			settings_changed.emit(what)
	_row("Display", UiStyle.segmented([[false, "Windowed"], [true, "Fullscreen"]], Settings.fullscreen, pick.call("fullscreen", "video")))
	_row("VSync", UiStyle.segmented([[true, "On"], [false, "Off"]], Settings.vsync, pick.call("vsync", "video")))
	var caps := []
	for c: int in Settings.FPS_CAPS:
		caps.append([c, "Unlimited" if c == 0 else str(c)])
	_row("FPS cap", UiStyle.segmented(caps, Settings.max_fps, pick.call("max_fps", "video")))
	_settings_body.add_child(_indent(UiStyle.note("The FPS cap only applies with VSync off.", 14)))
	var qs := []
	for q: String in Settings.QUALITY:
		qs.append([q, Settings.QUALITY[q].label])
	_row("Quality", UiStyle.segmented(qs, Settings.quality, pick.call("quality", "quality")))
	_settings_body.add_child(_indent(UiStyle.note("Lower quality = fewer pixels, less anti-aliasing and simpler shadows. Try Performance if you get frame drops.", 14)))
	_settings_body.add_child(_spacer(0, 8))
	# lighting tiles with a little sky swatch
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 14)
	var group := ButtonGroup.new()
	for id: String in Look.PRESETS:
		var p: Dictionary = Look.PRESETS[id]
		var b := Button.new()
		b.theme_type_variation = "SegButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == Settings.lighting
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 112)
		b.text = ""
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 8
		v.offset_right = -10
		v.offset_bottom = -6
		var sw := Control.new()
		sw.custom_minimum_size.y = 62
		sw.add_child(UiStyle.gradient_rect(PackedColorArray([p.sky[0], p.sky[1]]), 1))
		v.add_child(sw)
		var name_l := UiStyle.label(String(p.label).to_upper(), 24)
		v.add_child(name_l)
		b.add_child(v)
		_ignore_mouse(v)
		b.toggled.connect(func(on: bool) -> void:
			name_l.add_theme_color_override("font_color", UiStyle.INK if on else UiStyle.TEXT))
		name_l.add_theme_color_override("font_color", UiStyle.INK if b.button_pressed else UiStyle.TEXT)
		b.pressed.connect(func() -> void: pick.call("lighting", "lighting").call(id))
		tiles.add_child(b)
	_row("Lighting", tiles)


func _tab_audio() -> void:
	_section("Sound", "Audio")
	_slider_row("Master volume", 0, 1, 0.01, Settings.volume, func(v: float) -> String: return "%d%%" % roundi(v * 100),
		func(v: float) -> void:
			Settings.volume = v
			Settings.save_settings()
			settings_changed.emit("audio"))
	_settings_body.add_child(_indent(UiStyle.note("Sounds arrive with the effects update; this is saved for then.", 14)))


func _tab_controls() -> void:
	_section("Keybinds", "Controls")
	var groups := {}
	for a: Array in Settings.ACTIONS:
		if not groups.has(a[2]):
			groups[a[2]] = []
		groups[a[2]].append(a)
	for g: String in groups:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(UiStyle.label(g.to_upper(), 24, UiStyle.YELLOW))
		var ln := ColorRect.new()
		ln.color = UiStyle.LINE
		ln.custom_minimum_size.y = 2
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ln)
		_settings_body.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 26)
		grid.add_theme_constant_override("v_separation", 6)
		for a: Array in groups[g]:
			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(1, 1, 1, 0.04)
			rs.content_margin_left = 14
			rs.content_margin_right = 6
			rs.content_margin_top = 4
			rs.content_margin_bottom = 4
			row.add_theme_stylebox_override("panel", rs)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var h := HBoxContainer.new()
			var l := UiStyle.label(String(a[1]).to_upper(), 24)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(l)
			var action: String = a[0]
			var kb := UiStyle.button("", "KeyCap")
			kb.custom_minimum_size.x = 140
			kb.toggle_mode = true
			kb.pressed.connect(func() -> void:
				listening = action
				_refresh_binds())
			_key_buttons[action] = kb
			h.add_child(kb)
			row.add_child(h)
			grid.add_child(row)
		_settings_body.add_child(grid)
		_settings_body.add_child(_spacer(0, 6))
	_settings_body.add_child(UiStyle.note("Click a bind, then press a key or mouse button. Esc cancels. Binding a key that's already used swaps the two.", 14))
	var reset := UiStyle.button("RESET CONTROLS TO DEFAULTS", "", func() -> void:
		Settings.reset_binds()
		Settings.apply_input()
		Settings.save_settings()
		settings_changed.emit("binds")
		_refresh_binds())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_settings_body.add_child(reset)
	_refresh_binds()


func _refresh_binds() -> void:
	for action: String in _key_buttons:
		var kb: Button = _key_buttons[action]
		var on := listening == action
		kb.set_pressed_no_signal(on)
		kb.text = "PRESS A KEY…" if on else Settings.bind_label(Settings.binds[action]).to_upper()


# ---------- pause ----------

func _build_pause() -> Control:
	var s := _screen_root()
	s.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.02, 0.03, 0.11, 0.94), Color(0.02, 0.03, 0.11, 0.82),
		Color(0.02, 0.03, 0.11, 0.2), Color(0.02, 0.03, 0.11, 0.05)]), 0, PackedFloat32Array([0.0, 0.24, 0.62, 1.0])))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 56
	col.offset_top = 60
	col.offset_right = 500
	col.offset_bottom = -32
	col.add_theme_constant_override("separation", 4)
	_pause_mode = UiStyle.kicker("")
	col.add_child(_pause_mode)
	_pause_title = UiStyle.label("PAUSED", 124, UiStyle.TEXT, true)
	col.add_child(_pause_title)
	col.add_child(_spacer(0, 10))
	var resume_b := UiStyle.button("RESUME", "NavButton", func() -> void: resume.emit())
	resume_b.add_theme_color_override("font_color", UiStyle.YELLOW)
	for b: Button in [
		resume_b,
		UiStyle.button("SETTINGS", "NavButton", func() -> void: open_settings("pause")),
		_pause_leave_button(),
		UiStyle.button("QUIT GAME", "DangerNav", func() -> void: quit_game.emit()),
	]:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = 340
		col.add_child(b)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(push)
	_pause_note = UiStyle.note("", 14)
	col.add_child(_pause_note)
	s.add_child(col)
	return s


func _pause_leave_button() -> Button:
	_pause_leave = UiStyle.button("MAIN MENU", "NavButton", func() -> void: to_main_menu.emit())
	return _pause_leave


func _refresh_pause() -> void:
	_pause_mode.text = map_name.to_upper()
	_pause_title.text = "MENU" if online else "PAUSED"
	_pause_leave.text = "LEAVE MATCH" if online else "MAIN MENU"
	_pause_note.text = "Esc resumes. The match keeps going while you're in here: you can still be hit." if online \
		else "Esc resumes. The game is frozen while you're in here (it's solo)."


# ---------- multiplayer ----------

func _build_online() -> Control:
	var s := _screen_root()
	s.add_child(_menu_backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80
	col.offset_top = 36
	col.offset_right = -80
	col.offset_bottom = -30
	col.add_theme_constant_override("separation", 22)
	col.add_child(_screen_head("Play with friends", "Multiplayer", func() -> void:
		cancel_online.emit()
		show_screen("main")))
	# name
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	var nl := UiStyle.label("YOUR NAME", 26, UiStyle.MUTED)
	nl.custom_minimum_size.x = 180
	name_row.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.placeholder_text = "Bean"
	name_edit.max_length = 16
	name_edit.custom_minimum_size.x = 360
	name_edit.text_changed.connect(func(t: String) -> void:
		Settings.player_name = t
		Settings.save_settings())
	name_row.add_child(name_edit)
	col.add_child(name_row)
	# host | join
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 28)
	col.add_child(cards)

	var host := _online_card("HOST A LOBBY", "You run the game on this PC and play in it. Friends join your lobby.")
	var hv: VBoxContainer = host.get_meta("body")
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 14)
	var pl := UiStyle.label("PORT", 22, UiStyle.MUTED)
	pl.custom_minimum_size.x = 90
	port_row.add_child(pl)
	var port_edit := LineEdit.new()
	port_edit.text = str(Settings.host_port)
	port_edit.custom_minimum_size.x = 140
	port_edit.text_changed.connect(func(t: String) -> void:
		if t.is_valid_int() and int(t) >= 1024 and int(t) <= 65535:
			Settings.host_port = int(t)
			Settings.save_settings())
	port_row.add_child(port_edit)
	hv.add_child(port_row)
	var host_btn := UiStyle.button("HOST", "PlayButton", func() -> void: host_match.emit(Settings.host_port))
	host_btn.custom_minimum_size.y = 72
	hv.add_child(host_btn)
	hv.add_child(UiStyle.note("Over the internet: run playit.gg, add a UDP tunnel to this port, and send your friends the address it gives you (like abc.gl.at.ply.gg:12345).", 14))
	_online_ips = UiStyle.note("", 14)
	hv.add_child(_online_ips)
	cards.add_child(host)

	var join := _online_card("JOIN A LOBBY", "Paste the address your friend sent you.")
	var jv: VBoxContainer = join.get_meta("body")
	var addr := LineEdit.new()
	addr.text = Settings.join_address
	addr.placeholder_text = "abc.gl.at.ply.gg:12345  or  192.168.1.20:7777"
	addr.text_changed.connect(func(t: String) -> void:
		Settings.join_address = t.strip_edges()
		Settings.save_settings())
	addr.text_submitted.connect(func(_t: String) -> void: join_match.emit(Settings.join_address))
	jv.add_child(addr)
	var join_btn := UiStyle.button("JOIN", "PlayButton", func() -> void: join_match.emit(Settings.join_address))
	join_btn.custom_minimum_size.y = 72
	jv.add_child(join_btn)
	jv.add_child(UiStyle.note("You pick your character in the lobby. Everyone needs the same version of the game.", 14))
	cards.add_child(join)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	_online_status = UiStyle.label("", 24, Color("ffb86b"))
	status_row.add_child(_online_status)
	_online_cancel = UiStyle.button("CANCEL", "", func() -> void:
		cancel_online.emit()
		set_online_status(""))
	_online_cancel.visible = false
	status_row.add_child(_online_cancel)
	col.add_child(status_row)
	s.add_child(col)
	return s


func _online_card(title: String, blurb: String) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.047, 0.157, 0.85)
	st.set_border_width_all(2)
	st.border_color = Color(1, 1, 1, 0.2)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 16
	st.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(560, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UiStyle.label(title, 44, UiStyle.YELLOW, true))
	v.add_child(UiStyle.note(blurb, 15))
	p.add_child(v)
	p.set_meta("body", v)
	return p


func _refresh_online() -> void:
	var ips := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and ip.count(".") == 3):
			ips.append("%s:%d" % [ip, Settings.host_port])
	_online_ips.text = ("Same Wi-Fi: friends can use " + " or ".join(ips)) if not ips.is_empty() else ""


## Connecting / error text under the host and join cards ("" hides it). busy shows CANCEL.
func set_online_status(text: String, busy := false) -> void:
	_online_status.text = text
	_online_cancel.visible = busy


# ---------- helpers ----------

func _screen_root(top := 0) -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.offset_top = top
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(s)
	return s


## Dark purple-navy backdrop for full-screen menus (web .screen.modes / .screen.settings).
func _menu_backdrop() -> Control:
	var b := Control.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.04, 0.055, 0.19, 0.96), Color(0.086, 0.04, 0.22, 0.96)]), 1))
	return b


func _screen_head(kicker: String, title: String, on_back: Callable) -> Control:
	var head := HBoxContainer.new()
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", -6)
	left.add_child(UiStyle.kicker(kicker))
	left.add_child(UiStyle.label(title.to_upper(), 78, UiStyle.TEXT, true))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	var back := UiStyle.button("BACK  ·  ESC", "", on_back)
	back.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(back)
	return head


func _spacer(w := 0, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Line up a note under the row content (past the row label).
func _indent(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 230)
	m.add_child(c)
	return m


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)
