class_name LoadingScreen
extends CanvasLayer
## The card between the lobby and a stage (Risk of Rain style): stage number, the map's name in its
## own colors, a progress bar, what's happening and a tip. It lives under the tree root, so it
## stays up while the game scene reloads into the stage, and fades out when the run starts.
##
## begin() shows it and loads the stage's heavy files on a background thread; then `then` runs
## (the game reloads into the stage and reports its own build progress with progress()). Online,
## wait_for_players() keeps it up until the host says go.

const MIN_TIME := 1.2 # seconds on screen at least, so it doesn't just flash
const TIPS := [
	"Shoot the floor with the Boomstick to launch yourself.",
	"Aim at your feet and jump for a rocket jump.",
	"Slide down ramps to pick up speed. Slide-jump to keep it.",
	"Wall jump by jumping while you touch a wall in the air.",
	"Headshots do more damage with almost everything.",
	"Speed is safety: a moving bean is hard to hit.",
	"Jump pads keep your speed. Hit them running.",
]

static var instance: LoadingScreen

var _root: Control
var _bar_fill: ColorRect
var _status: Label
var _tip: Label
var _shown_at := 0.0
var _progress := 0.0
var _target := 0.0
var _requests: Array[String] = []
var _then := Callable()
var _closing := false
var _dots := 0.0


## Show the card (kicker like "STAGE 1", map `stage_id`), start loading, then call `then`.
static func begin(tree: SceneTree, kicker: String, stage_id: String, then: Callable) -> LoadingScreen:
	if instance and is_instance_valid(instance):
		instance.queue_free()
	instance = LoadingScreen.new()
	instance.name = "LoadingScreen"
	tree.root.add_child(instance)
	instance._setup(kicker, stage_id)
	instance._start(stage_id, then)
	return instance


static func is_up() -> bool:
	return instance != null and is_instance_valid(instance) and not instance._closing


## The game reports how its build is going (0..1 of its part) and what it's doing.
static func progress(frac: float, text: String) -> void:
	if is_up():
		instance._target = maxf(instance._target, 0.5 + 0.45 * clampf(frac, 0, 1))
		instance._status.text = text


## Online: loaded, now waiting for the others.
static func wait_for_players(text: String) -> void:
	if is_up():
		instance._target = 1.0
		instance._status.text = text


## Fade out (after the minimum time) and go away.
static func finish() -> void:
	if is_up():
		instance._finish()


func _setup(kicker: String, stage_id: String) -> void:
	layer = 50
	var info := MapData.info(stage_id)
	var grad: Array = info.get("grad", [Color("2f6bff"), Color("8a3dff")])
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it is clickable while loading
	add_child(_root)
	var bg := UiStyle.gradient_rect(PackedColorArray([Color("0a0e30"), (grad[0] as Color).darkened(0.55), (grad[1] as Color).darkened(0.45)]), 1)
	_root.add_child(bg)
	var art := UiStyle.label(String(info.get("art", "")), 360, Color(1, 1, 1, 0.07), true)
	art.remove_theme_color_override("font_shadow_color")
	art.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	art.offset_left = -1500
	art.offset_top = -420
	art.offset_right = 40
	art.offset_bottom = 60
	art.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(art)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_right = 1100
	col.offset_top = 0
	col.offset_bottom = 0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	_root.add_child(col)
	col.add_child(UiStyle.label(kicker, 34, UiStyle.YELLOW, true))
	col.add_child(UiStyle.label(String(info.get("name", stage_id)).to_upper(), 130, UiStyle.TEXT, true))
	var desc := UiStyle.note(String(info.get("desc", "")), 18, Color("c9d1f5"))
	col.add_child(desc)
	# bottom: status, bar, tip
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 90
	bottom.offset_right = -90
	bottom.offset_top = -150
	bottom.offset_bottom = -50
	bottom.add_theme_constant_override("separation", 10)
	_root.add_child(bottom)
	_status = UiStyle.label("Loading the stage", 26)
	bottom.add_child(_status)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.12)
	bar.custom_minimum_size.y = 10
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiStyle.YELLOW
	_bar_fill.size = Vector2(0, 10)
	bar.add_child(_bar_fill)
	bottom.add_child(bar)
	_tip = UiStyle.note("TIP: " + TIPS.pick_random(), 16, UiStyle.MUTED)
	bottom.add_child(_tip)
	_root.modulate.a = 0.0
	_shown_at = Time.get_ticks_msec() / 1000.0


## Heavy files (the stage scene, the gun models) load on a thread while the card animates.
func _start(stage_id: String, then: Callable) -> void:
	_then = then
	var files: Array[String] = ["res://maps/%s.tscn" % stage_id]
	for m: Dictionary in Items.MODELS.values():
		files.append(Models.DIR + String(m.file))
	for f in files:
		if ResourceLoader.exists(f) and ResourceLoader.load_threaded_request(f) == OK:
			_requests.append(f)


func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _closing:
		_root.modulate.a = minf(1.0, _root.modulate.a + dt * 6)
	_dots += dt
	if _then.is_valid():
		var sum := 0.0
		var done := true
		for f in _requests:
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(f, prog)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				done = false
				sum += float(prog[0]) if not prog.is_empty() else 0.0
			else:
				sum += 1.0
		_target = maxf(_target, 0.5 * (sum / maxf(1.0, _requests.size())))
		# Hand over once the files are in and the card has been fully visible for a moment.
		if done and _root.modulate.a >= 1.0:
			for f in _requests:
				ResourceLoader.load_threaded_get(f) # into the cache: the game's load() is instant now
			_requests.clear()
			var t := _then
			_then = Callable()
			_status.text = "Building the world"
			t.call_deferred()
	_progress = lerpf(_progress, _target, minf(1.0, dt * 8))
	var w: float = (_bar_fill.get_parent() as Control).size.x
	_bar_fill.size.x = w * _progress
	if _closing:
		if now - _shown_at >= MIN_TIME:
			_root.modulate.a -= dt * 4
			if _root.modulate.a <= 0:
				queue_free()
				if instance == self:
					instance = null


func _finish() -> void:
	_target = 1.0
	_closing = true
