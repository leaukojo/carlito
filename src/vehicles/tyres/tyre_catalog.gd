class_name TyreCatalog
extends RefCounted
## Static registry of the tyre classes (`TyreClass`), in the order the garage lists them. Which a
## body may fit is the class's `fits` against the spec's `tyre_fit`.

const CLASSES: PackedStringArray = [
	"res://src/vehicles/tyres/all_season.tres",
	"res://src/vehicles/tyres/summer.tres",
	"res://src/vehicles/tyres/winter.tres",
	"res://src/vehicles/tyres/studded.tres",
	"res://src/vehicles/tyres/mud.tres",
	"res://src/vehicles/tyres/truck_drive.tres",
	"res://src/vehicles/tyres/ag_lug.tres",
	"res://src/vehicles/tyres/slick.tres",
	"res://src/vehicles/tyres/trailer.tres",
]


## The class named `id`, or null.
static func by_id(id: String) -> TyreClass:
	for path in CLASSES:
		if path.get_file().get_basename() == id:
			return load(path) as TyreClass
	return null


## Every class made in `fit`, in catalog order.
static func fitting(fit: int) -> Array[TyreClass]:
	var out: Array[TyreClass] = []
	for path in CLASSES:
		var cls := load(path) as TyreClass
		if cls != null and cls.fits_body(fit):
			out.append(cls)
	return out
