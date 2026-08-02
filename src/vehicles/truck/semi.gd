class_name SemiTractor
extends TruckVehicle
## European cab-over tractor unit: the first vehicle in this project that tows a FREE-ROAMING
## body, on a real joint between two RigidBody3Ds.
##
## It is a TruckVehicle, so the whole J1939 chassis comes with it unchanged — the air-brake gate,
## the retarder, axle_load — and because its Model has no `arm` mesh, TruckVehicle's
## geometry-is-the-declaration rule gives it honest zeros on all five refuse-body signals with the
## cluster the same shape as the garbage truck's. Nothing about the contract changes here.
##
## Only the two BaseVehicle seams are used, and this class extends the second one by calling
## super() rather than replacing it. _physics_process is never forked.
##
## THE FIFTH WHEEL IS A REAL JOINT, and that is the whole point of the phase. A Generic6DOFJoint3D
## at the kingpin with its three linear axes locked, yaw free to the rig's own jackknife stop, a
## limited pitch and near-zero roll is what a fifth wheel is, and Jolt (project.godot 3d/physics_engine) plus physics
## interpolation is what makes it hold at the locked 60 Hz. The alternative that was written and
## tested but NOT taken is the kinematic follower in Articulation (jackknife_step +
## pose_at_angle); it is deaf to trailer-side forces, so a tanker's surge and a trailer's own
## tipping would stop being physical. See src/vehicles/CLAUDE.md for the measurements.
##
## The trailer carries its OWN unmodified RayWheels (TowedBody). No RayWheel clamp is forked,
## softened or touched anywhere in this phase.
##
## IT ALSO CARRIES THE ISO 11992 TRAILER BUS, and the lesson there is how little is on it: a
## coupling claim, the brake demand out (EBS11), the ABS state back (EBS21), an axle load. Two
## things keep that honest rather than decorative, and both live in this file:
##
##   - trailer_axle_load and trailer_abs are READ OFF THE TRAILER'S OWN WHEELS, after they have
##     integrated this tick. Real suspension forces, real slip — the trailer has real wheels, so
##     nothing needs faking.
##   - A COUPLED TRAILER DRAWS AIR (_aux_air_draw), through the chassis' existing reservoir model
##     rather than beside it. Coupling visibly dips AIR1/AIR2 and can leave the spring-brake gate
##     within reach of the next brake application.
##
## The bus itself is gated on spec.trailer_bus_equipped — the ISO 7638 data pair. A unit without it
## tows and brakes exactly the same trailer and publishes nothing about it.
##
## COUPLING IS UNCONDITIONAL, AND THE FIT CHECK IS REACTIVE. Nothing decides in advance whether nine
## metres of trailer will fit: it is coupled, and then _watch_fresh_coupling asks the physics engine
## whether the trailer's BODY ended up touching anything and takes it away again if it did. That is
## an exact question with an exact answer — a semi-trailer rides on raycasts, so its body touches
## nothing in normal towing — where the predictive version was a pile of thresholds that got both
## answers wrong, and whose failure modes (a settle condition that never came true, a refusal that
## left E doing nothing) were worse than the problem.

## Fifth-wheel coupling point in body space — the TOP FACE of the plate authored in semi.tscn
## (0.75 m behind the origin, 0.20 m ahead of the drive axle so the plate load lands mostly on
## it, 1.05 m up). The trailer's own origin IS its kingpin, so this single point is the whole
## coupling geometry: the joint sits here and the coupled pose is one transform multiply.
##
## The runtime value is READ OFF THE SCENE's Kingpin marker (see _ready), so re-authoring the plate
## moves the coupling with it — the geometry-lives-in-the-scene rule. This is the authored figure,
## kept as the documented default and pinned against the marker by test_trailer.
const KINGPIN_LOCAL := Vector3(0.0, 1.05, 0.75)

## What a fifth wheel actually allows, in degrees. Yaw is free out to the rig's own jackknife stop
## (Articulation.JACKKNIFE_MAX_DEG — the plate itself has no yaw stop); roll is near-zero because the
## plate and the trailer's bearing surface are flat against each other, and deliberately not exactly
## zero: a hair of compliance lets the solver settle instead of fighting the road every tick.
##
## PITCH IS THE ONE THAT WAS WRONG, AND IT WAS WRONG IN THE DIRECTION THE OLD COMMENT CLAIMED IT WAS
## RIGHT. It read "pitch is limited, which is what lets the trailer ride a crest without levering the
## tractor's rear off the road" — the limit does the opposite. Once the joint is ON its stop the two
## bodies are rigid to each other, so 24 t of level trailer levers the climbing tractor's drive axle
## into the air, which is exactly the reported "the truck cannot pull the trailer up a slope": not
## power, not grip, no traction at all because there was no load on the driven wheels. MEASURED at
## the old 8°, on a flat-to-15 % break of slope: the rear axle unloads and the rig stops. A fifth
## wheel is what lets a rig cross a grade break, so the travel has to COVER the break, not bound it.
##
## 15° is sized against what the rest of the rig can do rather than picked: the drivetrain climbs a
## 25 % grade (14.0°) on dirt, and crossing a SHARP break onto one swings the joint from -9.0° to
## +12.8° — so 15° clears the steepest slope the truck can climb anyway, with the stop still there as
## a real end of travel. Real plates oscillate about ±12-15°, so this is also the honest number.
##
## KNOWN AND NOT FIXED HERE: the rig rests at ~5.9° nose-up on FLAT ground, so a fifth of the travel
## is spent before the road does anything. That is a coupling-datum mismatch, not a joint setting —
## the tractor's kingpin sits 1.306 m over the road on its springs while the trailers are authored
## for a 1.05 m plate — and unpicking it means moving shared geometry every trailer depends on. It is
## why 8° had only ~2° of usable headroom, and it is the reason to be generous here until it is.
const PITCH_LIMIT_DEG := 15.0
const ROLL_LIMIT_DEG := 1.5

## Ticks after spawn before the trailer is laid behind the tractor. A PLAIN COUNTER and nothing
## else: the only thing it is buying is the moment the chassis has risen on its own suspension, so
## the coupled pose 5.45 m back is not the 0.16 m into the terrain the un-sprung spawn pose gives.
##
## It used to be a condition — every wheel grounded for N CONSECUTIVE ticks — and that was the bug.
## A condition can fail to come true: drive off the marker at once, or spawn on ground rough enough
## that something is always in the air, and the rig waits for a quiet moment that never arrives and
## runs bobtail forever. A counter always finishes. If the pose turns out to be bad, the check
## below is what deals with it, AFTER the fact, where there is real information instead of a guess.
const SPAWN_COUPLE_TICKS := 12

## How long a freshly coupled trailer is watched for the one thing that means it does not fit:
## ITS BODY TOUCHING SOMETHING. A semi-trailer stands on RayWheels — raycasts, not shapes — so in
## normal towing its collision body touches NOTHING, ever. A contact therefore is not a bump to be
## tolerated, it is the trailer being inside the world, and the answer is to take it away again.
##
## This replaced a predictive shape query that tried to decide beforehand whether nine metres of
## trailer would fit. That could not be made to work: the query reports the contacts it finds
## first rather than the deepest, so it waved buried trailers through, and any threshold generous
## enough not to refuse a grazed kerb was generous enough to miss a hillside. Coupling and then
## LOOKING is both simpler and better informed — the physics engine has already answered the
## question exactly, and no threshold is involved.
##
## A few ticks rather than one, because the first contact can take a step or two to be reported.
const COUPLE_WATCH_TICKS := 8

## Road speed (m/s) below which E may change the trailer — a genuine standstill, deliberately the
## same figure as TowedBody.RAISE_SPEED_MS rather than a second one: both are "the rig is stopped",
## and one number means a driver who can tip can also hitch. See cycle_implement for why.
const COUPLE_SPEED_MS := TowedBody.RAISE_SPEED_MS

## Told to the driver when TIP asks a plumbed body UP with the PTO out or the parking brake off — the
## two things the interlock wants that the driver can DO something about. Fired on the press, so it
## explains the refusal rather than nagging while the rig stands. Same text as the refuse arm's:
## it is the same two conditions and one message for them is one thing to learn.
const TIP_INTERLOCK_NOTICE := TruckVehicle.BODY_INTERLOCK_NOTICE
const TIP_INTERLOCK_NOTICE_DWELL_S := TruckVehicle.BODY_INTERLOCK_NOTICE_DWELL_S

@export var kingpin_path: NodePath = ^"Kingpin"

var _kingpin_local := KINGPIN_LOCAL
var _trailer_id := TrailerCatalog.BOBTAIL
var _trailer: TowedBody = null
var _joint: Generic6DOFJoint3D = null
## Has the SPAWN coupling been made? Level._spawn_vehicle assigns global_transform / spawn_transform
## AFTER add_child, so _ready is too early to lay a trailer anywhere — the first physics tick is the
## earliest honest moment. Same shape as BaseVehicle's _terrains_found guard.
var _coupled_once := false
## Ticks since spawn, against SPAWN_COUPLE_TICKS. Every tick, unconditionally — see the constant.
var _spawn_ticks := 0
## Ticks left in which a fresh coupling is watched for a body contact (see COUPLE_WATCH_TICKS).
var _couple_watch := 0
## True while the garage is showing this rig off (see set_display_frozen).
var _display_frozen := false
## The coupled trailer's reservoir fill, 0..1 — an empty trailer charges off the tractor's supply
## and the tractor's air bars visibly pay for it. 0 bobtail. See _aux_air_draw.
var _trailer_air := 0.0
## Previous tick's tip command (1 - hitch_request), so the notice above fires on the EDGE. -1 until
## the first tick, which is never a press.
var _last_tip_cmd := -1.0


func _ready() -> void:
	super._ready()
	# The coupling point comes off the scene, not out of a constant, so the plate and the joint
	# cannot disagree.
	var marker := get_node_or_null(kingpin_path) as Node3D
	if marker != null:
		_kingpin_local = marker.position
	else:
		push_error("%s: no Kingpin marker at %s — falling back to the authored default"
				% [name, kingpin_path])
	# Spawn coupled, so the towed body is doing something from the first frame (the tractor's
	# spawn-attached-implement precedent). The actual coupling waits for a real spawn transform.
	_trailer_id = TrailerCatalog.first()


## E (or the touch ATTACH button) cycles the TRAILER: box -> tipper -> tanker -> flatbed -> bobtail
## and round. Found by duck-typing in boot.gd, exactly like the tractor's implement cycle, so
## neither the shell nor VehicleCatalog learns that trailers exist — and nothing here learns what
## KIND of trailer it just coupled, which is the same discipline in the other direction.
##
## An unconditional wrapping cycle, because E and V are separate axes: V still walks the truck
## family's bodies from here, so the trailer cycle never has to hand a press back to the shell to
## keep the semi escapable. It cycles the COMBINATION and nothing else.
##
## IT REFUSES ON ONE THING ONLY — THE RIG MOVING. Coupling at speed lays nine metres of trailer at
## a pose the tractor has already left by the time the solver sees it, which reads as "it refuses
## even though there is room": the fit check below then finds the freshly laid body inside whatever
## the rig has driven past. A standstill is the honest condition for hitching one anyway, and it is
## the same shape as the tipper's raise interlock — real practice, expressed as a refusal with a
## reason rather than as a mystery.
##
## Everything ELSE is still decided after the fact: at a standstill every press couples the next
## entry, and a trailer that turns out not to fit is taken away again a few ticks later by
## _watch_fresh_coupling. No prediction of whether it will fit happens here.
func cycle_implement() -> void:
	if absf(telemetry.speed) > COUPLE_SPEED_MS:
		GameState.notice.emit("STOP WHERE THERE IS ROOM TO ATTACH", 0.0)
		return
	set_attachment(TrailerCatalog.next(_trailer_id))


## THE ATTACHMENT AXIS AS DATA — the same three questions TractorVehicle answers about its
## implements, so the vehicle selector can show the four trailers as pictures instead of leaving
## them behind four presses of E. Duck-typed like cycle_implement, and going through one setter
## means a press and a pick cannot diverge. BOBTAIL is a real entry here, as it is in the cycle.
func attachment_ids() -> PackedStringArray:
	return TrailerCatalog.TRAILERS


func current_attachment() -> String:
	return _trailer_id


func set_attachment(id: String) -> void:
	_set_trailer(id)


## Which of the coupled trailer's own controls do something right now — the shell hands this to the
## touch overlay so PTO and TIP are offered only where they are real. Duck-typed by boot.gd exactly
## like cycle_implement, so nothing in the shell learns what a trailer is.
##
## It is the SAME declaration the gating reads (TowedBody.consumers()), not a second list: a button
## that appeared for a trailer with no pump would be the scene claiming a connection again, one
## layer up.
func attachment_controls() -> Dictionary:
	if not is_instance_valid(_trailer):
		return {}
	return {
		"pto": _trailer.uses(TowedBody.Consumer.PTO),
		"lift": _trailer.uses(TowedBody.Consumer.HYDRAULIC),
	}


## THE GARAGE SHOWROOM HOOK, duck-typed by garage.gd exactly like cycle_implement. The showroom
## pins its vehicle (`FREEZE_MODE_KINEMATIC`) and HOVERS it 2.5 m off the floor so the orbit camera
## can look underneath — and a towed body is part of the vehicle for that purpose. Without this the
## trailer is the one thing in the room still obeying gravity: a 24 t body hanging off the joint in
## mid-air with no ground under its own wheels, which swings and thrashes until it comes to rest.
## That is what "the trailer jumps around in the garage" was, and re-laying it (swapping trailers)
## looked like a cure because the swap put it back at the coupled pose.
##
## It also exempts the rig from the coupling fit check: the showroom deliberately hovers it, so a
## display rig must never decide it does not fit and put its own trailer down.
func set_display_frozen(frozen: bool) -> void:
	_display_frozen = frozen
	_apply_display_freeze()


func _apply_display_freeze() -> void:
	if not is_instance_valid(_trailer):
		return
	_trailer.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_trailer.freeze = _display_frozen


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	super._tick_extras(input, delta)
	# THE SPAWN COUPLING: a plain countdown, then couple. No conditions, so it always happens.
	_spawn_ticks += 1
	if not _coupled_once and _spawn_ticks >= SPAWN_COUPLE_TICKS:
		_coupled_once = true
		_set_trailer(_trailer_id)
		# The rig SPAWNS having stood coupled, so its trailer's reservoirs are already charged. Every
		# coupling made while driving charges from empty and dips the air (see _aux_air_draw); the
		# first frame of the game is deliberately not one of them, or the truck would begin its life
		# with a low-pressure warning nobody caused.
		_trailer_air = 1.0
	if not is_instance_valid(_trailer):
		return
	var t := telemetry as TruckTelemetry

	# EBS11, towing-to-towed. The demand is computed on the TOWING side and the trailer is handed a
	# number — a towed body is never trusted to gate itself, the rule ThreePointHitch follows for
	# the implements — and it blends the foot brake with the retarder that is already acting on this
	# chassis' driven axle. t.retarder_state is this tick's, computed by super() above.
	var demand01 := TruckTelemetry.trailer_brake_blend(input.brake, t.retarder_state)
	# What the trailer's BODY is allowed to be doing, decided HERE and handed down as numbers. Same
	# rule as the brake demand above and the same rule ThreePointHitch follows for the implements.
	_drive_trailer_body(input, t)
	# The trailer's running gear is ticked HERE, not from its own _physics_process: one tick per
	# physics frame, always after this chassis' own wheels. It brakes on the demand WHATEVER the bus
	# is doing — the pneumatic lines are not the data pair, so a unit with no ISO 11992 bus still
	# stops its trailer; all that goes dark is what it can say about it. The parking brake goes down
	# the same way and for the same reason — one dash control applies the spring brakes at both ends
	# of a real rig, and the red line carrying it is pneumatic, not the data pair.
	_trailer.tick_towed(demand01, input.handbrake, delta, _grip_terrains)

	# ...and only now is the bus published, off a trailer whose wheels have already integrated this
	# tick. Reading it before tick_towed would publish last tick's loads and slip, which is the
	# stale-by-one-frame mistake the tractor's pose-then-read-the-linkage ordering exists to avoid.
	# super() left these cleared, so a unit with no data pair simply keeps the bobtail zeros.
	if spec.trailer_bus_equipped:
		t.trailer_connected = true
		t.trailer_axle_load = TruckTelemetry.axle_load_kg(_trailer.bogie_suspension_force())
		t.trailer_brake_demand = roundi(demand01 * 100.0)
		t.trailer_abs = TruckTelemetry.trailer_abs_active(_trailer.max_wheel_slip())

	# The base only watches this chassis fall off the world; a trailer that somehow leaves it
	# would otherwise hang there on the joint.
	if _trailer.global_position.y < FALL_RESPAWN_Y:
		respawn()
		return
	_watch_fresh_coupling()


## DOES THE TRAILER WE JUST COUPLED ACTUALLY FIT? Asked of the physics engine after the fact rather
## than guessed at beforehand, and the signal is exact rather than a threshold: a semi-trailer rides
## on RayWheels, which are RAYCASTS, so its collision body touches nothing at all in normal towing.
## One body contact means it is inside the world — a wall, a hillside, another vehicle — so it is
## taken away again and the driver is told why. Wheels cannot trigger this; they are not shapes.
##
## Only for the first few ticks after a coupling. Later contacts are ordinary driving (grounding out
## over a crest, backing into something) and are the driver's business, not a reason to unhitch.
##
## The showroom is exempt: it deliberately hovers the rig off the floor, and a display rig must
## never drop its trailer.
func _watch_fresh_coupling() -> void:
	if _couple_watch <= 0 or _display_frozen:
		return
	_couple_watch -= 1
	if not _trailer.body_is_colliding():
		return
	_set_trailer(TrailerCatalog.BOBTAIL)
	# Nobody pressed E for this one, so the shell has no idea the attachment moved — say so, or the
	# touch overlay keeps offering the PTO/TIP buttons of a trailer that is no longer there.
	GameState.attachment_changed.emit()
	GameState.notice.emit("NO ROOM FOR A TRAILER - PULL FORWARD", 0.0)


## HAND THE TRAILER'S BODY ITS DRIVE, ITS FLOW AND ITS INTERLOCK — all three decided on the TOWING
## side, which is the whole of what "the gating lives on the coupling side" means here. A towed body
## is never trusted to ignore drive it never plugged in, never trusted to shut a valve it does not
## have, and above all never trusted to police its own interlock: a trailer that did could be
## replaced by one that did not.
##
## Three gates, in the order they matter:
##
##   - THE PTO. Only a trailer that DECLARES Consumer.PTO is on the far end of the chassis stub, so
##     a box reads a dead shaft however far the PTO is engaged. The rpm handed down is this
##     chassis' own engine speed — the honest number, not a second model of one.
##   - THE VALVE. Only a trailer that DECLARES Consumer.HYDRAULIC has hoses on the remote. The
##     spool position is the local attachment toggle (InputRouter's `_hitch_up` — the **I** key and
##     the touch TIP button, which share that one owner), read as its transport sense rather than
##     its height: `hitch_request` 1 is the TRANSPORT pose, which for a mounted implement is raised
##     and for a tipping body is DOWN. So the rig spawns with the body where it belongs and one
##     press sends it up. There is no new input owner and, deliberately, no new signal — a tipper
##     command on the trailer bus is the exact thing this phase does not do.
##   - THE RAISE INTERLOCK, TowedBody.body_raise_allowed, evaluated on CHASSIS state (this truck's
##     road speed and parking brake). It refuses the RAISE DIRECTION ONLY, clamped against where
##     the body already is: rolling away with the body up must HOLD it, not command it down onto
##     whatever is under it. Lowering is always allowed, which is the direction that makes a rig
##     safe again.
##
## The pump is engine-driven through the PTO, so no PTO means no flow at all — and tipper.gd then
## freezes rather than sinking, because a lost drive is not a retraction.
func _drive_trailer_body(input: InputRouter.VehicleInput, t: TruckTelemetry) -> void:
	var driven := _trailer.uses(TowedBody.Consumer.PTO)
	_trailer.set_pto(t.pto_state and driven, roundi(drivetrain.rpm) if driven else 0)

	var plumbed := _trailer.uses(TowedBody.Consumer.HYDRAULIC)
	var cmd := 1.0 - clampf(input.hitch_request, 0.0, 1.0)
	_warn_if_tip_interlocked(cmd, plumbed, input.handbrake, t.pto_state)
	if not TowedBody.body_raise_allowed(t.speed, input.handbrake):
		cmd = minf(cmd, _trailer.body_pos01())
	_trailer.set_valve(cmd if plumbed and t.pto_state else 0.0)


## Say WHY the TIP button did nothing, on the press that did nothing. The refuse arm's
## _warn_if_body_interlocked in the same shape and for the same two conditions: no PTO means no pump,
## and the raise interlock wants the parking brake set. Road speed is deliberately left out — that
## one clears itself by stopping, and this notice is for the driver who IS stopped.
##
## Only on a press that asks the body UP, and only on a trailer that is plumbed at all: TIP on a box
## is a button the overlay never offers, and cycling the body back DOWN is always allowed.
func _warn_if_tip_interlocked(cmd: float, plumbed: bool, handbrake: float, pto_on: bool) -> void:
	var edge := not is_equal_approx(cmd, _last_tip_cmd) and _last_tip_cmd >= 0.0
	_last_tip_cmd = cmd
	if not edge or not plumbed or cmd <= _trailer.body_pos01():
		return
	if pto_on and handbrake >= TowedBody.RAISE_PARK_BRAKE_MIN:
		return
	GameState.notice.emit(TIP_INTERLOCK_NOTICE, TIP_INTERLOCK_NOTICE_DWELL_S)


## A COUPLED TRAILER DRAWS AIR: its reservoirs charge off this tractor's supply, so while they fill
## they are a second consumer on both circuits and the AIR1/AIR2 bars sag for it. That is the whole
## coupling between the trailer phases and the chassis phase's air model, and it deliberately goes
## THROUGH that model — air_step's own draw rates, its own clamps — rather than subtracting a
## trailer term somewhere beside it.
##
## Consequence, and it is the point rather than a rough edge: couple and drive off without letting
## the trailer charge and the reservoirs are 3 bar down, so the next real brake application can take
## them through the spring-brake gate and stop the rig where it stands.
func _aux_air_draw(delta: float) -> float:
	var coupled := is_instance_valid(_trailer)
	if not coupled:
		_trailer_air = 0.0
		return 0.0
	# Read the draw off the charge the trailer had at the START of the tick — the air is what fills
	# it, so it pays first and then rises.
	var draw := TruckTelemetry.trailer_air_draw(true, _trailer_air)
	_trailer_air = TruckTelemetry.trailer_air_step(_trailer_air, delta)
	return draw


## Re-lay the whole combination. The base handles this chassis (spawn transform, zeroed motion,
## zeroed accel/impact history, wheel reset); the trailer is then re-LAID at its coupled pose and
## stopped, not merely stopped — zeroing velocity alone leaves a body halted wherever it drifted
## to, which is the train's lesson. TowedBody.reset_at also clears its wheel state, which is the
## trailer's equivalent of the accel history: a RayWheel keeping last tick's compression across a
## teleport reports the jump as a suspension spike.
func respawn() -> void:
	super.respawn()
	# A re-laid trailer is not a fresh coupling: it is going back exactly where it was standing, so
	# the fit check has nothing to say about it and must not fire on the teleport.
	_couple_watch = 0
	if is_instance_valid(_trailer):
		_trailer.reset_at(Articulation.coupled_pose(spawn_transform, _kingpin_local))
		# Air is physical state, so a reset re-lays it on BOTH bodies: the base put this chassis back
		# at its spawn pressure, and a rig that has stood coupled has a charged trailer behind it.
		# Leaving it part-charged would make a respawn cost air the driver never spent.
		_trailer_air = 1.0


## The trailer is a separate body, so the chase camera's occlusion ray has to ignore it too — the
## train's precedent, and for the same reason: without this the pull-in slams the camera into the
## trailer's headboard the moment you look forward from behind.
func get_camera_exclude_bodies() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if is_instance_valid(_trailer):
		out.append(_trailer.get_rid())
	return out


## The combination is ~8.9 m long and 2.1 m tall: pull the chase view back and up so it clears the
## trailer, and widen the overhead/iso frames to fit the length. Between the wheeled default and
## the train's 32 m consist numbers. ChaseCamera caches this per TARGET, not per frame, so it is
## deliberately ONE frame for both states rather than a coupled and a bobtail one: cycling the
## trailer does not change the target, so a bobtail-specific frame would not be picked up until
## the next garage swap.
func get_camera_framing() -> Dictionary:
	return {"distance": 12.0, "height": 6.0, "look_height": 2.0, "top_height": 42.0, "iso_size": 44.0}


## A variant swap queue_frees this vehicle; the trailer lives beside it under the level (see
## _set_trailer), so it has to be taken along by hand or it is left standing in the road.
func _exit_tree() -> void:
	super._exit_tree()
	_drop_trailer(false)


# --- coupling ---------------------------------------------------------------------------------


## Couple `id` (or run bobtail for TrailerCatalog.BOBTAIL). The trailer is added as a child of THIS
## VEHICLE'S PARENT — the level — and never of the vehicle: a dynamic RigidBody3D under another
## body has its parent's transform applied on top of the one the physics server writes. So the two
## are siblings held together by nothing but the joint, which is what they physically are.
##
## IT NEVER REFUSES. Whether nine metres of trailer FIT is not decided here and is not decided in
## advance at all: the trailer is coupled, and _watch_fresh_coupling then asks the physics engine
## whether its body ended up inside anything and takes it away again if so. That is the whole of the
## clearance story now, and it replaced a predictive shape query that could not be made to work.
func _set_trailer(id: String) -> void:
	var host := get_parent()
	if not TrailerCatalog.is_coupled(id) or host == null:
		_trailer_id = id
		_drop_trailer()
		_trailer_air = 0.0
		_couple_watch = 0
		return

	var candidate := (load(id) as PackedScene).instantiate() as TowedBody
	var pose := Articulation.coupled_pose(global_transform, _kingpin_local)
	_trailer_id = id
	_drop_trailer()
	# Watch this one from here: it is a fresh coupling, so a body contact in the next few ticks means
	# it did not fit.
	_couple_watch = COUPLE_WATCH_TICKS
	# A trailer standing in a yard has bled down, so a coupling starts from EMPTY reservoirs and the
	# tractor's air pays to fill them. Dropping one takes its reservoirs with it, which is why this
	# is set on both paths rather than only on the coupled one.
	_trailer_air = 0.0
	_trailer = candidate
	host.add_child(_trailer)
	_trailer.global_transform = pose
	# Match the trailer's motion to the rig BEFORE the joint exists, treating the combination as
	# one rigid body for that instant. Coupling at speed otherwise hands the solver 14 t with the
	# whole road speed as relative velocity, which is an impulse big enough to throw the rig.
	var lever := _trailer.global_transform * _trailer.center_of_mass \
			- global_transform * center_of_mass
	_trailer.linear_velocity = linear_velocity + angular_velocity.cross(lever)
	_trailer.angular_velocity = angular_velocity
	_trailer.reset_physics_interpolation()
	_joint = _build_joint()
	add_child(_joint)
	# Bound LAST: assigning the two bodies is what makes Jolt build the constraint, and it reads
	# the joint node's own global transform for the frames — so the joint has to be in the tree, at
	# the kingpin, with both bodies already posed.
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(_trailer)
	# A trailer coupled while the showroom has the rig pinned is pinned with it — including one
	# swapped in with E, which is how you look at all four in the garage.
	_apply_display_freeze()


## Uncouple: the joint goes first, then the trailer.
##
## BOTH LEAVE THE TREE IN THIS CALL, and only their memory is deferred. `queue_free` alone was a
## real bug rather than a tidiness point: it defers to the END OF THE FRAME, and physics steps run
## before that flush — so between a swap and the flush the level held TWO trailers, both jointed to
## this tractor, interpenetrating at the same coupled pose. Two twenty-tonne bodies inside each
## other is an enormous separation impulse, and the new trailer wore it: thrown, or shoved into
## whatever was beside it. Removing them from the tree takes them out of the physics space
## immediately, which is the part that has to be synchronous; `queue_free` after that is just
## bookkeeping and stays deferred because a swap can be requested from anywhere.
## `unparent` false is the TEARDOWN path and it is not optional: `remove_child` fails outright while
## a parent is mid-removal ("Parent node is busy setting up children"), which is exactly where
## _exit_tree runs. Nothing is coupling there anyway — the tractor is leaving — so the overlap this
## guards against cannot happen and plain queue_free is right.
func _drop_trailer(unparent := true) -> void:
	if is_instance_valid(_joint):
		if unparent:
			_unparent(_joint)
		_joint.queue_free()
	_joint = null
	if is_instance_valid(_trailer):
		if unparent:
			_unparent(_trailer)
		_trailer.queue_free()
	_trailer = null


## Take `node` out of the tree now, if it is in one.
static func _unparent(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)


## The fifth wheel itself. Child of this chassis at the kingpin with an unrotated basis, so the
## joint's axes ARE the tractor's: X = pitch, Y = yaw, Z = roll.
##
## The linear axes are limited with lower == upper == 0, which is how a 6DOF joint says "locked":
## the trailer's kingpin cannot translate relative to the plate at all.
##
## YAW IS LIMITED, AND THE LIMIT IS A LABELLED MODEL OF THE VEHICLE'S OWN STOP rather than anything
## the fifth wheel does — a fifth wheel really does turn freely. What stops a jackknifing rig is
## steel: the trailer against the cab. That contact CANNOT be left to the collision system here.
## The trailer's gooseneck clears this chassis in the straight pose, but it sweeps THROUGH it around
## 60 deg of articulation, so `exclude_nodes_from_collision` must stay at its default true or the two
## bodies fight each other for the same space every time the rig bends. Driving it without a limit is
## what turned this from a comment
## into a decision: reversing on full lock folded the rig to 130 deg and the trailer swung THROUGH
## where a cab would be. So the stop is expressed on the joint, at the same measured angle the
## kinematic fallback clamps to — one number for both paths.
func _build_joint() -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.name = "FifthWheel"
	j.position = _kingpin_local
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
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(PITCH_LIMIT_DEG))
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(PITCH_LIMIT_DEG))
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
			-deg_to_rad(Articulation.JACKKNIFE_MAX_DEG))
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,
			deg_to_rad(Articulation.JACKKNIFE_MAX_DEG))
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(ROLL_LIMIT_DEG))
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(ROLL_LIMIT_DEG))
	return j


## Current articulation angle (rad, + = trailer to the right); 0 while bobtail. Read duck-typed by
## the F3 overlay — it is the one number that says how jackknifed the rig is, and reversing one is
## unreadable from the chase camera alone.
func articulation() -> float:
	if not is_instance_valid(_trailer):
		return 0.0
	return Articulation.articulation_angle(global_transform, _trailer.global_transform)
