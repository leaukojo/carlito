class_name Level
extends Node3D
## Base script for every playable level. A level scene is
## self-contained: static geometry, VehicleSpawn markers, a WorldEnvironment, a
## ChaseCamera, and a LevelInfo resource. This script composes them at load time —
## it instances the default vehicle at a matching spawn, points the camera at it,
## and handles respawn. Vehicles/levels/UI stay independent scenes.

## Emitted after the active vehicle is (re)spawned — at load and on a garage/cycle swap —
## so the shell can rebind the dashboard/bridge to the new vehicle FAMILY.
signal vehicle_changed(type: String)

@export var info: LevelInfo
## The chase camera to follow the active vehicle. Optional; a level may omit it.
@export var camera: ChaseCamera

## Night preset: a dim bluish sun + low
## ambient. The 'day_night' action toggles between the scene-authored day values
## (captured at load) and these — a level convenience, not a bridge signal.
const NIGHT_SUN_ENERGY := 0.12
const NIGHT_SUN_COLOR := Color(0.55, 0.62, 0.85)
const NIGHT_AMBIENT_ENERGY := 0.12
const NIGHT_FOG_COLOR := Color(0.05, 0.07, 0.13)
const NIGHT_SKY_ENERGY := 0.05

## Fullscreen color-grade + vignette (see vignette.gdshader). Built in code so every level
## gets it with no per-scene edit and no re-bake — same pattern BaseVehicle uses for dust.
const VIGNETTE_SHADER := preload("res://src/levels/base/vignette.gdshader")

var vehicle: BaseVehicle

## Variant to spawn INSTEAD of the level's own default — the shell sets it from a deep link
## or the saved session before the level enters the tree. Empty, unknown, not allowed here, or
## a train with no loop to run on: the level's default wins, so a stale link lands you in a
## playable level rather than an empty one.
var initial_variant := ""

var _sun: DirectionalLight3D
var _env: Environment
var _is_night := false
var _day_sun_energy := 1.0
var _day_sun_color := Color.WHITE
var _day_ambient_energy := 1.0
var _day_fog_color := Color.WHITE
var _day_sky_energy := 1.0

## Warm cache for the current family's other variants — see _warm_family(). Holding the
## Resources here is what keeps them in the ResourceLoader cache; drop the array and the
## next V press pays the full blocking load again.
var _warm: Array[Resource] = []
var _warming: PackedStringArray = []


func _ready() -> void:
	if info == null:
		info = LevelInfo.new()
	if camera == null:
		# Fall back to the first ChaseCamera in the level so a scene that only has
		# the node (no explicit `camera` wire) still follows the vehicle.
		for node in find_children("*", "ChaseCamera", true, false):
			camera = node as ChaseCamera
			break
	# GameState is fetched by path, not by autoload identifier: the CLI bake tools
	# (--script mode) load level scenes headless, where autoload
	# globals don't resolve at compile time. Runtime behaviour is identical.
	_game_state().current_level = scene_file_path
	_setup_baked()
	_capture_day_night()
	_build_vignette()
	# default_vehicle names a FAMILY (see LevelInfo); resolve it to that family's first
	# variant, the same body the garage spawns via boot.gd's first_in_family.
	var wanted := VehicleCatalog.first_in_family(info.default_vehicle)
	if initial_variant != "" and _can_spawn(initial_variant):
		wanted = initial_variant
	_spawn_vehicle(wanted)


## Whether `variant` could actually spawn here — allowed by LevelInfo, and for the rail-guided
## train, a closed loop to place it on. The same two gates _spawn_vehicle would fail on, asked
## in advance so a requested variant can fall back instead of erroring.
func _can_spawn(variant: String) -> bool:
	if not info.allows(variant):
		return false
	return VehicleCatalog.family_of(variant) != "train" or has_closed_rail()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn") and vehicle != null:
		vehicle.respawn()
	elif event.is_action_pressed("day_night"):
		toggle_day_night()
	elif event.is_action_pressed("camera_view"):
		cycle_camera()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# Raw wheel rather than an InputMap action: this is a view control with no bridge or
		# touch twin, so it never reaches VehicleInput and needs no arbitration.
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(-1.0)


## Advance the chase camera to its next view (C key / touch VIEW button).
func cycle_camera() -> void:
	if camera != null:
		camera.cycle()


## Zoom the chase camera's current view (mouse wheel; ISO and TOP only).
func zoom_camera(steps: float) -> void:
	if camera != null:
		camera.zoom(steps)


## Swap kit authoring content for the baked scene when one exists.
## The AuthoringRoot subtree (GridMap palettes + KitPiece prefabs) is the bake
## tool's INPUT: with a bake present it is freed at load (and export strips it from
## shipped builds entirely); without one the level plays the authoring content
## directly — fine for dev iteration, but per-piece collision means seams are
## possible until the level is baked. Bake output sits next to the level scene by
## convention: <level>.baked.scn (see kit/bake/level_baker.gd).
func _setup_baked() -> void:
	if scene_file_path.is_empty():
		return
	var baked_path := scene_file_path.get_basename() + ".baked.scn"
	if not ResourceLoader.exists(baked_path):
		return
	var authoring := _find_authoring(self)
	add_child((load(baked_path) as PackedScene).instantiate())
	if authoring != null:
		authoring.queue_free()


## See the note in _ready: bare `GameState` would fail to compile under the CLI
## bake tools. Only called from inside the tree, where the autoload exists.
func _game_state() -> Node:
	return get_node("/root/GameState")


## AuthoringRoot is detected by its duck-typing marker (same contract the baker and
## the export-strip plugin use), so this file never depends on kit/ scripts.
static func _find_authoring(node: Node) -> Node:
	if node.has_method("is_carlito_authoring"):
		return node
	for child in node.get_children():
		var found := _find_authoring(child)
		if found != null:
			return found
	return null


## Grab the level's sun + environment and remember the authored (day) lighting so the
## night toggle is reversible. Both are optional — a level may omit either.
func _capture_day_night() -> void:
	for node in find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		break
	for node in find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		if we.environment != null:
			# Levels share one saved Environment resource; night-mode mutations must
			# stay per-level, so work on a runtime copy.
			we.environment = we.environment.duplicate(true)
		_env = we.environment
		break
	if _sun != null:
		_day_sun_energy = _sun.light_energy
		_day_sun_color = _sun.light_color
	if _env != null:
		_day_ambient_energy = _env.ambient_light_energy
		_day_fog_color = _env.fog_light_color
		_day_sky_energy = _env.background_energy_multiplier
	# A level always starts at its authored day lighting; say so, so a HUD carrying the state
	# (the touch overlay's caption) is right from the first frame of a new level too.
	GameState.night_changed.emit(_is_night)


## Flip the level between its authored day lighting and night (N key / touch NIGHT button).
## Public for the same reason cycle_camera is: the shell relays the touch overlay's button here,
## and day/night is a LEVEL concern rather than a bridge signal.
func toggle_day_night() -> void:
	_is_night = not _is_night
	if _sun != null:
		_sun.light_energy = NIGHT_SUN_ENERGY if _is_night else _day_sun_energy
		_sun.light_color = NIGHT_SUN_COLOR if _is_night else _day_sun_color
	if _env != null:
		_env.ambient_light_energy = NIGHT_AMBIENT_ENERGY if _is_night else _day_ambient_energy
		_env.fog_light_color = NIGHT_FOG_COLOR if _is_night else _day_fog_color
		_env.background_energy_multiplier = NIGHT_SKY_ENERGY if _is_night else _day_sky_energy
	GameState.night_changed.emit(_is_night)


## Add the fullscreen color-grade + vignette overlay. It lives on its own CanvasLayer at
## layer 0 so it draws over the 3D world but UNDER the shell's HUD CanvasLayer (default
## layer 1) — the dashboard gauges stay undimmed. A full-rect ColorRect carries the shader;
## it ignores mouse input so it never eats touches meant for the touch controls.
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE_SHADER
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)


## Respawn the player as `variant` at a matching spawn marker (garage / V-cycle).
## Ignores unknown/disallowed variants so a bad choice can't break the level.
func set_vehicle(variant: String) -> void:
	if not info.allows(variant):
		push_error("Level: vehicle variant '%s' not allowed here" % variant)
		return
	_spawn_vehicle(variant)


## Instance `variant` at a spawn that accepts its FAMILY, replacing any current vehicle,
## and re-aim the camera. Used at load and by set_vehicle. The family (not the variant) is
## what the bridge/dashboard/spawn filters key off, so it goes into GameState.current_vehicle.
func _spawn_vehicle(variant: String) -> void:
	var scene_path := VehicleCatalog.scene_of(variant)
	if scene_path.is_empty():
		push_error("Level: no scene registered for vehicle variant '%s'" % variant)
		return
	var family := VehicleCatalog.family_of(variant)
	# The train is rail-guided: it ignores VehicleSpawn markers and self-places on a closed
	# rail loop in its own _ready (Phase 4 adds random-loop choice + garage gating on top).
	var is_train := family == "train"
	var spawn: VehicleSpawn = null
	if is_train:
		if _find_closed_rail() == null:
			push_error("Level: vehicle family 'train' needs a closed rail loop here")
			return
	else:
		spawn = _pick_spawn(family)
		if spawn == null:
			push_error("Level: no spawn marker accepts vehicle family '%s'" % family)
			return

	if vehicle != null:
		vehicle.queue_free()

	vehicle = (load(scene_path) as PackedScene).instantiate()
	add_child(vehicle)  # triggers the vehicle's _ready — the train places its consist here
	if spawn != null:
		vehicle.global_transform = spawn.global_transform
		vehicle.spawn_transform = spawn.global_transform
		vehicle.reset_physics_interpolation()
	_game_state().current_vehicle = family
	_game_state().current_variant = variant

	if camera != null:
		camera.target = vehicle.get_camera_target()
		if not vehicle.respawned.is_connected(camera.snap):
			vehicle.respawned.connect(camera.snap)
		camera.snap.call_deferred()

	vehicle_changed.emit(family)
	_warm_family(family, variant)


## Pull the family's OTHER variants in on background threads once the spawn has settled.
## `_spawn_vehicle` uses a blocking load(), so without this the first V press into a
## never-seen body hitches the main thread on mobile. Fire-and-forget: the poll in
## _process just moves finished loads into `_warm` so the cache keeps them, and a variant
## that lands after the player already pressed V costs nothing (the blocking load simply
## joins the in-flight request).
func _warm_family(family: String, spawned: String) -> void:
	_warm.clear()  # switching families: stop holding the old one's bodies in memory
	for variant in VehicleCatalog.VARIANTS:
		var entry: Dictionary = VehicleCatalog.VARIANTS[variant]
		if String(entry["family"]) != family or variant == spawned:
			continue
		var path := String(entry["scene"])
		if _warming.has(path) or ResourceLoader.has_cached(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_warming.append(path)
	set_process(not _warming.is_empty())


func _process(_delta: float) -> void:
	for i in range(_warming.size() - 1, -1, -1):
		var path := _warming[i]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var res := ResourceLoader.load_threaded_get(path)
		if res != null:
			_warm.append(res)
		_warming.remove_at(i)
	if _warming.is_empty():
		set_process(false)


## First VehicleSpawn under this level that accepts `family`; null if none.
func _pick_spawn(family: String) -> VehicleSpawn:
	for node in find_children("*", "VehicleSpawn", true, false):
		var spawn := node as VehicleSpawn
		if spawn != null and spawn.accepts(family):
			return spawn
	return null


## First closed rail loop under this level (RailTrack.find_closed_rail is the one shared walk,
## used by TrainVehicle too so the spawn gate and the train agree on what a rail is); null if
## none.
func _find_closed_rail() -> Node:
	return RailTrack.find_closed_rail(self)


## Whether a closed rail loop exists here — the shell's roster gate: the "train" family is
## dropped from the garage menu on a level with no loop (so a stray allow-list entry can't
## offer a train that _spawn_vehicle would then refuse). Same one walk the spawn gate uses.
func has_closed_rail() -> bool:
	return _find_closed_rail() != null
