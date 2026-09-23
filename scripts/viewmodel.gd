class_name Viewmodel
extends CanvasLayer
## The first-person gun. It lives in its own little 3D world drawn over the game (the web game's
## separate viewmodel scene), so guns never clip into walls and keep one FOV. Animation follows
## fx.js updateViewmodel: draw, recoil kick, walk bob, mouse sway, slide tilt, and the reload
## (flick the gun away, hands empty while it flies off in the world, a fresh gun springs up).
## Muzzle effects (fx.js muzzleFx) happen in here too: flash, comic POW star, action lines, smoke
## puffs and shell casings.

## The reload flick is done: the world should fling this gun away (CombatView.toss_gun).
signal tossed(weapon_id: String)
## A comic word next to the gun; screen_pos is 0..1.
signal word(text: String, screen_pos: Vector2, style: String)

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
var _cam: Camera3D
var _particles: Particles
var _flash: Node3D
var _flash_t := 0.0
var _star: Sprite3D
var _star_t := 0.0
var _star_size := 0.0
var _lines: Sprite3D
var _lines_t := 0.0
var _lines_size := 0.0
var _light: OmniLight3D
var _tossed_this_reload := false
var _star_tex: Texture2D
var _lines_tex: Texture2D


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
	_cam = cam
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
	_build_muzzle_fx()
	visible = false


func _build_muzzle_fx() -> void:
	var root := Node3D.new()
	_vp.add_child(root)
	_star_tex = Models.texture("res://assets/fx/star.png")
	_lines_tex = Models.texture("res://assets/fx/lines.png")
	_particles = Particles.new(root, 60, 0.9)
	# Muzzle flash: three crossed glowing blades
	_flash = Node3D.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color("ffd27a", 0.95)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.07)
	for i in 3:
		var p := MeshInstance3D.new()
		p.mesh = q
		p.material_override = fm
		p.rotation.z = i * PI / 3
		_flash.add_child(p)
	_flash.visible = false
	_vp.add_child(_flash)
	_star = _sprite(_star_tex)
	_lines = _sprite(_lines_tex)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffc060")
	_light.omni_range = 2
	_light.light_energy = 0
	_vp.add_child(_light)


## A flat picture that always faces the camera and draws over the gun.
func _sprite(tex: Texture2D) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.no_depth_test = true
	sp.render_priority = 10
	sp.visible = false
	_vp.add_child(sp)
	return sp


## Where the barrel of the gun in your hands is, in the viewmodel's space (camera at the origin).
func _muzzle() -> Vector3:
	var gun: Node3D = _guns.get(_current)
	if gun == null:
		return Vector3(0.18, -0.16, -0.7)
	return gun.transform * (gun.get_meta("muzzle") as Vector3)



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
				var w: Dictionary = Items.WEAPONS[e.weapon]
				_kick = minf(1.2, _kick + float(w.kick))
				_flash_t = 0.05
				_flash.rotation.z = randf() * PI
				_light.light_energy = 3.0
				_muzzle_fx(w)
			"throw":
				_throw_t = 1.0


## Everything that pops out of the gun when it fires.
func _muzzle_fx(w: Dictionary) -> void:
	var f: Dictionary = w.fx
	var m := _muzzle()
	_star_t = 0.08
	_star_size = f.star
	_star.modulate = Color("fff3a0")
	if f.lines:
		_lines_t = 0.1
		_lines_size = f.star * 1.4
	# Smoke puffs curling off the barrel (unlit and a bit smaller than the web game's: shaded,
	# see-through grey puffs this close to the camera read as a dark smudge)
	for i in (4 if f.lines else 2):
		_particles.spawn({
			"pos": m, "life": randf_range(0.3, 0.45), "drag": 3.0,
			"vel": Vector3(randf_range(-0.15, 0.15), randf_range(0.15, 0.4), randf_range(-0.6, -0.2)),
			"size": [0.012, randf_range(0.035, 0.055) * (1.4 if f.lines else 1.0)],
			"color": Color("ffffff"), "color2": Color("e4e7f0"), "opacity": [0.75, 0.0], "fade_start": 0.2,
		})
	# Shell casing flicked out to the right
	var gun: Node3D = _guns.get(w.id)
	if f.shell != null and gun:
		_particles.spawn({
			"cube": true, "lit": true, "pos": gun.transform * Vector3(0.03, 0.03, -0.1), "gravity": 5.0, "spin": 25.0,
			"life": 0.6, "vel": Vector3(randf_range(0.6, 1), randf_range(0.8, 1.2), randf_range(0, 0.3)),
			# smaller than the web game's: right next to the camera its size read as a big block
			"size": [0.016, 0.014] if w.id == "shotgun" else [0.01, 0.009], "color": f.shell, "opacity": [1.0, 1.0],
		})
	# Comic word next to the gun
	if randf() < f.word_chance:
		var px := _cam.unproject_position(m)
		word.emit((f.words as Array).pick_random(), px / Vector2(_vp.size), "big" if f.lines else "small")


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
			if not _tossed_this_reload:
				_tossed_this_reload = true
				tossed.emit(w.id)
		else:
			var k := (reload_p - 0.5) / 0.5
			var c := 1.7
			var e := 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2) # ease-out-back
			r_y = -0.45 * (1 - e)
			r_rot = -0.5 * (1 - e)
	else:
		_tossed_this_reload = false
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

	# Muzzle flash, POW star and action lines follow the barrel while they're up.
	var m := _muzzle()
	_flash_t = maxf(0.0, _flash_t - dt)
	_flash.visible = _flash_t > 0
	_flash.position = m
	_light.position = m
	_light.light_energy = 3.0 if _flash_t > 0 else 0.0
	_star_t = maxf(0.0, _star_t - dt)
	_star.visible = _star_t > 0
	if _star.visible:
		var t := 1.0 - _star_t / 0.08
		_star.position = m
		_star.pixel_size = _star_size * (0.7 + 0.5 * sin(minf(1.0, t * 1.6) * PI)) / _star_tex.get_width()
		_star.modulate.a = 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
	_lines_t = maxf(0.0, _lines_t - dt)
	_lines.visible = _lines_t > 0
	if _lines.visible:
		var t := 1.0 - _lines_t / 0.1
		_lines.position = m
		_lines.pixel_size = _lines_size * (0.6 + 0.6 * t) / _lines_tex.get_width()
		_lines.modulate.a = 1.0 - t * t
	_particles.update(dt)
