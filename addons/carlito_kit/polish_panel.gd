@tool
extends VBoxContainer
## Scene-wide cleanup passes an author runs after placing things: conform terrain under
## tiles/buildings, paint splat under tiles, tidy loose props, find flying props, and shoot
## the level-select card. UI only; the work lives in tile_conform.gd / placement_tool.gd /
## flying_check.gd / level_shot_tool.gd.

const TileConform := preload("res://addons/carlito_kit/tile_conform.gd")
const FlyingCheck := preload("res://addons/carlito_kit/flying_check.gd")

signal conform_tiles_requested(tile_lift: float, prefab_apron: float)
signal paint_tiles_requested
signal tidy_authoring_requested
signal flag_flying_requested(tolerance: float)
signal clear_flying_requested
signal drop_flying_requested(tolerance: float)
signal set_shot_view_requested
signal shoot_thumb_requested

var _conform_lift: SpinBox
var _conform_apron: SpinBox
var _fly_tolerance: SpinBox


func _init() -> void:
	name = "Polish"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	add_child(_heading("Terrain under what you placed"))
	var ground := HBoxContainer.new()
	add_child(ground)

	var conform_btn := Button.new()
	conform_btn.text = "Conform terrain"
	conform_btn.tooltip_text = "Flatten the terrain under every painted tile GridMap " \
			+ "AND every placed prefab building (Commercial/Industrial/Suburban/Racing " \
			+ "structures) to its base height (footprint incl. multi-cell overhangs, 4 m " \
			+ "fade-out) — the pad-flattening brush pass, automated. Destructive; one undo " \
			+ "step per terrain."
	conform_btn.pressed.connect(func():
		conform_tiles_requested.emit(_conform_lift.value, _conform_apron.value))
	ground.add_child(conform_btn)

	_conform_lift = SpinBox.new()
	_conform_lift.min_value = -1.0
	_conform_lift.max_value = 1.0
	_conform_lift.step = 0.05
	_conform_lift.value = TileConform.DEFAULT_TILE_LIFT
	_conform_lift.suffix = "m"
	_conform_lift.tooltip_text = "Tile lift: how far above the tile base plane the " \
			+ "conformed terrain may rise. Terrain lands on the highest 8-bit heightmap " \
			+ "step at or below base + lift (with a 151 m terrain one step is ~0.6 m), " \
			+ "so raising this closes the terrain-to-tile gap; past the road deck height " \
			+ "(0.24 m) terrain can poke through the roadway."
	ground.add_child(_conform_lift)

	_conform_apron = SpinBox.new()
	_conform_apron.min_value = 0.0
	_conform_apron.max_value = 8.0
	_conform_apron.step = 0.5
	_conform_apron.value = TileConform.DEFAULT_PREFAB_APRON
	_conform_apron.suffix = "m"
	_conform_apron.tooltip_text = "Building apron: flat ground kept around each prefab " \
			+ "building's footprint before the 4 m fade-out starts — larger values push " \
			+ "the terrain drop further from the walls (fixes the pedestal look)."
	ground.add_child(_conform_apron)

	var paint_btn := Button.new()
	paint_btn.text = "Paint splat under tiles"
	paint_btn.tooltip_text = "Paint the terrain splat to Asphalt (channel index 6) under " \
			+ "each painted tile's ACTUAL mesh (a curve paints only the curve), eroded " \
			+ "one splat pixel so it stays hidden — the wheels sample the ground splat " \
			+ "through the tile deck, so an unpainted tile street grips like the grass " \
			+ "beneath it. Run after Conform. Destructive; one undo step per terrain."
	paint_btn.pressed.connect(func(): paint_tiles_requested.emit())
	ground.add_child(paint_btn)

	add_child(HSeparator.new())
	add_child(_heading("Flying props"))
	var fly := HBoxContainer.new()
	add_child(fly)

	var flag_btn := Button.new()
	flag_btn.text = "Flag flying"
	flag_btn.tooltip_text = "Find every placed kit piece hovering above the ground " \
			+ "(roads, tiles and terrain all count as ground) and mark it with a tall " \
			+ "blinking red beacon in the 3D view, its hover printed in the Output panel. " \
			+ "The markers are editor-only — never saved into the scene or the bake."
	flag_btn.pressed.connect(func(): flag_flying_requested.emit(_fly_tolerance.value))
	fly.add_child(flag_btn)

	_fly_tolerance = SpinBox.new()
	_fly_tolerance.min_value = 0.0
	_fly_tolerance.max_value = 10.0
	_fly_tolerance.step = 0.05
	_fly_tolerance.value = FlyingCheck.DEFAULT_TOLERANCE
	_fly_tolerance.suffix = "m"
	_fly_tolerance.tooltip_text = "How far a piece may hover before it counts as flying. " \
			+ "Not every prefab's origin sits exactly on its mesh bottom, so a small " \
			+ "tolerance keeps honest placements quiet."
	fly.add_child(_fly_tolerance)

	var clear_btn := Button.new()
	clear_btn.text = "Clear flags"
	clear_btn.tooltip_text = "Remove the flying-prop markers. (Reloading the scene " \
			+ "clears them too — they only live in the editor.)"
	clear_btn.pressed.connect(func(): clear_flying_requested.emit())
	fly.add_child(clear_btn)

	var drop_btn := Button.new()
	drop_btn.text = "Drop flying"
	drop_btn.tooltip_text = "Move every flagged piece straight down until it rests on " \
			+ "the ground — only its height changes. Re-flags afterwards, so whatever " \
			+ "markers remain are the ones this could not fix (nothing under them). " \
			+ "One undo step."
	drop_btn.pressed.connect(func(): drop_flying_requested.emit(_fly_tolerance.value))
	fly.add_child(drop_btn)

	add_child(HSeparator.new())
	add_child(_heading("Housekeeping"))
	var tidy_row := HBoxContainer.new()
	add_child(tidy_row)

	var tidy_btn := Button.new()
	tidy_btn.text = "Tidy authoring"
	tidy_btn.tooltip_text = "Move every loose kit piece directly under AuthoringRoot into " \
			+ "its per-kit \"<Kit>Props\" folder (created as needed) — reorganizes an " \
			+ "existing level's flat bucket into per-kit groups. GridMaps, roads, and " \
			+ "scatter stay put. One undo step."
	tidy_btn.pressed.connect(func(): tidy_authoring_requested.emit())
	tidy_row.add_child(tidy_btn)

	add_child(HSeparator.new())
	add_child(_heading("Level card (the level-select screenshot)"))
	var card := HBoxContainer.new()
	add_child(card)

	var view_btn := Button.new()
	view_btn.text = "Set thumbnail view"
	view_btn.tooltip_text = "Save the CURRENT 3D viewport framing as this level's " \
			+ "screenshot camera (position, angle and FOV) — fly the view to the shot you " \
			+ "want, then press this. Stored next to the level as <level>_shot.tres; no " \
			+ "node is added, so re-framing never re-stales the bake."
	view_btn.pressed.connect(func(): set_shot_view_requested.emit())
	card.add_child(view_btn)

	var shoot_btn := Button.new()
	shoot_btn.text = "Shoot thumbnail"
	shoot_btn.tooltip_text = "Render the level-select card (src/ui/level_thumbs/<id>.png) " \
			+ "from the saved view — with none saved yet it frames an overview. It RUNS the " \
			+ "level in a second Godot process, so the picture shows the baked world: bake " \
			+ "first, or you shoot stale geometry. Takes a few seconds; the editor waits."
	shoot_btn.pressed.connect(func(): shoot_thumb_requested.emit())
	card.add_child(shoot_btn)

	var hint := Label.new()
	hint.text = "These act on the whole level, not on the next click. Every one is " \
			+ "destructive-by-button; the terrain and prop passes are undoable, the " \
			+ "level-card buttons write files (press again to redo)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	return l
