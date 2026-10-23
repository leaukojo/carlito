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

## Empty mass (kg) of the class drawn: an ~800 L single-disc spreader, the Demir DMR SF 800 at
## 150 kg: sourced. Citations: docs/sources.md.
const FRAME_KG := 150.0

## The empty machine's centre in this frame: the area-weighted centroid of its meshes, the open
## hopper and the ring rim taken without their cylinder caps.
const FRAME_CENTRE := Vector3(0.01, 0.56, 0.44)

## Hopper volume (m³) off the scene: an octagonal frustum (CylinderMesh, 8 segments, R 0.8 /
## r 0.2 / h 1.0), area 2√2·r² per section.
const HOPPER_M3 := 0.792

## Fertiliser bulk density (kg/m³): high-density ammonium nitrate prill, 0.90-0.95 t/m³
## (US 5486246): primary. Carried full, one laden mass; nothing empties it.
const LOAD_DENSITY := 950.0

## The load's centre: the frustum's volume centroid, 0.321 m under the 1.34 m rim, over the outlet.
const LOAD_CENTRE := Vector3(0.0, 1.019, 0.55)

## The disc's drive (kW), an ESTIMATE: the throw itself is ~0.3 kW (~0.33 kg/s, 4 ha/h at
## 300 kg/ha, leaving at ~30 m/s), the rest disc drag and the angle box; Pronar's single-disc
## spreader asks an 11 kW tractor, which bounds it. Nothing empties the hopper, so it never varies.
const DISC_KW := 2.0

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


func pto_power_kw(_ground_kmh: float, _ball_lift: float, _soil01: float) -> float:
	return DISC_KW


## Machine plus a full hopper.
func mass_kg() -> float:
	return FRAME_KG + HOPPER_M3 * LOAD_DENSITY


func mass_centre() -> Vector3:
	return VehicleMath.carried_com(FRAME_CENTRE, LOAD_CENTRE, FRAME_KG, HOPPER_M3 * LOAD_DENSITY)


## The disc stays clear of the ground at every hitch position, so the linkage carries it all.
func ground_share() -> float:
	return 0.0


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
