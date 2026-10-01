class_name DroneBus
extends RefCounted
## The drone's DroneCAN bus: the node roster (ESCs, GNSS, power, AHRS, rangefinder), as pure static
## logic over the failure mask. The roster is declared once here; the contract's `node_health`
## count, the `node_online` / `node_fail` bitfield width and the Y-key cycle must all match NODES
## (pinned by `tests/test_drone_bus.gd`). The roster index is the bit index, not the node id;
## `esc_fault` is the lone exception, in esc_index space.

## uavcan.protocol.NodeStatus health. ERROR is unreachable on purpose: the craft has two honest
## fault sources (over-temp ESC, node gone), landing on WARNING/CRITICAL. A test asserts it is
## never returned.
enum { HEALTH_OK = 0, HEALTH_WARNING = 1, HEALTH_ERROR = 2, HEALTH_CRITICAL = 3 }

## `id` is the DroneCAN node ID, `name` labels the node strip, `esc` is the esc_index this node
## drives (-1 if not an ESC). ESCs sit first in esc_index order so the node strip matches the ESC
## bars.
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


## How many nodes are on this bus. The contract JSON and InputRouter cannot read it and are pinned
## against it by test.
static func count() -> int:
	return NODES.size()


## Label for roster index `idx`, for the node strip's caption. Out-of-range answers "".
static func name_of(idx: int) -> String:
	if idx < 0 or idx >= count():
		return ""
	return String(NODES[idx]["name"])


## Roster index of the node with this name, or -1. For non-ESC nodes (ESCs use esc_index_of/
## esc_is_online).
static func index_of(node_name: String) -> int:
	for i in count():
		if String(NODES[i]["name"]) == node_name:
			return i
	return -1


## The mask of bits the roster uses. Bits above it are ignored, not rejected (a peer is describing
## an aircraft this is not).
static func roster_mask() -> int:
	return (1 << count()) - 1


## Is roster index `idx` still on the bus? Out-of-range reads offline (the safe answer).
static func is_online(fail_bits: int, idx: int) -> bool:
	if idx < 0 or idx >= count():
		return false
	return (fail_bits & (1 << idx)) == 0


## The contract `node_online` bitfield: bit i set = roster index i is present. The complement of
## the failure mask with no timer or debounce, since the failure is COMMANDED, not observed.
static func online_bits(fail_bits: int) -> int:
	return ~fail_bits & roster_mask()


## Roster index -> esc_index, or -1 if that node does not drive a motor.
static func esc_index_of(idx: int) -> int:
	if idx < 0 or idx >= count():
		return -1
	return int(NODES[idx]["esc"])


## Is the node driving `esc` still on the bus? An esc_index no node drives reads offline.
static func esc_is_online(fail_bits: int, esc: int) -> bool:
	for i in count():
		if esc_index_of(i) == esc:
			return is_online(fail_bits, i)
	return false


## The term `esc_fault` ORs in, IN ESC_INDEX BIT SPACE (bit i = esc_index i, not the roster's): a
## dropped ESC node is a fault though the ESC can no longer report one.
static func offline_esc_bits(fail_bits: int) -> int:
	var bits := 0
	for i in count():
		var esc := esc_index_of(i)
		if esc >= 0 and not is_online(fail_bits, i):
			bits |= 1 << esc
	return bits


## Zeroes an offline ESC's mixer command AFTER the mix, so the loss is asymmetric (yaw comes from
## counter-rotating diagonal pairs; one diagonal drops to half strength). DO NOT rescale,
## redistribute or desaturate. The COMMAND is zeroed, not `_omega`, so the motor spools down
## through its lag.
static func gate_commands(cmd: PackedFloat32Array, fail_bits: int) -> PackedFloat32Array:
	var out := cmd.duplicate()
	for i in count():
		var esc := esc_index_of(i)
		if esc < 0 or esc >= out.size():
			continue
		if not is_online(fail_bits, i):
			out[esc] = 0.0
	return out


## One node's health, DERIVED: offline -> CRITICAL (dominates over-temperature), an ESC over its
## temp warn -> WARNING, else OK. `esc_temps` may be short or empty (not over warn), so all_ok()
## can build the default before the craft ticks.
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


## The contract `node_health` value: a PLAIN Array of exactly count() ints in roster order (plain,
## not packed: JSON.stringify wants an ordinary Array for an instanced signal).
##
## `node_health` carries neither enum nor range (count > 1 with an enum is parse-rejected, and a
## range would put eight bars on the generated-bar path), so the node signals render only through
## the node strip.
static func health_all(fail_bits: int, esc_temps: PackedFloat32Array,
		temp_warn: float) -> Array:
	var out := []
	out.resize(count())
	for i in count():
		out[i] = health_of(i, fail_bits, esc_temps, temp_warn)
	return out


## A roster-sized all-OK health array: the telemetry default, right-shaped before the first tick.
static func all_ok() -> Array:
	return health_all(0, PackedFloat32Array(), INF)


## The Y-key cycle: none -> ESC1 -> ... -> RANGE -> none, one node failed at a time. Shifts the
## failure one bit left over EVERY int, so a multi-bit mask still terminates at none.
##
## The router must not depend on a vehicle class, so InputRouter.cycle_node_fail carries its own
## copy (roster length from `src/input/subsystem_counts.gd`), pinned equal by `tests/test_drone_bus.gd`.
static func cycle_fail(bits: int) -> int:
	var next := maxi(bits << 1, 1)
	return 0 if next > (1 << (count() - 1)) else next
