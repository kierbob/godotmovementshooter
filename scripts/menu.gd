class_name Menu
extends CanvasLayer
## Main menu, map picker, loadout, settings and the pause menu (the web game's menu.js, rebuilt in
## Godot).
## The game (main.gd) listens to the signals and decides what actually happens.

signal play(map_id: String)
signal play_trial(guns: bool) # straight onto the dev map's time trial course
signal resume
signal to_main_menu
signal quit_game
signal host_match(port: int)
signal join_match(address: String)
signal cancel_online
signal settings_changed(what: String) # "video" | "quality" | "lighting" | "audio" | "mouse" | "binds" | "loadout"

const TOP_H := 64
## Map cards come from each map scene's root (MapRoot: name, tag, desc, art, colors).
var map_info := {} # id -> {name, tag, desc, art, grad}
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
var _top: Control
var _top_tabs := {}
var _screens := {}
var _main_card_slot: Control
var _hint: Label
var _map_grid: HBoxContainer
var _trial_grid: HBoxContainer
var _settings_body: VBoxContainer
var _settings_scroll: ScrollContainer
var _side_tabs := {}
var _pause_mode: Label
var _key_buttons := {}
var _chips: HFlowContainer
var loadout_slot := "primary" # slot being edited on the loadout screen
var _preview_id := "" # item hovered on the loadout screen ("" = show the equipped one)
var _showcase: Showcase
var _loadout_slots: VBoxContainer
var _items_title: Label
var _items_count: Label
var _items_row: HBoxContainer
var _stage_info: VBoxContainer
var _thumb_rects := {} # item id -> [TextureRect] waiting for / showing its thumbnail
var online := false # in a multiplayer match: the pause menu says so
var _maps_back := "main" # where picking a map returns to
var _online_status: Label
var _online_cancel: Button
var _online_host_map: Label
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
	_screens.loadout = _build_loadout()
	_screens.settings = _build_settings()
	_screens.online = _build_online()
	_screens.pause = _build_pause()
	_top = _build_topbar()
	show_screen("")


func show_screen(s: String) -> void:
	screen = s
	listening = ""
	visible = s != ""
	for k: String in _screens:
		(_screens[k] as Control).visible = k == s
	var with_top := s in ["main", "maps", "loadout", "online"] or (s == "settings" and _settings_back != "pause")
	_top.visible = with_top
	(_screens.settings as Control).offset_top = TOP_H if with_top else 0
	for k: String in _top_tabs:
		(_top_tabs[k] as Button).set_pressed_no_signal(k == s or (k == _maps_back and s == "maps"))
	match s:
		"main": _refresh_main()
		"maps": _refresh_maps()
		"loadout": _open_loadout()
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
			"maps": show_screen(_maps_back)
			"loadout": show_screen("main")
			"online":
				cancel_online.emit()
				show_screen("main")
			"pause": resume.emit()
			_: return
		get_viewport().set_input_as_handled()


# ---------- top bar ----------

func _build_topbar() -> Control:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_H
	bar.add_child(UiStyle.fill_rect(Color(0.03, 0.047, 0.157, 0.82)))
	var line := UiStyle.fill_rect(UiStyle.LINE)
	line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -2
	bar.add_child(line)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28
	row.offset_right = -20
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 8)
	logo.add_child(UiStyle.label("MOVEMENT", 34, UiStyle.TEXT, true))
	logo.add_child(UiStyle.label("SHOOTER", 34, UiStyle.YELLOW, true))
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(logo)
	row.add_child(_spacer(26))
	var group := ButtonGroup.new()
	for t: Array in [["main", "PLAY"], ["online", "MULTIPLAYER"], ["loadout", "LOADOUT"], ["settings", "SETTINGS"]]:
		var b := UiStyle.button(t[1], "TopTab")
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_vertical = Control.SIZE_FILL
		if t[0] == "loadout":
			b.pressed.connect(func() -> void: show_screen("loadout"))
		elif t[0] == "settings":
			b.pressed.connect(func() -> void: open_settings("main"))
		elif t[0] == "online":
			b.pressed.connect(func() -> void: show_screen("online"))
		else:
			b.pressed.connect(func() -> void: show_screen("main"))
		_top_tabs[t[0]] = b
		row.add_child(b)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	var build := UiStyle.label("GODOT BUILD", 20, UiStyle.MUTED)
	build.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(build)
	row.add_child(_spacer(16))
	var quit := UiStyle.button("QUIT", "", func() -> void: quit_game.emit())
	quit.add_theme_font_size_override("font_size", 22)
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(quit)
	_root.add_child(bar)
	return bar


# ---------- main ----------

func _build_main() -> Control:
	var s := _screen_root()
	# darken the bottom so the play area reads over the orbiting map
	s.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.03, 0.055, 0.2, 0), Color(0.03, 0.055, 0.2, 0), Color(0.03, 0.055, 0.2, 0.9)]),
		1, PackedFloat32Array([0.0, 0.5, 1.0])))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_left = -448
	col.offset_top = -620 # room for the loadout chips when they wrap
	col.offset_right = -48
	col.offset_bottom = -44
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	_chips = HFlowContainer.new() # wraps onto a second line when the names are long
	_chips.alignment = FlowContainer.ALIGNMENT_END
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	col.add_child(_chips)
	_main_card_slot = VBoxContainer.new()
	col.add_child(_main_card_slot)
	var play_btn := UiStyle.button("PLAY", "PlayButton", func() -> void: play.emit(Settings.map))
	play_btn.custom_minimum_size.y = 84
	col.add_child(play_btn)
	_hint = UiStyle.note("", 14, Color("ffb86b"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)
	s.add_child(col)
	var tips := UiStyle.note("Esc pauses · F4 stats · F11 fullscreen", 13)
	tips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tips.offset_left = 28
	tips.offset_top = -40
	tips.offset_right = 400
	tips.offset_bottom = -16
	s.add_child(tips)
	return s


func _refresh_main() -> void:
	for c in _main_card_slot.get_children():
		c.queue_free()
	_main_card_slot.add_child(_map_card(Settings.map, "CHANGE MAP", func() -> void:
		_maps_back = "main"
		show_screen("maps")))
	for c in _chips.get_children():
		c.queue_free()
	for slot: Dictionary in Items.SLOTS:
		_chips.add_child(_chip(slot.label, Items.item(slot.id, Settings.loadout[slot.id]).name))


## Small "PRIMARY Boomstick" tag above the map card.
func _chip(kind: String, value: String) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.047, 0.157, 0.8)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var k := UiStyle.label(kind.to_upper(), 15, UiStyle.YELLOW)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	row.add_child(UiStyle.label(value.to_upper(), 20))
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ---------- loadout (locker) ----------

func _build_loadout() -> Control:
	var s := _screen_root(TOP_H)
	s.add_child(_menu_backdrop())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	s.add_child(row)
	# left: title + the three slot cards
	var nav := Control.new()
	nav.custom_minimum_size.x = 300
	nav.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.02, 0.03, 0.11, 0.85), Color(0.02, 0.03, 0.11, 0.45)])))
	var edge := UiStyle.fill_rect(UiStyle.LINE)
	edge.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	edge.offset_left = -2
	nav.add_child(edge)
	_loadout_slots = VBoxContainer.new()
	_loadout_slots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loadout_slots.offset_left = 28
	_loadout_slots.offset_top = 22
	_loadout_slots.offset_right = -22
	_loadout_slots.offset_bottom = -22
	_loadout_slots.add_theme_constant_override("separation", 10)
	nav.add_child(_loadout_slots)
	row.add_child(nav)
	# right: the stage on top, the item tiles below
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	right.add_child(stage)
	# soft purple glow behind the item, and a yellow "floor" under it
	var glow := _radial(Color(0.55, 0.35, 1.0, 0.35))
	glow.anchor_left = 0.35
	glow.anchor_right = 0.9
	glow.anchor_top = 0.05
	glow.anchor_bottom = 0.95
	stage.add_child(glow)
	var floor_glow := _radial(Color(1, 0.88, 0.2, 0.28))
	floor_glow.anchor_left = 0.3
	floor_glow.anchor_right = 1.05
	floor_glow.anchor_top = 0.72
	floor_glow.anchor_bottom = 0.92
	stage.add_child(floor_glow)
	_showcase = Showcase.new()
	_showcase.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_showcase)
	_stage_info = VBoxContainer.new()
	_stage_info.position = Vector2(36, 26)
	_stage_info.custom_minimum_size.x = 380
	_stage_info.add_theme_constant_override("separation", 0)
	_stage_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_stage_info)
	var hint := UiStyle.label("DRAG TO SPIN", 18, Color(1, 1, 1, 0.35))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -200
	hint.offset_top = -40
	hint.offset_right = -24
	hint.offset_bottom = -14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hint)
	var items := MarginContainer.new()
	items.add_theme_constant_override("margin_left", 32)
	items.add_theme_constant_override("margin_right", 28)
	items.add_theme_constant_override("margin_top", 6)
	items.add_theme_constant_override("margin_bottom", 22)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 8)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	_items_title = UiStyle.label("", 24, UiStyle.MUTED)
	title_row.add_child(_items_title)
	var count_box := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(1, 1, 1, 0.1)
	cs.content_margin_left = 7
	cs.content_margin_right = 7
	count_box.add_theme_stylebox_override("panel", cs)
	count_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_items_count = UiStyle.label("", 17)
	count_box.add_child(_items_count)
	title_row.add_child(count_box)
	iv.add_child(title_row)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 136
	_items_row = HBoxContainer.new()
	_items_row.add_theme_constant_override("separation", 12)
	scroll.add_child(_items_row)
	iv.add_child(scroll)
	items.add_child(iv)
	right.add_child(items)
	return s


## Soft oval glow (a radial gradient fading to clear).
func _radial(color: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([color, Color(color, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _open_loadout() -> void:
	_preview_id = ""
	_refresh_loadout()
	var ids: Array = Items.WEAPONS.keys() + Items.ABILITIES.keys()
	_showcase.render_thumbnails(ids, func(id: String, tex: Texture2D) -> void:
		for r: TextureRect in _thumb_rects.get(id, []):
			if is_instance_valid(r):
				r.texture = tex)


func _thumb(id: String, rect_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _showcase.thumb(id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = rect_size
	r.size = rect_size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _thumb_rects.has(id):
		_thumb_rects[id] = []
	_thumb_rects[id].append(r)
	return r


func _flat(color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	return st


func _refresh_loadout() -> void:
	_thumb_rects.clear()
	for c in _loadout_slots.get_children():
		c.queue_free()
	_loadout_slots.add_child(UiStyle.label("LOADOUT", 56, UiStyle.TEXT, true))
	for slot: Dictionary in Items.SLOTS:
		_loadout_slots.add_child(_slot_card(slot))

	var slot_info: Dictionary = Items.SLOTS.filter(func(x: Dictionary) -> bool: return x.id == loadout_slot)[0]
	var items := Items.items_for_slot(loadout_slot)
	_items_title.text = String(slot_info.title).to_upper()
	_items_count.text = str(items.size())
	for c in _items_row.get_children():
		c.queue_free()
	for it: Dictionary in items:
		_items_row.add_child(_item_tile(it))
	_refresh_stage()


func _slot_card(slot: Dictionary) -> Button:
	var id: String = slot.id
	var selected := id == loadout_slot
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, 92)
	card.clip_contents = true
	card.add_theme_stylebox_override("normal", _flat(Color(1, 0.88, 0.2, 0.14) if selected else Color(1, 1, 1, 0.06)))
	card.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.12)))
	card.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.12)))
	card.pressed.connect(func() -> void:
		loadout_slot = id
		_preview_id = ""
		_refresh_loadout())
	var item_id: String = Settings.loadout[id]
	var th := _thumb(item_id, Vector2(120, 68))
	th.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	th.offset_left = -112
	th.offset_top = 2
	th.offset_right = 8
	th.offset_bottom = 70
	th.modulate.a = 0.95 if selected else 0.55
	card.add_child(th)
	var bar := UiStyle.fill_rect(UiStyle.YELLOW if selected else UiStyle.LINE)
	bar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_right = 7 if selected else 5
	card.add_child(bar)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20
	v.offset_top = 10
	v.offset_right = -10
	v.add_theme_constant_override("separation", 0)
	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	label_row.add_child(UiStyle.label(String(slot.label).to_upper(), 18, UiStyle.YELLOW if selected else UiStyle.MUTED))
	var kb := PanelContainer.new()
	var ks := _flat(Color(0, 0, 0, 0.4))
	ks.set_corner_radius_all(3)
	ks.content_margin_left = 6
	ks.content_margin_right = 6
	kb.add_theme_stylebox_override("panel", ks)
	kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kb.add_child(UiStyle.label(Settings.bind_label(Settings.binds[id]).to_upper(), 13))
	label_row.add_child(kb)
	v.add_child(label_row)
	var name_l := UiStyle.label(String(Items.item(id, item_id).name).to_upper(), 32)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	name_l.add_theme_constant_override("outline_size", 6)
	v.add_child(name_l)
	card.add_child(v)
	_ignore_mouse(v)
	return card


func _item_tile(it: Dictionary) -> Button:
	var id: String = it.id
	var equipped: bool = Settings.loadout[loadout_slot] == id
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(190, 128)
	var normal := _flat(Color(1, 1, 1, 0.06))
	var hover := _flat(Color(1, 1, 1, 0.12))
	for st: StyleBoxFlat in [normal, hover]:
		st.set_border_width_all(2)
		st.border_color = UiStyle.YELLOW if equipped else Color(1, 1, 1, 0.12)
	tile.add_theme_stylebox_override("normal", normal)
	tile.add_theme_stylebox_override("hover", hover)
	tile.add_theme_stylebox_override("pressed", hover)
	var th := _thumb(id, Vector2(180, 96))
	th.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	th.offset_top = 2
	th.offset_bottom = 98
	tile.add_child(th)
	var name_l := UiStyle.label(String(it.name).to_upper(), 22)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_left = 12
	name_l.offset_right = -8
	name_l.offset_top = -34
	name_l.offset_bottom = -6
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	name_l.add_theme_constant_override("outline_size", 4)
	tile.add_child(name_l)
	if equipped:
		var tag := PanelContainer.new()
		var ts := _flat(UiStyle.YELLOW)
		ts.content_margin_left = 8
		ts.content_margin_right = 8
		tag.add_theme_stylebox_override("panel", ts)
		tag.position = Vector2(8, 8)
		tag.add_child(UiStyle.label("EQUIPPED", 15, UiStyle.INK))
		tile.add_child(tag)
	_ignore_mouse(name_l)
	tile.mouse_entered.connect(func() -> void:
		_preview_id = id
		_refresh_stage())
	tile.mouse_exited.connect(func() -> void:
		if _preview_id == id:
			_preview_id = ""
			_refresh_stage())
	tile.pressed.connect(func() -> void:
		Settings.loadout[loadout_slot] = id
		Settings.save_settings()
		settings_changed.emit("loadout")
		_preview_id = ""
		_refresh_loadout())
	return tile


func _refresh_stage() -> void:
	var equipped_id: String = Settings.loadout[loadout_slot]
	var id := _preview_id if _preview_id != "" else equipped_id
	var it := Items.item(loadout_slot, id)
	var stats := Items.ability_stats(it) if loadout_slot == "ability" else Items.weapon_stats(it)
	for c in _stage_info.get_children():
		c.queue_free()
	_stage_info.add_child(UiStyle.label(Items.item_class(it).to_upper(), 18, UiStyle.YELLOW))
	_stage_info.add_child(UiStyle.label(String(it.name).to_upper(), 84, UiStyle.TEXT, true))
	var desc := UiStyle.note(it.desc, 14, Color("c9d1f5"))
	desc.custom_minimum_size.x = 340
	_stage_info.add_child(desc)
	_stage_info.add_child(_spacer(0, 16))
	for stat: Array in stats:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		var sl := UiStyle.label(String(stat[0]).to_upper(), 18, UiStyle.MUTED)
		sl.custom_minimum_size.x = 84
		r.add_child(sl)
		var seg := HBoxContainer.new()
		seg.add_theme_constant_override("separation", 3)
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in 10:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(13, 9)
			cell.color = UiStyle.YELLOW if i < roundi(float(stat[1]) * 10) else Color(1, 1, 1, 0.12)
			seg.add_child(cell)
		r.add_child(seg)
		r.add_child(UiStyle.label(String(stat[2]).to_upper(), 20))
		_stage_info.add_child(r)
		_stage_info.add_child(_spacer(0, 4))
	_stage_info.add_child(_spacer(0, 14))
	var equipped := id == equipped_id
	var state := PanelContainer.new()
	var ss := _flat(UiStyle.YELLOW if equipped else Color(0, 0, 0, 0))
	ss.set_border_width_all(2)
	ss.border_color = UiStyle.YELLOW if equipped else UiStyle.LINE
	ss.content_margin_left = 14
	ss.content_margin_right = 14
	ss.content_margin_top = 2
	ss.content_margin_bottom = 2
	state.add_theme_stylebox_override("panel", ss)
	state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	state.add_child(UiStyle.label("EQUIPPED" if equipped else "CLICK TO EQUIP", 20, Color("15151a") if equipped else UiStyle.MUTED))
	_stage_info.add_child(state)
	_ignore_mouse(_stage_info)
	_showcase.show_item(id)


# ---------- map picker ----------

func _build_maps() -> Control:
	var s := _screen_root(TOP_H)
	s.add_child(_menu_backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 80
	col.offset_top = 36
	col.offset_right = -80
	col.add_theme_constant_override("separation", 26)
	col.add_child(_screen_head("Choose where to play", "Select Map", func() -> void: show_screen(_maps_back)))
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
	for id: String in map_info:
		var pick := func() -> void:
			Settings.map = id
			Settings.save_settings()
			show_screen(_maps_back)
		_map_grid.add_child(_map_card(id, "SELECTED" if id == Settings.map else "", pick, id == Settings.map))
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
	var s := _screen_root(TOP_H)
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
	var s := _screen_root(TOP_H)
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

	var host := _online_card("HOST A MATCH", "You run the match on this PC and play in it. Friends join you.")
	var hv: VBoxContainer = host.get_meta("body")
	_online_host_map = UiStyle.label("", 30)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 14)
	var ml := UiStyle.label("MAP", 22, UiStyle.MUTED)
	ml.custom_minimum_size.x = 90
	map_row.add_child(ml)
	_online_host_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_row.add_child(_online_host_map)
	map_row.add_child(UiStyle.button("CHANGE", "", func() -> void:
		_maps_back = "online"
		show_screen("maps")))
	hv.add_child(map_row)
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

	var join := _online_card("JOIN A MATCH", "Paste the address your friend sent you.")
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
	jv.add_child(UiStyle.note("You'll play on the host's map with your own loadout. Everyone needs the same version of the game.", 14))
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
	_online_host_map.text = String(map_info.get(Settings.map, {}).get("name", Settings.map)).to_upper()
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
