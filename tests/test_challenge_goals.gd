extends GdUnitTestSuite
## Challenge goal primitives, fed hand-built ChallengeFrames at the locked 60 Hz tick. Boundaries
## are inclusive and a hold is met on exactly its tick, so each edge is pinned from both sides.

const S := ChallengeCheck.Status
const DT := 1.0 / 60.0

const INSIDE := Vector3(0, 0, 0)
const OUTSIDE := Vector3(0, 0, 50)


func _frame(pos := Vector3.ZERO, signals := {}) -> ChallengeFrame:
	var f := ChallengeFrame.new()
	f.pose = Transform3D(Basis.IDENTITY, pos)
	f.signals = signals
	return f


## A frame whose body travelled from `from` to `to` during the tick.
func _moved(from: Vector3, to: Vector3, signals := {}) -> ChallengeFrame:
	var f := _frame(to, signals)
	f.prev_origin = from
	return f


func _box(size := Vector3(10, 4, 10), pos := Vector3.ZERO) -> ZoneShape:
	return ZoneShape.box(Transform3D(Basis.IDENTITY, pos), size)


func _bind(check: ChallengeCheck, zones: Dictionary) -> void:
	var typed: Dictionary[StringName, ZoneShape] = {}
	for k in zones:
		typed[StringName(k)] = zones[k]
	assert_array(check.bind(typed)).is_empty()
	assert_array(check.problems()).is_empty()
	check.reset()


## Steps `check` on `frame` up to `ticks` times; returns the status and the tick it came on
## (1-based), or RUNNING and `ticks`.
func _run(check: ChallengeCheck, frame: ChallengeFrame, ticks: int) -> Vector2i:
	for i in ticks:
		var s := check.step(frame, DT)
		if s != S.RUNNING:
			return Vector2i(s, i + 1)
	return Vector2i(S.RUNNING, ticks)


# --- reach -------------------------------------------------------------------

func test_reach_zone_passes_on_entry() -> void:
	var g := ReachZoneGoal.new()
	g.zone = &"Finish"
	_bind(g, {&"Finish": _box()})
	assert_int(g.step(_frame(OUTSIDE), DT)).is_equal(S.RUNNING)
	assert_int(g.step(_frame(INSIDE), DT)).is_equal(S.PASS)


## At 100 km/h a car covers 0.46 m a tick: a 20 cm finish line lies between two samples.
func test_a_thin_line_crossed_between_two_ticks_is_reached() -> void:
	var g := ReachZoneGoal.new()
	g.zone = &"Line"
	_bind(g, {&"Line": _box(Vector3(10, 4, 0.2))})
	assert_int(g.step(_frame(Vector3(0, 0, -0.3)), DT)).is_equal(S.RUNNING)   # no previous tick
	assert_int(g.step(_moved(Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)), DT)).is_equal(S.PASS)


func test_a_goal_reports_a_missing_zone() -> void:
	var g := ReachZoneGoal.new()
	g.zone = &"Nope"
	var zones: Dictionary[StringName, ZoneShape] = {&"Finish": _box()}
	assert_array(g.bind(zones)).has_size(1)


# --- stop in zone --------------------------------------------------------------

func _stop_goal() -> StopInZoneGoal:
	var g := StopInZoneGoal.new()
	g.zone = &"Box"
	g.hold_s = 0.5
	_bind(g, {&"Box": _box(Vector3(4, 2, 6))})
	return g


func _stopped(contacts: Array, wheel_count := 4, velocity := Vector3.ZERO, heading := 0.0) -> ChallengeFrame:
	var f := _frame(INSIDE, {"heading": heading})
	f.velocity = velocity
	f.wheel_contacts = PackedVector3Array(contacts)
	f.wheel_count = wheel_count
	return f


const EDGE_WHEELS := [Vector3(2, 0, 3), Vector3(-2, 0, 3), Vector3(2, 0, -3), Vector3(-2, 0, -3)]


## Every wheel exactly on the box edge counts as inside, and the hold is met on exactly its tick.
func test_stop_on_the_box_edge_passes_on_the_hold_tick() -> void:
	var g := _stop_goal()
	assert_that(_run(g, _stopped(EDGE_WHEELS), 30)).is_equal(Vector2i(S.PASS, 30))


func test_stop_a_millimetre_past_the_edge_never_passes() -> void:
	var g := _stop_goal()
	var wheels := EDGE_WHEELS.duplicate()
	wheels[0] = Vector3(2.001, 0, 3)
	assert_that(_run(g, _stopped(wheels), 120).x).is_equal(S.RUNNING)


func test_stop_with_a_wheel_off_the_ground_never_passes() -> void:
	var g := _stop_goal()
	assert_that(_run(g, _stopped(EDGE_WHEELS.slice(0, 3)), 120).x).is_equal(S.RUNNING)


func test_stop_hold_restarts_when_the_car_moves() -> void:
	var g := _stop_goal()
	assert_that(_run(g, _stopped(EDGE_WHEELS), 20).x).is_equal(S.RUNNING)
	assert_int(g.step(_stopped(EDGE_WHEELS, 4, Vector3(0, 0, -0.2)), DT)).is_equal(S.RUNNING)
	assert_that(_run(g, _stopped(EDGE_WHEELS), 30)).is_equal(Vector2i(S.PASS, 30))


## A drone drifting sideways reads 0 forward `speed`; it is not stopped.
func test_a_sideways_drift_is_not_a_stop() -> void:
	var g := _stop_goal()
	var drifting := _stopped([], 0, Vector3(1, 0, 0))
	drifting.signals["speed"] = 0.0
	assert_that(_run(g, drifting, 120).x).is_equal(S.RUNNING)


func test_stop_heading_tolerance_works_across_north() -> void:
	var g := _stop_goal()
	g.heading_deg = 5.0
	g.heading_tol_deg = 10.0
	assert_array(g.signal_refs()).contains_exactly(["heading"])
	assert_that(_run(g, _stopped(EDGE_WHEELS, 4, Vector3.ZERO, 190.0), 60).x).is_equal(S.RUNNING)
	assert_that(_run(g, _stopped(EDGE_WHEELS, 4, Vector3.ZERO, 355.0), 30).x).is_equal(S.PASS)
	assert_float(StopInZoneGoal.heading_error_deg(350.0, 10.0)).is_equal_approx(20.0, 1e-6)
	assert_float(StopInZoneGoal.heading_error_deg(10.0, 350.0)).is_equal_approx(20.0, 1e-6)


func test_stop_judges_a_wheel_less_body_by_its_origin() -> void:
	var g := _stop_goal()
	assert_that(_run(g, _stopped([], 0), 30).x).is_equal(S.PASS)


# --- signal band ----------------------------------------------------------------

func _gate(low: float) -> SignalBandGoal:
	var gate := SignalBandGoal.new()
	gate.signal_name = "kmh"
	gate.low = low
	gate.zone = &"Gate"
	_bind(gate, {&"Gate": _box(Vector3(10, 4, 1))})
	return gate


## The entry-speed gate: a thin zone across the road, `kmh` with a floor only.
func test_gate_passes_at_exactly_the_entry_speed_and_fails_below_it() -> void:
	var gate := _gate(40.0)
	assert_array(gate.signal_refs()).contains_exactly(["kmh"])
	assert_int(gate.step(_frame(Vector3(0, 0, 5), {"kmh": 20.0}), DT)).is_equal(S.RUNNING)
	assert_int(gate.step(_frame(INSIDE, {"kmh": 40.0}), DT)).is_equal(S.RUNNING)
	assert_int(gate.step(_frame(Vector3(0, 0, -5), {"kmh": 40.0}), DT)).is_equal(S.PASS)

	gate.reset()
	assert_int(gate.step(_frame(INSIDE, {"kmh": 39.9}), DT)).is_equal(S.FAIL)
	assert_str(gate.message).contains("kmh")


## Through a gate between two samples: the speed is still judged on that tick.
func test_a_gate_skipped_between_ticks_is_still_judged() -> void:
	var fast := _gate(40.0)
	var through := Vector3(0, 0, -1.5)
	assert_int(fast.step(_moved(Vector3(0, 0, 1.5), through, {"kmh": 90.0}), DT)).is_equal(S.RUNNING)
	assert_int(fast.step(_moved(through, Vector3(0, 0, -3), {"kmh": 90.0}), DT)).is_equal(S.PASS)
	var slow := _gate(40.0)
	assert_int(slow.step(_moved(Vector3(0, 0, 1.5), through, {"kmh": 30.0}), DT)).is_equal(S.FAIL)


func test_speed_band_is_inclusive_and_absolute_judges_magnitude() -> void:
	var band := SignalBandGoal.new()
	band.signal_name = "speed"
	band.low = 4.0
	band.high = 6.0
	band.absolute = true
	band.zone = &"Trap"
	_bind(band, {&"Trap": _box()})
	for v in [-4.0, -6.0, 5.0, 6.0]:
		assert_int(band.step(_frame(INSIDE, {"speed": v}), DT)).is_equal(S.RUNNING)
	assert_int(band.step(_frame(INSIDE, {"speed": 6.01}), DT)).is_equal(S.FAIL)


## With an exit, a trap left by its side (or a corridor through its roof) fails.
func test_a_window_with_an_exit_fails_any_other_way_out() -> void:
	var trap := SignalBandGoal.new()
	trap.signal_name = "kmh"
	trap.low = 48.0
	trap.high = 52.0
	trap.zone = &"Trap"
	trap.exit_zone = &"Exit"
	_bind(trap, {&"Trap": _box(Vector3(10, 4, 40)), &"Exit": _box(Vector3(10, 4, 2), Vector3(0, 0, -21))})
	var ok := {"kmh": 50.0}
	assert_int(trap.step(_frame(INSIDE, ok), DT)).is_equal(S.RUNNING)
	assert_int(trap.step(_frame(Vector3(20, 0, 0), ok), DT)).is_equal(S.FAIL)
	assert_str(trap.message).contains("Exit")
	trap.reset()
	assert_int(trap.step(_frame(INSIDE, ok), DT)).is_equal(S.RUNNING)
	assert_int(trap.step(_frame(Vector3(0, 0, -21), ok), DT)).is_equal(S.PASS)


# --- signal reach ----------------------------------------------------------------

func test_value_at_a_point_holds_inside_its_zone() -> void:
	var g := SignalReachGoal.new()
	g.signal_name = "axle_load"
	g.low = 5900.0
	g.high = 6700.0
	g.zone = &"Scale"
	g.hold_s = 1.0
	_bind(g, {&"Scale": _box()})
	assert_that(_run(g, _frame(OUTSIDE, {"axle_load": 6000.0}), 90).x).is_equal(S.RUNNING)
	assert_that(_run(g, _frame(INSIDE, {"axle_load": 7000.0}), 90).x).is_equal(S.RUNNING)
	assert_that(_run(g, _frame(INSIDE, {"axle_load": 6700.0}), 90)).is_equal(Vector2i(S.PASS, 60))


func test_state_reached_reads_a_bool_as_one() -> void:
	var g := SignalReachGoal.new()
	g.signal_name = "armed"
	g.low = 1.0
	g.high = 1.0
	_bind(g, {})
	assert_int(g.step(_frame(INSIDE, {"armed": false}), DT)).is_equal(S.RUNNING)
	assert_int(g.step(_frame(INSIDE, {"armed": true}), DT)).is_equal(S.PASS)


# --- lamp window ------------------------------------------------------------------

func _lamp_frame(pos: Vector3, lit: bool) -> ChallengeFrame:
	var f := _frame(pos)
	f.input.lamps.turn_left = lit
	return f


func _window(expect_on := true) -> LampWindowGoal:
	var g := LampWindowGoal.new()
	g.lamp = &"turn_left"
	g.zone = &"Window"
	g.expect_on = expect_on
	_bind(g, {&"Window": _box()})
	return g


## sloppyCAN blinks the turn bit at the source, so a "steady" check must pass a 1 Hz flash.
func test_lamp_window_passes_a_source_blinked_bit() -> void:
	var g := _window()
	for _cycle in 3:
		assert_that(_run(g, _lamp_frame(INSIDE, true), 30).x).is_equal(S.RUNNING)
		assert_that(_run(g, _lamp_frame(INSIDE, false), 30).x).is_equal(S.RUNNING)
	assert_int(g.step(_lamp_frame(OUTSIDE, false), DT)).is_equal(S.PASS)


## The default gap is a legal flasher's longest dark stretch, 1.05 s: 63 ticks pass, 64 fail.
func test_lamp_window_gap_limit_is_exact() -> void:
	var g := _window()
	g.step(_lamp_frame(INSIDE, true), DT)
	assert_that(_run(g, _lamp_frame(INSIDE, false), 63).x).is_equal(S.RUNNING)
	assert_int(g.step(_lamp_frame(INSIDE, false), DT)).is_equal(S.FAIL)


func test_lamp_window_fails_a_lamp_never_lit() -> void:
	var g := _window()
	assert_that(_run(g, _lamp_frame(INSIDE, false), 30).x).is_equal(S.RUNNING)
	assert_int(g.step(_lamp_frame(OUTSIDE, false), DT)).is_equal(S.FAIL)


func test_lamp_window_off_fails_on_any_lit_tick() -> void:
	var g := _window(false)
	assert_that(_run(g, _lamp_frame(INSIDE, false), 30).x).is_equal(S.RUNNING)
	assert_int(g.step(_lamp_frame(INSIDE, true), DT)).is_equal(S.FAIL)
	g.reset()
	_run(g, _lamp_frame(INSIDE, false), 30)
	assert_int(g.step(_lamp_frame(OUTSIDE, true), DT)).is_equal(S.PASS)


func test_a_lamp_goal_only_takes_an_on_off_bit() -> void:
	var g := LampWindowGoal.new()
	g.lamp = &"led"
	assert_array(g.problems()).is_not_empty()
	g.lamp = &"beacon"
	assert_array(g.problems()).is_empty()


# --- lamp frequency ---------------------------------------------------------------

func _flasher() -> LampFrequencyGoal:
	var g := LampFrequencyGoal.new()
	g.lamp = &"turn_left"
	g.zone = &"Window"
	_bind(g, {&"Window": _box()})
	return g


## Steps one lit/dark state per tick inside the window; returns the first non-RUNNING status.
func _steps(g: LampFrequencyGoal, states: Array[bool]) -> int:
	for lit in states:
		var s := g.step(_lamp_frame(INSIDE, lit), DT)
		if s != S.RUNNING:
			return s
	return S.RUNNING


## One period per entry of `periods` (ticks), lit for the first half.
func _periods(periods: Array) -> Array[bool]:
	var out: Array[bool] = []
	for p: int in periods:
		for t in p:
			out.append(t < p / 2.0)
	return out


## Enters dark, flashes `periods`, then leaves; returns the first non-RUNNING status.
func _flash(g: LampFrequencyGoal, periods: Array) -> int:
	g.step(_lamp_frame(INSIDE, false), DT)
	var s := _steps(g, _periods(periods))
	return s if s != S.RUNNING else g.step(_lamp_frame(OUTSIDE, false), DT)


func test_flashing_at_exactly_one_hertz_passes() -> void:
	assert_int(_flash(_flasher(), [60, 60, 60, 60])).is_equal(S.PASS)


func test_flashing_at_exactly_two_hertz_passes() -> void:
	assert_int(_flash(_flasher(), [30, 30, 30, 30, 30, 30])).is_equal(S.PASS)


## At 20 fps two or three physics ticks read the same inbound bit, so a 2 Hz source reads 27-33
## ticks; the 50 ms tolerance is that frame.
func test_two_hertz_sampled_at_a_render_frame_passes() -> void:
	assert_int(_flash(_flasher(), [30, 27, 33, 30, 28, 32, 30])).is_equal(S.PASS)


func test_flashing_past_the_tolerance_fails() -> void:
	assert_int(_flash(_flasher(), [26, 26, 26, 26, 26])).is_equal(S.FAIL)   # 2.3 Hz
	assert_int(_flash(_flasher(), [64, 64, 64])).is_equal(S.FAIL)           # 0.94 Hz
	assert_int(_flash(_flasher(), [63, 63, 63])).is_equal(S.PASS)           # 0.95 Hz, the limit


func test_a_steady_bit_fails_the_blink_check() -> void:
	var g := _flasher()
	g.step(_lamp_frame(INSIDE, false), DT)
	assert_that(_run(g, _lamp_frame(INSIDE, true), 120).x).is_equal(S.FAIL)


## Entering lit, 15 ticks before the next rise: timing entry as an edge would read a 0.27 s
## period and fail.
func test_entering_mid_flash_is_not_timed_as_an_edge() -> void:
	var g := _flasher()
	var states: Array[bool] = []
	states.append_array([true, true, true, true, true, true])
	states.append_array([false, false, false, false, false, false, false, false, false, false])
	states.append_array(_periods([30, 30, 30, 30]))
	assert_int(_steps(g, states)).is_equal(S.RUNNING)
	assert_int(g.step(_lamp_frame(OUTSIDE, false), DT)).is_equal(S.PASS)


func test_period_band_limits() -> void:
	var tol := 0.05
	assert_bool(LampFrequencyGoal.period_in_band(0.5, 1.0, 2.0, tol)).is_true()
	assert_bool(LampFrequencyGoal.period_in_band(1.0, 1.0, 2.0, tol)).is_true()
	assert_bool(LampFrequencyGoal.period_in_band(27 * DT, 1.0, 2.0, tol)).is_true()
	assert_bool(LampFrequencyGoal.period_in_band(63 * DT, 1.0, 2.0, tol)).is_true()
	assert_bool(LampFrequencyGoal.period_in_band(26 * DT, 1.0, 2.0, tol)).is_false()
	assert_bool(LampFrequencyGoal.period_in_band(64 * DT, 1.0, 2.0, tol)).is_false()


# --- ring lap ----------------------------------------------------------------------

func _ring_goal() -> RingLapGoal:
	var g := RingLapGoal.new()
	g.zone = &"Ring"
	_bind(g, {&"Ring": ZoneShape.ring(Transform3D.IDENTITY, 10.0, 20.0)})
	return g


func _on_ring(deg: float, r := 15.0) -> ChallengeFrame:
	var a := deg_to_rad(deg)
	return _frame(Vector3(r * cos(a), 0, r * sin(a)))


## Drives from `from_deg` to `to_deg` in one-degree steps; returns the first non-RUNNING status
## and the angle it came at.
func _sweep(g: RingLapGoal, from_deg: int, to_deg: int) -> Vector2i:
	var dir := 1 if to_deg >= from_deg else -1
	var deg := from_deg
	while deg != to_deg + dir:
		var s := g.step(_on_ring(deg), DT)
		if s != S.RUNNING:
			return Vector2i(s, deg)
		deg += dir
	return Vector2i(S.RUNNING, to_deg)


## Starts at 170 degrees, so the lap crosses atan2's seam at 180.
func test_ring_lap_passes_after_a_full_turn_across_the_seam() -> void:
	var g := _ring_goal()
	assert_that(_sweep(g, 170, 600)).is_equal(Vector2i(S.PASS, 530))


func test_ring_lap_counts_net_rotation() -> void:
	var g := _ring_goal()
	assert_that(_sweep(g, 0, 180).x).is_equal(S.RUNNING)
	assert_that(_sweep(g, 180, 0).x).is_equal(S.RUNNING)
	assert_that(_sweep(g, 0, 300).x).is_equal(S.RUNNING)
	assert_float(rad_to_deg(g.swept())).is_equal_approx(300.0, 1e-3)


func test_ring_lap_fails_when_the_car_leaves_the_ring() -> void:
	var g := _ring_goal()
	assert_int(g.step(_on_ring(0.0, 25.0), DT)).is_equal(S.RUNNING)   # not yet entered
	_sweep(g, 0, 90)
	assert_int(g.step(_on_ring(90.0, 21.0), DT)).is_equal(S.FAIL)


func test_ring_lap_needs_a_ring_with_an_inner_radius() -> void:
	var g := RingLapGoal.new()
	g.zone = &"Z"
	var boxed: Dictionary[StringName, ZoneShape] = {&"Z": _box()}
	var solid: Dictionary[StringName, ZoneShape] = {&"Z": ZoneShape.ring(Transform3D.IDENTITY, 0.0, 5.0)}
	assert_array(g.bind(boxed)).has_size(1)
	assert_array(g.bind(solid)).has_size(1)


# --- payload -------------------------------------------------------------------------

func test_payload_must_settle_in_the_zone() -> void:
	var g := PayloadInZoneGoal.new()
	g.zone = &"Drop"
	_bind(g, {&"Drop": _box()})
	var inside := _frame()
	inside.payloads = PackedVector3Array([Vector3(30, 0, 0), Vector3(1, 0, 1)])
	var bounced := _frame()
	bounced.payloads = PackedVector3Array([Vector3(30, 0, 0)])
	assert_that(_run(g, inside, 30).x).is_equal(S.RUNNING)
	assert_int(g.step(bounced, DT)).is_equal(S.RUNNING)
	assert_that(_run(g, inside, 60)).is_equal(Vector2i(S.PASS, 60))


# --- gimbal aim ------------------------------------------------------------------------

func test_aim_error_follows_the_gimbal_basis() -> void:
	var level := Transform3D.IDENTITY
	assert_float(GimbalAimGoal.aim_error_deg(level, 0.0, 0.0, Vector3(0, 0, -10))) \
			.is_equal_approx(0.0, 1e-3)
	assert_float(GimbalAimGoal.aim_error_deg(level, 0.0, 0.0, Vector3(10, 0, 0))) \
			.is_equal_approx(90.0, 1e-3)
	# DroneGimbal's own convention: yaw -90 pans the camera to +X.
	assert_float(GimbalAimGoal.aim_error_deg(level, 0.0, -90.0, Vector3(10, 0, 0))) \
			.is_equal_approx(0.0, 1e-3)
	assert_float(GimbalAimGoal.aim_error_deg(level, -45.0, 0.0, Vector3(0, -10, -10))) \
			.is_equal_approx(0.0, 1e-3)
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(5, 0, 0))
	assert_float(GimbalAimGoal.aim_error_deg(turned, 0.0, 0.0, Vector3(-5, 0, 0))) \
			.is_equal_approx(0.0, 1e-3)


## The mount rides the body: a craft pitched 45 degrees nose-down sees the same target with the
## gimbal level that a level craft needs -45 of gimbal pitch for.
func test_aim_error_composes_a_pitched_body() -> void:
	var nose_down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-45.0)), Vector3.ZERO)
	assert_float(GimbalAimGoal.aim_error_deg(nose_down, 0.0, 0.0, Vector3(0, -10, -10))) \
			.is_equal_approx(0.0, 1e-3)
	assert_float(GimbalAimGoal.aim_error_deg(nose_down, -45.0, 0.0, Vector3(0, -10, -10))) \
			.is_equal_approx(45.0, 1e-3)


func test_gimbal_aim_holds_on_the_actual_readbacks() -> void:
	var g := GimbalAimGoal.new()
	g.zone = &"Target"
	g.tol_deg = 2.0
	g.hold_s = 0.5
	_bind(g, {&"Target": _box(Vector3.ONE, Vector3(0, -10, -10))})
	var off := _frame(INSIDE, {"gimbal_pitch_actual": 0, "gimbal_yaw_actual": 0})
	var on := _frame(INSIDE, {"gimbal_pitch_actual": -45, "gimbal_yaw_actual": 0})
	assert_that(_run(g, off, 60).x).is_equal(S.RUNNING)
	assert_that(_run(g, on, 60)).is_equal(Vector2i(S.PASS, 30))


# --- input equals ------------------------------------------------------------------------

func test_led_matches_its_rgb565_under_the_mask() -> void:
	var g := InputEqualsGoal.new()
	g.field = &"led"
	g.values = PackedInt32Array([0xF800])
	g.mask = 0xFFFF
	g.hold_s = 0.5
	var f := _frame()
	f.input.lamps.led = 0x1F800
	assert_that(_run(g, f, 60)).is_equal(Vector2i(S.PASS, 30))
	g.reset()
	g.mask = -1
	assert_that(_run(g, f, 60).x).is_equal(S.RUNNING)


## Lights LOW or HIGH: any of the values passes.
func test_input_equals_takes_any_of_its_values() -> void:
	var g := InputEqualsGoal.new()
	g.field = &"lights"
	g.values = PackedInt32Array([3, 4])
	g.hold_s = 0.0
	var f := _frame()
	f.input.lights = 2
	assert_int(g.step(f, DT)).is_equal(S.RUNNING)
	f.input.lights = 4
	assert_int(g.step(f, DT)).is_equal(S.PASS)
	assert_array(InputEqualsGoal.new().problems()).is_not_empty()


# --- rollback ------------------------------------------------------------------------------

func _hill_goal() -> RollbackGoal:
	var g := RollbackGoal.new()
	g.zone = &"Ramp"
	g.hold_s = 1.0
	_bind(g, {&"Ramp": _box()})
	return g


## Forward is -Z, so rolling back is +Z.
func _hill(z: float, speed := 0.0) -> ChallengeFrame:
	var f := _frame(Vector3(0, 0, z))
	f.velocity = Vector3(0, 0, -speed)
	return f


func test_hill_start_within_the_rollback_passes() -> void:
	var g := _hill_goal()
	assert_that(_run(g, _hill(0.0), 60).x).is_equal(S.RUNNING)
	assert_int(g.step(_hill(0.09, -0.2), DT)).is_equal(S.RUNNING)
	assert_int(g.step(_hill(-1.0, 1.0), DT)).is_equal(S.RUNNING)
	assert_int(g.step(_hill(-2.0, 1.0), DT)).is_equal(S.PASS)


func test_hill_start_past_the_rollback_fails() -> void:
	var g := _hill_goal()
	_run(g, _hill(0.0), 60)
	assert_int(g.step(_hill(0.11, -0.2), DT)).is_equal(S.FAIL)
	assert_str(g.message).contains("11 cm")


## Movement before the stop has been held is not rollback: nothing has been anchored yet.
func test_hill_start_only_measures_after_the_held_stop() -> void:
	var g := _hill_goal()
	_run(g, _hill(0.0), 30)
	assert_int(g.step(_hill(0.5, -1.0), DT)).is_equal(S.RUNNING)
	assert_that(_run(g, _hill(0.5), 60).x).is_equal(S.RUNNING)
	assert_int(g.step(_hill(0.55, -0.2), DT)).is_equal(S.RUNNING)
	assert_int(g.step(_hill(0.62, -0.2), DT)).is_equal(S.FAIL)
