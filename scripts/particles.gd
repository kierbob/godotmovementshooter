class_name Particles
extends RefCounted
## Pooled cartoon particles (the web game's particles.js): chunky low-poly puffs and cubes that
## grow, drift, fade and change color. Fire and sparks are unlit (bright); smoke, debris and bean
## juice are "lit" with toon bands so they read as solid cartoon blobs.

const PER_KIND := 160

static var _puff: Mesh
static var _cube: Mesh

var live: Array[Dictionary] = []
var _free := {"basic": [], "lit": []}
var _fill := 0.6 # how much the "lit" ones glow on their shaded side (stands in for the sky fill light)


## A pool of hidden meshes under `parent` (the world, or the viewmodel's own little world).
## fill: see _fill; the viewmodel's little world has less light, so it passes more.
func _init(parent: Node3D, per_kind := PER_KIND, fill := 0.6) -> void:
	_fill = fill
	if _puff == null:
		var s := SphereMesh.new() # a few big facets, like three.js IcosahedronGeometry(1, 0)
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 6
		s.rings = 3
		_puff = s
		var b := BoxMesh.new()
		_cube = b
	for kind: String in ["basic", "lit"]:
		for i in per_kind:
			var mi := MeshInstance3D.new()
			mi.mesh = _puff
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if kind == "basic":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			else:
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.emission_enabled = true # stands in for the sky fill light the toon shader adds
			mi.material_override = m
			mi.visible = false
			mi.set_meta("kind", kind)
			parent.add_child(mi)
			_free[kind].append(mi)


## o: {pos, vel?, gravity?, drag?, life, delay?, size: [from, to], color, color2?,
##     opacity?: [from, to], fade_start? (0..1 of life), lit?, cube?, spin?}
func spawn(o: Dictionary) -> void:
	var kind := "lit" if o.get("lit", false) else "basic"
	var mi: MeshInstance3D = _free[kind].pop_back() if not _free[kind].is_empty() else null
	if mi == null:
		# Pool used up: recycle the oldest live particle of this kind.
		for i in live.size():
			if live[i].mi.get_meta("kind") == kind:
				mi = live[i].mi
				live.remove_at(i)
				break
		if mi == null:
			return
	mi.mesh = _cube if o.get("cube", false) else _puff
	mi.position = o.pos
	mi.rotation = Vector3(randf() * 6, randf() * 6, randf() * 6)
	mi.visible = o.get("delay", 0.0) <= 0
	mi.scale = Vector3.ONE * float(o.size[0])
	live.append({
		"mi": mi, "age": 0.0, "delay": o.get("delay", 0.0), "life": float(o.life),
		"vel": o.get("vel", Vector3.ZERO), "gravity": o.get("gravity", 0.0), "drag": o.get("drag", 0.0),
		"size": o.size, "color": o.color, "color2": o.get("color2", o.color),
		"opacity": o.get("opacity", [1.0, 0.0]), "fade_start": o.get("fade_start", 0.0), "spin": o.get("spin", 0.0),
	})
	_paint(live.back(), 0.0)


func update(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for p in live:
		var mi: MeshInstance3D = p.mi
		if p.delay > 0:
			p.delay -= dt
			if p.delay > 0:
				keep.append(p)
				continue
			mi.visible = true
		p.age += dt
		var t: float = p.age / p.life
		if t >= 1:
			mi.visible = false
			_free[mi.get_meta("kind")].append(mi)
			continue
		var damp := maxf(0.0, 1.0 - p.drag * dt)
		var v: Vector3 = p.vel
		v.x *= damp
		v.z *= damp
		v.y = v.y * damp - p.gravity * dt
		p.vel = v
		mi.position += v * dt
		if p.spin != 0:
			mi.rotation.x += p.spin * dt
			mi.rotation.y += p.spin * 0.7 * dt
		_paint(p, t)
		keep.append(p)
	live = keep


## Size, color and opacity at time t (0..1). Ease-out growth reads as a cartoon "poof".
func _paint(p: Dictionary, t: float) -> void:
	var g := 1.0 - (1.0 - t) * (1.0 - t)
	(p.mi as MeshInstance3D).scale = Vector3.ONE * lerpf(p.size[0], p.size[1], g)
	var ft: float = 0.0 if t <= p.fade_start else (t - p.fade_start) / (1.0 - p.fade_start)
	var c: Color = (p.color as Color).lerp(p.color2, t)
	c.a = lerpf(p.opacity[0], p.opacity[1], ft)
	var m := (p.mi as MeshInstance3D).material_override as StandardMaterial3D
	m.albedo_color = c
	if m.emission_enabled:
		m.emission = Color(c.r, c.g, c.b) * _fill


## Hide everything (new run).
func clear() -> void:
	for p in live:
		(p.mi as MeshInstance3D).visible = false
		_free[(p.mi as MeshInstance3D).get_meta("kind")].append(p.mi)
	live.clear()
