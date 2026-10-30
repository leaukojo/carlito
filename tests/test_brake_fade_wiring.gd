extends GdUnitTestSuite
## Brake heat wired into the spin step (`WheelDrive.tick`, `TowedBody.tick_towed`): the service
## brake fades with its wheel's temperature, the parking brake heats but never fades, and only the
## friction brakes' share of the reacted torque heats. Bodies are frozen far above nothing, so every
## wheel ticks airborne: its step's compliance is `delta / I` and `brake_spin / spin_compliance` is
## exactly the torque commanded.

const TICK := 1.0 / 60.0
const AMB := BrakeThermal.AMBIENT_C
## Past the PAD curve's last point: the service brake at half its cold torque.
const HOT := 750.0
const C := 4000.0


## A four-wheel bench body, insulated PAD brakes on both axles (cooling and radiation off, so the
## heat in is all `C ΔT`).
func _bench_spec() -> VehicleSpec:
	var gd := GroundDriveSpec.new()
	gd.wheel_positions = [
		Vector3(-0.8, 0.0, -1.3), Vector3(0.8, 0.0, -1.3),
		Vector3(-0.8, 0.0, 1.3), Vector3(0.8, 0.0, 1.3),
	]
	gd.wheel_radius = 0.36
	gd.wheel_inertia = 4.0
	gd.tyre_half_width = 0.1
	gd.rest_length = 0.3
	gd.brake_heat_capacity = C
	gd.brake_heat_capacity_rear = C
	gd.brake_fade_curve = BrakeThermal.FadeCurve.PAD
	gd.brake_fade_curve_rear = BrakeThermal.FadeCurve.PAD
	var spec := VehicleSpec.new()
	spec.mass = 1500.0
	spec.final_drive = 4.0
	spec.ground_drive = gd
	return spec


## A frozen body high above an empty world, its drive built and every wheel spinning at 50 rad/s.
func _rig(spec: VehicleSpec) -> Array:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var body := RigidBody3D.new()
	body.freeze = true
	body.collision_layer = 0
	root.add_child(body)
	body.global_position = Vector3(0.0, 100.0, 0.0)
	await get_tree().physics_frame
	var drive := WheelDrive.new(body, spec)
	for w in drive.wheels:
		w.omega = 50.0
	return [body, drive]


func _tick(rig: Array, spec: VehicleSpec, input: VehicleInput, ground_speed := 18.0) -> void:
	var drive: WheelDrive = rig[1]
	var terrains: Array[Node] = []
	# Latches the driven count the tick's torque split reads, as `BaseVehicle` calls it first.
	drive.drive_omega(spec.ground_drive, input)
	drive.tick(rig[0], spec, input, 0.0, 0.0, ground_speed, TICK, terrains)


static func _commanded(w: RayWheel) -> float:
	return w.brake_spin / w.spin_compliance


func test_a_hot_service_brake_commands_its_fade_of_the_cold_torque() -> void:
	var spec := _bench_spec()
	var rig: Array = await _rig(spec)
	var drive: WheelDrive = rig[1]
	for w in drive.wheels:
		if not w.is_rear:
			w.brake_temp = HOT
	var input := VehicleInput.new()
	input.brake = 1.0
	_tick(rig, spec, input)
	var cold := spec.ground_drive.brake_torque
	for w in drive.wheels:
		assert_float(_commanded(w)).is_equal_approx(cold * (1.0 if w.is_rear else 0.5), 1e-6)


func test_a_hot_parking_brake_commands_its_whole_torque() -> void:
	var spec := _bench_spec()
	var rig: Array = await _rig(spec)
	var drive: WheelDrive = rig[1]
	for w in drive.wheels:
		w.brake_temp = HOT
	var input := VehicleInput.new()
	input.handbrake = 1.0
	_tick(rig, spec, input)
	for w in drive.wheels:
		if w.is_rear:
			assert_float(_commanded(w)).is_equal_approx(spec.ground_drive.handbrake_torque, 1e-6)
			# It heats the drum all the same.
			assert_float(w.brake_temp).is_greater(HOT)


func test_the_retarder_alone_heats_nothing() -> void:
	var spec := _bench_spec()
	spec.ground_drive.retarder_equipped = true
	spec.ground_drive.retarder_rating_nm = 600.0
	var rig: Array = await _rig(spec)
	var drive: WheelDrive = rig[1]
	var input := VehicleInput.new()
	input.retarder = 1.0
	_tick(rig, spec, input)
	assert_float(drive.retarder_torque_applied).is_greater(0.0)
	for w in drive.wheels:
		assert_float(w.brake_temp).is_equal(AMB)


func test_beside_the_retarder_only_the_foot_brakes_share_heats() -> void:
	var spec := _bench_spec()
	spec.ground_drive.retarder_equipped = true
	spec.ground_drive.retarder_rating_nm = 600.0
	var rig: Array = await _rig(spec)
	var drive: WheelDrive = rig[1]
	var input := VehicleInput.new()
	input.brake = 0.5
	input.retarder = 1.0
	_tick(rig, spec, input)
	# Each driven rear takes half the retarder; the fronts carry none.
	var ret := drive.retarder_torque_applied / 2.0
	assert_float(ret).is_greater(0.0)
	for w in drive.wheels:
		var share := 1.0 - (ret if w.is_rear else 0.0) / _commanded(w)
		assert_float((w.brake_temp - AMB) * C) \
				.is_equal_approx(w.brake_reacted * share * w.brake_settled_spin * TICK, 1e-6)


func test_a_respawned_drive_has_every_brake_at_ambient() -> void:
	var spec := _bench_spec()
	var rig: Array = await _rig(spec)
	var drive: WheelDrive = rig[1]
	for w in drive.wheels:
		w.brake_temp = HOT
	drive.respawn()
	for w in drive.wheels:
		assert_float(w.brake_temp).is_equal(AMB)


# --- a towed body ------------------------------------------------------------------

## The shipped box trailer, frozen high above an empty world, every wheel spinning at 50 rad/s.
func _trailer() -> TowedBody:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var trailer := (load("res://src/vehicles/truck/trailers/box.tscn") as PackedScene) \
			.instantiate() as TowedBody
	root.add_child(trailer)
	trailer.freeze = true
	trailer.global_position = Vector3(0.0, 100.0, 0.0)
	await get_tree().physics_frame
	for w in trailer.wheels:
		w.omega = 50.0
	return trailer


func test_a_towed_bodys_service_brake_fades_and_its_parking_brake_does_not() -> void:
	var trailer: TowedBody = await _trailer()
	var gd := trailer.spec.ground_drive
	var terrains: Array[Node] = []
	trailer.wheels[0].brake_temp = HOT
	trailer.tick_towed(1.0, 0.0, TICK, terrains)
	var applied := trailer.brake_applied()
	assert_float(applied).is_greater(0.0)
	assert_float(_commanded(trailer.wheels[0])).is_equal_approx(applied * gd.brake_torque * 0.5, 1e-6)
	assert_float(_commanded(trailer.wheels[1])).is_equal_approx(applied * gd.brake_torque, 1e-6)
	assert_float(trailer.wheels[1].brake_temp).is_greater(AMB)
	# The parking brake on a hot wheel: its whole torque.
	var parked: TowedBody = await _trailer()
	parked.wheels[0].brake_temp = HOT
	parked.tick_towed(0.0, 1.0, TICK, terrains)
	assert_float(_commanded(parked.wheels[0])).is_equal_approx(gd.handbrake_torque, 1e-6)


func test_a_re_laid_towed_body_has_every_brake_at_ambient() -> void:
	var trailer: TowedBody = await _trailer()
	for w in trailer.wheels:
		w.brake_temp = HOT
	trailer.reset_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 100.0, 0.0)))
	for w in trailer.wheels:
		assert_float(w.brake_temp).is_equal(AMB)


# --- the hand-built bodies' figures -----------------------------------------------

## `docs/sources.md` § Brake heat's rows, [C, G0, G1, ε, A_r, curve]: the hand-built specs carry
## them verbatim on both axles (the generated bodies: `test_kenney_variants`).
const AIR_DISC := [18000.0, 2.22, 0.55, 0.82, 0.277, BrakeThermal.FadeCurve.PAD]
const FARM_DRUM := [24800.0, 8.44, 0.39, 0.0, 0.0, BrakeThermal.FadeCurve.DRUM]
const HAND_BUILT := {
	"res://src/vehicles/truck/semi.tscn": AIR_DISC,
	"res://src/vehicles/truck/conventional.tscn": AIR_DISC,
	"res://src/vehicles/truck/trailers/box.tscn": AIR_DISC,
	"res://src/vehicles/truck/trailers/flatbed.tscn": AIR_DISC,
	"res://src/vehicles/truck/trailers/tanker.tscn": AIR_DISC,
	"res://src/vehicles/truck/trailers/tipper.tscn": AIR_DISC,
	"res://src/vehicles/tractor/trailers/farm_tipper.tscn": FARM_DRUM,
}


func test_every_hand_built_body_carries_its_classs_brake_heat() -> void:
	const FIELDS := ["brake_heat_capacity", "brake_cooling_g0", "brake_cooling_g1",
			"brake_emissivity", "brake_radiating_area", "brake_fade_curve"]
	for path: String in HAND_BUILT:
		# Read through the scene, as it ships: an orphaned spec would pass by path.
		var node: Node = (load(path) as PackedScene).instantiate()
		var gd: GroundDriveSpec = (node.get("spec") as VehicleSpec).ground_drive
		node.free()
		var row: Array = HAND_BUILT[path]
		for k in FIELDS.size():
			for suffix in ["", "_rear"]:
				var field: String = FIELDS[k] + suffix
				assert_float(float(gd.get(field))) \
						.override_failure_message("%s %s" % [path, field]) \
						.is_equal(float(row[k]))


# --- the published reading (contract 'brake_temp') -----------------------------------

## A shipped body of `family` standing in the tree, the ticks not run: telemetry is filled by hand.
func _spawn(family: String) -> BaseVehicle:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var vehicle := (load(VehicleCatalog.scene_of(VehicleCatalog.first_in_family(family))) \
			as PackedScene).instantiate() as BaseVehicle
	root.add_child(vehicle)
	await get_tree().physics_frame
	return vehicle


func test_the_published_brake_temp_is_the_hottest_wheels() -> void:
	for family in ["car", "truck", "tractor"]:
		var v: BaseVehicle = await _spawn(family)
		var wheels := v.drive.wheels
		assert_float(v.telemetry.brake_temp).is_equal(AMB)
		for i in wheels.size():
			wheels[i].brake_temp = 100.0 + 10.0 * i
		wheels[wheels.size() - 2].brake_temp = 400.0
		v._update_telemetry(VehicleInput.new(), TICK)
		assert_float(v.telemetry.brake_temp) \
				.override_failure_message("%s: brake_temp is not the hottest wheel" % family) \
				.is_equal(400.0)
		# The wire key is the contract's name.
		assert_float(v.telemetry.to_bridge_dict()["brake_temp"]).is_equal(400.0)
