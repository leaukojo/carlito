class_name CardImport
extends RefCounted

## Import settings for the selector card thumbnails (`src/ui/level_thumbs/`,
## `src/ui/vehicle_thumbs/`). Cards are photographs shown at one size, never sampled in 3D,
## so they import lossy with no mipmaps — a real download saving.
##
## Godot's `.import` sidecar defaults to lossless, so a freshly shot card silently costs more
## than its neighbours unless the generator stamps it itself; both thumb generators call this
## right after `save_png` (mirrors `TerrainGen.ensure_import_settings`, which stamps the
## opposite way for heightmaps/splatmaps, since terrain reads those back with `get_image()`).

## Quality of the lossy WebP. 0.9 is what the shipped 43 sidecars carry.
const LOSSY_QUALITY := 0.9

## Under src/ because tools/* and kit/thumbs/* are export-excluded and the selectors need
## these PNGs at runtime.
const VEHICLE_THUMB_DIR := "res://src/ui/vehicle_thumbs"
const LEVEL_THUMB_DIR := "res://src/ui/level_thumbs"


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
