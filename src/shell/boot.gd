extends Node3D
## Shell composing independent level/UI scenes (no main.tscn). Deep link → saved session →
## DEFAULT_LEVEL. PROCESS_MODE_ALWAYS (set in boot.tscn) keeps menus running while paused.

const WorldConditions := preload("res://src/levels/base/world_conditions.gd")

## First-visit default: the endless flat ground. No bake to download, so a first visit never
## waits on one (level_3's is 13.9 MB).
const DEFAULT_LEVEL := "flatland"

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
## compiles each material's shader on its first draw, and ShaderWarmup makes that first draw
## the whole level's, the frame after add_child. Holding the overlay a few frames keeps the
## stall off-screen.
const HOLD_FRAMES := 3

var _level: Node3D = null
var _select: LevelSelect = null
var _vehicles: VehicleSelect = null
var _challenges: ChallengeSelect = null
var _pause: PauseMenu = null
var _loading: LoadingScreen = null
var _loading_path := ""  # non-empty while a threaded level load is in flight
var _packs: LevelPacks = null
var _fetching := false  # _loading_path's level pack is downloading; the load starts after
var _hold_frames := 0  # see HOLD_FRAMES
var _warmup: ShaderWarmup = null  # in effect for exactly the HOLD_FRAMES
var _next_variant := ""  # variant the level now loading should spawn ("" = its own default)
## Whether this session writes itself to user://. False for a deep link (must not overwrite
## an explicit link's intent) and under headless (CI must not inherit a local session).
var _persist := true
var _coach_shown := false
## Families coached this session (see _maybe_coach). Not persisted: the aircraft cue teaches
## a control set only relevant while flying, so it reappears each new flight of a session.
var _coached_families := {}
## CONDITIONS page state, kept for the session only (ShellPrefs stays disabled) and re-applied to
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
## The running challenge's briefing, reopened read-only from the touch INFO button; null once
## dismissed.
var _briefing: ChallengeBriefing = null


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
	GameState.notice.connect(_show_notice)
	GameState.notice_cleared.connect(_clear_notice)
	_packs = LevelPacks.new()
	_packs.finished.connect(_on_pack_finished)
	add_child(_packs)
	_progress = ChallengeProgress.open()
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
	# A debug build's `--challenge=` goes straight into an attempt, and like a deep link is never
	# remembered as the session.
	var challenge_id := BootParams.challenge()
	if challenge_id != "":
		_persist = false
		_start_challenge(ChallengeRegistry.def_of(challenge_id, true))
		return
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
	elif event.is_action_pressed("level_select"):
		_show_level_select()
	elif event.is_action_pressed("challenge_select"):
		_show_challenge_select()


## Swap to the next variant in the current family (V key / touch NEXT). Reuses the
## level's spawn/respawn path; a family with one variant is a no-op. V always changes the
## body only, never an attachment — that's E's axis, and the two never interact.
func _cycle_vehicle() -> void:
	if _level == null or _level.vehicle == null:
		return
	if _refused_in_challenge():
		return
	_level.set_vehicle(VehicleCatalog.next_in_family(GameState.current_variant))


## Cycle what's hanging off the back of the current vehicle (E key / touch ATTACH): tractor
## implement, semi trailer. Vehicles that tow nothing ignore it. Duck-typed like every other
## capability hook, so neither this file nor VehicleCatalog learns what an implement or
## trailer is.
func _cycle_attachment() -> void:
	if _level == null or _level.vehicle == null:
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


## The attempt passed or failed: a result panel (RETRY / NEXT / MENU), and a pass is recorded (a
## dev fixture's id is unknown to the store, so it never is).
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
			_next_challenge_after(def) != null)
	_result.retry_requested.connect(_on_result_retry)
	_result.next_requested.connect(_on_result_next)
	_result.menu_requested.connect(_on_result_menu)
	_ui.add_child(_result)


func _close_result() -> void:
	if _result != null:
		_result.queue_free()
		_result = null


## Same respawn the R key performs mid-attempt — the runner resets the attempt on any respawn.
func _on_result_retry() -> void:
	_close_result()
	_touch.set_challenge_mode(true)
	_respawn()


## The touch RETRY button, live only while an attempt is running (no result panel to close).
func _on_touch_retry() -> void:
	if _challenge != null:
		_respawn()


## The touch INFO button: the running def's briefing again, read-only. Pauses like every other
## overlay so reading it costs nothing off the attempt's own timer.
func _show_challenge_info() -> void:
	if _challenge == null or _loading_path != "" or _briefing != null:
		return
	_briefing = ChallengeBriefing.new()
	_briefing.setup(_challenge)
	_briefing.closed.connect(_close_challenge_info)
	_ui.add_child(_briefing)
	_touch.set_active(false)
	get_tree().paused = true


func _close_challenge_info() -> void:
	if _briefing == null:
		return
	_briefing.queue_free()
	_briefing = null
	if _pause == null:
		get_tree().paused = false
		_touch.set_active(_level != null)


## Not straight into the next attempt: the CHALLENGES screen on its briefing, so the player reads
## what to do before START. The finished attempt ends here, so BACK lands in free play like MENU.
func _on_result_next() -> void:
	var next := _next_challenge_after(_challenge)
	_close_result()
	_end_challenge()
	if next != null:
		_show_challenge_select(next.id)


func _on_result_menu() -> void:
	_close_result()
	_end_challenge()


## The next challenge sharing `def`'s family, in registry order, or null past the last one.
func _next_challenge_after(def: ChallengeDef) -> ChallengeDef:
	if def == null:
		return null
	var siblings := ChallengeRegistry.in_family(def.family())
	for i in siblings.size():
		if siblings[i].id == def.id:
			return siblings[i + 1] if i + 1 < siblings.size() else null
	return null


## True (and says why) when an attempt is in progress, for the controls that would undo it.
func _refused_in_challenge() -> bool:
	if _challenge == null:
		return false
	GameState.notice.emit(CHALLENGE_LOCKED_TEXT, 0.0)
	return true


# --- pause overlay -----------------------------------------------------------

## Esc (or touch MENU) walks the overlay stack out the way it came in, and only then resumes.
## Never frees the level outright — that stays a deliberate action, not one keypress.
func _on_menu_key() -> void:
	if _vehicles != null:
		_close_vehicle_select()
	elif _select != null:
		_close_level_select()
	elif _challenges != null:
		_close_challenge_select()
	elif _briefing != null:
		_close_challenge_info()
	elif _pause == null:
		_open_pause()
	elif not _pause.back():
		_close_pause()


func _open_pause() -> void:
	if _level == null or _loading_path != "" or _pause != null:
		return  # nothing to pause, or a level load is in flight
	_pause = PauseMenu.new()
	# Before add_child: CONTROLS sheet greys what the machine lacks, off the same capability read.
	_pause.setup(_capabilities(), _dashboard.density_setting(), _ui.user_scale(),
			_wind_preset, _current_preset, _wind_from_deg, _night, _challenge != null)
	_pause.resume_requested.connect(_close_pause)
	_pause.respawn_requested.connect(_on_pause_respawn)
	_pause.dashboard_density_changed.connect(_on_density_changed)
	_pause.ui_scale_changed.connect(_on_ui_scale_changed)
	_pause.conditions_changed.connect(_on_conditions_changed)
	_pause.night_toggled.connect(_on_night_toggled)
	_ui.add_child(_pause)
	# Hiding the pads also releases anything held (Pad drops its pointer when invisible).
	_touch.set_active(false)
	get_tree().paused = true


func _close_pause() -> void:
	_close_vehicle_select()
	_close_level_select()
	_close_challenge_select()
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


## F2: cycles the same density setting the SETTINGS page's button does, so the menu and the key
## can never disagree about dashboard state.
func _toggle_dashboard() -> void:
	_on_density_changed(Dashboard.next_setting(_dashboard.density_setting()))


## RESPAWN on the pause menu: close the overlay first, or the respawn happens under a paused tree.
func _on_pause_respawn() -> void:
	_close_pause()
	_respawn()


## CONDITIONS picked a new wind/current preset or compass direction. Kept for the session
## (ShellPrefs stays disabled) and applied to the current level; `_finish_load` re-applies it to
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
	if _level == null or _loading_path != "" or _select != null:
		return
	_select = LevelSelect.new()
	_select.level_chosen.connect(_on_level_chosen)
	_select.closed.connect(_close_level_select)
	_ui.add_child(_select)
	_touch.set_active(false)
	get_tree().paused = true


func _close_level_select() -> void:
	if _select == null:
		return
	_select.queue_free()
	_select = null
	# The pause menu may be underneath (the 4 key works while paused), in which case the world
	# stays paused and the driving pads stay down until RESUME.
	if _pause == null:
		get_tree().paused = false
		_touch.set_active(_level != null)


func _on_level_chosen(scene_path: String) -> void:
	_end_challenge()  # picking a level leaves the attempt; the lock must not follow into free play
	_close_level_select()
	_close_pause()  # unpauses: the level about to load must not spawn into a paused tree
	_load_level(scene_path)


# --- challenge selector --------------------------------------------------------

## CHALLENGES: reachable from the pause menu or the on-screen rail with no pause menu underneath,
## mirroring _show_level_select. Reachable during an attempt too (like LEVEL) — picking a
## challenge there ends the one in progress the same way picking a level does.
## `open_id` opens the screen on that challenge's briefing instead of the grid.
func _show_challenge_select(open_id := "") -> void:
	if _level == null or _loading_path != "" or _challenges != null:
		return
	_challenges = ChallengeSelect.new()
	_challenges.setup(_progress, open_id)
	_challenges.challenge_chosen.connect(_on_challenge_picked)
	_challenges.closed.connect(_close_challenge_select)
	_ui.add_child(_challenges)
	_touch.set_active(false)
	get_tree().paused = true


func _close_challenge_select() -> void:
	if _challenges == null:
		return
	_challenges.queue_free()
	_challenges = null
	# The pause menu may be underneath (5 works while paused), in which case the world stays
	# paused and the driving pads stay down until RESUME.
	if _pause == null:
		get_tree().paused = false
		_touch.set_active(_level != null)


func _on_challenge_picked(id: String) -> void:
	_close_challenge_select()
	_close_pause()
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
		_finish_load(load(scene_path) as PackedScene)
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
	# link or saved session gets a body other than the level's default.
	_level.initial_variant = _next_variant
	_next_variant = ""
	# This node is PROCESS_MODE_ALWAYS; the level would inherit that, so put back explicitly.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Read before add_child: the level's _ready broadcasts its authored day through
	# GameState.night_changed, which overwrites _night.
	var night := _night
	add_child(_level)  # level._ready() spawns the vehicle synchronously here
	# CONDITIONS is a session setting (ShellPrefs stays disabled), so every level this loads gets
	# the same wind/current/night the player picked, not the level's own authored defaults.
	_level.set_conditions(_wind_preset, _current_preset, _wind_from_deg)
	_level.set_night(night)
	_level.vehicle_changed.connect(_on_vehicle_changed)
	_bind_hud()
	_set_hud_visible(true)
	# Initial spawn already happened above, before the signal connected, so save here too.
	_save_session()
	_maybe_coach(GameState.current_vehicle)
	if _pending_challenge != null:
		var def := _pending_challenge
		_pending_challenge = null
		_begin_challenge(def)


## Remember where the player is, so a reload resumes it. No-op for a deep-linked or headless
## run (see _persist), during an attempt, and anywhere on a challenge arena: an arena is reached
## through a challenge, never the place to resume.
func _save_session() -> void:
	if not _persist or _level == null or _challenge != null \
			or bool(LevelRegistry.entry_of(_level.scene_file_path).get("arena", false)):
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
## whether opened from the touch GARAGE button or G: the preview is a real vehicle body in a
## SubViewport, so a second live body while driving is a hazard, and it's a screen to read
## rather than drive through.
func _open_vehicle_select() -> void:
	if _level == null or _loading_path != "" or _vehicles != null:
		return
	if _refused_in_challenge():
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
	# The pause menu may be underneath (G works while paused), in which case the world stays
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
