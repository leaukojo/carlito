// An odometer that counts wheel turns: choose the tyre fitted and how much the wheel spins, and see
// how far the odometer thinks the car has gone over 100 m of road. Plain JS and SVG, no libraries.
// Figures:
//   sedan_spec.tres  wheel_radius 0.36 m: the tyre the odometer is set for, 72 cm across
//                    (2.26 m per turn).
// Distance per counted turn = pi x the set-for diameter; turns over a distance d =
// d x (1 + slip) / (pi x the fitted diameter), slip being the slip ratio while driving.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var REF_D = 0.72;            // m, the tyre the odometer is set for
  var ROAD = 100;              // m of road driven
  var SCALE_MAX = 150;         // m at the right end of the bars
  var BX0 = 140, BX1 = 404;    // bar span
  var ROAD_Y = 40, ODO_Y = 128, BAR_H = 18;
  var GROUND_Y = 156, WHEEL_X = 66, PX_PER_M = 100; // the wheels drawn at 100 units per metre

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
  function bx(m) { return BX0 + (BX1 - BX0) * m / SCALE_MAX; }

  function make(root) {
    root.innerHTML = '';
    var svg = el('svg', { viewBox: '0 0 420 200', role: 'img',
      'aria-label': 'The fitted tyre beside the tyre the odometer is set for, and two bars: the 100 m of road driven, and the distance the odometer counts from the same wheel turns' }, root);

    // The wheels: the set-for tyre dashed, the fitted tyre solid, both standing on the road.
    el('line', { x1: 12, y1: GROUND_Y, x2: 122, y2: GROUND_Y, stroke: 'var(--fig-ink)', 'stroke-width': 1.5 }, svg);
    var refR = REF_D / 2 * PX_PER_M;
    el('circle', { cx: WHEEL_X, cy: GROUND_Y - refR, r: refR, fill: 'none', stroke: 'var(--fig-muted)',
      'stroke-width': 1.5, 'stroke-dasharray': '4 3' }, svg);
    var tyre = el('circle', { cx: WHEEL_X, fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 7 }, svg);
    var rim = el('circle', { cx: WHEEL_X, fill: 'var(--fig-fill)', stroke: 'var(--fig-muted)', 'stroke-width': 1 }, svg);
    var hub = el('circle', { cx: WHEEL_X, r: 3, fill: 'var(--fig-muted)' }, svg);
    var sizeLabel = text(svg, WHEEL_X, GROUND_Y + 18, '', { 'text-anchor': 'middle', fill: 'var(--fig-ink)' });
    text(svg, WHEEL_X, GROUND_Y + 34, 'dashed: set for 72 cm', { 'text-anchor': 'middle', 'font-size': 12 });

    // The bars.
    text(svg, BX0, ROAD_Y - 8, 'Road driven', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    text(svg, BX0, ODO_Y - 8, 'What the odometer counts', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    [0, 50, 100, 150].forEach(function (m) {
      el('line', { x1: bx(m), y1: ROAD_Y - 2, x2: bx(m), y2: ODO_Y + BAR_H + 4, stroke: 'var(--fig-grid)' }, svg);
      text(svg, bx(m), ODO_Y + BAR_H + 18, m + ' m', { 'text-anchor': m === 0 ? 'start' : m === 150 ? 'end' : 'middle', 'font-size': 12 });
    });
    el('rect', { x: bx(0), y: ROAD_Y, width: bx(ROAD) - bx(0), height: BAR_H, fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)', 'stroke-width': 1 }, svg);
    var odoBar = el('rect', { x: bx(0), y: ODO_Y, height: BAR_H, fill: 'var(--fig-fill)', stroke: 'var(--fig-blue)', 'stroke-width': 1.5 }, svg);
    var roadTicks = el('path', { fill: 'none', stroke: 'var(--fig-ink)', 'stroke-width': 0.75 }, svg);
    var odoTicks = el('path', { fill: 'none', stroke: 'var(--fig-blue)', 'stroke-width': 0.75 }, svg);
    var odoLabel = text(svg, 0, ODO_Y + 13, '', { fill: 'var(--fig-blue)', 'font-weight': 600 });
    text(svg, bx(ROAD) + 6, ROAD_Y + 13, '100 m', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    var turnsLabel = text(svg, bx(ROAD / 2), ROAD_Y + BAR_H + 30, '', { 'text-anchor': 'middle' });

    var uid = 'od' + Math.random().toString(36).slice(2, 8);
    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-d">Tyre fitted</label><input id="' + uid + '-d" type="range" min="64" max="80" step="1" value="72">' +
      '<output for="' + uid + '-d"></output>' +
      '<label for="' + uid + '-s">Wheelspin</label><input id="' + uid + '-s" type="range" min="0" max="30" step="1" value="0">' +
      '<output for="' + uid + '-s"></output>';
    root.appendChild(controls);
    var dIn = controls.querySelectorAll('input')[0];
    var sIn = controls.querySelectorAll('input')[1];
    var outs = controls.querySelectorAll('output');
    var readout = document.createElement('div');
    readout.className = 'w-readout';
    readout.setAttribute('aria-live', 'polite');
    root.appendChild(readout);

    function ticks(step, count, y) {
      var d = '';
      for (var i = 1; i <= count; i++) {
        var x = bx(step * i);
        d += 'M' + x.toFixed(1) + ',' + (y + 4) + 'V' + (y + BAR_H - 4);
      }
      return d;
    }
    function update() {
      var dia = parseFloat(dIn.value) / 100;
      var slip = parseFloat(sIn.value) / 100;
      var r = dia / 2 * PX_PER_M;
      tyre.setAttribute('cy', GROUND_Y - r); tyre.setAttribute('r', r - 3.5);
      rim.setAttribute('cy', GROUND_Y - r); rim.setAttribute('r', r * 0.62);
      hub.setAttribute('cy', GROUND_Y - r);
      sizeLabel.textContent = Math.round(dia * 100) + ' cm across';
      outs[0].textContent = Math.round(dia * 100) + ' cm';
      outs[1].textContent = Math.round(slip * 100) + ' %';

      var perTurnFit = Math.PI * dia;            // road covered by one turn, rolling freely
      var perTurnRef = Math.PI * REF_D;          // what the odometer adds per turn
      var turns = ROAD * (1 + slip) / perTurnFit;
      var reading = turns * perTurnRef;
      var whole = Math.floor(turns);
      roadTicks.setAttribute('d', ticks(ROAD / turns, whole, ROAD_Y));
      odoTicks.setAttribute('d', ticks(perTurnRef, whole, ODO_Y));
      odoBar.setAttribute('width', bx(reading) - bx(0));
      odoLabel.setAttribute('x', bx(Math.min(reading, SCALE_MAX)) + (reading > 135 ? -6 : 6));
      odoLabel.setAttribute('text-anchor', reading > 135 ? 'end' : 'start');
      odoLabel.textContent = Math.round(reading) + ' m';
      turnsLabel.textContent = 'the same ' + Math.round(turns) + ' turns of the wheel';

      var err = reading / ROAD - 1;
      var errText = Math.abs(err) < 0.005 ? 'exactly right'
        : Math.round(Math.abs(err) * 100) + ' % too ' + (err > 0 ? 'far' : 'short');
      readout.innerHTML = '<strong>The odometer reads ' + Math.round(reading) + ' m for 100 m of road: ' + errText + '.</strong><br>' +
        'One turn of this tyre covers ' + perTurnFit.toFixed(2) + ' m' + (slip > 0 ? ' when it rolls freely' : '') +
        ', but the odometer adds ' + perTurnRef.toFixed(2) + ' m for every turn. ' +
        'At a true 100 km/h, a speedometer counting the same turns would show ' + Math.round(100 * reading / ROAD) + ' km/h.';
    }
    dIn.addEventListener('input', update);
    sIn.addEventListener('input', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['odometer'] = make;
})();
