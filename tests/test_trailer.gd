extends GdUnitTestSuite
## Fifth-wheel geometry and the trailer's authored numbers. Pure statics plus scene/spec reads, no
## physics body.
##
## What is pinned: the kinematic follower (Articulation.jackknife_step / pose_at_angle), where
## forward straightens and reverse runs away; the does-not-sink invariant, which fails if a
## trailer's mass is raised as a free number; scene-vs-code agreement on the kingpin; the ISO 11992
## signals, read out of the sim rather than described; and the per-trailer masses, since mass is the
## only thing on the wire that tells the four trailers apart.

const Artic := preload("res://src/vehicles/base/articulation.gd")
const Catalog := preload("res://src/vehicles/truck/trailer_catalog.gd")
const SemiScript := preload("res://src/vehicles/truck/semi.gd")
const FifthWheelScript := preload("res://src/vehicles/truck/fifth_wheel.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
const TruckT := preload("res://src/vehicles/truck/truck_telemetry.gd")
const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const TowedBodyScript := preload("res://src/vehicles/base/towed_body.gd")
const TipperScript := preload("res://src/vehicles/truck/trailers/tipper.gd")
const TankerScript := preload("res://src/vehicles/truck/trailers/tanker.gd")

const DELTA := 1.0 / 60.0
const G := 9.8

## The trailer family's shared bogie geometry and centre of mass. Every trailer runs the same
## tri-axle bogie and they all sit at the same COM_Z.
const BOGIE_Z := 5.45
const COM_Z := 3.98

const FLATBED := "res://src/vehicles/truck/trailers/flatbed.tscn"
const BOX := "res://src/vehicles/truck/trailers/box.tscn"
const TIPPER := "res://src/vehicles/truck/trailers/tipper.tscn"
const TANKER := "res://src/vehicles/truck/trailers/tanker.tscn"


func _flatbed() -> Node3D:
	return _trailer(FLATBED)


func _trailer(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


func _semi() -> Node3D:
	return (load(CatalogScript.scene_of("semi")) as PackedScene).instantiate() as Node3D


## Yaw-only pose helper: the sign convention everywhere here is "+ = to the tractor's right", and a
## body's forward is -Z, so a RIGHT yaw is a NEGATIVE rotation about world up.
func _yawed(right_rad: float, origin := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -right_rad), origin)


func _contract() -> ContractScript.ContractData:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	return ContractScript.ContractData.parse(file.get_as_text())


## A flatbed with its RayWheels built by hand, one per spec anchor, so the running gear can be
## posed without a physics tree. _ready does exactly this when it is really spawned.
func _wheeled_flatbed() -> Node3D:
	var trailer := _flatbed()
	var spec: VehicleSpec = trailer.get("spec")
	var wheels: Array[RayWheel] = []
	var corner_mass: float = spec.mass / maxf(1.0, spec.ground_drive.wheel_positions.size())
	for p in spec.ground_drive.wheel_positions:
		wheels.append(RayWheel.new(p, false, false, null, corner_mass))
	trailer.set("wheels", wheels)
	return trailer


# --- articulation angle -------------------------------------------------------

func test_a_straight_rig_reads_zero_articulation() -> void:
	var t := _yawed(0.0, Vector3(12.0, 0.0, -4.0))
	assert_float(Artic.articulation_angle(t, t)).is_equal_approx(0.0, 1e-6)


func test_the_sign_says_which_way_the_trailer_points() -> void:
	var tractor := _yawed(0.0)
	# Trailer yawed to the tractor's right -> positive, and to its left -> negative.
	assert_float(Artic.articulation_angle(tractor, _yawed(0.4))).is_equal_approx(0.4, 1e-5)
	assert_float(Artic.articulation_angle(tractor, _yawed(-0.4))).is_equal_approx(-0.4, 1e-5)
	# It is the RELATIVE angle: turn the whole rig and nothing changes.
	var turned := _yawed(1.1)
	assert_float(Artic.articulation_angle(turned, _yawed(1.5))).is_equal_approx(0.4, 1e-5)


func test_the_angle_wraps_instead_of_running_past_pi() -> void:
	# A rig folded past a right angle must not report -350 deg as +10.
	var folded := Artic.articulation_angle(_yawed(0.0), _yawed(TAU - 0.3))
	assert_float(folded).is_equal_approx(-0.3, 1e-5)
	assert_float(absf(Artic.articulation_angle(_yawed(0.0), _yawed(PI + 0.2)))) \
			.is_less_equal(PI)


func test_a_ramp_is_not_an_articulation() -> void:
	# Flattened onto the horizontal plane, so a pitched tractor reads 0 rather than "jackknifed".
	var pitched := Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3.ZERO)
	assert_float(Artic.articulation_angle(pitched, pitched)).is_equal_approx(0.0, 1e-6)
	assert_float(Artic.articulation_angle(pitched, Transform3D(Basis.IDENTITY, Vector3.ZERO))) \
			.is_equal_approx(0.0, 1e-5)


# --- the coupled pose respawn uses --------------------------------------------

func test_the_coupled_pose_puts_the_trailer_kingpin_on_the_plate() -> void:
	# The trailer's ORIGIN is its kingpin (it is authored that way), so the coupled pose's origin
	# must be the tractor's kingpin point exactly — this is the whole coupling geometry.
	var kingpin := FifthWheelScript.KINGPIN_LOCAL
	for yaw in [0.0, 0.8, -2.5]:
		var tractor := _yawed(yaw, Vector3(5.0, 1.5, -9.0))
		var pose := Artic.coupled_pose(tractor, kingpin)
		assert_vector(pose.origin).is_equal_approx(tractor * kingpin, Vector3.ONE * 1e-5)
		assert_float(Artic.articulation_angle(tractor, pose)).is_equal_approx(0.0, 1e-6)


func test_the_coupled_pose_carries_the_tractors_attitude() -> void:
	# On a slope the trailer inherits the whole basis, pitch included (its own RayWheels then settle
	# it, and the joint's pitch limit is what allows the difference).
	var tractor := Transform3D(Basis(Vector3.RIGHT, 0.15) * Basis(Vector3.UP, 0.6), Vector3(0, 3, 0))
	var pose := Artic.coupled_pose(tractor, FifthWheelScript.KINGPIN_LOCAL)
	assert_vector(-pose.basis.z).is_equal_approx(-tractor.basis.z, Vector3.ONE * 1e-6)


# --- the fallback: pose + jackknife integration --------------------------------

func test_the_fallback_pose_round_trips_through_the_angle_it_was_given() -> void:
	# pose_at_angle and articulation_angle are inverses, which is what makes the fallback safe to take:
	# the pose reports back the angle the solve asked for, and stays hung off the kingpin.
	var tractor := _yawed(0.7, Vector3(-3.0, 0.0, 11.0))
	var kingpin := FifthWheelScript.KINGPIN_LOCAL
	for phi in [0.0, 0.35, -0.9, 1.2]:
		var pose := Artic.pose_at_angle(tractor, kingpin, phi, BOGIE_Z)
		assert_float(Artic.articulation_angle(tractor, pose)) \
			.override_failure_message("fallback pose lost the angle %f" % phi) \
			.is_equal_approx(phi, 1e-5)
		assert_vector(pose.origin).is_equal_approx(tractor * kingpin, Vector3.ONE * 1e-5)


func test_the_fallback_pose_survives_a_pitched_tractor() -> void:
	# The trailer is posed level (its yaw is the solved variable); a tractor on a ramp must not
	# tilt or NaN the follower's basis.
	var tractor := Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 2, 0))
	var pose := Artic.pose_at_angle(tractor, FifthWheelScript.KINGPIN_LOCAL, 0.5, BOGIE_Z)
	assert_float(pose.basis.determinant()).is_equal_approx(1.0, 1e-5)
	assert_float(pose.basis.y.dot(Vector3.UP)).is_equal_approx(1.0, 1e-5)


func test_pulling_forward_straightens_the_rig() -> void:
	# The negative-feedback half, and why towing a trailer forward is easy. The decay is exponential
	# with a time constant of bogie_z / v (0.68 s at 8 m/s), so what is pinned is the shape — every
	# step shrinks the angle monotonically toward zero — rather than a value after N ticks.
	var phi := 0.5
	for _i in 120:
		var next := Artic.jackknife_step(phi, 8.0, 0.0, DELTA, BOGIE_Z, 0.2)
		assert_float(next).is_between(0.0, phi)
		phi = next
	assert_float(phi).is_less(0.5 * 0.1)  # under a tenth of it after 2 s
	# Symmetric: the same from the other side.
	var neg := -0.5
	for _i in 120:
		var next := Artic.jackknife_step(neg, 8.0, 0.0, DELTA, BOGIE_Z, 0.2)
		assert_float(next).is_between(neg, 0.0)
		neg = next
	assert_float(neg).is_greater(-0.5 * 0.1)


func test_reversing_runs_the_angle_away_and_that_is_the_jackknife() -> void:
	# The positive-feedback half. A tiny angle grows under reverse instead of decaying, which is
	# why reversing a trailer is a skill — a model that stayed stable here would be wrong.
	var phi := 0.05
	var first := Artic.jackknife_step(phi, -3.0, 0.0, DELTA, BOGIE_Z, 0.2)
	assert_float(first).is_greater(phi)
	for _i in 600:
		phi = Artic.jackknife_step(phi, -3.0, 0.0, DELTA, BOGIE_Z, 0.2)
	# ...and it stops at the geometric limit rather than folding through the cab or wrapping.
	assert_float(phi).is_equal_approx(deg_to_rad(Artic.JACKKNIFE_MAX_DEG), 1e-6)


func test_the_limit_holds_on_both_sides() -> void:
	var phi := -0.05
	for _i in 600:
		phi = Artic.jackknife_step(phi, -3.0, 0.0, DELTA, BOGIE_Z, 0.2)
	assert_float(phi).is_equal_approx(-deg_to_rad(Artic.JACKKNIFE_MAX_DEG), 1e-6)


func test_a_standing_rig_does_not_articulate_by_itself() -> void:
	assert_float(Artic.jackknife_step(0.3, 0.0, 0.0, DELTA, BOGIE_Z, 0.2)).is_equal_approx(0.3, 1e-9)
	# Nor does a degenerate trailer with no wheelbase (guarded rather than dividing by zero).
	assert_float(Artic.jackknife_step(0.3, 8.0, 0.0, DELTA, 0.0, 0.2)).is_equal(0.3)


func test_turning_the_tractor_opens_the_angle_the_way_the_rig_bends() -> void:
	# Yaw is positive to the LEFT (the engine's own sign) and the trailer then lags on the right, a
	# positive articulation. The kingpin-ahead term only softens it, never inverts it.
	var left := Artic.jackknife_step(0.0, 5.0, 0.6, DELTA, BOGIE_Z, 0.2)
	assert_float(left).is_greater(0.0)
	assert_float(Artic.jackknife_step(0.0, 5.0, -0.6, DELTA, BOGIE_Z, 0.2)).is_less(0.0)


# --- static load split (what sizes the springs) -------------------------------

func test_the_kingpin_and_the_bogie_carry_the_whole_trailer() -> void:
	var share := Artic.kingpin_share(COM_Z, BOGIE_Z)
	assert_float(share + (1.0 - share)).is_equal_approx(1.0, 1e-9)
	# Load right over the bogie -> nothing on the plate; right on the plate -> all of it.
	assert_float(Artic.kingpin_share(BOGIE_Z, BOGIE_Z)).is_equal_approx(0.0, 1e-9)
	assert_float(Artic.kingpin_share(0.0, BOGIE_Z)).is_equal_approx(1.0, 1e-9)
	# Moving the load FORWARD moves weight onto the tractor. Which is how a rig is loaded.
	assert_float(Artic.kingpin_share(3.0, BOGIE_Z)).is_greater(share)


func test_every_trailer_puts_a_realistic_load_on_the_fifth_wheel() -> void:
	# 25-30 % is the band a real van semi-trailer is loaded to, and below it is the failure this pins:
	# at 19-22 % the tractor's single driven axle had a fifth of the trailer's weight missing from it
	# and the rig could not climb. A 4x2's traction budget is whatever the plate hands it. Above the
	# band the tractor's own axle limit becomes the constraint instead. Swept across the catalog,
	# because the share is a family-wide number.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var trailer := _trailer(path)
		var share: float = trailer.call("kingpin_share")
		assert_float(share) \
			.override_failure_message("%s puts %.1f%% on the plate" % [path, share * 100.0]) \
			.is_between(0.25, 0.30)
		# ...and the runtime figure is MEASURED off the spec's own anchors, not restated.
		assert_float(trailer.call("bogie_z")).is_equal_approx(BOGIE_Z, 1e-4)
		trailer.free()


func test_a_load_ahead_of_the_drive_axle_is_shared_with_the_steer_axle() -> void:
	# The semi's authored geometry: steer -1.15, drive +0.95, kingpin +0.75.
	assert_float(Artic.rear_axle_share(0.95, -1.15, 0.95)).is_equal_approx(1.0, 1e-9)
	assert_float(Artic.rear_axle_share(-1.15, -1.15, 0.95)).is_equal_approx(0.0, 1e-9)
	assert_float(Artic.rear_axle_share(-0.1, -1.15, 0.95)).is_equal_approx(0.5, 1e-9)
	# The kingpin sits 0.20 m ahead of the drive axle, so ~90 % of the plate load lands there.
	assert_float(Artic.rear_axle_share(0.75, -1.15, 0.95)).is_between(0.88, 0.93)


# --- the does-not-sink invariant ----------------------------------------------

## Static compression of one bogie wheel, as a fraction of the available travel.
func _travel_used(spec: VehicleSpec, load_kg: float, wheel_count: int) -> float:
	var per_wheel := load_kg * G / float(wheel_count)
	return (per_wheel / spec.ground_drive.spring_rate) / spec.ground_drive.rest_length


func test_the_flatbed_rides_on_its_springs_and_not_on_its_stops() -> void:
	var trailer := _flatbed()
	var spec: VehicleSpec = trailer.get("spec")
	var bogie_kg: float = spec.mass * (1.0 - float(trailer.call("kingpin_share")))
	var used := _travel_used(spec, bogie_kg, spec.ground_drive.wheel_positions.size())
	assert_float(used) \
		.override_failure_message("flatbed sits at %.0f%% of its suspension travel at rest" \
			% (used * 100.0)) \
		.is_between(0.2, 0.6)
	# The heaviest trailer is ~25 t on this same running gear: still inside the travel, so raising the
	# mass is a re-tune with a measured ceiling rather than a free number.
	var heavy := _travel_used(spec, 25000.0 * (1.0 - float(trailer.call("kingpin_share"))),
			spec.ground_drive.wheel_positions.size())
	assert_float(heavy) \
		.override_failure_message("a 25 t trailer bottoms this spring (%.0f%% of travel)" \
			% (heavy * 100.0)) \
		.is_less(0.9)
	# And the force cap must not be what holds it up (that would flatten trailer_axle_load).
	assert_float(25000.0 * G / float(spec.ground_drive.wheel_positions.size())) \
			.is_less(spec.ground_drive.max_suspension_force)
	trailer.free()


func test_the_semis_drive_axle_carries_the_fifth_wheel_load_without_bottoming() -> void:
	# The one number on the semi's spec that is not the garbage truck's: the rear springs carry its own
	# weight plus the plate load, and a coupled tractor sitting on its stops is the failure.
	var semi := _semi()
	var spec: VehicleSpec = semi.get("spec")
	var trailer := _flatbed()
	var t_spec: VehicleSpec = trailer.get("spec")

	var front_z := 0.0
	var rear_z := 0.0
	var rear_wheels := 0
	for p in spec.ground_drive.wheel_positions:
		front_z = minf(front_z, p.z)
		rear_z = maxf(rear_z, p.z)
		if p.z > 0.0:
			rear_wheels += 1
	var own_kg: float = spec.mass * Artic.rear_axle_share(spec.center_of_mass.z, front_z, rear_z)
	var plate_kg: float = t_spec.mass * float(trailer.call("kingpin_share")) \
			* Artic.rear_axle_share(FifthWheelScript.KINGPIN_LOCAL.z, front_z, rear_z)

	var solo := _travel_used(spec, own_kg, rear_wheels)
	var coupled := _travel_used(spec, own_kg + plate_kg, rear_wheels)
	assert_float(solo).override_failure_message(
			"bobtail rear sits at %.0f%% of travel" % (solo * 100.0)).is_between(0.2, 0.45)
	assert_float(coupled).override_failure_message(
			"coupled rear sits at %.0f%% of travel" % (coupled * 100.0)).is_between(0.3, 0.7)
	assert_float((own_kg + plate_kg) * G / float(rear_wheels)) \
		.is_less(spec.ground_drive.max_suspension_force)
	trailer.free()
	semi.free()


# --- the catalog, the cycle, and what the scenes declare ----------------------

func test_the_cycle_includes_bobtail_and_wraps() -> void:
	var seen := PackedStringArray()
	var id := Catalog.first()
	for _i in Catalog.TRAILERS.size():
		seen.append(id)
		id = Catalog.next(id)
	assert_str(id).is_equal(Catalog.first())
	assert_int(seen.size()).is_equal(Catalog.TRAILERS.size())
	assert_bool(seen.has(Catalog.BOBTAIL)) \
		.override_failure_message("running bobtail must be reachable by cycling").is_true()


func test_the_semi_spawns_coupled_and_bobtail_is_leavable() -> void:
	assert_bool(Catalog.is_coupled(Catalog.first())).is_true()
	assert_bool(Catalog.is_coupled(Catalog.BOBTAIL)).is_false()
	assert_bool(Catalog.is_coupled(Catalog.next(Catalog.BOBTAIL))).is_true()


func test_an_unknown_trailer_id_restarts_the_cycle() -> void:
	assert_str(Catalog.next("res://nope.tscn")).is_equal(Catalog.TRAILERS[0])


func test_the_trailer_cycle_wraps_and_ends_on_bobtail() -> void:
	# E cycles trailers and V cycles bodies, so this is a plain wrapping loop; the property to hold
	# is that it closes. Bobtail stays LAST so one press drops the trailer and the next picks it back
	# up — appending a new trailer after it would move running-bobtail into the middle of the cycle.
	var last: String = Catalog.TRAILERS[Catalog.TRAILERS.size() - 1]
	assert_str(Catalog.next(last)).is_equal(Catalog.first())
	assert_str(last) \
		.override_failure_message("bobtail must be the LAST cycle entry, not '%s'" % last) \
		.is_equal(Catalog.BOBTAIL)
	# ...and only the last entry wraps: an earlier one jumping back would shorten the cycle silently.
	for i in Catalog.TRAILERS.size() - 1:
		assert_str(Catalog.next(Catalog.TRAILERS[i])) \
			.override_failure_message("the cycle wraps early, at entry %d of %d" % [
				i, Catalog.TRAILERS.size()]) \
			.is_not_equal(Catalog.first())


func test_every_trailer_is_a_towed_body_with_its_wheels_authored_to_match_its_spec() -> void:
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("missing trailer scene: %s" % path).is_true()
		var node := (load(path) as PackedScene).instantiate()
		assert_object(node).is_instanceof(TowedBody)
		var spec: VehicleSpec = node.get("spec")
		assert_object(spec).override_failure_message("%s has no spec" % path).is_not_null()
		# The wheel visuals are paired to the spec's anchors BY INDEX, so a count mismatch is an
		# authoring error that would otherwise only show up as an invisible wheel.
		var wheel_root: Node = node.get_node_or_null(node.get("wheel_root"))
		assert_object(wheel_root) \
			.override_failure_message("%s has no Wheels node" % path).is_not_null()
		assert_int(wheel_root.get_child_count()) \
			.override_failure_message("%s: %d wheel visuals for %d spec anchors" % [
				path, wheel_root.get_child_count(), spec.ground_drive.wheel_positions.size()]) \
			.is_equal(spec.ground_drive.wheel_positions.size())
		# A towed body is undriven and unbraked-by-hand: it has no driveline to claim.
		assert_bool(spec.ground_drive.driven_front or spec.ground_drive.driven_rear) \
			.override_failure_message("%s claims driven wheels" % path).is_false()
		assert_bool(spec.ground_drive.retarder_equipped) \
			.override_failure_message("%s claims a retarder" % path).is_false()
		assert_bool(spec.ground_drive.rear_diff_lockable or spec.ground_drive.front_axle_engageable) \
			.override_failure_message("%s claims a tractor driveline" % path).is_false()
		# ...but it does brake, or the tractor would be stopping the whole rig on its own.
		assert_float(spec.ground_drive.brake_torque).is_greater(0.0)
		node.free()


func test_the_semi_is_a_truck_that_tows_and_declares_its_retarder() -> void:
	assert_str(CatalogScript.family_of("semi")).is_equal("truck")
	# The garage default must stay the garbage truck: the semi is last in the family because V on
	# it cycles trailers instead of bodies.
	assert_str(CatalogScript.first_in_family("truck")).is_equal("garbage-truck")
	var semi := _semi()
	assert_bool(semi.has_method("cycle_implement")) \
		.override_failure_message("E would not cycle the semi's trailer").is_true()
	# Hand-authored spec: no generator baseline stands behind this flag, so it is pinned here.
	var spec: VehicleSpec = semi.get("spec")
	assert_bool(spec.ground_drive.retarder_equipped).is_true()
	semi.free()


func test_the_kingpin_marker_and_the_code_agree() -> void:
	# The joint is built at the marker, so the constant is only documentation — unless they drift, at
	# which point everything measured against the authored figure (the trailer's ground plane at
	# y = -1.05, the cab clearance) is quietly wrong. The marker sits under a `FifthWheel` node at
	# identity, so `TowHost._ready`'s `transform * marker.position` is still this figure.
	var semi := _semi()
	var marker: Node3D = semi.get_node_or_null("FifthWheel/Kingpin")
	assert_object(marker).override_failure_message("semi.tscn has no Kingpin marker").is_not_null()
	assert_vector((semi.get_node("FifthWheel") as Node3D).position) \
		.override_failure_message("the FifthWheel node is offset, so the marker is not the datum") \
		.is_equal(Vector3.ZERO)
	assert_vector(marker.position).is_equal_approx(FifthWheelScript.KINGPIN_LOCAL, Vector3.ONE * 1e-6)
	semi.free()


## Worst swing radius about the kingpin over every BoxMesh corner ahead of it, walked recursively
## with the transforms accumulated by hand (an instantiated scene is not in a tree). Corners rather
## than a half-width-plus-overhang formula, because the tipper's body lives under a rotating pivot.
## Returns [radius, name].
func _worst_forward_swing(node: Node, xf: Transform3D, worst: Array) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var here := xf * n3.transform
		var mesh_node := n3 as MeshInstance3D
		if mesh_node != null and mesh_node.mesh is BoxMesh:
			var half: Vector3 = (mesh_node.mesh as BoxMesh).size * 0.5
			var signs: Array[float] = [-1.0, 1.0]
			for sx in signs:
				for sy in signs:
					for sz in signs:
						var p: Vector3 = here * Vector3(sx * half.x, sy * half.y, sz * half.z)
						# Behind the kingpin it swings away from the cab; only what is ahead can reach it.
						if p.z >= 0.0:
							continue
						var r := Vector2(p.x, p.z).length()
						if r > float(worst[0]):
							worst[0] = r
							worst[1] = String(n3.name)
		_worst_forward_swing(n3, here, worst)


func test_every_trailer_clears_the_cab_all_the_way_round() -> void:
	# A trailer's front corners swing on sqrt(x^2 + z^2) about the kingpin, and that radius has to fit
	# between the kingpin and the cab's rear face. Both figures are read off the authored scenes.
	var semi := _semi()
	var cab: Node3D = semi.get_node("Body/Cab")
	var cab_rear: float = cab.position.z + (cab.mesh as BoxMesh).size.z * 0.5
	var kingpin_to_cab: float = FifthWheelScript.KINGPIN_LOCAL.z - cab_rear
	semi.free()

	# Swept over every part that projects forward of the kingpin, not one named node: the frontmost
	# part has already changed once (the gooseneck took over from the headboard).
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var trailer := _trailer(path)
		var worst: Array = [0.0, ""]
		_worst_forward_swing(trailer, Transform3D.IDENTITY, worst)
		assert_float(worst[0]) \
			.override_failure_message("%s: nothing projects ahead of the kingpin" % path) \
			.is_greater(0.0)
		assert_float(kingpin_to_cab) \
			.override_failure_message(
				"%s: %s swings on %.3f m, which does not fit the %.2f m from the kingpin to the cab"
				% [path, worst[1], worst[0], kingpin_to_cab]) \
			.is_greater(float(worst[0]))
		trailer.free()


# --- ISO 11992: the EBS11 brake-demand blend ----------------------------------

func test_the_foot_brake_alone_is_the_whole_demand() -> void:
	# With the retarder released the tractor sends the pedal and nothing else, so a driver who
	# never touches the stalk sees TBRK track the brake exactly.
	assert_float(TruckT.trailer_brake_blend(0.0, 0)).is_equal(0.0)
	assert_float(TruckT.trailer_brake_blend(0.4, 0)).is_equal_approx(0.4, 1e-9)
	assert_float(TruckT.trailer_brake_blend(1.0, 0)).is_equal_approx(1.0, 1e-9)


func test_the_retarder_asks_the_trailer_for_the_same_fraction_it_is_making_itself() -> void:
	# The share is arithmetic: a retarder at full is RETARDER_MAX_FRAC of the tractor's own brake
	# torque, so it asks the trailer for that same fraction of the trailer's brakes and the two ends
	# scrub at matched fractions. Asserted against the constant, so re-rating moves both together.
	assert_float(TruckT.trailer_brake_blend(0.0, 100)) \
			.is_equal_approx(DrivetrainScript.RETARDER_MAX_FRAC, 1e-9)
	assert_float(TruckT.trailer_brake_blend(0.0, 50)) \
			.is_equal_approx(DrivetrainScript.RETARDER_MAX_FRAC * 0.5, 1e-9)
	assert_float(TruckT.trailer_brake_blend(0.0, 100)).is_greater(0.05)


func test_the_blend_adds_and_saturates_at_a_full_application() -> void:
	# Both consumers push the same channel, and it is monotone in each — a rig cannot brake the
	# trailer harder than the trailer's own brakes.
	var pedal_only := TruckT.trailer_brake_blend(0.5, 0)
	assert_float(TruckT.trailer_brake_blend(0.5, 100)).is_greater(pedal_only)
	assert_float(TruckT.trailer_brake_blend(0.9, 100)).is_equal(1.0)
	assert_float(TruckT.trailer_brake_blend(1.0, 100)).is_equal(1.0)
	# Garbage on either input is sanitized like every other request in this project.
	assert_float(TruckT.trailer_brake_blend(-2.0, -50)).is_equal(0.0)
	assert_float(TruckT.trailer_brake_blend(9.0, 900)).is_equal(1.0)


func test_the_demand_inherits_the_retarders_speed_fade_for_free() -> void:
	# The blend reads retarder_state (what actually ran, after the fade and the anti-lock cap), not the
	# request — so at walking pace, where the retarder has faded to nothing, it stops asking the
	# trailer for anything.
	var semi := _semi()
	var spec: VehicleSpec = semi.get("spec")
	var rated := DrivetrainScript.retarder_rating(spec.ground_drive.brake_torque) * 2.0
	var crawling := roundi(DrivetrainScript.retarder_pct(
			DrivetrainScript.retarder_demand(1.0, 0.3, spec.ground_drive.brake_torque) * 2.0, rated))
	assert_int(crawling).override_failure_message(
			"the retarder should have faded out at walking pace").is_equal(0)
	assert_float(TruckT.trailer_brake_blend(0.0, crawling)).is_equal(0.0)
	var rolling := roundi(DrivetrainScript.retarder_pct(
			DrivetrainScript.retarder_demand(1.0, 20.0, spec.ground_drive.brake_torque) * 2.0, rated))
	assert_int(rolling).is_equal(100)
	assert_float(TruckT.trailer_brake_blend(0.0, rolling)).is_greater(0.0)
	semi.free()


# --- ISO 11992: the EBS21 ABS predicate ---------------------------------------

func test_abs_reports_only_a_wheel_going_to_a_lock() -> void:
	# The threshold sits far above the 0.024-0.029 a braked axle settles at, so normal braking must
	# not light the lamp — an ABS telltale that is on whenever you brake says nothing.
	assert_bool(TruckT.trailer_abs_active(0.0)).is_false()
	assert_bool(TruckT.trailer_abs_active(0.03)).is_false()
	assert_bool(TruckT.trailer_abs_active(TruckT.TRAILER_ABS_SLIP)).is_false()
	assert_bool(TruckT.trailer_abs_active(TruckT.TRAILER_ABS_SLIP + 0.01)).is_true()
	# A fully locked wheel (slip 1.0 — the spin has stopped while the road has not).
	assert_bool(TruckT.trailer_abs_active(1.0)).is_true()
	assert_float(TruckT.TRAILER_ABS_SLIP).override_failure_message(
			"the ABS threshold must sit clear of ordinary braking slip").is_greater(0.1)


func test_abs_reads_the_worst_wheel_and_not_an_average() -> void:
	# ABS is a per-wheel device: one locking wheel is the event, and averaging it against three
	# healthy ones would hide exactly the case worth showing.
	var trailer := _wheeled_flatbed()
	var wheels: Array = trailer.get("wheels")
	assert_int(wheels.size()).is_greater(1)
	for w in wheels:
		w.slip = 0.02
	assert_float(trailer.call("max_wheel_slip")).is_equal_approx(0.02, 1e-9)
	assert_bool(TruckT.trailer_abs_active(trailer.call("max_wheel_slip"))).is_false()
	wheels[0].slip = 0.85
	assert_float(trailer.call("max_wheel_slip")).is_equal_approx(0.85, 1e-9)
	assert_bool(TruckT.trailer_abs_active(trailer.call("max_wheel_slip"))) \
		.override_failure_message("one locked wheel must light the trailer ABS").is_true()
	trailer.free()


# --- ISO 11992: trailer_axle_load, summed off the bogie's own springs ---------

func test_the_trailer_axle_load_is_summed_suspension_force_and_not_a_mass_lookup() -> void:
	# Read out of the sim, exactly as the drive axle's axle_load is and through the same function:
	# whatever the bogie's springs were holding up this tick, in kilograms.
	var trailer := _wheeled_flatbed()
	var wheels: Array = trailer.get("wheels")
	var spec: VehicleSpec = trailer.get("spec")

	# Springs unloaded (the bogie in the air on a crest) reads a real 0 — a mass lookup could not.
	for w in wheels:
		w.suspension_force = 0.0
	assert_float(trailer.call("bogie_suspension_force")).is_equal(0.0)
	assert_float(TruckT.axle_load_kg(trailer.call("bogie_suspension_force"))).is_equal(0.0)

	var bogie_kg: float = spec.mass * (1.0 - float(trailer.call("kingpin_share")))
	var per_wheel := bogie_kg * TruckT.GRAVITY / float(wheels.size())
	for w in wheels:
		w.suspension_force = per_wheel
	assert_float(trailer.call("bogie_suspension_force")) \
			.is_equal_approx(bogie_kg * TruckT.GRAVITY, 1e-3)
	assert_float(TruckT.axle_load_kg(trailer.call("bogie_suspension_force"))) \
		.override_failure_message("the summed springs must report the load the bogie carries") \
		.is_equal_approx(bogie_kg, 1e-3)
	# ...and it is the kingpin share that is missing from it, not a fudge: the plate carries the rest.
	assert_float(bogie_kg).is_less(spec.mass)

	# Weight transfer moves it, because the springs really moved.
	wheels[0].suspension_force = per_wheel * 1.6
	assert_float(TruckT.axle_load_kg(trailer.call("bogie_suspension_force"))).is_greater(bogie_kg)
	trailer.free()


func test_the_shipped_flatbed_sits_inside_the_contracts_trailer_load_range() -> void:
	# The bar would peg (and the warn would be meaningless) if a shipped trailer read off the end of
	# the contract's [0, 30000] scale.
	var trailer := _wheeled_flatbed()
	var spec: VehicleSpec = trailer.get("spec")
	var bogie_kg: float = spec.mass * (1.0 - float(trailer.call("kingpin_share")))
	var sig := _contract().get_signal_def("trailer_axle_load", "out")
	assert_object(sig).override_failure_message("missing trailer_axle_load out signal").is_not_null()
	assert_float(bogie_kg) \
		.override_failure_message("the flatbed's %.0f kg bogie is off the contract scale" % bogie_kg) \
		.is_between(float(sig.range[0]), float(sig.range[1]))
	# It must also sit BELOW the overload warn, or the shipped rig drives with a red bar.
	assert_float(bogie_kg).is_less(sig.warn)
	trailer.free()


# --- ISO 11992: a coupled trailer draws air ----------------------------------

func test_a_charging_trailer_draws_and_a_charged_one_stops() -> void:
	# The draw is a TRANSIENT at the coupling, not a permanent tax on the supply.
	assert_float(TruckT.trailer_air_draw(true, 0.0)).is_equal(TruckT.TRAILER_AIR_DRAW)
	assert_float(TruckT.trailer_air_draw(true, 0.99)).is_equal(TruckT.TRAILER_AIR_DRAW)
	assert_float(TruckT.trailer_air_draw(true, 1.0)).is_equal(0.0)
	assert_float(TruckT.trailer_air_draw(false, 0.0)).is_equal(0.0)
	assert_float(TruckT.trailer_air_draw(false, 1.0)).is_equal(0.0)


func test_the_trailer_reservoir_fills_in_its_stated_time_and_stops_there() -> void:
	var charge := 0.0
	for _i in roundi(TruckT.TRAILER_CHARGE_S / DELTA):
		charge = TruckT.trailer_air_step(charge, DELTA)
	assert_float(charge).is_equal_approx(1.0, 1e-6)
	# Half way through it is half full: the fill is linear, which is what makes the dip readable.
	var half := 0.0
	for _i in roundi(TruckT.TRAILER_CHARGE_S * 0.5 / DELTA):
		half = TruckT.trailer_air_step(half, DELTA)
	assert_float(half).is_equal_approx(0.5, 1e-6)
	assert_float(TruckT.trailer_air_step(1.0, 10.0)).is_equal(1.0)


func test_coupling_dips_both_circuits_and_the_primary_further() -> void:
	# Hooking up costs air, visibly, on the bars — and through the air model rather than beside it,
	# so the pair diverges here exactly as it does under braking. Simulated at the locked 60 Hz.
	var primary := TruckT.AIR_SPAWN_BAR
	var secondary := TruckT.AIR_SPAWN_BAR
	var charge := 0.0
	for _i in roundi(TruckT.TRAILER_CHARGE_S / DELTA):
		var draw := TruckT.trailer_air_draw(true, charge)
		primary = TruckT.air_step(primary, 0.0, true, DELTA,
				TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_PRIMARY, draw)
		secondary = TruckT.air_step(secondary, 0.0, true, DELTA,
				TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_SECONDARY, draw)
		charge = TruckT.trailer_air_step(charge, DELTA)

	assert_float(primary).override_failure_message(
			"coupling did not dip AIR1 (%.2f bar from %.2f)" % [primary, TruckT.AIR_SPAWN_BAR]) \
		.is_less(TruckT.AIR_SPAWN_BAR - 1.0)
	assert_float(primary).is_less(secondary)   # the smaller circuit-2 reservoir dips less
	assert_float(secondary).is_less(TruckT.AIR_SPAWN_BAR)
	# It must be VISIBLE on the cluster: the primary goes past the contract's low-pressure warn.
	var warn: float = _contract().get_signal_def("air_primary", "out").warn
	assert_float(primary).override_failure_message(
			"the coupling dip (%.2f bar) never reaches the %.1f bar warn" % [primary, warn]) \
		.is_less(warn)
	# ...but coupling ALONE must not set the spring brakes, or hooking up would immobilize the rig
	# every time. The gate is what the next brake application can reach, not what coupling does.
	assert_bool(TruckT.spring_brakes_applied(primary, secondary)) \
		.override_failure_message("coupling alone immobilized the truck").is_false()

	for _i in 600:
		primary = TruckT.air_step(primary, 0.0, true, DELTA,
				TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_PRIMARY, TruckT.trailer_air_draw(true, 1.0))
	assert_float(primary).is_greater(warn)


func test_coupling_and_driving_off_can_reach_the_spring_brake_gate() -> void:
	# The consequence: brake while the trailer is still charging and the reservoirs reach the cut-in,
	# at which point the spring brakes set and the rig stops where it stands. Pinned as "sooner than
	# the brake alone would", so it stays a real interaction rather than a coincidence of two rates.
	var ticks_to_gate := func(with_trailer: bool) -> int:
		var p := TruckT.AIR_SPAWN_BAR
		var s := TruckT.AIR_SPAWN_BAR
		var charge := 0.0
		for i in 3600:
			var draw: float = TruckT.trailer_air_draw(with_trailer, charge)
			p = TruckT.air_step(p, 1.0, true, DELTA,
					TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_PRIMARY, draw)
			s = TruckT.air_step(s, 1.0, true, DELTA,
					TruckT.AIR_CHARGE_RATE, TruckT.AIR_DRAW_SECONDARY, draw)
			charge = TruckT.trailer_air_step(charge, DELTA)
			if TruckT.spring_brakes_applied(p, s):
				return i
		return -1

	var coupled: int = ticks_to_gate.call(true)
	var bobtail: int = ticks_to_gate.call(false)
	assert_int(coupled).override_failure_message(
			"a full application on a freshly coupled rig never reached the gate").is_greater(0)
	assert_int(coupled).override_failure_message(
			"the fresh trailer must reach the gate SOONER than the brake alone (%d vs %d ticks)"
			% [coupled, bobtail]).is_less(bobtail)
	# It has to be reachable while the trailer is still charging, or the interaction is theoretical.
	assert_float(float(coupled) * DELTA).is_less(TruckT.TRAILER_CHARGE_S)


# --- ISO 11992: honest zeros, and the connector the claim depends on ----------

func test_the_trailer_bus_publishes_real_zeros_rather_than_a_gap() -> void:
	# A bobtail tractor unit is a legitimate state of the machine, so every trailer signal reads a real
	# false / 0 every tick — the same rule a detached implement follows.
	var t := TruckT.new()
	t.trailer_connected = true
	t.trailer_axle_load = 9000.0
	t.trailer_brake_demand = 55
	t.trailer_abs = true
	t.clear_trailer_bus()
	assert_bool(t.trailer_connected).is_false()
	assert_float(t.trailer_axle_load).is_equal(0.0)
	assert_int(t.trailer_brake_demand).is_equal(0)
	assert_bool(t.trailer_abs).is_false()
	# ...and they are published rather than merely stored: the bridge walks this dict.
	var d := t.to_bridge_dict()
	for key in ["trailer_connected", "trailer_axle_load", "trailer_brake_demand", "trailer_abs"]:
		assert_bool(d.has(key)) \
			.override_failure_message("to_bridge_dict drops '%s'" % key).is_true()


func test_the_european_unit_declares_the_iso_7638_data_pair() -> void:
	# Hand-authored spec with no generator baseline behind it, so the flag is pinned here exactly like
	# retarder_equipped. It is what makes trailer_connected a claim rather than a synonym for
	# "something is on the fifth wheel": a unit without it tows the same trailer and publishes nothing.
	var semi := _semi()
	var spec: VehicleSpec = semi.get("spec")
	assert_bool(spec.trailer_bus_equipped) \
		.override_failure_message("the European tractor unit must carry the ISO 11992 data pair") \
		.is_true()
	semi.free()
	# Off by default everywhere else, so no other vehicle can claim a trailer bus by omission.
	assert_bool(VehicleSpec.new().trailer_bus_equipped).is_false()
	# The trailers themselves declare nothing: the connector is the towing unit's.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := (load(path) as PackedScene).instantiate()
		var t_spec: VehicleSpec = node.get("spec")
		assert_bool(t_spec.trailer_bus_equipped) \
			.override_failure_message("%s claims a towing unit's connector" % path).is_false()
		node.free()


# --- what the catalog DECLARES: mass, consumers, and what they must agree on ------------------

## Static compression of one bogie wheel as a fraction of travel, for a trailer carrying `share` of
## its own mass on the fifth wheel. The load model can move `share`, hence the argument.
func _bogie_travel(spec: VehicleSpec, kingpin_share: float) -> float:
	var bogie_kg: float = spec.mass * (1.0 - kingpin_share)
	return _travel_used(spec, bogie_kg, spec.ground_drive.wheel_positions.size())


func test_no_two_trailers_report_the_same_mass() -> void:
	# Mass is the only thing on the wire that tells these four apart. There is no trailer_type and
	# there is not going to be one, so trailer_axle_load carrying a different number per trailer is the
	# whole of "which trailer is on the back". Two trailers sharing a mass would make the set claim a
	# variety it does not have.
	var seen := {}
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		assert_bool(seen.has(spec.mass)) \
			.override_failure_message("%s masses %.0f kg, already used by %s"
				% [path, spec.mass, seen.get(spec.mass, "")]) \
			.is_false()
		seen[spec.mass] = path
		node.free()
	assert_int(seen.size()).is_equal(Catalog.TRAILERS.size() - 1)


func test_the_box_is_the_heaviest_and_the_flatbed_the_lightest() -> void:
	# A 10 t difference across the catalog is what makes cycling trailers
	# change how the rig pulls away, stops and reads on axle_load, with no signal added anywhere.
	var heaviest := 0.0
	var lightest := INF
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		heaviest = maxf(heaviest, spec.mass)
		lightest = minf(lightest, spec.mass)
		node.free()
	var box := _trailer(BOX)
	var flatbed := _flatbed()
	assert_float((box.get("spec") as VehicleSpec).mass) \
		.override_failure_message("the box must be the heaviest trailer").is_equal(heaviest)
	assert_float((flatbed.get("spec") as VehicleSpec).mass) \
		.override_failure_message("the flatbed must be the lightest trailer").is_equal(lightest)
	assert_float(heaviest - lightest).is_greater(8000.0)
	box.free()
	flatbed.free()


func test_the_heaviest_trailer_holds_the_verified_mass_ratio() -> void:
	# The measured ceiling: 8 t tractor : 25 t trailer (3 : 1) is what was verified by re-speccing
	# live, and past it the rig is a re-tune needing re-verification rather than a free number. This
	# fails instead of shipping a trailer that quietly walked past it.
	var semi := _semi()
	var tractor_kg: float = (semi.get("spec") as VehicleSpec).mass
	semi.free()
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		assert_float(spec.mass / tractor_kg) \
			.override_failure_message("%s is %.2f : 1 against the tractor unit, past the verified 3 : 1"
				% [path, spec.mass / tractor_kg]) \
			.is_less_equal(3.0)
		node.free()


func test_every_trailer_rides_on_its_springs_and_not_on_its_stops() -> void:
	# The does-not-sink invariant across the whole catalog. Each spec's spring rate is sized off the
	# load its own bogie carries, so all four land at the same fraction of travel however different
	# their masses are, which makes raising a mass a visible edit rather than a silent bottoming.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		var used := _bogie_travel(spec, float(node.call("kingpin_share")))
		assert_float(used) \
			.override_failure_message("%s sits at %.0f%% of its suspension travel at rest"
				% [path, used * 100.0]) \
			.is_between(0.25, 0.5)
		# The force cap must not be what holds it up: a capped spring flattens trailer_axle_load.
		assert_float(spec.mass * G / float(spec.ground_drive.wheel_positions.size())) \
			.override_failure_message("%s leans on its suspension force cap" % path) \
			.is_less(spec.ground_drive.max_suspension_force)
		node.free()


func test_every_trailer_reads_inside_the_contracts_trailer_load_scale() -> void:
	# The bar would peg (and the warn would be meaningless) if a shipped trailer read off the end of
	# the contract's scale; the heavier trailers must move this bar, not saturate it.
	var sig := _contract().get_signal_def("trailer_axle_load", "out")
	assert_object(sig).override_failure_message("missing trailer_axle_load out signal").is_not_null()
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		var bogie_kg: float = spec.mass * (1.0 - float(node.call("kingpin_share")))
		assert_float(bogie_kg) \
			.override_failure_message("%s: a %.0f kg bogie is off the contract scale" % [path, bogie_kg]) \
			.is_between(float(sig.range[0]), float(sig.range[1]))
		assert_float(bogie_kg) \
			.override_failure_message("%s drives with the overload bar already red" % path) \
			.is_less(sig.warn)
		node.free()


func test_hydraulics_imply_the_pto_that_drives_the_pump() -> void:
	# The consistency rule, the shape of test_implement_catalog's draft-relevant-implies-a-depth: a
	# tipping pump is turned by the chassis PTO, so a trailer that claims a proportional valve and no
	# PTO has claimed plumbing with nothing behind it, and SemiTractor would hand it unusable flow.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		if node.call("uses", TowedBody.Consumer.HYDRAULIC):
			assert_bool(node.call("uses", TowedBody.Consumer.PTO)) \
				.override_failure_message("%s claims a valve but no PTO to drive the pump" % path) \
				.is_true()
		node.free()


func test_the_base_declaration_is_a_trailer_that_plugs_in_nothing() -> void:
	var base := TowedBody.new()
	assert_int(base.consumers()).is_equal(0)
	assert_bool(base.uses(TowedBody.Consumer.PTO)).is_false()
	assert_bool(base.uses(TowedBody.Consumer.HYDRAULIC)).is_false()
	assert_float(base.body_pos01()).is_equal(0.0)
	assert_float(base.load_shift_z()).is_equal(0.0)
	base.free()


func test_the_box_and_the_flatbed_are_the_same_trailer_to_the_towing_unit() -> void:
	# On the ISO 11992 bus a box is indistinguishable from a flatbed: the standard carries no body
	# type, so the two declare identical consumers, run identical running gear and differ only in mass.
	# A future trailer that breaks this by adding a signal to tell them apart fails here.
	var box := _trailer(BOX)
	var flatbed := _flatbed()
	assert_int(box.call("consumers")) \
		.override_failure_message("the box must plug nothing into the towing unit").is_equal(0)
	assert_int(box.call("consumers")).is_equal(flatbed.call("consumers"))
	assert_float(box.call("body_pos01")).is_equal(flatbed.call("body_pos01"))
	var box_spec: VehicleSpec = box.get("spec")
	var flat_spec: VehicleSpec = flatbed.get("spec")
	assert_float(box_spec.mass).is_greater(flat_spec.mass)
	var box_bogie: float = box_spec.mass * (1.0 - float(box.call("kingpin_share")))
	var flat_bogie: float = flat_spec.mass * (1.0 - float(flatbed.call("kingpin_share")))
	assert_float(box_bogie - flat_bogie) \
		.override_failure_message("the box must move trailer_axle_load by tonnes, not kilos") \
		.is_greater(5000.0)
	box.free()
	flatbed.free()


func test_a_trailer_that_declares_nothing_does_nothing_with_drive_it_is_handed() -> void:
	# Asserted at the trailer end too. The gate is SemiTractor's (a towed body is never trusted to
	# ignore drive it never plugged in), but a subclass that quietly reacted to flow it never declared
	# would make the declaration decorative, so every non-consumer gets a full PTO and an open valve.
	for path in [BOX, TANKER, FLATBED]:
		var node := _trailer(path)
		if node.call("uses", TowedBody.Consumer.HYDRAULIC):
			node.free()
			continue
		node.call("set_pto", true, 1800)
		node.call("set_valve", 1.0)
		for _i in 600:
			node.call("tick_body", DELTA)
		assert_float(node.call("body_pos01")) \
			.override_failure_message("%s moved a body it never declared" % path).is_equal(0.0)
		node.free()


# --- no two faces may share a plane and a facing (the z-fight rule) ----------------------------

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


func test_no_two_boxes_share_a_face_plane_and_a_facing() -> void:
	# The z-fight rule, asserted instead of remembered. src/vehicles/CLAUDE.md states it: two boxes
	# that TOUCH on a face plane flicker, two that OVERLAP never do, and the safe pairs are the ones
	# whose faces point at each other, because back-face culling drops one of them. So what is
	# forbidden is a shared plane with a shared facing (both minima or both maxima on the same axis)
	# over a patch big enough to see.
	#
	# This shipped as a real bug: the box trailer had its bottom rave and its side wall both ending at
	# x = +-0.96, which flickered as a 5.4 m stripe down each side.
	const EPS := 0.0015      # planes closer than this are the same plane
	const MIN_PATCH := 0.02  # a patch smaller than this is a sliver nobody sees
	# Both tractor units are swept too: they are the hand-authored reference the trailers were built to
	# match, and they already pass.
	var scenes := PackedStringArray([
		CatalogScript.scene_of("semi"), CatalogScript.scene_of("semi-conventional")])
	for path in Catalog.TRAILERS:
		if Catalog.is_coupled(path):
			scenes.append(path)

	for path in scenes:
		var scene := (load(path) as PackedScene).instantiate()
		var boxes: Array = []
		_axis_boxes(scene, Transform3D.IDENTITY, boxes)
		assert_int(boxes.size()).override_failure_message("%s has no boxes" % path).is_greater(4)
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


func _axis_overlap(a: Dictionary, b: Dictionary, axis: int) -> float:
	var lo: float = maxf((a["min"] as Vector3)[axis], (b["min"] as Vector3)[axis])
	var hi: float = minf((a["max"] as Vector3)[axis], (b["max"] as Vector3)[axis])
	return hi - lo


# --- coupling clearance: the shapes the refusal is tested with ---------------------------------

func test_every_trailer_offers_its_authored_shapes_before_it_enters_the_world() -> void:
	# collision_probes walks every CollisionShape3D with its transform accumulated to trailer space,
	# off a scene that is not in the tree. Nothing at runtime reads it — coupling asks the physics
	# engine after the fact — but it is how this suite checks the authored collision.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var probes: Array[Dictionary] = node.call("collision_probes")
		# ENABLED shapes, not authored ones: the tipper authors its body twice (a lowered pose and a
		# raised one) and keeps exactly one of the pair live, so a raw count would read the pose swap as
		# a shape the walk had lost.
		var authored := node.find_children("*", "CollisionShape3D", true, false)
		var live := 0
		for s: CollisionShape3D in authored:
			if s.shape != null and not s.disabled:
				live += 1
		assert_int(probes.size()) \
			.override_failure_message("%s: %d probes for %d live authored shapes"
				% [path, probes.size(), live]) \
			.is_equal(live)
		assert_int(probes.size()) \
			.override_failure_message("%s has no collision at all — it would never refuse" % path) \
			.is_greater(0)
		for probe in probes:
			assert_object(probe["shape"]).is_not_null()
			# A degenerate transform would make the query test a point and pass through anything.
			assert_float((probe["xf"] as Transform3D).basis.determinant()).is_equal_approx(1.0, 1e-5)
		node.free()


func test_the_probes_sit_where_the_trailer_does_and_clear_the_road() -> void:
	# Per-shape rather than one bounding box: the authored shapes already clear the ground, so a modest
	# slope 5 m behind the cab is not a collision. One box around the whole trailer would refuse every
	# hill.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var lowest := INF
		var frontmost := INF
		for probe in node.call("collision_probes"):
			var box := probe["shape"] as BoxShape3D
			assert_object(box).override_failure_message("%s: non-box probe" % path).is_not_null()
			var xf: Transform3D = probe["xf"]
			lowest = minf(lowest, xf.origin.y - box.size.y * 0.5)
			frontmost = minf(frontmost, xf.origin.z - box.size.z * 0.5)
		# Ground is y = -1.05 in trailer space; the lowest shape must stand clear of it.
		assert_float(lowest + 1.05) \
			.override_failure_message("%s: lowest collision shape is %.2f m over the road"
				% [path, lowest + 1.05]) \
			.is_between(0.15, 0.8)
		# ...and nothing reaches so far forward that the coupled pose starts inside the tractor.
		assert_float(frontmost) \
			.override_failure_message("%s: collision reaches %.2f m ahead of the kingpin" % [path, frontmost]) \
			.is_greater(-0.8)
		node.free()


func test_the_fit_check_is_reactive_and_its_windows_are_short() -> void:
	# The clearance story is two counters. Coupling never refuses; the trailer is laid, then watched
	# for the one thing that means it does not fit — its body touching something. Both windows are
	# pinned as bands. SPAWN_COUPLE_TICKS is a plain delay, not a condition (every wheel grounded for N
	# consecutive ticks): a condition can fail to come true and leave the rig running bobtail forever.
	assert_int(TowHost.SPAWN_COUPLE_TICKS) \
		.override_failure_message("long enough for the chassis to rise on its springs") \
		.is_between(5, 45)
	# The watch has to outlive the tick or two a first contact can take to be reported, and end well
	# before ordinary driving (grounding out over a crest) could trip it.
	assert_int(TowHost.COUPLE_WATCH_TICKS) \
		.override_failure_message("the watch must not outlast the driver's first corner") \
		.is_between(2, 30)


func test_every_trailer_stands_on_RAYCASTS_so_a_body_contact_really_does_mean_stuck() -> void:
	# The assumption the whole fit check rests on, asserted rather than trusted: a semi-trailer is held
	# up by RayWheels, which are raycasts and not shapes, so its collision body touches nothing in
	# normal towing. That is what makes "any body contact" exact. Give a trailer a wheel
	# CollisionShape and it would unhitch itself on spawn.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var node := _trailer(path)
		var spec: VehicleSpec = node.get("spec")
		assert_int(spec.ground_drive.wheel_positions.size()) \
			.override_failure_message("%s has no wheels" % path).is_greater(0)
		# The body's own shapes must exist (or nothing can ever report a contact) and none of them
		# may belong to a wheel — a wheel shape would rest on the road and unhitch the rig on spawn.
		var shapes := node.find_children("*", "CollisionShape3D", true, false)
		assert_int(shapes.size()) \
			.override_failure_message("%s has no body collision at all" % path).is_greater(0)
		for s: CollisionShape3D in shapes:
			assert_bool(String(s.name).to_lower().contains("wheel")) \
				.override_failure_message(
					"%s: %s is a wheel shape - the body-contact fit check would fire on the road"
					% [path, s.name]) \
				.is_false()
		node.free()


func test_the_trailer_reports_its_contacts_or_the_fit_check_is_blind() -> void:
	# body_is_colliding reads get_colliding_bodies(), which returns nothing at all unless the body is
	# monitoring contacts. Set in _ready rather than per scene, and asserted here because the failure
	# mode is silent: no error, no contacts, every coupling accepted forever.
	assert_int(TowedBodyScript.MAX_CONTACTS_REPORTED) \
		.override_failure_message("the fit check needs at least one contact reported").is_greater(0)
	var found := false
	var script: Script = load("res://src/vehicles/base/towed_body.gd")
	for m: Dictionary in script.get_script_method_list():
		if String(m["name"]) == "body_is_colliding":
			found = true
	assert_bool(found).override_failure_message("body_is_colliding is gone").is_true()


func test_the_showroom_hook_is_duck_typed_and_pins_the_trailer_too() -> void:
	# The garage freezes its vehicle and hovers it off the floor; a vehicle that owns other bodies
	# has to pin those with it. The hook is asked of the VEHICLE (garage.gd duck-types it there) and
	# handed to the coupling. `_fifth_wheel` is set by hand because it is resolved in _ready.
	var semi := _semi()
	assert_bool(semi.has_method("set_display_frozen")) \
		.override_failure_message("the garage would not be able to pin the trailer").is_true()
	var host := semi.get_node("FifthWheel")
	semi.set("_fifth_wheel", host)
	var trailer := _trailer(BOX)
	host.set("trailer", trailer)
	semi.call("set_display_frozen", true)
	assert_bool(trailer.get("freeze")) \
		.override_failure_message("the showroom left the trailer falling").is_true()
	assert_int(trailer.get("freeze_mode")).is_equal(RigidBody3D.FREEZE_MODE_KINEMATIC)
	# ...and driving away un-pins it, or the rig would tow a kinematic block.
	semi.call("set_display_frozen", false)
	assert_bool(trailer.get("freeze")).is_false()
	trailer.free()
	semi.free()


# --- what the touch overlay is offered --------------------------------------------------------

func test_the_attachment_controls_are_the_trailers_own_declaration() -> void:
	# The touch PTO/TIP buttons are offered by capability, and the capability read is the same
	# TowedBody.consumers() the gating reads, not a second list. Still asked of the VEHICLE (boot.gd
	# duck-types it there). `_fifth_wheel` is set by hand because it is resolved in _ready.
	var semi := _semi()
	var host := semi.get_node("FifthWheel")
	semi.set("_fifth_wheel", host)
	for path in [TIPPER, BOX, TANKER, FLATBED]:
		var trailer := _trailer(path)
		host.set("trailer", trailer)
		var controls: Dictionary = semi.call("attachment_controls")
		assert_bool(controls.get("pto", false)) \
			.override_failure_message("%s: PTO button does not match its declaration" % path) \
			.is_equal(trailer.call("uses", TowedBody.Consumer.PTO))
		assert_bool(controls.get("lift", false)) \
			.override_failure_message("%s: TIP button does not match its declaration" % path) \
			.is_equal(trailer.call("uses", TowedBody.Consumer.HYDRAULIC))
		trailer.free()
	var tipper := _trailer(TIPPER)
	host.set("trailer", tipper)
	var tip_controls: Dictionary = semi.call("attachment_controls")
	assert_bool(tip_controls["pto"]).is_true()
	assert_bool(tip_controls["lift"]).is_true()
	tipper.free()
	host.set("trailer", null)
	assert_bool((semi.call("attachment_controls") as Dictionary).is_empty()) \
		.override_failure_message("bobtail must offer no attachment controls").is_true()
	semi.free()


func test_the_shell_hook_is_duck_typed_and_the_semi_answers_it() -> void:
	# boot.gd finds this by name, exactly like cycle_implement, so nothing in the shell learns what
	# a trailer is. A rename here silently takes the buttons away.
	var semi := _semi()
	assert_bool(semi.has_method("attachment_controls")) \
		.override_failure_message("the shell would find no attachment controls on the semi").is_true()
	semi.free()
	var bin := (load(CatalogScript.scene_of("garbage-truck")) as PackedScene).instantiate()
	assert_bool(bin.has_method("attachment_controls")) \
		.override_failure_message("the garbage truck must not offer attachment controls").is_false()
	bin.free()


# --- the tipper: the interlock, and what tipping does to the load -----------------------------

func test_the_raise_interlock_wants_the_brake_set_and_the_rig_stopped() -> void:
	# Both conditions, and BOTH are required — the predicate is an AND, so neither alone opens it.
	assert_bool(TowedBody.body_raise_allowed(0.0, 1.0)) \
		.override_failure_message("parked with the brake on must permit a raise").is_true()
	assert_bool(TowedBody.body_raise_allowed(0.0, 0.0)) \
		.override_failure_message("stopped is not parked: the brake has to be set").is_false()
	assert_bool(TowedBody.body_raise_allowed(6.0, 1.0)) \
		.override_failure_message("rolling with the brake half on must still refuse").is_false()
	# Reversing is moving: the sign of the road speed cannot buy a raise.
	assert_bool(TowedBody.body_raise_allowed(-6.0, 1.0)).is_false()
	# The parking brake is a 0..1 application, and a brush of it is not "set".
	assert_bool(TowedBody.body_raise_allowed(0.0, 0.2)).is_false()
	assert_bool(TowedBody.body_raise_allowed(0.0, TowedBody.RAISE_PARK_BRAKE_MIN)).is_true()


func test_the_tipper_interlock_is_stricter_than_the_refuse_arms() -> void:
	# A refuse round is driven at walking pace with the arm cycling, so RefuseBody tolerates 5 km/h; a
	# tipping body is four metres of leverage going up, so it wants a genuine standstill. A tipper
	# allowed to work at the refuse arm's speed would be an interlock that means nothing.
	assert_float(TowedBody.RAISE_SPEED_MS).is_less(RefuseBody.WALK_PACE_MS)
	assert_bool(RefuseBody.is_inhibited(1.0, 1.0, true)) \
		.override_failure_message("the refuse arm is allowed to work at walking pace").is_false()
	assert_bool(TowedBody.body_raise_allowed(1.0, 1.0)) \
		.override_failure_message("the tipping body must refuse at walking pace").is_false()


func test_the_tipper_declares_the_pto_and_the_valve() -> void:
	var tipper := _trailer(TIPPER)
	assert_bool(tipper.call("uses", TowedBody.Consumer.PTO)) \
		.override_failure_message("the tipping pump runs off the chassis PTO").is_true()
	assert_bool(tipper.call("uses", TowedBody.Consumer.HYDRAULIC)).is_true()
	# The only trailer that plugs anything in, which makes the other three's zero a declaration.
	for path in [BOX, TANKER, FLATBED]:
		var other := _trailer(path)
		assert_int(other.call("consumers")) \
			.override_failure_message("%s plugs something into the towing unit" % path).is_equal(0)
		other.free()
	tipper.free()


func test_the_tipping_body_needs_the_pump_and_freezes_without_it() -> void:
	var tipper := _trailer(TIPPER)
	# Valve wide open, no PTO: no pump, so nothing moves however long it is left.
	tipper.call("set_pto", false, 0)
	tipper.call("set_valve", 1.0)
	for _i in 600:
		tipper.call("tick_body", DELTA)
	assert_float(tipper.call("body_pos01")) \
		.override_failure_message("the body rose with no pump turning").is_equal(0.0)
	# Drive it half way up, then drop the PTO: it FREEZES where it stands rather than coming home.
	tipper.call("set_pto", true, 1800)
	for _i in roundi(TipperScript.TIP_TRAVEL_S * 0.5 / DELTA):
		tipper.call("tick_body", DELTA)
	var mid: float = tipper.call("body_pos01")
	assert_float(mid).is_between(0.35, 0.65)
	tipper.call("set_pto", false, 0)
	tipper.call("set_valve", 0.0)
	for _i in 600:
		tipper.call("tick_body", DELTA)
	assert_float(tipper.call("body_pos01")) \
		.override_failure_message("losing the PTO drove the body home instead of freezing it") \
		.is_equal_approx(mid, 1e-6)
	tipper.free()


func test_the_body_rises_and_lowers_in_its_stated_time() -> void:
	var tipper := _trailer(TIPPER)
	tipper.call("set_pto", true, 1800)
	tipper.call("set_valve", 1.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		tipper.call("tick_body", DELTA)
	assert_float(tipper.call("body_pos01")).is_equal_approx(1.0, 1e-6)
	# Slow enough to be an interlock you can drive INTO rather than a snap.
	assert_float(TipperScript.TIP_TRAVEL_S).is_greater(2.0)
	tipper.call("set_valve", 0.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		tipper.call("tick_body", DELTA)
	assert_float(tipper.call("body_pos01")).is_equal_approx(0.0, 1e-6)
	tipper.free()


func test_the_raised_collision_is_the_LOWERED_box_swept_about_the_real_hinge() -> void:
	# A raised tipper used to have no collision at all: 5.2 m of body in the air passing straight
	# through a bridge. The fix is a second authored pose rather than a shape re-transformed every
	# tick, because posing a CollisionShape3D at 60 Hz rebuilds the compound and the inertia tensor on
	# the one body that also writes its own centre of mass.
	#
	# What this pins is that the second pose is the same BoxShape3D, placed exactly where a full tip
	# about TipBody's origin puts it: re-author the body, move the hinge or change TIP_MAX_DEG and this
	# fails, instead of leaving a stale box floating over the trailer.
	var tipper := _trailer(TIPPER)
	var hinge: Node3D = tipper.get_node("TipBody")
	var down: CollisionShape3D = tipper.get_node("CollisionTipBody")
	var up: CollisionShape3D = tipper.get_node("CollisionTipBodyRaised")
	assert_object(up.shape) \
		.override_failure_message("the two poses must be one box, or they can disagree").is_same(down.shape)
	var to_hinge := Transform3D(Basis.IDENTITY, hinge.position)
	var swept := to_hinge * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(TipperScript.TIP_MAX_DEG))) \
			* to_hinge.affine_inverse() * down.transform
	assert_vector(up.transform.origin) \
		.override_failure_message("the raised box is not where a full tip puts the lowered one") \
		.is_equal_approx(swept.origin, Vector3.ONE * 2e-4)
	assert_float(up.transform.basis.get_euler().x) \
		.override_failure_message("the raised box is not tipped through TIP_MAX_DEG") \
		.is_equal_approx(swept.basis.get_euler().x, 1e-4)
	# At rest the LOWERED pose is the live one — a trailer that spawned with its raised box enabled
	# would sit inside its own collision.
	assert_bool(down.disabled).override_failure_message("the parked pose must be the live one").is_false()
	assert_bool(up.disabled).override_failure_message("the raised pose must spawn disabled").is_true()
	tipper.free()


func test_the_collision_swaps_ONCE_a_tip_and_will_not_dither_on_the_threshold() -> void:
	# Two rebuilds a tip instead of sixty a second is why the raised box is a second authored shape, so
	# the hysteresis is the feature: a proportional spool parked between the two thresholds holds
	# whichever pose it arrived in rather than churning the compound every frame.
	assert_float(TipperScript.RAISED_OFF).is_less(TipperScript.RAISED_ON)
	assert_float(TipperScript.RAISED_OFF).is_between(0.05, 0.95)
	assert_float(TipperScript.RAISED_ON).is_between(0.05, 0.95)
	var tipper := _trailer(TIPPER)
	var down: CollisionShape3D = auto_free(CollisionShape3D.new())
	var up: CollisionShape3D = auto_free(CollisionShape3D.new())
	up.disabled = true
	tipper.set("_col_down", down)
	tipper.set("_col_up", up)
	for tip: float in [0.0, TipperScript.RAISED_OFF + 0.01, TipperScript.RAISED_ON - 0.01]:
		tipper.set("_tip", tip)
		tipper.call("_swap_collision")
		assert_bool(up.disabled) \
			.override_failure_message("the raised box came in at %.2f, below the threshold" % tip).is_true()
	tipper.set("_tip", 1.0)
	tipper.call("_swap_collision")
	assert_bool(up.disabled).override_failure_message("a fully raised body has no collision").is_false()
	assert_bool(down.disabled).override_failure_message("both poses are live at once").is_true()
	tipper.set("_tip", TipperScript.RAISED_ON - 0.01)
	tipper.call("_swap_collision")
	assert_bool(up.disabled).override_failure_message("the pose dithered inside the band").is_false()
	tipper.set("_tip", TipperScript.RAISED_OFF - 0.01)
	tipper.call("_swap_collision")
	assert_bool(up.disabled).override_failure_message("the body never came back to its parked pose").is_true()
	assert_bool(down.disabled).is_false()
	tipper.free()


func test_tipping_walks_the_load_off_the_fifth_wheel_and_onto_the_bogie() -> void:
	# A real centre of mass rather than a term added to a signal. Tipping slides the payload toward the
	# tailgate, so the fifth wheel's share falls and the bogie's rises: trailer_axle_load up and the
	# tractor's axle_load down, both read out of springs that really carry the difference.
	var tipper := _trailer(TIPPER)
	var spec: VehicleSpec = tipper.get("spec")
	var parked_share: float = tipper.call("live_kingpin_share")
	assert_float(parked_share).is_equal_approx(tipper.call("kingpin_share"), 1e-9)

	tipper.call("set_pto", true, 1800)
	tipper.call("set_valve", 1.0)
	var prev := parked_share
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		tipper.call("tick_body", DELTA)
		var now: float = tipper.call("live_kingpin_share")
		# Monotone: the load walks back, it never sloshes on the way.
		assert_float(now).is_less_equal(prev + 1e-9)
		prev = now

	assert_float(tipper.call("load_shift_z")).is_equal_approx(TipperScript.TIP_COM_SHIFT_Z, 1e-6)
	assert_vector(tipper.get("center_of_mass")) \
		.is_equal_approx(spec.center_of_mass + Vector3(0, 0, TipperScript.TIP_COM_SHIFT_Z),
			Vector3.ONE * 1e-5)

	var tipped_share: float = tipper.call("live_kingpin_share")
	assert_float(tipped_share) \
		.override_failure_message("tipping left %.1f%% on the plate, down from %.1f%% — no shift"
			% [tipped_share * 100.0, parked_share * 100.0]) \
		.is_less(parked_share * 0.5)
	# Both axle loads move, in tonnes rather than kilos: this is what you watch on the cluster.
	var moved_kg: float = spec.mass * (parked_share - tipped_share)
	assert_float(moved_kg) \
		.override_failure_message("only %.0f kg moved between the axles" % moved_kg) \
		.is_greater(2000.0)
	assert_float(_bogie_travel(spec, tipped_share)) \
		.override_failure_message("the tipper bottoms its springs at full tip").is_less(0.75)
	tipper.free()


func test_a_respawn_brings_the_body_and_its_load_home() -> void:
	# reset_at re-lays the trailer; a body left up and a payload left shifted would make respawn a
	# way to keep weight where the driver never put it (and to teleport four metres of steel).
	var tipper := _trailer(TIPPER)
	tipper.call("set_pto", true, 1800)
	tipper.call("set_valve", 1.0)
	for _i in roundi(TipperScript.TIP_TRAVEL_S / DELTA):
		tipper.call("tick_body", DELTA)
	assert_float(tipper.call("body_pos01")).is_greater(0.9)
	tipper.call("reset_at", Transform3D(Basis.IDENTITY, Vector3(4, 1, -7)))
	assert_float(tipper.call("body_pos01")).is_equal(0.0)
	assert_float(tipper.call("load_shift_z")).is_equal(0.0)
	assert_float(tipper.call("live_kingpin_share")).is_equal_approx(tipper.call("kingpin_share"), 1e-9)
	tipper.free()


func test_the_ram_aims_along_its_own_axis() -> void:
	# The ram's pose is built from an aim basis rather than a look_at, because a cylinder's axis is its
	# local +Y and looking_at points -Z. An unnormalized or left-handed basis here shears the ram.
	for dir in [Vector3.UP, Vector3(0.0, 0.6, 0.8).normalized(), Vector3.RIGHT, Vector3.FORWARD]:
		var aimed: Basis = TipperScript._aim_y(dir)
		assert_vector(aimed.y).is_equal_approx(dir, Vector3.ONE * 1e-5)
		assert_float(aimed.determinant()) \
			.override_failure_message("the ram basis is not right-handed and unit").is_equal_approx(1.0, 1e-5)
		assert_float(aimed.x.dot(aimed.y)).is_equal_approx(0.0, 1e-6)
		assert_float(aimed.y.dot(aimed.z)).is_equal_approx(0.0, 1e-6)


# --- the tanker: a labelled model of a shifting centre of mass ---------------------------------

func test_the_surge_runs_forward_under_braking_and_back_under_power() -> void:
	# The sign is the whole feel of the vehicle and is easy to get backwards: +z is rearward in the
	# trailer's own frame (the origin is the kingpin), so speeding up slumps the load back onto the
	# bogie and braking throws it forward onto the fifth wheel.
	assert_float(TankerScript.surge_target(0.0)).is_equal(0.0)
	assert_float(TankerScript.surge_target(2.0)).is_greater(0.0)
	assert_float(TankerScript.surge_target(-2.0)).is_less(0.0)
	# Symmetric, and saturating: the load runs out of barrel rather than out of the trailer.
	assert_float(TankerScript.surge_target(-2.0)).is_equal(-TankerScript.surge_target(2.0))
	assert_float(TankerScript.surge_target(50.0)).is_equal(TankerScript.SURGE_TRAVEL)
	assert_float(TankerScript.surge_target(-50.0)).is_equal(-TankerScript.SURGE_TRAVEL)
	# A firm brake application reaches the end of the travel, or the model would never be seen.
	assert_float(absf(TankerScript.surge_target(-3.0))).is_equal(TankerScript.SURGE_TRAVEL)


func test_the_surge_is_late_and_that_lateness_is_the_model() -> void:
	# A slug of liquid does not arrive with the pedal. The lag is the one property of a real surge that
	# matters here: full travel takes SURGE_TIME and no single tick jumps.
	var s := 0.0
	var target := TankerScript.SURGE_TRAVEL
	var steps := roundi(TankerScript.SURGE_TIME / DELTA)
	for _i in steps:
		var next := TankerScript.surge_step(s, target, DELTA)
		assert_float(next - s).is_less_equal(TankerScript.SURGE_TRAVEL * DELTA / TankerScript.SURGE_TIME + 1e-9)
		s = next
	assert_float(s).is_equal_approx(target, 1e-6)
	assert_float(TankerScript.surge_step(s, target, 10.0)).is_equal(target)
	# Slower than the brake application that causes it — that is what makes it readable.
	assert_float(TankerScript.SURGE_TIME).is_greater(0.5)


func test_a_braking_tanker_puts_its_load_on_the_fifth_wheel() -> void:
	# The consequence, through a real centre of mass: brake and the fifth wheel's share climbs (the
	# tractor's axle_load rises and its nose goes down), accelerate and the bogie takes it back.
	# Neither signal has a tanker term in it; the weight is somewhere else and the springs report it.
	var tanker := _trailer(TANKER)
	var rest: float = tanker.call("live_kingpin_share")
	assert_float(rest).is_equal_approx(tanker.call("kingpin_share"), 1e-9)

	tanker.set("accel_fwd", -4.0)  # a firm stop
	for _i in roundi(TankerScript.SURGE_TIME / DELTA):
		tanker.call("tick_body", DELTA)
	var braking: float = tanker.call("live_kingpin_share")
	assert_float(tanker.call("load_shift_z")).is_equal_approx(-TankerScript.SURGE_TRAVEL, 1e-6)
	assert_float(braking) \
		.override_failure_message("braking did not move the load onto the plate").is_greater(rest)

	tanker.set("accel_fwd", 4.0)   # hard away
	for _i in roundi(2.0 * TankerScript.SURGE_TIME / DELTA):
		tanker.call("tick_body", DELTA)
	var pulling: float = tanker.call("live_kingpin_share")
	assert_float(pulling).is_less(rest)
	# Worth tonnes at each end, or it is a number nothing on the cluster could show.
	var spec: VehicleSpec = tanker.get("spec")
	assert_float(spec.mass * (braking - pulling)) \
		.override_failure_message("the surge moves only %.0f kg between the axles"
			% (spec.mass * (braking - pulling))) \
		.is_greater(2000.0)
	# And the bogie stays on its springs at both ends of the travel, which the spec's rate was sized
	# for.
	assert_float(_bogie_travel(spec, braking)).is_between(0.2, 0.6)
	assert_float(_bogie_travel(spec, pulling)).is_between(0.2, 0.6)
	tanker.free()


func test_the_tanker_is_a_load_model_and_not_a_body() -> void:
	# It moves its own centre of mass and plugs nothing into the towing unit: no PTO, no valve, and
	# nothing for the raise interlock to clamp.
	var tanker := _trailer(TANKER)
	assert_int(tanker.call("consumers")).is_equal(0)
	assert_float(tanker.call("body_pos01")).is_equal(0.0)
	# A respawn puts the load back amidships, and the model's own state with it — otherwise the next
	# tick slews out from a number the reset never cleared.
	tanker.set("accel_fwd", -4.0)
	for _i in roundi(TankerScript.SURGE_TIME / DELTA):
		tanker.call("tick_body", DELTA)
	assert_float(absf(tanker.call("load_shift_z"))).is_greater(0.1)
	tanker.call("reset_at", Transform3D(Basis.IDENTITY, Vector3.ZERO))
	assert_float(tanker.call("load_shift_z")).is_equal(0.0)
	assert_float(tanker.get("accel_fwd")).is_equal(0.0)
	# ...and it stays home, because the acceleration history was cleared with it.
	tanker.call("tick_body", DELTA)
	assert_float(tanker.call("load_shift_z")).is_equal(0.0)
	tanker.free()


func test_every_trailer_declares_lamps_that_resolve_in_its_own_scene() -> void:
	# The lamp paths are resolved against the trailer, so a lens renamed in the scene (or a path copied
	# between two trailers whose rear ends later diverged) leaves that trailer dark on the road with
	# nothing to say so — LampSet tolerates every missing node by design. head_lamp_paths is asserted
	# empty on purpose: a semi-trailer has no headlamps and no beam.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var trailer := _trailer(path)
		var spec: VehicleSpec = trailer.get("spec")
		assert_array(spec.head_lamp_paths) 			.override_failure_message("%s declares headlamps; a trailer has none" % path).is_empty()
		var groups := {
			"brake_lamp_paths": spec.brake_lamp_paths,
			"turn_left_paths": spec.turn_left_paths,
			"turn_right_paths": spec.turn_right_paths,
			"steady_lamp_paths": spec.steady_lamp_paths,
		}
		for group_name in groups:
			var paths: Array[NodePath] = groups[group_name]
			assert_array(paths) 				.override_failure_message("%s declares no %s" % [path, group_name]).is_not_empty()
			for lens_path in paths:
				assert_object(trailer.get_node_or_null(lens_path)) 					.override_failure_message("%s: %s -> %s resolves to nothing" % [
						path, group_name, lens_path]) 					.is_instanceof(MeshInstance3D)
		trailer.free()


## A marker lens is a surface override, not a material_override: LampSet._bind_scene_colored gives
## each marker a private duplicate of its own surface material so the scene's colour survives,
## while head/brake/turn each share one canonical material assigned wholesale. Read the wrong one
## back and a lens that is lit correctly reports `null`.
func _marker_mat(mesh: MeshInstance3D) -> BaseMaterial3D:
	return mesh.get_surface_override_material(0) as BaseMaterial3D


func test_a_trailers_lamps_light_from_the_bits_the_tractor_hands_down() -> void:
	# The same brake_lamp / turn bits that light the tractor light the trailer, with no signal of their
	# own and no timer. Asserted on the material the set binds, and per-lens, so an indicator wired to
	# both sides fails here rather than in the mirror.
	for path in Catalog.TRAILERS:
		if not Catalog.is_coupled(path):
			continue
		var trailer := _trailer(path)
		var spec: VehicleSpec = trailer.get("spec")
		var lamps := LampSet.new()
		lamps.setup(trailer, spec)
		var tail := trailer.get_node(spec.brake_lamp_paths[0]) as MeshInstance3D
		var turn_l := trailer.get_node(spec.turn_left_paths[0]) as MeshInstance3D
		var turn_r := trailer.get_node(spec.turn_right_paths[0]) as MeshInstance3D
		var marker := trailer.get_node(spec.steady_lamp_paths[0]) as MeshInstance3D
		# Every lens is on a PRIVATE override, so nothing here can mutate the scene's shared lens
		# material — which is the same resource on all four of this trailer's rear lamps.
		for lens in [tail, turn_l, turn_r]:
			assert_object(lens.material_override) 				.override_failure_message("%s: %s got no lamp material" % [path, lens.name]) 				.is_not_null()
		assert_object(_marker_mat(marker)) 			.override_failure_message("%s: %s got no lamp material" % [path, marker.name]) 			.is_not_null()
		assert_object(turn_l.material_override).is_not_same(turn_r.material_override)

		lamps.apply(false, LampSet.HL_OFF, false, false)
		var tail_dark: float = tail.material_override.emission_energy_multiplier
		var marker_dark: float = _marker_mat(marker).emission_energy_multiplier
		# is_equal_approx, not is_equal: emission_energy_multiplier is stored as float32 and these
		# constants are float64 literals, so an exact compare fails with two identical-looking numbers.
		assert_float(tail_dark).is_equal_approx(LampSet.REAR_ENERGY[LampSet.Rear.OFF], 1e-5)

		# The stop lamp is the bit, not the pedal — brake_lamp arrives already decided.
		lamps.apply(true, LampSet.HL_OFF, false, false)
		assert_float(tail.material_override.emission_energy_multiplier) 			.override_failure_message("%s: stop lamp did not light" % path).is_greater(tail_dark)

		# Headlights on: the tail tier and the markers come up together, still no stop lamp.
		lamps.apply(false, LampSet.HL_LOW, false, false)
		assert_float(tail.material_override.emission_energy_multiplier) 			.is_equal_approx(LampSet.REAR_ENERGY[LampSet.Rear.TAIL], 1e-5)
		assert_float(_marker_mat(marker).emission_energy_multiplier) 			.override_failure_message("%s: markers stayed dark" % path).is_greater(marker_dark)

		# ONE side at a time, which is what makes it an indicator rather than a hazard.
		lamps.apply(false, LampSet.HL_OFF, true, false)
		assert_float(turn_l.material_override.emission_energy_multiplier) 			.is_equal_approx(LampSet.TURN_ON_ENERGY, 1e-5)
		assert_float(turn_r.material_override.emission_energy_multiplier) 			.override_failure_message("%s: the right indicator lit with the left" % path) 			.is_equal_approx(LampSet.TURN_OFF_ENERGY, 1e-5)
		trailer.free()
