// Forces on a vehicle: a top and a side view of one of the seven bodies, with each force drawn as
// an arrow on one shared scale. AN ILLUSTRATION, NOT THE PHYSICS: a simplified, steady-instant
// copy of the game's formulas (forces.md lists what it leaves out). Plain JS and SVG, no
// libraries. Every game figure is cited where it is set below, as file and code name; the
// physics-wide ones:
//   G 9.8          physics/3d/default_gravity (Godot's default; train_sim.gd GRAVITY 9.8)
//   RHO 1.225      vehicle_math.gd AIR_DENSITY
//   grip curve     GroundDriveSpec.grip_curve: peak 1 at 0.12 slip, 0.8 when locked or spinning
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
  // A world-frame (x forward, y up) vector seen in a body pitched by `rot` (+ = nose up).
  function toBody(fx, fy, rot) {
    var c = Math.cos(rot), s = Math.sin(rot);
    return { x: fx * c + fy * s, y: -fx * s + fy * c };
  }

  // ---- the forces ---------------------------------------------------------------------------
  // colour, dash, plain one-line explanation, and the guide page that says more.
  var FORCES = {
    weight: { name: 'Weight (gravity)', colour: 'var(--fig-ink)', page: 'weight-transfer', pageTitle: 'Weight transfer and rollover',
      text: 'Gravity pulls every part of the vehicle straight down; the game adds it up at one point, the centre of mass. On a slope, part of it pulls the vehicle downhill.' },
    normal: { name: 'Ground push on each wheel', colour: 'var(--fig-blue)', page: 'weight-transfer', pageTitle: 'Weight transfer and rollover',
      text: 'The ground pushes back up on each tyre, square to the ground. Speeding up, braking and turning move this push between the wheels.' },
    drive: { name: 'Drive force (tyres)', colour: 'var(--fig-green)', page: 'tyres', pageTitle: 'Tyres and slip',
      text: 'The engine turns the driven wheels; each tyre pushes back on the ground, and the ground pushes the vehicle forward. A tyre can push only as hard as its grip allows.' },
    brake: { name: 'Braking force (tyres)', colour: 'var(--fig-red)', page: 'brakes', pageTitle: 'Brakes',
      text: 'The brakes slow the wheels, and the tyres then hold the vehicle back against the ground. At a standstill they hold it still, up to their strength.' },
    lateral: { name: 'Side force (tyres)', colour: 'var(--fig-orange)', page: 'tyres', pageTitle: 'Tyres and slip',
      text: 'To turn, the tyres push sideways on the ground, toward the centre of the turn. Asked for more than their grip, they slide.' },
    rolling: { name: 'Rolling resistance', colour: 'var(--fx-purple, #7b3fb0)', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'A rolling tyre flexes, which costs a small, steady push backwards; a wheel carrying more weight pays more. It is zero at a standstill.' },
    drag: { name: 'Air drag', colour: 'var(--fig-muted)', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'The air the vehicle moves through holds it back. It is worked out from the speed through the air, so a headwind adds to it.' },
    side: { name: 'Crosswind push', colour: 'var(--fig-muted)', dash: '5 3', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'Wind blowing across the vehicle pushes it sideways, much harder than on its nose, because the side is much bigger than the front.' },
    buoyancy: { name: 'Buoyancy', colour: 'var(--fig-blue)', page: 'floating', pageTitle: 'Floating and boats',
      text: 'Water pushes up on the hull. The game measures it at four points: the deeper a point sits, the harder the water pushes it up.' },
    prop: { name: 'Propeller thrust', colour: 'var(--fig-green)', page: 'floating', pageTitle: 'Floating and boats',
      text: 'The propeller pushes water backwards, and the water pushes the boat forwards. It pushes low at the stern, which lifts the bow a little.' },
    water: { name: 'Water drag', colour: 'var(--fx-teal, #13807a)', page: 'floating', pageTitle: 'Floating and boats',
      text: 'The water holds the hull back. In the game this grows in step with the speed through the water: twice the speed, twice the drag.' },
    windage: { name: 'Windage', colour: 'var(--fig-muted)', page: 'floating', pageTitle: 'Floating and boats',
      text: 'The wind pushes on the part of the boat above the water, a little on the bow and more on the side.' },
    rudder: { name: 'Rudder turn (a twist)', colour: 'var(--fig-orange)', curl: true, page: 'floating', pageTitle: 'Floating and boats',
      text: 'The rudder turns the boat. The game applies it as a twist, not a push, so it is drawn as a curl that is not to scale. It grows with speed and with the propeller\'s wash.' },
    lift: { name: 'Lift', colour: 'var(--fx-teal, #13807a)', page: 'plane-flight', pageTitle: 'Plane flight',
      text: 'The wing pushes air down, and the air pushes the wing up. Lift grows with the square of the speed, and fades away below the stall speed.' },
    thrust: { name: 'Propeller thrust', colour: 'var(--fig-green)', page: 'plane-flight', pageTitle: 'Plane flight',
      text: 'The propeller pulls the plane forward. In the game it depends on the throttle only, not on the speed.' },
    airdrag: { name: 'Air drag', colour: 'var(--fig-muted)', page: 'plane-flight', pageTitle: 'Plane flight',
      text: 'The air holds the plane back. Like the lift, it grows with the square of the airspeed, so a headwind adds to it.' },
    rotor: { name: 'Rotor thrust', colour: 'var(--fig-green)', page: 'drone-flight', pageTitle: 'Drone flight',
      text: 'Each rotor pushes air down and is pushed up along its own axis. Tilting the drone tips that push, so part of it moves the drone along.' },
    dronedrag: { name: 'Air drag', colour: 'var(--fig-muted)', page: 'drone-flight', pageTitle: 'Drone flight',
      text: 'The air holds the drone back, in step with its speed through the air. To hold a speed the drone leans until its rotors cancel this.' },
    tractive: { name: 'Tractive effort', colour: 'var(--fig-green)', page: 'rail', pageTitle: 'Trains',
      text: 'The locomotive\'s motors turn its wheels against the rails: a fixed force at low speed, then a fixed power, so less force the faster it goes.' },
    running: { name: 'Running resistance', colour: 'var(--fx-purple, #7b3fb0)', page: 'rail', pageTitle: 'Trains',
      text: 'Each car\'s bearings, wheel flanges and air, worked out with the railway\'s Davis formula. It is zero at a standstill.' },
    trainbrake: { name: 'Braking force', colour: 'var(--fig-red)', page: 'rail', pageTitle: 'Trains',
      text: 'Every car brakes, up to the same force per car. At a standstill the brakes hold the train, up to that force.' },
    coupler: { name: 'Coupler pull', colour: 'var(--fig-orange)', page: 'rail', pageTitle: 'Trains',
      text: 'The links between the cars. Each one pulls the car behind forwards and the car in front backwards by the same amount.' },
    net: { name: 'Net force (what is left)', colour: 'var(--fig-ink)', dash: '2 3', page: null,
      text: 'All the pushes added together. Whatever is left over speeds the vehicle up, slows it down, or turns it.' }
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
      sliders: { speed: [0, 180, 60], slope: 30, load: 'The cars carry no load in the game.' }
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
    }),
    boat: {
      // boat-speed-a: mass 600 (boat-speed-a_spec.tres), center_of_mass y -0.317; boat-speed-a.tscn
      // probe_points x +-0.900, y -0.3, z +-1.618, float_depth 0.3 (so the water sits at y 0),
      // prop_offset (0, -0.238, 1.820), rudder_torque 6500, drag_long 360, drag_lat 2060; hull
      // boxes 4.044 x 2.142. boat.gd thrust_force 5200, reverse_thrust_factor 0.4, windage_long 6,
      // windage_lat 18, windage_offset (0, 0.55, 0.45). vehicle_math.gd RUDDER_SPEED_REF 6,
      // RUDDER_PROP_WASH 0.5. Steady afloat, the four probes share the weight.
      kind: 'boat', label: 'Boat (the speedboat)', mass: 600, comY: -0.317,
      probes: [[1.618, 0.9], [1.618, -0.9], [-1.618, 0.9], [-1.618, -0.9]], probeY: -0.3,
      thrust: 5200, propX: -1.820, propY: -0.238, rudderTorque: 6500, dragLong: 360, dragLat: 2060,
      windLong: 6, windLat: 18, windX: -0.45, windY: 0.55, length: 4.044, width: 2.142,
      sliders: { speed: [0, 60, 25], brake: 'Boats have no brakes.', slope: 'Water is flat.', load: 'The boats carry no load in the game.' }
    },
    plane: {
      // plane_spec.tres: mass 800, center_of_mass y -0.2, wheel_positions nose (0, 0, -2) and mains
      // (+-1.1, 0, 0.6), wheel_radius 0.22, rest_length 0.3, brake_torque 900 on every wheel
      // (brake_bias_front -1), mu_long 1.05 (GroundDriveSpec default), rolling_resistance 0
      // (GroundDriveSpec default), no ABS. plane.gd lift_coeff 13, lift_cap 16000, stall_speed 13,
      // full_lift_speed 20 (lift_frac: smoothstep between), max_thrust 9000 (rpm lerps idle to
      // redline with the throttle, so thrust = throttle x 9000 once spooled), drag_coeff 80 plus
      // drag_sq 10.5 (forward: 80u + 10.5u|u|, VehicleMath.damped_force's coeff_sq), drag_lat 1600
      // (linear); span 7 and length 5.5 size the drawing only. Lift and drag both use the air speed
      // along the nose (plane.gd _tick_extras: every aero term reads velocity relative to
      // WindField), with the wings level (aoa_factor 1).
      kind: 'plane', label: 'Plane', mass: 800, comY: -0.2,
      liftCoeff: 13, liftCap: 16000, stall: 13, fullLift: 20, maxThrust: 9000, dragCoeff: 80, dragSq: 10.5, dragLat: 1600,
      wheels: [{ name: 'nose wheel', x: 2, y: 0 }, { name: 'right main wheel', x: -0.6, y: -1.1 }, { name: 'left main wheel', x: -0.6, y: 1.1 }],
      wheelR: 0.22, groundY: -0.52, brakeT: 900, mu: 1.05, span: 7, length: 5.5,
      sliders: { speed: [0, 120, 70], steer: 'In the air, steering banks the plane; this page shows it flying straight.', slope: 'The page shows the plane level.', load: 'The plane carries no load in the game.' }
    },
    drone: {
      // drone_spec.tres mass 5; drone.gd max_thrust 150 (four rotors), climb_force 45 (full climb
      // stick), horizontal_drag 1.0 and vertical_drag 6.5 N per m/s against the air, max_tilt_deg
      // 32; drone_motors.gd arm_x = arm_z 0.407; drone_payload.gd MAX_PAYLOAD_KG 4. Lift thrust =
      // m g + climb x climb_force (drone.gd), leaning to cancel the drag.
      kind: 'drone', label: 'Drone', mass: 5, maxThrust: 150, climbForce: 45, hDrag: 1.0, maxTilt: 32, arm: 0.407,
      loadMax: 4,
      sliders: { speed: [0, 60, 20], steer: 'Steering turns the drone on the spot (yaw), which moves no arrow.', brake: 'Drones have no brakes; they lean back to slow down.', slope: 'Not used in the air.' }
    },
    train: {
      // train.gd loco_mass 50000, wagon_mass 34000, CAR_LENGTHS 6.72 then 4 x 6.24, COUPLER_GAP
      // 0.3. train_sim.gd tractive_effort: the grip limit mu_adh 0.35 x loco mass x g, then
      // max_power() / v, max_power() = power_to_mass 17080/715 W/kg x consist mass (4.44 MW);
      // davis_a 400, davis_b 15, davis_c 0.8 per car; max_brake 90000 per car (Coulomb: holds at
      // rest); grade force -m g sin(atan grade). The game's train ignores wind (wind_field.gd).
      kind: 'train', label: 'Train', masses: [50000, 34000, 34000, 34000, 34000], lengths: [6.72, 6.24, 6.24, 6.24, 6.24],
      gap: 0.3, muAdh: 0.35, powerToMass: 17080 / 715, davisA: 400, davisB: 15, davisC: 0.8, maxBrake: 90000,
      sliders: { speed: [0, 120, 50], slope: 4, steer: 'The rails do the steering.', load: 'The wagons carry no load in the game.', wind: 'The game\'s train ignores the wind.' }
    }
  };

  // ---- models -------------------------------------------------------------------------------
  // Each returns { arrows: [{ id, view: 'top'|'side', x, y, fx, fy, where, far }], curls,
  // net: { x, y }, mass, notes, sideRot }. Positions in metres, forces in newtons, body frame.

  // Best-gear wheel force at speed v: torque_curve x gear x final_drive x efficiency / radius
  // (Drivetrain.wheel_torque). Below the strongest rpm the page lets the clutch or converter slip
  // so the engine sits there; it leaves out a converter's torque multiplication.
  function driveForceMax(V, v) {
    if (V.limitKmh > 0 && v * 3.6 >= V.limitKmh) return 0;  // VehicleSpec.speed_limit_kmh
    var best = 0;
    V.gears.forEach(function (gr) {
      var total = gr * V.finalDrive;
      var rpm = v / V.driveR * total * 60 / (2 * Math.PI);
      if (rpm > V.redline) return;
      var f = sampleCurve(V.torque, Math.max(rpm, V.peakRpm)) * total * V.eff / V.driveR;
      if (f > best) best = f;
    });
    return best;
  }

  // At a standstill a brake holds against the other forces up to its strength; moving, it pushes
  // against the motion at full strength (the train's Coulomb brake, a wheel's held_force_range).
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

    var drive = s.throttle * driveForceMax(V, v);
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
        var fLat = grounded ? axleSide[key] * share : 0;
        var fRoll = moving ? -V.crr * N : 0;  // RayWheel.surface_drag_force on asphalt
        var muL = V.muLong * N, muY = V.muLat * (w.front ? 1 : V.rearLatGrip) * N;
        var fx = fDrive + fBrake;
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
          angle: wheelAngle(w), sliding: sliding });
        sumX += (fDrive + fBrake) * k + fRoll;
        sumY += fLat * k;
        latSum[key] += fLat * k;
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
      [['drive', r.drive], ['brake', r.brake], ['rolling', r.roll]].forEach(function (p) {
        if (!p[1]) return;
        arrows.push({ id: p[0], view: 'side', x: w.x, y: 0, fx: p[1], fy: 0, where: where, far: far });
        arrows.push({ id: p[0], view: 'top', x: w.x, y: w.y, fx: p[1] * c, fy: p[1] * sn, where: where, sliding: r.sliding });
      });
      if (r.lat) arrows.push({ id: 'lateral', view: 'top', x: w.x, y: w.y, fx: -r.lat * sn, fy: r.lat * c, where: where, sliding: r.sliding });
    });
    arrows.push({ id: 'weight', view: 'side', x: xc, y: h, fx: Wx, fy: -Wn, where: 'the centre of mass' });
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
          : 'A tyre is past its grip limit: with no ABS it locks, and grip falls to 0.8 of the peak.')
        : (V.tcs ? 'A driven tyre is at its grip limit: traction control holds it at the peak.'
          : 'A driven tyre is past its grip limit: it spins, and grip falls to 0.8 of the peak.'));
    }
    var held = Math.abs(res.sumY) / m;  // the sideways acceleration the tyres alone give
    var turn = isFinite(R) && moving ? { radius: R, ay: Math.abs(ay), held: held, heldRadius: held > 1e-6 ? v * v / held : Infinity, pull: Math.abs(res.sumY) } : null;
    return { arrows: arrows, curls: [], net: { x: netX, y: netY }, mass: m, notes: notes, sideRot: th, turn: turn,
      steerAngles: res.wheels.map(function (r) { return r.angle; }) };
  }

  function modelBoat(V, s) {
    var m = V.mass, W = m * G, v = s.speed / 3.6;
    var wind = windVector(s);
    var ax = v - wind.x, ay = -wind.y;          // air velocity on the hull
    var thrust = s.throttle * V.thrust;         // thrust_scale(t) = t when t >= 0
    var water = -V.dragLong * v;                // damped_force: linear in the speed through water
    var wLong = -V.windLong * ax, wLat = -V.windLat * ay;
    // VehicleMath.flow_authority with prop wash: |v| / 6 + |throttle| x 0.5, capped at 1.
    var authority = clamp(v / 6 + s.throttle * 0.5, 0, 1);
    var twist = s.steer * V.rudderTorque * authority;
    var arrows = [];
    V.probes.forEach(function (p) {
      var where = (p[0] > 0 ? 'bow' : 'stern') + ' ' + (p[1] > 0 ? 'left' : 'right') + ' probe';
      arrows.push({ id: 'buoyancy', view: 'side', x: p[0], y: V.probeY, fx: 0, fy: W / 4, where: where, far: p[1] > 0 });
    });
    arrows.push({ id: 'weight', view: 'side', x: 0, y: V.comY, fx: 0, fy: -W, where: 'the centre of mass' });
    if (thrust) {
      arrows.push({ id: 'prop', view: 'side', x: V.propX, y: V.propY, fx: thrust, fy: 0, where: 'the propeller' });
      arrows.push({ id: 'prop', view: 'top', x: V.propX, y: 0, fx: thrust, fy: 0, where: 'the propeller' });
    }
    if (water) {
      arrows.push({ id: 'water', view: 'side', x: 0, y: V.comY, fx: water, fy: 0, where: 'the centre of mass' });
      arrows.push({ id: 'water', view: 'top', x: 0, y: 0, fx: water, fy: 0, where: 'the centre of mass' });
    }
    if (wLong) {
      arrows.push({ id: 'windage', view: 'side', x: 0, y: V.comY, fx: wLong, fy: 0, where: 'the centre of mass' });
      arrows.push({ id: 'windage', view: 'top', x: 0, y: 0, fx: wLong, fy: 0, where: 'the centre of mass' });
    }
    if (wLat) arrows.push({ id: 'windage', view: 'top', x: V.windX, y: 0, fx: 0, fy: wLat, where: 'above the water, behind the middle' });
    var netX = thrust + water + wLong;
    arrows.push({ id: 'net', view: 'side', x: 0, y: V.comY, fx: netX, fy: 0, where: 'the centre of mass' });
    arrows.push({ id: 'net', view: 'top', x: 0, y: 0, fx: netX, fy: wLat, where: 'the centre of mass' });
    var curls = twist ? [{ id: 'rudder', x: V.propX, y: 0, torque: twist, where: 'about the middle of the boat' }] : [];
    var notes = [];
    if (s.steer && authority < 0.3) notes.push('The rudder does little this slowly: it needs speed, or the propeller\'s wash over it.');
    if (wLat) notes.push('The game\'s side drag in the water stops the crosswind from pushing the boat sideways for long; this page shows only the first push.');
    return { arrows: arrows, curls: curls, net: { x: netX, y: wLat }, mass: m, notes: notes, sideRot: 0 };
  }

  function modelPlane(V, s) {
    var m = V.mass, W = m * G, v = s.speed / 3.6;
    var wind = windVector(s);
    var ux = v - wind.x, uy = -wind.y;
    var air = Math.max(ux, 0);
    var t = clamp((air - V.stall) / (V.fullLift - V.stall), 0, 1);
    var lift = Math.min(V.liftCoeff * air * air, V.liftCap) * t * t * (3 - 2 * t);  // PlaneVehicle.lift_force
    var thrust = s.throttle * V.maxThrust;
    var drag = -(V.dragCoeff + V.dragSq * Math.abs(ux)) * ux, dragY = -V.dragLat * uy;
    var onGround = lift < W;
    var gearLoad = onGround ? W - lift : 0;
    var xn = V.wheels[0].x, xm = V.wheels[1].x;
    var noseN = gearLoad * (0 - xm) / (xn - xm);
    var Ns = [noseN, (gearLoad - noseN) / 2, (gearLoad - noseN) / 2];
    var moving = v > 0.05;
    var cap = s.brake * V.brakeT / V.wheelR;
    var arrows = [], sumX = 0, notes = [], locked = false;
    var brakeAll = onGround ? brakeShare(cap * 3, thrust + drag, moving, 1) : 0;
    V.wheels.forEach(function (w, i) {
      var N = Ns[i];
      var fb = brakeAll / 3;
      if (Math.abs(fb) > V.mu * N) {
        fb = sgn(fb) * V.mu * N * (moving ? 0.8 : 1);   // no ABS: a locked wheel slides at 0.8
        if (moving) locked = true;
      }
      sumX += fb;
      if (onGround) arrows.push({ id: 'normal', view: 'side', x: w.x, y: V.groundY, fx: 0, fy: N, where: 'the ' + w.name, far: w.y > 0 });
      if (fb) {
        arrows.push({ id: 'brake', view: 'side', x: w.x, y: V.groundY, fx: fb, fy: 0, where: 'the ' + w.name, far: w.y > 0 });
        arrows.push({ id: 'brake', view: 'top', x: w.x, y: w.y, fx: fb, fy: 0, where: 'the ' + w.name });
      }
    });
    arrows.push({ id: 'weight', view: 'side', x: 0, y: V.comY, fx: 0, fy: -W, where: 'the centre of mass' });
    if (lift) arrows.push({ id: 'lift', view: 'side', x: 0, y: 0.1, fx: 0, fy: lift, where: 'the wing' });
    if (thrust) {
      arrows.push({ id: 'thrust', view: 'side', x: V.length / 2, y: 0, fx: thrust, fy: 0, where: 'the propeller' });
      arrows.push({ id: 'thrust', view: 'top', x: V.length / 2, y: 0, fx: thrust, fy: 0, where: 'the propeller' });
    }
    if (drag) {
      arrows.push({ id: 'airdrag', view: 'side', x: 0, y: V.comY, fx: drag, fy: 0, where: 'the centre of mass' });
      arrows.push({ id: 'airdrag', view: 'top', x: 0, y: 0, fx: drag, fy: 0, where: 'the centre of mass' });
    }
    if (dragY) arrows.push({ id: 'airdrag', view: 'top', x: 0, y: 0, fx: 0, fy: dragY, where: 'the centre of mass' });
    var netX = thrust + drag + sumX, netUp = onGround ? 0 : lift - W;
    arrows.push({ id: 'net', view: 'side', x: 0, y: V.comY, fx: netX, fy: netUp, where: 'the centre of mass' });
    arrows.push({ id: 'net', view: 'top', x: 0, y: 0, fx: netX, fy: dragY, where: 'the centre of mass' });
    if (locked) notes.push('A wheel locks: with no ABS, its grip falls to 0.8 of the peak.');
    if (air < V.stall && v > 1) notes.push('Below the stall speed the wing gives no lift at all.');
    if (!onGround) notes.push('Lift is more than the weight: the plane leaves the ground.');
    else if (lift > 0) notes.push('The wing already carries ' + Math.round(lift / W * 100) + ' % of the weight; the wheels carry the rest.');
    return { arrows: arrows, curls: [], net: { x: netX, y: netUp }, mass: m, notes: notes, sideRot: 0, airborne: !onGround };
  }

  function modelDrone(V, s) {
    var m = V.mass + s.load, W = m * G, v = s.speed / 3.6;
    var wind = windVector(s);
    var ux = v - wind.x, uy = -wind.y;
    var dragX = -V.hDrag * ux, dragY = -V.hDrag * uy;
    var up = clamp(W + s.throttle * V.climbForce, 0, V.maxThrust);  // drone.gd lift_thrust
    // Lean so the thrust's level part cancels the drag, up to max_tilt_deg.
    var hx = -dragX, hy = -dragY, hMag = Math.hypot(hx, hy);
    var hMax = up * Math.tan(V.maxTilt * Math.PI / 180);
    var notes = [];
    if (hMag > hMax) { hx *= hMax / hMag; hy *= hMax / hMag; hMag = hMax; notes.push('The drone is leaning as far as it may (32°) and still cannot hold this speed.'); }
    var T = Math.hypot(up, hMag);
    if (T > V.maxThrust) {
      var k = V.maxThrust / T; up *= k; hx *= k; hy *= k; hMag *= k; T = V.maxThrust;
      notes.push('The rotors are at full power.');
    }
    var tilt = -Math.atan2(hx, up);              // nose down to go forward
    var arrows = [], per = T / 4;
    [[V.arm, 1], [-V.arm, 1], [V.arm, -1], [-V.arm, -1]].forEach(function (p) {
      var where = (p[0] > 0 ? 'front' : 'back') + ' ' + (p[1] > 0 ? 'left' : 'right') + ' rotor';
      arrows.push({ id: 'rotor', view: 'side', x: p[0], y: 0.08, fx: 0, fy: per, where: where, far: p[1] > 0 });
      if (hMag > 0) arrows.push({ id: 'rotor', view: 'top', x: p[0], y: p[1] * V.arm, fx: hx / 4, fy: hy / 4, where: where + ' (its level part)' });
    });
    var wb = toBody(0, -V.mass * G, tilt);
    arrows.push({ id: 'weight', view: 'side', x: 0, y: 0, fx: wb.x, fy: wb.y, where: 'the drone' });
    if (s.load > 0) {
      var hook = toBody(0, -0.7, tilt), wp = toBody(0, -s.load * G, tilt);
      arrows.push({ id: 'weight', view: 'side', x: hook.x, y: hook.y, fx: wp.x, fy: wp.y, where: 'the load on the hook' });
    }
    if (dragX || dragY) {
      var db = toBody(dragX, 0, tilt);
      if (dragX) arrows.push({ id: 'dronedrag', view: 'side', x: 0, y: 0, fx: db.x, fy: db.y, where: 'the drone' });
      arrows.push({ id: 'dronedrag', view: 'top', x: 0, y: 0, fx: dragX, fy: dragY, where: 'the drone' });
    }
    var netX = hx + dragX, netY = hy + dragY, netUp = up - W;
    var nb = toBody(netX, netUp, tilt);
    arrows.push({ id: 'net', view: 'side', x: 0, y: 0, fx: nb.x, fy: nb.y, where: 'the drone' });
    arrows.push({ id: 'net', view: 'top', x: 0, y: 0, fx: netX, fy: netY, where: 'the drone' });
    if (Math.abs(netUp) > 0.5) notes.push(netUp > 0 ? 'More thrust than weight: the drone climbs.' : 'Less thrust than weight: the drone sinks.');
    return { arrows: arrows, curls: [], net: { x: netX, y: netUp }, mass: m, notes: notes, sideRot: tilt, tilt: tilt, hookLoad: s.load };
  }

  function modelTrain(V, s) {
    var th = Math.atan(s.slope / 100), v = s.speed / 3.6, moving = v > 0.05;
    var n = V.masses.length, M = 0;
    V.masses.forEach(function (mm) { M += mm; });
    // Car centres, front (the loco) first, from x = 0 backwards.
    var centres = [], x = 0;
    V.lengths.forEach(function (len) { centres.push(x - len / 2); x -= len + V.gap; });
    var grip = V.muAdh * V.masses[0] * G;
    var power = V.powerToMass * M;
    var te = s.throttle * (v > 0 ? Math.min(grip, power / v) : grip);
    var forces = [], arrows = [];
    var davis = moving ? -(V.davisA + V.davisB * v + V.davisC * v * v) : 0;
    var others = te, grades = [];
    V.masses.forEach(function (mm) { var gx = -mm * G * Math.sin(th); grades.push(gx); others += gx + davis; });
    var brakeAll = brakeShare(s.brake * V.maxBrake * n, others, moving, 1);
    V.masses.forEach(function (mm, i) {
      var f = grades[i] + davis + brakeAll / n + (i === 0 ? te : 0);
      forces.push(f);
      var cx = centres[i], half = V.lengths[i] / 2, name = i === 0 ? 'the locomotive' : 'wagon ' + i;
      var Wn = mm * G * Math.cos(th);
      arrows.push({ id: 'weight', view: 'side', x: cx, y: 1.6, fx: grades[i], fy: -Wn, where: name });
      arrows.push({ id: 'normal', view: 'side', x: cx - half * 0.6, y: 0, fx: 0, fy: Wn / 2, where: name + ', rear bogie' });
      arrows.push({ id: 'normal', view: 'side', x: cx + half * 0.6, y: 0, fx: 0, fy: Wn / 2, where: name + ', front bogie' });
      if (davis) {
        arrows.push({ id: 'running', view: 'side', x: cx, y: 0.3, fx: davis, fy: 0, where: name });
        arrows.push({ id: 'running', view: 'top', x: cx, y: 0.5, fx: davis, fy: 0, where: name });
      }
      if (brakeAll) {
        arrows.push({ id: 'trainbrake', view: 'side', x: cx - half * 0.6, y: 0, fx: brakeAll / n, fy: 0, where: name });
        arrows.push({ id: 'trainbrake', view: 'top', x: cx, y: -0.5, fx: brakeAll / n, fy: 0, where: name });
      }
    });
    if (te) {
      arrows.push({ id: 'tractive', view: 'side', x: centres[0], y: 0, fx: te, fy: 0, where: 'the locomotive\'s wheels' });
      arrows.push({ id: 'tractive', view: 'top', x: centres[0], y: 0, fx: te, fy: 0, where: 'the locomotive\'s wheels' });
    }
    var net = 0;
    forces.forEach(function (f) { net += f; });
    var acc = net / M;
    // The cars share one acceleration; coupler i carries what the cars behind it need beyond their
    // own forces (TrainSim's spring couplers, settled).
    for (var i = 0; i < n - 1; i++) {
      var pull = 0;
      for (var j = i + 1; j < n; j++) pull += V.masses[j] * acc - forces[j];
      var cxp = centres[i] - V.lengths[i] / 2 - V.gap / 2, label = 'the coupler behind ' + (i === 0 ? 'the locomotive' : 'wagon ' + i);
      arrows.push({ id: 'coupler', view: 'side', x: cxp - V.gap / 2, y: 1.0, fx: pull, fy: 0, where: label + ', on the car behind' });
      arrows.push({ id: 'coupler', view: 'side', x: cxp + V.gap / 2, y: 1.0, fx: -pull, fy: 0, where: label + ', on the car in front' });
    }
    arrows.push({ id: 'net', view: 'top', x: centres[2], y: 0, fx: net, fy: 0, where: 'the whole train' });
    arrows.push({ id: 'net', view: 'side', x: centres[2], y: 1.6, fx: net, fy: 0, where: 'the whole train' });
    return { arrows: arrows, curls: [], net: { x: net, y: 0 }, mass: M, notes: [], sideRot: th, centres: centres };
  }

  function compute(key, s) {
    var V = VEHICLES[key];
    if (V.kind === 'wheeled') return modelWheeled(V, s);
    if (V.kind === 'boat') return modelBoat(V, s);
    if (V.kind === 'plane') return modelPlane(V, s);
    if (V.kind === 'drone') return modelDrone(V, s);
    return modelTrain(V, s);
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
          out.push({ wheel: true, x: w.x, y: w.y, len: w.r * 2, wid: w.hw * 2, angle: r.steerAngles ? r.steerAngles[i] : 0 });
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
    } else if (V.kind === 'boat') {
      var hl = V.length / 2, hw = V.width / 2;
      if (view === 'top') {
        out.push({ poly: [[-hl, -hw], [hl - 1.1, -hw], [hl, 0], [hl - 1.1, hw], [-hl, hw]], cls: 'body' });
        out.push({ poly: rect(-0.6, -0.7, 0.4, 0.7), cls: 'glass' });
      } else {
        out.push({ poly: [[-hl, -0.4], [hl - 1.2, -0.4], [hl, 0.5], [-hl, 0.5]], cls: 'body' });
        out.push({ poly: [[-0.6, 0.5], [0.4, 0.5], [0.1, 1.0], [-0.6, 1.0]], cls: 'glass' });
      }
    } else if (V.kind === 'plane') {
      var half = V.length / 2;
      if (view === 'top') {
        out.push({ poly: [[-half, -0.3], [half - 0.6, -0.5], [half, -0.3], [half, 0.3], [half - 0.6, 0.5], [-half, 0.3]], cls: 'body' });
        out.push({ poly: rect(-0.5, -V.span / 2, 0.7, V.span / 2), cls: 'body' });
        out.push({ poly: rect(-half, -1.5, -half + 0.7, 1.5), cls: 'body' });
        V.wheels.forEach(function (w) { out.push({ wheel: true, x: w.x, y: w.y, len: V.wheelR * 2, wid: 0.14, angle: 0 }); });
      } else {
        out.push({ poly: [[-half, 0.1], [-half, 1.2], [-half + 0.6, 1.2], [-half + 1.2, 0.4], [half - 1.4, 0.75], [half - 0.3, 0.45], [half, 0.0], [half - 0.3, -0.35], [-half + 1.5, -0.25]], cls: 'body' });
        out.push({ poly: rect(-0.5, 0.05, 0.7, 0.2), cls: 'glass' });
        V.wheels.forEach(function (w) {
          if (w.y <= 0) {
            out.push({ line: [[w.x, -0.25], [w.x, V.groundY + V.wheelR]] });
            out.push({ circle: true, x: w.x, y: V.groundY + V.wheelR, r: V.wheelR });
          }
        });
      }
    } else if (V.kind === 'drone') {
      var arm = V.arm;
      if (view === 'top') {
        out.push({ line: [[-arm, -arm], [arm, arm]] });
        out.push({ line: [[-arm, arm], [arm, -arm]] });
        [[arm, arm], [arm, -arm], [-arm, arm], [-arm, -arm]].forEach(function (p) { out.push({ circle: true, x: p[0], y: p[1], r: 0.2, cls: 'rotor' }); });
        out.push({ poly: rect(-0.12, -0.12, 0.16, 0.12), cls: 'body' });
      } else {
        out.push({ line: [[-arm, 0.04], [arm, 0.04]] });
        out.push({ poly: rect(-0.14, -0.08, 0.18, 0.06), cls: 'body' });
        [arm, -arm].forEach(function (x) { out.push({ poly: rect(x - 0.2, 0.07, x + 0.2, 0.1), cls: 'rotor' }); });
        if (r.hookLoad > 0) {
          out.push({ line: [[0, -0.08], [0, -0.6]], world: true });
          out.push({ poly: rect(-0.12, -0.82, 0.12, -0.6), cls: 'load', world: true });
        }
      }
    } else {
      r.centres.forEach(function (cx, i) {
        var half = V.lengths[i] / 2;
        if (view === 'top') out.push({ poly: rect(cx - half, -1.4, cx + half, 1.4), cls: i === 0 ? 'glass' : 'body' });
        else {
          out.push({ poly: i === 0 ? [[cx - half, 0.6], [cx + half, 0.6], [cx + half, 3.2], [cx + half - 1.6, 3.6], [cx - half, 3.6]] : rect(cx - half, 0.6, cx + half, 3.3), cls: i === 0 ? 'glass' : 'body' });
          [-1, 1].forEach(function (k) { out.push({ circle: true, x: cx + k * half * 0.6, y: 0.4, r: 0.4 }); });
        }
      });
    }
    return out;
  }

  // ---- the widget ---------------------------------------------------------------------------
  var ORDER = ['car', 'truck', 'tractor', 'boat', 'plane', 'drone', 'train'];
  var FORCE_SETS = {
    wheeled: ['weight', 'normal', 'drive', 'brake', 'lateral', 'rolling', 'drag', 'side', 'net'],
    boat: ['weight', 'buoyancy', 'prop', 'water', 'windage', 'rudder', 'net'],
    plane: ['weight', 'lift', 'thrust', 'airdrag', 'normal', 'brake', 'net'],
    drone: ['weight', 'rotor', 'dronedrag', 'net'],
    train: ['weight', 'normal', 'tractive', 'running', 'trainbrake', 'coupler', 'net']
  };

  function make(root) {
    root.innerHTML = '';
    var uid = 'fx' + Math.random().toString(36).slice(2, 8);
    var shown = {};
    Object.keys(FORCES).forEach(function (id) { shown[id] = id !== 'net'; });
    var current = 'car';

    function addEl(tag, cls, parent, html) {
      var e = document.createElement(tag);
      if (cls) e.className = cls;
      if (html !== undefined) e.innerHTML = html;
      (parent || root).appendChild(e);
      return e;
    }
    addEl('p', 'w-title', root, 'Try it: the forces on a vehicle');
    var pick = addEl('div', 'fx-pick');
    pick.innerHTML = '<label for="' + uid + '-veh">Vehicle</label> <select id="' + uid + '-veh"></select>';
    var vehSelect = pick.querySelector('select');
    ORDER.forEach(function (k) {
      var o = document.createElement('option');
      o.value = k;
      o.textContent = VEHICLES[k].label;
      vehSelect.appendChild(o);
    });

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
    var unused = addEl('p', 'w-note');
    addEl('p', 'w-note', root, 'An illustration, not the physics: a simplified copy of the game\'s formulas at one instant, with wheels on dry asphalt. All arrows in a view share that view\'s scale bar; untick the biggest forces to zoom in on the small ones.');

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

    function showInfo(id, arrow) {
      var F = FORCES[id];
      var html = '<strong>' + F.name + '.</strong> ' + F.text;
      if (arrow) html += ' <span class="fx-this">This arrow: ' + fmtN(arrow.mag) + ', at ' + arrow.where + (arrow.sliding ? ', sliding' : '') + '.</span>';
      if (F.page) html += ' <a href="#' + F.page + '">More: ' + F.pageTitle + '</a>';
      info.innerHTML = html;
    }
    info.innerHTML = 'Point at an arrow or a force\'s name, or tap it, to read what it is.';

    function setVehicle(key) {
      current = key;
      var V = VEHICLES[key], cfg = V.sliders, notes = [];
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
      if (V.kind === 'drone') {
        labels.throttle.textContent = 'Climb stick';
        inputs.throttle.min = -1; inputs.throttle.value = 0;
      } else {
        labels.throttle.textContent = 'Throttle';
        inputs.throttle.min = 0; inputs.throttle.value = 0.3;
      }
      labels.steer.textContent = V.kind === 'boat' ? 'Rudder' : 'Steering';
      var loadMax = V.loadMax || 0;
      inputs.load.max = loadMax || 100;
      inputs.load.step = loadMax > 100 ? 50 : 0.1;
      inputs.load.value = 0;
      labels.load.textContent = V.loadLabel || (V.kind === 'drone' ? 'Load (on the hook)' : 'Load');
      ['steer', 'brake', 'slope', 'load', 'wind'].forEach(function (k) {
        var reason = typeof cfg[k] === 'string' ? cfg[k] : null;
        if (k === 'slope' && typeof cfg.slope === 'number') reason = null;
        inputs[k].disabled = !!reason;
        labels[k].classList.toggle('fx-off', !!reason);
        if (reason) notes.push(labels[k].textContent + ': ' + reason);
      });
      windDir.disabled = inputs.wind.disabled;
      wl.classList.toggle('fx-off', windDir.disabled);
      unused.textContent = notes.length ? 'Not used here. ' + notes.join(' ') : '';
      unused.hidden = !notes.length;
      buildLegend();
      update();
    }

    var rows = {};
    function buildLegend() {
      legend.innerHTML = '<legend>Forces to show</legend>';
      rows = {};
      var kind = VEHICLES[current].kind;
      FORCE_SETS[kind].forEach(function (id) {
        var F = FORCES[id];
        var row = addEl('label', 'fx-row', legend);
        var cb = addEl('input', '', row);
        cb.type = 'checkbox'; cb.checked = shown[id];
        var sw = el('svg', { viewBox: '0 0 28 10', class: 'fx-swatch', 'aria-hidden': 'true' }, row);
        if (F.curl) el('path', { d: 'M4,8 A7,5 0 1 1 20,6', fill: 'none', stroke: F.colour, 'stroke-width': 2.5 }, sw);
        else el('line', { x1: 2, y1: 5, x2: 26, y2: 5, stroke: F.colour, 'stroke-width': 3, 'stroke-dasharray': F.dash || 'none' }, sw);
        addEl('span', 'fx-name', row, F.name);
        var val = addEl('span', 'fx-val', row);
        cb.addEventListener('change', function () { shown[id] = cb.checked; showInfo(id); update(); });
        row.addEventListener('mouseenter', function () { showInfo(id); });
        cb.addEventListener('focus', function () { showInfo(id); });
        rows[id] = val;
      });
    }

    function readState() {
      return {
        speed: parseFloat(inputs.speed.value), steer: parseFloat(inputs.steer.disabled ? 0 : inputs.steer.value),
        throttle: parseFloat(inputs.throttle.value), brake: inputs.brake.disabled ? 0 : parseFloat(inputs.brake.value),
        slope: inputs.slope.disabled ? 0 : parseFloat(inputs.slope.value), load: inputs.load.disabled ? 0 : parseFloat(inputs.load.value),
        wind: inputs.wind.disabled ? 0 : parseFloat(inputs.wind.value), windFrom: windDir.value
      };
    }

    function writeOutputs(s) {
      outputs.speed.textContent = Math.round(s.speed) + ' km/h';
      outputs.steer.textContent = inputs.steer.disabled ? '' : s.steer === 0 ? 'straight' : Math.round(Math.abs(s.steer) * 100) + ' % ' + (s.steer > 0 ? 'right' : 'left');
      outputs.throttle.textContent = VEHICLES[current].kind === 'drone'
        ? (s.throttle === 0 ? 'hold height' : Math.round(Math.abs(s.throttle) * 100) + ' % ' + (s.throttle > 0 ? 'up' : 'down'))
        : Math.round(s.throttle * 100) + ' %';
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
      // both views appears once in each; the top view holds a drone's or boat's sideways part).
      var sums = { top: {}, side: {} };
      r.arrows.forEach(function (a) { sums[a.view][a.id] = (sums[a.view][a.id] || 0) + Math.hypot(a.fx, a.fy); });
      var netMag = Math.hypot(r.net.x, r.net.y);
      Object.keys(rows).forEach(function (id) {
        var t = Math.max(sums.top[id] || 0, sums.side[id] || 0);
        var many = r.arrows.filter(function (a) { return a.id === id && a.view === (sums.side[id] >= (sums.top[id] || 0) ? 'side' : 'top'); }).length > 1;
        if (id === 'net') rows[id].textContent = fmtN(netMag);
        else if (FORCES[id].curl) rows[id].textContent = r.curls.length ? Math.round(Math.abs(r.curls[0].torque)) + ' N·m' : '0';
        else if (id === 'coupler') rows[id].textContent = 'up to ' + fmtN(maxCoupler(r));
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
    function maxCoupler(r) {
      var m = 0;
      r.arrows.forEach(function (a) { if (a.id === 'coupler') m = Math.max(m, Math.abs(a.fx)); });
      return m;
    }

    function writeReadout(V, r, s) {
      var along = r.net.x, acc = along / r.mass;
      var lines = [];
      if (Math.abs(acc) < 0.005) lines.push('<strong>The forces along the direction of travel balance:</strong> the speed holds.');
      else if (s.speed < 0.5 && acc < 0) lines.push('<strong>Net force ' + fmtN(Math.abs(along)) + ' backwards:</strong> the vehicle starts to move back at ' + Math.abs(acc).toFixed(2) + ' m/s².');
      else lines.push('<strong>Net force ' + fmtN(Math.abs(along)) + (acc > 0 ? ' forward' : ' backwards') + ':</strong> ' +
        (acc > 0 ? 'speeding up' : 'slowing down') + ' at ' + Math.abs(acc).toFixed(2) + ' m/s² (' + (Math.abs(acc) / G).toFixed(2) + ' g).');
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
      if (view === 'side' && V.kind !== 'drone') pts.push([pts[0][0], V.kind === 'plane' ? V.groundY : 0]);
      var rp = pts.map(function (q) { return rotate(q[0], q[1], rot); });
      var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
      rp.forEach(function (q) { minX = Math.min(minX, q[0]); maxX = Math.max(maxX, q[0]); minY = Math.min(minY, q[1]); maxY = Math.max(maxY, q[1]); });
      var mx = MAX_ARROW + 6, my = view === 'side' ? 88 : 70;
      var km = Math.min((VIEW_W - 2 * mx) / (maxX - minX), (VIEW_H - 2 * my) / Math.max(maxY - minY, 0.1), 260);
      var cx = VIEW_W / 2 - (minX + maxX) / 2 * km, cy = VIEW_H / 2 + (minY + maxY) / 2 * km;
      function P(x, y) { var q = rotate(x, y, rot); return [cx + q[0] * km, cy - q[1] * km]; }

      // ground, water or rail
      if (view === 'side') {
        if (V.kind === 'boat') {
          var wy = P(0, 0)[1];
          el('rect', { x: 0, y: wy, width: VIEW_W, height: VIEW_H - wy, class: 'fx-water' }, svg);
          el('line', { x1: 0, y1: wy, x2: VIEW_W, y2: wy, class: 'fx-ground' }, svg);
        } else if (V.kind !== 'drone' && !(V.kind === 'plane' && r.airborne)) {
          var gy = V.kind === 'plane' ? V.groundY : 0;
          var g0 = P(-80, gy), g1 = P(80, gy);
          el('line', { x1: g0[0], y1: g0[1], x2: g1[0], y2: g1[1], class: 'fx-ground' }, svg);
        }
      } else if (V.kind === 'wheeled' && r.turn) {
        // the turn centre's direction, as a faint line from the rear axle
        var side = s.steer > 0 ? -1 : 1, Rr = r.turn.radius;
        var c0 = P(V.xr, 0), c1 = P(V.xr, side * Math.min(Rr, 6));
        el('line', { x1: c0[0], y1: c0[1], x2: c1[0], y2: c1[1], class: 'fx-guide' }, svg);
        if (Rr < 6) svgText(svg, c1[0] + 4, c1[1] + (side > 0 ? -4 : 12), 'turn centre');
      }

      // the vehicle
      shp.forEach(function (p) {
        if (p.poly) {
          var pp = p.poly.map(function (q) { return p.world ? Pw(q) : P(q[0], q[1]); });
          el('polygon', { points: pp.map(function (q) { return q[0].toFixed(1) + ',' + q[1].toFixed(1); }).join(' '), class: 'fx-' + (p.cls || 'body') }, svg);
        } else if (p.circle) {
          var c = P(p.x, p.y);
          el('circle', { cx: c[0], cy: c[1], r: p.r * km, class: p.cls === 'rotor' ? 'fx-rotor' : 'fx-wheel' }, svg);
        } else if (p.wheel) {
          var wc = P(p.x, p.y);
          el('rect', { x: wc[0] - p.len / 2 * km, y: wc[1] - p.wid / 2 * km, width: p.len * km, height: p.wid * km, rx: 2, class: 'fx-wheel',
            transform: 'rotate(' + (-p.angle * 180 / Math.PI).toFixed(2) + ' ' + wc[0].toFixed(1) + ' ' + wc[1].toFixed(1) + ')' }, svg);
        } else if (p.line) {
          var l0 = p.world ? Pw(p.line[0]) : P(p.line[0][0], p.line[0][1]);
          var l1 = p.world ? Pw(p.line[1]) : P(p.line[1][0], p.line[1][1]);
          el('line', { x1: l0[0], y1: l0[1], x2: l1[0], y2: l1[1], class: 'fx-strut' }, svg);
        }
      });
      // a hanging load stays below the drone whatever its tilt
      function Pw(q) { var o = P(0, 0); return [o[0] + q[0] * km, o[1] - q[1] * km]; }

      // arrows: far side first, faint
      var list = r.arrows.filter(function (a) { return a.view === view && shown[a.id]; });
      list.sort(function (a, b) { return (b.far ? 1 : 0) - (a.far ? 1 : 0); });
      list.forEach(function (a) { drawArrow(svg, a, P, rot, kN); });
      if (view === 'top' && shown.rudder) r.curls.forEach(function (c) { drawCurl(svg, c, P); });

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
        svgText(svg, 12, 18, (V.kind === 'drone' ? 'flying ' : 'moving ') + Math.round(s.speed) + ' km/h →', { fill: 'var(--fig-ink)' });
        if (s.wind > 0) drawWind(svg, s);
      } else if (V.kind === 'drone' && r.tilt) {
        svgText(svg, 12, 18, 'leaning ' + Math.abs(Math.round(r.tilt * 180 / Math.PI)) + '° ' + (r.tilt < 0 ? 'forward' : 'back'), { fill: 'var(--fig-ink)' });
      } else if (V.kind === 'plane') {
        svgText(svg, 12, 18, r.airborne ? 'flying' : 'on the runway', { fill: 'var(--fig-ink)' });
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
      var hit = function () { showInfo(a.id, { mag: mag, where: a.where, sliding: a.sliding }); };
      g.addEventListener('mouseenter', hit);
      g.addEventListener('focus', hit);
      g.addEventListener('click', hit);
    }

    function drawCurl(svg, c, P) {
      var F = FORCES.rudder, p = P(c.x, c.y), R = 20, dir = c.torque > 0 ? 1 : -1;
      // + torque turns right: clockwise on screen. Screen angle phi grows clockwise (y is down),
      // so the curl runs 270 degrees from phi0 in the turning direction.
      var p0 = Math.PI * 0.75, p1 = p0 + dir * Math.PI * 1.5;
      var sx = p[0] + R * Math.cos(p0), sy = p[1] + R * Math.sin(p0);
      var ex = p[0] + R * Math.cos(p1), ey = p[1] + R * Math.sin(p1);
      var g = el('g', { class: 'fx-arrow', tabindex: 0, role: 'button', 'aria-label': F.name + ', ' + Math.round(Math.abs(c.torque)) + ' newton metres' }, svg);
      el('title', {}, g).textContent = F.name + ': ' + Math.round(Math.abs(c.torque)) + ' N·m (not to scale)';
      el('path', { d: 'M' + sx + ',' + sy + ' A' + R + ',' + R + ' 0 1 ' + (dir > 0 ? 1 : 0) + ' ' + ex + ',' + ey, fill: 'none', stroke: F.colour, 'stroke-width': 2.5 }, g);
      var tx = -Math.sin(p1) * dir, ty = Math.cos(p1) * dir;   // direction of travel at the end
      var nx = Math.cos(p1), ny = Math.sin(p1);
      el('path', { d: 'M' + (ex + tx * 7) + ',' + (ey + ty * 7) + ' L' + (ex + nx * 4.5) + ',' + (ey + ny * 4.5) + ' L' + (ex - nx * 4.5) + ',' + (ey - ny * 4.5) + ' Z', fill: F.colour }, g);
      svgText(svg, p[0], p[1] + R + 16, 'not to scale', { 'text-anchor': 'middle', 'font-size': 11 });
      el('circle', { cx: p[0], cy: p[1], r: R + 4, class: 'fx-hit' }, g);
      var hit = function () { showInfo('rudder'); };
      g.addEventListener('mouseenter', hit);
      g.addEventListener('focus', hit);
      g.addEventListener('click', hit);
    }

    function drawWind(svg, s) {
      var w = windVector(s), m = Math.hypot(w.x, w.y);
      var x = VIEW_W - 34, y = 34, L = 18;
      var ux = w.x / m, uy = -w.y / m;
      el('line', { x1: x - ux * L, y1: y - uy * L, x2: x + ux * L, y2: y + uy * L, stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, svg);
      el('path', { d: 'M' + (x + ux * L) + ',' + (y + uy * L) + ' l' + (-ux * 7 - uy * 4) + ',' + (-uy * 7 + ux * 4) + ' l' + (uy * 8) + ',' + (-ux * 8) + ' Z', fill: 'var(--fig-muted)' }, svg);
      svgText(svg, x, y + 34, 'wind ' + s.wind + ' m/s', { 'text-anchor': 'middle' });
    }

    vehSelect.addEventListener('change', function () { setVehicle(vehSelect.value); });
    setVehicle('car');
  }

  // `compute` is exposed for checking the numbers from a browser console.
  make.compute = compute;
  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets.forces = make;
})();
