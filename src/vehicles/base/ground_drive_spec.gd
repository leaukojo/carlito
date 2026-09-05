class_name GroundDriveSpec
extends Resource
## Wheeled ground drive as data: wheels, what drives and brakes them, suspension, tires,
## resistance. Pure data, read by WheelDrive, RayWheel and the retarder half of Drivetrain.
##
## Boat, drone and train declare none, so no WheelDrive is built; the plane has one but is not
## driven by it, since three undriven, braked, steered wheels are still a ground drive.
##
## Embedded per `<variant>_spec.tres` as a `[sub_resource]`, never standalone: an external
## resource would re-stale bakes on every tuning change.

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

@export_group("Suspension")
@export var rest_length := 0.25     ## m of free ray travel below the hub anchor
@export var spring_rate := 22000.0  ## N/m (~1.3 Hz natural frequency at 300 kg/corner — 60 Hz-safe)
@export var damper_bump := 1800.0   ## N*s/m
@export var damper_rebound := 2400.0
@export var max_suspension_force := 30000.0  ## N; clamp against deep-penetration catapults

@export_group("Tires")
## Slip -> grip factor, both axes: x is slip ratio (longitudinal) or slip angle in radians
## (lateral), peaking around 0.10-0.15.
@export var grip_curve := PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.4, 0.9), Vector2(1.0, 0.8),
])
@export var mu_long := 1.05
@export var mu_lat := 0.95
@export_range(0.0, 1.0) var handbrake_grip := 1.0  ## rear lateral grip while handbrake is pulled (1 = no effect); arcade drift knob since handbrake_torque alone can't lock the rears

@export_group("Brakes")
@export var brake_torque := 1300.0     ## Nm per wheel, all four
@export var handbrake_torque := 160.0  ## Nm per rear wheel — magnitudes encode the tested hierarchy: foot brake > drive force > handbrake (holds only below ~30% throttle)

@export_group("Resistance")
## Aerodynamic drag area in m^2 (Cd x frontal area), fed to `VehicleMath.aero_drag` as
## `0.5 * rho * Cd*A * v^2`. It never scales with mass, so a coupled rig's drag is the sum of both
## bodies' areas: a 32 t artic resists ~1.2x a rigid truck, not 4x. 0 means the plane, which runs
## its own drag through VehicleMath.
@export var drag_area := 0.0
@export var rolling_resistance := 0.0  ## `F = crr * N`; asphalt ~0.010-0.015 car, ~0.006-0.008 truck, ~0.020 lugged. N is read off the suspension each tick, not mass, so an airborne wheel resists nothing
## Aerodynamic downforce area in m^2 (Cl x frontal area), pushed down the body's own up axis via
## `VehicleMath.aero_downforce`; 0 means no wing. A force through the suspension, never a grip
## multiplier: it compresses the springs and RayWheel turns the bigger normal load into grip, so
## it costs ride height and gives a cornering limit that climbs with v^2. It must pair with
## `drag_area`, checked by `test_vehicle_catalog`, and is clamped only by `max_suspension_force`
## and `rest_length`.
@export var downforce_area := 0.0


@export_group("Steering lock")
## Maximum steered-wheel angle in degrees. Here rather than on VehicleSpec, since a lock means
## nothing without a wheel; `steer_speed` stays on the core spec, as it also slews a rudder.
@export var max_steer_deg := 32.0
## At or above steer_falloff_speed the usable lock shrinks linearly to this fraction of
## max_steer_deg; 1.0 is a constant lock. The fraction is not the setting, the absolute lock it
## leaves is, since it multiplies each body's own max_steer_deg. Pick the degrees wanted at speed,
## then divide.
@export_range(0.0, 1.0) var min_steer_frac := 1.0
@export var steer_falloff_speed := 30.0  ## m/s at which min_steer_frac is fully reached
