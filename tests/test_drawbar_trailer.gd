extends GdUnitTestSuite
## Tractor drawbar and tipping trailer: pinned coupler type, drawbar pin height (0.40 m),
## swing-stop yaw travel against tractor tyres, and no-sink/z-fight invariants.

const Catalog := preload("res://src/vehicles/tractor/implement_catalog.gd")
const DrawbarScript := preload("res://src/vehicles/tractor/drawbar.gd")
const TipperScript := preload("res://src/vehicles/tractor/trailers/farm_tipper.gd")
const TowedBodyScript := preload("res://src/vehicles/base/towed_body.gd")
const SemiScript := preload("res://src/vehicles/truck/semi.gd")
const FifthWheelScript := preload("res://src/vehicles/truck/fifth_wheel.gd")
const ImplementScript := preload("res://src/vehicles/tractor/implement_base.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
const Artic := preload("res://src/vehicles/base/articulation.gd")

const TRAILER := "res://src/vehicles/tractor/trailers/farm_tipper.tscn"
const DRAWBAR := "res://src/vehicles/tractor/drawbar.tscn"

const DELTA := 1.0 / 60.0
const G := 9.8

## The trailer's authored ground plane, in its own frame: the negative of the drawbar pin's height.
## Stated once here and checked against Drawbar.PIN_LOCAL below, so a moved pin fails rather than
## quietly burying or floating the trailer.
const TRAILER_GROUND_Y := -0.40

## Bogie centre and centre of mass, measured off farm_tipper_spec.tres.
const BOGIE_Z := 3.625

## Half the tread width of the tractor's rear tyre. MEASURED, not guessed: three_point_hitch.tscn's
## header records the rear tyre inner faces at |x| = 0.253 against a 0.529 anchor, which is where
## the draft arms' inboard run comes from.
const REAR_TYRE_HALF_WIDTH := 0.276


func _trailer() -> Node3D:
	return (load(TRAILER) as PackedScene).instantiate() as Node3D


func _drawbar() -> Node3D:
	return (load(DRAWBAR) as PackedScene).instantiate() as Node3D


func _tractor() -> Node3D:
	return (load(CatalogScript.scene_of("tractor-kenney")) as PackedScene).instantiate() as Node3D


func _spec_of(node: Node3D) -> VehicleSpec:
	return node.get("spec") as VehicleSpec


# --- the catalog carries two kinds, and says which is which ------------------------------------

func test_the_cycle_carries_the_trailer_and_still_ends_on_detached() -> void:
	# DETACHED stays a real entry and stays LAST, so one press of E from the trailer puts the tractor
	# back to bare and the next picks the spreader up again.
	assert_bool(Catalog.IMPLEMENTS.has(TRAILER)) \
		.override_failure_message("the drawbar trailer is not in the cycle").is_true()
	assert_str(Catalog.IMPLEMENTS[Catalog.IMPLEMENTS.size() - 1]).is_equal(Catalog.DETACHED)
	assert_str(Catalog.next(TRAILER)).is_equal(Catalog.DETACHED)
	assert_str(Catalog.next(Catalog.DETACHED)).is_equal(Catalog.first())


func test_the_tractor_does_not_spawn_towing() -> void:
	# NOT A PREFERENCE — A MEASUREMENT TRAP. tools/measure_vehicles reports its force figures against
	# `spec.mass`, which is the TRACTOR's 4000 kg, so a towed first() would silently have it measuring
	# a 14 t combination against a 4 t number. That is exactly the `-- semi` trap on the truck side,
	# and it cost two sessions there.
	assert_bool(Catalog.is_towed(Catalog.first())) \
		.override_failure_message("first() is towed: measure_vehicles would report a coupled rig") \
		.is_false()
	assert_bool(Catalog.is_attached(Catalog.first())).is_true()


func test_every_towed_entry_is_in_the_cycle_and_is_a_towed_body() -> void:
	assert_int(Catalog.TOWED.size()).is_greater(0)
	for path in Catalog.TOWED:
		assert_bool(Catalog.IMPLEMENTS.has(path)) \
			.override_failure_message("%s is towed but not in the cycle" % path).is_true()
		assert_bool(Catalog.is_towed(path)).is_true()
		var node := (load(path) as PackedScene).instantiate()
		assert_object(node as TowedBody) \
			.override_failure_message("%s is routed to the drawbar but is not a TowedBody" % path) \
			.is_not_null()
		node.free()


func test_the_two_kinds_declare_the_connection_they_are_routed_by() -> void:
	# The routing and the declaration are two statements of one fact, so they are swept against each
	# other. ImplementCatalog.TOWED is data the tractor reads before it instances anything; DRAWBAR
	# and THREE_POINT are what each machine says about itself. Either could rot on its own.
	for path in Catalog.IMPLEMENTS:
		if not Catalog.is_attached(path):
			continue
		var node := (load(path) as PackedScene).instantiate()
		var conn := int(node.call(&"connections"))
		var drawbar := (conn & int(ImplementScript.Connection.DRAWBAR)) != 0
		var three_point := (conn & int(ImplementScript.Connection.THREE_POINT)) != 0
		if Catalog.is_towed(path):
			assert_bool(drawbar) \
				.override_failure_message("%s is towed but declares no DRAWBAR" % path).is_true()
			assert_bool(three_point) \
				.override_failure_message("%s is towed and claims the linkage too" % path).is_false()
			assert_object(node as ImplementBase) \
				.override_failure_message("%s must not be an ImplementBase: an implement is visual"
					% path) \
				.is_null()
		else:
			assert_bool(three_point) \
				.override_failure_message("%s hangs on the linkage but declares no THREE_POINT" % path) \
				.is_true()
			assert_bool(drawbar) \
				.override_failure_message("%s claims the drawbar from the linkage" % path).is_false()
		node.free()


func test_the_trailer_declares_the_same_hose_in_both_vocabularies() -> void:
	# It speaks two languages because two machines read it: TowedBody.Consumer is what a TOWING unit
	# gates set_valve on, ImplementBase.Connection is what a TRACTOR publishes and offers buttons
	# from. One hose, so the two have to agree — pinned here rather than trusted.
	var trailer := _trailer()
	var consumers := int(trailer.call(&"consumers"))
	var conn := int(trailer.call(&"connections"))
	assert_bool((consumers & int(TowedBodyScript.Consumer.HYDRAULIC)) != 0) \
		.override_failure_message("the trailer must declare the hydraulics it is fed by").is_true()
	assert_bool((conn & int(ImplementScript.Connection.SCV)) != 0) \
		.override_failure_message("SCV in one vocabulary and not the other").is_true()
	# NO PTO, and that is the subtraction that tells this apart from the road tipper: a truck has to
	# turn a pump on the trailer, a tractor already carries the pump.
	assert_bool((consumers & int(TowedBodyScript.Consumer.PTO)) != 0) \
		.override_failure_message("a tractor's SCV is the pump — there is no shaft to declare") \
		.is_false()
	assert_bool((conn & int(ImplementScript.Connection.PTO)) != 0).is_false()
	trailer.free()


func test_the_trailer_is_attached_steel_and_bus_silence() -> void:
	# The third state, shipped. All four three-point implements claim an ISOBUS address, so until
	# this machine existed "attached but claiming no address" was only ever describable. It declares
	# no ISOBUS_DATA, so implement_connected reads false and implement_type reads 0 with ten tonnes
	# of steel visibly on the pin — which is also simply what a farm tipping trailer is.
	var trailer := _trailer()
	var conn := int(trailer.call(&"connections"))
	assert_bool((conn & int(ImplementScript.Connection.ISOBUS_DATA)) != 0) \
		.override_failure_message("the trailer claims a bus address it has no ECU for").is_false()
	assert_int(int(trailer.call(&"device_class"))).is_equal(ImplementScript.CLASS_NONE)
	# And nothing of it is in the soil, so draft_force publishes a clean zero rather than a small
	# polite number — the mower's and the spreader's rule.
	assert_bool(trailer.call(&"draft_relevant")).is_false()
	trailer.free()


# --- the coupling datum -------------------------------------------------------------------------

func test_the_pin_marker_and_the_code_agree() -> void:
	# Drawbar reads the marker at runtime, so the constant is only a documented default. Pinning them
	# together is what stops the two drifting into a joint anchored where no steel is.
	var drawbar := _drawbar()
	var pin: Node3D = drawbar.get_node("Pin")
	assert_vector(pin.position) \
		.override_failure_message("the Pin marker and Drawbar.PIN_LOCAL disagree") \
		.is_equal_approx(DrawbarScript.PIN_LOCAL, Vector3.ONE * 1e-4)
	drawbar.free()


func test_the_trailer_is_authored_against_the_pin_and_not_against_a_fifth_wheel() -> void:
	# The one number a copy-paste would get wrong. Every semi-trailer is authored with its ground at
	# y = -1.05, which is a fifth-wheel PLATE height; a drawbar pin is 0.40 m above the road. Author
	# this one against -1.05 and it hangs two thirds of a metre in the air.
	assert_float(TRAILER_GROUND_Y).is_equal_approx(-DrawbarScript.PIN_LOCAL.y, 1e-6)
	assert_float(DrawbarScript.PIN_LOCAL.y).is_not_equal(-FifthWheelScript.KINGPIN_LOCAL.y)
	# The wheel anchors follow from it: the same 0.424 hub height the truck family's 0.36 m wheel
	# uses, measured up from THIS trailer's ground rather than from the semi's.
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	for p in spec.ground_drive.wheel_positions:
		assert_float(p.y - TRAILER_GROUND_Y) \
			.override_failure_message("a wheel anchor sits %.3f m above this trailer's ground"
				% (p.y - TRAILER_GROUND_Y)) \
			.is_equal_approx(0.424, 1e-4)
	trailer.free()


func test_the_bogie_centre_is_measured_off_the_spec() -> void:
	var trailer := _trailer()
	assert_float(trailer.call(&"bogie_z")).is_equal_approx(BOGIE_Z, 1e-6)
	trailer.free()


# --- what it puts on the tractor -----------------------------------------------------------------

func test_a_drawbar_carries_a_NOSE_WEIGHT_and_not_a_share() -> void:
	# The contrast with the fifth wheel, as a number. A semi-trailer puts 27 % of itself on the
	# plate and that load IS the 4x2's traction budget; a tandem drawbar trailer puts a tenth or so
	# on the pin, so the tractor gets correspondingly less help gripping. A drawbar share that
	# drifted up to the semi's would quietly turn this into a semi-trailer on a shorter hitch.
	var trailer := _trailer()
	var share: float = trailer.call(&"kingpin_share")
	assert_float(share) \
		.override_failure_message("%.1f %% on the drawbar is a fifth-wheel share, not a nose weight"
			% (share * 100.0)) \
		.is_between(0.08, 0.15)
	trailer.free()


func test_the_combination_holds_the_verified_mass_ratio() -> void:
	# 3 : 1 is what the semi verified and re-tuned around; past it a rig is a re-tune, not a free
	# number. The tractor is 4 t, so this is the ceiling that matters here.
	var tractor := _tractor()
	var tractor_kg := _spec_of(tractor).mass
	tractor.free()
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	assert_float(spec.mass / tractor_kg) \
		.override_failure_message("%.2f : 1 against the tractor, past the verified 3 : 1"
			% (spec.mass / tractor_kg)) \
		.is_less_equal(3.0)
	trailer.free()


func test_the_trailer_rides_on_its_springs_and_not_on_its_stops() -> void:
	# The does-not-sink invariant. The spring rate is sized off the load THIS bogie carries, not
	# copied from a semi-trailer, so it lands at the same fraction of travel the whole trailer family
	# parks at despite carrying a third of the mass on half the axles.
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	var bogie_kg: float = spec.mass * (1.0 - float(trailer.call(&"kingpin_share")))
	var per_wheel := bogie_kg * G / float(spec.ground_drive.wheel_positions.size())
	var used := (per_wheel / spec.ground_drive.spring_rate) / spec.ground_drive.rest_length
	assert_float(used) \
		.override_failure_message("it sits at %.0f%% of its suspension travel at rest" % (used * 100.0)) \
		.is_between(0.25, 0.5)
	assert_float(per_wheel) \
		.override_failure_message("it leans on its suspension force cap") \
		.is_less(spec.ground_drive.max_suspension_force)
	trailer.free()


func test_the_brake_is_inside_its_own_tyres_and_apportioned_to_the_tractors() -> void:
	# Two rules at once, both of them the trailer family's. A trailer must not brake harder per tonne
	# than the machine pulling it (that is how a rig jackknifes under braking), and it must not ask
	# for more than its own tyres can hand back (past that the wheel just locks).
	var tractor := _tractor()
	var t_spec := _spec_of(tractor)
	var tractor_per_wheel := t_spec.mass * G / float(t_spec.ground_drive.wheel_positions.size())
	var tractor_brake := t_spec.ground_drive.brake_torque
	tractor.free()

	var trailer := _trailer()
	var spec := _spec_of(trailer)
	var bogie_kg: float = spec.mass * (1.0 - float(trailer.call(&"kingpin_share")))
	var per_wheel := bogie_kg * G / float(spec.ground_drive.wheel_positions.size())
	var apportioned := tractor_brake * per_wheel / tractor_per_wheel
	assert_float(spec.ground_drive.brake_torque) \
		.override_failure_message("%.0f Nm is not the load-apportioned %.0f Nm"
			% [spec.ground_drive.brake_torque, apportioned]) \
		.is_equal_approx(apportioned, apportioned * 0.05)
	assert_float(spec.ground_drive.brake_torque) \
		.override_failure_message("full pedal asks for more than the tyre can give") \
		.is_less(spec.ground_drive.mu_long * per_wheel * spec.ground_drive.wheel_radius)
	# The spring parking brake is a flat quarter of its own service brake, like every trailer here.
	assert_float(spec.ground_drive.handbrake_torque) \
		.is_equal_approx(spec.ground_drive.brake_torque * 0.25, spec.ground_drive.brake_torque * 0.02)
	trailer.free()


func test_the_trailer_declares_its_own_road_resistance() -> void:
	# Nothing rides an engine default, and a towed body is the one that proved why: it is not a
	# BaseVehicle, so it falls through every guard. Both terms, and a MARGINAL drag area rather than
	# a silhouette — set to the silhouette, a coupled rig is over-braked by its own aero.
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	assert_float(spec.ground_drive.drag_area).is_between(0.2, 1.0)
	assert_float(spec.ground_drive.rolling_resistance).is_greater(0.0)
	trailer.free()


# --- the joint: where a drawbar differs from a fifth wheel -----------------------------------

func test_the_drawbar_is_free_in_roll_where_the_fifth_wheel_is_not() -> void:
	# The one number that makes a drawbar a drawbar. A fifth wheel is a flat plate under a locked
	# kingpin and holds the trailer's roll to the tractor's within a hair; an eye on a pin lets the
	# trailer roll on its own wheels, so a rut under one of them does not lever the tractor over.
	assert_float(DrawbarScript.ROLL_LIMIT_DEG) \
		.override_failure_message("a drawbar that holds roll like a plate is a fifth wheel") \
		.is_greater(FifthWheelScript.ROLL_LIMIT_DEG * 5.0)
	# Wide, not unlimited: an unbounded axis on a 6DOF joint has nothing to catch a body that has
	# already gone past upright.
	assert_float(DrawbarScript.ROLL_LIMIT_DEG).is_less(90.0)


func test_the_pitch_stop_covers_a_grade_rather_than_bounding_one() -> void:
	# On its stop the two bodies are rigid, so a level trailer at a break of slope levers the
	# climbing tractor's drive axle off the ground and the rig stops gripping — diagnosed as neither
	# power nor grip when it cost the semi a session at +-8 deg. A tractor climbs steeper than an
	# artic and swings this about a much shorter drawbar, so it needs at least the semi's travel.
	assert_float(DrawbarScript.PITCH_LIMIT_DEG).is_greater_equal(FifthWheelScript.PITCH_LIMIT_DEG)


func test_the_swing_stop_is_this_rigs_own_and_not_the_semis() -> void:
	# Articulation.JACKKNIFE_MAX_DEG is a labelled model of a SEMI-TRAILER against a CAB. Reusing it
	# here would be borrowing another vehicle's steel; the sweep below is what actually sizes this.
	assert_float(DrawbarScript.SWING_MAX_DEG).is_not_equal(Artic.JACKKNIFE_MAX_DEG)
	assert_float(DrawbarScript.SWING_MAX_DEG).is_between(45.0, 120.0)


## Every axis-aligned or rotated BoxMesh corner in `node`, in scene space.
func _box_corners(node: Node, xf: Transform3D, out: Array[Vector3]) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var here := xf * n3.transform
		var mesh_node := n3 as MeshInstance3D
		if mesh_node != null and mesh_node.mesh is BoxMesh:
			var half: Vector3 = (mesh_node.mesh as BoxMesh).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						out.append(here * Vector3(sx * half.x, sy * half.y, sz * half.z))
		_box_corners(n3, here, out)


## The volumes on the tractor a swinging trailer must not reach: its two authored collision boxes
## (which stand in for the body) and its two rear tyres. Read off the shipped scene and spec rather
## than restated, so a re-bodied tractor re-sizes this test instead of outliving it.
func _tractor_volumes() -> Array[AABB]:
	var tractor := _tractor()
	var spec := _spec_of(tractor)
	var out: Array[AABB] = []
	# Recursive: the tractor's two boxes are direct children today, but a shape nested one level
	# down would otherwise be dropped from the sweep silently, which is the failure this test exists
	# to make impossible.
	for shape: CollisionShape3D in tractor.find_children("*", "CollisionShape3D", true, false):
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		out.append(AABB(shape.position - box.size * 0.5, box.size))
	var radius := spec.ground_drive.wheel_visual_radius_rear
	for p in spec.ground_drive.wheel_positions:
		if p.z <= 0.0:
			continue  # front axle; a trailer behind the pin can never reach it
		var half := Vector3(REAR_TYRE_HALF_WIDTH, radius, radius)
		var centre := Vector3(p.x, radius, p.z)
		out.append(AABB(centre - half, half * 2.0))
	tractor.free()
	assert_int(out.size()).override_failure_message("no tractor volumes to sweep against") \
		.is_greater(3)
	return out


func test_the_trailer_clears_the_tractor_through_its_whole_swing() -> void:
	# SWEPT, NOT ASSERTED. The stop is a labelled model of the trailer's front corners against the
	# tractor's rear tyres — it cannot be left to the collision system, because the joint excludes
	# the two bodies from each other by design (their steel deliberately shares space at the pin).
	# So the geometry has to be checked here, over every corner and the whole travel, rather than
	# discovered by folding the rig in the game.
	var volumes := _tractor_volumes()
	var trailer := _trailer()
	var corners: Array[Vector3] = []
	_box_corners(trailer, Transform3D.IDENTITY, corners)
	trailer.free()
	assert_int(corners.size()).override_failure_message("the trailer has no boxes").is_greater(50)

	const STEPS := 24
	var clashes := PackedStringArray()
	for step in range(-STEPS, STEPS + 1):
		var phi := deg_to_rad(DrawbarScript.SWING_MAX_DEG) * float(step) / float(STEPS)
		var basis := Basis(Vector3.UP, phi)
		for c in corners:
			var p: Vector3 = DrawbarScript.PIN_LOCAL + basis * c
			for v in volumes:
				if v.has_point(p):
					clashes.append("%.0f deg: (%.2f, %.2f, %.2f)"
							% [rad_to_deg(phi), p.x, p.y, p.z])
					break
	assert_int(clashes.size()) \
		.override_failure_message("the trailer reaches into the tractor at %d sampled corner(s): %s"
			% [clashes.size(), ", ".join(clashes.slice(0, 6))]) \
		.is_equal(0)


func test_the_drawbar_itself_clears_the_linkage_and_the_tyres() -> void:
	# The bar is bolted under the hitch housing and runs aft on the centreline under the PTO stub.
	# It has to miss BOTH the rear tyres and the swing of the lower links, or a tractor with an
	# implement on cannot lower it. Checked against the tyres here; the linkage clearance is
	# geometry the hitch scene's own header records (|x| 0.19 inboard, ball ends at |x| 0.37).
	var drawbar := _drawbar()
	var corners: Array[Vector3] = []
	_box_corners(drawbar, Transform3D.IDENTITY, corners)
	drawbar.free()
	assert_int(corners.size()).override_failure_message("the drawbar has no boxes").is_greater(8)
	for c in corners:
		assert_float(absf(c.x)) \
			.override_failure_message("the drawbar reaches out to |x| %.3f, into the tyres" % absf(c.x)) \
			.is_less(0.25)
		assert_float(c.y) \
			.override_failure_message("part of the drawbar is underground at y %.3f" % c.y) \
			.is_greater(0.0)


# --- the tipping body -----------------------------------------------------------------------

func test_the_body_rises_and_lowers_in_its_stated_time() -> void:
	# NO PTO GATE, and that is the difference from the road tipper rather than an omission: the pump
	# is the tractor's, so flow alone moves it. What reaches tick_body has already been through the
	# tractor's `running` gate and its raise interlock.
	var trailer := _trailer()
	trailer.call(&"set_valve", 1.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		trailer.call(&"tick_body", DELTA)
	assert_float(trailer.call(&"body_pos01")).is_equal_approx(1.0, 1e-6)
	assert_float(TipperScript.TIP_TRAVEL_S) \
		.override_failure_message("a body that snaps up makes the interlock invisible").is_greater(2.0)
	trailer.call(&"set_valve", 0.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		trailer.call(&"tick_body", DELTA)
	assert_float(trailer.call(&"body_pos01")).is_equal_approx(0.0, 1e-6)
	trailer.free()


func test_tipping_walks_the_load_off_the_drawbar_and_onto_the_bogie() -> void:
	# The load shift is a consequence, never a term. set_load_offset_z moves a real centre of mass,
	# so the bogie's springs genuinely carry more and the tractor genuinely carries less. Nothing is
	# added to any signal — the draft-force discipline.
	var trailer := _trailer()
	var parked: float = trailer.call(&"live_kingpin_share")
	assert_float(parked).is_equal_approx(float(trailer.call(&"kingpin_share")), 1e-6)
	trailer.call(&"set_valve", 1.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		trailer.call(&"tick_body", DELTA)
	var tipped: float = trailer.call(&"live_kingpin_share")
	assert_float(tipped) \
		.override_failure_message("tipping did not move any weight off the pin").is_less(parked)
	assert_float(trailer.call(&"load_shift_z")) \
		.is_equal_approx(TipperScript.TIP_COM_SHIFT_Z, 1e-6)
	# ...and it still presses on the pin. This is the one the road tipper's fraction gets wrong on a
	# drawbar: a plate starts with a quarter of the trailer's weight and a pin with a tenth, so a
	# load walked as far would take the nose weight past zero and leave the trailer standing on its
	# bogie alone. Measured by driving at a 0.55 m shift it read exactly 0.000; 0.33 keeps ~3 %.
	assert_float(tipped) \
		.override_failure_message("a fully tipped trailer carries nothing at all on the drawbar") \
		.is_greater(0.01)
	# A respawn brings the body AND its load home: leaving a shifted load behind would make respawn
	# a way to keep weight where the driver never put it.
	trailer.call(&"reset_body")
	trailer.call(&"set_load_offset_z", 0.0)
	assert_float(trailer.call(&"body_pos01")).is_equal(0.0)
	assert_float(trailer.call(&"live_kingpin_share")).is_equal_approx(parked, 1e-6)
	trailer.free()


func test_the_raise_interlock_wants_the_brake_set_and_the_rig_stopped() -> void:
	# The interlock is chassis state and TractorVehicle is what evaluates it; this pins the rule it
	# evaluates. Deliberately STRICT: a raised body is four metres of leverage on a trailer that is
	# about to be nearly two metres tall to begin with.
	assert_bool(TowedBodyScript.body_raise_allowed(0.0, 1.0)).is_true()
	assert_bool(TowedBodyScript.body_raise_allowed(3.0, 1.0)) \
		.override_failure_message("it would tip while rolling").is_false()
	assert_bool(TowedBodyScript.body_raise_allowed(0.0, 0.0)) \
		.override_failure_message("it would tip with the brake off").is_false()


func test_the_raised_collision_is_the_LOWERED_box_swept_about_the_real_hinge() -> void:
	# The second pose is not an independent guess at the geometry: it is the SAME BoxShape3D, placed
	# exactly where a full tip about TipBody's origin puts it. Re-author the body, move the hinge or
	# change TIP_MAX_DEG and this fails, instead of leaving a stale box floating over the trailer
	# where nothing would ever notice.
	#
	# It is not optional either: the interlock refuses the RAISE direction only, so driving away with
	# the body up is a pose the world has to be able to hit.
	var trailer := _trailer()
	var hinge: Node3D = trailer.get_node("TipBody")
	var down: CollisionShape3D = trailer.get_node("CollisionTipBody")
	var up: CollisionShape3D = trailer.get_node("CollisionTipBodyRaised")
	assert_object(up.shape) \
		.override_failure_message("the two poses must be one box, or they can disagree") \
		.is_same(down.shape)
	var to_hinge := Transform3D(Basis.IDENTITY, hinge.position)
	var swept := to_hinge * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(TipperScript.TIP_MAX_DEG))) \
			* to_hinge.affine_inverse() * down.transform
	assert_vector(up.transform.origin) \
		.override_failure_message("the raised box is not where a full tip puts the lowered one") \
		.is_equal_approx(swept.origin, Vector3.ONE * 2e-4)
	assert_float(up.transform.basis.get_euler().x) \
		.override_failure_message("the raised box is not tipped through TIP_MAX_DEG") \
		.is_equal_approx(swept.basis.get_euler().x, 1e-4)
	assert_bool(down.disabled) \
		.override_failure_message("the parked pose must be the live one").is_false()
	assert_bool(up.disabled) \
		.override_failure_message("the raised pose must spawn disabled").is_true()
	trailer.free()


func test_the_collision_swaps_ONCE_a_tip_and_will_not_dither_on_the_threshold() -> void:
	# Two thresholds rather than one, so a spool parked on the boundary cannot rebuild the compound
	# sixty times a second on the one body that is also writing its own centre of mass.
	assert_float(TipperScript.RAISED_ON) \
		.override_failure_message("the hysteresis is inverted or absent") \
		.is_greater(TipperScript.RAISED_OFF)
	assert_float(TipperScript.RAISED_OFF).is_greater(0.0)
	assert_float(TipperScript.RAISED_ON).is_less(1.0)


# --- the authored scenes hold their own invariants ---------------------------------------------

func test_the_wheel_visuals_match_the_specs_anchors() -> void:
	# A mismatch is otherwise an invisible wheel: TowedBody pairs them by INDEX.
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	var wheels: Node3D = trailer.get_node("Wheels")
	assert_int(wheels.get_child_count()) \
		.override_failure_message("%d wheel visuals for %d spec anchors"
			% [wheels.get_child_count(), spec.ground_drive.wheel_positions.size()]) \
		.is_equal(spec.ground_drive.wheel_positions.size())
	trailer.free()


func test_the_trailer_declares_lamps_that_resolve_in_its_own_scene() -> void:
	# LampSet tolerates a missing node SILENTLY, which is a dark trailer with nothing to say so. A
	# coupled combination lights at both ends off the tractor's own bits — no second signal, no side
	# channel, no blink timer.
	var trailer := _trailer()
	var spec := _spec_of(trailer)
	var groups: Array[Array] = [
		spec.brake_lamp_paths, spec.turn_left_paths, spec.turn_right_paths, spec.steady_lamp_paths]
	var total := 0
	for group in groups:
		for path: NodePath in group:
			total += 1
			assert_object(trailer.get_node_or_null(path) as MeshInstance3D) \
				.override_failure_message("lamp path '%s' resolves to nothing" % path) \
				.is_not_null()
	assert_int(total).override_failure_message("the trailer declares no lamps at all").is_greater(4)
	# No headlamps and no beam on a trailer: `lights` only ever picks the rear tier and the markers.
	assert_int(spec.head_lamp_paths.size()).is_equal(0)
	trailer.free()


func test_the_trailer_stands_on_RAYCASTS_so_a_body_contact_really_does_mean_stuck() -> void:
	# The fit check's whole assumption. A CollisionShape on a wheel would have the trailer touching
	# the road in normal towing, and the tractor would unhitch it a few ticks after every coupling.
	var trailer := _trailer()
	var wheels: Node3D = trailer.get_node("Wheels")
	assert_int(wheels.find_children("*", "CollisionShape3D", true, false).size()) \
		.override_failure_message("a wheel carries collision: the rig would unhitch itself") \
		.is_equal(0)
	trailer.free()


func test_the_authored_collision_clears_the_road() -> void:
	# Per-SHAPE rather than one bounding box: the shapes already clear the ground, so a modest slope
	# under the bogie is not a collision. One box around the whole trailer would swallow that
	# clearance and refuse every hill.
	var trailer := _trailer()
	var probes: Array[Dictionary] = trailer.call(&"collision_probes")
	assert_int(probes.size()) \
		.override_failure_message("no collision at all — the fit check would never fire") \
		.is_greater(2)
	for probe in probes:
		var box := probe["shape"] as BoxShape3D
		if box == null:
			continue
		var xf: Transform3D = probe["xf"]
		var lowest := INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p: Vector3 = xf * (box.size * 0.5 * Vector3(sx, sy, sz))
					lowest = minf(lowest, p.y)
		assert_float(lowest) \
			.override_failure_message("a collision box reaches %.3f m below this trailer's ground"
				% (TRAILER_GROUND_Y - lowest)) \
			.is_greater(TRAILER_GROUND_Y)
	trailer.free()


## Every axis-aligned BoxMesh in the scene as {name, min, max} in scene space, walked recursively.
## Rotated boxes are skipped: they have no axis plane to share with anything.
func _axis_boxes(node: Node, xf: Transform3D, out: Array) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var here := xf * n3.transform
		var mesh_node := n3 as MeshInstance3D
		if mesh_node != null and mesh_node.mesh is BoxMesh:
			var b := here.basis
			if absf(b.x.dot(Vector3.RIGHT)) > 0.999 and absf(b.y.dot(Vector3.UP)) > 0.999 \
					and absf(b.z.dot(Vector3.BACK)) > 0.999:
				var half: Vector3 = (mesh_node.mesh as BoxMesh).size * 0.5
				out.append({
					"name": String(n3.name),
					"min": here.origin - half,
					"max": here.origin + half,
				})
		_axis_boxes(n3, here, out)


func _axis_overlap(a: Dictionary, b: Dictionary, axis: int) -> float:
	var lo: float = maxf((a["min"] as Vector3)[axis], (b["min"] as Vector3)[axis])
	var hi: float = minf((a["max"] as Vector3)[axis], (b["max"] as Vector3)[axis])
	return hi - lo


func test_no_two_boxes_share_a_face_plane_and_a_facing() -> void:
	# The z-fight rule, asserted instead of remembered, on the two new scenes. Two boxes that TOUCH
	# on a face plane flicker; two that OVERLAP never do, and a pair whose faces point AT each other
	# is settled by back-face culling. So what is forbidden is a shared plane with a shared FACING
	# over a patch big enough to see. It shipped as a real bug on the truck side — 56 such pairs in
	# the box trailer alone — and hand-checking a fifty-part scene is not a review anyone can do.
	const EPS := 0.0015
	const MIN_PATCH := 0.02
	for path in [TRAILER, DRAWBAR]:
		var scene := (load(path) as PackedScene).instantiate()
		var boxes: Array = []
		_axis_boxes(scene, Transform3D.IDENTITY, boxes)
		assert_int(boxes.size()) \
			.override_failure_message("%s has too few boxes to sweep" % path) \
			.is_greater_equal(4)
		var clashes := PackedStringArray()
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a: Dictionary = boxes[i]
				var b: Dictionary = boxes[j]
				for axis in 3:
					var o1 := _axis_overlap(a, b, (axis + 1) % 3)
					var o2 := _axis_overlap(a, b, (axis + 2) % 3)
					if o1 < MIN_PATCH or o2 < MIN_PATCH:
						continue
					for side in ["min", "max"]:
						var pa: float = (a[side] as Vector3)[axis]
						var pb: float = (b[side] as Vector3)[axis]
						if absf(pa - pb) <= EPS:
							clashes.append("%s/%s %s-%s @ %.3f (%.2f x %.2f)" % [
									a["name"], b["name"], "XYZ"[axis], side, pa, o1, o2])
		assert_int(clashes.size()) \
			.override_failure_message("%s: %d coplanar same-facing pair(s): %s"
				% [path.get_file(), clashes.size(), ", ".join(clashes)]) \
			.is_equal(0)
		scene.free()


func test_the_drawbar_carries_no_collision_and_no_body_of_its_own() -> void:
	# It is tractor ANATOMY on the chassis body, exactly like ThreePointHitch: the joint Drawbar
	# builds is what holds a trailer on, and a collider here would fight the trailer for the space
	# they deliberately share at the pin.
	var drawbar := _drawbar()
	assert_int(drawbar.find_children("*", "CollisionShape3D", true, false).size()) \
		.override_failure_message("the drawbar has collision of its own").is_equal(0)
	assert_int(drawbar.find_children("*", "PhysicsBody3D", true, false).size()).is_equal(0)
	drawbar.free()


func test_the_tractor_scene_carries_the_drawbar_beside_the_linkage() -> void:
	# BOTH ends are tractor anatomy and both are hand-added children of the chassis ROOT — never
	# under Model, which gen_kenney_vehicles.gd rebuilds from the GLB on every run while still
	# printing success. The hitch was silently dropped by a regen once already.
	var tractor := _tractor()
	var drawbar := tractor.get_node_or_null("Drawbar")
	assert_object(drawbar) \
		.override_failure_message("the tractor has no drawbar: E would cycle to a trailer that is " \
			+ "remembered and never hitched") \
		.is_not_null()
	assert_object(tractor.get_node_or_null("ThreePointHitch")).is_not_null()
	assert_object(tractor.get_node_or_null("Model/Drawbar")) \
		.override_failure_message("the drawbar is under Model and the next regen will wipe it") \
		.is_null()
	tractor.free()


func test_a_towed_body_that_declares_nothing_reads_zero_instead_of_erroring() -> void:
	# `ImplementBase` defines connections() / device_class(), so every implement answers by
	# inheritance — but `TowedBody` defines NEITHER (its own vocabulary is Consumer, and teaching the
	# truck's base class the tractor's would invert the layering). Only FarmTipper adds them.
	#
	# So the shape this guards is a real one: a second towed entry written the way flatbed.tscn is,
	# with towed_body.gd as its script and no subclass at all. Unguarded, Object.call would report a
	# missing method SIXTY TIMES A SECOND while the signals read a silent zero — an error log as the
	# only symptom. The loud, nameable version of that complaint belongs at hitch time, once.
	var bare: TowedBody = TowedBody.new()
	assert_bool(bare.has_method(&"connections")) \
		.override_failure_message("TowedBody grew connections() — this test is now moot") \
		.is_false()
	# _drawbar is resolved in _ready, which needs a tree — set it and its trailer by hand, for the
	# same reason the rest of this suite runs without a physics body.
	var drawbar: Node3D = DrawbarScript.new()
	drawbar.set("trailer", bare)
	var tractor := _tractor()
	tractor.set("_drawbar", drawbar)
	var controls: Dictionary = tractor.call("attachment_controls")
	assert_bool(controls["pto"]).is_false()
	assert_bool(controls["scv"]).is_false()
	# The linkage is tractor anatomy and is unaffected by anything hanging off the drawbar.
	assert_bool(controls["lift"]).is_true()
	tractor.free()
	drawbar.free()
	bare.free()


func test_changing_the_attachment_restarts_the_interlock_notice() -> void:
	# The tip refusal fires on a CHANGE of spool position, and the notice is the ONLY feedback that
	# control has. Drop a trailer with the spool part way open and hitch it again and the stale
	# position would otherwise still be latched: the first refused press matches it, reads as "no
	# edge", and says nothing — indistinguishable from the key being dead.
	#
	# The latch lives on the COUPLING now (TowHost), restarted by couple() and uncouple() — the two
	# moments what is on the back changes — so the drawbar is set by hand here for the same reason
	# line 701 does it: _drawbar is resolved in _ready, which needs a tree.
	var tractor := _tractor()
	var drawbar: Node3D = DrawbarScript.new()
	tractor.set("_drawbar", drawbar)
	drawbar.set("_last_tip_cmd", 0.6)
	tractor.call("_set_implement", Catalog.DETACHED)
	assert_float(drawbar.get("_last_tip_cmd")) \
		.override_failure_message("the notice latch survived the attachment changing") \
		.is_less(0.0)
	tractor.free()
	drawbar.free()


func test_the_shell_hooks_are_duck_typed_and_the_tractor_answers_them() -> void:
	# The shell, VehicleCatalog and the selector all reach the drawbar through hooks they already
	# call — nothing outside the tractor learns that a trailer exists.
	var tractor := _tractor()
	for hook in ["cycle_implement", "attachment_ids", "current_attachment", "set_attachment",
			"attachment_controls", "set_display_frozen"]:
		assert_bool(tractor.has_method(hook)) \
			.override_failure_message("the tractor no longer answers '%s'" % hook).is_true()
	tractor.free()
