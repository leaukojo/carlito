// A vehicle's controls: the driver's view of the wheel, pedals, levers, key and switches, for the
// car, the truck or the tractor. A click on a control, or on its name in the buttons under the
// drawing, says what it does in a real vehicle, links to its guide page and Wikipedia, shows a
// photo and names its sloppyCAN signals. The car's AUTO and MANUAL switch between an automatic
// (two pedals, P R N D) and a manual (three pedals, a gated lever), as the GARAGE's GEARBOX row
// does. SCHEMATIC: a left-hand-drive cab.
// Embedded as <div class="widget an-widget" data-widget="cockpit" data-family="car"></div>
// (no data-family: the car); styled by the anatomy widget's an-* classes. Each claim is cited
// beside its data.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';

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
  // A thick stroke, set inline so the an-* classes' width does not thin it.
  function thick(s, w) { s[1].style = 'stroke-width:' + w; return s; }
  // A photo in img/cockpit/, credited to its Wikimedia Commons file page (file: its name there).
  function photo(src, file, author, licence) {
    return { src: 'img/cockpit/' + src, page: 'https://commons.wikimedia.org/wiki/File:' + file,
      author: author, licence: licence };
  }
  // Scenery, not clickable.
  function panel(svg, d) {
    el('path', { d: d, fill: 'var(--fig-grid)', 'fill-opacity': 0.5, stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, svg);
  }
  function floor(svg, x2) {
    el('line', { x1: 8, y1: 226, x2: x2, y2: 226, stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, svg);
  }
  function gauges(svg, xs, y, r) {
    xs.forEach(function (x) {
      el('circle', { cx: x, cy: y, r: r, fill: 'var(--fig-fill)', stroke: 'var(--fig-muted)' }, svg);
    });
  }

  var CONTROLS_PAGE = 'Controls and who drives';

  // ---- the car ------------------------------------------------------------------------------
  // signal: what sloppyCAN sends the simulator, from contract/carlito_contract.json.
  // Drawn in this order: later shapes sit on top. A layout's entry overrides these fields.
  var PEDALS = photo('pedals-manual.jpg', 'Pedal_Locations_in_2007_Subaru_Legacy_cropped.jpg', 'Tckma', 'public domain');
  var AUTO_PEDALS = photo('pedals-auto.jpg', 'Pedals_-_2013_Lexus_LS_460_(9864203176).jpg', 'Michael Sheehan', 'CC BY 2.0');
  var CAR_CONTROLS = [
    { id: 'lights', name: 'Light switch', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      wiki: 'Car_controls#Signals_and_lighting',
      text: 'Turns the lamps on: off, clearance lamps, low beam, high beam.',
      signal: ['lights'],
      photo: photo('light-switch.jpg', 'Close-up_on_the_headlight_switch_control_buttons.jpg', 'Shixart1985', 'CC BY 2.0'),
      shapes: [circle(58, 92, 14), thick(line(58, 92, 58, 80), 3)] },
    { id: 'indicators', name: 'Indicator stalk', cls: 'an-link', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      wiki: 'Automotive_lighting#Turn_signals',
      text: 'Pushed up or down, it blinks the right or left indicators before a turn.',
      signal: ['turnL', 'turnR'],
      photo: photo('indicator-stalk.jpg', 'Fog_Lights_On_Stalk.jpg', 'Ehsnils', 'CC BY-SA 3.0'),
      shapes: [thick(line(132, 106, 92, 96), 5), rect(80, 90, 14, 10, 4)] },
    { id: 'key', name: 'Ignition key', cls: 'an-box', page: 'controls/one-input-for-every-vehicle', pageTitle: CONTROLS_PAGE,
      wiki: 'Ignition_switch',
      // contract key: Lock, On, Ignition; "Throttle is forced 0 unless Ignition"
      text: 'Controls the power supply: ACC (Accessory) only for electronics, IGN (Ignition) or ON to include the engine. May be a button on recent cars.',
      signal: ['key'],
      photo: photo('ignition-switch.jpg', 'Zündschloss.jpg', 'Thomas doerfer', 'CC BY-SA 3.0'),
      shapes: [circle(252, 96, 10), rect(248, 84, 8, 14, 2)] },
    { id: 'wheel', name: 'Steering wheel', cls: 'an-link', page: 'steering', pageTitle: 'Steering and Ackermann',
      wiki: 'Steering_wheel',
      text: 'Turns the front wheels: the further you turn it, the tighter the turn.',
      signal: ['steer'],
      photo: photo('steering-wheel.jpg', '2019_Tesla_Model_3_Performance_Steering_wheel_and_pedals.jpg', 'Everestnc', 'CC BY 4.0'),
      shapes: [thick(circle(170, 104, 50), 7), thick(line(156, 108, 121, 114), 5),
        thick(line(184, 108, 219, 114), 5), thick(line(170, 118, 170, 153), 5)] },
    { id: 'horn', name: 'Horn', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      wiki: 'Vehicle_horn',
      text: 'The middle of the wheel: press it to sound the horn.',
      signal: ['horn'],
      photo: photo('horn.jpg', 'Mitsubishi_Lancer_(2008)_–_steering_wheel.jpg', 'Acgskup', 'CC BY 4.0'),
      shapes: [circle(170, 104, 16)] },
    { id: 'gear', name: 'Gear selector', cls: 'an-box', page: 'gearbox', pageTitle: 'Gearbox and shifting' },
    { id: 'handbrake', name: 'Handbrake', cls: 'an-box', page: 'holding', pageTitle: 'Holding still',
      wiki: 'Parking_brake',
      // contract handbrake: "the rear wheels' own hardware ... locks the rears at speed"
      text: 'The parking brake: it holds a parked car, and pulled on the move it locks the rear wheels. May be an electronic button instead.',
      signal: ['handbrake'],
      photo: photo('handbrake.jpg', 'Handbrake_lever.JPG', 'Ballista', 'CC BY-SA 3.0'),
      shapes: [rect(352, 150, 16, 70, 7)] },
    { id: 'clutch', name: 'Clutch pedal', cls: 'an-box', page: 'coupling/the-friction-clutch', pageTitle: 'Clutch and torque converter',
      wiki: 'Car_controls#Manual',
      text: 'The left pedal disconnects the engine from the wheels, to pull away and to change gear.',
      shapes: [rect(98, 186, 30, 26, 4)], photo: PEDALS },
    { id: 'brake', name: 'Brake pedal', cls: 'an-box', page: 'brakes', pageTitle: 'Brakes',
      wiki: 'Car_controls#Braking',
      text: 'Slows the car down, harder the more you press it.',
      signal: ['brake'],
      shapes: [rect(144, 182, 38, 30, 4)] },
    { id: 'accel', name: 'Accelerator pedal', cls: 'an-box', page: 'engine', pageTitle: 'The engine',
      wiki: 'Car_controls#Throttle_control',
      text: 'The right pedal asks the engine for power: the further down, the harder the car speeds up.',
      signal: ['accel'],
      shapes: [rect(204, 168, 20, 48, 4)] }
  ];

  // The car's two layouts. labels: [text, x, y] beside the gear lever.
  var CAR_LAYOUTS = [
    { id: 'auto', name: 'AUTO', aria: 'with an automatic gearbox', omit: ['clutch'],
      labels: [['P', 326, 158], ['R', 326, 174], ['N', 326, 190], ['D', 326, 206]],
      parts: {
        // gearbox.md Choosing a gear: P, R, N and D
        gear: { wiki: 'Automatic_transmission#Gear_selectors', text: 'P parks, R reverses, N disconnects the engine, D drives forward while the gearbox picks the gear. May look very different depending on the car.',
          signal: ['gear'],
          shapes: [rect(288, 146, 26, 74, 6), circle(301, 207, 9)],
          photo: photo('selector-auto.jpg', '2023_Audi_A4_B9_Avant_Allroad_-_gear_selector_(automatic_transmission).jpg', 'Acgskup', 'CC BY 4.0') },
        // an automatic's wide brake pedal, for either foot
        brake: { shapes: [rect(132, 182, 50, 30, 4)], photo: AUTO_PEDALS },
        accel: { photo: AUTO_PEDALS }
      } },
    { id: 'manual', name: 'MANUAL', aria: 'with a manual gearbox',
      labels: [['R', 284, 142], ['1', 300, 142], ['3', 316, 142], ['5', 332, 142],
        ['2', 300, 200], ['4', 316, 200], ['6', 332, 200]],
      parts: {
        // controls.md Choosing a gear (MANUAL): "the byte is taken exactly"
        gear: { name: 'Gear lever', page: 'gearbox-kinds/the-manual-gearbox', pageTitle: 'Kinds of gearbox', wiki: 'Gear_stick',
          text: 'Picks the gear: first to pull away, higher gears for more speed, R to reverse; the middle is neutral.',
          signal: ['gear'], photo: photo('lever-manual.jpg', 'Manual_gear_stick.jpg', 'Pommeau', 'CC BY-SA 4.0'),
          shapes: [thick(path('M284 150V170H332M300 150V190M316 150V190M332 150V190'), '3;fill:none'), circle(308, 170, 8)] },
        brake: { photo: PEDALS },
        accel: { photo: PEDALS }
      } }
  ];

  // ---- the truck ----------------------------------------------------------------------------
  // The garbage truck (automatic) and the semis (automated manual): two pedals, no P.
  var TRUCK_CONTROLS = [
    { id: 'lights', name: 'Light switch', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'Turns the lamps on: off, clearance lamps, low beam, high beam.', signal: ['lights'],
      shapes: [circle(58, 92, 14), thick(line(58, 92, 58, 80), 3)] },
    { id: 'indicators', name: 'Indicator stalk', cls: 'an-link', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'Pushed up or down, it blinks the right or left indicators before a turn.', signal: ['turnL', 'turnR'],
      shapes: [thick(line(132, 106, 92, 96), 5), rect(80, 90, 14, 10, 4)] },
    { id: 'retarder', name: 'Retarder stalk', cls: 'an-link', page: 'brakes/the-retarder', pageTitle: 'Brakes',
      // brakes.md The retarder; contract retarder: no local key
      text: 'Slows the truck through its driveline without touching the wheel brakes, so a long hill does not overheat them.',
      signal: ['retarder'],
      shapes: [thick(line(208, 106, 248, 96), 5), rect(246, 90, 14, 10, 4)] },
    { id: 'key', name: 'Ignition key', cls: 'an-box', page: 'controls/one-input-for-every-vehicle', pageTitle: CONTROLS_PAGE,
      text: 'Controls the power supply: ACC (Accessory) only for electronics, IGN (Ignition) or ON to include the engine.',
      signal: ['key'], shapes: [circle(290, 110, 10), rect(286, 98, 8, 14, 2)] },
    { id: 'wheel', name: 'Steering wheel', cls: 'an-link', page: 'steering', pageTitle: 'Steering and Ackermann',
      text: 'Turns the front wheels, with power assistance: a truck\'s wheel is large and almost flat.', signal: ['steer'],
      shapes: [thick(circle(170, 104, 54), 7), thick(line(156, 108, 117, 114), 5),
        thick(line(184, 108, 223, 114), 5), thick(line(170, 118, 170, 157), 5)] },
    { id: 'horn', name: 'Horn', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'The middle of the wheel sounds the horn; many trucks add loud air horns on the roof.', signal: ['horn'],
      shapes: [circle(170, 104, 16)] },
    { id: 'pto', name: 'PTO switch', cls: 'an-box', page: 'implements/on-the-trucks', pageTitle: 'Implements and the PTO',
      // implements.md On the trucks: the refuse body's pump, the tipper semi-trailer
      text: 'Sends engine power to a pump: the garbage truck\'s lifting arm, or a tipper trailer\'s ram.', signal: ['pto'],
      shapes: [rect(316, 50, 16, 24, 3)] },
    { id: 'body', name: 'Body controls', cls: 'an-box', page: 'implements/on-the-trucks', pageTitle: 'Implements and the PTO',
      // contract body_cmd: Idle, Lift, Dump, Lower (garbage truck)
      text: 'On the garbage truck: lift the bin, dump it into the hopper, lower the arm.', signal: ['body_cmd'],
      shapes: [rect(340, 52, 11, 20, 2), rect(355, 52, 11, 20, 2), rect(370, 52, 11, 20, 2)] },
    { id: 'gear', name: 'Gear selector', cls: 'an-box', page: 'gearbox', pageTitle: 'Gearbox and shifting',
      // contract gear: "the trucks park on their spring brakes", P reads as N
      text: 'D drives forward while the gearbox picks the gear, N is neutral, R reverses. Often push buttons. No P: the parking brake holds a truck.',
      signal: ['gear'], shapes: [rect(316, 92, 46, 30, 4)] },
    { id: 'handbrake', name: 'Parking brake valve', cls: 'an-box', page: 'brakes/air-and-spring-brakes', pageTitle: 'Brakes',
      // brakes.md Air and spring brakes
      text: 'A hand valve: pulled, it lets the air out and strong springs put the rear brakes on.', signal: ['handbrake'],
      shapes: [circle(392, 104, 9), rect(388, 110, 8, 14, 2)] },
    // MANUAL only: 3 lever positions x splitter x range = 12, as many as semi_spec.tres gear_ratios
    { id: 'gearLever', name: 'Gear lever', cls: 'an-box', page: 'gearbox-kinds/the-manual-gearbox', pageTitle: 'Kinds of gearbox',
      text: 'Three forward positions and R, with the clutch down. A splitter switch on the knob halves each step, and a range switch repeats them all higher up: 3 × 2 × 2 = 12 gears. Found on semis; refuse and fire trucks are nearly all automatic.',
      signal: ['gear'],
      shapes: [thick(path('M326 150V190M346 150V190M326 170H346'), '3;fill:none'), circle(336, 170, 8), rect(331, 160, 10, 5, 1)] },
    { id: 'clutch', name: 'Clutch pedal', cls: 'an-box', page: 'coupling/the-friction-clutch', pageTitle: 'Clutch and torque converter',
      text: 'Disconnects the engine to pull away and to change gear; a heavy truck\'s is stiff.',
      shapes: [rect(80, 186, 30, 26, 4)] },
    { id: 'brake', name: 'Brake pedal', cls: 'an-box', page: 'brakes/air-and-spring-brakes', pageTitle: 'Brakes',
      text: 'Lets compressed air into the brakes: the truck slows harder the more you press it.', signal: ['brake'],
      shapes: [rect(132, 182, 50, 30, 4)] },
    { id: 'accel', name: 'Accelerator pedal', cls: 'an-box', page: 'engine', pageTitle: 'The engine',
      text: 'The right pedal asks the engine for power: the further down, the harder the truck speeds up.', signal: ['accel'],
      shapes: [rect(204, 168, 20, 48, 4)] }
  ];

  // Photos (img/cockpit/truck-*) and Wikipedia articles; the gaps have a link only.
  var TRUCK_MANUAL_PEDALS = photo('truck-clutch-pedal.jpg', 'Inside_Mack_Granite.JPG', 'Panoha', 'CC BY-SA 3.0');
  var TRUCK_MEDIA = {
    wheel: { wiki: 'Steering_wheel', photo: photo('truck-steering-wheel.jpg', 'Mercedes-Benz_LKW_Lenkrad.jpg', 'selbst', 'public domain') },
    horn: { wiki: 'Air_horn' },
    retarder: { wiki: 'Retarder_(mechanical_engineering)' },
    pto: { wiki: 'Power_take-off' },
    key: { wiki: 'Ignition_switch' },
    indicators: { wiki: 'Automotive_lighting#Turn_signals', photo: photo('truck-indicator-stalk.jpg', 'Hino_Ranger_FD7JLA_Scanning_Cruise_Main_switch_and_Right_column_lever.jpg', 'Comyu', 'CC BY-SA 4.0') },
    // an Allison push-button selector, in a bus
    gear: { wiki: 'Automatic_transmission', photo: photo('truck-gear-selector.jpg', 'Aero_Star_MP37F_Allison_Shift_selector_and_Parking_brake_lever.jpg', 'Comyu', 'CC BY-SA 3.0') },
    handbrake: { wiki: 'Parking_brake', photo: photo('truck-parking-brake.jpg', 'Park_brake_hand_control.jpg', 'Panoha', 'CC BY-SA 3.0') },
    gearLever: { wiki: 'Gear_stick#Gear_knob_and_switches', photo: photo('truck-gear-lever-manual.jpg', 'Inside_Volvo_FM.jpg', 'Panoha', 'CC BY-SA 3.0') },
    clutch: { wiki: 'Clutch', photo: TRUCK_MANUAL_PEDALS },
    brake: { wiki: 'Air_brake_(road_vehicle)' },
    accel: { wiki: 'Car_controls#Throttle_control' }
  };
  TRUCK_CONTROLS.forEach(function (C) { Object.assign(C, TRUCK_MEDIA[C.id] || {}); });

  // ---- the tractor --------------------------------------------------------------------------
  // The powershift and the CVT tractor share one cab. Pages: implements.md, engine.md The
  // tractor's governor, differentials.md The tractor's diff lock and front-wheel drive.
  var TRACTOR_CONTROLS = [
    { id: 'lights', name: 'Light switch', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'Turns the lamps on: off, clearance lamps, low beam, high beam.', signal: ['lights'],
      shapes: [circle(57, 72, 12), thick(line(57, 72, 57, 62), 3)] },
    { id: 'shuttle', name: 'Shuttle lever', cls: 'an-link', page: 'gearbox', pageTitle: 'Gearbox and shifting',
      text: 'Picks forward or reverse without a stop to change gear: for loader and field work, back and forth.', signal: ['gear'],
      shapes: [thick(line(122, 104, 86, 90), 5), circle(82, 88, 7)] },
    { id: 'indicators', name: 'Indicator stalk', cls: 'an-link', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'Pushed up or down, it blinks the right or left indicators before a turn.', signal: ['turnL', 'turnR'],
      shapes: [thick(line(178, 104, 214, 94), 5), rect(212, 88, 14, 10, 4)] },
    { id: 'key', name: 'Ignition key', cls: 'an-box', page: 'controls/one-input-for-every-vehicle', pageTitle: CONTROLS_PAGE,
      text: 'Controls the power supply: ACC (Accessory) only for electronics, IGN (Ignition) or ON to include the engine.',
      signal: ['key'], shapes: [circle(208, 62, 9), rect(204, 51, 8, 13, 2)] },
    { id: 'wheel', name: 'Steering wheel', cls: 'an-link', page: 'steering/auto-steer-on-the-tractor', pageTitle: 'Steering and Ackermann',
      // steering.md Auto-steer on the tractor: guidance_curvature replaces steer
      text: 'Turns the front wheels. In the field, a guidance computer can steer instead (auto-steer).',
      signal: ['steer', 'guidance_curvature'],
      shapes: [thick(circle(150, 108, 44), 6), thick(line(138, 110, 108, 116), 5),
        thick(line(162, 110, 192, 116), 5), thick(line(150, 122, 150, 152), 5)] },
    { id: 'horn', name: 'Horn', cls: 'an-box', page: 'controls/lamps-and-horn', pageTitle: CONTROLS_PAGE,
      text: 'The middle of the wheel: press it to sound the horn.', signal: ['horn'],
      shapes: [circle(150, 108, 14)] },
    { id: 'handbrake', name: 'Parking brake', cls: 'an-box', page: 'holding', pageTitle: 'Holding still',
      text: 'Holds the parked tractor.', signal: ['handbrake'],
      shapes: [rect(22, 150, 14, 70, 7)] },
    // MANUAL only: 4 gears x 4 ranges = 16, as many as tractor-kenney_spec.tres gear_ratios
    { id: 'gearLever', name: 'Gear lever', cls: 'an-box', page: 'gearbox-kinds/the-manual-gearbox', pageTitle: 'Kinds of gearbox',
      text: 'Picks one of four gears, with the clutch down. With the range lever, 4 × 4 = 16 gears.',
      signal: ['gear'],
      shapes: [thick(path('M246 148V188M266 148V188M246 168H266'), '3;fill:none'), circle(256, 168, 7)] },
    { id: 'rangeLever', name: 'Range lever', cls: 'an-box', page: 'gearbox-kinds/the-manual-gearbox', pageTitle: 'Kinds of gearbox',
      text: 'Picks the range, from A for slow field work to D for the road; each range repeats the four gears.',
      signal: ['gear'],
      shapes: [rect(296, 202, 56, 10, 4), circle(304, 207, 6)] },
    { id: 'handThrottle', name: 'Hand throttle', cls: 'an-box', page: 'engine/the-tractors-governor', pageTitle: 'The engine',
      // contract hand_throttle: the higher of the accelerator and this sets the engine speed
      text: 'Sets an engine speed that stays put with no foot on the pedal: for steady PTO work.', signal: ['hand_throttle'],
      shapes: [rect(296, 104, 10, 44, 4), circle(301, 116, 8)] },
    { id: 'hitch', name: 'Hitch control', cls: 'an-box', page: 'implements/the-three-point-hitch', pageTitle: 'Implements and the PTO',
      text: 'Raises and lowers the three-point hitch, and the tool on it.', signal: ['hitch_pos'],
      shapes: [rect(322, 104, 22, 34, 4), line(322, 121, 344, 121)] },
    { id: 'scv', name: 'Hydraulic remote levers', cls: 'an-box', page: 'implements/the-hydraulic-remote', pageTitle: 'Implements and the PTO',
      text: 'Send oil to a ram on the tool (for example, to open a spreader\'s gate or tip a trailer).', signal: ['scv_flow'],
      shapes: [thick(line(366, 140, 366, 110), 3), circle(366, 106, 7), thick(line(392, 140, 392, 110), 3), circle(392, 106, 7)] },
    { id: 'pto', name: 'PTO switch', cls: 'an-box', page: 'implements/the-pto', pageTitle: 'Implements and the PTO',
      text: 'Turns the shaft at the back that drives the tool\'s machinery, at 540 or 1000 rpm.', signal: ['pto', 'pto_mode'],
      shapes: [circle(304, 178, 11), circle(304, 178, 4)] },
    { id: 'mfwd', name: 'Front-drive switch', cls: 'an-box', page: 'differentials/the-tractors-diff-lock-and-front-wheel-drive', pageTitle: 'Differentials and four-wheel drive',
      text: 'Drives the front wheels too, for more grip in the field.', signal: ['fwd_drive'],
      shapes: [rect(330, 170, 26, 16, 3)] },
    { id: 'diffLock', name: 'Diff lock', cls: 'an-box', page: 'differentials/the-tractors-diff-lock-and-front-wheel-drive', pageTitle: 'Differentials and four-wheel drive',
      text: 'Locks the two rear wheels together, so the one with grip pulls; for straight work in the field.', signal: ['diff_lock'],
      shapes: [rect(366, 170, 26, 16, 3)] },
    { id: 'clutch', name: 'Clutch pedal', cls: 'an-box', page: 'coupling/the-friction-clutch', pageTitle: 'Clutch and torque converter',
      text: 'Disconnects the engine to stop or inch the tractor.',
      shapes: [rect(64, 184, 28, 28, 4)] },
    { id: 'brake', name: 'Brake pedals', cls: 'an-box', page: 'brakes', pageTitle: 'Brakes',
      // contract brake: one value; fwd_drive_state: the pedal engages MFWD to brake the fronts
      text: 'One pedal per rear wheel: pressed alone, one brakes that side for a tight turn; latched together on the road.',
      signal: ['brake'], shapes: [rect(148, 184, 22, 28, 3), rect(174, 184, 22, 28, 3)] },
    { id: 'accel', name: 'Accelerator pedal', cls: 'an-box', page: 'engine/the-tractors-governor', pageTitle: 'The engine',
      // contract hand_throttle: "the higher of the accelerator and this sets an engine speed"
      text: 'Sets the engine speed the governor holds; the higher of it and the hand throttle wins.', signal: ['accel'],
      shapes: [rect(222, 172, 16, 44, 4)] }
  ];
  // Photos (img/cockpit/tractor-*) and Wikipedia articles. Commons has few free photos of tractor
  // cab controls: some show an older tractor, and the rest have a link only.
  var TRACTOR_MEDIA = {
    wheel: { wiki: 'Steering_wheel', photo: photo('tractor-steering-wheel.jpg', 'John_Deere_5400_in_Valle_del_Cuña_Pirú_(Ruiz_de_Montoya,_Misiones,_Argentina)_9.jpg', 'Horacio Cambeiro', 'CC BY-SA 4.0') },
    brake: { wiki: 'Tractor#Pedals', photo: photo('tractor-brake-pedals.jpg', 'Closeup_to_metal_dirty_control_pedal_of_tractor.jpg', 'Nenad Stojkovic', 'CC BY 2.0') },
    clutch: { wiki: 'Tractor#Pedals' },
    accel: { wiki: 'Throttle' },
    handThrottle: { wiki: 'Throttle' },
    shuttle: { wiki: 'Tractor#Levers_and_switches' },
    hitch: { wiki: 'Three-point_hitch' },
    pto: { wiki: 'Power_take-off' },
    scv: { wiki: 'Tractor#Power_take-off_systems_and_hydraulics', photo: photo('tractor-scv-lever.jpg', 'Agritechnica_2023,_Hanover_(P1140875).jpg', 'MB-one', 'CC BY-SA 4.0') },
    diffLock: { wiki: 'Locking_differential' },
    mfwd: { wiki: 'Four-wheel_drive', photo: photo('tractor-mfwd-switch.jpg', 'Kubota_B6200_Transfer_Case_Controls.jpg', 'NSEasternShoreChemist', 'CC BY-SA 4.0') },
    key: { wiki: 'Ignition_switch', photo: photo('tractor-ignition.jpg', 'Armaturenbrett.jpg', 'Johannes Maximilian', 'CC BY-SA 4.0') },
    gearLever: { wiki: 'Gear_stick' },
    // a compact tractor's hi-lo range lever, beside its front-drive lever
    rangeLever: { photo: photo('tractor-mfwd-switch.jpg', 'Kubota_B6200_Transfer_Case_Controls.jpg', 'NSEasternShoreChemist', 'CC BY-SA 4.0') }
  };
  TRACTOR_CONTROLS.forEach(function (C) { Object.assign(C, TRACTOR_MEDIA[C.id] || {}); });

  var FAMILIES = {
    car: { noun: 'A car', controls: CAR_CONTROLS, layouts: CAR_LAYOUTS,
      chips: ['wheel', 'accel', 'brake', 'clutch', 'gear', 'handbrake', 'key', 'lights', 'indicators', 'horn'],
      scenery: function (svg) {
        panel(svg, 'M8 40Q210 14 412 40V132H8Z');   // dashboard
        panel(svg, 'M276 132H340V226H276Z');       // centre console
        floor(svg, 270);
        gauges(svg, [148, 192], 44, 11);
      } },
    truck: { noun: 'A truck', controls: TRUCK_CONTROLS,
      layouts: [
        { id: 'auto', name: 'AUTO', aria: 'with an automatic gearbox', omit: ['gearLever', 'clutch'],
          labels: [['D', 327, 107], ['N', 339, 107], ['R', 351, 107]], parts: {} },
        { id: 'manual', name: 'MANUAL', aria: 'with a manual gearbox', omit: ['gear'],
          labels: [['R', 326, 142], ['1', 326, 198], ['2', 346, 142], ['3', 346, 198]],
          parts: {
            brake: { shapes: [rect(140, 182, 38, 30, 4)], photo: TRUCK_MANUAL_PEDALS },
            accel: { photo: TRUCK_MANUAL_PEDALS }
          } }
      ],
      chips: ['wheel', 'accel', 'brake', 'clutch', 'gear', 'gearLever', 'retarder', 'handbrake', 'pto', 'body', 'key', 'lights', 'indicators', 'horn'],
      scenery: function (svg) {
        panel(svg, 'M8 36H412V132H8Z');              // the flat, upright dashboard
        floor(svg, 412);
        gauges(svg, [146, 194], 42, 12);
      } },
    tractor: { noun: 'A tractor', controls: TRACTOR_CONTROLS,
      layouts: [
        { id: 'auto', name: 'AUTO', aria: 'with a powershift gearbox', omit: ['gearLever', 'rangeLever'], labels: [], parts: {} },
        { id: 'manual', name: 'MANUAL', aria: 'with a manual gearbox',
          labels: [['1', 246, 140], ['2', 246, 196], ['3', 266, 140], ['4', 266, 196],
            ['A', 304, 219], ['B', 318, 219], ['C', 332, 219], ['D', 346, 219]],
          parts: {
            clutch: { text: 'Disconnects the engine to stop the tractor and for every gear change.' }
          } }
      ],
      chips: ['wheel', 'accel', 'brake', 'clutch', 'shuttle', 'gearLever', 'rangeLever', 'handThrottle', 'handbrake', 'hitch', 'pto', 'scv', 'diffLock', 'mfwd', 'key', 'lights', 'indicators', 'horn'],
      scenery: function (svg) {
        panel(svg, 'M112 38H188V64Q150 74 112 64Z'); // the instrument pod on the steering column
        panel(svg, 'M282 92H412V226H282Z');          // the right-hand console
        floor(svg, 276);
        gauges(svg, [136, 164], 51, 9);
      } }
  };
  var HINT = 'Click a control, in the drawing or by its name, to see what it does and its sloppyCAN signals.';

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets.cockpit = function (root) {
    var fam = FAMILIES[root.getAttribute('data-family') || 'car'];
    if (!fam) return;
    var layout = fam.layouts[0], selected = null, groups = {}, chips = {};

    // AUTO / MANUAL, only where a family has two layouts.
    var pickButtons = [];
    if (fam.layouts.length > 1) {
      var pick = document.createElement('div');
      pick.className = 'an-chips';
      pick.setAttribute('role', 'group');
      pick.setAttribute('aria-label', 'Gearbox');
      root.appendChild(pick);
      pickButtons = fam.layouts.map(function (L) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'an-chip';
        b.textContent = L.name;
        b.addEventListener('click', function () { layout = L; draw(); });
        pick.appendChild(b);
        return b;
      });
    }
    var svg = el('svg', { viewBox: '0 0 420 230', role: 'img' }, root);
    var chipRow = document.createElement('div');
    chipRow.className = 'an-chips';
    chipRow.setAttribute('role', 'group');
    chipRow.setAttribute('aria-label', 'Controls');
    root.appendChild(chipRow);
    var info = document.createElement('div');
    info.className = 'an-info';
    info.setAttribute('aria-live', 'polite');
    root.appendChild(info);

    function controls() {
      return fam.controls.filter(function (C) { return (layout.omit || []).indexOf(C.id) < 0; })
        .map(function (C) { return Object.assign({}, C, layout.parts[C.id] || {}); });
    }
    function hover(id, on) { groups[id].classList.toggle('an-hover', on); }

    function select(id) {
      selected = id;
      for (var k in groups) groups[k].classList.toggle('an-on', k === id);
      for (var c in chips) chips[c].setAttribute('aria-pressed', c === id ? 'true' : 'false');
      var C = controls().filter(function (x) { return x.id === id; })[0];
      GuideKit.card(info, { name: C.name, text: C.text, page: C.page, pageTitle: C.pageTitle, wiki: C.wiki,
        photo: C.photo, sig: C.signal && 'sloppyCAN: ' + C.signal.map(function (n) { return '<code>' + n + '</code>'; }).join(', ') + '.' });
    }

    function draw() {
      fam.layouts.forEach(function (L, i) {
        if (pickButtons[i]) pickButtons[i].setAttribute('aria-pressed', L === layout ? 'true' : 'false');
      });
      svg.setAttribute('aria-label', fam.noun + '\'s controls seen from the driver\'s seat, ' + layout.aria);
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      groups = {};
      fam.scenery(svg);
      var list = controls();
      list.forEach(function (C) {
        var g = el('g', { 'class': 'an-part ' + C.cls }, svg);
        C.shapes.forEach(function (s) { el(s[0], s[1], g); });
        // A wider, invisible copy of each shape is the click target.
        C.shapes.forEach(function (s) {
          var h = el(s[0], s[1], g);
          h.setAttribute('class', 'an-hit');
          h.removeAttribute('style');
        });
        el('title', {}, g).textContent = C.name;
        g.addEventListener('click', function () { select(C.id); });
        groups[C.id] = g;
      });
      layout.labels.forEach(function (L) {
        el('text', { x: L[1], y: L[2], 'class': 'an-label', 'text-anchor': 'middle',
          'dominant-baseline': 'middle' }, svg).textContent = L[0];
      });

      while (chipRow.firstChild) chipRow.removeChild(chipRow.firstChild);
      chips = {};
      fam.chips.forEach(function (id) {
        var C = list.filter(function (x) { return x.id === id; })[0];
        if (!C) return;
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'an-chip';
        b.textContent = C.name;
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
      else { selected = null; info.classList.remove('w-card'); info.textContent = HINT; }
    }
    draw();
  };
})();
