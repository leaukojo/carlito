class_name ChallengeVisibility
extends RefCounted
## How a def's `ChallengeDef.Visibility` is laid over a level's lighting, and taken off again. It
## writes the listed properties of the level's own duplicated Environment and its sun, and returns a
## snapshot of what they held for `restore` to write back. Nothing new is rendered: pitch black is
## the lighting with no sun, zero ambient and a black sky, and blind is heavy fog. The presets are
## written against `default_env.tres`, the Environment every level shares (sky background, sky
## ambient, a light fog).
##
## The shell forces the level's day lighting before `apply` and restores its night choice only
## after `restore`, so the snapshot is always the day values and `set_night` never writes over a
## preset mid-attempt.

## DARK: only what the level and the vehicle carry light the world (headlights, lamps). Sky
## reflections go too, or the sky's radiance still shades every surface. The fog colour goes black,
## so the level's own light haze darkens the distance instead of glowing.
const DARK_ENV := {
	&"background_mode": Environment.BG_COLOR,
	&"background_color": Color.BLACK,
	&"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
	&"ambient_light_color": Color.BLACK,
	&"ambient_light_energy": 0.0,
	&"reflected_light_source": Environment.REFLECTION_SOURCE_DISABLED,
	&"fog_light_color": Color.BLACK,
}
const DARK_SUN := {&"visible": false}


## FOG: exponential, over the sky as well so the horizon gives nothing away, with no sun glow
## through it. The level's own fog colour stays. `fog_mode` stays ahead of `fog_density`, here and
## so in every snapshot, because setting the mode resets the density.
static func fog_env(density: float) -> Dictionary:
	return {
		&"fog_enabled": true,
		&"fog_mode": Environment.FOG_MODE_EXPONENTIAL,
		&"fog_density": density,
		&"fog_sky_affect": 1.0,
		&"fog_sun_scatter": 0.0,
	}


## Lay `visibility` over `env` and `sun` (either may be null) and return what `restore` needs. DAY
## changes nothing.
static func apply(env: Environment, sun: DirectionalLight3D, visibility: ChallengeDef.Visibility,
		fog_density: float) -> Dictionary:
	var env_values := {}
	var sun_values := {}
	match visibility:
		ChallengeDef.Visibility.DARK:
			env_values = DARK_ENV
			sun_values = DARK_SUN
		ChallengeDef.Visibility.FOG:
			env_values = fog_env(fog_density)
	return {&"env": _write(env, env_values), &"sun": _write(sun, sun_values)}


static func restore(env: Environment, sun: DirectionalLight3D, snapshot: Dictionary) -> void:
	_write(env, snapshot.get(&"env", {}))
	_write(sun, snapshot.get(&"sun", {}))


## Set each property on `obj`, in the dictionary's order, and return the values they replaced. All
## are read before any is written: setting `fog_mode` resets `fog_density`, even to the same mode.
static func _write(obj: Object, values: Dictionary) -> Dictionary:
	var before := {}
	if obj == null:
		return before
	for prop: StringName in values:
		before[prop] = obj.get(prop)
	for prop: StringName in values:
		obj.set(prop, values[prop])
	return before
