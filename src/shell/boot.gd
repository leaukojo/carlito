extends Node3D
## Shell composing independent level/UI scenes (no main.tscn). Deep link → saved session →
## DEFAULT_LEVEL. PROCESS_MODE_ALWAYS (set in boot.tscn) keeps menus running while paused.

## First-visit default: the dressed island (farm, coast roads, water). 1.8 MB bake, well
## under level_3's 13.9 MB, which a first visit must never wait on.
const DEFAULT_LEVEL := "level_1"

## Every screen parents to the UiScale Control (not the CanvasLayer): that's where the
## scaled theme lives, and a Control only inherits a theme from Control ancestors.
@onready var _ui: UiScale = $UI/UiScale
@onready var _notice: Label = $UI/UiScale/Notice
@onready var _dashboard: Dashboard = $UI/UiScale/Dashboard
@onready var _touch: TouchControls = $UI/UiScale/TouchControls
@onready var _debug: DebugOverlay = $UI/UiScale/DebugOverlay

## Seconds a GameState.notice stays on screen. Long enough to read while still driving.
const NOTICE_DWELL_S := 3.0

## Frames the loading screen stays up after the level enters the tree: gl_compatibility
## compiles each material's shader on its first draw, which happens the frame after
## add_child. Holding the overlay a few frames keeps that stall off-screen. Only covers
## what's visible at spawn; geometry scrolled into view later still compiles on arrival.
const HOLD_FRAMES := 3

var _level: Node3D = null
var _select: LevelSelect = null
var _vehicles: VehicleSelect = null
var _pause: PauseMenu = null
var _loading: LoadingScreen = null
var _loading_path := ""  # non-empty while a threaded level load is in flight
var _hold_frames := 0  # see HOLD_FRAMES
var _next_variant := ""  # variant the level now loading should spawn ("" = its own default)
## Whether this session writes itself to user://. False for a deep link (must not overwrite
## an explicit link's intent) and under headless (CI must not inherit a local session).
var _persist := true
var _coach_shown := false
## Families coached this session (see _maybe_coach). Not persisted: the aircraft cue teaches
## a control set only relevant while flying, so it reappears each new flight of a session.
var _coached_families := {}
## Density to restore when F2 un-hides the cluster (a session that boots at OFF comes back to AUTO).
var _density_before_hide: int = Dashboard.Density.AUTO


func _ready() -> void:
	var contract_state := "invalid - see errors above"
	if Contract.data != null and Contract.data.is_valid():
		contract_state = "v%d, %d signals" % [Contract.data.version, Contract.data.signals.size()]
	print("Carlito boot OK (contract: %s, bridge active: %s)" % [contract_state, Bridge.is_active()])

	_touch.menu_pressed.connect(_open_pause)
	_touch.garage_pressed.connect(_open_vehicle_select)
	_touch.respawn_pressed.connect(_respawn)
	_touch.next_attachment_pressed.connect(_cycle_attachment)
	_touch.camera_pressed.connect(_cycle_camera)
	_touch.day_night_pressed.connect(_toggle_day_night)
	GameState.attachment_changed.connect(_refresh_attachment_controls)
	GameState.notice.connect(_show_notice)
	GameState.notice_cleared.connect(_clear_notice)
	# Set before the first bind so nothing builds twice.
	_dashboard.set_density_setting(ShellPrefs.dashboard_density())
	_ui.set_user_scale(ShellPrefs.ui_scale())
	_set_hud_visible(false)  # nothing to bind to until the level is up
	_boot()


## Three authorities in order: deep link (`?level=&vehicle=` web, `--level=`/`--vehicle=`/
## CARLITO_LEVEL local), saved session, then DEFAULT_LEVEL. BootParams validates every id, so
## an unknown level/save falls back instead of booting into nothing. Also the headless CI
## path: reaching a level never requires a menu.
func _boot() -> void:
	var params := BootParams.resolve()
	var level_id := String(params["level"])
	var variant := String(params["vehicle"])
	_persist = level_id.is_empty() and variant.is_empty() \
			and DisplayServer.get_name() != "headless"
	if _persist:
		var saved := ShellPrefs.load_boot()
		level_id = String(saved["level"])
		variant = String(saved["vehicle"])
	if level_id.is_empty():
		level_id = DEFAULT_LEVEL
	_load_level(LevelRegistry.scene_of(level_id), variant)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("to_menu"):
		_on_menu_key()
	elif event.is_action_pressed("garage"):
		_open_vehicle_select()
	elif event.is_action_pressed("next_vehicle"):
		_cycle_vehicle()
	elif event.is_action_pressed("next_attachment"):
		_cycle_attachment()
	elif event.is_action_pressed("toggle_dashboard"):
		_toggle_dashboard()


## Swap to the next variant in the current family (V key / touch NEXT). Reuses the
## level's spawn/respawn path; a family with one variant is a no-op. V always changes the
## body only, never an attachment — that's E's axis, and the two never interact.
func _cycle_vehicle() -> void:
	if _level == null or _level.vehicle == null:
		return
	_level.set_vehicle(VehicleCatalog.next_in_family(GameState.current_variant))


## Cycle what's hanging off the back of the current vehicle (E key / touch ATTACH): tractor
## implement, semi trailer. Vehicles that tow nothing ignore it. Duck-typed like every other
## capability hook, so neither this file nor VehicleCatalog learns what an implement or
## trailer is.
func _cycle_attachment() -> void:
	if _level == null or _level.vehicle == null:
		return
	if _level.vehicle.has_method("cycle_implement"):
		_level.vehicle.cycle_implement()
		# New attachment may be driven where the old one wasn't (tipper vs. box).
		_touch.set_capabilities(_capabilities())


## Refresh for an attachment the sim changed on its own (GameState.attachment_changed — a
## coupling that didn't fit and was taken away). Otherwise the overlay keeps offering PTO/TIP
## buttons for a trailer that's no longer there.
func _refresh_attachment_controls() -> void:
	_touch.set_capabilities(_capabilities())


## What the active vehicle can do, driving the touch buttons and the pause menu's CONTROLS
## sheet. Duck-typed throughout, so neither this file nor the overlay learns what a trailer,
## implement or refuse body is.
##
## The two sources are OR'd, not merged: a semi's `pto` comes from its trailer and a garbage
## truck's from its own body, and neither may cancel the other out.
func _capabilities() -> Dictionary:
	var caps := {"tows": false, "pto": false, "lift": false,
			"diff_lock": false, "fwd_drive": false, "body_cmd": false}
	if _level == null or _level.vehicle == null:
		return caps
	var v: BaseVehicle = _level.vehicle
	# `tows`/`attachment_controls` stay duck-typed: method absence means "does not tow"
	# (src/vehicles/CLAUDE.md). `vehicle_capabilities` is defined on BaseVehicle itself.
	caps["tows"] = v.has_method("cycle_implement")
	_or_into(caps, v.vehicle_capabilities())
	if v.has_method("attachment_controls"):
		_or_into(caps, v.attachment_controls())
	return caps


static func _or_into(caps: Dictionary, extra: Dictionary) -> void:
	for k in extra:
		caps[k] = bool(caps.get(k, false)) or bool(extra[k])


# --- pause overlay -----------------------------------------------------------

## Esc (or touch MENU) walks the overlay stack out the way it came in, and only then resumes.
## Never frees the level outright — that stays a deliberate action, not one keypress.
func _on_menu_key() -> void:
	if _vehicles != null:
		_close_vehicle_select()
	elif _select != null:
		_close_level_select()
	elif _pause == null:
		_open_pause()
	elif not _pause.back():
		_close_pause()


func _open_pause() -> void:
	if _level == null or _loading_path != "" or _pause != null:
		return  # nothing to pause, or a level load is in flight
	_pause = PauseMenu.new()
	# Before add_child: CONTROLS sheet greys what the machine lacks, off the same capability read.
	_pause.setup(_capabilities(), _dashboard.density_setting(), _ui.user_scale())
	_pause.resume_requested.connect(_close_pause)
	_pause.vehicle_requested.connect(_open_vehicle_select)
	_pause.level_requested.connect(_show_level_select)
	_pause.dashboard_density_changed.connect(_on_density_changed)
	_pause.ui_scale_changed.connect(_on_ui_scale_changed)
	_ui.add_child(_pause)
	# Hiding the pads also releases anything held (Pad drops its pointer when invisible).
	_touch.set_active(false)
	get_tree().paused = true


func _close_pause() -> void:
	_close_vehicle_select()
	_close_level_select()
	if _pause != null:
		_pause.queue_free()
		_pause = null
	get_tree().paused = false
	_touch.set_active(_level != null)


## SETTINGS picked a new cluster density. The menu owns nothing, so applying and remembering
## it is this file's job — remembered even for a deep-linked session, unlike level/vehicle.
func _on_density_changed(setting: int) -> void:
	_dashboard.set_density_setting(setting)
	ShellPrefs.set_dashboard_density(setting)


## SETTINGS picked a new UI size. Handed to UiScale, which rebuilds the theme so every
## Control relayouts. Remembered, same reasoning as density.
func _on_ui_scale_changed(factor: float) -> void:
	_ui.set_user_scale(factor)
	ShellPrefs.set_ui_scale(factor)


## F2: hide the instrument cluster and restore it after. Moves the same density setting the
## SETTINGS page cycles, so the menu and the key can never disagree about dashboard state.
func _toggle_dashboard() -> void:
	if _dashboard.density_setting() == Dashboard.Density.OFF:
		_on_density_changed(_density_before_hide)
	else:
		_density_before_hide = _dashboard.density_setting()
		_on_density_changed(Dashboard.Density.OFF)


# --- level select ------------------------------------------------------------

## The LEVEL section of the pause menu. Opening it does not tear the current level down —
## that only happens once a different level is actually chosen.
func _show_level_select() -> void:
	if _select != null:
		return
	_select = LevelSelect.new()
	_select.level_chosen.connect(_on_level_chosen)
	_select.closed.connect(_close_level_select)
	_ui.add_child(_select)


func _close_level_select() -> void:
	if _select != null:
		_select.queue_free()
		_select = null


func _on_level_chosen(scene_path: String) -> void:
	_close_level_select()
	_close_pause()  # unpauses: the level about to load must not spawn into a paused tree
	_load_level(scene_path)


## Kick off a threaded level load behind a loading screen; _process polls progress.
## `variant` is the body to spawn instead of the level's default ("" = default).
## Headless (CI smoke) keeps the synchronous path — nobody watches a bar there.
func _load_level(scene_path: String, variant := "") -> void:
	if _level != null:
		# Unbind before free: a threaded load takes frames, else HUD/bridge hold a freed level.
		_unbind_hud()
		_level.queue_free()
		_level = null
	_set_hud_visible(false)
	_next_variant = variant
	if DisplayServer.get_name() == "headless":
		_finish_load(load(scene_path) as PackedScene)
		return
	_drop_loading_screen()  # a screen still up from the previous load's HOLD_FRAMES
	_loading = LoadingScreen.new()
	_ui.add_child(_loading)  # in the tree first: dresses itself with theme-scaled metrics
	_loading.set_level(scene_path)
	_loading_path = scene_path
	ResourceLoader.load_threaded_request(scene_path, "", true)  # parallel sub-resource loads


func _process(_delta: float) -> void:
	if _hold_frames > 0:
		_hold_frames -= 1
		if _hold_frames == 0:
			_drop_loading_screen()
		return
	if _loading_path == "":
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.set_progress(float(progress[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(_loading_path) as PackedScene
			_loading_path = ""
			_loading.set_progress(1.0)
			# Instantiate blocks this frame (level._ready spawns synchronously); the loading
			# screen stays up over the freeze and for HOLD_FRAMES more for the shader compile.
			_finish_load(scene)
			_hold_frames = HOLD_FRAMES
		_:
			var failed := _loading_path
			push_error("Level load failed: %s" % failed)
			_loading_path = ""
			_drop_loading_screen()
			# Fall back to the default level, unless that's the one that just failed —
			# another attempt would only loop.
			var default_scene := LevelRegistry.scene_of(DEFAULT_LEVEL)
			if failed != default_scene:
				_load_level(default_scene)


## Take the loading overlay down. Safe with nothing up; clears the countdown so a level
## chosen during the hold can't leave a stale timer pointing at a freed screen.
func _drop_loading_screen() -> void:
	_hold_frames = 0
	if _loading != null:
		_loading.queue_free()
		_loading = null


func _finish_load(scene: PackedScene) -> void:
	_level = scene.instantiate()
	# Set before the level enters the tree: _ready spawns the vehicle, so this is how a deep
	# link or saved session gets a body other than the level's default.
	_level.initial_variant = _next_variant
	_next_variant = ""
	# This node is PROCESS_MODE_ALWAYS; the level would inherit that, so put back explicitly.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)  # level._ready() spawns the vehicle synchronously here
	_level.vehicle_changed.connect(_on_vehicle_changed)
	_bind_hud()
	_set_hud_visible(true)
	# Initial spawn already happened above, before the signal connected, so save here too.
	_save_session()
	_maybe_coach(GameState.current_vehicle)


## Remember where the player is, so a reload resumes it. No-op for a deep-linked or headless
## run (see _persist).
func _save_session() -> void:
	if not _persist or _level == null:
		return
	ShellPrefs.save_boot(LevelRegistry.id_of(_level.scene_file_path), GameState.current_variant)


## Families with a control axis ground vehicles don't have; get a cue every time you climb
## into one this session.
const COACH_FAMILIES := ["plane", "drone"]


## Two cues, different lifetimes: the first-visit line (once per machine, first level of a
## session only) and the aircraft line (once per family per session, since climb/descend is
## undiscoverable). Aircraft takes precedence on a brand-new machine; the first-visit line is
## left unseen for the next ground vehicle.
func _maybe_coach(family: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if family in COACH_FAMILIES:
		if _coached_families.has(family):
			return
		_coached_families[family] = true
		_show_coach(family)
		return
	if _coach_shown or ShellPrefs.coach_seen():
		return
	_coach_shown = true
	ShellPrefs.mark_coach_seen()
	_show_coach("")


func _show_coach(family: String) -> void:
	var cue := CoachCue.new()
	cue.family = family  # before add_child: _ready() builds the label from it
	_ui.add_child(cue)


## (Re)bind HUD + bridge to the active level/vehicle. Called at load and whenever the
## garage swaps the vehicle (its type drives which dashboard cluster is built).
func _bind_hud() -> void:
	_dashboard.bind(_level)
	_debug.set_level(_level)
	_touch.set_capabilities(_capabilities())
	Bridge.bind(_level)


## Drop every reference to the level about to be freed: nothing may outlive it.
func _unbind_hud() -> void:
	_dashboard.bind(null)
	_debug.set_level(null)
	_touch.set_capabilities({})
	Bridge.bind(null)


func _on_vehicle_changed(type: String) -> void:
	_bind_hud()
	_save_session()
	_maybe_coach(type)  # vehicle_changed carries the family


# --- vehicle selector --------------------------------------------------------

## The garage: body, variant and attachment on one screen with a preview. Pauses the world
## whether opened from the pause menu or G: the preview is a real vehicle body in a
## SubViewport, so a second live body while driving is a hazard, and it's a screen to read
## rather than drive through.
func _open_vehicle_select() -> void:
	if _level == null or _loading_path != "" or _vehicles != null:
		return
	_vehicles = VehicleSelect.new()
	# Before add_child. The level's raw allow-list plus its runtime rail answer, never a
	# pre-filtered roster, so the screen can say why it can't spawn something.
	_vehicles.setup(_level.info.allowed_vehicles, String(_level.info.display_name),
			_level.has_closed_rail(), GameState.current_variant, _current_attachment())
	_vehicles.vehicle_chosen.connect(_on_vehicle_picked)
	_vehicles.attachment_chosen.connect(_on_attachment_picked)
	_vehicles.closed.connect(_close_vehicle_select)
	_ui.add_child(_vehicles)
	_touch.set_active(false)
	get_tree().paused = true


func _close_vehicle_select() -> void:
	if _vehicles == null:
		return
	_vehicles.queue_free()
	_vehicles = null
	# The pause menu may be underneath (VEHICLE was opened from it), in which case the world stays
	# paused and the driving pads stay down until RESUME.
	if _pause == null:
		get_tree().paused = false
		_touch.set_active(_level != null)


## What's on the back of the machine being driven, so the selector opens showing the trailer
## you actually have. Duck-typed like every other cross-layer hook.
func _current_attachment() -> String:
	if _level == null or _level.vehicle == null \
			or not _level.vehicle.has_method("current_attachment"):
		return ""
	return String(_level.vehicle.current_attachment())


## Picked a body: respawn as it, only if different — re-picking to change a trailer must not
## teleport back to the spawn marker.
func _on_vehicle_picked(variant: String) -> void:
	_close_vehicle_select()
	_close_pause()  # back to driving, not back to the menu
	if variant != GameState.current_variant:
		_level.set_vehicle(variant)


## Fires straight after _on_vehicle_picked, only for a machine that tows.
func _on_attachment_picked(id: String) -> void:
	if _level == null or _level.vehicle == null \
			or not _level.vehicle.has_method("set_attachment"):
		return
	if String(_level.vehicle.current_attachment()) == id:
		return
	_level.vehicle.set_attachment(id)
	_touch.set_capabilities(_capabilities())  # new attachment may be driven where the old wasn't


func _cycle_camera() -> void:
	if _level != null:
		_level.cycle_camera()


## Touch NIGHT button. Day/night is a Level concern (N key reaches it directly); pure relay.
func _toggle_day_night() -> void:
	if _level != null:
		_level.toggle_day_night()


func _respawn() -> void:
	if _level != null and _level.vehicle != null:
		_level.vehicle.respawn()


# --- helpers -----------------------------------------------------------------

func _set_hud_visible(v: bool) -> void:
	# set_shown, not .visible: the dashboard also hides itself at density OFF, and neither
	# reason to be hidden may overwrite the other.
	_dashboard.set_shown(v)
	_touch.set_active(v)
	if not v:
		_notice.visible = false


## Show a transient message from the sim (GameState.notice). Re-showing restarts the dwell
## instead of queueing, so holding E against a wall reads as one steady message.
func _show_notice(text: String, dwell_s: float) -> void:
	_notice.text = text
	_notice.visible = true
	var token := text + str(Time.get_ticks_msec())
	_notice.set_meta("token", token)
	var dwell := dwell_s if dwell_s > 0.0 else NOTICE_DWELL_S
	await get_tree().create_timer(dwell).timeout
	if is_instance_valid(_notice) and _notice.get_meta("token", "") == token:
		_notice.visible = false


## Take a notice down early once what it warned about is fixed. Matches on text so it only
## ever hides its own message; a later notice keeps the rest of its dwell.
func _clear_notice(text: String) -> void:
	if _notice.visible and _notice.text == text:
		_notice.visible = false
