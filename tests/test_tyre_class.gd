extends GdUnitTestSuite
## Tyre classes: the catalog's shape, every body's stock fit, and the identity a stock fit is.

const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")

const WHEELED_FAMILIES := ["car", "truck", "tractor"]
## Towed bodies are not catalog variants but run the same tyre seam (`TowedBody`).
const TRAILER_SPECS := [
	"res://src/vehicles/truck/trailers/box_spec.tres",
	"res://src/vehicles/truck/trailers/flatbed_spec.tres",
	"res://src/vehicles/truck/trailers/tanker_spec.tres",
	"res://src/vehicles/truck/trailers/tipper_spec.tres",
	"res://src/vehicles/tractor/trailers/farm_tipper_spec.tres",
]


func _spec_of(variant: String) -> VehicleSpecScript:
	var state := (load(VehicleCatalog.scene_of(variant)) as PackedScene).get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"spec":
			return state.get_node_property_value(0, i) as VehicleSpecScript
	return null


## Every wheeled body's spec, catalog variants and towed bodies, keyed by name.
func _wheeled_specs() -> Dictionary:
	var out := {}
	for variant in VehicleCatalog.VARIANTS:
		if WHEELED_FAMILIES.has(VehicleCatalog.family_of(variant)):
			out[variant] = _spec_of(variant)
	for path: String in TRAILER_SPECS:
		out[path] = load(path)
	return out


## A class with factors off 1: `dry` 1.2, 1.5 on snow, crr 1.3.
static func _fixture() -> TyreClass:
	var cls := TyreClass.new()
	cls.id = "fixture"
	cls.fits = [TyreClass.Fit.PASSENGER]
	cls.dry = 1.2
	cls.surface_grip = {"Snow": 1.5}
	cls.crr_factor = 1.3
	return cls


# --- the catalog -------------------------------------------------------------------

func test_every_class_loads_names_itself_and_fits_a_body() -> void:
	for path in TyreCatalog.CLASSES:
		var cls := load(path) as TyreClass
		assert_object(cls).override_failure_message("%s is no TyreClass" % path).is_not_null()
		assert_str(cls.id).override_failure_message("%s: id" % path) \
				.is_equal(path.get_file().get_basename())
		assert_str(cls.display_name).override_failure_message("%s: no display name" % path) \
				.is_not_empty()
		assert_int(cls.fits.size()).override_failure_message("%s fits no body" % path).is_greater(0)
		assert_bool(cls.fits.has(TyreClass.Fit.NONE)) \
				.override_failure_message("%s lists NONE as a fit" % path).is_false()


func test_every_surface_factor_names_a_surface_and_asphalt_is_the_reference() -> void:
	for path in TyreCatalog.CLASSES:
		var cls := load(path) as TyreClass
		for key: String in cls.surface_grip:
			assert_int(Surface.from_key(key)) \
					.override_failure_message("%s: '%s' is no surface" % [path, key]) \
					.is_not_equal(-1)
			assert_float(cls.surface_grip[key]).override_failure_message(
					"%s: a %s factor of %f" % [path, key, cls.surface_grip[key]]).is_greater(0.0)
		# `dry` carries asphalt, so its factor is 1 by definition.
		assert_float(cls.grip_factor(Surface.ASPHALT)).is_equal(1.0)
		assert_float(cls.dry).is_greater(0.0)
		assert_float(cls.crr_factor).is_greater(0.0)


func test_an_unknown_id_is_no_class() -> void:
	assert_object(TyreCatalog.by_id("no-such-tyre")).is_null()
	assert_str(TyreCatalog.by_id("winter").id).is_equal("winter")


func test_the_classes_a_fit_offers_are_in_catalog_order_and_hold_its_stock() -> void:
	var specs := _wheeled_specs()
	for body: String in specs:
		var gd: GroundDriveSpec = (specs[body] as VehicleSpecScript).ground_drive
		var offered := TyreCatalog.fitting(gd.tyre_fit)
		assert_bool(offered.has(gd.tyre)).override_failure_message(
				"%s: fit %d does not offer its stock %s" % [body, gd.tyre_fit, gd.tyre.id]) 				.is_true()
		var last := -1
		for cls in offered:
			var at := TyreCatalog.CLASSES.find(cls.resource_path)
			assert_int(at).is_greater(last)
			last = at


# --- every body's stock --------------------------------------------------------------

func test_every_stock_class_fits_its_body() -> void:
	var specs := _wheeled_specs()
	assert_int(specs.size()).is_greater(0)
	for body: String in specs:
		var gd: GroundDriveSpec = (specs[body] as VehicleSpecScript).ground_drive
		assert_object(gd.tyre).override_failure_message("%s has no stock tyre" % body).is_not_null()
		assert_bool(gd.tyre.fits_body(gd.tyre_fit)).override_failure_message(
				"%s: %s is not made in fit %d" % [body, gd.tyre.id, gd.tyre_fit]).is_true()


func test_a_stock_fit_on_asphalt_is_exactly_the_specs_mu() -> void:
	for path in TyreCatalog.CLASSES:
		var stock := load(path) as TyreClass
		var response := TyreClass.grip_response(stock, stock)
		assert_int(response.size()).is_equal(Surface.COUNT)
		assert_float(response[Surface.ASPHALT]).override_failure_message(path).is_equal(1.0)
		assert_float(TyreClass.crr_scale(stock, stock)).override_failure_message(path).is_equal(1.0)
		# Off asphalt the stock reads its own factor over the reference on each surface.
		for s in Surface.COUNT:
			assert_float(response[s]).override_failure_message("%s on %s" % [path,
					Surface.display_name(s)]).is_equal(
					float(PackedFloat32Array([Surface.ref_grip(s) * stock.grip_factor(s)])[0]))


func test_no_class_is_the_reference_tyre() -> void:
	assert_int(TyreClass.grip_response(null, null).size()).is_equal(0)
	assert_float(TyreClass.crr_scale(null, null)).is_equal(1.0)


func test_a_class_is_read_over_the_stock_one() -> void:
	var stock := TyreClass.new()
	stock.dry = 0.8
	stock.crr_factor = 2.0
	var cls := _fixture()
	var response := TyreClass.grip_response(cls, stock)
	assert_float(response[Surface.ASPHALT]).is_equal_approx(1.2 / 0.8, 1e-6)
	assert_float(response[Surface.SNOW]).is_equal_approx(
			Surface.ref_grip(Surface.SNOW) * 1.5 * 1.2 / 0.8, 1e-6)
	assert_float(response[Surface.WET]) 			.is_equal_approx(Surface.ref_grip(Surface.WET) * 1.2 / 0.8, 1e-6)
	assert_float(TyreClass.crr_scale(cls, stock)).is_equal_approx(1.3 / 2.0, 1e-9)


# --- one factor for both axles: the balance stands --------------------------------------

func test_the_factor_is_the_same_on_every_axle() -> void:
	var gd := GroundDriveSpec.new()
	var front := RayWheel.new(Vector3(0.0, 0.0, -1.0), true, true, null, 300.0)
	var rear := RayWheel.new(Vector3(0.0, 0.0, 1.0), false, true, null, 300.0)
	for w in [front, rear]:
		(w as RayWheel).apply_suspension(gd)
		(w as RayWheel).apply_tyre(_fixture(), gd.tyre)
	assert_bool(front.is_rear).is_false()
	assert_bool(rear.is_rear).is_true()
	assert_array(Array(rear.tyre_grip)).is_equal(Array(front.tyre_grip))


func test_a_class_factor_leaves_every_bodys_balance_margin_alone() -> void:
	# `load_scaled_mu` is linear in mu, so one factor on both axles scales both capacities alike at
	# any transfer: the front-first margin `BalanceModel.limit` reports cannot move with the class.
	var k := 1.37
	var checked := 0
	var specs := _wheeled_specs()
	for body: String in specs:
		var m := BalanceModel.axles(specs[body] as VehicleSpecScript)
		if m.is_empty():
			continue
		var scaled := m.duplicate(true)
		scaled["front"]["mu"] = float(m["front"]["mu"]) * k
		scaled["rear"]["mu"] = float(m["rear"]["mu"]) * k
		for lat_g in [0.0, 0.3, 0.6, 0.9]:
			var base := BalanceModel.axle_capacity_g(m, lat_g)
			var fitted := BalanceModel.axle_capacity_g(scaled, lat_g)
			assert_float(fitted.y / fitted.x).override_failure_message(
					"%s at %.1f g" % [body, lat_g]).is_equal_approx(base.y / base.x, 1e-5)
		checked += 1
	assert_int(checked).is_greater(0)


# --- the sourced table's shape (`docs/sources.md` § Sourced figures, *Tyre classes*) ------

## `id`'s grip on `surface` over the all-season tyre's: `dry` times the surface factor.
static func _vs_ref(id: String, surface: int) -> float:
	var cls := TyreCatalog.by_id(id)
	return cls.dry * cls.grip_factor(surface)


func test_on_dry_asphalt_summer_leads_and_a_winter_tyre_stops_a_few_to_15_percent_longer() -> void:
	var order := ["summer", "all_season", "winter", "studded"]
	for i in order.size() - 1:
		assert_float(_vs_ref(order[i], Surface.ASPHALT)).override_failure_message(
				"%s under %s on asphalt" % [order[i], order[i + 1]]) \
				.is_greater_equal(_vs_ref(order[i + 1], Surface.ASPHALT))
	# A stop's length goes as 1 / mu.
	assert_float(_vs_ref("summer", Surface.ASPHALT) / _vs_ref("winter", Surface.ASPHALT)) \
			.is_between(1.02, 1.15)


func test_on_snow_winter_is_one_and_a_half_to_twice_summer() -> void:
	var winter := _vs_ref("winter", Surface.SNOW)
	var summer := _vs_ref("summer", Surface.SNOW)
	assert_float(winter / summer).is_between(1.5, 2.0)
	assert_float(_vs_ref("all_season", Surface.SNOW)).is_greater(summer)
	assert_float(_vs_ref("all_season", Surface.SNOW)).is_less(winter)
	assert_float(_vs_ref("studded", Surface.SNOW)).is_greater_equal(winter)


func test_on_ice_every_class_is_low_and_studs_lead() -> void:
	assert_float(_vs_ref("studded", Surface.ICE)).is_greater(_vs_ref("winter", Surface.ICE))
	assert_float(_vs_ref("winter", Surface.ICE)).is_greater(_vs_ref("all_season", Surface.ICE))
	assert_float(_vs_ref("all_season", Surface.ICE)).is_greater_equal(_vs_ref("summer", Surface.ICE))
	for path in TyreCatalog.CLASSES:
		var cls := load(path) as TyreClass
		assert_float(Surface.ref_grip(Surface.ICE) * _vs_ref(cls.id, Surface.ICE)) \
				.override_failure_message("%s grips on ice" % cls.id).is_less_equal(0.3)


func test_in_mud_and_field_a_lug_beats_a_road_tyre() -> void:
	for s: int in [Surface.MUD, Surface.FIELD]:
		for lug: String in ["mud", "ag_lug"]:
			assert_float(_vs_ref(lug, s)).override_failure_message(
					"%s on %s" % [lug, Surface.display_name(s)]) \
					.is_greater(_vs_ref("all_season", s))


func test_a_mud_tyre_pays_on_asphalt() -> void:
	assert_float(_vs_ref("mud", Surface.ASPHALT)).is_less(1.0)
	assert_float(TyreCatalog.by_id("mud").crr_factor).is_greater(1.0)


func test_no_class_grips_past_its_own_dry_asphalt() -> void:
	# So a fit check at the asphalt factor bounds every surface (`test_vehicle_catalog`).
	for path in TyreCatalog.CLASSES:
		var cls := load(path) as TyreClass
		var response := TyreClass.grip_response(cls, cls)
		for s in Surface.COUNT:
			assert_float(response[s]).override_failure_message("%s on %s: %f" % [cls.id,
					Surface.display_name(s), response[s]]).is_less_equal(response[Surface.ASPHALT])
