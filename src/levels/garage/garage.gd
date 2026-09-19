extends Level
## Garage showroom: spawned vehicle is kinematic-frozen and hovers so the orbit camera can
## inspect it from any angle; _physics_process still runs (wheels steer, lamps toggle).

@onready var _title: Label3D = $Screen/Title
@onready var _keys_left: Label3D = $Screen/KeysLeft
@onready var _values_left: Label3D = $Screen/ValuesLeft
@onready var _keys_right: Label3D = $Screen/KeysRight
@onready var _values_right: Label3D = $Screen/ValuesRight


func _ready() -> void:
	# Connect before super._ready() so the load-time spawn's vehicle_changed is handled.
	vehicle_changed.connect(_on_vehicle_changed)
	super._ready()


## Runs on every (re)spawn/swap: pins the body and refreshes the wall stats. Duck-typed
## (set_display_frozen) so e.g. a semi's trailer gets pinned too without this file knowing what a trailer is.
func _on_vehicle_changed(_family: String) -> void:
	if vehicle == null:
		return
	vehicle.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	vehicle.freeze = true
	if vehicle.has_method("set_display_frozen"):
		vehicle.set_display_frozen(true)
	_refresh_stats()


## Centred name headline, then two stat columns. Each column is a dim key label beside a
## bright value label rather than one "Key: value" block — the columns line up whatever the
## key lengths are, and the value reads first.
func _refresh_stats() -> void:
	var spec: VehicleSpec = vehicle.spec
	_title.text = GameState.current_variant
	if spec == null:
		_set_column(_keys_left, _values_left, [["", "No spec"]])
		_set_column(_keys_right, _values_right, [])
		return
	var left: Array = [
		["Family", GameState.current_vehicle],
		["Mass", "%d kg" % roundi(spec.mass)],
		["Drive", _drive_text(spec)],
	]
	var right: Array = []
	# has_engine gates engine figures (the gearbox runs on every family, but a quadcopter has no crank).
	if spec.has_engine:
		left.append(["Gears", "%d" % spec.gear_ratios.size()])
		right.append(["Redline", "%d rpm" % roundi(spec.redline_rpm)])
		right.append(["Peak torque", "%d Nm" % roundi(Drivetrain.peak_torque(spec))])
	# Steering lock and foot brake are ground-drive figures; a boat/drone/train gets no line rather than 0 Nm/0 deg.
	if spec.ground_drive != null:
		right.append(["Max steer", "%.0f deg" % spec.ground_drive.max_steer_deg])
		right.append(["Brake", "%d Nm" % roundi(spec.ground_drive.brake_torque)])
	_set_column(_keys_left, _values_left, left)
	_set_column(_keys_right, _values_right, right)


## Writes one column's [key, value] rows into its two labels, keeping the line counts equal
## so row N of the key label sits beside row N of the value label.
func _set_column(keys: Label3D, values: Label3D, rows: Array) -> void:
	var k := PackedStringArray()
	var v := PackedStringArray()
	for row: Array in rows:
		k.append(row[0])
		v.append(row[1])
	keys.text = "\n".join(k)
	values.text = "\n".join(v)


func _drive_text(spec: VehicleSpec) -> String:
	var gd := spec.ground_drive
	if gd == null:
		return "none"
	if gd.driven_front and gd.driven_rear:
		return "AWD"
	if gd.driven_front:
		return "FWD"
	if gd.driven_rear:
		# The tractor's front axle engages at runtime; plain RWD would hide half the driveline.
		return "RWD/MFWD" if gd.front_axle_engageable else "RWD"
	return "none"
