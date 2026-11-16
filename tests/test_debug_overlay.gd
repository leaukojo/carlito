extends GdUnitTestSuite
## The F3 overlay opens shown on the dev channel's pages only.


func test_shown_by_default_only_under_the_dev_directory() -> void:
	assert_bool(DebugOverlay.shown_by_default("/carlito/dev/c2-abc12345.html")).is_true()
	assert_bool(DebugOverlay.shown_by_default("/carlito/dev/")).is_true()
	for path in ["/carlito/stable/c2-abc12345.html", "/carlito/", "/index.html", ""]:
		assert_bool(DebugOverlay.shown_by_default(path)) \
			.override_failure_message("'%s'" % path).is_false()
