extends SceneTree
## Clicks through the menus headless and checks each step: main screen, practice (through the
## loading screen), pause / settings / rebinding, the solo lobby (character select + ready starts a
## run on the first stage with that character's kit) and the multiplayer screen.
##   godot --headless --path . --script res://tests/menu_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)


func frames(n := 3) -> void:
	for i in n:
		await process_frame


## Wait for the scene to reload into a built game that's playing (or time out). Returns it.
func wait_playing(old: Node, secs := 10.0) -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		await process_frame
		var c := current_scene
		if c and c != old and c.get("_built") and c.state == "playing":
			return c
	return current_scene


## Find a button by its text under a node.
func button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := button(c, text)
		if b:
			return b
	return null


func _init() -> void:
	Settings.path = "user://settings_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.load_settings()
	Settings.map = "dev_map"
	change_scene_to_file("res://scenes/main.tscn")
	await frames(5)
	var game := current_scene
	var menu: Menu = game.menu

	check("starts in the main menu", game.state == "menu" and menu.screen == "main")
	for t in ["SINGLEPLAYER", "MULTIPLAYER", "PRACTICE", "SETTINGS", "QUIT"]:
		if button(menu._screens.main, t) == null:
			check("main menu has %s" % t, false)
	check("main menu has singleplayer, multiplayer, practice, settings and quit",
		["SINGLEPLAYER", "MULTIPLAYER", "PRACTICE", "SETTINGS", "QUIT"].all(func(t: String) -> bool: return button(menu._screens.main, t) != null))

	# practice: the map screen, then through the loading screen into free play
	button(menu._screens.main, "PRACTICE").pressed.emit()
	await frames()
	check("PRACTICE opens the practice map screen", menu.screen == "maps")
	check("practice has the Dev Arena and both time trials", menu._map_grid.get_child_count() == 1
		and menu._trial_grid.get_child_count() == 2)
	key(KEY_ESCAPE)
	await frames()
	check("Esc on the practice screen goes back", menu.screen == "main")
	menu.play.emit("dev_map")
	await frames(2)
	check("playing shows the loading screen", LoadingScreen.is_up())
	game = await wait_playing(game)
	menu = game.menu
	check("...then the game starts on that map", game.state == "playing" and game.map_id == "dev_map" and menu.screen == "")
	await create_timer(2.0).timeout
	check("the loading screen goes away", LoadingScreen.instance == null)

	key(KEY_ESCAPE)
	await frames()
	check("Esc pauses", game.state == "paused" and menu.screen == "pause")
	menu.open_settings("pause")
	await frames()
	check("pause -> settings", menu.screen == "settings")
	key(KEY_ESCAPE)
	await frames()
	check("Esc in settings goes back to pause", menu.screen == "pause" and game.state == "paused")
	key(KEY_ESCAPE)
	await frames()
	check("Esc in pause resumes", game.state == "playing" and menu.screen == "")

	# rebinding: jump -> J, then J onto slide swaps them
	key(KEY_ESCAPE)
	await frames()
	menu._settings_tab = "controls"
	menu.open_settings("pause")
	await frames()
	menu.listening = "jump"
	key(KEY_J)
	await frames()
	var ev: InputEvent = InputMap.action_get_events("jump")[0]
	check("rebind jump to J", Settings.binds.jump == "key:%d" % KEY_J and ev is InputEventKey and ev.physical_keycode == KEY_J)
	var slide_before: String = Settings.binds.slide
	menu.listening = "slide"
	key(KEY_J)
	await frames()
	check("binding a used key swaps the two", Settings.binds.slide == "key:%d" % KEY_J and Settings.binds.jump == slide_before)
	menu.listening = "jump"
	key(KEY_ESCAPE)
	await frames()
	check("Esc cancels a rebind", Settings.binds.jump == slide_before and menu.listening == "" and menu.screen == "settings")
	var cf := ConfigFile.new()
	check("binds are saved", cf.load(Settings.path) == OK and cf.get_value("binds", "slide", "") == "key:%d" % KEY_J)
	Settings.reset_binds()
	Settings.apply_input()

	# the admin console (F10)
	key(KEY_ESCAPE) # resume from the settings/pause stack first
	await frames()
	if game.state != "playing":
		menu.resume.emit()
		await frames()
	key(KEY_F10)
	await frames()
	check("F10 opens the admin console", game.console.is_open)
	var out: String = game.console.execute("spawn flyer beam")
	await frames()
	check("'spawn flyer beam' spawns one (%s)" % out, game.enemies.list.size() == 1 and game.enemies.list[0].type == "flyer_beam")
	game.console.execute("spawn swarmer 3")
	check("'spawn swarmer 3' spawns three more", game.enemies.list.size() == 4)
	var px: float = game.player.px
	var pz: float = game.player.pz
	Input.action_press("forward")
	await physics_frame
	await physics_frame
	Input.action_release("forward")
	check("typing in the console doesn't move you", game.player.px == px and game.player.pz == pz
		and game.player.horizontal_speed() < 0.01)
	game.console.execute("god")
	check("'god' turns on god mode", game.enemies.god)
	game.console.execute("freeze")
	check("'freeze' freezes them", game.enemies.frozen)
	game.console.execute("unfreeze")
	check("'unfreeze' lets them move again", not game.enemies.frozen)
	game.console.execute("freeze on")
	game.console.execute("freeze off")
	check("'freeze on' / 'freeze off' work too", not game.enemies.frozen)
	game.console.execute("killall")
	check("'killall' removes them all", game.enemies.list.is_empty())

	# a beam flyer that dies mid-beam takes its beam with it
	game.player.invuln = 0.0
	var fwd := Vector3(-sin(game.yaw), 0, -cos(game.yaw))
	var beamer: Enemies.Enemy = game.enemies.spawn("flyer_beam", Vector3(game.player.px, game.player.py + 3.0, game.player.pz) + fwd * 5.0)
	beamer.cd = 0.0
	var t0 := Time.get_ticks_msec()
	while beamer.state != "attack" and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await frames(2)
	var beam_mesh: Node3D = game.enemy_view._views.get(beamer.id, {}).get("beam")
	check("the beam flyer beams you (state %s)" % beamer.state, beamer.state == "attack" and beam_mesh != null and beam_mesh.visible)
	beamer.target.hp = 0.0 # dies mid-beam
	await frames(4)
	check("when it dies, the beam goes with it", game.enemies.list.is_empty() and not is_instance_valid(beam_mesh)
		and game.enemy_view.get_child_count() == 0)
	game.console.execute("god off")
	check("'god off' turns god mode off", not game.enemies.god)

	# shooters firing: every shot has exactly one mesh, and they go away when the shots do
	game.console.execute("god on")
	for t in ["lobber", "gunner", "flyer projectile"]:
		game.console.execute("spawn " + t)
	var most_meshes := 0
	var most_shots := 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
		most_meshes = maxi(most_meshes, game.enemy_view._proj.size())
		most_shots = maxi(most_shots, game.enemies.projectiles.size())
	game.console.execute("killall")
	await frames(3)
	# (the old bug keyed meshes on the shot Dictionary, whose hash changes as it flies: a new mesh
	# every frame, piling up, and an error when cleaning up)
	check("enemy shots get one mesh each, no pile-up (most meshes %d, most shots %d), all gone after" % [most_meshes, most_shots],
		most_meshes > 0 and most_meshes <= most_shots + 2 and game.enemy_view._proj.is_empty())
	game.console.execute("god off")

	# the buttons next to the text bar do the same, without typing
	button(game.console._panel, "BEAM").pressed.emit()
	await frames()
	check("the BEAM button spawns a beam flyer", game.enemies.list.size() == 1 and game.enemies.list[0].type == "flyer_beam")
	button(game.console._panel, "x3").pressed.emit()
	button(game.console._panel, "SWARMER").pressed.emit()
	await frames()
	check("x3 then SWARMER spawns three swarmers", game.enemies.list.filter(func(e: Enemies.Enemy) -> bool: return e.type == "swarmer").size() == 3)
	button(game.console._panel, "GOD").pressed.emit()
	check("the GOD button toggles god mode (and shows it)", game.enemies.god and game.console._god_btn.button_pressed)
	button(game.console._panel, "FREEZE").pressed.emit()
	button(game.console._panel, "FREEZE").pressed.emit()
	check("FREEZE twice freezes and unfreezes", not game.enemies.frozen and not game.console._freeze_btn.button_pressed)
	button(game.console._panel, "KILL ALL").pressed.emit()
	button(game.console._panel, "GOD").pressed.emit()
	await frames()
	check("KILL ALL clears them", game.enemies.list.is_empty() and not game.enemies.god)
	# items: give / take / random / clear, the HUD bar and the pickup banner
	var out_give: String = game.console.execute("give triple tap 2")
	await frames()
	check("'give triple tap 2' gives two (%s)" % out_give, game.combat.up.count("triple_tap") == 2)
	check("...the HUD shows it in the item bar, with the pickup banner", game.hud.items._bar.get_child_count() == 1
		and game.hud.items._banner.modulate.a > 0.5 and game.hud.items._b_name.text.begins_with("TRIPLE TAP"))
	game.console.execute("take triple tap")
	check("'take triple tap' drops one", game.combat.up.count("triple_tap") == 1)
	button(game.console._panel, "x3").pressed.emit()
	button(game.console._panel, "RANDOM").pressed.emit()
	check("x3 then RANDOM gives three random items", game.combat.up.total == 4)
	var ft_before: int = game.combat.up.count("frost_tip") # RANDOM may have rolled one already
	button(game.console._panel, "FT").pressed.emit()
	check("an item's button gives it (x3 Frost Tip)", game.combat.up.count("frost_tip") == ft_before + 3)
	var chill_me: Enemies.Enemy = game.enemies.spawn("brute", Vector3(game.player.px, game.player.py, game.player.pz - 15.0))
	for i in 5:
		game.combat.damage_target(chill_me.target, 1.0, "body", chill_me.center())
	await frames(3)
	var ice: MeshInstance3D = game.enemy_view._views[chill_me.id].fx._ice
	check("frozen solid: the enemy gets its ice block", ice != null and ice.visible)
	check("'items' lists what you carry", game.console.execute("items").contains("Frost Tip x%d" % (ft_before + 3)))
	button(game.console._panel, "CLEAR").pressed.emit()
	await frames(3)
	check("CLEAR drops them all (and the bar empties)", game.combat.up.total == 0 and game.hud.items._bar.get_child_count() == 0)
	game.console.execute("killall")
	button(game.console._panel, "x1").pressed.emit()
	key(KEY_F10)
	await frames()
	check("F10 closes it again", not game.console.is_open)

	menu.to_main_menu.emit()
	await frames()
	check("main menu from pause", game.state == "menu" and menu.screen == "main")

	# singleplayer: the lobby, pick a character, ready -> stage 1 with that kit
	button(menu._screens.main, "SINGLEPLAYER").pressed.emit()
	await frames()
	var lobby: LobbyScreen = menu.lobby
	check("SINGLEPLAYER opens the lobby with just you in it", menu.screen == "lobby" and menu.lobby_mode == "solo"
		and lobby._players.get_child_count() == 1)
	check("the lobby lists every character", lobby._char_list.get_child_count() == Characters.ORDER.size())
	key(KEY_ESCAPE)
	await frames()
	check("Esc leaves the lobby", menu.screen == "main")
	menu.open_lobby("solo")
	await frames()
	(lobby._char_list.get_child(2) as Button).pressed.emit() # sharpshooter
	await frames()
	check("clicking a character picks it", Settings.character == "sharpshooter")
	cf = ConfigFile.new()
	check("your character is saved", cf.load(Settings.path) == OK and cf.get_value("game", "character", "") == "sharpshooter")
	lobby._ready_btn.pressed.emit()
	game = await wait_playing(game)
	menu = game.menu
	var kit := Characters.loadout("sharpshooter")
	check("READY starts the run on the first stage (%s)" % Characters.FIRST_STAGE, game.state == "playing"
		and game.map_id == Characters.FIRST_STAGE)
	check("you play with your character's kit", game.combat.slots.primary.id == kit.primary
		and game.combat.slots.secondary.id == kit.secondary and game.combat.ability.id == kit.ability)

	# the run's loot: chests on the stage, gold on the HUD, E opens one, the item floats, walk in
	check("the stage has its chests (%d)" % game.loot.chests.size(), game.loot.chests.size() == Loot.CHESTS_PER_RUN
		and game.loot_view.get_child_count() >= Loot.CHESTS_PER_RUN)
	await frames(2)
	check("your gold shows ($0)", game.hud.items._gold.visible and game.hud.items._gold.text == "$0")
	game.console.execute("chest")
	await frames(2)
	check("near a chest: the E prompt, red while you're broke", game.hud.items._prompt.visible
		and game.hud.items._prompt.text.contains("OPEN CHEST") and game.hud.items._prompt.text.contains("$25"))
	game.console.execute("gold 40")
	key(KEY_E)
	await frames(3)
	var drops: Array = game.loot.drops
	check("E opens it: $15 left, an item pops out", game.loot.gold == 15 and drops.size() == 1)
	var vfx_on := false
	if not drops.is_empty():
		var dv: Dictionary = game.loot_view._drops.get(drops[0].id, {})
		vfx_on = not dv.is_empty() and (dv.node as Node3D).get_child(0) is VFXLoot
	check("...floating in the loot glow for its rarity", vfx_on)
	var item: String = drops[0].item if not drops.is_empty() else ""
	var had: int = game.combat.up.count(item) - 0 if item != "" else 0
	await create_timer(1.5).timeout # it hops out toward you and lands at your feet
	check("it lands by you and it's yours, with its banner", item != "" and game.loot.drops.is_empty()
		and game.combat.up.count(item) == had + 1 and game.hud.items._banner.modulate.a > 0.5)
	await create_timer(2.0).timeout
	menu.to_main_menu.emit()
	await frames()

	# multiplayer screen: name saved, a bad address explains itself, Esc goes back
	check("MULTIPLAYER is greyed out for now", button(menu._screens.main, "MULTIPLAYER").disabled)
	menu.show_screen("online") # the screen itself still works
	await frames()
	Settings.player_name = "Tester"
	Settings.save_settings()
	menu.join_match.emit("")
	await frames()
	check("joining with no address says what to do", menu._online_status.text.contains("address") and not game.online)
	cf = ConfigFile.new()
	check("your online name is saved", cf.load(Settings.path) == OK and cf.get_value("online", "name", "") == "Tester")
	key(KEY_ESCAPE)
	await frames()
	check("Esc on the multiplayer screen goes back to the main menu", menu.screen == "main")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("\n%s" % ("all menu checks passed" if fails == 0 else "%d menu check(s) failed" % fails))
	quit(1 if fails else 0)
