class_name Differential
extends RefCounted
## A differential as a friction coupling between its two outputs: pure statics, applied by
## `WheelDrive._couple_differentials` after the wheels integrate their spin.
##
## Every diff splits its input torque equally (the open-diff law) and then moves a coupling torque
## from the faster output to the slower one, bounded by a CAPACITY: 0 is an open diff, a torque-
## biasing diff (Torsen, plate LSD) scales with the torque going through it, and a locked or rigid
## one is unbounded. Never a traction cap: nothing here reads grip or load.
##
## The coupling is solved inside the wheels' semi-implicit spin step, not after it. That step is
## linear in the applied torque (`RayWheel.spin_compliance`), so a torque `T` applied as
## `omega -= T * compliance` after integrating is exactly what adding it to the drive torque would
## have given. An explicit post-tick transfer skips the `1 + reaction_stiffness` divisor, acts that
## much too strong on a gripping wheel and turns any limited-slip diff into a spool.


## Largest coupling torque (N·m) a torque-biasing diff can carry with `input_torque` through it: the
## slow output may take up to `bias_ratio` times what the fast one takes. With an equal nominal split
## `T/2 ± cap`, that ratio is `(T/2 + cap) / (T/2 - cap) = b`, so `cap = |T|/2 * (b-1)/(b+1)`. 0 for
## an open diff (b = 1) and with no torque through it, since a torque-sensing diff biases nothing
## when unloaded. Blind to the torque's sign, since overrun biases the same way.
static func bias_capacity(input_torque: float, bias_ratio: float) -> float:
	if bias_ratio <= 1.0:
		return 0.0
	return absf(input_torque) * 0.5 * (bias_ratio - 1.0) / (bias_ratio + 1.0)


## Coupling torque (N·m) moved from output a to output b, positive when a runs faster: the torque
## that brings the two outputs to one speed this tick, `(omega_a - omega_b) / (compliance_a +
## compliance_b)`, clamped to `capacity` (INF for a locked diff or a rigid coupling). The caller
## applies it as `omega_a -= T * compliance_a`, `omega_b += T * compliance_b`, so an unbounded
## coupling lands both outputs on the compliance-weighted mean, and a bounded one only shrinks the
## spread. It never reverses the spread, so it needs no 60 Hz clamp of its own. 0 when the outputs
## have no compliance (nothing to move) or the capacity is 0 (an open diff, a bit-exact no-op).
static func coupling_torque(omega_a: float, omega_b: float, compliance_a: float,
		compliance_b: float, capacity: float) -> float:
	var compliance := compliance_a + compliance_b
	if capacity <= 0.0 or compliance <= 0.0:
		return 0.0
	return clampf((omega_a - omega_b) / compliance, -capacity, capacity)
