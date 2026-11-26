extends RefCounted
## `measure_vehicles`' kerb pass (`kerb`, instead of every other pass): the tool spawns each body
## and hands it here (`start`, then `tick` every physics tick).
## Square steps across the strip: how the contact (`RayWheel`) meets an edge. At each of
## KERB_HEIGHTS a raised plateau is crawled square on at KERB_CRAWL (the circle's PI pedal, braked past it: a converter's creep outruns it), coasted
## square on from KERB_COAST (run up floored, the
## pedal lifted as the plateau is laid) and crawled at KERB_OBLIQUE_DEG; every run also takes the
## step down at its far edge. The plateau is laid once the run-up settles, its edge KERB_LEAD_CRAWL /
## _COAST ahead of the foremost hub, `wheelbase + KERB_TOP` long. Per wheel and edge, from KERB_LATCH
## out to KERB_CLEAR past: the hub's distance ahead of the edge along the heading when its contact
## first sits on the new level (`contact_point` over half the step, or under it on the step down)
## and the contact normal's lean from vertical then, the peak lean, the largest one-tick compression
## change, and its peak spring force against `max_suspension_force`. Per edge: the speed at the first
## contact, the least until every hub is KERB_CLEAR past, and then; the peak vertical acceleration at
## the COM; the time from the first contact to every hub clear. STUCK is measure_rough's rule.

const MeasureRig := preload("res://tools/measure_rig.gd")

const KERB_HEIGHTS: Array[float] = [0.12, 0.20]  ## the road tiles' curb, and a taller step
const KERB_CRAWL := 1.0            ## m/s
const KERB_COAST := 8.33           ## m/s (30 km/h)
const KERB_OBLIQUE_DEG := 30.0
const KERB_SETTLE_S := 3.0         ## s of crawl before the plateau is laid
const KERB_LEAD_CRAWL := 3.0       ## m from the foremost hub to the edge, as laid
const KERB_LEAD_COAST := 15.0
const KERB_TOP := 10.0             ## m of plateau past the wheelbase
const KERB_WIDTH := 80.0           ## m along the edge, wide enough for the 30 degree crossing
const KERB_LATCH := 1.0            ## m out from the edge where each wheel's window opens
const KERB_BRAKE_GAIN := 1.0       ## crawl brake per m/s over KERB_CRAWL
const KERB_CLEAR := 0.5            ## m past the edge that counts a hub as over it
const KERB_STUCK_S := 5.0
const KERB_STUCK_PROGRESS := 0.25  ## m of progress that resets the stuck clock
const KERB_TIMEOUT_S := 60.0

var _tool: Node3D                     ## the measure scene: the plateau's parent
var _start_z := 0.0                   ## the strip's spawn z
var _seconds := 0.0                   ## the coast's run-up cap
var _kb_hold: MeasureRig.PiHold       ## the crawl's PI pedal
var _restart: Callable                ## the tool's pass reset, after each respawn
var _finish: Callable                 ## the tool's end of this body
var _car: BaseVehicle
var _current := {}                    ## the tool's report entry for this body
var _kb_runs: Array[Dictionary] = []  ## {h, coast, oblique} still to run, this body
var _kb_run := {}                     ## the run in progress
var _kb_box: StaticBody3D = null      ## the plateau, once laid
var _kb_t := 0.0                      ## s since the plateau was laid
var _kb_heading := Vector3.ZERO       ## the body's heading as the plateau was laid
var _kb_n := Vector3.ZERO             ## the edges' normal, toward the approach
var _kb_cos := 1.0                    ## `_kb_heading` along `-_kb_n`
var _kb_edge_at: Array[Vector3] = []  ## a point on the near and the far edge, y 0
var _kb_edges: Array[Dictionary] = [] ## per edge, up then down: the run's figures (`_kerb_edge`)
var _kb_prev_vy := 0.0
var _kb_origin := Vector3.ZERO
var _kb_best := 0.0                   ## furthest progress along the heading, m
var _kb_best_t := 0.0
var _kb_overlaps := 0                 ## `RayWheel.start_overlaps` as the run began


func _init(tool: Node3D, start_z: float, seconds: float, hold: MeasureRig.PiHold, restart: Callable,
		finish: Callable) -> void:
	_tool = tool
	_start_z = start_z
	_seconds = seconds
	_kb_hold = hold
	_restart = restart
	_finish = finish


## The kerb runs on `car`, headed `title` ("<variant> (<drive>)"); `current` takes each verdict.
## First the disk's prediction per axle: a disk of radius `r` first meets a step `h`
## `sqrt(2 r h - h²)` ahead of its hub, its normal leaning back `asin(x / r)`; a cylinder meets an
## oblique edge `half_width tan θ` sooner, at its leading tread corner.
func start(car: BaseVehicle, title: String, current: Dictionary) -> void:
	_car = car
	_current = current
	_kb_runs = []
	for h in KERB_HEIGHTS:
		_kb_runs.append({"h": h, "coast": false, "oblique": false})
		_kb_runs.append({"h": h, "coast": true, "oblique": false})
		_kb_runs.append({"h": h, "coast": false, "oblique": true})
	var gd := _car.spec.ground_drive
	print("=== %s, kerb ===" % title)
	for rear in [false, true]:
		var r := gd.axle_radius(rear)
		var parts := PackedStringArray()
		for h in KERB_HEIGHTS:
			var x := sqrt(2.0 * r * h - h * h)
			parts.append("%.0f cm %.2f m, %.0f deg" % [h * 100.0, x, rad_to_deg(asin(x / r))])
		print("  predicted %-5s r %.2f: disk %s; cylinder +%.2f m at %.0f deg" % [
				"rear" if rear else "front", r, ", ".join(parts),
				gd.axle_half_width(rear) * tan(deg_to_rad(KERB_OBLIQUE_DEG)), KERB_OBLIQUE_DEG])
	_next_kerb_run()


func _next_kerb_run() -> void:
	if _kb_box != null:
		_tool.remove_child(_kb_box)
		_kb_box.queue_free()
		_kb_box = null
	if _kb_runs.is_empty():
		MeasureRig.drive(0.0, 0.0)
		_finish.call()
		return
	_kb_run = _kb_runs.pop_front()
	_car.spawn_transform = Transform3D(Basis.IDENTITY,
			Vector3(0.0, _car.rest_ride_height(), _start_z))
	_car.respawn()
	_restart.call()
	_kb_hold.integral = 0.0
	_kb_t = 0.0
	_kb_edges = []
	_kb_overlaps = RayWheel.start_overlaps
	MeasureRig.drive(100.0 if _kb_run["coast"] else 0.0, 0.0)


## One physics tick, `t` s into the run (the tool's pass clock).
func tick(delta: float, t: float) -> void:
	var v_long := _car.linear_velocity.dot(-_car.global_transform.basis.z)
	var coast: bool = _kb_run["coast"]
	if _kb_box == null:
		if coast:
			if v_long >= KERB_COAST or t >= _seconds:
				_lay_kerb(KERB_LEAD_COAST)
				MeasureRig.drive(0.0, 0.0)
		else:
			crawl(_car, _kb_hold, v_long, delta)
			if t >= KERB_SETTLE_S:
				_lay_kerb(KERB_LEAD_CRAWL)
		return
	if not coast:
		crawl(_car, _kb_hold, v_long, delta)
	_kb_t += delta
	var v := _car.linear_velocity.dot(_kb_heading)
	var ay := (_car.linear_velocity.y - _kb_prev_vy) / delta
	_kb_prev_vy = _car.linear_velocity.y
	for e in 2:
		_kerb_edge_tick(e, v, ay)
	var progress := (_car.global_position - _kb_origin).dot(_kb_heading)
	if progress > _kb_best + KERB_STUCK_PROGRESS:
		_kb_best = progress
		_kb_best_t = _kb_t
	var verdict := ""
	if float(_kb_edges[1]["t_clear"]) >= 0.0:
		verdict = "over"
	elif _kb_t - _kb_best_t > KERB_STUCK_S:
		verdict = "STUCK"
	elif _kb_t > KERB_TIMEOUT_S:
		verdict = "TIMEOUT"
	if verdict != "":
		_report_kerb_run(verdict)
		_next_kerb_run()


## The crawl's speed hold: the circle's PI pedal (`hold`) at `v_set`, and the brake past it.
static func crawl(car: BaseVehicle, hold: MeasureRig.PiHold, v_long: float, delta: float,
		v_set := KERB_CRAWL, steer_pct := 0.0) -> void:
	var err := v_set - v_long
	MeasureRig.drive(MeasureRig.pi_pedal(car, hold.step(err, delta), v_set) * 100.0,
			clampf(-err * KERB_BRAKE_GAIN, 0.0, 1.0) * 100.0, steer_pct)


## The plateau, its near edge `lead` ahead of the foremost hub along the heading, square to it or
## KERB_OBLIQUE_DEG off; its top at the run's height.
func _lay_kerb(lead: float) -> void:
	var h: float = _kb_run["h"]
	var xf := _car.global_transform
	_kb_heading = Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
	var oblique := deg_to_rad(KERB_OBLIQUE_DEG) if _kb_run["oblique"] else 0.0
	_kb_n = Basis(Vector3.UP, oblique) * -_kb_heading
	_kb_cos = _kb_heading.dot(-_kb_n)
	var front := -INF
	for w in _car.wheels:
		front = maxf(front, (xf * w.anchor).dot(_kb_heading))
	var near := _car.global_position + _kb_heading * (front - _car.global_position.dot(_kb_heading)
			+ lead)
	near.y = 0.0
	var length := MeasureRig.wheelbase_of(_car.spec) + KERB_TOP
	_kb_edge_at = [near, near - _kb_n * length]
	_kb_box = MeasureRig.add_welded_box(_tool, "Kerb",
			Vector3(KERB_WIDTH, h + MeasureRig.BLOCK_SINK, length), Transform3D(
			Basis(Vector3.UP, atan2(_kb_n.x, _kb_n.z)),
			near - _kb_n * (length * 0.5) + Vector3.UP * ((h - MeasureRig.BLOCK_SINK) * 0.5)))
	_kb_edges = [_kerb_edge(), _kerb_edge()]
	_kb_prev_vy = _car.linear_velocity.y
	_kb_origin = _car.global_position
	_kb_best = 0.0
	_kb_best_t = 0.0


## One edge's figures over a kerb run; the arrays are per wheel.
func _kerb_edge() -> Dictionary:
	var zero := []
	zero.resize(_car.wheels.size())
	zero.fill(0.0)
	var unset := zero.duplicate()
	unset.fill(NAN)
	return {"prev": zero.duplicate(), "x": unset, "lean": unset.duplicate(),
			"lean_peak": zero.duplicate(), "jump": zero.duplicate(), "peak": zero.duplicate(),
			"t_first": -1.0, "v_first": NAN, "v_min": INF, "v_clear": NAN,
			"t_clear": -1.0, "a_peak": 0.0}


## Edge `e` (0 the step up, 1 the step down) this tick, at road speed `v` and COM vertical
## acceleration `ay`.
func _kerb_edge_tick(e: int, v: float, ay: float) -> void:
	var edge := _kb_edges[e]
	var up_edge := e == 0
	var half_step: float = _kb_run["h"] * 0.5
	var xf := _car.global_transform
	var any_in := false
	var all_clear := true
	for i in _car.wheels.size():
		var w: RayWheel = _car.wheels[i]
		var d := (xf * w.anchor - _kb_edge_at[e]).dot(_kb_n) / _kb_cos
		var c := w.compression
		if d > KERB_LATCH:
			edge["prev"][i] = c
			all_clear = false
			continue
		any_in = true
		var change: float = c - float(edge["prev"][i])
		edge["prev"][i] = c
		if d <= -KERB_CLEAR:
			continue
		all_clear = false
		var lean := rad_to_deg(w.contact_normal.angle_to(Vector3.UP)) if w.in_contact else 0.0
		edge["lean_peak"][i] = maxf(float(edge["lean_peak"][i]), lean)
		edge["peak"][i] = maxf(float(edge["peak"][i]), w.suspension_force)
		edge["jump"][i] = maxf(float(edge["jump"][i]), change if up_edge else -change)
		var landed := w.in_contact and (w.contact_point.y > half_step if up_edge
				else w.contact_point.y < half_step)
		if is_nan(float(edge["x"][i])) and landed:
			edge["x"][i] = d
			edge["lean"][i] = lean
			if float(edge["t_first"]) < 0.0:
				edge["t_first"] = _kb_t
				edge["v_first"] = v
	if any_in and float(edge["t_clear"]) < 0.0:
		edge["v_min"] = minf(float(edge["v_min"]), v)
		edge["a_peak"] = maxf(float(edge["a_peak"]), absf(ay))
		if all_clear:
			edge["t_clear"] = _kb_t
			edge["v_clear"] = v


func _report_kerb_run(verdict: String) -> void:
	var h: float = _kb_run["h"]
	var how := "coast 30 km/h" if _kb_run["coast"] else "crawl"
	if _kb_run["oblique"]:
		how += " at %.0f deg" % KERB_OBLIQUE_DEG
	var cap := _car.spec.ground_drive.max_suspension_force
	var overlaps := RayWheel.start_overlaps - _kb_overlaps
	print("  %.0f cm %-18s : %s after %.1f s%s" % [h * 100.0, how, verdict, _kb_t,
			", %d cast start overlaps" % overlaps if overlaps > 0 else ""])
	for e in 2:
		var edge := _kb_edges[e]
		var edge_name := "up" if e == 0 else "down"
		if float(edge["t_first"]) < 0.0:
			print("    %-4s: no wheel on the new level by %.1f m past (airborne)" % [edge_name, KERB_CLEAR])
			continue
		var t_clear: float = edge["t_clear"]
		var v_clear: float = edge["v_clear"]
		print("    %-4s: %s, v %.2f -> min %.2f -> %s m/s, peak |a_y| %.2f g" % [edge_name,
				"%.2f s" % (t_clear - float(edge["t_first"])) if t_clear >= 0.0 else "not cleared",
				edge["v_first"], edge["v_min"], "-" if is_nan(v_clear) else "%.2f" % v_clear,
				float(edge["a_peak"]) / BrakeSizing.G])
		for i in _car.wheels.size():
			var x: float = edge["x"][i]
			var peak: float = edge["peak"][i]
			print(("      %-4s on the new level %s ahead, lean %s (peak %.0f deg), largest tick %.0f mm,"
					+ " peak %.1f of %.1f kN%s") % [MeasureRig.wheel_label(_car,_car.wheels[i]),
					"-" if is_nan(x) else "%+.2f m" % x,
					"-" if is_nan(x) else "%.0f deg" % float(edge["lean"][i]),
					float(edge["lean_peak"][i]), float(edge["jump"][i]) * 1000.0, peak / 1000.0,
					cap / 1000.0,
					" (clamp bound)" if peak >= cap - 1.0 else ""])
	_current["kerb_%.0f_%s" % [h * 100.0, how.replace(" ", "_")]] = verdict
