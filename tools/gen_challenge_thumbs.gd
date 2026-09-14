extends Node
## Challenge card generator: renders a screenshot of the vehicle right after it spawns on each
## challenge's own course, to src/ui/challenge_thumbs/<challenge_id>.png — replacing the arena's
## one shared landscape shot with something that actually differs challenge to challenge. Reuses
## the level's own ChaseCamera (`Level.set_vehicle` already aims and snaps it), so the framing
## matches what the player sees on START. Must run WINDOWED. Instantiates the arena for real, so
## Level._ready swaps in the baked scene — bake first.

const ShotStage := preload("res://tools/shot_stage.gd")

const SIZE := Vector2i(640, 360)  # 16:9, 2x the card so it stays crisp
const SETTLE_FRAMES := 90  # suspension drop + terrain/shader compile before read-back
const FOG_HAZE := 0.25  # fog_density * shot distance — see _thin_fog

var _viewport: SubViewport


func _ready() -> void:
	var only := OS.get_cmdline_user_args()
	DirAccess.open("res://").make_dir_recursive(CardImport.CHALLENGE_THUMB_DIR.trim_prefix("res://"))
	var written := 0
	var failed := 0
	for d in ChallengeRegistry.all():
		if not only.is_empty() and not only.has(d.id):
			continue
		if await _shoot(d):
			written += 1
		else:
			failed += 1
	print("[challenge thumbs] wrote %d image(s), %d failed" % [written, failed])
	get_tree().quit(1 if failed > 0 else 0)


## Render one challenge into a throwaway SubViewport and save its PNG. Each gets a fresh
## viewport (`own_world_3d`) since the arena brings its own WorldEnvironment/Sun.
func _shoot(d: ChallengeDef) -> bool:
	var arena_path := LevelRegistry.scene_of(d.arena)
	var arena_packed: PackedScene = load(arena_path) if arena_path != "" else null
	if arena_packed == null:
		push_error("[challenge thumbs] %s: cannot load arena '%s'" % [d.id, d.arena])
		return false
	var course_packed := load(d.course) as PackedScene
	var course := course_packed.instantiate() as Node3D if course_packed != null else null
	if course == null:
		push_error("[challenge thumbs] %s: cannot load course '%s'" % [d.id, d.course])
		return false

	_viewport = ShotStage.build_viewport(SIZE)
	add_child(_viewport)

	var level := arena_packed.instantiate() as Node3D
	_viewport.add_child(level)  # runs Level._ready: baked swap + default vehicle

	var lvl := level as Level
	lvl.add_child(course)  # ArenaPreview inside frees itself outside the editor

	var family := d.family()
	var spawn: VehicleSpawn = null
	for n in course.find_children("*", "VehicleSpawn", true, false):
		if (n as VehicleSpawn).accepts(family):
			spawn = n as VehicleSpawn
			break
	if spawn == null:
		push_error("[challenge thumbs] %s: course has no spawn for the %s family" % [d.id, family])
		_viewport.queue_free()
		_viewport = null
		return false

	lvl.set_vehicle(d.variant, spawn)  # aims and snaps lvl.camera at the new vehicle
	_thin_fog(level, lvl.camera.global_position.distance_to(spawn.global_position))

	await ShotStage.settle(get_tree(), SETTLE_FRAMES)
	var out := CardImport.challenge_thumb_path(d.id)
	var ok := ShotStage.save_capture(_viewport, out)

	_viewport.queue_free()
	_viewport = null

	if not ok:
		return false
	CardImport.ensure_import_settings(out)
	print("[challenge thumbs] %s -> %s" % [d.id, out])
	return true


## Fog is tuned for ground-level driving, so a wide shot reads as a white sheet; thin to a fixed
## haze at the shot's own distance (mirrors gen_level_thumbs.gd). Safe to mutate — Environment is
## duplicated per level.
func _thin_fog(level: Node3D, dist: float) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null or not env.fog_enabled:
			continue
		env.fog_density = minf(env.fog_density, FOG_HAZE / maxf(dist, 1.0))
		return
