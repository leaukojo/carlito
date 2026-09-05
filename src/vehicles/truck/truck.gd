class_name TruckVehicle
extends BaseVehicle
## Truck (J1939 chassis). Owns per-tick subsystem state the base has no concept of: two air brake
## reservoirs and the chassis PTO. Plugs into the two base seams only.
##
## Air pressure gates the brakes: below TruckTelemetry.AIR_SPRING_BRAKE_BAR on either circuit the
## spring brakes apply and the truck cannot move. The retarder is a real driveline torque on the
## driven axle, rated below brake_torque so brake > peak drive > handbrake still holds; math lives
## on Drivetrain / WheelDrive (gated by retarder_equipped), this class only reads back what ran.
## Spring brakes write wheel `omega` directly — a kinematic lock, unlike the retarder's torque.

## engine_load added while the chassis PTO is engaged (the tractor's parasitic term, reused — the
## PTO also powers the body network here, see body_bus).
@export var pto_load := 0.35

## CiA 422 refuse body unit, null on a truck with no body. See _find_rig.
var _body: RefuseBody = null
var _arm: MeshInstance3D = null      ## front-loader arm; body_pos reads back off its rotation
var _trash: MeshInstance3D = null    ## refuse pile in the hopper; height shows hopper_load
var _trash_full_y := 0.0             ## authored pile pose = full hopper
var _trash_empty_y := 0.0            ## measured off the pile's own mesh
var _mass_applied := 0.0             ## payload currently written into `mass`
var _last_body_cmd := 0              ## previous tick's body_cmd, so the notice fires on the edge

## Told to the driver when the body stalk is worked with the PTO out or the parking brake off.
## Fires on the press, not while inhibited, so it explains rather than nags.
const BODY_INTERLOCK_NOTICE := "ENGAGE THE PTO AND HANDBRAKE FIRST"
const BODY_INTERLOCK_NOTICE_DWELL_S := 5.0


func _make_telemetry() -> VehicleTelemetry:
	return TruckTelemetry.new()


func _ready() -> void:
	super._ready()
	_find_rig()


## Geometry is the declaration: no `arm` mesh means no body unit, honest zeros on all signals.
## Don't claim a body with no arm via a spec flag — rule 3 forbids it.
func _find_rig() -> void:
	_arm = get_node_or_null(^"Model/arm") as MeshInstance3D
	_trash = get_node_or_null(^"Model/body/trash") as MeshInstance3D
	if _arm == null:
		return
	_body = RefuseBody.new()
	if _trash != null:
		# Authored heaped = full hopper; empty is one pile-height lower, measured off the mesh.
		_trash_full_y = _trash.position.y
		_trash_empty_y = _trash_full_y - _trash.mesh.get_aabb().size.y
	_pose_rig()


## No `arm` mesh means no body unit, so neither the X-key body stalk nor the chassis PTO has
## anything to show. PTO is keyed to the body (not offered on every truck) because a PTO with
## nothing plugged in moves engine_load and nothing visible; it's also what powers the body network
## (RefuseBody.bus_up), so without this the arm can't be raised from touch at all.
func vehicle_capabilities() -> Dictionary:
	var caps := super()
	caps["body_cmd"] = _body != null
	caps["pto"] = _body != null
	return caps


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as TruckTelemetry
	var running := input.key == InputRouter.KEY_IGNITION

	# Air first: this tick's pressures are what the spring-brake gate below decides on. The second
	# consumer is asked for BEFORE the step, so a trailer coupled this tick pays for its charge the
	# same tick the gate reads.
	var aux_air := _aux_air_draw(delta)
	t.air_primary = TruckTelemetry.air_step(t.air_primary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_PRIMARY, aux_air)
	t.air_secondary = TruckTelemetry.air_step(t.air_secondary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_SECONDARY, aux_air)

	var pto_on := input.pto and running
	t.pto_state = pto_on
	# The GOVERNED throttle, not the pedal: engine_load off the request would report a load a
	# cut engine isn't making. See Drivetrain.applied_throttle.
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, drivetrain.applied_throttle, spec, pto_on, pto_load))

	# Read out of the sim: whatever the rear springs actually held up this tick, in kg — not a
	# mass lookup, so weight transfer and a laden body/trailer move it as consequences.
	t.axle_load = TruckTelemetry.axle_load_kg(_rear_suspension_force())

	# Straight off the driveline, like diff_lock_state: what ran this tick, not what was asked.
	t.retarder_state = roundi(Drivetrain.retarder_pct(
			retarder_torque_applied, _retarder_rating_total()))

	# Nothing on the fifth wheel: real false/0 on all four bus signals. SemiTractor overwrites
	# AFTER its trailer's wheels have ticked, so the loads/slip published are this tick's.
	t.clear_trailer_bus()

	_tick_body(t, input, pto_on, running, delta)

	# Spring brakes go on LAST, after retarder_state is read, and do NOT zero it: the retarder
	# torque ran earlier this tick and RayWheel integrated it, so the pin supersedes rather than
	# retracts it. (Narrow overlap: demand already fades to 0 below RETARDER_CUTOUT_MS.)
	if TruckTelemetry.spring_brakes_applied(t.air_primary, t.air_secondary):
		_apply_spring_brakes()


## What else is drawing on the air reservoirs this tick (air_step's `aux01`). Nothing on a truck
## with only its own brakes on the supply; SemiTractor overrides with a charging trailer, through
## the air model rather than a term beside it. Called once per tick, before the air step.
func _aux_air_draw(_delta: float) -> float:
	return 0.0


## CiA 422 body network + CiA 413 gateway. Rig posed first; body_pos computed back out of the
## mesh's rotation so picture and number don't drift. Hopper is mass only; don't add laden terms
## to axle_load or engine_load. The two report it unequally; axle_load is the bar after dump.
func _tick_body(t: TruckTelemetry, input: VehicleInput, pto_on: bool, running: bool,
		delta: float) -> void:
	if _body == null:
		# No refuse body: a real zero every tick, never a gap.
		t.body_state = RefuseBody.State.STOWED
		t.body_pos = 0
		t.body_inhibit = false
		t.body_bus = false
		t.hopper_load = 0
		return

	# The gateway: computed from CHASSIS state, published on the BODY network — road speed and
	# parking brake off this vehicle, PTO off the chassis driveline.
	var bus := RefuseBody.bus_up(running, pto_on)
	var inhibit := RefuseBody.is_inhibited(t.speed, input.handbrake, bus)

	_warn_if_body_interlocked(input, pto_on)
	_body.step(input.body_cmd, inhibit, delta)
	_pose_rig()

	t.body_state = _body.state
	t.body_pos = roundi(RefuseBody.arm_pos_pct(_arm.rotation.x))
	t.body_inhibit = inhibit
	t.body_bus = bus
	t.hopper_load = roundi(_body.hopper)

	# Only write `mass` when the payload actually changed (a physics-server property; the hopper
	# moves once per dump cycle, not once per tick).
	var payload := RefuseBody.hopper_mass_kg(_body.hopper)
	if not is_equal_approx(payload, _mass_applied):
		_mass_applied = payload
		mass = spec.mass + payload


## Say WHY the body stalk did nothing, on the press that did nothing. Covers only the two
## conditions the driver can act on (PTO, parking brake) — road speed clears itself by stopping.
## Fires on the EDGE of the command, only for moves that ask the arm to act (cycling to Idle is
## silent).
func _warn_if_body_interlocked(input: VehicleInput, pto_on: bool) -> void:
	var cmd := input.body_cmd
	var edge := cmd != _last_body_cmd
	_last_body_cmd = cmd
	if not edge or (cmd != RefuseBody.Cmd.LIFT and cmd != RefuseBody.Cmd.DUMP):
		return
	if pto_on and input.handbrake > RefuseBody.PARK_BRAKE_MIN:
		return
	GameState.notice.emit(BODY_INTERLOCK_NOTICE, BODY_INTERLOCK_NOTICE_DWELL_S)


## Pose the arm and the refuse pile from the body unit. Called after every step and on respawn.
func _pose_rig() -> void:
	if _body == null:
		return
	_arm.rotation.x = RefuseBody.arm_angle_rad(_body.pos)
	if _trash == null:
		return
	# The pile IS hopper_load: hidden when empty, rising as it fills.
	_trash.visible = _body.hopper > 0.0
	_trash.position.y = lerpf(_trash_empty_y, _trash_full_y, _body.hopper / 100.0)


## The retarder's rated torque across the whole driven rear axle — the 100 % end of the signal.
func _retarder_rating_total() -> float:
	if spec.ground_drive == null or not spec.ground_drive.retarder_equipped:
		return 0.0
	var count := 0
	for w in wheels:
		if w.is_rear and w.driven:
			count += 1
	return Drivetrain.retarder_rating(spec.ground_drive.brake_torque) * count


## Spring brakes lock rear wheels (omega = 0) like WheelDrive._lock_rear_diff, a post-integration
## kinematic write. No torque can hold this truck (first-gear exceeds brake_torque). No ramp:
## losing air while rolling locks the axle in one tick.
func _apply_spring_brakes() -> void:
	for w in wheels:
		if w.is_rear:
			w.omega = 0.0


## Total suspension force carried by the rear axle this tick (N), straight off the wheels.
func _rear_suspension_force() -> float:
	var total := 0.0
	for w in wheels:
		if w.is_rear:
			total += w.suspension_force
	return total


## Recharge the reservoirs to spawn pressure: air is physical state, re-laid like the tractor's
## hitch. engine_hours and the odometer survive — they record the machine's life, not this drive.
## The refuse body is re-laid too, stowed with the hopper empty, which is also the only way to
## empty it, since the rig has no in-place tip.
func respawn() -> void:
	super.respawn()
	var t := telemetry as TruckTelemetry
	t.air_primary = TruckTelemetry.AIR_SPAWN_BAR
	t.air_secondary = TruckTelemetry.AIR_SPAWN_BAR
	t.retarder_state = 0
	if _body != null:
		_body.reset()
		_pose_rig()
		_mass_applied = 0.0
		mass = spec.mass
