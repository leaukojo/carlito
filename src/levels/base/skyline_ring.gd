@tool
class_name SkylineRing
extends Node3D
## A distant, fog-tinted low-poly ridge ringing the island: the
## mainland silhouette on the horizon. Visual only — one mesh, one draw call, no
## collision, no LOD, no custom shader. The level's WorldEnvironment fog does the
## blending, exactly as WaterSurface's far-sea quad relies on it.
##
## Like WaterSurface, this is a single node a level drops in: the mesh is built in code
## as an INTERNAL child (never serialized), and every export rebuilds it, so the scene
## stores five numbers instead of geometry. It lives OUTSIDE AuthoringRoot (a direct
## child of the level, next to the water) and is not part of the bake pipeline.
##
## Radius is chosen from the FOG, not from WaterSurface.far_sea_extent: surviving colour
## is exp(-fog_density * distance), so at the shared env's 0.003 a ridge reads at ~600 m
## (~17% survives) and is invisible by ~900 m (~7%, and the sky at the horizon already
## IS fog_light_color). Keep it beyond everything reachable — the islands stop at ~256 m
## and the water's perimeter walls at 280 m — but inside the camera's far plane.

## Ring segments around the full circle. Fixed, not an export: 128 is ~29 m of chord at
## r = 600 (plenty of silhouette detail at that distance) for 512 triangles.
const SEGMENTS := 128

## Distance from the level origin to the ridge crest, in metres.
@export var radius := 600.0:
	set(v):
		radius = v
		_rebuild()
## Peak crest height above the sea plane. Crests vary down to SkylineGen.CREST_MIN of it.
@export var height := 80.0:
	set(v):
		height = v
		_rebuild()
## Ridge thickness across the band: the base rings sit half of this either side of the
## crest, giving the inward and outward slopes.
@export var band_depth := 220.0:
	set(v):
		band_depth = v
		_rebuild()
## Seeds the crest noise. Same seed, same ridge — vary it per level.
@export var gen_seed := 0:
	set(v):
		gen_seed = v
		_rebuild()
## Ridge albedo. Dark and desaturated: fog leaves only a small fraction of it, and that
## fraction is what separates the ridge from the pale horizon sky. Lit (not emissive), so
## the level's night toggle dims it along with everything else.
@export var color := Color(0.18, 0.22, 0.30):
	set(v):
		color = v
		_rebuild()

var _mesh: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.roughness = 1.0
		# Cheapest shading that still reads as lit land, and all three are visually free
		# HERE specifically: the ridge is flat shaded (every vertex of a face carries the
		# same normal) and 600 m back behind ~83% fog, lit by one directional light.
		# - no specular: a matte silhouette had no highlight to lose,
		# - per-vertex lighting: constant across a flat-shaded face anyway, so this is the
		#   same picture for 1536 vertex evaluations instead of one per covered pixel
		#   (a real win on gl_compatibility, which is what the project ships),
		# - Lambert over the default Burley: no perceptible difference at this distance.
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		_mesh.material_override = mat
		# A 600 m ring must never enter the directional shadow cascades (level_1 caps
		# them at 150 m) or any GI pass — it is backdrop, not lit geometry.
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_mesh, false, Node.INTERNAL_MODE_BACK)
	(_mesh.material_override as StandardMaterial3D).albedo_color = color
	_mesh.mesh = SkylineGen.build_mesh(radius, height, band_depth, gen_seed, SEGMENTS)
