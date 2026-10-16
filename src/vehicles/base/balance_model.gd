class_name BalanceModel
extends RefCounted
## A two-axle body's steady-state handling balance as pure arithmetic over its spec, which
## `tools/gen_kenney_vehicles.gd` reports and `measure_vehicles` prints beside its step and corner
## readings. RayWheel pushes at the patch, so the roll centre is the ground: an axle's roll stiffness
## is `(k / 2 + bar) * t^2` and every newton of transfer goes through it. Below the grip curve's peak
## a wheel's side force is exactly its cornering stiffness times its slip. The angular damping's yaw
## moment `I * c * r` is a term of its own. Derivation and calibration: `docs/vehicles.md`
## § Balance. The model is a plain Dictionary (`axles`), so a what-if edits it.

const G := BrakeSizing.G


## The model of `spec`, empty unless the body stands on exactly one front and one rear pair (a
## tandem, a semi's kingpin load or a single axle is not predicted):
## - `front` / `rear`: `load` (static N per wheel), `track` (m), `spring` (N/m per corner), `bar` (N/m),
##   `mu` (side mu at the reference load, `rear_lat_grip` included), `share` (`RayWheel.tyre_share`);
## - `mass` (kg), `h` (COM over the road at the static sag, m), `ref` (the even corner load, N,
##   `RayWheel.corner_mass * g`), `sensitivity` (`load_sensitivity`), `peak_slip` (the grip curve's
##   peak), `peak_load` (`cornering_peak_load`, x `ref`; 0 = off);
## - `wheelbase` (m), `yaw_inertia` (kg*m^2, the declared `yaw_dynamic_index`; NAN where Jolt computes
##   it, which a caller holding the live body fills in), `yaw_damp` (1/s, `angular_damping` or the
##   project's default, as `BaseVehicle` sets it).
static func axles(spec: VehicleSpec) -> Dictionary:
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
	var front := {"load": loads.x, "track": absf(front_x[0] - front_x[1]), "spring": gd.spring_rate,
			"bar": gd.anti_roll_rate, "mu": gd.mu_lat, "share": 1.0}
	var rear := {"load": loads.y, "track": absf(rear_x[0] - rear_x[1]),
			"spring": gd.rear_spring_rate(), "bar": gd.rear_anti_roll_rate(),
			"mu": gd.mu_lat * gd.rear_lat_grip, "share": 0.5 if gd.rear_twin_tyres else 1.0}
	# Each axle sags under its own static load; the COM sits between them by its weight share.
	var front_share := loads.x / (loads.x + loads.y)
	var sag := front_share * _sag(loads.x, gd.spring_rate, gd) \
			+ (1.0 - front_share) * _sag(loads.y, gd.rear_spring_rate(), gd)
	var wheelbase := rear_z - front_z
	var a := wheelbase * (1.0 - front_share)
	var yaw_inertia := VehicleMath.yaw_inertia(spec.mass, spec.yaw_dynamic_index, a, wheelbase - a) \
			if spec.yaw_dynamic_index > 0.0 else NAN
	var yaw_damp := spec.angular_damping if spec.angular_damping > 0.0 \
			else float(ProjectSettings.get_setting("physics/3d/default_angular_damp", 0.0))
	var peak_slip := 0.0
	var peak := -INF
	for pt in gd.grip_curve:
		if pt.y > peak:
			peak = pt.y
			peak_slip = pt.x
	return {"front": front, "rear": rear, "mass": spec.mass,
			"h": spec.center_of_mass.y + gd.rest_ride_height() - sag,
			"ref": spec.mass * G / 4.0, "sensitivity": gd.load_sensitivity,
			"peak_slip": maxf(peak_slip, 1e-3), "peak_load": gd.cornering_peak_load,
			"wheelbase": wheelbase, "yaw_inertia": yaw_inertia, "yaw_damp": yaw_damp}


static func _sag(n_load: float, rate: float, gd: GroundDriveSpec) -> float:
	return clampf(n_load / maxf(rate, 1.0), 0.0, gd.rest_length)


## An axle's roll stiffness (N*m/rad).
static func _roll_stiffness(axle: Dictionary) -> float:
	return (float(axle["spring"]) / 2.0 + maxf(float(axle["bar"]), 0.0)) * pow(float(axle["track"]), 2.0)


## Body roll (deg) at `lat_g` of steady side force (`_roll_state`).
static func roll_deg(m: Dictionary, lat_g: float) -> float:
	if m.is_empty():
		return NAN
	return rad_to_deg(float(_roll_state(m, lat_g)["phi"]))


## Roll (`phi`, rad) and each axle's left-minus-right load change (`front`, `rear`, N) at `lat_g`.
## Elastic while both inner wheels stand: `phi = m ay h / sum(K)`. An axle whose inner wheel lifts
## carries at most twice its static wheel load across it (moment `load * t`); the rest of the moment
## rolls the body on the other axle alone. Both lifted: the body is tipping, and roll reads INF.
static func _roll_state(m: Dictionary, lat_g: float) -> Dictionary:
	var f: Dictionary = m["front"]
	var r: Dictionary = m["rear"]
	var moment := float(m["mass"]) * G * absf(lat_g) * float(m["h"])
	var k_f := _roll_stiffness(f)
	var k_r := _roll_stiffness(r)
	var phi := moment / maxf(k_f + k_r, 1e-6)
	var df := 2.0 * k_f * phi / float(f["track"])
	var dr := 2.0 * k_r * phi / float(r["track"])
	var cap_f := 2.0 * float(f["load"])
	var cap_r := 2.0 * float(r["load"])
	if df > cap_f and dr > cap_r or (df > cap_f and k_r <= 0.0) or (dr > cap_r and k_f <= 0.0):
		return {"phi": INF, "front": cap_f, "rear": cap_r}
	if df > cap_f:
		df = cap_f
		phi = (moment - cap_f * float(f["track"]) / 2.0) / k_r
		dr = 2.0 * k_r * phi / float(r["track"])
	elif dr > cap_r:
		dr = cap_r
		phi = (moment - cap_r * float(r["track"]) / 2.0) / k_f
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
## difference `Wf / Cf - Wr / Cr` on their stiffness at the loads that g leaves them. The secant, as
## the step pass reads it (exact while every wheel is under the curve's peak). At a finite `speed`
## (m/s) it adds the angular damping's share (`yaw_damping_gradient`, NAN without a yaw inertia);
## INF leaves it out.
static func understeer_gradient(m: Dictionary, lat_g: float, speed := INF) -> float:
	if m.is_empty():
		return NAN
	var k := 0.0
	for key: String in ["front", "rear"]:
		var axle: Dictionary = m[key]
		k += (1.0 if key == "front" else -1.0) * 2.0 * float(axle["load"]) \
				/ _axle_stiffness(m, key, lat_g)
	var damped := yaw_damping_gradient(m, lat_g, speed) if is_finite(speed) else 0.0
	return rad_to_deg(k) + damped


## An axle's cornering stiffness (N per unit slip) at the loads `lat_g` leaves it.
static func _axle_stiffness(m: Dictionary, key: String, lat_g: float) -> float:
	var axle: Dictionary = m[key]
	var loads := pair_loads(float(axle["load"]), _transfer(m, key, lat_g))
	var share: float = axle["share"]
	return maxf(wheel_stiffness(m, float(axle["mu"]), loads.x, share)
			+ wheel_stiffness(m, float(axle["mu"]), loads.y, share), 1e-6)


## The angular damping's understeer (deg/g) at `speed` (m/s): the steady yaw rate `lat_g * g / v`
## costs the moment `I * c * r`, a side force `I c r / L` the front adds and the rear sheds, each axle
## slipping that much more or less. It falls as 1 / v. NAN without a yaw inertia.
static func yaw_damping_gradient(m: Dictionary, lat_g: float, speed: float) -> float:
	if m.is_empty() or lat_g <= 0.0 or speed <= 0.0:
		return NAN
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
## whose figure is lower saturates first.
static func axle_capacity_g(m: Dictionary, lat_g: float) -> Vector2:
	if m.is_empty():
		return Vector2(NAN, NAN)
	var out := Vector2.ZERO
	for i in 2:
		var key := "front" if i == 0 else "rear"
		var axle: Dictionary = m[key]
		var n_load: float = axle["load"]
		out[i] = pair_grip(float(axle["mu"]), n_load, _transfer(m, key, lat_g), float(m["ref"]),
				float(m["sensitivity"]), float(axle["share"])) / (2.0 * n_load)
	return out


## The steady-state limit: `g` where the first axle saturates, settled by a few passes (the transfer
## depends on the g it limits), each axle's capacity there (`front`, `rear`), and `margin`, the rear's
## over the front's less 1 (+ = the front washes out first, understeer at the limit).
static func limit(m: Dictionary) -> Dictionary:
	if m.is_empty():
		return {}
	var g := 0.0
	var caps := Vector2.ZERO
	for _pass in 8:
		caps = axle_capacity_g(m, g)
		g = minf(caps.x, caps.y)
	return {"g": g, "front": caps.x, "rear": caps.y, "margin": caps.y / caps.x - 1.0}
