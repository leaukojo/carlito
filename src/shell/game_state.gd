extends Node
## GameState autoload — current level/vehicle bookkeeping (stub until the shell lands).
##
## Plan §4.6: the shell composes independent level/vehicle/UI scenes at runtime;
## this autoload only tracks what is currently active.

## A transient message for the player, raised by the sim and shown by the shell — "no room to
## couple", and nothing else today. A SIGNAL rather than a state field because it is an event: the
## shell shows it for a few seconds and forgets it.
##
## It exists so a vehicle can REFUSE something and say why without learning that a HUD exists. The
## alternative was a return value on the duck-typed `cycle_implement()` hook, which is deliberately
## an unconditional `-> void` (see the E/V split note in src/vehicles/CLAUDE.md), or a direct
## reference from the vehicle to the shell — which is the dependency the shell's whole composition
## rule exists to avoid.
## `dwell_s` <= 0 means "use the shell's default dwell"; a longer value is for a notice the driver
## may need to act on rather than just read (the ignition-key notice).
signal notice(text: String, dwell_s: float)

## Take a notice down before its dwell expires, when the condition it described is fixed. Raised
## with the exact text that was shown, so a stale caller cannot clear someone else's message: the
## ignition notice dwells 20 s precisely because the driver has to go act on it, and a message
## still on screen after the key IS at Ignition reads as a broken game.
signal notice_cleared(text: String)

## What is hanging off the back of the active vehicle has changed WITHOUT anyone pressing E — a
## fresh coupling that turned out not to fit and was taken away again. The shell re-asks the
## vehicle for its capabilities so the touch overlay's PTO/TIP buttons follow the real attachment;
## without it the buttons keep offering a trailer the rig no longer has. The press path refreshes
## itself in boot.gd, so this is only for the changes the sim makes on its own.
signal attachment_changed()

## The active level's day/night state, raised by Level whenever it flips (and once when a level
## captures its authored lighting). It exists so the touch overlay's button can say what the press
## will DO — the caption has to follow the N key and a level change too, not just its own taps, and
## the level still learns nothing about the HUD.
signal night_changed(is_night: bool)

var current_level := ""    ## res:// path of the loaded level scene ("" = none)
var current_vehicle := ""  ## vehicle FAMILY id, e.g. "car" (matches contract 'vehicles' tags)
var current_variant := ""  ## active variant id within the family (VehicleCatalog), e.g. "sedan"
