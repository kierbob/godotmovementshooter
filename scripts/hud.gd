class_name Hud
extends CanvasLayer
## In-game overlay: stats panel (full / compact / off), the speed readout, and the combat HUD from
## the web game's hud.js: a crosshair per weapon (with recoil bloom), hitmarker, weapon slots, ammo,
## reload bar and the ability cooldown.

const HIT_TIME := 0.18

var debug_mode := 1 # 0 off, 1 compact, 2 full
var _panel: PanelContainer
var _debug: Label
var _speed: Label
var _speed_sub: Label
var _cross: Crosshair
var _hitmarker: Hitmarker
var _weapon_panel: VBoxContainer
var _slots: VBoxContainer
var _slot_key := ""
var _ammo: Label
var _mag: Label
var _reload_bg: Panel
var _reload_fill: ColorRect
var _ability: VBoxContainer
var _ability_icon: AbilityIcon
var _ability_name: Label
var _in_game := false
var _guns := true
var _bloom := 0.0
var _hit_t := 0.0


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
	_hitmarker = Hitmarker.new()
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmarker)

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

	_build_weapon_panel()
	_build_ability()
	set_in_game(false)


# ---------- weapon panel (bottom right) ----------

func _build_weapon_panel() -> void:
	_weapon_panel = VBoxContainer.new()
	_weapon_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_panel.offset_left = -268
	_weapon_panel.offset_top = -200
	_weapon_panel.offset_right = -28
	_weapon_panel.offset_bottom = -24
	_weapon_panel.alignment = BoxContainer.ALIGNMENT_END
	_weapon_panel.add_theme_constant_override("separation", 2)
	_weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weapon_panel)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	_weapon_panel.add_child(_slots)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 4)
	_ammo = _outlined(UiStyle.label("", 64), 3)
	ammo_row.add_child(_ammo)
	_mag = _outlined(UiStyle.label("", 28, Color(UiStyle.TEXT, 0.7)), 2)
	_mag.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(_mag)
	_weapon_panel.add_child(ammo_row)
	_reload_bg = Panel.new()
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0, 0, 0, 0.4)
	rb.set_corner_radius_all(2)
	_reload_bg.add_theme_stylebox_override("panel", rb)
	_reload_bg.custom_minimum_size.y = 4
	_reload_bg.clip_contents = true
	_reload_fill = ColorRect.new()
	_reload_fill.color = UiStyle.YELLOW
	_reload_fill.anchor_bottom = 1.0
	_reload_bg.add_child(_reload_fill)
	_weapon_panel.add_child(_reload_bg)


## Text shadow like the web HUD, done with an outline so it reads over bright sky.
func _outlined(l: Label, size: int) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("outline_size", size * 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _slot_chip(key: String, name: String, active: bool) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UiStyle.YELLOW, 0.9) if active else Color(0, 0, 0, 0.35)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var fg := Color("15151a") if active else Color(UiStyle.TEXT, 0.55)
	var k := UiStyle.label(key, 13, Color(fg, 0.8))
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	row.add_child(UiStyle.label(name.to_upper(), 20, fg))
	p.add_child(row)
	return p


# ---------- ability (left of the weapon panel) ----------

func _build_ability() -> void:
	_ability = VBoxContainer.new()
	_ability.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ability.offset_left = -400
	_ability.offset_top = -120
	_ability.offset_right = -270
	_ability.offset_bottom = -30
	_ability.alignment = BoxContainer.ALIGNMENT_END
	_ability.add_theme_constant_override("separation", 4)
	_ability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ability)
	_ability_icon = AbilityIcon.new()
	_ability_icon.custom_minimum_size = Vector2(58, 58)
	_ability_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ability.add_child(_ability_icon)
	_ability_name = _outlined(UiStyle.label("", 18), 2)
	_ability_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ability.add_child(_ability_name)


# ---------- public ----------

## Everything except the stats panel is hidden in menus.
func set_in_game(on: bool) -> void:
	_in_game = on
	_speed.visible = on
	_speed_sub.visible = on
	_panel.visible = on and debug_mode > 0
	_apply_guns_visible()


## Guns-off modes hide the crosshair, weapon panel and ability.
func set_guns(on: bool) -> void:
	_guns = on
	_apply_guns_visible()


func _apply_guns_visible() -> void:
	var show := _in_game and _guns
	_cross.visible = show
	_hitmarker.visible = show
	_weapon_panel.visible = show
	_ability.visible = show


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


## React to this frame's combat events: recoil bloom and hitmarkers.
func on_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e.type == "shot":
			_bloom = minf(1.0, _bloom + float(Items.WEAPONS[e.weapon].kick) * 0.8)
		elif e.type == "hit":
			_hit_t = HIT_TIME
			_hitmarker.style = "kill" if e.kill else "head" if e.zone == "head" else "body"


func update_combat(dt: float, combat: Combat, fov_deg: float) -> void:
	# Hitmarker
	_hit_t = maxf(0.0, _hit_t - dt)
	_hitmarker.showing = _hit_t > 0
	_hitmarker.queue_redraw()

	# Weapon slots (rebuilt only when something changes)
	var keys := [Settings.bind_label(Settings.binds.primary), Settings.bind_label(Settings.binds.secondary)]
	var slot_key := "%s|%s|%s|%s" % [combat.active, combat.slots.primary.id, combat.slots.secondary.id, keys]
	if slot_key != _slot_key:
		_slot_key = slot_key
		for c in _slots.get_children():
			c.queue_free()
		var i := 0
		for s: String in ["primary", "secondary"]:
			_slots.add_child(_slot_chip(keys[i], combat.slots[s].name, combat.active == s))
			i += 1

	var w := combat.weapon()
	var st := combat.weapon_state()
	_ammo.text = str(st.ammo)
	_ammo.add_theme_color_override("font_color", Color("ff6a5a") if st.ammo <= ceili(w.mag * 0.25) else UiStyle.TEXT)
	_mag.text = "/ %d" % w.mag
	var reloading: bool = st.reload_t > 0
	_reload_bg.modulate.a = 1.0 if reloading else 0.0
	_reload_fill.anchor_right = 1.0 - st.reload_t / w.reload if reloading else 0.0

	# Crosshair: the ring is the shotgun's real spread cone projected onto the screen.
	_bloom = maxf(0.0, _bloom - dt * 4)
	var h := _cross.size.y
	var spread := deg_to_rad(float(w.get("spread", 0.0)))
	var ring := clampf(tan(spread) / tan(deg_to_rad(fov_deg) / 2) * (h / 2), 8, 95) * (1 + _bloom * 0.25)
	if _cross.shape != w.crosshair or not is_equal_approx(_cross.bloom, _bloom) or not is_equal_approx(_cross.ring, ring):
		_cross.shape = w.crosshair
		_cross.bloom = _bloom
		_cross.ring = ring
		_cross.queue_redraw()

	# Ability
	var a := combat.ability
	_ability_name.text = String(a.name).to_upper()
	_ability_icon.frac = combat.ability_cd / float(a.cooldown)
	_ability_icon.cd = combat.ability_cd
	_ability_icon.key = Settings.bind_label(Settings.binds.ability)
	_ability_icon.queue_redraw()


## Per-weapon crosshair (shapes from hud.js CROSSHAIRS). Straight lines are pixel-aligned
## rectangles so they stay sharp, with a thin dark edge so they read on bright sky and walls.
class Crosshair:
	extends Control

	const FILL := Color(1, 1, 1, 0.95)
	const EDGE := Color(0.08, 0.08, 0.12, 0.7)

	var shape := "cross"
	var bloom := 0.0
	var ring := 20.0

	func _draw() -> void:
		var c := (size / 2).floor()
		match shape:
			"ring":
				_ring(c, ring)
				_dot(c)
			"cross":
				_ticks(c, roundi(5 + bloom * 10), 7)
			"dot":
				_dot(c)
				_ticks(c, roundi(8 + bloom * 7), 4)
			"rocket":
				var r := roundi(12 + bloom * 5)
				_ring(c, r)
				_dot(c)
				_hbar(c, r + 8, 6)
				_hbar(c, r + 14, 3)
			"scope":
				var r := roundi(15 + bloom * 6)
				_ring(c, r)
				_dot(c)
				# short ticks on the ring, not lines through it, so the center stays clear
				_bar(c + Vector2(-1, -r - 5), Vector2(2, 9))
				_bar(c + Vector2(-1, r - 4), Vector2(2, 9))
				_bar(c + Vector2(-r - 5, -1), Vector2(9, 2))
				_bar(c + Vector2(r - 4, -1), Vector2(9, 2))
			"bracket":
				var g := roundi(11 + bloom * 9)
				for sx: int in [-1, 1]:
					var x := g if sx > 0 else -g - 2
					_bar(c + Vector2(x, -8), Vector2(2, 16)) # upright
					var arm := Vector2(x - 3 if sx > 0 else x, 0)
					_bar(c + arm + Vector2(0, -8), Vector2(5, 2)) # top arm, pointing inward
					_bar(c + arm + Vector2(0, 6), Vector2(5, 2)) # bottom arm
				_dot(c)

	## A filled rect with a 1 px dark edge; pos/size in whole pixels.
	func _bar(pos: Vector2, sz: Vector2) -> void:
		draw_rect(Rect2(pos - Vector2.ONE, sz + Vector2(2, 2)), EDGE)
		draw_rect(Rect2(pos, sz), FILL)

	func _dot(c: Vector2) -> void:
		_bar(c - Vector2.ONE, Vector2(2, 2))

	## Four lines around the center: gap from the center, length each.
	func _ticks(c: Vector2, gap: int, length: int) -> void:
		_bar(c + Vector2(-1, -gap - length), Vector2(2, length))
		_bar(c + Vector2(-1, gap), Vector2(2, length))
		_bar(c + Vector2(-gap - length, -1), Vector2(length, 2))
		_bar(c + Vector2(gap, -1), Vector2(length, 2))

	func _hbar(c: Vector2, y: int, half: int) -> void:
		_bar(c + Vector2(-half, y), Vector2(half * 2, 2))

	func _ring(c: Vector2, r: float) -> void:
		draw_arc(c, r, 0, TAU, 96, EDGE, 3.5, true)
		draw_arc(c, r, 0, TAU, 96, FILL, 1.6, true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


## Four short diagonal ticks around the crosshair: white on a body hit, yellow on a headshot,
## red and longer on a kill.
class Hitmarker:
	extends Control

	var showing := false
	var style := "body"

	func _draw() -> void:
		if not showing:
			return
		var c := (size / 2).round()
		var col := Color("ff4a4a") if style == "kill" else Color("ffd84a") if style == "head" else Color.WHITE
		var half := 6.5 if style == "kill" else 4.5
		for i in 4:
			var d := Vector2.from_angle(PI / 4 + i * PI / 2)
			draw_line(c + d * (10 - half), c + d * (10 + half), Color(0, 0, 0, 0.6), 4.0, true)
			draw_line(c + d * (10 - half), c + d * (10 + half), col, 2.0, true)


## Round ability icon: key letter, a dark pie that shrinks as the cooldown runs out, yellow ring
## when it's ready.
class AbilityIcon:
	extends Control

	var frac := 0.0
	var cd := 0.0
	var key := "Q"

	func _draw() -> void:
		var c := size / 2
		var r := size.x / 2
		draw_circle(c, r, Color(0.078, 0.118, 0.275, 0.75))
		var font := get_theme_default_font()
		var ready := frac <= 0
		if ready:
			_centered(font, key, c, 26, Color.WHITE)
		else:
			# Pie from 12 o'clock, clockwise, covering the part that's still charging.
			var pts := PackedVector2Array([c])
			var steps := 40
			for i in steps + 1:
				pts.append(c + Vector2.from_angle(-PI / 2 + TAU * frac * i / steps) * (r - 2))
			if pts.size() >= 3:
				draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
			_centered(font, "%.1f" % cd, c, 14, Color.WHITE)
		var ring_col := UiStyle.YELLOW if ready else Color(1, 1, 1, 0.35)
		if ready:
			draw_arc(c, r + 2, 0, TAU, 48, Color(UiStyle.YELLOW, 0.35), 6, true)
		draw_arc(c, r - 1.5, 0, TAU, 48, ring_col, 3, true)

	func _centered(font: Font, text: String, c: Vector2, fs: int, col: Color) -> void:
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x / 2, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
