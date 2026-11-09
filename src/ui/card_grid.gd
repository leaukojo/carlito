extends RefCounted
## The card frame and column fit shared by LevelSelect, ChallengeSelect and VehicleSelect. Card
## *content* (screenshot, name strip, selection/refusal state) stays per-selector — only the
## frame and its metrics are common.


## A card's frame: no fill/padding (the thumbnail is the fill), just the hover/focus border.
## `ref` supplies the scale (UiTheme.px reads the Control it's asked to scale for).
static func card_box(ref: Control, border_w: float, lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UiTheme.SURFACE_LO
	s.set_corner_radius_all(int(UiTheme.px(ref, UiTheme.RADIUS)))
	s.border_color = UiTheme.ACCENT if lit else UiTheme.BORDER
	s.set_border_width_all(int(UiTheme.px(ref, border_w)))
	return s


## A bare card Button in the shared frame: border lit while hovered, focused or pressed, and in
## every state when `lit` (selected, done). Clips, so a full-rect thumbnail child stays inside;
## the caller sizes it and fills it.
static func card_button(ref: Control, border_w: float, lit: bool) -> Button:
	var card := Button.new()
	card.clip_contents = true
	for state in ["normal", "disabled"]:
		card.add_theme_stylebox_override(state, card_box(ref, border_w, lit))
	for state in ["hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, card_box(ref, border_w, true))
	return card


## How many `card_w`-wide cards (logical px) fit across `ref` inside the page margins with `gap`
## (scaled px) between them, clamped to 1..min(max_cols, n).
static func columns_for(ref: Control, card_w: float, gap: float, max_cols: int, n: int) -> int:
	var w := UiTheme.px(ref, card_w)
	var avail := ref.size.x - UiTheme.px(ref, UiTheme.MARGIN) * 2.0
	var fits := int(floorf((avail + gap) / (w + gap)))
	return clampi(fits, 1, mini(max_cols, n))
