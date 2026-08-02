shader_type canvas_item;
// Subtle fullscreen color-grade + vignette. The gl_compatibility renderer has no glow or
// SSAO, so this is the safe post-process substitute: it frames the image and lifts the
// palette a touch without ever touching the tuned Environment or any level geometry.
//
// Reads the already-rendered frame through hint_screen_texture (auto back-buffer copy) and
// draws over a full-rect ColorRect that Level.gd builds in code. Kept strictly subtle so the
// low-poly crispness survives — this is a frame, not a filter.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Max corner darkening (0 = off). Small on purpose.
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.15;
// How far in from the corners the darkening reaches (larger = softer, starts nearer centre).
uniform float vignette_softness : hint_range(0.1, 1.5) = 0.75;
// Saturation lift (1.0 = unchanged); a small push so the palette reads richer.
uniform float saturation : hint_range(0.5, 1.5) = 1.08;
// Contrast around mid-grey (1.0 = unchanged); a tiny nudge to separate the fields.
uniform float contrast : hint_range(0.5, 1.5) = 1.03;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// Saturation: mix toward Rec.709 luma grey.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, saturation);

	// Contrast around mid-grey.
	col = (col - 0.5) * contrast + 0.5;

	// Vignette: smooth radial falloff from screen centre; the corners (dist ~0.707) darken
	// by up to vignette_intensity, the centre is untouched.
	float dist = distance(SCREEN_UV, vec2(0.5));
	float vig = smoothstep(vignette_softness, vignette_softness * 0.4, dist);
	col *= mix(1.0 - vignette_intensity, 1.0, vig);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
