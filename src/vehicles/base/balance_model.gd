class_name BalanceModel
extends RefCounted
## A two-axle body's steady-state handling balance as pure arithmetic over its spec, which
## `tools/gen_kenney_vehicles.gd` reports and `measure_vehicles` prints beside its step and corner
## readings. RayWheel pushes at the patch, so the roll centre is the ground: an axle's roll stiffness
## is `(k / 2 + bar) * t^2` and every newton of transfer goes through it. Below the grip curve's peak
## a wheel's side force is exactly its cornering stiffness times its slip. The angular damping's yaw
## moment `I * c * r` is a term of its own, and so are roll and compliance steer, angles and not
## grips. `limit` is free-rolling at zero steer; the corner pass, steered and driven, has its own
## steady turn (`corner`, `corner_limit`). Derivation and calibration: `docs/handling.md` § Balance.
## The model is a plain Dictionary (`axles`), so a what-if edits it.

const G := BrakeSizing.G


## The model of `spec` at `speed` (m/s), SI units; empty unless one front and one rear pair (no
## tandem, kingpin). Per axle (`front` / `rear`): `load` and `aero` (static weight and downforce per
## wheel, `_normal`), `track`, `spring`, `bar`, `mu` (side mu at the reference load, `rear_lat_grip`
## in), `share` (`RayWheel.tyre_share`), `roll_steer` (deg/deg), `compliance_steer` (deg/kN a patch;
## front 0; both + = under), `mu_long`, `driven`, `diff_bias`. Body: `mass`, `h` (COM over the road
## at the static sag), `ref` (the even corner load), `sensitivity`, `peak_slip` (the grip curve's
## peak), `peak_load` (x `ref`; 0 = off), `wheelbase`, `front_arm` (COM to the front axle),
## `yaw_inertia` (declared `yaw_dynamic_index`; NAN where Jolt's: a caller fills it), `yaw_damp`
## (`angular_damping`; 0 = none); for `corner`, `grip_curve`, `crr`, `drag_area`, `side_area`,
## `aero_h` / `aero_arm`, `ackermann`, `lock` (the mean steer's at `speed`), `centre_bias`, `tcs`.
static func axles(spec: VehicleSpec, speed := 0.0) -> Dictionary:
	var gd := spec.ground_drive
	if gd == null or gd.wheel_positions.size() != 4 or spec.mass <= 0.0:
		return {}
	var front_x := PackedFloat32Array()
	var rear_x := PackedFloat32Array()
	var front_z := NAN
	var rear_z := NAN
	for p in gd.wheel_positions:
		var on_rear := RayWheel.is_rear_z(p.z)
		var z := rear_z if on_rear else front_z
		if not is_nan(z) and not is_equal_approx(z, p.z):
			return {}
		if on_rear:
			rear_z = p.z
			rear_x.append(p.x)
		else:
			front_z = p.z
			front_x.append(p.x)
	if front_x.size() != 2 or rear_x.size() != 2:
		return {}
	var loads := BrakeSizing.wheel_loads(spec)
	var front_share := loads.x / (loads.x + loads.y)
	# The wing's split (`GroundDriveSpec.downforce_front`), else through the COM: the weight's.
	var downforce := VehicleMath.aero_downforce(speed, gd.downforce_area) if speed > 0.0 else 0.0
	var aero_front := gd.downforce_front if gd.downforce_front >= 0.0 else front_share
	var front := {"load": loads.x, "aero": downforce * aero_front / 2.0,
			"track": absf(front_x[0] - front_x[1]), "spring": gd.spring_rate,
			"bar": gd.anti_roll_rate, "mu": gd.mu_lat, "share": 1.0,
			"roll_steer": gd.roll_steer_front, "compliance_steer": 0.0, "mu_long": gd.mu_long,
			"driven": gd.driven_front,
			"diff_bias": gd.diff_bias_front}
	var rear := {"load": loads.y, "aero": downforce * (1.0 - aero_front) / 2.0,
			"track": absf(rear_x[0] - rear_x[1]),
			"spring": gd.rear_spring_rate(), "bar": gd.rear_anti_roll_rate(),
			"mu": gd.mu_lat * gd.rear_lat_grip, "share": 0.5 if gd.rear_twin_tyres else 1.0,
			"roll_steer": gd.roll_steer_rear, "compliance_steer": gd.compliance_steer_rear,
			"mu_long": gd.mu_long, "driven": gd.driven_rear,
			"diff_bias": gd.diff_bias_rear}
	# Each axle sags under its own load, downforce included; the COM sits between them by its
	# weight share.
	var sag := front_share * _sag(_normal(front), gd.spring_rate, gd) \
			+ (1.0 - front_share) * _sag(_normal(rear), gd.rear_spring_rate(), gd)
	var wheelbase := rear_z - front_z
	var a := wheelbase * (1.0 - front_share)
	var yaw_inertia := VehicleMath.yaw_inertia(spec.mass, spec.yaw_dynamic_index, a, wheelbase - a) \
			if spec.yaw_dynamic_index > 0.0 else NAN
	var yaw_damp := maxf(spec.angular_damping, 0.0)
	var peak_slip := 0.0
	var peak := -INF
	for pt in gd.grip_curve:
		if pt.y > peak:
			peak = pt.y
			peak_slip = pt.x
	# The mean angle's lock at `speed`, tapered as `WheelDrive.tick` tapers it.
	var taper := 1.0
	if gd.steer_falloff_speed > 0.0:
		taper = lerpf(1.0, gd.min_steer_frac, clampf(speed / gd.steer_falloff_speed, 0.0, 1.0))
	var h := spec.center_of_mass.y + gd.rest_ride_height() - sag
	# The aero centre over the road and ahead of the COM; ZERO acts through the live COM
	# (`WheelDrive.apply_at`).
	var at_com := gd.aero_centre == Vector3.ZERO
	return {"front": front, "rear": rear, "mass": spec.mass, "h": h,
			"side_area": gd.side_area,
			"aero_h": h if at_com else gd.aero_centre.y + gd.rest_ride_height() - sag,
			"aero_arm": 0.0 if at_com else spec.center_of_mass.z - gd.aero_centre.z,
			"ref": spec.mass * G / 4.0, "sensitivity": gd.load_sensitivity,
			"peak_slip": maxf(peak_slip, 1e-3), "peak_load": gd.cornering_peak_load,
			"wheelbase": wheelbase, "yaw_inertia": yaw_inertia, "yaw_damp": yaw_damp,
			"front_arm": a, "grip_curve": gd.grip_curve, "crr": gd.rolling_resistance,
			"drag_area": gd.drag_area, "ackermann": gd.ackermann,
			"lock": deg_to_rad(gd.max_steer_deg * taper), "centre_bias": gd.centre_diff_bias,
			"tcs": gd.tcs_equipped}


static func _sag(n_load: float, rate: float, gd: GroundDriveSpec) -> float:
	return clampf(n_load / maxf(rate, 1.0), 0.0, gd.rest_length)


## An axle's normal load per wheel (N), its weight plus its downforce share (`axles`). Downforce adds
## load, not mass: grip, stiffness, sag and the lift cap read this; the side force an axle must make,
## and every g, stay over `load`. At speed 0 it is `load` exactly.
static func _normal(axle: Dictionary) -> float:
	return float(axle["load"]) + float(axle.get("aero", 0.0))


## An axle's roll stiffness (N*m/rad).
static func _roll_stiffness(axle: Dictionary) -> float:
	return (float(axle["spring"]) / 2.0 + maxf(float(axle["bar"]), 0.0)) * pow(float(axle["track"]), 2.0)


## Body roll (deg) at `lat_g` of steady side force (`_roll_state`).
static func roll_deg(m: Dictionary, lat_g: float) -> float:
	if m.is_empty():
		return NAN
	return rad_to_deg(float(_roll_state(m, lat_g)["phi"]))


## Roll (`phi`, rad) and each axle's left-minus-right load change (`front`, `rear`, N) at `lat_g`.
## Elastic while both inner wheels stand: `phi = m ay h / (sum(K) - m g h)`. The rolled body's COM
## sits `h phi` off the roll centre on the ground, so its weight adds `m g h phi` to the cornering
## moment (~9 % of it at a car's ~5 deg/g; `measure_vehicles` reads the roll that much over the
## moment alone: the step pass's roll-steer angles, the corner pass's roll against its pred). An
## axle whose inner wheel lifts carries at most twice its wheel load (`_normal`) across it (moment
## `load * t`); the rest of the moment rolls the body on the other axle alone. Both lifted, or no
## stiffness left over the weight's: the body is tipping, roll reads INF.
static func _roll_state(m: Dictionary, lat_g: float) -> Dictionary:
	var f: Dictionary = m["front"]
	var r: Dictionary = m["rear"]
	var weight_h := float(m["mass"]) * G * float(m["h"])
	var moment := weight_h * absf(lat_g)
	var k_f := _roll_stiffness(f)
	var k_r := _roll_stiffness(r)
	var cap_f := 2.0 * _normal(f)
	var cap_r := 2.0 * _normal(r)
	if k_f + k_r <= weight_h:
		return {"phi": INF, "front": cap_f, "rear": cap_r}
	var phi := moment / (k_f + k_r - weight_h)
	var df := 2.0 * k_f * phi / float(f["track"])
	var dr := 2.0 * k_r * phi / float(r["track"])
	if df > cap_f and dr > cap_r or (df > cap_f and k_r <= weight_h) \
			or (dr > cap_r and k_f <= weight_h):
		return {"phi": INF, "front": cap_f, "rear": cap_r}
	if df > cap_f:
		df = cap_f
		phi = (moment - cap_f * float(f["track"]) / 2.0) / (k_r - weight_h)
		dr = 2.0 * k_r * phi / float(r["track"])
	elif dr > cap_r:
		dr = cap_r
		phi = (moment - cap_r * float(r["track"]) / 2.0) / (k_f - weight_h)
		df = 2.0 * k_f * phi / float(f["track"])
	if df > cap_f + 1e-3 or dr > cap_r + 1e-3:
		return {"phi": INF, "front": cap_f, "rear": cap_r}
	return {"phi": phi, "front": df, "rear": dr}


## An axle's left-minus-right load change (N) at `lat_g` (`_roll_state`).
static func _transfer(m: Dictionary, key: String, lat_g: float) -> float:
	return float(_roll_state(m, lat_g)[key])


## The front axle's share of the lateral load transfer (LLTD): `(k / 2 + bar) * t` per axle, as
## `measure_vehicles` reads it off the corners' spring loads.
static func lltd(m: Dictionary) -> float:
	if m.is_empty():
		return NAN
	var f: Dictionary = m["front"]
	var r: Dictionary = m["rear"]
	var front := _roll_stiffness(f) / float(f["track"])
	return front / (front + _roll_stiffness(r) / float(r["track"]))


## A wheel's cornering stiffness (N per unit slip) at `n_load` (`RayWheel.combined_slip_force` on the
## curve's linear rise), its tyres each carrying `share` of it (a twin pair: `2 C(L / 2)`).
static func wheel_stiffness(m: Dictionary, mu: float, n_load: float, share := 1.0) -> float:
	var ref: float = m["ref"]
	var peak_load: float = m["peak_load"]
	if peak_load > 0.0:
		# One tyre's load, floored as `RayWheel.lateral_peak_slip` floors it.
		var tyre := maxf(n_load * share, ref * 0.25)
		return mu * ref * maxf(n_load, 0.0) / (tyre * float(m["peak_slip"])) \
				* RayWheel.cornering_load_shape(tyre, ref, peak_load)
	return RayWheel.load_scaled_mu(mu, n_load * share, ref, float(m["sensitivity"])) \
			* maxf(n_load, 0.0) / float(m["peak_slip"])


## The two wheels' loads (N; x outer, y inner) on an axle carrying `transfer` across it, the inner
## held at 0 (lifted: the outer then carries the axle).
static func pair_loads(n_load: float, transfer: float) -> Vector2:
	var half := minf(absf(transfer) / 2.0, n_load)
	return Vector2(n_load + half, n_load - half)


## Understeer gradient (deg/g) at `lat_g`: the steer past the neutral `L / R` per g, the axles' slip
## difference `Wf / Cf - Wr / Cr` on their stiffness at the loads that g leaves them, plus roll
## and compliance steer (`roll_steer_gradient`, `compliance_steer_gradient`) at every speed. The
## secant, as the step pass reads it (exact while every wheel is under the curve's peak). At a
## finite `speed` (m/s) it adds the angular damping's share (`yaw_damping_gradient`, NAN without a
## yaw inertia); INF leaves it out. It omits the fore-aft forces across the track and the diffs'
## split, which the corner model (`corner_at`) carries: measured K reads over it
## (docs/handling.md § Balance).
static func understeer_gradient(m: Dictionary, lat_g: float, speed := INF) -> float:
	if m.is_empty():
		return NAN
	var k := 0.0
	for key: String in ["front", "rear"]:
		var axle: Dictionary = m[key]
		k += (1.0 if key == "front" else -1.0) * 2.0 * float(axle["load"]) \
				/ _axle_stiffness(m, key, lat_g)
	var damped := yaw_damping_gradient(m, lat_g, speed) if is_finite(speed) else 0.0
	return rad_to_deg(k) + roll_steer_gradient(m, lat_g) + compliance_steer_gradient(m) + damped


## Roll steer's understeer (deg/g) at `lat_g`: each axle steers `roll_steer` deg per deg of roll,
## the front out of the turn and the rear into it, so `(front + rear) * roll / g`, the secant like
## the rest. Exactly 0 with both coefficients 0, before roll is read (a tipping body's INF roll times 0
## would be NAN); INF once roll is, with a coefficient. NAN on an empty model. Read at 0.001 g or
## more: roll is elastic there, so the secant is the gradient a vanishing g asks for.
static func roll_steer_gradient(m: Dictionary, lat_g: float) -> float:
	if m.is_empty():
		return NAN
	var front: Dictionary = m["front"]
	var rear: Dictionary = m["rear"]
	var coeff := float(front.get("roll_steer", 0.0)) + float(rear.get("roll_steer", 0.0))
	if coeff == 0.0:
		return 0.0
	var g := maxf(absf(lat_g), 1e-3)
	return coeff * roll_deg(m, g) / g


## Compliance steer's understeer (deg/g): each axle's patches carry its static weight per wheel
## (`load`) per g at steady state, so `sum(coeff * load / 1000)`. Linear in g, so no secant.
## Exactly 0 with every coefficient 0; NAN on an empty model.
static func compliance_steer_gradient(m: Dictionary) -> float:
	if m.is_empty():
		return NAN
	var k := 0.0
	for key: String in ["front", "rear"]:
		var axle: Dictionary = m[key]
		k += float(axle.get("compliance_steer", 0.0)) * float(axle["load"]) / 1000.0
	return k


## Compliance steer's 60 Hz loop gain: the angle reads last tick's force, which the angle changes by
## the patch's cornering stiffness, so `F_n = F* + g (F_{n-1} - F*)` with
## `g = deg_to_rad(|coeff|) / 1000 * C_patch`, at the static load (`_axle_stiffness / 2`); the
## higher axle's. The one-tick lateral cap and the patch spring never slope over `C`, so it bounds
## the gain at every speed. Exactly 0 with every coefficient 0; NAN on an empty model.
static func compliance_loop_gain(m: Dictionary) -> float:
	if m.is_empty():
		return NAN
	var gain := 0.0
	for key: String in ["front", "rear"]:
		var coeff := float((m[key] as Dictionary).get("compliance_steer", 0.0))
		if coeff != 0.0:
			gain = maxf(gain, deg_to_rad(absf(coeff)) / 1000.0 * _axle_stiffness(m, key, 0.0) / 2.0)
	return gain


## An axle's cornering stiffness (N per unit slip) at the loads `lat_g` leaves it.
static func _axle_stiffness(m: Dictionary, key: String, lat_g: float) -> float:
	var axle: Dictionary = m[key]
	var loads := pair_loads(_normal(axle), _transfer(m, key, lat_g))
	var share: float = axle["share"]
	return maxf(wheel_stiffness(m, float(axle["mu"]), loads.x, share)
			+ wheel_stiffness(m, float(axle["mu"]), loads.y, share), 1e-6)


## The angular damping's understeer (deg/g) at `speed` (m/s): the steady yaw rate `lat_g * g / v`
## costs the moment `I * c * r`, a side force `I c r / L` the front adds and the rear sheds, each axle
## slipping that much more or less. It falls as 1 / v. Exactly 0 with no damping (every declared
## wheeled body), before the inertia is read; else NAN without a yaw inertia.
static func yaw_damping_gradient(m: Dictionary, lat_g: float, speed: float) -> float:
	if m.is_empty() or lat_g <= 0.0 or speed <= 0.0:
		return NAN
	if float(m["yaw_damp"]) == 0.0:
		return 0.0
	var force := float(m["yaw_inertia"]) * float(m["yaw_damp"]) * lat_g * G / speed \
			/ float(m["wheelbase"])
	var slip := force * (1.0 / _axle_stiffness(m, "front", lat_g)
			+ 1.0 / _axle_stiffness(m, "rear", lat_g))
	return rad_to_deg(slip / lat_g)


## Two wheels' peak side force (N), `mu(L) * L` each at `pair_loads`, the mu read at the load one
## tyre carries (`share` of it).
static func pair_grip(mu: float, n_load: float, transfer: float, ref: float,
		sensitivity: float, share := 1.0) -> float:
	var loads := pair_loads(n_load, transfer)
	return loads.x * RayWheel.load_scaled_mu(mu, loads.x * share, ref, sensitivity) \
			+ loads.y * RayWheel.load_scaled_mu(mu, loads.y * share, ref, sensitivity)


## Each axle's side capacity in g of its own static weight at `lat_g` (x front, y rear): the axle
## whose figure is lower saturates first. Roll and compliance steer are not in it: they move the
## steer a side force needs, never the force an axle can make, so `limit` reads the same with or
## without them.
static func axle_capacity_g(m: Dictionary, lat_g: float) -> Vector2:
	if m.is_empty():
		return Vector2(NAN, NAN)
	var out := Vector2.ZERO
	for i in 2:
		var key := "front" if i == 0 else "rear"
		var axle: Dictionary = m[key]
		out[i] = pair_grip(float(axle["mu"]), _normal(axle), _transfer(m, key, lat_g), float(m["ref"]),
				float(m["sensitivity"]), float(axle["share"])) / (2.0 * float(axle["load"]))
	return out


## The steady-state limit: `g` where the first axle saturates, settled by a few passes (the transfer
## depends on the g it limits), each axle's capacity there (`front`, `rear`), and `margin`, the rear's
## over the front's less 1 (+ = the front washes out first, understeer at the limit). Roll and
## compliance steer never move it (`axle_capacity_g`).
static func limit(m: Dictionary) -> Dictionary:
	if m.is_empty():
		return {}
	var g := 0.0
	var caps := Vector2.ZERO
	for _pass in 8:
		caps = axle_capacity_g(m, g)
		g = minf(caps.x, caps.y)
	return {"g": g, "front": caps.x, "rear": caps.y, "margin": caps.y / caps.x - 1.0}


const CORNER_NEWTON_STEPS := 30
## The passes `_corner_state` takes a body's compliance steer through its own tyres' force, each
## shrinking the error by the loop's gain (~0.02, `compliance_loop_gain`); none without it.
const CORNER_COMPLIANCE_PASSES := 2
## The mean steer's step (deg) as `corner_limit` winds the lock on.
const CORNER_SWEEP_DEG := 0.5
## A wheel's drive force off its target by more than this fraction misses it.
const _CARRY_TOL := 1e-3


## The corner pass's steady turn (`docs/handling.md` § Balance): a left turn at `speed` (m/s, the
## COM's) on the mean steer `steer` (rad, >= 0; empty below), each wheel's slip off `beta` and the
## yaw rate at its Ackermann angle plus its roll and compliance steer, its force off the runtime
## law at its arm about the rolled body's COM, the air at the aero centre, the drive holding the speed split by the diffs and TC
## (`_split_drive`). Newton on (`beta`, yaw rate, drive) from `guess` (a previous result), else
## wound on from straight (`_wind_on`). Returns `lat_g` (`v r / g`), `front` / `rear`
## (`_axle_saturation`'s shares), `beta`, `yaw_rate`, `steer`, `drive` (the shaft's), `drive_front` /
## `drive_rear` (what the tyres carry), `wheels`; empty where no steady turn holds (`_solve_corner`).
## Left out, a few newtons: a centre's split by wheel radius. A rigid centre and the rear lock read
## as open (the tractor's, both off).
static func corner(m: Dictionary, speed: float, steer: float, guess := {}) -> Dictionary:
	if m.is_empty() or speed <= 0.0 or steer < 0.0:
		return {}
	var turn := _solve_corner(m, speed, steer, guess)
	return {} if turn.has("fails") else turn


## `corner`'s solve on a model, `speed` > 0 and `steer` >= 0: its result, or `{fails}` where no
## steady turn holds, `fold` (Newton finds no balance of side force and yaw: past the rear's fold,
## or a kink it does not cross), `drive` (the driven wheels cannot carry the drive holding the
## speed: one no TC holds past its grip, every one held, or nothing driven) or `tip` (Newton's turn
## tips the body, `_roll_state`: past `tip_g` no turn is steady).
static func _solve_corner(m: Dictionary, speed: float, steer: float, guess := {}) -> Dictionary:
	if guess.is_empty() and steer > deg_to_rad(CORNER_SWEEP_DEG):
		# Newton from the kinematic turn holds near straight only: wind the steer on to it.
		var walk := _wind_on(m, speed, steer)
		return walk["turn"] if walk["end"] == "lock" else {"fails": walk["end"]}
	return _newton_corner(m, speed, steer, guess)


## The mean steer wound on from straight to `to` (rad) as the corner pass winds it: CORNER_SWEEP_DEG
## steps, each solve continued from the last turn that held, the step halved where one fails, down
## to 0.01 deg. `visit(turn, prev)` sees each turn that holds and the one before it (empty at
## straight); true stops the walk there. Returns `end` (`lock`: it reached `to`; `visit`; or the
## failure past the floor, `fold` / `drive` / `tip`), `turn` (the last that held; empty if none)
## and `step` (the step it ended on).
static func _wind_on(m: Dictionary, speed: float, to: float, visit := Callable()) -> Dictionary:
	var step := deg_to_rad(CORNER_SWEEP_DEG)
	var prev := {}
	var steer := 0.0
	while steer < to:
		var next := minf(steer + step, to)
		var turn := _newton_corner(m, speed, next, prev)
		if turn.has("fails"):
			if step < deg_to_rad(0.01):
				return {"end": turn["fails"], "turn": prev, "step": step}
			step /= 2.0
			continue
		var stop := visit.is_valid() and bool(visit.call(turn, prev))
		prev = turn
		steer = next
		if stop:
			return {"end": "visit", "turn": turn, "step": step}
	return {"end": "lock", "turn": prev, "step": step}


## Newton on (`beta`, yaw rate, drive) at `steer` from `guess`, else from the kinematic turn (which
## holds near straight only: `_wind_on`). `_solve_corner`'s result.
static func _newton_corner(m: Dictionary, speed: float, steer: float, guess: Dictionary) -> Dictionary:
	var wheelbase := float(m["wheelbase"])
	var x := PackedFloat64Array([0.0, 0.0, 0.0])
	if guess.is_empty():
		var r0 := speed * tan(steer) / wheelbase
		x[0] = (wheelbase - float(m["front_arm"])) * r0 / speed
		x[1] = r0
		x[2] = float(m["crr"]) * float(m["mass"]) * G \
				+ VehicleMath.aero_drag(speed, float(m["drag_area"]))
	else:
		x = PackedFloat64Array([float(guess["beta"]), float(guess["yaw_rate"]),
				float(guess["drive"])])
	var weight := float(m["mass"]) * G
	var tol := PackedFloat64Array([1e-4 * weight, 1e-4 * weight, 1e-4 * weight * wheelbase])
	# Steps for the differences, well over the tyre law's float32 rounding (~1e-3 N here).
	var h := PackedFloat64Array([1e-5, 1e-5, 1e-5 * weight])
	for _i in CORNER_NEWTON_STEPS:
		var state := _corner_state(m, speed, steer, x)
		if bool(state["tipping"]):
			return {"fails": "tip"}
		var res: PackedFloat64Array = state["residual"]
		if absf(res[0]) < tol[0] and absf(res[1]) < tol[1] and absf(res[2]) < tol[2]:
			return state if bool(state["holds"]) else {"fails": "drive"}
		var jac: Array[PackedFloat64Array] = []
		for j in 3:
			var xj := x.duplicate()
			xj[j] += h[j]
			var rj: PackedFloat64Array = _corner_state(m, speed, steer, xj)["residual"]
			jac.append(PackedFloat64Array([(rj[0] - res[0]) / h[j], (rj[1] - res[1]) / h[j],
					(rj[2] - res[2]) / h[j]]))
		var dx := _solve3(jac, res)
		if dx.is_empty():
			# A drive that moves no force: every driven wheel held, or none driven.
			var dead := absf(jac[2][0]) + absf(jac[2][1]) + absf(jac[2][2]) < 1e-9
			return {"fails": "drive" if dead else "fold"}
		for j in 3:
			x[j] -= dx[j]
	return {"fails": "fold"}


## `corner` swept as the pass winds it: the mean steer from 0 to `lock`, continued from each
## solution, the peak `lat_g` refined between its neighbours. Returns that peak's `corner` result
## plus `margin` (the front's share over the rear's at that peak, less 1: + = the front leads),
## `at_lock` (the peak sits on the lock), `end` (where the sweep stopped: `lock`, or
## `_solve_corner`'s `fold` / `drive` / `tip`, the last turn that holds then the peak), `tip_g`, and
## `tips` (the sweep ended on the tip: the body tips before its peak, so no axle saturates first).
static func corner_limit(m: Dictionary, speed: float) -> Dictionary:
	if m.is_empty() or speed <= 0.0:
		return {}
	var lock := float(m["lock"])
	var best := {}
	var keep_best := func(turn: Dictionary, _prev: Dictionary) -> bool:
		if best.is_empty() or float(turn["lat_g"]) > float(best["lat_g"]):
			best.assign(turn)
		return false
	var walk := _wind_on(m, speed, lock, keep_best)
	var step := float(walk["step"])
	var end: String = walk["end"]
	if best.is_empty():
		return {}
	# Ternary search on the bracket around the sweep's peak, each probe continued from the peak.
	var lo := maxf(float(best["steer"]) - step, 0.0)
	var hi := minf(float(best["steer"]) + step, lock)
	var peak := best
	for _i in 12:
		var third := (hi - lo) / 3.0
		var left := corner(m, speed, lo + third, peak)
		var right := corner(m, speed, hi - third, peak)
		var g_left := float(left["lat_g"]) if not left.is_empty() else -INF
		var g_right := float(right["lat_g"]) if not right.is_empty() else -INF
		if g_left < g_right:
			lo += third
		else:
			hi -= third
		for probe: Dictionary in [left, right]:
			if not probe.is_empty() and float(probe["lat_g"]) > float(best["lat_g"]):
				best = probe
	best["margin"] = float(best["front"]) / maxf(float(best["rear"]), 1e-6) - 1.0
	best["at_lock"] = float(best["steer"]) >= lock - 1e-6
	best["end"] = end
	best["tip_g"] = tip_g(m)
	best["tips"] = end == "tip"
	return best


## The least steady g at which `_roll_state` tips the body (both inner wheels lifted, or the
## springs left under the weight's moment), bisected to 1e-4 g; INF if it never does under 3 g.
static func tip_g(m: Dictionary) -> float:
	if m.is_empty():
		return NAN
	if is_finite(roll_deg(m, 3.0)):
		return INF
	var lo := 0.0
	var hi := 3.0
	while hi - lo > 1e-4:
		var mid := (lo + hi) / 2.0
		if is_finite(roll_deg(m, mid)):
			lo = mid
		else:
			hi = mid
	return hi


## `corner` at `lat_g`: the steer wound on as `corner_limit` winds it, then bisected inside the step
## that passes `lat_g`, each probe continued from the last turn under it. Empty past the peak or the
## tip.
static func corner_at(m: Dictionary, speed: float, lat_g: float) -> Dictionary:
	if m.is_empty() or speed <= 0.0:
		return {}
	var found := {}
	var bisect := func(turn: Dictionary, prev: Dictionary) -> bool:
		if float(turn["lat_g"]) < lat_g:
			return false
		var below := prev
		var lo := float(prev["steer"]) if not prev.is_empty() else 0.0
		var hi := float(turn["steer"])
		var above := turn
		for _i in 20:
			var mid := (lo + hi) / 2.0
			var probe := corner(m, speed, mid, below)
			if probe.is_empty() or float(probe["lat_g"]) >= lat_g:
				hi = mid
				if not probe.is_empty():
					above = probe
			else:
				lo = mid
				below = probe
		found.assign(above)
		return true
	_wind_on(m, speed, float(m["lock"]), bisect)
	return found


## Axle `key`'s outer corner's compression past its inner's (m) under `roll` (`_roll_state`), what
## `RayWheel.roll_steer` reads. Both corners loaded: the transfer over the pair's rate
## `spring + 2 bar`. Its inner corner unloaded: the outer carries the axle, and the inner's ray reads
## the body's roll over the track (the bar still pushing the outer, `RayWheel.bar_force`) until it
## no longer reaches the road, then full droop under the outer's spring alone. Tipping (no steady
## turn, `_newton_corner`) reads full droop.
static func _axle_rolled(m: Dictionary, key: String, roll: Dictionary) -> float:
	var axle: Dictionary = m[key]
	var spring := maxf(float(axle["spring"]), 1.0)
	var bar := maxf(float(axle["bar"]), 0.0)
	var cap := 2.0 * _normal(axle)
	var transfer := float(roll[key])
	if transfer < cap:
		return transfer / (spring + 2.0 * bar)
	var phi := float(roll["phi"])
	var geometric := float(axle["track"]) * phi
	# The outer at the axle's load with the bar on: `(spring + bar) c_o - bar c_i = cap`.
	if is_finite(phi) and (cap - bar * geometric) / spring > geometric:
		return geometric
	return cap / spring


## `corner`'s equations at the state `x` (`beta`, yaw rate, drive): the residual of the body's
## longitudinal, lateral and yaw balance (N, N, N*m), and what `corner` reports. `holds` is false
## once a driven wheel no traction control holds cannot carry its share of the drive; `tipping` once
## `_roll_state` tips the body at its `v r`.
static func _corner_state(m: Dictionary, speed: float, steer: float,
		x: PackedFloat64Array) -> Dictionary:
	var beta := x[0]
	var r := x[1]
	var drive := x[2]
	var mass := float(m["mass"])
	var wheelbase := float(m["wheelbase"])
	var front_arm := float(m["front_arm"])
	# The speed's own rate along the path (`accel`, m/s^2, a caller's; absent = a steady turn) beside
	# the turn's.
	var accel := float(m.get("accel", 0.0))
	var acc_long := accel * cos(beta) - speed * r * sin(beta)
	var acc_lat := accel * sin(beta) + speed * r * cos(beta)
	# The air on the body as `VehicleMath.air_force` puts it, along and across the body (+ = forward,
	# left), at the aero centre: drag on `drag_area`, the side force on `side_area`. Its height
	# pitches load off the front and rolls the body against the turn, and its arm yaws it.
	var q_over_v := 0.5 * VehicleMath.AIR_DENSITY * speed
	var aero_u := -q_over_v * maxf(float(m["drag_area"]), 0.0) * speed * cos(beta)
	var aero_w := -q_over_v * maxf(float(m.get("side_area", 0.0)), 0.0) * speed * sin(beta) \
			if float(m["drag_area"]) > 0.0 else 0.0
	var aero_h := float(m.get("aero_h", m["h"]))
	var h := float(m["h"])
	var roll := _roll_state(m, absf(acc_lat) / G if aero_w == 0.0
			else absf(mass * acc_lat * h - aero_w * aero_h) / (mass * G * h))
	# Per front wheel; the rear sheds it.
	var pitch := (-mass * acc_long * h + aero_u * aero_h) / wheelbase / 2.0
	# Each axle's side force per patch (N, + = right as `force_lat`: a left turn pushes the body left)
	# that its compliance steer reads: first its equilibrium share of `m a_y`, then what its own tyres
	# make at the angle that share gives, as the runtime's latch reads its last tick
	# (`RayWheel.compliance_steer`). The fore-aft forces across the track (the steered fronts' side
	# forces, the outer wheels' larger rolling drag) yaw the body out of the turn, so the rear carries
	# 1-4 % under its share. The loop's gain (~0.02, `compliance_loop_gain`) leaves the second pass
	# within ~1e-5 of the fixed point.
	var patch := {"front": -mass * acc_lat * (wheelbase - front_arm) / wheelbase / 2.0,
			"rear": -mass * acc_lat * front_arm / wheelbase / 2.0}
	var eval := _corner_wheels(m, speed, steer, x, roll, pitch, patch)
	if float((m["front"] as Dictionary).get("compliance_steer", 0.0)) != 0.0 \
			or float((m["rear"] as Dictionary).get("compliance_steer", 0.0)) != 0.0:
		for _pass in CORNER_COMPLIANCE_PASSES:
			for key: String in patch:
				patch[key] = 0.0
			for w: Dictionary in eval["wheels"]:
				patch[w["axle"]] -= float(w["fy"]) / 2.0
			eval = _corner_wheels(m, speed, steer, x, roll, pitch, patch)
	var residual := PackedFloat64Array([float(eval["force_f"]) + aero_u - mass * acc_long,
			float(eval["force_l"]) + aero_w - mass * acc_lat,
			float(eval["moment"]) + aero_w * float(m.get("aero_arm", 0.0))])
	var reach_sum: Dictionary = eval["reach_sum"]
	var budget_sum: Dictionary = eval["budget_sum"]
	var drives: Dictionary = eval["drives"]
	return {"residual": residual, "holds": eval["holds"],
			"tipping": not is_finite(float(roll["phi"])), "lat_g": speed * absf(r) / G,
			"front": float(reach_sum["front"]) / maxf(float(budget_sum["front"]), 1.0),
			"rear": float(reach_sum["rear"]) / maxf(float(budget_sum["rear"]), 1.0),
			"beta": beta, "yaw_rate": r, "drive": drive, "drive_front": drives["front"],
			"drive_rear": drives["rear"], "steer": steer, "wheels": eval["wheels"]}


## `_corner_state`'s wheels at the state `x` under `roll` and `pitch` (N per front wheel), each axle's
## compliance steer off `patch` (its side force per patch, N, + = right): each wheel's angle, load,
## slips, drive, compliance-steer angle (`complied`, rad, + = left), tyre force (`fx`, `fy`, + =
## forward / left) and arms about the COM (`x`, + = right, the rolled body's; `z`, + = forward), and
## the body's summed forces (`force_f`, `force_l`), yaw moment (+ = left),
## `holds`, and per axle the ellipse sums (`reach_sum`, `budget_sum`) and the drive its tyres carry
## (`drives`).
static func _corner_wheels(m: Dictionary, speed: float, steer: float, x: PackedFloat64Array,
		roll: Dictionary, pitch: float, patch: Dictionary) -> Dictionary:
	var beta := x[0]
	var r := x[1]
	var drive := x[2]
	var wheelbase := float(m["wheelbase"])
	var front_arm := float(m["front_arm"])
	var curve: PackedVector2Array = m["grip_curve"]
	var ref := float(m["ref"])
	var sens := float(m["sensitivity"])
	var wheels: Array[Dictionary] = []
	# The rolled body carries its COM `h sin(phi)` outboard of the patches (the roll centre is the
	# ground), so each patch's arm about it sits that much inboard: ~3 cm on a car at 0.5 g, through
	# which the fore-aft forces yaw the body out of the turn. Pitch's fore-aft shift (1-2 mm while the
	# step pass's speed recovers) is left out.
	var phi := float(roll["phi"])
	var roll_cos := cos(phi) if is_finite(phi) else 1.0
	var shift := float(m["h"]) * sin(phi) if is_finite(phi) else 0.0
	for key: String in ["front", "rear"]:
		var axle: Dictionary = m[key]
		var on_front := key == "front"
		var half := float(axle["track"]) / 2.0
		var z := front_arm if on_front else front_arm - wheelbase
		var loads := pair_loads(_normal(axle) + (pitch if on_front else -pitch), float(roll[key]))
		var rolled := _axle_rolled(m, key, roll)
		var complied := RayWheel.compliance_steer_angle(float(patch[key]), float(patch[key]),
				float(axle.get("compliance_steer", 0.0)))
		# A left turn: the inner wheel is the left one (x + = right, as the spec's positions).
		for inner: bool in [true, false]:
			var x_right := -half if inner else half
			# Each wheel's roll steer off its axle's compressions, as `WheelDrive.wheel_steer_angle`
			# adds it: the outer (right) corner compressed `rolled` past the inner.
			var angle := (WheelDrive.ackermann_angle(steer, x_right, wheelbase,
					float(m["ackermann"])) if on_front else 0.0) \
					+ RayWheel.roll_steer_angle(0.0 if inner else rolled, rolled if inner else 0.0,
					x_right, -x_right, float(axle.get("roll_steer", 0.0)), not on_front) + complied
			var x_com := x_right * roll_cos - shift
			var v_f := speed * cos(beta) + r * x_com
			var v_l := speed * sin(beta) + r * z
			wheels.append({"axle": key, "inner": inner, "x": x_com, "z": z, "angle": angle,
					"complied": complied, "load": loads.y if inner else loads.x,
					"v_long": v_f * cos(angle) + v_l * sin(angle),
					"v_lat": -v_f * sin(angle) + v_l * cos(angle)})
	for w in wheels:
		var axle: Dictionary = m[w["axle"]]
		var n_load := maxf(float(w["load"]), 0.0)
		w["load"] = n_load
		w["budget_long"] = RayWheel.load_scaled_mu(float(axle["mu_long"]), n_load, ref, sens) * n_load
		w["budget_lat"] = RayWheel.load_scaled_mu(float(axle["mu"]), n_load * float(axle["share"]),
				ref, sens) * n_load
		w["lat_peak"] = RayWheel.lateral_peak_slip(n_load * float(axle["share"]), ref, sens,
				float(m["peak_load"]))
		w["slip_lat"] = -float(w["v_lat"]) / maxf(absf(float(w["v_long"])), 1e-3)
	_split_drive(m, wheels, drive)
	var force_f := 0.0
	var force_l := 0.0
	var moment := 0.0
	var holds := true
	var reach_sum := {"front": 0.0, "rear": 0.0}
	var budget_sum := {"front": 0.0, "rear": 0.0}
	var drives := {"front": 0.0, "rear": 0.0}
	for w in wheels:
		var n_load := float(w["load"])
		var budget_long := float(w["budget_long"])
		var budget_lat := float(w["budget_lat"])
		var target := float(w["target"])
		var tyre := RayWheel.combined_slip_force(float(w["kappa"]), float(w["slip_lat"]), budget_long,
				budget_lat, curve, float(w["lat_peak"]))
		if not bool(w["tc"]) and absf(tyre.x - target) > _CARRY_TOL * maxf(absf(target), 1.0):
			holds = false
		var fx := float(tyre.x) - VehicleMath.rolling_drag(float(m["crr"]), n_load)
		var fy := float(tyre.y)
		var angle := float(w["angle"])
		var along := fx * cos(angle) - fy * sin(angle)
		var across := fx * sin(angle) + fy * cos(angle)
		force_f += along
		force_l += across
		# Yaw, + = left: the forward offset times the left force, less the left offset (-x) times
		# the forward one.
		moment += float(w["z"]) * across + float(w["x"]) * along
		if budget_lat > 0.0 and budget_long > 0.0:
			reach_sum[w["axle"]] += Vector2(float(tyre.x) / budget_long, fy / budget_lat).length() \
					* budget_lat
			budget_sum[w["axle"]] += budget_lat
		drives[w["axle"]] += float(tyre.x)
		w["fx"] = float(tyre.x)
		w["fy"] = fy
	return {"wheels": wheels, "force_f": force_f, "force_l": force_l, "moment": moment,
			"holds": holds, "reach_sum": reach_sum, "budget_sum": budget_sum, "drives": drives}


## Each wheel's drive `target` (N), its slip ratio `kappa` and whether traction control holds it
## (`tc`), set on `wheels` (as `_corner_state` builds them) for the shaft's `drive` (N at the
## wheels): the centre splits it between the driven axles and each axle's diff between its wheels
## (`_diff_split`), on the spins their slips leave them.
static func _split_drive(m: Dictionary, wheels: Array[Dictionary], drive: float) -> void:
	for w in wheels:
		w["target"] = 0.0
		w["kappa"] = 0.0
		w["tc"] = false
	var front_driven := bool((m["front"] as Dictionary)["driven"])
	var rear_driven := bool((m["rear"] as Dictionary)["driven"])
	if front_driven and rear_driven:
		var spread := func(share: float) -> float:
			return _axle_drive(m, wheels, "front", share * drive) \
					- _axle_drive(m, wheels, "rear", (1.0 - share) * drive)
		var front_share := _diff_split(spread, float(m["centre_bias"]))
		_axle_drive(m, wheels, "front", front_share * drive)
		_axle_drive(m, wheels, "rear", (1.0 - front_share) * drive)
	elif front_driven or rear_driven:
		_axle_drive(m, wheels, "front" if front_driven else "rear", drive)


## Axle `key`'s two wheels driven with `target` (N) through its diff: their targets, slips and holds
## set (`_wheel_drive`), and their mean spin (m/s at the patch) returned.
static func _axle_drive(m: Dictionary, wheels: Array[Dictionary], key: String,
		target: float) -> float:
	var pair: Array[Dictionary] = []
	for w in wheels:
		if w["axle"] == key:
			pair.append(w)
	# `_corner_state` builds each axle inner wheel first.
	var spread := func(share: float) -> float:
		return _wheel_drive(m, pair[0], share * target) - _wheel_drive(m, pair[1],
				(1.0 - share) * target)
	var inner_share := _diff_split(spread, float((m[key] as Dictionary)["diff_bias"]))
	return (_wheel_drive(m, pair[0], inner_share * target)
			+ _wheel_drive(m, pair[1], (1.0 - inner_share) * target)) / 2.0


## A wheel driven with `target` (N): the slip that carries it (`_drive_slip`), held at TCS_SLIP where
## traction control takes off the drive it cannot carry: past that slip, or at no slip at all (a
## lifted wheel spins up to the hold), its diff partner keeping its own share as the runtime hold
## leaves it. Sets `target`, `kappa`, `tc` on `w`; returns its spin (m/s at the patch).
static func _wheel_drive(m: Dictionary, w: Dictionary, target: float) -> float:
	var kappa := _drive_slip(target, float(w["slip_lat"]), float(w["budget_long"]),
			float(w["budget_lat"]), m["grip_curve"], float(w["lat_peak"]), float(m["peak_slip"]))
	var held := false
	if bool(m["tcs"]) and target != 0.0:
		var carried := RayWheel.combined_slip_force(kappa, float(w["slip_lat"]),
				float(w["budget_long"]), float(w["budget_lat"]), m["grip_curve"],
				float(w["lat_peak"])).x
		held = absf(kappa) > RayWheel.TCS_SLIP or absf(carried - target) > _CARRY_TOL \
				* maxf(absf(target), 1.0)
	if held:
		kappa = RayWheel.TCS_SLIP * signf(target)
	w["target"] = target
	w["kappa"] = kappa
	w["tc"] = held
	return float(w["v_long"]) * (1.0 + kappa)


## Side a's share of a diff's torque (`Differential`): an even split, which the coupling moves toward
## the slower side up to the bias, `[1, bias] / (1 + bias)`; between, the two sides turn as one.
## `spread(share)` is side a's spin less side b's with side a taking `share`, rising with it.
static func _diff_split(spread: Callable, bias: float) -> float:
	if bias <= 1.0:
		return 0.5
	var lo := 1.0 / (1.0 + bias)
	var hi := bias / (1.0 + bias)
	if float(spread.call(hi)) <= 0.0:
		return hi
	if float(spread.call(lo)) >= 0.0:
		return lo
	for _i in 20:
		var mid := (lo + hi) / 2.0
		if float(spread.call(mid)) > 0.0:
			hi = mid
		else:
			lo = mid
	return (lo + hi) / 2.0


## The least slip ratio at which a wheel at side slip `slip_lat` carries `target` (N) along it, as
## the wheel spins up to it: the curve's rising side first (the combined slip at its peak
## `peak_slip`), then on past it in quarter-peak steps to a slip ratio of 1, regula falsi (Illinois)
## inside the first step that carries it. A wheel already past its side peak still pulls on the
## falling side. Where no slip carries it, the most it pulls: the wheel cannot hold the drive.
static func _drive_slip(target: float, slip_lat: float, budget_long: float, budget_lat: float,
		curve: PackedVector2Array, lat_peak: float, peak_slip: float) -> float:
	if target == 0.0 or budget_long <= 0.0:
		return 0.0
	var side := slip_lat / lat_peak
	var dir := signf(target)
	var miss := func(k: float) -> float:
		return (RayWheel.combined_slip_force(k, slip_lat, budget_long, budget_lat, curve, lat_peak).x
				- target) * dir
	var lo := 0.0
	var hi := sqrt(maxf(peak_slip * peak_slip - side * side, 0.0)) * dir
	var f_lo: float = miss.call(lo)
	var f_hi: float = miss.call(hi)
	var best := hi
	var best_f := f_hi
	while f_hi < 0.0:
		if absf(hi) >= 1.0:
			return best
		lo = hi
		f_lo = f_hi
		hi = clampf(hi + peak_slip / 4.0 * dir, -1.0, 1.0)
		f_hi = miss.call(hi)
		if f_hi > best_f:
			best = hi
			best_f = f_hi
	if f_lo >= 0.0:
		return lo
	var kept := 0
	for _i in 60:
		var k := (lo * f_hi - hi * f_lo) / (f_hi - f_lo)
		var f_k: float = miss.call(k)
		if absf(f_k) < 1e-6 * maxf(absf(target), 1.0):
			return k
		if signf(f_k) == signf(f_lo):
			lo = k
			f_lo = f_k
			if kept == -1:
				f_hi /= 2.0
			kept = -1
		else:
			hi = k
			f_hi = f_k
			if kept == 1:
				f_lo /= 2.0
			kept = 1
	return (lo + hi) / 2.0


## `a x = b` for the 3x3 `a` given by its columns (Cramer's rule); empty when singular.
static func _solve3(cols: Array[PackedFloat64Array], b: PackedFloat64Array) -> PackedFloat64Array:
	var det := _det3(cols[0], cols[1], cols[2])
	if absf(det) < 1e-300:
		return PackedFloat64Array()
	return PackedFloat64Array([_det3(b, cols[1], cols[2]) / det, _det3(cols[0], b, cols[2]) / det,
			_det3(cols[0], cols[1], b) / det])


static func _det3(c0: PackedFloat64Array, c1: PackedFloat64Array, c2: PackedFloat64Array) -> float:
	return c0[0] * (c1[1] * c2[2] - c2[1] * c1[2]) - c1[0] * (c0[1] * c2[2] - c2[1] * c0[2]) \
			+ c2[0] * (c0[1] * c1[2] - c1[1] * c0[2])
