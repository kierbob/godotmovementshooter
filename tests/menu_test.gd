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
	await create_timer(2.0).timeout
	menu.to_main_menu.emit()
	await frames()

	# multiplayer screen: name saved, a bad address explains itself, Esc goes back
	button(menu._screens.main, "MULTIPLAYER").pressed.emit()
	await frames()
	check("MULTIPLAYER opens the multiplayer screen", menu.screen == "online")
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
