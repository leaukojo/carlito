extends GdUnitTestSuite
## The collision-layer bit assignment. `src/physics/collision_layers.gd` is the declaration;
## `project.godot`'s `[layer_names]` is the inspector's copy of it, and the numbers are also
## written into every `.baked.scn` and into `cargo_payload.tscn`. FROZEN like `VehicleTelemetry`'s
## `status` bitfield: a new layer appends at bit 8 or above, an existing bit is never renumbered.
##
## The name assertions read `project.godot` as TEXT, because `ProjectSettings.get_setting(name,
## default)` falls back to the engine default and `has_setting()` is true for built-ins whether or
## not the file mentions them — neither can tell "declared" from "absent".

const Layers := preload("res://src/physics/collision_layers.gd")
const PROJECT_FILE := "res://project.godot"

## Bit index (1-based per [layer_names]) -> name -> constant.
const ASSIGNMENT := [
	[1, "Terrain", Layers.TERRAIN],
	[2, "Drivable", Layers.DRIVABLE],
	[3, "Props", Layers.PROPS],
	[4, "Vehicle", Layers.VEHICLE],
	[5, "Payload", Layers.PAYLOAD],
	[6, "Containment", Layers.CONTAINMENT],
	[7, "Trigger", Layers.TRIGGER],
]


func test_bits_are_frozen() -> void:
	for row: Array in ASSIGNMENT:
		assert_int(row[2]).is_equal(1 << (int(row[0]) - 1))


func test_every_layer_is_named_in_project_godot() -> void:
	var f := FileAccess.open(PROJECT_FILE, FileAccess.READ)
	assert_object(f).is_not_null()
	var text := f.get_as_text()
	for row: Array in ASSIGNMENT:
		assert_str(text).contains('3d_physics/layer_%d="%s"' % [row[0], row[1]])


## SOLID omits CONTAINMENT: the drone's sky fan and the chase
## camera both stop seeing the invisible map wall because of this one bit. See the header on
## `Layers.CONTAINMENT` for the failure it prevents.
func test_solid_excludes_containment() -> void:
	assert_int(Layers.SOLID & Layers.CONTAINMENT).is_equal(0)
	assert_int(Layers.SOLID).is_equal(
			Layers.TERRAIN | Layers.DRIVABLE | Layers.PROPS | Layers.VEHICLE | Layers.PAYLOAD)


func test_world_is_solid_plus_containment() -> void:
	assert_int(Layers.WORLD).is_equal(Layers.SOLID | Layers.CONTAINMENT)


## The only two families that move under physics, and therefore the whole of a static body's mask.
func test_dynamic_is_vehicle_and_payload() -> void:
	assert_int(Layers.DYNAMIC).is_equal(Layers.VEHICLE | Layers.PAYLOAD)


## The drown volume fires only because the water Area3D's mask names the vehicle's layer. Nothing
## else asserts this pairing, and getting it wrong breaks drowning SILENTLY.
func test_water_trigger_sees_vehicles() -> void:
	var water := WaterSurface.new()
	add_child(water)
	assert_int(water.collision_layer).is_equal(Layers.TRIGGER)
	assert_int(water.collision_mask & Layers.VEHICLE).is_not_equal(0)
	water.free()


func test_world_bounds_is_containment() -> void:
	var bounds := WorldBounds.new()
	add_child(bounds)
	assert_int(bounds.collision_layer).is_equal(Layers.CONTAINMENT)
	bounds.free()


func test_terrain_is_terrain_layer() -> void:
	var terrain := HeightmapTerrain.new()
	add_child(terrain)
	assert_int(terrain.collision_layer).is_equal(Layers.TERRAIN)
	terrain.free()


## `cargo_payload.gd` restores the AUTHORED layer on release, so the scene is where it lives.
func test_cargo_payload_scene_authors_the_payload_layer() -> void:
	var scene := load("res://src/levels/base/cargo_payload.tscn") as PackedScene
	var crate := scene.instantiate() as RigidBody3D
	assert_int(crate.collision_layer).is_equal(Layers.PAYLOAD)
	assert_int(crate.collision_mask).is_equal(Layers.WORLD)
	crate.free()
