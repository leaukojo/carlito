extends GdUnitTestSuite
## VehicleCatalog helpers and the brake-hardware guards (lock, stall hold, parking grade, pawl).
## Regression here means the generator broke; fix the generator, not this test.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")
const Layers := preload("res://src/physics/collision_layers.gd")


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
	# One tractor body on two gearboxes: the powershift and the CVT.
	assert_int(VehicleCatalog.variants_in_family("tractor").size()).is_equal(2)
	assert_int(VehicleCatalog.variants_in_family("boat").size()).is_equal(3)  # 3 watercraft


func test_the_modelled_drone_is_the_drone_family_default() -> void:
	# Levels and the garage name a FAMILY and spawn its first variant, so this order IS the default.
	assert_str(VehicleCatalog.first_in_family("drone")).is_equal("drone-mk2")
	assert_array(Array(VehicleCatalog.variants_in_family("drone"))).is_equal(["drone-mk2", "drone"])


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


## LampSet skips a path that resolves to nothing (or to the wrong node type) silently, so a lens
## renamed in a scene or a regen is a dark lamp with nothing to say so. Resolved on an instance
## that never enters the tree: the paths name scene-authored nodes, not ones `_ready` builds.
func test_every_variant_lamp_path_resolves_in_its_own_scene() -> void:
	# The plain drone loads drone-mk2's spec and has none of its lamps, by design
	# (test_drone_indicators pins them on the mk2); the skip holds only while the spec is shared.
	assert_str(_spec_of("drone").resource_path).is_equal(_spec_of("drone-mk2").resource_path)
	for variant in VehicleCatalog.VARIANTS:
		if variant == "drone":
			continue
		var body := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate()
		var spec: VehicleSpecScript = body.get("spec")
		for p in spec.headlight_paths:
			assert_object(body.get_node_or_null(p)) \
					.override_failure_message("%s: headlight_paths -> %s is no SpotLight3D" % [
						variant, p]) \
					.is_instanceof(SpotLight3D)
		var groups := {
			"head_lamp_paths": spec.head_lamp_paths,
			"brake_lamp_paths": spec.brake_lamp_paths,
			"turn_left_paths": spec.turn_left_paths,
			"turn_right_paths": spec.turn_right_paths,
			"steady_lamp_paths": spec.steady_lamp_paths,
			"flash_lamp_paths": spec.flash_lamp_paths,
			"strobe_lamp_paths": spec.strobe_lamp_paths,
			"led_lamp_paths": spec.led_lamp_paths,
		}
		for group_name in groups:
			for p: NodePath in groups[group_name]:
				assert_object(body.get_node_or_null(p)) \
						.override_failure_message("%s: %s -> %s is no MeshInstance3D" % [
							variant, group_name, p]) \
						.is_instanceof(MeshInstance3D)
		body.free()


## The water kill volume masks VEHICLE (test_collision_layers pins that side); this pins the other
## side, on every body after its `_ready` — BaseVehicle's or a family override that skips `super`.
func test_every_variant_sits_on_the_vehicle_layer() -> void:
	for variant in VehicleCatalog.VARIANTS:
		var body := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate() \
				as CollisionObject3D
		add_child(body)
		assert_int(body.collision_layer) \
				.override_failure_message("%s is on layer %d, not VEHICLE" % [
					variant, body.collision_layer]) \
				.is_equal(Layers.VEHICLE)
		body.free()


# --- engine constants over every generated Kenney spec -------------------------

func test_kenney_specs_keep_their_engine_constants_in_band() -> void:
	for variant in VehicleCatalog.VARIANTS:
		var scene := VehicleCatalog.scene_of(variant)
		if not scene.begins_with("res://src/vehicles/kenney/"):
			continue  # hand-built specs are covered by their family's suites
		var spec: VehicleSpecScript = load(scene.trim_suffix(".tscn") + "_spec.tres")
		assert_object(spec).override_failure_message("no spec for " + variant).is_not_null()
		assert_float(spec.engine_brake_frac).override_failure_message(
				variant + ": engine_brake_frac outside [0, 0.3]").is_between(0.0, 0.3)
		assert_float(spec.shift_cut_s).override_failure_message(
				variant + ": shift_cut_s outside [0, 1]").is_between(0.0, 1.0)


# --- the shift policy over every gearbox ---------------------------------------------

## Steps of the pedal grid the no-hunt guard sweeps (0, 0.05 .. 1).
const SHIFT_PEDAL_STEPS := 20


## Every variant's spec with a gearbox to shift: every family, since the plane, boats, drone and
## train walk one for the gear byte.
func _gearbox_specs() -> Dictionary:
	var out := {}
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec != null and spec.gear_ratios.size() >= 2:
			out[variant] = spec
	return out


static func _top_gear(spec: VehicleSpecScript) -> int:
	return mini(DrivetrainScript.TOP_GEAR, spec.gear_ratios.size())


## Full pedal is where the launches and top speeds are tuned: there the policy is the box's two fixed
## thresholds, on every gear, and the landing floor moves no upshift point. A skip box takes in one
## shift the gears a chain of forced shifts would: over-revved a step past `shift_up_rpm` (each
## landing at or past the point forces the next), or lugged a step under the coast line.
func test_every_box_shifts_at_its_full_pedal_pair_at_full_pedal() -> void:
	var specs := _gearbox_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		var top := _top_gear(spec)
		var coast := ShiftPolicy.down_rpm(spec, 0.0)
		for byte in range(1, top + 1):
			if byte < top:
				assert_float(ShiftPolicy.upshift_rpm(spec, byte, 1.0)).override_failure_message(
						"%s: D%d's full-pedal upshift moved off shift_up_rpm" % [variant, byte]) \
						.is_equal(spec.shift_up_rpm)
			var ratio := spec.gear_ratios[byte - 1]
			var rpm := spec.idle_rpm
			while rpm <= spec.redline_rpm:
				var expected := byte
				if rpm >= spec.shift_up_rpm and byte < top:
					expected = byte + 1
					while spec.skip_shifts and expected < top \
							and rpm * spec.gear_ratios[expected - 1] / ratio >= spec.shift_up_rpm:
						expected += 1
				elif rpm <= spec.shift_down_rpm and byte > 1:
					expected = byte - 1
					while spec.skip_shifts and rpm <= coast and expected > 1 \
							and rpm * spec.gear_ratios[expected - 1] / ratio <= coast:
						expected -= 1
				assert_int(ShiftPolicy.next_gear(spec, byte, rpm, 1.0, INF, false)) \
						.override_failure_message("%s: D%d at %.0f rpm, full pedal" % [variant, byte,
						rpm]).is_equal(expected)
				rpm += 25.0


## No box hunts at any pedal: every upshift lands LANDING_MARGIN over the downshift point at the
## same pedal, the map rises with the pedal, a stop steps the box down to D1 (the coast downshift
## sits over idle, which the gear selection's rpm is clamped to), and a kickdown never lands past
## its ceiling.
func test_no_box_hunts_at_any_pedal() -> void:
	var specs := _gearbox_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		var top := _top_gear(spec)
		assert_float(ShiftPolicy.up_rpm(spec, 0.0)).override_failure_message(
				variant + ": the light upshift sits over the full-pedal one") \
				.is_less_equal(spec.shift_up_rpm)
		assert_float(ShiftPolicy.down_rpm(spec, 0.0)).override_failure_message(
				variant + ": the coast downshift sits over the full-pedal one") \
				.is_less_equal(spec.shift_down_rpm)
		assert_float(ShiftPolicy.down_rpm(spec, 0.0)).override_failure_message(
				variant + ": the coast downshift is at or under idle; a stop strands the gear") \
				.is_greater(spec.idle_rpm)
		for i in SHIFT_PEDAL_STEPS + 1:
			var pedal := float(i) / SHIFT_PEDAL_STEPS
			var down := ShiftPolicy.down_rpm(spec, pedal)
			for byte in range(1, top):
				var land := ShiftPolicy.upshift_rpm(spec, byte, pedal) \
						* spec.gear_ratios[byte] / spec.gear_ratios[byte - 1]
				assert_float(land).override_failure_message(
						"%s: D%d>D%d lands %.0f rpm at pedal %.2f, under %.2fx its %.0f downshift"
						% [variant, byte, byte + 1, land, pedal, ShiftPolicy.LANDING_MARGIN, down]) \
						.is_greater_equal(ShiftPolicy.LANDING_MARGIN * down - 1e-2)
		for byte in range(2, top + 1):
			var rpm := spec.idle_rpm
			while rpm <= spec.redline_rpm:
				var k := ShiftPolicy.kickdown_target(spec, byte, rpm)
				if k < byte:
					assert_float(rpm * spec.gear_ratios[k - 1] / spec.gear_ratios[byte - 1]) \
							.override_failure_message("%s: a kickdown from D%d lands past its ceiling"
							% [variant, byte]) \
							.is_less_equal(ShiftPolicy.kickdown_ceiling_rpm(spec))
				rpm += 50.0


## A box single-speed by construction (its upshift point past the redline the gear selection's rpm
## is clamped to: the plane) stays single-speed at every pedal.
func test_a_single_speed_box_never_upshifts_at_any_pedal() -> void:
	var specs := _gearbox_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		if spec.shift_up_rpm < spec.redline_rpm:
			continue
		for i in SHIFT_PEDAL_STEPS + 1:
			var pedal := float(i) / SHIFT_PEDAL_STEPS
			assert_int(ShiftPolicy.next_gear(spec, 1, spec.redline_rpm, pedal, INF, false)) \
					.override_failure_message("%s upshifts at pedal %.2f" % [variant, pedal]) \
					.is_equal(1)


# --- brake hardware over every wheel-driven body ---------------------------------

## Every wheel-driven variant's spec, keyed by variant (the hand-built semis included).
func _driven_specs() -> Dictionary:
	var out := {}
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var spec := _spec_of(variant)
		if spec != null and spec.ground_drive != null:
			out[variant] = spec
	return out


## How far a foot brake is rated past its stock tyre's grip.
const BRAKE_STOCK_MARGIN := 1.15


func test_every_foot_brake_can_lock_its_wheels() -> void:
	# The hardware is rated on its own, past what the tyre can use: full pedal locks a wheel without
	# ABS, or ABS holds it at the grip peak. A total, not per axle: proportioning gives each axle its
	# share at the tyre-limited stop's transfer, and the measured braking table shows each lock.
	# The design margin is over the stock tyre; every other class the fit takes need only lock, as
	# a real body's brakes still lock its aftermarket summers (`taxi` on Summer has 1.14x).
	var specs := _driven_specs()
	assert_int(specs.size()).is_greater(0)
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		for cls in TyreCatalog.fitting(spec.ground_drive.tyre_fit):
			var mu: float = spec.ground_drive.mu_long * _asphalt_ratio(cls, spec.ground_drive)
			var margin := BRAKE_STOCK_MARGIN if cls.id == spec.ground_drive.tyre.id else 1.0
			assert_float(BrakeSizing.capacity_g(spec)).override_failure_message(
					"%s on %s: %.2f g of brake against %.2f of tyre (needs %.2fx)" % [variant,
					cls.id, BrakeSizing.capacity_g(spec), mu, margin]) \
					.is_greater_equal(margin * mu)


## `cls`'s dry-asphalt grip over the body's spec mu (its stock class's).
static func _asphalt_ratio(cls: TyreClass, gd: GroundDriveSpec) -> float:
	return TyreClass.grip_response(cls, gd.tyre)[Surface.ASPHALT]


func test_the_full_foot_brake_holds_gear_one_at_converter_stall() -> void:
	# Both pedals floored in D1: the brakes hold the body (a driven wheel may spin, a brake-stand
	# burnout) with no help from InputRouter.brake_override, which stays a modelled feature.
	var specs := _driven_specs()
	for variant: String in specs:
		var margin := BrakeSizing.stall_hold_margin(specs[variant])
		assert_float(margin).override_failure_message(
				"%s: the full foot brake holds only %.2f of gear 1 at stall" % [variant, margin]) \
				.is_greater_equal(1.0)


func test_every_engine_that_drives_wheels_declares_its_crank_and_coupling() -> void:
	# The crank is a rotating mass on every wheel-driving body (`Drivetrain.drives_wheels`): its
	# inertia is declared per class, never the floor a missing value falls to; its friction is
	# declared (what runs it down to idle, and a key-off crank to rest) and never past the motoring
	# law's redline anchor; and its coupling is rated at least at the engine's peak, or a locked
	# clutch would slip under its own engine.
	var specs := _driven_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		if not Drivetrain.drives_wheels(spec):
			continue
		assert_float(spec.engine_inertia).override_failure_message(
				"%s declares no engine_inertia" % variant).is_greater(0.01)
		assert_float(spec.engine_friction_frac).override_failure_message(
				"%s declares no engine_friction_frac" % variant).is_greater(0.0)
		assert_float(spec.engine_friction_frac).override_failure_message(
				"%s: friction %.2f past its redline motoring %.2f" % [variant,
				spec.engine_friction_frac, spec.engine_brake_frac]) \
				.is_less_equal(spec.engine_brake_frac)
		assert_float(spec.clutch_reserve).override_failure_message(
				"%s: a coupling rated %.2fx its peak" % [variant, spec.clutch_reserve]) \
				.is_greater_equal(1.0)
		if spec.coupling != VehicleSpec.Coupling.CONVERTER:
			continue
		# A converter multiplies (or at 1.0 passes) its impeller's torque, never less, and its
		# lock-up closes in a gear the box has.
		assert_float(spec.converter_stall_ratio).override_failure_message(
				"%s: a converter ratio of %.2f" % [variant, spec.converter_stall_ratio]) \
				.is_greater_equal(1.0)
		assert_int(spec.lockup_gear).override_failure_message(
				"%s: lock-up from D%d" % [variant, spec.lockup_gear]) \
				.is_between(1, mini(spec.gear_ratios.size(), Drivetrain.TOP_GEAR))


func test_every_pedal_map_is_none_at_rest_the_curve_floored_and_monotone() -> void:
	# The pedal reaches the crank only through `PedalMap.fuel`: no fuel at pedal 0, the whole curve
	# at pedal 1 (every floored figure is the curve's), and never less fuel for more pedal, from
	# under idle to past the redline. An all-speed governor is the idle controller at pedal 0 (it
	# fuels a crank under idle) and cuts past its high idle, the redline: there no fuel at pedal 0
	# from just over idle, and the whole curve at pedal 1 up to the redline.
	var specs := _driven_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		if not Drivetrain.drives_wheels(spec):
			continue
		var governed := spec.pedal_map == PedalMap.Kind.ALL_SPEED
		var at_rpm := spec.idle_rpm * 0.5
		while at_rpm <= spec.redline_rpm * 1.1:
			if not governed or at_rpm >= spec.idle_rpm * 1.05:
				assert_float(PedalMap.fuel(spec, 0.0, at_rpm)).override_failure_message(
						"%s: fuel at pedal 0, %.0f rpm" % [variant, at_rpm]).is_equal(0.0)
			if not governed or at_rpm <= spec.redline_rpm:
				assert_float(PedalMap.fuel(spec, 1.0, at_rpm)).override_failure_message(
						"%s: under full fuel floored at %.0f rpm" % [variant, at_rpm]).is_equal(1.0)
			var prev := 0.0
			for i in range(1, 101):
				var f := PedalMap.fuel(spec, i * 0.01, at_rpm)
				assert_float(f).override_failure_message("%s: pedal %.2f at %.0f rpm fuels %f under %f"
						% [variant, i * 0.01, at_rpm, f, prev]).is_greater_equal(prev)
				prev = f
			at_rpm += 250.0


func test_every_road_body_carries_a_hill_hold_and_the_tractor_a_powershift_one() -> void:
	# Hill-start assist rides with ABS (the road bodies and trucks, the semis' AMT included); the
	# open-wheelers carry neither. The tractor's is a powershift hill hold, with no timeout.
	var specs := _driven_specs()
	for variant: String in specs:
		var gd: GroundDriveSpec = (specs[variant] as VehicleSpecScript).ground_drive
		if gd.abs_equipped:
			assert_int(gd.hill_hold).override_failure_message(
					"%s carries ABS and no hill-start assist" % variant) \
					.is_equal(HillHold.Kind.ASSIST)
			assert_float(gd.hill_hold_s).override_failure_message(
					"%s: hill-start assist held %.1f s" % [variant, gd.hill_hold_s]).is_greater(0.0)
		elif gd.front_axle_engageable and DrivetrainScript.is_cvt(specs[variant]):
			# A CVT tractor holds in its transmission (`Drivetrain.standstill_hold`): no brake hold.
			assert_int(gd.hill_hold).override_failure_message(
					"%s: a CVT tractor's active standstill is its hold" % variant) \
					.is_equal(HillHold.Kind.NONE)
		elif gd.front_axle_engageable:
			assert_int(gd.hill_hold).override_failure_message(
					"%s: a powershift tractor with no hill hold" % variant) \
					.is_equal(HillHold.Kind.STANDSTILL)
		else:
			assert_int(gd.hill_hold).override_failure_message(
					"%s: a hill hold on a body without ABS" % variant) \
					.is_equal(HillHold.Kind.NONE)


func test_every_free_crank_settles_on_its_steepest_droop_without_ringing() -> void:
	# The crank's step is semi-implicit in its own curve (`Drivetrain.crank_compliance`): on the
	# steepest falling segment, held at the fuel that balances the motoring law mid-segment, a free
	# crank started at the segment's top climbs onto that point and never passes it. The fuel is held
	# as the pedal on a linear copy: a torque-request map holds its request, not a fuel.
	var specs := _driven_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = (specs[variant] as VehicleSpecScript).duplicate()
		spec.pedal_map = PedalMap.Kind.LINEAR
		if not Drivetrain.drives_wheels(spec):
			continue
		var curve := spec.torque_curve
		var steepest := -1
		var drop := 0.0
		for i in range(1, curve.size()):
			var fall := (curve[i - 1].y - curve[i].y) / (curve[i].x - curve[i - 1].x)
			if fall > drop:
				drop = fall
				steepest = i
		if steepest < 0 or curve[steepest].x > spec.redline_rpm:
			continue
		var mid := (curve[steepest - 1].x + curve[steepest].x) * 0.5
		var pedal := Drivetrain.drag_fuel(spec, mid)
		var dt := Drivetrain.new(spec)
		dt.rpm = curve[steepest - 1].x + 1.0
		var prev := dt.rpm
		for i in 240:
			dt.process(1.0 / 60.0, pedal, 0.0, 0.0, Drivetrain.GEAR_N, false)
			dt.couple(func(_spin: float, _c: float, _cap: float) -> float: return 0.0,
					func(_t: float) -> float: return 0.0)
			assert_float(dt.rpm).override_failure_message(
					"%s rang on its %.0f-%.0f rpm droop: %.1f after %.1f" % [variant,
					curve[steepest - 1].x, curve[steepest].x, dt.rpm, prev]) \
					.is_between(prev - 1e-6, mid + 1e-3)
			prev = dt.rpm
		assert_float(dt.rpm).override_failure_message("%s never reached its droop" % variant) \
				.is_equal_approx(mid, 1.0)


func test_the_centre_carries_an_axles_shortfall_to_the_other_axles_brakes() -> void:
	# `suv-luxury`'s rear brakes are under their own drive at stall, its fronts' have spare. Its
	# Torsen centre carries the rears' shortfall forward, as the coupled solve does, and nothing
	# pushes; an open centre carries none, and the rears push against the fronts' hold (a brake-stand
	# burnout).
	var spec: VehicleSpecScript = _spec_of("suv-luxury").duplicate()
	spec.ground_drive = spec.ground_drive.duplicate()
	var gd := spec.ground_drive
	assert_float(gd.axle_brake_torque(true)).is_less(absf(Drivetrain.stall_axle_torque(spec)) / 4.0)
	assert_float(BrakeSizing.stall_hold_margin(spec)).is_equal(INF)
	gd.centre_diff_bias = 1.0
	var open := BrakeSizing.stall_hold_margin(spec)
	assert_bool(is_finite(open)).is_true()
	# A rigid centre carries it all.
	gd.centre_diff_rigid = true
	assert_float(BrakeSizing.stall_hold_margin(spec)).is_equal(INF)


func test_every_handbrake_locks_the_rears_and_parks_on_its_regulation_grade() -> void:
	# A parking brake that can lock the rears makes the handbrake turn (the combined-slip tyre drops a
	# locked wheel's side force), and it parks the laden body on UN R13-H's 20 % or R13's 18 %. A
	# semi-trailer rig adds the trailer's spring brakes (test_trailer).
	var specs := _driven_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		assert_float(BrakeSizing.rear_lock_ratio(spec)).override_failure_message(
				"%s: the handbrake cannot lock the rears" % variant).is_greater(1.0)
		var need := BrakeSizing.regulation_grade(spec.mass)
		assert_float(BrakeSizing.park_grade(spec)).override_failure_message(
				"%s parks on %.0f %%, under the %.0f %% regulation grade"
				% [variant, BrakeSizing.park_grade(spec) * 100.0, need * 100.0]) \
				.is_greater_equal(need)


func test_the_parking_grade_is_the_lesser_of_the_handbrake_and_the_rear_tyres() -> void:
	# BrakeSizing.park_grade: a handbrake too weak to lock parks on its own arithmetic, either way it
	# faces; past the lock the rear tyres hold the grade and more handbrake moves nothing.
	var shipped: VehicleSpecScript = load("res://src/vehicles/kenney/sedan_spec.tres")
	var spec := shipped.duplicate(true) as VehicleSpecScript
	var gd := spec.ground_drive
	gd.handbrake_torque = 200.0
	var s := 2.0 * 200.0 / gd.axle_radius(true) / (spec.mass * BrakeSizing.G)
	assert_float(BrakeSizing.park_grade(spec)).is_equal_approx(s / sqrt(1.0 - s * s), 0.003)
	gd.handbrake_torque = 5000.0
	var tyre_limited := BrakeSizing.park_grade(spec)
	gd.handbrake_torque = 50000.0
	assert_float(BrakeSizing.park_grade(spec)).is_equal(tyre_limited)
	# 2 x 5000 / r is past m g, so the brake alone would hold a wall: the tyres set the grade.
	assert_float(tyre_limited).override_failure_message(
			"a locking handbrake parked on %.2f, not on its rear tyres" % tyre_limited) \
			.is_between(BrakeSizing.PARK_GRADE_LIGHT, 1.0)


func test_a_park_pawl_outholds_the_driven_tyres() -> void:
	# A steel tooth: the tyre slips before the pawl does.
	var specs := _driven_specs()
	for variant: String in specs:
		var spec: VehicleSpecScript = specs[variant]
		var gd := spec.ground_drive
		if gd.park_pawl_torque <= 0.0:
			continue
		var loads := BrakeSizing.wheel_loads(spec)
		var heaviest := maxf(loads.x if gd.driven_front else 0.0, loads.y if gd.driven_rear else 0.0)
		assert_float(gd.park_pawl_torque).override_failure_message(
				"%s: the pawl slips before its tyre" % variant) \
				.is_greater(BrakeSizing.wheel_grip(spec, heaviest) * gd.drive_radius())


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


func test_every_wheeled_spec_declares_a_fit_and_a_stock_class() -> void:
	# The fitment figures (mu, the load laws, crr) describe the stock class; with no class, or one
	# not made in the body's fit, a fitted class has nothing to be read over.
	var specs := {}
	for variant in VehicleCatalog.VARIANTS:
		if WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			specs[variant] = _spec_of(variant)
	for path: String in TRAILER_SPECS:
		specs[path] = load(path)
	for id: String in specs:
		var gd: GroundDriveSpec = (specs[id] as VehicleSpecScript).ground_drive
		assert_int(gd.tyre_fit).override_failure_message("%s declares no tyre_fit" % id) \
				.is_not_equal(TyreClass.Fit.NONE)
		assert_object(gd.tyre).override_failure_message("%s declares no stock tyre" % id) \
				.is_not_null()
		assert_bool(gd.tyre.fits_body(gd.tyre_fit)).override_failure_message(
				"%s: stock %s is not made in fit %d" % [id, gd.tyre.id, gd.tyre_fit]).is_true()


func test_every_ground_drive_declares_its_tyre_width() -> void:
	# The contact is a cylinder of the tyre's width (`RayWheel`): a body at 0 builds no cast and
	# trips its assert on the first tick.
	var specs := {}
	for variant in VehicleCatalog.VARIANTS:
		specs[variant] = _spec_of(variant)
	for path: String in TRAILER_SPECS:
		specs[path] = load(path)
	for id: String in specs:
		var gd: GroundDriveSpec = (specs[id] as VehicleSpecScript).ground_drive
		if gd == null:
			continue
		for rear in [false, true]:
			assert_float(gd.axle_half_width(rear)).override_failure_message(
					"%s declares no %s tyre_half_width" % [id, "rear" if rear else "front"]) \
					.is_greater(0.0)


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
	# The gear declares no class: it reads the reference tyre, and no swap is offered.
	assert_object(gd.tyre).is_null()
	assert_int(gd.tyre_fit).is_equal(TyreClass.Fit.NONE)


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
	# speed each axle's static load PLUS its share of the wing (`downforce_front`) has to still fit
	# in that axle's travel: a bottomed ray is a chassis dragged through the ground, not more grip.
	# 80 m/s (288 km/h) is what the two open-wheelers actually reach, and nothing else in the
	# catalog carries a wing at all.
	const TOP_SPEED := 80.0
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or spec.ground_drive.downforce_area <= 0.0:
			continue
		var gd := spec.ground_drive
		var loads := BrakeSizing.wheel_loads(spec)
		var share := gd.downforce_front if gd.downforce_front >= 0.0 				else loads.x / (loads.x + loads.y)
		var wing := VehicleMath.aero_downforce(TOP_SPEED, gd.downforce_area)
		for rear in [false, true]:
			var corner := (loads.y + wing * (1.0 - share) / 2.0) if rear 					else (loads.x + wing * share / 2.0)
			var spring_ceiling := (gd.rear_spring_rate() if rear else gd.spring_rate) * gd.rest_length
			var axle := "rear" if rear else "front"
			assert_float(corner).override_failure_message(
					("%s's %s bottoms out at %.0f km/h: %.0f N/corner against %.0f N of spring travel"
					+ " — cut cl, not the springs") % [variant, axle, TOP_SPEED * 3.6, corner,
					spring_ceiling]).is_less(spring_ceiling)
			assert_float(corner).override_failure_message(
					"%s's %s exceeds its own max_suspension_force at speed" % [variant, axle]) \
					.is_less(gd.max_suspension_force)


func test_a_winged_body_stays_front_first_at_any_speed() -> void:
	# The aero balance guard: a wing's split (`downforce_front`) moves each axle's grip with speed,
	# so the limit must stay front-first (understeer, `BalanceModel.limit` margin > 0) from rest to
	# the top end, not just at the static figure the generator reports.
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or spec.ground_drive.downforce_area <= 0.0:
			continue
		for kmh: float in [0.0, 150.0, 280.0]:
			var lim := BalanceModel.limit(BalanceModel.axles(spec, kmh / 3.6))
			assert_float(float(lim["margin"])).override_failure_message(
					"%s goes rear-first at %.0f km/h (margin %+.1f %%)"
					% [variant, kmh, float(lim["margin"]) * 100.0]).is_greater(0.0)


func test_every_body_with_drag_declares_its_aero_centre_and_side_area() -> void:
	# Drag and side force act at `aero_centre`; ZERO is "unset" and falls back to the live COM,
	# which moves under load. A body with a drag area says where its shape's centre of pressure is,
	# and how much side it shows a crosswind (0 would let wind push it only along its nose).
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or spec.ground_drive.drag_area <= 0.0:
			continue
		assert_bool(spec.ground_drive.aero_centre != Vector3.ZERO).override_failure_message(
				"%s declares drag_area %.2f but no aero_centre"
				% [variant, spec.ground_drive.drag_area]).is_true()
		assert_float(spec.ground_drive.side_area).override_failure_message(
				"%s declares drag_area %.2f but no side_area"
				% [variant, spec.ground_drive.drag_area]).is_greater(0.0)


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
		# Once per class the body's fit takes, at its dry-asphalt grip (no surface grips more).
		for cls in TyreCatalog.fitting(spec.ground_drive.tyre_fit):
			var mu_lat: float = spec.ground_drive.mu_lat * _asphalt_ratio(cls, spec.ground_drive)
			# a = v^2/R and R = wheelbase / tan(steer), so the angle mu_lat * g can sustain.
			var grip_deg := rad_to_deg(atan(mu_lat * 9.8 * wheelbase / (v * v)))
			assert_float(floor_deg).override_failure_message(
					"%s on %s: %.1f deg of lock at %.0f m/s against %.1f deg of grip (%.2fx, floor %.2fx)"
					% [variant, cls.id, floor_deg, v, grip_deg, floor_deg / grip_deg,
					STEER_GRIP_MARGIN]).is_greater(grip_deg * STEER_GRIP_MARGIN)


func test_every_inner_wheel_keeps_a_turn_centre_at_full_lock() -> void:
	# `WheelDrive.ackermann_angle` divides by `1 + f x tan(lock) / L`; on the inner wheel that
	# reaches 0 (the wheel at 90 deg) and then flips the steer. The bicycle lock is the largest
	# angle any body asks for, so the check is there.
	for variant in VehicleCatalog.VARIANTS:
		if not WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			continue
		var gd := _spec_of(variant).ground_drive
		var wheelbase := _wheelbase_of(_spec_of(variant))
		var t := tan(deg_to_rad(gd.max_steer_deg))
		for station in gd.wheel_positions:
			if RayWheel.is_rear_z(station.z):
				continue
			var denom: float = 1.0 - gd.ackermann * absf(station.x) * t / wheelbase
			assert_float(denom).override_failure_message(
					"%s: inner wheel past 90 deg at its %.1f deg lock (ackermann %.2f)"
					% [variant, gd.max_steer_deg, gd.ackermann]).is_greater(0.0)


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
				"%s: speed_limit_kmh %f exceeds SPN 74's 250 km/h" % [variant, limit]) \
			.is_less_equal(250.0)
		assert_float(limit).override_failure_message(
				"%s: speed_limit_kmh %f is not a whole km/h — SPN 74 has no fraction" \
				% [variant, limit]).is_equal(float(roundi(limit)))
		if limit > 0.0:
			governed += 1
	# ...and the sweep must actually be sweeping something: ten shipped specs carry a limiter
	# (van, pickup, pickup-flat, ambulance, garbage-truck, firetruck, tractor-kenney, tractor-cvt,
	# semi, conventional), and a regen that dropped the field would otherwise pass this silently.
	assert_int(governed).override_failure_message(
			"no shipped spec declares a speed_limit_kmh any more").is_equal(10)


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
## and SemiTractor (fifth wheel), which between them script exactly these four variants.
const TOWING_VARIANTS := ["tractor-kenney", "tractor-cvt", "semi", "semi-conventional"]


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


# --- the front/rear split -----------------------------------------------------

func test_no_wheel_station_sits_on_the_front_rear_boundary() -> void:
	# `RayWheel.is_rear_z` is the one predicate splitting the wheels by axle (handbrake, retarder,
	# diff lock, MFWD, wheelbase, dust, the driven/steered split). It breaks the z == 0 tie toward
	# FRONT; a spec with a station there would ship a wheel whose axle depends on which caller
	# asked, so no spec may have one.
	var specs: Array[VehicleSpecScript] = []
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec != null and spec.ground_drive != null:
			specs.append(spec)
	for path: String in TRAILER_SPECS:
		specs.append(load(path) as VehicleSpecScript)
	assert_int(specs.size()).is_greater(20)
	for spec in specs:
		for station: Vector3 in spec.ground_drive.wheel_positions:
			assert_bool(absf(station.z) < 1e-6).override_failure_message(
					"a wheel station sits at z == 0 (%s) — it is front to one caller and rear" \
					% str(station) + " to another").is_false()


# --- the declared differentials ------------------------------------------------

func test_every_differential_bias_is_open_or_biasing() -> void:
	# 1.0 is open and a bias ratio below it is no diff anyone builds; `Differential.bias_capacity`
	# would read it as open, so a typo there would ship an open diff with nothing to show for it.
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null:
			continue
		var gd := spec.ground_drive
		for bias: float in [gd.diff_bias_front, gd.diff_bias_rear, gd.centre_diff_bias]:
			assert_float(bias).override_failure_message(
					"%s declares a differential bias under 1 (open)" % variant).is_greater_equal(1.0)


func test_a_rigid_centre_only_on_a_front_axle_the_driver_can_disengage() -> void:
	# A rigid centre forces both axles to one mean speed, but the front runs a wider arc in a turn,
	# so the driveline winds up and scrubs. A tractor's MFWD is real because the driver engages it
	# for field work; a permanently driven front axle geared rigidly to the rear would scrub every
	# road corner.
	for variant in VehicleCatalog.VARIANTS:
		var spec := _spec_of(variant)
		if spec == null or spec.ground_drive == null or not spec.ground_drive.centre_diff_rigid:
			continue
		assert_bool(spec.ground_drive.front_axle_engageable and not spec.ground_drive.driven_front) \
				.override_failure_message("%s: a rigid centre on a front axle that is always driven"
					% variant).is_true()
