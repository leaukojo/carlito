extends GdUnitTestSuite
## Both towing machines asked the same questions: `SemiTractor` (fifth wheel) and
## `TractorVehicle` + `Drawbar` (pin) ride one `TowHost`, and this suite is its safety net.
##
## Pins what a refactor could silently change: the joint numbers (now `CouplingProfile` fields),
## the tip interlock's asymmetry, the coupling timings, the fit-check window.
##
## Statics and scene reads, no physics body, except the last sections - the duck-typed vehicle
## hooks and the two-body scenarios need a real chassis in a real tree.

const SemiScript := preload("res://src/vehicles/truck/semi.gd")
const DrawbarScript := preload("res://src/vehicles/tractor/drawbar.gd")
const FifthWheelScript := preload("res://src/vehicles/truck/fifth_wheel.gd")
const CatalogScript := preload("res://src/vehicles/vehicle_catalog.gd")
const TrailerCat := preload("res://src/vehicles/truck/trailer_catalog.gd")
const ImplementCat := preload("res://src/vehicles/tractor/implement_catalog.gd")

const DRAWBAR := "res://src/vehicles/tractor/drawbar.tscn"

## The raise command the tests push and the body position they push it against. 1.0 is body up,
## 0.0 is body down, so a cmd above pos01 is a raise — the only direction the interlock refuses.
const RAISE := 1.0
const DOWN := 0.0


## A towed body that answers the host's two questions without a physics space.
class StubTrailer:
	extends TowedBody

	var colliding := false
	var pos01 := 0.0
	## What this body plugs into. The collapsed interlock rule reads its PTO clause off consumers(),
	## so a road-tipper stub declares PTO | HYDRAULIC and a farm-tipper stub HYDRAULIC alone.
	var declares := 0

	func consumers() -> int:
		return declares

	func body_is_colliding() -> bool:
		return colliding

	func body_pos01() -> float:
		return pos01


var _notices: PackedStringArray = []
var _attachment_changes := 0


func _on_notice(text: String, _dwell_s: float) -> void:
	_notices.append(text)


func _on_attachment_changed() -> void:
	_attachment_changes += 1


func before_test() -> void:
	_notices = PackedStringArray()
	_attachment_changes = 0
	GameState.notice.connect(_on_notice)
	GameState.attachment_changed.connect(_on_attachment_changed)


func after_test() -> void:
	if GameState.notice.is_connected(_on_notice):
		GameState.notice.disconnect(_on_notice)
	if GameState.attachment_changed.is_connected(_on_attachment_changed):
		GameState.attachment_changed.disconnect(_on_attachment_changed)


func _semi() -> Node3D:
	return auto_free((load(CatalogScript.scene_of("semi")) as PackedScene).instantiate() as Node3D)


func _tractor() -> Node3D:
	return auto_free(
			(load(CatalogScript.scene_of("tractor-kenney")) as PackedScene).instantiate() as Node3D)


func _drawbar() -> Node3D:
	return auto_free((load(DRAWBAR) as PackedScene).instantiate() as Node3D)


## The semi's coupling: a node on the chassis, exactly as the drawbar is on the tractor.
func _fifth_wheel() -> Node3D:
	return _semi().get_node("FifthWheel") as Node3D


## A stub the code under test frees (the fit check drops it), so it is deliberately not
## auto_free'd — doing both is a double free.
func _dropped_stub() -> StubTrailer:
	return StubTrailer.new()


# --- the joint numbers, now profile fields -----------------------------------------------------

## A host joint's angular limits as { "pitch": deg, "yaw": deg, "roll": deg }, read off a joint the
## host really built rather than off the constants behind it.
func _angular_stops(joint: Generic6DOFJoint3D) -> Dictionary:
	return {
		"pitch": rad_to_deg(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
		"yaw": rad_to_deg(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
		"roll": rad_to_deg(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
	}


func test_both_hosts_lock_all_three_linear_axes() -> void:
	# A 6DOF joint says "locked" with lower == upper == 0, and the flag has to be enabled or the
	# limit is not applied at all: a kingpin that can slide off the plate looks fine standing still.
	for host: Node3D in [_fifth_wheel(), _drawbar()]:
		var joint: Generic6DOFJoint3D = auto_free(host.call("_build_joint"))
		assert_bool(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)) \
			.override_failure_message("%s: X linear limit not enabled" % host.name).is_true()
		assert_bool(joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)) \
			.override_failure_message("%s: Y linear limit not enabled" % host.name).is_true()
		assert_bool(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)) \
			.override_failure_message("%s: Z linear limit not enabled" % host.name).is_true()
		for param: int in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
				Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT]:
			assert_float(joint.get_param_x(param)) \
				.override_failure_message("%s: X linear travel is not locked" % host.name) \
				.is_equal(0.0)
			assert_float(joint.get_param_y(param)) \
				.override_failure_message("%s: Y linear travel is not locked" % host.name) \
				.is_equal(0.0)
			assert_float(joint.get_param_z(param)) \
				.override_failure_message("%s: Z linear travel is not locked" % host.name) \
				.is_equal(0.0)


func test_every_angular_stop_is_symmetric_about_zero() -> void:
	# A one-sided stop folds further one way than the other. Both hosts, all three axes.
	for host: Node3D in [_fifth_wheel(), _drawbar()]:
		var joint: Generic6DOFJoint3D = auto_free(host.call("_build_joint"))
		var lo := Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT
		var hi := Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT
		assert_float(joint.get_param_x(lo)) \
			.override_failure_message("%s: pitch folds further one way" % host.name) \
			.is_equal(-joint.get_param_x(hi))
		assert_float(joint.get_param_y(lo)) \
			.override_failure_message("%s: yaw folds further one way" % host.name) \
			.is_equal(-joint.get_param_y(hi))
		assert_float(joint.get_param_z(lo)) \
			.override_failure_message("%s: roll folds further one way" % host.name) \
			.is_equal(-joint.get_param_z(hi))


func test_the_fifth_wheels_stops_are_the_ones_it_declares() -> void:
	# Read off the built joint, not the constants, so the wiring is pinned as well as the values.
	var joint: Generic6DOFJoint3D = auto_free(_fifth_wheel().call("_build_joint"))
	var stops := _angular_stops(joint)
	assert_float(stops["pitch"]).is_equal_approx(FifthWheelScript.PITCH_LIMIT_DEG, 1e-4)
	assert_float(stops["yaw"]).is_equal_approx(Articulation.JACKKNIFE_MAX_DEG, 1e-4)
	assert_float(stops["roll"]).is_equal_approx(FifthWheelScript.ROLL_LIMIT_DEG, 1e-4)


func test_the_drawbars_stops_are_its_own_and_not_the_semis() -> void:
	var joint: Generic6DOFJoint3D = auto_free(_drawbar().call("_build_joint"))
	var stops := _angular_stops(joint)
	assert_float(stops["pitch"]).is_equal_approx(DrawbarScript.PITCH_LIMIT_DEG, 1e-4)
	assert_float(stops["yaw"]).is_equal_approx(DrawbarScript.SWING_MAX_DEG, 1e-4)
	assert_float(stops["roll"]).is_equal_approx(DrawbarScript.ROLL_LIMIT_DEG, 1e-4)
	# The yaw stop is not the semi's jackknife model: 75 deg is a trailer against a cab.
	assert_float(stops["yaw"]).is_not_equal(Articulation.JACKKNIFE_MAX_DEG)


func test_the_roll_axis_is_what_makes_a_drawbar_a_drawbar() -> void:
	# A plate under a locked kingpin holds the trailer's roll to the tractor's; a pin through an eye
	# does not. Hand both hosts the same roll stop and the drawbar silently becomes a fifth wheel.
	var plate: Generic6DOFJoint3D = auto_free(_fifth_wheel().call("_build_joint"))
	var pin: Generic6DOFJoint3D = auto_free(_drawbar().call("_build_joint"))
	var plate_roll := _angular_stops(plate)["roll"] as float
	var pin_roll := _angular_stops(pin)["roll"] as float
	assert_float(pin_roll) \
		.override_failure_message("the drawbar is as stiff in roll as a fifth wheel") \
		.is_greater(plate_roll * 5.0)
	# ...and neither is unbounded: an unlimited 6DOF axis cannot catch a body already past upright.
	assert_float(pin_roll).is_less(90.0)
	assert_float(plate_roll).is_greater(0.0)


func test_both_pitch_stops_clear_the_steepest_grade_their_machine_can_climb() -> void:
	# On the stop the two bodies are rigid, so a limit that bounds the grade levers the climbing
	# unit's drive axle off the road: the travel must cover the break of slope. The truck climbs a
	# 25 % grade (14.0 deg) and a sharp break onto one swings the joint to +12.8 deg.
	var plate: Generic6DOFJoint3D = auto_free(_fifth_wheel().call("_build_joint"))
	var pin: Generic6DOFJoint3D = auto_free(_drawbar().call("_build_joint"))
	assert_float(_angular_stops(plate)["pitch"]).is_greater(12.8)
	assert_float(_angular_stops(pin)["pitch"]).is_greater_equal(
			_angular_stops(plate)["pitch"] as float)


# --- the coupling timings ------------------------------------------------------------------------

func test_the_coupling_timings_stay_inside_their_bands() -> void:
	# A plain delay, not a condition (every wheel grounded for N consecutive ticks): a condition can
	# fail to come true and leave the rig running bobtail forever. A counter always finishes.
	assert_int(TowHost.SPAWN_COUPLE_TICKS) \
		.override_failure_message("long enough for the chassis to rise on its springs") \
		.is_between(5, 45)
	# The watch has to outlive the tick or two a first contact takes to be reported, and end well
	# before ordinary driving (grounding out over a crest) could trip it.
	assert_int(TowHost.COUPLE_WATCH_TICKS) \
		.override_failure_message("the watch must not outlast the driver's first corner") \
		.is_between(2, 30)
	# A genuine standstill, deliberately the same figure as the body raise wants.
	assert_float(TowHost.COUPLE_SPEED_MS).is_equal(TowedBody.RAISE_SPEED_MS)


# --- the fit check: what it actually does, on both hosts ---------------------------------------

func test_a_quiet_watch_counts_down_and_keeps_the_trailer() -> void:
	# The window is a countdown, not a latch: a trailer touching nothing survives every tick of it.
	var host := _fifth_wheel()
	var stub: StubTrailer = auto_free(StubTrailer.new())
	stub.colliding = false
	host.set("trailer", stub)
	host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	for _i in TowHost.COUPLE_WATCH_TICKS:
		host.call("_watch_fresh_coupling")
	assert_int(host.get("_couple_watch")).is_equal(0)
	assert_object(host.get("trailer")) \
		.override_failure_message("a trailer that fits was taken away anyway").is_not_null()
	assert_int(_notices.size()).is_equal(0)


func test_a_body_contact_takes_the_semis_trailer_away_and_says_so() -> void:
	# One body contact right after a coupling means the trailer was laid inside the world; it stands
	# on raycasts, so it touches nothing in normal towing. The vehicle is told through
	# `attachment_refused`. `_fifth_wheel` is set by hand because it is resolved in _ready.
	var semi := _semi()
	var host := semi.get_node("FifthWheel")
	semi.set("_fifth_wheel", host)
	var stub := _dropped_stub()
	stub.colliding = true
	host.set("trailer", stub)
	host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	host.call("_watch_fresh_coupling")
	assert_bool(host.call("is_coupled")) \
		.override_failure_message("the trailer did not fit and was kept anyway").is_false()
	assert_str(semi.get("_trailer_id")).is_equal(TrailerCat.BOBTAIL)
	# Nobody pressed E for this, so the shell has to be told or the touch overlay keeps offering the
	# PTO/TIP buttons of a trailer that is no longer there.
	assert_int(_attachment_changes) \
		.override_failure_message("the shell was not told the attachment moved").is_equal(1)
	assert_int(_notices.size()).is_equal(1)


func test_a_body_contact_takes_the_tractors_trailer_away_and_says_so() -> void:
	# The same question of the other host. The drawbar is parented to the tractor because that is how
	# a host reaches its chassis.
	var tractor := _tractor()
	var drawbar := _drawbar()
	var stub := _dropped_stub()
	stub.colliding = true
	drawbar.set("trailer", stub)
	tractor.add_child(drawbar)
	tractor.set("_drawbar", drawbar)
	tractor.set("_implement_id", ImplementCat.TOWED[0])
	drawbar.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	drawbar.call("_watch_fresh_coupling")
	assert_bool(drawbar.call("is_coupled")) \
		.override_failure_message("the trailer did not fit and was kept anyway").is_false()
	assert_str(tractor.get("_implement_id")).is_equal(ImplementCat.DETACHED)
	assert_int(_attachment_changes) \
		.override_failure_message("the shell was not told the attachment moved").is_equal(1)
	assert_int(_notices.size()).is_equal(1)


func test_an_expired_watch_never_fires_again() -> void:
	# Later contacts are ordinary driving, not a reason to unhitch. Both hosts.
	var host := _fifth_wheel()
	var stub: StubTrailer = auto_free(StubTrailer.new())
	stub.colliding = true
	host.set("trailer", stub)
	host.set("_couple_watch", 0)
	host.call("_watch_fresh_coupling")
	assert_object(host.get("trailer")) \
		.override_failure_message("an old contact unhitched the rig mid-drive").is_not_null()
	assert_int(_notices.size()).is_equal(0)


# --- the tip interlock, in its current asymmetric form -----------------------------------------

## The fifth wheel's warn with the spool starting down, so the pushed cmd is a real edge. The stub
## declares the road tipper's connections, because the merged rule reads its PTO clause off them.
func _semi_warn(cmd: float, plumbed: bool, handbrake: float, pto_on: bool,
		pos01 := 0.0) -> int:
	var host := _fifth_wheel()
	var stub: StubTrailer = auto_free(StubTrailer.new())
	stub.pos01 = pos01
	stub.declares = int(TowedBody.Consumer.PTO) | int(TowedBody.Consumer.HYDRAULIC)
	host.set("trailer", stub)
	host.set("_last_tip_cmd", DOWN)
	_notices = PackedStringArray()
	host.call("_warn_if_tip_interlocked", cmd, plumbed, handbrake, pto_on)
	return _notices.size()


## The tractor's, asked of the drawbar. The stub declares the farm tipper's single connection, one
## fewer than the semi's, and `pto_on` is false because there is no shaft to turn.
func _tractor_warn(cmd: float, plumbed: bool, handbrake: float, pos01 := 0.0) -> int:
	var drawbar := _drawbar()
	var stub: StubTrailer = auto_free(StubTrailer.new())
	stub.pos01 = pos01
	stub.declares = int(TowedBody.Consumer.HYDRAULIC)
	drawbar.set("trailer", stub)
	drawbar.set("_last_tip_cmd", DOWN)
	_notices = PackedStringArray()
	drawbar.call("_warn_if_tip_interlocked", cmd, plumbed, handbrake, false)
	return _notices.size()


func test_a_refused_raise_says_why_on_the_press_that_did_nothing() -> void:
	# The handbrake is the condition both hosts demand and the one the driver can act on. Road speed
	# is deliberately not named: that one clears itself by stopping.
	assert_int(_semi_warn(RAISE, true, 0.0, true)) \
		.override_failure_message("the semi refused the raise silently").is_equal(1)
	assert_int(_tractor_warn(RAISE, true, 0.0)) \
		.override_failure_message("the tractor refused the raise silently").is_equal(1)


func test_a_permitted_raise_says_nothing() -> void:
	assert_int(_semi_warn(RAISE, true, 1.0, true)).is_equal(0)
	assert_int(_tractor_warn(RAISE, true, 1.0)).is_equal(0)


func test_only_the_semi_also_demands_the_pto_and_that_is_the_branch_being_merged() -> void:
	# The one place the two hosts genuinely disagree. The truck's tipping trailer carries its own pump
	# and the chassis PTO turns it, so no PTO means no flow; a tractor already carries the pump. The
	# clause is derived from TowedBody.consumers(), not from which host is asking.
	assert_int(_semi_warn(RAISE, true, 1.0, false)) \
		.override_failure_message("the semi stopped explaining that the pump is not turning") \
		.is_equal(1)
	assert_int(_tractor_warn(RAISE, true, 1.0)) \
		.override_failure_message("the tractor grew a PTO condition it has no pump for") \
		.is_equal(0)


func test_a_trailer_with_no_plumbing_is_never_told_to_set_the_handbrake() -> void:
	# A box has no ram, so TIP on one is a press that means nothing. Warning about it would teach an
	# interlock that does not exist.
	assert_int(_semi_warn(RAISE, false, 0.0, false)).is_equal(0)
	assert_int(_tractor_warn(RAISE, false, 0.0)).is_equal(0)


func test_lowering_is_always_allowed_and_never_warns() -> void:
	# The interlock refuses the raise direction only, clamped against where the body already is.
	assert_int(_semi_warn(DOWN, true, 0.0, false, 1.0)).is_equal(0)
	assert_int(_tractor_warn(DOWN, true, 0.0, 1.0)).is_equal(0)


func test_holding_the_spool_still_is_not_a_press() -> void:
	# The notice fires on the edge, or a rig standing with the spool open would nag every tick.
	var host := _fifth_wheel()
	var stub: StubTrailer = auto_free(StubTrailer.new())
	stub.declares = int(TowedBody.Consumer.PTO) | int(TowedBody.Consumer.HYDRAULIC)
	host.set("trailer", stub)
	host.set("_last_tip_cmd", RAISE)
	_notices = PackedStringArray()
	host.call("_warn_if_tip_interlocked", RAISE, true, 0.0, false)
	assert_int(_notices.size()) \
		.override_failure_message("the interlock nagged while the spool was held still").is_equal(0)


# --- the two live discrepancies ----------------------------------------------------------------

func test_the_semis_interlock_notice_restarts_when_the_trailer_changes() -> void:
	# The notice fires on a change of spool position, so a change of what is on the back has to
	# restart the latch. Otherwise a stale position survives the swap: the first refused press matches
	# it, reads as "no edge" and says nothing, which on a control whose only feedback is the notice is
	# indistinguishable from a dead key. test_drawbar_trailer.gd:715 is the tractor's version.
	# The latch lives on TowHost, restarted by couple() and uncouple().
	var semi := _semi()
	var host := semi.get_node("FifthWheel")
	semi.set("_fifth_wheel", host)
	host.set("_last_tip_cmd", RAISE)
	semi.call("_set_trailer", TrailerCat.BOBTAIL)
	assert_float(host.get("_last_tip_cmd")) \
		.override_failure_message("the semi kept the old spool position across a trailer change") \
		.is_equal(-1.0)


func test_the_semi_does_not_hand_roll_the_bases_camera_exclusion() -> void:
	# A source-level pin, and it has to be: BaseVehicle.get_camera_exclude_bodies returns exactly
	# [get_rid()] today, so a hand-rolled copy is observably identical and no behavioural test can
	# tell them apart. Same technique test_lamps uses to assert no blink timer comes back.
	var src := FileAccess.get_file_as_string("res://src/vehicles/truck/semi.gd")
	var at := src.find("func get_camera_exclude_bodies")
	assert_int(at).override_failure_message("get_camera_exclude_bodies is gone").is_greater(-1)
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	# Comments are stripped first: the first version of this test matched the word "super" in the
	# comment above the call, so it passed with the call reverted.
	var code := ""
	for line in body.split("\n"):
		var stripped := (line as String).strip_edges()
		if not stripped.begins_with("#"):
			code += stripped + "\n"
	assert_bool(code.contains("super.get_camera_exclude_bodies()")) \
		.override_failure_message("the semi rebuilds the base's exclusion list instead of calling it") \
		.is_true()


# --- what became data --------------------------------------------------------------------------

## A towed body that declares something, so the derived gates can be asked what they do with it.
## `set_valve` is recorded rather than overridden away: the number the host hands down is the
## question. The ticked seams are no-ops — this stub has no wheels, no lamps and no body.
class DeclaringTrailer:
	extends TowedBody

	var declares := 0
	var last_valve := -1.0

	## No spec, so no _ready: this stub is in the tree only to have a global_position, and
	## TowedBody._ready would complain about a trailer with no mass, wheels or brakes.
	func _ready() -> void:
		pass

	func consumers() -> int:
		return declares

	func set_valve(flow01: float) -> void:
		last_valve = flow01

	func apply_lamps(_brake_on: bool, _headlights: int, _l: bool, _r: bool) -> void:
		pass

	func tick_towed(_brake01: float, _handbrake01: float, _delta: float,
			_grip_terrains: Array[Node]) -> void:
		pass

	func body_pos01() -> float:
		return 0.0

	func body_is_colliding() -> bool:
		return false


## Run one towing tick with the spool wide open and the handbrake set (so the raise interlock
## never clamps), and report what reached the trailer's valve.
func _valve_after_tick(declares: int, pto_on: bool) -> float:
	var drawbar := _drawbar()
	var stub := DeclaringTrailer.new()
	stub.declares = declares
	# Both go into the tree: tick_towing reads the trailer's global_position for the
	# fall-off-the-world check.
	add_child(auto_free(stub))
	add_child(drawbar)
	drawbar.set("trailer", stub)
	var input := VehicleInput.new()
	input.handbrake = 1.0
	drawbar.call("tick_towing", input, 0.0, 1.0, pto_on, 1500, 0.0, 1.0 / 60.0,
			[] as Array[Node])
	return stub.last_valve


## A host script's profile without orphaning the node it takes to ask. TowHost is a Node3D, so
## `Script.new().profile()` leaks one.
func _profile_of(host_script: GDScript) -> CouplingProfile:
	var host: Node3D = auto_free(host_script.new())
	return host.call("profile") as CouplingProfile


func test_flow_reaches_only_a_body_that_declares_hoses() -> void:
	# The gate the trailer is never trusted to apply itself. A box has no ram.
	assert_float(_valve_after_tick(0, true)) \
		.override_failure_message("a trailer with no plumbing was handed flow").is_equal(0.0)
	assert_float(_valve_after_tick(int(TowedBody.Consumer.HYDRAULIC), true)).is_equal(1.0)


func test_the_pto_clause_of_the_flow_gate_is_derived_from_what_the_body_declares() -> void:
	# The same collapse the tip notice makes, on the valve rather than on the words. A road tipper
	# declares PTO | HYDRAULIC because a truck has no hydraulic remotes and something must turn a pump
	# on the trailer; a farm tipper declares HYDRAULIC alone because a tractor carries the pump.
	var both := int(TowedBody.Consumer.PTO) | int(TowedBody.Consumer.HYDRAULIC)
	assert_float(_valve_after_tick(both, false)) \
		.override_failure_message("a trailer-mounted pump ran with the PTO out").is_equal(0.0)
	assert_float(_valve_after_tick(both, true)).is_equal(1.0)
	# ...and a body with no shaft is never held back by a shaft it does not have.
	assert_float(_valve_after_tick(int(TowedBody.Consumer.HYDRAULIC), false)) \
		.override_failure_message("a tractor's own pump was gated on a PTO the trailer lacks") \
		.is_equal(1.0)


func test_each_profile_says_the_same_thing_as_the_constants_it_was_built_from() -> void:
	# _build_joint reads only the profile; the constants are where each number keeps its argument.
	var pin: CouplingProfile = _profile_of(DrawbarScript)
	assert_float(pin.pitch_deg).is_equal(DrawbarScript.PITCH_LIMIT_DEG)
	assert_float(pin.yaw_deg).is_equal(DrawbarScript.SWING_MAX_DEG)
	assert_float(pin.roll_deg).is_equal(DrawbarScript.ROLL_LIMIT_DEG)
	var plate: CouplingProfile = _profile_of(FifthWheelScript)
	assert_float(plate.pitch_deg).is_equal(FifthWheelScript.PITCH_LIMIT_DEG)
	assert_float(plate.yaw_deg).is_equal(FifthWheelScript.YAW_LIMIT_DEG)
	assert_float(plate.roll_deg).is_equal(FifthWheelScript.ROLL_LIMIT_DEG)


func test_every_profile_can_say_all_three_things_a_driver_is_told() -> void:
	# An empty string is a notice that fires, occupies the banner and says nothing.
	for p: CouplingProfile in [_profile_of(DrawbarScript), _profile_of(FifthWheelScript)]:
		assert_str(p.speed_notice).is_not_empty()
		assert_str(p.no_room_notice).is_not_empty()
		assert_str(p.tip_notice).is_not_empty()
	# The two tip notices differ, the same asymmetry the derived rule reproduces: a road tipper's
	# driver is told to engage the PTO because there is a pump on the trailer to turn, a tractor's is
	# not.
	assert_str(_profile_of(DrawbarScript).tip_notice) \
		.override_failure_message("the tractor was told to engage a PTO its trailer does not have") \
		.is_not_equal(_profile_of(FifthWheelScript).tip_notice)


# --- the duck-typed vehicle hooks, asked of a real chassis --------------------------------------

## The host reaches its vehicle through two duck-typed hooks, and neither can be asked without a
## real chassis in a real tree: `attachment_spawn_ready` lays a remembered towed id behind the
## machine, `attachment_refused` stops the vehicle's id claiming a body no longer on the pin.
func test_the_spawn_countdown_couples_a_remembered_trailer_on_a_real_tractor() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var tractor: Node3D = auto_free(
			(load(CatalogScript.scene_of("tractor-kenney")) as PackedScene).instantiate() as Node3D)
	root.add_child(tractor)
	tractor.set("spawn_transform", tractor.global_transform)
	var host := tractor.get_node("Drawbar") as TowHost
	assert_object(host).is_not_null()
	assert_vector(host.marker_local()).is_equal_approx(Drawbar.PIN_LOCAL, Vector3.ONE * 1e-4)
	# The spawn countdown, then the remembered towed id.
	tractor.set("_implement_id", ImplementCat.TOWED[0])
	var input := VehicleInput.new()
	for i in TowHost.SPAWN_COUPLE_TICKS:
		host.tick_towing(input, 0.0, 0.0, false, 0, 0.0, 1.0 / 60.0, [] as Array[Node])
	assert_bool(host.is_coupled()) \
		.override_failure_message("the spawn countdown never coupled the remembered trailer") \
		.is_true()
	assert_str(tractor.call("current_attachment")).is_equal(ImplementCat.TOWED[0])
	# The joint really got built and bound to both bodies.
	var joint := tractor.get_node_or_null("DrawbarPin") as Generic6DOFJoint3D
	assert_object(joint).override_failure_message("no joint under the chassis").is_not_null()
	assert_bool(joint.node_a.is_empty()).is_false()
	assert_bool(joint.node_b.is_empty()).is_false()
	# The trailer is a sibling of the tractor, not a child of it.
	assert_object(host.trailer.get_parent()).is_same(root)
	# Camera exclude, respawn re-lay, freeze and teardown all go through the host.
	var rids: Array[RID] = tractor.call("get_camera_exclude_bodies")
	assert_int(rids.size()).is_equal(2)
	tractor.call("set_display_frozen", true)
	assert_bool(host.trailer.freeze).is_true()
	tractor.call("set_display_frozen", false)
	host.respawn_relay(tractor.global_transform)
	assert_vector(host.trailer.global_position) \
		.is_equal_approx(host.coupled_pose(tractor.global_transform).origin, Vector3.ONE * 1e-3)
	host.uncouple()
	assert_bool(host.is_coupled()).is_false()


## The air is the one piece of state that straddles the seam. The rig spawns having stood coupled,
## so its trailer's reservoirs are already charged — a coupling made while driving charges from
## empty and dips AIR1/AIR2, and the first frame must not be one of those. Both units, because the
## conventional's coupling datum Z is deliberately not the cab-over's.
func test_both_tractor_units_couple_at_their_own_datum_and_spawn_with_charged_air() -> void:
	for variant: String in ["semi", "semi-conventional"]:
		var root: Node3D = auto_free(Node3D.new())
		add_child(root)
		var unit: Node3D = auto_free(
				(load(CatalogScript.scene_of(variant)) as PackedScene).instantiate() as Node3D)
		root.add_child(unit)
		unit.set("spawn_transform", unit.global_transform)
		var host := unit.get_node("FifthWheel") as TowHost
		# The datum is the marker's own position, because the FifthWheel node sits at identity.
		assert_vector(host.marker_local()) 			.override_failure_message("%s: the coupling datum moved" % variant) 			.is_equal_approx((unit.get_node("FifthWheel/Kingpin") as Node3D).position,
				Vector3.ONE * 1e-6)
		unit.set("_trailer_id", TrailerCat.first())
		var input := VehicleInput.new()
		for _i in TowHost.SPAWN_COUPLE_TICKS:
			host.tick_towing(input, 0.0, 0.0, false, 0, 0.0, 1.0 / 60.0, [] as Array[Node])
		assert_bool(host.is_coupled()) 			.override_failure_message("%s: the spawn countdown never coupled" % variant).is_true()
		assert_float(unit.get("_trailer_air")) 			.override_failure_message("%s: the spawn rig began life with an empty trailer" % variant) 			.is_equal(1.0)
		# A respawn re-lays the air on BOTH bodies, or it would cost air the driver never spent.
		unit.set("_trailer_air", 0.3)
		unit.call("respawn")
		assert_float(unit.get("_trailer_air")).is_equal(1.0)
		host.uncouple()


# --- the whole coupling, on real rigs ------------------------------------------------------------
#
# Written against `TowHost` and parameterised over both couplings; the profile only changes the
# three sentences the driver is told. Real rigs, not stubs: the display freeze, the velocity match,
# the camera list and the teardown are about two bodies in a world.

const SEMI := "semi"
const TRACTOR := "tractor"
## Both couplings, every time.
const KINDS: Array[String] = [SEMI, TRACTOR]

const DELTA := 1.0 / 60.0
const TIPPER := "res://src/vehicles/truck/trailers/tipper.tscn"

## Which fields of a `CouplingProfile` the two couplings are allowed to disagree about: the three
## joint angles, the scene wiring, and the two notices a machine words for itself.
## `no_room_notice` is deliberately absent — both say the same sentence.
const LICENSED_DIFFERENCES: Array[String] = [
	"pitch_deg", "yaw_deg", "roll_deg", "joint_name", "marker_path", "speed_notice", "tip_notice",
]


## One towing rig, built the way a level builds one. The ids come off the machine's own catalog, so
## one scenario runs on both without knowing what either of them pulls.
class Rig:
	extends RefCounted

	var kind := ""
	var root: Node3D          ## the LEVEL: the parent a towed body is laid under, never the chassis
	var vehicle: Node3D
	var host: TowHost
	var towed_id := ""        ## this machine's catalog entry for the body it tows
	var tip_id := ""          ## ...and for the TIPPING one, which is not always the same entry
	var bare_id := ""         ## nothing on the back


func _rig(kind: String) -> Rig:
	var r := Rig.new()
	r.kind = kind
	r.root = auto_free(Node3D.new()) as Node3D
	add_child(r.root)
	var variant := "semi" if kind == SEMI else "tractor-kenney"
	r.vehicle = auto_free(
			(load(CatalogScript.scene_of(variant)) as PackedScene).instantiate() as Node3D) as Node3D
	r.root.add_child(r.vehicle)
	# Level._spawn_vehicle assigns this AFTER add_child, which is the whole reason the spawn
	# countdown exists; a rig built without it lays its body against the origin.
	r.vehicle.set("spawn_transform", r.vehicle.global_transform)
	if kind == SEMI:
		r.host = r.vehicle.get_node("FifthWheel") as TowHost
		r.towed_id = TrailerCat.first()
		r.tip_id = TIPPER
		r.bare_id = TrailerCat.BOBTAIL
	else:
		r.host = r.vehicle.get_node("Drawbar") as TowHost
		r.towed_id = ImplementCat.TOWED[0]
		r.tip_id = ImplementCat.TOWED[0]
		r.bare_id = ImplementCat.DETACHED
	return r


## Run the spawn countdown out, which is the only way a rig becomes able to couple at all.
func _spawn(r: Rig) -> void:
	var input := VehicleInput.new()
	for _i in TowHost.SPAWN_COUPLE_TICKS:
		r.host.tick_towing(input, 0.0, 0.0, false, 0, 0.0, DELTA, [] as Array[Node])


func _reset_notices() -> void:
	_notices = PackedStringArray()
	_attachment_changes = 0


## The catalog entry one press of E before `id`, so neither test learns what a box or a farm tipper
## is.
func _press_before(r: Rig, id: String) -> String:
	var ids: PackedStringArray = r.vehicle.call("attachment_ids")
	var i := ids.find(id)
	return ids[(i - 1 + ids.size()) % ids.size()]


func _one_press_before(r: Rig) -> String:
	return _press_before(r, r.towed_id)


# --- 1. the display-frozen exemption -----------------------------------------------------------

func test_the_fit_check_never_fires_while_the_showroom_has_the_rig_pinned() -> void:
	# The showroom hovers the rig on purpose, so a display rig must never decide it does not fit and
	# put its own body down. The exemption is a whole branch of the fit check.
	for kind: String in KINDS:
		var r := _rig(kind)
		_reset_notices()
		r.vehicle.call("set_display_frozen", true)
		var stub: StubTrailer = auto_free(StubTrailer.new())
		stub.colliding = true
		r.host.set("trailer", stub)
		r.host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
		for _i in TowHost.COUPLE_WATCH_TICKS * 2:
			r.host.call("_watch_fresh_coupling")
		assert_object(r.host.get("trailer")) \
			.override_failure_message("%s: the showroom put its own body down" % kind).is_not_null()
		# The window does not even count while exempt, so leaving the garage does not hand the rig a
		# half-spent watch.
		assert_int(r.host.get("_couple_watch")) \
			.override_failure_message("%s: the exempt window counted down anyway" % kind) \
			.is_equal(TowHost.COUPLE_WATCH_TICKS)
		assert_int(_notices.size()).is_equal(0)
		assert_int(_attachment_changes).is_equal(0)


func test_a_body_swapped_in_with_e_while_frozen_is_pinned_with_the_rig() -> void:
	# The garage swap: E cycles the attachment with the rig already frozen. A body coupled at that
	# moment has to be frozen by the coupling — the flag was set before it existed.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_display_frozen", true)
		r.vehicle.call("set_attachment", r.towed_id)
		assert_bool(r.host.is_coupled()) \
			.override_failure_message("%s: the frozen rig would not couple at all" % kind).is_true()
		assert_bool(r.host.trailer.freeze) \
			.override_failure_message("%s: the swapped-in body still obeys gravity" % kind).is_true()
		assert_int(r.host.trailer.freeze_mode).is_equal(RigidBody3D.FREEZE_MODE_KINEMATIC)
		# ...and driving out of the garage un-pins it, or the rig tows a kinematic block.
		r.vehicle.call("set_display_frozen", false)
		assert_bool(r.host.trailer.freeze) \
			.override_failure_message("%s: driving away tows a kinematic block" % kind).is_false()


# --- 2. lamps run while frozen ------------------------------------------------------------------

## A marker lens is a surface override, not a material_override: LampSet._bind_scene_colored gives
## each marker a private duplicate of the material the scene authored on it, while the head/brake/
## turn groups each share one canonical material assigned wholesale.
func _marker_mat(mesh: MeshInstance3D) -> BaseMaterial3D:
	return mesh.get_surface_override_material(0) as BaseMaterial3D


func test_a_rig_standing_in_the_showroom_still_shows_its_markers() -> void:
	# apply_lamps is separate from tick_towed because it is not physics, which is only true if the
	# lamps reach a frozen body. Asserted on the body's own lamp material, not on the call.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_display_frozen", true)
		r.vehicle.call("set_attachment", r.towed_id)
		var towed := r.host.trailer
		var spec: VehicleSpec = towed.spec
		var marker := towed.get_node(spec.steady_lamp_paths[0]) as MeshInstance3D
		var tail := towed.get_node(spec.brake_lamp_paths[0]) as MeshInstance3D
		var input := VehicleInput.new()
		input.lights = LampSet.HL_OFF
		r.host.tick_towing(input, 0.0, 0.0, false, 0, 0.0, DELTA, [] as Array[Node])
		var dark: float = _marker_mat(marker).emission_energy_multiplier
		# Sidelights on and the pedal down, on a rig that cannot move: both still light.
		input.lights = LampSet.HL_LOW
		input.lamps.brake_lamp = true
		r.host.tick_towing(input, 0.0, 0.0, false, 0, 0.0, DELTA, [] as Array[Node])
		assert_bool(towed.freeze) \
			.override_failure_message("%s: the rig was not frozen, so this proves nothing" % kind) \
			.is_true()
		assert_float(_marker_mat(marker).emission_energy_multiplier) \
			.override_failure_message("%s: a frozen rig went dark at the back" % kind) \
			.is_greater(dark)
		assert_float(tail.material_override.emission_energy_multiplier) \
			.override_failure_message("%s: the frozen rig's stop lamp did not light" % kind) \
			.is_equal_approx(LampSet.REAR_ENERGY[LampSet.Rear.STOP], 1e-5)


# --- 3. the velocity match at coupling ----------------------------------------------------------

func test_coupling_at_speed_hands_the_solver_no_relative_velocity() -> void:
	# The lever-arm guard. Coupling treats the pair as one rigid body for the instant before the joint
	# exists: a body laid at rest behind a moving rig hands the solver ten to twenty tonnes at the
	# whole road speed, an impulse big enough to throw the towing unit.
	#
	# Asserted at the coupling datum, the point the two bodies share once coupled. The rig is turning
	# as well as travelling: a match written with linear velocity alone would pass a straight-line test
	# and still throw the rig in a yard.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_attachment", r.bare_id)
		var chassis := r.vehicle as RigidBody3D
		chassis.linear_velocity = Vector3(0.0, 0.0, -20.0)
		chassis.angular_velocity = Vector3(0.0, 0.6, 0.0)
		r.vehicle.call("set_attachment", r.towed_id)
		var towed := r.host.trailer
		var datum := chassis.global_transform * r.host.marker_local()
		var v_chassis := chassis.linear_velocity + chassis.angular_velocity.cross(
				datum - chassis.global_transform * chassis.center_of_mass)
		# The towed body's ORIGIN is its eye / kingpin, so it is standing on the datum.
		var v_towed := towed.linear_velocity + towed.angular_velocity.cross(
				towed.global_position - towed.global_transform * towed.center_of_mass)
		assert_vector(v_towed) \
			.override_failure_message("%s: the coupling is a shear, not a match" % kind) \
			.is_equal_approx(v_chassis, Vector3.ONE * 1e-3)
		assert_vector(towed.angular_velocity).is_equal_approx(chassis.angular_velocity,
				Vector3.ONE * 1e-6)
		# ...and it is a match rather than a stop: a body left at rest would read zero here.
		assert_float(towed.linear_velocity.length()) \
			.override_failure_message("%s: the body was laid stationary behind a moving rig" % kind) \
			.is_greater(10.0)


# --- 4. teardown --------------------------------------------------------------------------------

func test_tearing_the_level_down_takes_the_whole_rig_without_complaint() -> void:
	# What `unparent = false` exists for. `remove_child` fails outright with "Parent node is busy
	# setting up children" while a parent is mid-removal, which is where _exit_tree runs. The engine
	# error is the assertion: everything under the level dies either way, so no state check could tell
	# the two paths apart.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_attachment", r.towed_id)
		assert_bool(r.host.is_coupled()) \
			.override_failure_message("%s: nothing was coupled, so this tests nothing" % kind) \
			.is_true()
		var towed: Node = r.host.trailer
		var joint: Node = r.host.get("_joint")
		var level := r.root
		await assert_error(func() -> void: level.free()) \
			.override_failure_message("%s: the teardown path logged an engine error" % kind) \
			.is_success()
		assert_bool(is_instance_valid(joint)) \
			.override_failure_message("%s: the joint outlived the level" % kind).is_false()
		assert_bool(is_instance_valid(towed)) \
			.override_failure_message("%s: the towed body outlived the level" % kind).is_false()


func test_taking_the_vehicle_out_of_the_level_frees_what_it_was_towing() -> void:
	# The other teardown, made necessary by the towed body's parentage: it is a child of the level, so
	# a vehicle swap that only freed the chassis would leave twenty tonnes standing in the road.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_attachment", r.towed_id)
		var towed: Node = r.host.trailer
		var joint: Node = r.host.get("_joint")
		var vehicle := r.vehicle
		await assert_error(func() -> void: (vehicle.get_parent() as Node).remove_child(vehicle)) \
			.override_failure_message("%s: pulling the chassis out logged an engine error" % kind) \
			.is_success()
		assert_bool(towed.is_queued_for_deletion()) \
			.override_failure_message("%s: the towed body was left standing in the level" % kind) \
			.is_true()
		assert_bool(joint.is_queued_for_deletion()) \
			.override_failure_message("%s: the joint was left behind" % kind).is_true()
		assert_bool(r.host.is_coupled()).is_false()


# --- 5. the camera exclusion, in full -----------------------------------------------------------

func test_the_chase_camera_ignores_both_bodies_of_the_combination() -> void:
	# Bare is the base's answer exactly; coupled is that answer plus the towed body's RID, a superset.
	# Without the second RID the pull-in slams the camera into the body's headboard.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		r.vehicle.call("set_attachment", r.bare_id)
		var bare: Array[RID] = r.vehicle.call("get_camera_exclude_bodies")
		assert_bool(bare.has((r.vehicle as RigidBody3D).get_rid())) \
			.override_failure_message("%s: the camera does not even exclude the chassis" % kind) \
			.is_true()
		assert_int(bare.size()) \
			.override_failure_message("%s: a bare machine excludes something extra" % kind) \
			.is_equal(1)
		r.vehicle.call("set_attachment", r.towed_id)
		var towing: Array[RID] = r.vehicle.call("get_camera_exclude_bodies")
		for rid: RID in bare:
			assert_bool(towing.has(rid)) \
				.override_failure_message("%s: coupling REPLACED the base's exclusion" % kind) \
				.is_true()
		assert_bool(towing.has(r.host.trailer.get_rid())) \
			.override_failure_message("%s: the camera sees through the towed body" % kind).is_true()
		assert_int(towing.size()).is_equal(2)


# --- 6. the couple-at-speed refusal, in each machine's own words --------------------------------

func test_each_coupling_refuses_at_speed_and_says_so_in_its_own_words() -> void:
	# Coupling at speed lays metres of body at a pose the towing unit has already left, which reads as
	# "it refuses even though there is room" once the fit check finds it inside what was driven past.
	# The expected text is read off the profile, so the refusal speaks in the machine's own sentence.
	for kind: String in KINDS:
		var r := _rig(kind)
		var speech := r.host.profile().speed_notice
		_reset_notices()
		# A genuine standstill is allowed, and the threshold itself is inclusive.
		assert_bool(r.host.may_couple(0.0)).is_true()
		assert_bool(r.host.may_couple(TowHost.COUPLE_SPEED_MS)) \
			.override_failure_message("%s: the threshold speed itself was refused" % kind).is_true()
		assert_int(_notices.size()) \
			.override_failure_message("%s: a permitted coupling was explained anyway" % kind) \
			.is_equal(0)
		# Either direction: reversing onto a body at speed is the same mistake.
		assert_bool(r.host.may_couple(TowHost.COUPLE_SPEED_MS * 10.0)).is_false()
		assert_bool(r.host.may_couple(-TowHost.COUPLE_SPEED_MS * 10.0)) \
			.override_failure_message("%s: reversing at speed was allowed to couple" % kind) \
			.is_false()
		assert_array(_notices).is_equal([speech, speech])


func test_neither_machine_will_hitch_a_body_while_it_is_moving() -> void:
	# The same refusal where the driver meets it: E, on a rig parked one press before its towed entry.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		var parked := _one_press_before(r)
		r.vehicle.call("set_attachment", parked)
		r.vehicle.get("telemetry").speed = 8.0
		_reset_notices()
		r.vehicle.call("cycle_implement")
		assert_str(r.vehicle.call("current_attachment")) \
			.override_failure_message("%s: a body was hitched at 29 km/h" % kind).is_equal(parked)
		assert_array(_notices).is_equal([r.host.profile().speed_notice])


# --- the coupling failure path ------------------------------------------------------------------

## A coupling that always refuses, so the vehicle's answer to a failed coupling can be asked without
## inventing a broken scene. `couple()` returning false is the entire contract between the halves.
class RefusingFifthWheel:
	extends FifthWheel

	func couple(_scene: PackedScene) -> bool:
		return false


class RefusingDrawbar:
	extends Drawbar

	func couple(_scene: PackedScene) -> bool:
		return false


func test_an_attachment_that_could_not_be_coupled_is_not_claimed_afterwards() -> void:
	# Leaving the id set has current_attachment() report a body that was never laid: the selector
	# highlights its card and the touch overlay offers its PTO and TIP buttons.
	for kind: String in KINDS:
		var r := _rig(kind)
		var refusing: TowHost = auto_free(
				RefusingFifthWheel.new() if kind == SEMI else RefusingDrawbar.new())
	# Never entered a tree, so _ready never ran and it resolved no marker; it does not need one.
	# `_coupled_once` is set by hand because the spawn countdown is not under test here.
		refusing.set("_coupled_once", true)
		r.vehicle.set("_fifth_wheel" if kind == SEMI else "_drawbar", refusing)
		r.vehicle.call("set_attachment", r.towed_id)
		assert_bool(refusing.is_coupled()).is_false()
		assert_str(r.vehicle.call("current_attachment")) \
			.override_failure_message(
				"%s: the shell was told a body is on the back that never was" % kind) \
			.is_equal(r.bare_id)


func test_a_scene_that_is_not_a_towed_body_is_refused_and_named() -> void:
	# The realistic way a coupling fails: a catalog id pointing at something that is not a towed body.
	# It names the coupling and the scene, because the only other symptom is a machine running bare.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		var wrong := PackedScene.new()
		var not_a_body := Node3D.new()
		@warning_ignore("return_value_discarded")
		wrong.pack(not_a_body)
		not_a_body.free()
		var answer: Array = [true]
		await assert_error(func() -> void: answer[0] = r.host.couple(wrong)) \
			.is_push_error("%s: '' is not a TowedBody" % r.host.name)
		assert_bool(answer[0]) \
			.override_failure_message("%s: couple() claimed success on a scene it rejected" % kind) \
			.is_false()
		assert_bool(r.host.is_coupled()) \
			.override_failure_message("%s: a refused coupling left the old body on" % kind).is_false()


# --- what the two couplings are allowed to disagree about ---------------------------------------

## Every declared field of a CouplingProfile, read off the resource rather than listed, so a field
## added later is asked about here whether or not anyone remembered to come and add it.
func _profile_fields() -> PackedStringArray:
	var out := PackedStringArray()
	for prop: Dictionary in CouplingProfile.new().get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out.append(String(prop["name"]))
	return out


func test_the_two_couplings_disagree_about_exactly_the_licensed_fields() -> void:
	# The answer is a diff of two resources, and it has to come out equal to the licensed list. A field
	# that joins that list without an argument for it is the drift this extraction removed.
	var plate := _profile_of(FifthWheelScript)
	var pin := _profile_of(DrawbarScript)
	var differ := PackedStringArray()
	for field: String in _profile_fields():
		if plate.get(field) != pin.get(field):
			differ.append(field)
	assert_array(differ) \
		.override_failure_message("the two couplings differ about %s; the plan licenses %s"
				% [differ, LICENSED_DIFFERENCES]) \
		.is_equal(LICENSED_DIFFERENCES)


func test_the_coupling_timings_belong_to_the_host_and_not_to_either_machine() -> void:
	# The three timings are identical on both couplings with no machine reason to differ, so they are
	# TowHost constants — and a subclass CAN shadow a const.
	assert_int(FifthWheelScript.SPAWN_COUPLE_TICKS).is_equal(TowHost.SPAWN_COUPLE_TICKS)
	assert_int(DrawbarScript.SPAWN_COUPLE_TICKS).is_equal(TowHost.SPAWN_COUPLE_TICKS)
	assert_int(FifthWheelScript.COUPLE_WATCH_TICKS).is_equal(TowHost.COUPLE_WATCH_TICKS)
	assert_int(DrawbarScript.COUPLE_WATCH_TICKS).is_equal(TowHost.COUPLE_WATCH_TICKS)
	assert_float(FifthWheelScript.COUPLE_SPEED_MS).is_equal(TowHost.COUPLE_SPEED_MS)
	assert_float(DrawbarScript.COUPLE_SPEED_MS).is_equal(TowHost.COUPLE_SPEED_MS)
	# ...and none of the three became a profile field.
	for field: String in _profile_fields():
		assert_bool(field.ends_with("_ticks") or field.ends_with("_ms")) \
			.override_failure_message("'%s' made a shared timing into per-machine data" % field) \
			.is_false()


# --- the scenario table, driven through both couplings ------------------------------------------
#
# One rig is walked through the whole two-body life — spawn, couple, couple while moving, fit
# refusal, tip against the interlock, respawn, teardown — and each step reports what happened as a
# plain string. The two traces must come out identical. Wherever a machine's own catalog, profile
# or wording would show through, the trace records what the machine itself says
# ("own-speed-notice") instead of the literal, so the licensed differences cancel by construction
# and anything left is unlicensed. On failure, the first line that differs names the step.

const STEP_OK := "ok"


## Say whether `got` is the machine's own word for `expect_own`. A mismatch keeps the real text,
## because a trace that says only "wrong" is a trace you cannot debug from.
func _own(got: String, expect_own: String, label: String) -> String:
	return "own-%s" % label if got == expect_own else "NOT-own-%s(%s)" % [label, got]


func _scenario_trace(r: Rig) -> PackedStringArray:
	var t := PackedStringArray()
	var p := r.host.profile()
	var input := VehicleInput.new()

	# SPAWN. The id is remembered rather than coupled until a real spawn transform exists.
	r.vehicle.call("set_attachment", r.towed_id)
	t.append("spawn/before: coupled=%s claimed=%s ready=%s" % [
		r.host.is_coupled(), _own(r.vehicle.call("current_attachment"), r.towed_id, "towed-id"),
		r.host.spawn_ready()])
	_spawn(r)
	t.append("spawn/after: coupled=%s claimed=%s ready=%s" % [
		r.host.is_coupled(), _own(r.vehicle.call("current_attachment"), r.towed_id, "towed-id"),
		r.host.spawn_ready()])

	# COUPLE. A joint under the chassis bound to both bodies, and a towed body that is a sibling of the
	# chassis rather than a child (a dynamic body under another gets its transform applied twice).
	r.vehicle.call("set_attachment", r.bare_id)
	t.append("uncouple: coupled=%s claimed=%s" % [
		r.host.is_coupled(), _own(r.vehicle.call("current_attachment"), r.bare_id, "bare-id")])
	r.vehicle.call("set_attachment", r.towed_id)
	var joint := r.host.get("_joint") as Generic6DOFJoint3D
	t.append("couple: coupled=%s joint=%s bound=%s sibling=%s pose=%s" % [
		r.host.is_coupled(),
		"own-joint-name" if joint != null and joint.name == String(p.joint_name) else "WRONG",
		joint != null and not joint.node_a.is_empty() and not joint.node_b.is_empty(),
		r.host.trailer.get_parent() == r.root,
		r.host.trailer.global_position.distance_to(
				r.host.coupled_pose(r.vehicle.global_transform).origin) < 1e-3])

	# Couple while moving. Parked one press before the towed entry, so E is a real hitch on both.
	r.vehicle.call("set_attachment", _one_press_before(r))
	r.vehicle.get("telemetry").speed = 8.0
	_reset_notices()
	r.vehicle.call("cycle_implement")
	t.append("moving: coupled=%s kept=%s said=%s" % [
		r.host.is_coupled(),
		r.vehicle.call("current_attachment") == _one_press_before(r),
		_own(", ".join(_notices), p.speed_notice, "speed-notice")])
	r.vehicle.get("telemetry").speed = 0.0

	# ...and dropping at speed is allowed, because a drop lays nothing: no pose is guessed.
	r.vehicle.call("set_attachment", _press_before(r, r.bare_id))
	r.vehicle.get("telemetry").speed = 8.0
	_reset_notices()
	r.vehicle.call("cycle_implement")
	t.append("moving/drop: coupled=%s claimed=%s notices=%d" % [
		r.host.is_coupled(), _own(r.vehicle.call("current_attachment"), r.bare_id, "bare-id"),
		_notices.size()])
	r.vehicle.get("telemetry").speed = 0.0

	# The fit refusal. The id is claimed for real first, so what is asserted is the recovery. The
	# colliding body is a stub because `body_is_colliding` is the physics engine's answer.
	r.vehicle.call("set_attachment", r.towed_id)
	r.host.uncouple()
	var stub := _dropped_stub()
	stub.colliding = true
	r.host.set("trailer", stub)
	r.host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	_reset_notices()
	r.host.call("_watch_fresh_coupling")
	t.append("fit: coupled=%s claimed=%s told-shell=%d said=%s" % [
		r.host.is_coupled(), _own(r.vehicle.call("current_attachment"), r.bare_id, "bare-id"),
		_attachment_changes, _own(", ".join(_notices), p.no_room_notice, "no-room-notice")])

	# The tip interlock. The machine's own tipping body, spool wide open, handbrake off.
	r.vehicle.call("set_attachment", r.tip_id)
	input.handbrake = 0.0
	# The spool starts down and is then opened, because the notice fires on the edge: the first tick is
	# the parked spool and the second is the press.
	r.host.tick_towing(input, 0.0, 0.0, true, 1500, 0.0, DELTA, [] as Array[Node])
	_reset_notices()
	r.host.tick_towing(input, 0.0, 1.0, true, 1500, 0.0, DELTA, [] as Array[Node])
	t.append("tip/refused: valve=%.2f notices=%d said=%s" % [
		r.host.trailer.valve_flow, _notices.size(),
		_own(", ".join(_notices), p.tip_notice, "tip-notice")])
	# ...and with the handbrake set it goes up, silently. Same two ticks, one condition different.
	input.handbrake = 1.0
	_reset_notices()
	r.host.tick_towing(input, 0.0, 1.0, true, 1500, 0.0, DELTA, [] as Array[Node])
	t.append("tip/allowed: valve=%.2f notices=%d" % [r.host.trailer.valve_flow, _notices.size()])

	# RESPAWN. The body is re-laid at its coupled pose and the fit-check window zeroed: a re-laid
	# body goes back exactly where it stood.
	r.host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	r.vehicle.call("respawn")
	t.append("respawn: relaid=%s stopped=%s watch=%d" % [
		r.host.trailer.global_position.distance_to(
				r.host.coupled_pose(r.vehicle.get("spawn_transform")).origin) < 1e-3,
		r.host.trailer.linear_velocity.length() < 1e-6,
		r.host.get("_couple_watch")])

	# TEARDOWN. Both bodies go and the joint with them.
	var towed: Node = r.host.trailer
	r.root.remove_child(r.vehicle)
	t.append("teardown: coupled=%s body-freed=%s joint-freed=%s" % [
		r.host.is_coupled(), towed.is_queued_for_deletion(), joint.is_queued_for_deletion()])
	return t


func test_the_two_machines_differ_only_where_decision_seven_says_they_may() -> void:
	var plate := _scenario_trace(_rig(SEMI))
	var pin := _scenario_trace(_rig(TRACTOR))
	# Line by line, because "two arrays differ" is not a finding and "the fit step differs" is.
	assert_int(pin.size()).is_equal(plate.size())
	for i in mini(plate.size(), pin.size()):
		assert_str(pin[i]) \
			.override_failure_message(
				"the two couplings part company at step %d:\n  fifth wheel: %s\n  drawbar:     %s"
				% [i, plate[i], pin[i]]) \
			.is_equal(plate[i])
	# ...and the trace has to record things going right, or two identically broken machines would
	# agree perfectly.
	assert_array(plate).is_equal([
		"spawn/before: coupled=false claimed=own-towed-id ready=false",
		"spawn/after: coupled=true claimed=own-towed-id ready=true",
		"uncouple: coupled=false claimed=own-bare-id",
		"couple: coupled=true joint=own-joint-name bound=true sibling=true pose=true",
		"moving: coupled=false kept=true said=own-speed-notice",
		"moving/drop: coupled=false claimed=own-bare-id notices=0",
		"fit: coupled=false claimed=own-bare-id told-shell=1 said=own-no-room-notice",
		"tip/refused: valve=0.00 notices=1 said=own-tip-notice",
		"tip/allowed: valve=1.00 notices=0",
		"respawn: relaid=true stopped=true watch=0",
		"teardown: coupled=false body-freed=true joint-freed=true",
	])


# --- two decided deltas -------------------------------------------------------------------------

func test_the_iso_bus_publishes_bobtail_zeros_on_the_tick_a_trailer_is_refused() -> void:
	# A decided delta, not an oversight. TowHost.tick_towing owns the fall and fit checks, so the ISO
	# 11992 publish happens after them. The one visible tick is the one the fit check takes the trailer
	# away: the semi publishes bobtail zeros instead of the departing trailer's last axle load. One
	# entry point for the whole towing side is worth more than a one-frame difference there.
	var r := _rig(SEMI)
	_spawn(r)
	r.vehicle.call("set_attachment", r.towed_id)
	r.host.uncouple()
	var stub := _dropped_stub()
	stub.colliding = true
	r.host.set("trailer", stub)
	r.host.set("_couple_watch", TowHost.COUPLE_WATCH_TICKS)
	var t: TruckTelemetry = r.vehicle.get("telemetry")
	t.trailer_connected = true
	t.trailer_axle_load = 19766
	r.vehicle.call("_tick_extras", VehicleInput.new(), DELTA)
	assert_bool(t.trailer_connected) \
		.override_failure_message("the bus still claimed a trailer that had just been refused") \
		.is_false()
	assert_float(t.trailer_axle_load) \
		.override_failure_message("the bus published the departed trailer's axle load").is_equal(0.0)


func test_dropping_a_body_while_moving_is_allowed_because_a_drop_lays_nothing() -> void:
	# The two cycles used to answer this differently: the semi asked may_couple() before looking at
	# what the next entry was, so a press that would merely have dropped the trailer was refused too
	# and bobtail was unreachable above walking pace.
	#
	# The tractor's order is right, because the refusal is about where a body would land and a drop
	# lays nothing. Complement of test_neither_machine_will_hitch_a_body_while_it_is_moving: same
	# speed, same key, opposite answer.
	for kind: String in KINDS:
		var r := _rig(kind)
		_spawn(r)
		# Park the cycle one press before the bare entry, so E is a real drop on both machines.
		r.vehicle.call("set_attachment", _press_before(r, r.bare_id))
		assert_bool(r.host.is_coupled()) \
			.override_failure_message("%s: nothing was on the back, so this tests nothing" % kind) \
			.is_true()
		r.vehicle.get("telemetry").speed = 8.0
		_reset_notices()
		r.vehicle.call("cycle_implement")
		assert_bool(r.host.is_coupled()) \
			.override_failure_message("%s: a drop at 29 km/h was refused as if it were a hitch" % kind) \
			.is_false()
		assert_str(r.vehicle.call("current_attachment")) \
			.override_failure_message("%s: the id still claims a body that was dropped" % kind) \
			.is_equal(r.bare_id)
		assert_int(_notices.size()) \
			.override_failure_message("%s: the driver was told why a press that WORKED did not" % kind) \
			.is_equal(0)
