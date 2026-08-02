shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Water surface visuals: the waves here are SHADER-ONLY — physics reads
// WaterSurface.get_height(), which is flat. Never feed VERTEX.y back into gameplay.
//
// Depth-fade: shallow water stays translucent, deep water goes opaque + bluer, so the
// seafloor (and the square map edge past it) fades out instead of showing through. This
// is fragment shading only — get_height() is untouched.

uniform vec4 water_color : source_color = vec4(0.10, 0.38, 0.52, 0.78);
// Slightly darker/bluer for deep water.
uniform vec4 deep_color : source_color = vec4(0.03, 0.14, 0.26, 1.0);
uniform float shallow_alpha = 0.45;
uniform float deep_alpha = 0.96;
// Water column depth (m) over which shallow fades to fully deep.
uniform float depth_fade_m = 6.0;
uniform float wave_height = 0.10;
uniform float wave_speed = 1.1;
// Sky tint mixed in at grazing angles (Fresnel). Keep close to the level's sky/horizon.
uniform vec4 sky_color : source_color = vec4(0.55, 0.70, 0.85, 1.0);
// Shoreline foam: a light band where the water column is shallow (water_depth -> 0),
// so surf hugs every coast and the vehicle waterline. Reuses the depth reconstruction
// below; all ALU, no extra texture reads.
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
// Water-column depth (m) over which foam fades out (band sits between depth 0 and this).
uniform float foam_depth_m = 0.6;
// Overall foam strength; a level can dial it down.
uniform float foam_intensity = 0.9;
// How much the moving wave normals ripple the surface (0 = flat lighting).
uniform float normal_strength = 0.6;
// Distance (m) over which wave normals settle back to flat, so distant water reflects the
// sky cleanly instead of making the clouds look wavy. Ripple stays full up close.
uniform float normal_fade_dist = 60.0;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// Model-space XZ passed to the fragment stage so the foam breakup is anchored to the water
// body (VERTEX is view-space in fragment(), which would swim with the camera).
varying vec2 v_wave_pos;

// Same displacement the vertex uses, plus its analytic slope so lighting reacts to the
// waves. A second, faster/finer octave rides on the normals only (no extra displacement)
// to add sparkle without more vertex motion. All ALU — no texture reads.
void vertex() {
	v_wave_pos = VERTEX.xz;
	float t = TIME * wave_speed;
	float sx = sin(t + VERTEX.x * 0.55);
	float sz = sin(t * 0.8 + VERTEX.z * 0.47);
	VERTEX.y += sx * sz * wave_height;

	// d/dx and d/dz of the wave surface -> tangent-space slope.
	float dx = 0.55 * cos(t + VERTEX.x * 0.55) * sz * wave_height;
	float dz = 0.47 * sx * cos(t * 0.8 + VERTEX.z * 0.47) * wave_height;
	// Finer ripple octave (normal only).
	float t2 = TIME * wave_speed * 1.7;
	dx += 0.9 * cos(t2 + VERTEX.x * 1.9) * wave_height * 0.5;
	dz += 0.9 * cos(t2 * 0.9 + VERTEX.z * 2.1) * wave_height * 0.5;

	// Settle the ripple to flat with distance: near water stays wavy, far water goes
	// glassy so the reflected sky/clouds aren't distorted.
	float view_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	float fade = clamp(1.0 - view_dist / max(normal_fade_dist, 0.001), 0.0, 1.0);
	NORMAL = normalize(vec3(-dx * normal_strength * fade, 1.0, -dz * normal_strength * fade));
}

void fragment() {
	// Reconstruct the opaque scene's view-space distance behind this water fragment.
	// gl_compatibility: NDC z is [-1, 1], so depth is remapped with * 2.0 - 1.0
	// (Forward+ would leave it as-is). Transparent pass reads the opaque depth buffer.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float frag_dist = -VERTEX.z;   // VERTEX is view-space in fragment()
	float water_depth = scene_dist - frag_dist;
	float t = clamp(water_depth / max(depth_fade_m, 0.001), 0.0, 1.0);

	vec3 base = mix(water_color.rgb, deep_color.rgb, t);

	// Fresnel: at grazing angles water turns reflective and picks up the sky; looking
	// straight down it stays its own color. NORMAL/VIEW are view-space here.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(base, sky_color.rgb, fresnel * 0.6);
	ALPHA = mix(mix(shallow_alpha, deep_alpha, t), 1.0, fresnel * 0.5);

	// Shoreline foam: strong at the waterline (water_depth -> 0), gone in deep water. A
	// cheap animated term breaks the band up so it reads as surf, not a flat contour.
	float foam_break = 0.85 + 0.15 * sin(TIME * wave_speed * 2.0 + v_wave_pos.x * 1.3 + v_wave_pos.y * 1.1);
	float foam = (1.0 - smoothstep(0.0, foam_depth_m, water_depth)) * foam_intensity * foam_break;
	ALBEDO = mix(ALBEDO, foam_color.rgb, foam);
	ALPHA = mix(ALPHA, 1.0, foam);

	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
