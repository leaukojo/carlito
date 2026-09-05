class_name TrainSim
extends RefCounted
## 1D consist sim: each car is a point mass on a curve arc; loco (index 0) pulls the rake via
## spring-damper couplers. Cars ordered head->tail; +s is forward. Forces are static pure
## functions so the sim runs headless. 60 Hz clamp discipline: damper never exceeds one-tick
## velocity reversal impulse; coupler force is hard-capped. Don't weaken either.

const GRAVITY := 9.8  ## m/s^2; matches the project default_gravity

# --- consist state (head = index 0) ---
var s := PackedFloat64Array()      ## arc position per car (m), modulo L on a closed loop
var v := PackedFloat64Array()      ## along-track speed per car (m/s), + = increasing s
var masses := PackedFloat64Array() ## per-car mass (kg)
var rest_gaps := PackedFloat64Array()  ## rest centre-to-centre spacing per adjacent pair, size n-1
var length := 0.0                  ## curve length (m); wrap modulus on closed loops
var closed := false

# --- tuning (set by TrainVehicle; honest EMU-inspired defaults, all clearly tunable) ---
var max_tractive := 320000.0   ## N, starting tractive effort (constant to base_speed)
var base_speed := 14.0         ## m/s, corner speed where traction goes power-limited
var max_power := 4480000.0     ## W, = max_tractive * base_speed above base_speed
var max_brake := 90000.0       ## N per car at full brake application
var davis_a := 400.0           ## N, rolling term (per car)
var davis_b := 15.0            ## N*s/m, flange/bearing term (per car)
var davis_c := 0.8             ## N*s^2/m^2, aero term (per car)
var coupler_k := 3.0e6         ## N/m, drawbar stiffness
var coupler_damp := 2.0e5      ## N*s/m, coupler damping
var coupler_slack := 0.05      ## m, free travel each side of rest before a coupler bites
var max_coupler := 500000.0    ## N, coupler force hard cap (matches contract coupler_force range)

# --- outputs, refreshed each step() ---
var head_coupler_force := 0.0  ## N, coupler between loco and first wagon (+ = tension/draw, - = buff)
var loco_accel := 0.0          ## m/s^2, net along-track acceleration of the loco


## Lay the consist out with the head at `head_s`, each following car one rest-gap behind.
func setup(car_masses: PackedFloat64Array, gaps: PackedFloat64Array, curve_length: float,
		is_closed: bool, head_s := 0.0) -> void:
	masses = car_masses
	rest_gaps = gaps
	length = curve_length
	closed = is_closed
	var n := masses.size()
	s = PackedFloat64Array()
	v = PackedFloat64Array()
	s.resize(n)
	v.resize(n)
	var pos := head_s
	for i in n:
		s[i] = _wrap(pos)
		v[i] = 0.0
		if i < n - 1:
			pos -= rest_gaps[i]


## Advance the consist one tick. `throttle` is the signed reverser demand (-1..1); `brake`
## and `parking` are 0..1; `grades[i]` is the signed track slope (rise/run) at car i.
func step(delta: float, throttle: float, brake: float, parking: float,
		grades: PackedFloat64Array) -> void:
	var n := s.size()
	var forces := PackedFloat64Array()
	forces.resize(n)
	for i in n:
		var f := 0.0
		if i == 0:
			f += tractive_effort(v[i], throttle, base_speed, max_tractive, max_power)
		f += davis_resistance(v[i], davis_a, davis_b, davis_c)
		f += brake_force(v[i], brake, parking, max_brake, masses[i], delta)
		f += grade_force(masses[i], grades[i] if i < grades.size() else 0.0, GRAVITY)
		forces[i] = f

	head_coupler_force = 0.0
	for i in n - 1:
		var gap := _wrapped_gap(s[i], s[i + 1])
		var mu := masses[i] * masses[i + 1] / (masses[i] + masses[i + 1])
		var fc := coupler_force(gap, rest_gaps[i], coupler_slack, v[i] - v[i + 1],
				coupler_k, coupler_damp, mu, delta, max_coupler)
		# fc > 0 is tension: it pulls the leading car back (-s) and the trailing car up (+s),
		# closing the gap; fc < 0 is buff and pushes them apart.
		forces[i] -= fc
		forces[i + 1] += fc
		if i == 0:
			head_coupler_force = fc

	loco_accel = forces[0] / masses[0]
	for i in n:
		v[i] += forces[i] / masses[i] * delta
		s[i] = _wrap(s[i] + v[i] * delta)


## Signed centre-to-centre gap between adjacent cars, wrapped onto the loop so a coupler
## straddling the s=0 seam still reads its true rest_gap separation.
func _wrapped_gap(s_lead: float, s_follow: float) -> float:
	var d := s_lead - s_follow
	if not closed or length <= 0.0:
		return d
	return fposmod(d + length * 0.5, length) - length * 0.5


func _wrap(arc: float) -> float:
	if closed and length > 0.0:
		return fposmod(arc, length)
	return arc


# --- pure force math (unit-tested; one-tick clamped like RayWheel / the boat) ---------------

## Tractive effort (N), signed by the reverser throttle. Constant `max_force` up to
## `base_speed`, then power-limited (P/v) above it — the standard traction hyperbola. Zero
## demand -> zero force; direction follows the throttle sign (the reverser), never the speed.
static func tractive_effort(speed: float, throttle: float, corner_speed: float,
		max_force: float, power_cap: float) -> float:
	var mag := clampf(absf(throttle), 0.0, 1.0)
	if mag <= 0.0:
		return 0.0
	var f := max_force
	var spd := absf(speed)
	if spd > corner_speed and spd > 0.0:
		f = minf(max_force, power_cap / spd)
	return signf(throttle) * mag * f


## Davis running resistance (N), opposing motion: a + b|v| + c v^2. Zero at rest (nothing to
## oppose), so it never induces standstill jitter.
static func davis_resistance(speed: float, a: float, b: float, c: float) -> float:
	var spd := absf(speed)
	return -signf(speed) * (a + b * spd + c * spd * spd)


## Train + parking brake force (N), opposing velocity, clamped so one tick can at most zero
## the car's speed, never reverse it.
static func brake_force(speed: float, brake: float, parking: float, brake_max: float,
		mass: float, delta: float) -> float:
	var demand := clampf(brake + parking, 0.0, 1.0) * brake_max
	if demand <= 0.0 or speed == 0.0:
		return 0.0
	var tick_cap := mass * absf(speed) / delta
	return clampf(-signf(speed) * demand, -tick_cap, tick_cap)


## Gravity holdback along the track (N): negative (retarding +s travel) on a climb, positive
## on a descent. `grade` is rise/run; sin(atan(grade)) keeps it exact for steep slopes.
static func grade_force(mass: float, grade: float, gravity: float) -> float:
	return -mass * gravity * sin(atan(grade))


## Coupler force (N) between two cars: spring on the stretch beyond the slack deadband plus a
## damper on the closing rate. + = tension (draw), - = buff. Damper clamped to the one-tick
## reversal of the relative velocity (reduced mass); total hard-capped — don't weaken either.
## Inside the slack band the coupler is free (returns 0).
static func coupler_force(gap: float, rest: float, slack: float, rel_vel: float,
		k: float, damp: float, reduced_mass: float, delta: float, max_force: float) -> float:
	var stretch := gap - rest
	var eff := 0.0
	if stretch > slack:
		eff = stretch - slack
	elif stretch < -slack:
		eff = stretch + slack
	else:
		return 0.0
	var tick_cap := reduced_mass * absf(rel_vel) / delta
	var damper := clampf(damp * rel_vel, -tick_cap, tick_cap)
	return clampf(k * eff + damper, -max_force, max_force)
