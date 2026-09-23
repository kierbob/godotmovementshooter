extends SceneTree
## Draws the cartoon effect textures (the web game's fx.js canvas textures) and saves them to
## assets/fx/: the comic POW star, the muzzle "action lines" and three bullet holes. They're
## baked once and committed, so the game just loads PNGs. Needs a real renderer, not --headless:
##   godot --path . --script res://tools/make_fx_textures.gd

const INK := Color("15151f")


## Jagged star outline: alternating outer/inner points with a little random wobble.
static func jagged(points: int, r_outer: float, r_inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var r := r_inner * randf_range(0.85, 1.1) if i % 2 else r_outer * randf_range(0.9, 1.1)
		var a := float(i) / (points * 2) * TAU
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


class Canvas:
	extends Node2D
	var jobs: Array[Callable] = []

	func _draw() -> void:
		for j in jobs:
			j.call(self)


func poly(c: Node2D, pts: PackedVector2Array, fill: Color, stroke := Color(0, 0, 0, 0), width := 0.0) -> void:
	if fill.a > 0:
		c.draw_colored_polygon(pts, fill)
	if width > 0:
		# Each edge on its own plus a dot on every corner = round joins (canvas lineJoin 'round');
		# a thick polyline would grow long miter spikes on the sharp tips.
		for i in pts.size():
			c.draw_line(pts[i], pts[(i + 1) % pts.size()], stroke, width, true)
			c.draw_circle(pts[i], width / 2, stroke)


func render(size: int, draw: Callable, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Canvas.new()
	canvas.position = Vector2(size, size) / 2
	canvas.scale = Vector2.ONE * (size / 128.0)
	canvas.jobs.append(draw)
	vp.add_child(canvas)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(size / 2, size / 2, Image.INTERPOLATE_LANCZOS) # drawn at 2x, scaled down = smooth edges
	img.save_png(path)
	print("wrote ", path)
	vp.queue_free()


func _init() -> void:
	seed(7)
	DirAccess.make_dir_recursive_absolute("res://assets/fx")
	await process_frame

	# POW star: white jagged star with a thick ink outline, and a white core.
	var outer := jagged(8, 56, 26)
	var core := jagged(8, 30, 16)
	await render(256, func(c: Node2D) -> void:
		poly(c, outer, Color.WHITE, INK, 7)
		poly(c, core, Color.WHITE), "res://assets/fx/star.png")

	# Action lines: 14 thin spikes radiating out, pale yellow with an ink outline.
	var spikes: Array[PackedVector2Array] = []
	for i in 14:
		var a := float(i) / 14 * TAU + randf_range(-0.1, 0.1)
		var r0 := randf_range(46, 64)
		var r1 := randf_range(100, 124)
		var w := randf_range(0.035, 0.06)
		spikes.append(PackedVector2Array([Vector2(cos(a - w), sin(a - w)) * r0, Vector2(cos(a), sin(a)) * r1,
			Vector2(cos(a + w), sin(a + w)) * r0]))
	await render(512, func(c: Node2D) -> void:
		c.scale = Vector2.ONE * 2.0 # this one is 256 px in the web game
		for s in spikes:
			poly(c, s, Color(0, 0, 0, 0), INK, 5)
		for s in spikes:
			c.draw_colored_polygon(s, Color("fff6c0")), "res://assets/fx/lines.png")

	# Bullet holes: a few cracks, a pale rim, a dark splotch, a black center.
	for n in 3:
		var cracks: Array[PackedVector2Array] = []
		for i in 5:
			var a := randf_range(0, TAU)
			var r := randf_range(44, 58)
			cracks.append(PackedVector2Array([Vector2(cos(a), sin(a)) * 26,
				Vector2(cos(a + randf_range(-0.2, 0.2)), sin(a + randf_range(-0.2, 0.2))) * r]))
		var rim := jagged(9, 40, 30)
		var splotch := jagged(8, 30, 22)
		await render(256, func(c: Node2D) -> void:
			for cr in cracks:
				c.draw_line(cr[0], cr[1], Color("1b1d28"), 5, true)
				c.draw_circle(cr[1], 2.5, Color("1b1d28"))
			poly(c, rim, Color(1, 1, 1, 0.45))
			poly(c, splotch, Color("1b1d28"))
			c.draw_circle(Vector2.ZERO, 11, Color("05060a")), "res://assets/fx/hole_%d.png" % n)
	quit()
