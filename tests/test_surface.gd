extends GdUnitTestSuite
## Surface: the one table every terrain channel and measure tool reads.


func test_every_row_is_complete_and_in_range() -> void:
	assert_int(Surface.NAMES.size()).is_equal(Surface.COUNT)
	assert_int(Surface.REF_GRIP.size()).is_equal(Surface.COUNT)
	assert_int(Surface.DRAG.size()).is_equal(Surface.COUNT)
	for s in Surface.COUNT:
		assert_str(Surface.NAMES[s]).is_not_empty()
		# Read raw: the accessors clamp, so only the table itself can show an out-of-range figure.
		assert_float(Surface.REF_GRIP[s]).is_between(0.0, 1.0)
		assert_float(Surface.DRAG[s]).is_between(0.0, Surface.MAX_DRAG)


func test_asphalt_is_the_reference() -> void:
	assert_float(Surface.ref_grip(Surface.ASPHALT)).is_equal(1.0)
	assert_float(Surface.drag(Surface.ASPHALT)).is_equal(0.0)
	assert_int(Surface.ASPHALT).is_equal(0)


func test_an_unknown_id_reads_asphalt() -> void:
	for bad: int in [-1, Surface.COUNT, 99]:
		assert_bool(Surface.is_valid(bad)).is_false()
		assert_float(Surface.ref_grip(bad)).is_equal(1.0)
		assert_float(Surface.drag(bad)).is_equal(0.0)


func test_from_key_round_trips_every_name() -> void:
	for s in Surface.COUNT:
		assert_int(Surface.from_key(Surface.NAMES[s])).is_equal(s)
		assert_int(Surface.from_key(Surface.NAMES[s].to_lower())).is_equal(s)
	assert_int(Surface.from_key("tarmac")).is_equal(-1)
