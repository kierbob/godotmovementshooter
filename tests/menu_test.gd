extends SceneTree
## Clicks through the menus headless and checks each step.
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
	menu.play.emit("dev_map")
	await frames()
	check("PLAY starts the game", game.state == "playing" and menu.screen == "")
	key(KEY_ESCAPE)
	await frames()
	check("Esc pauses", game.state == "paused" and menu.screen == "pause")
	menu.open_settings("pause")
	await frames()
	check("pause -> settings (no top bar)", menu.screen == "settings" and not menu._top.visible)
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

	# back to the main menu, then pick another map
	menu.to_main_menu.emit()
	await frames()
	check("main menu from pause", game.state == "menu" and menu.screen == "main")

	# loadout: pick a primary and an ability, and they're what you play with
	(menu._top_tabs.loadout as Button).pressed.emit()
	await frames()
	check("LOADOUT tab opens the loadout screen", menu.screen == "loadout" and menu._top.visible)
	var rocket_tile: Button = menu._items_row.get_child(2) # shotgun, rifle, rocket, sniper
	rocket_tile.pressed.emit()
	await frames()
	check("clicking a tile equips it", Settings.loadout.primary == "rocket")
	(menu._loadout_slots.get_child(3) as Button).pressed.emit() # title, primary, secondary, ability
	await frames()
	(menu._items_row.get_child(1) as Button).pressed.emit() # frag, knife, impulse
	await frames()
	check("ability slot lists abilities and equips one", menu.loadout_slot == "ability" and Settings.loadout.ability == "knife")
	cf = ConfigFile.new()
	check("loadout is saved", cf.load(Settings.path) == OK and cf.get_value("loadout", "primary", "") == "rocket")
	key(KEY_ESCAPE)
	await frames()
	check("Esc in loadout goes back to the main menu", menu.screen == "main")
	menu.play.emit("dev_map")
	await frames()
	check("you play with the chosen loadout", game.combat.slots.primary.id == "rocket" and game.combat.ability.id == "knife")
	menu.to_main_menu.emit()
	await frames()

	menu.play.emit("bean-street")
	await frames(8)
	game = current_scene
	check("playing another map reloads into it", game.map.name == "Bean Street" and game.state == "playing")
	check("chosen map is remembered", Settings.map == "bean-street")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("\n%s" % ("all menu checks passed" if fails == 0 else "%d menu check(s) failed" % fails))
	quit(1 if fails else 0)
