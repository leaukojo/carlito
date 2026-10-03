class_name Boot
extends Node3D
## Shell composing independent level/UI scenes (no main.tscn). Deep link →
## DEFAULT_LEVEL. PROCESS_MODE_ALWAYS (set in boot.tscn) keeps menus running while paused.

const WorldConditions := preload("res://src/levels/base/world_conditions.gd")

## First-visit default: the endless flat ground. No bake to download, so a first visit never
## waits on one (level_3's is 13.9 MB).
const DEFAULT_LEVEL := "flatland"

## Every screen parents to the UiScale Control (not the CanvasLayer): that's where the
## scaled theme lives, and a Control only inherits a theme from Control ancestors.
@onready var _ui: UiScale = $UI/UiScale
@onready var _notice: NoticeLine = $UI/UiScale/Notice
@onready var _dashboard: Dashboard = $UI/UiScale/Dashboard
@onready var _touch: TouchControls = $UI/UiScale/TouchControls
@onready var _debug: DebugOverlay = $UI/UiScale/DebugOverlay

## Frames the loading screen stays up after the level enters the tree: gl_compatibility
## compiles each material's shader on its first draw, and ShaderWarmup makes that first draw
## the whole level's, the frame after add_child. Holding the overlay a few frames keeps the
## stall off-screen.
const HOLD_FRAMES := 3

var _level: Node3D = null
## Modal UI in the order opened (LIFO): PauseMenu, LevelSelect, VehicleSelect, ChallengeSelect,
## ChallengeBriefing. Esc/touch MENU pops the top; pause/touch state derives from emptiness.
var _overlays: Array[Control] = []
var _loading: LoadingScreen = null
var _loading_path := ""  # non-empty while a threaded level load is in flight
var _packs: LevelPacks = null
var _fetching := false  # _loading_path's level pack is downloading; the load starts after
var _hold_frames := 0  # see HOLD_FRAMES
var _warmup: ShaderWarmup = null  # in effect for exactly the HOLD_FRAMES
var _next_variant := ""  # variant the level now loading should spawn ("" = its own default)
## CONDITIONS page state, kept for the session only and re-applied to
## every level this loads (`_finish_load`) and on change (`_on_conditions_changed`).
var _wind_preset: int = WorldConditions.Preset.LEVEL
var _current_preset: int = WorldConditions.Preset.LEVEL
var _wind_from_deg := 0.0
## Tracks GameState.night_changed rather than being written independently, so the N key and the
## CONDITIONS page can never disagree about which one is true.
var _night := false
## The attempt in progress, or null for free play. While set, driving is bridge-only and nothing
## that would undo the attempt (vehicle swap, attachment cycle, day/night, CONDITIONS) is honoured.
var _challenge: ChallengeDef = null
## The session's night choice, held while a challenge forces the level's own day lighting.
var _night_before_challenge := false
## The free-play gearbox picked in the vehicle selector; a challenge sets its own and this is
## put back when it ends. Session-only, like CONDITIONS.
var _manual_gearbox := false
const CHALLENGE_LOCKED_TEXT := "LOCKED DURING A CHALLENGE"
## Runs the attempt in progress, under the level; null in free play.
var _runner: ChallengeRunner = null
## The objective/timer readout while `_runner` is running; null in free play.
var _challenge_hud: ChallengeHud = null
## The pass/fail result panel (RETRY / NEXT / MENU); null once dismissed.
var _result: ChallengeResult = null
## The challenge to begin once the level now loading is up (`_start_challenge`).
var _pending_challenge: ChallengeDef = null
var _progress: ChallengeProgress = null
var _settings: UserSettings = null


func _ready() -> void:
	var contract_state := "invalid - see errors above"
	if Contract.data != null and Contract.data.is_valid():
		contract_state = "v%d, %d signals" % [Contract.data.version, Contract.data.signals.size()]
	print("Carlito boot OK (contract: %s, bridge active: %s)" % [contract_state, Bridge.is_active()])

	_touch.menu_pressed.connect(_open_pause)
	_touch.garage_pressed.connect(_open_vehicle_select)
	_touch.level_pressed.connect(_show_level_select)
	_touch.challenge_pressed.connect(_show_challenge_select)
	_touch.next_attachment_pressed.connect(_cycle_attachment)
	_touch.camera_pressed.connect(_cycle_camera)
	_touch.retry_pressed.connect(_on_touch_retry)
	_touch.info_pressed.connect(_show_challenge_info)
	GameState.attachment_changed.connect(_refresh_attachment_controls)
	GameState.night_changed.connect(_on_level_night_changed)
	_packs = LevelPacks.new()
	_packs.finished.connect(_on_pack_finished)
	add_child(_packs)
	_progress = ChallengeProgress.open()
	_settings = UserSettings.open()
	_apply_saved_settings()
	_set_hud_visible(false)  # nothing to bind to until the level is up
	_boot()


## Two authorities in order: deep link (`?level=&vehicle=` web, `--level=`/`--vehicle=`/
## CARLITO_LEVEL local), then DEFAULT_LEVEL. BootParams validates every id, so
## an unknown level falls back instead of booting into nothing. Also the headless CI
## path: reaching a level never requires a menu.
func _boot() -> void:
	# A debug build's `--challenge=` goes straight into an attempt.
	var challenge_id := BootParams.challenge()
	if challenge_id != "":
		_start_challenge(ChallengeRegistry.def_of(challenge_id, true))
		return
	var params := BootParams.resolve()
	var level_id := String(params["level"])
	var variant := String(params["vehicle"])
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
	elif event.is_action_pressed("level_select"):
		_show_level_select()
	elif event.is_action_pressed("challenge_select"):
		_show_challenge_select()


## Swap to the next variant in the current family (V key / touch NEXT). Reuses the
## level's spawn/respawn path; a family with one variant is a no-op. V always changes the
## body only, never an attachment — that's E's axis, and the two never interact.
func _cycle_vehicle() -> void:
	if _level == null or _level.vehicle == null or not _overlays.is_empty():
		return
	if _refused_in_challenge():
		return
	_level.set_vehicle(VehicleCatalog.next_in_family(GameState.current_variant))


## Cycle what's hanging off the back of the current vehicle (E key / touch ATTACH): tractor
## implement, semi trailer. Vehicles that tow nothing ignore it. Duck-typed like every other
## capability hook, so neither this file nor VehicleCatalog learns what an implement or
## trailer is.
func _cycle_attachment() -> void:
	if _level == null or _level.vehicle == null or not _overlays.is_empty():
		return
	if not (_challenge != null and _challenge.allow_attach_key) and _refused_in_challenge():
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


# --- challenge lock ------------------------------------------------------------

## Load the def's arena with its body, and begin the attempt once the level is up
## (`_finish_load`).
func _start_challenge(def: ChallengeDef) -> void:
	_end_challenge()
	_pending_challenge = def
	_load_level(LevelRegistry.scene_of(def.arena), def.variant)


## Enter an attempt on the level already loaded: bridge-only driving, the touch driving pads
## down, and the session's CONDITIONS suspended so the level runs its own authored wind, current
## and day. Camera, respawn, the menu and LEVEL stay live. A ChallengeRunner under the level runs
## the attempt itself.
func _begin_challenge(def: ChallengeDef) -> void:
	_challenge = def
	InputRouter.set_bridge_only(true)
	Bridge.set_challenge(true)
	InputRouter.set_manual_gearbox(def.transmission == ChallengeDef.Transmission.MANUAL)
	_touch.set_driving_locked(true)
	_touch.set_challenge_mode(true)
	if _level != null:
		_level.day_night_locked = true
		# Read before set_night: GameState.night_changed overwrites _night.
		_night_before_challenge = _night
		_level.set_conditions(WorldConditions.Preset.LEVEL, WorldConditions.Preset.LEVEL, 0.0)
		_level.set_night(false)
		# After set_night: the runner lays the def's visibility over the day lighting and restores
		# that.
		_runner = ChallengeRunner.new()
		_runner.setup(def)
		_runner.finished.connect(_on_challenge_finished)
		_level.add_child(_runner)
		_challenge_hud = ChallengeHud.new()
		_challenge_hud.set_runner(_runner)
		_ui.add_child(_challenge_hud)
		print("Challenge '%s' on %s (%s)" % [def.id, def.arena, def.variant])


## Leave the attempt: free play again, with the session's CONDITIONS put back.
func _end_challenge() -> void:
	if _challenge == null:
		return
	_challenge = null
	InputRouter.set_bridge_only(false)
	Bridge.set_challenge(false)
	InputRouter.set_manual_gearbox(_manual_gearbox)
	_touch.set_driving_locked(false)
	_touch.set_challenge_mode(false)
	_close_challenge_info()
	_close_result()
	if is_instance_valid(_challenge_hud):
		_challenge_hud.queue_free()
	_challenge_hud = null
	if is_instance_valid(_runner):
		# Before set_night below: the runner puts back the day lighting it found.
		_runner.end()
		_runner.queue_free()
	_runner = null
	if _level != null:
		_level.day_night_locked = false
		_level.set_conditions(_wind_preset, _current_preset, _wind_from_deg)
		_level.set_night(_night_before_challenge)


## The attempt passed or failed: a result panel (RETRY, plus NEXT on a pass), and a pass is
## recorded (a dev fixture's id is unknown to the store, so it never is).
func _on_challenge_finished(passed: bool, elapsed_s: float, message: String) -> void:
	if _challenge == null:
		return
	_touch.set_challenge_mode(false)  # the result panel takes over; RETRY/INFO reappear on retry
	_close_challenge_info()
	var def := _challenge
	var is_new_best := passed and _progress.record_pass(def.id, elapsed_s)
	_close_result()
	_result = ChallengeResult.new()
	_result.setup(def, passed, elapsed_s, message, _progress.best_time(def.id), is_new_best,
			ChallengeRegistry.next_after(def) != null)
	_result.retry_requested.connect(_on_result_retry)
	_result.next_requested.connect(_on_result_next)
	_result.challenges_requested.connect(_on_result_challenges)
	_ui.add_child(_result)


func _close_result() -> void:
	if _result != null:
		_result.queue_free()
		_result = null


## RETRY: the runner gives a fresh body per attempt (challenge_runner.gd's promise — fuel, air,
## battery all reset), so `restart()` runs whenever a runner exists; a def whose course never
## started leaves no runner action of its own, so it falls back to a plain respawn and fails
## again, visibly, rather than sitting on a stale result panel.
func _on_result_retry() -> void:
	_close_result()
	_touch.set_challenge_mode(true)
	if is_instance_valid(_runner):
		_runner.restart()
	else:
		_respawn()


## The touch RETRY button, live only while an attempt is running (no result panel to close).
## Same fresh-body reasoning as `_on_result_retry`.
func _on_touch_retry() -> void:
	if _challenge == null:
		return
	if is_instance_valid(_runner):
		_runner.restart()
	else:
		_respawn()


func _briefing_overlay() -> ChallengeBriefing:
	for o in _overlays:
		if o is ChallengeBriefing:
			return o
	return null


## The touch INFO button: the running def's briefing again, read-only. Pauses like every other
## overlay so reading it costs nothing off the attempt's own timer.
func _show_challenge_info() -> void:
	if _challenge == null or _loading_path != "" or _briefing_overlay() != null:
		return
	var briefing := ChallengeBriefing.new()
	briefing.setup(_challenge)
	briefing.closed.connect(_close_overlay.bind(briefing))
	_push_overlay(briefing)


## Idempotent: called from `_end_challenge`/`_on_challenge_finished` whether or not INFO is open.
func _close_challenge_info() -> void:
	var briefing := _briefing_overlay()
	if briefing != null:
		_close_overlay(briefing)


## Not straight into the next attempt: the CHALLENGES screen on its briefing, so the player reads
## what to do before START. The finished attempt ends here, so BACK lands in free play like MENU.
func _on_result_next() -> void:
	var next := ChallengeRegistry.next_after(_challenge)
	_close_result()
	_end_challenge()
	if next != null:
		_show_challenge_select(next.id)


## CHALLENGES on the result panel: same as NEXT but back to the grid instead of the next
## challenge's briefing.
func _on_result_challenges() -> void:
	_close_result()
	_end_challenge()
	_show_challenge_select()


## True (and says why) when an attempt is in progress, for the controls that would undo it.
func _refused_in_challenge() -> bool:
	if _challenge == null:
		return false
	GameState.notice.emit(CHALLENGE_LOCKED_TEXT, 0.0)
	return true


# --- pause overlay -----------------------------------------------------------

## Esc (or touch MENU) pops the top of the overlay stack, and only then resumes. Never frees the
## level outright — that stays a deliberate action, not one keypress.
func _on_menu_key() -> void:
	if _overlays.is_empty():
		_open_pause()
		return
	var top: Control = _overlays.back()
	if top is PauseMenu and (top as PauseMenu).back():
		return  # paged back within the pause menu itself, not a stack pop
	_pop_overlay()


func _find_pause() -> PauseMenu:
	for o in _overlays:
		if o is PauseMenu:
			return o
	return null


## Push a modal onto the stack: pauses the world and drops the touch pads. Every `_show_*`/
## `_open_*` overlay opener ends here.
func _push_overlay(node: Control) -> void:
	_overlays.append(node)
	_ui.add_child(node)
	_touch.set_active(false)
	get_tree().paused = true


## Remove a specific overlay wherever it sits in the stack. Every overlay's own close signal
## (`closed`, `resume_requested`, ...) binds here, so closing is idempotent from the caller's
## side — a node not in the stack is silently ignored.
func _close_overlay(node: Control) -> void:
	if not _overlays.has(node):
		return
	_overlays.erase(node)
	node.queue_free()
	_sync_overlay_state()


func _pop_overlay() -> void:
	if not _overlays.is_empty():
		_close_overlay(_overlays.back())


## Picking a level/vehicle/challenge (or RESPAWN/RESUME from pause) means "back to driving",
## whatever else is stacked above or below the overlay that fired it.
func _close_all_overlays() -> void:
	while not _overlays.is_empty():
		_pop_overlay()


## Close overlays stacked above `node`, leaving it the visible top again — a menu key for an
## overlay already open elsewhere in the stack pops down to it instead of stacking a duplicate.
func _reveal_overlay(node: Control) -> void:
	while not _overlays.is_empty() and _overlays.back() != node:
		_pop_overlay()


## Derives pause/touch state from the stack's emptiness. Every overlay close calls this instead
## of assuming it was the last one up.
func _sync_overlay_state() -> void:
	var open := not _overlays.is_empty()
	get_tree().paused = open
	_touch.set_active(not open and _level != null)


func _open_pause() -> void:
	if _level == null or _loading_path != "" or _find_pause() != null:
		return  # nothing to pause, or a level load is in flight
	var pause := PauseMenu.new()
	# Before add_child: CONTROLS sheet greys what the machine lacks, off the same capability read.
	var state := PauseMenu.State.new()
	state.density = _dashboard.density_setting()
	state.ui_scale = _ui.user_scale()
	state.extended_debug = _debug.is_extended()
	state.key_softening = InputRouter.key_softening()
	state.tcs_off = InputRouter.local_tcs_off()
	state.wind_preset = _wind_preset
	state.current_preset = _current_preset
	state.wind_from_deg = _wind_from_deg
	state.night = _night
	state.conditions_locked = _challenge != null
	pause.setup(_capabilities(), state)
	pause.resume_requested.connect(_close_all_overlays)
	pause.respawn_requested.connect(_on_pause_respawn)
	pause.dashboard_density_changed.connect(_on_density_changed)
	pause.ui_scale_changed.connect(_on_ui_scale_changed)
	pause.extended_debug_changed.connect(_on_extended_debug_changed)
	pause.key_softening_changed.connect(_on_key_softening_changed)
	pause.tcs_off_changed.connect(_on_tcs_off_changed)
	pause.conditions_changed.connect(_on_conditions_changed)
	pause.night_toggled.connect(_on_night_toggled)
	_push_overlay(pause)


## The SETTINGS choices saved by an earlier visit, through the same setters a press uses.
func _apply_saved_settings() -> void:
	_dashboard.set_density_setting(int(_settings.value("density")))
	_ui.set_user_scale(float(_settings.value("ui_scale")))
	_debug.set_extended(bool(_settings.value("extended_debug")))
	InputRouter.set_key_softening(float(_settings.value("key_softening")))
	InputRouter.set_local_tcs_off(bool(_settings.value("tcs_off")))


## SETTINGS picked a new cluster density. The menu owns nothing, so applying and remembering
## it is this file's job: each handler below saves what its owner actually applied.
func _on_density_changed(setting: int) -> void:
	_dashboard.set_density_setting(setting)
	_settings.set_value("density", _dashboard.density_setting())


## SETTINGS picked a new UI size. Handed to UiScale, which rebuilds the theme so every
## Control relayouts.
func _on_ui_scale_changed(factor: float) -> void:
	_ui.set_user_scale(factor)
	_settings.set_value("ui_scale", _ui.user_scale())


## SETTINGS picked "Extended debug labels".
func _on_extended_debug_changed(on: bool) -> void:
	_debug.set_extended(on)
	_settings.set_value("extended_debug", _debug.is_extended())


## SETTINGS picked a new KEY RESPONSE step.
func _on_key_softening_changed(amount: float) -> void:
	InputRouter.set_key_softening(amount)
	_settings.set_value("key_softening", InputRouter.key_softening())


## SETTINGS flipped TRACTION CONTROL.
func _on_tcs_off_changed(off: bool) -> void:
	InputRouter.set_local_tcs_off(off)
	_settings.set_value("tcs_off", InputRouter.local_tcs_off())


## F2: cycles the same density setting the SETTINGS page's button does, so the menu and the key
## can never disagree about dashboard state.
func _toggle_dashboard() -> void:
	_on_density_changed(Dashboard.next_setting(_dashboard.density_setting()))


## RESPAWN on the pause menu: close the overlay first, or the respawn happens under a paused tree.
func _on_pause_respawn() -> void:
	_close_all_overlays()
	_respawn()


## CONDITIONS picked a new wind/current preset or compass direction. Kept for the session
## and applied to the current level; `_finish_load` re-applies it to
## whatever loads next.
func _on_conditions_changed(wind_preset: int, current_preset: int, from_deg: float) -> void:
	_wind_preset = wind_preset
	_current_preset = current_preset
	_wind_from_deg = from_deg
	if _level != null:
		_level.set_conditions(_wind_preset, _current_preset, _wind_from_deg)


## CONDITIONS picked day/night directly (as opposed to the N key, which flips it). `_night`
## itself is written from GameState.night_changed (`_on_level_night_changed`), not here, so it
## can never disagree with what the level actually did.
func _on_night_toggled(on: bool) -> void:
	if _level != null:
		_level.set_night(on)


## Keeps the shell's remembered night state in lock-step with the level's, whether it changed
## from the N key, the CONDITIONS page, or a freshly loaded level's first-frame capture.
func _on_level_night_changed(is_night: bool) -> void:
	_night = is_night


# --- level select ------------------------------------------------------------

## LEVEL: reachable from the pause menu or the on-screen rail with no pause menu underneath, so
## this pauses the world and hides the pads itself, mirroring _open_vehicle_select. Opening it
## does not tear the current level down — that only happens once a different level is chosen.
func _show_level_select() -> void:
	if _level == null or _loading_path != "":
		return
	for o in _overlays:
		if o is LevelSelect:
			_reveal_overlay(o)
			return
	var select := LevelSelect.new()
	select.level_chosen.connect(_on_level_chosen)
	select.closed.connect(_close_overlay.bind(select))
	_push_overlay(select)


func _on_level_chosen(scene_path: String) -> void:
	_end_challenge()  # picking a level leaves the attempt; the lock must not follow into free play
	_close_all_overlays()  # unpauses: the level about to load must not spawn into a paused tree
	_load_level(scene_path)


# --- challenge selector --------------------------------------------------------

## CHALLENGES: reachable from the pause menu or the on-screen rail with no pause menu underneath,
## mirroring _show_level_select. Reachable during an attempt too (like LEVEL) — picking a
## challenge there ends the one in progress the same way picking a level does.
## `open_id` opens the screen on that challenge's briefing instead of the grid.
func _show_challenge_select(open_id := "") -> void:
	if _level == null or _loading_path != "":
		return
	for o in _overlays:
		if o is ChallengeSelect:
			_reveal_overlay(o)
			return
	var challenges := ChallengeSelect.new()
	challenges.setup(_progress, open_id)
	challenges.challenge_chosen.connect(_on_challenge_picked)
	challenges.closed.connect(_close_overlay.bind(challenges))
	_push_overlay(challenges)


func _on_challenge_picked(id: String) -> void:
	_close_all_overlays()
	_start_challenge(ChallengeRegistry.def_of(id))


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
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_loading_path = scene_path
			_load_failed()
		else:
			_finish_load(packed)
		return
	_drop_loading_screen()  # a screen still up from the previous load's HOLD_FRAMES
	_loading = LoadingScreen.new()
	_ui.add_child(_loading)  # in the tree first: dresses itself with theme-scaled metrics
	_loading.set_level(scene_path)
	# The web export is single-threaded, so the "threaded" request below runs the whole load
	# inside the call. Draw the loading screen first, or the boot load happens before the first
	# frame, under the HTML shell's stalled progress bar.
	await RenderingServer.frame_post_draw
	_loading_path = scene_path
	if LevelPacks.needs_fetch(scene_path):
		_fetching = true
		_packs.fetch(LevelRegistry.id_of(scene_path))  # _on_pack_finished starts the load
		return
	ResourceLoader.load_threaded_request(scene_path, "", true)  # parallel sub-resource loads


## The level's pack is mounted, or could not be fetched.
func _on_pack_finished(ok: bool) -> void:
	_fetching = false
	if ok:
		ResourceLoader.load_threaded_request(_loading_path, "", true)
	else:
		_load_failed()


func _process(_delta: float) -> void:
	if _hold_frames > 0:
		_hold_frames -= 1
		if _hold_frames == 0:
			_drop_loading_screen()
		return
	if _loading_path == "":
		return
	if _fetching:
		_loading.set_download(_packs.downloaded_bytes())
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
			_warmup = ShaderWarmup.begin(_level)
			_hold_frames = HOLD_FRAMES
		_:
			_load_failed()


func _load_failed() -> void:
	_pending_challenge = null  # its arena is what failed; the fallback level is free play
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
	if _warmup != null:
		_warmup.end()
		_warmup = null
	if _loading != null:
		_loading.queue_free()
		_loading = null


func _finish_load(scene: PackedScene) -> void:
	_level = scene.instantiate()
	# Set before the level enters the tree: _ready spawns the vehicle, so this is how a deep
	# link gets a body other than the level's default.
	_level.initial_variant = _next_variant
	_next_variant = ""
	# This node is PROCESS_MODE_ALWAYS; the level would inherit that, so put back explicitly.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Read before add_child: the level's _ready broadcasts its authored day through
	# GameState.night_changed, which overwrites _night.
	var night := _night
	add_child(_level)  # level._ready() spawns the vehicle synchronously here
	# CONDITIONS is a session setting, so every level this loads gets
	# the same wind/current/night the player picked, not the level's own authored defaults.
	_level.set_conditions(_wind_preset, _current_preset, _wind_from_deg)
	_level.set_night(night)
	_level.vehicle_changed.connect(_on_vehicle_changed)
	_bind_hud()
	_set_hud_visible(true)
	CoachCue.maybe_coach(GameState.current_vehicle, _ui)
	if _pending_challenge != null:
		var def := _pending_challenge
		_pending_challenge = null
		_begin_challenge(def)
	# The CI smokes require this line: a crash or hang before the first spawn leaves none.
	print("Carlito level OK: %s (%s, baked: %s)" % [LevelRegistry.id_of(_level.scene_file_path),
			GameState.current_variant, _level.baked])


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
	CoachCue.maybe_coach(type, _ui)  # vehicle_changed carries the family


# --- vehicle selector --------------------------------------------------------

## The garage: body, variant and attachment on one screen with a preview. Pauses the world
## whether opened from the touch GARAGE button or G: the preview is a real vehicle body in a
## SubViewport, so a second live body while driving is a hazard, and it's a screen to read
## rather than drive through.
func _open_vehicle_select() -> void:
	if _level == null or _loading_path != "":
		return
	if _refused_in_challenge():
		return
	for o in _overlays:
		if o is VehicleSelect:
			_reveal_overlay(o)
			return
	var vehicles := VehicleSelect.new()
	# Before add_child. The level's raw allow-list plus its runtime rail answer, never a
	# pre-filtered roster, so the screen can say why it can't spawn something.
	vehicles.setup(_level.info.allowed_vehicles, String(_level.info.display_name),
			_level.has_closed_rail(), GameState.current_variant, _current_attachment(),
			_manual_gearbox, _level.has_spawn_for)
	vehicles.vehicle_chosen.connect(_on_vehicle_picked)
	vehicles.attachment_chosen.connect(_on_attachment_picked)
	vehicles.gearbox_chosen.connect(_on_gearbox_picked)
	vehicles.closed.connect(_close_overlay.bind(vehicles))
	_push_overlay(vehicles)


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
	_close_all_overlays()  # back to driving, not back to the menu
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


## Fires on DRIVE for a family whose contract takes a gear byte. The selector is refused during
## an attempt, so this never overrides a challenge's own gearbox.
func _on_gearbox_picked(manual: bool) -> void:
	_manual_gearbox = manual
	InputRouter.set_manual_gearbox(manual)


func _cycle_camera() -> void:
	if _level != null:
		_level.cycle_camera()


func _respawn() -> void:
	if _level != null and _level.vehicle != null:
		_level.vehicle.respawn()


# --- helpers -----------------------------------------------------------------

func _set_hud_visible(v: bool) -> void:
	# set_shown, not .visible: the dashboard also hides itself at density OFF, and neither
	# reason to be hidden may overwrite the other.
	_dashboard.set_shown(v)
	_touch.set_active(v)
	_notice.set_shown(v)
