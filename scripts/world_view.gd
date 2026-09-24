class_name WorldView
## Builds everything you see in the world from MapData: the boxes (merged into one mesh per color,
## like the web game), jump pads, bean dummies and clouds.

const TOON := preload("res://shaders/toon.gdshader")
const CLOUD := preload("res://shaders/cloud.gdshader")

## Box colors by kind (render.js COLORS).
const COLORS := {
	"floor": Color("56648a"), "wall": Color("8fa3cc"), "block": Color("a77be0"), "stair": Color("f0b650"),
	"pillar": Color("4fcf92"), "low": Color("f0766a"), "test": Color("ffd35a"), "plat": Color("52aef5"),
	"trialfloor": Color("6f7fb0"), "arenafloor": Color("5d6f96"), "gate": Color("ff5ab4"),
	# Bean Town (a cartoon cul-de-sac)
	"grass": Color("7cc576"), "road": Color("5a6075"), "sidewalk": Color("c7ccd9"), "wood": Color("c49a6c"),
	"house_blue": Color("7fb8ff"), "house_yellow": Color("ffd36b"), "trim": Color("f5f1e8"), "roof": Color("d9674e"),
	"fence": Color("f3ecdf"), "hedge": Color("4f9e52"), "bus": Color("ffbf1f"), "truck": Color("e05252"),
	"shed": Color("a8784f"), "leaves": Color("5fbf5f"), "trunk": Color("8a5a3b"), "crate": Color("d6a86a"), "barrier": Color("8fd3ff"),
	# Sunstone Valley (stage 1)
	"sandstone": Color("e3a468"), "cliff": Color("b86f4a"), "sand": Color("f0d9a0"), "ruin": Color("ddd5c2"),
	"ruin_dark": Color("aaa08c"), "sunstone": Color("ffcf2e"),
}
const NO_SHADOW_KINDS := ["floor", "trialfloor", "arenafloor", "grass", "road", "sidewalk", "wood"]

static var _grid: ImageTexture
static var cloud_material: ShaderMaterial # lighting presets tint the clouds


## 4x4 grid texture: one cell = 1 m, a thicker border every 4 m (render.js gridTexture).
static func grid_texture() -> Texture2D:
	if _grid:
		return _grid
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := 1.0
			if x % 64 == 63 or x % 64 == 0:
				v *= 0.88
			if y % 64 == 63 or y % 64 == 0:
				v *= 0.88
			if x < 3 or x >= size - 3 or y < 3 or y >= size - 3:
				v *= 0.65
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_grid = ImageTexture.create_from_image(img)
	return _grid


static func toon_material(color: Color, textured := false, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_tex", textured)
	if textured:
		m.set_shader_parameter("albedo_tex", grid_texture())
	m.set_shader_parameter("emission_boost", glow)
	return m


## Black cartoon outline around a mesh (inverted hull drawn as a second pass).
static func with_outline(m: Material, thickness := 0.025) -> Material:
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = Color("1a1430")
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = thickness
	m.next_pass = o
	return m


# ---------- map geometry ----------

static func build_world(map: MapData, parent: Node3D) -> void:
	var by_kind := {}
	for b in map.boxes:
		if b.kind == "barrier":
			continue # invisible wall (keeps players in the map; only the editor shows it)
		var st: SurfaceTool = by_kind.get(b.kind)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_kind[b.kind] = st
		if b.ramp_axis >= 0:
			_add_ramp(st, b)
		else:
			_add_box(st, b)
	for kind: String in by_kind:
		var mi := MeshInstance3D.new()
		mi.name = "World_" + kind
		mi.mesh = (by_kind[kind] as SurfaceTool).commit()
		mi.material_override = toon_material(COLORS.get(kind, Color("888888")), true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in NO_SHADOW_KINDS \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mi)


## One face (3 or 4 corners). Godot draws clockwise triangles as front faces, so the corners are
## put in the right order for the outward normal n.
static func _add_face(st: SurfaceTool, v: Array[Vector3], n: Vector3, uv: Array[Vector2]) -> void:
	var ccw := (v[1] - v[0]).cross(v[2] - v[0]).dot(n) > 0
	for i in range(1, v.size() - 1):
		var tri := [0, i, i + 1] if not ccw else [0, i + 1, i]
		for k: int in tri:
			st.set_normal(n)
			st.set_uv(uv[k])
			st.add_vertex(v[k])


static func _add_box(st: SurfaceTool, b: MapData.Box) -> void:
	var x0 := b.min_x
	var x1 := b.max_x
	var y0 := b.min_y
	var y1 := b.max_y
	var z0 := b.min_z
	var z1 := b.max_z
	# UVs in meters from the box corner / 4, so the grid is 1 m everywhere (render.js boxGeometry).
	var uv_zy := func(p: Vector3) -> Vector2: return Vector2(p.z - z0, y1 - p.y) / 4.0
	var uv_xz := func(p: Vector3) -> Vector2: return Vector2(p.x - x0, p.z - z0) / 4.0
	var uv_xy := func(p: Vector3) -> Vector2: return Vector2(p.x - x0, y1 - p.y) / 4.0
	var faces := [
		[[Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)], Vector3.RIGHT, uv_zy],
		[[Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)], Vector3.LEFT, uv_zy],
		[[Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.UP, uv_xz],
		[[Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)], Vector3.DOWN, uv_xz],
		[[Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.BACK, uv_xy],
		[[Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)], Vector3.FORWARD, uv_xy],
	]
	for f: Array in faces:
		var verts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for p: Vector3 in f[0]:
			verts.append(p)
			uvs.append((f[2] as Callable).call(p))
		_add_face(st, verts, f[1], uvs)


## Wedge for a ramp (render.js rampGeometry).
static func _add_ramp(st: SurfaceTool, b: MapData.Box) -> void:
	var along_x := b.ramp_axis == 0
	var lo := (b.min_x if b.ramp_dir > 0 else b.max_x) if along_x else (b.min_z if b.ramp_dir > 0 else b.max_z)
	var hi := (b.max_x if b.ramp_dir > 0 else b.min_x) if along_x else (b.max_z if b.ramp_dir > 0 else b.min_z)
	var o0 := b.min_z if along_x else b.min_x
	var o1 := b.max_z if along_x else b.max_x
	var y0 := b.min_y
	var y1 := b.max_y
	var P := func(a: float, o: float, y: float) -> Vector3:
		return Vector3(a, y, o) if along_x else Vector3(o, y, a)
	var faces := [
		[P.call(lo, o0, y0), P.call(hi, o0, y0), P.call(hi, o1, y0), P.call(lo, o1, y0)], # bottom
		[P.call(hi, o0, y0), P.call(hi, o1, y0), P.call(hi, o1, y1), P.call(hi, o0, y1)], # tall end
		[P.call(lo, o0, y0), P.call(lo, o1, y0), P.call(hi, o1, y1), P.call(hi, o0, y1)], # slope
		[P.call(lo, o0, y0), P.call(hi, o0, y0), P.call(hi, o0, y1)], # sides
		[P.call(lo, o1, y0), P.call(hi, o1, y0), P.call(hi, o1, y1)],
	]
	# A point inside the wedge (its cross-section's centroid) to point every face away from. Not the
	# box center: the slope passes right through it, so which way the slope faced came down to
	# rounding and some slopes faced inward (culled, invisible from outside).
	var center: Vector3 = P.call(lo + (hi - lo) * 2.0 / 3.0, (o0 + o1) / 2, y0 + (y1 - y0) / 3.0)
	for f: Array in faces:
		var verts: Array[Vector3] = []
		for p: Vector3 in f:
			verts.append(p)
		var n := (verts[1] - verts[0]).cross(verts[2] - verts[0]).normalized()
		var mid := Vector3.ZERO
		for p in verts:
			mid += p
		mid /= verts.size()
		if n.dot(mid - center) < 0:
			n = -n
		var e1 := (verts[1] - verts[0]).normalized()
		var e2 := n.cross(e1)
		var uvs: Array[Vector2] = []
		for p in verts:
			var r := p - verts[0]
			uvs.append(Vector2(r.dot(e1), r.dot(e2)) / 4.0)
		_add_face(st, verts, n, uvs)


# ---------- markers ----------

static func build_pads(map: MapData, parent: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var disc_mat := toon_material(Color("ff5ab4"), false, 0.35)
	var ring_mat := toon_material(Color("ffffff"), false, 0.6)
	for pad in map.pads:
		var g := Node3D.new()
		g.position = Vector3(pad.x, pad.y, pad.z)
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = pad.radius
		cyl.bottom_radius = pad.radius
		cyl.height = 0.14
		disc.mesh = cyl
		disc.position.y = 0.07
		disc.material_override = with_outline(disc_mat.duplicate() as Material, 0.03)
		g.add_child(disc)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = pad.radius * 0.58
		torus.outer_radius = pad.radius * 0.72
		ring.mesh = torus
		ring.scale = Vector3(1, 0.35, 1)
		ring.position.y = 0.16
		ring.material_override = ring_mat
		g.add_child(ring)
		if pad.has_dir:
			var arrow := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.9, 1.0, 0.12)
			arrow.mesh = prism
			arrow.material_override = ring_mat
			# lay the triangle flat, pointing along the pad's direction
			arrow.rotation = Vector3(-PI / 2, atan2(-pad.dir_x, -pad.dir_z), 0)
			arrow.position.y = 0.3
			g.add_child(arrow)
		parent.add_child(g)
		out.append(g)
	return out


## Bean dummy (body + head capsules, eyes). Faces +Z; turn it with rotation.y.
static func make_bean(body_color := Color("ff8a3d"), head_color := Color("ffb35c")) -> Node3D:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.38
	cap.height = 1.44 # capsule from y 0.38 to 1.06 with 0.38 caps (combat.js DUMMY_PARTS)
	body.mesh = cap
	body.position.y = 0.72
	body.material_override = with_outline(toon_material(body_color), 0.03)
	g.add_child(body)
	var head := MeshInstance3D.new()
	var hcap := CapsuleMesh.new()
	hcap.radius = 0.2
	hcap.height = 0.46
	head.mesh = hcap
	head.position.y = 1.73
	head.material_override = with_outline(toon_material(head_color), 0.02)
	g.add_child(head)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color("1a1430")
	for x in [-0.075, 0.075]:
		var eye := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.035
		s.height = 0.08
		eye.mesh = s
		eye.material_override = eye_mat
		eye.position = Vector3(x, 1.77, 0.185)
		g.add_child(eye)
	return g


## Chunky low-poly cartoon clouds on a ring high above the map (render.js makeClouds).
static func build_clouds(parent: Node3D) -> Node3D:
	var group := Node3D.new()
	group.name = "Clouds"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD
	cloud_material = mat
	var puff := SphereMesh.new()
	puff.radius = 1.0 # same size as the web game's unit icosahedron puffs
	puff.height = 2.0
	puff.radial_segments = 8
	puff.rings = 4
	for i in 16:
		var cloud := Node3D.new()
		var puffs := 4 + rng.randi() % 4
		for j in puffs:
			var m := MeshInstance3D.new()
			m.mesh = puff
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var s := rng.randf_range(6, 11) * (1.3 if j == 0 else 1.0)
			m.scale = Vector3(s, s * 0.75, s)
			m.position = Vector3((j - puffs / 2.0) * rng.randf_range(6, 9), rng.randf_range(-1, 3), rng.randf_range(-4, 4))
			cloud.add_child(m)
		var a := (i / 16.0) * TAU + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(230, 320)
		cloud.position = Vector3(cos(a) * r, rng.randf_range(55, 95), sin(a) * r)
		cloud.rotation.y = -a + PI / 2
		group.add_child(cloud)
	parent.add_child(group)
	return group
