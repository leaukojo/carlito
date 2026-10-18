extends GdUnitTestSuite
## The rough-ground dev level's layout (tools/rough_ground_layout.gd): the ditch profile and wall
## angles its header states, the bump fields' tapers, and the promise that both lanes carry the
## same relief, which is what makes an asphalt/mud pair a comparison of surfaces alone.

const Layout := preload("res://tools/rough_ground_layout.gd")


func _ditch(patch_name: String) -> int:
	return Layout.patch_index(patch_name)


func test_patches_are_disjoint_and_in_driving_order() -> void:
	for i in range(1, Layout.PATCHES.size()):
		assert_float(Layout.patch_start_z(i)).is_less(Layout.patch_end_z(i - 1))


func test_ditch_samples_on_the_grid_as_the_header_states() -> void:
	# Integer z rows through the 60 cm ditch: [0, d/3, d, d/3, 0].
	var i := _ditch("ditch_60")
	var z0 := Layout.patch_start_z(i)
	var got: Array[float] = []
	for k in 5:
		got.append(Layout.relief(i, 0.0, z0 - float(k)))
	var want: Array[float] = [0.0, -0.6 / 3.0, -0.6, -0.6 / 3.0, 0.0]
	for k in 5:
		assert_float(got[k]).is_equal_approx(want[k], 1e-6)


func test_thirty_five_cm_inner_wall_is_under_the_mud_ceiling() -> void:
	# The mud ceiling for a perfect all-wheel drive on the reference tyre: atan(grip - added crr).
	var ceiling := rad_to_deg(atan(Surface.ref_grip(Surface.MUD) - Surface.drag(Surface.MUD)))
	var i := _ditch("ditch_35")
	var z0 := Layout.patch_start_z(i)
	# The inner segment, row 1 to row 2 (the centre line).
	var drop := Layout.relief(i, 0.0, z0 - 1.0) - Layout.relief(i, 0.0, z0 - 2.0)
	assert_float(rad_to_deg(atan(drop))).is_less(ceiling)


func test_sixty_cm_inner_wall_is_over_the_mud_ceiling() -> void:
	# The mud lane ends on a traction-limited ditch: its inner wall is steeper than the reference
	# tyre's mud ceiling.
	var ceiling := rad_to_deg(atan(Surface.ref_grip(Surface.MUD) - Surface.drag(Surface.MUD)))
	var i := _ditch("ditch_60")
	var z0 := Layout.patch_start_z(i)
	var drop := Layout.relief(i, 0.0, z0 - 1.0) - Layout.relief(i, 0.0, z0 - 2.0)
	assert_float(rad_to_deg(atan(drop))).is_greater(ceiling)


func test_bump_fields_fade_to_nothing_at_their_ends() -> void:
	for i in Layout.PATCHES.size():
		if int(Layout.PATCHES[i]["kind"]) != Layout.Kind.BUMPS:
			continue
		for dx in [-4.0, 0.0, 3.5]:
			assert_float(Layout.relief(i, dx, Layout.patch_start_z(i))).is_equal(0.0)
			assert_float(Layout.relief(i, dx, Layout.patch_end_z(i))).is_equal(0.0)


func test_bumps_stay_within_their_amplitude() -> void:
	for i in Layout.PATCHES.size():
		if int(Layout.PATCHES[i]["kind"]) != Layout.Kind.BUMPS:
			continue
		var amp := float(Layout.PATCHES[i]["amp"])
		var z := Layout.patch_start_z(i)
		while z > Layout.patch_end_z(i):
			for dx in [-5.0, -2.5, 0.0, 2.5, 5.0]:
				assert_float(absf(Layout.relief(i, dx, z))).is_less_equal(amp)
			z -= 0.5


func test_relief_is_zero_off_the_lane() -> void:
	# The generator adds relief(i, x - lane_x, z) per lane; past half a lane width nothing is
	# stamped, so neither lane's relief reaches the median or the other lane.
	var i := Layout.patch_index("bumps_20")
	var z := Layout.patch_start_z(i) - 10.0
	assert_float(Layout.relief(i, Layout.LANE_WIDTH * 0.5 + 0.1, z)).is_equal(0.0)
	assert_float(Layout.relief(i, 1.3, z)).is_not_equal(0.0)


func test_lanes_do_not_overlap() -> void:
	var a: float = Layout.LANES[0]["x"]
	var b: float = Layout.LANES[1]["x"]
	assert_float(absf(a - b)).is_greater_equal(Layout.LANE_WIDTH)
