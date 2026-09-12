class_name DroneIndicators
extends RefCounted
## The airframe's own status lights and the rangefinder beam. Owned by DroneVehicle and ticked LAST,
## so everything shown is this tick's published state. Tested in tests/test_drone_indicators.gd.
##
## Not the bus `led` channel (LampSet mirrors that onto the arm tips): each light here belongs to a
## node and shows that node's own state, the way a real ESC, GNSS puck or smart battery lights
## itself. Steady colours, one per state, and no timer: a pattern would need a clock, and the
## project has none (test_lamps scans this file for one). Every node is optional, so an airframe
## without them runs this on a no-op path.

## One colour per state. OFF is no light at all: the lens drops to its dark housing.
const OFF := Color(0.0, 0.0, 0.0)
const BLUE := Color(0.15, 0.4, 1.0)
const GREEN := Color(0.1, 1.0, 0.25)
const AMBER := Color(1.0, 0.55, 0.0)
const RED := Color(1.0, 0.08, 0.05)
const HOUSING := Color(0.05, 0.05, 0.05)
## Bars on the pack's gauge, each a quarter of the charge.
const GAUGE_BARS := 4

var _fc: StandardMaterial3D = null
var _gps: StandardMaterial3D = null
## Null entries for a missing node, so the index stays the bar / esc_index.
var _bars: Array[StandardMaterial3D] = []
var _escs: Array[StandardMaterial3D] = []
## Roster index of each ESC's node, esc_index order, resolved from DroneBus.NODES once.
var _esc_nodes := PackedInt32Array()
var _beam: MeshInstance3D = null
## Where the beam leaves the airframe, body-local: the node's authored position.
var _lens := Vector3.ZERO


func _init(body: Node3D) -> void:
	_fc = _bind(body, ^"FcLed")
	_gps = _bind(body, ^"GpsLed")
	for i in GAUGE_BARS:
		_bars.append(_bind(body, NodePath("BattBar%d" % i)))
	for esc in DroneProp.MOTORS.size():
		_escs.append(_bind(body, NodePath("EscLed%d" % esc)))
		_esc_nodes.append(_roster_of_esc(esc))
	_beam = body.get_node_or_null(^"RangeBeam") as MeshInstance3D
	if _beam != null:
		_lens = _beam.position
		# Posed in WORLD space every tick: the rangefinder casts straight down whatever the
		# attitude, so the beam must not tilt with the airframe.
		_beam.top_level = true
		_beam.visible = false


## `power_ok` is the key-and-pack master switch the arming block computed this tick: without it
## there is no flight controller to light its LED. The node lights follow what their nodes publish.
func tick(t: DroneTelemetry, power_ok: bool, body: Node3D) -> void:
	_light(_fc, fc_color(power_ok, t.arming_state, t.failsafe))
	_light(_gps, gps_color(t.fix_type))
	var lit := soc_bars(t.soc)
	var gauge := gauge_color(t.soc)
	for i in _bars.size():
		_light(_bars[i], gauge if i < lit else OFF)
	for esc in _escs.size():
		var node := _esc_nodes[esc]
		var health := int(t.node_health[node]) if node >= 0 and node < t.node_health.size() \
				else DroneBus.HEALTH_CRITICAL
		_light(_escs[esc], health_color(health))
	if _beam != null:
		var lens := body.global_transform * _lens
		var length := beam_length(t.agl, body.global_position.y - lens.y)
		_beam.visible = length > 0.0
		if length > 0.0:
			_beam.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, length, 1.0)),
					lens + Vector3.DOWN * (length * 0.5))


# --- what each light says (pure, unit-tested) --------------------------------------------------

## The flight controller: dark with no power, red over any failsafe (a failsafe outranks the
## arming state, since it can force a mode on an armed craft), else one colour per arming state.
static func fc_color(power_ok: bool, arming_state: int, failsafe: int) -> Color:
	if not power_ok:
		return OFF
	if failsafe != DroneArming.FS_NONE:
		return RED
	match arming_state:
		DroneArming.ARMED:
			return GREEN
		DroneArming.BLOCKED:
			return AMBER
	return BLUE


## The GNSS puck: green on a 3D fix, amber on 2D, red on anything less. An offline receiver
## publishes an empty sky, so it reads red too.
static func gps_color(fix_type: int) -> Color:
	match fix_type:
		DroneSensors.FIX_3D:
			return GREEN
		DroneSensors.FIX_2D:
			return AMBER
	return RED


## A bus node's derived health, as the node strip reads it: an ESC over its temperature warn is
## WARNING, one off the bus CRITICAL.
static func health_color(code: int) -> Color:
	match code:
		DroneBus.HEALTH_OK:
			return GREEN
		DroneBus.HEALTH_WARNING:
			return AMBER
	return RED


## Bars lit for a charge (%): each bar is a quarter, lit while any of its quarter remains.
static func soc_bars(soc: float) -> int:
	return clampi(ceili(soc * GAUGE_BARS / 100.0), 0, GAUGE_BARS)


## The gauge turns red exactly where the aircraft decides to come home: SOC_LOW is the contract's
## `soc` warn, pinned by test.
static func gauge_color(soc: float) -> Color:
	return RED if soc < DroneArming.SOC_LOW else GREEN


## Beam length (m) from a lens `lens_drop` metres below the origin the rangefinder casts from, down
## to the ground it measured. 0 means no beam: no return, or the RANGE node off the bus (-1 both).
static func beam_length(agl: float, lens_drop: float) -> float:
	if agl < 0.0:
		return 0.0
	return maxf(agl - lens_drop, 0.0)


# --- scene ------------------------------------------------------------------------------------

## A private emissive material on the LED at `path`, or null when the airframe has no such node.
static func _bind(body: Node, path: NodePath) -> StandardMaterial3D:
	var mesh := body.get_node_or_null(path) as MeshInstance3D
	if mesh == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mesh.material_override = mat
	_light(mat, OFF)
	return mat


## Lit LEDs share LampSet's indication-LED energies, so every LED on the airframe reads alike.
static func _light(mat: StandardMaterial3D, col: Color) -> void:
	if mat == null:
		return
	var lit := col != OFF
	mat.emission = col if lit else HOUSING
	mat.albedo_color = col.darkened(0.6) if lit else HOUSING
	mat.emission_energy_multiplier = LampSet.LED_ON_ENERGY if lit else LampSet.LED_OFF_ENERGY


static func _roster_of_esc(esc: int) -> int:
	for i in DroneBus.count():
		if DroneBus.esc_index_of(i) == esc:
			return i
	return -1
