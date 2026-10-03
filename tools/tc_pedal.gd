extends RefCounted
## The measure tools' slip-limiting driver (`tc`): an integral controller feathering the pedal to
## hold the WORST driven wheel at the grip curve's peak. It takes throttle sensitivity out of an
## answer, so what is left is the vehicle's own ceiling. `measure_grade.gd`'s `tc` is a different
## thing (a search for the force-max slip) and does not use this.
##
## The integral runs on the LOGS of pedal and slip: under the peak, slip goes roughly as drive
## torque, so one gain closes the loop at the same rate whatever the gear, speed or load. A linear
## integral on the slip error would climb back from a cut slowly (its error cannot pass the 0.12
## target) and slam to zero on a spin flash: about a second of a launch under the peak.

const TARGET_SLIP := 0.12   ## the shipped grip curves all peak here
const GAIN := 8.0           ## 1/s: log pedal per second per unit of log slip error
## The slip the integral reads is clamped to within this factor of TARGET_SLIP, so a wheel at rest
## or a spin flash moves the pedal at most `exp(ln(4) * GAIN * delta)` (x1.2 at 60 Hz) per tick.
const ERROR_SPAN := 4.0
const MIN_PEDAL := 0.02     ## keeps the multiplicative step off 0, where it would stick


## The tc pedal (MIN_PEDAL..1) for the next tick, from this tick's and the wheels' slip.
static func step(pedal: float, wheels: Array[RayWheel], delta: float) -> float:
	var slip := clampf(worst_driven_slip(wheels), TARGET_SLIP / ERROR_SPAN,
			TARGET_SLIP * ERROR_SPAN)
	return clampf(pedal * exp(log(TARGET_SLIP / slip) * GAIN * delta), MIN_PEDAL, 1.0)


## Highest slip over the driven wheels in contact; 0 with none.
static func worst_driven_slip(wheels: Array[RayWheel]) -> float:
	var worst := 0.0
	for w in wheels:
		if w.driven and w.in_contact:
			worst = maxf(worst, w.slip)
	return worst
