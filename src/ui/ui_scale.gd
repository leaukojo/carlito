class_name UiScale
extends Control
## Root of every on-screen Control. Rebuilds the theme (UiTheme) on window resize and assigns
## it to itself, so the UI subtree inherits one scaled theme; the shell parents transient
## overlays here too.
##
## Theme goes on this Control, not the root Window: a Control under a CanvasLayer does not
## inherit the Window's theme, and all game UI lives under boot.tscn's UI CanvasLayer.
##
## Not the engine's content scaling, which resizes the 3D render target's pixel count — rule
## 9 rules that out on web. A node in boot.tscn, not an autoload (fixed at four).

## Logical short-edge length that maps to scale 1.0. A 1080p desktop lands a little above
## 1.0; a laptop window lands near it.
const REF_SHORT := 800.0
## Touch needs a higher floor: the limit is a fingertip (UiTheme.TOUCH_MIN), not an eye, and
## a phone's short edge in logical px is far smaller than a desktop's.
const MIN_DESKTOP := 0.85
const MIN_TOUCH := 1.05
const MAX_SCALE := 2.0
## Rebuilding the theme relayouts every Control, so ignore changes below this.
const EPSILON := 0.02

## Player's own UI-size multiplier, applied on top of the computed scale (SETTINGS ▸ UI SIZE):
## the formula targets one fixed physical size, but the right physical size varies with
## monitor size and viewing distance, so the player gets the last word. Steps, not a slider,
## to match the other pause-menu buttons.
const USER_STEPS: Array[float] = [0.7, 0.85, 1.0, 1.15, 1.35, 1.6]
const USER_DEFAULT := 1.0

var _scale := 0.0
var _user := USER_DEFAULT


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # passthrough frame, never a click target
	get_window().size_changed.connect(_apply)
	_apply()


## Set by the shell from SETTINGS (and from user:// on boot); rebuilds the theme immediately,
## which is what makes the pause menu resize under the press.
func set_user_scale(factor: float) -> void:
	var f := clampf(factor, USER_STEPS[0], USER_STEPS[USER_STEPS.size() - 1])
	if is_equal_approx(f, _user):
		return
	_user = f
	_apply()


func user_scale() -> float:
	return _user


## The step after `factor`, wrapping. Static so the menu can label itself without the node.
static func next_user_scale(factor: float) -> float:
	for step in USER_STEPS:
		if step > factor + 0.01:
			return step
	return USER_STEPS[0]


func _apply() -> void:
	var s := _compute()
	if absf(s - _scale) < EPSILON:
		return
	_scale = s
	theme = UiTheme.build(s)


## Scale from the window's short edge in logical px: what runs out first (width alone tells
## you nothing on an ultrawide or a sideways phone). Player's multiplier applies after the
## clamp — the floor/ceiling bound the automatic formula, not what the player may ask for.
func _compute() -> float:
	var floor_scale := MIN_TOUCH if is_touch_display() else MIN_DESKTOP
	return clampf(logical_short_edge(get_window()) / REF_SHORT, floor_scale, MAX_SCALE) * _user


## The window's short edge in logical (density-independent) px. Static: the touch pads and the
## debug overlay read it too, so there's one definition, not two that can disagree.
##
## On web this reads the browser's CSS viewport (innerWidth/innerHeight) rather than
## `win.size / screen_get_scale()`: with `html/canvas_resize_policy=Adaptive`, Godot's JS shim
## already folds devicePixelRatio into `win.size` when HiDPI is allowed, so dividing by
## `screen_get_scale()` again double-counts it — and how often that fires depends on OS
## display-scaling%, so the same formula lands on a different result per screen. innerWidth/
## innerHeight are CSS pixels by definition; devicePixelRatio never enters them.
static func logical_short_edge(win: Window) -> float:
	if OS.has_feature("web"):
		var w: Variant = JavaScriptBridge.eval("window.innerWidth", true)
		var h: Variant = JavaScriptBridge.eval("window.innerHeight", true)
		if typeof(w) in [TYPE_FLOAT, TYPE_INT] and typeof(h) in [TYPE_FLOAT, TYPE_INT] \
				and float(w) > 0.0 and float(h) > 0.0:
			return minf(float(w), float(h))
	if win == null:
		return REF_SHORT
	return float(mini(win.size.x, win.size.y)) / display_scale()


## Whether this is a finger-driven display: decides the scale floor here, the touch overlay's
## pad sizing, and the first-run cue's wording. Not just `is_touchscreen_available()` — on web
## that's a single browser probe and browsers disagree (a phone on Opera answering "no" lands
## on the desktop floor and every control comes out a fifth too small). So on web the question
## is asked three ways (pointer media query, touch-point count, touch event API) and any yes
## counts. Cached: cannot change while the page is open, and it's read per frame by the touch
## overlay's rebuild guard.
static var _touch_cache := -1
static func is_touch_display() -> bool:
	if _touch_cache < 0:
		_touch_cache = 1 if _probe_touch() else 0
	return _touch_cache == 1


static func _probe_touch() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		var js := """(function(){try{
			return (window.matchMedia && window.matchMedia('(pointer: coarse)').matches)
				|| (navigator.maxTouchPoints || 0) > 0
				|| ('ontouchstart' in window);
		}catch(e){return false;}})()"""
		return bool(JavaScriptBridge.eval(js, true))
	return false


## Device pixel ratio (OS display scaling), or 1.0 where unreported. Native fallback only —
## see logical_short_edge for why web bypasses this.
static func display_scale() -> float:
	var s := DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	return s if s > 0.0 else 1.0
