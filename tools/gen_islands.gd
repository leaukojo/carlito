@tool
extends SceneTree
## Generates the blank-canvas island levels (level_2 .. level_4): heightmap PNG,
## auto-splat PNG, LevelInfo and the level scene, all deterministic from the seeds
## below. Re-running overwrites them — hand-authored content added afterwards
## (AuthoringRoot children) would be lost, so this is a one-shot scaffolding tool,
## not part of the bake pipeline.
##
## DO NOT RE-RUN AS IT STANDS. Levels 2 and 3 have since gained hand-added PlaneSpawn
## nodes and allow-lists this template does not write, so a re-run silently deletes them.
## Level 5 has left this tool entirely: tools/gen_rail_level.gd owns it now — it is the
## rail level, and its terrain has to be conformed to the loop, which this template has
## no notion of.
##
##   godot --headless --path . --script res://tools/gen_islands.gd
##   godot --headless --path . --import      # then re-import the fresh PNGs

const SIZE := 512.0          ## world extent (X and Z) — matches level_1
const HEIGHT := 51.0         ## white-pixel amplitude; stores the 3 m road levels exactly
const CHANNEL_NAMES := '"Grass", "Dirt", "Sand", "Rock", "Snow", "Mud", "Asphalt", "Gravel"'
const CHANNEL_GRIP := "0.8, 0.7, 0.6, 0.7, 0.75, 0.5, 1, 0.85"

const LEVELS := [
	{
		"id": "level_2", "title": "Level 2 - Bay Islands",
		"seed": 20025, "feature_scale": 180.0, "octaves": 4,
		"falloff_start": 0.65, "falloff_end": 0.88, "coast_roughness": 0.70,
		"terrace_levels": 3,
	},
	{
		"id": "level_3", "title": "Level 3 - Highlands",
		"seed": 30037, "feature_scale": 320.0, "octaves": 3,
		"falloff_start": 0.78, "falloff_end": 0.95, "coast_roughness": 0.25,
		"terrace_levels": 4,
	},
	{
		"id": "level_4", "title": "Level 4 - Archipelago",
		"seed": 40041, "feature_scale": 140.0, "octaves": 5,
		"falloff_start": 0.60, "falloff_end": 0.92, "coast_roughness": 0.90,
		"terrace_levels": 3,
	},
]


func _init() -> void:
	for cfg: Dictionary in LEVELS:
		_build(cfg)
	print("gen_islands: done. Run --import next.")
	quit()


func _build(cfg: Dictionary) -> void:
	var id: String = cfg["id"]
	var dir := "res://src/levels/island/%s" % id
	DirAccess.make_dir_recursive_absolute(dir)

	var cells := int(SIZE) + 1
	var heights := TerrainGen.generate_heights(TerrainGen.Preset.ISLAND, cfg["seed"],
			cfg["feature_scale"], cfg["octaves"], cfg["falloff_start"], cfg["falloff_end"],
			cells, cells, float(cfg["terrace_levels"]) * 3.0 / HEIGHT, 0.6,
			cfg["coast_roughness"])
	var px := SIZE / float(cells - 1)
	var splat := TerrainGen.build_splatmap(heights, HEIGHT, px, px, 2.0, 22.0, 38.0)

	_write_png(heights, "%s/%s_island_height.png" % [dir, id])
	_write_png(splat, "%s/%s_island_splat.png" % [dir, id])

	var spawn := _find_land_spawn(heights, cells)
	_write_text("%s/%s_info.tres" % [dir, id], _info_text(cfg["title"]))
	_write_text("%s/%s.tscn" % [dir, id], _scene_text(cfg, spawn))
	print("gen_islands: %s spawn at %v" % [id, spawn])


func _write_png(img: Image, path: String) -> void:
	var err := img.save_png(path)
	assert(err == OK, "save_png failed for %s" % path)
	TerrainGen.ensure_import_settings(path)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % path)
	f.store_string(text)


## Picks a flat, comfortably-above-sea cell nearest the map centre for the car spawn:
## the generated coastline is ragged, so a fixed marker would sometimes land in water.
func _find_land_spawn(img: Image, cells: int) -> Vector3:
	var best := Vector3(0, HEIGHT * 0.5, 0)
	var best_d := INF
	var mid := float(cells - 1) * 0.5
	for y in range(1, cells - 1, 4):
		for x in range(1, cells - 1, 4):
			var h := img.get_pixel(x, y).r * HEIGHT
			if h < 6.0 or h > HEIGHT * 0.55:
				continue
			var slope := absf(img.get_pixel(x + 1, y).r - img.get_pixel(x - 1, y).r) \
					+ absf(img.get_pixel(x, y + 1).r - img.get_pixel(x, y - 1).r)
			if slope * HEIGHT > 0.5:
				continue
			var d := Vector2(x - mid, y - mid).length()
			if d < best_d:
				best_d = d
				best = Vector3((x / mid - 1.0) * SIZE * 0.5, h + 1.5,
						(y / mid - 1.0) * SIZE * 0.5)
	return best


func _info_text(title: String) -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("car", "truck", "tractor", "boat")
default_vehicle = "car"
""" % title


func _scene_text(cfg: Dictionary, spawn: Vector3) -> String:
	var id: String = cfg["id"]
	var node_name := id.to_pascal_case()
	return """[gd_scene load_steps=11 format=3]

[ext_resource type="Script" path="res://src/levels/base/level.gd" id="1_level"]
[ext_resource type="Resource" path="res://src/levels/island/{id}/{id}_info.tres" id="2_info"]
[ext_resource type="Script" path="res://src/vehicles/base/chase_camera.gd" id="3_cam"]
[ext_resource type="Script" path="res://src/levels/base/vehicle_spawn.gd" id="4_spawn"]
[ext_resource type="Script" path="res://src/levels/base/heightmap_terrain.gd" id="5_terrain"]
[ext_resource type="Texture2D" path="res://src/levels/island/{id}/{id}_island_height.png" id="6_height"]
[ext_resource type="Texture2D" path="res://src/levels/island/{id}/{id}_island_splat.png" id="7_splat"]
[ext_resource type="Shader" path="res://kit/terrain/terrain_splat.gdshader" id="8_shader"]
[ext_resource type="Script" path="res://src/water/water_surface.gd" id="9_water"]
[ext_resource type="Script" path="res://kit/helpers/authoring_root.gd" id="10_authoring"]
[ext_resource type="Environment" path="res://src/levels/base/default_env.tres" id="11_env"]

[sub_resource type="PlaneMesh" id="SeaBedMesh"]
size = Vector2({size_plus}, {size_plus})

[sub_resource type="StandardMaterial3D" id="SeaBedMat"]
albedo_color = Color(0.83, 0.76, 0.55, 1)

[sub_resource type="ShaderMaterial" id="SplatMat"]
shader = ExtResource("8_shader")
shader_parameter/grass_color = Color(0.35, 0.55, 0.25, 1)
shader_parameter/dirt_color = Color(0.52, 0.4, 0.26, 1)
shader_parameter/sand_color = Color(0.83, 0.76, 0.55, 1)
shader_parameter/rock_color = Color(0.45, 0.44, 0.42, 1)
shader_parameter/color5 = Color(0.92, 0.94, 0.97, 1)
shader_parameter/color6 = Color(0.3, 0.24, 0.17, 1)
shader_parameter/color7 = Color(0.22, 0.22, 0.24, 1)
shader_parameter/color8 = Color(0.62, 0.6, 0.56, 1)
shader_parameter/splatmap = ExtResource("7_splat")
shader_parameter/blend_sharpness = 8.0
shader_parameter/roughness_value = 1.0

[node name="{node}" type="Node3D"]
script = ExtResource("1_level")
info = ExtResource("2_info")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = ExtResource("11_env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, 0.354, -0.354, 0, 0.707, 0.707, 0.5, -0.612, 0.612, 0, 40, 0)
light_color = Color(1, 0.96, 0.88, 1)
shadow_enabled = true
directional_shadow_blend_splits = true
directional_shadow_max_distance = 150.0

[node name="ChaseCamera" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, 6)
script = ExtResource("3_cam")

[node name="Spawn" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {sx}, {sy}, {sz})
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("car", "truck", "tractor")

[node name="WaterSpawn" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {wx}, 1.3, 0)
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("boat")
is_water = true

[node name="Sea" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)
script = ExtResource("9_water")
size = Vector2({size_plus}, {size_plus})
depth = 3.0
far_sea_extent = 1900.0

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
preset = 0
gen_seed = {seed}
feature_scale = {feature_scale}
falloff_start = {falloff_start}
falloff_end = {falloff_end}
coast_roughness = {coast_roughness}
terrace_levels = {terrace_levels}
splatmap = ExtResource("7_splat")
channel_names = PackedStringArray({channel_names})
channel_grip = PackedFloat32Array({channel_grip})

[node name="AuthoringRoot" type="Node3D" parent="."]
script = ExtResource("10_authoring")
chunk_size = 64.0
metadata/_custom_type_script = "uid://t88htpmwukbg"
""".format({
		"id": id, "node": node_name,
		"size": SIZE, "size_plus": SIZE + 48.0, "height": HEIGHT,
		"seed": cfg["seed"], "feature_scale": cfg["feature_scale"],
		"falloff_start": cfg["falloff_start"], "falloff_end": cfg["falloff_end"],
		"coast_roughness": cfg["coast_roughness"], "terrace_levels": cfg["terrace_levels"],
		"channel_names": CHANNEL_NAMES, "channel_grip": CHANNEL_GRIP,
		"sx": spawn.x, "sy": spawn.y, "sz": spawn.z,
		"wx": SIZE * 0.5 + 14.0,
	})
