extends GdUnitTestSuite
## Tractor ISOBUS math: the 540/1000 PTO gearing, the ISO wheel-based/ground-based speed pair
## and its slip, and the hour meter. Pure statics, exercised without a physics body — the same
## discipline as Drivetrain and the other per-vehicle suites.
##
## The differential lock and MFWD are DRIVELINE behaviour, not tractor math: both are
## `Differential` couplings (test_differential.gd; the WheelDrive passes in test_wheel_spin.gd),
## gated by spec flags asserted below.

const TractorT := preload("res://src/vehicles/tractor/tractor_telemetry.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
## Plough is deeper draft machine; working depth is on implement, not draft model.
const PloughScript := preload("res://src/vehicles/tractor/implements/plough.gd")
const WheelDriveScript := preload("res://src/vehicles/base/wheel_drive.gd")


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
	# The shipped tractor's drive axle is its drawn 0.66 m rear.
	assert_float(_tractor_spec().ground_drive.axle_radius(true)).is_equal_approx(0.66, 1e-4)


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


# --- ISOBUS guidance curvature -> wheel angle (bypasses the speed-tapered rack) -----------

func test_guidance_curvature_zero_is_dead_straight() -> void:
	assert_float(WheelDriveScript.steer_angle_from_curvature(0.0, 2.5, 32.0)).is_equal(0.0)


func test_guidance_curvature_matches_the_ackermann_reciprocal_at_small_angles() -> void:
	# 1000/curvature = radius; angle ~= wheelbase / radius for a small angle, so a modest
	# curvature on a real wheelbase should land close to that small-angle approximation.
	var wheelbase := 2.5
	var curvature := 20.0  # 1/km -> 50 m radius
	var angle := WheelDriveScript.steer_angle_from_curvature(curvature, wheelbase, 32.0)
	assert_float(angle).is_equal_approx(atan(wheelbase / 50.0), 1e-9)
	assert_float(rad_to_deg(angle)).is_between(2.5, 3.1)


func test_guidance_curvature_sign_matches_steer_convention() -> void:
	# + curvature = right, same as VehicleInput.steer; the caller (WheelDrive.tick) negates
	# this to build _applied_steer, exactly as the plain `steer` path does.
	assert_float(WheelDriveScript.steer_angle_from_curvature(20.0, 2.5, 32.0)).is_greater(0.0)
	assert_float(WheelDriveScript.steer_angle_from_curvature(-20.0, 2.5, 32.0)).is_less(0.0)


func test_guidance_curvature_clamps_to_the_mechanical_lock_not_the_taper() -> void:
	# A long wheelbase against a shallow rack asks for more angle than the wheel can turn to;
	# the clamp is the bare mechanical max_steer_deg, with no taper factor at all.
	var wheelbase := 10.0
	var max_deg := 5.0
	var angle := WheelDriveScript.steer_angle_from_curvature(127.0, wheelbase, max_deg)
	assert_float(rad_to_deg(angle)).is_equal_approx(max_deg, 1e-6)
	# A curvature past the wire's own ceiling still just sits on the same lock.
	var over := WheelDriveScript.steer_angle_from_curvature(500.0, wheelbase, max_deg)
	assert_float(angle).is_equal_approx(over, 1e-9)


## The unit BaseVehicle slews `_steer` toward under guidance (same [-1, 1] range as `input.steer`,
## + = right), so the wheels move at `spec.steer_speed` instead of jumping to the commanded angle.
func _guidance_wheelbase(gd: GroundDriveSpec) -> float:
	var front_z := INF
	var rear_z := -INF
	for pos in gd.wheel_positions:
		if pos.z < 0.0:
			front_z = minf(front_z, pos.z)
		else:
			rear_z = maxf(rear_z, pos.z)
	return rear_z - front_z


func test_the_foot_brake_engages_the_front_axle_and_brakes_only_the_rears() -> void:
	# Rear-axle brakes, as on a real tractor; the pedal engages MFWD so the rigid shaft brakes the
	# fronts too. Released, the axle drops back to the driver's own MFWD choice.
	var spec := _tractor_spec()
	var gd := spec.ground_drive
	assert_bool(gd.brake_engages_front_axle).is_true()
	assert_float(gd.brake_bias_front).is_equal(0.0)
	assert_float(gd.axle_brake_torque(false)).is_equal(0.0)
	var drive := WheelDriveScript.new(auto_free(Node3D.new()), spec)
	var input := VehicleInput.new()
	drive.drive_omega(gd, input)
	assert_int(drive._driven_count).is_equal(2)
	input.brake = 0.2
	drive.drive_omega(gd, input)
	assert_int(drive._driven_count).is_equal(4)
	input.brake = 0.0
	drive.drive_omega(gd, input)
	assert_int(drive._driven_count).is_equal(2)


func test_guidance_steer_unit_is_nan_with_no_guidance_command() -> void:
	var spec := _tractor_spec()
	var drive := WheelDriveScript.new(auto_free(Node3D.new()), spec)
	var input := VehicleInput.new()
	assert_bool(is_nan(drive.guidance_steer_unit(input, spec.ground_drive))).is_true()


func test_guidance_steer_unit_maps_back_to_the_same_angle_the_wire_would_apply() -> void:
	var spec := _tractor_spec()
	var gd := spec.ground_drive
	var drive := WheelDriveScript.new(auto_free(Node3D.new()), spec)
	var wheelbase := _guidance_wheelbase(gd)
	var input := VehicleInput.new()
	input.guidance_curvature = 20.0
	var unit := drive.guidance_steer_unit(input, gd)
	var expected_angle := WheelDriveScript.steer_angle_from_curvature(20.0, wheelbase, gd.max_steer_deg)
	assert_float(unit * deg_to_rad(gd.max_steer_deg)).is_equal_approx(expected_angle, 1e-9)
	# Same sign convention as `input.steer` (+ = right); WheelDrive.tick negates it exactly as it
	# negates the plain steer path.
	assert_float(unit).is_greater(0.0)
	input.guidance_curvature = -20.0
	assert_float(drive.guidance_steer_unit(input, gd)).is_less(0.0)


func test_guidance_steer_unit_clamps_to_the_mechanical_lock_as_plus_minus_one() -> void:
	var spec := _tractor_spec()
	var gd := spec.ground_drive
	var drive := WheelDriveScript.new(auto_free(Node3D.new()), spec)
	var input := VehicleInput.new()
	input.guidance_curvature = 500.0  # past the wire's own +-127 1/km ceiling
	assert_float(drive.guidance_steer_unit(input, gd)).is_equal_approx(1.0, 1e-6)
	input.guidance_curvature = -500.0
	assert_float(drive.guidance_steer_unit(input, gd)).is_equal_approx(-1.0, 1e-6)


func test_guidance_target_needs_several_ticks_at_steer_speed_not_a_jump() -> void:
	# BaseVehicle runs guidance through the SAME move_toward(_steer, target, spec.steer_speed)
	# slew as hand-steering; a curvature saturating the mechanical lock must not reach the unit
	# target (1.0) in a single 60 Hz tick.
	var spec := _tractor_spec()
	var gd := spec.ground_drive
	var drive := WheelDriveScript.new(auto_free(Node3D.new()), spec)
	var input := VehicleInput.new()
	input.guidance_curvature = 500.0
	var target := drive.guidance_steer_unit(input, gd)
	var dt := 1.0 / 60.0
	var steer := move_toward(0.0, target, spec.steer_speed * dt)
	assert_float(steer).is_equal_approx(spec.steer_speed * dt, 1e-6)
	assert_float(steer).is_less(target)
	# ...and reaches it after enough ticks at that same rate, never overshooting.
	var ticks := int(ceil(target / (spec.steer_speed * dt))) + 1
	for i in ticks:
		steer = move_toward(steer, target, spec.steer_speed * dt)
	assert_float(steer).is_equal_approx(target, 1e-6)


## The one exception to this suite's "no physics body" discipline: BaseVehicle's target
## selection (guidance vs. plain `input.steer`) is three lines inline in `_physics_process`, so
## exercising it for real means a real tractor scene. `InputRouter._current` is set directly,
## bypassing registration/arbitration, since only the target-selection and slew are under test.
func _guidance_test_tractor() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var tractor: Node3D = auto_free(
			(load(CatalogScript.scene_of("tractor-kenney")) as PackedScene).instantiate() as Node3D)
	tractor.set("display_only", true)  # skip InputRouter registration; _current is set by hand
	root.add_child(tractor)
	return tractor


func test_guidance_wheel_angle_matches_the_slewed_steer_with_no_taper() -> void:
	var tractor := _guidance_test_tractor()
	var spec: VehicleSpec = tractor.get("spec")
	var gd := spec.ground_drive
	var drive: WheelDrive = tractor.get("drive")
	var input := VehicleInput.new()
	input.guidance_curvature = 20.0
	InputRouter.set("_current", input)
	var dt := 1.0 / 60.0
	var target := drive.guidance_steer_unit(input, gd)
	var ticks := int(ceil(absf(target) / (spec.steer_speed * dt))) + 2
	for i in ticks:
		tractor._physics_process(dt)
	var telemetry: VehicleTelemetry = tractor.get("telemetry")
	assert_float(tractor.get("_steer")).is_equal_approx(target, 1e-5)
	assert_float(telemetry.steer).is_equal_approx(target, 1e-5)
	# The bicycle angle tracks the command; each steered wheel is its Ackermann split.
	var mean := -target * deg_to_rad(gd.max_steer_deg)
	assert_float(drive.mean_steer_angle()).is_equal_approx(mean, 1e-4)
	var wheelbase: float = drive.get("_wheelbase")
	var wheels: Array = tractor.get("wheels")
	var checked := 0
	for w in wheels:
		if w.steered:
			checked += 1
			assert_float(w.steer_angle).is_equal_approx(
					WheelDrive.ackermann_angle(mean, w.anchor.x, wheelbase, gd.ackermann), 1e-4)
	assert_int(checked).is_greater(0)


func test_guidance_absent_still_slews_toward_plain_input_steer() -> void:
	var tractor := _guidance_test_tractor()
	var spec: VehicleSpec = tractor.get("spec")
	var input := VehicleInput.new()
	input.steer = 0.4
	InputRouter.set("_current", input)
	var dt := 1.0 / 60.0
	var ticks := int(ceil(0.4 / (spec.steer_speed * dt))) + 2
	for i in ticks:
		tractor._physics_process(dt)
	assert_float(tractor.get("_steer")).is_equal_approx(0.4, 1e-5)


func test_wheelbase_is_measured_off_the_shipped_tractor_wheels() -> void:
	# Sanity check against the real spec, not a hand-typed number: front z is negative, rear
	# positive (base_vehicle.gd convention), so the wheelbase is their difference.
	var spec := _tractor_spec()
	var gd := spec.ground_drive
	var front_z := INF
	var rear_z := -INF
	for pos in gd.wheel_positions:
		if pos.z < 0.0:
			front_z = minf(front_z, pos.z)
		else:
			rear_z = maxf(rear_z, pos.z)
	var wheelbase: float = rear_z - front_z
	assert_float(wheelbase).is_greater(1.5)  # a real tractor, not a go-kart
	# At a modest working-speed curvature the commanded angle is now well under the mechanical
	# lock — the taper is what used to eat it, and this path no longer applies one.
	var angle := WheelDriveScript.steer_angle_from_curvature(20.0, wheelbase, gd.max_steer_deg)
	assert_float(rad_to_deg(angle)).is_less(gd.max_steer_deg)


# --- draft force (the pure model) ---------------------------------------------
## Model sizes draft force: depth from linkage lift, soil, D497's speed factor and the crawl
## taper, RESISTANCE, the 60 Hz damper margin on the hitch's effective mass, one-tick backstop,
## published percentage.

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


## A speed-independent shape: g(S) = 1 everywhere, so these tests isolate one factor at a time.
const FLAT := Vector4(1.0, 0.0, 0.0, 0.0)
## The reference speed in m/s, where every rating is given.
const V_REF := TractorT.DRAFT_S_REF_KMH / 3.6
const HarrowScript := preload("res://src/vehicles/tractor/implements/harrow.gd")


func test_draft_opposes_travel_in_both_directions() -> void:
	# Signed along FORWARD, so it is negative while driving forward: a resistance, never a push.
	var fwd := TractorT.draft_newtons(V_REF, 1.0, 1.0, 12000.0, FLAT, 4000.0, 1.0 / 60.0)
	assert_float(fwd).is_equal_approx(-12000.0, 1e-3)
	var rev := TractorT.draft_newtons(-V_REF, 1.0, 1.0, 12000.0, FLAT, 4000.0, 1.0 / 60.0)
	assert_float(rev).is_equal_approx(12000.0, 1e-3)


func test_draft_scales_with_depth_and_soil_and_is_zero_without_either() -> void:
	var v := V_REF
	var dt := 1.0 / 60.0
	# Half depth, full soil.
	assert_float(TractorT.draft_newtons(v, 0.5, 1.0, 12000.0, FLAT, 4000.0, dt)) \
			.is_equal_approx(-6000.0, 1e-3)
	# Full depth over half-painted soil (a splat border) — the same halving.
	assert_float(TractorT.draft_newtons(v, 1.0, 0.5, 12000.0, FLAT, 4000.0, dt)) \
			.is_equal_approx(-6000.0, 1e-3)
	# Out of the soil, or not over soil at all: a clean zero, not a small polite number.
	assert_float(TractorT.draft_newtons(v, 0.0, 1.0, 12000.0, FLAT, 4000.0, dt)).is_equal(0.0)
	assert_float(TractorT.draft_newtons(v, 1.0, 0.0, 12000.0, FLAT, 4000.0, dt)).is_equal(0.0)
	# And a machine with no rating (or garbage off a bad edit) produces none.
	assert_float(TractorT.draft_newtons(v, 1.0, 1.0, 0.0, FLAT, 4000.0, dt)).is_equal(0.0)
	assert_float(TractorT.draft_newtons(v, 1.0, 1.0, -500.0, FLAT, 4000.0, dt)).is_equal(0.0)


## The soil is `Surface.FIELD` wherever a level paints it, never a channel number: a level whose
## channel 4 is Snow has no soil there, and Field painted in channel 7 is soil.
func test_soil_is_the_field_surface_not_a_channel() -> void:
	var t: HeightmapTerrain = auto_free(HeightmapTerrain.new())
	t.terrain_size = Vector2(4, 4)
	add_child(t)
	var full := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	full.fill(Color(1, 0, 0, 0))
	var bare := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	bare.fill(Color(0, 0, 0, 0))
	t.splatmap = ImageTexture.create_from_image(bare)
	t.splatmap2 = ImageTexture.create_from_image(full)   # channel 4 at full weight
	var terrains: Array[Node] = [t]
	var table := PackedInt32Array(HeightmapTerrain.DEFAULT_CHANNEL_SURFACE)
	table[4] = Surface.SNOW
	t.channel_surface = table
	var soil := TractorVehicle.soil_under(Vector3.ZERO, terrains)
	assert_float(soil).is_equal(0.0)
	assert_float(TractorT.draft_newtons(V_REF, 1.0, soil, 12000.0, FLAT, 4000.0, 1.0 / 60.0)) \
			.is_equal(0.0)
	var alpha := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	alpha.fill(Color(0, 0, 0, 1))
	t.splatmap2 = ImageTexture.create_from_image(alpha)   # channel 7 at full weight
	table[7] = Surface.FIELD
	t.channel_surface = table
	assert_float(TractorVehicle.soil_under(Vector3.ZERO, terrains)).is_equal(1.0)


func test_draft_follows_d497_and_holds_at_its_range_top() -> void:
	# The plough's row is A + C S² (B 0): the ratio to 7 km/h at 3 and 10 km/h, and held past 10.
	var shape := PloughScript.DRAFT_SHAPE
	var at_ref := shape.x + shape.z * 49.0
	assert_float(TractorT.draft_speed01(7.0, shape)).is_equal_approx(1.0, 1e-6)
	assert_float(TractorT.draft_speed01(3.0, shape)) \
			.is_equal_approx((shape.x + shape.z * 9.0) / at_ref, 1e-6)
	assert_float(TractorT.draft_speed01(10.0, shape)) \
			.is_equal_approx((shape.x + shape.z * 100.0) / at_ref, 1e-6)
	assert_float(TractorT.draft_speed01(25.0, shape)).is_equal(TractorT.draft_speed01(10.0, shape))
	# Never extrapolated, and the force carries it: at road speed it is the range top's.
	var dt := 1.0 / 60.0
	assert_float(TractorT.draft_newtons(25.0 / 3.6, 1.0, 1.0, 8000.0, shape, 6000.0, dt)) \
			.is_equal_approx(-8000.0 * TractorT.draft_speed01(10.0, shape), 1e-2)
	# The harrow's row is linear (C 0), held past its 9 km/h.
	var h := HarrowScript.DRAFT_SHAPE
	assert_float(TractorT.draft_speed01(3.0, h)) \
			.is_equal_approx((h.x + h.y * 3.0) / (h.x + h.y * 7.0), 1e-6)
	assert_float(TractorT.draft_speed01(12.0, h)).is_equal(TractorT.draft_speed01(9.0, h))
	# A shape with nothing at the reference is no draft, never a division by zero.
	assert_float(TractorT.draft_speed01(7.0, Vector4.ZERO)).is_equal(0.0)


func test_draft_tapers_to_zero_below_the_crawl_speed() -> void:
	var dt := 1.0 / 60.0
	var shape := PloughScript.DRAFT_SHAPE
	# Standstill: soil resists motion, it does not shove a parked tractor out of the furrow.
	assert_float(TractorT.draft_newtons(0.0, 1.0, 1.0, 8000.0, shape, 6000.0, dt)).is_equal(0.0)
	# Half the crawl speed: half of D497's own value there.
	var v := TractorT.DRAFT_V_CRAWL * 0.5
	assert_float(TractorT.draft_newtons(v, 1.0, 1.0, 8000.0, shape, 6000.0, dt)) \
			.is_equal_approx(-8000.0 * TractorT.draft_speed01(v * 3.6, shape) * 0.5, 1e-2)
	# At the crawl speed it is fully on: D497's own value there, a hair over its zero-speed share of
	# the rating (A over A + C S_ref²).
	var crawl_kmh := TractorT.DRAFT_V_CRAWL * 3.6
	assert_float(TractorT.draft_newtons(TractorT.DRAFT_V_CRAWL, 1.0, 1.0, 8000.0, shape, 6000.0, dt)) \
			.is_equal_approx(-8000.0 * TractorT.draft_speed01(crawl_kmh, shape), 8000.0 * 1e-5)
	assert_float(TractorT.draft_speed01(crawl_kmh, shape)) \
			.is_equal_approx(TractorT.draft_speed01(0.0, shape), 0.01)


func test_draft_can_never_reverse_the_hitch_inside_one_tick() -> void:
	# The 60 Hz backstop, swept from a crawl up to working speed with an absurd rating: the impulse
	# on the effective mass the hitch point meets may stop the hitch dead but never past it, at
	# any speed. (Landing exactly on zero is the cap doing its job, so the bound carries a
	# float-precision allowance.)
	var dt := 1.0 / 60.0
	var eff_mass := 4000.0
	for i in 40:
		var v := 0.001 + float(i) * 0.05
		var f := TractorT.draft_newtons(v, 1.0, 1.0, 500000.0, FLAT, eff_mass, dt)
		assert_float(f).is_less_equal(0.0)
		var dv := f / eff_mass * dt   # the hitch's velocity change from this force alone
		assert_float(absf(dv)) \
			.override_failure_message("draft reversed the hitch at v = %f m/s" % v) \
			.is_less_equal(v * (1.0 + 1e-9))


func test_the_dial_reads_100_for_the_plough_at_its_rating() -> void:
	# 'draft_force' is a percentage of draft_max_force, and that is the plough's own rating.
	var plough: ImplementBase = auto_free((load(PLOUGH_PATH) as PackedScene).instantiate())
	assert_float(_tractor_draft_max()).is_equal(plough.draft_rating())


func test_the_shipped_draft_keeps_the_60hz_damper_margin_on_the_hitch() -> void:
	# The real 60 Hz guarantee, pinned against the SHIPPED numbers. Below DRAFT_V_CRAWL the draft
	# is a linear damper on the hitch point's speed, k = F_crawl / DRAFT_V_CRAWL, and an explicit
	# damper is stable while k*dt/m_eff < 2. m_eff is what the hitch meets, the body plus the
	# pitch its arm below and behind the COM turns, read off a spawned tractor: bare, and with each
	# draft machine on at the bottom stop. Under 1 it also keeps the one-tick cap (m_eff·v/dt) a
	# backstop the soil never reaches.
	var dt := 1.0 / 60.0
	var f_crawl := 0.0
	var ids: Array[String] = [ImplementCatalog.DETACHED]
	for path in ImplementCatalog.IMPLEMENTS:
		if not ImplementCatalog.is_attached(path) or ImplementCatalog.is_towed(path):
			continue
		var node: ImplementBase = auto_free((load(path) as PackedScene).instantiate())
		if node.draft_relevant():
			f_crawl = maxf(f_crawl,
					node.draft_rating() * TractorT.draft_speed01(0.0, node.draft_shape()))
			ids.append(path)
	assert_float(f_crawl).is_greater(0.0)
	var t := await _spawn_tractor()
	# Posed by hand, so no tick may re-pose it; the space still steps the tensor to the new load.
	t.set_physics_process(false)
	var lowest := INF
	var labels := PackedStringArray()
	for id in ids:
		_carry(t, id, 0.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var m_eff := t.hitch_effective_mass(t._hitch.hitch_point())
		labels.append("%s %.0f kg" % [id.get_file().get_basename() if id != "" else "bare", m_eff])
		assert_float(m_eff).is_less(t.mass)
		lowest = minf(lowest, m_eff)
	var k := f_crawl / TractorT.DRAFT_V_CRAWL
	assert_float(k * dt / lowest) \
		.override_failure_message(("draft is no longer a well-damped force at 60 Hz: k*dt/m_eff"
				+ " %.2f (m_eff, the body plus the pitch the hitch's arm turns: %s); raise"
				+ " DRAFT_V_CRAWL") % [k * dt / lowest, ", ".join(labels)]) \
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
	# carries drive in 2WD, and some of the traction budget belongs to steering. Judged at each
	# draft machine's hardest pull, its rating where D497's curve is held (the top of its range).
	var spec := _tractor_spec()
	var budget := 0.5 * spec.mass * 9.8 * spec.ground_drive.mu_long
	var checked := 0
	for path in ImplementCatalog.IMPLEMENTS:
		if not ImplementCatalog.is_attached(path) or ImplementCatalog.is_towed(path):
			continue
		var node: ImplementBase = auto_free((load(path) as PackedScene).instantiate())
		if not node.draft_relevant():
			continue
		checked += 1
		var hardest := node.draft_rating() * maxf(TractorT.draft_speed01(0.0, node.draft_shape()),
				TractorT.draft_speed01(node.draft_shape().w, node.draft_shape()))
		assert_float(hardest) \
			.override_failure_message("%s pulls %.0f N, past the tyres' %.0f N" % [path, hardest, budget]) \
			.is_less(budget)
	assert_int(checked).is_greater(0)


## The standing load (N·m at the axle) on a grade of `grade_pct`, nose up, with `soil` (the painted
## surface's added rolling coefficient) and `towed_kg` behind: what `WheelDrive.hold_step` hands
## the gearbox.
static func _standing_load(spec: VehicleSpec, grade_pct: float, soil: float, towed_kg := 0.0) -> float:
	var tilt := Basis(Vector3.RIGHT, atan(grade_pct / 100.0))
	return ShiftPolicy.standing_load(Vector3(0.0, -9.8, 0.0), tilt * Vector3.UP,
			tilt * Vector3.FORWARD, spec.ground_drive.rolling_resistance + soil,
			(spec.mass + towed_kg) * spec.ground_drive.drive_radius())


func test_the_shipped_tractor_starts_in_d3_empty_on_the_flat_and_lower_laden_or_on_a_grade() -> void:
	# A powershift's start gear is a driver preset, higher empty and lower laden: here the load
	# standing on the grade picks it (`ShiftPolicy.start_gear`, up to the spec's D3).
	var spec := _tractor_spec()
	assert_int(spec.start_gear_max).is_equal(3)
	assert_int(ShiftPolicy.start_gear(spec, _standing_load(spec, 0.0, 0.0))).is_equal(3)
	# Mud's 0.2 is still D3 bobtail; laden with the 10 t tipper it is D1.
	assert_int(ShiftPolicy.start_gear(spec, _standing_load(spec, 0.0, 0.2))).is_equal(3)
	assert_int(ShiftPolicy.start_gear(spec, _standing_load(spec, 0.0, 0.2, 10000.0))).is_equal(1)
	# The tipper on 10 % asphalt takes D2; the 26 % mud climb takes D1, its measured best.
	assert_int(ShiftPolicy.start_gear(spec, _standing_load(spec, 10.0, 0.0, 10000.0))).is_equal(2)
	assert_int(ShiftPolicy.start_gear(spec, _standing_load(spec, 26.4, 0.2))).is_equal(1)


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


# --- implement mass through the linkage -------------------------------------------
## The carried share of an implement's weight goes into the chassis' live mass and COM
## (`TractorVehicle._apply_implement_mass`), read off the linkage as posed. Scene tests: the hitch
## pose and the mass write need the tractor in the tree.

const PLOUGH_PATH := "res://src/vehicles/tractor/implements/plough.tscn"
const SPREADER_PATH := "res://src/vehicles/tractor/implements/spreader.tscn"


func _spawn_tractor() -> TractorVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var variant := CatalogScript.first_in_family("tractor")
	var t := (load(CatalogScript.scene_of(variant)) as PackedScene).instantiate() as TractorVehicle
	t.display_only = true  # no InputRouter registration; nothing here is driven
	root.add_child(t)
	t.global_position = Vector3(0.0, 50.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return t


## Attach `id`, pose the linkage at `pos01` and write the load, all inside one call stack so no
## physics tick re-poses it in between.
func _carry(t: TractorVehicle, id: String, pos01: float) -> void:
	t.set_attachment(id)
	t._hitch.set_hitch(pos01)
	t._apply_implement_mass()


func test_a_raised_plough_moves_live_mass_and_com_by_its_declared_figures() -> void:
	var t := await _spawn_tractor()
	_carry(t, PLOUGH_PATH, 1.0)
	var plough := t._hitch.implement
	assert_float(t.mass).is_equal_approx(t.spec.mass + plough.mass_kg(), 1e-3)
	var expected := VehicleMath.carried_com(t.spec.center_of_mass, t._hitch.implement_com(),
			t.spec.mass, plough.mass_kg())
	assert_vector(t.center_of_mass).is_equal_approx(expected, Vector3.ONE * 1e-5)
	# Hung behind the rear axle and lifted: the COM moves rearward and up.
	assert_float(t.center_of_mass.z).is_greater(t.spec.center_of_mass.z)
	assert_float(t.center_of_mass.y).is_greater(t.spec.center_of_mass.y)


func test_at_the_bottom_stop_the_ground_carries_its_share() -> void:
	var t := await _spawn_tractor()
	_carry(t, PLOUGH_PATH, 0.0)
	var plough := t._hitch.implement
	assert_float(t._hitch.ball_lift()).is_equal_approx(0.0, 1e-5)
	assert_float(t.mass).is_equal_approx(
			t.spec.mass + plough.mass_kg() * (1.0 - plough.ground_share()), 1e-3)


func test_the_spreader_is_carried_whole_raised_and_lowered() -> void:
	var t := await _spawn_tractor()
	_carry(t, SPREADER_PATH, 1.0)
	var raised := t.mass
	_carry(t, SPREADER_PATH, 0.0)
	assert_float(t.mass).is_equal_approx(raised, 1e-3)
	assert_float(t.mass).is_equal_approx(t.spec.mass + t._hitch.implement.mass_kg(), 1e-3)


func test_detached_is_the_spec_exactly() -> void:
	var t := await _spawn_tractor()
	_carry(t, PLOUGH_PATH, 1.0)
	_carry(t, ImplementCatalog.DETACHED, 1.0)
	assert_float(t.mass).is_equal(t.spec.mass)
	assert_vector(t.center_of_mass).is_equal(t.spec.center_of_mass)


func test_a_respawn_with_the_plough_on_carries_it_again_one_tick_later() -> void:
	var t := await _spawn_tractor()
	_carry(t, PLOUGH_PATH, 1.0)
	t.respawn()
	# The base reset wrote the bare machine; the plough survives the respawn on the linkage.
	assert_float(t.mass).is_equal(t.spec.mass)
	# `physics_frame` fires before the nodes tick, so the second await is the first one past a tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(t.mass).is_equal_approx(t.spec.mass + t._hitch.implement.mass_kg(), 1e-3)


## `axle_load` is the rear springs' force, so it needs a floor and real ticks. `InputRouter`
## re-arbitrates every tick, so the hitch is commanded over the bridge (`MeasureRig.drive`'s inbound),
## parked on the foot brake and the lever as the `hitch` pass is.
func test_axle_load_reads_the_rear_springs_and_rises_when_the_plough_is_raised() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var ground := StaticBody3D.new()
	ground.collision_layer = preload("res://src/physics/collision_layers.gd").TERRAIN
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 10.0, 400.0)
	shape.shape = box
	ground.add_child(shape)
	root.add_child(ground)
	ground.global_position = Vector3(0.0, -5.0, 0.0)
	var t := (load(CatalogScript.scene_of("tractor-kenney")) as PackedScene).instantiate() \
			as TractorVehicle
	t.display_only = true
	root.add_child(t)
	await get_tree().physics_frame
	t.global_position = Vector3(0.0, 2.0, 0.0)
	t.set_attachment(PLOUGH_PATH)
	var inbound := {"key": 3, "gear": 1, "accel": 0.0, "brake": 100.0, "steer": 0.0,
			"handbrake": 1.0, "hitch_pos": 0.0}
	Bridge.set("_active", true)
	Bridge.set("_inbound", inbound)
	for i in 240:
		await get_tree().physics_frame
	var tel := t.telemetry as TractorTelemetry
	assert_float(tel.axle_load).is_equal_approx(
			t.drive.rear_suspension_force() / VehicleTelemetry.GRAVITY, 1e-3)
	var lowered := tel.axle_load
	inbound["hitch_pos"] = 100.0
	for i in 240:
		await get_tree().physics_frame
	Bridge.set("_active", false)
	Bridge.set("_inbound", {})
	# The ground's share moves onto the linkage, hung behind the rear axle: the rear takes more
	# than the share itself (`m (L + e) / L`).
	var plough := t._hitch.implement
	assert_float(tel.axle_load - lowered) \
		.override_failure_message("raising the plough must load the rear axle") \
		.is_greater(plough.mass_kg() * plough.ground_share())


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
