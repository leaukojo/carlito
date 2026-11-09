// Slip against grip: drag the slip and see where the tyre sits on the game's grip curve, and how
// much force one sedan tyre makes on a few kinds of ground. Plain JS and SVG, no libraries.
// Figures, all read from the game:
//   GroundDriveSpec.grip_curve  (0,0) (0.12,1) (0.4,0.9) (1,0.8), sampled linearly
//                               (VehicleSpec.sample_curve)
//   sedan_spec.tres             mass 1150 kg, mu_long 1.05 (the GroundDriveSpec default)
//   surface.gd REF_GRIP         Asphalt 1, Wet 0.55, Gravel 0.71, Grass 0.5, Snow 0.45, Ice 0.12
//                               (the all-season tyre, the sedan's stock)
(function () {
  'use strict';
  var CURVE = [[0, 0], [0.12, 1], [0.4, 0.9], [1, 0.8]];
  var PEAK = 0.12;
  var CORNER_LOAD_N = 1150 * 9.81 / 4; // a sedan corner at rest
  var MU_LONG = 1.05;
  var SURFACES = [
    ['Dry asphalt', 1.0], ['Wet road', 0.55], ['Gravel', 0.71],
    ['Grass', 0.5], ['Snow', 0.45], ['Ice', 0.12]
  ];
  var NS = 'http://www.w3.org/2000/svg';
  // Plot frame (viewBox units).
  var X0 = 52, X1 = 404, Y0 = 206, Y1 = 26;

  function sample(x) {
    if (x <= CURVE[0][0]) return CURVE[0][1];
    for (var i = 1; i < CURVE.length; i++) {
      if (x <= CURVE[i][0]) {
        var t = (x - CURVE[i - 1][0]) / (CURVE[i][0] - CURVE[i - 1][0]);
        return CURVE[i - 1][1] + (CURVE[i][1] - CURVE[i - 1][1]) * t;
      }
    }
    return CURVE[CURVE.length - 1][1];
  }
  function px(slip) { return X0 + (X1 - X0) * slip; }
  function py(grip) { return Y0 - (Y0 - Y1) * grip; }
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
  function state(slip) {
    if (slip < 0.005) return 'Rolling freely: no slip, so no force.';
    if (slip < PEAK - 0.004) return 'Gripping: more slip gives more force.';
    if (slip <= PEAK + 0.004) return 'At the peak: the most force this tyre can give. ABS and traction control hold a wheel here.';
    if (slip < 0.98) return 'Sliding: past the peak, more slip gives a little less force.';
    return 'Locked (braking) or spinning hard (driving): 0.8 of the peak.';
  }

  function make(root) {
    root.innerHTML = '';
    root.classList.add('widget-slip-grip');
    var title = document.createElement('p');
    title.className = 'w-title';
    title.textContent = 'Try it: slip against grip';
    root.appendChild(title);

    var svg = el('svg', { viewBox: '0 0 420 244', role: 'img', 'aria-label': 'The grip curve with a marker at the chosen slip' }, root);
    // grid and axes
    [0.5, 1].forEach(function (g) {
      el('line', { x1: X0, y1: py(g), x2: X1, y2: py(g), stroke: 'var(--fig-grid)' }, svg);
    });
    el('line', { x1: px(PEAK), y1: Y1, x2: px(PEAK), y2: Y0, stroke: 'var(--fig-grid)' }, svg);
    el('path', { d: 'M' + X0 + ',' + (Y1 - 6) + ' L' + X0 + ',' + Y0 + ' L' + (X1 + 4) + ',' + Y0, fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    text(svg, X0 - 6, py(1) + 4, 'full', { 'text-anchor': 'end' });
    text(svg, X0 - 6, py(0.5) + 4, 'half', { 'text-anchor': 'end' });
    text(svg, X0 - 6, Y0 + 4, '0', { 'text-anchor': 'end' });
    text(svg, X0, Y0 + 18, '0', { 'text-anchor': 'middle' });
    text(svg, px(PEAK), Y0 + 18, '0.12', { 'text-anchor': 'middle' });
    text(svg, px(0.4), Y0 + 18, '0.4', { 'text-anchor': 'middle' });
    text(svg, X1, Y0 + 18, '1', { 'text-anchor': 'end' });
    text(svg, (X0 + X1) / 2, Y0 + 34, 'slip', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, 12, (Y0 + Y1) / 2, 'grip', { 'text-anchor': 'middle', fill: 'var(--fig-ink)', 'font-weight': 600,
      transform: 'rotate(-90 12 ' + (Y0 + Y1) / 2 + ')' });

    // dry curve as a dashed reference, live curve on top
    var pts = function (scale) {
      return CURVE.map(function (p) { return px(p[0]) + ',' + py(p[1] * scale); }).join(' ');
    };
    var dry = el('polyline', { points: pts(1), fill: 'none', stroke: 'var(--fig-muted)', 'stroke-width': 1.5, 'stroke-dasharray': '5 4' }, svg);
    var live = el('polyline', { points: pts(1), fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 3.5, 'stroke-linejoin': 'round' }, svg);
    var guide = el('line', { y1: Y1, y2: Y0, stroke: 'var(--fig-orange)', 'stroke-width': 1.5, 'stroke-dasharray': '3 3' }, svg);
    var dot = el('circle', { r: 7, fill: 'var(--fig-orange)', stroke: 'var(--surface)', 'stroke-width': 2 }, svg);
    var dryLabel = text(svg, X1, py(0.8) - 8, 'dry asphalt', { 'text-anchor': 'end' });

    // controls
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    var uid = 'sg' + Math.random().toString(36).slice(2, 8);
    controls.innerHTML =
      '<label for="' + uid + '-slip">Slip</label>' +
      '<input id="' + uid + '-slip" type="range" min="0" max="1" step="0.005" value="0.06">' +
      '<output for="' + uid + '-slip"></output>' +
      '<label for="' + uid + '-surf">Ground</label>' +
      '<select id="' + uid + '-surf"></select><span></span>';
    root.appendChild(controls);
    var slider = controls.querySelector('input');
    var out = controls.querySelector('output');
    var select = controls.querySelector('select');
    SURFACES.forEach(function (s, i) {
      var o = document.createElement('option');
      o.value = String(i);
      o.textContent = s[0];
      select.appendChild(o);
    });

    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);
    var note = document.createElement('p');
    note.className = 'w-note';
    note.textContent = 'The same curve serves braking and driving: slip here is its size, whichever way the tyre slips. ' +
      'The force is for one tyre of the sedan, standing at its share of the car\'s weight, on its stock all-season tyres.';
    root.appendChild(note);

    function update() {
      var slip = parseFloat(slider.value);
      var surf = SURFACES[parseInt(select.value, 10)];
      var g = sample(slip);
      live.setAttribute('points', pts(surf[1]));
      dry.style.display = surf[1] < 1 ? '' : 'none';
      dryLabel.style.display = surf[1] < 1 ? '' : 'none';
      var x = px(slip), y = py(g * surf[1]);
      guide.setAttribute('x1', x); guide.setAttribute('x2', x);
      dot.setAttribute('cx', x); dot.setAttribute('cy', y);
      out.textContent = slip.toFixed(3);
      var force = MU_LONG * surf[1] * g * CORNER_LOAD_N;
      var peakForce = MU_LONG * surf[1] * CORNER_LOAD_N;
      readout.innerHTML = '<strong>' + state(slip) + '</strong><br>' +
        'Grip: ' + Math.round(g * 100) + ' % of this ground\'s peak. ' +
        'Force from one tyre: about ' + (Math.round(force / 10) * 10) + ' N of a possible ' +
        (Math.round(peakForce / 10) * 10) + ' N.';
    }
    slider.addEventListener('input', update);
    select.addEventListener('change', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['slip-grip'] = make;
})();
