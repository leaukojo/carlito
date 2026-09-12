extends GdUnitTestSuite
## DroneIndicators' mappings, and drone-mk2, the airframe that draws every drone feature: its rig
## pinned to the model's pivots, and a ticked craft whose drawn parts follow the published state.
## The rig is test_drone_vehicle's: pose scripted, the base's two calls made directly at 1/60.

const Router := preload("res://src/input/input_router.gd")
const Layers := preload("res://src/physics/collision_layers.gd")
const Sensors := preload("res://src/vehicles/drone/drone_sensors.gd")
const Modes := preload("res://src/vehicles/drone/drone_modes.gd")
const Bus := preload("res://src/vehicles/drone/drone_bus.gd")
const Arming := preload("res://src/vehicles/drone/drone_arming.gd")
const Ind := preload("res://src/vehicles/drone/drone_indicators.gd")

const MK2 := "res://src/vehicles/drone/drone_mk2.tscn"
const BODY_GLB := "res://src/vehicles/drone/models/drone_mk2_body.glb"
const CRATE := "res://src/levels/base/cargo_payload.tscn"
const DELTA := 1.0 / 60.0
## Ticks until a position fix is available: full ray sweep + FIX_DEBOUNCE + margin.
const FIX_TICKS := int(float(Sensors.SKY_RAYS) / float(Sensors.SKY_RAYS_PER_TICK)) \
		+ int(Modes.FIX_DEBOUNCE / DELTA) + 4


class Rig extends RefCounted:
	var root: Node3D
	var drone: DroneVehicle
	var t: DroneTelemetry
	var input: VehicleInput

	func tick(n := 1) -> void:
		for _i in n:
			drone._update_telemetry(input, DELTA)
			drone._tick_extras(input, DELTA)

	func seconds(s: float) -> void:
		tick(int(round(s / DELTA)))

	## Arming is a rising edge: down for a tick first.
	func arm() -> void:
		input.arm = false
		tick()
		input.arm = true
		tick()

	## The colour a drawn LED is lit with right now.
	func led(path: String) -> Color:
		return ((drone.get_node(path) as MeshInstance3D).material_override as StandardMaterial3D).emission


## One awaited frame, then the pose: a body is not in the space state until the space has stepped.
func _rig(pos := Vector3(0.0, 50.0, 0.0), floor_y := NAN) -> Rig:
	var r := Rig.new()
	r.root = auto_free(Node3D.new()) as Node3D
	add_child(r.root)
	if not is_nan(floor_y):
		var ground := StaticBody3D.new()
		ground.collision_layer = Layers.TERRAIN
		ground.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400.0, 10.0, 400.0)
		shape.shape = box
		ground.add_child(shape)
		r.root.add_child(ground)
		ground.global_position = Vector3(pos.x, floor_y - 5.0, pos.z)
	r.drone = (load(MK2) as PackedScene).instantiate() as DroneVehicle
	r.root.add_child(r.drone)
	await get_tree().physics_frame
	r.drone.global_position = pos
	r.drone.linear_velocity = Vector3.ZERO
	r.drone.angular_velocity = Vector3.ZERO
	r.t = r.drone.telemetry as DroneTelemetry
	r.input = VehicleInput.new()
	r.input.key = Router.KEY_IGNITION
	return r


func _crate(r: Rig, pos: Vector3) -> CargoPayload:
	var c := (load(CRATE) as PackedScene).instantiate() as CargoPayload
	r.root.add_child(c)
	c.global_position = pos
	c.freeze = true
	await get_tree().physics_frame
	c.global_position = pos
	return c


func _assert_color(actual: Color, expected: Color, what: String) -> void:
	assert_bool(actual.is_equal_approx(expected)).override_failure_message(
			"%s is lit %s, expected %s" % [what, actual, expected]).is_true()


## A node's position in the scene root's frame, walked through its parents (out of the tree, so
## there is no global transform to ask for).
static func _root_position(root: Node, node: Node3D) -> Vector3:
	var xf := node.transform
	var up := node.get_parent()
	while up != root:
		xf = (up as Node3D).transform * xf
		up = up.get_parent()
	return xf.origin


# --- what each light says ---------------------------------------------------------------------

func test_the_fc_led_is_dark_unpowered_red_in_a_failsafe_else_one_colour_per_arming_state() -> void:
	_assert_color(Ind.fc_color(false, Arming.ARMED, Arming.FS_NONE), Ind.OFF, "unpowered FC")
	_assert_color(Ind.fc_color(true, Arming.DISARMED, Arming.FS_NONE), Ind.BLUE, "disarmed")
	_assert_color(Ind.fc_color(true, Arming.BLOCKED, Arming.FS_NONE), Ind.AMBER, "blocked")
	_assert_color(Ind.fc_color(true, Arming.ARMED, Arming.FS_NONE), Ind.GREEN, "armed")
	_assert_color(Ind.fc_color(true, Arming.ARMED, Arming.FS_BATT_LOW), Ind.RED, "failsafe")
	# ...and no power dominates even a failsafe: an absent FC is not reacting to anything.
	_assert_color(Ind.fc_color(false, Arming.DISARMED, Arming.FS_BATT_CRIT), Ind.OFF, "flat FC")


func test_the_gps_led_is_green_only_on_a_3d_fix() -> void:
	_assert_color(Ind.gps_color(Sensors.FIX_3D), Ind.GREEN, "3D fix")
	_assert_color(Ind.gps_color(Sensors.FIX_2D), Ind.AMBER, "2D fix")
	_assert_color(Ind.gps_color(Sensors.FIX_TIME_ONLY), Ind.RED, "time-only fix")
	_assert_color(Ind.gps_color(Sensors.FIX_NONE), Ind.RED, "no fix")


func test_an_esc_led_reads_the_node_strip_health() -> void:
	_assert_color(Ind.health_color(Bus.HEALTH_OK), Ind.GREEN, "OK")
	_assert_color(Ind.health_color(Bus.HEALTH_WARNING), Ind.AMBER, "hot")
	_assert_color(Ind.health_color(Bus.HEALTH_CRITICAL), Ind.RED, "offline")


func test_the_gauge_lights_a_bar_per_started_quarter_and_turns_red_at_the_rtl_threshold() -> void:
	assert_int(Ind.soc_bars(100.0)).is_equal(4)
	assert_int(Ind.soc_bars(75.5)).is_equal(4)
	assert_int(Ind.soc_bars(75.0)).is_equal(3)
	assert_int(Ind.soc_bars(25.0)).is_equal(1)
	assert_int(Ind.soc_bars(0.5)).is_equal(1)
	assert_int(Ind.soc_bars(0.0)).is_equal(0)
	_assert_color(Ind.gauge_color(Arming.SOC_LOW), Ind.GREEN, "gauge at the threshold")
	_assert_color(Ind.gauge_color(Arming.SOC_LOW - 0.1), Ind.RED, "gauge under it")


func test_the_beam_runs_from_the_lens_to_the_measured_ground_and_not_without_a_return() -> void:
	assert_float(Ind.beam_length(0.3, 0.034)).is_equal_approx(0.266, 1e-6)
	assert_float(Ind.beam_length(Sensors.RANGE_INVALID, 0.034)).is_equal(0.0)
	# Ground above the lens (the lens is below the origin that measured): nothing to draw.
	assert_float(Ind.beam_length(0.02, 0.034)).is_equal(0.0)


# --- the airframe -----------------------------------------------------------------------------

func test_every_rig_node_sits_on_its_model_pivot() -> void:
	# tools/gen_drone_model.py and drone_mk2.tscn state every pivot once each; this is what stops
	# the two drifting apart.
	var model: Node = auto_free((load(BODY_GLB) as PackedScene).instantiate())
	var drone: Node = auto_free((load(MK2) as PackedScene).instantiate())
	var pinned := 0
	for child in model.get_children():
		if not String(child.name).begins_with("Pivot_"):
			continue
		var target := String(child.name).trim_prefix("Pivot_")
		var node := drone.find_child(target, true, false) as Node3D
		assert_object(node).override_failure_message("drone_mk2.tscn has no %s" % target) \
				.is_not_null()
		if node == null:
			continue
		assert_vector(_root_position(drone, node)).override_failure_message(
				"%s is off its model pivot %s" % [target, (child as Node3D).position]) \
				.is_equal_approx((child as Node3D).position, Vector3.ONE * 1e-3)
		pinned += 1
	assert_int(pinned).is_greater(20)


func test_every_lamp_the_shared_spec_names_is_on_the_mk2() -> void:
	# Both drones load drone_spec.tres, and LampSet skips a missing node silently: right for the
	# plain drone, which has no spotlight, and a hidden failure for a renamed lamp here.
	var drone := auto_free((load(MK2) as PackedScene).instantiate()) as DroneVehicle
	var spec := drone.spec
	assert_int(spec.lamp_style).is_equal(VehicleSpec.LampStyle.AIRCRAFT)
	for paths: Array[NodePath] in [spec.headlight_paths, spec.head_lamp_paths, spec.led_lamp_paths]:
		assert_int(paths.size()).is_greater(0)
		for path in paths:
			assert_object(drone.get_node_or_null(path)).override_failure_message(
					"drone_mk2.tscn has no %s" % path).is_not_null()


# --- a ticked mk2 ------------------------------------------------------------------------------

func test_the_status_leds_follow_the_published_state() -> void:
	var r: Rig = await _rig()
	r.tick(FIX_TICKS)
	_assert_color(r.led("FcLed"), Ind.BLUE, "FC, disarmed")
	_assert_color(r.led("GpsLed"), Ind.GREEN, "GNSS under open sky")
	for i in Ind.GAUGE_BARS:
		_assert_color(r.led("BattBar%d" % i), Ind.GREEN, "full pack's bar %d" % i)
	r.arm()
	_assert_color(r.led("FcLed"), Ind.GREEN, "FC, armed")
	r.input.node_fail = 1 << 0
	r.tick()
	_assert_color(r.led("EscLed0"), Ind.RED, "ESC1 off the bus")
	_assert_color(r.led("EscLed1"), Ind.GREEN, "ESC2")
	# A dead motor is a failsafe, and a failsafe outranks the arming state.
	_assert_color(r.led("FcLed"), Ind.RED, "FC in the motor failsafe")


func test_the_drawn_gimbal_composes_to_the_hood_camera() -> void:
	var r: Rig = await _rig()
	r.input.gimbal_pitch = -45.0
	r.input.gimbal_yaw = 60.0
	r.seconds(3.0)
	assert_float(r.t.gimbal_pitch_actual).is_equal_approx(-45.0, 1e-3)
	var yaw := (r.drone.get_node("GimbalYaw") as Node3D).transform.basis
	var pitch := (r.drone.get_node("GimbalYaw/GimbalPitch") as Node3D).transform.basis
	var cam := (r.drone.get_node("HoodCam") as Node3D).transform.basis
	var drawn := yaw * pitch
	for axis in 3:
		assert_vector(drawn[axis]).is_equal_approx(cam[axis], Vector3.ONE * 1e-5)
	# ...and it really moved: the lens looks 45 degrees down.
	assert_float((-drawn.z).y).is_equal_approx(-sin(deg_to_rad(45.0)), 1e-4)


func test_the_rangefinder_beam_reaches_the_floor_and_goes_dark_off_the_bus() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(2)
	var beam := r.drone.get_node("RangeBeam") as MeshInstance3D
	assert_float(r.t.agl).is_equal_approx(0.3, 1e-3)
	assert_bool(beam.visible).is_true()
	var xf := beam.global_transform
	assert_float(xf.origin.y - xf.basis.y.length() * 0.5).is_equal_approx(0.0, 1e-3)
	r.input.node_fail = 1 << Bus.index_of("RANGE")
	r.tick(2)
	assert_bool(beam.visible).is_false()


func test_the_jaws_shut_only_on_a_closed_latch() -> void:
	var r: Rig = await _rig(Vector3(0.0, 1.2, 0.0), 0.0)
	var jaw := r.drone.get_node("Hardpoint/JawL") as Node3D
	# Open with nothing on the hook: the jaw has swung out about its hinge, so its x axis tips down.
	assert_float(jaw.transform.basis.x.y).is_less(-0.1)
	await _crate(r, Vector3.ZERO)
	r.input.hardpoint_cmd = true
	r.tick(2)
	assert_bool(r.t.hardpoint_state).is_true()
	assert_vector(jaw.transform.basis.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 1e-5)
	r.input.hardpoint_cmd = false
	r.tick(2)
	assert_float(jaw.transform.basis.x.y).is_less(-0.1)


func test_each_wash_disc_fades_in_with_its_own_motor() -> void:
	var r: Rig = await _rig()
	var disc_fl := (r.drone.get_node("RotorFL/Blur") as MeshInstance3D).material_override \
			as StandardMaterial3D
	var disc_fr := (r.drone.get_node("RotorFR/Blur") as MeshInstance3D).material_override \
			as StandardMaterial3D
	r.drone._process(DELTA)
	assert_float(disc_fl.albedo_color.a).is_equal(0.0)
	r.tick(FIX_TICKS)
	r.arm()
	r.seconds(1.0)
	r.drone._process(DELTA)
	assert_float(disc_fl.albedo_color.a).is_greater(0.05)
	# A dropped ESC spools its prop down and its disc fades with it; the others keep theirs.
	r.input.node_fail = 1 << 0
	r.seconds(1.0)
	r.drone._process(DELTA)
	assert_float(disc_fl.albedo_color.a).is_less(0.01)
	assert_float(disc_fr.albedo_color.a).is_greater(0.05)
