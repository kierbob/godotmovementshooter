class_name Showcase
extends SubViewportContainer
## Loadout "locker" stage (the web game's showcase.js): a small separate 3D view that shows the
## selected gun/ability slowly swaying (drag to spin), plus one-off picture thumbnails of every
## item for the tiles.

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _models := {} # id -> stage model (null if it failed to load)
var _current: Node3D
var _want := ""
var _pop := 1.0
var _spin := 0.0 # extra yaw from dragging
var _spin_vel := 0.0
var _dragging := false
var _t := 0.0
var _thumbs := {} # id -> Texture2D
var _thumbs_started := false


func _ready() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 28
	_vp.add_child(_cam)
	_add_lights(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	resized.connect(_fit_camera)
	_fit_camera()


## Key light from the front-right plus a yellow rim from behind (showcase.js).
static func _add_lights(parent: Node) -> void:
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(-Vector3(2, 3, 4))
	key.light_energy = 2.4
	parent.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(-Vector3(-3, 1, -2))
	rim.light_color = UiStyle.YELLOW
	rim.light_energy = 1.2
	parent.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


## Keep the whole gun in view on narrow screens; on wide ones slide it right, clear of the stats.
func _fit_camera() -> void:
	if size.y <= 0:
		return
	var aspect := size.x / size.y
	var wide := aspect >= 1.3
	var z := 4.4 if wide else 4.4 * (1.3 / aspect)
	var shift := -minf(1.1, (aspect - 1.3) * 0.9) if wide else 0.0
	_cam.position = Vector3(shift, 0.35, z)
	_cam.look_at(Vector3(shift, 0, 0))


## Stage models are built once and kept (hidden) under the pivot, so they're freed with the tree.
func _model(id: String) -> Node3D:
	if not _models.has(id):
		var m := Models.stage_model(id)
		if m:
			m.visible = false
			_pivot.add_child(m)
		_models[id] = m
	return _models[id]


func show_item(id: String) -> void:
	if id == _want:
		return
	_want = id
	if _current:
		_current.visible = false
	_current = _model(id)
	if _current:
		_current.visible = true
		_pop = 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_spin_vel = event.relative.x * 0.012
		_spin += _spin_vel
		accept_event()


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		_dragging = false
		return
	dt = minf(dt, 0.05)
	_t += dt
	if not _dragging:
		_spin_vel *= exp(-dt * 3)
		_spin += _spin_vel
	_pop = minf(1.0, _pop + dt * 5)
	var s := 0.8 + 0.2 * (1 - pow(1 - _pop, 3)) + sin(_pop * PI) * 0.06
	_pivot.scale = Vector3.ONE * s
	_pivot.rotation = Vector3(0.12 + sin(_t * 0.9) * 0.05, sin(_t * 0.5) * 0.45 + _spin, 0)
	_pivot.position.y = sin(_t * 1.4) * 0.04


func thumb(id: String) -> Texture2D:
	return _thumbs.get(id)


## Render a 3/4-view picture of each item for the tiles, one per frame. Calls on_each(id, texture)
## as they finish. Skipped without a real renderer (headless tests).
func render_thumbnails(ids: Array, on_each: Callable) -> void:
	if _thumbs_started or DisplayServer.get_name() == "headless":
		return
	_thumbs_started = true
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 180)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 28
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.4, 4.2), Vector3.ZERO)
	_add_lights(vp)
	var pivot := Node3D.new()
	pivot.rotation = Vector3(0.15, 0.35, 0)
	vp.add_child(pivot)
	for id: String in ids:
		var m := Models.stage_model(id)
		if m == null:
			continue
		pivot.add_child(m)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return
		var img := vp.get_texture().get_image()
		if img and not img.is_empty():
			_thumbs[id] = ImageTexture.create_from_image(img)
			on_each.call(id, _thumbs[id])
		pivot.remove_child(m)
		m.queue_free()
	vp.queue_free()
