extends Node
## One-shot generator for the Kenney car-kit vehicle variants (CC0). For each variant writes
## src/vehicles/kenney/<variant>.tscn + <variant>_spec.tres from a family baseline + per-variant
## overrides (chassis, GLB body, lamps, wheels). Brake hardware (`brake_torque`, `handbrake_torque`,
## `park_pawl_torque`, `retarder_rating_nm`) is declared per baseline as a real hardware class,
## never derived from the tyre; only the axle split (`_front_brake_share`) is derived.
## Game-mode tool scene (not --script): base_vehicle.gd / tractor.gd need the InputRouter/Bridge
## autoloads. Run `godot --headless --path . res://tools/gen_kenney_vehicles.tscn`.
## Deterministic and destructive-by-run: a hand-tune driven into a shipped .tres must be folded
## back into the recipe here before the next run, or the rerun silently discards it.

const StableSave := preload("res://tools/stable_save.gd")
const OUT_DIR := "res://src/vehicles/kenney"
const MODELS := OUT_DIR + "/models"
const BASE_SCRIPT := "res://src/vehicles/base/base_vehicle.gd"
const TRACTOR_SCRIPT := "res://src/vehicles/tractor/tractor.gd"
const TRUCK_SCRIPT := "res://src/vehicles/truck/truck.gd"
## Vehicle script per CONTRACT family; unlisted gets plain BaseVehicle. Garbage-truck/firetruck
## are family "truck" (J1939 chassis); the heavy vans (VAN_BASE) are family "car"
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

## --- resistance (see VehicleMath's road-resistance header) ----------------------------
## Frontal area is derived from each body's own AABB (not listed per variant) at FRONTAL_FILL,
## the standard A ~ 0.8 * width * height rule of thumb for a non-rectangular silhouette. Wheels
## are outside the AABB and not added; they're already inside the Cd this multiplies.
const FRONTAL_FILL := 0.82
const GRAVITY := 9.8
const MIN_CLEARANCE := 0.12  ## m the collision hull floor is held above the wheel-contact plane
const BALANCE_G := 0.15  ## side g `_balance` reads K at: the 10 % held step at 30 km/h (0.1-0.26 g)
const WHEEL_BAND := 0.4   ## m z-window (body space) the body half-width is measured over per axle

## Wheels per model: the radius-normalized scene, the drawn radius (the axle's physics radius too:
## a body is judged against the tyre it shows), and the tread half-width at that radius. The
## flush-X rule below places the wheel's outer face at the body side, so this must match the model.
## 0.36 is the kit wheel's native 0.30 m at KIT_SCALE.
const WHEEL_DEFAULT := {"scene": OUT_DIR + "/wheel.tscn", "radius": 0.36, "half": 0.240}
const WHEEL_TRUCK := {"scene": OUT_DIR + "/wheel-truck.tscn", "radius": 0.36, "half": 0.210}
## The tractor's axles differ, and both sit on the tractor's own `scale` 1.35 body: these
## are the model's 0.30 / 0.45 radii scaled with it AND by a further 1.086, taking the rear tyre's
## diameter to 0.62 of the wheelbase (the bare body scale left it at 0.57, reading as a small
## wheel under a big machine; a real field tractor is nearer 0.64, which is where the spreader's
## hopper corner starts sweeping the tread -- `test_three_point_hitch` is the ceiling). Scaling
## `half` with the radius is what keeps the flush-X rule landing on the scaled authored station;
## the tyre growing inboard is what `wheel_x_out` pays back.
const WHEEL_TRACTOR_FRONT := {
	"scene": OUT_DIR + "/wheel-tractor-front.tscn", "radius": 0.44, "half": 0.3021}
const WHEEL_TRACTOR_REAR := {
	"scene": OUT_DIR + "/wheel-tractor-rear.tscn", "radius": 0.66, "half": 0.4048}

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
## variant -> {front?: y, rear?: y}, BODY space — a figure on the SCALED body, so a `scale` edit
## has to bring it along. Tractor rear: the box centre lands too low there (verified driving);
## 1.647 is the shipped height.
var _fallback_lamp_y := {"tractor-kenney": {"rear": 1.647}}
var _drag_report: Array = []  ## per-variant measured frontal area + derived drag area
var _shape_report: Array = []  ## per-variant collision shape kind + hull vertex count
var _lens_report: Array = []   ## per-variant lens detection, so a bad lamp is diagnosable
var _brake_report: Array = []  ## per-variant brakes against the tyre, the stall and the grade
var _balance_report: Array = []  ## per-variant predicted handling balance (BalanceModel)

# --- family baselines (spec fields) ---------------------------------------------------
const CAR_BASE := {
	# cd 0.32 is a modern saloon; crr 0.012 is a passenger radial on asphalt.
	"cd": 0.32, "crr": 0.012,
	# com_y is body-space height over the road: ~0.35 of the body's height for a saloon (a real one is
	# ~0.5 m), raised per body for SUVs/vans and dropped for the open-wheelers.
	# Springs and dampers are derived per axle off a ride frequency (`_derive_springs`), so every
	# body stands at the same 0.128 m sag (46 % of rest_length) whatever its mass and balance:
	# 1.39 Hz / zeta 0.36 bump, 0.48 rebound is 22 kN/m on 1800 / 2400 N*s/m at the 1150 kg
	# saloon's even corner.
	"mass": 1150.0, "com_y": 0.48, "ride_hz": 1.39, "zeta_bump": 0.36, "zeta_rebound": 0.48,
	"max_suspension_force": 30000.0, "rest_length": 0.28,
	# Yaw dynamic index k²/(a·b) (VehicleSpec.yaw_dynamic_index): the measured cars' median, which
	# SUVs and light vans share; pickups and the open-wheelers override (bands and sources:
	# docs/vehicles.md § Inertia).
	"yaw_index": 1.03,
	# Link geometry as a share of 100 % (`_derive_link_slopes`), inside a road car's 20-50 %
	# anti-dive and 30-70 % anti-squat. Pitch is judged per g against the body's own h / L and
	# what its springs and links predict (the launch trace's `pitch` line), never a full-size
	# degree figure: the toy wheelbases (1.6 m on the SUV) pitch more by geometry alone.
	"anti_dive": 0.4, "anti_squat": 0.5,
	# Bars: the 20 kN/m pair split 16 / 4 kN/m, so the front carries ~65-70 % of the roll stiffness
	# and washes wide first on equal side grip: the corner pass saturates the front first at 0.82-0.89 g
	# (front / rear ellipse share: sedan 0.96 / 0.91, taxi 0.97 / 0.88, hatchback-sports 0.99 / 0.86,
	# police 0.99 / 0.84), roll 4.4-5.0 deg, no wheel lifted. BalanceModel.limit predicts +9.7 / +9.6 /
	# +11.5 / +5.6 % front-first. All-front (no rear bar) reads front-first too, but lifts
	# hatchback-sports' inner front (6.5 deg of roll), which caps the transfer. The linear understeer left
	# is near neutral (K at 0.15 g 0.79-0.80 on the front-heavy saloons, 0.03 on `police`): roll steer
	# and compliance steer, which the sim lacks, make the rest of a real car's 2-4 deg/g.
	"anti_roll_rate": 16000.0,
	"anti_roll_rate_rear": 4000.0,
	# FWD default; per-variant override in VARIANTS (rwd/awd where the body says so).
	"wheel_inertia": 1.2, "driven_front": true, "driven_rear": false,
	# Differentials: 1.0 is open (Differential.bias_capacity). Road cars keep open axles and an
	# open centre unless the body really carries an LSD or a biasing centre (VARIANTS).
	"diff_bias_front": 1.0, "diff_bias_rear": 1.0, "centre_diff_bias": 1.0,
	# The fitment below is the stock class on dry asphalt (`TyreClass`); a fitted class moves only
	# its factors. Passenger fit on the all-season class; the SUVs, pickups and `van` take the
	# light-truck fit and the open-wheelers the slick (VARIANTS).
	"tyre_fit": TyreClass.Fit.PASSENGER, "tyre": "all_season",
	"mu_long": 1.05, "mu_lat": 0.97,
	# Equal tyres front and rear: the balance is the bar split and the tyre's two load laws.
	"rear_lat_grip": 1.0,
	# Every road car carries ABS (EU-mandatory since 2004); the open-wheelers opt out in VARIANTS.
	"abs_equipped": true,
	# Traction control too (part of ESC, EU-mandatory since 2014); `race-future` opts out.
	"tcs_equipped": true,
	# Hill-start assist (HillHold.Kind.ASSIST): the brake held ~1 s after its release on a grade
	# (Honda), unless the drive holds the grade first. The open-wheelers opt out with ABS.
	"hill_hold": HillHold.Kind.ASSIST, "hill_hold_s": 1.0,
	# Passenger radials: ~10% of mu per doubling of load past the corner's static share.
	# Cornering stiffness peaks at 2.56x the static corner load: MF `PKY2` 2.13 on a 205/60R15 rated
	# `Fz0` 4000 N (Pacejka, Tyre and Vehicle Dynamics 2nd ed., Table A3.1), over the ~3300 N corner of
	# a ~1350 kg saloon (`PKY2 * Fz0 / ref`; the ~1.2 ratio is an assumption held across the family).
	"load_sensitivity": 0.10, "cornering_peak_load": 2.56,
	# 185 Nm peak / ~156 hp at 6000 on the base saloon, anchored on a 1150 kg saloon hitting
	# 220 km/h and 8.5 s to 100 (measured 219.9 / 8.55 via `measure_vehicles -- sedan 180`; a
	# 45 s cap stops it short, ~202 and still gaining).
	# Keep the shape when re-scaling: idle fraction 98/185=0.53 lets the car pull away on a grade;
	# 6600/6800 is the plateau coming down then a soft limiter keeping the sports bodies off the
	# rev limiter in sixth.
	"torque_curve": [900, 98, 2000, 154, 3200, 184, 4800, 185, 6000, 185, 6600, 170, 6800, 61],
	"idle_rpm": 900.0, "redline_rpm": 6800.0,
	# Brake hardware, Nm per wheel (`BrakeSizing` checks every figure; `_brakes`). A saloon's
	# 280-300 mm vented discs: 1450 Nm average is 1.43 g of capacity at 1150 kg, past the 1.05 tyre,
	# so full pedal reaches ABS. The handbrake is a cable on the rear discs, 1400 Nm a wheel: it
	# locks the unloaded rears at speed (the saloon's static rear wheel holds ~850 Nm), so the
	# parking grade is the rear tyres' (`BrakeSizing.park_grade`), past the 20 % R13-H grade. The
	# pawl is a steel tooth sized past the driven tyres, so they slip first.
	"brake_torque": 1450.0, "handbrake_torque": 1400.0, "park_pawl_torque": 3000.0,
	# Sixth is the top-speed control: 0.925 settles the sedan at 6025 rpm / 219.9 km/h.
	# Gears 2-5 re-spread: 1.550 / 1.470 / 1.380 / 1.290 / 1.199.
	"gear_ratios": [4.5, 2.903, 1.975, 1.431, 1.109, 0.925],
	# Reverse stays 2.2, sized against sliding grip not gear 1: 185x2.2x3.9x0.9 = 1429 Nm at the
	# tyres against 2556 Nm of front-axle grip, no sustained reverse burnout.
	"reverse_ratio": 2.2,
	# shift_up 5900, bound by the weak bodies reaching sixth; governed bodies (van/pickup) reach
	# it via `Drivetrain.governed_upshift`.
	"final_drive": 3.9, "efficiency": 0.9, "shift_up_rpm": 5900.0, "shift_down_rpm": 2200.0,
	# The converter automatic's part-pedal map (`ShiftPolicy`), off the one measured TCU map found, a
	# 2013 Malibu's 6T40 (EPA, SAE 2015-01-1142, Fig. 11): its ~20 % pedal line upshifts at
	# 1720-1910 rpm, its coast downshifts sit at 1120-1190 rpm (3rd to 6th). Light 1800 / coast 1150;
	# the landing floor raises D1>D2 to 1961 (lands 1265). Kickdown past 0.8: the Malibu's kickdown
	# lines climb at 59-100 % pedal (estimate inside them). Dwell 1.5 s: EPA ALPHA's six-speed hold
	# after an upshift (the Malibu's shortest measured stay ~1.25 s). Sequential: no skip-shifts.
	"shift_up_light_rpm": 1800.0, "shift_down_light_rpm": 1150.0, "kickdown_pedal": 0.8,
	"shift_dwell_s": 1.5, "skip_shifts": false, "start_gear_max": 0,
	# The shift's inertia phase: 0.3 s, mid of a converter automatic's 0.15-0.5 s (US 11,724,688), an
	# estimate inside that band. No fixed cut: the TCU reduces the engine's torque through the phase
	# so the clutch passes the driver's demand (`Drivetrain.handover_fuel`; US 9,327,733).
	"shift_handover_s": 0.3,
	"engine_brake_frac": 0.12, "shift_cut_s": 0.0, "launch_engage_s": 0.0,
	# Motoring at and below idle (engine_friction_frac): ~0.10 of peak, ~18 N·m, an estimate for a
	# 1.6-2.0 L petrol's friction plus closed-throttle pumping (no primary figure found): it runs a
	# blipped crank back to idle, and a key-off one to rest in about a second. docs/drivetrain.md
	# § Crank and coupling.
	"engine_friction_frac": 0.10,
	# Crank and coupling (docs/drivetrain.md § Crank and coupling): 0.20 kg·m² is a 1.2-2.0 L petrol's
	# measured rotating assembly with a flexplate and a converter impeller (0.125-0.149 whole engine
	# with flywheel and clutch, 0.092 impeller); an automatic's converter; a clutch rating 1.5x the
	# peak, a car's OE margin. The converter ships as a fluid coupling (ratio 1.0, D4: a real one's
	# ~2.0 waits on a brake review); a 6-speed's lock-up closes in every gear past the launch.
	"engine_inertia": 0.20, "coupling": VehicleSpec.Coupling.CONVERTER, "clutch_reserve": 1.5,
	"converter_stall_ratio": 1.0, "lockup_gear": 1,
	"launch_rpm_over_idle": 0.0,
	# Ackermann 1.0 (docs/vehicles.md § Steering geometry), an estimate: real road cars run partial
	# (~40-60 %, a patent claim, for the loaded outer tyre at high g), but here the low-speed scrub is
	# the point and the road-speed split is ~0.15 deg; the step-steer sweep is the guard.
	"max_steer_deg": 38.0, "steer_speed": 7.0, "ackermann": 1.0,
	# Steering falloff: BaseVehicle lerps lock from full to min_steer_frac near
	# steer_falloff_speed, so the pair states an absolute lock at motorway speed — divide by the
	# variant's own max_steer_deg. Car family: ~10 deg (0.26x38) at 42 m/s = 151 km/h; mu_lat 0.97
	# needs ~2.8x less lock at that speed.
	"min_steer_frac": 0.26, "steer_falloff_speed": 42.0,
}
## The Kenney trucks' driveline is a medium-duty class, sized to the 7.5-8 t these bodies carry (a
## Class 7 rear loader, the Mack MD7's): a Cummins B6.7 behind an Allison 3000-family close-ratio
## six-speed, into a 5.57 axle on a 315/80R22.5 (docs/sources.md). Its diesel
## curve ends at zero at the redline: the governor droops to nothing above rated speed.
const TRUCK_BASE := {
	# Flat-fronted working truck: cd 0.70, crr 0.007 for low-resistance commercial radials.
	"cd": 0.70, "crr": 0.007,
	# Springs and dampers are an honest choice bounded by launch pitch on the toy 1.94 m wheelbase
	# (docs/vehicles.md § Pitch): 400 kN/m (~2.3 Hz on `garbage-truck`'s 1.9 t front corner, an
	# estimate for an unladen steer axle) at ~0.6 / 0.75 of critical (bump / rebound), over a road
	# damper's 0.2-0.4 (Gillespie): a road band rings the D1>D2 shift's pitch harder (an estimate:
	# not re-measured on the medium-duty gearing).
	# com_y 0.75 is a working truck's real height, ~0.30 of the AABB on these bodies: a hopper or a
	# pump deck sits high and the cab above it. Half-track 0.66-0.69 over 0.75 m tips at ~0.88 g,
	# clear of mu_lat 0.75, so the firetruck slides before it rolls (the garbage truck overrides).
	"mass": 4000.0, "com_y": 0.75, "spring_rate": 400000.0, "damper_bump": 31000.0,
	"damper_rebound": 41000.0, "max_suspension_force": 120000.0, "rest_length": 0.32,
	# Yaw index 0: Jolt's uniform-density tensor; no measured heavy truck (docs/vehicles.md § Inertia).
	"yaw_index": 0.0,
	# One rate for every corner; no Kenney body declares a rear axle share of its own.
	"spring_rate_rear": 0.0, "damper_bump_rear": 0.0, "damper_rebound_rear": 0.0,
	"anti_roll_rate": 0.0,
	"anti_roll_rate_rear": -1.0,
	# Anti-squat as CAR_BASE's share: with every newton of launch transfer through the springs the
	# rear squat alone was ~1 deg of the pitch. No anti-dive: braking pitch was never the complaint.
	"anti_dive": 0.0, "anti_squat": 0.5,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	"diff_bias_front": 1.0, "diff_bias_rear": 1.0, "centre_diff_bias": 1.0,
	# J1939: only family with an auxiliary retarder on the driven axle. 600 Nm at the gearbox output
	# is a medium-duty output retarder: 0.84 m/s^2 on the 8 t body through the 4.01 final drive.
	"retarder_equipped": true, "retarder_rating_nm": 600.0,
	# Axle brakes of the ~26 t chassis these bodies are built on (7.1 t steer, 13 t drive axle):
	# 15500 Nm a wheel is 2.2 g at 8 t, so the light body can lock its wheels and ABS works for it,
	# and full pedal holds gear 1 at converter stall (BrakeSizing.stall_hold_margin). The spring
	# brakes act on the drive axle's drums at 7000 Nm a wheel, under the service brake the
	# proportioning leaves on that drum (9.6 kNm on `firetruck`; `garbage-truck` overrides; a spring
	# chamber never out-torques its service chamber), and still past the static rear wheel's grip, so
	# they lock it. A truck whose air drains cannot drive away because its Allison-class box drops to
	# neutral while they are on (`Drivetrain.drive_inhibit`, set by TruckVehicle), not because the
	# drums out-hold the engine. No pawl: the box parks on the spring brakes.
	"brake_torque": 15500.0, "handbrake_torque": 7000.0, "park_pawl_torque": 0.0,
	# ABS: mandatory on goods vehicles in the EU since 1991.
	"abs_equipped": true,
	# ASR, standard beside EBS on a goods vehicle: kept as equipment, whose work is on low grip. On
	# dry asphalt gear 1 at converter stall pushes ~0.38 g, under the rear tyres' grip: `garbage-truck`
	# notc reaches 50 km/h in the same 6.82 s (measure_vehicles trace, 2026-10-16).
	"tcs_equipped": true,
	# Hill-start assist held 3 s (Volvo VN); the converter's creep alone holds ~11 % here.
	"hill_hold": HillHold.Kind.ASSIST, "hill_hold_s": 3.0,
	# The stock M+S drive tyre on dry asphalt: it sets the brake split and the steering-taper margin;
	# a garage swap scales it by the class factor only (src/vehicles/CLAUDE.md § Physics). The brake
	# hardware is declared above.
	"tyre_fit": TyreClass.Fit.TRUCK, "tyre": "truck_drive",
	"mu_long": 0.80, "mu_lat": 0.75, "rear_lat_grip": 1.0,
	# Commercial radials, a touch less load-sensitive than a passenger tyre. Cornering stiffness peaks
	# at 3.33x the static corner load: MF `PKY2` 3.33 on a 315/80R22.5 (projectchrono
	# `CityBus_Pac02Tire.tir`), a truck tyre running at its rated `Fz0` as a loaded truck's does.
	# BalanceModel.limit leaves both bodies front-first without a bar (garbage-truck +0.7 %,
	# firetruck +0.2 %); the corner pass saturates the front first on both (0.99 / 0.89 and 0.87).
	"load_sensitivity": 0.08, "cornering_peak_load": 3.33,
	# The 2021 B6.7's top Performance rating (Cummins): 325 hp, 750 lb-ft (1017 N·m) at 1800, governed
	# 2600, which is 890 N·m at rated speed. Idle 700 at half the peak and 1200 rpm at 0.81 of it (the
	# shape this baseline carried before), rated speed to 2900 a governor droop to nothing: estimates.
	# The derived stall is 1250 rpm, `(idle / stall)²` 0.31.
	"torque_curve": [700, 509, 1200, 826, 1800, 1017, 2600, 890, 2900, 0],
	"idle_rpm": 700.0, "redline_rpm": 2900.0,
	# The Allison 3000 / 3200 close ratios and reverse (Allison; the 3200 carries 325 hp in refuse
	# service), into a 5.57 axle on a Class 7 rear loader with this engine (dealer listing): on the
	# 315/80R22.5's 0.500 m loaded radius, re-referred to the drawn 0.36 m (x 0.72), so road speed
	# per rpm and force per N*m are the real truck's. First 19.4:1 overall (38.9 per metre of radius),
	# top 52.1 km/h per 1000 rpm: the speed limit governs, never the droop.
	"gear_ratios": [3.49, 1.86, 1.41, 1.00, 0.75, 0.65], "reverse_ratio": 5.03,
	# shift_up 2700: past rated speed, where the next gear's torque meets this gear's on the droop
	# (D1 > D2 crosses ~2740, D5 > D6 ~2630); it lands the 1.88 D1 > D2 step at 1440 rpm. shift_down
	# 1200, 1.2x under that landing.
	"final_drive": 4.010, "efficiency": 0.9, "shift_up_rpm": 2700.0, "shift_down_rpm": 1200.0,
	# The converter automatic's map (`ShiftPolicy`) by CAR_BASE's structure at this diesel's band, an
	# estimate (no truck map found): light 1600, under the 1800 peak; coast 900. The landing floor
	# raises the 1.88 D1>D2 to 1857 (lands 990). Kickdown, dwell and no skip-shifts as CAR_BASE's.
	"shift_up_light_rpm": 1600.0, "shift_down_light_rpm": 900.0, "kickdown_pedal": 0.8,
	"shift_dwell_s": 1.5, "skip_shifts": false, "start_gear_max": 0,
	# A converter automatic's inertia phase and torque reduction, as CAR_BASE's: no fixed cut (an
	# Allison-class box shifts clutch to clutch, with no torque interruption).
	"shift_handover_s": 0.3,
	"engine_brake_frac": 0.15, "shift_cut_s": 0.0, "launch_engage_s": 0.0,
	# Motoring at and below idle: 0.10 of peak, the Volvo Penta TD640VE's (5.5 L) published friction
	# power (17-26 kW, 90-104 N·m, at 1800-2400 rpm) run linearly down to idle (~66 N·m of its 658).
	"engine_friction_frac": 0.10,
	# A 6-9 L medium diesel behind an Allison-class converter box: 1.5 kg·m² at the crank (a 5.5 L
	# industrial diesel's published total, Volvo Penta TD640VE); a truck clutch's 2x peak rating.
	"engine_inertia": 1.5, "coupling": VehicleSpec.Coupling.CONVERTER, "clutch_reserve": 2.0,
	# An Allison-class box: lock-up from 2nd range (1st-range lock-up is an option); the converter a
	# fluid coupling, as CAR_BASE's.
	"converter_stall_ratio": 1.0, "lockup_gear": 2,
	"launch_rpm_over_idle": 0.0,
	# Ackermann 1.0, an estimate: trucks set close to full for steer-tyre wear (SAE 861975, 912693;
	# no figure sourced).
	"max_steer_deg": 26.0, "steer_speed": 2.0, "ackermann": 1.0,
	# ~5.7 deg floor (0.22x26) at 26 m/s, under both governed cruise speeds (85/110 km/h);
	# 19.5 deg at 30 km/h, still wider than the ~17.6 deg mu_lat 0.75 can hold there.
	"min_steer_frac": 0.22, "steer_falloff_speed": 26.0,
}
## Heavy vans (delivery / delivery-flat / ambulance): car-family, proprietary CAN, on a van
## drivetrain of their own class (a Ford Transit 3.2 L five-cylinder diesel behind the 6R80
## six-speed automatic). A baseline of its own, not a CAR_BASE / TRUCK_BASE alias: TRUCK_BASE
## carries J1939-only flags, and the chassis figures below are a 4-5 t van's.
const VAN_BASE := {
	# A box van is a smoothed truck front: cd 0.45 on commercial tires.
	"cd": 0.45, "crr": 0.009,
	# Derived per axle as CAR_BASE's: 1.28 Hz / zeta 0.31 bump, 0.43 rebound is 65 kN/m on
	# 5000 / 7000 N*s/m at a 4 t van's even corner (TRUCK_BASE's 240 kN/m is an 8 t truck's).
	"mass": 4000.0, "com_y": 0.65, "ride_hz": 1.28, "zeta_bump": 0.31, "zeta_rebound": 0.43,
	"max_suspension_force": 90000.0, "rest_length": 0.32,
	# Yaw index 0.91, estimate: no 4-5 t van is measured; the median of the full-size Ford E-series
	# vans (0.87 / 0.91 / 0.94; docs/vehicles.md § Inertia).
	"yaw_index": 0.91,
	# CAR_BASE's geometry: the heavy vans' short wheelbases pitch the same way.
	"anti_dive": 0.4, "anti_squat": 0.5,
	# 110 kN/m: 2.6-3.0 deg of roll at the 0.75-0.84 g limit (corner pass, 2026-10-15).
	"anti_roll_rate": 110000.0,
	"anti_roll_rate_rear": -1.0,
	"wheel_inertia": 3.0, "driven_front": false, "driven_rear": true,
	"diff_bias_front": 1.0, "diff_bias_rear": 1.0, "centre_diff_bias": 1.0,
	# mu_lat 0.85: commercial-tyre side grip, so a cornering van slides before it lifts a wheel.
	# Twin rear tyres (the dual-rear-wheel Transit 350 HD class, drawn as singles), each at half the
	# corner's load (GroundDriveSpec.rear_twin_tyres): the pair's peak side force is
	# `1 + load_sensitivity` over one tyre's, its cornering stiffness `2 C(L / 2)`. BalanceModel.limit:
	# delivery -2.0 -> +5.4 %, delivery-flat +6.0 %, ambulance +7.5 % front-first (corner pass: front
	# first, 0.97 / 0.95, 0.98 / 0.84, 0.99 / 0.84); a bar split moves
	# `delivery` not at all, so the bars stay even. Step pass: no spin, body slip <= 5 deg, K at
	# 30 km/h +0.51 deg/g on `delivery` (single rears at c 1.92: -0.95, and a lifted 100 km/h step spins).
	# The heavy vans: a light-truck fit on the all-season class.
	"tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "tyre": "all_season",
	"mu_long": 1.0, "mu_lat": 0.85, "rear_lat_grip": 1.0, "rear_twin_tyres": true,
	"abs_equipped": true, "tcs_equipped": true,
	# Hill-start assist held 3 s, a truck's (Volvo VN).
	"hill_hold": HillHold.Kind.ASSIST, "hill_hold_s": 3.0,
	# A 3.5-5 t van's brakes: 5200 Nm a wheel is 1.4 g at 4.2 t, and they hold gear 1 at converter
	# stall (BrakeSizing.stall_hold_margin). Handbrake: drum-in-hat rears, 4800 Nm a wheel, locks the
	# rears; the parking grade is the rear tyres' (`BrakeSizing.park_grade`).
	"brake_torque": 5200.0, "handbrake_torque": 4800.0, "park_pawl_torque": 8000.0,
	# Commercial radials, as TRUCK_BASE. Cornering stiffness peaks at 1.92x the static corner load, an
	# estimate: no open LT / C-load MF set; `PKY2` ~1.4-1.8 on a tyre rated ~12 kN over a 4.2 t van's
	# ~10.3 kN corner.
	"load_sensitivity": 0.08, "cornering_peak_load": 1.92,
	# The van class (docs/sources.md, the heavy vans'): Ford's 3.2 L diesel, 470 Nm
	# over 1750-2500 rpm and at least 90 % of it over 1500-2750 (secondary), 147 kW at 3000 rpm (EU,
	# secondary), which is 468 Nm, so the plateau holds to rated speed. Idle 750 (estimate) at half
	# the peak, TRUCK_BASE's idle share, rising straight to the band's 1500 edge. Rated speed to
	# 4000 rpm is a governor droop to nothing (estimate: no published high-idle figure).
	"torque_curve": [750, 235, 1500, 423, 1750, 470, 2500, 470, 3000, 468, 4000, 0],
	"idle_rpm": 750.0, "redline_rpm": 4000.0,
	# The 6R80's ratios and reverse (secondary), through the 3.73 limited-slip axle of a 4.7 t
	# dual-rear-wheel Transit 350 HD with this engine (secondary): first 15.6:1 overall, top
	# 52.7 km/h per 1000 rpm at r 0.36, so top speed is drag's, well under the 211 km/h droop end.
	"gear_ratios": [4.171, 2.340, 1.521, 1.143, 0.867, 0.691], "reverse_ratio": 3.403,
	# shift_up 3300: past rated speed, where the next gear's torque meets this gear's on the droop
	# (D1 > D2 crosses ~3440, D5 > D6 ~3200); it lands the 1.78 D1 > D2 step at 1850 rpm, in the
	# band. shift_down 1400, under the band's 1500 edge: the widest landing sits 1.32x over it.
	"final_drive": 3.73, "efficiency": 0.9, "shift_up_rpm": 3300.0, "shift_down_rpm": 1400.0,
	# The converter automatic's map (`ShiftPolicy`) by CAR_BASE's structure at the diesel's band, an
	# estimate (no van map found): light 1750, the plateau's start; coast 1000. The landing floor
	# raises the 1.78 D1>D2 to 1958 (lands 1100). Kickdown, dwell and no skip-shifts as CAR_BASE's.
	"shift_up_light_rpm": 1750.0, "shift_down_light_rpm": 1000.0, "kickdown_pedal": 0.8,
	"shift_dwell_s": 1.5, "skip_shifts": false, "start_gear_max": 0,
	# A converter automatic's inertia phase and torque reduction, as CAR_BASE's: no fixed cut.
	"shift_handover_s": 0.3,
	"engine_brake_frac": 0.12, "shift_cut_s": 0.0, "launch_engage_s": 0.0,
	# No van-diesel friction figure found: TRUCK_BASE's 0.10 of peak at idle (TD640VE).
	"engine_friction_frac": 0.10,
	# Crank 0.40 kg·m² (estimate, band 0.35-0.45): twice a 2.5 L petrol's measured 0.20 with its
	# impeller (CAR_BASE's anchor), for a 3.2 L five-cylinder diesel's heavier crank and flywheel. A
	# car-and-light-truck box, so the car OE clutch margin 1.5; a six-speed's lock-up closes in every
	# gear past the launch. The converter a fluid coupling, as CAR_BASE's.
	"engine_inertia": 0.40, "coupling": VehicleSpec.Coupling.CONVERTER, "clutch_reserve": 1.5,
	"converter_stall_ratio": 1.0, "lockup_gear": 1,
	"launch_rpm_over_idle": 0.0,
	# Ackermann 1.0, an estimate, as TRUCK_BASE.
	"max_steer_deg": 26.0, "steer_speed": 2.0, "ackermann": 1.0,
	# ~6 deg floor (0.23x26) at 28 m/s, between the cars' 10 deg and trucks' 4.8. Ambulance keeps
	# the fraction on its narrower 24 deg rack (5.5 deg).
	"min_steer_frac": 0.23, "steer_falloff_speed": 28.0,
}
const TRACTOR_BASE := {
	# cd 0.90 (nothing streamlined), crr 0.020 (worst in the project, lugged tires).
	"cd": 0.90, "crr": 0.020,
	"mass": 4200.0, "com_y": 0.35,
	# Yaw index 0: Jolt's uniform-density tensor; no measured tractor (docs/vehicles.md § Inertia).
	"yaw_index": 0.0,
	# A tractor's "suspension" is its tyres: 330 kN/m is 2.5 Hz on the 1.33 t front corner of the
	# 7 t variant (a sedan is ~1.3 Hz), static sag 1330*9.8/330000 = 4.0 cm, 33% of the 0.12 m
	# rest_length — the same sag/travel fraction band the truck family targets; a real front tyre
	# of this size is 300-400 kN/m. Damping ratio 0.40-0.50 (a tyre has little hysteresis, but
	# this models the whole axle, not just the rubber).
	"spring_rate": 330000.0, "damper_bump": 16500.0,
	"damper_rebound": 20300.0, "max_suspension_force": 110000.0, "rest_length": 0.12,
	# Rear: the 650/65R38 157D's secant rate at its rated 4127 kg and 1.6 bar max pressure, 9.65 cm
	# down (72.8 in across, 32.6 in static loaded radius: docs/sources.md),
	# 4127*9.81/0.0965 = 420 kN/m. Sized at max pressure because the rear carries the implement:
	# pressure set to a field load holds the same deflection, ~305 kN/m at 3 t a corner.
	# COMPROMISE: the raised harrow sags a rear corner 8.2 cm of the 0.12 m `rest_length` (bare
	# 5.1 cm), leaving ~4 cm of bump; the `plough` pass's transients stay inside it, a harder jolt
	# reaches full bump (`RayWheel.start_overlaps`). The real tyre has its 0.42 m section in
	# reserve; a longer rear travel is a new spec field that moves every bare-tractor row.
	"spring_rate_rear": 420000.0, "damper_bump_rear": 0.0, "damper_rebound_rear": 0.0,
	"anti_roll_rate": 0.0,
	"anti_roll_rate_rear": -1.0,
	# No link geometry: the "suspension" is the tyres.
	"anti_dive": 0.0, "anti_squat": 0.0,
	# Per axle, I = m (kappa r)^2 at the drawn radius, tyre and rim (liquid ballast does not turn
	# with the tyre): rear 367 kg x (0.75 x 0.66)^2 = 90, front 143 kg x (0.75 x 0.44)^2 = 16
	# (docs/sources.md grades the masses and kappa). The spin step divides NET torque by 1 + reaction_stiffness, so a bigger inertia only slows
	# spin-up.
	"wheel_inertia": 16.0, "wheel_inertia_rear": 90.0, "driven_front": false, "driven_rear": true,
	# ISOBUS: only family with lockable diff / engageable front axle at runtime.
	"rear_diff_lockable": true, "front_axle_engageable": true,
	# Open rear with a lock; MFWD is a clutch into a rigid transfer to the front axle, no centre
	# diff, so engaged it ties the two axles' mean speeds together (and winds up in tight turns).
	"centre_diff_rigid": true,
	"diff_bias_front": 1.0, "diff_bias_rear": 1.0, "centre_diff_bias": 1.0,
	# `rear_lat_grip` 1.077: the rears are the bigger tyre, so they carry their load at a smaller share
	# of their rating, `1 + load_sensitivity * log2(rated rear / rated front)`: 650/65R38 157D (4125 kg)
	# over 540/65R28 142D (2650 kg), a ~180 hp tractor's fit (Michelin MultiBib). It scales the rear's
	# peak and its cornering stiffness alike. BalanceModel.limit: -3.2 -> +4.6 % front-first; the
	# corner pass saturates the front first (0.99 / 0.80 at 0.78 g).
	"tyre_fit": TyreClass.Fit.TRACTOR, "tyre": "ag_lug",
	"mu_long": 1.0, "mu_lat": 0.95, "rear_lat_grip": 1.077,
	# No ABS: a farm tractor's service brakes are not anti-lock. They sit on the rear axle only, and
	# the pedal engages MFWD so the shaft brakes the fronts (a 40 km/h tractor brakes all four).
	"abs_equipped": false, "brake_engages_front_axle": true,
	# Wet multi-disc brakes on the rear axle: 8600 Nm a wheel on average at a 0.36 m wheel (17.2 kNm
	# at each rear) is 1.4 g at 7 t, and the 34 kNm total beats gear 1 at stall (23.6 kNm over all
	# four wheels through MFWD; 63 / 43.3 kNm re-referred below): the shaft carries the fronts'
	# drive into the rears' spare brake (`BrakeSizing.stall_hold_margin`). The parking brake on the
	# rear axle, 8000 Nm a wheel at 0.36 m, locks the rears; the parking grade is the rear tyres'
	# (`BrakeSizing.park_grade`). The powershift's park lock is the pawl, 15000 Nm at 0.36 m.
	# All three sit inboard of the final reduction (the Case IH Puma's "differential" wet discs,
	# secondary, off a spec listing, not a workshop manual; the parking brake and pawl in the
	# transmission), so the re-derived reduction below (x 0.66 / 0.36 = 1.833) puts that much more
	# of the same hardware at the wheel: re-referred, not enlarged, and every force (torque over
	# radius) is unchanged.
	"brake_torque": 15767.0, "handbrake_torque": 14667.0, "park_pawl_torque": 27500.0,
	# No TC either: MFWD and the diff lock are a tractor's traction aids.
	"tcs_equipped": false,
	# A powershift hill hold (Valtra HillHold): held at rest in gear until the drive pedal is down
	# and the clutch carries the grade, with no timeout.
	"hill_hold": HillHold.Kind.STANDSTILL, "hill_hold_s": 0.0,
	# Big soft flotation tyres lose more mu per doubling of load than a road tyre. Cornering stiffness
	# peaks at 3.0x the static corner load, an estimate: no open ag-radial MF set (`PKY2 * Fz0 / ref`
	# ~2.5-3.5).
	"load_sensitivity": 0.12, "cornering_peak_load": 3.0,
	# Rated 2000, governed to nothing by 2600 (high idle).
	"torque_curve": [800, 550, 1200, 680, 1600, 700, 2000, 640, 2200, 560, 2600, 0],
	"idle_rpm": 800.0, "redline_rpm": 2600.0,
	# ~4.4:1 spread, 9 km/h first to a 40 km/h road gear. Reverse is the bus's one R byte, so it is
	# D3's ratio: a shuttle reverses near its forward working speeds.
	# `final_drive` 10.083 is 5.5 at a 0.36 m wheel re-referred to the drawn 0.66 m rear
	# (x 0.66 / 0.36): G / r is unchanged, so every road speed per rpm, the force per N*m and the
	# crank's reflected mass J (G / r)^2 / m are too. A radius re-referral, not a traction lever.
	"gear_ratios": [7.0, 5.2, 3.9, 2.9, 2.15, 1.6], "reverse_ratio": 3.9,
	"final_drive": 10.083, "efficiency": 0.9, "shift_up_rpm": 2200.0, "shift_down_rpm": 1000.0,
	# The powershift's map (`ShiftPolicy`): light 1500, Massey Ferguson AutoDrive's Eco mode (its
	# Power mode's 2100 is the full pair's 2200); the sourced 1200 downshift (Dynashift, both modes)
	# sits over the full pair's 1000, so the coast stays at it (0). 1500 lands ~1110 on the 1.35
	# steps, just over the landing floor (1484). No pedal kickdown: AutoDrive shifts on engine speed
	# and none is sourced for a powershift; with one, the bobtail kicked from D5 to D4 at 15 km/h
	# and revved into its forced upshift 0.62 s later (cruise probe, 2026-10-13). The six-speed's
	# 1.5 s dwell, and skip-shifts: a lift from 2200 in D1 lands D2 past its own light point and
	# takes D3.
	# The start gear up to D3 (`ShiftPolicy.start_gear`): a powershift's start gear is a driver
	# preset, higher for an empty run and lower with a load; picked here from the load standing on
	# the grade, as the I-Shift picks its own from gross weight and gradient. D3 on the flat, D1 laden
	# on mud or on a steep grade (docs/heavy_vehicles.md § Tractor, implement & ISOBUS).
	"shift_up_light_rpm": 1500.0, "shift_down_light_rpm": 0.0, "kickdown_pedal": 0.0,
	"shift_dwell_s": 1.5, "skip_shifts": true, "start_gear_max": 3,
	# The clutch overlap: 0.3 s, a simulated tractor powershift's baseline (YTO TX4A, Agriculture
	# 14(2) 254, 2024).
	"shift_handover_s": 0.3,
	"engine_brake_frac": 0.20, "shift_cut_s": 0.0,  ## powershift: no interruption
	# Motoring at and below idle: 0.10 of peak, the same 5.5 L industrial diesel's friction power
	# run down to idle, as TRUCK_BASE's.
	"engine_friction_frac": 0.10,
	# Powershift clutch modulation: the pack's capacity builds over 0.8 s on a pull-away (an
	# estimate; no fill-and-ramp duration sourced) while the controller slips it on the launch line,
	# in the start gear. The ramp is what holds a floored start near the grip peak: with the whole
	# rating on the first tick the rears flash to 0.6 slip and the front axle drops to 5 % of parked
	# (measure_vehicles trace, 2026-10-10). Its close onto the wheels spans `shift_handover_s`.
	"launch_engage_s": 0.8,
	# A 4.5-7 L tractor diesel: 1.5 kg·m² at the crank (the 5.5 L industrial anchor). A powershift is
	# a wet clutch pack, rated as a truck clutch (2x peak, an estimate: no pack figure sourced).
	"engine_inertia": 1.5, "coupling": VehicleSpec.Coupling.CLUTCH, "clutch_reserve": 2.0,
	"converter_stall_ratio": 1.0, "lockup_gear": 1,
	"launch_rpm_over_idle": 0.0,
	# Ackermann 1.0, an estimate (no ag-tractor figure sourced): headland turns at full lock are the
	# scrub case.
	# `steer_speed` 0.75: a hydrostatic steering unit turns the wheels only as fast as the driver
	# winds the wheel. A Fendt 516 Vario takes 5 1/3 turns lock to lock (topagrar test), 960 deg
	# centre to lock, and a quick human hand runs ~720 deg/s (NHTSA's fishhook rate), so lock in
	# ~1.3 s (docs/sources.md).
	"max_steer_deg": 38.0, "steer_speed": 0.75, "ackermann": 1.0,
	# steer_falloff_speed 11 m/s = 39.6 km/h is the tractor's own top speed, so the floor lock
	# arrives exactly at type-approval road speed. 0.55 keeps field-work cost (8-12 km/h headland
	# turns, a quarter of road speed) to ~11% while cutting 45% of road dartiness.
	"min_steer_frac": 0.55, "steer_falloff_speed": 11.0,
}

# variant id -> { family, base?, torque_mul?, <spec field overrides...> }
# `family` is the CONTRACT family (VehicleCatalog) and picks the feel baseline + vehicle script
# (FAMILY_SCRIPTS); `base` names the feel baseline when it differs (heavy vans are car-family,
# van chassis feel). Driveline flags (rear_diff_lockable / front_axle_engageable /
# retarder_equipped / centre_diff_rigid), the differential bias ratios and `gear_ratios` may all
# be overridden per variant over the baseline.
const VARIANTS := {
	# car family
	# Brake hardware classes over CAR_BASE's saloon: the performance package on `sedan-sports` and
	# `police` (1800 Nm, 1.6-1.9 g, and enough rear brake that both pedals hold the rear-driven
	# bodies at stall); SUV / light-commercial discs on the 1.5-1.6 t bodies (2000 Nm, 1.3-1.5 g;
	# 1700 Nm handbrakes for their heavier rears); racing brakes on the open-wheelers (2000 Nm,
	# 2.5 g at 900 kg; no pawl, a sequential box has no P).
	# Driven layout per body: FWD is the CAR_BASE default, `driven_rear` alone is RWD, both is
	# AWD — the axis that gives each car its own handling (FWD hatch scrabbles, RWD interceptor
	# steps out, SUVs hook up). `front_weight` on the front-drivers puts the transverse engine
	# over the driven axle (measured 48/52 rear-biased at the body origin, unusable for FWD).
	"sedan": {"family": "car", "front_weight": 0.60},
	# COMPROMISE (`sedan-sports`, `suv`, `suv-luxury`, `pickup`, `pickup-flat`): even bars,
	# `rear_lat_grip` 1.08 and the cornering-stiffness law off, a rear grip bonus with no hardware
	# behind it. These near-50/50 rear-driven bodies spin lifted 100 km/h steps on equal tyres with
	# a front-biased bar (1, 4, 1, 1, 2 cells; `suv` 3 with the law off too): on a lift the lightened
	# rears reach their side peak at a smaller slip, which the steady BalanceModel margin cannot see.
	# Undoing it needs roll steer (brief 15); until then these bodies hold 1.08's step results.
	"sedan-sports": {"family": "car", "anti_roll_rate": 10000.0, "anti_roll_rate_rear": -1.0, "rear_lat_grip": 1.08, "cornering_peak_load": 0.0, "engine_inertia": 0.18, "mass": 1050.0, "torque_mul": 1.12, "final_drive": 4.1, "max_steer_deg": 40.0, "driven_front": false, "driven_rear": true, "brake_torque": 1800.0},
	# Hot hatch: a helical front LSD (Quaife-class, ~2.5:1), so a front wheel a bump or a steer input
	# peels still leaves its partner up to 2.5x its torque rather than an equal share.
	"hatchback-sports": {"family": "car", "engine_inertia": 0.18, "mass": 1000.0, "torque_mul": 1.10, "final_drive": 4.2, "max_steer_deg": 42.0, "front_weight": 0.60, "diff_bias_front": 2.5},
	# Lever for SUV power is their own `torque_mul`, not the shared CAR_BASE curve: measured
	# 0-100 goes as peak^-0.6 on the sedan, peak^-1.4 on the suv.
	# Both SUVs: a Torsen-type centre (~3:1). Under launch squat the rear axle carries ~2x the
	# front (2412 / 4956 N measured), inside 3:1, so the heavy axle is no longer capped by the light one.
	"suv": {"family": "car", "tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "com_y": 0.62, "anti_roll_rate": 18000.0, "anti_roll_rate_rear": -1.0, "rear_lat_grip": 1.08, "cornering_peak_load": 0.0, "mass": 1500.0, "torque_mul": 1.05, "mu_lat": 0.88, "max_steer_deg": 34.0, "driven_rear": true, "centre_diff_bias": 3.0, "brake_torque": 2000.0, "handbrake_torque": 1700.0},
	# 1.54 is the biggest multiplier in the family: 285 Nm through an AWD 1600 kg body.
	"suv-luxury": {"family": "car", "tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "com_y": 0.62, "anti_roll_rate": 18000.0, "anti_roll_rate_rear": -1.0, "rear_lat_grip": 1.08, "cornering_peak_load": 0.0, "mass": 1600.0, "torque_mul": 1.54, "mu_lat": 0.88, "max_steer_deg": 33.0, "driven_rear": true, "centre_diff_bias": 3.0, "brake_torque": 2000.0, "handbrake_torque": 1700.0},
	"taxi": {"family": "car", "mass": 1250.0, "front_weight": 0.60},
	"police": {"family": "car", "mass": 1300.0, "torque_mul": 1.18, "final_drive": 4.0, "max_steer_deg": 40.0, "driven_front": false, "driven_rear": true, "brake_torque": 1800.0},
	# Open-wheelers: `wheel_x_out` measured per body against its own half-width at the wheel
	# stations (re-drive after changing, it also steadies cornering). `cd` 0.70: exposed wheels +
	# wing really do run ~2x a saloon's drag. `front_weight` 0.42: engine sits behind the driver;
	# at the body origin they measured 58/42 and 61/39, backwards for the layout. `race` is
	# rear-drive (classic formula car), `race-future` is AWD.
	# Steering falloff: the family's ~10 deg at 42 m/s, as an absolute lock (0.25x40, 0.24x42). A
	# race car turns in no slower than a saloon; spin margin is `rear_lat_grip` and TC, not lock.
	# `cl` 2.5 is the only wing in the project: same measured area as `cd`, Cl*A 2.24 against
	# Cd*A 0.63 (lift/drag 3.6). 2.1 kN at 140 km/h rising to 8.8 kN at 288 km/h top end; a spring
	# force (GroundDriveSpec.downforce_area) worth ~0.10 m of squat — raising `cl` past this
	# bottoms the suspension.
	# The two gear boxes differ on gear 1, a launch choice: `race` has TC to hold a 3.2 first at the
	# grip peak. `race-future` is AWD with no TC, and 409 Nm through a 3.2 first spins all four tyres
	# (0-100 3.25 s, 1.4 s of it spinning), so its first is 2.375, about where the engine stops
	# saturating them (0-100 3.00 s; measure_vehicles, 2026-10-08), with 2-5 re-spread
	# (1.33/1.31/1.29/1.27/1.26). Both keep a long top gear (0.66 vs CAR_BASE's 0.925), reaching
	# 288.0 / 295.8 km/h.
	# Differentials: `race` carries a plate LSD on its driven rear (2.5); `race-future` the same
	# rear plus a Torsen-type centre (3.0). Neither carries ABS (formula cars race without it) or
	# hill-start assist.
	# `race` carries TC, as GT and prototype racers do: 389 Nm through gears 1-3 outpulls its rears,
	# and floored through a turn below ~70 km/h it spun at almost any steer (step-steer probe,
	# 2026-10-03); the AWD `race-future` spreads it over four tyres and needs none.
	# `ride_hz` 1.6, stiffer than a saloon as a winged car is: at the family's 1.39 these light
	# bodies' fronts bottom under the top-speed wing load (test_downforce_fits_inside_...).
	# `torque_mul` tracks CAR_BASE so absolute torque stays fixed (2.10x185=389 Nm,
	# 2.21x185=409 Nm) — re-derive on any CAR_BASE torque edit.
	# `rear_lat_grip` 1.15: the wide rears a rear-heavy formula car runs; on equal tyres the heavier
	# rear axle's load-sensitive mu sits under the front's and the body steers loose. Bars even
	# (10 kN/m each): +11.0 / +10.4 % front-first (BalanceModel.limit).
	# Shifting: the full-pedal pair at any pedal (no light map, kickdown or dwell). The sequential
	# cuts the ignition 0.15 s through a shift (the torque interruption CAR_BASE's converter has no
	# need of) and closes at its rating: on J 0.06 the rev drop already spans ~2 ticks, a dog box's
	# near-instant engagement (estimate).
	# `yaw_index` 0: no measured open-wheeler, so Jolt's tensor (docs/vehicles.md § Inertia).
	"race": {"family": "car", "tyre_fit": TyreClass.Fit.RACE, "tyre": "slick", "anti_roll_rate": 10000.0, "anti_roll_rate_rear": -1.0, "yaw_index": 0.0, "shift_up_light_rpm": 0.0, "shift_down_light_rpm": 0.0, "kickdown_pedal": 0.0, "shift_dwell_s": 0.0, "shift_handover_s": 0.0, "shift_cut_s": 0.15, "engine_inertia": 0.06, "coupling": VehicleSpec.Coupling.CLUTCH, "ride_hz": 1.6, "com_y": 0.30, "cd": 0.70, "cl": 2.50, "mass": 900.0, "torque_mul": 2.10, "final_drive": 4.2, "gear_ratios": [3.2, 2.30, 1.72, 1.32, 0.98, 0.66], "mu_long": 1.35, "mu_lat": 1.4, "rear_lat_grip": 1.15, "max_steer_deg": 40.0, "driven_front": false, "driven_rear": true, "front_weight": 0.42, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.21, "min_steer_frac": 0.25, "steer_falloff_speed": 42.0, "diff_bias_rear": 2.5, "abs_equipped": false, "hill_hold": HillHold.Kind.NONE, "tcs_equipped": true, "brake_torque": 2000.0, "park_pawl_torque": 0.0},
	"race-future": {"family": "car", "tyre_fit": TyreClass.Fit.RACE, "tyre": "slick", "anti_roll_rate": 10000.0, "anti_roll_rate_rear": -1.0, "yaw_index": 0.0, "shift_up_light_rpm": 0.0, "shift_down_light_rpm": 0.0, "kickdown_pedal": 0.0, "shift_dwell_s": 0.0, "shift_handover_s": 0.0, "shift_cut_s": 0.15, "engine_inertia": 0.06, "coupling": VehicleSpec.Coupling.CLUTCH, "ride_hz": 1.6, "com_y": 0.30, "cd": 0.70, "cl": 2.50, "mass": 850.0, "torque_mul": 2.21, "final_drive": 4.2, "gear_ratios": [2.375, 1.786, 1.363, 1.057, 0.832, 0.66], "mu_long": 1.25, "mu_lat": 1.35, "rear_lat_grip": 1.15, "max_steer_deg": 42.0, "driven_rear": true, "front_weight": 0.42, "wheels": [WHEEL_DEFAULT, WHEEL_DEFAULT], "wheel_x_out": 0.36, "min_steer_frac": 0.24, "steer_falloff_speed": 42.0, "diff_bias_rear": 2.5, "centre_diff_bias": 3.0, "abs_equipped": false, "hill_hold": HillHold.Kind.NONE, "tcs_equipped": false, "brake_torque": 2000.0, "park_pawl_torque": 0.0},
	# Commercial bodies: RWD, governed at 180 like the real things (measured 198-200 ungoverned).
	# Bars: the 36 kN/m pair split 24 / 12 kN/m: the corner pass saturates the front first (0.99 /
	# 0.83 at 0.74 g), LLTD 58 %, roll 4.0 deg, no wheel lifted; BalanceModel.limit predicts +4.4 %.
	# 31 / 5 (predicted +8.1 %) and 36 / 0 lift the inner front (4.8 / 6.1 deg). K at 0.15 g -0.10.
	"van": {"family": "car", "tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "com_y": 0.58, "anti_roll_rate": 24000.0, "anti_roll_rate_rear": 12000.0, "mu_lat": 0.88, "mass": 1600.0, "max_steer_deg": 32.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0, "brake_torque": 2000.0, "handbrake_torque": 1700.0},
	# `ride_lift` 0.08 on the flatbeds: their arches are drawn shallower than the tyre, so at the
	# flush ride height the rear wheels broke through the bed floor.
	# `yaw_index` 0.94, the measured pickups' median (docs/vehicles.md § Inertia): the empty bed
	# leaves the mass forward.
	"pickup": {"family": "car", "tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "yaw_index": 0.94, "anti_roll_rate": 14000.0, "anti_roll_rate_rear": -1.0, "rear_lat_grip": 1.08, "cornering_peak_load": 0.0, "ride_lift": 0.08, "mass": 1550.0, "torque_mul": 1.05, "max_steer_deg": 33.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0, "brake_torque": 2000.0, "handbrake_torque": 1700.0},
	"pickup-flat": {"family": "car", "tyre_fit": TyreClass.Fit.LIGHT_TRUCK, "yaw_index": 0.94, "anti_roll_rate": 14000.0, "anti_roll_rate_rear": -1.0, "rear_lat_grip": 1.08, "cornering_peak_load": 0.0, "ride_lift": 0.08, "mass": 1500.0, "torque_mul": 1.05, "max_steer_deg": 33.0, "driven_front": false, "driven_rear": true, "speed_limit_kmh": 180.0, "brake_torque": 2000.0, "handbrake_torque": 1700.0},
	# heavy vans: car family, van feel (VAN_BASE, not CAR_BASE) — these are 4-5 t vehicles
	"delivery": {"family": "car", "base": "van", "mass": 4200.0},
	"delivery-flat": {"family": "car", "base": "van", "com_y": 0.55, "ride_lift": 0.08, "mass": 4000.0},
	"ambulance": {"family": "car", "base": "van", "mass": 4800.0, "max_steer_deg": 24.0, "speed_limit_kmh": 150.0},
	# truck family (J1939) — garbage-truck first, matching VehicleCatalog's cycle order.
	# A front loader (the lift arms over the cab). `front_weight` 0.465 is an empty one's, sourced:
	# 7800 of 16760 kg on the steer axle (City of Barrie, Vehicle Loads on Structures, Appx B, 2022;
	# its empty rear and side loaders sit at 0.35 and 0.42). `com_y` 0.85 is an estimate (no measured
	# refuse-truck figure found): 0.48 of the 1.77 m body, over TRUCK_BASE's ~0.30 because the hopper
	# and arms sit high. Half-track 0.66 over it tips at ~0.78 g static, beside mu_lat 0.75.
	# On the toy 1.94 m wheelbase the front axle unloads fully at g * 0.465 * L / h = 1.06 g, clear of
	# the ~0.45 g the rear tyres push in gear 1.
	# Spring brakes 6500 Nm a wheel: under the 6820 Nm the service brake's split leaves on its lighter
	# rear drum (a spring chamber never out-torques its service chamber), still past the static rear
	# wheel's ~6000 Nm of grip, so they lock it.
	# Governed at 85 km/h, under the EU's 90 km/h heavy-truck limiter (a refuse collector usually
	# runs lower); the governor settles it at 83.5 (docs/drivetrain.md § Engine braking under a fuel
	# cut).
	"garbage-truck": {"family": "truck", "mass": 8000.0, "com_y": 0.85, "front_weight": 0.465, "handbrake_torque": 6500.0, "max_steer_deg": 22.0, "steer_speed": 1.6, "speed_limit_kmh": 85.0},
	# Emergency vehicles are exempt from the goods-vehicle limiter; 110 is the appliance's own
	# rating, where the governor settles it (108.2 km/h).
	"firetruck": {"family": "truck", "mass": 7500.0, "max_steer_deg": 22.0, "steer_speed": 1.6, "speed_limit_kmh": 110.0},
	# tractor family (ISOBUS) — one drivable body.
	# 40 km/h is type approval; gearing already lands on 39.6, so this limit never acts, but
	# catches a future gearing change that would make the body road-illegal.
	# `scale` 1.35 on the Kenney compact body: 2.99 x 2.17 m on a 2.12 m wheelbase, so the 5.5 t
	# spec sits on something the size of a tractor. What bounds it is not any gate (the field
	# fence leaves 13 m) but what does NOT scale with it: the three-point linkage, the four
	# implements and the 1.90 m farm tipper.
	# `mass` 7000 / `front_weight` 0.38 is a ballasted tractor: ~180 hp at ~39 kg/hp (a working
	# tractor of this power is 40-50). Ballast is traction, not torque: gear-1 wheel force against
	# rear axle grip is ~1.6x (4.3 t, 43 kN at mu 1.0), which the launch ramp meters. The torque
	# curve and `final_drive` stay untouched — low-end torque is what pulls a drawbar trailer away.
	# `com_y_frac` 0.32 of the body's AABB top (2.60 m on the scaled body) = 0.83 m over the road:
	# the 5.5 t machine's 0.91 m with 1.5 t of ballast at ~0.55 m (liquid in the rear tyres, hub
	# weights). A fraction, not a metre figure, because `scale` above may still move and the
	# fraction survives it.
	# `wheel_x_out` 0.214 sets the track: 1.62 m front / 1.79 m rear, a real tractor's 1.8-1.9 m
	# (the flush fit alone left 1.31 / 1.49, and the body rolled ~3 deg per jolt and tipped at
	# 0.84 g). Roll stiffness and roll damping both go as track squared, so this is the rocking
	# and the rollover fix in one: rear half-track 0.90 over 0.83 m is a static threshold of
	# ~1.08 g, at the lug tyres' slide. The tyres stand proud of the body, as a tractor's do.
	"tractor-kenney": {
		"family": "tractor", "mass": 7000.0, "front_weight": 0.38, "speed_limit_kmh": 40.0,
		"com_y_frac": 0.32, "scale": 1.35, "wheel_x_out": 0.214},
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
		var geo := _analyze(MODELS.path_join(variant + ".glb"), wheels,
				float(ov.get("scale", 1.0)))
		if geo.is_empty():
			continue
		var recipe := ov.duplicate()
		recipe["_id"] = variant
		var spec := _build_spec(String(ov.get("base", family)), recipe, geo, wheels)
		var spec_path := OUT_DIR.path_join(variant + "_spec.tres")
		if StableSave.save(spec, spec_path) != OK:
			push_error("failed to save " + spec_path)
			continue
		var scene_script: Variant = load(String(FAMILY_SCRIPTS.get(family, BASE_SCRIPT)))
		var scene := _build_scene(variant, scene_script, load(spec_path), geo)
		var scene_path := OUT_DIR.path_join(variant + ".tscn")
		if StableSave.save(scene, scene_path) != OK:
			push_error("failed to save " + scene_path)
			continue
		ok += 1
	print("gen_kenney_vehicles: wrote %d/%d variants" % [ok, VARIANTS.size()])
	print("collision shapes: ", ", ".join(_shape_report))
	print("resistance (frontal area measured off the body AABB, see FRONTAL_FILL):")
	for line: String in _drag_report:
		print("   ", line)
	print("brakes (Nm per wheel, declared hardware; see _brakes / BrakeSizing):")
	for line: String in _brake_report:
		print("   ", line)
	print("balance (predicted, BalanceModel; K and LLTD read beside `measure_vehicles -- <v> 60 step`):")
	for line: String in _balance_report:
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
	# com_y is a family figure a body may override; com_z is per body, from `front_weight`
	# (fraction of static weight on the front axle). com_z 0 is wherever Kenney put the
	# body origin, which spans 36/64 to 61/39 across these bodies — invisible under AWD (four
	# driven wheels carry any split), but decisive the moment a variant drives one axle: the
	# open-wheeler launched badly as a rear-driver because its origin was 58% front-heavy.
	spec.center_of_mass = Vector3(0, _com_y(get_f, geo, ov), _com_z(geo, ov))
	spec.yaw_dynamic_index = get_f.call("yaw_index")
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
	# Each axle's physics radius is its drawn tyre's; one scene per axle when they differ (tractor).
	var front_wheel: Dictionary = wheels[0]
	var rear_wheel: Dictionary = wheels[1]
	gd.wheel_scene = load(String(front_wheel["scene"])) as PackedScene
	if String(rear_wheel["scene"]) != String(front_wheel["scene"]):
		gd.wheel_scene_rear = load(String(rear_wheel["scene"])) as PackedScene
	gd.wheel_radius = float(front_wheel["radius"])
	# Left at 0 (= the front's) on equal radii, so those bodies' files do not move.
	if float(rear_wheel["radius"]) != gd.wheel_radius:
		gd.wheel_radius_rear = float(rear_wheel["radius"])
	gd.tyre_half_width = float(front_wheel["half"])
	if float(rear_wheel["half"]) != gd.tyre_half_width:
		gd.tyre_half_width_rear = float(rear_wheel["half"])
	gd.wheel_inertia =float(b["wheel_inertia"])
	gd.wheel_inertia_rear = float(b.get("wheel_inertia_rear", 0.0))
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
	gd.retarder_rating_nm = float(ov.get("retarder_rating_nm", b.get("retarder_rating_nm", 0.0)))
	gd.abs_equipped = get_flag.call("abs_equipped")
	gd.tcs_equipped = get_flag.call("tcs_equipped")
	gd.hill_hold = int(ov.get("hill_hold", b["hill_hold"])) as HillHold.Kind
	gd.hill_hold_s = get_f.call("hill_hold_s")
	gd.brake_engages_front_axle = get_flag.call("brake_engages_front_axle")
	# Differentials (Differential): per variant over a baseline of open (1.0) everywhere, and the
	# rigid centre is a driveline flag like the two above.
	gd.diff_bias_front = get_f.call("diff_bias_front")
	gd.diff_bias_rear = get_f.call("diff_bias_rear")
	gd.centre_diff_bias = get_f.call("centre_diff_bias")
	gd.centre_diff_rigid = get_flag.call("centre_diff_rigid")
	gd.rest_length = float(b["rest_length"])
	# A `ride_hz` baseline derives these once the wheel stations exist (`_derive_springs`).
	if not b.has("ride_hz"):
		gd.spring_rate = float(b["spring_rate"])
		gd.damper_bump = float(b["damper_bump"])
		gd.damper_rebound = float(b["damper_rebound"])
		gd.spring_rate_rear = float(b["spring_rate_rear"])
		gd.damper_bump_rear = float(b["damper_bump_rear"])
		gd.damper_rebound_rear = float(b["damper_rebound_rear"])
	gd.anti_roll_rate = get_f.call("anti_roll_rate")
	gd.anti_roll_rate_rear = get_f.call("anti_roll_rate_rear")
	gd.max_suspension_force = float(b["max_suspension_force"])
	gd.grip_curve = _grip_curve.duplicate()
	# The stock class and the size it is fitted in; the figures below are that class on dry asphalt.
	gd.tyre_fit = int(ov.get("tyre_fit", b["tyre_fit"])) as TyreClass.Fit
	gd.tyre = TyreCatalog.by_id(String(ov.get("tyre", b["tyre"])))
	if gd.tyre == null or not gd.tyre.fits_body(gd.tyre_fit):
		push_error("%s: stock tyre '%s' is unknown or not made in its fit" % [
				ov.get("_id", ""), ov.get("tyre", b["tyre"])])
	gd.mu_long = get_f.call("mu_long")
	gd.mu_lat = get_f.call("mu_lat")
	gd.rear_lat_grip = get_f.call("rear_lat_grip")
	gd.rear_twin_tyres = get_flag.call("rear_twin_tyres")
	# Family number, not a per-variant knob: baseline only, pinned by test_kenney_variants.
	gd.load_sensitivity = float(b["load_sensitivity"])
	# A family tyre figure too; a variant overrides it only to hold the law off (VARIANTS' interim
	# 1.08 bodies).
	gd.cornering_peak_load = get_f.call("cornering_peak_load")

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
	spec.engine_brake_frac = float(b["engine_brake_frac"])
	spec.engine_friction_frac = float(b["engine_friction_frac"])
	spec.shift_cut_s = get_f.call("shift_cut_s")
	spec.launch_engage_s = float(b["launch_engage_s"])
	# The crank is per engine (the sports pair, the open-wheelers), the coupling per gearbox (the
	# open-wheelers' sequential); the rating and launch target are the class's.
	spec.engine_inertia = get_f.call("engine_inertia")
	spec.coupling = int(ov.get("coupling", b["coupling"])) as VehicleSpec.Coupling
	spec.clutch_reserve = float(b["clutch_reserve"])
	spec.converter_stall_ratio = float(b["converter_stall_ratio"])
	spec.lockup_gear = int(b["lockup_gear"])
	spec.launch_rpm_over_idle = float(b["launch_rpm_over_idle"])
	spec.shift_up_rpm = float(b["shift_up_rpm"])
	spec.shift_down_rpm = float(b["shift_down_rpm"])
	# The part-pedal map and the shift's handover are the gearbox's, per variant like `coupling`:
	# the open-wheelers' sequential keeps full-pedal shifting and closes at its rating.
	spec.shift_up_light_rpm = get_f.call("shift_up_light_rpm")
	spec.shift_down_light_rpm = get_f.call("shift_down_light_rpm")
	spec.kickdown_pedal = get_f.call("kickdown_pedal")
	spec.shift_dwell_s = get_f.call("shift_dwell_s")
	spec.shift_handover_s = get_f.call("shift_handover_s")
	spec.skip_shifts = bool(b["skip_shifts"])
	spec.start_gear_max = int(b["start_gear_max"])
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
	gd.ackermann = get_f.call("ackermann")
	gd.min_steer_frac = get_f.call("min_steer_frac")
	gd.steer_falloff_speed = get_f.call("steer_falloff_speed")

	var susp := _suspension_recipe(b, ov)
	var sag := _static_sag(susp, spec, gd)
	gd.wheel_positions = _wheel_positions(geo, gd, sag, float(ov.get("wheel_x_out", 0.0)),
			float(ov.get("ride_lift", 0.0)))
	if susp.has("ride_hz"):
		_derive_springs(spec, gd, susp)
	_derive_link_slopes(spec, gd, susp, sag)
	_brakes(spec, gd, get_f, String(ov.get("_id", "")), sag)
	_balance(spec, String(ov.get("_id", "")))

	spec.headlight_paths.assign(_lamp_paths["headlight_paths"])
	spec.head_lamp_paths.assign(_lamp_paths["head_lamp_paths"])
	spec.brake_lamp_paths.assign(_lamp_paths["brake_lamp_paths"])
	spec.turn_left_paths.assign(_lamp_paths["turn_left_paths"])
	spec.turn_right_paths.assign(_lamp_paths["turn_right_paths"])
	return spec


## The baseline with the variant's `ride_hz` over it, the one suspension key a variant may override
## (it only re-derives on a `ride_hz` baseline).
func _suspension_recipe(b: Dictionary, ov: Dictionary) -> Dictionary:
	var susp := b.duplicate()
	if ov.has("ride_hz") and b.has("ride_hz"):
		susp["ride_hz"] = ov["ride_hz"]
	return susp


## Spring compression (m) at rest the wheel stations are built around: `g / (2 pi ride_hz)^2` on a
## `ride_hz` baseline, where every axle sags alike, else the even corner's `mass / 4 * g /
## spring_rate`. Held under 0.8 of the travel.
func _static_sag(b: Dictionary, spec: VehicleSpec, gd: GroundDriveSpec) -> float:
	var sag := GRAVITY / pow(TAU * float(b["ride_hz"]), 2.0) if b.has("ride_hz") \
			else spec.mass / 4.0 * GRAVITY / gd.spring_rate
	return clampf(sag, 0.0, gd.rest_length * 0.8)


## FL, FR, RL, RR hub anchors at the Kenney model's own wheel positions (body space), so RayWheel
## visuals sit in the wheel wells. Each axle's anchor Y puts its hub at its own radius above
## ground at the static `sag`, so the body rests level. `x_out` pushes a
## corner further outboard (open-wheelers), widening suspension and visual track together.
## `ride_lift` drops the anchors, which raises the chassis that far over the wheels at
## equilibrium: purely a fit knob for a body whose arches are drawn too shallow for the tyre.
func _wheel_positions(geo: Dictionary, gd: GroundDriveSpec, sag: float, x_out: float,
		ride_lift := 0.0) -> PackedVector3Array:
	var fl := Vector3.ZERO
	var fr := Vector3.ZERO
	var rl := Vector3.ZERO
	var rr := Vector3.ZERO
	for xz: Vector2 in geo["wheel_xz"]:
		var y := gd.axle_radius(RayWheel.is_rear_z(xz.y)) + gd.rest_length - sag - ride_lift
		var p := Vector3(xz.x + signf(xz.x) * x_out, y, xz.y)  # body space (front = -Z, right = +X)
		if p.z < 0.0:
			if p.x < 0.0: fl = p
			else: fr = p
		else:
			if p.x < 0.0: rl = p
			else: rr = p
	return PackedVector3Array([fl, fr, rl, rr])


## The declared brake hardware (Nm per wheel; a variant overrides its baseline's class), with only
## the axle split derived (`_front_brake_share`). `_brake_report` prints what `BrakeSizing` makes
## of it: capacity against the tyre, the stall hold, the rear lock and the parking grade;
## `test_vehicle_catalog` is the authoritative check.
func _brakes(spec: VehicleSpec, gd: GroundDriveSpec, get_f: Callable, id: String,
		sag: float) -> void:
	gd.brake_torque = get_f.call("brake_torque")
	gd.handbrake_torque = get_f.call("handbrake_torque")
	gd.park_pawl_torque = get_f.call("park_pawl_torque")
	# Rear-axle brakes that engage the front axle share through the shaft, not a split.
	gd.brake_bias_front = 0.0 if gd.brake_engages_front_axle \
			else _front_brake_share(spec, gd, sag)
	_brake_report.append(("%-16s %6.0f / hand %5.0f / pawl %5.0f: %.2f g (%.2fx the tyre), "
			+ "%.0f%% front, stall hold %.2f, rear lock %.2f, parks %.0f%%")
			% [id, gd.brake_torque, gd.handbrake_torque, gd.park_pawl_torque,
			BrakeSizing.capacity_g(spec), BrakeSizing.capacity_g(spec) / gd.mu_long,
			gd.brake_bias_front * 100.0, BrakeSizing.stall_hold_margin(spec),
			BrakeSizing.rear_lock_ratio(spec), BrakeSizing.park_grade(spec) * 100.0])


## What `BalanceModel` predicts of the body's handling: the understeer gradient at BALANCE_G (the
## step pass's 30 km/h reading), the front share of the lateral load transfer, and the steady-state
## limit with the axle that saturates first and the roll there.
func _balance(spec: VehicleSpec, id: String) -> void:
	var m := BalanceModel.axles(spec)
	if m.is_empty():
		_balance_report.append("%-16s not predicted (no single front and rear pair)" % id)
		return
	var lim := BalanceModel.limit(m)
	# The damping term needs a declared yaw inertia; Jolt computes the rest only at runtime.
	var damped := BalanceModel.yaw_damping_gradient(m, BALANCE_G, 30.0 / 3.6)
	_balance_report.append(("%-16s K %.2f deg/g at %.2f g (%s angular damping at 30 km/h), "
			+ "LLTD %.0f %%; limit %.2f g, %s first (front %.2f / rear %.2f g, %+.1f %%), roll %.1f deg there")
			% [id, BalanceModel.understeer_gradient(m, BALANCE_G), BALANCE_G,
			"-" if is_nan(damped) else "%+.2f" % damped,
			BalanceModel.lltd(m) * 100.0, lim["g"],
			"front" if float(lim["margin"]) >= 0.0 else "rear", lim["front"], lim["rear"],
			float(lim["margin"]) * 100.0, BalanceModel.roll_deg(m, lim["g"])])


## The front axle's share of the foot brake (`GroundDriveSpec.brake_bias_front`): its share of
## what the two axles can hold in a full-pedal stop. Each axle's load is its static share plus the
## `a * h / L` the stop moves forward, and its grip is load-scaled as RayWheel scales it
## (`load_scaled_mu`: the loaded front loses mu, the unloaded rear gains it); `a` is what full pedal
## asks, held to what the tyres can give, settled by a few passes. So both axles reach their limit
## together: an even split under-brakes the front and locks the rear first.
func _front_brake_share(spec: VehicleSpec, gd: GroundDriveSpec, sag: float) -> float:
	var ax := _axles(spec, gd)
	if ax.is_empty():
		return -1.0  # no axle pair: every wheel alike
	var wheelbase: float = ax["wheelbase"]
	var n_front: int = ax["n_front"]
	var n_rear: int = ax["n_rear"]
	var h := _com_height(spec, gd, sag)
	var weight := spec.mass * GRAVITY
	var ref_load := weight / gd.wheel_positions.size()  # RayWheel's: corner_mass * g
	var static_front: float = ax["static_front"]
	var asked := gd.brake_torque * (n_front / gd.axle_radius(false)
			+ n_rear / gd.axle_radius(true)) / weight  # in g
	var decel := asked
	var cap_front := 0.0
	var cap_rear := 0.0
	for _pass in 4:
		var n_f := clampf(static_front + decel * h / wheelbase, 0.0, 1.0) * weight
		var n_r := weight - n_f
		cap_front = n_f * RayWheel.load_scaled_mu(gd.mu_long, n_f / n_front, ref_load,
				gd.load_sensitivity)
		cap_rear = n_r * RayWheel.load_scaled_mu(gd.mu_long, n_r / n_rear, ref_load,
				gd.load_sensitivity)
		decel = minf(asked, (cap_front + cap_rear) / weight)
	var share := cap_front / maxf(cap_front + cap_rear, 1e-6)
	# Thousandths, rounded so the stored float is the plain decimal.
	return roundf(clampf(share, 0.05, 0.95) * 1000.0) / 1000.0


## The axle pair off the wheel stations (front = -Z): `wheelbase`, wheels per axle and the static
## share of weight on the front (`static_front`, off COM.z). Empty when there is no pair.
func _axles(spec: VehicleSpec, gd: GroundDriveSpec) -> Dictionary:
	var front_z := INF
	var rear_z := -INF
	var n_rear := 0
	for p in gd.wheel_positions:
		if RayWheel.is_rear_z(p.z):
			rear_z = maxf(rear_z, p.z)
			n_rear += 1
		else:
			front_z = minf(front_z, p.z)
	var n_front := gd.wheel_positions.size() - n_rear
	var wheelbase := rear_z - front_z
	if not is_finite(wheelbase) or wheelbase <= 0.0 or n_front == 0 or n_rear == 0:
		return {}
	return {"wheelbase": wheelbase, "n_front": n_front, "n_rear": n_rear,
			"static_front": (rear_z - spec.center_of_mass.z) / wheelbase}


## The COM's height over the road at rest (m): each anchor sits its axle's `radius + rest_length -
## sag` above it (_wheel_positions); [0] is a front one.
func _com_height(spec: VehicleSpec, gd: GroundDriveSpec, sag: float) -> float:
	return spec.center_of_mass.y + gd.axle_radius(false) + gd.rest_length - sag \
			- gd.wheel_positions[0].y


## Per-axle springs and dampers off the baseline's `ride_hz` / `zeta_bump` / `zeta_rebound`: each
## axle's corner mass `m` is its static share of the weight, its rate `m * omega^2` and each damper
## `zeta * 2 m omega` (critical `2 sqrt(k m)` at that rate). A real car is sprung to a ride
## frequency, not a rate, so a heavier body or axle stands at the saloon's sag instead of sitting
## in its bump travel; every axle sagging alike keeps the body level (`_static_sag`).
func _derive_springs(spec: VehicleSpec, gd: GroundDriveSpec, b: Dictionary) -> void:
	var omega := TAU * float(b["ride_hz"])
	var ax := _axles(spec, gd)
	var front_m := spec.mass / maxf(gd.wheel_positions.size(), 1.0)
	var rear_m := front_m
	if not ax.is_empty():
		front_m = spec.mass * float(ax["static_front"]) / float(ax["n_front"])
		rear_m = spec.mass * (1.0 - float(ax["static_front"])) / float(ax["n_rear"])
	gd.spring_rate = roundf(front_m * omega * omega)
	gd.spring_rate_rear = roundf(rear_m * omega * omega)
	gd.damper_bump = roundf(float(b["zeta_bump"]) * 2.0 * front_m * omega)
	gd.damper_rebound = roundf(float(b["zeta_rebound"]) * 2.0 * front_m * omega)
	gd.damper_bump_rear = roundf(float(b["zeta_bump"]) * 2.0 * rear_m * omega)
	gd.damper_rebound_rear = roundf(float(b["zeta_rebound"]) * 2.0 * rear_m * omega)


## `GroundDriveSpec.anti_dive_slope` / `anti_squat_slope` off the baseline's `anti_dive` /
## `anti_squat` shares: 100 % is the slope `h / wheelbase` at which that axle's links carry its
## whole load transfer and its springs none. Thousandths, so a regen writes a stable file.
func _derive_link_slopes(spec: VehicleSpec, gd: GroundDriveSpec, b: Dictionary, sag: float) -> void:
	var ax := _axles(spec, gd)
	if ax.is_empty():
		return
	var full := _com_height(spec, gd, sag) / float(ax["wheelbase"])
	gd.anti_dive_slope = roundf(float(b["anti_dive"]) * full * 1000.0) / 1000.0
	gd.anti_squat_slope = roundf(float(b["anti_squat"]) * full * 1000.0) / 1000.0


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
		child.owner = null
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
##              scale * the variant's own `scale` + x/z centring on the body, native y = 0 kept
##              (the wheel-contact plane). Everything downstream measures the body through this
##              transform — drag_area, com_z and the wheel stations all follow a `scale` for free,
##              and so does the ride height, since _wheel_positions derives anchor Y from
##              each axle's radius and rest_length rather than off the model.
##   wheel_xz:  the four wheels' body-space (x, z). z is the Kenney wheel z; x is the flush
##              rule below (never inset from the authored position).
##   body_pairs: [Mesh, native transform] for the wheel-less body (collision hull source)
##   box:       body_aabb transformed by xform (lamp placement + hull fallback)
func _analyze(path: String, wheel_models: Array, scale := 1.0) -> Dictionary:
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
	var body_scale := KIT_SCALE * scale
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * body_scale)
	var xform := Transform3D(basis, Vector3(body_scale * c.x, 0.0, body_scale * c.z))

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
	# One track for the whole body: a Kenney body flares its front fender and tucks the rear
	# arch, so the flush rule alone stands the front wheels out and sinks the rear ones in --
	# visibly mismatched on a road vehicle. Average the four into a single half-width. A body
	# whose axles wear DIFFERENT wheel models (the tractor) is deliberately narrow at the front
	# and keeps its per-axle stations.
	if wheel_models[0]["scene"] == wheel_models[1]["scene"]:
		var mean_x := 0.0
		for xz: Vector2 in wheel_xz:
			mean_x += absf(xz.x)
		mean_x /= maxf(float(wheel_xz.size()), 1.0)
		for i in wheel_xz.size():
			var xz: Vector2 = wheel_xz[i]
			wheel_xz[i] = Vector2(signf(xz.x) * mean_x, xz.y)

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
## (0 where it says nothing). Measured off THIS
## body's own axle line, so the same declared split means the same handling on every wheelbase.
## COM height over the road. `com_y_frac` is the same figure expressed as a fraction of the
## body's own AABB top, for a body whose `scale` may still move (the tractor): the fraction is
## what stays true across a rescale, the metre figure is not.
func _com_y(get_f: Callable, geo: Dictionary, ov: Dictionary) -> float:
	if not ov.has("com_y_frac"):
		return float(get_f.call("com_y"))
	var box: AABB = geo["box"]
	return float(ov["com_y_frac"]) * box.end.y


func _com_z(geo: Dictionary, ov: Dictionary) -> float:
	if not ov.has("front_weight"):
		return 0.0
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
