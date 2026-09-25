class_name StatusFx
extends RefCounted
## Item statuses drawn on one bean (an enemy or a dummy; see Upgrades for what they do): a tint
## (frozen pale blue, chilled blue, burning flickering orange), an ice block when frozen, a red
## target ring over a marked head, a blinking sticky bomb, and particles (flames, blood drips,
## snowflakes). EnemyView and main.gd's dummies each keep one per bean.

var node: Node3D # the bean's root (the extras hang off it)
var mats: Array # its toon materials (tinted through "albedo")
var bases: Array[Color] = []
var size := 1.0
var _ice: MeshInstance3D
var _mark: MeshInstance3D
var _bomb: MeshInstance3D
var _bomb_mat: StandardMaterial3D
var _puff_t := 0.0
var _time := 0.0
var _tinted := false
var _active := false # something is showing (so an empty status still has to tidy up once)


func _init(n: Node3D, m: Array, s: float) -> void:
	node = n
	mats = m
	size = s
	for mat: ShaderMaterial in mats:
		bases.append(mat.get_shader_parameter("albedo"))


## particles: null = don't spawn any (far away: nobody sees them, and they cost frame time).
func update(st: Dictionary, dt: float, particles: Particles, pos: Vector3) -> void:
	if st.is_empty() and not _active:
		return # the usual case: nothing on it, nothing to do
	_active = not st.is_empty()
	_time += dt
	var tint := Color.WHITE
	var amt := 0.0
	if st.has("freeze"):
		tint = Color("d6f0ff")
		amt = 0.7
	elif st.has("chill"):
		tint = Color("7fc8ff")
		amt = 0.4
	elif st.has("burn"):
		tint = Color("ff6a10")
		amt = 0.5 + 0.15 * sin(_time * 20.0)
	if amt > 0 or _tinted:
		for i in mats.size():
			(mats[i] as ShaderMaterial).set_shader_parameter("albedo", bases[i].lerp(tint, amt))
		_tinted = amt > 0

	_show_ice(st.has("freeze"))
	_show_mark(st.has("mark"))
	_show_bomb(st.get("bombs", []))

	if particles == null or st.is_empty():
		return
	_puff_t -= dt
	if _puff_t > 0:
		return
	_puff_t = 0.09
	var center := pos + Vector3(0, 1.0 * size, 0)
	if st.has("burn"):
		for i in 3:
			particles.spawn({
				"pos": center + Vector3(randf_range(-0.35, 0.35), randf_range(-0.7, 0.6), randf_range(-0.35, 0.35)) * size,
				"vel": Vector3(randf_range(-0.3, 0.3), randf_range(2.2, 3.4), randf_range(-0.3, 0.3)),
				"life": randf_range(0.35, 0.5), "size": [0.3 * size, 0.04], "color": Color("ffe14d"), "color2": Color("ff4a1a"),
				"opacity": [1.0, 0.0], "fade_start": 0.4,
			})
	if st.has("bleed") and randf() < 0.5:
		particles.spawn({
			"lit": true, "pos": center + Vector3(randf_range(-0.25, 0.25), randf_range(-0.3, 0.4), randf_range(-0.25, 0.25)) * size,
			"vel": Vector3(0, -0.5, 0), "gravity": 12.0, "life": 0.5, "size": [0.08, 0.05],
			"color": Color("c0392b"), "opacity": [1.0, 1.0],
		})
	if (st.has("chill") or st.has("freeze")) and randf() < 0.35:
		particles.spawn({
			"cube": true, "spin": 4.0, "pos": center + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 0.9), randf_range(-0.5, 0.5)) * size,
			"vel": Vector3(0, -0.6, 0), "life": 0.8, "size": [0.06, 0.03], "color": Color("f0faff"), "opacity": [0.9, 0.0],
		})


func _show_ice(on: bool) -> void:
	if not on:
		if _ice:
			_ice.visible = false
		return
	if _ice == null:
		_ice = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 2.2, 1.0) * size
		_ice.mesh = b
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.75, 0.92, 1.0, 0.42)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice.material_override = m
		_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ice.position.y = 1.05 * size
		node.add_child(_ice)
	_ice.visible = true


func _show_mark(on: bool) -> void:
	if not on:
		if _mark:
			_mark.visible = false
		return
	if _mark == null:
		_mark = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.26
		t.outer_radius = 0.34
		t.rings = 24
		t.ring_segments = 6
		_mark.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("ff3b3b")
		m.no_depth_test = true # seen through walls: you marked it, you should find it
		_mark.material_override = m
		_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mark.position.y = 2.55 * size
		_mark.scale = Vector3(1, 0.3, 1)
		node.add_child(_mark)
	_mark.visible = true
	_mark.rotation.y = _time * 3.0


func _show_bomb(bombs: Array) -> void:
	if bombs.is_empty():
		if _bomb:
			_bomb.visible = false
		return
	if _bomb == null:
		_bomb = MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.13
		s.height = 0.26
		_bomb.mesh = s
		_bomb_mat = StandardMaterial3D.new()
		_bomb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bomb.material_override = _bomb_mat
		_bomb.position = Vector3(0, 1.0 * size, 0.38 * size)
		node.add_child(_bomb)
	_bomb.visible = true
	# blinks faster as the fuse runs out
	var left := 9.0
	for b: Dictionary in bombs:
		left = minf(left, float(b.t))
	var rate := lerpf(24.0, 6.0, clampf(left / Upgrades.BOMB_FUSE, 0.0, 1.0))
	_bomb_mat.albedo_color = Color("ff3030") if sin(_time * rate) > 0 else Color("3a3f4b")
