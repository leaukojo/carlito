class_name DroneBus
extends RefCounted
## The drone's DroneCAN bus: eight nodes (ESCs, GNSS, power, AHRS, rangefinder). Pure static
## logic that DroneVehicle feeds the failure mask and ESC temps to. The roster is declared once
## here; the contract's `node_health` count, the `node_online` / `node_fail` bitfield width and the
## Y-key cycle all read NODES, and growing one without the other stops the local key reaching the
## new node. The roster index is the bit index, not the node id, with `esc_fault` the lone
## exception in esc_index space. An offline node has its command zeroed after the mix,
## uncompensated, publishes CRITICAL and holds its last telemetry.

## uavcan.protocol.NodeStatus health, verbatim — 0 OK / 1 WARNING / 2 ERROR / 3 CRITICAL.
## ERROR is deliberately unreachable today: the craft has only two honest fault sources
## (over-temp ESC, node gone), landing on WARNING/CRITICAL. A test asserts it is never
## returned, so a third fault source is a decision, not a drift.
enum { HEALTH_OK = 0, HEALTH_WARNING = 1, HEALTH_ERROR = 2, HEALTH_CRITICAL = 3 }

## The airframe's bus. `id` is the DroneCAN node ID, `name` labels the node strip, `esc` is
## the esc_index this node drives (-1 if not an ESC). Array index is the bit index, not node id.
## ESCs sit first in esc_index order so the node strip matches the ESC bars; id blocks
## (11-14 motors, 20-23 sensors) follow ordinary DroneCAN per-function static-id practice.
const NODES := [
	{"id": 11, "name": "ESC1", "esc": 0},
	{"id": 12, "name": "ESC2", "esc": 1},
	{"id": 13, "name": "ESC3", "esc": 2},
	{"id": 14, "name": "ESC4", "esc": 3},
	{"id": 20, "name": "GNSS", "esc": -1},
	{"id": 21, "name": "POWER", "esc": -1},
	{"id": 22, "name": "AHRS", "esc": -1},
	{"id": 23, "name": "RANGE", "esc": -1},
]


## How many nodes are on this bus. Never type 8; the contract JSON and InputRouter can't read
## this directly and are pinned against it by test instead.
static func count() -> int:
	return NODES.size()


## Label for roster index `idx`, for the node strip's caption. Out-of-range answers "".
static func name_of(idx: int) -> String:
	if idx < 0 or idx >= count():
		return ""
	return String(NODES[idx]["name"])


## Roster index of the node with this name, or -1. For non-ESC nodes (ESCs use esc_index_of/
## esc_is_online). Resolved once at _ready, not per tick.
static func index_of(node_name: String) -> int:
	for i in count():
		if String(NODES[i]["name"]) == node_name:
			return i
	return -1


## The mask of bits the roster actually uses. Bits above it are ignored, not rejected: a peer
## setting a bit for a node this airframe doesn't have is describing an aircraft we're not.
static func roster_mask() -> int:
	return (1 << count()) - 1


## Is roster index `idx` still on the bus? Out-of-range reads offline (the safe answer).
static func is_online(fail_bits: int, idx: int) -> bool:
	if idx < 0 or idx >= count():
		return false
	return (fail_bits & (1 << idx)) == 0


## The contract `node_online` bitfield: bit i set = roster index i is present and publishing.
## The complement of the failure mask, nothing else — no timer or debounce, since the failure
## is COMMANDED rather than observed (the verbatim-mirror rule).
static func online_bits(fail_bits: int) -> int:
	return ~fail_bits & roster_mask()


## Roster index -> esc_index, or -1 if that node does not drive a motor.
static func esc_index_of(idx: int) -> int:
	if idx < 0 or idx >= count():
		return -1
	return int(NODES[idx]["esc"])


## Is the node driving `esc` still on the bus? Inverse of esc_index_of, for callers walking
## motors (esc_index) rather than roster entries. An esc_index no node drives reads offline.
static func esc_is_online(fail_bits: int, esc: int) -> bool:
	for i in count():
		if esc_index_of(i) == esc:
			return is_online(fail_bits, i)
	return false


## The term `esc_fault` ORs in, IN ESC_INDEX BIT SPACE (bit i = esc_index i, not the roster's).
## A dropped ESC node is a fault even though the ESC can no longer report one itself.
static func offline_esc_bits(fail_bits: int) -> int:
	var bits := 0
	for i in count():
		var esc := esc_index_of(i)
		if esc >= 0 and not is_online(fail_bits, i):
			bits |= 1 << esc
	return bits


## Force an offline ESC's mixer command to ZERO, applied AT THE MOTOR after the mix, so the
## loss is asymmetric (yaw comes from counter-rotating diagonal pairs; one diagonal is now
## half strength). DO NOT rescale, redistribute or desaturate. The COMMAND is zeroed rather
## than `_omega` so the motor spools down through its lag, the disarm shape.
static func gate_commands(cmd: PackedFloat32Array, fail_bits: int) -> PackedFloat32Array:
	var out := cmd.duplicate()
	for i in count():
		var esc := esc_index_of(i)
		if esc < 0 or esc >= out.size():
			continue
		if not is_online(fail_bits, i):
			out[esc] = 0.0
	return out


## One node's health, DERIVED (never injected): offline -> CRITICAL, an ESC over its temp
## warn -> WARNING, else OK. Offline DOMINATES an over-temperature. `esc_temps` may be
## short/empty (not over warn), which lets all_ok() build the default before the craft ticks.
static func health_of(idx: int, fail_bits: int, esc_temps: PackedFloat32Array,
		temp_warn: float) -> int:
	if idx < 0 or idx >= count():
		return HEALTH_CRITICAL
	if not is_online(fail_bits, idx):
		return HEALTH_CRITICAL
	var esc := esc_index_of(idx)
	if esc >= 0 and esc < esc_temps.size() and esc_temps[esc] > temp_warn:
		return HEALTH_WARNING
	return HEALTH_OK


## The contract `node_health` value: a PLAIN Array of exactly count() ints in roster order.
## Plain rather than PackedInt32Array because JSON.stringify wants an ordinary Array for an
## instanced signal — the same rule the ESC arrays follow.
static func health_all(fail_bits: int, esc_temps: PackedFloat32Array,
		temp_warn: float) -> Array:
	var out := []
	out.resize(count())
	for i in count():
		out[i] = health_of(i, fail_bits, esc_temps, temp_warn)
	return out


## A roster-sized all-OK health array — the telemetry default, so a grown roster cannot leave
## it the wrong SHAPE for the bridge on a craft that hasn't ticked yet.
static func all_ok() -> Array:
	return health_all(0, PackedFloat32Array(), INF)


## The Y-key cycle: none -> ESC1 -> ESC2 -> ... -> RANGE -> none, one node failed at a time.
## Shifts the failure one bit left, wrapping to none past the last, over EVERY int (not just
## the eight it normally holds) so a multi-bit mask still terminates at none.
##
## The router mirrors this rule rather than calling it — the router must not depend on a
## vehicle class, so InputRouter.cycle_node_fail carries its own copy (roster length from
## `src/input/subsystem_counts.gd`), pinned equal to this by `tests/test_drone_bus.gd`.
static func cycle_fail(bits: int) -> int:
	var next := maxi(bits << 1, 1)
	return 0 if next > (1 << (count() - 1)) else next
