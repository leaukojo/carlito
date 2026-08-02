class_name UiScale
extends Control
## The root of every on-screen Control, and the thing that keeps them legible: it rebuilds the
## theme (UiTheme) whenever the window changes shape and assigns it to ITSELF, so the whole UI
## subtree below inherits one scaled theme. The shell parents its transient overlays here too,
## which is how they get themed without asking.
##
## It is a CONTROL, and the theme goes on this node rather than on the root Window, because a
## Control under a CanvasLayer does NOT inherit the Window's theme — measured on 4.7.1: a
## Control parented directly to the Window resolved the theme, the same Control under a
## CanvasLayer fell back to Godot's default. All game UI lives under boot.tscn's UI layer, so
## the window-level assignment would have silently done nothing.
##
## A NODE in boot.tscn, not an autoload: the autoload set is fixed at four (see CLAUDE.md), and
## nothing outside the shell needs this before the shell exists. Controls that lay out in
## pixels read the scale back off the theme they already inherit (`UiTheme.scale_of(self)`) and
## relayout on NOTIFICATION_THEME_CHANGED — so there is no global to keep in sync.
##
## WHY NOT THE ENGINE'S CONTENT SCALING. Both `Window.content_scale_factor` (with the stretch
## mode disabled) and `CONTENT_SCALE_MODE_CANVAS_ITEMS` were measured on 4.7.1, and BOTH move
## the 3D render target: factor 2.0 turned a 1152x648 window into a 2304x1296 render (4x the
## pixels), and canvas_items scaled the target by the stretch ratio. Standing rule 9 rules that
## out on web. Scaling the theme instead leaves every viewport and render setting untouched.

## Logical short-edge length that maps to scale 1.0. Chosen so a 1080p desktop lands a little
## above 1.0 and a laptop window lands near it.
const REF_SHORT := 800.0
## Scale floors. Touch needs a higher one: the limit there is a fingertip (UiTheme.TOUCH_MIN),
## not an eye, and a phone's short edge in logical px is far smaller than a desktop's.
const MIN_DESKTOP := 0.85
const MIN_TOUCH := 1.05
const MAX_SCALE := 2.0
## Rebuilding the theme re-lays-out every Control, so ignore changes below this.
const EPSILON := 0.02

var _scale := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # a passthrough frame, never a click target
	get_window().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var s := _compute()
	if absf(s - _scale) < EPSILON:
		return
	_scale = s
	theme = UiTheme.build(s)


## Scale from the window's SHORT edge in logical (density-independent) pixels. The short edge
## is what runs out first — a phone held sideways and an ultrawide monitor both have plenty of
## width and it tells you nothing about how big text should be.
func _compute() -> float:
	var floor_scale := MIN_TOUCH if DisplayServer.is_touchscreen_available() else MIN_DESKTOP
	return clampf(logical_short_edge(get_window()) / REF_SHORT, floor_scale, MAX_SCALE)


## The window's short edge in logical (density-independent) pixels. Static because it is also
## how the dashboard decides "phone-sized" for its automatic density — one definition of how
## big the screen actually is, rather than two that can disagree.
static func logical_short_edge(win: Window) -> float:
	if win == null:
		return REF_SHORT
	return float(mini(win.size.x, win.size.y)) / display_scale()


## Device pixel ratio (browser devicePixelRatio / OS display scaling), or 1.0 where the
## platform does not report one. Without it a high-density phone reports a huge pixel count
## and would be handed the SMALLEST ui, which is backwards.
static func display_scale() -> float:
	var s := DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	return s if s > 0.0 else 1.0
