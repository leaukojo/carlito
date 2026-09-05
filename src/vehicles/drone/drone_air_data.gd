class_name DroneAirData
extends RefCounted
## The barometer: static pressure, altitude solved from it, and outside air temperature.
## Pure static logic; ungated by the bus roster (no barometer node to fail).
## Deliberately disagrees with altitude (GPS) and agl (rangefinder). Two labelled models make
## the gap: the altimeter is set to a standard day (QNH_STANDARD) while sea-level pressure
## drifts around it, and the static port under-reads with the square of airspeed (level 6 only).
## Never correct one height toward another.

# --- the standard atmosphere ---------------------------------------------------

## ISA standard-day sea-level pressure (Pa) — the SUBSCALE SETTING the altimeter is left on.
## The instrument assumes this; the air does not (error 1 above).
const QNH_STANDARD := 101325.0
## ISA sea-level temperature (K).
const T0_K := 288.15
## ISA tropospheric lapse rate (K/m).
const LAPSE_K_M := 0.0065
## Barometric exponent g/(R*L), spelled out (9.80665 / (287.052874 * 0.0065)) so it's checkable.
const BARO_EXP := 5.255876
## Absolute zero. Contract carries `oat` in Celsius; DSDL carries Kelvin, sloppyCAN converts.
const KELVIN_0C := 273.15

# --- the two error terms -------------------------------------------------------

## Amplitude of the sea-level pressure drift (Pa). ONE HECTOPASCAL = ~8.4 m of indicated
## altitude, sized against the aircraft not the weather: the drone's world is 120 m tall, so
## a realistic 40 hPa swing would be 330 m of error.
const DRIFT_PA := 100.0
## Period of that drift (s). Four minutes: a slow wander that turns around inside one flight.
const DRIFT_PERIOD := 240.0
## Static-source position error coefficient, dimensionless — port under-reads by this
## fraction of dynamic pressure (~69 Pa / ~6 m at 15 m/s).
const PORT_ERROR_K := 0.5
## Air density for that dynamic pressure (kg/m^3). Sea-level ISA, held constant — the drone's
## 0-120 m world changes real density by ~1%.
const AIR_DENSITY := 1.225


## The level's ACTUAL sea-level pressure at `t` seconds elapsed (Pa) — what the fixed subscale
## is wrong about.
static func sea_level_pressure(t: float) -> float:
	return QNH_STANDARD + DRIFT_PA * sin(TAU * t / DRIFT_PERIOD)


## Static pressure at `alt_m` above sea level under `sea_level_pa`. ISA barometric formula,
## unmodified. Clamped at zero so an absurd altitude can't return a negative pressure.
static func pressure_at(alt_m: float, sea_level_pa: float) -> float:
	var ratio := 1.0 - LAPSE_K_M * alt_m / T0_K
	if ratio <= 0.0:
		return 0.0
	return sea_level_pa * pow(ratio, BARO_EXP)


## The inverse: altitude an altimeter set to `qnh_pa` reports for `pressure_pa`. This is
## `baro_alt`; running it against QNH_STANDARD while the air is at `sea_level_pressure(t)` is
## error 1 above.
static func altitude_from(pressure_pa: float, qnh_pa: float) -> float:
	if pressure_pa <= 0.0 or qnh_pa <= 0.0:
		return 0.0
	return T0_K / LAPSE_K_M * (1.0 - pow(pressure_pa / qnh_pa, 1.0 / BARO_EXP))


## Static port error at this airspeed (Pa, always <= 0). Error 2 above. `airspeed` is speed
## relative to the air, already computed for the flight path's dampers — wind is free here.
static func port_error_pa(airspeed: float) -> float:
	return -PORT_ERROR_K * 0.5 * AIR_DENSITY * airspeed * airspeed


## Outside air temperature at `alt_m`, CELSIUS: the ISA lapse and nothing else. No weather
## claimed — see the contract desc for `oat`.
static func oat_c(alt_m: float) -> float:
	return T0_K - LAPSE_K_M * alt_m - KELVIN_0C
