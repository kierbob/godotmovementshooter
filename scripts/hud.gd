class_name Hud
extends CanvasLayer
## In-game overlay: stats panel (full / compact / off), the speed readout, and the combat HUD from
## the web game's hud.js: a crosshair per weapon (with recoil bloom), hitmarker, floating damage
## numbers, comic words ("BLAM!", "KABOOM!"), weapon slots, ammo, reload bar and the ability cooldown.

## Comic word styles (hud.css .comic-word): font size and fill color.
const WORD_STYLES := {
	"small": [30, Color("ffe14d")], "big": [48, Color("ffb020")], "head": [40, Color("ffe14d")],
	"kill": [52, Color("ff4a4a")], "blue": [44, Color("6fe6ff")],
}
const WORD_LIFE := 0.8
const NUMBER_LIFE := 0.9

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
var _words_layer: Control
var _words: Array = [] # [{label, age, world, screen, jitter}]
var _numbers: Array = [] # [{label, age, pos, drift}]
var _comic_font: Font
var _camera: Camera3D
var _plain_dot: Control
var _trial_box: VBoxContainer
var _trial_mode: Label
var _trial_time: Label
var _trial_best: Label
var online: OnlineHud # health, kill feed, scoreboard... (multiplayer only)
var _online := false


func _ready() -> void:
	layer = 5
	_comic_font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
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
	_words_layer = Control.new()
	_words_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_words_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_words_layer)
	_hitmarker = Hitmarker.new() # after the words so damage numbers never cover it
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmarker)

	# Small and low: it's a readout, not the main event.
	_speed = UiStyle.label("", 30)
	_speed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speed.offset_top = -74
	_speed.offset_bottom = -40
	_speed.offset_left = -120
	_speed.offset_right = 120
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_speed.add_theme_constant_override("outline_size", 6)
	add_child(_speed)
	_speed_sub = UiStyle.label("", 14, UiStyle.YELLOW)
	_speed_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speed_sub.offset_top = -42
	_speed_sub.offset_bottom = -24
	_speed_sub.offset_left = -120
	_speed_sub.offset_right = 120
	_speed_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_sub.add_theme_color_override("font_outline_color", UiStyle.OUTLINE)
	_speed_sub.add_theme_constant_override("outline_size", 4)
	add_child(_speed_sub)

	_build_weapon_panel()
	_build_ability()
	_build_trial()
	online = OnlineHud.new()
	online.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(online)
	move_child(online, 0) # under the crosshair and words
	_plain_dot = PlainDot.new()
	_plain_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plain_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plain_dot)
	set_in_game(false)


# ---------- time trial clock (top center) ----------

func _build_trial() -> void:
	_trial_box = VBoxContainer.new()
	_trial_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_trial_box.offset_left = -300
	_trial_box.offset_right = 300
	_trial_box.offset_top = 10
	_trial_box.offset_bottom = 130
	_trial_box.add_theme_constant_override("separation", -4)
	_trial_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_trial_box)
	_trial_mode = _comic(20, Color("ffe14d"))
	_trial_time = _comic(60, Color("9ff0ff"))
	_trial_best = _comic(18, Color("d8def5"))
	for l: Label in [_trial_mode, _trial_time, _trial_best]:
		_trial_box.add_child(l)
	_trial_box.visible = false


## Comic-font label with an ink outline and drop shadow (the web's .trial-timer text).
func _comic(size: int, color: Color) -> Label:
	var l := Label.new()
	if _comic_font:
		l.add_theme_font_override("font", _comic_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("15151f"))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.add_theme_color_override("font_shadow_color", Color("15151f"))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Big clock at the top while you're on the time trial course (hud.js updateTrial).
func update_trial(trial: TimeTrial) -> void:
	var show := trial != null and trial.active and _in_game
	_trial_box.visible = show
	if not show:
		return
	_trial_mode.text = "TIME TRIAL · GUNS ON" if trial.guns else "TIME TRIAL · GUNS OFF"
	_trial_time.text = TimeTrial.format_time(trial.time if trial.running else maxf(0.0, trial.last[trial.mode()]))
	_trial_time.add_theme_color_override("font_color", Color.WHITE if trial.running else Color("9ff0ff"))
	_trial_best.text = "BEST %s  ·  %s RESTART" % [TimeTrial.format_time(trial.best[trial.mode()]),
		Settings.bind_label(Settings.binds.respawn).to_upper()]


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
	online.visible = on and _online
	_speed.visible = on
	_speed_sub.visible = on
	_panel.visible = on and debug_mode > 0
	_apply_guns_visible()


func set_online(on: bool) -> void:
	_online = on
	online.visible = on and _in_game


## Guns-off modes hide the crosshair, weapon panel and ability.
func set_guns(on: bool) -> void:
	_guns = on
	_apply_guns_visible()


func _apply_guns_visible() -> void:
	var show := _in_game and _guns
	_cross.visible = show
	_hitmarker.visible = show
	_words_layer.visible = _in_game # comic words ("GO!", "FINISH!") show in guns-off modes too
	_weapon_panel.visible = show
	_ability.visible = show
	_plain_dot.visible = _in_game and not _guns
	if not _in_game:
		_trial_box.visible = false


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
			_hitmarker.hit("kill" if e.kill else "head" if e.zone == "head" else "body")
			_add_number(e)


# ---------- comic words and damage numbers ----------

## A comic word. world_pos (Vector3) floats it over that spot; otherwise screen_pos (0..1).
func word(text: String, world_pos: Variant, screen_pos: Variant, style: String) -> void:
	var st: Array = WORD_STYLES.get(style, WORD_STYLES.small)
	var l := Label.new()
	l.text = text
	if _comic_font:
		l.add_theme_font_override("font", _comic_font)
	l.add_theme_font_size_override("font_size", st[0])
	l.add_theme_color_override("font_color", st[1])
	# ink outline plus a hard drop shadow, like the web's text-stroke + text-shadow
	l.add_theme_color_override("font_outline_color", Color("15151f"))
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_shadow_color", Color("15151f"))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 7)
	l.rotation = deg_to_rad(randf_range(-10, 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words_layer.add_child(l)
	l.size = l.get_minimum_size()
	l.pivot_offset = l.size / 2
	_words.append({"label": l, "age": 0.0, "world": world_pos, "screen": screen_pos,
		"jitter": Vector2(randf_range(-15, 15), randf_range(-10, 10))})
	if _words.size() > 12:
		(_words.pop_front().label as Label).queue_free()
	_place_word(_words.back())


func _place_word(w: Dictionary) -> void:
	var l: Label = w.label
	var view := _words_layer.size
	var at: Vector2
	if w.world != null:
		if _camera == null or _camera.is_position_behind(w.world):
			l.visible = false
			return
		l.visible = true
		at = _camera.unproject_position(w.world) + Vector2(0, -30 - w.age * 40)
	else:
		at = (w.screen as Vector2) * view
	l.position = at + w.jitter - l.size / 2
	# comic pop: tiny -> overshoot -> settle, then fade
	var t: float = w.age / WORD_LIFE
	var sc := lerpf(0.3, 1.25, t / 0.18) if t < 0.18 else lerpf(1.25, 1.0, (t - 0.18) / 0.12) if t < 0.3 else 1.0
	l.scale = Vector2.ONE * sc
	l.modulate.a = 1.0 if t < 0.7 else 1.0 - (t - 0.7) / 0.3


## Damage number that pops at the hit and floats up (white body, yellow head, red kill).
func _add_number(e: Dictionary) -> void:
	var l := UiStyle.label(str(roundi(e.dmg)), 34 if e.kill else 32 if e.zone == "head" else 26,
		Color("ff4a4a") if e.kill else Color("ffd84a") if e.zone == "head" else Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words_layer.add_child(l)
	l.size = l.get_minimum_size()
	l.pivot_offset = l.size / 2
	_numbers.append({"label": l, "age": 0.0, "pos": e.pos, "drift": randf_range(-20, 20)})
	if _numbers.size() > 40:
		(_numbers.pop_front().label as Label).queue_free()


func _update_floaters(dt: float) -> void:
	var keep: Array = []
	for w: Dictionary in _words:
		w.age += dt
		if w.age > WORD_LIFE:
			(w.label as Label).queue_free()
			continue
		_place_word(w)
		keep.append(w)
	_words = keep
	keep = []
	for n: Dictionary in _numbers:
		n.age += dt
		var l: Label = n.label
		if n.age > NUMBER_LIFE:
			l.queue_free()
			continue
		keep.append(n)
		if _camera == null or _camera.is_position_behind(n.pos):
			l.visible = false
			continue
		l.visible = true
		# starts up-right of the hit so it doesn't sit on the crosshair, then floats up
		var p := _camera.unproject_position(n.pos) + Vector2(26 + n.drift * n.age, -22 - 60 * n.age)
		l.position = p - l.size / 2
		l.scale = Vector2.ONE * (1.4 if n.age < 0.08 else 1.0)
		l.modulate.a = 1.0 if n.age < 0.6 else 1.0 - (n.age - 0.6) / 0.3
	_numbers = keep


## Drop floating words and numbers (new run / menus).
func clear_floaters() -> void:
	for w: Dictionary in _words:
		(w.label as Label).queue_free()
	for n: Dictionary in _numbers:
		(n.label as Label).queue_free()
	_words.clear()
	_numbers.clear()


func update_combat(dt: float, combat: Combat, camera: Camera3D) -> void:
	_camera = camera
	var fov_deg := camera.fov
	_hitmarker.tick(dt)
	_update_floaters(dt)

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


## Hitmarker: four tapered ticks around the crosshair that point in at it, pop in slightly big
## and fade. White on a body hit, yellow and a bit bigger on a headshot, red and bigger on a kill.
class Hitmarker:
	extends Control

	const LIFE := {"body": 0.2, "head": 0.24, "kill": 0.32}
	const COLOR := {"body": Color.WHITE, "head": Color("ffd84a"), "kill": Color("ff4a4a")}

	var style := "body"
	var _t := -1.0 # time since the hit (< 0 = hidden)

	func hit(kind: String) -> void:
		# a kill always wins over a body hit landing in the same instant
		if _t >= 0 and _t < 0.05 and style == "kill" and kind != "kill":
			return
		style = kind
		_t = 0.0
		queue_redraw()

	func tick(dt: float) -> void:
		if _t < 0:
			return
		_t += dt
		if _t > LIFE[style]:
			_t = -1.0
		queue_redraw()

	func _draw() -> void:
		if _t < 0:
			return
		var c := (size / 2).floor()
		var life: float = LIFE[style]
		var big := 1.35 if style == "kill" else 1.15 if style == "head" else 1.0
		var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - _t / 0.07) # starts big, snaps in
		var alpha := 1.0 if _t < life * 0.5 else 1.0 - (_t - life * 0.5) / (life * 0.5)
		var inner := 8.0 * big * pop
		var outer := inner + 10.0 * big
		var col: Color = COLOR[style]
		col.a = alpha
		var edge := Color(0.06, 0.06, 0.1, 0.75 * alpha)
		for i in 4:
			var d := Vector2.from_angle(PI / 4 + i * PI / 2)
			var side := d.orthogonal()
			# wedge: thin at the inside, thicker at the outside
			var tip := c + d * inner
			var w := 2.2 * big
			var pts := PackedVector2Array([tip - side * 0.6, tip + side * 0.6, c + d * outer + side * w, c + d * outer - side * w])
			var grow := PackedVector2Array([tip - side * 1.8 - d * 1.2, tip + side * 1.8 - d * 1.2,
				c + d * (outer + 1.4) + side * (w + 1.4), c + d * (outer + 1.4) - side * (w + 1.4)])
			draw_colored_polygon(grow, edge)
			draw_colored_polygon(pts, col)


## Guns-off modes: just a small dot to aim your movement (hud.css .plain-dot).
class PlainDot:
	extends Control

	func _draw() -> void:
		var c := (size / 2).floor()
		draw_circle(c, 3.0, Color(0.08, 0.08, 0.12, 0.7))
		draw_circle(c, 2.0, Color.WHITE)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


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
