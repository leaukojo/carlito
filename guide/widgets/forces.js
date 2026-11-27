// Forces on a vehicle: a top and a side view of one of the three bodies, with each force drawn as
// an arrow on one shared scale. AN ILLUSTRATION, NOT THE PHYSICS: a simplified, steady-instant
// copy of the game's formulas (forces.md lists what it leaves out). Plain JS and SVG, no
// libraries. Every game figure is cited where it is set below, as file and code name; the
// physics-wide ones:
//   G 9.8          physics/3d/default_gravity (Godot's default)
//   RHO 1.225      vehicle_math.gd AIR_DENSITY
//   grip curve     GroundDriveSpec.grip_curve: peak 1 at 0.12 slip, 0.8 when locked or spinning
//   GROUNDS        surface.gd REF_GRIP and DRAG (the all-season tyre's, for all three bodies)
// Each view has one linear scale (newtons per pixel) with its own bar.
// Body frame: x forward, y up (side view) or y to the left (top view). Both views face right, so
// the side view shows the right-hand side; the left wheels' arrows are drawn faint, offset.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var G = 9.8;
  var RHO = 1.225;
  var VIEW_W = 420, VIEW_H = 280;
  var MAX_ARROW = 85;      // px: the longest ticked force
  var TINY = 2;            // px: shorter than this draws as a dot
  var GROUNDS = {
    dry: { name: 'Dry asphalt', grip: 1, drag: 0 },
    wet: { name: 'Wet asphalt', grip: 0.75, drag: 0 },
    snow: { name: 'Snow', grip: 0.34, drag: 0.02 },
    ice: { name: 'Ice', grip: 0.12, drag: 0 }
  };

  // ---- helpers ------------------------------------------------------------------------------
  function clamp(x, a, b) { return Math.min(Math.max(x, a), b); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function sgn(x) { return x > 0 ? 1 : x < 0 ? -1 : 0; }
  // VehicleSpec.sample_curve: linear between points, flat past the ends.
  function sampleCurve(pts, x) {
    if (x <= pts[0][0]) return pts[0][1];
    for (var i = 1; i < pts.length; i++) {
      if (x <= pts[i][0]) {
        var t = (x - pts[i - 1][0]) / (pts[i][0] - pts[i - 1][0]);
        return lerp(pts[i - 1][1], pts[i][1], t);
      }
    }
    return pts[pts.length - 1][1];
  }
  function fmtN(n) {
    var a = Math.abs(n);
    if (a >= 1e6) return (n / 1e6).toFixed(2) + ' MN';
    if (a >= 1e4) return Math.round(n / 1e3) + ' kN';
    if (a >= 1e3) return (n / 1e3).toFixed(1) + ' kN';
    return Math.round(n) + ' N';
  }
  function niceFloor(x) {
    var p = Math.pow(10, Math.floor(Math.log10(x)));
    var f = x / p;
    return (f >= 5 ? 5 : f >= 2 ? 2 : 1) * p;
  }
  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function svgText(parent, x, y, str, extra) {
    var t = el('text', Object.assign({ x: x, y: y, 'font-size': 12, fill: 'var(--fig-muted)' }, extra || {}), parent);
    t.textContent = str;
    return t;
  }
  // Wind as the air's own velocity in the body frame (x forward, y left).
  function windVector(s) {
    var w = s.wind;
    if (s.windFrom === 'ahead') return { x: -w, y: 0 };
    if (s.windFrom === 'behind') return { x: w, y: 0 };
    if (s.windFrom === 'left') return { x: 0, y: -w };
    return { x: 0, y: w };
  }

  // ---- the forces ---------------------------------------------------------------------------
  // colour, dash, plain one-line explanation, and the guide page that says more.
  var FORCES = {
    weight: { name: 'Weight (gravity)', colour: 'var(--fig-ink)', page: 'weight-transfer', pageTitle: 'Weight transfer and rollover',
      text: 'Gravity pulls the vehicle down. On a slope, part of it pulls downhill.' },
    normal: { name: 'Ground push on each wheel', colour: 'var(--fig-blue)', page: 'weight-transfer', pageTitle: 'Weight transfer and rollover',
      text: 'The ground pushes up on each tyre and holds the vehicle up.' },
    drive: { name: 'Drive force (tyres)', colour: 'var(--fig-green)', page: 'slip', pageTitle: 'Slip and the grip curve',
      text: 'The tyres push back on the ground, so the ground pushes the vehicle forward.' },
    brake: { name: 'Braking force (tyres)', colour: 'var(--fig-red)', page: 'brakes', pageTitle: 'Brakes',
      text: 'The brakes slow the wheels, and the tyres hold the vehicle back.' },
    lateral: { name: 'Side force (tyres)', colour: 'var(--fig-orange)', page: 'slip', pageTitle: 'Slip and the grip curve',
      text: 'To turn, the tyres push sideways, toward the inside of the turn.' },
    rolling: { name: 'Rolling resistance', colour: 'var(--fx-purple, #7b3fb0)', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'A rolling tyre flexes, which holds the vehicle back a little.' },
    drag: { name: 'Air drag', colour: 'var(--fig-muted)', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'The air holds the vehicle back, more and more the faster it goes.' },
    side: { name: 'Crosswind push', colour: 'var(--fig-muted)', dash: '5 3', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'Wind blowing across the vehicle pushes it sideways.' },
    net: { name: 'Net force (what is left)', colour: 'var(--fig-ink)', dash: '2 3', page: null,
      text: 'All the forces added together. What is left speeds the vehicle up, slows it or turns it.' }
  };

  // ---- wheeled bodies -----------------------------------------------------------------------
  // From a spec: wheel_positions (Godot z is backwards, so x = -z), the COM over the ground
  // (center_of_mass.y + GroundDriveSpec.rest_ride_height: radius + rest_length - anchor y), the
  // brakes per wheel (GroundDriveSpec.axle_brake_torque), and the lock taper
  // (WheelDrive.steer_lock_deg).
  function wheeled(o) {
    var nFront = 2, nRear = 2, total = o.brakeTorque * 4;
    var bf = o.brakeBias < 0 ? o.brakeTorque : total * o.brakeBias / nFront;
    var br = o.brakeBias < 0 ? o.brakeTorque : total * (1 - o.brakeBias) / nRear;
    o.xf = -o.zFront;
    o.xr = -o.zRear;
    o.wheels = [
      { name: 'front right', x: o.xf, y: -o.trackF / 2, r: o.rF, hw: o.hwF, front: true, driven: o.drivenFront, brakeT: bf },
      { name: 'front left', x: o.xf, y: o.trackF / 2, r: o.rF, hw: o.hwF, front: true, driven: o.drivenFront, brakeT: bf },
      { name: 'rear right', x: o.xr, y: -o.trackR / 2, r: o.rR, hw: o.hwR, front: false, driven: o.drivenRear, brakeT: br },
      { name: 'rear left', x: o.xr, y: o.trackR / 2, r: o.rR, hw: o.hwR, front: false, driven: o.drivenRear, brakeT: br }
    ];
    o.driveR = o.drivenRear ? o.rR : o.rF;   // GroundDriveSpec.drive_radius
    var peak = 0;
    o.peakRpm = o.torque[0][0];
    o.torque.forEach(function (p) { if (p[1] > peak) { peak = p[1]; o.peakRpm = p[0]; } });
    o.kind = 'wheeled';
    return o;
  }

  var VEHICLES = {
    car: wheeled({
      // sedan_spec.tres: mass 1150, center_of_mass (0, 0.48, -0.188), wheel_positions z -0.822 and
      // 0.762, x +-0.63, wheel_radius 0.36, rest_length 0.28, anchor y 0.5115 (ride 0.129),
      // tyre_half_width 0.21 (default), driven_front, mu_long 1.05 (GroundDriveSpec default),
      // mu_lat 0.97, rolling_resistance 0.012, drag_area 0.65, side_area 4.16, aero_centre
      // (0, 0.87, -0.43), brake_torque 1450, brake_bias_front 0.873, abs_equipped,
      // tcs_equipped, torque_curve, idle_rpm 900 and redline_rpm 6800 (VehicleSpec defaults),
      // gear_ratios, final_drive 3.9 and efficiency 0.9 (VehicleSpec defaults), max_steer_deg 38,
      // min_steer_frac 0.26, steer_falloff_speed 42, no speed_limit_kmh.
      label: 'Car (the sedan)', mass: 1150, comX: 0.188, comH: 0.609,
      zFront: -0.822, zRear: 0.762, trackF: 1.26, trackR: 1.26, rF: 0.36, rR: 0.36, hwF: 0.21, hwR: 0.21,
      drivenFront: true, drivenRear: false, muLong: 1.05, muLat: 0.97, rearLatGrip: 1,
      crr: 0.012, cda: 0.65, cya: 4.16, aeroX: 0.43, aeroH: 0.999,
      brakeTorque: 1450, brakeBias: 0.873, abs: true, tcs: true,
      torque: [[900, 98], [2000, 154], [3200, 184], [4800, 185], [6000, 185], [6600, 170], [6800, 61]],
      redline: 6800, gears: [4.5, 2.903, 1.975, 1.431, 1.109, 0.925], finalDrive: 3.9, eff: 0.9,
      maxSteer: 38, minSteerFrac: 0.26, falloff: 42, limitKmh: 0,
      loadMax: 0, loadX: 0,
      body: { front: 1.05, rear: 1.0, width: 1.75, height: 1.45, kind: 'car' },
      sliders: { speed: [0, 180, 60], slope: 30, load: 'The cars carry no load in the simulator.' }
    }),
    truck: wheeled({
      // garbage-truck_spec.tres: mass 8000, center_of_mass (0, 0.85, -0.262), wheel_positions z
      // -1.302 and 0.642, x +-0.66, wheel_radius 0.36, rest_length 0.32, anchor y 0.631 (ride
      // 0.049), tyre_half_width 0.21, rear drive (GroundDriveSpec default), mu_long 0.8, mu_lat
      // 0.75, rolling_resistance 0.007, drag_area 1.95, side_area 7.21, aero_centre
      // (0, 1.03, -0.82), brake_torque 15500, brake_bias_front 0.78, abs_equipped, tcs_equipped,
      // torque_curve, redline_rpm 2900, gear_ratios, final_drive 4.01, max_steer_deg 22,
      // min_steer_frac 0.22, steer_falloff_speed 26, speed_limit_kmh 85.
      // Load: refuse_body.gd HOPPER_PAYLOAD_KG 5000 at a full hopper, added as mass only
      // (truck.gd set_live_mass(spec.mass + payload)), so at the chassis COM.
      label: 'Truck (the garbage truck)', mass: 8000, comX: 0.262, comH: 0.899,
      zFront: -1.302, zRear: 0.642, trackF: 1.32, trackR: 1.32, rF: 0.36, rR: 0.36, hwF: 0.21, hwR: 0.21,
      drivenFront: false, drivenRear: true, muLong: 0.8, muLat: 0.75, rearLatGrip: 1,
      crr: 0.007, cda: 1.95, cya: 7.21, aeroX: 0.82, aeroH: 1.079,
      brakeTorque: 15500, brakeBias: 0.78, abs: true, tcs: true,
      torque: [[700, 509], [1200, 826], [1800, 1017], [2600, 890], [2900, 0]],
      redline: 2900, gears: [3.49, 1.86, 1.41, 1, 0.75, 0.65], finalDrive: 4.01, eff: 0.9,
      maxSteer: 22, minSteerFrac: 0.22, falloff: 26, limitKmh: 85,
      loadMax: 5000, loadX: 0.262, loadLabel: 'Load (refuse in the hopper)',
      body: { front: 1.25, rear: 2.3, width: 2.3, height: 3.1, kind: 'truck' },
      sliders: { speed: [0, 90, 40], slope: 30 }
    }),
    tractor: wheeled({
      // tractor-kenney_spec.tres: mass 7000, center_of_mass (0, 1.013, 0.372), wheel_positions z
      // -1.227 (x +-0.782) and 1.353 (x +-0.896), wheel_radius 0.537, wheel_radius_rear 0.805,
      // rest_length 0.12 (ride 0.052), tyre_half_width 0.368 and 0.494, rear drive, mu_long 1.0,
      // mu_lat 0.95 (default), rear_lat_grip 1.077, rolling_resistance 0.02, drag_area 5.47,
      // side_area 10.77, aero_centre (0, 1.77, -0.58), brake_torque 19231, brake_bias_front 0 (all
      // rear), no ABS or TCS, torque_curve, redline_rpm 2350, 16 gear_ratios, final_drive 12.299,
      // max_steer_deg 38, min_steer_frac 0.55, steer_falloff_speed 11, speed_limit_kmh 40.
      // Load: a raised implement, up to harrow.gd MASS_KG 1550 (the heaviest), carried whole when
      // raised (ImplementBase.carried01), its centre placed for all of them at the harrow's: the
      // hitch at z 0.81 (tractor-kenney.tscn) + the raised ball 0.92 + 0.827 cos 25.8 deg
      // (hitch_linkage.gd lower_pivot, lower_len, lower_angle_hi_deg) + MASS_CENTRE z 0.59.
      label: 'Tractor', mass: 7000, comX: -0.372, comH: 1.065,
      zFront: -1.227, zRear: 1.353, trackF: 1.564, trackR: 1.792, rF: 0.537, rR: 0.805, hwF: 0.368, hwR: 0.494,
      drivenFront: false, drivenRear: true, muLong: 1.0, muLat: 0.95, rearLatGrip: 1.077,
      crr: 0.02, cda: 5.47, cya: 10.77, aeroX: 0.58, aeroH: 1.822,
      brakeTorque: 19231, brakeBias: 0, abs: false, tcs: false,
      torque: [[800, 550], [1200, 680], [1600, 700], [2000, 640], [2200, 560], [2350, 0]],
      redline: 2350, gears: [7, 6.275, 5.625, 5.042, 4.52, 4.051, 3.632, 3.255, 2.918, 2.616, 2.345, 2.102, 1.884, 1.689, 1.514, 1.357],
      finalDrive: 12.299, eff: 0.9,
      maxSteer: 38, minSteerFrac: 0.55, falloff: 11, limitKmh: 40,
      loadMax: 1550, loadX: -3.06, loadLabel: 'Load (implement on the hitch)',
      body: { front: 0.75, rear: 0.5, width: 2.0, height: 2.7, kind: 'tractor' },
      sliders: { speed: [0, 45, 12], slope: 30 }
    })
  };

  // ---- models -------------------------------------------------------------------------------
  // Each returns { arrows: [{ id, view: 'top'|'side', x, y, fx, fy, where, far }],
  // net: { x, y }, mass, notes, sideRot }. Positions in metres, forces in newtons, body frame.

  // Best-gear wheel force at speed v: torque_curve x gear x final_drive x efficiency / radius
  // (Drivetrain.wheel_torque). Below the strongest rpm the page lets the clutch or converter slip
  // so the engine sits there; it leaves out a converter's torque multiplication. Returns the force
  // and what it assumes: the gear (1-based, 0 = none), the engine's rpm, and whether the clutch slips.
  function driveForceMax(V, v) {
    var best = { force: 0, gear: 0, rpm: 0, limited: false };
    if (V.limitKmh > 0 && v * 3.6 >= V.limitKmh) { best.limited = true; return best; }  // VehicleSpec.speed_limit_kmh
    V.gears.forEach(function (gr, i) {
      var total = gr * V.finalDrive;
      var rpm = v / V.driveR * total * 60 / (2 * Math.PI);
      if (rpm > V.redline) return;
      var engine = Math.max(rpm, V.peakRpm);
      var f = sampleCurve(V.torque, engine) * total * V.eff / V.driveR;
      if (f > best.force) best = { force: f, gear: i + 1, rpm: engine, limited: false };
    });
    return best;
  }

  // The drive's gear and engine speed (the strongest gear at this speed), or why there is no drive,
  // tacked onto the readout's first line.
  function driveNote(V, d) {
    if (d.limited) return 'The speed limiter cuts the drive at ' + V.limitKmh + ' km/h.';
    if (!d.gear) return 'Every gear is past the redline: no drive.';
    return 'Gear: ' + d.gear + ', engine: ' + Math.round(d.rpm / 100) * 100 + ' rpm.';
  }

  // At a standstill a brake holds against the other forces up to its strength; moving, it pushes
  // against the motion at full strength (a wheel's held_force_range).
  function brakeShare(capacity, others, moving, dir) {
    if (moving) return -dir * capacity;
    return -clamp(others, -capacity, capacity);
  }

  function modelWheeled(V, s) {
    var m = V.mass + s.load;
    var xc = (V.mass * V.comX + s.load * V.loadX) / m;  // VehicleMath.carried_com
    var h = V.comH;
    var th = Math.atan(s.slope / 100);
    var W = m * G, Wn = W * Math.cos(th), Wx = -W * Math.sin(th);
    var v = s.speed / 3.6;
    var moving = v > 0.05;
    var L = V.xf - V.xr, a = V.xf - xc;
    var notes = [];

    // VehicleMath.air_force: air = velocity - wind; 0.5 rho |air| CdA |u| along, CyA |w| across.
    var wind = windVector(s);
    var ux = v - wind.x, uy = -wind.y;
    var qv = 0.5 * RHO * Math.hypot(ux, uy);
    var drag = -sgn(ux) * qv * V.cda * Math.abs(ux);
    var side = -sgn(uy) * qv * V.cya * Math.abs(uy);

    // WheelDrive.steer_lock_deg and the kinematic (bicycle) turn: radius L / tan(angle).
    var lock = V.maxSteer * lerp(1, V.minSteerFrac, clamp(v / V.falloff, 0, 1));
    var delta = s.steer * lock * Math.PI / 180;          // + = right
    var R = Math.abs(delta) > 1e-4 ? L / Math.tan(Math.abs(delta)) : Infinity;
    var ay = isFinite(R) ? -sgn(delta) * v * v / R : 0;   // y is to the left
    var tyreSide = m * ay - side;                         // what the tyres must add across
    var axleSide = { front: tyreSide * (V.xr - xc) / -L, rear: tyreSide * a / L };
    // WheelDrive.ackermann_angle: full Ackermann, the inner wheel turns more.
    function wheelAngle(w) {
      if (!w.front || !isFinite(R)) return 0;
      var t = w.y * sgn(delta);  // + on the outside of the turn
      return -sgn(delta) * Math.atan(L / (R + t));
    }

    var driveMax = driveForceMax(V, v);
    var drive = s.throttle * driveMax.force;
    var nDriven = V.wheels.filter(function (w) { return w.driven; }).length;
    var capTotal = 0;
    V.wheels.forEach(function (w) { capTotal += s.brake * w.brakeT / w.r; });
    // The brakes' share of the whole: moving, full strength; still, only what holds.
    var brakeTotal = brakeShare(capTotal, drive + Wx + drag, moving, 1);

    // Load moves with the forces the tyres actually make, which grip caps, and grip depends on
    // load: the solve repeats a few times, starting from what the turn asks for.
    var accel = 0, res = null, latActual = { front: axleSide.front, rear: axleSide.rear };
    for (var iter = 0; iter < 6; iter++) res = solveWheels(accel);
    function solveWheels(ax) {
      // Moments about the front contact patch: weight, the slope pull and the inertia act at the
      // COM height, the drag at the aero centre's.
      var NrRaw = (a * Wn + h * (-Wx + m * ax) - V.aeroH * drag) / L;
      var Nr = clamp(NrRaw, 0, Wn);
      var axleLift = NrRaw > Wn ? 'front' : NrRaw < 0 ? 'rear' : null;  // a whole axle unloaded in pitch
      var axleN = { front: Wn - Nr, rear: Nr };
      var out = [], sumX = 0, sumY = 0, lifted = false, slide = { front: false, rear: false };
      var slideBrake = false, slideDrive = false;
      var reach = { front: 0, rear: 0 }, latSum = { front: 0, rear: 0 };
      // Each wheel's load first: the standstill hold below shares the brakes by grip.
      var loads = V.wheels.map(function (w) {
        var key = w.front ? 'front' : 'rear';
        var track = Math.abs(w.y) * 2;
        var Fy = latActual[key];
        var N = axleN[key] / 2 - sgn(w.y) * Fy * h / track;
        var other = axleN[key] / 2 + sgn(w.y) * Fy * h / track;
        if (N < 0) { N = 0; lifted = true; }
        if (other < 0) N = axleN[key];
        return N;
      });
      // Moving, the brakes share their full strength by capacity. Still, a wheel holds up to the
      // lesser of its brake capacity and its grip, and what a wheel cannot take goes to the wheels
      // with spare capacity; only when every wheel is at its limit does the vehicle move.
      var brakeF = [], brakeSat = [];
      if (moving) {
        V.wheels.forEach(function (w) { brakeF.push(capTotal > 0 ? brakeTotal * (s.brake * w.brakeT / w.r) / capTotal : 0); });
      } else {
        var got = [], want = Math.abs(brakeTotal);
        var capW = V.wheels.map(function (w) { return s.brake * w.brakeT / w.r; });
        var room = function (i) { return Math.min(capW[i], V.muLong * loads[i]) - got[i]; };
        V.wheels.forEach(function () { got.push(0); });
        for (var pass = 0; pass < 4 && want > 1e-6; pass++) {
          var open = 0, taken = 0;
          capW.forEach(function (c, i) { if (room(i) > 1e-6) open += c; });
          if (!(open > 0)) break;
          var ask = want;
          capW.forEach(function (c, i) {
            if (room(i) <= 1e-6) return;
            var add = Math.min(ask * c / open, room(i));
            got[i] += add;
            taken += add;
          });
          want -= taken;
        }
        got.forEach(function (g, i) {
          brakeF.push(sgn(brakeTotal) * g);
          brakeSat.push(want > 1 && capW[i] > 0 && room(i) <= 1e-6);
        });
      }
      V.wheels.forEach(function (w, wi) {
        var key = w.front ? 'front' : 'rear';
        var N = loads[wi];
        var share = axleN[key] > 0 ? N / axleN[key] : 0;
        // A wheel in the air makes no force at all; its share of the drive is lost, as with an open
        // differential on a lifted wheel.
        var grounded = N > 0;
        var fDrive = w.driven && grounded ? drive / nDriven : 0;
        var fBrake = grounded ? brakeF[wi] : 0;
        var fRoll = moving ? -V.crr * N : 0;  // RayWheel.tick's rolling moment on asphalt
        var muL = V.muLong * N, muY = V.muLat * (w.front ? 1 : V.rearLatGrip) * N;
        var fx = fDrive + fBrake;
        // Forces along and across the WHEEL, which a steered wheel turns by `ang`. The body needs
        // its share of the axle's sideways force; a steered wheel's push along itself already gives
        // part of it (at a standstill, all of it), so the side force makes up the rest.
        var ang = wheelAngle(w), ca = Math.cos(ang), sa = Math.sin(ang);
        var fLat = grounded ? (axleSide[key] * share - (fx + fRoll) * sa) / ca : 0;
        // RayWheel.friction_ellipse: the along and across demands share one grip budget.
        var rch = Math.hypot(muL > 0 ? fx / muL : (fx ? 9 : 0), muY > 0 ? fLat / muY : (fLat ? 9 : 0));
        reach[key] = Math.max(reach[key], rch);
        var k = 1, sliding = false;
        if (rch > 1 + 1e-6) {
          sliding = true;
          slide[key] = true;
          if (Math.abs(fBrake) > Math.abs(fDrive)) slideBrake = true; else slideDrive = true;
          var longDominant = Math.abs(fx) / Math.max(muL, 1e-9) >= Math.abs(fLat) / Math.max(muY, 1e-9);
          var aid = Math.abs(fBrake) > Math.abs(fDrive) ? V.abs : V.tcs;
          // Past the grip peak the curve falls to 0.8; ABS or TCS hold the wheel at the peak.
          k = (longDominant && !aid ? 0.8 : 1) / rch;
        } else if (brakeSat[wi]) {
          // Still, and every wheel at its limit: the brakes cannot hold the vehicle.
          sliding = true;
          slide[key] = true;
          slideBrake = true;
        }
        out.push({ w: w, N: N, drive: fDrive * k, brake: fBrake * k, lat: fLat * k, roll: fRoll,
          angle: ang, sliding: sliding, use: grounded ? Math.min(rch, 1) : 0, lifted: !grounded });
        // Back to the body's axes, as the arrows are drawn.
        var along = fx * k + fRoll, across = fLat * k;
        sumX += along * ca - across * sa;
        sumY += along * sa + across * ca;
        latSum[key] += along * sa + across * ca;
      });
      accel = (sumX + drag + Wx) / m;
      latActual = latSum;
      return { wheels: out, sumX: sumX, sumY: sumY, lifted: lifted, axleLift: axleLift, slide: slide, reach: reach,
        slideBrake: slideBrake, slideDrive: slideDrive };
    }

    var arrows = [];
    res.wheels.forEach(function (r) {
      var w = r.w, far = w.y > 0, c = Math.cos(r.angle), sn = Math.sin(r.angle);
      var where = w.name + ' wheel';
      arrows.push({ id: 'normal', view: 'side', x: w.x, y: 0, fx: 0, fy: r.N, where: where, far: far });
      // The side view shows each force's part along the car: a steered wheel's push is turned, and
      // its side force then pushes partly backwards or forwards too.
      var part = sn ? ' (its part along the car)' : '';
      [['drive', r.drive], ['brake', r.brake], ['rolling', r.roll]].forEach(function (p) {
        if (!p[1]) return;
        arrows.push({ id: p[0], view: 'side', x: w.x, y: 0, fx: p[1] * c, fy: 0, where: where + part, far: far });
        arrows.push({ id: p[0], view: 'top', x: w.x, y: w.y, fx: p[1] * c, fy: p[1] * sn, where: where, sliding: r.sliding });
      });
      if (r.lat) {
        arrows.push({ id: 'lateral', view: 'top', x: w.x, y: w.y, fx: -r.lat * sn, fy: r.lat * c, where: where, sliding: r.sliding });
        if (sn) arrows.push({ id: 'lateral', view: 'side', x: w.x, y: 0, fx: -r.lat * sn, fy: 0, where: where + part, far: far });
      }
    });
    arrows.push({ id: 'weight', view: 'side', x: xc, y: h, fx: Wx, fy: -Wn, where: 'the centre of mass' });
    // On a slope the weight pulls downhill too: the view from above shows that part.
    if (Wx) arrows.push({ id: 'weight', view: 'top', x: xc, y: 0, fx: Wx, fy: 0, where: 'the centre of mass (the downhill part of the weight)' });
    if (drag) {
      arrows.push({ id: 'drag', view: 'side', x: V.aeroX, y: V.aeroH, fx: drag, fy: 0, where: 'the centre of pressure' });
      arrows.push({ id: 'drag', view: 'top', x: V.aeroX, y: 0, fx: drag, fy: 0, where: 'the centre of pressure' });
    }
    if (side) arrows.push({ id: 'side', view: 'top', x: V.aeroX, y: 0, fx: 0, fy: side, where: 'the centre of pressure' });
    var netX = res.sumX + drag + Wx, netY = res.sumY + side;
    arrows.push({ id: 'net', view: 'side', x: xc, y: h, fx: netX, fy: 0, where: 'the centre of mass' });
    arrows.push({ id: 'net', view: 'top', x: xc, y: 0, fx: netX, fy: netY, where: 'the centre of mass' });

    if (res.axleLift) notes.push('The ' + res.axleLift + ' wheels have lifted off the ground: the vehicle is close to tipping over ' +
      (res.axleLift === 'front' ? 'backwards' : 'forwards') + '.');
    else if (res.lifted) notes.push('A wheel has lifted off the ground: the vehicle is close to rolling over.');
    var turning = Math.abs(ay) > 0.1;
    if (turning && (res.slide.front || res.slide.rear)) {
      notes.push(res.reach.front >= res.reach.rear
        ? 'The front tyres reach their grip first: the vehicle runs wide of the turn (understeer).'
        : 'The rear tyres reach their grip first: the back steps out (oversteer).');
    }
    if ((res.slide.front || res.slide.rear) && !turning) {
      // Brake or drive, by what the wheels that slid were asked for.
      var braking = res.slideBrake;
      notes.push(braking && !moving ? 'A braked tyre is past its grip: the brakes cannot hold the vehicle here.'
        : braking ? (V.abs ? 'A tyre is at its grip limit: ABS holds it at the peak of the grip curve.'
          : 'A tyre is past its grip limit: without ABS it locks, and grip falls to 0.8 of the peak.')
        : (V.tcs ? 'A driven tyre is at its grip limit: traction control holds it at the peak.'
          : 'A driven tyre is past its grip limit: it spins, and grip falls to 0.8 of the peak.'));
    }
    var held = Math.abs(res.sumY) / m;  // the sideways acceleration the tyres alone give
    var turn = isFinite(R) && moving ? { radius: R, ay: Math.abs(ay), held: held, heldRadius: held > 1e-6 ? v * v / held : Infinity, pull: Math.abs(res.sumY) } : null;
    return { arrows: arrows, net: { x: netX, y: netY }, mass: m, notes: notes, sideRot: th, turn: turn,
      driveNote: s.throttle > 0 ? driveNote(V, driveMax) : '',
      steerAngles: res.wheels.map(function (r) { return r.angle; }),
      grip: res.wheels.map(function (r) { return { use: r.use, lifted: r.lifted }; }) };
  }

  // The ground scales the tyres' grip and adds its drag; s.aids false switches ABS and TCS off.
  function compute(key, s) {
    var V = VEHICLES[key], g = GROUNDS[s.ground || 'dry'], aids = s.aids !== false;
    return modelWheeled(Object.assign({}, V, { muLong: V.muLong * g.grip, muLat: V.muLat * g.grip,
      crr: V.crr + g.drag, abs: V.abs && aids, tcs: V.tcs && aids }), s);
  }

  // ---- drawing the vehicles -----------------------------------------------------------------
  // Outlines are schematic: true wheelbase, track and wheel sizes, approximate bodies.
  function rect(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]; }
  function shapes(key, V, r, view) {
    var out = [];
    if (V.kind === 'wheeled') {
      var b = V.body, xF = V.xf + b.front, xR = V.xr - b.rear;
      if (view === 'top') {
        out.push({ poly: rect(xR, -b.width / 2, xF, b.width / 2), cls: 'body' });
        if (b.kind === 'car') out.push({ poly: rect(V.xr + 0.1, -b.width / 2 + 0.15, V.xf - 0.35, b.width / 2 - 0.15), cls: 'glass' });
        if (b.kind === 'truck') out.push({ poly: rect(V.xf - 0.5, -b.width / 2, xF, b.width / 2), cls: 'glass' });
        if (b.kind === 'tractor') out.push({ poly: rect(V.xr - 0.3, -0.7, V.xr + 0.9, 0.7), cls: 'glass' });
        V.wheels.forEach(function (w, i) {
          out.push({ wheel: true, x: w.x, y: w.y, len: w.r * 2, wid: w.hw * 2, angle: r.steerAngles ? r.steerAngles[i] : 0,
            grip: r.grip ? r.grip[i] : null });
        });
      } else {
        var ground = Math.max(V.rF, V.rR) * 0.55;
        if (b.kind === 'car') {
          out.push({ poly: [[xR, 0.3], [xF, 0.3], [xF, 0.85], [V.xf - 0.4, 0.95], [V.xf - 1.0, b.height], [V.xr + 0.2, b.height], [xR + 0.15, 0.95], [xR, 0.9]], cls: 'body' });
        } else if (b.kind === 'truck') {
          out.push({ poly: rect(xR, 0.45, V.xf - 0.55, b.height), cls: 'body' });
          out.push({ poly: [[V.xf - 0.5, 0.45], [xF, 0.45], [xF, 2.4], [V.xf - 0.5, 2.6]], cls: 'body' });
        } else {
          out.push({ poly: [[xR + 0.3, ground], [xF, ground], [xF, 1.4], [V.xr + 0.9, 1.45], [V.xr + 0.9, b.height], [V.xr - 0.4, b.height], [V.xr - 0.4, 1.6], [xR + 0.3, 1.6]], cls: 'body' });
        }
        V.wheels.forEach(function (w) {
          if (w.y < 0) out.push({ circle: true, x: w.x, y: w.r, r: w.r });
        });
        if (key === 'tractor' && r.mass > V.mass) {
          out.push({ poly: rect(V.loadX - 0.6, 0.3, V.loadX + 0.6, 1.0), cls: 'load' });
          out.push({ line: [[V.xr - 0.2, 0.9], [V.loadX + 0.6, 0.7]] });
        }
      }
    }
    return out;
  }

  // ---- the widget ---------------------------------------------------------------------------
  var ORDER = ['car', 'truck', 'tractor'];
  // widget-kit.js icon for each vehicle drawn.
  var ICON = { car: 'car', truck: 'truck', tractor: 'tractor' };

  // Teaching presets: a vehicle and the sliders it changes (the rest at the vehicle's defaults),
  // with what to look for. The values were picked by running `compute`, so each one shows what
  // its name says; re-check them after a model change. `id` is the address other pages link to,
  // forces.md#example-<id>: renaming one breaks their links.
  var PRESETS = [
    { id: 'pulling-away', veh: 'car', name: 'Pulling away at full throttle', set: { speed: 0, throttle: 1 },
      look: 'The front tyres, which drive, are at their grip limit, so traction control holds them. Speeding up moves weight to the rear, off the wheels that drive.' },
    { id: 'wheelspin', veh: 'car', name: 'Pulling away on snow, without traction control', set: { speed: 0, throttle: 1, ground: 'snow', aids: false },
      look: 'The front tyres spin, so they push with only 0.8 of the little grip that snow gives. Switch traction control back on: the car speeds up harder.' },
    { id: 'high-gear', veh: 'car', name: 'Full throttle at 150 km/h', set: { speed: 150, throttle: 1 },
      look: 'Even the strongest gear available at this speed pushes far less than first gear does. Lower the speed and watch the gear and the drive force change.' },
    { id: 'cruising', veh: 'car', name: 'Cruising at 100 km/h', set: { speed: 100, throttle: 0.13 },
      look: 'The drive just matches air drag and rolling resistance, so the net force is about zero and the speed holds. At this speed air drag is the bigger of the two.' },
    { id: 'coasting', veh: 'car', name: 'Coasting from 150 km/h', set: { speed: 150, throttle: 0 },
      look: 'With no drive, only air drag and rolling resistance are left, and they slow the car. Lower the speed: the drag falls quickly, while the rolling resistance stays the same.' },
    { id: 'headwind', veh: 'car', name: 'Cruising into a headwind', set: { speed: 100, throttle: 0.13, wind: 15, windFrom: 'ahead' },
      look: 'The same throttle as "Cruising at 100 km/h" no longer holds the speed, because drag follows the speed through the air. Set the wind to come from behind to compare.' },
    { id: 'emergency-stop', veh: 'car', name: 'Emergency stop from 100 km/h', set: { speed: 100, throttle: 0, brake: 0.8 },
      look: 'All four tyres are at or near their grip limit; ABS holds the ones at the limit at the peak of the grip curve. Braking moves weight forward: the front ground forces grow, the rear ones shrink.' },
    { id: 'stop-without-abs', veh: 'car', name: 'Emergency stop without ABS', set: { speed: 100, throttle: 0, brake: 0.8, aids: false },
      look: 'The same stop, but the tyres at their limit lock and slide, so they grip less and the car slows less. Switch ABS back on to compare.' },
    { id: 'stop-wet', veh: 'car', name: 'Emergency stop on a wet road', set: { speed: 100, throttle: 0, brake: 0.8, ground: 'wet' },
      look: 'The brakes ask for as much as on a dry road, but the wet tyres reach their limit sooner, so the car slows less.' },
    { id: 'stop-snow', veh: 'car', name: 'Emergency stop on snow', set: { speed: 100, throttle: 0, brake: 0.8, ground: 'snow' },
      look: 'Snow leaves so little grip that the car slows at less than half the rate of a dry stop. Less weight moves to the front, too.' },
    { id: 'full-lock', veh: 'car', name: 'Full lock at walking pace', set: { speed: 3, steer: 1, throttle: 0.05 },
      look: 'In the view from above, the inner front wheel is turned much more than the outer one, so that both roll around the same turn centre.' },
    { id: 'turning', veh: 'car', name: 'Turning, well within grip', set: { speed: 50, steer: 0.05, throttle: 0.12 },
      look: 'The tyres push the car toward the turn centre and use about a third of their grip. The outer wheels carry more weight than the inner ones.' },
    { id: 'understeer', veh: 'car', name: 'Turning at the grip limit (understeer)', set: { speed: 50, steer: 0.15, throttle: 0.12 },
      look: 'The front tyres reach their limit first, so the car starts to run wide. Any more speed or steering and it cannot hold this circle.' },
    { id: 'too-fast', veh: 'car', name: 'Too fast for the turn', set: { speed: 50, steer: 0.25, throttle: 0.12 },
      look: 'The wheels point along a tight circle, but the tyres cannot push hard enough: the readout gives the wider circle the car really follows.' },
    { id: 'braking-in-a-turn', veh: 'car', name: 'Braking in a turn (the rear steps out)', set: { speed: 50, steer: 0.05, throttle: 0, brake: 0.5 },
      look: 'The same easy turn as "Turning, well within grip", now braking. Braking uses the rear tyres\' grip and takes weight off them, so they reach their limit first: oversteer.' },
    { id: 'parked-on-a-hill', veh: 'car', name: 'Parked on a 20 % hill', set: { speed: 0, throttle: 0, slope: 20, brake: 0.3 },
      look: 'The brakes push uphill exactly as hard as the weight pulls downhill, so nothing moves. The downhill part of the weight shows in both views.' },
    { id: 'hill-start', veh: 'car', name: 'Hill start, with both pedals released', set: { speed: 0, throttle: 0, slope: 15 },
      look: 'Nothing opposes the downhill part of the weight, so the car rolls back. This is the moment hill-start assist covers. Add brake or throttle until the car holds.' },
    { id: 'crosswind', veh: 'car', name: 'Crosswind at 100 km/h', set: { speed: 100, throttle: 0.13, wind: 15, windFrom: 'left' },
      look: 'The wind pushes the car sideways at its centre of pressure, and the tyres push back to keep it straight.' },
    { id: 'truck-uphill', veh: 'truck', name: 'Full truck starting uphill', set: { speed: 0, throttle: 1, slope: 15, load: 5000 },
      look: 'About half the drive goes into holding the truck against the slope, so it speeds up at about half the rate it would on the flat (set the slope to 0 to compare).' },
    { id: 'truck-downhill', veh: 'truck', name: 'Full truck braking down a hill', set: { speed: 50, throttle: 0, slope: -10, load: 5000, brake: 0.07 },
      look: 'The brakes must push all the way down just to keep the speed from rising. All that work becomes heat, which is why long descents make brakes fade.' },
    { id: 'truck-governed', veh: 'truck', name: 'At the speed limiter', set: { speed: 85, throttle: 1 },
      look: 'The throttle is fully open, but the limiter cuts the drive. Lower the speed a little and the drive force returns.' },
    { id: 'truck-lifts-wheel', veh: 'truck', name: 'Full truck turning too fast: wheels lift', set: { speed: 40, steer: 0.5, throttle: 0.1, load: 5000 },
      look: 'So much weight moves to the outside that the inner wheels leave the ground. A little more and the truck could roll over.' },
    { id: 'power-oversteer', veh: 'truck', name: 'Full throttle in a wet turn (the rear steps out)', set: { speed: 15, steer: 0.4, throttle: 1, ground: 'wet', aids: false },
      look: 'The rear tyres spend their grip on driving and have too little left for turning, so the back steps out: oversteer.' },
    { id: 'inner-wheel', veh: 'truck', name: 'Power in a tight turn: the inner wheel gives up first', set: { speed: 20, steer: 0.7, throttle: 0.4, ground: 'wet', aids: false },
      look: 'The inner rear wheel carries less weight than the outer one, so it reaches its limit first and the back starts to step out. The diagram has no differential: in a real truck with an open one, the outer wheel would push no harder than the inner one.' },
    { id: 'tractor-implement', veh: 'tractor', name: 'Carrying a raised implement', set: { speed: 12, throttle: 0.1, load: 1550 },
      look: 'The implement hangs behind the rear axle, so it presses the rear wheels down and lifts weight off the front ones. Set the load to 0 to compare.' },
    { id: 'tractor-wheels-spin', veh: 'tractor', name: 'Steep climb, no implement: the wheels spin', set: { speed: 0, throttle: 1, slope: 25 },
      look: 'The rear tyres, which drive, reach their grip limit and spin. Compare with the next preset.' },
    { id: 'tractor-front-lifts', veh: 'tractor', name: 'Steep climb with an implement: the front lifts', set: { speed: 0, throttle: 1, slope: 25, load: 1550 },
      look: 'The implement behind the rear axle adds grip to the driving wheels, but takes all the weight off the front ones: the tractor is close to tipping over backwards.' }
  ];

  function make(root) {
    root.innerHTML = '';
    var uid = 'fx' + Math.random().toString(36).slice(2, 8);
    var shown = {};
    Object.keys(FORCES).forEach(function (id) { shown[id] = true; });
    var current = 'car';

    function addEl(tag, cls, parent, html) {
      var e = document.createElement(tag);
      if (cls) e.className = cls;
      if (html !== undefined) e.innerHTML = html;
      (parent || root).appendChild(e);
      return e;
    }
    var picker = GuideKit.vehiclePicker(root, ORDER.map(function (k) {
      return { id: k, icon: ICON[k], name: VEHICLES[k].label };
    }), 'car', function (k) { setVehicle(k); });
    var pick = addEl('div', 'fx-pick');
    pick.innerHTML = '<label for="' + uid + '-pre">Example</label> <select id="' + uid + '-pre"></select> ';
    var presetSelect = pick.querySelector('#' + uid + '-pre');
    var help = GuideKit.helpButton(pick);
    var presetHelp = help.panel;
    // The example the sliders started from, or null. The ? explains it, and shows only while there
    // is one. Moving a control keeps it as the starting point: the list's blank entry then reads
    // "<example> (changed)", so choosing the example again puts its settings back.
    var example = null;
    var blank = null;
    // The examples of the vehicle on show; an example belongs to one vehicle.
    function fillPresets(k) {
      presetSelect.innerHTML = '';
      blank = document.createElement('option');
      blank.value = ''; blank.textContent = 'choose an example';
      presetSelect.appendChild(blank);
      PRESETS.forEach(function (p, i) {
        if (p.veh !== k) return;
        var o = document.createElement('option');
        o.value = String(i); o.textContent = p.name;
        presetSelect.appendChild(o);
      });
      example = null;
      help.open(false);
      help.button.hidden = true;
    }
    function leaveExample() {
      if (!example || presetSelect.value === '') return;
      blank.textContent = example.name + ' (changed)';
      presetSelect.value = '';
    }

    var views = addEl('div', 'fx-views');
    function makeView(title) {
      var fig = addEl('div', 'fx-view', views);
      addEl('p', 'fx-view-title', fig, title);
      return el('svg', { viewBox: '0 0 ' + VIEW_W + ' ' + VIEW_H, role: 'group', 'aria-label': title }, fig);
    }
    var topSvg = makeView('From above');
    var sideSvg = makeView('From the side');

    var info = addEl('div', 'fx-info');
    info.setAttribute('aria-live', 'polite');
    var readout = addEl('div', 'w-readout');
    readout.setAttribute('aria-live', 'polite');

    var panels = addEl('div', 'fx-panels');
    var controls = addEl('div', 'w-controls', panels);
    var legend = addEl('fieldset', 'fx-legend', panels);

    // sliders: [key, label, min, max, step, default]
    var SL = [
      ['speed', 'Speed', 0, 180, 1, 60],
      ['steer', 'Steering', -1, 1, 0.05, 0],
      ['throttle', 'Throttle', 0, 1, 0.01, 0.3],
      ['brake', 'Brake', 0, 1, 0.01, 0],
      ['slope', 'Slope', -30, 30, 1, 0],
      ['load', 'Load', 0, 100, 1, 0],
      ['wind', 'Wind', 0, 15, 0.5, 0]
    ];
    var inputs = {}, outputs = {}, labels = {};
    SL.forEach(function (d) {
      var id = uid + '-' + d[0];
      var lab = addEl('label', '', controls, d[1]);
      lab.setAttribute('for', id);
      var inp = addEl('input', '', controls);
      inp.type = 'range'; inp.id = id; inp.min = d[2]; inp.max = d[3]; inp.step = d[4]; inp.value = d[5];
      var out = addEl('output', '', controls);
      out.setAttribute('for', id);
      inputs[d[0]] = inp; outputs[d[0]] = out; labels[d[0]] = lab;
      inp.addEventListener('input', update);
    });
    var wl = addEl('label', '', controls, 'Wind from');
    wl.setAttribute('for', uid + '-wdir');
    var windDir = addEl('select', '', controls);
    windDir.id = uid + '-wdir';
    [['ahead', 'ahead'], ['behind', 'behind'], ['left', 'the left'], ['right', 'the right']].forEach(function (o) {
      var op = document.createElement('option');
      op.value = o[0]; op.textContent = o[1];
      windDir.appendChild(op);
    });
    addEl('span', '', controls);
    windDir.addEventListener('change', update);
    var gl = addEl('label', '', controls, 'Ground');
    gl.setAttribute('for', uid + '-ground');
    var ground = addEl('select', '', controls);
    ground.id = uid + '-ground';
    Object.keys(GROUNDS).forEach(function (k) {
      var op = document.createElement('option');
      op.value = k; op.textContent = GROUNDS[k].name;
      ground.appendChild(op);
    });
    addEl('span', '', controls);
    ground.addEventListener('change', update);
    var al = addEl('label', '', controls, 'ABS, traction control');
    al.setAttribute('for', uid + '-aids');
    var aids = addEl('input', 'fx-check', controls);
    aids.type = 'checkbox'; aids.id = uid + '-aids';
    addEl('span', '', controls);
    aids.addEventListener('change', update);

    // Kept short on purpose: the name, one plain sentence, and where to read more.
    function showInfo(id, sliding) {
      var F = FORCES[id];
      var html = '<strong>' + F.name + '.</strong> ' + F.text;
      if (sliding) html += ' <span class="fx-this">This tyre is sliding.</span>';
      if (F.page) html += ' <a href="#' + F.page + '">More: ' + F.pageTitle + '</a>';
      info.innerHTML = html;
    }
    info.innerHTML = 'Click an arrow or a force\'s name to read what it is.';
    // An arrow is a button: a click, Enter or Space explains it.
    function onActivate(g, fn) {
      g.addEventListener('click', fn);
      g.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fn(); }
      });
    }

    function setVehicle(key) {
      current = key;
      picker.set(key);
      fillPresets(key);
      var V = VEHICLES[key], cfg = V.sliders;
      var speedCfg = cfg.speed;
      inputs.speed.max = speedCfg[1];
      inputs.speed.value = speedCfg[2];
      inputs.steer.value = 0;
      inputs.brake.value = 0;
      var slopeMax = typeof cfg.slope === 'number' ? cfg.slope : 30;
      inputs.slope.min = -slopeMax;
      inputs.slope.max = slopeMax;
      inputs.slope.step = slopeMax > 10 ? 1 : 0.5;
      inputs.slope.value = 0;
      inputs.wind.value = 0;
      inputs.throttle.value = 0.3;
      var loadMax = V.loadMax || 0;
      inputs.load.max = loadMax || 100;
      inputs.load.step = loadMax > 100 ? 50 : 0.1;
      inputs.load.value = 0;
      labels.load.textContent = V.loadLabel || 'Load';
      // A control the vehicle has no use for is greyed out; why is its tooltip, not a note.
      ['steer', 'brake', 'slope', 'load', 'wind'].forEach(function (k) {
        var reason = typeof cfg[k] === 'string' ? cfg[k] : null;
        if (k === 'slope' && typeof cfg.slope === 'number') reason = null;
        inputs[k].disabled = !!reason;
        labels[k].classList.toggle('fx-off', !!reason);
        labels[k].title = inputs[k].title = reason || '';
      });
      ground.value = 'dry';
      windDir.value = 'ahead';
      aids.disabled = !(V.abs || V.tcs);
      aids.checked = !aids.disabled;
      al.classList.toggle('fx-off', aids.disabled);
      al.title = aids.title = aids.disabled ? 'This vehicle has neither.' : '';
      windDir.disabled = inputs.wind.disabled;
      wl.classList.toggle('fx-off', windDir.disabled);
      buildLegend();
      update();
    }

    var rows = {};
    function buildLegend() {
      legend.innerHTML = '<legend>Forces to show</legend>';
      rows = {};
      Object.keys(FORCES).forEach(function (id) {
        var F = FORCES[id];
        // The tick shows or hides the force; its name is a button that explains it.
        var row = addEl('div', 'fx-row', legend);
        var cb = addEl('input', '', row);
        cb.type = 'checkbox'; cb.checked = shown[id];
        cb.setAttribute('aria-label', 'Show ' + F.name);
        var sw = el('svg', { viewBox: '0 0 28 10', class: 'fx-swatch', 'aria-hidden': 'true' }, row);
        el('line', { x1: 2, y1: 5, x2: 26, y2: 5, stroke: F.colour, 'stroke-width': 3, 'stroke-dasharray': F.dash || 'none' }, sw);
        var name = addEl('button', 'fx-name', row, F.name);
        name.type = 'button';
        var val = addEl('span', 'fx-val', row);
        cb.addEventListener('change', function () { shown[id] = cb.checked; update(); });
        name.addEventListener('click', function () { showInfo(id); });
        rows[id] = val;
      });
    }

    function readState() {
      return {
        speed: parseFloat(inputs.speed.value), steer: parseFloat(inputs.steer.disabled ? 0 : inputs.steer.value),
        throttle: parseFloat(inputs.throttle.value), brake: inputs.brake.disabled ? 0 : parseFloat(inputs.brake.value),
        slope: inputs.slope.disabled ? 0 : parseFloat(inputs.slope.value), load: inputs.load.disabled ? 0 : parseFloat(inputs.load.value),
        wind: inputs.wind.disabled ? 0 : parseFloat(inputs.wind.value), windFrom: windDir.value,
        ground: ground.value, aids: aids.checked
      };
    }

    function writeOutputs(s) {
      outputs.speed.textContent = Math.round(s.speed) + ' km/h';
      outputs.steer.textContent = inputs.steer.disabled ? '' : s.steer === 0 ? 'straight' : Math.round(Math.abs(s.steer) * 100) + ' % ' + (s.steer > 0 ? 'right' : 'left');
      outputs.throttle.textContent = Math.round(s.throttle * 100) + ' %';
      outputs.brake.textContent = inputs.brake.disabled ? '' : Math.round(s.brake * 100) + ' %';
      outputs.slope.textContent = inputs.slope.disabled ? '' : s.slope === 0 ? 'level' : Math.abs(s.slope) + ' % ' + (s.slope > 0 ? 'uphill' : 'downhill');
      outputs.load.textContent = inputs.load.disabled ? '' : (s.load >= 100 ? Math.round(s.load) : s.load.toFixed(1)) + ' kg';
      outputs.wind.textContent = inputs.wind.disabled ? '' : s.wind + ' m/s';
    }

    function update() {
      var s = readState();
      writeOutputs(s);
      var V = VEHICLES[current];
      var r = compute(current, s);
      // Legend totals: each force summed in the view that shows the whole of it (a force drawn in
      // both views appears once in each).
      var sums = { top: {}, side: {} };
      r.arrows.forEach(function (a) { sums[a.view][a.id] = (sums[a.view][a.id] || 0) + Math.hypot(a.fx, a.fy); });
      var netMag = Math.hypot(r.net.x, r.net.y);
      Object.keys(rows).forEach(function (id) {
        var t = Math.max(sums.top[id] || 0, sums.side[id] || 0);
        var many = r.arrows.filter(function (a) { return a.id === id && a.view === (sums.side[id] >= (sums.top[id] || 0) ? 'side' : 'top'); }).length > 1;
        if (id === 'net') rows[id].textContent = fmtN(netMag);
        else rows[id].textContent = fmtN(t) + (many ? ' in all' : '');
      });

      // One linear scale per view, set by its longest ticked force: the side view is ruled by the
      // weight, so the top view's level forces get their own, each with its bar.
      ['top', 'side'].forEach(function (view) {
        var maxF = 0;
        r.arrows.forEach(function (a) { if (a.view === view && shown[a.id]) maxF = Math.max(maxF, Math.hypot(a.fx, a.fy)); });
        var k = maxF > 0 ? MAX_ARROW / maxF : 0;
        var bar = maxF > 0 ? niceFloor(maxF / 2) : 0;
        drawView(view === 'top' ? topSvg : sideSvg, view, V, r, s, k, bar);
      });
      writeReadout(V, r, s);
    }

    function writeReadout(V, r, s) {
      var along = r.net.x, acc = along / r.mass;
      var lines = [];
      if (Math.abs(acc) < 0.005) lines.push('<strong>The forces along the direction of travel balance:</strong> the speed holds.');
      else if (s.speed < 0.5 && acc < 0) lines.push('<strong>Net force ' + fmtN(Math.abs(along)) + ' backwards:</strong> the vehicle starts to move back at ' + Math.abs(acc).toFixed(2) + ' m/s².');
      else lines.push('<strong>Net force ' + fmtN(Math.abs(along)) + (acc > 0 ? ' forward' : ' backwards') + ':</strong> ' +
        (acc > 0 ? 'speeding up' : 'slowing down') + ' at ' + Math.abs(acc).toFixed(2) + ' m/s² (' + (Math.abs(acc) / G).toFixed(2) + ' g).');
      if (r.driveNote) lines[0] += ' ' + r.driveNote;
      if (r.turn) {
        var t = r.turn;
        if (t.held >= t.ay * 0.97) lines.push('Turning on a circle of about ' + Math.round(t.radius) + ' m radius: the tyres push ' +
          fmtN(t.pull) + ' toward its centre (' + (t.held / G).toFixed(2) + ' g).');
        else lines.push('The front wheels point along a circle of about ' + Math.round(t.radius) + ' m radius, but at this speed that needs ' +
          (t.ay / G).toFixed(1) + ' g. The tyres manage ' + (t.held / G).toFixed(2) + ' g, a circle of about ' + Math.round(t.heldRadius) + ' m.');
      }
      r.notes.forEach(function (n) { lines.push(n); });
      readout.innerHTML = lines.join('<br>');
    }

    // ---- drawing ----
    function drawView(svg, view, V, r, s, kN, bar) {
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      var rot = view === 'side' ? r.sideRot : 0;
      var shp = shapes(current, V, r, view);
      // fit the outline (the arrows get the margins)
      var pts = [];
      shp.forEach(function (p) {
        if (p.poly) p.poly.forEach(function (q) { pts.push(q); });
        if (p.circle) { pts.push([p.x - p.r, p.y - p.r]); pts.push([p.x + p.r, p.y + p.r]); }
        if (p.wheel) { pts.push([p.x - p.len / 2, p.y - p.wid / 2]); pts.push([p.x + p.len / 2, p.y + p.wid / 2]); }
        if (p.line) p.line.forEach(function (q) { pts.push(q); });
      });
      if (view === 'side') pts.push([pts[0][0], 0]);
      var rp = pts.map(function (q) { return rotate(q[0], q[1], rot); });
      var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
      rp.forEach(function (q) { minX = Math.min(minX, q[0]); maxX = Math.max(maxX, q[0]); minY = Math.min(minY, q[1]); maxY = Math.max(maxY, q[1]); });
      var mx = MAX_ARROW + 6, my = view === 'side' ? 88 : 70;
      var km = Math.min((VIEW_W - 2 * mx) / (maxX - minX), (VIEW_H - 2 * my) / Math.max(maxY - minY, 0.1), 260);
      var cx = VIEW_W / 2 - (minX + maxX) / 2 * km, cy = VIEW_H / 2 + (minY + maxY) / 2 * km;
      function P(x, y) { var q = rotate(x, y, rot); return [cx + q[0] * km, cy - q[1] * km]; }

      // the ground
      if (view === 'side') {
        var g0 = P(-80, 0), g1 = P(80, 0);
        el('line', { x1: g0[0], y1: g0[1], x2: g1[0], y2: g1[1], class: 'fx-ground' }, svg);
      } else if (r.turn) {
        // A faint line from the rear axle to the turn centre: a dot there when it fits the view,
        // else an arrowhead at the view's edge with the distance.
        var side = s.steer > 0 ? -1 : 1, Rr = r.turn.radius;
        var c0 = P(V.xr, 0);
        var room = (side > 0 ? c0[1] : VIEW_H - c0[1]) - 22;  // px to the edge, less the label
        var fits = Rr * km <= room;
        var c1 = [c0[0], c0[1] - side * (fits ? Rr * km : room)];
        el('line', { x1: c0[0], y1: c0[1], x2: c1[0], y2: c1[1], class: 'fx-guide' }, svg);
        if (fits) {
          el('circle', { cx: c1[0], cy: c1[1], r: 3, fill: 'var(--fig-muted)' }, svg);
        } else {
          var tip = c1[1] - side * 6;
          el('path', { d: 'M' + c1[0] + ',' + tip + ' L' + (c1[0] - 4) + ',' + c1[1] + ' L' + (c1[0] + 4) + ',' + c1[1] + ' Z',
            fill: 'var(--fig-muted)' }, svg);
        }
        svgText(svg, c1[0] + 6, c1[1] + 4, 'turn centre' + (fits ? '' : ', ' + Math.round(Rr) + ' m away'));
      }

      // the vehicle
      shp.forEach(function (p) {
        if (p.poly) {
          var pp = p.poly.map(function (q) { return P(q[0], q[1]); });
          el('polygon', { points: pp.map(function (q) { return q[0].toFixed(1) + ',' + q[1].toFixed(1); }).join(' '), class: 'fx-' + (p.cls || 'body') }, svg);
        } else if (p.circle) {
          var c = P(p.x, p.y);
          el('circle', { cx: c[0], cy: c[1], r: p.r * km, class: 'fx-wheel' }, svg);
        } else if (p.wheel) {
          var wc = P(p.x, p.y);
          var rot = 'rotate(' + (-p.angle * 180 / Math.PI).toFixed(2) + ' ' + wc[0].toFixed(1) + ' ' + wc[1].toFixed(1) + ')';
          el('rect', { x: wc[0] - p.len / 2 * km, y: wc[1] - p.wid / 2 * km, width: p.len * km, height: p.wid * km, rx: 2,
            class: 'fx-wheel' + (p.grip && p.grip.lifted ? ' fx-lifted' : ''), transform: rot }, svg);
          // The share of its grip the tyre uses: a fill from the back of the tyre, full at the limit.
          if (p.grip && p.grip.use > 0.005) {
            el('rect', { x: wc[0] - p.len / 2 * km, y: wc[1] - p.wid / 2 * km, width: p.len * km * p.grip.use, height: p.wid * km, rx: 2,
              class: 'fx-grip', fill: p.grip.use >= 0.999 ? 'var(--fig-red)' : p.grip.use >= 0.7 ? 'var(--fig-orange)' : 'var(--fig-green)',
              transform: rot }, svg);
          }
        } else if (p.line) {
          var l0 = P(p.line[0][0], p.line[0][1]);
          var l1 = P(p.line[1][0], p.line[1][1]);
          el('line', { x1: l0[0], y1: l0[1], x2: l1[0], y2: l1[1], class: 'fx-strut' }, svg);
        }
      });

      // arrows: far side first, faint
      var list = r.arrows.filter(function (a) { return a.view === view && shown[a.id]; });
      list.sort(function (a, b) { return (b.far ? 1 : 0) - (a.far ? 1 : 0); });
      list.forEach(function (a) { drawArrow(svg, a, P, rot, kN); });

      // scale bar and context labels
      if (bar > 0) {
        var bl = bar * kN, bx = 12, by = VIEW_H - 14;
        el('line', { x1: bx, y1: by, x2: bx + bl, y2: by, stroke: 'var(--fig-ink)', 'stroke-width': 2 }, svg);
        el('line', { x1: bx, y1: by - 4, x2: bx, y2: by + 4, stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
        el('line', { x1: bx + bl, y1: by - 4, x2: bx + bl, y2: by + 4, stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
        svgText(svg, bx + bl + 6, by + 4, '= ' + fmtN(bar));
      } else {
        svgText(svg, 12, VIEW_H - 10, 'No force ticked.');
      }
      if (view === 'top') {
        svgText(svg, 12, 18, 'moving ' + Math.round(s.speed) + ' km/h →', { fill: 'var(--fig-ink)' });
        if (s.wind > 0) drawWind(svg, s);
      }
    }

    function rotate(x, y, a) { var c = Math.cos(a), s = Math.sin(a); return [x * c - y * s, x * s + y * c]; }

    function drawArrow(svg, a, P, rot, kN) {
      var F = FORCES[a.id];
      var mag = Math.hypot(a.fx, a.fy);
      var p0 = P(a.x, a.y);
      var d = rotate(a.fx, a.fy, rot);
      var len = mag * kN;
      var dx = d[0] * kN, dy = -d[1] * kN;
      var g = el('g', { class: 'fx-arrow' + (a.far ? ' fx-far' : ''), tabindex: a.far ? -1 : 0, role: 'button',
        'aria-label': F.name + ', ' + fmtN(mag) + ', at ' + a.where }, svg);
      if (a.far) g.setAttribute('transform', 'translate(5,-4)');
      el('title', {}, g).textContent = F.name + ': ' + fmtN(mag) + ' at ' + a.where;
      var colour = F.colour;
      // A tyre past its grip: a red ring where it touches the ground.
      if (a.sliding) el('circle', { cx: p0[0], cy: p0[1], r: 7, fill: 'none', stroke: 'var(--fig-red)', 'stroke-width': 2 }, g);
      if (len < TINY) {
        el('circle', { cx: p0[0], cy: p0[1], r: 2.5, fill: colour }, g);
      } else {
        var ux = dx / len, uy = dy / len;
        var head = Math.min(8, len * 0.6), hw = head * 0.55;
        var bx = p0[0] + dx - ux * head, by = p0[1] + dy - uy * head;
        el('line', { x1: p0[0], y1: p0[1], x2: bx, y2: by, stroke: colour, 'stroke-width': 2.5, 'stroke-dasharray': F.dash || 'none' }, g);
        el('path', { d: 'M' + (p0[0] + dx) + ',' + (p0[1] + dy) + ' L' + (bx - uy * hw) + ',' + (by + ux * hw) + ' L' + (bx + uy * hw) + ',' + (by - ux * hw) + ' Z', fill: colour }, g);
      }
      el('line', { x1: p0[0], y1: p0[1], x2: p0[0] + dx, y2: p0[1] + dy, class: 'fx-hit' }, g);
      onActivate(g, function () { showInfo(a.id, a.sliding); });
    }

    function drawWind(svg, s) {
      var w = windVector(s), m = Math.hypot(w.x, w.y);
      var x = VIEW_W - 34, y = 34, L = 18;
      var ux = w.x / m, uy = -w.y / m;
      el('line', { x1: x - ux * L, y1: y - uy * L, x2: x + ux * L, y2: y + uy * L, stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, svg);
      el('path', { d: 'M' + (x + ux * L) + ',' + (y + uy * L) + ' l' + (-ux * 7 - uy * 4) + ',' + (-uy * 7 + ux * 4) + ' l' + (uy * 8) + ',' + (-ux * 8) + ' Z', fill: 'var(--fig-muted)' }, svg);
      svgText(svg, x, y + 34, 'wind ' + s.wind + ' m/s', { 'text-anchor': 'middle' });
    }

    // An example puts every slider back to its vehicle's default, then sets its own.
    function applyPreset(i) {
      var p = PRESETS[i];
      setVehicle(p.veh);
      presetSelect.value = String(i);
      Object.keys(p.set).forEach(function (k) {
        if (k === 'windFrom') windDir.value = p.set[k];
        else if (k === 'ground') ground.value = p.set[k];
        else if (k === 'aids') aids.checked = p.set[k];
        else inputs[k].value = p.set[k];
      });
      update();
      example = p;
      presetHelp.innerHTML = '<strong>' + p.name + '.</strong> ' + p.look;
      help.button.hidden = false;
    }
    presetSelect.addEventListener('change', function () {
      if (presetSelect.value !== '') applyPreset(parseInt(presetSelect.value, 10));
    });
    controls.addEventListener('input', leaveExample);
    windDir.addEventListener('change', leaveExample);
    ground.addEventListener('change', leaveExample);
    aids.addEventListener('change', leaveExample);
    setVehicle('car');

    // A link from another page, forces.md#example-<id> (the address #forces/example-<id>), opens
    // with that example chosen and its explanation showing.
    function fromAddress() {
      var m = /\/example-([\w-]+)$/.exec(decodeURIComponent(location.hash));
      if (!m) return;
      for (var i = 0; i < PRESETS.length; i++) {
        if (PRESETS[i].id === m[1]) { applyPreset(i); help.open(true); return; }
      }
    }
    function onHash() {
      if (!document.contains(root)) { window.removeEventListener('hashchange', onHash); return; }
      fromAddress();
    }
    window.addEventListener('hashchange', onHash);
    fromAddress();
  }

  // `compute` is exposed for checking the numbers from a browser console.
  make.compute = compute;
  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets.forces = make;
})();
