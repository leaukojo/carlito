extends Node
## Bridge autoload — CAN bridge to sloppyCAN.
##
## Web-only postMessage transport. The export head-include installs `window.__carlito`,
## stashing inbound values with a timestamp and exposing publish() for outbound. This
## autoload polls the inbound stash each physics tick (freshness-gated at 300 ms) and
## publishes telemetry at ~20 Hz, marshaling by contract name — never a hand-written field
## list. On desktop OS.has_feature("web") is false: bridge stays inactive, never touches JS.

const FRESHNESS_MS := 300           ## stale inbound past this is ignored → local input owns
const PUBLISH_HZ := 20
const PUBLISH_INTERVAL := 1.0 / PUBLISH_HZ

var _web := false
var _active := false                ## fresh bridge data arrived within FRESHNESS_MS at last poll
var _inbound := {}                  ## last fresh inbound values, keyed by contract "in" name
var _inbound_version := 0           ## contract version stamped by the peer (0 = none sent)
var _publish_accum := 0.0
var _telem: VehicleTelemetry = null ## that level's active vehicle telemetry, resolved at bind
var _version_warned := false
var _missing_warned := {}           ## out-signal names already warned as absent from telemetry
var _shape_warned := {}             ## out-signal names already warned as the wrong VALUE SHAPE


func _ready() -> void:
	_web = OS.has_feature("web")
	if _web:
		var version := Contract.data.version if Contract.data != null else 0
		JavaScriptBridge.eval("if(window.__carlito)window.__carlito.outVer=%d;" % version, true)


func _physics_process(delta: float) -> void:
	# Poll before InputRouter reads them same frame (autoload tick order).
	_poll_inbound()
	if not _web:
		return
	_publish_accum += delta
	if _publish_accum >= PUBLISH_INTERVAL:
		_publish_accum -= PUBLISH_INTERVAL
		_publish()


## Whether fresh bridge data is currently arriving. Drives UI and input arbitration.
func is_active() -> bool:
	return _active


## Last fresh inbound values keyed by contract "in" name ({} when inactive).
func get_input_values() -> Dictionary:
	return _inbound if _active else {}


## Register Level's telemetry source. Resolved once per vehicle change, not per publish.
func bind(level: Node) -> void:
	_telem = null
	if level != null:
		var vehicle: Node = level.get("vehicle")
		if vehicle != null:
			_telem = vehicle.get("telemetry")


func _poll_inbound() -> void:
	if not _web:
		return
	# Freshness gate in JS: stash only while fresh, else "".
	var code := "(function(){var c=window.__carlito;return (c && Date.now()-c.inT < %d) ? JSON.stringify({v:c.ver,d:c.in}) : '';})();" % FRESHNESS_MS
	var raw: Variant = JavaScriptBridge.eval(code, true)
	if typeof(raw) != TYPE_STRING or (raw as String).is_empty():
		_active = false
		_inbound = {}
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_active = false
		_inbound = {}
		return
	_active = true
	_inbound = parsed.get("d", {})
	_inbound_version = int(parsed.get("v", 0))
	if _inbound_version != 0 and _inbound_version != Contract.data.version and not _version_warned:
		_version_warned = true
		push_warning("Bridge: contract version mismatch — sloppyCAN v%d vs game v%d" % [
			_inbound_version, Contract.data.version])


func _publish() -> void:
	if _telem == null:
		return
	var dict: Dictionary = _telem.to_bridge_dict()
	var values := {}
	# Only signals the active vehicle declares (avoid false warnings for missing PTO on cars).
	for sig in Contract.data.signals_for_vehicle(GameState.current_vehicle, "out"):
		if sig.todo:
			continue
		if not dict.has(sig.name):
			if not _missing_warned.has(sig.name):
				_missing_warned[sig.name] = true
				push_warning("Bridge: out signal '%s' has no telemetry value" % sig.name)
			continue
		var value: Variant = dict[sig.name]
		# Shape must match contract: instanced → Array of count, scalar → not Array.
		if sig.is_instanced():
			if not _is_instance_array(value, sig.count):
				_warn_shape(sig.name, "an Array of %d numbers" % sig.count, value)
				continue
		elif typeof(value) == TYPE_ARRAY:
			_warn_shape(sig.name, "a scalar (contract declares no 'count')", value)
			continue
		values[sig.name] = value
	# JSON valid in JS object-literal syntax, embeds directly to publish() with no escaping.
	JavaScriptBridge.eval("if(window.__carlito&&window.__carlito.publish)window.__carlito.publish(%s);" % JSON.stringify(values), true)


func _warn_shape(sig_name: String, expected: String, got: Variant) -> void:
	if _shape_warned.has(sig_name):
		return
	_shape_warned[sig_name] = true
	push_warning("Bridge: out signal '%s' must be %s, got %s" % [sig_name, expected, got])


## An instanced signal's value: an Array of exactly `count` numbers.
static func _is_instance_array(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return false
	for v: Variant in (value as Array):
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
	return true
