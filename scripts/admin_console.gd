class_name AdminConsole
extends CanvasLayer
## Testing console on F10 (rebindable): type a command, Enter runs it.
##   spawn flyer beam      spawn a variant (also: spawn beam, spawn swarmer 5, spawn runner = any runner)
##   killall               remove every enemy
##   god [on|off]          you can't be hurt (no word: toggle); ungod = off
##   heal                  full health
##   freeze [on|off]       enemies stand still (no word: toggle); unfreeze = off
##   list                  every enemy type
##   give <item> [count]   an item (give triple tap 3, give random 5); take <item> [count]
##   items                 what you're carrying; clearitems drops the lot
##   help
## Up / Down walk through what you typed before. Next to the text bar there are buttons for all
## of it (every enemy, a count, god / freeze / heal / kill all), which just run the same commands.
## The game (main.gd) does the work in admin().

const HELP := [
	"spawn <enemy> [variant] [count]   e.g. spawn flyer beam, spawn swarmer 5, spawn runner",
	"killall · god [on/off] · heal · freeze / unfreeze · list · help",
	"give <item> [count] (give random 5) · take <item> · items · clearitems",
]
const VARIANT_WORDS := {"projectile": "flyer_projectile", "beam": "flyer_beam", "healer": "flyer_healer",
	"charger": "charger", "brute": "brute", "swarmer": "swarmer", "gunner": "gunner", "lobber": "lobber", "sniper": "sniper"}

var game: Node # main.gd: admin(command, data) -> String
var is_open := false
var _panel: PanelContainer
var _log: Label
var _edit: LineEdit
var _lines: Array[String] = []
var _history: Array[String] = []
var _hist_i := -1
var _count := 1 # how many the spawn buttons spawn
var _count_btns := {}
var _god_btn: Button
var _freeze_btn: Button


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.03, 0.1, 0.9)
	st.border_width_bottom = 3
	st.border_color = UiStyle.YELLOW
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", st)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.theme = UiStyle.theme()
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_panel.add_child(row)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	row.add_child(_build_buttons())
	var title := UiStyle.label("ADMIN · F10 TO CLOSE", 18, UiStyle.YELLOW)
	v.add_child(title)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	_log = Label.new()
	_log.add_theme_font_override("font", mono)
	_log.add_theme_font_size_override("font_size", 16)
	_log.add_theme_color_override("font_color", Color("d8def5"))
	v.add_child(_log)
	_edit = LineEdit.new()
	_edit.add_theme_font_override("font", mono)
	_edit.add_theme_font_size_override("font_size", 20)
	_edit.placeholder_text = "type a command (help)"
	_edit.text_submitted.connect(_submit)
	_edit.gui_input.connect(_edit_input)
	v.add_child(_edit)
	_panel.visible = false
	for l in HELP:
		say(l)


## The button panel: spawn any enemy (x1 / x3 / x5), and the toggles.
func _build_buttons() -> Control:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 5)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.add_child(_tag("SPAWN"))
	for n: int in [1, 3, 5]:
		var b := _btn("x%d" % n, func() -> void:
			_count = n
			_refresh_buttons())
		b.toggle_mode = true
		_count_btns[n] = b
		top.add_child(b)
	grid.add_child(top)
	for fam: String in Enemies.FAMILIES:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		r.add_child(_tag(fam.to_upper() + "S"))
		for id: String in Enemies.FAMILIES[fam]:
			var label := String(Enemies.TYPES[id].name).trim_suffix(" Flyer").to_upper()
			var word := id.trim_prefix("flyer_")
			r.add_child(_btn(label, func() -> void: _press("spawn %s %d" % [word if fam != "flyer" else "flyer " + word, _count])))
		r.add_child(_btn("ANY", func() -> void: _press("spawn %s %d" % [fam, _count])))
		grid.add_child(r)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.add_child(_tag(""))
	_god_btn = _btn("GOD", func() -> void: _press("god"))
	_god_btn.toggle_mode = true
	tools.add_child(_god_btn)
	_freeze_btn = _btn("FREEZE", func() -> void: _press("freeze"))
	_freeze_btn.toggle_mode = true
	tools.add_child(_freeze_btn)
	tools.add_child(_btn("HEAL", func() -> void: _press("heal")))
	tools.add_child(_btn("KILL ALL", func() -> void: _press("killall")))
	grid.add_child(tools)
	_refresh_buttons()
	return grid


func _tag(text: String) -> Label:
	var l := UiStyle.label(text, 16, UiStyle.MUTED)
	l.custom_minimum_size.x = 92
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _btn(text: String, on_press: Callable) -> Button:
	var b := UiStyle.button(text, "SegButton", on_press)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(96, 30)
	return b


## A button runs its command as if typed (so it shows in the log too).
func _press(text: String) -> void:
	say("> " + text)
	say(execute(text))
	_refresh_buttons()


func _refresh_buttons() -> void:
	for n: int in _count_btns:
		(_count_btns[n] as Button).set_pressed_no_signal(n == _count)
	var en: Variant = game.get("enemies") if game else null
	if _god_btn:
		_god_btn.set_pressed_no_signal(en != null and en.god)
		_freeze_btn.set_pressed_no_signal(en != null and en.frozen)


func toggle() -> void:
	is_open = not is_open
	_panel.visible = is_open
	if is_open:
		_edit.grab_focus()
		_edit.text = ""
		_refresh_buttons()
	else:
		_edit.release_focus()


func say(text: String) -> void:
	_lines.append(text)
	if _lines.size() > 8:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


func _submit(text: String) -> void:
	_edit.text = ""
	text = text.strip_edges()
	if text == "":
		return
	_history.append(text)
	_hist_i = -1
	say("> " + text)
	say(execute(text))
	_refresh_buttons()


func _edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not _history.is_empty():
		if event.keycode == KEY_UP:
			_hist_i = _history.size() - 1 if _hist_i < 0 else maxi(0, _hist_i - 1)
		elif event.keycode == KEY_DOWN:
			_hist_i = mini(_history.size() - 1, _hist_i + 1) if _hist_i >= 0 else -1
		else:
			return
		if _hist_i >= 0:
			_edit.text = _history[_hist_i]
			_edit.caret_column = _edit.text.length()
		_edit.accept_event()


## Run one command; returns what to print.
func execute(text: String) -> String:
	var words := text.to_lower().split(" ", false)
	if words.is_empty():
		return ""
	var cmd := words[0]
	match cmd:
		"help", "?":
			return "\n".join(HELP)
		"spawn", "s":
			var r := parse_spawn(words.slice(1))
			if r.is_empty():
				return "Don't know that enemy. Try: list"
			return _call("spawn", r)
		"killall", "kill", "clear":
			return _call("killall", {})
		"god":
			return _call("god", {"on": words[1] if words.size() > 1 else "toggle"})
		"ungod":
			return _call("god", {"on": "off"})
		"heal":
			return _call("heal", {})
		"freeze":
			return _call("freeze", {"on": words[1] if words.size() > 1 else "toggle"})
		"unfreeze":
			return _call("freeze", {"on": "off"})
		"give", "g", "take":
			var r := parse_give(words.slice(1))
			if r.is_empty():
				return "Don't know that item. Try: items all"
			if cmd == "take":
				r.count = -r.count
			return _call("give", r)
		"items":
			return _call("items", {"all": words.size() > 1})
		"clearitems":
			return _call("clearitems", {})
		"list":
			var out := PackedStringArray()
			for fam: String in Enemies.FAMILIES:
				var names := PackedStringArray()
				for id: String in Enemies.FAMILIES[fam]:
					names.append(String(Enemies.TYPES[id].name).to_lower())
				out.append("%s: %s" % [fam, ", ".join(names)])
			return "\n".join(out)
	return "Unknown command '%s' (help)" % cmd


func _call(what: String, data: Dictionary) -> String:
	if game and game.has_method("admin"):
		return game.admin(what, data)
	return "(no game to run it in)"


## The words after "give": {id, count} ("random" for a random one), or {} if it isn't an item.
static func parse_give(words: Array) -> Dictionary:
	var count := 1
	var name := PackedStringArray()
	for w: String in words:
		if w.is_valid_int():
			count = clampi(int(w), 1, 100)
		else:
			name.append(w)
	var joined := " ".join(name)
	if joined == "random" or joined == "any":
		return {"id": "random", "count": count}
	var id := Upgrades.find(joined)
	return {} if id == "" else {"id": id, "count": count}


## The words after "spawn" -> {type, count}, or {} if it isn't an enemy. Order doesn't matter:
## "flyer beam", "beam flyer", "beam", "swarmer 5", "healers 2". A family on its own ("flyer",
## "runner") picks one of its variants at random.
static func parse_spawn(words: Array) -> Dictionary:
	var count := 1
	var family := ""
	var variant := ""
	for w: String in words:
		if w.is_valid_int():
			count = clampi(int(w), 1, 30)
			continue
		var word := w.trim_suffix("s") if not VARIANT_WORDS.has(w) and not Enemies.FAMILIES.has(w) else w
		if Enemies.FAMILIES.has(word):
			family = word
		elif VARIANT_WORDS.has(word):
			variant = VARIANT_WORDS[word]
		else:
			return {}
	if variant == "" and family == "":
		return {}
	if variant == "":
		var options: Array = Enemies.FAMILIES[family]
		variant = options[randi() % options.size()]
	elif family != "" and Enemies.TYPES[variant].family != family:
		return {} # "runner beam": not a thing
	return {"type": variant, "count": count}
