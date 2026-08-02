extends ImplementBase
## Mounted single-disc fertilizer spreader — the implement that uses the most connections.
##
## Three-point mounted and PTO-driven like the mower, but it is also the only machine with a
## HYDRAULIC REMOTE: the slide gate under the hopper outlet is fed by a tractor SCV, which is
## why connections() claims Connection.SCV and why the ram is actually modelled beside the
## gate. The 'scv_flow' signal drives that gate through the set_scv seam — this is the one
## machine on the catalog that reacts to it, because it is the only one with the plumbing.
##
## Not draft-relevant: the disc is held clear of the ground at every hitch position, so this
## machine costs the tractor no pull however deep the hitch goes.

## Disc turns per PTO shaft turn — cosmetic legibility gearing, see spin_from_pto. Geared a
## little higher than the mower's rotor because a broadcast disc really does run faster than
## a cutter, and four vanes read cleanly at this rate.
const DISC_RATIO := 0.4

## Metres the slide gate travels between shut and fully open, along the machine's +X (it
## retracts TOWARD the ram, which is how a single-acting slide gate opens). Sized off the
## authored scene, not picked: the plate's leading edge starts at x = -0.08 and the outlet neck
## is at x = 0, so 0.16 m clears the outlet with margin, and the same figure is the ram rod's
## stroke — which lands the 0.18 m rod exactly inside the 0.2 m cylinder body at full
## retraction rather than poking out its far end.
const GATE_TRAVEL := 0.16

## Seconds for the ram to run the gate from shut to fully open. A hydraulic cylinder is not
## instant, and the slew is what makes a flow CHANGE readable rather than a snap.
const GATE_TRAVEL_TIME := 1.2

@onready var _spinner: Node3D = $Spinner
@onready var _gate: Node3D = $Gate
@onready var _ram_rod: Node3D = $RamRod

var _gate_shut_x := 0.0    ## authored (shut) X of the gate plate, read at _ready
var _rod_shut_x := 0.0     ## authored (shut) X of the ram rod
var _gate_open := 0.0      ## 0..1 actual opening, slewed toward the commanded flow


func _ready() -> void:
	# Authored pose IS the shut pose, so the offsets are measured off the scene rather than
	# duplicated as constants here (the mower/plough rule: geometry lives in the .tscn).
	_gate_shut_x = _gate.position.x
	_rod_shut_x = _ram_rod.position.x


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.SCV | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FERTILIZER


func _process(delta: float) -> void:
	# Vertical axis, like the mower's rotor: a broadcast disc throws sideways.
	spin_from_pto(_spinner, delta, DISC_RATIO)
	# The commanded flow is the spool position, so it is the gate's TARGET opening; the ram
	# runs it there at its own speed. scv_flow is whatever the hitch handed down this tick
	# (0 with the engine stopped, and 0 the instant this machine comes off the linkage).
	_gate_open = move_toward(_gate_open, clampf(scv_flow, 0.0, 1.0), delta / GATE_TRAVEL_TIME)
	var stroke := _gate_open * GATE_TRAVEL
	_gate.position.x = _gate_shut_x + stroke
	# The rod is rigid: it travels with the plate it pushes, sliding back into the cylinder.
	_ram_rod.position.x = _rod_shut_x + stroke
