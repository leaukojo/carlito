extends Node3D
## Dev-only flat test drive scene: flat plane + one car + chase camera.
## Not a shipped level — kept for isolated wheel checks; the gym is the dressed dev level.


@onready var _car: BaseVehicle = $Car
@onready var _camera: ChaseCamera = $ChaseCamera


func _ready() -> void:
	_car.global_transform = ($Spawn as Marker3D).global_transform
	_car.spawn_transform = _car.global_transform
	_car.reset_physics_interpolation()
	_camera.target = _car.get_camera_target()
	_car.respawned.connect(_camera.snap)
	_camera.snap.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn"):
		_car.respawn()
