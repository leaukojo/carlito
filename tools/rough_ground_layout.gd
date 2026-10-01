extends RefCounted
## Where everything on the rough-ground dev level is, shared by the tool that writes the level
## (`gen_rough_ground.gd`) and the tool that drives it (`measure_rough.gd`), so a patch cannot
## move under the measurement. `preload`ed, never `class_name`d, like every tools/ helper.
##
## Two parallel lanes run north (-Z), one asphalt and one mud, carrying the same patches at the
## same z in the same order: a flat control, three random-bump fields of rising amplitude, then
## three V-ditches of rising depth. Both lanes share one bump field per patch (the seed is the
## patch's, never the lane's), so the only difference between a lane pair is the surface.
##
## A V-ditch is a trough across the lane, `depth` deep on its centre line and level again
## DITCH_HALF either side, in a patch one metre longer than the trough so the centre line falls
## on a heightmap row. Sampled on the 1 m grid that is the profile [0, d/3, d, d/3, 0]: two 1 m
## segments a side, the inner one at 2d/3 per metre (the nominal d / 1.5 m wall) and the outer
## at half that. The 50 cm ditch's inner wall is
## atan(0.333) = 18.4 deg, above the atan(0.5 - 0.2) = 16.7 deg ceiling a perfect all-wheel
## drive can hold in mud (grip 0.5, added crr 0.2) on a uniform grade. But the wall is 1 m of run,
## shorter than any wheelbase, so while the front pair climbs it the rear pair pushes from the
## gentler face, and a body arrives rolling: a traction-capable 4x4 crosses it at a crawl and
## stalls on it from a near-standstill, which is honest. The pull-away ceiling itself is checked by
## `measure_grade`, on a whole-body grade. The 35 cm ditch's wall is 13.1 deg, under it.

enum Kind { FLAT, BUMPS, DITCH }

const LEVEL_PATH := "res://src/levels/dev/rough_ground/rough_ground.tscn"

## World extent (X and Z) of the island's square heightmap, one cell per metre.
const SIZE := 352.0
## White-pixel amplitude: 3.06 / 255 = 12 mm per 8-bit step, and PLATEAU_Y lands on step 200.
const HEIGHT := 3.06
const PLATEAU_Y := 2.4
const SEA_Y := 1.0
## Flat disc everything sits on, then a blend ring down to the seabed, so the coast is round.
const PLATEAU_R := 150.0
const PLATEAU_BLEND := 20.0

const LANE_WIDTH := 10.0
## Lane name -> centre x and the splat channel painted under it (HeightmapTerrain order:
## 5 Mud, 6 Asphalt — the level's channel table matches measure_grade.gd's named surfaces).
const LANES: Array[Dictionary] = [
	{"name": "asphalt", "x": -8.0, "channel": 6},
	{"name": "mud", "x": 8.0, "channel": 5},
]

## z of the first patch's south edge; the lanes run north from here.
const FIRST_PATCH_Z := 110.0
## Flat ground between two patches: a standing-start run-up plus room for the longest body
## (the tractor, ~4 m) to clear one patch before its nose reaches the next.
const GAP := 18.0
## Metres south of a patch's edge the measured body starts, at rest.
const RUN_UP := 10.0

const BUMP_LATTICE := 3.0   ## m between random height samples, so the two tracks disagree
const BUMP_TAPER := 3.0     ## m over which a bump field fades in and out at its ends
const BUMP_SEED := 4127
const DITCH_HALF := 1.5     ## m from a ditch's centre line to where it is level again
const DITCH_LENGTH := 2.0 * DITCH_HALF + 1.0  ## whole metres either side of an on-grid centre

## In driving order. `amp` is the bump field's peak (+-amp about the plateau), `depth` the
## ditch's; `length` is the patch's extent along the lane.
const PATCHES: Array[Dictionary] = [
	{"name": "flat", "kind": Kind.FLAT, "length": 24.0},
	{"name": "bumps_5", "kind": Kind.BUMPS, "length": 24.0, "amp": 0.05},
	{"name": "bumps_10", "kind": Kind.BUMPS, "length": 24.0, "amp": 0.10},
	{"name": "bumps_20", "kind": Kind.BUMPS, "length": 24.0, "amp": 0.20},
	{"name": "ditch_20", "kind": Kind.DITCH, "length": DITCH_LENGTH, "depth": 0.20},
	{"name": "ditch_35", "kind": Kind.DITCH, "length": DITCH_LENGTH, "depth": 0.35},
	{"name": "ditch_50", "kind": Kind.DITCH, "length": DITCH_LENGTH, "depth": 0.50},
]


## South edge (larger z: the lanes run toward -Z) of patch `index`.
static func patch_start_z(index: int) -> float:
	var z := FIRST_PATCH_Z
	for i in index:
		z -= float(PATCHES[i]["length"]) + GAP
	return z


## North edge of patch `index`.
static func patch_end_z(index: int) -> float:
	return patch_start_z(index) - float(PATCHES[index]["length"])


static func lane_index(lane_name: String) -> int:
	for i in LANES.size():
		if String(LANES[i]["name"]) == lane_name:
			return i
	return -1


static func patch_index(patch_name: String) -> int:
	for i in PATCHES.size():
		if String(PATCHES[i]["name"]) == patch_name:
			return i
	return -1


## Height above the plateau (m, negative = below) patch `index` puts at world x/z, 0 outside it.
## Lane-relative, so every lane gets the same field: `lane_dx` is x minus the lane's centre.
static func relief(index: int, lane_dx: float, world_z: float) -> float:
	if absf(lane_dx) > LANE_WIDTH * 0.5:
		return 0.0
	var p: Dictionary = PATCHES[index]
	var from := patch_start_z(index)
	var along := from - world_z  ## metres into the patch
	var length := float(p["length"])
	if along < 0.0 or along > length:
		return 0.0
	match int(p["kind"]):
		Kind.BUMPS:
			var taper := minf(clampf(along / BUMP_TAPER, 0.0, 1.0),
					clampf((length - along) / BUMP_TAPER, 0.0, 1.0))
			return float(p["amp"]) * taper * _value_noise(BUMP_SEED + index,
					(lane_dx + LANE_WIDTH * 0.5) / BUMP_LATTICE, along / BUMP_LATTICE)
		Kind.DITCH:
			var off := absf(along - length * 0.5)
			return -float(p["depth"]) * maxf(0.0, 1.0 - off / DITCH_HALF)
	return 0.0


## Smooth value noise in [-1, 1]: a seeded random value on every integer lattice point,
## smoothstep-blended between them. Pure and deterministic, so a replay writes the same bytes.
static func _value_noise(seed_value: int, u: float, v: float) -> float:
	var i := floori(u)
	var j := floori(v)
	var fu := u - float(i)
	var fv := v - float(j)
	var su := fu * fu * (3.0 - 2.0 * fu)
	var sv := fv * fv * (3.0 - 2.0 * fv)
	var a := lerpf(_lattice(seed_value, i, j), _lattice(seed_value, i + 1, j), su)
	var b := lerpf(_lattice(seed_value, i, j + 1), _lattice(seed_value, i + 1, j + 1), su)
	return lerpf(a, b, sv)


static func _lattice(seed_value: int, i: int, j: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(seed_value, i, j))
	return rng.randf_range(-1.0, 1.0)
