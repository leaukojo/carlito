extends GdUnitTestSuite
## Tractor ISOBUS math: the 540/1000 PTO gearing, the ISO wheel-based/ground-based speed pair
## and its slip, and the hour meter. Pure statics, exercised without a physics body — the same
## discipline as Drivetrain and the other per-vehicle suites.
##
## The differential lock and MFWD are DRIVELINE behaviour, not tractor math: the lock's shared-
## omega step is tested as Drivetrain.locked_axle_omega in test_drivetrain.gd, and both are
## gated by spec flags asserted below.

const TractorT := preload("res://src/vehicles/tractor/tractor_telemetry.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
## Plough is deeper draft machine; working depth is on implement, not draft model.
const PloughScript := preload("res://src/vehicles/tractor/implements/plough.gd")


## Spec read via scene (not path), follows catalog->scene->spec chain (orphan-spec lesson).
func _tractor_spec() -> VehicleSpec:
	var variant := CatalogScript.first_in_family("tractor")
	var scene: PackedScene = load(CatalogScript.scene_of(variant))
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == "spec":
			return state.get_node_property_value(0, i) as VehicleSpec
	return null


## Draft max via catalog->scene chain (scene override or script default).
func _tractor_draft_max() -> float:
	var variant := CatalogScript.first_in_family("tractor")
	var scene: PackedScene = load(CatalogScript.scene_of(variant))
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == "draft_max_force":
			return float(state.get_node_property_value(0, i))
	var tractor: TractorVehicle = auto_free(TractorVehicle.new())
	return tractor.draft_max_force


# --- PTO mode (540 / 1000) ----------------------------------------------------

func test_pto_mode_names_the_shaft_speed_not_a_ratio() -> void:
	assert_float(TractorT.pto_speed_for_mode(TractorT.PTO_MODE_540)).is_equal(540.0)
	assert_float(TractorT.pto_speed_for_mode(TractorT.PTO_MODE_1000)).is_equal(1000.0)
	# An unknown byte off the bus falls back to the slower, safer mode.
	assert_float(TractorT.pto_speed_for_mode(7)).is_equal(540.0)
	assert_float(TractorT.pto_speed_for_mode(-1)).is_equal(540.0)


func test_pto_shaft_lands_on_its_named_speed_at_rated_rpm() -> void:
	assert_int(TractorT.pto_shaft_rpm(TractorT.PTO_RATED_RPM, TractorT.PTO_MODE_540)).is_equal(540)
	assert_int(TractorT.pto_shaft_rpm(TractorT.PTO_RATED_RPM, TractorT.PTO_MODE_1000)).is_equal(1000)
	# Below rated it scales with the engine; the shaft is geared to it, not held at a speed.
	assert_int(TractorT.pto_shaft_rpm(TractorT.PTO_RATED_RPM * 0.5, TractorT.PTO_MODE_1000)).is_equal(500)
	assert_int(TractorT.pto_shaft_rpm(0.0, TractorT.PTO_MODE_1000)).is_equal(0)


func test_pto_stays_in_contract_range_at_the_shipped_redline_without_clamping() -> void:
	# The clamp in pto_shaft_rpm is a backstop, not the mechanism: if the shipped gearing ever
	# needed it, the tractor would silently flat-line at redline. Assert the UNCLAMPED value.
	var spec := _tractor_spec()
	var raw := spec.redline_rpm * TractorT.pto_ratio_for_mode(TractorT.PTO_MODE_1000)
	assert_float(raw).is_less_equal(float(TractorT.PTO_RPM_MAX))
	assert_int(TractorT.pto_shaft_rpm(spec.redline_rpm, TractorT.PTO_MODE_1000)) \
			.is_equal(int(raw))
	# And the 540 mode sits comfortably below it.
	assert_int(TractorT.pto_shaft_rpm(spec.redline_rpm, TractorT.PTO_MODE_540)) \
			.is_less(TractorT.pto_shaft_rpm(spec.redline_rpm, TractorT.PTO_MODE_1000))


# --- ISO wheel-based speed ----------------------------------------------------

func test_wheel_kmh_is_spin_through_the_physics_radius() -> void:
	# 10 rad/s on a 0.5 m wheel = 5 m/s = 18 km/h.
	assert_float(TractorT.wheel_kmh(10.0, 0.5)).is_equal_approx(18.0, 1e-4)
	# Unsigned: reversing still reports a speed (direction lives on 'gear' / 'speed').
	assert_float(TractorT.wheel_kmh(-10.0, 0.5)).is_equal_approx(18.0, 1e-4)
	assert_float(TractorT.wheel_kmh(0.0, 0.6)).is_equal(0.0)


# --- ISO wheel slip -----------------------------------------------------------

func test_slip_is_the_gap_between_wheel_and_ground_speed() -> void:
	# Rolling true: no gap, no slip.
	assert_float(TractorT.slip_pct(20.0, 20.0)).is_equal(0.0)
	# Ground moving at half the driveline speed = 50 % slip.
	assert_float(TractorT.slip_pct(20.0, 10.0)).is_equal_approx(50.0, 1e-4)
	# Wheels turning with the tractor going nowhere: fully dug in.
	assert_float(TractorT.slip_pct(20.0, 0.0)).is_equal(100.0)


func test_slip_is_unsigned_and_quiet_at_standstill() -> void:
	# Braking slip (ground outrunning the wheels) reads 0 — J1939 SPN 1858 is unsigned.
	assert_float(TractorT.slip_pct(5.0, 20.0)).is_equal(0.0)
	# Below the floor the ratio is meaningless noise, so it reports nothing.
	assert_float(TractorT.slip_pct(0.0, 0.0)).is_equal(0.0)
	assert_float(TractorT.slip_pct(TractorT.SLIP_FLOOR_KMH, 0.0)).is_equal(0.0)
	assert_float(TractorT.slip_pct(TractorT.SLIP_FLOOR_KMH + 0.5, 0.0)).is_equal(100.0)


# --- draft force (the pure model) ---------------------------------------------
## Model sizes draft force: depth from linkage lift, soil/speed factors, RESISTANCE,
## 60 Hz damper margin, one-tick backstop, published percentage.

func test_draft_depth_comes_out_of_the_linkage_lift() -> void:
	var full := PloughScript.SHARE_DEPTH_M
	# Fully lowered: the tools are at full working depth.
	assert_float(TractorT.draft_depth01(0.0, full)).is_equal(1.0)
	# Lifted by exactly the working depth: the tools are at the ground line, out of the soil.
	assert_float(TractorT.draft_depth01(full, full)).is_equal(0.0)
	assert_float(TractorT.draft_depth01(full * 0.5, full)).is_equal_approx(0.5, 1e-6)
	# Airborne (the hitch raised far past the soil) stays 0, never negative.
	assert_float(TractorT.draft_depth01(0.57, full)).is_equal(0.0)


func test_draft_depth_is_bounded_and_survives_a_degenerate_depth() -> void:
	# A lift below the working datum cannot happen on the shipped linkage, but it must not report
	# more than full depth if the geometry is ever changed.
	assert_float(TractorT.draft_depth01(-1.0, PloughScript.SHARE_DEPTH_M)).is_equal(1.0)
	# An implement with no depth has no draft — never a division by zero.
	assert_float(TractorT.draft_depth01(0.0, 0.0)).is_equal(0.0)


func test_draft_opposes_travel_in_both_directions() -> void:
	# Signed along FORWARD, so it is negative while driving forward: a resistance, never a push.
	var fwd := TractorT.draft_newtons(TractorT.DRAFT_SPEED_REF, 1.0, 1.0, 12000.0, 4000.0, 1.0 / 60.0)
	assert_float(fwd).is_equal_approx(-12000.0, 1e-3)
	var rev := TractorT.draft_newtons(-TractorT.DRAFT_SPEED_REF, 1.0, 1.0, 12000.0, 4000.0, 1.0 / 60.0)
	assert_float(rev).is_equal_approx(12000.0, 1e-3)


func test_draft_scales_with_depth_and_soil_and_is_zero_without_either() -> void:
	var v := TractorT.DRAFT_SPEED_REF
	# Half depth, full soil.
	assert_float(TractorT.draft_newtons(v, 0.5, 1.0, 12000.0, 4000.0, 1.0 / 60.0)) \
			.is_equal_approx(-6000.0, 1e-3)
	# Full depth over half-painted soil (a splat border) — the same halving.
	assert_float(TractorT.draft_newtons(v, 1.0, 0.5, 12000.0, 4000.0, 1.0 / 60.0)) \
			.is_equal_approx(-6000.0, 1e-3)
	# Out of the soil, or not over soil at all: a clean zero, not a small polite number.
	assert_float(TractorT.draft_newtons(v, 0.0, 1.0, 12000.0, 4000.0, 1.0 / 60.0)).is_equal(0.0)
	assert_float(TractorT.draft_newtons(v, 1.0, 0.0, 12000.0, 4000.0, 1.0 / 60.0)).is_equal(0.0)
	# And a machine with no rated draft (or garbage off a bad edit) produces none.
	assert_float(TractorT.draft_newtons(v, 1.0, 1.0, 0.0, 4000.0, 1.0 / 60.0)).is_equal(0.0)
	assert_float(TractorT.draft_newtons(v, 1.0, 1.0, -500.0, 4000.0, 1.0 / 60.0)).is_equal(0.0)


func test_draft_builds_with_speed_and_saturates() -> void:
	var dt := 1.0 / 60.0
	# Standstill: soil resists motion, it does not shove a parked tractor out of the furrow.
	assert_float(TractorT.draft_newtons(0.0, 1.0, 1.0, 12000.0, 4000.0, dt)).is_equal(0.0)
	# Half the reference ploughing speed = half the rated draft.
	assert_float(TractorT.draft_newtons(TractorT.DRAFT_SPEED_REF * 0.5, 1.0, 1.0, 12000.0, 4000.0, dt)) \
			.is_equal_approx(-6000.0, 1e-3)
	# Past the reference it saturates — draft must not grow without limit with road speed.
	assert_float(TractorT.draft_newtons(TractorT.DRAFT_SPEED_REF * 5.0, 1.0, 1.0, 12000.0, 4000.0, dt)) \
			.is_equal_approx(-12000.0, 1e-3)


func test_draft_can_never_reverse_travel_inside_one_tick() -> void:
	# The 60 Hz guardrail, swept from a crawl up to working speed with an absurd rated draft: the
	# impulse may slow the tractor to a dead stop but never past it, at any speed. (Landing exactly
	# on zero is the cap doing its job, so the bound carries a float-precision allowance.)
	var dt := 1.0 / 60.0
	var body_mass := 4000.0
	for i in 40:
		var v := 0.001 + float(i) * 0.05
		var f := TractorT.draft_newtons(v, 1.0, 1.0, 500000.0, body_mass, dt)
		assert_float(f).is_less_equal(0.0)
		var dv := f / body_mass * dt   # the tick's velocity change from this force alone
		assert_float(absf(dv)) \
			.override_failure_message("draft reversed travel at v = %f m/s" % v) \
			.is_less_equal(v * (1.0 + 1e-9))


func test_the_speed_ramp_not_the_backstop_is_what_fades_draft_out() -> void:
	# With the SHIPPED rating and mass the cap must stay a backstop: at a crawl the ramp has
	# already taken the force to a small fraction of the impulse the cap would allow. If this
	# inverts, the tractor is being arrested by a stability device instead of resisted by soil.
	var dt := 1.0 / 60.0
	var body_mass := _tractor_spec().mass
	var rated := _tractor_draft_max()
	var v := 0.05
	var f := absf(TractorT.draft_newtons(v, 1.0, 1.0, rated, body_mass, dt))
	assert_float(f).is_equal_approx(rated * v / TractorT.DRAFT_SPEED_REF, 1e-3)
	assert_float(f).is_less(body_mass * v / dt * 0.1)


func test_the_shipped_rating_keeps_the_60hz_damper_margin() -> void:
	# The real 60 Hz guarantee, pinned against the SHIPPED numbers rather than a literal. Below
	# DRAFT_SPEED_REF the model is exactly a linear damper, F = -k*v, and an explicit damper is
	# stable while k*dt/m < 2. This is what makes the one-tick cap unreachable — and the cap
	# bounds only the LINEAR impulse, so a rating that reached it would still be free to spin the
	# chassis about the 1.3 m hitch offset. Fail here rather than there: raising draft_max_force
	# past this margin means the force needs a real angular bound too, not just a bigger number.
	var dt := 1.0 / 60.0
	var body_mass := _tractor_spec().mass
	var k := _tractor_draft_max() / TractorT.DRAFT_SPEED_REF
	assert_float(k * dt / body_mass) \
		.override_failure_message("draft is no longer a well-damped linear force at 60 Hz") \
		.is_less(0.5)


func test_draft_percentage_is_the_applied_force_over_the_rating() -> void:
	assert_float(TractorT.draft_pct(-12000.0, 12000.0)).is_equal(100.0)
	assert_float(TractorT.draft_pct(-3000.0, 12000.0)).is_equal(25.0)
	assert_float(TractorT.draft_pct(0.0, 12000.0)).is_equal(0.0)
	# Unsigned: reversing through the soil reports the same size of pull.
	assert_float(TractorT.draft_pct(3000.0, 12000.0)).is_equal(25.0)
	# Clamped to the contract's 0-100 range, and safe with no rating at all.
	assert_float(TractorT.draft_pct(-99000.0, 12000.0)).is_equal(100.0)
	assert_float(TractorT.draft_pct(-1000.0, 0.0)).is_equal(0.0)


func test_the_shipped_tractor_can_actually_pull_its_rated_draft() -> void:
	# A plough the tractor cannot move is not a playground: the rating has to sit well under what
	# the tires can put down (mu x weight). Half of that is a generous bound — only the rear axle
	# carries drive in 2WD, and some of the traction budget belongs to steering.
	var spec := _tractor_spec()
	var rated := _tractor_draft_max()
	assert_float(rated).is_greater(0.0)
	assert_float(rated).is_less(0.5 * spec.mass * 9.8 * spec.ground_drive.mu_long)


# The hour meter moved to test_telemetry with VehicleTelemetry.hours_step: engine_hours is a
# shared tractor/truck signal now (J1939 SPN 247), so the model is not tractor math any more.

# --- struct defaults ----------------------------------------------------------

func test_fresh_tractor_telemetry_rests_open_2wd_and_at_zero_hours() -> void:
	var t := TractorT.new()
	assert_bool(t.diff_lock_state).is_false()
	assert_bool(t.fwd_drive_state).is_false()
	assert_float(t.wheel_speed).is_equal(0.0)
	assert_float(t.ground_speed).is_equal(0.0)
	assert_int(t.wheel_slip).is_equal(0)
	assert_float(t.engine_hours).is_equal(0.0)


# --- driveline flags are tractor-scoped ---------------------------------------

func test_only_the_tractor_declares_a_lockable_diff_and_an_engageable_front_axle() -> void:
	var tractor_spec := _tractor_spec()
	assert_object(tractor_spec) \
		.override_failure_message("the drivable tractor scene declares no spec").is_not_null()
	assert_bool(tractor_spec.ground_drive.rear_diff_lockable).is_true()
	assert_bool(tractor_spec.ground_drive.front_axle_engageable).is_true()
	# Spawn state is 2WD: engaging MFWD has to be a thing you do, or it proves nothing.
	assert_bool(tractor_spec.ground_drive.driven_front).is_false()
	# Every other shipped spec leaves both off, so no car's driveline can move under these bits.
	var checked := 0
	for path in _spec_paths("res://src/vehicles"):
		if path == tractor_spec.resource_path:
			continue
		var spec: VehicleSpec = load(path)
		if spec.ground_drive == null:
			continue  # no running gear at all — the stronger form of "declares neither flag"
		checked += 1
		assert_bool(spec.ground_drive.rear_diff_lockable) \
			.override_failure_message("%s must not declare a lockable diff" % path).is_false()
		assert_bool(spec.ground_drive.front_axle_engageable) \
			.override_failure_message("%s must not declare an engageable front axle" % path).is_false()
	assert_int(checked).is_greater(0)


# --- the touch overlay's PTO / LIFT buttons -----------------------------------

func test_the_attachment_controls_are_the_implements_own_declaration() -> void:
	# The touch PTO/TIP buttons are offered by CAPABILITY, and the capability read is the SAME
	# ImplementBase.connections() the hitch gates the real drive on — not a second list. A PTO
	# button on a plough would be the scene claiming a connection again, one layer up.
	var variant := CatalogScript.first_in_family("tractor")
	var tractor := (load(CatalogScript.scene_of(variant)) as PackedScene).instantiate()
	var hitch: ThreePointHitch = tractor.get_node_or_null(^"ThreePointHitch")
	assert_object(hitch).override_failure_message("the tractor scene has no hitch").is_not_null()
	# _hitch is resolved in _ready, which needs a tree — set it directly and hang the implement on
	# the hitch by hand, for the same reason the rest of this suite runs without a physics body.
	tractor.set("_hitch", hitch)

	for path in ImplementCatalog.IMPLEMENTS:
		# DETACHED is a real entry in the cycle and it is the bare case below. TOWED entries are real
		# entries too, but they hang off the DRAWBAR rather than the linkage and are not
		# ImplementBases at all — tests/test_drawbar_trailer.gd covers what they offer.
		if not ImplementCatalog.is_attached(path) or ImplementCatalog.is_towed(path):
			continue
		var implement := (load(path) as PackedScene).instantiate() as ImplementBase
		hitch.implement = implement
		var controls: Dictionary = tractor.call("attachment_controls")
		assert_bool(controls.get("pto", false)) \
			.override_failure_message("%s: PTO button does not match its declaration" % path) \
			.is_equal(implement.uses(ImplementBase.Connection.PTO))
		# The LINKAGE is tractor anatomy, so the lift button is always real: it raises and lowers
		# with nothing on it and hitch_pos is a signal on a bare tractor.
		assert_bool(controls.get("lift", false)) \
			.override_failure_message("%s: the lift button must always be offered" % path).is_true()
		implement.free()
	hitch.implement = null

	# Detached: no drive to engage, but the linkage is still there to raise.
	var bare: Dictionary = tractor.call("attachment_controls")
	assert_bool(bare["pto"]) \
		.override_failure_message("a bare hitch has nothing on the far end of the stub shaft").is_false()
	assert_bool(bare["lift"]).is_true()
	tractor.free()


func test_the_shell_hook_is_duck_typed_and_the_tractor_answers_it() -> void:
	# boot.gd finds this by name, exactly like cycle_implement, so nothing in the shell learns what
	# an implement is — and the semi answers the same question about its trailer. A rename here
	# silently takes the buttons away.
	var tractor: TractorVehicle = auto_free(TractorVehicle.new())
	assert_bool(tractor.has_method("attachment_controls")) \
		.override_failure_message("the shell would find no attachment controls on the tractor").is_true()
	# ...and it answers safely before _ready has resolved the hitch, which is when a spawn asks.
	var early: Dictionary = tractor.attachment_controls()
	assert_bool(early["pto"]).is_false()
	assert_bool(early["lift"]).is_true()


## Every *_spec.tres under `root`, recursively.
func _spec_paths(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with("_spec.tres"):
			out.append(root.path_join(f))
	for sub in dir.get_directories():
		out.append_array(_spec_paths(root.path_join(sub)))
	return out
