class_name TractorVehicle
extends BaseVehicle
## Tractor. Owns the hitch position, PTO and current implement or trailer state on top of
## BaseVehicle, through the two seams only, and puts its own draft force on the chassis in
## _tick_extras. It also tows via the drawbar, the same TowHost class as the semi's fifth wheel;
## the linkage and the drawbar share one E cycle and are never both loaded at once.

const SPAWN_HITCH := 1.0                ## spawn default: raised (transport), PTO off

## Splat channel 4 ("Field") is the "in soil" predicate for draft, not Dirt (channel 1), which
## auto-splat paints on every slope. Auto-splat only zeroes splatmap2, so an unpainted level reads
## "no soil" everywhere.
const SOIL_CHANNEL := 4

@export var hitch_travel_time := 1.5   ## s for a full raise or lower
@export var pto_load := 0.35           ## engine_load added while PTO engaged
## The 100% end of 'draft_force' (N): the plough's `draft_rating()`, so the plough at full depth on
## full soil at `TractorTelemetry.DRAFT_S_REF_KMH` reads 100 %. Each implement pulls its own rating.
@export var draft_max_force := 22410.0
@export var hitch_path: NodePath = ^"ThreePointHitch"
@export var drawbar_path: NodePath = ^"Drawbar"

## N along forward, this tick's draft force; unclamped, where `draft_force` stops at 100 %.
var draft_applied := 0.0
var _hitch_actual := SPAWN_HITCH       ## 0..1, chases input.hitch_request
var _hitch: ThreePointHitch
var _drawbar: TowHost
var _implement_id := ImplementCatalog.DETACHED  ## current entry in the E cycle
var _carried_applied := 0.0            ## implement kg currently written into `mass`
var _com_applied := Vector3.ZERO       ## the COM written with it (the spec's from _ready)


func _make_telemetry() -> VehicleTelemetry:
	return TractorTelemetry.new()


func _ready() -> void:
	super._ready()
	_hitch = get_node_or_null(hitch_path) as ThreePointHitch
	_drawbar = get_node_or_null(drawbar_path) as TowHost
	# The base wrote spec mass and COM: a bare tractor never writes them again.
	_com_applied = spec.center_of_mass
	# Spawn with an implement on the linkage.
	_set_implement(ImplementCatalog.first())


## Advance to the next E-cycle entry, DETACHED included. Refuses a towed entry while moving: a
## trailer must be laid at a pose the tractor has not already left.
func cycle_implement() -> void:
	var next_id := ImplementCatalog.next(_implement_id)
	if TowHost.may_cycle_to(_drawbar, next_id, ImplementCatalog.is_towed, telemetry.speed):
		set_attachment(next_id)


## The attachment axis as data for the selector UI, mirroring SemiTractor's trailer answers.
## DETACHED is a real entry.
func attachment_ids() -> PackedStringArray:
	return ImplementCatalog.IMPLEMENTS


func current_attachment() -> String:
	return _implement_id


func set_attachment(id: String) -> void:
	_set_implement(id)


## Which attachment controls are live right now, for the touch overlay. PTO and SCV follow the
## attached machine's own declaration; LIFT is always true (the linkage works empty).
func attachment_controls() -> Dictionary:
	var conn := _attachment_connections()
	return {
		"pto": (conn & int(ImplementBase.Connection.PTO)) != 0,
		"scv": (conn & int(ImplementBase.Connection.SCV)) != 0,
		"lift": true,
	}


## Garage showroom hook; the coupling owns the freeze and its fit-check exemption.
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


## What the attached machine declares, 0 or CLASS_NONE with nothing attached. Duck-typed: an
## ImplementBase and a TowedBody share no base class on purpose. TowedBody defines neither method
## by default, so a towed entry that omits one reads zero; _verify_towed_declares catches that.
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


## A towed attachment must answer `connections` and `device_class`; checked once at attach.
func _verify_towed_declares(node: Node) -> void:
	for method: StringName in [&"connections", &"device_class"]:
		if not node.has_method(method):
			push_error("%s: '%s' declares no %s() — it cannot say what it plugs into"
					% [name, _implement_id, method])


## Put `id` on the linkage or the drawbar, whichever ImplementCatalog routes it to, or clear both
## for DETACHED. The other end is always emptied first.
func _set_implement(id: String) -> void:
	_implement_id = id
	var towed := ImplementCatalog.is_towed(id)
	if _hitch != null:
		if ImplementCatalog.is_attached(id) and not towed:
			_hitch.attach(load(id) as PackedScene)
		else:
			_hitch.detach()
		# Re-pose either way: the linkage works empty.
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


## Called by TowHost once the spawn countdown finishes, so a remembered towed id can be laid. Only
## a towed id matters: re-running the setter for an implement would re-instance it.
func attachment_spawn_ready() -> void:
	if ImplementCatalog.is_towed(_implement_id):
		_set_implement(_implement_id)


## The fit check took the trailer away; the id follows, or current_attachment() reports a trailer
## no longer on the pin.
func attachment_refused() -> void:
	_set_implement(ImplementCatalog.DETACHED)


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as TractorTelemetry
	var running := input.key == InputRouter.KEY_IGNITION
	_hitch_actual = move_toward(_hitch_actual, input.hitch_request, delta / maxf(hitch_travel_time, 0.01))
	var pto_on := input.pto and running
	t.hitch_pos_actual = roundi(_hitch_actual * 100.0)
	t.pto_state = pto_on
	# 540/1000 select a gearbox ratio off the engine; the engine is never re-targeted.
	t.pto_rpm = TractorTelemetry.pto_shaft_rpm(drivetrain.rpm, input.pto_mode) if pto_on else 0
	# Governed throttle, not the pedal.
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, drivetrain.applied_throttle, spec, pto_on, pto_load))
	# Driveline state read out of the sim, not the request bits.
	t.diff_lock_state = rear_diff_locked
	t.fwd_drive_state = _front_axle_driven()
	# ISOBUS wheel-based / ground-based speed pair; the difference is slip.
	t.wheel_speed = TractorTelemetry.wheel_kmh(
			_drive_axle_omega(), spec.ground_drive.axle_radius(true))
	t.ground_speed = absf(t.speed) * 3.6
	t.wheel_slip = roundi(TractorTelemetry.slip_pct(t.wheel_speed, t.ground_speed))
	# Rear (drive) axle load off its springs: an implement's carried weight moves it.
	t.axle_load = VehicleTelemetry.axle_load_kg(drive.rear_suspension_force())
	# implement_connected and type report the address claim (ISOBUS_DATA), not the steel: the
	# shipped drawbar trailer is attached and electronically silent. Reads whichever end is loaded.
	var implement: ImplementBase = _hitch.implement if _hitch != null else null
	var on_bus := (_attachment_connections() & int(ImplementBase.Connection.ISOBUS_DATA)) != 0
	t.implement_connected = on_bus
	t.implement_type = _attachment_device_class() if on_bus else ImplementBase.CLASS_NONE
	# Hydraulic remote for both ends; the pump is engine-driven, so no flow with the engine off.
	var spool := clampf(input.scv_flow, 0.0, 1.0) if running else 0.0
	# Pose the linkage before the draft force reads ball_lift() / hitch_point(), which come from
	# the same solve; posing after would use last tick's geometry.
	if _hitch != null:
		_hitch.set_hitch(_hitch_actual, delta)
		_hitch.set_pto(pto_on, t.pto_rpm)
		_hitch.set_scv(spool)
	_apply_implement_mass()
	# Towing: brake demand is the plain foot brake's application (no retarder; the hill hold's
	# included, so the rig holds as one). The trailer brakes regardless of the bus: hoses are not a
	# data bus. No air system: the lever is the parking brake.
	if _drawbar != null:
		drive.towed_kg = _drawbar.towed_mass_kg()
		var foot := drive.pedal_application(drive.foot_pedal(input))
		_drawbar.tick_towing(input, foot, input.handbrake, spool,
				pto_on, t.pto_rpm, telemetry.speed, delta, _grip_terrains)
		drivetrain.speed_cap_kmh = _drawbar.speed_cap_kmh()
	# Draft force on the chassis while the linkage works in soil. Nothing above reads it:
	# engine_load and wheel_slip are its consequences from prior ticks.
	draft_applied = _apply_draft(implement, delta)
	t.draft_force = roundi(TractorTelemetry.draft_pct(draft_applied, draft_max_force))


## Fold the carried share of the implement's weight into the chassis' live mass and COM, off the
## linkage as posed this tick: all of it raised clear, `1 - ground_share()` at the bottom stop.
## Written only on change (`mass` and `center_of_mass` are physics-server writes).
## COMPROMISE: Jolt's tensor is the hull's about the live COM, so an implement's lever term
## (`m_t m_i / M · D²`) reaches roll, pitch and yaw only as the COM shift's `M d²`, about `m_i / M`
## of it (the `hitch` pass reports the gap); closing it is a composite inertia declaration, against
## "never set roll or pitch" and "yaw only through `yaw_dynamic_index`". The ground-borne share
## also leaves the horizontal inertia, and a lowered implement drags nothing beyond the draft law.
func _apply_implement_mass() -> void:
	var implement: ImplementBase = _hitch.implement if _hitch != null else null
	var carried := 0.0
	var com := spec.center_of_mass
	if implement != null:
		carried = implement.mass_kg() * ImplementBase.carried01(
				_hitch.ball_lift(), implement.support_lift(), implement.ground_share())
		com = VehicleMath.carried_com(spec.center_of_mass, _hitch.implement_com(), spec.mass,
				carried)
	if is_equal_approx(carried, _carried_applied) and com.is_equal_approx(_com_applied):
		return
	_carried_applied = carried
	_com_applied = com
	set_live_mass(spec.mass + carried, com)


## Apply this tick's draft force to the chassis and return it (N, signed along forward), or 0
## unless a draft-relevant implement is down in painted soil.
func _apply_draft(implement: ImplementBase, delta: float) -> float:
	if _hitch == null or implement == null or not implement.draft_relevant():
		return 0.0
	# Working depth is the implement's own declared reach (plough 0.25 m, harrow tines 0.10 m).
	var depth01 := TractorTelemetry.draft_depth01(
			_hitch.ball_lift(), implement.tool_depth())
	if depth01 <= 0.0:
		return 0.0
	var point := _hitch.hitch_point()
	var soil01 := _soil_at(point)
	if soil01 <= 0.0:
		return 0.0
	# The implement moves with the hitch, so its speed through the soil is the hitch point's.
	var forward := -global_transform.basis.z
	var v_hitch := VehicleMath.point_velocity(self, point).dot(forward)
	var force := TractorTelemetry.draft_newtons(v_hitch, depth01, soil01,
			implement.draft_rating(), implement.draft_shape(), hitch_effective_mass(point), delta)
	# Applied at the hitch point, below the centre of mass, so its own moment is nose-down; the net
	# nose-up transfer comes from the tyres' answering drive force at ground level, a longer arm.
	apply_force(forward * force, point - global_position)
	return force


## Effective mass (kg) a force along the forward axis at world `point` meets: the body plus the
## moments its arm from the COM turns, off the live tensor (`RayWheel.contact_masses` for one arm,
## read the way `size_cap_masses` reads it). What bounds draft (TractorTelemetry.DRAFT_V_CRAWL).
func hitch_effective_mass(point: Vector3) -> float:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return mass
	var b := global_transform.basis
	var arm := b.transposed() * (point - global_position) - center_of_mass
	return RayWheel.contact_masses(PackedVector3Array([arm]), Vector3.FORWARD, mass,
			b.transposed() * state.inverse_inertia_tensor * b)[0]


## Ploughable-soil weight under `point`, 0..1, off the wheels' terrain pick; unpainted means no soil.
func _soil_at(point: Vector3) -> float:
	var terrain := RayWheel.terrain_at(point, _grip_terrains)
	if terrain == null or not terrain.has_method("channel_weight_at"):
		return 0.0
	return terrain.channel_weight_at(point, SOIL_CHANNEL)


## Mean spin of the rear axle (rad/s): always driven (the front changes with MFWD), and it digs in,
## so it is what wheel_slip measures.
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


## Re-raise the implement. Whatever is attached survives a respawn: the drawbar re-lays it at the
## coupled pose. The base has written spec mass and COM, so the cache says so and the next tick
## writes the surviving implement's load again.
func reset_session_state() -> void:
	super.reset_session_state()
	_hitch_actual = SPAWN_HITCH
	_carried_applied = 0.0
	_com_applied = spec.center_of_mass
	if _drawbar != null:
		_drawbar.respawn_relay(spawn_transform)


## The trailer is a separate body; its RID goes in beside this one's or the camera sees through it.
func get_camera_exclude_bodies() -> Array[RID]:
	var out := super.get_camera_exclude_bodies()
	if _drawbar != null:
		_drawbar.camera_exclude_into(out)
	return out


## Framed for the tractor-plus-trailer combination even with the trailer dropped, so the camera
## never jumps on an E press. look_height clears the scaled body's cab roof.
func get_camera_framing() -> Dictionary:
	return {"distance": 11.0, "height": 5.5, "look_height": 2.4, "top_height": 36.0, "iso_size": 38.0}


## Articulation angle (rad, + = trailer to the right); 0 with nothing towed. Read by the F3 overlay.
func articulation() -> float:
	return _drawbar.articulation() if _drawbar != null else 0.0
