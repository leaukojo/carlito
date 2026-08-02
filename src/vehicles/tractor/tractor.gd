class_name TractorVehicle
extends BaseVehicle
## Tractor. A real BaseVehicle subclass because it owns per-tick
## subsystem state the base has no concept of: the rear hitch position, the PTO, and which
## implement is on the linkage. It never forks _physics_process — it plugs into the two base
## seams (_make_telemetry, _tick_extras).
##
## The linkage itself is ThreePointHitch (tractor anatomy: draft arms, rockshaft, lift rods,
## top link, PTO stub); this class only decides WHERE it should be and WHAT is hanging on it.
## Implement geometry is scene-authored (like lamp placement); drive tuning lives in the
## body's spec (tractor-kenney_spec.tres). Only the implement behaviour knobs are
## @export here (node behaviour, not wheel/engine tuning — a four-knob TractorSpec would be
## over-engineering, CLAUDE.md rule 2).
##
## It is also the one vehicle that puts a force of its own on the chassis: the draft of an
## implement working in the soil, applied at the hitch point from _tick_extras (see _apply_draft).
## Everything the player then hears and reads — the rpm sag, the load, the slip — is a consequence
## of that one force, published by the systems that already measured it.

const SPAWN_HITCH := 1.0                ## spawn default: raised (transport), PTO off

## Splat paint channel that IS soil for the draft force: channel 4, level 1's "Field" — the
## ploughable ground painted into the farm. Deliberately not Dirt (channel 1): auto-splat paints
## dirt on every slope of the island, so a draft test keyed on it would fire on hillsides.
## Channel 4 lives in splatmap2, which auto-splat only ever zeroes, so it cannot appear by
## accident — and an unpainted level therefore answers "no soil" everywhere.
const SOIL_CHANNEL := 4

@export var hitch_travel_time := 1.5   ## s for a full raise or lower
@export var pto_load := 0.35           ## engine_load added while PTO engaged
## Rated draft, in newtons: the pull of a draft-relevant implement at full working depth in soil
## at DRAFT_SPEED_REF, and the 100 % end of the 'draft_force' signal. 12 kN is a real figure for a
## three-furrow mounted plough, and comfortably inside what 4 t on these tires can pull — the
## tractor lugs and slips against it, it is not stopped by it.
@export var draft_max_force := 12000.0
@export var hitch_path: NodePath = ^"ThreePointHitch"

var _hitch_actual := SPAWN_HITCH       ## 0..1, chases input.hitch_request
var _hitch: ThreePointHitch
var _implement_id := ImplementCatalog.DETACHED  ## current entry in the E cycle


func _make_telemetry() -> VehicleTelemetry:
	return TractorTelemetry.new()


func _ready() -> void:
	super._ready()
	_hitch = get_node_or_null(hitch_path) as ThreePointHitch
	# Spawn with an implement on the linkage, so hitch and PTO do something visible from the
	# first frame; E cycles from here (including back to a bare tractor).
	_set_implement(ImplementCatalog.first())


## Advance to the next entry in the implement cycle — the DETACHED state included. Called by
## the shell when E / the touch ATTACH button fires on this vehicle; the shell finds it by
## duck-typing, so nothing outside the tractor knows implements exist.
##
## E is the attachment axis and V the body one, so this can be an unconditional cycle: it never
## has to decide whether to hand the press back to the shell, and cycling to DETACHED can never
## re-spawn the tractor out from under the implement.
func cycle_implement() -> void:
	set_attachment(ImplementCatalog.next(_implement_id))


## THE ATTACHMENT AXIS AS DATA — the same three questions SemiTractor answers about its trailers,
## so the vehicle selector can show the axis as a row of pictures instead of a key you press five
## times to see what exists. Duck-typed like cycle_implement: the shell asks a machine what it can
## carry and gets scene paths back, never learning that implements exist.
##
## cycle_implement is now "set the next one", so a press and a pick go through one setter and
## cannot diverge. DETACHED is a real entry in what comes back, exactly as it is in the cycle.
func attachment_ids() -> PackedStringArray:
	return ImplementCatalog.IMPLEMENTS


func current_attachment() -> String:
	return _implement_id


func set_attachment(id: String) -> void:
	_set_implement(id)


## Which of this machine's attachment controls do something right now — the shell hands this to
## the touch overlay so the PTO and TIP/lift buttons are offered only where they are real. Duck-
## typed by boot.gd exactly like cycle_implement above, so nothing in the shell learns what an
## implement is; SemiTractor answers the same question about its trailer.
##
## The PTO answer is the implement's OWN declaration (ImplementBase.Connection.PTO), the same one
## ThreePointHitch gates the real drive on — not a second list, so a button cannot appear for a
## machine with nothing on the far end of the stub shaft. The LIFT answer is unconditionally true
## because the three-point linkage is TRACTOR ANATOMY: it raises and lowers with nothing hanging
## on it, and `hitch_pos` is a real signal on a bare tractor.
func attachment_controls() -> Dictionary:
	var implement := _hitch.implement if _hitch != null else null
	return {
		"pto": implement != null and implement.uses(ImplementBase.Connection.PTO),
		"lift": true,
	}


## Attach `id` (or detach for ImplementCatalog.DETACHED). Attaching is a logical ISOBUS
## address claim: there is no cable, the implement simply starts answering on the bus, which
## is what implement_connected / implement_type report from _tick_extras.
func _set_implement(id: String) -> void:
	_implement_id = id
	if _hitch == null:
		return
	if ImplementCatalog.is_attached(id):
		_hitch.attach(load(id) as PackedScene)
	else:
		_hitch.detach()
	_hitch.set_hitch(_hitch_actual)


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as TractorTelemetry
	var running := input.key == InputRouter.KEY_IGNITION
	_hitch_actual = move_toward(_hitch_actual, input.hitch_request, delta / hitch_travel_time)
	var pto_on := input.pto and running
	t.hitch_pos_actual = roundi(_hitch_actual * 100.0)
	t.pto_state = pto_on
	# 540 / 1000 is a GEARBOX selection, so the shaft speed follows the engine through the
	# selected mode's ratio — the engine is not asked to run at a different speed for it.
	t.pto_rpm = TractorTelemetry.pto_shaft_rpm(drivetrain.rpm, input.pto_mode) if pto_on else 0
	t.engine_load = roundi(VehicleTelemetry.engine_load_pct(
			drivetrain.rpm, input.throttle, spec, pto_on, pto_load))
	# Driveline state, read out of the sim rather than echoed from the request bits: the base
	# reports what it actually ran the rear diff as, and the front wheels report whether they
	# really are driven this tick.
	t.diff_lock_state = rear_diff_locked
	t.fwd_drive_state = _front_axle_driven()
	# The ISOBUS wheel-based / ground-based speed pair, both out of the same sim: the driveline's
	# own speed from the drive axle's spin, and the chassis' forward velocity. _tick_extras runs
	# last, so both are this tick's values. Their difference IS the slip — nothing separate.
	t.wheel_speed = TractorTelemetry.wheel_kmh(_drive_axle_omega(), spec.wheel_radius)
	t.ground_speed = absf(t.speed) * 3.6
	t.wheel_slip = roundi(TractorTelemetry.slip_pct(t.wheel_speed, t.ground_speed))
	t.engine_hours = VehicleTelemetry.hours_step(t.engine_hours, running, delta)
	# The bus reads whatever is actually on the linkage — detached is 0 / false, not a gap.
	# What these two report is the ADDRESS CLAIM, not the steel: an implement that declares no
	# ISOBUS_DATA connection is mechanically attached and electronically absent, exactly like a
	# dumb plough on a real ISOBUS tractor. So the connection an implement declares is what
	# decides the signal — the declaration is load-bearing, not documentation.
	var implement: ImplementBase = _hitch.implement if _hitch != null else null
	var on_bus := implement != null and implement.uses(ImplementBase.Connection.ISOBUS_DATA)
	t.implement_connected = on_bus
	t.implement_type = implement.device_class() if on_bus else ImplementBase.CLASS_NONE
	# Pose the linkage BEFORE the draft force reads it: _apply_draft sizes the force from
	# ball_lift() and applies it at hitch_point(), and both come out of the four-bar solve
	# set_hitch runs. Posing afterwards would place this tick's force with last tick's geometry.
	if _hitch != null:
		_hitch.set_hitch(_hitch_actual)
		_hitch.set_pto(pto_on, t.pto_rpm)
		# Hydraulic remote. The pump is engine-driven, so a stopped engine means no flow
		# however far sloppyCAN opens the spool — the same `running` gate the PTO gets.
		_hitch.set_scv(input.scv_flow if running else 0.0)
	# Draft: a real rearward force on the chassis whenever what is on the linkage works IN the
	# soil and is still down in it. Nothing above reacts to it — engine_load was computed from the
	# rpm the drivetrain already sagged to, and wheel_slip from the wheels that already had to pull
	# against it, both on the ticks since. That IS the coupling; there is no draft term anywhere
	# else, and adding one would be double-counting a force the body already felt.
	t.draft_force = roundi(TractorTelemetry.draft_pct(
			_apply_draft(implement, t.speed, delta), draft_max_force))


## Apply this tick's draft force to the chassis and return it (newtons, signed along forward).
## Returns a clean 0 — and applies nothing at all — unless a draft-relevant implement is down in
## painted soil: a detached hitch, a mower or a spreader (nothing of theirs is in the ground), a
## lifted plough and ground that is not the field each fall out here, in that order.
func _apply_draft(implement: ImplementBase, v_fwd: float, delta: float) -> float:
	if _hitch == null or implement == null or not implement.draft_relevant():
		return 0.0
	# Working depth is the IMPLEMENT's own declared reach, not one figure for both draft
	# machines: the plough's shares go 0.055 m down and the harrow's tines 0.02 m, so a shared
	# constant had the harrow still reporting draft with its tines visibly in the air.
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
	# AT THE HITCH POINT, not the centre of mass, so the pull also pitches the tractor and the
	# weight transfer a real plough causes falls out of the sim rather than being modelled. Which
	# WAY it pitches is worth being precise about, because the offset alone does not say: the
	# hitch (y ~ 0.21) is BELOW the centre of mass (y = 0.35 in the spec), so this force's own
	# moment is nose-DOWN. The net is nose-up and rear-loaded because the tires must answer it
	# with a forward drive force at ground level, a longer arm below the same centre of mass.
	apply_force(-global_transform.basis.z * force, point - global_position)
	return force


## How strongly the ground under `point` is ploughable soil, 0..1 — the "in soil" test. Reuses
## the wheels' own terrain pick (nearest painted surface within reach, so a plough crossing a
## bridge over the field is not in soil) and the terrain's CACHED splat Images: <= 8 bilinear
## reads, never a get_image() per tick. Duck-typed like the grip query, so the tractor depends on
## no terrain type — a level with no painted terrain simply has no soil.
func _soil_at(point: Vector3) -> float:
	var terrain := RayWheel.terrain_at(point, _grip_terrains)
	if terrain == null or not terrain.has_method("channel_weight_at"):
		return 0.0
	return terrain.channel_weight_at(point, SOIL_CHANNEL)


## Mean spin of the REAR axle (rad/s) — the always-driven one, which is where a real
## wheel-based speed sensor sits. Deliberately not "every driven wheel": that set changes when
## MFWD engages, so wheel_speed would step at the moment you engage the front axle even though
## nothing about the tractor's motion changed. The rear axle is also the one that digs in, so
## it is the axle wheel_slip should be measuring.
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


## Re-raise the implement on respawn so a reset returns to the spawn default (raised). What
## is ATTACHED survives — respawn moves the tractor, it does not rebuild it, and losing the
## implement every time you reset would be its own kind of bug.
func respawn() -> void:
	super.respawn()
	_hitch_actual = SPAWN_HITCH
