class_name CurrentField
extends Resource
## The world's tidal stream: one horizontal vector (y=0) whose rate rides a slow sinusoid, so the
## water floods, goes slack and ebbs back the other way over `tide_period_s`. `Level.current`
## defaults to null (still water). `rate_at()` is pure (period, offset, time), so a passage is
## reproducible; BoatVehicle runs its hull drag relative to it and nothing else reads it.
##
## A SIBLING of WindField, not a subclass and not a shared base: the two share the compass
## convention and `base_vector`, and nothing else — a tide is not a gust, and the time shapes
## have no arithmetic in common.

## Compass heading (deg) the stream flows TOWARD at the flood, WindField.direction_deg's
## convention so the two resources cannot disagree. The ebb reverses the vector.
@export_range(0.0, 360.0, 1.0) var set_deg := 0.0
## m/s at peak flood; 0 is still water.
@export_range(0.0, 5.0, 0.1, "or_greater") var drift := 0.0
## Seconds for a full flood - slack - ebb - slack cycle. 0 pins the rate at `drift` (a steady stream).
@export_range(0.0, 3600.0, 1.0, "or_greater") var tide_period_s := 240.0
## Seconds into the cycle at level start: 0 is slack turning to flood, a quarter period is peak flood.
@export var tide_offset_s := 0.0


## Current vector (m/s, world space, y always 0) at level time `t` seconds. A negative rate is
## the ebb, and `base_vector` reverses the vector for it — so the 180-degree flip costs no branch.
func vector_at(t: float) -> Vector3:
	return WindField.base_vector(set_deg, rate_at(drift, tide_period_s, tide_offset_s, t))


## Signed rate (m/s) at level time `t`: positive floods along `set_deg`, negative ebbs back along
## it. Pure, so the tide is a function of ticks elapsed and not of frame-rate jitter.
static func rate_at(peak: float, period_s: float, offset_s: float, t: float) -> float:
	if period_s <= 0.0:
		return peak
	return peak * sin(TAU * (t + offset_s) / period_s)


## Current at the node's level, or zero if not under one. Duck-typed: a vehicle must not learn
## what a Level is. Its own copy of WindField.at's walk, for the same reason that one keeps its
## own — static, standalone-tested, and ZERO off a level is the contract.
static func at(node: Node) -> Vector3:
	var n := node.get_parent() if node != null else null
	while n != null:
		if n.has_method("current_vector"):
			return n.call("current_vector")
		n = n.get_parent()
	return Vector3.ZERO
