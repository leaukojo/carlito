extends RefCounted
## The picture card and column fit shared by LevelSelect, ChallengeSelect and VehicleSelect: the
## frame, the whole thumbnail, the caption under it. What a card says and does (selection,
## refusal, badges) stays per-selector.


## A card's frame: no fill/padding (the thumbnail is the fill), just the hover/focus border.
## `ref` supplies the scale (UiTheme.px reads the Control it's asked to scale for).
static func card_box(ref: Control, border_w: float, rim: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UiTheme.SURFACE_LO
	s.set_corner_radius_all(int(UiTheme.px(ref, UiTheme.RADIUS)))
	s.border_color = rim
	s.set_border_width_all(int(UiTheme.px(ref, border_w)))
	return s


## A bare card Button in the shared frame. `lit` (selected, done) rims it ACCENT in every state;
## otherwise the rim is plain, and UiTheme.HOVER while hovered, focused or pressed, so what the
## cursor is on never reads as what is picked. Clips, so a full-rect thumbnail child stays
## inside; the caller sizes it and fills it.
static func card_button(ref: Control, border_w: float, lit: bool) -> Button:
	var card := Button.new()
	card.clip_contents = true
	var rest := UiTheme.ACCENT if lit else UiTheme.BORDER
	var hot := UiTheme.ACCENT if lit else UiTheme.HOVER
	for state in ["normal", "disabled"]:
		card.add_theme_stylebox_override(state, card_box(ref, border_w, rest))
	for state in ["hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, card_box(ref, border_w, hot))
	return card


## Caption row height under a card's picture, logical px.
const CAPTION_H := 34.0


## A picture card: the thumbnail whole (never cropped), its caption in a row under it, so the
## caption hides none of the picture. The card is the Button and holds no text itself (tests tell
## cards from plain buttons by that). `aspect` is height / width of the thumbnails, `right` an
## optional second caption at the row's right edge (a bake weight). `dim` greys a refused card.
## The caller sizes nothing: every pixel size is read from `ref`'s scale here, so a selector
## rebuilds its cards on a theme change.
static func picture_card(ref: Control, card_w: float, aspect: float, border_w: float, lit: bool,
		thumb_path: String, caption: String, caption_variation := &"Title", right := "",
		right_color := Color.TRANSPARENT, dim := false) -> Button:
	var card := card_button(ref, border_w, lit)
	var inset := UiTheme.px(ref, border_w)
	var w := UiTheme.px(ref, card_w)
	var pic := Vector2(w - inset * 2.0, roundf((w - inset * 2.0) * aspect))
	var cap_h := UiTheme.px(ref, CAPTION_H)
	card.custom_minimum_size = Vector2(w, pic.y + cap_h + inset * 2.0)

	# The picture is inset by the border: a StyleBox is the button's background, so a full-rect
	# child would paint over it and hide the hover / selection border entirely.
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = inset
	stack.offset_top = inset
	stack.offset_right = -inset
	stack.offset_bottom = -inset
	card.add_child(stack)

	if ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = ResourceLoader.load(thumb_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
		thumb.custom_minimum_size = pic
		thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(thumb)
	else:
		var missing := Label.new()  # never shot (or excluded from export): a flat plate
		missing.text = "no screenshot" if not thumb_path.is_empty() else ""  # "" = a card with no picture (NONE)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		missing.theme_type_variation = &"Dim"
		missing.custom_minimum_size = pic
		missing.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(missing)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = cap_h
	var scrim := PanelContainer.new()  # the caption's backing, as the theme's own panel look
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.SCRIM
	box.content_margin_left = UiTheme.px(ref, 10.0)
	box.content_margin_right = UiTheme.px(ref, 10.0)
	scrim.add_theme_stylebox_override("panel", box)
	scrim.add_child(row)
	stack.add_child(scrim)

	var label := Label.new()
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = caption_variation
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if not right.is_empty():
		var side := Label.new()
		side.text = right
		side.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side.theme_type_variation = &"Dim"
		if right_color.a > 0.0:
			side.add_theme_color_override("font_color", right_color)
		row.add_child(side)
	return card


## How many `card_w`-wide cards (logical px) fit across `ref` inside the page margins with `gap`
## (scaled px) between them, clamped to 1..min(max_cols, n).
static func columns_for(ref: Control, card_w: float, gap: float, max_cols: int, n: int) -> int:
	var w := UiTheme.px(ref, card_w)
	var avail := ref.size.x - UiTheme.px(ref, UiTheme.MARGIN) * 2.0
	var fits := int(floorf((avail + gap) / (w + gap)))
	return clampi(fits, 1, mini(max_cols, n))
