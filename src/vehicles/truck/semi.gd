class_name SemiTractor
extends TruckVehicle
## European cab-over tractor unit: a TruckVehicle towing a free-roaming trailer body over a real
## joint between two RigidBody3Ds. Coupling and two-body housekeeping live in TowHost, shared with
## the tractor's drawbar; `FifthWheel` is this unit's CouplingProfile.
##
## What stays here is trailer catalog routing, the brake-demand blend, the ISO 11992 bus, the
## trailer's air draw, the spool source and camera framing.

@export var fifth_wheel_path: NodePath = ^"FifthWheel"

var _fifth_wheel: TowHost
var _trailer_id := TrailerCatalog.BOBTAIL
## Coupled trailer's reservoir fill, 0..1; 0 while bobtail. See _aux_air_draw.
var _trailer_air := 0.0


func _ready() -> void:
	super._ready()
	_fifth_wheel = get_node_or_null(fifth_wheel_path) as TowHost
	if _fifth_wheel == null:
		push_error("%s: no FifthWheel at %s — this unit cannot tow" % [name, fifth_wheel_path])
	# Coupling waits for a real spawn transform (attachment_spawn_ready); only the id is set here.
	_trailer_id = TrailerCatalog.first()


## E cycles the trailer: box -> tipper -> tanker -> flatbed -> bobtail -> round. Refuses only a
## coupling while the rig is moving (the trailer would be laid at a pose the tractor has left);
## dropping one is never refused.
func cycle_implement() -> void:
	var next_id := TrailerCatalog.next(_trailer_id)
	if TowHost.may_cycle_to(_fifth_wheel, next_id, TrailerCatalog.is_coupled, telemetry.speed):
		set_attachment(next_id)


## The attachment axis as data for the selector UI, as on TractorVehicle. BOBTAIL is a real entry.
func attachment_ids() -> PackedStringArray:
	return TrailerCatalog.TRAILERS


func current_attachment() -> String:
	return _trailer_id


func set_attachment(id: String) -> void:
	_set_trailer(id)


## Which of the coupled trailer's controls are real right now, for the touch overlay, off the same
## TowedBody.consumers() the gating reads.
func attachment_controls() -> Dictionary:
	if _fifth_wheel == null or not _fifth_wheel.is_coupled():
		return {}
	return {
		"pto": _fifth_wheel.trailer.uses(TowedBody.Consumer.PTO),
		"lift": _fifth_wheel.trailer.uses(TowedBody.Consumer.HYDRAULIC),
	}


## Garage showroom hook; TowHost owns the freeze and its fit-check exemption.
func set_display_frozen(frozen: bool) -> void:
	if _fifth_wheel != null:
		_fifth_wheel.set_display_frozen(frozen)


## The spawn countdown finished, so the remembered trailer can be laid behind the tractor.
func attachment_spawn_ready() -> void:
	_set_trailer(_trailer_id)
	# The rig spawns as if long coupled: charged (an in-game coupling starts empty; see _aux_air_draw).
	_trailer_air = 1.0


## The fit check took the trailer away; the id follows, or current_attachment() reports a trailer
## no longer coupled.
func attachment_refused() -> void:
	_set_trailer(TrailerCatalog.BOBTAIL)


func _tick_extras(input: VehicleInput, delta: float) -> void:
	super._tick_extras(input, delta)
	if _fifth_wheel == null:
		return
	var t := telemetry as TruckTelemetry

	# EBS11, towing to towed: the trailer is handed a number and never gates itself. Blends the foot
	# brake with this tick's retarder_state (set by super() above).
	var demand01 := TruckTelemetry.trailer_brake_blend(input.brake, t.retarder_state)
	# Spool: hitch_request read in its transport sense (1 = tipping body down), not as a height.
	var spool := 1.0 - clampf(input.hitch_request, 0.0, 1.0)
	# Spawn countdown, PTO/valve gates, raise interlock, lamps, running gear, fall + fit checks (TowHost).
	_fifth_wheel.tick_towing(input, demand01, spool, t.pto_state, roundi(drivetrain.rpm),
			t.speed, delta, _grip_terrains)

	# Published only now: before tick_towing the trailer's loads and slip are a tick stale. A unit
	# with no data pair keeps zeros.
	if _fifth_wheel.is_coupled() and spec.trailer_bus_equipped:
		var trailer := _fifth_wheel.trailer
		t.trailer_connected = true
		t.trailer_axle_load = TruckTelemetry.axle_load_kg(trailer.bogie_suspension_force())
		# The LAGGED application, not the blend: EBS11 reports what the trailer brakes with.
		t.trailer_brake_demand = roundi(trailer.brake_applied() * 100.0)
		t.trailer_abs = TruckTelemetry.trailer_abs_active(trailer.max_wheel_slip())


## Couple `id`, or go bobtail for TrailerCatalog.BOBTAIL. Routing only: the pose, velocity match,
## joint and fit-check window are TowHost's. The id follows a coupling that could not be made, or
## current_attachment() reports a trailer never laid.
func _set_trailer(id: String) -> void:
	_trailer_id = id
	# A yard trailer has bled down: coupling starts empty and tractor air fills it. Set on every path;
	# dropping a trailer takes its reservoirs with it.
	_trailer_air = 0.0
	if _fifth_wheel == null:
		return
	if not TrailerCatalog.is_coupled(id):
		_fifth_wheel.uncouple()
		return
	# No real spawn transform exists before the countdown runs; the id is remembered and the host asks
	# for it back.
	if not _fifth_wheel.spawn_ready():
		_fifth_wheel.uncouple()
		return
	if not _fifth_wheel.couple(load(id) as PackedScene):
		_trailer_id = TrailerCatalog.BOBTAIL


## A coupled trailer draws air off this tractor's supply while it charges, so AIR1 and AIR2 sag
## through the same air_step model. Coupling costs ~3 bar (`TruckTelemetry.TRAILER_CHARGE_S`),
## close enough to the spring-brake gate that braking while it charges can trip it.
func _aux_air_draw(delta: float) -> float:
	if _fifth_wheel == null or not _fifth_wheel.is_coupled():
		_trailer_air = 0.0
		return 0.0
	# Draw is off the charge the trailer had at the START of the tick.
	var draw := TruckTelemetry.trailer_air_draw(true, _trailer_air)
	_trailer_air = TruckTelemetry.trailer_air_step(_trailer_air, delta)
	return draw


## Re-lay the whole combination: the base resets this chassis, the host re-lays the trailer.
func reset_session_state() -> void:
	super.reset_session_state()
	if _fifth_wheel == null:
		return
	_fifth_wheel.respawn_relay(spawn_transform)
	if _fifth_wheel.is_coupled():
		# A rig that stood coupled has a charged trailer.
		_trailer_air = 1.0


## The trailer is a separate body; the chase camera's occlusion ray must exclude it too, or the
## pull-in slams into its headboard.
func get_camera_exclude_bodies() -> Array[RID]:
	var out := super.get_camera_exclude_bodies()
	if _fifth_wheel != null:
		_fifth_wheel.camera_exclude_into(out)
	return out


## The chase view is pulled back and up to clear the trailer. One frame serves both coupled and
## bobtail: cycling the trailer does not change the camera target.
func get_camera_framing() -> Dictionary:
	return {"distance": 13.5, "height": 6.0, "look_height": 2.0, "top_height": 42.0, "iso_size": 44.0}


## Articulation angle (rad, + = trailer to the right); 0 while bobtail. Read by the F3 overlay.
func articulation() -> float:
	return _fifth_wheel.articulation() if _fifth_wheel != null else 0.0
