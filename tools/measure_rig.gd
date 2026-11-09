extends RefCounted
## What the game-mode measure tools share: the body's spawn and its in-memory spec copy, the flat
## full-grip slab or tilted ramp it is driven on, the painted surface over it, the tyre class on it,
## the rig's bodies and laden mass, the PI speed hold, the trailer-roll table, the report labels,
## and the bridge stash it is driven through. Each tool keeps its own layout (strip, pad) and pass
## logic.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Layers := preload("res://src/physics/collision_layers.gd")

## `noesc` (every tool): the body's stability control unfitted in memory (`unfit_esc`), its traction
## control left as fitted: the bridge's `esc_off` would take TC with it, and the chassis tables are
## recorded with TC on. Each tool sets it from its flags; a chassis table's doc preset sets it itself.
static var esc_off := false
## `noabs` (measure_vehicles): the LAB page's ANTI-LOCK BRAKES OFF (`apply_lab`).
static var abs_off := false
## `axle=open|locked` (measure_vehicles, measure_rough): the LAB page's DIFFERENTIALS switch
## (`apply_lab`).
static var axle_diff := VehicleInput.AxleDiff.STOCK
## A towed body's own roll-over control off (`notrsp`): its lift table is measured on the bare
## trailer, never one braking itself.
static var trailer_roll_off := false
## A coupled tanker's surge pinned at 0 (`nosurge`, `SurgePin`): the surge's share of a run, sized
## against the same run with it.
static var surge_off := false


## `body`'s spec and its ground drive copied, in memory, never shipped (the ground drive is a
## sub-resource a spec copy shares), and the copy's ground drive returned to edit. Before
## `add_child` the wheels build from it; after, a caller re-reads what it changed onto them.
static func own_ground_drive(body: Node) -> GroundDriveSpec:
	var spec := (body.get("spec") as VehicleSpec).duplicate() as VehicleSpec
	spec.ground_drive = spec.ground_drive.duplicate()
	body.set("spec", spec)
	return spec.ground_drive


## Under `esc_off`, `car`'s ESC unfitted on its own spec (`own_ground_drive`). Its tick reads the
## spec each tick, so any time works.
static func unfit_esc(car: Node) -> void:
	var spec: VehicleSpec = car.get("spec")
	if not esc_off or spec == null or spec.ground_drive == null or not spec.ground_drive.esc_equipped:
		return
	own_ground_drive(car).esc_equipped = false


## `variant`'s body instanced under `parent`: ESC unfitted (`unfit_esc`), then `prep(body)` (the
## tool's spec overrides: before `add_child`, so the wheels build from them), then added. Lay it
## with `place` once the tool's in-tree setup (a tyre fit, an attachment) is done: a tyre moves
## `rest_ride_height`.
static func spawn(parent: Node, variant: String, prep := Callable()) -> Node:
	var body: Node = (load(Catalog.scene_of(variant)) as PackedScene).instantiate()
	unfit_esc(body)
	if prep.is_valid():
		prep.call(body)
	parent.add_child(body)
	return body


## `body` laid at `xform`, which `respawn()` re-lays it (and any trailer) on, with no interpolation
## from where it was.
static func place(body: Node3D, xform: Transform3D) -> void:
	body.global_transform = xform
	body.set("spawn_transform", xform)
	body.reset_physics_interpolation()


## `body` (null: nothing) taken out of `parent` and freed; a unit takes its trailer with it.
static func free_body(parent: Node, body: Node) -> void:
	if body == null:
		return
	parent.remove_child(body)
	body.queue_free()


## `body` on a ramp tilted `angle` rad (`tilt_ramp`, through (0, `lift`, 0)): `up` metres up the
## slope from the origin, wheels just touching, turned `yaw` about the ramp's normal (PI / 2 parks it
## across).
static func slope_pose(body: Node, angle: float, up: float, yaw := 0.0, lift := 0.0) -> Transform3D:
	var tilt := Basis(Vector3.RIGHT, angle)
	var surface := tilt * Vector3(0.0, 0.0, -up) + Vector3.UP * lift
	return Transform3D(tilt * Basis(Vector3.UP, yaw),
			surface + tilt.y * float(body.call(&"rest_ride_height")))



## A tool's `<prefix><value>` flag (prefix e.g. "pedal="): the value of the last one, "" when absent.
static func flag(args: PackedStringArray, prefix: String) -> String:
	var value := ""
	for a in args:
		if a.begins_with(prefix):
			value = a.substr(prefix.length())
	return value


## `flag` as a float; `default` when absent.
static func float_flag(args: PackedStringArray, prefix: String, default: float) -> float:
	var value := flag(args, prefix)
	return float(value) if value != "" else default


## A tool's `gear=<byte>` flag: the drive byte to hold, 0 when absent; -1 (printed as an error)
## outside 1..TOP_GEAR, which the tool quits on.
static func gear_flag(args: PackedStringArray) -> int:
	var value := flag(args, "gear=")
	if value == "":
		return 0
	var byte := int(value)
	if byte < 1 or byte > Drivetrain.TOP_GEAR:
		printerr("gear=%s: expected a drive byte 1-%d" % [value, Drivetrain.TOP_GEAR])
		return -1
	return byte


## The four switches every tool takes into the statics above: `noesc`, `noabs`, `notrsp`, `nosurge`.
static func common_flags(args: PackedStringArray) -> void:
	esc_off = args.has("noesc")
	abs_off = args.has("noabs")
	trailer_roll_off = args.has("notrsp")
	surge_off = args.has("nosurge")


## A tool's variant argument: `all_variants` for "all" (when the tool takes it), one catalog variant,
## or a comma list of them. Empty (printed as an error) on anything else, which the tool quits on.
static func variants_arg(which: String, all_variants: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if which == "all" and not all_variants.is_empty():
		out = all_variants.duplicate()
	elif Array(which.split(",")).all(func(v: String) -> bool: return Catalog.VARIANTS.has(v)):
		out.assign(which.split(","))
	else:
		printerr("unknown variant '%s' — expected %sone of: %s" % [which,
				"'all' or " if not all_variants.is_empty() else "",
				", ".join(all_variants if not all_variants.is_empty() else Catalog.VARIANTS.keys())])
	return out


## A tool's `axle=open|locked` flag into `axle_diff`; false (printed as an error) on any other
## value, which the tool quits on. STOCK when absent.
static func axle_flag(args: PackedStringArray) -> bool:
	axle_diff = VehicleInput.AxleDiff.STOCK
	var value := flag(args, "axle=")
	if value != "":
		var mode: Variant = VehicleInput.AxleDiff.get(value.to_upper())
		if mode == null or mode == VehicleInput.AxleDiff.STOCK:
			printerr("axle=%s: expected open or locked" % value)
			return false
		axle_diff = mode
	return true


## Under `abs_off` / `axle_diff`, the LAB switches on this tick's input as the router sets them
## (`InputRouter.lab_raw` on `car`'s hardware, then `lab_cascade`): the bridge stash these tools
## drive through never carries them. The router builds a fresh struct every tick, so nothing leaks;
## call it from the tool root's `_physics_process`, which runs after the router's and before its
## vehicle child's.
static func apply_lab(car: Node) -> void:
	if (not abs_off and axle_diff == VehicleInput.AxleDiff.STOCK) or car == null:
		return
	var lab := lab_on(car)
	var input := InputRouter.get_vehicle_input()
	input.abs_off = bool(lab[&"abs_off"])
	input.axle_diff = int(lab[&"axle_diff"]) as VehicleInput.AxleDiff
	InputRouter.lab_cascade(input)


## `abs_off` / `axle_diff` as they reach `car` (`InputRouter.lab_raw` on its hardware): stock on a
## body without it, as the LAB page leaves it.
static func lab_on(car: Node) -> Dictionary[StringName, Variant]:
	var caps: Dictionary = car.call(&"vehicle_capabilities") \
			if car != null and car.has_method(&"vehicle_capabilities") else {}
	return InputRouter.lab_raw(abs_off, axle_diff, false, caps, false)


## A report's note of `axle_diff` on `car`, e.g. ", driven axles locked (axle=, not the spec's)",
## or that the body has no axle diff the switch acts on; empty at STOCK.
static func axle_label(car: Node) -> String:
	if axle_diff == VehicleInput.AxleDiff.STOCK:
		return ""
	if int(lab_on(car)[&"axle_diff"]) == VehicleInput.AxleDiff.STOCK:
		return ", axle= ignored (no switchable axle diff)"
	return ", driven axles %s%s (axle=, not the spec's)" % [
			String(VehicleInput.AxleDiff.find_key(axle_diff)).to_lower(),
			", with ESC and TC" if axle_diff == VehicleInput.AxleDiff.LOCKED else ""]


## Under `trailer_roll_off`, `trailer`'s roll-over control unfitted on its own spec, as `unfit_esc`
## does. Its tick reads the spec each tick, so any time works.
static func unfit_trailer_roll(trailer: TowedBody) -> void:
	var spec := trailer.spec
	if not trailer_roll_off or spec == null or spec.ground_drive == null \
			or not spec.ground_drive.trailer_roll_equipped:
		return
	own_ground_drive(trailer).trailer_roll_equipped = false


## `body`'s coupled towed body, null with none; under `trailer_roll_off` its roll-over control is
## unfitted first (`unfit_trailer_roll`, a no-op once done).
static func towed(body: Node) -> TowedBody:
	var host := coupled_host(body)
	if host == null or host.trailer == null:
		return null
	unfit_trailer_roll(host.trailer)
	return host.trailer


## What a coupled trailer did over one pass, for the trailer roll-over tables: its first wheel lift
## on its own sensor (`TowedBody.accel_lat`), whether it passed `BaseVehicle.OVERTURNED_DEG` and
## when, the ticks it reported VDC active, and per tick its own application (the higher side's
## chambers) and the towing unit's roll stability (`WheelDrive.roll_application`), the two series a
## chatter count reads. `begin` at the pass's start, then `tick` once a physics tick with `towed`'s
## trailer (null reads as nothing done).
class TrailerWatch:
	extends RefCounted

	var lift_g := -1.0       ## the trailer's own g at its first wheel lift, -1 never
	var overturn_t := -1.0   ## s into the pass the trailer passed OVERTURNED_DEG, -1 never
	var vdc_ticks := 0
	var applied := PackedFloat64Array()
	var tractor_roll := PackedFloat64Array()
	var _t := 0.0

	func begin() -> void:
		lift_g = -1.0
		overturn_t = -1.0
		vdc_ticks = 0
		applied = PackedFloat64Array()
		tractor_roll = PackedFloat64Array()
		_t = 0.0

	func tick(trailer: TowedBody, drive: WheelDrive, delta: float) -> void:
		_t += delta
		tractor_roll.append(drive.roll_application() if drive != null else 0.0)
		if trailer == null:
			applied.append(0.0)
			return
		applied.append(maxf(trailer._roll_actual.x, trailer._roll_actual.y))
		if trailer.vdc_active():
			vdc_ticks += 1
		if lift_g < 0.0 and trailer.wheels.any(func(w: RayWheel) -> bool: return not w.in_contact):
			lift_g = absf(trailer.accel_lat) / StabilityControl.G
		if overturn_t < 0.0 \
				and absf(VehicleMath.roll_deg(trailer.global_basis)) >= BaseVehicle.OVERTURNED_DEG:
			overturn_t = _t


## doc=trailer_roll's rows, [tractor ESC off, trailer roll-over control off]: both off (the
## baseline), the trailer's alone, the tractor's alone, both. Each is its own spawn
## (measure_vehicles' corner and step passes, measure_semi_launch's P7).
const TRAILER_ROLL_CONFIGS := [[true, true], [true, false], [false, true], [false, false]]

## `chatter_runs`: the consecutive sign flips that count as a tick-rate oscillation, and the
## smallest tick-to-tick change read as a direction: CHATTER_EPS (rad), or CHATTER_REL of the
## angle. Contact noise in the latched compressions flips at 0.1-2 µrad on a 2-5 mrad angle
## (`sedan`, 2026-10-19) and does not grow with the coefficient; a ringing loop's swing scales with
## it.
const CHATTER_FLIPS := 3
const CHATTER_EPS := 1e-7
const CHATTER_REL := 0.01
## ESC's floor, in its moment share (measure_vehicles' `_esc_share`): a change under 0.5 % of a
## wheel's brake (~7 N·m on `van`) is the sensors' per-tick noise on a held touch, no direction; a
## modulator dump's ring swings from 0 to the whole share.
const ESC_CHATTER_EPS := 0.005


## Pure: the runs in `series` where the tick-to-tick change flips sign on CHATTER_FLIPS or more
## consecutive ticks, a tick-rate oscillation. A change under CHATTER_EPS (rad) or CHATTER_REL of
## the angle is no direction and ends the run: a one-tick contact blip and its return, ticks apart
## from the next, are not a ringing loop. `eps`: another series' floor in its own unit.
static func chatter_runs(series: PackedFloat64Array, eps := CHATTER_EPS) -> int:
	var runs := 0
	var flips := 0
	var last := 0.0
	for i in range(1, series.size()):
		var d := series[i] - series[i - 1]
		if absf(d) < maxf(eps, CHATTER_REL * absf(series[i])):
			flips = 0
			last = 0.0
			continue
		if last != 0.0 and signf(d) != signf(last):
			flips += 1
			if flips == CHATTER_FLIPS:
				runs += 1
		else:
			flips = 0
		last = d
	return runs


## A `TrailerWatch` over the pass just run, the figures a trailer cell prints: its first lift and
## the time it went over (-1 never), the time VDC read active (s, `delta` a tick), and the chatter
## on its own application / the tractor's roll stability. Statics of the rig, not the watch's: an
## inner class cannot call the outer script's.
static func trailer_summary(watch: TrailerWatch, delta: float) -> Dictionary:
	return {"lift_g": watch.lift_g, "overturn_t": watch.overturn_t,
			"vdc_s": watch.vdc_ticks * delta,
			"chatter": chatter_runs(watch.applied, ESC_CHATTER_EPS),
			"tractor_chatter": chatter_runs(watch.tractor_roll, ESC_CHATTER_EPS)}


## A trailer cell (`trailer_summary`'s figures): its first lift and the time it went over, else
## `holds`; the time VDC read active; chatter on its own application / the tractor's roll stability.
static func trailer_cell(s: Dictionary, tractor_over: bool, holds := "holds") -> String:
	var outcome := holds
	if float(s["overturn_t"]) >= 0.0:
		outcome = "lifts at %.3f g, over at %.2f s" % [s["lift_g"], s["overturn_t"]]
	elif float(s["lift_g"]) >= 0.0:
		outcome = "lifts at %.3f g, stays up" % float(s["lift_g"])
	if tractor_over:
		outcome += ", tractor over"
	return "%s; VDC %.2f s; chatter %d / %d" % [outcome, s["vdc_s"], s["chatter"],
			s["tractor_chatter"]]


## A PI speed hold's state: `step` moves the integral on the error and returns the demand, both
## 0..1. A RefCounted, not a static on a Vector2: the integral stays float64 (Vector2 is float32).
class PiHold:
	extends RefCounted

	var integral := 0.0
	var kp := 0.0
	var ki := 0.0

	func _init(p_kp: float, p_ki: float) -> void:
		kp = p_kp
		ki = p_ki

	## One tick on `err` (setpoint less reading, in the hold's unit); `freeze` holds the integral
	## (a shift cut, where the drive drops and it would wind up).
	func step(err: float, delta: float, freeze := false) -> float:
		if not freeze:
			integral = clampf(integral + err * ki * delta, 0.0, 1.0)
		return clampf(integral + err * kp, 0.0, 1.0)


## Under `surge_off`, `body`'s coupled tanker held at no surge, in memory: after every priority-0
## tick (the rig's, which runs the surge model) it zeroes the model and the centre of mass before
## the physics step. The residue is one tick's slew (`SURGE_TRAVEL / SURGE_TIME / 60`, ~1 mm) that
## the unit's `brake_load_kg` reads inside its tick. A separate node, so a run without the flag
## keeps its tick order; `add_surge_pin` once, then set `body` per spawn.
class SurgePin:
	extends Node

	const Tanker := preload("res://src/vehicles/truck/trailers/tanker.gd")

	var body: Node = null

	func _physics_process(_delta: float) -> void:
		if body == null or not is_instance_valid(body):
			return
		# `coupled_host`'s walk: an inner class cannot call the outer script's statics.
		for node in body.find_children("*", "", true, false):
			var host := node as TowHost
			if host != null and host.is_coupled() and is_instance_valid(host.trailer) \
					and host.trailer.get_script() == Tanker:
				host.trailer.set("_surge", 0.0)
				host.trailer.set_load_offset(0.0)


## A `SurgePin` under `parent` under `surge_off`, else null.
static func add_surge_pin(parent: Node) -> SurgePin:
	if not surge_off:
		return null
	var pin := SurgePin.new()
	pin.name = "SurgePin"
	pin.process_physics_priority = 1
	parent.add_child(pin)
	return pin


## One `Surface` everywhere, over a slab or a ramp: the duck-typed contract `HeightmapTerrain`
## answers (`BaseVehicle._collect_grip_terrains`), nothing more. `height_at` is the plane through
## (0, `lift`, 0) rising `tan_angle` toward -Z, so `RayWheel.terrain_at`'s reach finds it anywhere
## on a climb. A body finds its terrains once: add the patch before its first tick, then change
## `surface` in place.
class GripPatch:
	extends Node3D

	var surface := Surface.ASPHALT
	var tan_angle := 0.0
	var lift := 0.0  ## m, a ramp raised by `tilt_ramp`'s `lift`

	func contains_xz(_world_pos: Vector3) -> bool:
		return true

	func height_at(world_pos: Vector3) -> float:
		return lift - world_pos.z * tan_angle

	func grip_at(_world_pos: Vector3, response: PackedFloat32Array) -> float:
		return Surface.grip_in(response, surface)

	func drag_at(_world_pos: Vector3) -> float:
		return Surface.drag(surface)

	func surface_weight_at(_world_pos: Vector3, id: int) -> float:
		return 1.0 if id == surface else 0.0

	func surface_at(_world_pos: Vector3) -> int:
		return surface


## A tool's `tyre=<id>` flag: the id, "" when absent. An id `TyreCatalog` does not know is printed
## as an error and returned as "?", which the tool quits on.
static func tyre_flag(args: PackedStringArray) -> String:
	var id := flag(args, "tyre=").to_lower()
	if id != "" and TyreCatalog.by_id(id) == null:
		printerr("tyre=%s: expected one of %s" % [id, ", ".join(Array(TyreCatalog.CLASSES).map(
				func(p: String) -> String: return p.get_file().get_basename()))])
		return "?"
	return id


## A tool's `wind=<from_deg>:<m/s>` flag as a steady world wind vector: FROM degrees as the
## CONDITIONS page enters them (0 = out of the north, -Z), turned into the heading it blows toward
## as `WorldConditions.wind_for` does. ZERO when absent; a malformed flag is printed as an error
## and returned as NAN, which the tool quits on. The tool's root answers it as `wind_vector()`.
static func wind_flag(args: PackedStringArray) -> Vector3:
	var value := flag(args, "wind=")
	if value == "":
		return Vector3.ZERO
	var parts := value.split(":")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		printerr("wind=%s: expected <from_deg>:<m/s>, e.g. wind=90:9" % value)
		return Vector3(NAN, NAN, NAN)
	return WindField.base_vector(fposmod(float(parts[0]) + 180.0, 360.0), float(parts[1]))


## A tool's `rollsteer=<front>,<rear>` flag: the roll-steer coefficients (deg/deg,
## `GroundDriveSpec.roll_steer_front` / `_rear`; a missing half reads 0). NAN when absent.
static func roll_steer_flag(args: PackedStringArray) -> Vector2:
	var value := flag(args, "rollsteer=")
	if value == "":
		return Vector2(NAN, NAN)
	var pair := value.split(",")
	return Vector2(float(pair[0]) if pair.size() > 0 else 0.0,
			float(pair[1]) if pair.size() > 1 else 0.0)


## A tool's `angdamp=<1/s>` flag: the angular damping `apply_angdamp` declares (0 = none). NAN when
## absent.
static func angdamp_flag(args: PackedStringArray) -> float:
	var figure := float_flag(args, "angdamp=", NAN)
	return figure if is_nan(figure) else maxf(figure, 0.0)


## `rollsteer=` on `body` (in the tree, so its drive is built): the coefficients overridden on a
## copy of its spec, in memory, never shipped, and re-read by its wheels, which cache their axle's
## at build (`RayWheel.apply_suspension`). Axles are paired for a spec that declared no bar or roll
## steer. NAN: the spec's.
static func apply_roll_steer(body: BaseVehicle, coeffs: Vector2) -> void:
	if is_nan(coeffs.x) or body.drive == null:
		return
	var gd := own_ground_drive(body)
	gd.roll_steer_front = coeffs.x
	gd.roll_steer_rear = coeffs.y
	for w in body.drive.wheels:
		w.roll_steer_coeff = gd.roll_steer_rear if w.is_rear else gd.roll_steer_front
	RayWheel.pair_axles(body.drive.wheels)


## A tool's `compliance=<deg/kN>` flag: the rear compliance-steer coefficient
## (`GroundDriveSpec.compliance_steer_rear`). NAN when absent.
static func compliance_flag(args: PackedStringArray) -> float:
	return float_flag(args, "compliance=", NAN)


## `compliance=` on `body` (in the tree, so its drive is built), as `apply_roll_steer`: the
## coefficient overridden on a copy of its spec, in memory, never shipped, re-read by its rear
## wheels, the axles paired. NAN: the spec's.
static func apply_compliance(body: BaseVehicle, coeff: float) -> void:
	if is_nan(coeff) or body.drive == null:
		return
	var gd := own_ground_drive(body)
	gd.compliance_steer_rear = coeff
	for w in body.drive.wheels:
		w.compliance_steer_coeff = gd.compliance_steer_rear if w.is_rear else 0.0
	RayWheel.pair_axles(body.drive.wheels)


## `angdamp=`: the angular damping of `body` and a coupled trailer REPLACEd with `figure` (1/s).
## Call it every tick: a trailer couples after its countdown and a respawn may re-couple it. NAN:
## as the bodies set it.
static func apply_angdamp(body: BaseVehicle, figure: float) -> void:
	if is_nan(figure):
		return
	for b in rig_bodies(body):
		VehicleMath.declare_angular_damp(b, figure)


const PURSUIT_LOOKAHEAD_S := 2.0   ## s of travel to the point the pursuit driver aims at
const PURSUIT_LOOKAHEAD_MIN := 8.0  ## m, its floor at a crawl


## A pure-pursuit driver's steer (-1..1, + = right) holding `body` on the line from `line_o` along
## `line_dir` (unit; a grade's is not level): the bicycle angle `atan(2 L sin α / d)` onto a point
## `d` ahead on the line, over the lock the body's speed leaves it (`WheelDrive.steer_lock_deg`).
## Speed-scaled where a fixed-gain keeper set for a crawl snakes a rig at road speed.
static func pursuit_steer(body: BaseVehicle, line_o: Vector3, line_dir: Vector3) -> float:
	var gd := body.spec.ground_drive
	var wheelbase := body.drive._wheelbase if body.drive != null else 0.0
	if gd == null or wheelbase <= 0.0:
		return 0.0
	var xform := body.global_transform
	var speed := absf(body.linear_velocity.dot(-xform.basis.z))
	var ahead := maxf(PURSUIT_LOOKAHEAD_MIN, PURSUIT_LOOKAHEAD_S * speed)
	var aim := line_o + line_dir * ((xform.origin - line_o).dot(line_dir) + ahead) - xform.origin
	var alpha := atan2(aim.dot(xform.basis.x), aim.dot(-xform.basis.z))
	var lock := deg_to_rad(WheelDrive.steer_lock_deg(gd, speed))
	return clampf(atan(2.0 * wheelbase * sin(alpha) / ahead) / maxf(lock, 1e-6), -1.0, 1.0)


## `body` and its coupled trailer (none: `body` alone), the bodies a run accelerates: a semi couples
## its trailer as a sibling, never a child (`TowHost.couple`).
static func rig_bodies(body: RigidBody3D) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = [body]
	var host := coupled_host(body)
	if host != null and host.trailer != null:
		out.append(host.trailer)
	return out


## The towed mass (kg) coupled to `body` right now (`TowHost.towed_mass_kg`), 0 with nothing coupled.
static func towed_mass(body: Node) -> float:
	var host := coupled_host(body)
	return host.towed_mass_kg() if host != null else 0.0


## `body`'s coupled hitch, or null with nothing coupled.
static func coupled_host(body: Node) -> TowHost:
	for node in body.find_children("*", "", true, false):
		var host := node as TowHost
		if host != null and host.is_coupled():
			return host
	return null


## Fit the `TyreCatalog` class `id` on `body` (in the tree, so its drive is built); "" keeps the
## stock. Returns the id on the wheels, with a note when `id` is not made in the body's `tyre_fit`
## and the stock stayed (`BaseVehicle.fit_tyre`).
static func fit_tyre(body: BaseVehicle, id: String) -> String:
	if body.drive == null:
		return ""
	var gd := body.spec.ground_drive
	if id != "" and not body.fit_tyre(TyreCatalog.by_id(id)):
		return "%s (%s is not made in its fit: stock)" % [_tyre_id(gd.tyre), id]
	return _tyre_id(body.drive.tyre)


static func _tyre_id(cls: TyreClass) -> String:
	return cls.id if cls != null else "reference"


## Hard-road rolling resistance of the tyre on `body`: the fitted class's on a driven body
## (`WheelDrive.rolling_resistance`), the spec's stock on a towed one (it keeps its stock).
static func crr(body: Node) -> float:
	var wheel_drive := body.get("drive") as WheelDrive
	if wheel_drive != null:
		return wheel_drive.rolling_resistance()
	return (body.get("spec") as VehicleSpec).ground_drive.rolling_resistance


## A flat slab of `size` under `parent`, centred at `x` with its top face at y = 0.
static func add_slab(parent: Node, slab_name: String, size: Vector3, x := 0.0) -> void:
	var ground := _box_body(slab_name, size)
	ground.position = Vector3(x, -size.y * 0.5, 0.0)
	parent.add_child(ground)


## A box of `size` under `parent` at `xform` (its centre), on TERRAIN. Returns it, so a pass can
## free it (the kerb pass's plateau).
static func add_box(parent: Node, box_name: String, size: Vector3, xform: Transform3D) -> StaticBody3D:
	var box := _box_body(box_name, size)
	box.transform = xform
	parent.add_child(box)
	return box


## `ramp` (built under `parent` from `size` when null) tilted `angle` rad about +X, so its -Z (the
## body's forward) climbs and its top face passes through (0, `lift`, 0): a long ramp is raised so
## its foot stays above `BaseVehicle.FALL_RESPAWN_Y`. Returns the ramp.
static func tilt_ramp(parent: Node, ramp: StaticBody3D, size: Vector3, angle: float,
		lift := 0.0) -> StaticBody3D:
	if ramp == null:
		ramp = _box_body("Ramp", size)
		parent.add_child(ramp)
	var tilt := Basis(Vector3.RIGHT, angle)
	ramp.transform = Transform3D(tilt, tilt * Vector3(0.0, -size.y * 0.5, 0.0) + Vector3.UP * lift)
	return ramp


## TERRAIN: every gameplay ray masks Layers.SOLID, so an engine-default body would drop the
## vehicle through.
static func _box_body(body_name: String, size: Vector3) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = Layers.DYNAMIC
	body.add_child(collision)
	body.add_child(visual)
	return body


## Laden mass (kg) a variant parks with: the body, plus the trailer a semi spawns coupled to. Read
## off the scenes (`VehicleCatalog.spec_in`), never an instance.
static func rig_mass(variant: String) -> float:
	var mass := Catalog.spec_of(variant).mass
	var tows: bool = Catalog.root_property(Catalog.scene_of(variant), &"script") == SemiTractor
	if tows and TrailerCatalog.is_coupled(TrailerCatalog.first()):
		mass += Catalog.spec_in(TrailerCatalog.first()).mass
	return mass


## Every catalog variant with a driven axle; boat/drone/plane/train declare none.
static func wheel_driven_variants() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.VARIANTS:
		var spec := Catalog.spec_of(id)
		var gd: GroundDriveSpec = spec.ground_drive if spec != null else null
		if gd != null and (gd.driven_front or gd.driven_rear):
			out.append(id)
	return out


## "AWD", "FWD" or "RWD" off the driven axles; a tool adds its own toggles (a tractor's MFWD).
static func layout_label(gd: GroundDriveSpec) -> String:
	return "AWD" if gd.driven_front and gd.driven_rear else ("FWD" if gd.driven_front else "RWD")


## The declared differentials that are not open (`GroundDriveSpec` § Driveline), e.g.
## ", centre 3.0:1, rear LSD 2.5:1"; empty when every diff is open.
static func diff_label(gd: GroundDriveSpec) -> String:
	var label := ""
	if gd.centre_diff_rigid:
		label += ", centre rigid"
	elif gd.centre_diff_bias > 1.0:
		label += ", centre %.1f:1" % gd.centre_diff_bias
	if gd.diff_bias_front > 1.0:
		label += ", front LSD %.1f:1" % gd.diff_bias_front
	if gd.diff_bias_rear > 1.0:
		label += ", rear LSD %.1f:1" % gd.diff_bias_rear
	return label


## "FL", "RR": a wheel of `body`'s by its axle (F / R, or A1, A2... front to back past two axles)
## and side.
static func wheel_label(body: BaseVehicle, w: RayWheel) -> String:
	var axles: Array[float] = []
	for o in body.wheels:
		if not axles.any(func(z: float) -> bool: return is_equal_approx(z, o.anchor.z)):
			axles.append(o.anchor.z)
	axles.sort()
	var i := axles.find_custom(func(z: float) -> bool: return is_equal_approx(z, w.anchor.z))
	var axle := ("F" if i == 0 else "R") if axles.size() == 2 else "A%d" % (i + 1)
	return axle + ("L" if w.anchor.x < 0.0 else "R")


## A RAMN gear byte as the driver reads it: "D3", "R", "N", "P".
static func gear_label(byte: int) -> String:
	if Drivetrain.is_drive(byte):
		return "D%d" % byte
	if Drivetrain.is_reverse(byte):
		return "R"
	return "P" if byte == Drivetrain.GEAR_P else "N"


## One shift as the gates judge it, read on the tick `body`'s byte changed: when (`t`), from and to,
## the road speed, the crank rpm that road speed gives in the gear left (`before`) and the gear taken
## (`land`), unclamped (`Drivetrain.wheel_engine_rpm`; on a CVT both its published rpm), and the
## pedal the shift policy read (`Drivetrain.last_pedal`).
static func shift_record(body: BaseVehicle, t: float, from: int, to: int) -> Dictionary:
	var v: float = body.telemetry.speed
	var road_omega := v / body.drivetrain.road_radius
	var cvt := Drivetrain.is_cvt(body.spec)
	return {"t": t, "from": from, "to": to, "kmh": v * 3.6,
			"before": body.telemetry.rpm if cvt else Drivetrain.wheel_engine_rpm(body.spec, road_omega, from),
			"land": body.telemetry.rpm if cvt else Drivetrain.wheel_engine_rpm(body.spec, road_omega, to),
			"pedal": body.drivetrain.last_pedal}


## "D1>D2 46.1 km/h 5900>3800 rpm, ...": each `shift_record` on road speed, `timed` with its time;
## plus what a tool added to it: a launch's slip ("slip 0.30 s Tc 412": the time until the coupling
## locked and the peak torque it carried at the crank, the shift's handover), a climb's road `load`.
static func shifts_label(shifts: Array, timed := false) -> String:
	var out: Array[String] = []
	for s: Dictionary in shifts:
		var extra := ""
		if s.has("slip_s"):
			extra = " slip %.2f s Tc %.0f" % [s["slip_s"], s["tc_peak"]]
		elif s.has("slip_ticks"):
			extra = " slip open, Tc %.0f" % s["tc_peak"]
		if s.has("load") and not is_nan(float(s["load"])):
			extra += " load %.0f" % s["load"]
		out.append("%s>%s%s %.1f km/h %.0f>%.0f rpm%s" % [gear_label(s["from"]), gear_label(s["to"]),
				" %.2f s" % s["t"] if timed else "", s["kmh"], s["before"], s["land"], extra])
	return ", ".join(out)


## sloppyCAN's inbound stash, written straight into the (desktop-inert) Bridge autoload. Percentages
## are the contract's "in" ranges (`steer` -100..100, + = right); bridge_source normalizes them.
## `gear` is the RAMN byte: 1 is D in the automatic box, D1 under `InputRouter.set_manual_gearbox`.
## `tcs_off` switches the body's traction control off, as the bridge's own flag does. `key` is the
## ignition byte (`InputRouter.KEY_*`); anything but 3 stops the engine and a truck's compressor.
## `extra` overrides or adds inbound keys last (a part `handbrake`, `diff_lock`, `fwd_drive`).
static func drive(accel_pct: float, brake_pct: float, steer_pct := 0.0, handbrake := false,
		gear := 1, tcs_off := false, key := 3, extra := {}) -> void:
	var inbound := {
		"key": key, "gear": gear, "accel": accel_pct, "brake": brake_pct,
		"steer": steer_pct, "handbrake": 1.0 if handbrake else 0.0, "tcs_off": tcs_off,
	}
	inbound.merge(extra, true)
	Bridge.set("_active", true)
	Bridge.set("_inbound", inbound)
