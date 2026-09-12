extends GdUnitTestSuite
## BoatVehicle orchestration: the shipped hull over real water and a real seabed, ticked at the
## _tick_extras seam like test_drone_vehicle.gd. What the pure statics in test_boat.gd and
## test_boat_autopilot.gd cannot reach is the WIRING — which point the sounder is asked about and
## which list it walks, and which value the autopilot slews the helm FROM — so this suite exists
## for those call sites. Delta is 1/60 per standing rule 9.

const BOAT := "res://src/vehicles/watercraft/boat-speed-a.tscn"
const SAILBOAT := "res://src/vehicles/watercraft/boat-sail-a.tscn"
const TerrainScript := preload("res://src/levels/base/heightmap_terrain.gd")
const WaterScript := preload("res://src/water/water_surface.gd")

const DELTA := 1.0 / 60.0
const EXTENT := 200.0   ## square extent shared by the water region and the terrain


## The root answers WindField's duck-typed `wind_vector` walk, which is the only way a rig can put
## the hull in a breeze — WindField.at climbs parents looking for exactly this method. Dead calm
## by default, so every case that predates the rig reads the Vector3.ZERO it always did.
class WindyRoot extends Node3D:
	var wind := Vector3.ZERO

	func wind_vector() -> Vector3:
		return wind


## The rig: a level-ish root with water at y=0, a flat bed, and the hull floating on the surface.
## Only the ROOT is auto_free'd — that takes the whole subtree exactly once.
class Rig extends RefCounted:
	var root: WindyRoot
	var boat: BoatVehicle
	var bed: HeightmapTerrain
	var t: BoatTelemetry
	var input: VehicleInput

	## One tick in the base's own order. `_grip_terrains` is seeded here because
	## BaseVehicle._physics_process is what fills it in the running game, and this suite drives
	## the two sub-steps directly rather than the whole base tick.
	##
	## The helm slew is repeated verbatim from BaseVehicle._physics_process rather than skipped:
	## it is the pre-emption the autopilot has to undo, so a rig without it would let a
	## double-slewed rudder pass.
	func tick(n := 1) -> void:
		for _i in n:
			boat._grip_terrains = boat._find_grip_terrains()
			boat._steer = move_toward(boat._steer, input.steer, boat.spec.steer_speed * DELTA)
			boat._update_telemetry(input, DELTA)
			boat._tick_extras(input, DELTA)

	## Point the bow at a compass bearing (0 = north = -Z, increasing clockwise).
	func head(bearing_deg: float) -> void:
		boat.global_rotation = Vector3(0.0, deg_to_rad(-bearing_deg), 0.0)


## bed_y: the flat seabed's world Y. The hull sits at the origin with the waterline at y=0, which
## is where the generator puts a boat's model origin (tools/gen_boat_variants.gd).
func _rig(bed_y := -6.0, pos := Vector3.ZERO, scene := BOAT, wind := Vector3.ZERO) -> Rig:
	var r := Rig.new()
	r.root = auto_free(WindyRoot.new()) as WindyRoot
	r.root.wind = wind
	add_child(r.root)

	var water: WaterSurface = WaterScript.new()
	water.size = Vector2(EXTENT, EXTENT)
	r.root.add_child(water)
	water.global_position = Vector3.ZERO

	# No height texture, so height_at is the node's own Y: a flat bed at bed_y.
	r.bed = TerrainScript.new()
	r.bed.terrain_size = Vector2(EXTENT, EXTENT)
	r.root.add_child(r.bed)
	r.bed.global_position = Vector3(0.0, bed_y, 0.0)

	r.boat = (load(scene) as PackedScene).instantiate() as BoatVehicle
	r.root.add_child(r.boat)
	r.boat.global_position = pos
	r.boat.linear_velocity = Vector3.ZERO
	r.boat.angular_velocity = Vector3.ZERO
	r.t = r.boat.telemetry as BoatTelemetry
	r.input = VehicleInput.new()
	return r


func test_the_sounder_measures_from_the_probe_plane_and_not_from_the_origin() -> void:
	# The wiring the pure statics cannot see. The hull floats with its ORIGIN on the waterline and
	# its probes at -float_depth, and the transducer rides that probe plane — so over a bed 6 m
	# down the reading is 6 minus the draft. Asking about the origin instead would read a round
	# 6.0, and every case in test_boat.gd would still pass.
	var r := _rig(-6.0)
	r.tick()
	assert_float(r.boat.float_depth).is_greater(0.0)
	assert_float(r.t.depth).is_equal_approx(6.0 - r.boat.float_depth, 1e-3)


func test_the_sounding_follows_the_bed_up() -> void:
	# The same hull over a shoal: the reading is the water actually under her, not a constant.
	var r := _rig(-6.0)
	r.tick()
	var deep := r.t.depth
	r.bed.global_position = Vector3(0.0, -1.0, 0.0)
	r.tick()
	assert_float(r.t.depth).is_equal_approx(1.0 - r.boat.float_depth, 1e-3)
	assert_float(r.t.depth).is_less(deep)


func test_a_bed_above_the_transducer_bottoms_out_at_zero_rather_than_going_negative() -> void:
	var r := _rig(-6.0)
	r.bed.global_position = Vector3(0.0, 1.0, 0.0)
	r.tick()
	assert_float(r.t.depth).is_equal(0.0)


func test_off_the_terrain_there_is_no_bottom_and_the_sentinel_is_published() -> void:
	# Still over water, but past the seabed's extent: NO DEPTH, never a fabricated number off
	# height_at's clamped UV, and never 0 — which is the value a shoal alarm acts on.
	var r := _rig(-6.0)
	r.bed.terrain_size = Vector2(20.0, 20.0)
	r.boat.global_position = Vector3(60.0, 0.0, 0.0)
	r.tick()
	assert_float(r.t.depth).is_equal(BoatTelemetry.DEPTH_INVALID)


func test_out_of_the_water_the_sounder_reads_nothing() -> void:
	# On the trailer the anemometer still reads; the sounder does not.
	var r := _rig(-6.0, Vector3(500.0, 0.0, 0.0))
	r.tick()
	assert_float(r.t.depth).is_equal(BoatTelemetry.DEPTH_INVALID)
	assert_float(r.t.aws).is_greater_equal(0.0)


# --- the autopilot's call site -----------------------------------------------
# The laws are in test_boat_autopilot.gd. What only shows up here is the WIRING: which value the
# helm slews from, when the target is captured, and that the published rudder is the applied one.

func test_engaging_with_no_commanded_course_captures_the_heading_the_boat_is_on() -> void:
	var r := _rig()
	r.head(120.0)
	r.input.nav_mode = BoatAutopilot.STANDBY
	r.tick()
	# Standing by holds no target and reports the course an engage would take.
	assert_int(r.t.nav_mode_actual).is_equal(BoatAutopilot.STANDBY)
	assert_float(r.t.heading_target).is_equal_approx(120.0, 0.1)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.tick()
	assert_int(r.t.nav_mode_actual).is_equal(BoatAutopilot.HEADING_HOLD)
	assert_float(r.t.heading_target).is_equal_approx(120.0, 0.1)
	# The capture is an EDGE: swinging under the pilot does not drag the target along.
	r.head(126.0)
	r.tick()
	assert_float(r.t.heading_target).is_equal_approx(120.0, 0.1)


func test_a_commanded_course_overrides_the_capture() -> void:
	var r := _rig()
	r.head(120.0)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.input.heading_cmd = 250.0
	r.tick()
	assert_float(r.t.heading_target).is_equal_approx(250.0, 1e-3)
	# The bus going quiet does not make the pilot abandon the course: the target is only ever
	# re-taken on an ENGAGE edge, and the pilot is already engaged.
	r.input.heading_cmd = VehicleInput.HEADING_CMD_NONE
	r.tick(5)
	assert_float(r.t.heading_target).is_equal_approx(250.0, 1e-3)


func test_a_hand_on_the_helm_takes_the_rudder_back_and_releasing_it_recaptures() -> void:
	var r := _rig()
	r.head(120.0)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.tick()
	r.head(150.0)          # blown 30 degrees off; the pilot is pulling back to 120
	r.tick(10)
	assert_float(r.boat._steer).is_less(0.0)
	# The helmsman grabs the wheel: STANDBY, and the rudder follows the hand, not the course.
	r.input.steer = 1.0
	r.tick(30)
	assert_int(r.t.nav_mode_actual).is_equal(BoatAutopilot.STANDBY)
	assert_float(r.boat._steer).is_greater(0.0)
	# Letting go re-engages on the NEW heading rather than steering back to the old one.
	r.input.steer = 0.0
	r.tick()
	assert_int(r.t.nav_mode_actual).is_equal(BoatAutopilot.HEADING_HOLD)
	assert_float(r.t.heading_target).is_equal_approx(150.0, 0.1)


## The reason the boat re-runs the base's slew from its own `_helm` instead of adding a second
## one: two move_towards per tick cancel, and the rudder would never leave the middle.
func test_the_pilot_moves_the_rudder_at_the_helms_own_rate_and_no_faster() -> void:
	var r := _rig()
	r.head(0.0)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.tick()
	r.head(90.0)   # hard over: the pilot wants full rudder and has to slew there
	var per_tick := r.boat.spec.steer_speed * DELTA
	var prev := r.boat._steer
	for _i in 40:
		r.tick()
		assert_float(absf(r.boat._steer - prev)) \
			.override_failure_message("the rudder moved faster than a hand can") \
			.is_less_equal(per_tick + 1e-6)
		prev = r.boat._steer
	# ...and it does get there: a cancelling double slew would have pinned it near zero.
	assert_float(r.boat._steer).is_less(-0.9)


func test_the_published_rudder_is_the_one_the_pilot_applied() -> void:
	# _update_telemetry runs BEFORE _tick_extras and publishes the pre-empted helm, so an
	# autopilot that did not rewrite 'steer' would show the rudder centring while it steers.
	var r := _rig()
	r.head(0.0)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.tick()
	r.head(60.0)
	r.tick(20)
	assert_float(r.boat._steer).is_less(-0.1)
	assert_float(r.t.steer).is_equal_approx(r.boat._steer, 1e-6)
	assert_int(r.t.rudder_actual).is_equal(roundi(r.boat._steer * 100.0))


func test_respawn_recaptures_where_the_hull_now_points() -> void:
	var r := _rig()
	r.head(120.0)
	r.input.nav_mode = BoatAutopilot.HEADING_HOLD
	r.tick()
	assert_float(r.t.heading_target).is_equal_approx(120.0, 0.1)
	r.boat.spawn_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-40.0)), Vector3.ZERO)
	r.boat.respawn()
	r.tick()
	assert_float(r.t.heading_target) \
		.override_failure_message("a respawned hull is still steering to its old course") \
		.is_equal_approx(40.0, 0.1)


# --- the rig ------------------------------------------------------------------
#
# WHAT THESE REACH is the wiring: that the shipped sailboat scene carries the knobs, that the
# block is gated on `sail_area`, and that the boom is computed from THIS tick's apparent wind and
# the sheet on the input. The force's own magnitude and direction are tests/test_boat_sail.gd's,
# and how the hull rides under it is the driving pass — this suite steps _tick_extras by hand, so
# nothing integrates the forces it applies.

## Wind from the starboard beam: blowing toward -X with the bow at -Z is air arriving from +X.
const BEAM_WIND := Vector3(-5.0, 0.0, 0.0)


func test_the_shipped_sailboat_reads_the_beam_wind_and_answers_the_sheet() -> void:
	var r := _rig(-6.0, Vector3.ZERO, SAILBOAT, BEAM_WIND)
	assert_float(r.boat.sail_area).override_failure_message("no rig on the shipped scene") \
		.is_greater(0.0)
	r.input.sheet = 0.5
	r.tick()
	# awa is +90 at rest, so half the sheet is half of sheet_max_deg.
	assert_float(r.t.awa).is_equal_approx(90.0, 0.5)
	assert_float(r.t.sail_angle).is_equal_approx(r.boat.sheet_max_deg * 0.5, 0.5)
	# Hauling in is the same tick with a different sheet: the boom follows, no state in between.
	r.input.sheet = 0.0
	r.tick()
	assert_float(r.t.sail_angle).is_equal_approx(0.0, 1e-3)


func test_the_boom_falls_to_leeward_whichever_side_the_wind_is_on() -> void:
	var stbd := _rig(-6.0, Vector3.ZERO, SAILBOAT, BEAM_WIND)
	stbd.input.sheet = 0.5
	stbd.tick()
	var port := _rig(-6.0, Vector3.ZERO, SAILBOAT, -BEAM_WIND)
	port.input.sheet = 0.5
	port.tick()
	assert_float(port.t.sail_angle).is_equal_approx(-stbd.t.sail_angle, 0.5)
	assert_float(stbd.t.sail_angle).is_greater(0.0)


func test_a_powerboat_in_the_same_wind_has_no_rig_to_answer_with() -> void:
	# `sail_area` 0 is what skips the whole block; the signal is still declared by the family and
	# a resting 0 is the honest reading for a hull with no boom.
	var r := _rig(-6.0, Vector3.ZERO, BOAT, BEAM_WIND)
	r.input.sheet = 1.0
	r.tick()
	assert_float(r.boat.sail_area).is_equal(0.0)
	assert_float(r.t.aws).override_failure_message("no anemometer reading").is_greater(0.0)
	assert_float(r.t.sail_angle).is_equal(0.0)


func test_only_the_hull_with_a_rig_claims_the_sail_capability() -> void:
	# What gates the SHEET button and its CONTROLS row — a rig is anatomy, not a family trait.
	var sail := _rig(-6.0, Vector3.ZERO, SAILBOAT)
	var power := _rig()
	assert_bool(bool(sail.boat.vehicle_capabilities()["sail"])).is_true()
	assert_bool(bool(power.boat.vehicle_capabilities()["sail"])).is_false()


func test_the_boom_keeps_reading_with_the_hull_out_of_the_water() -> void:
	# The FORCE is gated on the buoyancy (a beached hull has no drag to oppose it) but the READING
	# is not, for the reason the anemometer is not: a boom swings on the trailer, and one frozen at
	# its last angle would be stale rather than still.
	# Ashore, the same way the sounder case puts it there: clear of the water region in XZ.
	var r := _rig(-6.0, Vector3(500.0, 0.0, 0.0), SAILBOAT, BEAM_WIND)
	r.input.sheet = 0.5
	r.tick()
	var why := "the hull is meant to be out of the water"
	assert_float(r.t.depth).override_failure_message(why).is_equal(BoatTelemetry.DEPTH_INVALID)
	assert_float(r.t.sail_angle).is_equal_approx(r.boat.sheet_max_deg * 0.5, 0.5)
