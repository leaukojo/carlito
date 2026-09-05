extends Node
## GameState autoload: current level/vehicle bookkeeping. The shell composes independent
## level/vehicle/UI scenes at runtime; this only tracks what's currently active.

## Transient player message. Lets sim refuse something and say why without a HUD reference.
## dwell_s <= 0 means shell default; longer for actionable notices (ignition-key).
@warning_ignore("UNUSED_SIGNAL")  # emitted from InputRouter, not from this class
signal notice(text: String, dwell_s: float)

## Takes a notice down before its dwell expires, once the condition it described is fixed.
## Raised with the exact text shown, so a stale caller can't clear someone else's message.
@warning_ignore("UNUSED_SIGNAL")  # emitted from InputRouter, not from this class
signal notice_cleared(text: String)

## The active vehicle's attachment changed without anyone pressing E (a coupling that didn't
## fit, taken away again). Lets the shell re-ask capabilities so the touch overlay's PTO/TIP
## buttons follow the real attachment. The press path refreshes itself in boot.gd; this
## covers only sim-driven changes.
@warning_ignore("UNUSED_SIGNAL")  # emitted from TowHost, not from this class
signal attachment_changed()

## Active level's day/night state, raised by Level on flip (and once on authored-lighting
## capture), so the touch overlay's button caption follows the N key and level changes too.
@warning_ignore("UNUSED_SIGNAL")  # emitted from Level, not from this class
signal night_changed(is_night: bool)

var current_level := ""    ## res:// path of the loaded level scene ("" = none)
var current_vehicle := ""  ## vehicle FAMILY id, e.g. "car" (matches contract 'vehicles' tags)
var current_variant := ""  ## active variant id within the family (VehicleCatalog), e.g. "sedan"
