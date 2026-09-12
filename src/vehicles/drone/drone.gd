class_name DroneVehicle
extends BaseVehicle
## Quadcopter drone. A BaseVehicle subclass owning flight locomotion, plugged into two base seams
## (_make_telemetry, _tick_extras). Each subsystem's laws live in a pure-fn sibling; this holds
## the cross-tick state and the tick order. See drone/CLAUDE.md. Tested in test_drone.gd.
##
## Tick order is load-bearing: cargo mass → sensors → arming → modes. Mass affects pre-arm and
## controllers; mode reads debounced fix, never raw. Rotor effects (rpm, spin, damper) gate on
## motors turning, not armed. Attitude has priority over throttle. Mixer clamps per motor with
## no rescaling. One-tick damper clamp (60 Hz locked). Armed is latched (enables refusal).
## Node_fail is bench switch (respawn does not clear). Where two readings disagree after node
## drop (rotor_rpm held vs pack_current live), that is the instrument.


## Blade rad/s per rotor rpm — a cosmetic ratio far below the real rev rate (which would
## alias to a shimmer at 60 fps); rotor_rpm stays the honest published number.
const ROTOR_VISUAL_SPIN := 0.005


@export_group("Lift")
## N total rotor thrust cap (hard cap). Also the motor scale: each of the four caps at
## max_thrust/4, so the sum is capped by geometry.
@export var max_thrust := 150.0
@export var climb_force := 45.0      ## N added/removed at full climb stick (< m*g, full-down still descends gently)
@export var vertical_drag := 6.5     ## N per m/s of vertical speed (terminal climb/descent rate)

@export_group("Motors")
## Motor/prop spool time constant (s): the command is a target speed and the motor is a
## first-order lag toward it. Lower is snappier; 0.05 s is a real ESC-and-prop figure.
@export var motor_spool_tau := 0.05
## Prop reaction torque per newton of thrust (m), ~0.02*D for a hobby prop (0.44 m here).
## The ONLY source of yaw authority. Do not inflate to buy snappier yaw — see header.
@export var prop_torque_ratio := 0.02

@export_group("Attitude")
@export var max_tilt_deg := 32.0             ## forward/back lean at full throttle
@export var attitude_stiffness := 14.0       ## N*m per unit leveling error (~sin of the attitude error)
@export var attitude_damping := 3.0          ## N*m per rad/s of off-axis (non-yaw) angular velocity
## N*m cap on the leveling torque demand — equals the mixer's real roll authority at hover.
@export var max_attitude_torque := 20.0
## rad/s at full steer, sized to what the props can actually make.
@export var max_yaw_rate := 1.0
@export var yaw_gain := 2.0                  ## N*m per rad/s of yaw-rate error (sized with max_yaw_rate)
## N*m cap on the yaw torque demand: prop ceiling at hover (0.98 N*m) rounded up. A demand
## past it drives the falling motor pair to zero and turns a hard yaw into a climb.
@export var max_yaw_torque := 1.0

@export_group("Translation")
## N per m/s of horizontal speed (air resistance). Absorbs this craft's share of the removed
## `physics/3d/default_linear_damp` (mass * 0.1) so total feel is unchanged. Opposes velocity
## relative to the AIR; in still air that's velocity itself (tests/test_wind.gd).
@export var horizontal_drag := 1.0

## Body footprint (m); only used to derive the moment of inertia the torque clamps need.
@export var body_extents := Vector3(1.1, 0.2, 1.1)

var _inertia := 0.6   ## representative moment (kg*m^2) for the one-tick torque clamps

## The four motors: visuals, positions, torque arms, spooled speeds, ESC temps
## (drone_motors.gd, chain is pure statics in drone_propulsion.gd). Built in _ready.
var _motors: DroneMotors
## Pack's remembered values (coulomb accumulator, temperature), laws in drone_pack.gd.
var _pack := DronePack.new()
## Sky pattern/mask, round-robin cursor, rangefinder, roster indices (drone_sensor_suite.gd,
## laws in drone_sensors.gd). Built in _ready (needs body RID).
var _sensors: DroneSensorSuite
## Landing debounce stays here, not on the suite — it's a DECISION, run at the tick's bottom
## since it needs this tick's collective demand.
var _landed_hold := 0.0           ## s the landing conditions have held continuously
## Resolved once from DroneBus.NODES. GNSS/RANGE moved onto the suite; AHRS stays here since
## the arming snapshot reads it.
var _ahrs_node := -1
## Hover collective, m*g/max_thrust — the landing predicate's ceiling. Via `lift_thrust` at
## _ready, the same call the flight path makes (no second formula).
var _hover_collective := 0.0
## Largest collective an autonomous mode may ask for (full-climb). Shipped airframe:
## (5*9.8 + 45) / 150 = 0.627.
var _auto_collective_max := 0.0
## Hardpoint marker, crate, latch (drone_hook.gd; laws in drone_payload.gd). Mass write is
## `_apply_carried_mass` here. Built in _ready.
var _hook: DroneHook
## Airframe's own mass/COM, since `mass`/`center_of_mass` are overwritten while a payload is
## on the hook. Latched from spec at _ready.
var _base_mass := 1.0
var _base_com := Vector3.ZERO
## HoodCam marker, chasing angles, contract-read stops (drone_gimbal_mount.gd, laws in
## drone_gimbal.gd). Built in _ready.
var _gimbal: DroneGimbalMount
## The airframe's own status LEDs and the rangefinder beam (drone_indicators.gd), ticked last on
## this tick's published state. Built in _ready.
var _indicators: DroneIndicators
## Barometer's only state: elapsed seconds against which sea-level pressure drifts. NOT
## cleared by respawn — the drift is the level's weather.
var _air_time := 0.0
## Flight modes' only state (laws are pure fns in drone_modes.gd).
var _mode_actual: int = DroneModes.STABILIZE  ## contract 'mode_actual': what the FC is really in
var _mode_request: int = DroneModes.STABILIZE ## last seen `flight_mode`, for the change EDGE
var _alt_target := 0.0            ## world Y the altitude cascade holds
var _alt_integ := 0.0             ## the drone's ONE integrator (climb-rate trim)
var _loiter_pos := Vector3.ZERO   ## the point the position controller holds
## Debounced position fix. Published sats/fix_type/hdop stay raw; the mode reads this so a
## flickering receiver can't toggle LOITER at the tick rate. Starts false.
var _pos_fix := false
var _fix_hold := 0.0
## Home = position at which the craft armed; tracks the craft while disarmed, so home_dist
## reads 0 on the ground and the fence can't breach before takeoff.
var _home := Vector3.ZERO
## The two auto latches. Cleared by the pilot changing mode, by disarming, and by respawn —
## never by `_reset_controllers`, which runs on the mode change they cause.
var _fence_rtl := false     ## a geofence breach has commanded RTL
## Pilot cancelled a fence RTL while still outside; suppresses re-latch until back inside
## (DroneModes.fence_answered).
var _fence_answered := false
var _rtl_landing := false   ## RTL has reached its landing leg (so mode_actual reads LAND)
## Last tick's landed predicate. LAND cuts motors one tick late (predicate needs this tick's
## collective demand).
var _landed := false
var _armed_prev := false  ## last tick's arm gate, for the takeoff edge
## Arming machine's only state (laws in drone_arming.gd). `_armed` is LATCHED, not
## recomputed — what makes a refusal possible. `_arm_prev` is the previous REQUEST (rising
## edge; arming is an edge, disarming is a level).
var _armed := false
var _arm_prev := false
var _disarm_hold := 0.0   ## s the craft has been armed AND landed, continuously
## This tick's answers, held for the telemetry block and the mode resolve's forced mode.
var _failsafe: int = DroneArming.FS_NONE  ## contract 'failsafe', the most severe active condition
var _prearm_fail := 0                 ## contract 'prearm_fail' bits, live (0 published in flight)


## Visuals only, physics untouched — the blades are the telemetry, drawn.
func _process(delta: float) -> void:
	if _motors != null:
		_motors.spin_visuals(delta)


func _make_telemetry() -> VehicleTelemetry:
	return DroneTelemetry.new()


func _ready() -> void:
	super._ready()
	_base_mass = spec.mass
	_base_com = spec.center_of_mass
	_hook = DroneHook.new(self)
	_gimbal = DroneGimbalMount.new(self)
	_sensors = DroneSensorSuite.new(self)
	_motors = DroneMotors.new(self)
	_indicators = DroneIndicators.new(self)
	_ahrs_node = DroneBus.index_of("AHRS")
	_apply_carried_mass()
	_home = global_position
	_alt_target = global_position.y
	_loiter_pos = global_position



## Write the current mass/COM onto the body and re-derive everything sized against them.
## Called at _ready and on every hook change, never per tick. This is where a payload is
## FELT — inertia and both collectives go through the SAME calls the empty aircraft used,
## with the mass substituted, so there's no second formula for a loaded quad.
func _apply_carried_mass() -> void:
	var carried := DronePayload.carried_mass(_base_mass, _hook.payload_mass())
	mass = carried
	center_of_mass = DronePayload.carried_com(
			_base_com, _hook.hook_local(), _base_mass, _hook.payload_mass())
	# Box-footprint inertia (m (w^2 + d^2) / 12), the clamp basis for the torque dampers.
	_inertia = VehicleMath.inertia_of(carried, body_extents.x, body_extents.z)
	_hover_collective = clampf(
			lift_thrust(carried, _gravity, 0.0, climb_force, max_thrust)
			/ maxf(max_thrust, 1e-6), 0.0, 1.0)
	# Same call at full climb stick: the ceiling every autonomous mode is clamped to.
	_auto_collective_max = clampf(
			lift_thrust(carried, _gravity, 1.0, climb_force, max_thrust)
			/ maxf(max_thrust, 1e-6), 0.0, 1.0)


## A teleport must not carry spun-up motors or hot ESCs across. The pack is replaced, not
## just cooled — unlike fuel (a gauge nothing else reads), an empty pack stops the motors,
## so a flat pack surviving respawn would leave the craft permanently unflyable. `node_fail`
## is not reset — it's an input, and clearing it here would fight what sloppyCAN is saying.
func respawn() -> void:
	super.respawn()
	_motors.reset()
	# Hook opens, crate left BEHIND at its carried pose — a payload teleporting with the
	# aircraft would be cargo delivered by respawning, which this level must not allow.
	_hook.reset(self)
	_apply_carried_mass()
	_gimbal.reset()
	_pack.reset()
	# The sensors measured where the craft was, so clearing the sky mask makes the receiver
	# reacquire over four ticks and zeroing the debounce means proving grounded again.
	_sensors.reset()
	_landed_hold = 0.0
	# Fresh FC: home is here, both auto latches release. `_mode_request` is NOT reset — a
	# respawn in LOITER re-enters LOITER, anchored here.
	_home = global_position
	_fence_rtl = false
	_fence_answered = false
	_rtl_landing = false
	_landed = false
	_mode_actual = DroneModes.STABILIZE
	# Comes back DISARMED. `_arm_prev` goes to false rather than the live request ON
	# PURPOSE: leaving the edge available lets the craft arm again next tick if the switch
	# is up and checks pass — a way OUT of a stuck aircraft.
	_armed = false
	_arm_prev = false
	_disarm_hold = 0.0
	_failsafe = DroneArming.FS_NONE
	_prearm_fail = 0
	_pos_fix = false
	_fix_hold = 0.0
	_reset_controllers()
	var t := telemetry as DroneTelemetry
	if t != null:
		for i in t.esc_rpm.size():
			t.esc_rpm[i] = 0
			t.esc_current[i] = 0.0
			t.esc_temp[i] = DroneProp.ESC_AMBIENT


## Re-seats every controller on the craft's CURRENT state. Called on a mode change, on the
## disarmed -> armed edge, and from respawn(). Does NOT touch `_fence_rtl`/`_rtl_landing` —
## those cause mode changes, so clearing them here would undo itself.
##
## `keep_trim` carries the climb-rate integrator across a mode change, passed only between
## two cascade modes (`DroneModes.uses_cascade`). Arming/respawn always dump it.
func _reset_controllers(keep_trim := false) -> void:
	if not keep_trim:
		_alt_integ = 0.0
	_alt_target = global_position.y
	_loiter_pos = global_position


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as DroneTelemetry
	var body_basis := global_transform.basis
	var up := body_basis.y
	# Attitude/flight state are the base's (VehicleTelemetry's attitude/height block),
	# already written this tick before _tick_extras runs, so nothing below acts on a
	# controller with a tick of lag.

	# Sensors measured before anything decides anything: two raycasts against level
	# collision (sky fan, rangefinder beam), five rays a tick between them
	# (DroneSensors.SKY_RAYS_PER_TICK). Order is load-bearing: fix_type refuses a LOITER, so
	# resolving against last tick's fix would fly on a stale reading.
	var space := get_world_3d().direct_space_state
	_sensors.measure(space, global_position)
	# The two node gates fail in OPPOSITE directions on purpose — offline GNSS publishes an
	# empty sky (one substitution), offline rangefinder publishes INVALID, never 0. See
	# drone_sensor_suite.gd.
	_sensors.publish(t, input.node_fail)

	# Read once per tick: the barometer's static port and both dampers below need the same
	# wind value.
	var wind := WindField.at(self)

	# The barometer's whole point is to disagree with the two heights just published (two
	# labelled models, see drone_air_data.gd). Ungated by the bus roster: no barometer node
	# to fail.
	_air_time += delta
	var airspeed := (linear_velocity - wind).length()
	t.static_press = DroneAirData.pressure_at(
			global_position.y, DroneAirData.sea_level_pressure(_air_time)) \
			+ DroneAirData.port_error_pa(airspeed)
	t.baro_alt = DroneAirData.altitude_from(t.static_press, DroneAirData.QNH_STANDARD)
	t.oat = DroneAirData.oat_c(global_position.y)

	# The cargo hook, above the arming block: a payload changes the mass that the pre-arm
	# check and every controller below are sized against. Hook only decides the latch; the
	# mass write is this class's, on the two edges only (`tick` returns "latch changed").
	if _hook.tick(input.hardpoint_cmd, space, self):
		_apply_carried_mass()
	t.hardpoint_state = _hook.latched
	t.payload_weight = DronePayload.payload_weight_n(_hook.payload_mass(), _gravity)

	# The mode/failsafes decide on the DEBOUNCED fix, never the raw one just published (see
	# drone_modes.gd). Stepped here, above the arming block, since the pre-arm GPS check
	# reads the same held predicate the mode refusal does.
	var raw_fix := DroneModes.has_pos_fix(t.fix_type)
	_fix_hold = DroneModes.fix_hold_step(_fix_hold, raw_fix, _pos_fix, delta)
	_pos_fix = DroneModes.held_fix_ok(raw_fix, _pos_fix, _fix_hold)

	# --- arming, pre-arm checks and failsafes (pure fns in drone_arming.gd) -----------
	# Reads this tick's fix/attitude/pack; mode resolve below reads armed + forced mode.
	# Key + pack gate arming. SOC is last tick's accumulator (integrated below, 16 ms lag).
	var power_ok := input.key == InputRouter.KEY_IGNITION and _pack.has_charge()
	# Mode_want is request after fence latch, before failsafe forcing (wanted_mode).
	# Reading resolved mode would close a loop: a forced failsafe could decide on itself.
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
	# Post-landing auto-disarm on LAST tick's landed predicate (same one-tick discipline as
	# LAND's motor cut — the predicate needs a collective demand this tick hasn't produced).
	_disarm_hold = DroneArming.disarm_hold_step(_disarm_hold, _armed, _landed, delta)
	_armed = DroneArming.arm_step(_armed, input.arm, _arm_prev, power_ok, _prearm_fail, _landed,
			DroneArming.auto_disarm_due(_disarm_hold))
	_arm_prev = input.arm
	var armed := _armed
	# Taking off is a fresh flight: no accumulated trim, both hold targets on the aircraft.
	# The disarm edge is left to the latches below.
	if armed and not _armed_prev:
		_reset_controllers()
	_armed_prev = armed

	# Horizontal air drag always acts, one-tick clamped. The VERTICAL damper is rotor-borne
	# (sets the terminal climb/descent rate the turning rotors produce), so it gates on the
	# MOTORS TURNING rather than `armed`: a disarm spools down over ~5*tau, still making lift.
	# Once stopped the craft is an inert body in near free fall.
	# Both dampers oppose velocity relative to the AIR (VehicleMath.air_damper); in still air
	# that's velocity itself. The two axis masks keep horizontal/vertical coefficients separate.
	apply_central_force(VehicleMath.air_damper(linear_velocity, wind, horizontal_drag,
			mass, delta, Vector3(1.0, 0.0, 1.0)))
	if armed or _motors.turning():
		apply_central_force(VehicleMath.air_damper(linear_velocity, wind, vertical_drag,
				mass, delta, Vector3(0.0, 1.0, 0.0)))

	# --- flight modes (pure fns in drone_modes.gd) -----------------------------
	# Home tracks the craft while disarmed, latching at the arming position — home_dist
	# reads 0 on the ground and the fence can't breach before takeoff.
	if not armed:
		_home = global_position
	var home_dist := DroneModes.home_distance(global_position, _home)

	# The two auto latches release on a CHANGE of the pilot's requested mode — how control
	# comes back after an override. A failsafe is NOT released here (a live condition can't
	# be dismissed by Z; it clears when its cause does — restore the ESC with Y, respawn for
	# a fresh pack).
	if input.flight_mode != _mode_request:
		_mode_request = input.flight_mode
		_fence_answered = _fence_rtl   # cancelled OUT beyond the fence: it may not re-command
		_fence_rtl = false
		_rtl_landing = false
	# SOFT: commands a return, doesn't stop the aircraft (WorldBounds is still the hard wall).
	# The cancel above only holds because `fence_answered` suppresses the re-latch until back
	# inside — release and latch run on the same tick, so without it the breach re-commands
	# RTL immediately.
	_fence_answered = DroneModes.fence_answered(_fence_answered, armed, global_position, _home,
			DroneModes.GEOFENCE_RADIUS, DroneModes.GEOFENCE_CEILING)
	_fence_rtl = not _fence_answered and DroneModes.fence_latch(_fence_rtl, armed,
			global_position, _home, DroneModes.GEOFENCE_RADIUS, DroneModes.GEOFENCE_CEILING)
	var rtl_phase := DroneModes.rtl_phase_of(global_position, _home,
			DroneModes.RTL_ALT, DroneModes.RTL_ARRIVE_M)
	# Resolve, latch on what that resolved to, resolve again: the landing leg may only latch
	# off a mode actually being flown, and re-resolving keeps `resolve_mode` the one place a
	# mode is decided (the second call is pure and free).
	#
	# A failsafe forces its mode through the same call as `forced` — still one decision site:
	# BATT_LOW commands RTL, BATT_CRIT/an offline ESC command LAND, both over pilot and fence
	# via DroneModes.auto_rank.
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

	# Demands are in the mixer's thrust-fraction units, not forces/torques. Disarmed they
	# stay zero, so the motors spool down to nothing.
	var collective := 0.0
	var roll_demand := 0.0
	var pitch_demand := 0.0
	var yaw_demand := 0.0
	# LAND's touchdown cut zeroes ALL FOUR demands, not just collective — see below.
	var motors_cut := false
	if armed:
		var stick_climb := clampf(input.climb, -1.0, 1.0)
		var stick_throttle := clampf(input.throttle, -1.0, 1.0)
		var max_tilt_rad := deg_to_rad(max_tilt_deg)
		# Manual tilt, default in every mode that doesn't overwrite it. Negated so W leans
		# the nose FORWARD.
		var tilt := Vector2(-stick_throttle * max_tilt_rad, 0.0)
		if _mode_actual == DroneModes.STABILIZE:
			# Hover feedforward plus climb trim, as a fraction of max_thrust. The climb axis
			# is a thrust TRIM here, a climb RATE in every other mode — that's STABILIZE.
			collective = clampf(lift_thrust(mass, _gravity, stick_climb,
					climb_force, max_thrust) / maxf(max_thrust, 1e-6), 0.0, 1.0)
		else:
			# Every autonomous mode is the same two controllers with different targets — one
			# cascade, not four. Only where the targets come from and whether sticks are
			# listened to changes.
			var rate_cmd := 0.0
			var hold_pos := false
			match _mode_actual:
				DroneModes.ALT_HOLD:
					if absf(stick_climb) > DroneModes.STICK_DEADBAND:
						rate_cmd = stick_climb * DroneModes.ALT_RATE_MAX
				DroneModes.LOITER:
					if absf(stick_climb) > DroneModes.STICK_DEADBAND:
						rate_cmd = stick_climb * DroneModes.ALT_RATE_MAX
					# Stick out of deadband: pilot is flying, anchor follows the craft;
					# releasing holds wherever it was let go.
					if absf(stick_throttle) > DroneModes.STICK_DEADBAND:
						_loiter_pos = global_position
					else:
						hold_pos = true
				DroneModes.RTL:
					# Sticks ignored except yaw — no real FC takes the yaw stick away.
					var target := DroneModes.rtl_target(_home, global_position, rtl_phase,
							DroneModes.RTL_ALT)
					_alt_target = target.y
					_loiter_pos = target
					hold_pos = true
				DroneModes.LAND:
					rate_cmd = -DroneModes.LAND_RATE
					# An RTL that handed over keeps holding home: the mode change re-anchored
					# `_loiter_pos` on the craft, right for a pilot-selected LAND but wrong for
					# an RTL's last leg — reach rtl_target's RTL_LAND leg here instead.
					if _rtl_landing:
						_loiter_pos = DroneModes.rtl_target(_home, global_position,
								DroneModes.RTL_LAND, DroneModes.RTL_ALT)
					# Position-held with a fix, free-drifting without one; mode_actual still
					# reads LAND (see resolve_mode) — `failsafe` carries GPS_LOST separately.
					hold_pos = _pos_fix
					motors_cut = _landed
			# While a rate is commanded the altitude target rides the craft (pure
			# feedforward); once the stick centres the target holds and the P term takes
			# over. RTL sets the target itself above.
			if _mode_actual != DroneModes.RTL and not is_zero_approx(rate_cmd):
				_alt_target = global_position.y
			var rate_target := DroneModes.alt_rate_target(_alt_target - global_position.y, rate_cmd)
			var rate_err := rate_target - linear_velocity.y
			_alt_integ = DroneModes.alt_integ_step(_alt_integ, rate_err, delta)
			collective = DroneModes.alt_hold_collective(_hover_collective, rate_err, _alt_integ,
					_auto_collective_max)
			if hold_pos:
				# Position error and ground velocity in the HEADING FRAME — the same
				# `heading_frame` call feeds this and level_target_up below so the two can't
				# disagree about which way "right" is.
				var frame := heading_frame(body_basis)
				var err := _loiter_pos - global_position
				tilt = DroneModes.position_tilt_demand(
						Vector2(err.dot(-frame.z), err.dot(frame.x)),
						Vector2(linear_velocity.dot(-frame.z), linear_velocity.dot(frame.x)),
						max_tilt_rad)

		# Attitude: chase whatever tilt the active mode asked for. align_torque (A x B) is
		# sign-correct by construction; the damper opposes only off-axis angular velocity so
		# it never fights yaw. Every mode reaches the airframe through this ONE path
		# (limit_length'd by the same max_attitude_torque), so autonomy can't out-torque a stick.
		var target_up := level_target_up(body_basis, tilt)
		var perp := angular_velocity - up * angular_velocity.dot(up)
		var att := (align_torque(up, target_up, attitude_stiffness)
				+ VehicleMath.clamped_damper(perp, attitude_damping, _inertia, delta)).limit_length(max_attitude_torque)
		# Split onto the two axes the mixer can produce; the body-Y component is dropped
		# (align_torque is a cross with body up, `perp` already excludes yaw rate).
		roll_demand = DroneProp.torque_to_demand(att.dot(body_basis.z), _motors.arm_x, max_thrust)
		pitch_demand = DroneProp.torque_to_demand(att.dot(body_basis.x), _motors.arm_z, max_thrust)

		# Yaw: drive the yaw rate toward the commanded rate about body up. steer negative =
		# left; +Y torque yaws left, so the sign flips (the boat's rudder convention). Manual
		# in every mode, RTL included.
		var yaw_t := VehicleMath.yaw_torque(-_steer * max_yaw_rate, angular_velocity.dot(up),
				yaw_gain, _inertia, delta, max_yaw_torque)
		yaw_demand = DroneProp.torque_to_demand(yaw_t, prop_torque_ratio, max_thrust)

		if motors_cut:
			# Zeroing only the collective is not a cut: mix_quad_x clamps the sum per motor,
			# so an attitude demand still drives two motors positive at zero collective — a
			# craft on a slope would fight the terrain (~25 N against 49 N of weight,
			# skittering or tipping). Zeroed here, after computing, so the loops above keep
			# running regardless of whether the motors are turning.
			collective = 0.0
			roll_demand = 0.0
			pitch_demand = 0.0
			yaw_demand = 0.0
			# The integrator too: left running against LAND's rate it saturates within
			# seconds, and `keep_trim` would hand that straight to the next ALT_HOLD.
			# Anti-windup by the plainest route. Auto-disarm follows a few seconds later
			# (DroneArming.disarm_hold_step).
			_alt_integ = 0.0

	# Mix -> gate -> spool -> thrust at each rotor's own arm: roll/pitch torque are the arm
	# geometry, yaw is the summed prop reaction; the node-failure gate lands AFTER the mix,
	# uncompensated. Tuning knobs are passed rather than copied into drone_motors.gd.
	_motors.apply(self, collective, roll_demand, pitch_demand, yaw_demand, input.node_fail,
			max_thrust, motor_spool_tau, prop_torque_ratio, delta)

	# ESC bus read out of the motors (rule 3), published element-wise so an offline ESC holds
	# its last reading. The four amps feed the pack below.
	var amps := _motors.publish(t, input.node_fail, max_thrust, prop_torque_ratio, delta)
	# `armed` is unchanged in meaning (the ESC gate bool); the three beside it are what state
	# the FC is in, why it refused, and what it's reacting to. `prearm_fail` goes dark in
	# flight (DroneArming.published_fail) — a check gating nothing isn't a refusal.
	t.armed = armed
	t.arming_state = DroneArming.state_of(armed, input.arm, power_ok, _prearm_fail)
	t.prearm_fail = DroneArming.published_fail(armed, _prearm_fail)
	t.failsafe = _failsafe

	# Pack downstream of the ESCs: pack_current sums the four amps plus a constant avionics
	# draw, soc coulomb-counts that sum, terminal voltage is the OCV curve minus IR drop.
	# `battery` overwrites the base's alternator write — the drone has no alternator.
	var pack_a := _pack.step(amps, delta)
	t.pack_current = pack_a
	t.soc = _pack.soc
	t.pack_temp = _pack.temp
	t.battery = _pack.volts(pack_a)

	# `mode_actual` is what the FC is in after every refusal/override, so it disagreeing with
	# the `flight_mode` request is the reading (e.g. LOITER dropped to ALT_HOLD on GNSS loss).
	t.mode_actual = _mode_actual
	t.home_dist = home_dist

	# Gimbal: slew-limited toward the command, then written onto the HoodCam marker —
	# ChaseCamera's HOOD view composes that transform, so this is the whole FPV feed.
	# Published as where it HAS reached, not what was asked for.
	_gimbal.tick(input.gimbal_pitch, input.gimbal_yaw, delta)
	t.gimbal_pitch_actual = _gimbal.pitch
	t.gimbal_yaw_actual = _gimbal.yaw

	# ST_GROUND: the predicate reads the suite's OWN measurement, not published `t.agl`, so
	# an offline RANGE node invalidates the reading without the aircraft forgetting it's
	# grounded. `collective` here is the demand before the mixer clamped it or a dead motor
	# swallowed it — a takeoff is what the pilot asked for.
	_landed_hold = DroneSensors.landed_hold(_landed_hold, DroneSensors.landed_now(
			_sensors.agl(), t.vspeed, collective,
			DroneSensors.LANDED_AGL, DroneSensors.LANDED_VSPEED,
			_hover_collective * DroneSensors.LANDED_COLLECTIVE_FRAC), delta)
	t.ground = _landed_hold >= DroneSensors.LANDED_DEBOUNCE
	t.status = VehicleTelemetry.with_status_bit(t.status, VehicleTelemetry.ST_GROUND, t.ground)
	# Held for LAND to cut motors NEXT tick — can't read this tick, since the predicate needs
	# the collective demand the mode branch already produced (16 ms after a 0.5 s debounce).
	_landed = t.ground

	# The airframe's own lights and the rangefinder beam, LAST: they show what this tick published.
	_indicators.tick(t, power_ok, self)


# --- the body's own flight math (unit-tested; the motors are DroneProp's) ------
#
# The BODY's own math: how much lift the craft may ask for, which way is forward, where
# "level" points once tilted, and the torque that gets it there. Mixer/motors/per-ESC bus
# are in drone_propulsion.gd.

## Total rotor thrust (N) along body up. Hover feedforward counters gravity; the climb
## stick adds/removes lift. Non-negative (rotors only push) and hard-capped at max_thrust.
static func lift_thrust(body_mass: float, gravity: float, climb: float,
		climb_gain: float, thrust_cap: float) -> float:
	return clampf(body_mass * gravity + climb * climb_gain, 0.0, thrust_cap)


## The craft's heading frame: yaw only, level, right-handed — `basis.x` is heading-right,
## `basis.y` is world up, `-basis.z` is flat forward. ONE definition, so level_target_up and
## the position controller's error projection can't disagree about which way "right" is.
##
## Degenerate nose-vertical case: falls back to the up-vector's own heading, and to
## Basis.IDENTITY only if that's vertical too.
static func heading_frame(body_basis: Basis) -> Basis:
	var fwd := -body_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 1e-3:
		flat = Vector3(body_basis.y.x, 0.0, body_basis.y.z)
	if flat.length() < 1e-3:
		return Basis.IDENTITY
	flat = flat.normalized()
	return Basis(flat.cross(Vector3.UP).normalized(), Vector3.UP, -flat)


## Target body-up direction: world up tilted by `tilt` rad. tilt.x is fore/aft lean (right axis),
## tilt.y is lateral lean (forward axis). One rotation about the combined axis, so total lean
## is exactly `tilt.length()` — a diagonal cannot make 45 deg from two 32-degree axes.
static func level_target_up(body_basis: Basis, tilt: Vector2) -> Vector3:
	var frame := heading_frame(body_basis)
	var rot := frame.x * tilt.x + (-frame.z) * tilt.y
	var angle := rot.length()
	if angle < 1e-9:
		return Vector3.UP
	return Vector3.UP.rotated(rot / angle, angle)


## Corrective torque rotating `body_up` toward `target_up` (A x B). Direction is correct
## by construction (no trig sign chasing); magnitude ~ sin(error) * stiffness.
static func align_torque(body_up: Vector3, target_up: Vector3, stiffness: float) -> Vector3:
	return body_up.cross(target_up) * stiffness
