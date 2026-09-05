class_name AttachmentCatalog
extends RefCounted
## The shape every attachment registry the E cycle walks has in common (TrailerCatalog,
## ImplementCatalog): an ordered list of scene ids that ends on an empty-string sentinel, plus the
## three questions the cycle asks of it. The list itself and the reasoning for its ORDER stay with
## the family's own catalog — only the structure is shared, so nothing here learns that trailers or
## implements exist.

const NONE := ""  ## detached / bobtail: a real cycle entry, never a special case


## What the vehicle spawns carrying. The first entry is never NONE, so a machine drives with its
## attachment signals doing something from frame one.
static func first(ids: PackedStringArray) -> String:
	return ids[0]


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(ids: PackedStringArray, current: String) -> String:
	var i := ids.find(current)
	return ids[(i + 1) % ids.size()] if i >= 0 else ids[0]


## True when `id` names an actual machine (as opposed to the detached state).
static func is_attached(id: String) -> bool:
	return id != NONE
