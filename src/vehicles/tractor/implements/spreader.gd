extends ImplementBase
## Mounted single-disc fertilizer spreader — the implement that uses the most connections.
## Three-point mounted and PTO-driven like the mower, but also the only machine with a hydraulic
## remote: the slide gate under the hopper outlet is fed by a tractor SCV (Connection.SCV), and
## the only implement that reacts to `scv_flow`. Not draft-relevant: the disc stays clear of the
## ground at every hitch position.

## Disc turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto). Higher than the
## mower's rotor: a broadcast disc runs faster than a cutter, and four vanes read cleanly here.
const DISC_RATIO := 0.4

## Metres the slide gate travels shut->open along +X (retracts toward the ram). Sized off the
## authored scene: plate leading edge at x=-0.08, outlet neck at x=0, so 0.16 m clears the outlet
## and matches the ram rod's stroke (0.18 m rod inside the 0.2 m cylinder at full retraction).
const GATE_TRAVEL := 0.16

## Seconds for the ram to run the gate shut to open; the slew makes a flow change readable.
const GATE_TRAVEL_TIME := 1.2

@onready var _spinner: Node3D = $Spinner
@onready var _gate: Node3D = $Gate
@onready var _ram_rod: Node3D = $RamRod

var _gate_shut_x := 0.0    ## authored (shut) X of the gate plate, read at _ready
var _rod_shut_x := 0.0     ## authored (shut) X of the ram rod
var _gate_open := 0.0      ## 0..1 actual opening, slewed toward the commanded flow


func _ready() -> void:
	# Authored pose is the shut pose; offsets are measured off the scene, not duplicated as constants.
	_gate_shut_x = _gate.position.x
	_rod_shut_x = _ram_rod.position.x


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.SCV | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FERTILIZER


## The gate plate and the rod that pushes it both slide on their own position.x every tick —
## StaticMeshMerge must leave them out of the root's merge group or the slide would drag the
## whole machine's merged mesh along with it.
func static_merge_skip() -> Array[Node]:
	return [_gate, _ram_rod]


func _process(delta: float) -> void:
	# Vertical axis, like the mower's rotor: a broadcast disc throws sideways.
	spin_from_pto(_spinner, delta, DISC_RATIO)
	# scv_flow is the spool position, the gate's target opening; the ram runs it there at its
	# own speed (0 with the engine stopped or the moment this comes off the linkage).
	_gate_open = move_toward(_gate_open, clampf(scv_flow, 0.0, 1.0), delta / GATE_TRAVEL_TIME)
	var stroke := _gate_open * GATE_TRAVEL
	_gate.position.x = _gate_shut_x + stroke
	_ram_rod.position.x = _rod_shut_x + stroke  # rigid rod travels with the plate it pushes
