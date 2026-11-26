class_name ChassisReading
extends RefCounted
## What each tyre does this tick, read off the solve that produced it (standing rule 3), for the
## chassis view: per wheel its place, load, grip in use, force and spin; per body its acceleration,
## where its load centres and how its differentials ran. Built fresh after the tick (`of`); it holds
## nothing between ticks and smooths nothing. Plan-view vectors are body xz: x + = right, y (the
## body's z) + = rear, so front is up on a screen. A coupled body (`TowHost`) is read beside it in
## its own body xz (`towed`), placed on the towing unit's by `frame`.

## Between samples of a swept arc (`swept_box`), rad: the box falls short by at most
## 1 - cos(SWEEP_STEP / 2) of a radius, under 0.1 %.
const SWEEP_STEP := deg_to_rad(5.0)

## A differential as it ran this tick (`diff_state`).
enum Diff {
	NONE,     ## no differential ran there
	OPEN,     ## it moved nothing between its outputs: open, or biasing with nothing to move
	BIASING,  ## it moved torque between its outputs, within its capacity
	LOCKED,   ## locked or rigid: its outputs turn as one
}


## One wheel's reading.
class WheelReading:
	var anchor := Vector2.ZERO  ## m, body xz of the hub's anchor (`RayWheel.anchor`)
	var in_contact := false
	var normal_load := 0.0      ## N, the corner's whole load (`RayWheel.suspension_force`); 0 lifted
	var grip_use := 0.0         ## share of the friction ellipse in use, 0..1 (`ChassisReading.grip_use`)
	var past_peak := false      ## sliding: combined slip past the curve's peak (`RayWheel.past_peak`)
	var force := Vector2.ZERO   ## N, body xz: the tyre's push on the car, turned with its steer
	var long_slip := 0.0        ## signed slip ratio, + = spinning, - = locking (`RayWheel.long_slip`)
	var driven := false
	var steered := false
	var rear := false           ## in the rear axle group (`RayWheel.is_rear`): which diff it is on
	var braked := false         ## a brake worked on it this tick (`RayWheel.brake_spin` > 0)
	var abs_held := false      ## the anti-lock held its brake back (`RayWheel.abs_active`)
	var tcs_held := false       ## traction control held its drive back (`RayWheel.tcs_active`)
	var esc_braked := false     ## stability control braked it (`WheelDrive.esc_brakes`)


var wheels: Array[WheelReading] = []
var com := Vector2.ZERO               ## m, body xz of the centre of mass
var accel := Vector2.ZERO             ## m/s², body xz: telemetry's `acc_lat`, `-acc_long`
var load_centre := Vector2(NAN, NAN)  ## m, body xz where the normal loads centre; NAN with none
var mass := 0.0                       ## kg, the body's (`RigidBody3D.mass`); 0 unread
var front_diff := Diff.NONE
var rear_diff := Diff.NONE
var centre_diff := Diff.NONE
## The body coupled behind this one (`TowHost.trailer`), null with none; its own reading.
var towed: ChassisReading = null
## This body's xz into the towing unit's: IDENTITY on the unit, the live articulation on a towed one.
var frame := Transform2D.IDENTITY
## m, towing-unit xz: a towed body's coupling datum (`TowHost.marker_local`), where it swings.
var coupling := Vector2.ZERO
## rad, the coupling's yaw stop either way (`CouplingProfile.yaw_deg`); 0 on the unit.
var yaw_stop := 0.0


## `vehicle`'s reading this tick; null on a body with no wheels (boat, plane, drone, train). The
## first of `hosts` (its `TowHost`s) with a wheeled body coupled adds that body's (`towed`): a
## machine tows one body at a time. Both must be in the tree, where a transform reads.
static func of(vehicle: BaseVehicle, hosts: Array[TowHost] = []) -> ChassisReading:
	if vehicle.drive == null or vehicle.drive.wheels.is_empty():
		return null
	var r := read(vehicle.drive, vehicle.telemetry, vehicle.center_of_mass)
	r.mass = vehicle.mass
	if not vehicle.is_inside_tree():
		return r
	for host in hosts:
		if is_instance_valid(host) and host.is_coupled() and host.trailer.is_inside_tree() \
				and not host.trailer.wheels.is_empty():
			r.towed = of_towed(host, vehicle)
			break
	return r


## The reading of the body coupled on `host`, a coupling on `unit`: its wheels in its own body xz,
## no differentials (a towed body has no drive) and no acceleration (the unit's arrow is the rig's).
static func of_towed(host: TowHost, unit: Node3D) -> ChassisReading:
	var body := host.trailer
	var r := ChassisReading.new()
	_read_wheels(r, body.wheels, PackedByteArray())
	r.com = Vector2(body.center_of_mass.x, body.center_of_mass.z)
	r.mass = body.mass
	r.frame = towed_frame(unit.global_transform, body.global_transform)
	var datum := host.marker_local()
	r.coupling = Vector2(datum.x, datum.z)
	r.yaw_stop = deg_to_rad(host.profile().yaw_deg)
	return r


## The reading of `drive`'s wheels and differentials, with the body's acceleration out of
## `telemetry` and its centre of mass `body_com` (body space).
static func read(drive: WheelDrive, telemetry: VehicleTelemetry, body_com: Vector3) -> ChassisReading:
	var r := ChassisReading.new()
	var esc := PackedByteArray()
	for i in drive.wheels.size():
		esc.append(1 if drive.esc_brakes(i) else 0)
	_read_wheels(r, drive.wheels, esc)
	r.com = Vector2(body_com.x, body_com.z)
	r.accel = Vector2(telemetry.acc_lat, -telemetry.acc_long)
	r.front_diff = diff_state(drive.diff_capacity.x, drive.diff_moved.x)
	r.rear_diff = diff_state(drive.diff_capacity.y, drive.diff_moved.y)
	r.centre_diff = diff_state(drive.diff_capacity.z, drive.diff_moved.z)
	return r


## `rays`' readings into `r`, and their load centre; `esc` flags the ones stability control braked
## (`WheelDrive.esc_brakes`), empty for none.
static func _read_wheels(r: ChassisReading, rays: Array[RayWheel], esc: PackedByteArray) -> void:
	var points := PackedVector2Array()
	var loads := PackedFloat64Array()
	for i in rays.size():
		var wr := wheel_reading(rays[i], i < esc.size() and esc[i] != 0)
		r.wheels.append(wr)
		points.append(wr.anchor)
		loads.append(wr.normal_load)
	r.load_centre = centre_of_loads(points, loads)


## One wheel's reading off its last tick; `esc_braked` is its owner's (`WheelDrive.esc_brakes`).
static func wheel_reading(w: RayWheel, esc_braked := false) -> WheelReading:
	var wr := WheelReading.new()
	wr.anchor = Vector2(w.anchor.x, w.anchor.z)
	wr.in_contact = w.in_contact
	wr.normal_load = w.suspension_force if w.in_contact else 0.0
	wr.grip_use = grip_use(Vector2(w.force_long, w.force_lat), w.patch_budget())
	wr.past_peak = w.past_peak()
	wr.force = wheel_to_body(Vector2(w.force_long, w.force_lat), w.steer_angle)
	wr.long_slip = w.long_slip
	wr.driven = w.driven
	wr.steered = w.steered
	wr.rear = w.is_rear
	wr.braked = w.brake_spin > 0.0
	wr.abs_held = w.abs_active
	wr.tcs_held = w.tcs_active
	wr.esc_braked = esc_braked
	return wr


## Pure: the share of the friction ellipse a tyre force uses, `|(F_long / B_long, F_lat / B_lat)|`,
## `force` and `budget` both (along the wheel, across it) in N. 0 with either budget at 0 (lifted).
static func grip_use(force: Vector2, budget: Vector2) -> float:
	if budget.x <= 0.0 or budget.y <= 0.0:
		return 0.0
	return Vector2(force.x / budget.x, force.y / budget.y).length()


## Pure: a tyre force (x along the wheel, + forward; y across it, + right; N) as body xz, the wheel
## steered `steer` rad (+ = left, `RayWheel.steer_angle`).
static func wheel_to_body(force: Vector2, steer: float) -> Vector2:
	var forward := Vector2(-sin(steer), -cos(steer))
	var right := Vector2(cos(steer), -sin(steer))
	return forward * force.x + right * force.y


## Pure: where normal loads `loads` (N) at body-xz `points` (m) centre; NAN with no load at all.
static func centre_of_loads(points: PackedVector2Array, loads: PackedFloat64Array) -> Vector2:
	var total := 0.0
	var moment := Vector2.ZERO
	for i in points.size():
		total += loads[i]
		moment += points[i] * loads[i]
	if total <= 0.0:
		return Vector2(NAN, NAN)
	return moment / total


## Pure: a differential's state off its capacity and the torque it moved this tick
## (`WheelDrive.diff_capacity`, `diff_moved`; NAN where none ran).
static func diff_state(capacity: float, moved: float) -> Diff:
	if is_nan(capacity):
		return Diff.NONE
	if is_inf(capacity):
		return Diff.LOCKED
	return Diff.BIASING if moved != 0.0 else Diff.OPEN


## Pure: the bounding box of `anchors` (body xz, m); an empty Rect2 with none.
static func anchor_box(anchors: PackedVector2Array) -> Rect2:
	if anchors.is_empty():
		return Rect2()
	var box := Rect2(anchors[0], Vector2.ZERO)
	for p in anchors:
		box = box.expand(p)
	return box


## Pure: a towed body's xz into the towing unit's, off both bodies' transforms, flattened onto the
## unit's plane: turned by the articulation (`Articulation.articulation_angle`), placed at the towed
## body's origin (its kingpin or drawbar eye).
static func towed_frame(unit: Transform3D, body: Transform3D) -> Transform2D:
	var at := unit.affine_inverse() * body.origin
	return Transform2D(Articulation.articulation_angle(unit, body), Vector2(at.x, at.z))


## Pure: the box `anchors` (a towed body's xz, m) reach with its origin at `origin` (the towing
## unit's xz), turned anywhere within ±`max_yaw` rad: sampled every SWEEP_STEP and at both stops.
static func swept_box(anchors: PackedVector2Array, origin: Vector2, max_yaw: float) -> Rect2:
	if anchors.is_empty():
		return Rect2()
	var box := Rect2(origin + anchors[0], Vector2.ZERO)
	var steps := maxi(1, ceili(2.0 * max_yaw / SWEEP_STEP))
	for k in steps + 1:
		var yaw := -max_yaw + 2.0 * max_yaw * k / steps
		for p in anchors:
			box = box.expand(origin + p.rotated(yaw))
	return box
