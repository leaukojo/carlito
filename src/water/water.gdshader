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
// Distance (m) past which the depth-derived terms (foam, shallow->deep blend) are gone and
// the surface reads as deep. The depth buffer resolves a 0.6 m foam band only up close; a
// 1 m column over a flat pan (every island) otherwise flickers foam and alpha all the way
// to the horizon. Fades in over [dist, 2*dist].
uniform float depth_fx_fade_dist = 90.0;
// Sun glitter: fine per-pixel ripple on the normals (ALU sin, no texture), fading with
// normal_fade_dist like the vertex waves.
uniform float glitter_strength = 0.35;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// World-space XZ: the waves and the foam breakup are anchored to the world, not the water
// body, so an `infinite` WaterSurface can re-centre on the camera without its waves moving.
// (VERTEX is view-space in fragment(), which would swim with the camera.)
varying vec2 v_wave_pos;
// Near->far settle of the ripple, shared by the vertex waves and the fragment glitter.
varying float v_fade;

// Same displacement the vertex uses, plus its analytic slope so lighting reacts to the
// waves. The wavelengths (~11-13 m) stay coarser than the 17.5 m quad only just; anything
// finer belongs in fragment() (see glitter), where it is sampled per pixel. All ALU.
void vertex() {
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	v_wave_pos = wp;
	float t = TIME * wave_speed;
	// Two waves travelling along directions ~35 and ~-55 degrees off the x axis: a product
	// of axis-aligned sines reads as a checkerboard grid once the mesh samples it well.
	const vec2 DA = vec2(0.82, 0.57);
	const vec2 DB = vec2(0.57, -0.82);
	float pa = t + dot(wp, DA) * 0.55;
	float pb = t * 0.8 + dot(wp, DB) * 0.47;
	VERTEX.y += (sin(pa) + sin(pb)) * 0.5 * wave_height;

	// d/dx and d/dz of the wave surface -> tangent-space slope.
	float ca = cos(pa) * 0.55 * 0.5 * wave_height;
	float cb = cos(pb) * 0.47 * 0.5 * wave_height;
	float dx = ca * DA.x + cb * DB.x;
	float dz = ca * DA.y + cb * DB.y;
	// Settle the ripple to flat with distance: near water stays wavy, far water goes
	// glassy so the reflected sky/clouds aren't distorted.
	float view_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	float fade = clamp(1.0 - view_dist / max(normal_fade_dist, 0.001), 0.0, 1.0);
	NORMAL = normalize(vec3(-dx * normal_strength * fade, 1.0, -dz * normal_strength * fade));
	v_fade = fade;
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
	// Depth-derived terms die out with distance (deep everywhere far away, no foam).
	float depth_fx = 1.0 - smoothstep(depth_fx_fade_dist, depth_fx_fade_dist * 2.0, frag_dist);
	float t = clamp(water_depth / max(depth_fade_m, 0.001), 0.0, 1.0);
	t = mix(1.0, t, depth_fx);

	vec3 base = mix(water_color.rgb, deep_color.rgb, t);

	// Glitter: two fine world-space sine ripples perturb the normal per pixel, so the sun
	// highlight breaks into moving sparkle instead of one vertex-smooth blob. World slope
	// goes to view space through VIEW_MATRIX (a direction, w = 0).
	float gt = TIME * wave_speed * 1.7;
	float gx = cos(gt + v_wave_pos.x * 1.9 + v_wave_pos.y * 0.6) + 0.6 * cos(gt * 1.3 - v_wave_pos.x * 4.1);
	float gz = cos(gt * 0.9 + v_wave_pos.y * 2.1 - v_wave_pos.x * 0.5) + 0.6 * cos(gt * 1.1 + v_wave_pos.y * 3.7);
	vec3 slope = (VIEW_MATRIX * vec4(-gx, 0.0, -gz, 0.0)).xyz;
	vec3 n = normalize(NORMAL + slope * glitter_strength * wave_height * v_fade);
	NORMAL = n;

	// Fresnel: at grazing angles water turns reflective and picks up the sky; looking
	// straight down it stays its own color. NORMAL/VIEW are view-space here.
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(base, sky_color.rgb, fresnel * 0.6);
	ALPHA = mix(mix(shallow_alpha, deep_alpha, t), 1.0, fresnel * 0.5);

	// Shoreline foam: strong at the waterline (water_depth -> 0), gone in deep water. A
	// cheap animated term breaks the band up so it reads as surf, not a flat contour.
	float foam_break = 0.85 + 0.15 * sin(TIME * wave_speed * 2.0 + v_wave_pos.x * 1.3 + v_wave_pos.y * 1.1);
	float foam = (1.0 - smoothstep(0.0, foam_depth_m, water_depth)) * foam_intensity * foam_break * depth_fx;
	ALBEDO = mix(ALBEDO, foam_color.rgb, foam);
	ALPHA = mix(ALPHA, 1.0, foam);

	// A mirror-sharp sun highlight on far, flat water aliases into a flickering point; let
	// the far surface go a little rougher so the highlight spreads and holds still.
	ROUGHNESS = mix(0.25, 0.08, v_fade);
	SPECULAR = 0.7;
}
