class_name LoadingScreen
extends Control
## Loading overlay shown while a level scene streams in (threaded load in boot.gd). Plain
## text + progress bar over the level's own card screenshot, no emoji. Built in code, a
## transient overlay the shell frees once the level is up.
##
## `set_level()` dresses it: the shell hands over the path, the screen looks the rest up
## itself (LevelRegistry). A level with no card or an unregistered scene falls back to plain dark.

## Progress-bar footprint in logical px (scaled through UiTheme).
const BAR_SIZE := Vector2(340, 16)
## How far the backdrop is dimmed. The picture is context, not the subject: the text on top of
## it has to stay the thing you read.
const BACKDROP_DIM := 0.30

var _bar: ProgressBar = null
var _name: Label = null
var _title: Label = null
var _weight: Label = null
var _backdrop: TextureRect = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks while loading
	add_child(bg)

	# Created empty; a level without a card leaves it blank rather than rearranging the screen.
	_backdrop = TextureRect.new()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate = Color(BACKDROP_DIM, BACKDROP_DIM, BACKDROP_DIM)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.theme_type_variation = &"Display"
	_name.visible = false
	col.add_child(_name)

	# Second billing once a level name is up, else two Display lines stacked fight each other.
	_title = Label.new()
	_title.text = "LOADING"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.theme_type_variation = &"Display"
	col.add_child(_title)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(
			UiTheme.px(self, BAR_SIZE.x), UiTheme.px(self, BAR_SIZE.y))
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	col.add_child(_bar)

	_weight = Label.new()
	_weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weight.theme_type_variation = &"Dim"
	_weight.visible = false
	col.add_child(_weight)


## Dress the screen for the level loading: name, card picture as backdrop, and the same
## weight the level-select card promised. Safe with an unregistered path (dev fixtures).
func set_level(scene_path: String) -> void:
	var entry := LevelRegistry.entry_of(scene_path)
	if entry.is_empty():
		return
	_name.text = String(entry["name"]).to_upper()
	_name.visible = true
	_title.theme_type_variation = &"Dim"

	var thumb_path := LevelShot.thumb_path(String(entry["id"]))
	if ResourceLoader.exists(thumb_path):
		_backdrop.texture = load(thumb_path)

	var weight := LevelRegistry.weight_text(scene_path)
	_weight.text = weight
	_weight.visible = not weight.is_empty()


func set_progress(p: float) -> void:
	if _bar != null:
		_bar.value = clampf(p, 0.0, 1.0)
