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
var _nonfinite_warned := {}         ## out-signal names already warned as a non-finite value
## A challenge attempt is running. Rides the carlitoOutput ENVELOPE, not the contract: it is no
## CAN value, and sloppyCAN turns its RAMN demo traffic off on the rising edge so hand-sent frames
## are not overwritten.
var _challenge := false


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


## Set by the shell on entering / leaving a challenge attempt.
func set_challenge(on: bool) -> void:
	_challenge = on


## Register Level's telemetry source. Resolved once per vehicle change, not per publish.
func bind(level: Node) -> void:
	_telem = null
	# A new vehicle family's telemetry starts with a clean warning slate: a signal that was
	# missing/wrong-shaped on the last family must not silence the same bug on this one.
	_missing_warned.clear()
	_shape_warned.clear()
	_nonfinite_warned.clear()
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
	_inbound = parsed.get("d", {})
	# Agrees with bridge_source.poll(), which reports inactive on an empty value dict.
	_active = not _inbound.is_empty()
	_inbound_version = int(parsed.get("v", 0))
	if _inbound_version != 0 and _inbound_version != Contract.data.version and not _version_warned:
		_version_warned = true
		push_warning("Bridge: contract version mismatch — sloppyCAN v%d vs game v%d" % [
			_inbound_version, Contract.data.version])
		GameState.notice.emit("SLOPPYCAN CONTRACT VERSION MISMATCH", 0.0)


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
		if not _all_finite(value):
			_warn_nonfinite(sig.name)
			continue
		values[sig.name] = value
	# JSON valid in JS object-literal syntax, embeds directly to publish() with no escaping.
	JavaScriptBridge.eval("if(window.__carlito&&window.__carlito.publish)window.__carlito.publish(%s,%s);" % [
		JSON.stringify(values), "true" if _challenge else "false"], true)


func _warn_shape(sig_name: String, expected: String, got: Variant) -> void:
	if _shape_warned.has(sig_name):
		return
	_shape_warned[sig_name] = true
	push_warning("Bridge: out signal '%s' must be %s, got %s" % [sig_name, expected, got])


func _warn_nonfinite(sig_name: String) -> void:
	if _nonfinite_warned.has(sig_name):
		return
	_nonfinite_warned[sig_name] = true
	push_warning("Bridge: out signal '%s' has a non-finite value, skipped" % sig_name)


## Whether `value` (a scalar or an Array, per the shape check above) is safe to
## JSON.stringify into the JavaScriptBridge.eval string — a non-finite float serialises as
## bare `nan`/`inf`, which is not valid JS and throws inside eval, killing every publish.
static func _all_finite(value: Variant) -> bool:
	if typeof(value) == TYPE_ARRAY:
		for v: Variant in (value as Array):
			if typeof(v) == TYPE_FLOAT and not is_finite(v):
				return false
		return true
	return not (typeof(value) == TYPE_FLOAT and not is_finite(value))


## An instanced signal's value: an Array of exactly `count` numbers.
static func _is_instance_array(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return false
	for v: Variant in (value as Array):
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
	return true
