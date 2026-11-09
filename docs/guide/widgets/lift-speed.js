// Lift against speed: the plane's lift law, with sliders for speed, angle of attack and flaps, set
// against its weight. Plain JS and SVG, no libraries.
// Figures, all read from the game:
//   plane.gd       lift_coeff 13 N per (m/s)^2, flap_lift_bonus 4 at full flaps, lift_cap 16000 N,
//                  aoa_lift_slope 5.7 per rad, aoa_lift_max 1.8 (aoa_factor clamps 1 + slope x aoa
//                  to [0, 1.8]), stall_speed 13 m/s, full_lift_speed 20 m/s (lift_frac: smoothstep
//                  between them), max_thrust 9000 N, drag_coeff 350 N per m/s
//   plane_spec.tres mass 800 kg
// lift = min(coeff x aoa_factor x v^2, cap) x lift_frac(v)  (PlaneVehicle.lift_force)
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var LIFT_COEFF = 13, FLAP_BONUS = 4, CAP = 16000, SLOPE = 5.7, AOA_MAX = 1.8;
  var STALL = 13, FULL = 20, MASS = 800, G = 9.81;
  var WEIGHT = MASS * G;
  var VMAX = 35, FMAX = 18000;
  var X0 = 62, X1 = 404, Y0 = 210, Y1 = 22;

  function liftFrac(v) {
    var t = Math.min(Math.max((v - STALL) / (FULL - STALL), 0), 1);
    return t * t * (3 - 2 * t);
  }
  function aoaFactor(aoaDeg) {
    return Math.min(Math.max(1 + SLOPE * aoaDeg * Math.PI / 180, 0), AOA_MAX);
  }
  function lift(v, aoaDeg, flaps) {
    var coeff = (LIFT_COEFF + FLAP_BONUS * flaps) * aoaFactor(aoaDeg);
    return Math.min(coeff * v * v, CAP) * liftFrac(v);
  }
  function px(v) { return X0 + (X1 - X0) * v / VMAX; }
  function py(f) { return Y0 - (Y0 - Y1) * f / FMAX; }
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

  function make(root) {
    root.innerHTML = '';
    var title = document.createElement('p');
    title.className = 'w-title';
    title.textContent = 'Try it: lift against speed';
    root.appendChild(title);

    var svg = el('svg', { viewBox: '0 0 420 252', role: 'img', 'aria-label': 'The plane\'s lift against airspeed, with its weight as a line and a marker at the chosen speed' }, root);
    el('rect', { x: X0, y: Y1, width: px(STALL) - X0, height: Y0 - Y1, fill: 'var(--fig-fill)' }, svg);
    text(svg, (X0 + px(STALL)) / 2, Y1 + 16, 'no lift', { 'text-anchor': 'middle' });
    [5000, 10000, 15000].forEach(function (f) {
      el('line', { x1: X0, y1: py(f), x2: X1, y2: py(f), stroke: 'var(--fig-grid)' }, svg);
      text(svg, X0 - 6, py(f) + 4, String(f / 1000) + 'k', { 'text-anchor': 'end' });
    });
    text(svg, X0 - 6, Y0 + 4, '0', { 'text-anchor': 'end' });
    [0, 10, 20, 30].forEach(function (v) {
      text(svg, px(v), Y0 + 18, String(v), { 'text-anchor': 'middle' });
    });
    el('path', { d: 'M' + X0 + ',' + (Y1 - 6) + ' L' + X0 + ',' + Y0 + ' L' + (X1 + 4) + ',' + Y0, fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    text(svg, (X0 + X1) / 2, Y0 + 36, 'airspeed, m/s', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, 14, (Y0 + Y1) / 2, 'force, N', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600,
      transform: 'rotate(-90 14 ' + (Y0 + Y1) / 2 + ')' });
    el('line', { x1: X0, y1: py(WEIGHT), x2: X1, y2: py(WEIGHT), stroke: 'var(--fig-orange)', 'stroke-width': 2, 'stroke-dasharray': '6 4' }, svg);
    text(svg, X1, py(WEIGHT) - 6, 'weight', { 'text-anchor': 'end', fill: 'var(--fig-orange)', 'font-weight': 600 });
    var curve = el('polyline', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3.5, 'stroke-linejoin': 'round' }, svg);
    var guide = el('line', { y1: Y1, y2: Y0, stroke: 'var(--fig-ink)', 'stroke-width': 1, 'stroke-dasharray': '3 3' }, svg);
    var dot = el('circle', { r: 7, fill: 'var(--fig-blue)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);

    var uid = 'ls' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-v">Airspeed</label><input id="' + uid + '-v" type="range" min="0" max="35" step="0.5" value="22">' +
      '<output for="' + uid + '-v"></output>' +
      '<label for="' + uid + '-a">Nose above flight path</label><input id="' + uid + '-a" type="range" min="-10" max="15" step="0.5" value="0">' +
      '<output for="' + uid + '-a"></output>' +
      '<label for="' + uid + '-f">Flaps</label><input id="' + uid + '-f" type="range" min="0" max="1" step="0.25" value="0">' +
      '<output for="' + uid + '-f"></output>';
    root.appendChild(controls);
    var ins = controls.querySelectorAll('input');
    var outs = controls.querySelectorAll('output');

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);
    var note = document.createElement('p');
    note.className = 'w-note';
    note.textContent = 'The game\'s lift law for its 800 kg plane. Lift fades to nothing between 20 and 13 m/s, the stall, ' +
      'and stops growing with angle at about 8°. It is capped at about twice the weight.';
    root.appendChild(note);

    function update() {
      var v = parseFloat(ins[0].value), aoa = parseFloat(ins[1].value), flaps = parseFloat(ins[2].value);
      var pts = [];
      for (var s = 0; s <= VMAX; s += 0.5) pts.push(px(s) + ',' + py(Math.min(lift(s, aoa, flaps), FMAX)));
      curve.setAttribute('points', pts.join(' '));
      var L = lift(v, aoa, flaps);
      guide.setAttribute('x1', px(v)); guide.setAttribute('x2', px(v));
      dot.setAttribute('cx', px(v)); dot.setAttribute('cy', py(Math.min(L, FMAX)));
      outs[0].textContent = v.toFixed(1) + ' m/s';
      outs[1].textContent = aoa.toFixed(1) + '°';
      outs[2].textContent = Math.round(flaps * 100) + ' %';
      var ratio = L / WEIGHT;
      var verdict;
      if (v <= STALL) verdict = 'Stalled: below 13 m/s the wing gives no lift at all, and the nose drops.';
      else if (ratio > 1.05) verdict = 'Lift is more than the weight: the plane climbs.';
      else if (ratio >= 0.95) verdict = 'Lift about equals the weight: the plane holds its height.';
      else verdict = 'Lift is less than the weight: the plane sinks.';
      readout.innerHTML = '<strong>' + verdict + '</strong><br>Lift about ' + (Math.round(L / 100) * 100) +
        ' N against a weight of about ' + (Math.round(WEIGHT / 100) * 100) + ' N (' + Math.round(ratio * 100) + ' %). ' +
        'That is ' + Math.round(v * 3.6) + ' km/h.';
    }
    ins.forEach(function (i) { i.addEventListener('input', update); });
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['lift-speed'] = make;
})();
