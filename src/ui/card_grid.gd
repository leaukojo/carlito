extends RefCounted
## The card frame shared by LevelSelect and VehicleSelect. Card *content* (screenshot, name
## strip, selection/refusal state) stays per-selector — only the frame and its metrics are
## common.


## A card's frame: no fill/padding (the thumbnail is the fill), just the hover/focus border.
## `ref` supplies the scale (UiTheme.px reads the Control it's asked to scale for).
static func card_box(ref: Control, border_w: float, lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UiTheme.SURFACE_LO
	s.set_corner_radius_all(int(UiTheme.px(ref, UiTheme.RADIUS)))
	s.border_color = UiTheme.ACCENT if lit else UiTheme.BORDER
	s.set_border_width_all(int(UiTheme.px(ref, border_w)))
	return s
