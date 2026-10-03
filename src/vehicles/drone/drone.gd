class_name DroneVehicle
extends BaseVehicle
## Quadcopter drone. Each subsystem's laws live in a pure-fn sibling; this holds the cross-tick
## state and the tick order. Tick order and rules: `src/vehicles/drone/CLAUDE.md`; tour:
## `docs/vehicles.md` § Drone subsystems.


## Blade rad/s per rotor rpm: cosmetic, far below the real rev rate (which would alias to a
## shimmer at 60 fps); `rotor_rpm` stays the honest published number.
const ROTOR_VISUAL_SPIN := 0.005


@export_group("Lift")
## N total rotor thrust cap. Also the motor scale: each of the four caps at max_thrust/4.
@export var max_thrust := 150.0
@export var climb_force := 45.0      ## N added/removed at full climb stick (< m*g, full-down still descends gently)
@export var vertical_drag := 6.5     ## N per m/s of vertical speed (terminal climb/descent rate)

@export_group("Motors")
## Motor/prop spool time constant (s): first-order lag toward the commanded speed. 0.05 s is a
## real ESC-and-prop figure.
@export var motor_spool_tau := 0.05
## Prop reaction torque per newton of thrust (m), ~0.02*D for a hobby prop (0.44 m here).
## The ONLY source of yaw authority (~1 N*m); never inflate it for yaw snap (rule 3).
@export var prop_torque_ratio := 0.02

@export_group("Attitude")
@export var max_tilt_deg := 32.0             ## forward/back lean at full throttle
@export var attitude_stiffness := 14.0       ## N*m per unit leveling error (~sin of the attitude error)
@export var attitude_damping := 3.0          ## N*m per rad/s of off-axis (non-yaw) angular velocity
## N*m cap on the leveling torque demand: the mixer's real roll authority at hover,
## arm_x * max_thrust * (m*g/max_thrust) = 0.407 * 150 * 0.327 = 20 N*m. Moving a rotor in
## drone.tscn rescales it (`tests/test_drone.gd` pins it).
@export var max_attitude_torque := 20.0
## rad/s at full steer, sized to what the props can actually make.
@export var max_yaw_rate := 1.0
@export var yaw_gain := 2.0                  ## N*m per rad/s of yaw-rate error (sized with max_yaw_rate)
## N*m cap on the yaw torque demand: prop ceiling at hover (prop_torque_ratio * max_thrust * 0.327 =
## 0.98 N*m) rounded up. A demand past it zeroes the falling motor pair and climbs.
@export var max_yaw_torque := 1.0

@export_group("Translation")
## N per m/s of horizontal speed (air resistance). Absorbs this craft's share of the removed
## `physics/3d/default_linear_damp` (mass * 0.1). Opposes velocity relative to the AIR; in still
## air that is velocity itself (`tests/test_wind.gd`).
@export var horizontal_drag := 1.0

## Body footprint (m); only used to derive the moment of inertia the torque clamps need.
@export var body_extents := Vector3(1.1, 0.2, 1.1)

var _inertia := 0.6   ## representative moment (kg*m^2) for the one-tick torque clamps

## The four motors (`drone_motors.gd`; chain is pure statics in `drone_propulsion.gd`). Built in _ready.
var _motors: DroneMotors
## The pack's remembered values (coulomb accumulator, temperature); laws in `drone_pack.gd`.
var _pack := DronePack.new()
## Sky mask, rangefinder, roster indices (`drone_sensor_suite.gd`). Built in _ready (needs body RID).
var _sensors: DroneSensorSuite
## A DECISION, so it lives here and runs at the tick's bottom (it needs this tick's collective).
var _landed_hold := 0.0           ## s the landing conditions have held continuously
## Resolved once from DroneBus.NODES; the arming snapshot reads it.
var _ahrs_node := -1
## Resolved once from DroneBus.NODES; gates the pack telemetry hold below.
var _power_node := -1
## The last drone-published `battery`. BaseVehicle's alternator write touches `telemetry.battery`
## every tick regardless of the POWER node, so the field cannot be its own hold.
var _held_battery := 0.0
## Hover collective, m*g/max_thrust: the landing predicate's ceiling (via `lift_thrust`).
var _hover_collective := 0.0
## Largest collective an autonomous mode may ask for (full-climb). Shipped airframe:
## (5*9.8 + 45) / 150 = 0.627.
var _auto_collective_max := 0.0
## Hardpoint marker, crate, latch (`drone_hook.gd`). Built in _ready.
var _hook: DroneHook
## The airframe's own mass/COM: `mass`/`center_of_mass` are overwritten while a payload is on the hook.
var _base_mass := 1.0
var _base_com := Vector3.ZERO
## HoodCam marker, chasing angles, contract-read stops (`drone_gimbal_mount.gd`). Built in _ready.
var _gimbal: DroneGimbalMount
## Status LEDs and the rangefinder beam (`drone_indicators.gd`). Built in _ready.
var _indicators: DroneIndicators
## Elapsed seconds against which sea-level pressure drifts. NOT cleared by respawn: the drift is
## the level's weather.
var _air_time := 0.0
var _mode_actual: int = DroneModes.STABILIZE  ## contract 'mode_actual': what the FC is really in
var _mode_request: int = DroneModes.STABILIZE ## last seen `flight_mode`, for the change EDGE
var _alt_target := 0.0            ## world Y the altitude cascade holds
var _alt_integ := 0.0             ## the drone's ONE integrator (climb-rate trim)
var _loiter_pos := Vector3.ZERO   ## the point the position controller holds
## Debounced position fix: published sats/fix_type/hdop stay raw; the mode reads this so a
## flickering receiver cannot toggle LOITER at the tick rate. Starts false.
var _pos_fix := false
var _fix_hold := 0.0
## Position at which the craft armed; tracks the craft while disarmed, so `home_dist` reads 0 on
## the ground and the fence cannot breach before takeoff.
var _home := Vector3.ZERO
## The two auto latches. Released by the pilot's mode change, disarm and respawn, never by
## `_reset_controllers` (it runs on the mode change they cause).
var _fence_rtl := false     ## a geofence breach has commanded RTL
## Pilot cancelled a fence RTL while still outside; suppresses re-latch until back inside
## (DroneModes.fence_answered).
var _fence_answered := false
var _rtl_landing := false   ## RTL has reached its landing leg (so mode_actual reads LAND)
## Last tick's landed predicate: LAND cuts the motors one tick late.
var _landed := false
var _armed_prev := false  ## last tick's arm gate, for the takeoff edge
## `_armed` is LATCHED, not recomputed, which is what makes a refusal possible. `_arm_prev` is the
## previous REQUEST (arming is a rising edge, disarming a level).
var _armed := false
var _arm_prev := false
var _disarm_hold := 0.0   ## s the craft has been armed AND landed, continuously
var _failsafe: int = DroneArming.FS_NONE  ## contract 'failsafe', the most severe active condition
var _prearm_fail := 0                 ## contract 'prearm_fail' bits, live (0 published in flight)


## Visuals only: the blades are the telemetry, drawn.
func _process(delta: float) -> void:
	if _motors != null:
		_motors.spin_visuals(delta)


## W and S tilt the nose forward and back (`input.throttle`): one stick, so one ramp.
func key_pedals_are_a_stick() -> bool:
	return true


func _make_telemetry() -> VehicleTelemetry:
	return DroneTelemetry.new()


func _ready() -> void:
	super._ready()
	# Omits WorldBounds: an unannounced stop in mid-air reads as a bug. The geofence
	# (`drone_modes.gd`) is the soft boundary.
	collision_mask = Layers.SOLID
	_base_mass = spec.mass
	_base_com = spec.center_of_mass
	_hook = DroneHook.new(self)
	_gimbal = DroneGimbalMount.new(self)
	_sensors = DroneSensorSuite.new(self)
	_motors = DroneMotors.new(self)
	_indicators = DroneIndicators.new(self)
	_ahrs_node = DroneBus.index_of("AHRS")
	_power_node = DroneBus.index_of("POWER")
	_apply_carried_mass()
	_home = global_position
	_alt_target = global_position.y
	_loiter_pos = global_position


## A carried crate is a child of the Hardpoint marker, so a vehicle swap would free it too
## (`Level._spawn_vehicle`). Hands it back to the level before teardown.
func release_level_items() -> void:
	if _hook != null:
		_hook.reset(self)


## Writes the current mass/COM onto the body and re-derives inertia and both collectives from
## them: this is where a payload is FELT. Called at _ready and on every hook change, never per tick.
func _apply_carried_mass() -> void:
	var carried := DronePayload.carried_mass(_base_mass, _hook.payload_mass())
	mass = carried
	center_of_mass = DronePayload.carried_com(
			_base_com, _hook.hook_local(), _base_mass, _hook.payload_mass())
	# Box-footprint inertia, m (w^2 + d^2) / 12: the clamp basis for the torque dampers.
	_inertia = VehicleMath.inertia_of(carried, body_extents.x, body_extents.z)
	_hover_collective = clampf(
			lift_thrust(carried, _gravity, 0.0, climb_force, max_thrust)
			/ maxf(max_thrust, 1e-6), 0.0, 1.0)
	# Full climb stick: the ceiling every autonomous mode is clamped to.
	_auto_collective_max = clampf(
			lift_thrust(carried, _gravity, 1.0, climb_force, max_thrust)
			/ maxf(max_thrust, 1e-6), 0.0, 1.0)


## Overrides `respawn()` (not the reset seam) because the crate must drop BEFORE the body
## teleports: it is a child of the Hardpoint marker and would read its global transform at the
## new spawn pose, delivering cargo by respawning.
func respawn() -> void:
	_hook.reset(self)
	super.respawn()


## The pack is replaced, not just cooled: an empty pack stops the motors, so a surviving flat pack
## would leave the craft unflyable. The `node_fail` a BRIDGE is sending survives (it is an input).
func reset_session_state() -> void:
	super.reset_session_state()
	_motors.reset()
	_apply_carried_mass()
	_gimbal.reset()
	_pack.reset()
	# Clears the sky mask (the receiver reacquires over four ticks); zeroing the debounce means
	# proving grounded again.
	_sensors.reset()
	_landed_hold = 0.0
	# `_mode_request` is NOT reset: a respawn in LOITER re-enters LOITER, anchored here.
	_home = global_position
	_fence_rtl = false
	_fence_answered = false
	_rtl_landing = false
	_landed = false
	_mode_actual = DroneModes.STABILIZE
	# Comes back DISARMED. `_arm_prev` goes false, not to the live request, ON PURPOSE: the
	# craft re-arms next tick if the switch is up and checks pass, a way OUT of a stuck aircraft.
	_armed = false
	_arm_prev = false
	# Else the disarmed->armed edge reads stale-true and the first arm skips `_reset_controllers()`.
	_armed_prev = false
	_disarm_hold = 0.0
	_failsafe = DroneArming.FS_NONE
	_prearm_fail = 0
	_pos_fix = false
	_fix_hold = 0.0
	_reset_controllers()
	# The base reseeds `battery` to a car's 12.6 V; a drone flies on ~25 V, so both it and
	# `_held_battery` (what an offline POWER node publishes) take the fresh pack's open-circuit voltage.
	var t := telemetry as DroneTelemetry
	if t != null:
		t.battery = _pack.volts(0.0)
		_held_battery = t.battery


## Re-seats every controller on the craft's CURRENT state: on a mode change, the disarmed -> armed
## edge and respawn. Leaves `_fence_rtl`/`_rtl_landing` alone (they cause mode changes).
##
## `keep_trim` carries the climb-rate integrator across a change between two cascade modes
## (`DroneModes.uses_cascade`); arming and respawn always dump it.
func _reset_controllers(keep_trim := false) -> void:
	if not keep_trim:
		_alt_integ = 0.0
	_alt_target = global_position.y
	_loiter_pos = global_position


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as DroneTelemetry
	var body_basis := global_transform.basis
	var up := body_basis.y
	# Attitude/height telemetry is the base's, written before _tick_extras runs. Tick order:
	# `src/vehicles/drone/CLAUDE.md`.

	# fix_type refuses a LOITER, so the sensors measure first (resolving on last tick's fix would
	# fly on a stale reading). Sky fan + rangefinder: five rays a tick (DroneSensors.SKY_RAYS_PER_TICK).
	var space := get_world_3d().direct_space_state
	_sensors.measure(space, global_position)
	# The node gates fail in OPPOSITE directions on purpose: offline GNSS publishes an empty sky,
	# offline rangefinder publishes INVALID, never 0 (`drone_sensor_suite.gd`).
	_sensors.publish(t, input.node_fail)

	# Once per tick: the barometer's static port and both dampers use the same wind.
	var wind := WindField.at(self)

	# The barometer exists to disagree with the two heights just published (`drone_air_data.gd`).
	# Ungated by the bus roster: no barometer node.
	_air_time += delta
	var airspeed := (linear_velocity - wind).length()
	t.static_press = DroneAirData.pressure_at(
			global_position.y, DroneAirData.sea_level_pressure(_air_time)) \
			+ DroneAirData.port_error_pa(airspeed)
	t.baro_alt = DroneAirData.altitude_from(t.static_press, DroneAirData.QNH_STANDARD)
	t.oat = DroneAirData.oat_c(global_position.y)

	# Above arming: a payload changes the mass the pre-arm check and every controller are sized
	# against. `tick` returns "latch changed"; the mass write stays here.
	if _hook.tick(input.hardpoint_cmd, space, self):
		_apply_carried_mass()
	t.hardpoint_state = _hook.latched
	t.payload_weight = DronePayload.payload_weight_n(_hook.payload_mass(), _gravity)

	# Modes and failsafes decide on the DEBOUNCED fix, never the raw one just published; stepped
	# above arming because the pre-arm GPS check reads the same held predicate.
	var raw_fix := DroneModes.has_pos_fix(t.fix_type)
	_fix_hold = DroneModes.fix_hold_step(_fix_hold, raw_fix, _pos_fix, delta)
	_pos_fix = DroneModes.held_fix_ok(raw_fix, _pos_fix, _fix_hold)

	# --- arming, pre-arm checks and failsafes (`drone_arming.gd`) ---
	# SOC is last tick's accumulator (integrated below).
	var power_ok := input.key == InputRouter.KEY_IGNITION and _pack.has_charge()
	# mode_want is the request after the fence latch, before failsafe forcing: reading the resolved
	# mode would let a forced failsafe decide on itself.
	var snap := DroneArming.Snapshot.new()
	snap.pitch = t.pitch
	snap.roll = t.roll
	snap.soc = _pack.soc
	snap.node_fail = input.node_fail
	snap.ahrs_node = _ahrs_node
	snap.climb = input.climb
	snap.pos_fix = _pos_fix
	snap.mode_want = DroneModes.wanted_mode(input.flight_mode, _fence_rtl)
	snap.fence_rtl = _fence_rtl
	_failsafe = DroneArming.failsafe_of(snap)
	snap.failsafe = _failsafe
	_prearm_fail = DroneArming.prearm_fail(snap)
	# Auto-disarm reads LAST tick's landed predicate (it needs a collective this tick has not made).
	_disarm_hold = DroneArming.disarm_hold_step(_disarm_hold, _armed, _landed, delta)
	_armed = DroneArming.arm_step(_armed, input.arm, _arm_prev, power_ok, _prearm_fail, _landed,
			DroneArming.auto_disarm_due(_disarm_hold))
	_arm_prev = input.arm
	var armed := _armed
	# Taking off is a fresh flight: no accumulated trim, both hold targets on the aircraft.
	if armed and not _armed_prev:
		_reset_controllers()
	_armed_prev = armed

	# Horizontal drag always acts. The VERTICAL damper is rotor-borne, so it gates on the motors
	# TURNING, not `armed`: a disarm spools down over ~5*tau, still making lift. Both oppose
	# velocity relative to the AIR (VehicleMath.air_damper), one-tick clamped (the 60 Hz tick:
	# `src/vehicles/CLAUDE.md`); the axis masks keep the two coefficients separate.
	apply_central_force(VehicleMath.air_damper(linear_velocity, wind, horizontal_drag,
			mass, delta, Vector3(1.0, 0.0, 1.0)))
	if armed or _motors.turning():
		apply_central_force(VehicleMath.air_damper(linear_velocity, wind, vertical_drag,
				mass, delta, Vector3(0.0, 1.0, 0.0)))

	# --- flight modes (`drone_modes.gd`) ---
	# Home tracks the craft while disarmed (see `_home`).
	if not armed:
		_home = global_position
	var home_dist := DroneModes.home_distance(global_position, _home)

	# A CHANGE of the pilot's requested mode releases the two auto latches. A failsafe is not
	# released here: it clears with its cause (Y restores the ESC, respawn gives a fresh pack).
	if input.flight_mode != _mode_request:
		_mode_request = input.flight_mode
		# OR, not assign: a second mode change while still outside must not spend an already-held
		# cancel (`_fence_rtl` is false by then; assigning would re-arm the fence a change early).
		_fence_answered = _fence_answered or _fence_rtl
		_fence_rtl = false
		_rtl_landing = false
	# Soft: commands a return, does not stop the aircraft. Release and latch run on the same tick,
	# so `fence_answered` is what keeps the breach from re-commanding RTL at once.
	_fence_answered = DroneModes.fence_answered(_fence_answered, armed, global_position, _home,
			DroneModes.GEOFENCE_RADIUS, DroneModes.GEOFENCE_CEILING)
	_fence_rtl = not _fence_answered and DroneModes.fence_latch(_fence_rtl, armed,
			global_position, _home, DroneModes.GEOFENCE_RADIUS, DroneModes.GEOFENCE_CEILING)
	var rtl_phase := DroneModes.rtl_phase_of(global_position, _home,
			DroneModes.RTL_ALT, DroneModes.RTL_ARRIVE_M)
	# Resolve, latch on the result, resolve again: the landing leg may only latch off a mode
	# actually being flown, and `resolve_mode` stays the one decision site (it is pure).
	# A failsafe enters as `forced` (BATT_LOW commands RTL, BATT_CRIT or an offline ESC LAND), over
	# pilot and fence via DroneModes.auto_rank.
	var forced := DroneArming.failsafe_mode(_failsafe)
	var mode := DroneModes.resolve_mode(input.flight_mode, _pos_fix, _fence_rtl, armed,
			_rtl_landing, forced)
	_rtl_landing = DroneModes.rtl_landing_latch(_rtl_landing, armed, mode, rtl_phase)
	mode = DroneModes.resolve_mode(input.flight_mode, _pos_fix, _fence_rtl, armed, _rtl_landing,
			forced)
	if mode != _mode_actual:
		# Climb-rate trim survives a change BETWEEN cascade modes and nothing else.
		var keep_trim := DroneModes.uses_cascade(mode) and DroneModes.uses_cascade(_mode_actual)
		_mode_actual = mode
		_reset_controllers(keep_trim)

	# Demands are in the mixer's thrust-fraction units, not forces/torques. Disarmed they stay zero.
	var collective := 0.0
	var roll_demand := 0.0
	var pitch_demand := 0.0
	var yaw_demand := 0.0
	# LAND's touchdown cut zeroes ALL FOUR demands (below).
	var motors_cut := false
	if armed:
		var stick_climb := clampf(input.climb, -1.0, 1.0)
		var stick_throttle := clampf(input.throttle, -1.0, 1.0)
		var max_tilt_rad := deg_to_rad(max_tilt_deg)
		# Manual tilt, the default in every mode that does not overwrite it. Negated so W leans
		# the nose FORWARD.
		var tilt := Vector2(-stick_throttle * max_tilt_rad, 0.0)
		if _mode_actual == DroneModes.STABILIZE:
			# Hover feedforward plus climb trim. The climb axis is a thrust TRIM here, a climb
			# RATE in every other mode.
			collective = clampf(lift_thrust(mass, _gravity, stick_climb,
					climb_force, max_thrust) / maxf(max_thrust, 1e-6), 0.0, 1.0)
		else:
			# One cascade for every non-STABILIZE mode; only the targets and stick use differ.
			var rate_cmd := 0.0
			var hold_pos := false
			match _mode_actual:
				DroneModes.ALT_HOLD:
					if absf(stick_climb) > DroneModes.STICK_DEADBAND:
						rate_cmd = stick_climb * DroneModes.ALT_RATE_MAX
				DroneModes.LOITER:
					if absf(stick_climb) > DroneModes.STICK_DEADBAND:
						rate_cmd = stick_climb * DroneModes.ALT_RATE_MAX
					# Stick out of deadband: the anchor follows the craft; release holds there.
					if absf(stick_throttle) > DroneModes.STICK_DEADBAND:
						_loiter_pos = global_position
					else:
						hold_pos = true
				DroneModes.RTL:
					# Sticks ignored except yaw (no real FC takes the yaw stick away).
					var target := DroneModes.rtl_target(_home, global_position, rtl_phase,
							DroneModes.RTL_ALT)
					_alt_target = target.y
					_loiter_pos = target
					hold_pos = true
				DroneModes.LAND:
					rate_cmd = -DroneModes.LAND_RATE
					# The mode change re-anchored `_loiter_pos` on the craft: right for a pilot LAND,
					# wrong for an RTL's last leg, which keeps holding home.
					if _rtl_landing:
						_loiter_pos = DroneModes.rtl_target(_home, global_position,
								DroneModes.RTL_LAND, DroneModes.RTL_ALT)
					# Position-held with a fix, free-drifting without; `failsafe` carries GPS_LOST.
					hold_pos = _pos_fix
					motors_cut = _landed
			# While a rate is commanded the altitude target rides the craft (pure feedforward);
			# RTL sets its own target above.
			if _mode_actual != DroneModes.RTL and not is_zero_approx(rate_cmd):
				_alt_target = global_position.y
			var rate_target := DroneModes.alt_rate_target(_alt_target - global_position.y, rate_cmd)
			var rate_err := rate_target - linear_velocity.y
			_alt_integ = DroneModes.alt_integ_step(_alt_integ, rate_err, delta)
			collective = DroneModes.alt_hold_collective(_hover_collective, rate_err, _alt_integ,
					_auto_collective_max)
			if hold_pos:
				# Error and ground velocity in the HEADING FRAME, the same `heading_frame` that
				# `level_target_up` uses.
				var frame := heading_frame(body_basis)
				var err := _loiter_pos - global_position
				tilt = DroneModes.position_tilt_demand(
						Vector2(err.dot(-frame.z), err.dot(frame.x)),
						Vector2(linear_velocity.dot(-frame.z), linear_velocity.dot(frame.x)),
						max_tilt_rad)

		# Attitude: every mode reaches the airframe through this ONE path, limited by
		# max_attitude_torque, so autonomy cannot out-torque a stick. The damper opposes only
		# off-axis angular velocity so it never fights yaw.
		var target_up := level_target_up(body_basis, tilt)
		var perp := angular_velocity - up * angular_velocity.dot(up)
		var att := (align_torque(up, target_up, attitude_stiffness)
				+ VehicleMath.clamped_damper(perp, attitude_damping, _inertia, delta)).limit_length(max_attitude_torque)
		# Only the two axes the mixer can produce; `att` has no body-Y component to drop.
		roll_demand = DroneProp.torque_to_demand(att.dot(body_basis.z), _motors.arm_x, max_thrust)
		pitch_demand = DroneProp.torque_to_demand(att.dot(body_basis.x), _motors.arm_z, max_thrust)

		# Yaw rate toward the commanded rate about body up; manual in every mode. steer negative =
		# left but +Y torque yaws left, so the sign flips (the boat's rudder convention).
		var yaw_t := VehicleMath.yaw_torque(-_steer * max_yaw_rate, angular_velocity.dot(up),
				yaw_gain, _inertia, delta, max_yaw_torque)
		yaw_demand = DroneProp.torque_to_demand(yaw_t, prop_torque_ratio, max_thrust)

		if motors_cut:
			# Zeroing only the collective is not a cut: mix_quad_x clamps per motor, so an attitude
			# demand still drives two motors positive (a craft on a slope fights the terrain,
			# ~25 N against 49 N of weight).
			collective = 0.0
			roll_demand = 0.0
			pitch_demand = 0.0
			yaw_demand = 0.0
			# Anti-windup: against LAND's rate the integrator saturates within seconds and
			# `keep_trim` would hand it to the next ALT_HOLD.
			_alt_integ = 0.0

	# The node-failure gate lands AFTER the mix, uncompensated. Tuning knobs are passed in, not
	# copied onto `drone_motors.gd`.
	_motors.apply(self, collective, roll_demand, pitch_demand, yaw_demand, input.node_fail,
			max_thrust, motor_spool_tau, prop_torque_ratio, delta)

	# Published element-wise so an offline ESC holds its last reading; the four amps feed the pack.
	var amps := _motors.publish(t, input.node_fail, max_thrust, prop_torque_ratio, delta)
	# `armed` is the ESC gate bool. `prearm_fail` goes dark in flight (DroneArming.published_fail).
	t.armed = armed
	t.arming_state = DroneArming.state_of(armed, input.arm, power_ok, _prearm_fail)
	t.prearm_fail = DroneArming.published_fail(armed, _prearm_fail)
	t.failsafe = _failsafe

	# `battery` overwrites the base's alternator write (no alternator here). The INTERNAL pack
	# always integrates (arming's has_charge() reads it); only the PUBLISHED four hold while the
	# POWER node is off the bus.
	var pack_a := _pack.step(amps, delta)
	if DroneBus.is_online(input.node_fail, _power_node):
		t.pack_current = pack_a
		t.soc = _pack.soc
		t.pack_temp = _pack.temp
		t.battery = _pack.volts(pack_a)
		_held_battery = t.battery
	else:
		# The other three hold on their own (nothing else writes them); `battery` was overwritten
		# by the base's alternator earlier this tick.
		t.battery = _held_battery

	# `mode_actual` differing from the `flight_mode` request is the reading (LOITER -> ALT_HOLD on GNSS loss).
	t.mode_actual = _mode_actual
	t.home_dist = home_dist

	# The HoodCam marker is the whole FPV feed (ChaseCamera's HOOD view). Published as where the
	# gimbal HAS reached, not what was asked.
	_gimbal.tick(input.gimbal_pitch, input.gimbal_yaw, delta)
	t.gimbal_pitch_actual = _gimbal.pitch
	t.gimbal_yaw_actual = _gimbal.yaw

	# ST_GROUND reads the suite's OWN agl, not published `t.agl`, so an offline RANGE node does not
	# make the aircraft forget it is grounded. `collective` is the demand before the mixer or a
	# dead motor clamped it: a takeoff is what the pilot asked for.
	_landed_hold = DroneSensors.landed_hold(_landed_hold, DroneSensors.landed_now(
			_sensors.agl(), t.vspeed, collective,
			DroneSensors.LANDED_AGL, DroneSensors.LANDED_VSPEED,
			_hover_collective * DroneSensors.LANDED_COLLECTIVE_FRAC), delta)
	t.ground = _landed_hold >= DroneSensors.LANDED_DEBOUNCE
	t.status = VehicleTelemetry.with_status_bit(t.status, VehicleTelemetry.ST_GROUND, t.ground)
	# Read one tick late by LAND's cut and auto-disarm (it needs this tick's collective).
	_landed = t.ground

	# Last: the lights and beam show what this tick published.
	_indicators.tick(t, power_ok, self)


# --- airframe math (mixer/motors/ESC bus: `drone_propulsion.gd`) ---

## Total rotor thrust (N) along body up: hover feedforward plus climb. Clamped to [0, thrust_cap].
static func lift_thrust(body_mass: float, gravity: float, climb: float,
		climb_gain: float, thrust_cap: float) -> float:
	return clampf(body_mass * gravity + climb * climb_gain, 0.0, thrust_cap)


## The craft's heading frame: yaw only, level, right-handed. `basis.x` is heading-right, `basis.y`
## is world up, `-basis.z` is flat forward. Nose vertical falls back to the up-vector's heading,
## and to Basis.IDENTITY if that is vertical too.
static func heading_frame(body_basis: Basis) -> Basis:
	var fwd := -body_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 1e-3:
		flat = Vector3(body_basis.y.x, 0.0, body_basis.y.z)
	if flat.length() < 1e-3:
		return Basis.IDENTITY
	flat = flat.normalized()
	return Basis(flat.cross(Vector3.UP).normalized(), Vector3.UP, -flat)


## Target body-up direction: world up tilted by `tilt` rad. tilt.x is fore/aft lean (about the right
## axis), tilt.y is lateral lean (about forward). One rotation, so total lean is exactly
## `tilt.length()`: a diagonal cannot make 45 deg from two 32-degree axes.
static func level_target_up(body_basis: Basis, tilt: Vector2) -> Vector3:
	var frame := heading_frame(body_basis)
	var rot := frame.x * tilt.x + (-frame.z) * tilt.y
	var angle := rot.length()
	if angle < 1e-9:
		return Vector3.UP
	return Vector3.UP.rotated(rot / angle, angle)


## Corrective torque rotating `body_up` toward `target_up`: A x B, magnitude ~ sin(error) * stiffness.
static func align_torque(body_up: Vector3, target_up: Vector3, stiffness: float) -> Vector3:
	return body_up.cross(target_up) * stiffness
