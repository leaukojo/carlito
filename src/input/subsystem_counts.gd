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

## Positions on the boat autopilot's mode switch (contract 'nav_mode') — the length of the
## local 2 cycle: STANDBY, HEADING_HOLD.
const NAV_MODES := 2

## Detents on the sailboat's sheet (contract 'sheet') — the length of the local 3 cycle. Five, so
## the ladder reaches both ends and the useful middle: hauled in, close-hauled, reach, broad and
## fully eased. Unlike the other counts here nothing structural pins it — the wire carries a
## continuous 0..1 and the detents are only how a keyboard reaches it, so growing this is safe
## where growing BODY_CMD or FLIGHT_MODES is not.
const SHEET_DETENTS := 5
