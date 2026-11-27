// Torque and power against engine speed: pick a vehicle, drag the engine speed, and see the
// full-throttle torque on the simulator's torque curve and the power it gives there.
// Plain JS and SVG, no libraries.
// Figures, all read from the simulator's specs (torque_curve, rpm -> N·m, linear between points,
// as VehicleSpec.sample_curve; idle_rpm; redline_rpm):
//   sedan_spec.tres          (900,98) (2000,154) (3200,184) (4800,185) (6000,185) (6600,170)
//                            (6800,61); idle 900, redline 6800 (VehicleSpec defaults)
//   garbage-truck_spec.tres  (700,509) (1200,826) (1800,1017) (2600,890) (2900,0); idle 700,
//                            redline 2900
//   semi_spec.tres           (600,1500) (780,1985) (1170,2308) (1560,2215) (1820,1723)
//                            (2080,577); idle 600, redline 2080
//   tractor-kenney_spec.tres (800,550) (1200,680) (1600,700) (2000,640) (2200,560) (2350,0);
//                            idle 800, redline 2350
// Power = torque x rpm x 2 pi / 60 (Drivetrain.peak_power); the best power is searched every
// 10 rpm from idle to the redline, as Drivetrain.peak_power does.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var VEHICLES = [
    { id: 'car', icon: 'car', name: 'Saloon car (petrol)', idle: 900, red: 6800,
      curve: [[900, 98], [2000, 154], [3200, 184], [4800, 185], [6000, 185], [6600, 170], [6800, 61]] },
    { id: 'truck', icon: 'truck', name: 'Medium truck (diesel)', idle: 700, red: 2900,
      curve: [[700, 509], [1200, 826], [1800, 1017], [2600, 890], [2900, 0]] },
    { id: 'semi', icon: 'semi', name: 'Semi truck (diesel)', idle: 600, red: 2080,
      curve: [[600, 1500], [780, 1985], [1170, 2308], [1560, 2215], [1820, 1723], [2080, 577]] },
    { id: 'tractor', icon: 'tractor', name: 'Farm tractor (diesel)', idle: 800, red: 2350,
      curve: [[800, 550], [1200, 680], [1600, 700], [2000, 640], [2200, 560], [2350, 0]] }
  ];
  // Plot frame (viewBox units): torque scale on the left, power on the right.
  var X0 = 56, X1 = 366, Y0 = 214, Y1 = 30;

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
  function powerW(torque, rpm) { return torque * rpm * 2 * Math.PI / 60; }
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
    var mag = Math.pow(10, Math.floor(Math.log10(x)));
    var steps = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    for (var i = 0; i < steps.length; i++) if (x <= steps[i] * mag) return steps[i] * mag;
    return 10 * mag;
  }
  function fmt(n) { return Math.round(n).toLocaleString('en-GB'); }
  // A share in whole percent that reads 100 only at the peak itself.
  function pct(x, peak) { return x >= peak - 1e-9 ? 100 : Math.min(99, Math.round(x / peak * 100)); }
  // The best torque (value, and the rpm span it holds over) and the best power (kW, rpm).
  function peaks(v) {
    var tMax = 0, i;
    for (i = 0; i < v.curve.length; i++) tMax = Math.max(tMax, v.curve[i][1]);
    var at = v.curve.filter(function (p) { return p[1] === tMax; });
    var best = { kw: 0, rpm: v.idle };
    for (var r = v.idle; r <= v.red; r += 10) {
      var kw = powerW(torqueAt(v.curve, r), r) / 1000;
      if (kw > best.kw) best = { kw: kw, rpm: r };
    }
    return { torque: tMax, from: at[0][0], to: at[at.length - 1][0], kw: best.kw, kwRpm: best.rpm };
  }

  function make(root) {
    root.innerHTML = '';
    GuideKit.vehiclePicker(root, VEHICLES.map(function (x) {
      return { id: x.id, icon: x.icon, name: x.name };
    }), VEHICLES[0].id, function (id) {
      for (var i = 0; i < VEHICLES.length; i++) if (VEHICLES[i].id === id) setVehicle(VEHICLES[i]);
    });

    var svg = el('svg', { viewBox: '0 0 420 262', role: 'img',
      'aria-label': 'The engine\'s full-throttle torque and its power against engine speed, with a marker at the chosen speed' }, root);

    var uid = 'tq' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-r">Engine speed</label><input id="' + uid + '-r" type="range" step="10">' +
      '<output for="' + uid + '-r"></output>';
    root.appendChild(controls);
    var rIn = controls.querySelector('input');
    var out = controls.querySelector('output');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    var v, pk, xMax, tMaxAxis, pMaxAxis, guide, tDot, pDot;
    function px(rpm) { return X0 + (X1 - X0) * rpm / xMax; }
    function pyT(nm) { return Y0 - (Y0 - Y1) * nm / tMaxAxis; }
    function pyP(kw) { return Y0 - (Y0 - Y1) * kw / pMaxAxis; }

    // The chart for one vehicle is built once; a speed change only moves the marker.
    function build() {
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      xMax = v.red > 4000 ? Math.ceil(v.red / 1000) * 1000 : Math.ceil(v.red / 500) * 500;
      tMaxAxis = niceMax(pk.torque * 1.08);
      pMaxAxis = niceMax(pk.kw * 1.08);
      var xStep = xMax > 4000 ? 1000 : 500;

      el('rect', { x: X0, y: Y1, width: px(v.idle) - X0, height: Y0 - Y1, fill: 'var(--fig-fill)' }, svg);
      [0.5, 1].forEach(function (f) {
        el('line', { x1: X0, y1: Y0 - (Y0 - Y1) * f, x2: X1, y2: Y0 - (Y0 - Y1) * f, stroke: 'var(--fig-grid)' }, svg);
        text(svg, X0 - 6, Y0 - (Y0 - Y1) * f + 4, fmt(tMaxAxis * f), { 'text-anchor': 'end', fill: 'var(--fig-blue)' });
        text(svg, X1 + 6, Y0 - (Y0 - Y1) * f + 4, fmt(pMaxAxis * f), { fill: 'var(--fig-orange)' });
      });
      text(svg, X0 - 6, Y0 + 4, '0', { 'text-anchor': 'end' });
      for (var r = 0; r <= xMax; r += xStep) {
        text(svg, px(r), Y0 + 17, fmt(r), { 'text-anchor': 'middle' });
      }
      el('path', { d: 'M' + X0 + ',' + (Y1 - 6) + ' L' + X0 + ',' + Y0 + ' L' + X1 + ',' + Y0 + ' L' + X1 + ',' + (Y1 - 6),
        fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
      el('line', { x1: px(v.red), y1: Y1, x2: px(v.red), y2: Y0, stroke: 'var(--fig-muted)', 'stroke-dasharray': '3 3' }, svg);
      text(svg, px(v.idle) - 4, Y0 - 6, 'idle', { 'text-anchor': 'end' });
      text(svg, px(v.red) - 3, Y1 - 5, 'redline', { 'text-anchor': 'end' });
      text(svg, (X0 + X1) / 2, Y0 + 36, 'engine speed, rpm', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
      text(svg, X0, 12, 'torque, N·m', { fill: 'var(--fig-blue)', 'font-weight': 600 });
      text(svg, (X0 + X1) / 2, 12, 'power, kW', { 'text-anchor': 'middle', fill: 'var(--fig-orange)', 'font-weight': 600 });

      var tPts = v.curve.map(function (p) { return px(p[0]) + ',' + pyT(p[1]); }).join(' ');
      var pPts = [];
      for (var q = v.idle; q <= v.red; q += 10) pPts.push(px(q) + ',' + pyP(powerW(torqueAt(v.curve, q), q) / 1000));
      el('polyline', { points: pPts.join(' '), fill: 'none', stroke: 'var(--fig-orange)', 'stroke-width': 2.5,
        'stroke-dasharray': '6 4', 'stroke-linejoin': 'round' }, svg);
      el('polyline', { points: tPts, fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3.5, 'stroke-linejoin': 'round' }, svg);

      guide = el('line', { y1: Y1, y2: Y0, stroke: 'var(--fig-ink)', 'stroke-width': 1, 'stroke-dasharray': '2 3' }, svg);
      pDot = el('circle', { r: 6, fill: 'var(--fig-orange)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);
      tDot = el('circle', { r: 6, fill: 'var(--fig-blue)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);
    }

    function draw() {
      var rpm = parseFloat(rIn.value);
      var torque = torqueAt(v.curve, rpm);
      var w = powerW(torque, rpm);
      var kw = w / 1000;
      guide.setAttribute('x1', px(rpm)); guide.setAttribute('x2', px(rpm));
      tDot.setAttribute('cx', px(rpm)); tDot.setAttribute('cy', pyT(torque));
      pDot.setAttribute('cx', px(rpm)); pDot.setAttribute('cy', pyP(kw));
      out.textContent = fmt(rpm) + ' rpm';
      var span = pk.from === pk.to ? 'at ' + fmt(pk.from) + ' rpm' : 'from ' + fmt(pk.from) + ' to ' + fmt(pk.to) + ' rpm';
      readout.innerHTML = '<strong>At ' + fmt(rpm) + ' rpm: ' + fmt(torque) + ' N·m and ' + fmt(kw) + ' kW.</strong><br>' +
        'Power = ' + fmt(torque) + ' N·m × ' + fmt(rpm) + ' rpm × 2π ÷ 60 = about ' + fmt(Math.round(w / 100) * 100) + ' W.<br>' +
        'That is ' + pct(torque, pk.torque) + ' % of the most torque (' + fmt(pk.torque) + ' N·m, ' + span + ') and ' +
        pct(kw, pk.kw) + ' % of the most power (' + fmt(pk.kw) + ' kW, at ' + fmt(pk.kwRpm) + ' rpm).';
    }

    function setVehicle(chosen) {
      v = chosen;
      pk = peaks(v);
      rIn.min = String(v.idle);
      rIn.max = String(v.red);
      rIn.value = String(Math.round((v.idle + v.red) / 2 / 10) * 10);
      build();
      draw();
    }
    rIn.addEventListener('input', draw);
    setVehicle(VEHICLES[0]);
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['torque-curve'] = make;
})();
