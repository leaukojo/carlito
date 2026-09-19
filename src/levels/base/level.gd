class_name Level
extends Node3D
## Base script for every playable level: composes static geometry, VehicleSpawn markers,
## a WorldEnvironment, a ChaseCamera, and a LevelInfo — spawns the default vehicle, aims the camera, handles respawn.

## Emitted after the active vehicle is (re)spawned, so the shell rebinds dashboard/bridge.
signal vehicle_changed(type: String)

@export var info: LevelInfo
## The chase camera to follow the active vehicle; optional.
@export var camera: ChaseCamera
## World wind (see WindField); null is dead calm. Only flight bodies read it.
@export var wind: WindField
## Tidal stream (see CurrentField); null is still water. Only the boat reads it.
@export var current: CurrentField

## Night preset: dim bluish sun + low ambient, toggled against the authored day values — a level convenience, not a bridge signal.
const NIGHT_SUN_ENERGY := 0.12
const NIGHT_SUN_COLOR := Color(0.55, 0.62, 0.85)
const NIGHT_AMBIENT_ENERGY := 0.12
const NIGHT_FOG_COLOR := Color(0.05, 0.07, 0.13)
const NIGHT_SKY_ENERGY := 0.05

## Camera orbit per pixel of a right-button drag. Negative on both axes so the drag carries the
## world with it (drag right and the vehicle swings right); flip a sign to invert that axis.
const ORBIT_DEG_PER_PIXEL := Vector2(-0.3, -0.3)

## Fullscreen color-grade + vignette, built in code so every level gets it with no re-bake.
const VIGNETTE_SHADER := preload("res://src/levels/base/vignette.gdshader")
const Groups := preload("res://src/levels/base/carlito_groups.gd")
const WorldConditions := preload("res://src/levels/base/world_conditions.gd")
const Layers := preload("res://src/physics/collision_layers.gd")

var vehicle: BaseVehicle

## Variant to spawn instead of the level's default (set by the shell from a deep link or
## saved session). Falls back to default if empty, unknown, disallowed, or a loopless train.
var initial_variant := ""

## Right button held, and whether it has moved since — a press that never moved is a recenter.
var _orbiting := false
var _orbit_dragged := false

var _sun: DirectionalLight3D
var _env: Environment
var _is_night := false
## Set by the shell while a challenge owns the lighting: the N key does nothing. `set_night` is
## not gated, since the shell calls it to apply and restore the lighting.
var day_night_locked := false
var _day_sun_energy := 1.0
var _day_sun_color := Color.WHITE
var _day_ambient_energy := 1.0
var _day_fog_color := Color.WHITE
var _day_sky_energy := 1.0

## Warm cache for the current family's other variants (see _warm_family); holding the
## Resources here keeps them in the ResourceLoader cache.
var _warm: Array[Resource] = []
var _warming: PackedStringArray = []

## Seconds of level time, accumulated from the physics delta so the environment fields are a function of ticks elapsed, not frame-rate jitter. Serves both wind and current.
var _env_time := 0.0

## Authored `wind`/`current`, captured before the first `set_conditions` override so a LEVEL
## preset can restore them; a null side-car is captured as null the same way.
var _authored_wind: WindField
var _authored_current: CurrentField


## Tagged in `_init`, not `_enter_tree`: bake tools load level scenes that never enter a tree.
func _init() -> void:
	add_to_group(Groups.LEVEL)


func _ready() -> void:
	if info == null:
		info = LevelInfo.new()
	if camera == null:
		# Fall back to the first ChaseCamera so a scene with no explicit `camera` wire still follows.
		for node in find_children("*", "ChaseCamera", true, false):
			camera = node as ChaseCamera
			break
	GameState.current_level = scene_file_path
	_setup_baked()
	_capture_day_night()
	_capture_conditions()
	_build_vignette()
	# default_vehicle names a family; resolve to its first variant (boot.gd's first_in_family).
	var wanted := VehicleCatalog.first_in_family(info.default_vehicle)
	if initial_variant != "" and _can_spawn(initial_variant):
		wanted = initial_variant
	_spawn_vehicle(wanted)
	set_physics_process(wind != null or current != null)


## Whether `variant` could spawn here: allowed by LevelInfo, and for the train, a closed rail loop.
func _can_spawn(variant: String) -> bool:
	if not info.allows(variant):
		return false
	return VehicleCatalog.family_of(variant) != "train" or has_closed_rail()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn") and vehicle != null:
		vehicle.respawn()
	elif event.is_action_pressed("day_night") and not day_night_locked:
		toggle_day_night()
	elif event.is_action_pressed("camera_view"):
		cycle_camera()
	elif event is InputEventMouseButton:
		# Raw wheel/button, not an InputMap action: view controls with no bridge/touch twin, no
		# arbitration needed.
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			if mb.pressed:
				_orbit_dragged = false
			elif not _orbit_dragged:
				recenter_camera()  ## a right-CLICK (no drag) puts the view back
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(-1.0)
	elif _orbiting and event is InputEventMouseMotion:
		var rel := (event as InputEventMouseMotion).relative
		if rel != Vector2.ZERO:
			_orbit_dragged = true
			orbit_camera(rel * ORBIT_DEG_PER_PIXEL)


## Advances the chase camera to its next view (C key / touch CAMERA button).
func cycle_camera() -> void:
	if camera != null:
		camera.cycle()


## Zooms the chase camera's current view (mouse wheel; every view but HOOD).
func zoom_camera(steps: float) -> void:
	if camera != null:
		camera.zoom(steps)


## Turns the chase camera's current view around the vehicle (right-drag; every view but HOOD).
func orbit_camera(degrees: Vector2) -> void:
	if camera != null:
		camera.orbit(degrees)


## Puts the current view back to its authored angle (right-click without a drag).
func recenter_camera() -> void:
	if camera != null:
		camera.recenter()


## Swaps kit authoring content for the baked scene when one exists (<level>.baked.scn); without one, per-piece collision can seam.
func _setup_baked() -> void:
	if scene_file_path.is_empty():
		return
	# Exported scenes have AuthoringRoot stripped (strip_export.gd), so a missing one does not
	# mean "nothing baked" — the baked scene is the only geometry there.
	var authoring := Groups.find_authoring(self)
	var baked_path := scene_file_path.get_basename() + ".baked.scn"
	if not ResourceLoader.exists(baked_path):
		if authoring != null:
			# .baked.scn is untracked build output, so a fresh clone lands here until it bakes once.
			push_warning(("%s is running UNBAKED authoring content — per-piece dev collision and "
					+ "unmerged meshes; perf here does not resemble the shipped build. "
					+ "Run tools/bake_levels.tscn.") % scene_file_path.get_file())
		return
	add_child((load(baked_path) as PackedScene).instantiate())
	if authoring != null:
		authoring.queue_free()


## Grabs the sun + environment and remembers the authored (day) lighting so night is reversible.
func _capture_day_night() -> void:
	for node in find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		break
	for node in find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		if we.environment != null:
			# Levels share one saved Environment resource; night mutations must stay per-level.
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
	# A level always starts at authored day lighting; emit so the HUD is right from frame one.
	GameState.night_changed.emit(_is_night)


## Flips between authored day lighting and night (N key).
func toggle_day_night() -> void:
	set_night(not _is_night)


## Sets day/night directly (the pause-menu CONDITIONS page); a no-op below the same state, so a
## re-selected value costs nothing and does not re-emit.
func set_night(on: bool) -> void:
	if on == _is_night:
		return
	_is_night = on
	if _sun != null:
		_sun.light_energy = NIGHT_SUN_ENERGY if _is_night else _day_sun_energy
		_sun.light_color = NIGHT_SUN_COLOR if _is_night else _day_sun_color
	if _env != null:
		_env.ambient_light_energy = NIGHT_AMBIENT_ENERGY if _is_night else _day_ambient_energy
		_env.fog_light_color = NIGHT_FOG_COLOR if _is_night else _day_fog_color
		_env.background_energy_multiplier = NIGHT_SKY_ENERGY if _is_night else _day_sky_energy
	GameState.night_changed.emit(_is_night)


## Whether the level is currently showing its night preset.
func is_night() -> bool:
	return _is_night


## This level's own duplicated Environment (null without a WorldEnvironment). A challenge's
## visibility preset is written onto it and restored from a snapshot, like `set_night`'s values.
func environment() -> Environment:
	return _env


## The level's sun, or null.
func sun_light() -> DirectionalLight3D:
	return _sun


## Captures the authored `wind`/`current` before any CONDITIONS override, so a later LEVEL
## preset has a side-car to restore.
func _capture_conditions() -> void:
	_authored_wind = wind
	_authored_current = current


## Applies the pause-menu CONDITIONS choice (wind/current preset, shared compass direction),
## replacing `wind`/`current` for every reader (`WindField.at`/`CurrentField.at` sample them
## live, never a cached copy). LEVEL restores the authored side-cars captured in `_ready`.
func set_conditions(wind_preset: int, current_preset: int, from_deg: float) -> void:
	wind = WorldConditions.wind_for(wind_preset, _authored_wind, from_deg)
	current = WorldConditions.current_for(current_preset, _authored_current, from_deg)
	set_physics_process(wind != null or current != null)


func _physics_process(delta: float) -> void:
	_env_time += delta


## World wind vector (m/s, world space, y=0); zero on a level with no WindField.
func wind_vector() -> Vector3:
	return Vector3.ZERO if wind == null else wind.vector_at(_env_time)


## Tidal current vector (m/s, world space, y=0); zero on a level with no CurrentField.
func current_vector() -> Vector3:
	return Vector3.ZERO if current == null else current.vector_at(_env_time)


## Adds the color-grade + vignette overlay on layer 0 (under the shell's HUD layer 1); ignores mouse input.
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


## Respawns the player as `variant` at a matching spawn marker, or at `at` when given (a challenge
## course's marker, which `pick_spawn` would not choose); ignores disallowed variants.
func set_vehicle(variant: String, at: VehicleSpawn = null) -> void:
	if not info.allows(variant):
		push_error("Level: vehicle variant '%s' not allowed here" % variant)
		return
	_spawn_vehicle(variant, at)


## Instances `variant` at `at`, or at a spawn accepting its family, replacing any current vehicle,
## and re-aims the camera.
func _spawn_vehicle(variant: String, at: VehicleSpawn = null) -> void:
	var scene_path := VehicleCatalog.scene_of(variant)
	if scene_path.is_empty():
		push_error("Level: no scene registered for vehicle variant '%s'" % variant)
		return
	var family := VehicleCatalog.family_of(variant)
	# The train is rail-guided: ignores VehicleSpawn markers, self-places on a closed rail loop.
	var is_train := family == "train"
	var spawn: VehicleSpawn = null
	if is_train:
		if _find_closed_rail() == null:
			push_error("Level: vehicle family 'train' needs a closed rail loop here")
			return
	else:
		spawn = at if at != null else pick_spawn(family)
		if spawn == null:
			push_error("Level: no spawn marker accepts vehicle family '%s'" % family)
			return

	if vehicle != null:
		# Detach before freeing: queue_free() defers to end of frame, else the outgoing body
		# stays in the tree (and collidable, sharing layer VEHICLE) for a physics tick under the new one.
		remove_child(vehicle)
		vehicle.queue_free()

	vehicle = (load(scene_path) as PackedScene).instantiate()
	add_child(vehicle)  # triggers _ready — the train places its consist here
	if spawn != null:
		var placed := _rest_transform(vehicle, spawn.global_transform)
		vehicle.global_transform = placed
		vehicle.spawn_transform = placed
		vehicle.reset_physics_interpolation()
	GameState.current_vehicle = family
	GameState.current_variant = variant

	if camera != null:
		camera.target = vehicle.get_camera_target()
		if not vehicle.respawned.is_connected(camera.snap):
			vehicle.respawned.connect(camera.snap)
		camera.snap.call_deferred()

	vehicle_changed.emit(family)
	_warm_family(family, variant)


## The marker's transform with the origin raised to `vehicle.rest_ride_height()` above the ground
## below it (basis and x/z unchanged), so a wheeled body spawns with its wheels just touching
## instead of dropping onto its springs. 0.0 height (boat/drone/train) or no ground under the
## marker leaves the marker transform exactly as authored — a boat's marker must never be pulled
## down to the seabed.
func _rest_transform(body: BaseVehicle, marker_xf: Transform3D) -> Transform3D:
	var rest := body.rest_ride_height()
	if rest <= 0.0:
		return marker_xf
	var origin := marker_xf.origin
	var query := PhysicsRayQueryParameters3D.create(
			origin + Vector3.UP * 5.0, origin + Vector3.DOWN * 50.0, Layers.SOLID)
	query.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return marker_xf
	return Transform3D(marker_xf.basis, Vector3(origin.x, hit.position.y + rest, origin.z))


## Pulls the family's other variants in on background threads so the first V press into a new body doesn't hitch.
## Not on the web: that export is single-threaded, so every "threaded" request would run to
## completion inside this call, and the whole family would load synchronously under the spawn.
func _warm_family(family: String, spawned: String) -> void:
	_warm.clear()  # switching families: stop holding the old one's bodies in memory
	if OS.has_feature("web"):
		return
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


## First VehicleSpawn accepting `family`; null if none.
func pick_spawn(family: String) -> VehicleSpawn:
	for node in find_children("*", "VehicleSpawn", true, false):
		var spawn := node as VehicleSpawn
		if spawn != null and spawn.accepts(family):
			return spawn
	return null


## First closed rail loop here (RailTrack.find_closed_rail is the one shared walk); null if none.
func _find_closed_rail() -> Node:
	return RailTrack.find_closed_rail(self)


## Whether a closed rail loop exists — the shell's roster gate drops "train" from the garage menu when it doesn't.
func has_closed_rail() -> bool:
	return _find_closed_rail() != null


## Whether `_spawn_vehicle` could actually place `family` here — the same rail check for "train",
## the same `pick_spawn` walk otherwise — so the vehicle selector can refuse DRIVE with a reason
## instead of `_spawn_vehicle` silently `push_error`-ing and leaving the old vehicle in place.
func has_spawn_for(family: StringName) -> bool:
	if family == "train":
		return has_closed_rail()
	return pick_spawn(String(family)) != null
