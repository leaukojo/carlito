class_name TyreClass
extends Resource
## A tread class (summer, winter, mud...): the swappable half of a tyre. The other half, the
## fitment (`mu_*`, the load laws, the radius, `rolling_resistance`), is the body's own on
## `GroundDriveSpec` and describes its STOCK class on dry asphalt and a hard road. A class states
## only factors over the reference all-season passenger tyre, so one class serves a 1.1 t car and
## an 8 t truck. Fitted, the grip on surface `s` is `mu x dry / stock.dry x Surface.ref_grip(s) x
## grip_factor(s)` and the rolling resistance `rolling_resistance x crr_factor / stock.crr_factor`:
## the stock class is exactly the spec. Classes: `TyreCatalog`.

## The tyre sizes a body takes; a class lists the ones it is made in. Stored in specs and classes:
## append, never reorder.
enum Fit { NONE, PASSENGER, LIGHT_TRUCK, TRUCK, TRACTOR, RACE, TRAILER }

@export var id := ""  ## the file's basename; what a stored choice names
@export var display_name := ""
@export var fits: Array[Fit] = []
## Peak grip on dry asphalt over the reference tyre's.
@export var dry := 1.0
## Peak grip per surface over the reference tyre on that surface, keyed by `Surface.display_name`;
## a missing surface is 1. Asphalt is 1 by definition (`dry` carries it). One factor serves both
## axes and both axles, so the balance margins stand (`BalanceModel`).
@export var surface_grip: Dictionary[String, float] = {}
## Hard-road rolling resistance over the reference tyre's.
@export var crr_factor := 1.0


func fits_body(fit: int) -> bool:
	return fit != Fit.NONE and fits.has(fit)


## This class's factor on `surface` over the reference tyre (1 when unstated).
func grip_factor(surface: int) -> float:
	return float(surface_grip.get(Surface.display_name(surface), 1.0))


## `fitted`'s peak grip per `Surface` id over the body's spec mu, on a body whose spec describes
## `stock` (`HeightmapTerrain.grip_at`'s response). Empty for no class: the reference tyre. A null
## `stock` reads as the reference.
static func grip_response(fitted: TyreClass, stock: TyreClass) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if fitted == null:
		return out
	var dry_ratio := fitted.dry / (stock.dry if stock != null else 1.0)
	out.resize(Surface.COUNT)
	for s in Surface.COUNT:
		out[s] = Surface.ref_grip(s) * dry_ratio * fitted.grip_factor(s)
	return out


## `fitted`'s hard-road rolling resistance over the spec's (`stock`'s); 1 with no class.
static func crr_scale(fitted: TyreClass, stock: TyreClass) -> float:
	if fitted == null:
		return 1.0
	return fitted.crr_factor / (stock.crr_factor if stock != null else 1.0)
