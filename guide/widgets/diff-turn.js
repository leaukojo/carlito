// Wheels in a turn: pick a vehicle, set the turn's radius and the speed, and see the circle each
// wheel follows round the one turning centre and how fast each wheel rolls.
// Plain JS and SVG, no libraries.
// Figures, all read from the simulator's specs (GroundDriveSpec.wheel_positions: x is half the
// track, z the axle's place; max_steer_deg; driven_front / driven_rear; wheel_radius):
//   sedan_spec.tres          front and rear x 0.63, z -0.822 and 0.762 (wheelbase 1.584 m);
//                            max_steer_deg 38; front-wheel drive; wheel_radius 0.36
//   semi_spec.tres           front x 0.72, rear x 0.62, z -2.65 and 0.95 (wheelbase 3.60 m);
//                            max_steer_deg 24; rear-wheel drive; wheel_radius 0.36
//   tractor-kenney_spec.tres front x 0.782, rear x 0.896, z -1.227 and 1.353 (wheelbase 2.58 m);
//                            max_steer_deg 38; rear-wheel drive, the front axle engageable;
//                            wheel_radius 0.537, rear 0.805
// Geometry only (no tyre slip): the rear wheels roll round the turning centre on the rear axle's
// line, each front wheel round the same centre (Ackermann). A wheel's speed = the speed at the
// middle of the rear axle x its radius / the turn's radius. The tightest radius keeps the inner
// front wheel within max_steer_deg: wheelbase / tan(max) + half the front track, rounded up.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var VEHICLES = [
    { id: 'car', icon: 'car', name: 'Saloon car (front-wheel drive)', L: 1.584, tf: 1.26, tr: 1.26,
      rf: 0.36, rr: 0.36, maxSteer: 38, driven: 'front' },
    { id: 'semi', icon: 'semi', name: 'Semi truck (rear-wheel drive)', L: 3.60, tf: 1.44, tr: 1.24,
      rf: 0.36, rr: 0.36, maxSteer: 24, driven: 'rear' },
    { id: 'tractor', icon: 'tractor', name: 'Farm tractor (rear-wheel drive, front drive on demand)', L: 2.58, tf: 1.564, tr: 1.792,
      rf: 0.537, rr: 0.805, maxSteer: 38, driven: 'rear' }
  ];
  var R_MAX = 40;
  var CX = 300, RY = 196; // the middle of the rear axle, in viewBox units
  // viewBox units per metre, the same for every vehicle so their sizes compare; the turning
  // centre stays in view up to about 11 m.
  var SCALE = 26;

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
  function minRadius(v) {
    var r = v.L / Math.tan(v.maxSteer * Math.PI / 180) + v.tf / 2;
    return Math.ceil(r * 2) / 2;
  }
  function one(n) { return (Math.round(n * 10) / 10).toFixed(1); }

  function make(root) {
    root.innerHTML = '';
    GuideKit.vehiclePicker(root, VEHICLES.map(function (x) {
      return { id: x.id, icon: x.icon, name: x.name };
    }), VEHICLES[0].id, function (id) {
      for (var i = 0; i < VEHICLES.length; i++) if (VEHICLES[i].id === id) setVehicle(VEHICLES[i]);
    });

    var svg = el('svg', { viewBox: '0 0 420 250', role: 'img',
      'aria-label': 'The vehicle seen from above turning left, with the circle each wheel follows round the turning centre' }, root);
    var clipId = 'dtc' + Math.random().toString(36).slice(2, 8);
    var defs = el('defs', {}, svg);
    var clip = el('clipPath', { id: clipId }, defs);
    el('rect', { x: 0, y: 0, width: 420, height: 250 }, clip);
    var layer = el('g', { 'clip-path': 'url(#' + clipId + ')' }, svg);

    var uid = 'dt' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-r">Turn radius</label><input id="' + uid + '-r" type="range" step="0.5">' +
      '<output for="' + uid + '-r"></output>' +
      '<label for="' + uid + '-v">Speed</label><input id="' + uid + '-v" type="range" min="5" max="40" step="1" value="20">' +
      '<output for="' + uid + '-v"></output>';
    root.appendChild(controls);
    var rIn = controls.querySelectorAll('input')[0];
    var vIn = controls.querySelectorAll('input')[1];
    var outs = controls.querySelectorAll('output');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    var v;
    function draw() {
      var R = parseFloat(rIn.value);
      var kmh = parseFloat(vIn.value);
      var s = SCALE;
      var FY = RY - v.L * s;     // the front axle's line
      var cx = CX - R * s;       // the turning centre, on the rear axle's line
      while (layer.firstChild) layer.removeChild(layer.firstChild);

      // Each wheel: [x, y (viewBox), radius of its circle (m), inner?, front?]
      var wheels = [
        [CX - v.tr / 2 * s, RY, R - v.tr / 2, true, false],
        [CX + v.tr / 2 * s, RY, R + v.tr / 2, false, false],
        [CX - v.tf / 2 * s, FY, Math.sqrt(Math.pow(R - v.tf / 2, 2) + v.L * v.L), true, true],
        [CX + v.tf / 2 * s, FY, Math.sqrt(Math.pow(R + v.tf / 2, 2) + v.L * v.L), false, true]
      ];
      wheels.forEach(function (w) {
        el('circle', { cx: cx, cy: RY, r: w[2] * s, fill: 'none',
          stroke: w[3] ? 'var(--fig-blue)' : 'var(--fig-orange)', 'stroke-width': 2,
          'stroke-dasharray': w[4] ? '6 4' : 'none' }, layer);
      });
      // Lines from the turning centre to each wheel, then the body and the wheels.
      var centreSeen = cx > 8;
      if (centreSeen) {
        wheels.forEach(function (w) {
          el('line', { x1: cx, y1: RY, x2: w[0], y2: w[1], stroke: 'var(--fig-muted)', 'stroke-width': 1, 'stroke-dasharray': '2 3' }, layer);
        });
      }
      var bw = Math.max(v.tf, v.tr) * s + 6;
      el('rect', { x: CX - bw / 2, y: FY - 0.75 * s, width: bw, height: v.L * s + 1.5 * s, rx: 8,
        fill: 'var(--fig-fill)', stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, layer);
      wheels.forEach(function (w, i) {
        var rad = w[4] ? v.rf : v.rr;
        var len = 2 * rad * s, wid = Math.max(6, 0.32 * rad * s);
        var driven = v.driven === (w[4] ? 'front' : 'rear');
        var g = el('g', { transform: 'translate(' + w[0] + ' ' + w[1] + ')' }, layer);
        if (w[4]) {
          var steer = Math.atan(v.L / (w[3] ? R - v.tf / 2 : R + v.tf / 2)) * 180 / Math.PI;
          g.setAttribute('transform', 'translate(' + w[0] + ' ' + w[1] + ') rotate(' + (-steer) + ')');
        }
        el('rect', { x: -wid / 2, y: -len / 2, width: wid, height: len, rx: 2,
          fill: driven ? 'var(--fig-ink)' : 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, g);
      });
      if (centreSeen) {
        el('circle', { cx: cx, cy: RY, r: 4.5, fill: 'var(--fig-ink)' }, layer);
        text(layer, cx, RY + 20, 'turning centre', { 'text-anchor': cx < 60 ? 'start' : 'middle', fill: 'var(--fig-ink)' });
      } else {
        text(layer, 10, RY + 4, '← turning centre, ' + one(R) + ' m', { fill: 'var(--fig-ink)' });
      }
      text(layer, 412, 18, 'inner wheels', { 'text-anchor': 'end', fill: 'var(--fig-blue)', 'font-weight': 600 });
      text(layer, 412, 36, 'outer wheels', { 'text-anchor': 'end', fill: 'var(--fig-orange)', 'font-weight': 600 });
      text(layer, 412, 54, 'dashed: front', { 'text-anchor': 'end' });
      text(layer, 412, 72, 'filled: driven', { 'text-anchor': 'end' });

      outs[0].textContent = one(R) + ' m';
      outs[1].textContent = kmh + ' km/h';
      var sp = wheels.map(function (w) { return kmh * w[2] / R; });
      var dr = v.driven === 'front' ? [sp[2], sp[3], wheels[2][2], wheels[3][2], v.tf] : [sp[0], sp[1], wheels[0][2], wheels[1][2], v.tr];
      var faster = Math.round((dr[1] / dr[0] - 1) * 100);
      var frontFarther = Math.round(((wheels[2][2] + wheels[3][2]) / (wheels[0][2] + wheels[1][2]) - 1) * 100);
      readout.innerHTML = '<strong>The outer driven wheel (' + v.driven + ') rolls ' + faster + ' % faster than the inner one.</strong><br>' +
        'Rear wheels: inner ' + one(sp[0]) + ' km/h, outer ' + one(sp[1]) + ' km/h. ' +
        'Front wheels: inner ' + one(sp[2]) + ' km/h, outer ' + one(sp[3]) + ' km/h.<br>' +
        'The front wheels travel ' + (frontFarther < 1 ? 'less than 1' : frontFarther) + ' % farther than the rear ones.<br>' +
        'Joined by one solid shaft, the two driven wheels would have to scrub about ' + one(2 * Math.PI * dr[4]) +
        ' m on every full circle (2π × the ' + one(dr[4]) + ' m between them), however wide the circle.';
    }

    function setVehicle(chosen) {
      v = chosen;
      var rMin = minRadius(v);
      rIn.min = String(rMin);
      rIn.max = String(R_MAX);
      rIn.value = String(Math.max(rMin, 8));
      draw();
    }
    rIn.addEventListener('input', draw);
    vIn.addEventListener('input', draw);
    setVehicle(VEHICLES[0]);
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['diff-turn'] = make;
})();
