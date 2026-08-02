# GdUnit generated TestSuite
extends GdUnitTestSuite
## Unit tests for the kit generator's pure logic:
## families-driven classification (ordered first-match), the coverage gate (unaccounted +
## reasonless-exclude failures), catch-all detection, and meshlib id preservation — the
## rules that keep a mis-classified or silently-dropped asset from baking into every level.

const Recipe := preload("res://kit/helpers/kit_recipe.gd")


func _fam(fam_name: String, match_list: Array, pipeline := "prefab", extra := {}) -> Dictionary:
	var f := {"name": fam_name, "match": match_list, "pipeline": pipeline}
	for k in extra:
		f[k] = extra[k]
	return f


# ------------------------------------------------------------------- classify

func test_classify_first_family_wins_by_order() -> void:
	# barrier family precedes the plain-road family: ordering, not lookahead, disambiguates.
	var families := [
		_fam("roads-barrier", ["^road-.*barrier"], "palette"),
		_fam("roads", ["^road-"], "palette"),
	]
	var r := Recipe.classify(["road-straight", "road-straight-barrier"], families)
	assert_that(r.assignments["road-straight"]).is_equal("roads")
	assert_that(r.assignments["road-straight-barrier"]).is_equal("roads-barrier")
	assert_that(r.unaccounted).is_empty()


func test_classify_reports_unaccounted() -> void:
	var families := [_fam("trees", ["^tree"], "prefab")]
	var r := Recipe.classify(["tree_a", "rock_b", "grass"], families)
	assert_that(r.assignments["tree_a"]).is_equal("trees")
	assert_that(r.unaccounted).contains(["rock_b", "grass"])
	assert_int(r.unaccounted.size()).is_equal(2)


func test_classify_counts_per_family() -> void:
	var families := [
		_fam("trees", ["^tree"], "prefab"),
		_fam("props", ["."], "prefab"),  # catch-all
	]
	var r := Recipe.classify(["tree_a", "tree_b", "bench", "cone"], families)
	assert_int(r.counts["trees"]).is_equal(2)
	assert_int(r.counts["props"]).is_equal(2)
	assert_that(r.unaccounted).is_empty()


func test_classify_search_semantics_anchored_vs_free() -> void:
	# "^road" is anchored; "barrier" is a free substring match.
	var families := [
		_fam("barrier", ["barrier"], "palette"),
		_fam("road", ["^road"], "palette"),
	]
	var r := Recipe.classify(["road-end-barrier", "roadside"], families)
	assert_that(r.assignments["road-end-barrier"]).is_equal("barrier")
	assert_that(r.assignments["roadside"]).is_equal("road")


# ------------------------------------------------------------- validate_families

func test_validate_flags_reasonless_exclude() -> void:
	var bad := [_fam("skip", ["^raceCar"], "exclude")]
	assert_int(Recipe.validate_families(bad).size()).is_equal(1)
	var good := [_fam("skip", ["^raceCar"], "exclude", {"reason": "hand-built vehicles"})]
	assert_that(Recipe.validate_families(good)).is_empty()


func test_validate_flags_missing_patterns_and_name() -> void:
	var errs := Recipe.validate_families([{"name": "", "match": [], "pipeline": "prefab"}])
	assert_int(errs.size()).is_equal(2)  # no name + no patterns


func test_validate_flags_duplicate_names() -> void:
	# Duplicate names collide in classify counts + gen's fam_by_name -> silent misroute.
	var dup := [_fam("props", ["^a"]), _fam("props", ["^b"])]
	assert_int(Recipe.validate_families(dup).size()).is_equal(1)
	assert_that(Recipe.validate_families([_fam("a", ["^a"]), _fam("b", ["^b"])])).is_empty()


# --------------------------------------------------------------- is_catch_all

func test_is_catch_all_detects_universal_patterns() -> void:
	assert_bool(Recipe.is_catch_all(_fam("p", ["."]))).is_true()
	assert_bool(Recipe.is_catch_all(_fam("p", [".*"]))).is_true()
	assert_bool(Recipe.is_catch_all(_fam("p", ["^tree"]))).is_false()
	assert_bool(Recipe.is_catch_all(_fam("p", ["^road", "."]))).is_true()  # any pattern


# -------------------------------------------------------------- assign_item_ids

func test_assign_item_ids_preserves_existing() -> void:
	# Painted GridMaps reference these ids: road-a keeps 0, road-b keeps 5.
	var existing := {"road-a": 0, "road-b": 5}
	var ids := Recipe.assign_item_ids(existing, ["road-a", "road-b", "road-c"])
	assert_int(ids["road-a"]).is_equal(0)
	assert_int(ids["road-b"]).is_equal(5)
	assert_int(ids["road-c"]).is_equal(6)  # appended after max existing


func test_assign_item_ids_fresh_start_from_zero() -> void:
	# Clean-slate regen: no existing meshlib -> ids restart at 0 in order.
	var ids := Recipe.assign_item_ids({}, ["b", "a", "c"])
	assert_int(ids["b"]).is_equal(0)
	assert_int(ids["a"]).is_equal(1)
	assert_int(ids["c"]).is_equal(2)


func test_assign_item_ids_removed_item_leaves_gap() -> void:
	# road-b (id 5) no longer emitted; its id is retired, new items still avoid collisions.
	var existing := {"road-a": 0, "road-b": 5}
	var ids := Recipe.assign_item_ids(existing, ["road-a", "road-d"])
	assert_int(ids["road-a"]).is_equal(0)
	assert_int(ids["road-d"]).is_equal(6)
	assert_bool(ids.has("road-b")).is_false()
