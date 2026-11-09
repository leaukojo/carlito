// Ackermann angles: set the bicycle (mean) steering angle and the Ackermann fraction, and see each
// front wheel's angle and where the line at right angles to it meets the rear axle. Plain JS/SVG.
// The split is the game's own law, WheelDrive.ackermann_angle:
//     tan(wheel) = tan(mean) / (1 + f * x * tan(mean) / L)    (x + = right, angle + = left)
// Geometry, from each spec's wheel_positions and steering lock:
//   sedan_spec.tres           front x +-0.63, z -0.822 / rear 0.762: L 1.584 m; max_steer_deg 38
//   tractor-kenney_spec.tres  front x +-0.782, z -1.227 / rear x +-0.896, z 1.353: L 2.580 m; 38
//   semi_spec.tres            front x +-0.72, z -2.65 / rear x +-0.62, z 0.95: L 3.60 m; 24
// Wheel radius drawn: 0.36 m (sedan, semi), 0.537 m front / 0.805 m rear (tractor).
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var BODIES = [
    { name: 'Sedan', L: 1.584, fx: 0.63, rx: 0.63, lock: 38, fr: 0.36, rr: 0.36 },
    { name: 'Tractor', L: 2.580, fx: 0.782, rx: 0.896, lock: 38, fr: 0.537, rr: 0.805 },
    { name: 'Semi tractor unit', L: 3.60, fx: 0.72, rx: 0.62, lock: 24, fr: 0.36, rr: 0.36 }
  ];
  var W = 420, H = 300;
  var CX = 96, FRONT_Y = 92, REAR_Y = 232; // the car's centre line and axle lines, viewBox units
  var LPX = REAR_Y - FRONT_Y;

  function el(name, attrs, parent) {
    var e = document.createElementNS(NS, name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function rad(d) { return d * Math.PI / 180; }
  function deg(r) { return r * 180 / Math.PI; }
  // The game's split, in its own sign convention.
  function ackermannAngle(mean, x, L, f) {
    if (f === 0 || x === 0 || L <= 0) return mean;
    var t = Math.tan(mean);
    return Math.atan(t / (1 + f * x * t / L));
  }

  function make(root) {
    root.innerHTML = '';
    var title = document.createElement('p');
    title.className = 'w-title';
    title.textContent = 'Try it: Ackermann angles';
    root.appendChild(title);

    var svg = el('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img',
      'aria-label': 'A vehicle seen from above turning right, with lines from each front wheel to the rear axle line' }, root);
    var g = el('g', {}, svg);

    var controls = document.createElement('div');
    controls.className = 'w-controls';
    var uid = 'ak' + Math.random().toString(36).slice(2, 8);
    controls.innerHTML =
      '<label for="' + uid + '-body">Vehicle</label><select id="' + uid + '-body"></select><span></span>' +
      '<label for="' + uid + '-angle">Steering</label>' +
      '<input id="' + uid + '-angle" type="range" min="0" max="38" step="0.5" value="30">' +
      '<output for="' + uid + '-angle"></output>' +
      '<label for="' + uid + '-frac">Ackermann</label>' +
      '<input id="' + uid + '-frac" type="range" min="0" max="1" step="0.05" value="1">' +
      '<output for="' + uid + '-frac"></output>';
    root.appendChild(controls);
    var bodySel = controls.querySelector('select');
    var angle = controls.querySelector('#' + uid + '-angle');
    var frac = controls.querySelector('#' + uid + '-frac');
    var outs = controls.querySelectorAll('output');
    BODIES.forEach(function (b, i) {
      var o = document.createElement('option');
      o.value = String(i);
      o.textContent = b.name;
      bodySel.appendChild(o);
    });

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);
    var note = document.createElement('p');
    note.className = 'w-note';
    note.textContent = 'Steering is the bicycle angle, up to this vehicle\'s lock. Ackermann 1 is what every vehicle in ' +
      'the game uses; 0 is LAB ▸ STEERING: PARALLEL. Drawn turning right; a left turn is the mirror image.';
    root.appendChild(note);

    function wheelRect(parent, x, y, len, wid, turnDeg, cls) {
      el('rect', { x: x - wid / 2, y: y - len / 2, width: wid, height: len, rx: Math.min(4, wid / 3),
        fill: cls || 'var(--fig-ink)', transform: 'rotate(' + turnDeg + ' ' + x + ' ' + y + ')' }, parent);
    }

    function update() {
      var b = BODIES[parseInt(bodySel.value, 10)];
      angle.max = String(b.lock);
      if (parseFloat(angle.value) > b.lock) angle.value = String(b.lock);
      var delta = parseFloat(angle.value);
      var f = parseFloat(frac.value);
      outs[0].textContent = delta.toFixed(1) + '°';
      outs[1].textContent = f === 1 ? '1 (full)' : (f === 0 ? '0 (parallel)' : f.toFixed(2));

      var s = LPX / b.L; // px per metre
      while (g.firstChild) g.removeChild(g.firstChild);

      // body and rear axle line
      var halfW = Math.max(b.fx, b.rx) + 0.18;
      el('rect', { x: CX - halfW * s, y: FRONT_Y - 0.55 * s, width: 2 * halfW * s, height: LPX + 1.1 * s,
        rx: 0.35 * s, fill: 'var(--fig-fill)', stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, g);
      el('line', { x1: CX - b.rx * s, y1: REAR_Y, x2: W, y2: REAR_Y, stroke: 'var(--fig-muted)',
        'stroke-width': 1.2, 'stroke-dasharray': '2 4' }, g);

      // the game's angles: a right turn is a negative mean in its convention
      var mean = -rad(delta);
      var inner = ackermannAngle(mean, +b.fx, b.L, f);  // right wheel is inside a right turn
      var outer = ackermannAngle(mean, -b.fx, b.L, f);
      var wheels = [
        { x: CX + b.fx * s, a: inner, colour: 'var(--fig-orange)' },
        { x: CX - b.fx * s, a: outer, colour: 'var(--fig-blue)' }
      ];
      var crossings = [];
      wheels.forEach(function (w) {
        var th = -w.a; // turned right, radians, >= 0
        if (th > 1e-4) {
          var xc = w.x + LPX / Math.tan(th);
          crossings.push(xc);
          var xEnd = Math.min(xc, W + 40);
          var yEnd = FRONT_Y + (xEnd - w.x) * Math.tan(th);
          el('line', { x1: w.x, y1: FRONT_Y, x2: xEnd, y2: yEnd, stroke: w.colour, 'stroke-width': 1.8,
            'stroke-dasharray': '6 4' }, g);
          if (xc <= W - 4) el('circle', { cx: xc, cy: REAR_Y, r: 4.5, fill: w.colour }, g);
        }
      });
      // rear wheels, then front wheels at their own angles
      wheelRect(g, CX - b.rx * s, REAR_Y, 2 * b.rr * s, Math.max(8, 0.28 * s), 0);
      wheelRect(g, CX + b.rx * s, REAR_Y, 2 * b.rr * s, Math.max(8, 0.28 * s), 0);
      wheels.forEach(function (w) {
        wheelRect(g, w.x, FRONT_Y, 2 * b.fr * s, Math.max(8, 0.24 * s), deg(-w.a));
      });

      var R = delta > 0.01 ? b.L / Math.tan(rad(delta)) : Infinity;
      var line1 = 'Inner wheel <strong style="color:var(--fig-orange)">' + deg(-inner).toFixed(1) + '°</strong>, ' +
        'outer wheel <strong style="color:var(--fig-blue)">' + deg(-outer).toFixed(1) + '°</strong>.';
      var line2;
      if (!isFinite(R)) {
        line2 = 'Straight ahead: no turn centre.';
      } else {
        line2 = 'Turn radius at the rear axle: ' + R.toFixed(2) + ' m.';
        if (crossings.length === 2) {
          var gap = Math.abs(crossings[0] - crossings[1]) / s;
          line2 += gap < 0.01
            ? ' Both lines meet at one turn centre, so neither tyre scrubs.'
            : ' The two lines cross the rear axle line ' + gap.toFixed(2) + ' m apart, so the front tyres push against each other.';
        }
        if (crossings.some(function (x) { return x > W - 4; })) line2 += ' (Some of the lines run off the drawing.)';
      }
      readout.innerHTML = line1 + '<br>' + line2;
    }
    bodySel.addEventListener('change', update);
    angle.addEventListener('input', update);
    frac.addEventListener('input', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['ackermann'] = make;
})();
