class_name UiTheme
extends RefCounted
## The project's one set of UI design tokens, and the Theme built from them. `build(scale)`
## returns a Theme UiScale assigns to the root window; screens ask for a role
## (`theme_type_variation = &"Title"`), never a pixel size. Only semantic overrides survive
## in screens (a lamp's lit colour, a bar's warn red).
##
## Built fresh per scale (not a `.tres` asset) since UI scale changes with the window. Touches
## no viewport/render setting — the engine's content-scale options resize the 3D render
## target, which the web perf budget cannot pay.

const FONT := preload("res://src/ui/theme/font/Barlow-Regular.ttf")

# --- colour tokens ------------------------------------------------------------
# One dark instrument palette. Named by ROLE, so a screen never picks a raw colour.

const BG := Color(0.05, 0.06, 0.08, 0.96)        ## full-screen menu backdrop
const SCRIM := Color(0.04, 0.05, 0.07, 0.82)     ## overlay over a live scene
const SURFACE := Color(0.11, 0.13, 0.16, 0.94)   ## panels, cards, buttons
const SURFACE_HI := Color(0.17, 0.20, 0.25, 0.96) ## hovered surface
const SURFACE_LO := Color(0.08, 0.09, 0.11, 0.90) ## pressed / recessed
const BORDER := Color(0.26, 0.30, 0.36, 0.85)
const RIM := Color(0.27, 0.47, 0.65)             ## a button's keycap rim (ACCENT, darkened)
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

## Theme type carrying the scale itself, so a Control can recover it via `UiTheme.scale_of(self)`
## instead of a global. Rebuilding fires NOTIFICATION_THEME_CHANGED, how screens learn to relayout.
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
		# Same TEXT_MUTED as a disabled Button, so "unavailable" reads the same either way.
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
	t.set_stylebox("normal", "Button", keycap(SURFACE, RIM, scale))
	t.set_stylebox("hover", "Button", keycap(SURFACE_HI, ACCENT, scale))
	t.set_stylebox("pressed", "Button", _pushed(keycap(SURFACE_LO, RIM, scale)))
	# Flat, grey rim: a refused button must not look like a key waiting to be pressed.
	t.set_stylebox("disabled", "Button", _pushed(keycap(SURFACE_LO, BORDER, scale)))
	# The focus ring is the keyboard/gamepad affordance: without it nothing shows where focus is.
	t.set_stylebox("focus", "Button", _ringed(keycap(SURFACE_HI, ACCENT, scale), scale))

	# `Choice`: a toggle standing in a radio group (vehicle selector's family column). Selected
	# gets the accent border, not the darker recessed `pressed` box, so selection never reads as
	# a press.
	t.set_type_variation(&"Choice", "Button")
	var chosen := _ringed(keycap(SURFACE_LO, ACCENT, scale), scale)
	t.set_stylebox("pressed", &"Choice", chosen)
	t.set_stylebox("hover_pressed", &"Choice", chosen)
	t.set_color("font_pressed_color", &"Choice", ACCENT)
	t.set_color("font_hover_pressed_color", &"Choice", ACCENT)

	# `Primary`: the button that IS the screen's purpose (the selector's DRIVE). Accent-filled
	# with dark text so it stands out among dark boxes. Disabled keeps the plain recessed box, so
	# a refused DRIVE cannot look like the thing to press.
	t.set_type_variation(&"Primary", "Button")
	t.set_font_size("font_size", &"Primary", _fs(FS_TITLE, scale))
	var primary_rim := ACCENT.darkened(0.45)
	t.set_stylebox("normal", &"Primary", keycap(ACCENT, primary_rim, scale))
	t.set_stylebox("hover", &"Primary", keycap(ACCENT.lightened(0.18), primary_rim, scale))
	t.set_stylebox("pressed", &"Primary", _pushed(keycap(ACCENT.darkened(0.22), primary_rim, scale)))
	t.set_stylebox("disabled", &"Primary", _pushed(keycap(SURFACE_LO, BORDER, scale)))
	t.set_stylebox("focus", &"Primary",
			_ringed(keycap(ACCENT.lightened(0.18), TEXT, scale), scale))
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


## The one button look: a raised key — thin rim, deeper bottom lip, light drop shadow. Theme
## Buttons and the touch overlay's pads both take it, so a pad and a menu row read as one kind.
static func keycap(bg: Color, rim: Color, scale: float) -> StyleBoxFlat:
	var s := _box(bg, scale)
	s.set_corner_radius_all(maxi(2, int(roundf(float(RADIUS + 2) * scale))))
	s.border_color = rim
	s.border_width_bottom = maxi(2, int(roundf(3.0 * scale)))
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	s.shadow_size = maxi(1, int(roundf(2.0 * scale)))
	s.shadow_offset = Vector2(0.0, roundf(scale))
	return s


## A keycap with a 2 px rim all round (focus, selection), keeping its bottom lip.
static func _ringed(s: StyleBoxFlat, scale: float) -> StyleBoxFlat:
	var w := maxi(2, int(roundf(2.0 * scale)))
	var lip := s.border_width_bottom
	s.set_border_width_all(w)
	s.border_width_bottom = maxi(w, lip)
	return s


## A keycap held down: the lip and the shadow go, so it sits flush.
static func _pushed(s: StyleBoxFlat) -> StyleBoxFlat:
	s.border_width_bottom = 1
	s.shadow_size = 0
	return s


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
