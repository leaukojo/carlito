extends Node
## One-shot generator for the Kenney car-kit vehicle variants (CC0). For each variant writes
## src/vehicles/kenney/<variant>.tscn + <variant>_spec.tres from a family baseline + per-variant
## overrides (chassis, GLB body, lamps, wheels). brake_torque / handbrake_torque are always
## derived from the tyre (BRAKE_GRIP_FRAC / _derive_brakes), never hand-tuned.
## Game-mode tool scene (not --script): base_vehicle.gd / tractor.gd need the InputRouter/Bridge
## autoloads. Run `godot --headless --path . res://tools/gen_kenney_vehicles.tscn`.
## Deterministic and destructive-by-run: a hand-tune driven into a shipped .tres must be folded
## back into the recipe here before the next run, or the rerun silently discards it.

const OUT_DIR := "res://src/vehicles/kenney"
const MODELS := OUT_DIR + "/models"
const BASE_SCRIPT := "res://src/vehicles/base/base_vehicle.gd"
const TRACTOR_SCRIPT := "res://src/vehicles/tractor/tractor.gd"
const TRUCK_SCRIPT := "res://src/vehicles/truck/truck.gd"
## Vehicle script per CONTRACT family; unlisted gets plain BaseVehicle. Garbage-truck/firetruck
## are family "truck" (J1939 chassis); the heavy vans drive like trucks but are family "car"
## (ordinary chassis, proprietary CAN) and keep base_vehicle.gd.
const FAMILY_SCRIPTS := {"tractor": TRACTOR_SCRIPT, "truck": TRUCK_SCRIPT}

const KIT_SCALE := 1.2
## Direct children this generator writes and may replace on regen. Everything else in the scene
## is hand-authored and transplanted (see _existing_children): the collision box pair, the
## tractor's ThreePointHitch, and the hand-placed "HoodCam" marker.
const GENERATED_CHILDREN := ["Model", "Lamps"]
const COLORMAP := OUT_DIR + "/models/Textures/colormap.png"

## --- lamp-lens detection (see _find_lenses) -------------------------------------------
const LENS_WELD := 0.001       ## m, vertex weld tolerance for the triangle union-find
const LENS_MERGE_GAP := 0.02   ## m two lens fragments may be apart and still be one lens
## The lamp mesh encloses the model's lens rather than sitting on it: every outward face is
## held this far outside the lens face (see _split).
const LENS_CLEAR := 0.006
const LENS_MIN_DEPTH := 0.04   ## m depth floor for a lens the model draws as a flat quad
const LENS_MIN_H := 0.06       ## m floor on lens height (some are a single flat quad)
const TURN_FRAC := 0.35        ## outboard share of a lens' width that becomes the indicator
const DISC_MIN_TRIS := 12      ## a lens this dense with square extents is a disc, not a box
const WHEEL_RADIUS := 0.36  ## physics radius, all four corners (RayWheel is single-radius)

## --- resistance (see VehicleMath's road-resistance header) ----------------------------
## Frontal area is derived from each body's own AABB (not listed per variant) at FRONTAL_FILL,
## the standard A ~ 0.8 * width * height rule of thumb for a non-rectangular silhouette. Wheels
## are outside the AABB and not added; they're already inside the Cd this multiplies.
const FRONTAL_FILL := 0.82
const GRAVITY := 9.8
## Share of the tyre's own longitudinal grip full pedal asks for; every baseline derives its foot
## brake from the tyre through this (see _derive_brakes): deceleration at full pedal is
## `frac * mu_long * g` on every body, whatever it weighs. Just under 1 because RayWheel's slip
## tyre saturates at the ceiling; past it the pedal becomes an on/off lock with no steering.
const BRAKE_GRIP_FRAC := 0.95
const MIN_CLEARANCE := 0.12  ## m the collision hull floor is held above the wheel-contact plane
const WHEEL_BAND := 0.4   ## m z-window (body space) the body half-width is measured over per axle

## Wheel visuals per model: the radius-normalized scene, the rendered radius, and the tread
## half-width at that radius. The flush-X rule below places the wheel's outer face at the body
## side, so this must match the model.
const WHEEL_DEFAULT := {"scene": OUT_DIR + "/wheel.tscn", "radius": WHEEL_RADIUS, "half": 0.240}
const WHEEL_TRUCK := {"scene": OUT_DIR + "/wheel-truck.tscn", "radius": WHEEL_RADIUS, "half": 0.210}
## Tractor axles differ visually only (0.30 / 0.45 straddling the 0.36 physics radius).
const WHEEL_TRACTOR_FRONT := {
	"scene": OUT_DIR + "/wheel-tractor-front.tscn", "radius": 0.30, "half": 0.206}
const WHEEL_TRACTOR_REAR := {
	"scene": OUT_DIR + "/wheel-tractor-rear.tscn", "radius": 0.45, "half": 0.276}

# Not const: Vector2 / NodePath / Array literals aren't constant expressions in GDScript.
var _grip_curve := PackedVector2Array([
		Vector2(0, 0), Vector2(0.12, 1), Vector2(0.4, 0.9), Vector2(1, 0.8)])
var _lamp_paths := {
	"headlight_paths": [NodePath("Lamps/HeadlightL"), NodePath("Lamps/HeadlightR")],
	"head_lamp_paths": [NodePath("Lamps/HeadLensL"), NodePath("Lamps/HeadLensR")],
	"brake_lamp_paths": [NodePath("Lamps/BrakeLampL"), NodePath("Lamps/BrakeLampR")],
	"turn_left_paths": [NodePath("Lamps/TurnLF"), NodePath("Lamps/TurnLR")],
	"turn_right_paths": [NodePath("Lamps/TurnRF"), NodePath("Lamps/TurnRR")],
}
## Hand-measured lens boxes [centre, size] for models where the atlas swatch is too close to the
## body colour for detection to find the edge. Replaces whatever _find_lenses returned there.
var _lens_overrides := {
	# taxi: amber lamp on amber bodywork over-reaches downward; top pinned at the real lens top.
	"taxi": {"front": [Vector3(0.495, 0.90, -1.53), Vector3(0.33, 0.12, 0.0)]},
	# ambulance: thin vertical red tail stripe; detection picked the centred cross livery instead.
	"ambulance": {"rear": [Vector3(0.72, 0.72, 1.84), Vector3(0.12, 0.44, 0.10)]},
	# race / race-future: open-wheelers paint no lamp swatch, so detection returns nothing and the
	# body-box fallback floats off the slim nose/tail; measured off the model's own nose/tail
	# bodywork (see tools/measure_race.gd) instead.
	"race": {
		"front": [Vector3(0.20, 0.22, -1.38), Vector3(0.26, 0.13, 0.12)],
		"rear": [Vector3(0.16, 0.40, 1.30), Vector3(0.22, 0.14, 0.12)],
	},
	"race-future": {
		"front": [Vector3(0.28, 0.31, -1.42), Vector3(0.32, 0.14, 0.14)],
		"rear": [Vector3(0.34, 0.50, 1.42), Vector3(0.34, 0.16, 0.14)],
	},
}
## Lamp height for an end with no painted lens (the body-box fallback centre is wrong there).
## variant -> {front?: y, rear?: y}, body space. Tractor rear: box centre lands too low
## (verified driving); 1.22 is the shipped height.
var _fallback_lamp_y := {"tractor-kenney": {"rear": 1.22}}
var _drag_report: Array = []  ## per-variant measured frontal area + derived drag area
var _shape_report: Array = []  ## per-variant collision shape kind + hull vertex count
var _lens_report: Array = []   ## per-variant lens detection, so a bad lamp is diagnosable
var _brake_report: Array = []  ## per-variant grip-derived brake, so a fictional one is visible

# --- family baselines (spec fields; brake/handbrake are derived, not listed) -----------
const CAR_BASE := {
	# cd 0.32 is a modern saloon; crr 0.012 is a passenger radial on asphalt.
	"cd": 0.32, "crr": 0.012,
	"mass": 1150.0, "com_y": 0.20, "spring_rate": 22000.0, "damper_bump": 1800.0,
	"damper_rebound": 2400.0, "max_suspension_force": 30000.0, "rest_length": 0.28,
	# FWD default; per-variant override in VARIANTS (rwd/awd where the body says so).
	"wheel_inertia": 1.2, "driven_front": true, "driven_rear": false,
	"mu_long": 1.05, "mu_lat": 1.1, "handbrake_grip": 0.45,
	# 185 Nm peak / ~156 hp at 6000 on the base saloon, anchored on a 1150 kg saloon hitting
	# 220 km/h and 8.5 s to 100 (measured 219.8 / 8.35 via `measure_vehicles -- sedan`).
	# Keep the shape when re-scaling: idle fraction 98/185=0.53 lets the car pull away on a grade;
	# 6600/6800 is the plateau coming down then a soft limiter keeping the sports bodies off the
	# rev limiter in sixth.
	"torque_curve": [900, 98, 2000, 154, 3200, 184, 4800, 185, 6000, 185, 6600, 170, 6800, 61],
	"idle_rpm": 900.0, "redline_rpm": 6800.0,
	# Brakes derive from the tyre on every baseline (BRAKE_GRIP_FRAC / _derive_brakes).
	# Sixth is the top-speed control: 0.925 settles the sedan at 6012 rpm / 219.8 km/h.
	# Gears 2-5 re-spread: 1.550 / 1.470 / 1.380 / 1.290 / 1.199.
	"gear_ratios": [4.5, 2.903, 1.975, 1.431, 1.109, 0.925],
	# Reverse stays 2.2, sized against sliding grip not gear 1: 185x2.2x3.9x0.9 = 1429 Nm at the
	# tyres against 2556 Nm of front-axle grip, no sustained reverse burnout.
	"reverse_ratio": 2.2,
	# shift_up 5900, bound by the weak bodies reaching sixth; governed bodies (van/pickup) reach
	# it via `Drivetrain.governed_upshift`.
	"final_drive": 3.9, "efficiency": 0.9, "shift_up_rpm": 5900.0, "shift_down_rpm": 2200.0,
	"max_steer_deg": 38.0, "steer_speed": 7.0,
	# Steering falloff: BaseVehicle lerps lock from full to min_steer_frac near
	# steer_falloff_speed, so the pair states an absolute lock at motorway speed — divide by the
	# variant's own max_steer_deg. Car family: ~10 deg (0.26x38) at 42 m/s = 151 km/h; mu_lat 1.1
	# needs ~2.5x less lock at that speed.
	"min_steer_frac": 0.26, "steer_falloff_speed": 42.0,
}
## Diesel curves end at zero at the redline: the governor droops to nothing above rated speed,
## so top gear is governed (never drag-limited), top speed = `redline x gear 6`.
const TRUCK_BASE := {
	# Flat-fronted working truck: cd 0.70, crr 0.007 for low-resistance commercial radials.
	"cd": 0.70, "crr": 0.007,
	# Spring/damper/force hand-tuned by driving both trucks.
	"mass": 4000.0, "com_y": 0.30, "spring_rate": 240000.0, "damper_bump": 12000.0,
	"damper_rebound": 15800.0, "max_suspension_force": 120000.0, "rest_length": 0.32,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	# J1939: only family with an auxiliary retarder on the driven axle.
	"retarder_equipped": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	"torque_curve": [700, 400, 1200, 650, 1800, 800, 2400, 780, 2800, 600, 3200, 0],
	"idle_rpm": 700.0, "redline_rpm": 3200.0,
	# 6th 1.0 -> 0.92: overdrive top, governed speed ~102 km/h vs 96.5 direct-drive.
	"gear_ratios": [6.5, 3.7, 2.4, 1.6, 1.2, 0.92], "reverse_ratio": 6.0,
	"final_drive": 4.5, "efficiency": 0.9, "shift_up_rpm": 2600.0, "shift_down_rpm": 1200.0,
	"max_steer_deg": 26.0, "steer_speed": 2.0,
	# ~4.8 deg floor (0.22x22) at 26 m/s, under both governed cruise speeds (85/110 km/h);
	# 16.5 deg at 30 km/h, tighter than mu_lat 0.95 allows.
	"min_steer_frac": 0.22, "steer_falloff_speed": 26.0,
}
## Heavy vans (delivery / delivery-flat / ambulance): car-family, proprietary CAN, but drive
## like trucks, so a deliberate snapshot of TRUCK_BASE's numbers rather than an alias — TRUCK_BASE
## also carries J1939-only flags, so the two must be free to diverge.
const VAN_BASE := {
	# A box van is a smoothed truck front: cd 0.45 on commercial tires.
	"cd": 0.45, "crr": 0.009,
	# 4-5 t vans; 240000 N/m is TRUCK_BASE's rate, measured on 8 t, and does not apply here.
	"mass": 4000.0, "com_y": 0.30, "spring_rate": 65000.0, "damper_bump": 5000.0,
	"damper_rebound": 7000.0, "max_suspension_force": 90000.0, "rest_length": 0.32,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	"torque_curve": [700, 400, 1200, 650, 1800, 800, 2400, 780, 2800, 600, 3200, 0],
	"idle_rpm": 700.0, "redline_rpm": 3200.0,
	# 6th 1.0 -> 0.78: governed top ~120 km/h.
	"gear_ratios": [6.5, 3.7, 2.4, 1.6, 1.2, 0.78], "reverse_ratio": 6.0,
	"final_drive": 4.5, "efficiency": 0.9, "shift_up_rpm": 2600.0, "shift_down_rpm": 1200.0,
	"max_steer_deg": 26.0, "steer_speed": 2.0,
	# ~6 deg floor (0.23x26) at 28 m/s, between the cars' 10 deg and trucks' 4.8. Ambulance keeps
	# the fraction on its narrower 24 deg rack (5.5 deg).
	"min_steer_frac": 0.23, "steer_falloff_speed": 28.0,
}
const TRACTOR_BASE := {
	# cd 0.90 (nothing streamlined), crr 0.020 (worst in the project, lugged tires).
	"cd": 0.90, "crr": 0.020,
	"mass": 4200.0, "com_y": 0.35, "spring_rate": 70000.0, "damper_bump": 6000.0,
	"damper_rebound": 8000.0, "max_suspension_force": 110000.0, "rest_length": 0.35,
	"wheel_inertia": 4.0, "driven_front": false, "driven_rear": true,
	# ISOBUS: only family with lockable diff / engageable front axle at runtime.
	"rear_diff_lockable": true, "front_axle_engageable": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	# Rated 2000, governed to nothing by 2600 (high idle).
	"torque_curve": [800, 550, 1200, 680, 1600, 700, 2000, 640, 2200, 560, 2600, 0],
	"idle_rpm": 800.0, "redline_rpm": 2600.0,
	# ~4.4:1 spread, 9 km/h first to a 40 km/h road gear. First is free of the foot brake
	# (tyre-derived), so a crawler gear costs only a bigger handbrake.
	"gear_ratios": [7.0, 5.2, 3.9, 2.9, 2.15, 1.6], "reverse_ratio": 7.0,
	"final_drive": 5.5, "efficiency": 0.9, "shift_up_rpm": 2200.0, "shift_down_rpm": 1000.0,
	"max_steer_deg": 38.0, "steer_speed": 1.8,
	# steer_falloff_speed 11 m/s = 39.6 km/h is the tractor's own top speed, so the floor lock
	# arrives exactly at type-approval road speed. 0.55 keeps field-work cost (8-12 km/h headland
	# turns, a quarter of road speed) to ~11% while cutting 45% of road dartiness.
	"min_steer_frac": 0.55, "steer_falloff_speed": 11.0,
}

# variant id -> { family, base?, torque_mul?, <spec field overrides...> }
# `family` is the CONTRACT family (VehicleCatalog) and picks the feel baseline + vehicle script
# (FAMILY_SCRIPTS); `base` names the feel baseline when it differs (heavy vans are car-family,
# van chassis feel). Driveline flags (rear_diff_lockable / front_axle_engageable /
# retarder_equipped), `gear_ratios` and `com_z` may all be overridden per variant over the
# baseline.
const VARIANTS := {
	# car family
	# Driven layout per body: FWD is the CAR_BASE default, `driven_rear` alone is RWD, both is
	# AWD — the axis that gives each car its own handling (FWD hatch scrabbles, RWD interceptor
	# steps out, SUVs hook up). `front_weight` on the front-drivers puts the transverse engine
	# over the driven axle (measured 48/52 rear-biased at the body origin, unusable for FWD).
	"sedan": {"family": "car", "front_weight": 0.60},
	"sedan-sports": {"family": "car", "mass": 1050.0, "torque_mul": 1.12, "final_drive": 4.1, "max_steer_deg": 40.0, "driven_front": false, "driven_rear": true},
	"hatchback-sports": {"family": "car", "mass": 1000.0, "torque_mul": 1.10, "final_drive": 4.2, "max_steer_deg": 42.0, "front_weight": 0.60},
	# Lever for SUV power is their own `torque_mul`, not the shared CAR_BASE curve: measured
	# 0-100 goes as peak^-0.6 on the sedan, peak^-1.4 on the suv.
	"suv": {"family": "car", "mass": 1500.0, "torque_mul": 1.05, "mu_lat": 1.0, "max_steer_deg": 34.0, "driven_rear": true},
	# 1.54 is the biggest multiplier in the family: 285 Nm through an AWD 1600 kg body.
	"suv-luxury": {"family": "car", "mass": 1600.0, "torque_mul": 1.54, "mu_lat": 1.0, "max_steer_deg": 33.0, "driven_rear": true},
	"taxi": {"family": "car", "mass": 1250.0, "front_weight": 0.60},
	"police": {"family": "car", "mass": 1300.0, "torque_mul": 1.18, "final_drive": 4.0, "max_steer_deg": 40.0, "driven_front": false, "driven_rear": true},
	# Open-wheelers: `wheel_x_out` measured per body against its own half-width at the wheel
	# stations (re-drive after changing, it also steadies cornering). `cd` 0.70: exposed wheels +
	# wing really do run ~2x a saloon's drag. `front_weight` 0.42: engine sits behind the driver;
	# at the body origin they measured 58/42 and 61/39, backwards for the layout. `race` is
	# rear-drive (classic formula car), `race-future` is AWD.
	# Steering falloff exists because of these two: `race` let go at ~140 km/h with full lock
	# live. They keep ~7 deg at the floor, reached at 35 m/s = 126 km/h (family: 151) — still ~6x
	# what mu_lat holds there.
	# `cl` 2.5 is the only wing in the project: same measured area as `cd`, Cl*A 2.24 against
	# Cd*A 0.63 (lift/drag 3.6). 2.1 kN at 140 km/h rising to 8.8 kN at 288 km/h top end; a spring
	# force (GroundDriveSpec.downforce_area) worth ~0.10 m of squat — raising `cl` past this
	# bottoms the suspension.
	# The two gear boxes differ on gear 1: `race` is rear-drive so 3.2 first clears the
	# transmissible-drive hierarchy free. `race-future` is AWD (all four tyres saturate), capped
	# by `max_drive / 4 * 1.02 <= grip_ceiling` at this body's 409 Nm peak -> gear1 <= 2.377,
	# giving 2.375 with 2-5 re-spread (1.33/1.31/1.29/1.27/1.26). Re-derive per body on any
	# torque change. Both keep a long top gear (0.66 vs CAR_BASE's 0.925), reaching 288.0 /
	# 295.8 km/h.
	# `torque_mul` tracks CAR_BASE so absolute torque stays fixed (2.10x185=389 Nm,
	# 2.21x185=409 Nm) — re-derive on any CAR_BASE torque edit.
	"race": {"family": "car", "cd": 0.70, "cl": 2.50, "mass": 900.0, "torque_mul": 2.10, "final_drive": 4.2, "gear_ratios": [3.2, 2.30, 1.72, 1.32, 0.98, 0.66], "mu_long": 1.35, "mu_lat": 1.4, "max_steer_deg": 40.0, "handbrake_grip": 0.5, "driven_front": false, "driven_rear": true, "front_weight": 0.42, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.21, "min_steer_frac": 0.18, "steer_falloff_speed": 35.0},
	"race-future": {"family": "car", "cd": 0.70, "cl": 2.50, "mass": 850.0, "torque_mul": 2.21, "final_drive": 4.2, "gear_ratios": [2.375, 1.786, 1.363, 1.057, 0.832, 0.66], "mu_long": 1.25, "mu_lat": 1.35, "max_steer_deg": 42.0, "handbrake_grip": 0.5, "driven_rear": true, "front_weight": 0.42, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.36, "min_steer_frac": 0.17, "steer_falloff_speed": 35.0},
	# Commercial bodies: RWD, governed at 180 like the real things (measured 198-200 ungoverned).
	"van": {"family": "car", "mass": 1600.0, "max_steer_deg": 32.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0},
	"pickup": {"family": "car", "mass": 1550.0, "torque_mul": 1.05, "max_steer_deg": 33.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0},
	"pickup-flat": {"family": "car", "mass": 1500.0, "torque_mul": 1.05, "max_steer_deg": 33.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0},
	# heavy vans: car family, van feel (VAN_BASE, not CAR_BASE) — these are 4-5 t vehicles
	"delivery": {"family": "car", "base": "van", "mass": 4200.0},
	"delivery-flat": {"family": "car", "base": "van", "mass": 4000.0},
	"ambulance": {"family": "car", "base": "van", "mass": 4800.0, "torque_mul": 1.1, "max_steer_deg": 24.0, "speed_limit_kmh": 150.0},
	# truck family (J1939) — garbage-truck first, matching VehicleCatalog's cycle order.
	# com_z -0.14 = 0.14 m forward (front = -Z), hand-tuned by driving: the hopper body pulls
	# mass back off the rear axle. 90 km/h is the EU heavy-truck limiter (a refuse collector
	# usually runs lower); this is the one body the governor visibly bites (measured 99.5).
	"garbage-truck": {"family": "truck", "mass": 8000.0, "torque_mul": 1.3, "com_z": -0.14, "max_steer_deg": 22.0, "steer_speed": 1.6, "speed_limit_kmh": 85.0},
	# Emergency vehicles are exempt from the goods-vehicle limiter; 110 is the appliance's own
	# rating, just above what this body reaches.
	"firetruck": {"family": "truck", "mass": 7500.0, "torque_mul": 1.3, "max_steer_deg": 22.0, "steer_speed": 1.6, "speed_limit_kmh": 110.0},
	# tractor family (ISOBUS) — one drivable body.
	# 40 km/h is type approval; gearing already lands on 39.6, so this limit never acts, but
	# catches a future gearing change that would make the body road-illegal.
	"tractor-kenney": {"family": "tractor", "mass": 4000.0, "speed_limit_kmh": 40.0},
}

## Feel baselines, keyed by a variant's `base` (defaulting to its `family`). "van" is a feel
## baseline only — no such contract family exists.
const BASELINES := {
	"car": CAR_BASE, "van": VAN_BASE, "truck": TRUCK_BASE, "tractor": TRACTOR_BASE}

## family -> [front wheel, rear wheel]; a variant may override with "wheels".
const FAMILY_WHEELS := {
	"car": [WHEEL_TRUCK, WHEEL_TRUCK],
	"truck": [WHEEL_TRUCK, WHEEL_TRUCK],
	"tractor": [WHEEL_TRACTOR_FRONT, WHEEL_TRACTOR_REAR],
}


func _ready() -> void:
	var ok := 0
	for variant: String in VARIANTS:
		var ov: Dictionary = VARIANTS[variant]
		var family := String(ov["family"])
		var wheels: Array = ov.get("wheels", FAMILY_WHEELS[family])
		var geo := _analyze(MODELS.path_join(variant + ".glb"), wheels)
		if geo.is_empty():
			continue
		var recipe := ov.duplicate()
		recipe["_id"] = variant
		var spec := _build_spec(String(ov.get("base", family)), recipe, geo, wheels)
		var spec_path := OUT_DIR.path_join(variant + "_spec.tres")
		if _save_spec_stable(spec, spec_path) != OK:
			push_error("failed to save " + spec_path)
			continue
		var scene_script: Variant = load(String(FAMILY_SCRIPTS.get(family, BASE_SCRIPT)))
		var scene := _build_scene(variant, scene_script, load(spec_path), geo)
		var scene_path := OUT_DIR.path_join(variant + ".tscn")
		if _save_scene_stable(scene, scene_path) != OK:
			push_error("failed to save " + scene_path)
			continue
		ok += 1
	print("gen_kenney_vehicles: wrote %d/%d variants" % [ok, VARIANTS.size()])
	print("collision shapes: ", ", ".join(_shape_report))
	print("resistance (frontal area measured off the body AABB, see FRONTAL_FILL):")
	for line: String in _drag_report:
		print("   ", line)
	print("brakes (per wheel; see BRAKE_GRIP_FRAC / _derive_brakes):")
	for line: String in _brake_report:
		print("   ", line)
	print("lamp lenses (right side; 'fallback' = no lamp painted on that end):")
	for line: String in _lens_report:
		print("   ", line)
	get_tree().quit(0 if ok == VARIANTS.size() else 1)


# --- spec ------------------------------------------------------------------------------

## `baseline` is the BASELINES key (a variant's `base`, else its `family`) — the feel recipe,
## which is not always the contract family (heavy vans are car-family on the van baseline).
func _build_spec(baseline: String, ov: Dictionary, geo: Dictionary, wheels: Array) -> VehicleSpec:
	var b: Dictionary = BASELINES[baseline]
	var get_f := func(key: String) -> float: return float(ov.get(key, b[key]))
	var get_flag := func(key: String) -> bool: return bool(ov.get(key, b.get(key, false)))

	var spec := VehicleSpec.new()
	# The wheeled ground drive: every body has one, embedded in the saved .tres (no separate
	# resource_path).
	var gd := GroundDriveSpec.new()
	spec.ground_drive = gd
	spec.mass = get_f.call("mass")
	# com_y is a family figure; com_z is per body, preferring `front_weight` (fraction of static
	# weight on the front axle) over a raw `com_z` offset. com_z 0 is wherever Kenney put the
	# body origin, which spans 36/64 to 61/39 across these bodies — invisible under AWD (four
	# driven wheels carry any split), but decisive the moment a variant drives one axle: the
	# open-wheeler launched badly as a rear-driver because its origin was 58% front-heavy.
	spec.center_of_mass = Vector3(0, float(b["com_y"]), _com_z(geo, ov))
	# Resistance: Cd + crr from the family recipe, frontal area measured off this body's own
	# AABB (FRONTAL_FILL). Snapped to 0.01 m^2 so a regen writes a stable file.
	var body_box: AABB = geo["box"]
	gd.drag_area = float(roundi(
			get_f.call("cd") * FRONTAL_FILL * body_box.size.x * body_box.size.y * 100.0)) / 100.0
	gd.rolling_resistance = get_f.call("crr")
	# Downforce is a per-variant opt-in (`cl`), no baseline — a wing belongs to the individual
	# body. Measures the same area as drag so the two never disagree about size.
	var cl := float(ov.get("cl", 0.0))
	gd.downforce_area = float(roundi(
			cl * FRONTAL_FILL * body_box.size.x * body_box.size.y * 100.0)) / 100.0
	_drag_report.append("%-16s box %.2f w x %.2f h = %.2f m^2, cd %.2f -> Cd*A %.2f, crr %.3f%s" % [
			ov.get("_id", ""), body_box.size.x, body_box.size.y,
			FRONTAL_FILL * body_box.size.x * body_box.size.y, get_f.call("cd"),
			gd.drag_area, gd.rolling_resistance,
			"" if cl <= 0.0 else ", cl %.2f -> Cl*A %.2f" % [cl, gd.downforce_area]])
	gd.wheel_radius = WHEEL_RADIUS
	gd.wheel_inertia = float(b["wheel_inertia"])
	# Wheel visuals: one scene per axle when they differ (tractor); physics stays single-radius
	# (gd.wheel_radius is the only radius RayWheel uses).
	var front_wheel: Dictionary = wheels[0]
	var rear_wheel: Dictionary = wheels[1]
	gd.wheel_scene = load(String(front_wheel["scene"])) as PackedScene
	if String(rear_wheel["scene"]) != String(front_wheel["scene"]):
		gd.wheel_scene_rear = load(String(rear_wheel["scene"])) as PackedScene
	var front_r := float(front_wheel["radius"])
	var rear_r := float(rear_wheel["radius"])
	# Left at 0 (= wheel_radius) only when both axles render at the physics radius.
	if front_r != WHEEL_RADIUS or rear_r != WHEEL_RADIUS:
		gd.wheel_visual_radius = front_r
		gd.wheel_visual_radius_rear = rear_r
	# Driven layout is per variant with the baseline as fallback. `get_flag` would be wrong here
	# (defaults a missing key to false, silently undriving an axle the baseline drives).
	gd.driven_front = bool(ov.get("driven_front", b["driven_front"]))
	gd.driven_rear = bool(ov.get("driven_rear", b["driven_rear"]))
	# Driveline capability flags, off unless declared: per-variant override consulted first,
	# baseline as fallback (reading only the baseline would make a per-variant override
	# silently impossible).
	gd.rear_diff_lockable = get_flag.call("rear_diff_lockable")
	gd.front_axle_engageable = get_flag.call("front_axle_engageable")
	gd.retarder_equipped = get_flag.call("retarder_equipped")
	gd.rest_length = float(b["rest_length"])
	gd.spring_rate = float(b["spring_rate"])
	gd.damper_bump = float(b["damper_bump"])
	gd.damper_rebound = float(b["damper_rebound"])
	gd.max_suspension_force = float(b["max_suspension_force"])
	gd.grip_curve = _grip_curve.duplicate()
	gd.mu_long = get_f.call("mu_long")
	gd.mu_lat = get_f.call("mu_lat")
	gd.handbrake_grip = get_f.call("handbrake_grip")

	var torque_mul := float(ov.get("torque_mul", 1.0))
	spec.torque_curve = _scaled_curve(b["torque_curve"], torque_mul)
	spec.idle_rpm = float(b["idle_rpm"])
	spec.redline_rpm = float(b["redline_rpm"])
	# A whole array, so it takes the same per-variant override path as the scalars: the two
	# open-wheelers run a close-ratio box the rest of the car family does not.
	spec.gear_ratios = PackedFloat32Array(ov.get("gear_ratios", b["gear_ratios"]))
	spec.reverse_ratio = float(b["reverse_ratio"])
	spec.final_drive = get_f.call("final_drive")
	spec.efficiency = float(b["efficiency"])
	spec.shift_up_rpm = float(b["shift_up_rpm"])
	spec.shift_down_rpm = float(b["shift_down_rpm"])
	# Road-speed governor (0 = ungoverned). Per variant with a baseline fallback: what a body is
	# limited to is a regulatory/class fact about that body, not a family feel knob.
	spec.speed_limit_kmh = float(ov.get("speed_limit_kmh", b.get("speed_limit_kmh", 0.0)))
	spec.steer_speed = get_f.call("steer_speed")
	# The LOCK is a ground-drive figure (a lock means nothing without a steered wheel); the slew
	# rate above stays on the core spec. High-speed falloff is per variant with a baseline
	# fallback: the fraction is keyed to the body's own max_steer_deg (see CAR_BASE's header),
	# so a variant that overrides the rack usually wants to override this too rather than
	# inherit the family number.
	gd.max_steer_deg = get_f.call("max_steer_deg")
	gd.min_steer_frac = get_f.call("min_steer_frac")
	gd.steer_falloff_speed = get_f.call("steer_falloff_speed")

	gd.wheel_positions = _wheel_positions(geo, spec, gd, float(ov.get("wheel_x_out", 0.0)))
	_derive_brakes(spec, gd, String(ov.get("_id", "")))

	spec.headlight_paths.assign(_lamp_paths["headlight_paths"])
	spec.head_lamp_paths.assign(_lamp_paths["head_lamp_paths"])
	spec.brake_lamp_paths.assign(_lamp_paths["brake_lamp_paths"])
	spec.turn_left_paths.assign(_lamp_paths["turn_left_paths"])
	spec.turn_right_paths.assign(_lamp_paths["turn_right_paths"])
	return spec


## FL, FR, RL, RR hub anchors at the Kenney model's own wheel positions (body space), so RayWheel
## visuals sit in the wheel wells. Anchor Y is uniform so the body rests level: at spring
## equilibrium the visual wheel centre lands at WHEEL_RADIUS above ground. `x_out` pushes a
## corner further outboard (open-wheelers), widening suspension and visual track together.
func _wheel_positions(geo: Dictionary, spec: VehicleSpec, gd: GroundDriveSpec,
		x_out: float) -> PackedVector3Array:
	var corner_mass := spec.mass / 4.0
	var comp := clampf(corner_mass * GRAVITY / gd.spring_rate, 0.0, gd.rest_length * 0.8)
	var y := WHEEL_RADIUS + gd.rest_length - comp
	var fl := Vector3.ZERO
	var fr := Vector3.ZERO
	var rl := Vector3.ZERO
	var rr := Vector3.ZERO
	for xz: Vector2 in geo["wheel_xz"]:
		var p := Vector3(xz.x + signf(xz.x) * x_out, y, xz.y)  # body space (front = -Z, right = +X)
		if p.z < 0.0:
			if p.x < 0.0: fl = p
			else: fr = p
		else:
			if p.x < 0.0: rl = p
			else: rr = p
	return PackedVector3Array([fl, fr, rl, rr])


## Derive brake/handbrake from the tyre on every baseline — one derivation, no per-baseline
## brake knob. `brake_torque = BRAKE_GRIP_FRAC * the tyre's own per-wheel ceiling`, so full pedal
## asks for `BRAKE_GRIP_FRAC * mu_long * g` of deceleration regardless of body mass or gearing.
## `handbrake_torque` (x2) = 1.5 * launch torque at idle+25% throttle (strictly between the
## 25%/50% brackets `test_vehicle_catalog` checks; `wheel_torque` is linear in throttle so this
## holds at any gear-1 ratio).
##
## The floor is the force hierarchy stated against transmissible drive: the brake must beat
## `min(peak drive, driven * per-wheel grip)`, since it never needs to out-muscle torque a
## spinning tyre can't hand the road. Free on a 2-driven-wheel body (1.9x margin); on AWD it's
## 3.8 against 4.0, so an engine that saturates all four tyres can land 2% over its own tyre —
## the only shape that can't clear the rule, fixed on `race-future` by lengthening gear 1 (see
## VARIANTS) until it stopped saturating. `_brake_report` flags anything still over its tyre;
## `test_vehicle_catalog.test_kenney_specs_keep_force_hierarchy` is the authoritative check.
func _derive_brakes(spec: VehicleSpec, gd: GroundDriveSpec, id: String) -> void:
	var peak_engine := 0.0
	var idle_engine := VehicleSpec.sample_curve(spec.torque_curve, spec.idle_rpm)
	for i in spec.torque_curve.size():
		peak_engine = maxf(peak_engine, spec.torque_curve[i].y)
	var ratio1 := spec.gear_ratios[0] * spec.final_drive
	var max_drive := peak_engine * ratio1 * spec.efficiency
	var launch_25 := idle_engine * 0.25 * ratio1 * spec.efficiency
	var wheels := maxi(gd.wheel_positions.size(), 1)
	var grip_ceiling := spec.mass * GRAVITY / wheels * gd.mu_long * gd.wheel_radius
	# Driven corners off the spec's own geometry + layout (front = -Z, same convention
	# BaseVehicle reads), so an FWD/RWD/AWD override moves this with no second list to keep.
	var driven := 0
	for p in gd.wheel_positions:
		if (p.z < 0.0 and gd.driven_front) or (p.z > 0.0 and gd.driven_rear):
			driven += 1
	# 2% over the bare minimum, so `ceilf` rounding can never land on the assertion.
	var transmissible := minf(max_drive, float(driven) * grip_ceiling)
	var hierarchy_floor := transmissible / wheels * 1.02
	gd.brake_torque = ceilf(maxf(grip_ceiling * BRAKE_GRIP_FRAC, hierarchy_floor))
	_brake_report.append("%-16s %6.0f Nm/wheel = %.2f g (tyre holds %.2f g, %d driven)%s" % [
			id, gd.brake_torque,
			gd.brake_torque * wheels / gd.wheel_radius / spec.mass / GRAVITY, gd.mu_long,
			driven, "  <-- OVER THE TYRE" if gd.brake_torque > grip_ceiling else ""])
	gd.handbrake_torque = maxf(1.0, roundf(launch_25 * 0.75))


func _scaled_curve(flat: Array, mul: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	@warning_ignore("integer_division")
	for i in flat.size() / 2:
		out.append(Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]) * mul))
	return out


# --- scene -----------------------------------------------------------------------------

func _build_scene(variant: String, scene_script: Variant, spec: VehicleSpec, geo: Dictionary) -> PackedScene:
	var box_aabb: AABB = geo["box"]   # wheel-less body, already in body space (front = -Z)

	var root := RigidBody3D.new()
	root.name = variant.to_pascal_case()
	root.set_script(scene_script)
	root.set("spec", spec)

	# Collision is hand-authored (CollisionLower/CollisionUpper box pairs) and transplanted
	# verbatim on regen rather than overwritten; only a brand-new variant gets the generated
	# convex hull as a starting point.
	var kept := _existing_children(variant)
	var kept_collision: Array = kept["collision"]
	if kept_collision.is_empty():
		var col := _body_shape(variant, geo)
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = col["shape"]
		cs.position = col["pos"]
		_add(root, root, cs)
	else:
		for cs in kept_collision:
			_add(root, root, cs)
		_shape_report.append("%s=kept(%d)" % [variant, kept_collision.size()])

	# Body model: instance the GLB, steal its non-wheel children into a Model node under the body
	# transform (180deg Y flip: Kenney +Z front -> project -Z, + kit scale + x/z centring).
	var glb := (load(MODELS.path_join(variant + ".glb")) as PackedScene).instantiate()
	var model := Node3D.new()
	model.name = "Model"
	model.transform = geo["xform"]
	_add(root, root, model)
	for child in glb.get_children():
		var lname := String(child.name).to_lower()
		if lname.begins_with("wheel") and (lname.ends_with("left") or lname.ends_with("right")):
			continue  # a driven corner wheel — RayWheel provides these
		glb.remove_child(child)
		model.add_child(child)
		_own(child, root)
	glb.free()

	_apply_body_material(model)

	_add_lamps(root, variant, box_aabb, geo["lenses"])

	# Hand-authored subsystem nodes (tractor's ThreePointHitch), added last to match editor order.
	for extra: Node in kept["extras"]:
		_add(root, root, extra)

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Painted-body finish via material_override (survives pack(), regen-owned). One shared material
## for every MeshInstance3D under Model: colormap atlas + double-sided, semi-gloss sheen
## (specular, not metal), soft rim edge-catch. No clearcoat — silent no-op under
## gl_compatibility.
func _apply_body_material(model: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "body_finish"
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = load(COLORMAP)
	mat.roughness = 0.6
	mat.metallic = 0.0
	mat.metallic_specular = 0.6
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.5
	_set_material_override(model, mat)


func _set_material_override(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_set_material_override(c, mat)


## Set owner recursively so pack() serialises the stolen GLB subtree into the vehicle scene.
func _own(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for c in node.get_children():
		_own(c, scene_owner)


## Everything in the existing scene the generator does not rebuild, kept so it survives the old
## instance being freed. A whitelist of what the generator writes (GENERATED_CHILDREN plus
## collision), not a list of what to save, so a hand-added node is preserved by default.
##
## Returns {collision, extras}: collision goes back in first (before Model), extras last (after
## Lamps), matching authored child order so a no-op regen stays byte-identical. Extras are
## reparented (not duplicated) out of an instance loaded with GEN_EDIT_STATE_INSTANCE — plain
## `duplicate()` loses scene-instance state, so `pack()` would write the hitch's properties back
## out explicitly (including `script=`), pinning the vehicle scene to today's hitch script.
## Collision shapes are plain nodes and stay a plain duplicate.
func _existing_children(variant: String) -> Dictionary:
	var kept := {"collision": [], "extras": []}
	var path := OUT_DIR.path_join(variant + ".tscn")
	if not ResourceLoader.exists(path):
		return kept
	var scene := load(path) as PackedScene
	if scene == null:
		return kept
	var inst := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	for child in inst.get_children():
		if child is CollisionShape3D:
			(kept["collision"] as Array).append(child.duplicate())
		elif not (String(child.name) in GENERATED_CHILDREN):
			(kept["extras"] as Array).append(child)
	for extra: Node in kept["extras"]:
		inst.remove_child(extra)
	inst.free()
	return kept


## Convex hull of the wheel-less body (verts clamped up to MIN_CLEARANCE for a flat floor
## above the wheel-contact plane), simplified by QuickHull. Box fallback if degenerate.
## Returns {shape, pos}. Verts already sit in body space, so pos is the origin for a hull.
func _body_shape(variant: String, geo: Dictionary) -> Dictionary:
	var xform: Transform3D = geo["xform"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for pair: Array in geo["body_pairs"]:
		var full := xform * (pair[1] as Transform3D)
		for v in (pair[0] as Mesh).get_faces():
			var p := full * v
			p.y = maxf(p.y, MIN_CLEARANCE)
			st.add_vertex(p)
			n += 1
	if n >= 12:
		var hull := (st.commit() as ArrayMesh).create_convex_shape(true, true)
		if hull != null and hull.points.size() >= 4:
			_shape_report.append("%s=hull(%d)" % [variant, hull.points.size()])
			return {"shape": hull, "pos": Vector3.ZERO}
	push_warning("%s: convex hull degenerate, falling back to box" % variant)
	_shape_report.append("%s=box" % variant)
	return _box_shape(geo)


func _box_shape(geo: Dictionary) -> Dictionary:
	var box_aabb: AABB = geo["box"]
	var box_min_y := maxf(box_aabb.position.y, MIN_CLEARANCE)
	var box_h := box_aabb.position.y + box_aabb.size.y - box_min_y
	var ctr := box_aabb.get_center()
	var box := BoxShape3D.new()
	box.size = Vector3(box_aabb.size.x, box_h, box_aabb.size.z)
	return {"shape": box, "pos": Vector3(ctr.x, box_min_y + box_h * 0.5, ctr.z)}


## Lamps subtree matching car.tscn's names/paths. Each end's lens rectangle comes from
## _find_lenses (the model's own painted lamp face), split along its width — inboard
## (1 - TURN_FRAC) is head/brake, outboard TURN_FRAC is the turn indicator (the Kenney kit paints
## no indicator of its own). Ends with no painted lamp fall back to the body-box formula below,
## whose height a variant may override via _fallback_lamp_y.
func _add_lamps(root: RigidBody3D, variant: String, box: AABB, lenses: Dictionary) -> void:
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	_add(root, root, lamps)

	var ctr := box.get_center()
	var hw := box.size.x * 0.5
	var fb_front := ctr.z - box.size.z * 0.5 * 0.98
	var fb_rear := ctr.z + box.size.z * 0.5 * 0.98
	var fb_mesh := _box_mesh(0.2, 0.12, 0.06)
	var fb_y: Dictionary = _fallback_lamp_y.get(variant, {})
	var fb_y_front := float(fb_y.get("front", ctr.y))
	var fb_y_rear := float(fb_y.get("rear", ctr.y))

	# --- front: spot light + head lens on the main part, indicator on the split-off part ---
	var f: Dictionary = lenses.get("front", {})
	if f.is_empty():
		_add(root, lamps, _spot("HeadlightL", Vector3(-hw * 0.6, fb_y_front, fb_front)))
		_add(root, lamps, _spot("HeadlightR", Vector3(hw * 0.6, fb_y_front, fb_front)))
		_pair(root, lamps, "HeadLens", Vector3(hw * 0.6, fb_y_front, fb_front), fb_mesh)
		_pair(root, lamps, "TurnLF", Vector3(hw * 0.86, fb_y_front, fb_front), fb_mesh, "TurnRF")
	else:
		var fs := _split(f, -1.0)
		var sp: Vector3 = fs["spot_pos"]
		_add(root, lamps, _spot("HeadlightL", Vector3(-sp.x, sp.y, sp.z)))
		_add(root, lamps, _spot("HeadlightR", sp))
		_pair(root, lamps, "HeadLens", fs["main_pos"], fs["main_mesh"])
		_pair(root, lamps, "TurnLF", fs["turn_pos"], fs["turn_mesh"], "TurnRF")

	# --- rear: brake lamp on the main part, indicator on the split-off part ---
	var r: Dictionary = lenses.get("rear", {})
	if r.is_empty():
		_pair(root, lamps, "BrakeLamp", Vector3(hw * 0.62, fb_y_rear, fb_rear), fb_mesh)
		_pair(root, lamps, "TurnLR", Vector3(hw * 0.86, fb_y_rear, fb_rear), fb_mesh, "TurnRR")
	else:
		var rs := _split(r, 1.0)
		_pair(root, lamps, "BrakeLamp", rs["main_pos"], rs["main_mesh"])
		_pair(root, lamps, "TurnLR", rs["turn_pos"], rs["turn_mesh"], "TurnRR")


## Split one end's right-side lens box into an inboard main lamp and an outboard indicator.
## `facing` is -1 front / +1 rear (outward normal along Z).
##
## The lamp mesh encloses the model's lens rather than resting on it: depth spans the lens' full
## z extent (Kenney lenses often wrap onto the flank, so a fixed-thickness slab left the painted
## lens showing in profile), and every outward face grows LENS_CLEAR beyond the model's so our
## surface wins the depth test unambiguously from every angle (a coincident face there
## z-fights; a render-priority/depth-bias hack would win on the end face but not the flank).
## Growth on the inboard side is free, it just buries the mesh in the chassis.
##
## The cut follows the lens shape: a wide lens splits along width (main inboard, indicator
## outboard); a tall lens (vertical clusters like the ambulance's rear corner light) splits along
## height (main on top) so the indicator still lands on real lens area. A disc lens (SUV
## headlamp) keeps its full circle as the main lamp with the indicator as a small box outboard.
##
## Returns Vector3 positions (right/+X side): main_pos, turn_pos, spot_pos, plus main_mesh /
## turn_mesh.
func _split(lens: Dictionary, facing: float) -> Dictionary:
	var b: AABB = lens["box"]
	var c := b.get_center()
	var depth := maxf(b.size.z, LENS_MIN_DEPTH) + LENS_CLEAR
	var z_face := c.z + facing * b.size.z * 0.5          # the model's outward lens plane
	var z := z_face + facing * (LENS_CLEAR - depth * 0.5)
	var spot_z := z_face + facing * 0.02

	if bool(lens["disc"]):
		var radius := minf(b.size.x, maxf(b.size.y, LENS_MIN_H)) * 0.5 + LENS_CLEAR
		var disc_turn_w := radius * 0.9
		var disc_h := maxf(b.size.y, LENS_MIN_H) * 0.7 + 2.0 * LENS_CLEAR
		# Indicator sits just OUTBOARD of the disc's rim, with a clearance gap so its inner
		# face never touches the cylinder's tangent line.
		var disc_turn_in := c.x + radius + LENS_CLEAR
		return {
			"spot_pos": Vector3(c.x, c.y, spot_z),
			"main_pos": Vector3(c.x, c.y, z), "main_mesh": _disc_mesh(radius, depth),
			"turn_pos": Vector3(disc_turn_in + disc_turn_w * 0.5, c.y, z),
			"turn_mesh": _box_mesh(disc_turn_w, disc_h, depth),
		}

	# Each half grows outward by LENS_CLEAR (buried in the chassis / proud of the body) but
	# the seam edge stays EXACT, so the two halves abut without overlapping — an overlap there
	# would put two coplanar faces in the same place and bring the z-fighting back.
	if b.size.y > b.size.x:
		# Tall lens -> split along HEIGHT: main lamp on top, indicator below, seam between.
		var w := b.size.x + 2.0 * LENS_CLEAR
		var turn_h := b.size.y * TURN_FRAC
		var main_h := b.size.y - turn_h
		var bottom := c.y - b.size.y * 0.5
		var top := c.y + b.size.y * 0.5
		var seam_y := bottom + turn_h
		var main_cy := (seam_y + top + LENS_CLEAR) * 0.5
		var turn_cy := (bottom - LENS_CLEAR + seam_y) * 0.5
		return {
			"spot_pos": Vector3(c.x, main_cy, spot_z),
			"main_pos": Vector3(c.x, main_cy, z), "main_mesh": _box_mesh(w, main_h + LENS_CLEAR, depth),
			"turn_pos": Vector3(c.x, turn_cy, z), "turn_mesh": _box_mesh(w, turn_h + LENS_CLEAR, depth),
		}

	# Wide lens -> split along WIDTH: main lamp inboard, indicator outboard, seam between.
	var h := maxf(b.size.y, LENS_MIN_H) + 2.0 * LENS_CLEAR
	var in_edge := c.x - b.size.x * 0.5
	var out_edge := c.x + b.size.x * 0.5
	var turn_w := b.size.x * TURN_FRAC
	var main_w := b.size.x - turn_w
	var seam_x := in_edge + main_w
	var main_cx := (in_edge - LENS_CLEAR + seam_x) * 0.5
	var turn_cx := (seam_x + out_edge + LENS_CLEAR) * 0.5
	return {
		"spot_pos": Vector3(main_cx, c.y, spot_z),
		"main_pos": Vector3(main_cx, c.y, z), "main_mesh": _box_mesh(main_w + LENS_CLEAR, h, depth),
		"turn_pos": Vector3(turn_cx, c.y, z), "turn_mesh": _box_mesh(turn_w + LENS_CLEAR, h, depth),
	}


func _box_mesh(w: float, h: float, depth: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, depth)
	return m


## Cylinder laid on its side so the circular face points down Z (CylinderMesh's axis is +Y).
func _disc_mesh(radius: float, depth: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = depth
	m.radial_segments = 12
	m.rings = 0
	return m


## Add a mirrored mesh pair. `pos` is the RIGHT-side position; the left one is its mirror.
## Naming follows the existing paths: "HeadLens"/"BrakeLamp" take an L/R suffix, while the
## turn lenses are already fully named (TurnLF + TurnRF), so pass both.
func _pair(scene_owner: Node, parent: Node, right_name: String, pos: Vector3, mesh: Mesh,
		left_name := "") -> void:
	var l_name := right_name + "L" if left_name.is_empty() else right_name
	var r_name := right_name + "R" if left_name.is_empty() else left_name
	_add(scene_owner, parent, _lens(l_name, Vector3(-pos.x, pos.y, pos.z), mesh))
	_add(scene_owner, parent, _lens(r_name, pos, mesh))


func _spot(spot_name: String, pos: Vector3) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.name = spot_name
	s.position = pos
	s.visible = false
	s.light_energy = 0.0
	s.spot_range = 28.0
	s.spot_angle = 38.0
	return s


func _lens(lens_name: String, pos: Vector3, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = lens_name
	mi.position = pos
	mi.mesh = mesh
	if mesh is CylinderMesh:
		mi.basis = Basis(Vector3.RIGHT, PI * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _add(scene_owner: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner


# --- geometry --------------------------------------------------------------------------

## Analyse a Kenney vehicle GLB into geometry the spec/scene builders share:
##   xform:     body-model transform — 180deg Y flip (Kenney +Z front -> project -Z) + kit
##              scale + x/z centring on the body, native y = 0 kept (the wheel-contact plane)
##   wheel_xz:  the four wheels' body-space (x, z). z is the Kenney wheel z; x is the flush
##              rule below (never inset from the authored position).
##   body_pairs: [Mesh, native transform] for the wheel-less body (collision hull source)
##   box:       body_aabb transformed by xform (lamp placement + hull fallback)
func _analyze(path: String, wheel_models: Array) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("cannot load " + path)
		return {}
	var inst := scene.instantiate()
	var body_pairs: Array = []
	var wheels: Array = []
	_collect_body_wheels(inst, Transform3D.IDENTITY, body_pairs, wheels)
	inst.free()
	if body_pairs.is_empty() or wheels.size() != 4:
		push_error("%s: body meshes=%d, wheel nodes=%d (expected 4)" %
				[path, body_pairs.size(), wheels.size()])
		return {}

	# Native body verts + AABB (AABB centre drives the x/z centring in xform).
	var bverts := PackedVector3Array()
	var body_aabb := AABB()
	var first := true
	for pair: Array in body_pairs:
		for v in (pair[0] as Mesh).get_faces():
			var wpt: Vector3 = (pair[1] as Transform3D) * v
			bverts.append(wpt)
			if first:
				body_aabb = AABB(wpt, Vector3.ZERO)
				first = false
			else:
				body_aabb = body_aabb.expand(wpt)

	var c := body_aabb.get_center()
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * KIT_SCALE)
	var xform := Transform3D(basis, Vector3(KIT_SCALE * c.x, 0.0, KIT_SCALE * c.z))

	# Per-wheel flush X: place the wheel's OUTER face at the body side measured in a z-band
	# around that wheel (fenders differ front/rear), i.e. |x| = body_half - wheel_half. The
	# tread half-width is per axle, since the two axles may wear different models (tractor).
	# Never pull a wheel inward from where Kenney put it (open-wheel cars sit proud of a slim
	# body): take max(flush, authored). The embedded wheel z is kept as-is.
	var wheel_xz: Array = []
	for w: Vector3 in wheels:
		var tw: Vector3 = xform * w
		var body_half := 0.0
		for v in bverts:
			var tv: Vector3 = xform * v
			if absf(tv.z - tw.z) < WHEEL_BAND:
				body_half = maxf(body_half, absf(tv.x))
		var half: float = wheel_models[0 if tw.z < 0.0 else 1]["half"]
		var flush := body_half - half
		var x := signf(tw.x) * maxf(flush, absf(tw.x))
		wheel_xz.append(Vector2(x, tw.z))

	var box := _xform_aabb(body_aabb, xform)
	var variant := path.get_file().get_basename()
	var lenses := _find_lenses(body_pairs, xform, box)
	for end: String in _lens_overrides.get(variant, {}):
		var o: Array = _lens_overrides[variant][end]
		var size: Vector3 = o[1]
		lenses[end] = {"box": AABB((o[0] as Vector3) - size * 0.5, size), "disc": false}
	_lens_report.append("%-16s front %s  rear %s" %
			[variant, _lens_line(lenses.get("front", {})),
			_lens_line(lenses.get("rear", {}))])
	return {"xform": xform, "wheel_xz": wheel_xz, "body_pairs": body_pairs, "box": box,
			"lenses": lenses}


func _lens_line(lens: Dictionary) -> String:
	if lens.is_empty():
		return "%-34s" % "fallback"
	var b: AABB = lens["box"]
	var c := b.get_center()
	return "%s (%+.3f,%+.3f,%+.3f) %.2fx%.2f" % [
			"disc" if lens["disc"] else "box ", c.x, c.y, c.z, b.size.x, b.size.y]


## Locate each end's lamp lens by reading the model's own texturing. The Kenney kit is one
## merged mesh per vehicle from a single colormap atlas, so a lens is the run of triangles whose
## UV lands on the lamp swatches (amber front, red rear): sample the atlas per triangle
## centroid, union triangles sharing a welded vertex and atlas shade, keep lens-shaped clusters
## (small, off centreline, at an end face), then merge survivors that touch (one lens spans
## several shades). Filtering before merging stops a lens fusing into a same-hue body panel
## (firetruck is red all over) while still rejoining a lens split by its own gradient.
##
## Returns {front: {box, disc}, rear: {box, disc}} — box is the right-side (+X) lens; a missing
## key means that end has no painted lamp.
func _find_lenses(body_pairs: Array, xform: Transform3D, box: AABB) -> Dictionary:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(COLORMAP)) != OK:
		push_error("cannot load " + COLORMAP)
		return {}

	var tris: Array = []  # [a, b, c, Color]
	for pair: Array in body_pairs:
		var mesh: Mesh = pair[0]
		var xf: Transform3D = xform * (pair[1] as Transform3D)
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if uvs.is_empty():
				continue
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			for i in range(0, idx.size(), 3):
				var i0 := idx[i]
				var i1 := idx[i + 1]
				var i2 := idx[i + 2]
				var uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
				var px := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
				var py := clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)
				tris.append([xf * verts[i0], xf * verts[i1], xf * verts[i2],
						img.get_pixel(px, py)])

	# Union triangles sharing a welded vertex at the same atlas shade.
	var parent := PackedInt32Array()
	parent.resize(tris.size())
	for i in tris.size():
		parent[i] = i
	var seen := {}
	for i in tris.size():
		var col: Color = tris[i][3]
		var shade := "%d_%d_%d" % [int(col.r * 12), int(col.g * 12), int(col.b * 12)]
		for k in 3:
			var v: Vector3 = tris[i][k]
			var key := "%s|%d,%d,%d" % [shade, roundi(v.x / LENS_WELD),
					roundi(v.y / LENS_WELD), roundi(v.z / LENS_WELD)]
			if seen.has(key):
				_union(parent, i, int(seen[key]))
			else:
				seen[key] = i

	var clusters := {}
	for i in tris.size():
		var root := _find(parent, i)
		if not clusters.has(root):
			clusters[root] = [AABB(tris[i][0], Vector3.ZERO), 0, tris[i][3]]
		var e: Array = clusters[root]
		var b: AABB = e[0]
		for k in 3:
			b = b.expand(tris[i][k])
		e[0] = b
		e[1] = int(e[1]) + 1

	# Lens-shaped survivors, then merge the ones that touch.
	var cand: Array = []  # [AABB, tri count, family]
	for root: int in clusters:
		var e: Array = clusters[root]
		var b: AABB = e[0]
		var fam := _lens_family(e[2])
		if fam == "":
			continue
		if b.size.x > 0.55 or b.size.y > 0.40 or b.size.z > 0.45:
			continue
		if absf(b.get_center().x) < 0.10:
			continue
		if absf(b.get_center().z) < box.size.z * 0.5 - 0.75:
			continue
		if fam == "white" and b.size.x * b.size.y > 0.10:
			continue
		cand.append([b, int(e[1]), fam])
	_merge_touching(cand)

	return {"front": _pick_lens(cand, -1.0), "rear": _pick_lens(cand, 1.0)}


## Best mirrored lens pair on one end (-1 front / +1 rear), as {box, disc} for the +X side.
## Front lamps are painted amber (the kit's clear-lens swatch), rear red; white is only ever
## a front fallback. Ties go to the largest lens face.
func _pick_lens(cand: Array, facing: float) -> Dictionary:
	for fam: String in (["red"] if facing > 0.0 else ["amber", "white"]):
		var best: Array = []
		for a: Array in cand:
			var ba: AABB = a[0]
			if a[2] != fam or signf(ba.get_center().z) != facing or ba.get_center().x <= 0.0:
				continue
			# Require the mirror twin — a lamp is always a pair, stray livery rarely is.
			var mirrored := false
			for b: Array in cand:
				var bb: AABB = b[0]
				if b[2] != fam or bb.get_center().x >= 0.0:
					continue
				if absf(bb.get_center().x + ba.get_center().x) < 0.05 \
						and absf(bb.get_center().y - ba.get_center().y) < 0.05 \
						and absf(bb.get_center().z - ba.get_center().z) < 0.08:
					mirrored = true
					break
			if not mirrored:
				continue
			if best.is_empty() or ba.size.x * ba.size.y > (best[0] as AABB).size.x * (best[0] as AABB).size.y:
				best = a
		if not best.is_empty():
			var bb2: AABB = best[0]
			var disc := int(best[1]) >= DISC_MIN_TRIS and absf(bb2.size.x - bb2.size.y) < 0.03
			return {"box": bb2, "disc": disc}
	return {}


## Coarse hue family of an atlas sample; "" = not a lamp swatch.
func _lens_family(c: Color) -> String:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	if mx < 0.55:
		return ""
	# The kit's clear-lens swatch is a faintly blue white (#d4ecff on the tractors), so the
	# neutral band has to be wide enough to catch it; the size/position filters upstream are
	# what keep glass and pale body panels out.
	if mx - mn < 0.22:
		return "white" if mx > 0.88 else ""
	if c.r > 0.6 and c.g < 0.45 and c.b < 0.45:
		return "red"
	if c.r > 0.85 and c.g > 0.40 and c.g < 0.92 and c.b < 0.50:
		return "amber"
	return ""


## In-place merge of same-family candidates whose boxes touch within LENS_MERGE_GAP.
func _merge_touching(cand: Array) -> void:
	var merged := true
	while merged:
		merged = false
		for i in cand.size():
			for j in range(i + 1, cand.size()):
				if cand[i][2] != cand[j][2]:
					continue
				if not (cand[i][0] as AABB).grow(LENS_MERGE_GAP).intersects(cand[j][0]):
					continue
				cand[i][0] = (cand[i][0] as AABB).merge(cand[j][0])
				cand[i][1] = int(cand[i][1]) + int(cand[j][1])
				cand.remove_at(j)
				merged = true
				break
			if merged:
				break


func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	while parent[i] != r:
		var n := parent[i]
		parent[i] = r
		i = n
	return r


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## Collect body mesh pairs and wheel-node centres. The four driven wheels are the corner
## nodes `wheel-{front,back}-{left,right}`; a bare `wheel-back` etc. is the SUV's spare tyre —
## real body geometry, so it is NOT treated as a wheel (kept in the model, no RayWheel).
func _collect_body_wheels(node: Node, xform: Transform3D, body_pairs: Array, wheels: Array) -> void:
	var nx := xform
	if node is Node3D:
		nx = xform * (node as Node3D).transform
	var lname := String(node.name).to_lower()
	if lname.begins_with("wheel") and (lname.ends_with("left") or lname.ends_with("right")):
		wheels.append(nx.origin)
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		body_pairs.append([(node as MeshInstance3D).mesh, nx])
	for child in node.get_children():
		_collect_body_wheels(child, nx, body_pairs, wheels)


## Body-space z of the centre of mass, from the recipe's `front_weight` where it declares one
## (`com_z` where it states the offset directly, 0 where it says nothing). Measured off THIS
## body's own axle line, so the same declared split means the same handling on every wheelbase.
func _com_z(geo: Dictionary, ov: Dictionary) -> float:
	if not ov.has("front_weight"):
		return float(ov.get("com_z", 0.0))
	var front_z := INF
	var rear_z := -INF
	for xz: Vector2 in geo["wheel_xz"]:
		front_z = minf(front_z, xz.y)   # front = -Z
		rear_z = maxf(rear_z, xz.y)
	var front := clampf(float(ov["front_weight"]), 0.05, 0.95)
	return front_z + (1.0 - front) * (rear_z - front_z)


## AABB of `aabb` after `xform` (8 corners; xform is rotation+uniform-scale+translation).
func _xform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var out := AABB(xform * aabb.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xform * (aabb.position + Vector3(
				aabb.size.x if (i & 1) else 0.0,
				aabb.size.y if (i & 2) else 0.0,
				aabb.size.z if (i & 4) else 0.0)))
	return out


# --- stable save (strip churny per-node unique_id, like gen_kit_assets) ----------------

var _unique_id_re := RegEx.create_from_string(" unique_id=\\d+")
## Godot re-rolls the 5-character suffix of every generated sub-resource id on each save
## (`StandardMaterial3D_l7l2h` -> `StandardMaterial3D_lei3o`).
var _subres_id_re := RegEx.create_from_string("\\b([A-Za-z0-9]+)_([a-z0-9]{5})\\b")


## A scene's content minus the three things a re-save churns for free: per-node `unique_id`,
## sub-resource ID suffixes, and line endings (git checks out CRLF, ResourceSaver writes LF, so
## a raw byte compare calls every file changed). Sub-resource IDs are renumbered by order of
## first appearance rather than blanked, so a genuine edit that repoints a node at a different
## sub-resource of the same type still reads as a change (a real insertion shifts every later
## number — errs toward reporting a difference, the safe direction).
func _churn_key(text: String) -> String:
	var flat := _unique_id_re.sub(text.replace("\r\n", "\n"), "", true)
	var seen := {}
	var out := ""
	var cursor := 0
	for m in _subres_id_re.search_all(flat):
		out += flat.substr(cursor, m.get_start() - cursor)
		cursor = m.get_end()
		var token := m.get_string()
		if not seen.has(token):
			seen[token] = "%s_ID%d" % [m.get_string(1), seen.size()]
		out += String(seen[token])
	return out + flat.substr(cursor)


## The ` uid="uid://..."` attribute of a .tres/.tscn header line, "" if it carries none.
func _header_uid(text: String) -> String:
	var head_end := text.find("]")
	var at := text.find(" uid=\"uid://")
	if head_end < 0 or at < 0 or at > head_end:
		return ""
	var close := text.find("\"", at + 6)
	if close < 0 or close > head_end:
		return ""
	return text.substr(at, close - at + 1)


var _ext_res_re := RegEx.create_from_string("\\[ext_resource [^\\]]*\\]")
var _uid_attr_re := RegEx.create_from_string(" uid=\"uid://[^\"]*\"")
var _path_attr_re := RegEx.create_from_string(" path=\"([^\"]*)\"")


## `res://…` -> ` uid="uid://…"` for every `[ext_resource]` line in `text` that carries both.
func _ext_resource_uids(text: String) -> Dictionary:
	var out := {}
	for m in _ext_res_re.search_all(text):
		var line := m.get_string()
		var u := _uid_attr_re.search(line)
		var pa := _path_attr_re.search(line)
		if u != null and pa != null:
			out[pa.get_string(1)] = u.get_string()
	return out


## Re-inject the UIDs `after` lost relative to `before` (header + every `[ext_resource]`,
## matched by resource path). ResourceSaver only writes a `uid=` it can see, so a plain save
## silently strips one whenever the source resource carries none in memory — a broken reference
## the moment a path moves, and a no-op regen turned into an 18-file diff.
func _restore_uids(before: String, after: String) -> String:
	if before.is_empty():
		return after
	var out := after
	var head_uid := _header_uid(before)
	if not head_uid.is_empty() and _header_uid(out).is_empty():
		var head_end := out.find("]")
		if head_end >= 0:
			out = out.insert(head_end, head_uid)
	var want := _ext_resource_uids(before)
	if want.is_empty():
		return out
	var rebuilt := ""
	var cursor := 0
	for m in _ext_res_re.search_all(out):
		var line := m.get_string()
		rebuilt += out.substr(cursor, m.get_start() - cursor)
		cursor = m.get_end()
		if _uid_attr_re.search(line) == null:
			var pa := _path_attr_re.search(line)
			if pa != null and want.has(pa.get_string(1)):
				line = line.insert(pa.get_start(), String(want[pa.get_string(1)]))
		rebuilt += line
	return rebuilt + out.substr(cursor)


## Save a spec, keeping the UIDs the file already had (see `_restore_uids`).
func _save_spec_stable(spec: Resource, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(spec, path)
	if err != OK or before.is_empty():
		return err
	var after := _restore_uids(before, FileAccess.get_file_as_string(path))
	if _churn_key(after) == _churn_key(before):
		after = before   # unchanged: keep the on-disk line endings too
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(after)
	return OK


func _save_scene_stable(packed: PackedScene, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(packed, path)
	if err != OK or before.is_empty():
		return err
	var after := _restore_uids(before, FileAccess.get_file_as_string(path))
	if _churn_key(after) == _churn_key(before):
		after = before
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(after)
	return OK
