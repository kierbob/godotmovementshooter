extends Node3D
## Game entry. Builds the map, runs the movement + combat sim at a fixed 120 Hz (Godot physics
## ticks), draws the first-person camera and gun in between ticks, and switches between the
## menu / playing / paused.
##
## Command-line options (after `--`), handy for testing:
##   --map=bean-street        start on another map from data/
##   --at=x,y,z,yaw,pitch     start playing, placed there
##   --screen=main|maps|pause|settings:<tab>   open a menu screen
##   --shot=path.png          save a screenshot after --frames=N frames, then quit

const MAPS: Array[String] = ["dev_map", "bean-street"]
const SENS_BASE := 0.022 * PI / 180.0 # radians per mouse count at sensitivity 1 (CS2 / Apex scale)

static var auto_play := false # set before reloading into another map from the menu

var state := "menu" # "menu" | "playing" | "paused"
var map_id := "" # which map this scene built
var map: MapData
var player: PlayerSim
var combat: Combat
var combat_view: CombatView
var viewmodel: Viewmodel
var camera: Camera3D
var hud: Hud
var menu: Menu
var clouds: Node3D
var beans: Array[Dictionary] = [] # one per combat target, same order: {node, mats, fill, flash}
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial

var prev_pos := Vector3.ZERO # position at the previous tick (the camera blends toward the current one)
var yaw := 0.0
var pitch := 0.0
var eye := Cfg.PLAYER_EYE_HEIGHT
var roll := 0.0
var top_speed := 0.0
var menu_time := 0.0

# Presses since the last tick (a quick tap between two ticks still counts).
var jump_pressed := false
var slide_pressed := false
var respawn_pressed := false
var fire_pressed := false
var reload_pressed := false
var ability_pressed := false
var slot_pressed := "" # "primary" / "secondary"
var cycle := 0 # mouse wheel

var _debug_timer := 0.0
var _frames := 0
var _fps_timer := 0.0
var _fps := 0
var _shot_path := ""
var _shot_frames := 30
var _frame := 0


func _ready() -> void:
	Settings.load_settings()
	Settings.apply_input()
	_parse_args()
	if not MAPS.has(Settings.map):
		Settings.map = MAPS[0]
	map_id = Settings.map
	map = MapData.load_file("res://data/%s.json" % map_id)
	WorldView.build_world(map, self)
	WorldView.build_pads(map, self)
	clouds = WorldView.build_clouds(self)
	combat = Combat.new(map.boxes, map.targets)
	combat_view = CombatView.new()
	add_child(combat_view)
	_build_beans()
	_setup_environment()
	Look.apply(Settings.lighting, env, sun, sky_mat, WorldView.cloud_material)
	if _shot_path == "":
		Settings.apply_display()
	Settings.apply_quality(get_viewport())
	viewmodel = Viewmodel.new()
	add_child(viewmodel)
	viewmodel.set_msaa(Settings.QUALITY[Settings.quality].msaa)

	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 500.0
	add_child(camera)

	player = PlayerSim.new(map.spawn.x, map.spawn.y, map.spawn.z)
	yaw = map.spawn.yaw
	prev_pos = _player_pos()

	hud = Hud.new()
	add_child(hud)
	hud.debug_mode = Settings.stats_mode
	menu = Menu.new()
	add_child(menu)
	menu.map_name = map.name
	menu.play.connect(_on_play)
	menu.resume.connect(_resume)
	menu.to_main_menu.connect(_enter_menu)
	menu.quit_game.connect(func() -> void: get_tree().quit())
	menu.settings_changed.connect(_on_settings_changed)
	combat_view.word.connect(hud.word)
	viewmodel.word.connect(func(text: String, at: Vector2, style: String) -> void: hud.word(text, null, at, style))
	viewmodel.tossed.connect(func(id: String) -> void: combat_view.toss_gun(id, camera, player))

	if auto_play:
		auto_play = false
		_start_play()
	else:
		_enter_menu()
	_apply_args_state()


# ---------- states ----------

func _enter_menu() -> void:
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_in_game(false)
	viewmodel.visible = false
	menu.show_screen("main")


func _start_play() -> void:
	state = "playing"
	player = PlayerSim.new(map.spawn.x, map.spawn.y, map.spawn.z)
	yaw = map.spawn.yaw
	pitch = 0.0
	top_speed = 0.0
	eye = Cfg.PLAYER_EYE_HEIGHT
	prev_pos = _player_pos()
	combat.set_loadout(Settings.loadout)
	combat.reset_targets()
	combat_view.clear()
	hud.clear_floaters()
	if _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_in_game(true)
	viewmodel.visible = true
	menu.show_screen("")


func _pause() -> void:
	state = "paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show_screen("pause")


func _resume() -> void:
	state = "playing"
	if _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu.show_screen("")


func _on_play(id: String) -> void:
	if id != map_id:
		# The world is built once per scene: reload into the new map and start right away.
		Settings.map = id
		Settings.save_settings()
		auto_play = true
		get_tree().reload_current_scene()
		return
	_start_play()


func _on_settings_changed(what: String) -> void:
	match what:
		"video", "audio":
			Settings.apply_display()
		"quality":
			Settings.apply_quality(get_viewport())
			viewmodel.set_msaa(Settings.QUALITY[Settings.quality].msaa)
		"lighting":
			Look.apply(Settings.lighting, env, sun, sky_mat, WorldView.cloud_material)


func _notification(what: int) -> void:
	# Alt-tab / clicking another window pauses (it's solo).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and _shot_path == "":
		_pause()


# ---------- setup ----------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			Settings.map = a.substr(6)
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--lighting="):
			Settings.lighting = a.substr(11)


func _apply_args_state() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var v := a.substr(5).split(",")
			_start_play()
			player.respawn(float(v[0]), float(v[1]), float(v[2]))
			prev_pos = _player_pos()
			if v.size() > 3:
				yaw = float(v[3])
			if v.size() > 4:
				pitch = float(v[4])
		elif a.begins_with("--screen="):
			var sc := a.substr(9)
			if sc == "pause":
				_start_play()
				_pause()
			elif sc.begins_with("settings"):
				var parts := sc.split(":")
				if parts.size() > 1:
					menu._settings_tab = parts[1]
				menu.open_settings("main")
			else:
				menu.show_screen(sc)


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	# Lighting comes from the toon shader (sun bands + hemisphere fill), not Godot's ambient.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Very distant haze in the horizon color: fights are untouched, the far map edge softens.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_beans() -> void:
	for t in combat.targets:
		var node := WorldView.make_bean()
		node.position = t.pos
		add_child(node)
		var mats := [(node.get_child(0) as MeshInstance3D).material_override, (node.get_child(1) as MeshInstance3D).material_override]
		# Health bar over the head (the bean turns to face you, so the bar does too).
		var bar := Node3D.new()
		bar.position.y = 2.2
		for part: Array in [[Vector2(0.84, 0.1), Color(0.07, 0.07, 0.07, 0.7), 0.0], [Vector2(0.8, 0.07), Color("5ee06a"), 0.001]]:
			var q := QuadMesh.new()
			q.size = part[0]
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.position.z = part[2]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = part[1]
			if part[1].a < 1:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = m
			bar.add_child(mi)
		node.add_child(bar)
		beans.append({"node": node, "mats": mats, "fill": bar.get_child(1), "flash": 0.0})


# ---------- input ----------

func _input(event: InputEvent) -> void:
	if menu.listening != "":
		return # the settings screen is waiting for a new keybind
	if event.is_action_pressed("fullscreen"):
		Settings.fullscreen = not Settings.fullscreen
		Settings.save_settings()
		Settings.apply_display()
		return
	if state != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# screen_relative = raw mouse counts (Godot reads raw input while the mouse is captured).
		var rel: Vector2 = event.screen_relative
		var k := SENS_BASE * Settings.sensitivity
		yaw -= rel.x * k
		pitch = clampf(pitch - rel.y * k, -PI / 2 + 0.001, PI / 2 - 0.001)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump"):
		jump_pressed = true
	if event.is_action_pressed("slide"):
		slide_pressed = true
	if event.is_action_pressed("respawn"):
		respawn_pressed = true
	if event.is_action_pressed("fire"):
		fire_pressed = true
	if event.is_action_pressed("reload"):
		reload_pressed = true
	if event.is_action_pressed("ability"):
		ability_pressed = true
	if event.is_action_pressed("primary"):
		slot_pressed = "primary"
	if event.is_action_pressed("secondary"):
		slot_pressed = "secondary"
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle = 1
	if event.is_action_pressed("stats"):
		Settings.stats_mode = hud.cycle_debug()
		Settings.save_settings()
	if event.is_action_pressed("next_map"):
		_on_play(MAPS[(MAPS.find(map_id) + 1) % MAPS.size()])


func _axis(pos: String, neg: String) -> float:
	return (1.0 if Input.is_action_pressed(pos) else 0.0) - (1.0 if Input.is_action_pressed(neg) else 0.0)


func _sample() -> Cmd:
	var c := Cmd.new()
	c.forward = _axis("forward", "back")
	c.right = _axis("right", "left")
	c.jump = jump_pressed
	c.jump_held = Input.is_action_pressed("jump")
	c.sprint = Input.is_action_pressed("sprint")
	c.crouch = Input.is_action_pressed("crouch")
	c.slide = Input.is_action_pressed("slide")
	c.slide_pressed = slide_pressed
	c.fire = Input.is_action_pressed("fire")
	c.fire_pressed = fire_pressed
	c.reload = reload_pressed
	c.ability = ability_pressed
	c.slot = slot_pressed
	c.cycle = cycle
	c.yaw = yaw
	c.pitch = pitch
	jump_pressed = false
	slide_pressed = false
	fire_pressed = false
	reload_pressed = false
	ability_pressed = false
	slot_pressed = ""
	cycle = 0
	return c


# ---------- simulation (fixed 120 Hz) ----------

func _physics_process(_delta: float) -> void:
	if state != "playing":
		return # solo: menus freeze the game
	prev_pos = _player_pos()
	if respawn_pressed:
		respawn_pressed = false
		_respawn()
	var c := _sample()
	combat.tick(player, c, Cfg.TICK_DT) # before movement so knockback applies this tick
	player.step(c, map, Cfg.TICK_DT)
	if player.py < -30:
		_respawn()


func _respawn() -> void:
	player.respawn(map.spawn.x, map.spawn.y, map.spawn.z)
	yaw = map.spawn.yaw
	pitch = 0.0
	prev_pos = _player_pos()


func _player_pos() -> Vector3:
	return Vector3(player.px, player.py, player.pz)


# ---------- per frame ----------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	var cur := _player_pos()
	var speed := player.horizontal_speed()
	if state == "menu":
		# Slow orbit around the map behind the main menu.
		menu_time += dt
		var t := menu_time * 0.06
		camera.fov = Settings.fov
		camera.look_at_from_position(Vector3(sin(t) * 42, 20, cos(t) * 42), Vector3(0, 3, 0))
	else:
		var a := Engine.get_physics_interpolation_fraction() if state == "playing" else 1.0
		var pos := prev_pos.lerp(cur, a)
		# Camera effects ease toward targets so crouch/slide transitions aren't instant snaps.
		eye = _ease(eye, Cfg.PLAYER_CROUCH_EYE_HEIGHT if player.crouching else Cfg.PLAYER_EYE_HEIGHT, 14, dt)
		roll = _ease(roll, -0.05 if player.sliding else 0.0, 10, dt)
		var speed_t := clampf((speed - Cfg.MOVE_WALK_SPEED) / (Cfg.MOVE_MAX_SPEED - Cfg.MOVE_WALK_SPEED), 0, 1)
		camera.fov = _ease(camera.fov, Settings.fov + speed_t * 15, 6, dt)
		camera.position = pos + Vector3(0, eye, 0)
		camera.rotation = Vector3(pitch, yaw, roll) # Godot's default Euler order is YXZ, same as the web game
		if combat_view.shake > 0 and state == "playing":
			var sh := combat_view.shake
			camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * sh

	_update_beans(cur if state != "menu" else camera.position, dt)
	clouds.rotation.y += dt * 0.004
	top_speed = maxf(top_speed, speed)
	hud.set_speed(speed, top_speed)

	var events := combat.fx
	combat.fx = []
	hud.on_events(events)
	viewmodel.on_events(events, combat)
	# Tracers leave from about where the gun's barrel is on screen (fx.js muzzleWorld).
	combat_view.on_events(events, camera.global_transform * Vector3(0.18, -0.16, -0.7), player)
	for e in events:
		if e.type == "hit":
			beans[e.target].flash = 0.08
	combat_view.update(dt if state == "playing" else 0.0, combat)
	if state != "menu":
		hud.update_combat(dt if state == "playing" else 0.0, combat, camera)
		viewmodel.update(dt if state == "playing" else 0.0, combat, player, yaw)
	_update_debug(dt, speed)

	if _shot_path != "":
		_frame += 1
		if _frame == _shot_frames:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


func _ease(cur: float, target: float, rate: float, dt: float) -> float:
	return cur + (target - cur) * minf(1.0, dt * rate)


## Combat moves the dummies (sliding ones) and decides when they're down. Hit dummies flash white
## for a moment; the bar over their head shows health (green, yellow, red).
func _update_beans(look_at_pos: Vector3, dt: float) -> void:
	for i in beans.size():
		var b := beans[i]
		var node: Node3D = b.node
		var t := combat.targets[i]
		node.position = t.pos
		node.visible = not t.dead
		node.rotation.y = atan2(look_at_pos.x - t.pos.x, look_at_pos.z - t.pos.z) # dummies turn to face you
		var frac := t.hp / t.max_hp
		var fill: MeshInstance3D = b.fill
		fill.scale.x = maxf(0.001, frac)
		fill.position.x = -0.4 * (1 - frac)
		(fill.material_override as StandardMaterial3D).albedo_color = \
			Color("5ee06a") if frac > 0.5 else Color("f2c14e") if frac > 0.25 else Color("e5534b")
		b.flash = maxf(0.0, b.flash - dt)
		for m: ShaderMaterial in b.mats:
			m.set_shader_parameter("emission_boost", 2.5 if b.flash > 0 else 0.0)


func _update_debug(dt: float, speed: float) -> void:
	_frames += 1
	_fps_timer += dt
	if _fps_timer >= 0.5:
		_fps = roundi(_frames / _fps_timer)
		_frames = 0
		_fps_timer = 0.0
	_debug_timer -= dt
	if _debug_timer > 0:
		return
	_debug_timer = 0.1
	if hud.debug_mode == 1:
		hud.set_debug("%d FPS · %.1f m/s · %s" % [_fps, speed, player.state])
		return
	var lines := PackedStringArray()
	lines.append("%d FPS   %s   (Godot %s)" % [_fps, map.name, Engine.get_version_info().string])
	lines.append("speed      %.2f m/s   top %.2f" % [speed, top_speed])
	lines.append("state      %s%s%s" % [player.state, "  grounded" if player.grounded else "", "  sprint" if player.sprinting else ""])
	lines.append("pos        %.2f  %.2f  %.2f" % [player.px, player.py, player.pz])
	lines.append("vel        %.2f  %.2f  %.2f" % [player.vx, player.vy, player.vz])
	lines.append("yaw/pitch  %.1f°  %.1f°" % [rad_to_deg(yaw), rad_to_deg(pitch)])
	lines.append("wall jumps %d   slide cd %.2f" % [player.wall_jumps, player.slide_cooldown])
	var st := combat.weapon_state()
	lines.append("weapon     %s  %d/%d%s   ability %.1f" % [combat.weapon().name, st.ammo, combat.weapon().mag,
		"  reloading" if st.reload_t > 0 else "", combat.ability_cd])
	lines.append("")
	for e: Dictionary in player.events.slice(-6):
		lines.append("%6.2f  %s  %s" % [e.t, e.name, e.detail])
	hud.set_debug("\n".join(lines))
