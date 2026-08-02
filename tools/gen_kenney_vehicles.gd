extends Node
## One-shot generator for the Kenney car-kit vehicle variants (CC0). For each variant it
## writes src/vehicles/kenney/<variant>.tscn + <variant>_spec.tres:
##   - a RigidBody3D root carrying the family's vehicle script (FAMILY_SCRIPTS: TruckVehicle for
##     the truck family, TractorVehicle for the tractor, plain BaseVehicle for cars/vans),
##   - the GLB body instanced + centred at the kit-wide scale, a BoxShape3D from its AABB,
##   - a shared Lamps subtree (same node names/paths as car.tscn) sized to the body,
##   - a spec whose feel starts from the family baseline + per-variant overrides; wheels
##     come from spec.wheel_scene (the shared Kenney wheel wrapper) at runtime.
##
## brake_torque / handbrake_torque are DERIVED from each variant's drivetrain so the §6
## force hierarchy (brake > peak drive per wheel > handbrake, handbrake capped low) holds
## by construction for every generated spec — never hand-tuned.
##
## GAME-MODE tool scene, NOT --script: base_vehicle.gd / tractor.gd reference the
## InputRouter / Bridge autoloads, which only resolve with autoloads registered. Run:
##   godot --headless --path . res://tools/gen_kenney_vehicles.tscn
## Deterministic + destructive-by-run. Delete tools/measure_kenney.gd after; this stays as
## the regen path (rerun after a scale/feel change, then re-bake).

const OUT_DIR := "res://src/vehicles/kenney"
const MODELS := OUT_DIR + "/models"
const BASE_SCRIPT := "res://src/vehicles/base/base_vehicle.gd"
const TRACTOR_SCRIPT := "res://src/vehicles/tractor/tractor.gd"
const TRUCK_SCRIPT := "res://src/vehicles/truck/truck.gd"
## Vehicle script per CONTRACT family; anything unlisted gets plain BaseVehicle. Keying on the
## family is what makes this correct rather than a per-variant flag: garbage-truck and firetruck
## are family "truck" and both need the J1939 chassis, while the heavy vans DRIVE like trucks but
## are family "car" (ordinary chassis, proprietary CAN) and must keep base_vehicle.gd.
const FAMILY_SCRIPTS := {"tractor": TRACTOR_SCRIPT, "truck": TRUCK_SCRIPT}

const KIT_SCALE := 1.2
## The direct children this generator writes itself, i.e. the ONLY ones a regen may replace.
## Anything else the scene carries is hand-authored and is transplanted — see _existing_children.
## That covers the collision box pair, the tractor's ThreePointHitch, and the hand-placed
## "HoodCam" marker (the bonnet-cam seat; ChaseCamera falls back silently without it, so its
## loss reads as drift rather than as a missing node — test_vehicle_catalog sweeps for it).
const GENERATED_CHILDREN := ["Model", "Lamps"]
const COLORMAP := OUT_DIR + "/models/Textures/colormap.png"

## --- lamp-lens detection (see _find_lenses) -------------------------------------------
const LENS_WELD := 0.001       ## m, vertex weld tolerance for the triangle union-find
const LENS_MERGE_GAP := 0.02   ## m two lens fragments may be apart and still be one lens
## The lamp mesh does not sit ON the model's lens, it ENCLOSES it: every outward face is
## held this far outside the corresponding lens face. Two problems, one fix — see _split.
const LENS_CLEAR := 0.006
const LENS_MIN_DEPTH := 0.04   ## m depth floor for a lens the model draws as a flat quad
const LENS_MIN_H := 0.06       ## m floor on lens height (some are a single flat quad)
const TURN_FRAC := 0.35        ## outboard share of a lens' width that becomes the indicator
const DISC_MIN_TRIS := 12      ## a lens this dense with square extents is a disc, not a box
const WHEEL_RADIUS := 0.36  ## physics radius, all four corners (RayWheel is single-radius)
const GRAVITY := 9.8
const MIN_CLEARANCE := 0.12  ## m the collision hull floor is held above the wheel-contact plane
const WHEEL_BAND := 0.4   ## m z-window (body space) the body half-width is measured over per axle

## Wheel visuals per model: the radius-normalized scene, the rendered radius, and the tread
## half-width AT that radius (native half-width / native radius * rendered radius) — the flush-X
## rule below places the wheel's outer face at the body side, so it must match the model.
const WHEEL_DEFAULT := {"scene": OUT_DIR + "/wheel.tscn", "radius": WHEEL_RADIUS, "half": 0.240}
const WHEEL_TRUCK := {"scene": OUT_DIR + "/wheel-truck.tscn", "radius": WHEEL_RADIUS, "half": 0.210}
## Tractor axles differ VISUALLY only (0.30 / 0.45 straddling the 0.36 physics radius).
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
## Hand-measured lens boxes [centre, size] for the few models where the atlas swatch is too
## close to the body colour for detection to find the edge — the taxi's amber lamp sits on
## amber bodywork, so the cluster over-reaches downward and must be cropped to the real lens.
## Replaces whatever _find_lenses returned for that end.
var _lens_overrides := {
	# Detection returns the whole 0.36-tall yellow region (y 0.60..0.96); the real lamp is
	# the strip at the TOP of it, so the top edge stays pinned at 0.96 and the height was
	# set by eye against the model.
	"taxi": {"front": [Vector3(0.495, 0.90, -1.53), Vector3(0.33, 0.12, 0.0)]},
	# The tail lamp is a thin VERTICAL red stripe on the back face, outboard (x=0.72) at door
	# height (y~0.72). Detection kept picking the centred cross livery instead; measured off
	# the model's back-face red band. Tall -> indicator splits off at the bottom.
	"ambulance": {"rear": [Vector3(0.72, 0.72, 1.84), Vector3(0.12, 0.44, 0.10)]},
	# The open-wheelers paint NO lamp swatch, so detection returns nothing and the body-box
	# fallback floated the lamps well above/outside the slim nose+tail (the box is dominated by
	# the wide rear wing and tall roll hoop). These boxes are measured off the model's own nose
	# cone and tail bodywork (see tools/measure_race.gd), so _split lands the lamps on real
	# geometry. Wide -> head/brake inboard, indicator outboard.
	"race": {
		"front": [Vector3(0.20, 0.22, -1.38), Vector3(0.26, 0.13, 0.12)],
		"rear": [Vector3(0.16, 0.40, 1.30), Vector3(0.22, 0.14, 0.12)],
	},
	"race-future": {
		"front": [Vector3(0.28, 0.31, -1.42), Vector3(0.32, 0.14, 0.14)],
		"rear": [Vector3(0.34, 0.50, 1.42), Vector3(0.34, 0.16, 0.14)],
	},
}
## Lamp height for an end with NO painted lens, where the body-box centre the fallback formula
## uses is not where the lamp belongs. variant -> {front?: y, rear?: y}, body space.
## The tractor's rear box centre lands the lamps too low (verified by driving); 1.22 is the
## shipped height, kept here so a regen reproduces it instead of re-deriving the wrong one — the
## box centre is a guess for a body whose rear end is mostly open frame between the big wheels.
var _fallback_lamp_y := {"tractor-kenney": {"rear": 1.22}}
var _shape_report: Array = []  ## per-variant collision shape kind + hull vertex count
var _lens_report: Array = []   ## per-variant lens detection, so a bad lamp is diagnosable

# --- family baselines (spec fields; brake/handbrake are derived, not listed) -----------
const CAR_BASE := {
	"mass": 1150.0, "com_y": 0.20, "spring_rate": 22000.0, "damper_bump": 1800.0,
	"damper_rebound": 2400.0, "max_suspension_force": 30000.0, "rest_length": 0.28,
	"wheel_inertia": 1.2, "driven_front": true, "driven_rear": true,
	"mu_long": 1.05, "mu_lat": 1.1, "handbrake_grip": 0.45,
	"torque_curve": [900, 150, 2000, 235, 3200, 285, 4800, 290, 6000, 255, 6800, 100],
	"idle_rpm": 900.0, "redline_rpm": 6800.0,
	"gear_ratios": [3.5, 2.2, 1.55, 1.18, 0.88, 0.66], "reverse_ratio": 2.2,
	"final_drive": 3.9, "efficiency": 0.9, "shift_up_rpm": 5600.0, "shift_down_rpm": 2200.0,
	"max_steer_deg": 38.0, "steer_speed": 7.0,
}
const TRUCK_BASE := {
	"mass": 4000.0, "com_y": 0.30, "spring_rate": 65000.0, "damper_bump": 5000.0,
	"damper_rebound": 7000.0, "max_suspension_force": 90000.0, "rest_length": 0.32,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	# J1939 driveline: the truck is the only family carrying an auxiliary retarder on the driven
	# axle. Regenerating a spec without this would silently kill the retarder, so it lives in the
	# recipe and not only in the .tres — the same rule the tractor's two flags follow.
	"retarder_equipped": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	"torque_curve": [700, 400, 1200, 650, 1800, 800, 2400, 780, 2800, 600, 3200, 200],
	"idle_rpm": 700.0, "redline_rpm": 3200.0,
	"gear_ratios": [6.5, 3.7, 2.4, 1.6, 1.2, 1], "reverse_ratio": 6.0,
	"final_drive": 4.5, "efficiency": 0.9, "shift_up_rpm": 2600.0, "shift_down_rpm": 1200.0,
	"max_steer_deg": 26.0, "steer_speed": 2.0,
}
## Heavy vans (delivery / delivery-flat / ambulance). They are `car`-FAMILY — ordinary chassis on
## proprietary CAN, not J1939 — but they DRIVE like the trucks they used to be, so they keep the
## truck chassis feel: this is TRUCK_BASE's numbers as of the family move, snapshotted rather than
## aliased ON PURPOSE. TRUCK_BASE is where J1939-only driveline flags land (a retarder is not van
## equipment), so the two baselines have to be free to diverge.
const VAN_BASE := {
	"mass": 4000.0, "com_y": 0.30, "spring_rate": 65000.0, "damper_bump": 5000.0,
	"damper_rebound": 7000.0, "max_suspension_force": 90000.0, "rest_length": 0.32,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	"torque_curve": [700, 400, 1200, 650, 1800, 800, 2400, 780, 2800, 600, 3200, 200],
	"idle_rpm": 700.0, "redline_rpm": 3200.0,
	"gear_ratios": [6.5, 3.7, 2.4, 1.6, 1.2, 1], "reverse_ratio": 6.0,
	"final_drive": 4.5, "efficiency": 0.9, "shift_up_rpm": 2600.0, "shift_down_rpm": 1200.0,
	"max_steer_deg": 26.0, "steer_speed": 2.0,
}
const TRACTOR_BASE := {
	"mass": 4200.0, "com_y": 0.35, "spring_rate": 70000.0, "damper_bump": 6000.0,
	"damper_rebound": 8000.0, "max_suspension_force": 110000.0, "rest_length": 0.35,
	"wheel_inertia": 4.0, "driven_front": false, "driven_rear": true,
	# ISOBUS driveline: the tractor is the only family whose diff locks and whose front axle
	# engages at runtime. Regenerating a spec without these would silently kill diff_lock /
	# fwd_drive, so they live in the recipe, not only in the .tres.
	"rear_diff_lockable": true, "front_axle_engageable": true,
	"mu_long": 1.0, "mu_lat": 0.95, "handbrake_grip": 1.0,
	"torque_curve": [800, 550, 1200, 680, 1600, 700, 2000, 640, 2400, 480, 2600, 300],
	"idle_rpm": 800.0, "redline_rpm": 2600.0,
	"gear_ratios": [7, 4.2, 2.8, 1.9, 1.4, 1.1], "reverse_ratio": 7.0,
	"final_drive": 5.5, "efficiency": 0.9, "shift_up_rpm": 2200.0, "shift_down_rpm": 1000.0,
	"max_steer_deg": 38.0, "steer_speed": 1.8,
}

# variant id -> { family, base?, torque_mul?, <spec field overrides...> }
# `family` is the CONTRACT family (must match VehicleCatalog) and picks both the feel baseline
# and the vehicle script (FAMILY_SCRIPTS); `base` names the feel BASELINE when it differs from
# the family — the heavy vans are car-family but keep the van chassis feel. A driveline flag
# (rear_diff_lockable / front_axle_engageable / retarder_equipped) may be overridden PER VARIANT
# here as well as declared in the baseline.
const VARIANTS := {
	# car family
	"sedan": {"family": "car"},
	"sedan-sports": {"family": "car", "mass": 1050.0, "torque_mul": 1.12, "final_drive": 4.1, "max_steer_deg": 40.0},
	"hatchback-sports": {"family": "car", "mass": 1000.0, "torque_mul": 1.10, "final_drive": 4.2, "max_steer_deg": 42.0},
	"suv": {"family": "car", "mass": 1500.0, "torque_mul": 1.05, "mu_lat": 1.0, "max_steer_deg": 34.0},
	"suv-luxury": {"family": "car", "mass": 1600.0, "torque_mul": 1.10, "mu_lat": 1.0, "max_steer_deg": 33.0},
	"taxi": {"family": "car", "mass": 1250.0},
	"police": {"family": "car", "mass": 1300.0, "torque_mul": 1.18, "final_drive": 4.0, "max_steer_deg": 40.0},
	# Open-wheelers keep the default rim and stand proud of the slim body (F1 track width).
	# `wheel_x_out` is MEASURED against each body's own half-width at the wheel stations, not
	# shared: the wheel is 0.24 half-thick, and at the kit's authored 0.42 half-track it sank
	# 0.36 into race-future's 0.66-wide bodywork (0.12 into race's 0.42) with only the outer rim
	# showing. These leave ~0.03 of rim still overlapping, so the wheel reads as exposed without
	# the full 1.86 m F1 track. Widening the track also steadies the car in corners — re-drive
	# after a change rather than treating it as a cosmetic number.
	"race": {"family": "car", "mass": 900.0, "torque_mul": 1.35, "final_drive": 4.2, "mu_long": 1.2, "mu_lat": 1.3, "max_steer_deg": 40.0, "handbrake_grip": 0.5, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.21},
	"race-future": {"family": "car", "mass": 850.0, "torque_mul": 1.42, "final_drive": 4.2, "mu_long": 1.25, "mu_lat": 1.35, "max_steer_deg": 42.0, "handbrake_grip": 0.5, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.36},
	"van": {"family": "car", "mass": 1600.0, "max_steer_deg": 32.0},
	"pickup": {"family": "car", "mass": 1550.0, "torque_mul": 1.05, "max_steer_deg": 33.0},
	"pickup-flat": {"family": "car", "mass": 1500.0, "torque_mul": 1.05, "max_steer_deg": 33.0},
	# heavy vans: car family, van feel (see VAN_BASE) — NOT CAR_BASE, they are 4-5 t vehicles
	"delivery": {"family": "car", "base": "van", "mass": 4200.0},
	"delivery-flat": {"family": "car", "base": "van", "mass": 4000.0},
	"ambulance": {"family": "car", "base": "van", "mass": 4800.0, "torque_mul": 1.1, "max_steer_deg": 24.0},
	# truck family (J1939) — garbage-truck first, matching VehicleCatalog's cycle order
	"garbage-truck": {"family": "truck", "mass": 8000.0, "torque_mul": 1.3, "max_steer_deg": 22.0, "steer_speed": 1.6},
	"firetruck": {"family": "truck", "mass": 7500.0, "torque_mul": 1.3, "max_steer_deg": 22.0, "steer_speed": 1.6},
	# tractor family (ISOBUS) — one drivable body
	"tractor-kenney": {"family": "tractor", "mass": 4000.0},
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
		var spec := _build_spec(String(ov.get("base", family)), ov, geo, wheels)
		var spec_path := OUT_DIR.path_join(variant + "_spec.tres")
		if ResourceSaver.save(spec, spec_path) != OK:
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
	spec.mass = get_f.call("mass")
	spec.center_of_mass = Vector3(0, float(b["com_y"]), 0)
	spec.wheel_radius = WHEEL_RADIUS
	spec.wheel_inertia = float(b["wheel_inertia"])
	# Wheel visuals: one scene per axle when they differ (tractor), plus the rendered radii.
	# Physics stays single-radius — spec.wheel_radius above is the only radius RayWheel uses.
	var front_wheel: Dictionary = wheels[0]
	var rear_wheel: Dictionary = wheels[1]
	spec.wheel_scene = load(String(front_wheel["scene"])) as PackedScene
	if String(rear_wheel["scene"]) != String(front_wheel["scene"]):
		spec.wheel_scene_rear = load(String(rear_wheel["scene"])) as PackedScene
	var front_r := float(front_wheel["radius"])
	var rear_r := float(rear_wheel["radius"])
	# Left at 0 (= wheel_radius) only when both axles render at the physics radius; otherwise
	# both are set explicitly, since the rear field falls back to the front one when unset.
	if front_r != WHEEL_RADIUS or rear_r != WHEEL_RADIUS:
		spec.wheel_visual_radius = front_r
		spec.wheel_visual_radius_rear = rear_r
	spec.driven_front = bool(b["driven_front"])
	spec.driven_rear = bool(b["driven_rear"])
	# Driveline capability flags, off unless something declares them. The per-variant override is
	# consulted FIRST and the baseline is the fallback. Reading the baseline alone — which is what
	# this did — makes a per-variant flag silently impossible: a VARIANTS entry could set one and
	# the generator would drop it without a word. Every variant shipping today happens to take its
	# flags from the baseline, so nothing here exercises the override yet; it is fixed now because
	# a flag that is quietly ignored is the kind of gap found the hard way.
	spec.rear_diff_lockable = get_flag.call("rear_diff_lockable")
	spec.front_axle_engageable = get_flag.call("front_axle_engageable")
	spec.retarder_equipped = get_flag.call("retarder_equipped")
	spec.rest_length = float(b["rest_length"])
	spec.spring_rate = float(b["spring_rate"])
	spec.damper_bump = float(b["damper_bump"])
	spec.damper_rebound = float(b["damper_rebound"])
	spec.max_suspension_force = float(b["max_suspension_force"])
	spec.grip_curve = _grip_curve.duplicate()
	spec.mu_long = get_f.call("mu_long")
	spec.mu_lat = get_f.call("mu_lat")
	spec.handbrake_grip = get_f.call("handbrake_grip")

	var torque_mul := float(ov.get("torque_mul", 1.0))
	spec.torque_curve = _scaled_curve(b["torque_curve"], torque_mul)
	spec.idle_rpm = float(b["idle_rpm"])
	spec.redline_rpm = float(b["redline_rpm"])
	spec.gear_ratios = PackedFloat32Array(b["gear_ratios"])
	spec.reverse_ratio = float(b["reverse_ratio"])
	spec.final_drive = get_f.call("final_drive")
	spec.efficiency = float(b["efficiency"])
	spec.shift_up_rpm = float(b["shift_up_rpm"])
	spec.shift_down_rpm = float(b["shift_down_rpm"])
	spec.max_steer_deg = get_f.call("max_steer_deg")
	spec.steer_speed = get_f.call("steer_speed")

	spec.wheel_positions = _wheel_positions(geo, spec, float(ov.get("wheel_x_out", 0.0)))
	_derive_brakes(spec)

	spec.headlight_paths.assign(_lamp_paths["headlight_paths"])
	spec.head_lamp_paths.assign(_lamp_paths["head_lamp_paths"])
	spec.brake_lamp_paths.assign(_lamp_paths["brake_lamp_paths"])
	spec.turn_left_paths.assign(_lamp_paths["turn_left_paths"])
	spec.turn_right_paths.assign(_lamp_paths["turn_right_paths"])
	return spec


## FL, FR, RL, RR hub anchors placed at the Kenney model's own wheel positions (x/z from
## each `wheel-*` node, transformed into body space), so the RayWheel visuals sit exactly in
## the wheel wells. Anchor Y is uniform across the four so the body rests level: at spring
## equilibrium the visual wheel centre lands at WHEEL_RADIUS above ground (ground at body
## y = 0, the Kenney wheel-contact plane), i.e. wheels flush with the chassis as designed.
## `x_out` pushes each corner further outboard (open-wheelers): it widens the real track, so
## suspension and visual move together.
func _wheel_positions(geo: Dictionary, spec: VehicleSpec, x_out: float) -> PackedVector3Array:
	var corner_mass := spec.mass / 4.0
	var comp := clampf(corner_mass * GRAVITY / spec.spring_rate, 0.0, spec.rest_length * 0.8)
	var y := WHEEL_RADIUS + spec.rest_length - comp
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


## Derive brake/handbrake from the drivetrain so the §6 hierarchy always holds:
## total_brake (x4) = 1.4 * peak drive torque; total_handbrake (x2) = 1.5 * launch torque
## at idle+25% throttle (strictly between the 25% and 50% launch brackets the test checks).
func _derive_brakes(spec: VehicleSpec) -> void:
	var peak_engine := 0.0
	var idle_engine := VehicleSpec.sample_curve(spec.torque_curve, spec.idle_rpm)
	for i in spec.torque_curve.size():
		peak_engine = maxf(peak_engine, spec.torque_curve[i].y)
	var ratio1 := spec.gear_ratios[0] * spec.final_drive
	var max_drive := peak_engine * ratio1 * spec.efficiency
	var launch_25 := idle_engine * 0.25 * ratio1 * spec.efficiency
	spec.brake_torque = ceilf(max_drive * 0.35)
	spec.handbrake_torque = maxf(1.0, roundf(launch_25 * 0.75))


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

	# Collision is HAND-AUTHORED and preserved across regens: the collision nodes live in the
	# existing scene (tuned by hand — see the CollisionLower/CollisionUpper box pairs), so a
	# regen transplants them verbatim rather than overwriting them. Only a brand-new variant
	# with no scene yet gets the generated convex hull as a starting point. This is why a
	# rerun no longer clobbers hand-placed collision boxes.
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

	# Body model: instance the GLB, then steal its non-wheel children into a Model node under
	# the body transform (180deg Y flip so Kenney's +Z front faces this project's -Z, + kit
	# scale + x/z centring). The GLB's own wheel-* meshes are dropped with the freed instance.
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

	# Hand-authored subsystem nodes (the tractor's ThreePointHitch instance), transplanted like
	# the collision boxes and added LAST so the child order matches what the editor wrote.
	for extra: Node in kept["extras"]:
		_add(root, root, extra)

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Subtle painted-body finish, regen-owned via material_override (survives pack(), a hand-edit
## to the GLB-baked material would be clobbered on regen). One shared material for every
## MeshInstance3D under Model: keeps the colormap atlas + double-sided look but adds a
## semi-gloss sheen (specular, not metal) and a soft rim edge-catch so bodies lift off the
## matte terrain. NO clearcoat — it is a silent no-op under gl_compatibility.
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


## Everything in the existing scene the generator does NOT rebuild, duplicated so it survives
## the old instance being freed. This is the seam that keeps hand-authored anatomy from being
## regenerated away — and it is a WHITELIST of what the generator writes (GENERATED_CHILDREN
## plus the collision shapes), never a list of what to save, so a hand-added node is preserved
## by default rather than dropped by omission. Silently dropping one is exactly the bug this
## replaced: the tractor's whole ThreePointHitch (and every implement with it) disappeared on
## a regen while the run still reported success.
##
## Returns {collision, extras} because the two go back in at different points: collision first
## (before Model), extras last (after Lamps), matching the authored child order so a no-op
## regen stays byte-identical. Both empty when the scene doesn't exist yet (a new variant).
## Extras are REPARENTED out of the old instance rather than duplicated, and the old scene is
## instantiated with GEN_EDIT_STATE_INSTANCE (editor-build only — this tool always runs from the
## editor binary): both are needed for an instanced child to be re-serialised as a one-line
## instance. `duplicate()` loses the node's scene-instance state, so `pack()` no longer knows
## which properties came from the instanced scene and writes them all back out — the tractor's
## hitch came out carrying an explicit `type=` and `script=` that would pin the vehicle scene to
## today's hitch script forever. Collision shapes are plain nodes, so they stay a plain duplicate.
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


## Lamps subtree matching car.tscn's names/paths (LampSet needs zero changes beyond the head
## lens). Each end's lens rectangle comes from _find_lenses — i.e. from the model's own
## painted lamp face, not from the body box. The lens is SPLIT along its width: the inboard
## (1 - TURN_FRAC) carries the head/brake lamp, the outboard TURN_FRAC becomes the turn
## indicator, so an indicator always sits on real lens geometry (the Kenney kit paints no
## indicator of its own). Ends with no painted lamp (race, race-future, the tractors) fall
## back to the body-box formula below — whose height a variant may override via _fallback_lamp_y.
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


## Split one end's RIGHT-side lens box into an inboard main lamp and an outboard indicator.
## `facing` is -1 front / +1 rear: the outward normal along Z, which decides which way the
## meshes grow and which way the beam looks.
##
## The lamp mesh ENCLOSES the model's lens rather than resting on it, which is what fixes
## both of the artifacts a thin proud-of-the-face slab produced:
##   * Kenney lenses often WRAP around the corner onto the flank, so a slab covering only
##     the end face left the painted lens showing in profile. Depth therefore spans the
##     lens' full z extent, not a fixed thickness.
##   * A mesh whose side face landed exactly on the painted lens' side plane gave two
##     coincident coplanar surfaces, and the depth buffer cannot order those — hence the
##     shimmering seen from the side. Growing every outward face LENS_CLEAR beyond the
##     model's makes our surface unambiguously nearer the camera from every angle, so the
##     ordinary depth test resolves it. That is why this is geometry and not a
##     render_priority / depth-bias hack: a bias would win the tie on the end face but not
##     on the flank, and biasing risks punching through neighbouring bodywork instead.
## Growth on the INBOARD side is free — it just buries the mesh deeper inside the chassis.
##
## The cut follows the lens' shape: a WIDE lens (the usual case) splits along its width —
## main lamp inboard, indicator outboard — while a TALL lens (vertical clusters like the
## ambulance's rear corner light) splits along its height, main on top and indicator below,
## so the indicator still lands on real lens area instead of hanging off the side.
##
## A disc lens (the SUV's round headlamp) cannot be cut in half and still read as a disc, so
## it keeps its full circle as the main lamp and the indicator becomes a small box just
## outboard of it.
##
## Returns Vector3 positions (right/+X side) for the main lamp, the indicator, and the spot:
## main_pos, turn_pos, spot_pos, plus main_mesh / turn_mesh.
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


## Locate each end's lamp lens by reading the model's own texturing.
##
## The Kenney kit is one merged mesh per vehicle drawn from a single colormap atlas, so a
## lamp lens is not a named node — it is the run of triangles whose UV lands on the atlas'
## lamp swatches (amber at the front, red at the rear). This samples the atlas at every
## triangle's UV centroid, unions triangles that share a welded vertex AND an atlas shade,
## keeps the clusters that are lens-SHAPED (small, off the centreline, at an end face), then
## merges the survivors that touch — one lens spans several shades of its swatch.
##
## Filtering before merging is deliberate: it stops a lens fusing into a same-hue body panel
## (the firetruck is red all over) while still re-joining a lens split by its own gradient.
##
## Returns {front: {box, disc}, rear: {box, disc}} — box is the RIGHT-side (+X) lens; a
## missing key means that end has no painted lamp and the caller falls back to the body box.
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


func _save_scene_stable(packed: PackedScene, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(packed, path)
	if err != OK or before.is_empty():
		return err
	var after := FileAccess.get_file_as_string(path)
	if after != before and _unique_id_re.sub(after, "", true) == _unique_id_re.sub(before, "", true):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(before)
	return OK
