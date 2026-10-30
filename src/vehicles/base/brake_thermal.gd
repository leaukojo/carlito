class_name BrakeThermal
extends RefCounted
## One lumped temperature per friction brake and the fade it causes: a simple honest model,
## labelled (root rule 3). The law is FHWA's GSRS brake model plus disc radiation
## (`docs/sources.md` § Brake heat): `C dT/dt = P − (G0 + G1 v)(T − T_amb) − ε σ A_r (T⁴ − T_amb⁴)`.
## Pure statics; the figures are a body's hardware (`GroundDriveSpec.axle_brake_figures`).

## The lining's friction against temperature, a factor on the cold torque.
enum FadeCurve { NONE, PAD, RACE, DRUM, WET }

## Ambient (°C), `VehicleTelemetry.COOLANT_AMBIENT`'s until a level declares one; a brake starts
## here. A literal: reading that constant cycles through VehicleSpec -> GroundDriveSpec back here.
const AMBIENT_C := 20.0
const STEFAN_BOLTZMANN := 5.670374419e-8  ## W/(m²K⁴)
const KELVIN := 273.15

## (°C, factor) points, `docs/sources.md` § Brake heat: OE resin pad on iron (and the air discs).
const PAD := [Vector2(400.0, 1.0), Vector2(465.0, 0.86), Vector2(615.0, 0.86), Vector2(750.0, 0.5)]
const RACE := [Vector2(650.0, 1.0), Vector2(850.0, 0.7)]
## S-cam, light-vehicle and agricultural drums, drum expansion folded in.
const DRUM := [Vector2(177.0, 1.0), Vector2(316.0, 0.8), Vector2(480.0, 0.5)]
## A tractor's wet multi-discs, read off the sump's temperature.
const WET := [Vector2(90.0, 1.0), Vector2(190.0, 0.75)]


## One brake's hardware. `capacity` 0 = no thermal model: the brake stays at ambient, factor 1.
class Figures:
	extends RefCounted
	var capacity := 0.0         ## C, J/K
	var g0 := 0.0               ## convective conductance at rest, W/K
	var g1 := 0.0               ## its rise with road speed, W/K per m/s
	var emissivity := 0.0       ## ε; 0 where `g0`/`g1` already carry radiation (GSRS drums)
	var radiating_area := 0.0   ## A_r, m²
	var fade := PackedVector2Array()  ## (°C, factor) points, rising in °C; empty = factor 1

	func _init(c := 0.0, g0_ := 0.0, g1_ := 0.0, eps := 0.0, a_r := 0.0,
			curve := FadeCurve.NONE) -> void:
		capacity = c
		g0 = g0_
		g1 = g1_
		emissivity = eps
		radiating_area = a_r
		fade = BrakeThermal.curve_points(curve)


## A named curve's points; NONE has none (factor 1 for ever).
static func curve_points(curve: FadeCurve) -> PackedVector2Array:
	match curve:
		FadeCurve.PAD: return PackedVector2Array(PAD)
		FadeCurve.RACE: return PackedVector2Array(RACE)
		FadeCurve.DRUM: return PackedVector2Array(DRUM)
		FadeCurve.WET: return PackedVector2Array(WET)
	return PackedVector2Array()


## Heat leaving the brake (W) at `temp` (°C) and road speed `speed` (m/s): convection plus
## radiation, the latter in kelvin. Zero at ambient.
static func loss_w(temp: float, speed: float, figures: Figures) -> float:
	var convect := (figures.g0 + figures.g1 * absf(speed)) * (temp - AMBIENT_C)
	var t_k := temp + KELVIN
	var amb_k := AMBIENT_C + KELVIN
	var radiate := figures.emissivity * STEFAN_BOLTZMANN * figures.radiating_area \
			* (t_k * t_k * t_k * t_k - amb_k * amb_k * amb_k * amb_k)
	return convect + radiate


## One explicit step: the brake's temperature (°C) after `delta` s taking `power_w` (W, the friction
## brake's reacted power). Explicit is safe: the time constants are minutes to an hour. A cooling
## step never carries a brake past ambient.
static func step(temp: float, power_w: float, speed: float, delta: float,
		figures: Figures) -> float:
	if figures.capacity <= 0.0:
		return AMBIENT_C
	var next := temp + delta * (power_w - loss_w(temp, speed, figures)) / figures.capacity
	return maxf(next, AMBIENT_C) if temp >= AMBIENT_C else next


## The fade factor in (0, 1] at `temp` (°C): 1 below the curve's first point, linear between its
## points, flat past the last.
static func fade_factor(temp: float, figures: Figures) -> float:
	var pts := figures.fade
	if pts.is_empty() or temp <= pts[0].x:
		return 1.0 if pts.is_empty() else pts[0].y
	for i in range(1, pts.size()):
		if temp <= pts[i].x:
			var a := pts[i - 1]
			var b := pts[i]
			return lerpf(a.y, b.y, (temp - a.x) / (b.x - a.x))
	return pts[pts.size() - 1].y
