class_name Dashboard
extends Control
## Instrument cluster. Tell-tale row and bars are GENERATED from contract signal metadata
## (name, range, warn, flavor, instance count) — a bool "in" or warn'd/flavored "out" signal
## appears here with no code change. The two radial gauges, the attitude indicator and the
## node health strip are HAND-BUILT, reading only scale/redline/warn from the contract.
## Density (AUTO/FULL/COMPACT/OFF) drops whole sections only, never individual signals:
## COMPACT keeps the tell-tale row and gauges; AUTO picks COMPACT on a phone screen or while
## the bridge is live, FULL otherwise, never OFF on its own. Plain text + color only.

## Signals rendered as bespoke radial gauges (never as generated bars).
const GAUGE_SIGNALS: PackedStringArray = ["kmh", "rpm"]
## Declaring both builds the hand-built attitude indicator (boat/plane/drone).
const HORIZON_SIGNALS: PackedStringArray = ["pitch", "roll"]
## Instanced signal the node strip is generated from (drone's DroneCAN roster). Count decides
## how many squares there are.
const NODE_HEALTH_SIGNAL := "node_health"
## Fields the readout line reads directly rather than through a generated widget: the
## body-network interlock INHIB is suppressed against, and the drone's three range-less readings.
const BODY_BUS_FIELD := &"body_bus"
const BARO_FIELD := &"baro_alt"
const GIMBAL_PITCH_FIELD := &"gimbal_pitch_actual"
const GIMBAL_YAW_FIELD := &"gimbal_yaw_actual"
const PAYLOAD_FIELD := &"payload_weight"

## What is on screen. AUTO is a setting value only — `density()` never returns it.
enum Density {AUTO, FULL, COMPACT, OFF}
## Persisted setting ids (cfg file a human may open) and the SETTINGS page cycle order.
const DENSITY_KEYS := {
	Density.AUTO: "auto", Density.FULL: "full",
	Density.COMPACT: "compact", Density.OFF: "off",
}
## Window short edge (logical px) at or below which AUTO picks COMPACT.
const COMPACT_SHORT_EDGE := 520.0
## How long a change in Bridge.is_active() must hold before AUTO rebuilds (freshness flips on
## a 300 ms window, Bridge.FRESHNESS_MS).
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
## Max bar rows (bars + group captions) per column before spilling into a second column. The
## cluster is full-width (280 px middle between two 150 px gauges), so a third column pushes
## the gauges off a 1280-wide window — that bound sets this number.
##
## Packing is greedy first-fit over unsplittable groups, so column count is not
## `ceil(rows / cap)`. The drone's 27 rows are three unsplittable 5-row ESC groups that land in
## three columns at any cap below 14; 14 is the smallest value holding the two-column bound.
##
## Re-derive rather than assume: must also stay at or above the tallest scalar cluster (the
## truck's, currently 12) or a family with no instanced signal splits into two columns for no
## reason. `test_dashboard` pins both ends.
##
## The drone is at 28 of the 28 rows two columns hold (`home_dist` used the last row). Give a
## drone signal a range only if it has a meaningful full scale and you've re-derived this
## budget — `esc_fault`, `node_health`, `node_online` stay range-less for that reason.
##
## Cost is panel height: 14 rows is ~356 px against 11 rows' ~278; the panel has no other bound.
const BAR_ROWS_MAX := 14
## Enum "in" signals shown as small state chips rather than a lamp or a bar (gear rides the tacho
## instead).
##
## Known cosmetic wart: `lights` (OFF/CLEARANCE/LOW/HIGH, shared by all eight vehicles) drives an
## aircraft ladder on the plane (VehicleSpec.LampStyle.AIRCRAFT) and has no headlamp meaning on
## the drone (whose real indication is the `led` in-signal, a packed colour read off the airframe
## arm tips instead). The level numbers are the protocol and are right; only the display name is
## vehicle-wrong. Not fixed before the sloppyCAN frame layout is finalized.
const ENUM_CHIPS: PackedStringArray = ["key", "lights", "pto_mode", "body_cmd"]

## Cosmetic tell-tale presentation (UI styling, not signal data): short caption + lit
## color per known lamp. Unknown lamps fall back to the upper-cased signal name / amber.
const LAMP_TEXT := {
	"handbrake": "BRAKE", "turnL": "<L", "turnR": "R>", "horn": "HORN",
	"checkEngine": "CHECK", "battery": "BATT", "brakeLamp": "STOP",
	"pto": "PTO REQ", "pto_state": "PTO", "arm": "ARM", "armed": "ARMED",
	# DroneCAN buzzer (BeepCommand). The 'led' colour signal is a u32, not a bool, so it
	# generates no lamp and is read off the airframe's arm tips instead.
	"beep": "BEEP",
	# Cargo hook: REQUEST beside STATE, captioned REQ like the tractor driveline pair below.
	"hardpoint_cmd": "HOOK REQ", "hardpoint_state": "HOOK",
	"implement_connected": "IMPL",
	# tractor driveline: request lamps beside state lamps, captioned REQ.
	"diff_lock": "DIFF REQ", "diff_lock_state": "DIFF",
	"fwd_drive": "MFWD REQ", "fwd_drive_state": "MFWD",
	# train: "in" request lamps sit next to "out" state lamps, captioned REQ for the small size.
	"pantograph": "PAN REQ", "pantograph_state": "PANTO",
	"doors": "DOOR REQ", "doors_state": "DOORS",
	# truck J1939-73 DM1 lamp status byte; checkEngine above is DM1's MIL, these are the other three.
	"red_stop": "RSL", "amber_warn": "AWL", "protect_lamp": "PROT",
	# CiA 422 body network via the CiA 413 gateway. INHIB is the chassis-side interlock, BODY BUS
	# is whether the body network is powered.
	"body_inhibit": "INHIB", "body_bus": "BODY BUS",
	# ISO 11992 trailer bus. TRLR is the coupling claim (dark with a trailer attached is valid,
	# see contract desc); ABS/EBS come off the trailer.
	"trailer_connected": "TRLR", "trailer_abs": "ABS", "trailer_ebs_fault": "EBS",
	# SAE J2497 power line, the North American conventional's whole trailer protocol, beside
	# rather than replacing the ISO 11992 lamps (dark on that unit).
	"trailer_abs_lamp": "TRLR ABS",
	# Aircraft flashing lamps; they flash because the bit flashes, no timer here.
	"beacon": "BCN", "strobe": "STRB",
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
	"beep": Color(0.45, 0.72, 1.0),
	"hardpoint_cmd": Color(1.0, 0.70, 0.15), "hardpoint_state": Color(0.35, 0.85, 0.45),
	"pantograph": Color(0.45, 0.72, 1.0), "pantograph_state": Color(0.45, 0.72, 1.0),
	"doors": Color(1.0, 0.70, 0.15), "doors_state": Color(1.0, 0.70, 0.15),
	"red_stop": Color(0.95, 0.35, 0.30), "amber_warn": Color(1.0, 0.70, 0.15),
	"protect_lamp": Color(1.0, 0.70, 0.15),
	"body_inhibit": Color(1.0, 0.70, 0.15), "body_bus": Color(0.45, 0.72, 1.0),
	"trailer_connected": Color(0.35, 0.85, 0.45), "trailer_abs": Color(1.0, 0.70, 0.15),
	"trailer_ebs_fault": Color(0.95, 0.35, 0.30),
	"trailer_abs_lamp": Color(1.0, 0.70, 0.15),
	"beacon": Color(0.95, 0.35, 0.30), "strobe": Color(1.0, 1.0, 1.0),
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
	"esc_rpm": "ESC RPM", "esc_current": "ESC AMP", "esc_temp": "ESC TEMP",
	# 'battery' is VOLTS not BATT: BATT is already the 'in' warning lamp in the tell-tale row.
	"battery": "VOLTS", "pack_current": "PACK A", "soc": "SOC", "pack_temp": "PACK T",
	"agl": "AGL", "sats": "SATS", "hdop": "HDOP", "home_dist": "HOME",
	"catenary_volts": "LINE", "motor_current": "AMPS", "brake_pipe": "PIPE",
	"grade": "GRADE", "coupler_force": "COUPL",
}
## Cosmetic short captions for the generated enum "out" chips (like BAR_LABEL for bars). ARMING
## and FS avoid colliding with the ARM/ARMED tell-tale lamps above.
const OUT_CHIP_TEXT := {"implement_type": "TOOL", "body_state": "BODY", "fix_type": "FIX",
		"mode_actual": "MODE", "arming_state": "ARMING", "failsafe": "FS"}
## uavcan.protocol.NodeStatus health -> square colour, indexed by the health value (0 OK,
## 1 WARNING, 2 ERROR, 3 CRITICAL, DroneBus's wire enum). Out-of-range falls back to CRITICAL,
## never to "looks fine".
const NODE_HEALTH_COLOR: Array[Color] = [
	Color(0.30, 0.72, 0.38), Color(1.0, 0.70, 0.15),
	Color(0.95, 0.50, 0.15), Color(0.90, 0.20, 0.16),
]
const NODE_SQUARE := 12.0  ## node strip square, logical px
const NODE_GAP := 8.0      ## between one node's square+label column and the next

## Unlit tell-tale colour; the "off" end of the LIT colours above, which are signal data.
const LAMP_OFF := Color(0.28, 0.30, 0.34)

var _gear_def: RefCounted = null  ## contract "gear" out SignalDef, for gear-byte -> "D3"/"N"/"R"
var _speedo: Gauge
var _tach: Gauge
var _horizon: AttitudeIndicator = null  ## artificial horizon (flight families) — see HORIZON_SIGNALS
var _node_squares: Array[ColorRect] = []  ## one per bus node, roster order; empty with no node_health
## signal name -> Array[DashBar], always an array (a scalar has one entry) so the update loop
## needs no count branch: DashBar.value is typed float and would throw on an instanced Array.
var _bars := {}
var _lamps := {}     ## signal name -> Label (input bool tell-tales)
var _out_lamps := {} ## signal name -> Label (bool "out" ISOBUS tell-tales, driven from telemetry)
var _chips := {}     ## signal name -> [Label, SignalDef] (enum "in" requests)
var _out_chips := {} ## signal name -> [Label, SignalDef] (flavored enum "out" readouts)
var _readout: Label = null
var _has_speed_limit := false  ## this family declares the 'speed_limit' out signal (SPN 74)
var _has_engine_hours := false ## this family declares the 'engine_hours' out signal (SPN 247)

## Bound vehicle's telemetry, resolved at bind rather than walked every frame; the shell rebinds
## on every Level.vehicle_changed. Null between levels.
var _telem: VehicleTelemetry = null
## Widget -> telemetry field, resolved once per build against the telemetry's real property list
## and held as StringName (avoids interning a String key every frame per bar). A contract signal
## whose telemetry field is spelled differently is dropped here with one warning instead of
## failing silently at 60 Hz.
var _bar_fields: Array[Array] = []       ## [[StringName, Array[DashBar]], ...]
var _out_lamp_fields: Array[Array] = []  ## [[StringName, Label, lit Color], ...]
var _out_chip_fields: Array[Array] = []  ## [[StringName, Label, SignalDef, caption], ...]
var _node_health_field := &""  ## resolved 'node_health', or &"" where this cluster has no strip
var _has_baro := false         ## bound telemetry carries 'baro_alt' (drone) — readout line
var _has_gimbal := false       ## ...'gimbal_pitch_actual' + 'gimbal_yaw_actual'
var _has_payload := false      ## ...'payload_weight'
var _field_warned := {}        ## field names already reported unresolved, so the warning is once
var _reverser: Label = null  ## reverser (N/D/R) readout for a gear-out vehicle with no tacho (train)

var _setting: int = Density.AUTO   ## what the player asked for (AUTO = let the rules decide)
var _density: int = Density.FULL   ## what that resolves to right now
var _vehicle_type := ""        ## the family the current cluster was built for
var _built := false            ## bind() has run at least once
var _shown := false            ## the shell's HUD visibility, ANDed with the density
var _bridge_seen := false      ## bridge freshness as the density last saw it (see BRIDGE_DWELL_S)
var _bridge_changed_ms := 0


## Attach to a running Level and build the cluster for its active vehicle type.
## Called by the shell once the level has spawned its vehicle.
func bind(level: Node) -> void:
	# Prefer the vehicle actually spawned (a garage swap changes it); fall back to the
	# level's default before the first spawn.
	var vtype := GameState.current_vehicle
	if vtype == "" and level != null and level.get("info") != null:
		# default_vehicle is a VARIANT ("bullet"); the contract keys signals by FAMILY ("train").
		vtype = VehicleCatalog.family_of(level.info.default_vehicle)
	_built = true
	_bridge_seen = Bridge.is_active()
	# Resolve telemetry before building: _build ends by binding every widget to a field on it.
	_telem = null
	if level != null:
		var vehicle: Node = level.get("vehicle")
		if vehicle != null:
			_telem = vehicle.get("telemetry")
	_density = _resolve()
	_build(vtype)


# --- density -----------------------------------------------------------------

## Setting -> the key it persists as (ShellPrefs stores a string; a cfg file may be hand-edited).
static func key_of(setting: int) -> String:
	return String(DENSITY_KEYS.get(setting, DENSITY_KEYS[Density.AUTO]))


## Inverse; an unknown key (older or hand-edited cfg) falls back to AUTO.
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


## Set the setting (from the pause menu / saved prefs) and rebuild if the result differs.
func set_density_setting(setting: int) -> void:
	_setting = setting if setting in DENSITY_KEYS else Density.AUTO
	if _setting == Density.AUTO:
		# Re-read the bridge rather than let AUTO resolve from a stale answer nothing watched.
		_bridge_seen = Bridge.is_active()
		_bridge_changed_ms = 0
	_apply_density()


## Shell's HUD visibility, kept separate from density: neither may clobber the other, since
## both can independently hide the cluster.
func set_shown(shown: bool) -> void:
	_shown = shown
	_apply_visible()


## Resolve the setting against the world; only AUTO consults anything.
func _resolve() -> int:
	if _setting != Density.AUTO:
		return _setting
	# AUTO never resolves to OFF — a dashboard that vanished on its own reads as a bug.
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


## A window resize rebuilds the theme (UiScale), which changes every metric below and can move
## the screen across the phone-sized threshold, so the cluster is rebuilt here too.
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
	_node_squares.clear()
	_lamps.clear()
	_out_lamps.clear()
	_chips.clear()
	_out_chips.clear()

	# Pin the cluster panel across the bottom edge and grow it upward: with the default grow
	# direction (down) it would slide off-screen once its children give it a real height.
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
	# Rides above the cluster with the tell-tales and survives COMPACT: node_health renders
	# nowhere else, so dropping it would lose a signal instead of a whole section.
	var strip := _build_node_strip(vehicle_type)
	if strip != null:
		col.add_child(strip)

	var cluster := HBoxContainer.new()
	cluster.alignment = BoxContainer.ALIGNMENT_CENTER
	cluster.add_theme_constant_override("separation", int(UiTheme.px(self, CLUSTER_GAP)))
	col.add_child(cluster)

	# A gauge is only built when the vehicle declares its signal: the boat has no 'rpm'/'gear',
	# so its cluster is speedo-only.
	var out_names: Array = Contract.data.signals_for_vehicle(vehicle_type, "out") \
			.map(func(s: RefCounted) -> String: return s.name)

	_speedo = null
	if out_names.has("kmh"):
		_speedo = _make_gauge("kmh", "SPEED", 8)
		cluster.add_child(_speedo)

	# Reverser readout: the train declares 'gear' out without 'rpm', so the gear label the tacho
	# gap would carry has nowhere to go. Bespoke centre label, survives COMPACT like a gauge.
	_reverser = null
	_readout = null
	_has_speed_limit = out_names.has("speed_limit")
	_has_engine_hours = out_names.has("engine_hours")
	var wants_reverser := out_names.has("gear") and not out_names.has("rpm")
	# The middle column (bars + readout) is what COMPACT drops, so on a train it holds only the
	# reverser and on everything else in COMPACT it isn't built at all.
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

	# Artificial horizon: exists only where the vehicle declares both 'pitch' and 'roll', lands
	# in the tacho slot (those families declare no 'rpm'), survives COMPACT like a gauge.
	_horizon = null
	if declares_horizon(out_names):
		_horizon = _make_horizon()
		cluster.add_child(_horizon)

	# Every widget above is new, so field bindings are stale; a density change or theme rebuild
	# comes back through here too.
	_resolve_fields()


## Build the tell-tale row: state chips for the enum inputs, then a lamp per bool input —
## generated by walking the contract's "in" signals for this vehicle.
##
## Wraps (HFlowContainer, not HBox): the truck with a trailer runs to fifteen lamps, wider than
## a phone. An HBox would push the ends off screen; a wrap keeps the row inside the width the
## density modes cannot help with.
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
	# train pantograph_state/doors_state), driven from telemetry rather than input.
	for sig in Contract.data.signals_for_vehicle(vehicle_type, "out"):
		if sig.type != "bool" or sig.flavor == "":
			continue
		_out_lamps[sig.name] = _make_lamp(sig.name, row)

	# Flavored enum "out" signals become state chips, the readout counterpart of the enum
	# input chips above. 'gear' out is unflavored and stays on the tacho.
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


## Bars for every "out" signal that has a range and is either warn'd or flavored (contract
## metadata, not hardcoded names), except the two gauges.
##
## An instanced signal (contract 'count' > 1, the drone's four ESCs) becomes a group caption
## plus one bar per instance, labelled with its zero-based index — that index is the esc_index
## on the wire and the bit position in esc_fault, so it must match the bus's own numbering.
##
## Bars flow into columns of at most BAR_ROWS_MAX rows; a group is never split across a column
## break.
func _build_bars(vehicle_type: String, into: Node) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(UiTheme.px(self, CLUSTER_GAP)))
	into.add_child(cols)
	var col: VBoxContainer = null
	var col_rows := 0
	for sig in Contract.data.signals_for_vehicle(vehicle_type, "out"):
		if sig.name in GAUGE_SIGNALS or sig.range.size() != 2:
			continue
		if not sig.has_warn() and sig.flavor == "":
			continue
		var caption: String = BAR_LABEL.get(sig.name, sig.name.to_upper())
		# `col_rows > 0` guard: a group taller than the cap gets its own column rather than an
		# empty one first.
		var rows: int = sig.count + (1 if sig.is_instanced() else 0)
		if col == null or (col_rows > 0 and col_rows + rows > BAR_ROWS_MAX):
			col = _new_bar_column()
			cols.add_child(col)
			col_rows = 0
		col_rows += rows
		if sig.is_instanced():
			# Group heading: a DashBar caption truncates at its LABEL_W gutter, so "ESC RPM"
			# over four bars labelled 0..3 reads better than four truncated ones.
			var head := Label.new()
			head.theme_type_variation = &"MutedSmall"
			head.text = caption
			col.add_child(head)
		var group: Array[DashBar] = []
		for i in sig.count:
			var bar := DashBar.new()
			bar.custom_minimum_size = Vector2(0, UiTheme.px(self, BAR_H))
			bar.label = str(i) if sig.is_instanced() else caption
			bar.units = _short_unit(sig.unit)
			bar.min_value = float(sig.range[0])
			bar.max_value = float(sig.range[1])
			bar.warn = sig.warn
			bar.warn_is_low = sig.warn_is_low()
			col.add_child(bar)
			group.append(bar)
		_bars[sig.name] = group


## One bar column, MID_W wide with MID_GAP stacking. Top-aligned: a short second column
## centred against a tall first one reads as misalignment.
func _new_bar_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(UiTheme.px(self, MID_W), 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", int(UiTheme.px(self, MID_GAP)))
	return col


## One small square per node on the DroneCAN roster, coloured from the instanced `node_health`
## signal. Built only where the vehicle declares that signal (contract gate, not a family check).
## Count comes from the contract; names come from DroneBus, the roster's one declaration — a
## square past the roster's end is captioned with its index rather than left blank.
## Returns null when there is nothing to build, so the caller adds no empty row.
func _build_node_strip(vehicle_type: String) -> Control:
	var sig := Contract.data.get_signal_def(NODE_HEALTH_SIGNAL, "out")
	if sig == null or not (vehicle_type in sig.vehicles):
		return null
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", int(UiTheme.px(self, NODE_GAP)))
	row.add_theme_constant_override("v_separation", int(UiTheme.px(self, SECTION_GAP)))
	var head := Label.new()
	head.theme_type_variation = &"MutedSmall"
	head.text = "NODES"
	row.add_child(head)
	var edge := UiTheme.px(self, NODE_SQUARE)
	for i in sig.count:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var square := ColorRect.new()
		square.custom_minimum_size = Vector2(edge, edge)
		square.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		square.color = LAMP_OFF
		cell.add_child(square)
		var node_label := Label.new()
		node_label.theme_type_variation = &"MutedSmall"
		var label_text := DroneBus.name_of(i)
		node_label.text = label_text if label_text != "" else str(i)
		node_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(node_label)
		row.add_child(cell)
		_node_squares.append(square)
	return row


## Does this set of "out" signal names carry the whole attitude pair? Static so the test pins
## the same predicate the cluster builds from.
static func declares_horizon(out_names: Array) -> bool:
	for n in HORIZON_SIGNALS:
		if not out_names.has(n):
			return false
	return true


## Hand-built like the two gauges: only the two warn thresholds are read from the contract.
func _make_horizon() -> AttitudeIndicator:
	var h := AttitudeIndicator.new()
	var edge := UiTheme.px(self, GAUGE_W if _density == Density.FULL else GAUGE_W_COMPACT)
	h.custom_minimum_size = Vector2(edge, edge)
	h.caption = "ATTITUDE"
	var pitch_def := Contract.data.get_signal_def("pitch", "out")
	if pitch_def != null and pitch_def.has_warn():
		h.pitch_warn = pitch_def.warn
	var roll_def := Contract.data.get_signal_def("roll", "out")
	if roll_def != null and roll_def.has_warn():
		h.roll_warn = roll_def.warn
	return h


func _make_gauge(signal_name: String, caption: String, ticks: int) -> Gauge:
	var g := Gauge.new()
	var edge := UiTheme.px(self, GAUGE_W if _density == Density.FULL else GAUGE_W_COMPACT)  # smaller in COMPACT to fit a phone
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


## Watch bridge freshness for the AUTO density, with a dwell: Bridge.is_active() toggles on a
## 300 ms freshness window, and rebuilding on every toggle would be visible thrash. State must
## hold for BRIDGE_DWELL_S before the density acts on it.
func _poll_bridge() -> void:
	if _setting != Density.AUTO:
		return  # an explicit pick does not consult the bridge
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


## Bind the built widgets to the telemetry fields they read, once per build.
##
## A widget knows only its contract signal name; the telemetry field may be spelled differently.
## `t.get()` on a missing name returns nil, which a per-frame lookup could only read as "leave
## the widget alone" — a bar frozen at zero looks exactly like a signal that never moves.
## Resolving here against the real property list turns that into one warning at bind.
func _resolve_fields() -> void:
	_bar_fields.clear()
	_out_lamp_fields.clear()
	_out_chip_fields.clear()
	_node_health_field = &""
	_has_baro = false
	_has_gimbal = false
	_has_payload = false
	if _telem == null:
		return
	var fields := {}
	for prop in _telem.get_property_list():
		fields[StringName(prop["name"])] = true
	for sig_name: String in _bars:
		var field := _field(fields, sig_name)
		if field != &"":
			_bar_fields.append([field, _bars[sig_name]])
	for sig_name: String in _out_lamps:
		var field := _field(fields, sig_name)
		if field != &"":
			# Lit colour resolved here too, rather than out of a String-keyed table every frame.
			_out_lamp_fields.append([field, _out_lamps[sig_name],
					LAMP_COLOR.get(sig_name, Color(1.0, 0.70, 0.15))])
	for sig_name: String in _out_chips:
		var field := _field(fields, sig_name)
		if field != &"":
			_out_chip_fields.append([field, _out_chips[sig_name][0], _out_chips[sig_name][1],
					String(OUT_CHIP_TEXT.get(sig_name, sig_name.to_upper()))])
	if not _node_squares.is_empty():
		_node_health_field = _field(fields, NODE_HEALTH_SIGNAL)
	# The readout's three range-less drone readings live on DroneTelemetry alone; their presence
	# is the gate, unlike the contract-gated HRS/LIM below.
	_has_baro = fields.has(BARO_FIELD)
	_has_gimbal = fields.has(GIMBAL_PITCH_FIELD) and fields.has(GIMBAL_YAW_FIELD)
	_has_payload = fields.has(PAYLOAD_FIELD)


## `name` as a telemetry field, or &"" (warned once) if the bound telemetry does not carry it.
func _field(fields: Dictionary, sig_name: String) -> StringName:
	var field := StringName(sig_name)
	if fields.has(field):
		return field
	if not _field_warned.has(field):
		_field_warned[field] = true
		push_warning("Dashboard: contract signal '%s' has no telemetry field on %s" % [
			sig_name, _telem.get_script().resource_path.get_file()])
	return &""


func _process(_dt: float) -> void:
	_poll_bridge()
	if not visible or _telem == null:
		return
	var t := _telem

	if _speedo != null:
		_speedo.value = t.kmh
	if _tach != null:
		_tach.value = t.rpm
		_tach.center_text = _gear_def.enum_label(t.gear_byte) if _gear_def != null else ""
	if _reverser != null:
		_reverser.text = "REVERSER  %s" % (_gear_def.enum_label(t.gear_byte) if _gear_def != null else "")
	if _horizon != null:
		# pitch/roll are shared fields on every vehicle; the instrument itself is gated by
		# declares_horizon above, so no duck-typed lookup is needed here.
		_horizon.pitch = t.pitch
		_horizon.roll = t.roll

	# Length-guarded like the instanced bars below; the bridge is where a wrong shape is
	# reported loudly, not here.
	if _node_health_field != &"":
		var health: Variant = t.get(_node_health_field)
		if typeof(health) == TYPE_ARRAY:
			var values: Array = health
			for i in mini(_node_squares.size(), values.size()):
				var level := int(values[i])
				if level < 0 or level >= NODE_HEALTH_COLOR.size():
					level = NODE_HEALTH_COLOR.size() - 1
				_node_squares[i].color = NODE_HEALTH_COLOR[level]

	# Resolved pairs, not the name-keyed dict: _resolve_fields already dropped and reported
	# fields that don't exist, so there's no nil case left to guard.
	for pair in _bar_fields:
		var v: Variant = t.get(pair[0])
		var group: Array[DashBar] = pair[1]
		if group.size() == 1:
			group[0].value = v
			continue
		# Instanced signal: element i drives bar i. A short/long array degrades to static bars;
		# the bridge is where a wrong shape is reported loudly, not here.
		if typeof(v) != TYPE_ARRAY:
			continue
		var values: Array = v
		for i in mini(group.size(), values.size()):
			group[i].value = values[i]

	# Flavored bool "out" tell-tales (pto_state, armed, pantograph_state/doors_state) are
	# telemetry-driven, unlike the input lamps in _update_telltales.
	for pair in _out_lamp_fields:
		var field: StringName = pair[0]
		var on := bool(t.get(field))
		# Presentation only: `body_inhibit` reflects RefuseBody's chassis-side interlock, true
		# whenever the body network is down, so INHIB would light for ordinary driving with the
		# PTO out (BODY BUS already says that). Suppressed while the bus is dark — a body with no
		# network cannot be refused a command. The bridge still publishes body_inhibit verbatim.
		if field == &"body_inhibit" and on and not bool(t.get(BODY_BUS_FIELD)):
			on = false
		var col: Color = pair[2] if on else LAMP_OFF
		(pair[1] as Label).add_theme_color_override("font_color", col)

	# Flavored enum "out" chips (implement_type), telemetry-driven like the out lamps.
	for chip in _out_chip_fields:
		var out_sig: RefCounted = chip[2]
		(chip[1] as Label).text = "%s:%s" % [
			chip[3], out_sig.enum_label(int(t.get(chip[0])))]

	_update_telltales()
	if _readout != null:
		_readout.text = "HDG %03d  ODO %.1f km  %.4f, %.4f" % [
			roundi(t.heading), t.odo, t.lat, t.lon]
		# Hour meter (tractor/truck, SPN 247) joins the odometer instead of becoming a bar: a
		# running total has no meaningful full scale. Contract-gated: engine_hours lives on the
		# base VehicleTelemetry, so a duck-type would put HRS on the boat and the drone too.
		if _has_engine_hours:
			_readout.text += "  HRS %.1f" % t.engine_hours
		# Road-speed governor (car/truck/tractor, J1939 SPN 74): a configured limit is constant
		# for the session, so a bar would say less than this line. 0 reads as ungoverned.
		if _has_speed_limit:
			_readout.text += ("  LIM %d" % t.speed_limit) if t.speed_limit > 0 else "  LIM ---"
		# Drone's three range-less readings, same reason as HRS/LIM, plus no room for a fourth
		# bar (see BAR_ROWS_MAX — the drone cluster is full).
		if _has_baro:
			_readout.text += "  BARO %.1f m" % t.get(BARO_FIELD)
		# Gimbal angle pair, whole degrees (what the signal carries).
		if _has_gimbal:
			_readout.text += "  GMB %+d/%+d" % [
				roundi(float(t.get(GIMBAL_PITCH_FIELD))), roundi(float(t.get(GIMBAL_YAW_FIELD)))]
		# Hook load in newtons (hardpoint.Status's unit); 0 with the hook open reads as
		# "carrying nothing" rather than a gap.
		if _has_payload:
			_readout.text += "  PAY %.1f N" % t.get(PAYLOAD_FIELD)


func _update_telltales() -> void:
	var vi := InputRouter.get_vehicle_input()
	# Mirror every lamp/warning bit verbatim; sloppyCAN is the sole authority when the bridge
	# is live, locally only handbrake/horn/brake_lamp are driven and the rest stay off.
	var active := {
		"handbrake": vi.handbrake > 0.0,
		"horn": vi.horn,
		"turnL": vi.lamps.turn_left,
		"turnR": vi.lamps.turn_right,
		"brakeLamp": vi.lamps.brake_lamp,
		"checkEngine": vi.lamps.check_engine,
		"battery": vi.lamps.battery_warn,
		"arm": vi.arm,
		"pantograph": vi.pantograph,
		"doors": vi.doors,
		"diff_lock": vi.diff_lock,
		"fwd_drive": vi.fwd_drive,
		"red_stop": vi.lamps.red_stop,
		"amber_warn": vi.lamps.amber_warn,
		"protect_lamp": vi.lamps.protect_lamp,
		"trailer_ebs_fault": vi.lamps.trailer_ebs_fault,
		"trailer_abs_lamp": vi.lamps.trailer_abs_lamp,
		# PTO request, beside the pto_state lamp telemetry drives: separates "commanded" from
		# "engaged".
		"pto": vi.pto,
		"beep": vi.lamps.beep,
		# Cargo hook request, beside hardpoint_state: separates "asked" from "caught something".
		"hardpoint_cmd": vi.hardpoint_cmd,
		"beacon": vi.lamps.beacon,
		"strobe": vi.lamps.strobe,
	}
	for sig_name in _lamps:
		var on: bool = active.get(sig_name, false)
		var col: Color = LAMP_COLOR.get(sig_name, Color(1.0, 0.70, 0.15)) if on else LAMP_OFF
		_lamps[sig_name].add_theme_color_override("font_color", col)

	var enums := {
		"key": vi.key, "lights": vi.lights, "pto_mode": vi.pto_mode,
		# Refuse body command, beside the body_state chip telemetry drives — so "commanded but
		# inhibited" reads.
		"body_cmd": vi.body_cmd,
	}
	for sig_name in _chips:
		var label: Label = _chips[sig_name][0]
		var sig: RefCounted = _chips[sig_name][1]
		var raw: int = enums.get(sig_name, 0)
		label.text = "%s:%s" % [sig_name.to_upper(), sig.enum_label(raw)]
