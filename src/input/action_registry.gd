class_name ActionRegistry
extends RefCounted
## Registry of every bound input action: who uses it and its on-screen button. A registry, not
## a copy of InputMap (no key names typed here); `keys_for()` reads the live binding. The pad's
## buttons are not in InputMap: each row's `pad` slot is their one binding (`pad_action`). Pure
## static data + functions; tests assert every bound action appears here. No emoji.

## Where a row sits on the CONTROLS sheet. Ordering here is the sheet's section order.
enum Group { DRIVE, VEHICLE, WORLD, SHELL }

## How the touch overlay offers the row.
##  NONE         - keyboard only, documented but not on screen (dev keys, day/night)
##  TAP          - a stack button latching a one-shot edge under `poll_key`
##  HOLD         - a stack button holding a level under `poll_key` while pressed
##  SHELL_SIGNAL - a stack button emitting one of the overlay's shell signals
##  WIDGET       - not a stack button: the joystick, the pedals, the flight pads. The overlay
##                 builds those by hand and only asks this table whether to SHOW them.
enum Touch { NONE, TAP, HOLD, SHELL_SIGNAL, WIDGET }

## Why a capability-gated row does not apply right now, for the sheet's third column. Derived
## rather than a per-row field so the phrase cannot drift from the capability it explains.
const CAP_NOTE := {
	"tows": "nothing to tow",
	"pto": "no PTO on this machine",
	"lift": "nothing to raise",
	"scv": "no hydraulic remote plumbed in",
	"diff_lock": "no lockable diff",
	"fwd_drive": "no engageable front axle",
	"body_cmd": "no refuse body",
	"sail": "no rig on this hull",
}

## Pad slots that mean something only under a menu: accept the focused control, and go back.
const MENU_PAD := {"cross": &"ui_accept", "circle": &"to_menu"}
const BRIDGE_NOTE := "sloppyCAN is driving"
## A live bridge that carries no driving control: the keyboard drives, sloppyCAN still sets this.
const BRIDGE_SETS_NOTE := "set by sloppyCAN"

## Every bound action, one row each (one control on two keys is one row). Gating: families (empty
## = all), excludes, capability, bridge_owned (inert under the bridge), driving (bridge-owned only
## while the bridge DRIVES). signals: contract IN signal(s). touch_state: a VehicleInput field
## truthy while an on/off switch is engaged (the button reads "<label> ON" in amber). pad: the
## gamepad button per action, parallel to `actions` (PadLayer.BUTTONS names, "l1+" = held with
## L1); rows share a slot only where no context applies two of them (tests/test_action_registry.gd).
## pad_axis: the pad's name for a stick InputMap does not carry (`pad_for`).
## Pedals/joystick are not flagged on purpose: greying them with bridge freshness reads as broken.
const ENTRIES: Array[Dictionary] = [
	# --- drive ---------------------------------------------------------------
	{
		"id": &"drive", "actions": ["accel", "brake_reverse"], "group": Group.DRIVE,
		"label": "Drive / reverse", "signals": ["accel", "brake"], "touch": Touch.WIDGET,
	},
	{
		"id": &"steer", "actions": ["steer_left", "steer_right"], "group": Group.DRIVE,
		"label": "Steer", "signals": ["steer"], "excludes": ["train"], "touch": Touch.WIDGET,
	},
	{
		# Excluded where there's nothing to hold: boat/drone have no wheels for brake torque.
		# Plane's tricycle gear takes it; train's is read by TrainSim rather than wheels.
		"id": &"handbrake", "actions": ["handbrake"], "pad": ["cross"], "group": Group.DRIVE,
		"label": "Handbrake", "signals": ["handbrake"], "excludes": ["boat", "drone"],
		# Momentary on the key and the pad; touch has only the latch below (a parking brake held
		# with a finger is not one).
		"bridge_owned": true, "driving": true,
	},
	{
		# The latch InputRouter owns (`_parking_brake`); `handbrake` reads the stronger of it and the
		# held control. Plain R1: no role without L1 on a wheeled body. WIDGET: touch's HAND, the
		# QUICK row's latch slot above GAS.
		"id": &"parking_brake", "actions": ["parking_brake"], "pad": ["r1"], "group": Group.DRIVE,
		"label": "Parking brake (on / off)", "signals": ["handbrake"],
		"excludes": ["boat", "drone"], "bridge_owned": true, "driving": true,
		"touch": Touch.WIDGET, "poll_key": &"parking_brake_toggle", "touch_state": "handbrake",
	},
	{
		"id": &"climb", "actions": ["aircraft_up", "aircraft_down"], "group": Group.DRIVE,
		"label": "Climb / descend", "signals": ["elevator", "climb"],
		"families": ["plane", "drone"], "bridge_owned": true, "driving": true,
		# Not in InputMap: PadSource reads the stick itself (plane pull-back and drone push are
		# both "up"), so the sheet's name for it is typed here.
		"pad_axis": "Left stick up / down", "touch": Touch.WIDGET,
	},
	# --- the vehicle's own controls ------------------------------------------
	{
		"id": &"horn", "actions": ["horn"], "pad": ["l3"], "group": Group.VEHICLE,
		# WIDGET: sits in the QUICK row on the pedals, not in the EQUIP drawer.
		"label": "Horn", "signals": ["horn"], "bridge_owned": true, "driving": true,
		"touch": Touch.WIDGET,
	},
	{
		"id": &"headlights", "actions": ["headlights"], "pad": ["square"], "group": Group.VEHICLE,
		# WIDGET, same reason as horn: lives in the QUICK row.
		"label": "Lights (off / clearance / low / high)", "signals": ["lights"],
		"bridge_owned": true, "driving": true, "touch": Touch.WIDGET,
	},
	{
		# No `signals`, deliberately: on a semi this reads the same local toggle as a tipper
		# valve with no contract signal of its own (see src/vehicles/truck/CLAUDE.md). Naming hitch_pos here would fail the family cross-check for the right reason.
		# `families` only so L1+square can be shared: just the tractor and the semi report `lift`.
		"id": &"hitch", "actions": ["hitch"], "pad": ["l1+square"], "group": Group.VEHICLE,
		"label": "Raise / lower the hitch (tip the body)", "families": ["tractor", "truck"],
		"capability": "lift", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "TIP", "poll_key": &"hitch_toggle",
	},
	{
		"id": &"pto", "actions": ["pto"], "pad": ["l1+circle"], "group": Group.VEHICLE,
		"label": "PTO drive", "signals": ["pto"], "families": ["tractor", "truck"],
		"capability": "pto", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO", "poll_key": &"pto_toggle", "touch_state": "pto",
	},
	{
		"id": &"pto_mode", "actions": ["pto_mode"], "pad": ["l1+r1"], "group": Group.VEHICLE,
		"label": "PTO speed (540 / 1000)", "signals": ["pto_mode"], "families": ["tractor"],
		"bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO SPD", "poll_key": &"pto_mode_toggle",
	},
	{
		# Every letter and 1-5 are bound: minus / equals read as down / up. Keyboard and pad only:
		# touch gets the preset below, which sets and clears it in one button.
		"id": &"hand_throttle", "actions": ["hand_throttle_down", "hand_throttle_up"],
		"pad": ["l1+dpad_down", "l1+dpad_up"], "group": Group.VEHICLE,
		"label": "Hand throttle down / up", "signals": ["hand_throttle"],
		"families": ["tractor"], "bridge_owned": true,
	},
	{
		"id": &"hand_throttle_pto", "actions": ["hand_throttle_pto"], "pad": ["l1+r3"],
		"group": Group.VEHICLE,
		"label": "Hand throttle to the PTO's rated speed (again: off)", "signals": ["hand_throttle"],
		"families": ["tractor"], "bridge_owned": true,
		# No `touch_state`: the hand throttle is a level, not an on/off switch, so "ON" would read
		# for any setting, the preset or not.
		"touch": Touch.TAP, "touch_label": "PTO RPM", "poll_key": &"hand_throttle_pto_toggle",
	},
	{
		# Has a local key where the truck's `retarder` does not — see input_router.gd's
		# _scv declaration. Capability-gated, not family-gated: a bare tractor has no remote
		# plumbed in, so the button appears with the machine that answers it, like PTO.
		"id": &"scv", "actions": ["scv"], "pad": ["l1+cross"], "group": Group.VEHICLE,
		"label": "Hydraulic remote (SCV) spool", "signals": ["scv_flow"], "families": ["tractor"],
		"capability": "scv", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "SCV", "poll_key": &"scv_toggle",
		"touch_state": "scv_flow",
	},
	{
		"id": &"diff_lock", "actions": ["diff_lock"], "pad": ["l1+dpad_left"],
		"group": Group.VEHICLE,
		"label": "Rear diff lock", "signals": ["diff_lock"], "families": ["tractor"],
		"capability": "diff_lock", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "DIFF LOCK", "poll_key": &"diff_lock_toggle",
		"touch_state": "diff_lock",
	},
	{
		"id": &"fwd_drive", "actions": ["fwd_drive"], "pad": ["l1+dpad_right"],
		"group": Group.VEHICLE,
		"label": "Front-wheel drive (MFWD)", "signals": ["fwd_drive"], "families": ["tractor"],
		"capability": "fwd_drive", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "MFWD", "poll_key": &"fwd_drive_toggle",
		"touch_state": "fwd_drive",
	},
	{
		"id": &"arm", "actions": ["arm"], "pad": ["l1+square"], "group": Group.VEHICLE,
		"label": "Arm the motors", "signals": ["arm"], "families": ["drone"], "bridge_owned": true,
		"driving": true,
		# WIDGET: the QUICK row's latch slot above GAS, where HAND sits on wheeled machines.
		"touch": Touch.WIDGET, "poll_key": &"arm_toggle", "touch_state": "arm",
	},
	{
		# Key is Z: Q (the letter originally assumed free) has been the tractor's SCV spool
		# since that control got a key; Z is the only unbound letter left.
		"id": &"flight_mode", "actions": ["flight_mode"], "pad": ["l1+circle"],
		"group": Group.VEHICLE,
		"label": "Flight mode (stabilize / alt hold / loiter / RTL / land)",
		"signals": ["flight_mode"], "families": ["drone"], "bridge_owned": true,
		# WIDGET like ARM, not TAP like FAIL below: reached for while flying, so it sits in the
		# QUICK row rather than in the EQUIP drawer.
		"touch": Touch.WIDGET, "poll_key": &"flight_mode_cycle",
	},
	{
		"id": &"node_fail", "actions": ["node_fail"], "pad": ["l1+r1"], "group": Group.VEHICLE,
		"label": "Fail a bus node (cycle)", "signals": ["node_fail"], "families": ["drone"],
		"bridge_owned": true,
		# TAP, not WIDGET like ARM: a bench switch, not a flight control, so it belongs in the
		# EQUIP drawer where a mis-tap while flying costs nothing.
		"touch": Touch.TAP, "touch_label": "FAIL", "poll_key": &"node_fail_cycle",
	},
	{
		# First control on a digit (1): every letter is bound. TAP, matching PTO/TIP — a load
		# control used from a steady hover, not a stick flown with.
		"id": &"hardpoint", "actions": ["hardpoint"], "pad": ["l1+cross"], "group": Group.VEHICLE,
		"label": "Cargo hook (hold / release)", "signals": ["hardpoint_cmd"],
		"families": ["drone"], "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "HOOK", "poll_key": &"hardpoint_toggle",
		"touch_state": "hardpoint_cmd",
	},
	{
		# Second control on a digit (2), after HOOK on 1: every letter is bound. TAP rather than
		# WIDGET — engaging a pilot is a tap, not an axis steered with, and the EQUIP drawer has
		# room where the QUICK row does not.
		"id": &"nav_mode", "actions": ["nav_mode"], "pad": ["l1+square"], "group": Group.VEHICLE,
		"label": "Autopilot (standby / heading hold)", "signals": ["nav_mode"],
		"families": ["boat"], "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "AUTO", "poll_key": &"nav_mode_cycle",
	},
	{
		# Third control on a digit (3), after HOOK on 1 and AUTO on 2: every letter is bound. TAP
		# rather than WIDGET for the same reason AUTO is — trimming is a tap between manoeuvres,
		# not an axis steered with, and the EQUIP drawer has room the QUICK row does not.
		# Capability-gated, not family-gated: a rig is anatomy, and only `boat-sail-a` has one, so
		# the button appears with the machine that answers it (the BODY / PTO precedent).
		"id": &"sheet", "actions": ["sheet"], "pad": ["l1+circle"], "group": Group.VEHICLE,
		"label": "Sheet (haul in / ease the sail)", "signals": ["sheet"], "families": ["boat"],
		"capability": "sail", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "SHEET", "poll_key": &"sheet_cycle",
	},
	{
		"id": &"flaps", "actions": ["flaps"], "pad": ["l1+square"], "group": Group.VEHICLE,
		"label": "Flaps", "signals": ["flaps"], "families": ["plane"], "bridge_owned": true,
		# WIDGET, same reason as ARM: in the QUICK row, not the EQUIP drawer.
		"touch": Touch.WIDGET, "poll_key": &"flaps_toggle", "touch_state": "flaps",
	},
	{
		"id": &"pantograph", "actions": ["pantograph"], "pad": ["l1+square"],
		"group": Group.VEHICLE,
		"label": "Pantograph up / down", "signals": ["pantograph"], "families": ["train"],
		"bridge_owned": true,
		# WIDGET: built in the pedal row beside BRAKE, where the driving hand is.
		"touch": Touch.WIDGET, "poll_key": &"pantograph_toggle", "touch_state": "pantograph",
	},
	{
		"id": &"doors", "actions": ["doors"], "pad": ["l1+circle"], "group": Group.VEHICLE,
		"label": "Doors", "signals": ["doors"], "families": ["train"], "bridge_owned": true,
		# WIDGET, same reason as PANTO: sits in the QUICK row beside LIGHTS.
		"touch": Touch.WIDGET, "poll_key": &"doors_toggle", "touch_state": "doors",
	},
	{
		"id": &"body_cmd", "actions": ["body_cmd"], "pad": ["l1+cross"], "group": Group.VEHICLE,
		"label": "Refuse body (idle / lift / dump / lower)", "signals": ["body_cmd"],
		"families": ["truck"], "capability": "body_cmd", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "BODY", "poll_key": &"body_cmd_toggle",
	},
	{
		# Not bridge_owned: the attachment cycle is a local authoring convenience with no
		# contract signal, so sloppyCAN driving does not take it away.
		"id": &"next_attachment", "actions": ["next_attachment"], "pad": ["l1+triangle"],
		"group": Group.VEHICLE,
		"label": "Next implement / trailer", "capability": "tows",
		"touch": Touch.SHELL_SIGNAL, "touch_label": "ATTACH",
	},
	# --- the world -----------------------------------------------------------
	{
		"id": &"camera_view", "actions": ["camera_view"], "pad": ["circle"], "group": Group.WORLD,
		"label": "Camera view", "touch": Touch.SHELL_SIGNAL, "touch_label": "CAMERA",
	},
	{
		# No action: level.gd reads the stick raw, as it reads the mouse's right-drag (view-only).
		"id": &"camera_look", "actions": [], "group": Group.WORLD,
		"label": "Look around the vehicle", "pad_axis": "Right stick",
	},
	{
		# Pad only: the mouse wheel and a right-click do these raw in level.gd.
		"id": &"camera_recenter", "actions": ["camera_recenter"], "pad": ["r3"],
		"group": Group.WORLD, "label": "Recenter the camera",
	},
	{
		# Held: level.gd zooms while the action is down, not a step per press like the wheel.
		"id": &"camera_zoom", "actions": ["camera_zoom_in", "camera_zoom_out"],
		"pad": ["dpad_up", "dpad_down"], "group": Group.WORLD, "label": "Camera zoom in / out",
	},
	{
		# Keyboard and pad only: the pause menu's RESPAWN row reaches touch.
		"id": &"respawn", "actions": ["respawn"], "pad": ["triangle"], "group": Group.WORLD,
		"label": "Respawn",
	},
	{
		# Keyboard-only, same reason as RESPAWN — the CONDITIONS page carries the day/night
		# toggle for touch.
		"id": &"day_night", "actions": ["day_night"], "group": Group.WORLD,
		"label": "Day / night",
	},
	# --- the shell -----------------------------------------------------------
	{
		"id": &"garage", "actions": ["garage"], "pad": ["create"], "group": Group.SHELL,
		"label": "Garage", "touch": Touch.SHELL_SIGNAL, "touch_label": "VEHICLE",
	},
	{
		# Keyboard-only: the garage is the way to change vehicle on touch, so the stack does not
		# also carry a blind "next body" button.
		"id": &"next_vehicle", "actions": ["next_vehicle"], "group": Group.SHELL,
		"label": "Next vehicle body",
	},
	{
		"id": &"level_select", "actions": ["level_select"], "group": Group.SHELL,
		"label": "Level select", "touch": Touch.SHELL_SIGNAL, "touch_label": "LEVEL",
	},
	{
		# Every letter is bound (see FLIGHT_MODE's note); 5 is the next free digit after
		# HOOK/AUTO/SHEET/LEVEL claimed 1-4.
		"id": &"challenge_select", "actions": ["challenge_select"], "group": Group.SHELL,
		"label": "Challenges", "touch": Touch.SHELL_SIGNAL, "touch_label": "CHALLENGE",
	},
	{
		"id": &"to_menu", "actions": ["to_menu"], "pad": ["options"], "group": Group.SHELL,
		"label": "Menu / back", "touch": Touch.SHELL_SIGNAL, "touch_label": "MENU",
	},
	{
		# Same setting the SETTINGS page cycles; F2 drops the cluster to OFF and back.
		# Keyboard-only — the pause menu is one tap away on touch.
		"id": &"toggle_dashboard", "actions": ["toggle_dashboard"], "group": Group.SHELL,
		"label": "Dashboard on / off",
	},
	{
		"id": &"debug_overlay", "actions": ["debug_overlay"], "group": Group.SHELL,
		"label": "Debug overlay",
	},
	{
		"id": &"toggle_touch", "actions": ["toggle_touch"], "group": Group.SHELL,
		"label": "Touch driving controls on / off",
	},
	{
		# The top-left MENU/GARAGE/LEVEL/CAMERA column, apart from F4 so hiding the pads never
		# takes the way back to the menu with them.
		"id": &"toggle_important", "actions": ["toggle_important"], "group": Group.SHELL,
		"label": "Touch menu buttons on / off",
	},
]

## Section headings, in Group order.
const GROUP_TITLES := ["DRIVE", "VEHICLE", "WORLD", "SHELL"]

## A joypad axis bound in InputMap -> its name on screen.
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "Left stick",
	JOY_AXIS_LEFT_Y: "Left stick",
	JOY_AXIS_RIGHT_X: "Right stick",
	JOY_AXIS_RIGHT_Y: "Right stick",
	JOY_AXIS_TRIGGER_LEFT: "L2",
	JOY_AXIS_TRIGGER_RIGHT: "R2",
}


static func entries() -> Array[Dictionary]:
	return ENTRIES


static func find(id: StringName) -> Dictionary:
	for e in ENTRIES:
		if e["id"] == id:
			return e
	return {}


static func in_group(group: Group) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in ENTRIES:
		if int(e["group"]) == int(group):
			out.append(e)
	return out


## The state every gate is evaluated against. `caps` is the shell's capability dict (see
## boot.gd _capabilities); a missing key reads false, so a caller with nothing to say about
## capabilities still gets sensible family-only gating.
## `bridge_drives` is `InputRouter.bridge_drives()`: false in fallback, where a `driving` row is
## the local driver's while the rest of the bridge-owned rows stay sloppyCAN's.
static func context(family: String, bridge_active: bool, caps: Dictionary,
		bridge_drives := bridge_active) -> Dictionary:
	return {"family": family, "bridge": bridge_active, "drives": bridge_drives, "caps": caps}


## Is this row inert because sloppyCAN owns it right now? A `driving` row follows whoever
## drives; any other bridge-owned row is the bridge's whenever one is live.
static func _bridge_holds(entry: Dictionary, ctx: Dictionary) -> bool:
	if not bool(entry.get("bridge_owned", false)):
		return false
	var key := "drives" if bool(entry.get("driving", false)) else "bridge"
	return bool(ctx.get(key, false))


## Does this control do something right now? The one gate predicate — touch overlay and
## CONTROLS sheet both read it, so a button and its help can never disagree.
static func applies(id: StringName, ctx: Dictionary) -> bool:
	return applies_entry(find(id), ctx)


static func applies_entry(entry: Dictionary, ctx: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if _bridge_holds(entry, ctx):
		return false
	var family := String(ctx.get("family", ""))
	var families: Array = entry.get("families", [])
	if not families.is_empty() and not families.has(family):
		return false
	if entry.get("excludes", []).has(family):
		return false
	var cap := String(entry.get("capability", ""))
	if cap != "" and not bool((ctx.get("caps", {}) as Dictionary).get(cap, false)):
		return false
	return true


## The action a gamepad `slot` ("cross", "l1+square", ...) presses in `ctx`, or &"" for none: the
## one row whose `pad` holds it and that applies. While `paused` (a menu is up) only SHELL rows
## answer, so Options still closes the menu and no vehicle control latches under it; Cross presses
## the focused control (`ui_accept`) and Circle backs out like Esc (`to_menu`), which Godot's
## built-in `ui_*` map gives no pad button.
static func pad_action(slot: String, ctx: Dictionary, paused := false) -> StringName:
	if paused and MENU_PAD.has(slot):
		return MENU_PAD[slot]
	for e in ENTRIES:
		var i: int = e.get("pad", []).find(slot)
		if i < 0 or (paused and int(e["group"]) != Group.SHELL):
			continue
		if applies_entry(e, ctx):
			return StringName(e["actions"][i])
	return &""


## The action a gamepad button `slot` presses with L1 `l1` held: the L1 layer's row, else (no L1
## role on this vehicle) the button's own, so a button with nothing on L1 still works with L1 down.
## A role the vehicle has but that is inert right now (sloppyCAN owns it, a menu is up) does not
## fall through: L1+Square on a tractor whose hitch sloppyCAN sets must not cycle the lights.
static func pad_press(slot: String, l1: bool, ctx: Dictionary, paused := false) -> StringName:
	if l1 and not (paused and MENU_PAD.has(slot)):  # L1 down in a menu must not kill Cross / Circle
		var layered := PadLayer.LAYER_PREFIX + slot
		for e in ENTRIES:
			if e.get("pad", []).has(layered) and relevant_entry(e, ctx):
				return pad_action(layered, ctx, paused)
	return pad_action(slot, ctx, paused)


## Does `entry` fit the current vehicle/attachment at all, ignoring whether the bridge happens
## to own it right now? The CONTROLS sheet's one predicate for whether a row is worth SHOWING
## (hidden if not: the boat has no diff lock, ever) — a row that fits but is bridge-owned while
## sloppyCAN drives still shows, greyed, since that reason goes away on its own.
static func relevant_entry(entry: Dictionary, ctx: Dictionary) -> bool:
	var without_bridge := ctx.duplicate()
	without_bridge["bridge"] = false
	without_bridge["drives"] = false
	return applies_entry(entry, without_bridge)


## Why `entry` does not apply, for the sheet's third column ("" when it does apply). Bridge is
## reported first since it's the reason most likely to go away again.
static func gate_note(entry: Dictionary, ctx: Dictionary) -> String:
	if applies_entry(entry, ctx):
		return ""
	if _bridge_holds(entry, ctx):
		return BRIDGE_NOTE if bool(ctx.get("drives", false)) else BRIDGE_SETS_NOTE
	var families: Array = entry.get("families", [])
	if not families.is_empty() and not families.has(String(ctx.get("family", ""))):
		return _join_families(families) + " only"
	if entry.get("excludes", []).has(String(ctx.get("family", ""))):
		return "not on the " + String(ctx.get("family", ""))
	var cap := String(entry.get("capability", ""))
	return String(CAP_NOTE.get(cap, "unavailable"))


## Families this row applies to, with shorthand expanded (empty `families` = every family,
## `excludes` = every family but those). `all_families` is passed in to keep this file free
## of a VehicleCatalog dependency. Not used by the runtime gate — for the contract cross-check
## in tests/test_action_registry.gd.
static func families_of(entry: Dictionary, all_families: PackedStringArray) -> PackedStringArray:
	var declared: Array = entry.get("families", [])
	if not declared.is_empty():
		var out := PackedStringArray()
		for f in declared:
			out.append(String(f))
		return out
	var excludes: Array = entry.get("excludes", [])
	var rest := PackedStringArray()
	for f in all_families:
		if not excludes.has(f):
			rest.append(f)
	return rest


## Whether every vehicle has this control. Splits the touch stack into two columns: universal
## controls outer, the current machine's own beside them.
static func is_universal(entry: Dictionary) -> bool:
	return entry.get("families", []).is_empty() \
			and entry.get("excludes", []).is_empty() \
			and String(entry.get("capability", "")) == ""


## The row's binding, read live out of InputMap — never a typed-in string. One key per action,
## joined: a two-action row reads "W / S". Joypad bindings are skipped (`pad_for` names them).
static func keys_for(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	for action in entry.get("actions", []):
		var action_name := StringName(action)
		if not InputMap.has_action(action_name):
			continue
		for ev in InputMap.action_get_events(action_name):
			var key_ev := ev as InputEventKey
			if key_ev == null or key_ev.physical_keycode == KEY_NONE:
				continue
			parts.append(OS.get_keycode_string(key_ev.physical_keycode))
			break
	return " / ".join(parts)


## The row's gamepad binding, for the sheet and the L1 legend: its `pad` slots by name
## ("L1 + Square", a two-action row "L1 + D-pad down / D-pad up"), else its joypad axes read live
## out of InputMap ("R2 / L2"), else its `pad_axis`; "" when the pad does not reach it.
static func pad_for(entry: Dictionary) -> String:
	var slots: Array = entry.get("pad", [])
	if not slots.is_empty():
		var all_layered := true
		for slot: String in slots:
			all_layered = all_layered and slot.begins_with(PadLayer.LAYER_PREFIX)
		var names := PackedStringArray()
		for slot: String in slots:
			var bare := slot.trim_prefix(PadLayer.LAYER_PREFIX)
			var slot_name := String(PadLayer.SLOT_NAMES.get(bare, bare))
			names.append(slot_name if all_layered or bare == slot
					else PadLayer.LAYER_NAME + slot_name)
		return (PadLayer.LAYER_NAME if all_layered else "") + " / ".join(names)
	var axes := PackedStringArray()
	for action in entry.get("actions", []):
		var action_name := StringName(action)
		if not InputMap.has_action(action_name):
			continue
		for ev in InputMap.action_get_events(action_name):
			var motion := ev as InputEventJoypadMotion
			if motion == null:
				continue
			var axis_name := String(AXIS_NAMES.get(motion.axis, ""))
			if axis_name != "" and not axes.has(axis_name):
				axes.append(axis_name)
			break
	if not axes.is_empty():
		return " / ".join(axes)
	return String(entry.get("pad_axis", ""))


## The hold-L1 layer for `ctx`, for the legend shown while L1 is held: each row on it the vehicle
## can use (`relevant_entry`, so a bridge-owned row stays, for the caller to grey), once, in
## PadLayer.SLOT_NAMES order.
static func pad_layer_rows(ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bare: String in PadLayer.SLOT_NAMES:
		var slot := PadLayer.LAYER_PREFIX + bare
		for e in ENTRIES:
			if e.get("pad", []).has(slot) and not out.has(e) and relevant_entry(e, ctx):
				out.append(e)
	return out


static func _join_families(families: Array) -> String:
	if families.size() == 1:
		return String(families[0])
	var head := PackedStringArray()
	for i in families.size() - 1:
		head.append(String(families[i]))
	return ", ".join(head) + " and " + String(families[-1])
