extends Node3D
## Shell: boot -> load level -> play, with a pause overlay over the top of it. Composes
## independent level/UI scenes — there is no giant main.tscn. The persistent HUD (dashboard,
## debug overlay, touch controls) lives in boot.tscn; the pause, level-select and vehicle-selector
## screens are transient overlays created here.
##
## DRIVE FIRST, IN EVERY MODE. There is no front door: the page loads and you are already in a
## level with a car. What level and what car is decided in _boot() — a deep link wins, then the
## session saved in user://, then DEFAULT_LEVEL. Level select is a section of the pause menu
## now, not a gate in front of the game, because a visitor who does not yet know this is a
## playable game has no basis on which to choose a level.
##
## PAUSE. This node is PROCESS_MODE_ALWAYS (set in boot.tscn) so the shell and its menus keep
## running while `get_tree().paused` is true; the level is explicitly put back to PAUSABLE when
## it is added, since it is a child of this node and would otherwise inherit ALWAYS and never
## pause. The autoloads pause with the world — a paused sandbox publishing telemetry it is no
## longer simulating would be a fiction.

## Where a first visit starts (see docs/plans/ui_improvements.md): the dressed island, so the
## first frame has farm fields, coast roads and open water rather than bare terrain. It is the
## second-lightest bake at 1.8 MB — heavier than the mountain's 0.7, still nowhere near
## level_3 (13.9 MB), which a first visit must never wait on.
const DEFAULT_LEVEL := "level_1"

## Every screen is parented to the UiScale Control, not the CanvasLayer: that is where the
## scaled theme lives, and a Control only inherits a theme from its Control ancestors.
@onready var _ui: Control = $UI/UiScale
@onready var _notice: Label = $UI/UiScale/Notice
@onready var _dashboard: Dashboard = $UI/UiScale/Dashboard
@onready var _touch: TouchControls = $UI/UiScale/TouchControls
@onready var _debug: DebugOverlay = $UI/UiScale/DebugOverlay

## Seconds a GameState.notice stays on screen. Long enough to read while still driving.
const NOTICE_DWELL_S := 3.0

## Frames the loading screen is held up AFTER the level has entered the tree. The load is
## done by then, but under gl_compatibility every material compiles its shader on its FIRST
## DRAW, and the whole level draws for the first time on the frame after add_child — so
## freeing the screen when the load finished put the compile stall on the first frame the
## player could see. A CanvasLayer does not stop the 3D world rendering underneath it, so
## those frames are real draws and the stall happens behind the overlay instead. This only
## covers what is on screen at the spawn; geometry that scrolls into view later still
## compiles when it arrives (see the perf notes in docs/TODO.md).
const HOLD_FRAMES := 3

var _level: Node3D = null
var _select: LevelSelect = null
var _vehicles: VehicleSelect = null
var _pause: PauseMenu = null
var _loading: LoadingScreen = null
var _loading_path := ""  # non-empty while a threaded level load is in flight
## Frames the loading screen stays up AFTER the level is in the tree — see HOLD_FRAMES.
var _hold_frames := 0
var _next_variant := ""  # variant the level now loading should spawn ("" = its own default)
## Whether this session writes itself back to user://. False when a deep link chose the
## configuration (an explicit link is somebody else's intent, and must not overwrite yours)
## and under headless, where CI must not inherit whatever was last driven locally.
var _persist := true
var _coach_shown := false
## Families already coached in THIS session (see _maybe_coach). Not a ShellPrefs key on purpose:
## the first-visit cue is once per machine because it teaches that the game is playable at all,
## while the aircraft line teaches a control set you only need while you are in one — so it comes
## back for each new flight of a session, and getting into a plane after an hour in a truck says
## R / F again.
var _coached_families := {}
## Density to restore when F2 un-hides the cluster (a session that boots at OFF comes back to AUTO).
var _density_before_hide := Dashboard.Density.AUTO


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
	# How dense the cluster is, as last chosen (AUTO by default, which decides from screen size
	# and whether the bridge is live). Set before the first bind so nothing builds twice.
	_dashboard.set_density_setting(ShellPrefs.dashboard_density())
	_set_hud_visible(false)  # nothing to bind to until the level is up
	_boot()


## Decide what to boot into and load it. Three authorities, in order: a deep link
## (`?level=&vehicle=` on web, `--level=`/`--vehicle=` or CARLITO_LEVEL locally), the session
## saved in user://, then DEFAULT_LEVEL. Every id is validated on the way in (BootParams), so
## a link or a save naming a level that no longer exists falls back instead of booting into
## nothing. This is also the headless CI path — the smoke no longer needs a special case,
## because clicking a menu is no longer how anyone reaches a level.
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
## level's spawn/respawn path; a family with one variant is a no-op.
##
## ONE KEY, ONE AXIS. V always changes the BODY and never anything hanging off it — the two used
## to share this key, with the vehicle whose subsystem cycle had run out handing the press back so
## V could carry on to the next body. That worked, but it made V mean different things on different
## vehicles and left the tractor (one body, so it could never hand back) a dead end you could only
## leave through the garage. E is now the attachment axis, and the two never interact.
func _cycle_vehicle() -> void:
	if _level == null or _level.vehicle == null:
		return
	_level.set_vehicle(VehicleCatalog.next_in_family(GameState.current_variant))


## Cycle what is hanging off the back of the current vehicle (E key / touch ATTACH): the tractor's
## implement, the semi's trailer. Vehicles that tow nothing ignore it.
##
## Duck-typed, like every other cross-layer hook in this codebase (set_vehicle, grip_at,
## is_carlito_authoring), so neither this file nor VehicleCatalog learns what an implement or a
## trailer is — only that some vehicles carry one and that cycling it never changes the body.
func _cycle_attachment() -> void:
	if _level == null or _level.vehicle == null:
		return
	if _level.vehicle.has_method("cycle_implement"):
		_level.vehicle.cycle_implement()
		# The new attachment may be driven where the old one was not (a tipper for a box), so the
		# overlay's PTO/TIP buttons are re-offered here as well as on a vehicle bind. Nothing else
		# about the HUD changes — the body did not.
		_touch.set_capabilities(_capabilities())


## The same refresh, for an attachment the SIM changed on its own (GameState.attachment_changed —
## a coupling that did not fit and was taken away again). Without it the overlay keeps offering the
## PTO/TIP buttons of a trailer that is no longer there.
func _refresh_attachment_controls() -> void:
	_touch.set_capabilities(_capabilities())


## What the active vehicle can do, for the control gating ActionRegistry drives (the touch buttons
## and the pause menu's CONTROLS sheet). Every read is DUCK-TYPED, so neither this file nor the
## overlay learns what a trailer, an implement or a refuse body is — only that some machines tow,
## some have something driven or liftable on the back, and some have a lockable diff.
##
## The two sources are OR'd rather than merged, and that is load-bearing: a semi's `pto` comes from
## its trailer and a garbage truck's from its own body, so neither may cancel the other out.
func _capabilities() -> Dictionary:
	var caps := {"tows": false, "pto": false, "lift": false,
			"diff_lock": false, "fwd_drive": false, "body_cmd": false}
	if _level == null or _level.vehicle == null:
		return caps
	var v: Node3D = _level.vehicle
	caps["tows"] = v.has_method("cycle_implement")
	if v.has_method("vehicle_capabilities"):
		_or_into(caps, v.vehicle_capabilities())
	if v.has_method("attachment_controls"):
		_or_into(caps, v.attachment_controls())
	return caps


static func _or_into(caps: Dictionary, extra: Dictionary) -> void:
	for k in extra:
		caps[k] = bool(caps.get(k, false)) or bool(extra[k])


# --- pause overlay -----------------------------------------------------------

## Esc (or the touch MENU button). Walks the overlay stack out the way it came in: a screen
## opened on top of the pause menu closes back to it, the pause menu's own second page closes
## back to its first, and only then does Esc resume. Esc used to free the level outright with
## no confirmation, which is the bug this replaces.
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
	# Before add_child (the VehicleSelect.setup pattern): the CONTROLS sheet greys what this
	# machine does not have, off the same capability read the touch buttons gate on.
	_pause.setup(_capabilities(), _dashboard.density_setting())
	_pause.resume_requested.connect(_close_pause)
	_pause.vehicle_requested.connect(_open_vehicle_select)
	_pause.level_requested.connect(_show_level_select)
	_pause.dashboard_density_changed.connect(_on_density_changed)
	_ui.add_child(_pause)
	# The driving pads sit behind the scrim and are not reachable; hiding them also releases
	# anything held (Pad drops its pointer when it loses visibility) so nothing sticks.
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


## SETTINGS picked a new instrument-cluster density. The menu owns nothing, so applying it and
## remembering it are both this file's job — and it is remembered even for a deep-linked session
## (unlike the level and the vehicle, which an explicit link chose for you): how much dashboard
## you want to look at is yours, not the link's.
func _on_density_changed(setting: int) -> void:
	_dashboard.set_density_setting(setting)
	ShellPrefs.set_dashboard_density(setting)


## F2: hide the instrument cluster, and bring it back the way it was. It moves the SAME density
## setting the SETTINGS page cycles rather than adding a second reason to be hidden — one state,
## so the menu and the key can never disagree about whether there is a dashboard, and (like the
## menu) the choice is remembered.
func _toggle_dashboard() -> void:
	if _dashboard.density_setting() == Dashboard.Density.OFF:
		_on_density_changed(_density_before_hide)
	else:
		_density_before_hide = _dashboard.density_setting()
		_on_density_changed(Dashboard.Density.OFF)


# --- level select ------------------------------------------------------------

## The LEVEL section of the pause menu (G-key garage aside, this is only ever reached from
## there). Opening it does not tear the current level down — that only happens once a
## different level is actually chosen.
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
## `variant` is the body to spawn instead of the level's default ("" = the default).
## Headless (CI smoke) keeps the synchronous path — nobody is watching a bar there.
func _load_level(scene_path: String, variant := "") -> void:
	if _level != null:
		# Unbind BEFORE the free: a threaded load takes frames, and the dashboard, the debug
		# overlay and the bridge would each be holding a freed level for all of them.
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
	_ui.add_child(_loading)  # in the tree first: it dresses itself with theme-scaled metrics
	_loading.set_level(scene_path)
	_loading_path = scene_path
	ResourceLoader.load_threaded_request(scene_path, "", true)  # sub-threads: parallel sub-resource loads


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
			# Instantiate blocks this frame (level._ready spawns the vehicle
			# synchronously); the loading screen stays up over the freeze, and for
			# HOLD_FRAMES more so the first-draw shader compile is behind it too.
			_finish_load(scene)
			_hold_frames = HOLD_FRAMES
		_:
			var failed := _loading_path
			push_error("Level load failed: %s" % failed)
			_loading_path = ""
			_drop_loading_screen()
			# There is no menu to fall back to any more, so fall back to the level a first
			# visit gets — unless that is the one that just failed, in which case something
			# is wrong with the build and another attempt would only loop.
			var default_scene := LevelRegistry.scene_of(DEFAULT_LEVEL)
			if failed != default_scene:
				_load_level(default_scene)


## Take the loading overlay down. Safe to call with nothing up (the failure path and the
## HOLD_FRAMES countdown both reach it), and it also clears the countdown so a level chosen
## during the hold cannot leave a stale timer pointing at a freed screen.
func _drop_loading_screen() -> void:
	_hold_frames = 0
	if _loading != null:
		_loading.queue_free()
		_loading = null


func _finish_load(scene: PackedScene) -> void:
	_level = scene.instantiate()
	# Set BEFORE the level enters the tree: it spawns its vehicle in _ready, and this is how
	# a deep link or the saved session gets a body other than the level's default without
	# spawning the default first and immediately throwing it away.
	_level.initial_variant = _next_variant
	_next_variant = ""
	# This node is PROCESS_MODE_ALWAYS so the pause menu keeps running; the level is a child
	# of it and would inherit that, so the world is put back to pausable explicitly.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)  # level._ready() spawns the vehicle synchronously here
	_level.vehicle_changed.connect(_on_vehicle_changed)
	_bind_hud()
	_set_hud_visible(true)
	# The initial spawn already happened above, before the signal was connected, so the
	# session is saved here rather than only in _on_vehicle_changed.
	_save_session()
	# GameState.current_vehicle is the FAMILY, and the initial spawn already set it above.
	_maybe_coach(GameState.current_vehicle)


## Remember where the player is, so a reload resumes it. No-op for a deep-linked or headless
## run (see _persist).
func _save_session() -> void:
	if not _persist or _level == null:
		return
	ShellPrefs.save_boot(LevelRegistry.id_of(_level.scene_file_path), GameState.current_variant)


## Families that get a cue of their own every time you climb into one this session, because their
## controls include an axis the ground vehicles have no equivalent of.
const COACH_FAMILIES := ["plane", "drone"]


## The coaching line, for the vehicle just spawned. Two cues live here and they have different
## lifetimes, which is the whole of the logic:
##
##   - the FIRST-VISIT line, once per machine and only for the first level of a session — it
##     teaches how to start, and by the second level you have started;
##   - the AIRCRAFT line, once per family per SESSION, because climb/descend is undiscoverable and
##     you meet it again every time you leave the ground.
##
## The aircraft case takes precedence on a brand-new machine: it is the more useful sentence for
## somebody sitting in a plane, and the first-visit line is left unseen (and unmarked) for the next
## ground vehicle.
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


## (Re)bind the HUD + bridge to the active level/vehicle. Called at load and whenever the
## garage swaps the vehicle (its type drives which dashboard cluster is built).
func _bind_hud() -> void:
	_dashboard.bind(_level)
	_debug.set_level(_level)  # F3 overlay reads the active vehicle's per-wheel surface grip
	_touch.set_capabilities(_capabilities())  # each control offered only where it does something
	Bridge.bind(_level)  # telemetry source for the ~20 Hz outbound publish (web only)


## Drop every reference to the level about to be freed. The mirror of _bind_hud, and the
## reason it exists separately: nothing may outlive the level it points at.
func _unbind_hud() -> void:
	_dashboard.bind(null)
	_debug.set_level(null)
	_touch.set_capabilities({})
	Bridge.bind(null)


func _on_vehicle_changed(type: String) -> void:
	_bind_hud()
	_save_session()
	# Level.vehicle_changed carries the FAMILY, so getting into an aircraft mid-session is coached
	# the same way arriving in one is.
	_maybe_coach(type)


# --- vehicle selector --------------------------------------------------------

## The garage, replaced: body, variant and attachment on one screen with a preview, instead of a
## family menu plus two invisible key cycles.
##
## IT PAUSES THE WORLD, whether it was opened from the pause menu or straight off G. Two reasons,
## and the first is not cosmetic: the selector's preview is a REAL vehicle body in a SubViewport,
## and a second live body while you are driving is a class of hazard this shell does not need. The
## second is that a screen you read is a screen you are not driving through.
func _open_vehicle_select() -> void:
	if _level == null or _loading_path != "" or _vehicles != null:
		return
	_vehicles = VehicleSelect.new()
	# Before add_child (the setup pattern every shell screen uses). The level's RAW allow-list plus
	# its runtime rail answer, never a pre-filtered roster: the screen shows what it cannot spawn
	# and has to be able to say why. Level.has_closed_rail() is still the one closed-loop walk.
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


## What is on the back of the machine being driven, so the selector opens showing the trailer you
## actually have rather than the catalog's first. Duck-typed like every other cross-layer hook, so
## the shell still does not learn what a trailer or an implement is.
func _current_attachment() -> String:
	if _level == null or _level.vehicle == null \
			or not _level.vehicle.has_method("current_attachment"):
		return ""
	return String(_level.vehicle.current_attachment())


## Picked a body: respawn as it — but only if it is a different one. Re-picking what you are
## already driving to change its trailer must not teleport you back to the spawn marker.
func _on_vehicle_picked(variant: String) -> void:
	_close_vehicle_select()
	_close_pause()  # picked a vehicle: back to driving it, not back to the menu
	if variant != GameState.current_variant:
		_level.set_vehicle(variant)


## Emitted straight after _on_vehicle_picked, and only for a machine that tows — so `_level.vehicle`
## is already the body that was picked. Same setter E goes through.
func _on_attachment_picked(id: String) -> void:
	if _level == null or _level.vehicle == null \
			or not _level.vehicle.has_method("set_attachment"):
		return
	if String(_level.vehicle.current_attachment()) == id:
		return
	_level.vehicle.set_attachment(id)
	_touch.set_capabilities(_capabilities())  # the new attachment may be driven where the old was not


func _cycle_camera() -> void:
	if _level != null:
		_level.cycle_camera()


## The touch NIGHT button. Day/night is a Level concern (the N key reaches it directly), so this
## is a relay and nothing more — same shape as _cycle_camera.
func _toggle_day_night() -> void:
	if _level != null:
		_level.toggle_day_night()


func _respawn() -> void:
	if _level != null and _level.vehicle != null:
		_level.vehicle.respawn()


# --- helpers -----------------------------------------------------------------

func _set_hud_visible(v: bool) -> void:
	# set_shown, not `.visible`: the dashboard also hides itself at density OFF, and neither
	# reason to be hidden may overwrite the other.
	_dashboard.set_shown(v)
	_touch.set_active(v)
	if not v:
		_notice.visible = false


## Show a transient message from the sim (GameState.notice). Re-showing restarts the dwell rather
## than queueing, so holding E against a wall reads as one steady message instead of a stutter, and
## the timer is a SceneTreeTimer rather than per-frame state — there is nothing to reset on a level
## change beyond hiding the label, which _set_hud_visible already does.
func _show_notice(text: String, dwell_s: float) -> void:
	_notice.text = text
	_notice.visible = true
	var token := text + str(Time.get_ticks_msec())
	_notice.set_meta("token", token)
	var dwell := dwell_s if dwell_s > 0.0 else NOTICE_DWELL_S
	await get_tree().create_timer(dwell).timeout
	if is_instance_valid(_notice) and _notice.get_meta("token", "") == token:
		_notice.visible = false


## Take a notice down early (GameState.notice_cleared) once what it warned about is fixed. Matches
## on the text so it can only ever hide its OWN message — a later notice that replaced it keeps the
## rest of its dwell. The pending timer above is harmless afterwards: it re-checks the token.
func _clear_notice(text: String) -> void:
	if _notice.visible and _notice.text == text:
		_notice.visible = false
