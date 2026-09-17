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


## Rule 9's .web perf overrides: msaa off, positional shadows hard and the sun at the cheapest
## soft filter on web (hard = one depth tap, whose edges shimmer as the texel grid slides under a
## moving camera; anything softer costs more than the budget on gl_compatibility). Text-only for the same reason as the physics pins above —
## these are non-default overrides, so get_setting() would work, but pinning the text catches the
## editor silently dropping the line as well as reverting the value.
func test_web_msaa_is_disabled() -> void:
	assert_str(_project_text()).contains("anti_aliasing/quality/msaa_3d.web=0")


func test_web_soft_shadows_are_disabled() -> void:
	var text := _project_text()
	assert_str(text).contains("lights_and_shadows/positional_shadow/soft_shadow_filter_quality.web=0")
	assert_str(text).contains("lights_and_shadows/directional_shadow/soft_shadow_filter_quality.web=1")


## scaling_3d/scale.web below 1 adds an upscale pass on gl_compatibility and measures worse
## (root CLAUDE.md rule 9) — this must never reappear.
func test_web_scale_override_is_absent() -> void:
	assert_bool(_project_text().contains("scaling_3d/scale.web")).is_false()
