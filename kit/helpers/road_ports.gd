class_name RoadPorts
extends RefCounted
## Pure port math for RoadPath <-> roads-GridMap endpoint snapping (see
## docs/level_kit.md). A "port" is the edge-center of an occupied cell face that the
## tile's road actually crosses, per the recipe's `ports` table (kit/import/roads.json)
## rotated by the cell's orientation basis — fully computable from the GridMap lattice,
## no junction math, RoadBuilder untouched. The editor draw tool snaps RoadPath
## endpoints to these; the snap only writes ordinary Curve3D point data.
##
## Baker-safe (no editor APIs) and headless-testable: like the baker's _collect_gridmap,
## the GridMap's world transform is passed in explicitly so untreed GridMaps work.
## Covered by tests/test_road_ports.gd.
##
## v1 caveat (documented in the recipe too): face openness is judged by GridMap cell
## occupancy alone — a neighbor cell visually covered by another tile's overhang but
## never painted counts as open. Centered multi-cell pieces whose road ends land on
## half-cell planes (road-curve, road-split) have no table entry on purpose.

## Local face -> outward cell-space normal. Only horizontal faces exist: tiles never
## carry road through their top/bottom.
const FACES := {
	"+x": Vector3i(1, 0, 0),
	"-x": Vector3i(-1, 0, 0),
	"+z": Vector3i(0, 0, 1),
	"-z": Vector3i(0, 0, -1),
}


## Compile the recipe's `ports` section for enumerate_ports. Invalid faces/regexes are
## skipped here (validate() reports them); an absent section yields zero entries.
## Returns { surface_y: float, entries: [{ regexes: [RegEx], ports: [{cell: Vector3i,
## face: Vector3i}] }] }.
static func parse_table(recipe: Dictionary) -> Dictionary:
	var src: Dictionary = recipe.get("ports", {})
	var entries := []
	for e: Dictionary in src.get("entries", []):
		var regexes: Array[RegEx] = []
		for p in e.get("match", []):
			var re := RegEx.create_from_string(String(p))
			if re != null and re.is_valid():
				regexes.append(re)
		var ports := []
		for port: Dictionary in e.get("ports", []):
			var face: Vector3i = FACES.get(String(port.get("face", "")), Vector3i.ZERO)
			var cell: Array = port.get("cell", [0, 0])
			if face == Vector3i.ZERO or cell.size() != 2:
				continue
			ports.append({"cell": Vector3i(int(cell[0]), 0, int(cell[1])), "face": face})
		entries.append({"regexes": regexes, "ports": ports})
	return {"surface_y": float(src.get("surface_y", 0.0)), "entries": entries}


## Recipe-shape validation independent of any GridMap (mirrors KitRecipe
## .validate_families). Returns human-readable error strings (empty == valid).
static func validate(recipe: Dictionary) -> Array:
	var errors: Array[String] = []
	var src: Dictionary = recipe.get("ports", {})
	if src.is_empty():
		return errors  # a kit without ports is fine
	var entries: Array = src.get("entries", [])
	for i in entries.size():
		var e: Dictionary = entries[i]
		var matches: Array = e.get("match", [])
		if matches.is_empty():
			errors.append("ports entry %d has no match patterns" % i)
		for p in matches:
			# create_from_string returns a non-null but invalid RegEx on bad patterns
			var re := RegEx.create_from_string(String(p))
			if re == null or not re.is_valid():
				errors.append("ports entry %d has invalid regex '%s'" % [i, str(p)])
		var ports: Array = e.get("ports", [])
		if ports.is_empty():
			errors.append("ports entry %d lists no ports" % i)
		for port: Dictionary in ports:
			var face := String(port.get("face", ""))
			if not FACES.has(face):
				errors.append("ports entry %d has invalid face '%s'" % [i, face])
			var cell: Array = port.get("cell", [0, 0])
			if cell.size() != 2:
				errors.append("ports entry %d has malformed cell %s" % [i, str(port.get("cell"))])
	return errors


## Enumerate every open port of a painted roads GridMap, in deterministic (sorted-cell)
## order. `xform` is the GridMap's world transform (pass gm.global_transform when it is
## in a tree). Each port: { position: Vector3 (world edge-center at the asphalt surface),
## normal: Vector3 (world outward face normal), cell: Vector3i (the port's home cell) }.
static func enumerate_ports(gm: GridMap, table: Dictionary,
		xform := Transform3D.IDENTITY) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ml := gm.mesh_library
	if ml == null or table.get("entries", []).is_empty():
		return out
	var surface_y := float(table.get("surface_y", 0.0))
	var cs := gm.cell_size
	var by_item := {}  # item id -> matched ports Array (cached per item)
	var cells := gm.get_used_cells()
	cells.sort()
	for cell: Vector3i in cells:
		var item := gm.get_cell_item(cell)
		if not by_item.has(item):
			by_item[item] = _ports_for_name(ml.get_item_name(item), table)
		var ports: Array = by_item[item]
		if ports.is_empty():
			continue
		var cell_basis := gm.get_basis_with_orthogonal_index(
				gm.get_cell_item_orientation(cell))
		for port: Dictionary in ports:
			# rotate the anchor-relative home-cell offset and face normal into the
			# painted orientation; roundi guards float noise from the basis product
			var off_r: Vector3 = cell_basis * Vector3(port["cell"] as Vector3i)
			var home := cell + Vector3i(roundi(off_r.x), 0, roundi(off_r.z))
			var n_r: Vector3 = cell_basis * Vector3(port["face"] as Vector3i)
			var face := Vector3i(roundi(n_r.x), 0, roundi(n_r.z))
			if gm.get_cell_item(home + face) != GridMap.INVALID_CELL_ITEM:
				continue  # neighbor occupied -> the tiles already join, no port
			var local := gm.map_to_local(home) \
					+ Vector3(face.x * cs.x * 0.5, surface_y, face.z * cs.z * 0.5)
			out.append({
				"position": xform * local,
				"normal": (xform.basis * Vector3(face)).normalized(),
				"cell": home,
			})
	return out


## Nearest port by horizontal (XZ) distance — a click on terrain beside a raised deck
## should still snap up onto it; the port carries its own Y. Sorted enumeration order
## breaks ties (first wins). Returns {} when none is within max_dist.
static func nearest_port(ports: Array, point: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for p: Dictionary in ports:
		var pos: Vector3 = p["position"]
		var d := Vector2(pos.x - point.x, pos.z - point.z).length()
		if d <= max_dist and d < best_d:
			best_d = d
			best = p
	return best


## First matching entry wins (KitRecipe.classify semantics). Empty array == no ports.
static func _ports_for_name(name: String, table: Dictionary) -> Array:
	for entry: Dictionary in table.get("entries", []):
		for re: RegEx in entry.get("regexes", []):
			if re.search(name) != null:
				return entry.get("ports", [])
	return []
