// Vehicle anatomy: a top-view cutaway of one vehicle family, each modelled system drawn as a part.
// A click on a part, or on its name in the buttons under the drawing, names it, says what it does in one sentence, links to its page and
// lists its sloppyCAN signals. A row of icons switches between the family's layouts. SCHEMATIC,
// NOT TO SCALE: parts sit where they read clearly, not where the game's meshes put them.
// Embedded as <div class="widget an-widget" data-widget="anatomy" data-family="car"></div>.
// Every claim is cited beside its data as file and code name. Every signal the family carries in
// contract/carlito_contract.json (by name and direction) belongs to exactly one part.
// Drawing frame: the vehicle faces right (front at large x), its left side up.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var VIEW_BOX = '0 28 420 184'; // the drawing spans y 34..206; the margin above and below is cut

  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function rect(x, y, w, h, rx) { return ['rect', { x: x, y: y, width: w, height: h, rx: rx || 2 }]; }
  function circle(cx, cy, r) { return ['circle', { cx: cx, cy: cy, r: r }]; }
  function line(x1, y1, x2, y2) { return ['line', { x1: x1, y1: y1, x2: x2, y2: y2 }]; }
  function path(d) { return ['path', { d: d }]; }
  // A coil spring drawn along y from y0, 20 units long.
  function spring(x, y0) {
    return path('M' + x + ' ' + y0 + 'l4 2.5l-8 5l8 5l-8 5l4 2.5');
  }

  // ---- the car family -----------------------------------------------------------------------
  // Shared parts. text: one plain sentence; page: the guide page (#route) that says more;
  // send / receive: the signals the game sends to sloppyCAN (out) and reads from it (in).
  var CAR_PARTS = {
    engine: { name: 'Engine', page: 'engine', pageTitle: 'The engine',
      text: 'Burns petrol to turn the crankshaft; the pedal sets how much torque it makes.',
      send: ['rpm', 'speed_limit'] },
    // VehicleSpec.coupling default CONVERTER
    coupling: { name: 'Torque converter', page: 'coupling/the-torque-converter', pageTitle: 'Clutch and torque converter',
      text: 'A fluid coupling between the engine and the gearbox: it lets the engine idle while the car stands still, and makes the car creep forward.' },
    // VehicleSpec.gear_ratios (six), park_pawl_torque (sedan_spec.tres 3000)
    gearbox: { name: 'Gearbox', page: 'gearbox', pageTitle: 'Gearbox and shifting',
      text: 'A six-speed automatic that picks the gear for the speed and the pedal; in P its park pawl locks the wheels it drives.',
      send: ['gear'] },
    // GroundDriveSpec.diff_bias_front / diff_bias_rear default 1 (open)
    diffFront: { name: 'Front differential', page: 'differentials/the-open-differential', pageTitle: 'Differentials and four-wheel drive',
      text: 'Splits the drive between the two front wheels and lets them turn at different speeds in a corner.' },
    diffRear: { name: 'Rear differential', page: 'differentials/the-open-differential', pageTitle: 'Differentials and four-wheel drive',
      text: 'Splits the drive between the two rear wheels and lets them turn at different speeds in a corner.' },
    // suv_spec.tres centre_diff_bias 3
    diffCentre: { name: 'Centre differential', page: 'differentials/the-centre-differential', pageTitle: 'Differentials and four-wheel drive',
      text: 'A Torsen-type differential between the front and rear axles: it shares the drive and sends more of it to the axle that grips.' },
    tyres: { name: 'Tyres', page: 'slip', pageTitle: 'Slip and the grip curve',
      text: 'Each tyre grips by slipping a little against the ground; past the peak of its grip it slides.',
      send: ['slip', 'ground'] },
    // contract handbrake: the rear wheels' own hardware; brake_temp: hottest brake, heat model
    brakes: { name: 'Brakes', page: 'brakes', pageTitle: 'Brakes',
      text: 'A brake at each wheel turns speed into heat, and a hot brake stops less well; the handbrake works the rear ones.',
      send: ['brake_temp'] },
    // anti_roll_rate in every car spec; GroundDriveSpec spring_rate, damper_bump
    suspension: { name: 'Suspension', page: 'suspension', pageTitle: 'Suspension',
      text: 'A spring and a damper at each corner keep the tyres on the ground, and anti-roll bars limit the lean in a corner.' },
    // *_spec.tres ackermann 1.0, min_steer_frac, steer_falloff_speed
    steering: { name: 'Steering', page: 'steering', pageTitle: 'Steering and Ackermann',
      text: 'Turns the front wheels, the inner one more than the outer, and less far as the speed rises.',
      send: ['steer'] },
    // abs_equipped, tcs_equipped, esc_equipped true on the road cars
    aids: { name: 'ABS, traction and stability control', page: 'driver-aids', pageTitle: 'ABS, traction and stability control',
      text: 'ABS keeps a braked wheel from locking, traction control keeps a driven wheel from spinning, and stability control brakes one wheel to stop a skid.',
      receive: ['tcs_off', 'esc_off'] },
    tank: { name: 'Fuel tank', page: 'auxiliary/fuel', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Holds the fuel; the harder the engine works, the faster it empties.',
      send: ['fuel', 'fuel_rate'] },
    radiator: { name: 'Radiator', page: 'auxiliary/coolant', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Carries the engine\'s heat away into the air, through the coolant that flows in it.',
      send: ['coolant'] },
    // contract battery (out): alternator volts, drooping with the lamp load
    battery: { name: 'Battery and alternator', page: 'auxiliary/battery-and-alternator', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Power the car\'s electrics; the voltage sags a little as more lamps are switched on.',
      send: ['battery'] },
    sensors: { name: 'Position and motion sensors', page: 'position', pageTitle: 'Position, heading and distance',
      text: 'Report where the car is and which way it faces, its speed and distance, and how it turns, accelerates and hits things.',
      send: ['speed', 'kmh', 'yaw', 'accLong', 'accLat', 'impact', 'posX', 'posZ', 'heading', 'lat', 'lon', 'odo'] },
    // contract status: ignition, ground, moving, gear, handbrake, headlights, stability control
    dashboard: { name: 'Dashboard', page: 'auxiliary/warning-lamps', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Shows the gauges and the warning lamps.',
      send: ['status'], receive: ['checkEngine', 'battery'] },
    controls: { name: 'Driver\'s controls', page: 'controls', pageTitle: 'Controls and who drives',
      text: 'What the driver uses to operate the car (pedals, steering wheel, gear selector, key, handbrake, horn, etc.).',
      send: ['throttle'], receive: ['accel', 'brake', 'steer', 'gear', 'key', 'handbrake', 'horn'] },
    // controls.md Lamps and horn: sloppyCAN is the only authority on the lamps once connected
    lamps: { name: 'Lamps', page: 'controls/lamps-and-horn', pageTitle: 'Controls and who drives',
      text: 'Headlights, indicators and stop lamps, to see and to be seen.',
      receive: ['lights', 'turnL', 'turnR', 'brakeLamp'] },
    body: { name: 'Body', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'The air pushes on the body: drag grows quickly with speed, and a crosswind pushes the car sideways.',
      send: ['twd', 'tws'] },
    // race_spec.tres downforce_area 2.24
    wings: { name: 'Wings', page: 'resistance/downforce-on-racing-cars', pageTitle: 'Air and rolling resistance',
      text: 'Press the car onto the road harder as the speed rises, for more grip in fast corners.' }
  };

  // Each car part's photo (img/anatomy/, credited to its Wikimedia Commons file page) and English
  // Wikipedia article, shown in its card (GuideKit.card).
  function photo(src, file, author, licence) {
    return { src: 'img/anatomy/' + src, page: 'https://commons.wikimedia.org/wiki/File:' + file,
      author: author, licence: licence };
  }
  var CAR_MEDIA = {
    engine: { wiki: 'Petrol_engine', photo: photo('engine.jpg', 'BMW_Engine_M10.JPG', 'Buschtrommler', 'public domain') },
    coupling: { wiki: 'Torque_converter', photo: photo('torque-converter.jpg', 'Bauma_2007_ZF_Drehmomentwandler.jpg', 'Aconcagua', 'CC BY-SA 3.0') },
    gearbox: { wiki: 'Automatic_transmission', photo: photo('gearbox-auto.jpg', 'Automatic_transmission_cut.jpg', 'Silverxxx', 'CC BY-SA 3.0') },
    diffFront: { wiki: 'Differential_(mechanical_device)', photo: photo('differential.jpg', 'Differential_gear_001.JPG', 'Tennen-Gas', 'CC BY-SA 3.0') },
    diffRear: { wiki: 'Differential_(mechanical_device)', photo: photo('differential.jpg', 'Differential_gear_001.JPG', 'Tennen-Gas', 'CC BY-SA 3.0') },
    // a cutaway render of the Audi quattro centre differential, not a photo: no free photo of a Torsen unit
    diffCentre: { wiki: 'Torsen', photo: photo('torsen.jpg', 'Audi_quattro_Differential_Color.jpg', 'Stefanobiondo', 'CC BY-SA 4.0') },
    tyres: { wiki: 'Tire', photo: photo('tyre.jpg', 'Michelin_Tire_Tread_(3529289077).jpg', 'ryan harvey', 'CC BY-SA 2.0') },
    brakes: { wiki: 'Disc_brake', photo: photo('brakes.jpg', '2020_Chevrolet_Bolt_EV_front_disc_brake_1.jpg', '4300streetcar', 'CC BY 4.0') },
    suspension: { wiki: 'Car_suspension', photo: photo('suspension.jpg', 'Radius_rod_sway_bar.jpg', 'RB30DE', 'public domain') },
    steering: { wiki: 'Rack_and_pinion', photo: photo('steering.jpg', 'OpelGTsuspension.jpg', 'dave_7', 'CC BY-SA 2.0') },
    aids: { wiki: 'Anti-lock_braking_system', photo: photo('abs.jpg', 'ABS_HCU_April_2018.jpg', 'Samf4u', 'CC BY-SA 4.0') },
    tank: { wiki: 'Fuel_tank', photo: photo('fuel-tank.jpg', 'Fiat_128_fuel_tank_(15299168104).jpg', 'Riley from Christchurch, New Zealand', 'CC BY 2.0') },
    radiator: { wiki: 'Radiator_(engine_cooling)', photo: photo('radiator.jpg', 'Radiator_fans_installed.jpg', 'simonov', 'CC BY-SA 2.0') },
    battery: { wiki: 'Automotive_battery', photo: photo('battery.jpg', 'Car_battery_cross-section.jpeg', 'Ben Cossalter', 'CC BY-SA 3.0') },
    // a wheel-speed sensor: the GPS-antenna and inertial-unit photos found were poor
    sensors: { wiki: 'Wheel_speed_sensor', photo: photo('sensors.jpg', 'ABS_Sensor_GM_IMG_0557.JPG', 'Hans Haase', 'CC BY-SA 4.0') },
    dashboard: { wiki: 'Dashboard', photo: photo('dashboard.jpg', 'Audi_A3_instruments.JPG', 'RapidAssistant', 'CC BY-SA 4.0') },
    controls: { wiki: 'Car_controls' },
    lamps: { wiki: 'Headlamp', photo: photo('lamps.jpg', 'Scheinwerfer.jpg', 'Meierman2', 'CC BY-SA 3.0') },
    body: { wiki: 'Automotive_aerodynamics', photo: photo('body.jpg', 'Porsche_908_Fibreglass_Shell_RSideFront_PorscheM_9June2013_(15009563641).jpg', 'Valder137', 'CC BY 2.0') },
    wings: { wiki: 'Downforce', photo: photo('wings.jpg', 'Porsche_908_LH_Coupe_rear_wing_Porsche_Museum.jpg', 'Morio', 'CC BY-SA 3.0') }
  };
  for (var media in CAR_MEDIA) Object.assign(CAR_PARTS[media], CAR_MEDIA[media]);

  // Road-car geometry: front axle FA, rear axle RA.
  var FA = 300, RA = 110;
  function wheels() {
    var s = [];
    [FA, RA].forEach(function (ax) {
      s.push(rect(ax - 22, 40, 44, 18, 4), rect(ax - 22, 182, 44, 18, 4));
    });
    return s;
  }
  function brakes() {
    return [rect(FA - 7, 59, 14, 5, 1), rect(FA - 7, 176, 14, 5, 1),
      rect(RA - 7, 59, 14, 5, 1), rect(RA - 7, 176, 14, 5, 1)];
  }
  function springs(frontX, rearX) {
    return [spring(frontX, 66), spring(frontX, 154), spring(rearX, 66), spring(rearX, 154)];
  }
  function roadCar(o) {
    // o: { drive: 'front'|'rear'|'all' }
    var front = o.drive !== 'rear', rear = o.drive !== 'front';
    var parts = {
      body: [path('M40 50H380Q396 50 396 66V174Q396 190 380 190H40Q24 190 24 174V66Q24 50 40 50Z')],
      tank: [rect(156, 62, 42, 36, 4)],
      sensors: [circle(172, 164, 5), circle(172, 164, 1.5)],
      controls: [['ellipse', { cx: 236, cy: 86, rx: 3.5, ry: 12 }], circle(232, 120, 4.5)],
      dashboard: [rect(246, 62, 6, 116, 2)],
      gearbox: [rect(262, 98, 52, 44, 4)],
      steering: [line(320, 64, 320, 176), line(320, 64, FA + 8, 56), line(320, 176, FA + 8, 184)],
      coupling: [rect(326, 106, 12, 28, 3)],
      engine: [rect(342, 86, 36, 68, 5)],
      radiator: [rect(384, 70, 5, 100, 1)],
      aids: [rect(344, 60, 22, 16, 3)],
      battery: [rect(344, 164, 22, 16, 3)],
      lamps: [rect(386, 58, 6, 12, 1), rect(386, 170, 6, 12, 1), rect(27, 58, 5, 12, 1), rect(27, 170, 5, 12, 1)],
      tyres: wheels(),
      brakes: brakes(),
      suspension: springs(FA - 32, RA + 30)
    };
    // Drive lines: shafts carrying drive are drawn bold; an undriven axle thin.
    var drive = [line(262, 120, 378, 120)], dead = [];
    (front ? drive : dead).push(line(FA, 58, FA, 182));
    (rear ? drive : dead).push(line(RA, 58, RA, 182));
    if (front) {
      parts.diffFront = [circle(FA, 158, 9)];
      drive.push(line(FA, 142, FA, 149));
    }
    if (rear) {
      parts.diffRear = [circle(RA, 120, 10)];
      drive.push(line(262, 120, RA + 10, 120));
    }
    if (o.drive === 'all') {
      parts.diffCentre = [circle(200, 120, 9)];
      drive.push(['path', { d: 'M200 129V158H291' }]);
    }
    var labels = [['Engine', 360, 120, -90], ['Gearbox', 288, 120], ['Fuel', 177, 80]];
    return { parts: parts, drive: drive, dead: dead, labels: labels };
  }

  // The open-wheel racer: engine behind the driver, gearbox and diff in one case at the rear axle.
  function racer() {
    var body = 'M392 112V128L300 136L270 142L250 160H150L130 142L62 138L50 130V110L62 102L130 98L150 80H250L270 98L300 104Z';
    var parts = {
      body: [path(body)],
      wings: [rect(380, 34, 14, 172, 3), rect(30, 52, 13, 136, 3)],
      tank: [rect(206, 102, 34, 36, 4)],
      sensors: [circle(340, 120, 4.5), circle(340, 120, 1.5)],
      controls: [['ellipse', { cx: 276, cy: 120, rx: 3, ry: 9 }]],
      dashboard: [rect(284, 108, 5, 24, 1)],
      engine: [rect(150, 100, 50, 40, 5)],
      coupling: [rect(138, 106, 10, 28, 3)],
      gearbox: [rect(92, 104, 44, 32, 4)],
      diffRear: [circle(RA, 120, 9)],
      steering: [line(318, 64, 318, 176), line(318, 64, FA + 8, 56), line(318, 176, FA + 8, 184)],
      radiator: [rect(206, 84, 36, 10, 2), rect(206, 146, 36, 10, 2)],
      aids: [rect(160, 84, 28, 10, 2)],
      battery: [rect(160, 146, 28, 10, 2)],
      lamps: [rect(386, 114, 6, 12, 1), rect(52, 114, 6, 12, 1)],
      tyres: wheels(),
      brakes: brakes(),
      suspension: [line(FA, 58, FA - 6, 104), line(FA, 182, FA - 6, 136), line(RA, 58, 130, 98),
        line(RA, 182, 130, 142), spring(FA - 32, 74), spring(FA - 32, 146), spring(RA + 34, 74),
        spring(RA + 34, 146)]
    };
    return { parts: parts, drive: [line(RA, 58, RA, 182), line(RA, 120, 200, 120)],
      dead: [line(FA, 58, FA, 182)], labels: [['Engine', 175, 120], ['Fuel', 223, 120, -90]] };
  }

  // ---- the truck family ---------------------------------------------------------------------
  // The garbage truck, the fire truck and the two semi tractor units (TruckVehicle, SemiTractor).
  var TRUCK_PARTS = {
    // fuel_type 1 (DIESEL), pedal_map LINEAR (default), speed_limit_kmh in every truck spec;
    // contract engine_hours: accumulated while the key is at Ignition
    engine: { name: 'Engine', page: 'engine/limits-the-rev-limiter-and-the-speed-governor', pageTitle: 'The engine',
      text: 'A diesel that turns the crankshaft; a governor holds the truck to its top speed, and an hour meter counts its running time.',
      send: ['rpm', 'speed_limit', 'engine_load', 'engine_hours'] },
    // garbage-truck_spec.tres: coupling CONVERTER (VehicleSpec default)
    coupling: { name: 'Torque converter', page: 'coupling/the-torque-converter', pageTitle: 'Clutch and torque converter',
      text: 'A fluid coupling between the engine and the gearbox: it lets the engine idle while the truck stands still, and makes it creep forward.' },
    // garbage-truck_spec.tres gear_ratios (six), park_pawl_torque 0 (default); contract gear:
    // "the trucks park on their spring brakes"
    gearbox: { name: 'Gearbox', page: 'gearbox', pageTitle: 'Gearbox and shifting',
      text: 'A six-speed automatic that picks the gear for the speed and the load; it has no park position.',
      send: ['gear', 'gear_ratio'] },
    // retarder_equipped true, retarder_rating_nm in every truck spec; contract retarder: "No local key"
    retarder: { name: 'Retarder', page: 'brakes/the-retarder', pageTitle: 'Brakes',
      text: 'An extra brake inside the driveline that slows the drive shaft without heating the wheel brakes.',
      receive: ['retarder'], send: ['retarder_state'] },
    // TruckVehicle: drivetrain.accessory_torque = the body pump on the crank (RefuseBody.PUMP_KW);
    // pto_set_rpm = pto_mode_rpm 1300 when TruckTelemetry.pto_mode_engaged
    pto: { name: 'PTO', page: 'implements/on-the-trucks', pageTitle: 'Implements and the PTO',
      text: 'A power take-off that drives the refuse body\'s pump: each lift loads the engine, and with the truck parked the engine holds a set speed for it.',
      receive: ['pto'], send: ['pto_state'] },
    // diff_bias_rear 1 (default, open); driven_rear (default)
    diffRear: { name: 'Rear differential', page: 'differentials/the-open-differential', pageTitle: 'Differentials and four-wheel drive',
      text: 'Splits the drive between the two rear wheels, the only driven ones, and lets them turn at different speeds in a corner.' },
    tyres: { name: 'Tyres', page: 'slip', pageTitle: 'Slip and the grip curve',
      text: 'Each tyre grips by slipping a little against the ground; past the peak of its grip it slides.',
      send: ['slip', 'ground'] },
    // garbage-truck_spec.tres brake_fade_curve 3 (DRUM); handbrake_torque on the rears
    // (TruckVehicle: spring brakes are handbrake_torque through WheelDrive.spring_brake)
    brakes: { name: 'Brakes', page: 'brakes/heat-and-fade', pageTitle: 'Brakes',
      text: 'Drum brakes at each wheel turn speed into heat, and a hot brake stops less well; the parking brake is a spring brake on the rear wheels.',
      send: ['brake_temp'] },
    // TruckTelemetry.air_step, AIR_SPRING_BRAKE_BAR; Drivetrain.drive_inhibit
    airTanks: { name: 'Air tanks', page: 'brakes/air-and-spring-brakes', pageTitle: 'Brakes',
      text: 'Two tanks of compressed air, filled by the engine, work the brakes; if the air runs low, the spring brakes come on.',
      send: ['air_primary', 'air_secondary'] },
    // ackermann 1.0, min_steer_frac, steer_falloff_speed in every truck spec
    steering: { name: 'Steering', page: 'steering', pageTitle: 'Steering and Ackermann',
      text: 'Turns the front wheels, the inner one more than the outer, and less far as the speed rises.',
      send: ['steer'] },
    // spring_rate, anti_squat_slope (rigid trucks); anti_roll_rate 0 (default) on the rigid trucks;
    // TruckVehicle: axle_load = VehicleTelemetry.axle_load_kg(drive.rear_suspension_force())
    suspension: { name: 'Suspension', page: 'suspension', pageTitle: 'Suspension',
      text: 'Stiff springs and dampers at each corner carry the load; the force on the rear springs is read as the axle load.',
      send: ['axle_load'] },
    // abs_equipped, tcs_equipped, esc_equipped true and esc_roll_lift_g in every truck spec;
    // contract esc_off: "traction control is off with it"
    aids: { name: 'ABS, traction and stability control', page: 'driver-aids/roll-stability-on-trucks', pageTitle: 'ABS, traction and stability control',
      text: 'ABS keeps a braked wheel from locking, traction control keeps a driven wheel from spinning, and stability control brakes to stop a skid or a rollover.',
      receive: ['esc_off'] },
    tank: { name: 'Fuel tank', page: 'auxiliary/fuel', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Holds the diesel; the harder the engine works, the faster it empties.',
      send: ['fuel', 'fuel_rate'] },
    radiator: { name: 'Radiator', page: 'auxiliary/coolant', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Carries the engine\'s heat away into the air, through the coolant that flows in it.',
      send: ['coolant'] },
    battery: { name: 'Battery and alternator', page: 'auxiliary/battery-and-alternator', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Power the truck\'s electrics; the voltage sags a little as more lamps are switched on.',
      send: ['battery'] },
    sensors: { name: 'Position and motion sensors', page: 'position', pageTitle: 'Position, heading and distance',
      text: 'Report where the truck is and which way it faces, its speed and distance, and how it turns, accelerates and hits things.',
      send: ['speed', 'kmh', 'yaw', 'accLong', 'accLat', 'impact', 'posX', 'posZ', 'heading', 'lat', 'lon', 'odo'] },
    // dashboard.gd LAMP: red_stop RSL, amber_warn AWL, protect_lamp PROT, trailer_ebs_fault EBS,
    // trailer_abs_lamp TRLR ABS; contract: each "Mirrored VERBATIM ... sloppyCAN is the sole authority"
    dashboard: { name: 'Dashboard', page: 'auxiliary/warning-lamps', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Shows the gauges and the warning lamps, including the fault lamps of the truck\'s own network.',
      send: ['status'], receive: ['checkEngine', 'battery', 'red_stop', 'amber_warn', 'protect_lamp', 'trailer_ebs_fault', 'trailer_abs_lamp'] },
    controls: { name: 'Driver\'s controls', page: 'controls', pageTitle: 'Controls and who drives',
      text: 'What the driver uses to operate the truck (pedals, steering wheel, gear selector, key, parking brake, horn, etc.).',
      send: ['throttle'], receive: ['accel', 'brake', 'steer', 'gear', 'key', 'handbrake', 'horn'] },
    lamps: { name: 'Lamps', page: 'controls/lamps-and-horn', pageTitle: 'Controls and who drives',
      text: 'Headlights, indicators and stop lamps, to see and to be seen.',
      receive: ['lights', 'turnL', 'turnR', 'brakeLamp'] },
    body: { name: 'Body', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'The air pushes on the body: drag grows quickly with speed, and a crosswind pushes the truck sideways.',
      send: ['twd', 'tws'] },
    // RefuseBody: body_cmd Idle/Lift/Dump/Lower; is_inhibited: road speed over
    // WALK_PACE_MS, parking brake under PARK_BRAKE_MIN, or the body network down (PTO out)
    refuseArm: { name: 'Front-loading arm', page: 'implements/on-the-trucks', pageTitle: 'Implements and the PTO',
      text: 'Lifts a bin up over the cab and empties it into the hopper; it moves only with the truck parked and the PTO in.',
      receive: ['body_cmd'], send: ['body_state', 'body_pos'] },
    // RefuseBody HOPPER_PER_CYCLE 12.5, HOPPER_PAYLOAD_KG 5000 written into the chassis mass;
    // contract hopper_load: "Cleared on respawn"
    hopper: { name: 'Hopper', page: 'implements/on-the-trucks', pageTitle: 'Implements and the PTO',
      text: 'Holds the refuse: each emptied bin adds weight, which the axle load shows.',
      send: ['hopper_load'] },
    // contract body_bus, body_inhibit: CiA 422 body network, CiA 413 truck gateway; RefuseBody.bus_up
    gateway: { name: 'Body gateway', page: 'glossary/canopen', pageTitle: 'Glossary: CANopen',
      text: 'Joins the body\'s own network, CANopen, to the truck\'s J1939 network; it is up only with the PTO in, and it stops the arm unless the truck is parked.',
      send: ['body_bus', 'body_inhibit'] },
    // FifthWheel (a TowHost profile); KINGPIN_LOCAL
    fifthWheel: { name: 'Fifth wheel', page: 'towing/two-bodies-and-a-joint', pageTitle: 'Towing',
      text: 'The plate the trailer\'s kingpin locks into: the trailer rests on it and pivots about it.' },
    // SemiTractor.cycle_implement: box, tipper, tanker, flatbed, bobtail;
    // trailer_axle_load: VehicleTelemetry.axle_load_kg(trailer.bogie_suspension_force())
    trailer: { name: 'Semi-trailer', page: 'towing/the-trailers', pageTitle: 'Towing',
      text: 'A box, tipper, tanker or flatbed trailer, a second body joined to the truck at the fifth wheel.',
      send: ['trailer_axle_load'] },
    // trailers/*_spec.tres abs_equipped, trailer_roll_equipped; TowedBody.brake_applied,
    // abs_active, vdc_active
    trailerWheels: { name: 'Trailer wheels and brakes', page: 'towing/trailer-brakes', pageTitle: 'Towing',
      text: 'The trailer brakes itself on its own three axles, with its own ABS and roll control.',
      send: ['trailer_brake_applied', 'trailer_abs', 'trailer_vdc'] },
    // semi_spec.tres trailer_bus_equipped true; TruckTelemetry.ebs11_demand
    trailerLink: { name: 'Trailer link', page: 'towing/the-trailer-link', pageTitle: 'Towing',
      text: 'A data link in the trailer\'s connector: the truck sends the trailer its brake demand, and the trailer reports back.',
      send: ['trailer_connected', 'trailer_brake_demand'] }
  };
  // Photos and Wikipedia articles, as CAR_MEDIA; the semi's own (clutch, AMT, disc brakes) are in
  // its layout. Gaps (aids, radiator, battery, sensors, gateway) have a link or nothing.
  var TRUCK_MEDIA = {
    engine: { wiki: 'Diesel_engine', photo: photo('truck-engine.jpg', 'MAN_D2676_LF25_diesel_engine_for_trucks_353kW._Spielvogel_1.jpg', 'Spielvogel', 'CC0') },
    coupling: { wiki: 'Torque_converter', photo: photo('torque-converter.jpg', 'Bauma_2007_ZF_Drehmomentwandler.jpg', 'Aconcagua', 'CC BY-SA 3.0') },
    gearbox: { wiki: 'Automatic_transmission', photo: photo('truck-gearbox-auto.jpg', 'Allison_4000_6-speed_transmission.jpg', 'Spielvogel', 'CC BY-SA 4.0') },
    retarder: { wiki: 'Retarder_(mechanical_engineering)', photo: photo('truck-retarder.jpg', 'Aquatarder_Voith_SWR_2865.jpg', 'Spielvogel', 'CC BY-SA 4.0') },
    pto: { wiki: 'Power_take-off', photo: photo('truck-pto.jpg', 'PTO_gearbox.JPG', 'Panoha', 'CC BY-SA 3.0') },
    diffRear: { wiki: 'Differential_(mechanical_device)', photo: photo('truck-diff-rear.jpg', 'Rear_axles_tandem.jpg', 'Panoha', 'CC BY-SA 3.0') },
    tyres: { wiki: 'Tire', photo: photo('truck-diff-rear.jpg', 'Rear_axles_tandem.jpg', 'Panoha', 'CC BY-SA 3.0') },
    // a light truck's drum brake: no free photo of a heavy truck's was found
    brakes: { wiki: 'Drum_brake', photo: photo('truck-drum-brakes.jpg', 'Drum_brake.jpg', '-WesK-', 'CC BY-SA 3.0') },
    airTanks: { wiki: 'Air_brake_(road_vehicle)#Supply_system', photo: photo('truck-air-tanks.jpg', 'A_truck_chassis_section.jpg', 'Panoha', 'CC BY-SA 3.0') },
    steering: { wiki: 'Recirculating_ball' },
    suspension: { wiki: 'Leaf_spring', photo: photo('truck-suspension.jpg', 'Trunnion_001.JPG', 'Tennen-Gas', 'CC BY-SA 3.0') },
    aids: { wiki: 'Anti-lock_braking_system' },
    tank: { wiki: 'Fuel_tank', photo: photo('truck-fuel-tank.jpg', 'Peterbilt_Diesel_Fuel_Tank.jpg', 'Theodoros0', 'CC BY-SA 4.0') },
    radiator: { wiki: 'Radiator_(engine_cooling)' },
    battery: { wiki: 'Automotive_battery' },
    sensors: { wiki: 'Wheel_speed_sensor' },
    dashboard: { wiki: 'Dashboard#Electronic_instrument_cluster', photo: photo('truck-dashboard.jpg', '2010_Actros_3_Instrument_Cluster.jpg', 'Paulactros', 'CC BY-SA 3.0') },
    controls: { wiki: 'Car_controls' },
    lamps: { wiki: 'Headlamp', photo: photo('truck-lamps.jpg', 'FH_LED_lights.JPG', 'Panoha', 'CC BY-SA 3.0') },
    body: { wiki: 'Automotive_aerodynamics' },
    refuseArm: { wiki: 'Garbage_truck#Front_loaders', photo: photo('truck-refuse-arm.jpg', 'Scaniafrontloader.JPG', 'Gǝriffen (Commons user)', 'CC BY-SA 3.0') },
    // a side loader's body: the hopper, not the front loader's arm
    hopper: { wiki: 'Garbage_truck', photo: photo('truck-hopper.jpg', 'Recology_Lodal_Garbage_Truck_14425_in_San_Francisco.jpg', 'Dllu', 'CC BY-SA 4.0') },
    fifthWheel: { wiki: 'Fifth-wheel_coupling', photo: photo('truck-fifth-wheel.jpg', 'Saf_Holland_turntable,_fifth_wheel_01.jpg', 'Photohelp13', 'CC BY-SA 4.0') },
    trailer: { wiki: 'Semi-trailer', photo: photo('truck-trailer.jpg', 'Insulated_semi-trailer_-_rear.jpg', 'Eric Polk', 'CC BY-SA 4.0') },
    trailerWheels: { wiki: 'Semi-trailer', photo: photo('truck-trailer-wheels.jpg', 'Semi-trailer_Groenewegen,_twin_tires,_suspension_IMG_20211110_153847.jpg', 'Bertux', 'CC BY-SA 4.0') },
    // an air coupling (glad hand); the data plug is not shown
    trailerLink: { wiki: 'Air_brake_(road_vehicle)#Control_system', photo: photo('truck-trailer-link.jpg', 'Glad_Hand.jpg', 'phot0geek', 'CC BY-SA 2.0') }
  };
  for (var kmedia in TRUCK_MEDIA) Object.assign(TRUCK_PARTS[kmedia], TRUCK_MEDIA[kmedia]);

  // The rigid truck: the car's road geometry, with a cab ahead of a refuse body.
  function rigidTruck() {
    var parts = {
      body: [path('M228 50H380Q396 50 396 66V174Q396 190 380 190H228Z'), rect(24, 46, 200, 148, 6)],
      hopper: [rect(30, 52, 188, 136, 4)],
      refuseArm: [rect(214, 33, 192, 5, 2), rect(214, 202, 192, 5, 2), rect(401, 33, 5, 174, 2)],
      gateway: [rect(36, 160, 20, 16, 3)],
      tank: [rect(156, 62, 42, 36, 4)],
      airTanks: [rect(150, 140, 48, 9, 4), rect(150, 152, 48, 9, 4)],
      sensors: [circle(60, 120, 5), circle(60, 120, 1.5)],
      controls: [['ellipse', { cx: 238, cy: 86, rx: 3.5, ry: 12 }], circle(234, 120, 4.5)],
      dashboard: [rect(246, 62, 6, 116, 2)],
      gearbox: [rect(262, 98, 52, 44, 4)],
      retarder: [rect(196, 112, 14, 16, 3)],
      pto: [rect(284, 146, 16, 8, 2)],
      diffRear: [circle(RA, 120, 10)],
      steering: [line(320, 64, 320, 176), line(320, 64, FA + 8, 56), line(320, 176, FA + 8, 184)],
      coupling: [rect(326, 106, 12, 28, 3)],
      engine: [rect(342, 86, 36, 68, 5)],
      radiator: [rect(384, 70, 5, 100, 1)],
      aids: [rect(344, 60, 22, 16, 3)],
      battery: [rect(344, 164, 22, 16, 3)],
      lamps: [rect(386, 58, 6, 12, 1), rect(386, 170, 6, 12, 1), rect(27, 58, 5, 12, 1), rect(27, 170, 5, 12, 1)],
      tyres: wheels(),
      brakes: brakes(),
      suspension: springs(FA - 32, RA + 30)
    };
    return { parts: parts, drive: [line(262, 120, RA + 10, 120), line(RA, 58, RA, 182), line(262, 120, 342, 120)],
      dead: [line(FA, 58, FA, 182)], labels: [['Engine', 360, 120, -90], ['Gearbox', 288, 120], ['Hopper', 62, 84]] };
  }

  // The semi tractor unit under its trailer, about to scale: kingpin ahead of the drive axle.
  var SFA = 357, SRA = 215;
  function semi() {
    var w = [], b = [], tw = [];
    [SFA, SRA].forEach(function (ax) {
      w.push(rect(ax - 22, 40, 44, 18, 4), rect(ax - 22, 182, 44, 18, 4));
      b.push(rect(ax - 7, 59, 14, 5, 1), rect(ax - 7, 176, 14, 5, 1));
    });
    [49, 78, 107].forEach(function (ax) {
      tw.push(rect(ax - 12, 46, 24, 16, 3), rect(ax - 12, 178, 24, 16, 3));
    });
    var parts = {
      body: [path('M322 50H382Q396 50 396 64V176Q396 190 382 190H322V168H196V72H322Z')],
      trailer: [rect(20, 42, 270, 156, 4)],
      trailerWheels: tw,
      fifthWheel: [path('M' + (SRA + 4) + ' 104A18 18 0 1 1 ' + (SRA + 4) + ' 136')],
      tank: [rect(250, 146, 50, 20, 4)],
      airTanks: [rect(250, 76, 50, 9, 4), rect(250, 88, 50, 9, 4)],
      sensors: [circle(306, 156, 5), circle(306, 156, 1.5)],
      controls: [['ellipse', { cx: 368, cy: 76, rx: 3, ry: 9 }], circle(358, 77, 3.5)],
      dashboard: [rect(377, 66, 5, 108, 2)],
      gearbox: [rect(272, 104, 32, 32, 4)],
      retarder: [rect(256, 112, 12, 16, 3)],
      pto: [rect(276, 138, 14, 7, 2)],
      diffRear: [circle(SRA, 120, 9)],
      steering: [line(322, 64, 322, 176), line(322, 64, SFA - 8, 56), line(322, 176, SFA - 8, 184)],
      coupling: [rect(308, 106, 10, 28, 3)],
      engine: [rect(338, 90, 34, 60, 5)],
      radiator: [rect(385, 72, 5, 96, 1)],
      aids: [rect(338, 154, 18, 13, 3)],
      battery: [rect(357, 154, 18, 13, 3)],
      trailerLink: [path('M322 164C312 176 300 180 290 180')],
      lamps: [rect(390, 56, 5, 12, 1), rect(390, 172, 5, 12, 1), rect(22, 48, 5, 12, 1), rect(22, 180, 5, 12, 1)],
      tyres: w,
      brakes: b,
      suspension: [spring(SFA - 26, 66), spring(SFA - 26, 154), spring(SRA - 30, 66), spring(SRA - 30, 154)]
    };
    return { parts: parts, drive: [line(SRA, 58, SRA, 182), line(SRA + 9, 120, 338, 120)],
      dead: [line(SFA, 58, SFA, 182)], labels: [['Engine', 355, 120, -90], ['Trailer', 150, 120]] };
  }

  // ---- the tractor family -------------------------------------------------------------------
  // tractor-kenney (powershift) and tractor-cvt, one body (gen_kenney_vehicles.gd TRACTOR_BASE).
  var TRACTOR_PARTS = {
    // pedal_map 2 (ALL_SPEED), governor_droop 0.07, fuel_type 1 (DIESEL)
    engine: { name: 'Engine', page: 'engine/the-tractors-governor', pageTitle: 'The engine',
      text: 'A diesel with an all-speed governor: the pedal or the hand throttle sets an engine speed, and the governor holds it under load.',
      send: ['rpm', 'speed_limit', 'engine_load', 'engine_hours'] },
    // tractor-kenney_spec.tres coupling 1 (CLUTCH); the CVT has no launch clutch (Drivetrain, power-split CVT)
    coupling: { name: 'Clutch', page: 'coupling/the-friction-clutch', pageTitle: 'Clutch and torque converter',
      text: 'A friction clutch between the engine and the gearbox, worked by the tractor itself: it slips to pull away, then locks shut.' },
    // tractor-kenney_spec.tres gear_ratios (sixteen), park_pawl_torque 33542
    gearbox: { name: 'Powershift gearbox', page: 'gearbox', pageTitle: 'Gearbox and shifting',
      text: 'A sixteen-speed powershift that picks the gear and changes it under load; in P its park pawl holds the driven wheels.',
      send: ['gear', 'gear_ratio'] },
    // rear_diff_lockable true; diff_bias_rear 1 (open)
    diffRear: { name: 'Rear differential and lock', page: 'differentials/the-tractors-diff-lock-and-front-wheel-drive', pageTitle: 'Differentials and four-wheel drive',
      text: 'Splits the drive between the rear wheels; locked, it turns them as one, so the wheel that grips does the pulling.',
      receive: ['diff_lock'], send: ['diff_lock_state'] },
    // front_axle_engageable, centre_diff_rigid, brake_engages_front_axle true
    frontDrive: { name: 'Front-wheel drive (MFWD)', page: 'differentials/the-tractors-diff-lock-and-front-wheel-drive', pageTitle: 'Differentials and four-wheel drive',
      text: 'A clutch that drives the front axle too: on request, and by itself whenever the brake is pressed.',
      receive: ['fwd_drive'], send: ['fwd_drive_state'] },
    // tyres/ag_lug.tres: Mud 1.25, Field 1.2, Grass 1.15, Sand 1.1
    tyres: { name: 'Lug tyres', page: 'surfaces/tyre-classes', pageTitle: 'Ground and tyre types',
      text: 'Big tyres with deep lugs that grip best in mud and fields; each grips by slipping a little, and past the peak of its grip it slides.',
      send: ['slip', 'ground'] },
    // TRACTOR_BASE: wet multi-disc brakes on the rear axle, brake_fade_curve_rear 4 (WET), the
    // parking brake on the rear axle
    brakes: { name: 'Brakes', page: 'brakes/heat-and-fade', pageTitle: 'Brakes',
      text: 'Wet disc brakes in the rear axle\'s oil, which fade when the oil gets hot; the parking brake works the rear axle too.',
      send: ['brake_temp'] },
    // steer_speed 0.75, ackermann 1.0; WheelDrive.steer_angle_from_curvature
    steering: { name: 'Steering', page: 'steering/auto-steer-on-the-tractor', pageTitle: 'Steering and Ackermann',
      text: 'Turns the front wheels slowly, the inner one more than the outer; a guidance computer can steer it along a curve (auto-steer).',
      receive: ['guidance_curvature'], send: ['steer'] },
    // TRACTOR_BASE: the "suspension" is the tyres; front_axle_swing_deg 10; TractorTelemetry axle_load
    suspension: { name: 'Swinging front axle', page: 'suspension/the-tractor-tyres-as-springs-and-a-swinging-axle', pageTitle: 'Suspension',
      text: 'No springs: the tyres are the springs, the front axle swings on a pivot, and the force on the rear axle is read as its load.',
      send: ['axle_load'] },
    tank: { name: 'Fuel tank', page: 'auxiliary/fuel', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Holds the diesel; the harder the engine works, the faster it empties.',
      send: ['fuel', 'fuel_rate'] },
    radiator: { name: 'Radiator', page: 'auxiliary/coolant', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Carries the engine\'s heat away into the air, through the coolant that flows in it.',
      send: ['coolant'] },
    battery: { name: 'Battery and alternator', page: 'auxiliary/battery-and-alternator', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Power the tractor\'s electrics; the voltage sags a little as more lamps are switched on.',
      send: ['battery'] },
    sensors: { name: 'Position and motion sensors', page: 'position', pageTitle: 'Position, heading and distance',
      text: 'Report where the tractor is and which way it faces, its speed and distance, and how it turns, accelerates and hits things.',
      send: ['speed', 'kmh', 'yaw', 'accLong', 'accLat', 'impact', 'posX', 'posZ', 'heading', 'lat', 'lon', 'odo'] },
    // contract wheel_speed (rear axle spin), ground_speed ("radar"), wheel_slip
    radar: { name: 'Speed sensors', page: 'glossary/wheel-slip', pageTitle: 'Glossary: wheel slip',
      text: 'A radar measures the true speed over the ground and the rear axle\'s spin gives the wheel speed; the gap between them is the wheel slip.',
      send: ['wheel_speed', 'ground_speed', 'wheel_slip'] },
    dashboard: { name: 'Dashboard', page: 'auxiliary/warning-lamps', pageTitle: 'Fuel, coolant, battery and air',
      text: 'Shows the gauges and the warning lamps.',
      send: ['status'], receive: ['checkEngine', 'battery'] },
    controls: { name: 'Driver\'s controls', page: 'controls', pageTitle: 'Controls and who drives',
      text: 'What the driver uses to operate the tractor (pedals, hand throttle, steering wheel, gear selector, key, parking brake, horn, etc.).',
      send: ['throttle'], receive: ['accel', 'brake', 'steer', 'gear', 'key', 'handbrake', 'horn', 'hand_throttle'] },
    lamps: { name: 'Lamps', page: 'controls/lamps-and-horn', pageTitle: 'Controls and who drives',
      text: 'Headlights, indicators and stop lamps, to see and to be seen.',
      receive: ['lights', 'turnL', 'turnR', 'brakeLamp'] },
    body: { name: 'Body', page: 'resistance', pageTitle: 'Air and rolling resistance',
      text: 'The air pushes on the body: drag grows quickly with speed, and a crosswind pushes the tractor sideways.',
      send: ['twd', 'tws'] },
    // three_point_hitch.gd, hitch_linkage.gd; TractorVehicle._apply_draft
    hitch: { name: 'Three-point hitch', page: 'implements/the-three-point-hitch', pageTitle: 'Implements and the PTO',
      text: 'Two lower arms and a top link carry a tool on the back and raise or lower it; a tool working the soil pulls back on them.',
      receive: ['hitch_pos'], send: ['hitch_pos_actual', 'draft_force'] },
    pto: { name: 'PTO', page: 'implements/the-pto', pageTitle: 'Implements and the PTO',
      text: 'A shaft at the back, turned by the engine at a chosen speed, that drives a tool\'s moving parts.',
      receive: ['pto', 'pto_mode'], send: ['pto_state', 'pto_rpm'] },
    // ThreePointHitch.set_scv, Drawbar.set_scv
    scv: { name: 'Hydraulic remote', page: 'implements/the-hydraulic-remote', pageTitle: 'Implements and the PTO',
      text: 'An oil supply that works a ram on the tool: the spreader\'s gate, or the tipper trailer\'s body.',
      receive: ['scv_flow'] },
    // implement_base.gd: attaching is the address claim
    isobus: { name: 'Implement bus (ISOBUS)', page: 'implements/the-implement-bus', pageTitle: 'Implements and the PTO',
      text: 'A data link over which a tool tells the tractor that it is attached and what kind of tool it is.',
      send: ['implement_connected', 'implement_type'] },
    // src/vehicles/tractor/drawbar.gd (a TowHost profile); ImplementCatalog.TOWED farm_tipper
    drawbar: { name: 'Drawbar', page: 'towing/two-bodies-and-a-joint', pageTitle: 'Towing',
      text: 'A pin at the back that pulls a trailer, the farm tipper.' }
  };
  // Photos and Wikipedia articles, as CAR_MEDIA. Commons has few free photos of modern tractor
  // parts: several are older tractors, and the gaps (clutch, gearbox, front drive, brakes, tank,
  // radiator, battery, sensors, radar) have a link only.
  var TRACTOR_MEDIA = {
    engine: { wiki: 'Diesel_engine', photo: photo('tractor-engine.jpg', 'AGCO_Sisu_Power_49_AWI_diesel_engine_cutaway.JPG', 'Tommi Nummelin', 'CC BY-SA 3.0') },
    coupling: { wiki: 'Clutch#Wet_clutch' },
    gearbox: { wiki: 'Tractor#Transmission' },
    diffRear: { wiki: 'Locking_differential', photo: photo('tractor-diff-lock.png', 'Differential_lock.png', 'Jemand an Tastatur', 'CC BY-SA 4.0') },
    frontDrive: { wiki: 'Four-wheel_drive' },
    tyres: { photo: photo('tractor-tyres.jpg', 'Front_wheel_of_a_tractor.JPG', 'High Contrast', 'CC BY 3.0 de') },
    brakes: { wiki: 'Disc_brake' },
    steering: { wiki: 'Power_steering#Hydraulic_systems', photo: photo('tractor-steering.jpg', 'Vorderachse_eine_Traktors_älterer_Bauart.JPG', 'High Contrast', 'CC BY 3.0 de') },
    suspension: { photo: photo('tractor-suspension.jpg', 'Swing_axle_of_a_McCormick_Tractor.jpg', 'HobbyAstronaut', 'CC0') },
    tank: { wiki: 'Fuel_tank' },
    radiator: { wiki: 'Radiator' },
    battery: { wiki: 'Automotive_battery' },
    sensors: { wiki: 'Precision_agriculture' },
    dashboard: { wiki: 'Dashboard', photo: photo('tractor-dashboard.jpg', 'Fendt_Farmer_2_Armaturenbrett.jpg', 'KRafi08', 'public domain') },
    controls: { wiki: 'Tractor#Levers_and_switches' },
    lamps: { wiki: 'Headlamp', photo: photo('tractor-lamps.jpg', 'Close-up_view_of_an_old_tractor\'s_headlight_surrounded_by_rural_greenery.jpg', 'Shixart1985', 'CC BY 2.0') },
    body: { wiki: 'Tractor', photo: photo('tractor-body.jpg', 'Claas_Axion_810.jpg', 'Daniel Brockpähler', 'CC BY-SA 3.0') },
    hitch: { wiki: 'Three-point_hitch', photo: photo('tractor-hitch.jpg', 'Three-point_linkage_of_a_Kubota_tractor.jpg', 'This user loves Krittaya.', 'public domain') },
    pto: { wiki: 'Power_take-off', photo: photo('tractor-pto.jpg', 'Zapfwelle_eines_Traktors_-_power_take-off_of_a_tractor.jpg', 'bdk', 'CC BY-SA 3.0') },
    // a labelled photo of a tractor's rear: the hydraulic outlets are item 7
    scv: { wiki: 'Tractor#Power_take-off_systems_and_hydraulics', photo: photo('tractor-scv.jpg', 'A_Tractor\'s_rear_1.jpg', 'Sam Craig (derivative work: Jd6420)', 'CC BY-SA 2.0') },
    isobus: { wiki: 'ISO_11783', photo: photo('tractor-isobus.jpg', 'CCI200_Terminal.jpg', 'Competence Center ISOBUS e.V.', 'CC BY-SA 3.0 de') },
    drawbar: { wiki: 'Tractor#Drawbars', photo: photo('tractor-drawbar.jpg', 'John_Deere_3050,_three-point_linkage,_PTO_and_swinging_drawbar.jpg', 'Peter Mooney', 'CC BY-SA 2.0') }
  };
  for (var tmedia in TRACTOR_MEDIA) Object.assign(TRACTOR_PARTS[tmedia], TRACTOR_MEDIA[tmedia]);

  // The farm tractor: big rear wheels under the cab, small fronts under the bonnet.
  var TFA = 330, TRA = 150;
  function farmTractor(o) {
    // o: { cvt: true } leaves out the clutch
    var parts = {
      body: [path('M250 92H384Q392 92 392 100V140Q392 148 384 148H250Z'), rect(112, 70, 138, 100, 6)],
      tank: [rect(254, 70, 40, 18, 4)],
      sensors: [circle(170, 86, 5), circle(170, 86, 1.5)],
      radar: [rect(162, 150, 18, 10, 2)],
      dashboard: [rect(240, 78, 5, 84, 2)],
      controls: [['ellipse', { cx: 230, cy: 88, rx: 3.5, ry: 10 }], circle(226, 152, 4)],
      gearbox: [rect(196, 100, 82, 40, 5)],
      diffRear: [circle(TRA, 120, 11)],
      frontDrive: [rect(258, 146, 12, 12, 2), circle(TFA, 158, 8)],
      steering: [line(352, 80, 352, 160), line(352, 80, TFA + 10, 72), line(352, 160, TFA + 10, 168)],
      engine: [rect(300, 98, 64, 44, 5)],
      radiator: [rect(372, 96, 5, 48, 1)],
      battery: [rect(272, 164, 22, 12, 3)],
      scv: [circle(124, 86, 3.5), circle(134, 86, 3.5)],
      isobus: [rect(120, 148, 12, 10, 2)],
      hitch: [line(112, 98, 44, 88), line(112, 142, 44, 152), line(112, 108, 52, 108)],
      pto: [rect(64, 116, 48, 7, 2)],
      drawbar: [rect(56, 130, 56, 6, 2)],
      lamps: [rect(386, 98, 5, 10, 1), rect(386, 132, 5, 10, 1), rect(114, 72, 5, 10, 1), rect(114, 158, 5, 10, 1)],
      suspension: [circle(TFA, 120, 5)],
      tyres: [rect(TRA - 54, 30, 108, 32, 8), rect(TRA - 54, 178, 108, 32, 8),
        rect(TFA - 34, 52, 68, 22, 6), rect(TFA - 34, 166, 68, 22, 6)],
      brakes: [rect(TRA - 5, 72, 10, 14, 1), rect(TRA - 5, 154, 10, 14, 1)]
    };
    if (!o.cvt) parts.coupling = [rect(284, 106, 10, 28, 3)];
    return { parts: parts, drive: [line(TRA, 62, TRA, 178), line(TRA + 11, 120, 300, 120)],
      dead: [line(TFA, 74, TFA, 166), path('M264 158H322')],
      labels: [['Engine', 314, 120, -90], ['Gearbox', 237, 120]] };
  }

  var FAMILIES = {
    tractor: {
      parts: TRACTOR_PARTS,
      layouts: [
        // tractor-kenney_spec.tres coupling 1, sixteen gear_ratios, hill_hold 2 (STANDSTILL)
        { id: 'tractor-kenney', icon: 'tractor', name: 'The powershift tractor', draw: function () { return farmTractor({}); },
          parts: {
            brakes: { text: 'Wet disc brakes in the rear axle\'s oil, which fade when the oil gets hot.' }
          } },
        // tractor-cvt_spec.tres cvt_range_tops (four ranges), gear_ratios empty, hill_hold 0;
        // Drivetrain.standstill_hold (active standstill)
        { id: 'tractor-cvt', icon: 'tractor', name: 'The CVT tractor', draw: function () { return farmTractor({ cvt: true }); },
          parts: {
            gearbox: { name: 'Stepless gearbox (CVT)', page: 'gearbox/the-stepless-gearbox',
              text: 'Moves its ratio smoothly to give the road speed the pedal asks for, and holds the tractor still at a ratio of zero.',
              // a rendering of the Fendt Vario, not a photo
              wiki: 'Continuously_variable_transmission#Hydrostatic/hydraulic',
              photo: photo('tractor-gearbox-cvt.png', 'Internal_view_of_Vario_Transmission.png', 'AGCO Corporation - Fendt Marketing Team', 'CC BY 2.5') }
          } }
      ]
    },
    truck: {
      parts: TRUCK_PARTS,
      layouts: [
        // garbage-truck_spec.tres; TruckVehicle._find_rig: the refuse body is its `arm` mesh
        { id: 'garbage-truck', icon: 'truck', name: 'The rigid truck: the garbage truck', draw: rigidTruck },
        // semi_spec.tres coupling 1 (CLUTCH), shift_cut_s (AMT), twelve gear_ratios,
        // brake_fade_curve 1 (PAD), anti_roll_rate 480000, trailer_bus_equipped true
        { id: 'semi', icon: 'semi', name: 'The semi and its trailer', draw: semi,
          parts: {
            coupling: { name: 'Clutch', page: 'coupling/the-friction-clutch',
              text: 'A friction clutch between the engine and the gearbox, worked by the truck itself: it slips to pull away, then locks shut.',
              wiki: 'Clutch', photo: photo('truck-clutch.jpg', 'Pull_type_clutch.jpg', 'Panoha', 'CC BY-SA 3.0') },
            // the I-Shift's gear-change unit, not the whole gearbox
            gearbox: { text: 'A twelve-speed automated manual gearbox: it picks and changes the gear itself, and has no park position.',
              wiki: 'Automated_manual_transmission', photo: photo('truck-gearbox-amt.jpg', 'I_shift_gear_change_unit.jpg', 'Panoha', 'CC BY-SA 3.0') },
            pto: { text: 'A power take-off: it drives the pump of a tipper trailer, which raises its body.' },
            brakes: { text: 'Disc brakes at each wheel turn speed into heat, and a hot brake stops less well; the parking brake is a spring brake on the rear wheels.',
              wiki: 'Air_brake_(road_vehicle)', photo: photo('truck-disc-brakes.jpg', 'Air_disc_brake.jpg', 'Panoha', 'CC BY-SA 3.0') },
            suspension: { text: 'Stiff springs and dampers at each corner, and anti-roll bars sized for a trailer; the force on the rear springs is read as the axle load.' }
          } }
      ]
    },
    car: {
      parts: CAR_PARTS,
      layouts: [
        // sedan_spec.tres driven_front true, driven_rear false
        { id: 'sedan', icon: 'car', name: 'Front-wheel drive: the sedan', draw: function () { return roadCar({ drive: 'front' }); } },
        // sedan-sports_spec.tres: GroundDriveSpec default driven_rear
        { id: 'sedan-sports', icon: 'sports', name: 'Rear-wheel drive: the sedan-sports', draw: function () { return roadCar({ drive: 'rear' }); } },
        // suv_spec.tres driven_front true, centre_diff_bias 3
        { id: 'suv', icon: 'suv', name: 'All-wheel drive: the suv', draw: function () { return roadCar({ drive: 'all' }); } },
        // race_spec.tres coupling 1 (CLUTCH), abs/esc_equipped false, tcs_equipped true,
        // park_pawl_torque 0 (default), diff_bias_rear 2.5, downforce_area 2.24
        { id: 'race', icon: 'race', name: 'The racing car', draw: racer,
          parts: {
            coupling: { name: 'Clutch', page: 'coupling/the-friction-clutch',
              text: 'A friction clutch between the engine and the gearbox: it slips to pull away, then locks shut.',
              wiki: 'Clutch', photo: photo('clutch.jpg', 'Zweimassenschwungrad_und_kupplung_aufgeschnitten.jpg', 'Cschirp', 'CC BY-SA 3.0') },
            // no free photo of a sequential gearbox was found
            gearbox: { text: 'A six-speed sequential gearbox: each change is a short ignition cut, and there is no park position.',
              wiki: 'Sequential_manual_transmission', photo: null },
            diffRear: { name: 'Limited-slip differential', page: 'differentials/limited-slip-and-torsen-type-differentials',
              text: 'Splits the drive between the rear wheels like an open differential, but sends more of it to the wheel that grips.',
              wiki: 'Limited-slip_differential', photo: photo('lsd.jpg', 'Limited_slip_diff_cone.jpg', 'RB30DE', 'CC BY-SA 3.0') },
            tyres: { name: 'Slick tyres', text: 'Racing tyres with no tread; each grips by slipping a little against the ground, and past the peak of its grip it slides.',
              wiki: 'Racing_slick', photo: photo('slick.jpg', 'F1_Slick_Tires.jpg', 'vtornet', 'CC BY 2.0') },
            aids: { name: 'Traction control', text: 'Keeps a driven wheel from spinning; this car has no ABS and no stability control.',
              receive: ['tcs_off'], wiki: 'Traction_control_system', photo: null }
          } }
      ]
    }
  };

  // ---- the widget ---------------------------------------------------------------------------
  // Parts drawn in this order, so small ones sit on top of large ones.
  // A large part's hit area covers what lies under it, so the large ones come first.
  var ORDER = ['body', 'trailer', 'hopper', 'wings', 'tank', 'fifthWheel', 'airTanks', 'sensors',
    'radar', 'dashboard', 'controls', 'gearbox', 'retarder', 'pto', 'diffRear', 'diffCentre',
    'diffFront', 'frontDrive', 'steering', 'coupling', 'engine', 'radiator', 'aids', 'battery',
    'gateway', 'scv', 'isobus', 'hitch', 'drawbar', 'refuseArm', 'trailerLink', 'lamps',
    'suspension', 'tyres', 'trailerWheels', 'brakes'];
  var CLS = { body: 'an-body', trailer: 'an-body', wings: 'an-wing', steering: 'an-link',
    suspension: 'an-link', fifthWheel: 'an-link', trailerLink: 'an-link', hitch: 'an-link',
    tyres: 'an-tyre', trailerWheels: 'an-tyre', brakes: 'an-brake', lamps: 'an-lamp',
    diffFront: 'an-diff', diffRear: 'an-diff', diffCentre: 'an-diff', frontDrive: 'an-diff' };
  // The buttons under the drawing, in reading order: the drive path from the engine to the
  // ground first, then what controls it, then the systems around it.
  var CHIPS = ['engine', 'coupling', 'gearbox', 'retarder', 'pto', 'diffCentre', 'diffFront',
    'frontDrive', 'diffRear', 'tyres', 'brakes', 'airTanks', 'steering', 'suspension', 'aids',
    'tank', 'radiator', 'battery', 'sensors', 'radar', 'dashboard', 'controls', 'lamps', 'body',
    'wings', 'hitch', 'drawbar', 'scv', 'isobus', 'refuseArm', 'hopper', 'gateway', 'fifthWheel',
    'trailer', 'trailerWheels', 'trailerLink'];

  function sigList(names) {
    return names.map(function (n) { return '<code>' + n + '</code>'; }).join(', ');
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets.anatomy = function (root) {
    var fam = FAMILIES[root.getAttribute('data-family')];
    if (!fam) return;
    var current = fam.layouts[0], selected = null, groups = {};

    var pickerHost = document.createElement('div');
    pickerHost.className = 'an-pick';
    root.appendChild(pickerHost);
    var picker = GuideKit.vehiclePicker(pickerHost, fam.layouts, current.id, function (id) {
      fam.layouts.forEach(function (L) { if (L.id === id) current = L; });
      draw();
    });
    var caption = document.createElement('p');
    caption.className = 'an-layout';
    pickerHost.appendChild(caption); // beside the icons
    var svg = el('svg', { viewBox: VIEW_BOX, role: 'img' }, root);
    var chipRow = document.createElement('div');
    chipRow.className = 'an-chips';
    chipRow.setAttribute('role', 'group');
    chipRow.setAttribute('aria-label', 'Parts');
    root.appendChild(chipRow);
    var chips = {};
    var info = document.createElement('div');
    info.className = 'an-info';
    info.setAttribute('aria-live', 'polite');
    root.appendChild(info);

    function partOf(id) {
      var P = Object.assign({}, fam.parts[id], (current.parts || {})[id] || {});
      return P;
    }
    function showInfo(id) {
      var P = partOf(id);
      var s = [];
      if (P.send) s.push('the simulator sends ' + sigList(P.send));
      if (P.receive) s.push('sloppyCAN sends ' + sigList(P.receive));
      GuideKit.card(info, { name: P.name, text: P.text, page: P.page, pageTitle: P.pageTitle, wiki: P.wiki,
        photo: P.photo, sig: s.length ? 'In sloppyCAN: ' + s.join('; ') + '.' : '' });
    }
    function select(id) {
      selected = id;
      for (var k in groups) groups[k].classList.toggle('an-on', k === id);
      for (var c in chips) chips[c].setAttribute('aria-pressed', c === id ? 'true' : 'false');
      showInfo(id);
    }
    function hover(id, on) { if (groups[id]) groups[id].classList.toggle('an-hover', on); }
    function addShapes(parent, shapes, cls) {
      shapes.forEach(function (s) {
        var e = el(s[0], s[1], parent);
        if (cls) e.setAttribute('class', cls);
      });
    }

    function draw() {
      caption.textContent = current.name;
      svg.setAttribute('aria-label', current.name + ', seen from above, front to the right');
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      groups = {};
      var D = current.draw();
      var shafts = el('g', {}, null);
      addShapes(shafts, D.dead, 'an-dead');
      addShapes(shafts, D.drive, 'an-drive');
      ORDER.forEach(function (id) {
        if (!D.parts[id]) return;
        if (id === 'tank') svg.appendChild(shafts); // shafts run under the boxes, over the body
        var P = partOf(id);
        // Not focusable: the buttons under the drawing are the keyboard's way in.
        var g = el('g', { 'class': 'an-part ' + (CLS[id] || 'an-box') }, svg);
        addShapes(g, D.parts[id]);
        // A wider, invisible copy of each shape is the click target.
        D.parts[id].forEach(function (s) {
          var h = el(s[0], s[1], g);
          h.setAttribute('class', 'an-hit');
        });
        var title = el('title', {}, g);
        title.textContent = P.name;
        g.addEventListener('click', function () { select(id); });
        groups[id] = g;
      });
      (D.labels || []).forEach(function (L) {
        var t = el('text', { x: L[1], y: L[2], 'class': 'an-label', 'text-anchor': 'middle',
          'dominant-baseline': 'middle' }, svg);
        if (L[3]) t.setAttribute('transform', 'rotate(' + L[3] + ' ' + L[1] + ' ' + L[2] + ')');
        t.textContent = L[0];
      });
      while (chipRow.firstChild) chipRow.removeChild(chipRow.firstChild);
      chips = {};
      CHIPS.forEach(function (id) {
        if (!D.parts[id]) return;
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'an-chip';
        b.textContent = partOf(id).name;
        b.setAttribute('aria-pressed', 'false');
        b.addEventListener('click', function () { select(id); });
        b.addEventListener('mouseenter', function () { hover(id, true); });
        b.addEventListener('mouseleave', function () { hover(id, false); });
        b.addEventListener('focus', function () { hover(id, true); });
        b.addEventListener('blur', function () { hover(id, false); });
        chipRow.appendChild(b);
        chips[id] = b;
      });
      if (selected && groups[selected]) select(selected);
      else {
        selected = null;
        info.classList.remove('w-card');
        info.innerHTML = 'Click a part, in the drawing or by its name, to read what it is. The bold line carries the engine\'s drive to the wheels.';
      }
    }
    picker.set(current.id);
    draw();
  };
})();
