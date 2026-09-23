class_name TrialView
extends Node3D
## Time trial visuals (the web game's trialview.js): the teleport portals (a ring with a spinning
## swirl and a comic label), the timer board over the start gate, a START banner and the checkered
## FINISH arch. Reads TimeTrial; never changes it.

const INK := Color("15151f")

var _trial: TimeTrial
var _font: Font
var _portals: Array = [] # [{ring, swirl}]
var _board_lines := {} # name -> Label3D
var _board_key := ""
var _time := 0.0


func setup(trial: TimeTrial) -> void:
	_trial = trial
	_font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
	var hub := Vector3(float(trial.spawn.x), 0, float(trial.spawn.z))
	var start := _v(trial.course.start)
	for p: Dictionary in trial.portals:
		var guns: bool = p.guns
		_add_portal(p, Color("ff9a3c") if guns else Color("3cf0a0"),
			[p.label, p.sub, Color("ffb45a") if guns else Color("7dffc4")], hub)
	_add_portal(trial.course.exit, Color("7ab8ff"), [trial.course.exit.label, "", Color.WHITE], start)
	_build_board()
	_build_banners()


static func _v(d: Dictionary) -> Vector3:
	return Vector3(float(d.x), float(d.get("y", 0.0)), float(d.z))


## Comic text in the world: yellow-ish fill, thick ink outline, always faces the camera.
func _label(text: String, size: int, color: Color, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.modulate = color
	l.outline_size = maxi(8, size / 5)
	l.outline_modulate = INK
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


func _toon(mesh: Mesh, color: Color, outline := 0.03) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WorldView.toon_material(color)
	if outline > 0:
		Models.add_outline(mi, outline)
	return mi


## A portal that turns to face `face_toward`, so you see it head-on on your way over.
func _add_portal(p: Dictionary, color: Color, lines: Array, face_toward: Vector3) -> void:
	var g := Node3D.new()
	g.position = _v(p)
	g.rotation.y = atan2(face_toward.x - g.position.x, face_toward.z - g.position.z)
	add_child(g)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.3
	base_mesh.bottom_radius = 1.4
	base_mesh.height = 0.2
	var base := _toon(base_mesh, Color("2a3150"))
	base.position.y = 0.1
	g.add_child(base)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.24
	var ring := _toon(torus, color)
	ring.position.y = 1.35
	ring.rotation.x = PI / 2 # stand the ring up, facing along the portal's forward axis
	g.add_child(ring)
	var disc := QuadMesh.new()
	disc.size = Vector2(2.0, 2.0)
	var swirl := MeshInstance3D.new()
	swirl.mesh = disc
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _swirl_texture(color)
	swirl.material_override = m
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	swirl.position.y = 1.35
	g.add_child(swirl)
	var title := _label(lines[0], 64, Color("ffe14d"))
	title.position.y = 3.55
	g.add_child(title)
	if lines[1] != "":
		var sub := _label(lines[1], 52, lines[2])
		sub.position.y = 2.95
		g.add_child(sub)
	_portals.append({"ring": ring, "swirl": swirl})


## Soft glowing disc with four white swirl arms (trialview.js swirlTexture).
static func _swirl_texture(color: Color) -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size / 2.0 + 0.5, y - size / 2.0 + 0.5) / (size / 2.0)
			var r := d.length()
			if r >= 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# radial gradient: white core -> portal color -> clear edge
			var c := Color.WHITE.lerp(color, clampf((r - 0.08) / 0.42, 0, 1))
			c.a = 1.0 if r < 0.5 else 1.0 - (r - 0.5) / 0.5
			# four arms curling outward
			var arm := absf(fmod(d.angle() * 2.0 / PI + r * 1.6 + 8.0, 1.0) - 0.5)
			if arm < 0.07 and r > 0.12 and r < 0.8:
				c = c.lerp(Color(1, 1, 1, 0.85), 0.8)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _build_board() -> void:
	var b: Dictionary = _trial.course.board
	var at := Vector3(float(b.x), float(b.y), float(b.z))
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(float(b.w) + 0.4, float(b.h) + 0.4, 0.3)
	var frame := _toon(frame_mesh, Color("ffd35a"))
	frame.position = at - Vector3(0, 0, 0.1)
	add_child(frame)
	var screen_mesh := QuadMesh.new()
	screen_mesh.size = Vector2(float(b.w), float(b.h))
	var screen := MeshInstance3D.new()
	screen.mesh = screen_mesh
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color("141a3a")
	screen.material_override = sm
	screen.position = at + Vector3(0, 0, 0.06)
	add_child(screen)
	# Text rows (board faces +Z, toward the start room). Heights follow the web board's layout.
	var h := float(b.h)
	var rows := {
		"title": [0.37, 60, Color("ffe14d")], "mode": [0.22, 42, Color.WHITE], "clock": [-0.02, 100, Color("9ff0ff")],
		"off": [-0.33, 36, Color("7dffc4")], "on": [-0.33, 36, Color("ffb45a")],
	}
	for key: String in rows:
		var row: Array = rows[key]
		var l := _label("", row[1], row[2], false)
		l.pixel_size = h / 384.0 # the web board is 384 px tall
		var x := 0.0 if key in ["title", "mode", "clock"] else float(b.w) * (-0.23 if key == "off" else 0.23)
		l.position = at + Vector3(x, h * float(row[0]), 0.08)
		add_child(l)
		_board_lines[key] = l
	_board_lines.title.text = "TIME TRIAL"


func _build_banners() -> void:
	var start := _v(_trial.course.start)
	var sb := _label("START", 64, Color("ffe14d"))
	sb.position = Vector3(start.x, 5.0, 1.2)
	add_child(sb)
	var f: Dictionary = _trial.course.finish
	var cx := (float(f.min.x) + float(f.max.x)) / 2
	var cz := (float(f.min.z) + float(f.max.z)) / 2
	var y0 := float(f.min.y)
	for x: float in [float(f.min.x), float(f.max.x)]:
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.5, 5, 0.5)
		var post := _toon(post_mesh, Color.WHITE)
		post.position = Vector3(x, y0 + 2.5, cz)
		add_child(post)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(float(f.max.x) - float(f.min.x) + 0.5, 1, 0.5)
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = _checker_texture()
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bm.uv1_scale = Vector3(2, 1, 1)
	beam.material_override = bm
	Models.add_outline(beam, 0.03)
	beam.position = Vector3(cx, y0 + 5, cz)
	add_child(beam)
	var fl := _label("FINISH!", 64, Color("ffe14d"))
	fl.position = Vector3(cx, y0 + 6.6, cz)
	add_child(fl)


static func _checker_texture() -> Texture2D:
	var img := Image.create(8, 2, false, Image.FORMAT_RGBA8)
	for y in 2:
		for x in 8:
			img.set_pixel(x, y, INK if (x + y) % 2 else Color.WHITE)
	return ImageTexture.create_from_image(img)


func update(dt: float) -> void:
	_time += dt
	for p: Dictionary in _portals:
		(p.swirl as Node3D).rotation.z -= dt * 2.5
		(p.ring as Node3D).scale = Vector3.ONE * (1 + sin(_time * 3) * 0.03)
	var t := _trial
	# Only touch the text when what it shows changes (10x a second while the clock runs).
	var key := "%s|%s|%s|%s|%s|%s|%s" % [t.guns, t.running, floori(t.time * 10) if t.running else t.last[t.mode()],
		t.best.on, t.best.off, t.last.on, t.last.off]
	if key == _board_key:
		return
	_board_key = key
	(_board_lines.mode as Label3D).text = "GUNS ON" if t.guns else "GUNS OFF"
	(_board_lines.mode as Label3D).modulate = Color("ffb45a") if t.guns else Color("7dffc4")
	var clock: Label3D = _board_lines.clock
	clock.text = TimeTrial.format_time(t.time if t.running else maxf(0.0, t.last[t.mode()]))
	clock.modulate = Color.WHITE if t.running else Color("9ff0ff")
	for k: String in ["off", "on"]:
		(_board_lines[k] as Label3D).text = "GUNS %s\nBEST %s\nLAST %s" % [k.to_upper(),
			TimeTrial.format_time(t.best[k]), TimeTrial.format_time(t.last[k])]
