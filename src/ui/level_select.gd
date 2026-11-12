class_name LevelSelect
extends Control
## Level-select: the LEVEL section of the pause menu, not the shell's front door. Walks
## LevelRegistry and emits the chosen scene path. One card per level — its screenshot
## (src/ui/level_thumbs/<id>.png) with the name under it, and a panel below the grid giving the
## hovered / focused level's name, registry `desc` and allowed families. No emoji. Built in code, a transient
## overlay the shell frees on pick.
##
## Sizing/colour come from UiTheme; the grid reflows column count to available width, so it
## works on a phone and a 4K monitor.

signal level_chosen(scene_path: String)
signal closed  # BACK / Esc

const CardGrid := preload("res://src/ui/card_grid.gd")

## Card width in logical px (scaled). Height follows the 16:9.5 screenshot aspect.
const CARD_W := 320.0
const CARD_ASPECT := 0.594  ## 190/320, the shape gen_level_thumbs shoots
## Card frame width, and the inset the screenshot needs so the frame stays visible.
const BORDER_W := 3.0
const MAX_COLUMNS := 4
## Above this the weight reads as a warning: worth flagging before a phone connection commits.
const HEAVY_MB := 8.0

var _col: VBoxContainer  ## the whole page, rebuilt when the theme (so every pixel size) changes
var _desc_name: Label
var _desc: Label
var _desc_vehicles: Label
var _shown := {}  ## the registry entry the description panel reads
var _grid: HFlowContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the menu
	add_child(bg)
	_build()


## Card and margin sizes are fixed when built, so a resize rebuilds the page. Deferred: the
## notification arrives while the theme is still propagating through the children being freed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _col != null:
		_rebuild.call_deferred()


func _rebuild() -> void:
	var had_focus := is_inside_tree() and get_viewport().gui_get_focus_owner() != null \
			and _col.is_ancestor_of(get_viewport().gui_get_focus_owner())
	remove_child(_col)
	_col.queue_free()
	_build(String(_shown.get("scene", "")), had_focus)


## `focus_scene` is the level whose card is lit and described; `grab` seats keyboard focus on it.
func _build(focus_scene := "", grab := true) -> void:
	var col := VBoxContainer.new()
	_col = col
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	var title := Label.new()
	title.text = "LEVEL SELECTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	col.add_child(title)

	# Grid scrolls: cards don't fit a small window.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Without this, arrowing onto a card below the fold moves a selection you can't see.
	scroll.follow_focus = true
	col.add_child(scroll)

	# ScrollContainer ignores its child's size flags and pins content top-left, so a shrink-sized
	# grid needs a full-width wrapper to center against.
	var grid_wrap := VBoxContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_wrap)

	_grid = HFlowContainer.new()
	_grid.alignment = FlowContainer.ALIGNMENT_CENTER  # centers a short last row instead of packing it left
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid_wrap.add_child(_grid)
	scroll.resized.connect(_reflow)

	var first: Button = null
	var seated: Button = null
	for entry in LevelRegistry.LEVELS:
		# Dev fixtures are test assets, not shipped content; bake/check tools still walk them.
		if bool(entry.get("dev", false)):
			continue
		var card := _make_card(entry)
		_grid.add_child(card)
		if first == null:
			first = card
		if String(entry["scene"]) == focus_scene:
			seated = card

	col.add_child(_build_description())

	# The only Button here that is not a card (tests tell them apart: a card's name is a
	# child Label, never `text`).
	var back := UiTheme.back_button(self, func() -> void: closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)

	_reflow()
	if first != null:
		_show_entry(LevelRegistry.entry_of(focus_scene) if seated != null else _first_entry())
		if grab:
			(seated if seated != null else first).grab_focus()  # keyboard/gamepad start point


func _first_entry() -> Dictionary:
	for entry in LevelRegistry.LEVELS:
		if not bool(entry.get("dev", false)):
			return entry
	return {}


## The description under the grid: the hovered / focused level's name as the heading, its text at
## body size, and the families its LevelInfo allows. Fixed height, so hovering never reflows the grid.
func _build_description() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = UiTheme.px(self, 110.0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_desc_name = Label.new()
	_desc_name.theme_type_variation = &"Title"
	box.add_child(_desc_name)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_desc)
	_desc_vehicles = Label.new()
	_desc_vehicles.theme_type_variation = &"MutedSmall"
	box.add_child(_desc_vehicles)
	return panel


## Fit as many cards across as the window allows. Runs on scroll-area resize (incl. theme rebuild).
func _reflow() -> void:
	if _grid == null or _grid.get_child_count() == 0:
		return
	var card_w := UiTheme.px(self, CARD_W)
	var gap := float(_grid.get_theme_constant("h_separation"))
	var cols := CardGrid.columns_for(self, CARD_W, gap, MAX_COLUMNS, _grid.get_child_count())
	# HFlowContainer wraps by width, not a column count, so constrain its width to fit exactly
	# `cols` cards per line — ALIGNMENT_CENTER then centers a short last line instead of packing
	# it against the left edge the way GridContainer's fixed column grid did.
	_grid.custom_minimum_size.x = cols * card_w + maxf(cols - 1, 0) * gap


## One level card: screenshot, name and bake weight under it. The whole card is the Button.
func _make_card(entry: Dictionary) -> Button:
	var scene := String(entry["scene"])
	# Cost to load, shown before the wait starts. Blank for a level with no bake (the garage).
	var weight := LevelRegistry.weight_text(scene)
	var heavy := LevelRegistry.weight_bytes(scene) > int(HEAVY_MB * 1048576.0)
	var card := CardGrid.picture_card(self, CARD_W, CARD_ASPECT, BORDER_W, false,
			LevelShot.thumb_path(String(entry["id"])), String(entry["name"]), &"Title", weight,
			UiTheme.WARN if heavy else Color.TRANSPARENT)  # WARN: "this one is a wait"
	card.tooltip_text = String(entry.get("desc", ""))
	card.pressed.connect(_on_level_pressed.bind(scene))
	card.mouse_entered.connect(_show_entry.bind(entry))
	card.focus_entered.connect(_show_entry.bind(entry))
	return card


func _show_entry(entry: Dictionary) -> void:
	_shown = entry
	if _desc == null or entry.is_empty():
		return
	_desc_name.text = String(entry["name"]).to_upper()
	_desc.text = String(entry.get("desc", ""))
	var allowed: Variant = LevelRegistry.allowed_vehicles_of(String(entry["scene"]))
	if allowed == null:
		_desc_vehicles.text = ""
		return
	var families := PackedStringArray()
	for f: String in allowed:
		families.append(f.to_upper())
	_desc_vehicles.text = "VEHICLES: %s" % (", ".join(families) if not families.is_empty() else "ALL")


func _on_level_pressed(scene_path: String) -> void:
	level_chosen.emit(scene_path)
