extends GdUnitTestSuite
## Instrument cluster density: whole sections drop in COMPACT mode, not individual signals.
## Cluster builds headless; bind(null) provides no level dependency.

## Families whose clusters are compared across densities. Every generated section is
## represented: isobus bars + request/state lamp pairs (tractor), DM1 + trailer lamps (truck),
## the reverser and its 'gear'-without-'rpm' case (train), the speedo-only vehicle (boat), and
## the INSTANCED bars (drone — the only family with contract 'count' > 1 signals).
const FAMILIES: PackedStringArray = ["car", "tractor", "truck", "train", "boat", "plane", "drone"]

var _saved_vehicle := ""


func before_test() -> void:
	_saved_vehicle = GameState.current_vehicle


func after_test() -> void:
	GameState.current_vehicle = _saved_vehicle


## A dashboard bound to `family` with no level, at an explicit density (never AUTO, so the
## result does not depend on the runner's window size).
func _dash(family: String, setting: int) -> Dashboard:
	var dash: Dashboard = auto_free(Dashboard.new())
	add_child(dash)
	dash.set_density_setting(setting)
	GameState.current_vehicle = family
	dash.bind(null)
	return dash


## COMPACT drops whole sections (bars, readout), never individual signals.
func test_compact_keeps_every_generated_telltale() -> void:
	for family in FAMILIES:
		var full := _dash(family, Dashboard.Density.FULL)
		var compact := _dash(family, Dashboard.Density.COMPACT)
		assert_array(compact._lamps.keys()).is_equal(full._lamps.keys())
		assert_array(compact._out_lamps.keys()).is_equal(full._out_lamps.keys())
		assert_array(compact._chips.keys()).is_equal(full._chips.keys())
		assert_array(compact._out_chips.keys()).is_equal(full._out_chips.keys())
		# The gauges are hand-built but still only exist where the vehicle declares the signal.
		assert_bool(compact._speedo != null).is_equal(full._speedo != null)
		assert_bool(compact._tach != null).is_equal(full._tach != null)
		# ...and so is the train's reverser, which stands in for the tacho it has no signal for.
		assert_bool(compact._reverser != null).is_equal(full._reverser != null)


## The row is as wide as the contract makes it — fifteen lamps on a truck with a trailer — so it
## has to WRAP or the ends leave the screen on a phone, which is the size COMPACT exists for.
## Pinned because an HBoxContainer looks identical on a desktop and fails only where it matters.
func test_the_telltale_row_wraps() -> void:
	var dash := _dash("truck", Dashboard.Density.COMPACT)
	var rows := dash.find_children("*", "FlowContainer", true, false)
	assert_int(rows.size()).is_equal(1)
	assert_int((rows[0] as FlowContainer).alignment).is_equal(FlowContainer.ALIGNMENT_CENTER)
	# ...and it is the row that carries the lamps, not some other container that happens to flow.
	assert_array(rows[0].get_children()).contains([dash._lamps.values()[0]])


## The generation rules are unchanged at FULL: a family with isobus bars still
## has them at FULL, and the lamp row is never empty for a machine the contract describes.
func test_full_still_generates_the_bars_and_lamps() -> void:
	var tractor := _dash("tractor", Dashboard.Density.FULL)
	assert_array(tractor._bars.keys()).contains(["hitch_pos_actual", "pto_rpm", "engine_load"])
	assert_dict(tractor._lamps).is_not_empty()
	assert_dict(tractor._out_lamps).is_not_empty()


## An instanced signal (contract 'count' N) generates N bars under one group caption, and a
## scalar one still generates exactly one — the uniform Array[DashBar] keying is what lets the
## update loop stay branch-free, so "count 1 quietly became a list of one that nobody reads" is
## the failure worth pinning. Nothing here names the drone's bars by hand: the counts come from
## the contract, so adding an instanced signal to another vehicle is covered for free.
func test_an_instanced_signal_generates_one_bar_per_instance() -> void:
	var checked := 0
	for family in FAMILIES:
		var dash := _dash(family, Dashboard.Density.FULL)
		for sig_name: String in dash._bars:
			var sig := Contract.data.get_signal_def(sig_name, "out")
			assert_object(sig).override_failure_message("bar '%s' has no contract signal" % sig_name).is_not_null()
			var group: Array = dash._bars[sig_name]
			assert_int(group.size()) \
				.override_failure_message("%s bar '%s' should have %d instances" % [family, sig_name, sig.count]) \
				.is_equal(sig.count)
			if sig.count > 1:
				checked += 1
	# ...and at least one family really is exercising the instanced path (the drone's ESCs).
	assert_int(checked).is_greater(0)


## The bars flow into columns past BAR_ROWS_MAX rows, and no group is split across a break —
## four ESC bars under one caption, half in each column, would read as two different signals.
## Counted off the contract, so this covers whatever instanced signal lands next.
func test_bar_columns_respect_the_row_cap_and_never_split_a_group() -> void:
	for family in FAMILIES:
		var dash := _dash(family, Dashboard.Density.FULL)
		var rows := 0
		for sig_name: String in dash._bars:
			var sig := Contract.data.get_signal_def(sig_name, "out")
			rows += sig.count + (1 if sig.is_instanced() else 0)
		# Every bar lives in some column; the columns are the DashBars' parents.
		var columns := {}
		for sig_name: String in dash._bars:
			var group: Array = dash._bars[sig_name]
			var parents := {}
			for bar: DashBar in group:
				parents[bar.get_parent()] = true
				columns[bar.get_parent()] = true
			assert_int(parents.size()) \
				.override_failure_message("%s: '%s' was split across columns" % [family, sig_name]) \
				.is_equal(1)
		if rows == 0:
			continue
		# One column until the cap is exceeded, and never more columns than the rows need.
		var wanted := int(ceil(float(rows) / float(Dashboard.BAR_ROWS_MAX)))
		assert_int(columns.size()) \
			.override_failure_message("%s: %d rows landed in %d columns" % [family, rows, columns.size()]) \
			.is_between(maxi(wanted, 1), maxi(wanted + 1, 1))
		if rows <= Dashboard.BAR_ROWS_MAX:
			assert_int(columns.size()) \
				.override_failure_message("%s: %d rows should stay in one column" % [family, rows]) \
				.is_equal(1)


## The instance bars are labelled with the ESC index on the wire — zero-based, matching the
## contract's esc_index and the bit position in esc_fault. A bar called "4" for the ESC the bus
## calls 3 is the kind of off-by-one a CAN bench exists to not have.
func test_instance_bars_are_labelled_with_their_zero_based_index() -> void:
	var dash := _dash("drone", Dashboard.Density.FULL)
	for sig_name: String in dash._bars:
		var sig := Contract.data.get_signal_def(sig_name, "out")
		if not sig.is_instanced():
			continue
		var group: Array = dash._bars[sig_name]
		for i in group.size():
			assert_str((group[i] as DashBar).label) \
				.override_failure_message("'%s' bar %d" % [sig_name, i]).is_equal(str(i))


## The road-speed governor rides the readout line, never a bar, and it is gated on the CONTRACT
## rather than on the telemetry field. That distinction is the whole test: `speed_limit` lives on
## the BASE VehicleTelemetry (the car family has no subclass to put it on), so every vehicle in the
## game carries the field and the engine_hours-style `t.get(...)` duck-type would have printed LIM
## on the boat and the drone. Driving one family cannot catch that; this can.
func test_the_speed_limit_rides_the_readout_and_only_where_the_contract_declares_it() -> void:
	for family in FAMILIES:
		var declares: bool = Contract.data.signals_for_vehicle(family, "out") 				.any(func(sig: RefCounted) -> bool: return sig.name == "speed_limit")
		var full := _dash(family, Dashboard.Density.FULL)
		assert_bool(full._has_speed_limit).override_failure_message(
				"'%s': cluster LIM flag disagrees with the contract" % family).is_equal(declares)
		# Range-less and unflavored, so it must never have generated a bar either.
		assert_bool(full._bars.has("speed_limit")).override_failure_message(
				"'%s': speed_limit generated a bar — it is a readout, not a full scale" % family) 			.is_false()
	# The sweep has to be sweeping something in BOTH directions, or a contract edit that dropped
	# the signal (or spread it to every family) would pass it unchanged.
	assert_bool(_dash("truck", Dashboard.Density.FULL)._has_speed_limit).is_true()
	assert_bool(_dash("boat", Dashboard.Density.FULL)._has_speed_limit).is_false()


## The hour meter rides the same readout line under the same rule, and it is the case above's
## twin for a reason: `engine_hours` used to be declared on TruckTelemetry and TractorTelemetry,
## so the duck-typed `t.get(...)` gate it had was safe. It now lives on the base beside the
## odometer — every vehicle carries it and counts it — so the gate had to become the contract
## one. Driving a truck cannot catch the regression; a boat printing HRS 0.0 is what it looks like.
func test_the_hour_meter_rides_the_readout_and_only_where_the_contract_declares_it() -> void:
	for family in FAMILIES:
		var declares: bool = Contract.data.signals_for_vehicle(family, "out") \
			.any(func(sig: RefCounted) -> bool: return sig.name == "engine_hours")
		var full := _dash(family, Dashboard.Density.FULL)
		assert_bool(full._has_engine_hours).override_failure_message(
				"'%s': cluster HRS flag disagrees with the contract" % family).is_equal(declares)
		# Range-less like speed_limit, so it must never have generated a bar either.
		assert_bool(full._bars.has("engine_hours")).override_failure_message(
				"'%s': engine_hours generated a bar — it is a readout, not a full scale" % family) \
			.is_false()
	# Swept in both directions, or a contract edit either way would pass unnoticed.
	assert_bool(_dash("tractor", Dashboard.Density.FULL)._has_engine_hours).is_true()
	assert_bool(_dash("boat", Dashboard.Density.FULL)._has_engine_hours).is_false()


## COMPACT is "two gauges and the lamp row": the bars and the GPS/odometer readout are what it
## buys back, and no bar may survive into it (a stale bar would keep updating off-screen-sized).
func test_compact_drops_the_bars_and_the_readout() -> void:
	var compact := _dash("tractor", Dashboard.Density.COMPACT)
	assert_dict(compact._bars).is_empty()
	assert_object(compact._readout).is_null()
	assert_dict(compact._lamps).is_not_empty()  # ...and keeps the row, per the case above


## OFF hides the cluster outright, and the shell's own HUD visibility may not bring it back —
## the two reasons to be hidden are independent (boot.gd _set_hud_visible).
func test_off_hides_the_cluster_even_when_the_shell_shows_the_hud() -> void:
	var dash := _dash("car", Dashboard.Density.OFF)
	dash.set_shown(true)
	assert_bool(dash.visible).is_false()

	# ...and turning it back on from SETTINGS restores it without another bind.
	dash.set_density_setting(Dashboard.Density.FULL)
	assert_bool(dash.visible).is_true()
	assert_dict(dash._lamps).is_not_empty()

	# No level bound: the HUD stays down whatever the density says.
	dash.set_shown(false)
	assert_bool(dash.visible).is_false()


## AUTO decides from the screen and the bridge, and the one thing it must never decide is OFF:
## a dashboard that vanished on its own reads as a broken build, not as a setting.
func test_auto_never_resolves_to_off() -> void:
	var dash := _dash("car", Dashboard.Density.AUTO)
	assert_int(dash.density_setting()).is_equal(Dashboard.Density.AUTO)
	assert_bool(dash.density() == Dashboard.Density.OFF).is_false()


## An explicit pick is honoured as given — AUTO's rules do not get a second say.
func test_an_explicit_setting_is_what_is_shown() -> void:
	for setting in [Dashboard.Density.FULL, Dashboard.Density.COMPACT, Dashboard.Density.OFF]:
		assert_int(_dash("car", setting).density()).is_equal(setting)


## The setting round-trips through the string ShellPrefs stores, and an unknown key (an older or
## hand-edited user://shell.cfg) falls back to AUTO rather than to a blank dashboard.
func test_density_keys_round_trip_and_reject_junk() -> void:
	for setting: int in Dashboard.DENSITY_KEYS:
		assert_int(Dashboard.setting_from_key(Dashboard.key_of(setting))).is_equal(setting)
	assert_int(Dashboard.setting_from_key("gauges-only")).is_equal(Dashboard.Density.AUTO)
	assert_int(Dashboard.setting_from_key("")).is_equal(Dashboard.Density.AUTO)


## The SETTINGS page is one button, so every mode has to be reachable by pressing it repeatedly
## and the cycle has to come back round.
func test_next_setting_cycles_every_mode() -> void:
	var seen := []
	var setting: int = Dashboard.Density.AUTO
	for _i in Dashboard.DENSITY_KEYS.size():
		seen.append(setting)
		setting = Dashboard.next_setting(setting)
	assert_int(setting).is_equal(Dashboard.Density.AUTO)  # back to the start
	assert_array(seen).contains(Dashboard.DENSITY_KEYS.keys())


## The whole node bus renders nowhere, and that is a decision rather than an omission, so it is
## asserted -- a "draws nothing" claim breaks silently otherwise. All four carry no range and no
## enum; node_health briefly had a range, which put nine rows on the 27-row cluster, took it to
## three columns and made it wider than a 1280 window. node_strip is what per-node health is for.
func test_the_node_bus_publishes_but_draws_nothing() -> void:
	var dash := _dash("drone", Dashboard.Density.FULL)
	for store in [dash._bars, dash._lamps, dash._out_lamps, dash._chips, dash._out_chips]:
		for sig_name in ["node_fail", "node_health", "node_online", "esc_fault"]:
			assert_bool((store as Dictionary).has(sig_name)) \
				.override_failure_message("'%s' grew a widget" % sig_name).is_false()


## The bar budget, from both ends. `BAR_ROWS_MAX` is bounded below by the tallest scalar cluster
## (the truck's — below it, a family with no instanced signal splits) and ABOVE by nothing at all
## except panel height, so the number is chosen by the bound that actually bites: NO CLUSTER MAY
## NEED A THIRD COLUMN. The cluster is a full-width panel with a 280 px middle between two 150 px
## gauges, so there is room to spill sideways exactly ONCE; a third column is ~1236 px across and
## pushes the gauges off the panel on a 1280-wide or UI-scaled window.
##
## This is the test that has to exist, because the arithmetic lies: packing is greedy first-fit
## over groups that may not be split, so column count ≠ ceil(rows / cap). Drone's 27 rows as
## three unsplittable 5-row ESC groups take three columns at every cap ≤ 14 (27/14 reads as 2).
func test_no_cluster_needs_a_third_bar_column() -> void:
	for family in FAMILIES:
		var columns := _bar_columns(family)
		assert_int(columns) 			.override_failure_message("%s needs %d bar columns" % [family, columns]) 			.is_less_equal(2)


## ...and the OTHER end of the budget: a SCALAR family stays in one column. The drone is the only
## vehicle with instanced signals and the only one that may split — the truck spilling
## `trailer_brake_demand` alone into a 280 px column of its own is the regression this catches,
## and it is the one that already happened.
func test_only_the_instanced_family_splits_its_bars() -> void:
	for family in FAMILIES:
		if family == "drone":
			continue
		assert_int(_bar_columns(family)) \
			.override_failure_message("%s split its bars across %d columns" % [family, _bar_columns(family)]) \
			.is_equal(1)


## How many columns a family's generated bars actually land in — the DashBars' distinct parents,
## read off the built cluster rather than recomputed from the contract.
func _bar_columns(family: String) -> int:
	var dash := _dash(family, Dashboard.Density.FULL)
	var columns := {}
	for sig_name: String in dash._bars:
		for bar: DashBar in (dash._bars[sig_name] as Array):
			columns[bar.get_parent()] = true
	return columns.size()


# --- the artificial horizon (hand-built, contract-gated) -----------------------

## Built exactly where the vehicle declares BOTH 'pitch' and 'roll', and nowhere else. Swept off
## the contract rather than named per family, so a signal spreading to another vehicle is covered.
func test_the_horizon_is_built_only_where_both_attitude_signals_are_declared() -> void:
	var built := 0
	for family in FAMILIES:
		var out_names: Array = Contract.data.signals_for_vehicle(family, "out") \
				.map(func(sig: RefCounted) -> String: return sig.name)
		var declares := Dashboard.declares_horizon(out_names)
		for density in [Dashboard.Density.FULL, Dashboard.Density.COMPACT]:
			var dash := _dash(family, density)
			assert_bool(dash._horizon != null).override_failure_message(
					"'%s': horizon presence disagrees with the contract" % family).is_equal(declares)
		if declares:
			built += 1
	# ...and the sweep is sweeping something in both directions.
	assert_int(built).is_greater(0)
	assert_int(built).is_less(FAMILIES.size())


## The two warn thresholds come off the contract, like the gauges' redline — nothing about the
## scale is typed into the widget.
func test_the_horizon_reads_its_warn_thresholds_from_the_contract() -> void:
	var dash := _dash("boat", Dashboard.Density.FULL)
	assert_object(dash._horizon).is_not_null()
	assert_float(dash._horizon.pitch_warn).is_equal(Contract.data.get_signal_def("pitch", "out").warn)
	assert_float(dash._horizon.roll_warn).is_equal(Contract.data.get_signal_def("roll", "out").warn)


## THE SIGNS. An instrument that reads backwards is worse than none, and driving one family
## cannot tell you the other two agree — so both conventions are pinned as arithmetic.
func test_the_horizon_signs_follow_the_contract_conventions() -> void:
	# Wings level: the horizon is horizontal and its own "down" is the screen's.
	assert_vector(AttitudeIndicator.horizon_dir(0.0)).is_equal_approx(Vector2(1.0, 0.0), Vector2.ONE * 1e-5)
	assert_vector(AttitudeIndicator.horizon_down(0.0)).is_equal_approx(Vector2(0.0, 1.0), Vector2.ONE * 1e-5)
	# roll + = right side down, so the horizon's RIGHT end rises (y is DOWN on a canvas).
	assert_float(AttitudeIndicator.horizon_dir(30.0).y).is_less(0.0)
	assert_float(AttitudeIndicator.horizon_dir(-30.0).y).is_greater(0.0)
	# pitch + = nose up, so the horizon slides DOWN the disc.
	var c := Vector2(50.0, 50.0)
	assert_float(AttitudeIndicator.horizon_center(c, 50.0, 10.0, 0.0).y).is_greater(c.y)
	assert_float(AttitudeIndicator.horizon_center(c, 50.0, -10.0, 0.0).y).is_less(c.y)
	# Level flight puts it through the middle, and the displacement is linear in pitch.
	assert_vector(AttitudeIndicator.horizon_center(c, 50.0, 0.0, 0.0)).is_equal_approx(c, Vector2.ONE * 1e-5)
	var one := AttitudeIndicator.horizon_center(c, 50.0, 5.0, 0.0).y - c.y
	var two := AttitudeIndicator.horizon_center(c, 50.0, 10.0, 0.0).y - c.y
	assert_float(two).is_equal_approx(one * 2.0, 1e-4)


## The ground is carved out of the disc by clipping, so the clip has to degrade sanely at the
## two poses where it produces nothing: straight up and straight down.
func test_the_ground_polygon_covers_all_or_none_of_the_disc_at_the_extremes() -> void:
	var c := Vector2(50.0, 50.0)
	var disc := PackedVector2Array()
	for i in 32:
		var t := TAU * float(i) / 32.0
		disc.append(c + Vector2(cos(t), sin(t)) * 50.0)
	# Nose hard down: the horizon is off the top, so the disc is all ground.
	var down := AttitudeIndicator.horizon_center(c, 50.0, -90.0, 0.0)
	assert_int(AttitudeIndicator.clip_half_plane(disc, down, Vector2(0.0, 1.0)).size()).is_greater(2)
	# Nose hard up: the horizon is off the bottom, so there is no ground at all.
	var up := AttitudeIndicator.horizon_center(c, 50.0, 90.0, 0.0)
	assert_int(AttitudeIndicator.clip_half_plane(disc, up, Vector2(0.0, 1.0)).size()).is_equal(0)
	# A NAN warn (a signal with no threshold) never reads as past it.
	assert_bool(AttitudeIndicator.past_warn(999.0, NAN)).is_false()
	assert_bool(AttitudeIndicator.past_warn(-46.0, 45.0)).is_true()


# --- the node health strip (the bus made visible) -----------------------------

## One square per contract INSTANCE of node_health, on the family that declares it and on no
## other — and it survives COMPACT, because that signal renders nowhere else on the cluster.
func test_the_node_strip_is_built_only_where_node_health_is_declared() -> void:
	var built := 0
	for family in FAMILIES:
		var sig := Contract.data.get_signal_def(Dashboard.NODE_HEALTH_SIGNAL, "out")
		var declares: bool = sig != null and family in sig.vehicles
		for density in [Dashboard.Density.FULL, Dashboard.Density.COMPACT]:
			var dash := _dash(family, density)
			var want: int = sig.count if declares else 0
			assert_int(dash._node_squares.size()).override_failure_message(
					"'%s' at density %d: %d node squares, wanted %d"
					% [family, density, dash._node_squares.size(), want]).is_equal(want)
		if declares:
			built += 1
	assert_int(built).is_equal(1)  # the drone, and nothing else


## Each square is captioned with the node's own name from the ROSTER — the strip's whole point
## is saying WHICH node went, so an unnamed or misordered square is the failure worth pinning.
func test_the_node_squares_are_labelled_from_the_roster_in_order() -> void:
	var dash := _dash("drone", Dashboard.Density.FULL)
	assert_int(dash._node_squares.size()).is_equal(DroneBus.count())
	for i in dash._node_squares.size():
		var cell := dash._node_squares[i].get_parent()
		var label := cell.get_child(1) as Label
		assert_str(label.text).override_failure_message("node square %d" % i) \
				.is_equal(DroneBus.name_of(i))
	# ...and there is a colour for every health value the bus can publish, CRITICAL included.
	assert_int(Dashboard.NODE_HEALTH_COLOR.size()).is_greater(DroneBus.HEALTH_CRITICAL)


## The drone's four enum readouts reach the cluster through the GENERIC path and nothing else:
## a flavored enum "out" signal becomes a chip, full stop. Nothing in `_build_telltale_row` names
## them, and `OUT_CHIP_TEXT` is a cosmetic caption table that a missing entry falls back out of —
## so this is swept off the contract rather than listed, and a fifth dronecan enum is covered the
## day it is declared. What it protects is the RULE: the moment one of these needs a special case,
## the special case has to be generic or this fails.
func test_every_flavored_enum_out_signal_becomes_a_chip_with_no_special_casing() -> void:
	var seen := 0
	for family in FAMILIES:
		var dash := _dash(family, Dashboard.Density.FULL)
		for sig in Contract.data.signals_for_vehicle(family, "out"):
			var wants: bool = sig.has_enum() and sig.flavor != ""
			assert_bool(dash._out_chips.has(sig.name)).override_failure_message(
					"'%s' out signal '%s': chip presence disagrees with (enum + flavor)"
					% [family, sig.name]).is_equal(wants)
			if wants:
				seen += 1
		# ...and no chip exists that no signal asked for.
		for chip_name: String in dash._out_chips:
			var def := Contract.data.get_signal_def(chip_name, "out")
			assert_bool(def != null and def.has_enum() and def.flavor != "") 					.override_failure_message("chip '%s' has no flavored enum behind it" % chip_name) 					.is_true()
	assert_int(seen).is_greater(0)
	# The drone's four really are among them, so the sweep is not vacuously passing.
	var drone := _dash("drone", Dashboard.Density.FULL)
	for sig_name in ["mode_actual", "arming_state", "fix_type", "failsafe"]:
		assert_bool(drone._out_chips.has(sig_name)).override_failure_message(
				"'%s' did not land as a generated chip" % sig_name).is_true()
