class_name PlayerSim
extends RefCounted
## Movement simulation: a line-for-line port of the web game's src/player.js, so it feels the
## same. Position/velocity are plain 64-bit floats (Vector3 is 32-bit) so the results match the
## JS version to the last digit (checked by tests/compare.gd against recorded JS runs).

var px := 0.0
var py := 0.0
var pz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var height := Cfg.PLAYER_HEIGHT
var grounded := false
var crouching := false
var sliding := false
var slide_cooldown := 0.0 # time until the next slide gives a boost
var coyote := 0.0
var jump_buffer := 0.0
var air_time := 0.0
var friction_grace := 0.0 # skip ground friction briefly after knockback
var land_grace := 0.0 # skip ground friction briefly after landing (keeps jump chains fast)
var hp := 100.0
var max_hp := 100.0
var dead := false
var regen_delay := 0.0
var invuln := 0.0
var sprinting := false
var pad_cooldown := 0.0
var pad_launches := 0 # increments on every jump pad launch (visuals watch this)
var last_pad := -1
var has_wall_n := false # outward normal (x, z) of the wall we're touching / last touched
var wall_n := Vector2i.ZERO
var wall_coyote := 0.0 # can still wall jump this long after leaving a wall
var wall_jumps := 0 # wall jumps since last touching the ground
var last_wall_jump_t := -1.0
var has_last_wall_n := false
var last_wall_n := Vector2i.ZERO
var state := "air"
var time := 0.0
var events: Array = [] # recent movement events for the debug panel: { t, name, detail }
var quiet := false # don't log events (replays)
# Ramp we're standing on this tick: downhill direction + slide acceleration (JS p.rampDown).
var ramp_down := false
var ramp_down_x := 0.0
var ramp_down_z := 0.0
var ramp_down_a := 0.0

var _hit_top := 0.0 # top of the last box _move_axis hit (a ramp's slope height under us)
var _wall := Vector2i.ZERO # result of _find_wall


func _init(x := 0.0, y := 0.0, z := 0.0) -> void:
	px = x
	py = y
	pz = z


func respawn(x: float, y: float, z: float) -> void:
	px = x
	py = y
	pz = z
	vx = 0.0
	vy = 0.0
	vz = 0.0
	sliding = false
	slide_cooldown = 0.0
	_log("respawn")


func _log(event_name: String, detail := "") -> void:
	if quiet:
		return
	events.append({"t": time, "name": event_name, "detail": detail})
	if events.size() > 8:
		events.pop_front()


func eye_y() -> float:
	return py + (Cfg.PLAYER_CROUCH_EYE_HEIGHT if crouching else Cfg.PLAYER_EYE_HEIGHT)


## Knockback from guns/explosions. Anything pushing up cancels your fall first, so a rocket
## jump works the same whether you're rising or falling.
func apply_impulse(ix: float, iy: float, iz: float, source := "") -> void:
	if iy > 0:
		vy = maxf(vy, 0.0)
		grounded = false
		coyote = 0.0
	vx += ix
	vy += iy
	vz += iz
	var strength := hyp3(ix, iy, iz)
	friction_grace = maxf(friction_grace, Cfg.MOVE_KNOCKBACK_GRACE + Cfg.MOVE_KNOCKBACK_GRACE_PER * strength)
	_log("knockback", "%.1f m/s %s" % [strength, source])


## Same result as JavaScript's Math.hypot, bit for bit (V8 scales by the max and uses Kahan
## summation). A plain sqrt(x*x + z*z) can differ in the last digit, which occasionally flips
## a "speed > walk speed" check and makes the port drift from the web game.
static func hyp2(a: float, b: float) -> float:
	a = absf(a)
	b = absf(b)
	var mx := maxf(a, b)
	if mx == 0.0:
		return 0.0
	var n := a / mx
	var sum := n * n
	n = b / mx
	var summand := n * n
	var pre := sum + summand
	return sqrt(pre) * mx


static func hyp3(a: float, b: float, c: float) -> float:
	a = absf(a)
	b = absf(b)
	c = absf(c)
	var mx := maxf(maxf(a, b), c)
	if mx == 0.0:
		return 0.0
	var n := a / mx
	var sum := n * n
	var comp := 0.0
	n = b / mx
	var summand := n * n - comp
	var pre := sum + summand
	comp = (pre - sum) - summand
	sum = pre
	n = c / mx
	summand = n * n - comp
	pre = sum + summand
	return sqrt(pre) * mx


func horizontal_speed() -> float:
	return hyp2(vx, vz)


func _set_horizontal_speed(speed: float) -> void:
	var cur := horizontal_speed()
	if cur < 1e-6:
		return
	vx *= speed / cur
	vz *= speed / cur


# ---------- collision ----------

func _blocked(boxes: Array[MapData.Box]) -> bool:
	var hw := Cfg.PLAYER_HALF_WIDTH
	var ax0 := px - hw
	var ax1 := px + hw
	var az0 := pz - hw
	var az1 := pz + hw
	for b in boxes:
		var top := MapData.solid_top(b, ax0, ax1, az0, az1)
		if MapData.overlaps_top(ax0, py, az0, ax1, py + height, az1, b, top):
			return true
	return false


## The ramp we're standing on, if any.
func _ramp_under(boxes: Array[MapData.Box]) -> MapData.Box:
	var hw := Cfg.PLAYER_HALF_WIDTH
	var ax0 := px - hw
	var ax1 := px + hw
	var az0 := pz - hw
	var az1 := pz + hw
	for b in boxes:
		if b.ramp_axis < 0:
			continue
		var top := MapData.solid_top(b, ax0, ax1, az0, az1)
		if MapData.overlaps_top(ax0, py - 0.06, az0, ax1, py + height, az1, b, top) and absf(top - py) < 0.06:
			return b
	return null


## After walking down a ramp (or off its bottom), put our feet back on the ground if it's only a
## little below, so downhill isn't a string of tiny falls.
func _snap_down(boxes: Array[MapData.Box], max_drop: float) -> bool:
	var hw := Cfg.PLAYER_HALF_WIDTH
	var ax0 := px - hw
	var ax1 := px + hw
	var az0 := pz - hw
	var az1 := pz + hw
	var top := -INF
	for b in boxes:
		var t := MapData.solid_top(b, ax0, ax1, az0, az1)
		if not MapData.overlaps_top(ax0, py - max_drop, az0, ax1, py + height, az1, b, t):
			continue
		if t > py + 1e-6:
			return false # something at our feet level: not a clean drop
		top = maxf(top, t)
	if top == -INF:
		return false
	py = top
	return true


## Move along one axis (0 = x, 1 = y, 2 = z) and push out of anything we hit.
## Returns the box hit (its effective top is in _hit_top), or null.
func _move_axis(axis: int, delta: float, boxes: Array[MapData.Box]) -> MapData.Box:
	if delta == 0.0:
		return null
	if axis == 0:
		px += delta
	elif axis == 1:
		py += delta
	else:
		pz += delta
	var hit: MapData.Box = null
	var hw := Cfg.PLAYER_HALF_WIDTH
	for b in boxes:
		var ax0 := px - hw
		var ax1 := px + hw
		var az0 := pz - hw
		var az1 := pz + hw
		var top := MapData.solid_top(b, ax0, ax1, az0, az1)
		if not MapData.overlaps_top(ax0, py, az0, ax1, py + height, az1, b, top):
			continue
		hit = b
		_hit_top = top
		if axis == 1:
			py = top if delta < 0 else b.min_y - height
		elif axis == 0:
			px = b.min_x - hw if delta > 0 else b.max_x + hw
		else:
			pz = b.min_z - hw if delta > 0 else b.max_z + hw
	return hit


## Horizontal move with automatic step-up onto low ledges while grounded, and onto a slope that
## rises under us in the air.
func _move_horizontal(axis: int, delta: float, boxes: Array[MapData.Box], was_grounded: bool) -> void:
	var start := px if axis == 0 else pz
	var ox := px
	var oz := pz
	var hit := _move_axis(axis, delta, boxes)
	if hit == null:
		return
	var rise := _hit_top - py
	var step := was_grounded and rise > 0 and rise <= Cfg.PLAYER_STEP_HEIGHT
	# Not in the web game (world.js pushes you out to the ramp's low end, a teleport of meters):
	# moving uphill along a ramp in the air with our feet on or above its slope just now means the
	# slope rose into us, so ride up onto it. On the ground the step-up above already does this.
	var hw := Cfg.PLAYER_HALF_WIDTH
	var onto_slope := not step and hit.ramp_axis == axis and rise > 0 \
		and py >= MapData.solid_top(hit, ox - hw, ox + hw, oz - hw, oz + hw) - 1e-6
	if step or onto_slope:
		var sx := px
		var sy := py
		var sz := pz
		if axis == 0:
			px = start + delta
		else:
			pz = start + delta
		py = _hit_top + 1e-4
		if not _blocked(boxes):
			_log("step-up" if step else "onto slope", "%.2f m" % rise)
			return
		px = sx
		py = sy
		pz = sz
	if axis == 0:
		vx = 0.0
	else:
		vz = 0.0


## Outward normal (axis-aligned) of a wall right next to us, in _wall. Probes a thin slice on each
## side of the hitbox, ignoring the feet/head so floors and ceilings don't count as walls.
func _find_wall(boxes: Array[MapData.Box]) -> bool:
	var hw := Cfg.PLAYER_HALF_WIDTH
	var r := Cfg.WALL_REACH
	var y0 := py + 0.3
	var y1 := py + height - 0.1
	var found := false
	var best_score := -INF
	for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x0 := px - hw - (r if n.x > 0 else 0.0)
		var z0 := pz - hw - (r if n.y > 0 else 0.0)
		var x1 := px + hw + (r if n.x < 0 else 0.0)
		var z1 := pz + hw + (r if n.y < 0 else 0.0)
		# Only the slice beyond the hitbox on the wall side matters; shrink it a bit sideways so a
		# wall we're pressed flat against doesn't also count as a wall on our left/right.
		if n.x > 0:
			x1 = px - hw
		if n.x < 0:
			x0 = px + hw
		if n.y > 0:
			z1 = pz - hw
		if n.y < 0:
			z0 = pz + hw
		if n.x != 0:
			z0 += 0.05
			z1 -= 0.05
		if n.y != 0:
			x0 += 0.05
			x1 -= 0.05
		var touching := false
		for b in boxes:
			var top := MapData.solid_top(b, x0, x1, z0, z1)
			# Touching counts here (the probe sits flush against the wall face).
			if x0 <= b.max_x and x1 >= b.min_x and y0 < top and y1 > b.min_y and z0 <= b.max_z and z1 >= b.min_z:
				touching = true
				break
		if not touching:
			continue
		var score := -(vx * n.x + vz * n.y) # prefer the wall we're moving into
		if score > best_score:
			best_score = score
			_wall = n
			found = true
	return found


# ---------- movement pieces ----------

## Kick off the wall: keep momentum along it, push away (bent toward where you steer), pop up,
## and add a small speed bump.
func _wall_jump(n: Vector2i, has_wish: bool, wx: float, wz: float) -> void:
	var before := horizontal_speed()
	var vn := vx * n.x + vz * n.y
	var tx := vx - n.x * vn
	var tz := vz - n.y * vn
	var dx := float(n.x)
	var dz := float(n.y)
	if has_wish:
		var bx := n.x + wx
		var bz := n.y + wz
		var bl := hyp2(bx, bz)
		if bl > 1e-3 and (bx * n.x + bz * n.y) / bl >= 0.3:
			dx = bx / bl
			dz = bz / bl
	vx = tx * Cfg.WALL_KEEP_ALONG + dx * Cfg.WALL_JUMP_PUSH
	vz = tz * Cfg.WALL_KEEP_ALONG + dz * Cfg.WALL_JUMP_PUSH
	# The push only sets the direction; speed is what you had plus a small bump.
	_set_horizontal_speed(maxf(before, Cfg.MOVE_WALK_SPEED) + Cfg.WALL_SPEED_BUMP)
	vy = Cfg.WALL_JUMP_UP
	wall_jumps += 1
	jump_buffer = 0.0
	wall_coyote = 0.0
	last_wall_jump_t = time
	last_wall_n = n
	has_last_wall_n = true
	friction_grace = 0.0
	_log("wall jump", "#%d %.1f m/s" % [wall_jumps, horizontal_speed()])


func _check_pads(pads: Array[MapData.Pad]) -> void:
	if pad_cooldown > 0:
		return
	for i in pads.size():
		var pad := pads[i]
		var feet := py - pad.y
		if feet < -0.1 or feet > 0.4:
			continue
		var dxp := px - pad.x
		var dzp := pz - pad.z
		if hyp2(dxp, dzp) > pad.radius:
			continue
		vy = pad.launch if pad.has_launch else Cfg.JUMP_PAD_LAUNCH
		if pad.has_dir:
			# Directional pad: fling along its arrow, keeping extra speed if you were faster.
			var along := vx * pad.dir_x + vz * pad.dir_z
			var f := maxf(pad.forward, along)
			vx = pad.dir_x * f
			vz = pad.dir_z * f
		else:
			var speed := horizontal_speed()
			if speed > 1:
				_set_horizontal_speed(speed + (pad.forward if pad.has_forward else Cfg.JUMP_PAD_FORWARD_BOOST))
		grounded = false
		coyote = 0.0
		sliding = false
		pad_cooldown = Cfg.JUMP_PAD_COOLDOWN
		pad_launches += 1
		wall_jumps = 0
		last_pad = i
		_log("jump pad", "%.1f m/s" % horizontal_speed())
		return


## Quake-style acceleration toward the wish direction, but input alone can never raise total
## horizontal speed above max(current speed, wish speed): no air/ground strafe gain.
func _accelerate(wx: float, wz: float, wish_speed: float, accel: float, dt: float) -> void:
	var before := hyp2(vx, vz)
	var current := vx * wx + vz * wz
	var add := wish_speed - current
	if add <= 0:
		return
	var amount := minf(accel * wish_speed * dt, add)
	vx += wx * amount
	vz += wz * amount
	var cap := maxf(before, wish_speed)
	var after := hyp2(vx, vz)
	if after > cap:
		vx *= cap / after
		vz *= cap / after


func _apply_friction(dt: float) -> void:
	var speed := hyp2(vx, vz)
	if speed < 1e-4:
		vx = 0.0
		vz = 0.0
		return
	var drop := maxf(speed, Cfg.MOVE_STOP_SPEED) * Cfg.MOVE_FRICTION * dt
	var scale := maxf(speed - drop, 0.0) / speed
	vx *= scale
	vz *= scale


## Turn horizontal velocity toward the wish direction by at most max_turn radians, keeping speed.
func _steer(wx: float, wz: float, max_turn: float) -> void:
	var speed := hyp2(vx, vz)
	if speed < 1e-4:
		return
	var cur := atan2(vz, vx)
	var diff := atan2(wz, wx) - cur
	diff = atan2(sin(diff), cos(diff))
	if absf(diff) > PI * 0.75:
		return # holding back doesn't reverse momentum
	var a := cur + maxf(-max_turn, minf(max_turn, diff))
	vx = cos(a) * speed
	vz = sin(a) * speed


## Apex-style air control: momentum swings toward where you steer at a fixed turn rate, keeping
## its speed. Steering backwards brakes instead. no_brake: right after a gun knockback.
func _air_control(wx: float, wz: float, dt: float, no_brake: bool) -> void:
	var speed := hyp2(vx, vz)
	if speed > 0.5:
		var cur := atan2(vz, vx)
		var diff := atan2(wz, wx) - cur
		diff = atan2(sin(diff), cos(diff))
		if absf(diff) > Cfg.AIR_BRAKE_ANGLE:
			if no_brake:
				return
			var s := maxf(0.0, speed - Cfg.AIR_BRAKE * dt)
			vx *= s / speed
			vz *= s / speed
			return
		_steer(wx, wz, Cfg.AIR_TURN_RATE * dt)
	_accelerate(wx, wz, Cfg.MOVE_WALK_SPEED, Cfg.AIR_ACCEL, dt)


## Crouch shrinks the hitbox from the top. Standing up needs headroom.
func _update_crouch(want: bool, boxes: Array[MapData.Box]) -> void:
	if want and not crouching:
		crouching = true
		height = Cfg.PLAYER_CROUCH_HEIGHT
	elif not want and crouching:
		height = Cfg.PLAYER_HEIGHT
		if _blocked(boxes):
			height = Cfg.PLAYER_CROUCH_HEIGHT # no room, stay down
		else:
			crouching = false


func _start_slide(reason: String, allow_boost := true) -> void:
	var speed := horizontal_speed()
	if speed < Cfg.SLIDE_MIN_SPEED:
		return
	var new_speed := speed
	if allow_boost and slide_cooldown <= 0:
		new_speed = maxf(speed, minf(speed + Cfg.SLIDE_BOOST, Cfg.SLIDE_BOOST_MAX_SPEED))
		_set_horizontal_speed(new_speed)
		slide_cooldown = Cfg.SLIDE_BOOST_COOLDOWN
	sliding = true
	var boosted := new_speed > speed + 0.01
	_log(reason, ("%.1f→%.1f m/s" % [speed, new_speed]) if boosted else ("%.1f m/s (no boost)" % speed))


# ---------- the tick ----------

func step(c: Cmd, m: MapData, dt: float) -> void:
	var boxes := m.nearby(px, py, pz, 2.0)
	time += dt
	var was_grounded := grounded

	# Wish direction from yaw. Yaw 0 looks down -Z.
	var s := sin(c.yaw)
	var co := cos(c.yaw)
	var wx := -s * c.forward + co * c.right
	var wz := -co * c.forward - s * c.right
	var wl := hyp2(wx, wz)
	if wl > 0:
		wx /= wl
		wz /= wl

	if c.jump:
		jump_buffer = Cfg.MOVE_JUMP_BUFFER
	else:
		jump_buffer = maxf(0.0, jump_buffer - dt)
	coyote = Cfg.MOVE_COYOTE_TIME if grounded else maxf(0.0, coyote - dt)
	slide_cooldown = maxf(0.0, slide_cooldown - dt)
	friction_grace = maxf(0.0, friction_grace - dt)
	land_grace = maxf(0.0, land_grace - dt)
	pad_cooldown = maxf(0.0, pad_cooldown - dt)

	# Ramps: sliding downhill speeds you up; running uphill carries you up and off the top.
	var ramp: MapData.Box = _ramp_under(boxes) if grounded else null
	var ramp_vy := 0.0
	if ramp != null:
		var sl := MapData.ramp_slope(ramp)
		var ux := float(ramp.ramp_dir) if ramp.ramp_axis == 0 else 0.0
		var uz := float(ramp.ramp_dir) if ramp.ramp_axis == 2 else 0.0
		ramp_vy = maxf(0.0, vx * ux + vz * uz) * sl
		ramp_down = true
		ramp_down_x = -ux
		ramp_down_z = -uz
		ramp_down_a = (Cfg.MOVE_GRAVITY * sl) / hyp2(1.0, sl)
	else:
		ramp_down = false

	# Slide (hold slide key) and crouch (hold crouch key) are separate.
	if grounded and c.slide_pressed and not sliding:
		_start_slide("slide")
	if sliding and not c.slide:
		sliding = false
		_log("slide cancel")
	if sliding and horizontal_speed() < Cfg.SLIDE_END_SPEED:
		sliding = false
		_log("slide end")
	_update_crouch(c.crouch or sliding, boxes)

	if grounded:
		if sliding:
			_set_horizontal_speed(maxf(0.0, horizontal_speed() - Cfg.SLIDE_FRICTION * dt))
			if ramp_down: # gravity pulls you down the slope
				vx += ramp_down_x * ramp_down_a * dt
				vz += ramp_down_z * ramp_down_a * dt
			if wl > 0:
				_steer(wx, wz, Cfg.SLIDE_STEER_RATE * dt)
		else:
			# Sprint only counts when moving forward-ish (not backpedaling or pure strafing).
			var spr := c.sprint and c.forward > 0 and not crouching
			var wish_speed := Cfg.PLAYER_CROUCH_SPEED if crouching else (Cfg.MOVE_SPRINT_SPEED if spr else Cfg.MOVE_WALK_SPEED)
			var speed := horizontal_speed()
			var along := (vx * wx + vz * wz) / speed if wl > 0 and speed > 0.01 else -1.0
			if friction_grace > 0:
				pass # just got knocked back: keep everything for a moment
			elif crouching and speed > wish_speed:
				# Crouching kills momentum fast: going fast low to the ground is what sliding is for.
				_set_horizontal_speed(maxf(wish_speed, speed - Cfg.PLAYER_CROUCH_BRAKE * dt))
			elif land_grace > 0:
				pass # just landed: keep everything for a moment (jump chains stay fast)
			elif speed > wish_speed and along > 0.7:
				# Carrying extra speed and still pushing that way: let it fade slowly (momentum!)
				_set_horizontal_speed(maxf(wish_speed, speed - Cfg.MOVE_OVERSPEED_DECAY * dt))
				# ...and carve toward your aim. Without this, speed above run speed can't be steered at
				# all (acceleration adds nothing once you're already faster), which feels like ice.
				_steer(wx, wz, Cfg.MOVE_GROUND_TURN_RATE * dt)
			else:
				_apply_friction(dt)
			sprinting = spr and speed > Cfg.MOVE_WALK_SPEED - 0.5
			if wl > 0:
				_accelerate(wx, wz, wish_speed, Cfg.MOVE_GROUND_ACCEL, dt)
	elif wl > 0:
		_air_control(wx, wz, dt, friction_grace > 0)

	# Walls: touching one in the air lets you wall jump off it.
	var touching_wall := false if grounded else _find_wall(boxes)
	if touching_wall:
		wall_n = _wall
		has_wall_n = true
		wall_coyote = Cfg.WALL_COYOTE_TIME
	else:
		wall_coyote = maxf(0.0, wall_coyote - dt)

	if jump_buffer > 0 and coyote > 0:
		vy = Cfg.MOVE_JUMP_VELOCITY + ramp_vy # jumping while running up a ramp goes higher
		grounded = false
		coyote = 0.0
		jump_buffer = 0.0
		var jump_name := "slide jump" if sliding else ("jump" if was_grounded else "coyote jump")
		sliding = false
		_log(jump_name, "%.1f m/s" % horizontal_speed())
	elif jump_buffer > 0 and not grounded and wall_coyote > 0 and wall_jumps < Cfg.WALL_MAX_JUMPS:
		var n := wall_n
		var same_wall := has_last_wall_n and last_wall_n == n
		if not same_wall or time - last_wall_jump_t >= Cfg.WALL_SAME_WALL_DELAY:
			_wall_jump(n, wl > 0, wx, wz)

	vy = minf(maxf(vy - Cfg.MOVE_GRAVITY * dt, -Cfg.MOVE_MAX_FALL_SPEED), Cfg.MOVE_MAX_RISE_SPEED)

	# Hard momentum cap: nothing gets you past this.
	if horizontal_speed() > Cfg.MOVE_MAX_SPEED:
		_set_horizontal_speed(Cfg.MOVE_MAX_SPEED)

	# Substep so fast movement can't tunnel through thin geometry.
	var max_step := 0.25
	var dist := maxf(maxf(absf(vx), absf(vy)), absf(vz)) * dt
	var steps := maxi(1, ceili(dist / max_step))
	var sdt := dt / steps
	var landed := false
	for i in steps:
		_move_horizontal(0, vx * sdt, boxes, was_grounded)
		_move_horizontal(2, vz * sdt, boxes, was_grounded)
		var v_y := vy
		if _move_axis(1, v_y * sdt, boxes) != null:
			if v_y < 0:
				landed = true
			vy = 0.0

	# Ramps: stick to the slope going down; fly off the top going up.
	if was_grounded and not landed and vy <= 0:
		if ramp != null and _snap_down(boxes, horizontal_speed() * dt * 1.5 + 0.05):
			landed = true
			vy = 0.0
		elif ramp_vy > 0:
			vy = ramp_vy
			_log("ramp launch", "%.1f m/s up" % ramp_vy)

	if landed and not was_grounded:
		land_grace = Cfg.MOVE_LAND_GRACE
		_log("land", "%.1f m/s after %.2f s" % [horizontal_speed(), air_time])
		# Only a real fall/jump earns a boosted landing slide. Dropping off a small box mid-slide
		# just carries the slide on, with no new boost.
		if c.slide and not sliding:
			var real_fall := air_time >= Cfg.SLIDE_LAND_MIN_AIR_TIME
			_start_slide("land slide" if real_fall else "slide continue", real_fall)
	if not landed and was_grounded and vy <= 0:
		_log("left ground")
	grounded = landed
	air_time = 0.0 if grounded else air_time + dt
	if grounded:
		wall_jumps = 0
		wall_coyote = 0.0
		has_last_wall_n = false
	if not grounded and sliding and vy < 0:
		sliding = false # slid off a ledge
	_check_pads(m.pads)

	var speed_now := horizontal_speed()
	if not grounded:
		state = "rising" if vy > 0 else "falling"
	elif sliding:
		state = "sliding"
	elif crouching:
		state = "crouch walk" if speed_now > 0.5 else "crouched"
	else:
		state = ("sprinting" if sprinting else "walking") if speed_now > 0.5 else "idle"
