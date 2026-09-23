// Cartoon shading matching the web game (three.js MeshToonMaterial + HemisphereLight):
// the sun lights surfaces in three hard bands, and a sky/ground "hemisphere" color fills the rest.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
// Hemisphere ambient: sky color on up-facing surfaces, ground color on down-facing ones.
// Global so the lighting preset (look.gd) changes every material at once. Linear colors.
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
global uniform float hemi_energy;
uniform float emission_boost = 0.0; // glowy bits (jump pads)

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// three.js lights divide by PI (Lambert); same here so the same intensities look the same.
	vec3 hemi = mix(hemi_ground, hemi_sky, world_normal.y * 0.5 + 0.5) * hemi_energy / PI;
	EMISSION = base * (hemi + emission_boost);
}

void light() {
	// Faces turned away from the sun are always in their own shape's shadow: no sunlight (this
	// also avoids shadow-map speckle on them).
	float ndl = dot(NORMAL, LIGHT);
	if (ndl > 0.0) {
		// Three hard bands, like the web game's 3-texel toon gradient (90, 170, 255).
		float d = ndl * 0.5 + 0.5;
		float band = d < 2.0 / 3.0 ? 0.667 : 1.0;
		DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
	}
}
