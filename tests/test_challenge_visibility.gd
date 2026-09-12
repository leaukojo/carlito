extends GdUnitTestSuite
## ChallengeVisibility: the DARK and FOG presets laid over a level's own Environment and sun, and
## the snapshot that puts back exactly what was there.

const V := ChallengeDef.Visibility
const DAY_ENV := "res://src/levels/base/default_env.tres"


func _env() -> Environment:
	return (load(DAY_ENV) as Environment).duplicate(true) as Environment


func _sun() -> DirectionalLight3D:
	return auto_free(DirectionalLight3D.new()) as DirectionalLight3D


func test_dark_leaves_nothing_lit_but_the_level_and_the_vehicle() -> void:
	var env := _env()
	var sun := _sun()
	ChallengeVisibility.apply(env, sun, V.DARK, 0.0)
	assert_bool(sun.visible).is_false()
	assert_int(env.background_mode).is_equal(Environment.BG_COLOR)
	assert_object(env.background_color).is_equal(Color.BLACK)
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)
	assert_float(env.ambient_light_energy).is_equal(0.0)
	assert_int(env.reflected_light_source).is_equal(Environment.REFLECTION_SOURCE_DISABLED)
	assert_object(env.fog_light_color).is_equal(Color.BLACK)


func test_fog_covers_the_sky_at_the_def_density() -> void:
	var env := _env()
	ChallengeVisibility.apply(env, _sun(), V.FOG, 0.12)
	assert_bool(env.fog_enabled).is_true()
	assert_int(env.fog_mode).is_equal(Environment.FOG_MODE_EXPONENTIAL)
	assert_float(env.fog_density).is_equal_approx(0.12, 1e-6)
	assert_float(env.fog_sky_affect).is_equal(1.0)


## Restore puts back exactly what was there — every stored property of both objects, not only the
## ones a preset lists, since an Environment setter can move a property beside its own (setting
## `fog_mode` resets `fog_density`).
func test_restore_puts_back_exactly_what_was_there() -> void:
	for vis: V in [V.DARK, V.FOG]:
		var env := _env()
		var sun := _sun()
		var env_before := _stored(env)
		var sun_before := _stored(sun)
		var snapshot := ChallengeVisibility.apply(env, sun, vis, 0.12)
		ChallengeVisibility.restore(env, sun, snapshot)
		for pair: Array in [[env_before, _stored(env)], [sun_before, _stored(sun)]]:
			var was: Dictionary = pair[0]
			var now: Dictionary = pair[1]
			for prop: StringName in was:
				assert_that(now[prop]).override_failure_message(
						"%s after %s" % [prop, vis]).is_equal(was[prop])


## Every stored property of `obj`, by name.
func _stored(obj: Object) -> Dictionary:
	var out := {}
	for p in obj.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE:
			out[StringName(p.name)] = obj.get(p.name)
	return out


func test_day_changes_nothing() -> void:
	var env := _env()
	var sun := _sun()
	var snapshot := ChallengeVisibility.apply(env, sun, V.DAY, 0.0)
	assert_dict(snapshot[&"env"]).is_empty()
	assert_dict(snapshot[&"sun"]).is_empty()
	assert_float(env.ambient_light_energy).is_equal(_env().ambient_light_energy)


## A level without a WorldEnvironment or a sun still runs the challenge.
func test_a_missing_environment_or_sun_is_skipped() -> void:
	var snapshot := ChallengeVisibility.apply(null, null, V.DARK, 0.0)
	ChallengeVisibility.restore(null, null, snapshot)
	assert_dict(snapshot[&"env"]).is_empty()
