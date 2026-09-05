class_name TowHost
extends Node3D
## The towing side of a two-body rig, shared by the fifth wheel and the drawbar: the coupling
## datum, the Generic6DOFJoint3D, and all two-body housekeeping. The two couplings differ only by
## a CouplingProfile.
##
## A node on the chassis, reached via get_parent(). What reaches the towed body is gated here,
## never in the towed subclass. Two duck-typed hooks reach back: `attachment_spawn_ready()` and
## `attachment_refused()`.

## Ticks after spawn before a remembered attachment is coupled. A plain countdown, not a
## condition, so it always finishes; coupling on tick one lays the body 0.16 m into the terrain.
const SPAWN_COUPLE_TICKS := 12

## Ticks a freshly coupled body is watched for a body contact, which means it does not fit: a
## towed body rides RayWheels, so it normally touches nothing. Later contacts are ordinary driving.
const COUPLE_WATCH_TICKS := 8

## Road speed (m/s) below which the attachment cycle will couple. Same figure as
## TowedBody.RAISE_SPEED_MS on purpose — both mean "the rig is stopped".
const COUPLE_SPEED_MS := TowedBody.RAISE_SPEED_MS

## How long the interlock notice stays up.
const TIP_NOTICE_DWELL_S := 5.0

var trailer: TowedBody = null  ## null while nothing is coupled

var _marker_local := Vector3.ZERO
var _joint: Generic6DOFJoint3D = null
## Has the spawn coupling been made? Level._spawn_vehicle assigns global_transform after
## add_child, so _ready (and set_attachment, same frame) is too early to lay a body anywhere.
var _coupled_once := false
var _spawn_ticks := 0    ## ticks since spawn, against SPAWN_COUPLE_TICKS — counted unconditionally
var _couple_watch := 0   ## ticks left in which a fresh coupling is watched for a body contact
var _display_frozen := false  ## the showroom has this rig pinned (see set_display_frozen)
var _last_tip_cmd := -1.0     ## last spool position, so the interlock notice fires on the edge


# --- what a subclass declares -------------------------------------------------------------------


## This coupling's profile. A method, not a member initialiser: a test builds a joint off a host
## that never ran _ready, where an assigned profile would be null.
func profile() -> CouplingProfile:
	push_error("%s: no CouplingProfile — TowHost.profile() must be overridden" % name)
	return CouplingProfile.new()


## The coupling datum in the chassis' frame when no marker is authored; _ready reads the real one.
func default_marker_local() -> Vector3:
	return Vector3.ZERO


func _ready() -> void:
	_marker_local = default_marker_local()
	var path := profile().marker_path
	var marker := get_node_or_null(path) as Node3D
	if marker == null:
		push_error("%s: no coupling marker at %s — falling back to the authored default"
				% [name, path])
		return
	# Through this node's own transform, so an offset-instanced coupler still reports the datum
	# in the chassis' frame, which is the frame the joint is positioned in.
	_marker_local = transform * marker.position


func _exit_tree() -> void:
	# The towed body is a child of the level, not the chassis, so nothing else frees it.
	uncouple(false)


# --- the coupling datum -------------------------------------------------------------------------


## The coupling datum in the chassis' own frame: the joint's anchor, and where an origin is laid.
func marker_local() -> Vector3:
	return _marker_local


## Where a towed body's origin belongs, given the chassis' pose. It inherits the whole basis.
func coupled_pose(chassis: Transform3D) -> Transform3D:
	return Articulation.coupled_pose(chassis, _marker_local)


func is_coupled() -> bool:
	return is_instance_valid(trailer)


## Has a real spawn transform existed yet? Until it has, a towed id is remembered, not coupled.
func spawn_ready() -> bool:
	return _coupled_once


## Articulation angle (rad, + = towed body to the right); 0 with nothing coupled. F3 reads it.
func articulation() -> float:
	var chassis := _chassis()
	if chassis == null or not is_instance_valid(trailer):
		return 0.0
	return Articulation.articulation_angle(chassis.global_transform, trailer.global_transform)


# --- coupling -----------------------------------------------------------------------------------


## The attachment cycle's gate, and the whole of what the semi and the tractor share about it:
## `next_id` is refused only when `needs_coupler` calls it a coupling AND this host will not take a
## body at `speed_ms`. Dropping one is never refused, since nothing is laid. Static because a
## vehicle may have no coupler node at all, and the predicate is passed in rather than read, so
## this knows neither trailers nor implements.
static func may_cycle_to(host: TowHost, next_id: String, needs_coupler: Callable,
		speed_ms: float) -> bool:
	if not bool(needs_coupler.call(next_id)):
		return true
	return host == null or host.may_couple(speed_ms)


## May the attachment cycle couple at this road speed? See COUPLE_SPEED_MS.
func may_couple(speed_ms: float) -> bool:
	if absf(speed_ms) <= COUPLE_SPEED_MS:
		return true
	GameState.notice.emit(profile().speed_notice, 0.0)
	return false


## Couple `scene` on this coupling. Returns true if something is now on the back. The body becomes
## a child of the chassis' parent (the level), never the chassis: a RigidBody3D under another body
## gets the parent's transform double-applied. Fit is decided afterward by _watch_fresh_coupling.
func couple(scene: PackedScene) -> bool:
	var chassis := _chassis()
	var host := chassis.get_parent() if chassis != null else null
	if scene == null or chassis == null or host == null:
		uncouple()
		return false
	var instance := scene.instantiate()
	var candidate := instance as TowedBody
	if candidate == null:
		push_error("%s: '%s' is not a TowedBody" % [name, scene.resource_path])
		# The node was already built; nothing else holds it, so free it explicitly.
		instance.free()
		uncouple()
		return false
	var pose := coupled_pose(chassis.global_transform)
	uncouple()
	trailer = candidate
	host.add_child(trailer)
	trailer.global_transform = pose
	# Match velocity to the towing unit before the joint exists, treating the pair as one rigid
	# body for that instant. Otherwise the solver gets tens of tonnes with the whole road speed as
	# relative velocity, an impulse big enough to throw the towing unit.
	var lever := trailer.global_transform * trailer.center_of_mass \
			- chassis.global_transform * chassis.center_of_mass
	trailer.linear_velocity = chassis.linear_velocity + chassis.angular_velocity.cross(lever)
	trailer.angular_velocity = chassis.angular_velocity
	trailer.reset_physics_interpolation()
	_joint = _build_joint()
	chassis.add_child(_joint)
	# Bound last: assigning the bodies is what makes Jolt build the constraint, and it reads the
	# joint's global transform for the frames, so the joint must already be in the tree, at the
	# datum, with both bodies posed.
	_joint.node_a = _joint.get_path_to(chassis)
	_joint.node_b = _joint.get_path_to(trailer)
	_couple_watch = COUPLE_WATCH_TICKS
	# A body coupled while the showroom has the rig pinned is pinned with it too.
	_apply_display_freeze()
	return true


## Uncouple: joint first, then the towed body, both leaving the tree synchronously — `queue_free`
## alone defers to end of frame and a swap in the meantime leaves two jointed bodies at one pose.
## `unparent` false is the teardown path, since `remove_child` fails mid-`_exit_tree`.
func uncouple(unparent := true) -> void:
	if is_instance_valid(_joint):
		if unparent:
			_unparent(_joint)
		_joint.queue_free()
	_joint = null
	if is_instance_valid(trailer):
		if unparent:
			_unparent(trailer)
		trailer.queue_free()
	trailer = null
	_couple_watch = 0
	_restart_tip_latch()


static func _unparent(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)


## The coupling itself: child of the chassis at the datum, unrotated, so the joint axes are the
## towing unit's (X pitch, Y yaw, Z roll). Linear axes locked, angular stops from the profile.
## `exclude_nodes_from_collision` stays true: coupling and trailer nose overlap by design.
func _build_joint() -> Generic6DOFJoint3D:
	var p := profile()
	var j := Generic6DOFJoint3D.new()
	j.name = String(p.joint_name)
	j.position = _marker_local
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(p.pitch_deg))
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(p.pitch_deg))
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(p.yaw_deg))
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(p.yaw_deg))
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(p.roll_deg))
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(p.roll_deg))
	return j


func _chassis() -> RigidBody3D:
	return get_parent() as RigidBody3D


# --- the showroom, respawn, the camera ----------------------------------------------------------


## The garage showroom hook (duck-typed by garage.gd). The showroom pins and hovers the vehicle,
## so a towed body freezes with it and is exempt from the fit check.
func set_display_frozen(frozen: bool) -> void:
	_display_frozen = frozen
	_apply_display_freeze()


func _apply_display_freeze() -> void:
	if not is_instance_valid(trailer):
		return
	trailer.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	trailer.freeze = _display_frozen


## Re-lay the towed half of a respawn: the body goes back to its coupled pose and stops, since
## zeroing velocity alone leaves it wherever it drifted to. TowedBody.reset_at also clears its
## wheel state, which a RayWheel would otherwise report as a suspension spike after the teleport.
func respawn_relay(pose: Transform3D) -> void:
	# A re-laid body isn't a fresh coupling; the fit check must not fire on the teleport.
	_couple_watch = 0
	if is_instance_valid(trailer):
		trailer.reset_at(coupled_pose(pose))


## The chase camera must not see through the combination: the towed body's RID goes in beside the
## chassis', or the pull-in slams the camera into the trailer's headboard.
func camera_exclude_into(out: Array[RID]) -> void:
	if is_instance_valid(trailer):
		out.append(trailer.get_rid())


# --- the per-tick towing side -------------------------------------------------------------------


## Everything the towing side does in a physics tick, handed the numbers the vehicle computed.
##
## The spawn countdown must not `return` early out of the rest, or a body coupled with E during
## the wait hangs off the joint with dead wheels. tick_towed runs last so a caller publishing
## wheel-derived state this tick (ISO 11992 axle load / ABS) gets current numbers.
func tick_towing(input: VehicleInput, demand01: float, spool: float,
		pto_on: bool, pto_rpm: int, speed_ms: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	_spawn_ticks += 1
	if not _coupled_once and _spawn_ticks >= SPAWN_COUPLE_TICKS:
		_coupled_once = true
		var ready_chassis := _chassis()
		if ready_chassis != null and ready_chassis.has_method(&"attachment_spawn_ready"):
			ready_chassis.call(&"attachment_spawn_ready")
	if not is_instance_valid(trailer):
		return

	# Gated: only a body declaring Consumer.PTO sees drive, and rpm is the towing unit's own.
	var driven := trailer.uses(TowedBody.Consumer.PTO)
	trailer.set_pto(pto_on and driven, pto_rpm if driven else 0)

	# The valve needs Consumer.HYDRAULIC, and if PTO-turned, PTO engaged too. The raise interlock
	# (TowedBody.body_raise_allowed) refuses the raise direction only: rolling away with the body
	# up must hold it, never drop it, so lowering is always allowed.
	var plumbed := trailer.uses(TowedBody.Consumer.HYDRAULIC)
	var cmd := clampf(spool, 0.0, 1.0)
	_warn_if_tip_interlocked(cmd, plumbed, input.handbrake, pto_on)
	if not TowedBody.body_raise_allowed(speed_ms, input.handbrake):
		cmd = minf(cmd, trailer.body_pos01())
	trailer.set_valve(cmd if plumbed and (not driven or pto_on) else 0.0)

	# The towed body's lamps, off the bits the chassis just lit its own with. Not physics, so it
	# runs even while frozen for the showroom.
	trailer.apply_lamps(input.lamps.brake_lamp, input.lights,
			input.lamps.turn_left, input.lamps.turn_right)
	# Ticked here, not from the towed body's own _physics_process: one tick per physics frame,
	# always after the chassis' own wheels. The handbrake applies the spring brakes at both ends.
	trailer.tick_towed(demand01, input.handbrake, delta, grip_terrains)

	# The base only watches the chassis fall off the world; a towed body left behind would
	# otherwise hang there on the joint. Guarded on is_inside_tree(): a body outside the tree has
	# no global transform, so the engine hands back Transform3D(), an origin that reads here as
	# "at y=0" rather than "no answer".
	if trailer.is_inside_tree() and trailer.global_position.y < BaseVehicle.FALL_RESPAWN_Y:
		var fallen_chassis := _chassis()
		if fallen_chassis != null and fallen_chassis.has_method(&"respawn"):
			fallen_chassis.call(&"respawn")
		return
	_watch_fresh_coupling()


## Did what we just coupled actually fit? A towed body rides RayWheels, so a contact right after
## coupling means it was laid inside the world; the showroom is exempt. The vehicle is told, so
## its attachment catalog stops claiming a body that is no longer there.
func _watch_fresh_coupling() -> void:
	if _couple_watch <= 0 or _display_frozen:
		return
	_couple_watch -= 1
	if not is_instance_valid(trailer) or not trailer.body_is_colliding():
		return
	var chassis := _chassis()
	if chassis != null and chassis.has_method(&"attachment_refused"):
		chassis.call(&"attachment_refused")
	uncouple()
	# Nobody pressed E for this one, so tell the shell the attachment moved, or the touch overlay
	# keeps offering PTO/TIP buttons for a body that is no longer there.
	GameState.attachment_changed.emit()
	GameState.notice.emit(profile().no_room_notice, 0.0)


## Say why the tip command did nothing: only on a press asking the body up, on a plumbed body.
## Road speed is left out of the reason since the driver already has to be stopped.
func _warn_if_tip_interlocked(cmd: float, plumbed: bool, handbrake: float, pto_on: bool) -> void:
	var edge := not is_equal_approx(cmd, _last_tip_cmd) and _last_tip_cmd >= 0.0
	_last_tip_cmd = cmd
	if not edge or not plumbed or not is_instance_valid(trailer) or cmd <= trailer.body_pos01():
		return
	if (not trailer.uses(TowedBody.Consumer.PTO) or pto_on) \
			and handbrake >= TowedBody.RAISE_PARK_BRAKE_MIN:
		return
	GameState.notice.emit(profile().tip_notice, TIP_NOTICE_DWELL_S)


## The interlock notice fires on a change of spool position, so a couple/uncouple restarts the
## latch, or the first refused press after a new coupling reads as "no edge" and says nothing.
func _restart_tip_latch() -> void:
	_last_tip_cmd = -1.0
