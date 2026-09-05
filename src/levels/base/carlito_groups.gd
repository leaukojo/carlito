extends RefCounted
## The scene-tagging vocabulary: SceneTree groups that say what a node is, plus the two
## walks that find tagged nodes. Preloaded, never class_name'd — the baker, export-strip
## plugin, and measure tools all run headless. Tagged in `_init`, not `_enter_tree`: the
## baker walks level scenes and scatter prefab templates that never enter a tree.
## `is_in_group()` works out of the tree; `get_tree().get_nodes_in_group()` does not (and in
## the editor returns every open scene), so the walks below stay walks, scoped to a
## caller-named root — correct as a lookup only in the running game's single level.

## Level content, tagged by the kit helper classes in `kit/helpers/`.
const AUTHORING := &"carlito_authoring"    ## AuthoringRoot — the bake input, freed at runtime
const KIT_PIECE := &"carlito_kit_piece"    ## KitPiece — a placed prefab the baker merges
const ROAD := &"carlito_road"              ## RoadPath — a drawn road/rail curve
const SCATTER := &"carlito_scatter"        ## ScatterBase — a scatter region or canvas

## Runtime content, tagged in `src/levels/base/`.
const LEVEL := &"carlito_level"            ## Level — the one per running game
const PAYLOAD := &"carlito_payload"        ## CargoPayload — what the drone's hook may catch


## First AuthoringRoot at or under `root`, or null; depth-first so the shallowest wins.
static func find_authoring(root: Node) -> Node:
	if root == null:
		return null
	if root.is_in_group(AUTHORING):
		return root
	for child in root.get_children():
		var found := find_authoring(child)
		if found != null:
			return found
	return null


## First AuthoringRoot above `node`, or null — what editor tools gate destructive actions on.
static func authoring_ancestor(node: Node) -> Node:
	var up := node.get_parent() if node != null else null
	while up != null:
		if up.is_in_group(AUTHORING):
			return up
		up = up.get_parent()
	return null
