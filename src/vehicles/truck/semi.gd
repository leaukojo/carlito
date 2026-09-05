class_name SemiTractor
extends TruckVehicle
## European cab-over tractor unit: a TruckVehicle towing a free-roaming trailer body over a real
## joint between two RigidBody3Ds. Coupling and two-body housekeeping live in TowHost, shared with
## the tractor's drawbar, and `FifthWheel` is this unit's CouplingProfile.
##
## What stays here is trailer catalog routing, the brake-demand blend, the ISO 11992 bus, the
## trailer's air draw, the spool source and camera framing. Coupling is unconditional and the fit
## check is reactive, asking the physics engine after the fact.

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
	# Coupling waits for a real spawn transform; only the id is set here.
	_trailer_id = TrailerCatalog.first()


## E cycles the trailer: box -> tipper -> tanker -> flatbed -> bobtail -> round. Neither the shell
## nor VehicleCatalog learns trailers exist. It refuses only when coupling while the rig is moving,
## since coupling at speed lays the trailer at a pose the tractor has already left; dropping one is
## never refused, because nothing is laid.
func cycle_implement() -> void:
	var next_id := TrailerCatalog.next(_trailer_id)
	if TowHost.may_cycle_to(_fifth_wheel, next_id, TrailerCatalog.is_coupled, telemetry.speed):
		set_attachment(next_id)


## The same three questions TractorVehicle answers about implements, so the selector can show the
## four trailers as pictures. BOBTAIL is a real entry here too.
func attachment_ids() -> PackedStringArray:
	return TrailerCatalog.TRAILERS


func current_attachment() -> String:
	return _trailer_id


func set_attachment(id: String) -> void:
	_set_trailer(id)


## Which of the coupled trailer's controls are real right now, for the touch overlay. It reads the
## same TowedBody.consumers() the gating reads, never a second list.
func attachment_controls() -> Dictionary:
	if _fifth_wheel == null or not _fifth_wheel.is_coupled():
		return {}
	return {
		"pto": _fifth_wheel.trailer.uses(TowedBody.Consumer.PTO),
		"lift": _fifth_wheel.trailer.uses(TowedBody.Consumer.HYDRAULIC),
	}


## Garage showroom hook, forwarded to TowHost, which owns the freeze and the fit-check exemption
## that goes with it.
func set_display_frozen(frozen: bool) -> void:
	if _fifth_wheel != null:
		_fifth_wheel.set_display_frozen(frozen)


## The spawn countdown finished, so the remembered trailer can be laid behind the tractor.
func attachment_spawn_ready() -> void:
	_set_trailer(_trailer_id)
	# The rig spawns having stood coupled, so reservoirs start charged (an in-game coupling starts
	# empty; see _aux_air_draw).
	_trailer_air = 1.0


## The fit check took the trailer away, having laid it inside the world. The id must follow, or
## current_attachment() reports a trailer no longer coupled.
func attachment_refused() -> void:
	_set_trailer(TrailerCatalog.BOBTAIL)


func _tick_extras(input: VehicleInput, delta: float) -> void:
	super._tick_extras(input, delta)
	if _fifth_wheel == null:
		return
	var t := telemetry as TruckTelemetry

	# EBS11, towing to towed: the demand is computed here and the trailer is handed a number, so
	# it never gates itself. Blends the foot brake with the retarder already acting on this
	# chassis' axle, reading this tick's retarder_state from super() above.
	var demand01 := TruckTelemetry.trailer_brake_blend(input.brake, t.retarder_state)
	# Spool: hitch_request read in its transport sense (1 = tipping body down) rather than as a
	# height, so there is no new input owner and no new bus signal.
	var spool := 1.0 - clampf(input.hitch_request, 0.0, 1.0)
	# Spawn countdown, PTO/valve gates, raise interlock, lamps, running gear, fall + fit checks.
	_fifth_wheel.tick_towing(input, demand01, spool, t.pto_state, roundi(drivetrain.rpm),
			t.speed, delta, _grip_terrains)

	# Published only now, off a trailer whose wheels have already integrated this tick; reading
	# before tick_towing would ship stale loads and slip. A unit with no data pair keeps zeros.
	if _fifth_wheel.is_coupled() and spec.trailer_bus_equipped:
		var trailer := _fifth_wheel.trailer
		t.trailer_connected = true
		t.trailer_axle_load = TruckTelemetry.axle_load_kg(trailer.bogie_suspension_force())
		t.trailer_brake_demand = roundi(demand01 * 100.0)
		t.trailer_abs = TruckTelemetry.trailer_abs_active(trailer.max_wheel_slip())


## Couple `id`, or go bobtail for TrailerCatalog.BOBTAIL. Routing only: the pose, velocity match,
## joint and fit-check window are TowHost's. It never refuses on fit, and the id follows a coupling
## that could not be made, or current_attachment() reports a trailer never laid.
func _set_trailer(id: String) -> void:
	_trailer_id = id
	# A yard trailer has bled down, so coupling starts from empty reservoirs and tractor air fills
	# them. Set on every path, since dropping a trailer takes its reservoirs with it.
	_trailer_air = 0.0
	if _fifth_wheel == null:
		return
	if not TrailerCatalog.is_coupled(id):
		_fifth_wheel.uncouple()
		return
	# No real spawn transform exists before the countdown runs, so the id is remembered and the
	# host's countdown asks for it back rather than coupling against a pose never occupied.
	if not _fifth_wheel.spawn_ready():
		_fifth_wheel.uncouple()
		return
	if not _fifth_wheel.couple(load(id) as PackedScene):
		_trailer_id = TrailerCatalog.BOBTAIL


## A coupled trailer draws air off this tractor's supply while it charges, so AIR1 and AIR2 sag
## for it through the same air_step model rather than a term added beside it. Couple and drive off
## without charging and the reservoirs sit 3 bar down, close enough to the spring-brake gate that
## the next real brake application can trip it.
func _aux_air_draw(delta: float) -> float:
	if _fifth_wheel == null or not _fifth_wheel.is_coupled():
		_trailer_air = 0.0
		return 0.0
	# Draw is off the charge the trailer had at the START of the tick.
	var draw := TruckTelemetry.trailer_air_draw(true, _trailer_air)
	_trailer_air = TruckTelemetry.trailer_air_step(_trailer_air, delta)
	return draw


## Re-lay the whole combination: the base handles this chassis, the host re-lays the trailer, and
## air is this vehicle's own state.
func respawn() -> void:
	super.respawn()
	if _fifth_wheel == null:
		return
	_fifth_wheel.respawn_relay(spawn_transform)
	if _fifth_wheel.is_coupled():
		# A rig that stood coupled has a charged trailer, so do not cost air never spent.
		_trailer_air = 1.0


## The trailer is a separate body, so the chase camera's occlusion ray must exclude it too, or the
## pull-in slams into the trailer's headboard when looking forward from behind.
func get_camera_exclude_bodies() -> Array[RID]:
	var out := super.get_camera_exclude_bodies()
	if _fifth_wheel != null:
		_fifth_wheel.camera_exclude_into(out)
	return out


## The combination is ~8.9 m long and 2.1 m tall, so the chase view is pulled back and up to clear
## the trailer with wider overhead and iso frames. One frame serves both coupled and bobtail, since
## cycling the trailer does not change the camera target.
func get_camera_framing() -> Dictionary:
	return {"distance": 12.0, "height": 6.0, "look_height": 2.0, "top_height": 42.0, "iso_size": 44.0}


## Articulation angle (rad, + = trailer to the right); 0 while bobtail. Read by the F3 overlay.
func articulation() -> float:
	return _fifth_wheel.articulation() if _fifth_wheel != null else 0.0
