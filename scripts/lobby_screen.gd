class_name LobbyScreen
extends Control
## The lobby before a run (Risk of Rain style): pick your character on the left, see them on the
## stage in the middle (bean in their color, holding their main gun, with their kit listed), and
## the players on the right with who's ready. READY starts the run when everyone is; online, a
## short countdown runs first. Solo is the same screen with just you in it.

signal character_picked(id: String)
signal ready_toggled(on: bool)
signal leave

var ready_on := false
var _mode := "solo" # "solo" | "host" | "client"
var _kicker: Label
var _char_list: VBoxContainer
var _showcase: Showcase
var _info: VBoxContainer
var _players: VBoxContainer
var _stage_label: Label
var _status: Label
var _ready_btn: Button
var _host_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Control.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.add_child(UiStyle.gradient_rect(PackedColorArray([Color(0.04, 0.055, 0.19, 0.97), Color(0.086, 0.04, 0.22, 0.97)]), 1))
	add_child(back)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 56
	root.offset_top = 36
	root.offset_right = -56
	root.offset_bottom = -36
	root.add_theme_constant_override("separation", 28)
	add_child(root)

	# left: title + characters
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 10)
	_kicker = UiStyle.kicker("")
	left.add_child(_kicker)
	var title := UiStyle.label("CHOOSE YOUR BEAN", 58, UiStyle.TEXT, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(title)
	left.add_child(_gap(8))
	_char_list = VBoxContainer.new()
	_char_list.add_theme_constant_override("separation", 10)
	left.add_child(_char_list)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(push)
	var leave_btn := UiStyle.button("LEAVE  ·  ESC", "", func() -> void: leave.emit())
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(leave_btn)
	root.add_child(left)

	# middle: the character on the stage, their kit over it
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	_showcase = Showcase.new()
	_showcase.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_showcase)
	_info = VBoxContainer.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_info.offset_left = 8
	_info.offset_right = 520
	_info.offset_top = -330
	_info.offset_bottom = -8
	_info.alignment = BoxContainer.ALIGNMENT_END
	_info.add_theme_constant_override("separation", 2)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_info)
	root.add_child(stage)

	# right: players, stage, ready
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.add_theme_constant_override("separation", 12)
	right.add_child(UiStyle.kicker("Players"))
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.047, 0.157, 0.85)
	ps.set_border_width_all(2)
	ps.border_color = Color(1, 1, 1, 0.15)
	ps.content_margin_left = 16
	ps.content_margin_right = 16
	ps.content_margin_top = 12
	ps.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", ps)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 8)
	panel.add_child(_players)
	right.add_child(panel)
	_host_note = UiStyle.note("", 14)
	right.add_child(_host_note)
	var push2 := Control.new()
	push2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(push2)
	_stage_label = UiStyle.label("", 24, UiStyle.MUTED)
	right.add_child(_stage_label)
	_status = UiStyle.label("", 26, Color("ffb86b"))
	right.add_child(_status)
	_ready_btn = UiStyle.button("READY", "PlayButton", func() -> void: set_ready(not ready_on, true))
	_ready_btn.custom_minimum_size.y = 84
	right.add_child(_ready_btn)
	root.add_child(right)


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## mode: "solo" | "host" | "client". host_note: e.g. how friends can join.
func open(mode: String, host_note := "") -> void:
	_mode = mode
	ready_on = false
	_kicker.text = {"solo": "SINGLEPLAYER", "host": "MULTIPLAYER · HOSTING", "client": "MULTIPLAYER"}[mode]
	_host_note.text = host_note
	_stage_label.text = "FIRST STAGE · " + String(MapData.info(Characters.FIRST_STAGE).get("name", Characters.FIRST_STAGE)).to_upper()
	_status.text = ""
	_refresh_characters()
	_refresh_ready()
	if mode == "solo":
		set_players([{"name": Settings.player_name if Settings.player_name != "" else "You", "character": Settings.character,
			"ready": false, "you": true}])


func set_ready(on: bool, from_click := false) -> void:
	ready_on = on
	_refresh_ready()
	_refresh_characters() # locked in while ready
	if from_click:
		ready_toggled.emit(on)


func set_status(text: String) -> void:
	_status.text = text


## rows: [{name, character, ready, you}]
func set_players(rows: Array) -> void:
	for c in _players.get_children():
		c.queue_free()
	for r: Dictionary in rows:
		var info := Characters.get_info(r.character)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var sw := ColorRect.new()
		sw.color = info.color
		sw.custom_minimum_size = Vector2(10, 40)
		row.add_child(sw)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiStyle.label(String(r.name) + ("  (you)" if r.get("you", false) else ""), 26,
			UiStyle.YELLOW if r.get("you", false) else UiStyle.TEXT))
		col.add_child(UiStyle.label(String(info.name).to_upper(), 17, UiStyle.MUTED))
		row.add_child(col)
		var tag := UiStyle.label("READY" if r.ready else "PICKING", 22, Color("7ee787") if r.ready else UiStyle.MUTED)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
		_players.add_child(row)


func _refresh_ready() -> void:
	_ready_btn.text = "CANCEL" if ready_on else "READY"


func _refresh_characters() -> void:
	for c in _char_list.get_children():
		c.queue_free()
	for id: String in Characters.ORDER:
		_char_list.add_child(_char_button(id))
	var ch := Characters.get_info(Settings.character)
	_showcase.show_character(ch.id)
	for c in _info.get_children():
		c.queue_free()
	_info.add_child(UiStyle.label(String(ch.role).to_upper(), 20, UiStyle.YELLOW))
	_info.add_child(UiStyle.label(String(ch.name).to_upper(), 72, UiStyle.TEXT, true))
	var desc := UiStyle.note(ch.desc, 15, Color("c9d1f5"))
	desc.custom_minimum_size.x = 420
	_info.add_child(desc)
	_info.add_child(_gap(10))
	for slot: Array in [["PRIMARY", ch.primary, false], ["SECONDARY", ch.secondary, false], ["ABILITY", ch.ability, true]]:
		var it: Dictionary = Items.ABILITIES[slot[1]] if slot[2] else Items.WEAPONS[slot[1]]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		var k := UiStyle.label(slot[0], 17, UiStyle.MUTED)
		k.custom_minimum_size.x = 110
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(k)
		r.add_child(UiStyle.label(String(it.name).to_upper(), 28))
		_info.add_child(r)


func _char_button(id: String) -> Button:
	var ch := Characters.get_info(id)
	var picked := id == Settings.character
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 0.88, 0.2, 0.14) if picked else Color(1, 1, 1, 0.06)
	normal.set_border_width_all(2)
	normal.border_color = UiStyle.YELLOW if picked else Color(1, 1, 1, 0.1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.12)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.disabled = ready_on # locked in while ready
	var bar := ColorRect.new()
	bar.color = ch.color
	bar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_right = 10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_top = 8
	v.add_theme_constant_override("separation", -4)
	v.add_child(UiStyle.label(String(ch.name).to_upper(), 34, UiStyle.YELLOW if picked else UiStyle.TEXT))
	v.add_child(UiStyle.label(String(ch.role).to_upper(), 16, UiStyle.MUTED))
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	b.pressed.connect(func() -> void:
		if ready_on:
			return
		Settings.character = id
		Settings.save_settings()
		_refresh_characters()
		character_picked.emit(id))
	return b
