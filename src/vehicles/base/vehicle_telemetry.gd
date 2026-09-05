class_name VehicleTelemetry
extends RefCounted
## Per-tick telemetry published by BaseVehicle, covering every contract "out" signal for ground
## vehicles (car/truck/tractor). Motion is read out of the sim, never derived; fuel, coolant and
## battery are simple honest models, labelled as modeled rather than measured. Non-trivial
## derivations are the static pure functions below.

# --- GPS mapping (world XZ -> lat/lon around the Paris origin) ---
const GPS_ORIGIN_LAT := 48.8566
const GPS_ORIGIN_LON := 2.3522
const METERS_PER_DEG_LAT := 111320.0  ## mean meters per degree of latitude

# --- auxiliary-system model constants ---
const FUEL_IDLE_BURN := 0.02   ## %/s burned at idle while running
const FUEL_LOAD_BURN := 0.18   ## extra %/s at full throttle
const COOLANT_AMBIENT := 20.0    ## degC cold-start / engine-off resting temp
const COOLANT_OPERATING := 90.0  ## degC steady running temp at no load
const COOLANT_HOT := 108.0       ## degC steady running temp at full load
const BATTERY_RESTING := 12.6    ## V engine off
const BATTERY_CHARGING := 14.2   ## V engine running (alternator), before load droop

# --- status bitfield (contract 'status', u16) ---
## FROZEN wire layout. A new flag appends at bit 7 or above (nine free in the u16); an existing
## bit is never renumbered, and adding one bumps `version` and ships as a paired promote.
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
var gear_byte := 0      ## RAMN byte: 0=N, 1..6=D1-D6, 255=R (contract 'gear')
var throttle := 0.0     ## -1..1 as applied, signed by direction (contract 'throttle')
var steer := 0.0        ## -1..1 as applied (contract 'steer')
## Body angular rates and accelerations (DroneCAN's `angular_velocity` / `linear_acceleration`),
## on the base since every chassis has body motion.
var yaw := 0.0          ## yaw rate rad/s about the body up axis (contract 'yaw')
var roll_rate := 0.0    ## roll rate rad/s about the body forward axis, + = right side down (contract 'roll_rate')
var pitch_rate := 0.0   ## pitch rate rad/s about the body right axis, + = nose up (contract 'pitch_rate')
var acc_long := 0.0     ## longitudinal accel m/s^2, smoothed (contract 'accLong')
var acc_lat := 0.0      ## lateral accel m/s^2, smoothed (contract 'accLat')
var acc_vert := 0.0     ## vertical accel m/s^2 along body up, smoothed (contract 'acc_vert')
## Attitude/height, on the base for the same reason (one copy, not three).
var pitch := 0.0        ## deg, + = nose/bow up (contract 'pitch')
var roll := 0.0         ## deg, + = starboard/right side down (contract 'roll')
var altitude := 0.0     ## m above sea level (contract 'altitude'; world Y, water is y=0)
var vspeed := 0.0       ## m/s variometer, + = climbing (contract 'vspeed')
## Instanced signal 'slip' (count 2), kept per-axle so understeer and oversteer differ.
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
var odo := 0.0          ## odometer km, persists across respawn (contract 'odo')
## The odometer's twin: climbs only, survives respawn. Only truck and tractor declare it;
## elsewhere it counts quietly, and the dashboard gates HRS on the contract.
var engine_hours := 0.0 ## h, contract 'engine_hours' (J1939 SPN 247; survives respawn)

# --- auxiliary systems (modeled, not measured) ---
var fuel := 100.0                ## % remaining (contract 'fuel')
var coolant := COOLANT_AMBIENT   ## degC (contract 'coolant')
var battery := BATTERY_RESTING   ## V (contract 'battery' out; distinct from the 'in' warning LED)
var status := 0                  ## u16 bitfield (contract 'status')


# --- pure derivations (unit-tested) -----------------------------------------

## Latitude for a world Z, mapping -Z to north. Returns a float (64-bit) rather than a Vector2,
## so the contract's f64 lat/lon precision survives.
static func gps_lat(world_z: float) -> float:
	return GPS_ORIGIN_LAT + (-world_z) / METERS_PER_DEG_LAT


## Longitude for a world X (+X = east), meters-per-degree shrunk by the origin latitude.
static func gps_lon(world_x: float) -> float:
	return GPS_ORIGIN_LON + world_x / (METERS_PER_DEG_LAT * cos(deg_to_rad(GPS_ORIGIN_LAT)))


## Compass heading [0,360) from a forward vector. 0 = north (-Z), 90 = east (+X).
static func heading_from_forward(forward: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


## Odometer step: accumulate absolute distance travelled, in km.
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


## Fuel burn step (%). Only burns while running; idle burn plus a load term.
static func fuel_step(prev_pct: float, load_frac: float, running: bool, delta: float) -> float:
	if not running:
		return prev_pct
	var burn := (FUEL_IDLE_BURN + FUEL_LOAD_BURN * clampf(load_frac, 0.0, 1.0)) * delta
	return clampf(prev_pct - burn, 0.0, 100.0)


## Steady-state coolant target: ambient when off, warming toward the hot end with load.
static func coolant_target(running: bool, load_frac: float) -> float:
	if not running:
		return COOLANT_AMBIENT
	return lerpf(COOLANT_OPERATING, COOLANT_HOT, clampf(load_frac, 0.0, 1.0))


## First-order lag toward the coolant target; never overshoots.
static func coolant_step(prev_c: float, target_c: float, rate: float, delta: float) -> float:
	return move_toward(prev_c, target_c, rate * delta)


## Battery terminal voltage: resting when off, alternator-charged and drooping under load when
## running.
static func battery_volts(running: bool, load_frac: float) -> float:
	if not running:
		return BATTERY_RESTING
	return BATTERY_CHARGING - 0.6 * clampf(load_frac, 0.0, 1.0)


## Engine load, J1939 SPN 92: delivered torque over peak torque, plus a parasitic PTO term.
## Shared by the tractor (ISOBUS) and the truck (J1939). The denominator is the peak, not the
## torque at the current rpm, which would cancel to throttle.
static func engine_load_pct(engine_rpm: float, throttle_in: float, spec: VehicleSpec,
		pto_on: bool, pto_load: float) -> float:
	var peak := Drivetrain.peak_torque(spec)
	if peak <= 0.0:
		return 0.0
	var delivered := Drivetrain.engine_torque(spec, engine_rpm) \
			* clampf(absf(throttle_in), 0.0, 1.0)
	var load_frac := delivered / peak
	if pto_on:
		load_frac += pto_load
	return clampf(load_frac, 0.0, 1.0) * 100.0


## Hour meter step: real time under the key. Only climbs, survives respawn. Shared for the same
## reason as engine_load_pct (J1939 SPN 247, which ISOBUS inherits).
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
## bit `pack_status` cannot compute from shared state (the drone and boat ST_GROUND is a landed
## predicate, not a wheel count) without a third BaseVehicle seam.
static func with_status_bit(packed: int, bit: int, on: bool) -> int:
	return (packed | bit) if on else (packed & ~bit)


# --- bridge marshaling -------------------------------------------------------

## Contract name for a telemetry field spelled differently. The wire names are the contract's
## and are frozen; the field names are GDScript's.
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
## class is a wire signal — anything that is not one belongs on the vehicle, not here. Only the
## four tables above and the synthesised 'slip' are not identity. CAN byte scaling is
## sloppyCAN's job.
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
	# 'slip' is instanced (count 2) and kept per-axle so understeer and oversteer differ. A plain
	# Array, not Packed, since JSON.stringify puts it on the wire.
	d["slip"] = [slip_front, slip_rear]
	return d
