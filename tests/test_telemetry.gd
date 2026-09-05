extends GdUnitTestSuite
## Telemetry derivations: pure static math. Motion from sim (no test); tested: GPS,
## heading, odometer, acceleration, impact gate, auxiliary systems, status packer.

const T := preload("res://src/vehicles/base/vehicle_telemetry.gd")
const TractorT := preload("res://src/vehicles/tractor/tractor_telemetry.gd")
const TruckT := preload("res://src/vehicles/truck/truck_telemetry.gd")
const BoatT := preload("res://src/vehicles/boat/boat_telemetry.gd")
const DroneT := preload("res://src/vehicles/drone/drone_telemetry.gd")
const PlaneT := preload("res://src/vehicles/plane/plane_telemetry.gd")
const TrainT := preload("res://src/vehicles/train/train_telemetry.gd")
const ContractScript := preload("res://src/bridge/contract.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")


# --- GPS mapping (world XZ -> lat/lon around Paris 48.8566, 2.3522) ---

func test_gps_lat_maps_north_to_higher_latitude() -> void:
	assert_float(T.gps_lat(0.0)).is_equal_approx(T.GPS_ORIGIN_LAT, 1e-9)
	# -Z is north: one degree of latitude north is METERS_PER_DEG_LAT metres of -Z.
	assert_float(T.gps_lat(-T.METERS_PER_DEG_LAT)).is_equal_approx(49.8566, 1e-6)
	assert_float(T.gps_lat(T.METERS_PER_DEG_LAT)).is_equal_approx(47.8566, 1e-6)


func test_gps_lon_shrinks_with_origin_latitude() -> void:
	assert_float(T.gps_lon(0.0)).is_equal_approx(T.GPS_ORIGIN_LON, 1e-9)
	var m_per_deg_lon := T.METERS_PER_DEG_LAT * cos(deg_to_rad(T.GPS_ORIGIN_LAT))
	assert_float(T.gps_lon(m_per_deg_lon)).is_equal_approx(3.3522, 1e-6)
	assert_float(T.gps_lon(-m_per_deg_lon)).is_equal_approx(1.3522, 1e-6)


# --- heading (0 = north/-Z, 90 = east/+X) ---

func test_heading_cardinals() -> void:
	assert_float(T.heading_from_forward(Vector3(0, 0, -1))).is_equal_approx(0.0, 1e-4)
	assert_float(T.heading_from_forward(Vector3(1, 0, 0))).is_equal_approx(90.0, 1e-4)
	assert_float(T.heading_from_forward(Vector3(0, 0, 1))).is_equal_approx(180.0, 1e-4)
	assert_float(T.heading_from_forward(Vector3(-1, 0, 0))).is_equal_approx(270.0, 1e-4)


# --- odometer ---

func test_odo_accumulates_absolute_distance_in_km() -> void:
	assert_float(T.odo_step(0.0, 10.0, 0.1)).is_equal_approx(0.001, 1e-9)
	# Reversing still adds distance.
	assert_float(T.odo_step(5.0, -20.0, 0.5)).is_equal_approx(5.01, 1e-9)
	assert_float(T.odo_step(1.0, 0.0, 0.5)).is_equal(1.0)


# --- body-frame acceleration ---

func test_body_accel_projects_onto_forward_right_and_up() -> void:
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var up := Vector3(0, 1, 0)
	# Gained 10 m/s forward over 0.1 s -> +100 m/s^2 longitudinal, 0 lateral, 0 vertical.
	var a := T.body_accel(Vector3(0, 0, -10), Vector3.ZERO, 0.1, fwd, right, up)
	assert_float(a.x).is_equal_approx(100.0, 1e-4)
	assert_float(a.y).is_equal_approx(0.0, 1e-4)
	assert_float(a.z).is_equal_approx(0.0, 1e-4)
	# Gained 5 m/s to the right over 0.5 s -> +10 m/s^2 lateral.
	var b := T.body_accel(Vector3(5, 0, 0), Vector3.ZERO, 0.5, fwd, right, up)
	assert_float(b.x).is_equal_approx(0.0, 1e-4)
	assert_float(b.y).is_equal_approx(10.0, 1e-4)
	# Gained 2 m/s upward over 0.25 s -> +8 m/s^2 on the third axis (the drone's acc_vert).
	var c := T.body_accel(Vector3(0, 2, 0), Vector3.ZERO, 0.25, fwd, right, up)
	assert_float(c.z).is_equal_approx(8.0, 1e-4)
	assert_float(c.x).is_equal_approx(0.0, 1e-4)
	# Zero/negative delta is guarded.
	assert_vector(T.body_accel(Vector3(9, 9, 9), Vector3.ZERO, 0.0, fwd, right, up)) \
		.is_equal(Vector3.ZERO)


## Kinematic (contract acc_vert desc): reports changes in motion, not gravity.
## At rest reads zero, not +9.8 up.
func test_body_accel_carries_no_gravity_term() -> void:
	var v := Vector3(3, -7, 2)
	assert_vector(T.body_accel(v, v, 1.0 / 60.0, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3.UP)) \
		.is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)


# --- impact gate ---

func test_impact_gate_thresholds() -> void:
	assert_float(T.impact_gate(30.0, 25.0)).is_equal(30.0)
	assert_float(T.impact_gate(25.0, 25.0)).is_equal(25.0)
	assert_float(T.impact_gate(10.0, 25.0)).is_equal(0.0)


# --- fuel model ---

func test_fuel_burns_only_while_running_and_clamps() -> void:
	assert_float(T.fuel_step(80.0, 1.0, false, 1.0)).is_equal(80.0)  # engine off: no burn
	assert_float(T.fuel_step(100.0, 0.0, true, 1.0)).is_equal_approx(99.98, 1e-6)  # idle
	assert_float(T.fuel_step(100.0, 1.0, true, 1.0)).is_equal_approx(99.8, 1e-6)   # full load
	# Never goes below empty.
	assert_float(T.fuel_step(0.05, 1.0, true, 1.0)).is_equal(0.0)
	# Load monotonically increases burn.
	assert_float(T.fuel_step(50.0, 1.0, true, 1.0)).is_less(T.fuel_step(50.0, 0.0, true, 1.0))


# --- coolant model ---

func test_coolant_target_warms_with_load() -> void:
	assert_float(T.coolant_target(false, 1.0)).is_equal(T.COOLANT_AMBIENT)
	assert_float(T.coolant_target(true, 0.0)).is_equal(T.COOLANT_OPERATING)
	assert_float(T.coolant_target(true, 1.0)).is_equal(T.COOLANT_HOT)


func test_coolant_step_chases_target_without_overshoot() -> void:
	assert_float(T.coolant_step(20.0, 90.0, 2.0, 1.0)).is_equal_approx(22.0, 1e-6)
	# move_toward never passes the target.
	assert_float(T.coolant_step(89.5, 90.0, 2.0, 1.0)).is_equal(90.0)
	assert_float(T.coolant_step(90.0, 90.0, 2.0, 1.0)).is_equal(90.0)


# --- battery model ---

func test_battery_charges_when_running_droops_under_load() -> void:
	assert_float(T.battery_volts(false, 1.0)).is_equal(T.BATTERY_RESTING)
	assert_float(T.battery_volts(true, 0.0)).is_equal(T.BATTERY_CHARGING)
	assert_float(T.battery_volts(true, 1.0)).is_equal_approx(T.BATTERY_CHARGING - 0.6, 1e-6)


# --- status bitfield ---

func test_pack_status_sets_expected_bits() -> void:
	# Running, grounded, moving, in D3: ignition + ground + moving, no gear/aux bits.
	assert_int(T.pack_status(true, true, true, 3, false, false)) \
			.is_equal(T.ST_IGNITION | T.ST_GROUND | T.ST_MOVING)
	# Reverse sets the reverse bit (0xFF is R).
	assert_int(T.pack_status(true, true, true, 0xFF, false, false)) \
			.is_equal(T.ST_IGNITION | T.ST_GROUND | T.ST_MOVING | T.ST_REVERSE)
	# Parked in N with handbrake and headlights on, engine off.
	assert_int(T.pack_status(false, false, false, 0, true, true)) \
			.is_equal(T.ST_NEUTRAL | T.ST_HANDBRAKE | T.ST_HEADLIGHTS)


## The seam a wheel-less vehicle answers ST_GROUND through (the drone's landed predicate
## writes over the packed word with it). It must touch NOTHING but the named bit, in either
## direction, or a vehicle correcting its own bit would clear someone else's.
func test_with_status_bit_sets_and_clears_only_that_bit() -> void:
	var packed := T.pack_status(true, true, true, 3, false, true)
	assert_int(T.with_status_bit(packed, T.ST_GROUND, false)) \
			.is_equal(T.ST_IGNITION | T.ST_MOVING | T.ST_HEADLIGHTS)
	# Setting an already-set bit and clearing an already-clear one are both no-ops.
	assert_int(T.with_status_bit(packed, T.ST_GROUND, true)).is_equal(packed)
	assert_int(T.with_status_bit(packed, T.ST_REVERSE, false)).is_equal(packed)
	assert_int(T.with_status_bit(packed, T.ST_REVERSE, true)).is_equal(packed | T.ST_REVERSE)


# --- struct defaults ---

func test_fresh_telemetry_has_sane_defaults() -> void:
	var t := T.new()
	assert_float(t.fuel).is_equal(100.0)
	assert_float(t.coolant).is_equal(T.COOLANT_AMBIENT)
	assert_float(t.battery).is_equal(T.BATTERY_RESTING)
	assert_float(t.lat).is_equal(T.GPS_ORIGIN_LAT)
	assert_float(t.odo).is_equal(0.0)


# --- bridge marshaling conformance ----------------------
## to_bridge_dict must supply a value for every non-todo "out" signal a ground vehicle
## declares — otherwise the Bridge would silently drop it. Mirrors test_contract's
## undefined-signal guard, from the telemetry side.

func test_to_bridge_dict_covers_every_ground_out_signal() -> void:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var contract := ContractScript.ContractData.parse(file.get_as_text())
	# The truck/tractor/boat/drone/plane/train publish via their telemetry subclasses
	# (extra out fields), so their coverage must be checked against those subclasses, not the
	# base struct — mapping the truck to the base struct here would silently stop covering
	# every J1939 chassis signal the moment one was added.
	var keys_by_vehicle := {
		"car": T.new().to_bridge_dict().keys(),
		"truck": TruckT.new().to_bridge_dict().keys(),
		"tractor": TractorT.new().to_bridge_dict().keys(),
		"boat": BoatT.new().to_bridge_dict().keys(),
		"drone": DroneT.new().to_bridge_dict().keys(),
		"plane": PlaneT.new().to_bridge_dict().keys(),
		"train": TrainT.new().to_bridge_dict().keys(),
	}
	for vehicle in keys_by_vehicle:
		var keys: Array = keys_by_vehicle[vehicle]
		for sig in contract.signals_for_vehicle(vehicle, "out"):
			if sig.todo:
				continue
			assert_bool(keys.has(sig.name)) \
				.override_failure_message("to_bridge_dict missing '%s' out signal: %s" % [vehicle, sig.name]) \
				.is_true()


## The mirror of the coverage test, and the guard on the property-list walk: every key
## to_bridge_dict produces must be a contract out-signal SOMEWHERE. A telemetry class whose
## member vars are all wire signals is what makes the walk safe, and nothing else pins it —
## add a private/cache field to one of these structs and it becomes a bridge key silently.
## Union across families, not per-family: the base struct hands `engine_hours`/`speed_limit`
## to machines that never declare them, which is pre-existing and harmless.

func test_to_bridge_dict_invents_no_signal() -> void:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var contract := ContractScript.ContractData.parse(file.get_as_text())
	var known := {}
	for vehicle in ["car", "truck", "tractor", "boat", "drone", "plane", "train"]:
		for sig in contract.signals_for_vehicle(vehicle, "out"):
			known[sig.name] = true
	var dicts := {
		"car": T.new().to_bridge_dict(),
		"truck": TruckT.new().to_bridge_dict(),
		"tractor": TractorT.new().to_bridge_dict(),
		"boat": BoatT.new().to_bridge_dict(),
		"drone": DroneT.new().to_bridge_dict(),
		"plane": PlaneT.new().to_bridge_dict(),
		"train": TrainT.new().to_bridge_dict(),
	}
	for vehicle in dicts:
		for key in (dicts[vehicle] as Dictionary):
			assert_bool(known.has(key)) 				.override_failure_message("to_bridge_dict invents '%s' key: %s" % [vehicle, key]) 				.is_true()


## An INSTANCED signal (contract 'count' > 1) must be an Array of exactly that many
## numbers — the shape Bridge._publish enforces at runtime, checked here at build time so
## a telemetry field that is the wrong length fails CI instead of going quiet on the bus
## behind a warn-once push_warning. A struct that has never ticked still has to be the
## right SHAPE, which is why the drone's ESC arrays are sized at their declaration.
func test_to_bridge_dict_shapes_every_instanced_out_signal() -> void:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var contract := ContractScript.ContractData.parse(file.get_as_text())
	var dict_by_vehicle := {
		"car": T.new().to_bridge_dict(),
		"truck": TruckT.new().to_bridge_dict(),
		"tractor": TractorT.new().to_bridge_dict(),
		"boat": BoatT.new().to_bridge_dict(),
		"drone": DroneT.new().to_bridge_dict(),
		"plane": PlaneT.new().to_bridge_dict(),
		"train": TrainT.new().to_bridge_dict(),
	}
	var instanced := 0
	for vehicle in dict_by_vehicle:
		var d: Dictionary = dict_by_vehicle[vehicle]
		for sig in contract.signals_for_vehicle(vehicle, "out"):
			if sig.todo or sig.count <= 1:
				continue
			instanced += 1
			var v: Variant = d.get(sig.name)
			assert_int(typeof(v)) \
				.override_failure_message("'%s' %s must be an Array (count %d)" % [vehicle, sig.name, sig.count]) \
				.is_equal(TYPE_ARRAY)
			assert_int((v as Array).size()) \
				.override_failure_message("'%s' %s wrong length" % [vehicle, sig.name]).is_equal(sig.count)
			for element: Variant in (v as Array):
				assert_bool(typeof(element) == TYPE_INT or typeof(element) == TYPE_FLOAT) \
					.override_failure_message("'%s' %s element is not a number" % [vehicle, sig.name]).is_true()
	# ...and the sweep is actually sweeping something (the drone's ESC/node signals, and since
	# v30 `slip` on every wheeled family — the first instanced signal that is not the drone's).
	assert_int(instanced).is_greater(0)


## THE PER-AXLE SPLIT (v30). The bridge only checks the SHAPE; what it cannot check is that the
## two elements are the right way round, and front/rear reversed is a bug that looks like working
## telemetry — an understeering car would read as oversteering on the bus and nowhere else.
func test_slip_publishes_front_then_rear_in_contract_index_order() -> void:
	var t := T.new()
	t.slip_front = 0.25
	t.slip_rear = 0.75
	var v: Variant = t.to_bridge_dict()["slip"]
	assert_int(typeof(v)).is_equal(TYPE_ARRAY)
	assert_array(v as Array) 		.override_failure_message("slip element 0 is the FRONT axle, element 1 the rear") 		.is_equal([0.25, 0.75])
	# A plain Array, not a Packed one: JSON.stringify is what puts it on the wire, and a
	# PackedFloat32Array would still pass the bridge's shape check and then not serialize.
	assert_int(typeof(v)).is_not_equal(TYPE_PACKED_FLOAT32_ARRAY)


# --- hour meter, shared tractor/truck (J1939 SPN 247) -------------------------

func test_engine_hours_accumulate_only_while_running() -> void:
	assert_float(T.hours_step(0.0, false, 3600.0)).is_equal(0.0)
	assert_float(T.hours_step(0.0, true, 3600.0)).is_equal_approx(1.0, 1e-9)
	# One 60 Hz tick under the key.
	assert_float(T.hours_step(0.0, true, 1.0 / 60.0)).is_equal_approx(1.0 / 216000.0, 1e-12)
	# Monotonic: it only ever climbs from where it was.
	assert_float(T.hours_step(12.5, true, 1800.0)).is_equal_approx(13.0, 1e-9)


# --- engine-load model, shared tractor/truck (modeled honest value) -----------
## Delivered torque over the PEAK of the curve. A round inline spec keeps every expectation
## hand-checkable: peak 200 Nm at 2000 rpm, half that (100) at 1000, redline 4000.

func _load_spec() -> VehicleSpecScript:
	var spec: VehicleSpecScript = VehicleSpecScript.new()
	spec.torque_curve = PackedVector2Array([
		Vector2(1000, 100), Vector2(2000, 200), Vector2(3000, 100)])
	spec.redline_rpm = 4000.0
	return spec


func test_engine_load_scales_with_throttle_at_a_fixed_rpm() -> void:
	var spec := _load_spec()
	assert_float(T.engine_load_pct(2000.0, 0.0, spec, false, 0.35)).is_equal(0.0)
	# At peak-torque rpm the engine can make all 200 Nm, so full throttle IS full load.
	assert_float(T.engine_load_pct(2000.0, 1.0, spec, false, 0.35)).is_equal(100.0)
	assert_float(T.engine_load_pct(2000.0, 0.5, spec, false, 0.35)).is_equal_approx(50.0, 1e-4)
	# Reverse throttle loads the engine just the same.
	assert_float(T.engine_load_pct(2000.0, -0.5, spec, false, 0.35)).is_equal_approx(50.0, 1e-4)


func test_engine_load_is_rpm_aware_not_a_second_pedal_readout() -> void:
	# Load follows engine's curve position (off peak can't make full torque, so not full load).
	var spec := _load_spec()
	var at_peak := T.engine_load_pct(2000.0, 1.0, spec, false, 0.35)
	var lugging := T.engine_load_pct(1000.0, 1.0, spec, false, 0.35)
	var revved := T.engine_load_pct(3000.0, 1.0, spec, false, 0.35)
	assert_float(lugging).is_equal_approx(50.0, 1e-4)  # 100 of 200 Nm
	assert_float(revved).is_equal_approx(50.0, 1e-4)   # 100 of 200 Nm
	assert_float(at_peak).is_greater(lugging)
	assert_float(at_peak).is_greater(revved)
	# The rev limiter reaches this signal through the THROTTLE, not the rpm: it is a fuel cut,
	# and `Drivetrain.applied_throttle` — which is what every caller passes here — carries it.
	# The curve itself keeps saying what the engine makes at 4000 (100 Nm), which is honest;
	# with the fuel cut there is no load.
	assert_float(T.engine_load_pct(4000.0, 1.0, spec, false, 0.35)).is_equal_approx(50.0, 1e-4)
	assert_float(T.engine_load_pct(4000.0, 0.0, spec, false, 0.35)).is_equal(0.0)


func test_engine_load_adds_the_pto_parasitic_term_and_clamps() -> void:
	var spec := _load_spec()
	# 50 % of the curve + a 35 % parasitic draw.
	assert_float(T.engine_load_pct(2000.0, 0.5, spec, true, 0.35)).is_equal_approx(85.0, 1e-4)
	# Clamped at 100 %.
	assert_float(T.engine_load_pct(2000.0, 0.9, spec, true, 0.35)).is_equal(100.0)
	# An engine with no torque curve reports nothing rather than dividing by zero.
	var curveless: VehicleSpecScript = VehicleSpecScript.new()
	curveless.torque_curve = PackedVector2Array()
	assert_float(T.engine_load_pct(2000.0, 1.0, curveless, false, 0.35)).is_equal(0.0)


# --- train telemetry struct ---

func test_train_telemetry_rests_at_charged_pipe_and_lowered_pantograph() -> void:
	var t := TrainT.new()
	assert_bool(t.pantograph_state).is_false()
	assert_bool(t.doors_state).is_false()
	assert_float(t.brake_pipe).is_equal(TrainT.BRAKE_PIPE_CHARGED)
	assert_float(t.catenary_volts).is_equal(0.0)
	assert_int(t.grade).is_equal(0)  # contract 'grade' is i8 (integer percent)
	assert_float(t.coupler_force).is_equal(0.0)
