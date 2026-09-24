class_name CombatView
extends Node3D
## Everything combat draws in the world, ported from the web game's fx.js: flying projectiles and
## their smoke trails, tracers, bullet holes, comic POW stars, bean-juice splats, cartoon
## explosions (fireball, smoke, debris, shockwave ring, a flash of light), and the guns you chuck
## away when reloading. Reads Combat; never changes it. Asks the HUD for comic words via `word`.

## A comic word: world_pos (Vector3) or screen_pos (Vector2, 0..1) says where; style is
## "small" | "big" | "head" | "kill" | "blue".
signal word(text: String, world_pos: Variant, screen_pos: Variant, style: String)

const EXPLOSION_COLOR := {"rocket": Color("ff8a30"), "frag": Color("ff7a20"), "impulse": Color("40d8ff")}

var shake := 0.0 # camera shake amount; main.gd applies it and it decays here
var particles: Particles
var _time := 0.0
var _combat: Combat
var _meshes := {} # Combat.Projectile -> Node3D
var _tracers: Array = [] # [{node, life}]
var _next_tracer := 0
var _decals: Array = [] # [{node, age}]
var _next_decal := 0
var _stars: Array = [] # [{node, age, life, size}]
var _next_star := 0
var _rings: Array = [] # [{node, life, max, from, to, opacity}]
var _ring_mesh: ArrayMesh
var _lights: Array = [] # [{light, life}]
var _next_light := 0
var _muzzle_light: OmniLight3D
var _held := {} # weapon id -> world-size gun to clone when tossing
var _tossed: Array = [] # [{node, vel, spin, age}]
var _star_tex: Texture2D


func _ready() -> void:
	_star_tex = Models.texture("res://assets/fx/star.png")
	var holes: Array[Texture2D] = []
	for i in 3:
		holes.append(Models.texture("res://assets/fx/hole_%d.png" % i))
	particles = Particles.new(self)
	for i in 48:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 0.012, 1)
		mi.mesh = b
		mi.material_override = _flat(Color("fff2a0"), 0.9)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"node": mi, "life": 0.0})
	var quad := QuadMesh.new()
	for i in 80:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := _flat(Color.WHITE, 1.0)
		m.albedo_texture = holes[i % 3]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_decals.append({"node": mi, "age": 0.0})
	for i in 24:
		var sp := Sprite3D.new()
		sp.texture = _star_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		sp.transparent = true
		sp.visible = false
		add_child(sp)
		_stars.append({"node": sp, "age": 0.0, "life": 0.0, "size": 0.0})
	# Pooled lights: adding lights while playing makes the renderer stutter.
	for i in 2:
		var l := OmniLight3D.new()
		l.omni_range = 14
		l.light_energy = 0
		add_child(l)
		_lights.append({"light": l, "life": 0.0})
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color("ffd27a")
	_muzzle_light.omni_range = 8
	_muzzle_light.light_energy = 0
	add_child(_muzzle_light)
	_ring_mesh = _make_ring(0.82, 1.0, 40)
	# Templates stay in the tree (hidden) so they're freed with it.
	for id: String in Items.WEAPONS:
		var g := Models.held_gun(id, float(Items.MODELS[id].length) * 1.1)
		if g:
			g.visible = false
			add_child(g)
		_held[id] = g


static func _flat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Flat ring lying on the ground (three.js RingGeometry), seen from above and below.
static func _make_ring(inner: float, outer: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1))]
		for v: Vector3 in [p[0] * inner, p[0] * outer, p[1] * outer, p[0] * inner, p[1] * outer, p[1] * inner]:
			st.add_vertex(v)
	return st.commit()


static func _rand_unit() -> Vector3:
	var u := randf() * 2 - 1
	var t := randf() * TAU
	var s := sqrt(1 - u * u)
	return Vector3(s * cos(t), u, s * sin(t))


# ---------- events ----------

## React to this frame's combat events. muzzle = where the gun's barrel is in the world.
func on_events(events: Array[Dictionary], muzzle: Vector3, player: PlayerSim) -> void:
	for e in events:
		match e.type:
			"shot":
				var w: Dictionary = Items.WEAPONS[e.weapon]
				_muzzle_light.position = muzzle
				_muzzle_light.light_energy = 3.0
				for end: Vector3 in e.ends:
					_add_tracer(muzzle, end)
				if w.knockback > 0:
					shake = maxf(shake, w.knockback * 0.006)
			"hit":
				_hit_splat(e)
				if e.get("quiet", false):
					pass # someone else's hit, online: just the splat
				elif e.kill:
					word.emit("SPLAT!", e.pos, null, "kill")
				elif e.zone == "head" and randf() < 0.5:
					word.emit("BONK!", e.pos, null, "head")
			"impact":
				if e.get("on_player", false):
					add_star(e.pos, 0.3, 0.08, Color("fff3b0")) # the shot stopped on another player: no hole in the air
				else:
					_impact(e.pos, e.normal)
			"explosion":
				_explosion(e.pos, e.radius, e.kind)
				var blue: bool = e.kind == "impulse"
				word.emit("BWOMP!" if blue else "KABOOM!", e.pos, null, "blue" if blue else "big")
				var slot: Dictionary = _lights[_next_light % _lights.size()]
				_next_light += 1
				var l: OmniLight3D = slot.light
				l.light_color = EXPLOSION_COLOR.get(e.kind, Color("ff8a30"))
				l.position = e.pos + Vector3(0, 0.3, 0)
				slot.life = 0.25
				var d := (e.pos as Vector3).distance_to(Vector3(player.px, player.py, player.pz))
				shake = maxf(shake, maxf(0.0, 0.06 * (1 - d / 15)))


## Another online player fired: a flash at their gun and tracers from it (no comic words, they're
## not yours).
func remote_shot(e: Dictionary, gun: Vector3) -> void:
	add_star(gun, 0.28, 0.06, Color("fff3a0"))
	for end: Vector3 in e.get("ends", []):
		_add_tracer(gun, end)


## A tracer line (enemy snipers use it too).
func tracer(from: Vector3, to: Vector3) -> void:
	_add_tracer(from, to)


func _add_tracer(from: Vector3, to: Vector3) -> void:
	var t: Dictionary = _tracers[_next_tracer % _tracers.size()]
	_next_tracer += 1
	var node: MeshInstance3D = t.node
	var length := from.distance_to(to)
	if length < 0.3: # hit something right in front of the gun: nothing to draw
		return
	var dir := (to - from) / length
	# Stretch along the tracer's own axis (Basis.scaled would stretch along the world's Z and skew it).
	node.basis = Basis.looking_at(dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP) * Basis.from_scale(Vector3(1, 1, length))
	node.position = (from + to) / 2
	node.visible = true
	t.life = 0.07


func _add_decal(pos: Vector3, n: Vector3) -> void:
	var d: Dictionary = _decals[_next_decal % _decals.size()]
	_next_decal += 1
	var node: MeshInstance3D = d.node
	# The quad faces +Z; turn +Z to the surface normal, then spin it randomly around that.
	var b := Basis.looking_at(-n, Vector3.RIGHT if absf(n.y) > 0.99 else Vector3.UP)
	node.basis = b.rotated(n, randf() * TAU).scaled(Vector3.ONE * randf_range(0.16, 0.22))
	node.position = pos + n * 0.01
	(node.material_override as StandardMaterial3D).albedo_color.a = 1.0
	node.visible = true
	d.age = 0.0


func add_star(pos: Vector3, size: float, life: float, color := Color.WHITE) -> void:
	var st: Dictionary = _stars[_next_star % _stars.size()]
	_next_star += 1
	var sp: Sprite3D = st.node
	sp.position = pos
	sp.modulate = color
	sp.visible = true
	st.age = 0.0
	st.life = life
	st.size = size


func _add_ring(pos: Vector3, color: Color, from: float, to: float, life: float, opacity: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	var m := _flat(color, opacity)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * from
	add_child(mi)
	_rings.append({"node": mi, "life": life, "max": life, "from": from, "to": to, "opacity": opacity})


## A bullet hitting a wall: hole, little star, grey chips, a puff of dust.
func _impact(pos: Vector3, n: Vector3) -> void:
	_add_decal(pos, n)
	add_star(pos + n * 0.08, 0.35, 0.1, Color("fff3b0"))
	for i in 4:
		var r := _rand_unit()
		particles.spawn({
			"cube": true, "lit": true, "pos": pos, "life": randf_range(0.35, 0.55), "gravity": 18.0, "spin": 14.0,
			"vel": n * randf_range(2, 4) + r * 2 + Vector3(0, 2, 0),
			"size": [0.07, 0.04], "color": Color("9aa3b5"), "opacity": [1.0, 1.0],
		})
	particles.spawn({"pos": pos, "life": 0.22, "size": [0.08, 0.3], "color": Color.WHITE, "opacity": [0.8, 0.0]})


## Bean juice! Orange blobs and a comic star: yellow on headshots, red on kills.
func _hit_splat(e: Dictionary) -> void:
	var head: bool = e.zone == "head"
	var color := Color("ffc766") if head else Color("ff8a3d")
	var count := 14 if e.kill else 9 if head else 6
	for i in count:
		var r := _rand_unit()
		particles.spawn({
			"lit": true, "pos": e.pos, "life": randf_range(0.4, 0.7), "gravity": 14.0, "drag": 0.5,
			"vel": Vector3(r.x * randf_range(2, 4), absf(r.y) * 3 + 1.5, r.z * randf_range(2, 4)),
			"size": [randf_range(0.07, 0.11), 0.03], "color": color, "opacity": [1.0, 1.0],
		})
	add_star(e.pos, 0.9 if e.kill else 0.6 if head else 0.4, 0.18 if e.kill else 0.12,
		Color("ff5a5a") if e.kill else Color("ffe066") if head else Color.WHITE)


func _explosion(pos: Vector3, radius: float, kind: String) -> void:
	var k := radius / 4.5
	var impulse := kind == "impulse"
	var pal := [Color("eaffff"), Color("3fd8ff"), Color("1f5cff")] if impulse else [Color("ffe14d"), Color("ff7a1a"), Color("d8321a")]
	# White flash core
	particles.spawn({"pos": pos, "life": 0.12, "size": [0.4, 2.2 * k], "color": Color.WHITE, "color2": pal[0], "opacity": [1.0, 0.0]})
	# Fireball: chunky puffs thrown outward that burn from yellow to red
	for i in 12:
		var d := _rand_unit()
		d.y = absf(d.y) * 0.8 + 0.15
		particles.spawn({
			"pos": pos + d * 0.3, "vel": d * randf_range(4, 8) * k, "drag": 5.0,
			"life": randf_range(0.35, 0.55), "size": [0.4 * k, randf_range(0.9, 1.5) * k],
			"color": pal[0], "color2": pal[2], "opacity": [1.0, 0.0], "fade_start": 0.6,
		})
	if not impulse:
		# Cartoon smoke: fat grey toon puffs that billow up and linger
		for i in 10:
			particles.spawn({
				"lit": true, "delay": randf_range(0.06, 0.2),
				"pos": pos + Vector3(randf_range(-0.8, 0.8), randf_range(0, 0.8), randf_range(-0.8, 0.8)) * k,
				"vel": Vector3(randf_range(-1, 1), randf_range(1, 2.2), randf_range(-1, 1)), "drag": 1.2,
				"life": randf_range(1.4, 2.2), "size": [0.5 * k, randf_range(1.1, 1.7) * k],
				"color": Color("c4c9d2"), "color2": Color("70757f"), "opacity": [0.95, 0.0], "fade_start": 0.5,
			})
		# Chunks of debris
		for i in 6:
			var d := _rand_unit()
			particles.spawn({
				"cube": true, "lit": true, "pos": pos, "gravity": 20.0, "spin": 12.0, "life": randf_range(0.7, 1.0),
				"vel": Vector3(d.x * 4, randf_range(5, 9), d.z * 4), "size": [0.13, 0.07], "color": Color("3a3f4b"),
				"opacity": [1.0, 1.0],
			})
	else:
		# Impulse: electric sparkles instead of smoke
		for i in 16:
			var d := _rand_unit()
			particles.spawn({
				"cube": true, "pos": pos, "gravity": 6.0, "drag": 2.0, "spin": 20.0, "life": randf_range(0.35, 0.6),
				"vel": d * randf_range(6, 10), "size": [0.09, 0.02], "color": Color("bff8ff"), "opacity": [1.0, 1.0],
			})
	_add_ring(pos, pal[1], 0.3, radius * 1.15, 0.3, 0.8)


## Smoke trails behind flying projectiles.
func _trail(pr: Combat.Projectile, mesh: Node3D, dt: float) -> void:
	var every := 0.018 if pr.kind == "rocket" else 0.035
	var left: float = mesh.get_meta("trail_t", 0.0) - dt
	mesh.set_meta("trail_t", left)
	if left > 0 or pr.stuck or pr.resting:
		return
	mesh.set_meta("trail_t", every)
	var back := pr.pos - pr.vel.normalized() * 0.3
	var jitter := Vector3(randf_range(-0.4, 0.4), randf_range(0, 0.6), randf_range(-0.4, 0.4))
	match pr.kind:
		"rocket":
			particles.spawn({"lit": true, "pos": back, "vel": jitter, "drag": 2.0, "life": 0.6, "size": [0.12, 0.42],
				"color": Color("e4e7ec"), "color2": Color("9aa0a8"), "opacity": [0.9, 0.0], "fade_start": 0.3})
			particles.spawn({"pos": back, "life": 0.08, "size": [0.14, 0.04], "color": Color("ffc040"), "opacity": [1.0, 0.6]})
		"frag":
			particles.spawn({"pos": back, "vel": jitter, "life": 0.3, "size": [0.06, 0.16], "color": Color.WHITE, "opacity": [0.6, 0.0]})
		"impulse":
			particles.spawn({"cube": true, "pos": back, "vel": jitter, "spin": 15.0, "life": 0.3, "size": [0.06, 0.01],
				"color": Color("7ff6ff"), "opacity": [1.0, 0.5]})


# ---------- the reload toss ----------

## Reloading: the empty gun gets flung out to the right from in front of the camera, spins,
## bounces off the world and poofs away.
func toss_gun(id: String, cam: Camera3D, player: PlayerSim) -> void:
	if randf() < 0.3:
		word.emit(["YEET!", "BYE!", "TOSS!"].pick_random(), null, Vector2(0.68, 0.62), "small")
	var tpl: Node3D = _held.get(id)
	if tpl == null:
		return
	var obj := tpl.duplicate() as Node3D
	obj.visible = true
	add_child(obj)
	var b := cam.global_transform.basis
	obj.global_transform = Transform3D(b, cam.global_transform * Vector3(0.35, -0.2, -0.6))
	var vel := -b.z * 3 + b.x * randf_range(4, 6) + Vector3(0, randf_range(4, 6), 0)
	vel += Vector3(player.vx, maxf(0.0, player.vy), player.vz)
	_tossed.append({"node": obj, "vel": vel, "spin": Vector3(randf_range(-14, 14), randf_range(-8, 8), randf_range(-14, 14)), "age": 0.0})
	if _tossed.size() > 6:
		_remove_tossed(_tossed.pop_front())


func _remove_tossed(t: Dictionary) -> void:
	var node: Node3D = t.node
	particles.spawn({"pos": node.position, "life": 0.3, "size": [0.2, 0.7], "color": Color.WHITE, "opacity": [0.9, 0.0]})
	add_star(node.position, 0.5, 0.12)
	node.queue_free()


func _update_tossed(dt: float) -> void:
	var keep: Array = []
	for t: Dictionary in _tossed:
		var node: Node3D = t.node
		t.age += dt
		var vel: Vector3 = t.vel
		vel.y -= 20 * dt
		var sp := vel.length()
		if sp > 0.01 and _combat:
			var hit := _combat.raycast(node.position, vel / sp, sp * dt + 0.1, 0, false)
			if hit:
				# bounce off whatever it hit, losing energy
				vel = vel.bounce(hit.normal) * 0.45
				t.spin *= 0.6
				node.position = hit.point + hit.normal * 0.1
			else:
				node.position += vel * dt
		t.vel = vel
		node.rotation += (t.spin as Vector3) * dt
		if t.age > 1.6:
			_remove_tossed(t)
		else:
			keep.append(t)
	_tossed = keep


# ---------- per frame ----------

## extra: other online players' projectiles (drawn the same way, from snapshots).
func update(dt: float, combat: Combat, extra: Array = []) -> void:
	_combat = combat
	_time += dt
	var alive := {}
	for pr: Combat.Projectile in combat.projectiles + extra:
		alive[pr] = true
		var mesh: Node3D = _meshes.get(pr)
		if mesh == null:
			mesh = Models.projectile(pr.kind)
			add_child(mesh)
			_meshes[pr] = mesh
		var moved := mesh.position != pr.pos
		mesh.position = pr.pos
		if not pr.stuck and pr.vel.length() > 0.1:
			var fwd := pr.vel.normalized()
			mesh.basis = Basis.looking_at(fwd, Vector3.RIGHT if absf(fwd.y) > 0.99 else Vector3.UP)
		var spin := mesh.get_node_or_null("Spin") as Node3D
		if spin:
			spin.rotation.x = 0.0 if pr.stuck else -_time * 25
		if moved:
			_trail(pr, mesh, dt) # no trail puffs piling up while paused
	for pr: Variant in _meshes.keys():
		if not alive.has(pr):
			(_meshes[pr] as Node3D).queue_free()
			_meshes.erase(pr)

	for t: Dictionary in _tracers:
		if t.life <= 0:
			continue
		t.life -= dt
		var node: MeshInstance3D = t.node
		(node.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, t.life / 0.07) * 0.9
		node.visible = t.life > 0
	var rings_left: Array = []
	for r: Dictionary in _rings:
		r.life -= dt
		var k: float = 1.0 - maxf(0.0, r.life) / r.max
		var node: MeshInstance3D = r.node
		node.scale = Vector3.ONE * lerpf(r.from, r.to, sqrt(k))
		(node.material_override as StandardMaterial3D).albedo_color.a = r.opacity * (1 - k)
		if r.life > 0:
			rings_left.append(r)
		else:
			node.queue_free()
	_rings = rings_left
	particles.update(dt)
	_update_tossed(dt)
	# Bullet holes stay 10 s, then fade out over the last second.
	for d: Dictionary in _decals:
		var node: MeshInstance3D = d.node
		if not node.visible:
			continue
		d.age += dt
		if d.age > 10:
			node.visible = false
		elif d.age > 9:
			(node.material_override as StandardMaterial3D).albedo_color.a = 10 - d.age
	# Comic stars pop big then shrink away.
	for st: Dictionary in _stars:
		var sp: Sprite3D = st.node
		if not sp.visible:
			continue
		st.age += dt
		var t: float = st.age / st.life
		if t >= 1:
			sp.visible = false
			continue
		var s: float = st.size * (0.6 + t / 0.3 * 0.4 if t < 0.3 else 1 - (t - 0.3) * 0.6)
		sp.pixel_size = s / _star_tex.get_width()
		sp.modulate.a = 1.0 if t < 0.6 else 1 - (t - 0.6) / 0.4
	for slot: Dictionary in _lights:
		slot.life = maxf(0.0, slot.life - dt)
		(slot.light as OmniLight3D).light_energy = 8.0 * slot.life / 0.25
	_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - dt * 60)
	shake = maxf(0.0, shake - dt * 0.25)


## Drop everything (new run / map).
func clear() -> void:
	for pr: Variant in _meshes.keys():
		(_meshes[pr] as Node3D).queue_free()
	_meshes.clear()
	for r: Dictionary in _rings:
		(r.node as Node3D).queue_free()
	_rings.clear()
	for t: Dictionary in _tossed:
		(t.node as Node3D).queue_free()
	_tossed.clear()
	for d: Dictionary in _decals:
		(d.node as Node3D).visible = false
	for st: Dictionary in _stars:
		(st.node as Node3D).visible = false
	for t: Dictionary in _tracers:
		(t.node as Node3D).visible = false
		t.life = 0.0
	particles.clear()
	shake = 0.0
