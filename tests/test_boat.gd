extends GdUnitTestSuite
## Boat buoyancy/thrust/rudder math. Pure static fns exercised
## without the physics body — the same testing discipline as Drivetrain and RayWheel's
## telemetry derivations. What matters most here is the 60 Hz one-tick clamp (the
## RayWheel discipline): the probe damper may never reverse a velocity within one tick,
## and buoyancy is hard-capped. The hull drag and attitude math the boat shares with the
## drone and plane lives in `VehicleMath` — see `test_vehicle_math.gd`.

const B := preload("res://src/vehicles/boat/boat.gd")
const BoatT := preload("res://src/vehicles/boat/boat_telemetry.gd")

const DELTA := 1.0 / 60.0

## Round numbers so expected values are hand-checkable: an 800 kg boat on 4 probes
## floating 0.4 m deep at g = 10 -> k = 800*10 / (4*0.4) = 5000 N/m per probe.
const MASS := 800.0
const G := 10.0
const PROBES := 4.0
const FLOAT_DEPTH := 0.4
const K := MASS * G / (PROBES * FLOAT_DEPTH)      # 5000
const PROBE_MASS := MASS / PROBES                 # 200
const MAX_F := 3.0 * PROBE_MASS * G               # 6000


# --- probe_force: spring ------------------------------------------------------

func test_probe_force_zero_at_and_above_surface() -> void:
	assert_float(B.probe_force(0.0, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)
	assert_float(B.probe_force(-1.0, -5.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)


func test_probe_force_spring_is_linear_in_depth() -> void:
	assert_float(B.probe_force(0.1, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)) \
			.is_equal_approx(500.0, 1e-6)
	assert_float(B.probe_force(0.2, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)) \
			.is_equal_approx(1000.0, 1e-6)


func test_probe_force_all_probes_at_float_depth_carry_the_boat() -> void:
	# Floating level at the design depth, at rest: the probes sum to exactly m*g.
	var per_probe := B.probe_force(FLOAT_DEPTH, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)
	assert_float(per_probe * PROBES).is_equal_approx(MASS * G, 1e-6)


# --- probe_force: 60 Hz clamps ------------------------------------------------

func test_probe_force_damper_clamped_to_one_tick_reversal() -> void:
	# Sinking at 2 m/s with an absurd damper coefficient: the damper contribution must
	# cap at probe_mass * |v| / delta (RayWheel's damper clamp), not the raw c*v.
	# max_force is lifted out of the way so this isolates the damper clamp.
	var v := -2.0
	var tick_cap := PROBE_MASS * absf(v) / DELTA  # 24000
	var f := B.probe_force(0.1, v, K, 1e9, PROBE_MASS, DELTA, 1e12)
	assert_float(f).is_equal_approx(500.0 + tick_cap, 1e-3)


func test_probe_force_never_negative_when_rising() -> void:
	# Rising fast out of the water: the damper pulls down but water never sucks the
	# hull under — total force clamps at zero.
	assert_float(B.probe_force(0.05, 10.0, K, 1e9, PROBE_MASS, DELTA, MAX_F)).is_equal(0.0)


func test_probe_force_hard_capped_on_deep_penetration() -> void:
	# Slammed 3 m deep (a drop from the crane): raw spring would be 15000 N; the cap
	# holds it at MAX_F so the boat never catapults (max_suspension_force analogue).
	assert_float(B.probe_force(3.0, 0.0, K, 500.0, PROBE_MASS, DELTA, MAX_F)).is_equal(MAX_F)


# --- thrust + rudder ------------------------------------------------------------

func test_thrust_scale_forward_full_reverse_scaled() -> void:
	assert_float(B.thrust_scale(1.0, 0.4)).is_equal(1.0)
	assert_float(B.thrust_scale(0.5, 0.4)).is_equal(0.5)
	assert_float(B.thrust_scale(-1.0, 0.4)).is_equal_approx(-0.4, 1e-6)
	assert_float(B.thrust_scale(0.0, 0.4)).is_equal(0.0)
	# Out-of-range input clamps first.
	assert_float(B.thrust_scale(2.0, 0.4)).is_equal(1.0)


func test_rudder_authority_needs_flow() -> void:
	# Dead in the water, no throttle: no flow over the blade, no turn.
	assert_float(B.rudder_authority(0.0, 0.0)).is_equal(0.0)
	# Prop wash alone gives partial authority from standstill (turn out of a dock).
	assert_float(B.rudder_authority(0.0, 1.0)).is_equal_approx(B.RUDDER_PROP_WASH, 1e-6)
	# Full authority at/above the reference speed, clamped at 1.
	assert_float(B.rudder_authority(B.RUDDER_SPEED_REF, 0.0)).is_equal(1.0)
	assert_float(B.rudder_authority(30.0, 1.0)).is_equal(1.0)
	# Reverse flow works the blade too.
	assert_float(B.rudder_authority(-B.RUDDER_SPEED_REF, 0.0)).is_equal(1.0)


# --- trim model (modeled honest value, like engine_load) ------------------------

func test_trim_step_chases_forward_throttle() -> void:
	# 40 %/s toward throttle*100; one second at full throttle from zero.
	assert_float(BoatT.trim_step(0.0, 1.0, 40.0, 1.0)).is_equal_approx(40.0, 1e-6)
	# move_toward never overshoots the target.
	assert_float(BoatT.trim_step(95.0, 1.0, 40.0, 1.0)).is_equal(100.0)
	# Off throttle / reverse both trim back toward zero.
	assert_float(BoatT.trim_step(50.0, 0.0, 40.0, 1.0)).is_equal_approx(10.0, 1e-6)
	assert_float(BoatT.trim_step(50.0, -1.0, 40.0, 1.0)).is_equal_approx(10.0, 1e-6)


func test_boat_telemetry_bridge_dict_adds_boat_fields() -> void:
	var t := BoatT.new()
	t.pitch = 4.5
	t.roll = -2.0
	t.rudder_actual = -60
	t.trim = 35
	var d := t.to_bridge_dict()
	assert_float(d["pitch"]).is_equal(4.5)
	assert_float(d["roll"]).is_equal(-2.0)
	assert_int(d["rudder_actual"]).is_equal(-60)
	assert_int(d["trim"]).is_equal(35)
	# Base fields still ride along (super() first, tractor pattern).
	assert_bool(d.has("speed")).is_true()
	assert_bool(d.has("status")).is_true()
