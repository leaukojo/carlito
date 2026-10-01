class_name TruckVehicle
extends BaseVehicle
## Truck (J1939 chassis). Owns per-tick subsystem state the base has none of: two air brake
## reservoirs and the chassis PTO. Plugs into the two base seams only.
##
## Air pressure gates the brakes: below TruckTelemetry.AIR_SPRING_BRAKE_BAR on either circuit the
## spring brakes apply and the truck cannot move. The retarder is a real driveline torque on the
## driven axle (math on Drivetrain / WheelDrive, gated by retarder_equipped); this class only reads
## back what ran. Spring brakes write wheel `omega` directly: a kinematic lock, not a torque.

## engine_load added while the chassis PTO is engaged (the tractor's parasitic term; the PTO also
## powers the body network, see body_bus).
@export var pto_load := 0.35

## CiA 422 refuse body unit, null on a truck with no body. See _find_rig.
var _body: RefuseBody = null
var _arm: MeshInstance3D = null      ## front-loader arm; body_pos reads back off its rotation
var _trash: MeshInstance3D = null    ## refuse pile in the hopper; height shows hopper_load
var _trash_full_y := 0.0             ## authored pile pose = full hopper
var _trash_empty_y := 0.0            ## measured off the pile's own mesh
var _mass_applied := 0.0             ## payload currently written into `mass`
var _last_body_cmd := 0              ## previous tick's body_cmd, for the notice edge
var _spring_brakes_were_applied := false  ## last tick's gate, for the notice edge

## Told to the driver when the body stalk is worked with the PTO out or the parking brake off.
## Fires on the press, not while inhibited.
const BODY_INTERLOCK_NOTICE := "ENGAGE THE PTO AND HANDBRAKE FIRST"
const BODY_INTERLOCK_NOTICE_DWELL_S := 5.0

## Told to the driver the tick the spring-brake gate applies; once per application.
const SPRING_BRAKE_NOTICE := "SPRING BRAKES APPLIED - AIR LOW"
const SPRING_BRAKE_NOTICE_DWELL_S := 5.0


func _make_telemetry() -> VehicleTelemetry:
	return TruckTelemetry.new()


func _ready() -> void:
	super._ready()
	_find_rig()


## Geometry is the declaration: no `arm` mesh means no body unit and zeros on all body signals.
## No spec flag claims a body without an arm (rule 3).
func _find_rig() -> void:
	_arm = get_node_or_null(^"Model/arm") as MeshInstance3D
	_trash = get_node_or_null(^"Model/body/trash") as MeshInstance3D
	if _arm == null:
		return
	_body = RefuseBody.new()
	if _trash != null:
		# Authored heaped = full hopper; empty is one pile-height lower.
		_trash_full_y = _trash.position.y
		_trash_empty_y = _trash_full_y - _trash.mesh.get_aabb().size.y
	_pose_rig()


## No `arm` mesh means no body unit, so neither the X-key body stalk nor the chassis PTO has
## anything to show. PTO is keyed to the body: with nothing plugged in it moves only engine_load,
## and it powers the body network (RefuseBody.bus_up), so touch needs it to raise the arm.
func vehicle_capabilities() -> Dictionary:
	var caps := super()
	caps["body_cmd"] = _body != null
	caps["pto"] = _body != null
	return caps


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as TruckTelemetry
	var running := input.key == InputRouter.KEY_IGNITION

	# Air first: this tick's pressures feed the spring-brake gate below. The aux consumer is asked
	# BEFORE the step, so a trailer coupled this tick pays for its charge the same tick.
	var aux_air := _aux_air_draw(delta)
	t.air_primary = TruckTelemetry.air_step(t.air_primary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_PRIMARY, aux_air)
	t.air_secondary = TruckTelemetry.air_step(t.air_secondary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_SECONDARY, aux_air)

	var pto_on := input.pto and running
	t.pto_state = pto_on
	# The GOVERNED throttle, not the pedal: the request would report a load a cut engine isn't making.
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, drivetrain.applied_throttle, spec, pto_on, pto_load))

	# kg the rear springs held up this tick, not a mass lookup, so weight transfer and load move it.
	t.axle_load = TruckTelemetry.axle_load_kg(_rear_suspension_force())

	# What ran this tick, off the driveline, not what was asked.
	t.retarder_state = roundi(Drivetrain.retarder_pct(
			retarder_torque_applied, _retarder_rating_total()))

	# Nothing on the fifth wheel: false/0 on all four bus signals. SemiTractor overwrites AFTER its
	# trailer's wheels have ticked.
	t.clear_trailer_bus()

	_tick_body(t, input, pto_on, running, delta)

	# Spring brakes go on LAST, after retarder_state is read, and do NOT zero it: the retarder torque
	# ran and RayWheel integrated it this tick. (Demand already fades to 0 below RETARDER_CUTOUT_MS.)
	var gate_applied := TruckTelemetry.spring_brakes_applied(t.air_primary, t.air_secondary)
	if gate_applied:
		_apply_spring_brakes()
	if TruckTelemetry.spring_brake_notice_edge(gate_applied, _spring_brakes_were_applied):
		GameState.notice.emit(SPRING_BRAKE_NOTICE, SPRING_BRAKE_NOTICE_DWELL_S)
	_spring_brakes_were_applied = gate_applied


## What else draws on the air reservoirs this tick (air_step's `aux01`); SemiTractor overrides it
## with a charging trailer. Called once per tick, before the air step.
func _aux_air_draw(_delta: float) -> float:
	return 0.0


## CiA 422 body network + CiA 413 gateway. The rig is posed first and body_pos read back off the
## mesh, so picture and number agree. The hopper is mass only: no laden terms on axle_load or
## engine_load.
func _tick_body(t: TruckTelemetry, input: VehicleInput, pto_on: bool, running: bool,
		delta: float) -> void:
	if _body == null:
		# No refuse body: zeros every tick.
		t.body_state = RefuseBody.State.STOWED
		t.body_pos = 0
		t.body_inhibit = false
		t.body_bus = false
		t.hopper_load = 0
		return

	# The gateway: computed from CHASSIS state (road speed, parking brake, PTO), published on the
	# BODY network.
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

	# `mass` is a physics-server write; the hopper changes once per dump cycle, so only write on change.
	var payload := RefuseBody.hopper_mass_kg(_body.hopper)
	if not is_equal_approx(payload, _mass_applied):
		_mass_applied = payload
		mass = spec.mass + payload
		if drive != null:
			drive.set_corner_mass_from(mass)


## Say WHY the body stalk did nothing, on the press that did nothing. Only the two conditions the
## driver can act on (PTO, parking brake); road speed clears itself. Fires on the command EDGE, for
## LIFT and DUMP only.
func _warn_if_body_interlocked(input: VehicleInput, pto_on: bool) -> void:
	var cmd := input.body_cmd
	var edge := cmd != _last_body_cmd
	_last_body_cmd = cmd
	if not edge or (cmd != RefuseBody.Cmd.LIFT and cmd != RefuseBody.Cmd.DUMP):
		return
	if pto_on and input.handbrake > RefuseBody.PARK_BRAKE_MIN:
		return
	GameState.notice.emit(BODY_INTERLOCK_NOTICE, BODY_INTERLOCK_NOTICE_DWELL_S)


## Pose the arm and the refuse pile from the body unit.
func _pose_rig() -> void:
	if _body == null:
		return
	_arm.rotation.x = RefuseBody.arm_angle_rad(_body.pos)
	if _trash == null:
		return
	# The pile IS hopper_load: hidden when empty, rising as it fills.
	_trash.visible = _body.hopper > 0.0
	_trash.position.y = lerpf(_trash_empty_y, _trash_full_y, _body.hopper / 100.0)


## The retarder's rated torque across the driven rear axle: the 100 % end of the signal.
func _retarder_rating_total() -> float:
	if spec.ground_drive == null or not spec.ground_drive.retarder_equipped:
		return 0.0
	var count := 0
	for w in wheels:
		if w.is_rear and w.driven:
			count += 1
	return Drivetrain.retarder_rating(spec.ground_drive.brake_torque) * count


## Spring brakes lock the rear wheels (omega = 0), a post-integration kinematic write: first-gear
## drive torque exceeds brake_torque, so no torque could hold the truck. No ramp: losing air while
## rolling locks the axle in one tick.
func _apply_spring_brakes() -> void:
	for w in wheels:
		if w.is_rear:
			w.omega = 0.0


## Total suspension force carried by the rear axle this tick (N).
func _rear_suspension_force() -> float:
	var total := 0.0
	for w in wheels:
		if w.is_rear:
			total += w.suspension_force
	return total


## The refuse body is re-laid stowed with the hopper empty (the only way to empty it: the rig has
## no in-place tip). The base has already reset the air reservoirs, `mass` and the corner mass.
func reset_session_state() -> void:
	super.reset_session_state()
	_last_body_cmd = RefuseBody.Cmd.IDLE
	_spring_brakes_were_applied = false
	if _body != null:
		_body.reset()
		_pose_rig()
		_mass_applied = 0.0
