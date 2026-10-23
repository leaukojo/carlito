class_name VehicleTelemetry
extends RefCounted
## Per-tick telemetry published by BaseVehicle, covering every contract "out" signal for ground
## vehicles (car/truck/tractor). Motion is read out of the sim; fuel, coolant and battery are
## honest models, labelled as modeled (the burn read from the crank's delivered fuel). Non-trivial
## derivations are the static pure functions below. A respawn reseeds this object IN PLACE (`BaseVehicle._reseed_telemetry`), so a
## declaration default is the spawn value and a new field needs nothing said elsewhere.

# --- GPS mapping (world XZ -> lat/lon around the Paris origin) ---
const GPS_ORIGIN_LAT := 48.8566
const GPS_ORIGIN_LON := 2.3522
const METERS_PER_DEG_LAT := 111320.0  ## mean meters per degree of latitude

# --- fuel: a Willans line on the delivered fuel (modeled; docs/drivetrain.md § Fuel) ---
## PETROL: pump E10. DIESEL: EN 590, the road diesels' and the tractor's.
enum Fuel { PETROL, DIESEL }
## Indicated efficiency per Fuel: the fuel's chemical power over the power of the torque it adds
## above the motoring law. PETROL 0.41 puts the `sedan`'s minimum within 1 % of US EPA's measured
## 2.5 L Malibu map's 239 g/kWh, through the same engine's motoring curve; DIESEL 0.45 is Volvo Penta's TD640VE and TAD1641GE at
## full load over their published friction power (0.450, 0.456). Sources: docs/sources.md § Fuel.
const FUEL_INDICATED_EFFICIENCY: Array[float] = [0.41, 0.45]
## Lower heating value (MJ/kg) per Fuel: the Malibu map's E10 test fuel, Volvo Penta's rating fuel.
const FUEL_HEATING_MJ_KG: Array[float] = [41.05, 42.7]
## Density (kg/L) per Fuel, the same two fuels.
const FUEL_DENSITY_KG_L: Array[float] = [0.757, 0.84]
## COMPROMISE: the tank is a game scale. A body's tank lasts this long at full fuel at its rated
## speed (`tank_litres`), as long as the rigid crank's tank at full throttle (FUEL_IDLE_BURN plus
## FUEL_LOAD_BURN, 0.20 %/s); the burn that drains it is real. A real tank (a saloon's ~50 L lasts about an hour flat out) never visibly
## moves in a session: undoing it is a litre figure per body, and a gauge that sits at full.
const FUEL_TANK_FULL_LOAD_S := 500.0
## The rigid crank's throttle model (boat, plane): their engines turn at the wheel's or the prop's
## speed and carry no crank torque law to read the burn from.
const FUEL_IDLE_BURN := 0.02   ## %/s burned at idle while running
const FUEL_LOAD_BURN := 0.18   ## extra %/s at full throttle

# --- auxiliary-system model constants ---
const COOLANT_AMBIENT := 20.0    ## degC cold-start / engine-off resting temp
const COOLANT_OPERATING := 90.0  ## degC steady running temp at no load
const COOLANT_HOT := 108.0       ## degC steady running temp at full load
const BATTERY_RESTING := 12.6    ## V engine off
const BATTERY_CHARGING := 14.2   ## V engine running (alternator), before load droop

const GRAVITY := 9.8  ## m/s^2, for the suspension-force -> kilograms read

## PTO power over the crank power it takes: ASAE D497.4's "PTO power ~0.90 of net flywheel power",
## the tractor's driveline figure, taken for the truck's gear PTO too (an estimate there). Sources:
## docs/sources.md § PTO power.
const PTO_EFFICIENCY := 0.90

# --- status bitfield (contract 'status', u16) ---
## FROZEN wire layout: a new flag appends at bit 7 or above, never renumbering (contract-edit skill).
const ST_IGNITION := 1 << 0    ## engine running (key in Ignition)
## Wheels in contact, or the wheel-less body's own landed predicate (drone and boat overwrite
## this in `_tick_extras` via `with_status_bit`).
const ST_GROUND := 1 << 1
const ST_MOVING := 1 << 2      ## |speed| above the standstill epsilon
const ST_REVERSE := 1 << 3     ## engaged gear is R
const ST_NEUTRAL := 1 << 4     ## engaged gear is N
const ST_HANDBRAKE := 1 << 5   ## parking brake engaged
const ST_HEADLIGHTS := 1 << 6  ## headlights at LOW or brighter

# --- motion (measured from the sim) ---
var speed := 0.0        ## signed longitudinal m/s (contract 'speed')
var kmh := 0.0          ## absolute km/h (contract 'kmh')
var rpm := 0.0          ## real engine RPM out of the drivetrain (contract 'rpm')
var gear_byte := 0      ## RAMN byte: 0=N, 1..24=D1-D24, 255=R, 254=P (contract 'gear')
## The gearbox's input over output speed (contract 'gear_ratio', J1939 SPN 526):
## `Drivetrain.gearbox_ratio`, on a wheel-driving body; 0 elsewhere.
var gear_ratio := 0.0
var throttle := 0.0     ## -1..1 as applied, signed by direction (contract 'throttle')
var steer := 0.0        ## -1..1 as applied (contract 'steer')
## Body angular rates and accelerations (DroneCAN's `angular_velocity` / `linear_acceleration`).
var yaw := 0.0          ## yaw rate rad/s about the body up axis (contract 'yaw')
var roll_rate := 0.0    ## roll rate rad/s about the body forward axis, + = right side down (contract 'roll_rate')
var pitch_rate := 0.0   ## pitch rate rad/s about the body right axis, + = nose up (contract 'pitch_rate')
var acc_long := 0.0     ## longitudinal accel m/s^2, smoothed (contract 'accLong')
var acc_lat := 0.0      ## lateral accel m/s^2, smoothed (contract 'accLat')
var acc_vert := 0.0     ## vertical accel m/s^2 along body up, smoothed (contract 'acc_vert')
## Attitude/height.
var pitch := 0.0        ## deg, + = nose/bow up (contract 'pitch')
var roll := 0.0         ## deg, + = starboard/right side down (contract 'roll')
var altitude := 0.0     ## m above sea level (contract 'altitude'; world Y, water is y=0)
var vspeed := 0.0       ## m/s variometer, + = climbing (contract 'vspeed')
## Instanced signal 'slip' (count 2), per-axle so understeer and oversteer differ.
var slip_front := 0.0   ## mean |slip ratio|, front axle (contract 'slip' element 0)
var slip_rear := 0.0    ## mean |slip ratio|, rear axle (contract 'slip' element 1)
var ground := false     ## all wheels in contact (contract 'ground')
var impact := 0.0       ## impact event magnitude m/s^2, peak-held (contract 'impact')

# --- configuration (DECLARED, not measured) ---
## Copied off the spec once in BaseVehicle._ready.
var speed_limit := 0    ## road-speed governor km/h, 0 = ungoverned (contract 'speed_limit')

# --- navigation ---
var pos_x := 0.0        ## world X (contract 'posX')
var pos_z := 0.0        ## world Z (contract 'posZ')
var heading := 0.0      ## compass heading deg, [0,360) (contract 'heading')
var lat := GPS_ORIGIN_LAT   ## GPS latitude, Paris origin (contract 'lat')
var lon := GPS_ORIGIN_LON   ## GPS longitude, Paris origin (contract 'lon')
var odo := 0.0          ## odometer km (contract 'odo')
## True wind, from the level's WindField (`true_wind`). Filled by BaseVehicle for a wheeled body
## and by the boat; the contract declares it for car, truck, tractor and boat.
var twd := 0.0          ## deg, contract 'twd' (the bearing it comes FROM)
var tws := 0.0          ## m/s, contract 'tws'
## The odometer's twin: climbs only, for as long as the machine lasts. The contract declares it
## for tractor, truck and boat; elsewhere it counts quietly, and the dashboard gates HRS on it.
var engine_hours := 0.0 ## h, contract 'engine_hours' (J1939 SPN 247)

# --- auxiliary systems (modeled, not measured) ---
var fuel := 100.0                ## % remaining (contract 'fuel')
## L/h, contract 'fuel_rate': `fuel_rate_lph` on a wheel-driving crank, the boat's own model on the
## boat (`BoatTelemetry.fuel_rate_model`); 0 elsewhere, where the contract does not declare it.
var fuel_rate := 0.0
var coolant := COOLANT_AMBIENT   ## degC (contract 'coolant')
var battery := BATTERY_RESTING   ## V (contract 'battery' out; distinct from the 'in' warning LED)
var status := 0                  ## u16 bitfield (contract 'status')


# --- pure derivations (unit-tested) -----------------------------------------

## Latitude for a world Z, mapping -Z to north. A 64-bit float, so the contract's f64 lat/lon
## precision survives.
static func gps_lat(world_z: float) -> float:
	return GPS_ORIGIN_LAT + (-world_z) / METERS_PER_DEG_LAT


## Longitude for a world X (+X = east), meters-per-degree shrunk by the origin latitude.
static func gps_lon(world_x: float) -> float:
	return GPS_ORIGIN_LON + world_x / (METERS_PER_DEG_LAT * cos(deg_to_rad(GPS_ORIGIN_LAT)))


## Compass heading [0,360) from a forward vector. 0 = north (-Z), 90 = east (+X).
static func heading_from_forward(forward: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


## True wind as (speed m/s, bearing deg it comes FROM). `WindField.direction_deg` is the heading
## the wind blows TOWARD, so the meteorological inversion happens here and nowhere else (a wind is
## named by where it comes from, a current by where it goes). Flattened like every horizontal
## flow. Dead calm reads (0, 0).
static func true_wind(wind: Vector3) -> Vector2:
	var flat := Vector3(wind.x, 0.0, wind.z)
	var flow := flat.length()
	if flow < 1e-6:
		return Vector2.ZERO
	return Vector2(flow, heading_from_forward(-flat))


## Odometer step: absolute distance travelled, in km.
static func odo_step(prev_km: float, speed_ms: float, delta: float) -> float:
	return prev_km + absf(speed_ms) * delta / 1000.0


## Body-frame acceleration (long, lat, vert) m/s^2 from the velocity change over the tick,
## projected onto forward/right/up. Kinematic, with no gravity term, so a body at rest and one in
## free fall both read zero. The caller smooths.
static func body_accel(v_now: Vector3, v_prev: Vector3, delta: float,
		forward: Vector3, right: Vector3, up: Vector3) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	var a := (v_now - v_prev) / delta
	return Vector3(a.dot(forward), a.dot(right), a.dot(up))


## Impact magnitude gate: the acceleration spike is only an event once it clears the threshold,
## otherwise 0. The caller peak-holds it so a one-tick spike stays visible.
static func impact_gate(accel_mag: float, threshold: float) -> float:
	return accel_mag if accel_mag >= threshold else 0.0


## The burn (L/h) on a wheel-driving crank at the `delivered` fuel (`Drivetrain.applied_throttle`):
## it adds `delivered * (curve - motoring)` to the crank over its motoring law
## (`Drivetrain.crank_torque`), and its chemical power is that torque's power over the fuel's
## indicated efficiency. 0 at zero fuel (a cut burns nothing) and with the key off. At idle the
## controller's fuel nets out the friction (and any creep or PTO load), so idle burn is that power
## over the efficiency, and brake-specific consumption rises at part load on its own.
static func fuel_rate_lph(spec: VehicleSpec, at_rpm: float, delivered: float,
		running: bool) -> float:
	if not running:
		return 0.0
	var span := Drivetrain.engine_torque(spec, at_rpm) - Drivetrain.motoring_torque(spec, at_rpm)
	var power_w := clampf(delivered, 0.0, 1.0) * maxf(span, 0.0) * maxf(at_rpm, 0.0) \
			/ Drivetrain.RADS_TO_RPM
	var kind := spec.fuel_type
	var kg_per_s := power_w / (FUEL_INDICATED_EFFICIENCY[kind] * FUEL_HEATING_MJ_KG[kind] * 1e6)
	return kg_per_s / FUEL_DENSITY_KG_L[kind] * 3600.0


## The burn (L/h) at full fuel at the rated speed (`PedalMap.rated_rpm`): the tank's scale and the
## coolant's full load.
static func rated_fuel_rate_lph(spec: VehicleSpec) -> float:
	return fuel_rate_lph(spec, PedalMap.rated_rpm(spec), 1.0, true)


## The tank (L): FUEL_TANK_FULL_LOAD_S at the rated burn (the COMPROMISE at the constant).
static func tank_litres(spec: VehicleSpec) -> float:
	return rated_fuel_rate_lph(spec) * FUEL_TANK_FULL_LOAD_S / 3600.0


## Tank level step (%): `burn_lph` drawn from a `tank_l` litre tank over the tick.
static func fuel_drain(prev_pct: float, burn_lph: float, tank_l: float, delta: float) -> float:
	if tank_l <= 0.0:
		return prev_pct
	return clampf(prev_pct - burn_lph * delta / 3600.0 / tank_l * 100.0, 0.0, 100.0)


## The rigid crank's fuel step (%): idle burn plus a load term, only while running.
static func fuel_step(prev_pct: float, load_frac: float, running: bool, delta: float) -> float:
	if not running:
		return prev_pct
	var burn := (FUEL_IDLE_BURN + FUEL_LOAD_BURN * clampf(load_frac, 0.0, 1.0)) * delta
	return clampf(prev_pct - burn, 0.0, 100.0)


## Steady-state coolant target: ambient when off, warming toward the hot end with load (on a
## wheel-driving crank the fuel power's share of its rated figure: the heat the cooling rejects
## follows the fuel's energy, not the pedal).
static func coolant_target(running: bool, load_frac: float) -> float:
	if not running:
		return COOLANT_AMBIENT
	return lerpf(COOLANT_OPERATING, COOLANT_HOT, clampf(load_frac, 0.0, 1.0))


## Linear slew toward the coolant target (`rate` degC/s); never overshoots.
static func coolant_step(prev_c: float, target_c: float, rate: float, delta: float) -> float:
	return move_toward(prev_c, target_c, rate * delta)


## Battery terminal voltage: resting when off, alternator-charged and drooping under load when
## running.
static func battery_volts(running: bool, load_frac: float) -> float:
	if not running:
		return BATTERY_RESTING
	return BATTERY_CHARGING - 0.6 * clampf(load_frac, 0.0, 1.0)


## Axle load (kg) from the summed suspension force (N) on that axle, not a mass lookup. Shared
## by the truck's drive axle and trailer bogie and the tractor's rear axle (SPN 582).
static func axle_load_kg(suspension_force_n: float) -> float:
	return maxf(suspension_force_n, 0.0) / GRAVITY


## Engine load, J1939 SPN 92: delivered torque over peak torque. Shared by the tractor (ISOBUS) and
## the truck (J1939). A driven PTO is in it as the fuel its crank load takes
## (`Drivetrain.accessory_torque`). The denominator is the peak, not the torque at the current rpm,
## which would cancel to throttle.
static func engine_load_pct(engine_rpm: float, throttle_in: float, spec: VehicleSpec) -> float:
	var peak := Drivetrain.peak_torque(spec)
	if peak <= 0.0:
		return 0.0
	var delivered := Drivetrain.engine_torque(spec, engine_rpm) \
			* clampf(absf(throttle_in), 0.0, 1.0)
	return clampf(delivered / peak, 0.0, 1.0) * 100.0


## The load (N·m, `Drivetrain.accessory_torque`) a PTO driving `shaft_kw` at the shaft puts on the
## crank: that power at `rated_engine_rpm`, the engine speed the PTO turns at its rated shaft speed,
## through PTO_EFFICIENCY. A constant torque, never the power over the live speed, whose falling
## slope would feed back on the crank as a negative stiffness.
static func pto_crank_torque(shaft_kw: float, rated_engine_rpm: float) -> float:
	if rated_engine_rpm <= 0.0:
		return 0.0
	return maxf(shaft_kw, 0.0) * 1000.0 / (rated_engine_rpm / Drivetrain.RADS_TO_RPM) \
			/ PTO_EFFICIENCY


## Hour meter step: real time under the key (J1939 SPN 247, which ISOBUS inherits). Only climbs;
## a respawn is a new machine.
static func hours_step(prev_h: float, running: bool, delta: float) -> float:
	return prev_h + delta / 3600.0 if running else prev_h


## Pack the status bitfield from current vehicle state.
static func pack_status(ignition: bool, ground_contact: bool, moving: bool,
		gear_byte_: int, handbrake: bool, headlights: bool) -> int:
	var s := 0
	if ignition:
		s |= ST_IGNITION
	if ground_contact:
		s |= ST_GROUND
	if moving:
		s |= ST_MOVING
	if gear_byte_ == Drivetrain.GEAR_R:
		s |= ST_REVERSE
	if gear_byte_ == Drivetrain.GEAR_N:
		s |= ST_NEUTRAL
	if handbrake:
		s |= ST_HANDBRAKE
	if headlights:
		s |= ST_HEADLIGHTS
	return s


## Set or clear one already-packed status bit, so a subclass can override from `_tick_extras` a
## bit `pack_status` cannot compute from shared state (the drone and boat ST_GROUND).
static func with_status_bit(packed: int, bit: int, on: bool) -> int:
	return (packed | bit) if on else (packed & ~bit)


# --- bridge marshaling -------------------------------------------------------

## Contract name for a telemetry field spelled differently (the wire names are the contract's).
const WIRE_NAMES := {
	"gear_byte": "gear",
	"acc_long": "accLong",
	"acc_lat": "accLat",
	"pos_x": "posX",
	"pos_z": "posZ",
}
## Fields the wire carries as whole units off a float accumulator.
const WIRE_ROUNDED := ["rpm", "fuel", "coolant", "soc",
		"gimbal_pitch_actual", "gimbal_yaw_actual"]
## Fields the wire carries as a percent (i8) of a -1..1 fraction.
const WIRE_PERCENT := ["throttle", "steer"]
## Fields that reach the wire only through a synthesised signal, never under their own name.
const WIRE_PRIVATE := ["slip_front", "slip_rear"]

## Every "out" signal this vehicle declares, keyed by contract name, in contract units; the
## bridge walks Contract.signals_for_vehicle() and pulls each name from here. The dict IS this
## telemetry's own property list, subclass fields included, so every member var of a telemetry
## class is a wire signal. Only the four tables above and the synthesised 'slip' are not identity.
## CAN byte scaling is sloppyCAN's job.
func to_bridge_dict() -> Dictionary:
	var d := {}
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = prop.name
		if field in WIRE_PRIVATE:
			continue
		var value: Variant = get(field)
		if field in WIRE_ROUNDED:
			value = roundi(value)
		elif field in WIRE_PERCENT:
			value = roundi(value * 100.0)
		d[WIRE_NAMES.get(field, field)] = value
	# A plain Array, not Packed, since JSON.stringify puts it on the wire.
	d["slip"] = [slip_front, slip_rear]
	return d
