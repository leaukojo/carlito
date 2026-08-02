extends GdUnitTestSuite
## Selector-card import settings (`CardImport`). The generators only ever write the `.png`,
## so without this stamp Godot imports a NEW card with its lossless defaults and it quietly
## costs ~20 KB more than the 43 already in the tree. Same discipline as
## `TerrainGen.ensure_import_settings`, stamping the opposite way (cards want lossy;
## heightmaps must stay lossless because the terrain reads them back).

const Card := preload("res://src/ui/card_import.gd")

const PNG := "user://card_import_test.png"
const SIDECAR := PNG + ".import"


func after_test() -> void:
	DirAccess.remove_absolute(SIDECAR)


func test_writes_lossy_mipmapless_params() -> void:
	DirAccess.remove_absolute(SIDECAR)
	Card.ensure_import_settings(PNG)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SIDECAR)).is_equal(OK)
	assert_str(String(cfg.get_value("remap", "importer"))).is_equal("texture")
	assert_str(String(cfg.get_value("remap", "type"))).is_equal("CompressedTexture2D")
	assert_int(int(cfg.get_value("params", "compress/mode"))).is_equal(1)
	assert_bool(bool(cfg.get_value("params", "compress/high_quality"))).is_false()
	assert_float(float(cfg.get_value("params", "compress/lossy_quality"))) \
			.is_equal_approx(Card.LOSSY_QUALITY, 1e-6)
	assert_bool(bool(cfg.get_value("params", "mipmaps/generate"))).is_false()


func test_preserves_godots_own_keys_and_is_idempotent() -> void:
	# Godot owns the uid/path/dest_files bookkeeping; a re-shot card must not lose it.
	DirAccess.remove_absolute(SIDECAR)
	var seed_cfg := ConfigFile.new()
	seed_cfg.set_value("remap", "uid", "uid://abc123")
	seed_cfg.set_value("deps", "source_file", PNG)
	seed_cfg.save(SIDECAR)

	Card.ensure_import_settings(PNG)
	Card.ensure_import_settings(PNG)   # re-running a generator is a no-op

	var cfg := ConfigFile.new()
	assert_int(cfg.load(SIDECAR)).is_equal(OK)
	assert_str(String(cfg.get_value("remap", "uid"))).is_equal("uid://abc123")
	assert_str(String(cfg.get_value("deps", "source_file"))).is_equal(PNG)
	assert_int(int(cfg.get_value("params", "compress/mode"))).is_equal(1)


func test_shipped_cards_are_all_stamped() -> void:
	# The saving is only real if every card in the tree actually carries it — a card shot
	# before the generators stamped would still be lossless and nothing else would notice.
	for dir_path in ["res://src/ui/level_thumbs/", "res://src/ui/vehicle_thumbs/"]:
		for f in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".png.import"):
				continue
			var cfg := ConfigFile.new()
			assert_int(cfg.load(dir_path + f)).is_equal(OK)
			assert_int(int(cfg.get_value("params", "compress/mode", 0))) \
					.override_failure_message("%s%s imports lossless" % [dir_path, f]) \
					.is_equal(1)
