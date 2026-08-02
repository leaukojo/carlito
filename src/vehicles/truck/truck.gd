class_name TruckVehicle
extends BaseVehicle
## Truck (J1939 chassis). A real BaseVehicle subclass because it owns per-tick subsystem state
## the base has no concept of: two air brake reservoirs and the chassis PTO. It never forks
## _physics_process — it plugs into the two base seams (_make_telemetry, _tick_extras), exactly
## like TractorVehicle.
##
## Two of its signals are REAL BEHAVIOUR, not readouts, which is why they are worth having:
##
##   - AIR PRESSURE GATES THE BRAKES. The reservoirs charge while the engine runs and are drawn
##     down by brake applications; below TruckTelemetry.AIR_SPRING_BRAKE_BAR on either circuit
##     the spring brakes apply and the truck cannot move. Same shape as the train's pantograph
##     cutting traction: a signal with a bar, a warn and a RULE.
##   - THE RETARDER IS A REAL DRIVELINE TORQUE on the driven axle. It fades to nothing at
##     walking pace, cannot skid the axle, and is rated well below brake_torque so the tuned
##     brake > peak drive > handbrake hierarchy still holds by construction. Being driveline
##     behaviour it lives where the differential lock lives — math on Drivetrain, application in
##     BaseVehicle, gated by spec.retarder_equipped (false on every non-truck spec) — NOT here.
##     This class only reads back what the driveline applied.
##
## The spring brake is the one thing here that writes wheel `omega` directly, and that is
## deliberate rather than a shortcut: it is a KINEMATIC LOCK to zero, which can only remove
## energy, so it is the same kind of post-tick write BaseVehicle._lock_rear_diff already makes.
## A brake TORQUE is not, which is why the retarder goes through RayWheel's own brake path
## instead — see the retarder block in drivetrain.gd for the measurement behind that.
## No RayWheel clamp is touched, forked or weakened anywhere here.

## engine_load added while the chassis PTO is engaged. The tractor's parasitic term reused
## rather than a second model of the same thing — a PTO costs the engine the same way whatever
## it is turning. On this family the PTO is also what powers the body network (see body_bus).
@export var pto_load := 0.35

## The refuse body's CiA 422 functional unit, or null on a truck that has no body to run. See
## _find_rig for why the geometry is what declares it.
var _body: RefuseBody = null
var _arm: MeshInstance3D = null      ## the front-loader arm; body_pos is read back off its rotation
var _trash: MeshInstance3D = null    ## the refuse pile in the hopper; its height shows hopper_load
var _trash_full_y := 0.0             ## the AUTHORED pile pose = a full hopper
var _trash_empty_y := 0.0            ## sunk out of sight, measured off the pile's own mesh
var _mass_applied := 0.0             ## payload currently written into `mass`, to avoid re-writing it
var _last_body_cmd := 0              ## previous tick's body_cmd, so the notice below fires on the EDGE

## Told to the driver when the body stalk is worked with the PTO out or the parking brake off — the
## two things the interlock demands that are also the two the driver can DO something about. Fires on
## the press rather than while inhibited, so it explains the refusal instead of nagging.
const BODY_INTERLOCK_NOTICE := "ENGAGE THE PTO AND HANDBRAKE FIRST"
const BODY_INTERLOCK_NOTICE_DWELL_S := 5.0


func _make_telemetry() -> VehicleTelemetry:
	return TruckTelemetry.new()


func _ready() -> void:
	super._ready()
	_find_rig()


## Find the refuse body's meshes BY NAME, and let their presence declare whether this truck has a
## body at all.
##
## REGEN TRAP, and it is silent: tools/gen_kenney_vehicles.gd rebuilds the entire `Model` subtree
## from the GLB on every run (GENERATED_CHILDREN == ["Model", "Lamps"]), so any node added under
## Model is wiped by the next regen while the run still prints success. Nothing is added here — the
## rig is found by name and posed from code, so a regen has nothing to lose.
##
## THE GEOMETRY IS THE DECLARATION. The firetruck's Model is one merged `body` mesh with a `grill`
## child, so `arm` is not there and it gets no body unit — it publishes honest zeros on all five
## body signals. This is the implement rule (what a machine declares lives in CODE, never in
## exported data) in its strongest available form: a VehicleSpec flag could claim a refuse body on a
## truck with no arm to show it, which is exactly the fiction rule 3 forbids. Here the signal cannot
## exist without the geometry that performs it.
func _find_rig() -> void:
	_arm = get_node_or_null(^"Model/arm") as MeshInstance3D
	_trash = get_node_or_null(^"Model/body/trash") as MeshInstance3D
	if _arm == null:
		return
	_body = RefuseBody.new()
	if _trash != null:
		# The pile is AUTHORED heaped, so that pose is a full hopper; empty is one pile-height
		# lower, which drops it inside the body. Measured off the mesh, never a constant — the
		# implement rule (geometry lives in the scene and is measured off it).
		_trash_full_y = _trash.position.y
		_trash_empty_y = _trash_full_y - _trash.mesh.get_aabb().size.y
	_pose_rig()


## Both of these are the GEOMETRY DECLARATION above wearing a different hat: no `arm` mesh means
## no body unit, so neither the X-key body stalk nor the chassis PTO has anything to show, and the
## shell offers neither. A VehicleSpec flag would let a truck with nothing to lift claim both.
##
## The PTO one is not cosmetic: the body network only comes up with the chassis PTO engaged
## (RefuseBody.bus_up), so without this the refuse arm cannot be raised from touch at all. It is
## keyed to the body rather than offered on every truck because a chassis PTO with nothing plugged
## into it moves engine_load and nothing you can see.
func vehicle_capabilities() -> Dictionary:
	var caps := super()
	caps["body_cmd"] = _body != null
	caps["pto"] = _body != null
	return caps


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as TruckTelemetry
	var running := input.key == InputRouter.KEY_IGNITION

	# Air first: this tick's pressures are what the spring-brake gate below decides on. The second
	# consumer is asked for BEFORE the step, so a trailer coupled this tick pays for its charge on
	# the same tick the gate reads — which is what lets coupling and pulling straight away catch
	# you out instead of catching you out one frame late.
	var aux_air := _aux_air_draw(delta)
	t.air_primary = TruckTelemetry.air_step(t.air_primary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_PRIMARY, aux_air)
	t.air_secondary = TruckTelemetry.air_step(t.air_secondary, input.brake, running, delta,
			TruckTelemetry.AIR_CHARGE_RATE, TruckTelemetry.AIR_DRAW_SECONDARY, aux_air)

	var pto_on := input.pto and running
	t.pto_state = pto_on
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, input.throttle, spec, pto_on, pto_load))
	t.engine_hours = VehicleTelemetry.hours_step(t.engine_hours, running, delta)

	# Drive-axle load, READ OUT OF THE SIM: whatever the rear springs were actually holding up
	# this tick, in kilograms. Not a mass lookup — so braking weight transfer, and from the
	# later phases a laden body or a coupled trailer, move it as consequences of real force.
	t.axle_load = TruckTelemetry.axle_load_kg(_rear_suspension_force())

	# Read straight off the driveline, like diff_lock_state: BaseVehicle put this torque into the
	# driven wheels' brake torque this tick, so it is what ran, not what was asked for.
	t.retarder_state = roundi(Drivetrain.retarder_pct(
			retarder_torque_applied, _retarder_rating_total()))

	# The ISO 11992 trailer bus in the only state a truck that cannot tow is ever in: nothing on the
	# fifth wheel, so a real false / 0 on all four signals every tick. SemiTractor overwrites them
	# AFTER its trailer's own wheels have ticked — that ordering is load-bearing (the loads and the
	# slip published have to be this tick's), which is why it is not a seam called from here.
	t.clear_trailer_bus()

	_tick_body(t, input, pto_on, running, delta)

	# The spring brakes go on LAST, after retarder_state has been read. They do NOT zero it, and
	# that is the honest way round: the retarder torque went into the driven wheels' brake torque
	# earlier in this same tick and RayWheel integrated it, so it really did run — the pin that
	# follows supersedes it rather than retracting it. Zeroing here would make retarder_state an
	# echo of the gate instead of a read of the driveline, which is the diff_lock_state rule
	# backwards. (The window is narrow anyway: the demand is already faded to 0 below
	# RETARDER_CUTOUT_MS, so the two only overlap while the air fails with the truck still rolling.)
	if TruckTelemetry.spring_brakes_applied(t.air_primary, t.air_secondary):
		_apply_spring_brakes()


## What else is drawing on the air reservoirs this tick, as a fraction of a full brake application
## (air_step's `aux01`). Nothing, on a truck with nothing but its own brakes on the supply.
##
## SemiTractor overrides it with a freshly coupled trailer charging its reservoirs — the one place
## the trailer phases reach into the chassis phase, and they do it through the air MODEL rather
## than through a term beside it. Called once per tick, before the air step, so the reservoir it is
## filling and the pressure filling it move together.
func _aux_air_draw(_delta: float) -> float:
	return 0.0


## The CiA 422 body network, one tick — and the CiA 413 gateway that carries it to the J1939 side.
##
## Ordering here is load-bearing, the same way the tractor's linkage is posed BEFORE the draft force
## reads it: the rig is posed from the unit and body_pos is then computed back OUT of the mesh's own
## rotation. Sizing the signal from the unit's travel fraction directly would look identical and
## would let the number and the picture drift apart the moment the pose gains a limit or an offset.
##
## The hopper touches the chassis through MASS AND NOTHING ELSE — adding a laden term to axle_load
## or engine_load would double-count it, which is the fiction this coupling exists to demonstrate the
## alternative to. The two then report it UNEQUALLY, and knowing which is which saves reading the
## cluster wrong: axle_load is summed suspension force, so the payload lands on it the next tick,
## while engine_load only reaches the payload through the rpm the drivetrain sags to — so it answers
## under throttle and on a grade, and a loaded truck holding a steady speed on the flat reads the
## same load as an empty one. That is honest rather than missing (see the "engine_load is not
## monotone in draft" note in src/vehicles/CLAUDE.md), and it is why axle_load is the bar to watch
## after a dump cycle. center_of_mass stays on the spec: a load that shifts the balance is the
## tanker's content in a later phase, and doing it here would preempt it with a second, less honest
## version.
func _tick_body(t: TruckTelemetry, input: InputRouter.VehicleInput, pto_on: bool, running: bool,
		delta: float) -> void:
	if _body == null:
		# No refuse body on this truck. A real zero every tick, never a gap — the same rule a
		# detached implement follows, and what keeps the firetruck's cluster the same shape as the
		# garbage truck's rather than a different dashboard for the same chassis class.
		t.body_state = RefuseBody.State.STOWED
		t.body_pos = 0
		t.body_inhibit = false
		t.body_bus = false
		t.hopper_load = 0
		return

	# The gateway. Both of these are computed from CHASSIS state and published on the BODY network:
	# road speed and the parking brake come off this vehicle, the PTO off the chassis driveline.
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

	# Only write `mass` when the payload actually changed: it is a physics-server property, and the
	# hopper moves once per dump cycle rather than once per tick.
	var payload := RefuseBody.hopper_mass_kg(_body.hopper)
	if not is_equal_approx(payload, _mass_applied):
		_mass_applied = payload
		mass = spec.mass + payload


## Say WHY the body stalk did nothing, on the press that did nothing.
##
## Only the two conditions the driver can act on: the PTO powers the body network (RefuseBody.bus_up)
## and the parking brake is what the interlock demands. Road speed is deliberately not covered here —
## that one clears itself by stopping, and the notice exists for the case where the driver is already
## stopped and nothing moves. It fires on the EDGE of the command (InputRouter cycles body_cmd
## whether or not the body can act on it) and only for the commands that ask the arm to move, so
## cycling round to Idle is silent.
func _warn_if_body_interlocked(input: InputRouter.VehicleInput, pto_on: bool) -> void:
	var cmd := input.body_cmd
	var edge := cmd != _last_body_cmd
	_last_body_cmd = cmd
	if not edge or (cmd != RefuseBody.Cmd.LIFT and cmd != RefuseBody.Cmd.DUMP):
		return
	if pto_on and input.handbrake > RefuseBody.PARK_BRAKE_MIN:
		return
	GameState.notice.emit(BODY_INTERLOCK_NOTICE, BODY_INTERLOCK_NOTICE_DWELL_S)


## Pose the arm and the refuse pile from the body unit. Called after every step and on respawn, so
## the rig is never left showing a state the unit has moved on from.
func _pose_rig() -> void:
	if _body == null:
		return
	_arm.rotation.x = RefuseBody.arm_angle_rad(_body.pos)
	if _trash == null:
		return
	# The pile IS hopper_load: hidden when empty, rising out of the hopper as it fills.
	_trash.visible = _body.hopper > 0.0
	_trash.position.y = lerpf(_trash_empty_y, _trash_full_y, _body.hopper / 100.0)


## The retarder's rated torque across the whole driven rear axle — the 100 % end of the signal.
func _retarder_rating_total() -> float:
	if not spec.retarder_equipped:
		return 0.0
	var count := 0
	for w in wheels:
		if w.is_rear and w.driven:
			count += 1
	return Drivetrain.retarder_rating(spec.brake_torque) * count


## Spring brakes: hold the rear wheels at rest. They are a MECHANICAL lock (a spring clamping
## the shoes, held off by air), not a torque to be out-muscled, so this pins omega rather than
## applying a large brake torque — the same post-integration omega write BaseVehicle._lock_rear_diff
## makes for the locked diff.
##
## Consequence worth knowing, because it looks odd before you think about it: Drivetrain reads
## the DRIVE wheel omega, so with the rears pinned the tachometer falls to idle however far the
## throttle is pressed. That is the engine lugging against the brakes, which is what actually
## happens — and it is why this needs no separate "cut the throttle" term.
##
## Second consequence, ACCEPTED rather than overlooked: there is no ramp, so losing the air while
## rolling locks the rear axle in a single tick — slip goes to 1 and the friction circle takes the
## rear lateral grip with it. That is what spring brakes physically do (they are held OFF by air,
## so a supply failure applies them fully), so it is honest rather than a bug, and it is exactly
## why the contract's low-pressure 'warn' sits a whole 2 bar above the gate. Do not soften it into
## a gradual brake torque: a torque cannot hold this truck at all (first-gear drive torque per
## driven wheel exceeds brake_torque), which is why it is a kinematic pin in the first place.
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


## Recharge the reservoirs to the spawn pressure on respawn: air is physical state, so a reset
## re-lays it the way the tractor's respawn re-raises the hitch. engine_hours and the odometer
## are meters and deliberately survive — they record the machine's life, not this drive.
##
## The refuse body is re-laid too, arm stowed and hopper EMPTY — the truck tipped at the transfer
## station. That is also the only way to empty it: the rig has no body raise, so there is nothing
## that could show an in-place tip. The load going while the meters stay is the honest split: cargo
## is not a record of the machine's life.
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
