class_name RefuseBody
extends RefCounted
## The garbage truck's refuse body, as a CiA 422 ("CleANopen", EN 16815:2019) FUNCTIONAL UNIT —
## which is how that profile actually models a body: not as a device but as the CANopen interface
## of a virtual one. Pure logic, no nodes and no engine calls, so the state machine, the interlock
## and the hopper coupling are asserted in tests/test_truck.gd rather than only described.
##
## WHAT IS ON WHICH NETWORK, because the boundary is the content of this whole class:
##   - the BODY network (CiA 422) owns the command, the state, the arm position and the hopper;
##   - the CHASSIS network (J1939) owns road speed, the PTO and the parking brake;
##   - a CiA 413-6 gateway carries `body_inhibit` from the chassis side to the body side, and
##     CiA 413-8 is why the body's signals appear on the truck's own cluster at all.
## `is_inhibited()` is that crossing, written as one function so it is visible.
##
## THE RIG'S CEILING, stated plainly because it bounds what this may pretend to be: the garbage
## truck is a FRONT LOADER. Its `arm` mesh rotates about its own X at its origin and swings up over
## the cab; there is NO separable tailgate, NO body raise and NO compaction blade in the model. So
## there is no rear-loader packer cycle here, and there is no way to tip the hopper in place —
## respawn is what empties it. Inventing either would be a signal with nothing to show.
##
## What is READ and what is MODELLED (rule 3):
##   - the arm position is READ back off the posed mesh by the vehicle, never from `pos` directly;
##   - `hopper` is a MODEL, labelled: a counter of completed dump cycles. It earns its place by
##     adding real mass to the chassis, so `axle_load` and `engine_load` move as consequences.

enum Cmd { IDLE = 0, LIFT = 1, DUMP = 2, LOWER = 3 }
enum State { STOWED = 0, LIFTING = 1, DUMPING = 2, LOWERING = 3, INHIBITED = 4 }

## Stowed to fully over the cab. Slow enough that the interlock is something you can drive into.
const ARM_TRAVEL_SEC := 3.0
## The two ends of the arm's travel, in degrees about its own local X. NEGATIVE is up and back over
## the cab (the mesh reaches along its local +Z, and the Model node's yaw-180 makes that the
## vehicle's front), so the stow angle is POSITIVE — below the authored pose, forks down at the road.
##
## BOTH ARE MEASURED BY DRIVING, not derived, and this is the reason the rule is written down: the
## arm's origin sits at its own AABB min corner rather than on a natural hinge line, so the mesh
## sweeps a wide arc about a corner of itself and no arithmetic off the bounding box predicts where
## it ends up. Driving the first pass showed the arm CLIPPING THROUGH THE BODY at the top — the swing
## was carrying it into the cab rather than over it — so the travel is roughly half what was first
## guessed. The stowed end then took two passes of its own: 20 degrees below the authored pose put
## the forks through the road, and 5 is where they sit on it.
## Re-measure both the same way if the model ever changes.
const ARM_STOW_DEG := 5.0
const ARM_DUMP_DEG := -78.0
## The tip at the top. One completed dwell is one completed cycle.
const DUMP_DWELL_SEC := 1.2
## Hopper filled per completed dump cycle, so eight cycles fill it.
const HOPPER_PER_CYCLE := 12.5
## Payload at a full hopper (kg). The chassis is 8000 kg, so this is a clearly felt +63 % — and it
## is the ONLY way the hopper touches the chassis. See TruckVehicle for why there is no second term.
const HOPPER_PAYLOAD_KG := 5000.0
## Road speed above which the body is inhibited (~5 km/h): walking pace, because a refuse round is
## driven at walking pace between bins and the interlock has to allow that.
const WALK_PACE_MS := 1.4
## Parking brake application the interlock demands. A real refuse body is operated stopped and
## parked, and the local handbrake is the only parking brake this project has.
const PARK_BRAKE_MIN := 0.5
const POS_EPS := 0.001

var pos := 0.0                ## 0..1 arm travel; the vehicle poses the mesh from this
var state := State.STOWED     ## contract 'body_state'
var hopper := 0.0             ## 0..100 %, contract 'hopper_load'
var _dwell := 0.0             ## seconds into the tip at the top
var _dumped := false          ## this Dump command's cycle already counted


## Whether the body network is powered and the gateway answering — contract 'body_bus'.
##
## LABELLED MODEL: there is no CANopen stack to be up or down, so this is the power condition. The
## body network runs off the PTO-driven supply, so it needs the engine running AND the chassis PTO
## engaged. The point is that it CAN be down: drop the PTO and the whole second network goes with
## it, which is what separates two networks from one network with more signals on it.
static func bus_up(running: bool, pto_on: bool) -> bool:
	return running and pto_on


## The interlock — contract 'body_inhibit', and the one value in the game that crosses a bus
## boundary. Every argument here is CHASSIS state; the result is published on the BODY network.
##
## A down bus inhibits, which is why "PTO not engaged" is not tested again: `bus_up` already
## carries it, and stating it twice would let the two drift apart.
##
## Consequence on the CLUSTER, known and deliberate rather than an oversight: because a down bus
## inhibits, this is true whenever BODY BUS is dark — which is the whole of normal driving with the
## PTO out, so INHIB only carries information of its own once the bus is up (measured over a refuse
## round: lit with the bus dark 44 % of ticks, lit with the bus up 20 %). SETTLED, and the fix is on
## the DASHBOARD: it suppresses the INHIB lamp while BODY BUS is dark, because a body with no
## network cannot be refused a command. Do NOT unpick the rule above to quieten the lamp — dropping
## the bus term here would leave the interlock claiming an unpowered body may swing its arm, and the
## published signal must stay the honest one.
static func is_inhibited(speed_ms: float, handbrake01: float, bus: bool) -> bool:
	return not bus \
			or absf(speed_ms) > WALK_PACE_MS \
			or handbrake01 <= PARK_BRAKE_MIN


## Arm rotation (rad about the mesh's own local X) for a travel fraction. Paired with
## arm_pos_pct: the vehicle WRITES this onto the mesh and then reads the number back out, so the
## picture and the signal cannot disagree.
##
## Note that stowed is NOT the authored rotation of zero — it is ARM_STOW_DEG below it, so both ends
## of the travel are named constants and neither is an accident of how the mesh was exported.
static func arm_angle_rad(pos01: float) -> float:
	return lerpf(deg_to_rad(ARM_STOW_DEG), deg_to_rad(ARM_DUMP_DEG), clampf(pos01, 0.0, 1.0))


## Travel percent recovered from the mesh's actual rotation — contract 'body_pos'. The inverse of
## arm_angle_rad, and the direction that matters: this is read off the POSED rig.
static func arm_pos_pct(angle_rad: float) -> float:
	var stow := deg_to_rad(ARM_STOW_DEG)
	var top := deg_to_rad(ARM_DUMP_DEG)
	return clampf((angle_rad - stow) / (top - stow), 0.0, 1.0) * 100.0


## Payload mass (kg) for a hopper fill percentage. The whole coupling to the chassis lives here.
static func hopper_mass_kg(hopper_pct: float) -> float:
	return clampf(hopper_pct, 0.0, 100.0) / 100.0 * HOPPER_PAYLOAD_KG


## Advance the unit one tick. `inhibit` comes from is_inhibited() on the chassis side.
##
## The state rule, and it is total: LIFTING / LOWERING mean the MODE is selected, not merely that
## the actuator is moving. That is what lets the contract's five settled values cover every case
## including the arm held at the top — there is no "Raised" state, and inventing one would change
## a settled enum to describe something the operator cannot command.
##
## Idle and Lower both stow, deliberately: a body that stayed up when the command dropped would be
## the unsafe design. An unknown command byte from the bus lands here too, so the fallback is the
## safe pose rather than a stuck arm.
func step(cmd: int, inhibit: bool, delta: float) -> void:
	if inhibit:
		# Frozen WHERE IT STANDS, not driven home: the interlock refuses the command, it does not
		# take over as one. Losing the PTO mid-lift leaves the arm up, which is what happens.
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

	# The latch clears on any command other than Dump, so one Dump selection is one cycle —
	# holding the command down does not tick the hopper up forever.
	_dwell = 0.0
	_dumped = false

	if cmd == Cmd.LIFT:
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta / ARM_TRAVEL_SEC)
		return

	pos = move_toward(pos, 0.0, delta / ARM_TRAVEL_SEC)
	state = State.STOWED if pos <= POS_EPS else State.LOWERING


## Back to the delivered pose with the hopper empty — what TruckVehicle.respawn() calls. The load
## going with it is the deliberate part: the truck tipped at the transfer station, and cargo is not
## a meter the way the odometer and engine_hours are.
func reset() -> void:
	pos = 0.0
	state = State.STOWED
	hopper = 0.0
	_dwell = 0.0
	_dumped = false
