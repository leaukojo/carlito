class_name DroneAirData
extends RefCounted
## The barometer: static pressure, altitude solved from it, and outside air temperature.
## Pure static logic; ungated by the bus roster (no barometer node to fail).
## Deliberately disagrees with altitude (GPS) and agl (rangefinder), via two labelled models: the
## altimeter stays on a standard day (QNH_STANDARD) while sea-level pressure drifts around it, and
## the static port under-reads with the square of airspeed. Never correct one height toward another.

# --- the standard atmosphere ---------------------------------------------------

## ISA standard-day sea-level pressure (Pa): the SUBSCALE SETTING the altimeter is left on. The
## instrument assumes this; the air does not.
const QNH_STANDARD := 101325.0
## ISA sea-level temperature (K).
const T0_K := 288.15
## ISA tropospheric lapse rate (K/m).
const LAPSE_K_M := 0.0065
## Barometric exponent g/(R*L) = 9.80665 / (287.052874 * 0.0065).
const BARO_EXP := 5.255876
## 0 degC in K. The contract carries `oat` in Celsius; sloppyCAN converts to the DSDL's Kelvin.
const KELVIN_0C := 273.15

# --- the two error terms -------------------------------------------------------

## Amplitude of the sea-level pressure drift (Pa). 1 hPa = ~8.4 m of indicated altitude; sized
## for a 120 m-tall world (a realistic 40 hPa swing would be 330 m of error).
const DRIFT_PA := 100.0
## Period of that drift (s): a slow wander that turns around inside one flight.
const DRIFT_PERIOD := 240.0
## Static-source position error coefficient (dimensionless): the port under-reads by this fraction
## of dynamic pressure (~69 Pa / ~6 m at 15 m/s).
const PORT_ERROR_K := 0.5
## Air density for that dynamic pressure (kg/m^3): sea-level ISA, held constant (0-120 m changes
## it ~1%).
const AIR_DENSITY := 1.225


## The level's ACTUAL sea-level pressure at `t` seconds elapsed (Pa).
static func sea_level_pressure(t: float) -> float:
	return QNH_STANDARD + DRIFT_PA * sin(TAU * t / DRIFT_PERIOD)


## Static pressure at `alt_m` above sea level under `sea_level_pa` (ISA barometric formula).
## Clamped at zero so an absurd altitude cannot return a negative pressure.
static func pressure_at(alt_m: float, sea_level_pa: float) -> float:
	var ratio := 1.0 - LAPSE_K_M * alt_m / T0_K
	if ratio <= 0.0:
		return 0.0
	return sea_level_pa * pow(ratio, BARO_EXP)


## The inverse: altitude an altimeter set to `qnh_pa` reports for `pressure_pa` (`baro_alt`).
static func altitude_from(pressure_pa: float, qnh_pa: float) -> float:
	if pressure_pa <= 0.0 or qnh_pa <= 0.0:
		return 0.0
	return T0_K / LAPSE_K_M * (1.0 - pow(pressure_pa / qnh_pa, 1.0 / BARO_EXP))


## Static port error at this airspeed (Pa, always <= 0). `airspeed` is relative to the air.
static func port_error_pa(airspeed: float) -> float:
	return -PORT_ERROR_K * 0.5 * AIR_DENSITY * airspeed * airspeed


## Outside air temperature at `alt_m`, CELSIUS: the ISA lapse and nothing else (contract `oat`).
static func oat_c(alt_m: float) -> float:
	return T0_K - LAPSE_K_M * alt_m - KELVIN_0C
