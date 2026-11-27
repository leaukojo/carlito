// Swinging front axle: raise a bump under one front wheel of a tractor and compare an axle that
// swings on a centre pivot with one fixed to the body. Seen from the front. Plain JS and SVG.
// Figures: front_axle_swing_deg 10 (TRACTOR_BASE in tools/gen_kenney_vehicles.gd), the stop.
// Drawing only, not the simulator: the axle's width (1.8 m between the wheels) and the sizes of
// the parts; the body is held level by the rear axle on flat ground, and the tyres do not squash.
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var STOP_DEG = 10;
  var PX_CM = 1.5;                    // 1.8 m between the wheels is 270 px
  var MAX_CM = 40;
  var GROUND = 240, LX = 75, RX = 345, W = RX - LX;
  var TYRE_W = 16, TYRE_R = 40;       // front tyre: half-width, radius
  var STOP_DX = 52;                   // the stops either side of the pivot

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
    root.classList.add('widget-swing-axle');
    var uid = 'sw' + Math.random().toString(36).slice(2, 8);
    var svg = el('svg', { viewBox: '0 0 420 ' + (GROUND + 8), role: 'img' }, root);

    var state = text(svg, 20, 20, '', { fill: 'var(--fig-ink)', 'font-weight': 600 });
    var sub = text(svg, 20, 38, '');

    el('line', { x1: 20, y1: GROUND, x2: 400, y2: GROUND, stroke: 'var(--fig-grid)', 'stroke-width': 6 }, svg);
    var bump = el('rect', { rx: 8, fill: 'var(--fig-grid)', stroke: 'var(--fig-muted)', 'stroke-width': 1.5 }, svg);
    // The tractor's front, seen from the front: bonnet, grille, and the two stops under it.
    var body = el('g', {}, svg);
    el('rect', { x: 150, y: -96, width: 120, height: 84, rx: 8, fill: 'var(--fig-fill)', stroke: 'var(--fig-ink)',
      'stroke-width': 2 }, body);
    for (var i = 0; i < 5; i++) {
      el('line', { x1: 166, y1: -80 + i * 12, x2: 254, y2: -80 + i * 12, stroke: 'var(--fig-muted)', 'stroke-width': 2 }, body);
    }
    el('line', { x1: 210, y1: -12, x2: 210, y2: 0, stroke: 'var(--fig-ink)', 'stroke-width': 6 }, body);
    [-STOP_DX, STOP_DX].forEach(function (dx) {
      el('rect', { x: 210 + dx - 7, y: -18, width: 14, height: 9, fill: 'var(--fig-muted)', stroke: 'var(--fig-ink)',
        'stroke-width': 1.5 }, body);
    });
    var tyres = [0, 1].map(function () {
      return el('rect', { width: 2 * TYRE_W, height: 2 * TYRE_R, rx: 10, fill: 'var(--fig-ink)' }, svg);
    });
    var beam = el('line', { stroke: 'var(--fig-orange)', 'stroke-width': 9, 'stroke-linecap': 'round' }, svg);
    var pivot = el('circle', { r: 6, fill: 'var(--surface)', stroke: 'var(--fig-ink)', 'stroke-width': 2 }, svg);
    var bolt = el('rect', { width: 12, height: 12, fill: 'var(--fig-ink)' }, svg);
    var gapLabel = text(svg, RX - TYRE_W - 8, 0, 'in the air', { 'text-anchor': 'end', fill: 'var(--fig-red)', 'font-weight': 600 });

    var controls = document.createElement('div');
    controls.className = 'w-controls';
    controls.innerHTML =
      '<label for="' + uid + '-k">Front axle</label>' +
      '<select id="' + uid + '-k"><option value="swing">swinging on a pivot</option>' +
      '<option value="fixed">fixed to the body</option></select><span></span>' +
      '<label for="' + uid + '-b">Bump under the left wheel</label>' +
      '<input id="' + uid + '-b" type="range" min="0" max="' + MAX_CM + '" step="1" value="15">' +
      '<output for="' + uid + '-b" aria-live="polite"></output>';
    root.appendChild(controls);
    var kind = controls.querySelector('select');
    var input = controls.querySelector('input');
    var out = controls.querySelector('output');

    function update() {
      var swing = kind.value === 'swing';
      var cm = parseFloat(input.value), b = cm * PX_CM;
      var stop = swing ? STOP_DEG * Math.PI / 180 : 0;
      // The beam tilts until both wheels touch, or until its stop; past that the right wheel lifts.
      var tilt = Math.min(Math.atan(b / W), stop);
      var lHub = GROUND - b - TYRE_R;
      var rHub = lHub + W * Math.tan(tilt);
      var gap = (GROUND - TYRE_R) - rHub;
      var mid = [(LX + RX) / 2, (lHub + rHub) / 2];

      bump.setAttribute('x', LX - 34); bump.setAttribute('width', 68);
      bump.setAttribute('y', GROUND - b); bump.setAttribute('height', b);
      bump.style.display = b > 0 ? '' : 'none';
      tyres[0].setAttribute('x', LX - TYRE_W); tyres[0].setAttribute('y', lHub - TYRE_R);
      tyres[1].setAttribute('x', RX - TYRE_W); tyres[1].setAttribute('y', rHub - TYRE_R);
      beam.setAttribute('x1', LX); beam.setAttribute('y1', lHub);
      beam.setAttribute('x2', RX); beam.setAttribute('y2', rHub);
      // The body rides on the pivot and stays level: the rear axle holds it.
      body.setAttribute('transform', 'translate(0,' + mid[1] + ')');
      pivot.setAttribute('cx', mid[0]); pivot.setAttribute('cy', mid[1]);
      pivot.style.display = swing ? '' : 'none';
      bolt.setAttribute('x', mid[0] - 6); bolt.setAttribute('y', mid[1] - 6);
      bolt.style.display = swing ? 'none' : '';
      var lifted = gap > 0.5;
      gapLabel.style.display = lifted ? '' : 'none';
      gapLabel.setAttribute('y', GROUND - 8);

      out.textContent = cm + ' cm';
      var deg = Math.round(tilt * 180 / Math.PI);
      if (!swing) {
        state.textContent = lifted ? 'the right wheel hangs in the air' : 'both wheels on the ground';
        sub.textContent = lifted ? 'it carries nothing, so it cannot grip or steer' : 'flat ground: no problem yet';
      } else if (!lifted) {
        state.textContent = 'both wheels on the ground';
        sub.textContent = deg === 0 ? 'flat ground' : 'the axle tilts ' + deg + '° on its pivot; the body stays level';
      } else {
        state.textContent = 'the axle is on its stop: the right wheel lifts';
        sub.textContent = 'it can tilt only ' + STOP_DEG + '° each way';
      }
      svg.setAttribute('aria-label', 'A tractor\'s front axle seen from the front: ' + state.textContent);
    }
    kind.addEventListener('change', update);
    input.addEventListener('input', update);
    update();
  }

  window.GuideWidgets = window.GuideWidgets || {};
  window.GuideWidgets['swing-axle'] = make;
})();
