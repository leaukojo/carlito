@tool
extends SceneTree
## One-shot scaffolding tool that owns LEVEL 5 end to end: heightmap, rail loop curve,
## terrain conform, splatmap, LevelInfo and the level scene. Level 5 is the rail
## verification level — it was a blank canvas (empty AuthoringRoot, no bake), and it is
## registered, so putting the loop there keeps it under CI instead of an unregistered dev
## scene.
##
##   godot --headless --path . --script res://tools/gen_rail_level.gd
##   godot --headless --path . --import          # then re-import the fresh PNGs
##   godot --headless --path . res://tools/bake_levels.tscn
##
## Re-running OVERWRITES everything under src/levels/island/level_5/ — hand edits made in
## the editor afterwards are lost. Same contract as tools/gen_islands.gd, which no longer
## covers level 5 (and must NOT be re-run: levels 2/3/5 have since gained hand-added
## PlaneSpawn nodes and drifted allow-lists that its template would clobber).
##
## Order is the mandated authoring order: terrain -> road + conform -> splat. Conform
## carves the corridor into the heightmap BEFORE the splat is classified, so the cuttings
## and embankments the loop makes get their own slope-correct paint.
##
## No splat paint under the ballast: channel 7 (Gravel, grip 0.85) needs a second weight
## map this level does not have, and against unpainted grass (0.8) the grip delta is
## nothing. Deliberate omission, not an oversight.

const DIR := "res://src/levels/island/level_5"
const SIZE := 512.0            ## world extent (X and Z), matching the other islands
const HEIGHT := 51.0           ## white-pixel amplitude; stores the 3 m road levels exactly
const CHANNEL_NAMES := '"Grass", "Dirt", "Sand", "Rock", "Snow", "Mud", "Asphalt", "Gravel"'
const CHANNEL_GRIP := "0.8, 0.7, 0.6, 0.7, 0.75, 0.5, 1, 0.85"
const TITLE := "Level 5 - Railway"
const RAIL_PROFILE := "res://kit/roads/rail_profile.tres"

# --- terrain: broad forms and a two-step terrace, so the loop climbs from a coastal
# shelf onto a plateau instead of rolling over noise.
const GEN_SEED := 50807
const FEATURE_SCALE := 300.0
const OCTAVES := 3
const FALLOFF_START := 0.74
const FALLOFF_END := 0.92
const COAST_ROUGHNESS := 0.35
const TERRACE_LEVELS := 4      ## 12 m steps: a proper mesa for the loop to sit on

# --- the loop. A perturbed ellipse: r_mul below keeps it from reading as a drawn-compass
# circle while staying C-infinity, so the min turn radius never approaches the ~2.4 m
# ribbon half-width the extruder's fold clamp cares about.
const LOOP_POINTS := 12
const LOOP_A := 118.0          ## semi-axis along X (m)
const LOOP_B := 92.0           ## semi-axis along Z (m)
const LOOP_WOBBLE := 0.07      ## radial modulation, x3 per turn
const CONTOUR_SCALE_MIN := 0.55   ## radial search band for the contour follow, x the ellipse
const CONTOUR_SCALE_MAX := 1.40
const CONTOUR_SCALE_STEP := 0.005
const CONTOUR_SMOOTH_PASSES := 3
const MAX_GRADE := 0.05        ## 5%: steep for real rail, readable in game
const HARMONICS := 2           ## how much of the draped profile survives shaping
const GRADE_PASSES := 400      ## relaxation sweeps for the grade clamp safety net
const SEA_Y := 1.0             ## the Sea Area3D's height
const SEA_CLEARANCE := 4.0     ## lowest rail must sit this far above the water
const CREST_MARGIN := 3.0      ## highest rail must stay this far under the terrain ceiling

# --- conform (RoadPath's own defaults, so re-running Conform in the editor is a no-op)
const CONFORM_EPSILON := 0.05
const CONFORM_FALLOFF := 14.0  ## railway earthworks slope out further than a road's verge
const MAX_SEG_LEN := 6.0
const MAX_SEG_ANGLE := 6.0

# --- car spawn: searched inward from the loop so the rails are visible on spawn
const SPAWN_INSET_MIN := 14.0
const SPAWN_INSET_MAX := 34.0
const SPAWN_MIN_HEIGHT := 3.0
const SPAWN_SHELF_TOLERANCE := 4.0   ## must be on the track's own terrace, not above it


func _init() -> void:
	var cells := int(SIZE) + 1
	var heights := TerrainGen.generate_heights(TerrainGen.Preset.ISLAND, GEN_SEED,
			FEATURE_SCALE, OCTAVES, FALLOFF_START, FALLOFF_END, cells, cells,
			float(TERRACE_LEVELS) * 3.0 / HEIGHT, 0.6, COAST_ROUGHNESS)

	var profile: Resource = load(RAIL_PROFILE)
	if profile == null:
		printerr("[gen-rail] cannot load %s" % RAIL_PROFILE)
		quit(1)
		return

	var positions := _loop_positions(heights)
	var curve := _build_curve(positions)
	_report(curve, positions, heights)
	_conform(heights, curve, profile)

	var px := SIZE / float(cells - 1)
	var splat := TerrainGen.build_splatmap(heights, HEIGHT, px, px, 2.0, 22.0, 38.0)
	_write_png(heights, "%s/level_5_island_height.png" % DIR)
	_write_png(splat, "%s/level_5_island_splat.png" % DIR)

	var curve_path := "%s/level_5_rail_curve.tres" % DIR
	# Saved as a resource rather than emitted as .tscn text: Curve3D's `_data` packing is
	# an engine detail, and this way the curve is also an editable, hash-tracked
	# dependency of the level scene.
	var err := ResourceSaver.save(curve, curve_path)
	if err != OK:
		printerr("[gen-rail] cannot save %s (error %d)" % [curve_path, err])
		quit(1)
		return

	var spawn := _find_spawn(heights, positions)
	_write_text("%s/level_5_info.tres" % DIR, _info_text())
	_write_text("%s/level_5.tscn" % DIR, _scene_text(spawn))
	print("[gen-rail] car spawn at %v" % spawn)
	print("[gen-rail] done. Run --import, then bake_levels.")
	quit()


# ------------------------------------------------------------------- the loop


## Slide each control point radially until it sits near the ring's own median elevation,
## then smooth the radii around the ring. This is how a mountain railway is actually
## surveyed — you route along the contour and pay for the residual in earthworks, rather
## than driving a fixed line across the hill and paying for all of it. Without it a plain
## ellipse on this island wanted 20 m cuttings; with it the corridor barely leaves the
## ground. Deterministic: a fixed radial scan, no RNG anywhere.
func _follow_contour(heights: Image, base: Array[Vector2]) -> Array[Vector2]:
	var sampled: Array[float] = []
	for p in base:
		sampled.append(_height_at(heights, p.x, p.y))
	var sorted := sampled.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var target: float = sorted[sorted.size() / 2]

	var scales: Array[float] = []
	for p in base:
		var best := 1.0
		var best_err := INF
		var t := CONTOUR_SCALE_MIN
		while t <= CONTOUR_SCALE_MAX:
			var err := absf(_height_at(heights, p.x * t, p.y * t) - target)
			if err < best_err:
				best_err = err
				best = t
			t += CONTOUR_SCALE_STEP
		scales.append(best)

	# The scan is per point and independent, so neighbours can land far apart and kink the
	# plan view. Smoothing the radii (wrap-around) trades a little contour accuracy for a
	# curve the extruder is happy with — the min-turn-radius report is the check.
	for _pass in CONTOUR_SMOOTH_PASSES:
		var smoothed := scales.duplicate()
		for i in scales.size():
			var prev := scales[(i + scales.size() - 1) % scales.size()]
			var next := scales[(i + 1) % scales.size()]
			smoothed[i] = (prev + 2.0 * scales[i] + next) * 0.25
		scales = smoothed

	var out: Array[Vector2] = []
	for i in base.size():
		out.append(base[i] * scales[i])
	print("[gen-rail] contour: target %.1f m, radius scale %.2f..%.2f" % [
			target, scales.min(), scales.max()])
	return out


## Control-point positions for the loop: a wobbled ellipse draped onto the terrain, then
## given a surveyed gradient profile, then shifted so the whole loop clears the sea and
## stays inside the terrain's height range.
##
## The gradient profile is the interesting part. A raw drape follows every bump — 36 m of
## relief in 868 m on this island — which no railway would be built on, and simply
## relaxing it against the grade limit diffuses the whole ring flat (the constraint's
## flattest solution wins). So instead the draped profile is reduced to its first two
## harmonics around the loop: one long climb and one long descent per lap, plus a second-
## order undulation, following the terrain's actual tilt rather than inventing one. That
## AC part is then scaled until the steepest edge sits exactly on the grade budget, which
## keeps as much relief as the budget allows instead of throwing it away. Conform turns
## the difference into cuttings and embankments — which is what earthworks ARE.
func _loop_positions(heights: Image) -> PackedVector3Array:
	# Plain Arrays while the profile is worked on: writing through an element's member
	# (pts[i].y = ...) is not a thing on a PackedVector3Array.
	var base: Array[Vector2] = []
	for i in LOOP_POINTS:
		var ang := TAU * float(i) / float(LOOP_POINTS)
		var r_mul := 1.0 + LOOP_WOBBLE * sin(3.0 * ang)
		base.append(Vector2(LOOP_A * r_mul * cos(ang), LOOP_B * r_mul * sin(ang)))
	var xz := _follow_contour(heights, base)
	var ys: Array[float] = []
	for p in xz:
		ys.append(_height_at(heights, p.x, p.y))
	print("[gen-rail] draped relief before shaping: %.1f m" % (ys.max() - ys.min()))

	# Phase by ARC position, not by index: the points are evenly spaced in ellipse angle,
	# which is not evenly spaced along the ellipse.
	var runs: Array[float] = []
	var total := 0.0
	for i in LOOP_POINTS:
		var run := xz[i].distance_to(xz[(i + 1) % LOOP_POINTS])
		runs.append(run)
		total += run
	var phase: Array[float] = []
	var walked := 0.0
	for i in LOOP_POINTS:
		phase.append(TAU * walked / total)
		walked += runs[i]

	# Harmonic fit. Equally-spaced-sample coefficients on arc phase is an approximation
	# (the ellipse's angle/arc mismatch), which is fine — this is a shaping filter, not a
	# transform anyone reads back.
	var mean := 0.0
	for y in ys:
		mean += y
	mean /= float(LOOP_POINTS)
	var ac: Array[float] = []
	for i in LOOP_POINTS:
		ac.append(0.0)
	for k in range(1, HARMONICS + 1):
		var a := 0.0
		var b := 0.0
		for i in LOOP_POINTS:
			a += (ys[i] - mean) * cos(float(k) * phase[i])
			b += (ys[i] - mean) * sin(float(k) * phase[i])
		a *= 2.0 / float(LOOP_POINTS)
		b *= 2.0 / float(LOOP_POINTS)
		for i in LOOP_POINTS:
			ac[i] += a * cos(float(k) * phase[i]) + b * sin(float(k) * phase[i])

	# Scale the AC part onto the grade budget — DOWN only. Scaling a gentle profile up to
	# the budget would invent relief the ground does not have, and conform would build
	# that invention out of ten-metre embankments on flat plateau.
	var steepest := 0.0
	for i in LOOP_POINTS:
		if runs[i] > 0.001:
			steepest = maxf(steepest, absf(ac[(i + 1) % LOOP_POINTS] - ac[i]) / runs[i])
	var scale := minf(MAX_GRADE / maxf(steepest, 0.0001), 1.0)
	for i in LOOP_POINTS:
		ys[i] = mean + ac[i] * scale

	# Safety net only: after the fit the budget is met by construction, but a degenerate
	# spacing could still leave one edge over. Per edge, pull both ends toward each other
	# by half the excess; swept because fixing one edge can break its neighbour.
	for _pass in GRADE_PASSES:
		var worst := 0.0
		for i in LOOP_POINTS:
			var j := (i + 1) % LOOP_POINTS
			var run := xz[i].distance_to(xz[j])
			if run < 0.001:
				continue
			var rise := ys[j] - ys[i]
			var excess := absf(rise) - MAX_GRADE * run
			if excess <= 0.0:
				continue
			worst = maxf(worst, excess)
			var shift := signf(rise) * excess * 0.5
			ys[i] += shift
			ys[j] -= shift
		if worst < 0.001:
			break

	var lo := INF
	var hi := -INF
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
	# One rigid shift, so the grade clamp above survives it untouched.
	var lift := maxf(SEA_Y + SEA_CLEARANCE - lo, 0.0)
	lift -= maxf(hi + lift - (HEIGHT - CREST_MARGIN), 0.0)
	# The two constraints can only both be met if the profile fits the band. When it does
	# not, the ceiling wins above and the loop silently drops back toward the water — say
	# so rather than shipping a rail the sea eats.
	if lo + lift < SEA_Y + SEA_CLEARANCE - 0.001:
		printerr(("[gen-rail] relief %.1f m does not fit the %.1f m band between sea " +
				"clearance and the crest margin — lowest rail lands at %.1f m") % [
				hi - lo, HEIGHT - CREST_MARGIN - SEA_Y - SEA_CLEARANCE, lo + lift])

	var pts := PackedVector3Array()
	for i in LOOP_POINTS:
		pts.append(Vector3(xz[i].x, ys[i] + lift, xz[i].y))
	return pts


## The closed Curve3D: Catmull-Rom handles everywhere, and the seam handled exactly the
## way the editor's "Close loop" button does it (road_draw_tool.close_loop) — the last
## point sits ON the first, which is what RoadBuilder.is_closed_loop asks and what makes
## extrude give both end rings one shared bisector frame.
func _build_curve(positions: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	for p in positions:
		curve.add_point(p)
	curve.add_point(positions[0])
	var last := curve.point_count - 1
	for i in range(1, last):
		var h: Dictionary = RoadBuilder.smooth_handles(curve.get_point_position(i - 1),
				curve.get_point_position(i), curve.get_point_position(i + 1))
		curve.set_point_in(i, h["in"])
		curve.set_point_out(i, h["out"])
	var seam: Dictionary = RoadBuilder.smooth_handles(positions[positions.size() - 1],
			positions[0], positions[1])
	curve.set_point_out(0, seam["out"])
	curve.set_point_in(last, seam["in"])
	return curve


## Acceptance numbers for the run: the loop must stay above the fold limit, keep its
## grades real but bounded, never dip toward the sea, and not demand an earthwork the
## conform falloff cannot slope out.
func _report(curve: Curve3D, positions: PackedVector3Array, heights: Image) -> void:
	var length := curve.get_baked_length()
	var radius := RoadBuilder.min_turn_radius(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var lo := INF
	var hi := -INF
	var steepest := 0.0
	for i in LOOP_POINTS:
		var j := (i + 1) % LOOP_POINTS
		var run := Vector2(positions[j].x - positions[i].x,
				positions[j].z - positions[i].z).length()
		if run > 0.001:
			steepest = maxf(steepest, absf(positions[j].y - positions[i].y) / run)
		lo = minf(lo, positions[i].y)
		hi = maxf(hi, positions[i].y)
	print("[gen-rail] loop: %.1f m long, %d control points, closed=%s" % [
			length, curve.point_count, RoadBuilder.is_closed_loop(curve)])
	print("[gen-rail] min turn radius %.1f m, steepest grade %.1f%%, y %.1f..%.1f m" % [
			radius, steepest * 100.0, lo, hi])
	# Earthworks: how far the surveyed profile sits off the untouched ground, sampled
	# densely along the centreline (the control points alone miss the extremes).
	var cut := 0.0
	var fill := 0.0
	var step := 4.0
	var walked := 0.0
	while walked < length:
		var w := curve.sample_baked(walked)
		var delta := w.y - _height_at(heights, w.x, w.z)
		fill = maxf(fill, delta)
		cut = maxf(cut, -delta)
		walked += step
	print("[gen-rail] earthworks: %.1f m deepest cutting, %.1f m tallest embankment (falloff %.0f m)" % [
			cut, fill, CONFORM_FALLOFF])


# ---------------------------------------------------------------- conform


## RoadPath._conform_terrain's math, headless: that one is is_editor_hint-guarded and
## routes its write through EditorUndoRedoManager, but the geometry it feeds
## RoadBuilder.conform_heights is reproduced here exactly — centreline samples AT the
## extrusion's ring offsets plus a full-width deck strip on the ribbon's own frames.
## Everything in this level sits at the origin, so world == terrain-local.
func _conform(heights: Image, curve: Curve3D, profile: Resource) -> void:
	var offsets := RoadBuilder.adaptive_offsets(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var fw: float = profile.call("full_half_width")
	var samples := PackedVector3Array()
	for o in offsets:
		var w := curve.sample_baked(o)
		samples.append(Vector3(w.x, w.z, _norm_height(w.y)))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-fw, 0), Vector2(fw, 0)]),
			PackedInt32Array([0]), offsets, false)
	var deck := PackedVector3Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck.append(Vector3(v.x, v.z, _norm_height(v.y)))
	var dirty := RoadBuilder.conform_heights(heights, samples, fw, CONFORM_FALLOFF,
			SIZE, SIZE, deck)
	print("[gen-rail] conform: %d ring samples, dirty rect %s" % [samples.size(), dirty])
	if not dirty.has_area():
		printerr("[gen-rail] conform changed nothing — the loop missed the terrain")


## World Y -> the heightmap's 0..1 storage, minus the z-fight epsilon (the ribbon rides
## on top). Clamped exactly like RoadPath does, which is why _loop_positions keeps the
## loop inside the range in the first place.
func _norm_height(y: float) -> float:
	return clampf((y - CONFORM_EPSILON) / HEIGHT, 0.0, 1.0)


# ---------------------------------------------------------------- sampling


## Bilinear terrain height at world XZ, mirroring HeightmapTerrain.height_at (terrain
## centred on the origin, one cell per world unit).
func _height_at(img: Image, x: float, z: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var u := clampf((x + SIZE * 0.5) / SIZE, 0.0, 1.0) * float(w - 1)
	var v := clampf((z + SIZE * 0.5) / SIZE, 0.0, 1.0) * float(h - 1)
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := u - float(x0)
	var ty := v - float(y0)
	var top := lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, tx)
	var bot := lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, tx)
	return lerpf(top, bot, ty) * HEIGHT


## Car spawn: the flattest dry spot on a ring INSIDE the loop, so the player faces the
## rails the moment the level loads. Candidates must sit on the same shelf as the track
## they were measured from (SPAWN_SHELF_TOLERANCE) — this island is terraced in 12 m
## steps, and the flattest ground near the line is otherwise happily on top of a cliff
## you cannot drive down. Deterministic: fixed insets, no RNG. Reads the CONFORMED
## heights, so the corridor's own earthworks are accounted for.
func _find_spawn(heights: Image, positions: PackedVector3Array) -> Vector3:
	var best := Vector3(0, HEIGHT * 0.5, 0)
	var best_slope := INF
	var inset := SPAWN_INSET_MIN
	while inset <= SPAWN_INSET_MAX:
		for p in positions:
			var inward := Vector2(-p.x, -p.z)
			if inward.length() < 0.001:
				continue
			inward = inward.normalized() * inset
			var x := p.x + inward.x
			var z := p.z + inward.y
			var y := _height_at(heights, x, z)
			if y < SPAWN_MIN_HEIGHT or absf(y - p.y) > SPAWN_SHELF_TOLERANCE:
				continue
			var slope := absf(_height_at(heights, x + 2.0, z) - _height_at(heights, x - 2.0, z)) \
					+ absf(_height_at(heights, x, z + 2.0) - _height_at(heights, x, z - 2.0))
			if slope < best_slope:
				best_slope = slope
				best = Vector3(x, y + 1.5, z)
		inset += 2.0
	if is_inf(best_slope):
		printerr("[gen-rail] no spawn candidate inside the loop passed the height/shelf " +
				"filter — falling back to the map centre, which is probably mid-air")
	return best


# ---------------------------------------------------------------- file output


func _write_png(img: Image, path: String) -> void:
	var err := img.save_png(path)
	assert(err == OK, "save_png failed for %s" % path)
	TerrainGen.ensure_import_settings(path)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % path)
	f.store_string(text)


func _info_text() -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("train", "car", "truck", "tractor", "boat", "bike", "drone", "plane")
default_vehicle = "car"
""" % TITLE


## The level scene. Node set matches what level 5 already had (including the hand-added
## PlaneSpawn) plus the rail loop under AuthoringRoot. The terrain's generation
## parameters are written back so a future in-editor Generate reproduces the same base
## island — the conform on top of it is this tool's, and re-running Generate would undo it.
func _scene_text(spawn: Vector3) -> String:
	return """[gd_scene load_steps=17 format=3]

[ext_resource type="Script" path="res://src/levels/base/level.gd" id="1_level"]
[ext_resource type="Resource" path="res://src/levels/island/level_5/level_5_info.tres" id="2_info"]
[ext_resource type="Script" path="res://src/vehicles/base/chase_camera.gd" id="3_cam"]
[ext_resource type="Script" path="res://src/levels/base/vehicle_spawn.gd" id="4_spawn"]
[ext_resource type="Script" path="res://src/levels/base/heightmap_terrain.gd" id="5_terrain"]
[ext_resource type="Texture2D" path="res://src/levels/island/level_5/level_5_island_height.png" id="6_height"]
[ext_resource type="Texture2D" path="res://src/levels/island/level_5/level_5_island_splat.png" id="7_splat"]
[ext_resource type="Shader" path="res://kit/terrain/terrain_splat.gdshader" id="8_shader"]
[ext_resource type="Script" path="res://src/water/water_surface.gd" id="9_water"]
[ext_resource type="Script" path="res://kit/helpers/authoring_root.gd" id="10_authoring"]
[ext_resource type="Environment" path="res://src/levels/base/default_env.tres" id="11_env"]
[ext_resource type="Script" path="res://kit/helpers/road_path.gd" id="12_road"]
[ext_resource type="Resource" path="res://kit/roads/rail_profile.tres" id="13_rail"]
[ext_resource type="Resource" path="res://src/levels/island/level_5/level_5_rail_curve.tres" id="14_curve"]

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

[node name="Level5" type="Node3D"]
script = ExtResource("1_level")
info = ExtResource("2_info")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = ExtResource("11_env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, 0.353553, -0.353553, 0, 0.707107, 0.707107, 0.5, -0.612372, 0.612372, 0, 40, 0)
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
vehicle_types = PackedStringArray("car", "truck", "tractor", "bike", "drone")

[node name="WaterSpawn" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {wx}, 1.3, 0)
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("boat")
is_water = true

[node name="PlaneSpawn" type="Marker3D" parent="."]
transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, 98, 37.3, -2)
script = ExtResource("4_spawn")
vehicle_types = PackedStringArray("plane")

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
gen_octaves = {octaves}
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

[node name="RailLoop" type="Node3D" parent="AuthoringRoot"]
script = ExtResource("12_road")
profile = ExtResource("13_rail")
conform_falloff = {conform_falloff}

[node name="Path" type="Path3D" parent="AuthoringRoot/RailLoop"]
curve = ExtResource("14_curve")
""".format({
		"size": SIZE, "size_plus": SIZE + 48.0, "height": HEIGHT,
		"seed": GEN_SEED, "feature_scale": FEATURE_SCALE, "octaves": OCTAVES,
		"falloff_start": FALLOFF_START, "falloff_end": FALLOFF_END,
		"coast_roughness": COAST_ROUGHNESS, "terrace_levels": TERRACE_LEVELS,
		"channel_names": CHANNEL_NAMES, "channel_grip": CHANNEL_GRIP,
		"conform_falloff": CONFORM_FALLOFF,
		"sx": spawn.x, "sy": spawn.y, "sz": spawn.z,
		"wx": SIZE * 0.5 + 14.0,
	})
