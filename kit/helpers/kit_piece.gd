@tool
class_name KitPiece
extends Node3D
## Root of every generated kit prefab (kit/prefabs/**). Carries the one piece of
## bake metadata the level baker needs: how this piece participates in collision
##. Placement is ordinary editor work; the baker finds these
## nodes under the level's AuthoringRoot and merges their meshes per chunk.
##
## Collision modes:
##  - "none"        decoration, no collision at all
##  - "box"         one box (solid buildings, containers)
##  - "footprint"   one box or cylinder (whichever fits tighter) covering only the
##                  area the piece stands on, extruded to full height (trees, posts)
##  - "hull"        one convex hull (props hit from outside)
##  - "multiconvex" several convex hulls (open structures: grandstands, gantries)
##  - "weld"        drivable structure (ramp/bridge/pier): its triangles join the
##                  level's single welded drivable body at bake time
##
## For box/footprint/hull/multiconvex the generator pre-builds the shapes in a "DevCollision"
## StaticBody3D child (so unbaked levels are playable); the baker harvests those
## same shapes into the per-chunk body. "weld" pieces get a dev trimesh that the
## bake replaces with the welded body.

@export_enum("none", "box", "footprint", "hull", "multiconvex", "weld") var collision_mode := "box"


## Duck-typing marker: the baker and export-strip plugin detect kit pieces via
## has_method() so they never depend on class_name cache state in CLI runs.
func is_carlito_kit_piece() -> bool:
	return true
