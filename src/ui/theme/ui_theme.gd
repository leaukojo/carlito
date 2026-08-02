class_name UiTheme
extends RefCounted
## The project's one set of UI design tokens, and the Theme built from them.
##
## Every screen used to carry its own `add_theme_font_size_override` / hand-built StyleBoxFlat
## calls, so "the font is too small" was a dozen separate edits and no two screens agreed on a
## colour. Those live here now: `build(scale)` returns a Theme that `UiScale` assigns to the
## root window, from which every Control inherits it. Screens ask for a ROLE
## (`theme_type_variation = &"Title"`), never a pixel size.
##
## Overrides that survive in the screens are the SEMANTIC ones — a lamp's lit colour, a bar's
## warn red. Those are signal data wearing a colour, not styling, and they do not belong here.
##
## Scaling: this is a Theme built at a given scale rather than a `.tres` asset, because the UI
## scale changes with the window (see ui_scale.gd) and a saved Theme would need every size
## rewritten on every resize anyway. Nothing here touches viewport or render settings —
## measured, `content_scale_factor` and `CONTENT_SCALE_MODE_CANVAS_ITEMS` BOTH resize the 3D
## render target (factor 2.0 turned a 1152x648 window into a 2304x1296 render), which the web
## perf budget cannot pay. See docs/plans/ui_improvements.md.

const FONT := preload("res://src/ui/theme/font/Barlow-Regular.ttf")

# --- colour tokens ------------------------------------------------------------
# One dark instrument palette. Named by ROLE, so a screen never picks a raw colour.

const BG := Color(0.05, 0.06, 0.08, 0.96)        ## full-screen menu backdrop
const SCRIM := Color(0.04, 0.05, 0.07, 0.82)     ## overlay over a live scene
const SURFACE := Color(0.11, 0.13, 0.16, 0.94)   ## panels, cards, buttons
const SURFACE_HI := Color(0.17, 0.20, 0.25, 0.96) ## hovered surface
const SURFACE_LO := Color(0.08, 0.09, 0.11, 0.90) ## pressed / recessed
const BORDER := Color(0.26, 0.30, 0.36, 0.85)
const TEXT := Color(0.90, 0.93, 0.98)
const TEXT_DIM := Color(0.62, 0.67, 0.74)
const TEXT_MUTED := Color(0.42, 0.46, 0.52)      ## disabled
const ACCENT := Color(0.42, 0.72, 1.00)          ## focus ring, progress fill, selection
const WARN := Color(1.00, 0.70, 0.15)
const DANGER := Color(0.95, 0.35, 0.30)
const OK := Color(0.35, 0.85, 0.45)

# --- type scale (logical px at scale 1.0) -------------------------------------

const FS_DISPLAY := 34   ## the one big title on a full-screen menu
const FS_TITLE := 22     ## section headings, card names
const FS_BODY := 17      ## buttons, descriptions — the default
const FS_LABEL := 15     ## dense secondary text
const FS_SMALL := 13     ## the debug overlay and other dev readouts

# --- metrics (logical px at scale 1.0) ----------------------------------------

const RADIUS := 6
const PAD_X := 16
const PAD_Y := 10
const GAP := 14          ## default separation inside a container
const MARGIN := 32       ## full-screen menu edge margin
const TOUCH_MIN := 46    ## minimum touch target edge; below this a finger misses

## Theme type carrying the scale itself, so any Control can recover it from the theme it
## already inherits (`UiTheme.scale_of(self)`) instead of reaching for a global. Rebuilding
## the theme fires NOTIFICATION_THEME_CHANGED, which is how persistent screens learn to relayout.
const SCALE_TYPE := &"Carlito"
const SCALE_CONST := &"scale_pct"


## The UI scale the given Control is currently themed at (1.0 = unscaled).
static func scale_of(c: Control) -> float:
	var pct := c.get_theme_constant(SCALE_CONST, SCALE_TYPE)
	return (float(pct) / 100.0) if pct > 0 else 1.0


## Scale a logical-pixel metric for `c`. Use for anything the theme cannot express —
## a joystick radius, a card size, a fixed anchor offset.
static func px(c: Control, logical: float) -> float:
	return roundf(logical * scale_of(c))


## Build the Theme for a given UI scale. Assigned to the root window by UiScale; every
## Control inherits it from there.
static func build(scale: float) -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = _fs(FS_BODY, scale)
	t.set_constant(SCALE_CONST, SCALE_TYPE, int(roundf(scale * 100.0)))

	_build_label(t, scale)
	_build_button(t, scale)
	_build_panel(t, scale)
	_build_progress(t, scale)
	_build_containers(t, scale)
	return t


static func _fs(logical: int, scale: float) -> int:
	return maxi(8, int(roundf(float(logical) * scale)))


static func _build_label(t: Theme, scale: float) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", _fs(FS_BODY, scale))
	# Roles, addressed by `theme_type_variation`. A screen says what a label IS, not how big.
	for role in [
		["Display", FS_DISPLAY, TEXT],
		["Title", FS_TITLE, TEXT],
		["Dim", FS_LABEL, TEXT_DIM],
		["Small", FS_SMALL, TEXT_DIM],
		# A row that does not apply right now — the CONTROLS sheet's greyed-out controls. Same
		# TEXT_MUTED the theme already uses for a disabled Button, so "unavailable" reads the same
		# whether it is a button or a line of text.
		["Muted", FS_BODY, TEXT_MUTED],
		["MutedSmall", FS_LABEL, TEXT_MUTED],
	]:
		var role_name := StringName(role[0])
		t.set_type_variation(role_name, "Label")
		t.set_font_size("font_size", role_name, _fs(int(role[1]), scale))
		t.set_color("font_color", role_name, role[2])


static func _build_button(t: Theme, scale: float) -> void:
	t.set_font_size("font_size", "Button", _fs(FS_BODY, scale))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_MUTED)
	t.set_stylebox("normal", "Button", _box(SURFACE, scale))
	t.set_stylebox("hover", "Button", _box(SURFACE_HI, scale))
	t.set_stylebox("pressed", "Button", _box(SURFACE_LO, scale))
	t.set_stylebox("disabled", "Button", _box(SURFACE_LO, scale))
	# The focus ring is the keyboard/gamepad affordance the old menus had no visible sign of.
	var focus := _box(SURFACE_HI, scale)
	focus.border_color = ACCENT
	focus.set_border_width_all(maxi(2, int(roundf(2.0 * scale))))
	t.set_stylebox("focus", "Button", focus)

	# `Choice`: a toggle button standing in a RADIO GROUP (the vehicle selector's family column).
	# The base `pressed` box is a press — darker, recessed — and a selection that reads as
	# recessed reads as unavailable. Selected gets the accent border the picture cards already
	# mark their selection with, so the screen speaks one selection language.
	t.set_type_variation(&"Choice", "Button")
	var chosen := _box(SURFACE_LO, scale)
	chosen.border_color = ACCENT
	chosen.set_border_width_all(maxi(2, int(roundf(2.0 * scale))))
	t.set_stylebox("pressed", &"Choice", chosen)
	t.set_stylebox("hover_pressed", &"Choice", chosen)
	t.set_color("font_pressed_color", &"Choice", ACCENT)
	t.set_color("font_hover_pressed_color", &"Choice", ACCENT)

	# `Primary`: the one button on a screen that IS the screen's purpose (the selector's DRIVE).
	# Accent-filled with dark text rather than another dark box among dark boxes — a player was
	# picking a vehicle and never finding the way out of the menu. Disabled keeps the plain recessed
	# box, so a refused DRIVE cannot look like the thing to press.
	t.set_type_variation(&"Primary", "Button")
	t.set_font_size("font_size", &"Primary", _fs(FS_TITLE, scale))
	t.set_stylebox("normal", &"Primary", _box(ACCENT, scale))
	t.set_stylebox("hover", &"Primary", _box(ACCENT.lightened(0.18), scale))
	t.set_stylebox("pressed", &"Primary", _box(ACCENT.darkened(0.22), scale))
	t.set_stylebox("disabled", &"Primary", _box(SURFACE_LO, scale))
	var primary_focus := _box(ACCENT.lightened(0.18), scale)
	primary_focus.border_color = TEXT
	primary_focus.set_border_width_all(maxi(2, int(roundf(2.0 * scale))))
	t.set_stylebox("focus", &"Primary", primary_focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, &"Primary", BG)
	t.set_color("font_disabled_color", &"Primary", TEXT_MUTED)


static func _build_panel(t: Theme, scale: float) -> void:
	t.set_stylebox("panel", "PanelContainer", _box(SURFACE, scale))
	t.set_stylebox("panel", "Panel", _box(SURFACE, scale))


static func _build_progress(t: Theme, scale: float) -> void:
	var bg := _box(SURFACE_LO, scale)
	bg.set_border_width_all(0)
	var fill := _box(ACCENT, scale)
	fill.set_border_width_all(0)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)


static func _build_containers(t: Theme, scale: float) -> void:
	var gap := maxi(4, int(roundf(float(GAP) * scale)))
	t.set_constant("separation", "BoxContainer", gap)
	t.set_constant("separation", "VBoxContainer", gap)
	t.set_constant("separation", "HBoxContainer", gap)
	t.set_constant("h_separation", "GridContainer", gap)
	t.set_constant("v_separation", "GridContainer", gap)


static func _box(bg: Color, scale: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(maxi(2, int(roundf(float(RADIUS) * scale))))
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.content_margin_left = roundf(float(PAD_X) * scale)
	s.content_margin_right = roundf(float(PAD_X) * scale)
	s.content_margin_top = roundf(float(PAD_Y) * scale)
	s.content_margin_bottom = roundf(float(PAD_Y) * scale)
	return s
