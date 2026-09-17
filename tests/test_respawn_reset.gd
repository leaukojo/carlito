extends GdUnitTestSuite
## A respawn is a RESET: `BaseVehicle.reset_session_state` hands back a machine indistinguishable
## from a freshly instanced one, down to the odometer and the hour meter.
##
## The sweep is generic on purpose. It perturbs EVERY script property of a family's telemetry,
## respawns, and demands the whole object back — so a field added to any telemetry subclass is
## covered here the day it is declared, with no list to keep up to date. The reference is the
## vehicle's OWN reset state rather than a second body, which is what makes "speed_limit is copied
## off the spec" and "the drone publishes its pack's volts, not a car's 12.6" need no exceptions.

const Layers := preload("res://src/physics/collision_layers.gd")

## One body per family. The rest of each family is the same class over a different spec.
const FAMILIES := ["car", "truck", "tractor", "boat", "drone", "plane", "train"]


func _spawn(variant: String) -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	# A floor so a wheeled body has something to sit on; nothing here ticks physics, but a RayWheel
	# reset that finds no ground must still be the reset state the reference was taken in.
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 10.0, 400.0)
	shape.shape = box
	ground.add_child(shape)
	root.add_child(ground)
	ground.global_position = Vector3(0.0, -5.0, 0.0)
	var vehicle := (load(VehicleCatalog.scene_of(variant)) as PackedScene).instantiate() as BaseVehicle
	root.add_child(vehicle)
	# Bodies are not in the space state until the space has stepped once; the pose goes on after.
	await get_tree().physics_frame
	vehicle.global_position = Vector3(0.0, 2.0, 0.0)
	vehicle.spawn_transform = vehicle.global_transform
	return vehicle


## Every script property of `t`, arrays copied so a later element write does not edit the snapshot.
static func _snapshot(t: VehicleTelemetry) -> Dictionary:
	var out := {}
	for prop in t.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = t.get(prop.name)
			out[prop.name] = (v as Array).duplicate() if v is Array else v
	return out


## Drive a value away from whatever it is, whatever it is. Returns the field names it could not
## move, so the caller can fail on a type this sweep does not know how to perturb.
static func _perturb(t: VehicleTelemetry) -> PackedStringArray:
	var untouched := PackedStringArray()
	for prop in t.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = prop.name
		var v: Variant = t.get(field)
		if v is bool:
			t.set(field, not bool(v))
		elif v is int:
			t.set(field, int(v) + 37)
		elif v is float:
			t.set(field, float(v) + 41.5)
		elif v is Array:
			# Element-wise, never a fresh array: that is the rule the published per-ESC store lives
			# by, and this has to leave the same object in place to test the reseed honestly.
			var arr: Array = v
			for i in arr.size():
				arr[i] = (arr[i] + 37) if arr[i] is int else (arr[i] + 41.5)
		else:
			untouched.append(field)
	return untouched


# --- the sweep ----------------------------------------------------------------


func test_every_family_respawns_to_its_as_built_telemetry() -> void:
	for family in FAMILIES:
		var variant := VehicleCatalog.first_in_family(family)
		var v: BaseVehicle = await _spawn(variant)
		v.respawn()
		var ref_state := _snapshot(v.telemetry)

		var untouched := _perturb(v.telemetry)
		assert_array(untouched) \
				.override_failure_message(("%s telemetry carries %s, a type this sweep cannot " \
						+ "perturb — teach `_perturb` about it rather than listing it as an " \
						+ "exception, or the field is untested.") % [variant, untouched]) \
				.is_empty()

		v.respawn()
		var now := _snapshot(v.telemetry)
		for field in ref_state:
			assert_that(now[field]) \
					.override_failure_message(("%s: telemetry.%s survived a respawn (%s, expected " \
							+ "%s). Reseed it in that family's `reset_session_state`.") \
							% [variant, field, now[field], ref_state[field]]) \
					.is_equal(ref_state[field])


## The dashboard and the bridge each resolve `telemetry` once per vehicle change and cache the
## reference, so a respawn that handed back a NEW object would leave both publishing a detached
## instance — stale forever, with nothing logged.
func test_respawn_reseeds_the_telemetry_object_rather_than_replacing_it() -> void:
	for family in FAMILIES:
		var v: BaseVehicle = await _spawn(VehicleCatalog.first_in_family(family))
		var same: VehicleTelemetry = v.telemetry
		v.respawn()
		assert_object(v.telemetry) \
				.override_failure_message("%s replaced its telemetry object on respawn" % family) \
				.is_same(same)


## The named half of the sweep: the four things a driver would notice, spelled out so a failure
## says what broke rather than which property index moved.
func test_the_aux_models_and_the_life_meters_start_over() -> void:
	var v: BaseVehicle = await _spawn(VehicleCatalog.first_in_family("truck"))
	var t := v.telemetry
	t.fuel = 12.0
	t.coolant = 104.0
	t.odo = 415.0
	t.engine_hours = 9.5
	v.respawn()
	assert_float(t.fuel).is_equal(100.0)
	assert_float(t.coolant).is_equal(VehicleTelemetry.COOLANT_AMBIENT)
	# The life meters go too: a respawn is a new machine, not the same one towed home.
	assert_float(t.odo).is_equal(0.0)
	assert_float(t.engine_hours).is_equal(0.0)


## A respawn while rolling backwards used to come back still in R, because nothing rebuilt the
## gearbox — the direction latch `InputRouter.arbitrate_local` reads lives in `Drivetrain`.
func test_respawn_hands_back_a_gearbox_in_neutral() -> void:
	var v: BaseVehicle = await _spawn(VehicleCatalog.first_in_family("car"))
	v.drivetrain.gear_byte = Drivetrain.GEAR_R
	v.respawn()
	assert_int(v.get_gear_byte()).is_equal(Drivetrain.GEAR_N)


## The airframe cycles are InputRouter's, and a respawn clears them through the same call a new
## body does (`reset_vehicle_cycles`) — the keys are bound globally, so one left latched follows
## you. The other toggles are DRIVER state and survive both, exactly as they do today.
func test_respawn_clears_the_airframe_cycles_but_not_the_driver_toggles() -> void:
	var v: BaseVehicle = await _spawn(VehicleCatalog.first_in_family("drone"))
	InputRouter.set("_node_fail", 1 << 0)
	InputRouter.set("_flight_mode", 2)
	InputRouter.set("_nav_mode", 1)
	InputRouter.set("_sheet", 3)
	InputRouter.set("_hardpoint", true)
	InputRouter.set("_lights", 3)
	InputRouter.set("_pto", true)
	v.respawn()
	assert_int(InputRouter.get("_node_fail")).is_equal(0)
	assert_int(InputRouter.get("_flight_mode")).is_equal(0)
	assert_int(InputRouter.get("_nav_mode")).is_equal(0)
	assert_int(InputRouter.get("_sheet")).is_equal(0)
	assert_bool(InputRouter.get("_hardpoint")).is_false()
	assert_int(InputRouter.get("_lights")).is_equal(3)
	assert_bool(InputRouter.get("_pto")).is_true()
