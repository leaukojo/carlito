class_name BrakeSizing
extends RefCounted
## What a body's declared brake hardware can do, as pure arithmetic over its spec: the figures
## `tools/gen_kenney_vehicles.gd` reports and `test_vehicle_catalog` asserts. Static axle loads off
## the wheel stations and the centre of mass (on the flat, or on `park_grade`'s slope), load-scaled
## mu at rest (`RayWheel.load_scaled_mu`).

const G := 9.8
## Laden mass (kg) up to which a body parks on the car / light-van grade (UN R13-H); heavier
## goods vehicles park on the heavy one (UN R13).
const LIGHT_MASS_KG := 3500.0
const PARK_GRADE_LIGHT := 0.20
const PARK_GRADE_HEAVY := 0.18
const PARK_SCAN_DEG := 0.1  ## angle step of `park_grade`'s scan


## Full-pedal foot-brake capacity in g at the body's own mass.
static func capacity_g(spec: VehicleSpec) -> float:
	return g_per_demand(spec, spec.mass)


## Deceleration (g) a full brake demand makes on `load_kg` resting on the body's wheels: its own
## mass, or a towing unit's coupled static load (its mass plus what the trailer puts on the
## coupling), or a trailer's bogie load.
static func g_per_demand(spec: VehicleSpec, load_kg: float) -> float:
	var gd := spec.ground_drive
	if gd == null or gd.wheel_radius <= 0.0 or load_kg <= 0.0:
		return 0.0
	return gd.brake_torque * gd.wheel_positions.size() / gd.wheel_radius / (load_kg * G)


## The axle pair off the wheel stations (front = -Z, `RayWheel.is_rear_z`): the foremost front and
## rearmost rear station z and each axle's wheel count.
static func axle_geometry(spec: VehicleSpec) -> Dictionary:
	var gd := spec.ground_drive
	var front_z := INF
	var rear_z := -INF
	var n_rear := 0
	for p in gd.wheel_positions:
		if RayWheel.is_rear_z(p.z):
			rear_z = maxf(rear_z, p.z)
			n_rear += 1
		else:
			front_z = minf(front_z, p.z)
	return {"front_z": front_z, "rear_z": rear_z, "n_rear": n_rear,
			"n_front": gd.wheel_positions.size() - n_rear}


## Share of the static weight on the front axle (1 with no rear axle, 0 with no front one).
static func _static_front_share(spec: VehicleSpec, ax: Dictionary) -> float:
	if int(ax["n_rear"]) == 0:
		return 1.0
	if int(ax["n_front"]) == 0:
		return 0.0
	var rear_z: float = ax["rear_z"]
	var front_z: float = ax["front_z"]
	return clampf((rear_z - spec.center_of_mass.z) / maxf(rear_z - front_z, 1e-3), 0.0, 1.0)


## Static normal load (N) on one wheel of each axle: x front, y rear. A body with one axle carries
## it all there.
static func wheel_loads(spec: VehicleSpec) -> Vector2:
	var ax := axle_geometry(spec)
	var weight := spec.mass * G
	var front_share := _static_front_share(spec, ax)
	return Vector2(weight * front_share / maxf(1.0, int(ax["n_front"])),
			weight * (1.0 - front_share) / maxf(1.0, int(ax["n_rear"])))


## Height (m) of the centre of mass over the contact plane, off the UNCOMPRESSED wheel station
## (`RayWheel`'s ray is `rest_length + wheel_radius` long): a few cm over the sagged height, which
## overstates weight transfer, the conservative side for a parking grade.
static func com_height(spec: VehicleSpec) -> float:
	var gd := spec.ground_drive
	if gd.wheel_positions.is_empty():
		return 0.0
	return spec.center_of_mass.y + gd.wheel_radius + gd.rest_length - gd.wheel_positions[0].y


## A wheel's longitudinal grip (N) at `n_load`, as RayWheel scales it against the even corner share.
static func wheel_grip(spec: VehicleSpec, n_load: float) -> float:
	var gd := spec.ground_drive
	var ref := spec.mass * G / maxf(1.0, gd.wheel_positions.size())
	return n_load * RayWheel.load_scaled_mu(gd.mu_long, n_load, ref, gd.load_sensitivity)


## How well the full foot brake holds the BODY still on the flat against full throttle in gear 1
## (`Drivetrain.stall_axle_torque`: the curve at the launch target, converter stall on most
## bodies, times a converter's stall torque ratio): what the wheels can hold back over what the
## driven tyres push, >= 1 holding.
## A driven wheel whose brake is under its drive pushes the body with `(D - B) / r`, at most its
## tyre's grip (past that it spins, a brake-stand burnout, and pushes with less); every other
## wheel's brake holds back through its own tyre. With both axles driven (an AWD centre, or a pedal
## that engages MFWD) the centre first carries an axle's shortfall to the other axle's spare brake,
## up to its capacity at the stall drive, as the coupled solve does
## (`WheelDrive._couple_differentials`): the body holds on its brake total.
static func stall_hold_margin(spec: VehicleSpec) -> float:
	var gd := spec.ground_drive
	if gd == null or gd.wheel_positions.is_empty() or gd.wheel_radius <= 0.0:
		return INF
	var ax := axle_geometry(spec)
	var n_front := int(ax["n_front"])
	var n_rear := int(ax["n_rear"])
	var front_driven := n_front > 0 and (gd.driven_front or gd.brake_engages_front_axle)
	var rear_driven := n_rear > 0 and (gd.driven_rear or gd.brake_engages_front_axle)
	var driven := (n_front if front_driven else 0) + (n_rear if rear_driven else 0)
	if driven == 0:
		return INF
	var axle_drive := absf(Drivetrain.stall_axle_torque(spec))
	var drive := axle_drive / driven
	# Per-wheel drive on each axle after the centre's transfer (floats: a Vector2 is float32).
	var d_front := drive if front_driven else 0.0
	var d_rear := drive if rear_driven else 0.0
	if front_driven and rear_driven:
		var capacity := INF if gd.centre_diff_rigid \
				else Differential.bias_capacity(axle_drive, gd.centre_diff_bias)
		# An axle's shortfall: its drive past its own brakes (negative: their spare).
		var b_front := gd.axle_brake_torque(false)
		var b_rear := gd.axle_brake_torque(true)
		var front_short := n_front * (drive - b_front)
		var rear_short := n_rear * (drive - b_rear)
		if front_short > 0.0 and rear_short < 0.0:
			var moved := minf(minf(front_short, -rear_short), capacity)
			d_front = b_front + (front_short - moved) / n_front
			d_rear = drive + moved / n_rear
		elif rear_short > 0.0 and front_short < 0.0:
			var moved := minf(minf(rear_short, -front_short), capacity)
			d_front = drive + moved / n_front
			d_rear = b_rear + (rear_short - moved) / n_rear
	var loads := wheel_loads(spec)
	var r := gd.wheel_radius
	var push := 0.0
	var resist := 0.0
	for p in gd.wheel_positions:
		var rear := RayWheel.is_rear_z(p.z)
		var grip := wheel_grip(spec, loads.y if rear else loads.x)
		var f := clampf(((d_rear if rear else d_front) - gd.axle_brake_torque(rear)) / r, -grip,
				grip)
		if f > 0.0:
			push += f
		else:
			resist -= f
	return INF if push <= 0.0 else resist / push


## The handbrake against one rear wheel's static grip: > 1 locks the rears at speed (they unload
## further under the stop).
static func rear_lock_ratio(spec: VehicleSpec) -> float:
	var gd := spec.ground_drive
	var grip := wheel_grip(spec, wheel_loads(spec).y)
	return INF if grip <= 0.0 else gd.handbrake_torque / (grip * gd.wheel_radius)


## Steepest grade (rise over run) the handbrake alone parks the body on, facing either way: each
## rear wheel holds the lesser of its brake (`handbrake_torque / r`) and its tyre's grip at the
## normal load the slope leaves it, against `m g sin(theta)`. A handbrake that locks the rears
## (`rear_lock_ratio` > 1) is tyre-limited here, worst facing downhill, where the slope moves weight
## off the rears (`com_height`). Scanned in PARK_SCAN_DEG steps, so exact to that step.
static func park_grade(spec: VehicleSpec) -> float:
	var gd := spec.ground_drive
	var ax := axle_geometry(spec)
	var n_rear := int(ax["n_rear"])
	if n_rear == 0 or gd.wheel_radius <= 0.0 or spec.mass <= 0.0:
		return 0.0
	var weight := spec.mass * G
	var rear_share := 1.0 - _static_front_share(spec, ax)
	var h_over_l := 0.0
	if int(ax["n_front"]) > 0:
		h_over_l = com_height(spec) / maxf(float(ax["rear_z"]) - float(ax["front_z"]), 1e-3)
	var ref := weight / gd.wheel_positions.size()
	var worst := INF
	# +1: nose up the slope, the rears downhill and gaining load; -1: nose down, the rears unloading.
	for facing: float in [1.0, -1.0]:
		var held_deg := 0.0
		var deg := PARK_SCAN_DEG
		while deg < 89.0:
			var theta := deg_to_rad(deg)
			var n_wheel := weight * clampf(cos(theta) * rear_share
					+ facing * sin(theta) * h_over_l, 0.0, 1.0) / n_rear
			var grip := n_wheel * RayWheel.load_scaled_mu(gd.mu_long, n_wheel, ref,
					gd.load_sensitivity)
			if n_rear * minf(gd.handbrake_torque / gd.wheel_radius, grip) < weight * sin(theta):
				break
			held_deg = deg
			deg += PARK_SCAN_DEG
		worst = minf(worst, tan(deg_to_rad(held_deg)))
	return worst


## The grade a parking brake must hold the laden body on: UN R13-H for cars and light vans, UN R13
## for heavier goods vehicles.
static func regulation_grade(mass: float) -> float:
	return PARK_GRADE_LIGHT if mass <= LIGHT_MASS_KG else PARK_GRADE_HEAVY
