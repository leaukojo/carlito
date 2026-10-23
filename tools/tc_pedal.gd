extends RefCounted
## The measure tools' slip-limiting driver (`tc`): an integral controller feathering the delivered
## fuel to hold the WORST driven wheel at the grip curve's peak. Callers send it through the
## pedal map's inverse (`PedalMap.pedal_for`), as `measure_grade.gd`'s `_tc_fuel`, so one gain
## serves every map: on a governed tractor the pedal is a speed setting, which cuts no fuel until
## the setting reaches the lugging crank. It takes throttle sensitivity out of an
## answer, so what is left is the vehicle's own ceiling. `measure_grade.gd`'s `tc` is a different
## thing (a search for the force-max slip) and does not use this.
##
## The integral runs on the LOGS of fuel and slip: under the peak, slip goes roughly as drive
## torque, so one gain closes the loop at the same rate whatever the gear, speed or load. A linear
## integral on the slip error would climb back from a cut slowly (its error cannot pass the 0.12
## target) and slam to zero on a spin flash: about a second of a launch under the peak.

const TARGET_SLIP := 0.12   ## the shipped grip curves all peak here
const GAIN := 8.0           ## 1/s: log fuel per second per unit of log slip error
## Over the target the slip the integral reads is clamped to this factor of TARGET_SLIP, so a spin
## flash cuts the fuel at most `exp(ln(4) * GAIN * delta)` (x0.83 at 60 Hz) a tick.
const ERROR_SPAN := 4.0
## Under it, to this one: the climb is at most x1.055 a tick, 0.02 to full fuel in ~1.2 s. A wheel
## held under the peak reads almost no slip until the drive passes the tyre's grip, then flashes in
## two or three ticks, and behind a locked heavy crank (the 2WD tractor in D1 on mud, 2223 kg·m² at
## the axle) no fuel cut pulls it back for ~0.5 s. Climbing at x1.2, the driver cycled there
## between 0.02 and full fuel about once a second and never crossed flat mud.
const ERROR_SPAN_UNDER := 1.5
const MIN_FUEL := 0.02      ## keeps the multiplicative step off 0, where it would stick


## The tc fuel (MIN_FUEL..1) for the next tick, from this tick's and the wheels' slip. Its
## integral climbs only while the drive reaches the wheels (`bite_pending` false): a wheel reads no
## slip while the coupling withholds the pedal, and an integral climbing through that winds up to
## full fuel, then flashes the tyres the tick the clutch bites.
static func step(fuel: float, wheels: Array[RayWheel], delta: float,
		drivetrain: Drivetrain = null) -> float:
	var slip := clampf(worst_driven_slip(wheels), TARGET_SLIP / ERROR_SPAN_UNDER,
			TARGET_SLIP * ERROR_SPAN)
	var next := fuel * exp(log(TARGET_SLIP / slip) * GAIN * delta)
	if drivetrain != null and bite_pending(drivetrain,
			PedalMap.pedal_for(drivetrain.spec, fuel, drivetrain.rpm)):
		next = minf(next, fuel)
	return clampf(next, MIN_FUEL, 1.0)


## The coupling still withholds what `pedal` asks: a launch ramp short of its rating, or a friction
## clutch slipping into a pull-away while the crank revs from idle toward the pedal's launch line,
## where it passes almost nothing until the crank lands (`Drivetrain.launch_target_rpm`). A crank
## held ON idle is not revving (a pedal under the idle controller's own fuel), so the climb goes on
## there, or the pedal would never get past it. A converter passes drive from the first tick, so it
## never withholds. COMPROMISE: read off the crank's speed, so a crank held under the line by wheels
## blocked against a bump also freezes the climb (the 2WD tractor on mud bumps_20 holds ~0.12 pedal
## there, `use` .19). Keying it on the clutch's carried torque instead, alone or with the speed, kept
## the flat-mud cycle (2026-10-10).
static func bite_pending(drivetrain: Drivetrain, pedal: float) -> bool:
	if drivetrain.ramp < 1.0:
		return true
	var spec := drivetrain.spec
	return spec.coupling == VehicleSpec.Coupling.CLUTCH \
			and drivetrain.coupling_state == Drivetrain.CouplingState.SLIPPING \
			and drivetrain.rpm > spec.idle_rpm + 1.0 \
			and drivetrain.rpm < Drivetrain.launch_target_rpm(spec, pedal) - 1.0


## Highest slip over the driven wheels in contact; 0 with none.
static func worst_driven_slip(wheels: Array[RayWheel]) -> float:
	var worst := 0.0
	for w in wheels:
		if w.driven and w.in_contact:
			worst = maxf(worst, w.slip)
	return worst
