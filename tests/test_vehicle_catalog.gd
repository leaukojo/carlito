extends GdUnitTestSuite
## VehicleCatalog helpers and the force-hierarchy guard (brake > drive > handbrake).
## Regression here means the generator broke; fix the generator, not this test.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")


# --- catalog structure --------------------------------------------------------

func test_family_of_and_scene_of() -> void:
	assert_str(VehicleCatalog.family_of("sedan")).is_equal("car")
	assert_str(VehicleCatalog.family_of("firetruck")).is_equal("truck")
	assert_str(VehicleCatalog.family_of("tractor-kenney")).is_equal("tractor")
	assert_str(VehicleCatalog.family_of("boat-speed-a")).is_equal("boat")
	assert_str(VehicleCatalog.family_of("nope")).is_equal("")
	assert_str(VehicleCatalog.scene_of("sedan")).is_equal("res://src/vehicles/kenney/sedan.tscn")
	assert_str(VehicleCatalog.scene_of("nope")).is_equal("")


func test_first_in_family_is_the_default_body() -> void:
	# The garage (and a level's default_vehicle) spawn first_in_family. car / truck / boat /
	# tractor have no hand-built body, so they default to their first kit / watercraft variant.
	assert_str(VehicleCatalog.first_in_family("car")).is_equal("sedan-sports")
	assert_str(VehicleCatalog.first_in_family("truck")).is_equal("garbage-truck")
	assert_str(VehicleCatalog.first_in_family("boat")).is_equal("boat-speed-a")
	assert_str(VehicleCatalog.first_in_family("tractor")).is_equal("tractor-kenney")


func test_variants_in_family_grouping() -> void:
	var car := VehicleCatalog.variants_in_family("car")
	assert_int(car.size()).is_equal(15)   # 15 Kenney, incl. the three heavy vans
	assert_bool(car.has("sedan")).is_true()
	assert_bool(car.has("ambulance")).is_true()   # chassis class, not job — see VehicleCatalog
	assert_bool(car.has("firetruck")).is_false()
	# The truck family is the J1939 chassis class only: two Kenney bodies + the two hand-built
	# tractor units (the European cab-over and the North American conventional).
	assert_int(VehicleCatalog.variants_in_family("truck").size()).is_equal(4)
	assert_int(VehicleCatalog.variants_in_family("tractor").size()).is_equal(1)
	assert_int(VehicleCatalog.variants_in_family("boat").size()).is_equal(3)  # 3 watercraft


func test_next_in_family_wraps() -> void:
	var car := VehicleCatalog.variants_in_family("car")
	# cycling from the last variant returns to the first.
	assert_str(VehicleCatalog.next_in_family(car[car.size() - 1])).is_equal(car[0])
	assert_str(VehicleCatalog.next_in_family(car[0])).is_equal(car[1])
	var boat := VehicleCatalog.variants_in_family("boat")
	assert_str(VehicleCatalog.next_in_family(boat[0])).is_equal(boat[1])
	# unknown is returned unchanged.
	assert_str(VehicleCatalog.next_in_family("nope")).is_equal("nope")


func test_every_variant_scene_exists() -> void:
	for variant in VehicleCatalog.VARIANTS:
		assert_bool(ResourceLoader.exists(VehicleCatalog.scene_of(variant))) \
				.override_failure_message("missing scene for variant '%s'" % variant).is_true()


func test_every_variant_scene_has_a_hood_cam_marker() -> void:
	# ChaseCamera HOOD reads HoodCam Marker3D from PackedScene state (not instantiating).
	# Silent fallback if absent, so lost marker looks like "drifted" not missing.
	# Scene state is what the author tunes; no script run needed.
	for variant in VehicleCatalog.VARIANTS:
		var scene: PackedScene = load(VehicleCatalog.scene_of(variant))
		var state := scene.get_state()
		var found := false
		for i in state.get_node_count():
			if state.get_node_name(i) == &"HoodCam":
				found = true
				break
		assert_bool(found).override_failure_message(
				"%s has no HoodCam marker" % variant).is_true()


# --- the force hierarchy over every generated Kenney spec ---------------------

func test_kenney_specs_keep_force_hierarchy() -> void:
	for variant in VehicleCatalog.VARIANTS:
		var scene := VehicleCatalog.scene_of(variant)
		if not scene.begins_with("res://src/vehicles/kenney/"):
			continue  # hand-built legacy specs are covered elsewhere
		var spec_path := scene.trim_suffix(".tscn") + "_spec.tres"
		var spec: VehicleSpecScript = load(spec_path)
		assert_object(spec).override_failure_message("no spec for " + variant).is_not_null()
		var gd := spec.ground_drive

		var peak_engine := 0.0
		for p in spec.torque_curve:
			peak_engine = maxf(peak_engine, p.y)
		var max_drive: float = peak_engine * spec.gear_ratios[0] * spec.final_drive * spec.efficiency
		var total_brake: float = gd.brake_torque * gd.wheel_positions.size()
		var total_handbrake: float = gd.handbrake_torque * 2.0
		# Brake beats what driven wheels can transmit: tyre limit is mu_long * N * r.
		# Gearbox multiplies torque without limit; only the road limits tyre force.
		# Require brake to exceed tyre ceiling per wheel, not peak engine torque.
		# Static per-wheel load: same model the tyre ceiling uses.
		var driven := 0
		for p in gd.wheel_positions:
			if (p.z < 0.0 and gd.driven_front) or (p.z > 0.0 and gd.driven_rear):
				driven += 1
		var wheel_ceiling: float = spec.mass * 9.8 / maxi(gd.wheel_positions.size(), 1) \
				* gd.mu_long * gd.wheel_radius
		var transmissible: float = minf(max_drive, float(driven) * wheel_ceiling)
		# The assertion: full accel + full brake still stops, on the road rather than on paper.
		assert_float(total_brake).override_failure_message(
				"%s: brake %.0f <= the %.0f its %d driven wheels can transmit (peak drive %.0f)"
				% [variant, total_brake, transmissible, driven, max_drive]).is_greater(transmissible)
		# handbrake holds only below ~25% throttle: between the 25% and 50% launch brackets.
		var drive_25: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.25, 1))
		var drive_50: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.5, 1))
		assert_float(total_handbrake).override_failure_message(
				"%s: handbrake %.0f <= drive_25 %.0f" % [variant, total_handbrake, drive_25]).is_greater(drive_25)
		assert_float(total_handbrake).override_failure_message(
				"%s: handbrake %.0f >= drive_50 %.0f" % [variant, total_handbrake, drive_50]).is_less(drive_50)


## The variants whose brake torque is still more than four tyres can hold: they ship knowingly
## over-braked, with full pedal locking the wheels before the travel runs out.
const OVER_BRAKED := [
	# A ratchet: fixing one means deleting its name, and nothing new goes in without a reason
	# beside it. Currently empty. The one entry it ever carried was `race-future` at 1.28 g
	# against 1.25 of grip — AWD on a close-ratio 3.2 first, so its engine saturated all four
	# tyres. Fixed the only way that shape can be: first gear lengthened 3.2 -> 2.375, never a
	# bigger brake. Every 2-driven-wheel body clears the rule by 1.9x.
]


func test_no_kenney_spec_brakes_harder_than_its_tyres_except_the_listed_ones() -> void:
	# While brake_torque was 0.35 * peak drive this was an identity with the hierarchy assertion
	# above and could name any number: `race` shipped demanding 2.07 g from 1.2 g of grip. Sized
	# off the tyre it is a real claim — four wheels ask `4 * brake / r` of force and the road can
	# only answer `mass * g * mu_long`, so anything past that is a lock, not a stop.
	for variant in VehicleCatalog.VARIANTS:
		var scene := VehicleCatalog.scene_of(variant)
		if not scene.begins_with("res://src/vehicles/kenney/"):
			continue
		var spec: VehicleSpecScript = load(scene.trim_suffix(".tscn") + "_spec.tres")
		var gd := spec.ground_drive
		var wheels: int = maxi(gd.wheel_positions.size(), 1)
		var ceiling: float = spec.mass * 9.8 / wheels * gd.mu_long * gd.wheel_radius
		var demand_g: float = gd.brake_torque * wheels / gd.wheel_radius / spec.mass / 9.8
		if OVER_BRAKED.has(variant):
			# Ratchet: a listed variant that no longer exceeds its tyres has been fixed, and the
			# list has to shrink with it or the exemption quietly outlives the problem.
			assert_float(gd.brake_torque).override_failure_message(
					"%s is in OVER_BRAKED but brakes at %.2f g, within its %.2f g of grip — remove it"
					% [variant, demand_g, gd.mu_long]).is_greater(ceiling)
			continue
		assert_float(gd.brake_torque).override_failure_message(
				("%s demands %.2f g of braking from %.2f g of grip (%.0f Nm/wheel against %.0f)"
				+ " — the pedal is an on/off wheel lock") % [variant, demand_g, gd.mu_long,
				gd.brake_torque, ceiling]).is_less_equal(ceiling)


## Wheel-driven families. The free bodies below carry their own drag through VehicleMath and
## must NOT also declare a road-resistance pair, or they would be dragged twice.
const WHEELED_FAMILIES := ["car", "truck", "tractor"]


# --- resistance: every chassis declares its own, nothing rides an engine default ------

func test_every_wheeled_variant_declares_its_own_road_resistance() -> void:
	# The guard against the bug this model replaced. Until it landed, what set every wheeled
	# vehicle's top speed was `physics/3d/default_linear_damp` — a project setting nobody chose.
	# A new variant that ships with both terms at 0 now has NO drag at all rather than quietly
	# inheriting one, so the omission has to fail here instead of on the strip.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var spec := _spec_of(variant)
		assert_object(spec).override_failure_message("no spec for " + variant).is_not_null()
		assert_float(spec.ground_drive.drag_area).override_failure_message(
				"%s declares no drag_area — it would coast forever" % variant).is_greater(0.0)
		assert_float(spec.ground_drive.rolling_resistance).override_failure_message(
				"%s declares no rolling_resistance" % variant).is_greater(0.0)


func test_free_body_variants_declare_no_road_resistance() -> void:
	# The boat, drone, plane and train run their own drag (hull / air / the train's 1D sim), so
	# a road-resistance pair here would be a second, unaccounted term on top of it — exactly the
	# double-drag the engine default was. Read through the ground drive, because that is where
	# the pair lives; the boat/drone/train reach it with NO ground drive at all, which is the
	# stronger form of the same statement and is pinned on its own below.
	for variant in VehicleCatalog.VARIANTS:
		if WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var gd := _spec_of(variant).ground_drive
		if gd == null:
			continue  # no running gear, so no road resistance to declare
		assert_float(gd.drag_area).override_failure_message(
				"%s is a free body and must not also declare drag_area" % variant).is_equal(0.0)
		assert_float(gd.rolling_resistance).override_failure_message(
				"%s is a free body and must not also declare rolling_resistance"
				% variant).is_equal(0.0)


## Trailer specs are not catalog variants (a towed body is not a vehicle), but they carry the
## same running gear off the same resource, so the seam has to hold for them too.
const TRAILER_SPECS := [
	"res://src/vehicles/truck/trailers/box_spec.tres",
	"res://src/vehicles/truck/trailers/flatbed_spec.tres",
	"res://src/vehicles/truck/trailers/tanker_spec.tres",
	"res://src/vehicles/truck/trailers/tipper_spec.tres",
	"res://src/vehicles/tractor/trailers/farm_tipper_spec.tres",
]


# --- the ground-drive seam ----------------------------------------------------

func test_every_wheeled_variant_declares_a_ground_drive() -> void:
	# The other half of the split: a body that stands on wheels has to say so IN DATA, because
	# BaseVehicle builds no WheelDrive without one — a wheeled spec that lost its ground drive
	# would spawn a chassis with no wheels, no brakes and no suspension and simply fall over.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var gd := _spec_of(variant).ground_drive
		assert_object(gd).override_failure_message(
				"%s is wheeled but declares no ground_drive" % variant).is_not_null()
		assert_int(gd.wheel_positions.size()).override_failure_message(
				"%s declares a ground drive with no wheels" % variant).is_greater(0)
	for path: String in TRAILER_SPECS:
		var t_gd := (load(path) as VehicleSpecScript).ground_drive
		assert_object(t_gd).override_failure_message(
				"%s declares no ground_drive" % path).is_not_null()
		assert_int(t_gd.wheel_positions.size()).is_greater(0)


## The families with no running gear at all. The plane is deliberately NOT here: it stands on
## three braked, steered wheels and keeps a ground drive (see below).
const WHEEL_LESS_FAMILIES := ["boat", "drone", "train"]


func test_free_body_variants_declare_no_ground_drive() -> void:
	# The split, stated as data: a boat spec carries no wheel field. It is
	# also what decides which CODE runs — BaseVehicle builds no WheelDrive without a ground
	# drive, so a stray empty sub-resource here would quietly put the wheel-less bodies back on
	# the wheeled path (vacuous loops, an unread steer angle) with nothing else to show for it.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEEL_LESS_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		assert_object(_spec_of(variant).ground_drive).override_failure_message(
				"%s has no running gear and must declare no ground_drive" % variant).is_null()


func test_the_planes_ground_drive_is_undriven_and_makes_no_road_resistance() -> void:
	# The plane is the one body in this file no tool measures. measure_vehicles walks variants
	# with a driven axle and the plane has none, measure_drone is the quad's — so its landing
	# gear (three RayWheels, braked, nose wheel steered) is exercised only by flying it. Pin the
	# shape here instead: it HAS a ground drive (it is not a free body on the ground), that
	# drive is undriven, and its drag is the airframe's alone.
	var gd := _spec_of("plane").ground_drive
	assert_object(gd).override_failure_message(
			"the plane stands on wheels and must declare a ground drive").is_not_null()
	assert_int(gd.wheel_positions.size()).is_equal(3)
	assert_bool(gd.driven_front or gd.driven_rear).override_failure_message(
			"a light aircraft has no driven wheel").is_false()
	assert_float(gd.brake_torque).override_failure_message(
			"the plane brakes on the ground").is_greater(0.0)
	# Road resistance would be a SECOND drag term on a body that already runs its own through
	# VehicleMath — the double-drag the engine default was.
	assert_float(gd.drag_area).is_equal(0.0)
	assert_float(gd.rolling_resistance).is_equal(0.0)


func test_a_declared_wing_declares_its_drag_too() -> void:
	# A wing that makes no drag is a lie, and it is the cheap way to buy grip: downforce is
	# routed through the suspension precisely so it PAYS — ride height, rolling resistance from
	# the extra normal load, and the aero drag the same bodywork makes. A variant that shipped
	# downforce_area with drag_area 0 would have the grip for free.
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or spec.ground_drive.downforce_area <= 0.0:
			continue
		assert_float(spec.ground_drive.drag_area).override_failure_message(
				("%s declares a wing (Cl*A %.2f) but no drag_area — downforce with no drag is"
				+ " grip for free") % [variant, spec.ground_drive.downforce_area]).is_greater(0.0)


func test_downforce_fits_inside_the_suspension_travel_it_acts_through() -> void:
	# The budget on `cl`. Downforce is a force through the springs, so at the body's own top
	# speed the static load PLUS the wing has to still fit in the travel: a bottomed ray is a
	# chassis dragged through the ground, not more grip. 80 m/s (288 km/h) is what the two
	# open-wheelers actually reach, and nothing else in the catalog carries a wing at all.
	const TOP_SPEED := 80.0
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or spec.ground_drive.downforce_area <= 0.0:
			continue
		var gd := spec.ground_drive
		var corners := maxf(1.0, float(gd.wheel_positions.size()))
		var load_per_corner := (spec.mass * 9.8
				+ VehicleMath.aero_downforce(TOP_SPEED, gd.downforce_area)) / corners
		var spring_ceiling := gd.spring_rate * gd.rest_length
		assert_float(load_per_corner).override_failure_message(
				("%s bottoms out at %.0f km/h: %.0f N/corner against %.0f N of spring travel"
				+ " — cut cl, not the springs") % [variant, TOP_SPEED * 3.6, load_per_corner,
				spring_ceiling]).is_less(spring_ceiling)
		assert_float(load_per_corner).override_failure_message(
				"%s exceeds its own max_suspension_force at speed" % variant) 				.is_less(gd.max_suspension_force)


func test_a_coupled_rig_adds_a_trailers_drag_instead_of_multiplying_the_tractors() -> void:
	# THE §3 ARGUMENT, PINNED. Godot's damp is per-mass, so coupling a 24 t trailer to an 8 t
	# tractor made the rig resist ~4x a bobtail. Drag AREAS add, and a trailer's is a marginal
	# in-the-wake figure, so the combination has to land near a real artic's ~1.2-1.4x a rigid
	# truck rather than anywhere near its mass ratio.
	var tractor: VehicleSpecScript = load("res://src/vehicles/truck/semi_spec.tres")
	var trailer: VehicleSpecScript = load("res://src/vehicles/truck/trailers/box_spec.tres")
	var rigid: VehicleSpecScript = load("res://src/vehicles/kenney/garbage-truck_spec.tres")
	var combination: float = tractor.ground_drive.drag_area + trailer.ground_drive.drag_area
	var mass_ratio: float = (tractor.mass + trailer.mass) / tractor.mass
	assert_float(combination / tractor.ground_drive.drag_area).override_failure_message(
			"coupling multiplies the tractor's drag by %.2f (mass ratio is %.2f)"
			% [combination / tractor.ground_drive.drag_area, mass_ratio]).is_less(1.5)
	assert_float(combination / rigid.ground_drive.drag_area).override_failure_message(
			"the artic resists %.2fx a rigid truck" % (combination / rigid.ground_drive.drag_area)).is_less(1.6)


## How much more lock the floor must still offer than grip can actually use, checked at the
## speed where the floor first applies. The shipped fleet's worst is 2.65x (the conventional),
## the best 18.8x (sedan-sports), so this fails only on a value that is genuinely over-tapered
## and not on ordinary re-tuning.
const STEER_GRIP_MARGIN := 1.5


# --- steering: every wheeled body tapers its lock, and none of them tapers too far -------

func test_every_wheeled_variant_tapers_its_steering_at_speed() -> void:
	# The default is the DISABLED one (min_steer_frac 1.0), which is how every car, truck and
	# tractor shipped with its full lock live at motorway speed — `race` had all 40 degrees at
	# 140 km/h and would spin on a twitch. A new wheeled variant that forgets the pair inherits
	# that same silence, so the omission has to fail here rather than on the road.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var spec := _spec_of(variant)
		assert_object(spec).override_failure_message("no spec for " + variant).is_not_null()
		var gd := spec.ground_drive
		assert_float(gd.steer_falloff_speed).override_failure_message(
				"%s has no steer_falloff_speed — its taper is inert" % variant).is_greater(0.0)
		assert_float(gd.min_steer_frac).override_failure_message(
				"%s keeps its full lock at speed (min_steer_frac 1.0)" % variant).is_less(1.0)


func test_a_steering_taper_never_out_limits_the_tyres() -> void:
	# The other half, and the one that is not obvious from the number. min_steer_frac is a
	# fraction of each body's OWN max_steer_deg, so the same value means different degrees on a
	# 22-degree truck rack and a 42-degree open-wheeler — reading the fractions side by side
	# tells you nothing about whether any of them can still corner. What has to hold is that the
	# tyres give up before the rack does: at the floor, the steady-state Ackermann angle the
	# body can still ask for must exceed the one mu_lat can actually hold at that speed. Below
	# the floor speed the rack is the limit on EVERY vehicle (no rack generates 1 g at walking
	# pace), which is why the check is at steer_falloff_speed and not lower — that is also the
	# worst point, since above it the floor is flat while the grip angle keeps falling as 1/v^2.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var spec := _spec_of(variant)
		var wheelbase := _wheelbase_of(spec)
		assert_float(wheelbase).override_failure_message(
				"%s has no wheelbase to steer about" % variant).is_greater(0.0)
		var v := spec.ground_drive.steer_falloff_speed
		var floor_deg: float = spec.ground_drive.max_steer_deg * spec.ground_drive.min_steer_frac
		# a = v^2/R and R = wheelbase / tan(steer), so the angle mu_lat * g can sustain.
		var grip_deg := rad_to_deg(atan(spec.ground_drive.mu_lat * 9.8 * wheelbase / (v * v)))
		assert_float(floor_deg).override_failure_message(
				"%s: %.1f deg of lock at %.0f m/s against %.1f deg of grip (%.2fx, floor %.2fx)"
				% [variant, floor_deg, v, grip_deg, floor_deg / grip_deg, STEER_GRIP_MARGIN]
				).is_greater(grip_deg * STEER_GRIP_MARGIN)


## Front-to-rear wheel spread, read off the stations rather than declared: it is just the z
## extent of the same array.
func _wheelbase_of(spec: VehicleSpecScript) -> float:
	if spec.ground_drive.wheel_positions.is_empty():
		return 0.0
	var zmin := INF
	var zmax := -INF
	for station in spec.ground_drive.wheel_positions:
		zmin = minf(zmin, station.z)
		zmax = maxf(zmax, station.z)
	return zmax - zmin


## A variant's VehicleSpec, read out of the PackedScene's STATE rather than by instantiating it.
## Instantiating a vehicle just to read one exported resource leaves orphan nodes behind (the
## Kenney bodies carry sub-scenes), which gdUnit reports and CI treats as a failure — and no
## vehicle script has to run to answer "what spec does this scene ship".
## speed_limit (J1939 SPN 74): one byte, 1 km/h per bit, 0..250 km/h. Spec at 300 wraps to 44;
## 90.5 truncates silently. Fail here on every family.
func test_every_declared_speed_limit_fits_the_byte_it_is_published_in() -> void:
	var governed := 0
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		assert_object(spec).override_failure_message("no spec for " + variant).is_not_null()
		var limit := spec.speed_limit_kmh
		assert_float(limit).override_failure_message(
				"%s: speed_limit_kmh %f is negative" % [variant, limit]).is_greater_equal(0.0)
		assert_float(limit).override_failure_message(
				"%s: speed_limit_kmh %f exceeds SPN 74's 250 km/h" % [variant, limit]) 			.is_less_equal(250.0)
		assert_float(limit).override_failure_message(
				"%s: speed_limit_kmh %f is not a whole km/h — SPN 74 has no fraction" 				% [variant, limit]).is_equal(float(roundi(limit)))
		if limit > 0.0:
			governed += 1
	# ...and the sweep must actually be sweeping something: nine shipped specs carry a limiter
	# (van, pickup, pickup-flat, ambulance, garbage-truck, firetruck, tractor-kenney, semi,
	# conventional), and a regen that dropped the field would otherwise pass this silently.
	assert_int(governed).override_failure_message(
			"no shipped spec declares a speed_limit_kmh any more").is_equal(9)


## The unnamed interface the shell duck-types at ~8 sites (vehicle_select's ATTACH button,
## boot's implement cycling, the dashboard's articulation readout). It is NOT hoisted onto
## BaseVehicle on purpose — a method's ABSENCE is what keeps the ATTACH button off every car
## (src/vehicles/CLAUDE.md) — so the seven have to move together, and nothing in the code makes
## them. `vehicle_select.gd` guards on `set_attachment` and then calls `attachment_ids()` and
## `current_attachment()` unguarded, which is only safe because the set is all-or-none. That
## invariant is held HERE and nowhere else; a guard at the call site would hide it instead.
const ATTACHMENT_AXIS := [
	"cycle_implement", "attachment_ids", "current_attachment", "set_attachment",
	"attachment_controls", "set_display_frozen", "articulation",
]

## The towing bodies, and the whole list of them: TractorVehicle (three-point hitch + drawbar)
## and SemiTractor (fifth wheel), which between them script exactly these three variants.
const TOWING_VARIANTS := ["tractor-kenney", "semi", "semi-conventional"]


# --- the attachment axis: all of it, or none of it -----------------------------

func test_the_attachment_axis_is_all_or_none_and_only_the_towing_variants_have_it() -> void:
	var with_axis: Array[String] = []
	for variant in VehicleCatalog.VARIANTS:
		var methods := _script_methods_of(variant)
		var present: Array[String] = []
		var absent: Array[String] = []
		for method: String in ATTACHMENT_AXIS:
			if methods.has(method):
				present.append(method)
			else:
				absent.append(method)
		assert_bool(present.is_empty() or absent.is_empty()).override_failure_message(
				("%s defines HALF the attachment axis: has %s, missing %s. The shell calls"
				+ " attachment_ids()/current_attachment() unguarded behind a set_attachment"
				+ " check — define all seven or none.") % [variant, present, absent]).is_true()
		if not present.is_empty():
			with_axis.append(variant)
	with_axis.sort()
	var expected := TOWING_VARIANTS.duplicate()
	expected.sort()
	assert_array(with_axis).override_failure_message(
			("the attachment axis is defined by %s, expected exactly %s — a new towing body needs"
			+ " a name here, and a car that grew these methods grew an ATTACH button with it")
			% [with_axis, expected]).is_equal(expected)


## Every method name reachable on a variant's root script, walking the GDScript inheritance chain
## by hand. Read off the SCRIPT rather than an instance for the same reason as `_spec_of`: a
## vehicle scene instanced only to be asked a question leaves orphans behind, and `has_method` on
## a live node would answer the identical question.
func _script_methods_of(variant: String) -> PackedStringArray:
	var out := PackedStringArray()
	var state := (load(VehicleCatalog.scene_of(variant)) as PackedScene).get_state()
	var script: Script = null
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"script":
			script = state.get_node_property_value(0, i) as Script
			break
	while script != null:
		for m in script.get_script_method_list():
			out.append(m["name"])
		script = script.get_base_script()
	return out


func _spec_of(variant: String) -> VehicleSpecScript:
	var state := (load(VehicleCatalog.scene_of(variant)) as PackedScene).get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"spec":
			return state.get_node_property_value(0, i) as VehicleSpecScript
	return null
