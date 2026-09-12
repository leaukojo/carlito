class_name ChallengeDef
extends Resource
## One challenge: what to drive and where, the course overlay, the briefing, and the ordered goals
## plus the constraints that fail it. A .tres under `src/challenges/defs/`, listed in
## ChallengeRegistry and held to `ChallengeRegistry.problems()` by the suite.

## How the level is lit for the attempt, applied to its duplicated Environment: DARK is no sun,
## zero ambient and a black sky; FOG is heavy fog at `fog_density`.
enum Visibility { DAY, DARK, FOG }

@export var id := ""
@export var title := ""
## A VehicleCatalog variant. The family is derived from it (`family()`), never stored beside it.
@export var variant := "sedan-sports"
## A scene from the family's attachment catalog (TrailerCatalog / ImplementCatalog), laid at spawn
## because E is locked. "" is the catalog's own NONE — bobtail or detached — and the only legal
## value for a family with no catalog.
@export var attachment := ""
## E stays live for this challenge: coupling has no signal (Truck 1 is the one that needs it).
@export var allow_attach_key := false
@export var arena := ""   ## a LevelRegistry id
## A path, never a PackedScene: an island course ships in its arena's level pack, which is not
## mounted when the registry loads its defs.
@export_file("*.tscn") var course := ""
@export var spawn_jitter_m := 0.0     ## seeded per attempt, so a replayed frame log drifts
@export var spawn_jitter_deg := 0.0
@export_multiline var briefing := ""
@export_multiline var hint := ""      ## the signals involved, revealed by HINT
@export var par_s := 0.0              ## over it fails the attempt; 0 = no par
@export var visibility: Visibility = Visibility.DAY
@export var fog_density := 0.0        ## FOG only
@export var goals: Array[ChallengeGoal] = []
@export var constraints: Array[ChallengeConstraint] = []


func family() -> String:
	return VehicleCatalog.family_of(variant)
