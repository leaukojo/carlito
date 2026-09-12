shader_type spatial;
// InfiniteGround's surface: a checker of `cell_m` squares with minor lines on every cell and
// major lines every `major_every` cells, laid in WORLD space so the mesh can re-centre under
// the camera without the pattern moving. Filtered with fwidth, so the far field settles to
// the mean colour instead of shimmering.

uniform vec4 color_a : source_color = vec4(0.36, 0.48, 0.30, 1.0);
uniform vec4 color_b : source_color = vec4(0.31, 0.43, 0.26, 1.0);
uniform vec4 line_color : source_color = vec4(0.86, 0.90, 0.80, 1.0);
uniform float cell_m = 10.0;
uniform float major_every = 10.0;
// Line width in metres (major lines are twice this).
uniform float line_m = 0.15;

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Coverage of a grid line of `width` (in cell units) at `p` (in cell units). Never drawn
// thinner than a pixel; a sub-pixel line fades by its true coverage instead.
float grid_line(vec2 p, float width) {
	vec2 w = max(fwidth(p), vec2(1e-5));
	vec2 draw_w = max(vec2(width), w);
	vec2 d = abs(fract(p - 0.5) - 0.5) * 2.0;
	vec2 l = 1.0 - smoothstep(draw_w - w * 1.5, draw_w + w * 1.5, d);
	l *= clamp(vec2(width) / draw_w, 0.0, 1.0);
	l = mix(l, vec2(width), clamp(w * 2.0 - 1.0, 0.0, 1.0));
	return max(l.x, l.y);
}

void fragment() {
	vec2 p = v_world / cell_m;
	vec2 w = max(fwidth(p), vec2(1e-5));
	// Box-filtered checker (period two cells).
	vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
	float check = 0.5 - 0.5 * i.x * i.y;
	vec3 col = mix(color_a.rgb, color_b.rgb, check);
	float minor = grid_line(p, line_m / cell_m);
	float major = grid_line(p / major_every, 2.0 * line_m / (cell_m * major_every));
	col = mix(col, line_color.rgb, max(minor * 0.35, major * 0.8));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
