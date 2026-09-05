class_name RefuseBody
extends RefCounted
## The garbage truck's refuse body, a CiA 422 functional unit. Pure logic, no nodes. The body
## network owns command, state, arm and hopper; the chassis network (J1939) owns road speed, PTO
## and parking brake; a CiA 413-6 gateway carries `body_inhibit` across in `is_inhibited()`.
##
## The rig is a front loader with no separable tailgate, body raise or compaction blade, so respawn
## is the only way to empty the hopper. Arm position is read back off the posed mesh, never `pos`
## directly, and `hopper` is a labelled model adding real mass to the chassis, which axle_load and
## engine_load then follow.

enum Cmd { IDLE = 0, LIFT = 1, DUMP = 2, LOWER = 3 }
enum State { STOWED = 0, LIFTING = 1, DUMPING = 2, LOWERING = 3, INHIBITED = 4 }

## Stowed to fully over the cab. Slow enough to drive into the interlock.
const ARM_TRAVEL_SEC := 3.0
## Arm travel ends, degrees about its own local X. Negative is up and back over the cab, stow is
## positive, below the authored pose. Both were measured by driving, since the arm's origin is its
## own AABB min corner rather than a hinge line, so no arithmetic predicts the sweep.
const ARM_STOW_DEG := 5.0
const ARM_DUMP_DEG := -78.0
## Dwell at the top; one completed dwell is one completed cycle.
const DUMP_DWELL_SEC := 1.2
## Hopper filled per completed dump cycle (eight cycles fill it).
const HOPPER_PER_CYCLE := 12.5
## Payload at a full hopper, kg, against an 8000 kg chassis. The only way the hopper is felt.
const HOPPER_PAYLOAD_KG := 5000.0
## Road speed above which the body is inhibited (~5 km/h walking pace, between bins).
const WALK_PACE_MS := 1.4
## Parking brake application the interlock demands; local handbrake is the only parking brake here.
const PARK_BRAKE_MIN := 0.5
const POS_EPS := 0.001

var pos := 0.0                ## 0..1 arm travel; the vehicle poses the mesh from this
var state := State.STOWED     ## contract 'body_state'
var hopper := 0.0             ## 0..100 %, contract 'hopper_load'
var _dwell := 0.0             ## seconds into the tip at the top
var _dumped := false          ## this Dump command's cycle already counted


## Whether the body network is powered and the gateway answering, contract 'body_bus'. A labelled
## model of the power condition, since there is no real CANopen stack to be up or down. It needs
## the engine running and the chassis PTO engaged, so dropping the PTO takes the network down.
static func bus_up(running: bool, pto_on: bool) -> bool:
	return running and pto_on


## The interlock, contract 'body_inhibit'. The arguments are chassis state and the result is
## published on the body network. A down bus inhibits, so do not test PTO separately; `bus_up`
## already carries it. This stays true through normal driving with the PTO out, which the dashboard
## handles by suppressing the INHIB lamp while BODY BUS is dark. Do not drop the bus term here to
## quieten it: an unpowered body must not claim it may swing its arm.
static func is_inhibited(speed_ms: float, handbrake01: float, bus: bool) -> bool:
	return not bus \
			or absf(speed_ms) > WALK_PACE_MS \
			or handbrake01 <= PARK_BRAKE_MIN


## Arm rotation (rad about the mesh's own local X) for a travel fraction. Paired with arm_pos_pct:
## the vehicle writes this onto the mesh, then reads the number back out. Stowed is not rotation
## zero, but ARM_STOW_DEG below the authored pose.
static func arm_angle_rad(pos01: float) -> float:
	return lerpf(deg_to_rad(ARM_STOW_DEG), deg_to_rad(ARM_DUMP_DEG), clampf(pos01, 0.0, 1.0))


## Travel percent recovered from the mesh's actual rotation, contract 'body_pos'. Read off the
## posed rig, the inverse of arm_angle_rad.
static func arm_pos_pct(angle_rad: float) -> float:
	var stow := deg_to_rad(ARM_STOW_DEG)
	var top := deg_to_rad(ARM_DUMP_DEG)
	return clampf((angle_rad - stow) / (top - stow), 0.0, 1.0) * 100.0


## Payload mass (kg) for a hopper fill percentage. The whole coupling to the chassis lives here.
static func hopper_mass_kg(hopper_pct: float) -> float:
	return clampf(hopper_pct, 0.0, 100.0) / 100.0 * HOPPER_PAYLOAD_KG


## Advance the unit one tick; `inhibit` comes from is_inhibited() on the chassis side. LIFTING and
## LOWERING mean the mode is selected, not merely that the actuator is moving, since there is no
## "Raised" state. Idle and Lower both stow, and an unknown command byte lands there too, so the
## fallback is always the safe pose.
func step(cmd: int, inhibit: bool, delta: float) -> void:
	if inhibit:
		# Frozen where it stands, not driven home. Losing PTO mid-lift leaves the arm up.
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
		# Dump implies the lift it needs first, so the arm travels up before the tip.
		_dwell = 0.0
		_dumped = false
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta / ARM_TRAVEL_SEC)
		return

	# The latch clears on any command other than Dump, so one Dump selection is one cycle and
	# holding the command down does not tick the hopper up forever.
	_dwell = 0.0
	_dumped = false

	if cmd == Cmd.LIFT:
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta / ARM_TRAVEL_SEC)
		return

	pos = move_toward(pos, 0.0, delta / ARM_TRAVEL_SEC)
	state = State.STOWED if pos <= POS_EPS else State.LOWERING


## Back to the delivered pose with the hopper empty, called by TruckVehicle.respawn(). The load
## goes with it deliberately: cargo is not a meter the way the odometer and engine_hours are.
func reset() -> void:
	pos = 0.0
	state = State.STOWED
	hopper = 0.0
	_dwell = 0.0
	_dumped = false
