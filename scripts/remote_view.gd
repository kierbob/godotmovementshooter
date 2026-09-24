class_name RemoteView
extends Node3D
## Other online players (web fx.js makeTargetView for "remote"): a bean in their color with a
## floating name tag and their gun hovering at their side, Rayman-style. They squash down when
## crouching or sliding (no limbs, so that's the animation), blink while spawn-protected, vanish
## while splatted and flash white when hit.

const GUN_OFFSET := Vector3(-0.52, 0.95, 0.3) # bean space (the bean faces +Z)

var _views := {} # id -> {node, mats, gun, gun_id, tag, flash, low}
var _time := 0.0


## samples: id -> sampled player dict (Net.sample); roster: id -> {name, color}.
func update(samples: Dictionary, roster: Dictionary, dt: float) -> void:
	_time += dt
	for id: int in samples:
		var s: Dictionary = samples[id]
		var v: Dictionary = _views.get(id, {})
		var info: Dictionary = roster.get(id, {"name": "Bean", "color": Color("4fc3ff")})
		if v.is_empty():
			v = _make(info.name, info.color)
			_views[id] = v
		var node: Node3D = v.node
		var dead: bool = s.flags & NetCodec.F_DEAD != 0
		var protected: bool = s.flags & NetCodec.F_PROTECTED != 0
		node.visible = not dead and (not protected or fmod(_time, 0.24) < 0.16)
		node.position = Vector3(s.x, s.y, s.z)
		node.rotation.y = float(s.yaw) + PI # camera yaw 0 looks down -Z; the bean faces +Z
		var low: bool = s.flags & (NetCodec.F_CROUCH | NetCodec.F_SLIDE) != 0
		var body: Node3D = v.body
		body.scale.y = lerpf(body.scale.y, 0.62 if low else 1.0, minf(1.0, dt * 14))
		(v.tag as Label3D).position.y = 2.3 * body.scale.y + 0.05
		if v.gun_id != s.weapon:
			_set_gun(v, s.weapon)
		var gun: Node3D = v.gun_holder
		gun.position = GUN_OFFSET * Vector3(1, body.scale.y, 1)
		gun.rotation.x = -float(s.pitch) * 0.7 # the gun tilts with their aim
		v.flash = maxf(0.0, v.flash - dt)
		for m: ShaderMaterial in v.mats:
			m.set_shader_parameter("emission_boost", 2.5 if v.flash > 0 else 0.0)
	for id: int in _views.keys():
		if not samples.has(id):
			(_views[id].node as Node3D).queue_free()
			_views.erase(id)


func flash(id: int) -> void:
	if _views.has(id):
		_views[id].flash = 0.08


## Where their gun's barrel is, for their muzzle flash and tracers.
func muzzle(id: int, fallback: Vector3) -> Vector3:
	var v: Dictionary = _views.get(id, {})
	if v.is_empty():
		return fallback
	var gun: Node3D = v.gun_holder
	return gun.global_transform * Vector3(0, 0, float(v.gun_len) * 0.55)


func clear() -> void:
	for v: Dictionary in _views.values():
		(v.node as Node3D).queue_free()
	_views.clear()


func _make(player_name: String, color: Color) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var body := Node3D.new()
	node.add_child(body)
	var bean := WorldView.make_bean(color, color.lerp(Color.WHITE, 0.3))
	body.add_child(bean)
	var mats := [(bean.get_child(0) as MeshInstance3D).material_override, (bean.get_child(1) as MeshInstance3D).material_override]
	var tag := Label3D.new()
	tag.text = player_name
	tag.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	tag.font_size = 64
	tag.pixel_size = 0.006
	tag.modulate = color.lerp(Color.WHITE, 0.45)
	tag.outline_size = 14
	tag.outline_modulate = Color("15151f")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.position.y = 2.35
	node.add_child(tag)
	var holder := Node3D.new()
	holder.position = GUN_OFFSET
	node.add_child(holder)
	return {"node": node, "body": body, "mats": mats, "tag": tag, "gun_holder": holder, "gun": null,
		"gun_id": "", "gun_len": 0.5, "flash": 0.0}


func _set_gun(v: Dictionary, id: String) -> void:
	if v.gun:
		(v.gun as Node3D).queue_free()
	v.gun = null
	v.gun_id = id
	if not Items.MODELS.has(id):
		return
	var length := float(Items.MODELS[id].length) * 1.1
	var g := Models.held_gun(id, length)
	if g == null:
		return
	# held_gun points its barrel along -Z; the bean faces +Z
	g.rotation.y = PI
	(v.gun_holder as Node3D).add_child(g)
	v.gun = g
	v.gun_len = length
