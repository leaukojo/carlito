extends GdUnitTestSuite
## Instrument cluster density. What is pinned here is the thing driving cannot check: that a
## density mode drops whole SECTIONS and never a generated signal. The tell-tales are generated
## by walking the contract, and some of them exist for exactly one vehicle (the train's
## pantograph, the truck's DM1 lamps) — so "COMPACT quietly lost a lamp" is a bug that would
## only show on one machine, on one screen size.
##
## The cluster builds headless: it is Controls and custom _draw widgets, and bind(null) leaves
## it with no level to read telemetry from, which is all these cases need.

## Families whose clusters are compared across densities. Every generated section is
## represented: isobus bars + request/state lamp pairs (tractor), DM1 + trailer lamps (truck),
## the reverser and its 'gear'-without-'rpm' case (train), and the speedo-only vehicle (boat).
const FAMILIES: PackedStringArray = ["car", "tractor", "truck", "train", "boat", "plane"]

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


## THE ONE THAT MATTERS. Every tell-tale, chip and gauge the contract generates for a vehicle is
## on screen in COMPACT exactly as it is in FULL — the mode drops the bars and the readout line,
## which are whole sections, and nothing signal-shaped beyond them.
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


## The generation rules themselves are untouched by this phase: a family with isobus bars still
## has them at FULL, and the lamp row is never empty for a machine the contract describes.
func test_full_still_generates_the_bars_and_lamps() -> void:
	var tractor := _dash("tractor", Dashboard.Density.FULL)
	assert_array(tractor._bars.keys()).contains(["hitch_pos_actual", "pto_rpm", "engine_load"])
	assert_dict(tractor._lamps).is_not_empty()
	assert_dict(tractor._out_lamps).is_not_empty()


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
