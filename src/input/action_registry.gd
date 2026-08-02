class_name ActionRegistry
extends RefCounted
## The one description of what every bound input action IS, who it applies to, and what its
## on-screen button looks like. Two consumers read it and nothing else describes controls:
## the pause menu's CONTROLS sheet (`src/ui/pause_menu.gd`) and the touch overlay's button
## stack (`src/ui/touch_controls.gd`).
##
## It exists because the same list used to be written three times — a hand-typed hint label, a
## hand-written stack of touch buttons, and the project's [input] map — and only the last one was
## ever true. Ten bound actions had drifted out of the label entirely and six had no touch button
## at all. A test (tests/test_action_registry.gd) now asserts every bound action appears here, so
## a new binding cannot ship undocumented.
##
## IT IS A REGISTRY, NOT A SECOND COPY OF THE INPUT MAP (standing rule 4). No key name is typed
## here: `keys_for()` reads the live binding out of InputMap. The table carries only prose and
## GATING — which vehicles have the control, whether sloppyCAN owns it, and what its button says.
##
## Pure static data + pure functions, no autoload and no nodes, so the gate predicate every
## consumer shares is unit-tested directly (standing rule 8). Plain text, no emoji (rule 10).

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
	"diff_lock": "no lockable diff",
	"fwd_drive": "no engageable front axle",
	"body_cmd": "no refuse body",
}

const BRIDGE_NOTE := "sloppyCAN is driving"

## Every bound action, one row each — except the four pairs that are one control on two keys
## (drive/reverse, steer, climb/descend), which are one row so the sheet reads the way a person
## thinks about them. `id` is the row's name; for a single-action row it is the action name.
##
## Gating vocabulary, and it covers every shape the touch overlay used to hand-write:
##   families     - only these vehicle families have it (empty = all of them)
##   excludes     - every family EXCEPT these (steer: the train is rail-guided; handbrake: the
##                  boat and the drone have no wheels and read the field nowhere)
##   capability   - a bool the shell reads off the vehicle; see boot.gd _capabilities().
##                  Capability rather than family wherever one family disagrees with itself:
##                  within `truck` the semi tows and the garbage truck does not, and cycling a
##                  semi's trailer changes the answer without changing the body.
##   bridge_owned - the control rides VehicleInput, so it is INERT while sloppyCAN drives:
##                  InputRouter takes the bridge branch and never polls a local source at all.
##                  Hidden on touch, greyed on the sheet. Not set on the shell conveniences
##                  (ATTACH, VIEW, GARAGE, NEXT, RESPAWN, MENU), which are overlay signals that
##                  never reach VehicleInput and so keep working with the bridge live.
##                  KNOWN INCONSISTENCY, deliberate: the pedals and the joystick ride VehicleInput
##                  too and are equally inert, but are NOT flagged. They are the identity of the
##                  overlay, `Bridge.is_active()` follows data freshness, and having the gas pedal
##                  vanish and reappear as sloppyCAN stutters reads as the app breaking. This
##                  matches what shipped before the registry; revisit it as a design question, not
##                  by quietly flipping the flag.
##   signals      - the contract IN signal(s) this control rides, when it has one. NOT used at
##                  runtime: tests/test_action_registry.gd cross-checks the family gate above
##                  against the contract's own `vehicles` list, so the two cannot drift (rule 4 —
##                  validated against the contract rather than hand-duplicating it).
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
		# Excluded where there is nothing to hold: the boat and the drone have no wheels for the
		# brake torque to reach and read the field nowhere. The plane's tricycle gear DOES take it
		# (handbrake_torque on three RayWheels) and the train's is read by TrainSim rather than by
		# wheels, so both keep it.
		"id": &"handbrake", "actions": ["handbrake"], "group": Group.DRIVE,
		"label": "Handbrake", "signals": ["handbrake"], "excludes": ["boat", "drone"],
		"bridge_owned": true,
		# WIDGET: it sits beside the steering joystick, and on touch it LATCHES (a parking brake
		# you hold with a finger is not one). The key stays momentary.
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
		# WIDGET, not a stack button: it sits in the pedal cluster beside GAS/BRAKE, where the hand
		# already is, rather than up in the stack of settings.
		"label": "Horn", "signals": ["horn"], "bridge_owned": true, "touch": Touch.WIDGET,
	},
	{
		"id": &"headlights", "actions": ["headlights"], "group": Group.VEHICLE,
		# WIDGET for the same reason as the horn: it lives in the pedal cluster, built by hand.
		"label": "Lights (off / clearance / low / high)", "signals": ["lights"],
		"bridge_owned": true, "touch": Touch.WIDGET,
	},
	{
		# THE ONE ROW WITH NO `signals`, and deliberately so. On a tractor this is `hitch_pos`; on a
		# semi it is the tipper's valve, which reads the SAME local toggle in its transport sense and
		# has NO contract signal of its own — `hitch_pos` is flavored isobus and a bulk tipper is a
		# J1939 truck (the decision is recorded in src/vehicles/CLAUDE.md, same reason `scv_flow` was
		# not reused there). Naming hitch_pos here would fail the family cross-check for the right
		# reason and be silenced for the wrong one, so the row states the exception instead.
		"id": &"hitch", "actions": ["hitch"], "group": Group.VEHICLE,
		"label": "Raise / lower the hitch (tip the body)",
		"capability": "lift", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "TIP", "poll_key": "hitch_toggle",
	},
	{
		"id": &"pto", "actions": ["pto"], "group": Group.VEHICLE,
		"label": "PTO drive", "signals": ["pto"], "families": ["tractor", "truck"],
		"capability": "pto", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO", "poll_key": "pto_toggle",
	},
	{
		"id": &"pto_mode", "actions": ["pto_mode"], "group": Group.VEHICLE,
		"label": "PTO speed (540 / 1000)", "signals": ["pto_mode"], "families": ["tractor"],
		"bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "PTO SPD", "poll_key": "pto_mode_toggle",
	},
	{
		"id": &"diff_lock", "actions": ["diff_lock"], "group": Group.VEHICLE,
		"label": "Rear diff lock", "signals": ["diff_lock"], "families": ["tractor"],
		"capability": "diff_lock", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "DIFF", "poll_key": "diff_lock_toggle",
	},
	{
		"id": &"fwd_drive", "actions": ["fwd_drive"], "group": Group.VEHICLE,
		"label": "Front-wheel drive (MFWD)", "signals": ["fwd_drive"], "families": ["tractor"],
		"capability": "fwd_drive", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "MFWD", "poll_key": "fwd_drive_toggle",
	},
	{
		"id": &"arm", "actions": ["arm"], "group": Group.VEHICLE,
		"label": "Arm the motors", "signals": ["arm"], "families": ["drone"], "bridge_owned": true,
		# WIDGET: built by hand above the UP/DOWN flight pads, where the aircraft controls already are.
		"touch": Touch.WIDGET, "poll_key": "arm_toggle",
	},
	{
		"id": &"flaps", "actions": ["flaps"], "group": Group.VEHICLE,
		"label": "Flaps", "signals": ["flaps"], "families": ["plane"], "bridge_owned": true,
		# WIDGET, same reason as ARM: it belongs above the UP/DOWN pads, not in the settings stack.
		"touch": Touch.WIDGET, "poll_key": "flaps_toggle",
	},
	{
		"id": &"pantograph", "actions": ["pantograph"], "group": Group.VEHICLE,
		"label": "Pantograph up / down", "signals": ["pantograph"], "families": ["train"],
		"bridge_owned": true,
		# WIDGET: built by hand in the pedal cluster beside BRAKE, where the driving hand is.
		"touch": Touch.WIDGET, "poll_key": "pantograph_toggle",
	},
	{
		"id": &"doors", "actions": ["doors"], "group": Group.VEHICLE,
		"label": "Doors", "signals": ["doors"], "families": ["train"], "bridge_owned": true,
		# WIDGET, same reason as PANTO: it sits in the pedal cluster beside LIGHTS.
		"touch": Touch.WIDGET, "poll_key": "doors_toggle",
	},
	{
		"id": &"body_cmd", "actions": ["body_cmd"], "group": Group.VEHICLE,
		"label": "Refuse body (idle / lift / dump / lower)", "signals": ["body_cmd"],
		"families": ["truck"], "capability": "body_cmd", "bridge_owned": true,
		"touch": Touch.TAP, "touch_label": "BODY", "poll_key": "body_cmd_toggle",
	},
	{
		# Not bridge_owned, unlike the two above it: the attachment CYCLE is a local authoring
		# convenience with no contract signal behind it, so sloppyCAN driving does not take it away.
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
		"id": &"respawn", "actions": ["respawn"], "group": Group.WORLD,
		"label": "Respawn", "touch": Touch.SHELL_SIGNAL, "touch_label": "RESPAWN",
	},
	{
		# On the stack, not keyboard-only: it is player-facing content (every level dresses itself
		# for night) and the Phase 7 sweep found it was the one such control a phone could not
		# reach at all. The two rows below it stay keyboard-only on purpose — they are dev keys.
		"id": &"day_night", "actions": ["day_night"], "group": Group.WORLD,
		"label": "Day / night", "touch": Touch.SHELL_SIGNAL, "touch_label": "NIGHT",
	},
	# --- the shell -----------------------------------------------------------
	{
		"id": &"garage", "actions": ["garage"], "group": Group.SHELL,
		"label": "Garage", "touch": Touch.SHELL_SIGNAL, "touch_label": "GARAGE",
	},
	{
		# Keyboard-only: the garage is the way to change vehicle on touch, so the stack does not
		# also carry a blind "next body" button.
		"id": &"next_vehicle", "actions": ["next_vehicle"], "group": Group.SHELL,
		"label": "Next vehicle body",
	},
	{
		"id": &"to_menu", "actions": ["to_menu"], "group": Group.SHELL,
		"label": "Menu / back", "touch": Touch.SHELL_SIGNAL, "touch_label": "MENU",
	},
	{
		# The same setting the SETTINGS page cycles, reached in one key: F2 drops the cluster to
		# OFF and back to whatever density you had. Keyboard-only — on touch the pause menu is
		# already one tap away and the stack is for controls you use while driving.
		"id": &"toggle_dashboard", "actions": ["toggle_dashboard"], "group": Group.SHELL,
		"label": "Dashboard on / off",
	},
	{
		"id": &"debug_overlay", "actions": ["debug_overlay"], "group": Group.SHELL,
		"label": "Debug overlay",
	},
	{
		"id": &"toggle_touch", "actions": ["toggle_touch"], "group": Group.SHELL,
		"label": "Touch controls on / off",
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


## Does this control do something right now? THE one gate predicate — the touch overlay hides
## what it says no to and the CONTROLS sheet greys it, so a button and its help can never
## disagree about whether a control exists.
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


## Why `entry` does not apply, for the sheet's third column ("" when it does apply). The bridge
## is reported first because it is the reason that is about to go away again.
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


## The families this row applies to, with the shorthand forms expanded: an empty `families` means
## every family, and `excludes` means every family but those. `all_families` is passed in so this
## file stays free of a VehicleCatalog dependency (it is data about input, not about vehicles).
##
## Not used by the runtime gate — `applies()` answers that directly. This is for the contract
## cross-check in tests/test_action_registry.gd, which is what keeps the family lists above honest.
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


## Whether every vehicle has this control. It is what splits the touch stack into its two
## columns — universal controls in the outer one, the current machine's own beside it — so a
## button's column cannot disagree with whether it is vehicle-specific.
static func is_universal(entry: Dictionary) -> bool:
	return entry.get("families", []).is_empty() \
			and entry.get("excludes", []).is_empty() \
			and String(entry.get("capability", "")) == ""


## The row's binding, READ LIVE out of InputMap — never a typed-in string, which is the drift
## that made this file necessary. One key per action, joined: a two-action row reads "W / S".
## Joypad bindings are skipped (the sheet footnotes them once for the drive group).
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
