class_name LevelSelect
extends Control
## Level-select: the LEVEL section of the pause menu, not the shell's front door. Walks
## LevelRegistry and emits the chosen scene path. One card per level — its screenshot
## (src/ui/level_thumbs/<id>.png) with the name on a bottom strip, and the registry `desc`
## shown below the grid while a card is hovered/focused. No emoji. Built in code, a transient
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
const STRIP_H := 34.0
## Card frame width, and the inset the screenshot needs so the frame stays visible.
const BORDER_W := 3.0
const MAX_COLUMNS := 4
## Above this the weight reads as a warning: worth flagging before a phone connection commits.
const HEAVY_MB := 8.0

var _desc: Label
var _grid: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the menu
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	var title := Label.new()
	title.text = "CARLITO 2  -  SELECT LEVEL"
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

	_grid = GridContainer.new()
	_grid.columns = 1  # real value set by _reflow once the scroll container has a width
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(_grid)
	scroll.resized.connect(_reflow)

	var first: Button = null
	for entry in LevelRegistry.LEVELS:
		# Dev fixtures are test assets, not shipped content; bake/check tools still walk them.
		if bool(entry.get("dev", false)):
			continue
		var card := _make_card(entry)
		_grid.add_child(card)
		if first == null:
			first = card

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Fixed, so hovering never reflows the grid.
	_desc.custom_minimum_size.y = UiTheme.px(self, 48.0)
	_desc.theme_type_variation = &"Dim"
	col.add_child(_desc)

	# The only Button here that is not a card (tests tell them apart: a card's name is a
	# child Label, never `text`).
	var back := Button.new()
	back.text = "BACK"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(UiTheme.px(self, 200.0), UiTheme.px(self, UiTheme.TOUCH_MIN))
	back.pressed.connect(func() -> void: closed.emit())
	col.add_child(back)

	_reflow()
	if first != null:
		first.grab_focus()  # keyboard/gamepad start point; also fills the description line


## Fit as many cards across as the window allows. Runs on scroll-area resize (incl. theme rebuild).
func _reflow() -> void:
	if _grid == null or _grid.get_child_count() == 0:
		return
	var card_w := UiTheme.px(self, CARD_W)
	var gap := float(_grid.get_theme_constant("h_separation", "GridContainer"))
	var avail := size.x - UiTheme.px(self, UiTheme.MARGIN) * 2.0
	var fits := int(floorf((avail + gap) / (card_w + gap)))
	_grid.columns = clampi(fits, 1, mini(MAX_COLUMNS, _grid.get_child_count()))


## One level card: screenshot behind, name on a bottom strip. The whole card is the Button.
func _make_card(entry: Dictionary) -> Button:
	var level_name := String(entry["name"])
	var desc := String(entry.get("desc", ""))
	var card_w := UiTheme.px(self, CARD_W)

	var card := Button.new()
	card.custom_minimum_size = Vector2(card_w, roundf(card_w * CARD_ASPECT))
	card.clip_contents = true
	card.tooltip_text = desc
	# The card IS the picture: the theme's button padding would inset the screenshot.
	card.add_theme_stylebox_override("normal", CardGrid.card_box(self, BORDER_W, false))
	card.add_theme_stylebox_override("hover", CardGrid.card_box(self, BORDER_W, true))
	card.add_theme_stylebox_override("pressed", CardGrid.card_box(self, BORDER_W, true))
	card.add_theme_stylebox_override("focus", CardGrid.card_box(self, BORDER_W, true))
	card.pressed.connect(_on_level_pressed.bind(String(entry["scene"])))
	card.mouse_entered.connect(_show_desc.bind(desc))
	card.focus_entered.connect(_show_desc.bind(desc))

	# The picture is inset by the border: a StyleBox is the button's background, so a full-rect
	# child paints straight over it and the hover/focus border would be invisible otherwise.
	# Border width stays fixed rather than growing when lit, so the inset never has to move.
	var inset := UiTheme.px(self, BORDER_W)

	var thumb_path := LevelShot.thumb_path(String(entry["id"]))
	if ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = load(thumb_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = inset
		thumb.offset_top = inset
		thumb.offset_right = -inset
		thumb.offset_bottom = -inset
		card.add_child(thumb)
	else:
		# Never shot (or excluded from export): flat plate so it still reads as a card.
		var missing := Label.new()
		missing.text = "no screenshot"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		missing.theme_type_variation = &"Dim"
		missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(missing)

	var strip := ColorRect.new()
	strip.color = UiTheme.SCRIM
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = inset
	strip.offset_right = -inset
	strip.offset_top = -UiTheme.px(self, STRIP_H)
	strip.offset_bottom = -inset
	card.add_child(strip)

	var label := Label.new()
	label.text = level_name
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"Title"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = UiTheme.px(self, 10.0)
	strip.add_child(label)

	# Cost to load, shown before the wait starts. Blank for a level with no bake (the garage).
	var weight := LevelRegistry.weight_text(String(entry["scene"]))
	if not weight.is_empty():
		var w := Label.new()
		w.text = weight
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.theme_type_variation = &"Dim"
		if LevelRegistry.weight_bytes(String(entry["scene"])) > int(HEAVY_MB * 1048576.0):
			w.add_theme_color_override("font_color", UiTheme.WARN)  # semantic: "this one is a wait"
		w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		w.offset_right = -UiTheme.px(self, 10.0)
		strip.add_child(w)

	return card


func _show_desc(text: String) -> void:
	if _desc != null:
		_desc.text = text


func _on_level_pressed(scene_path: String) -> void:
	level_chosen.emit(scene_path)
