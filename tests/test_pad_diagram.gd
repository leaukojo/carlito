extends GdUnitTestSuite
## The CONTROLS sheet's drawn pad: its callouts come from ActionRegistry, the L1 set from the same
## list the L1 legend reads, and nothing the text column names is missing from the drawing.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")


## Every family, with every capability on and off: the drawn L1 set is the legend's list, and
## every row the pad reaches (`pad_for` not empty) has a callout on one of the two sets.
func test_the_drawing_covers_what_the_text_column_names() -> void:
	var checked := 0
	for family in _all_families():
		for all_caps in [false, true]:
			var caps := {}
			for cap: String in ActionRegistry.CAP_NOTE:
				caps[cap] = all_caps
			var ctx := ActionRegistry.context(family, false, caps)
			var layer := PadDiagram.callouts(ctx, true)
			var layer_ids := []
			for c in layer:
				if not layer_ids.has(c["entry"]["id"]):
					layer_ids.append(c["entry"]["id"])
			var legend_ids := []
			for entry in ActionRegistry.pad_layer_rows(ctx):
				legend_ids.append(entry["id"])
			assert_array(layer_ids).override_failure_message("%s: L1 set %s, legend %s"
					% [family, layer_ids, legend_ids]).contains_exactly_in_any_order(legend_ids)

			var drawn := {}
			for c in PadDiagram.callouts(ctx, false) + layer:
				assert_bool(PadDiagram.SPOTS.has(c["spot"])) \
					.override_failure_message("callout on unknown spot '%s'" % c["spot"]).is_true()
				if not (c["entry"] as Dictionary).is_empty():
					drawn[c["entry"]["id"]] = true
			for entry in ActionRegistry.entries():
				if not ActionRegistry.relevant_entry(entry, ctx) \
						or ActionRegistry.pad_for(entry) == "":
					continue
				checked += 1
				assert_bool(drawn.has(entry["id"])) \
					.override_failure_message("%s: '%s' (%s) is not on the drawn pad"
							% [family, entry["id"], ActionRegistry.pad_for(entry)]).is_true()
	assert_int(checked).is_greater(50)  # a silently-empty sweep would pass forever


## A stick carries its axis rows and its press; L1 hints at the layer only where there is one.
func test_a_stick_carries_its_axes_and_its_press() -> void:
	var drone := _texts(PadDiagram.callouts(ActionRegistry.context("drone", false, {}), false))
	var horn := PadDiagram.PRESS_PREFIX + String(ActionRegistry.find(&"horn")["label"])
	assert_array(drone.get("l_stick", [])).contains_exactly([
			String(ActionRegistry.find(&"steer")["label"]),
			String(ActionRegistry.find(&"climb")["label"]), horn])
	assert_array(drone.get("r2", [])).contains_exactly([String(ActionRegistry.find(&"drive")["label"])])
	assert_array(drone.get("l1", [])).contains_exactly([PadDiagram.LAYER_HINT])
	var car := _texts(PadDiagram.callouts(ActionRegistry.context("car", false, {}), false))
	assert_bool(car.has("l1")).is_false()
	assert_bool(PadDiagram.callouts(ActionRegistry.context("car", false, {}), true).is_empty()) \
			.is_true()


## A callout the bridge owns right now greys with the sheet's own reason.
func test_a_bridge_owned_callout_greys_with_the_sheets_reason() -> void:
	var diagram: PadDiagram = auto_free(PadDiagram.new())
	diagram.setup(ActionRegistry.context("car", true, {}, true), false)
	add_child(diagram)
	assert_array(Array(diagram.greyed_notes())).contains_exactly([ActionRegistry.BRIDGE_NOTE])
	diagram.setup(ActionRegistry.context("car", false, {}), false)
	assert_array(Array(diagram.greyed_notes())).is_empty()


## Laid out in the tree: wider than the pad by two callout columns, and as tall as the pad.
func test_the_layout_fits_the_pad_and_its_columns() -> void:
	var diagram: PadDiagram = auto_free(PadDiagram.new())
	diagram.setup(ActionRegistry.context("tractor", false, {"pto": true, "lift": true}), true)
	add_child(diagram)
	var pad_w := UiTheme.px(diagram, PadDiagram.PAD_W)
	assert_float(diagram.needed_width()).is_greater(pad_w + 2.0 * UiTheme.px(diagram,
			PadDiagram.COLUMN_GAP))
	assert_float(diagram.custom_minimum_size.y).is_greater_equal(
			pad_w * PadDiagram.PAD_BOTTOM / PadDiagram.PAD_UNITS)


func _texts(callouts: Array[Dictionary]) -> Dictionary:
	var out := {}
	for c in callouts:
		if not out.has(c["spot"]):
			out[c["spot"]] = []
		out[c["spot"]].append(c["text"])
	return out


func _all_families() -> PackedStringArray:
	var out := PackedStringArray()
	for variant in Catalog.VARIANTS:
		var fam: String = Catalog.VARIANTS[variant]["family"]
		if not out.has(fam):
			out.append(fam)
	return out
