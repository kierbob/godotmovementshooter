class_name UiStyle
## The menu look from the web game (menu.css): navy panels, yellow accents, slanted buttons,
## chunky condensed titles. Builds one Theme plus small widget helpers.

const YELLOW := Color("ffe135")
const YELLOW_HI := Color("fff07a")
const YELLOW_DARK := Color("b89a00")
const INK := Color("0b1030")
const OUTLINE := Color("1a1430")
const TEXT := Color("f2f5ff")
const MUTED := Color("9aa6d6")
const LINE := Color(1, 1, 1, 0.14)
const DANGER := Color("ff4054")
const SKEW := Vector2(0.2, 0) # the slant on buttons

static var _theme: Theme
static var title_font: Font # condensed display font (Bebas Neue if installed, else Impact)
static var slant_font: Font # same, leaning forward like the web's skewX titles
static var body_font: Font


static func theme() -> Theme:
	if _theme:
		return _theme
	# Bebas Neue if installed; otherwise Windows' Bahnschrift in its bold condensed style (it's a
	# variable font: weight + width axes).
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Bebas Neue", "Bahnschrift", "Impact"])
	var display := FontVariation.new()
	display.base_font = sys
	var ts := TextServerManager.get_primary_interface()
	display.variation_opentype = {ts.name_to_tag("wght"): 700, ts.name_to_tag("wdth"): 75}
	title_font = display
	var slant := FontVariation.new()
	slant.base_font = sys
	slant.variation_opentype = display.variation_opentype
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
	slant_font = slant
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Segoe UI", "Arial"])
	body_font = body

	var t := Theme.new()
	t.default_font = display
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)

	# --- plain button: translucent, slanted ---
	_button(t, "Button", _box(Color(1, 1, 1, 0.08), 3), _box(Color(1, 1, 1, 0.18), 3), _box(YELLOW, 3), TEXT, INK)
	# --- big yellow PLAY button with a chunky bottom edge ---
	var play := _box(YELLOW, 0)
	play.border_width_bottom = 7
	play.border_color = YELLOW_DARK
	var play_hover := play.duplicate() as StyleBoxFlat
	play_hover.bg_color = YELLOW_HI
	var play_down := play.duplicate() as StyleBoxFlat
	play_down.border_width_bottom = 2
	play_down.content_margin_top = 12
	t.set_type_variation("PlayButton", "Button")
	_button(t, "PlayButton", play, play_hover, play_down, INK, INK)
	t.set_font_size("font_size", "PlayButton", 54)
	# --- side nav (pause menu / settings tabs): text only, yellow slab on hover ---
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 18
	clear.content_margin_right = 18
	var slab := _box(YELLOW, 0)
	slab.content_margin_left = 28
	t.set_type_variation("NavButton", "Button")
	_button(t, "NavButton", clear, slab, slab, TEXT, INK)
	t.set_font_size("font_size", "NavButton", 48)
	t.set_constant("align_to_largest_stylebox", "NavButton", 0)
	# --- settings tabs: dim card with a left bar; selected = yellow bar + tint ---
	var tab := _box(Color(1, 1, 1, 0.04), 0)
	tab.skew = Vector2.ZERO
	tab.border_width_left = 5
	tab.border_color = LINE
	tab.content_margin_left = 22
	var tab_hover := tab.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color(1, 1, 1, 0.1)
	var tab_on := tab.duplicate() as StyleBoxFlat
	tab_on.bg_color = Color(YELLOW, 0.14)
	tab_on.border_color = YELLOW
	tab_on.border_width_left = 7
	t.set_type_variation("SideTab", "Button")
	_button(t, "SideTab", tab, tab_hover, tab_on, MUTED, TEXT)
	t.set_stylebox("hover_pressed", "SideTab", tab_on)
	t.set_color("font_hover_color", "SideTab", TEXT)
	t.set_font_size("font_size", "SideTab", 38)
	# --- top bar tabs: muted text, active = white with a yellow underline ---
	var top := StyleBoxEmpty.new()
	top.content_margin_left = 22
	top.content_margin_right = 22
	var top_on := StyleBoxFlat.new()
	top_on.bg_color = Color(0, 0, 0, 0)
	top_on.border_width_bottom = 4
	top_on.border_color = YELLOW
	top_on.content_margin_left = 22
	top_on.content_margin_right = 22
	t.set_type_variation("TopTab", "Button")
	_button(t, "TopTab", top, top, top_on, MUTED, TEXT)
	t.set_stylebox("hover_pressed", "TopTab", top_on)
	t.set_color("font_hover_color", "TopTab", TEXT)
	t.set_font_size("font_size", "TopTab", 26)
	# --- segmented choice (quality, on/off...): selected = yellow ---
	var seg := _box(Color(1, 1, 1, 0.08), 3)
	seg.border_width_bottom = 3
	seg.border_color = Color(1, 1, 1, 0.15)
	var seg_hover := seg.duplicate() as StyleBoxFlat
	seg_hover.bg_color = Color(1, 1, 1, 0.16)
	var seg_on := seg.duplicate() as StyleBoxFlat
	seg_on.bg_color = YELLOW
	seg_on.border_color = YELLOW_DARK
	t.set_type_variation("SegButton", "Button")
	_button(t, "SegButton", seg, seg_hover, seg_on, TEXT, INK)
	t.set_stylebox("hover_pressed", "SegButton", seg_on)
	t.set_font_size("font_size", "SegButton", 24)
	# --- keycaps (keybinds) ---
	var cap := _box(Color(0, 0, 0, 0.45), 3)
	cap.border_width_bottom = 3
	cap.border_color = Color(1, 1, 1, 0.2)
	cap.content_margin_left = 14
	cap.content_margin_right = 14
	var cap_hover := cap.duplicate() as StyleBoxFlat
	cap_hover.bg_color = Color(1, 1, 1, 0.16)
	var cap_on := cap.duplicate() as StyleBoxFlat
	cap_on.bg_color = YELLOW
	cap_on.border_color = YELLOW_DARK
	t.set_type_variation("KeyCap", "Button")
	_button(t, "KeyCap", cap, cap_hover, cap_on, TEXT, INK)
	t.set_stylebox("hover_pressed", "KeyCap", cap_on)
	t.set_font_size("font_size", "KeyCap", 22)
	# --- danger nav (quit): red slab ---
	var red := slab.duplicate() as StyleBoxFlat
	red.bg_color = DANGER
	t.set_type_variation("DangerNav", "Button")
	_button(t, "DangerNav", clear, red, red, TEXT, Color.WHITE)
	t.set_font_size("font_size", "DangerNav", 48)

	# --- sliders: thin dark track, yellow fill, slanted yellow grabber ---
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.skew = Vector2(0.3, 0)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = YELLOW
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _grabber(YELLOW))
	t.set_icon("grabber_highlight", "HSlider", _grabber(YELLOW_HI))
	t.set_constant("center_grabber", "HSlider", 1)

	# --- text boxes: dark with a bottom line ---
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0, 0, 0, 0.4)
	edit.border_width_bottom = 3
	edit.border_color = LINE
	edit.content_margin_left = 10
	edit.content_margin_right = 10
	edit.content_margin_top = 4
	edit.content_margin_bottom = 4
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = YELLOW
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", YELLOW)
	t.set_color("selection_color", "LineEdit", Color(YELLOW, 0.35))
	t.set_font_size("font_size", "LineEdit", 26)

	# --- scrollbars ---
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	var sg := StyleBoxFlat.new()
	sg.bg_color = Color(1, 1, 1, 0.3)
	var sg_hi := sg.duplicate() as StyleBoxFlat
	sg_hi.bg_color = YELLOW
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sg_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", sg_hi)

	# --- tooltips / panels ---
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.047, 0.07, 0.2, 0.94)
	panel.border_color = LINE
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t


static func _box(color: Color, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.skew = SKEW
	s.content_margin_left = 18 + pad
	s.content_margin_right = 18 + pad
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s


static func _button(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, fg: Color, fg_pressed: Color) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_stylebox("disabled", type, normal)
	t.set_color("font_color", type, fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_hover_color", type, fg_pressed if hover is StyleBoxFlat and (hover as StyleBoxFlat).bg_color == YELLOW else fg)
	t.set_color("font_pressed_color", type, fg_pressed)
	t.set_color("font_hover_pressed_color", type, fg_pressed)
	t.set_color("font_disabled_color", type, Color(fg, 0.35))


static func _grabber(color: Color) -> Texture2D:
	var w := 16
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# slanted slab: shift each row right as it goes up
			var shift := int((h - y) * 0.25)
			var inside := x >= shift and x < shift + 10
			img.set_pixel(x, y, color if inside else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# ---------- widget helpers ----------

## A label in the display font. size = font size.
static func label(text: String, size := 26, color := TEXT, slanted := false) -> Label:
	theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", slant_font if slanted else title_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 40:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", maxi(2, size / 20))
		l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 20))
	return l


## Small body-text note (the web game's system-ui notes).
static func note(text: String, size := 15, color := MUTED) -> Label:
	theme()
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", body_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Yellow "kicker" line above a big title.
static func kicker(text: String) -> Label:
	var l := label(text.to_upper(), 20, YELLOW)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func button(text: String, variation := "", on_press := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## A row of choices; the selected one is yellow. Calls on_pick(value).
static func segmented(options: Array, current: Variant, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for o: Array in options: # [value, label]
		var b := button(o[1], "SegButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = o[0] == current
		b.custom_minimum_size.x = 120
		b.pressed.connect(func() -> void: on_pick.call(o[0]))
		row.add_child(b)
	return row


## Vertical gradient/solid rect filling its parent.
static func fill_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Gradient texture rect (colors along `dir`: 0 = left→right, 1 = top→bottom).
static func gradient_rect(colors: PackedColorArray, dir := 0, offsets := PackedFloat32Array()) -> TextureRect:
	var g := Gradient.new()
	g.colors = colors
	if offsets.size() == colors.size():
		g.offsets = offsets
	else:
		var offs := PackedFloat32Array()
		for i in colors.size():
			offs.append(float(i) / maxf(1, colors.size() - 1))
		g.offsets = offs
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0) if dir == 0 else (Vector2(0, 1) if dir == 1 else Vector2(1, 1))
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
