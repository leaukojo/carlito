extends GdUnitTestSuite
## DroneVehicle orchestration: tests published telemetry and public properties, not private
## fields. Body pose/velocity scripted, ticks called directly (_update_telemetry then
## _tick_extras from base_vehicle.gd:159,175). Delta is 1/60 per standing rule 9.

const Router := preload("res://src/input/input_router.gd")
const Layers := preload("res://src/physics/collision_layers.gd")
const Modes := preload("res://src/vehicles/drone/drone_modes.gd")
const Arming := preload("res://src/vehicles/drone/drone_arming.gd")
const Sensors := preload("res://src/vehicles/drone/drone_sensors.gd")
const Bus := preload("res://src/vehicles/drone/drone_bus.gd")
const Prop := preload("res://src/vehicles/drone/drone_propulsion.gd")
const Gimbal := preload("res://src/vehicles/drone/drone_gimbal.gd")
const Power := preload("res://src/vehicles/drone/drone_power.gd")

const DRONE := "res://src/vehicles/drone/drone.tscn"
const CRATE := "res://src/levels/base/cargo_payload.tscn"
const DELTA := 1.0 / 60.0

## Ticks until a position fix is available: full ray sweep + FIX_DEBOUNCE + margin.
const FIX_TICKS := int(float(Sensors.SKY_RAYS) / float(Sensors.SKY_RAYS_PER_TICK)) \
		+ int(Modes.FIX_DEBOUNCE / DELTA) + 4


## The rig: a level-ish root, the aircraft, and optionally a floor for the rays to return off.
## Only the ROOT is auto_free'd — freeing it takes the whole subtree exactly once, which is what
## the cargo case needs: a latched crate REPARENTS itself under the hook, and registering it
## separately would be a second free of an already-dead instance (test_tow_host's note).
class Rig extends RefCounted:
	var root: Node3D
	var drone: DroneVehicle
	var t: DroneTelemetry
	var input: VehicleInput

	## One tick, in the base's own order: the attitude/height block first (the sensors, the
	## pre-arm attitude check and the landed predicate all read THIS tick's values), then the
	## subsystem hook.
	func tick(n := 1) -> void:
		for _i in n:
			drone._update_telemetry(input, DELTA)
			drone._tick_extras(input, DELTA)

	func seconds(s: float) -> void:
		tick(int(round(s / DELTA)))

	## Raise the arm switch on a RISING EDGE — down for a tick first, because arming is an edge
	## and a switch that was already up has spent it (drone_arming.gd).
	func arm() -> void:
		input.arm = false
		tick()
		input.arm = true
		tick()


## floor_y: top surface of static box, or NAN for open air. One awaited frame is required:
## bodies not in space state until space steps once. Pose written after frame.
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
		# A box's origin is its centre, so drop it half its height to put the TOP at floor_y.
		ground.global_position = Vector3(pos.x, floor_y - 5.0, pos.z)
	r.drone = (load(DRONE) as PackedScene).instantiate() as DroneVehicle
	r.root.add_child(r.drone)
	await get_tree().physics_frame
	r.drone.global_position = pos
	r.drone.linear_velocity = Vector3.ZERO
	r.drone.angular_velocity = Vector3.ZERO
	r.t = r.drone.telemetry as DroneTelemetry
	r.input = VehicleInput.new()
	r.input.key = Router.KEY_IGNITION
	return r


## A crate on the ground under the hook. The shipped `cargo_payload.tscn` rather than a stub,
## because what is being pinned is that the REAL crate's mass reaches the airframe. Awaits a frame
## for the same reason `_rig` does — the capture ray cannot see a collider the space has not
## stepped over yet, and the hook would read as broken.
func _crate(r: Rig, pos: Vector3) -> CargoPayload:
	var c := (load(CRATE) as PackedScene).instantiate() as CargoPayload
	r.root.add_child(c)
	c.global_position = pos
	c.freeze = true
	await get_tree().physics_frame
	c.global_position = pos
	return c


## An armed craft in open air with a settled position fix — the state most cases start from.
func _flying(pos := Vector3(0.0, 50.0, 0.0)) -> Rig:
	var r: Rig = await _rig(pos)
	r.tick(FIX_TICKS)
	r.arm()
	return r


# --- the rig itself -------------------------------------------------------------------------

## The guard on every case below: a ticked drone really does fill its whole cluster, so a later
## assertion reading a default is reading a REGRESSION rather than a rig that never ran.
func test_a_ticked_drone_publishes_its_whole_cluster() -> void:
	var r: Rig = await _flying()
	r.seconds(1.0)
	assert_bool(r.t.armed).is_true()
	assert_int(r.t.sats).is_equal(Sensors.SKY_RAYS)          # open sky above, nothing occluding
	assert_int(r.t.fix_type).is_equal(Sensors.FIX_3D)
	assert_float(r.t.agl).is_equal(Sensors.RANGE_INVALID)    # nothing below: no return, not zero
	assert_int(r.t.rotor_rpm).is_greater(0)
	assert_float(r.t.pack_current).is_greater(0.0)
	assert_float(r.t.soc).is_less(100.0)
	assert_float(r.t.battery).is_greater(0.0)
	assert_float(r.t.static_press).is_greater(0.0)
	assert_int(r.t.node_online).is_equal(Bus.online_bits(0))


# --- arming ----------------------------------------------------------------------------------

## Arming is an edge, disarming is a level. Switch already-up arms the craft (respawn escape).
func test_arming_is_an_edge_so_an_auto_disarmed_craft_needs_the_switch_cycled() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(FIX_TICKS)
	r.arm()
	assert_bool(r.t.armed).is_true()
	# Sit there with the switch UP until the post-landing timer runs out.
	r.seconds(Arming.AUTO_DISARM_S + 1.5)
	assert_bool(r.t.armed).is_false()
	# ...and it stays down, however long the switch is left up. This is the case that would go
	# green on a level-triggered arm while the aircraft strobed its motors once a second.
	r.seconds(5.0)
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.arming_state).is_equal(Arming.DISARMED)
	assert_int(r.t.rotor_rpm).is_equal(0)
	# Cycle it, and the same aircraft arms again on the very next tick.
	r.arm()
	assert_bool(r.t.armed).is_true()
	assert_int(r.t.arming_state).is_equal(Arming.ARMED)


## A disarm thrown in flight is REFUSED — five kilograms falling out of the sky is not a thing a
## switch may ask for. The gate is the landed predicate, and in open air (no rangefinder return)
## the craft is never landed, so the refusal holds indefinitely.
func test_a_disarm_is_refused_in_flight() -> void:
	var r: Rig = await _flying()
	r.input.arm = false
	r.seconds(5.0)
	assert_bool(r.t.armed).is_true()
	assert_bool(r.t.ground).is_false()


## ...and it is not LOST either: the instruction lands the moment the craft is down and settled.
func test_the_refused_disarm_takes_effect_once_the_craft_is_down() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(FIX_TICKS)
	r.arm()
	r.seconds(1.0)                       # outlast LANDED_DEBOUNCE with the craft on the deck
	assert_bool(r.t.ground).is_true()
	assert_bool(r.t.armed).is_true()
	r.input.arm = false
	r.tick(2)
	assert_bool(r.t.armed).is_false()


## The post-landing auto-disarm: the switch is left UP, so nothing asks the craft to stop, and it
## stops itself a few seconds after touchdown. It reads DISARMED rather than BLOCKED afterwards —
## nothing is refusing it, it is waiting for the switch to be cycled.
func test_the_craft_auto_disarms_a_few_seconds_after_touchdown() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(FIX_TICKS)
	r.arm()
	r.seconds(1.0)
	assert_bool(r.t.armed).is_true()     # the timer has not run out yet
	r.seconds(Arming.AUTO_DISARM_S + 0.5)
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.arming_state).is_equal(Arming.DISARMED)


## The key is a MASTER SWITCH, not a check: it cuts instantly and unconditionally, and an
## unpowered flight controller reads DISARMED rather than BLOCKED — it is absent, not refusing.
func test_the_key_is_a_master_switch_and_an_unpowered_fc_refuses_nothing() -> void:
	var r: Rig = await _flying()
	r.seconds(1.0)
	assert_bool(r.t.armed).is_true()
	r.input.key = Router.KEY_ON
	r.tick()
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.arming_state).is_equal(Arming.DISARMED)
	# ...and the motors spool DOWN rather than stopping dead, still making decaying lift.
	var spooling := r.t.rotor_rpm
	assert_int(spooling).is_greater(0)
	r.tick(10)
	assert_int(r.t.rotor_rpm).is_less(spooling)


## A REFUSAL, as against nobody asking: the switch is up, the aircraft is powered, and a check
## says no. BLOCKED, with the offending bit named — here the climb stick, which a real FC refuses
## to arm under.
func test_a_refused_arm_reads_blocked_and_names_the_check() -> void:
	var r: Rig = await _rig()
	r.tick(FIX_TICKS)
	r.input.climb = 1.0
	r.arm()
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.arming_state).is_equal(Arming.BLOCKED)
	assert_int(r.t.prearm_fail & Arming.PA_STICK).is_equal(Arming.PA_STICK)
	# Centre the stick and cycle the switch: the same aircraft now arms.
	r.input.climb = 0.0
	r.arm()
	assert_bool(r.t.armed).is_true()


## `prearm_fail` goes DARK in flight. A flying craft deflects its climb stick and leans past ten
## degrees constantly, so live bits would light through every manoeuvre and make the signal
## unreadable in exactly the state it has nothing to say about.
func test_prearm_fail_publishes_nothing_while_armed() -> void:
	var r: Rig = await _flying()
	r.input.climb = 1.0                                     # would be PA_STICK on the ground
	var xform := r.drone.global_transform
	xform.basis = Basis(Vector3.RIGHT, deg_to_rad(25.0))    # ...and PA_ATTITUDE
	r.drone.global_transform = xform
	r.tick(10)
	assert_bool(r.t.armed).is_true()
	assert_int(r.t.prearm_fail).is_equal(0)


# --- the mode ladder -------------------------------------------------------------------------

## Every rung of the ladder is reachable on a craft with a fix, and `mode_actual` reads back what
## was asked for. This is the case the dev tool cannot make: `measure_drone` flies STABILIZE only.
##
## The craft is flown away from home first, and that is not scene-setting. An RTL selected while
## the aircraft is already sitting on its home point is on its LANDING LEG immediately, so it
## reads LAND — correctly, and it is the `rtl_landing_latch` behaviour `test_drone_modes` pins
## from the pure side. Asking for RTL somewhere it can actually return FROM is what makes this a
## test of the ladder rather than of that latch.
func test_every_flight_mode_is_reachable_and_read_back() -> void:
	var r: Rig = await _flying()
	r.drone.global_position = Vector3(100.0, 50.0, 0.0)   # inside the fence, well out from home
	r.tick(2)
	for mode in [Modes.STABILIZE, Modes.ALT_HOLD, Modes.LOITER, Modes.RTL, Modes.LAND]:
		r.input.flight_mode = mode
		r.tick(2)
		assert_int(r.t.mode_actual) \
				.override_failure_message("mode %d did not resolve to itself" % mode) \
				.is_equal(mode)


## A DISARMED craft is always STABILIZE, whatever the switch says — there is no autonomous mode
## for an aircraft that is not flying.
func test_a_disarmed_craft_is_always_stabilize() -> void:
	var r: Rig = await _rig()
	r.tick(FIX_TICKS)
	r.input.flight_mode = Modes.LOITER
	r.tick(2)
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.mode_actual).is_equal(Modes.STABILIZE)


## LOITER without a position fix falls back to ALT_HOLD, and the disagreement between the request
## and `mode_actual` IS the reading. Taking the GNSS node off the bus is the honest way to remove
## the fix: it is the same substitution the sensors make, not a second code path.
func test_loiter_without_a_fix_falls_back_to_alt_hold() -> void:
	var r: Rig = await _flying()
	r.input.flight_mode = Modes.LOITER
	r.tick(2)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)
	r.input.node_fail = 1 << Bus.index_of("GNSS")
	r.seconds(Modes.FIX_DEBOUNCE + 0.2)          # the DECISION is debounced; the reading is not
	assert_int(r.t.fix_type).is_equal(Sensors.FIX_NONE)
	assert_int(r.t.mode_actual).is_equal(Modes.ALT_HOLD)


# --- the two auto latches --------------------------------------------------------------------

## The geofence is SOFT: it COMMANDS a return rather than stopping the aircraft, and it latches so
## the override cannot chatter against the flight it causes. Home is where the craft armed, so
## `home_dist` is measured from there.
##
## The mode key hands control back from anywhere, the fence included, and this case pins the part
## that costs something to keep true: the vehicle clears `_fence_rtl` on a mode change and calls
## `fence_latch` on the SAME tick, so the cancel only survives because `fence_answered` suppresses
## the re-latch while the craft is still outside. The suppression is not a permanent disarm of the
## fence — it clears on re-entry, and the next breach commands RTL again.
func test_the_geofence_commands_rtl_and_the_mode_key_cancels_it_from_outside() -> void:
	var r: Rig = await _flying()
	assert_float(r.t.home_dist).is_equal_approx(0.0, 1e-3)
	r.drone.global_position = Vector3(Modes.GEOFENCE_RADIUS + 100.0, 50.0, 0.0)
	r.tick(2)
	assert_float(r.t.home_dist).is_greater(Modes.GEOFENCE_RADIUS)
	assert_int(r.t.mode_actual).is_equal(Modes.RTL)
	assert_int(r.t.failsafe).is_equal(Arming.FS_GEOFENCE)
	# The mode key, pressed while still in breach: the fence stops commanding and STAYS quiet out
	# here, however far the craft keeps flying from home.
	r.input.flight_mode = Modes.ALT_HOLD
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_NONE)
	assert_int(r.t.mode_actual).is_equal(Modes.ALT_HOLD)
	r.drone.global_position = Vector3(Modes.GEOFENCE_RADIUS + 400.0, 50.0, 0.0)
	r.tick(2)
	assert_int(r.t.mode_actual).is_equal(Modes.ALT_HOLD)
	# Back inside, and the cancel is spent: the fence is armed again and the NEXT breach commands.
	r.drone.global_position = Vector3(10.0, 50.0, 0.0)
	r.tick(2)
	assert_int(r.t.mode_actual).is_equal(Modes.ALT_HOLD)
	r.drone.global_position = Vector3(Modes.GEOFENCE_RADIUS + 100.0, 50.0, 0.0)
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_GEOFENCE)
	assert_int(r.t.mode_actual).is_equal(Modes.RTL)
	# Flying home does NOT release the latch by itself — that is the anti-chatter rule, not a stuck
	# bit: releasing on re-entry would release the command that flew the craft there.
	r.drone.global_position = Vector3(10.0, 50.0, 0.0)
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_GEOFENCE)
	assert_int(r.t.mode_actual).is_equal(Modes.RTL)
	# ...and the mode key hands control back from in here too.
	r.input.flight_mode = Modes.LOITER
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_NONE)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)


## A failsafe is not a latch, and the mode key cannot dismiss one. An ESC off the bus commands
## LAND, and it keeps commanding LAND through every mode change until its cause is gone.
func test_a_failsafe_is_not_released_by_a_mode_change() -> void:
	var r: Rig = await _flying()
	r.input.node_fail = 1 << 0                    # ESC1 (roster index 0) off the bus
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_MOTOR)
	assert_int(r.t.mode_actual).is_equal(Modes.LAND)
	for mode in [Modes.STABILIZE, Modes.ALT_HOLD, Modes.LOITER]:
		r.input.flight_mode = mode
		r.tick(2)
		assert_int(r.t.mode_actual) \
				.override_failure_message("mode key %d dismissed a live failsafe" % mode) \
				.is_equal(Modes.LAND)
	# ...and it clears when its CAUSE does, with nothing dismissing it.
	r.input.node_fail = 0
	r.tick(2)
	assert_int(r.t.failsafe).is_equal(Arming.FS_NONE)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)


# --- the sensors -----------------------------------------------------------------------------

## A measurement is raw; a decision is debounced. The published fix follows the sky immediately,
## while the predicate the MODE reads waits out FIX_DEBOUNCE — which is why a receiver flickering
## across the four-satellite line cannot toggle LOITER at the tick rate.
func test_the_mode_is_debounced_while_the_published_fix_is_not() -> void:
	var r: Rig = await _flying()
	r.input.flight_mode = Modes.LOITER
	r.tick(2)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)
	r.input.node_fail = 1 << Bus.index_of("GNSS")
	r.tick(2)
	# The reading has already gone. The decision has not.
	assert_int(r.t.fix_type).is_equal(Sensors.FIX_NONE)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)
	# Restore it well inside the debounce window: the mode never moved.
	r.input.node_fail = 0
	r.seconds(Modes.FIX_DEBOUNCE + 0.2)
	assert_int(r.t.mode_actual).is_equal(Modes.LOITER)


## The two node gates are DELIBERATELY OPPOSITE, and this is the case that says so. A receiver
## that has stopped talking is not still solving, so the fix collapses; a rangefinder that has
## stopped talking publishes the INVALID sentinel and never a zero, because zero is precisely the
## value a landing detector would act on.
func test_the_two_sensor_nodes_fail_in_opposite_directions() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(FIX_TICKS)
	assert_int(r.t.sats).is_equal(Sensors.SKY_RAYS)
	assert_float(r.t.agl).is_equal_approx(0.3, 1e-3)
	r.input.node_fail = (1 << Bus.index_of("GNSS")) | (1 << Bus.index_of("RANGE"))
	r.tick(2)
	assert_int(r.t.sats).is_equal(0)
	assert_int(r.t.fix_type).is_equal(Sensors.FIX_NONE)
	assert_float(r.t.hdop).is_equal_approx(Sensors.HDOP_MAX, 1e-3)
	assert_float(r.t.agl).is_equal(Sensors.RANGE_INVALID)
	# ...and the craft has NOT forgotten it is standing on the ground: the landed predicate reads
	# the airframe's own measurement, not the published one.
	assert_bool(r.t.ground).is_true()


# --- the motors and the bus ------------------------------------------------------------------

## A dropped node holds its last telemetry — it must never be zeroed, because a stale reading
## beside a live total is the whole reason to have a node roster. Meanwhile the state underneath
## keeps integrating the truth: the gated motor really does spool down, so `pack_current` (measured
## at the pack) FALLS while the published rpm stands still.
func test_an_offline_esc_holds_its_telemetry_while_the_pack_tells_the_truth() -> void:
	var r: Rig = await _flying()
	r.seconds(1.0)
	var held_rpm := int(r.t.esc_rpm[0])
	var held_amps := float(r.t.esc_current[0])
	var pack_before := r.t.pack_current
	assert_int(held_rpm).is_greater(0)
	r.input.node_fail = 1 << 0
	r.seconds(2.0)
	assert_int(int(r.t.esc_rpm[0])).is_equal(held_rpm)                   # frozen, never zeroed
	assert_float(float(r.t.esc_current[0])).is_equal_approx(held_amps, 1e-4)
	assert_int(int(r.t.esc_rpm[1])).is_greater(0)                        # the live ones keep going
	assert_float(r.t.pack_current).is_less(pack_before)                  # the true draw fell
	assert_int(r.t.esc_fault & 1).is_equal(1)
	assert_int(r.t.node_online & 1).is_equal(0)


## ...and `rotor_rpm` counts the STALE element, on purpose: it is the mean of the PUBLISHED array,
## which is what a listener reading four messages would compute and what the contract defines it
## as. It and `pack_current` disagreeing after a node drops is the reading, not a bug.
func test_rotor_rpm_is_the_mean_of_the_published_array_stale_element_included() -> void:
	var r: Rig = await _flying()
	r.seconds(1.0)
	r.input.node_fail = 1 << 0
	r.seconds(2.0)
	var sum := 0
	for v in r.t.esc_rpm:
		sum += int(v)
	assert_int(r.t.rotor_rpm).is_equal(Prop.rotor_rpm(PackedInt32Array(r.t.esc_rpm)))
	assert_int(r.t.rotor_rpm).is_greater(0)
	assert_int(sum).is_greater(0)


## The motors are a first-order lag toward their command, not a step: arming does not put the
## rotors at hover speed on the next tick.
func test_the_motors_spool_rather_than_step() -> void:
	var r: Rig = await _rig()
	r.tick(FIX_TICKS)
	r.arm()
	var first := r.t.rotor_rpm
	r.tick(3)
	var later := r.t.rotor_rpm
	assert_int(first).is_greater(0)
	assert_int(later).is_greater(first)                # still climbing toward the command
	r.seconds(1.0)
	var settled := r.t.rotor_rpm
	assert_int(settled).is_greater(later)
	# Hover is sqrt(m*g / max_thrust) of the rotor's top speed — the header's arithmetic, read
	# back off the bus rather than restated.
	var hover_frac := sqrt(r.drone.mass * 9.8 / r.drone.max_thrust)
	assert_int(settled).is_equal(int(round(hover_frac * Prop.ROTOR_MAX_RPM)))


# --- the pack --------------------------------------------------------------------------------

## `soc` coulomb-counts and only ever falls, and the terminal voltage is the OCV curve less the IR
## drop — so a punch-out visibly sags the volts against a hover. `battery` is the SHARED contract
## signal, overwritten here after the base wrote its alternator model into it.
func test_the_pack_drains_monotonically_and_the_volts_sag_under_load() -> void:
	var r: Rig = await _flying()
	r.seconds(1.0)
	var hover_v := r.t.battery
	var hover_a := r.t.pack_current
	var soc_at_hover := r.t.soc
	r.input.climb = 1.0                                 # full up stick
	r.seconds(1.0)
	assert_float(r.t.pack_current).is_greater(hover_a)
	assert_float(r.t.battery).is_less(hover_v)          # sags under the bigger draw
	assert_float(r.t.soc).is_less(soc_at_hover)
	# Monotonic across the whole run, whatever the stick does.
	var prev := r.t.soc
	for i in 60:
		r.input.climb = -1.0 if i % 2 == 0 else 1.0
		r.tick()
		assert_float(r.t.soc).is_less_equal(prev)
		prev = r.t.soc
	assert_float(r.t.pack_temp).is_greater(Power.PACK_AMBIENT)


# --- the cargo hook --------------------------------------------------------------------------

## The hook is a real mass change, and this is the case that says the crate's mass reaches the
## RigidBody3D. Commanding HOLD over open ground leaves the latch OPEN — the `arm`/`armed`
## relationship again — and releasing needs no condition at all, which is the asymmetry a real
## cargo hook has: the failure you must never have is a load you cannot drop.
func test_the_hook_latches_only_over_a_payload_and_the_craft_really_gets_heavier() -> void:
	var r: Rig = await _rig(Vector3(0.0, 1.5, 0.0), 0.0)
	r.tick(4)
	var empty_mass := r.drone.mass
	var empty_com := r.drone.center_of_mass
	# HOLD with nothing under the hook: refused, and nothing about the aircraft moves.
	r.input.hardpoint_cmd = true
	r.tick(2)
	assert_bool(r.t.hardpoint_state).is_false()
	assert_float(r.drone.mass).is_equal_approx(empty_mass, 1e-4)
	assert_float(r.t.payload_weight).is_equal_approx(0.0, 1e-4)
	# ...now put a crate under it. Same command, and this time the latch closes.
	var crate: CargoPayload = await _crate(r, Vector3(0.0, 0.0, 0.0))
	r.tick(2)
	assert_bool(r.t.hardpoint_state).is_true()
	assert_float(r.drone.mass).is_equal_approx(empty_mass + crate.mass, 1e-3)
	assert_float(r.t.payload_weight).is_greater(0.0)
	# The centre of mass moved TOWARD the hook, which hangs below the body.
	assert_float(r.drone.center_of_mass.y).is_less(empty_com.y)
	# Release: no condition, no timer, and the aircraft is its own weight again.
	r.input.hardpoint_cmd = false
	r.tick(2)
	assert_bool(r.t.hardpoint_state).is_false()
	assert_float(r.drone.mass).is_equal_approx(empty_mass, 1e-4)
	assert_float(r.t.payload_weight).is_equal_approx(0.0, 1e-4)


# --- the gimbal ------------------------------------------------------------------------------

## The mount SLEWS at its own rate and stops at the CONTRACT's own range — the travel and the
## signal range are one number, read off `gimbal_pitch` / `gimbal_yaw` at _ready. Published as
## where it HAS reached, never as what was asked for.
func test_the_gimbal_slews_at_its_rate_and_stops_at_the_contract_travel() -> void:
	var pitch_def: RefCounted = Contract.data.get_signal_def("gimbal_pitch", "in")
	var yaw_def: RefCounted = Contract.data.get_signal_def("gimbal_yaw", "in")
	assert_object(pitch_def).is_not_null()
	assert_object(yaw_def).is_not_null()
	var r: Rig = await _flying()
	assert_float(r.t.gimbal_pitch_actual).is_equal_approx(Gimbal.REST_PITCH, 1e-4)
	# One tick of a full-travel command moves exactly one tick's worth of slew, not the whole way.
	r.input.gimbal_pitch = 1000.0
	r.input.gimbal_yaw = -1000.0
	r.tick()
	assert_float(r.t.gimbal_pitch_actual) \
			.is_equal_approx(Gimbal.REST_PITCH + Gimbal.SLEW_DEG_S * DELTA, 1e-4)
	assert_float(r.t.gimbal_yaw_actual) \
			.is_equal_approx(Gimbal.REST_YAW - Gimbal.SLEW_DEG_S * DELTA, 1e-4)
	# ...and it walks to the STOP and stays there, however far past it the command reaches.
	r.seconds(10.0)
	assert_float(r.t.gimbal_pitch_actual).is_equal_approx(float(pitch_def.range[1]), 1e-4)
	assert_float(r.t.gimbal_yaw_actual).is_equal_approx(float(yaw_def.range[0]), 1e-4)


# --- LAND ------------------------------------------------------------------------------------

## Land's touchdown cut is all four commands, not just the collective. `mix_quad_x` clamps the sum
## per motor, so a zero collective with an attitude demand on top still drives two of them and a
## craft landed on a slope sits there fighting the ground. Observable exactly where it matters: on
## the bus, every rotor goes to zero — and the craft is LEANED here so the levelling loop really
## does have an attitude demand to spend.
func test_lands_touchdown_cut_stops_all_four_motors() -> void:
	var r: Rig = await _rig(Vector3(0.0, 0.3, 0.0), 0.0)
	r.tick(FIX_TICKS)
	r.arm()
	var xform := r.drone.global_transform
	xform.basis = Basis(Vector3.RIGHT, deg_to_rad(8.0))
	r.drone.global_transform = xform
	r.input.flight_mode = Modes.LAND
	r.seconds(1.0)
	assert_bool(r.t.ground).is_true()
	assert_int(r.t.mode_actual).is_equal(Modes.LAND)
	r.seconds(1.0)                                   # let the spool-down finish
	assert_int(r.t.rotor_rpm).is_equal(0)
	for i in r.t.esc_rpm.size():
		assert_int(int(r.t.esc_rpm[i])) \
				.override_failure_message("esc %d still turning after the LAND cut" % i) \
				.is_equal(0)


# --- respawn ---------------------------------------------------------------------------------

## A respawn hands you a FRESH AIRCRAFT: full pack, cleared held telemetry, a reacquiring
## receiver, home here, and disarmed. What it deliberately does NOT clear is `node_fail` — that is
## an INPUT, a bench switch someone flipped, and clearing it here would be a side channel writing
## over what sloppyCAN is saying.
func test_respawn_hands_back_a_fresh_aircraft_but_not_the_bench_switch() -> void:
	var r: Rig = await _flying()
	r.input.node_fail = 1 << 0                       # ESC1 off the bus, with held telemetry
	r.seconds(3.0)
	assert_float(r.t.soc).is_less(100.0)
	assert_int(int(r.t.esc_rpm[0])).is_greater(0)    # frozen at its last value
	assert_bool(r.t.armed).is_true()
	r.drone.respawn()
	r.tick()
	# The pack is REPLACED, not just cooled — an empty pack stops the motors, so carrying one
	# across a respawn would leave the craft permanently unflyable with no way back.
	assert_float(r.t.soc).is_greater(99.0)
	# The held ESC telemetry is history in the same sense the accel history is, and goes with it.
	assert_int(int(r.t.esc_rpm[0])).is_equal(0)
	assert_bool(r.t.armed).is_false()
	assert_int(r.t.failsafe).is_equal(Arming.FS_MOTOR)   # still true: the node is still off the bus
	assert_int(r.t.node_online & 1).is_equal(0)          # the switch survived, exactly as designed
	# The receiver REACQUIRES rather than arriving with a fix it earned somewhere else.
	assert_int(r.t.sats).is_less(Sensors.SKY_RAYS)
