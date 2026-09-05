class_name WindField
extends Resource
## The world's wind: a steady base flow plus a deterministic gust term, sampled as one
## horizontal vector (y=0). `Level.wind` defaults to null (dead calm). `gust()` is pure
## (seed, time), so flights are reproducible; gust magnitude is bounded by `gust_speed`.
## DroneVehicle/PlaneVehicle fly drag relative to it; ground vehicles ignore it.

## Gust octaves; each half the period and amplitude of the one before (one slow surge with a little chop).
const OCTAVES := 3
## Period (s) of the slowest gust octave.
const BASE_PERIOD := 7.0

## Compass heading (deg) the wind blows toward: 0 = world -Z, 90 = +X (reverse of aviation's "comes from").
@export_range(0.0, 360.0, 1.0) var direction_deg := 0.0
## m/s of steady flow; 0 is dead calm.
@export_range(0.0, 30.0, 0.1, "or_greater") var speed := 0.0
## m/s ceiling on the gust added to the steady flow — a hard bound, not an average.
@export_range(0.0, 30.0, 0.1, "or_greater") var gust_speed := 0.0
## Seed for the gust phases; same seed, same wind forever.
@export var gust_seed := 1


## Wind vector (m/s, world space, y always 0) at level time `t` seconds.
func vector_at(t: float) -> Vector3:
	var v := base_vector(direction_deg, speed)
	if gust_speed <= 0.0:
		return v
	var g := gust(gust_seed, t, gust_speed)
	return v + Vector3(g.x, 0.0, g.y)


## Steady component: `speed` m/s along the compass heading `deg` (0 = -Z, 90 = +X).
static func base_vector(deg: float, wind_speed: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(sin(r), 0.0, -cos(r)) * wind_speed


## Gust as an XZ pair (x -> world X, y -> world Z), magnitude bounded by `amplitude`.
## Pure: a function of the seed and time only.
static func gust(seed_value: int, t: float, amplitude: float) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var acc := Vector2.ZERO
	var norm := 0.0
	for i in OCTAVES:
		var scale := float(1 << i)          # 1, 2, 4: octave i is `scale` times faster
		var weight := 1.0 / scale           # ...and 1/scale as strong
		var omega := TAU * scale / BASE_PERIOD
		acc += Vector2(sin(omega * t + _phase(seed_value, i * 2)),
				sin(omega * t + _phase(seed_value, i * 2 + 1))) * weight
		norm += weight
	# Also normalized by sqrt(2): the two independent sine-stack axes could reach sqrt(2)
	# times `norm` on a diagonal, so this makes `amplitude` a true ceiling on gust speed.
	return acc / (norm * sqrt(2.0)) * amplitude


## Wind at the node's level, or zero if not under one. Duck-typed: a vehicle must not learn what a Level is.
static func at(node: Node) -> Vector3:
	var n := node.get_parent() if node != null else null
	while n != null:
		if n.has_method("wind_vector"):
			return n.call("wind_vector")
		n = n.get_parent()
	return Vector3.ZERO


## Deterministic phase (rad) for octave component `k` of `seed_value`; masked to 31 bits.
static func _phase(seed_value: int, k: int) -> float:
	var h := ((seed_value * 73856093) ^ ((k + 1) * 19349663)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0 * TAU
