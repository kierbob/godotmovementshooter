extends Node3D
## Game entry. Builds the map, runs the movement + combat sim at a fixed 120 Hz (Godot physics
## ticks), draws the first-person camera and gun in between ticks, and switches between the
## menu / playing / paused. Online (see Net / MatchServer), it predicts your own movement and gun
## locally, corrects to the host's state when it arrives, and draws everyone else.
##
## A run (solo or online) and practice both go lobby/menu -> LoadingScreen -> reload this scene into
## the stage -> play. While a loading screen is up, building the scene yields a frame between steps
## so the card keeps moving and shows how far along it is.
##
## Command-line options (after `--`), handy for testing:
##   --map=bean-town          start on another map from maps/
##   --at=x,y,z,yaw,pitch     start playing, placed there
##   --screen=main|maps|pause|settings:<tab>   open a menu screen
##   --shot=path.png          save a screenshot after --frames=N frames, then quit
##   --host[=port]            host a multiplayer lobby
##   --join=address:port      join a lobby
##   --ready                  ready up in the lobby straight away
##   --solo                   start a solo run
##   --name=Bean              your online name

const SENS_BASE := 0.022 * PI / 180.0 # radians per mouse count at sensitivity 1 (CS2 / Apex scale)

## What to do once this scene has (re)built: {mode: "solo" | "online" | "practice", stage, trial}.
static var pending_run := {}
static var pending_hint := "" # shown on the multiplayer screen after a reload (e.g. "Disconnected")
static var _net_args_done := false # --host / --join / --solo only once (not again after reloading)
static var _auto_ready := false # --ready

var state := "menu" # "menu" | "playing" | "paused"
var map_id := "" # which map this scene built
var map: MapData
var player: PlayerSim
var combat: Combat
var combat_view: CombatView
var viewmodel: Viewmodel
var sound: Sound
var trial: TimeTrial # null on maps without a course
var trial_view: TrialView
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
var _last_move_t := -1.0 # newest movement event that already made a sound

var _debug_timer := 0.0
var _frames := 0
var _fps_timer := 0.0
var _fps := 0
var _shot_path := ""
var _shot_frames := 30
var _frame := 0

# online
var net: Net # the connection (lives outside this scene so it survives reloads)
var online := false
var remote_view: RemoteView
var _history: Array = [] # our recent inputs [[seq, Cmd, impulses]], replayed after a correction
var _visual_offset := Vector3.ZERO # corrections are eased out instead of popping the camera
var _remote_targets := {} # id -> Combat.Target: other players, so our shots stop on them
var _remote_proj := {} # "owner:id" -> Combat.Projectile: other players' rockets, grenades, knives
var _killer := "" # who got us last (death screen)
var _built := false # the scene finished building (it yields frames while a loading screen is up)
var enemies: Enemies
var enemy_view: EnemyView
var console: AdminConsole # F10
var director: Director # a solo run's waves and boss (null in practice)
var run_info := {} # this run so far: stage_n, and what the earlier stages add to the results
var _run_over := false
var loot: Loot # gold, chests and dropped items (solo)
var loot_view: LootView
var interact_pressed := false
var _nav_built: Nav # the worker thread's result (see _ready)
var _respawn_t := -1.0 # solo: seconds until you're back after getting splatted (-1 = alive)
const SOLO_RESPAWN := 2.5
const SOLO_PROTECTION := 1.5
var _waiting_run := false # online: loaded the stage, waiting for the others


func _ready() -> void:
	Settings.load_settings()
	Settings.apply_input()
	_parse_args()
	var maps := MapData.list()
	if not maps.has(Settings.map):
		Settings.map = maps[0] if not maps.is_empty() else "dev_map"
	map_id = Settings.map
	await _step(0.0, "Reading the stage")
	map = MapData.load_map(map_id) # maps/<id>.tscn, edited in the Godot editor
	await _step(0.2, "Building the world")
	WorldView.build_world(map, self)
	WorldView.build_pads(map, self)
	clouds = WorldView.build_clouds(self)
	combat = Combat.new(map.boxes, map.targets)
	combat.grid = map
	enemies = Enemies.new(map, combat)
	loot = Loot.new(map, combat.up)
	if pending_run.get("mode", "") == "solo":
		run_info = pending_run.duplicate(true)
		director = Director.new(enemies, map, int(run_info.get("stage_n", 1)))
		loot.money = director.money_mult() # later stages: bigger payouts, pricier chests
	loot.place_chests() # a random pick of the map's chest spots (none on maps without any)
	# Where enemies can walk (their paths, and safe spawn spots): about a second on a big stage,
	# so it's built on a worker thread while the rest loads. The map is only read from there on
	# (its box grid is built first, here).
	var nav_task := -1
	var nav_mode: String = pending_run.get("mode", "")
	if nav_mode == "solo" or (nav_mode == "practice" and pending_run.get("trial", "") == ""):
		map.nearby(0, 0, 0, 1)
		nav_task = WorkerThreadPool.add_task(func() -> void: _nav_built = Nav.build(map), false, "nav")
	await _step(0.5, "Loading guns and effects")
	combat_view = CombatView.new()
	add_child(combat_view)
	remote_view = RemoteView.new()
	add_child(remote_view)
	enemy_view = EnemyView.new()
	enemy_view.particles = combat_view.particles # burning, bleeding, snow on chilled ones
	add_child(enemy_view)
	loot_view = LootView.new()
	loot_view.particles = combat_view.particles
	add_child(loot_view)
	_build_beans()
	_setup_environment()
	_apply_lighting()
	if _shot_path == "":
		Settings.apply_display()
	Settings.apply_quality(get_viewport())
	viewmodel = Viewmodel.new()
	add_child(viewmodel)
	sound = Sound.new()
	add_child(sound)
	viewmodel.set_msaa(Settings.QUALITY[Settings.quality].msaa)
	await _step(0.85, "Almost there")
	if nav_task >= 0:
		while not WorkerThreadPool.is_task_completed(nav_task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(nav_task)
		enemies.nav = _nav_built
		_nav_built = null

	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 500.0 * map.view_scale
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
	menu.play_trial.connect(_on_play_trial)
	menu.resume.connect(_resume)
	menu.to_main_menu.connect(func() -> void:
		if online:
			_leave_match("")
		else:
			_enter_menu())
	menu.quit_game.connect(func() -> void: get_tree().quit())
	hud.run.again.connect(func() -> void:
		_enter_menu()
		menu.open_lobby("solo"))
	hud.run.main_menu.connect(_enter_menu)
	menu.settings_changed.connect(_on_settings_changed)
	menu.host_match.connect(_on_host)
	menu.join_match.connect(_on_join)
	menu.cancel_online.connect(_on_cancel_online)
	menu.lobby_character.connect(_on_lobby_character)
	menu.lobby_ready.connect(_on_lobby_ready)
	menu.lobby_leave.connect(_on_lobby_leave)
	console = AdminConsole.new()
	console.game = self
	add_child(console)
	combat_view.word.connect(hud.word)
	# Gun words sit a little left of / above the muzzle so they don't cover the gun.
	viewmodel.word.connect(func(text: String, at: Vector2, style: String) -> void:
		hud.word(text, null, at + Vector2(-40, -50) / get_viewport().get_visible_rect().size, style))
	viewmodel.tossed.connect(func(id: String) -> void:
		combat_view.toss_gun(id, camera, player)
		sound.play("throw"))
	viewmodel.reload_caught.connect(func() -> void: sound.play("switch"))
	# Every button in the menus clicks (web: any <button>).
	_hook_buttons(menu)
	get_tree().node_added.connect(_hook_button) # buttons made later (menus rebuild their lists)

	if not map.trial.is_empty():
		trial = TimeTrial.new(map)
		trial_view = TrialView.new()
		add_child(trial_view)
		trial_view.setup(trial)
	_built = true
	var run := pending_run
	pending_run = {}
	match run.get("mode", ""):
		"solo", "practice":
			_start_play()
			_carry_in(run.get("carry", {}))
			if run.get("trial", "") != "" and trial:
				trial.enter(player, run.trial == "on")
				_handle_trial_events()
			LoadingScreen.finish()
		"online":
			_enter_menu()
			menu.show_screen("")
			if Net.instance and Net.instance.connected:
				net = Net.instance
				_connect_net()
				_waiting_run = true
				net.report_loaded(Net.map_checksum(map))
			else:
				LoadingScreen.finish()
				_enter_menu()
		_:
			LoadingScreen.finish()
			_enter_menu()
			if Net.instance and Net.instance.connected:
				net = Net.instance # back from something, still in a lobby
				_connect_net()
				_open_online_lobby()
			elif pending_hint != "":
				menu.show_screen("online")
				menu.set_online_status(pending_hint)
				pending_hint = ""
	_apply_args_state()


## One building step: with a loading screen up, show progress and let a frame draw.
func _step(frac: float, text: String) -> void:
	if LoadingScreen.is_up():
		LoadingScreen.progress(frac, text)
		await get_tree().process_frame


## Load `stage` behind the loading screen, then carry on with `run` (see pending_run).
func _load_into(kicker: String, stage: String, run: Dictionary) -> void:
	pending_run = run
	pending_run.stage = stage
	LoadingScreen.begin(get_tree(), kicker, stage, func() -> void:
		Settings.map = stage
		Settings.save_settings()
		get_tree().reload_current_scene())


# ---------- states ----------

func _enter_menu() -> void:
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.run.hide_results()
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
	combat.set_loadout(Settings.loadout())
	_last_move_t = -1.0 # a new PlayerSim starts its clock at 0
	combat.reset_targets()
	enemies.clear()
	enemy_view.clear()
	_respawn_t = -1.0
	_run_over = false
	_killer = ""
	combat_view.clear()
	hud.clear_floaters()
	if _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_in_game(true)
	if trial:
		trial.reset()
	_update_guns_mode()
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


## Practice on a map (free play with its dummies), behind the loading screen.
func _on_play(id: String) -> void:
	_load_into("PRACTICE", id, {"mode": "practice"})


## Straight onto a time trial from the menu (the course lives on the dev map).
func _on_play_trial(guns: bool) -> void:
	_load_into("TIME TRIAL", "dev_map", {"mode": "practice", "trial": "on" if guns else "off"})


## Guns are off on the "guns off" time trial; everything else has them.
func _update_guns_mode() -> void:
	var on := trial == null or not trial.active or trial.guns
	combat.enabled = on
	hud.set_online(online or not (trial and trial.active)) # health, feed, death screen
	hud.set_guns(on)
	viewmodel.visible = on and state != "menu"
	menu.map_name = ("TIME TRIAL · GUNS ON" if trial.guns else "TIME TRIAL · GUNS OFF") if trial and trial.active else map.name


## Time trial events: teleports snap the camera, plus the sound and comic-word feedback.
func _handle_trial_events() -> void:
	for e: Dictionary in trial.events:
		match e.type:
			"teleport":
				prev_pos = _player_pos()
				yaw = float(e.to.get("yaw", yaw))
				pitch = 0.0
				sound.play("teleport")
			"enter", "leave":
				_update_guns_mode()
			"start":
				sound.play("go")
				hud.word("GO!", null, Vector2(0.5, 0.32), "big")
			"finish":
				sound.play("finish")
				hud.word("NEW BEST!" if e.best else "FINISH!", null, Vector2(0.5, 0.3), "head" if e.best else "big")
			"fell":
				hud.word("WHOOPS!", null, Vector2(0.5, 0.3), "kill")
	trial.events.clear()


func _on_settings_changed(what: String) -> void:
	match what:
		"video", "audio":
			Settings.apply_display()
		"quality":
			Settings.apply_quality(get_viewport())
			viewmodel.set_msaa(Settings.QUALITY[Settings.quality].msaa)
		"lighting":
			_apply_lighting()


## The lighting preset, with the haze pushed out on big maps so the far side isn't washed out.
func _apply_lighting() -> void:
	Look.apply(Settings.lighting, env, sun, sky_mat, WorldView.cloud_material)
	env.fog_depth_begin *= map.view_scale
	env.fog_depth_end *= map.view_scale


func _notification(what: int) -> void:
	# Alt-tab / clicking another window opens the menu (solo: the game freezes; online it carries on).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _built and state == "playing" and _shot_path == "":
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
		elif a.begins_with("--name="):
			Settings.player_name = a.substr(7)
		elif a == "--ready":
			_auto_ready = true


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
		elif (a == "--host" or a.begins_with("--host=")) and not _net_args_done:
			_net_args_done = true
			Settings.host_port = int(a.substr(7)) if a.begins_with("--host=") else Settings.host_port
			_on_host(Settings.host_port)
		elif a.begins_with("--join=") and not _net_args_done:
			_net_args_done = true
			_on_join(a.substr(7))
		elif a == "--solo" and not _net_args_done:
			_net_args_done = true
			menu.open_lobby("solo")
			_on_lobby_ready(true)
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
		# HP number above the bar, so you can see exactly what each shot did.
		var hp := Label3D.new()
		hp.position.y = 0.17
		hp.pixel_size = 0.0055
		hp.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
		hp.font_size = 44
		hp.outline_size = 12
		hp.outline_modulate = Color("15151f")
		hp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.add_child(hp)
		node.add_child(bar)
		beans.append({"node": node, "mats": mats, "fill": bar.get_child(1), "hp_label": hp, "flash": 0.0, "shown_hp": -1,
			"fx": StatusFx.new(node, mats, 1.0)})


# ---------- input ----------

func _input(event: InputEvent) -> void:
	if not _built:
		return
	if event.is_action_pressed("console") and not event.is_echo():
		_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if console.is_open:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_toggle_console()
			get_viewport().set_input_as_handled()
		return # typing: the game ignores the keys
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
	if event.is_action_pressed("respawn") and not online: # online, the host decides where you are
		respawn_pressed = true
	if event.is_action_pressed("fire"):
		fire_pressed = true
	if event.is_action_pressed("reload"):
		reload_pressed = true
	if event.is_action_pressed("ability"):
		ability_pressed = true
	if event.is_action_pressed("interact"):
		interact_pressed = true
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
	if event.is_action_pressed("next_map") and not online:
		var maps := MapData.list()
		_on_play(maps[(maps.find(map_id) + 1) % maps.size()])


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
	if not _built:
		return
	if online:
		_online_tick()
		return
	if state != "playing":
		return # solo: menus freeze the game
	prev_pos = _player_pos()
	if respawn_pressed:
		respawn_pressed = false
		if trial and trial.active:
			trial.restart(player) # on the course, respawn = restart the run
		else:
			_respawn()
	var c := _sample()
	if player.dead or console.is_open:
		c = Cmd.new() # splatted, or typing in the console: stand still
		c.yaw = yaw
		c.pitch = pitch
	combat.tick(player, c, Cfg.TICK_DT) # before movement so knockback applies this tick
	player.step(c, map, Cfg.TICK_DT)
	if not (trial and trial.active):
		enemies.tick(player, Cfg.TICK_DT)
		_tick_health(Cfg.TICK_DT)
		if interact_pressed and not player.dead and not console.is_open:
			var chest := loot.chest_in_reach(player)
			if chest:
				loot.open(chest, player)
		loot.tick(player, enemies.deaths, Cfg.TICK_DT)
		if director:
			director.tick(player, Cfg.TICK_DT)
	interact_pressed = false
	if trial:
		trial.tick(player, Cfg.TICK_DT)
	if trial and not trial.events.is_empty():
		_handle_trial_events()
	if player.py < -30:
		_respawn()


## Solo health: spawn protection and regen while alive; back at the spawn a moment after dying
## (practice), or the run is over (a run).
func _tick_health(dt: float) -> void:
	if player.dead and director:
		if not _run_over:
			_run_over = true
			_respawn_t = 1.6 # a moment to see what got you
		_respawn_t -= dt
		if _respawn_t <= 0 and not hud.run.results_up():
			_show_results("RUN OVER", Color("ff6a5a"))
		return
	if player.dead:
		if _respawn_t < 0:
			_respawn_t = SOLO_RESPAWN
		_respawn_t -= dt
		if _respawn_t <= 0:
			_respawn_t = -1.0
			_respawn()
			player.hp = player.max_hp
			player.dead = false
			player.invuln = SOLO_PROTECTION
			_killer = ""
		return
	player.invuln = maxf(0.0, player.invuln - dt)
	player.regen_delay = maxf(0.0, player.regen_delay - dt)
	if player.regen_delay == 0 and player.hp < player.max_hp:
		player.hp = minf(player.max_hp, player.hp + Enemies.REGEN_RATE * dt)


func _respawn() -> void:
	player.respawn(map.spawn.x, map.spawn.y, map.spawn.z)
	yaw = map.spawn.yaw
	pitch = 0.0
	prev_pos = _player_pos()


func _player_pos() -> Vector3:
	return Vector3(player.px, player.py, player.pz)


# ---------- per frame ----------

func _process(delta: float) -> void:
	if not _built:
		return
	var dt := minf(delta, 0.1)
	if _waiting_run and net:
		var loaded := 0
		for m: Dictionary in net.lobby.values():
			if m.loaded:
				loaded += 1
		LoadingScreen.wait_for_players("Waiting for everyone to load (%d/%d)" % [loaded, net.lobby.size()])
	var cur := _player_pos()
	var speed := player.horizontal_speed()
	if state == "menu":
		# Slow orbit around the map behind the main menu.
		menu_time += dt
		var t := menu_time * 0.06
		camera.fov = Settings.fov
		camera.look_at_from_position(Vector3(sin(t) * 42, 20, cos(t) * 42), Vector3(0, 3, 0))
	else:
		var a := Engine.get_physics_interpolation_fraction() if state == "playing" or online else 1.0
		var pos := prev_pos.lerp(cur, a)
		# Camera effects ease toward targets so crouch/slide transitions aren't instant snaps.
		eye = _ease(eye, Cfg.PLAYER_CROUCH_EYE_HEIGHT if player.crouching else Cfg.PLAYER_EYE_HEIGHT, 14, dt)
		roll = _ease(roll, -0.05 if player.sliding else 0.0, 10, dt)
		var speed_t := clampf((speed - Cfg.MOVE_WALK_SPEED) / (Cfg.MOVE_MAX_SPEED - Cfg.MOVE_WALK_SPEED), 0, 1)
		camera.fov = _ease(camera.fov, Settings.fov + speed_t * 15, 6, dt)
		_visual_offset *= exp(-dt * 12)
		camera.position = pos + Vector3(0, eye, 0) + _visual_offset
		camera.rotation = Vector3(pitch, yaw, roll) # Godot's default Euler order is YXZ, same as the web game
		if combat_view.shake > 0 and state == "playing":
			var sh := combat_view.shake
			camera.position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * sh

	if online:
		_update_online(dt)
	else:
		_update_beans(cur if state != "menu" else camera.position, dt)
		enemy_view.update(enemies, camera, dt)
		_handle_enemy_events(enemies.events)
		enemies.events.clear()
		_update_loot(dt)
		_update_run(dt)
		if state != "menu":
			# in a run there's no respawn (-1: no timer), and the results replace the death screen
			hud.online.update(dt, player, yaw, -1.0 if director else maxf(0.0, _respawn_t), _killer, "")
			if hud.run.results_up():
				hud.online.hide_death()
			if player.dead:
				viewmodel.visible = false
			elif combat.enabled:
				viewmodel.visible = true
	clouds.rotation.y += dt * 0.004
	top_speed = maxf(top_speed, speed)
	hud.set_speed(speed, top_speed)

	var events := combat.fx
	combat.fx = []
	hud.on_events(events)
	viewmodel.on_events(events, combat)
	# Tracers start where the gun's barrel is drawn: a point in the world that lands on the same
	# pixel as the viewmodel's muzzle. 1.2 m out rather than right at the lens, so the beam isn't
	# fat where it leaves the gun.
	var muzzle := camera.project_position(viewmodel.muzzle_screen(), 1.2)
	combat_view.on_events(events, muzzle, player)
	for e in events:
		if e.type == "hit" and e.target < beans.size():
			beans[e.target].flash = 0.08
		elif e.type == "hit":
			enemy_view.flash(e.target)
	combat_view.update(dt if state == "playing" or online else 0.0, combat, _remote_proj.values())
	sound.listener = camera.global_position
	_play_combat_sounds(events)
	var live := state == "playing" or (online and state == "paused") # online never stops
	if live:
		_play_movement_sounds()
	if state != "menu":
		hud.update_combat(dt if live else 0.0, combat, camera)
		viewmodel.update(dt if live else 0.0, combat, player, yaw)
	if trial_view:
		trial_view.update(dt)
	hud.update_trial(trial)
	_update_debug(dt, speed)

	if _shot_path != "":
		_frame += 1
		if _frame == _shot_frames:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


# ---------- sounds (web main.js playCombatSounds / playMovementSounds) ----------

func _play_combat_sounds(events: Array[Dictionary]) -> void:
	for e in events:
		match e.type:
			"shot": sound.play(e.weapon, {"gap": 0.0})
			"hit":
				if e.kill:
					sound.play("kill", {"gap": 0.03})
				elif e.get("src", "gun") == "gun":
					sound.play("headshot" if e.zone == "head" else "hit", {"gap": 0.03})
				elif e.get("src") == "item":
					sound.play("hit", {"gap": 0.08, "vol": 0.5}) # burn/bleed ticks stay quiet
			"impact": sound.play("impact", {"pos": e.pos, "gap": 0.03})
			"explosion" when e.kind in ["bigbang", "orbital"]:
				sound.play("impact", {"pos": e.pos, "gap": 0.05}) # goes off on every hit: keep it small
			"explosion": sound.play("impulse" if e.kind == "impulse" else "explosion", {"pos": e.pos, "gap": 0.0})
			"zap": sound.play("impulse", {"pos": e.to, "gap": 0.1, "vol": 0.45})
			"freeze", "shatter": sound.play("dry" if e.type == "freeze" else "impact", {"pos": e.pos, "gap": 0.05})
			"item_proc": sound.play("reload", {"gap": 0.1, "vol": 0.6})
			"level_up": sound.play("finish")
			"orbital": sound.play("sniper", {"pos": e.pos, "gap": 0.0})
			"black_hole": sound.play("impulse", {"pos": e.pos, "gap": 0.1})
			"hydra": sound.play("rocket", {"gap": 0.05, "vol": 0.6})
			"revive": sound.play("teleport")
			"throw": sound.play("knifeThrow" if e.ability == "knife" else "throw")
			"dash":
				sound.play("wallJump")
				sound.play("slide", {"gap": 0.0})
				combat_view.shake = maxf(combat_view.shake, 0.02)
			"switch": sound.play("switch")
			# (reload sounds come from the gun toss animation: throw, then catch)


## Movement sounds come from the player's event log (jump, land, slide...).
func _play_movement_sounds() -> void:
	for e: Dictionary in player.events:
		if e.t <= _last_move_t:
			continue
		_last_move_t = e.t
		var n: String = e.name
		if n == "wall jump":
			sound.play("wallJump")
		elif n.ends_with("jump"):
			sound.play("jump")
		elif n == "land":
			var air := String(e.detail).get_slice("after ", 1).to_float()
			if air > 0.15:
				var k := minf(1.0, air / 1.2)
				sound.play("land", {"vol": (0.2 + 0.3 * k) / 0.5}) # baked at full strength
		elif n == "slide" or n == "land slide":
			sound.play("slide")
		elif n == "jump pad":
			sound.play("pad")


func _hook_buttons(n: Node) -> void:
	_hook_button(n)
	for c in n.get_children():
		_hook_buttons(c)


func _hook_button(n: Node) -> void:
	if n is BaseButton and not n.has_meta("clicks"):
		n.set_meta("clicks", true)
		(n as BaseButton).pressed.connect(func() -> void: sound.play("ui", {"gap": 0.05}))


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
		(b.fx as StatusFx).update(t.status, dt, combat_view.particles, t.pos)
		node.rotation.y = atan2(look_at_pos.x - t.pos.x, look_at_pos.z - t.pos.z) # dummies turn to face you
		var frac := t.hp / t.max_hp
		var fill: MeshInstance3D = b.fill
		fill.scale.x = maxf(0.001, frac)
		fill.position.x = -0.4 * (1 - frac)
		(fill.material_override as StandardMaterial3D).albedo_color = \
			Color("5ee06a") if frac > 0.5 else Color("f2c14e") if frac > 0.25 else Color("e5534b")
		var hp_now := ceili(t.hp)
		if hp_now != b.shown_hp:
			b.shown_hp = hp_now
			(b.hp_label as Label3D).text = "%d / %d" % [hp_now, roundi(t.max_hp)]
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
	lines.append("weapon     %s  %d/%d%s   ability %.1f" % [combat.weapon().name, st.ammo, combat.mag_size(),
		"  reloading" if st.reload_t > 0 else "", combat.ability_cd])
	lines.append("")
	for e: Dictionary in player.events.slice(-6):
		lines.append("%6.2f  %s  %s" % [e.t, e.name, e.detail])
	hud.set_debug("\n".join(lines))


# ---------- multiplayer ----------

func _connect_net() -> void:
	if not net.joined.is_connected(_on_net_joined):
		net.joined.connect(_on_net_joined)
		net.failed.connect(_on_net_failed)
		net.left.connect(_on_net_left)
		net.lobby_changed.connect(_refresh_lobby)
		net.load_stage.connect(_on_load_stage)
		net.run_started.connect(_on_run_started)


## Open a lobby that friends can join.
func _on_host(port: int) -> void:
	net = Net.get_instance(get_tree())
	_connect_net()
	var err := net.host(port, Settings.player_name, Settings.character)
	if err != OK:
		menu.set_online_status("Couldn't host on port %d (%s). Is another game already running on it?" % [port, error_string(err)])


func _on_join(address: String) -> void:
	if Net.parse_address(address).is_empty():
		menu.set_online_status("Type the address your friend sent you first (like abc.gl.at.ply.gg:12345).")
		return
	net = Net.get_instance(get_tree())
	_connect_net()
	var err := net.join(address, Settings.player_name, Settings.character)
	if err != OK:
		menu.set_online_status("Couldn't start connecting (%s)." % error_string(err))
	else:
		menu.set_online_status("Connecting to %s..." % address, true)


func _on_cancel_online() -> void:
	if net and not online:
		net.leave()


func _on_net_joined(w: Dictionary) -> void:
	menu.set_online_status("")
	_open_online_lobby()
	if w.get("phase", "lobby") != "lobby":
		menu.lobby.set_status("Joining the run in progress...")


func _open_online_lobby() -> void:
	var note := ""
	if net.is_host():
		var ips := PackedStringArray()
		for ip in IP.get_local_addresses():
			if ip.begins_with("192.168.") or ip.begins_with("10."):
				ips.append("%s:%d" % [ip, Settings.host_port])
		note = "Friends join with your playit.gg address (UDP tunnel to port %d)%s." % [Settings.host_port,
			(", or on your Wi-Fi: " + " / ".join(ips)) if not ips.is_empty() else ""]
	menu.open_lobby("host" if net.is_host() else "client", note)
	_refresh_lobby()
	if _auto_ready:
		menu.lobby.set_ready(true)
		net.set_me(Settings.character, true)


## The lobby list and countdown, from the host's copy.
func _refresh_lobby() -> void:
	if net == null or menu.screen != "lobby" or menu.lobby_mode == "solo":
		return
	var rows := []
	var ready_count := 0
	for id: int in net.lobby:
		var m: Dictionary = net.lobby[id]
		if m.is_empty():
			continue
		rows.append({"name": m.name, "character": m.character, "ready": m.ready, "you": id == net.my_id})
		if m.ready:
			ready_count += 1
	menu.lobby.set_players(rows)
	if net.countdown >= 0:
		menu.lobby.set_status("Starting in %d..." % ceili(net.countdown))
	elif net.phase == "loading" or net.phase == "run":
		menu.lobby.set_status("Joining the run in progress...")
	else:
		menu.lobby.set_status("Waiting for everyone to ready up (%d/%d)" % [ready_count, rows.size()])


func _on_lobby_character(id: String) -> void:
	if menu.lobby_mode != "solo" and net:
		net.set_me(id, menu.lobby.ready_on)


func _on_lobby_ready(on: bool) -> void:
	if menu.lobby_mode == "solo":
		if on:
			_load_into("STAGE 1", Characters.FIRST_STAGE, {"mode": "solo"})
	elif net:
		net.set_me(Settings.character, on)


func _on_lobby_leave() -> void:
	if menu.lobby_mode == "solo":
		menu.show_screen("main")
	else:
		if net:
			net.leave()
		menu.show_screen("online")


## Everyone was ready: load the stage behind the loading screen, then tell the host we're in.
func _on_load_stage(stage: String) -> void:
	_load_into("STAGE 1", stage, {"mode": "online"})


## Everyone has loaded: the run starts.
func _on_run_started(start: Dictionary) -> void:
	if not _built:
		return
	_waiting_run = false
	_start_online(start)
	LoadingScreen.finish()


func _on_net_failed(reason: String) -> void:
	LoadingScreen.finish()
	if menu.screen == "lobby" or state != "menu":
		_leave_match(reason)
		return
	menu.set_online_status(reason)


func _on_net_left(reason: String) -> void:
	_leave_match(reason)


## Back to the menu from a match (reloads the scene so everything solo starts fresh).
func _leave_match(reason: String) -> void:
	online = false
	_waiting_run = false
	if net:
		net.leave()
	pending_hint = reason
	pending_run = {}
	LoadingScreen.finish()
	get_tree().reload_current_scene()


func _start_online(w: Dictionary) -> void:
	online = true
	menu.online = true
	combat = Combat.new(map.boxes, []) # no dummies online: other players are the targets
	combat.grid = map
	for b: Dictionary in beans:
		(b.node as Node3D).visible = false
	_start_play()
	var sp: Dictionary = w.spawn
	player.respawn(sp.x, sp.y, sp.z)
	player.log_impulses = true
	yaw = sp.yaw
	prev_pos = _player_pos()
	_history.clear()
	_visual_offset = Vector3.ZERO
	if trial:
		trial.reset()
	hud.set_online(true)
	menu.map_name = "ONLINE · " + map.name
	menu.set_online_status("")


## One sim tick online: predict our own movement and gun, send the input.
func _online_tick() -> void:
	if net == null or not net.connected:
		return
	if net.me_fresh:
		_reconcile()
	prev_pos = _player_pos()
	var c: Cmd
	if state == "playing" and not player.dead:
		c = _sample()
	else:
		# In the menu or splatted: stand still (the match doesn't stop, and the host still needs
		# an input every tick to keep us in step).
		_sample() # swallow presses
		c = Cmd.new()
		c.yaw = yaw
		c.pitch = pitch
	player.impulse_log = []
	combat.tick(player, c, Cfg.TICK_DT) # before movement so knockback applies this tick
	if not player.dead:
		player.step(c, map, Cfg.TICK_DT)
	var seq := net.queue_cmd(c)
	_history.append([seq, c, player.impulse_log])
	if _history.size() > 360:
		_history.pop_front()


## The host sent our real state as of input #seq. Rewind to it and replay every newer input (and
## our own predicted knockback), so we stay responsive but always end up on the host's truth,
## including knocks from other players' explosions. Any visible jump is eased out.
func _reconcile() -> void:
	net.me_fresh = false
	var me := net.me
	var st: PackedFloat64Array = me.state
	if st.size() != PlayerSim.STATE_SIZE:
		return
	var acked: int = me.seq
	_history = _history.filter(func(h: Array) -> bool: return h[0] > acked)
	var before := _player_pos()
	var was_dead := player.dead
	player.load_state(st)
	player.quiet = true
	player.log_impulses = false
	for h: Array in _history:
		for imp: Array in h[2]:
			player.apply_impulse(imp[0], imp[1], imp[2])
		if not player.dead:
			player.step(h[1], map, Cfg.TICK_DT)
	player.quiet = false
	player.log_impulses = true
	var d := before - _player_pos()
	if d.length() < 3:
		_visual_offset += d
	else:
		_visual_offset = Vector3.ZERO # respawn / big correction: just go there
	prev_pos -= d
	if was_dead and not player.dead:
		combat.set_loadout(Settings.loadout()) # the host gave us fresh ammo on respawn


## Once per frame online: other players, their projectiles, the host's events, the online HUD.
func _update_online(dt: float) -> void:
	if net == null:
		return
	var samples := {}
	var targets: Array[Combat.Target] = []
	for id: int in net.remotes:
		var s: Variant = net.sample(net.remotes[id])
		if s == null:
			continue
		samples[id] = s
		var t: Combat.Target = _remote_targets.get(id)
		if t == null:
			t = Combat.Target.new()
			t.id = id
			t.kind = "remote"
			_remote_targets[id] = t
		t.pos = Vector3(s.x, s.y, s.z)
		t.dead = int(s.flags) & NetCodec.F_DEAD != 0
		targets.append(t)
	for id: int in _remote_targets.keys():
		if not samples.has(id):
			_remote_targets.erase(id)
	combat.targets = targets
	remote_view.update(samples, net.roster, dt)
	_sync_remote_projectiles(dt)
	_handle_net_events(net.take_events())

	var badge := "HOSTING" if net.is_host() else "ONLINE"
	var count := net.remotes.size() + 1
	badge += " · %d PLAYER%s" % [count, "" if count == 1 else "S"]
	if not net.is_host():
		badge += " · %d MS" % roundi(net.ping)
	hud.online.update(dt, player, yaw, float(net.me.get("respawn_in", 0.0)), _killer, badge)
	viewmodel.visible = state != "menu" and not player.dead # no gun while splatted
	var rows := []
	for p: Dictionary in net.players:
		var info: Dictionary = net.roster.get(p.id, {"name": "Bean", "color": Color.WHITE})
		rows.append({"name": info.name, "kills": p.kills, "deaths": p.deaths, "color": info.color, "you": p.id == net.my_id})
	hud.online.scoreboard(state == "playing" and Input.is_action_pressed("scoreboard"), rows)


## Other players' rockets, grenades and knives: jump to each snapshot, fly on between them.
func _sync_remote_projectiles(dt: float) -> void:
	if net.proj_fresh:
		net.proj_fresh = false
		var seen := {}
		for s: Dictionary in net.proj:
			if s.owner == net.my_id:
				continue # ours are simulated locally
			var key := "%d:%d" % [s.owner, s.id]
			seen[key] = true
			var pr: Combat.Projectile = _remote_proj.get(key)
			if pr == null:
				pr = Combat.Projectile.new()
				pr.kind = s.kind
				var item: Dictionary = Items.WEAPONS.get(s.kind, Items.ABILITIES.get(s.kind, {}))
				pr.def = item.get("projectile", {})
				_remote_proj[key] = pr
			pr.pos = s.pos
			pr.vel = s.vel
			pr.stuck = s.stuck
		for key: String in _remote_proj.keys():
			if not seen.has(key):
				_remote_proj.erase(key)
	else:
		for pr: Combat.Projectile in _remote_proj.values():
			if not pr.stuck:
				pr.vel.y -= float(pr.def.get("gravity", 0.0)) * dt
				pr.pos += pr.vel * dt


## Gameplay events from the host. Our own shots and explosions already showed (we predicted
## them), so from us only the confirmed hits count. Everyone else's effects show in a lighter form.
func _handle_net_events(evs: Array) -> void:
	var me := net.my_id
	for e: Dictionary in evs:
		match e.type:
			"kill":
				var killer := _player_name(e.killer)
				var victim := _player_name(e.victim)
				if e.killer == me:
					hud.online.feed([["YOU", UiStyle.YELLOW], ["SPLATTED", Color("ff4a4a")], [victim, Color.WHITE]], "mine")
				elif e.victim == me:
					_killer = killer
					hud.online.feed([[killer, Color.WHITE], ["SPLATTED", Color("ff4a4a")], ["YOU", UiStyle.YELLOW]], "died")
					sound.play("death")
				else:
					hud.online.feed([[killer, Color.WHITE], ["SPLATTED", Color("ff4a4a")], [victim, Color.WHITE]])
			"join", "leave":
				if e.id != me:
					hud.online.feed([[str(e.name), Color.WHITE], ["joined" if e.type == "join" else "left", UiStyle.MUTED]])
			"respawn":
				if e.id == me:
					yaw = float(e.yaw)
					pitch = 0.0
					_killer = ""
			"hit":
				if e.target == me:
					var shooter: Combat.Target = _remote_targets.get(e.by)
					hud.online.hurt(e.dmg, shooter.pos if shooter else null)
					sound.play("hurt", {"gap": 0.06})
					combat_view.shake = maxf(combat_view.shake, 0.03)
				elif e.by == me:
					# Our hit, confirmed by the host: hitmarker, damage number, splat, sound.
					var local: Array[Dictionary] = [e]
					hud.on_events(local)
					combat_view.on_events(local, e.pos, player)
					_play_combat_sounds(local)
					remote_view.flash(e.target)
				else:
					var quiet: Array[Dictionary] = [e.merged({"quiet": true})]
					combat_view.on_events(quiet, e.pos, player)
					remote_view.flash(e.target)
			_:
				if e.get("by", 0) == me:
					continue # our own shots / impacts / explosions were predicted locally
				match e.type:
					"shot":
						var gun := remote_view.muzzle(e.by, e.origin)
						combat_view.remote_shot(e, gun)
						sound.play(e.weapon, {"pos": gun, "gap": 0.0})
					"impact", "explosion":
						var one: Array[Dictionary] = [e]
						combat_view.on_events(one, e.pos, player)
						_play_combat_sounds(one)
					"throw":
						var t: Combat.Target = _remote_targets.get(e.by)
						if t:
							sound.play("knifeThrow" if e.ability == "knife" else "throw", {"pos": t.pos})


func _player_name(id: int) -> String:
	return str(net.roster.get(id, {}).get("name", "Someone"))


# ---------- enemies + admin console ----------

## Sounds and effects for what the enemies did this frame (EnemyView draws the rest).
func _handle_enemy_events(evs: Array[Dictionary]) -> void:
	if evs.is_empty():
		return
	enemy_view.on_events(evs)
	for e in evs:
		match e.type:
			"hurt":
				hud.online.hurt(e.dmg, e.from)
				sound.play("hurt", {"gap": 0.06})
				combat_view.shake = maxf(combat_view.shake, 0.03)
			"player_died":
				_killer = str(e.by)
				sound.play("death")
			"blocked":
				hud.word("BLOCKED!", null, Vector2(0.5, 0.62), "small")
				sound.play("switch", {"gap": 0.05})
			"windup":
				sound.play("dry", {"pos": e.pos, "gap": 0.05}) # the click you learn to listen for
			"enemy_shot":
				sound.play("smg" if e.enemy == "gunner" else "pistol", {"pos": e.pos, "gap": 0.0})
			"lob":
				sound.play("throw", {"pos": e.pos})
			"snipe":
				sound.play("sniper", {"pos": e.from, "gap": 0.0})
				combat_view.tracer(e.from, e.to)
			"enemy_explosion":
				var one: Array[Dictionary] = [{"type": "explosion", "pos": e.pos, "radius": e.radius, "kind": "frag"}]
				combat_view.on_events(one, e.pos, player)
				sound.play("explosion", {"pos": e.pos, "gap": 0.0})
			"enemy_impact":
				combat_view.add_star(e.pos, 0.3, 0.08, Color("bfe6ff"))
			"slam":
				sound.play("explosion", {"pos": e.pos, "gap": 0.0})
				combat_view.shake = maxf(combat_view.shake, 0.05)
			"dash":
				sound.play("wallJump", {"pos": _enemy_pos(e.id)})
			"bite":
				sound.play("hit", {"pos": _enemy_pos(e.id), "gap": 0.05})
			"beam_on":
				sound.play("impulse", {"pos": _enemy_pos(e.id)})


## The waves: the HUD, banners and sounds for what the director did, and off to the next stage.
func _update_run(dt: float) -> void:
	hud.run.update(dt, director if state != "menu" else null, enemies)
	var marked: Array[Enemies.Enemy] = []
	if director and state == "playing":
		marked = director.marked()
	hud.run.markers.update(dt, camera, marked, director.boss if director else null)
	if director == null:
		return
	for e in director.events:
		match e.type:
			"wave_start":
				hud.run.banner("WAVE %d" % e.wave, "%d enemies incoming" % e.count, Color.WHITE)
				sound.play("go")
			"wave_clear":
				if e.wave < Director.WAVES:
					hud.run.banner("WAVE %d CLEARED" % e.wave, "here's something for it", UiStyle.YELLOW, 1.8)
				# every cleared wave pays an item, better the later the wave (Loot.WAVE_ODDS); it
				# pops out a few meters in front of you
				var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
				loot.drop_item(_player_pos() + fwd * 3.0, loot.roll_wave_item(e.wave), player)
			"boss_warn":
				hud.run.banner("BOSS INCOMING", "", Color("ff6a5a"), 3.5)
				sound.play("teleport")
			"boss":
				hud.run.banner(String(e.name).to_upper(), "stage %d boss" % director.stage, Color("ff6a5a"))
				sound.play("explosion", {"pos": e.pos})
				combat_view.shake = maxf(combat_view.shake, 0.08)
			"stage_clear":
				hud.run.banner("STAGE CLEARED", "grab your loot: the next stage is coming", Color("ffd84a"), 4.0)
				sound.play("finish")
				# the boss's reward: a rare, sometimes a legendary
				var rarity := "legendary" if randf() < 0.35 else "rare"
				loot.drop_item(e.pos, combat.up.random_of(rarity), player)
			"next_stage":
				_next_stage()
	director.events.clear()


## Everything a run takes to the next stage (and the results screen adds up).
func _carry_out() -> Dictionary:
	var before: Dictionary = run_info.get("carry", {})
	return {"items": combat.up.stacks.duplicate(), "level": combat.up.level, "xp": combat.up.xp, "gold": loot.gold,
		"kills": int(before.get("kills", 0)) + (director.kills if director else 0),
		"time": float(before.get("time", 0.0)) + (director.time if director else 0.0)}


## A new stage of the same run: your items, level and gold come along.
func _carry_in(carry: Dictionary) -> void:
	if carry.is_empty():
		return
	for id: String in carry.get("items", {}):
		combat.up.add(id, int(carry.items[id]))
	combat.up.level = int(carry.get("level", 1))
	combat.up.xp = float(carry.get("xp", 0.0))
	combat.up.active = combat.up.total > 0 or combat.up.level > 1
	loot.gold = int(carry.get("gold", 0))
	combat.up.tick(player, 0.0) # max health from items and levels, before anything happens
	player.hp = player.max_hp


func _next_stage() -> void:
	var n := int(run_info.get("stage_n", 1)) + 1
	_load_into("STAGE %d" % n, Characters.stage_map(n), {"mode": "solo", "stage_n": n, "carry": _carry_out()})


## The results screen (the run's over): what you did, and the way out.
func _show_results(title: String, color: Color) -> void:
	var c := _carry_out()
	var secs := int(c.time)
	hud.run.show_results(title, color, [
		["Character", Characters.get_info(Settings.character).name],
		["Stage", "%d (wave %d)" % [director.stage, director.wave]],
		["Time", "%d:%02d" % [secs / 60, secs % 60]],
		["Kills", c.kills],
		["Level", combat.up.level],
		["Items", combat.up.total],
		["Gold", loot.gold],
	])
	state = "over"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	viewmodel.visible = false


## Chests, dropped items, gold and the "open chest" prompt.
func _update_loot(dt: float) -> void:
	loot_view.update(loot, camera, dt)
	loot_view.on_events(loot.events)
	for e in loot.events:
		match e.type:
			"gold":
				hud.items.gold_added(e.amount)
				sound.play("coin", {"gap": 0.05, "vol": 0.6})
			"chest_open":
				sound.play("chest", {"pos": e.pos})
				if e.rarity == "legendary":
					hud.word("LEGENDARY!!", e.pos + Vector3(0, 2.2, 0), null, "big")
					sound.play("finish")
				elif e.rarity == "rare":
					hud.word("RARE!", e.pos + Vector3(0, 2.2, 0), null, "kill")
			"barrel":
				hud.items.gold_added(e.amount)
				sound.play("impact", {"pos": e.pos})
				sound.play("coin", {"gap": 0.0, "vol": 0.6})
				hud.word("CRUNCH!", e.pos + Vector3(0, 1.2, 0), null, "small")
			"shrine_fail":
				sound.play("deny", {"gap": 0.1})
				hud.word("NOTHING...", e.pos + Vector3(0, 2.6, 0), null, "small")
			"pickup":
				hud.items.pickup(e.item, e.count)
				sound.play("pickup")
			"deny":
				sound.play("deny", {"gap": 0.2})
	loot.events.clear()
	var in_run := state != "menu" and not (trial and trial.active)
	hud.items.set_gold(loot.gold if in_run and (not map.chests.is_empty() or loot.gold > 0) else -1)
	var up := combat.up
	hud.items.set_level(up.level if in_run else 0, up.xp / Upgrades.xp_to_next(up.level))
	var chest := loot.chest_in_reach(player) if in_run and not player.dead else null
	if chest:
		var key := Settings.bind_label(Settings.binds.get("interact", ""))
		var price := "   $%d" % chest.cost if chest.cost > 0 else ""
		hud.items.set_prompt("%s   %s%s" % [key, Loot.action(chest), price], loot.gold >= chest.cost)
	else:
		hud.items.set_prompt("")


func _enemy_pos(id: int) -> Vector3:
	for e in enemies.list:
		if e.id == id:
			return e.center()
	return camera.global_position


func _toggle_console() -> void:
	console.toggle()
	if console.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif state == "playing" and _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The admin console's commands (AdminConsole parses, this does). Returns what to print.
func admin(what: String, data: Dictionary) -> String:
	if state == "menu" or online:
		return "Start a solo game first (Singleplayer or Practice)."
	match what:
		"spawn":
			var type: String = data.type
			var n: int = data.count
			var def: Dictionary = Enemies.TYPES[type]
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var side := Vector3(fwd.z, 0, -fwd.x)
			for i in n:
				var off := side * (i - (n - 1) / 2.0) * 1.6
				var at := Vector3(player.px, player.py, player.pz) + fwd * 12.0 + off
				var g := enemies._ground_under(at + Vector3(0, 3, 0)) # the ground about your level
				at.y = g if g > -30 else player.py
				var fits := enemies._body_fits(at, def.size)
				if def.family == "flyer":
					at.y += 4.0
					fits = enemies._push_out(at, 0.5 * def.size).distance_to(at) < 0.01
				if not fits: # in a wall, a rock, a tree: the nearest spot it fits instead
					at = enemies.safe_spot(at - Vector3(0, 4.0 if def.family == "flyer" else 0.0, 0), 0.0, 4.0, type)
					if at == Vector3.INF:
						at = enemies.safe_spot(Vector3(player.px, player.py, player.pz), 3.0, 14.0, type)
					if at == Vector3.INF:
						continue
				var e := enemies.spawn(type, at)
				e.yaw = yaw + PI # facing you
			return "Spawned %d %s%s" % [n, def.name, "s" if n > 1 else ""]
		"killall":
			var k := enemies.list.size()
			enemies.clear()
			return "Removed %d enem%s" % [k, "y" if k == 1 else "ies"]
		"god":
			var on: String = data.on
			enemies.god = (not enemies.god) if on == "toggle" else on in ["on", "1", "true"]
			return "God mode %s" % ("ON: nothing can hurt you" if enemies.god else "off")
		"heal":
			player.hp = player.max_hp
			return "Healed"
		"freeze":
			var f: String = data.get("on", "toggle")
			enemies.frozen = (not enemies.frozen) if f == "toggle" else f in ["on", "1", "true"]
			return "Enemies %s" % ("frozen" if enemies.frozen else "moving again")
		"give":
			var n: int = data.count
			var id: String = data.id
			if id == "random":
				var got := PackedStringArray()
				for i in n:
					var r := combat.up.random_id()
					combat.up.add(r)
					got.append(Upgrades.LIST[r].name)
					hud.items.pickup(r, combat.up.count(r))
				return "Got " + ", ".join(got)
			combat.up.add(id, n)
			var it: Dictionary = Upgrades.LIST[id]
			if n > 0:
				hud.items.pickup(id, combat.up.count(id))
				return "Got %d %s (now %d)" % [n, it.name, combat.up.count(id)]
			return "Dropped %s (now %d)" % [it.name, combat.up.count(id)]
		"items":
			if data.all:
				var lines := PackedStringArray()
				for rarity: String in ["common", "uncommon", "rare", "legendary"]:
					var names := PackedStringArray()
					for id: String in Upgrades.LIST:
						if Upgrades.LIST[id].rarity == rarity:
							names.append(String(Upgrades.LIST[id].name).to_lower())
					lines.append("%s: %s" % [rarity, ", ".join(names)])
				return "\n".join(lines)
			if combat.up.total == 0:
				return "No items yet (give <item>, give random 5, items all)"
			var have := PackedStringArray()
			for id: String in combat.up.stacks:
				have.append("%s x%d" % [Upgrades.LIST[id].name, combat.up.count(id)])
			return ", ".join(have)
		"wave", "boss", "nextstage":
			if director == null:
				return "Not in a run (Singleplayer)"
			match what:
				"wave":
					director.skip_to(int(data.n))
					enemies.clear()
					return "Wave %d next" % int(data.n)
				"boss":
					director.skip_to_boss()
					enemies.clear()
					return "The boss is coming"
			_next_stage()
			return "On to the next stage"
		"levelup":
			for i in int(data.n):
				combat.up.add_xp(Upgrades.xp_to_next(combat.up.level) - combat.up.xp, player)
			return "Level %d" % combat.up.level
		"gold":
			loot.gold = maxi(0, loot.gold + int(data.amount))
			return "Gold: $%d" % loot.gold
		"chest":
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var at := Vector3(player.px, player.py, player.pz) + fwd * 2.2 # right in reach
			var g := enemies._ground_under(at + Vector3(0, 3, 0))
			at.y = g if g > -30 else player.py
			if data.size != "shop" or not loot._place_shop(at, yaw + PI): # a shop: all three terminals
				loot.add_chest(at, data.size, yaw + PI) # front facing you
			return "A %s appeared ($%d)" % [String(Loot.CHESTS[data.size].name).to_lower(), Loot.CHESTS[data.size].cost]
		"clearitems":
			var had := combat.up.total
			combat.up.clear()
			return "Dropped %d item%s" % [had, "" if had == 1 else "s"]
	return "?"
