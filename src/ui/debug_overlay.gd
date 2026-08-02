class_name DebugOverlay
extends Label
## Always-available perf overlay ("the FPS/draw-call overlay is always
## available"). Toggle with F3 (the "debug_overlay" action). Reads the engine's own
## Performance monitors — FPS, frame time, draw calls, primitives, VRAM, node count —
## so the §5.4 web budget (60 fps, < ~500 draw calls) can be checked while driving.
## Plain text only.

const REFRESH := 0.25  ## s between text rebuilds (per-frame churn is pointless and noisy)
## Width reserved for the readout, in logical px (scaled through UiTheme).
const WIDTH := 260.0

var _accum := 0.0
var _level: Node  ## active level, for the per-wheel surface-grip readout (set by the shell)


## The shell rebinds this whenever it swaps the level/vehicle (mirrors Dashboard.bind).
func set_level(level: Node) -> void:
	_level = level


func _ready() -> void:
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Green is SEMANTIC here (this is the dev readout, deliberately unlike the game UI), so it
	# stays an override; the size and footprint follow the theme scale.
	add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	theme_type_variation = &"Small"
	_apply_metrics()
	# Keep updating (to toggle) even if the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Persistent overlay, so it re-reads its footprint when UiScale rebuilds the theme.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_apply_metrics()


func _apply_metrics() -> void:
	offset_left = -UiTheme.px(self, WIDTH)
	offset_top = UiTheme.px(self, 10.0)
	offset_right = -UiTheme.px(self, 10.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible
		if visible:
			_refresh()
		accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= REFRESH:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var frame_ms := (Performance.get_monitor(Performance.TIME_PROCESS)
			+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	text = "FPS %d  (%.1f ms)\ndraw calls %d\nprimitives %d\nVRAM %.1f MB\nnodes %d" % [
		Engine.get_frames_per_second(), frame_ms, draw_calls, prims, vram, nodes]
	text += _grip_line()
	text += _articulation_line()
	text += _ui_scale_line()


## Per-wheel painted-surface grip of the active vehicle (1.00 on unpainted ground), or "" when
## there's no vehicle / it has no wheels (the boat). Wheel order is FL FR RL RR.
func _grip_line() -> String:
	if _level == null:
		return ""
	var vehicle: BaseVehicle = _level.get("vehicle")
	if vehicle == null or vehicle.wheels.is_empty():
		return ""
	var parts := PackedStringArray()
	for w in vehicle.wheels:
		parts.append("%.2f" % w.surface_grip)
	return "\ngrip " + " ".join(parts)


## Fifth-wheel articulation angle of a towing vehicle (degrees, + = trailer to the right), or ""
## for anything that tows nothing. Duck-typed like every other cross-layer hook here, so this file
## learns nothing about trailers. How jackknifed a rig is cannot be read off the chase camera.
func _articulation_line() -> String:
	if _level == null:
		return ""
	var vehicle: Node = _level.get("vehicle")
	if vehicle == null or not vehicle.has_method("articulation"):
		return ""
	return "\nartic %+.1f deg" % rad_to_deg(vehicle.call("articulation"))


## TEMP diagnostic for the cross-device UI-scale bug: every number UiScale's formula touches,
## so a report from a friend's browser (F3, screenshot) tells us which one is lying instead of
## guessing blind. Remove once the touch-UI sizing is confirmed consistent across browsers.
func _ui_scale_line() -> String:
	var win := get_window()
	var w := 0.0
	var h := 0.0
	var dpr := 0.0
	if OS.has_feature("web"):
		w = float(JavaScriptBridge.eval("window.innerWidth", true))
		h = float(JavaScriptBridge.eval("window.innerHeight", true))
		dpr = float(JavaScriptBridge.eval("window.devicePixelRatio", true))
	return "\nwin %dx%d  css %dx%d  dpr %.2f\nscreen_scale %.2f  touch %s  short %.0f  ui_scale %.2f" % [
		win.size.x, win.size.y, int(w), int(h), dpr,
		DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW),
		UiScale.is_touch_display(), UiScale.logical_short_edge(win),
		UiTheme.scale_of(self)]
