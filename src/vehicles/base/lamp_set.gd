class_name LampSet
extends RefCounted
## Applies lamp state to the scene-authored lamp nodes a VehicleSpec names by NodePath, relative
## to the vehicle root; transforms live in the model scene.
##
## sloppyCAN is the sole authority on lamp state: brake tier, turn bits, headlight level, beacon
## and strobe are all mirrored verbatim, and there is no local blink timer anywhere in the
## project. A lamp blinks because the source toggles its bit, J1939-73 DM1 flash-1Hz/2Hz on the
## truck included. Do not add a timer here for anything.

## Rear tri-state: STOP (brake) > TAIL (headlights on) > OFF (dim housing, never invisible).
enum Rear { OFF, TAIL, STOP }

## Headlight levels. These mirror the contract 'lights' enum values exactly.
const HL_OFF := 1
const HL_CLEARANCE := 2
const HL_LOW := 3
const HL_HIGH := 4

## Emissive energy per rear tier; OFF keeps a dim housing glow so the lens stays visible.
const REAR_ENERGY := { Rear.OFF: 0.15, Rear.TAIL: 0.7, Rear.STOP: 3.5 }
const REAR_COLOR := Color(0.95, 0.06, 0.03)

## Turn lens: dark amber when off (still visible), bright amber when lit.
const TURN_OFF_ENERGY := 0.12
const TURN_ON_ENERGY := 3.5
const TURN_COLOR := Color(1.0, 0.5, 0.0)

## Head lens emissive energy per headlight level: the SpotLight3D is a beam, not a surface, so
## this is the glow on the lamp face itself. OFF keeps a dim housing glow.
const HEAD_LENS_ENERGY := {HL_OFF: 0.15, HL_CLEARANCE: 0.8, HL_LOW: 3.0, HL_HIGH: 5.0}
const HEAD_LENS_COLOR := Color(1.0, 0.96, 0.85)

## Steady marker lenses (plane nav lights): dim housing glow off, one steady level from clearance
## up. Colour is scene-authored; see _bind_scene_colored.
const STEADY_ENERGY := { HL_OFF: 0.15, HL_CLEARANCE: 2.2, HL_LOW: 2.2, HL_HIGH: 2.2 }

## Flashing lens groups (beacon, wing-tip strobes): only energy lives here. The rate is the
## source's, via the `beacon` / `strobe` bits, and the colour is scene-authored.
const BEACON_ON_ENERGY := 4.5
const BEACON_OFF_ENERGY := 0.15
const STROBE_ON_ENERGY := 7.0  ## brightest lamp on the airframe on purpose
const STROBE_OFF_ENERGY := 0.15

## Indication LEDs (drone arm tips): colour is commanded, so only energy lives here. Word 0
## (black, also the absent-bridge default) is commanded-off and drops to housing glow.
const LED_ON_ENERGY := 4.0
const LED_OFF_ENERGY := 0.15

## Headlight SpotLight3D energy + range per level (distinct per state).
const HEAD_ENERGY := { HL_OFF: 0.0, HL_CLEARANCE: 1.2, HL_LOW: 7.5, HL_HIGH: 14.0 }
const HEAD_RANGE := { HL_OFF: 0.0, HL_CLEARANCE: 8.0, HL_LOW: 32.0, HL_HIGH: 90.0 }

## Beam shape per level. The Compatibility renderer has no light projectors, so the cone itself
## expresses low beam (wide, short, downward) against high beam (narrow, near-level, long throw).
## HEAD_ANGLE is spot_angle (half-angle, degrees), HEAD_PITCH the downward aim applied to the
## scene-authored basis, HEAD_FALLOFF the cone-edge exponent (higher = tighter hotspot).
const HEAD_ANGLE := { HL_OFF: 38.0, HL_CLEARANCE: 36.0, HL_LOW: 44.0, HL_HIGH: 38.0 }
const HEAD_PITCH := { HL_OFF: 0.0, HL_CLEARANCE: 12.0, HL_LOW: 11.0, HL_HIGH: 1.5 }
const HEAD_FALLOFF := { HL_OFF: 1.0, HL_CLEARANCE: 1.0, HL_LOW: 1.4, HL_HIGH: 0.7 }

## Real low beams are asymmetric: the kerb-side lamp is kicked up and out for the verge, the
## oncoming side aimed lower to avoid dazzle. Left lamps get this extra downward pitch at low
## beam plus a matching outward yaw; high beam is symmetric.
const LOW_LEFT_EXTRA_PITCH := 4.0
const LOW_OUTWARD_YAW := 7.0

## Aircraft ladder (VehicleSpec.LampStyle): CLEARANCE stays dark (no forward beam parked at
## night), LOW is the taxi beam (wide, short, down), HIGH is landing (narrow, long, tight
## hotspot). No dip or splay, which is a road-car-only anti-dazzle measure.
const AIR_LENS_ENERGY := { HL_OFF: 0.15, HL_CLEARANCE: 0.15, HL_LOW: 2.0, HL_HIGH: 5.0 }
const AIR_ENERGY := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 5.0, HL_HIGH: 16.0 }
const AIR_RANGE := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 25.0, HL_HIGH: 120.0 }
const AIR_ANGLE := { HL_OFF: 38.0, HL_CLEARANCE: 38.0, HL_LOW: 45.0, HL_HIGH: 20.0 }
const AIR_PITCH := { HL_OFF: 0.0, HL_CLEARANCE: 0.0, HL_LOW: 14.0, HL_HIGH: 2.0 }
const AIR_FALLOFF := { HL_OFF: 1.0, HL_CLEARANCE: 1.0, HL_LOW: 1.2, HL_HIGH: 0.5 }

var _heads: Array[SpotLight3D] = []
## Authored basis per head, captured at setup so pitch applies relative to a scene that aims a
## lamp off-axis.
var _head_rest: Array[Basis] = []
## -1.0 left / +1.0 right / 0.0 centred lamp (from its authored local X).
var _head_side: Array[float] = []
var _head_mat: StandardMaterial3D
var _rear_mat: StandardMaterial3D
var _turn_l_mat: StandardMaterial3D
var _turn_r_mat: StandardMaterial3D
## One material per steady lens (differ in colour, so can't share).
var _steady_mats: Array[BaseMaterial3D] = []
## One material per flashing lens. Beacon and strobes are separate switches on a real aircraft,
## run at different times, so they are two groups.
var _flash_mats: Array[BaseMaterial3D] = []
var _strobe_mats: Array[BaseMaterial3D] = []
## Shared material for the indication-LED group (arm tips light as one lamp).
var _led_mat: StandardMaterial3D = null
## True when the spec asks for the aircraft beam ladder instead of the road-car one.
var _aircraft := false
## Every lens mesh _bind / _bind_scene_colored touched (see bound_meshes).
var _bound: Array[Node] = []


# --- pure decision (unit-tested) --------------------------------------------

## Rear tri-state: STOP from the brake bit (0x1BB), else TAIL at clearance or brighter, else OFF.
static func rear_tier(brake_on: bool, headlights: int) -> Rear:
	if brake_on:
		return Rear.STOP
	if headlights >= HL_CLEARANCE:
		return Rear.TAIL
	return Rear.OFF


## Decode a packed indication-LED word into a colour. The low 16 bits are RGB565
## (uavcan.equipment.indication.LightsCommand): red 15-11, green 10-5, blue 4-0. Bits above 15
## are ignored rather than rejected, since a richer LightsCommand describes hardware this
## airframe lacks. Alpha is always opaque; the wire carries none.
static func led_color(packed: int) -> Color:
	# Each field is scaled by its own max (31/63/31) so full scale is really 1.0; a plain
	# shift-and-divide-by-256 tops out at 0.97 and can never make white.
	return Color(
			float((packed >> 11) & 0x1F) / 31.0,
			float((packed >> 5) & 0x3F) / 63.0,
			float(packed & 0x1F) / 31.0)


## Dipped-beam asymmetry for one lamp, in degrees: x = extra downward pitch, y = outward yaw.
## `side` is -1 left / +1 right / 0 centred. Road-car low beam only.
static func beam_splay(aircraft: bool, headlights: int, side: float) -> Vector2:
	if aircraft or headlights != HL_LOW:
		return Vector2.ZERO
	return Vector2(LOW_LEFT_EXTRA_PITCH if side < 0.0 else 0.0, -side * LOW_OUTWARD_YAW)


# --- setup + application (scene) --------------------------------------------

## Every lens mesh setup() bound, as a copy. StaticMeshMerge callers pass it as a skip list: a lens
## folded into a merged sibling would be hidden, and its material with it. Recorded at bind time
## rather than re-read off the spec, so a new lamp group cannot be merged away unnoticed.
func bound_meshes() -> Array[Node]:
	return _bound.duplicate()


## Resolve the spec's lamp NodePaths against the vehicle and give the mesh lamps a private
## emissive material so runtime energy changes never touch a shared resource.
func setup(vehicle: Node, spec: VehicleSpec) -> void:
	_aircraft = spec.lamp_style == VehicleSpec.LampStyle.AIRCRAFT
	for p in spec.headlight_paths:
		var n := vehicle.get_node_or_null(p)
		if n is SpotLight3D:
			# Visible from spawn (energy 0 still lights nothing) so the "lit" shader variant
			# compiles during the spawn hitch, not when the player first switches it on.
			(n as SpotLight3D).visible = true
			_heads.append(n)
			_head_rest.append((n as SpotLight3D).transform.basis)
			# -1 left / +1 right / 0 centred (a lone centre lamp must not splay).
			var head_x := (n as SpotLight3D).position.x
			_head_side.append(0.0 if absf(head_x) < 0.01 else signf(head_x))
	_head_mat = _bind(vehicle, spec.head_lamp_paths, HEAD_LENS_COLOR, HEAD_LENS_ENERGY[HL_OFF])
	_rear_mat = _bind(vehicle, spec.brake_lamp_paths, REAR_COLOR, REAR_ENERGY[Rear.OFF])
	_turn_l_mat = _bind(vehicle, spec.turn_left_paths, TURN_COLOR, TURN_OFF_ENERGY)
	_turn_r_mat = _bind(vehicle, spec.turn_right_paths, TURN_COLOR, TURN_OFF_ENERGY)
	_steady_mats = _bind_scene_colored(vehicle, spec.steady_lamp_paths, STEADY_ENERGY[HL_OFF])
	_flash_mats = _bind_scene_colored(vehicle, spec.flash_lamp_paths, BEACON_OFF_ENERGY)
	_strobe_mats = _bind_scene_colored(vehicle, spec.strobe_lamp_paths, STROBE_OFF_ENERGY)
	# Indication LEDs share one material like head/brake/turn; the colour is written from the bus
	# each tick, so the bind colour here is the dark housing until commanded.
	_led_mat = _bind(vehicle, spec.led_lamp_paths, Color(0.05, 0.05, 0.05), LED_OFF_ENERGY)


## One shared emissive material assigned as material_override to every mesh in `paths`, which all
## light together. Returned so apply() can mutate its energy; null if none resolved.
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
			_bound.append(n)
	return mat


## Marker lenses (steady and flashing) keep the colour the scene authored, unlike head/brake/turn
## which share one canonical colour. Each gets a private duplicate of its own material, so red,
## green and white can sit in one group and a node outside the group sharing the same scene
## material does not light too. Read back through `material_override` a correctly-lit marker
## returns null; use a `_marker_mat()` helper (see test_tow_host / test_trailer) instead.
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
				mesh.set_surface_override_material(0, mat)
				mats.append(mat)
				_bound.append(mesh)
	return mats


## Mirror the current lamp state to the scene. Every argument is a bit or value off VehicleInput,
## and there is no timer, fade or clock anywhere below. `beacon` and `strobe` default false for
## callers with no flashing lamps (TowedBody).
func apply(brake_on: bool, headlights: int, turn_left: bool, turn_right: bool,
		led: int = 0, beacon: bool = false, strobe: bool = false) -> void:
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
	# Flashing groups are mirrored verbatim, gated only on the master switch and never a timer: an
	# unpowered aircraft's lamp stays dark whatever the bus says.
	var powered := headlights >= HL_CLEARANCE
	for m in _flash_mats:
		m.emission_energy_multiplier = BEACON_ON_ENERGY if (powered and beacon) else BEACON_OFF_ENERGY
	for m in _strobe_mats:
		m.emission_energy_multiplier = STROBE_ON_ENERGY if (powered and strobe) else STROBE_OFF_ENERGY

	# Commanded colour mirrored verbatim; word 0 (black = commanded off) drops to housing glow
	# rather than an invisible black emissive.
	if _led_mat != null:
		var led_col := led_color(led)
		_led_mat.emission = led_col
		_led_mat.albedo_color = led_col.darkened(0.6)
		_led_mat.emission_energy_multiplier = LED_OFF_ENERGY if led == 0 else LED_ON_ENERGY

	var range_table: Dictionary = AIR_RANGE if _aircraft else HEAD_RANGE
	var energy: float = (AIR_ENERGY if _aircraft else HEAD_ENERGY).get(headlights, 0.0)
	var angle: float = (AIR_ANGLE if _aircraft else HEAD_ANGLE).get(headlights, 38.0)
	var falloff: float = (AIR_FALLOFF if _aircraft else HEAD_FALLOFF).get(headlights, 1.0)
	# Rotation about the lamp's own X (down = negative), applied to the rest basis so repeated
	# calls never accumulate.
	var pitch := -float((AIR_PITCH if _aircraft else HEAD_PITCH).get(headlights, 0.0))
	for i in _heads.size():
		var h := _heads[i]
		var splay := beam_splay(_aircraft, headlights, _head_side[i])
		var p := pitch - splay.x
		var yaw := deg_to_rad(splay.y)
		# Stays visible always (energy 0 lights nothing) so the "lit" shader variant compiled
		# at spawn is never freed, avoiding a re-compile hitch on hide/show.
		h.light_energy = energy
		h.spot_range = range_table.get(headlights, 0.0)
		h.spot_angle = angle
		h.spot_angle_attenuation = falloff
		h.transform.basis = _head_rest[i] * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(p))
