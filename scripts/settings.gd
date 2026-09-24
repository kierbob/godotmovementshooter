class_name Settings
## Player settings, saved to user://settings.cfg (the web game kept these in localStorage).
## Keybinds live in Godot's InputMap; a bind is stored as "key:<physical keycode>" or "mouse:<button>".

static var path := "user://settings.cfg" # tests point this elsewhere

## [action, label, group, default bind]
const ACTIONS := [
	["forward", "Move Forward", "Movement", "key:%d" % KEY_W],
	["back", "Move Back", "Movement", "key:%d" % KEY_S],
	["left", "Move Left", "Movement", "key:%d" % KEY_A],
	["right", "Move Right", "Movement", "key:%d" % KEY_D],
	["sprint", "Sprint", "Movement", "key:%d" % KEY_SHIFT],
	["jump", "Jump", "Movement", "key:%d" % KEY_SPACE],
	["crouch", "Crouch", "Movement", "key:%d" % KEY_CTRL],
	["slide", "Slide", "Movement", "key:%d" % KEY_C],
	["fire", "Fire", "Combat", "mouse:%d" % MOUSE_BUTTON_LEFT],
	["reload", "Reload", "Combat", "key:%d" % KEY_R],
	["primary", "Primary Weapon", "Combat", "key:%d" % KEY_1],
	["secondary", "Secondary Weapon", "Combat", "key:%d" % KEY_2],
	["ability", "Ability", "Combat", "key:%d" % KEY_Q],
	["respawn", "Respawn", "Other", "key:%d" % KEY_K],
	["scoreboard", "Scoreboard (online)", "Other", "key:%d" % KEY_TAB],
	["stats", "Stats Panel", "Other", "key:%d" % KEY_F4],
	["console", "Admin Console", "Other", "key:%d" % KEY_F10],
	["fullscreen", "Fullscreen", "Other", "key:%d" % KEY_F11],
	["next_map", "Next Map (dev)", "Other", "key:%d" % KEY_F2],
]

const QUALITY := {
	"high": {"label": "High", "scale": 1.0, "msaa": Viewport.MSAA_4X, "shadow": 4096},
	"balanced": {"label": "Balanced", "scale": 1.0, "msaa": Viewport.MSAA_2X, "shadow": 2048},
	"performance": {"label": "Performance", "scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "shadow": 1024},
}
const FPS_CAPS := [0, 60, 144, 240]

static var sensitivity := 2.0 # same scale as CS2 / Apex
static var fov := 80.0 # vertical, like the web game
static var volume := 0.6
static var fullscreen := false
static var vsync := true
static var max_fps := 0
static var quality := "balanced"
static var lighting := "pastel"
static var stats_mode := 1 # 0 off, 1 compact, 2 full
static var map := "dev_map"
static var character := Characters.DEFAULT # picked in the lobby; sets your kit (Characters.loadout)
static var binds := {} # action -> "key:..." / "mouse:..."
static var player_name := "" # online name
static var join_address := "" # last address joined ("host:port", e.g. a playit.gg address)
static var host_port := 7777
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	reset_binds()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	sensitivity = clampf(cf.get_value("mouse", "sensitivity", sensitivity), 0.05, 20.0)
	fov = clampf(cf.get_value("video", "fov", fov), 60.0, 110.0)
	volume = clampf(cf.get_value("audio", "volume", volume), 0.0, 1.0)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	vsync = cf.get_value("video", "vsync", vsync)
	max_fps = cf.get_value("video", "max_fps", max_fps)
	var q: String = cf.get_value("video", "quality", quality)
	quality = q if QUALITY.has(q) else quality
	var l: String = cf.get_value("video", "lighting", lighting)
	lighting = l if Look.PRESETS.has(l) else lighting
	stats_mode = cf.get_value("hud", "stats_mode", stats_mode)
	map = cf.get_value("game", "map", map)
	player_name = str(cf.get_value("online", "name", player_name)).substr(0, 16)
	join_address = str(cf.get_value("online", "address", join_address))
	host_port = clampi(int(cf.get_value("online", "port", host_port)), 1024, 65535)
	var ch: String = str(cf.get_value("game", "character", character))
	character = ch if Characters.is_valid(ch) else Characters.DEFAULT
	for a: Array in ACTIONS:
		var b: String = cf.get_value("binds", a[0], binds[a[0]])
		if b.begins_with("key:") or b.begins_with("mouse:"):
			binds[a[0]] = b


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("mouse", "sensitivity", sensitivity)
	cf.set_value("video", "fov", fov)
	cf.set_value("audio", "volume", volume)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "max_fps", max_fps)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "lighting", lighting)
	cf.set_value("hud", "stats_mode", stats_mode)
	cf.set_value("game", "map", map)
	cf.set_value("online", "name", player_name)
	cf.set_value("online", "address", join_address)
	cf.set_value("online", "port", host_port)
	cf.set_value("game", "character", character)
	for a: String in binds:
		cf.set_value("binds", a, binds[a])
	cf.save(path)


## Your kit: the picked character's guns and ability.
static func loadout() -> Dictionary:
	return Characters.loadout(character)


static func reset_binds() -> void:
	for a: Array in ACTIONS:
		binds[a[0]] = a[3]


## Bind an action; if another action already uses that key, they swap.
static func bind(action: String, bind_str: String) -> void:
	for other: String in binds:
		if other != action and binds[other] == bind_str:
			binds[other] = binds[action]
	binds[action] = bind_str
	apply_input()


static func event_for(bind_str: String) -> InputEvent:
	var parts := bind_str.split(":")
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(parts[1]) as Key
	return k


## "key:..." / "mouse:..." for an input event, or "" if it can't be a bind.
static func bind_for(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return "key:%d" % code
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


static func bind_label(bind_str: String) -> String:
	var parts := bind_str.split(":")
	if parts[0] == "mouse":
		match int(parts[1]):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		return "Mouse %s" % parts[1]
	# Show the key as printed on YOUR keyboard layout (AZERTY etc.), not the US position.
	var physical := int(parts[1]) as Key
	var shown := physical
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_keycode_from_physical(physical)
		if mapped != KEY_NONE:
			shown = mapped
	return OS.get_keycode_string(shown)


static func apply_input() -> void:
	for a: Array in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event_for(binds[action]))


static func apply_display() -> void:
	var want := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


static func apply_quality(vp: Viewport) -> void:
	var q: Dictionary = QUALITY[quality]
	vp.scaling_3d_scale = q.scale
	vp.msaa_3d = q.msaa
	RenderingServer.directional_shadow_atlas_set_size(q.shadow, true)


## cm of mouse travel for a full 360° turn at this DPI (web settings.js cmPer360).
static func cm_per_360(dpi: float) -> float:
	var counts := 360.0 / (0.022 * sensitivity)
	return counts / dpi * 2.54
