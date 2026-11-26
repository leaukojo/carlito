extends RefCounted
## `measure_vehicles`' scrape pass (`scrape`, instead of every other pass): the tool spawns each body
## and hands it here (`start`, then `tick` every physics tick).
## The body driven along a wall: spawned SCRAPE_DEG off the strip's line toward a SCRAPE_HIGH wall
## on its right, the wall's face SCRAPE_GAP out from its widest tyre, held at SCRAPE_SPEED with the
## wheel straight for SCRAPE_S; `steer=<pct>` holds the wheel there from SCRAPE_STEER_S on, the body
## by then along the wall. `onebody` makes the wall a shape of the strip's body (a parapet
## welded to its deck). Per wheel (a coupled towed body's too, `T<n>`): how far its cylinder
## reached past the wall's face (at full bump, so to within the body's roll), the share of ticks in
## contact, and the ticks its contact was one the spring cannot carry (`RayWheel.carries`). Per
## body: the speed it ends at, the peak acceleration across it and yaw rate, the peak tilt. `trace`
## prints the ticks. A hull resting on a welded wall sits up to Jolt's `penetration_slop` inside it
## (its 0.02 m default, kept as the margin that holds a resting contact still); a box wall reads 0.

const MeasureRig := preload("res://tools/measure_rig.gd")
const Kerb := preload("res://tools/measure_vehicles_kerb.gd")

const SCRAPE_DEG := 5.0
const SCRAPE_SPEED := 5.0          ## m/s
const SCRAPE_S := 10.0
const SCRAPE_STEER_S := 6.0
const SCRAPE_GAP := 1.0            ## m
const SCRAPE_HIGH := 2.0           ## m
const SCRAPE_LONG := 120.0         ## m of wall, from SCRAPE_BEHIND behind the spawn
const SCRAPE_BEHIND := 20.0        ## m

var _tool: Node3D                     ## the measure scene: the wall's parent, its `Ground` the strip
var _start_z := 0.0                   ## the strip's spawn z
var _trace := false                   ## print every tick
var _scrape_one := false              ## `onebody`: the wall a shape of the strip's body
var _sc_steer := 0.0                  ## `steer=`: the wheel held there (%) once SCRAPE_STEER_S in
var _hold: MeasureRig.PiHold          ## the crawl's PI pedal (`Kerb.crawl`)
var _restart: Callable                ## the tool's pass reset, after the respawn
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _sc_wall: Node3D = null           ## the wall: a body, or the strip's second shape
var _sc_wall_x := 0.0                 ## its face, m
var _sc_wheels: Array[Dictionary] = [] ## per wheel, the run's figures (`tick`)
var _sc_peak := Vector3.ZERO          ## peak acceleration across (x, m/s2), yaw rate (y), tilt (z, deg)
var _sc_prev_v := Vector3.ZERO


func _init(tool: Node3D, start_z: float, trace: bool, one_body: bool, steer_pct: float,
		hold: MeasureRig.PiHold, restart: Callable, finish: Callable) -> void:
	_tool = tool
	_start_z = start_z
	_trace = trace
	_scrape_one = one_body
	_sc_steer = steer_pct
	_hold = hold
	_restart = restart
	_finish = finish


## The drive along a wall on `car`, headed `title` ("<variant> (<drive>)").
func start(car: BaseVehicle, title: String, _current: Dictionary) -> void:
	_car = car
	if _sc_wall != null:
		_sc_wall.get_parent().remove_child(_sc_wall)
		_sc_wall.queue_free()
	var reach := 0.0
	for w in _car.wheels:
		reach = maxf(reach, absf(w.anchor.x) + w.half_width)
	_sc_wall_x = reach + SCRAPE_GAP
	var size := Vector3(1.0, SCRAPE_HIGH + MeasureRig.BLOCK_SINK, SCRAPE_LONG)
	var centre := Vector3(_sc_wall_x + 0.5, (SCRAPE_HIGH - MeasureRig.BLOCK_SINK) * 0.5,
			_start_z + SCRAPE_BEHIND - SCRAPE_LONG * 0.5)
	if _scrape_one:
		var ground: StaticBody3D = _tool.get_node("Ground")
		var shape := CollisionShape3D.new()
		shape.shape = MeasureRig.welded_box_shape(size)
		shape.position = centre - ground.position
		ground.add_child(shape)
		_sc_wall = shape
	else:
		_sc_wall = MeasureRig.add_welded_box(_tool, "Wall", size, Transform3D(Basis.IDENTITY, centre))
	print("=== %s, scrape, the wall %s ===" % [title,
			"a shape of the strip's body" if _scrape_one else "a body of its own"])
	MeasureRig.place(_car, Transform3D(Basis(Vector3.UP, -deg_to_rad(SCRAPE_DEG)),
			Vector3(0.0, _car.rest_ride_height(), _start_z)))
	_car.respawn()
	_restart.call()
	_hold.integral = 0.0
	_sc_wheels = []
	_sc_peak = Vector3.ZERO
	_sc_prev_v = Vector3.ZERO
	MeasureRig.drive(0.0, 0.0)


## One physics tick, `t` s into the run (the tool's pass clock).
func tick(delta: float, t: float) -> void:
	var b := _car.global_transform.basis
	var v_long := _car.linear_velocity.dot(-b.z)
	Kerb.crawl(_car, _hold, v_long, delta, SCRAPE_SPEED, _sc_steer if t >= SCRAPE_STEER_S else 0.0)
	# The unit's wheels, then a coupled towed body's (it couples after the spawn countdown).
	var towed := MeasureRig.towed(_car)
	var wheels: Array[RayWheel] = _car.drive.wheels.duplicate()
	var own := wheels.size()
	if towed != null:
		wheels.append_array(towed.wheels)
	while _sc_wheels.size() < wheels.size():
		var i := _sc_wheels.size()
		_sc_wheels.append({"deep": -INF, "contact": 0, "off": 0, "ticks": 0,
				"label": MeasureRig.wheel_label(_car, wheels[i]) if i < own else "T%d" % (i - own)})
	var cells := PackedStringArray()
	for i in wheels.size():
		var w := wheels[i]
		var row := _sc_wheels[i]
		var xf := _car.global_transform if i < own else towed.global_transform
		var mount := w.mount_basis(xf.basis)
		var axle := Basis(mount.y, w.steer_angle) * mount.x
		var deep := (xf * w.mount_anchor()).x + RayWheel.cylinder_support(Vector3.RIGHT, axle,
				w.wheel_radius, w.half_width) - _sc_wall_x
		row["deep"] = maxf(row["deep"], deep)
		row["ticks"] += 1
		if not w.in_contact:
			cells.append("%s %+.0f mm -" % [row["label"], deep * 1000.0])
			continue
		var along := w.contact_normal.dot(mount.y)
		var off := not RayWheel.carries(w.contact_normal, mount.y)
		row["contact"] += 1
		row["off"] += int(off)
		cells.append("%s %+.0f mm c%.3f F%.0f n.up %+.2f n.ax %+.2f%s" % [row["label"], deep * 1000.0,
				w.compression, w.suspension_force, along, w.contact_normal.dot(axle),
				" OFF" if off else ""])
	var accel := (_car.linear_velocity - _sc_prev_v) / delta
	_sc_prev_v = _car.linear_velocity
	var tilt := rad_to_deg(b.y.angle_to(Vector3.UP))
	_sc_peak = _sc_peak.max(Vector3(absf(accel.dot(b.x)), absf(_car.angular_velocity.dot(b.y)), tilt))
	if _trace:
		print("    t %.3f v %.2f tilt %.1f | %s" % [t, v_long, tilt, " | ".join(cells)])
	if t >= SCRAPE_S:
		print("  ends at %.2f m/s; peak %.2f g across, %.1f deg/s yaw, %.1f deg tilt" % [v_long,
				_sc_peak.x / BrakeSizing.G, rad_to_deg(_sc_peak.y), _sc_peak.z])
		for row in _sc_wheels:
			print("    %-3s %+4.0f mm past the wall's face, contact %3.0f %%, off its travel %d ticks"
					% [row["label"], float(row["deep"]) * 1000.0,
					100.0 * row["contact"] / maxf(float(row["ticks"]), 1.0), row["off"]])
		MeasureRig.drive(0.0, 0.0)
		_finish.call()
