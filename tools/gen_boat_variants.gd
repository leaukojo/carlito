extends Node
## Generator for the Watercraft Pack boat variants: writes
## src/vehicles/watercraft/<variant>.tscn + <variant>_spec.tres. Deterministic and
## re-runnable, the regen path after a scale/feel change. Model origin sits at the
## resting waterline. Collision is hand-authored (CollisionLower/CollisionUpper box pairs)
## and transplanted verbatim on regen; only a variant with no scene yet gets a generated
## convex hull. Game-mode tool scene, not --script: boat.gd needs the InputRouter/
## Bridge autoloads to compile.

const VehicleGenIO := preload("res://tools/vehicle_gen_io.gd")
const OUT_DIR := "res://src/vehicles/watercraft"
const MODELS := "res://kit/raw/watercraft"   ## raw glbs; the packed .tscn embeds the
## meshes, so the glb is export-excluded and not needed at runtime.
const BOAT_SCRIPT := "res://src/vehicles/boat/boat.gd"
## Direct children this generator writes and may replace on regen. Everything else in the scene
## is hand-authored and transplanted (see VehicleGenIO.existing_children): the collision box pair.
const GENERATED_CHILDREN := ["Model", "Lamps"]

const BOAT_SCALE := 1.2  ## Kenney kit scale: speed-a lands at 2.1 m beam x 4.0 m LOA
## against the 1.8 m car. Not the recipe's prop scale of 2.0.
## GLB node names (lowercase) excluded from hull measurement and collision shape.
const EXCLUDE_COLLISION := ["sail"]

# Baseline spec (src/vehicles/boat/boat_spec.tres). Ground drive declared empty; all 6
# gear_ratios kept since auto_shift indexes up to byte 6 regardless.
const BOAT_BASE := {
	"torque_curve": [800, 120, 2500, 200, 4200, 210, 5200, 90],
	"idle_rpm": 800.0, "redline_rpm": 5200.0,
	# The motoring law the burn nets out at idle (`Drivetrain.drag_fuel`): the car-petrol class
	# figure (docs/drivetrain.md § Motoring and friction), an estimate for an outboard.
	"engine_friction_frac": 0.07, "engine_brake_frac": 0.25,
	"gear_ratios": [2.6, 1.9, 1.4, 1.05, 0.8, 0.62], "reverse_ratio": 2.0,
	"final_drive": 2.1, "efficiency": 0.9, "shift_up_rpm": 4400.0, "shift_down_rpm": 1800.0,
	# The part-pedal shift policy (`ShiftPolicy`) declared neutral: the full-pedal pair at any pedal.
	"shift_up_light_rpm": 0.0, "shift_down_light_rpm": 0.0, "kickdown_pedal": 0.0,
	"shift_dwell_s": 0.0, "skip_shifts": false, "shift_handover_s": 0.0, "start_gear_max": 0,
	"steer_speed": 2.2,
}

## Hull drag numbers include each hull's own `mass * 0.1` folded into drag_lat and a planing hull's drag_long; drop it and top speed gains ~20%.
##
## variant id -> overrides. draft_frac is share of hull height below the waterline. A planing
## hull (`drag_sq` and `waterline_length` 0) tops out at thrust_force / drag_long m/s; a
## displacement hull's forward drag is `BoatVehicle.wave_drag_sq` (docs/boat.md § Hull drag).
const VARIANTS := {
	# light and quick: least mass, eager rudder, modest power
	"boat-speed-a": {
		"mass": 600.0, "torque_mul": 1.0, "draft_frac": 0.22, "float_depth": 0.30,
		"thrust_force": 5200.0, "drag_long": 360.0, "drag_lat": 2060.0, "drag_yaw": 3800.0,
		"drag_sq": 0.0, "waterline_length": 0.0,
		"rudder_torque": 6500.0, "keel_extra": 0.15, "com_frac": 0.8,
		"steer_speed": 2.8,
		"sail_area": 0.0, "sail_center": Vector3.ZERO, "sheet_max_deg": 0.0,
	},
	# heavy and powerful: faster flat out, but slow to spin up and slow to turn
	"boat-speed-j": {
		"mass": 1400.0, "torque_mul": 1.6, "draft_frac": 0.26, "float_depth": 0.34,
		"thrust_force": 11000.0, "drag_long": 660.0, "drag_lat": 4340.0, "drag_yaw": 12000.0,
		"drag_sq": 0.0, "waterline_length": 0.0,
		"rudder_torque": 11000.0, "keel_extra": 0.25, "com_frac": 0.8,
		"steer_speed": 1.6,
		"sail_area": 0.0, "sail_center": Vector3.ZERO, "sheet_max_deg": 0.0,
	},
	# sailboat: the RIG is the drive (BoatSail) and the outboard is auxiliary. A displacement
	# hull: `drag_sq` 24 under the wave wall of a 4.1 m waterline (an estimate, ~0.9 of the 4.52 m
	# LOA; hull speed 2.54 m/s), `drag_long` 40 the low-speed floor. 500 N, a ~5 hp outboard on a
	# 4.5 m, 500 kg hull, tops out at 2.66 m/s (5.2 kt), just over hull speed; a 9 m/s beam reach
	# settles at ~3.1 m/s (1.24x), both pinned by test_boat_variants. A linear hull lets the rig,
	# which grows with the wind squared, run away (5.9 m/s on that reach). Deep keel and slippery
	# flanks are what turn the rig's side force into leeway rather than a slide.
	"boat-sail-a": {
		"mass": 500.0, "torque_mul": 0.55, "draft_frac": 0.20, "float_depth": 0.28,
		"thrust_force": 500.0, "drag_long": 40.0, "drag_lat": 1250.0, "drag_yaw": 3200.0,
		"drag_sq": 24.0, "waterline_length": 4.1,
		"rudder_torque": 4200.0, "keel_extra": 0.60, "com_frac": 0.3,
		"steer_speed": 2.0,
		# 14 m^2 on a 4.52 m LOA / 2.14 m beam hull, the centre of effort 2.0 m above the
		# waterline (the COM sits 0.12 below it, so that is the heeling lever) and 0.25 m abaft
		# the mast. 90 deg of boom travel is what makes a dead run pure drag.
		"sail_area": 14.0, "sail_center": Vector3(0.0, 2.0, 0.25), "sheet_max_deg": 90.0,
		# The GLB's own sail mesh, the node EXCLUDE_COLLISION already keeps out of the hull.
		"sail_pivot": "Model/boat-sail-a/sail",
	},
}

var _shape_report: Array = []  ## per-variant collision shape kind + hull vertex count


func _ready() -> void:
	var boat_script := load(BOAT_SCRIPT)
	var ok := 0
	for variant: String in VARIANTS:
		var ov: Dictionary = VARIANTS[variant]
		var geo := _analyze(MODELS.path_join(variant + ".glb"), float(ov["draft_frac"]))
		if geo.is_empty():
			continue
		if VehicleGenIO.write_variant(OUT_DIR, variant, _build_spec(ov, geo),
				func(s: VehicleSpec) -> PackedScene:
					return _build_scene(variant, boat_script, s, ov, geo)):
			ok += 1
	print("gen_boat_variants: wrote %d/%d variants" % [ok, VARIANTS.size()])
	print("collision shapes: ", ", ".join(_shape_report))
	get_tree().quit(0 if ok == VARIANTS.size() else 1)


# --- spec ------------------------------------------------------------------------------

func _build_spec(ov: Dictionary, geo: Dictionary) -> VehicleSpec:
	var spec := VehicleSpec.new()
	spec.mass = float(ov["mass"])
	# COM below the waterline (origin), as a share of the draft: the boats' righting moment.
	spec.center_of_mass = Vector3(0, -float(geo["draft"]) * float(ov["com_frac"]), 0)
	# No ground drive: the gear byte it still publishes is scaled by Drivetrain.DEFAULT_ROAD_RADIUS.
	spec.torque_curve = VehicleGenIO.scaled_curve(BOAT_BASE["torque_curve"], float(ov["torque_mul"]))
	spec.idle_rpm = float(BOAT_BASE["idle_rpm"])
	spec.redline_rpm = float(BOAT_BASE["redline_rpm"])
	spec.engine_friction_frac = float(BOAT_BASE["engine_friction_frac"])
	spec.engine_brake_frac = float(BOAT_BASE["engine_brake_frac"])
	spec.gear_ratios = PackedFloat32Array(BOAT_BASE["gear_ratios"])
	spec.reverse_ratio = float(BOAT_BASE["reverse_ratio"])
	spec.final_drive = float(BOAT_BASE["final_drive"])
	spec.efficiency = float(BOAT_BASE["efficiency"])
	spec.shift_up_rpm = float(BOAT_BASE["shift_up_rpm"])
	spec.shift_down_rpm = float(BOAT_BASE["shift_down_rpm"])
	spec.shift_up_light_rpm = float(BOAT_BASE["shift_up_light_rpm"])
	spec.shift_down_light_rpm = float(BOAT_BASE["shift_down_light_rpm"])
	spec.kickdown_pedal = float(BOAT_BASE["kickdown_pedal"])
	spec.shift_dwell_s = float(BOAT_BASE["shift_dwell_s"])
	spec.skip_shifts = bool(BOAT_BASE["skip_shifts"])
	spec.shift_handover_s = float(BOAT_BASE["shift_handover_s"])
	spec.start_gear_max = int(BOAT_BASE["start_gear_max"])
	# No max_steer_deg; `rudder_torque` turns the hull, `steer_speed` slews the rudder axis.
	spec.steer_speed = float(ov.get("steer_speed", BOAT_BASE["steer_speed"]))
	spec.headlight_paths.assign([NodePath("Lamps/Headlight")])
	return spec


# --- scene -----------------------------------------------------------------------------

func _build_scene(variant: String, scene_script: Variant, spec: VehicleSpec,
		ov: Dictionary, geo: Dictionary) -> PackedScene:
	var hull: AABB = geo["hull"]      # hull-only box, body space, origin at the waterline
	var loa := hull.size.z
	var beam := hull.size.x
	var draft := float(geo["draft"])
	var float_depth := float(ov["float_depth"])

	var root := RigidBody3D.new()
	root.name = variant.to_pascal_case()
	root.set_script(scene_script)
	root.set("spec", spec)

	# Buoyancy: four probes at the hull quarters, float_depth below the waterline.
	root.set("probe_points", PackedVector3Array([
		Vector3(-beam * 0.42, -float_depth, -loa * 0.40),
		Vector3(beam * 0.42, -float_depth, -loa * 0.40),
		Vector3(-beam * 0.42, -float_depth, loa * 0.40),
		Vector3(beam * 0.42, -float_depth, loa * 0.40),
	]))
	root.set("float_depth", float_depth)
	# Outdrive at the stern (+Z after the 180 deg flip), below the waterline.
	root.set("prop_offset", Vector3(0, -draft * 0.6, loa * 0.45))
	root.set("thrust_force", float(ov["thrust_force"]))
	root.set("rudder_torque", float(ov["rudder_torque"]))
	root.set("drag_long", float(ov["drag_long"]))
	root.set("drag_sq", float(ov["drag_sq"]))
	root.set("waterline_length", float(ov["waterline_length"]))
	root.set("drag_lat", float(ov["drag_lat"]))
	root.set("drag_yaw", float(ov["drag_yaw"]))
	root.set("keel_offset", -(draft + float(ov["keel_extra"])))
	# The rig, declared rather than derived: a sail plan is a designer's choice, not something the
	# hull AABB implies, and `sail_area` 0 is how the two powerboats say they have none.
	root.set("sail_area", float(ov["sail_area"]))
	root.set("sail_center", ov["sail_center"] as Vector3)
	root.set("sheet_max_deg", float(ov["sheet_max_deg"]))
	root.set("sail_pivot", NodePath(String(ov.get("sail_pivot", ""))))

	var kept := VehicleGenIO.existing_children(OUT_DIR, variant, GENERATED_CHILDREN)
	VehicleGenIO.add_collision(root, variant, kept["collision"], _body_shape.bind(variant, geo),
			_shape_report)

	# Body model: GLB children stolen into a Model node (180 deg Y flip, kit scale, centring, waterline drop).
	VehicleGenIO.steal_model(root, MODELS.path_join(variant + ".glb"), geo["xform"])

	var lamps := Node3D.new()
	lamps.name = "Lamps"
	VehicleGenIO.add(root, root, lamps)
	VehicleGenIO.add(root, lamps, VehicleGenIO.headlight("Headlight",
			Vector3(0, hull.size.y * 0.15, -loa * 0.45)))

	# Hand-authored children (e.g. "HoodCam"), transplanted last to match editor child order.
	for extra: Node in kept["extras"]:
		VehicleGenIO.add(root, root, extra)

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Convex hull of the HULL meshes (rigging excluded); box fallback if degenerate.
func _body_shape(variant: String, geo: Dictionary) -> Dictionary:
	var shape := VehicleGenIO.hull_shape(geo["hull_pairs"], geo["xform"])
	if shape != null:
		_shape_report.append("%s=hull(%d)" % [variant, shape.points.size()])
		return {"shape": shape, "pos": Vector3.ZERO}
	push_warning("%s: convex hull degenerate, falling back to box" % variant)
	var hull: AABB = geo["hull"]
	var box := BoxShape3D.new()
	box.size = hull.size
	_shape_report.append("%s=box" % variant)
	return {"shape": box, "pos": hull.get_center()}


# --- geometry --------------------------------------------------------------------------

## Analyse a Watercraft GLB into geometry the spec/scene builders share:
##   xform:      body-model transform — 180 deg Y flip (pack +Z bow -> project -Z) + kit
##               scale + x/z centring on the hull, dropped so y = 0 is the waterline
##   hull:       hull-only AABB after xform (probe/prop/lamp placement, box fallback)
##   hull_pairs: [Mesh, native transform] for the hull meshes (collision hull source)
##   draft:      metres of hull below the waterline
func _analyze(path: String, draft_frac: float) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("cannot load " + path)
		return {}
	var inst := scene.instantiate()
	var hull_pairs: Array = []
	_collect_hull(inst, Transform3D.IDENTITY, hull_pairs)
	inst.free()
	if hull_pairs.is_empty():
		push_error(path + ": no hull meshes")
		return {}

	var native := AABB()
	var first := true
	for pair: Array in hull_pairs:
		for v in (pair[0] as Mesh).get_faces():
			var p: Vector3 = (pair[1] as Transform3D) * v
			if first:
				native = AABB(p, Vector3.ZERO)
				first = false
			else:
				native = native.expand(p)

	var c := native.get_center()
	var draft := draft_frac * native.size.y * BOAT_SCALE
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * BOAT_SCALE)
	# native y = 0 is the hull bottom; drop the model by the draft so y = 0 is the waterline.
	var xform := Transform3D(basis, Vector3(
			BOAT_SCALE * c.x, -BOAT_SCALE * native.position.y - draft, BOAT_SCALE * c.z))
	return {"xform": xform, "hull_pairs": hull_pairs, "draft": draft,
			"hull": xform * native}


## Collect hull mesh pairs; EXCLUDE_COLLISION subtrees are skipped.
func _collect_hull(node: Node, xform: Transform3D, hull_pairs: Array) -> void:
	if String(node.name).to_lower() in EXCLUDE_COLLISION:
		return
	var nx := xform
	if node is Node3D:
		nx = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		hull_pairs.append([(node as MeshInstance3D).mesh, nx])
	for child in node.get_children():
		_collect_hull(child, nx, hull_pairs)
