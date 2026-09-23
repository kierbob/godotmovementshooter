class_name Look
## Lighting presets (render.js LIGHTING): sky gradient, sun, hemisphere fill, fog and exposure.
## sky = [top, horizon]; sun_dir = where the sun sits; hemi = sky/ground fill light.

const PRESETS := {
	"sunny": {
		"label": "Sunny Toon", "sky": [Color("3aa6ff"), Color("bfeaff")], "fog": Color("bfeaff"), "fog_near": 55.0, "fog_far": 300.0,
		"hemi_sky": Color("eef8ff"), "hemi_ground": Color("6e5c86"), "hemi": 1.55, "sun": Color("fff1d6"), "sun_i": 2.6,
		"sun_dir": Vector3(35, 60, 25), "exposure": 1.0, "cloud": Color("ffffff"), "sun_disc": Color("fff6cf"),
	},
	"pastel": {
		"label": "Candy Pastel", "sky": [Color("ff9fd8"), Color("a9e6ff")], "fog": Color("b9dcff"), "fog_near": 55.0, "fog_far": 300.0,
		"hemi_sky": Color("fff2ff"), "hemi_ground": Color("9a80c8"), "hemi": 1.8, "sun": Color("fff6fb"), "sun_i": 2.1,
		"sun_dir": Vector3(25, 65, 30), "exposure": 1.05, "cloud": Color("fff0fb"), "sun_disc": Color("ffffff"),
	},
	"arcade": {
		"label": "Arcade Punch", "sky": [Color("1452ff"), Color("6fd2ff")], "fog": Color("6fd2ff"), "fog_near": 60.0, "fog_far": 320.0,
		"hemi_sky": Color("ffffff"), "hemi_ground": Color("3b2470"), "hemi": 1.05, "sun": Color("ffffff"), "sun_i": 3.8,
		"sun_dir": Vector3(40, 55, -30), "exposure": 1.02, "cloud": Color("ffffff"), "sun_disc": Color("fffbe6"),
	},
}


static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


## Apply a preset to the environment, sun, sky and clouds (and the toon shader's global fill light).
static func apply(id: String, env: Environment, sun: DirectionalLight3D, sky_mat: ShaderMaterial, cloud_mat: ShaderMaterial) -> void:
	var p: Dictionary = PRESETS.get(id, PRESETS.pastel)
	sky_mat.set_shader_parameter("top_color", p.sky[0])
	sky_mat.set_shader_parameter("horizon_color", p.sky[1])
	sky_mat.set_shader_parameter("sun_color", p.sun_disc)
	env.fog_light_color = p.fog
	env.fog_depth_begin = p.fog_near
	env.fog_depth_end = p.fog_far
	env.tonemap_exposure = p.exposure
	sun.light_color = p.sun
	sun.light_energy = p.sun_i / PI # three.js lights divide by PI; see toon.gdshader
	sun.look_at_from_position(p.sun_dir, Vector3.ZERO)
	RenderingServer.global_shader_parameter_set("hemi_sky", _lin(p.hemi_sky))
	RenderingServer.global_shader_parameter_set("hemi_ground", _lin(p.hemi_ground))
	RenderingServer.global_shader_parameter_set("hemi_energy", p.hemi)
	if cloud_mat:
		cloud_mat.set_shader_parameter("albedo", p.cloud)
