extends RefCounted
## `measure_vehicles`' hitch pass (`hitch`, instead of every other pass): the tool spawns each body
## and hands it here (`start`, then `tick` every physics tick).

const MeasureRig := preload("res://tools/measure_rig.gd")

## Parked on the foot brake and the lever, a body with three-point implements is read bare, then per
## implement (`trailer=` names one; else every carried one) at each of HITCH_STAGES. A reading waits
## HITCH_WAIT_S (the linkage's 1.5 s stroke and the settle), then averages HITCH_AVG_S: each axle's
## summed `suspension_force` (kg) against the statics off the live mass and COM; the front change
## from bare against `m e / L` off the implement point the live COM implies; the front share against
## HITCH_FRONT_MIN; and the body-frame tensor diagonal against the composite (the bare tensor plus
## parallel-axis terms for the bare mass and a point implement), the gap Jolt's COM-shift leaves.
const HITCH_WAIT_S := 4.0
const HITCH_AVG_S := 1.0
## Ballasting minimum: at least 20 % of total weight on the front axle to keep the tractor
## steerable (John Deere operator's manual, "Select Ballast Carefully").
const HITCH_FRONT_MIN := 0.20
## `hitch_pos` per reading: the bottom stop, raised, lowered again.
const HITCH_STAGES: Array[float] = [0.0, 100.0, 0.0]

var _trailer := ""                    ## `trailer=`: the one implement to read, else every carried one
var _restart: Callable                ## the tool's pass reset
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _current := {}                    ## the tool's report entry for this body
var _t := 0.0                         ## s since the reading began
var _hi_ids: Array[String] = []       ## implements still to read, this body
var _hi_stage := -1                   ## index into HITCH_STAGES; -1 the bare reading
var _hi_sums := Vector3.ZERO          ## front N, rear N, ticks over the current average
var _hi_bare := {}                    ## the bare reading: front kg, mass, COM, body-frame tensor


func _init(trailer: String, restart: Callable, finish: Callable) -> void:
	_trailer = trailer
	_restart = restart
	_finish = finish


## The hitch statics on `car`, headed `title` ("<variant> (<drive>)"): parked, bare first.
func start(car: BaseVehicle, title: String, current: Dictionary) -> void:
	_car = car
	_current = current
	_restart.call()
	_t = 0.0
	_hi_ids = []
	_hi_bare = {}
	if not _car is TractorVehicle:
		print("=== %s: no three-point linkage, hitch skipped ===" % String(_current["variant"]))
		_finish.call()
		return
	for id: String in _car.call(&"attachment_ids"):
		if not ImplementCatalog.is_attached(id) or ImplementCatalog.is_towed(id):
			continue
		if _trailer == "" or id.get_file().get_basename() == _trailer:
			_hi_ids.append(id)
	print("=== %s, hitch statics, parked: per-axle kg off the springs ===" % title)
	_car.call(&"set_attachment", AttachmentCatalog.NONE)
	_hi_stage = -1
	_begin_hitch_reading(100.0)


## Command `hitch_pos` (0..100) on the parking brakes and restart the reading's clock.
func _begin_hitch_reading(hitch_pos: float) -> void:
	_t = 0.0
	_hi_sums = Vector3.ZERO
	MeasureRig.drive(0.0, 100.0, 0.0, true, 1, false, 3, {"hitch_pos": hitch_pos})


## One physics tick.
func tick(delta: float, _host_t: float) -> void:
	_t += delta
	if _t < HITCH_WAIT_S:
		return
	var axles := Vector2.ZERO
	for w in _car.wheels:
		if w.is_rear:
			axles.y += w.suspension_force
		else:
			axles.x += w.suspension_force
	_hi_sums += Vector3(axles.x, axles.y, 1.0)
	if _t < HITCH_WAIT_S + HITCH_AVG_S:
		return
	_report_hitch_reading()
	# After the bare reading, or an implement's last stage: on to the next implement.
	if _hi_stage >= 0 and _hi_stage + 1 < HITCH_STAGES.size():
		_hi_stage += 1
	elif _hi_ids.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish.call()
		return
	else:
		_car.call(&"set_attachment", _hi_ids.pop_front())
		_hi_stage = 0
	_begin_hitch_reading(HITCH_STAGES[_hi_stage])


## The body-frame inertia tensor (kg·m²) off the live state: `inverse_inertia_tensor` is world-space
## (`RayWheel.size_cap_masses`' read), so it is turned into the body's axes and inverted.
func _body_tensor() -> Basis:
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	var b := _car.global_transform.basis
	return (b.transposed() * state.inverse_inertia_tensor * b).inverse()


## Diagonal of the parallel-axis tensor of `kg` at offset `d`: x pitch, y yaw, z roll.
static func _parallel_axis(kg: float, d: Vector3) -> Vector3:
	return kg * Vector3(d.y * d.y + d.z * d.z, d.x * d.x + d.z * d.z, d.x * d.x + d.y * d.y)


func _report_hitch_reading() -> void:
	var g := _car.get_gravity().length()
	var n := maxf(_hi_sums.z, 1.0)
	var front := _hi_sums.x / n / g
	var rear := _hi_sums.y / n / g
	var rear_z := float(BrakeSizing.axle_geometry(_car.spec)["rear_z"])
	var wheelbase := MeasureRig.wheelbase_of(_car.spec)
	var m := _car.mass
	var com := _car.center_of_mass
	var front_pred := m * (rear_z - com.z) / wheelbase
	var share := front / maxf(front + rear, 1e-6)
	var tensor := _body_tensor()
	var label := "bare"
	if _hi_stage >= 0:
		var where := "raised" if HITCH_STAGES[_hi_stage] > 50.0 else "bottom stop"
		label = "%s, %s" % [String(_car.call(&"current_attachment")).get_file().get_basename(), where]
	print(("  %-22s: front %.0f kg, rear %.0f kg; statics %.0f / %.0f (front %+.1f %%, rear %+.1f %%);"
			+ " front share %.1f %% (min %.0f %%)") % [label, front, rear, front_pred, m - front_pred,
			(front / front_pred - 1.0) * 100.0, (rear / (m - front_pred) - 1.0) * 100.0, share * 100.0,
			HITCH_FRONT_MIN * 100.0])
	var row := {"label": label, "front_kg": front, "rear_kg": rear, "front_pred": front_pred,
			"share": share, "mass": m, "com_z": com.z, "com_y": com.y}
	if _hi_stage < 0:
		_hi_bare = {"front": front, "mass": m, "com": com, "tensor": tensor}
		print("  %-22s  mass %.0f kg, COM (%.3f, %.3f, %.3f); tensor diagonal %s kg·m²" % ["",
				m, com.x, com.y, com.z, _diag_label(_diag(tensor))])
	else:
		var bare_m: float = _hi_bare["mass"]
		var bare_com: Vector3 = _hi_bare["com"]
		var carried := m - bare_m
		var lines := "  %-22s  mass %.0f kg (+%.0f carried), COM (%.3f, %.3f, %.3f)" % ["", m, carried,
				com.x, com.y, com.z]
		if carried > 0.5:
			# The point the carried load sits at, recovered from the live COM (carried_com inverted).
			var p := bare_com + (com - bare_com) * m / carried
			var d_front_pred := carried * (rear_z - p.z) / wheelbase
			var jolt := _diag(tensor)
			var composite := _diag(_hi_bare["tensor"]) + _parallel_axis(bare_m, bare_com - com) \
					+ _parallel_axis(carried, p - com)
			lines += ("; Δfront %+.0f kg (m e / L %+.0f, e %.2f m behind the rear axle)\n  %-22s  tensor"
					+ " diagonal %s, composite %s: Jolt carries %.0f / %.0f / %.0f %% (pitch / yaw / roll)") \
					% [front - float(_hi_bare["front"]), d_front_pred, p.z - rear_z, "",
					_diag_label(jolt), _diag_label(composite), jolt.x / composite.x * 100.0,
					jolt.y / composite.y * 100.0, jolt.z / composite.z * 100.0]
			row["d_front"] = front - float(_hi_bare["front"])
			row["d_front_pred"] = d_front_pred
			row["yaw_ratio"] = jolt.y / composite.y
		print(lines)
	if not _current.has("hitch"):
		_current["hitch"] = []
	(_current["hitch"] as Array).append(row)


static func _diag(t: Basis) -> Vector3:
	return Vector3(t.x.x, t.y.y, t.z.z)


static func _diag_label(d: Vector3) -> String:
	return "%.0f / %.0f / %.0f" % [d.x, d.y, d.z]
