// Gear against speed: pick a vehicle, a gear and an engine speed, and see the road speed that
// gear gives and how hard the driven wheels push. Plain JS and SVG, no libraries.
// Figures, all read from the game's specs:
//   sedan_spec.tres    gear_ratios 4.5 2.903 1.975 1.431 1.109 0.925; final_drive 3.9 and
//                      efficiency 0.9 (CAR_BASE); wheel_radius 0.36; idle 900, redline 6800
//                      (VehicleSpec defaults); torque_curve as below; mass 1150
//   race_spec.tres     gear_ratios 3.2 2.30 1.72 1.32 0.98 0.66; final_drive 4.2; radius 0.36;
//                      idle 900, redline 6800; torque_curve as below; mass 900
//   semi_spec.tres     gear_ratios 6.5 ... 0.69 (12); final_drive 2.925; efficiency 0.9; radius
//                      0.36; idle 600, redline 2080; torque_curve as below; mass 8000 (bobtail)
//   tractor-kenney_spec.tres  gear_ratios 7 ... 1.357 (16); final_drive 12.299 at the 0.805 m
//                      driven rear (GroundDriveSpec.drive_radius); idle 800, redline 2350; mass 7000
// Road speed = rpm x 2 pi / 60 x radius / (gear x final drive) (Drivetrain.wheel_engine_rpm, in
// reverse). Wheel push = torque x gear x final drive x efficiency / radius (Drivetrain.wheel_torque),
// with the clutch locked: no converter multiplication, no grip limit, no drag.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var VEHICLES = [
    { id: 'sedan', name: 'sedan (car)', ratios: [4.5, 2.903, 1.975, 1.431, 1.109, 0.925], fd: 3.9, r: 0.36,
      idle: 900, red: 6800, mass: 1150,
      curve: [[900, 98], [2000, 154], [3200, 184], [4800, 185], [6000, 185], [6600, 170], [6800, 61]] },
    { id: 'race', name: 'race (racing car)', ratios: [3.2, 2.30, 1.72, 1.32, 0.98, 0.66], fd: 4.2, r: 0.36,
      idle: 900, red: 6800, mass: 900,
      curve: [[900, 205.8], [2000, 323.4], [3200, 386.4], [4800, 388.5], [6000, 388.5], [6600, 357], [6800, 128.1]] },
    { id: 'semi', name: 'semi (truck, no trailer)', ratios: [6.5, 5.316, 4.277, 3.5, 2.849, 2.327, 1.917, 1.568, 1.26, 1.031, 0.839, 0.69],
      fd: 2.925, r: 0.36, idle: 600, red: 2080, mass: 8000,
      curve: [[600, 1500], [780, 1985], [1170, 2308], [1560, 2215], [1820, 1723], [2080, 577]] },
    { id: 'tractor', name: 'tractor-kenney', ratios: [7, 6.275, 5.625, 5.042, 4.52, 4.051, 3.632, 3.255, 2.918, 2.616, 2.345, 2.102, 1.884, 1.689, 1.514, 1.357],
      fd: 12.299, r: 0.805, idle: 800, red: 2350, mass: 7000,
      curve: [[800, 550], [1200, 680], [1600, 700], [2000, 640], [2200, 560], [2350, 0]] }
  ];
  var EFF = 0.9;
  var X0 = 70, X1 = 404;

  function torqueAt(curve, rpm) {
    if (rpm <= curve[0][0]) return curve[0][1];
    for (var i = 1; i < curve.length; i++) {
      if (rpm <= curve[i][0]) {
        var t = (rpm - curve[i - 1][0]) / (curve[i][0] - curve[i - 1][0]);
        return curve[i - 1][1] + (curve[i][1] - curve[i - 1][1]) * t;
      }
    }
    return curve[curve.length - 1][1];
  }
  function kmh(v, gear, rpm) {
    return rpm * 2 * Math.PI / 60 * v.r / (v.ratios[gear] * v.fd) * 3.6;
  }
  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function text(parent, x, y, str, extra) {
    var t = el('text', Object.assign({ x: x, y: y, 'font-size': 13, fill: 'var(--fig-muted)' }, extra || {}), parent);
    t.textContent = str;
    return t;
  }
  function niceMax(x) {
    var steps = [10, 20, 25, 50, 100, 150, 200, 250, 300];
    for (var i = 0; i < steps.length; i++) if (x <= steps[i]) return steps[i];
    return Math.ceil(x / 100) * 100;
  }

  function make(root) {
    root.innerHTML = '';
    var title = document.createElement('p');
    title.className = 'w-title';
    title.textContent = 'Try it: gears against road speed';
    root.appendChild(title);

    var svg = el('svg', { role: 'img', 'aria-label': 'Each gear\'s road-speed range, from idle to the redline, with a marker at the chosen gear and engine speed' }, root);

    var uid = 'gs' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-v">Vehicle</label><select id="' + uid + '-v"></select><span></span>' +
      '<label for="' + uid + '-g">Gear</label><input id="' + uid + '-g" type="range" min="1" step="1">' +
      '<output for="' + uid + '-g"></output>' +
      '<label for="' + uid + '-r">Engine speed</label><input id="' + uid + '-r" type="range" step="10">' +
      '<output for="' + uid + '-r"></output>';
    root.appendChild(controls);
    var vSel = controls.querySelector('select');
    var gIn = controls.querySelectorAll('input')[0];
    var rIn = controls.querySelectorAll('input')[1];
    var outs = controls.querySelectorAll('output');
    VEHICLES.forEach(function (v, i) {
      var o = document.createElement('option');
      o.value = String(i);
      o.textContent = v.name;
      vSel.appendChild(o);
    });

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);
    var note = document.createElement('p');
    note.className = 'w-note';
    note.textContent = 'Each bar runs from idle to the redline in that gear. The push is the engine\'s full-throttle ' +
      'torque at this speed through the gears, with the clutch locked; it leaves out the converter, the tyres\' grip ' +
      'and the air. A governor caps the semi at 90 km/h and the tractor at 40.';
    root.appendChild(note);

    var v = VEHICLES[0];
    // The chart for one vehicle is built once (`build`); a gear or rpm change only restyles two
    // bars and moves the marker (`draw`).
    var TOP = 14;
    var bars = [], labels = [], row = 22, px = null, marker = null, guide = null, shown = -1;
    function build() {
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      var n = v.ratios.length;
      row = n > 8 ? 12 : 22;
      var h = TOP + n * row + 44;
      svg.setAttribute('viewBox', '0 0 420 ' + h);
      var vmax = niceMax(kmh(v, n - 1, v.red));
      px = function (s) { return X0 + (X1 - X0) * s / vmax; };
      var y0 = TOP + n * row;
      for (var t = 0; t <= 4; t++) {
        var s = vmax * t / 4;
        el('line', { x1: px(s), y1: TOP - 4, x2: px(s), y2: y0, stroke: 'var(--fig-grid)' }, svg);
        text(svg, px(s), y0 + 16, String(Math.round(s)), { 'text-anchor': t === 4 ? 'end' : 'middle' });
      }
      text(svg, (X0 + X1) / 2, y0 + 34, 'road speed, km/h', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
      bars = []; labels = []; shown = -1;
      for (var g = 0; g < n; g++) {
        var y = TOP + g * row;
        var a = kmh(v, g, v.idle), b = kmh(v, g, v.red);
        bars.push(el('rect', { x: px(a), y: y + 2, width: Math.max(1, px(b) - px(a)), height: row - 4, rx: 2 }, svg));
        labels.push(text(svg, X0 - 8, y + row / 2 + 4, 'D' + (g + 1), { 'text-anchor': 'end', 'font-size': n > 8 ? 11 : 13 }));
        style(g, false);
      }
      guide = el('line', { y1: TOP - 4, y2: y0, stroke: 'var(--fig-orange)', 'stroke-width': 1.5, 'stroke-dasharray': '3 3' }, svg);
      marker = el('circle', { r: 6, fill: 'var(--fig-orange)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);
    }
    function style(g, on) {
      var n = v.ratios.length;
      bars[g].setAttribute('fill', on ? 'var(--fig-blue)' : 'var(--fig-fill)');
      bars[g].setAttribute('stroke', on ? 'none' : 'var(--fig-grid)');
      labels[g].setAttribute('fill', on ? 'var(--fig-ink)' : 'var(--fig-muted)');
      labels[g].setAttribute('font-weight', on ? 600 : 400);
      labels[g].setAttribute('visibility', n <= 8 || on || g === 0 || g === n - 1 ? 'visible' : 'hidden');
    }
    function draw() {
      var gear = parseInt(gIn.value, 10) - 1;
      var rpm = parseFloat(rIn.value);
      if (gear !== shown) {
        if (shown >= 0) style(shown, false);
        style(gear, true);
        shown = gear;
      }
      var sp = kmh(v, gear, rpm);
      guide.setAttribute('x1', px(sp)); guide.setAttribute('x2', px(sp));
      marker.setAttribute('cx', px(sp)); marker.setAttribute('cy', TOP + gear * row + row / 2);

      outs[0].textContent = 'D' + (gear + 1);
      outs[1].textContent = Math.round(rpm) + ' rpm';
      var torque = torqueAt(v.curve, rpm);
      var push = torque * v.ratios[gear] * v.fd * EFF / v.r;
      var accel = push / v.mass;
      readout.innerHTML = '<strong>D' + (gear + 1) + ' at ' + Math.round(rpm) + ' rpm is about ' + Math.round(sp) + ' km/h.</strong><br>' +
        'Gear ratio ' + v.ratios[gear] + ', times the final drive ' + v.fd + ': the engine turns ' +
        (v.ratios[gear] * v.fd).toFixed(1) + ' times for each turn of the wheels.<br>' +
        'Full throttle here gives about ' + Math.round(torque) + ' N·m at the engine and a push of about ' +
        (push >= 10000 ? Math.round(push / 1000) + ' kN' : (Math.round(push / 10) * 10) + ' N') + ' at the tyres: ' +
        'enough to speed the bare vehicle up by about ' + accel.toFixed(1) + ' m/s² if the tyres could take it.';
    }
    function setVehicle() {
      v = VEHICLES[parseInt(vSel.value, 10)];
      gIn.max = String(v.ratios.length);
      gIn.value = '1';
      rIn.min = String(v.idle);
      rIn.max = String(v.red);
      rIn.value = String(Math.round((v.idle + v.red) / 2 / 10) * 10);
      build();
      draw();
    }
    vSel.addEventListener('change', setVehicle);
    gIn.addEventListener('input', draw);
    rIn.addEventListener('input', draw);
    setVehicle();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['gear-speed'] = make;
})();
