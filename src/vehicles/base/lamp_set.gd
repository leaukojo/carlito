class_name LampSet
extends RefCounted
## Applies §6 lamp state to the scene-authored lamp nodes a VehicleSpec names.
##
## Placement is scene-authored: the spec only DECLARES which nodes are
## the head / brake / turn lamps (by NodePath, relative to the vehicle root); their
## transforms live in the model scene. sloppyCAN is the sole authority on lamp state
##: the brake tier, the turn bits and the headlight level are mirrored
## VERBATIM here — there is no local blink timer; turn lamps blink because the source
## toggles the bit.
##
## The decision (rear_tier) is a pure static fn, unit-tested in tests/test_lamps.gd;
## apply() is the thin scene-touching part (Light3D energy + emissive materials).
##
## ONE DOCUMENTED EXCEPTION to the no-local-blink rule: the aircraft anti-collision beacon
## (flash_lamp_paths) is pulsed from the wall clock here. It is not an exception to
## "sloppyCAN is the authority" so much as a gap in it — the contract carries no beacon
## signal at all, so there is no bit to mirror, and a beacon that does not flash is not a
## beacon. Tracked in TODO.md; if the contract ever gains a toggling beacon bit, delete
## BEACON_* and mirror it verbatim like every other lamp. Do NOT read this as licence to
## add a timer to the turn lamps, which DO have an authoritative source.

## Rear tri-state: STOP (brake) > TAIL (headlights on) > OFF (dim housing,
## never invisible).
enum Rear { OFF, TAIL, STOP }

## Headlight levels — mirror the contract 'lights' enum values exactly.
const HL_OFF := 1
const HL_CLEARANCE := 2
const HL_LOW := 3
const HL_HIGH := 4

## Emissive energy per rear tier; OFF keeps a dim housing glow so the lens is always
## visible.
const REAR_ENERGY := { Rear.OFF: 0.15, Rear.TAIL: 0.7, Rear.STOP: 3.5 }
const REAR_COLOR := Color(0.95, 0.06, 0.03)

## Turn lens: dark amber when off (still visible), bright amber when lit.
const TURN_OFF_ENERGY := 0.12
const TURN_ON_ENERGY := 3.5
const TURN_COLOR := Color(1.0, 0.5, 0.0)

## Head LENS emissive energy per headlight level — the glow on the lamp face itself, which
## the SpotLight3D (a beam, not a surface) cannot provide. OFF keeps a dim housing glow so
## the lens is always visible, exactly like the rear tier.
const HEAD_LENS_ENERGY := {HL_OFF: 0.15, HL_CLEARANCE: 0.8, HL_LOW: 3.0, HL_HIGH: 5.0}
const HEAD_LENS_COLOR := Color(1.0, 0.96, 0.85)

## Steady marker lenses (the plane's nav lights today): dim housing glow when the
## master switch is off, one steady lit level from clearance up — no tier, no blink. Their
## COLOUR is scene-authored (see _bind_steady), so only the energy lives here.
const STEADY_ENERGY := { HL_OFF: 0.15, HL_CLEARANCE: 2.2, HL_LOW: 2.2, HL_HIGH: 2.2 }

## Anti-collision beacon pulse — the local-clock exception documented in the header. Phase
## is read off the clock rather than accumulated, so it never drifts and needs no timer
## node. A real beacon is a rotating lamp: a short bright pulse is its readable stand-in.
const BEACON_PERIOD := 1.4    ## s per flash (~43 flashes/min, the real beacon rate)
const BEACON_ON_FRAC := 0.16  ## fraction of the period the lens is lit
const BEACON_ON_ENERGY := 4.5
const BEACON_OFF_ENERGY := 0.15

## Headlight SpotLight3D energy + range per level (distinct per state).
const HEAD_ENERGY := { HL_OFF: 0.0, HL_CLEARANCE: 1.2, HL_LOW: 7.5, HL_HIGH: 14.0 }
const HEAD_RANGE := { HL_OFF: 0.0, HL_CLEARANCE: 8.0, HL_LOW: 32.0, HL_HIGH: 90.0 }

## Beam SHAPE per level. The Compatibility renderer has no light projectors, so the beam
## pattern is what the cone itself can express: a wide, short, downward-aimed spread for
## low beam (light on the road just ahead), a narrow, near-level, long throw for high
## beam. Without the downward pitch every level renders the same disc on whatever wall is
## in front — which is the artifact these three tables exist to remove.
##
## HEAD_ANGLE is the HALF-angle in degrees (Godot's spot_angle), HEAD_PITCH the downward
## aim in degrees applied to the scene-authored basis, HEAD_FALLOFF the cone-edge exponent
## (higher = more light concentrated on the axis, i.e. a hotspot rather than a flat disc).
const HEAD_ANGLE := { HL_OFF: 38.0, HL_CLEARANCE: 36.0, HL_LOW: 44.0, HL_HIGH: 38.0 }
const HEAD_PITCH := { HL_OFF: 0.0, HL_CLEARANCE: 12.0, HL_LOW: 11.0, HL_HIGH: 1.5 }
const HEAD_FALLOFF := { HL_OFF: 1.0, HL_CLEARANCE: 1.0, HL_LOW: 1.4, HL_HIGH: 0.7 }

## Real low beams are asymmetric: the kerb-side lamp is kicked up/out to light the verge,
## the oncoming side is aimed lower so it doesn't dazzle. Left lamps take this much EXTRA
## downward pitch at low beam (and a matching outward yaw so the pair covers the full lane
## width instead of two stacked discs). High beam is symmetric — both lamps aim long.
const LOW_LEFT_EXTRA_PITCH := 4.0
const LOW_OUTWARD_YAW := 7.0

## The AIRCRAFT ladder (VehicleSpec.LampStyle), for a wing lamp that is a taxi/landing
## light rather than a headlamp. CLEARANCE is the beacon-and-nav step, so the beam is
## still DARK there — a real aircraft shows no forward beam parked at night. LOW is the
## TAXI beam: wide, short, aimed well down at the ground ahead. HIGH is the LANDING beam:
## narrow, long and near-level, with a tight hotspot. No dip/splay at any level — the
## road car's asymmetry exists to avoid dazzling oncoming traffic.
const AIR_LENS_ENERGY := { HL_OFF: 0.15, HL_CLEARANCE: 0.15, HL_LOW: 2.0, HL_HIGH: 5.0 }
const AIR_ENERGY := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 5.0, HL_HIGH: 16.0 }
const AIR_RANGE := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 25.0, HL_HIGH: 120.0 }
const AIR_ANGLE := { HL_OFF: 38.0, HL_CLEARANCE: 38.0, HL_LOW: 45.0, HL_HIGH: 20.0 }
const AIR_PITCH := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 14.0, HL_HIGH: 2.0 }
const AIR_FALLOFF := { HL_OFF: 1.0, HL_CLEARANCE: 1.0, HL_LOW: 1.2, HL_HIGH: 0.5 }

var _heads: Array[SpotLight3D] = []
## Authored basis per head, captured at setup — the pitch is applied relative to it so a
## scene that aims a lamp off-axis keeps its aim.
var _head_rest: Array[Basis] = []
## -1.0 left / +1.0 right / 0.0 centred lamp (from its authored local X).
var _head_side: Array[float] = []
var _head_mat: StandardMaterial3D
var _rear_mat: StandardMaterial3D
var _turn_l_mat: StandardMaterial3D
var _turn_r_mat: StandardMaterial3D
## One material per steady lens (they differ in colour, so they cannot share).
var _steady_mats: Array[BaseMaterial3D] = []
## One material per flashing lens (the beacon) — same per-lens rule as the steady group.
var _flash_mats: Array[BaseMaterial3D] = []
## True when the spec asks for the AIRCRAFT beam ladder instead of the road-car one.
var _aircraft := false


# --- pure decision (unit-tested) --------------------------------------------

## Rear tri-state: STOP from the brake bit (sloppyCAN's 0x1BB brake bit locally the
## foot brake), else TAIL when the headlights are at clearance or brighter, else OFF.
static func rear_tier(brake_on: bool, headlights: int) -> Rear:
	if brake_on:
		return Rear.STOP
	if headlights >= HL_CLEARANCE:
		return Rear.TAIL
	return Rear.OFF


## Dipped-beam asymmetry for one beam lamp, in degrees: x = EXTRA downward pitch, y =
## outward yaw (+ = to the lamp's left, hence the -side). `side` is -1 left / +1 right /
## 0 centred. Only the road car's low beam is asymmetric — it exists so the kerb-side lamp
## lights the verge while the other stays out of oncoming eyes. An aircraft taxi or landing
## light has no oncoming traffic to dip for, so it stays on its authored aim at every level.
## Whether the beacon lens is in the lit part of its flash at `time_sec`. Phase comes from
## the clock, not an accumulator, so it cannot drift; a non-positive period disables it.
static func beacon_lit(time_sec: float, period: float, on_frac: float) -> bool:
	if period <= 0.0:
		return false
	return fposmod(time_sec, period) < period * clampf(on_frac, 0.0, 1.0)


static func beam_splay(aircraft: bool, headlights: int, side: float) -> Vector2:
	if aircraft or headlights != HL_LOW:
		return Vector2.ZERO
	return Vector2(LOW_LEFT_EXTRA_PITCH if side < 0.0 else 0.0, -side * LOW_OUTWARD_YAW)


# --- setup + application (scene) --------------------------------------------

## Resolve the spec's lamp NodePaths against the vehicle and give the mesh lamps a
## private emissive material so runtime energy changes never touch a shared resource.
func setup(vehicle: Node, spec: VehicleSpec) -> void:
	_aircraft = spec.lamp_style == VehicleSpec.LampStyle.AIRCRAFT
	for p in spec.headlight_paths:
		var n := vehicle.get_node_or_null(p)
		if n is SpotLight3D:
			# Keep the light visible from spawn (energy still drives brightness — a
			# zero-energy spot lights nothing). This forces the renderer to compile the
			# "lit" shader variant during the spawn hitch instead of freezing the frame
			# the player first switches the headlamp on.
			(n as SpotLight3D).visible = true
			_heads.append(n)
			_head_rest.append((n as SpotLight3D).transform.basis)
			# -1 left / +1 right / 0 centred (a lone centre lamp must not splay sideways).
			var head_x := (n as SpotLight3D).position.x
			_head_side.append(0.0 if absf(head_x) < 0.01 else signf(head_x))
	_head_mat = _bind(vehicle, spec.head_lamp_paths, HEAD_LENS_COLOR, HEAD_LENS_ENERGY[HL_OFF])
	_rear_mat = _bind(vehicle, spec.brake_lamp_paths, REAR_COLOR, REAR_ENERGY[Rear.OFF])
	_turn_l_mat = _bind(vehicle, spec.turn_left_paths, TURN_COLOR, TURN_OFF_ENERGY)
	_turn_r_mat = _bind(vehicle, spec.turn_right_paths, TURN_COLOR, TURN_OFF_ENERGY)
	_steady_mats = _bind_scene_colored(vehicle, spec.steady_lamp_paths, STEADY_ENERGY[HL_OFF])
	_flash_mats = _bind_scene_colored(vehicle, spec.flash_lamp_paths, BEACON_OFF_ENERGY)


## One shared emissive material assigned as material_override to every mesh in `paths`
## (they always light together). Returns it so apply() can mutate its energy; null if
## no mesh resolved.
func _bind(vehicle: Node, paths: Array[NodePath], color: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = null
	for p in paths:
		var n := vehicle.get_node_or_null(p)
		if n is MeshInstance3D:
			if mat == null:
				mat = StandardMaterial3D.new()
				mat.albedo_color = color.darkened(0.6)
				mat.emission_enabled = true
				mat.emission = color
				mat.emission_energy_multiplier = energy
			(n as MeshInstance3D).material_override = mat
	return mat


## Marker lenses (steady and flashing) keep the colour the scene authored on them, unlike
## the head/brake/turn groups above which each have one canonical colour. So each gets a
## PRIVATE COPY
## of its own material rather than one shared group material — that is what lets red, green
## and white sit in one group, and it keeps a lens that shares a scene material with a node
## OUTSIDE the group from being lit along with it.
func _bind_scene_colored(vehicle: Node, paths: Array[NodePath], energy: float) -> Array[BaseMaterial3D]:
	var mats: Array[BaseMaterial3D] = []
	for p in paths:
		var n := vehicle.get_node_or_null(p)
		if n is MeshInstance3D:
			var mesh := n as MeshInstance3D
			var src := mesh.get_active_material(0)
			if src is BaseMaterial3D:
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				mat.emission_enabled = true
				mat.emission_energy_multiplier = energy
				mesh.material_override = mat
				mats.append(mat)
	return mats


## Mirror the current lamp state to the scene. brake_on / turn bits come straight from
## VehicleInput (sloppyCAN authoritative when the bridge is live); no timers here.
func apply(brake_on: bool, headlights: int, turn_left: bool, turn_right: bool) -> void:
	# Which beam ladder this vehicle climbs — the road car's parking/dipped/main, or the
	# aircraft's dark/taxi/landing (see the AIR_* tables).
	var lens_table: Dictionary = AIR_LENS_ENERGY if _aircraft else HEAD_LENS_ENERGY
	if _head_mat != null:
		_head_mat.emission_energy_multiplier = lens_table.get(headlights, lens_table[HL_OFF])
	if _rear_mat != null:
		_rear_mat.emission_energy_multiplier = REAR_ENERGY[rear_tier(brake_on, headlights)]
	if _turn_l_mat != null:
		_turn_l_mat.emission_energy_multiplier = TURN_ON_ENERGY if turn_left else TURN_OFF_ENERGY
	if _turn_r_mat != null:
		_turn_r_mat.emission_energy_multiplier = TURN_ON_ENERGY if turn_right else TURN_OFF_ENERGY
	var steady: float = STEADY_ENERGY.get(headlights, STEADY_ENERGY[HL_OFF])
	for m in _steady_mats:
		m.emission_energy_multiplier = steady
	# The beacon flashes only once the master switch is on, and is the ONE lamp here driven
	# by a clock rather than a mirrored bit (the exception documented in the header).
	var lit := headlights >= HL_CLEARANCE and beacon_lit(
			Time.get_ticks_msec() / 1000.0, BEACON_PERIOD, BEACON_ON_FRAC)
	for m in _flash_mats:
		m.emission_energy_multiplier = BEACON_ON_ENERGY if lit else BEACON_OFF_ENERGY

	var range_table: Dictionary = AIR_RANGE if _aircraft else HEAD_RANGE
	var energy: float = (AIR_ENERGY if _aircraft else HEAD_ENERGY).get(headlights, 0.0)
	var angle: float = (AIR_ANGLE if _aircraft else HEAD_ANGLE).get(headlights, 38.0)
	var falloff: float = (AIR_FALLOFF if _aircraft else HEAD_FALLOFF).get(headlights, 1.0)
	# Pitch is a rotation about the lamp's own X (down = negative), applied to the rest
	# basis so repeated calls never accumulate.
	var pitch := -float((AIR_PITCH if _aircraft else HEAD_PITCH).get(headlights, 0.0))
	for i in _heads.size():
		var h := _heads[i]
		# Road low beam only: the kerb-side lamp dips further and both splay outward so the
		# pair reads as one lane-width spread. Zero for an aircraft lamp at every level.
		var splay := beam_splay(_aircraft, headlights, _head_side[i])
		var p := pitch - splay.x
		var yaw := deg_to_rad(splay.y)
		# Stays visible always (energy 0 = lights nothing, costs nothing) so the "lit"
		# shader variant compiled at spawn is never freed — otherwise re-hiding and
		# re-showing would re-trigger the compile hitch.
		h.light_energy = energy
		h.spot_range = range_table.get(headlights, 0.0)
		h.spot_angle = angle
		h.spot_angle_attenuation = falloff
		h.transform.basis = _head_rest[i] * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(p))
