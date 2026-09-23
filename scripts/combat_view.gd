class_name CombatView
extends Node3D
## Draws combat in the world: flying and stuck projectiles, plus a plain expanding blast where
## something explodes. Reads Combat every frame; never changes it. (The web game's full cartoon
## explosions, tracers and puffs come with the effects step.)

const BLAST_TIME := 0.25
const BLAST_COLOR := {"rocket": Color("ff8a30"), "frag": Color("ff7a20"), "impulse": Color("40d8ff")}

var _meshes := {} # Combat.Projectile -> Node3D
var _blasts: Array = [] # [{node, age, radius}]
var _time := 0.0


func update(dt: float, combat: Combat) -> void:
	_time += dt
	var alive := {}
	for pr in combat.projectiles:
		alive[pr] = true
		var mesh: Node3D = _meshes.get(pr)
		if mesh == null:
			mesh = Models.projectile(pr.kind)
			add_child(mesh)
			_meshes[pr] = mesh
		mesh.position = pr.pos
		if not pr.stuck and pr.vel.length() > 0.1:
			var fwd := pr.vel.normalized()
			var up := Vector3.RIGHT if absf(fwd.y) > 0.99 else Vector3.UP
			mesh.basis = Basis.looking_at(fwd, up)
		var spin := mesh.get_node_or_null("Spin") as Node3D
		if spin:
			spin.rotation.x = 0.0 if pr.stuck else -_time * 25
	for pr: Variant in _meshes.keys():
		if not alive.has(pr):
			(_meshes[pr] as Node3D).queue_free()
			_meshes.erase(pr)

	for b: Dictionary in _blasts:
		b.age += dt
		var t: float = b.age / BLAST_TIME
		var node: MeshInstance3D = b.node
		node.scale = Vector3.ONE * b.radius * (0.3 + 0.7 * sqrt(t))
		(node.material_override as StandardMaterial3D).albedo_color.a = 0.75 * (1 - t)
	for b: Dictionary in _blasts.filter(func(x: Dictionary) -> bool: return x.age >= BLAST_TIME):
		(b.node as Node3D).queue_free()
	_blasts = _blasts.filter(func(x: Dictionary) -> bool: return x.age < BLAST_TIME)


func on_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e.type == "explosion":
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			mi.mesh = s
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = BLAST_COLOR.get(e.kind, Color("ff8a30"))
			mi.material_override = m
			mi.position = e.pos
			add_child(mi)
			_blasts.append({"node": mi, "age": 0.0, "radius": float(e.radius) * 0.6})


## Drop everything (new run / map).
func clear() -> void:
	for n in get_children():
		n.queue_free()
	_meshes.clear()
	_blasts.clear()
