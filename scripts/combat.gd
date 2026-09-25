class_name Combat
extends RefCounted
## Weapons, abilities, projectiles, damage and knockback: a port of the web game's src/combat.js
## (bots left out for now). Pure logic that runs inside the fixed sim tick, so the multiplayer
## server (MatchServer) runs the same code. Visuals and the HUD read `fx` (a queue of events)
## every frame and clear it.
##
## Vector3 is fine here (unlike PlayerSim): spread is random anyway, so nothing needs to match the
## web game bit for bit. Knockback goes into the player through PlayerSim.apply_impulse.

const SWITCH_TIME := 0.3 # seconds to draw a weapon
const SEMI_BUFFER := 0.12 # a click this early before the gun is ready still fires

## Bean dummies are two capsules (segment a→b with radius r, relative to the feet): a body bean
## and a floating head bean. zone picks the damage multiplier (head = weapon head_mult).
const DUMMY_PARTS := [
	{"zone": "body", "a": Vector3(0, 0.38, 0), "b": Vector3(0, 1.06, 0), "r": 0.38},
	{"zone": "head", "a": Vector3(0, 1.7, 0), "b": Vector3(0, 1.76, 0), "r": 0.2},
]
const DUMMY_HP := 150.0
const DUMMY_RESPAWN := 2.5


class Target:
	var id := 0 # dummies: their index; online players: their peer id
	var kind := "dummy" # "dummy" | "enemy" | "player" (server side, has a body) | "remote" (client side)
	var name := ""
	var body: PlayerSim = null # a real player: explosions push it, spawn protection applies
	var size := 1.0 # hitbox scale (a small swarmer, a big brute)
	var base := Vector3.ZERO
	var pos := Vector3.ZERO
	var move := {} # {axis: "x"|"z", amp, speed} for sliding dummies
	var hp := DUMMY_HP
	var max_hp := DUMMY_HP
	var dead := false
	var respawn_t := 0.0
	var status := {} # burn, bleed, chill, freeze, mark, bombs (Upgrades ticks them)
	var knock := Vector3.ZERO # flyers: a shove from an item, applied by Enemies next tick


class Projectile:
	var id := 0
	var kind := ""
	var def := {}
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var alive := true
	var stuck := false
	var resting := false
	var copy := false # a Triple Tap copy: its explosion doesn't push you
	var src := "gun" # "item" for wisps (they don't proc)


class Hit:
	var t := 0.0
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var target: Target = null
	var zone := ""


var boxes: Array[MapData.Box] = []
var grid: MapData # when set, rays only test the boxes in the grid cells they cross (much faster)
var targets: Array[Target] = []
var projectiles: Array[Projectile] = []
var fx: Array[Dictionary] = [] # events for the HUD / visuals: shot, impact, hit, explosion, ...
var time := 0.0
var enabled := true # false = guns off (time trial later)

var loadout := {}
var slots := {} # "primary"/"secondary" -> weapon dict
var state := {} # "primary"/"secondary" -> {ammo, reload_t, next_fire}
var active := "primary"
var draw_t := 0.0
var ability := {}
var ability_cd := 0.0
var fire_queued := 0.0
var last_hit := {}
var _next_projectile := 1
var up: Upgrades # the items you carry (empty = no effect at all)
var player: PlayerSim # whose guns these are (set every tick; items read it)


func _init(map_boxes: Array[MapData.Box], map_targets: Array) -> void:
	boxes = map_boxes
	up = Upgrades.new(self)
	for i in map_targets.size():
		var src: Dictionary = map_targets[i]
		var t := Target.new()
		t.id = i
		t.base = Vector3(src.x, src.y, src.z)
		t.pos = t.base
		t.move = src.get("move", {})
		targets.append(t)
	set_loadout(Items.DEFAULT_LOADOUT)


func set_loadout(lo: Dictionary) -> void:
	loadout = lo.duplicate()
	slots = {"primary": Items.WEAPONS[lo.primary], "secondary": Items.WEAPONS[lo.secondary]}
	state = {
		"primary": {"ammo": mag_size("primary"), "reload_t": 0.0, "reload_len": 1.0, "next_fire": 0.0},
		"secondary": {"ammo": mag_size("secondary"), "reload_t": 0.0, "reload_len": 1.0, "next_fire": 0.0},
	}
	active = "primary"
	draw_t = 0.0
	ability = Items.ABILITIES[lo.ability]
	ability_cd = 0.0
	fire_queued = 0.0
	projectiles.clear()
	last_hit = {}


func reset_targets() -> void:
	for t in targets:
		t.hp = t.max_hp
		t.dead = false
		t.respawn_t = 0.0
		t.pos = t.base


func weapon() -> Dictionary:
	return slots[active]


func weapon_state() -> Dictionary:
	return state[active]


## Magazine size with items (Extended Mag).
func mag_size(slot := "") -> int:
	return up.mag_size(int(slots[active if slot == "" else slot].mag))


func tick(p: PlayerSim, c: Cmd, dt: float) -> void:
	time += dt
	player = p
	_update_targets(p, dt)
	up.tick(p, dt)
	if not enabled:
		_update_projectiles(p, dt)
		return

	# Reloads tick on BOTH guns, so a holstered gun keeps reloading at the normal speed.
	for slot: String in ["primary", "secondary"]:
		var s: Dictionary = state[slot]
		if s.reload_t > 0:
			s.reload_t -= dt
			if s.reload_t <= 0:
				s.reload_t = 0.0
				s.ammo = mag_size(slot)

	# Weapon switching. An empty gun starts reloading whether you switch to it or away from it.
	var want := c.slot
	if want == "" and c.cycle != 0:
		want = "secondary" if active == "primary" else "primary"
	if want != "" and want != active:
		var prev := active
		active = want
		draw_t = SWITCH_TIME
		fx.append({"type": "switch", "slot": want})
		for slot: String in [prev, want]:
			if state[slot].ammo == 0 and state[slot].reload_t == 0:
				start_reload(slot)
	draw_t = maxf(0.0, draw_t - dt)

	var w := weapon()
	var st := weapon_state()
	if c.reload and st.reload_t == 0 and st.ammo < mag_size():
		start_reload()

	fire_queued = SEMI_BUFFER if c.fire_pressed else maxf(0.0, fire_queued - dt)
	var want_fire: bool = c.fire if w.auto else fire_queued > 0
	if want_fire and draw_t == 0 and st.reload_t == 0 and time >= st.next_fire:
		if st.ammo <= 0:
			start_reload()
		else:
			fire_queued = 0.0
			_fire(p, c, w)
			st.ammo -= 1
			st.next_fire = time + 1.0 / up.fire_rate(w.fire_rate)
			if st.ammo == 0:
				start_reload()

	ability_cd = maxf(0.0, ability_cd - dt)
	if c.ability and ability_cd == 0:
		_throw_ability(p, c)

	_update_projectiles(p, dt)


func start_reload(slot := "") -> void:
	if slot == "":
		slot = active
	state[slot].reload_t = up.reload_time(slots[slot].reload)
	state[slot].reload_len = state[slot].reload_t
	# Only the gun in your hands makes reload noise/animation.
	if slot == active:
		fx.append({"type": "reload", "weapon": slots[slot].id})


# ---------- aiming ----------

static func aim_dir(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


## A random direction inside a cone of `degrees` around d (uniform over the disc).
static func spread_dir(d: Vector3, degrees: float) -> Vector3:
	if degrees == 0:
		return d
	var up := Vector3(1, 0, 0) if absf(d.y) > 0.99 else Vector3(0, 1, 0)
	var right := d.cross(up).normalized()
	var up2 := right.cross(d)
	var angle := deg_to_rad(degrees) * sqrt(randf())
	var phi := randf() * TAU
	var off := right * cos(phi) + up2 * sin(phi)
	return (d * cos(angle) + off * sin(angle)).normalized()


static func eye_position(p: PlayerSim) -> Vector3:
	return Vector3(p.px, p.eye_y(), p.pz)


# ---------- raycasting ----------

static func _box_min(b: MapData.Box, axis: int) -> float:
	return b.min_x if axis == 0 else b.min_y if axis == 1 else b.min_z


static func _box_max(b: MapData.Box, axis: int) -> float:
	return b.max_x if axis == 0 else b.max_y if axis == 1 else b.max_z


## A ramp's sloped top as the half-space n·p <= c (world.js rampPlane).
static func ramp_plane(b: MapData.Box) -> Array:
	var s := MapData.ramp_slope(b)
	var n := Vector3(0, 1, 0)
	n[b.ramp_axis] = -b.ramp_dir * s
	var c := b.min_y - s * _box_min(b, b.ramp_axis) if b.ramp_dir > 0 else b.min_y + s * _box_max(b, b.ramp_axis)
	return [n, c]


## Ray vs box (slab method), clipped by a ramp's slope. Returns [t, normal] or [] on a miss.
## Rays starting inside are ignored.
static func ray_box(o: Vector3, d: Vector3, b: MapData.Box, max_t: float) -> Array:
	var tmin := 0.0
	var tmax := max_t
	var axis := -1
	var sign := 0.0
	for a in 3:
		var lo := _box_min(b, a)
		var hi := _box_max(b, a)
		if absf(d[a]) < 1e-9:
			if o[a] < lo or o[a] > hi:
				return []
			continue
		var t1 := (lo - o[a]) / d[a]
		var t2 := (hi - o[a]) / d[a]
		var s := -1.0
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
			s = 1.0
		if t1 > tmin:
			tmin = t1
			axis = a
			sign = s
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return []
	var plane_n := Vector3.ZERO
	if b.ramp_axis >= 0:
		var rp := ramp_plane(b)
		var n: Vector3 = rp[0]
		var c: float = rp[1]
		var denom := n.dot(d)
		var dist := c - n.dot(o)
		if absf(denom) < 1e-9:
			if dist < 0:
				return []
		else:
			var t := dist / denom
			if denom < 0:
				if t > tmin:
					tmin = t
					plane_n = n
			else:
				tmax = minf(tmax, t)
			if tmin > tmax:
				return []
	if plane_n != Vector3.ZERO:
		return [tmin, plane_n.normalized()]
	if axis < 0:
		return []
	var normal := Vector3.ZERO
	normal[axis] = sign
	return [tmin, normal]


static func closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var len2 := ab.dot(ab)
	var t := clampf((p - a).dot(ab) / (len2 if len2 > 0 else 1.0), 0, 1)
	return a + ab * t


## Ray vs capsule (segment a→b, radius r). d must be normalized. Returns t, or -1 on a miss.
static func ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float, max_t: float) -> float:
	var ba := b - a
	var oa := o - a
	var baba := ba.dot(ba)
	var bard := ba.dot(d)
	var baoa := ba.dot(oa)
	var rdoa := d.dot(oa)
	var oaoa := oa.dot(oa)
	var qa := baba - bard * bard
	var qb := baba * rdoa - baoa * bard
	var qc := baba * oaoa - baoa * baoa - r * r * baba
	var h := qb * qb - qa * qc
	if h < 0:
		return -1.0
	if qa > 1e-9:
		var t := (-qb - sqrt(h)) / qa
		var y := baoa + t * bard
		if y > 0 and y < baba:
			return t if t >= 0 and t <= max_t else -1.0
	# End caps (spheres).
	for cap: Vector3 in [a, b]:
		var oc := o - cap
		var b2 := d.dot(oc)
		var c2 := oc.dot(oc) - r * r
		var h2 := b2 * b2 - c2
		if h2 > 0:
			var t := -b2 - sqrt(h2)
			if t >= 0 and t <= max_t:
				return t
	return -1.0


## First thing a ray hits (walls and dummies), or null.
## pad: extra radius on every dummy part (projectiles have size; knives get extra forgiveness).
## with_targets false = walls only.
func raycast(o: Vector3, d: Vector3, max_t: float, pad := 0.0, with_targets := true) -> Hit:
	var best: Hit = null
	for b in (grid.ray_boxes(o, d, max_t) if grid else boxes):
		if b.kind == "barrier":
			continue # invisible walls only stop players
		var h := ray_box(o, d, b, best.t if best else max_t)
		if not h.is_empty():
			best = Hit.new()
			best.t = h[0]
			best.normal = h[1]
	if with_targets:
		for tg in targets:
			if tg.dead:
				continue
			for part: Dictionary in DUMMY_PARTS:
				var a: Vector3 = tg.pos + part.a * tg.size
				var b: Vector3 = tg.pos + part.b * tg.size
				# Heads only get half the padding so body throws don't turn into free headshots.
				var r: float = part.r * tg.size + (pad * 0.5 if part.zone == "head" else pad)
				var t := ray_capsule(o, d, a, b, r, best.t if best else max_t)
				if t >= 0:
					var point := o + d * t
					best = Hit.new()
					best.t = t
					best.normal = (point - closest_on_segment(point, a, b)).normalized()
					best.target = tg
					best.zone = part.zone
	if best:
		best.point = o + d * best.t
		# With padded hitboxes the fat body can reach out in front of the head: pick the zone
		# whose real (unpadded) shape the path passes closest to.
		if best.target and pad > 0:
			best.zone = _closest_zone(best.target, o, d, best.t, pad)
	return best


func _closest_zone(target: Target, o: Vector3, d: Vector3, t0: float, pad: float) -> String:
	var best_zone := "body"
	var best_gap := INF
	for i in 13:
		var p := o + d * (t0 + (i / 12.0) * (pad * 2 + 0.8))
		for part: Dictionary in DUMMY_PARTS:
			var a: Vector3 = target.pos + part.a * target.size
			var b: Vector3 = target.pos + part.b * target.size
			var gap: float = (p - closest_on_segment(p, a, b)).length() - part.r * target.size
			if gap < best_gap:
				best_gap = gap
				best_zone = part.zone
	return best_zone


static func zone_mult(zone: String, head_mult: float) -> float:
	return head_mult if zone == "head" else 1.0


## src: "gun" (your weapons: items proc on these), "dot" (burn/bleed ticks, dot = which) or
## "item" (item explosions, lightning, wisps).
func damage_target(t: Target, dmg: float, zone: String, point: Vector3, src := "gun", dot := "") -> void:
	if t.dead:
		return
	if t.body and t.body.invuln > 0:
		return # spawn protection
	if t.kind == "remote":
		# Another online player on our screen: the shot stops on them, but the server decides the
		# damage (and sends the hit back so the hitmarker only shows real hits).
		fx.append({"type": "impact", "pos": point, "normal": Vector3.UP, "on_player": true})
		return
	var crit := false
	if up.active:
		var m := up.modify_damage(t, dmg, zone, point, src)
		dmg = m[0]
		crit = m[1]
	t.hp -= dmg
	var kill := t.hp <= 0
	if kill:
		t.dead = true
		t.hp = 0.0
		t.respawn_t = DUMMY_RESPAWN
	if src == "gun":
		last_hit = {"dmg": dmg, "zone": zone, "kill": kill, "time": time}
	fx.append({"type": "hit", "target": t.id, "pos": point, "dmg": dmg, "zone": zone, "kill": kill,
		"src": src, "crit": crit, "dot": dot})
	if up.active:
		if src == "gun":
			up.on_hit(t, dmg, zone, point)
		if kill:
			up.on_kill(t)


# ---------- firing ----------

func _fire(p: PlayerSim, c: Cmd, w: Dictionary) -> void:
	var o := eye_position(p)
	var dirs := up.fire_dirs(aim_dir(c.yaw, c.pitch)) # just the aim, unless Triple Tap
	if w.type == "hitscan":
		var ends: Array[Vector3] = []
		var per_target := {} # add up pellets so a shotgun blast counts as one hit per dummy
		var bounces: Array[Vector3] = [] # wall hits Ricochet may bounce
		for d in dirs:
			for i in int(w.pellets):
				var dir := spread_dir(d, w.spread)
				var hit := raycast(o, dir, w.range)
				ends.append(hit.point if hit else o + dir * float(w.range))
				if hit and hit.target:
					var acc: Dictionary = per_target.get(hit.target, {"dmg": 0.0, "zone": hit.zone, "point": hit.point})
					acc.dmg += w.damage * zone_mult(hit.zone, w.head_mult)
					if hit.zone == "head":
						acc.zone = "head"
					per_target[hit.target] = acc
				elif hit:
					fx.append({"type": "impact", "pos": hit.point, "normal": hit.normal})
					bounces.append(hit.point + hit.normal * 0.1)
		for t: Target in per_target:
			damage_target(t, per_target[t].dmg, per_target[t].zone, per_target[t].point)
		if up.count("ricochet") > 0:
			for b in bounces:
				up.ricochet(b, w.damage)
		fx.append({"type": "shot", "weapon": w.id, "origin": o, "ends": ends})
	else:
		for i in dirs.size():
			_spawn_projectile(w.id, w.projectile, o, dirs[i], false, p).copy = i > 0
		fx.append({"type": "shot", "weapon": w.id, "origin": o, "ends": []})
	if w.knockback > 0:
		# From the 64-bit yaw/pitch directly, so the push matches the web game as closely as it can.
		var cp := cos(c.pitch)
		var k: float = w.knockback
		p.apply_impulse(sin(c.yaw) * cp * k, -sin(c.pitch) * k, cos(c.yaw) * cp * k, w.name)


func _throw_ability(p: PlayerSim, c: Cmd) -> void:
	if ability.has("dash"):
		_dash(p, c)
		return
	var dirs := up.fire_dirs(aim_dir(c.yaw, c.pitch))
	for i in dirs.size():
		_spawn_projectile(ability.id, ability.projectile, eye_position(p), dirs[i], ability.projectile.get("inherit", true), p).copy = i > 0
	ability_cd = ability.cooldown
	fx.append({"type": "throw", "ability": ability.id})


## Combat Dash: at least dash.speed along your aim (flattened), plus a little hop.
func _dash(p: PlayerSim, c: Cmd) -> void:
	var d: Dictionary = ability.dash
	var dx := -sin(c.yaw)
	var dz := -cos(c.yaw)
	var along := p.vx * dx + p.vz * dz
	var push := maxf(0.0, float(d.speed) - along)
	# (an upward impulse first stops any fall, so the hop is up to d.up from there)
	p.apply_impulse(dx * push, maxf(0.0, float(d.up) - maxf(p.vy, 0.0)), dz * push, ability.name)
	ability_cd = ability.cooldown
	fx.append({"type": "dash", "ability": ability.id})


func _spawn_projectile(kind: String, def: Dictionary, origin: Vector3, d: Vector3, inherit: bool, p: PlayerSim) -> Projectile:
	var pr := Projectile.new()
	pr.id = _next_projectile
	_next_projectile += 1
	pr.kind = kind
	pr.def = def
	pr.vel = d * float(def.speed) + Vector3(0, def.get("up", 0.0), 0)
	if inherit:
		pr.vel += Vector3(p.vx, maxf(0.0, p.vy) * 0.5, p.vz)
	pr.pos = origin + d * 0.5
	projectiles.append(pr)
	return pr


## A projectile an item made (Wisp Jar): starts right at `pos`, never procs.
func spawn_item_projectile(kind: String, def: Dictionary, pos: Vector3, d: Vector3) -> void:
	var pr := _spawn_projectile(kind, def, pos - d * 0.5, d, false, null)
	pr.src = "item"


func _update_projectiles(p: PlayerSim, dt: float) -> void:
	for pr in projectiles:
		pr.age += dt
		var def := pr.def
		if pr.stuck:
			if pr.age > 4:
				pr.alive = false
			continue
		if def.has("fuse") and pr.age >= def.fuse:
			_explode(pr.pos, def.explode, p, pr.kind, not pr.copy)
			pr.alive = false
			continue
		if pr.age > def.get("life", 8.0):
			pr.alive = false
			continue
		if pr.resting:
			continue

		pr.vel.y -= def.get("gravity", 0.0) * dt
		if def.has("homing"):
			_home(pr, float(def.homing) * dt)
		var speed := pr.vel.length()
		var dir := pr.vel / (speed if speed > 0 else 1.0)
		var hit := raycast(pr.pos, dir, speed * dt + def.radius, def.radius + def.get("hit_pad", 0.0))
		if hit == null:
			pr.pos += pr.vel * dt
			continue
		match def.impact:
			"explode":
				_explode(hit.point - dir * 0.1, def.explode, p, pr.kind, not pr.copy)
				pr.alive = false
			"wisp":
				if hit.target:
					damage_target(hit.target, def.damage, "body", hit.point, pr.src)
				fx.append({"type": "impact", "pos": hit.point, "normal": hit.normal, "small": true})
				pr.alive = false
			"stick":
				if hit.target:
					damage_target(hit.target, def.damage * zone_mult(hit.zone, def.head_mult), hit.zone, hit.point, pr.src)
					pr.alive = false
				else:
					pr.pos = hit.point - dir * float(def.radius)
					pr.stuck = true
					pr.age = 0.0
					fx.append({"type": "impact", "pos": hit.point, "normal": hit.normal})
			"bounce":
				var n := hit.normal
				pr.vel = (pr.vel - n * (2 * pr.vel.dot(n))) * float(def.bounce)
				pr.pos = hit.point + n * (def.radius + 0.01)
				if pr.vel.length() < 1.5 and n.y > 0.7:
					pr.vel = Vector3.ZERO
					pr.resting = true
	projectiles = projectiles.filter(func(pr: Projectile) -> bool: return pr.alive)


## Turn a homing projectile toward the nearest living enemy (by at most `turn` radians).
func _home(pr: Projectile, turn: float) -> void:
	var best: Target = null
	var best_d := 40.0
	for t in targets:
		if not t.dead and t.kind in ["enemy", "dummy"]:
			var d := pr.pos.distance_to(t.pos + Vector3(0, t.size, 0))
			if d < best_d:
				best = t
				best_d = d
	if best == null:
		return
	var want := (best.pos + Vector3(0, best.size, 0) - pr.pos).normalized()
	var speed := pr.vel.length()
	var cur := pr.vel / maxf(speed, 0.001)
	var ang := cur.angle_to(want)
	if ang > 0.0001:
		var axis := cur.cross(want)
		cur = cur.rotated(axis.normalized(), minf(ang, turn)) if axis.length() > 1e-6 else want
	pr.vel = cur * speed


## An item's explosion (Big Bang, Party Popper, Sticky Bomb, Stomp Boots): hurts enemies and
## dummies only, never pushes you, never procs.
func item_explosion(pos: Vector3, radius: float, dmg: float, kind: String) -> void:
	for t in targets:
		if t.dead or t.kind not in ["enemy", "dummy"]:
			continue
		var d := maxf(0.0, pos.distance_to(t.pos + Vector3(0, 0.9 * t.size, 0)) - 0.5 * t.size)
		if d < radius:
			damage_target(t, dmg * (1 - 0.5 * (d / radius)), "body", t.pos + Vector3(0, 1.2 * t.size, 0), "item")
	fx.append({"type": "explosion", "pos": pos, "radius": radius, "kind": kind, "small": true})


## self_knock false: a Triple Tap copy's blast doesn't launch you (only the real one does).
func _explode(pos: Vector3, e: Dictionary, p: PlayerSim, kind: String, self_knock := true) -> void:
	for t in targets:
		if t.dead:
			continue
		var d_min := INF
		for part: Dictionary in DUMMY_PARTS:
			var a: Vector3 = t.pos + part.a * t.size
			var b: Vector3 = t.pos + part.b * t.size
			d_min = minf(d_min, maxf(0.0, (pos - closest_on_segment(pos, a, b)).length() - part.r * t.size))
		if d_min < e.radius:
			var dmg: float = e.damage * (1 - 0.6 * (d_min / e.radius))
			damage_target(t, dmg, "body", t.pos + Vector3(0, 1.2, 0))
			# Players have real bodies: explosions launch them too.
			if t.body and not t.dead:
				var kdir := ((t.pos + Vector3(0, 0.9, 0) - pos).normalized() + Vector3(0, 0.5, 0)).normalized()
				var ks: float = e.knockback * (1 - 0.5 * (d_min / e.radius))
				t.body.apply_impulse(kdir.x * ks, kdir.y * ks, kdir.z * ks, kind)

	# Knockback on the player (no self-damage).
	if not self_knock:
		fx.append({"type": "explosion", "pos": pos, "radius": e.radius, "kind": kind})
		return
	var hw := Cfg.PLAYER_HALF_WIDTH
	var closest := Vector3(
		clampf(pos.x, p.px - hw, p.px + hw),
		clampf(pos.y, p.py, p.py + p.height),
		clampf(pos.z, p.pz - hw, p.pz + hw))
	var d := (pos - closest).length()
	if d < e.radius:
		var center := Vector3(p.px, p.py + p.height / 2, p.pz)
		# Bias upward so explosions always lift a bit: rocket/grenade jumps feel consistent.
		var dir := ((center - pos).normalized() + Vector3(0, 0.5, 0)).normalized()
		var strength: float = e.knockback * (1 - 0.5 * (d / e.radius))
		p.apply_impulse(dir.x * strength, dir.y * strength, dir.z * strength, kind)
	fx.append({"type": "explosion", "pos": pos, "radius": e.radius, "kind": kind})


func _update_targets(p: PlayerSim, dt: float) -> void:
	for t in targets:
		if t.kind != "dummy":
			continue # players respawn on the server's clock
		if t.dead:
			t.respawn_t -= dt
			if t.respawn_t <= 0:
				t.dead = false
				t.hp = t.max_hp
		if not t.move.is_empty():
			var axis := 0 if t.move.axis == "x" else 2
			t.pos[axis] = t.base[axis] + sin(time * float(t.move.speed)) * float(t.move.amp)
