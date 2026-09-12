## Player-selectable overrides for a level's authored `wind`/`current`, applied at runtime by
## `Level.set_conditions`. Pure static logic, preload-only (not `class_name`'d) so the baker's
## headless walk never depends on it. The shell holds the chosen preset/direction for the
## session and re-applies it to every level it loads.
##
## The UI enters direction as meteorological "FROM" degrees (0 = wind/current coming out of the
## north); `WindField`/`CurrentField` store the heading the flow goes TOWARD, so the one
## conversion (`from + 180`, wrapped) happens exactly once, in `wind_for`/`current_for` below.

enum Preset { LEVEL, CALM, LIGHT, STRONG }
const PRESET_LABELS := ["LEVEL", "CALM", "LIGHT", "STRONG"]

## The UI cycles direction in 45-degree steps, one of 8 compass points.
const DIRECTION_STEP_DEG := 45.0
const COMPASS := ["NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST",
		"NORTHWEST"]

## Families whose physics reads the level's wind (drone/plane drag, BoatVehicle windage —
## src/vehicles/CLAUDE.md's drag block); ground vehicles and the train ignore it.
const WIND_FAMILIES := ["drone", "plane", "boat"]
## Families whose physics reads the level's current (BoatVehicle hull drag, `boat.gd`); nothing
## else names `CurrentField`.
const CURRENT_FAMILIES := ["boat"]

## LIGHT wind: a steady breeze a hovering drone or a cruising plane shrugs off without drama.
const WIND_LIGHT_SPEED := 4.0
const WIND_LIGHT_GUST := 1.5
## STRONG wind: hard but still flyable. A hovering drone (`drone_spec.tres` mass 5 kg,
## `drone.gd`'s `max_thrust` 150 N) sustains ~30.6 m/s of level, non-climbing flight at its
## 32-degree `max_tilt_deg` ceiling (vertical component pays the 49 N hover load, horizontal
## component `horizontal_drag * v` is what's left) — 9 + 4 gust is under half of that, so a headwind
## costs authority without stopping the craft. The plane's 13 m/s `stall_speed` (`plane.gd`)
## means a strong tailwind gust bites into margin on a slow final — the intended bite, not a bug.
const WIND_STRONG_SPEED := 9.0
const WIND_STRONG_GUST := 4.0
## Fixed so a chosen preset always flies the same gust sequence (`WindField.gust_seed`'s contract).
const GUST_SEED := 1

## LIGHT/STRONG current: sized against `BoatVehicle`'s hull drag so a boat can still make way
## against either preset (`src/vehicles/CLAUDE.md`'s drag block; boats are the only current reader).
const CURRENT_LIGHT_DRIFT := 0.5
const CURRENT_STRONG_DRIFT := 1.5
## A player-picked current is one steady push for the session, not an authored tide cycle: period
## 0 pins `CurrentField.rate_at` at `drift` forever (see `current_field.gd`).
const CURRENT_PERIOD_S := 0.0
const CURRENT_OFFSET_S := 0.0


## Cycles LEVEL -> CALM -> LIGHT -> STRONG -> LEVEL.
static func next_preset(p: int) -> int:
	return (p + 1) % PRESET_LABELS.size()


## "SW" etc. for a FROM-degrees heading, snapped to the nearest of the 8 compass points.
static func compass_label(from_deg: float) -> String:
	var idx := int(round(fposmod(from_deg, 360.0) / DIRECTION_STEP_DEG)) % COMPASS.size()
	return COMPASS[idx]


## Wind for `preset` at FROM-heading `from_deg`. LEVEL returns `authored` unchanged (may be
## null); CALM is dead calm (null); LIGHT/STRONG are a NEW `WindField` — the authored `.tres` is
## shared and must never be mutated.
static func wind_for(preset: int, authored: WindField, from_deg: float) -> WindField:
	match preset:
		Preset.CALM:
			return null
		Preset.LIGHT, Preset.STRONG:
			var w := WindField.new()
			w.direction_deg = fposmod(from_deg + 180.0, 360.0)   # FROM -> the TOWARD heading WindField stores
			w.speed = WIND_LIGHT_SPEED if preset == Preset.LIGHT else WIND_STRONG_SPEED
			w.gust_speed = WIND_LIGHT_GUST if preset == Preset.LIGHT else WIND_STRONG_GUST
			w.gust_seed = GUST_SEED
			return w
		_:
			return authored


## Current for `preset` at the same FROM-heading `from_deg` the wind uses. LEVEL/CALM/LIGHT/STRONG
## as `wind_for`; a fresh `CurrentField`, never the authored one mutated.
static func current_for(preset: int, authored: CurrentField, from_deg: float) -> CurrentField:
	match preset:
		Preset.CALM:
			return null
		Preset.LIGHT, Preset.STRONG:
			var c := CurrentField.new()
			c.set_deg = fposmod(from_deg + 180.0, 360.0)   # FROM -> the TOWARD heading CurrentField stores
			c.drift = CURRENT_LIGHT_DRIFT if preset == Preset.LIGHT else CURRENT_STRONG_DRIFT
			c.tide_period_s = CURRENT_PERIOD_S
			c.tide_offset_s = CURRENT_OFFSET_S
			return c
		_:
			return authored
