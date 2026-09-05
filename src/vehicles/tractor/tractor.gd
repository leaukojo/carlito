class_name TractorVehicle
extends BaseVehicle
## Tractor. Owns the hitch position, PTO and current implement or trailer state on top of
## BaseVehicle, through the two seams only, and puts its own draft force on the chassis in
## _tick_extras. It also tows via the drawbar, the same TowHost class as the semi's fifth wheel;
## the linkage and the drawbar share one E cycle and are never both loaded at once.

const SPAWN_HITCH := 1.0                ## spawn default: raised (transport), PTO off

## Splat channel 4 ("Field") is the only honest "in soil" predicate for draft force, not Dirt
## (channel 1), which auto-splat paints on every slope. It lives in splatmap2, which auto-splat
## only zeroes, so an unpainted level reads "no soil" everywhere.
const SOIL_CHANNEL := 4

@export var hitch_travel_time := 1.5   ## s for a full raise or lower
@export var pto_load := 0.35           ## engine_load added while PTO engaged
## Rated draft (N): the pull of a draft-relevant implement at full depth at DRAFT_SPEED_REF, and
## the 100% end of 'draft_force'. 12 kN is a real 3-furrow plough figure, which the tractor lugs
## and slips against rather than stalling.
@export var draft_max_force := 12000.0
@export var hitch_path: NodePath = ^"ThreePointHitch"
@export var drawbar_path: NodePath = ^"Drawbar"

var _hitch_actual := SPAWN_HITCH       ## 0..1, chases input.hitch_request
var _hitch: ThreePointHitch
var _drawbar: TowHost
var _implement_id := ImplementCatalog.DETACHED  ## current entry in the E cycle


func _make_telemetry() -> VehicleTelemetry:
	return TractorTelemetry.new()


func _ready() -> void:
	super._ready()
	_hitch = get_node_or_null(hitch_path) as ThreePointHitch
	_drawbar = get_node_or_null(drawbar_path) as TowHost
	# Spawn with an implement on the linkage so hitch/PTO are visible from frame one.
	_set_implement(ImplementCatalog.first())


## Advance to the next E-cycle entry, DETACHED included. Refuses only for a towed entry while
## moving, since a trailer must be laid at a pose the tractor has not already left.
func cycle_implement() -> void:
	var next_id := ImplementCatalog.next(_implement_id)
	if TowHost.may_cycle_to(_drawbar, next_id, ImplementCatalog.is_towed, telemetry.speed):
		set_attachment(next_id)


## The attachment axis as data, mirroring SemiTractor's trailer answers, for the selector UI.
## DETACHED is a real entry, as in the cycle.
func attachment_ids() -> PackedStringArray:
	return ImplementCatalog.IMPLEMENTS


func current_attachment() -> String:
	return _implement_id


func set_attachment(id: String) -> void:
	_set_implement(id)


## Which attachment controls are live right now, for the touch overlay. PTO and SCV read the
## attached machine's own declaration, the same one the coupling gates real drive and flow on;
## LIFT is always true, since the three-point linkage is tractor anatomy and works empty.
func attachment_controls() -> Dictionary:
	var conn := _attachment_connections()
	return {
		"pto": (conn & int(ImplementBase.Connection.PTO)) != 0,
		"scv": (conn & int(ImplementBase.Connection.SCV)) != 0,
		"lift": true,
	}


## Garage showroom hook, forwarded to the coupling, which owns the freeze and its fit-check
## exemption.
func set_display_frozen(frozen: bool) -> void:
	if _drawbar != null:
		_drawbar.set_display_frozen(frozen)


## Whatever is attached right now, on either end. One cycle means one machine at a time.
func _attachment() -> Node:
	if _hitch != null and _hitch.implement != null:
		return _hitch.implement
	if _drawbar != null and _drawbar.is_coupled():
		return _drawbar.trailer
	return null


## What the attached machine declares, 0 or CLASS_NONE with nothing attached. Duck-typed, since
## an ImplementBase and a TowedBody share no base class on purpose. The `has_method` guards are
## there because TowedBody defines neither method by default, so a second towed entry without them
## would silently read zero instead of erroring; _verify_towed_declares catches that at hitch time.
func _attachment_connections() -> int:
	var node := _attachment()
	if node == null or not node.has_method(&"connections"):
		return 0
	return int(node.call(&"connections"))


func _attachment_device_class() -> int:
	var node := _attachment()
	if node == null or not node.has_method(&"device_class"):
		return ImplementBase.CLASS_NONE
	return int(node.call(&"device_class"))


## A towed attachment must be able to answer what it declares, checked once here while it is
## still nameable.
func _verify_towed_declares(node: Node) -> void:
	for method: StringName in [&"connections", &"device_class"]:
		if not node.has_method(method):
			push_error("%s: '%s' declares no %s() — it cannot say what it plugs into"
					% [name, _implement_id, method])


## Put `id` on the linkage or the drawbar, whichever ImplementCatalog routes it to, or clear both
## for DETACHED. An implement attach is a logical ISOBUS address claim with no cable, while a
## trailer is a real coupling. The other end is always emptied first.
func _set_implement(id: String) -> void:
	_implement_id = id
	var towed := ImplementCatalog.is_towed(id)
	if _hitch != null:
		if ImplementCatalog.is_attached(id) and not towed:
			_hitch.attach(load(id) as PackedScene)
		else:
			_hitch.detach()
		# Re-pose either way: the linkage is tractor anatomy and works empty.
		_hitch.set_hitch(_hitch_actual)
	if _drawbar == null:
		return
	if not towed:
		_drawbar.uncouple()
		return
	# No real spawn transform exists before the countdown runs, so the id stays remembered and
	# the host asks for it back.
	if not _drawbar.spawn_ready():
		_drawbar.uncouple()
		return
	if not _drawbar.couple(load(id) as PackedScene):
		# Nothing coupled, so current_attachment() must not report a trailer never laid.
		_implement_id = ImplementCatalog.DETACHED
		return
	_verify_towed_declares(_drawbar.trailer)


## Called by TowHost once the spawn countdown finishes and a real transform exists, so a
## remembered towed id can be laid. Only a towed id matters: re-running the setter for an implement
## would detach and re-instance one already attached since _ready.
func attachment_spawn_ready() -> void:
	if ImplementCatalog.is_towed(_implement_id):
		_set_implement(_implement_id)


## The fit check took the trailer away, having laid it inside the world. The id must follow, or
## current_attachment() reports a trailer no longer on the pin.
func attachment_refused() -> void:
	_set_implement(ImplementCatalog.DETACHED)


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as TractorTelemetry
	var running := input.key == InputRouter.KEY_IGNITION
	_hitch_actual = move_toward(_hitch_actual, input.hitch_request, delta / hitch_travel_time)
	var pto_on := input.pto and running
	t.hitch_pos_actual = roundi(_hitch_actual * 100.0)
	t.pto_state = pto_on
	# 540/1000 select a gearbox ratio off the engine; the engine itself is never re-targeted.
	t.pto_rpm = TractorTelemetry.pto_shaft_rpm(drivetrain.rpm, input.pto_mode) if pto_on else 0
	# Governed throttle, not the pedal (see Drivetrain.applied_throttle).
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, drivetrain.applied_throttle, spec, pto_on, pto_load))
	# Driveline state read out of the sim, not echoed from request bits.
	t.diff_lock_state = rear_diff_locked
	t.fwd_drive_state = _front_axle_driven()
	# ISOBUS wheel-based and ground-based speed pair, both this tick's; the difference is slip.
	t.wheel_speed = TractorTelemetry.wheel_kmh(
			_drive_axle_omega(), spec.ground_drive.wheel_radius)
	t.ground_speed = absf(t.speed) * 3.6
	t.wheel_slip = roundi(TractorTelemetry.slip_pct(t.wheel_speed, t.ground_speed))
	# implement_connected and type report the address claim (ISOBUS_DATA), not the steel: a
	# machine attached while declaring no bus address is mechanically attached and electronically
	# silent, which the shipped drawbar trailer is. Reads whichever end is loaded.
	var implement: ImplementBase = _hitch.implement if _hitch != null else null
	var on_bus := (_attachment_connections() & int(ImplementBase.Connection.ISOBUS_DATA)) != 0
	t.implement_connected = on_bus
	t.implement_type = _attachment_device_class() if on_bus else ImplementBase.CLASS_NONE
	# Hydraulic remote for both ends; pump is engine-driven so a stopped engine gives no flow.
	var spool := clampf(input.scv_flow, 0.0, 1.0) if running else 0.0
	# Pose the linkage before the draft force reads it, since ball_lift() and hitch_point() come
	# from the same four-bar solve set_hitch runs; posing after would use last tick's geometry.
	if _hitch != null:
		_hitch.set_hitch(_hitch_actual)
		_hitch.set_pto(pto_on, t.pto_rpm)
		_hitch.set_scv(spool)
	# Towing: brake demand is the plain foot brake, with no retarder blend since a tractor has
	# none. The trailer brakes regardless, because hoses are not a data bus.
	if _drawbar != null:
		_drawbar.tick_towing(input, input.brake, spool, pto_on, t.pto_rpm,
				telemetry.speed, delta, _grip_terrains)
	# Draft force on the chassis while the linkage works in soil. Nothing above reacts to it, since
	# engine_load and wheel_slip already reflect the sag and pull from prior ticks.
	t.draft_force = roundi(TractorTelemetry.draft_pct(
			_apply_draft(implement, t.speed, delta), draft_max_force))


## Apply this tick's draft force to the chassis and return it (N, signed along forward), or 0
## unless a draft-relevant implement is down in painted soil.
func _apply_draft(implement: ImplementBase, v_fwd: float, delta: float) -> float:
	if _hitch == null or implement == null or not implement.draft_relevant():
		return 0.0
	# Working depth is the implement's own declared reach (plough 0.055 m, harrow tines 0.02 m); a
	# shared constant had the harrow reporting draft with its tines visibly in the air.
	var depth01 := TractorTelemetry.draft_depth01(
			_hitch.ball_lift(), implement.tool_depth())
	if depth01 <= 0.0:
		return 0.0
	var point := _hitch.hitch_point()
	var soil01 := _soil_at(point)
	if soil01 <= 0.0:
		return 0.0
	var force := TractorTelemetry.draft_newtons(
			v_fwd, depth01, soil01, draft_max_force, mass, delta)
	# Applied at the hitch point (y ~0.21), below the centre of mass (y = 0.35), so this force's
	# own moment is nose-down. The net nose-up transfer comes from the tires' answering drive
	# force at ground level, a longer arm below the same centre of mass.
	apply_force(-global_transform.basis.z * force, point - global_position)
	return force


## Ploughable-soil weight under `point`, 0..1. Reuses the wheels' terrain pick and the cached
## splat Images; no terrain painted means no soil.
func _soil_at(point: Vector3) -> float:
	var terrain := RayWheel.terrain_at(point, _grip_terrains)
	if terrain == null or not terrain.has_method("channel_weight_at"):
		return 0.0
	return terrain.channel_weight_at(point, SOIL_CHANNEL)


## Mean spin of the rear axle (rad/s). Always driven, unlike the front, which changes with MFWD,
## and the axle that digs in, so it is what wheel_slip measures.
func _drive_axle_omega() -> float:
	var total := 0.0
	var count := 0
	for w in wheels:
		if w.is_rear:
			total += w.omega
			count += 1
	return total / count if count > 0 else 0.0


## Whether the front axle is really taking drive right now (MFWD engaged).
func _front_axle_driven() -> bool:
	for w in wheels:
		if not w.is_rear:
			return w.driven
	return false


## Re-raise the implement on respawn. A respawn moves the tractor rather than rebuilding it, so
## whatever is attached survives.
func respawn() -> void:
	super.respawn()
	_hitch_actual = SPAWN_HITCH
	if _drawbar != null:
		_drawbar.respawn_relay(spawn_transform)


## The trailer is a separate body, so its RID goes in beside this one's or the camera sees
## through the combination.
func get_camera_exclude_bodies() -> Array[RID]:
	var out := super.get_camera_exclude_bodies()
	if _drawbar != null:
		_drawbar.camera_exclude_into(out)
	return out


## Framed like the up-to-seven-metre combination even with the trailer dropped, so the camera
## never jumps on an E press.
func get_camera_framing() -> Dictionary:
	return {"distance": 10.0, "height": 5.0, "look_height": 1.8, "top_height": 36.0, "iso_size": 38.0}


## Articulation angle (rad, + = trailer to the right); 0 with nothing towed. Read by the F3
## overlay, as on SemiTractor.
func articulation() -> float:
	return _drawbar.articulation() if _drawbar != null else 0.0
