extends RefCounted
## What the game-mode measure tools share: the flat full-grip slab or tilted ramp a body is driven
## on, the painted surface over it, the tyre class on the body, a rig's laden mass, and the bridge
## stash it is driven through. Each tool keeps its own layout (strip, pad) and pass logic.

const Catalog := preload("res://src/vehicles/vehicle_catalog.gd")
const Layers := preload("res://src/physics/collision_layers.gd")


## One `Surface` everywhere, over a slab or a ramp: the duck-typed contract `HeightmapTerrain`
## answers (`BaseVehicle._collect_grip_terrains`), nothing more. `height_at` is the plane through
## the origin rising `tan_angle` toward -Z, so `RayWheel.terrain_at`'s reach finds it anywhere on a
## climb. A body finds its terrains once: add the patch before its first tick, then change
## `surface` in place.
class GripPatch:
	extends Node3D

	var surface := Surface.ASPHALT
	var tan_angle := 0.0

	func contains_xz(_world_pos: Vector3) -> bool:
		return true

	func height_at(world_pos: Vector3) -> float:
		return -world_pos.z * tan_angle

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
	for a in args:
		if a.begins_with("tyre="):
			var id := a.substr(5).to_lower()
			if TyreCatalog.by_id(id) == null:
				printerr("tyre=%s: expected one of %s" % [id, ", ".join(Array(TyreCatalog.CLASSES).map(
						func(p: String) -> String: return p.get_file().get_basename()))])
				return "?"
			return id
	return ""


## Fit the `TyreCatalog` class `id` on `body` (in the tree, so its drive is built); "" keeps the
## stock. Returns the id on the wheels, with a note when `id` is not made in the body's `tyre_fit`
## and the stock stayed (`WheelDrive.fit_tyre`).
static func fit_tyre(body: BaseVehicle, id: String) -> String:
	if body.drive == null:
		return ""
	var gd := body.spec.ground_drive
	if id != "" and not body.drive.fit_tyre(gd, TyreCatalog.by_id(id)):
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
## body's forward) climbs and its top face passes through the origin. Returns the ramp.
static func tilt_ramp(parent: Node, ramp: StaticBody3D, size: Vector3, angle: float) -> StaticBody3D:
	if ramp == null:
		ramp = _box_body("Ramp", size)
		parent.add_child(ramp)
	var tilt := Basis(Vector3.RIGHT, angle)
	ramp.transform = Transform3D(tilt, tilt * Vector3(0.0, -size.y * 0.5, 0.0))
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


## Laden mass (kg) a variant parks with: the body, plus the trailer a semi spawns coupled to.
static func rig_mass(variant: String) -> float:
	var body: Node = (load(Catalog.VARIANTS[variant]["scene"]) as PackedScene).instantiate()
	var mass: float = (body.get("spec") as VehicleSpec).mass
	var tows := body is SemiTractor
	body.free()
	if tows and TrailerCatalog.is_coupled(TrailerCatalog.first()):
		var trailer: Node = (load(TrailerCatalog.first()) as PackedScene).instantiate()
		mass += (trailer.get("spec") as VehicleSpec).mass
		trailer.free()
	return mass


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
