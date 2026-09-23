class_name Viewmodel
extends CanvasLayer
## The first-person gun. It lives in its own little 3D world drawn over the game (the web game's
## separate viewmodel scene), so guns never clip into walls and keep one FOV. Animation follows
## fx.js updateViewmodel: draw, recoil kick, walk bob, mouse sway, slide tilt, and the reload
## (flick the gun away, hands empty, a fresh gun springs up).

const FOV := 62.0

var _vp: SubViewport
var _sun: DirectionalLight3D
var _guns := {} # weapon id -> holder Node3D (null if the model failed to load)
var _current := ""
var _kick := 0.0
var _throw_t := 0.0
var _bob_phase := 0.0
var _sway := 0.0
var _last_yaw := 0.0


func _ready() -> void:
	layer = 4 # under the HUD (5) and menus (10)
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.01
	cam.far = 10.0
	_vp.add_child(cam)
	# Toon shading comes from the sun bands + the global hemisphere fill, same as the world.
	_sun = DirectionalLight3D.new()
	_sun.basis = Basis.looking_at(-Vector3(1, 2, 1)) # shining from up-right-behind (web vmSun)
	_sun.light_energy = 1.8
	_vp.add_child(_sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	for id: String in Items.WEAPONS:
		var g := Models.viewmodel(id)
		if g:
			g.visible = false
			_vp.add_child(g)
		_guns[id] = g
	visible = false


## Match the quality setting's anti-aliasing (the gun is small, so it's worth keeping some).
func set_msaa(msaa: Viewport.MSAA) -> void:
	_vp.msaa_3d = maxi(msaa, Viewport.MSAA_2X) as Viewport.MSAA


func has_model(id: String) -> bool:
	return _guns.get(id) != null


## React to combat events (call once per frame with that frame's events).
func on_events(events: Array[Dictionary], combat: Combat) -> void:
	for e in events:
		match e.type:
			"shot":
				_kick = minf(1.2, _kick + float(Items.WEAPONS[e.weapon].kick))
			"throw":
				_throw_t = 1.0


func update(dt: float, combat: Combat, player: PlayerSim, yaw: float) -> void:
	var w := combat.weapon()
	if _current != w.id:
		if _guns.get(_current):
			(_guns[_current] as Node3D).visible = false
		_current = w.id
	var gun: Node3D = _guns.get(w.id)
	if gun == null:
		return
	var st := combat.weapon_state()
	var draw_p := combat.draw_t / Combat.SWITCH_TIME

	# Reload: 0–12% wind-up flick, 12–50% hands empty, 50–100% new gun springs up (overshoots).
	var reload_p: float = 1.0 - st.reload_t / w.reload if st.reload_t > 0 else 0.0
	var r_y := 0.0
	var r_rot := 0.0
	var r_x := 0.0
	var empty := false
	if st.reload_t > 0:
		if reload_p < 0.12:
			var k := reload_p / 0.12
			r_y = k * 0.12
			r_rot = k * 0.9
			r_x = k * 0.08
		elif reload_p < 0.5:
			empty = true
		else:
			var k := (reload_p - 0.5) / 0.5
			var c := 1.7
			var e := 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2) # ease-out-back
			r_y = -0.45 * (1 - e)
			r_rot = -0.5 * (1 - e)
	gun.visible = not empty

	_kick = maxf(0.0, _kick - dt * 7)
	_throw_t = maxf(0.0, _throw_t - dt * 4)
	var speed := player.horizontal_speed()
	var walking := player.grounded and not player.sliding
	if walking:
		_bob_phase += dt * (4 + speed * 0.9)
	var bob_amt := minf(1.0, speed / 9) if walking else 0.0
	var dyaw := yaw - _last_yaw
	_last_yaw = yaw
	_sway += (clampf(dyaw * 0.8, -0.04, 0.04) - _sway) * minf(1.0, dt * 12)

	gun.position = Vector3(
		0.24 + sin(_bob_phase) * 0.012 * bob_amt + _sway + r_x,
		-0.24 + absf(cos(_bob_phase)) * 0.014 * bob_amt - draw_p * 0.3 + r_y - _throw_t * 0.18,
		-0.42 + _kick * 0.07)
	# The holder's own yaw is the barrel cant; everything else animates on top of it.
	gun.rotation = Vector3(_kick * 0.16 + r_rot - draw_p * 0.6, 0.08 + _sway * 2, -r_x * 3 + (0.15 if player.sliding else 0.0))
