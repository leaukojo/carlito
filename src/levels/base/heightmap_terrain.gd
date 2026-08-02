@tool
class_name HeightmapTerrain
extends StaticBody3D
## Terrain from a heightmap image: a greyscale texture becomes both a
## welded ground mesh and a matching HeightMapShape3D. This is the §2-rule-2 ground
## path — a dedicated collision surface, never a trimesh scatter. One grid cell = one
## world unit, so the mesh and collision vertices coincide exactly (no shape scaling).
##
## @tool so authors see the terrain in the editor; call rebuild() after changing the
## image or size. Cells sample the red channel as normalized height [0,1] * height.
##
## Generation/chunking:
##  - The render mesh is CHUNKED (one MeshInstance3D per chunk_cells tile) so island-
##    scale maps frustum-cull instead of drawing one giant always-on mesh. Culling
##    granularity only, not LOD. Collision stays ONE HeightMapShape3D (§2-2 untouched).
##  - A FastNoiseLite GENERATOR (preset/seed/feature scale/octaves + island falloff +
##    terrace plateaus) behind Generate / Generate-random tool buttons ("random" just
##    rolls a fresh seed into gen_seed): destructive-by-button, deterministic from the seed,
##    one undoable action, writes the level's heightmap PNG (pipeline unchanged). The
##    world amplitude is the existing `height` export — generated pixels stay [0,1].
##  - An AUTO-SPLAT button seeding the RGBA splatmap (kit/terrain/terrain_splat.gdshader
##    colors: R=grass G=dirt B=sand A=rock) from slope + height, same undo discipline.
##    Pure math lives in TerrainGen (kit/terrain/terrain_gen.gd), unit-tested.
##
## Ground painting has EIGHT channels: 0..3 are splatmap.RGBA, 4..7 the optional
## splatmap2.RGBA (absent = the plain 4-channel terrain, unchanged). Both the colors and the
## names are per-level data — the colors ARE the material's shader params (edit them on the
## material to repaint a level's palette), the names are `channel_names` below. Auto-splat
## still only classifies the base four.

const SPLAT_SHADER_PATH := "res://kit/terrain/terrain_splat.gdshader"
## Splat shader color param per channel index (0..7). The one place the channel order is
## written down: the brush cursor and the panel's swatches read colors through it.
const CHANNEL_PARAMS: Array[StringName] = [
	&"grass_color", &"dirt_color", &"sand_color", &"rock_color",
	&"color5", &"color6", &"color7", &"color8",
]
## The splat shader's own `blend_sharpness` default — the fallback when the material isn't
## the splat shader (or hasn't set the param). grip_at sharpens with the same exponent the
## shader does, so friction and the drawn border agree.
const DEFAULT_BLEND_SHARPNESS := 8.0
## Sharpened-weight total below which a pixel counts as unpainted. Same threshold the splat
## shader uses to fall back to a flat color.
const MIN_SPLAT_TOTAL := 0.001
const DEFAULT_CHANNEL_NAMES := [
	"Grass", "Dirt", "Sand", "Rock", "Snow", "Mud", "Asphalt", "Gravel",
]


## Emitted when one of the source images is REPLACED wholesale — `kind` is "height",
## "splat" or "splat2". Fires for Generate, Auto-splat, road Conform, an inspector
## assignment, and the undo of any of them (they all land through the property setters).
##
## This is the seam the kit brush needs: it keeps a decoded working copy of each image in
## memory until scene save, so anything that rewrites a PNG behind its back leaves that copy
## stale — and the next stroke would stamp into the pre-button pixels and flush them, undoing
## the button. Brush-side identity checks can't stand in for this: _apply_generated reloads
## with CACHE_MODE_REPLACE, which keeps the same Texture2D instance and swaps its contents.
signal source_image_replaced(kind: String)


## The stock channel names: the `channel_names` export default, and the panel's fallback.
## A function because a PackedStringArray isn't a constant expression.
static func default_channel_names() -> PackedStringArray:
	return PackedStringArray(DEFAULT_CHANNEL_NAMES)

## Grayscale image that IS the terrain: white = high, black = low.
@export var heightmap: Texture2D:
	set(value):
		heightmap = value
		_height_dirty = true
		_rebuild_if_ready()
		source_image_replaced.emit("height")
## World-unit extent on X (width) and Z (depth). Also the collision/mesh grid size.
@export var terrain_size := Vector2(64, 64):
	set(value):
		terrain_size = value
		_rebuild_if_ready()
## How tall a fully white pixel is, in meters. The overall vertical scale — and
## therefore the generator's amplitude knob (presets peak at a fraction of it).
@export var height := 8.0:
	set(value):
		height = value
		_rebuild_if_ready()
@export var material: Material:
	set(value):
		material = value
		# The splat cache also holds the material's blend_sharpness (see _ensure_splat_cache).
		_splat_dirty = true
		_rebuild_if_ready()
## Render-mesh tile size in cells (one MeshInstance3D per tile — the frustum-cull unit).
@export var chunk_cells := 64:
	set(value):
		chunk_cells = maxi(1, value)
		_rebuild_if_ready()
@warning_ignore("unused_private_class_variable")
@export_tool_button("Rebuild terrain") var _rebuild_action := rebuild

## The roads GridMap's vertical cell (kit/import/roads.json cell_size.y) — the world-space
## lattice terraced plateaus must land on for painted tiles to sit flush.
const GRID_LEVEL_M := 3.0

@export_group("Generation")
@export var preset: TerrainGen.Preset = TerrainGen.Preset.ISLAND
## The terrain's fingerprint: the same seed always regenerates the exact same landscape.
## Change it (or use the random button) for a different one.
@export var gen_seed := 0
## Size of hills/valleys in meters. Bigger = broader, calmer shapes.
@export var feature_scale := 60.0
## Detail layers stacked on the base shape: 1 = smooth blobs, 8 = lots of fine crinkly
## detail. More octaves = slower generation, bumpier ground.
@export_range(1, 8) var gen_octaves := 4
## Island preset only: where the land starts descending to sea level, as a fraction of
## the map radius.
@export_range(0.0, 1.0) var falloff_start := 0.55
## Island preset only: where the descent reaches sea level, as a fraction of the map
## radius.
@export_range(0.0, 1.0) var falloff_end := 0.95
## Island preset only: how ragged the coastline is. 0 = perfectly round island, 1 = deep
## bays and jutting headlands. The map border always reaches sea level regardless.
@export_range(0.0, 1.0) var coast_roughness := 0.5
## Plateau band height in road-grid levels — 1 level = the roads GridMap's 3 m vertical
## cell, so plateau flats always land on paintable road heights (tiles sit flush, Conform
## becomes a touch-up). 0 disables terracing. Tip: terrain height = 51 stores the 3 m
## levels byte-exactly in the 8-bit heightmap; any other height leaves at most half a
## height/255 residual, hidden by the tile deck.
@export_range(0, 8) var terrace_levels := 3
## Portion of each terrace band that stays dead flat; the rest ramps between plateaus.
@export_range(0.0, 0.9) var terrace_flat := 0.6
## Runs the noise generator from the current gen_seed. Same generator as "Generate new
## random terrain" — that button just rolls a fresh gen_seed first (written back, so the
## result stays reproducible and undoable).
@warning_ignore("unused_private_class_variable")
@export_tool_button("Generate terrain (from seed)") var _generate_action := _generate
## Rolls a new gen_seed and runs the same generator as "Generate terrain (from seed)".
## The new seed is written back, so the result stays reproducible and undo restores the
## old seed with the old image.
@warning_ignore("unused_private_class_variable")
@export_tool_button("Generate new random terrain") var _generate_random_action := _generate_random

@export_group("Splat")
## Weights for paint channels 0..3 (RGBA = grass/dirt/sand/rock).
@export var splatmap: Texture2D:
	set(value):
		splatmap = value
		_splat_dirty = true
		_push_splat_param()
		source_image_replaced.emit("splat")
## Weights for paint channels 4..7 (RGBA). Optional: without it the terrain is a plain
## 4-channel one. The brush creates it on the first stroke of a channel >= 4.
@export var splatmap2: Texture2D:
	set(value):
		splatmap2 = value
		_splat_dirty = true
		_push_splat_param()
		source_image_replaced.emit("splat2")
## Display names for the eight paint channels, shown in the brush panel's channel picker.
## Names only — a channel's COLOR is the matching shader param on `material` (see
## CHANNEL_PARAMS); rename and recolor per level to taste.
@export var channel_names := default_channel_names()
## Tire grip multiplier per paint channel 0..7 (1.0 = the vehicle's spec grip; lower =
## slippery, e.g. ice/mud). RayWheel scales mu_long/mu_lat by the weighted splat mix under
## each contact (see grip_at). All-1.0 default = no effect, so unpainted levels are unchanged.
## Clamped to [0, 1] on read: a value above 1 would raise mu past the tuned spec (breaking
## the brake > peak-drive hierarchy on that surface) and a negative one would invert the
## friction force outright. A per-element @export_range is not a thing, hence the read clamp
## plus the configuration warning.
@export var channel_grip := PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1])
## Beaches appear below this world height (the band fades out over another half of it);
## above, grass.
@export var sand_height := 2.0
## Ground steeper than this becomes dirt.
@export var dirt_slope_deg := 22.0
## Ground steeper than this becomes rock.
@export var rock_slope_deg := 38.0
## Colors the terrain automatically from height and slope: beaches low, grass flat, dirt
## on slopes, rock on cliffs. Overwrites hand painting (undoable).
@warning_ignore("unused_private_class_variable")
@export_tool_button("Auto-splat") var _auto_splat_action := _auto_splat


# Decoded splatmap copies kept for the per-tick grip query (get_splat_weights): decoding a
# Texture2D every wheel every frame would be ruinous, so they are cached and only re-decoded
# when a splatmap is replaced (_splat_dirty, set in the setters above).
#
# EDITOR CAVEAT: the kit brush keeps its own working image and only assigns splatmap back at
# scene save, so mid-stroke these copies hold the pre-stroke pixels. Nothing drives in the
# editor, so the runtime grip query is unaffected; an in-editor consumer of grip_at would
# need the brush to push its working image.
var _splat_img: Image
var _splat2_img: Image
var _splat_dirty := true
var _sharpness := DEFAULT_BLEND_SHARPNESS  ## cached with the splat images (material param)
var _decode_warned := false                ## one-shot guard for the decode-failure warning

# Same deal for the heightmap, which grip terrain selection samples per wheel per tick
# (RayWheel compares the contact height against the terrain surface). Runtime only: in the
# editor height_at keeps reading the texture directly, so an external PNG edit reimported in
# place still shows up without a scene reload.
var _height_img: Image
var _height_dirty := true


func _ready() -> void:
	rebuild()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if splatmap != null and splatmap2 != null and splatmap.get_size() != splatmap2.get_size():
		warnings.append(("splatmap2 is %dx%d but splatmap is %dx%d — paint channels 4..7 then "
				+ "cover a different footprint than 0..3. Repaint splatmap2 at the base size.")
				% [splatmap2.get_width(), splatmap2.get_height(),
				splatmap.get_width(), splatmap.get_height()])
	for i in channel_grip.size():
		if channel_grip[i] < 0.0 or channel_grip[i] > 1.0:
			warnings.append(("channel_grip[%d] = %.2f is outside [0, 1] and will be clamped: "
					+ "above 1 breaks the vehicle's tuned brake > drive hierarchy, below 0 "
					+ "inverts tire friction.") % [i, channel_grip[i]])
	return warnings


func _rebuild_if_ready() -> void:
	if is_inside_tree():
		rebuild()


## (Re)generate the mesh + collision from the current heightmap. Safe to call in the
## editor or at runtime; a null heightmap flattens to a plane at y=0.
func rebuild() -> void:
	var dims := _grid_dims()
	var cols := dims.x   # vertices along X
	var rows := dims.y   # vertices along Z
	var img := _read_image()
	var heights := _sample_heights(img, cols, rows)

	_apply_chunks(cols, rows, heights)
	_apply_collision(cols, rows, heights)
	_push_splat_param()


## Editor incremental rebuild (terrain brush): remesh only the render chunks overlapping the
## world-space XZ rectangle, sampling heights from `img` — the brush's live working image,
## not the exported (stale) heightmap texture. Lets a sculpt stroke update geometry without
## remeshing a whole island every sample; collision is refreshed separately on stroke end.
func rebuild_region_world(img: Image, min_x: float, max_x: float,
		min_z: float, max_z: float) -> void:
	var container := get_node_or_null(^"Chunks") as Node3D
	if container == null:
		rebuild()   # nothing to patch yet — fall back to a full build
		return
	var dims := _grid_dims()
	var cols := dims.x
	var rows := dims.y
	var heights := _sample_heights(img, cols, rows)
	# A collapsed flat terrain has no chunk nodes to patch — the first sculpt stroke
	# densifies the whole mesh from the brush's live image (once; later samples patch).
	if container.get_node_or_null(^"FlatQuad") != null:
		_apply_chunks(cols, rows, heights)
		_push_splat_param()
		return
	# World XZ -> cell indices (see _build_chunk: world x of cell cx = gpos.x - (cols-1)/2 +
	# cx). Expanded one cell each side so an edit on a chunk border also refreshes the
	# neighbour's shared verts/normals.
	var span_x := float(cols - 1)
	var span_z := float(rows - 1)
	var c0 := int(floor(min_x - global_position.x + span_x * 0.5)) - 1
	var c1 := int(ceil(max_x - global_position.x + span_x * 0.5)) + 1
	var r0 := int(floor(min_z - global_position.z + span_z * 0.5)) - 1
	var r1 := int(ceil(max_z - global_position.z + span_z * 0.5)) + 1
	var edit := Rect2i(c0, r0, maxi(c1 - c0, 1), maxi(r1 - r0, 1))
	for rect in TerrainGen.chunk_ranges(cols, rows, chunk_cells):
		if not Rect2i(rect.position, rect.size).intersects(edit):
			continue
		var old := container.get_node_or_null(
				NodePath("Chunk_%d_%d" % [rect.position.x, rect.position.y]))
		if old != null:
			old.free()
		container.add_child(_build_chunk(rect, cols, rows, heights))
	_push_splat_param()


## Rebuild the collision HeightMapShape3D from `img` (terrain brush, called once at stroke end —
## HeightMapShape3D has no partial-update API, so the whole shape is reassigned, but that's
## cheap data next to remeshing and only happens on release).
func rebuild_collision_from_image(img: Image) -> void:
	var dims := _grid_dims()
	_apply_collision(dims.x, dims.y, _sample_heights(img, dims.x, dims.y))


## The source PNG a brush writes on save: the heightmap's / splatmap's own PNG when it
## has one, else beside the scene. Wraps _target_png_path so the addon reuses the exact same
## path logic as the generation buttons.
func png_path_for(kind: String) -> String:
	if kind == "height":
		return _target_png_path(heightmap, "height")
	if kind == "splat2":
		return _target_png_path(splatmap2, "splat2")
	return _target_png_path(splatmap, "splat")


## The editable color of paint channel `ch` (0..7): the material's shader param when the
## level set one, else the splat shader's own default. Gray when the material isn't a
## shader material (nothing to paint into).
func channel_color(ch: int) -> Color:
	var mat := material as ShaderMaterial
	if mat == null:
		return Color.GRAY
	var param := CHANNEL_PARAMS[clampi(ch, 0, 7)]
	var value: Variant = mat.get_shader_parameter(param)
	if value is Color:
		return value
	if mat.shader != null:
		# An unset param reads back null — ask the shader for the uniform's own default.
		var def: Variant = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), param)
		if def is Color:
			return def
	return Color.GRAY


## Display name of paint channel `ch`, falling back to the default when `channel_names` is
## short (a level may store fewer than eight).
func channel_name(ch: int) -> String:
	var i := clampi(ch, 0, 7)
	if i < channel_names.size() and not channel_names[i].is_empty():
		return channel_names[i]
	return DEFAULT_CHANNEL_NAMES[i]  # a level may store fewer than eight


## Vertex grid dimensions: one cell = one world unit, so verts = extent + 1 (min 2).
## Shared by rebuild() and height_at() so the world<->grid mapping lives in one place.
func _grid_dims() -> Vector2i:
	return Vector2i(maxi(2, int(terrain_size.x) + 1), maxi(2, int(terrain_size.y) + 1))


## World-space surface height under `world_pos`'s XZ, bilinearly sampled from the
## heightmap (the ground query used by the editor placement fallback and
## scatter ground-snap). Assumes the terrain is axis-aligned (unrotated/unscaled, as
## all authored HeightmapTerrains are); a null heightmap is flat at the node's Y.
func height_at(world_pos: Vector3) -> float:
	var img := _height_image()
	if img == null:
		return global_position.y
	var uv := _terrain_uv(world_pos)
	return global_position.y + _sample_red_bilinear(img, uv.x, uv.y) * height


## Normalized terrain UV under `world_pos`'s XZ, clamped to the extent. The one place the
## world -> splat/heightmap mapping is written down: height_at, get_splat_weights and grip_at
## all go through it, and it matches the render mesh's global UV (see _build_chunk), so the
## friction lookup lines up with what's drawn.
func _terrain_uv(world_pos: Vector3) -> Vector2:
	var dims := _grid_dims()
	var span_x := float(dims.x - 1)
	var span_z := float(dims.y - 1)
	# grid X spans [-span_x/2, +span_x/2] in local space (see _apply_chunks's x0/z0).
	var lx := world_pos.x - global_position.x
	var lz := world_pos.z - global_position.z
	return Vector2(
			clampf((lx + span_x * 0.5) / span_x, 0.0, 1.0),
			clampf((lz + span_z * 0.5) / span_z, 0.0, 1.0))


## Whether `world_pos`'s XZ lies within this terrain's extent (axis-aligned rect).
func contains_xz(world_pos: Vector3) -> bool:
	var lx := world_pos.x - global_position.x
	var lz := world_pos.z - global_position.z
	return absf(lx) <= terrain_size.x * 0.5 and absf(lz) <= terrain_size.y * 0.5


## The eight paint weights under `world_pos`'s XZ: [0..3] = splatmap.RGBA, [4..7] =
## splatmap2.RGBA (all-zero when the second map is absent), bilinearly sampled from the cached
## splat Images. Uses the SAME world->(u,v) mapping as height_at, i.e. the shader's global
## terrain UV, so the friction lookup lines up with what's drawn. Raw weights on purpose (no
## `blend_sharpness` pow — that only crispens the visual border; grip fades smoothly across a
## painted seam, which is the sensible physical behavior). All-zero when no splatmap is set.
func get_splat_weights(world_pos: Vector3) -> PackedFloat32Array:
	var weights := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_ensure_splat_cache()
	if _splat_img == null:
		return weights
	var uv := _terrain_uv(world_pos)
	var c0 := _sample_rgba_bilinear(_splat_img, uv.x, uv.y)
	weights[0] = c0.r; weights[1] = c0.g; weights[2] = c0.b; weights[3] = c0.a
	if _splat2_img != null:
		var c1 := _sample_rgba_bilinear(_splat2_img, uv.x, uv.y)
		weights[4] = c1.r; weights[5] = c1.g; weights[6] = c1.b; weights[7] = c1.a
	return weights


## Tire grip multiplier under `world_pos`: the paint-weight-blended channel_grip. 1.0 (spec
## grip) when unpainted or with no splatmap. RayWheel scales its friction coefficients by
## this. Cheap and allocation-free: <= 8 cached-Image bilinear reads, no weights array.
##
## Weights are pow-sharpened by the material's `blend_sharpness` and normalized EXACTLY as
## the splat shader does before they are mixed. Raw weights would be wrong here: the shader's
## sharpening makes the dominant channel win almost immediately, so a brush-falloff pixel of
## 0.7 grass / 0.3 ice draws as 99.9% grass while raw normalization hands it 30% of the ice
## grip — an invisible slick apron around every painted patch. Sharpening also disposes of the
## other half of that bug: normalization alone makes weight MAGNITUDE irrelevant, so the
## faintest trace of ice read as full ice. After pow(8) a faint trace falls under
## MIN_SPLAT_TOTAL and reads as unpainted, same as the shader's flat-color fallback.
##
## The one deliberate divergence from the shader: below MIN_SPLAT_TOTAL it falls back to
## neutral 1.0, not to channel 0 (the shader's grass) — channel 0 is ice in the gym, and
## unpainted ground must never inherit it.
func grip_at(world_pos: Vector3) -> float:
	if splatmap == null:
		return 1.0
	_ensure_splat_cache()
	if _splat_img == null:
		return 1.0
	var uv := _terrain_uv(world_pos)
	var c0 := _sample_rgba_bilinear(_splat_img, uv.x, uv.y)
	var c1 := Color(0, 0, 0, 0)
	if _splat2_img != null:
		c1 = _sample_rgba_bilinear(_splat2_img, uv.x, uv.y)
	var total := 0.0
	var grip := 0.0
	for i in 8:
		var raw: float = (c0 if i < 4 else c1)[i & 3]
		var w := pow(raw, _sharpness)
		total += w
		grip += w * channel_grip_at(i)
	if total < MIN_SPLAT_TOTAL:
		return 1.0
	return grip / total


## How strongly paint channel `ch` covers `world_pos`, 0..1 — the "is this surface X?" query.
## The tractor's draft force asks it "is this the ploughable field?" once per tick, so it takes
## the same allocation-free, cached-Image path as grip_at: <= 8 bilinear reads, never a
## get_image() per tick.
##
## Weights are pow-sharpened by the material's `blend_sharpness` and normalized exactly as
## grip_at (and the splat shader) does, for the same two reasons: a brush-falloff pixel must not
## report a channel the shader draws as absent, and normalization alone would make the faintest
## trace read as full coverage. 0 when unpainted, below MIN_SPLAT_TOTAL, or with no splatmap —
## unlike grip_at there is no neutral value to fall back to, "not painted" IS 0 here.
func channel_weight_at(world_pos: Vector3, ch: int) -> float:
	if splatmap == null or ch < 0 or ch >= CHANNEL_PARAMS.size():
		return 0.0
	_ensure_splat_cache()
	if _splat_img == null:
		return 0.0
	if ch >= 4 and _splat2_img == null:
		return 0.0   # a plain 4-channel terrain: channels 4..7 are unpainted by construction
	var uv := _terrain_uv(world_pos)
	var c0 := _sample_rgba_bilinear(_splat_img, uv.x, uv.y)
	var c1 := Color(0, 0, 0, 0)
	if _splat2_img != null:
		c1 = _sample_rgba_bilinear(_splat2_img, uv.x, uv.y)
	var total := 0.0
	var want := 0.0
	for i in 8:
		var raw: float = (c0 if i < 4 else c1)[i & 3]
		var w := pow(raw, _sharpness)
		total += w
		if i == ch:
			want = w
	if total < MIN_SPLAT_TOTAL:
		return 0.0
	return want / total


## The grip multiplier of channel `ch`, clamped to the sane [0, 1] range (see channel_grip)
## and defaulting to 1.0 for a level that stores a short array.
func channel_grip_at(ch: int) -> float:
	if ch < 0 or ch >= channel_grip.size():
		return 1.0
	return clampf(channel_grip[ch], 0.0, 1.0)


## Decode both splatmaps once into uncompressed working Images for get_splat_weights (and
## cache the material's blend sharpness with them); only re-runs after a splatmap or the
## material is replaced (_splat_dirty). Same decompress dance as _read_image.
func _ensure_splat_cache() -> void:
	if not _splat_dirty:
		return
	_splat_img = _decode_texture(splatmap)
	_splat2_img = _decode_texture(splatmap2)
	_sharpness = _blend_sharpness()
	_splat_dirty = false
	# A texture that refuses to decode is indistinguishable from unpainted ground: grip
	# silently goes neutral everywhere and stays there (retrying per tick would mean a
	# get_image() per wheel per frame, which is exactly what this cache exists to avoid).
	# Warn once so it is visible — including in the browser console on the web export, where
	# a texture readback is the failure most likely to differ from a desktop run.
	if splatmap != null and _splat_img == null and not _decode_warned:
		_decode_warned = true
		push_warning("HeightmapTerrain '%s': splatmap could not be decoded — per-surface tire grip is disabled for this terrain." % name)


## Decoded heightmap for the per-tick surface query, cached at runtime (see _height_img).
## In the editor it decodes per call, so an externally edited + reimported PNG is picked up
## without a scene reload.
func _height_image() -> Image:
	if Engine.is_editor_hint():
		return _read_image()
	if _height_dirty:
		_height_img = _read_image()
		_height_dirty = false
	return _height_img


## The material's splat `blend_sharpness`, or the shader's own default (same lookup shape as
## channel_color). Read once per cache refresh — never per query.
func _blend_sharpness() -> float:
	var mat := material as ShaderMaterial
	if mat == null:
		return DEFAULT_BLEND_SHARPNESS
	var value: Variant = mat.get_shader_parameter(&"blend_sharpness")
	if value == null and mat.shader != null:
		# An unset param reads back null — ask the shader for the uniform's own default.
		value = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), &"blend_sharpness")
	if value is float or value is int:
		return maxf(1.0, float(value))
	return DEFAULT_BLEND_SHARPNESS


## Uncompressed decoded copy of `tex`, or null when unset (shared by the splat cache).
static func _decode_texture(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	return img


## Bilinear RGBA lookup at normalized (u, v) in [0,1] — the all-channel sibling of
## _sample_red_bilinear, used by get_splat_weights.
func _sample_rgba_bilinear(img: Image, u: float, v: float) -> Color:
	var iw := img.get_width()
	var ih := img.get_height()
	var fx := u * float(iw - 1)
	var fy := v * float(ih - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, iw - 1)
	var y1 := mini(y0 + 1, ih - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := img.get_pixel(x0, y0).lerp(img.get_pixel(x1, y0), tx)
	var bot := img.get_pixel(x0, y1).lerp(img.get_pixel(x1, y1), tx)
	return top.lerp(bot, ty)


## Bilinear red-channel lookup at normalized (u, v) in [0,1]. Smoother than the mesh's
## nearest sampling, so a placed prop sits on the interpolated surface, not a vertex step.
func _sample_red_bilinear(img: Image, u: float, v: float) -> float:
	var iw := img.get_width()
	var ih := img.get_height()
	var fx := u * float(iw - 1)
	var fy := v * float(ih - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, iw - 1)
	var y1 := mini(y0 + 1, ih - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, tx)
	var bot := lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, tx)
	return lerpf(top, bot, ty)


## Decoded, uncompressed copy of the heightmap image, or null when unset.
func _read_image() -> Image:
	if heightmap == null:
		return null
	var img := heightmap.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	return img


## Row-major (z*cols + x) height grid: red channel * height, or all-zero without an image.
func _sample_heights(img: Image, cols: int, rows: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	if img == null:
		return data
	var iw := img.get_width()
	var ih := img.get_height()
	for z in rows:
		var v := float(z) / float(rows - 1)
		var py := clampi(int(round(v * (ih - 1))), 0, ih - 1)
		for x in cols:
			var u := float(x) / float(cols - 1)
			var px := clampi(int(round(u * (iw - 1))), 0, iw - 1)
			data[z * cols + x] = img.get_pixel(px, py).r * height
	return data


## Rebuild every render chunk (one MeshInstance3D per chunk_cells tile). Full rebuild is
## button/load-time only; brush strokes call _build_chunk for just the touched tiles.
func _apply_chunks(cols: int, rows: int, heights: PackedFloat32Array) -> void:
	var container := get_node_or_null(^"Chunks") as Node3D
	if container == null:
		var legacy := get_node_or_null(^"Mesh")   # legacy single-mesh child (hot reload)
		if legacy != null:
			legacy.free()
		# Left unowned on purpose: the mesh is regenerated from the heightmap on
		# every load, so it must never be serialized into the level scene (an
		# editor save would otherwise bake stale geometry). It
		# still renders in the editor viewport as a preview.
		container = Node3D.new()
		container.name = "Chunks"
		add_child(container)
	for child in container.get_children():
		child.free()
	# A dead-flat terrain (null heightmap or an all-uniform image) renders
	# as one two-triangle quad — the few-polygon path. Any relief re-densifies here on
	# the next full rebuild. Collision is untouched: still the one HeightMapShape3D.
	if TerrainGen.is_uniform(heights):
		container.add_child(_build_flat_quad(cols, rows,
				heights[0] if not heights.is_empty() else 0.0))
		return
	for rect in TerrainGen.chunk_ranges(cols, rows, chunk_cells):
		container.add_child(_build_chunk(rect, cols, rows, heights))


## One chunk tile: verts chunk-local (the MeshInstance3D carries the offset, so its AABB
## is tile-sized and frustum-culls), UVs global 0..1 across the whole terrain (splat
## continuity), normals analytic from the full grid (chunk borders never seam).
func _build_chunk(rect: Rect2i, cols: int, rows: int,
		heights: PackedFloat32Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := rect.size.x   # cells; verts = cells + 1 (border shared with the neighbor)
	var h := rect.size.y
	for z in h + 1:
		for x in w + 1:
			var gx := rect.position.x + x
			var gz := rect.position.y + z
			st.set_uv(Vector2(float(gx) / float(cols - 1), float(gz) / float(rows - 1)))
			st.set_normal(TerrainGen.grid_normal(heights, cols, rows, gx, gz))
			st.add_vertex(Vector3(x, heights[gz * cols + gx], z))
	for z in h:
		for x in w:
			var i := z * (w + 1) + x
			# two triangles per quad, wound CW (Godot's front-face order) so the
			# top surface renders / lights.
			st.add_index(i); st.add_index(i + 1); st.add_index(i + w + 1)
			st.add_index(i + 1); st.add_index(i + w + 2); st.add_index(i + w + 1)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [rect.position.x, rect.position.y]
	mi.position = Vector3(
			-float(cols - 1) * 0.5 + float(rect.position.x), 0.0,
			-float(rows - 1) * 0.5 + float(rect.position.y))
	mi.mesh = st.commit()
	mi.material_override = material
	return mi


## Single quad covering the whole terrain at uniform height `y` (see _apply_chunks).
## Same conventions as _build_chunk: UVs 0..1 across the terrain (splat continuity),
## CW winding, normal straight up (exact for a flat surface).
func _build_flat_quad(cols: int, rows: int, y: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := float(cols - 1)
	var h := float(rows - 1)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		st.set_uv(corner)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(corner.x * w, y, corner.y * h))
	st.add_index(0); st.add_index(1); st.add_index(2)
	st.add_index(1); st.add_index(3); st.add_index(2)
	var mi := MeshInstance3D.new()
	mi.name = "FlatQuad"
	mi.position = Vector3(-w * 0.5, 0.0, -h * 0.5)
	mi.mesh = st.commit()
	mi.material_override = material
	return mi


func _apply_collision(cols: int, rows: int, heights: PackedFloat32Array) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = cols
	shape.map_depth = rows
	shape.map_data = heights
	var cs := get_node_or_null(^"Collision") as CollisionShape3D
	if cs == null:
		# Unowned like the chunks (see _apply_chunks): regenerated per load, never saved.
		cs = CollisionShape3D.new()
		cs.name = "Collision"
		add_child(cs)
	cs.shape = shape


## Feed both splatmaps to the splat ShaderMaterial (no-op on other material types).
func _push_splat_param() -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(&"splatmap", splatmap)
		(material as ShaderMaterial).set_shader_parameter(&"splatmap2", splatmap2)


# --- generation (editor-only: destructive-by-button, undoable, never per-frame) ---


func _generate() -> void:
	_generate_with_seed(gen_seed)


func _generate_random() -> void:
	_generate_with_seed(randi_range(0, 999_999))


func _generate_with_seed(seed_value: int) -> void:
	if not Engine.is_editor_hint():
		return
	var path := _target_png_path(heightmap, "height")
	if path.is_empty():
		return
	var dims := _grid_dims()
	if terrace_levels > 0:
		# Plateaus are grid-aligned in the terrain's LOCAL frame; a terrain node sitting
		# off the 3 m world lattice shifts every plateau off the paintable road heights.
		var y_off := fposmod(global_position.y, GRID_LEVEL_M)
		if y_off > 0.01 and y_off < GRID_LEVEL_M - 0.01:
			push_warning("Terrain Y = %.2f is not a multiple of %.0f m — terraced plateaus won't align with the road GridMap levels." % [global_position.y, GRID_LEVEL_M])
	var img := TerrainGen.generate_heights(preset, seed_value, feature_scale, gen_octaves,
			falloff_start, falloff_end, dims.x, dims.y,
			float(terrace_levels) * GRID_LEVEL_M / maxf(height, 0.001),
			terrace_flat, coast_roughness)
	var props := {}
	if seed_value != gen_seed:
		props[&"gen_seed"] = [gen_seed, seed_value]
	_commit_generated("Generate terrain heightmap", [[&"heightmap", path, img]], props)


func _auto_splat() -> void:
	if not Engine.is_editor_hint():
		return
	var img := _read_image()
	if img == null:
		push_warning("Auto-splat needs a heightmap — generate or assign one first.")
		return
	var path := _target_png_path(splatmap, "splat")
	if path.is_empty():
		return
	var px_x := terrain_size.x / maxf(float(img.get_width() - 1), 1.0)
	var px_z := terrain_size.y / maxf(float(img.get_height() - 1), 1.0)
	var splat := TerrainGen.build_splatmap(img, height, px_x, px_z,
			sand_height, dirt_slope_deg, rock_slope_deg)
	var images: Array = [[&"splatmap", path, splat]]
	# Auto-splat classifies channels 0..3 only, so any painted 4..7 weight has to be zeroed
	# in the SAME action — left alone it would keep double-counting against the fresh base
	# weights, and the terrain would still read as snow/asphalt where it now says grass.
	if splatmap2 != null:
		var path2 := _target_png_path(splatmap2, "splat2")
		if not path2.is_empty():
			var zero := Image.create(splat.get_width(), splat.get_height(), false,
					Image.FORMAT_RGBA8)
			zero.fill(Color(0, 0, 0, 0))
			images.append([&"splatmap2", path2, zero])
	# One-click promise: if the current material isn't the splat shader, swap in a fresh
	# splat ShaderMaterial (inside the same undo action, so undo restores the old look).
	var props := {}
	var current := material as ShaderMaterial
	if current == null or current.shader == null \
			or current.shader.resource_path != SPLAT_SHADER_PATH:
		var new_material := ShaderMaterial.new()
		new_material.shader = load(SPLAT_SHADER_PATH)
		props[&"material"] = [material, new_material]
	_commit_generated("Auto-splat terrain", images, props)


## One undoable action around the generated image(s) (a stray click must not
## destroy hand-sculpted brush work): do applies the new images, undo restores a
## snapshot of the prior ones — both through _apply_generated, which writes the PNG and
## reimports, so disk always matches the scene. `images` is a list of
## [property, png path, new image] triples that must land or revert together (auto-splat
## rewrites splatmap AND clears splatmap2). `props` are sibling property changes
## ({name: [old, new]} — the random seed, the material swap) riding the same action.
func _commit_generated(action_name: String, images: Array, props: Dictionary) -> void:
	# Untyped on purpose: EditorUndoRedoManager is an editor-only class, so ANNOTATING with it
	# makes this @tool script fail to PARSE in exported (non-editor) builds — which silently
	# breaks every HeightmapTerrain at runtime. The value is fetched by string singleton lookup
	# and this whole function is is_editor_hint()-guarded, so dynamic typing costs nothing.
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action(action_name)
	for prop_name: StringName in props:
		# Registered first so e.g. the material is live before the image applies (do
		# runs in registration order, undo reversed).
		undo_redo.add_do_property(self, prop_name, props[prop_name][1])
		undo_redo.add_undo_property(self, prop_name, props[prop_name][0])
	for entry: Array in images:
		var prop: StringName = entry[0]
		var path: String = entry[1]
		var new_img: Image = entry[2]
		var prior: Image = null
		var tex: Texture2D = get(prop)
		if tex != null:
			prior = tex.get_image()
			if prior != null and prior.is_compressed():
				prior.decompress()
		undo_redo.add_do_method(self, &"_apply_generated", prop, path, new_img)
		undo_redo.add_undo_method(self, &"_apply_generated", prop, path, prior)
	undo_redo.commit_action()


## Write the image to its PNG (lossless import sidecar enforced), reimport, and point
## `prop` at the imported texture. A null image (undoing a first-ever Generate) just
## clears the property; the file stays on disk, harmless.
func _apply_generated(prop: StringName, path: String, img: Image) -> void:
	if not Engine.is_editor_hint():
		return
	if img == null:
		set(prop, null)
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("HeightmapTerrain: failed to write %s (%s)" % [path, error_string(err)])
		return
	TerrainGen.ensure_import_settings(path)
	# Untyped: EditorFileSystem is editor-only — see the note in _commit_generated (a type
	# annotation here breaks the exported build's parse of this runtime script).
	var filesystem = Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
	filesystem.update_file(path)
	filesystem.reimport_files(PackedStringArray([path]))
	set(prop, ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE))


## Where a generated PNG lands: over the current texture's source PNG when there is
## one (the level's heightmap), else beside the scene as
## <scene>_<node>_<kind>.png — which requires the scene to be saved once.
func _target_png_path(tex: Texture2D, kind: String) -> String:
	if tex != null and tex.resource_path.begins_with("res://") \
			and tex.resource_path.get_extension() == "png":
		return tex.resource_path
	var root := owner if owner != null else self
	var scene_path := root.scene_file_path
	if scene_path.is_empty():
		push_warning("Save the scene first — the generated PNG is written beside it.")
		return ""
	return "%s/%s_%s_%s.png" % [scene_path.get_base_dir(),
			scene_path.get_file().get_basename(), String(name).to_snake_case(), kind]
