class_name DroneSensors
extends RefCounted
## GNSS, rangefinder, and the landed predicate — pure static logic, no node state.
## DroneVehicle keeps the sky mask, cursor and debounce between ticks.
##
## `sats`/`agl` are the two contract signals a LEVEL can actually move. Never script a fix:
## `sats` is 16 real raycasts against level collision, so a wrong reading means the cone
## (mask angle, length, origin) is wrong, never an author-placed "GPS is bad here" volume.
## Mask is 80 deg from zenith (10 deg elevation), the real-receiver cutoff.

const Layers := preload("res://src/physics/collision_layers.gd")

# --- GNSS ---------------------------------------------------------------------

## Rays in the sky pattern, and the max `sats` — pinned against the contract range top by test.
const SKY_RAYS := 16
## Half-angle of the cone from the ZENITH (80 = a 10 degree elevation mask).
const SKY_MASK_DEG := 80.0
## Ray length before it counts as reaching the sky (m) — past the tallest level geometry,
## not a real satellite distance.
const SKY_RANGE := 200.0
## Rays recast per tick: 16 / 4 = 15 Hz full-sky refresh.
const SKY_RAYS_PER_TICK := 4

## Fix thresholds, in satellites — textbook counts, sole input to `fix_type`.
const FIX_SATS_TIME := 1  ## enough to discipline a clock, not to place anything
const FIX_SATS_2D := 3    ## horizontal position against an assumed altitude
const FIX_SATS_3D := 4    ## all three axes plus the receiver clock

## uavcan.equipment.gnss.Fix2.status, verbatim.
enum { FIX_NONE = 0, FIX_TIME_ONLY = 1, FIX_2D = 2, FIX_3D = 3 }

## HDOP scale constant, set so open sky reads ~0.9 (spread 0.413 at 80 deg -> 0.372/0.413).
## Re-derive if the mask angle moves — the envelope test pins the open-sky reading.
const HDOP_K := 0.372
## Floor on the spread, so a sky collapsed to one direction divides by something.
const HDOP_MIN_SPREAD := 1e-3
## Published ceiling and the "no fix" value — pinned against the contract `hdop` range top.
const HDOP_MAX := 10.0

# --- rangefinder ---------------------------------------------------------------

## Max range of the downward beam (m); pinned against the contract `agl` range top.
const RANGE_MAX := 100.0
## No return inside RANGE_MAX, or the RANGE node off the bus. Never zero — zero is a value
## a landing detector would act on. Pinned against the contract `agl` range bottom.
const RANGE_INVALID := -1.0

# --- the landed predicate (contract `status` bit 1, ST_GROUND) ------------------

## Contract `status` bit 1 (ST_GROUND); the drone's own answer since it has no wheels for
## the base's "every wheel in contact". Three conditions (ArduPilot's shape): ground close,
## not moving vertically, not asking more lift than a hover — the third separates sitting
## on the skids from hovering just above them.
const LANDED_AGL := 0.5          ## m of measured AGL below which the ground is "close"
const LANDED_VSPEED := 0.3       ## m/s of |vertical speed| below which it is "not moving"
## Collective ceiling as a multiple of HOVER collective; margin is slack on stick noise, not
## headroom — above it is a takeoff regardless of the other two conditions.
const LANDED_COLLECTIVE_FRAC := 1.05
## Seconds all three must hold before the bit sets. Asymmetric — see landed_hold.
const LANDED_DEBOUNCE := 0.5


# --- GNSS: the sky pattern and what comes back from it -------------------------

## Fixed sky pattern: `n` unit directions in the WORLD frame (+Y up), area-uniform over the
## cap from zenith to `mask_deg`, golden-angle spiral. World up, not body up — a body-frame
## cone would swing the constellation on every lean and drop the fix in a turn. Deterministic,
## built once at _ready.
static func sky_pattern(n: int, mask_deg: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if n <= 0:
		return out
	out.resize(n)
	# Area-uniform over a cap means uniform in cos(zenith), so the cosine — not the angle —
	# is what gets spread evenly from 1 (straight up) down to cos(mask).
	var cos_max := cos(deg_to_rad(clampf(mask_deg, 0.0, 90.0)))
	var golden := PI * (3.0 - sqrt(5.0))  # 2.39996 rad, the sunflower angle
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var cz := 1.0 - t * (1.0 - cos_max)
		var sz := sqrt(maxf(1.0 - cz * cz, 0.0))
		var az := golden * float(i)
		out[i] = Vector3(sz * cos(az), cz, sz * sin(az))
	return out


## The ONE query object both sensor rays refill and reuse, caller-owned, held for the
## craft's life to avoid 5 throwaway RefCounteds/tick. Mask must stay `Layers.SOLID` (omits
## Containment) or WorldBounds' walls eat satellites over open water.
static func make_query(exclude: Array[RID]) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Layers.SOLID
	query.exclude = exclude
	return query


## Recast `per_tick` rays of `pattern` from `cursor` into the visibility mask (bit i = ray i
## reached the sky); untouched rays keep their last reading. Not pure — the measurement IS
## the raycast. `query` comes from `make_query`, refilled per ray, never rebuilt.
static func sweep_sky(space: PhysicsDirectSpaceState3D, origin: Vector3,
		pattern: PackedVector3Array, visible: int, cursor: int, per_tick: int,
		query: PhysicsRayQueryParameters3D) -> int:
	var n := pattern.size()
	if space == null or n <= 0 or query == null:
		return visible
	var out := visible
	for k in mini(maxi(per_tick, 0), n):
		var i := (cursor + k) % n
		query.from = origin
		query.to = origin + pattern[i] * SKY_RANGE
		if space.intersect_ray(query).is_empty():
			out |= 1 << i
		else:
			out &= ~(1 << i)
	return out


## Satellites in view: set bits of the mask over the `n` rays the pattern has. Bits above
## the pattern are ignored, so a shrunk pattern can't report satellites that no longer exist.
static func sats(visible: int, n: int) -> int:
	var count := 0
	for i in maxi(n, 0):
		if (visible & (1 << i)) != 0:
			count += 1
	return count


## uavcan.equipment.gnss.Fix2.status from the satellite count, and from nothing else.
static func fix_type(sat_count: int) -> int:
	if sat_count >= FIX_SATS_3D:
		return FIX_3D
	if sat_count >= FIX_SATS_2D:
		return FIX_2D
	if sat_count >= FIX_SATS_TIME:
		return FIX_TIME_ONLY
	return FIX_NONE


## Horizontal dilution of precision: a labelled honest model. Approximated by satellite spread.
## Bunched satellites solve badly, spread ones solve well. Clamped to HDOP_MAX when below four
## satellites (returns ceiling, not a plausible lie).
static func hdop(pattern: PackedVector3Array, visible: int) -> float:
	var sum := Vector3.ZERO
	var n := 0
	for i in pattern.size():
		if (visible & (1 << i)) != 0:
			sum += pattern[i]
			n += 1
	if n < FIX_SATS_3D:
		return HDOP_MAX
	var spread := 1.0 - (sum / float(n)).length()
	return clampf(HDOP_K / maxf(spread, HDOP_MIN_SPREAD), 0.0, HDOP_MAX)


# --- rangefinder ---------------------------------------------------------------

## Height above whatever is under the craft: one ray straight DOWN in world space against
## level collision. Returns RANGE_INVALID (not zero) on no hit inside RANGE_MAX. World down,
## not body down, is the tilt correction — same number a slant beam / cos(pitch)*cos(roll)
## gives, with no second model. Clamped at zero so a level hit can't read as the sentinel.
static func measure_agl(space: PhysicsDirectSpaceState3D, origin: Vector3,
		query: PhysicsRayQueryParameters3D) -> float:
	if space == null or query == null:
		return RANGE_INVALID
	query.from = origin
	query.to = origin + Vector3.DOWN * RANGE_MAX
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return RANGE_INVALID
	return maxf(origin.y - (hit.position as Vector3).y, 0.0)


# --- the landed predicate ------------------------------------------------------

## Are all three landing conditions true this tick? An invalid agl (sentinel or no reading)
## is not "close to the ground" — must be tested for explicitly, not compared as a number.
static func landed_now(agl: float, vspeed: float, collective: float,
		agl_max: float, vspeed_max: float, collective_max: float) -> bool:
	if agl < 0.0 or agl > agl_max:
		return false
	if absf(vspeed) > vspeed_max:
		return false
	return collective <= collective_max


## Debounce accumulator: seconds the conditions have held continuously. Counts up while they
## hold, drops to zero the instant any breaks.
##
## Asymmetric on purpose: a landing bounces (skids touch, hop, rangefinder flickers), so
## setting waits out LANDED_DEBOUNCE. Clearing must NOT wait — a ground bit lingering into a
## takeoff is the same lie this replaced, only shorter.
static func landed_hold(prev_s: float, now: bool, delta: float) -> float:
	return prev_s + maxf(delta, 0.0) if now else 0.0
