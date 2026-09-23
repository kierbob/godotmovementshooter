extends SceneTree
## Checks the time trial headless: portals, the start line, the finish gate, falling off, the exit
## portal, best times per mode and saving them, and that guns really are off on the guns-off run.
##   godot --headless --path . --script res://tests/trial_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func types(t: TimeTrial) -> Array:
	return t.events.map(func(e: Dictionary) -> String: return e.type)


## Stand the player at (x, y, z) and run one trial tick.
func stand(t: TimeTrial, p: PlayerSim, x: float, y: float, z: float, dt := Cfg.TICK_DT) -> void:
	p.px = x
	p.py = y
	p.pz = z
	t.tick(p, dt)


func _init() -> void:
	await run()
	print("\n%s" % ("all trial checks passed" if fails == 0 else "%d trial checks FAILED" % fails))
	quit(1 if fails > 0 else 0)


func run() -> void:
	TimeTrial.path = "user://trials_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.path))
	var map := MapData.load_file("res://data/dev_map.json")
	check("the dev map has a course and two portals", not map.trial.is_empty() and map.portals.size() == 2)
	var t := TimeTrial.new(map)
	var p := PlayerSim.new(0.0, 0.0, 30.0)
	var off_portal: Dictionary = map.portals.filter(func(x: Dictionary) -> bool: return not x.guns)[0]
	var on_portal: Dictionary = map.portals.filter(func(x: Dictionary) -> bool: return x.guns)[0]
	var start: Dictionary = map.trial.start

	# walk into the guns-off portal
	stand(t, p, float(off_portal.x), 0.0, float(off_portal.z))
	check("the guns-off portal takes you onto the course", t.active and not t.guns and types(t) == ["teleport", "enter"])
	check("...to the start room, with no momentum", absf(p.pz - float(start.z)) < 0.01 and p.vx == 0 and p.vz == 0)
	t.events.clear()

	# the clock waits for the start line, then runs
	for i in 60:
		stand(t, p, 200.0, 0.0, 10.0)
	check("the clock doesn't run in the start room", not t.running and t.time == 0)
	stand(t, p, 200.0, 0.0, -1.0)
	check("crossing the start line starts the clock", t.running and types(t) == ["start"])
	for i in 600: # 5 s on the course
		stand(t, p, 200.0, 0.0, -30.0)
	check("the clock counts up (5 s)", absf(t.time - 5.0 - Cfg.TICK_DT) < 0.05)
	t.events.clear()

	# fall off: back to the start, clock reset
	stand(t, p, 200.0, -9.0, -100.0)
	check("falling below the course restarts you", not t.running and t.time == 0 and types(t) == ["teleport", "fell"])
	t.events.clear()

	# a full run into the finish gate
	stand(t, p, 200.0, 0.0, -1.0)
	for i in 1200: # 10 s
		stand(t, p, 200.0, 4.0, -120.0)
	stand(t, p, 200.0, 4.0, -178.0) # inside the finish volume
	var fin: Array = t.events.filter(func(e: Dictionary) -> bool: return e.type == "finish")
	check("the finish gate stops the clock", not t.running and fin.size() == 1)
	check("the first finish is a new best (~10 s)", fin.size() == 1 and fin[0].best and absf(t.best.off - 10.0) < 0.05)
	check("...and sends you back to the start", absf(p.pz - float(start.z)) < 0.01)
	t.events.clear()

	# a slower run doesn't beat it
	stand(t, p, 200.0, 0.0, -1.0)
	for i in 1800:
		stand(t, p, 200.0, 4.0, -120.0)
	stand(t, p, 200.0, 4.0, -178.0)
	check("a slower run is not a new best", t.best.off < 10.1 and t.last.off > 14.9 and not t.events[-1].best)
	t.events.clear()

	# restart (K) mid-run
	stand(t, p, 200.0, 0.0, -1.0)
	stand(t, p, 200.0, 0.0, -40.0)
	t.events.clear()
	t.restart(p)
	check("K restarts the run from the start", not t.running and t.time == 0 and types(t) == ["teleport", "restart"])
	t.events.clear()

	# the exit portal takes you back to the hub (after the teleport cooldown)
	for i in 100:
		stand(t, p, 200.0, 0.0, 10.0)
	stand(t, p, float(map.trial.exit.x), 0.0, float(map.trial.exit.z))
	check("the BACK TO HUB portal leaves the course", not t.active and types(t) == ["teleport", "leave"])
	check("...dropping you at the hub spawn", absf(p.pz - float(map.spawn.z)) < 0.01)
	t.events.clear()

	# guns-on mode keeps its own records
	for i in 100:
		stand(t, p, 0.0, 0.0, 30.0)
	stand(t, p, float(on_portal.x), 0.0, float(on_portal.z))
	check("the guns-on portal starts the guns-on trial", t.active and t.guns and t.best.on < 0)

	# records are saved and loaded back
	var t2 := TimeTrial.new(map)
	check("best times are saved between sessions", absf(t2.best.off - t.best.off) < 0.001 and t2.best.on < 0)
	check("times are shown as mm:ss.mmm", TimeTrial.format_time(83.25) == "01:23.250" and TimeTrial.format_time(-1) == "--:--.---")

	# in the real game: guns off really means no shooting
	Settings.path = "user://settings_trial_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.load_settings()
	Settings.map = "dev_map"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 5:
		await process_frame
	var game := current_scene
	game.menu.play_trial.emit(false)
	for i in 3:
		await process_frame
	check("the GUNS OFF card starts the trial with guns off", game.trial.active and not game.trial.guns and not game.combat.enabled)
	check("...and hides the gun", not game.viewmodel.visible)
	game.menu.to_main_menu.emit()
	await process_frame
	game.menu.play_trial.emit(true)
	for i in 3:
		await process_frame
	check("the GUNS ON card starts it with guns on", game.trial.active and game.trial.guns and game.combat.enabled and game.viewmodel.visible)
	game.menu.to_main_menu.emit()
	await process_frame
	game.menu.play.emit("dev_map")
	await process_frame
	check("playing normally afterwards is off the course with guns", not game.trial.active and game.combat.enabled)
	game.queue_free() # stops any sound still playing, so nothing is held at exit
	for i in 3:
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
