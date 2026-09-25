class_name ItemHud
extends Control
## The items you carry: a row of chips along the top (icon letters in the item's color, a border
## in its rarity's color, the stack count), and the Risk of Rain style banner when you pick one up
## (name in its rarity color, what it does, what another one adds). Also your gold (top right,
## with a "+7" that pops up for each kill) and the "E  OPEN CHEST  $25" prompt near a chest.

const BANNER_TIME := 3.2

var _bar: HFlowContainer
var _key := "" # what the bar shows, so it only rebuilds on a change
var _banner: VBoxContainer
var _b_name: Label
var _b_desc: Label
var _b_stack: Label
var _banner_t := 0.0
var _comic: Font
var _gold: Label
var _gold_add: Label
var _gold_add_t := 0.0
var _gold_shown := -1
var _prompt: Label
var _level: Label
var _xp_bg: ColorRect
var _xp_fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comic = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	_bar = HFlowContainer.new()
	_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar.offset_left = -420
	_bar.offset_right = 420
	_bar.offset_top = 12
	_bar.offset_bottom = 60
	_bar.add_theme_constant_override("h_separation", 6)
	_bar.add_theme_constant_override("v_separation", 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_banner = VBoxContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.offset_left = -360
	_banner.offset_right = 360
	_banner.offset_top = -260
	_banner.offset_bottom = -150
	_banner.alignment = BoxContainer.ALIGNMENT_END
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", 2)
	add_child(_banner)
	_b_name = _text(40, Color.WHITE, _comic)
	_b_desc = _text(20, UiStyle.TEXT, null)
	_b_stack = _text(16, UiStyle.MUTED, null)
	for l in [_b_name, _b_desc, _b_stack]:
		_banner.add_child(l)
	_banner.modulate.a = 0.0

	_gold = _text(40, Color("ffd84a"), _comic)
	_gold.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gold.offset_left = -260
	_gold.offset_right = -28
	_gold.offset_top = 14
	_gold.offset_bottom = 60
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold.visible = false
	add_child(_gold)
	_gold_add = _text(26, Color("fff1a0"), _comic)
	_gold_add.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gold_add.offset_left = -260
	_gold_add.offset_right = -28
	_gold_add.offset_top = 58
	_gold_add.offset_bottom = 90
	_gold_add.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_gold_add)
	_prompt = _text(26, Color.WHITE, _comic)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = 70
	_prompt.offset_bottom = 110
	_prompt.visible = false
	add_child(_prompt)

	# level + XP bar, just above the health bar (bottom left)
	_level = _text(24, Color("ffd84a"), _comic)
	_level.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level.offset_left = 30
	_level.offset_right = 290
	_level.offset_top = -146
	_level.offset_bottom = -118
	_level.visible = false
	add_child(_level)
	_xp_bg = ColorRect.new()
	_xp_bg.color = Color(0, 0, 0, 0.5)
	_xp_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_xp_bg.offset_left = 30
	_xp_bg.offset_right = 290
	_xp_bg.offset_top = -116
	_xp_bg.offset_bottom = -110
	_xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bg.visible = false
	add_child(_xp_bg)
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color("ffd84a")
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fill.size = Vector2(0, 6)
	_xp_bg.add_child(_xp_fill)


func _text(size: int, color: Color, font: Font) -> Label:
	var l := UiStyle.label("", size, color)
	if font:
		l.add_theme_font_override("font", font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Every frame: rebuild the chips if what you carry changed, fade the banner.
func update(dt: float, up: Upgrades) -> void:
	var key := str(up.stacks)
	if key != _key:
		_key = key
		_rebuild(up)
	_banner_t = maxf(0.0, _banner_t - dt)
	_banner.modulate.a = clampf(_banner_t / 0.5, 0.0, 1.0)
	_gold_add_t = maxf(0.0, _gold_add_t - dt)
	_gold_add.modulate.a = clampf(_gold_add_t / 0.4, 0.0, 1.0)


## Gold in the corner (only in runs: gold < 0 hides it).
func set_gold(gold: int) -> void:
	_gold.visible = gold >= 0
	if gold != _gold_shown and gold >= 0:
		_gold_shown = gold
		_gold.text = "$%d" % gold


## Your level and how far to the next one (level < 1 hides it: not in a run).
func set_level(level: int, frac: float) -> void:
	_level.visible = level >= 1
	_xp_bg.visible = level >= 1
	if level >= 1:
		_level.text = "LV %d" % level
		_xp_fill.size = Vector2(260.0 * clampf(frac, 0.0, 1.0), 6)


## A "+7" under the gold for a moment (quick kills add up into one number).
func gold_added(amount: int) -> void:
	var prev := int(_gold_add.text.trim_prefix("+")) if _gold_add_t > 0 and _gold_add.text.begins_with("+") else 0
	_gold_add.text = "+%d" % (prev + amount)
	_gold_add_t = 1.2


## The interact prompt ("" hides it); red when you can't afford it.
func set_prompt(text: String, ok := true) -> void:
	_prompt.visible = text != ""
	if text != "":
		_prompt.text = text
		_prompt.add_theme_color_override("font_color", Color.WHITE if ok else Color("ff6a5a"))


## Picked one up: show its banner.
func pickup(id: String, count: int) -> void:
	var it: Dictionary = Upgrades.LIST[id]
	_b_name.text = String(it.name).to_upper() + ("  x%d" % count if count > 1 else "")
	_b_name.add_theme_color_override("font_color", Upgrades.RARITY[it.rarity].color)
	_b_desc.text = it.desc
	_b_stack.text = "%s · stacking: %s" % [Upgrades.RARITY[it.rarity].name, it.stack]
	_banner_t = BANNER_TIME


func _rebuild(up: Upgrades) -> void:
	for c in _bar.get_children():
		c.queue_free()
	# Rarest first, then in list order: the good stuff reads first.
	var ids: Array = []
	for rarity: String in ["legendary", "rare", "uncommon", "common"]:
		for id: String in Upgrades.LIST:
			if up.count(id) > 0 and Upgrades.LIST[id].rarity == rarity:
				ids.append(id)
	for id: String in ids:
		_bar.add_child(chip(id, up.count(id)))


## One item's chip (the console's buttons use it too).
static func chip(id: String, n: int, size := 40.0) -> Control:
	var it: Dictionary = Upgrades.LIST[id]
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var st := StyleBoxFlat.new()
	st.bg_color = (it.color as Color).darkened(0.35)
	st.border_color = Upgrades.RARITY[it.rarity].color
	st.set_border_width_all(2 if it.rarity == "common" else 3)
	st.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", st)
	var icon := UiStyle.label(it.icon, int(size * 0.42), Color.WHITE)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	icon.add_theme_constant_override("outline_size", 4)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	if n > 1:
		# the count hangs off the bottom-right corner, clear of the letters
		var c := UiStyle.label("%d" % n, int(size * 0.36), Color("ffe066"))
		c.position = Vector2(size * 0.78, size * 0.5)
		c.add_theme_color_override("font_outline_color", Color.BLACK)
		c.add_theme_constant_override("outline_size", 6)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)
	return root
