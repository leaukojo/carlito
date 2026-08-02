class_name CardImport
extends RefCounted

## Import settings for the selector CARD thumbnails (`src/ui/level_thumbs/`,
## `src/ui/vehicle_thumbs/`).
##
## Cards are photographs shown at one size and never sampled in 3D, so they import LOSSY
## with no mipmaps — 1.03 MB -> 0.33 MB across the shipped set, and unlike a VRAM-compressed
## blob that is a real DOWNLOAD saving (lossless `.ctex` is already deflated and gzips no
## further).
##
## Godot writes a `.import` sidecar with its LOSSLESS defaults the first time it sees a new
## PNG, so a newly shot card silently costs ~20 KB more than its neighbours unless the
## generator stamps the sidecar itself. Both `tools/gen_level_thumbs.gd` and
## `tools/gen_vehicle_thumbs.gd` call this right after `save_png`, the same discipline as
## `TerrainGen.ensure_import_settings` (which stamps the opposite way — heightmaps and
## splatmaps must stay lossless, because the terrain reads them back with `get_image()`).
##
## Lives here rather than on `LevelShot` (`kit/helpers/`) or `VehicleShot` (`src/ui/`)
## because it belongs to neither: it is a property of the cards, which both produce.

## Quality of the lossy WebP. 0.9 is what the shipped 43 sidecars carry.
const LOSSY_QUALITY := 0.9


## Stamp `png_path`'s `.import` sidecar so the card imports lossy and mipmap-free.
## Existing keys are preserved (`cfg.load` first), so re-running a generator over a card
## that is already correct is a no-op, and Godot fills in every key not set here.
static func ensure_import_settings(png_path: String) -> void:
	var cfg := ConfigFile.new()
	var import_path := png_path + ".import"
	cfg.load(import_path)   # missing file is fine — we're creating it
	cfg.set_value("remap", "importer", "texture")
	cfg.set_value("remap", "type", "CompressedTexture2D")
	cfg.set_value("params", "compress/mode", 1)          # 1 = lossy
	cfg.set_value("params", "compress/high_quality", false)
	cfg.set_value("params", "compress/lossy_quality", LOSSY_QUALITY)
	cfg.set_value("params", "mipmaps/generate", false)   # drawn at one size, never in 3D
	cfg.save(import_path)
