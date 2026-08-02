extends Node
## Bridge autoload — CAN bridge to sloppyCAN.
##
## Web-only postMessage transport. The export head-include (src/bridge/web/head_include.html)
## installs `window.__carlito`: it stashes inbound {type:'carlitoInput'} values with a timestamp
## and exposes publish() for outbound {type:'carlitoOutput'}. This autoload:
##   - polls the inbound stash each physics tick (~60 Hz), freshness-gated at 300 ms, and exposes
##     is_active()/get_input_values() to the bridge InputSource;
##   - publishes telemetry outward at ~20 Hz, marshaling values by contract name from the bound
##     vehicle's VehicleTelemetry.to_bridge_dict() — never a hand-written field list.
## On desktop OS.has_feature("web") is false: the bridge stays inactive and never touches JS.

const FRESHNESS_MS := 300           ## stale inbound past this is ignored → local input owns
const PUBLISH_HZ := 20
const PUBLISH_INTERVAL := 1.0 / PUBLISH_HZ

var _web := false
var _active := false                ## fresh bridge data arrived within FRESHNESS_MS at last poll
var _inbound := {}                  ## last fresh inbound values, keyed by contract "in" name
var _inbound_version := 0           ## contract version stamped by the peer (0 = none sent)
var _publish_accum := 0.0
var _level: Node = null             ## telemetry provider (the active Level), set via bind()
var _version_warned := false
var _missing_warned := {}           ## out-signal names already warned as absent from telemetry


func _ready() -> void:
	_web = OS.has_feature("web")
	if _web:
		var version := Contract.data.version if Contract.data != null else 0
		JavaScriptBridge.eval("if(window.__carlito)window.__carlito.outVer=%d;" % version, true)


func _physics_process(delta: float) -> void:
	# Autoloads tick in declaration order (Contract, Bridge, InputRouter), so polling here
	# lands the fresh values before InputRouter reads them the same frame.
	_poll_inbound()
	if not _web:
		return
	_publish_accum += delta
	if _publish_accum >= PUBLISH_INTERVAL:
		_publish_accum -= PUBLISH_INTERVAL
		_publish()


## Whether fresh bridge data is currently arriving. Drives UI decisions (e.g. hiding the
## manual lights button while sloppyCAN owns the lamps) and the input arbitration seam.
func is_active() -> bool:
	return _active


## Last fresh inbound values keyed by contract "in" name ({} when inactive).
func get_input_values() -> Dictionary:
	return _inbound if _active else {}


## Register the active Level as the telemetry source (mirrors Dashboard.bind); publish reads
## _level.vehicle.telemetry each tick so it survives respawn / vehicle swap.
func bind(level: Node) -> void:
	_level = level


func _poll_inbound() -> void:
	if not _web:
		return
	# The freshness gate runs in JS in one shot: return the stash only while fresh, else "".
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
	if _level == null:
		return
	var vehicle: Node = _level.get("vehicle")
	if vehicle == null:
		return
	var tel: VehicleTelemetry = vehicle.get("telemetry")
	if tel == null:
		return
	var dict: Dictionary = tel.to_bridge_dict()
	var values := {}
	# Publish only the signals the active vehicle actually declares: a car emits
	# car signals, a tractor adds its ISOBUS ones. Walking all signals_out() would (now that
	# the tractor signals are no longer todo) warn on a car for the missing hitch/PTO values.
	for sig in Contract.data.signals_for_vehicle(GameState.current_vehicle, "out"):
		if sig.todo:
			continue
		if not dict.has(sig.name):
			if not _missing_warned.has(sig.name):
				_missing_warned[sig.name] = true
				push_warning("Bridge: out signal '%s' has no telemetry value" % sig.name)
			continue
		values[sig.name] = dict[sig.name]
	# JSON is valid JS object-literal syntax and every out value is numeric/bool, so it
	# embeds directly into the publish() call with no escaping.
	JavaScriptBridge.eval("if(window.__carlito&&window.__carlito.publish)window.__carlito.publish(%s);" % JSON.stringify(values), true)
