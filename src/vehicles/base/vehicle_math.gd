class_name VehicleMath
extends RefCounted

## Pure math shared by the free-body vehicles (boat, drone, plane), which carry their own damping
## and attitude terms instead of leaning on RayWheel.
##
## The one-tick clamps (damper force <= moment * |vel| / delta) are the 60 Hz clamp rule in
## free-body form (src/vehicles/CLAUDE.md § Physics).


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


## Yaw moment of inertia (kg*m^2) off a dynamic index `k² / (a·b)`: `front_arm` and `rear_arm`
## are the COM's distances to the front and rear axles. An index of 1 is the two-mass car whose
## mass sits on its axles.
static func yaw_inertia(body_mass: float, index: float, front_arm: float, rear_arm: float) -> float:
	return index * body_mass * front_arm * rear_arm


## The centre of mass with a `payload` (kg) carried at `point`, both in the body's frame: the
## mass-weighted mean of `base_com` and `point`. No payload returns `base_com` exactly (no
## `x * m / m` rounding), and a massless total never divides by zero.
static func carried_com(base_com: Vector3, point: Vector3, base_mass: float,
		payload: float) -> Vector3:
	var m := maxf(base_mass, 0.0)
	var p := maxf(payload, 0.0)
	if p <= 0.0 or m + p <= 0.0:
		return base_com
	return (base_com * m + point * p) / (m + p)


## Body pitch in degrees, + = nose/bow up. Read straight from the basis.
static func pitch_deg(b: Basis) -> float:
	return rad_to_deg(asin(clampf((-b.z).y, -1.0, 1.0)))


## Body roll in degrees, + = right side down. atan2 stays stable through a full capsize.
static func roll_deg(b: Basis) -> float:
	return rad_to_deg(atan2(-b.x.y, b.y.y))


## True when the body's own up axis has fallen more than `threshold_deg` away from world up.
## The tilt half of "overturned" and nothing else: the dwell that separates a kerb strike from a
## rollover belongs to the caller. Combined pitch and roll, so a body on its nose counts too.
static func is_inverted(b: Basis, threshold_deg: float) -> bool:
	return b.y.dot(Vector3.UP) < cos(deg_to_rad(threshold_deg))


## World velocity of the world point `point` riding on `body`. `linear_velocity` is the CENTRE OF
## MASS's velocity, so the lever runs from the COM, never the origin: on a body whose COM sits off
## its origin the origin lever is out by `angular_velocity x (com - origin)`. Reads the declared
## `center_of_mass`, so the body is in CENTER_OF_MASS_MODE_CUSTOM (every vehicle and towed body
## is); `PhysicsDirectBodyState3D.get_velocity_at_local_position` is the same figure in any mode.
static func point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	return body.linear_velocity \
			+ body.angular_velocity.cross(point - body.global_transform * body.center_of_mass)


# --- road resistance (wheeled vehicles) --------------------------------------------------
## Declared resistance, not Godot's `default_linear_damp` (linear in v and an acceleration, so a
## 24 t trailer on an 8 t tractor would quadruple the rig's resistance instead of ~1.2x). Both
## terms below are mass-free, so an airborne wheel resists nothing.

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


## Anti-roll bar force (N, + = up) on the LEFT wheel of an axle; the right wheel takes the negative.
## Equal and opposite, so the bar moves load between the two corners without adding vertical force
## to the body. `rate` is N per metre of compression difference; 0 is no bar.
static func anti_roll_force(comp_l: float, comp_r: float, rate: float) -> float:
	return maxf(rate, 0.0) * (comp_l - comp_r)


## The compression (m) at which a bar's partner corner hangs with its tyre carrying nothing: where
## its spring `partner_spring` (N/m) balances the bar's pull off this corner's `comp_self`,
## `rate c / (k + rate)`. A partner reads no lower than this, touching or airborne, so the bar's
## force on this corner moves only the load the partner really has (its tyre cannot pull the
## ground), with no step as the partner lifts. 0 with no bar.
static func anti_roll_hang(comp_self: float, rate: float, partner_spring: float) -> float:
	var k := maxf(partner_spring, 0.0)
	if rate <= 0.0:
		return 0.0
	return rate * maxf(comp_self, 0.0) / (k + rate)


## Angular damping declared on `body` (1/s): REPLACEs the engine's default, so 0 is none and the
## yaw, roll and pitch bleed is the tyres' and dampers' alone. The wheeled bodies and trailers call it
## with their `VehicleSpec.angular_damping` (src/vehicles/CLAUDE.md § Physics).
static func declare_angular_damp(body: RigidBody3D, figure: float) -> void:
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = maxf(figure, 0.0)


## Rolling-resistance magnitude (N): `crr * N`. Pass the suspension force the springs reported
## this tick as `normal_load`, never `mass * g`. Applied per contact (`RayWheel.surface_drag_force`).
static func rolling_drag(crr: float, normal_load: float) -> float:
	return maxf(crr, 0.0) * maxf(normal_load, 0.0)


## Aero force on a wheeled body from the air it moves through (`wind` = `WindField.at`). The air
## is read in the body frame with its body-up part dropped: `u` along the nose, `w` to the right.
## Drag is `cda` on `u`, side force `cya` on `w`, both scaled by `|(u, w)|`, so the side term is
## `q * cya * sin(yaw)`. Each axis is one-tick clamped on `body_mass`, which never enters the force.
## Gated on the AIR speed, so a parked body in wind is pushed. Still air and straight running give
## `w = 0`: the plain drag term. Rolling resistance is not here: it acts at each contact
## (`RayWheel.surface_drag_force`).
static func air_force(vel: Vector3, wind: Vector3, basis: Basis, cda: float, cya: float,
		body_mass: float, delta: float) -> Vector3:
	var air := vel - wind
	var up := basis.y.normalized()
	air -= up * air.dot(up)
	var airspeed := air.length()
	if airspeed < RESIST_EPS or delta <= 0.0:
		return Vector3.ZERO
	var fwd := -basis.z.normalized()
	var right := basis.x.normalized()
	var u := air.dot(fwd)
	var w := air.dot(right)
	var q_over_v := 0.5 * AIR_DENSITY * airspeed
	var fu := minf(q_over_v * maxf(cda, 0.0) * absf(u), body_mass * absf(u) / delta)
	var fw := minf(q_over_v * maxf(cya, 0.0) * absf(w), body_mass * absf(w) / delta)
	return -fwd * signf(u) * fu - right * signf(w) * fw


## The body-space point (from the origin) between the front and rear axle stations (`z`) at which a
## vertical force puts `front_share` of itself on the front axle. Its height is irrelevant to a
## force along body-up, so y is 0.
static func downforce_point(front_z: float, rear_z: float, front_share: float) -> Vector3:
	return Vector3(0.0, 0.0, rear_z - clampf(front_share, 0.0, 1.0) * (rear_z - front_z))
