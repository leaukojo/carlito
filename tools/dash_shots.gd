extends Control
## Dev utility: the FULL dashboard of each family, drawn over a grey backdrop with every ranged
## "out" signal at a sample value, saved to reports/dash_shots/<family>_<ui size %>.png (the
## cluster's panel, cropped). For reviewing the cluster's layout without driving each body. Must
## run WINDOWED (a headless run renders nothing).
##
##   & $GODOT --path . --resolution 1280x720 res://tools/dash_shots.tscn -- [scale=<0.7..1.6>]
##       [families=truck,boat]

const OUT_DIR := "res://reports/dash_shots/"
const FAMILIES: PackedStringArray = ["car", "tractor", "truck", "train", "boat", "plane", "drone"]
## Telemetry class per family, the one its body carries.
const TELEMETRY := {
	"car": preload("res://src/vehicles/base/vehicle_telemetry.gd"),
	"tractor": preload("res://src/vehicles/tractor/tractor_telemetry.gd"),
	"truck": preload("res://src/vehicles/truck/truck_telemetry.gd"),
	"train": preload("res://src/vehicles/train/train_telemetry.gd"),
	"boat": preload("res://src/vehicles/boat/boat_telemetry.gd"),
	"plane": preload("res://src/vehicles/plane/plane_telemetry.gd"),
	"drone": preload("res://src/vehicles/drone/drone_telemetry.gd"),
}
## Where in its range a sample bar sits.
const FILL := 0.62
## The hand-built instruments' readings, so no needle or number reads a blank.
const SAMPLE := {
	"kmh": 72.0, "rpm": 1450.0, "gear_byte": 6, "heading": 30.0, "twd": 250.0, "tws": 6.0,
	"awa": -40.0, "aws": 8.5, "cog": 38.0, "sog": 4.2, "depth": 12.5, "pitch": 4.0, "roll": -6.0,
	"odo": 123.4, "engine_hours": 1234.5, "speed_limit": 90,
}
const SETTLE_FRAMES := 6
const MARGIN := 12  ## px of backdrop kept round the cropped panel

var _ui: UiScale
var _dash: Dashboard


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ui_size := float(_flag(args, "scale=", "1.0"))
	var families := FAMILIES
	if _flag(args, "families=", "") != "":
		families = PackedStringArray(_flag(args, "families=", "").split(","))
	var layer := CanvasLayer.new()
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.42, 0.46, 0.50)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	_ui = UiScale.new()
	layer.add_child(_ui)
	_ui.set_user_scale(ui_size)
	_dash = Dashboard.new()
	_dash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_dash)
	_dash.set_density_setting(Dashboard.Density.FULL)
	_dash.set_shown(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for family in families:
		await _shoot(family, ui_size)
	get_tree().quit(0)


func _shoot(family: String, ui_size: float) -> void:
	GameState.current_vehicle = family
	_dash.bind(null)
	var telem: VehicleTelemetry = (TELEMETRY[family] as GDScript).new()
	_fill(telem, family)
	_dash._telem = telem
	_dash._resolve_fields()
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("headless run renders nothing (run windowed)")
		return
	var panel := _dash.get_child(_dash.get_child_count() - 1) as Control
	var rect := Rect2i(panel.get_global_rect()).grow(MARGIN)
	var img := get_viewport().get_texture().get_image()
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := "%s%s_%d.png" % [OUT_DIR, family, roundi(ui_size * 100.0)]
	img.get_region(rect).save_png(ProjectSettings.globalize_path(path))
	print("%s: %s (%d x %d)" % [family, ProjectSettings.globalize_path(path), rect.size.x,
			rect.size.y])


## Every ranged numeric "out" signal the telemetry carries at FILL of its range, then SAMPLE.
func _fill(telem: VehicleTelemetry, family: String) -> void:
	for sig in Contract.data.signals_for_vehicle(family, "out"):
		if sig.range.size() != 2 or sig.has_enum() or sig.type == "bool":
			continue
		var cur: Variant = telem.get(sig.name)
		if cur == null:
			continue
		var v := float(sig.range[0]) + FILL * (float(sig.range[1]) - float(sig.range[0]))
		if typeof(cur) == TYPE_ARRAY:
			var arr: Array = (cur as Array).duplicate()
			arr.resize(sig.count)
			for i in sig.count:
				arr[i] = v * (0.8 + 0.1 * i)
			telem.set(sig.name, arr)
		elif typeof(cur) == TYPE_INT:
			telem.set(sig.name, roundi(v))
		else:
			telem.set(sig.name, v)
	for key: String in SAMPLE:
		if telem.get(key) != null:
			telem.set(key, SAMPLE[key])


static func _flag(args: PackedStringArray, prefix: String, default: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return default
