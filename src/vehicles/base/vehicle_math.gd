class_name VehicleMath
extends RefCounted

## Pure math shared by the free-body vehicles (boat, drone, plane), which carry their own damping
## and attitude terms instead of leaning on RayWheel.
##
## The one-tick clamps are RayWheel's 60 Hz stability rule in free-body form: a damper may at most
## zero the motion it opposes within one tick, never reverse it. Do not weaken them or raise the
## tick.


## Linear damping force (or torque) against `vel`, clamped so one tick can at most zero it.
## `moment` is the mass or inertia the impulse acts on.
static func damped_force(vel: float, coeff: float, moment: float, delta: float) -> float:
	var tick_cap := moment * absf(vel) / delta
	return clampf(-coeff * vel, -tick_cap, tick_cap)


## `damped_force` in three dimensions, opposing `vel_vec`.
static func clamped_damper(vel_vec: Vector3, coeff: float, moment: float, delta: float) -> Vector3:
	var speed := vel_vec.length()
	if speed < 1e-6:
		return Vector3.ZERO
	var mag := minf(coeff * speed, moment * speed / delta)
	return -vel_vec / speed * mag


## `clamped_damper` against velocity relative to the air (`wind` = `WindField.at`). Still air
## means relative velocity equals velocity, which is what keeps every drag coefficient tuned
## against the absolute term valid. `axis` masks per-axis coefficients (the drone's horizontal
## against its vertical). Never for an angular damper: there is no air to be relative to.
static func air_damper(vel: Vector3, wind: Vector3, coeff: float, moment: float,
		delta: float, axis := Vector3.ONE) -> Vector3:
	return clamped_damper((vel - wind) * axis, coeff, moment, delta)


## Control authority 0..1 from flow over a control surface: no flow, no control. Linear in speed
## up to `speed_ref`. `wash_frac` is a propeller's own wash at full throttle, which lets a boat
## turn out of a dock from a standstill; a surface outside the prop stream passes 0.
static func flow_authority(speed: float, speed_ref: float, wash_frac := 0.0,
		throttle := 0.0) -> float:
	return clampf(absf(speed) / maxf(0.1, speed_ref)
			+ absf(throttle) * wash_frac, 0.0, 1.0)


## Yaw torque driving yaw rate toward `target_rate`, one-tick clamped and capped at `max_torque`.
static func yaw_torque(target_rate: float, current_rate: float, gain: float,
		moment: float, delta: float, max_torque: float) -> float:
	var err := target_rate - current_rate
	var tick_cap := moment * absf(err) / delta
	return clampf(clampf(gain * err, -tick_cap, tick_cap), -max_torque, max_torque)


## Moment of inertia (kg*m^2) of a box footprint: the clamp basis for the torque dampers above.
static func inertia_of(body_mass: float, dim_a: float, dim_b: float) -> float:
	return body_mass * (dim_a * dim_a + dim_b * dim_b) / 12.0


## Body pitch in degrees, + = nose/bow up. Read straight from the basis.
static func pitch_deg(b: Basis) -> float:
	return rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0)))


## Body roll in degrees, + = right side down. atan2 stays stable through a full capsize.
static func roll_deg(b: Basis) -> float:
	return rad_to_deg(atan2(-b.x.y, b.y.y))


# --- road resistance (wheeled vehicles) --------------------------------------------------
## Replaces Godot's default `physics/3d/default_linear_damp`, which is linear in v where real
## aero is quadratic, and an acceleration that scales with load: a 24 t trailer on an 8 t tractor
## would quadruple the rig's resistance instead of the ~1.2x a real artic makes. Both terms below
## are mass-free, so an airborne wheel resists nothing.

const AIR_DENSITY := 1.225  ## kg/m^3, sea level, no altitude/temperature term
const RESIST_EPS := 0.05    ## m/s floor below which resistance isn't applied (stops jitter)


## Aerodynamic drag magnitude (N): `0.5 * rho * Cd*A * v^2`. `cda` is the lumped Cd x frontal
## area, one number per vehicle.
static func aero_drag(speed: float, cda: float, rho := AIR_DENSITY) -> float:
	return 0.5 * rho * maxf(cda, 0.0) * speed * speed


## Aerodynamic downforce magnitude (N): the same form as drag, off the lift coefficient `cla`.
## A force the caller pushes the body down with, never a grip multiplier, so it is routed through
## the suspension and pays ride height and rolling resistance.
static func aero_downforce(speed: float, cla: float, rho := AIR_DENSITY) -> float:
	return aero_drag(speed, cla, rho)


## Rolling-resistance magnitude (N): `crr * N`. Pass the suspension force the springs reported
## this tick as `normal_load`, never `mass * g`.
static func rolling_drag(crr: float, normal_load: float) -> float:
	return maxf(crr, 0.0) * maxf(normal_load, 0.0)


## The two terms together as a force vector opposing `vel`, one-tick clamped like
## `clamped_damper`. `body_mass` is only the clamp basis; it enters neither term.
static func road_resistance(vel: Vector3, cda: float, crr: float, normal_load: float,
		body_mass: float, delta: float) -> Vector3:
	var speed := vel.length()
	if speed < RESIST_EPS or delta <= 0.0:
		return Vector3.ZERO
	var mag := aero_drag(speed, cda) + rolling_drag(crr, normal_load)
	return -vel / speed * minf(mag, body_mass * speed / delta)
