// Brake energy: pick a vehicle, its mass, a speed and a number of stops in a row, and see the energy
// of motion (1/2 x m x v^2), how far it warms the hottest brake if all of it goes there, and where
// that temperature sits on that kind of brake's fade curve. Plain JS and SVG, no libraries.
// Figures, all read from the simulator:
//   BrakeThermal (brake_thermal.gd)  AMBIENT_C 20; fade curves (°C, factor), linear between the
//                       points, flat past them: PAD (400,1) (465,0.86) (615,0.86) (750,0.5);
//                       RACE (650,1) (850,0.7); DRUM (177,1) (316,0.8) (480,0.5); WET (90,1) (190,0.75)
//   sedan_spec.tres     mass 1150; brake_bias_front 0.873; brake_heat_capacity 4020 / _rear 2520 J/K;
//                       PAD front and rear
//   race_spec.tres      mass 900; brake_bias_front 0.621; capacity 6360 / 4770; RACE front and rear
//   garbage-truck_spec.tres  mass 8000; brake_bias_front 0.78; capacity 39300 / 39300; DRUM
//   tractor-kenney_spec.tres mass 7000; brake_bias_front 0 (the foot brake reaches the front axle
//                       through the shaft, so the rear wet discs take all of it); capacity_rear 93000
//                       (the rear axle's oil, steel in it); WET. Top speed about 43 km/h
//                       (gear-speed.js: top gear at the redline)
// Each axle's share of the energy is its share of the brake torque (brake_bias_front), split over
// its two brakes; a brake's temperature rise is its energy over its heat capacity C
// (BrakeThermal.step without the cooling term). Mass ranges past the spec's own mass are the
// widget's, for exploring.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var AMBIENT = 20;
  var CURVES = {
    pad: { name: 'pads on discs', pts: [[400, 1], [465, 0.86], [615, 0.86], [750, 0.5]] },
    race: { name: 'racing pads', pts: [[650, 1], [850, 0.7]] },
    drum: { name: 'drums', pts: [[177, 1], [316, 0.8], [480, 0.5]] },
    wet: { name: 'wet discs in oil', pts: [[90, 1], [190, 0.75]] }
  };
  var VEHICLES = [
    { id: 'sedan', icon: 'car', name: 'Saloon car', mass: 1150, mMin: 800, mMax: 2500, vMax: 200, v: 100,
      bias: 0.873, cF: 4020, cR: 2520, curve: 'pad' },
    { id: 'race', icon: 'race', name: 'Racing car', mass: 900, mMin: 700, mMax: 1500, vMax: 250, v: 150,
      bias: 0.621, cF: 6360, cR: 4770, curve: 'race' },
    { id: 'garbage', icon: 'truck', name: 'Garbage truck', mass: 8000, mMin: 6000, mMax: 26000, vMax: 90, v: 60,
      bias: 0.78, cF: 39300, cR: 39300, curve: 'drum' },
    { id: 'tractor', icon: 'tractor', name: 'Farm tractor', mass: 7000, mMin: 5000, mMax: 15000, vMax: 40, v: 40,
      bias: 0, cF: 0, cR: 93000, curve: 'wet' }
  ];
  // Plot frame (viewBox units): temperature across, braking force up.
  var X0 = 56, X1 = 404, Y0 = 186, Y1 = 22, TMAX = 900;

  function fade(pts, t) {
    if (t <= pts[0][0]) return pts[0][1];
    for (var i = 1; i < pts.length; i++) {
      if (t <= pts[i][0]) {
        var a = pts[i - 1], b = pts[i];
        return a[1] + (b[1] - a[1]) * (t - a[0]) / (b[0] - a[0]);
      }
    }
    return pts[pts.length - 1][1];
  }
  function px(t) { return X0 + (X1 - X0) * Math.min(t, TMAX) / TMAX; }
  function py(f) { return Y0 - (Y0 - Y1) * f; }
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
  function fmt(n) {
    return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }
  function energy(j) {
    return j >= 1e6 ? (j / 1e6).toFixed(1) + ' MJ' : fmt(j / 1000) + ' kJ';
  }

  function make(root) {
    root.innerHTML = '';
    var v = VEHICLES[0];
    GuideKit.vehiclePicker(root, VEHICLES.map(function (x) {
      return { id: x.id, icon: x.icon, name: x.name };
    }), v.id, function (id) {
      for (var i = 0; i < VEHICLES.length; i++) if (VEHICLES[i].id === id) setVehicle(VEHICLES[i]);
    });

    var svg = el('svg', { viewBox: '0 0 420 226', role: 'img',
      'aria-label': 'The fade curve of the chosen kind of brake, braking force against temperature, with a marker at the brake\'s temperature after the stops' }, root);
    [0.5, 1].forEach(function (f) {
      el('line', { x1: X0, y1: py(f), x2: X1, y2: py(f), stroke: 'var(--fig-grid)' }, svg);
    });
    [300, 600].forEach(function (t) {
      el('line', { x1: px(t), y1: Y1, x2: px(t), y2: Y0, stroke: 'var(--fig-grid)' }, svg);
    });
    el('path', { d: 'M' + X0 + ',' + (Y1 - 6) + ' L' + X0 + ',' + Y0 + ' L' + (X1 + 4) + ',' + Y0,
      fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    text(svg, X0 - 6, py(1) + 4, 'full', { 'text-anchor': 'end' });
    text(svg, X0 - 6, py(0.5) + 4, 'half', { 'text-anchor': 'end' });
    text(svg, X0 - 6, Y0 + 4, '0', { 'text-anchor': 'end' });
    [0, 300, 600, 900].forEach(function (t) {
      text(svg, px(t), Y0 + 18, String(t), { 'text-anchor': t === 0 ? 'start' : t === 900 ? 'end' : 'middle' });
    });
    text(svg, (X0 + X1) / 2, Y0 + 34, 'brake temperature, °C', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, 12, (Y0 + Y1) / 2, 'braking force', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600,
      transform: 'rotate(-90 12 ' + (Y0 + Y1) / 2 + ')' });
    var curve = el('polyline', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3, 'stroke-linejoin': 'round' }, svg);
    var curveLabel = text(svg, X1, py(1) - 8, '', { 'text-anchor': 'end', fill: 'var(--fig-blue)', 'font-weight': 600 });
    var steps = el('g', {}, svg);
    var guide = el('line', { y1: Y1, y2: Y0, stroke: 'var(--fig-orange)', 'stroke-width': 1.5, 'stroke-dasharray': '3 3' }, svg);
    var dot = el('circle', { r: 7, fill: 'var(--fig-orange)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);

    var uid = 'be' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-m">Mass</label><input id="' + uid + '-m" type="range" step="50">' +
      '<output for="' + uid + '-m"></output>' +
      '<label for="' + uid + '-v">Speed</label><input id="' + uid + '-v" type="range" min="10" step="5">' +
      '<output for="' + uid + '-v"></output>' +
      '<label for="' + uid + '-n">Stops in a row</label><input id="' + uid + '-n" type="range" min="1" max="10" step="1" value="1">' +
      '<output for="' + uid + '-n"></output>';
    root.appendChild(controls);
    var inputs = controls.querySelectorAll('input');
    var mIn = inputs[0], vIn = inputs[1], nIn = inputs[2];
    var outs = controls.querySelectorAll('output');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function update() {
      var c = CURVES[v.curve];
      var m = parseFloat(mIn.value), kmh = parseFloat(vIn.value), n = parseInt(nIn.value, 10);
      var ms = kmh / 3.6;
      var e = 0.5 * m * ms * ms;
      // The hotter of a front and a rear brake: each axle's share over its two brakes.
      var dF = v.cF > 0 ? e * v.bias / 2 / v.cF : 0;
      var dR = v.cR > 0 ? e * (1 - v.bias) / 2 / v.cR : 0;
      var front = dF >= dR;
      var rise = front ? dF : dR;
      var share = front ? v.bias : 1 - v.bias;
      var temp = AMBIENT + n * rise;
      var f = fade(c.pts, temp);

      outs[0].textContent = fmt(m) + ' kg';
      outs[1].textContent = kmh + ' km/h';
      outs[2].textContent = String(n);

      while (steps.firstChild) steps.removeChild(steps.firstChild);
      for (var i = 1; i < n; i++) {
        var ti = AMBIENT + i * rise;
        el('circle', { cx: px(ti), cy: py(fade(c.pts, ti)), r: 3.5, fill: 'var(--fig-orange)', opacity: 0.5 }, steps);
      }
      var x = px(temp);
      guide.setAttribute('x1', x); guide.setAttribute('x2', x);
      dot.setAttribute('cx', x); dot.setAttribute('cy', py(f));

      var which = v.cF > 0 ? (front ? 'Each front brake' : 'Each rear brake') : 'Each rear brake';
      var where = v.curve === 'wet' ? ' (the oil it sits in)' : '';
      var state;
      if (f >= 0.999) state = 'full braking force.';
      else state = Math.round(f * 100) + ' % of its braking force: the brake is fading.';
      var after = temp > TMAX ? 'over ' + TMAX + ' °C' : 'about ' + fmt(temp) + ' °C';
      readout.innerHTML =
        '<strong>Energy of motion: ½ × ' + fmt(m) + ' kg × (' + ms.toFixed(1) + ' m/s)² ≈ ' + energy(e) + '.</strong><br>' +
        'From half this speed it would be ' + energy(e / 4) + ', a quarter as much.<br>' +
        which + where + ' takes half of its axle\'s ' + Math.round(share * 100) + ' % share, about ' +
        energy(e * share / 2) + ', and warms by about ' +
        (rise < 10 ? rise.toFixed(1) : fmt(rise)) + ' °C a stop.<br>' +
        'After ' + (n === 1 ? 'one stop' : n + ' stops with no time to cool') + ': ' + after + ', ' + state;
    }
    function setVehicle(chosen) {
      v = chosen;
      var c = CURVES[v.curve];
      var pts = [[0, c.pts[0][1]]].concat(c.pts, [[TMAX, c.pts[c.pts.length - 1][1]]]);
      curve.setAttribute('points', pts.map(function (p) { return px(p[0]) + ',' + py(p[1]); }).join(' '));
      curveLabel.textContent = c.name;
      mIn.min = String(v.mMin); mIn.max = String(v.mMax); mIn.value = String(v.mass);
      vIn.max = String(v.vMax); vIn.value = String(v.v);
      update();
    }
    [mIn, vIn, nIn].forEach(function (i) { i.addEventListener('input', update); });
    setVehicle(v);
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['brake-energy'] = make;
})();
