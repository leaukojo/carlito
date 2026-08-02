class_name Dashboard
extends Control
## Instrument cluster. The mandated split:
##   - the tell-tale row and the bars are GENERATED from contract signal metadata
##     (name, range, warn thresholds) — add a bool "in" signal or a warn'd "out"
##     signal to the JSON and it appears here, no code change;
##   - the two radial gauges (speedo, tacho) are HAND-BUILT widgets that only READ
##     their scale/redline from the contract.
## This is emphatically NOT a generic dashboard-from-JSON framework: which two signals
## are gauges, and the cosmetic lamp labels/colors, are hand-picked here; the repetitive
## parts (the lamp row, the bars) are generated. Plain text + color only.
##
## DENSITY. The full cluster is a lot of screen on a phone, and it is redundant while
## sloppyCAN is up beside it showing the same numbers — but it is also the ONLY view of the
## contract when you are standalone, so the answer is modes rather than deletion:
##   FULL     everything (below);
##   COMPACT  the tell-tale row and the gauges — no bars, no GPS/odometer readout;
##   OFF      nothing at all.
## What COMPACT drops is only ever WHOLE SECTIONS. The generation rules are untouched: which
## lamps, chips, bars and gauges exist for a vehicle is still decided by walking the contract,
## so no density can quietly lose a signal that only one vehicle declares — every tell-tale
## the contract produces is on screen in both visible modes.
##
## The setting is AUTO by default and resolves per the plan: never OFF on its own, COMPACT on a
## phone-sized screen or while the bridge is live, FULL otherwise. It is overridable (and
## persisted) from the pause menu's SETTINGS page.

## The two signals rendered as bespoke radial gauges (never as generated bars).
const GAUGE_SIGNALS: PackedStringArray = ["kmh", "rpm"]

## What is on screen. AUTO is a SETTING value only — `density()` never returns it.
enum Density {AUTO, FULL, COMPACT, OFF}
## Stable ids for the persisted setting (a cfg file a human may open), and the order the
## SETTINGS page cycles them in.
const DENSITY_KEYS := {
	Density.AUTO: "auto", Density.FULL: "full",
	Density.COMPACT: "compact", Density.OFF: "off",
}
## Window short edge (logical px, see UiScale) at or below which AUTO picks COMPACT. A phone
## is under this in either orientation; a laptop window is comfortably over it.
const COMPACT_SHORT_EDGE := 520.0
## How long a change in Bridge.is_active() must hold before AUTO rebuilds for it. Freshness
## flips on a 300 ms window (Bridge.FRESHNESS_MS), so a peer publishing slowly would otherwise
## rebuild the cluster over and over.
const BRIDGE_DWELL_S := 2.0

# --- layout metrics (logical px at scale 1.0, scaled through UiTheme.px) -------

const PANEL_PAD_X := 14.0
const PANEL_PAD_Y := 8.0
const SECTION_GAP := 6.0   ## between the tell-tale row and the cluster below it
const LAMP_GAP := 10.0     ## between tell-tales
const CLUSTER_GAP := 24.0  ## between speedo, middle column and tacho
const MID_W := 280.0       ## middle column (bars + readout) minimum width
const MID_GAP := 8.0       ## between the bars stacked in it
const GAUGE_W := 150.0
const GAUGE_W_COMPACT := 112.0
const BAR_H := 18.0
## Enum "in" signals shown as small state chips (gear is shown on the tacho instead).
const ENUM_CHIPS: PackedStringArray = ["key", "lights", "pto_mode", "body_cmd"]

## Cosmetic tell-tale presentation (UI styling, not signal data): short caption + lit
## color per known lamp. Unknown lamps fall back to the upper-cased signal name / amber.
const LAMP_TEXT := {
	"handbrake": "BRAKE", "turnL": "<L", "turnR": "R>", "horn": "HORN",
	"checkEngine": "CHECK", "battery": "BATT", "brakeLamp": "STOP",
	"pto": "PTO REQ", "pto_state": "PTO", "arm": "ARM", "armed": "ARMED",
	"implement_connected": "IMPL",
	# tractor driveline: the request lamps sit beside their state lamps, captioned REQ like the
	# train's pantograph/doors pair below.
	"diff_lock": "DIFF REQ", "diff_lock_state": "DIFF",
	"fwd_drive": "MFWD REQ", "fwd_drive_state": "MFWD",
	# train: the "in" request lamps sit right next to their "out" state lamps in the same
	# row, so the requests are captioned REQ to stay readable at the small tell-tale size.
	"pantograph": "PAN REQ", "pantograph_state": "PANTO",
	"doors": "DOOR REQ", "doors_state": "DOORS",
	# truck J1939-73 DM1 lamp status byte. checkEngine above already IS DM1's MIL, so these
	# are the other three and no fourth is invented for it.
	"red_stop": "RSL", "amber_warn": "AWL", "protect_lamp": "PROT",
	# CiA 422 body network, reached across the CiA 413 gateway. INHIB is the interlock computed on
	# the chassis side, BODY BUS is whether the body network is powered at all.
	"body_inhibit": "INHIB", "body_bus": "BODY BUS",
	# ISO 11992 trailer bus. TRLR is the coupling claim — dark with a trailer physically on the back
	# is a real state rather than a bug (see the contract desc); ABS and EBS come off the trailer.
	"trailer_connected": "TRLR", "trailer_abs": "ABS", "trailer_ebs_fault": "EBS",
	# SAE J2497 power line, the North American conventional's ENTIRE trailer protocol. It sits
	# beside the ISO 11992 lamps rather than replacing them: on that unit they are the dark ones.
	"trailer_abs_lamp": "TRLR ABS",
}
const LAMP_COLOR := {
	"handbrake": Color(0.95, 0.35, 0.30), "turnL": Color(0.35, 0.85, 0.45),
	"turnR": Color(0.35, 0.85, 0.45), "horn": Color(0.45, 0.72, 1.0),
	"checkEngine": Color(1.0, 0.70, 0.15), "battery": Color(0.95, 0.35, 0.30),
	"brakeLamp": Color(0.95, 0.35, 0.30),
	"pto": Color(0.35, 0.85, 0.45), "pto_state": Color(0.35, 0.85, 0.45),
	"implement_connected": Color(0.35, 0.85, 0.45),
	"diff_lock": Color(1.0, 0.70, 0.15), "diff_lock_state": Color(1.0, 0.70, 0.15),
	"fwd_drive": Color(0.45, 0.72, 1.0), "fwd_drive_state": Color(0.45, 0.72, 1.0),
	"arm": Color(0.35, 0.85, 0.45), "armed": Color(0.35, 0.85, 0.45),
	"pantograph": Color(0.45, 0.72, 1.0), "pantograph_state": Color(0.45, 0.72, 1.0),
	"doors": Color(1.0, 0.70, 0.15), "doors_state": Color(1.0, 0.70, 0.15),
	"red_stop": Color(0.95, 0.35, 0.30), "amber_warn": Color(1.0, 0.70, 0.15),
	"protect_lamp": Color(1.0, 0.70, 0.15),
	"body_inhibit": Color(1.0, 0.70, 0.15), "body_bus": Color(0.45, 0.72, 1.0),
	"trailer_connected": Color(0.35, 0.85, 0.45), "trailer_abs": Color(1.0, 0.70, 0.15),
	"trailer_ebs_fault": Color(0.95, 0.35, 0.30),
	"trailer_abs_lamp": Color(1.0, 0.70, 0.15),
}
## Cosmetic short captions for the generated "out" bars (like LAMP_TEXT for lamps).
const BAR_LABEL := {
	"hitch_pos_actual": "HITCH", "pto_rpm": "PTO", "engine_load": "LOAD",
	"wheel_speed": "WHEEL", "ground_speed": "GROUND", "wheel_slip": "SLIP",
	"draft_force": "DRAFT",
	"air_primary": "AIR1", "air_secondary": "AIR2", "retarder_state": "RET",
	"axle_load": "AXLE", "body_pos": "ARM", "hopper_load": "HOPPER",
	"trailer_axle_load": "TRLR", "trailer_brake_demand": "TBRK",
	"altitude": "ALT", "vspeed": "V/S", "flaps_actual": "FLAPS", "rotor_rpm": "ROTOR",
	"catenary_volts": "LINE", "motor_current": "AMPS", "brake_pipe": "PIPE",
	"grade": "GRADE", "coupler_force": "COUPL",
}
## Cosmetic short captions for the generated enum "out" chips (like BAR_LABEL for bars).
const OUT_CHIP_TEXT := {"implement_type": "TOOL", "body_state": "BODY"}
## Unlit tell-tale colour. The LIT colours above are signal data; this is the "off" end of the
## same scale, so it stays here rather than in the theme.
const LAMP_OFF := Color(0.28, 0.30, 0.34)

var _level: Node = null
var _gear_def: RefCounted = null  ## contract "gear" out SignalDef, for gear-byte -> "D3"/"N"/"R"
var _speedo: Gauge
var _tach: Gauge
var _bars := {}      ## signal name -> DashBar
var _lamps := {}     ## signal name -> Label (input bool tell-tales)
var _out_lamps := {} ## signal name -> Label (bool "out" ISOBUS tell-tales, driven from telemetry)
var _chips := {}     ## signal name -> [Label, SignalDef] (enum "in" requests)
var _out_chips := {} ## signal name -> [Label, SignalDef] (flavored enum "out" readouts)
var _readout: Label = null
var _reverser: Label = null  ## reverser (N/D/R) readout for a gear-out vehicle with no tacho (train)

var _setting := Density.AUTO   ## what the player asked for (AUTO = let the rules decide)
var _density := Density.FULL   ## what that resolves to right now
var _vehicle_type := ""        ## the family the current cluster was built for
var _built := false            ## bind() has run at least once — nothing to rebuild before it
var _shown := false            ## the shell's HUD visibility, ANDed with the density
## Bridge freshness as the density last saw it, and when it changed (see BRIDGE_DWELL_S).
var _bridge_seen := false
var _bridge_changed_ms := 0


## Attach to a running Level and build the cluster for its active vehicle type.
## Called by the shell once the level has spawned its vehicle.
func bind(level: Node) -> void:
	_level = level
	# Prefer the vehicle actually spawned (a garage swap changes it); fall back to the
	# level's default before the first spawn.
	var vtype := GameState.current_vehicle
	if vtype == "" and level != null and level.get("info") != null:
		# default_vehicle is a VARIANT ("bullet"); the contract keys signals by FAMILY ("train").
		vtype = VehicleCatalog.family_of(level.info.default_vehicle)
	_built = true
	_bridge_seen = Bridge.is_active()
	_density = _resolve()
	_build(vtype)


# --- density -----------------------------------------------------------------

## Setting -> the key it persists as. ShellPrefs stores the STRING (a `user://` cfg is a file a
## human may open and an enum ordinal there would be meaningless), and this is the one mapping.
static func key_of(setting: int) -> String:
	return String(DENSITY_KEYS.get(setting, DENSITY_KEYS[Density.AUTO]))


## The inverse; an unknown key (an older or hand-edited cfg) falls back to AUTO.
static func setting_from_key(key: String) -> int:
	for setting: int in DENSITY_KEYS:
		if DENSITY_KEYS[setting] == key:
			return setting
	return Density.AUTO


## Next setting in the cycle, for the SETTINGS page's one button.
static func next_setting(setting: int) -> int:
	var order: Array = DENSITY_KEYS.keys()
	return int(order[(maxi(order.find(setting), 0) + 1) % order.size()])


## What the player picked, AUTO included. The pause menu's SETTINGS page shows this.
func density_setting() -> int:
	return _setting


## What is actually on screen (never AUTO).
func density() -> int:
	return _density


## Set the SETTING (from the pause menu / the saved prefs) and rebuild if the result differs.
func set_density_setting(setting: int) -> void:
	_setting = setting if setting in DENSITY_KEYS else Density.AUTO
	if _setting == Density.AUTO:
		# Nothing watched the bridge while an explicit pick was in force, so re-read it here
		# rather than let AUTO spend its dwell resolving from a stale answer.
		_bridge_seen = Bridge.is_active()
		_bridge_changed_ms = 0
	_apply_density()


## The shell's HUD visibility. Kept separate from the density because both can hide the
## cluster and neither may clobber the other: nothing is on screen without a level, and
## nothing is on screen at density OFF.
func set_shown(shown: bool) -> void:
	_shown = shown
	_apply_visible()


## Resolve the setting against the world. Only AUTO consults anything; an explicit pick is
## honoured as given, OFF included.
func _resolve() -> int:
	if _setting != Density.AUTO:
		return _setting
	# Phone-sized: the full cluster is most of a phone screen. Bridge live: sloppyCAN is
	# already showing you these numbers next door. AUTO never resolves to OFF — a dashboard
	# that vanished on its own would read as a bug.
	if UiScale.logical_short_edge(get_window()) <= COMPACT_SHORT_EDGE:
		return Density.COMPACT
	return Density.COMPACT if _bridge_seen else Density.FULL


## Re-resolve and rebuild only if the answer changed. Every input to _resolve() routes here.
func _apply_density() -> void:
	var next := _resolve()
	if next == _density and _built:
		return
	_density = next
	if _built:
		_build(_vehicle_type)
	_apply_visible()


func _apply_visible() -> void:
	visible = _shown and _density != Density.OFF


## A window resize rebuilds the theme (UiScale), which changes every metric below AND can move
## the screen across the phone-sized threshold — so the cluster is rebuilt from here rather
## than left at sizes computed for the old scale.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _built:
		_density = _resolve()
		_build(_vehicle_type)
		_apply_visible()


func _build(vehicle_type: String) -> void:
	_vehicle_type = vehicle_type
	for c in get_children():
		c.queue_free()
	_bars.clear()
	_lamps.clear()
	_out_lamps.clear()
	_chips.clear()
	_out_chips.clear()

	# The Dashboard control stays full-rect (set in boot.tscn). Pin the cluster panel
	# across the bottom edge and grow it UPWARD to fit its content: with the default
	# grow direction (down) the panel would slide off the bottom of the screen once its
	# children give it a real height, since its anchors/offsets are set before they exist.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	sb.content_margin_left = UiTheme.px(self, PANEL_PAD_X)
	sb.content_margin_right = UiTheme.px(self, PANEL_PAD_X)
	sb.content_margin_top = UiTheme.px(self, PANEL_PAD_Y)
	sb.content_margin_bottom = UiTheme.px(self, PANEL_PAD_Y)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(UiTheme.px(self, SECTION_GAP)))
	panel.add_child(col)

	if Contract.data == null or not Contract.data.is_valid():
		var err := Label.new()
		err.text = "dashboard: contract unavailable"
		col.add_child(err)
		return
	_gear_def = Contract.data.get_signal_def("gear", "out")

	col.add_child(_build_telltale_row(vehicle_type))

	var cluster := HBoxContainer.new()
	cluster.alignment = BoxContainer.ALIGNMENT_CENTER
	cluster.add_theme_constant_override("separation", int(UiTheme.px(self, CLUSTER_GAP)))
	col.add_child(cluster)

	# A gauge is only built when the vehicle declares its signal (contract-driven like
	# the bars/lamps): the boat has no 'rpm'/'gear', so its cluster is speedo-only —
	# the gear text lives in the tacho gap and goes with it.
	var out_names: Array = Contract.data.signals_for_vehicle(vehicle_type, "out") \
			.map(func(s: RefCounted) -> String: return s.name)

	_speedo = null
	if out_names.has("kmh"):
		_speedo = _make_gauge("kmh", "SPEED", 8)
		cluster.add_child(_speedo)

	# Reverser readout: the train is the only family that declares 'gear' out without 'rpm',
	# so the gear label the tacho gap would normally carry has nowhere to go. Give it a bespoke
	# centre label (hand-picked like the two gauges), built only for that case. It survives
	# COMPACT because it stands in for a gauge, not for a bar.
	_reverser = null
	_readout = null
	var wants_reverser := out_names.has("gear") and not out_names.has("rpm")
	# The middle column carries the bars and the readout, which is what COMPACT drops — so on a
	# train it is built for the reverser alone, and on everything else in COMPACT not at all
	# (an empty 280 px column between the two gauges is just a hole).
	if _density == Density.FULL or wants_reverser:
		var mid := VBoxContainer.new()
		mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mid.add_theme_constant_override("separation", int(UiTheme.px(self, MID_GAP)))
		cluster.add_child(mid)
		if wants_reverser:
			_reverser = Label.new()
			_reverser.theme_type_variation = &"Title"
			_reverser.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(_reverser)
		if _density == Density.FULL:
			mid.custom_minimum_size = Vector2(UiTheme.px(self, MID_W), 0)
			_build_bars(vehicle_type, mid)
			_readout = Label.new()
			_readout.theme_type_variation = &"Small"
			mid.add_child(_readout)

	_tach = null
	if out_names.has("rpm"):
		_tach = _make_gauge("rpm", "RPM", 8)
		cluster.add_child(_tach)


## Build the tell-tale row: state chips for the enum inputs, then a lamp per bool
## input — generated by walking the contract's "in" signals for this vehicle.
##
## It WRAPS (HFlowContainer, not HBox). The row is generated, so its width is however many
## lamps the contract declares for this machine — the truck with a trailer runs to fifteen —
## and a single line of them is wider than a phone. An HBox would push the ends off the screen
## and take the lamps that matter with them; the density modes cut height, and this is what
## keeps the row inside the width they cannot help with. On a desktop it is one line and looks
## exactly as it did.
func _build_telltale_row(vehicle_type: String) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	# FlowContainer separates on two axes and ignores plain "separation".
	var gap := int(UiTheme.px(self, LAMP_GAP))
	row.add_theme_constant_override("h_separation", gap)
	row.add_theme_constant_override("v_separation", int(UiTheme.px(self, SECTION_GAP)))

	for sig in Contract.data.signals_for_vehicle(vehicle_type, "in"):
		if sig.has_enum() and sig.name in ENUM_CHIPS:
			var chip := Label.new()
			chip.theme_type_variation = &"Small"
			row.add_child(chip)
			_chips[sig.name] = [chip, sig]

	for sig in Contract.data.signals_for_vehicle(vehicle_type, "in"):
		if sig.type != "bool":
			continue
		_lamps[sig.name] = _make_lamp(sig.name, row)

	# Flavored bool "out" signals become tell-tales too (isobus pto_state, dronecan armed,
	# train pantograph_state/doors_state), driven from telemetry rather than input —
	# generated from contract metadata.
	for sig in Contract.data.signals_for_vehicle(vehicle_type, "out"):
		if sig.type != "bool" or sig.flavor == "":
			continue
		_out_lamps[sig.name] = _make_lamp(sig.name, row)

	# Flavored enum "out" signals become state chips too — the readout counterpart of the
	# enum INPUT chips above (isobus implement_type). Generated the same way: the decoded
	# text comes from the contract's own enum table, so adding an ISO device class there
	# shows up here with no code change. 'gear' out is unflavored and stays on the tacho.
	for sig in Contract.data.signals_for_vehicle(vehicle_type, "out"):
		if not sig.has_enum() or sig.flavor == "":
			continue
		var chip := Label.new()
		chip.theme_type_variation = &"Small"
		row.add_child(chip)
		_out_chips[sig.name] = [chip, sig]
	return row


## One tell-tale Label (caption from LAMP_TEXT, unlit color), added to `into`.
func _make_lamp(sig_name: String, into: Node) -> Label:
	var lamp := Label.new()
	lamp.text = LAMP_TEXT.get(sig_name, sig_name.to_upper())
	lamp.theme_type_variation = &"Small"
	lamp.add_theme_color_override("font_color", LAMP_OFF)  # state, not styling
	into.add_child(lamp)
	return lamp


## Bars for every "out" signal (this vehicle) that has a range and is either warn'd
## (fuel/coolant, altitude/vspeed) or flavored (isobus implement panel, canaerospace
## flaps, dronecan rotor, train line/amps/pipe — driven from the contract 'flavor'
## metadata, not hardcoded names), except the two gauges.
func _build_bars(vehicle_type: String, into: Node) -> void:
	for sig in Contract.data.signals_for_vehicle(vehicle_type, "out"):
		if sig.name in GAUGE_SIGNALS or sig.range.size() != 2:
			continue
		if not sig.has_warn() and sig.flavor == "":
			continue
		var bar := DashBar.new()
		bar.custom_minimum_size = Vector2(0, UiTheme.px(self, BAR_H))
		bar.label = BAR_LABEL.get(sig.name, sig.name.to_upper())
		bar.units = _short_unit(sig.unit)
		bar.min_value = float(sig.range[0])
		bar.max_value = float(sig.range[1])
		bar.warn = sig.warn
		bar.warn_is_low = sig.warn_is_low()
		into.add_child(bar)
		_bars[sig.name] = bar


func _make_gauge(signal_name: String, caption: String, ticks: int) -> Gauge:
	var g := Gauge.new()
	# Smaller in COMPACT: the gauges are what COMPACT keeps, so they have to fit a phone.
	var edge := UiTheme.px(self, GAUGE_W if _density == Density.FULL else GAUGE_W_COMPACT)
	g.custom_minimum_size = Vector2(edge, edge)
	g.caption = caption
	g.major_ticks = ticks
	var sig := Contract.data.get_signal_def(signal_name, "out")
	if sig != null and sig.range.size() == 2:
		g.min_value = float(sig.range[0])
		g.max_value = float(sig.range[1])
	if sig != null and sig.has_warn():
		g.redline = sig.warn
	g.units = _short_unit(sig.unit) if sig != null else ""
	return g


func _short_unit(unit: String) -> String:
	# Percent/degree read better glued to the number; keep the rest spaced.
	match unit:
		"%": return "%"
		"degC": return "°C"
		_: return ""


## Watch bridge freshness for the AUTO density, with a dwell. Bridge.is_active() follows a
## 300 ms freshness window, so a peer publishing slowly toggles it — and rebuilding the cluster
## on every toggle would be visible thrash. The state has to HOLD for BRIDGE_DWELL_S before the
## density acts on it.
func _poll_bridge() -> void:
	if _setting != Density.AUTO:
		return  # an explicit pick does not consult the bridge, so there is nothing to watch
	var live := Bridge.is_active()
	if live == _bridge_seen:
		_bridge_changed_ms = 0
		return
	if _bridge_changed_ms == 0:
		_bridge_changed_ms = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _bridge_changed_ms < int(BRIDGE_DWELL_S * 1000.0):
		return
	_bridge_seen = live
	_bridge_changed_ms = 0
	_apply_density()


func _process(_dt: float) -> void:
	_poll_bridge()
	if not visible or _level == null:
		return
	var vehicle: Node = _level.get("vehicle")
	if vehicle == null:
		return
	var t: VehicleTelemetry = vehicle.get("telemetry")
	if t == null:
		return

	if _speedo != null:
		_speedo.value = t.kmh
	if _tach != null:
		_tach.value = t.rpm
		_tach.center_text = _gear_def.enum_label(t.gear_byte) if _gear_def != null else ""
	if _reverser != null:
		_reverser.text = "REVERSER  %s" % (_gear_def.enum_label(t.gear_byte) if _gear_def != null else "")

	for sig_name in _bars:
		# Bars are keyed by contract signal name; telemetry fields share those names
		# (fuel, coolant). Guard the lookup so warn'ing a signal whose telemetry field
		# is spelled differently (e.g. accLong -> acc_long) degrades to a static bar
		# rather than assigning null into a float.
		var v: Variant = t.get(sig_name)
		if typeof(v) != TYPE_NIL:
			_bars[sig_name].value = v

	# Flavored bool "out" tell-tales (pto_state, armed, pantograph_state/doors_state) are
	# telemetry-driven, unlike the input lamps in _update_telltales.
	for sig_name in _out_lamps:
		var on := bool(t.get(sig_name))
		# PRESENTATION ONLY, and the one place a lamp does not simply show its signal.
		# `body_inhibit` is true whenever the body network is down (RefuseBody.is_inhibited takes
		# `bus`, deliberately, so the interlock never claims an unpowered body may swing its arm) —
		# so INHIB would be lit for the whole of ordinary driving with the PTO out, and BODY BUS
		# beside it would already be saying it. Measured over a scripted refuse round: INHIB lit
		# with the bus DARK 44 % of ticks (carrying nothing BODY BUS did not), and lit with the bus
		# UP only 20 % — which is the case it exists for, "the body is powered and still refused".
		# A permanently-lit amber tell-tale reads as a fault, so it is suppressed while the bus is
		# dark: a body with no network cannot be refused a command. The SIGNAL is untouched — the
		# bridge still publishes body_inhibit verbatim — and the rule in RefuseBody stays as it is.
		if sig_name == "body_inhibit" and on and not bool(t.get("body_bus")):
			on = false
		var col: Color = LAMP_COLOR.get(sig_name, Color(1.0, 0.70, 0.15)) if on else LAMP_OFF
		_out_lamps[sig_name].add_theme_color_override("font_color", col)

	# Flavored enum "out" chips (implement_type) — telemetry-driven like the out lamps, and
	# guarded the same way the bars are in case a field is spelled differently.
	for sig_name in _out_chips:
		var raw: Variant = t.get(sig_name)
		if typeof(raw) == TYPE_NIL:
			continue
		var out_sig: RefCounted = _out_chips[sig_name][1]
		(_out_chips[sig_name][0] as Label).text = "%s:%s" % [
			OUT_CHIP_TEXT.get(sig_name, sig_name.to_upper()), out_sig.enum_label(int(raw))]

	_update_telltales()
	if _readout != null:
		_readout.text = "HDG %03d  ODO %.1f km  %.4f, %.4f" % [
			roundi(t.heading), t.odo, t.lat, t.lon]
		# The hour meter (tractor and truck — SPN 247 is shared) joins the odometer here
		# rather than becoming a bar: an hour meter is a running total with no meaningful
		# full-scale. Guarded like the bars, so every other vehicle's line is untouched.
		var hours: Variant = t.get("engine_hours")
		if typeof(hours) != TYPE_NIL:
			_readout.text += "  HRS %.1f" % hours


func _update_telltales() -> void:
	var vi := InputRouter.get_vehicle_input()
	# Mirror every lamp/warning bit the input carries. sloppyCAN is the sole
	# authority when the bridge is live; locally only handbrake/horn/brake_lamp are
	# driven and the turn/warning LEDs stay off — their correct default.
	var active := {
		"handbrake": vi.handbrake > 0.0,
		"horn": vi.horn,
		"turnL": vi.turn_left,
		"turnR": vi.turn_right,
		"brakeLamp": vi.brake_lamp,
		"checkEngine": vi.check_engine,
		"battery": vi.battery_warn,
		"arm": vi.arm,
		"pantograph": vi.pantograph,
		"doors": vi.doors,
		"diff_lock": vi.diff_lock,
		"fwd_drive": vi.fwd_drive,
		# The truck's DM1 lamps, mirrored verbatim with every other lamp bit above.
		"red_stop": vi.red_stop,
		"amber_warn": vi.amber_warn,
		"protect_lamp": vi.protect_lamp,
		# The trailer's own fault lamp off the ISO 11992 bus, mirrored the same way.
		"trailer_ebs_fault": vi.trailer_ebs_fault,
		# ...and the North American unit's single power-line bit, mirrored the same way again.
		"trailer_abs_lamp": vi.trailer_abs_lamp,
		# The PTO REQUEST, beside the pto_state lamp the telemetry drives: the pair is what
		# separates "commanded" from "engaged", which is the whole point of publishing both.
		"pto": vi.pto,
	}
	for sig_name in _lamps:
		var on: bool = active.get(sig_name, false)
		var col: Color = LAMP_COLOR.get(sig_name, Color(1.0, 0.70, 0.15)) if on else LAMP_OFF
		_lamps[sig_name].add_theme_color_override("font_color", col)

	var enums := {
		"key": vi.key, "lights": vi.lights, "pto_mode": vi.pto_mode,
		# The refuse body COMMAND, beside the body_state chip the telemetry drives — the same
		# request/state pairing the pto and pto_state lamps use, so "commanded but inhibited" reads.
		"body_cmd": vi.body_cmd,
	}
	for sig_name in _chips:
		var label: Label = _chips[sig_name][0]
		var sig: RefCounted = _chips[sig_name][1]
		var raw: int = enums.get(sig_name, 0)
		label.text = "%s:%s" % [sig_name.to_upper(), sig.enum_label(raw)]
