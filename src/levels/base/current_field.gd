class_name CurrentField
extends Resource
## The world's tidal stream: one horizontal vector (y=0) whose rate rides a slow sinusoid, so the
## water floods, goes slack and ebbs over `tide_period_s`. `Level.current` null = still water.
## A sibling of WindField, not a subclass: they share only the compass convention and `base_vector`.

## Compass heading (deg) the stream flows TOWARD at the flood (WindField.direction_deg's convention).
@export_range(0.0, 360.0, 1.0) var set_deg := 0.0
## m/s at peak flood; 0 is still water.
@export_range(0.0, 5.0, 0.1, "or_greater") var drift := 0.0
## Seconds for a full flood - slack - ebb - slack cycle. 0 pins the rate at `drift` (a steady stream).
@export_range(0.0, 3600.0, 1.0, "or_greater") var tide_period_s := 240.0
## Seconds into the cycle at level start: 0 is slack turning to flood, a quarter period is peak flood.
@export var tide_offset_s := 0.0


## Current vector (m/s, world space, y always 0) at level time `t` seconds.
func vector_at(t: float) -> Vector3:
	return WindField.base_vector(set_deg, rate_at(drift, tide_period_s, tide_offset_s, t))


## Signed rate (m/s) at level time `t`: positive floods along `set_deg`, negative ebbs back along
## it. Pure, so the tide depends on ticks elapsed, not frame-rate jitter.
static func rate_at(peak: float, period_s: float, offset_s: float, t: float) -> float:
	if period_s <= 0.0:
		return peak
	return peak * sin(TAU * (t + offset_s) / period_s)


## Current at the node's level, or zero if not under one. Duck-typed: a vehicle must not learn
## what a Level is.
static func at(node: Node) -> Vector3:
	var n := node.get_parent() if node != null else null
	while n != null:
		if n.has_method("current_vector"):
			return n.call("current_vector")
		n = n.get_parent()
	return Vector3.ZERO
