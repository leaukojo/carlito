class_name TerrainGen
extends RefCounted
## Pure, unit-tested terrain-generation math. HeightmapTerrain's
## Generate / Auto-splat buttons and the chunked render mesh all call these statics, so
## the noise remap, island falloff, splat classification, and chunk lattice get the same
## test discipline as Drivetrain (tests/test_terrain_gen.gd). Everything is deterministic
## from its arguments — same seed, same island, forever.
##
## Heightmaps stay the existing pipeline: an 8-bit greyscale PNG whose red channel is
## normalized height [0,1]; the node's `height` export is the world amplitude (meters of
## a white pixel). The splatmap is an RGBA weight image: R=grass, G=dirt, B=sand, A=rock.

enum Preset { ISLAND, ROLLING_HILLS, PLAINS, DUNES }

## Per-preset character: fractal type, frequency multiplier (relative to feature_scale),
## default octave count, relative amplitude (fraction of `height` the preset peaks at, so
## plains read gentle and islands tall at the same world scale), and radial falloff.
const PRESETS := {
	Preset.ISLAND: {
		"fractal": FastNoiseLite.FRACTAL_FBM, "freq_mult": 1.0,
		"amplitude": 1.0, "falloff": true,
	},
	Preset.ROLLING_HILLS: {
		"fractal": FastNoiseLite.FRACTAL_FBM, "freq_mult": 1.0,
		"amplitude": 0.5, "falloff": false,
	},
	Preset.PLAINS: {
		"fractal": FastNoiseLite.FRACTAL_FBM, "freq_mult": 0.7,
		"amplitude": 0.15, "falloff": false,
	},
	Preset.DUNES: {
		"fractal": FastNoiseLite.FRACTAL_RIDGED, "freq_mult": 1.2,
		"amplitude": 0.4, "falloff": false,
	},
}


## Deterministically configured noise for a preset. feature_scale is meters per noise
## feature (grid cells are 1 m); sampling happens at integer grid coordinates, so the
## same seed produces the same landscape independent of terrain size.
static func make_noise(preset: Preset, seed_value: int, feature_scale: float,
		octaves: int) -> FastNoiseLite:
	var cfg: Dictionary = PRESETS[preset]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = cfg.fractal
	noise.seed = seed_value
	noise.frequency = float(cfg.freq_mult) / maxf(feature_scale, 0.001)
	noise.fractal_octaves = maxi(1, octaves)
	return noise


## Noise sample [-1,1] -> normalized height [0,1], clamped.
static func remap01(n: float) -> float:
	return clampf((n + 1.0) * 0.5, 0.0, 1.0)


## Normalized elliptical radius from the image centre: 0 at centre, 1 at the midpoint of
## each edge, >1 in the corners (so a rectangular map still reads as one island).
static func radius01(x: int, y: int, cols: int, rows: int) -> float:
	var hx := maxf(float(cols - 1) * 0.5, 0.001)
	var hy := maxf(float(rows - 1) * 0.5, 0.001)
	var dx := (float(x) - hx) / hx
	var dy := (float(y) - hy) / hy
	return sqrt(dx * dx + dy * dy)


## Island falloff: 1 inside radius `start`, smoothstep down to 0 at `end` (edges reach
## sea level). Degenerate start >= end acts as a hard step at `start`.
static func island_falloff(r: float, start: float, end: float) -> float:
	if r <= start:
		return 1.0
	if r >= end:
		return 0.0
	var t := (r - start) / (end - start)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Terrace the normalized height into plateau bands of height `step01` (band height as a
## fraction of the terrain amplitude — i.e. step_metres / terrain height — so a metres
## step lands the same regardless of world scale). Buildable flats for villages/farms.
## Each flat plateau level is snapped to the NEAREST 8-bit heightmap value
## (roundf(level * 255.0) / 255.0) — the same residual class as the Conform button's
## round-quantize: at most half a height/255 step either side of the grid plane, hidden
## by the tile deck (terrain height = 51 m stores every 3 m level byte-exactly).
## flat_frac in [0,1) is the portion of each band that stays dead flat; the rest ramps
## between plateaus.
## step01 <= 0.0 or >= 1.0 is a no-op (terracing disabled / band taller than the terrain).
static func terrace(h: float, step01: float, flat_frac: float) -> float:
	if step01 <= 0.0 or step01 >= 1.0:
		return h
	var t := h / step01
	var f := floorf(t)
	var frac := t - f
	var ramp := _smooth01((frac - flat_frac * 0.5) / maxf(1.0 - flat_frac, 0.001))
	var level := roundf(f * step01 * 255.0) / 255.0
	return clampf(level + ramp * step01, 0.0, 1.0)


## Build the normalized heightmap image (8-bit greyscale, the existing pipeline format).
## cols x rows should be the terrain's vertex grid so 1 px = 1 vertex. Terracing (when
## terrace_step01 is in (0,1)) is applied last — after amplitude and falloff — so island
## coasts step into concentric plateau rings.
##
## coast_roughness [0,1] perturbs the island falloff's radial distance with a dedicated
## coast noise, turning the perfect circle into bays and headlands (0 = round; higher =
## raggeder). It only touches falloff presets, and a hard unperturbed guard past r=0.92
## keeps every map-border pixel at sea level regardless of roughness. At coast_roughness
## == 0 the output is byte-identical to the pre-roughness generator (back-compat pin).
static func generate_heights(preset: Preset, seed_value: int, feature_scale: float,
		octaves: int, falloff_start: float, falloff_end: float,
		cols: int, rows: int, terrace_step01 := 0.0, terrace_flat := 0.6,
		coast_roughness := 0.0) -> Image:
	var cfg: Dictionary = PRESETS[preset]
	var noise := make_noise(preset, seed_value, feature_scale, octaves)
	# Dedicated coast noise (derived seed) sampled at the grid cells, ~32 m per feature —
	# roughly the falloff band width, so bays read at coastline scale, not per-pixel fuzz.
	var coast_noise: FastNoiseLite = null
	if cfg.falloff and coast_roughness > 0.0:
		coast_noise = FastNoiseLite.new()
		coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		coast_noise.seed = seed_value + 1000003
		coast_noise.frequency = 1.0 / 32.0
	var img := Image.create(cols, rows, false, Image.FORMAT_L8)
	for y in rows:
		for x in cols:
			var h := remap01(noise.get_noise_2d(float(x), float(y))) * float(cfg.amplitude)
			if cfg.falloff:
				var r := radius01(x, y, cols, rows)
				if coast_noise != null:
					var n := coast_noise.get_noise_2d(float(x), float(y))
					var rp := r + coast_roughness * (falloff_end - falloff_start) * n
					# Perturbed falloff shapes the coast; the unperturbed guard forces the
					# outermost ring to 0 so a negative sample can never lift the border.
					h *= island_falloff(rp, falloff_start, falloff_end) \
							* island_falloff(r, 0.92, 1.0)
				else:
					h *= island_falloff(r, falloff_start, falloff_end)
			h = terrace(h, terrace_step01, terrace_flat)
			img.set_pixel(x, y, Color(h, h, h))
	return img


## Surface normal at grid vertex (x, z) by central differences over the meter-unit
## height grid (row-major, z * cols + x). Chunk meshes share these analytically derived
## normals, so chunk borders never seam the lighting (per-chunk generate_normals would —
## border verts only see one chunk's triangles).
static func grid_normal(heights: PackedFloat32Array, cols: int, rows: int,
		x: int, z: int) -> Vector3:
	var x0 := maxi(x - 1, 0)
	var x1 := mini(x + 1, cols - 1)
	var z0 := maxi(z - 1, 0)
	var z1 := mini(z + 1, rows - 1)
	var gx := (heights[z * cols + x1] - heights[z * cols + x0]) / maxf(float(x1 - x0), 1.0)
	var gz := (heights[z1 * cols + x] - heights[z0 * cols + x]) / maxf(float(z1 - z0), 1.0)
	return Vector3(-gx, 1.0, -gz).normalized()


## Slope in degrees from 4 meter-unit neighbor heights and the pixel spacing (meters).
static func slope_deg(hl: float, hr: float, hu: float, hd: float,
		px_x: float, px_z: float) -> float:
	var gx := (hr - hl) / maxf(2.0 * px_x, 0.001)
	var gz := (hd - hu) / maxf(2.0 * px_z, 0.001)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


## RGBA splat weights for one point (R=grass, G=dirt, B=sand, A=rock; sums to 1):
## rock takes over above rock_slope_deg, dirt ramps in toward dirt_slope_deg, and the
## remaining flat share is sand below sand_height (fading out over half of it again —
## the beach band) else grass.
static func classify_splat(height_m: float, slope: float, sand_height: float,
		dirt_slope_deg: float, rock_slope_deg: float) -> Color:
	var t_dirt := _smooth01(slope / maxf(dirt_slope_deg, 0.001))
	var t_rock := _smooth01((slope - dirt_slope_deg) / maxf(rock_slope_deg - dirt_slope_deg, 0.001))
	var dirt := t_dirt * (1.0 - t_rock)
	var flat := (1.0 - t_dirt) * (1.0 - t_rock)
	var sand_w := 1.0 - _smooth01((height_m - sand_height) / maxf(sand_height * 0.5, 0.001))
	return Color(flat * (1.0 - sand_w), dirt, flat * sand_w, t_rock)


## Per-pixel auto-splat over a heightmap image. height_scale is the world amplitude of a
## white pixel; px_x/px_z the world meters between pixels (terrain extent / (px - 1)).
static func build_splatmap(height_img: Image, height_scale: float, px_x: float,
		px_z: float, sand_height: float, dirt_slope_deg: float,
		rock_slope_deg: float) -> Image:
	var w := height_img.get_width()
	var h := height_img.get_height()
	var splat := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var hl := height_img.get_pixel(maxi(x - 1, 0), y).r * height_scale
			var hr := height_img.get_pixel(mini(x + 1, w - 1), y).r * height_scale
			var hu := height_img.get_pixel(x, maxi(y - 1, 0)).r * height_scale
			var hd := height_img.get_pixel(x, mini(y + 1, h - 1)).r * height_scale
			var slope := slope_deg(hl, hr, hu, hd, px_x, px_z)
			var height_m := height_img.get_pixel(x, y).r * height_scale
			splat.set_pixel(x, y, classify_splat(
					height_m, slope, sand_height, dirt_slope_deg, rock_slope_deg))
	return splat


## Whether every height in the grid is the same value (a dead-flat terrain). The mesher
## uses this to collapse a flat terrain to one two-triangle quad — the few-polygon path
## for flat ground; any relief (sculpt, generate) re-densifies on the next rebuild.
static func is_uniform(heights: PackedFloat32Array) -> bool:
	if heights.is_empty():
		return true
	var first := heights[0]
	for h in heights:
		if h != first:
			return false
	return true


## Cell-space chunk lattice for the render mesh: Rect2i positions/sizes in cells (a
## chunk of N cells has N+1 verts, sharing its border row/column with the neighbor).
## Covers (cols-1) x (rows-1) cells exactly, last chunk takes the remainder.
static func chunk_ranges(cols: int, rows: int, chunk_cells: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var cells_x := maxi(cols - 1, 1)
	var cells_z := maxi(rows - 1, 1)
	var step := maxi(chunk_cells, 1)
	for cz in range(0, cells_z, step):
		for cx in range(0, cells_x, step):
			out.append(Rect2i(cx, cz, mini(step, cells_x - cx), mini(step, cells_z - cz)))
	return out


## Write/patch the PNG's .import sidecar so generated images survive the importer:
## lossless (runtime get_image() needs real bytes), no mipmaps, detect_3d off (the
## splatmap is sampled by a 3D shader — the default detect_3d would silently reimport it
## VRAM-compressed), and no alpha-border fix (it rewrites RGB wherever alpha == 0, which
## would corrupt grass/dirt/sand weights at rock == 0). Round-trips existing sidecars.
static func ensure_import_settings(png_path: String) -> void:
	var cfg := ConfigFile.new()
	var import_path := png_path + ".import"
	cfg.load(import_path)   # missing file is fine — we're creating it
	cfg.set_value("remap", "importer", "texture")
	cfg.set_value("remap", "type", "CompressedTexture2D")
	cfg.set_value("params", "compress/mode", 0)
	cfg.set_value("params", "mipmaps/generate", false)
	cfg.set_value("params", "detect_3d/compress_to", 0)
	cfg.set_value("params", "process/fix_alpha_border", false)
	cfg.save(import_path)


## Clamped smoothstep 0..1 (GDScript's smoothstep needs from < to; this is the bare t).
static func _smooth01(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
