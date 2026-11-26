extends RefCounted
## `measure_vehicles`' arm pass (`arm`, instead of every other pass): the tool spawns each body
## and hands it here (`start`, then `tick` every physics tick).

const MeasureRig := preload("res://tools/measure_rig.gd")

## The refuse body's arm cycle, parked: in N on the handbrake with the PTO in, ARM_SETTLE_S idle, then
## LIFT to the top and LOWER to the stow, each to ARM_TIMEOUT_S. A line every ARM_LINE_S: the arm's
## `body_pos`, rpm against the PTO mode's set speed (`VehicleSpec.pto_mode_rpm`), `engine_load` and
## the delivered fuel; per stroke its time and its mean and least rpm.
const ARM_SETTLE_S := 3.0
const ARM_LINE_S := 0.5
const ARM_TIMEOUT_S := 15.0

var _restart: Callable                ## the tool's pass reset
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _current := {}                    ## the tool's report entry for this body
var _t := 0.0                         ## s into the stage
var _arm_stage := 0                   ## 0 settling, 1 lifting, 2 lowering
var _arm_line_t := 0.0
var _arm_sums := Vector3.ZERO         ## rpm summed, ticks, least rpm over the stroke


func _init(restart: Callable, finish: Callable) -> void:
	_restart = restart
	_finish = finish


## The arm cycle on `car`: parked in N on the handbrake, the PTO in, in the bridge's manual box.
func start(car: BaseVehicle, _title: String, current: Dictionary) -> void:
	_car = car
	_current = current
	_restart.call()
	_t = 0.0
	if not _car is TruckVehicle or not bool(_car.vehicle_capabilities().get("body_cmd", false)):
		print("=== %s: no refuse body, arm skipped ===" % String(_current["variant"]))
		_finish.call()
		return
	InputRouter.set_manual_gearbox(true)
	print("=== %s, arm cycle, parked in N, handbrake and PTO on: PTO mode set speed %.0f rpm ===" % [
			String(_current["variant"]), _car.spec.pto_mode_rpm])
	_arm_stage = 0
	_arm_drive(RefuseBody.Cmd.IDLE)


func _arm_drive(cmd: int) -> void:
	MeasureRig.drive(0.0, 0.0, 0.0, true, 0, false, 3, {"pto": true, "body_cmd": cmd})
	_t = 0.0
	_arm_line_t = 0.0
	_arm_sums = Vector3(0.0, 0.0, INF)


## One physics tick.
func tick(delta: float, _host_t: float) -> void:
	_t += delta
	var tel := _car.telemetry as TruckTelemetry
	var dt: Drivetrain = _car.drivetrain
	_arm_sums += Vector3(dt.rpm, 1.0, 0.0)
	_arm_sums.z = minf(_arm_sums.z, dt.rpm)
	if _t >= _arm_line_t:
		_arm_line_t += ARM_LINE_S
		print("  %-7s %5.2f s: body_pos %3d %%, %4.0f rpm, engine_load %3d %%, fuel %.3f" % [
				["settle", "lift", "lower"][_arm_stage], _t, tel.body_pos, dt.rpm, tel.engine_load,
				dt.applied_throttle])
	var done := false
	match _arm_stage:
		0:
			done = _t >= ARM_SETTLE_S
		1:
			done = tel.body_pos >= 100 or _t >= ARM_TIMEOUT_S
		2:
			done = tel.body_pos <= 0 or _t >= ARM_TIMEOUT_S
	if not done:
		return
	print("  %s: %.2f s, rpm mean %.0f, least %.0f%s" % [["settle", "lift", "lower"][_arm_stage], _t,
			_arm_sums.x / maxf(_arm_sums.y, 1.0), _arm_sums.z,
			" (TIMEOUT)" if _arm_stage > 0 and _t >= ARM_TIMEOUT_S else ""])
	_arm_stage += 1
	if _arm_stage == 1:
		_arm_drive(RefuseBody.Cmd.LIFT)
	elif _arm_stage == 2:
		_arm_drive(RefuseBody.Cmd.LOWER)
	else:
		MeasureRig.drive(0.0, 0.0)
		InputRouter.set_manual_gearbox(false)
		_finish.call()
