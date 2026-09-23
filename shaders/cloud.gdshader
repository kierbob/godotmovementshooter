// Chunky cartoon clouds: toon-banded like everything else, but never fogged (they're far away).
shader_type spatial;
render_mode specular_disabled, fog_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 0.941, 0.984, 1.0);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = albedo.rgb * mix(vec3(0.75, 0.68, 0.85), vec3(1.0), world_normal.y * 0.5 + 0.5) * 0.55;
}

void light() {
	float d = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = d < 1.0 / 3.0 ? 0.353 : (d < 2.0 / 3.0 ? 0.667 : 1.0);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
}
