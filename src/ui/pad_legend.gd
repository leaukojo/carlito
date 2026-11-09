class_name PadLegend
extends PanelContainer
## The gamepad's hold-L1 layer, listed while L1 is held: the vehicle's own controls sit there and
## are otherwise hard to remember. Generated from ActionRegistry and gated as the CONTROLS sheet
## is: rows the vehicle cannot use are left out, a bridge-owned one greyed. The shell shows it on
## PadLayer.layer_changed (`show_layer`) and owns when; this owns nothing. No emoji.

## Shown when the layer is empty here (a car tows nothing), so L1 doing nothing reads as meant.
const EMPTY_TEXT := "Nothing on L1 for this vehicle"

var _grid: GridContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left edge, mid-height: clear of the road ahead, the top-edge notices and the bottom cluster.
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	add_child(col)
	var title := Label.new()
	title.text = "L1"
	title.theme_type_variation = &"Title"
	col.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = 2
	col.add_child(_grid)
	_place()


## List the layer as it answers in `ctx` (ActionRegistry.context) and show it.
func show_layer(ctx: Dictionary) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var rows := ActionRegistry.pad_layer_rows(ctx)
	if rows.is_empty():
		_add(_label("", &"Dim"))
		_add(_label(EMPTY_TEXT, &"Muted"))
	for entry in rows:
		var applies := ActionRegistry.applies_entry(entry, ctx)
		_add(_label(ActionRegistry.pad_for(entry).trim_prefix(PadLayer.LAYER_NAME),
				&"Dim" if applies else &"MutedSmall"))
		_add(_label(String(entry["label"]), &"" if applies else &"Muted"))
	visible = true


func _add(label: Label) -> void:
	_grid.add_child(label)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


## The edge inset is a theme-scaled metric, so it follows UI SIZE.
func _place() -> void:
	offset_left = UiTheme.px(self, UiTheme.MARGIN)
	offset_top = 0.0
	offset_bottom = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _grid != null:
		_place()
