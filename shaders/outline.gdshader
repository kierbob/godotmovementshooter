// Cartoon outline shell (drawn back faces only, in ink). The mesh is already inflated along smooth
// normals by Models.shell(); here it's also pushed a little away from the camera, along the line
// of sight so it doesn't move on screen. That keeps the outline around the silhouette (nothing is
// behind it there) but hides it wherever it overlaps the model itself: the Kenney guns are built
// from overlapping blocks, and an inner block's shell used to paint whole faces black.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.082, 0.082, 0.122, 1.0);
uniform float push = 0.0; // in the mesh's own units (scaled with the model)

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	v.xyz += normalize(v.xyz) * push * s;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = ink.rgb;
}
