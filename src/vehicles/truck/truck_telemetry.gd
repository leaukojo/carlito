class_name TruckTelemetry
extends VehicleTelemetry
## Truck telemetry (J1939 FMS set). Field names are exactly the contract names. `engine_hours`
## stays on the shared VehicleTelemetry (the tractor declares it too).
##
## Read out of the sim: axle_load, retarder_state. Modeled: engine_load, air_primary/secondary
## (below AIR_SPRING_BRAKE_BAR the spring brakes gate movement). body_* fields cross the CiA 413
## gateway from the CiA 422 refuse body; trailer_* fields are the ISO 11992 bus. Both publish
## zeros when absent (no body / bobtail).

# --- air brake reservoirs (modeled honest values) --------------------------------------
const AIR_MAX_BAR := 12.0     ## contract 'air_primary'/'air_secondary' range max
## Spawn pressure: above the spring-brake cut-in but below working pressure, so the bars visibly
## charge after start.
const AIR_SPAWN_BAR := 7.0
## THE GATE. Below this on EITHER circuit the spring brakes apply and the truck cannot move.
## Below the contract's 'warn' (5.0), so the driver gets a band to stop in (FMVSS 121 / ECE R13).
const AIR_SPRING_BRAKE_BAR := 3.0
const AIR_CHARGE_RATE := 0.45      ## bar/s the compressor makes, engine running only
const AIR_DRAW_PRIMARY := 1.10     ## bar/s drawn at a full brake application, circuit 1
## Circuit 2 runs off a smaller reservoir, so the pair (SPN 1087/1088) diverges under braking.
const AIR_DRAW_SECONDARY := 0.85
## A coupled trailer's draw on these reservoirs, as a fraction of a full brake application (it rides
## air_step's draw rates, so primary dips further than secondary). Labelled honest model:
## fixed-time fill, not a pressure-driven charge model.
const TRAILER_AIR_DRAW := 0.75
## Seconds to charge a freshly coupled trailer. Net primary rate while charging is
## 0.45 - 0.825 = -0.375 bar/s, so coupling costs 3 bar; braking while it charges reaches the
## spring-brake gate in under 3 s.
const TRAILER_CHARGE_S := 8.0

# --- ISO 11992 trailer bus ---------------------------------------------------------------
## Slip at which the trailer's ABS reports active (EBS21), well above the slip a braked axle
## settles at. Unsigned: an undriven axle has no traction case to tell from a lock.
const TRAILER_ABS_SLIP := 0.30

# Retarder math lives on Drivetrain; this class only reports what BaseVehicle applied.

const GRAVITY := 9.8  ## m/s^2, for the suspension-force -> kilograms read

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

## One reservoir's step (bar). Charges only while running. Draw is pedal position only. `aux01`
## (coupled trailer) is a second consumer, clamped separately then summed.
static func air_step(current: float, brake01: float, running: bool, delta: float,
		charge_rate: float, draw_rate: float, aux01 := 0.0) -> float:
	var demand := clampf(brake01, 0.0, 1.0) + clampf(aux01, 0.0, 1.0)
	var next := current - demand * draw_rate * delta
	if running:
		next += charge_rate * delta
	return clampf(next, 0.0, AIR_MAX_BAR)


## A coupled trailer's reservoir fill after one tick (0 = just coupled and empty, 1 = charged).
static func trailer_air_step(charge01: float, delta: float) -> float:
	return clampf(charge01 + delta / TRAILER_CHARGE_S, 0.0, 1.0)


## What a charging trailer draws from EACH tractor circuit, as air_step's `aux01`. Zero once charged
## and bobtail: a transient at coupling.
static func trailer_air_draw(coupled: bool, charge01: float) -> float:
	return TRAILER_AIR_DRAW if coupled and charge01 < 1.0 else 0.0


## Whether the spring brakes have applied. Reads the MINIMUM of the two circuits: one healthy
## circuit must not mask a failing one.
static func spring_brakes_applied(primary: float, secondary: float) -> bool:
	return minf(primary, secondary) < AIR_SPRING_BRAKE_BAR


## True on the tick the gate goes false -> true: one driver notice per application.
static func spring_brake_notice_edge(applied: bool, was_applied: bool) -> bool:
	return applied and not was_applied


## Axle load in kilograms from the summed suspension force (N) carrying that axle: what the springs
## held up this tick, not a mass lookup.
static func axle_load_kg(suspension_force_n: float) -> float:
	return maxf(suspension_force_n, 0.0) / GRAVITY


## EBS11 blend: braking demand (0..1) sent down the trailer bus, foot brake plus retarder; the
## trailer's own wheels brake with it.
##
## The retarder acts on the TRACTOR's axle alone, so without a share down the bus the trailer would
## push the tractor. Retarder at full is Drivetrain.RETARDER_MAX_FRAC of the tractor's brake
## torque, asked of the trailer's brakes at the same fraction. `retarder_pct` (what ran) inherits
## the speed fade.
static func trailer_brake_blend(brake01: float, retarder_pct: int) -> float:
	var retarder_share := clampf(float(retarder_pct) / 100.0, 0.0, 1.0) * Drivetrain.RETARDER_MAX_FRAC
	return clampf(clampf(brake01, 0.0, 1.0) + retarder_share, 0.0, 1.0)


## EBS21: is the trailer's ABS active? `max_slip` is the worst |longitudinal slip| across the
## trailer's RayWheels this tick (undriven, so slip is a lock).
static func trailer_abs_active(max_slip: float) -> bool:
	return max_slip > TRAILER_ABS_SLIP


## Publish the bobtail state on the whole trailer bus: false/0 on every signal.
func clear_trailer_bus() -> void:
	trailer_connected = false
	trailer_axle_load = 0.0
	trailer_brake_demand = 0
	trailer_abs = false
