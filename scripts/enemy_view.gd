class_name EnemyView
extends Node3D
## Draws the enemies (Enemies is the logic): angry beans in each type's color with something that
## says what they do (charger horns, brute shoulder plates, swarmer spikes, a gun for gunners and
## snipers, a grenade for lobbers, a propeller on flyers, a cross on healers), a health bar, and a
## red "!" plus a glow during every windup. Also their attacks: the sniper's laser (red while it
## tracks, white once it locks), beams (magenta damage, green heal), the lobber's landing ring, the
## brute's shockwave ring, and their glowing shots.
##
## Lines are kept calm in a crowd: a tracking laser is faint and stops just past you (not 80 m on
## across the map), only the MAX_TRACKING nearest are drawn (a locked one, the cue to move, always
## is), and healers' beams are thin and dim (they never hurt you).

const BAR_Y := 2.25
const DETAIL_RANGE := 45.0 # past this, eyes / brows / gear aren't drawn (a few pixels anyway)
const BAR_RANGE := 60.0
const MAX_TRACKING := 3 # tracking sniper lasers drawn at once (the nearest)
const HEAL_BEAM_RANGE := 45.0

var _views := {} # enemy id -> {node, body, mats, fill, bang, laser, beam, spin, flash}
var _proj := {} # projectile id -> mesh (not the Dictionary itself: its hash changes as it moves)
var _markers: Array = [] # [{node, life}] lobber landing rings
var _waves: Array = [] # [{node, id}] brute shockwaves
var _time := 0.0
var _glow_cache := {}
var _tracking := {} # sniper ids whose tracking laser is drawn this frame
var _cam := Vector3.ZERO
var particles: Particles # the world's particles (main hands CombatView's over), for status effects


func update(en: Enemies, camera: Camera3D, dt: float) -> void:
	_time += dt
	_cam = camera.global_position if camera else Vector3.ZERO
	_pick_tracking(en)
	var seen := {}
	for e in en.list:
		seen[e.id] = true
		var v: Dictionary = _views.get(e.id, {})
		if v.is_empty():
			v = _make(e)
			_views[e.id] = v
		var node: Node3D = v.node
		node.position = e.target.pos
		node.rotation.y = e.yaw + PI # the bean faces +Z; yaw 0 looks down -Z
		var dist := camera.global_position.distance_to(node.position) if camera else 10.0
		var near := dist < DETAIL_RANGE
		if near != v.near:
			v.near = near
			for d: Node3D in v.detail:
				d.visible = near
		# health bar: only once it's hurt (Risk of Rain style), facing the camera; not right in your
		# face (a swarmer at your feet would cover the screen) or far away
		var frac: float = e.target.hp / e.target.max_hp
		var bar: Node3D = v.bar
		bar.visible = frac < 0.999 and dist > 2.5 and dist < BAR_RANGE
		if bar.visible:
			if camera:
				bar.global_rotation = Vector3(0, camera.global_rotation.y, 0)
			if frac != v.frac:
				v.frac = frac
				var fill: MeshInstance3D = v.fill
				fill.scale.x = maxf(0.001, frac)
				fill.position.x = -0.4 * (1 - frac)
				(fill.material_override as StandardMaterial3D).albedo_color = \
					Color("5ee06a") if frac > 0.5 else Color("f2c14e") if frac > 0.25 else Color("e5534b")
		# windup: "!" and a pulsing glow
		var winding: bool = e.state in ["windup", "aim", "lock"]
		(v.bang as Label3D).visible = winding
		v.flash = maxf(0.0, v.flash - dt)
		var glow := 2.5 if v.flash > 0 else (0.6 + 0.6 * sin(_time * 30.0) if winding else 0.0)
		if glow != v.glow:
			v.glow = glow
			for m: ShaderMaterial in v.mats:
				m.set_shader_parameter("emission_boost", glow)
		(v.fx as StatusFx).update(e.target.status, dt, particles if near else null, e.target.pos)
		if v.spin and Upgrades.time_scale(e.target) > 0:
			(v.spin as Node3D).rotation.y += dt * 30.0 * Upgrades.time_scale(e.target)
		if e.def.family == "flyer":
			(v.body as Node3D).position.y = sin(_time * 3.0 + e.id) * 0.08
		_update_laser(e, v, en)
		_update_beam(e, v, en)
		if e.wave_r >= 0:
			_update_wave(e)
	for id: int in _views.keys():
		if not seen.has(id):
			_free_view(_views[id])
			_views.erase(id)
	_update_projectiles(en, dt)
	for w: Dictionary in _waves.duplicate():
		if not seen.has(w.id) or _find(en, w.id) == null or _find(en, w.id).wave_r < 0:
			(w.node as Node3D).queue_free()
			_waves.erase(w)
	var left: Array = []
	for m: Dictionary in _markers:
		m.life -= dt
		if m.life > 0:
			left.append(m)
			var mi: MeshInstance3D = m.node
			mi.scale = Vector3.ONE * (1.0 + 0.08 * sin(_time * 12.0))
		else:
			(m.node as Node3D).queue_free()
	_markers = left


func flash(id: int) -> void:
	if _views.has(id):
		_views[id].flash = 0.08


## React to the logic's events (the landing marker for a lob).
func on_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e.type == "lob":
			var ring := MeshInstance3D.new()
			var t := TorusMesh.new()
			t.inner_radius = Enemies.LOBBER.radius - 0.25
			t.outer_radius = Enemies.LOBBER.radius
			t.rings = 32
			t.ring_segments = 6
			ring.mesh = t
			ring.material_override = _glow_mat(Color(1, 0.35, 0.25, 0.8))
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.position = (e.land as Vector3) + Vector3(0, 0.06, 0)
			ring.scale.y = 0.2
			add_child(ring)
			_markers.append({"node": ring, "life": float(e.time) + 0.1})


## An enemy's model plus its laser / beam (those live outside its node, in world space).
func _free_view(v: Dictionary) -> void:
	(v.node as Node3D).queue_free()
	for k in ["laser", "beam"]:
		if v[k]:
			(v[k] as Node3D).queue_free()


func clear() -> void:
	for v: Dictionary in _views.values():
		_free_view(v)
	_views.clear()
	for mesh: Node3D in _proj.values():
		mesh.queue_free()
	_proj.clear()
	for m: Dictionary in _markers:
		(m.node as Node3D).queue_free()
	_markers.clear()
	for w: Dictionary in _waves:
		(w.node as Node3D).queue_free()
	_waves.clear()


# ---------- models ----------

func _make(e: Enemies.Enemy) -> Dictionary:
	var col: Color = e.def.color
	var node := Node3D.new()
	add_child(node)
	var body := Node3D.new()
	body.scale = Vector3.ONE * e.target.size
	node.add_child(body)
	var bean := WorldView.make_bean(col, col.lerp(Color.WHITE, 0.35))
	body.add_child(bean)
	var mats := [(bean.get_child(0) as MeshInstance3D).material_override, (bean.get_child(1) as MeshInstance3D).material_override]
	# angry brows: every enemy has them (the dummies don't)
	var ink := _flat(Color("1a1430"))
	for sgn: float in [-1.0, 1.0]:
		var brow := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.025, 0.02)
		brow.mesh = bm
		brow.material_override = ink
		brow.position = Vector3(sgn * 0.075, 1.84, 0.19)
		brow.rotation.z = sgn * -0.45
		body.add_child(brow)
	var spin: Node3D = null
	match e.type:
		"charger":
			for sgn: float in [-1.0, 1.0]:
				var horn := _part(CylinderMesh.new(), Color("fff1d6"), body)
				(horn.mesh as CylinderMesh).top_radius = 0.0
				(horn.mesh as CylinderMesh).bottom_radius = 0.06
				(horn.mesh as CylinderMesh).height = 0.26
				horn.position = Vector3(sgn * 0.13, 1.98, 0.02)
				horn.rotation.z = sgn * -0.5
		"colossus":
			for i in 5: # a gold crown
				var spike := _part(CylinderMesh.new(), Color("ffcf2e"), body)
				(spike.mesh as CylinderMesh).top_radius = 0.0
				(spike.mesh as CylinderMesh).bottom_radius = 0.06
				(spike.mesh as CylinderMesh).height = 0.22
				var a := TAU * i / 5.0
				spike.position = Vector3(sin(a) * 0.17, 2.02, cos(a) * 0.17)
			var band := _part(CylinderMesh.new(), Color("ffcf2e"), body)
			(band.mesh as CylinderMesh).top_radius = 0.2
			(band.mesh as CylinderMesh).bottom_radius = 0.2
			(band.mesh as CylinderMesh).height = 0.07
			band.position.y = 1.9
			for sgn: float in [-1.0, 1.0]:
				var plate := _part(BoxMesh.new(), Color("3a2a4a"), body)
				(plate.mesh as BoxMesh).size = Vector3(0.36, 0.16, 0.46)
				plate.position = Vector3(sgn * 0.37, 1.3, 0)
		"brute":
			for sgn: float in [-1.0, 1.0]:
				var plate := _part(BoxMesh.new(), Color("4b3a7a"), body)
				(plate.mesh as BoxMesh).size = Vector3(0.34, 0.14, 0.44)
				plate.position = Vector3(sgn * 0.36, 1.32, 0)
		"swarmer":
			for i in 5:
				var spike := _part(CylinderMesh.new(), Color("3f7d2c"), body)
				(spike.mesh as CylinderMesh).top_radius = 0.0
				(spike.mesh as CylinderMesh).bottom_radius = 0.07
				(spike.mesh as CylinderMesh).height = 0.22
				var a := -0.9 + i * 0.45
				spike.position = Vector3(sin(a) * 0.3, 1.2 + cos(a) * 0.1, -0.28)
				spike.rotation.x = -1.1
		"gunner", "sniper":
			var gun := Models.held_gun("rifle" if e.type == "gunner" else "sniper", 0.8 if e.type == "sniper" else 0.6)
			if gun:
				gun.position = Vector3(-0.5, 0.95, 0.3)
				gun.rotation.y = PI
				body.add_child(gun)
		"lobber":
			var nade := Models.projectile("frag")
			nade.position = Vector3(-0.5, 1.0, 0.25)
			nade.scale = Vector3.ONE * 1.8
			body.add_child(nade)
		"flyer_projectile", "flyer_beam", "flyer_healer":
			spin = Node3D.new()
			spin.position.y = 2.05
			body.add_child(spin)
			var stick := _part(CylinderMesh.new(), Color("3a3f5a"), spin)
			(stick.mesh as CylinderMesh).top_radius = 0.025
			(stick.mesh as CylinderMesh).bottom_radius = 0.025
			(stick.mesh as CylinderMesh).height = 0.14
			for sgn: float in [-1.0, 1.0]:
				var blade := _part(BoxMesh.new(), Color("f2f5ff"), spin)
				(blade.mesh as BoxMesh).size = Vector3(0.5, 0.03, 0.1)
				blade.position = Vector3(sgn * 0.25, 0.07, 0)
			if e.type == "flyer_healer":
				for sz: Vector3 in [Vector3(0.26, 0.08, 0.04), Vector3(0.08, 0.26, 0.04)]:
					var bar := _part(BoxMesh.new(), Color.WHITE, body)
					(bar.mesh as BoxMesh).size = sz
					bar.position = Vector3(0, 0.85, 0.39)
			elif e.type == "flyer_beam":
				var lens := _part(SphereMesh.new(), Color("ffb3ff"), body)
				(lens.mesh as SphereMesh).radius = 0.1
				(lens.mesh as SphereMesh).height = 0.2
				lens.position = Vector3(0, 0.95, 0.38)
				lens.material_override = _glow_mat(Color("ff7bff"))
	# health bar + windup "!"
	var bar := Node3D.new()
	bar.position.y = BAR_Y * e.target.size
	node.add_child(bar)
	for part: Array in [[Vector2(0.84, 0.1), Color(0.07, 0.07, 0.07, 0.7), 0.0], [Vector2(0.8, 0.07), Color("5ee06a"), 0.001]]:
		var q := QuadMesh.new()
		q.size = part[0]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position.z = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = part[1]
		if part[1].a < 1:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		bar.add_child(mi)
	var bang := Label3D.new()
	bang.text = "!"
	bang.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	bang.font_size = 96
	bang.fixed_size = true # same size on screen near or far (a close one doesn't cover your view)
	bang.pixel_size = 0.0005
	bang.modulate = Color("ff3b3b")
	bang.outline_size = 16
	bang.outline_modulate = Color("15151f")
	bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bang.no_depth_test = true
	bang.position.y = BAR_Y * e.target.size + 0.45
	bang.visible = false
	node.add_child(bang)
	# Cheap to draw: only the body and head cast shadows (every shadowed mesh is drawn again per
	# shadow split), and the small stuff is a list to hide at a distance.
	var bean_body := bean.get_child(0)
	var bean_head := bean.get_child(1)
	var detail: Array[Node3D] = []
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi != bean_body and mi != bean_head:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in bean.get_children().slice(2): # eyes
		detail.append(c)
	for c in body.get_children():
		if c != bean and c != spin:
			detail.append(c)
	return {"node": node, "body": body, "mats": mats, "bar": bar, "fill": bar.get_child(1), "bang": bang,
		"spin": spin, "flash": 0.0, "laser": null, "beam": null, "fx": StatusFx.new(node, mats, e.target.size),
		"detail": detail, "near": true, "glow": -1.0, "frac": -1.0}


func _part(mesh: PrimitiveMesh, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WorldView.with_outline(WorldView.toon_material(color), 0.012)
	parent.add_child(mi)
	return mi


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _glow_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _glow_cache.has(key):
		return _glow_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_cache[key] = m
	return m


# ---------- attacks ----------

## The MAX_TRACKING snipers nearest the camera that are tracking you: theirs are the lasers drawn.
func _pick_tracking(en: Enemies) -> void:
	_tracking.clear()
	var aiming: Array = []
	for e in en.list:
		if e.type == "sniper" and e.state == "aim":
			aiming.append(e)
	if aiming.size() > MAX_TRACKING:
		aiming.sort_custom(func(a: Enemies.Enemy, b: Enemies.Enemy) -> bool:
			return a.center().distance_squared_to(_cam) < b.center().distance_squared_to(_cam))
	for i in mini(MAX_TRACKING, aiming.size()):
		_tracking[aiming[i].id] = true


## A thin cylinder from a to b (lasers and beams).
func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		mi.visible = false
		return
	mi.visible = true
	mi.global_position = (a + b) / 2
	var up := d / len
	var side := up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	mi.global_basis = Basis(side, up * len, side.cross(up)) # the cylinder's height (local Y) stretched to the length


func _line(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 1.0
	c.radial_segments = 8
	mi.mesh = c
	mi.material_override = _glow_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _update_laser(e: Enemies.Enemy, v: Dictionary, en: Enemies) -> void:
	if e.type != "sniper":
		return
	var on: bool = e.state in ["aim", "lock"]
	if v.laser == null:
		v.laser = _line(0.02, Color(1, 0.2, 0.2, 0.85))
	var laser: MeshInstance3D = v.laser
	if not on:
		laser.visible = false
		return
	var locked: bool = e.state == "lock"
	if not locked and not _tracking.has(e.id):
		laser.visible = false # too many at once: the nearest few are enough
		return
	var from := en._eye(e)
	var to: Vector3 = e.aim
	var d := (to - from).normalized()
	var reach := from.distance_to(to) + 3.0 # a little past you, not across the whole map
	var wall := en._ray_walls(from, d, reach)
	_stretch(laser, from, from + d * (wall if wall >= 0 else reach))
	# faint red while it tracks you, bright white once it's locked (that's your cue to move)
	laser.material_override = _glow_mat(Color(1, 1, 1, 0.95) if locked else Color(1, 0.25, 0.25, 0.45))
	(laser.mesh as CylinderMesh).top_radius = 0.03 if locked else 0.012
	(laser.mesh as CylinderMesh).bottom_radius = (laser.mesh as CylinderMesh).top_radius


func _update_beam(e: Enemies.Enemy, v: Dictionary, en: Enemies) -> void:
	if e.type != "flyer_beam" and e.type != "flyer_healer":
		return
	if v.beam == null:
		v.beam = _line(0.05, Color(1, 0.4, 1, 0.65) if e.type == "flyer_beam" else Color(0.4, 1, 0.6, 0.3))
	var beam: MeshInstance3D = v.beam
	var to := Vector3.ZERO
	var on := false
	if e.type == "flyer_beam" and e.state == "attack":
		on = true
		# ends just short of you: right up to your chest it would fill the bottom of the screen
		to = en.player_center + (e.pos - en.player_center).normalized() * 0.9
	elif e.type == "flyer_healer" and e.heal_target and e.heal_target.alive and e.pos.distance_to(_cam) < HEAL_BEAM_RANGE:
		on = true
		to = e.heal_target.center()
	if not on:
		beam.visible = false
		return
	var from := e.pos + Vector3(0, -0.1, 0)
	_stretch(beam, from, to)
	var w := (0.045 + 0.015 * sin(_time * 40.0)) if e.type == "flyer_beam" else 0.025
	(beam.mesh as CylinderMesh).top_radius = w
	(beam.mesh as CylinderMesh).bottom_radius = w


func _update_wave(e: Enemies.Enemy) -> void:
	var w: Dictionary = {}
	for x: Dictionary in _waves:
		if x.id == e.id:
			w = x
	if w.is_empty():
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.82
		t.outer_radius = 1.0
		t.rings = 48
		t.ring_segments = 6
		ring.mesh = t
		ring.material_override = _glow_mat(Color(0.75, 0.55, 1.0, 0.85))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		w = {"node": ring, "id": e.id}
		_waves.append(w)
	var node: MeshInstance3D = w.node
	node.position = e.wave_at + Vector3(0, 0.15, 0)
	var r := maxf(0.01, e.wave_r)
	node.scale = Vector3(r, 0.6, r)


func _update_projectiles(en: Enemies, dt: float) -> void:
	var seen := {}
	for pr: Dictionary in en.projectiles:
		var id: int = pr.id
		seen[id] = true
		var mesh: MeshInstance3D = _proj.get(id)
		if mesh == null:
			mesh = MeshInstance3D.new()
			var s := SphereMesh.new()
			var r: float = pr.radius
			s.radius = r
			s.height = r * 2
			s.radial_segments = 12
			s.rings = 6
			mesh.mesh = s
			var col: Color = {"bullet": Color("7fd4ff"), "orb": Color("ffe066"), "lob": Color("ff8a3d")}.get(pr.kind, Color.WHITE)
			mesh.material_override = _glow_mat(col)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)
			_proj[id] = mesh
		mesh.position = pr.pos
	for id: int in _proj.keys():
		if not seen.has(id):
			(_proj[id] as Node3D).queue_free()
			_proj.erase(id)


static func _find(en: Enemies, id: int) -> Enemies.Enemy:
	for e in en.list:
		if e.id == id:
			return e
	return null
