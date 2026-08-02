extends GdUnitTestSuite
## Truck J1939 chassis math: the air brake reservoirs and the spring-brake gate, the auxiliary
## driveline retarder, and the drive-axle load read. Pure statics, exercised without a physics
## body — the same discipline as test_tractor / test_drivetrain.
##
## The two behavioural claims this suite exists to pin, because both are quiet failures:
##   - the retarder CANNOT LOCK A WHEEL. Its torque is capped below what the road can answer at
##     that contact patch, so the cap is a property of the model rather than a clamp someone
##     might tune away.
##   - the tuned §6 hierarchy (brake > peak drive > handbrake) still holds on every shipped
##     truck spec WITH the retarder added, not just on the sedan test_drivetrain checks.

const TruckT := preload("res://src/vehicles/truck/truck_telemetry.gd")
const Body := preload("res://src/vehicles/truck/refuse_body.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const SemiScript := preload("res://src/vehicles/truck/semi.gd")
## The North American conventional — the variant whose whole content is a trailer bus it lacks.
const CONVENTIONAL := "semi-conventional"


## Every spec the shipped TRUCK scenes actually load, walked catalog -> scene -> spec rather
## than named by path. test_tractor's lesson, learned the hard way: an orphan spec left behind
## by a refactor kept a suite green while the driveline flags were dead in-game.
func _truck_specs() -> Array[VehicleSpec]:
	var out: Array[VehicleSpec] = []
	for variant in CatalogScript.variants_in_family("truck"):
		var scene: PackedScene = load(CatalogScript.scene_of(variant))
		var state := scene.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == "spec":
				out.append(state.get_node_property_value(0, i) as VehicleSpec)
				break
	return out


## Rear (driven) wheel count off a spec, without a physics body: BaseVehicle calls a corner
## rear when its anchor z > 0, and the truck baseline is rear-drive.
func _rear_count(spec: VehicleSpec) -> int:
	var n := 0
	for p in spec.wheel_positions:
		if p.z > 0.0:
			n += 1
	return n


func _contract() -> ContractScript.ContractData:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	return ContractScript.ContractData.parse(file.get_as_text())


# --- air brake reservoirs (the modeled honest value) --------------------------

func test_air_charges_only_while_the_engine_runs() -> void:
	# The compressor is engine-driven, so a stopped engine makes no air however long you wait.
	assert_float(TruckT.air_step(7.0, 0.0, false, 1.0, 0.45, 1.10)).is_equal(7.0)
	assert_float(TruckT.air_step(7.0, 0.0, true, 1.0, 0.45, 1.10)).is_equal_approx(7.45, 1e-6)
	# One 60 Hz tick under the key.
	assert_float(TruckT.air_step(7.0, 0.0, true, 1.0 / 60.0, 0.45, 1.10)) \
			.is_equal_approx(7.0 + 0.45 / 60.0, 1e-9)


func test_a_brake_application_draws_the_reservoir_down() -> void:
	# Engine off, full application: pure draw.
	assert_float(TruckT.air_step(7.0, 1.0, false, 1.0, 0.45, 1.10)).is_equal_approx(5.9, 1e-6)
	# Running, full application: the compressor cannot keep up, so it still net-drains. That is
	# what makes a long brake application able to reach the gate at all.
	assert_float(TruckT.air_step(7.0, 1.0, true, 1.0, 0.45, 1.10)).is_equal_approx(6.35, 1e-6)
	# Half application draws half as much.
	assert_float(TruckT.air_step(7.0, 0.5, false, 1.0, 0.45, 1.10)).is_equal_approx(6.45, 1e-6)
	# Off the brake it recovers.
	assert_float(TruckT.air_step(6.0, 0.0, true, 1.0, 0.45, 1.10)).is_greater(6.0)


func test_air_is_bounded_at_both_ends() -> void:
	# Working pressure is a ceiling: the governor cuts the compressor out, it does not keep going.
	assert_float(TruckT.air_step(TruckT.AIR_MAX_BAR, 0.0, true, 10.0, 0.45, 1.10)) \
			.is_equal(TruckT.AIR_MAX_BAR)
	# And it never goes negative, however hard or long the brake is held.
	assert_float(TruckT.air_step(0.2, 1.0, false, 10.0, 0.45, 1.10)).is_equal(0.0)
	# A garbage request is clamped like every other input.
	assert_float(TruckT.air_step(7.0, 5.0, false, 1.0, 0.45, 1.10)).is_equal_approx(5.9, 1e-6)
	assert_float(TruckT.air_step(7.0, -3.0, false, 1.0, 0.45, 1.10)).is_equal(7.0)


func test_the_two_circuits_diverge_rather_than_being_a_clone() -> void:
	# The dual circuit is the point (SPN 1087/1088). Circuit 2 runs off a smaller reservoir, so
	# after the same application the two read differently — if these ever match, the pair has
	# become one signal published twice.
	var primary := TruckT.air_step(7.0, 1.0, false, 1.0,
			TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_PRIMARY)
	var secondary := TruckT.air_step(7.0, 1.0, false, 1.0,
			TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_SECONDARY)
	assert_float(primary).is_not_equal(secondary)
	assert_float(primary).is_less(secondary)


# --- the spring-brake gate ----------------------------------------------------

func test_spring_brakes_apply_below_the_cut_in() -> void:
	var gate := TruckT.AIR_SPRING_BRAKE_BAR
	assert_bool(TruckT.spring_brakes_applied(gate + 0.1, gate + 0.1)).is_false()
	assert_bool(TruckT.spring_brakes_applied(gate, gate)).is_false()
	assert_bool(TruckT.spring_brakes_applied(gate - 0.1, gate - 0.1)).is_true()
	assert_bool(TruckT.spring_brakes_applied(0.0, 0.0)).is_true()
	# A fully charged truck can always move.
	assert_bool(TruckT.spring_brakes_applied(TruckT.AIR_MAX_BAR, TruckT.AIR_MAX_BAR)).is_false()


func test_one_healthy_circuit_never_masks_a_failing_one() -> void:
	# The gate reads the MINIMUM, which is what makes the redundancy mean something: the spring
	# chambers are held off by the supply, so a failure on either circuit sets them.
	var gate := TruckT.AIR_SPRING_BRAKE_BAR
	assert_bool(TruckT.spring_brakes_applied(TruckT.AIR_MAX_BAR, gate - 0.5)).is_true()
	assert_bool(TruckT.spring_brakes_applied(gate - 0.5, TruckT.AIR_MAX_BAR)).is_true()


func test_the_warning_sits_above_the_gate_so_there_is_a_band_to_stop_in() -> void:
	# The contract's 'warn' is the LOW-PRESSURE WARNING, not the cut-in. If they ever collapse
	# onto one number the driver goes from a red bar to immobile in the same instant, which is
	# neither real practice nor playable.
	var air := _contract().get_signal_def("air_primary", "out")
	assert_bool(air.has_warn()).is_true()
	assert_float(TruckT.AIR_SPRING_BRAKE_BAR) \
		.override_failure_message("the spring-brake cut-in must sit BELOW the low-pressure warn") \
		.is_less(air.warn)
	# And the spawn pressure is drivable but not full: the truck pulls away immediately, and the
	# bars visibly charge afterwards, which is the whole demonstration.
	assert_float(TruckT.AIR_SPAWN_BAR).is_greater(TruckT.AIR_SPRING_BRAKE_BAR)
	assert_float(TruckT.AIR_SPAWN_BAR).is_less(TruckT.AIR_MAX_BAR)


# --- the retarder (driveline math, so it lives on Drivetrain) ------------------

func test_retarder_fades_out_at_low_speed_and_saturates_once_rolling() -> void:
	# A driveline brake has nothing to work against at walking pace.
	assert_float(DrivetrainScript.retarder_speed_fade(0.0)).is_equal(0.0)
	assert_float(DrivetrainScript.retarder_speed_fade(DrivetrainScript.RETARDER_CUTOUT_MS)).is_equal(0.0)
	assert_float(DrivetrainScript.retarder_speed_fade(DrivetrainScript.RETARDER_FULL_MS)).is_equal(1.0)
	assert_float(DrivetrainScript.retarder_speed_fade(DrivetrainScript.RETARDER_FULL_MS * 4.0)).is_equal(1.0)
	# Halfway between cutout and full.
	var mid := (DrivetrainScript.RETARDER_CUTOUT_MS + DrivetrainScript.RETARDER_FULL_MS) * 0.5
	assert_float(DrivetrainScript.retarder_speed_fade(mid)).is_equal_approx(0.5, 1e-6)
	# Unsigned: rolling backwards, a retarder still retards.
	assert_float(DrivetrainScript.retarder_speed_fade(-DrivetrainScript.RETARDER_FULL_MS)).is_equal(1.0)


func test_retarder_demand_scales_with_the_request_and_stops_at_its_rating() -> void:
	var rated := DrivetrainScript.retarder_rating(1000.0)
	assert_float(rated).is_equal_approx(1000.0 * DrivetrainScript.RETARDER_MAX_FRAC, 1e-6)
	assert_float(DrivetrainScript.retarder_demand(1.0, 20.0, 1000.0)).is_equal_approx(rated, 1e-6)
	assert_float(DrivetrainScript.retarder_demand(0.5, 20.0, 1000.0)) \
			.is_equal_approx(rated * 0.5, 1e-6)
	# Released, standing still, or with no rating at all: a clean zero.
	assert_float(DrivetrainScript.retarder_demand(0.0, 20.0, 1000.0)).is_equal(0.0)
	assert_float(DrivetrainScript.retarder_demand(1.0, 0.0, 1000.0)).is_equal(0.0)
	assert_float(DrivetrainScript.retarder_demand(1.0, 20.0, 0.0)).is_equal(0.0)
	# A garbage request off the bus is clamped like every other input.
	assert_float(DrivetrainScript.retarder_demand(4.0, 20.0, 1000.0)).is_equal_approx(rated, 1e-6)
	assert_float(DrivetrainScript.retarder_demand(-1.0, 20.0, 1000.0)).is_equal(0.0)


func test_the_slip_cap_shuts_off_once_the_axle_is_at_the_target() -> void:
	var dt := 1.0 / 60.0
	var r := 0.36
	var v := 20.0
	# Rolling true: there is headroom, so the cap is not zero.
	assert_float(DrivetrainScript.retarder_slip_cap(v / r, v, r, 3.0, dt)).is_greater(0.0)
	# Already at the target slip: no headroom left, so the retarder adds nothing more.
	var at_target := (v - DrivetrainScript.RETARDER_SLIP_TARGET * v) / r
	assert_float(DrivetrainScript.retarder_slip_cap(at_target, v, r, 3.0, dt)) \
			.is_equal_approx(0.0, 1e-6)
	# Past it (a wheel already skidding on something else): still nothing, never negative.
	assert_float(DrivetrainScript.retarder_slip_cap(at_target * 0.5, v, r, 3.0, dt)).is_equal(0.0)
	# Degenerate geometry is guarded rather than dividing by zero.
	assert_float(DrivetrainScript.retarder_slip_cap(v / r, v, 0.0, 3.0, dt)).is_equal(0.0)
	assert_float(DrivetrainScript.retarder_slip_cap(v / r, v, r, 3.0, 0.0)).is_equal(0.0)


func test_the_slip_cap_reads_a_SIGNED_road_speed_and_works_in_reverse() -> void:
	# BaseVehicle passes linear_velocity.dot(-basis.z), which is negative in reverse, and the
	# cap's signf() depends on that. Passing a magnitude instead would leave the headroom
	# saturated while reversing and quietly disable the backstop, so pin the symmetry.
	var dt := 1.0 / 60.0
	var r := 0.36
	var v := 20.0
	var fwd := DrivetrainScript.retarder_slip_cap(v / r, v, r, 3.0, dt)
	var rev := DrivetrainScript.retarder_slip_cap(-v / r, -v, r, 3.0, dt)
	assert_float(rev).is_equal_approx(fwd, 1e-6)
	# And it shuts off at the target in reverse too, rather than staying wide open.
	var at_target := -(v - DrivetrainScript.RETARDER_SLIP_TARGET * v) / r
	assert_float(DrivetrainScript.retarder_slip_cap(at_target, -v, r, 3.0, dt)) \
			.is_equal_approx(0.0, 1e-6)


func test_the_retarder_is_inert_at_a_standstill_however_the_wheels_are_spinning() -> void:
	# At rest the cap degenerates to a nonzero ceiling (signf(0) == 0). That is not a hole: the
	# demand is faded to exactly 0 below RETARDER_CUTOUT_MS off the same road speed, and
	# retarder_torque takes the minimum. Asserted because a ceiling looks like permission.
	var dt := 1.0 / 60.0
	for spec in _truck_specs():
		assert_float(DrivetrainScript.retarder_slip_cap(50.0, 0.0, spec.wheel_radius,
				spec.wheel_inertia, dt)).is_greater(0.0)
		# Stationary chassis, driven wheels spinning hard (a standing burnout): still nothing.
		assert_float(DrivetrainScript.retarder_torque(1.0, 0.0, 50.0, spec, dt)).is_equal(0.0)
		# And just under the cutout, where the fade is still zero.
		assert_float(DrivetrainScript.retarder_torque(
				1.0, DrivetrainScript.RETARDER_CUTOUT_MS - 0.01, 50.0, spec, dt)).is_equal(0.0)


func test_the_retarder_can_never_skid_the_driven_axle() -> void:
	# THE GUARANTEE, stated as what it actually is: however long the retarder is held on, it
	# cannot drive the driven axle past RETARDER_SLIP_TARGET.
	#
	# It must be a SLIP limit and not a force limit — that is the whole lesson of this test.
	# The first version capped at mu * N * r, which bounds the SATURATED road torque; a locked
	# wheel is already making that much, so it permitted a full skid (measured: slip 1.0 and
	# 8 m/s^2, an emergency stop wearing a retarder's name).
	#
	# Integrated open-loop with NO road reaction pushing back, which is the worst case the wheel
	# can ever see: in the sim the tire is also spinning it back up.
	var dt := 1.0 / 60.0
	for spec in _truck_specs():
		for v: float in [30.0, 22.0, 15.0, 8.0, 4.0, 2.0, -22.0, -8.0]:
			var omega: float = v / spec.wheel_radius
			for _tick in 200:
				var tau := DrivetrainScript.retarder_torque(1.0, v, omega, spec, dt)
				omega = move_toward(omega, 0.0, tau / spec.wheel_inertia * dt)
			# Unsigned, so the reverse cases read the same way: braking slip is how far the
			# wheel has fallen behind the ground, whichever way the truck is pointing.
			var denom: float = maxf(absf(v), RayWheel.LOW_SPEED_FLOOR)
			var slip: float = (absf(v) - absf(omega) * spec.wheel_radius) / denom
			assert_float(slip) \
				.override_failure_message(
					"retarder skidded the axle to slip %f at %f m/s on %s" % [
						slip, v, spec.resource_path]) \
				.is_less_equal(DrivetrainScript.RETARDER_SLIP_TARGET + 1e-6)


func test_the_retarder_is_worth_feeling_on_every_shipped_truck() -> void:
	# The rating is only defensible if the number the docs quote is the number the constants
	# make. Fully faded in, the driven axle's total torque over the wheel radius is a force, and
	# over the mass it is a deceleration — flat road, no drag, which is the same arithmetic
	# drivetrain.gd states. The band is the claim: below ~1 m/s^2 a retarder is indistinguishable
	# from coasting (the Phase 2 drive gate reads as "it does nothing"), and above ~1.6 it has
	# started standing in for the foot brake instead of assisting it.
	for spec in _truck_specs():
		var total: float = DrivetrainScript.retarder_rating(spec.brake_torque) * _rear_count(spec)
		var decel: float = total / spec.wheel_radius / spec.mass
		assert_float(decel) \
			.override_failure_message(
				"%s retards at only %.2f m/s^2 — the docs claim 1.0-1.6" % [
					spec.resource_path, decel]) \
			.is_between(1.0, 1.6)


func test_the_slip_cap_stays_a_backstop_and_not_the_operating_point() -> void:
	# Finding from review: at the previous rating the axle settled near 0.004 slip, so the cap
	# was unreachable and the "cannot lock a wheel" guarantee was only ever exercised open-loop.
	# Pin the margin the other way round instead of restating the settled slip: at the slip
	# TARGET the road can make strictly MORE force than the retarder ever demands, so the
	# equilibrium provably sits below the target and the cap is a backstop. Monotone, so it needs
	# no inverse of the grip curve.
	for spec in _truck_specs():
		var rear: int = _rear_count(spec)
		var demand_n: float = DrivetrainScript.retarder_rating(spec.brake_torque) / spec.wheel_radius
		# Static rear-axle load off the spec's own geometry: the com sits between the axles, so
		# each axle carries the share proportional to the OTHER axle's distance from it.
		var front_z := 0.0
		var rear_z := 0.0
		for p in spec.wheel_positions:
			if p.z > 0.0:
				rear_z = maxf(rear_z, p.z)
			else:
				front_z = minf(front_z, p.z)
		var to_front: float = absf(spec.center_of_mass.z - front_z)
		var wheelbase: float = rear_z - front_z
		var rear_load_n: float = spec.mass * 9.8 * (to_front / wheelbase) / rear
		var grip_at_target: float = VehicleSpec.sample_curve(
				spec.grip_curve, DrivetrainScript.RETARDER_SLIP_TARGET) * spec.mu_long * rear_load_n
		assert_float(grip_at_target) \
			.override_failure_message(
				"%s: the retarder demands %.0f N/wheel but the road only makes %.0f N at the slip cap, so the cap IS the operating point" % [
					spec.resource_path, demand_n, grip_at_target]) \
			.is_greater(demand_n * 2.0)


func test_retarder_percentage_is_what_was_applied_over_the_rating() -> void:
	assert_float(DrivetrainScript.retarder_pct(300.0, 300.0)).is_equal(100.0)
	assert_float(DrivetrainScript.retarder_pct(150.0, 300.0)).is_equal(50.0)
	assert_float(DrivetrainScript.retarder_pct(0.0, 300.0)).is_equal(0.0)
	# Unsigned magnitude: SPN 520's negative convention is documented in the contract, not
	# encoded here, because a negative range would fill the generated bar backwards.
	assert_float(DrivetrainScript.retarder_pct(-150.0, 300.0)).is_equal(50.0)
	# Clamped to the contract range, and safe on a spec with no retarder.
	assert_float(DrivetrainScript.retarder_pct(9000.0, 300.0)).is_equal(100.0)
	assert_float(DrivetrainScript.retarder_pct(150.0, 0.0)).is_equal(0.0)


# --- drive-axle load ----------------------------------------------------------

func test_axle_load_is_the_suspension_force_in_kilograms() -> void:
	# A weight, not a mass lookup: whatever the rear springs were actually holding this tick.
	assert_float(TruckT.axle_load_kg(TruckT.GRAVITY * 5000.0)).is_equal_approx(5000.0, 1e-6)
	assert_float(TruckT.axle_load_kg(TruckT.GRAVITY * 11500.0)).is_equal_approx(11500.0, 1e-6)
	# Airborne: no force, no load. And it never reports a negative weight.
	assert_float(TruckT.axle_load_kg(0.0)).is_equal(0.0)
	assert_float(TruckT.axle_load_kg(-1000.0)).is_equal(0.0)
	# Monotone in force, which is what makes braking weight transfer visible on the bar.
	assert_float(TruckT.axle_load_kg(20000.0)).is_greater(TruckT.axle_load_kg(10000.0))


# --- the shipped truck specs --------------------------------------------------

func test_every_truck_spec_keeps_the_force_hierarchy_with_the_retarder_added() -> void:
	# test_drivetrain pins the §6 hierarchy on the sedan only. The retarder is a new braking
	# torque on the driven axle, so it has to be checked HERE, on the specs that carry it.
	var specs := _truck_specs()
	assert_int(specs.size()).override_failure_message("no truck specs found").is_greater(0)
	for spec in specs:
		var peak_engine := 0.0
		for p in spec.torque_curve:
			peak_engine = maxf(peak_engine, p.y)
		var ratio1 := spec.gear_ratios[0] * spec.final_drive
		var max_drive := peak_engine * ratio1 * spec.efficiency
		var total_brake := spec.brake_torque * spec.wheel_positions.size()
		var total_handbrake := spec.handbrake_torque * 2.0
		var total_retarder := DrivetrainScript.retarder_rating(spec.brake_torque) * _rear_count(spec)

		# Unchanged: full accel + full brake must stop.
		assert_float(total_brake) \
			.override_failure_message("brake no longer beats peak drive").is_greater(max_drive)
		# Unchanged: the handbrake holds only below ~25 % throttle.
		var drive_25: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.25, 1))
		var drive_50: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.5, 1))
		assert_float(total_handbrake).is_greater(drive_25)
		assert_float(total_handbrake).is_less(drive_50)
		# New: the retarder is an AUXILIARY brake. It must not be able to stand in for the foot
		# brake (so it stays well under peak drive), and everything else braking at once must
		# still come to less than the service brake — otherwise the hierarchy has a back door.
		assert_float(total_retarder) \
			.override_failure_message("the retarder has become a second service brake") \
			.is_less(max_drive)
		assert_float(total_retarder + total_handbrake) \
			.override_failure_message("retarder + handbrake outrank the foot brake") \
			.is_less(total_brake)


func test_only_the_truck_declares_a_retarder() -> void:
	# A spec flag is only real on the spec the shipped SCENE loads — and it must be inert
	# everywhere else, or the 'retarder' input bit could change a car's driveline.
	var truck_paths := PackedStringArray()
	for spec in _truck_specs():
		assert_bool(spec.retarder_equipped) \
			.override_failure_message("%s must declare a retarder" % spec.resource_path).is_true()
		truck_paths.append(spec.resource_path)
	assert_int(truck_paths.size()).is_greater(0)

	var checked := 0
	for path in _spec_paths("res://src/vehicles"):
		if path in truck_paths:
			continue
		var spec: VehicleSpec = load(path)
		checked += 1
		assert_bool(spec.retarder_equipped) \
			.override_failure_message("%s must not declare a retarder" % path).is_false()
	assert_int(checked).is_greater(0)


## Every *_spec.tres under `root`, recursively (the test_tractor sweep).
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


# --- struct defaults ----------------------------------------------------------

func test_fresh_truck_telemetry_rests_part_charged_and_released() -> void:
	var t := TruckT.new()
	assert_float(t.air_primary).is_equal(TruckT.AIR_SPAWN_BAR)
	assert_float(t.air_secondary).is_equal(TruckT.AIR_SPAWN_BAR)
	assert_int(t.retarder_state).is_equal(0)
	assert_float(t.axle_load).is_equal(0.0)
	assert_bool(t.pto_state).is_false()
	assert_int(t.engine_load).is_equal(0)
	assert_float(t.engine_hours).is_equal(0.0)
	# A truck spawns able to drive away — the gate must not be on at spawn.
	assert_bool(TruckT.spring_brakes_applied(t.air_primary, t.air_secondary)).is_false()
	# The body signals rest at honest zeros, which is also exactly what a truck with no refuse
	# body publishes forever (the firetruck).
	assert_int(t.body_state).is_equal(Body.State.STOWED)
	assert_int(t.body_pos).is_equal(0)
	assert_bool(t.body_inhibit).is_false()
	assert_bool(t.body_bus).is_false()
	assert_int(t.hopper_load).is_equal(0)


# --- CiA 422 body: the gateway ------------------------------------------------
#
# The two functions here are the whole reason this phase exists: bus_up decides whether the second
# network is powered at all, and is_inhibited is a value computed from CHASSIS state and published
# on the BODY network. Nothing else in the project crosses a bus boundary.

func test_the_body_network_is_powered_only_by_the_running_engine_and_the_pto() -> void:
	assert_bool(Body.bus_up(true, true)) \
		.override_failure_message("engine running and PTO in must power the body network").is_true()
	assert_bool(Body.bus_up(false, true)) \
		.override_failure_message("key off must take the body network down").is_false()
	assert_bool(Body.bus_up(true, false)) \
		.override_failure_message("the body supply is PTO-driven, so no PTO is no bus").is_false()
	assert_bool(Body.bus_up(false, false)).is_false()


func test_the_interlock_needs_stopped_parked_and_a_live_bus_together() -> void:
	var parked := Body.PARK_BRAKE_MIN + 0.4
	assert_bool(Body.is_inhibited(0.0, parked, true)) \
		.override_failure_message("stopped, parked and powered is the one case that may operate") \
		.is_false()
	assert_bool(Body.is_inhibited(0.0, parked, false)) \
		.override_failure_message("a down body network must inhibit — there is nothing to command") \
		.is_true()
	assert_bool(Body.is_inhibited(0.0, 0.0, true)) \
		.override_failure_message("the parking brake must be SET to swing the arm").is_true()
	assert_bool(Body.is_inhibited(Body.WALK_PACE_MS + 1.0, 1.0, true)) \
		.override_failure_message("holding the brake must not buy you an arm cycle at speed") \
		.is_true()


func test_the_interlock_allows_walking_pace_but_not_road_speed() -> void:
	var parked := 1.0
	# A refuse round is driven at walking pace between bins, so the threshold has to allow that.
	assert_bool(Body.is_inhibited(Body.WALK_PACE_MS * 0.5, parked, true)).is_false()
	assert_bool(Body.is_inhibited(Body.WALK_PACE_MS * 2.0, parked, true)).is_true()
	# Reversing up to a bin is the same case: the threshold is a speed, not a velocity.
	assert_bool(Body.is_inhibited(-Body.WALK_PACE_MS * 0.5, parked, true)).is_false()
	assert_bool(Body.is_inhibited(-Body.WALK_PACE_MS * 2.0, parked, true)) \
		.override_failure_message("reversing fast must inhibit exactly like driving fast").is_true()


# --- CiA 422 body: the state machine -----------------------------------------

const DT := 1.0 / 60.0  ## the locked physics tick, so these run the ticks the game runs


## Run `cmd` for `seconds` of ticks, uninhibited unless told otherwise.
func _run(unit: RefuseBody, cmd: int, seconds: float, inhibit := false) -> void:
	for _i in roundi(seconds / DT):
		unit.step(cmd, inhibit, DT)


func test_a_fresh_body_is_stowed_and_empty() -> void:
	var unit := Body.new()
	assert_float(unit.pos).is_equal(0.0)
	assert_int(unit.state).is_equal(Body.State.STOWED)
	assert_float(unit.hopper).is_equal(0.0)


func test_idle_holds_a_stowed_body_stowed() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.IDLE, 2.0)
	assert_float(unit.pos).is_equal(0.0)
	assert_int(unit.state).is_equal(Body.State.STOWED)


func test_lift_raises_the_arm_and_saturates_at_the_top() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 0.5)
	assert_int(unit.state).is_equal(Body.State.LIFTING)
	assert_float(unit.pos).is_between(0.4, 0.6)
	# Held at the top the mode is still Lift — there is no "Raised" state, and the arm must not
	# creep past full travel however long the command is held.
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 2.0)
	assert_float(unit.pos).is_equal(1.0)
	assert_int(unit.state).is_equal(Body.State.LIFTING)


func test_dump_lifts_first_then_tips_and_fills_the_hopper_once() -> void:
	var unit := Body.new()
	# Dump implies the lift it needs: the arm travels up before anything tips.
	_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC * 0.5)
	assert_int(unit.state) \
		.override_failure_message("a Dump from stowed must lift before it tips") \
		.is_equal(Body.State.LIFTING)
	assert_float(unit.hopper).is_equal(0.0)

	# At the top it tips, and the dwell is what completes the cycle.
	_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC)
	assert_int(unit.state).is_equal(Body.State.DUMPING)
	assert_float(unit.hopper) \
		.override_failure_message("one completed dwell at the top is one completed cycle") \
		.is_equal(Body.HOPPER_PER_CYCLE)

	# Holding the command must NOT keep counting: one Dump selection is one cycle.
	_run(unit, Body.Cmd.DUMP, Body.DUMP_DWELL_SEC * 5.0)
	assert_float(unit.hopper) \
		.override_failure_message("holding Dump ticked the hopper up more than once") \
		.is_equal(Body.HOPPER_PER_CYCLE)


func test_a_second_cycle_needs_the_command_to_leave_dump() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC + Body.DUMP_DWELL_SEC + 0.5)
	assert_float(unit.hopper).is_equal(Body.HOPPER_PER_CYCLE)
	# Lower, then Dump again: a real second cycle, and the load adds up.
	_run(unit, Body.Cmd.LOWER, Body.ARM_TRAVEL_SEC + 0.5)
	assert_float(unit.pos).is_equal(0.0)
	_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC + Body.DUMP_DWELL_SEC + 0.5)
	assert_float(unit.hopper).is_equal(Body.HOPPER_PER_CYCLE * 2.0)


func test_lower_and_idle_both_stow_the_arm() -> void:
	for cmd: int in [Body.Cmd.LOWER, Body.Cmd.IDLE]:
		var unit := Body.new()
		_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 2.0)
		assert_float(unit.pos).is_equal(1.0)
		# Mid-travel it reports Lowering, and it arrives at Stowed.
		_run(unit, cmd, Body.ARM_TRAVEL_SEC * 0.5)
		assert_int(unit.state) \
			.override_failure_message("cmd %d must lower a raised arm" % cmd) \
			.is_equal(Body.State.LOWERING)
		_run(unit, cmd, Body.ARM_TRAVEL_SEC)
		assert_float(unit.pos).is_equal(0.0)
		assert_int(unit.state).is_equal(Body.State.STOWED)


func test_an_unknown_command_byte_stows_rather_than_sticking() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 2.0)
	# The bus can send anything; the fallback must be the safe pose, not a stuck arm.
	_run(unit, 200, Body.ARM_TRAVEL_SEC * 2.0)
	assert_float(unit.pos).is_equal(0.0)
	assert_int(unit.state).is_equal(Body.State.STOWED)


func test_the_interlock_freezes_the_arm_where_it_stands_and_resumes_from_there() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 0.5)
	var frozen := unit.pos
	# Frozen, not driven home: losing the PTO mid-lift leaves the arm up, which is what happens.
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 2.0, true)
	assert_float(unit.pos) \
		.override_failure_message("the interlock moved the arm instead of refusing the command") \
		.is_equal(frozen)
	assert_int(unit.state).is_equal(Body.State.INHIBITED)
	# Clearing it resumes from the frozen position rather than restarting the travel.
	_run(unit, Body.Cmd.LIFT, DT * 2.0)
	assert_float(unit.pos).is_greater(frozen)
	assert_int(unit.state).is_equal(Body.State.LIFTING)


func test_the_interlock_cannot_be_beaten_by_holding_dump_at_the_top() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.LIFT, Body.ARM_TRAVEL_SEC * 2.0)
	_run(unit, Body.Cmd.DUMP, Body.DUMP_DWELL_SEC * 10.0, true)
	assert_float(unit.hopper) \
		.override_failure_message("an inhibited body completed a dump cycle anyway") \
		.is_equal(0.0)
	assert_int(unit.state).is_equal(Body.State.INHIBITED)


func test_the_hopper_saturates_rather_than_wrapping() -> void:
	var unit := Body.new()
	# More cycles than it takes to fill it, so a wrap or an overflow shows up.
	for _i in 20:
		_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC + Body.DUMP_DWELL_SEC + 0.5)
		_run(unit, Body.Cmd.LOWER, Body.ARM_TRAVEL_SEC + 0.5)
		assert_float(unit.hopper).is_between(0.0, 100.0)
	assert_float(unit.hopper).is_equal(100.0)


func test_reset_re_lays_the_body_empty() -> void:
	var unit := Body.new()
	_run(unit, Body.Cmd.DUMP, Body.ARM_TRAVEL_SEC + Body.DUMP_DWELL_SEC + 0.5)
	assert_float(unit.hopper).is_greater(0.0)
	unit.reset()
	assert_float(unit.pos).is_equal(0.0)
	assert_int(unit.state).is_equal(Body.State.STOWED)
	assert_float(unit.hopper) \
		.override_failure_message("respawn is the only way to empty the hopper — it must empty it") \
		.is_equal(0.0)


# --- CiA 422 body: the arm pose, written then read back ----------------------
#
# body_pos is computed back OUT of the mesh rotation the vehicle just wrote, so these two are
# halves of one round trip. If they ever disagree the number and the picture disagree, which is
# the ball_lift() lesson this pairing exists to obey.

func test_the_arm_angle_and_the_published_position_round_trip() -> void:
	for pos01: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var pct := Body.arm_pos_pct(Body.arm_angle_rad(pos01))
		assert_float(pct) \
			.override_failure_message("pos %f did not survive the pose round trip" % pos01) \
			.is_equal_approx(pos01 * 100.0, 0.001)


func test_the_arm_swings_up_and_back_over_the_cab_from_below_the_authored_pose() -> void:
	# NEGATIVE rotation about the arm's own local X is up and back; a sign flip on either end would
	# swing the forks down through the road, or stow them in the air.
	assert_float(Body.ARM_DUMP_DEG) \
		.override_failure_message("the arm must rotate up over the cab, not down into the road") \
		.is_less(0.0)
	assert_float(Body.ARM_STOW_DEG) \
		.override_failure_message("stowed sits BELOW the authored pose, so it must be positive") \
		.is_greater(0.0)
	assert_float(Body.arm_angle_rad(1.0)).is_less(Body.arm_angle_rad(0.0))


func test_the_travel_stays_short_enough_not_to_clip_the_body() -> void:
	# Driving the first pass at -155 deg carried the arm THROUGH the cab instead of over it. There
	# is no cheap geometric predicate for "clips" without a physics query, so the shipped envelope
	# is pinned instead: a future edit that doubles the travel back into the body fails here and
	# has to be re-measured by driving rather than reasoned about.
	assert_float(absf(Body.ARM_DUMP_DEG)) \
		.override_failure_message("this much travel clipped the arm through the body once already") \
		.is_less_equal(90.0)


func test_the_published_position_is_clamped_at_both_ends() -> void:
	# Both ends come from arm_angle_rad, not from a bare 0: stowed is no longer the authored
	# rotation, so hardcoding 0 here would silently re-couple the signal to the export.
	assert_float(Body.arm_pos_pct(Body.arm_angle_rad(0.0))).is_equal(0.0)
	assert_float(Body.arm_pos_pct(Body.arm_angle_rad(1.0))).is_equal(100.0)
	# The authored pose is PART WAY up now, and must publish as such rather than as stowed.
	assert_float(Body.arm_pos_pct(0.0)).is_between(1.0, 99.0)
	# A pose outside the travel (a hand-edited scene, a future limit) must not publish >100 or <0.
	assert_float(Body.arm_pos_pct(deg_to_rad(Body.ARM_DUMP_DEG * 2.0))).is_equal(100.0)
	assert_float(Body.arm_pos_pct(deg_to_rad(Body.ARM_STOW_DEG * 2.0))).is_equal(0.0)


# --- CiA 422 body: the hopper is mass, and mass is the only coupling ---------

func test_the_hopper_maps_to_a_real_payload_in_kilograms() -> void:
	assert_float(Body.hopper_mass_kg(0.0)).is_equal(0.0)
	assert_float(Body.hopper_mass_kg(100.0)).is_equal(Body.HOPPER_PAYLOAD_KG)
	assert_float(Body.hopper_mass_kg(50.0)).is_equal_approx(Body.HOPPER_PAYLOAD_KG * 0.5, 0.001)
	# Clamped, so a bad percentage cannot make the chassis lighter than empty or absurdly heavy.
	assert_float(Body.hopper_mass_kg(-20.0)).is_equal(0.0)
	assert_float(Body.hopper_mass_kg(400.0)).is_equal(Body.HOPPER_PAYLOAD_KG)


func test_a_full_hopper_is_a_payload_the_shipped_suspension_can_carry() -> void:
	# The whole point of the mass coupling is that axle_load and engine_load report it. That only
	# works if the springs can actually hold the loaded truck up: a payload past the suspension
	# force cap would sit the chassis on its bump stops and flatten the very signal it feeds.
	for spec in _truck_specs():
		var loaded := spec.mass + Body.HOPPER_PAYLOAD_KG
		var rear := _rear_count(spec)
		assert_int(rear).is_greater(0)
		# Worst case: the whole loaded weight on the rear axle (it never is, but the cap must hold).
		var per_wheel := loaded * 9.8 / float(rear)
		assert_float(per_wheel) \
			.override_failure_message(
				"a full hopper exceeds %s's suspension force cap — raising HOPPER_PAYLOAD_KG is a" \
				% spec.resource_path + " re-tune, not a free number") \
			.is_less(spec.max_suspension_force)
		# And it must stay inside the axle_load signal's own range, or the AXLE bar pins.
		assert_float(loaded).is_less(20000.0)


# --- the North American variant: the trailer bus as a SUBTRACTION ---------------------
#
# The whole variant is one spec flag, so what has to be pinned is that the flag is a flag: real on
# both shipped specs with opposite values, off by default everywhere else, and — the part that is
# actually the lesson — that a trailer COUPLED to the unit without it publishes honest zeros rather
# than a gap. Everything else about the two units is deliberately identical.


## The shipped scene of one truck variant, instantiated (freed by the caller).
func _truck_scene(variant: String) -> Node:
	var path := CatalogScript.scene_of(variant)
	assert_str(path).override_failure_message("no scene for '%s'" % variant).is_not_empty()
	return (load(path) as PackedScene).instantiate()


func test_the_north_american_unit_is_a_truck_family_BODY_variant() -> void:
	# It is a different tractor UNIT, not a different trailer, so it belongs to the V cycle and the
	# E cycle is untouched: one more truck-family entry, towing through the same SemiTractor script
	# rather than a class of its own.
	assert_str(CatalogScript.family_of(CONVENTIONAL)).is_equal("truck")
	assert_array(CatalogScript.variants_in_family("truck")).contains([CONVENTIONAL])
	# ...and it is not the family default, which stays the garbage truck.
	assert_str(CatalogScript.first_in_family("truck")).is_not_equal(CONVENTIONAL)
	var unit := _truck_scene(CONVENTIONAL)
	assert_object(unit as SemiScript) \
		.override_failure_message("the conventional must run the SemiTractor script").is_not_null()
	assert_bool(unit.has_method("cycle_implement")) \
		.override_failure_message("E would not cycle the conventional's trailer").is_true()
	unit.free()


func test_the_trailer_bus_flag_is_opposite_on_the_two_shipped_units() -> void:
	# THE FLAG IS ONLY REAL ON THE SPEC THE SHIPPED SCENE LOADS (the tractor's orphan-spec lesson),
	# so both are read catalog -> scene -> spec. Europe has the ISO 7638 data pair on pins 6 and 7;
	# North America has no data pair at all and puts trailer ABS on the power line instead.
	var by_variant := {}
	for variant in CatalogScript.variants_in_family("truck"):
		var unit := _truck_scene(variant)
		var spec: VehicleSpec = unit.get("spec")
		by_variant[variant] = spec.trailer_bus_equipped
		unit.free()
	assert_bool(by_variant.get("semi", false)) \
		.override_failure_message("the European cab-over must carry the ISO 11992 data pair") \
		.is_true()
	assert_bool(by_variant.get(CONVENTIONAL, true)) \
		.override_failure_message(
			"the conventional must NOT carry a trailer bus - that absence is the whole variant") \
		.is_false()
	# Every other truck in the family tows nothing, so none of them claims a connector either.
	for variant: String in by_variant:
		if variant == "semi":
			continue
		assert_bool(by_variant[variant]) \
			.override_failure_message("%s claims a trailer bus" % variant).is_false()
	# ...and off by default, so no vehicle anywhere can claim one by omission.
	assert_bool(VehicleSpec.new().trailer_bus_equipped).is_false()


func test_a_coupled_trailer_on_the_north_american_unit_publishes_honest_zeros() -> void:
	# THE LESSON, ASSERTED. TruckVehicle clears the whole bus every tick and SemiTractor only
	# OVERWRITES it behind spec.trailer_bus_equipped, so this reproduces the publish step exactly
	# for a unit without the pair: values a coupled trailer really would produce are offered, the
	# gate refuses them, and every trailer signal stays a real zero — attached steel and bus
	# silence, never a gap.
	for variant in CatalogScript.variants_in_family("truck"):
		var unit := _truck_scene(variant)
		var spec: VehicleSpec = unit.get("spec")
		unit.free()
		if spec.trailer_bus_equipped:
			continue
		var t := TruckT.new()
		# Values a coupled trailer really would produce, so a publish that ignored the gate is
		# visible rather than indistinguishable from a fresh struct.
		t.trailer_connected = true
		t.trailer_axle_load = 19766.0
		t.trailer_brake_demand = 55
		t.trailer_abs = true
		# The per-tick clear, and then the publish that never happens: SemiTractor writes the four
		# fields ONLY under `if spec.trailer_bus_equipped`, and this unit does not have it.
		t.clear_trailer_bus()
		assert_bool(t.trailer_connected) \
			.override_failure_message(
				"%s: a coupled trailer must not claim on a unit with no data pair" % variant) \
			.is_false()
		assert_float(t.trailer_axle_load).is_equal(0.0)
		assert_int(t.trailer_brake_demand).is_equal(0)
		assert_bool(t.trailer_abs).is_false()
		# Zeros, not absences: the bridge walks to_bridge_dict, so the cluster keeps its shape.
		var d := t.to_bridge_dict()
		for key in ["trailer_connected", "trailer_axle_load", "trailer_brake_demand", "trailer_abs"]:
			assert_bool(d.has(key)) \
				.override_failure_message("%s: to_bridge_dict drops '%s'" % [variant, key]) \
				.is_true()


func test_the_trailer_still_brakes_on_the_unit_with_no_bus() -> void:
	# The pneumatic lines are not the data pair. Only the PUBLISHING goes dark, so the EBS11 blend
	# the trailer's own wheels brake with is computed the same way on both units — a unit that could
	# not stop its trailer would be a different vehicle, not a different protocol.
	assert_float(TruckT.trailer_brake_blend(0.6, 0)).is_equal_approx(0.6, 1e-6)
	assert_float(TruckT.trailer_brake_blend(0.0, 100)) \
		.is_equal_approx(DrivetrainScript.RETARDER_MAX_FRAC, 1e-6)
	# ...and a coupled trailer draws air off either unit's reservoirs, for the same reason.
	assert_float(TruckT.trailer_air_draw(true, 0.0)).is_greater(0.0)


func test_the_j2497_lamp_is_one_mirrored_bit_and_nothing_else() -> void:
	# SAE J2497 / PLC4TRUCKS carries trailer ABS on the POWER line as LAMP ON / LAMP OFF, so the
	# entire North American trailer protocol is one contract "in" bool with its own flavor — no
	# range (that would generate a bar), no counterpart "out" signal (nothing in the game may
	# source it), and no local timer anywhere, exactly like the DM1 lamps.
	var data := _contract()
	var sig := data.get_signal_def("trailer_abs_lamp", "in")
	assert_object(sig).override_failure_message("trailer_abs_lamp is missing").is_not_null()
	assert_str(sig.type).is_equal("bool")
	assert_str(sig.flavor) \
		.override_failure_message("the North American boundary is its OWN flavor, not iso11992") \
		.is_equal("j2497")
	assert_array(sig.vehicles).is_equal(["truck"])
	assert_int(sig.range.size()) \
		.override_failure_message("a tell-tale must not generate a bar").is_equal(0)
	assert_bool(data.has_signal_def("trailer_abs_lamp", "out")) \
		.override_failure_message("nothing in the game may source this bit").is_false()
	# It is the WHOLE flavor: one signal, which is the contrast with iso11992's five.
	var j2497 := 0
	for s in data.signals:
		if s.flavor == "j2497":
			j2497 += 1
	assert_int(j2497) \
		.override_failure_message("j2497 must stay ONE signal - that is the subtraction") \
		.is_equal(1)
	# ...and the desc carries the lesson, where someone adding a second one would read it.
	assert_str(sig.desc).contains("bus silence")


func test_the_conventional_leaves_the_trailers_the_same_room_to_swing() -> void:
	# GEOMETRY, NOT TASTE, and the one thing a longer tractor unit could quietly break: every
	# trailer's forward corners swing about the kingpin on a radius that has to fit between the
	# kingpin and the rearmost cab structure. test_trailer pins the trailers against the cab-over's
	# gap, so this pins the conventional against the SAME gap rather than against a literal — the
	# sleeper is what a bonneted unit spends that clearance on, and moving it back stops the rig
	# turning.
	var semi := _truck_scene("semi")
	var cab: MeshInstance3D = semi.get_node("Body/Cab")
	var cabover_gap: float = SemiScript.KINGPIN_LOCAL.z \
			- (cab.position.z + (cab.mesh as BoxMesh).size.z * 0.5)
	semi.free()

	var unit := _truck_scene(CONVENTIONAL)
	var kingpin: Node3D = unit.get_node_or_null(unit.get("kingpin_path"))
	assert_object(kingpin) \
		.override_failure_message("conventional.tscn has no Kingpin marker").is_not_null()
	# The COUPLING PLANE may not move: every trailer is authored with its ground at y = -1.05
	# against a plate top at y = 1.05, so a variant that raised or dropped it would float or bury
	# every trailer in the catalog.
	assert_float(kingpin.position.y) \
		.override_failure_message("the coupling plane is shared by every trailer - it cannot move") \
		.is_equal_approx(SemiScript.KINGPIN_LOCAL.y, 1e-6)
	var sleeper: MeshInstance3D = unit.get_node("Body/Sleeper")
	var gap: float = kingpin.position.z \
			- (sleeper.position.z + (sleeper.mesh as BoxMesh).size.z * 0.5)
	unit.free()
	assert_float(gap) \
		.override_failure_message(
			"the conventional leaves %.3f m from kingpin to sleeper, less than the cab-over's %.3f"
			% [gap, cabover_gap]) \
		.is_greater_equal(cabover_gap - 1e-6)
	# ...and it really is the LONGER unit, which is the point of the silhouette.
	var conv_spec: VehicleSpec = load("res://src/vehicles/truck/conventional_spec.tres")
	var semi_spec: VehicleSpec = load("res://src/vehicles/truck/semi_spec.tres")
	assert_float(_wheelbase(conv_spec)) \
		.override_failure_message("a bonneted conventional must be the longer-wheelbase unit") \
		.is_greater(_wheelbase(semi_spec))


## Front-to-rear axle distance off a spec's own anchors.
func _wheelbase(spec: VehicleSpec) -> float:
	var front := 0.0
	var rear := 0.0
	for p in spec.wheel_positions:
		front = minf(front, p.z)
		rear = maxf(rear, p.z)
	return rear - front
