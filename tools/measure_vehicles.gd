extends Node3D
## Drives a vehicle down a flat full-grip strip and reports acceleration, top speed and
## straight-line tracking, plus an opt-in cornering pass on a skid pad. Game-mode tool scene
## (needs autoloads + a physics step).
## `track strict` is the CI gate and exits nonzero on a FAIL; the accel/top-speed report
## always exits 0.
## Driven through the bridge stash, as measure_semi_launch / measure_grade / measure_rough are: the
## keyboard path shapes its keys (src/input/key_shaper.gd), which would measure the shaper instead of
## the vehicle.
## `tyre=<id>` fits that `TyreCatalog` class on each body (`MeasureRig.fit_tyre`; the stock where it
## is not made in the body's fit); `surface=<name>` paints every slab one `Surface`
## (`MeasureRig.GripPatch`). Without it the slabs are bare ground, which reads the tyre's asphalt.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")

const STRIP_LENGTH := 6000.0

## A body that reaches an edge is flagged, never measured silently.
const STRIP_WIDTH := 40.0
const START_Z := 2800.0      ## spawn near one end; the body faces -Z, so it runs the length
## Metres of strip ahead of the spawn; using all of it means the run ran out of road.
const RUN_LENGTH := START_Z + STRIP_LENGTH * 0.5
const DEFAULT_SECONDS := 90.0

## Top speed is called once gains stop meaningfully over SETTLE_WINDOW; relative threshold
## since the approach to terminal speed is asymptotic.
const SETTLE_REL := 0.002     ## fraction of current speed gained over the window
const SETTLE_ABS := 0.02      ## m/s floor, so a near-stationary vehicle still terminates
const SETTLE_WINDOW := 3.0    ## s

# --- tracking pass ---------------------------------------------------------
## Measured from a latched origin once up to speed, so the launch transient is not counted as drift.
const TRACK_START_SPEED := 16.7   ## m/s (~60 km/h) before the origin is latched
const TRACK_DISTANCE := 200.0     ## m of straight running measured after that
## Set well above what shipped vehicles do; a FAIL means a real asymmetry (docs/vehicle_measurements.md).
const MAX_LATERAL_DRIFT := 1.0    ## m off the latched forward axis over TRACK_DISTANCE
const MAX_HEADING_DRIFT := 1.0    ## deg of heading change over the same stretch
## Ticks the whole front axle may spend off the ground over the pass, launch included: a wheelie.
## The Kenney wheelbases are toy-scale under real COM heights (docs/vehicles.md § Pitch), so a COM
## or damper edit can tip a rear-driven body onto its rear axle with no other test noticing.
const MAX_FRONT_LIFT_TICKS := 0
## Variants whose tracking FAIL is a KNOWN, open defect: still measured, still printed as FAIL,
## but excluded from `strict`'s exit code so one unfixed body does not block every deploy. A
## variant that is not on this list gates CI as before, so a NEW asymmetry still turns the job
## red. Each entry names the plan that owns the fix; delete the entry with the plan. Empty today.
const KNOWN_TRACKING_FAILS: Array[String] = []

# --- coast-down pass (opt-in: pass the `coast` flag) ----------------------
## Cuts throttle at settled top speed and measures the deceleration. The gear byte stays D, so
## the engine's overrun stays in: it is printed beside the declared resistance
## model `0.5 * 1.225 * drag_area * v^2 + crr * m * g` (the fitted tyre's crr, `MeasureRig.crr`),
## both averaged per tick.
## Also reports chassis contacts: RayWheel is a raycast, so any contact is the hull scraping.
const COAST_SECONDS := 5.0

# --- cornering pass (opt-in: pass the `corner` flag) ----------------------
## The only lateral measurement there is — the tracking pass runs at zero steer, so nothing else
## can see a grip change that only shows up in a corner. Holds a speed, then winds the lock on
## until the tyres give up, and reports the peak lateral acceleration with the axle that
## saturated first. Off by default: CI needs only the tracking gate.
const CORNER_SPEED := 11.11        ## m/s (~40 km/h) held through the pass
const CORNER_RAMP_S := 10.0        ## s from zero steer to full lock
const CORNER_SMOOTH_S := 0.25      ## exponential smoothing on the lateral-g reading
## Past this slip angle the body is sliding, not cornering: `v * yaw_rate` there measures a spin,
## not a grip limit, so the peak stops being sampled and the report says the gate tripped.
const CORNER_MAX_SLIP_ANGLE := 0.5  ## |v_lat| / |v|
## The speed hold is a PI pedal, never bang-bang: full-pedal pulses through a torque-biasing diff
## send the whole engine to the slower wheel or axle, and the pass then reads power-on oversteer
## instead of grip (`race` spun at a reported 1.62 g; the SUV's rear saturated first).
const CORNER_PEDAL_KP := 0.8       ## pedal per m/s of speed error
const CORNER_PEDAL_KI := 0.5       ## pedal per second per m/s of speed error
const CORNER_PEDAL_START := 0.35   ## integral seed when the ramp begins, roughly a car's cruise
## On ice (grip 0.12) the run-up to CORNER_SPEED takes ~50 m and the circle is ~100 m in radius.
const PAD_SIZE := 600.0
const PAD_X := -500.0              ## clear of the strip's +/- STRIP_WIDTH / 2 and the step pad

# --- braking pass (opt-in: pass the `brake` flag) --------------------------
## Straight stops on the strip, one per pedal in BRAKE_PEDALS: full throttle up to BRAKE_SPEED (or
## 90 % of the top the accel pass found, whichever is lower), then throttle off and the pedal held
## to a stop. Reports distance, mean deceleration, the seconds any wheel of the rig spent past
## BRAKE_LOCK_SLIP (skidding rather than rolling), and the seconds any wheel's ABS held it back.
const BRAKE_SPEED := 27.78         ## m/s (100 km/h)
const BRAKE_PEDALS: Array[float] = [0.3, 0.6, 1.0]
const BRAKE_LOCK_SLIP := 0.3
const BRAKE_STOP_SPEED := 0.3      ## m/s counted as stopped

## --- both pedals at stall (`stall`, instead of every other pass) ---
## Settles on the full foot brake, then floors the throttle against it in manual D1 (the worst gear;
## the automatic box would start the tractor in D3) with traction control off (the ideal TC takes
## the drive back at a standstill, so it would measure the TC, not the brake), and reports how far
## the body moved, its peak speed and the driven wheels' peak spin. `InputRouter.brake_override`
## latches only past BRAKE_OVERRIDE_SPEED, so a body that holds never reaches it: a latch is
## reported as a failure to hold, never hidden.
const STALL_SETTLE_S := 1.5
const STALL_HOLD_S := 10.0
## --- handbrake turn (`handbrake`, instead of every other pass) ---
## Up to HB_SPEED on the strip, then a HB_STEER step with the throttle lifted, held HB_HOLD_S and
## released straight for HB_AFTER_S: once with the steer alone, once with the handbrake pulled
## over the same window. Reports the rear wheels' locked time, peak yaw rate and heading change.
const HB_SPEED := 16.67            ## m/s (60 km/h)
const HB_STEER := 30.0             ## % of lock, + = right
const HB_HOLD_S := 1.0
const HB_AFTER_S := 1.5
## --- step steer (`step`, instead of every other pass) ---
## At each speed of the body's STEP_SETS row (run up floored, then STEP_SETTLE_S on the PI pedal,
## CORNER_PEDAL_KP / _KI), the bridge steer is stepped in one tick to each of STEP_LOCKS and held
## STEP_HOLD_S: once with the PI pedal still holding the entry speed, once with the pedal lifted on
## the step. The body's own `steer_speed` slews the wheels behind the input, as for a driver.
## Reports the steady yaw rate (mean of the last STEP_STEADY_S) against the neutral-steer
## `v * delta / L` off the bicycle angle (under 1 understeers), the rise to 90 % of
## it, the overshoot past it, the peak body slip and roll, the most wheels lifted at once, a spin
## (slip past STEP_SPIN_DEG) and a rollover (up axis past STEP_ROLL_DEG from vertical).
const STEP_SETS := {
	"car": [30.0, 60.0, 100.0],
	"truck": [30.0, 50.0, 70.0],
	"tractor": [15.0, 25.0, 34.0],
}
const STEP_LOCKS: Array[float] = [10.0, 20.0, 30.0]  ## % of lock, + = right
const STEP_SETTLE_S := 3.0
const STEP_HOLD_S := 3.0
const STEP_STEADY_S := 0.5
## `chatter_runs`: the consecutive sign flips that count as a tick-rate oscillation, and the
## smallest tick-to-tick change read as a direction: CHATTER_EPS (rad), or CHATTER_REL of the
## angle. Contact noise in the latched compressions flips at 0.1-2 µrad on a 2-5 mrad angle
## (`sedan`, 2026-10-19) and does not grow with the coefficient; a ringing loop's swing scales with it.
const CHATTER_FLIPS := 3
const CHATTER_EPS := 1e-7
const CHATTER_REL := 0.01
const STEP_RISE := 0.9
const STEP_SPIN_DEG := 20.0
const STEP_ROLL_DEG := 45.0
## The strip is 40 m wide; a 3 s step at 100 km/h and 0.8 g travels ~35 m sideways.
const STEP_PAD_WIDTH := 400.0
## --- full-lock circle (`circle`, instead of every other pass) ---
## Full right lock from a standstill on the PI pedal (CORNER_PEDAL_KP / _KI) at CIRCLE_SPEED,
## CIRCLE_SETTLE_S to settle, then averaged over CIRCLE_HOLD_S: the rear axle centre's speed over
## the yaw rate (the radius driven) against `L / tan δ` off the bicycle angle, and each steered
## wheel's slip angle off its contact velocity (+ = it points further into the turn than its patch
## travels): the front scrub Ackermann removes. Every body runs with no attachment unless `trailer=`
## names one.
const CIRCLE_SPEED := 1.39         ## m/s (5 km/h)
const CIRCLE_LOCK := 100.0         ## % of lock, + = right
const CIRCLE_SETTLE_S := 8.0
const CIRCLE_HOLD_S := 4.0
## --- hitch statics (`hitch`, instead of every other pass) ---
## Parked on the foot brake and the lever, a body with three-point implements is read bare, then per
## implement (`trailer=` names one; else every carried one) at each of HITCH_STAGES. A reading waits
## HITCH_WAIT_S (the linkage's 1.5 s stroke and the settle), then averages HITCH_AVG_S: each axle's
## summed `suspension_force` (kg) against the statics off the live mass and COM; the front change
## from bare against `m e / L` off the implement point the live COM implies; the front share against
## HITCH_FRONT_MIN; and the body-frame tensor diagonal against the composite (the bare tensor plus
## parallel-axis terms for the bare mass and a point implement), the gap Jolt's COM-shift leaves.
const HITCH_WAIT_S := 4.0
const HITCH_AVG_S := 1.0
## Ballasting minimum: at least 20 % of total weight on the front axle to keep the tractor
## steerable (John Deere operator's manual, "Select Ballast Carefully").
const HITCH_FRONT_MIN := 0.20
## `hitch_pos` per reading: the bottom stop, raised, lowered again.
const HITCH_STAGES: Array[float] = [0.0, 100.0, 0.0]
## --- draft (`plough`, instead of every other pass) ---
## The strip answers as level 1's field (`FieldStrip`), so draft acts. Per draft-relevant implement
## (`trailer=` names one; else each), lowered at rest for HITCH_WAIT_S, then each of PLOUGH_KMH
## held on the circle's PI pedal for PLOUGH_SETTLE_S and averaged over PLOUGH_AVG_S: the draft (N,
## `TractorVehicle.draft_applied`; the `draft_force` dial beside it) against its D497 figure at the speed held, `engine_load`,
## `wheel_slip`, `axle_load`, the front share, gear and rpm. Then braked to a stop, held
## PLOUGH_STOP_S, and floored from rest for PLOUGH_START_S with the implement down: every shift as
## it lands, a trace line every PLOUGH_TRACE_S, and the hunting gate. With `trace[=n]` the start's
## first `trace_s=` seconds print a line every n ticks instead (`_plough_trace_line`).
const PLOUGH_KMH: Array[float] = [3.0, 7.0, 10.0]
const PLOUGH_SETTLE_S := 8.0
const PLOUGH_AVG_S := 3.0
const PLOUGH_STOP_S := 2.0
const PLOUGH_START_S := 15.0
const PLOUGH_TRACE_S := 0.5
## `plough course`: the strip answers as tractor_plough's course instead (`FieldStrip`), measured
## off the course scene and `gen_farm_playground.gd` by distance ahead of the course's Spawn: its
## light bands mix Field with Sand at LIGHT_SOIL_MIX. Per COURSE_RUNS entry (km/h, `hitch_pos`):
## respawned, the plough set at rest for HITCH_WAIT_S, then the PI pedal on a setpoint ramped at
## COURSE_RAMP to the run's speed, through the Row to its Exit: `engine_load` and the
## `draft_force` dial, mean, least and most inside the Row on full soil and on a band (the soil at
## the hitch point; telemetry lags it a tick), each extreme's distance into the Row, gear and rpm;
## every shift in the Row.
const COURSE_SCENE := "res://src/levels/island/level_1/courses/tractor_plough_course.tscn"
const FarmPlayground := preload("res://tools/gen_farm_playground.gd")
const COURSE_RUNS: Array[Vector2] = [Vector2(3.0, 0.0), Vector2(5.0, 0.0), Vector2(7.0, 0.0),
		Vector2(9.0, 0.0), Vector2(7.0, 100.0), Vector2(16.0, 100.0)]
const COURSE_RAMP := 0.5           ## m/s², the tractor's CRUISE_SETS ramp
const COURSE_TIMEOUT_S := 120.0
## --- kerb (`kerb`, instead of every other pass) ---
## Square steps across the strip: how the contact (`RayWheel`) meets an edge. At each of
## KERB_HEIGHTS a raised plateau is crawled square on at KERB_CRAWL (the circle's PI pedal, braked past it: a converter's creep outruns it), coasted
## square on from KERB_COAST (run up floored, the
## pedal lifted as the plateau is laid) and crawled at KERB_OBLIQUE_DEG; every run also takes the
## step down at its far edge. The plateau is laid once the run-up settles, its edge KERB_LEAD_CRAWL /
## _COAST ahead of the foremost hub, `wheelbase + KERB_TOP` long. Per wheel and edge, from KERB_LATCH
## out to KERB_CLEAR past: the hub's distance ahead of the edge along the heading when its contact
## first sits on the new level (`contact_point` over half the step, or under it on the step down)
## and the contact normal's lean from vertical then, the peak lean, the largest one-tick compression
## change, and its peak spring force against `max_suspension_force`. Per edge: the speed at the first
## contact, the least until every hub is KERB_CLEAR past, and then; the peak vertical acceleration at
## the COM; the time from the first contact to every hub clear. STUCK is measure_rough's rule.
const KERB_HEIGHTS: Array[float] = [0.12, 0.20]  ## the road tiles' curb, and a taller step
const KERB_CRAWL := 1.0            ## m/s
const KERB_COAST := 8.33           ## m/s (30 km/h)
const KERB_OBLIQUE_DEG := 30.0
const KERB_SETTLE_S := 3.0         ## s of crawl before the plateau is laid
const KERB_LEAD_CRAWL := 3.0       ## m from the foremost hub to the edge, as laid
const KERB_LEAD_COAST := 15.0
const KERB_TOP := 10.0             ## m of plateau past the wheelbase
const KERB_WIDTH := 80.0           ## m along the edge, past the strip either side at 30 degrees
const KERB_LATCH := 1.0            ## m out from the edge where each wheel's window opens
const KERB_BRAKE_GAIN := 1.0       ## crawl brake per m/s over KERB_CRAWL
const KERB_CLEAR := 0.5            ## m past the edge that counts a hub as over it
const KERB_STUCK_S := 5.0
const KERB_STUCK_PROGRESS := 0.25  ## m of progress that resets the stuck clock
const KERB_TIMEOUT_S := 60.0

# --- launch breakdown (accel pass) -----------------------------------------
## Where the time to each LAUNCH_MARKS mark goes, in seconds since the pass began. The buckets
## overlap (a spinning wheel can be in the fuel cut too), except `torque-bound`, which excludes the
## rest: pedal floored, no cut, every driven wheel on the ground under the grip peak, so the tyres
## had grip to spare and more torque would have bought speed. Its `stall` share has the wheel side
## under the launch target (`Drivetrain.launch_target_rpm` at full pedal): the only ticks converter
## torque multiplication could act in.
const LAUNCH_MARKS: Array[float] = [50.0, 100.0]
## Slip that counts as wheelspin: well past the 0.12 grip peak, so `tc` holding the peak reads none.
const SPIN_SLIP := 0.2
const LAUNCH_FLOORED := 0.98       ## pedal at or above this is floored
const TcPedal := preload("res://tools/tc_pedal.gd")

# --- launch trace (`trace`, accel pass) ------------------------------------
## A per-tick line of the launch (`_trace_line`) and the launch gates, judged over the launch: to the
## last LAUNCH_MARKS mark, to the held gear's full-pedal upshift point (`ShiftPolicy.upshift_rpm`)
## on road speed under `gear=`, or to the end of the pass for a body that never gets there (the
## 40 km/h tractor, traced to its top). The gates are a report of what reads as wrong from the
## seat, never CI.
## On the foot brake first, so the front axle's parked load is a settled one (and a trailer couples).
const TRACE_SETTLE_S := 1.5
const TRACE_PRINT_S := 3.0         ## default `trace_s=`: seconds of lines printed
## Two shifts closer than this read as one busy shift.
const GATE_MIN_GEAR_S := 1.0
## An upshift lands (road speed, new gear) at least this far over the downshift point at the pedal
## it was taken at (`ShiftPolicy.down_rpm`), or the box would hunt back down: the policy's own floor.
const GATE_LANDING_MARGIN := ShiftPolicy.LANDING_MARGIN
## The front axle's share of its parked load falls past what steady transfer predicts
## (`_transfer_share`), once the gap is cleared of road resistance, the trace's tick-late
## acceleration and the pitched pose's steady lean (`_gap_split`'s `over`), by at most what a body
## damped at GATE_XFER_ZETA overshoots a step of the event's own swing (the steady share's change
## since the event began), and never less than this floor (in shares, 0.05 = 5 points). So the gate
## judges damping and the drive's shape; a short, tall body's larger swing is its footprint's.
const GATE_XFER_GAP := 0.05
## The reference damping ratio: the low end of the road band (0.3-0.4 of critical, § Pitch). A step
## overshoots `exp(-ζπ / sqrt(1 - ζ²))` of itself, 37 % here; a ramped drive overshoots less.
const GATE_XFER_ZETA := 0.3
## The pitch-per-g reading averages the launch gear's middle stretch, this share of its time
## dropped at each end: the take-up's pitch ring before it, the shift's handover after.
const PITCH_TRIM := 0.25

# --- part-pedal probes (`cruise`, `kickdown`, `pulse`, instead of every other pass) ----------
## Each runs at every speed of the body's CRUISE_SETS row, from a standstill, in automatic D: the
## PI pedal (CORNER_PEDAL_KP / _KI) follows a setpoint ramped from the speed it is at to the target
## at the row's m/s², then holds it until the speed stays within CRUISE_TOL for CRUISE_SETTLE_S with
## no shift; that settle prints the cruise line (gear, rpm, pedal and `engine_load` averaged over
## it). `kickdown` then steps the pedal to 1 until KICK_GAIN_KMH more; `pulse` (re-settled first)
## drives the hold's PI pedal as on/off for PULSE_S, its duty latched at each period's start (or
## fixed by `duty=`): a keyboard holding a speed, the worst case. A row's speeds within
## GOVERNOR_BAND of a governor are dropped (its fade would hold them, not the pedal). Every window
## (approach and hold, kick, pulse) gets the hunting, landing and limiter gates.
const CRUISE_SETS := {
	"car": {"kmh": [50.0, 60.0, 90.0, 100.0, 120.0], "ramp": 1.0},
	"truck": {"kmh": [30.0, 50.0, 70.0, 85.0], "ramp": 0.5},
	"tractor": {"kmh": [15.0, 25.0, 34.0], "ramp": 0.5},
}
const CRUISE_TOL := 0.3            ## m/s off the target that still counts as held
const CRUISE_SETTLE_S := 5.0
const KICK_GAIN_KMH := 20.0
const PULSE_PERIOD_S := 1.0        ## default `pulse=<s>`
const PULSE_S := 30.0              ## s of pulsing at each speed
## `xwind[=<m/s>]` (with `cruise`): one speed per family, settled in the `wind=` flag's air (still by
## default), then a steady crosswind from the body's right for XWIND_S, pedal held at the settle's
## and steer at zero: lateral drift, heading, yaw rate and roll. The default speed is STRONG's
## steady 9 + its 4 m/s gust ceiling (`WorldConditions`). `headtail` (with `cruise`) runs the same
## speed twice more, each from a fresh standstill: into, then with, STRONG's steady WIND_HEADTAIL
## along the heading (a re-settle would inherit the gear the last wind left).
const XWIND_KMH := {"car": 90.0, "truck": 70.0, "tractor": 25.0}
const WIND_HEADTAIL := 9.0
const XWIND_SPEED := 13.0
const XWIND_S := 2.0
## s into the crosswind window that print a checkpoint: a driver corrects within about a second, so
## the first is the figure a wheel held straight is judged on; later ones show where it goes.
const XWIND_MARKS: Array[float] = [1.0]

# --- doc presets (`doc=<id>` as arg 1) -------------------------------------
## Each runs a fixed set and rewrites its `docs/vehicle_measurements.md` region (`doc_region.gd`). Cornering
## and accel run every wheel-driven variant (accel twice, floored then `tc`, each only to
## 100 km/h); braking the set below, heavies from 90 % of their top.
const DocRegion := preload("res://tools/doc_region.gd")
const DOC_BRAKING: Array[String] = ["sedan", "pickup", "delivery", "garbage-truck", "semi", "race"]
## doc=cruise: one body per shift map (the car's, the sports car's, the governed light
## commercial's, the heavy van's, the Kenney truck's, the semi's AMT on its spawn trailer, the
## tractor's powershift).
const DOC_CRUISE: Array[String] = ["sedan", "sedan-sports", "van", "delivery", "garbage-truck",
		"semi", "tractor-kenney"]
## doc=steer: a FWD, a RWD and an AWD car, an open-wheeler, a light and a heavy van, a Kenney truck.
const DOC_STEER: Array[String] = ["sedan", "sedan-sports", "suv", "race", "van", "delivery",
		"garbage-truck"]
## doc=wind: a car, a heavy van, a Kenney truck and the semi on its spawn trailer, each `cruise
## headtail xwind` at its XWIND_KMH speed.
const DOC_WIND: Array[String] = ["sedan", "delivery", "garbage-truck", "semi"]
const DOC_SECONDS := 60.0
## doc=tyres: a passenger car, a light truck and a heavy truck, each on every class its fit takes
## (`TyreCatalog.fitting`) over each of DOC_TYRE_SURFACES. A run is three passes: a `tc` launch to
## TYRES_LAUNCH_KMH, the cornering pass, and a full-pedal stop from TYRES_STOP_KMH.
const DOC_TYRES: Array[String] = ["sedan", "pickup", "garbage-truck"]
const DOC_TYRE_SURFACES: Array[int] = [Surface.ASPHALT, Surface.WET, Surface.SNOW, Surface.ICE,
		Surface.MUD, Surface.FIELD]
const TYRES_LAUNCH_KMH := 30.0
const TYRES_STOP_KMH := 50.0

const REFERENCE_SPECS_PATH := "res://tools/vehicle_reference_specs.json"
const REPORT_DIR := "res://reports/specs_sweep/"

enum Phase { ACCEL, COAST, TRACKING, CORNERING, BRAKING, STALL, HANDBRAKE, STEP, CRUISE, CIRCLE,
		KERB, HITCH, PLOUGH, DONE }
## Where a step-steer run is (`_tick_step`).
enum Step { RUN_UP, SETTLE, STEPPED }
## What a part-pedal probe window is doing (`_tick_cruise`).
enum Cruise { APPROACH, KICK, PULSE, XWIND }
## The air a cruise speed runs in (`headtail`): the `wind=` flag's, or WIND_HEADTAIL against or
## along the heading on top of it.
enum Air { STILL, HEAD, TAIL }
## Where a `plough` run is (`_tick_plough`).
enum Plough { LOWER, HOLD, STOP, START, COURSE_SET, COURSE_RUN }


## The strip as level 1's field for the `plough` pass, on what `BaseVehicle._collect_grip_terrains`
## and `TractorVehicle.soil_under` duck-type: `Surface.FIELD` at full weight everywhere. With `bands`
## (`plough course`), Field at `field` weight and Sand over the rest inside each band, by distance
## ahead of strip z `start_z` (the body faces -Z).
class FieldStrip extends Node:
	var start_z := 0.0
	var bands: Array[Vector2] = []
	var field := 1.0

	func ahead(p: Vector3) -> float:
		return start_z - p.z

	func field_at(p: Vector3) -> float:
		var s := ahead(p)
		for b in bands:
			if s >= b.x and s <= b.y:
				return field
		return 1.0

	func contains_xz(_p: Vector3) -> bool:
		return true

	func height_at(_p: Vector3) -> float:
		return 0.0

	func grip_at(p: Vector3, response: PackedFloat32Array) -> float:
		return lerpf(Surface.grip_in(response, Surface.SAND), Surface.grip_in(response, Surface.FIELD),
				field_at(p))

	func drag_at(p: Vector3) -> float:
		return lerpf(Surface.drag(Surface.SAND), Surface.drag(Surface.FIELD), field_at(p))

	func surface_weight_at(p: Vector3, surface: int) -> float:
		return field_at(p) if surface == Surface.FIELD else 0.0

var _queue: Array[String] = []
## The first body spawns on the first physics tick, as every later one does (`_finish_vehicle`):
## spawned from `_ready` instead it launched a tick early (`sedan,sedan,sedan 30 tc` 0-50 km/h:
## 3.62 / 3.63 / 3.63 s).
var _first_pending := false
var _seconds := DEFAULT_SECONDS
var _car: BaseVehicle
var _variant := ""
var _phase := Phase.ACCEL
var _failures := 0
## FAILs that were on KNOWN_TRACKING_FAILS, counted apart so they never reach the exit code.
var _known_failures := 0
## Allowlisted variants that PASSED: the entry is stale and should be deleted with its plan.
var _stale_allowances: Array[String] = []
var _coast := false
## `corner`: run the skid-pad pass after tracking. Off by default so the CI invocation and the
## default dev report are unchanged.
var _corner := false
## `brake`: run the braking pass last. Off by default, like `corner`.
var _brake := false
## `stall` / `handbrake`: run only that probe on each body (see their constants).
var _stall := false
var _hb_turn := false
var _probe_on := false        ## past the settle / run-up, into the measured window
var _probe_t := 0.0
var _probe_x0 := Vector3.ZERO
## Heading change (deg) integrated off the yaw rate, so a spin past 180 reads as one (a wrapped
## heading difference cannot tell a J-turn from a full rotation).
var _probe_turned := 0.0
var _probe_v_peak := 0.0
var _probe_spin_peak := 0.0
var _probe_yaw_peak := 0.0
var _probe_lock_t := 0.0
var _probe_override := false
var _hb_pulled := false       ## this handbrake run pulls the lever (the second of the pair)
var _step := false
var _st_runs: Array[Dictionary] = []  ## {kmh, lock, lifted} still to run, this body
var _st_run := {}                     ## the run in progress
var _st_stage := Step.RUN_UP
var _st_t := 0.0                      ## s into the current stage
var _st_target := 0.0                 ## m/s held into the step
var _st_i := 0.0                      ## integral half of the PI pedal
var _st_yaw: PackedFloat32Array = []  ## rad/s in the steered direction, one per tick of the step
var _st_tail := Vector3.ZERO          ## sums over the steady tail: v_long, steered angle, ticks
var _st_slip_peak := 0.0              ## deg
var _st_spin_t := -1.0                ## s into the step the body passed STEP_SPIN_DEG
var _st_roll_peak := 0.0              ## deg
var _st_lifted := 0                   ## most wheels off the ground in one tick of the step
var _st_roll_t := -1.0                ## s into the step the body passed STEP_ROLL_DEG
var _st_xfer0 := Vector2.ZERO         ## `_axle_transfer` on the step's first tick
var _st_xfer := Vector2.ZERO          ## `_axle_transfer` summed over the steady tail
## Each axle's mean roll-steer angle (rad; x front, y rear; + = toward understeer), one per tick of
## the step (`_axle_roll_steer`).
var _st_rs: PackedVector2Array = []
## `circle`: run only the full-lock circle (§ full-lock circle) on each body.
var _circle := false
var _ci_i := 0.0                      ## integral half of the circle's PI pedal
var _ci_sums := {}                    ## the circle's figures summed over the hold (`_tick_circle`)
## `hitch`: run only the hitch statics (§ hitch statics) on each body.
var _hitch_pass := false
var _hi_ids: Array[String] = []       ## implements still to read, this body
var _hi_stage := -1                   ## index into HITCH_STAGES; -1 the bare reading
var _hi_sums := Vector3.ZERO          ## front N, rear N, ticks over the current average
var _hi_bare := {}                    ## the bare reading: front kg, mass, COM, body-frame tensor
## `plough`: run only the draft pass (§ draft) on each body.
var _plough_pass := false
var _pl_ids: Array[String] = []       ## draft implements still to run, this body
var _pl_stage := Plough.LOWER
var _pl_speed := 0                    ## index into PLOUGH_KMH
var _pl_i := 0.0                      ## integral half of the PI pedal
var _pl_sums := {}                    ## the hold's figures summed (`_tick_plough`)
var _pl_rating := 0.0                 ## N, the implement's `draft_rating()`
var _pl_shape := Vector4.ZERO         ## its `draft_shape()`
var _pl_shifts: Array = []            ## the standing start's shifts (`_shift_record`)
var _pl_gear := -1                    ## gear byte at the last tick, to catch a shift
var _pl_trace_t := 0.0                ## s of the start at the next trace line
var _pl_moving_t := -1.0              ## s into the start the body first passed 0.5 km/h
var _pl_ticks := 0                    ## ticks into the start, for `trace=n`
var _pl_peak_slip := 0.0              ## the grip curve's peak slip (`_plough_trace_line`)
## `plough course`: run the course (§ draft) instead of the held speeds and the start.
var _course := false
var _co_strip: FieldStrip
var _co_row := Vector2.ZERO           ## the Row, m ahead of the course's Spawn
var _co_id := ""                      ## the implement the course runs
var _co_runs: Array[Vector2] = []     ## COURSE_RUNS still to run, this body
var _co_run := Vector2.ZERO           ## this run's km/h and `hitch_pos`
var _co_set := 0.0                    ## the ramped setpoint, m/s
var _co_ext := {}                     ## "<signal>, <soil> soil" -> [least, at, most, at, sum, ticks]
var _co_shifts: Array[String] = []    ## shifts inside the Row
var _co_gear := -1
## `kerb`: run only the kerb runs (§ kerb) on each body.
var _kerb := false
var _kb_runs: Array[Dictionary] = []  ## {h, coast, oblique} still to run, this body
var _kb_run := {}                     ## the run in progress
var _kb_box: StaticBody3D = null      ## the plateau, once laid
var _kb_i := 0.0                      ## integral half of the crawl's PI pedal
var _kb_t := 0.0                      ## s since the plateau was laid
var _kb_heading := Vector3.ZERO       ## the body's heading as the plateau was laid
var _kb_n := Vector3.ZERO             ## the edges' normal, toward the approach
var _kb_cos := 1.0                    ## `_kb_heading` along `-_kb_n`
var _kb_edge_at: Array[Vector3] = []  ## a point on the near and the far edge, y 0
var _kb_edges: Array[Dictionary] = [] ## per edge, up then down: the run's figures (`_kerb_edge`)
var _kb_prev_vy := 0.0
var _kb_origin := Vector3.ZERO
var _kb_best := 0.0                   ## furthest progress along the heading, m
var _kb_best_t := 0.0
var _kb_overlaps := 0                 ## `RayWheel.start_overlaps` as the run began
## `RayWheel.start_overlaps` as this body spawned (`_finish_vehicle` prints any since).
var _body_overlaps := 0
## `track`: skip the accel/top-speed pass — CI only needs the tracking gate.
var _track_only := false
## `strict`: exit nonzero on a tracking FAIL. Off by default so dev invocation stays a report.
var _strict := false
## `trailer=<name>`: what a body with an attachment axis spawns carrying, by the attachment
## scene's file name (`box`, `flatbed`, `farm_tipper`...) or `bobtail` / `none` for nothing.
## Empty: the catalog's own first entry; the tractor's none.
var _trailer := ""
## `doc=<braking|cornering|accel|cruise|steer|tyres>`: the preset that ran, its region rewritten at
## the end; empty otherwise.
var _doc := ""
## doc=tyres: each run's {tyre, surface}, popped beside its variant in `_queue`.
var _runs: Array[Dictionary] = []
## `tyre=<id>`: the class fitted on each body ("": its stock). Per run under doc=tyres.
var _tyre := ""
## `surface=<name>`: the `Surface` the slabs are painted (-1: bare). Per run under doc=tyres.
var _surface := -1
var _patch: MeasureRig.GripPatch
## `tc`: the accel pass slip-limits the worst driven wheel (`tc_pedal.gd`) instead of flooring.
var _tc := false
## This accel pass is slip-limited: `tc`, or doc=accel's second run of a body.
var _tc_run := false
var _tc_pedal := 1.0
var _loss := {}     ## launch-breakdown seconds so far this pass (`_sample_launch`)
## The limiter and shift cuts that shaped the car's last tick (`_latch_cuts`), and what judging the
## shift cut needs from the tick before: the gear, a shift cut still pending.
var _limiter_cut := false
var _shift_cut := false
var _cut_gear := -1
var _cut_pending := false
var _launch := {}   ## `_loss` snapshotted as each LAUNCH_MARKS mark latched, keyed by km/h
## `trace[=n]`: a trace line every n ticks for `trace_s=<s>` seconds, plus every gear change, and
## the launch gates at the end of the accel pass.
var _trace := false
var _trace_every := 1
var _trace_s := TRACE_PRINT_S
var _trace_settling := false  ## still on the foot brake before the traced launch
var _trace_ticks := 0
var _parked_front := 0.0      ## N on the front axle at the end of the settle
var _parked_pitch := 0.0      ## deg of body pitch at the end of the settle
var _parked_kingpin := 0.0    ## N a coupled trailer rests on the hitch at the end of the settle
var _gate := {}               ## the gates' running state this pass (`_sample_gates`)
## `notc`: the accel pass with the body's traction control off, as the bridge's `tcs_off` does.
var _notc := false
## `gear=<1-6>`: the accel pass in the bridge's manual mode, held in that byte (0: automatic D).
var _held_gear := 0
## `j=<kg·m²>`: the crank's inertia overridden on a copy of the spec, in memory, never shipped: the
## anchor run that compares the coupled crank against the wheels' own inertia (NAN: the spec's).
var _engine_inertia := NAN
## `rear_lat_grip=<x>`: the rear side-grip factor overridden the same way, the step pass's probe of
## a rear tyre's grip (NAN: the spec's).
var _rear_lat_grip := NAN
## `bar_rear=<N/m>`: the rear anti-roll bar rate overridden the same way (NAN: the spec's).
var _bar_rear := NAN
## `cornering_peak=<x>`: the tyre's cornering-stiffness law (`GroundDriveSpec.cornering_peak_load`)
## overridden the same way (NAN: the spec's).
var _cornering_peak := NAN
## `speeds=<km/h>,<km/h>`: the step pass runs these instead of its family's STEP_SETS row (a
## winged body's balance at speed). The step pad holds the run-up.
var _step_speeds: Array[float] = []
## `ackermann=<0..1>`: the Ackermann fraction (`GroundDriveSpec.ackermann`) overridden the same way
## (NAN: the spec's).
var _ackermann := NAN
## `rollsteer=<front>,<rear>`: the roll-steer coefficients (deg/deg,
## `GroundDriveSpec.roll_steer_front` / `_rear`) overridden the same way (NAN: the spec's).
var _roll_steer := Vector2(NAN, NAN)
## `angdamp=<1/s>`: the body's angular damping REPLACEd with this, and every towed body's as it
## couples (`_apply_angdamp`); 0 = none (NAN: as the body sets it).
var _angdamp := NAN
## `pedal=<0..1>`: the accel pass held at this pedal instead of floored (it implies the trace's
## settle and gates).
var _pedal := 1.0

# part-pedal probes (`cruise`, `kickdown`, `pulse`)
var _cruise := false
var _kickdown := false
var _pulse := false
var _pulse_period := PULSE_PERIOD_S
var _pulse_duty := NAN             ## `duty=<0..1>`; NAN: the PI pedal, latched each period
var _cr_speeds: Array[float] = []  ## km/h still to run, this body
var _cr_actions: Array[Cruise] = []  ## what follows each settle at the current speed
var _cr_stage := Cruise.APPROACH
var _cr_target := 0.0              ## m/s
var _cr_set := 0.0                 ## m/s, the ramped setpoint
var _cr_ramp := 1.0                ## m/s²
var _cr_i := 0.0                   ## integral half of the PI pedal
var _cr_pedal := 0.0               ## the pedal that drove the last tick
var _cr_settled := false           ## this speed's cruise line printed
var _cr_hold_t := 0.0              ## s within CRUISE_TOL with no shift
var _cr_sums := Vector3.ZERO       ## pedal, rpm and engine_load summed over the hold
var _cr_ticks := 0
var _cr_pedal_peak := 0.0          ## the approach's highest pedal: 1.00 is a floored approach
var _cr_gear := -1                 ## gear byte at the last tick, to catch a shift
var _cr_shifts: Array = []         ## this window's shifts (`_shift_record`)
var _cr_limiter := 0               ## limiter ticks this window
var _cr_v0 := 0.0                  ## m/s at the start of this window
var _cr_g0 := 0                    ## gear at the start of a window (a kick's cruise gear)
var _cr_t0 := 0.0                  ## `_t` at the start of this window
var _cr_duty := 0.0                ## this pulse period's on share
var _cr_duty_sum := 0.0            ## summed over the pulse's periods, for its mean
var _cr_periods := 0
var _cr_band := Vector2(INF, -INF)  ## m/s, the slowest and fastest of the pulse
var _xwind := false
var _headtail := false
var _cr_airs: Array[Air] = []      ## the air each of `_cr_speeds` runs in
var _cr_air := Air.STILL
var _xwind_speed := XWIND_SPEED    ## m/s
var _xw_origin := Vector3.ZERO     ## the body's position as the crosswind starts
var _xw_right := Vector3.ZERO      ## its flat right axis then: drift is measured along it
var _xw_heading := 0.0             ## rad
var _xw_yaw_peak := 0.0            ## rad/s
var _xw_pedal := 0.0
var _xw_marks: Array[float] = []    ## s into the window still to print a checkpoint at

## `wind=<from_deg>:<m/s>` (`MeasureRig.wind_flag`): the steady wind every body in this tool reads,
## through `wind_vector()` (the duck-typed contract `WindField.at` walks up to).
var _wind_base := Vector3.ZERO
var _wind := Vector3.ZERO

# coast pass
var _coast_v0 := 0.0
var _coast_declared := 0.0   ## N, declared resistance summed over the coast's ticks
var _coast_overrun := 0.0    ## N at the road, `Drivetrain.overrun_torque` summed the same way
## kg the crank adds to the rig while its coupling is locked, `J G^2 / (eta r^2)` (the overrun
## direction's reflection), summed the same way
var _coast_crank_kg := 0.0
var _coast_ticks := 0
var _coast_tyres := 0.0      ## N, retarding tyre force over the rig's wheels, summed the same way
var _contact_peak := 0
var _contact_t0 := -1.0
var _contact_t1 := -1.0

# accel pass
var _t := 0.0
var _peak := 0.0
var _dist := 0.0
var _marks := {}
var _settle_t := 0.0
var _settle_v := 0.0
var _prev_settle_t := 0.0  ## start of the last complete settle window
var _prev_settle_v := 0.0
var _prev_v := 0.0
var _inst_a := 0.0   ## body's own acceleration last tick, for the balance audit
var _lateral_peak := 0.0  ## m the body strayed from the strip's centre line, against the edge

# tracking pass
var _latched := false
var _track_origin := Vector3.ZERO
var _track_right := Vector3.ZERO
var _track_forward := Vector3.ZERO
var _track_heading := 0.0
var _track_dist := 0.0
var _drift_peak := 0.0
var _drift_final := 0.0
var _heading_peak := 0.0
var _front_lift_ticks := 0

# cornering pass
var _corner_ramping := false   ## false while still getting up to _corner_speed
## m/s held through this body's pass (`_corner_target`).
var _corner_speed := CORNER_SPEED
var _corner_ramp_t := 0.0
var _corner_lat := 0.0         ## smoothed lateral acceleration, m/s^2
var _corner_peak := 0.0
var _corner_front := 0.0       ## front-axle saturation at the peak
var _corner_rear := 0.0
var _corner_slid := false      ## the slip-angle gate tripped at some point
var _corner_roll := 0.0        ## chassis roll (deg) at the lateral-g peak
var _corner_drive := 0.0       ## the tyres' summed longitudinal force (N) at the peak
var _corner_xfer0 := Vector2.ZERO  ## `_axle_transfer` as the lock starts winding on
var _corner_lltd := NAN        ## front share of the lateral load transfer at the peak (`_lltd`)
var _corner_lifted := 0        ## most wheels off the ground in any one tick of the pass
var _corner_pedal_i := 0.0     ## integral half of the PI speed hold
## `telemetry.acc_lat` (the path's own lateral acceleration) under the same smoothing, and its peak
## below the slip-angle gate. `v * yaw_rate` also counts the yaw a body overshoots into a slip
## angle: on ice (`sedan`, `surface=ice`) it peaks at 0.22 g against a 0.10 g path.
var _corner_path := 0.0
var _corner_path_peak := 0.0

# braking pass
var _top_seen := 0.0           ## m/s, the accel pass's peak (0 when it did not run)
var _brake_i := 0              ## index into BRAKE_PEDALS
var _brake_target := 0.0       ## m/s the stop starts from
var _brake_on := false         ## false while still getting up to speed
var _brake_v0 := 0.0
var _brake_t := 0.0
var _brake_x0 := Vector3.ZERO
var _brake_lock_t := 0.0       ## s any wheel spent past BRAKE_LOCK_SLIP
var _brake_abs_t := 0.0        ## s any wheel's ABS held its brake back
var _brake_rows: Array[Dictionary] = []
var _brake_from := BRAKE_SPEED     ## m/s; doc=tyres stops from TYRES_STOP_KMH
var _brake_pedals := BRAKE_PEDALS  ## doc=tyres: full pedal alone

# sweep report: per-vehicle measured figures, buffered as each pass reports, plus the
# real-world comparison figures loaded once from REFERENCE_SPECS_PATH.
var _reference := {}
var _sweep: Array[Dictionary] = []
var _current := {}


## The air every body under this tool moves through (`WindField.at`).
func wind_vector() -> Vector3:
	return _wind


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "sedan-sports"
	if args.size() > 1:
		_seconds = maxf(5.0, float(args[1]))
	var flags := args.slice(2)
	_coast = flags.has("coast")
	_corner = flags.has("corner")
	_brake = flags.has("brake")
	_stall = flags.has("stall")
	_hb_turn = flags.has("handbrake")
	_step = flags.has("step")
	_circle = flags.has("circle")
	_hitch_pass = flags.has("hitch")
	_plough_pass = flags.has("plough")
	_course = _plough_pass and flags.has("course")
	_kerb = flags.has("kerb")
	_track_only = flags.has("track")
	_strict = flags.has("strict")
	_tc = flags.has("tc")
	_notc = flags.has("notc")
	_cruise = flags.has("cruise")
	_kickdown = flags.has("kickdown")
	for f in flags:
		var flag := String(f)
		if flag.begins_with("trailer="):
			_trailer = flag.substr(8).to_lower()
		elif flag.begins_with("surface="):
			_surface = Surface.from_key(flag.substr(8))
			if _surface < 0:
				printerr("surface=%s: expected one of %s" % [flag.substr(8), ", ".join(Surface.NAMES)])
				get_tree().quit(1)
				return
		elif flag == "trace" or flag.begins_with("trace="):
			_trace = true
			_trace_every = maxi(1, int(flag.substr(6))) if flag.length() > 5 else 1
		elif flag.begins_with("trace_s="):
			_trace_s = float(flag.substr(8))
		elif flag.begins_with("j="):
			_engine_inertia = float(flag.substr(2))
		elif flag.begins_with("rear_lat_grip="):
			_rear_lat_grip = float(flag.substr(14))
		elif flag.begins_with("bar_rear="):
			_bar_rear = float(flag.substr(9))
		elif flag.begins_with("cornering_peak="):
			_cornering_peak = float(flag.substr(15))
		elif flag.begins_with("speeds="):
			for kmh in flag.substr(7).split(",", false):
				_step_speeds.append(float(kmh))
		elif flag.begins_with("ackermann="):
			_ackermann = clampf(float(flag.substr(10)), 0.0, 1.0)
		elif flag.begins_with("rollsteer="):
			var pair := flag.substr(10).split(",")
			_roll_steer = Vector2(float(pair[0]) if pair.size() > 0 else 0.0,
					float(pair[1]) if pair.size() > 1 else 0.0)
		elif flag.begins_with("angdamp="):
			_angdamp = maxf(float(flag.substr(8)), 0.0)
		elif flag.begins_with("pedal="):
			_pedal = clampf(float(flag.substr(6)), 0.05, 1.0)
		elif flag == "pulse" or flag.begins_with("pulse="):
			_pulse = true
			if flag.length() > 5:
				_pulse_period = maxf(float(flag.substr(6)), 0.1)
		elif flag.begins_with("duty="):
			_pulse_duty = clampf(float(flag.substr(5)), 0.0, 1.0)
		elif flag == "headtail":
			_headtail = true
		elif flag == "xwind" or flag.begins_with("xwind="):
			_xwind = true
			if flag.length() > 5:
				_xwind_speed = maxf(float(flag.substr(6)), 0.0)
		elif flag.begins_with("gear="):
			_held_gear = int(flag.substr(5))
			if _held_gear < 1 or _held_gear > Drivetrain.TOP_GEAR:
				printerr("gear=%s: expected a drive byte 1-%d" % [flag.substr(5), Drivetrain.TOP_GEAR])
				get_tree().quit(1)
				return
	_tyre = MeasureRig.tyre_flag(flags)
	if _tyre == "?":
		get_tree().quit(1)
		return
	_wind_base = MeasureRig.wind_flag(flags)
	if is_nan(_wind_base.x):
		get_tree().quit(1)
		return
	_wind = _wind_base
	if (_xwind or _headtail) and not _cruise:
		printerr("xwind / headtail run inside the cruise probe: add `cruise`")
		get_tree().quit(1)
		return
	if _surface >= 0 and _plough_pass:
		printerr("surface= and plough both paint the strip: plough runs on level 1's field")
		get_tree().quit(1)
		return
	if _pedal < 1.0 and _tc:
		printerr("pedal= and tc both set the accel pass's pedal: pick one")
		get_tree().quit(1)
		return
	if _pedal < 1.0 and not _trace:
		# The gates and each shift's line; per-tick lines only when `trace` asks for them.
		_trace = true
		_trace_s = 0.0
	if which.begins_with("doc="):
		_doc = which.substr(4)
		_seconds = DOC_SECONDS
		if _doc == "braking":
			_brake = true
		elif _doc == "cornering":
			_track_only = true
			_corner = true
		elif _doc == "accel":
			_tc = false  # the preset runs each body floored, then `tc`
		elif _doc == "steer":
			_step = true
		elif _doc == "tyres":
			# A `tc` launch, the cornering pass, a full-pedal stop (`_end_tyre_launch`).
			_tc = true
			_corner = true
			_brake = true
			_brake_from = TYRES_STOP_KMH / 3.6
			_brake_pedals = [1.0]
		elif _doc != "cruise" and _doc != "wind":
			printerr(("unknown doc preset '%s' — expected doc=braking, doc=cornering, doc=accel,"
					+ " doc=cruise, doc=wind, doc=steer or doc=tyres") % _doc)
			get_tree().quit(1)
			return
		if _trace or _notc or _held_gear > 0 or not is_nan(_engine_inertia) \
				or not is_nan(_rear_lat_grip) or not is_nan(_bar_rear) or not is_nan(_cornering_peak) \
				or not is_nan(_ackermann) or not is_nan(_roll_steer.x) or not is_nan(_angdamp) \
				or _circle or _hitch_pass or _plough_pass or _kerb or _cruise_probe() \
				or _tyre != "" or _surface >= 0 or not _step_speeds.is_empty() or _xwind or _headtail \
				or _wind_base != Vector3.ZERO:
			printerr("trace / notc / gear= / j= / rear_lat_grip= / bar_rear= / cornering_peak= / speeds= /"
					+ " ackermann= / rollsteer= / angdamp= / circle / hitch / plough / kerb /"
					+ " pedal= / cruise /"
					+ " kickdown / pulse / xwind / headtail / wind= / tyre= / surface= change the passes a"
					+ " doc preset tabulates:"
					+ " run them per body")
			get_tree().quit(1)
			return
		# After the check above: each preset is the cruise probe alone.
		_cruise = _doc == "cruise" or _doc == "wind"
		_xwind = _doc == "wind"
		_headtail = _doc == "wind"
	var ref_file := FileAccess.open(REFERENCE_SPECS_PATH, FileAccess.READ)
	_reference = JSON.parse_string(ref_file.get_as_text())
	# Do not speed up with Engine.time_scale: it enlarges the physics step and breaks the
	# locked-60-Hz tuning (default car's 0-100 went 5.30 s -> 6.40 s at time_scale 8).
	MeasureRig.add_slab(self, "Strip", Vector3(STRIP_WIDTH, 2.0, STRIP_LENGTH))
	if _corner:
		# Skid pad: a wide square well off to the side, since a body at full lock circles in tens of
		# metres (a hundred on ice) and the strip is only 40 m wide.
		MeasureRig.add_slab(self, "Pad", Vector3(PAD_SIZE, 2.0, PAD_SIZE), PAD_X)
	if _step or _circle:
		# Under the strip and either side of it, top face flush with the strip's.
		MeasureRig.add_slab(self, "StepPad", Vector3(STEP_PAD_WIDTH, 2.0, STRIP_LENGTH))
	if _surface >= 0 or _doc == "tyres":
		# Before the first body ticks, as the field below.
		_patch = MeasureRig.GripPatch.new()
		_patch.name = "GripPatch"
		add_child(_patch)
	if _plough_pass:
		# Before the first body ticks: its wheels find the painted terrains once.
		var strip := FieldStrip.new()
		if _course:
			_co_strip = strip
			_load_course(strip)
		add_child(strip)
	if which == "all" or _doc == "cornering" or _doc == "accel":
		_queue.assign(_wheel_driven_variants())
	elif _doc == "braking":
		_queue = DOC_BRAKING.duplicate()
	elif _doc == "cruise":
		_queue = DOC_CRUISE.duplicate()
	elif _doc == "wind":
		_queue = DOC_WIND.duplicate()
	elif _doc == "steer":
		_queue = DOC_STEER.duplicate()
	elif _doc == "tyres":
		for v in DOC_TYRES:
			for cls in TyreCatalog.fitting(_tyre_fit(v)):
				for s in DOC_TYRE_SURFACES:
					_queue.append(v)
					_runs.append({"tyre": cls.id, "surface": s})
	elif Catalog.VARIANTS.has(which):
		_queue = [which]
	elif which.contains(",") and Array(which.split(",")).all(
			func(v: String) -> bool: return Catalog.VARIANTS.has(v)):
		_queue.assign(which.split(","))
	else:
		printerr("unknown variant '%s' — expected 'all' or one of: %s" %
				[which, ", ".join(_wheel_driven_variants())])
		get_tree().quit(1)
		return
	if _circle and _trailer == "":
		_trailer = "bobtail"
	if _course and _trailer == "":
		_trailer = "plough"  # the implement tractor_plough attaches
	var steer_label := "steer stepped" if _step else "zero steer input"
	if _circle:
		steer_label = "full right lock"
	elif _hitch_pass:
		steer_label = "parked"
	elif _plough_pass:
		steer_label = "level 1's field (grip %.2f, drag %.2f) under it" % [Surface.ref_grip(Surface.FIELD),
				Surface.drag(Surface.FIELD)]
	print("strip: %.0f x %.0f m flat, %s, %s, %.0f s cap per pass\n" %
			[STEP_PAD_WIDTH if _step else STRIP_WIDTH, STRIP_LENGTH, _surface_label(), steer_label,
			_seconds])
	MeasureRig.drive(100.0, 0.0)
	_first_pending = true


## Every catalog variant with a driven axle; boat/drone/plane/train declare none.
func _wheel_driven_variants() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.VARIANTS:
		var scene: PackedScene = load(Catalog.VARIANTS[id]["scene"])
		var body := scene.instantiate()
		if body is BaseVehicle:
			var spec: VehicleSpec = (body as BaseVehicle).spec
			var gd: GroundDriveSpec = spec.ground_drive if spec != null else null
			if gd != null and (gd.driven_front or gd.driven_rear):
				out.append(id)
		body.free()
	return out


## `variant`'s `GroundDriveSpec.tyre_fit` (`TyreClass.Fit.NONE` on a body with no ground drive).
static func _tyre_fit(variant: String) -> int:
	var body: Node = (load(Catalog.VARIANTS[variant]["scene"]) as PackedScene).instantiate()
	var spec: VehicleSpec = body.get("spec")
	var fit: int = spec.ground_drive.tyre_fit if spec != null and spec.ground_drive != null \
			else TyreClass.Fit.NONE
	body.free()
	return fit


## What the slabs are painted: per run under doc=tyres, else `surface=` or bare ground.
func _surface_label() -> String:
	if _doc == "tyres":
		return "painted per run"
	if _surface >= 0:
		return "painted %s (grip %.2f, drag %.2f)" % [Surface.display_name(_surface),
				Surface.ref_grip(_surface), Surface.drag(_surface)]
	return "bare (the tyre's asphalt)"


func _next_vehicle() -> void:
	if _car != null:
		remove_child(_car)
		_car.queue_free()
		_car = null
	if _queue.is_empty():
		if _failures > 0:
			print("%d vehicle(s) with a tracking FAIL" % _failures)
		elif _known_failures > 0:
			print("all vehicles tracked straight except %d known FAIL(s)" % _known_failures)
		else:
			print("all vehicles tracked straight")
		if _known_failures > 0:
			print("  known FAIL(s) allowed by KNOWN_TRACKING_FAILS - see the plan named there")
		for allowed in _stale_allowances:
			print("  NOTE: %s is on KNOWN_TRACKING_FAILS but PASSED - delete the entry" % allowed)
		_write_report()
		if _doc == "braking":
			DocRegion.write(_doc, _braking_table())
		elif _doc == "cornering":
			DocRegion.write(_doc, _cornering_table())
		elif _doc == "accel":
			DocRegion.write(_doc, _accel_table())
		elif _doc == "cruise":
			DocRegion.write(_doc, _cruise_table())
		elif _doc == "wind":
			DocRegion.write(_doc, _wind_table())
		elif _doc == "steer":
			DocRegion.write(_doc, _steer_table())
		elif _doc == "tyres":
			DocRegion.write(_doc, _tyres_table())
		get_tree().quit(1 if _strict and _failures > 0 else 0)
		return
	_variant = _queue.pop_front()
	if not _runs.is_empty():
		var run: Dictionary = _runs.pop_front()
		_tyre = run["tyre"]
		_surface = run["surface"]
	if _patch != null:
		_patch.surface = _surface
	_current = {"variant": _variant, "family": String(Catalog.VARIANTS[_variant]["family"])}
	_top_seen = 0.0
	_brake_i = 0
	_brake_rows = []
	_car = load(Catalog.VARIANTS[_variant]["scene"]).instantiate()
	_body_overlaps = RayWheel.start_overlaps
	if not is_nan(_engine_inertia):
		_car.spec = _car.spec.duplicate()
		_car.spec.engine_inertia = _engine_inertia
		_current["engine_inertia"] = _engine_inertia
	if not is_nan(_rear_lat_grip):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.rear_lat_grip = _rear_lat_grip
	if not is_nan(_bar_rear):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.anti_roll_rate_rear = _bar_rear
	if not is_nan(_cornering_peak):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.cornering_peak_load = _cornering_peak
	if not is_nan(_ackermann):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.ackermann = _ackermann
	if not is_nan(_roll_steer.x):
		_car.spec = _car.spec.duplicate()
		_car.spec.ground_drive = _car.spec.ground_drive.duplicate()
		_car.spec.ground_drive.roll_steer_front = _roll_steer.x
		_car.spec.ground_drive.roll_steer_rear = _roll_steer.y
	_current["abs"] = _car.spec.ground_drive.abs_equipped
	add_child(_car)
	var tyre := MeasureRig.fit_tyre(_car, _tyre)
	if _tyre != "" or _surface >= 0:
		_current["tyre"] = tyre
		_current["stock"] = _car.drive != null and _car.drive.tyre == _car.spec.ground_drive.tyre
		_current["surface"] = _surface
		print("--- %s: tyre %s, on %s ---" % [_variant, tyre,
				Surface.display_name(_surface) if _surface >= 0 else "bare ground"])
	# Strip top is y=0; wheels just touching, no spawn drop onto the springs.
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_apply_trailer()
	if _coast:
		_car.contact_monitor = true
		_car.max_contacts_reported = 8
	_tc_run = _tc
	if _stall:
		_start_stall()
	elif _cruise_probe():
		_start_cruise()
	elif _hb_turn:
		_hb_pulled = false
		_start_handbrake_run()
	elif _step:
		_start_step()
	elif _circle:
		_start_circle()
	elif _hitch_pass:
		_start_hitch()
	elif _plough_pass:
		_start_plough()
	elif _kerb:
		_start_kerb()
	elif _track_only:
		_reset_pass(Phase.TRACKING)
	else:
		_start_accel()


## The accel pass from a standstill: floored at once, or with `trace` held on the foot brake for
## TRACE_SETTLE_S first (`_tick_accel` floors it and restarts the clock).
func _start_accel() -> void:
	_reset_pass(Phase.ACCEL)
	InputRouter.set_manual_gearbox(_held_gear > 0)
	_trace_settling = _trace
	if _trace_settling:
		_drive_accel(0.0, 100.0)
	else:
		_drive_accel(_pedal * 100.0)


## The accel pass's bridge stash: `gear=` and `notc` ride it; every other pass drives D with TC.
func _drive_accel(accel_pct: float, brake_pct := 0.0) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, false, maxi(_held_gear, 1), _notc)


## Swap the spawn attachment for `trailer=`'s before the first tick: set_attachment only remembers
## an id until the coupling countdown has run, then couples it (TowHost.SPAWN_COUPLE_TICKS).
func _apply_trailer(body: BaseVehicle = null) -> void:
	if body == null:
		body = _car
	if _trailer == "" and body is TractorVehicle:
		# Bare tractor by default: a carried implement's weight moves its axle loads.
		body.call(&"set_attachment", AttachmentCatalog.NONE)
		return
	if _trailer == "" or not body.has_method(&"attachment_ids"):
		return
	var found := _trailer in ["bobtail", "none"]
	var want := AttachmentCatalog.NONE
	if not found:
		for id: String in body.call(&"attachment_ids"):
			if id.get_file().get_basename() == _trailer:
				want = id
				found = true
	if not found:
		print("  %s has no attachment '%s'; measured on its spawn attachment" % [_variant, _trailer])
		return
	body.call(&"set_attachment", want)
	_current["trailer"] = _trailer


func _reset_pass(phase: Phase) -> void:
	_phase = phase
	_t = 0.0
	_peak = 0.0
	_dist = 0.0
	_marks = {}
	_settle_t = 0.0
	_settle_v = 0.0
	_prev_settle_t = 0.0
	_prev_settle_v = 0.0
	# Must reset: a stale _prev_v reads the first tick of a new pass as the last vehicle's terminal speed falling to zero.
	_prev_v = 0.0
	_lateral_peak = 0.0
	_tc_pedal = 1.0
	_loss = {"spin": 0.0, "limiter": 0.0, "shift": 0.0, "torque": 0.0, "stall": 0.0, "gears": {},
			"force": 0.0, "budget": 0.0, "under_peak": 0.0, "past_peak": 0.0, "tick_cap": 0.0,
			"tcs": 0.0}
	_launch = {}
	_limiter_cut = false
	_shift_cut = false
	_cut_gear = -1
	_cut_pending = false
	_gate = {}
	_trace_ticks = 0
	_coast_v0 = 0.0
	_coast_declared = 0.0
	_coast_overrun = 0.0
	_coast_crank_kg = 0.0
	_coast_tyres = 0.0
	_coast_ticks = 0
	_contact_peak = 0
	_contact_t0 = -1.0
	_contact_t1 = -1.0
	_latched = false
	_track_dist = 0.0
	_drift_peak = 0.0
	_drift_final = 0.0
	_heading_peak = 0.0
	_front_lift_ticks = 0
	_corner_ramping = false
	_corner_speed = _corner_target(_car.spec)
	_corner_ramp_t = 0.0
	_corner_lat = 0.0
	_corner_peak = 0.0
	_corner_front = 0.0
	_corner_rear = 0.0
	_corner_slid = false
	_corner_roll = 0.0
	_corner_drive = 0.0
	_corner_xfer0 = Vector2.ZERO
	_corner_lltd = NAN
	_corner_lifted = 0
	_corner_pedal_i = 0.0
	_corner_path = 0.0
	_corner_path_peak = 0.0
	_brake_on = false
	_brake_v0 = 0.0
	_brake_t = 0.0
	_brake_lock_t = 0.0
	_brake_abs_t = 0.0


func _physics_process(delta: float) -> void:
	if _first_pending:
		_first_pending = false
		_next_vehicle()
		return
	if _car == null or _phase == Phase.DONE:
		return
	_t += delta
	_apply_angdamp()
	if _coast:
		var n := _car.get_contact_count()
		_contact_peak = maxi(_contact_peak, n)
		# First/last timestamps distinguish a scraping hull (long window) from a spawn bounce.
		if n > 0:
			if _contact_t0 < 0.0:
				_contact_t0 = _t
			_contact_t1 = _t
	if _phase == Phase.ACCEL:
		_tick_accel(delta)
	elif _phase == Phase.COAST:
		_tick_coast()
	elif _phase == Phase.CORNERING:
		_tick_cornering(delta)
	elif _phase == Phase.BRAKING:
		_tick_braking(delta)
	elif _phase == Phase.STALL:
		_tick_stall(delta)
	elif _phase == Phase.HANDBRAKE:
		_tick_handbrake(delta)
	elif _phase == Phase.STEP:
		_tick_step(delta)
	elif _phase == Phase.CRUISE:
		_tick_cruise(delta)
	elif _phase == Phase.HITCH:
		_tick_hitch()
	elif _phase == Phase.PLOUGH:
		_tick_plough(delta)
	elif _phase == Phase.CIRCLE:
		_tick_circle(delta)
	elif _phase == Phase.KERB:
		_tick_kerb(delta)
	else:
		_tick_tracking()


func _tick_accel(delta: float) -> void:
	if _trace_settling:
		if _t < TRACE_SETTLE_S:
			return
		_trace_settling = false
		_parked_front = _front_axle_load()
		_parked_pitch = _car.telemetry.pitch
		_parked_kingpin = _kingpin_load(0.0)
		# The clock starts on the pedal: a line at t has had t of floored ticks.
		_reset_pass(Phase.ACCEL)
		_drive_accel(_pedal * 100.0)
		_print_trace_header()
		return
	# The pedal that drove this tick, then next tick's.
	var pedal := _tc_pedal if _tc_run else _pedal
	if _tc_run:
		# Held through a shift cut: the wheels unload there, and the integral would wind up.
		if not _car.drivetrain.shift_cut_active():
			_tc_pedal = TcPedal.step(_tc_pedal, _car.wheels, delta, _car.drivetrain)
		_drive_accel(_tc_pedal * 100.0)
	var v: float = _car.telemetry.speed  # signed m/s, read out of the sim
	_inst_a = (v - _prev_v) / delta
	_prev_v = v
	_dist += absf(v) * delta
	_peak = maxf(_peak, v)
	_lateral_peak = maxf(_lateral_peak, absf(_car.global_position.x))
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		if not _marks.has(kmh) and v * 3.6 >= kmh:
			_marks[kmh] = _t
	if not _marks.has("quarter") and _dist >= 402.34:
		_marks["quarter"] = Vector2(_t, v * 3.6)
	_latch_cuts(delta)
	_sample_launch(delta, pedal)
	if _trace:
		_sample_gates()
	if _doc == "accel":
		if _marks.has(LAUNCH_MARKS[-1]) or _t >= _seconds:
			_end_launch_run()
		return
	if _doc == "tyres":
		if v * 3.6 >= TYRES_LAUNCH_KMH or _t >= _seconds:
			_end_tyre_launch(v * 3.6 >= TYRES_LAUNCH_KMH)
		return
	# Plateaued: call it rather than idling at terminal speed for the rest of the budget.
	var settled := _t - _settle_t >= SETTLE_WINDOW
	if settled and _peak - _settle_v < maxf(SETTLE_ABS, _peak * SETTLE_REL):
		_report_accel(false)
		return
	if settled:
		# Kept for the cap note: a cap just past a restart would otherwise report a gain over 0 s.
		_prev_settle_t = _settle_t
		_prev_settle_v = _settle_v
		_settle_t = _t
		_settle_v = _peak
	if _t >= _seconds:
		_report_accel(true)


## The cuts that shaped the car's last tick. The limiter's is the drivetrain's own record
## (`Drivetrain.on_limiter`: its hard cut, or a crossing landed on the redline). A shift cut ran if
## one was still pending from the tick before or a shift latched it in this one (`shift_cut_active`
## reads the count after its decrement, so it misses a cut's last tick).
func _latch_cuts(delta: float) -> void:
	var spec: VehicleSpec = _car.spec
	var dt: Drivetrain = _car.drivetrain
	_limiter_cut = dt.on_limiter
	_shift_cut = _cut_pending or (Drivetrain.is_shift(_cut_gear, dt.gear_byte)
			and Drivetrain.shift_cut_ticks(spec.shift_cut_s, delta) > 0)
	_cut_gear = dt.gear_byte
	_cut_pending = dt.shift_cut_active()


## One tick of the launch breakdown (§ launch breakdown), until the last LAUNCH_MARKS mark latches.
## The cuts are the ones that shaped the tick (`_latch_cuts`).
func _sample_launch(delta: float, pedal: float) -> void:
	if _launch.has(LAUNCH_MARKS[-1]):
		return
	var spec: VehicleSpec = _car.spec
	var gd := spec.ground_drive
	var dt: Drivetrain = _car.drivetrain
	var spinning := false
	var spare_grip := true
	var tcs := false
	var omega := 0.0
	var driven := 0
	for w in _car.wheels:
		if not w.driven:
			continue
		omega += w.omega
		driven += 1
		# The body's own TC acts off the ground too (`RayWheel.tick`).
		tcs = tcs or w.tcs_active
		if not w.in_contact:
			spare_grip = false
			continue
		var budget := _long_budget(w, gd)
		_loss["force"] += w.force_long * delta
		_loss["budget"] += budget * delta
		_split_deficit(w, gd, budget, delta)
		if w.slip >= TcPedal.TARGET_SLIP:
			spare_grip = false
			if w.slip > SPIN_SLIP:
				spinning = true
	var wheel_rpm := Drivetrain.wheel_engine_rpm(spec, omega / maxf(1.0, driven), dt.gear_byte)
	var cut := _limiter_cut
	var shifting := _shift_cut
	if spinning:
		_loss["spin"] += delta
	if cut:
		_loss["limiter"] += delta
	if shifting:
		_loss["shift"] += delta
	if tcs:
		_loss["tcs"] += delta
	# TC holds the slip just under the peak, which reads as spare grip; a held wheel is not
	# torque-bound.
	if pedal >= LAUNCH_FLOORED and spare_grip and not cut and not shifting and not tcs:
		_loss["torque"] += delta
		if wheel_rpm < Drivetrain.launch_target_rpm(spec, 1.0):
			_loss["stall"] += delta
	var gears: Dictionary = _loss["gears"]
	gears[dt.gear_byte] = float(gears.get(dt.gear_byte, 0.0)) + delta
	for kmh in LAUNCH_MARKS:
		if _marks.has(kmh) and not _launch.has(kmh):
			_launch[kmh] = _loss.duplicate(true)


## Splits one driven contact's `budget - force_long` into `_loss`'s three deficit buckets, which sum
## to it exactly: `tick_cap`, what the one-tick cap (`RayWheel.long_cap`) took off the curve force
## where it bound; the
## rest, the curve short of its 1.0 peak (plus the share lateral slip takes), is `under_peak` or
## `past_peak` by the slip's side of TcPedal.TARGET_SLIP. The wheel's fields are from its last tick,
## the body's velocity one step on: the slip denominator is exact under the wheel's `slip_floor`,
## which is where the cap binds.
func _split_deficit(w: RayWheel, gd: GroundDriveSpec, budget: float, delta: float) -> void:
	var up := _car.global_transform.basis.y
	var wheel_forward := Basis(up, w.steer_angle) * -_car.global_transform.basis.z
	var forward := (wheel_forward - w.contact_normal * wheel_forward.dot(w.contact_normal)).normalized()
	var vel := VehicleMath.point_velocity(_car, w.contact_point)
	var slip_denom := maxf(absf(vel.dot(forward)), w.slip_floor)
	var slip_long := w.slip * signf(w.force_long)
	var budget_lat: float = RayWheel.load_scaled_mu(
			gd.mu_lat * w.axle_lat_grip * w.surface_grip,
			w.suspension_force * w.tyre_share, w.corner_mass * 9.81, gd.load_sensitivity) \
			* w.suspension_force
	var curve := RayWheel.combined_slip_force(slip_long,
			-vel.dot(forward.cross(w.contact_normal)) / slip_denom, budget, budget_lat,
			gd.grip_curve, RayWheel.lateral_peak_slip(w.suspension_force * w.tyre_share,
				w.corner_mass * 9.81, gd.load_sensitivity, gd.cornering_peak_load)).x
	var capped := curve - w.force_long if absf(curve) > w.long_cap else 0.0
	_loss["tick_cap"] += capped * delta
	_loss["under_peak" if w.slip < TcPedal.TARGET_SLIP else "past_peak"] += \
			(budget - w.force_long - capped) * delta


## "spin 1.20 s, limiter 0.31 s, ...; grip use 0.62 (under peak 0.05, past peak 0.30, tick cap
## 0.03); gears 1 2.10, 2 1.00 s": one LAUNCH_MARKS snapshot. Grip use is the driven tyres' force
## over their `_long_budget`, time-weighted; the bracket is the rest of that budget
## (`_split_deficit`), so the four sum to 1.
static func _loss_label(l: Dictionary) -> String:
	var gears: Array[String] = []
	var bytes: Array = (l["gears"] as Dictionary).keys()
	bytes.sort()
	for g: int in bytes:
		gears.append("%d %.2f" % [g, l["gears"][g]])
	var d := _deficit_shares(l)
	return ("spin %.2f s, limiter %.2f s, shift %.2f s, tcs %.2f s, torque-bound %.2f s"
			+ " (%.2f s under stall);"
			+ " grip use %.2f (under peak %.2f, past peak %.2f, tick cap %.2f); gears %s s") % [
			l["spin"], l["limiter"], l["shift"], l["tcs"], l["torque"], l["stall"], _grip_use(l), d.x,
			d.y, d.z, ", ".join(gears)]


static func _grip_use(l: Dictionary) -> float:
	return float(l["force"]) / maxf(float(l["budget"]), 1.0)


## (under peak, past peak, tick cap), each a share of the time-weighted budget like `_grip_use`.
static func _deficit_shares(l: Dictionary) -> Vector3:
	return Vector3(l["under_peak"], l["past_peak"], l["tick_cap"]) / maxf(float(l["budget"]), 1.0)


func _print_launch() -> void:
	for kmh in LAUNCH_MARKS:
		if _launch.has(kmh):
			print("  %-13s : %s" % ["launch 0-%.0f" % kmh, _loss_label(_launch[kmh])])


## One tick of the launch trace (§ launch trace): its line on cadence (and on every gear change
## inside the launch), then the gates' running state until the launch window closes. Every field is
## the state the car's last tick left, read as `_sample_launch` reads it; the two cuts are the ones
## that shaped that tick (`_latch_cuts`), so a CUT line reads fuel 0.
func _sample_gates() -> void:
	var spec: VehicleSpec = _car.spec
	var dt: Drivetrain = _car.drivetrain
	var v: float = _car.telemetry.speed
	var gear := dt.gear_byte
	if _gate.is_empty():
		_gate = {"open": true, "end": "", "end_t": 0.0, "gear": gear, "since": 0.0, "shifts": [],
				"dwell_min": INF, "dwell_gear": gear, "limiter": 0, "cut": false, "cuts": [],
				"gap": {"over": -INF}, "shift_gap": {"over": -INF}, "events": [], "a_peak": 0.0, "a_peak_t": 0.0, "lifted": 0, "pitch": [],
				"h_l": (_car.global_transform * _car.center_of_mass).y
						/ maxf(_transfer_wheelbase(), 0.01)}
	_trace_ticks += 1
	var wheel_rpm := Drivetrain.wheel_engine_rpm(spec, _driven_omega(), gear)
	var cut := _limiter_cut
	var share := _front_axle_load() / maxf(_parked_front, 1.0)
	var xfer := _transfer_share(_inst_a)
	var shifted := gear != int(_gate["gear"])
	if (_t <= _trace_s and (_trace_ticks - 1) % _trace_every == 0) or (shifted and _gate["open"]):
		print(_trace_line(wheel_rpm, share, xfer))
	if not _gate["open"]:
		return
	var road_omega := v / dt.road_radius
	if shifted:
		var from := int(_gate["gear"])
		var dwell := _t - float(_gate["since"])
		if dwell < float(_gate["dwell_min"]):
			_gate["dwell_min"] = dwell
			_gate["dwell_gear"] = from
		var rec := _shift_record(from, gear)
		rec["slip_ticks"] = 0
		rec["tc_peak"] = 0.0
		(_gate["shifts"] as Array).append(rec)
		_gate["slipping"] = rec
		_gate["gear"] = gear
		_gate["since"] = _t
	# The shift's handover: its ticks until the coupling locks (or the converter's law takes it), and
	# the peak torque it carried at the crank.
	var slipping: Dictionary = _gate.get("slipping", {})
	if not slipping.is_empty():
		slipping["slip_ticks"] = int(slipping["slip_ticks"]) + 1
		slipping["tc_peak"] = maxf(float(slipping["tc_peak"]), absf(dt.coupling_torque))
		if dt.coupling_state != Drivetrain.CouplingState.SLIPPING or dt.converting:
			slipping["slip_s"] = float(slipping["slip_ticks"]) / Engine.physics_ticks_per_second
			_gate["slipping"] = {}
	if cut:
		_gate["limiter"] = int(_gate["limiter"]) + 1
		if not _gate["cut"]:
			(_gate["cuts"] as Array).append(_t)
	_gate["cut"] = cut
	if _front_lifted():
		_gate["lifted"] = int(_gate["lifted"]) + 1
	# Accelerating ticks only: on a slowing one (the brake's release) the gap is the body's lag. A gap
	# inside a shift's handover or cut belongs to the shift policy: kept apart, reported, not gated.
	var handover: Dictionary = _gate.get("slipping", {})
	var in_shift := not handover.is_empty() or _shift_cut
	var key := "shift_gap" if in_shift else "gap"
	# Judged on the overshoot (`_gap_split`'s `over`): what the body's pitching and heave leave of it,
	# as a two-tick mean. Under the tyre's LOW_SPEED_FLOOR a take-up's drive force alternates at the
	# tick rate, which the body cannot follow and a steady reference must not chase.
	var kin := _body_kinematics()
	var split := _gap_split(kin, _gate.get("kin", {}), xfer - share)
	_gate["kin"] = kin
	var over := NAN
	if not split.is_empty():
		over = 0.5 * (float(split["over"]) + float(_gate.get("last_over", split["over"])))
		_gate["last_over"] = split["over"]
	if _inst_a > 0.0 and not is_nan(over) and over > float(_gate[key]["over"]):
		_gate[key] = {"over": over, "gap": xfer - share, "t": _t, "share": share,
				"a": _inst_a, "split": split,
				"shift": "%s>%s" % [_gear_label(handover["from"]), _gear_label(handover["to"])]
				if not handover.is_empty() else "a shift cut"}
	# Each event (the launch, then each shift's settle) is judged on its own swing: the largest step
	# the steady share has taken within it, as a two-tick mean like `over`. The launch's runs from
	# parked (1.0). A shift's is the larger of the rise through its handover and cut (from the shift's
	# tick to its highest) and the fall since, the body still answering the first as the second comes.
	# Its worst tick is kept.
	var xfer_mean := 0.5 * (xfer + float(_gate.get("last_xfer", xfer)))
	_gate["last_xfer"] = xfer
	if shifted:
		_gate["shift_lo"] = xfer_mean
		_gate["shift_hi"] = xfer_mean
	elif in_shift:
		_gate["shift_hi"] = maxf(float(_gate.get("shift_hi", xfer_mean)), xfer_mean)
	if key == "gap" and _inst_a > 0.0 and not is_nan(over):
		var shifts: Array = _gate["shifts"]
		var event := "launch" if shifts.is_empty() else "%s>%s" % [
				_gear_label(shifts[-1]["from"]), _gear_label(shifts[-1]["to"])]
		var events: Array = _gate["events"]
		if events.is_empty() or events[-1]["event"] != event:
			var launch := shifts.is_empty()
			events.append({"event": event, "margin": -INF, "peak": {"over": -INF},
					"hi": 1.0 if launch else float(_gate.get("shift_hi", xfer_mean)),
					"lo": 1.0 if launch else float(_gate.get("shift_lo", xfer_mean))})
		var e: Dictionary = events[-1]
		var hi := float(e["hi"])
		var swing := maxf(hi - float(e["lo"]), hi - xfer_mean)
		var allowance := maxf(GATE_XFER_GAP, _step_overshoot(GATE_XFER_ZETA) * swing)
		var tick := {"over": over, "allowance": allowance, "t": _t}
		if over - allowance > float(e["margin"]):
			e["margin"] = over - allowance
			e["worst"] = tick
		if over > float(e["peak"]["over"]):
			e["peak"] = tick
	# The launch gear's stretch, for the pitch-per-g reading: t, pitch over parked, predicted, a.
	if (_gate["shifts"] as Array).is_empty():
		(_gate["pitch"] as Array).append(Vector4(_t, _car.telemetry.pitch - _parked_pitch,
				_predicted_pitch(_inst_a), _inst_a))
	if _inst_a > float(_gate["a_peak"]):
		_gate["a_peak"] = _inst_a
		_gate["a_peak_t"] = _t
	if _held_gear > 0:
		var up := ShiftPolicy.upshift_rpm(spec, gear, 1.0)
		if Drivetrain.wheel_engine_rpm(spec, road_omega, gear) >= up:
			_close_gates("held in D%d to its %.0f rpm upshift point" % [gear, up])
	elif v * 3.6 >= LAUNCH_MARKS[-1]:
		_close_gates("to %.0f km/h" % LAUNCH_MARKS[-1])


func _close_gates(why: String) -> void:
	_gate["open"] = false
	_gate["end"] = why
	_gate["end_t"] = _t


## "  1.250   38.2   D1  4980    5010 S   -30  0.59  1.00    -     -    86% | FL +0.11* FR +0.10 ":
## t, km/h, gear, published rpm (the crank), the wheel-side rpm through the gear (the coupling's
## synchronous speed), the coupling's state (O open, S slipping, L locked) and slip (crank less
## wheel side, rpm), `clutch` (the commanded capacity over the rating), the delivered fuel
## (`applied_throttle`), the limiter and shift cuts, the front axle's load over parked and what
## steady transfer predicts at the body's acceleration (`_transfer_share`), that acceleration in g,
## then each driven wheel's slip (signed by its force; * = its TC held drive back).
func _trace_line(wheel_rpm: float, front_share: float, xfer: float) -> String:
	var dt: Drivetrain = _car.drivetrain
	var slips: Array[String] = []
	for w in _car.wheels:
		if w.driven:
			slips.append("%s %+.2f%s" % [_wheel_label(w), w.slip * signf(w.force_long),
					"*" if w.tcs_active else " "])
	# `c`: O(pen), S(lipping), L(ocked), or H while the converter's (hydrodynamic) law carries it.
	var state := "H" if dt.converting else "OSL"[dt.coupling_state]
	return ("  %7.3f %6.1f %4s %5.0f %7.0f %s %5.0f %6.2f %6.0f %5.2f %4s %5s %5.0f%% %4.0f%% %+5.2f"
			+ " | %s") % [_t,
			_car.telemetry.speed * 3.6, _gear_label(dt.gear_byte), _car.telemetry.rpm, wheel_rpm,
			state, _car.telemetry.rpm - wheel_rpm, dt.clutch, dt.coupling_torque, dt.applied_throttle,
			"CUT" if _limiter_cut else "-", "CUT" if _shift_cut else "-", front_share * 100.0,
			xfer * 100.0, _inst_a / 9.81, " ".join(slips)]


func _print_trace_header() -> void:
	print("  %-13s : parked front axle %.1f kN; a line every %d tick(s) to %.1f s, and each gear change"
			% ["trace", _parked_front / 1000.0, _trace_every, _trace_s])
	print("  %7s %6s %4s %5s %7s %s %5s %6s %6s %5s %4s %5s %6s %5s %5s | %s" % ["t s", "km/h",
			"gear", "rpm", "whl rpm", "c", "slip", "clutch", "Tc", "fuel", "lim", "shift", "front",
			"xfer", "a g", "driven slip (* = TC)"])


## The launch gates (§ launch trace), each PASS or FAIL with its figure.
func _print_gates() -> void:
	if _gate.is_empty():
		return
	if _gate["open"]:
		_close_gates("until the pass ended at %.1f km/h" % (_car.telemetry.speed * 3.6))
	var spec: VehicleSpec = _car.spec
	print("  %-13s : over the launch %s, %.2f s" % ["gates", _gate["end"], _gate["end_t"]])
	var shifts: Array = _gate["shifts"]
	var downs := 0
	var steps: Array[String] = []
	for s: Dictionary in shifts:
		if int(s["to"]) < int(s["from"]):
			downs += 1
		steps.append("%s>%s %.2f s" % [_gear_label(s["from"]), _gear_label(s["to"]), s["t"]])
	_gate_line("shifts", downs == 0, "%d%s%s" % [shifts.size(), ", %d down" % downs if downs > 0
			else "", ": " + ", ".join(steps) if not steps.is_empty() else ""])
	if not shifts.is_empty():
		print("  %-13s : %s" % ["  each shift", _shifts_label(shifts)])
	var dwell: float = _gate["dwell_min"]
	_gate_line("gear dwell", dwell >= GATE_MIN_GEAR_S, "no gear left" if is_inf(dwell)
			else "shortest %.2f s in %s, floor %.2f s" % [dwell, _gear_label(_gate["dwell_gear"]),
			GATE_MIN_GEAR_S])
	var cuts: Array = _gate["cuts"]
	var limiter := "%d ticks" % _gate["limiter"]
	if cuts.size() >= 2:
		var span: float = cuts[-1] - cuts[0]
		limiter += ", the cut cycles at %.1f Hz (%d cuts over %.2f s)" % [(cuts.size() - 1) / span,
				cuts.size(), span]
	elif cuts.size() == 1:
		limiter += ", one cut from %.2f s" % cuts[0]
	_gate_line("limiter", int(_gate["limiter"]) == 0, limiter)
	_gate_line.callv(["landing"] + _landing_gate(shifts, spec))
	_gate_line.callv(["hunting"] + _hunting_gate(shifts))
	var gap: Dictionary = _gate["gap"]
	var events: Array[String] = []
	var within := true
	for e: Dictionary in _gate["events"]:
		var over := float(e["margin"]) > 0.0
		within = within and not over
		var tick: Dictionary = e["worst"] if over else e["peak"]
		events.append("%s %.1f of %.1f at %.2f s%s" % [e["event"], float(tick["over"]) * 100.0,
				float(tick["allowance"]) * 100.0, tick["t"], " OVER" if over else ""])
	_gate_line("front axle", int(_gate["lifted"]) == 0 and within,
			"%s, lifted %d ticks; allowance %.0f %% of each event's swing, at least %.0f points" % [
			_gap_label(gap), _gate["lifted"], _step_overshoot(GATE_XFER_ZETA) * 100.0,
			GATE_XFER_GAP * 100.0])
	if gap.has("split"):
		print("  %-13s : %s (the peak tick's)" % ["  front split", _split_label(gap["split"])])
	if not events.is_empty():
		print("  %-13s : %s (points of overshoot against that tick's allowance: each event's peak, or its worst tick when OVER)"
				% ["  per event", ", ".join(events)])
	var shift_gap: Dictionary = _gate["shift_gap"]
	if not is_inf(float(shift_gap["over"])):
		# Not a gate: § The shift policy owns it.
		print("  %-13s : %s, in %s (§ The shift policy)" % ["  in shifts", _gap_label(shift_gap),
				shift_gap["shift"]])
	print("  %-13s : peak acceleration %.2f g at %.2f s" % ["  front why",
			float(_gate["a_peak"]) / 9.81, _gate["a_peak_t"]])
	_print_pitch()


## The share of a step a second-order body damped at `zeta` (0..1) overshoots it by.
static func _step_overshoot(zeta: float) -> float:
	return exp(-zeta * PI / sqrt(1.0 - zeta * zeta))


## "8 points of overshoot (two-tick mean) at 2.25 s (that tick: 12 under steady transfer, 49 % of
## parked at +0.43 g)": a `_sample_gates` peak. `front split` is that tick's alone.
static func _gap_label(gap: Dictionary) -> String:
	if is_inf(float(gap["over"])):
		return "no accelerating tick"
	return ("%.0f points of overshoot (two-tick mean) at %.2f s (that tick: %.0f under steady "
			+ "transfer, %.0f %% of parked at %+.2f g)") % [
			float(gap["over"]) * 100.0, gap["t"], float(gap["gap"]) * 100.0,
			float(gap["share"]) * 100.0, float(gap["a"]) / 9.81]


## Not a gate: body pitch over a/g on the launch gear's middle stretch (PITCH_TRIM), beside h/L and
## what the springs and links predict (`_predicted_pitch`), both averaged over the same ticks.
func _print_pitch() -> void:
	var samples: Array = _gate["pitch"]
	if samples.size() < 2:
		return
	var t0: float = samples[0].x
	var span: float = samples[-1].x - t0
	var sum := Vector3.ZERO  # pitch, predicted, a
	var n := 0
	for s: Vector4 in samples:
		if s.x >= t0 + span * PITCH_TRIM and s.x <= t0 + span * (1.0 - PITCH_TRIM):
			sum += Vector3(s.y, s.z, s.w)
			n += 1
	var g := sum.z / maxf(n, 1) / 9.81
	if n == 0 or g <= 0.01:
		print("  %-13s : no steady stretch in the launch gear" % "  pitch")
		return
	print(("  %-13s : %.2f deg per g over %.2f-%.2f s of the launch gear at %.2f g, predicted %.2f"
			+ " (springs and links); h/L %.2f") % ["  pitch", sum.x / n / g,
			t0 + span * PITCH_TRIM, t0 + span * (1.0 - PITCH_TRIM), g, sum.y / n / g, _gate["h_l"]])


func _gate_line(gate: String, ok: bool, detail: String) -> void:
	print("  %-13s : %s  %s" % ["  " + gate, "PASS" if ok else "FAIL", detail])


## One shift as the gates judge it, read on the tick the byte changed: when, from and to, the road
## speed, the crank rpm that road speed gives in the gear left (`before`) and the gear taken
## (`land`), and the pedal the shift policy read (`Drivetrain.last_pedal`).
func _shift_record(from: int, to: int) -> Dictionary:
	var spec: VehicleSpec = _car.spec
	var v: float = _car.telemetry.speed
	var road_omega := v / _car.drivetrain.road_radius
	return {"t": _t, "from": from, "to": to, "kmh": v * 3.6,
			"before": Drivetrain.wheel_engine_rpm(spec, road_omega, from),
			"land": Drivetrain.wheel_engine_rpm(spec, road_omega, to),
			"pedal": _car.drivetrain.last_pedal}


## "D1>D2 46.1 km/h 5900>3800 rpm, ...": each `_shift_record` on road speed; on the launch trace
## also its slip ("slip 0.30 s Tc 412": the time until the coupling locked and the peak torque it
## carried at the crank, the shift's handover).
static func _shifts_label(shifts: Array) -> String:
	var out: Array[String] = []
	for s: Dictionary in shifts:
		var slip := ""
		if s.has("slip_s"):
			slip = " slip %.2f s Tc %.0f" % [s["slip_s"], s["tc_peak"]]
		elif s.has("slip_ticks"):
			slip = " slip open, Tc %.0f" % s["tc_peak"]
		out.append("%s>%s %.1f km/h %.0f>%.0f rpm%s" % [_gear_label(s["from"]), _gear_label(s["to"]),
				s["kmh"], s["before"], s["land"], slip])
	return ", ".join(out)


## Every upshift lands at GATE_LANDING_MARGIN x the downshift point at its pedal or more, or the box
## would hunt back down. [pass, detail]
static func _landing_gate(shifts: Array, spec: VehicleSpec) -> Array:
	var land_low := INF
	var label := "no upshift"
	for s: Dictionary in shifts:
		var down := ShiftPolicy.down_rpm(spec, float(s["pedal"]))
		var land := float(s["land"]) / maxf(down, 1.0)
		if int(s["to"]) > int(s["from"]) and land < land_low:
			land_low = land
			label = "lowest %.2fx (%s>%s lands %.0f rpm over %.0f)" % [land,
					_gear_label(s["from"]), _gear_label(s["to"]), s["land"], down]
	return [land_low >= GATE_LANDING_MARGIN, label + ", floor %.2fx the downshift point"
			% GATE_LANDING_MARGIN]


## No two consecutive shifts in opposite directions inside GATE_MIN_GEAR_S: the box hunting.
## Consecutive pairs suffice, since an opposite pair further apart has a closer one between.
## [pass, detail]
static func _hunting_gate(shifts: Array) -> Array:
	var gap := INF
	var label := "no opposite shifts"
	for i in range(1, shifts.size()):
		var a: Dictionary = shifts[i - 1]
		var b: Dictionary = shifts[i]
		var dt: float = float(b["t"]) - float(a["t"])
		if (int(a["to"]) > int(a["from"])) != (int(b["to"]) > int(b["from"])) and dt < gap:
			gap = dt
			label = "shortest %.2f s between opposite shifts (%s>%s, %s>%s at %.2f s)" % [dt,
					_gear_label(a["from"]), _gear_label(a["to"]), _gear_label(b["from"]),
					_gear_label(b["to"]), b["t"]]
	return [gap >= GATE_MIN_GEAR_S, label + ", floor %.2f s" % GATE_MIN_GEAR_S]


## The driven wheels' mean spin (rad/s), as `WheelDrive.drive_omega` hands it to
## `Drivetrain.process`: through the gear, the wheel-side rpm the limiter judges.
func _driven_omega() -> float:
	var omega := 0.0
	var driven := 0
	for w in _car.wheels:
		if w.driven:
			omega += w.omega
			driven += 1
	return omega / maxf(1.0, driven)


## The front axle's share of its parked load that steady longitudinal transfer predicts at the
## body's acceleration `a` (m/s²): `(N_f - (m a h + F h_hitch) / L) / N_f`. `m` is the chassis'
## mass, `h` its COM's height over the strip, `L` from the front axle to the mean station of the
## others (a tandem shares the transfer), `N_f` the parked load (`_parked_front`). A coupled
## trailer's pull `F` at the hitch's height is what the chassis' tyres push less what its own mass
## takes (`sum force_long - m a`), so a trailer whose brakes still hold reads as the pull it is; the
## chassis' drag, and the change in what the trailer rests on the hitch as it pitches, are left out.
## What a measured share does beyond this is the sprung body pitching past steady state, or an
## acceleration the driveline spiked.
func _transfer_share(a: float) -> float:
	var wheelbase := _transfer_wheelbase()
	if wheelbase <= 0.0 or _parked_front <= 0.0:
		return 1.0
	return (_parked_front - _transfer_moment(a) / wheelbase) / _parked_front


## `_transfer_share`'s `L`: the foremost axle to the mean station of the others (m), not
## `_wheelbase`'s rearmost, so a tandem shares the transfer.
func _transfer_wheelbase() -> float:
	var front_z := _front_z()
	var rear_z := 0.0
	var rears := 0
	for w in _car.wheels:
		if not is_equal_approx(w.anchor.z, front_z):
			rear_z += w.anchor.z
			rears += 1
	return rear_z / maxf(1.0, rears) - front_z


func _front_z() -> float:
	var front_z := INF
	for w in _car.wheels:
		front_z = minf(front_z, w.anchor.z)
	return front_z


## `_transfer_share`'s `m a h + F h_hitch` (N·m).
func _transfer_moment(a: float) -> float:
	var moment := _car.mass * a * (_car.global_transform * _car.center_of_mass).y
	var hitch_y := _hitch_y()
	if hitch_y >= 0.0:
		var pull := -_car.mass * a
		for w in _car.wheels:
			pull += w.force_long
		moment += pull * hitch_y
	return moment


## A coupled hitch's height over the strip (m), or -1 with nothing coupled.
func _hitch_y() -> float:
	var host := _coupled_host()
	return (_car.global_transform * host.marker_local()).y if host != null else -1.0


## `angdamp=`: the body's angular damping, and a coupled trailer's, REPLACEd with the probe's.
## Every tick, since a trailer couples after its countdown and a respawn may re-couple it.
func _apply_angdamp() -> void:
	if is_nan(_angdamp):
		return
	var bodies: Array[RigidBody3D] = [_car]
	var host := _coupled_host()
	if host != null and host.trailer != null:
		bodies.append(host.trailer)
	for b in bodies:
		VehicleMath.declare_angular_damp(b, _angdamp)


## The coupled hitch, or null with nothing coupled.
func _coupled_host() -> TowHost:
	for node in _car.find_children("*", "", true, false):
		var host := node as TowHost
		if host != null and host.is_coupled():
			return host
	return null


## N a coupled trailer rests on the hitch, off the trailer's own vertical balance: its mass times
## `g` plus its COM's vertical acceleration `z_accel` (m/s²), less what its own wheels carry. 0 with
## nothing coupled.
func _kingpin_load(z_accel: float) -> float:
	var host := _coupled_host()
	if host == null or host.trailer == null:
		return 0.0
	var rests := host.trailer.mass * (9.81 + z_accel)
	for w in host.trailer.wheels:
		rests -= w.suspension_force
	return rests


## Body pitch (deg, + = nose up) that steady transfer at `a` sets on the springs: the transfer
## `_transfer_moment / L` comes off the front axle and onto the others, less what each axle's links
## carry (`RayWheel.link_slope * force_long`, the drive the tyres pass this tick); each axle's spring
## change over its summed rate is its deflection, and their difference over `L` the pitch. Dampers
## and bar read nothing at steady state; the springs' clamps and the tyres' own give are left out.
func _predicted_pitch(a: float) -> float:
	var wheelbase := _transfer_wheelbase()
	if wheelbase <= 0.0:
		return 0.0
	var transfer := _transfer_moment(a) / wheelbase
	var front_z := _front_z()
	var spring := Vector2(-transfer, transfer)  # front, rear: the change each axle's springs carry
	var rate := Vector2.ZERO
	for w in _car.wheels:
		var i := 0 if is_equal_approx(w.anchor.z, front_z) else 1
		spring[i] -= w.link_slope * w.force_long
		rate[i] += w.spring_rate
	if rate.x <= 0.0 or rate.y <= 0.0:
		return 0.0
	return rad_to_deg(atan((spring.y / rate.y - spring.x / rate.x) / wheelbase))


## N on the foremost axle's springs (the axle `_front_lifted` judges).
func _front_axle_load() -> float:
	var front_z := INF
	for w in _car.wheels:
		front_z = minf(front_z, w.anchor.z)
	var total := 0.0
	for w in _car.wheels:
		if is_equal_approx(w.anchor.z, front_z):
			total += w.suspension_force
	return total


## The body's motion `_gap_split` differentiates: velocity of the COM (and its vertical part), pitch
## rate (+ = nose up), each wheel's tyre force (the next tick's link force reads it), the pose (the
## COM and the level heading), and a coupled trailer's vertical velocity.
func _body_kinematics() -> Dictionary:
	var body := _car.global_transform.basis
	var force_long := PackedFloat32Array()
	for w in _car.wheels:
		force_long.append(w.force_long)
	var host := _coupled_host()
	return {"vel": _car.linear_velocity, "vy": _car.linear_velocity.y,
			"w": _car.angular_velocity.dot(body.x), "force_long": force_long, "com": _car.global_transform * _car.center_of_mass,
			"ahead": Vector3(-body.z.x, 0.0, -body.z.z).normalized(),
			"trailer_vy": host.trailer.linear_velocity.y if host != null and host.trailer != null
					else 0.0}


## The `front axle` gap taken apart, in shares of the parked load. This tool ticks before its child
## car, so the velocities read now are what the wheel forces read now made. On the sprung body,
## `N_f L = m (g + z'') b - F h + T (h - h_k) + I θ'' - Σ N d` (F the tyres' summed drive force, at
## the road; T a trailer's pull at the hitch's height h_k). Against `_transfer_share`'s
## `m a h + T h_k`, the gap is then:
## - `resistance`: `R (h - h_k) / L`, drag and rolling at the COM (R = F - m a with no trailer);
## - `a lag`: `m (a - a_trace) (h - h_k) / L`, the trace's acceleration (off the telemetry) a tick
##   behind;
## - `heave`: `-z'' / g`, the body rising or settling;
## - `pitch`: `-I θ'' / L`, the body's pitch accelerating;
## - `lean`: `Σ N d / L`, each load's patch `d` ahead of where its station puts it. A patch stays
##   under its hub (`RayWheel.patch_offset`), so a pitched body moves it by the COM's height less
##   the radius times the angle: the pitched pose's steady geometry;
## - `kingpin` (coupled only): `-ΔV e / L`, the load a trailer rests on the hitch (`_kingpin_load`)
##   moved off its parked figure, at `e` ahead of the rear stations. Not taken out of `over`: it is
##   part steady (the trailer's own transfer) and part the trailer's pitch;
## - `residual`: the rest, ~0 when the terms above are the whole story.
## `over`: the overshoot, the gap less resistance, lag and lean (the gate takes a two-tick mean).
## Also the front axle's own split (N): spring, damper (the remainder), bar, link.
func _gap_split(kin: Dictionary, prev: Dictionary, gap: float) -> Dictionary:
	if prev.is_empty() or _parked_front <= 0.0:
		return {}
	var delta := 1.0 / Engine.physics_ticks_per_second
	var wheelbase := _transfer_wheelbase()
	var h := (_car.global_transform * _car.center_of_mass).y
	var hitch_y := _hitch_y()
	var lever := h - maxf(hitch_y, 0.0)
	var per_moment := 1.0 / (wheelbase * _parked_front)
	# Along one level heading: the body's own forward axis turns with its pitch rate between samples.
	var ahead: Vector3 = prev["ahead"]
	var a := ((kin["vel"] as Vector3) - (prev["vel"] as Vector3)).dot(ahead) / delta
	var right := _car.global_transform.basis.x
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	var i_pitch := 1.0 / right.dot(state.inverse_inertia_tensor * right)
	var tyres := 0.0
	# N·m: the loads' moment from their patches sitting off the stations, against the pose the
	# patches were found in (last sample's: the body has moved a tick on since).
	var lean := 0.0
	var com: Vector3 = prev["com"]
	var front := {"spring": 0.0, "damper": 0.0, "bar": 0.0, "link": 0.0}
	var front_z := _front_z()
	var prev_long: PackedFloat32Array = prev["force_long"]
	for i in _car.wheels.size():
		var w: RayWheel = _car.wheels[i]
		tyres += w.force_long
		if w.in_contact:
			var station := _car.center_of_mass.z - w.anchor.z  # ahead of the COM, body space
			lean += w.suspension_force * ((w.contact_point - com).dot(ahead) - station)
		if not is_equal_approx(w.anchor.z, front_z) or not w.in_contact:
			continue
		var spring := w.spring_rate * w.compression
		var bar := w.bar_force(w.bar_rate)
		var link := w.link_slope * prev_long[i]
		front["spring"] += spring
		front["bar"] += bar
		front["link"] += link
		front["damper"] += w.suspension_force - spring - bar - link
	var resistance := tyres - _car.mass * a
	var gd := _car.spec.ground_drive
	var aero := -VehicleMath.air_force(prev["vel"], _wind, _car.global_basis, gd.drag_area,
			gd.side_area, _car.mass, delta).dot(ahead)
	if hitch_y >= 0.0:
		var rolling := 0.0  ## each contact's own, along its wheel (`RayWheel.force_roll`)
		for w in _car.wheels:
			rolling += w.force_roll
		resistance = aero - rolling
	# Drag acts at the aero centre (`WheelDrive.apply_at`), not the COM: its own lever.
	var aero_y := h if gd.aero_centre == Vector3.ZERO \
			else (_car.global_transform * gd.aero_centre).y
	var terms := {
		"resistance": ((resistance - aero) * lever
				+ aero * (aero_y - maxf(hitch_y, 0.0))) * per_moment,
		"a lag": _car.mass * (a - _inst_a) * lever * per_moment,
		"heave": -(float(kin["vy"]) - float(prev["vy"])) / delta / 9.81,
		"pitch": -i_pitch * (float(kin["w"]) - float(prev["w"])) / delta * per_moment,
		"lean": lean * per_moment,
	}
	var host := _coupled_host()
	if host != null:
		var z_accel := (float(kin["trailer_vy"]) - float(prev["trailer_vy"])) / delta
		var ahead_of_rears := front_z + wheelbase - host.marker_local().z
		terms["kingpin"] = -(_kingpin_load(z_accel) - _parked_kingpin) * ahead_of_rears * per_moment
	var residual := gap
	for term: String in terms:
		residual -= float(terms[term])
	terms["residual"] = residual
	return {"front": front, "terms": terms,
			"over": gap - float(terms["resistance"]) - float(terms["a lag"]) - float(terms["lean"])}


## "spring 9.1, damper -0.3, bar 0.0, link 0.0 kN; resistance +0.3, a lag +1.0, ... points".
static func _split_label(split: Dictionary) -> String:
	var front: Array[String] = []
	for part: String in split["front"]:
		front.append("%s %.1f" % [part, float(split["front"][part]) / 1000.0])
	var terms: Array[String] = []
	for term: String in split["terms"]:
		terms.append("%s %+.1f" % [term, float(split["terms"][term]) * 100.0])
	return "%s kN; %s points" % [", ".join(front), ", ".join(terms)]


## "FL", "RR": a wheel's axle (F / R, or A1, A2... front to back past two axles) and side.
func _wheel_label(w: RayWheel) -> String:
	var axles: Array[float] = []
	for o in _car.wheels:
		if not axles.any(func(z: float) -> bool: return is_equal_approx(z, o.anchor.z)):
			axles.append(o.anchor.z)
	axles.sort()
	var i := axles.find_custom(func(z: float) -> bool: return is_equal_approx(z, w.anchor.z))
	var axle := ("F" if i == 0 else "R") if axles.size() == 2 else "A%d" % (i + 1)
	return axle + ("L" if w.anchor.x < 0.0 else "R")


static func _gear_label(byte: int) -> String:
	if Drivetrain.is_drive(byte):
		return "D%d" % byte
	if Drivetrain.is_reverse(byte):
		return "R"
	return "P" if byte == Drivetrain.GEAR_P else "N"


## doc=accel: one launch is done. The body runs floored first, then slip-limited, then the next
## body; no top speed, tracking or other pass.
func _end_launch_run() -> void:
	var marks := {}
	for kmh in LAUNCH_MARKS:
		if _marks.has(kmh):
			marks[kmh] = _marks[kmh]
	print("=== %s, %s ===" % [_variant, "tc" if _tc_run else "floored"])
	for kmh in LAUNCH_MARKS:
		print("  %-13s : %s" % ["0-%.0f km/h" % kmh,
				("%.2f s" % marks[kmh]) if marks.has(kmh) else "not reached in %.0f s" % _seconds])
	_print_launch()
	_current["launch_tc" if _tc_run else "launch"] = {"tc": _tc_run, "marks": marks,
			"loss": _launch.duplicate(true)}
	_current["towed_kg"] = _combination_mass() - _car.spec.mass
	MeasureRig.drive(100.0, 0.0)
	if _tc_run:
		_tc_run = false
		_finish_vehicle()
		return
	_car.respawn()
	_tc_run = true
	_start_accel()


## doc=tyres: the `tc` launch is done (`reached`: at TYRES_LAUNCH_KMH, else out of time). On to the
## cornering pass, then the stop; no top speed or tracking.
func _end_tyre_launch(reached: bool) -> void:
	_current["launch_t"] = _t if reached else NAN
	print("  %-13s : %s" % ["0-%.0f km/h tc" % TYRES_LAUNCH_KMH,
			("%.2f s" % _t) if reached else "not reached in %.0f s" % _seconds])
	_tc_run = false
	MeasureRig.drive(100.0, 0.0)
	_start_cornering()


func _tick_tracking() -> void:
	var pos := _car.global_position
	if _front_lifted():
		_front_lift_ticks += 1
	if not _latched:
		# Latch this pose as the ideal line once the launch transient is over.
		if _car.telemetry.speed >= TRACK_START_SPEED:
			_latched = true
			_track_origin = pos
			_track_right = _car.global_transform.basis.x
			_track_forward = -_car.global_transform.basis.z
			_track_heading = _car.telemetry.heading
		elif _t >= _seconds:
			print("  %-13s : never reached %.0f km/h, skipped" % ["tracking", TRACK_START_SPEED * 3.6])
			_report_tracking(true)
		return
	var offset := pos - _track_origin
	_track_dist = offset.dot(_track_forward)
	_drift_final = offset.dot(_track_right)
	_drift_peak = maxf(_drift_peak, absf(_drift_final))
	# Wrapped difference: heading is [0,360), so a run across north must not read as 359 deg.
	var dh := absf(fposmod(_car.telemetry.heading - _track_heading + 180.0, 360.0) - 180.0)
	_heading_peak = maxf(_heading_peak, dh)
	if _track_dist >= TRACK_DISTANCE or _t >= _seconds:
		_report_tracking(false)


## Every wheel on the foremost axle (front = -Z) is out of contact while another one is down. Not
## "no front contact" alone: before the first wheel tick every wheel reads out of contact.
func _front_lifted() -> bool:
	var front_z := INF
	for w in _car.wheels:
		front_z = minf(front_z, w.anchor.z)
	var other_down := false
	for w in _car.wheels:
		if is_equal_approx(w.anchor.z, front_z):
			if w.in_contact:
				return false
		elif w.in_contact:
			other_down = true
	return other_down


## CORNER_SPEED, or just under a governor that would never let the body reach it (the tractor):
## where the fade starts, so the hold has throttle left.
static func _corner_target(spec: VehicleSpec) -> float:
	if spec.speed_limit_kmh > 0.0:
		return minf(CORNER_SPEED, spec.speed_limit_kmh / 3.6 - Drivetrain.GOVERNOR_BAND)
	return CORNER_SPEED


## Hold `_corner_speed` on the pad, then wind the lock on from zero over CORNER_RAMP_S and watch
## what the tyres will hold. Full pedal up to the speed, then a PI hold (CORNER_PEDAL_KP / _KI)
## through the ramp; a governed or slow body simply sits on the pedal.
func _tick_cornering(delta: float) -> void:
	var vel: Vector3 = _car.linear_velocity
	# Horizontal: a body off the pad edge would otherwise reach the speed by falling.
	var speed := Vector2(vel.x, vel.z).length()
	var err := _corner_speed - speed
	if _corner_ramping:
		_corner_pedal_i = clampf(_corner_pedal_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	var pedal := clampf(_corner_pedal_i + err * CORNER_PEDAL_KP, 0.0, 1.0) if _corner_ramping \
			else 1.0
	if not _corner_ramping:
		MeasureRig.drive(pedal * 100.0, 0.0)
		# Wait for the speed, but never past the budget — a body that cannot reach 40 km/h says so
		# rather than silently reporting the transient.
		if speed >= _corner_speed:
			_corner_ramping = true
			_corner_pedal_i = CORNER_PEDAL_START
			_corner_xfer0 = _axle_transfer()
		elif _t >= _seconds:
			print("  %-13s : never reached %.0f km/h, skipped"
					% ["cornering", _corner_speed * 3.6])
			_report_cornering(true)
		return
	_corner_ramp_t += delta
	MeasureRig.drive(pedal * 100.0, 0.0, minf(_corner_ramp_t / CORNER_RAMP_S, 1.0) * 100.0)
	# Lateral acceleration of the motion that actually happened: `v * yaw_rate` is the centripetal
	# term of the body's own velocity and angular velocity, both read out of the sim (rule 3).
	var lat := speed * absf(_car.angular_velocity.y)
	_corner_lat += (lat - _corner_lat) * clampf(delta / CORNER_SMOOTH_S, 0.0, 1.0)
	var airborne := 0
	for w in _car.wheels:
		if not w.in_contact:
			airborne += 1
	_corner_lifted = maxi(_corner_lifted, airborne)
	var slip_angle := absf(vel.dot(_car.global_transform.basis.x)) / maxf(speed, 1.0)
	_corner_path += (absf(_car.telemetry.acc_lat) - _corner_path) * clampf(delta / CORNER_SMOOTH_S,
			0.0, 1.0)
	if slip_angle <= CORNER_MAX_SLIP_ANGLE:
		_corner_path_peak = maxf(_corner_path_peak, _corner_path)
	if slip_angle > CORNER_MAX_SLIP_ANGLE:
		_corner_slid = true
	elif _corner_lat > _corner_peak:
		_corner_peak = _corner_lat
		_corner_front = _axle_saturation(false)
		_corner_rear = _axle_saturation(true)
		_corner_roll = absf(VehicleMath.roll_deg(_car.global_transform.basis))
		_corner_drive = 0.0
		for w in _car.wheels:
			if w.in_contact:
				_corner_drive += w.force_long
		_corner_lltd = _lltd(_axle_transfer() - _corner_xfer0)
	if _corner_ramp_t >= CORNER_RAMP_S or _t >= _seconds:
		_report_cornering(false)


## Share of the friction ellipse one axle's contacts use, each tyre's
## `|(force_long / long budget, force_lat / lat budget)|` weighted by its side budget, 1.0 being a
## saturated axle: a driven wheel's drive spends the budget its side grip would use
## (`RayWheel.combined_slip_force`). The weight keeps an inner wheel unloaded to ~0 N from halving
## the reading while its partner carries the axle. The budgets are rebuilt through
## `RayWheel.load_scaled_mu` rather than stored on the wheel, so the reading cannot drift away from
## the law the sim actually applied.
func _axle_saturation(rear: bool) -> float:
	var gd: GroundDriveSpec = _car.spec.ground_drive
	var total := 0.0
	var weight := 0.0
	for w in _car.wheels:
		if w.is_rear != rear or not w.in_contact:
			continue
		var ref_load: float = w.corner_mass * 9.81
		var budget_long := _long_budget(w, gd)
		var budget_lat: float = RayWheel.load_scaled_mu(
				gd.mu_lat * w.axle_lat_grip * w.surface_grip,
				w.suspension_force * w.tyre_share, ref_load, gd.load_sensitivity) * w.suspension_force
		total += Vector2(w.force_long / maxf(budget_long, 1.0),
				w.force_lat / maxf(budget_lat, 1.0)).length() * budget_lat
		weight += budget_lat
	return total / maxf(weight, 1.0)


## A contact's longitudinal grip budget (N): load-scaled `mu_long` times its spring load.
static func _long_budget(w: RayWheel, gd: GroundDriveSpec) -> float:
	return RayWheel.load_scaled_mu(gd.mu_long * w.surface_grip, w.suspension_force,
			w.corner_mass * 9.81, gd.load_sensitivity) * w.suspension_force


func _report_cornering(skipped: bool) -> void:
	# Release the lock before anything else: a held steer input would ride into the next vehicle's
	# passes and read there as a chassis that pulls.
	MeasureRig.drive(100.0, 0.0)
	if skipped:
		_current["cornering"] = {"skipped": true, "speed_kmh": _corner_speed * 3.6}
		_after_lateral_passes()
		return
	var axle := "front" if _corner_front >= _corner_rear else "rear"
	var note := "  <-- SLID: peak is the last reading before the body let go" if _corner_slid else ""
	# BalanceModel's free-rolling limit beside the reading (`docs/vehicles.md` § Balance: the pass
	# runs driven, at 9-23 deg of lock on these wheelbases).
	var model := BalanceModel.axles(_car.spec, _corner_speed)
	var lim := BalanceModel.limit(model)
	var pred := "-" if lim.is_empty() else "%s first, %+.1f %%" % [
			"front" if float(lim["margin"]) >= 0.0 else "rear", float(lim["margin"]) * 100.0]
	print("  %-13s : peak %.2f m/s^2 (%.2f g) at %.0f km/h; %s saturates first"
			% ["cornering", _corner_peak, _corner_peak / 9.81, _corner_speed * 3.6, axle]
			+ " (front %.2f, rear %.2f; pred %s)%s" % [_corner_front, _corner_rear, pred, note])
	# The drive the speed hold spends at the peak: a driven axle saturates before its side force
	# alone says, which BalanceModel's free-rolling limit does not see.
	print("  %-13s : path %.2f g at most (`acc_lat`); drive %.0f N at the peak"
			% ["", _corner_path_peak / 9.81, _corner_drive])
	print(("  %-13s : roll %.1f deg at the peak (pred %.1f), front %s (pred %s) of the load transfer,"
			+ " up to %d wheel(s)") % ["", _corner_roll,
			BalanceModel.roll_deg(model, _corner_peak / 9.81), _pct(_corner_lltd),
			_pct(BalanceModel.lltd(model)), _corner_lifted]
			+ " off the ground%s" % ("  <-- OVERTURNED" if _car.is_overturned() else ""))
	_current["cornering"] = {"skipped": false, "peak": _corner_peak, "speed_kmh": _corner_speed * 3.6,
			"peak_g": _corner_peak / 9.81, "path_g": _corner_path_peak / 9.81, "front": _corner_front,
			"rear": _corner_rear, "axle": axle, "slid": _corner_slid, "roll_deg": _corner_roll, "lltd": _corner_lltd,
			"wheels_lifted": _corner_lifted, "overturned": _car.is_overturned()}
	_after_lateral_passes()


## Mass of everything this run accelerates (chassis + coupled sub-bodies), in kg. Not
## `spec.mass`: a semi couples its trailer as a sibling, never a child (TowHost.couple).
func _rig_bodies() -> Array:
	var out: Array = [_car]
	for child in get_children():
		var body := child as RigidBody3D
		if body != null and body != _car and body.get("wheels") != null:
			out.append(body)
	return out


func _combination_mass() -> float:
	var total: float = _car.mass
	for child in get_children():
		var body := child as RigidBody3D
		if body != null and body != _car:
			total += body.mass
	return total


## `capped`: the time cap ended the pass, not the settle test, so the top figure is a floor.
func _report_accel(capped: bool) -> void:
	var spec: VehicleSpec = _car.spec
	var all_up := _combination_mass()
	# Chassis and all-up mass reported separately where they differ (see _combination_mass).
	var mass_label := "%.0f kg" % spec.mass
	if not is_equal_approx(all_up, spec.mass):
		mass_label = "%.0f kg chassis, %.0f kg all up" % [spec.mass, all_up]
	if _current.has("trailer"):
		mass_label += ", trailer=%s" % _current["trailer"]
	print("=== %s (%s), %s, %s ===" % [_variant, Catalog.VARIANTS[_variant]["family"],
			mass_label, _drive_label(spec)])
	_current["mass_label"] = mass_label
	_current["towed_kg"] = all_up - spec.mass
	_current["drive_label"] = _drive_label(spec)
	_current["marks"] = _marks.duplicate(true)
	for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
		var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
		print("  %-13s : %s" % [label,
				("%.2f s" % _marks[kmh]) if _marks.has(kmh) else "not reached"])
	if _marks.has("quarter"):
		var q: Vector2 = _marks["quarter"]
		print("  %-13s : %.2f s @ %.1f km/h" % ["quarter mile", q.x, q.y])
	if _tc_run:
		print("  %-13s : slip-limited at %.2f on the worst driven wheel (tc)"
				% ["pedal", TcPedal.TARGET_SLIP])
	var run: Array[String] = []
	if _notc:
		run.append("traction control off (notc)")
	if _held_gear > 0:
		run.append("manual, held in D%d (gear=%d)" % [_held_gear, _held_gear])
	if _pedal < 1.0:
		run.append("pedal held at %.2f (pedal=)" % _pedal)
	if not is_nan(_engine_inertia):
		run.append("crank inertia %.3f kg·m² (j=, not the spec's)" % _engine_inertia)
	if not run.is_empty():
		print("  %-13s : %s" % ["run", ", ".join(run)])
	_print_launch()
	_current["launch"] = {"tc": _tc_run, "loss": _launch.duplicate(true)}
	if _trace:
		_print_gates()
	# The passes after this one run floored, in D with the body's TC.
	_tc_run = false
	InputRouter.set_manual_gearbox(false)
	MeasureRig.drive(100.0, 0.0)
	# Settled, capped, or a peak the body then lost: three different claims, never one label.
	var v_now: float = _car.telemetry.speed
	var top_label := "top (settled)"
	var top_note := ""
	if capped:
		top_label = "top (time cap)"
		top_note = "  <-- still gaining %.2f km/h over the last %.1f s: a floor, not terminal" \
				% [(_peak - _prev_settle_v) * 3.6, _t - _prev_settle_t]
	elif v_now < _peak * 0.95:
		top_label = "top (lost)"
		top_note = "  <-- speed fell to %.1f km/h after the peak: not terminal" % (v_now * 3.6)
	print("  %-13s : %.1f km/h (%.1f mph), gear %d @ %.0f rpm%s" % [top_label,
			_peak * 3.6, _peak * 2.23694, _car.telemetry.gear_byte, _car.telemetry.rpm, top_note])
	_current["top_label"] = top_label
	_current["top_kmh"] = _peak * 3.6
	_top_seen = _peak
	_current["top_gear"] = _car.telemetry.gear_byte
	_current["top_rpm"] = _car.telemetry.rpm
	# Distance separates "settled at terminal speed" from "ran out of strip" (`_peak` is a running maximum).
	var v: float = _car.telemetry.speed
	var ran_out := _dist >= RUN_LENGTH - 50.0
	var off_edge := _lateral_peak >= STRIP_WIDTH * 0.5 - 2.0
	print("  %-13s : %.0f m used of %.0f m, %.0f m left; speed now %.1f km/h%s"
			% ["distance", _dist, RUN_LENGTH, RUN_LENGTH - _dist, v * 3.6,
			"  <-- STRIP RAN OUT, top speed is not terminal" if ran_out else ""])
	print("  %-13s : %.1f m off the centre line at most, %.0f m to the edge%s"
			% ["  lateral", _lateral_peak, STRIP_WIDTH * 0.5,
			"  <-- LEFT THE STRIP, nothing after that is a measurement" if off_edge else ""])
	_current["dist"] = _dist
	_current["run_length"] = RUN_LENGTH
	_current["speed_now_kmh"] = v * 3.6
	_current["ran_out"] = ran_out
	# Force balance vs. the body's own acceleration: `resistance` matches the spec's declared
	# `0.5*rho*Cd*A*v^2 + crr*N`, `tyres` matches `axle_torque / r`, `rake` is the suspension
	# force along travel (~0 on flat ground). Summed over the whole combination so a
	# trailer's coupling force cancels.
	var normal_load := 0.0
	var tyre := 0.0
	var applied := 0.0
	var declared := 0.0
	var rake := 0.0
	for body in _rig_bodies():
		var bs: GroundDriveSpec = body.spec.ground_drive
		var body_load := 0.0
		var vdir: Vector3 = body.linear_velocity.normalized()
		for w in body.wheels:
			body_load += w.suspension_force
			tyre += w.force_long
			applied += absf(w.force_roll)
			# Per wheel: the four contacts of a body straddling a crest do not share one normal.
			rake += w.suspension_force * w.contact_normal.dot(vdir)
		normal_load += body_load
		applied += VehicleMath.air_force(body.linear_velocity, _wind, body.global_basis, bs.drag_area,
				bs.side_area, body.mass, get_physics_process_delta_time()).length()
		declared += VehicleMath.aero_drag(body.linear_velocity.length(), bs.drag_area) \
				+ VehicleMath.rolling_drag(MeasureRig.crr(body), body.mass * 9.81)
	var net := tyre - applied + rake
	var up_dot := rake / maxf(normal_load, 1.0)
	print("  %-13s : tyres %.0f N - resistance %.0f N (declared %.0f) + rake %.0f N = %.0f N"
			% ["balance", tyre, applied, declared, rake, net])
	print("  %-13s : contacts %.2f deg %s of perpendicular put %.1f%% of the %.0f N load into"
			% ["  rake", absf(rad_to_deg(asin(clampf(up_dot, -1.0, 1.0)))),
			"ahead" if rake > 0.0 else "behind", absf(up_dot) * 100.0, normal_load]
			+ " travel; a %.4f m/s^2 vs %.4f measured" % [net / all_up, _inst_a])
	_current["balance"] = {"tyre": tyre, "applied": applied, "declared": declared,
			"rake": rake, "net": net}
	# Unreachable ratios: the vehicle carries gears it can never use.
	var top_gear: int = _car.telemetry.gear_byte
	if top_gear > 0 and top_gear < spec.gear_ratios.size():
		print("  %-13s : tops out in gear %d of %d — the taller ratios never engage"
				% ["note", top_gear, spec.gear_ratios.size()])
		_current["gear_note"] = "tops out in gear %d of %d" % [top_gear, spec.gear_ratios.size()]
	if _coast:
		print("  %-13s : %s" % ["hull contacts", _contact_label("accel")])
		_current["accel_contacts"] = _contact_label("accel")
		# The speed actually held, not `_peak`: a capped or lost run is not at its peak here.
		var v0 := v
		_reset_pass(Phase.COAST)
		_coast_v0 = v0
		MeasureRig.drive(0.0, 0.0)
		return
	_car.respawn()
	_reset_pass(Phase.TRACKING)


## Throttle is already released; just watch it slow down.
func _tick_coast() -> void:
	for body in _rig_bodies():
		var bs: GroundDriveSpec = body.spec.ground_drive
		_coast_declared += VehicleMath.aero_drag(body.linear_velocity.length(), bs.drag_area) \
				+ VehicleMath.rolling_drag(MeasureRig.crr(body), body.mass * 9.81)
		for w in body.wheels:
			_coast_tyres -= w.force_long
	var dt: Drivetrain = _car.drivetrain
	_coast_overrun += absf(Drivetrain.overrun_torque(_car.spec, dt.rpm, 0.0, dt.gear_byte)) \
			/ _car.spec.ground_drive.drive_radius()
	if dt.coupling_state == Drivetrain.CouplingState.LOCKED:
		var g := Drivetrain.ratio_for_byte(_car.spec, dt.gear_byte)
		_coast_crank_kg += Drivetrain.crank_inertia(_car.spec) * g * g \
				/ (maxf(_car.spec.efficiency, 0.05) * pow(_car.spec.ground_drive.drive_radius(), 2.0))
	_coast_ticks += 1
	if _t < COAST_SECONDS:
		return
	var v: float = _car.telemetry.speed
	var decel := (_coast_v0 - v) / _t          # m/s^2, averaged over the window
	var all_up := _combination_mass()
	var declared := _coast_declared / _coast_ticks
	var overrun := _coast_overrun / _coast_ticks
	var crank_kg := _coast_crank_kg / _coast_ticks
	var tyres := _coast_tyres / _coast_ticks
	print("  %-13s : %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg"
			% ["coast-down", _coast_v0 * 3.6, v * 3.6, _t, decel, decel / 9.81,
			decel * all_up, all_up])
	print("  %-13s : declared resistance %.0f N + engine overrun %.0f N = %.0f N (mean per tick)"
			% ["  model", declared, overrun, declared + overrun])
	# The crank turns with the wheels while its coupling is locked, so it is decelerated too.
	print("  %-13s : the locked crank adds %.0f kg (J G^2 / eta r^2), so the model decelerates"
			% ["", crank_kg] + " %.3f m/s^2" % ((declared + overrun) / (all_up + crank_kg)))
	# What reached the road: the overrun less what the wheels' own spin absorbs or gives back.
	print("  %-13s : the tyres carried %.0f N of retardation, so declared + tyres = %.0f N"
			% ["", tyres, declared + tyres])
	print("  %-13s : %s" % ["hull contacts", _contact_label("coast")])
	_current["coast"] = {"v0_kmh": _coast_v0 * 3.6, "v1_kmh": v * 3.6, "t": _t,
			"decel": decel, "decel_g": decel / 9.81, "force_n": decel * all_up, "mass": all_up,
			"declared_n": declared, "overrun_n": overrun, "tyres_n": tyres, "crank_kg": crank_kg}
	_current["coast_contacts"] = _contact_label("coast")
	MeasureRig.drive(100.0, 0.0)
	_car.respawn()
	_reset_pass(Phase.TRACKING)


func _report_tracking(skipped: bool) -> void:
	# In track-only mode nothing else prints the variant name (the `===` header belongs to the
	# accel report), so a FAIL in an `all` sweep would be anonymous.
	if _track_only:
		print("=== %s ===" % _variant)
	if skipped:
		_current["tracking"] = {"skipped": true}
	else:
		var ok := _drift_peak <= MAX_LATERAL_DRIFT and _heading_peak <= MAX_HEADING_DRIFT \
				and _front_lift_ticks <= MAX_FRONT_LIFT_TICKS
		var known := KNOWN_TRACKING_FAILS.has(_variant)
		if not ok:
			if known:
				_known_failures += 1
			else:
				_failures += 1
		elif known:
			_stale_allowances.append(_variant)
		var verdict := "PASS" if ok else ("FAIL (known)" if known else "FAIL")
		print("  %-13s : %s  drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg,"
				% ["tracking", verdict, _drift_peak, _drift_final,
				_track_dist, _heading_peak]
				+ " front axle off the ground %d ticks" % _front_lift_ticks)
		if _front_lift_ticks > MAX_FRONT_LIFT_TICKS:
			print("                 wheelie — suspect a raised com_y or softer pitch damping")
		elif not ok:
			print("                 straight-line pull — suspect asymmetric wheel_positions,")
			print("                 a one-sided drive split, or uneven brake torque")
		_current["tracking"] = {"skipped": false, "pass": ok, "drift_peak": _drift_peak,
				"drift_final": _drift_final, "track_dist": _track_dist, "heading_peak": _heading_peak,
				"front_lift_ticks": _front_lift_ticks}
	if _corner:
		_start_cornering()
		return
	_after_lateral_passes()


## Onto the pad: spawn_transform is what respawn() re-lays the body (and any trailer) on. Pad top is
## y=0, same as the strip.
func _start_cornering() -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(PAD_X, _car.rest_ride_height(), 0.0))
	_car.respawn()
	_reset_pass(Phase.CORNERING)


## Tracking and the optional cornering pass are done: the braking pass if asked for, else the next
## vehicle.
func _after_lateral_passes() -> void:
	if _brake:
		_start_brake_run()
		return
	_finish_vehicle()


## Re-lay the rig at the strip's start (the cornering pass may have moved it to the pad) and run up
## to this stop's entry speed.
func _start_brake_run() -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_reset_pass(Phase.BRAKING)
	_brake_target = _brake_from if _top_seen <= 0.0 else minf(_brake_from, 0.9 * _top_seen)
	MeasureRig.drive(100.0, 0.0)


func _tick_braking(delta: float) -> void:
	var v: float = _car.telemetry.speed
	if not _brake_on:
		# Up to speed, or out of budget (a body that never gets there brakes from where it is).
		if v >= _brake_target or _t >= _seconds:
			_brake_on = true
			_brake_v0 = v
			_brake_x0 = _car.global_position
			MeasureRig.drive(0.0, _brake_pedals[_brake_i] * 100.0)
		return
	_brake_t += delta
	var skidding := false
	var anti_lock := false
	for body in _rig_bodies():
		for w in body.wheels:
			if w.in_contact and w.slip > BRAKE_LOCK_SLIP:
				skidding = true
			if w.abs_active:
				anti_lock = true
	if skidding:
		_brake_lock_t += delta
	if anti_lock:
		_brake_abs_t += delta
	if absf(v) > BRAKE_STOP_SPEED and _brake_t < _seconds:
		return
	var dist := (_car.global_position - _brake_x0).length()
	var row := {"pedal": _brake_pedals[_brake_i], "v0_kmh": _brake_v0 * 3.6, "t": _brake_t,
			"dist": dist, "g": _brake_v0 / maxf(_brake_t, 1e-6) / 9.81, "skid_t": _brake_lock_t,
			"abs_t": _brake_abs_t}
	_brake_rows.append(row)
	print("  %-13s : %3.0f%% from %.0f km/h: %.2f s, %.1f m, %.2f g mean; skidding %.2f s, ABS %.2f s"
			% ["braking", row["pedal"] * 100.0, row["v0_kmh"], row["t"], row["dist"], row["g"],
			row["skid_t"], row["abs_t"]])
	_brake_i += 1
	if _brake_i < _brake_pedals.size():
		_start_brake_run()
		return
	_current["braking"] = _brake_rows.duplicate(true)
	MeasureRig.drive(100.0, 0.0)
	_finish_vehicle()


func _reset_probe() -> void:
	_probe_on = false
	_probe_t = 0.0
	_probe_v_peak = 0.0
	_probe_spin_peak = 0.0
	_probe_yaw_peak = 0.0
	_probe_turned = 0.0
	_probe_lock_t = 0.0
	_probe_override = false


func _start_stall() -> void:
	_reset_pass(Phase.STALL)
	_reset_probe()
	InputRouter.set_manual_gearbox(true)
	MeasureRig.drive(0.0, 100.0, 0.0, false, 1, true)


func _tick_stall(delta: float) -> void:
	if not _probe_on:
		if _t >= STALL_SETTLE_S:
			_probe_on = true
			_probe_x0 = _car.global_position
			MeasureRig.drive(100.0, 100.0, 0.0, false, 1, true)
		return
	_probe_t += delta
	_probe_v_peak = maxf(_probe_v_peak, absf(_car.telemetry.speed))
	for w in _car.wheels:
		if w.driven:
			_probe_spin_peak = maxf(_probe_spin_peak, absf(w.omega))
	_probe_override = _probe_override or bool(InputRouter.get("_brake_override"))
	if _probe_t < STALL_HOLD_S:
		return
	var moved := (_car.global_position - _probe_x0).length()
	var held := not _probe_override and moved < 0.05
	print(("  %-13s : %s  moved %.3f m in %.0f s, peak %.3f m/s, driven spin peak %.2f rad/s%s;"
			+ " gear %d, %.0f rpm, applied throttle %.2f")
			% ["stall", "HOLDS" if held else "CREEPS", moved, STALL_HOLD_S, _probe_v_peak,
			_probe_spin_peak, ", brake_override latched" if _probe_override else "",
			_car.drivetrain.gear_byte, _car.drivetrain.rpm, _car.drivetrain.applied_throttle])
	_current["stall"] = {"held": held, "moved": moved, "v_peak": _probe_v_peak,
			"spin_peak": _probe_spin_peak, "override": _probe_override}
	InputRouter.set_manual_gearbox(false)
	MeasureRig.drive(100.0, 0.0)
	_finish_vehicle()


func _start_handbrake_run() -> void:
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_reset_pass(Phase.HANDBRAKE)
	_reset_probe()
	MeasureRig.drive(100.0, 0.0)


func _tick_handbrake(delta: float) -> void:
	if not _probe_on:
		if _car.telemetry.speed >= HB_SPEED or _t >= _seconds:
			_probe_on = true
			MeasureRig.drive(0.0, 0.0, HB_STEER, _hb_pulled)
		return
	_probe_t += delta
	if _probe_t >= HB_HOLD_S and _probe_t - delta < HB_HOLD_S:
		MeasureRig.drive(0.0, 0.0, 0.0, false)
	_probe_yaw_peak = maxf(_probe_yaw_peak, absf(rad_to_deg(_car.angular_velocity.y)))
	_probe_turned += rad_to_deg(_car.angular_velocity.y) * delta
	if _probe_t <= HB_HOLD_S:
		var locked := false
		for w in _car.wheels:
			if w.is_rear and w.in_contact and w.slip > BRAKE_LOCK_SLIP:
				locked = true
		if locked:
			_probe_lock_t += delta
	if _probe_t < HB_HOLD_S + HB_AFTER_S:
		return
	var turned := absf(_probe_turned)
	var label := "handbrake" if _hb_pulled else "steer only"
	print(("  %-13s : rears locked %.2f of %.1f s, yaw rate peak %.0f deg/s, turned %.0f deg%s,"
			+ " %.0f km/h left") % [label, _probe_lock_t, HB_HOLD_S, _probe_yaw_peak, turned,
			" (spun)" if turned > 180.0 else "", _car.telemetry.speed * 3.6])
	_current["handbrake_pulled" if _hb_pulled else "handbrake_steer"] = {"lock_t": _probe_lock_t,
			"yaw_peak": _probe_yaw_peak, "turned": turned}
	if not _hb_pulled:
		_hb_pulled = true
		_start_handbrake_run()
		return
	MeasureRig.drive(100.0, 0.0)
	_finish_vehicle()


## The step-steer runs (§ step steer) on this body: its family's STEP_SETS row less the speeds its
## governor would cap, each lock held then lifted.
func _start_step() -> void:
	var family := String(Catalog.VARIANTS[_variant]["family"])
	var limit: float = _car.spec.speed_limit_kmh
	_st_runs = []
	var speeds: Array = _step_speeds if not _step_speeds.is_empty() \
			else STEP_SETS.get(family, STEP_SETS["car"])
	for kmh: float in speeds:
		if limit > 0.0 and kmh >= limit - Drivetrain.GOVERNOR_BAND * 3.6:
			continue
		for lock in STEP_LOCKS:
			for lifted in [false, true]:
				_st_runs.append({"kmh": kmh, "lock": lock, "lifted": lifted})
	_current["step"] = []
	var probe := "" if is_nan(_rear_lat_grip) \
			else ", rear_lat_grip %.2f (not the spec's)" % _rear_lat_grip
	if not is_nan(_bar_rear):
		probe += ", bar_rear %.0f N/m (not the spec's)" % _bar_rear
	if not is_nan(_cornering_peak):
		probe += ", cornering_peak %.2f (not the spec's)" % _cornering_peak
	if not is_nan(_roll_steer.x):
		probe += ", roll steer %.2f / %.2f deg/deg (not the spec's)" % [_roll_steer.x,
				_roll_steer.y]
	if not is_nan(_angdamp):
		probe += ", angular damping %.2f /s (not the body's)" % _angdamp
	print("=== %s (%s), step steer%s ===" % [_variant, _drive_label(_car.spec), probe])
	_next_step_run()


func _next_step_run() -> void:
	if _st_runs.is_empty():
		# Release the lock first: a held steer would ride into the next vehicle's run-up.
		MeasureRig.drive(100.0, 0.0)
		_finish_vehicle()
		return
	_st_run = _st_runs.pop_front()
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_reset_pass(Phase.STEP)
	_st_stage = Step.RUN_UP
	_st_t = 0.0
	_st_target = float(_st_run["kmh"]) / 3.6
	_st_i = CORNER_PEDAL_START
	_st_yaw = PackedFloat32Array()
	_st_tail = Vector3.ZERO
	_st_slip_peak = 0.0
	_st_spin_t = -1.0
	_st_roll_peak = 0.0
	_st_lifted = 0
	_st_roll_t = -1.0
	_st_xfer = Vector2.ZERO
	_st_rs = PackedVector2Array()
	MeasureRig.drive(100.0, 0.0)


func _tick_step(delta: float) -> void:
	var b := _car.global_transform.basis
	var vel := _car.linear_velocity
	var v_long := vel.dot(-b.z)
	_st_t += delta
	if _st_stage == Step.RUN_UP:
		if v_long >= _st_target:
			_st_stage = Step.SETTLE
			_st_t = 0.0
		elif _t >= _seconds:
			# Every run left at this speed would spend the same cap reaching nothing.
			print("  %-13s : %3.0f km/h never reached, its steps skipped" % ["step", _st_run["kmh"]])
			for r: Dictionary in [_st_run] + _st_runs.filter(func(x: Dictionary) -> bool:
					return x["kmh"] == _st_run["kmh"]):
				r["skipped"] = true
				_current["step"].append(r)
			_st_runs = _st_runs.filter(func(x: Dictionary) -> bool: return x["kmh"] != _st_run["kmh"])
			_next_step_run()
		return
	var lifted := bool(_st_run["lifted"]) and _st_stage == Step.STEPPED
	var err := _st_target - v_long
	_st_i = clampf(_st_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	var pedal := 0.0 if lifted else clampf(_st_i + err * CORNER_PEDAL_KP, 0.0, 1.0)
	if _st_stage == Step.SETTLE:
		MeasureRig.drive(pedal * 100.0, 0.0)
		if _st_t >= STEP_SETTLE_S:
			_st_stage = Step.STEPPED
			_st_t = 0.0
			_st_run["v0_kmh"] = v_long * 3.6
			_st_xfer0 = _axle_transfer()
			if not _current.has("yaw_index"):
				_current["yaw_index"] = _yaw_index()
				var yi: Dictionary = _current["yaw_index"]
				print("  %-13s : %.2f (Iyy %.0f kg m², m a b %.0f kg m²)"
						% ["yaw index", yi["index"], yi["iyy"], yi["mab"]])
		return
	MeasureRig.drive(pedal * 100.0, 0.0, float(_st_run["lock"]))
	# Yaw rate in the steered direction: + steer is right, a clockwise turn seen from above.
	_st_yaw.append(-_car.angular_velocity.dot(b.y))
	var slip := absf(rad_to_deg(atan2(vel.dot(b.x), maxf(v_long, 0.1))))
	_st_slip_peak = maxf(_st_slip_peak, slip)
	if slip > STEP_SPIN_DEG and _st_spin_t < 0.0:
		_st_spin_t = _st_t
	_st_roll_peak = maxf(_st_roll_peak, absf(VehicleMath.roll_deg(b)))
	if VehicleMath.is_inverted(b, STEP_ROLL_DEG) and _st_roll_t < 0.0:
		_st_roll_t = _st_t
	var airborne := 0
	for w in _car.wheels:
		if not w.in_contact:
			airborne += 1
	_st_lifted = maxi(_st_lifted, airborne)
	_st_rs.append(_axle_roll_steer(float(_st_run["lock"]) < 0.0))
	if _st_t > STEP_HOLD_S - STEP_STEADY_S:
		# The bicycle angle: with Ackermann the steered wheels' own angles do not average to it.
		_st_tail += Vector3(v_long, absf(_car.drive.mean_steer_angle()), 1.0)
		_st_xfer += _axle_transfer()
	if _st_t >= STEP_HOLD_S:
		_report_step_run(delta)
		_next_step_run()


## The step's figures off its per-tick yaw rate (§ step steer), printed and kept in `_current`.
func _report_step_run(delta: float) -> void:
	var r := _st_run
	var label := "%3.0f km/h %2.0f %% %s" % [r["kmh"], r["lock"], "lifted" if r["lifted"] else "held"]
	# The entry speed the PI settle actually left, beside the nominal one in the label.
	label += " (%.1f)" % float(r["v0_kmh"])
	r["slip_peak"] = _st_slip_peak
	r["spin_t"] = _st_spin_t
	r["roll_t"] = _st_roll_t
	r["lifted_n"] = _st_lifted
	var tilt := "roll peak %.1f deg, up to %d wheel(s) lifted" % [_st_roll_peak, _st_lifted]
	# A rolled body's yaw and slip are read off a body on its side: neither is a handling figure.
	if _st_roll_t >= 0.0:
		print("  %-26s : ROLLED %.2f s into the step (past %.0f deg); %s"
				% [label, _st_roll_t, STEP_ROLL_DEG, tilt])
		if _car.spec.ground_drive.has_roll_steer():
			_report_roll_steer(r, {}, int(_st_tail.z))
		_current["step"].append(r)
		return
	if _st_spin_t >= 0.0:
		print("  %-26s : SPUN %.2f s into the step (slip past %.0f deg); %s"
				% [label, _st_spin_t, STEP_SPIN_DEG, tilt])
		if _car.spec.ground_drive.has_roll_steer():
			_report_roll_steer(r, {}, int(_st_tail.z))
		_current["step"].append(r)
		return
	var ticks := int(_st_tail.z)
	var tail := 0.0
	for i in range(_st_yaw.size() - ticks, _st_yaw.size()):
		tail += _st_yaw[i]
	var steady := tail / maxf(ticks, 1)
	var v_mean := _st_tail.x / maxf(_st_tail.z, 1.0)
	var delta_mean := _st_tail.y / maxf(_st_tail.z, 1.0)
	var neutral := v_mean * delta_mean / _wheelbase()
	var rise := -1.0
	var peak := 0.0
	for i in _st_yaw.size():
		if rise < 0.0 and steady > 0.0 and _st_yaw[i] >= STEP_RISE * steady:
			rise = (i + 1) * delta
		peak = maxf(peak, _st_yaw[i])
	r["steady_dps"] = rad_to_deg(steady)
	r["lat_g"] = v_mean * steady / 9.81
	r["of_neutral"] = steady / neutral if neutral > 0.0 else 0.0
	r["rise_s"] = rise
	r["overshoot"] = peak / steady - 1.0 if steady > 0.0 else 0.0
	r["lltd"] = _lltd(_st_xfer / maxf(_st_tail.z, 1.0) - _st_xfer0)
	# Understeer gradient off the steady tail: the steer past the neutral `L r / v` per g of side
	# force. Held runs only: a lifted run slows through its tail, so it is never steady.
	r["k_dpg"] = NAN
	if not r["lifted"] and r["lat_g"] > 0.01:
		r["k_dpg"] = rad_to_deg((delta_mean - _wheelbase() * steady / v_mean) / r["lat_g"])
	# BalanceModel's prediction beside each, off the live spec (a probe flag included) and the live
	# yaw tensor (Jolt's own where the spec declares none), its downforce at the run's speed.
	var model := BalanceModel.axles(_car.spec, v_mean)
	if not model.is_empty():
		model["yaw_inertia"] = (_current["yaw_index"] as Dictionary)["iyy"]
		if not is_nan(_angdamp):
			model["yaw_damp"] = _angdamp
	var k := "" if is_nan(r["k_dpg"]) else "K %.2f deg/g (pred %.2f), " \
			% [r["k_dpg"], BalanceModel.understeer_gradient(model, r["lat_g"], v_mean)]
	print(("  %-26s : steady %.1f deg/s (%.2f g), %.2f of neutral; %sfront %s (pred %s) of the load"
			+ " transfer; rise %.2f s, overshoot %.0f %%, slip peak %.1f deg, %s") % [label,
			r["steady_dps"], r["lat_g"], r["of_neutral"], k, _pct(r["lltd"]),
			_pct(BalanceModel.lltd(model)), rise, r["overshoot"] * 100.0, _st_slip_peak, tilt])
	if _car.spec.ground_drive.has_roll_steer():
		_report_roll_steer(r, model, ticks)
	_current["step"].append(r)


## Each axle's mean roll-steer angle over the steady tail beside `BalanceModel`'s (its coefficient
## times the predicted roll; "-" on an empty `model`, a spun or rolled run), and the chatter count
## over the whole held step (`chatter_runs`), printed and kept in `r`.
func _report_roll_steer(r: Dictionary, model: Dictionary, ticks: int) -> void:
	var tail := Vector2.ZERO
	for i in range(maxi(_st_rs.size() - ticks, 0), _st_rs.size()):
		tail += _st_rs[i]
	tail = tail / maxf(ticks, 1)
	var roll := BalanceModel.roll_deg(model, r["lat_g"]) if not model.is_empty() else NAN
	var gd := _car.spec.ground_drive
	var fronts := PackedFloat64Array()
	var rears := PackedFloat64Array()
	for v in _st_rs:
		fronts.append(v.x)
		rears.append(v.y)
	r["roll_steer"] = Vector2(rad_to_deg(tail.x), rad_to_deg(tail.y))
	r["chatter"] = chatter_runs(fronts) + chatter_runs(rears)
	var pred := func(coeff: float) -> String: return "-" if is_nan(roll) else "%+.3f" % (coeff * roll)
	print(("  %-26s : roll steer front %+.3f deg (pred %s), rear %+.3f deg (pred %s),"
			+ " + = toward understeer; chatter %d") % ["", rad_to_deg(tail.x),
			pred.call(gd.roll_steer_front), rad_to_deg(tail.y), pred.call(gd.roll_steer_rear),
			r["chatter"]])


## Each axle's mean roll-steer angle this tick (rad; x front, y rear), signed + toward understeer:
## the front out of the turn, the rear into it. `turn_left`: the step's direction.
func _axle_roll_steer(turn_left: bool) -> Vector2:
	var sums := Vector4.ZERO  # front sum, front count, rear sum, rear count
	for w in _car.wheels:
		if w.is_rear:
			sums += Vector4(0.0, 0.0, w.roll_steer(), 1.0)
		else:
			sums += Vector4(w.roll_steer(), 1.0, 0.0, 0.0)
	var front := sums.x / maxf(sums.y, 1.0)
	var rear := sums.z / maxf(sums.w, 1.0)
	# A left turn: out of it is right (-), into it left (+).
	return Vector2(-front, rear) if turn_left else Vector2(front, -rear)


## Pure: the runs in `series` where the tick-to-tick change flips sign on CHATTER_FLIPS or more
## consecutive ticks, a tick-rate oscillation. A change under CHATTER_EPS (rad) or CHATTER_REL of
## the angle is no direction and ends the run: a one-tick contact blip and its return, ticks apart
## from the next, are not a ringing loop.
static func chatter_runs(series: PackedFloat64Array) -> int:
	var runs := 0
	var flips := 0
	var last := 0.0
	for i in range(1, series.size()):
		var d := series[i] - series[i - 1]
		if absf(d) < maxf(CHATTER_EPS, CHATTER_REL * absf(series[i])):
			flips = 0
			last = 0.0
			continue
		if last != 0.0 and signf(d) != signf(last):
			flips += 1
			if flips == CHATTER_FLIPS:
				runs += 1
		else:
			flips = 0
		last = d
	return runs


## The full-lock circle (§ full-lock circle) on this body, from where `_next_vehicle` spawned it.
func _start_circle() -> void:
	_reset_pass(Phase.CIRCLE)
	_ci_i = 0.0
	_ci_sums = {"ticks": 0.0, "v": 0.0, "radius": 0.0, "mean": 0.0, "n_in": 0.0, "n_out": 0.0,
			"angle_in": 0.0, "angle_out": 0.0, "slip_in": 0.0, "slip_out": 0.0}
	var probe := "" if is_nan(_ackermann) else " (not the spec's)"
	print("=== %s (%s), full-lock circle, ackermann %.2f%s ===" % [_variant,
			_drive_label(_car.spec), _car.spec.ground_drive.ackermann, probe])
	MeasureRig.drive(0.0, 0.0, CIRCLE_LOCK)


func _tick_circle(delta: float) -> void:
	var b := _car.global_transform.basis
	var v_long := _car.linear_velocity.dot(-b.z)
	var err := CIRCLE_SPEED - v_long
	_ci_i = clampf(_ci_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	MeasureRig.drive(clampf(_ci_i + err * CORNER_PEDAL_KP, 0.0, 1.0) * 100.0, 0.0, CIRCLE_LOCK)
	if _t < CIRCLE_SETTLE_S:
		return
	var s := _ci_sums
	var rear := _car.global_transform * Vector3(0.0, 0.0,
			float(BrakeSizing.axle_geometry(_car.spec)["rear_z"]))
	var v_rear := VehicleMath.point_velocity(_car, rear)
	v_rear -= b.y * v_rear.dot(b.y)
	s["ticks"] += 1.0
	s["v"] += v_long
	s["radius"] += v_rear.length() / maxf(absf(_car.angular_velocity.dot(b.y)), 1e-4)
	s["mean"] += absf(_car.drive.mean_steer_angle())
	for w in _car.wheels:
		if not w.steered or not w.in_contact:
			continue
		var side := "in" if w.anchor.x > 0.0 else "out"  # a right turn: the inner wheel is +x
		s["n_" + side] += 1.0
		s["angle_" + side] += rad_to_deg(absf(w.steer_angle))
		s["slip_" + side] += _slip_angle_deg(w)
	if _t < CIRCLE_SETTLE_S + CIRCLE_HOLD_S:
		return
	var n: float = s["ticks"]
	var mean: float = s["mean"] / n
	var r := {"kmh": s["v"] / n * 3.6, "radius": s["radius"] / n, "mean_deg": rad_to_deg(mean),
			"law_radius": _wheelbase() / tan(mean)}
	for side in ["in", "out"]:
		var k := maxf(s["n_" + side], 1.0)
		r["angle_" + side] = s["angle_" + side] / k
		r["slip_" + side] = s["slip_" + side] / k
	print(("  %-13s : %.1f km/h, R %.2f m at the rear axle (L / tan δ %.2f, δ %.1f deg); inner"
			+ " %.1f deg slip %+.2f deg, outer %.1f deg slip %+.2f deg") % ["circle", r["kmh"],
			r["radius"], r["law_radius"], r["mean_deg"], r["angle_in"], r["slip_in"],
			r["angle_out"], r["slip_out"]])
	_current["circle"] = r
	MeasureRig.drive(0.0, 0.0)
	_finish_vehicle()


## A steered wheel's slip angle (deg) in the circle's right turn, off its contact patch's velocity
## as `_split_deficit` reads the wheel's forward: + = it points further right than it travels.
func _slip_angle_deg(w: RayWheel) -> float:
	var n := w.contact_normal
	var fwd := Basis(_car.global_transform.basis.y, w.steer_angle) * -_car.global_transform.basis.z
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var vel := VehicleMath.point_velocity(_car, w.contact_point)
	return rad_to_deg(atan2(-vel.dot(fwd.cross(n)), vel.dot(fwd)))


## The hitch statics (§ hitch statics) on this body: parked, bare first.
func _start_hitch() -> void:
	_reset_pass(Phase.HITCH)
	_hi_ids = []
	_hi_bare = {}
	if not _car is TractorVehicle:
		print("=== %s: no three-point linkage, hitch skipped ===" % _variant)
		_finish_vehicle()
		return
	for id: String in _car.call(&"attachment_ids"):
		if not ImplementCatalog.is_attached(id) or ImplementCatalog.is_towed(id):
			continue
		if _trailer == "" or id.get_file().get_basename() == _trailer:
			_hi_ids.append(id)
	print("=== %s (%s), hitch statics, parked: per-axle kg off the springs ===" % [_variant,
			_drive_label(_car.spec)])
	_car.call(&"set_attachment", AttachmentCatalog.NONE)
	_hi_stage = -1
	_begin_hitch_reading(100.0)


## Command `hitch_pos` (0..100) on the parking brakes and restart the reading's clock.
func _begin_hitch_reading(hitch_pos: float) -> void:
	_t = 0.0
	_hi_sums = Vector3.ZERO
	MeasureRig.drive(0.0, 100.0, 0.0, true, 1, false, 3, {"hitch_pos": hitch_pos})


func _tick_hitch() -> void:
	if _t < HITCH_WAIT_S:
		return
	var axles := Vector2.ZERO
	for w in _car.wheels:
		if w.is_rear:
			axles.y += w.suspension_force
		else:
			axles.x += w.suspension_force
	_hi_sums += Vector3(axles.x, axles.y, 1.0)
	if _t < HITCH_WAIT_S + HITCH_AVG_S:
		return
	_report_hitch_reading()
	# After the bare reading, or an implement's last stage: on to the next implement.
	if _hi_stage >= 0 and _hi_stage + 1 < HITCH_STAGES.size():
		_hi_stage += 1
	elif _hi_ids.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish_vehicle()
		return
	else:
		_car.call(&"set_attachment", _hi_ids.pop_front())
		_hi_stage = 0
	_begin_hitch_reading(HITCH_STAGES[_hi_stage])


## The body-frame inertia tensor (kg·m²) off the live state: `inverse_inertia_tensor` is world-space
## (`RayWheel.size_cap_masses`' read), so it is turned into the body's axes and inverted.
func _body_tensor() -> Basis:
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	var b := _car.global_transform.basis
	return (b.transposed() * state.inverse_inertia_tensor * b).inverse()


## Diagonal of the parallel-axis tensor of `kg` at offset `d`: x pitch, y yaw, z roll.
static func _parallel_axis(kg: float, d: Vector3) -> Vector3:
	return kg * Vector3(d.y * d.y + d.z * d.z, d.x * d.x + d.z * d.z, d.x * d.x + d.y * d.y)


func _report_hitch_reading() -> void:
	var g := _car.get_gravity().length()
	var n := maxf(_hi_sums.z, 1.0)
	var front := _hi_sums.x / n / g
	var rear := _hi_sums.y / n / g
	var rear_z := float(BrakeSizing.axle_geometry(_car.spec)["rear_z"])
	var wheelbase := _wheelbase()
	var m := _car.mass
	var com := _car.center_of_mass
	var front_pred := m * (rear_z - com.z) / wheelbase
	var share := front / maxf(front + rear, 1e-6)
	var tensor := _body_tensor()
	var label := "bare"
	if _hi_stage >= 0:
		var where := "raised" if HITCH_STAGES[_hi_stage] > 50.0 else "bottom stop"
		label = "%s, %s" % [String(_car.call(&"current_attachment")).get_file().get_basename(), where]
	print(("  %-22s: front %.0f kg, rear %.0f kg; statics %.0f / %.0f (front %+.1f %%, rear %+.1f %%);"
			+ " front share %.1f %% (min %.0f %%)") % [label, front, rear, front_pred, m - front_pred,
			(front / front_pred - 1.0) * 100.0, (rear / (m - front_pred) - 1.0) * 100.0, share * 100.0,
			HITCH_FRONT_MIN * 100.0])
	var row := {"label": label, "front_kg": front, "rear_kg": rear, "front_pred": front_pred,
			"share": share, "mass": m, "com_z": com.z, "com_y": com.y}
	if _hi_stage < 0:
		_hi_bare = {"front": front, "mass": m, "com": com, "tensor": tensor}
		print("  %-22s  mass %.0f kg, COM (%.3f, %.3f, %.3f); tensor diagonal %s kg·m²" % ["",
				m, com.x, com.y, com.z, _diag_label(_diag(tensor))])
	else:
		var bare_m: float = _hi_bare["mass"]
		var bare_com: Vector3 = _hi_bare["com"]
		var carried := m - bare_m
		var lines := "  %-22s  mass %.0f kg (+%.0f carried), COM (%.3f, %.3f, %.3f)" % ["", m, carried,
				com.x, com.y, com.z]
		if carried > 0.5:
			# The point the carried load sits at, recovered from the live COM (carried_com inverted).
			var p := bare_com + (com - bare_com) * m / carried
			var d_front_pred := carried * (rear_z - p.z) / wheelbase
			var jolt := _diag(tensor)
			var composite := _diag(_hi_bare["tensor"]) + _parallel_axis(bare_m, bare_com - com) \
					+ _parallel_axis(carried, p - com)
			lines += ("; Δfront %+.0f kg (m e / L %+.0f, e %.2f m behind the rear axle)\n  %-22s  tensor"
					+ " diagonal %s, composite %s: Jolt carries %.0f / %.0f / %.0f %% (pitch / yaw / roll)") \
					% [front - float(_hi_bare["front"]), d_front_pred, p.z - rear_z, "",
					_diag_label(jolt), _diag_label(composite), jolt.x / composite.x * 100.0,
					jolt.y / composite.y * 100.0, jolt.z / composite.z * 100.0]
			row["d_front"] = front - float(_hi_bare["front"])
			row["d_front_pred"] = d_front_pred
			row["yaw_ratio"] = jolt.y / composite.y
		print(lines)
	if not _current.has("hitch"):
		_current["hitch"] = []
	(_current["hitch"] as Array).append(row)


static func _diag(t: Basis) -> Vector3:
	return Vector3(t.x.x, t.y.y, t.z.z)


static func _diag_label(d: Vector3) -> String:
	return "%.0f / %.0f / %.0f" % [d.x, d.y, d.z]


## The draft pass (§ draft) on this body: each draft-relevant implement in turn.
func _start_plough() -> void:
	_reset_pass(Phase.PLOUGH)
	_pl_ids = []
	if not _car is TractorVehicle:
		print("=== %s: no three-point linkage, plough skipped ===" % _variant)
		_finish_vehicle()
		return
	for id: String in _car.call(&"attachment_ids"):
		if not ImplementCatalog.is_attached(id) or ImplementCatalog.is_towed(id):
			continue
		var node := (load(id) as PackedScene).instantiate() as ImplementBase
		var draft := node.draft_relevant()
		node.free()
		if draft and (_trailer == "" or id.get_file().get_basename() == _trailer):
			_pl_ids.append(id)
	print("=== %s (%s), draft on the field, dial 100 %% = %.2f kN ===" % [_variant,
			_drive_label(_car.spec), (_car as TractorVehicle).draft_max_force / 1000.0])
	_next_plough_implement()


## Respawn with the next implement on and lower it at rest, or finish the body.
func _next_plough_implement() -> void:
	if _pl_ids.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish_vehicle()
		return
	var id: String = _pl_ids.pop_front()
	if _course:
		_co_id = id
		_co_runs = COURSE_RUNS.duplicate()
		_next_course_run()
		return
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_car.call(&"set_attachment", id)
	var node := (load(id) as PackedScene).instantiate() as ImplementBase
	_pl_rating = node.draft_rating()
	_pl_shape = node.draft_shape()
	node.free()
	print("  %s: rated %.2f kN at %.0f km/h, D497 shape (%.0f, %.0f, %.1f) held above %.0f km/h;"
			% [id.get_file().get_basename(), _pl_rating / 1000.0, TractorTelemetry.DRAFT_S_REF_KMH,
			_pl_shape.x, _pl_shape.y, _pl_shape.z, _pl_shape.w]
			+ " g(0) %.2f" % TractorTelemetry.draft_speed01(0.0, _pl_shape))
	_pl_stage = Plough.LOWER
	_pl_speed = 0
	_pl_i = 0.0
	_t = 0.0
	_plough_drive(0.0, 100.0, true)


## A held speed's sums, zeroed (`_tick_plough`).
static func _plough_sums() -> Dictionary:
	var sums := {"gear": 0}
	for k: String in ["ticks", "v", "draft", "dial", "load", "slip", "axle", "front", "total", "rpm",
			"pedal"]:
		sums[k] = 0.0
	return sums


## The bridge stash for the pass: the linkage always at its bottom stop.
func _plough_drive(accel_pct: float, brake_pct: float, handbrake := false) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, handbrake, 1, false, 3, {"hitch_pos": 0.0})


func _tick_plough(delta: float) -> void:
	var v_long := _car.linear_velocity.dot(-_car.global_transform.basis.z)
	var tel := _car.telemetry as TractorTelemetry
	match _pl_stage:
		Plough.COURSE_SET:
			if _t < HITCH_WAIT_S:
				return
			_pl_stage = Plough.COURSE_RUN
			_t = 0.0
		Plough.COURSE_RUN:
			_co_set = minf(_co_set + COURSE_RAMP * delta, _co_run.x / 3.6)
			var err := _co_set - v_long
			_pl_i = clampf(_pl_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
			_course_drive(clampf(_pl_i + err * CORNER_PEDAL_KP, 0.0, 1.0) * 100.0, 0.0)
			var s := _co_strip.ahead(_car.global_position)
			if s > _co_row.y or _t > COURSE_TIMEOUT_S:
				_report_course_run(s)
				_next_course_run()
			elif s >= _co_row.x:
				_course_sample(s - _co_row.x, tel)
		Plough.LOWER:
			if _t < HITCH_WAIT_S:
				return
			_pl_stage = Plough.HOLD
			_t = 0.0
			_pl_sums = _plough_sums()
		Plough.HOLD:
			var err := PLOUGH_KMH[_pl_speed] / 3.6 - v_long
			_pl_i = clampf(_pl_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
			var pedal := clampf(_pl_i + err * CORNER_PEDAL_KP, 0.0, 1.0)
			_plough_drive(pedal * 100.0, 0.0)
			if _t < PLOUGH_SETTLE_S:
				return
			var axles := Vector2.ZERO
			for w in _car.wheels:
				if w.is_rear:
					axles.y += w.suspension_force
				else:
					axles.x += w.suspension_force
			_pl_sums["ticks"] += 1.0
			_pl_sums["v"] += v_long
			_pl_sums["draft"] += absf((_car as TractorVehicle).draft_applied)
			_pl_sums["dial"] += float(tel.draft_force)
			_pl_sums["load"] += float(tel.engine_load)
			_pl_sums["slip"] += float(tel.wheel_slip)
			_pl_sums["axle"] += tel.axle_load
			_pl_sums["front"] += axles.x
			_pl_sums["total"] += axles.x + axles.y
			_pl_sums["rpm"] += _car.drivetrain.rpm
			_pl_sums["pedal"] += pedal
			_pl_sums["gear"] = _car.drivetrain.gear_byte
			if _t < PLOUGH_SETTLE_S + PLOUGH_AVG_S:
				return
			_report_plough_hold()
			_pl_speed += 1
			_t = 0.0
			_pl_sums = _plough_sums()
			if _pl_speed >= PLOUGH_KMH.size():
				_pl_stage = Plough.STOP
		Plough.STOP:
			_plough_drive(0.0, 100.0)
			if absf(v_long) > 0.05:
				_t = 0.0
			if _t < PLOUGH_STOP_S:
				return
			_pl_stage = Plough.START
			_t = 0.0
			_pl_shifts = []
			_pl_gear = _car.drivetrain.gear_byte
			_pl_trace_t = 0.0
			_pl_moving_t = -1.0
			_pl_ticks = 0
			print("    standing start, floored, implement down (from %s):" % _gear_label(_pl_gear))
			if _trace:
				_pl_peak_slip = 0.0
				var peak := 0.0
				for pt in _car.spec.ground_drive.grip_curve:
					if pt.y > peak:
						peak = pt.y
						_pl_peak_slip = pt.x
				print(("      trace: a line every %d tick(s) to %.1f s; c O(pen) S(lipping) L(ocked), ramp"
						+ " the start-up ramp, clutch its commanded capacity, Tc at the crank (N·m); per rear"
						+ " wheel the slip ratio, < / > the grip curve's rising / falling side of its %.2f"
						+ " peak, and Fx / Fz") % [_trace_every, _trace_s, _pl_peak_slip])
		Plough.START:
			_plough_drive(100.0, 0.0)
			var gear: int = _car.drivetrain.gear_byte
			if gear != _pl_gear:
				var s := _shift_record(_pl_gear, gear)
				_pl_shifts.append(s)
				print("      %5.2f s  %s" % [_t, _shifts_label([s])])
				_pl_gear = gear
			if _pl_moving_t < 0.0 and absf(v_long) * 3.6 > 0.5:
				_pl_moving_t = _t
			_pl_ticks += 1
			if _trace and _t < _trace_s:
				if (_pl_ticks - 1) % _trace_every == 0:
					print(_plough_trace_line(v_long))
				_pl_trace_t = _t + PLOUGH_TRACE_S
			elif _t >= _pl_trace_t:
				_pl_trace_t += PLOUGH_TRACE_S
				print("      %5.2f s  %4.1f km/h %s %4.0f rpm, draft %3d %%, wheel_slip %2d %%, engine_load %3d %%"
						% [_t, v_long * 3.6, _gear_label(gear), _car.drivetrain.rpm, tel.draft_force,
						tel.wheel_slip, tel.engine_load])
			if _t < PLOUGH_START_S:
				return
			print("      moving (0.5 km/h) at %s; %s" % ["%.2f s" % _pl_moving_t if _pl_moving_t >= 0.0
					else "never", _shifts_label(_pl_shifts) if not _pl_shifts.is_empty() else "no shift"])
			var hunt := _hunting_gate(_pl_shifts)
			_gate_line("hunting", hunt[0], hunt[1])
			_next_plough_implement()


## One held speed's averages against D497 at the speed held (full depth, full soil).
func _report_plough_hold() -> void:
	var s := _pl_sums
	var n: float = maxf(s["ticks"], 1.0)
	var v: float = s["v"] / n
	var draft_n: float = s["draft"] / n
	var d497 := _pl_rating * TractorTelemetry.draft_speed01(v * 3.6, _pl_shape) \
			* clampf(absf(v) / TractorTelemetry.DRAFT_V_CRAWL, 0.0, 1.0)
	if not _current.has("plough"):
		_current["plough"] = []
	(_current["plough"] as Array).append({"implement": String(_car.call(&"current_attachment"))
			.get_file().get_basename(), "kmh": v * 3.6, "draft_n": draft_n, "d497_n": d497,
			"engine_load": s["load"] / n, "wheel_slip": s["slip"] / n, "axle_load": s["axle"] / n,
			"front_share": s["front"] / maxf(s["total"], 1e-6)})
	print(("    %4.1f km/h (held %4.1f): draft %.2f kN (D497 %.2f, %+.1f %%), dial %.0f %%; engine_load"
			+ " %.0f %%, wheel_slip %.1f %%, axle_load %.0f kg, front share %.1f %%; %s %.0f rpm,"
			+ " pedal %.2f") % [PLOUGH_KMH[_pl_speed], v * 3.6, draft_n / 1000.0, d497 / 1000.0,
			(draft_n / maxf(d497, 1.0) - 1.0) * 100.0, s["dial"] / n, s["load"] / n, s["slip"] / n,
			s["axle"] / n, s["front"] / maxf(s["total"], 1e-6) * 100.0, _gear_label(int(s["gear"])),
			s["rpm"] / n, s["pedal"] / n])


## The course's Row and light bands as distances ahead of its Spawn, laid on `strip` (§ draft).
func _load_course(strip: FieldStrip) -> void:
	var course := (load(COURSE_SCENE) as PackedScene).instantiate()
	var spawn := (course.get_node("Spawn") as Node3D).transform
	var row := course.get_node("Row") as ChallengeZone
	var row_z := Vector2(row.position.z - row.size.z * 0.5, row.position.z + row.size.z * 0.5)
	course.free()
	# The course runs along world z (its Spawn faces +z or -z); distance ahead of the Spawn.
	var dir := signf(-spawn.basis.z.z)
	var ahead := func(z: float) -> float: return (z - spawn.origin.z) * dir
	var a: float = ahead.call(row_z.x)
	var b: float = ahead.call(row_z.y)
	_co_row = Vector2(minf(a, b), maxf(a, b))
	strip.start_z = START_Z
	strip.field = 1.0 - FarmPlayground.LIGHT_SOIL_MIX
	var bands: Array[String] = []
	for band in FarmPlayground.LIGHT_SOIL_BANDS:
		a = ahead.call(band.x)
		b = ahead.call(band.y)
		strip.bands.append(Vector2(minf(a, b), maxf(a, b)))
		bands.append("%.0f-%.0f m" % [minf(a, b) - _co_row.x, maxf(a, b) - _co_row.x])
	print("course: tractor_plough's Row %.0f-%.0f m ahead of its Spawn; light bands %s into it, Field"
			% [_co_row.x, _co_row.y, ", ".join(bands)] + " %.2f (grip %.2f, drag %.3f), open diff"
			% [strip.field,
			lerpf(Surface.ref_grip(Surface.SAND), Surface.ref_grip(Surface.FIELD), strip.field),
			lerpf(Surface.drag(Surface.SAND), Surface.drag(Surface.FIELD), strip.field)])


## The bridge stash for a course run: the linkage held at the run's `hitch_pos`.
func _course_drive(accel_pct: float, brake_pct: float, handbrake := false) -> void:
	MeasureRig.drive(accel_pct, brake_pct, 0.0, handbrake, 1, false, 3, {"hitch_pos": _co_run.y})


## Respawn at the course's Spawn for the next COURSE_RUNS entry, or the next implement.
func _next_course_run() -> void:
	if _co_runs.is_empty():
		_next_plough_implement()
		return
	_co_run = _co_runs.pop_front()
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_car.call(&"set_attachment", _co_id)
	_co_ext = {}
	_co_shifts = []
	_co_gear = -1
	_co_set = 0.0
	_pl_i = 0.0
	_t = 0.0
	_pl_stage = Plough.COURSE_SET
	_course_drive(0.0, 100.0, true)


## One tick inside the Row, `d` m into it: each signal's extremes by the soil at the hitch point.
func _course_sample(d: float, tel: TractorTelemetry) -> void:
	var dt: Drivetrain = _car.drivetrain
	var hitch := _car.get_node((_car as TractorVehicle).hitch_path) as ThreePointHitch
	var soil := "band" if _co_strip.field_at(hitch.hitch_point()) < 1.0 else "full"
	var at := "%4.1f m, %s %4.0f rpm" % [d, _gear_label(dt.gear_byte), dt.rpm]
	for sig: String in ["engine_load", "draft_force"]:
		var v := float(tel.get(sig))
		var key := "%s, %s soil" % [sig, soil]
		if not _co_ext.has(key):
			_co_ext[key] = [v, at, v, at, 0.0, 0]
		var ext: Array = _co_ext[key]
		ext[4] += v
		ext[5] += 1
		if v < ext[0]:
			ext[0] = v
			ext[1] = at
		if v > ext[2]:
			ext[2] = v
			ext[3] = at
	if _co_gear >= 0 and dt.gear_byte != _co_gear:
		_co_shifts.append("%s>%s at %.1f m" % [_gear_label(_co_gear), _gear_label(dt.gear_byte), d])
	_co_gear = dt.gear_byte


func _report_course_run(s: float) -> void:
	print("  %s %s, %.0f km/h: %s" % [_co_id.get_file().get_basename(),
			"down" if _co_run.y <= 0.0 else "raised", _co_run.x,
			"through the Row in %.1f s" % _t if s > _co_row.y
			else "TIMEOUT %.1f m into the Row" % (s - _co_row.x)])
	var keys := _co_ext.keys()
	keys.sort()
	for key: String in keys:
		var ext: Array = _co_ext[key]
		print("    %-28s mean %3.0f %%, least %3.0f %% (%s), most %3.0f %% (%s)" % [key,
				ext[4] / maxi(ext[5], 1), ext[0], ext[1], ext[2], ext[3]])
	print("    shifts in the Row: %s" % (", ".join(_co_shifts) if not _co_shifts.is_empty()
			else "none"))


## One `trace` line of the floored start (§ draft): what the coupling passes, the draft against the
## rears' summed tyre force, and each rear tyre against its grip curve.
func _plough_trace_line(v_long: float) -> String:
	var dt: Drivetrain = _car.drivetrain
	var rears: Array[String] = []
	var fx := 0.0
	for w in _car.wheels:
		if w.is_rear:
			fx += w.force_long
			rears.append("%s %.3f %s %+.3f" % [_wheel_label(w), w.slip,
					">" if w.slip > _pl_peak_slip else "<",
					w.force_long / maxf(w.suspension_force, 1.0)])
	return ("      %6.3f %5.2f km/h %s %4.0f rpm %s ramp %.2f clutch %.2f Tc %5.0f fuel %.2f | draft"
			+ " %5.2f kN, rear Fx %5.2f kN | %s") % [_t, v_long * 3.6, _gear_label(dt.gear_byte),
			dt.rpm, "OSL"[dt.coupling_state], dt.ramp, dt.clutch, dt.coupling_torque,
			dt.applied_throttle, absf((_car as TractorVehicle).draft_applied) / 1000.0, fx / 1000.0,
			"  ".join(rears)]


## The kerb runs (§ kerb) on this body, after the disk's prediction per axle: a disk of radius `r`
## first meets a step `h` `sqrt(2 r h - h²)` ahead of its hub, its normal leaning back `asin(x / r)`;
## a cylinder meets an oblique edge `half_width tan θ` sooner, at its leading tread corner.
func _start_kerb() -> void:
	_kb_runs = []
	for h in KERB_HEIGHTS:
		_kb_runs.append({"h": h, "coast": false, "oblique": false})
		_kb_runs.append({"h": h, "coast": true, "oblique": false})
		_kb_runs.append({"h": h, "coast": false, "oblique": true})
	var gd := _car.spec.ground_drive
	print("=== %s (%s), kerb ===" % [_variant, _drive_label(_car.spec)])
	for rear in [false, true]:
		var r := gd.axle_radius(rear)
		var parts := PackedStringArray()
		for h in KERB_HEIGHTS:
			var x := sqrt(2.0 * r * h - h * h)
			parts.append("%.0f cm %.2f m, %.0f deg" % [h * 100.0, x, rad_to_deg(asin(x / r))])
		print("  predicted %-5s r %.2f: disk %s; cylinder +%.2f m at %.0f deg" % [
				"rear" if rear else "front", r, ", ".join(parts),
				gd.axle_half_width(rear) * tan(deg_to_rad(KERB_OBLIQUE_DEG)), KERB_OBLIQUE_DEG])
	_next_kerb_run()


func _next_kerb_run() -> void:
	if _kb_box != null:
		remove_child(_kb_box)
		_kb_box.queue_free()
		_kb_box = null
	if _kb_runs.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish_vehicle()
		return
	_kb_run = _kb_runs.pop_front()
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), START_Z))
	_car.respawn()
	_reset_pass(Phase.KERB)
	_kb_i = 0.0
	_kb_t = 0.0
	_kb_edges = []
	_kb_overlaps = RayWheel.start_overlaps
	MeasureRig.drive(100.0 if _kb_run["coast"] else 0.0, 0.0)


func _tick_kerb(delta: float) -> void:
	var v_long := _car.linear_velocity.dot(-_car.global_transform.basis.z)
	var coast: bool = _kb_run["coast"]
	if _kb_box == null:
		if coast:
			if v_long >= KERB_COAST or _t >= _seconds:
				_lay_kerb(KERB_LEAD_COAST)
				MeasureRig.drive(0.0, 0.0)
		else:
			_kerb_crawl(v_long, delta)
			if _t >= KERB_SETTLE_S:
				_lay_kerb(KERB_LEAD_CRAWL)
		return
	if not coast:
		_kerb_crawl(v_long, delta)
	_kb_t += delta
	var v := _car.linear_velocity.dot(_kb_heading)
	var ay := (_car.linear_velocity.y - _kb_prev_vy) / delta
	_kb_prev_vy = _car.linear_velocity.y
	for e in 2:
		_kerb_edge_tick(e, v, ay)
	var progress := (_car.global_position - _kb_origin).dot(_kb_heading)
	if progress > _kb_best + KERB_STUCK_PROGRESS:
		_kb_best = progress
		_kb_best_t = _kb_t
	var verdict := ""
	if float(_kb_edges[1]["t_clear"]) >= 0.0:
		verdict = "over"
	elif _kb_t - _kb_best_t > KERB_STUCK_S:
		verdict = "STUCK"
	elif _kb_t > KERB_TIMEOUT_S:
		verdict = "TIMEOUT"
	if verdict != "":
		_report_kerb_run(verdict)
		_next_kerb_run()


## The crawl's speed hold: the circle's PI pedal at KERB_CRAWL, and the brake past it.
func _kerb_crawl(v_long: float, delta: float) -> void:
	var err := KERB_CRAWL - v_long
	_kb_i = clampf(_kb_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	MeasureRig.drive(clampf(_kb_i + err * CORNER_PEDAL_KP, 0.0, 1.0) * 100.0,
			clampf(-err * KERB_BRAKE_GAIN, 0.0, 1.0) * 100.0)


## The plateau, its near edge `lead` ahead of the foremost hub along the heading, square to it or
## KERB_OBLIQUE_DEG off; its top at the run's height.
func _lay_kerb(lead: float) -> void:
	var h: float = _kb_run["h"]
	var xf := _car.global_transform
	_kb_heading = Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
	var oblique := deg_to_rad(KERB_OBLIQUE_DEG) if _kb_run["oblique"] else 0.0
	_kb_n = Basis(Vector3.UP, oblique) * -_kb_heading
	_kb_cos = _kb_heading.dot(-_kb_n)
	var front := -INF
	for w in _car.wheels:
		front = maxf(front, (xf * w.anchor).dot(_kb_heading))
	var near := _car.global_position + _kb_heading * (front - _car.global_position.dot(_kb_heading)
			+ lead)
	near.y = 0.0
	var length := _wheelbase() + KERB_TOP
	_kb_edge_at = [near, near - _kb_n * length]
	_kb_box = MeasureRig.add_box(self, "Kerb", Vector3(KERB_WIDTH, h, length), Transform3D(
			Basis(Vector3.UP, atan2(_kb_n.x, _kb_n.z)),
			near - _kb_n * (length * 0.5) + Vector3.UP * (h * 0.5)))
	_kb_edges = [_kerb_edge(), _kerb_edge()]
	_kb_prev_vy = _car.linear_velocity.y
	_kb_origin = _car.global_position
	_kb_best = 0.0
	_kb_best_t = 0.0


## One edge's figures over a kerb run; the arrays are per wheel.
func _kerb_edge() -> Dictionary:
	var zero := []
	zero.resize(_car.wheels.size())
	zero.fill(0.0)
	var unset := zero.duplicate()
	unset.fill(NAN)
	return {"prev": zero.duplicate(), "x": unset, "lean": unset.duplicate(),
			"lean_peak": zero.duplicate(), "jump": zero.duplicate(), "peak": zero.duplicate(),
			"t_first": -1.0, "v_first": NAN, "v_min": INF, "v_clear": NAN,
			"t_clear": -1.0, "a_peak": 0.0}


## Edge `e` (0 the step up, 1 the step down) this tick, at road speed `v` and COM vertical
## acceleration `ay`.
func _kerb_edge_tick(e: int, v: float, ay: float) -> void:
	var edge := _kb_edges[e]
	var up_edge := e == 0
	var half_step: float = _kb_run["h"] * 0.5
	var xf := _car.global_transform
	var any_in := false
	var all_clear := true
	for i in _car.wheels.size():
		var w: RayWheel = _car.wheels[i]
		var d := (xf * w.anchor - _kb_edge_at[e]).dot(_kb_n) / _kb_cos
		var c := w.compression
		if d > KERB_LATCH:
			edge["prev"][i] = c
			all_clear = false
			continue
		any_in = true
		var change: float = c - float(edge["prev"][i])
		edge["prev"][i] = c
		if d <= -KERB_CLEAR:
			continue
		all_clear = false
		var lean := rad_to_deg(w.contact_normal.angle_to(Vector3.UP)) if w.in_contact else 0.0
		edge["lean_peak"][i] = maxf(float(edge["lean_peak"][i]), lean)
		edge["peak"][i] = maxf(float(edge["peak"][i]), w.suspension_force)
		edge["jump"][i] = maxf(float(edge["jump"][i]), change if up_edge else -change)
		var landed := w.in_contact and (w.contact_point.y > half_step if up_edge
				else w.contact_point.y < half_step)
		if is_nan(float(edge["x"][i])) and landed:
			edge["x"][i] = d
			edge["lean"][i] = lean
			if float(edge["t_first"]) < 0.0:
				edge["t_first"] = _kb_t
				edge["v_first"] = v
	if any_in and float(edge["t_clear"]) < 0.0:
		edge["v_min"] = minf(float(edge["v_min"]), v)
		edge["a_peak"] = maxf(float(edge["a_peak"]), absf(ay))
		if all_clear:
			edge["t_clear"] = _kb_t
			edge["v_clear"] = v


func _report_kerb_run(verdict: String) -> void:
	var h: float = _kb_run["h"]
	var how := "coast 30 km/h" if _kb_run["coast"] else "crawl"
	if _kb_run["oblique"]:
		how += " at %.0f deg" % KERB_OBLIQUE_DEG
	var cap := _car.spec.ground_drive.max_suspension_force
	var overlaps := RayWheel.start_overlaps - _kb_overlaps
	print("  %.0f cm %-18s : %s after %.1f s%s" % [h * 100.0, how, verdict, _kb_t,
			", %d cast start overlaps" % overlaps if overlaps > 0 else ""])
	for e in 2:
		var edge := _kb_edges[e]
		var edge_name := "up" if e == 0 else "down"
		if float(edge["t_first"]) < 0.0:
			print("    %-4s: no wheel on the new level by %.1f m past (airborne)" % [edge_name, KERB_CLEAR])
			continue
		var t_clear: float = edge["t_clear"]
		var v_clear: float = edge["v_clear"]
		print("    %-4s: %s, v %.2f -> min %.2f -> %s m/s, peak |a_y| %.2f g" % [edge_name,
				"%.2f s" % (t_clear - float(edge["t_first"])) if t_clear >= 0.0 else "not cleared",
				edge["v_first"], edge["v_min"], "-" if is_nan(v_clear) else "%.2f" % v_clear,
				float(edge["a_peak"]) / 9.81])
		for i in _car.wheels.size():
			var x: float = edge["x"][i]
			var peak: float = edge["peak"][i]
			print(("      %-4s on the new level %s ahead, lean %s (peak %.0f deg), largest tick %.0f mm,"
					+ " peak %.1f of %.1f kN%s") % [_wheel_label(_car.wheels[i]),
					"-" if is_nan(x) else "%+.2f m" % x,
					"-" if is_nan(x) else "%.0f deg" % float(edge["lean"][i]),
					float(edge["lean_peak"][i]), float(edge["jump"][i]) * 1000.0, peak / 1000.0,
					cap / 1000.0,
					" (clamp bound)" if peak >= cap - 1.0 else ""])
	_current["kerb_%.0f_%s" % [h * 100.0, how.replace(" ", "_")]] = verdict


## Wheelbase (m) off the axle stations, foremost front to rearmost rear. A tandem's effective
## wheelbase is shorter, so a semi's ratio to neutral reads low: compare it only with itself.
func _wheelbase() -> float:
	var ax := BrakeSizing.axle_geometry(_car.spec)
	return maxf(float(ax["rear_z"]) - float(ax["front_z"]), 1e-3)


## Each axle group's left-minus-right load (N; x the front, y the rear axles), off the springs'
## `suspension_force`: the whole load each corner carries, bar and links included.
func _axle_transfer() -> Vector2:
	var d := Vector2.ZERO
	for w in _car.wheels:
		var f: float = w.suspension_force * (1.0 if w.anchor.x < 0.0 else -1.0)
		if w.is_rear:
			d.y += f
		else:
			d.x += f
	return d


## The front axles' share of a lateral load transfer `change` (`_axle_transfer` now less before):
## the roll-stiffness split's reading (LLTD). NAN when the change is too small to share out.
static func _lltd(change: Vector2) -> float:
	var total := change.x + change.y
	return change.x / total if absf(total) > 1.0 else NAN


## "58 %", or "-" for NAN.
static func _pct(share: float) -> String:
	return "-" if is_nan(share) else "%.0f %%" % (share * 100.0)


## The yaw dynamic index k² / (a·b) the body runs with, off the live tensor: the moment about the
## body's up axis through the world-space inverse tensor (`TowHost`'s axis read; `inverse_inertia`
## is in the principal frame), over `m a b` from the axle stations and the COM.
func _yaw_index() -> Dictionary:
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	var up := _car.global_transform.basis.y
	var iyy := 1.0 / up.dot(state.inverse_inertia_tensor * up)
	var ax := BrakeSizing.axle_geometry(_car.spec)
	var com_z := _car.spec.center_of_mass.z
	var mab := _car.mass * (com_z - float(ax["front_z"])) * (float(ax["rear_z"]) - com_z)
	return {"index": iyy / mab, "iyy": iyy, "mab": mab}


func _cruise_probe() -> bool:
	return _cruise or _kickdown or _pulse


## The part-pedal probes (§ part-pedal probes) on this body: its family's CRUISE_SETS row (a van
## rides the car row), less the speeds its governor would cap.
func _start_cruise() -> void:
	var family := String(Catalog.VARIANTS[_variant]["family"])
	var row: Dictionary = CRUISE_SETS.get(family, CRUISE_SETS["car"])
	var limit: float = _car.spec.speed_limit_kmh
	_cr_speeds = []
	_cr_airs = []
	for kmh: float in [XWIND_KMH.get(family, XWIND_KMH["car"])] if _xwind or _headtail else row["kmh"]:
		if limit <= 0.0 or kmh < limit - Drivetrain.GOVERNOR_BAND * 3.6:
			for air: Air in [Air.STILL, Air.HEAD, Air.TAIL] if _headtail else [Air.STILL]:
				_cr_speeds.append(kmh)
				_cr_airs.append(air)
	_cr_ramp = row["ramp"]
	_reset_pass(Phase.CRUISE)
	InputRouter.set_manual_gearbox(false)
	_current["cruise"] = []
	var speeds := PackedStringArray()
	for kmh in _cr_speeds:
		speeds.append("%.0f" % kmh)
	var label := "=== %s, part pedal at %s km/h, setpoint ramped at %.1f m/s²" % [_variant,
			" / ".join(speeds), _cr_ramp]
	if _current.has("trailer"):
		label += ", trailer=%s" % _current["trailer"]
	print(label + " ===")
	_next_cruise_speed()


func _next_cruise_speed() -> void:
	if _cr_speeds.is_empty():
		MeasureRig.drive(100.0, 0.0)
		_finish_vehicle()
		return
	# Each speed from a fresh standstill: its line never depends on what the last speed left in
	# the box, and the strip holds every window.
	_car.respawn()
	_cr_i = 0.0
	_cr_target = _cr_speeds.pop_front() / 3.6
	_cr_air = _cr_airs.pop_front()
	_cr_settled = false
	_cr_actions = []
	if _cr_air != Air.STILL:
		_begin_cruise_window(Cruise.APPROACH)  # the settle in that air is the whole job
		return
	if _kickdown:
		_cr_actions.append(Cruise.KICK)
	if _pulse:
		if _kickdown:
			_cr_actions.append(Cruise.APPROACH)  # re-settle after the kick
		_cr_actions.append(Cruise.PULSE)
	if _xwind:
		if not _cr_actions.is_empty():
			_cr_actions.append(Cruise.APPROACH)
		_cr_actions.append(Cruise.XWIND)
	_wind = _wind_base
	_begin_cruise_window(Cruise.APPROACH)


func _begin_cruise_window(stage: Cruise) -> void:
	_cr_stage = stage
	_cr_t0 = _t
	_cr_shifts = []
	_cr_limiter = 0
	_cr_gear = _car.drivetrain.gear_byte
	_cr_g0 = _cr_gear
	_cr_v0 = _car.telemetry.speed
	# A pulse starts off a settle, so it holds the target; an approach ramps from where it is.
	_cr_set = _cr_target if stage == Cruise.PULSE else _cr_v0
	_cr_pedal_peak = 0.0
	_cr_duty_sum = 0.0
	_cr_periods = 0
	_cr_band = Vector2(INF, -INF)
	_reset_cruise_hold()
	var fwd_flat := -_car.global_basis.z
	fwd_flat = Vector3(fwd_flat.x, 0.0, fwd_flat.z).normalized()
	_wind = _wind_base
	if _cr_air == Air.HEAD:
		_wind = _wind_base - fwd_flat * WIND_HEADTAIL
	elif _cr_air == Air.TAIL:
		_wind = _wind_base + fwd_flat * WIND_HEADTAIL
	if stage == Cruise.KICK:
		_drive_probe(1.0)
	elif stage == Cruise.XWIND:
		_xw_origin = _car.global_position
		var fwd := -_car.global_basis.z
		_xw_right = Vector3(-fwd.z, 0.0, fwd.x).normalized()
		_xw_heading = atan2(fwd.x, -fwd.z)
		_xw_yaw_peak = 0.0
		_xw_pedal = _cr_pedal
		_xw_marks = XWIND_MARKS.duplicate()
		# From the right, so it blows toward the body's left, on top of the flag's wind.
		_wind = _wind_base - _xw_right * _xwind_speed
		_drive_probe(_xw_pedal)


func _reset_cruise_hold() -> void:
	_cr_hold_t = 0.0
	_cr_sums = Vector3.ZERO
	_cr_ticks = 0


## The probes drive automatic D, with `notc` riding the stash as the accel pass's does.
func _drive_probe(pedal: float) -> void:
	MeasureRig.drive(pedal * 100.0, 0.0, 0.0, false, 1, _notc)


func _tick_cruise(delta: float) -> void:
	var dt: Drivetrain = _car.drivetrain
	var v: float = _car.telemetry.speed
	var gear := dt.gear_byte
	var shifted := gear != _cr_gear
	if Drivetrain.is_shift(_cr_gear, gear):
		_cr_shifts.append(_shift_record(_cr_gear, gear))
	_cr_gear = gear
	if dt.on_limiter:
		_cr_limiter += 1
	var window := _t - _cr_t0
	if _cr_stage == Cruise.APPROACH:
		_tick_cruise_hold(delta, v, shifted, window)
	elif _cr_stage == Cruise.KICK:
		if v >= _cr_v0 + KICK_GAIN_KMH / 3.6 or window >= _seconds:
			_report_kick(v, window)
	elif _cr_stage == Cruise.XWIND:
		_xw_yaw_peak = maxf(_xw_yaw_peak, absf(_car.angular_velocity.y))
		if not _xw_marks.is_empty() and window >= _xw_marks[0]:
			var mark: float = _xw_marks.pop_front()
			print("  %-13s : %s" % ["  at %.0f s" % mark, _xwind_state()])
			_current["xwind_%.0fs" % mark] = _xwind_figures()
		if window >= XWIND_S:
			_report_xwind(v)
	else:
		var pi := _cruise_pi(delta, v)
		var into := fmod(window, _pulse_period)
		# Latched when the period's index moves: a test on the phase can miss a boundary in float.
		var period := floori(window / _pulse_period)
		if period != _cr_periods - 1:
			_cr_duty = pi if is_nan(_pulse_duty) else _pulse_duty
			_cr_duty_sum += _cr_duty
			_cr_periods += 1
		_drive_probe(1.0 if into < _pulse_period * _cr_duty else 0.0)
		_cr_band = Vector2(minf(_cr_band.x, v), maxf(_cr_band.y, v))
		if window >= PULSE_S:
			_report_pulse()


## The PI pedal on the ramped setpoint, and the settle test on the tick that just ran.
func _tick_cruise_hold(delta: float, v: float, shifted: bool, window: float) -> void:
	var dt: Drivetrain = _car.drivetrain
	if _cr_set == _cr_target and absf(v - _cr_target) <= CRUISE_TOL and not shifted:
		_cr_hold_t += delta
		_cr_sums += Vector3(_cr_pedal, dt.rpm, VehicleTelemetry.engine_load_pct(dt.rpm,
				dt.applied_throttle, _car.spec, false, 0.0))
		_cr_ticks += 1
	else:
		_reset_cruise_hold()
	if _cr_hold_t >= CRUISE_SETTLE_S:
		_report_cruise_hold(window)
		return
	if window >= _seconds:
		print("  %-13s : %.0f km/h not held in %.0f s (%.1f km/h now, pedal %.2f, %s)" % ["cruise",
				_cr_target * 3.6, _seconds, v * 3.6, _cr_pedal, _gear_label(dt.gear_byte)])
		if not _cr_settled:
			(_current["cruise"] as Array).append({"kmh": _cr_target * 3.6, "held": false,
					"now_kmh": v * 3.6})
		_cruise_gates()
		_next_cruise_speed()
		return
	_cr_set = move_toward(_cr_set, _cr_target, _cr_ramp * delta)
	_cr_pedal = _cruise_pi(delta, v)
	_cr_pedal_peak = maxf(_cr_pedal_peak, _cr_pedal)
	_drive_probe(_cr_pedal)


## One tick of the PI pedal on the setpoint (CORNER_PEDAL_KP / _KI). The integral is held through
## a shift cut, as TcPedal holds it: the drive drops there, and it would wind up.
func _cruise_pi(delta: float, v: float) -> float:
	var err := _cr_set - v
	if not _car.drivetrain.shift_cut_active():
		_cr_i = clampf(_cr_i + err * CORNER_PEDAL_KI * delta, 0.0, 1.0)
	return clampf(_cr_i + err * CORNER_PEDAL_KP, 0.0, 1.0)


func _report_cruise_hold(window: float) -> void:
	var m := _cr_sums / maxf(1.0, _cr_ticks)
	var label := "cruise" if not _cr_settled else "  re-settled"
	if _cr_air == Air.HEAD:
		label = "into %.0f m/s" % WIND_HEADTAIL
	elif _cr_air == Air.TAIL:
		label = "with %.0f m/s" % WIND_HEADTAIL
	print(("  %-13s : %.0f km/h in %s at %.0f rpm, pedal %.2f, engine_load %.0f %%; settled after"
			+ " %.1f s,") % [label, _cr_target * 3.6, _gear_label(_car.drivetrain.gear_byte), m.y,
			m.x, m.z, window]
			+ " approach pedal peak %.2f, %d shift(s)" % [_cr_pedal_peak, _cr_shifts.size()])
	if m.x >= LAUNCH_FLOORED:
		print("  %-13s : floored: the body's top, not a cruise" % "")
	if _cr_air != Air.STILL:
		_current["wind_head" if _cr_air == Air.HEAD else "wind_tail"] = {"pedal": m.x,
				"load": m.z}
	elif not _cr_settled:
		# Read here, not at the start: a spawn trailer couples after a countdown.
		_current["towed_kg"] = _combination_mass() - _car.spec.mass
		(_current["cruise"] as Array).append({"kmh": _cr_target * 3.6, "held": true,
				"gear": _car.drivetrain.gear_byte, "rpm": m.y, "pedal": m.x, "load": m.z,
				"floored": m.x >= LAUNCH_FLOORED})
	_cr_settled = true
	_cruise_gates()
	_next_cruise_window()


## Kickdown from the settle: the first downshift, the gears dropped below the cruise gear, the time
## to KICK_GAIN_KMH more.
func _report_kick(v: float, window: float) -> void:
	var first_down := -1.0
	var low: int = _cr_g0
	for sh: Dictionary in _cr_shifts:
		if int(sh["to"]) < int(sh["from"]) and first_down < 0.0:
			first_down = float(sh["t"]) - _cr_t0
		low = mini(low, int(sh["to"]))
	var tick := 1.0 / Engine.physics_ticks_per_second
	var down := "no downshift"
	if first_down >= 0.0:
		down = "first downshift after %d ticks (%.2f s)" % [roundi(first_down / tick), first_down]
	var gain := "+%.0f km/h in %.2f s" % [KICK_GAIN_KMH, window]
	if v < _cr_v0 + KICK_GAIN_KMH / 3.6:
		gain = "+%.0f km/h not reached in %.0f s (%.1f km/h)" % [KICK_GAIN_KMH, _seconds,
				v * 3.6]
	print("  %-13s : from %.1f km/h in %s, pedal stepped to 1: %s, %d gear(s) down to %s; %s" % [
			"kickdown", _cr_v0 * 3.6, _gear_label(_cr_g0), down, _cr_g0 - low, _gear_label(low), gain])
	_cruise_gates()
	_next_cruise_window()


func _report_pulse() -> void:
	var gears: Array[int] = [_cr_g0]
	for sh: Dictionary in _cr_shifts:
		gears.append(int(sh["to"]))
	print(("  %-13s : %.0f s on/off at %.2f s period, mean duty %.2f, from %.1f km/h (%.1f-%.1f):"
			+ " %d shift(s), %.1f a minute, %s to %s") % ["pulse", PULSE_S, _pulse_period,
			_cr_duty_sum / maxf(1.0, _cr_periods),
			_cr_v0 * 3.6, _cr_band.x * 3.6, _cr_band.y * 3.6, _cr_shifts.size(),
			_cr_shifts.size() * 60.0 / PULSE_S,
			_gear_label(int(gears.min())), _gear_label(int(gears.max()))])
	_cruise_gates()
	_next_cruise_window()


## The crosswind window's line: where the body went with the wheel held straight.
func _report_xwind(v: float) -> void:
	print(("  %-13s : %.0f m/s from the right for %.0f s at %.0f km/h, pedal %.2f, steer 0: %s,"
			+ " %.1f km/h at the end") % ["crosswind", _xwind_speed, XWIND_S, _cr_target * 3.6,
			_xw_pedal, _xwind_state(), v * 3.6])
	_current["xwind_%.0fs" % XWIND_S] = _xwind_figures()
	_wind = _wind_base
	_cruise_gates()
	_next_cruise_window()


## Drift (m, + = toward the wind), heading turned (deg, + = into it), the yaw-rate peak so far, roll.
func _xwind_state() -> String:
	var f := _xwind_figures()
	return "drift %+.2f m, heading %+.2f deg, yaw rate peak %.2f deg/s, roll %+.2f deg" % [
			f["drift"], f["heading"], f["yaw_peak"], f["roll"]]


func _xwind_figures() -> Dictionary:
	var fwd := -_car.global_basis.z
	return {"drift": (_car.global_position - _xw_origin).dot(_xw_right),
			"heading": rad_to_deg(wrapf(atan2(fwd.x, -fwd.z) - _xw_heading, -PI, PI)),
			"yaw_peak": rad_to_deg(_xw_yaw_peak), "roll": VehicleMath.roll_deg(_car.global_basis)}


## This speed's next window, or the next speed once its windows are done.
func _next_cruise_window() -> void:
	if _cr_actions.is_empty():
		_next_cruise_speed()
	else:
		_begin_cruise_window(_cr_actions.pop_front())


## The window's shifts, then its gates on one line: hunting, landing, the limiter.
func _cruise_gates() -> void:
	if not _cr_shifts.is_empty():
		print("  %-13s : %s" % ["  each shift", _shifts_label(_cr_shifts)])
	var gates: Array[String] = []
	for g: Array in [["hunting"] + _hunting_gate(_cr_shifts),
			["landing"] + _landing_gate(_cr_shifts, _car.spec),
			["limiter", _cr_limiter == 0, "%d ticks" % _cr_limiter]]:
		gates.append("%s %s (%s)" % [g[0], "PASS" if g[1] else "FAIL", g[2]])
	print("  %-13s : %s" % ["  gates", "; ".join(gates)])


func _finish_vehicle() -> void:
	var overlaps := RayWheel.start_overlaps - _body_overlaps
	if overlaps > 0:
		# A wheel's cast started inside something: read as full bump. On the flat strip that is an
		# attachment (or its own trailer) under a hub, never the ground.
		print("  contact: %d cast start overlaps, a hub inside something" % overlaps)
	_current["start_overlaps"] = overlaps
	print("")
	_sweep.append(_current)
	_next_vehicle()


func _contact_label(pass_name: String) -> String:
	if _contact_peak == 0:
		return "none during %s (wheels are shape queries, so any contact is the chassis)" % pass_name
	return "x%d during %s, t=%.2f..%.2f s — a real problem, not a spawn drop" \
			% [_contact_peak, pass_name, _contact_t0, _contact_t1]


func _drive_label(spec: VehicleSpec) -> String:
	var gd := spec.ground_drive
	var layout := "AWD"
	if not (gd.driven_front and gd.driven_rear):
		layout = "FWD" if gd.driven_front else "RWD"
	return layout + _diff_label(gd)


## The declared differentials that are not open (`GroundDriveSpec` § Driveline), e.g.
## ", centre 3.0:1, rear LSD 2.5:1"; empty when every diff is open.
static func _diff_label(gd: GroundDriveSpec) -> String:
	var label := ""
	if gd.centre_diff_rigid:
		label += ", centre rigid"
	elif gd.centre_diff_bias > 1.0:
		label += ", centre %.1f:1" % gd.centre_diff_bias
	if gd.diff_bias_front > 1.0:
		label += ", front LSD %.1f:1" % gd.diff_bias_front
	if gd.diff_bias_rear > 1.0:
		label += ", rear LSD %.1f:1" % gd.diff_bias_rear
	return label


## The `braking` region: one row per body, a cell per pedal (mean g, distance), noting where any
## wheel's ABS acted or any wheel skidded (slip past BRAKE_LOCK_SLIP).
func _braking_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=braking`; per body `-- <variant>"
			+ " %.0f brake`): stops from 100 km/h, or 90 %% of the top where that is lower (`from`).")
			% [DocRegion.measured(), _seconds])
	lines.append_array(["", "| Body | 30 % pedal | 60 % | 100 % |", "| --- | --- | --- | --- |"])
	for e in _sweep:
		var rows: Array = e.get("braking", [])
		if rows.is_empty():
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		if float(rows[0]["v0_kmh"]) < BRAKE_SPEED * 3.6 - 1.0:
			label += " (from %.0f)" % float(rows[0]["v0_kmh"])
		if not bool(e["abs"]):
			label += " (no ABS)"
		var cells: Array[String] = []
		for b: Dictionary in rows:
			var cell := "%.2f g, %.1f m" % [b["g"], b["dist"]]
			if float(b["abs_t"]) > 0.0:
				cell += ", ABS"
			if float(b["skid_t"]) >= 0.05:
				cell += ", skids %.2f s" % float(b["skid_t"])
			cells.append(cell)
		lines.append("| %s | %s |" % [label, " | ".join(cells)])
	return lines


## The `cornering` region: every wheel-driven variant on the skid pad.
func _cornering_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=cornering`; per body `-- <variant>"
			+ " %.0f track corner`): peak lateral g, the axle that saturates first (by its share of"
			+ " the friction ellipse), roll at the peak, most wheels lifted at once.")
			% [DocRegion.measured(), _seconds])
	lines.append_array(["", "| Body | Peak | Saturates first | Roll | Lifted |",
			"| --- | --- | --- | --- | --- |"])
	for e in _sweep:
		var c: Dictionary = e.get("cornering", {})
		if c.is_empty():
			continue
		if c.get("skipped", false):
			lines.append("| `%s` | never reached %.0f km/h | | | |" % [e["variant"], c["speed_kmh"]])
			continue
		lines.append("| `%s` | %.2f g%s | %s | %.1f deg | %d%s |" % [e["variant"], c["peak_g"],
				" (slid)" if c["slid"] else "", c["axle"], c["roll_deg"], c["wheels_lifted"],
				", overturned" if c["overturned"] else ""])
	return lines


## The `cruise` region: DOC_CRUISE's bodies held on the flat by the PI pedal at each speed of their
## family's CRUISE_SETS row, from a standstill: the gear and rpm the shift policy settled in, the
## pedal and `engine_load` averaged over the hold.
func _cruise_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=cruise`; per body `-- <variant> %.0f"
			+ " cruise`): each speed held on the flat strip from a standstill, the setpoint ramped at"
			+ " %.1f m/s² (%.1f on the trucks and the tractor), settled after %.0f s within %.1f m/s with"
			+ " no shift; a speed within the governor's band is dropped. Each cell: the gear, the crank's"
			+ " rpm, the pedal and `engine_load` over the hold.") % [DocRegion.measured(), _seconds,
			CRUISE_SETS["car"]["ramp"], CRUISE_SETS["truck"]["ramp"], CRUISE_SETTLE_S, CRUISE_TOL])
	lines.append_array(["", "| Body | Held at (km/h: gear, rpm, pedal, load) |", "| --- | --- |"])
	for e in _sweep:
		if not e.has("cruise"):
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		var cells: Array[String] = []
		for c: Dictionary in e["cruise"]:
			if not bool(c["held"]):
				cells.append("%.0f: not held (%.1f)" % [c["kmh"], c["now_kmh"]])
			else:
				cells.append("%.0f: %s %.0f rpm, %.2f, %.0f %%%s" % [c["kmh"], _gear_label(c["gear"]),
						c["rpm"], c["pedal"], c["load"], " (floored: its top)" if c["floored"] else ""])
		lines.append("| %s | %s |" % [label, "; ".join(cells)])
	return lines


## The `wind` region: DOC_WIND's bodies at their XWIND_KMH speed, the cruise hold in still air,
## into and with WIND_HEADTAIL, then the crosswind window's figures at each mark.
func _wind_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=wind`; per body `-- <variant> %.0f"
			+ " cruise headtail xwind`): one speed held from a standstill as `doc=cruise` holds it, and"
			+ " again from a standstill into, then with, a steady %.0f m/s along the heading (STRONG's"
			+ " steady wind): the pedal and `engine_load` over each hold, against drag's"
			+ " `0.5 rho CdA ((v ± w)^2 - v^2)`."
			+ " Then, from the still-air settle, %.0f m/s (STRONG's steady wind plus its gust ceiling)"
			+ " from the right, the pedal held and the wheel straight: drift (+ toward the wind), the"
			+ " heading turned (+ into it), the yaw-rate peak and the roll.") % [DocRegion.measured(),
			_seconds, WIND_HEADTAIL, XWIND_SPEED])
	var marks: Array[String] = []
	for t: float in XWIND_MARKS + [XWIND_S]:
		marks.append("at %.0f s" % t)
	lines.append_array(["", "| Body | km/h | Still (pedal, load) | Into the wind | With it | Crosswind "
			+ " | ".join(marks) + " |", "| --- | --- | --- | --- | --- |" + " --- |".repeat(marks.size())])
	for e in _sweep:
		if not e.has("cruise") or (e["cruise"] as Array).is_empty():
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		var c: Dictionary = e["cruise"][0]
		var cells: Array[String] = [label, "%.0f" % c["kmh"]]
		cells.append("%.2f, %.0f %%" % [c["pedal"], c["load"]] if bool(c["held"]) else "not held")
		for key: String in ["wind_head", "wind_tail"]:
			var h: Dictionary = e.get(key, {})
			cells.append("not held" if h.is_empty() else "%.2f, %.0f %%" % [h["pedal"], h["load"]])
		for t: float in XWIND_MARKS + [XWIND_S]:
			var x: Dictionary = e.get("xwind_%.0fs" % t, {})
			cells.append("-" if x.is_empty() else "%+.2f m, %+.1f deg, %.1f deg/s, roll %+.1f deg"
					% [x["drift"], x["heading"], x["yaw_peak"], x["roll"]])
		lines.append("| %s |" % " | ".join(cells))
	return lines


## The `steer` region: DOC_STEER's bodies, a row per entry speed, a cell per lock (held / lifted).
func _steer_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=steer`; per body `-- <variant> %.0f"
			+ " step`): from each speed settled on the PI pedal, the bridge steer stepped in one tick"
			+ " and held %.0f s, the pedal held / lifted on the step. Each cell: the steady yaw rate"
			+ " (last %.1f s) over neutral steer `v * delta / L` (under 1 understeers), the rise to"
			+ " %.0f %% of it, the overshoot past it, `(n up)` with wheels lifted; `spun` past %.0f deg"
			+ " of body slip, `rolled` past %.0f deg off vertical. The body's yaw dynamic index"
			+ " k² / (a·b) beside its name. `K` is the understeer gradient off the smallest held step"
			+ " (`(delta - L r / v)` per g of side force; linear only at low g, so read it with its g),"
			+ " beside the front axles' share of the lateral load transfer (LLTD).")
			% [DocRegion.measured(), _seconds, STEP_HOLD_S, STEP_STEADY_S, STEP_RISE * 100.0,
			STEP_SPIN_DEG, STEP_ROLL_DEG])
	var head := "| Body | km/h | K at %.0f %% held, LLTD |" % STEP_LOCKS[0]
	var rule := "| --- | --- | --- |"
	for lock in STEP_LOCKS:
		head += " %.0f %% lock, held / lifted |" % lock
		rule += " --- |"
	lines.append_array(["", head, rule])
	for e in _sweep:
		if not e.has("step"):
			continue
		var label := "`%s` (%.2f)" % [e["variant"], (e.get("yaw_index", {}) as Dictionary).get("index", 0.0)]
		var rows := {}  # kmh -> {lock -> [held cell, lifted cell]}
		for r: Dictionary in e["step"]:
			var by_lock: Dictionary = rows.get_or_add(r["kmh"], {})
			var pair: Array = by_lock.get_or_add(r["lock"], ["-", "-"])
			pair[1 if r["lifted"] else 0] = _step_cell(r)
		for kmh in rows:
			var cells: Array[String] = [_k_cell(e["step"], kmh)]
			for lock in STEP_LOCKS:
				var pair: Array = (rows[kmh] as Dictionary).get(lock, ["-", "-"])
				cells.append("%s / %s" % pair)
			lines.append("| %s | %.0f | %s |" % [label, kmh, " | ".join(cells)])
			label = ""
	return lines


## The `tyres` region: per DOC_TYRES body, a row per class it fits, a cell per DOC_TYRE_SURFACES
## surface: the full-pedal stop, the cornering pass's peak, the `tc` launch.
func _tyres_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=tyres`; per run `-- <variant> %.0f"
			+ " track corner brake tc tyre=<id> surface=<name>`). Each cell: the full-pedal stop from"
			+ " %.0f km/h, the cornering pass's path g at %.0f km/h (`slid`: the body let go), the `tc`"
			+ " 0-%.0f km/h time; `-` where the body never reached that speed in the cap.")
			% [DocRegion.measured(), _seconds, TYRES_STOP_KMH, CORNER_SPEED * 3.6, TYRES_LAUNCH_KMH])
	var head := "| Body | Tyre |"
	var rule := "| --- | --- |"
	for s in DOC_TYRE_SURFACES:
		head += " %s |" % Surface.display_name(s)
		rule += " --- |"
	lines.append_array(["", head, rule])
	var rows := {}  # "variant tyre" -> {surface -> entry}, in run order
	for e in _sweep:
		if e.has("tyre"):
			var by_surface: Dictionary = rows.get_or_add("%s %s" % [e["variant"], e["tyre"]], {})
			by_surface[e["surface"]] = e
	var last := ""
	for key: String in rows:
		var by_surface: Dictionary = rows[key]
		var first: Dictionary = by_surface.values()[0]
		var cells: Array[String] = []
		for s in DOC_TYRE_SURFACES:
			cells.append(_tyre_cell(by_surface.get(s, {})))
		var body := "`%s`" % first["variant"] if first["variant"] != last else ""
		last = first["variant"]
		lines.append("| %s | %s%s | %s |" % [body, first["tyre"], " (stock)" if first["stock"] else "",
				" | ".join(cells)])
	return lines


## "14.2 m, 0.81 g, 1.95 s": one doc=tyres run.
static func _tyre_cell(e: Dictionary) -> String:
	if e.is_empty():
		return "-"
	var stops: Array = e.get("braking", [])
	var stop := "-"
	if not stops.is_empty():
		var b: Dictionary = stops[0]
		stop = "%.1f m" % float(b["dist"])
		if float(b["v0_kmh"]) < TYRES_STOP_KMH - 1.0:
			stop = "from %.0f km/h: %s" % [float(b["v0_kmh"]), stop]
	var c: Dictionary = e.get("cornering", {})
	var corner := "-" if c.is_empty() or c.get("skipped", false) \
			else "%.2f g%s" % [c["path_g"], " slid" if c["slid"] else ""]
	var t: float = e.get("launch_t", NAN)
	return "%s, %s, %s" % [stop, corner, "-" if is_nan(t) else "%.2f s" % t]


## "1.42 deg/g at 0.21 g, 58 %": K and LLTD off the smallest held step at `kmh`.
static func _k_cell(runs: Array, kmh: float) -> String:
	for r: Dictionary in runs:
		if r["kmh"] == kmh and r["lock"] == STEP_LOCKS[0] and not r["lifted"]:
			if is_nan(float(r.get("k_dpg", NAN))):
				return "-"
			return "%.2f deg/g at %.2f g, %s" % [r["k_dpg"], r["lat_g"], _pct(r["lltd"])]
	return "-"


## "0.86, 0.42 s, +6 %": one step run's table cell.
static func _step_cell(r: Dictionary) -> String:
	if r.get("skipped", false):
		return "not reached"
	if float(r["roll_t"]) >= 0.0:
		return "rolled"
	var lifted := " (%d up)" % int(r["lifted_n"]) if int(r["lifted_n"]) > 0 else ""
	if float(r["spin_t"]) >= 0.0:
		return "spun" + lifted
	return "%.2f, %.2f s, %+.0f %%%s" % [r["of_neutral"], r["rise_s"], float(r["overshoot"]) * 100.0,
			lifted]


## The `accel` region: every wheel-driven variant's standing start, floored and `tc`, beside the
## real-world reference, with the floored run's 0-50 breakdown.
func _accel_table() -> Array[String]:
	var lines := DocRegion.wrap(("%s (`measure_vehicles -- doc=accel`; per body `-- <variant> %.0f`,"
			+ " plus `tc` for the slip-limited run): standing starts on the strip, pedal floored (with the"
			+ " body's own traction control where fitted), then"
			+ " slip-limited at the %.2f grip peak (`tc`), beside the real-world reference"
			+ " (`tools/vehicle_reference_specs.json`). The breakdown is the floored run's 0-50"
			+ " seconds: a driven wheel past %.2f slip, the limiter's fuel cut, a shift cut, the body's"
			+ " traction control holding a driven wheel back, and"
			+ " torque-bound (pedal floored, no cut or hold, every driven tyre under its peak), the part of"
			+ " that under converter stall in brackets; then grip use, the driven tyres' force over"
			+ " their load-scaled `mu_long` budget, floored / tc, with the rest of that budget in"
			+ " brackets: the grip curve short of its peak with the slip under / past %.2f, and"
			+ " what the one-tick force cap took off.")
			% [DocRegion.measured(), _seconds, TcPedal.TARGET_SLIP, SPIN_SLIP, TcPedal.TARGET_SLIP])
	lines.append_array(["", "| Body | 0-50 floored / tc / ref | 0-100 floored / tc / ref"
			+ " | 0-50 spin / limiter / shift / tcs / torque-bound (stall) | 0-50 grip use (under peak /"
			+ " past peak / tick cap) |",
			"| --- | --- | --- | --- | --- |"])
	for e in _sweep:
		if not e.has("launch"):
			continue
		var label := "`%s`" % e["variant"]
		if float(e.get("towed_kg", 0.0)) > 1.0:
			label += " + %.0f t towed" % (float(e["towed_kg"]) / 1000.0)
		var ref: Dictionary = (_reference.get(e["variant"], {}) as Dictionary).get("marks_s", {})
		var cells: Array[String] = []
		for kmh in LAUNCH_MARKS:
			var floored: Dictionary = e["launch"]["marks"]
			var tc: Dictionary = e.get("launch_tc", {}).get("marks", {})
			var ref_v: Variant = ref.get("%.0f" % kmh)
			cells.append("%s / %s / %s" % [_secs(floored.get(kmh)), _secs(tc.get(kmh)),
					_secs(ref_v, "%.1f")])
		var loss: Dictionary = e["launch"]["loss"].get(LAUNCH_MARKS[0], {})
		cells.append("-" if loss.is_empty() else "%.2f / %.2f / %.2f / %.2f / %.2f (%.2f)"
				% [loss["spin"], loss["limiter"], loss["shift"], loss["tcs"], loss["torque"],
				loss["stall"]])
		var tc_loss: Dictionary = e.get("launch_tc", {}).get("loss", {}).get(LAUNCH_MARKS[0], {})
		cells.append("%s / %s" % [_grip_cell(loss), _grip_cell(tc_loss)])
		lines.append("| %s | %s |" % [label, " | ".join(cells)])
	return lines


## "0.80 (0.02 / 0.15 / 0.03)": a grip-use table cell, `-` with no snapshot.
static func _grip_cell(l: Dictionary) -> String:
	if l.is_empty():
		return "-"
	var d := _deficit_shares(l)
	return "%.2f (%.2f / %.2f / %.2f)" % [_grip_use(l), d.x, d.y, d.z]


## Seconds for a table cell, `-` where the mark was not reached (or has no reference).
static func _secs(v: Variant, fmt := "%.2f") -> String:
	return "-" if v == null else fmt % float(v)


## One markdown file per sweep, measured figures beside REFERENCE_SPECS_PATH's real-world
## comparison figures. Named by timestamp so a re-run never overwrites the last one.
func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var lines: Array[String] = []
	lines.append("# Vehicle spec sweep — %s" % stamp)
	lines.append("")
	lines.append("Strip: %.0f x %.0f m flat, %s, zero steer input, %.0f s cap per pass."
			% [STRIP_WIDTH, STRIP_LENGTH, _surface_label(), _seconds])
	lines.append("Reference figures are real-world comparison numbers, not measured — see "
			+ "`tools/vehicle_reference_specs.json`.")
	lines.append("")
	for entry in _sweep:
		lines.append_array(_report_lines(entry))
	var f := FileAccess.open(REPORT_DIR + stamp + ".md", FileAccess.WRITE)
	f.store_string("\n".join(lines))


func _report_lines(e: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var ref: Dictionary = _reference.get(e["variant"], {})
	var ref_label: String = ref.get("label", "no reference data for this variant")
	var run := ""
	if e.has("tyre"):
		run = ", tyre %s on %s" % [e["tyre"], Surface.display_name(e["surface"])
				if int(e["surface"]) >= 0 else "bare ground"]
	lines.append("## %s (%s)%s" % [e["variant"], e["family"], run])
	lines.append("")
	if e.has("mass_label"):
		lines.append("%s, %s" % [e["mass_label"], e["drive_label"]])
		lines.append("")
	lines.append("| Metric | Measured | Reference (%s) |" % ref_label)
	lines.append("|---|---|---|")
	if e.has("marks"):
		var marks: Dictionary = e["marks"]
		var ref_marks: Dictionary = ref.get("marks_s", {})
		for kmh in [50.0, 96.56, 100.0, 150.0, 200.0]:
			var label := "0-60 mph" if kmh == 96.56 else "0-%.0f km/h" % kmh
			var measured := ("%.2f s" % marks[kmh]) if marks.has(kmh) else "not reached"
			var ref_key := "96.56" if kmh == 96.56 else "%.0f" % kmh
			var ref_v: Variant = ref_marks.get(ref_key)
			var reference := ("%.1f s" % ref_v) if ref_v != null else "not reached"
			lines.append("| %s | %s | %s |" % [label, measured, reference])
		var q_measured := "not reached"
		if marks.has("quarter"):
			var q: Vector2 = marks["quarter"]
			q_measured = "%.2f s @ %.1f km/h" % [q.x, q.y]
		var q_reference := "not reached"
		if ref.has("quarter_mile_s"):
			q_reference = "%.1f s @ %.0f km/h" % [ref["quarter_mile_s"], ref.get("quarter_mile_kmh", 0.0)]
		lines.append("| quarter mile | %s | %s |" % [q_measured, q_reference])
		var top_reference := ("%.0f km/h" % ref["top_speed_kmh"]) if ref.has("top_speed_kmh") else "not reached"
		lines.append("| %s | %.1f km/h, gear %d @ %.0f rpm | %s |"
				% [e["top_label"], e["top_kmh"], e["top_gear"], e["top_rpm"], top_reference])
		lines.append("| distance used | %.0f m of %.0f m%s | — |"
				% [e["dist"], e["run_length"], "  (STRIP RAN OUT)" if e["ran_out"] else ""])
		var b: Dictionary = e["balance"]
		lines.append("| force balance | tyres %.0f N - resistance %.0f N (declared %.0f) + rake %.0f N = %.0f N | — |"
				% [b["tyre"], b["applied"], b["declared"], b["rake"], b["net"]])
		if e.has("gear_note"):
			lines.append("| note | %s | — |" % e["gear_note"])
	for key in ["launch", "launch_tc"]:
		if not e.has(key):
			continue
		var l: Dictionary = e[key]
		for kmh in LAUNCH_MARKS:
			if (l["loss"] as Dictionary).has(kmh):
				lines.append("| launch 0-%.0f%s | %s | — |" % [kmh, " (tc)" if l["tc"] else "",
						_loss_label(l["loss"][kmh])])
	if e.has("tracking"):
		var t: Dictionary = e["tracking"]
		if t.get("skipped", false):
			lines.append("| tracking | never reached %.0f km/h, skipped | — |" % (TRACK_START_SPEED * 3.6))
		else:
			lines.append("| tracking | %s, drift %.3f m peak / %.3f m final over %.0f m, heading %.3f deg | — |"
					% ["PASS" if t["pass"] else "FAIL", t["drift_peak"], t["drift_final"],
					t["track_dist"], t["heading_peak"]])
	if e.has("cornering"):
		var c: Dictionary = e["cornering"]
		if c.get("skipped", false):
			lines.append("| cornering | never reached %.0f km/h, skipped | — |" % c["speed_kmh"])
		else:
			lines.append("| cornering | peak %.2f m/s^2 (%.2f g) at %.0f km/h, %s saturates first (front %.2f, rear %.2f)%s | — |"
					% [c["peak"], c["peak_g"], c["speed_kmh"], c["axle"], c["front"],
					c["rear"], "  (SLID)" if c["slid"] else ""])
	if e.has("braking"):
		for b: Dictionary in e["braking"]:
			lines.append("| braking %.0f%% | from %.0f km/h: %.2f s, %.1f m, %.2f g mean; skidding %.2f s, ABS %.2f s | — |"
					% [b["pedal"] * 100.0, b["v0_kmh"], b["t"], b["dist"], b["g"], b["skid_t"],
					b["abs_t"]])
	if e.has("coast"):
		var c: Dictionary = e["coast"]
		lines.append("| coast-down | %.1f -> %.1f km/h in %.1f s = %.3f m/s^2 (%.3f g), %.0f N on %.0f kg | — |"
				% [c["v0_kmh"], c["v1_kmh"], c["t"], c["decel"], c["decel_g"], c["force_n"], c["mass"]])
		lines.append("| coast model | declared %.0f N + overrun %.0f N = %.0f N; tyres carried %.0f N | — |"
				% [c["declared_n"], c["overrun_n"], c["declared_n"] + c["overrun_n"], c["tyres_n"]])
		lines.append("| hull contacts (accel) | %s | — |" % e.get("accel_contacts", "n/a"))
		lines.append("| hull contacts (coast) | %s | — |" % e["coast_contacts"])
	lines.append("")
	return lines
