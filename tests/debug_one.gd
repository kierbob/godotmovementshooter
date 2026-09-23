extends SceneTree
## Prints Godot vs web values tick by tick for one scenario (debugging tool).
##   godot --headless --path . --script res://tests/debug_one.gd -- "<scenario name>" <from> <to>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/traces.json"))
	for sc: Dictionary in data.scenarios:
		if sc.name != args[0]:
			continue
		var m := MapData.load_file("res://tests/maps/%s.json" % sc.map)
		var p := PlayerSim.new(sc.start.x, sc.start.y, sc.start.z)
		for i in int(args[2]) + 1:
			var tk: Dictionary = sc.ticks[i]
			var cc: Array = tk.c
			var c := Cmd.new()
			c.forward = cc[0]; c.right = cc[1]; c.jump = cc[2] == 1; c.jump_held = cc[3] == 1
			c.sprint = cc[4] == 1; c.crouch = cc[5] == 1; c.slide = cc[6] == 1; c.slide_pressed = cc[7] == 1; c.yaw = cc[8]
			if tk.has("imp"):
				p.apply_impulse(tk.imp[0], tk.imp[1], tk.imp[2])
			p.step(c, m, Cfg.TICK_DT)
			if i >= int(args[1]):
				var e: Array = tk.p
				print("%d  godot p(%.5f %.5f %.5f) v(%.4f %.4f %.4f) g%s %s | web p(%.5f %.5f %.5f) v(%.4f %.4f %.4f) g%s" % [
					i, p.px, p.py, p.pz, p.vx, p.vy, p.vz, int(p.grounded), p.state, e[0], e[1], e[2], e[3], e[4], e[5], e[6]])
		print(p.events)
	quit()
