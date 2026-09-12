class_name ActionRegistry
extends RefCounted
## Registry of every bound input action: who uses it and its on-screen button. A registry, not
## a copy of InputMap (no key names typed here); `keys_for()` reads the live binding. Pure
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

const BRIDGE_NOTE := "sloppyCAN is driving"

## Every bound action, one row each — one control on two keys (drive/reverse, steer, climb)
## becomes one row. Gating fields: families (empty = all), excludes, capability
## (shell-read bool), bridge_owned (VehicleInput-only, inert when bridge active; shell signals
## are always local). signals: contract IN signal(s), cross-checked vs contract's vehicles list.
## touch_state: a VehicleInput field that is truthy while the switch is engaged — the button
## then reads "<label> ON" in amber. Only for on/off switches; a cycled ladder has no ON.
##
## Pedals/joystick are equally inert under bridge but deliberately NOT flagged — they're the
## overlay's identity and flickering them with bridge freshness reads as broken.
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
		"id": &"handbrake", "actions": ["handbrake"], "group": Group.DRIVE,
		"label": "Handbrake", "signals": ["handbrake"], "excludes": ["boat", "drone"],
		"bridge_owned": true,
		# WIDGET: sits beside the steering joystick; on touch it latches (a parking brake
		# held with a finger is not one). Key stays momentary.
		"touch": Touch.WIDGET,
	},
	{
		"id": &"climb", "actions": ["aircraft_up", "aircraft_down"], "group": Group.DRIVE,
		"label": "Climb / descend", "signals": ["elevator", "climb"],
		"families": ["plane", "drone"], "bridge_owned": true,
		"touch": Touch.WIDGET,
	},
	# --- the vehicle's own controls ------------------------------------------
	{
		"id": &"horn", "actions": ["horn"], "group": Group.VEHICLE,
		# WIDGET: sits in the QUICK row on the pedals, not in the EQUIP drawer.
		"label": "Horn", "signals": ["horn"], "bridge_owned": true, "touch": Touch.WIDGET,
	},
	{
		"id": &"headlights", "actions": ["headlights"], "group": Group.VEHICLE,
		# WIDGET, same reason as horn: lives in the QUICK row.
		"label": "Lights (off / clearance / low / high)", "signals": ["lights"],
		"bridge_owned": true, "touch": Touch.WIDGET,
	},
	{
		# No `signals`, deliberately: on a semi this reads the same local toggle as a tipper
		# valve with no contract signal of its own (see src/vehicles/CLAUDE.md). Naming
		# hitch_pos here would fail the family cross-check for the right reason.
		"id": &"hitch", "actions": ["hitch"], "group": Group.VEHICLE,
		"label": "Raise / lower the hitch (tip the body)",
		"capability": "lift", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "TIP", "poll_key": &"hitch_toggle",
	},
	{
		"id": &"pto", "actions": ["pto"], "group": Group.VEHICLE,
		"label": "PTO drive", "signals": ["pto"], "families": ["tractor", "truck"],
		"capability": "pto", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO", "poll_key": &"pto_toggle", "touch_state": "pto",
	},
	{
		"id": &"pto_mode", "actions": ["pto_mode"], "group": Group.VEHICLE,
		"label": "PTO speed (540 / 1000)", "signals": ["pto_mode"], "families": ["tractor"],
		"bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO SPD", "poll_key": &"pto_mode_toggle",
	},
	{
		# Has a local key where the truck's `retarder` does not — see input_router.gd's
		# _scv declaration. Capability-gated, not family-gated: a bare tractor has no remote
		# plumbed in, so the button appears with the machine that answers it, like PTO.
		"id": &"scv", "actions": ["scv"], "group": Group.VEHICLE,
		"label": "Hydraulic remote (SCV) spool", "signals": ["scv_flow"], "families": ["tractor"],
		"capability": "scv", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "SCV", "poll_key": &"scv_toggle",
		"touch_state": "scv_flow",
	},
	{
		"id": &"diff_lock", "actions": ["diff_lock"], "group": Group.VEHICLE,
		"label": "Rear diff lock", "signals": ["diff_lock"], "families": ["tractor"],
		"capability": "diff_lock", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "DIFF", "poll_key": &"diff_lock_toggle",
		"touch_state": "diff_lock",
	},
	{
		"id": &"fwd_drive", "actions": ["fwd_drive"], "group": Group.VEHICLE,
		"label": "Front-wheel drive (MFWD)", "signals": ["fwd_drive"], "families": ["tractor"],
		"capability": "fwd_drive", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "MFWD", "poll_key": &"fwd_drive_toggle",
		"touch_state": "fwd_drive",
	},
	{
		"id": &"arm", "actions": ["arm"], "group": Group.VEHICLE,
		"label": "Arm the motors", "signals": ["arm"], "families": ["drone"], "bridge_owned": true,
		# WIDGET: the QUICK row's latch slot above GAS, where HAND sits on wheeled machines.
		"touch": Touch.WIDGET, "poll_key": &"arm_toggle", "touch_state": "arm",
	},
	{
		# Key is Z: Q (the letter originally assumed free) has been the tractor's SCV spool
		# since that control got a key; Z is the only unbound letter left.
		"id": &"flight_mode", "actions": ["flight_mode"], "group": Group.VEHICLE,
		"label": "Flight mode (stabilize / alt hold / loiter / RTL / land)",
		"signals": ["flight_mode"], "families": ["drone"], "bridge_owned": true,
		# WIDGET like ARM, not TAP like FAIL below: reached for while flying, so it sits in the
		# QUICK row rather than in the EQUIP drawer.
		"touch": Touch.WIDGET, "poll_key": &"flight_mode_cycle",
	},
	{
		"id": &"node_fail", "actions": ["node_fail"], "group": Group.VEHICLE,
		"label": "Fail a bus node (cycle)", "signals": ["node_fail"], "families": ["drone"],
		"bridge_owned": true,
		# TAP, not WIDGET like ARM: a bench switch, not a flight control, so it belongs in the
		# EQUIP drawer where a mis-tap while flying costs nothing.
		"touch": Touch.TAP, "touch_label": "FAIL", "poll_key": &"node_fail_cycle",
	},
	{
		# First control on a digit (1): every letter is bound. TAP, matching PTO/TIP — a load
		# control used from a steady hover, not a stick flown with.
		"id": &"hardpoint", "actions": ["hardpoint"], "group": Group.VEHICLE,
		"label": "Cargo hook (hold / release)", "signals": ["hardpoint_cmd"],
		"families": ["drone"], "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "HOOK", "poll_key": &"hardpoint_toggle",
		"touch_state": "hardpoint_cmd",
	},
	{
		# Second control on a digit (2), after HOOK on 1: every letter is bound. TAP rather than
		# WIDGET — engaging a pilot is a tap, not an axis steered with, and the EQUIP drawer has
		# room where the QUICK row does not.
		"id": &"nav_mode", "actions": ["nav_mode"], "group": Group.VEHICLE,
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
		"id": &"sheet", "actions": ["sheet"], "group": Group.VEHICLE,
		"label": "Sheet (haul in / ease the sail)", "signals": ["sheet"], "families": ["boat"],
		"capability": "sail", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "SHEET", "poll_key": &"sheet_cycle",
	},
	{
		"id": &"flaps", "actions": ["flaps"], "group": Group.VEHICLE,
		"label": "Flaps", "signals": ["flaps"], "families": ["plane"], "bridge_owned": true,
		# WIDGET, same reason as ARM: in the QUICK row, not the EQUIP drawer.
		"touch": Touch.WIDGET, "poll_key": &"flaps_toggle", "touch_state": "flaps",
	},
	{
		"id": &"pantograph", "actions": ["pantograph"], "group": Group.VEHICLE,
		"label": "Pantograph up / down", "signals": ["pantograph"], "families": ["train"],
		"bridge_owned": true,
		# WIDGET: built in the pedal row beside BRAKE, where the driving hand is.
		"touch": Touch.WIDGET, "poll_key": &"pantograph_toggle", "touch_state": "pantograph",
	},
	{
		"id": &"doors", "actions": ["doors"], "group": Group.VEHICLE,
		"label": "Doors", "signals": ["doors"], "families": ["train"], "bridge_owned": true,
		# WIDGET, same reason as PANTO: sits in the QUICK row beside LIGHTS.
		"touch": Touch.WIDGET, "poll_key": &"doors_toggle", "touch_state": "doors",
	},
	{
		"id": &"body_cmd", "actions": ["body_cmd"], "group": Group.VEHICLE,
		"label": "Refuse body (idle / lift / dump / lower)", "signals": ["body_cmd"],
		"families": ["truck"], "capability": "body_cmd", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "BODY", "poll_key": &"body_cmd_toggle",
	},
	{
		# Not bridge_owned: the attachment cycle is a local authoring convenience with no
		# contract signal, so sloppyCAN driving does not take it away.
		"id": &"next_attachment", "actions": ["next_attachment"], "group": Group.VEHICLE,
		"label": "Next implement / trailer", "capability": "tows",
		"touch": Touch.SHELL_SIGNAL, "touch_label": "ATTACH",
	},
	# --- the world -----------------------------------------------------------
	{
		"id": &"camera_view", "actions": ["camera_view"], "group": Group.WORLD,
		"label": "Camera view", "touch": Touch.SHELL_SIGNAL, "touch_label": "VIEW",
	},
	{
		# Keyboard-only: the pause menu's RESPAWN row reaches touch.
		"id": &"respawn", "actions": ["respawn"], "group": Group.WORLD,
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
		"id": &"garage", "actions": ["garage"], "group": Group.SHELL,
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
		"id": &"to_menu", "actions": ["to_menu"], "group": Group.SHELL,
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
		# The top-left MENU/GARAGE/LEVEL/VIEW column, apart from F4 so hiding the pads never
		# takes the way back to the menu with them.
		"id": &"toggle_important", "actions": ["toggle_important"], "group": Group.SHELL,
		"label": "Touch menu buttons on / off",
	},
]

## Section headings, in Group order.
const GROUP_TITLES := ["DRIVE", "VEHICLE", "WORLD", "SHELL"]


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
static func context(family: String, bridge_active: bool, caps: Dictionary) -> Dictionary:
	return {"family": family, "bridge": bridge_active, "caps": caps}


## Does this control do something right now? The one gate predicate — touch overlay and
## CONTROLS sheet both read it, so a button and its help can never disagree.
static func applies(id: StringName, ctx: Dictionary) -> bool:
	return applies_entry(find(id), ctx)


static func applies_entry(entry: Dictionary, ctx: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if bool(entry.get("bridge_owned", false)) and bool(ctx.get("bridge", false)):
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


## Does `entry` fit the current vehicle/attachment at all, ignoring whether the bridge happens
## to own it right now? The CONTROLS sheet's one predicate for whether a row is worth SHOWING
## (hidden if not: the boat has no diff lock, ever) — a row that fits but is bridge-owned while
## sloppyCAN drives still shows, greyed, since that reason goes away on its own.
static func relevant_entry(entry: Dictionary, ctx: Dictionary) -> bool:
	var without_bridge := ctx.duplicate()
	without_bridge["bridge"] = false
	return applies_entry(entry, without_bridge)


## Why `entry` does not apply, for the sheet's third column ("" when it does apply). Bridge is
## reported first since it's the reason most likely to go away again.
static func gate_note(entry: Dictionary, ctx: Dictionary) -> String:
	if applies_entry(entry, ctx):
		return ""
	if bool(entry.get("bridge_owned", false)) and bool(ctx.get("bridge", false)):
		return BRIDGE_NOTE
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
## joined: a two-action row reads "W / S". Joypad bindings are skipped (the sheet footnotes
## them once for the drive group).
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


static func _join_families(families: Array) -> String:
	if families.size() == 1:
		return String(families[0])
	var head := PackedStringArray()
	for i in families.size() - 1:
		head.append(String(families[i]))
	return ", ".join(head) + " and " + String(families[-1])
