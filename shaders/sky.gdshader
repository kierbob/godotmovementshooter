// Candy Pastel sky: pink overhead fading to light blue at the horizon, with a soft round sun.
shader_type sky;

uniform vec3 top_color : source_color = vec3(1.0, 0.624, 0.847);
uniform vec3 horizon_color : source_color = vec3(0.663, 0.902, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0);

void sky() {
	float h = EYEDIR.y;
	// Mostly pink; the blue only shows near and below the horizon (like the web game's backdrop).
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.25, 0.4, h));
	if (LIGHT0_ENABLED) {
		float ang = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		float core = 1.0 - smoothstep(0.045, 0.055, ang);
		float halo = (1.0 - smoothstep(0.055, 0.16, ang)) * 0.55;
		col = mix(col, sun_color, max(core, halo));
	}
	COLOR = col;
}
