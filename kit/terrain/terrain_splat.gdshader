shader_type spatial;
// 8-color splat ground material: albedo colors blended by weights read from
// TWO RGBA splatmaps — channels 0..3 = splatmap.RGBA (grass/dirt/sand/rock, TerrainGen's
// channel order), channels 4..7 = splatmap2.RGBA. The second map is OPTIONAL: unbound it
// samples transparent (all-zero weights), so a 4-channel terrain looks exactly as before.
// Plain arithmetic + two samplers, gl_compatibility-safe; no texture layers by design (plan:
// low-poly color fields). The splatmaps are raw weight data, NOT source_color — sRGB
// conversion would bend the weights. UV is HeightmapTerrain's global 0..1 terrain UV,
// identical across render chunks, so splat blending never seams at chunk borders.
//
// The eight colors are per-level: they are material shader params, so each level dials its
// own palette (and HeightmapTerrain.channel_names labels them for the brush panel).

uniform vec4 grass_color : source_color = vec4(0.35, 0.55, 0.25, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.52, 0.40, 0.26, 1.0);
uniform vec4 sand_color : source_color = vec4(0.83, 0.76, 0.55, 1.0);
uniform vec4 rock_color : source_color = vec4(0.45, 0.44, 0.42, 1.0);
uniform vec4 color5 : source_color = vec4(0.92, 0.94, 0.97, 1.0);  // snow
uniform vec4 color6 : source_color = vec4(0.30, 0.24, 0.17, 1.0);  // mud
uniform vec4 color7 : source_color = vec4(0.22, 0.22, 0.24, 1.0);  // asphalt
uniform vec4 color8 : source_color = vec4(0.62, 0.60, 0.56, 1.0);  // gravel
uniform sampler2D splatmap : filter_linear, repeat_disable, hint_default_black;
// hint_default_transparent, NOT _black: the engine's default black texture is OPAQUE black
// (alpha 255), which would give every unpainted terrain a full-weight channel 8.
uniform sampler2D splatmap2 : filter_linear, repeat_disable, hint_default_transparent;
// Contrast between the color fields: weights are pow-sharpened and renormalized, so
// the dominant channel wins fast (crisp low-poly borders) instead of long soft fades.
uniform float blend_sharpness : hint_range(1.0, 16.0) = 8.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 w = pow(texture(splatmap, UV), vec4(blend_sharpness));
	vec4 w2 = pow(texture(splatmap2, UV), vec4(blend_sharpness));
	float total = w.r + w.g + w.b + w.a + w2.r + w2.g + w2.b + w2.a;
	vec3 blend = grass_color.rgb * w.r + dirt_color.rgb * w.g
			+ sand_color.rgb * w.b + rock_color.rgb * w.a
			+ color5.rgb * w2.r + color6.rgb * w2.g
			+ color7.rgb * w2.b + color8.rgb * w2.a;
	// No splatmap bound (hint_default_black) or an empty pixel: plain grass, not black.
	ALBEDO = total > 0.001 ? blend / total : grass_color.rgb;
	ROUGHNESS = roughness_value;
}
