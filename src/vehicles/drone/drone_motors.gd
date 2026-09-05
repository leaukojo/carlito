class_name DroneMotors
extends RefCounted
## The four rotors: visuals, positions, torque arms read from scene, spooled speeds, temps.
## This RefCounted is owned by DroneVehicle. DroneProp holds the propulsion chain; this holds
## the state that makes that chain pure static. Tuning knobs arrive as arguments, not copied to
## a second home (which breaks sync). A moved rotor inverts a control axis; test_drone.gd's
## test_motors_table_matches_the_scene_geometry is the CI gate. The gate lands after the mix,
## uncompensated; zeroing the command rather than speed lets the prop spool down and make
## decaying lift. ESC telemetry is written element-wise, skipping offline nodes to hold values.

var _rotors: Array[Node3D] = []             ## blade visuals, MOTORS (esc_index) order
var _offsets := PackedVector3Array()        ## body-local positions, same order
var _omega := PackedFloat32Array()          ## normalized motor speed [0, 1], same order
var _esc_temp := PackedFloat32Array()       ## per-ESC temperature (degC), same order

## Mean |x|/|z| levers of the four rotors (m), roll/pitch torque arms, MEASURED off the scene
## in `_init`. Defaults are what `drone.tscn` ships, for a craft whose rotors failed to bind.
var arm_x := 0.407
var arm_z := 0.407

## Over-temperature fault threshold, read from the contract rather than typed twice — must
## match the dashboard's `esc_temp` highlight. INF until read, so a contract without the signal
## never faults.
var _temp_warn := INF


## Cache the four rotors in esc_index order and measure the torque arms off the scene. A geometry
## mismatch only pushes an error and flies on; a missing rotor bails, since there is nothing to
## fly with either way.
func _init(body: Node3D) -> void:
	_omega.resize(DroneProp.MOTORS.size())
	_omega.fill(0.0)
	_esc_temp.resize(DroneProp.MOTORS.size())
	_esc_temp.fill(DroneProp.ESC_AMBIENT)
	var temp_def: RefCounted = Contract.data.get_signal_def("esc_temp", "out")
	if temp_def != null and temp_def.has_warn():
		_temp_warn = temp_def.warn
	var sum_x := 0.0
	var sum_z := 0.0
	for i in DroneProp.MOTORS.size():
		var m: Dictionary = DroneProp.MOTORS[i]
		var rotor := body.get_node_or_null(NodePath(m["node"])) as Node3D
		if rotor == null:
			push_error("DroneMotors: rotor '%s' (esc_index %d) is missing from the scene." % [m["node"], i])
			_rotors.clear()
			return
		if signf(rotor.position.x) != float(m["roll"]) or signf(-rotor.position.z) != float(m["pitch"]):
			push_error("DroneMotors: rotor '%s' at %s disagrees with its MOTORS mix signs — the mixer would fly it backwards."
					% [m["node"], rotor.position])
		_rotors.append(rotor)
		_offsets.append(rotor.position)
		sum_x += absf(rotor.position.x)
		sum_z += absf(rotor.position.z)
	arm_x = sum_x / float(DroneProp.MOTORS.size())
	arm_z = sum_z / float(DroneProp.MOTORS.size())


## Mix, gate, spool, and apply each rotor's thrust at its own scene position — roll/pitch
## torque come from the arm geometry, yaw from the summed prop reaction; a clamped motor
## simply loses its share. Body origin is the centre of mass (`spec.center_of_mass` zero
## here), so a body-up force at (x, y, z) makes torque (-z*T, 0, x*T) — the rotor's authored
## position is the lever.
func apply(body: RigidBody3D, collective: float, roll: float, pitch: float, yaw: float,
		node_fail: int, max_thrust: float, spool_tau: float, torque_ratio: float,
		delta: float) -> void:
	var basis := body.global_transform.basis
	var up := basis.y
	var cmd := DroneBus.gate_commands(
			DroneProp.mix_quad_x(collective, roll, pitch, yaw), node_fail)
	var reaction := 0.0
	for i in _rotors.size():
		_omega[i] = DroneProp.spool_step(_omega[i], cmd[i], spool_tau, delta)
		var f := DroneProp.motor_thrust(_omega[i], max_thrust)
		reaction += float(DroneProp.MOTORS[i]["yaw"]) * torque_ratio * f
		body.apply_force(up * f, basis * _offsets[i])
	body.apply_torque(up * reaction)


## The ESC bus, read out of the motors (rule 3). `esc_rpm` is the four spooled speeds; current
## and temperature are labelled models on top (`drone_propulsion.gd`). `rotor_rpm` reads the
## published array, so a dropped ESC's stale rpm keeps counting toward it, what a listener
## seeing only the four messages would compute.
func publish(t: DroneTelemetry, node_fail: int, max_thrust: float, torque_ratio: float,
		delta: float) -> PackedFloat32Array:
	var rpms := DroneProp.esc_rpm(_omega, DroneProp.ROTOR_MAX_RPM)
	var amps := PackedFloat32Array()
	amps.resize(_omega.size())
	for i in _omega.size():
		amps[i] = DroneProp.esc_current_a(_omega[i], DroneProp.ROTOR_MAX_RPM, max_thrust,
				torque_ratio, DroneProp.ESC_PACK_VOLTS, DroneProp.ESC_ETA, DroneProp.ESC_I_NOLOAD)
		_esc_temp[i] = DroneProp.esc_temp_step(_esc_temp[i], amps[i], DroneProp.ESC_AMBIENT,
				DroneProp.ESC_TEMP_K, DroneProp.ESC_TEMP_TAU, delta)
	# ELEMENT-WISE, skipping an offline ESC so its entry HOLDS — see the header.
	for i in _omega.size():
		if i >= t.esc_rpm.size() or not DroneBus.esc_is_online(node_fail, i):
			continue
		t.esc_rpm[i] = rpms[i]
		t.esc_current[i] = amps[i]
		t.esc_temp[i] = _esc_temp[i]
	# esc_fault ORs an ESC over its warn with an ESC whose node is gone; the second is computed
	# since a silent node can't file its own fault.
	t.esc_fault = DroneProp.esc_fault_bits(_esc_temp, _temp_warn) | DroneBus.offline_esc_bits(node_fail)
	# Health is DERIVED (drone_bus.gd), never injected; presence is the mask's complement.
	t.node_health = DroneBus.health_all(node_fail, _esc_temp, _temp_warn)
	t.node_online = DroneBus.online_bits(node_fail)
	t.rotor_rpm = DroneProp.rotor_rpm(PackedInt32Array(t.esc_rpm))
	return amps


## Are the props still turning? Rotor-borne effects gate on THIS, not `armed` — `armed` flips
## in one tick, the props spool down over ~5*tau.
func turning() -> bool:
	return DroneProp.mean_omega(_omega) > 0.0


## Cosmetic only: spin each blade at ITS OWN motor speed (called from `_process`, physics
## untouched). Direction is the same `MOTORS["spin"]` the reaction torque uses; rate is
## `_omega * ROTOR_MAX_RPM`, the same mapping `rotor_rpm` averages — no second rpm curve.
func spin_visuals(delta: float) -> void:
	if _rotors.size() != DroneProp.MOTORS.size():
		return
	for i in DroneProp.MOTORS.size():
		var step := float(DroneProp.MOTORS[i]["spin"]) * _omega[i] * DroneProp.ROTOR_MAX_RPM \
				* DroneVehicle.ROTOR_VISUAL_SPIN * delta
		_rotors[i].rotate_y(step)


## A teleport must not carry spun-up motors across — the accel-history reset's discipline.
## The HELD telemetry on `DroneTelemetry` is cleared by the vehicle, since those arrays are
## the bus's store, not this object's state.
func reset() -> void:
	_omega.fill(0.0)
	_esc_temp.fill(DroneProp.ESC_AMBIENT)
