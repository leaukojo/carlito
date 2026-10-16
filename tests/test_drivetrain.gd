extends GdUnitTestSuite
## Drivetrain math + RAMN gear-byte semantics.
## Pure logic — specs are built inline with round numbers so every expected value
## is hand-checkable; §6 at the bottom is the brake pedal's map.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")
const GroundDriveSpecScript := preload("res://src/vehicles/base/ground_drive_spec.gd")

const GEAR_N := 0x00
const GEAR_R := 0xFF
const GEAR_P := 0xFE
const TICK := 1.0 / 60.0


func _spec() -> VehicleSpecScript:
	var spec: VehicleSpecScript = VehicleSpecScript.new()
	spec.ground_drive = GroundDriveSpecScript.new()
	spec.torque_curve = PackedVector2Array([
		Vector2(1000, 100), Vector2(2000, 200), Vector2(3000, 300), Vector2(4000, 200)])
	spec.idle_rpm = 800.0
	spec.redline_rpm = 4000.0
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5, 1.2, 1.0, 0.8])
	spec.reverse_ratio = 3.2
	spec.final_drive = 4.0
	spec.efficiency = 0.9
	spec.shift_up_rpm = 3500.0
	spec.shift_down_rpm = 1500.0
	# A car's crank behind a friction clutch rated the default 1.5x peak (450 Nm); the converter's
	# fixture is `_converter_spec`.
	spec.engine_inertia = 0.2
	spec.coupling = VehicleSpecScript.Coupling.CLUTCH
	return spec


## `_spec` behind a torque converter (a fluid coupling unless a test sets a ratio), its lock-up from
## gear 1.
func _converter_spec() -> VehicleSpecScript:
	var spec := _spec()
	spec.coupling = VehicleSpecScript.Coupling.CONVERTER
	return spec


## The wheel side a fixture's crank couples to: one lumped output at `omega` (rad/s at the axle),
## whose step moves `TICK / inertia` rad/s per N·m; INF inertia holds it at `omega` (a braked wheel,
## or one the road holds at the speed a test sets).
class LumpedWheel:
	var omega := 0.0
	var inertia := INF

	func _init(p_omega := 0.0, p_inertia := INF) -> void:
		omega = p_omega
		inertia = p_inertia

	func compliance() -> float:
		return 0.0 if is_inf(inertia) else (1.0 / 60.0) / inertia


## One tick of a wheel-driving Drivetrain against a lumped wheel side, as `WheelDrive` runs it:
## `process`, then the gearbox output solved against the wheel (`Drivetrain.couple`), the wheel
## moved by what it passed. Returns that axle torque (N·m, + = forward on the wheel). Road speed is
## the wheel's own unless given.
func _tick(dt: DrivetrainScript, throttle: float, wheel: LumpedWheel, byte: int, auto := false,
		ground_speed := NAN) -> float:
	var road := wheel.omega * dt.road_radius if is_nan(ground_speed) else ground_speed
	dt.process(TICK, throttle, wheel.omega, road, byte, auto)
	var c := wheel.compliance()
	var t := dt.couple(func(spin: float, crank_c: float, capacity: float) -> float:
		return -Differential.coupling_torque(wheel.omega, spin, c, crank_c, capacity),
		func(torque: float) -> float: return wheel.omega + torque * c)
	wheel.omega += t * c
	return t


# --- sample_curve -----------------------------------------------------------

func test_sample_curve_interpolates_and_clamps() -> void:
	var points := PackedVector2Array([Vector2(1000, 100), Vector2(2000, 200)])
	assert_float(VehicleSpecScript.sample_curve(points, 1500.0)).is_equal_approx(150.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 1000.0)).is_equal_approx(100.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 500.0)).is_equal_approx(100.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 9000.0)).is_equal_approx(200.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(PackedVector2Array(), 1.0)).is_equal(0.0)


# --- gear byte semantics (RAMN: 0x00=N, 0x01..0x06=D1-D6, 0xFF=R; plus 0xFE=P) ------

func test_gear_byte_classification() -> void:
	assert_bool(DrivetrainScript.is_drive(0)).is_false()
	for byte in range(1, 7):
		assert_bool(DrivetrainScript.is_drive(byte)).is_true()
	assert_bool(DrivetrainScript.is_drive(7)).is_false()
	assert_bool(DrivetrainScript.is_reverse(0xFF)).is_true()
	assert_bool(DrivetrainScript.is_reverse(6)).is_false()


func test_invalid_gear_bytes_normalize_to_neutral() -> void:
	for byte in [7, 100, 253, -1]:
		assert_int(DrivetrainScript.normalize_byte(byte)).is_equal(GEAR_N)
	assert_int(DrivetrainScript.normalize_byte(GEAR_R)).is_equal(GEAR_R)
	assert_int(DrivetrainScript.normalize_byte(GEAR_P)).is_equal(GEAR_P)
	assert_int(DrivetrainScript.normalize_byte(3)).is_equal(3)


func test_p_is_engaged_only_on_a_gearbox_with_a_pawl_and_drives_nothing() -> void:
	var spec := _spec()
	spec.ground_drive.park_pawl_torque = 3000.0
	for auto in [true, false]:
		var dt := DrivetrainScript.new(spec)
		var torque := _tick(dt, 1.0, LumpedWheel.new(), GEAR_P, auto)
		assert_int(dt.gear_byte).is_equal(GEAR_P)
		# Open like N: no drive, and the engine free-revs on the pedal.
		assert_float(torque).is_equal(0.0)
		for _i in 120:
			_tick(dt, 1.0, LumpedWheel.new(), GEAR_P, auto)
		assert_float(dt.rpm).is_greater(spec.idle_rpm + 1000.0)
	# No pawl: P is N, and the out byte reports what is engaged.
	var bare := DrivetrainScript.new(_spec())
	bare.process(1.0 / 60.0, 0.0, 0.0, 0.0, GEAR_P, true)
	assert_int(bare.gear_byte).is_equal(GEAR_N)


func test_p_to_d_is_a_selection_not_a_shift() -> void:
	assert_bool(DrivetrainScript.is_open(GEAR_P)).is_true()
	assert_bool(DrivetrainScript.is_open(GEAR_N)).is_true()
	assert_bool(DrivetrainScript.is_open(1)).is_false()
	assert_bool(DrivetrainScript.is_open(GEAR_R)).is_false()
	assert_bool(DrivetrainScript.is_shift(GEAR_P, 1)).is_false()
	assert_bool(DrivetrainScript.is_shift(GEAR_R, GEAR_P)).is_false()


func test_the_pawl_holds_the_driven_wheels_only_at_a_walking_pace_in_p() -> void:
	var gd := GroundDriveSpecScript.new()
	gd.park_pawl_torque = 3000.0
	assert_float(WheelDrive.pawl_torque(true, gd, 0.0)).is_equal(3000.0)
	assert_float(WheelDrive.pawl_torque(true, gd, -0.5)).is_equal(3000.0)
	# Above it the pawl ratchets over the teeth: P holds nothing at speed.
	assert_float(WheelDrive.pawl_torque(true, gd, WheelDrive.PAWL_ENGAGE_SPEED)).is_equal(0.0)
	assert_float(WheelDrive.pawl_torque(true, gd, 10.0)).is_equal(0.0)
	assert_float(WheelDrive.pawl_torque(false, gd, 0.0)).is_equal(0.0)
	gd.park_pawl_torque = 0.0
	assert_float(WheelDrive.pawl_torque(true, gd, 0.0)).is_equal(0.0)


func test_ratio_for_byte_signed_by_direction() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.ratio_for_byte(spec, 1)).is_equal_approx(12.0, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, 6)).is_equal_approx(3.2, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, GEAR_R)).is_equal_approx(-12.8, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, GEAR_N)).is_equal(0.0)
	assert_float(DrivetrainScript.ratio_for_byte(spec, 200)).is_equal(0.0)


## A drive byte past a short gearbox reads the top ratio rather than indexing out of range, so a
## wheel-less spec need not carry six ratios to survive a bridge-exact gear byte.
func test_ratio_for_byte_clamps_to_a_short_gearbox() -> void:
	var spec := _spec()
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5])
	assert_float(DrivetrainScript.ratio_for_byte(spec, 6)) \
			.is_equal_approx(1.5 * spec.final_drive, 0.001)
	spec.gear_ratios = PackedFloat32Array()
	assert_float(DrivetrainScript.ratio_for_byte(spec, 1)).is_equal(0.0)


# --- engine torque ------------------------------------------------------------

func test_engine_torque_is_the_curve_and_nothing_else() -> void:
	# The redline does NOT live here — it is a fuel cut (limiter_cut), so the curve is free to
	# say what the engine makes at its redline. engine_load reads this too, so hiding a cut in
	# here would also lie about the load at a rpm the engine is perfectly happy at.
	var spec := _spec()
	assert_float(DrivetrainScript.engine_torque(spec, 2500.0)).is_equal_approx(250.0, 0.001)
	assert_float(DrivetrainScript.engine_torque(spec, 4000.0)).is_equal_approx(200.0, 0.001)
	assert_float(DrivetrainScript.engine_torque(spec, 5000.0)).is_equal_approx(200.0, 0.001)


func test_limiter_cut_judges_the_unclamped_crank_speed() -> void:
	var spec := _spec()   # redline 4000
	assert_bool(DrivetrainScript.limiter_cut(spec, 3999.0)).is_false()
	assert_bool(DrivetrainScript.limiter_cut(spec, 4000.0)).is_true()
	assert_bool(DrivetrainScript.limiter_cut(spec, 6000.0)).is_true()


func test_wheel_engine_rpm_is_unclamped_and_rpm_from_wheel_is_its_clamp() -> void:
	# 40 rad/s D1 (ratio 12) is ~4584 rpm vs 4000 redline (one bounded, one raw).
	var spec := _spec()
	var raw: float = DrivetrainScript.wheel_engine_rpm(spec, 40.0, 1)
	assert_float(raw).is_equal_approx(40.0 * 12.0 * 60.0 / TAU, 0.01)
	assert_float(raw).is_greater(spec.redline_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 40.0, 1)).is_equal(spec.redline_rpm)
	assert_float(DrivetrainScript.wheel_engine_rpm(spec, 500.0, GEAR_N)).is_equal(spec.idle_rpm)


# --- RPM from wheel speed -----------------------------------------------------

func test_rpm_from_wheel_exact_ratio_math() -> void:
	var spec := _spec()
	# 50 rad/s through D3 (1.5 * 4.0 = 6): 300 rad/s engine = 300 * 60 / TAU rpm.
	var expected := 300.0 * 60.0 / TAU
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 50.0, 3)).is_equal_approx(expected, 0.01)


func test_rpm_from_wheel_clamps_idle_and_redline() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 0.1, 1)).is_equal(spec.idle_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 1000.0, 1)).is_equal(spec.redline_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 500.0, GEAR_N)).is_equal(spec.idle_rpm)


func test_the_limiter_cuts_fuel_past_the_redline() -> void:
	# The limiter judges the crank. Spec curve ends (4000, 200): 200 Nm tail.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# D1 (ratio 12) at 40 rad/s of wheel is ~4584 rpm, past the 4000 redline: the locked coupling
	# carries the crank there. Bridge mode so the box cannot upshift out of it.
	var torque := 0.0
	for i in 60:
		torque = _tick(dt, 1.0, LumpedWheel.new(40.0), 1)
	assert_float(dt.rpm).is_greater(spec.redline_rpm)
	assert_float(torque).is_equal_approx(0.0, 1e-6)
	# The fuel cut has to reach telemetry too — an engine that is being cut is not making the
	# load the pedal is still asking for (the same rule applied_throttle exists for).
	assert_float(dt.applied_throttle).is_equal(0.0)


func test_the_limiter_lands_the_crank_on_the_redline_and_never_fuels_past_it() -> void:
	# A free crank floored in N would cross the redline by a big step in one tick: the crossing
	# tick is fuelled to land on it exactly, and the next is the hard cut. Its own fuel never takes
	# the needle past the red mark.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var reached := -1
	for i in 240:
		_tick(dt, 1.0, LumpedWheel.new(), GEAR_N)
		assert_float(dt.rpm).is_less_equal(spec.redline_rpm + 1e-6)
		if reached < 0 and dt.rpm >= spec.redline_rpm - 1e-6:
			reached = i
	assert_int(reached).is_greater_equal(0)
	# On the redline: cut; fallen off it: fuelled back onto it. A cycle between the two.
	var cuts := 0
	for i in 10:
		_tick(dt, 1.0, LumpedWheel.new(), GEAR_N)
		if dt.applied_throttle == 0.0:
			cuts += 1
		assert_float(dt.rpm).is_less_equal(spec.redline_rpm + 1e-6)
	assert_int(cuts).is_between(3, 7)


func test_a_coupled_crank_lands_its_crossing_on_the_redline_too() -> void:
	# Floored in D1 with the wheels spinning free on the crank's own fuel (a lifted pair): the
	# coupled solve lands the crossing on the redline, so the crank never fuels past it there either.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var wheel := LumpedWheel.new(0.0, 2.4)
	var reached := false
	for i in 600:
		_tick(dt, 1.0, wheel, 1)
		assert_float(dt.rpm).is_less_equal(spec.redline_rpm + 1e-3)
		reached = reached or dt.rpm >= spec.redline_rpm - 1.0
	assert_bool(reached).is_true()


func test_below_the_redline_the_engine_still_makes_its_curve() -> void:
	# The other side of the cut: it is a limiter, not a de-rate. 20 rad/s in D1 is ~2292 rpm.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 60:
		torque = _tick(dt, 1.0, LumpedWheel.new(20.0), 1)
	assert_float(dt.applied_throttle).is_equal(1.0)
	assert_float(absf(torque)).is_greater(0.0)


func test_rpm_positive_in_reverse() -> void:
	var spec := _spec()
	# Reversing: wheel spins backwards, ratio is negative — RPM must still be positive.
	var rpm: float = DrivetrainScript.rpm_from_wheel(spec, -20.0, GEAR_R)
	assert_float(rpm).is_equal_approx(absf(-20.0 * -12.8) * 60.0 / TAU, 0.01)


# --- wheel torque ---------------------------------------------------------------

func test_wheel_torque_product_and_sign() -> void:
	var spec := _spec()
	# 2000 rpm -> 200 Nm engine; D1 ratio 12; efficiency 0.9; half throttle.
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 0.5, 1)) \
			.is_equal_approx(200.0 * 0.5 * 12.0 * 0.9, 0.001)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 1.0, GEAR_R)) \
			.is_equal_approx(200.0 * -12.8 * 0.9, 0.001)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 1.0, GEAR_N)).is_equal(0.0)


func test_wheel_torque_clamps_throttle_magnitude() -> void:
	var spec := _spec()
	# Throttle is a 0..1 magnitude — direction comes from the gear, so a
	# stray negative value must never flip the torque sign.
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, -1.0, 1)).is_equal(0.0)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 2.0, 1)) \
			.is_equal_approx(200.0 * 12.0 * 0.9, 0.001)


# --- auto-shift ------------------------------------------------------------------

func test_auto_shift_thresholds() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, 3, 3500.0)).is_equal(4)
	assert_int(DrivetrainScript.auto_shift(spec, 3, 1500.0)).is_equal(2)
	assert_int(DrivetrainScript.auto_shift(spec, 3, 2500.0)).is_equal(3)


func test_auto_shift_stays_within_gearbox() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, 6, 4000.0)).is_equal(6)
	assert_int(DrivetrainScript.auto_shift(spec, 1, 800.0)).is_equal(1)


func test_auto_shift_stays_inside_a_short_gearbox() -> void:
	# A spec with fewer than TOP_GEAR ratios is never upshifted past its last real ratio
	# (governed_upshift guards the same).
	var spec := _spec()
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5])
	assert_int(DrivetrainScript.auto_shift(spec, 3, 4000.0)).is_equal(3)
	assert_int(DrivetrainScript.auto_shift(spec, 2, 4000.0)).is_equal(3)
	# The downshift end is untouched by the guard.
	assert_int(DrivetrainScript.auto_shift(spec, 3, 800.0)).is_equal(2)


func test_auto_shift_never_touches_neutral_or_reverse() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, GEAR_N, 4000.0)).is_equal(GEAR_N)
	assert_int(DrivetrainScript.auto_shift(spec, GEAR_R, 4000.0)).is_equal(GEAR_R)


# --- process (instance tick) ------------------------------------------------------

func test_process_enters_drive_and_delivers_forward_torque() -> void:
	# A held wheel, pedal floored: the crank revs to its launch target, and from then on the slipping
	# coupling pushes the wheel forward.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 30:
		torque = _tick(dt, 1.0, LumpedWheel.new(), 1, true)
	assert_int(dt.gear_byte).is_equal(1)
	assert_float(torque).is_greater(0.0)


func test_process_reverse_delivers_negative_torque() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 30:
		torque = _tick(dt, 1.0, LumpedWheel.new(), GEAR_R, true)
	assert_int(dt.gear_byte).is_equal(GEAR_R)
	assert_float(torque).is_less(0.0)


func test_process_exact_mode_adopts_bridge_byte_without_auto_shift() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# Bridge mode (gear owns direction): byte is verbatim even at a wheel
	# speed whose rpm is far above the auto upshift threshold.
	dt.process(TICK, 1.0, 100.0, 100.0 * spec.ground_drive.wheel_radius, 2, false)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_auto_upshifts_at_speed() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(TICK, 1.0, 0.0, 0.0, 1, true)
	# Road speed giving 40 rad/s of wheel spin (no slip) through D1 (ratio 12) is
	# ~4584 rpm, above shift_up 3500. Auto-shift decides on this road speed, not spin.
	dt.process(TICK, 1.0, 40.0, 40.0 * spec.ground_drive.wheel_radius, 1, true)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_rpm_rests_at_idle() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 0.0, LumpedWheel.new(), GEAR_N, true)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1.0)


# --- the crank ----------------------------------------------------------------------

func test_a_free_crank_integrates_the_engine_law() -> void:
	# In N nothing loads the crank: one tick moves it by the engine's own net torque over its
	# inertia, `crank_torque * dt / J`, at the delivered fuel.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.rpm = 2000.0
	_tick(dt, 0.5, LumpedWheel.new(), GEAR_N)
	var expected := 2000.0 / DrivetrainScript.RADS_TO_RPM \
			+ DrivetrainScript.crank_torque(spec, 2000.0, 0.5) * TICK / spec.engine_inertia
	assert_float(dt.rpm / DrivetrainScript.RADS_TO_RPM).is_equal_approx(expected, 1e-9)
	# The law is brief 02's: f * curve + (1 - f) * motoring, motoring -frac * peak at the redline.
	assert_float(DrivetrainScript.crank_torque(spec, 4000.0, 0.0)).is_equal_approx(-30.0, 1e-9)
	assert_float(DrivetrainScript.crank_torque(spec, 2000.0, 0.25)) \
			.is_equal_approx(0.25 * 200.0 + 0.75 * DrivetrainScript.motoring_torque(spec, 2000.0), 1e-9)


func test_fuel_to_land_puts_a_free_crank_on_its_target_in_one_tick() -> void:
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var omega := 1500.0 / DrivetrainScript.RADS_TO_RPM
	var target := omega + 5.0
	var c := TICK / spec.engine_inertia
	var f := DrivetrainScript.fuel_to_land(spec, omega, target, c)
	assert_float(f).is_between(0.0, 1.0)
	assert_float(omega + DrivetrainScript.crank_torque(spec, 1500.0, f) * c) \
			.is_equal_approx(target, 1e-9)
	# Out of reach either way: clamped, never past full or below none.
	assert_float(DrivetrainScript.fuel_to_land(spec, omega, omega + 1000.0, c)).is_equal(1.0)
	assert_float(DrivetrainScript.fuel_to_land(spec, omega, omega - 1000.0, c)).is_equal(0.0)


func test_a_light_crank_settles_on_a_steep_droop_without_ringing() -> void:
	# `race`'s case: a 0.06 kg·m² crank on a curve falling 230 N·m over 200 rpm gains ~3 a tick
	# explicitly. The semi-implicit step (`crank_compliance`) lands it on the droop monotonically.
	var spec := _spec()
	spec.engine_inertia = 0.06
	spec.engine_brake_frac = 0.1
	spec.torque_curve = PackedVector2Array([Vector2(1000, 300), Vector2(3800, 360),
			Vector2(4000, 130)])
	var stiff := DrivetrainScript.crank_stiffness(spec, 3900.0, 1.0)
	assert_float(stiff * TICK / spec.engine_inertia).is_greater(2.0)
	var pedal := DrivetrainScript.drag_fuel(spec, 3900.0)
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.rpm = 3810.0
	var prev := dt.rpm
	for i in 120:
		_tick(dt, pedal, LumpedWheel.new(), GEAR_N)
		assert_float(dt.rpm).is_greater_equal(prev - 1e-6)
		assert_float(dt.rpm).is_less_equal(3900.0 + 1e-3)
		prev = dt.rpm
	assert_float(dt.rpm).is_equal_approx(3900.0, 0.5)


func test_the_idle_controller_brings_a_dragged_crank_back_to_idle_without_overshoot() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.rpm = spec.idle_rpm - 300.0
	for i in 30:
		_tick(dt, 0.0, LumpedWheel.new(), GEAR_N)
		assert_float(dt.rpm).is_less_equal(spec.idle_rpm + 1e-6)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1e-6)
	# Idle fuelling shows as delivered fuel only while it works; at idle on the frictionless law it
	# is 0.
	assert_float(dt.applied_throttle).is_equal_approx(0.0, 1e-9)


func test_an_engine_with_friction_burns_fuel_to_hold_its_idle() -> void:
	# Friction 0.1 of the 300 peak is 30 N·m at idle, against the curve's 100 there: the idle
	# controller holds the crank on idle with the fuel that nets zero, 30 / 130.
	var spec := _spec()
	spec.engine_friction_frac = 0.1
	spec.engine_brake_frac = 0.2
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 30:
		_tick(dt, 0.0, LumpedWheel.new(), GEAR_N)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1e-6)
	assert_float(dt.applied_throttle).is_equal_approx(30.0 / 130.0, 1e-6)


func test_a_lifted_pedal_runs_a_free_crank_down_to_idle_on_the_motoring_law() -> void:
	# Lifted in N, the crank falls on `-peak (a + (b - a) x)`, linear in its speed: the semi-implicit
	# step shrinks `(omega - idle) + c` by `J / (J + k dt)` a tick (k the law's slope, c = peak a / k),
	# and the idle controller catches it on idle. Friction (a) is what gets it there: without it the
	# fall slows to nothing as it nears idle.
	var spec := _spec()
	spec.engine_friction_frac = 0.1
	spec.engine_brake_frac = 0.2
	var peak := 300.0
	var j := spec.engine_inertia
	var k := (0.2 - 0.1) * peak / ((spec.redline_rpm - spec.idle_rpm) / DrivetrainScript.RADS_TO_RPM)
	assert_float(DrivetrainScript.crank_stiffness(spec, 2000.0, 0.0)).is_equal_approx(k, 1e-9)
	var c := peak * 0.1 / k
	var start := 3000.0
	var gap := (start - spec.idle_rpm) / DrivetrainScript.RADS_TO_RPM
	var expected := ceili(log(c / (gap + c)) / log(j / (j + k * TICK)))
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.rpm = start
	var ticks := 0
	while dt.rpm > spec.idle_rpm + 1e-6 and ticks < 600:
		_tick(dt, 0.0, LumpedWheel.new(), GEAR_N)
		assert_float(dt.rpm).is_greater_equal(spec.idle_rpm - 1e-6)
		ticks += 1
	assert_int(ticks).is_equal(expected)
	# The same law with no friction is still well above idle after those ticks.
	spec.engine_friction_frac = 0.0
	dt = DrivetrainScript.new(spec)
	dt.rpm = start
	for i in ticks:
		_tick(dt, 0.0, LumpedWheel.new(), GEAR_N)
	assert_float(dt.rpm).is_greater(spec.idle_rpm + 500.0)


func test_key_off_runs_the_crank_down_and_ignition_steps_it_back_to_idle() -> void:
	# The key-off crank turns against the motoring law alone: its friction stops it.
	var spec := _spec()
	spec.engine_friction_frac = 0.1
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.running = false
	var prev := dt.rpm
	for i in 180:
		_tick(dt, 1.0, LumpedWheel.new(), 1)
		assert_float(dt.rpm).is_less_equal(prev)
		prev = dt.rpm
		# No fuel, and nothing reaches the wheels.
		assert_float(dt.applied_throttle).is_equal(0.0)
		assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.OPEN)
	assert_float(dt.rpm).is_equal(0.0)
	# The key back to Ignition: the starter (not modelled) puts the crank on idle that tick.
	dt.running = true
	_tick(dt, 0.0, LumpedWheel.new(), GEAR_N)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1e-6)


# --- the coupling (a held wheel stands in for the brake) ---------------------------
# Fixture band is idle 800 -> redline 4000, so stall is 800 + 0.25 * 3200 = 1600 rpm.

func test_converter_free_rpm_follows_the_n_squared_load_from_idle_to_stall() -> void:
	# With the turbine held the converter loads the crank with coef * omega^2, which full fuel
	# meets at the 1600 rpm stall (160 N·m there). The curve is N / 10 between 1000 and 2000 rpm, so
	# at 0.75 fuel 0.075 N = 160 (N / 1600)^2: 1200 rpm. At 0.3 the fuelled curve (100 N·m flat under
	# 1000) cannot hold even idle's 40 N·m load: the idle controller's floor.
	var spec := _converter_spec()
	assert_float(DrivetrainScript.converter_free_rpm(spec, 1.0)).is_equal(1600.0)
	assert_float(DrivetrainScript.converter_free_rpm(spec, 0.75)).is_equal_approx(1200.0, 0.01)
	assert_float(DrivetrainScript.converter_free_rpm(spec, 0.3)).is_equal(spec.idle_rpm)
	assert_float(DrivetrainScript.converter_free_rpm(spec, 0.0)).is_equal(spec.idle_rpm)
	# Throttle is a 0..1 magnitude here as everywhere else.
	assert_float(DrivetrainScript.converter_free_rpm(spec, -1.0)).is_equal(spec.idle_rpm)
	assert_float(DrivetrainScript.converter_free_rpm(spec, 2.0)).is_equal(1600.0)
	# A clutch's launch line stays linear in the pedal, and both meet at the stall speed.
	var clutch := _spec()
	assert_float(DrivetrainScript.launch_target_rpm(clutch, 0.5)).is_equal_approx(1200.0, 0.001)
	assert_float(DrivetrainScript.launch_target_rpm(clutch, 1.0)).is_equal_approx(1600.0, 0.001)
	assert_float(DrivetrainScript.launch_target_rpm(spec, 0.75)).is_equal_approx(1200.0, 0.01)


func test_a_held_wheel_revs_the_engine_to_stall_and_makes_more_torque_for_it() -> void:
	# Brake or handbrake holding the wheels, pedal down: the slipping clutch lands the crank on its
	# launch line, and carries the curve's torque there.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 120:
		torque = _tick(dt, 1.0, LumpedWheel.new(), 1)
	assert_float(dt.rpm).is_equal_approx(1600.0, 1.0)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
	# 1600 rpm on the curve is 160 Nm against idle's 100; D1 ratio 12, efficiency 0.9.
	assert_float(torque).is_equal_approx(160.0 * 12.0 * 0.9, 1.0)
	assert_float(torque).is_greater(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 1.0, 1))


func test_a_lifted_pedal_never_pours_the_crank_into_the_wheels() -> void:
	# Held on the 1600 rpm line floored, then lifted to 20 %: the line drops to 960. The slipping
	# coupling never carries more than the engine's fuelled torque, so the crank sinks toward the
	# new line on its own motoring and its inertia never floods the wheels.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 1.0, LumpedWheel.new(), 1)
	var prev := dt.rpm
	for i in 120:
		var at_rpm := dt.rpm
		var t := _tick(dt, 0.2, LumpedWheel.new(), 1)
		assert_float(t).is_less_equal(
				DrivetrainScript.wheel_torque(spec, at_rpm, dt.applied_throttle, 1) + 1e-6)
		assert_float(dt.rpm).is_less_equal(prev + 1e-6)
		prev = dt.rpm
	assert_float(dt.rpm).is_less(1600.0)
	assert_float(dt.rpm).is_greater_equal(DrivetrainScript.launch_target_rpm(spec, 0.2) - 1e-6)


func test_a_heavy_amt_launches_on_its_own_target() -> void:
	# `launch_rpm_over_idle` replaces the launch line: the semis' AMT holds 300 over idle.
	var spec := _spec()
	spec.launch_rpm_over_idle = 300.0
	assert_float(DrivetrainScript.launch_target_rpm(spec, 1.0)).is_equal(1100.0)
	assert_float(DrivetrainScript.launch_target_rpm(spec, 0.2)).is_equal(1100.0)
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 1.0, LumpedWheel.new(), 1)
	assert_float(dt.rpm).is_equal_approx(1100.0, 1.0)


func test_a_held_wheel_off_the_pedal_still_rests_at_idle() -> void:
	# A clutch is no creep model: no pedal, no rev, and the coupling stays open.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 0.0, LumpedWheel.new(), 1)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 0.001)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.OPEN)


func test_the_wheels_still_own_the_crank_once_they_outrun_the_launch_line() -> void:
	# A floor, never a ceiling: 20 rad/s in D1 is ~2292 rpm, well past the 1600 stall, so the
	# clutch locks and the crank turns with the wheels.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 1.0, LumpedWheel.new(20.0), 1)
	assert_float(dt.rpm).is_equal_approx(DrivetrainScript.wheel_engine_rpm(spec, 20.0, 1), 1e-6)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)


func test_a_converter_lets_its_lock_up_go_under_its_line_and_a_clutch_stays_locked() -> void:
	# Locked at 1100 rpm (D1) pedal up, then floored: the converter's free rev at full pedal is the
	# 1600 stall, so its lock-up lets go and the converter law takes the crank past it (the turbine
	# turns, so it loads the crank less than held). A friction clutch stays locked and lugs.
	for coupling in [VehicleSpec.Coupling.CONVERTER, VehicleSpec.Coupling.CLUTCH]:
		var spec := _spec()
		spec.coupling = coupling
		var dt: DrivetrainScript = DrivetrainScript.new(spec)
		var omega := 1100.0 / DrivetrainScript.RADS_TO_RPM / 12.0
		for i in 60:
			_tick(dt, 0.0, LumpedWheel.new(omega), 1)
		assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
		for i in 240:
			_tick(dt, 1.0, LumpedWheel.new(omega), 1)
		if coupling == VehicleSpec.Coupling.CONVERTER:
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
			assert_bool(dt.converting).is_true()
			assert_float(dt.rpm).is_greater(1600.0)
			# Steady: the engine's torque is what the converter carries.
			assert_float(dt.coupling_torque).is_equal_approx(
					DrivetrainScript.engine_torque(spec, dt.rpm), 1.0)
		else:
			assert_float(dt.rpm).is_equal_approx(1100.0, 1e-6)
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)


func test_the_foot_brake_releases_a_converter_lock_up_and_keeps_a_clutch_closed() -> void:
	# Locked at 3000 rpm, pedal up, then braking: a converter's lock-up lets go, its crank sinks on
	# its own motoring and the converter passes the wheels only what that slip makes, under the
	# locked engine's braking; a clutch stays closed and keeps it all.
	for coupling in [VehicleSpec.Coupling.CONVERTER, VehicleSpec.Coupling.CLUTCH]:
		var spec := _spec()
		spec.engine_brake_frac = 0.1
		spec.coupling = coupling
		var dt: DrivetrainScript = DrivetrainScript.new(spec)
		var omega := 3000.0 / DrivetrainScript.RADS_TO_RPM / 12.0
		for i in 60:
			_tick(dt, 0.0, LumpedWheel.new(omega), 1)
		assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
		var locked_braking := DrivetrainScript.overrun_torque(spec, 3000.0, 0.0, 1)
		dt.braking = true
		var t := 0.0
		for i in 30:
			t = _tick(dt, 0.0, LumpedWheel.new(omega), 1)
		assert_bool(DrivetrainScript.lock_up_released(spec, true)) \
				.is_equal(coupling == VehicleSpec.Coupling.CONVERTER)
		if coupling == VehicleSpec.Coupling.CONVERTER:
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
			assert_bool(dt.converting).is_true()
			assert_float(t).is_less_equal(0.0)
			assert_float(t).is_greater(locked_braking)
			assert_float(dt.rpm).is_less(3000.0)
		else:
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
			assert_float(t).is_less(0.0)
		# Off the brake the lock-up closes again.
		dt.braking = false
		for i in 60:
			_tick(dt, 0.0, LumpedWheel.new(omega), 1)
		assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
		assert_float(dt.rpm).is_equal_approx(3000.0, 1e-3)


# --- the converter ----------------------------------------------------------

func test_a_held_converter_floored_sits_on_stall_and_passes_the_curve_there() -> void:
	# The wheels held, pedal down: the converter law balances full fuel on the 1600 rpm stall, and
	# carries the curve's 160 N·m there through D1 (ratio 12, efficiency 0.9).
	var spec := _converter_spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 120:
		torque = _tick(dt, 1.0, LumpedWheel.new(), 1)
	assert_float(dt.rpm).is_equal_approx(1600.0, 1.0)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
	assert_bool(dt.converting).is_true()
	assert_float(torque).is_equal_approx(160.0 * 12.0 * 0.9, 1.0)
	assert_float(torque).is_equal_approx(DrivetrainScript.stall_axle_torque(spec), 1.0)


func test_a_stall_torque_ratio_multiplies_the_held_drive_and_the_stall_the_brake_holds() -> void:
	var spec := _converter_spec()
	spec.converter_stall_ratio = 2.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 120:
		torque = _tick(dt, 1.0, LumpedWheel.new(), 1)
	# The crank still sits on stall: the ratio is the stator's reaction, which the crank never feels.
	assert_float(dt.rpm).is_equal_approx(1600.0, 1.0)
	assert_float(torque).is_equal_approx(2.0 * 160.0 * 12.0 * 0.9, 2.0)
	assert_float(DrivetrainScript.stall_axle_torque(spec)) \
			.is_equal_approx(2.0 * DrivetrainScript.stall_axle_torque(_converter_spec()), 1e-3)
	# A clutch body multiplies nothing, whatever the field says.
	var clutch := _spec()
	clutch.converter_stall_ratio = 2.0
	assert_float(DrivetrainScript.stall_axle_torque(clutch)) \
			.is_equal_approx(DrivetrainScript.wheel_torque(clutch, 1600.0, 1.0, 1), 1e-3)


func test_a_converter_in_gear_off_the_pedal_creeps() -> void:
	# The wheels held, no pedal: the converter loads the idling crank with idle's ~40 N·m, which the
	# idle controller fuels, so the crank holds a few rpm under idle, the coupling never opens, and
	# the wheels feel the creep through the gear. Off the brake they turn.
	var spec := _converter_spec()
	var neutral: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(neutral, 0.0, LumpedWheel.new(), GEAR_N)
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 120:
		torque = _tick(dt, 0.0, LumpedWheel.new(), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
	assert_float(dt.rpm).is_between(spec.idle_rpm - 100.0, spec.idle_rpm)
	assert_float(torque).is_greater(0.0)
	var coef := TorqueConverter.capacity_coefficient(spec)
	var omega := dt.rpm / DrivetrainScript.RADS_TO_RPM
	assert_float(torque).is_equal_approx(coef * omega * omega * 12.0 * 0.9, 1e-3)
	assert_float(dt.applied_throttle).is_greater(neutral.applied_throttle)
	var wheel := LumpedWheel.new(0.0, 50.0)
	for i in 60:
		_tick(dt, 0.0, wheel, 1)
	assert_float(wheel.omega).is_greater(0.0)


func test_a_converter_drives_the_wheels_from_the_first_tick_of_a_pull_away() -> void:
	# Floored from rest on a free pair: the converter carries drive at once, where a clutch first
	# revs the crank to its launch line with nothing reaching the wheels.
	var converter: DrivetrainScript = DrivetrainScript.new(_converter_spec())
	assert_float(_tick(converter, 1.0, LumpedWheel.new(0.0, 2.4), 1)).is_greater(0.0)
	var clutch: DrivetrainScript = DrivetrainScript.new(_spec())
	assert_float(_tick(clutch, 1.0, LumpedWheel.new(0.0, 2.4), 1)).is_equal(0.0)


func test_the_lock_up_closes_past_the_coupling_point_from_its_gear() -> void:
	# Half pedal on wheels the road holds at 2400 rpm through D1: the converter brings the crank
	# within the coupling point of them and the lock-up closes them together. With the lock-up from
	# gear 2 (an Allison-class box) D1 stays on the converter, its crank a slip above the wheels.
	for lockup_gear in [1, 2]:
		var spec := _converter_spec()
		spec.lockup_gear = lockup_gear
		var dt: DrivetrainScript = DrivetrainScript.new(spec)
		var omega := 2400.0 / DrivetrainScript.RADS_TO_RPM / 12.0
		for i in 120:
			_tick(dt, 0.5, LumpedWheel.new(omega), 1)
		if lockup_gear == 1:
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
			assert_float(dt.rpm).is_equal_approx(2400.0, 1e-3)
		else:
			assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
			assert_bool(dt.converting).is_true()
			assert_float(dt.rpm).is_greater(2400.0)
			assert_float(2400.0 / dt.rpm).is_greater_equal(TorqueConverter.COUPLING_POINT)


func test_a_converter_body_shifts_on_its_gearbox_clutch_at_the_rating() -> void:
	# Locked in D1 at 3400 rpm on road-held wheels, then D2: the shift slips at the rating (the
	# gearbox's on-coming clutch), never through the converter law, and the crank's inertia sets a
	# drop of several ticks onto the new gear, where the lock-up holds.
	var spec := _converter_spec()
	spec.shift_cut_s = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var omega := 3400.0 / DrivetrainScript.RADS_TO_RPM / 12.0
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(omega), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	var sync2 := DrivetrainScript.wheel_engine_rpm(spec, omega, 2)
	var ticks := 0
	while dt.rpm > sync2 + 1e-6 and ticks < 60:
		var t := _tick(dt, 1.0, LumpedWheel.new(omega), 2)
		ticks += 1
		assert_bool(dt.converting).is_false()
		assert_float(t).is_less_equal(DrivetrainScript.clutch_rating(spec) * 8.0 * 0.9 + 1e-6)
	assert_int(ticks).is_greater_equal(3)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)


func test_abs_releases_a_converter_lock_up_without_opening_it() -> void:
	var spec := _converter_spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 60:
		_tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	dt.abs_release = true
	_tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.SLIPPING)
	assert_bool(dt.converting).is_true()


func test_engagement_ends_on_slip_never_a_timer() -> void:
	# A free pair of wheels (2.4 kg·m²) pulled away floored: the coupling slips, landing the crank
	# on its line, until the wheel side comes up to it; it locks that tick and not before.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var wheel := LumpedWheel.new(0.0, 2.4)
	var locked_at := -1
	for i in 240:
		_tick(dt, 1.0, wheel, 1)
		var wheel_rpm := DrivetrainScript.wheel_engine_rpm(spec, wheel.omega, 1)
		if dt.coupling_state == DrivetrainScript.CouplingState.LOCKED:
			locked_at = i
			# The two sides met: the crank turns with the wheels.
			assert_float(dt.rpm).is_equal_approx(wheel_rpm, 1e-6)
			break
		# Until then the two sides stay apart.
		assert_float(dt.rpm).is_greater(wheel_rpm + 1e-3)
	assert_int(locked_at).is_greater(0)


func test_an_upshift_drops_the_rpm_through_slip_over_several_ticks() -> void:
	# Locked in D1 at 3400 rpm on a heavy (road-held) wheel, then D2: the coupling slips at its rating
	# and the crank's inertia sets the drop, never one tick.
	var spec := _spec()
	spec.shift_cut_s = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var omega := 3400.0 / DrivetrainScript.RADS_TO_RPM / 12.0
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(omega), 1)
	var sync2 := DrivetrainScript.wheel_engine_rpm(spec, omega, 2)
	var ticks := 0
	var prev := dt.rpm
	while dt.rpm > sync2 + 1e-6 and ticks < 60:
		var t := _tick(dt, 1.0, LumpedWheel.new(omega), 2)
		ticks += 1
		assert_float(dt.rpm).is_less(prev)
		prev = dt.rpm
		# The drop pushes the wheels: the inertia's torque, held to the rating through the ratio.
		assert_float(t).is_less_equal(DrivetrainScript.clutch_rating(spec) * 8.0 * 0.9 + 1e-6)
	assert_int(ticks).is_greater_equal(3)
	assert_float(dt.rpm).is_equal_approx(sync2, 1e-6)


func test_the_handover_rate_spans_the_inertia_phase_and_is_the_rating_at_zero() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.handover_rate(spec, 100.0)).is_equal(INF)
	spec.shift_handover_s = 0.25
	assert_float(DrivetrainScript.handover_rate(spec, 100.0)).is_equal_approx(400.0, 1e-4)
	assert_float(DrivetrainScript.handover_rate(spec, -100.0)).is_equal_approx(400.0, 1e-4)


## Locked in D1 at 3400 rpm on road-held wheels, floored with no cut, then D2 with a 0.25 s inertia
## phase: the crank comes down to the new gear at an even rate, never through the converter law, and
## the clutch closes on the new gear when the phase is done. `check(dt, rpm_before, rate)` judges each
## tick of the phase. Returns the phase's ticks.
func _hand_over(spec: VehicleSpecScript, check: Callable) -> int:
	spec.shift_handover_s = 0.25
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var omega := 3400.0 / DrivetrainScript.RADS_TO_RPM / 12.0
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(omega), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	var sync2 := DrivetrainScript.wheel_engine_rpm(spec, omega, 2)
	var rate := DrivetrainScript.handover_rate(spec, (dt.rpm - sync2) / DrivetrainScript.RADS_TO_RPM)
	var step_rpm := rate * TICK * DrivetrainScript.RADS_TO_RPM
	var ticks := 0
	while ticks == 0 or dt.coupling_state != DrivetrainScript.CouplingState.LOCKED and ticks < 60:
		var was := dt.rpm
		_tick(dt, 1.0, LumpedWheel.new(omega), 2)
		ticks += 1
		assert_bool(dt.converting).is_false()
		if dt.coupling_state != DrivetrainScript.CouplingState.LOCKED:
			assert_float(was - dt.rpm).is_equal_approx(step_rpm, 1e-3)
			assert_float(dt.coupling_torque).is_less(DrivetrainScript.clutch_rating(spec))
			check.call(dt, was, rate)
	assert_float(dt.rpm).is_equal_approx(sync2, 1e-6)
	return ticks


func test_an_upshift_hands_over_the_engines_torque_plus_the_cranks_inertia() -> void:
	# A clutch body (an AMT, a powershift): the oncoming clutch carries the engine's delivered torque
	# plus J x the rate, under the 450 N·m rating.
	var spec := _spec()
	var ticks := _hand_over(spec, func(dt: DrivetrainScript, was: float, rate: float) -> void:
		var law := DrivetrainScript.engine_torque(spec, was) + spec.engine_inertia * rate
		assert_float(dt.coupling_torque).is_equal_approx(law, 0.05 * law)
		assert_float(dt.applied_throttle).is_equal(1.0))
	assert_int(ticks).is_between(15, 16)


func test_a_converter_automatic_reduces_the_engine_so_the_shift_passes_the_drivers_torque() -> void:
	# A converter automatic's TCU: through the inertia phase the engine is fuelled down so the clutch
	# passes what the pedal asks (the curve, floored), neither the inertia's surge nor a hole, and the
	# reduction is the delivered fuel telemetry reads.
	var spec := _converter_spec()
	var ticks := _hand_over(spec, func(dt: DrivetrainScript, was: float, _rate: float) -> void:
		var demand := DrivetrainScript.engine_torque(spec, was)
		assert_float(dt.coupling_torque).is_equal_approx(demand, 1e-3 * demand)
		assert_float(dt.applied_throttle).is_greater(0.0)
		assert_float(dt.applied_throttle).is_less(1.0))
	assert_int(ticks).is_between(15, 16)


func test_the_handover_fuel_lands_the_crank_passing_the_demand_within_the_pedal() -> void:
	# pred(f) = 100 + 10 f rad/s, landing on 104 while passing 20 N·m through compliance 0.1: f 0.6.
	assert_float(DrivetrainScript.handover_fuel(100.0, 10.0, 104.0, 20.0, 0.1, 1.0)) \
			.is_equal_approx(0.6, 1e-6)
	# Never past the pedal's fuel, never under none (the clutch takes the surplus there).
	assert_float(DrivetrainScript.handover_fuel(100.0, 10.0, 120.0, 20.0, 0.1, 0.8)).is_equal(0.8)
	assert_float(DrivetrainScript.handover_fuel(100.0, 10.0, 90.0, 20.0, 0.1, 1.0)).is_equal(0.0)
	# A lifted pedal's demand is motoring: the clutch passes none of it.
	assert_float(DrivetrainScript.handover_fuel(100.0, 10.0, 104.0, -5.0, 0.1, 1.0)) \
			.is_equal_approx(0.4, 1e-6)
	assert_float(DrivetrainScript.handover_fuel(100.0, 0.0, 104.0, 20.0, 0.1, 1.0)).is_equal(0.0)


func test_a_downshift_blips_the_crank_up_to_the_wheels() -> void:
	# Locked in D2 at 2000 rpm, then D1 (3000 rpm synchronous): the controller fuels the crank up
	# while the clutch slips, so it never drags the wheels backward for the whole rise.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var omega := 2000.0 / DrivetrainScript.RADS_TO_RPM / 8.0
	for i in 60:
		_tick(dt, 0.0, LumpedWheel.new(omega), 2)
	var sync := DrivetrainScript.wheel_engine_rpm(spec, omega, 1)
	# Never more drag on the wheels than the locked engine's own braking at the new gear.
	var floor_t := DrivetrainScript.overrun_torque(spec, sync, 0.0, 1) - 1e-6
	assert_float(_tick(dt, 0.0, LumpedWheel.new(omega), 1)).is_greater_equal(floor_t)
	assert_float(dt.applied_throttle).is_greater(0.0)
	for i in 30:
		assert_float(_tick(dt, 0.0, LumpedWheel.new(omega), 1)).is_greater_equal(floor_t)
	assert_float(dt.rpm).is_equal_approx(sync, 1e-6)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)


func test_the_driveline_loss_applies_by_the_torque_s_direction() -> void:
	# Locked and steady, the wheels see today's laws exactly: the curve times the ratio times the
	# efficiency in drive, the motoring torque times the ratio OVER the efficiency in overrun.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var omega := 30.0
	var drive_dt: DrivetrainScript = DrivetrainScript.new(spec)
	var over_dt: DrivetrainScript = DrivetrainScript.new(spec)
	var drive := 0.0
	var over := 0.0
	for i in 120:
		drive = _tick(drive_dt, 1.0, LumpedWheel.new(omega), 1)
		over = _tick(over_dt, 0.0, LumpedWheel.new(omega), 1)
	var at_rpm := DrivetrainScript.wheel_engine_rpm(spec, omega, 1)
	assert_float(drive).is_equal_approx(DrivetrainScript.wheel_torque(spec, at_rpm, 1.0, 1), 1e-6)
	assert_float(over).is_equal_approx(DrivetrainScript.overrun_torque(spec, at_rpm, 0.0, 1), 1e-6)


func test_abs_opens_the_coupling() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 60:
		_tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	dt.abs_release = true
	var t := _tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.OPEN)
	assert_float(t).is_equal(0.0)


func test_drag_torque_control_fuels_the_crank_to_zero_net_motoring() -> void:
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 60:
		_tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	dt.drag_control = true
	var t := _tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_float(dt.applied_throttle).is_equal_approx(DrivetrainScript.drag_fuel(spec, dt.rpm), 1e-9)
	assert_float(t).is_equal_approx(0.0, 1e-6)


func test_the_controller_opens_stops_and_roll_backs_and_slips_every_shift() -> void:
	var spec := _spec()
	var open := DrivetrainScript.CouplingState.OPEN
	var slip := DrivetrainScript.CouplingState.SLIPPING
	var locked := DrivetrainScript.CouplingState.LOCKED
	var step := func(state: int, from: int, to: int, pedal: float, crank: float, sync: float,
			running := true, abs_held := false) -> int:
		return DrivetrainScript.coupling_step(spec, state, from, to, pedal, crank, sync, running,
				abs_held)
	assert_int(step.call(locked, 1, 1, 0.5, 2000.0, 2000.0, false)).is_equal(open)  # key off
	assert_int(step.call(locked, 1, GEAR_N, 0.5, 2000.0, 2000.0)).is_equal(open)
	assert_int(step.call(locked, 1, 1, 0.5, 2000.0, 2000.0, true, true)).is_equal(open)  # ABS
	assert_int(step.call(locked, 1, GEAR_R, 0.5, 2000.0, 2000.0)).is_equal(open)  # direction
	assert_int(step.call(locked, 1, 1, 0.0, 800.0, 500.0)).is_equal(open)  # stopping, pedal up
	assert_int(step.call(locked, 1, 1, 0.0, 800.0, -200.0)).is_equal(open)  # rolled back
	assert_int(step.call(open, GEAR_N, 1, 0.3, 800.0, 0.0)).is_equal(slip)  # pull-away
	assert_int(step.call(open, 1, 1, 0.0, 800.0, 2000.0)).is_equal(slip)  # re-engage, rolling
	assert_int(step.call(locked, 1, 2, 0.5, 3000.0, 2000.0)).is_equal(slip)  # shift
	assert_int(step.call(locked, 1, 1, 0.5, 700.0, 600.0)).is_equal(slip)  # anti-stall
	assert_int(step.call(locked, 1, 1, 0.0, 2000.0, 2000.0)).is_equal(locked)
	assert_int(step.call(slip, 1, 1, 1.0, 1600.0, 0.0)).is_equal(slip)
	# A converter never opens in gear: a stop, a roll-back or ABS lets its lock-up go, and it slips
	# (creep); only the key, N or P and a direction change open it.
	var conv := _converter_spec()
	var cstep := func(state: int, from: int, to: int, pedal: float, crank: float, sync: float,
			running := true, abs_held := false, braking := false) -> int:
		return DrivetrainScript.coupling_step(conv, state, from, to, pedal, crank, sync, running,
				abs_held, braking)
	assert_int(cstep.call(locked, 1, 1, 0.5, 2000.0, 2000.0, false)).is_equal(open)  # key off
	assert_int(cstep.call(locked, 1, GEAR_N, 0.5, 2000.0, 2000.0)).is_equal(open)
	assert_int(cstep.call(locked, 1, GEAR_R, 0.5, 2000.0, 2000.0)).is_equal(open)  # direction
	assert_int(cstep.call(locked, 1, 1, 0.5, 2000.0, 2000.0, true, true)).is_equal(slip)  # ABS
	assert_int(cstep.call(locked, 1, 1, 0.0, 2000.0, 2000.0, true, false, true)) \
			.is_equal(slip)  # the foot brake
	assert_int(cstep.call(locked, 1, 1, 0.0, 800.0, 500.0)).is_equal(slip)  # stopping, pedal up
	assert_int(cstep.call(slip, 1, 1, 0.0, 800.0, 0.0)).is_equal(slip)  # held at a stop: creep
	assert_int(cstep.call(slip, 1, 1, 0.0, 800.0, -200.0)).is_equal(slip)  # rolled back
	assert_int(cstep.call(open, GEAR_N, 1, 0.0, 800.0, 0.0)).is_equal(slip)  # into D
	assert_int(cstep.call(locked, 1, 2, 0.5, 3000.0, 2000.0)).is_equal(slip)  # shift
	assert_int(cstep.call(locked, 1, 1, 1.0, 1100.0, 1100.0)).is_equal(slip)  # under the line
	assert_int(cstep.call(locked, 1, 1, 0.0, 2000.0, 2000.0)).is_equal(locked)
	conv.lockup_gear = 2
	assert_int(cstep.call(locked, 1, 1, 0.0, 2000.0, 2000.0)).is_equal(slip)  # under its gear


func test_a_held_vehicle_does_not_upshift_however_long_it_is_revved() -> void:
	# Auto-shift judges rpm computed from ROAD speed, never `dt.rpm`, so a stall rev cannot walk
	# the box up the gears while the vehicle stands still on the brake.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 1.0, LumpedWheel.new(), 1, true)
	assert_int(dt.gear_byte).is_equal(1)


func test_a_stall_rev_never_trips_the_limiter() -> void:
	# The converter line sits far under the redline: full pedal against a held wheel is fuel the
	# engine actually gets.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		_tick(dt, 1.0, LumpedWheel.new(), 1)
	assert_float(dt.applied_throttle).is_equal(1.0)


func test_a_machine_that_drives_no_wheels_keeps_the_rigid_crank() -> void:
	# Boat and drone carry no ground_drive; the plane's wheels are undriven. All three keep
	# the crank the wheels alone turn, so a held one sits at idle however hard it is revved.
	var no_gd := _spec()
	no_gd.ground_drive = null
	var undriven := _spec()
	undriven.ground_drive.driven_front = false
	undriven.ground_drive.driven_rear = false
	for spec: VehicleSpecScript in [no_gd, undriven]:
		assert_bool(DrivetrainScript.drives_wheels(spec)).is_false()
		assert_float(DrivetrainScript.converter_free_rpm(spec, 1.0)).is_equal(spec.idle_rpm)
		var dt: DrivetrainScript = DrivetrainScript.new(spec)
		for i in 120:
			dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, 1, false)
		assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 0.001)


# --- road-speed governor ------------------------------------------------------------

func test_governor_is_absent_unless_a_limit_is_declared() -> void:
	var spec := _spec()   # speed_limit_kmh defaults to 0
	assert_float(DrivetrainScript.governor_scale(spec, 0.0)).is_equal(1.0)
	assert_float(DrivetrainScript.governor_scale(spec, 200.0)).is_equal(1.0)


func test_governor_fades_across_the_band_and_shuts_at_the_limit() -> void:
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var limit := 90.0 / 3.6                        # 25 m/s
	var band: float = DrivetrainScript.GOVERNOR_BAND
	# Wide open well below the limit, shut at and above it, half way at half a band below.
	assert_float(DrivetrainScript.governor_scale(spec, limit - 10.0 * band)).is_equal(1.0)
	assert_float(DrivetrainScript.governor_scale(spec, limit - band * 0.5)).is_equal_approx(0.5, 1e-4)
	assert_float(DrivetrainScript.governor_scale(spec, limit)).is_equal(0.0)
	assert_float(DrivetrainScript.governor_scale(spec, limit + 50.0)).is_equal(0.0)


func test_governor_is_unsigned_so_it_limits_reverse_too() -> void:
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var limit := 90.0 / 3.6
	assert_float(DrivetrainScript.governor_scale(spec, -limit)).is_equal(0.0)
	assert_float(DrivetrainScript.governor_scale(spec, -limit + 0.5 * DrivetrainScript.GOVERNOR_BAND)) \
			.is_equal_approx(0.5, 1e-4)


func test_a_runtime_cap_governs_only_where_it_is_the_lower_limit() -> void:
	var spec := _spec()
	var cap := 5.0
	var cap_ms := cap / 3.6
	# Ungoverned spec: the cap alone governs, and 0 means no cap.
	assert_float(DrivetrainScript.governor_scale(spec, cap_ms, cap)).is_equal(0.0)
	assert_float(DrivetrainScript.governor_scale(spec, cap_ms, 0.0)).is_equal(1.0)
	# Governed spec: the lower of the two wins, either way round.
	spec.speed_limit_kmh = 90.0
	assert_float(DrivetrainScript.governor_scale(spec, cap_ms, cap)).is_equal(0.0)
	# A cap above the spec's limit leaves the spec's limit governing: shut at 90, not at 200.
	assert_float(DrivetrainScript.governor_scale(spec, 90.0 / 3.6, 200.0)).is_equal(0.0)


func test_process_cuts_the_throttle_at_the_runtime_cap() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.speed_cap_kmh = 5.0
	dt.process(1.0 / 60.0, 1.0, 10.0, 5.0 / 3.6, 1, false)
	assert_float(dt.applied_throttle).is_equal(0.0)
	dt.speed_cap_kmh = 0.0
	dt.process(1.0 / 60.0, 1.0, 10.0, 5.0 / 3.6, 1, false)
	assert_float(dt.applied_throttle).is_equal(1.0)


func test_process_publishes_the_governed_throttle_not_the_pedal() -> void:
	# Telemetry (engine_load, fuel, coolant) reads governed throttle, not pedal.
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var free := 0.0
	for i in 60:
		free = _tick(dt, 1.0, LumpedWheel.new(20.0), 1, false, 5.0)
	assert_float(dt.applied_throttle).is_equal(1.0)
	assert_float(free).is_greater(0.0)
	# Same full pedal, now sitting on the limit: no throttle through, no drive torque.
	var governed := _tick(dt, 1.0, LumpedWheel.new(20.0), 1, false, 90.0 / 3.6)
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_float(governed).is_equal_approx(0.0, 1e-6)


func test_a_governed_engine_still_turns_with_the_wheels() -> void:
	# rpm follows the ROAD, not the pedal — a limited truck at 90 km/h is not idling, it is
	# turning at whatever the gearing makes it turn at with the fuel cut.
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 240:
		_tick(dt, 1.0, LumpedWheel.new(25.0), 1, false, 90.0 / 3.6)
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_float(dt.rpm).is_equal_approx(DrivetrainScript.wheel_engine_rpm(spec, 25.0, 1), 1e-6)


# --- overrun (engine braking) ----------------------------------------------

func test_overrun_is_absent_unless_declared() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 0.0, 1)).is_equal(0.0)


func test_overrun_is_zero_at_full_fuel_in_neutral_and_at_idle_without_friction() -> void:
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 1.0, 1)).is_equal(0.0)
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 0.0, GEAR_N)).is_equal(0.0)
	assert_float(DrivetrainScript.overrun_torque(spec, 800.0, 0.0, 1)).is_equal(0.0)


func test_the_motoring_law_runs_from_its_friction_at_idle_to_its_redline_anchor() -> void:
	# Friction 0.05 of the 300 peak (15 N·m) at and below idle, rising linearly to 0.1 (30 N·m) at
	# redline; the axle sees it through the gear and the efficiency, as every overrun does.
	var spec := _spec()
	spec.engine_friction_frac = 0.05
	spec.engine_brake_frac = 0.1
	assert_float(DrivetrainScript.motoring_torque(spec, 800.0)).is_equal_approx(-15.0, 1e-9)
	assert_float(DrivetrainScript.motoring_torque(spec, 400.0)).is_equal_approx(-15.0, 1e-9)
	assert_float(DrivetrainScript.motoring_torque(spec, 2400.0)).is_equal_approx(-22.5, 1e-9)
	assert_float(DrivetrainScript.motoring_torque(spec, 4000.0)).is_equal_approx(-30.0, 1e-9)
	assert_float(DrivetrainScript.overrun_torque(spec, 800.0, 0.0, 1)) \
			.is_equal_approx(-15.0 * 12.0 / 0.9, 1e-6)
	assert_float(DrivetrainScript.overrun_torque(spec, 800.0, 0.0, GEAR_N)).is_equal(0.0)


func test_overrun_signed_against_the_gear_and_scaled_by_ratio_and_rpm() -> void:
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	# Peak 300, frac 0.1 = 30 Nm at the crank at redline; gear 1 ratio 3*4 = 12, / eff 0.9.
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 0.0, 1)) \
			.is_equal_approx(-30.0 * 12.0 / 0.9, 1e-6)
	# Halfway idle->redline (2400) is half the torque.
	assert_float(DrivetrainScript.overrun_torque(spec, 2400.0, 0.0, 1)) \
			.is_equal_approx(-15.0 * 12.0 / 0.9, 1e-6)
	# Reverse rolls the other way, so overrun there is positive.
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 0.0, GEAR_R)) \
			.is_equal_approx(30.0 * 3.2 * 4.0 / 0.9, 1e-6)


func test_part_fuel_blends_the_curve_with_the_motoring_torque() -> void:
	# T = f * T_wot + (1 - f) * T_motoring: no edge between 1 % pedal and none.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var full_motoring := DrivetrainScript.overrun_torque(spec, 4000.0, 0.0, 1)
	assert_float(DrivetrainScript.overrun_torque(spec, 4000.0, 0.25, 1)) \
			.is_equal_approx(0.75 * full_motoring, 1e-6)
	var net := func(f: float) -> float:
		return DrivetrainScript.wheel_torque(spec, 4000.0, f, 1) \
				+ DrivetrainScript.overrun_torque(spec, 4000.0, f, 1)
	# 1 % fuel at redline is net engine braking, 1 % of the way from the lifted pedal to the curve.
	assert_float(net.call(0.01)).is_less(0.0)
	assert_float(net.call(0.01) - net.call(0.0)) \
			.is_equal_approx(0.01 * (net.call(1.0) - net.call(0.0)), 1e-4)
	# Full fuel is the curve alone, so a drag-bound top speed does not move.
	assert_float(net.call(1.0)).is_equal(DrivetrainScript.wheel_torque(spec, 4000.0, 1.0, 1))


func test_process_on_overrun_returns_negative_torque_with_no_load() -> void:
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# Enter D at speed (wheel omega 30 rad/s -> ~3440 rpm, under the redline), lift off.
	var torque := 0.0
	for i in 120:
		torque = _tick(dt, 0.0, LumpedWheel.new(30.0), 1)
	assert_float(torque).is_less(0.0)
	assert_float(dt.applied_throttle).is_equal(0.0)
	# Full pedal is the full-throttle torque alone.
	var at_rpm := dt.rpm
	var driven := _tick(dt, 1.0, LumpedWheel.new(30.0), 1)
	assert_float(driven).is_equal_approx(
			DrivetrainScript.wheel_torque(spec, at_rpm, 1.0, dt.gear_byte), 1e-6)


func test_wheels_turning_against_the_gear_get_no_engine_braking_and_no_limiter_cut() -> void:
	# A wheel spun backwards in D (rolled back in a ditch, say) is no overspeed: the pedal fuels the
	# engine and drives it forward again. Lifted, the engine does not brake it further backwards.
	# Judged on |rpm| with the overrun signed against the gear, the two would latch it spinning back.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	for byte: int in [1, GEAR_R]:
		var dt: DrivetrainScript = DrivetrainScript.new(spec)
		var against := -40.0 * signf(DrivetrainScript.ratio_for_byte(spec, byte))
		var torque := 0.0
		for i in 60:
			torque = _tick(dt, 1.0, LumpedWheel.new(against), byte, false, 0.0)
		assert_float(dt.applied_throttle).override_failure_message(
				"byte %d: the limiter cut a wheel turning against the gear" % byte).is_equal(1.0)
		assert_float(torque * signf(against)).is_less(0.0)
		for i in 60:
			torque = _tick(dt, 0.0, LumpedWheel.new(against), byte, false, 0.0)
		assert_float(torque).override_failure_message(
				"byte %d: engine braking drove a wheel further against the gear" % byte).is_equal(0.0)


func test_a_tripped_limiter_brakes_with_the_pedal_down() -> void:
	# The limiter is a fuel cut, and a cut engine is motored: a lifted driven wheel past the
	# redline slows by itself instead of latching the cut.
	var spec := _spec()
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 60:
		torque = _tick(dt, 1.0, LumpedWheel.new(40.0), 1)
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_float(torque).is_less(0.0)


func test_a_governed_engine_at_its_limit_brakes_with_the_pedal_down() -> void:
	# Pedal down on a descent at the limit must not freewheel faster than pedal up: both are a
	# fuel cut, so both are the same engine braking.
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	spec.engine_brake_frac = 0.1
	var down: DrivetrainScript = DrivetrainScript.new(spec)
	var up: DrivetrainScript = DrivetrainScript.new(spec)
	var t_down := 0.0
	var t_up := 0.0
	for i in 120:
		t_down = _tick(down, 1.0, LumpedWheel.new(30.0), 1, false, 90.0 / 3.6)
		t_up = _tick(up, 0.0, LumpedWheel.new(30.0), 1, false, 90.0 / 3.6)
	assert_float(down.applied_throttle).is_equal(0.0)
	assert_float(t_down).is_less(0.0)
	assert_float(t_down).is_equal_approx(t_up, 1e-6)


func test_the_shift_cut_is_engine_braking_once_the_rev_drop_is_done() -> void:
	# An upshift slips the crank down to the new gear first (its inertia pushes the wheels); locked
	# again inside the cut, the unfuelled engine brakes them.
	var spec := _spec()
	spec.shift_cut_s = 0.2
	spec.engine_brake_frac = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 1)
	var torque := 0.0
	for i in 8:
		torque = _tick(dt, 1.0, LumpedWheel.new(30.0), 2)
	assert_bool(dt.shift_cut_active()).is_true()
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	assert_float(torque).is_less(0.0)


# --- shift cut ---------------------------------------------------------------

func test_shift_cut_ticks_rounds_up_and_is_zero_without_a_cut() -> void:
	assert_int(DrivetrainScript.shift_cut_ticks(0.0, 1.0 / 60.0)).is_equal(0)
	assert_int(DrivetrainScript.shift_cut_ticks(0.1, 1.0 / 60.0)).is_equal(6)
	assert_int(DrivetrainScript.shift_cut_ticks(0.15, 1.0 / 60.0)).is_equal(9)


func test_torque_restore_is_one_without_a_ramp() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.torque_restore_step(spec, 0.0, true, 1.0 / 60.0)).is_equal(1.0)
	assert_float(DrivetrainScript.torque_restore_step(spec, 0.3, false, 1.0 / 60.0)).is_equal(1.0)


func test_torque_restore_ramps_back_over_its_time_after_the_cut() -> void:
	var spec := _spec()
	spec.shift_torque_ramp_s = 0.3
	var delta := 1.0 / 60.0
	var c := DrivetrainScript.torque_restore_step(spec, 1.0, true, delta)
	assert_float(c).is_equal(0.0)
	for i in 17:
		c = DrivetrainScript.torque_restore_step(spec, c, false, delta)
	assert_float(c).is_less(1.0)
	c = DrivetrainScript.torque_restore_step(spec, c, false, delta)
	assert_float(c).is_equal_approx(1.0, 1e-5)
	# A new cut mid-ramp starts it over.
	c = DrivetrainScript.torque_restore_step(spec, 0.5, true, delta)
	assert_float(c).is_equal(0.0)


func test_the_restore_ramp_only_withholds_fuel_after_a_shift_cut() -> void:
	# Off (0) the fuel returns in one tick; on, the delivered fuel climbs back under the pedal.
	var spec := _spec()
	spec.shift_cut_s = 0.1
	spec.shift_torque_ramp_s = 0.3
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 1)
	assert_float(dt.applied_throttle).is_equal(1.0)
	for i in 6:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 2)
	assert_float(dt.applied_throttle).is_equal(0.0)
	var last := 0.0
	for i in 18:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 2)
		assert_float(dt.applied_throttle).is_greater_equal(last)
		assert_float(dt.applied_throttle).is_less_equal(1.0)
		last = dt.applied_throttle
	assert_float(last).is_equal_approx(1.0, 1e-5)


func test_is_shift_needs_both_sides_engaged() -> void:
	assert_bool(DrivetrainScript.is_shift(1, 2)).is_true()
	assert_bool(DrivetrainScript.is_shift(1, GEAR_R)).is_true()
	assert_bool(DrivetrainScript.is_shift(GEAR_N, 1)).is_false()
	assert_bool(DrivetrainScript.is_shift(1, GEAR_N)).is_false()
	assert_bool(DrivetrainScript.is_shift(3, 3)).is_false()


func test_exact_byte_change_cuts_throttle_for_the_declared_ticks() -> void:
	var spec := _spec()
	spec.shift_cut_s = 0.1  # 6 ticks at 60 Hz
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	_tick(dt, 1.0, LumpedWheel.new(30.0), 1)
	assert_float(dt.applied_throttle).is_equal(1.0)  # N->D is a selection, not a shift
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 1)
	for i in 6:
		_tick(dt, 1.0, LumpedWheel.new(30.0), 2)
		assert_bool(dt.shift_cut_active() or i == 5) \
				.override_failure_message("cut ended early at tick %d" % i).is_true()
		assert_float(dt.applied_throttle).is_equal(0.0)
	_tick(dt, 1.0, LumpedWheel.new(30.0), 2)
	assert_bool(dt.shift_cut_active()).is_false()
	assert_float(dt.applied_throttle).is_equal(1.0)


func test_no_cut_declared_means_no_interruption() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(1.0 / 60.0, 1.0, 30.0, 10.0, 1, false)
	dt.process(1.0 / 60.0, 1.0, 30.0, 10.0, 2, false)
	assert_float(dt.applied_throttle).is_equal(1.0)


func test_no_launch_engagement_declared_has_the_whole_rating_on_the_first_tick() -> void:
	var dt: DrivetrainScript = DrivetrainScript.new(_spec())
	dt.process(TICK, 1.0, 0.0, 0.0, 1, true)
	assert_float(dt.ramp).is_equal(1.0)


func test_the_launch_ramp_builds_the_coupling_rating_over_the_declared_time() -> void:
	# A powershift's pressure ramp: what the controller may command climbs from nothing to the
	# whole rating over `launch_engage_s`; the pedal's fuel is untouched.
	var spec := _spec()
	spec.launch_engage_s = 0.5  # 30 ticks at 60 Hz
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	_tick(dt, 1.0, LumpedWheel.new(), 1, true)
	assert_float(dt.ramp).is_equal_approx(1.0 / 30.0, 1e-5)
	for i in 29:
		_tick(dt, 1.0, LumpedWheel.new(), 1, true)
		assert_float(dt.clutch).is_less_equal(dt.ramp + 1e-9)
	assert_float(dt.ramp).is_equal_approx(1.0, 1e-5)
	assert_float(dt.applied_throttle).is_equal(1.0)


func test_the_launch_ramp_restarts_when_stopped_with_the_pedal_up_and_holds_while_rolling() -> void:
	var spec := _spec()
	spec.launch_engage_s = 0.5
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.ramp = 1.0
	dt.process(TICK, 0.0, 30.0, 10.0, 1, false)  # coasting: stays closed
	assert_float(dt.ramp).is_equal(1.0)
	dt.process(TICK, 0.0, 0.0, 0.0, 1, false)  # stopped, pedal up: restarts
	assert_float(dt.ramp).is_equal(0.0)


func test_the_launch_ramp_restarts_in_neutral_and_on_a_direction_change() -> void:
	var spec := _spec()
	spec.launch_engage_s = 0.5
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(TICK, 1.0, 30.0, 10.0, 1, false)
	dt.ramp = 1.0
	dt.process(TICK, 1.0, 30.0, 10.0, GEAR_R, false)
	assert_float(dt.ramp).is_equal(0.0)
	dt.ramp = 1.0
	dt.process(TICK, 1.0, 30.0, 10.0, GEAR_N, false)
	assert_float(dt.ramp).is_equal(0.0)
	# An upshift is not a pull-away.
	dt.process(TICK, 1.0, 30.0, 10.0, 1, false)
	dt.ramp = 1.0
	dt.process(TICK, 1.0, 30.0, 10.0, 2, false)
	assert_float(dt.ramp).is_equal(1.0)


func test_engagement_ends_on_slip_never_on_the_ramps_timer() -> void:
	# A pull-away still slips once its ramp has closed, until the two sides meet: the clutch locks
	# on slip, and the box stays in the gear the road speed gives it (D1) throughout.
	var spec := _spec()
	spec.launch_engage_s = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var wheel := LumpedWheel.new(0.0, 40.0)
	var slipped_past_the_ramp := false
	for i in 600:
		_tick(dt, 1.0, wheel, 1, true)
		if dt.coupling_state == DrivetrainScript.CouplingState.LOCKED:
			break
		slipped_past_the_ramp = slipped_past_the_ramp or dt.ramp >= 1.0
		assert_int(dt.gear_byte).is_equal(1)
	assert_bool(slipped_past_the_ramp).is_true()
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)


func test_auto_upshift_latches_the_cut_once() -> void:
	var spec := _spec()
	spec.shift_cut_s = 0.1
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, 1, true)
	assert_int(dt.gear_byte).is_equal(1)
	# Fast enough in gear 1 that road rpm is past shift_up: it upshifts this tick and cuts.
	dt.process(1.0 / 60.0, 1.0, 60.0, 20.0, 1, true)
	assert_int(dt.gear_byte).is_equal(2)
	assert_bool(dt.shift_cut_active()).is_true()


# --- the shift policy's state (ShiftPolicy; its pure functions: test_shift_policy) ------------

## The road speed (m/s) whose rpm through `byte` is `rpm`, on `dt`'s gear-selection radius.
static func _road_speed_for(dt: DrivetrainScript, byte: int, rpm: float) -> float:
	return rpm / DrivetrainScript.RADS_TO_RPM / DrivetrainScript.ratio_for_byte(dt.spec, byte) \
			* dt.road_radius


## One auto tick at road speed `v`, the wheels turning with it.
static func _auto_tick(dt: DrivetrainScript, pedal: float, v: float, req: int) -> void:
	dt.process(TICK, pedal, v / dt.road_radius, v, req, true)


func test_the_dwell_counts_from_the_last_gear_change() -> void:
	# A lift upshift is due at once (2500 rpm in D1, light up 2000), but the box entered D1 this
	# tick: it waits out the 0.5 s dwell, then takes D2 (1667 rpm there, clear of both lines).
	var spec := _spec()
	spec.shift_up_light_rpm = 2000.0
	spec.shift_dwell_s = 0.5
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var v := _road_speed_for(dt, 1, 2500.0)
	for i in 25:
		_auto_tick(dt, 0.0, v, 1)
	assert_int(dt.gear_byte).is_equal(1)
	for i in 15:
		_auto_tick(dt, 0.0, v, 1)
	assert_int(dt.gear_byte).is_equal(2)


func test_a_pedal_stab_kicks_down_once_the_dwell_lets_it() -> void:
	# Entered in D5 at 1600 rpm, the pedal stabbed to 1 on the next tick: the kickdown stays armed
	# through the 0.5 s dwell, then takes D3 (2400 rpm, under 0.85 x 3500) in one shift. The pedal
	# held there never re-arms it.
	var spec := _spec()
	spec.kickdown_pedal = 0.9
	spec.shift_dwell_s = 0.5
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var v := _road_speed_for(dt, 5, 1600.0)
	_auto_tick(dt, 0.0, v, 5)
	assert_int(dt.gear_byte).is_equal(5)
	for i in 10:
		_auto_tick(dt, 1.0, v, 5)
	assert_int(dt.gear_byte).is_equal(5)
	for i in 30:
		_auto_tick(dt, 1.0, v, 5)
	assert_int(dt.gear_byte).is_equal(3)
	for i in 60:
		_auto_tick(dt, 1.0, v, 5)
	assert_int(dt.gear_byte).is_equal(3)


func test_the_policy_reads_the_pedal_never_the_delivered_fuel() -> void:
	# On the rigid crank the shift cut zeroes the delivered fuel. Read as a lift, that 0 would upshift
	# D2 at 2400 rpm (the lift's point there is 1.1 x 1500 x 1.33 = 2200); the pedal is still
	# floored, so the box holds D2.
	var spec := _spec()
	spec.ground_drive = null
	spec.shift_cut_s = 0.5
	spec.shift_up_light_rpm = 2000.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	_auto_tick(dt, 1.0, 0.0, 1)
	_auto_tick(dt, 1.0, _road_speed_for(dt, 1, 3600.0), 1)
	assert_int(dt.gear_byte).is_equal(2)
	for i in 10:
		_auto_tick(dt, 1.0, _road_speed_for(dt, 1, 3600.0), 1)
	assert_bool(dt.shift_cut_active()).is_true()
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_int(dt.gear_byte).is_equal(2)


func test_governed_upshift_takes_the_tallest_gear_that_still_pulls() -> void:
	# The van case: a limit that lands just below the rpm-based upshift point used to strand
	# the box a gear short, and the measure tool reported it as an unreachable ratio.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	var at_limit := 180.0 / 3.6
	var g := DrivetrainScript.governed_upshift(spec, 5, at_limit, spec.ground_drive.wheel_radius)
	assert_int(g).is_equal(spec.gear_ratios.size())


func test_governed_upshift_will_not_lug_the_engine_below_the_downshift_point() -> void:
	# A limiter low enough that top gear would drop the engine under shift_down_rpm must NOT
	# be taken — that is the guard that keeps this from bogging a slow-governed vehicle.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 12.0
	var g := DrivetrainScript.governed_upshift(spec, 1, 12.0 / 3.6, spec.ground_drive.wheel_radius)
	assert_int(g).is_less(spec.gear_ratios.size())
	assert_float(DrivetrainScript.rpm_from_wheel(spec, (12.0 / 3.6) / spec.ground_drive.wheel_radius, g)) \
			.is_greater_equal(spec.idle_rpm)


func test_a_spec_with_no_ground_drive_still_gets_a_gear_selection_scale() -> void:
	# The boat, the drone and the train walk a gearbox and publish the gear byte in `status`
	# without owning a wheel. road_radius is what lets them: with no ground drive to copy a
	# wheel_radius off, Drivetrain declares DEFAULT_ROAD_RADIUS and the shift points stand where
	# they always did. A fallback of 0 here would divide by zero on the very first tick.
	var spec := _spec()
	spec.ground_drive = null
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	assert_float(dt.road_radius).is_equal(DrivetrainScript.DEFAULT_ROAD_RADIUS)
	# And it really is the same scale a wheeled body of that radius would pick.
	var wheeled := _spec()
	wheeled.ground_drive.wheel_radius = DrivetrainScript.DEFAULT_ROAD_RADIUS
	assert_float(DrivetrainScript.new(wheeled).road_radius).is_equal(dt.road_radius)


func test_governed_upshift_reads_the_declared_radius_as_a_pure_scale() -> void:
	# road_radius is DECLARED on the Drivetrain rather than reached for on the spec, so that a
	# wheel-less body (boat, train) keeps its gearing when the wheel fields move to the ground
	# road_radius enters as ground_speed / road_radius (nowhere else); ratio IS selection scale.
	var spec := _spec()
	spec.speed_limit_kmh = 180.0
	var at_limit := 180.0 / 3.6
	var g := DrivetrainScript.governed_upshift(spec, 1, at_limit, 0.36)
	assert_int(DrivetrainScript.governed_upshift(spec, 1, at_limit / 2.0, 0.18)).is_equal(g)
	assert_int(DrivetrainScript.governed_upshift(spec, 1, at_limit * 2.0, 0.72)).is_equal(g)
	# And a Drivetrain copies it off the spec, so nothing about today's gearing moved.
	spec.ground_drive.wheel_radius = 0.36
	assert_float(DrivetrainScript.new(spec).road_radius).is_equal(0.36)


func test_governed_upshift_never_leaves_the_RAMN_drive_range() -> void:
	# 7th ratio: is_drive rejects, ratio_for_byte returns 0.0 (free-wheel). TOP_GEAR is bus number.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	spec.gear_ratios = PackedFloat32Array([4.0, 2.6, 1.8, 1.3, 1.0, 0.8, 0.65])
	var g := DrivetrainScript.governed_upshift(spec, 5, 180.0 / 3.6, spec.ground_drive.wheel_radius)
	assert_int(g).is_less_equal(DrivetrainScript.TOP_GEAR)
	assert_bool(DrivetrainScript.is_drive(g)).is_true()
	assert_float(DrivetrainScript.ratio_for_byte(spec, g)).is_not_equal(0.0)


func test_auto_shift_and_is_drive_agree_with_governed_upshift_on_top_gear() -> void:
	# All three must read TOP_GEAR (is_drive, auto_shift, governed_upshift).
	var spec := _spec()
	spec.gear_ratios = PackedFloat32Array([4.0, 2.6, 1.8, 1.3, 1.0, 0.8, 0.65])
	assert_bool(DrivetrainScript.is_drive(DrivetrainScript.TOP_GEAR)).is_true()
	assert_bool(DrivetrainScript.is_drive(DrivetrainScript.TOP_GEAR + 1)).is_false()
	# At the redline in top, auto-shift holds rather than stepping off the end of the range.
	assert_int(DrivetrainScript.auto_shift(spec, DrivetrainScript.TOP_GEAR, spec.redline_rpm)) \
			.is_equal(DrivetrainScript.TOP_GEAR)


func test_a_governed_vehicle_ends_up_in_top_gear() -> void:
	# End to end through process(): full pedal, sitting on the limit, auto box.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.gear_byte = 1
	var at_limit := 180.0 / 3.6
	for i in 60:
		_tick(dt, 1.0, LumpedWheel.new(at_limit / spec.ground_drive.wheel_radius), 1, true, at_limit)
	assert_int(dt.gear_byte).is_equal(spec.gear_ratios.size())
	assert_float(dt.applied_throttle).is_equal(0.0)


# --- peak torque --------------------------------------------------------------------

func test_peak_torque_is_the_highest_point_on_the_curve() -> void:
	# The engine-load denominator (and the garage's headline figure): the most this engine can
	# ever make, wherever on the curve that is — not the value at any particular rpm.
	assert_float(DrivetrainScript.peak_torque(_spec())).is_equal(300.0)
	var flat: VehicleSpecScript = VehicleSpecScript.new()
	flat.torque_curve = PackedVector2Array([Vector2(1000, 50), Vector2(2000, 50)])
	assert_float(DrivetrainScript.peak_torque(flat)).is_equal(50.0)
	var empty: VehicleSpecScript = VehicleSpecScript.new()
	empty.torque_curve = PackedVector2Array()
	assert_float(DrivetrainScript.peak_torque(empty)).is_equal(0.0)


# --- §6 the brake pedal ---------------------------------------------------------

func test_half_pedal_asks_the_same_deceleration_of_every_body_and_full_pedal_its_capacity() -> void:
	# WheelDrive.brake_application: anchored per body, so the feel per pedal travel is shared and only
	# the end of the travel reaches each body's own reserve.
	for cap: float in [1.0, 1.43, 2.2, 2.6]:
		assert_float(WheelDrive.brake_application(0.5, cap) * cap) \
				.override_failure_message("%.2f g of capacity: half pedal is not 0.5 g" % cap) \
				.is_equal_approx(WheelDrive.BRAKE_HALF_PEDAL_G, 1e-6)
		assert_float(WheelDrive.brake_application(1.0, cap)).is_equal(1.0)
		assert_float(WheelDrive.brake_application(0.0, cap)).is_equal(0.0)
		assert_float(WheelDrive.brake_application(2.0, cap)).is_equal(1.0)
		assert_float(WheelDrive.brake_application(-1.0, cap)).is_equal(0.0)
		var prev := 0.0
		for i in range(1, 11):
			var a := WheelDrive.brake_application(i / 10.0, cap)
			assert_float(a).is_greater(prev)
			prev = a
	# More capacity is more reserve at the end of the travel, never a harder first third.
	assert_float(WheelDrive.brake_application(0.3, 2.2) * 2.2) \
			.is_less(WheelDrive.brake_application(0.3, 1.43) * 1.43)
	# A body with no more than the anchor is linear, never regressive.
	assert_float(WheelDrive.brake_application(0.3, 0.4)).is_equal_approx(0.3, 1e-6)


# --- the launch's close, the start gear and the road load (ShiftPolicy's load rules) -----------

## A floored pull-away against a lumped wheel side, its capacity ramped over 1 s so the crank flares
## to ~3000 rpm, far over the 1600 rpm launch line, with `handover_s` for the close. Returns [the most the coupling
## carried at the crank from the tick the wheel side reached the line to the lock, the ticks that
## took, the crank's flare over the wheel side on that first tick (rpm), the rate it latched].
func _launch_close(handover_s: float, check := Callable()) -> Array:
	var spec := _spec()
	spec.launch_engage_s = 1.0
	spec.shift_handover_s = handover_s
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# A vehicle's worth at the axle: the wheel side comes up ~16 rpm a tick through D1.
	var wheel := LumpedWheel.new(0.0, 200.0)
	var line := DrivetrainScript.launch_target_rpm(spec, 1.0)
	var peak := 0.0
	var ticks := 0
	var flare := NAN
	var rate := NAN
	for i in 600:
		var sync := DrivetrainScript.wheel_engine_rpm(spec, wheel.omega, 1)
		var was := dt.rpm
		_tick(dt, 1.0, wheel, 1)
		if is_nan(flare) and sync >= line:
			flare = was - sync
			rate = DrivetrainScript.handover_rate(spec, flare / DrivetrainScript.RADS_TO_RPM)
		if not is_nan(flare):
			ticks += 1
			peak = maxf(peak, dt.coupling_torque)
			if check.is_valid() and dt.coupling_state != DrivetrainScript.CouplingState.LOCKED:
				check.call(dt, was, rate)
		if dt.coupling_state == DrivetrainScript.CouplingState.LOCKED:
			break
	assert_int(dt.coupling_state).is_equal(DrivetrainScript.CouplingState.LOCKED)
	return [peak, ticks, flare, rate]


func test_a_clutch_pull_aways_close_hands_over_never_at_the_rating() -> void:
	# The ramp held the clutch under the engine's torque, so the crank flared over the line. Closing at
	# the rating would pour that flare into the wheels in a tick; the handover lands the crank at the
	# shift's rate instead, the clutch carrying the engine's torque plus J x the rate.
	var spec := _spec()
	var rated := _launch_close(0.0)
	var handed := _launch_close(0.25, func(dt: DrivetrainScript, was: float, rate: float) -> void:
		var law := DrivetrainScript.engine_torque(spec, was) + spec.engine_inertia * rate
		assert_float(dt.coupling_torque).is_less_equal(law * 1.05))
	assert_float(float(handed[2])).is_greater(1000.0)
	assert_float(float(rated[0])).is_equal_approx(DrivetrainScript.clutch_rating(spec), 1e-3)
	assert_float(float(handed[0])).is_less(0.95 * DrivetrainScript.clutch_rating(spec))
	assert_int(int(handed[1])).is_greater(int(rated[1]) + 2)


## `_spec` with a start gear up to D3, a 0.5 s launch ramp and a 1 s dwell: at its 1600 rpm launch
## line (160 N·m) D1 / D2 / D3 make 1728 / 1152 / 864 N·m at the axle, so a 400 N·m standing load
## starts in D3, 500 in D2, 900 in D1.
func _start_spec() -> VehicleSpecScript:
	var spec := _spec()
	spec.start_gear_max = 3
	spec.launch_engage_s = 0.5
	spec.shift_dwell_s = 1.0
	return spec


func test_a_pull_away_starts_in_the_gear_the_standing_load_allows() -> void:
	var dt: DrivetrainScript = DrivetrainScript.new(_start_spec())
	dt.load_mass_kg = 1000.0
	for load_gear: Vector2i in [Vector2i(400, 3), Vector2i(500, 2), Vector2i(900, 1),
			Vector2i(400, 3)]:
		dt.standing_load = load_gear.x
		_auto_tick(dt, 0.0, 0.0, 1)
		assert_int(dt.gear_byte).override_failure_message("standing load %d" % load_gear.x) \
				.is_equal(load_gear.y)
	# Entered while rolling, it takes the byte asked for and the road speed's gear, as without one.
	var rolling: DrivetrainScript = DrivetrainScript.new(_start_spec())
	rolling.standing_load = 400.0
	_auto_tick(rolling, 0.0, 2.0, 1)
	assert_int(rolling.gear_byte).is_equal(1)
	# Declared at D1, entering D takes the requested byte.
	var none: DrivetrainScript = DrivetrainScript.new(_spec())
	_auto_tick(none, 0.0, 0.0, 1)
	assert_int(none.gear_byte).is_equal(1)


func test_a_launch_holds_its_start_gear_until_the_coupling_locks() -> void:
	# Pedal down, rolling at 600 rpm in D3, under its 1500 coast line: no downshift while it slips.
	var dt: DrivetrainScript = DrivetrainScript.new(_start_spec())
	dt.load_mass_kg = 1000.0
	dt.standing_load = 400.0
	_auto_tick(dt, 0.0, 0.0, 1)
	var v := _road_speed_for(dt, 3, 900.0)
	for i in 30:
		_auto_tick(dt, 1.0, v, 1)
	assert_int(dt.gear_byte).is_equal(3)
	# Locked, the launch is over and the coast line steps it down.
	dt.coupling_state = DrivetrainScript.CouplingState.LOCKED
	_auto_tick(dt, 1.0, v, 1)
	assert_int(dt.gear_byte).is_equal(2)


func test_a_light_pedal_launches_in_the_gear_it_can_hold_the_load_in() -> void:
	# A 400 N·m load starts D3 floored. At a fifth of the pedal the launch line is 960 rpm (100 N·m,
	# 20 on that fuel): D3 makes 108, D2 144 and D1 216 N·m at the axle, none twice 400, so it
	# takes D1 at once. Pressed on, it never goes back up while the launch lasts.
	var dt: DrivetrainScript = DrivetrainScript.new(_start_spec())
	dt.load_mass_kg = 1000.0
	dt.standing_load = 400.0
	_auto_tick(dt, 0.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(3)
	_auto_tick(dt, 0.2, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(1)
	for i in 10:
		_auto_tick(dt, 1.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(1)
	# Floored from the start it keeps D3.
	var floored: DrivetrainScript = DrivetrainScript.new(_start_spec())
	floored.load_mass_kg = 1000.0
	floored.standing_load = 400.0
	_auto_tick(floored, 0.0, 0.0, 1)
	_auto_tick(floored, 1.0, 0.0, 1)
	assert_int(floored.gear_byte).is_equal(3)


func test_a_launch_that_cannot_move_steps_its_start_gear_down() -> void:
	# Held at rest with the pedal down: after the 0.5 s ramp and the 1 s dwell (90 ticks, one more
	# for the float sum), one gear down, and again after as long.
	var dt: DrivetrainScript = DrivetrainScript.new(_start_spec())
	dt.load_mass_kg = 1000.0
	dt.standing_load = 400.0
	_auto_tick(dt, 0.0, 0.0, 1)
	for i in 89:
		_auto_tick(dt, 1.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(3)
	for i in 2:
		_auto_tick(dt, 1.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(2)
	for i in 91:
		_auto_tick(dt, 1.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(1)
	# The pedal lifted at rest picks again from the load.
	_auto_tick(dt, 0.0, 0.0, 1)
	assert_int(dt.gear_byte).is_equal(3)


func test_the_road_load_is_seeded_at_rest_and_held_under_the_brake() -> void:
	var dt: DrivetrainScript = DrivetrainScript.new(_spec())
	_auto_tick(dt, 0.0, 0.0, 1)
	assert_bool(is_nan(dt.road_load)).is_true()  # no mass: no estimate
	dt.load_mass_kg = 1000.0
	dt.standing_load = 300.0
	_auto_tick(dt, 0.0, 0.0, 1)
	assert_float(dt.road_load).is_equal(300.0)
	# Rolling at a steady 5 m/s with nothing passed, it decays from the seed toward no load.
	for i in 60:
		_auto_tick(dt, 0.0, 5.0, 1)
	assert_float(dt.road_load).is_less(300.0 * 0.5)
	# Braked, a hard deceleration is the brake, never a load: held.
	var held := dt.road_load
	dt.braking = true
	for i in 30:
		_auto_tick(dt, 0.0, 5.0 - 0.1 * i, 1)
	assert_float(dt.road_load).is_equal(held)
	# The rigid crank keeps none.
	var rigid := _spec()
	rigid.ground_drive = null
	var boat: DrivetrainScript = DrivetrainScript.new(rigid)
	boat.load_mass_kg = 1000.0
	_auto_tick(boat, 0.0, 5.0, 1)
	assert_bool(is_nan(boat.road_load)).is_true()
