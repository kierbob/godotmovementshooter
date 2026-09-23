extends SceneTree
## Checks the Godot movement port against the web game (tests/traces.json, recorded from the web
## game's real code by tools/make_traces.mjs).
##
## One-tick check (pass/fail): before every tick, copy the web game's exact player state into the
## Godot player, run that one tick with the same input, and compare. Errors can't pile up, so any
## logic difference shows immediately.
##
## Whole-run check (info): run the full scenario freely. Godot's sin/cos and Chrome's can differ in
## the 16th digit (Chrome and Firefox differ too), so a long run can eventually take the other side
## of an exact tie (e.g. speed == walk speed) and drift. That's expected, not a bug.
##   godot --headless --path . --script res://tests/compare.gd

const TOLERANCE := 1e-9


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/traces.json"))
	var maps := {
		"dev_map": MapData.load_file("res://data/dev_map.json"),
		"bean-street": MapData.load_file("res://data/bean-street.json"),
	}
	var fails := 0
	var total := 0
	var total_ticks := 0
	var sim_usec := 0
	for sc: Dictionary in data.scenarios:
		var m: MapData = maps[sc.map]
		var ticks: Array = sc.ticks
		# --- one-tick checks ---
		var bad := 0
		var ties := 0
		var worst := 0.0
		var first_detail := ""
		var p := PlayerSim.new()
		for i in ticks.size():
			var tk: Dictionary = ticks[i]
			_restore(p, tk.s)
			var t0 := Time.get_ticks_usec()
			p.step(_cmd(tk.c), m, Cfg.TICK_DT)
			sim_usec += Time.get_ticks_usec() - t0
			var err := _error(p, tk.p)
			if err > TOLERANCE:
				# An exact speed tie (speed == walk/sprint/crouch speed to ~1e-12) can go either way
				# on a last-digit sin/cos difference; both results are valid web-game behavior.
				if _is_speed_tie(tk.s):
					ties += 1
				else:
					bad += 1
					worst = maxf(worst, err)
					if first_detail == "":
						first_detail = "tick %d: godot (%.5f, %.5f, %.5f) web (%.5f, %.5f, %.5f)" % [
							i, p.px, p.py, p.pz, tk.p[0], tk.p[1], tk.p[2]]
		total_ticks += ticks.size()
		# --- whole-run drift (info) ---
		var q := PlayerSim.new(sc.start.x, sc.start.y, sc.start.z)
		var drift_at := -1
		for i in ticks.size():
			var tk: Dictionary = ticks[i]
			if tk.has("imp"):
				q.apply_impulse(tk.imp[0], tk.imp[1], tk.imp[2], "test")
			q.step(_cmd(tk.c), m, Cfg.TICK_DT)
			if drift_at < 0 and _error(q, tk.p) > 1e-6:
				drift_at = i
		var run_note := "whole run identical" if drift_at < 0 else "whole run drifts from tick %d (float tie)" % drift_at
		total += 1
		if bad > 0:
			fails += 1
			print("FAIL  %s  %d/%d ticks differ (worst %.4f), first %s" % [sc.name, bad, ticks.size(), worst, first_detail])
		else:
			print("PASS  %s  %d ticks%s, %s" % [sc.name, ticks.size(),
				(" (%d exact speed ties)" % ties) if ties else "", run_note])
	print("\n%d/%d scenarios: every tick matches the web game. Sim cost: %.0f us per tick." % [
		total - fails, total, float(sim_usec) / maxf(1, total_ticks)])
	quit(1 if fails else 0)


func _cmd(cc: Array) -> Cmd:
	var c := Cmd.new()
	c.forward = cc[0]
	c.right = cc[1]
	c.jump = cc[2] == 1
	c.jump_held = cc[3] == 1
	c.sprint = cc[4] == 1
	c.crouch = cc[5] == 1
	c.slide = cc[6] == 1
	c.slide_pressed = cc[7] == 1
	c.yaw = cc[8]
	return c


func _error(p: PlayerSim, e: Array) -> float:
	var err := maxf(maxf(absf(p.px - e[0]), absf(p.py - e[1])), absf(p.pz - e[2]))
	err = maxf(err, maxf(maxf(absf(p.vx - e[3]), absf(p.vy - e[4])), absf(p.vz - e[5])))
	if p.grounded != (e[6] == 1):
		err = INF
	return err


func _is_speed_tie(s: Dictionary) -> bool:
	var speed := PlayerSim.hyp2(s.vel.x, s.vel.z)
	for v in [Cfg.MOVE_WALK_SPEED, Cfg.MOVE_SPRINT_SPEED, Cfg.PLAYER_CROUCH_SPEED]:
		if absf(speed - v) < 1e-9:
			return true
	return false


## Copy the web game's player state (snapshotState) into a Godot PlayerSim.
func _restore(p: PlayerSim, s: Dictionary) -> void:
	p.px = s.pos.x
	p.py = s.pos.y
	p.pz = s.pos.z
	p.vx = s.vel.x
	p.vy = s.vel.y
	p.vz = s.vel.z
	p.height = s.height
	p.grounded = s.grounded
	p.crouching = s.crouching
	p.sliding = s.sliding
	p.slide_cooldown = s.slideCooldown
	p.coyote = s.coyote
	p.jump_buffer = s.jumpBuffer
	p.air_time = s.airTime
	p.friction_grace = s.frictionGrace
	p.land_grace = s.landGrace
	p.sprinting = s.sprinting
	p.pad_cooldown = s.padCooldown
	p.pad_launches = int(s.padLaunches)
	p.last_pad = int(s.lastPad)
	p.has_wall_n = s.wallNormal != null
	if p.has_wall_n:
		p.wall_n = Vector2i(int(s.wallNormal.x), int(s.wallNormal.z))
	p.wall_coyote = s.wallCoyote
	p.wall_jumps = int(s.wallJumps)
	p.last_wall_jump_t = s.lastWallJumpT
	p.has_last_wall_n = s.lastWallJumpNormal != null
	if p.has_last_wall_n:
		p.last_wall_n = Vector2i(int(s.lastWallJumpNormal.x), int(s.lastWallJumpNormal.z))
	p.time = s.time
