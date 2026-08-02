class_name TrainTelemetry
extends VehicleTelemetry
## Train telemetry (flavor "train" — rail practice / CiA 421 semantics, not a real train
## CAN standard). Adds the rail "out" fields on top of the shared VehicleTelemetry. Field
## names are EXACTLY the contract names (pantograph_state / doors_state / catenary_volts /
## motor_current / brake_pipe / grade / coupler_force) so the Bridge's name-keyed
## marshaling and the dashboard's t.get(name) reads work unchanged.
##
## grade and coupler_force are real reads out of the consist sim (curve tangent, coupler
## spring); pantograph_state / doors_state are gate reads. catenary_volts, motor_current
## and brake_pipe are modeled honest values (same latitude as the boat's trim / the
## tractor's engine_load) — the train has no simulated electrical or pneumatic circuit.
##
## Phase 2 ships the struct only: every field holds its resting value until Phase 3's
## TrainVehicle drives them. Declaring them now keeps the bridge-coverage test honest the
## moment the contract lists the train "out" signals.
##
## The base to_bridge_dict still carries rpm/fuel/coolant/ground/slip; the train declares
## none of those, so the Bridge (which walks the contract, not this dict) never reads them.

const BRAKE_PIPE_CHARGED := 5.0  ## bar, fully released train brake pipe pressure
const NOMINAL_CATENARY := 25000.0  ## V, 25 kV AC nominal line voltage (rail practice)

var pantograph_state := false  ## contract 'pantograph_state' (raised: request and key Ignition)
var doors_state := false       ## contract 'doors_state' (open: request honored at standstill)
var catenary_volts := 0.0      ## V, contract 'catenary_volts' (modeled: nominal minus sag)
var motor_current := 0.0       ## A, contract 'motor_current' (modeled from traction force)
var brake_pipe := BRAKE_PIPE_CHARGED  ## bar, contract 'brake_pipe' (modeled air brake)
var grade := 0                 ## %, contract 'grade' i8 (track slope at the loco, + = climbing)
var coupler_force := 0.0       ## kN, contract 'coupler_force' (+ = tension, - = buff)


# --- honest aux models (modeled values, like the boat's trim / tractor's engine_load) ------
# Pure -> unit-tested. The train has no simulated electrical or pneumatic circuit; these turn
# the sim's traction/brake reads into plausible line-voltage / motor-current / pipe-pressure
# gauges, clearly labelled as modeled.

## Traction motor current (A) from the loco's tractive force: linear, clamped to the rating.
static func motor_current_amps(traction_force: float, amps_per_newton: float,
		max_current: float) -> float:
	return clampf(absf(traction_force) * amps_per_newton, 0.0, max_current)


## Catenary voltage (V): nominal line voltage minus a sag proportional to current draw
## (the more the train pulls, the more the line droops), clamped non-negative.
static func catenary_volts_model(current: float, nominal: float, sag_per_amp: float) -> float:
	return maxf(nominal - current * sag_per_amp, 0.0)


## Brake pipe pressure (bar) chasing its target: full release sits at BRAKE_PIPE_CHARGED,
## brake application vents the pipe down (drop_rate), release recharges it (charge_rate).
## `apply_range` is how far full application pulls the target below charged.
static func brake_pipe_step(current: float, brake: float, delta: float,
		drop_rate: float, charge_rate: float, apply_range: float) -> float:
	var target := BRAKE_PIPE_CHARGED - clampf(brake, 0.0, 1.0) * apply_range
	var rate := drop_rate if target < current else charge_rate
	return move_toward(current, target, rate * delta)


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["pantograph_state"] = pantograph_state
	d["doors_state"] = doors_state
	d["catenary_volts"] = catenary_volts
	d["motor_current"] = motor_current
	d["brake_pipe"] = brake_pipe
	d["grade"] = grade
	d["coupler_force"] = coupler_force
	return d
