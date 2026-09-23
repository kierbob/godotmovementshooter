class_name Models
## Loads the .glb gun models (assets/models/weapons, Kenney CC0) and gives them the game's cartoon
## look: toon shading that keeps the palette texture, plus black outlines (the web game's
## models.js). Also builds the knife and the flying projectiles out of simple shapes.

const DIR := "res://assets/models/weapons/"
const INK := Color("15151f") # outline color (web outline.js)
const OUTLINE := preload("res://shaders/outline.gdshader")
const STAGE_FIT := 1.7 # longest side of every model on the loadout stage

static var _outline_mats := {} # thickness -> ShaderMaterial
static var _cache := {} # file -> PackedScene (null if it failed), instanced for every use


## The raw model, or null if the file is missing/broken. Uses Godot's imported copy when the editor
## has imported it; otherwise reads the .glb directly (e.g. running play.bat before the editor ever
## opened the project).
static func load_glb(file: String) -> Node3D:
	if not _cache.has(file):
		var path := DIR + file
		var ps: PackedScene = null
		if ResourceLoader.exists(path):
			ps = load(path) as PackedScene
		if ps == null and FileAccess.file_exists(path):
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_file(path, st) == OK:
				var node := doc.generate_scene(st)
				ps = PackedScene.new()
				ps.pack(node)
				node.free()
		if ps == null:
			push_warning("Gun model %s failed to load." % file)
		_cache[file] = ps
	var scene: PackedScene = _cache[file]
	return scene.instantiate() as Node3D if scene else null


## A texture from the project. Uses Godot's imported copy when there is one; otherwise reads the
## PNG directly, so a fresh download still works before the editor has imported anything.
static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img else null


## Same idea for fonts (.ttf).
static func font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	var f := FontFile.new()
	return f if f.load_dynamic_font(ProjectSettings.globalize_path(path)) == OK else null


## Swap the model's PBR materials for toon ones (keeping the palette texture) and add outlines.
## outline is in the model's own units (so divide by its scale).
static func toonify(root: Node, outline: float) -> void:
	for mi in _meshes(root):
		# Materials go on a copy of the mesh rather than as per-instance overrides: overrides on
		# imported meshes error on shutdown in headless runs.
		mi.mesh = mi.mesh.duplicate()
		for i in mi.mesh.get_surface_count():
			var old := mi.get_active_material(i)
			var col := Color.WHITE
			var tex: Texture2D = null
			if old is BaseMaterial3D:
				col = (old as BaseMaterial3D).albedo_color
				tex = (old as BaseMaterial3D).albedo_texture
			var m := WorldView.toon_material(col)
			if tex:
				m.set_shader_parameter("use_palette", true)
				m.set_shader_parameter("palette_tex", tex)
			mi.mesh.surface_set_material(i, m)
		if outline > 0:
			add_outline(mi, outline)


## Black cartoon outline: an inflated copy of the mesh drawn back faces only (outline.js). The copy
## is welded and uses smoothed normals; pushing a low-poly mesh out along its own hard-edged normals
## tears the outline apart at every corner.
static func add_outline(mi: MeshInstance3D, thickness: float) -> void:
	var o := MeshInstance3D.new()
	o.name = "Outline"
	o.mesh = shell(mi.mesh, thickness)
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.material_override = _outline_material(thickness)
	mi.add_child(o)


## Ink material for outline shells (shaders/outline.gdshader), one per thickness. The shell is
## pushed back 3x its thickness so it only shows around the silhouette, never over the model.
static func _outline_material(thickness: float) -> ShaderMaterial:
	var key := snappedf(thickness, 0.00001)
	if not _outline_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE
		m.set_shader_parameter("ink", INK)
		m.set_shader_parameter("push", thickness * 3.0)
		_outline_mats[key] = m
	return _outline_mats[key]


## The mesh with vertices at the same spot merged, each pushed out by `thickness` along the
## average of the faces around it (area-weighted, like three.js computeVertexNormals).
static func shell(mesh: Mesh, thickness: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(src.size()))
		# weld by position (1e-4 grid, like mergeVertices)
		var key_to_new := {}
		var remap := PackedInt32Array()
		remap.resize(src.size())
		var pos := PackedVector3Array()
		for i in src.size():
			var k := Vector3i((src[i] * 10000.0).round())
			if not key_to_new.has(k):
				key_to_new[k] = pos.size()
				pos.append(src[i])
			remap[i] = key_to_new[k]
		var normals := PackedVector3Array()
		normals.resize(pos.size())
		var tris := PackedInt32Array()
		tris.resize(idx.size())
		for t in range(0, idx.size() - 2, 3):
			var a := remap[idx[t]]
			var b := remap[idx[t + 1]]
			var c := remap[idx[t + 2]]
			tris[t] = a
			tris[t + 1] = b
			tris[t + 2] = c
			# Godot winds front faces clockwise, so this cross product points outward.
			var n := (pos[c] - pos[a]).cross(pos[b] - pos[a])
			normals[a] += n
			normals[b] += n
			normals[c] += n
		for i in pos.size():
			pos[i] += normals[i].normalized() * thickness
		var shell_arrays := []
		shell_arrays.resize(Mesh.ARRAY_MAX)
		shell_arrays[Mesh.ARRAY_VERTEX] = pos
		shell_arrays[Mesh.ARRAY_INDEX] = tris
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shell_arrays)
	return out


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out


## Bounding box of everything under `node`, in the space of node's parent (works outside the tree).
static func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for entry: Array in _mesh_transforms(node, node.transform):
		var mi: MeshInstance3D = entry[0]
		var b: AABB = (entry[1] as Transform3D) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _mesh_transforms(n: Node, xf: Transform3D) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([n, xf])
	for c in n.get_children():
		if c is Node3D:
			out.append_array(_mesh_transforms(c, xf * (c as Node3D).transform))
	return out


## First-person gun: barrel along -Z, back end near the holder, sized to the weapon's length.
## Returns the holder (place it low-right of the camera) with meta "muzzle" (holder space), or
## null if the model didn't load.
static func viewmodel(id: String) -> Node3D:
	var cfg: Dictionary = Items.MODELS[id]
	var model := load_glb(cfg.file)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.add_child(model)
	var box := bounds(model)
	var s: float = cfg.length / maxf(box.size.z, 1e-3)
	model.scale *= s
	box = bounds(model)
	# Center on X, top of the gun a bit above the holder, back of the gun at z = +0.12.
	var c := box.get_center()
	model.position.x -= c.x
	model.position.y -= box.end.y - 0.11
	model.position.z -= box.end.z - 0.12
	model.position += cfg.offset
	box = bounds(model)
	toonify(model, 0.0035 / s)
	_no_shadows(model)
	var muzzle := Vector3(0, box.end.y - box.size.y * 0.3, box.position.z)
	# Angle the barrel slightly in toward the crosshair so you see the gun's side.
	const CANT := 0.08
	holder.rotation.y = CANT
	holder.set_meta("muzzle", muzzle.rotated(Vector3.UP, CANT))
	return holder


## World-size gun (the one you chuck away when reloading): `length` long along its barrel,
## centered on its middle so it spins nicely. Null if the model didn't load.
static func held_gun(id: String, length: float) -> Node3D:
	var model := load_glb(Items.MODELS[id].file)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.add_child(model)
	var box := bounds(model)
	var s := length / maxf(box.size.z, 1e-3)
	model.scale *= s
	box = bounds(model)
	model.position -= box.get_center()
	toonify(model, 0.012 / s)
	return holder


## Loadout stage model: side-on, barrel pointing right, longest side STAGE_FIT, centered.
static func stage_model(id: String) -> Node3D:
	var model: Node3D
	var file: String = Items.MODELS.get(id, {}).get("file", "")
	if file != "":
		model = load_glb(file)
	elif id == "knife":
		model = knife()
	if model == null:
		return null
	model.rotation.y = -PI / 2
	var holder := Node3D.new()
	holder.add_child(model)
	var box := bounds(model)
	var s := STAGE_FIT / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 1e-3))
	model.scale *= s
	box = bounds(model)
	model.position -= box.get_center()
	if file != "":
		toonify(model, 0.028 / s)
	return holder


## Throwing knife built from boxes (showcase.js knifeModel), blade toward -Z.
static func knife() -> Node3D:
	var g := Node3D.new()
	var steel := Color("d8dee9")
	_part(g, BoxMesh.new(), Vector3(0.06, 0.02, 0.4), Vector3(0, 0, -0.12), steel)
	var tip := PrismMesh.new() # a flat wedge for the point
	_part(g, tip, Vector3(0.06, 0.12, 0.02), Vector3(0, 0, -0.38), steel).rotation.x = -PI / 2
	_part(g, BoxMesh.new(), Vector3(0.16, 0.05, 0.04), Vector3(0, 0, 0.1), Color("333844"))
	_part(g, BoxMesh.new(), Vector3(0.07, 0.06, 0.22), Vector3(0, 0, 0.23), Color("6b3f22"))
	return g


static func _part(parent: Node3D, mesh: PrimitiveMesh, size: Vector3, pos: Vector3, color: Color, outline := 0.012) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is PrismMesh:
		(mesh as PrismMesh).size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = WorldView.toon_material(color)
	if outline > 0:
		add_outline(mi, outline)
	parent.add_child(mi)
	return mi


static func _no_shadows(root: Node) -> void:
	for mi in _meshes(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _glow(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if alpha < 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A flying projectile (fx.js makeProjectile). Points along -Z: aim it with look_at.
static func projectile(kind: String) -> Node3D:
	var g := Node3D.new()
	match kind:
		"rocket":
			var body := CylinderMesh.new()
			body.top_radius = 0.07
			body.bottom_radius = 0.07
			body.height = 0.45
			_part(g, body, Vector3.ZERO, Vector3.ZERO, Color("55603f"), 0.01).rotation.x = PI / 2
			var tip := CylinderMesh.new()
			tip.top_radius = 0.0
			tip.bottom_radius = 0.07
			tip.height = 0.14
			_part(g, tip, Vector3.ZERO, Vector3(0, 0, -0.29), Color("333333"), 0.01).rotation.x = -PI / 2
			var flame := MeshInstance3D.new()
			var fs := SphereMesh.new()
			fs.radius = 0.1
			fs.height = 0.2
			flame.mesh = fs
			flame.material_override = _glow(Color("ffa040"), 0.9)
			flame.position.z = 0.28
			flame.scale.z = 2
			g.add_child(flame)
		"frag":
			var ball := SphereMesh.new()
			ball.radius = 0.12
			ball.height = 0.24
			_part(g, ball, Vector3.ZERO, Vector3.ZERO, Color("3b5d2a"), 0.012)
			var band := TorusMesh.new()
			band.inner_radius = 0.1
			band.outer_radius = 0.14
			_part(g, band, Vector3.ZERO, Vector3.ZERO, Color("222222"), 0.0)
		"knife":
			var spin := Node3D.new()
			spin.name = "Spin"
			_part(spin, BoxMesh.new(), Vector3(0.03, 0.008, 0.2), Vector3(0, 0, -0.06), Color("d8dee9"), 0.0)
			_part(spin, BoxMesh.new(), Vector3(0.035, 0.03, 0.1), Vector3(0, 0, 0.09), Color("2a1d14"), 0.0)
			g.add_child(spin)
		"impulse":
			for layer: Array in [[0.12, Color("7ff6ff"), 1.0], [0.22, Color("38c8ff"), 0.35]]:
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = layer[0]
				sm.height = layer[0] * 2
				mi.mesh = sm
				mi.material_override = _glow(layer[1], layer[2])
				g.add_child(mi)
	return g
