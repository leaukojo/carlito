extends RefCounted
## Leaf: the local keys' walks over the cycled controls, one copy each (the router must not depend
## on a vehicle class). Lengths come from `subsystem_counts.gd`.

const Counts := preload("res://src/input/subsystem_counts.gd")


## Y key, node-failure walk: none -> node 0 -> node 1 -> ... -> last -> none. Shifts the mask one
## bit left, wrapping past the last back to none; handles any starting int (not just the normal
## DRONE_NODES states) so a multi-bit bus-commanded mask still terminates instead of sticking or
## shifting silently off the end.
static func node_fail(bits: int) -> int:
	var next_fail := maxi(bits << 1, 1)
	return 0 if next_fail > (1 << (Counts.DRONE_NODES - 1)) else next_fail


## Z key, flight-mode walk: STABILIZE -> ALT_HOLD -> LOITER -> RTL -> LAND -> STABILIZE.
static func flight_mode(mode: int) -> int:
	return _ladder(mode, Counts.FLIGHT_MODES)


## 2 key, autopilot walk: STANDBY -> HEADING HOLD -> STANDBY.
static func nav_mode(mode: int) -> int:
	return _ladder(mode, Counts.NAV_MODES)


## 3 key, sheet walk: hauled in -> ... -> fully eased -> hauled in.
static func sheet(detent: int) -> int:
	return _ladder(detent, Counts.SHEET_DETENTS)


## One step of a wrap-around ladder: 0 -> 1 -> ... -> n-1 -> 0. `posmod` (not `%`) so a negative
## starting value still lands inside the ladder.
static func _ladder(x: int, n: int) -> int:
	return posmod(x + 1, n)
