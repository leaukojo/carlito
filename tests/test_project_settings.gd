extends GdUnitTestSuite
## Project settings that are INVARIANTS, not preferences. Standing rule 9 locks the physics tick
## at 60 Hz with interpolation because the suspension tuning is rate-dependent: every RayWheel
## clamp (damper <= one-tick reversal, suspension force cap, spin integration) is sized for a
## 1/60 s step, so changing the rate silently re-tunes every vehicle.
##
## The text assertions are the real guard: Godot omits any setting equal to its default when the
## editor rewrites `project.godot`, and `get_setting()` / `has_setting()` cannot tell a pinned
## value from a missing one when the invariant IS the engine default (60 Hz is).

const PROJECT_FILE := "res://project.godot"


func _project_text() -> String:
	var f := FileAccess.open(PROJECT_FILE, FileAccess.READ)
	assert_object(f).is_not_null()  # tests run from source; no project.godot means no guard
	return f.get_as_text()


func test_physics_tick_is_60hz() -> void:
	assert_int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", -1)).is_equal(60)
	assert_str(_project_text()).contains("common/physics_ticks_per_second=60")


func test_physics_interpolation_is_on() -> void:
	assert_bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)).is_true()
	assert_str(_project_text()).contains("common/physics_interpolation=true")
