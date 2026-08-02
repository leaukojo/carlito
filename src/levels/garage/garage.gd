extends Level
## Garage showroom. The spawned vehicle is physics-frozen and hovers above the floor so
## the orbit camera can inspect it from any angle, including underneath. Freezing is
## KINEMATIC, so _physics_process still runs — wheels steer/spin, the engine revs, lamps
## toggle — the body just never moves. A wall screen shows the active vehicle's spec.
## Input, lamps, dashboard and bridge all flow through Level unchanged.

@onready var _title: Label3D = $Screen/Title
@onready var _stats_left: Label3D = $Screen/StatsLeft
@onready var _stats_right: Label3D = $Screen/StatsRight


func _ready() -> void:
	# Connect before super._ready() so the load-time spawn's vehicle_changed is handled.
	vehicle_changed.connect(_on_vehicle_changed)
	super._ready()


## Runs on every (re)spawn/swap: pin the new body in place and refresh the wall stats.
##
## A vehicle that owns OTHER bodies has to pin those too, and it is asked to rather than reached
## into — the same duck-type the shell uses for `cycle_implement`, so this file never learns what a
## trailer is. Without it the semi's trailer is the one thing in the room still obeying gravity: a
## separate 24 t RigidBody3D hanging off the fifth wheel with no floor under its wheels, swinging on
## the joint until it settles.
func _on_vehicle_changed(_family: String) -> void:
	if vehicle == null:
		return
	vehicle.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	vehicle.freeze = true
	if vehicle.has_method("set_display_frozen"):
		vehicle.set_display_frozen(true)
	_refresh_stats()


## Centred name headline, then two equal-length stat columns under it. The name gets its own
## line because variant names are long enough to reach the second column when inlined.
func _refresh_stats() -> void:
	var spec: VehicleSpec = vehicle.spec
	_title.text = _game_state().current_variant
	if spec == null:
		_stats_left.text = "No spec"
		_stats_right.text = ""
		return
	_stats_left.text = "\n".join([
		"Family: %s" % _game_state().current_vehicle,
		"Mass: %d kg" % roundi(spec.mass),
		"Drive: %s" % _drive_text(spec),
		"Gears: %d" % spec.gear_ratios.size(),
	])
	_stats_right.text = "\n".join([
		"Redline: %d rpm" % roundi(spec.redline_rpm),
		"Peak torque: %d Nm" % roundi(Drivetrain.peak_torque(spec)),
		"Max steer: %.0f deg" % spec.max_steer_deg,
		"Brake: %d Nm" % roundi(spec.brake_torque),
	])


func _drive_text(spec: VehicleSpec) -> String:
	if spec.driven_front and spec.driven_rear:
		return "AWD"
	if spec.driven_front:
		return "FWD"
	if spec.driven_rear:
		# The tractor spawns rear-drive but its front axle engages at runtime, so calling it
		# plain RWD would hide half the driveline.
		return "RWD/MFWD" if spec.front_axle_engageable else "RWD"
	return "none"
