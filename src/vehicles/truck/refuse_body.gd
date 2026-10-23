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

## Stowed to fully over the cab, at the pump's rated flow (`pump_flow` 1).
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
## The body pump's draw at the PTO shaft while the arm rises (kW). The pump is a 40 yd³ front
## loader's, rated about 50 gpm at 1300 engine rpm against a 2500 psi relief (a city's bid spec:
## sourced). Raising, it works at an ESTIMATED half the relief: 3.15 L/s at 8.6 MPa is 27 kW of
## flow, over an ESTIMATED 0.85 pump efficiency. The same bid's 8000 lb container lifted an
## estimated 4 m in half its 13-18 s cycle is ~22 kW, the same size. Lowering and holding run at a
## load-sensing pump's standby (under 25 psi): 0. Citations: docs/sources.md § PTO power.
const PUMP_KW := 32.0
## The engine speed that flow is rated at: the pump's torque on the crank is PUMP_KW over it
## (`VehicleTelemetry.pto_crank_torque`).
const PUMP_RATED_ENGINE_RPM := 1300.0

var pos := 0.0                ## 0..1 arm travel; the vehicle poses the mesh from this
var raising := false          ## the arm rose on the last `step` (`pump_kw`)
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


## The pump's flow over its rated flow at `engine_rpm`, 0..1: a fixed displacement's flow is its
## speed's share of PUMP_RATED_ENGINE_RPM. The cap at 1 is an ESTIMATE, the body's flow control
## holding the arm's rated speed past it (no body's figure found). The torque stays the pump's
## displacement times its pressure, constant in speed (`VehicleTelemetry.pto_crank_torque`).
static func pump_flow(engine_rpm: float) -> float:
	return clampf(engine_rpm / PUMP_RATED_ENGINE_RPM, 0.0, 1.0)


## The pump's draw at the PTO shaft this tick (kW): PUMP_KW while the arm rises, else 0.
func pump_kw() -> float:
	return PUMP_KW if raising else 0.0


## Advance the unit one tick; `inhibit` comes from is_inhibited(). LIFTING and LOWERING mean the
## mode is selected, not that the actuator is moving (there is no "Raised" state). Idle, Lower and
## an unknown command byte all stow. The arm rises at the pump's `flow` (`pump_flow`); it lowers on
## its own weight through the valve, at the rated rate whatever the pump turns.
func step(cmd: int, inhibit: bool, delta: float, flow := 1.0) -> void:
	var was := pos
	_step_arm(cmd, inhibit, delta, clampf(flow, 0.0, 1.0))
	raising = pos > was


func _step_arm(cmd: int, inhibit: bool, delta: float, flow: float) -> void:
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
		pos = move_toward(pos, 1.0, delta * flow / ARM_TRAVEL_SEC)
		return

	# The latch clears on any other command: one Dump selection is one cycle.
	_dwell = 0.0
	_dumped = false

	if cmd == Cmd.LIFT:
		state = State.LIFTING
		pos = move_toward(pos, 1.0, delta * flow / ARM_TRAVEL_SEC)
		return

	pos = move_toward(pos, 0.0, delta / ARM_TRAVEL_SEC)
	state = State.STOWED if pos <= POS_EPS else State.LOWERING


## Back to the delivered pose with the hopper empty, called by TruckVehicle.reset_session_state().
## The load goes too: cargo is not a meter like the odometer and engine_hours.
func reset() -> void:
	pos = 0.0
	raising = false
	state = State.STOWED
	hopper = 0.0
	_dwell = 0.0
	_dumped = false
