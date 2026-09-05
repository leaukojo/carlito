extends GdUnitTestSuite
## The scene tags the baker, the export plugin and the drone's hook select on.
##
## Every tag goes on in `_init`, not `_enter_tree`: LevelBaker.bake is handed a level scene that
## need not be in any tree, and it instantiates every scatter prefab template loose. An
## `_enter_tree` tag never fires for either, and the level bakes CLEAN and ships empty — no error,
## just missing geometry.

const Groups := preload("res://src/levels/base/carlito_groups.gd")
const AuthoringRootScript := preload("res://kit/helpers/authoring_root.gd")
const KitPieceScript := preload("res://kit/helpers/kit_piece.gd")
const RoadPathScript := preload("res://kit/helpers/road_path.gd")
const ScatterRegionScript := preload("res://kit/helpers/scatter_region.gd")
const CargoPayloadScript := preload("res://src/levels/base/cargo_payload.gd")
const LevelScript := preload("res://src/levels/base/level.gd")


func test_every_tagged_class_carries_its_group_outside_the_tree() -> void:
	var cases := {
		Groups.AUTHORING: AuthoringRootScript,
		Groups.KIT_PIECE: KitPieceScript,
		Groups.ROAD: RoadPathScript,
		Groups.SCATTER: ScatterRegionScript,
		Groups.PAYLOAD: CargoPayloadScript,
		Groups.LEVEL: LevelScript,
	}
	for group: StringName in cases:
		var node: Node = (cases[group] as GDScript).new()
		auto_free(node)
		assert_bool(node.is_in_group(group)) \
			.override_failure_message("%s is not in '%s' before entering the tree" % [
				node.get_script().resource_path.get_file(), group]) \
			.is_true()


func test_find_authoring_reaches_a_nested_root_outside_the_tree() -> void:
	# The shape the baker actually meets: the AuthoringRoot is a child of the level, not the
	# node it is handed. Nothing here is ever added to a tree.
	var level: Node = LevelScript.new()
	auto_free(level)
	var holder := Node3D.new()
	level.add_child(holder)
	var authoring: Node = AuthoringRootScript.new()
	holder.add_child(authoring)

	assert_object(Groups.find_authoring(level)).is_same(authoring)
	assert_object(Groups.find_authoring(holder)).is_same(authoring)
	var bare := Node3D.new()
	auto_free(bare)
	assert_object(Groups.find_authoring(bare)).is_null()


func test_authoring_ancestor_looks_up_and_never_at_itself() -> void:
	var authoring: Node = AuthoringRootScript.new()
	auto_free(authoring)
	var piece: Node = KitPieceScript.new()
	authoring.add_child(piece)

	assert_object(Groups.authoring_ancestor(piece)).is_same(authoring)
	# The root is not its OWN ancestor — the editor tools gate on "am I inside the subtree".
	assert_object(Groups.authoring_ancestor(authoring)).is_null()
