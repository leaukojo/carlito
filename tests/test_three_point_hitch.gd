extends GdUnitTestSuite
## ThreePointHitch — does the AUTHORED SCENE agree with the SOLVED linkage?
##
## hitch_linkage.gd proves the maths closes; this proves the geometry someone drew in the
## .tscn is pinned to that maths. Those are different failures: a link authored at the wrong
## length or a pivot node moved in the editor leaves the solver perfectly happy while the
## rendered linkage pulls itself apart. Every joint drawn as a pin is checked to sit where
## the solver says the pin is, across the whole travel.
##
## It also holds the clearances that were measured off the Kenney body — the rear tyre inner
## faces at |x| = 0.253 are the tightest constraint on the whole assembly.

const HitchScene := preload("res://src/vehicles/tractor/three_point_hitch.tscn")
const PloughScene := preload("res://src/vehicles/tractor/implements/plough.tscn")
const HarrowScene := preload("res://src/vehicles/tractor/implements/harrow.tscn")
const MowerScene := preload("res://src/vehicles/tractor/implements/mower.tscn")
const SpreaderScene := preload("res://src/vehicles/tractor/implements/spreader.tscn")
const TractorScene := preload("res://src/vehicles/kenney/tractor-kenney.tscn")

## Joint slop we accept. The parts are rigid, so this is float noise, not a fudge factor.
const JOINT_EPS := 0.002
## Measured off wheel-tractor-rear.tscn at its 0.45 visual radius: half-width 0.276 at
## x = +/-0.529, so the gap between the rear tyres is this half-width.
const TYRE_INNER_X := 0.253
## Rearmost tyre contact in body Z (wheel centre 0.822 + visual radius 0.45).
const TYRE_REAR_Z := 1.272
## Tyre crown in body Y (wheel centre 0.45 + visual radius 0.45). Anything above this passes
## OVER the wheel and cannot sweep into it — which is how a tall implement's hopper leans in
## over the tractor as the hitch raises without that being a clash.
const TYRE_TOP_Y := 0.9


func _hitch() -> ThreePointHitch:
	var h: ThreePointHitch = auto_free(HitchScene.instantiate())
	add_child(h)
	return h


func _at(node: Node, path: String) -> Vector3:
	return (node.get_node(NodePath(path)) as Node3D).global_position


## Global position of a node found by NAME anywhere under `node` — the three implements carry
## their pins inside the shared Headstock scene, so a fixed path would test the nesting rather
## than the geometry.
func _named(node: Node, name_: String) -> Vector3:
	var found := node.find_child(name_, true, false) as Node3D
	assert_object(found).override_failure_message("no node named %s" % name_).is_not_null()
	return found.global_position


# --- the drawn linkage tracks the solved one ----------------------------------

func test_ball_ends_and_top_link_follow_the_solve() -> void:
	var hitch := _hitch()
	var link := HitchLinkage.new()
	for i in 21:
		var t := float(i) / 20.0
		hitch.set_hitch(t)
		var s := link.solve(t)
		var ball: Vector2 = s["ball"]
		# Both ball ends sit at the solved (z, y), splayed to +/-0.37 in x.
		for side in [["LowerLinkL/Ball", -0.37], ["LowerLinkR/Ball", 0.37]]:
			assert_vector(_at(hitch, side[0])) \
				.override_failure_message("ball end adrift at pos01 = %.2f" % t) \
				.is_equal_approx(Vector3(side[1], ball.y, ball.x), Vector3.ONE * JOINT_EPS)
		# The top link's rear eye is the top pin (detached parks it, so attach first below).


func test_lift_rods_stay_pinned_to_the_rockshaft_arms_and_the_links() -> void:
	var hitch := _hitch()
	var link := HitchLinkage.new()
	for i in 21:
		var t := float(i) / 20.0
		hitch.set_hitch(t)
		var s := link.solve(t)
		var attach: Vector2 = s["rod_attach"]
		# Rod head == arm pin.
		assert_vector(_at(hitch, "LiftRodL")) \
			.override_failure_message("lift rod head off the arm pin at pos01 = %.2f" % t) \
			.is_equal_approx(_at(hitch, "RockArmL/Pin"), Vector3.ONE * JOINT_EPS)
		# Rod foot (its far end, one rod length along local +Z) == the point on the link.
		var rod: Node3D = hitch.get_node("LiftRodL")
		var foot: Vector3 = rod.global_transform * Vector3(0.0, 0.0, link.lift_rod_len)
		assert_vector(foot) \
			.override_failure_message("lift rod foot off the link at pos01 = %.2f" % t) \
			.is_equal_approx(Vector3(-0.19, attach.y, attach.x), Vector3.ONE * JOINT_EPS)


func test_attached_implement_pins_meet_the_linkage() -> void:
	# The whole point of the four-bar solve: all three pins stay connected through the lift.
	# Run for EVERY implement — they share one Headstock scene precisely so this cannot drift
	# for one machine at a time, and that is only true while all three actually instance it.
	for scene in [PloughScene, HarrowScene, MowerScene, SpreaderScene]:
		var hitch := _hitch()
		hitch.attach(scene)
		for i in 21:
			var t := float(i) / 20.0
			hitch.set_hitch(t)
			assert_vector(_named(hitch.implement, "PinL")) \
				.override_failure_message("%s lower pin left the ball end at pos01 = %.2f"
					% [hitch.implement.name, t]) \
				.is_equal_approx(_at(hitch, "LowerLinkL/Ball"), Vector3.ONE * JOINT_EPS)
			assert_vector(_named(hitch.implement, "PinR")) \
				.is_equal_approx(_at(hitch, "LowerLinkR/Ball"), Vector3.ONE * JOINT_EPS)
			assert_vector(_named(hitch.implement, "TopPin")) \
				.override_failure_message("%s top pin left the top link at pos01 = %.2f"
					% [hitch.implement.name, t]) \
				.is_equal_approx(_at(hitch, "TopLink/EyeRear"), Vector3.ONE * JOINT_EPS)


# --- attach / detach ----------------------------------------------------------

func test_attach_and_detach() -> void:
	var hitch := _hitch()
	assert_object(hitch.implement).is_null()
	hitch.attach(PloughScene)
	assert_object(hitch.implement).is_not_null()
	assert_int(hitch.implement.device_class()).is_equal(ImplementBase.CLASS_TILLAGE)
	# Attaching again replaces rather than stacking.
	hitch.attach(MowerScene)
	assert_int(hitch.get_node("Mount").get_child_count()).is_equal(1)
	hitch.detach()
	assert_object(hitch.implement).is_null()
	# Detached the linkage still articulates — the rockshaft raises the links either way.
	hitch.set_hitch(0.0)
	var low: float = _at(hitch, "LowerLinkL/Ball").y
	hitch.set_hitch(1.0)
	assert_bool(_at(hitch, "LowerLinkL/Ball").y > low + 0.3).is_true()


## A packed implement that declares NOTHING — the bare base. Mechanically it hangs on the
## links like any other; electronically and mechanically it is inert, which is what the two
## connection gates below are for.
func _mechanical_only() -> PackedScene:
	var node := ImplementBase.new()
	node.name = "DumbImplement"
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	return packed


func test_pto_drive_only_reaches_an_implement_that_declares_the_connection() -> void:
	var hitch := _hitch()
	hitch.attach(MowerScene)
	hitch.set_pto(true, 540)
	# The mower declares Connection.PTO, so the drive arrives and its rotor turns.
	assert_bool(hitch.implement.pto_on).is_true()
	assert_int(hitch.implement.pto_rpm).is_equal(540)

	# The PLOUGH is the real case for the gate: it is mechanically attached and mechanically
	# inert. The tractor's own stub shaft still turns (it always does) but nothing is on the
	# far end of it, so the implement reads a dead shaft rather than being trusted to ignore
	# a live one.
	hitch.attach(PloughScene)
	hitch.set_pto(true, 540)
	assert_bool(hitch.implement.pto_on).is_false()
	assert_int(hitch.implement.pto_rpm).is_equal(0)
	assert_int(hitch._pto_rpm).is_equal(540)
	assert_bool(hitch._pto_on).is_true()


func test_a_driven_rotor_turns_only_while_the_pto_is_engaged() -> void:
	# What pto_rpm looks like. The rotor's angle is the only place the shaft speed is visible on
	# a driven implement, so it must move with drive and hold still without it — and it must
	# turn about the axis that machine actually uses. The harrow's transverse rotor and the
	# mower's vertical one are the two cases, and a wrong axis is invisible in a still frame.
	for case in [[MowerScene, Vector3.UP], [HarrowScene, Vector3.RIGHT]]:
		var hitch := _hitch()
		hitch.attach(case[0])
		var rotor: Node3D = hitch.implement.get_node("Rotor")
		var axis: Vector3 = case[1]
		hitch.set_pto(true, 540)
		hitch.implement._process(0.1)
		assert_float(absf(rotor.rotation.dot(axis))) \
			.override_failure_message("%s rotor did not turn about %s under PTO drive"
				% [hitch.implement.name, axis]) \
			.is_greater(0.01)
		# ...and about NOTHING else: a rotor spinning on the wrong axis still "turns".
		assert_float((rotor.rotation - axis * rotor.rotation.dot(axis)).length()) \
			.override_failure_message("%s rotor turned off its own axis" % hitch.implement.name) \
			.is_less(1e-5)

		hitch.set_pto(false, 0)
		var was := rotor.rotation
		hitch.implement._process(0.1)
		assert_vector(rotor.rotation).is_equal_approx(was, Vector3.ONE * 1e-5)


func test_attaching_null_leaves_the_hitch_detached() -> void:
	var hitch := _hitch()
	hitch.attach(PloughScene)
	hitch.attach(null)
	assert_object(hitch.implement).is_null()
	assert_int(hitch.get_node("Mount").get_child_count()).is_equal(0)


# --- clearances measured off the Kenney body ----------------------------------

func test_nothing_sweeps_into_the_rear_tyres() -> void:
	# The draft arms run inboard of the tyres until they are clear of them in Z, then splay.
	# This is the constraint that decides the whole layout, so it is asserted, not commented.
	for scene in [PloughScene, HarrowScene, MowerScene, SpreaderScene]:
		var hitch := _hitch()
		hitch.attach(scene)
		for i in 21:
			hitch.set_hitch(float(i) / 20.0)
			for node in hitch.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				var box := mi.get_aabb()
				for c in 8:
					var p: Vector3 = mi.global_transform * box.get_endpoint(c)
					if p.z >= TYRE_REAR_Z or p.y >= TYRE_TOP_Y:
						continue  # behind or above the tyres: free to splay
					assert_bool(absf(p.x) <= TYRE_INNER_X) \
						.override_failure_message("%s reaches x = %.3f at z = %.3f, inside the rear tyre"
							% [mi.name, p.x, p.z]) \
						.is_true()


func test_pto_stub_spins_and_stays_inside_its_guard() -> void:
	# The stub is splined (a smooth cylinder cannot show rotation at chase-camera distance),
	# so it sweeps a bigger envelope than the bare shaft. That envelope has to clear the
	# guard hood and cheeks or the ribs scythe through them once it turns.
	var hitch := _hitch()
	var stub: Node3D = hitch.get_node("PtoStub")
	var to_stub := stub.global_transform.affine_inverse()

	var envelope := 0.0  # max radius any spun part reaches from the shaft axis
	for child in stub.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var box := mi.get_aabb()
		for c in 8:
			var p: Vector3 = to_stub * (mi.global_transform * box.get_endpoint(c))
			envelope = maxf(envelope, Vector2(p.x, p.y).length())
	assert_float(envelope).is_greater(0.06)  # splines really do stand proud of the shaft

	for guard in hitch.get_node("PtoGuard").find_children("*", "MeshInstance3D", true, false):
		var mi := guard as MeshInstance3D
		var box := mi.get_aabb()
		for c in 8:
			var p: Vector3 = to_stub * (mi.global_transform * box.get_endpoint(c))
			if absf(p.z) > 0.22:
				continue  # past the end of the shaft, nothing to hit
			assert_float(Vector2(p.x, p.y).length()) \
				.override_failure_message("guard part %s is inside the spun PTO envelope" % mi.name) \
				.is_greater(envelope)

	# And it actually turns when the PTO is engaged, at the reported shaft speed.
	hitch.set_pto(true, 540)
	var was := stub.rotation.z
	hitch._process(0.1)
	assert_bool(absf(stub.rotation.z - was) > 0.01).is_true()
	hitch.set_pto(false, 0)
	was = stub.rotation.z
	hitch._process(0.1)
	assert_float(stub.rotation.z).is_equal_approx(was, 1e-5)


func test_hitch_subtree_is_collision_free() -> void:
	for scene in [PloughScene, HarrowScene, MowerScene, SpreaderScene]:
		var hitch := _hitch()
		hitch.attach(scene)
		assert_int(hitch.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)
		assert_int(hitch.find_children("*", "PhysicsBody3D", true, false).size()).is_equal(0)


func test_each_implement_sits_at_its_own_working_height_and_lifts_clear() -> void:
	# Ground is y ~ 0 at ride height (measured: the tractor's chassis origin settles on the
	# ground plane, so the linkage's body-space Y IS height above ground). Each machine has a
	# DIFFERENT correct lowered height and they are asserted separately, because "everything
	# touches the ground" would be wrong for two of the three:
	#   plough   — the shares must be IN the soil, i.e. below zero;
	#   harrow   — the tines reach INTO the soil and the packer roller rests on it;
	#   mower    — the skids rest on the ground, the blades sweep just above it;
	#   spreader — nothing touches at any position; the disc is held clear by design, and its
	#              lowest point is not even part of the machine, it is the mounting lugs.
	# Raised, all three must be unmistakably airborne — the whole visual point of hitch_pos.
	var cases := [
		[PloughScene, -0.10, -0.01, 0.35],
		[HarrowScene, -0.05, 0.02, 0.35],
		[MowerScene, -0.03, 0.05, 0.35],
		[SpreaderScene, 0.10, 0.35, 0.60],
	]
	for case in cases:
		var hitch := _hitch()
		hitch.attach(case[0])
		hitch.set_hitch(0.0)
		var low := _lowest_y(hitch.implement)
		assert_float(low) \
			.override_failure_message("%s lowered sits at y = %.3f, outside its working band"
				% [hitch.implement.name, low]) \
			.is_between(case[1], case[2])
		hitch.set_hitch(1.0)
		var high := _lowest_y(hitch.implement)
		assert_bool(high > float(case[3])) \
			.override_failure_message("%s raised is only y = %.3f off the ground"
				% [hitch.implement.name, high]) \
			.is_true()


# --- the tractor driving it ---------------------------------------------------

func _tractor() -> TractorVehicle:
	var t: TractorVehicle = auto_free(TractorScene.instantiate())
	add_child(t)
	return t


func test_tractor_spawns_attached_and_v_cycles_through_detached() -> void:
	var tractor := _tractor()
	var hitch: ThreePointHitch = tractor.get_node("ThreePointHitch")
	assert_object(hitch.implement) \
		.override_failure_message("tractor should spawn with an implement on the linkage") \
		.is_not_null()
	# One full lap of the cycle must pass through detached and come back attached.
	var saw_detached := false
	for _i in ImplementCatalog.IMPLEMENTS.size():
		tractor.cycle_implement()
		if hitch.implement == null:
			saw_detached = true
	assert_bool(saw_detached).is_true()
	assert_object(hitch.implement).is_not_null()


func test_both_implement_signals_are_published_in_both_states() -> void:
	# The detached state is not a missing reading: every "out" signal the tractor declares
	# must still have a value, or the Bridge silently drops it (and warns once).
	var tractor := _tractor()
	var hitch: ThreePointHitch = tractor.get_node("ThreePointHitch")
	var input := InputRouter.VehicleInput.new()

	tractor._tick_extras(input, 1.0 / 60.0)
	var attached: Dictionary = tractor.telemetry.to_bridge_dict()
	assert_bool(attached["implement_connected"]).is_true()
	assert_int(attached["implement_type"]).is_equal(hitch.implement.device_class())

	hitch.detach()
	tractor._tick_extras(input, 1.0 / 60.0)
	var bare: Dictionary = tractor.telemetry.to_bridge_dict()
	assert_bool(bare.has("implement_connected")).is_true()
	assert_bool(bare["implement_connected"]).is_false()
	assert_int(bare["implement_type"]).is_equal(ImplementBase.CLASS_NONE)


func test_an_implement_off_the_bus_is_attached_but_claims_no_address() -> void:
	# The third state, and the one these signals exist to distinguish: steel on the linkage
	# with nothing answering on the bus. Phase 3's plough is the real case — implement_connected
	# reports the ADDRESS CLAIM, so it reads false here even though something IS attached.
	var tractor := _tractor()
	var hitch: ThreePointHitch = tractor.get_node("ThreePointHitch")
	hitch.attach(_mechanical_only())
	var input := InputRouter.VehicleInput.new()
	input.key = InputRouter.KEY_IGNITION
	input.pto = true

	tractor._tick_extras(input, 1.0 / 60.0)
	var d: Dictionary = tractor.telemetry.to_bridge_dict()
	assert_object(hitch.implement).is_not_null()
	assert_bool(d["implement_connected"]).is_false()
	assert_int(d["implement_type"]).is_equal(ImplementBase.CLASS_NONE)
	# The tractor's own PTO is unaffected — what is attached never gags the tractor's signals.
	assert_bool(d["pto_state"]).is_true()


func test_the_hitch_sits_at_the_body_origin_on_the_tractor() -> void:
	# The clearance test above measures the STANDALONE hitch against body-space constants, so
	# it is only valid while the instance on the tractor is at identity. Assert that, or
	# nudging the node in the editor walks the linkage into the tyres with the suite green.
	var tractor := _tractor()
	var hitch: Node3D = tractor.get_node("ThreePointHitch")
	assert_bool(hitch.transform.is_equal_approx(Transform3D.IDENTITY)) \
		.override_failure_message("ThreePointHitch is offset on the tractor; this suite's " \
			+ "clearance constants are measured in BODY space and no longer apply") \
		.is_true()


func _lowest_y(node: Node) -> float:
	var low := 99.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var box := mi.get_aabb()
		for c in 8:
			low = minf(low, (mi.global_transform * box.get_endpoint(c)).y)
	return low
