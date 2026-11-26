// The engineers' second meaning of understeer (understeer.md, Learn more box): pick a speed and a
// balance, and see the steering a car needs on one bend: the bicycle angle (wheelbase / radius)
// plus the front tyres' slip angle minus the rear's.
// Plain JS and SVG, no libraries.
// Figures: illustrative, a typical road car, not read from the simulator (the simulated cars need
// far less extra steering: docs/handling.md Balance, "Stated shortfall: linear K"):
//   wheelbase 2.5 m, bend radius 50 m
//   slip angle per axle = K_axle x sideways acceleration, linear (well below the grip limit):
//   understeer front 6 / rear 4 deg per g (3 / 2 deg at 56 km/h, the default speed),
//   neutral 5 / 5, oversteer 4 / 6
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var L = 2.5, R = 50, G = 9.81;
  var BALANCES = [
    { name: 'Front tyres roll further off (understeer)', kf: 6, kr: 4 },
    { name: 'Both the same (neutral)', kf: 5, kr: 5 },
    { name: 'Rear tyres roll further off (oversteer)', kf: 4, kr: 6 }
  ];
  var W = 420, H = 236;
  var EXAG = 5;                          // the sketch draws every angle this many times larger
  var CX = 72, FRONT_Y = 62, REAR_Y = 178; // the sketch's centre line and axles
  var BX0 = 168, BX1 = 404, BMAX = 6;    // the bars' degree scale: 0 to BMAX degrees
  var BICYCLE = Math.atan(L / R) * 180 / Math.PI;

  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function text(parent, x, y, str, extra) {
    var t = el('text', Object.assign({ x: x, y: y, 'font-size': 13, fill: 'var(--fig-ink)' }, extra || {}), parent);
    t.textContent = str;
    return t;
  }
  function bx(d) { return BX0 + (BX1 - BX0) * Math.max(0, Math.min(d, BMAX)) / BMAX; }
  // A line from (x, y) along an angle in degrees, clockwise from straight ahead (up).
  function ray(parent, x, y, angDeg, len, attrs) {
    var a = angDeg * Math.PI / 180;
    return el('line', Object.assign({ x1: x, y1: y, x2: x + len * Math.sin(a), y2: y - len * Math.cos(a) }, attrs), parent);
  }
  function wheel(parent, x, y, angDeg, attrs) {
    return el('rect', Object.assign({ x: x - 5, y: y - 15, width: 10, height: 30, rx: 3,
      transform: 'rotate(' + angDeg + ' ' + x + ' ' + y + ')' }, attrs), parent);
  }

  function make(root) {
    root.innerHTML = '';
    var svg = el('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img',
      'aria-label': 'A car seen from above turning right, its front wheel and each axle\'s direction of travel, and bars adding up the steering it needs' }, root);
    var defs = el('defs', {}, svg);
    ['orange', 'green'].forEach(function (c) {
      var m = el('marker', { id: 'sb-arrow-' + c, viewBox: '0 0 10 10', refX: 8, refY: 5,
        markerWidth: 7, markerHeight: 7, orient: 'auto-start-reverse' }, defs);
      el('path', { d: 'M0,0 L10,5 L0,10 Z', fill: 'var(--fig-' + c + ')' }, m);
    });
    var g = el('g', {}, svg);

    var controls = document.createElement('div');
    controls.className = 'w-controls';
    var uid = 'sb' + Math.random().toString(36).slice(2, 8);
    controls.innerHTML =
      '<label for="' + uid + '-speed">Speed</label>' +
      '<input id="' + uid + '-speed" type="range" min="5" max="70" step="1" value="56">' +
      '<output for="' + uid + '-speed"></output>' +
      '<label for="' + uid + '-bal">Balance</label>' +
      '<select id="' + uid + '-bal"></select><span></span>';
    root.appendChild(controls);
    var speed = controls.querySelector('input');
    var out = controls.querySelector('output');
    var select = controls.querySelector('select');
    BALANCES.forEach(function (b, i) {
      var o = document.createElement('option');
      o.value = String(i);
      o.textContent = b.name;
      select.appendChild(o);
    });

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function bar(y, label, value, colour) {
      text(g, BX0, y - 6, label + ': ' + value.toFixed(1) + '°');
      el('rect', { x: BX0, y: y, width: Math.max(0.5, bx(value) - BX0), height: 12, rx: 2, fill: colour }, g);
    }

    function update() {
      var v = parseFloat(speed.value) / 3.6;
      var b = BALANCES[parseInt(select.value, 10)];
      out.textContent = speed.value + ' km/h';
      var ayG = v * v / R / G;
      var af = b.kf * ayG, ar = b.kr * ayG;
      var steer = BICYCLE + af - ar;

      while (g.firstChild) g.removeChild(g.firstChild);

      // Sketch: a one-track car turning right, every angle drawn EXAG times larger.
      el('rect', { x: CX - 26, y: FRONT_Y - 34, width: 52, height: REAR_Y - FRONT_Y + 68, rx: 14,
        fill: 'var(--fig-fill)', stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, g);
      // front: where the bicycle angle points (ghost), where the wheel points, where it travels
      wheel(g, CX, FRONT_Y, BICYCLE * EXAG, { fill: 'none', stroke: 'var(--fig-muted)', 'stroke-width': 1.2, 'stroke-dasharray': '3 2' });
      ray(g, CX, FRONT_Y, steer * EXAG, 48, { stroke: 'var(--fig-blue)', 'stroke-width': 1.5, 'stroke-dasharray': '5 3' });
      ray(g, CX, FRONT_Y, (steer - af) * EXAG, 46, { stroke: 'var(--fig-orange)', 'stroke-width': 2.5, 'marker-end': 'url(#sb-arrow-orange)' });
      wheel(g, CX, FRONT_Y, steer * EXAG, { fill: 'var(--fig-blue)' });
      // rear: the wheel points straight ahead, and travels a little to the outside
      ray(g, CX, REAR_Y, 0, 48, { stroke: 'var(--fig-muted)', 'stroke-width': 1.5, 'stroke-dasharray': '5 3' });
      ray(g, CX, REAR_Y, -ar * EXAG, 46, { stroke: 'var(--fig-green)', 'stroke-width': 2.5, 'marker-end': 'url(#sb-arrow-green)' });
      wheel(g, CX, REAR_Y, 0, { fill: 'var(--fig-ink)' });
      text(g, CX, H - 6, 'angles drawn ' + EXAG + '× larger', { 'text-anchor': 'middle', fill: 'var(--fig-muted)' });

      // Bars: the bicycle angle, plus the front slip angle, minus the rear, gives the steering.
      bar(36, 'Steering when slow', BICYCLE, 'var(--fig-muted)');
      bar(86, '+ Front tyres roll off', af, 'var(--fig-orange)');
      bar(136, '− Rear tyres roll off', ar, 'var(--fig-green)');
      bar(186, '= Steering needed', steer, 'var(--fig-blue)');
      el('line', { x1: bx(BICYCLE), y1: 172, x2: bx(BICYCLE), y2: 206, stroke: 'var(--fig-ink)',
        'stroke-width': 1.5, 'stroke-dasharray': '3 2' }, g);

      var diff = af - ar, msg;
      if (Math.max(af, ar) < 0.1) {
        msg = 'At this speed the tyres hardly roll off, so the car goes where its front wheels point.';
      } else if (Math.abs(diff) < 0.05) {
        msg = 'Both ends roll off the same, so the driver steers just as much as when driving slowly: neutral.';
      } else if (diff > 0) {
        msg = 'The front tyres roll ' + diff.toFixed(1) + '° further off than the rear ones, so the driver steers ' +
          diff.toFixed(1) + '° more: understeer.';
      } else {
        msg = 'The rear tyres roll ' + (-diff).toFixed(1) + '° further off than the front ones, so the driver steers ' +
          (-diff).toFixed(1) + '° less: oversteer.';
      }
      readout.innerHTML = 'Steering <strong style="color:var(--fig-blue)">' + steer.toFixed(1) + '°</strong>, against ' +
        BICYCLE.toFixed(1) + '° when driven slowly. ' + msg;
    }
    speed.addEventListener('input', update);
    select.addEventListener('change', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['steer-balance'] = make;
})();
