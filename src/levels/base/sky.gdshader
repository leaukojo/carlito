shader_type sky;
render_mode use_debanding;

// Gradient + sun disc (reimplemented from ProceduralSkyMaterial's tuned values)
// plus two octaves of scrolling noise clouds. Night tinting is handled by the
// Environment's background_energy_multiplier (Level.gd), so no night uniform here.

uniform vec4 sky_top_color : source_color = vec4(0.23, 0.42, 0.72, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.72, 0.82, 0.92, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.16, 0.36, 0.47, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.72, 0.82, 0.92, 1.0);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.12;

uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.62, 0.68, 0.78, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.006;
uniform sampler2D cloud_noise : hint_default_black, filter_linear_mipmap, repeat_enable;

void sky() {
	float horizon = clamp(EYEDIR.y, -1.0, 1.0);

	// Vertical gradient, sharpened near the horizon by sky_curve (matches PSM).
	float up = clamp(horizon, 0.0, 1.0);
	float t = 1.0 - pow(1.0 - up, 1.0 / max(sky_curve, 0.001));
	vec3 sky_col = mix(sky_horizon_color.rgb, sky_top_color.rgb, t);

	float down = clamp(-horizon, 0.0, 1.0);
	float gt = 1.0 - pow(1.0 - down, 1.0 / max(sky_curve, 0.001));
	vec3 ground_col = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, gt);

	vec3 col = horizon >= 0.0 ? sky_col : ground_col;

	// Sun disc + soft glow from the primary directional light.
	float sun = dot(EYEDIR, LIGHT0_DIRECTION);
	col += LIGHT0_COLOR * LIGHT0_ENERGY * smoothstep(0.9995, 0.9999, sun);
	col += LIGHT0_COLOR * LIGHT0_ENERGY * 0.15 * smoothstep(0.995, 1.0, sun);

	// Clouds: project the view onto a plane above the horizon so they read as a
	// dome. Only draw them in the upper hemisphere, fading in from the horizon.
	if (horizon > 0.0) {
		vec2 uv = EYEDIR.xz / (horizon + 0.15);
		vec2 flow = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = texture(cloud_noise, uv * 0.15 + flow).r;
		n += 0.5 * texture(cloud_noise, uv * 0.35 - flow * 1.7).r;
		n /= 1.5;

		float density = smoothstep(cloud_coverage, cloud_coverage + 0.25, n);
		float band = smoothstep(0.02, 0.35, horizon) * smoothstep(1.0, 0.6, horizon);
		density *= band;

		vec3 cloud = mix(cloud_shadow_color.rgb, cloud_color.rgb, smoothstep(0.4, 0.9, n));
		col = mix(col, cloud, density);
	}

	COLOR = col;
}
