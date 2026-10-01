extends ImplementBase
## Mounted single-disc fertilizer spreader, the implement that uses the most connections.
## Three-point mounted and PTO-driven like the mower, and the only one with a hydraulic remote: the
## slide gate under the hopper outlet follows `scv_flow` (Connection.SCV). Not draft-relevant: the
## disc stays clear of the ground at every hitch position.

## Disc turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto).
const DISC_RATIO := 0.4

## Metres the slide gate travels shut->open along +X (toward the ram). Sized off the authored
## scene: plate leading edge at x=-0.08, outlet neck at x=0, so 0.16 m clears the outlet and fits
## the ram stroke.
const GATE_TRAVEL := 0.16

## Seconds for the ram to run the gate shut to open.
const GATE_TRAVEL_TIME := 1.2

@onready var _spinner: Node3D = $Spinner
@onready var _gate: Node3D = $Gate
@onready var _ram_rod: Node3D = $RamRod

var _gate_shut_x := 0.0    ## authored (shut) X of the gate plate, read at _ready
var _rod_shut_x := 0.0     ## authored (shut) X of the ram rod
var _gate_open := 0.0      ## 0..1 actual opening, slewed toward the commanded flow


func _ready() -> void:
	# The authored pose is the shut pose.
	_gate_shut_x = _gate.position.x
	_rod_shut_x = _ram_rod.position.x


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.SCV | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FERTILIZER


## The gate plate and its rod slide on their own position.x every tick; merged into the root they
## would drag the whole machine's mesh.
func static_merge_skip() -> Array[Node]:
	return [_gate, _ram_rod]


func _process(delta: float) -> void:
	# Vertical axis, like the mower's rotor.
	spin_from_pto(_spinner, delta, DISC_RATIO)
	# scv_flow is the gate's target opening; the ram slews it there (0 with the engine stopped or
	# off the linkage).
	_gate_open = move_toward(_gate_open, clampf(scv_flow, 0.0, 1.0), delta / GATE_TRAVEL_TIME)
	var stroke := _gate_open * GATE_TRAVEL
	_gate.position.x = _gate_shut_x + stroke
	_ram_rod.position.x = _rod_shut_x + stroke  # the rod travels with the plate
