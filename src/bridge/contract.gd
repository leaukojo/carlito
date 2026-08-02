extends Node
## Contract autoload — loads and validates the shared signal contract at startup.
##
## The contract (contract/carlito_contract.json) is the single definition of every
## signal crossing the sloppyCAN bridge. The bridge marshals messages from
## it and the dashboard builds its tell-tales/gauges from it; code must never
## hand-duplicate signal names.
##
## All parsing/validation logic lives in the static inner classes so unit tests can
## exercise it without the autoload lifecycle. Consumers read `Contract.data`.

const CONTRACT_PATH := "res://contract/carlito_contract.json"

const DIRS: PackedStringArray = ["in", "out"]
const TYPES: PackedStringArray = ["bool", "u8", "i8", "u16", "i16", "u32", "i32", "f32", "f64"]


## One validated signal definition.
class SignalDef:
	var name := ""
	var dir := ""                      ## "in" (sloppyCAN -> game) or "out" (game -> sloppyCAN)
	var type := ""                     ## one of Contract.TYPES
	var unit := ""
	@warning_ignore("shadowed_global_identifier")
	var range := []                    ## [] or [min: float, max: float]
	var warn := NAN                    ## optional danger threshold the dashboard highlights; NAN = none
	var enum_entries := []             ## Array of [lo: int, hi: int, label: String, interp_prefix]
									   ## interp_prefix: String when a "D1-D6"-style range label
									   ## interpolates ("D" + value), null otherwise (resolved at parse)
	var vehicles: PackedStringArray = []
	var flavor := ""                   ## e.g. "isobus"
	var todo := false                  ## declared but not implemented on either side yet
	var desc := ""

	func has_enum() -> bool:
		return not enum_entries.is_empty()

	func has_warn() -> bool:
		return not is_nan(warn)

	## True when 'warn' marks a low-side danger (near range min, e.g. low fuel) vs a
	## high-side one (near range max, e.g. redline / overheat). Meaningless without
	## both a range and a warn; guard with has_warn().
	func warn_is_low() -> bool:
		if range.size() != 2:
			return false
		return warn < (float(range[0]) + float(range[1])) * 0.5

	## Decode a raw value against the enum table ("" when unmapped).
	## Range entries with a "D1-D6"-style label interpolate the index
	## (e.g. "1-6": "D1-D6" decodes 3 -> "D3"); other labels return as-is.
	func enum_label(value: int) -> String:
		for entry: Array in enum_entries:
			if value < entry[0] or value > entry[1]:
				continue
			if entry[3] != null:
				return str(entry[3]) + str(value)
			return entry[2]
		return ""


## The parsed contract. Build via ContractData.parse(); check is_valid() before use.
class ContractData:
	var version := 0
	var signals: Array[SignalDef] = []
	var errors: PackedStringArray = []

	func is_valid() -> bool:
		return errors.is_empty()

	func get_signal_def(name: String, dir: String) -> SignalDef:
		for s in signals:
			if s.name == name and s.dir == dir:
				return s
		return null

	func has_signal_def(name: String, dir: String) -> bool:
		return get_signal_def(name, dir) != null

	func signals_in() -> Array[SignalDef]:
		var out: Array[SignalDef] = []
		out.assign(signals.filter(func(s: SignalDef) -> bool: return s.dir == "in"))
		return out

	func signals_out() -> Array[SignalDef]:
		var out: Array[SignalDef] = []
		out.assign(signals.filter(func(s: SignalDef) -> bool: return s.dir == "out"))
		return out

	func signals_for_vehicle(vehicle: String, dir: String) -> Array[SignalDef]:
		var out: Array[SignalDef] = []
		out.assign(signals.filter(func(s: SignalDef) -> bool:
			return s.dir == dir and vehicle in s.vehicles))
		return out

	func is_todo(name: String, dir: String) -> bool:
		var s := get_signal_def(name, dir)
		return s != null and s.todo

	## Parse + validate contract JSON text. Never throws; collects every problem
	## into .errors so a broken contract reports all its faults at once.
	static func parse(json_text: String) -> ContractData:
		var data := ContractData.new()
		var json := JSON.new()
		if json.parse(json_text) != OK:
			data.errors.append("invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
			return data
		var root: Variant = json.data
		if typeof(root) != TYPE_DICTIONARY:
			data.errors.append("contract root must be an object")
			return data

		var version_v: Variant = root.get("version")
		if typeof(version_v) != TYPE_FLOAT or version_v != floorf(version_v) or version_v < 1:
			data.errors.append("'version' must be a positive integer")
		else:
			data.version = int(version_v)

		var signals_v: Variant = root.get("signals")
		if typeof(signals_v) != TYPE_ARRAY:
			data.errors.append("'signals' must be an array")
			return data

		var seen := {}
		for i in (signals_v as Array).size():
			var entry: Variant = signals_v[i]
			if typeof(entry) != TYPE_DICTIONARY:
				data.errors.append("signals[%d]: must be an object" % i)
				continue
			var sig := _parse_signal(entry, i, data.errors)
			if sig == null:
				continue
			var key := sig.name + "/" + sig.dir
			if seen.has(key):
				data.errors.append("signals[%d]: duplicate signal '%s' dir '%s'" % [i, sig.name, sig.dir])
				continue
			seen[key] = true
			data.signals.append(sig)
		return data

	## Returns null (after appending errors) when the entry is unusable;
	## a SignalDef otherwise.
	@warning_ignore("shadowed_variable")
	static func _parse_signal(entry: Dictionary, index: int, errors: PackedStringArray) -> SignalDef:
		var sig := SignalDef.new()
		var where := "signals[%d]" % index

		var name_v: Variant = entry.get("name")
		if typeof(name_v) != TYPE_STRING or (name_v as String).is_empty():
			errors.append("%s: 'name' must be a non-empty string" % where)
			return null
		sig.name = name_v
		where = "signal '%s'" % sig.name

		var dir_v: Variant = entry.get("dir")
		if typeof(dir_v) != TYPE_STRING or dir_v not in DIRS:
			errors.append("%s: 'dir' must be one of %s" % [where, DIRS])
			return null
		sig.dir = dir_v
		where = "signal '%s' (%s)" % [sig.name, sig.dir]

		var type_v: Variant = entry.get("type")
		if typeof(type_v) != TYPE_STRING or type_v not in TYPES:
			errors.append("%s: 'type' must be one of %s" % [where, TYPES])
			return null
		sig.type = type_v

		sig.unit = str(entry.get("unit", ""))
		sig.flavor = str(entry.get("flavor", ""))
		sig.desc = str(entry.get("desc", ""))
		sig.todo = entry.get("status", "") == "todo"

		var range_v: Variant = entry.get("range")
		if range_v != null:
			if typeof(range_v) != TYPE_ARRAY or (range_v as Array).size() != 2 \
					or typeof(range_v[0]) != TYPE_FLOAT or typeof(range_v[1]) != TYPE_FLOAT \
					or float(range_v[0]) > float(range_v[1]):
				errors.append("%s: 'range' must be [min, max] with min <= max" % where)
				return null
			sig.range = [float(range_v[0]), float(range_v[1])]

		var warn_v: Variant = entry.get("warn")
		if warn_v != null:
			if typeof(warn_v) != TYPE_FLOAT:
				errors.append("%s: 'warn' must be a number" % where)
				return null
			sig.warn = float(warn_v)

		var vehicles_v: Variant = entry.get("vehicles")
		if vehicles_v != null:
			if typeof(vehicles_v) != TYPE_ARRAY:
				errors.append("%s: 'vehicles' must be an array of strings" % where)
				return null
			for v: Variant in vehicles_v:
				if typeof(v) != TYPE_STRING:
					errors.append("%s: 'vehicles' must be an array of strings" % where)
					return null
				sig.vehicles.append(v)

		var enum_v: Variant = entry.get("enum")
		if enum_v != null:
			if typeof(enum_v) != TYPE_DICTIONARY:
				errors.append("%s: 'enum' must be an object" % where)
				return null
			var key_re := RegEx.create_from_string("^(\\d+)(?:-(\\d+))?$")
			var label_re := RegEx.create_from_string("^(\\D*)(\\d+)-(\\D*)(\\d+)$")
			for key: Variant in (enum_v as Dictionary):
				var m := key_re.search(str(key))
				if m == null or typeof(enum_v[key]) != TYPE_STRING:
					errors.append("%s: enum key '%s' must be 'N' or 'N-M' mapping to a string" % [where, key])
					return null
				var lo := int(m.get_string(1))
				var hi := int(m.get_string(2)) if not m.get_string(2).is_empty() else lo
				if hi < lo:
					errors.append("%s: enum key '%s' has max < min" % [where, key])
					return null
				var label: String = enum_v[key]
				# A range key with a "D1-D6"-style label decodes by interpolating
				# the value into the shared prefix; resolve that here, once.
				var interp_prefix: Variant = null
				if hi > lo:
					var lm := label_re.search(label)
					if lm and lm.get_string(1) == lm.get_string(3) \
							and int(lm.get_string(2)) == lo and int(lm.get_string(4)) == hi:
						interp_prefix = lm.get_string(1)
				sig.enum_entries.append([lo, hi, label, interp_prefix])
		return sig


var data: ContractData = null


func _ready() -> void:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	if file == null:
		push_error("Contract: cannot open %s (%s)" % [CONTRACT_PATH, error_string(FileAccess.get_open_error())])
		data = ContractData.new()
		data.errors.append("contract file missing")
		return
	data = ContractData.parse(file.get_as_text())
	for err in data.errors:
		push_error("Contract: %s" % err)
	if data.is_valid():
		print("Contract: loaded v%d, %d signals (%d in / %d out)" % [
			data.version, data.signals.size(), data.signals_in().size(), data.signals_out().size()])
