extends Node
## Author the rough-ground dev level: an unregistered island whose only content is two lanes of
## rising unevenness, asphalt and mud, for measuring traction off flat ground
## (`tools/measure_rough.tscn`). Every position lives in `rough_ground_layout.gd`, shared with that
## tool. Writes the heightmap, both splats, the LevelInfo and the level .tscn text, overwriting
## all of them; chain recorded in src/levels/dev/rough_ground/rough_ground_gen.json
## (tools/CLAUDE.md). No roads, props or scatter, so there is nothing to bake.
##
##   godot --headless --path . res://tools/gen_rough_ground.tscn
##   godot --headless --path . --import

const Layout := preload("res://tools/rough_ground_layout.gd")

const DIR := "res://src/levels/dev/rough_ground"
const HEIGHT_PNG := DIR + "/rough_ground_height.png"
const SPLAT_PNG := DIR + "/rough_ground_splat.png"
const SPLAT2_PNG := DIR + "/rough_ground_splat2.png"
const INFO_PATH := DIR + "/rough_ground_info.tres"
const TITLE := "Rough Ground (dev)"

## Channel table: level 1's, so the lanes are the same asphalt and mud a shipped island paints
## and `measure_grade.gd`'s SURFACES name the same (grip, crr) pairs.
const CHANNEL_NAMES: Array[String] = [
	"Grass", "Dirt", "Sand", "Rock", "Field", "Mud", "Asphalt", "Gravel",
]
const CHANNEL_GRIP: Array[float] = [0.8, 0.7, 0.6, 0.7, 0.7, 0.5, 1.0, 0.85]
const CHANNEL_DRAG: Array[float] = [0.06, 0.03, 0.1, 0.01, 0.08, 0.2, 0.0, 0.02]
const CH_GRASS := 0
const CH_SAND := 2
## Land below this is beach.
const SAND_BELOW := Layout.SEA_Y + 0.6
## Lane paint runs this far past the spawn and past the last patch.
const LANE_MARGIN := 12.0
const SPAWN_CLEARANCE := 0.6


func _ready() -> void:
	get_tree().quit(_scaffold())


func _scaffold() -> int:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cells := int(Layout.SIZE) + 1
	# Raw L8 bytes rather than set_pixel: a Color round-trip can land a step one below its value.
	var height_bytes := PackedByteArray()
	height_bytes.resize(cells * cells)
	var splat := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	var splat2 := Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	splat2.fill(Color(0, 0, 0, 0))
	var lane_north := Layout.patch_end_z(Layout.PATCHES.size() - 1) - LANE_MARGIN
	var lane_south := Layout.patch_start_z(0) + Layout.RUN_UP + LANE_MARGIN
	var lowest := INF
	var highest := -INF
	for pz in cells:
		var z := _world(pz)
		for px in cells:
			var x := _world(px)
			var y := _island_y(x, z)
			for lane: Dictionary in Layout.LANES:
				for i in Layout.PATCHES.size():
					y += Layout.relief(i, x - float(lane["x"]), z)
			var step := clampi(roundi(y / Layout.HEIGHT * 255.0), 0, 255)
			height_bytes[pz * cells + px] = step
			var stored := float(step) / 255.0 * Layout.HEIGHT
			if Vector2(x, z).length() <= Layout.PLATEAU_R:
				lowest = minf(lowest, stored)
				highest = maxf(highest, stored)
			var base := Color(0, 0, 0, 0)
			base[CH_SAND if stored < SAND_BELOW else CH_GRASS] = 1.0
			splat.set_pixel(px, pz, base)
			if z < lane_north or z > lane_south:
				continue
			for lane: Dictionary in Layout.LANES:
				if absf(x - float(lane["x"])) <= Layout.LANE_WIDTH * 0.5:
					# A lane pixel is ONLY its lane's channel: a leftover grass weight would blend
					# grip at the edge, and the measurement drives the lane's centre anyway.
					splat.set_pixel(px, pz, Color(0, 0, 0, 0))
					var paint := Color(0, 0, 0, 0)
					paint[int(lane["channel"]) - 4] = 1.0
					splat2.set_pixel(px, pz, paint)
	if lowest <= Layout.SEA_Y:
		printerr("[rough-ground] a patch reaches the sea (lowest %.3f m)" % lowest)
		return 1
	print("[rough-ground] plateau spans %.3f .. %.3f m" % [lowest, highest])
	for i in Layout.PATCHES.size():
		print("[rough-ground]   %-9s z %7.1f .. %7.1f" % [Layout.PATCHES[i]["name"],
				Layout.patch_start_z(i), Layout.patch_end_z(i)])
	var heights := Image.create_from_data(cells, cells, false, Image.FORMAT_L8, height_bytes)
	if not _write_png(heights, HEIGHT_PNG):
		return 1
	if not _write_png(splat, SPLAT_PNG):
		return 1
	if not _write_png(splat2, SPLAT2_PNG):
		return 1
	_write_text(INFO_PATH, _info_text())
	_write_text(Layout.LEVEL_PATH, _scene_text())
	print("[rough-ground] done. Run --import.")
	return 0


## The island with no patches: the plateau disc, smoothstepped down to the seabed round its rim.
func _island_y(x: float, z: float) -> float:
	var t := (Vector2(x, z).length() - Layout.PLATEAU_R) / Layout.PLATEAU_BLEND
	var c := clampf(t, 0.0, 1.0)
	return Layout.PLATEAU_Y * (1.0 - c * c * (3.0 - 2.0 * c))


## HeightmapTerrain's own convention at one cell per metre, the terrain at the origin.
func _world(p: int) -> float:
	return float(p) - Layout.SIZE * 0.5


func _info_text() -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo" format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("car", "truck", "tractor")
default_vehicle = "car"
""" % TITLE


func _scene_text() -> String:
	var spawn := Transform3D(Basis.IDENTITY, Vector3(float(Layout.LANES[0]["x"]),
			Layout.PLATEAU_Y + SPAWN_CLEARANCE, Layout.patch_start_z(0) + Layout.RUN_UP))
	var extent := Layout.SIZE + 48.0
	return """[gd_scene format=3]

[ext_resource type="Script" path="res://src/levels/base/level.gd" id="1_level"]
[ext_resource type="Resource" path="{info}" id="2_info"]
[ext_resource type="Script" path="res://src/vehicles/base/chase_camera.gd" id="3_cam"]
[ext_resource type="Script" path="res://src/levels/base/vehicle_spawn.gd" id="4_spawn"]
[ext_resource type="Script" path="res://src/levels/base/heightmap_terrain.gd" id="5_terrain"]
[ext_resource type="Texture2D" path="{height_png}" id="6_height"]
[ext_resource type="Texture2D" path="{splat_png}" id="7_splat"]
[ext_resource type="Texture2D" path="{splat2_png}" id="8_splat2"]
[ext_resource type="Shader" path="res://kit/terrain/terrain_splat.gdshader" id="9_shader"]
[ext_resource type="Script" path="res://src/water/water_surface.gd" id="10_water"]
[ext_resource type="Script" path="res://src/levels/base/world_bounds.gd" id="11_bounds"]
[ext_resource type="Environment" path="res://src/levels/base/default_env.tres" id="12_env"]

[sub_resource type="PlaneMesh" id="SeaBedMesh"]
size = Vector2({extent}, {extent})

[sub_resource type="StandardMaterial3D" id="SeaBedMat"]
albedo_color = Color(0.83, 0.76, 0.55, 1)

[sub_resource type="ShaderMaterial" id="SplatMat"]
shader = ExtResource("9_shader")
shader_parameter/grass_color = Color(0.35, 0.55, 0.25, 1)
shader_parameter/dirt_color = Color(0.52, 0.4, 0.26, 1)
shader_parameter/sand_color = Color(0.83, 0.76, 0.55, 1)
shader_parameter/rock_color = Color(0.45, 0.44, 0.42, 1)
shader_parameter/color5 = Color(0.44, 0.29, 0.17, 1)
shader_parameter/color6 = Color(0.3, 0.24, 0.17, 1)
shader_parameter/color7 = Color(0.22, 0.22, 0.24, 1)
shader_parameter/color8 = Color(0.62, 0.6, 0.56, 1)
shader_parameter/splatmap = ExtResource("7_splat")
shader_parameter/splatmap2 = ExtResource("8_splat2")
shader_parameter/blend_sharpness = 8.0
shader_parameter/roughness_value = 1.0

[node name="RoughGround" type="Node3D"]
script = ExtResource("1_level")
info = ExtResource("2_info")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = ExtResource("12_env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, 0.354, -0.354, 0, 0.707, 0.707, 0.5, -0.612, 0.612, 0, 40, 0)
light_color = Color(1, 0.96, 0.88, 1)
shadow_enabled = true
directional_shadow_mode = 0
directional_shadow_max_distance = 150.0

[node name="ChaseCamera" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 6)
script = ExtResource("3_cam")

[node name="Spawn" type="Marker3D" parent="."]
transform = {spawn}
script = ExtResource("4_spawn")

[node name="Sea" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {sea_y}, 0)
script = ExtResource("10_water")
size = Vector2({extent}, {extent})
depth = {sea_y}
far_sea_extent = 1900.0

[node name="Bounds" type="StaticBody3D" parent="."]
script = ExtResource("11_bounds")
extent = Vector2({extent}, {extent})

[node name="SeaBed" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.01, 0)
mesh = SubResource("SeaBedMesh")
surface_material_override/0 = SubResource("SeaBedMat")

[node name="Island" type="StaticBody3D" parent="."]
script = ExtResource("5_terrain")
heightmap = ExtResource("6_height")
terrain_size = Vector2({size}, {size})
height = {height}
material = SubResource("SplatMat")
splatmap = ExtResource("7_splat")
splatmap2 = ExtResource("8_splat2")
channel_names = PackedStringArray({channel_names})
channel_grip = PackedFloat32Array({channel_grip})
channel_drag = PackedFloat32Array({channel_drag})
sand_height = {sand_height}
""".format({
		"info": INFO_PATH, "height_png": HEIGHT_PNG, "splat_png": SPLAT_PNG,
		"splat2_png": SPLAT2_PNG, "extent": extent, "size": Layout.SIZE,
		"height": Layout.HEIGHT, "sea_y": Layout.SEA_Y, "sand_height": SAND_BELOW,
		"channel_names": '"%s"' % '", "'.join(CHANNEL_NAMES),
		"channel_grip": ", ".join(PackedStringArray(
				CHANNEL_GRIP.map(func(g: float) -> String: return str(g)))),
		"channel_drag": ", ".join(PackedStringArray(
				CHANNEL_DRAG.map(func(g: float) -> String: return str(g)))),
		"spawn": var_to_str(spawn),
	})


func _write_png(img: Image, path: String) -> bool:
	if img.save_png(path) != OK:
		printerr("[rough-ground] failed to write %s" % path)
		return false
	TerrainGen.ensure_import_settings(path)
	print("[rough-ground] wrote %s" % path)
	return true


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[rough-ground] cannot write %s" % path)
		return
	f.store_string(text)
	print("[rough-ground] wrote %s" % path)
