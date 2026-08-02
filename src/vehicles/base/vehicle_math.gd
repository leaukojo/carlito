class_name VehicleMath
extends RefCounted

## Pure math shared by the free-body vehicles (boat, drone, plane), which unlike the
## wheeled ones carry their own damping and attitude terms instead of leaning on RayWheel.
##
## Everything here is a static pure function with no engine state, tested in
## `tests/test_vehicle_math.gd`. The one-tick clamps are the 60 Hz stability discipline
## the whole project runs on (RayWheel's rule, in a free-body flavor): a damper may at
## most ZERO the motion it opposes within one tick, never reverse it. **Don't weaken
## them, and don't raise the tick.**


## Linear damping force (or torque — the plane applies it to rotation rates) against
## `vel`, clamped so one tick can at most zero the velocity it opposes. `moment` is the
## mass or inertia the impulse acts on.
static func damped_force(vel: float, coeff: float, moment: float, delta: float) -> float:
	var tick_cap := moment * absf(vel) / delta
	return clampf(-coeff * vel, -tick_cap, tick_cap)


## `damped_force` in three dimensions: a damper opposing `vel_vec`, magnitude-clamped the
## same way. Direction is exactly opposite the velocity.
static func clamped_damper(vel_vec: Vector3, coeff: float, moment: float, delta: float) -> Vector3:
	var speed := vel_vec.length()
	if speed < 1e-6:
		return Vector3.ZERO
	var mag := minf(coeff * speed, moment * speed / delta)
	return -vel_vec / speed * mag


## Yaw torque driving the yaw rate toward `target_rate`, one-tick clamped (the impulse
## can't overshoot the target rate within a tick) and hard-capped at `max_torque`.
static func yaw_torque(target_rate: float, current_rate: float, gain: float,
		moment: float, delta: float, max_torque: float) -> float:
	var err := target_rate - current_rate
	var tick_cap := moment * absf(err) / delta
	return clampf(clampf(gain * err, -tick_cap, tick_cap), -max_torque, max_torque)


## Representative moment of inertia (kg*m^2) of a box footprint, m (a^2 + b^2) / 12 — the
## clamp basis for the torque dampers above. Symmetric in the two dimensions, so the boat
## passes length/width and the flyers width/depth.
static func inertia_of(body_mass: float, dim_a: float, dim_b: float) -> float:
	return body_mass * (dim_a * dim_a + dim_b * dim_b) / 12.0


## Body pitch in degrees, + = nose/bow up. Read straight from the basis.
static func pitch_deg(b: Basis) -> float:
	return rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0)))


## Body roll in degrees, + = starboard (right) side down. atan2 keeps it stable through a
## full capsize/flip (contract range -180..180).
static func roll_deg(b: Basis) -> float:
	return rad_to_deg(atan2(-b.x.y, b.y.y))
