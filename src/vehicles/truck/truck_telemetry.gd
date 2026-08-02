class_name TruckTelemetry
extends VehicleTelemetry
## Truck telemetry (J1939 flavor). Adds the chassis "out" fields on top of the ground-vehicle
## VehicleTelemetry. Field names are EXACTLY the contract names (air_primary / air_secondary /
## retarder_state / axle_load / pto_state / engine_load / engine_hours) so the Bridge's
## name-keyed marshaling and the dashboard's t.get(name) reads work unchanged.
##
## The signal selection is cited rather than tasteful: every chassis signal here is in the
## published FMS set — the standard subset of J1939-71 six European manufacturers agreed to
## expose in 2002, precisely BECAUSE the internal bus is proprietary. That public-versus-
## proprietary line is the lesson the truck family carries.
##
## What is read out of the sim and what is modeled, per rule 3:
##   - axle_load        READ. Summed RayWheel suspension force on the rear axle. Weight
##                      transfer under braking moves it because the suspension really moved.
##   - retarder_state   READ. The driveline torque actually applied (BaseVehicle's
##                      retarder_torque_applied) — not the request echoed back, which is the
##                      same rule diff_lock_state follows.
##   - engine_load      modeled (VehicleTelemetry.engine_load_pct), off the drivetrain's own
##                      torque curve at the drivetrain's own rpm.
##   - air_primary /    MODELED, and labelled: the truck has no simulated pneumatic circuit.
##     air_secondary    A reservoir charges while the engine runs and is drawn down by brake
##                      applications. It is worth having because it is not just a bar — below
##                      AIR_SPRING_BRAKE_BAR the spring brakes apply and the truck cannot move,
##                      the same shape as the train's pantograph cutting traction.
##
## The CiA 422 body fields below come from a SECOND NETWORK across a gateway, and their model lives
## on RefuseBody rather than here — this class only publishes them:
##   - body_pos         READ off the POSED arm mesh, not off the unit's own travel fraction.
##   - body_state       READ off the body unit; body_inhibit READ off chassis state (speed, PTO,
##                      parking brake) and published on the body network — the gateway's point.
##   - body_bus /       MODELED, and labelled. See RefuseBody. hopper_load earns its place by
##     hopper_load      adding real MASS to the chassis, so axle_load above reports it as a
##                      consequence — there is no laden term in axle_load or engine_load.
## A truck with no refuse body (the firetruck) publishes real zeros on all five every tick, never a
## gap, which is what keeps the cluster the same shape across the family.
##
## The ISO 11992 fields below come from the TRAILER bus, and the lesson there is how LITTLE is on
## it: part 2 of the standard is the application layer for brakes and running gear only, so four
## signals are the whole boundary. Two of them are read out of the trailer's own unmodified
## RayWheels rather than invented:
##   - trailer_axle_load   READ. Summed suspension force on the trailer's bogie, through the SAME
##                         axle_load_kg the drive axle uses — one model, not two.
##   - trailer_abs         READ. The trailer's worst wheel slip against TRAILER_ABS_SLIP. It has
##                         real wheels, so it can really lock them.
##   - trailer_brake_demand  a REPORT of the EBS11 blend the tractor sent (see
##                         trailer_brake_blend), which is also what the trailer really brakes with.
##   - trailer_connected   the coupling claim, and its third state is the content — see the
##                         contract desc, and VehicleSpec.trailer_bus_equipped.
## Bobtail publishes a real false / 0 on all four every tick (clear_trailer_bus), the same rule the
## body fields and the tractor's implements follow.

# --- air brake reservoirs (modeled honest values) --------------------------------------
const AIR_MAX_BAR := 12.0     ## contract 'air_primary'/'air_secondary' range max
## Spawn pressure: a truck that has stood and bled down. Above the spring-brake cut-in, so you
## can drive away immediately, but below the working pressure — the bars visibly charge after
## start, which is the whole demonstration.
const AIR_SPAWN_BAR := 7.0
## THE GATE. Below this on EITHER circuit the spring brakes apply and the truck cannot move.
## Deliberately below the contract's 'warn' (5.0), which is only the low-pressure WARNING: real
## practice (FMVSS 121 / ECE R13) puts the warning well above the cut-in so the driver gets a
## band to stop in rather than going from a red lamp to immobile in the same instant.
const AIR_SPRING_BRAKE_BAR := 3.0
const AIR_CHARGE_RATE := 0.45      ## bar/s the compressor makes, engine running only
const AIR_DRAW_PRIMARY := 1.10     ## bar/s drawn at a full brake application, circuit 1
## Circuit 2 runs off a smaller reservoir, so the two diverge under braking instead of being a
## clone of each other. The pair is the point (SPN 1087/1088), the way the tractor's
## wheel_speed / ground_speed pair is: the redundancy has to be visible to mean anything.
const AIR_DRAW_SECONDARY := 0.85
## A COUPLED TRAILER DRAWS AIR, and it does it through the reservoirs above rather than through a
## term of its own: its own reservoirs charge off the tractor's supply, so it is simply a second
## consumer on both circuits while it fills. Expressed as a fraction of a full brake application so
## it rides air_step's existing draw rates — the primary therefore dips further than the secondary,
## which is the same divergence the pair already has. LABELLED HONEST MODEL: the fill is a fixed
## time rather than a pressure-driven charge, because a second pneumatic model would be two models
## of the same thing.
const TRAILER_AIR_DRAW := 0.75
## Seconds to charge a freshly coupled trailer's reservoirs. Sized to be SEEN and to bite: at 0.75
## of the primary draw the net rate is 0.45 - 0.825 = -0.375 bar/s, so coupling costs 3 bar and
## takes AIR1 from the 7.0 spawn pressure below the 5.0 low-pressure warn before it recovers. Brake
## while it charges and the net is -1.475 bar/s, which reaches the spring-brake gate in under 3 s —
## couple and drive off without letting it charge and the rig can genuinely stop itself.
const TRAILER_CHARGE_S := 8.0

# --- ISO 11992 trailer bus ---------------------------------------------------------------
## Longitudinal slip at which the trailer's ABS reports active (EBS21). Well above the 0.024-0.029
## a braked axle settles at, so it means a wheel really going toward a lock rather than normal
## braking slip. Unsigned like the tractor's wheel_slip: a semi-trailer axle is undriven, so there
## is no traction case to tell apart from a lock.
const TRAILER_ABS_SLIP := 0.30

# The retarder's own math lives on Drivetrain, next to the differential lock, because it is
# DRIVELINE behaviour: BaseVehicle adds its torque to the driven wheels' brake torque so
# RayWheel integrates it like every other brake. This class only reports what was applied.

const GRAVITY := 9.8  ## m/s^2, for the suspension-force -> kilograms read

var air_primary := AIR_SPAWN_BAR    ## bar, contract 'air_primary' (SPN 1087)
var air_secondary := AIR_SPAWN_BAR  ## bar, contract 'air_secondary' (SPN 1088)
var retarder_state := 0             ## %, contract 'retarder_state' (magnitude; see the contract desc)
var axle_load := 0.0                ## kg, contract 'axle_load' (SPN 582, off the suspension)
var pto_state := false              ## contract 'pto_state' (PTO request and engine running)
var engine_load := 0                ## %, contract 'engine_load' (J1939 SPN 92)
var engine_hours := 0.0             ## h, contract 'engine_hours' (SPN 247; survives respawn)

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

## One air reservoir's step, in bar. The compressor is engine-driven, so it only charges while
## running; a brake application draws the reservoir down in proportion to how hard it is pressed.
## ONE function used for both circuits with different rates — the dual circuit is a second
## reservoir, not a second model.
##
## What the model deliberately does NOT consume air for, so these read as decisions and not gaps:
## the handbrake (a real spring brake spends air being RELEASED, not held), the spring brakes
## applying, and anything speed- or load-dependent — the draw is the pedal position and nothing
## else, so a stationary truck with the pedal down bleeds at the same rate as one hauling down a
## pass. Pedal position alone is what makes the gate reachable by doing something a driver can
## see themselves doing, which is the whole point of the signal; the rest would be extra terms in
## a labelled honest model that nothing on the dashboard could distinguish.
##
## `aux01` is a SECOND CONSUMER on the same circuit, in the same units as the pedal — a freshly
## coupled trailer charging its reservoirs off this supply, and nothing else today. It is clamped
## SEPARATELY from the pedal and then summed, so the two can together ask for more than one full
## application (they are independent taps on one reservoir, which is what they physically are)
## while a garbage value on either one is still sanitized to its own [0, 1].
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


## What a charging trailer draws from EACH tractor circuit, as air_step's `aux01`. Zero once it is
## charged and zero bobtail — the air only moves while the reservoirs are actually filling, so this
## is a transient at the coupling and not a permanent tax on the supply.
static func trailer_air_draw(coupled: bool, charge01: float) -> float:
	return TRAILER_AIR_DRAW if coupled and charge01 < 1.0 else 0.0


## Whether the spring brakes have applied — the gate that stops the truck moving.
##
## Reads the MINIMUM of the two circuits, which is what makes the redundancy real: one healthy
## circuit must not mask a failing one, because the spring brake chambers are held off by the
## supply and a supply failure anywhere sets them. Pure, so the rule is asserted rather than
## just described.
static func spring_brakes_applied(primary: float, secondary: float) -> bool:
	return minf(primary, secondary) < AIR_SPRING_BRAKE_BAR


## Axle load in kilograms from the summed suspension force (N) carrying that axle. A weight, not
## a mass lookup: the number is whatever the springs were actually holding up this tick.
static func axle_load_kg(suspension_force_n: float) -> float:
	return maxf(suspension_force_n, 0.0) / GRAVITY


## THE EBS11 BLEND: the braking demand (0..1) the towing unit sends down the trailer bus, from the
## foot brake and the retarder together. This is not just the readout — it is what the trailer's
## own wheels brake with, and trailer_brake_demand is then read off it.
##
## The retarder has to be in here, and the reason is physical rather than tidy: it acts on the
## TRACTOR's driven axle alone, so retarding a coupled rig without sending a share down the bus
## leaves 14 t of trailer pushing an 8 t tractor. Its share is ARITHMETIC, not taste — the retarder
## at full is Drivetrain.RETARDER_MAX_FRAC of the tractor's own brake torque, so it asks the trailer
## for that same fraction of the trailer's brakes and the two ends of the rig scrub at matched
## fractions of what each has. Taking `retarder_pct` (retarder_state, what actually ran) rather than
## the request also means the demand inherits the speed fade for free: at walking pace the retarder
## has faded out, so it stops asking the trailer for anything.
static func trailer_brake_blend(brake01: float, retarder_pct: int) -> float:
	var retarder_share := clampf(float(retarder_pct) / 100.0, 0.0, 1.0) * Drivetrain.RETARDER_MAX_FRAC
	return clampf(clampf(brake01, 0.0, 1.0) + retarder_share, 0.0, 1.0)


## EBS21: is the trailer's ABS active? `max_slip` is the worst |longitudinal slip| across the
## trailer's own RayWheels this tick. Undriven wheels, so a slip is a lock and nothing else.
static func trailer_abs_active(max_slip: float) -> bool:
	return max_slip > TRAILER_ABS_SLIP


## Publish the bobtail truth on the whole trailer bus: nothing coupled (or nothing claiming), so a
## real false / 0 on every signal EVERY TICK rather than a gap. That is what keeps the cluster the
## same shape whether the semi is coupled or running solo, exactly as a detached implement keeps
## the tractor's.
func clear_trailer_bus() -> void:
	trailer_connected = false
	trailer_axle_load = 0.0
	trailer_brake_demand = 0
	trailer_abs = false


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["air_primary"] = air_primary
	d["air_secondary"] = air_secondary
	d["retarder_state"] = retarder_state
	d["axle_load"] = axle_load
	d["pto_state"] = pto_state
	d["engine_load"] = engine_load
	d["engine_hours"] = engine_hours
	d["body_state"] = body_state
	d["body_pos"] = body_pos
	d["body_inhibit"] = body_inhibit
	d["body_bus"] = body_bus
	d["hopper_load"] = hopper_load
	d["trailer_connected"] = trailer_connected
	d["trailer_axle_load"] = trailer_axle_load
	d["trailer_brake_demand"] = trailer_brake_demand
	d["trailer_abs"] = trailer_abs
	return d
