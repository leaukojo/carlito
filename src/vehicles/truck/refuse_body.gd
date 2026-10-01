class_name RefuseBody
extends RefCounted
## The garbage truck's refuse body, a CiA 422 functional unit. Pure logic, no nodes. The body
## network owns command, state, arm and hopper; the chassis network (J1939) owns road speed, PTO
## and parking brake; a CiA 413-6 gateway carries `body_inhibit` across in `is_inhibited()`.
##
## The rig is a front loader with no tailgate, body raise or compaction blade, so respawn is the
## only way to empty the hopper. Arm position is read back off the posed mesh, never `pos`, and
## `hopper` is a labelled model adding real mass to the chassis.

enum Cmd { IDLE = 0, LIFT = 1, DUMP = 2, LOWER = 3 }
enum State { STOWED = 0, LIFTING = 1, DUMPING = 2, LOWERING = 3, INHIBITED = 4 }

## Stowed to fully over the cab.
const ARM_TRAVEL_SEC := 3.0
## Arm travel ends, degrees about its own local X. Negative is up and back over the cab; stow is
## positive, below the authored pose. Measured by driving: the arm's origin is its AABB min corner,
## not a hinge line.
const ARM_STOW_DEG := 5.0
const ARM_DUMP_DEG := -78.0
## Dwell at the top; one completed dwell is one completed cycle.
const DUMP_DWELL_SEC := 1.2
## Hopper filled per completed dump cycle (eight cycles fill it).
const HOPPER_PER_CYCLE := 12.5
## Payload at a full hopper, kg, against an 8000 kg chassis; the only way the hopper is felt.
const HOPPER_PAYLOAD_KG := 5000.0
## Road speed (m/s) above which the body is inhibited (~5 km/h walking pace, between bins).
const WALK_PACE_MS := 1.4
## Parking brake application the interlock demands (the local handbrake is the only one).
const PARK_BRAKE_MIN := 0.5
const POS_EPS := 0.001

var pos := 0.0                ## 0..1 arm travel; the vehicle poses the mesh from this
var state := State.STOWED     ## contract 'body_state'
var hopper := 0.0             ## 0..100 %, contract 'hopper_load'
var _dwell := 0.0             ## seconds into the tip at the top
var _dumped := false          ## this Dump command's cycle already counted


## Whether the body network is powered and the gateway answering, contract 'body_bus'. A labelled
## model (there is no CANopen stack): the engine running and the chassis PTO engaged.
static func bus_up(running: bool, pto_on: bool) -> bool:
	return running and pto_on


## The interlock, contract 'body_inhibit': chassis state in, published on the body network. A down
## bus inhibits (`bus_up` already carries the PTO). It stays true through normal driving with the
## PTO out; the dashboard suppresses the INHIB lamp while BODY BUS is dark. Keep the bus term: an
## unpowered body must not claim it may swing its arm.
static func is_inhibited(speed_ms: float, handbrake01: float, bus: bool) -> bool:
	return not bus \
			or absf(speed_ms) > WALK_PACE_MS \
			or handbrake01 <= PARK_BRAKE_MIN


## Arm rotation (rad about the mesh's own local X) for a travel fraction; paired with arm_pos_pct
## (the vehicle writes this onto the mesh, then reads the number back). Stowed is ARM_STOW_DEG, not 0.
static func arm_angle_rad(pos01: float) -> float:
	return lerpf(deg_to_rad(ARM_STOW_DEG), deg_to_rad(ARM_DUMP_DEG), clampf(pos01, 0.0, 1.0))


## Travel percent recovered from the mesh's rotation, contract 'body_pos'; the inverse of arm_angle_rad.
static func arm_pos_pct(angle_rad: float) -> float:
	var stow := deg_to_rad(ARM_STOW_DEG)
	var top := deg_to_rad(ARM_DUMP_DEG)
	return clampf((angle_rad - stow) / (top - stow), 0.0, 1.0) * 100.0


## Payload mass (kg) for a hopper fill percentage; the whole coupling to the chassis.
static func hopper_mass_kg(hopper_pct: float) -> float:
	return clampf(hopper_pct, 0.0, 100.0) / 100.0 * HOPPER_PAYLOAD_KG


## Advance the unit one tick; `inhibit` comes from is_inhibited(). LIFTING and LOWERING mean the
## mode is selected, not that the actuator is moving (there is no "Raised" state). Idle, Lower and
## an unknown command byte all stow.
func step(cmd: int, inhibit: bool, delta: float) -> void:
	if inhibit:
		# Frozen where it stands, not driven home: losing PTO mid-lift leaves the arm up.
		state = State.INHIBITED
		_dwell = 0.0
		_dumped = false
		return

	if cmd == Cmd.DUMP:
		if pos >= 1.0 - POS_EPS:
			state = State.DUMPING
			if not _dumped:
				_dwell += delta
				if _dwell >= DUMP_DWELL_SEC:
					_dwell = 0.0
					_dumped = true
					hopper = minf(hopper + HOPPER_PER_CYCLE, 100.0)
			return
		# Dump lifts first, then tips.
		_dwell = 0.0
		_dumped = false
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta / ARM_TRAVEL_SEC)
		return

	# The latch clears on any other command: one Dump selection is one cycle.
	_dwell = 0.0
	_dumped = false

	if cmd == Cmd.LIFT:
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta / ARM_TRAVEL_SEC)
		return

	pos = move_toward(pos, 0.0, delta / ARM_TRAVEL_SEC)
	state = State.STOWED if pos <= POS_EPS else State.LOWERING


## Back to the delivered pose with the hopper empty, called by TruckVehicle.reset_session_state().
## The load goes too: cargo is not a meter like the odometer and engine_hours.
func reset() -> void:
	pos = 0.0
	state = State.STOWED
	hopper = 0.0
	_dwell = 0.0
	_dumped = false
