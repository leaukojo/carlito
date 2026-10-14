extends RefCounted
## What the game-mode measure tools share: the flat full-grip slab a body is driven on and the
## bridge stash it is driven through. Each tool keeps its own layout (strip, pad) and pass logic.

const Layers := preload("res://src/physics/collision_layers.gd")


## A flat slab of `size` under `parent`, centred at `x` with its top face at y = 0. TERRAIN: every
## gameplay ray masks Layers.SOLID, so an engine-default body would drop the vehicle through.
static func add_slab(parent: Node, slab_name: String, size: Vector3, x := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var ground := StaticBody3D.new()
	ground.name = slab_name
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = Layers.DYNAMIC
	ground.position = Vector3(x, -size.y * 0.5, 0.0)
	ground.add_child(collision)
	ground.add_child(visual)
	parent.add_child(ground)


## sloppyCAN's inbound stash, written straight into the (desktop-inert) Bridge autoload. Percentages
## are the contract's "in" ranges (`steer` -100..100, + = right); bridge_source normalizes them.
## `gear` is the RAMN byte: 1 is D in the automatic box, D1 under `InputRouter.set_manual_gearbox`.
## `tcs_off` switches the body's traction control off, as the bridge's own flag does. `key` is the
## ignition byte (`InputRouter.KEY_*`); anything but 3 stops the engine and a truck's compressor.
static func drive(accel_pct: float, brake_pct: float, steer_pct := 0.0, handbrake := false,
		gear := 1, tcs_off := false, key := 3) -> void:
	Bridge.set("_active", true)
	Bridge.set("_inbound", {
		"key": key, "gear": gear, "accel": accel_pct, "brake": brake_pct,
		"steer": steer_pct, "handbrake": 1.0 if handbrake else 0.0, "tcs_off": tcs_off,
	})
