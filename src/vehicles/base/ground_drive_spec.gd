class_name GroundDriveSpec
extends Resource
## Wheeled ground drive as data: wheels, what drives and brakes them, suspension, tires,
## resistance. Pure data, read by WheelDrive, RayWheel and the retarder half of Drivetrain.
##
## Boat, drone and train declare none, so no WheelDrive is built; the plane has one but is not
## driven by it, since three undriven, braked, steered wheels are still a ground drive.
##
## Embedded per `<variant>_spec.tres` as a `[sub_resource]`, never standalone: an external resource
## would re-stale bakes on every tuning change.

@export_group("Wheels")
## Hub anchors in body space, order FL, FR, RL, RR (front = -Z, right = +X).
@export var wheel_positions := PackedVector3Array([
	Vector3(-0.78, -0.1, -1.25), Vector3(0.78, -0.1, -1.25),
	Vector3(-0.78, -0.1, 1.25), Vector3(0.78, -0.1, 1.25),
])
@export var wheel_radius := 0.32  ## physics radius, all four corners; gear-selection scale is separate (Drivetrain.road_radius)
@export var wheel_inertia := 1.2   ## kg*m^2 around the axle
@export var wheel_scene: PackedScene  ## optional visual scene under WheelFL..RR when the scene authors no wheel mesh; radius-normalized (scaled to radius 1.0), WheelDrive scales it to wheel_visual_radius
@export var wheel_scene_rear: PackedScene  ## optional rear-axle visual (tractor's big rears); null = wheel_scene
@export var wheel_visual_radius := 0.0  ## rendered radius, m; 0 = wheel_radius. Visual only — a mismatch is lifted/dropped to still meet the ground
@export var wheel_visual_radius_rear := 0.0  ## rendered rear-axle radius; 0 = wheel_visual_radius, visual only

@export_group("Driveline")
@export var driven_front := false
@export var driven_rear := true
@export var rear_diff_lockable := false  ## rear axle can rigidly lock at runtime (tractor); off elsewhere so diff_lock affects nothing else
@export var front_axle_engageable := false  ## front axle engages at runtime (tractor MFWD) instead of fixed by driven_front; off elsewhere
@export var retarder_equipped := false  ## driveline carries an auxiliary retarder (truck J1939 SPN 520); off elsewhere
## Torque bias ratio of the front axle's differential (`Differential.bias_capacity`): the slower
## wheel may take up to this many times the faster one's torque. 1 = open; a helical or plate LSD
## sits around 2-3. Only read while the axle is driven.
@export_range(1.0, 10.0) var diff_bias_front := 1.0
## The rear axle's, as `diff_bias_front`. The diff lock (`rear_diff_lockable`) overrides it with an
## unbounded coupling while held.
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
## Rear-axle rate; 0 = spring_rate (the wheel_visual_radius_rear precedent). A body whose rear
## carries a multiple of the front's load (a coupled tractor unit) is sized per axle here.
@export var spring_rate_rear := 0.0
## Rear-axle dampers; 0 = the front value x sqrt(rear_spring_rate() / spring_rate), which keeps
## the front's damping ratio on the stiffer axle at the same corner mass.
@export var damper_bump_rear := 0.0
@export var damper_rebound_rear := 0.0
## Anti-roll bar, N per metre of left/right compression difference on an axle (0 = none). Moves
## spring load between the two wheels of an axle without adding net vertical force, so it stiffens
## roll and leaves ride and pitch alone. Roll stiffness gained per axle is 2 x rate / spring_rate
## times what that axle's springs give.
@export var anti_roll_rate := 0.0
@export var max_suspension_force := 30000.0  ## N; clamp against deep-penetration catapults

@export_group("Tires")
## Slip -> grip factor, peaking around 0.10-0.15: x is the combined slip, the length of (slip
## ratio, `v_lat / |v_long|`) (`RayWheel.combined_slip_force`).
@export var grip_curve := PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.4, 0.9), Vector2(1.0, 0.8),
])
@export var mu_long := 1.05
@export var mu_lat := 0.95
## Fractional mu lost per DOUBLING of load past the corner's static share
## (`RayWheel.corner_mass * g`); 0 = grip exactly linear in load, so weight transfer cannot move
## the balance. Car 0.10, truck/van/trailers 0.08, tractor 0.12 (soft flotation tyres), plane 0.
@export_range(0.0, 0.5) var load_sensitivity := 0.0
@export_range(0.0, 1.0) var handbrake_grip := 1.0  ## rear lateral grip while handbrake is pulled (1 = no effect); arcade drift knob since handbrake_torque alone can't lock the rears

@export_group("Brakes")
@export var brake_torque := 1300.0     ## Nm per wheel on average; `brake_bias_front` splits it by axle
@export var handbrake_torque := 160.0  ## Nm per rear wheel — magnitudes encode the tested hierarchy: foot brake > drive force > handbrake (holds only below ~30% throttle)
## Share of the whole foot brake (`brake_torque` x wheel count) on the front axle, 0 = rear only;
## negative = every wheel `brake_torque`. A generated body takes the share its front axle can hold
## in a full-pedal stop (gen_kenney_vehicles `_derive_brakes`): an even split under-brakes the axle
## braking loads up.
@export_range(-1.0, 1.0) var brake_bias_front := -1.0
## Anti-lock brakes: the foot brake (and retarder) may not drive a wheel's braking slip past
## `RayWheel.ABS_SLIP`.
@export var abs_equipped := false
## Traction control, `abs_equipped`'s drive-side twin: the drive may not push a driven wheel's slip
## past `RayWheel.TCS_SLIP`. The bridge's `tcs_off` switches it off.
@export var tcs_equipped := false
## The foot brake engages the front axle (`front_axle_engageable`), as a fast tractor's rear-axle
## brakes do: braking the fronts through the shaft, never a brake of their own. Pairs with
## `brake_bias_front` 0.
@export var brake_engages_front_axle := false

@export_group("Resistance")
## Aerodynamic drag area in m^2 (Cd x frontal area), fed to `VehicleMath.aero_drag`. It never
## scales with mass, so a coupled rig's drag is the sum of both bodies' areas: a 32 t artic resists
## ~1.2x a rigid truck, not 4x. 0 means the plane, which runs its own drag through VehicleMath.
@export var drag_area := 0.0
@export var rolling_resistance := 0.0  ## `F = crr * N`; asphalt ~0.010-0.015 car, ~0.006-0.008 truck, ~0.020 lugged. N is read off the suspension each tick, not mass, so an airborne wheel resists nothing
## Aerodynamic downforce area in m^2 (Cl x frontal area), pushed down the body's own up axis via
## `VehicleMath.aero_downforce`; 0 means no wing. A force through the suspension, never a grip
## multiplier. Must pair with `drag_area` (`test_vehicle_catalog`); bounded only by
## `max_suspension_force` and `rest_length`.
@export var downforce_area := 0.0


@export_group("Steering lock")
## Maximum steered-wheel angle in degrees. `steer_speed` stays on VehicleSpec, as it also slews a
## rudder.
@export var max_steer_deg := 32.0
## At or above steer_falloff_speed the usable lock shrinks linearly to this fraction of
## max_steer_deg; 1.0 is a constant lock. It multiplies each body's own max_steer_deg: pick the
## degrees wanted at speed, then divide.
@export_range(0.0, 1.0) var min_steer_frac := 1.0
@export var steer_falloff_speed := 30.0  ## m/s at which min_steer_frac is fully reached


## Rear-axle spring rate, N/m: `spring_rate_rear`, or the front rate when it is 0.
func rear_spring_rate() -> float:
	return spring_rate_rear if spring_rate_rear > 0.0 else spring_rate


## Rear-axle bump damper, N*s/m: explicit, or the front damper scaled by sqrt(rate ratio) so the
## damping ratio c / (2 sqrt(k m)) is what the front has at the same corner mass.
func rear_damper_bump() -> float:
	return damper_bump_rear if damper_bump_rear > 0.0 else damper_bump * _rear_damper_scale()


## Rear-axle rebound damper, N*s/m; same rule as rear_damper_bump.
func rear_damper_rebound() -> float:
	return damper_rebound_rear if damper_rebound_rear > 0.0 			else damper_rebound * _rear_damper_scale()


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


## Origin height (m) above flat ground with every wheel just touching and the springs unloaded:
## `wheel_radius + rest_length` above the LOWEST wheel anchor (least y). 0.0 with no wheel
## positions, so a spawn placer can call it on any spec unguarded.
func rest_ride_height() -> float:
	if wheel_positions.is_empty():
		return 0.0
	var lowest_y := INF
	for p in wheel_positions:
		lowest_y = minf(lowest_y, p.y)
	return wheel_radius + rest_length - lowest_y
