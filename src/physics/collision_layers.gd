extends RefCounted
## The project's 3D physics collision layers, and the composite masks built from them.
##
## Reached by `preload()`, never `class_name`: the baker and measure tools run headless,
## where class_name cache state is unreliable and a layer resolving to 0 puts a body nowhere.
##
## Bit assignment is frozen: written into `project.godot`'s `[layer_names]`, every
## `.baked.scn`, and `cargo_payload.tscn`. A new layer appends at bit 8+; none is renumbered.

## Ground: `HeightmapTerrain`'s HeightMapShape3D, and the flat strip the measure tools build.
const TERRAIN := 1 << 0
## The level-wide welded body the baker emits — roads, ramps, anything drivable (standing rule 1).
const DRIVABLE := 1 << 1
## The baker's per-chunk prefab bodies: boxes and hulls for scenery you can bump into.
const PROPS := 1 << 2
## `BaseVehicle` and `TowedBody`. Every wagon, trailer and implement is on this too.
const VEHICLE := 1 << 3
## `CargoPayload` — a crate the drone's hook can pick up. Zeroed while carried, then restored to
## this layer (see `cargo_payload.gd`, which reads its authored layer rather than a literal).
const PAYLOAD := 1 << 4
## `WorldBounds`: the map's containment box, invisible walls a few tens of metres off the
## coast reaching 1500 m up. A sensor asking "what is actually out there" must not see them:
## without this bit left out of `SOLID`, the drone's GNSS fan loses half its satellites over
## open water and the chase camera pulls in against a wall that isn't there.
const CONTAINMENT := 1 << 5
## Area3D volumes that detect rather than collide — currently only `WaterSurface`'s drown volume.
const TRIGGER := 1 << 6

## Everything a body can rest on, drive over or bump into. The default mask for every gameplay
## ray. Deliberately WITHOUT `CONTAINMENT` — see that constant.
const SOLID := TERRAIN | DRIVABLE | PROPS | VEHICLE | PAYLOAD
## What a MOVING body must collide with: the solid world plus the box that keeps it inside it.
const WORLD := SOLID | CONTAINMENT
## What a STATIC body needs in its mask — the only bodies in the game that move under physics.
const DYNAMIC := VEHICLE | PAYLOAD
