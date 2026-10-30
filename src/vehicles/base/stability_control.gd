class_name StabilityControl
extends RefCounted
## Electronic stability control as pure statics: a yaw-rate reference off the bicycle model on the
## body's own steady K, a body-slip estimate off the sensors a real unit has (never the sim's true
## slip), and one wheel braked against the error with the engine trimmed. Proportional and
## continuous, never cycling. Signs + = left: steer (`WheelDrive.mean_steer_angle`), yaw rate,
## lateral acceleration, body slip (the velocity left of the nose). Corners: Vector4 FL, FR, RL, RR.
## Lateral acceleration is gravity-free, a real unit's bank-compensated reading: a raw one on a side
## slope integrates into a slip that is not there.
## Roll stability (`GroundDriveSpec.esc_roll_lift_g`, the semis): past ROLL_SHARE of the rig's
## measured first lift (or as the steer asks it), every wheel and the trailer braked, the fuel cut.
## Figures: `docs/sources.md` § Stability control.

const G := BrakeSizing.G

## Not active below it, nor in reverse (R140 6.2).
const MIN_SPEED := 20.0 / 3.6
## Dead-band on the yaw-rate error (rad/s): the floor, or this share of the reference (estimates).
const DEADBAND_RATE := 0.035
const DEADBAND_SHARE := 0.10
## Body slip (rad) past which the estimate alone acts (estimate).
const SLIP_LIMIT := deg_to_rad(5.0)
## The slip estimate's leak (s), against the kinematic integral's drift (estimate).
const SLIP_LEAK_S := 2.0
## What the reference may ask past the measured lateral acceleration's yaw (g); over the dead-band's
## floor below `BOUND_MARGIN_G * G / DEADBAND_RATE` (~200 km/h), so a ploughing body still reads
## understeer at the limit (estimate).
const BOUND_MARGIN_G := 0.2
## The proportional gain's time constant: `M_z = I_z * error / CORRECT_S` (estimate).
const CORRECT_S := 0.25
## A hydraulic modulator's rise (s) from zero to the wheel's full declared brake, and its release
## back (estimates). The release is rate-limited, not a dump: a dump at the dead-band's edge drops
## the torque to 0, the error returns and the rise starts over, a tick-rate ring on the step pass.
## A corner on the side the moment no longer asks dumps at once: draining, it would cancel the
## new side's correction.
const RISE_S := 0.25
const RELEASE_S := 0.25
## The speed the reference K table is read off the corner model at (estimate: K moves little with
## speed on the ESC bodies, none of which carries downforce).
const REFERENCE_SPEED := 80.0 / 3.6
## The table's resolution, in g and in deg/g.
const TABLE_SNAP := 1e-4
## Roll stability starts braking at this share of the rig's first-lift g and reaches the full brake
## at the lift (estimate: no intervention point is published).
const ROLL_SHARE := 0.7
## The retardation (m/s²) under which automatically commanded braking may leave the stop lamps
## dark (R13 5.2.1.30.5); selective braking, the yaw's, never lights them (5.2.1.30.6).
const LAMP_DECEL := 0.7
## Once lit, the request holds down to this retardation (m/s²), so a roll application hovering at
## LAMP_DECEL neither flickers the lamp nor cycles the lock-up; under LAMP_DECEL R13 lets the
## signal stand or go (estimate: no release point is published).
const LAMP_RELEASE_DECEL := 0.5


## The corner model's K table of `spec` (`BalanceModel.k_curve` at REFERENCE_SPEED), snapped to
## TABLE_SNAP so a regen writes a stable file: `GroundDriveSpec.esc_reference_k`. Empty where the
## model is (no single front and rear pair). A point the snap lands on its neighbour's g is dropped.
static func reference_table(spec: VehicleSpec) -> PackedVector2Array:
	var table := PackedVector2Array()
	for p in BalanceModel.k_curve(BalanceModel.axles(spec, REFERENCE_SPEED), REFERENCE_SPEED):
		var point := Vector2(snappedf(p.x, TABLE_SNAP), snappedf(p.y, TABLE_SNAP))
		if table.is_empty() or point.x > table[table.size() - 1].x:
			table.append(point)
	return table


## The reference K (deg/g) at `lat_g`, read linearly off `points` (x g ascending, y K), held at the
## end values. An empty table is an error, NAN.
static func reference_k(points: PackedVector2Array, lat_g: float) -> float:
	if points.is_empty():
		push_error("StabilityControl: no reference K table")
		return NAN
	return VehicleSpec.sample_curve(points, absf(lat_g))


## The yaw rate (rad/s) the driver asks: `v δ / (L + K v²)`, K (`k_deg_g`) in rad per m/s², bounded
## by what the measured `lat_acc` carries plus BOUND_MARGIN_G. 0 at standstill.
static func reference_yaw(speed: float, steer: float, wheelbase: float, k_deg_g: float,
		lat_acc: float) -> float:
	if speed <= 0.0 or wheelbase <= 0.0:
		return 0.0
	var bound := (absf(lat_acc) + BOUND_MARGIN_G * G) / speed
	var den := wheelbase + deg_to_rad(k_deg_g) / G * speed * speed
	if den <= 0.0:
		# An oversteering body past its critical speed: no finite steady turn.
		return bound * signf(steer)
	return clampf(speed * steer / den, -bound, bound)


## One tick of the body-slip estimate (rad): `β̇ = a_y / v − r`, leaked over SLIP_LEAK_S. Reset
## to 0 below MIN_SPEED.
static func slip_step(beta: float, lat_acc: float, yaw_rate: float, speed: float,
		delta: float) -> float:
	if speed < MIN_SPEED:
		return 0.0
	return (beta + (lat_acc / speed - yaw_rate) * delta) * exp(-delta / SLIP_LEAK_S)


## The yaw-rate error's dead-band (rad/s) about `ref_yaw`.
static func deadband(ref_yaw: float) -> float:
	return maxf(DEADBAND_RATE, DEADBAND_SHARE * absf(ref_yaw))


## The corrective yaw moment (N·m, + = left): the yaw error past its dead-band plus the slip past
## SLIP_LIMIT (as a rate over CORRECT_S), each from 0 at its threshold, times `I_z / CORRECT_S`.
static func yaw_moment(ref_yaw: float, yaw_rate: float, slip_est: float,
		yaw_inertia: float) -> float:
	var err := ref_yaw - yaw_rate
	var rate := signf(err) * maxf(absf(err) - deadband(ref_yaw), 0.0)
	rate += signf(slip_est) * maxf(absf(slip_est) - SLIP_LIMIT, 0.0) / CORRECT_S
	return yaw_inertia * rate / CORRECT_S


## One tick: `torques` (N·m per corner) and `throttle_cap` (0..1 on the delivered fuel). One wheel:
## the moment's side; the front where it opposes the measured yaw (oversteer, a countersteer spin
## too), else the rear (understeer); a wheel braking on that side in `prev` keeps its axle, so a yaw
## rate crossing zero never hops the brake mid-correction (either axle yaws the body the same way).
## `T = |M_z| R_w / (t / 2)`, capped at the axle's declared brake (`brake`, x front, y rear, per
## wheel; `half_track`, `wheel_radius` likewise). Each corner moves from `prev` toward its target
## at most `brake / rise_s` per second up and `brake / release_s` down; a corner on the other side
## of the moment dumps at once. Under MIN_SPEED (or in reverse) it is off: every corner 0 at once.
## The engine trim is proportional: the fuel capped at `1 − T / T_brake` of the most-braked corner,
## so a light touch at the dead-band's edge trims nothing it would toggle.
static func intervention(speed: float, ref_yaw: float, yaw_rate: float, slip_est: float,
		yaw_inertia: float, half_track: Vector2, wheel_radius: Vector2, brake: Vector2,
		prev: Vector4, delta: float, rise_s := RISE_S, release_s := RELEASE_S) -> Dictionary:
	if speed < MIN_SPEED:
		return {"torques": Vector4.ZERO, "throttle_cap": 1.0}
	var target := Vector4.ZERO
	var moment := yaw_moment(ref_yaw, yaw_rate, slip_est, yaw_inertia)
	var side := -1
	if moment != 0.0:
		side = 0 if moment > 0.0 else 1
		var axle := 1 if moment * yaw_rate >= 0.0 else 0
		if prev[side] > 0.0:
			axle = 0
		elif prev[2 + side] > 0.0:
			axle = 1
		var corner := 2 * axle + side
		target[corner] = minf(absf(moment) * wheel_radius[axle] / half_track[axle], brake[axle])
	var torques := Vector4.ZERO
	var cut := 0.0
	for i in 4:
		var cap := brake.y if i >= 2 else brake.x
		var floor_t := 0.0 if side >= 0 and i % 2 != side \
				else maxf(prev[i] - cap / release_s * delta, 0.0)
		torques[i] = clampf(target[i], floor_t, prev[i] + cap / rise_s * delta)
		if torques[i] > 0.0 and cap > 0.0:
			cut = maxf(cut, torques[i] / cap)
	return {"torques": torques, "throttle_cap": 1.0 - minf(cut, 1.0)}


## The lateral g (unsigned) the driver's steer asks: `speed` times `reference_yaw` on the measured
## `lat_acc`, so it leads the body by at most BOUND_MARGIN_G (roll stability acts on the steer
## before the g builds, never on a steer past what the road carries). 0 at standstill.
static func asked_lat_g(speed: float, steer: float, wheelbase: float, k_deg_g: float,
		lat_acc: float) -> float:
	return absf(speed * reference_yaw(speed, steer, wheelbase, k_deg_g, lat_acc)) / G


## The rig's first-lift lateral g at the coupled load `load_kg`, read linearly off `points` (x kg
## ascending, y g; `GroundDriveSpec.esc_roll_lift_g`), held at the end values. An empty table: no
## roll stability, INF.
static func roll_lift_g(points: PackedVector2Array, load_kg: float) -> float:
	if points.is_empty():
		return INF
	return VehicleSpec.sample_curve(points, load_kg)


## One tick of roll stability's application, 0..1 of every wheel's declared brake and the trailer's
## demand (the fuel capped at `1 − it`): 0 under ROLL_SHARE of `lift_g`, rising linearly to 1 at
## it, moving from `prev` at most `delta / rise_s` up and `delta / release_s` down, the yaw
## modulator's rates. Under MIN_SPEED (or in reverse) the target is 0, released at the rate (a rig
## slowing through it under full braking does not lurch); with no lift (INF), 0 at once.
static func roll_application(speed: float, lat_g: float, lift_g: float, prev: float,
		delta: float, rise_s := RISE_S, release_s := RELEASE_S) -> float:
	if not is_finite(lift_g) or lift_g <= 0.0:
		return 0.0
	var target := 0.0
	if speed >= MIN_SPEED:
		target = clampf((absf(lat_g) - ROLL_SHARE * lift_g) / ((1.0 - ROLL_SHARE) * lift_g),
				0.0, 1.0)
	return clampf(target, maxf(prev - delta / release_s, 0.0), prev + delta / rise_s)


## Each corner's stability brake torque (N·m, FL, FR, RL, RR): the yaw controller's `yaw` plus
## roll stability's `roll_app` of the axle's declared `brake` (x front, y rear), the roll part held
## to what the axle's most-braked yaw corner leaves under the brake, so the yaw moment survives a
## full roll application (the yaw takes priority).
static func corner_torques(roll_app: float, yaw: Vector4, brake: Vector2) -> Vector4:
	var out := yaw
	for axle in 2:
		var roll_t := minf(roll_app * brake[axle],
				maxf(brake[axle] - maxf(yaw[2 * axle], yaw[2 * axle + 1]), 0.0))
		out[2 * axle] += roll_t
		out[2 * axle + 1] += roll_t
	return out


## The retardation (m/s²) roll stability commands: each wheel's roll part of its corner's torque
## (`corner_torques`' `esc_brake` less the `yaw`), over its axle's radius (x front, y rear), summed
## and over the sensed load. The commanded torque, what the unit knows.
## COMPROMISE: on a coupled semi the load is the unit's sensed one (`WheelDrive.brake_load_kg`:
## the unit plus the kingpin share), never the rig's: the trailer's braking at the same demand
## (`ebs11_demand`) and its bogie-borne mass are left out, so the figure is off the rig's by how
## the trailer's brake-to-mass ratio differs from the unit's (a laden trailer's share of the kingpin
## lowers it). Exact needs the trailer's applied force and towed mass summed here (`TowHost`).
static func roll_retardation(esc_brake: Vector4, yaw: Vector4, corner: PackedInt32Array,
		axle_radius: Vector2, load_kg: float) -> float:
	if load_kg <= 0.0:
		return 0.0
	var force := 0.0
	for c in corner:
		@warning_ignore("integer_division")
		var radius := axle_radius[c / 2]
		if radius > 0.0:
			force += (esc_brake[c] - yaw[c]) / radius
	return force / load_kg


## The stop-lamp request of braking the unit commands itself: roll stability's retardation at
## LAMP_DECEL or more, held while `lit` (last tick's request) down to LAMP_RELEASE_DECEL.
static func brake_light_request(retardation: float, lit := false) -> bool:
	return retardation >= (LAMP_RELEASE_DECEL if lit else LAMP_DECEL)


# --- trailer roll-over control -----------------------------------------------------------------

## A semi-trailer EBS's own roll-over function, the makers' staged logic: past the
## threshold a low-pressure test pulse on every wheel; the inside wheels slowing under it bring the
## full application on the outside ones; a rapid rise skips the pulse; no reaction raises the
## threshold and spends the crossing. One pulse per crossing, never cycling. Commands only (0..1 of
## the trailer's declared brake per side): the chambers' lag (`TowedBody.lagged_brake`) is the
## application and release rate.
enum TrailerStage { IDLE, PULSE, FULL, SPENT }

## Not active below it, not adjustable ([194]).
const TRAILER_MIN_SPEED := 15.0 / 3.6
## The test pulse's share of the declared brake: "low pressure" (estimate).
const TRAILER_PULSE := 0.15
## How long the pulse holds while the wheel reaction is read; the chambers reach it in ~0.05 s
## (estimate).
const TRAILER_PULSE_S := 0.3
## The drop in the inside-over-outside wheel speed ratio under the pulse that reads as a lifting
## inside wheel; under `RayWheel.ABS_SLIP`, or the ABS releases the wheel before the read (estimate).
const TRAILER_LIFT_SLIP := 0.08
## A lateral-g rise (g/s) at the crossing past which it brakes without a pulse (estimate).
const TRAILER_RAPID_G_S := 1.0
## The rise rate's low-pass (s): a raw 60 Hz derivative fakes a rapid rise (estimate).
const TRAILER_RATE_FILTER_S := 0.1
## What a crossing with no wheel reaction adds to the threshold (g) (estimate).
const TRAILER_LEARN_G := 0.03
## The learned threshold's ceiling, a share of the lift: learning never moves it onto the lift
## (estimate).
const TRAILER_MAX_SHARE := 0.9
## Under this share of the lift the lateral g is non-critical: released and re-armed (estimate).
const TRAILER_RELEASE_SHARE := 0.6


## A fresh state for `trailer_roll_step`: idle, nothing learned.
static func trailer_roll_state() -> Dictionary:
	return {"stage": TrailerStage.IDLE, "timer": 0.0, "raise": 0.0, "rate": 0.0, "last_g": 0.0,
			"ratio0": 1.0}


## The lateral g (unsigned) the function crosses at: ROLL_SHARE of `lift_g` plus the learned
## `raise`, held under TRAILER_MAX_SHARE of it.
static func trailer_roll_threshold(lift_g: float, raise: float) -> float:
	return minf(ROLL_SHARE * lift_g + raise, TRAILER_MAX_SHARE * lift_g)


## One tick: `{ "state", "cmd": Vector2(left, right) }`, each side 0..1 of the declared brake.
## `lat_g` signed (+ = left, so the right wheels are outside), `lift_g` the trailer's first lift at
## its own load (`roll_lift_g`), `speed_left` / `speed_right` each side's mean wheel ground speed.
## The reaction is the inside-over-outside ratio dropping from its value at the crossing, so the
## turn's own geometry never reads as a lift; a g back under the release level before the read ends
## learns nothing. Under TRAILER_MIN_SPEED, or with no lift (INF), idle
## and 0 at once; the learned raise is kept.
static func trailer_roll_step(state: Dictionary, speed: float, lat_g: float, lift_g: float,
		speed_left: float, speed_right: float, delta: float) -> Dictionary:
	var s := state.duplicate()
	var g := absf(lat_g)
	if delta > 0.0:
		s["rate"] += ((g - s["last_g"]) / delta - s["rate"]) \
				* minf(delta / TRAILER_RATE_FILTER_S, 1.0)
	s["last_g"] = g
	if speed < TRAILER_MIN_SPEED or not is_finite(lift_g) or lift_g <= 0.0:
		s["stage"] = TrailerStage.IDLE
		return {"state": s, "cmd": Vector2.ZERO}
	var outside := speed_right if lat_g >= 0.0 else speed_left
	var inside := speed_left if lat_g >= 0.0 else speed_right
	var ratio := inside / outside if outside > 0.0 else 1.0
	var release := TRAILER_RELEASE_SHARE * lift_g
	match s["stage"]:
		TrailerStage.IDLE:
			if g >= trailer_roll_threshold(lift_g, s["raise"]):
				s["timer"] = 0.0
				s["ratio0"] = ratio
				s["stage"] = TrailerStage.FULL if s["rate"] >= TRAILER_RAPID_G_S \
						else TrailerStage.PULSE
		TrailerStage.PULSE:
			s["timer"] += delta
			if s["ratio0"] - ratio > TRAILER_LIFT_SLIP:
				s["stage"] = TrailerStage.FULL
			elif g < release:
				# Non-critical before the read ended: no verdict, nothing learned.
				s["stage"] = TrailerStage.IDLE
			elif s["timer"] >= TRAILER_PULSE_S:
				s["raise"] = minf(s["raise"] + TRAILER_LEARN_G,
						(TRAILER_MAX_SHARE - ROLL_SHARE) * lift_g)
				s["stage"] = TrailerStage.SPENT
		TrailerStage.FULL, TrailerStage.SPENT:
			if g < release:
				s["stage"] = TrailerStage.IDLE
	var cmd := Vector2.ZERO
	match s["stage"]:
		TrailerStage.PULSE:
			cmd = Vector2(TRAILER_PULSE, TRAILER_PULSE)
		TrailerStage.FULL:
			# The inside "largely unchanged" from the test pulse ([195]).
			cmd = Vector2(TRAILER_PULSE, 1.0) if lat_g >= 0.0 else Vector2(1.0, TRAILER_PULSE)
	return {"state": s, "cmd": cmd}
