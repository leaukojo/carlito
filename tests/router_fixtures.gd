extends RefCounted
## A router polls every connected joypad (PadSource), so one built bare reads whatever controller
## sits on the machine running the suite. Every suite that builds an InputRouter builds it here.

const RouterScript := preload("res://src/input/input_router.gd")
const PadSourceScript := preload("res://src/input/sources/pad_source.gd")


## A pad at rest.
class IdlePad extends PadSourceScript:
	func poll() -> Dictionary[StringName, Variant]:
		return {}


## A router on an idle pad, not freed: the suite wraps it in `auto_free`.
static func idle_router() -> Node:
	var router: Node = RouterScript.new()
	router._pad_source = IdlePad.new()
	return router
