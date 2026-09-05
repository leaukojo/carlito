extends RefCounted
## Leaf constants: positions per cycled subsystem control. Both InputRouter and vehicle classes
## preload this, avoiding a router->vehicle dependency. Counts intrinsic to a structure are
## pinned by tests — grow without the constant and the local key silently stops reaching the
## new position while the bridge can still command it.

## Positions on the refuse body's command stalk (contract 'body_cmd'): Idle, Lift, Dump, Lower.
const BODY_CMD := 4

## Nodes on the drone's DroneCAN bus (contract 'node_fail') — the length of the local Y cycle
## and the used width of the `node_fail` / `node_online` bitfields.
const DRONE_NODES := 8

## Positions on the drone's flight-mode ladder (contract 'flight_mode') — the length of the
## local Z cycle: STABILIZE, ALT_HOLD, LOITER, RTL, LAND.
const FLIGHT_MODES := 5
