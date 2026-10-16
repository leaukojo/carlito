class_name TruckTelemetry
extends VehicleTelemetry
## Truck telemetry (J1939 FMS set); field names are the contract names. Read out of the sim:
## axle_load, retarder_state. Modeled: engine_load, air_primary/secondary.

# --- air brake reservoirs (modeled honest values) --------------------------------------
const AIR_MAX_BAR := 12.0     ## contract 'air_primary'/'air_secondary' range max
## Spawn pressure: above the spring-brake cut-in, below working, so the bars visibly charge.
const AIR_SPAWN_BAR := 7.0
## Below this on EITHER circuit the spring brakes apply; under 'warn' (5.0) for a band to stop in.
const AIR_SPRING_BRAKE_BAR := 3.0
const AIR_CHARGE_RATE := 0.45      ## bar/s the compressor makes, engine running only
## bar one full brake press draws on the pedal's rise, circuit 1: pumping once a second drains.
const AIR_PRESS_PRIMARY := 0.70
## Circuit 2 runs off a smaller reservoir, so the pair (SPN 1087/1088) diverges under braking.
const AIR_PRESS_SECONDARY := 0.55
const AIR_DRAW_PRIMARY := 1.10     ## bar/s a continuous consumer draws at full demand, circuit 1
const AIR_DRAW_SECONDARY := 0.85
## A charging trailer's draw, as a fraction of AIR_DRAW_*. Labelled honest model: fixed-time fill.
const TRAILER_AIR_DRAW := 0.75
## Seconds to charge a freshly coupled trailer: coupling costs ~3 bar of primary.
const TRAILER_CHARGE_S := 8.0

var air_primary := AIR_SPAWN_BAR    ## bar, contract 'air_primary' (SPN 1087)
var air_secondary := AIR_SPAWN_BAR  ## bar, contract 'air_secondary' (SPN 1088)
var retarder_state := 0             ## %, contract 'retarder_state' (magnitude; see the contract desc)
var axle_load := 0.0                ## kg, contract 'axle_load' (SPN 582, off the suspension)
var pto_state := false              ## contract 'pto_state' (PTO request and engine running)
var engine_load := 0                ## %, contract 'engine_load' (J1939 SPN 92)

# --- CiA 422 body network (across the CiA 413 gateway; zeros without a refuse body) -----
var body_state := 0                 ## contract 'body_state' (RefuseBody.State)
var body_pos := 0                   ## %, contract 'body_pos' (read off the posed arm mesh)
var body_inhibit := false           ## contract 'body_inhibit' (chassis-computed, body-published)
var body_bus := false               ## contract 'body_bus'
var hopper_load := 0                ## %, contract 'hopper_load' (adds real chassis mass)

# --- ISO 11992 trailer bus (zeros bobtail, and on a unit with no data pair) --------------
var trailer_connected := false      ## contract 'trailer_connected' (coupled AND the bus claimed)
var trailer_axle_load := 0.0        ## kg, contract 'trailer_axle_load' (off the bogie's springs)
var trailer_brake_demand := 0       ## %, contract 'trailer_brake_demand' (EBS11, what was sent)
var trailer_abs := false            ## contract 'trailer_abs' (EBS21, off the trailer's own slip)


# --- pure derivations (unit-tested in tests/test_truck.gd) -------------------------------

## One reservoir's step (bar). `aux01` (a coupled trailer) draws `draw_rate` bar/s per unit.
static func air_step(current: float, brake01: float, prev_brake01: float, running: bool,
		delta: float, charge_rate: float, press_bar: float, draw_rate: float, aux01 := 0.0) -> float:
	var rise := maxf(0.0, clampf(brake01, 0.0, 1.0) - clampf(prev_brake01, 0.0, 1.0))
	var next := current - rise * press_bar - clampf(aux01, 0.0, 1.0) * draw_rate * delta
	if running:
		next += charge_rate * delta
	return clampf(next, 0.0, AIR_MAX_BAR)


## A coupled trailer's reservoir fill after one tick (0 = just coupled and empty, 1 = charged).
static func trailer_air_step(charge01: float, delta: float) -> float:
	return clampf(charge01 + delta / TRAILER_CHARGE_S, 0.0, 1.0)


## What a charging trailer draws from EACH tractor circuit, as air_step's `aux01`.
static func trailer_air_draw(coupled: bool, charge01: float) -> float:
	return TRAILER_AIR_DRAW if coupled and charge01 < 1.0 else 0.0


## The MINIMUM of the two circuits: one healthy circuit must not mask a failing one.
static func spring_brakes_applied(primary: float, secondary: float) -> bool:
	return minf(primary, secondary) < AIR_SPRING_BRAKE_BAR


## True on the tick the gate goes false -> true: one driver notice per application.
static func spring_brake_notice_edge(applied: bool, was_applied: bool) -> bool:
	return applied and not was_applied


## EBS11 braking demand (0..1) down the trailer bus: foot brake plus the retarder's share
## (`Drivetrain.retarder_fraction`), or the trailer would push a retarding tractor.
static func trailer_brake_blend(brake01: float, retarder_pct: int, retarder_frac: float) -> float:
	var retarder_share := clampf(float(retarder_pct) / 100.0, 0.0, 1.0) \
			* clampf(retarder_frac, 0.0, 1.0)
	return clampf(clampf(brake01, 0.0, 1.0) + retarder_share, 0.0, 1.0)


## Publish the bobtail state on the whole trailer bus: false/0 on every signal.
func clear_trailer_bus() -> void:
	trailer_connected = false
	trailer_axle_load = 0.0
	trailer_brake_demand = 0
	trailer_abs = false
