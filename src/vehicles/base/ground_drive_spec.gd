class_name GroundDriveSpec
extends Resource
## Wheeled ground drive as data: wheels, what drives and brakes them, suspension, tires,
## resistance. Boat, drone and train declare none; the plane's wheels are an undriven one.
## A `[sub_resource]` per `<variant>_spec.tres`: an external one re-stales bakes on every tune.

@export_group("Wheels")
## Hub anchors in body space, order FL, FR, RL, RR (front = -Z, right = +X).
@export var wheel_positions := PackedVector3Array([
	Vector3(-0.78, -0.1, -1.25), Vector3(0.78, -0.1, -1.25),
	Vector3(-0.78, -0.1, 1.25), Vector3(0.78, -0.1, 1.25),
])
@export var wheel_radius := 0.32  ## physics radius (m): the front axle, and every axle at `wheel_radius_rear` 0
@export var wheel_inertia := 1.2   ## kg*m^2 around the axle: the front's, and every axle's at `wheel_inertia_rear` 0
## Rear-axle physics radius (m); 0 = `wheel_radius`. Read through `axle_radius`.
@export var wheel_radius_rear := 0.0
## Rear-axle wheel inertia (kg*m^2); 0 = `wheel_inertia`. Read through `axle_inertia`.
@export var wheel_inertia_rear := 0.0
## Tread half-width (m) of the drawn tyre: the front axle, and every axle at `tyre_half_width_rear`
## 0. Read through `axle_half_width`: the contact cylinder's width (`RayWheel`), so > 0 on every body.
@export var tyre_half_width := 0.0
## Rear-axle tread half-width (m); 0 = `tyre_half_width`.
@export var tyre_half_width_rear := 0.0
@export var wheel_scene: PackedScene  ## optional visual scene under WheelFL..RR when the scene authors no wheel mesh; radius-normalized (scaled to radius 1.0), WheelDrive scales it to the axle's radius
@export var wheel_scene_rear: PackedScene  ## optional rear-axle visual (tractor's big rears); null = wheel_scene

@export_group("Driveline")
@export var driven_front := false
@export var driven_rear := true
@export var rear_diff_lockable := false  ## rear axle can rigidly lock at runtime (tractor); off elsewhere so diff_lock affects nothing else
@export var front_axle_engageable := false  ## front axle engages at runtime (tractor MFWD) instead of fixed by driven_front; off elsewhere
@export var retarder_equipped := false  ## driveline carries an auxiliary retarder (truck J1939 SPN 520); off elsewhere
## The retarder's hardware rating (Nm) at the gearbox output (`Drivetrain.retarder_rating`).
@export var retarder_rating_nm := 0.0
## Torque bias ratio of the front axle's differential (`Differential.bias_capacity`): the slower
## wheel may take up to this many times the faster one's torque. 1 = open; an LSD sits around 2-3.
@export_range(1.0, 10.0) var diff_bias_front := 1.0
## The rear axle's, as `diff_bias_front`; the diff lock overrides it while held.
@export_range(1.0, 10.0) var diff_bias_rear := 1.0
## Torque bias ratio between the axles, read whenever both are driven: 1 = an open centre, where
## the lighter axle caps the whole body; a Torsen-type centre sits around 3.
@export_range(1.0, 10.0) var centre_diff_bias := 1.0
## The axles are geared rigidly together with no centre diff (a tractor's MFWD): overrides
## `centre_diff_bias`. It winds the driveline up in tight turns, so only a body whose front axle
## can be disengaged carries it (`test_vehicle_catalog`).
@export var centre_diff_rigid := false

@export_group("Suspension")
@export var rest_length := 0.25     ## m of free ray travel below the hub anchor
@export var spring_rate := 22000.0  ## N/m (~1.3 Hz natural frequency at 300 kg/corner — 60 Hz-safe)
@export var damper_bump := 1800.0   ## N*s/m
@export var damper_rebound := 2400.0
## Rear-axle rate; 0 = spring_rate. For a rear carrying a multiple of the front's load.
@export var spring_rate_rear := 0.0
## Rear-axle dampers; 0 = the front value scaled to keep its damping ratio (`rear_damper_bump`).
@export var damper_bump_rear := 0.0
@export var damper_rebound_rear := 0.0
## Anti-roll bar, N per metre of left/right compression difference on an axle (0 = none): stiffens
## roll, leaves ride and pitch alone.
@export var anti_roll_rate := 0.0
## Rear-axle bar rate; -1 = `anti_roll_rate`. 0 is real hardware (no rear bar), so not the sentinel.
@export var anti_roll_rate_rear := -1.0
## Front side-view link slope (contact patch to instant centre): a tyre force `F` puts
## `-F * anti_dive_slope` through the links, so the body pitches less. `h / wheelbase` = 100 %.
@export var anti_dive_slope := 0.0
## The rear axle's, signed the other way (`+F * anti_squat_slope`).
@export var anti_squat_slope := 0.0
@export var max_suspension_force := 30000.0  ## N; clamp against deep-penetration catapults

@export_group("Tires")
## Slip -> grip factor, peaking around 0.10-0.15: x is the combined slip, the length of (slip
## ratio, `v_lat / |v_long|`) (`RayWheel.combined_slip_force`), the side slip read against its own
## peak (`RayWheel.lateral_peak_slip`).
@export var grip_curve := PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.4, 0.9), Vector2(1.0, 0.8),
])
@export var mu_long := 1.05
@export var mu_lat := 0.95
## The rear tyres' side grip as a multiple of `mu_lat`: a rear-tyre hardware fact (a wider or a
## larger rear tyre), 1.0 on equal tyres. Understeer is the bar split and the tyre's load laws
## (`docs/vehicles.md` § Balance).
@export var rear_lat_grip := 1.0
## Twin tyres on each rear corner (a dual-rear-wheel van or truck): each carries half the corner's
## load, so the side grip and the cornering-stiffness law read at half load (`RayWheel.tyre_share`):
## the pair's peak is `1 + load_sensitivity` over one tyre's, its stiffness `2 C(L / 2)`. Lateral
## only: the longitudinal budget, the brake split and the launch keep one tyre's figures.
@export var rear_twin_tyres := false
## Fractional mu lost per DOUBLING of load past the corner's static share
## (`RayWheel.corner_mass * g`); 0 = grip exactly linear in load, so weight transfer cannot move
## the balance. Car 0.10, truck/van/trailers 0.08, tractor 0.12 (soft flotation tyres), plane 0.
## The cars' 0.10 reads low against sourced tyres (`docs/vehicles.md` § Balance); raising it
## re-derives the brake split.
@export_range(0.0, 0.5) var load_sensitivity := 0.0
## The load at which the tyre's cornering stiffness peaks, as a multiple of the corner's static
## share (Magic Formula `PKY2 * Fz0 / ref`, `RayWheel.cornering_load_shape`): a heavier wheel gives
## less stiffness per newton. 0 = off, stiffness follows `mu(L) * L`. A family tyre figure, like
## `load_sensitivity`; it moves only the slip at which the side force peaks, never the peak.
@export_range(0.0, 6.0) var cornering_peak_load := 0.0

@export_group("Brakes")
## Full-pedal foot-brake capacity, Nm per wheel on average: the hardware's rating, more than the
## tyre can use. `brake_bias_front` splits it by axle.
@export var brake_torque := 1300.0
## Parking-brake torque, Nm per rear wheel, no ABS; sized by `BrakeSizing`.
@export var handbrake_torque := 160.0
## Park pawl strength, Nm per driven wheel while the gearbox sits in P (`Drivetrain.GEAR_P`); 0 =
## no pawl, and a P request reads as N. A steel tooth: sized past the tyre, so the tyre slips first.
@export var park_pawl_torque := 0.0
## Share of the whole foot brake (`brake_torque` x wheel count) on the front axle, 0 = rear only;
## negative = every wheel `brake_torque`. Generated bodies: gen_kenney_vehicles `_front_brake_share`.
@export_range(-1.0, 1.0) var brake_bias_front := -1.0
## Anti-lock brakes: the foot brake (and retarder) may not drive a wheel's braking slip past
## `RayWheel.ABS_SLIP`.
@export var abs_equipped := false
## Traction control, `abs_equipped`'s drive-side twin: the drive may not push a driven wheel's slip
## past `RayWheel.TCS_SLIP`. `VehicleInput.tcs_off` switches it off (bridge or local setting).
@export var tcs_equipped := false
## Foot-brake hold against roll-back on a grade pull-away (`HillHold`). ASSIST: hill-start assist;
## STANDSTILL: a powershift tractor's. COMPROMISE: a real tractor holds in the transmission; a
## gearbox-output lock here is solved before the coupling, so the drive would creep against it.
@export var hill_hold := HillHold.Kind.NONE
## ASSIST's timeout (s): the hold lets go this long after the brake's release whatever the drive
## carries (Honda's ~1 s on a car, Volvo's 3 s on a truck). STANDSTILL has none.
@export var hill_hold_s := 0.0
## The foot brake engages the front axle, braking the fronts through the shaft (a fast tractor).
## Pairs with `brake_bias_front` 0.
@export var brake_engages_front_axle := false

@export_group("Resistance")
## Aerodynamic drag area in m^2 (Cd x frontal area); never scales with mass. 0 = the plane's own.
@export var drag_area := 0.0
@export var rolling_resistance := 0.0  ## `F = crr * N`; asphalt ~0.010-0.015 car, ~0.006-0.008 truck, ~0.020 lugged. N is read off the suspension each tick, not mass, so an airborne wheel resists nothing
## Aerodynamic downforce area in m^2 (Cl x frontal area); 0 = no wing. A force through the
## suspension, never a grip multiplier; pairs with `drag_area` (`test_vehicle_catalog`).
@export var downforce_area := 0.0


@export_group("Steering lock")
## The bicycle (mean) angle's lock in degrees; with `ackermann` the inner wheel turns past it
## (`steer_speed` is on VehicleSpec).
@export var max_steer_deg := 32.0
## Ackermann fraction (`WheelDrive.ackermann_angle`): 0 = parallel steer, 1 = every steered wheel's
## axis through one turn centre on the rear axle line.
@export_range(0.0, 1.0) var ackermann := 0.0
## Fraction of max_steer_deg left at steer_falloff_speed, linear in between; 1.0 = constant lock.
@export_range(0.0, 1.0) var min_steer_frac := 1.0
@export var steer_falloff_speed := 30.0  ## m/s at which min_steer_frac is fully reached


## Rear-axle spring rate, N/m: `spring_rate_rear`, or the front rate when it is 0.
func rear_spring_rate() -> float:
	return spring_rate_rear if spring_rate_rear > 0.0 else spring_rate


## Rear-axle anti-roll bar rate, N/m: `anti_roll_rate_rear`, or the front rate when it is negative.
func rear_anti_roll_rate() -> float:
	return anti_roll_rate_rear if anti_roll_rate_rear >= 0.0 else anti_roll_rate


## Either axle carries a bar, so the wheels need their partners (`RayWheel.pair_axles`).
func has_anti_roll_bar() -> bool:
	return anti_roll_rate > 0.0 or rear_anti_roll_rate() > 0.0


## Rear-axle bump damper, N*s/m: explicit, or the front damper scaled by sqrt(rate ratio) so the
## damping ratio c / (2 sqrt(k m)) is what the front has at the same corner mass.
func rear_damper_bump() -> float:
	return damper_bump_rear if damper_bump_rear > 0.0 else damper_bump * _rear_damper_scale()


## Rear-axle rebound damper, N*s/m; same rule as rear_damper_bump.
func rear_damper_rebound() -> float:
	return damper_rebound_rear if damper_rebound_rear > 0.0 \
			else damper_rebound * _rear_damper_scale()


func _rear_damper_scale() -> float:
	return sqrt(rear_spring_rate() / spring_rate) if spring_rate > 0.0 else 1.0


## Foot-brake torque (Nm) at one wheel of the front or rear axle: `brake_torque` until a bias is
## declared, then that axle's share of the whole foot brake spread over its own wheels.
func axle_brake_torque(rear: bool) -> float:
	if brake_bias_front < 0.0:
		return brake_torque
	var n_rear := 0
	for p in wheel_positions:
		if RayWheel.is_rear_z(p.z):
			n_rear += 1
	var n_front := wheel_positions.size() - n_rear
	var total := brake_torque * wheel_positions.size()
	if rear:
		return total * (1.0 - brake_bias_front) / maxf(1.0, n_rear)
	return total * brake_bias_front / maxf(1.0, n_front)


## Physics radius (m) of a front or rear wheel: `wheel_radius_rear`, or the front's at 0.
func axle_radius(rear: bool) -> float:
	return wheel_radius_rear if rear and wheel_radius_rear > 0.0 else wheel_radius


## Wheel inertia (kg*m^2) of a front or rear wheel: `wheel_inertia_rear`, or the front's at 0.
func axle_inertia(rear: bool) -> float:
	return wheel_inertia_rear if rear and wheel_inertia_rear > 0.0 else wheel_inertia


## Tread half-width (m) of a front or rear tyre: `tyre_half_width_rear`, or the front's at 0.
func axle_half_width(rear: bool) -> float:
	return tyre_half_width_rear if rear and tyre_half_width_rear > 0.0 else tyre_half_width


## The radius (m) the final drive is quoted at: the rear axle's when it is driven, else the
## front's. A wheel at radius `r` turns `r / drive_radius()` times the shaft (`WheelDrive`'s shaft
## frame).
func drive_radius() -> float:
	return axle_radius(driven_rear)


## Origin height (m) above flat ground with every wheel just touching and the springs unloaded:
## the most any wheel asks, `axle_radius + rest_length` above its anchor. 0.0 with no wheel
## positions, so a spawn placer can call it on any spec unguarded.
func rest_ride_height() -> float:
	if wheel_positions.is_empty():
		return 0.0
	var height := -INF
	for p in wheel_positions:
		height = maxf(height, axle_radius(RayWheel.is_rear_z(p.z)) + rest_length - p.y)
	return height
